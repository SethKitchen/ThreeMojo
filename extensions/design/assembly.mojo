# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A structure as boxes, built stage by stage, for animated views.

An `Assembly` holds `Part`s: boxes with a center, a size, a color, a
construction stage and, when a check gave one, a demand-to-capacity
ratio. `add_assembly` puts the parts of an assembly into a scene:

- `build` is a stage number with a fraction. Parts of the stages below
  its whole part stand in place. Parts of its own stage come down from
  above as the fraction runs from 0 to 1. Parts of later stages are not
  added. So a sweep of `build` from 0 to the stage count animates the
  construction sequence.
- With `by_ratio`, a part with a ratio takes the color of
  `utilization_color` of `extensions.geotech.failure`, so the view shows
  which members work hardest. A part without a ratio is gray.

`draw_ratio_legend` paints the color scale of the ratios into a rendered
frame, with ticks at 0.5, 1.0 and 1.5. `orbit_eye` places a camera on a circle around a target, for a turning
view. The y axis is up, as in three.js.
"""

from std.math import cos, floor, sin
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.design.steel import require_positive
from extensions.geotech.failure import utilization_color
from geometries.box import box
from materials.material import standard_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from units.si import Angle, Length, METER, RADIAN

# The ratio of a part that no check rated.
comptime NO_RATIO = -1.0


@fieldwise_init
struct Part(Copyable, Movable):
    """A box of a structure."""

    var name: String
    # The center, in meters, y up.
    var center: Vector3
    # The extents along x, y and z, in meters.
    var size: Vector3
    var color: Color
    # The construction stage, 0 or more.
    var stage: Int
    # The demand-to-capacity ratio, or `NO_RATIO`.
    var ratio: Float64
    # A turn about the x axis, in radians, such as a roof's pitch.
    var tilt: Float32
    # From above 0 to 1. Below 1 the part is see-through.
    var opacity: Float32

    def check(self) raises:
        """Refuse a part that cannot be drawn.

        Raises:
            Error: If a size is not positive, the stage is negative, or
                the opacity is not above 0 and at most 1.
        """
        require_positive(Float64(self.size.x), "A part's size must be positive")
        require_positive(Float64(self.size.y), "A part's size must be positive")
        require_positive(Float64(self.size.z), "A part's size must be positive")
        if self.stage < 0:
            raise Error("A part's stage must be 0 or more")
        if not (self.opacity > 0 and self.opacity <= 1):
            raise Error("A part's opacity must be above 0 and at most 1")


struct Assembly(Movable):
    """The parts of a structure."""

    var parts: List[Part]

    def __init__(out self):
        """Start an empty assembly."""
        self.parts = List[Part]()

    def add(mut self, var part: Part) raises:
        """Add a part.

        Args:
            part: The part.

        Raises:
            Error: If the part is not valid.
        """
        part.check()
        self.parts.append(part^)

    def add_box(
        mut self,
        name: String,
        low: Vector3,
        high: Vector3,
        color: Color,
        stage: Int,
        ratio: Float64 = NO_RATIO,
    ) raises:
        """Add an upright opaque box by two opposite corners.

        Args:
            name: The part's name.
            low: The corner with the least x, y and z, in meters.
            high: The opposite corner.
            color: The color.
            stage: The construction stage.
            ratio: The demand-to-capacity ratio, or `NO_RATIO`.

        Raises:
            Error: If the box has no volume or the stage is negative.
        """
        var center = Vector3(
            (low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2
        )
        var size = Vector3(high.x - low.x, high.y - low.y, high.z - low.z)
        self.add(Part(name, center, size, color, stage, ratio, 0, 1))

    def stage_count(self) -> Int:
        """Return one more than the highest stage.

        Returns:
            The number of stages, 0 for an empty assembly.
        """
        var n = 0
        for p in self.parts:
            n = max(n, p.stage + 1)
        return n


def ratio_color(ratio: Float64) -> Color:
    """Return the sRGB color of a demand-to-capacity ratio.

    Args:
        ratio: The ratio. `NO_RATIO`, or any negative ratio, is gray.

    Returns:
        `utilization_color` of the ratio, encoded to 8-bit sRGB.
    """
    if ratio < 0:
        return Color(150, 154, 160)
    var c = utilization_color(ratio)
    return Color(_srgb(c[0]), _srgb(c[1]), _srgb(c[2]))


def _srgb(linear: Float64) -> UInt8:
    """Return a linear channel from 0 to 1 as an 8-bit sRGB value."""
    var v = min(max(linear, 0.0), 1.0)
    var s = 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return UInt8(Int(s * 255 + 0.5))


def add_assembly(
    mut scene: Scene,
    mut assets: Assets,
    assembly: Assembly,
    build: Float64,
    by_ratio: Bool,
    drop: Length,
    first_stage: Int = 0,
) raises -> Int:
    """Add the parts of an assembly that a build state shows.

    Args:
        scene: The scene to add to.
        assets: The geometry and material store.
        assembly: The parts.
        build: The stage, with a fraction for the stage in progress. The
            stage count or more shows every part in place.
        by_ratio: True to color each part by its ratio.
        drop: How far above its place a part of the current stage starts.
        first_stage: Parts of earlier stages are left out, such as the
            ground in a view of the structure alone.

    Returns:
        How many parts were added.

    Raises:
        Error: If `build` is negative or not finite, `drop` is negative,
            or the scene refuses a node.
    """
    if not (build >= 0 and build < Float64.MAX):
        raise Error("A build state must be zero or more and finite")
    var lift = drop.to(METER)
    if not (lift >= 0 and lift < Float32.MAX):
        raise Error("A drop height must be zero or more")
    var whole = Int(floor(build))
    var fraction = build - Float64(whole)
    var added = 0
    for p in assembly.parts:
        if p.stage < first_stage:
            continue
        if p.stage > whole or (p.stage == whole and fraction <= 0):
            continue
        var y = p.center.y
        if p.stage == whole:
            # Ease out: fast at first, settling into place.
            var t = 1 - (1 - fraction) ** 3
            y += Float32((1 - t) * Float64(lift))
        var geometry = assets.geometries.add(
            box(
                Length(p.size.x, METER),
                Length(p.size.y, METER),
                Length(p.size.z, METER),
            )
        )
        var color = ratio_color(p.ratio) if by_ratio else p.color
        var see_through = p.opacity < 1
        var material = assets.materials.add(
            standard_material(
                color,
                roughness=0.82,
                metalness=Float32(0.25) if p.ratio >= 0
                and by_ratio else Float32(0),
                opacity=p.opacity,
                transparent=see_through,
            )
        )
        var node = Object3D()
        node.set_position(p.center.x, y, p.center.z)
        if p.tilt != 0:
            node.rotate_x(Angle(p.tilt, RADIAN))
        scene.add_mesh(
            Mesh(
                geometry,
                material,
                scene.add(node^),
                cast_shadow=not see_through,
                receive_shadow=True,
            )
        )
        added += 1
    return added


def orbit_eye(
    target: Vector3, radius: Float32, height: Float32, angle: Float32
) -> Vector3:
    """Return a camera position on a circle around a target.

    Args:
        target: The point the camera circles, in meters.
        radius: The circle's radius, in meters.
        height: The camera's height above the target, in meters.
        angle: The angle around the vertical, in radians, from +x toward
            -z (counterclockwise seen from above).

    Returns:
        The camera position.
    """
    return Vector3(
        target.x + radius * cos(angle),
        target.y + height,
        target.z - radius * sin(angle),
    )


# The ratio at the right end of the legend.
comptime LEGEND_MAX: Float64 = 2.0


def draw_ratio_legend(
    mut frame: Framebuffer, x: Int, y: Int, width: Int, height: Int
) raises:
    """Paint the ratio color scale as a bar in a frame.

    The bar runs from a ratio of 0 at its left end to `LEGEND_MAX` at its
    right end, with a dark frame and white ticks at 0.5, 1.0 and 1.5.

    Args:
        frame: The rendered frame.
        x: The bar's left pixel.
        y: The bar's top pixel.
        width: The bar's width in pixels, 2 or more.
        height: The bar's height in pixels, 2 or more.

    Raises:
        Error: If the bar does not fit inside the frame or is too small.
    """
    if width < 2 or height < 2:
        raise Error("A legend must be at least 2 by 2 pixels")
    if x < 0 or y < 0 or x + width > frame.width or y + height > frame.height:
        raise Error("A legend must fit inside the frame")
    # The bar is 2 pixels or more each way, so these loops always run.
    for i in range(width):  # pragma: no branch
        var r = LEGEND_MAX * Float64(i) / Float64(width - 1)
        var c = ratio_color(r)
        # The bar is at least 2 pixels high.
        for j in range(height):  # pragma: no branch
            var edge = i == 0 or i == width - 1 or j == 0 or j == height - 1
            frame.set_pixel(x + i, y + j, Color(30, 34, 40) if edge else c)
    for tick in [0.5, 1.0, 1.5]:
        var i = Int(tick / LEGEND_MAX * Float64(width - 1) + 0.5)
        # The bar is at least 2 pixels high.
        for j in range(height):  # pragma: no branch
            frame.set_pixel(x + i, y + j, Color(255, 255, 255))
