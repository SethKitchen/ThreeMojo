# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The woods of a landscape: groves and clearings, stands of one age, and
trees of the kind that the altitude suits.

A tree is placed where the ground can hold it and a wood grows.

- It needs dry ground above the water, ground that is not too steep, and a
  little room round the moat and round the eye of the camera.
- It grows in groves. A slow noise draws the groves and the clearings. The
  plain is mostly fields, with woodlots, and the hills are mostly wood.
- It stops at the treeline, which is ragged: the wood thins and the trees
  shrink toward it, and none grows over it.
- Its kind follows the altitude: broadleaf trees in the lowland, spruce and
  fir higher, and larch near the treeline, which is gold in the autumn.
- Its size follows its stand. A stand is a patch of trees of one age, and a
  few dominant trees stand taller than the rest.

A tree is drawn by what its distance asks. The trees near the eye are the
skeletons with cards of leaves of `trees`, in full and then in reduced
detail. Farther on they are the crowns of `crowns`, and the farthest are a
cone or a ball. The distances are measured from the eye of the camera. The
field of view can also be given, and then only the trees that the camera
sees are planted, with the ground round the eye, for the reflection.
"""

from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from extensions.castle.crowns import (
    ball_crown,
    broadleaf_crown,
    cone_crown,
    spruce,
)
from extensions.castle.kinds import FOLIAGE, WOOD
from extensions.castle.landscape import Landscape
from extensions.castle.look import CastleLook
from extensions.castle.parts import unit_noise
from extensions.castle.trees import TreeShape, _autumn, broadleaf, conifer
from math.matrix4 import rotation_y, scaling, translation
from math.smoothstep import clamped_smoothstep
from objects.instanced_mesh import InstancedMesh
from render.framebuffer import Color
from std.math import atan2, pi, sqrt
from units.si import Angle, Length64, RADIAN

# The tiers: the trees of the skeleton in full detail, in reduced detail, the
# crowns, and the cones and balls.
comptime _TIERS = 4
# The kinds of shape in a tier.
comptime _BROAD = 0
comptime _SPRUCE = 1
comptime _FIR = 2
comptime _LARCH = 3
# Each tier has this many shapes of each kind, to keep a wood from looking
# cloned.
comptime _VARIANTS = 3
comptime _KINDS = 4
# Trees nearer than this to the eye are planted whatever the view.
comptime _ALWAYS = 70.0


@fieldwise_init
struct ForestSettings(ImplicitlyCopyable):
    """The choices of the woods."""

    # Where the random numbers start.
    var seed: Int
    # The distance from the eye to which trees are drawn in full detail, in
    # reduced detail, as crowns, and as cones and balls.
    var hero: Length64
    var near: Length64
    var mid: Length64
    var far: Length64
    # The eye of the camera, in the plan.
    var eye_x: Float64
    var eye_y: Float64
    # Where the camera looks, in radians from east toward north, and half the
    # angle that it sees, with a margin. A half angle of pi plants all round.
    var heading: Float64
    var half_view: Float64
    # No tree stands this close to the eye.
    var keep_radius: Float64

    def check(self) raises:
        """Refuse settings that cannot plant a wood.

        Raises:
            Error: If the distances are not in order, or a number is not
                finite, or the half angle is not positive.
        """
        var ok = (
            self.hero.value > 0.0
            and self.hero.value < self.near.value
            and self.near.value < self.mid.value
            and self.mid.value < self.far.value
        )
        if not ok:
            raise Error(
                "The distances of the woods must grow: hero, near, mid, far"
            )
        if not (self.half_view > 0.0 and self.keep_radius >= 0.0):
            raise Error(
                "The half view must be positive and the keep not negative"
            )
        if not (
            self.eye_x == self.eye_x
            and self.eye_y == self.eye_y
            and self.heading == self.heading
        ):
            raise Error("The eye and the heading must be numbers")


def default_forest() -> ForestSettings:
    """Return woods that are drawn all round the middle of the plan.

    Returns:
        Full detail to 110 m, reduced detail to 320 m, crowns to 1.2 km and
        cones and balls to 2.6 km, from an eye at the origin, with no view
        and no keep.
    """
    return ForestSettings(
        7,
        Length64(110.0),
        Length64(320.0),
        Length64(1200.0),
        Length64(2600.0),
        0.0,
        0.0,
        0.0,
        pi,
        0.0,
    )


@fieldwise_init
struct Clearing(ImplicitlyCopyable):
    """A round place that no tree stands in."""

    # The middle of the place, in the plan.
    var x: Float64
    var y: Float64
    # How far the clearing reaches, in meters.
    var radius: Float64


@fieldwise_init
struct _Spot(Copyable, Movable):
    """Where one tree stands, and how it looks."""

    var x: Float64
    var y: Float64
    var z: Float64
    var shape: Int
    var size: Float64
    var turn: Float64
    var color: Color


def _bank(seed: Int) raises -> List[TreeShape]:
    """Grow the shapes of every tier, in the order of `_shape_index`."""
    var shapes = List[TreeShape]()
    # Tier 0, in full detail: the skeletons of `trees`.
    for k in range(_VARIANTS):
        shapes.append(broadleaf(seed + 11 * k, 1.0))
    for k in range(_VARIANTS):
        shapes.append(conifer(seed + 13 * k, 1.0))
    # A fir and a larch are conifers of this tier too.
    for k in range(_VARIANTS):
        shapes.append(conifer(seed + 17 * k + 2, 1.0))
    for k in range(_VARIANTS):
        shapes.append(conifer(seed + 19 * k + 4, 1.0))
    # Tier 1, in reduced detail.
    for k in range(_VARIANTS):
        shapes.append(broadleaf(seed + 29 * k + 3, 0.4))
    for k in range(_VARIANTS):
        shapes.append(conifer(seed + 31 * k + 5, 0.4))
    for k in range(_VARIANTS):
        shapes.append(conifer(seed + 37 * k + 6, 0.4))
    for k in range(_VARIANTS):
        shapes.append(conifer(seed + 41 * k + 8, 0.4))
    # Tier 2, the crowns.
    for k in range(_VARIANTS):
        shapes.append(broadleaf_crown(seed + 43 * k, 18.0, 22))
    for k in range(_VARIANTS):
        shapes.append(spruce(seed + 47 * k, 24.0, 11, 0.3, 1.0))
    for k in range(_VARIANTS):
        shapes.append(spruce(seed + 53 * k, 26.0, 12, 0.25, 0.7))
    for k in range(_VARIANTS):
        shapes.append(spruce(seed + 59 * k, 22.0, 10, 0.15, 1.25))
    # Tier 3, cones and balls.
    for k in range(_VARIANTS):
        shapes.append(ball_crown(seed + 61 * k, 17.0))
    for k in range(_VARIANTS):
        shapes.append(cone_crown(seed + 67 * k, 24.0))
    for k in range(_VARIANTS):
        shapes.append(cone_crown(seed + 71 * k, 26.0))
    for k in range(_VARIANTS):
        shapes.append(cone_crown(seed + 73 * k, 22.0))
    return shapes^


def _shape_index(tier: Int, kind: Int, variant: Int) -> Int:
    """Return the place in the bank of a shape of a tier and a kind."""
    return (tier * _KINDS + kind) * _VARIANTS + variant


def _tier_at(settings: ForestSettings, distance: Float64) -> Int:
    """Return the tier that a tree at a distance from the eye is drawn in, or
    minus one if it is farther than the last."""
    if distance < settings.hero.value:
        return 0
    if distance < settings.near.value:
        return 1
    if distance < settings.mid.value:
        return 2
    if distance < settings.far.value:
        return 3
    return -1


def _in_view(settings: ForestSettings, x: Float64, y: Float64) -> Bool:
    """Return whether a point is in the sector that the camera sees, or close
    to the eye."""
    var dx = x - settings.eye_x
    var dy = y - settings.eye_y
    if sqrt(dx * dx + dy * dy) < _ALWAYS:
        return True
    var delta = atan2(dy, dx) - settings.heading
    while delta > pi:
        delta -= 2.0 * pi
    while delta < -pi:
        delta += 2.0 * pi
    return abs(delta) <= settings.half_view


def _color_of(kind: Int, pick: Float64, tone: Float64, drift: Float64) -> Color:
    """Return the tint of a tree of a kind in the autumn."""
    if kind == _BROAD:
        var chosen = pick + 0.35 * drift
        return _autumn(chosen - Float64(Int(chosen)), 0.8 + 0.3 * tone)
    if kind == _LARCH:
        return Color(
            UInt8(Int(205.0 * (0.8 + 0.3 * tone))),
            UInt8(Int(160.0 * (0.8 + 0.3 * tone))),
            UInt8(Int(52.0 * (0.8 + 0.3 * tone))),
        )
    if kind == _FIR:
        return Color(
            UInt8(Int(36.0 * (0.75 + 0.5 * tone))),
            UInt8(Int(74.0 * (0.75 + 0.5 * tone))),
            UInt8(Int(62.0 * (0.75 + 0.5 * tone))),
        )
    return Color(
        UInt8(Int(46.0 * (0.75 + 0.5 * tone))),
        UInt8(Int(84.0 * (0.75 + 0.5 * tone))),
        UInt8(Int(52.0 * (0.75 + 0.5 * tone))),
    )


def _mute(color: Color, share: Float64) -> Color:
    """Return a color drawn toward the gray of the same light, as the air of
    a distance does: a wood a kilometer away is quieter than one beside the
    eye."""
    var gray = (Float64(color.r) + Float64(color.g) + Float64(color.b)) / 3.0
    var keep = 1.0 - share
    return Color(
        UInt8(Int(Float64(color.r) * keep + gray * share * 0.9)),
        UInt8(Int(Float64(color.g) * keep + gray * share * 0.95)),
        UInt8(Int(Float64(color.b) * keep + gray * share * 0.8)),
    )


def _grow_tier(
    land: Landscape,
    settings: ForestSettings,
    tier: Int,
    inner: Float64,
    outer: Float64,
    cell: Float64,
    clearings: List[Clearing],
    mut spots: List[_Spot],
) raises:
    """Plant the trees of one tier: on a jittered grid of cells, each cell
    keeps a tree if the wood is thick there and the ground holds one."""
    var treeline = land.settings.treeline.value
    var seed = settings.seed
    var columns = Int(2.0 * outer / cell) + 1
    for row in range(columns):
        for column in range(columns):
            var jx = unit_noise(Float64(column), Float64(row), seed + tier)
            var jy = unit_noise(Float64(column), Float64(row), seed + 2 + tier)
            var x = settings.eye_x - outer + (Float64(column) + jx) * cell
            var y = settings.eye_y - outer + (Float64(row) + jy) * cell
            var dx = x - settings.eye_x
            var dy = y - settings.eye_y
            var distance = sqrt(dx * dx + dy * dy)
            if distance < inner or distance >= outer:
                continue
            if distance < settings.keep_radius:
                continue
            if not _in_view(settings, x, y):
                continue
            var cleared = False
            for at in range(len(clearings)):
                var cx = x - clearings[at].x
                var cy = y - clearings[at].y
                if (
                    cx * cx + cy * cy
                    < clearings[at].radius * clearings[at].radius
                ):
                    cleared = True
            if cleared:
                continue
            var altitude = land.altitude(x, y)
            if altitude < 1.0:
                continue
            var flat = land.flatness(x, y)
            if flat < 0.62:
                continue
            if land.distance_from_moat(x, y) < 14.0:
                continue
            # Groves and clearings: mostly fields on the plain, wood on the
            # hills.
            var grove = land.grove(x, y)
            var hills = clamped_smoothstep(25.0, 120.0, altitude)
            var odds = (0.08 + 0.9 * grove * grove) * (1.0 - hills) + (
                0.3 + 0.7 * grove
            ) * hills
            odds *= clamped_smoothstep(1.0, 4.0, altitude)
            odds *= clamped_smoothstep(0.62, 0.78, flat)
            var edge = 30.0 * (land.patches(x, y, 90.0, 71) - 0.5)
            odds *= 1.0 - clamped_smoothstep(
                treeline - 70.0, treeline + 30.0, altitude + edge
            )
            if unit_noise(x * 1.37, y * 1.91, seed + 5) >= odds:
                continue
            # The kind of tree follows the altitude, and the stand.
            var share = 0.22 + 0.7 * clamped_smoothstep(25.0, 200.0, altitude)
            share += 0.3 * (land.patches(x, y, 150.0, 73) - 0.5)
            var kind = _BROAD
            var chosen = unit_noise(x * 0.73, y * 0.61, seed + 9)
            var sub = unit_noise(x * 0.43, y * 0.89, seed + 10)
            if chosen < share:
                kind = _SPRUCE
                if altitude > 110.0 and sub < 0.4:
                    kind = _LARCH
                elif sub > 0.7:
                    kind = _FIR
            # The size follows the stand, the dominant trees, and the treeline.
            var cohort = 0.7 + 0.5 * land.patches(x, y, 80.0, 41)
            var dominant = 1.0
            if unit_noise(x, y, seed + 11) < 0.05:
                dominant = 1.3
            var dwarf = 1.0 - 0.5 * clamped_smoothstep(
                treeline - 120.0, treeline, altitude
            )
            var size = (0.75 + 0.4 * unit_noise(x, y, seed + 12)) * cohort
            size *= dominant * dwarf
            var variant = (
                Int(unit_noise(x, y, seed + 13) * Float64(_VARIANTS))
                % _VARIANTS
            )
            var tone = unit_noise(x * 1.13, y * 0.97, seed + 14)
            var drift = land.patches(x, y, 200.0, 75) - 0.5
            var tint = _color_of(kind, unit_noise(x, y, seed + 16), tone, drift)
            if tier == 2:
                tint = _mute(tint, 0.3)
            elif tier == 3:
                tint = _mute(tint, 0.5)
            spots.append(
                _Spot(
                    x,
                    y,
                    land.height(x, y),
                    _shape_index(tier, kind, variant),
                    size,
                    2.0 * pi * unit_noise(x, y, seed + 15),
                    tint,
                )
            )


def plant_forest(
    mut scene: Scene,
    mut assets: Assets,
    look: CastleLook,
    land: Landscape,
    node: NodeId,
    settings: ForestSettings,
    clearings: List[Clearing],
) raises -> Int:
    """Plant the woods of a landscape.

    Args:
        scene: The scene that receives the instanced meshes.
        assets: The stores. The geometries are added.
        look: The materials, which hold the leaves, the needles and the bark.
        land: The landscape that the trees stand on.
        node: The scene node that the trees are placed relative to. Its frame
            is the y-up frame of the mesh view.
        settings: The choices of the woods.
        clearings: Places that no tree stands in.

    Returns:
        The number of trees planted.

    Raises:
        Error: If the settings are refused, a tree cannot be grown, or the
            scene refuses a mesh.
    """
    settings.check()
    var spots = List[_Spot]()
    var edges = [
        0.0,
        settings.hero.value,
        settings.near.value,
        settings.mid.value,
        settings.far.value,
    ]
    var cells: List[Float64] = [7.0, 9.0, 24.0, 48.0]
    for tier in range(_TIERS):
        _grow_tier(
            land,
            settings,
            tier,
            edges[tier],
            edges[tier + 1],
            cells[tier],
            clearings,
            spots,
        )
    var shapes = _bank(settings.seed)
    var counts = List[Int](length=len(shapes), fill=0)
    for at in range(len(spots)):
        counts[spots[at].shape] += 1
    for shape in range(len(shapes)):
        if counts[shape] == 0:
            continue
        var tier = shape // (_KINDS * _VARIANTS)
        var kind = (shape // _VARIANTS) % _KINDS
        var near_trees = tier < 2
        var foliage = look.material(FOLIAGE)
        if kind != _BROAD:
            foliage = look.needles
        if tier == 3:
            foliage = look.material(WOOD)
        if shapes[shape].bark.triangle_count() > 0:
            var bark = InstancedMesh(
                assets.geometries.add(shapes[shape].bark.clone()),
                look.trunk,
                node,
                counts[shape],
                cast_shadow=near_trees,
                receive_shadow=near_trees,
            )
            _place(bark, spots, shape, False)
            scene.add_instanced_mesh(bark^)
        var leaves = InstancedMesh(
            assets.geometries.add(shapes[shape].leaves.clone()),
            foliage,
            node,
            counts[shape],
            cast_shadow=near_trees,
            receive_shadow=near_trees,
        )
        _place(leaves, spots, shape, True)
        scene.add_instanced_mesh(leaves^)
    return len(spots)


def _place(
    mut mesh: InstancedMesh, spots: List[_Spot], shape: Int, tinted: Bool
) raises:
    """Set the matrix, and for leaves the color, of each tree of a shape."""
    var at = 0
    for k in range(len(spots)):
        if spots[k].shape != shape:
            continue
        var size = Float32(spots[k].size)
        var placed = scaling(size, size, size)
        placed.premultiply(rotation_y(Angle(Float32(spots[k].turn), RADIAN)))
        placed.premultiply(
            translation(
                Float32(spots[k].x),
                Float32(spots[k].z) - 0.3 * size,
                Float32(-spots[k].y),
            )
        )
        mesh.set_matrix_at(at, placed)
        if tinted:
            mesh.set_color_at(at, spots[k].color)
        at += 1
