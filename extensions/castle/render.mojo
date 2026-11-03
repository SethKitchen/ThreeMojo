# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mesh view of a castle plan: the building, the ground and the bridge
as triangles that a renderer can draw.

The plan gives the footprints and the heights. This module gives them the
look of the building, from what a photograph shows and what a building of the
style has. Nothing here is surveyed, and the plan says so by marking those
parts `ESTIMATED`.

- A **wing** has a stone plinth, brick walls with rows of windows cut
  through them, string courses and a cornice. Its slate roof overhangs the
  walls, and carries dormers, chimneys and a leaded ridge.
- A **round tower** is a ring of plates with slit windows, on a plinth with
  bands of stone. It ends in a slate spire on a corbel table, or in a
  crenellated crown.
- The **gate** is a block with a pointed portal on the side of the bridge,
  windows and a crenellated parapet.
- The **quay wall** is brick with a stone coping. The **bridge** has three
  arches, cutwaters on its piers, parapets and a railing.
- The **ground** is a grid of heights: the bed of the moat, its banks, the
  island and the meadow, which runs on to the horizon.

The materials are named in `kinds`. A surface with a texture takes the color
of the texture and a tint from the vertex. The z axis is up, and z is zero
at the ground of the island.
"""

from std.math import atan2, cos, floor, isfinite, pi, sin, sqrt
from extensions.castle.kinds import CONE
from extensions.castle.parts import (
    Kit,
    at_height,
    MaterialMesh,
    Opening,
    box_at,
    chimney,
    corbel_ring,
    dormer,
    finial,
    merlon_row,
    quad_uv,
    ridge_cap,
    ring_band,
    round_crown,
    round_wall,
    signed_area,
    spire,
    srgb,
    unit_noise,
    wall,
    white,
    window_row,
)
from extensions.castle.plan import (
    CastlePlan,
    Gate,
    Point,
    Tower,
    Wing,
    convex_hull,
    distance_to_outline,
    offset_outline,
    point,
    polygon_contains,
)
from generators.utils import Vec3d
from units.si import Length64

# The width of the bank of the island, and of the ground outside, in meters.
comptime _ISLAND_BANK = Float64(1.5)
comptime _OUTER_BANK = Float64(6.0)
# The ring path: its distance from the water, and its width, in meters.
comptime _PATH_FROM = Float64(7.0)
comptime _PATH_TO = Float64(9.0)
# How far the roof of a wing overhangs its walls, in meters.
comptime _OVERHANG = Float64(0.45)
# The spacing of the grid of the far meadow, and how far it reaches.
comptime _FAR_STEP = Float64(40.0)
comptime _FAR_REACH = Float64(3200.0)


@fieldwise_init
struct ViewSettings(ImplicitlyCopyable):
    """The choices of the view that no survey makes."""

    # The height of the stone plinth above the water: a guess from a
    # photograph.
    var plinth: Length64
    # The spacing of the terrain's grid.
    var terrain_step: Length64
    # The spacing of the windows along a wall: a guess of the style.
    var window_pitch: Length64
    # The spacing of the trees.
    var tree_spacing: Length64
    # Where the trees' random numbers start.
    var seed: Int

    def check(self) raises:
        """Refuse settings that cannot be built.

        Raises:
            Error: If the plinth is negative or not finite, or a spacing is
                not positive and finite.
        """
        if not (isfinite(self.plinth.value) and self.plinth.value >= 0):
            raise Error("A plinth must be zero or more and finite")
        if not (
            isfinite(self.terrain_step.value) and self.terrain_step.value > 0
        ):
            raise Error("A terrain step must be positive and finite")
        if not (
            isfinite(self.window_pitch.value) and self.window_pitch.value > 0
        ):
            raise Error("A window pitch must be positive and finite")
        if not (
            isfinite(self.tree_spacing.value) and self.tree_spacing.value > 0
        ):
            raise Error("A tree spacing must be positive and finite")


def default_view() -> ViewSettings:
    """Return the settings that the example uses.

    Returns:
        A plinth of 2.2 m, a terrain step of 1.5 m, windows 3.2 m apart and
        trees 6 m apart.
    """
    return ViewSettings(
        Length64(2.2), Length64(1.0), Length64(3.2), Length64(6.0), 7
    )


def _tint(x: Float64, y: Float64, seed: Int) -> Vec3d:
    """Return a tint that varies a little from wall to wall."""
    var shade = 0.93 + 0.12 * unit_noise(x, y, seed)
    return Vec3d(shade, shade * 0.99, shade * 0.98)


def _smooth(x: Float64) -> Float64:
    """Return the smooth step of a number clamped to 0 through 1."""
    var t = min(max(x, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _ease(x: Float64) -> Float64:
    """Return a curve that rises steeply from 0 at 0 and levels off at 1
    for a number of 1 or more."""
    var t = 1.0 - min(max(x, 0.0), 1.0)
    return 1.0 - t * t


def ground_height(
    plan: CastlePlan, hull: List[Point], at: Point
) raises -> Float64:
    """Return the height of the ground at a point, above the island.

    The ground is continuous across the shore and has a slope there, so that
    the water meets the bank along a clean line and not along a step.
    """
    var water = plan.moat.water_level.value - plan.island_level.value
    var near = distance_to_outline(plan.moat.outline, at).value
    var ripple = 0.1 * (
        unit_noise(at.x.value * 0.7, at.y.value * 0.7, 11) - 0.5
    )
    if polygon_contains(plan.moat.outline, at):
        # The bed shelves down from the shore to the full depth.
        return water - plan.moat.depth.value * _ease(near / 3.0)
    if polygon_contains(hull, at):
        return water + (0.0 - water) * _ease(near / _ISLAND_BANK) + ripple
    var ground = plan.ground_level.value - plan.island_level.value
    return water + (ground - water) * _ease(near / _OUTER_BANK) + ripple


def _terrain(plan: CastlePlan, settings: ViewSettings, mut kit: Kit) raises:
    """Add the ground: the island, the banks, the meadow and the far fields."""
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
    var margin = 75.0
    low_x -= margin
    low_y -= margin
    high_x += margin
    high_y += margin
    var step = settings.terrain_step.value
    var columns = Int((high_x - low_x) / step) + 1
    var rows = Int((high_y - low_y) / step) + 1
    var heights = List[Float64](capacity=columns * rows)
    var colors = List[Vec3d](capacity=columns * rows)
    var dry = Vec3d(1.0, 0.86, 0.6)
    for row in range(rows):
        for column in range(columns):
            var at = point(
                low_x + Float64(column) * step, low_y + Float64(row) * step
            )
            heights.append(ground_height(plan, hull, at))
            var near = distance_to_outline(plan.moat.outline, at).value
            var shade = 0.8 + 0.4 * unit_noise(
                at.x.value * 0.35, at.y.value * 0.35, settings.seed
            )
            var color = Vec3d(shade, shade, shade)
            # Autumn: some patches of the meadow have gone dry.
            if unit_noise(at.x.value * 0.08, at.y.value * 0.08, 3) > 0.62:
                color = Vec3d(shade * dry.x, shade * dry.y, shade * dry.z)
            # The wet margin of the water is dark.
            if near < 1.6:
                var wet = 0.45 + 0.55 * _smooth(near / 1.6)
                color = Vec3d(
                    color.x * wet, color.y * wet * 0.95, color.z * wet
                )
            colors.append(color)
    kit.lawn.heightfield(
        Vec3d(low_x, low_y, 0), step, step, columns, rows, heights, colors
    )
    # The far fields: four strips round the near ground, which run on to the
    # horizon as a patchwork of fields. Each strip meets the near ground
    # along an edge, at the same height.
    var ground = plan.ground_level.value - plan.island_level.value
    var far_low_x = low_x - _FAR_REACH
    var far_high_x = high_x + _FAR_REACH
    var far_low_y = low_y - _FAR_REACH
    var far_high_y = high_y + _FAR_REACH
    _strip(kit, far_low_x, far_low_y, low_x, far_high_y, ground, settings.seed)
    _strip(
        kit, high_x, far_low_y, far_high_x, far_high_y, ground, settings.seed
    )
    _strip(kit, low_x, far_low_y, high_x, low_y, ground, settings.seed)
    _strip(kit, low_x, high_y, high_x, far_high_y, ground, settings.seed)


def _strip(
    mut kit: Kit,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    ground: Float64,
    seed: Int,
) raises:
    """Add a flat strip of far meadow, colored in patches like fields."""
    var columns = max(2, Int((x1 - x0) / _FAR_STEP) + 1)
    var rows = max(2, Int((y1 - y0) / _FAR_STEP) + 1)
    var step_x = (x1 - x0) / Float64(columns - 1)
    var step_y = (y1 - y0) / Float64(rows - 1)
    var heights = List[Float64](capacity=columns * rows)
    var colors = List[Vec3d](capacity=columns * rows)
    var fields = List[Vec3d]()
    fields.append(Vec3d(0.9, 0.95, 0.7))
    fields.append(Vec3d(1.2, 1.1, 0.6))
    fields.append(Vec3d(0.8, 0.8, 0.55))
    fields.append(Vec3d(1.0, 0.9, 0.55))
    fields.append(Vec3d(0.7, 0.85, 0.6))
    for row in range(rows):
        for column in range(columns):
            var x = x0 + Float64(column) * step_x
            var y = y0 + Float64(row) * step_y
            heights.append(ground)
            var pick = unit_noise(floor(x / 110.0), floor(y / 90.0), seed + 5)
            var tone = fields[Int(pick * 5.0) % 5]
            var fine = 0.9 + 0.2 * unit_noise(x, y, seed + 6)
            colors.append(Vec3d(tone.x * fine, tone.y * fine, tone.z * fine))
    kit.lawn.heightfield(
        Vec3d(x0, y0, 0), step_x, step_y, columns, rows, heights, colors
    )


def _water(plan: CastlePlan, mut kit: Kit) raises:
    """Add the surface of the moat."""
    var outline = List[Tuple[Float64, Float64]]()
    for corner in plan.moat.outline:
        outline.append((corner.x.value, corner.y.value))
    var level = plan.moat.water_level.value - plan.island_level.value
    kit.water.plate(
        outline,
        List[List[Tuple[Float64, Float64]]](),
        Vec3d(0, 0, level),
        Vec3d(1, 0, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 0, -0.05),
        white(),
    )


def _facade(
    mut kit: Kit,
    p: Vec3d,
    q: Vec3d,
    away: Vec3d,
    bottom: Float64,
    plinth: Float64,
    eave: Float64,
    pitch: Float64,
    seed: Int,
) raises:
    """Add one wall of a block: the plinth, the brick with its windows, the
    ledge, a string course between the floors, and the cornice."""
    var run = Vec3d(q.x - p.x, q.y - p.y, 0)
    var length = run.length()
    if not (length > 1e-6):
        return
    var along = run * (1.0 / length)
    var up = Vec3d(0, 0, 1)
    var tint = _tint(p.x, p.y, seed)
    wall(kit, True, p, q, away, bottom, plinth, List[Opening](), tint)
    var openings = List[Opening]()
    var sill = plinth + 0.9
    while sill + 1.9 < eave - 0.8:
        var row = window_row(length, 1.4, pitch, 1.1, 1.9, sill, False)
        for o in row:
            openings.append(o.copy())
        sill += 3.5
    wall(kit, False, p, q, away, plinth, eave, openings, tint)
    var mid = Vec3d(p.x, p.y, 0) + along * (length / 2)
    box_at(
        kit.stone,
        mid + away * 0.12 + Vec3d(0, 0, plinth),
        along,
        away,
        up,
        length / 2,
        0.14,
        0.07,
        white(),
    )
    if plinth + 3.6 < eave - 1.0:
        box_at(
            kit.stone,
            mid + away * 0.05 + Vec3d(0, 0, plinth + 3.6),
            along,
            away,
            up,
            length / 2,
            0.07,
            0.11,
            white(),
        )
    box_at(
        kit.stone,
        mid + away * 0.17 + Vec3d(0, 0, eave - 0.13),
        along,
        away,
        up,
        length / 2 + 0.1,
        0.2,
        0.13,
        white(),
    )


def _wing(
    plan: CastlePlan, wing: Wing, settings: ViewSettings, mut kit: Kit
) raises:
    """Add a wing: walls with windows, a gable at each end, a slate roof
    with dormers, chimneys and a leaded ridge."""
    var datum = plan.island_level.value
    var bottom = wing.base.value - datum
    var eave = bottom + wing.eave_height.value
    var ridge = bottom + wing.ridge_height.value
    var plinth = bottom + settings.plinth.value
    var half = wing.width.value / 2
    var count = len(wing.axis)
    var outline = wing.outline()
    var up = Vec3d(0, 0, 1)
    var left = List[Vec3d]()
    var right = List[Vec3d]()
    var crest = List[Vec3d]()
    var left_eave = List[Vec3d]()
    var right_eave = List[Vec3d]()
    var scale = (half + _OVERHANG) / half
    for at in range(count):
        var axis = Vec3d(wing.axis[at].x.value, wing.axis[at].y.value, 0)
        var l = Vec3d(outline[at].x.value, outline[at].y.value, 0)
        var r = Vec3d(
            outline[2 * count - 1 - at].x.value,
            outline[2 * count - 1 - at].y.value,
            0,
        )
        left.append(l)
        right.append(r)
        crest.append(Vec3d(axis.x, axis.y, ridge))
        var lo = axis + (l - axis) * scale
        var ro = axis + (r - axis) * scale
        left_eave.append(Vec3d(lo.x, lo.y, eave - 0.3))
        right_eave.append(Vec3d(ro.x, ro.y, eave - 0.3))
    var pitch = settings.window_pitch.value
    for at in range(count - 1):
        var run = Vec3d(
            wing.axis[at + 1].x.value - wing.axis[at].x.value,
            wing.axis[at + 1].y.value - wing.axis[at].y.value,
            0,
        )
        var d = run.normalized()
        var across = Vec3d(-d.y, d.x, 0)
        _facade(
            kit, left[at], left[at + 1], across, bottom, plinth, eave, pitch, at
        )
        _facade(
            kit,
            right[at + 1],
            right[at],
            across * -1.0,
            bottom,
            plinth,
            eave,
            pitch,
            at + 40,
        )
        var slate = _tint(left[at].x, left[at].y, 17)
        for side in range(2):
            var facing = across if side == 0 else across * -1.0
            var e0 = left_eave[at]
            var e1 = left_eave[at + 1]
            if side == 1:
                e0 = right_eave[at]
                e1 = right_eave[at + 1]
            var r0 = crest[at]
            var r1 = crest[at + 1]
            var slope = r0 - e0
            var v_axis = (slope - d * slope.dot(d)).normalized()
            quad_uv(
                kit.slate, e0, e1, r1, r0, facing + up, slate, e0, d, v_axis
            )
            # The gutter along the eave.
            var length = (e1 - e0).length()
            box_at(
                kit.metal,
                (e0 + e1) * 0.5 - facing * 0.05,
                d,
                facing,
                up,
                length / 2,
                0.08,
                0.09,
                srgb(96, 100, 104),
            )
            # The dormers: one every five meters, away from the ends.
            var dormers = Int(length / 5.0)
            var horizontal = sqrt(slope.x * slope.x + slope.y * slope.y)
            for k in range(dormers):
                var t = 0.5
                if dormers > 1:
                    t = 0.18 + 0.64 * Float64(k) / Float64(dormers - 1)
                var base = e0 + (e1 - e0) * t
                var crest_here = r0 + (r1 - r0) * t
                var foot = base + (crest_here - base) * 0.5
                dormer(
                    kit,
                    foot,
                    facing,
                    (ridge - e0.z) / horizontal,
                    1.3,
                    at * 8 + k,
                )
        ridge_cap(kit.metal, crest[at], crest[at + 1], 0.28)
        # Chimneys on the long runs of the ridge.
        if run.length() > 9.0:
            for k in range(2):
                var t = 0.3 + 0.4 * Float64(k)
                var spot = crest[at] + (crest[at + 1] - crest[at]) * t
                chimney(kit, spot.x, spot.y, ridge - 1.0, 3.4)
    # The gables.
    var first = Vec3d(
        wing.axis[1].x.value - wing.axis[0].x.value,
        wing.axis[1].y.value - wing.axis[0].y.value,
        0,
    ).normalized()
    var last = Vec3d(
        wing.axis[count - 1].x.value - wing.axis[count - 2].x.value,
        wing.axis[count - 1].y.value - wing.axis[count - 2].y.value,
        0,
    ).normalized()
    var width = wing.width.value
    var cap_windows = List[Opening]()
    var sill = plinth + 0.9
    while sill + 1.7 < eave - 0.8:
        var row = window_row(width, 1.9, 4.0, 1.0, 1.7, sill, False)
        for o in row:
            cap_windows.append(o.copy())
        sill += 3.5
    for end in range(2):
        var p = right[0]
        var q = left[0]
        var away = first * -1.0
        if end == 1:
            p = left[count - 1]
            q = right[count - 1]
            away = last
        var tint = _tint(p.x, p.y, 60 + end)
        wall(kit, True, p, q, away, bottom, plinth, List[Opening](), tint)
        wall(kit, False, p, q, away, plinth, eave, cap_windows, tint, ridge)
        finial(kit.metal, (p.x + q.x) / 2, (p.y + q.y) / 2, ridge, 1.1)


def _tower(
    plan: CastlePlan,
    tower: Tower,
    index: Int,
    settings: ViewSettings,
    mut kit: Kit,
) raises:
    """Add a round tower: plinth, wall with slit windows, bands of stone,
    and a spire or a crenellated crown."""
    var datum = plan.island_level.value
    var bottom = tower.base.value - datum
    var wall_top = bottom + tower.wall_height.value
    var radius = tower.radius.value
    var cx = tower.center.x.value
    var cy = tower.center.y.value
    var plinth = min(bottom + settings.plinth.value, wall_top)
    var facets = max(12, Int(2.0 * pi * radius / 0.75))
    facets += facets % 2
    var tint = _tint(cx, cy, 90 + index)
    var none = List[Float64]()
    round_wall(
        kit,
        cx,
        cy,
        radius + 0.06,
        bottom,
        plinth,
        facets,
        True,
        tint,
        none,
        0,
        0,
        0.3,
    )
    ring_band(
        kit.stone,
        cx,
        cy,
        radius + 0.16,
        plinth - 0.18,
        plinth,
        0.14,
        facets,
        white(),
    )
    var levels = List[Float64]()
    var z = plinth + 1.3
    while z + 1.25 < wall_top - 1.0:
        levels.append(z)
        z += 3.3
    round_wall(
        kit,
        cx,
        cy,
        radius,
        plinth,
        wall_top,
        facets,
        False,
        tint,
        levels,
        3,
        index,
        0.3,
    )
    var band = plinth + 6.6
    while band < wall_top - 2.0:
        ring_band(
            kit.stone,
            cx,
            cy,
            radius + 0.07,
            band,
            band + 0.22,
            0.07,
            facets,
            white(),
        )
        band += 6.6
    if tower.roof == CONE:
        var count = max(8, Int(2.0 * pi * radius / 0.75))
        _cornice(kit, cx, cy, radius, wall_top, count, facets)
        spire(
            kit,
            cx,
            cy,
            radius + 0.45,
            wall_top,
            tower.roof_height.value,
            facets,
            index,
        )
        return
    round_crown(
        kit, cx, cy, radius, wall_top, max(tower.roof_height.value, 0.8)
    )
    if radius > 3.0:
        # A stair turret on the crown, with a spire of its own.
        var turn = 2.45
        var tx = cx + radius * 0.5 * cos(turn)
        var ty = cy + radius * 0.5 * sin(turn)
        var turret = List[Float64]()
        turret.append(wall_top + 1.2)
        round_wall(
            kit,
            tx,
            ty,
            0.95,
            wall_top,
            wall_top + 3.6,
            12,
            False,
            tint,
            turret,
            3,
            0,
            0.22,
        )
        spire(kit, tx, ty, 1.3, wall_top + 3.6, 3.2, 12, index + 5)


def _cornice(
    mut kit: Kit,
    cx: Float64,
    cy: Float64,
    radius: Float64,
    top: Float64,
    count: Int,
    facets: Int,
):
    """Add the cornice under a spire: corbels that carry a stone band."""
    corbel_ring(kit.stone, cx, cy, radius, top - 0.05, count, white())
    ring_band(
        kit.stone, cx, cy, radius + 0.42, top - 0.45, top, 0.0, facets, white()
    )


def _gate(
    plan: CastlePlan,
    gate: Gate,
    settings: ViewSettings,
    mut kit: Kit,
) raises:
    """Add the gate tower: walls on a plinth with windows and a pointed
    portal, a crenellated parapet and a leaded roof."""
    var datum = plan.island_level.value
    var bottom = gate.base.value - datum
    var top = bottom + gate.height.value
    var plinth = bottom + settings.plinth.value
    var corners = gate.outline()
    var deck = plan.bridge.deck.value - datum
    for edge in range(4):
        var p = Vec3d(corners[edge].x.value, corners[edge].y.value, 0)
        var q = Vec3d(
            corners[(edge + 1) % 4].x.value, corners[(edge + 1) % 4].y.value, 0
        )
        var run = q - p
        var length = run.length()
        var along = run * (1.0 / length)
        var away = Vec3d(along.y, -along.x, 0)
        var tint = _tint(p.x, p.y, 120 + edge)
        wall(kit, True, p, q, away, bottom, plinth, List[Opening](), tint)
        var openings = List[Opening]()
        var sill = plinth + 1.4
        while sill + 2.4 < top - 1.6:
            var row = window_row(length, 1.8, 3.6, 1.0, 2.4, sill, True)
            for o in row:
                # The portal side keeps its middle clear.
                if edge == 0 and abs(o.at - length / 2) < 3.0:
                    continue
                openings.append(o.copy())
            sill += 3.6
        if edge == 0:
            openings.append(Opening(length / 2, deck, 3.4, 5.6, True, False))
            openings.append(
                Opening(length / 2, deck + 7.0, 1.7, 3.6, True, True)
            )
        wall(kit, False, p, q, away, plinth, top, openings, tint)
        var up = Vec3d(0, 0, 1)
        var mid = p + along * (length / 2)
        box_at(
            kit.stone,
            mid + away * 0.12 + Vec3d(0, 0, plinth),
            along,
            away,
            up,
            length / 2,
            0.14,
            0.07,
            white(),
        )
        merlon_row(kit, p, q, away, top, gate.parapet.value)
    # The leaded roof inside the parapet.
    var lead = srgb(84, 90, 94)
    var a = Vec3d(corners[0].x.value, corners[0].y.value, top)
    var b = Vec3d(corners[1].x.value, corners[1].y.value, top)
    var c = Vec3d(corners[2].x.value, corners[2].y.value, top)
    var d = Vec3d(corners[3].x.value, corners[3].y.value, top)
    kit.metal.oriented(a, b, c, Vec3d(0, 0, 1), lead)
    kit.metal.oriented(a, c, d, Vec3d(0, 0, 1), lead)


def _quay(plan: CastlePlan, mut kit: Kit) raises:
    """Add the wall of the quay, from the bed of the moat to its top, with
    pilasters and a stone coping."""
    var datum = plan.island_level.value
    var outline = offset_outline(plan.quay.axis, plan.quay.thickness)
    var bottom = plan.quay.foot.value - datum
    var top = plan.quay.top.value - datum
    var count = len(outline)
    var up = Vec3d(0, 0, 1)
    for at in range(count):
        var p = outline[at]
        var q = outline[(at + 1) % count]
        var run = Vec3d(q.x.value - p.x.value, q.y.value - p.y.value, 0)
        var length = run.length()
        if not (length > 1e-6):
            continue
        var along = run * (1.0 / length)
        # The outline of a band runs along its left side and back along its
        # right side, so it runs clockwise, and the left of each edge faces
        # out of the wall.
        var away = Vec3d(-along.y, along.x, 0)
        var a = Vec3d(p.x.value, p.y.value, 0)
        var b = Vec3d(q.x.value, q.y.value, 0)
        wall(
            kit,
            False,
            a,
            b,
            away,
            bottom,
            top,
            List[Opening](),
            _tint(a.x, a.y, 150),
        )
        if length > 3.0:
            var pilasters = Int(length / 4.5)
            for k in range(pilasters):
                var offset = (Float64(k) + 0.5) * length / Float64(pilasters)
                box_at(
                    kit.stone,
                    a
                    + along * offset
                    + away * 0.1
                    + Vec3d(0, 0, (bottom + top) / 2),
                    along,
                    away,
                    up,
                    0.3,
                    0.12,
                    (top - bottom) / 2,
                    Vec3d(0.75, 0.72, 0.68),
                )
    var coping = List[Tuple[Float64, Float64]]()
    for corner in outline:
        coping.append((corner.x.value, corner.y.value))
    kit.stone.plate(
        coping,
        List[List[Tuple[Float64, Float64]]](),
        Vec3d(0, 0, top),
        Vec3d(1, 0, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 0, -0.15),
        white(),
    )


def _bridge(plan: CastlePlan, gate: Gate, mut kit: Kit) raises:
    """Add the bridge: spandrel walls with arches, soffits, a deck, cutwaters
    on the piers, a coping, a railing and a lead-in from the gate."""
    ref bridge = plan.bridge
    var datum = plan.island_level.value
    var deck = bridge.deck.value - datum
    var heading = bridge.heading.value
    var along = Vec3d(cos(heading), sin(heading), 0)
    var across = Vec3d(-sin(heading), cos(heading), 0)
    var up = Vec3d(0, 0, 1)
    var start = Vec3d(bridge.start.x.value, bridge.start.y.value, 0)
    # The gate's face stands back from the first pier. The lead-in is solid.
    var from_gate = (
        (start.x - gate.center.x.value) * along.x
        + (start.y - gate.center.y.value) * along.y
        - gate.width.value / 2
    )
    var lead_in = max(from_gate - bridge.pier.value / 2, 0.0)
    var launch = start - along * lead_in
    var length = bridge.length().value
    var half = bridge.width.value / 2 - 0.8
    var thick = 0.7
    var crown_gap = 0.3
    var radius = bridge.clear_span().value / 2
    var springing = deck - crown_gap - bridge.ring.value - bridge.rise().value
    var parapet_top = deck + 0.9
    var low = springing - 0.8
    var water = plan.moat.water_level.value - datum
    # Two spandrel walls, one each side, each a plate with the arches cut.
    for side in range(2):
        var offset = half if side == 0 else -half - thick
        var origin = launch - along * (bridge.pier.value / 2) + across * offset
        var outline = List[Tuple[Float64, Float64]]()
        var reach = lead_in + length + bridge.pier.value
        outline.append((0.0, low))
        outline.append((reach, low))
        outline.append((reach, parapet_top))
        outline.append((0.0, parapet_top))
        var holes = List[List[Tuple[Float64, Float64]]]()
        for span in range(bridge.spans):
            var arch = List[Tuple[Float64, Float64]]()
            var middle = (
                lead_in
                + bridge.pier.value / 2
                + (Float64(span) + 0.5) * bridge.pitch.value
            )
            # The semicircle from the left springing, over the crown.
            for step in range(13):
                var turn = pi - pi * Float64(step) / 12.0
                arch.append(
                    (
                        middle + radius * cos(turn),
                        springing + radius * sin(turn),
                    )
                )
            holes.append(arch^)
        kit.stone.plate(
            outline,
            holes,
            Vec3d(origin.x, origin.y, 0),
            along,
            up,
            across * thick,
            _tint(origin.x, origin.y, 200),
        )
    # The soffit of each arch: strips across the bridge between the walls.
    var inner = across * half
    var other = across * (-half)
    for span in range(bridge.spans):
        var middle = lead_in + (Float64(span) + 0.5) * bridge.pitch.value
        for step in range(12):
            var t0 = pi - pi * Float64(step) / 12.0
            var t1 = pi - pi * Float64(step + 1) / 12.0
            var p0 = launch + along * (middle + radius * cos(t0))
            var p1 = launch + along * (middle + radius * cos(t1))
            var z0 = springing + radius * sin(t0)
            var z1 = springing + radius * sin(t1)
            var a0 = Vec3d(p0.x + inner.x, p0.y + inner.y, z0)
            var a1 = Vec3d(p1.x + inner.x, p1.y + inner.y, z1)
            var b1 = Vec3d(p1.x + other.x, p1.y + other.y, z1)
            var b0 = Vec3d(p0.x + other.x, p0.y + other.y, z0)
            # Seen from below, inside the arch.
            var down = Vec3d(0, 0, -1)
            kit.stone.oriented(a0, a1, b1, down, srgb(150, 146, 138))
            kit.stone.oriented(a0, b1, b0, down, srgb(150, 146, 138))
    # The deck, a little below the tops of the walls.
    var p0 = launch - along * (bridge.pier.value / 2) + across * half
    var p1 = (
        launch
        + along * (lead_in + length + bridge.pier.value / 2)
        + across * half
    )
    var p2 = (
        launch
        + along * (lead_in + length + bridge.pier.value / 2)
        - across * half
    )
    var p3 = launch - along * (bridge.pier.value / 2) - across * half
    var top = Vec3d(0, 0, deck)
    kit.gravel.oriented(p0 + top, p1 + top, p2 + top, up, white())
    kit.gravel.oriented(p0 + top, p2 + top, p3 + top, up, white())
    var span_length = lead_in + length + bridge.pier.value
    for side in range(2):
        var offset = half if side == 0 else -half - thick
        var foot = (
            launch
            + along * (span_length / 2 - bridge.pier.value / 2)
            + across * (offset + thick / 2)
        )
        box_at(
            kit.stone,
            Vec3d(foot.x, foot.y, parapet_top + 0.07),
            along,
            across,
            up,
            span_length / 2,
            (thick + 0.16) / 2,
            0.08,
            white(),
        )
        # The railing: posts and two rails on the coping.
        var iron = srgb(40, 42, 44)
        var posts = Int(span_length / 1.4)
        for k in range(posts + 1):
            var s = Float64(k) * span_length / Float64(posts)
            var at = (
                launch
                - along * (bridge.pier.value / 2)
                + along * s
                + across * (offset + thick / 2)
            )
            box_at(
                kit.metal,
                Vec3d(at.x, at.y, parapet_top + 0.62),
                along,
                across,
                up,
                0.025,
                0.025,
                0.5,
                iron,
            )
        for rail in range(2):
            box_at(
                kit.metal,
                Vec3d(foot.x, foot.y, parapet_top + 0.4 + 0.45 * Float64(rail)),
                along,
                across,
                up,
                span_length / 2,
                0.02,
                0.02,
                iron,
            )
    # The cutwaters: the piers stand out from the walls in points.
    for pier in range(bridge.spans + 1):
        var s = lead_in + Float64(pier) * bridge.pitch.value
        var centre = launch + along * s
        var reach = half + thick + 1.3
        var wedge = List[Tuple[Float64, Float64]]()
        # Corners in the plan, counterclockwise: the pier and its two points.
        wedge.append((-1.0, -half - thick))
        wedge.append((0.0, -reach))
        wedge.append((1.0, -half - thick))
        wedge.append((1.0, half + thick))
        wedge.append((0.0, reach))
        wedge.append((-1.0, half + thick))
        var rotated = List[Tuple[Float64, Float64]]()
        for corner in wedge:
            rotated.append(
                (
                    centre.x + along.x * corner[0] + across.x * corner[1],
                    centre.y + along.y * corner[0] + across.y * corner[1],
                )
            )
        var height = (water + 0.9) - low
        kit.stone.plate(
            rotated,
            List[List[Tuple[Float64, Float64]]](),
            Vec3d(0, 0, low),
            Vec3d(1, 0, 0),
            Vec3d(0, 1, 0),
            Vec3d(0, 0, height),
            white(),
        )


def shore_ring(plan: CastlePlan, hull: List[Point]) raises -> List[Point]:
    """Return the outer shore of the moat as a closed ring, in order.

    The outline of the water is one polygon with the island cut out of it.
    Its outer shore is the part that lies near the convex hull; the shore of
    the island lies a moat's width farther in.
    """
    var ring = List[Point]()
    for corner in plan.moat.outline:
        if distance_to_outline(hull, corner).value < 7.0:
            ring.append(corner)
    return ring^


def resample_ring(ring: List[Point], spacing: Float64) -> List[Point]:
    """Return a closed ring with a corner at least every `spacing` meters."""
    var result = List[Point]()
    var count = len(ring)
    for at in range(count):
        var a = ring[at]
        var b = ring[(at + 1) % count]
        var dx = b.x.value - a.x.value
        var dy = b.y.value - a.y.value
        var steps = max(1, Int(sqrt(dx * dx + dy * dy) / spacing + 0.5))
        for step in range(steps):
            var t = Float64(step) / Float64(steps)
            result.append(point(a.x.value + dx * t, a.y.value + dy * t))
    return result^


def offset_ring(ring: List[Point], distance: Float64) -> List[Point]:
    """Return a ring moved away from its inside by a distance, with the
    corners mitered."""
    var count = len(ring)
    var sign = 1.0 if signed_area(ring) > 0 else -1.0
    var result = List[Point]()
    for at in range(count):
        var before = ring[(at + count - 1) % count]
        var here = ring[at]
        var after = ring[(at + 1) % count]
        var d0 = Vec3d(
            here.x.value - before.x.value, here.y.value - before.y.value, 0
        ).normalized()
        var d1 = Vec3d(
            after.x.value - here.x.value, after.y.value - here.y.value, 0
        ).normalized()
        var n0 = Vec3d(d0.y, -d0.x, 0) * sign
        var n1 = Vec3d(d1.y, -d1.x, 0) * sign
        var bisector = (n0 + n1).normalized()
        var reach = distance / max(bisector.dot(n1), 0.5)
        result.append(
            point(
                here.x.value + bisector.x * reach,
                here.y.value + bisector.y * reach,
            )
        )
    return result^


def _ring_path(plan: CastlePlan, hull: List[Point], mut kit: Kit) raises:
    """Add the path of gravel that runs round the moat, and the fence that
    keeps walkers from the water."""
    var ring = resample_ring(shore_ring(plan, hull), 2.4)
    var inner = offset_ring(ring, _PATH_FROM + 0.2)
    var outer = offset_ring(ring, _PATH_TO - 0.2)
    var fence = offset_ring(ring, 4.6)
    var count = len(ring)
    for at in range(count):
        var next = (at + 1) % count
        var a = Vec3d(inner[at].x.value, inner[at].y.value, 0)
        var b = Vec3d(inner[next].x.value, inner[next].y.value, 0)
        var c = Vec3d(outer[next].x.value, outer[next].y.value, 0)
        var d = Vec3d(outer[at].x.value, outer[at].y.value, 0)
        a.z = ground_height(plan, hull, inner[at]) + 0.03
        b.z = ground_height(plan, hull, inner[next]) + 0.03
        c.z = ground_height(plan, hull, outer[next]) + 0.03
        d.z = ground_height(plan, hull, outer[at]) + 0.03
        kit.gravel.oriented(a, b, c, Vec3d(0, 0, 1), white())
        kit.gravel.oriented(a, c, d, Vec3d(0, 0, 1), white())
    # The fence: a post every 2.4 m and two rails between them.
    var wood = srgb(98, 82, 62)
    var up = Vec3d(0, 0, 1)
    for at in range(count):
        var next = (at + 1) % count
        var here = Vec3d(fence[at].x.value, fence[at].y.value, 0)
        var there = Vec3d(fence[next].x.value, fence[next].y.value, 0)
        here.z = ground_height(plan, hull, fence[at])
        there.z = ground_height(plan, hull, fence[next])
        var run = there - here
        var length = sqrt(run.x * run.x + run.y * run.y)
        var along = Vec3d(run.x / length, run.y / length, 0)
        var across = Vec3d(-along.y, along.x, 0)
        box_at(
            kit.wood,
            here + Vec3d(0, 0, 0.55),
            along,
            across,
            up,
            0.06,
            0.06,
            0.55,
            wood,
        )
        for rail in range(2):
            var z = 0.5 + 0.42 * Float64(rail)
            var low = here + Vec3d(0, 0, z)
            var high = there + Vec3d(0, 0, z)
            var middle = (low + high) * 0.5
            var tilt = (high - low).normalized()
            box_at(
                kit.wood,
                middle,
                tilt,
                across,
                tilt.cross(across) * -1.0,
                (high - low).length() / 2,
                0.025,
                0.04,
                wood,
            )


def _shift_axis(axis: List[Point], distance: Float64) -> List[Point]:
    """Return an open polyline moved to the right of its direction of
    travel, with the corners mitered."""
    var count = len(axis)
    var result = List[Point]()
    for at in range(count):
        var before = axis[max(at - 1, 0)]
        var here = axis[at]
        var after = axis[min(at + 1, count - 1)]
        var d0 = Vec3d(
            here.x.value - before.x.value, here.y.value - before.y.value, 0
        )
        var d1 = Vec3d(
            after.x.value - here.x.value, after.y.value - here.y.value, 0
        )
        if d0.length() < 1e-9:
            d0 = d1
        if d1.length() < 1e-9:
            d1 = d0
        d0 = d0.normalized()
        d1 = d1.normalized()
        var n0 = Vec3d(d0.y, -d0.x, 0)
        var n1 = Vec3d(d1.y, -d1.x, 0)
        var bisector = (n0 + n1).normalized()
        var reach = distance / max(bisector.dot(n1), 0.5)
        result.append(
            point(
                here.x.value + bisector.x * reach,
                here.y.value + bisector.y * reach,
            )
        )
    return result^


def _courtyard(plan: CastlePlan, mut kit: Kit) raises:
    """Add the garden of the courtyard: a gravel path that follows the
    wall of the quay, with a low hedge on the lawn side of it."""
    var centre = _shift_axis(plan.quay.axis, 5.2)
    var path = offset_outline(centre, Length64(2.2))
    var count = len(path)
    var lift = Vec3d(0, 0, 0.04)
    # The band comes as a closed outline: one side, then the other, back.
    var half = count // 2
    for at in range(half - 1):
        var a = at_height(path[at], 0.0) + lift
        var b = at_height(path[at + 1], 0.0) + lift
        var c = at_height(path[count - 2 - at], 0.0) + lift
        var d = at_height(path[count - 1 - at], 0.0) + lift
        kit.gravel.oriented(a, b, c, Vec3d(0, 0, 1), white())
        kit.gravel.oriented(a, c, d, Vec3d(0, 0, 1), white())
    var hedge = _shift_axis(plan.quay.axis, 6.7)
    var green = Vec3d(0.5, 0.65, 0.4)
    var up = Vec3d(0, 0, 1)
    for at in range(len(hedge) - 1):
        var a = at_height(hedge[at], 0.0)
        var b = at_height(hedge[at + 1], 0.0)
        var run = b - a
        var length = run.length()
        if not (length > 0.5):
            continue
        var along = run * (1.0 / length)
        var across = Vec3d(-along.y, along.x, 0)
        box_at(
            kit.lawn,
            (a + b) * 0.5 + Vec3d(0, 0, 0.3),
            along,
            across,
            up,
            length / 2,
            0.3,
            0.3,
            green,
        )


def castle_meshes(
    plan: CastlePlan, settings: ViewSettings
) raises -> List[MaterialMesh]:
    """Build the mesh view of a castle plan.

    Args:
        plan: The plan. It must be consistent.
        settings: The choices of the view.

    Returns:
        One geometry for each material that has triangles, in the order of
        the materials in `kinds`.

    Raises:
        Error: If the plan or the settings are refused, or a mesh cannot be
            built.
    """
    plan.check()
    settings.check()
    var kit = Kit()
    build_castle(plan, settings, kit)
    return kit.meshes()


def build_castle(plan: CastlePlan, settings: ViewSettings, mut kit: Kit) raises:
    """Add the building, the ground and the bridge of a plan to a kit.

    Args:
        plan: The plan. It must be consistent.
        settings: The choices of the view.
        kit: The builders that receive the triangles.

    Raises:
        Error: If a mesh cannot be built.
    """
    _terrain(plan, settings, kit)
    build_structures(plan, settings, kit)


def build_structures(
    plan: CastlePlan, settings: ViewSettings, mut kit: Kit
) raises:
    """Add everything of a plan but its ground to a kit: the moat, the path,
    the wings, the towers, the gate, the quay, the courtyard and the bridge.

    The ground is left out so that a landscape can lay its own, which meets
    the castle at `ground_height`.

    Args:
        plan: The plan. It must be consistent.
        settings: The choices of the view.
        kit: The builders that receive the triangles.

    Raises:
        Error: If a mesh cannot be built.
    """
    var hull = convex_hull(plan.moat.outline)
    _water(plan, kit)
    _ring_path(plan, hull, kit)
    for wing in plan.wings:
        _wing(plan, wing, settings, kit)
    for at in range(len(plan.towers)):
        _tower(plan, plan.towers[at], at, settings, kit)
    _gate(plan, plan.gate, settings, kit)
    _quay(plan, kit)
    _courtyard(plan, kit)
    _bridge(plan, plan.gate, kit)
