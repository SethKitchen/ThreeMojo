# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The render view: meshes of a castle plan for a scene.

`add_castle` adds one node for the castle and one mesh for each surface:
brick, dressed stone, slate, water, lawn, gravel, trunks and foliage. Every
mesh takes its color from its vertex colors, so each brick course, each
slate and each tree has its own shade, and one seed fixes them all.

The plan frame is z up, with x to the east and y to the north. The scene is
y up, and a plan point (x, y, z) is the scene point (x, z, -y). The ground
of the island is z = 0. The water stands `freeboard` below it.

A round tower is a shaft of facets with a stone plinth and a string course.
It has arrow slits, and a cone of slate or a corbelled parapet of merlons. A
block has brick walls with a stone string course, rows of windows and a roof:
a gable with dormers, or a flat roof behind a corbelled, battlemented
parapet. A gate arch opens in the face at the end of a parapet block's
length. A bridge has segmental stone arches on brick piers, spandrel walls, a
gravel deck and parapets. The moat is a ring of water between a brick
revetment and a lawn bank. Trees stand in a ring beyond a gravel path: round
autumn crowns and dark conifers.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.castle.kinds import (
    BRICK,
    CONE,
    FOLIAGE,
    GABLE,
    GRAVEL,
    LAWN,
    PARAPET,
    ROUND,
    SLATE,
    SQUARE,
    STONE,
    Surface,
    TRUNK,
    WATER,
)
from extensions.castle.plan import (
    Block,
    Bridge,
    CastlePlan,
    Moat,
    PlanPoint,
    Tower,
)
from extensions.visual.mesh import MeshBuilder
from generators.utils import Vec3d, generator_random
from materials.material import Material, standard_material
from math.utils import SeededRandom
from objects.mesh import Mesh
from render.color_spaces import srgb_to_linear_three
from render.framebuffer import Color
from std.math import asin, cos, floor, pi, sin, sqrt
from units.si import Length64, METER

# The surfaces, in the order of their meshes.
comptime _SURFACES = 8
# The height of one storey, and of a window row, in meters.
comptime _STOREY = 3.6
# The height of a merlon, and its length and thickness.
comptime _MERLON = 1.2
# The depth below the ground at which walls start, in meters.
comptime _FOOT = 0.4
# How far a roof overhangs a wall.
comptime _OVERHANG = 0.45


@fieldwise_init
struct CastleOptions(ImplicitlyCopyable):
    """What `add_castle` draws."""

    # The facets of a round tower or a cone, six or more.
    var sides: Int
    # The trees of the wood around the castle, zero or more.
    var trees: Int
    # The seed of every shade and of the trees.
    var seed: Int
    # Whether the meshes cast and receive shadows.
    var shadows: Bool
    # Whether to draw the water as a mesh. Turn it off to put a mirror there.
    var water: Bool
    # No tree stands within the clearing radius of this point of the plan.
    # Put it under the camera so that no crown fills the frame.
    var clearing: PlanPoint
    var clearing_radius: Length64

    @staticmethod
    def default() -> CastleOptions:
        """Return 20 facets, 700 trees, seed 1085, shadows and water.

        Returns:
            The options. They have no clearing.
        """
        return CastleOptions(
            20,
            700,
            1085,
            True,
            True,
            PlanPoint(Length64(0.0, METER), Length64(0.0, METER)),
            Length64(0.0, METER),
        )


struct RenderedCastle(Movable):
    """What `add_castle` added."""

    var root: NodeId
    var meshes: Int
    var triangles: Int

    def __init__(out self, root: NodeId, meshes: Int, triangles: Int):
        """Hold a summary.

        Args:
            root: The castle's node.
            meshes: How many meshes were added.
            triangles: How many triangles they hold.
        """
        self.root = root
        self.meshes = meshes
        self.triangles = triangles


def _linear(red: Float64, green: Float64, blue: Float64) -> Vec3d:
    """Return a color of 0 to 255 sRGB channels as a linear color."""
    return Vec3d(
        srgb_to_linear_three(red / 255.0),
        srgb_to_linear_three(green / 255.0),
        srgb_to_linear_three(blue / 255.0),
    )


def surface_color(surface: Surface) -> Vec3d:
    """Return the linear base color of a surface.

    Args:
        surface: The surface.

    Returns:
        A color with each channel from zero to one. An unnamed surface
        gives mid gray.
    """
    if surface == BRICK:
        return _linear(168.0, 96.0, 70.0)
    if surface == STONE:
        return _linear(204.0, 195.0, 174.0)
    if surface == SLATE:
        return _linear(88.0, 100.0, 118.0)
    if surface == WATER:
        return _linear(34.0, 58.0, 66.0)
    if surface == LAWN:
        return _linear(136.0, 154.0, 64.0)
    if surface == GRAVEL:
        return _linear(178.0, 162.0, 136.0)
    if surface == TRUNK:
        return _linear(78.0, 60.0, 46.0)
    if surface == FOLIAGE:
        return _linear(200.0, 120.0, 40.0)
    return _linear(128.0, 128.0, 128.0)


struct _Layers(Movable):
    """One mesh builder for each surface, and the random shades."""

    var builders: List[MeshBuilder]
    var random: SeededRandom

    def __init__(out self, seed: Int):
        self.builders = List[MeshBuilder]()
        for _ in range(_SURFACES):  # pragma: no branch
            self.builders.append(MeshBuilder())
        self.random = generator_random(seed)

    def tone(mut self, base: Vec3d, spread: Float64) -> Vec3d:
        """Return a base color, made lighter or darker by up to `spread`."""
        var k = 1.0 + spread * (self.random.next() * 2.0 - 1.0)
        return Vec3d(base.x * k, base.y * k, base.z * k)


def _p(x: Float64, y: Float64, z: Float64) -> Vec3d:
    """Return a point."""
    return Vec3d(x, y, z)


