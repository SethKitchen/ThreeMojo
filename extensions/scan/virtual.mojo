# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A virtual scanner: pictures of a scene with their depth, made into splats.

A renderer that draws a scene well, with materials, shadows, water and woods,
draws it slowly. A scan of the scene as a set of splats draws it in
milliseconds, and the scan can be cut into parts, weighed, and walked
through, as a scan of a real building can. `VirtualScan` makes the scan from
rendered pictures, as a photographer's rig does: each pixel of a picture is a
point of the scene, and the picture's color is the color of the point.

For each pixel of a view that holds a surface:

1. **The point.** The pixel's center and its stored depth, an NDC depth from
   -1 to 1, are taken back through the camera to a point of the scene.
2. **The surface.** The points of the pixel's right and lower neighbors give
   two tangents, and their cross product the normal, turned toward the
   camera. A pixel on the edge of a surface is left out: a neighbor that has
   no depth, a neighbor more than `edge` of the distance nearer or farther,
   or a normal that is within `grazing` of the line of sight.
3. **The splat.** It lies in the surface, as wide as the pixel's footprint
   along each tangent, `spread` of it as a deviation, and `thin` of that
   across the surface. It has the pixel's color.

The views overlap, so a point of the scene is seen many times. The points go
into cells, `voxel` on an edge, and a cell keeps the sample seen best: the
one that faced the camera most squarely, from the nearest. So a scan of 16
views of a castle holds about a splat for each cell of its surface, and no
more.

The splats are in the scene's own axes, in meters. A `ScanFrame` that names the
scene's up and north reads them. For a scene with y up and z south, as
`extensions.castle.scene` makes, up is +y and north is -z.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from math.finite import require_finite, require_positive_finite
from math.matrix4 import Matrix4, basis
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.collections import Dict
from std.math import floor, sqrt
from std.memory import bitcast
from std.pathlib import Path
from units.si import Length64, METER

comptime SPLAT_ROW = 32
"""The bytes of one splat of a `.splat` file."""


@fieldwise_init
struct VirtualScanOptions(ImplicitlyCopyable):
    """The choices of a virtual scan."""

    var voxel: Length64
    """The edge of a cell: the scan keeps one splat in each."""
    var edge: Float64
    """The most, as a share of its distance, that a neighbor of a pixel is
    nearer or farther than the pixel before the pixel is on an edge."""
    var grazing: Float64
    """The least cosine between the line of sight and the normal."""
    var spread: Float64
    """A splat's deviation, as a share of the pixel's footprint."""
    var thin: Float64
    """A splat's deviation across the surface, as a share of the smaller
    deviation in it."""
    var opacity: UInt8
    """The opacity byte of every splat."""

    def check(self) raises:
        """Refuse options that cannot make a scan.

        Raises:
            Error: If a number is not finite, the voxel, the edge, the
                spread or the thickness is not positive, or the grazing
                cosine is not from 0 up to 1.
        """
        require_positive_finite(
            self.voxel.to(METER), "Virtual scan: the voxel must be positive"
        )
        require_positive_finite(
            self.edge, "Virtual scan: the edge must be positive"
        )
        require_positive_finite(
            self.spread, "Virtual scan: the spread must be positive"
        )
        require_positive_finite(
            self.thin, "Virtual scan: the thickness must be positive"
        )
        require_finite(
            self.grazing, "Virtual scan: the grazing cosine must be finite"
        )
        if self.grazing < 0 or self.grazing >= 1:
            raise Error("Virtual scan: the grazing cosine is 0 up to 1")


def default_virtual_scan_options() -> VirtualScanOptions:
    """Return the options of a scan of a building from outside.

    Returns:
        A cell of 0.15 m, an edge of 3 percent of the distance, a grazing
        cosine of 0.2, a spread of 0.7 of the footprint, a thickness of
        0.15 and an opacity of 0.94.
    """
    return VirtualScanOptions(Length64(0.15, METER), 0.03, 0.2, 0.7, 0.15, 240)


