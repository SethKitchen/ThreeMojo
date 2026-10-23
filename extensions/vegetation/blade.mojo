# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One blade of grass as geometry, and a buffer that holds many.

**The blade.** A blade is a strip of `segments` quads that ends in one
triangle at the tip. It is `2 * segments - 1` triangles and
`2 * segments + 1` vertices. The strip starts at the root and steps up
one segment at a time:

- Each segment turns toward the blade's forward side by its share of
  `curl`, the bend of a blade at rest. It turns by its share of the
  wind's tip bend as well. The two turns add as one tilt along the
  ground, at most `MAX_TILT`. Each segment keeps its length.
- The width tapers as `1 - s * s`, where `s` runs from zero at the root
  to one at the tip. A blade is nearly parallel at the root and comes
  to a point.

**The normals.** A flat strip lit by its face normal looks like paper.
Each edge vertex tilts its normal out toward its own edge, by `ROUNDING`,
so the strip is lit as if it were rounded across its width. Each normal
tilts up as well, by `UP_BIAS`. The field then shades as one soft surface
and not as a noise of blades turned every way.

**The colors.** The color runs from the root to the tip. The root color
is dark: it holds the occlusion of the dense grass round the root, which
the renderer does not compute. `shade` mixes between two tip colors, so
neighbors differ.