def _quad(
    mut layers: _Layers,
    surface: Surface,
    a: Vec3d,
    b: Vec3d,
    c: Vec3d,
    d: Vec3d,
    facing: Vec3d,
    color: Vec3d,
) raises:
    """Add a quad that faces `facing`, as two triangles."""
    layers.builders[surface.value].oriented(a, b, c, facing, color)
    layers.builders[surface.value].oriented(a, c, d, facing, color)


def _triangle(
    mut layers: _Layers,
    surface: Surface,
    a: Vec3d,
    b: Vec3d,
    c: Vec3d,
    facing: Vec3d,
    color: Vec3d,
) raises:
    """Add a triangle that faces `facing`."""
    layers.builders[surface.value].oriented(a, b, c, facing, color)


def _frustum_colored(
    mut layers: _Layers,
    surface: Surface,
    base: Vec3d,
    cx: Float64,
    cy: Float64,
    r0: Float64,
    z0: Float64,
    r1: Float64,
    z1: Float64,
    sides: Int,
    phase: Float64,
    spread: Float64,
):
    """Add the side of a cone or a cylinder, smooth shaded.

    The radius goes from r0 at the height z0 to r1 at z1. A radius of zero
    makes a point. Each facet has its own shade.
    """
    var slope = (r0 - r1) / (z1 - z0)
    # `add_castle` refuses fewer than six facets, so the loop always runs.
    for k in range(sides):  # pragma: no branch
        var t0 = phase + 2.0 * pi * Float64(k) / Float64(sides)
        var t1 = phase + 2.0 * pi * Float64(k + 1) / Float64(sides)
        var color = layers.tone(base, spread)
        var n0 = Vec3d(cos(t0), sin(t0), slope).normalized()
        var n1 = Vec3d(cos(t1), sin(t1), slope).normalized()
        var a = _p(cx + r0 * cos(t0), cy + r0 * sin(t0), z0)
        var b = _p(cx + r0 * cos(t1), cy + r0 * sin(t1), z0)
        var c = _p(cx + r1 * cos(t1), cy + r1 * sin(t1), z1)
        var d = _p(cx + r1 * cos(t0), cy + r1 * sin(t0), z1)
        layers.builders[surface.value].smooth_triangle(
            a, b, c, n0, n1, n1, color, color, color
        )
        layers.builders[surface.value].smooth_triangle(
            a, c, d, n0, n1, n0, color, color, color
        )


def _frustum(
    mut layers: _Layers,
    surface: Surface,
    cx: Float64,
    cy: Float64,
    r0: Float64,
    z0: Float64,
    r1: Float64,
    z1: Float64,
    sides: Int,
    phase: Float64,
    spread: Float64,
):
    """Add the side of a cone or a cylinder in the base color of a surface."""
    _frustum_colored(
        layers,
        surface,
        surface_color(surface),
        cx,
        cy,
        r0,
        z0,
        r1,
        z1,
        sides,
        phase,
        spread,
    )


def _disc(
    mut layers: _Layers,
    surface: Surface,
    cx: Float64,
    cy: Float64,
    r: Float64,
    z: Float64,
    sides: Int,
    color: Vec3d,
) raises:
    """Add a disc that faces up."""
    var up = Vec3d(0.0, 0.0, 1.0)
    var middle = _p(cx, cy, z)
    for k in range(sides):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(k) / Float64(sides)
        var t1 = 2.0 * pi * Float64(k + 1) / Float64(sides)
        _triangle(
            layers,
            surface,
            middle,
            _p(cx + r * cos(t0), cy + r * sin(t0), z),
            _p(cx + r * cos(t1), cy + r * sin(t1), z),
            up,
            color,
        )


def _box(
    mut layers: _Layers,
    surface: Surface,
    corner: Vec3d,
    u: Vec3d,
    v: Vec3d,
    height: Float64,
    color: Vec3d,
) raises:
    """Add the sides and the top of a box with no bottom.

    The box stands on the parallelogram of `corner`, `u` and `v`. The
    vector u cross v points up.
    """
    var up = Vec3d(0.0, 0.0, height)
    var a = corner
    var b = corner + u
    var c = corner + u + v
    var d = corner + v
    var middle = (a + c) * 0.5 + up * 0.5
    var faces = [(a, b), (b, c), (c, d), (d, a)]
    for f in range(4):
        var p = faces[f][0]
        var q = faces[f][1]
        var facing = (p + q) * 0.5 + up * 0.5 - middle
        _quad(layers, surface, p, q, q + up, p + up, facing, color)
    _quad(
        layers, surface, a + up, b + up, c + up, d + up, Vec3d(0, 0, 1), color
    )


def _dark() -> Vec3d:
    """Return the color of a window or an arrow slit."""
    return _linear(22.0, 26.0, 34.0)


def _slit(
    mut layers: _Layers,
    origin: Vec3d,
    along: Vec3d,
    normal: Vec3d,
    width: Float64,
    height: Float64,
) raises:
    """Add a dark rectangle that stands proud of a wall by a hair."""
    var a = origin - along * (width / 2.0) + normal * 0.03
    var b = origin + along * (width / 2.0) + normal * 0.03
    var up = Vec3d(0.0, 0.0, height)
    _quad(layers, SLATE, a, b, b + up, a + up, normal, _dark())


def _merlon_ring(
    mut layers: _Layers, cx: Float64, cy: Float64, radius: Float64, z: Float64
) raises:
    """Add merlons around a circle, each facing outward, on a floor at z."""
    var count = max(3, Int(2.0 * pi * radius / 1.7))
    var stone = surface_color(STONE)
    # There are three merlons at least, so the loop always runs.
    for k in range(count):  # pragma: no branch
        var theta = 2.0 * pi * (Float64(k) + 0.5) / Float64(count)
        var radial = Vec3d(cos(theta), sin(theta), 0.0)
        var tangent = Vec3d(-sin(theta), cos(theta), 0.0)
        var corner = _p(cx, cy, z) + radial * (radius - 0.25) - tangent * 0.4
        _box(
            layers,
            STONE,
            corner,
            radial * 0.5,
            tangent * 0.8,
            _MERLON,
            layers.tone(stone, 0.06),
        )