def _point(
    inverse: Matrix4, x: Int, y: Int, width: Int, height: Int, depth: Float32
) -> Vector3:
    """Return the scene point of a pixel.

    Args:
        inverse: The inverse of the projection times the view.
        x: The pixel's column.
        y: The pixel's row, from the top.
        width: The picture's width.
        height: The picture's height.
        depth: The pixel's NDC depth.

    Returns:
        The point, in the scene.
    """
    return inverse.transform_point(
        Vector3(
            (Float32(x) + 0.5) / Float32(width) * 2 - 1,
            1 - (Float32(y) + 0.5) / Float32(height) * 2,
            depth,
        )
    )


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of two vectors.

    Args:
        a: The first.
        b: The second.

    Returns:
        `a x b`.
    """
    return Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def _cell(point: Vector3, voxel: Float64) -> Int:
    """Return the key of the cell that holds a point.

    Args:
        point: The point.
        voxel: The cell's edge, in meters.

    Returns:
        The three cell indexes, 21 bits each, in one number.
    """
    var i = Int(floor(Float64(point.x) / voxel)) & 0x1FFFFF
    var j = Int(floor(Float64(point.y) / voxel)) & 0x1FFFFF
    var k = Int(floor(Float64(point.z) / voxel)) & 0x1FFFFF
    return i | (j << 21) | (k << 42)


struct VirtualScan(Movable):
    """The splats of the views added so far; see the module docstring."""

    var options: VirtualScanOptions
    """The choices."""
    var cells: Dict[Int, Int]
    """For each cell, the place of its splat in the lists."""
    var centers: List[Float32]
    """Three floats a splat: the point."""
    var tangents: List[Float32]
    """Three floats a splat: the first tangent, a unit vector."""
    var normals: List[Float32]
    """Three floats a splat: the normal, a unit vector."""
    var deviations: List[Float32]
    """Two floats a splat: the deviations along the two tangents."""
    var colors: List[UInt8]
    """Four bytes a splat: the color and the opacity."""
    var scores: List[Float32]
    """How well each splat was seen: its cosine over its distance."""
    var views: Int
    """How many views have been added."""
    var samples: Int
    """How many samples the views gave, before the cells took the best."""

    def __init__(out self, options: VirtualScanOptions) raises:
        """Start a scan.

        Args:
            options: The choices.

        Raises:
            Error: If the options are refused.
        """
        options.check()
        self.options = options
        self.cells = Dict[Int, Int]()
        self.centers = List[Float32]()
        self.tangents = List[Float32]()
        self.normals = List[Float32]()
        self.deviations = List[Float32]()
        self.colors = List[UInt8]()
        self.scores = List[Float32]()
        self.views = 0
        self.samples = 0

    def count(self) -> Int:
        """Return how many splats the scan holds.

        Returns:
            One for each cell that has a sample.
        """
        return len(self.scores)

    def add_view(
        mut self, image: Framebuffer, view: Matrix4, projection: Matrix4
    ) raises -> Int:
        """Add a picture, with the camera that took it.

        Args:
            image: The picture and its depth, from `Renderer.render`. A pixel
                with no surface has a depth of infinity, or outside -1 to 1.
            view: The camera's view matrix: the scene to the camera.
            projection: The camera's projection matrix.

        Returns:
            How many samples the picture gave.

        Raises:
            Error: If a matrix cannot be inverted.
        """
        var width = image.width
        var height = image.height
        var inverse = projection * view
        inverse.invert()
        var eye_inverse = view
        eye_inverse.invert()
        var eye = eye_inverse.transform_point(Vector3(0, 0, 0))
        var points = List[Vector3](length=width * height, fill=Vector3(0, 0, 0))
        var present = List[Bool](length=width * height, fill=False)
        for y in range(height):
            for x in range(width):
                var depth = image.depth[y * width + x]
                if depth > -1 and depth < 1:
                    points[y * width + x] = _point(
                        inverse, x, y, width, height, depth
                    )
                    present[y * width + x] = True
        var voxel = self.options.voxel.to(METER)
        var taken = 0
        for y in range(height - 1):
            for x in range(width - 1):
                var slot = y * width + x
                if not (
                    present[slot]
                    and present[slot + 1]
                    and present[slot + width]
                ):
                    continue
                var p = points[slot]
                var right = points[slot + 1]
                var down = points[slot + width]
                var seen = p - eye
                var distance = seen.length()
                if not (distance > 0):
                    continue
                var reach = Float32(self.options.edge) * distance
                if (
                    abs((right - eye).length() - distance) > reach
                    or abs((down - eye).length() - distance) > reach
                ):
                    continue
                var tangent = right - p
                var across = down - p
                var normal = _cross(tangent, across)
                var size = normal.length()
                # Far from the origin the float32 points of neighbors can be
                # the same point, and the quad has no area and no normal.
                if not (size > 0):
                    continue
                var along = tangent.length()
                var below = across.length()
                normal = normal * (1 / size)
                var facing = normal.dot(seen) / distance
                if facing > 0:
                    normal = normal * -1
                    facing = -facing
                var cosine = -facing
                if Float64(cosine) < self.options.grazing:
                    continue
                taken += 1
                var score = cosine / distance
                var key = _cell(p, voxel)
                var found = self.cells.get(key)
                if found:
                    var place = found.value()
                    if score <= self.scores[place]:
                        continue
                    self._set(
                        place,
                        p,
                        tangent * (1 / along),
                        normal,
                        along,
                        below,
                        image,
                        slot,
                        score,
                    )
                else:
                    self.cells[key] = len(self.scores)
                    self.centers.extend([0, 0, 0])
                    self.tangents.extend([0, 0, 0])
                    self.normals.extend([0, 0, 0])
                    self.deviations.extend([0, 0])
                    self.colors.extend([0, 0, 0, 0])
                    self.scores.append(0)
                    self._set(
                        len(self.scores) - 1,
                        p,
                        tangent * (1 / along),
                        normal,
                        along,
                        below,
                        image,
                        slot,
                        score,
                    )
        self.views += 1
        self.samples += taken
        return taken

    def _set(
        mut self,
        place: Int,
        point: Vector3,
        tangent: Vector3,
        normal: Vector3,
        along: Float32,
        below: Float32,
        image: Framebuffer,
        slot: Int,
        score: Float32,
    ):
        """Write one splat's lanes.

        Args:
            place: Which splat.
            point: Its center.
            tangent: Its first tangent, a unit vector.
            normal: Its normal, a unit vector.
            along: The pixel's footprint along the first tangent.
            below: Its footprint along the second.
            image: The picture that gave the color.
            slot: The pixel.
            score: How well the sample was seen.
        """
        self.centers[place * 3] = point.x
        self.centers[place * 3 + 1] = point.y
        self.centers[place * 3 + 2] = point.z
        self.tangents[place * 3] = tangent.x
        self.tangents[place * 3 + 1] = tangent.y
        self.tangents[place * 3 + 2] = tangent.z
        self.normals[place * 3] = normal.x
        self.normals[place * 3 + 1] = normal.y
        self.normals[place * 3 + 2] = normal.z
        self.deviations[place * 2] = along * Float32(self.options.spread)
        self.deviations[place * 2 + 1] = below * Float32(self.options.spread)
        self.colors[place * 4] = image.pixels[slot * 4]
        self.colors[place * 4 + 1] = image.pixels[slot * 4 + 1]
        self.colors[place * 4 + 2] = image.pixels[slot * 4 + 2]
        self.colors[place * 4 + 3] = self.options.opacity
        self.scores[place] = score

    def geometry(self) raises -> GaussianSplatGeometry:
        """Return the scan as splats.

        Each splat's covariance is `sa^2 a a^T + sb^2 b b^T + sn^2 n n^T`,
        for its tangents `a` and `b`, its normal `n`, and its deviations.

        Returns:
            The splats, in the scene's axes and meters.

        Raises:
            Error: If the scan holds no splat.
        """
        if self.count() == 0:
            raise Error("Virtual scan: the views gave no splat")
        var covariances = List[Float32](length=self.count() * 6, fill=0)
        for place in range(self.count()):
            var a = Vector3(
                self.tangents[place * 3],
                self.tangents[place * 3 + 1],
                self.tangents[place * 3 + 2],
            )
            var n = Vector3(
                self.normals[place * 3],
                self.normals[place * 3 + 1],
                self.normals[place * 3 + 2],
            )
            var b = _cross(n, a)
            var sa = self.deviations[place * 2]
            var sb = self.deviations[place * 2 + 1]
            var sn = min(sa, sb) * Float32(self.options.thin)
            var lanes: List[Float32] = [
                a.x * a.x * sa * sa + b.x * b.x * sb * sb + n.x * n.x * sn * sn,
                a.x * a.y * sa * sa + b.x * b.y * sb * sb + n.x * n.y * sn * sn,
                a.x * a.z * sa * sa + b.x * b.z * sb * sb + n.x * n.z * sn * sn,
                a.y * a.y * sa * sa + b.y * b.y * sb * sb + n.y * n.y * sn * sn,
                a.y * a.z * sa * sa + b.y * b.z * sb * sb + n.y * n.z * sn * sn,
                a.z * a.z * sa * sa + b.z * b.z * sb * sb + n.z * n.z * sn * sn,
            ]
            for lane in range(6):
                covariances[place * 6 + lane] = lanes[lane]
        return create_gaussian_splat_geometry(
            self.centers.copy(), covariances^, self.colors.copy()
        )

    def splat_bytes(self) raises -> List[UInt8]:
        """Return the scan as the rows of a `.splat` file.

        A row holds the center, the three deviations, the color and the
        rotation, 32 bytes, as `loaders.splat.parse_splat` reads them. The
        rotation is a quaternion whose bytes are `128 + 128 q`, so it is
        kept to a hundredth.

        Returns:
            The bytes of the file.

        Raises:
            Error: If the scan holds no splat.
        """
        if self.count() == 0:
            raise Error("Virtual scan: the views gave no splat")
        var out = List[UInt8](length=self.count() * SPLAT_ROW, fill=0)
        for place in range(self.count()):
            var row = place * SPLAT_ROW
            var a = Vector3(
                self.tangents[place * 3],
                self.tangents[place * 3 + 1],
                self.tangents[place * 3 + 2],
            )
            var n = Vector3(
                self.normals[place * 3],
                self.normals[place * 3 + 1],
                self.normals[place * 3 + 2],
            )
            var b = _cross(n, a)
            var turn = Quaternion.from_matrix(basis(a, b, n))
            var sa = self.deviations[place * 2]
            var sb = self.deviations[place * 2 + 1]
            var sn = min(sa, sb) * Float32(self.options.thin)
            var floats: List[Float32] = [
                self.centers[place * 3],
                self.centers[place * 3 + 1],
                self.centers[place * 3 + 2],
                sa,
                sb,
                sn,
            ]
            for lane in range(6):
                var bits = bitcast[DType.uint32](floats[lane])
                for byte in range(4):
                    out[row + lane * 4 + byte] = UInt8(
                        (bits >> UInt32(8 * byte)) & 255
                    )
            for lane in range(4):
                out[row + 24 + lane] = self.colors[place * 4 + lane]
            out[row + 28] = _rotation_byte(turn.w)
            out[row + 29] = _rotation_byte(turn.x)
            out[row + 30] = _rotation_byte(turn.y)
            out[row + 31] = _rotation_byte(turn.z)
        return out^

    def write(self, path: String) raises:
        """Write the scan as a `.splat` file.

        Args:
            path: The file.

        Raises:
            Error: If the scan holds no splat or the file cannot be written.
        """
        Path(path).write_bytes(self.splat_bytes())


def _rotation_byte(value: Float32) -> UInt8:
    """Return a quaternion lane as the byte of a `.splat` file.

    Args:
        value: The lane, from -1 to 1.

    Returns:
        `128 + 128 value`, rounded, at most 255.
    """
    var scaled = Int(floor(Float64(value) * 128 + 128.5))
    return UInt8(min(max(scaled, 0), 255))
