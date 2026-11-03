# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The trees of the domain: branching trunks with cards of leaves.

A tree is grown by `TreeGenerator`: a trunk that forks into boughs, branches
and twigs, each a tube. The bark is that skeleton. The leaves are cards, each
a small spray of leaves cut out by its alpha, set at the thin ends of the
twigs. A broadleaf tree wears a card in every direction, with normals bent
outward so that the crown shades like a mass and not like a heap of cards. A
conifer wears sprays of needles along its branches.

A few shapes are grown once and drawn many times. Each is an instanced mesh,
and each instance has its own place, turn, size and color. The color of an
instance tints the gray leaves, so that a wood in autumn is orange, gold, red
and green.

The woods are an illustration. The survey does not say where the trees are,
and the plan says nothing of them. They follow the photograph: a meadow open
to the north, broadleaf trees close to the moat, and dark conifers behind.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId
from core.scene import Scene
from extensions.castle.kinds import FOLIAGE
from extensions.castle.look import CastleLook
from extensions.castle.parts import tri_uv, unit_noise
from extensions.castle.render import (
    ground_height,
    offset_ring,
    resample_ring,
    shore_ring,
)
from extensions.castle.plan import (
    CastlePlan,
    Point,
    convex_hull,
    distance_to_outline,
    point,
    polygon_contains,
)
from extensions.visual.mesh import MeshBuilder
from generators.tree import TreeGenerator, TreeParameters, TreeTube
from generators.utils import Vec3d
from math.matrix4 import rotation_y, scaling, translation
from objects.instanced_mesh import InstancedMesh
from render.framebuffer import Color
from std.math import atan2, cos, floor, pi, sin, sqrt
from units.si import (
    Angle,
    DEGREE,
    InverseLength,
    Length,
    METER,
    PER_METER,
    RADIAN,
)


@fieldwise_init
struct TreeShape(Movable):
    """One grown tree: its bark and its leaves."""

    # The bark, as a geometry with positions and normals.
    var bark: BufferGeometry
    # The leaf cards, with positions, normals, texture coordinates and colors.
    var leaves: BufferGeometry
    # The height of the highest leaf over the foot, in meters.
    var height: Float64


def _zup(p: Vec3d) -> Vec3d:
    """Return a point of the y-up frame in the z-up frame of the builder."""
    return Vec3d(p.x, -p.z, p.y)


def _unit_or(v: Vec3d, fallback: Vec3d) -> Vec3d:
    """Return a vector scaled to unit length, or the fallback if it has no
    length."""
    if v.length() < 1e-6:
        return fallback
    return v.normalized()


def _side(n: Vec3d, hint: Vec3d) -> Vec3d:
    """Return the unit vector at right angles to both arguments, or east if
    they are parallel."""
    return _unit_or(n.cross(hint), Vec3d(1, 0, 0))