def _round_tower(mut layers: _Layers, tower: Tower, sides: Int) raises:
    """Add a round tower: plinth, shaft, string course, slits and a top."""
    var cx = tower.center.x.value
    var cy = tower.center.y.value
    var r = tower.radius.value
    var h = tower.height.value
    var top = h - 0.5
    if tower.roof == PARAPET:
        top = h - 1.7
    _frustum(layers, STONE, cx, cy, r + 0.35, -_FOOT, r, 1.0, sides, 0.0, 0.05)
    _frustum(layers, BRICK, cx, cy, r, 1.0, r, top, sides, 0.0, 0.10)
    var course = h * 0.5
    _frustum(
        layers,
        STONE,
        cx,
        cy,
        r + 0.08,
        course - 0.15,
        r + 0.08,
        course + 0.15,
        sides,
        0.0,
        0.05,
    )
    var level = 0
    var z = 3.2
    while z + 1.0 < top - 0.8:
        for j in range(4):
            var theta = 0.6 + 0.8 * Float64(level) + pi * Float64(j) / 2.0
            var radial = Vec3d(cos(theta), sin(theta), 0.0)
            var tangent = Vec3d(-sin(theta), cos(theta), 0.0)
            _slit(
                layers,
                _p(cx, cy, z) + radial * (r + 0.0),
                tangent,
                radial,
                0.28,
                1.0,
            )
        level += 1
        z += 4.2
    if tower.roof == PARAPET:
        _frustum(
            layers,
            STONE,
            cx,
            cy,
            r,
            h - 1.7,
            r + 0.55,
            h - 1.0,
            sides,
            0.0,
            0.04,
        )
        _frustum(
            layers,
            STONE,
            cx,
            cy,
            r + 0.55,
            h - 1.0,
            r + 0.55,
            h,
            sides,
            0.0,
            0.04,
        )
        _disc(layers, STONE, cx, cy, r + 0.55, h, sides, surface_color(STONE))
        _merlon_ring(layers, cx, cy, r + 0.55, h)
    else:
        var rise = tower.roof_rise.value
        _frustum(
            layers, STONE, cx, cy, r, h - 0.5, r + 0.3, h, sides, 0.0, 0.04
        )
        _frustum(
            layers, SLATE, cx, cy, r + 0.3, h, 0.0, h + rise, sides, 0.0, 0.12
        )
        layers.builders[STONE.value].tube(
            _p(cx, cy, h + rise),
            _p(cx, cy, h + rise + 1.4),
            0.07,
            0.0,
            5,
            surface_color(STONE),
            surface_color(STONE),
        )


struct _Frame(ImplicitlyCopyable):
    """The rectangle of a block in the plan: a center and two directions."""

    var cx: Float64
    var cy: Float64
    var length: Float64
    var width: Float64
    # The unit direction of the length, and the unit direction across it.
    var a: Vec3d
    var c: Vec3d

    def __init__(
        out self,
        cx: Float64,
        cy: Float64,
        length: Float64,
        width: Float64,
        heading: Float64,
    ):
        self.cx = cx
        self.cy = cy
        self.length = length
        self.width = width
        self.a = Vec3d(cos(heading), sin(heading), 0.0)
        self.c = Vec3d(-sin(heading), cos(heading), 0.0)

    def at(self, along: Float64, across: Float64, z: Float64) -> Vec3d:
        """Return a point from its place along and across the rectangle."""
        return _p(self.cx, self.cy, z) + self.a * along + self.c * across

    def start(self, face: Int, z: Float64) -> Vec3d:
        """Return the start of a face, going counterclockwise."""
        var u = self.length / 2.0
        var v = self.width / 2.0
        if face == 0:
            return self.at(-u, -v, z)
        if face == 1:
            return self.at(u, -v, z)
        if face == 2:
            return self.at(u, v, z)
        return self.at(-u, v, z)

    def direction(self, face: Int) -> Vec3d:
        """Return the unit direction along a face."""
        if face == 0:
            return self.a
        if face == 1:
            return self.c
        if face == 2:
            return self.a * -1.0
        return self.c * -1.0

    def size(self, face: Int) -> Float64:
        """Return the length of a face."""
        if face % 2 == 0:
            return self.length
        return self.width

    def outward(self, face: Int) -> Vec3d:
        """Return the unit normal of a face, pointing out."""
        return self.direction(face).cross(Vec3d(0.0, 0.0, 1.0))


def _gate(mut layers: _Layers, frame: _Frame) raises:
    """Add a pointed-round gate arch in the face at the end of the length."""
    var s = frame.start(1, 0.0)
    var d = frame.direction(1)
    var n = frame.outward(1)
    var mid = frame.width / 2.0
    var spring = 3.6
    var radius = 1.6
    var dark = _dark()
    var stone = surface_color(STONE)
    var up = Vec3d(0.0, 0.0, 1.0)
    var base = s + d * mid + n * 0.05
    _quad(
        layers,
        SLATE,
        base - d * radius,
        base + d * radius,
        base + d * radius + up * spring,
        base - d * radius + up * spring,
        n,
        dark,
    )
    var steps = 12
    var hub = base + up * spring
    for k in range(steps):  # pragma: no branch
        var t0 = pi * Float64(k) / Float64(steps)
        var t1 = pi * Float64(k + 1) / Float64(steps)
        var p0 = hub + d * (radius * cos(t0)) + up * (radius * sin(t0))
        var p1 = hub + d * (radius * cos(t1)) + up * (radius * sin(t1))
        _triangle(layers, SLATE, hub, p0, p1, n, dark)
        var q0 = (
            hub
            + d * ((radius + 0.45) * cos(t0))
            + up * ((radius + 0.45) * sin(t0))
        )
        var q1 = (
            hub
            + d * ((radius + 0.45) * cos(t1))
            + up * ((radius + 0.45) * sin(t1))
        )
        var rim = n * -0.01
        _quad(layers, STONE, p0 + rim, p1 + rim, q1 + rim, q0 + rim, n, stone)
    for side in range(2):
        var sign = Float64(2 * side - 1)
        var inner = base + d * (sign * radius) + n * -0.01
        var outer = base + d * (sign * (radius + 0.45)) + n * -0.01
        _quad(
            layers,
            STONE,
            inner,
            outer,
            outer + up * spring,
            inner + up * spring,
            n,
            stone,
        )


