# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Deterministic strand-hair reference scenes and their coverage metrics.

The scenes are procedural, so they add no reference data. Each one makes
one requirement of the strand path measurable:

- `add_fine_silhouettes` draws long straight fibers of one width and one
  opacity. Draw it once with `STRAND_LINE_COVERAGE` and once, at a higher
  resolution, with `SOLID_LINE_COVERAGE`. Then `coverage_samples`,
  `supersampled_coverage` and the two error functions compare the
  stochastic coverage with that supersampled ground truth.
- `add_crossing_strands` draws two layers of fibers at distinct depths.
  Reversed submission must give the same image. Where the layers overlap,
  the visible fractions must match alpha compositing.
- `HairReferenceRig` hangs a curtain of long guide and follower strands in
  rows at increasing depth. It gives the self-shadow, backlight and moving
  long-hair scenes, and a receiver plane for the cast shadow.

Each scene uses an orthographic camera on +z, so one pixel has a known
size in meters. The tests, the GPU parity fixtures and the reference image
use these same builders.

This is not a three.js port. See Strand hair rendering.
"""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.hair.collider import HairCollider
from extensions.humanoid.skeleton.head.hair.density import HairDensity
from extensions.humanoid.skeleton.head.hair.groom import (
    HairGroom,
    follower_across,
)
from extensions.humanoid.skeleton.head.hair.shading import (
    HairLight,
    HairLook,
    shade_groom_into,
)
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairSimulation,
    HairWind,
)
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    add_strands,
)
from geometries.plane import plane
from lights.light import directional_light
from materials.material import (
    DOUBLE_SIDE,
    LineWidth,
    Material,
    OPAQUE,
    line_material,
)
from math.vector3 import Vector3
from objects.line_segments2 import (
    LineCoverage,
    LineSegments2,
    line_segments_geometry,
)
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from std.math import abs, isfinite, max, min
from units.si import Length, METER

# The fibers of the two flat scenes reach past the view on both sides, so
# no cap is inside the image.
comptime _REACH = Float32(1.6)
comptime REFERENCE_BACKGROUND = Color(0, 0, 0)
comptime FRONT_COLOR = Color(255, 0, 0)
comptime BACK_COLOR = Color(0, 0, 255)
comptime FIBER_COLOR = Color(150, 95, 50)


def reference_camera(view: Length) raises -> OrthographicCamera:
    """Return the reference camera: a square view from four meters on +z.

    Args:
        view: The height and the width of the visible square.

    Returns:
        The camera, aimed at the origin.

    Raises:
        Error: If the view is not positive.
    """
    var camera = centered(view, 1, Length(0.1, METER), Length(10, METER))
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _strand(
    mut scene: Scene,
    mut assets: Assets,
    points: List[Vector3],
    color: Color,
    width: Length,
    opacity: Float32,
    coverage: LineCoverage,
) raises:
    """Attach one wide-line draw with its own node, geometry and material."""
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(line_segments_geometry(points))
    var material = assets.materials.add(
        line_material(
            color,
            LineWidth(world=width),
            opacity=opacity,
            blending=OPAQUE,
        )
    )
    scene.add_wide_line(
        LineSegments2(
            geometry, material, node, coverage=coverage, cast_shadow=True
        )
    )


def add_fine_silhouettes(
    mut scene: Scene,
    mut assets: Assets,
    count: Int,
    width: Length,
    opacity: Float32,
    coverage: LineCoverage,
    reverse: Bool = False,
) raises:
    """Add `count` long, slightly tilted fibers as one draw.

    The fibers are spread evenly over the middle 1.6 meters of the view.
    Each one falls 0.1 meters over its length, so its edges cross every
    pixel phase. A width in meters keeps the projected area the same at
    every image size. That is what lets a supersampled image be the
    ground truth.

    Args:
        scene: The scene that receives the draw.
        assets: The store for its geometry and material.
        count: How many fibers, one or more.
        width: The fiber width.
        opacity: The strand opacity, zero through one.
        coverage: The coverage rule of the draw.
        reverse: Give the fibers in reverse order.

    Raises:
        Error: If the count is less than one, or the width, opacity or
            coverage is refused.
    """
    if count < 1:
        raise Error("A reference scene needs at least one fiber")
    var points = List[Vector3]()
    for index in range(count):  # pragma: no branch
        var fiber = count - 1 - index if reverse else index
        var y = Float32(-0.8) + Float32(1.6) * (Float32(fiber) + 0.5) / Float32(
            count
        )
        points.append(Vector3(-_REACH, y - 0.05, 0))
        points.append(Vector3(_REACH, y + 0.05, 0))
    _strand(scene, assets, points, FIBER_COLOR, width, opacity, coverage)


def _layer(count: Int, vertical: Bool, z: Float32) -> List[Vector3]:
    """Return `count` parallel fibers over the middle 1.2 meters."""
    var points = List[Vector3]()
    for index in range(count):  # pragma: no branch
        var at = Float32(0)
        if count > 1:
            at = Float32(-0.6) + Float32(1.2) * Float32(index) / Float32(
                count - 1
            )
        if vertical:
            points.append(Vector3(at, -_REACH, z))
            points.append(Vector3(at, _REACH, z))
        else:
            points.append(Vector3(-_REACH, at, z))
            points.append(Vector3(_REACH, at, z))
    return points^


def add_crossing_strands(
    mut scene: Scene,
    mut assets: Assets,
    count: Int,
    width: Length,
    front_opacity: Float32,
    back_opacity: Float32,
    coverage: LineCoverage,
    reverse: Bool = False,
) raises:
    """Add two crossing layers of fibers at distinct depths.

    The front layer is `FRONT_COLOR` and horizontal, 0.2 meters toward the
    camera. The back layer is `BACK_COLOR` and vertical, 0.2 meters away.
    Each layer is one draw. One fiber in each layer sits on the axis, so
    a wide fiber pair gives a square overlap at the center.

    Args:
        scene: The scene that receives the two draws.
        assets: The store for their geometries and materials.
        count: How many fibers in each layer, one or more.
        width: The fiber width.
        front_opacity: The front layer's opacity.
        back_opacity: The back layer's opacity.
        coverage: The coverage rule of both draws.
        reverse: Submit the back layer first.

    Raises:
        Error: If the count is less than one, or a width, opacity or
            coverage is refused.
    """
    if count < 1:
        raise Error("A reference scene needs at least one fiber")
    for order in range(2):  # pragma: no branch
        var front = (order == 1) if reverse else (order == 0)
        if front:
            _strand(
                scene,
                assets,
                _layer(count, False, 0.2),
                FRONT_COLOR,
                width,
                front_opacity,
                coverage,
            )
        else:
            _strand(
                scene,
                assets,
                _layer(count, True, -0.2),
                BACK_COLOR,
                width,
                back_opacity,
                coverage,
            )


def _rgb(color: Color) -> Int:
    """Pack a color's three channels into one integer, alpha ignored."""
    return (Int(color.r) << 16) | (Int(color.g) << 8) | Int(color.b)