def _emit_card(
    mut mesh: MeshBuilder,
    center: Vec3d,
    n: Vec3d,
    right: Vec3d,
    spine: Vec3d,
    size: Float64,
    outward: Vec3d,
    r3: Float64,
    r5: Float64,
):
    """Add one card of leaves, a square of the given size in the plane of
    `right` and `spine`, with its normal bent outward."""
    var half = size / 2
    var bent = _zup((n + outward * 0.8).normalized())
    var a = _zup(center - right * half - spine * half)
    var b = _zup(center + right * half - spine * half)
    var c = _zup(center + right * half + spine * half)
    var d = _zup(center - right * half + spine * half)
    var shade = 0.7 + 0.3 * r5
    var color = Vec3d(shade, shade * (0.94 + 0.06 * r3), shade * 0.9)
    tri_uv(
        mesh,
        a,
        b,
        c,
        bent,
        bent,
        bent,
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        color,
    )
    tri_uv(
        mesh,
        a,
        c,
        d,
        bent,
        bent,
        bent,
        (0.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
        color,
    )


def _cards(
    tubes: List[TreeTube],
    seed: Int,
    card: Float64,
    per_ring: Int,
    twig: Float64,
    step: Int,
    needles: Bool,
) raises -> Tuple[BufferGeometry, Float64]:
    """Return the cards of leaves of a skeleton, and the height they reach.

    A card sits at each ring of a tube that is thinner than `twig`. A needle
    spray lies along the branch. A leaf card faces away from the middle of
    the crown, turned a little at random.
    """
    var anchors = List[Vec3d]()
    var tangents = List[Vec3d]()
    for at in range(len(tubes)):
        var k = 0
        while k < len(tubes[at].rings):
            if tubes[at].rings[k].radius <= twig:
                anchors.append(tubes[at].rings[k].position)
                tangents.append(tubes[at].rings[k].tangent)
            k += step
    var crown = Vec3d(0, 0, 0)
    var top = Float64(0)
    for anchor in anchors:
        crown = crown + anchor
        top = max(top, anchor.y)
    if len(anchors) > 0:
        crown = crown * (1.0 / Float64(len(anchors)))
    var mesh = MeshBuilder()
    var up = Vec3d(0, 1, 0)
    for i in range(len(anchors)):
        for j in range(per_ring):
            var r1 = unit_noise(Float64(i), Float64(j), seed)
            var r2 = unit_noise(Float64(i) + 17.0, Float64(j), seed + 1)
            var r3 = unit_noise(Float64(i) + 31.0, Float64(j), seed + 2)
            var r4 = unit_noise(Float64(i) + 47.0, Float64(j), seed + 3)
            var r5 = unit_noise(Float64(i) + 61.0, Float64(j), seed + 4)
            var size = card * (0.75 + 0.5 * r4)
            var center = anchors[i] + Vec3d(r1 - 0.5, r2 - 0.5, r3 - 0.5) * (
                card * 0.8
            )
            var outward = _unit_or(center - crown, up)
            var random = _unit_or(Vec3d(2 * r1 - 1, 2 * r2 - 1, 2 * r3 - 1), up)
            var n: Vec3d
            var right: Vec3d
            var spine: Vec3d
            if needles:
                # The spray lies along the branch, leaning with the weight of
                # its needles, and faces up.
                n = (up + random * 0.5).normalized()
                right = _side(tangents[i], n)
                spine = n.cross(right)
                center = center + spine * (size * 0.4)
            else:
                n = (outward * 0.65 + random * 0.35).normalized()
                right = _side(n, up)
                spine = n.cross(right)
            _emit_card(mesh, center, n, right, spine, size, outward, r3, r5)
    return (mesh.geometry(), top + card)


def broadleaf(seed: Int, detail: Float64) raises -> TreeShape:
    """Grow a broadleaf tree of about twenty meters, with a round crown.

    Args:
        seed: The seed of the branching.
        detail: One for a tree seen from near, less for a tree far away. It
            sets the number of boughs and the size of a card.

    Returns:
        The tree, with its foot at the origin and its trunk along y.

    Raises:
        Error: If the tree cannot be grown.
    """
    var p = TreeParameters()
    p.seed = seed
    p.levels = 4
    p.trunk_length = Length(
        Float32(12.0 + 4.0 * unit_noise(Float64(seed), 1.0, 9)), METER
    )
    p.trunk_radius = Length(0.55, METER)
    p.children = [5, 9, 6]
    if detail < 0.6:
        p.children = [4, 6, 4]
    p.branch_angle = [Angle(52, DEGREE), Angle(58, DEGREE), Angle(62, DEGREE)]
    p.length_ratio = 0.78
    p.section_length = Length(2.0, METER)
    p.radial_segments = 6
    p.min_radius = Length(0.02, METER)
    p.min_length = Length(0.8, METER)
    p.trunk_clear = 0.3
    p.check()
    var generator = TreeGenerator(p^)
    var tubes = generator.tubes()
    var found = _cards(tubes, seed, 1.2 / sqrt(detail), 5, 0.09, 1, False)
    return TreeShape(generator.build(), found[0].clone(), found[1])


def conifer(seed: Int, detail: Float64) raises -> TreeShape:
    """Grow a conifer of about twenty-five meters, a narrow cone with
    drooping branches.

    Args:
        seed: The seed of the branching.
        detail: One for a tree seen from near, less for a tree far away.

    Returns:
        The tree, with its foot at the origin and its trunk along y.

    Raises:
        Error: If the tree cannot be grown.
    """
    var p = TreeParameters()
    p.seed = seed
    p.levels = 3
    p.trunk_length = Length(
        Float32(22.0 + 5.0 * unit_noise(Float64(seed), 2.0, 9)), METER
    )
    p.trunk_radius = Length(0.4, METER)
    p.children = [30, 6]
    if detail < 0.6:
        p.children = [18, 4]
    p.branch_angle = [Angle(80, DEGREE), Angle(50, DEGREE)]
    p.angle_variance = Angle(8, DEGREE)
    p.length_ratio = 0.3
    p.branch_length_falloff = 0.85
    p.taper = 0.85
    p.droop = InverseLength(0.2, PER_METER)
    p.up_pull = 0.05
    p.section_length = Length(1.5, METER)
    p.radial_segments = 5
    p.min_radius = Length(0.02, METER)
    p.min_length = Length(0.8, METER)
    p.child_start = 0.15
    p.trunk_clear = 0.1
    p.check()
    var generator = TreeGenerator(p^)
    var tubes = generator.tubes()
    var found = _cards(tubes, seed, 2.2 / sqrt(detail), 3, 0.12, 1, True)
    return TreeShape(generator.build(), found[0].clone(), found[1])


@fieldwise_init
struct _Spot(Copyable, Movable):
    """Where one tree stands, and how it looks."""

    # The place in the plan, in meters east and north.
    var x: Float64
    var y: Float64
    # The height of the ground over the ground of the island.
    var z: Float64
    # Which shape of tree it is.
    var variant: Int
    # How much the shape is scaled.
    var size: Float64
    # How far it is turned about its trunk, in radians.
    var turn: Float64
    # The tint of its leaves.
    var color: Color


# The shapes that are grown: four broadleaf and three conifers for the near
# woods, then two and two for the far woods.
comptime _NEAR_BROAD = 4
comptime _NEAR_CONIFER = 3
comptime _FAR_BROAD = 2
comptime _FAR_CONIFER = 2


def _autumn(pick: Float64, shade: Float64) -> Color:
    """Return the tint of a broadleaf tree in autumn."""
    var index = Int(pick * 6.0) % 6
    var r = 255
    var g = 150
    var b = 50
    if index == 1:
        r = 255
        g = 200
        b = 70
    elif index == 2:
        r = 235
        g = 95
        b = 45
    elif index == 3:
        r = 170
        g = 178
        b = 62
    elif index == 4:
        r = 215
        g = 170
        b = 55
    elif index == 5:
        r = 250
        g = 125
        b = 40
    return Color(
        UInt8(Int(Float64(r) * shade)),
        UInt8(Int(Float64(g) * shade)),
        UInt8(Int(Float64(b) * shade)),
    )


def _spots(
    plan: CastlePlan,
    keep_x: Float64,
    keep_y: Float64,
    keep_radius: Float64,
    seed: Int,
) raises -> List[_Spot]:
    """Return where the trees stand.

    The wood is thin near the moat and thick beyond. A meadow is left open to
    the north, behind the castle, and nothing stands within `keep_radius` of
    the point `keep_x`, `keep_y`.
    """
    var hull = convex_hull(plan.moat.outline)
    var low_x = Float64(1.0e30)
    var low_y = Float64(1.0e30)
    var high_x = Float64(-1.0e30)
    var high_y = Float64(-1.0e30)
    for corner in plan.moat.outline:
        low_x = min(low_x, corner.x.value)
        low_y = min(low_y, corner.y.value)
        high_x = max(high_x, corner.x.value)
        high_y = max(high_y, corner.y.value)
    var middle_x = (low_x + high_x) / 2
    var middle_y = (low_y + high_y) / 2
    var ground = plan.ground_level.value - plan.island_level.value
    var spots = List[_Spot]()
    for far in range(2):
        var spacing = 8.0 if far == 0 else 16.0
        var reach_in = 0.0 if far == 0 else 125.0
        var reach_out = 125.0 if far == 0 else 320.0
        var columns = Int(2.0 * reach_out / spacing)
        for row in range(columns):
            for column in range(columns):
                var jx = unit_noise(Float64(column), Float64(row), seed + far)
                var jy = unit_noise(
                    Float64(column), Float64(row), seed + 2 + far
                )
                var x = middle_x - reach_out + (Float64(column) + jx) * spacing
                var y = middle_y - reach_out + (Float64(row) + jy) * spacing
                var away = sqrt(
                    (x - middle_x) * (x - middle_x)
                    + (y - middle_y) * (y - middle_y)
                )
                if away < reach_in or away >= reach_out:
                    continue
                var at = point(x, y)
                if polygon_contains(hull, at):
                    continue
                var distance = distance_to_outline(plan.moat.outline, at).value
                if distance < 11.0:
                    continue
                var gap = sqrt(
                    (x - keep_x) * (x - keep_x) + (y - keep_y) * (y - keep_y)
                )
                if gap < keep_radius:
                    continue
                var odds = min(1.0, (distance - 11.0) / 30.0) * 0.85
                var bearing = atan2(y - middle_y, x - middle_x)
                # A meadow is left open to the north, behind the castle.
                if bearing > 0.55 and bearing < 2.6 and away < 85.0:
                    odds = 0.0
                if unit_noise(x, y, seed + 4) > odds:
                    continue
                var north = max(0.0, sin(bearing))
                var share = 0.2 + 0.45 * north
                var variant: Int
                var size: Float64
                var color: Color
                var pick = unit_noise(x, y, seed + 5)
                var shade = 0.8 + 0.3 * unit_noise(y, x, seed + 6)
                if unit_noise(x, y, seed + 7) < share:
                    # A conifer: dark green.
                    var tone = 0.75 + 0.5 * pick
                    color = Color(
                        UInt8(Int(46.0 * tone)),
                        UInt8(Int(84.0 * tone)),
                        UInt8(Int(52.0 * tone)),
                    )
                    if far == 0:
                        variant = _NEAR_BROAD + Int(pick * 3.0) % _NEAR_CONIFER
                    else:
                        variant = (
                            _NEAR_BROAD
                            + _NEAR_CONIFER
                            + _FAR_BROAD
                            + Int(pick * 2.0) % _FAR_CONIFER
                        )
                    size = 0.6 + 0.4 * unit_noise(x, y, seed + 8)
                else:
                    color = _autumn(pick, shade)
                    if far == 0:
                        variant = Int(pick * 4.0) % _NEAR_BROAD
                    else:
                        variant = (
                            _NEAR_BROAD
                            + _NEAR_CONIFER
                            + Int(pick * 2.0) % _FAR_BROAD
                        )
                    size = 0.55 + 0.35 * unit_noise(x, y, seed + 8)
                spots.append(
                    _Spot(
                        x,
                        y,
                        ground,
                        variant,
                        size,
                        2.0 * pi * unit_noise(x, y, seed + 9),
                        color,
                    )
                )
    # Trees of the courtyard garden, in the colors of the autumn.
    spots.append(_Spot(8.0, 44.0, 0.0, 1, 0.26, 0.5, _autumn(0.05, 1.0)))
    spots.append(_Spot(14.0, 36.0, 0.0, 2, 0.17, 2.0, _autumn(0.45, 1.0)))
    return spots^


def plant_trees(
    mut scene: Scene,
    mut assets: Assets,
    look: CastleLook,
    plan: CastlePlan,
    node: NodeId,
    keep_x: Float64,
    keep_y: Float64,
    keep_radius: Float64,
    seed: Int = 7,
) raises -> Int:
    """Grow the trees of the domain and plant them round the moat.

    Args:
        scene: The scene that receives the instanced meshes.
        assets: The stores. The geometries are added.
        look: The materials, which hold the leaves and the bark.
        plan: The plan, which gives the moat and the ground.
        node: The scene node the trees are placed relative to. Its frame is
            the y-up frame of the mesh view.
        keep_x: The east coordinate of a place to keep clear, such as the
            eye of the camera.
        keep_y: The north coordinate of that place.
        keep_radius: How far round it nothing stands, in meters.
        seed: Where the random numbers start.

    Returns:
        The number of trees planted.

    Raises:
        Error: If a tree cannot be grown or the scene refuses a mesh.
    """
    var shapes = List[TreeShape]()
    for k in range(_NEAR_BROAD):
        shapes.append(broadleaf(seed + 11 * k, 1.0))
    for k in range(_NEAR_CONIFER):
        shapes.append(conifer(seed + 13 * k, 1.0))
    for k in range(_FAR_BROAD):
        shapes.append(broadleaf(seed + 29 * k + 3, 0.4))
    for k in range(_FAR_CONIFER):
        shapes.append(conifer(seed + 31 * k + 5, 0.4))
    var spots = _spots(plan, keep_x, keep_y, keep_radius, seed)
    var counts = List[Int](length=len(shapes), fill=0)
    for at in range(len(spots)):
        counts[spots[at].variant] += 1
    for variant in range(len(shapes)):
        if counts[variant] == 0:
            continue
        var is_conifer = (
            variant >= _NEAR_BROAD and variant < _NEAR_BROAD + _NEAR_CONIFER
        ) or variant >= _NEAR_BROAD + _NEAR_CONIFER + _FAR_BROAD
        var foliage = look.material(FOLIAGE)
        if is_conifer:
            foliage = look.needles
        var bark = InstancedMesh(
            assets.geometries.add(shapes[variant].bark.clone()),
            look.trunk,
            node,
            counts[variant],
            cast_shadow=True,
            receive_shadow=True,
        )
        var leaves = InstancedMesh(
            assets.geometries.add(shapes[variant].leaves.clone()),
            foliage,
            node,
            counts[variant],
            cast_shadow=True,
            receive_shadow=True,
        )
        var at = 0
        for k in range(len(spots)):
            if spots[k].variant != variant:
                continue
            var size = Float32(spots[k].size)
            var placed = scaling(size, size, size)
            placed.premultiply(
                rotation_y(Angle(Float32(spots[k].turn), RADIAN))
            )
            placed.premultiply(
                translation(
                    Float32(spots[k].x),
                    Float32(spots[k].z),
                    Float32(-spots[k].y),
                )
            )
            bark.set_matrix_at(at, placed)
            leaves.set_matrix_at(at, placed)
            leaves.set_color_at(at, spots[k].color)
            at += 1
        scene.add_instanced_mesh(bark^)
        scene.add_instanced_mesh(leaves^)
    return len(spots)


def bush(seed: Int, radius: Float64, height: Float64) raises -> BufferGeometry:
    """Make a shrub: a rounded cluster of cards of leaves.

    Args:
        seed: Where the random numbers start.
        radius: The radius of the cluster, in meters.
        height: The height of the cluster, in meters.

    Returns:
        The geometry, with its foot at the origin.

    Raises:
        Error: If the geometry cannot be built.
    """
    var mesh = MeshBuilder()
    var up = Vec3d(0, 1, 0)
    for i in range(110):
        var r1 = unit_noise(Float64(i), 3.0, seed)
        var r2 = unit_noise(Float64(i) + 11.0, 5.0, seed + 1)
        var r3 = unit_noise(Float64(i) + 23.0, 7.0, seed + 2)
        var r4 = unit_noise(Float64(i) + 37.0, 9.0, seed + 3)
        var r5 = unit_noise(Float64(i) + 53.0, 2.0, seed + 4)
        var around = 2.0 * pi * r1
        var lift = 2.0 * r2 - 1.0
        var flat = sqrt(max(0.0, 1.0 - lift * lift))
        var shell = 0.55 + 0.45 * r3
        var center = Vec3d(
            flat * cos(around) * radius * shell,
            height * (0.5 + 0.5 * lift * shell),
            flat * sin(around) * radius * shell,
        )
        var outward = Vec3d(
            flat * cos(around), lift * 0.7 + 0.3, flat * sin(around)
        )
        outward = outward.normalized()
        var random = _unit_or(Vec3d(2 * r1 - 1, 2 * r2 - 1, 2 * r3 - 1), up)
        var n = (outward * 0.6 + random * 0.4).normalized()
        var right = _side(n, up)
        var spine = n.cross(right)
        _emit_card(
            mesh, center, n, right, spine, 0.55 + 0.4 * r4, outward, r3, r5
        )
    return mesh.geometry()


def plant_bushes(
    mut scene: Scene,
    mut assets: Assets,
    look: CastleLook,
    plan: CastlePlan,
    node: NodeId,
    seed: Int = 7,
    gap: Float64 = 0.12,
) raises -> Int:
    """Plant shrubs along the bank of the moat, between the water and the
    fence.

    Args:
        scene: The scene that receives the instanced meshes.
        assets: The stores. The geometries are added.
        look: The materials, which hold the leaves.
        plan: The plan.
        node: The scene node that the shrubs are placed relative to. Its
            frame is the y-up frame of the mesh view.
        seed: Where the random numbers start.
        gap: The share of the places along the bank that are left bare, from
            0 up to 1.

    Returns:
        The number of shrubs planted.

    Raises:
        Error: If a geometry cannot be built or the scene refuses a mesh.
    """
    var hull = convex_hull(plan.moat.outline)
    var ring = offset_ring(resample_ring(shore_ring(plan, hull), 1.9), 2.9)
    var ground = List[Float64]()
    for corner in ring:
        ground.append(ground_height(plan, hull, corner))
    var shapes = List[BufferGeometry]()
    for k in range(3):
        shapes.append(bush(seed + 7 * k, 1.5, 1.8))
    var spots = List[_Spot]()
    for at in range(len(ring)):
        var x = ring[at].x.value
        var y = ring[at].y.value
        if unit_noise(x, y, seed + 21) < gap:
            continue
        var pick = unit_noise(x, y, seed + 22)
        var tone = 0.8 + 0.4 * unit_noise(y, x, seed + 23)
        spots.append(
            _Spot(
                x,
                y,
                ground[at],
                Int(pick * 3.0) % 3,
                0.7 + 0.7 * unit_noise(x, y, seed + 24),
                2.0 * pi * unit_noise(x, y, seed + 25),
                _autumn(unit_noise(x, y, seed + 26), tone),
            )
        )
    var counts = List[Int](length=len(shapes), fill=0)
    for at in range(len(spots)):
        counts[spots[at].variant] += 1
    for variant in range(len(shapes)):
        if counts[variant] == 0:
            continue
        var leaves = InstancedMesh(
            assets.geometries.add(shapes[variant].clone()),
            look.material(FOLIAGE),
            node,
            counts[variant],
            cast_shadow=True,
            receive_shadow=True,
        )
        var at = 0
        for k in range(len(spots)):
            if spots[k].variant != variant:
                continue
            var size = Float32(spots[k].size)
            var placed = scaling(size, size, size)
            placed.premultiply(
                rotation_y(Angle(Float32(spots[k].turn), RADIAN))
            )
            placed.premultiply(
                translation(
                    Float32(spots[k].x),
                    Float32(spots[k].z),
                    Float32(-spots[k].y),
                )
            )
            leaves.set_matrix_at(at, placed)
            leaves.set_color_at(at, spots[k].color)
            at += 1
        scene.add_instanced_mesh(leaves^)
    return len(spots)