def _walls(
    mut layers: _Layers, frame: _Frame, height: Float64, gate: Bool
) raises:
    """Add the brick walls of a block with plinth, string course and
    windows, and a gate arch in the face at the end of the length."""
    var brick = surface_color(BRICK)
    var stone = surface_color(STONE)
    var up = Vec3d(0.0, 0.0, 1.0)
    for face in range(4):
        var s = frame.start(face, 0.0)
        var d = frame.direction(face)
        var n = frame.outward(face)
        var size = frame.size(face)
        var pieces = Int(floor(size / 2.2)) + 1
        var step = size / Float64(pieces)
        # A face has one piece at least, so the loop always runs.
        for k in range(pieces):  # pragma: no branch
            var p = s + d * (step * Float64(k)) - up * _FOOT
            var q = s + d * (step * Float64(k + 1)) - up * _FOOT
            var rise = up * (height + _FOOT)
            _quad(
                layers,
                BRICK,
                p,
                q,
                q + rise,
                p + rise,
                n,
                layers.tone(brick, 0.08),
            )
        var proud = n * 0.12
        var ledge = up * (0.9 + _FOOT)
        var p0 = s - up * _FOOT + proud
        var p1 = s + d * size - up * _FOOT + proud
        _quad(layers, STONE, p0, p1, p1 + ledge, p0 + ledge, n, stone)
        _quad(
            layers,
            STONE,
            p0 + ledge,
            p1 + ledge,
            p1 + ledge - proud,
            p0 + ledge - proud,
            up,
            stone,
        )
        var band = up * (height - 0.55)
        var b0 = s + band + n * 0.08
        var b1 = s + d * size + band + n * 0.08
        _quad(layers, STONE, b0, b1, b1 + up * 0.3, b0 + up * 0.3, n, stone)
        var count = Int(floor(size / 3.6))
        if count < 1:
            count = 1
        var spacing = size / Float64(count)
        var row = 0
        var z = 1.4
        while z + 1.7 < height - 0.9:
            for k in range(count):  # pragma: no branch
                var along = spacing * (Float64(k) + 0.5)
                var in_gate = (
                    gate
                    and face == 1
                    and row == 0
                    and abs(along - size / 2.0) < 2.6
                )
                if not in_gate:
                    var origin = s + d * along + up * z
                    var frame_color = layers.tone(stone, 0.05)
                    var f0 = origin - d * 0.7 + n * 0.02
                    var f1 = origin + d * 0.7 + n * 0.02
                    _quad(
                        layers,
                        STONE,
                        f0 - up * 0.15,
                        f1 - up * 0.15,
                        f1 + up * 1.85,
                        f0 + up * 1.85,
                        n,
                        frame_color,
                    )
                    _slit(layers, origin, d, n, 1.1, 1.7)
            row += 1
            z += _STOREY
    if gate:
        _gate(layers, frame)


def _slope_height(
    q: Float64, half: Float64, eave: Float64, ridge: Float64
) -> Float64:
    """Return the height of a gable roof at a distance q from its ridge."""
    return ridge - (ridge - eave) * q / half


def _dormer(
    mut layers: _Layers,
    frame: _Frame,
    along: Float64,
    side: Float64,
    half: Float64,
    eave: Float64,
    ridge: Float64,
) raises:
    """Add a dormer window to one slope of a gable roof."""
    var up = Vec3d(0.0, 0.0, 1.0)
    var wide = 0.8
    var wall = 1.5
    var peak = 0.6
    var qf = half * 0.62
    var zf = _slope_height(qf, half, eave, ridge)
    var zt = zf + wall + peak
    var qb = max(0.0, (ridge - zt) * half / (ridge - eave))
    var brick = surface_color(BRICK)
    var slate = surface_color(SLATE)
    var outward = frame.c * side
    var fl = frame.at(along - wide, side * qf, zf)
    var fr = frame.at(along + wide, side * qf, zf)
    var tl = fl + up * wall
    var tr = fr + up * wall
    var apex = frame.at(along, side * qf, zt)
    var back = frame.at(along, side * qb, zt)
    var bl = frame.at(along - wide, side * qb, zt)
    var br = frame.at(along + wide, side * qb, zt)
    _quad(layers, BRICK, fl, fr, tr, tl, outward, layers.tone(brick, 0.06))
    _triangle(layers, BRICK, tl, tr, apex, outward, layers.tone(brick, 0.06))
    _slit(
        layers,
        frame.at(along, side * qf, zf + 0.25),
        frame.a,
        outward,
        0.9,
        1.0,
    )
    var roof = outward + up
    _triangle(layers, SLATE, tl, apex, back, roof, layers.tone(slate, 0.1))
    _triangle(layers, SLATE, tl, back, bl, roof, layers.tone(slate, 0.1))
    _triangle(layers, SLATE, tr, br, back, roof, layers.tone(slate, 0.1))
    _triangle(layers, SLATE, tr, back, apex, roof, layers.tone(slate, 0.1))
    _triangle(layers, BRICK, fl, tl, bl, frame.a * -1.0, brick)
    _triangle(layers, BRICK, fr, br, tr, frame.a, brick)