def coverage_samples(
    image: Framebuffer, background: Color
) raises -> List[Float32]:
    """Return one where a pixel differs from the background, else zero.

    Args:
        image: A rendered image.
        background: The color it was cleared to.

    Returns:
        One value for each pixel, row by row.

    Raises:
        Error: If the image cannot be read.
    """
    var samples = List[Float32](capacity=image.width * image.height)
    for y in range(image.height):  # pragma: no branch
        for x in range(image.width):  # pragma: no branch
            var p = image.get_pixel(x, y)
            var differs = _rgb(p) != _rgb(background)
            samples.append(Float32(1) if differs else Float32(0))
    return samples^


def supersampled_coverage(
    image: Framebuffer, factor: Int, background: Color, opacity: Float32
) raises -> List[Float32]:
    """Return the ground-truth coverage of each pixel of a smaller image.

    Each pixel of the smaller image covers `factor` by `factor` pixels of
    `image`. Its coverage is the fraction of those that differ from the
    background, times `opacity`. This is alpha coverage with a box filter.

    Args:
        image: A solid-coverage image, `factor` times the size.
        factor: How many pixels of `image` span one smaller pixel.
        background: The color `image` was cleared to.
        opacity: The opacity of the strands it shows.

    Returns:
        One value for each smaller pixel, row by row.

    Raises:
        Error: If the factor is less than one or does not divide both
            image sizes.
    """
    if factor < 1 or image.width % factor != 0 or image.height % factor != 0:
        raise Error("The supersampling factor must divide the image")
    var width = image.width // factor
    var height = image.height // factor
    var hits = coverage_samples(image, background)
    var result = List[Float32](length=width * height, fill=0)
    var scale = opacity / Float32(factor * factor)
    for y in range(image.height):  # pragma: no branch
        for x in range(image.width):  # pragma: no branch
            result[(y // factor) * width + x // factor] += (
                hits[y * image.width + x] * scale
            )
    return result^


def total_coverage_error(
    measured: List[Float32], reference: List[Float32]
) raises -> Float64:
    """Return the relative error of the summed coverage.

    Args:
        measured: The stochastic coverage of each pixel.
        reference: The ground-truth coverage of the same pixels.

    Returns:
        The absolute difference of the two sums, over the reference sum.

    Raises:
        Error: If the lengths differ or the reference covers nothing.
    """
    if len(measured) != len(reference):
        raise Error("Coverage lists must have the same length")
    var a = Float64(0)
    var b = Float64(0)
    for index in range(len(measured)):
        a += Float64(measured[index])
        b += Float64(reference[index])
    if b <= 0:
        raise Error("The reference coverage must be positive")
    return abs(a - b) / b


def block_coverage_error(
    measured: List[Float32],
    reference: List[Float32],
    width: Int,
    block: Int,
) raises -> Float64:
    """Return the coverage error after a box filter of `block` pixels.

    The image is cut into whole squares of `block` by `block` pixels. The
    result is the mean absolute difference of the square means, over the
    mean of the reference square means. Stochastic coverage has one
    sample a pixel, so this measures its noise at that filter size.

    Args:
        measured: The stochastic coverage of each pixel.
        reference: The ground-truth coverage of the same pixels.
        width: The image width in pixels.
        block: The filter size, which must divide the width and height.

    Returns:
        The normalized mean absolute error.

    Raises:
        Error: If the lengths differ, the block does not divide the image,
            or the reference covers nothing.
    """
    if len(measured) != len(reference):
        raise Error("Coverage lists must have the same length")
    if (
        block < 1
        or width < 1
        or width % block != 0
        or len(measured) % (width * block) != 0
    ):
        raise Error("The block size must divide the image")
    var height = len(measured) // width
    var columns = width // block
    var squares = columns * (height // block)
    var a = List[Float64](length=squares, fill=0)
    var b = List[Float64](length=squares, fill=0)
    for y in range(height):
        for x in range(width):  # pragma: no branch
            var square = (y // block) * columns + x // block
            a[square] += Float64(measured[y * width + x])
            b[square] += Float64(reference[y * width + x])
    var error = Float64(0)
    var total = Float64(0)
    for square in range(squares):
        error += abs(a[square] - b[square])
        total += b[square]
    if total <= 0:
        raise Error("The reference coverage must be positive")
    return error / total


def count_color(
    image: Framebuffer, color: Color, x0: Int, y0: Int, x1: Int, y1: Int
) raises -> Int:
    """Count the pixels of one exact color in a rectangle.

    Args:
        image: A rendered image.
        color: The color to count, alpha ignored.
        x0: The first column.
        y0: The first row, from the top.
        x1: One past the last column.
        y1: One past the last row.

    Returns:
        How many pixels in the rectangle have that color.

    Raises:
        Error: If the rectangle leaves the image.
    """
    var count = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            var p = image.get_pixel(x, y)
            count += Int(_rgb(p) == _rgb(color))
    return count


@fieldwise_init
struct _Ball(DistanceField, ImplicitlyCopyable):
    """A sphere that stands for the head behind the curtain."""

    var center: Vector3
    var radius: Float32

    def distance(self, point: Vector3) -> Float32:
        """Return the signed distance from the sphere's surface.

        Args:
            point: Where to measure.

        Returns:
            Negative inside, positive outside.
        """
        return (point - self.center).length() - self.radius


# The curtain: rows of strands that hang 0.4 meters from roots on a bar.
comptime _CURTAIN_TOP = Float32(0.2)
comptime _CURTAIN_LENGTH = Float32(0.4)
comptime _CURTAIN_HALF_WIDTH = Float32(0.12)
comptime _CURTAIN_ROW_SPACING = Float32(0.04)
# Each drawn strand stands for a clump of fibers, so the density of a
# coarse curtain uses a clump diameter, not one fiber's 80 micrometers.
comptime _CURTAIN_CLUMP = Float32(0.0015)


struct HairReferenceRig(Movable):
    """A curtain of long strands in rows, with its light, wind and camera.

    Row zero is nearest the camera, at z = 0. Each later row is
    0.04 meters farther away. Every guide has followers to each
    side, laid in its frame. A sphere behind the curtain is the collider.
    A receiver plane behind it can show the cast shadow.
    """

    var scene: Scene
    var assets: Assets
    var camera: OrthographicCamera
    var hair: HairStrands
    var motion: HairSimulation
    var collider: HairCollider
    var wind: HairWind
    var lights: List[HairLight]
    var eye: Vector3
    var ambient: Vector3
    # The row of each strand, in strand order.
    var rows: List[Int]
    var receiver: Optional[NodeId]

    def __init__(
        out self,
        look: HairLook,
        light: Vector3,
        rows: Int = 4,
        guides: Int = 12,
        followers: Int = 2,
        points: Int = 12,
        clump: Length = Length(_CURTAIN_CLUMP, METER),
        width: LineWidth = LineWidth(pixels=1),
        opacity: Float32 = 0.65,
        receiver: Bool = False,
    ) raises:
        """Hang the curtain and shade it for one distant light.

        Args:
            look: How the fibers scatter light.
            light: The direction toward the light, in world space.
            rows: How many rows, one or more.
            guides: How many guide strands in each row, one or more.
            followers: How many followers each guide has, zero or more.
            points: How many points on each strand, two or more.
            clump: The diameter that the density volume gives each strand.
            width: The drawn width of each strand.
            opacity: The strand opacity.
            receiver: Add a shadow-receiving plane behind the curtain, and
                a matching shadow-casting scene light.

        Raises:
            Error: If a count is out of range, the light direction is
                zero or not finite, or a strand setting is refused.
        """
        if rows < 1 or guides < 1 or followers < 0 or points < 2:
            raise Error(
                "A hair reference curtain needs rows, guides and points"
            )
        var toward = light
        var length = toward.length()
        if not (length > 0 and isfinite(length)):
            raise Error("A hair reference light needs a finite direction")
        toward = toward / length
        var groom = HairGroom()
        var strand_rows = List[Int]()
        var normal = Vector3(0, 0, 1)
        var spacing = 2 * _CURTAIN_HALF_WIDTH / Float32(guides)
        var step = _CURTAIN_LENGTH / Float32(points - 1)
        for row in range(rows):  # pragma: no branch
            var z = -Float32(row) * _CURTAIN_ROW_SPACING
            for guide in range(guides):  # pragma: no branch
                var x = -_CURTAIN_HALF_WIDTH + spacing * (Float32(guide) + 0.5)
                # Alternate rows shift by a quarter spacing, so the rows
                # do not hide each other exactly.
                x += spacing * 0.25 * Float32(row % 2)
                var line = List[Vector3]()
                var normals = List[Vector3]()
                var depths = List[Float32]()
                for k in range(points):  # pragma: no branch
                    line.append(Vector3(x, _CURTAIN_TOP - step * Float32(k), z))
                    normals.append(normal)
                    depths.append(0)
                groom.add(line, normals, depths, 1)
                strand_rows.append(row)
                var lead = len(groom) - 1
                for follower in range(followers):
                    var side = Float32(1 if follower % 2 == 0 else -1)
                    var offset = (
                        side
                        * spacing
                        * Float32(follower // 2 + 1)
                        / Float32(followers + 1)
                    )
                    var placed = List[Vector3]()
                    var across = List[Float32]()
                    var up = List[Float32]()
                    for k in range(points):  # pragma: no branch
                        var before = line[max(k - 1, 0)]
                        var after = line[min(k + 1, points - 1)]
                        var a = follower_across(before, after, normal)
                        placed.append(line[k] + a * offset)
                        across.append(offset)
                        up.append(0)
                    groom.add_follower(
                        placed, normals, depths, 1, lead, across, up
                    )
                    strand_rows.append(row)
        var center = Vector3(
            0, 0, -Float32(rows - 1) * _CURTAIN_ROW_SPACING - 0.13
        )
        self.collider = HairCollider(
            _Ball(center, 0.1),
            Vector3(-0.4, -0.4, -0.6),
            Vector3(0.4, 0.4, 0.3),
        )
        self.motion = HairSimulation(groom, guides_only=True)
        self.wind = HairWind(Vector3(1, 0, 0.4), 0.6)
        self.lights = [HairLight(toward, Vector3(3, 3, 3))]
        self.eye = Vector3(0, 0, 4)
        self.ambient = Vector3(0.05, 0.05, 0.05)
        self.rows = strand_rows^
        self.scene = Scene()
        self.assets = Assets()
        var root = self.scene.add(Object3D())
        var hair = add_strands(
            self.scene, self.assets, root, groom^, look, width, opacity
        )
        hair.density = HairDensity(24, clump)
        self.hair = hair^
        self.receiver = None
        if receiver:
            var back = Object3D()
            back.set_position(
                0, 0, -Float32(rows) * _CURTAIN_ROW_SPACING - 0.15
            )
            var node = self.scene.add(back^)
            var shape = self.assets.geometries.add(
                plane(Length(0.8, METER), Length(0.8, METER))
            )
            var paint = self.assets.materials.add(
                Material(Color(170, 180, 200), side=DOUBLE_SIDE)
            )
            self.scene.add_mesh(Mesh(shape, paint, node, receive_shadow=True))
            var lamp = Object3D()
            lamp.set_position(toward.x * 3, toward.y * 3, toward.z * 3)
            var lamp_node = self.scene.add(lamp^)
            var sun = directional_light(Color(255, 255, 255), lamp_node)
            sun.cast_shadow = True
            sun.shadow.map_size = 128
            sun.shadow.set_extent(Length(0.45, METER))
            sun.shadow.near = Length(0.1, METER)
            sun.shadow.far = Length(10, METER)
            self.scene.add_light(sun)
            self.receiver = node
        self.camera = centered(
            Length(0.6, METER), 1, Length(0.1, METER), Length(10, METER)
        )
        self.camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
        self.scene.update()
        self.hair.shade(self.assets, self.lights, self.eye, self.ambient)

    def advance(mut self, steps: Int) raises:
        """Step the guides in the wind, write the groom and shade it again.

        Args:
            steps: How many simulation steps, zero or more.

        Raises:
            Error: If the groom no longer matches the simulation.
        """
        for _ in range(steps):
            self.motion.step(self.collider, self.wind)
        self.motion.write(self.hair.groom)
        self.hair.shade(self.assets, self.lights, self.eye, self.ambient)

    def colors(self) raises -> List[Float32]:
        """Return each point's shaded linear color, three floats a point.

        The arithmetic is `HairStrands.shade` after its density rebuild:
        the same optical depths and the same shading.

        Returns:
            The colors the last `shade` uploaded.

        Raises:
            Error: If the density or shading inputs are refused.
        """
        ref groom = self.hair.groom
        var depths = List[Float32](
            capacity=len(groom.points) * len(self.lights)
        )
        for index in range(len(groom.points)):  # pragma: no branch
            for light in self.lights:  # pragma: no branch
                depths.append(
                    self.hair.density.optical_depth(
                        groom.points[index], light.direction
                    )
                )
        var colors = List[Float32](length=len(groom.points) * 3, fill=0)
        shade_groom_into(
            groom,
            self.hair.look,
            self.lights,
            self.eye,
            self.ambient,
            colors,
            depths,
        )
        return colors^

    def row_luminance(self) raises -> List[Float64]:
        """Return the mean linear luminance of each row's points.

        Returns:
            One mean for each row, row zero first.

        Raises:
            Error: If the colors cannot be shaded.
        """
        var colors = self.colors()
        var count = 0
        for row in self.rows:  # pragma: no branch
            count = max(count, row + 1)
        var sums = List[Float64](length=count, fill=0)
        var points = List[Int](length=count, fill=0)
        ref groom = self.hair.groom
        for strand in range(len(groom)):  # pragma: no branch
            var row = self.rows[strand]
            for index in range(
                groom.starts[strand], groom.starts[strand + 1]
            ):  # pragma: no branch
                sums[row] += (
                    0.2126 * Float64(colors[index * 3])
                    + 0.7152 * Float64(colors[index * 3 + 1])
                    + 0.0722 * Float64(colors[index * 3 + 2])
                )
                points[row] += 1
        for row in range(count):  # pragma: no branch
            sums[row] /= Float64(points[row])
        return sums^