**A poppy** is a thin stem, built as a blade, with a cup of five red
petals at its tip.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from extensions.vegetation.checks import require_between
from extensions.vegetation.kinds import (
    DRY_GRASS,
    POPPY,
    PlantKind,
    require_plant_kind,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
from units.si import DEGREE, METER, RADIAN, Angle, Length

# How far an edge normal tilts out toward its edge.
comptime ROUNDING = Float32(0.55)
# How far every normal tilts up.
comptime UP_BIAS = Float32(0.65)
# The most segments a blade can have.
comptime MAX_SEGMENTS = 8
# The petals of a poppy's cup.
comptime PETALS = 5
# The radius of a poppy's cup at a shade of zero.
comptime CUP_RADIUS = Float32(0.025)
# The most a segment can tilt from upright, in radians: 83 degrees. A
# segment never lies flat, so a blade never folds into the ground.
comptime MAX_TILT = Float32(1.45)


@fieldwise_init
struct BladeColors(ImplicitlyCopyable):
    """The linear colors at the root and at the tip of a blade."""

    var root: Vector3
    var tip: Vector3


def blade_colors(kind: PlantKind, shade: Float32) raises -> BladeColors:
    """Return the root and tip colors of a blade.

    Args:
        kind: What the blade is. A poppy's colors are its stem's.
        shade: Where between the two tip colors the blade is, from zero to
            one.

    Returns:
        The linear root and tip colors.

    Raises:
        Error: If `kind` is not valid.
    """
    require_plant_kind(kind)
    if kind == DRY_GRASS:
        return BladeColors(
            Vector3(0.035, 0.032, 0.010),
            Vector3(0.36 + 0.12 * shade, 0.30 + 0.08 * shade, 0.10),
        )
    if kind == POPPY:
        return BladeColors(
            Vector3(0.012, 0.030, 0.006), Vector3(0.060, 0.150, 0.025)
        )
    return BladeColors(
        Vector3(0.006, 0.018, 0.003),
        Vector3(0.060 + 0.11 * shade, 0.210 + 0.10 * shade, 0.018),
    )


struct Blade(ImplicitlyCopyable):
    """One blade, placed: where its root is, which way it faces, and its
    size, rest bend, phase and shade."""

    # Where the root is, on the ground, in meters.
    var root: Vector3
    # Which way the blade's face turns, about +y. The blade curls toward
    # the direction a quarter turn from its width.
    var facing: Angle
    # How long the blade is, root to tip.
    var height: Length
    # How wide the blade is at its root.
    var width: Length
    # How far the tip turns from upright at rest.
    var curl: Angle
    # The blade's own phase for the flutter, from zero to one.
    var phase: Float32
    # Where between the two tip colors the blade is, from zero to one.
    var shade: Float32
    # What the blade is.
    var kind: PlantKind

    def __init__(
        out self,
        root: Vector3,
        facing: Angle,
        height: Length,
        width: Length,
        curl: Angle,
        phase: Float32,
        shade: Float32,
        kind: PlantKind,
    ):
        """Create a blade. `check` says whether it can be built.

        Args:
            root: Where the root is, in meters.
            facing: Which way the face turns, about +y.
            height: How long the blade is.
            width: How wide it is at the root.
            curl: How far the tip turns from upright at rest.
            phase: Its flutter phase, from zero to one.
            shade: Where between the tip colors it is, from zero to one.
            kind: What it is.
        """
        self.root = root
        self.facing = facing
        self.height = height
        self.width = width
        self.curl = curl
        self.phase = phase
        self.shade = shade
        self.kind = kind

    def check(self) raises:
        """Refuse a blade that cannot be built.

        Raises:
            Error: If a root coordinate is not within a thousand
                kilometers, the facing is not finite, the height is not
                from 1 millimeter to 5 meters, the width is not from 0.1
                millimeter to 20 centimeters, the curl is not from 0 to 120
                degrees, the phase or shade is not from 0 to 1, or the
                kind is not valid.
        """
        var far = Float32(1.0e6)
        require_between(self.root.x, -far, far, "A blade's root is too far")
        require_between(self.root.y, -far, far, "A blade's root is too far")
        require_between(self.root.z, -far, far, "A blade's root is too far")
        require_between(
            self.facing.to(RADIAN), -far, far, "A blade must face a finite way"
        )
        require_between(
            self.height.to(METER),
            0.001,
            5,
            "A blade must be from 1 millimeter to 5 meters long",
        )
        require_between(
            self.width.to(METER),
            0.0001,
            0.2,
            "A blade must be from 0.1 millimeter to 20 centimeters wide",
        )
        require_between(
            self.curl.to(DEGREE),
            0,
            120,
            "A blade must curl from 0 to 120 degrees",
        )
        require_between(self.phase, 0, 1, "A blade's phase must be from 0 to 1")
        require_between(self.shade, 0, 1, "A blade's shade must be from 0 to 1")
        require_plant_kind(self.kind)


def blade_triangles(segments: Int) -> Int:
    """Return how many triangles a blade of `segments` segments has.

    Args:
        segments: The segments, one or more.

    Returns:
        `2 * segments - 1`.
    """
    return 2 * segments - 1


struct BladeMesh(Movable):
    """Positions, normals, colors and an index, filled blade by blade.

    `geometry` hands them over as one indexed geometry.
    """

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]
    var index: List[Int]

    def __init__(out self):
        """Create an empty buffer."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()
        self.index = List[Int]()

    def reserve(mut self, blades: Int, segments: Int):
        """Make room for `blades` blades of `segments` segments.

        Args:
            blades: How many blades will be added.
            segments: How many segments each has.
        """
        var vertices = blades * (2 * segments + 1)
        self.positions.reserve(len(self.positions) + 3 * vertices)
        self.normals.reserve(len(self.normals) + 3 * vertices)
        self.colors.reserve(len(self.colors) + 3 * vertices)
        self.index.reserve(
            len(self.index) + 3 * blades * blade_triangles(segments)
        )

    def vertex_count(self) -> Int:
        """Return how many vertices the buffer holds.

        Returns:
            The vertex count.
        """
        return len(self.positions) // 3

    def triangle_count(self) -> Int:
        """Return how many triangles the buffer holds.

        Returns:
            The triangle count.
        """
        return len(self.index) // 3

    def _vertex(mut self, p: Vector3, n: Vector3, c: Vector3):
        """Append one vertex, with its normal made unit length."""
        self.positions.append(p.x)
        self.positions.append(p.y)
        self.positions.append(p.z)
        var scale = 1 / sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
        self.normals.append(n.x * scale)
        self.normals.append(n.y * scale)
        self.normals.append(n.z * scale)
        self.colors.append(c.x)
        self.colors.append(c.y)
        self.colors.append(c.z)

    def _triangle(mut self, a: Int, b: Int, c: Int):
        """Append one triangle."""
        self.index.append(a)
        self.index.append(b)
        self.index.append(c)

    def add(
        mut self,
        blade: Blade,
        segments: Int,
        bend: Vector2,
        widen: Float32,
        glint: Float32 = 0,
    ) raises:
        """Add a blade, bent by the wind.

        The blade is not checked here, so a field can add many blades
        fast. Check each blade once, when it is placed.

        Args:
            blade: The blade.
            segments: How many segments, from 1 to `MAX_SEGMENTS`.
            bend: How far the wind turns the tip, in radians, as x and z.
                See `Wind.tip_bend`.
            widen: What the width is multiplied by. A thinned level of
                detail widens the blades it keeps, so the field keeps its
                cover.
            glint: How much brighter the tip is, from 0 to 1. A gust bends
                a blade so it shows more of its lit face, and the field
                then shows the gust as a wave of light.

        Raises:
            Error: If `segments` is out of range, `widen` is not from 1 to
                200, `glint` is not from 0 to 1, or the kind is not valid.
        """
        if segments < 1 or segments > MAX_SEGMENTS:
            raise Error("A blade must have from 1 to 8 segments")
        require_between(
            widen, 1, 200, "A blade must be widened from 1 to 200 times"
        )
        require_between(glint, 0, 1, "A blade's glint must be from 0 to 1")
        var colors = blade_colors(blade.kind, blade.shade)
        colors.tip = colors.tip * (1 + glint)
        var face = blade.facing.to(RADIAN)
        var ax = cos(face)
        var az = sin(face)
        var curl = blade.curl.to(RADIAN)
        var step = blade.height.to(METER) / Float32(segments)
        var half = blade.width.to(METER) * widen * 0.5
        var point = blade.root
        var base = self.vertex_count()
        for k in range(segments + 1):  # pragma: no branch
            var s = Float32(k) / Float32(segments)
            # The direction of the segment that starts at this ring, read
            # at its middle. The tip ring reads past the end, which only
            # sets the tip's normal.
            var mid = s + 0.5 / Float32(segments)
            # The rest curl and the wind are one tilt: an angle along the
            # ground. The wind adds to the curl or takes from it.
            var tx = -az * curl * mid + bend.x * mid
            var tz = ax * curl * mid + bend.y * mid
            var tilt = sqrt(tx * tx + tz * tz)
            var lean = min(tilt, MAX_TILT)
            var keep = sin(lean) / max(tilt, Float32(1.0e-6))
            var hx = tx * keep
            var hz = tz * keep
            var dy = cos(lean)
            var normal = Vector3(dy * az, hz * ax - hx * az, -dy * ax)
            normal.y += UP_BIAS
            var color = colors.root + (colors.tip - colors.root) * s
            if k < segments:
                var width = half * (1 - s * s)
                var side = Vector3(ax * width, 0, az * width)
                var tilt = Vector3(ax * ROUNDING, 0, az * ROUNDING)
                self._vertex(point - side, normal - tilt, color)
                self._vertex(point + side, normal + tilt, color)
                point = point + Vector3(hx, dy, hz) * step
            else:
                self._vertex(point, normal, color)
        for k in range(segments - 1):
            var a = base + 2 * k
            self._triangle(a, a + 1, a + 3)
            self._triangle(a, a + 3, a + 2)
        var last = base + 2 * (segments - 1)
        self._triangle(last, last + 1, last + 2)
        if blade.kind == POPPY:
            self._cup(point, face, blade.shade, sqrt(widen))

    def _cup(
        mut self, center: Vector3, face: Float32, shade: Float32, grow: Float32
    ):
        """Append a poppy's cup of petals, open upward, at a stem's tip.

        Each petal is one triangle with three vertices of its own, so each
        petal has its own normal.
        """
        var radius = CUP_RADIUS * (0.8 + 0.4 * shade) * grow
        var heart = Vector3(0.20, 0.008, 0.004)
        var rim = Vector3(0.62, 0.020, 0.010)
        var turn = Float32(2) * Float32(pi) / Float32(PETALS)
        for j in range(PETALS):  # pragma: no branch
            var a0 = face + turn * Float32(j)
            var a1 = a0 + turn * 0.95
            var am = a0 + turn * 0.475
            var p0 = center + Vector3(
                cos(a0) * radius, radius * 0.55, sin(a0) * radius
            )
            var p1 = center + Vector3(
                cos(a1) * radius, radius * 0.55, sin(a1) * radius
            )
            var n = Vector3(cos(am) * 0.5, 1, sin(am) * 0.5)
            var first = self.vertex_count()
            self._vertex(center, n, heart)
            self._vertex(p0, n, rim)
            self._vertex(p1, n, rim)
            self._triangle(first, first + 1, first + 2)

    def geometry(deinit self) raises -> BufferGeometry:
        """Hand the buffer over as one indexed geometry.

        Returns:
            The geometry, with `position`, `normal`, `color` and an index.

        Raises:
            Error: If the buffer is empty.
        """
        if len(self.index) == 0:
            raise Error("A blade mesh with no blades makes no geometry")
        var geometry = BufferGeometry()
        geometry.set_attribute(POSITION, BufferAttribute(self.positions^, 3))
        geometry.set_attribute(NORMAL, BufferAttribute(self.normals^, 3))
        geometry.set_attribute(COLOR, BufferAttribute(self.colors^, 3))
        geometry.set_index(self.index^)
        return geometry^