def _gable_roof(
    mut layers: _Layers, frame: _Frame, height: Float64, rise: Float64
) raises:
    """Add a gable roof of slate rows with end walls, a ridge cap and
    dormers."""
    var up = Vec3d(0.0, 0.0, 1.0)
    var half = frame.width / 2.0 + _OVERHANG
    var reach = frame.length / 2.0 + _OVERHANG
    var eave = height - 0.25
    var ridge = height + rise
    var slate = surface_color(SLATE)
    var rows = 8
    for side in range(2):
        var s = Float64(2 * side - 1)
        var facing = frame.c * (s * rise) + up * half
        for r in range(rows):  # pragma: no branch
            var f0 = Float64(r) / Float64(rows)
            var f1 = Float64(r + 1) / Float64(rows)
            var q0 = s * half * (1.0 - f0)
            var q1 = s * half * (1.0 - f1)
            var z0 = eave + (ridge - eave) * f0
            var z1 = eave + (ridge - eave) * f1
            _quad(
                layers,
                SLATE,
                frame.at(-reach, q0, z0),
                frame.at(reach, q0, z0),
                frame.at(reach, q1, z1),
                frame.at(-reach, q1, z1),
                facing,
                layers.tone(slate, 0.12),
            )
    var brick = surface_color(BRICK)
    for end in range(2):
        var e = Float64(2 * end - 1)
        var x = e * frame.length / 2.0
        _triangle(
            layers,
            BRICK,
            frame.at(x, -frame.width / 2.0, height),
            frame.at(x, frame.width / 2.0, height),
            frame.at(x, 0.0, ridge),
            frame.a * e,
            layers.tone(brick, 0.05),
        )
    _box(
        layers,
        STONE,
        frame.at(-reach, -0.12, ridge - 0.02),
        frame.a * (2.0 * reach),
        frame.c * 0.24,
        0.2,
        surface_color(STONE),
    )
    var count = Int(frame.length / 6.5)
    for side in range(2):
        for k in range(count):
            var along = (Float64(k) + 0.5) * frame.length / Float64(
                count
            ) - frame.length / 2.0
            _dormer(
                layers, frame, along, Float64(2 * side - 1), half, eave, ridge
            )


def _battlements(mut layers: _Layers, frame: _Frame, height: Float64) raises:
    """Add a flat roof behind a corbelled parapet of merlons."""
    var up = Vec3d(0.0, 0.0, 1.0)
    var stone = surface_color(STONE)
    var u = frame.length / 2.0
    var v = frame.width / 2.0
    var slate = surface_color(SLATE)
    _quad(
        layers,
        SLATE,
        frame.at(-u, -v, height),
        frame.at(u, -v, height),
        frame.at(u, v, height),
        frame.at(-u, v, height),
        up,
        slate,
    )
    for face in range(4):
        var s = frame.start(face, 0.0)
        var d = frame.direction(face)
        var n = frame.outward(face)
        var size = frame.size(face)
        var e = s + d * size
        _quad(
            layers,
            STONE,
            s + up * (height - 1.0),
            e + up * (height - 1.0),
            e + n * 0.45 + up * (height - 0.55),
            s + n * 0.45 + up * (height - 0.55),
            n - up,
            stone,
        )
        _quad(
            layers,
            STONE,
            s + n * 0.45 + up * (height - 0.55),
            e + n * 0.45 + up * (height - 0.55),
            e + n * 0.45 + up * height,
            s + n * 0.45 + up * height,
            n,
            stone,
        )
        _quad(
            layers,
            STONE,
            s + n * 0.45 + up * height,
            e + n * 0.45 + up * height,
            e + up * height,
            s + up * height,
            up,
            stone,
        )
        var count = max(1, Int(size / 1.7))
        var spacing = size / Float64(count)
        for k in range(count):  # pragma: no branch
            var along = spacing * (Float64(k) + 0.5)
            _box(
                layers,
                STONE,
                s + d * (along - 0.45) + n * 0.45 + up * height,
                d * 0.9,
                n * -0.5,
                _MERLON,
                layers.tone(stone, 0.06),
            )


def _square_tower(mut layers: _Layers, tower: Tower) raises:
    """Add a square tower: walls and a pyramid or a parapet."""
    var side = tower.radius.value * 2.0
    var frame = _Frame(
        tower.center.x.value, tower.center.y.value, side, side, 0.0
    )
    var h = tower.height.value
    _walls(layers, frame, h, False)
    if tower.roof == PARAPET:
        _battlements(layers, frame, h)
    else:
        var corner = tower.radius.value * sqrt(2.0) + 0.4
        _frustum(
            layers,
            SLATE,
            frame.cx,
            frame.cy,
            corner,
            h,
            0.0,
            h + tower.roof_rise.value,
            4,
            pi / 4.0,
            0.1,
        )


def _bridge(mut layers: _Layers, bridge: Bridge, water: Float64) raises:
    """Add a bridge of segmental stone arches on brick piers.

    The deck starts at `bridge.start`. `water` is the height of the water.
    """
    var up = Vec3d(0.0, 0.0, 1.0)
    var length = bridge.length().value
    var width = bridge.width.value
    var middle = bridge.point(bridge.length().scaled(0.5), Length64(0.0, METER))
    var frame = _Frame(
        middle.x.value, middle.y.value, length, width, bridge.heading.value
    )
    var brick = surface_color(BRICK)
    var stone = surface_color(STONE)
    var span = bridge.span.value
    var pier = bridge.pier.value
    var deck = water + bridge.deck_height().value
    var floor = water - 0.6
    var half = width / 2.0
    var radius = bridge.intrados_radius().value
    var outer = radius + bridge.ring.value
    var rise = bridge.rise.value
    var springing = water + bridge.springing.value
    var center_z = springing + rise - radius
    var reach = asin(min(1.0, span / 2.0 / radius))
    var steps = 12
    for i in range(bridge.spans + 1):  # pragma: no branch
        var x0 = (pier + span) * Float64(i) - length / 2.0
        _box(
            layers,
            BRICK,
            frame.at(x0, -half, floor),
            frame.a * pier,
            frame.c * width,
            deck - floor,
            layers.tone(brick, 0.06),
        )
    for i in range(bridge.spans):  # pragma: no branch
        var xc = pier + span / 2.0 + (pier + span) * Float64(i) - length / 2.0
        for j in range(steps):  # pragma: no branch
            var t0 = -reach + 2.0 * reach * Float64(j) / Float64(steps)
            var t1 = -reach + 2.0 * reach * Float64(j + 1) / Float64(steps)
            var tone = layers.tone(stone, 0.07)
            for face in range(2):
                var side = Float64(2 * face - 1)
                var proud = side * (half + 0.02)
                _quad(
                    layers,
                    STONE,
                    frame.at(
                        xc + radius * sin(t0),
                        proud,
                        center_z + radius * cos(t0),
                    ),
                    frame.at(
                        xc + radius * sin(t1),
                        proud,
                        center_z + radius * cos(t1),
                    ),
                    frame.at(
                        xc + outer * sin(t1), proud, center_z + outer * cos(t1)
                    ),
                    frame.at(
                        xc + outer * sin(t0), proud, center_z + outer * cos(t0)
                    ),
                    frame.c * side,
                    tone,
                )
            var p0 = frame.at(
                xc + radius * sin(t0), -half, center_z + radius * cos(t0)
            )
            var p1 = frame.at(
                xc + radius * sin(t1), -half, center_z + radius * cos(t1)
            )
            var q0 = frame.at(
                xc + radius * sin(t0), half, center_z + radius * cos(t0)
            )
            var q1 = frame.at(
                xc + radius * sin(t1), half, center_z + radius * cos(t1)
            )
            var hub = frame.at(xc, 0.0, center_z)
            _quad(
                layers, STONE, p0, p1, q1, q0, hub - (p0 + q1) * 0.5, tone * 0.8
            )
        var columns = 10
        for k in range(columns):  # pragma: no branch
            var x_a = -span / 2.0 + span * Float64(k) / Float64(columns)
            var x_b = -span / 2.0 + span * Float64(k + 1) / Float64(columns)
            var z_a = center_z + sqrt(max(outer * outer - x_a * x_a, 0.0))
            var z_b = center_z + sqrt(max(outer * outer - x_b * x_b, 0.0))
            for face in range(2):
                var side = Float64(2 * face - 1)
                _quad(
                    layers,
                    BRICK,
                    frame.at(xc + x_a, side * half, z_a),
                    frame.at(xc + x_b, side * half, z_b),
                    frame.at(xc + x_b, side * half, deck),
                    frame.at(xc + x_a, side * half, deck),
                    frame.c * side,
                    layers.tone(brick, 0.07),
                )
    var lane = half - 0.45
    _quad(
        layers,
        GRAVEL,
        frame.at(-length / 2.0, -lane, deck + 0.01),
        frame.at(length / 2.0, -lane, deck + 0.01),
        frame.at(length / 2.0, lane, deck + 0.01),
        frame.at(-length / 2.0, lane, deck + 0.01),
        up,
        surface_color(GRAVEL),
    )
    var wall = bridge.parapet.value
    for face in range(2):
        var side = Float64(2 * face - 1)
        var edge = side * lane
        var inner = side * half
        var low = min(edge, inner)
        _box(
            layers,
            BRICK,
            frame.at(-length / 2.0, low, deck),
            frame.a * length,
            frame.c * 0.45,
            wall,
            layers.tone(brick, 0.05),
        )
        _box(
            layers,
            STONE,
            frame.at(-length / 2.0, low - 0.04, deck + wall),
            frame.a * length,
            frame.c * 0.53,
            0.12,
            stone,
        )


def _ring(
    mut layers: _Layers,
    surface: Surface,
    inner: Vec3d,
    inner_x: Float64,
    inner_y: Float64,
    outer: Vec3d,
    outer_x: Float64,
    outer_y: Float64,
    steps: Int,
    spread: Float64,
) raises:
    """Add a horizontal or sloping strip between two ellipses.

    An ellipse is a center (x, y, z) and two semi-axes. The strip faces up.
    """
    var base = surface_color(surface)
    var up = Vec3d(0.0, 0.0, 1.0)
    for k in range(steps):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(k) / Float64(steps)
        var t1 = 2.0 * pi * Float64(k + 1) / Float64(steps)
        _quad(
            layers,
            surface,
            _p(
                inner.x + inner_x * cos(t0),
                inner.y + inner_y * sin(t0),
                inner.z,
            ),
            _p(
                inner.x + inner_x * cos(t1),
                inner.y + inner_y * sin(t1),
                inner.z,
            ),
            _p(
                outer.x + outer_x * cos(t1),
                outer.y + outer_y * sin(t1),
                outer.z,
            ),
            _p(
                outer.x + outer_x * cos(t0),
                outer.y + outer_y * sin(t0),
                outer.z,
            ),
            up,
            layers.tone(base, spread),
        )


def _revetment(
    mut layers: _Layers, moat: Moat, bed: Float64, steps: Int
) raises:
    """Add the brick wall that holds the island, from the bed to the ground."""
    var brick = surface_color(BRICK)
    var cx = moat.island_center.x.value
    var cy = moat.island_center.y.value
    var a = moat.island_semi_x.value
    var b = moat.island_semi_y.value
    var up = Vec3d(0.0, 0.0, 1.0)
    for k in range(steps):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(k) / Float64(steps)
        var t1 = 2.0 * pi * Float64(k + 1) / Float64(steps)
        var p0 = _p(cx + a * cos(t0), cy + b * sin(t0), bed)
        var p1 = _p(cx + a * cos(t1), cy + b * sin(t1), bed)
        var rise = up * (-bed)
        var facing = _p(cos((t0 + t1) / 2.0) * b, sin((t0 + t1) / 2.0) * a, 0.0)
        _quad(
            layers,
            BRICK,
            p0,
            p1,
            p1 + rise,
            p0 + rise,
            facing,
            layers.tone(brick, 0.08),
        )


def _ground(
    mut layers: _Layers, plan: CastlePlan, steps: Int, water_mesh: Bool
) raises:
    """Add the island, the water, the bank, the path and the meadow."""
    var moat = plan.moat.copy()
    var up = Vec3d(0.0, 0.0, 1.0)
    var water = -moat.freeboard.value
    var bed = water - moat.depth.value
    var cx = moat.center.x.value
    var cy = moat.center.y.value
    var ax = moat.semi_x.value
    var ay = moat.semi_y.value
    var ix = moat.island_center.x.value
    var iy = moat.island_center.y.value
    var iax = moat.island_semi_x.value
    var iay = moat.island_semi_y.value
    var lawn = surface_color(LAWN)
    for k in range(steps):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(k) / Float64(steps)
        var t1 = 2.0 * pi * Float64(k + 1) / Float64(steps)
        _triangle(
            layers,
            LAWN,
            _p(ix, iy, 0.0),
            _p(ix + iax * cos(t0), iy + iay * sin(t0), 0.0),
            _p(ix + iax * cos(t1), iy + iay * sin(t1), 0.0),
            up,
            layers.tone(lawn, 0.06),
        )
    _disc(layers, GRAVEL, 0.0, 0.0, 5.5, 0.03, steps, surface_color(GRAVEL))
    _revetment(layers, moat, bed, steps)
    if water_mesh:
        _ring(
            layers,
            WATER,
            _p(ix, iy, water),
            iax,
            iay,
            _p(cx, cy, water),
            ax,
            ay,
            steps,
            0.04,
        )
    _ring(
        layers,
        LAWN,
        _p(cx, cy, water),
        ax,
        ay,
        _p(cx, cy, 0.0),
        ax + 2.4,
        ay + 2.4,
        steps,
        0.05,
    )
    _ring(
        layers,
        LAWN,
        _p(cx, cy, 0.0),
        ax + 2.4,
        ay + 2.4,
        _p(cx, cy, 0.0),
        ax + 5.0,
        ay + 5.0,
        steps,
        0.05,
    )
    _ring(
        layers,
        GRAVEL,
        _p(cx, cy, 0.0),
        ax + 5.0,
        ay + 5.0,
        _p(cx, cy, 0.0),
        ax + 8.0,
        ay + 8.0,
        steps,
        0.04,
    )
    _ring(
        layers,
        LAWN,
        _p(cx, cy, 0.0),
        ax + 8.0,
        ay + 8.0,
        _p(cx, cy, 0.0),
        ax + 3000.0,
        ay + 3000.0,
        steps,
        0.05,
    )


def foliage_color(index: Int) -> Vec3d:
    """Return the linear color of an autumn crown.

    Args:
        index: Which of the six colors, 0 to 5. Another index is taken
            modulo six.

    Returns:
        Orange, amber, red, olive, deep conifer green or gold.
    """
    var k = index % 6
    if k == 0:
        return _linear(222.0, 120.0, 32.0)
    if k == 1:
        return _linear(236.0, 176.0, 44.0)
    if k == 2:
        return _linear(178.0, 66.0, 38.0)
    if k == 3:
        return _linear(112.0, 128.0, 52.0)
    if k == 4:
        return _linear(30.0, 62.0, 42.0)
    return _linear(232.0, 200.0, 70.0)


def _crown(
    mut layers: _Layers,
    x: Float64,
    y: Float64,
    z: Float64,
    radius: Float64,
    squash: Float64,
    color: Vec3d,
):
    """Add a squashed ball of foliage, smooth shaded."""
    var bands = 6
    var around = 8
    for i in range(bands):  # pragma: no branch
        var p0 = pi * Float64(i) / Float64(bands)
        var p1 = pi * Float64(i + 1) / Float64(bands)
        for j in range(around):  # pragma: no branch
            var t0 = 2.0 * pi * Float64(j) / Float64(around)
            var t1 = 2.0 * pi * Float64(j + 1) / Float64(around)
            var tone = layers.tone(color, 0.10)
            var n00 = Vec3d(
                sin(p0) * cos(t0), sin(p0) * sin(t0), cos(p0) / squash
            ).normalized()
            var n01 = Vec3d(
                sin(p0) * cos(t1), sin(p0) * sin(t1), cos(p0) / squash
            ).normalized()
            var n10 = Vec3d(
                sin(p1) * cos(t0), sin(p1) * sin(t0), cos(p1) / squash
            ).normalized()
            var n11 = Vec3d(
                sin(p1) * cos(t1), sin(p1) * sin(t1), cos(p1) / squash
            ).normalized()
            var a = _p(
                x + radius * sin(p0) * cos(t0),
                y + radius * sin(p0) * sin(t0),
                z + radius * squash * cos(p0),
            )
            var b = _p(
                x + radius * sin(p0) * cos(t1),
                y + radius * sin(p0) * sin(t1),
                z + radius * squash * cos(p0),
            )
            var c = _p(
                x + radius * sin(p1) * cos(t1),
                y + radius * sin(p1) * sin(t1),
                z + radius * squash * cos(p1),
            )
            var d = _p(
                x + radius * sin(p1) * cos(t0),
                y + radius * sin(p1) * sin(t0),
                z + radius * squash * cos(p1),
            )
            layers.builders[FOLIAGE.value].smooth_triangle(
                a, c, b, n00, n11, n01, tone, tone, tone
            )
            layers.builders[FOLIAGE.value].smooth_triangle(
                a, d, c, n00, n10, n11, tone, tone, tone
            )


def _wood(mut layers: _Layers, plan: CastlePlan, options: CastleOptions) raises:
    """Add a wood of autumn crowns and conifers beyond the path."""
    var moat = plan.moat.copy()
    var trunk = surface_color(TRUNK)
    for _ in range(options.trees):
        var theta = 2.0 * pi * layers.random.next()
        var depth = layers.random.next()
        var size = 0.8 + 0.7 * layers.random.next()
        var palette = Int(layers.random.next() * 4.0)
        var chance = layers.random.next()
        var reach_x = moat.semi_x.value + 11.0 + depth * 260.0
        var reach_y = moat.semi_y.value + 11.0 + depth * 260.0
        var x = moat.center.x.value + reach_x * cos(theta)
        var y = moat.center.y.value + reach_y * sin(theta)
        var away_x = x - options.clearing.x.value
        var away_y = y - options.clearing.y.value
        if (
            sqrt(away_x * away_x + away_y * away_y)
            < options.clearing_radius.value
        ):
            continue
        var conifer_chance = 0.1 + 0.4 * depth
        if sin(theta) > 0.2:
            conifer_chance += 0.25
        if chance < conifer_chance:
            var height = (10.0 + 6.0 * size) * 0.8
            layers.builders[TRUNK.value].tube(
                _p(x, y, 0.0), _p(x, y, 2.0), 0.2 * size, 0.0, 5, trunk, trunk
            )
            for tier in range(3):
                var z = 1.8 + height * 0.26 * Float64(tier)
                var r = (2.9 - 0.7 * Float64(tier)) * size
                _frustum_colored(
                    layers,
                    FOLIAGE,
                    foliage_color(4),
                    x,
                    y,
                    r,
                    z,
                    0.0,
                    z + height * 0.42,
                    8,
                    0.0,
                    0.10,
                )
        else:
            var crown = (3.4 + 1.8 * layers.random.next()) * size
            var stem = 3.0 + 2.0 * size
            layers.builders[TRUNK.value].tube(
                _p(x, y, 0.0),
                _p(x, y, stem + crown * 0.4),
                0.28 * size,
                0.0,
                5,
                trunk,
                trunk,
            )
            _crown(
                layers,
                x,
                y,
                stem + crown * 0.55,
                crown,
                0.85,
                foliage_color(palette),
            )


def _material(surface: Surface) raises -> Material:
    """Return the material of a surface: vertex colors with a roughness."""
    var roughness = Float32(0.9)
    if surface == STONE:
        roughness = 0.82
    elif surface == SLATE:
        roughness = 0.6
    elif surface == WATER:
        roughness = 0.04
    elif surface == GRAVEL:
        roughness = 0.97
    var material = standard_material(Color(255, 255, 255), roughness=roughness)
    material.vertex_colors = True
    return material


def add_castle(
    mut scene: Scene,
    mut assets: Assets,
    plan: CastlePlan,
    options: CastleOptions,
) raises -> RenderedCastle:
    """Add meshes of a castle plan to a scene.

    The castle node's user data records the plan's name and what the view
    leaves out: interiors, the thickness of walls and the structure.

    Args:
        scene: The scene to add the castle's node and meshes to.
        assets: The store for the geometries and materials.
        plan: The plan. It is checked first.
        options: The facets, the trees, the seed and the shadows.

    Returns:
        The castle's node and the number of meshes and triangles.

    Raises:
        Error: If the plan is not sound, there are fewer than six facets, or
            the tree count is negative.
    """
    plan.check()
    if options.sides < 6:
        raise Error("A round tower needs at least six facets")
    if options.trees < 0:
        raise Error("A wood cannot have fewer than no trees")
    var layers = _Layers(options.seed)
    for i in range(len(plan.towers)):  # pragma: no branch
        ref tower = plan.towers[i]
        if tower.shape == ROUND:
            _round_tower(layers, tower, options.sides)
        else:
            _square_tower(layers, tower)
    for i in range(len(plan.blocks)):
        ref block = plan.blocks[i]
        var frame = _Frame(
            block.center.x.value,
            block.center.y.value,
            block.length.value,
            block.width.value,
            block.heading.value,
        )
        var gate = block.roof == PARAPET
        _walls(layers, frame, block.height.value, gate)
        if gate:
            _battlements(layers, frame, block.height.value)
        else:
            _gable_roof(
                layers, frame, block.height.value, block.roof_rise.value
            )
    _bridge(layers, plan.bridge, -plan.moat.freeboard.value)
    _ground(layers, plan, 96, options.water)
    _wood(layers, plan, options)
    var root_node = Object3D()
    root_node.name = plan.name
    root_node.user_data.set_string("model", plan.name)
    root_node.user_data.set_string(
        "dropped",
        (
            "interiors, wall thickness, openings through walls and"
            " structural data; every dimension is estimated"
        ),
    )
    var root = scene.add(root_node^)
    var meshes = 0
    var triangles = 0
    for k in range(_SURFACES):  # pragma: no branch
        ref builder = layers.builders[k]
        if builder.count() == 0:
            continue
        triangles += builder.count()
        var node = Object3D()
        node.name = Surface(k).name()
        node.parent = root
        var mesh_node = scene.add(node^)
        var cast = options.shadows and k != WATER.value
        scene.add_mesh(
            Mesh(
                assets.geometries.add(builder.geometry()),
                assets.materials.add(_material(Surface(k))),
                mesh_node,
                cast_shadow=cast,
                receive_shadow=options.shadows,
            )
        )
        meshes += 1
    return RenderedCastle(root, meshes, triangles)
