# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the ground of a castle in a landscape: the settings, the rings
and how they meet, the height and the flatness of the triangles that are
drawn, and the finding of a site.

The geometry is checked against facts that do not come from the code: a
triangle is a plane through its three corners, the middle of a cell lies on
its diagonal, and two rings meet along a line with no gap.
"""

from extensions.castle.landscape import (
    build_landscape,
    default_landscape,
    find_site,
)
from extensions.castle.plan import convex_hull, point
from extensions.castle.render import ground_height
from extensions.castle.wijnendale import wijnendale_plan
from std.math import nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._castle_land import plateau, rolling, small_settings
from tests._castle_small import small_plan
from units.si import Length64, METER


def test_the_defaults_make_a_landscape() raises:
    var settings = default_landscape()
    settings.check()
    assert_almost_equal(settings.relief.value, 1500.0)
    assert_almost_equal(settings.near_step.value, 1.0)
    assert_almost_equal(settings.reach.value, 9600.0)
    assert_true(settings.treeline.value < settings.snow_line.value)


def test_each_number_of_the_settings_is_checked() raises:
    var not_a_number = nan[DType.float64]()
    var relief = default_landscape()
    relief.relief = Length64(not_a_number, METER)
    with assert_raises(contains="positive finite"):
        relief.check()
    relief.relief = Length64(0.0, METER)
    with assert_raises(contains="positive finite"):
        relief.check()
    var hills = default_landscape()
    hills.hills_radius = Length64(100.0, METER)
    with assert_raises(contains="past the plain"):
        hills.check()
    var share = default_landscape()
    share.plain_share = 1.5
    with assert_raises(contains="from 0 to 1"):
        share.check()
    share.plain_share = -0.1
    with assert_raises(contains="from 0 to 1"):
        share.check()
    share.plain_share = not_a_number
    with assert_raises(contains="from 0 to 1"):
        share.check()
    var octaves = default_landscape()
    octaves.octaves = 0
    with assert_raises(contains="an octave and a segment"):
        octaves.check()
    var segments = default_landscape()
    segments.segments = 0
    with assert_raises(contains="an octave and a segment"):
        segments.check()
    var trees = default_landscape()
    trees.treeline = Length64(500.0, METER)
    with assert_raises(contains="under the snow line"):
        trees.check()
    var haze = default_landscape()
    haze.haze = not_a_number
    with assert_raises(contains="haze"):
        haze.check()
    haze.haze = -1.0
    with assert_raises(contains="haze"):
        haze.check()


def test_a_reach_too_short_for_the_castle_is_refused() raises:
    var settings = small_settings()
    settings.reach = Length64(800.0, METER)
    with assert_raises(contains="too short"):
        _ = build_landscape(small_plan(), settings)


def test_the_ground_is_the_castles_own_round_the_moat() raises:
    var plan = small_plan()
    var land = build_landscape(plan, small_settings())
    assert_equal(len(land.rings), 4)
    var hull = convex_hull(plan.moat.outline)
    ref fine = land.rings[0]
    # At the vertices of the finest ring, a long way inside it, the height is
    # what the plan says.
    for k in range(-3, 4):
        var x = land.middle_x + Float64(k) * 20.0
        var y = land.middle_y + Float64(k) * 10.0
        assert_almost_equal(
            land.height(x, y),
            ground_height(plan, hull, point(x, y)),
            atol=1.0e-9,
        )
    assert_almost_equal(land.level, -3.59, atol=1.0e-9)
    assert_almost_equal(land.ground, -1.3, atol=1.0e-9)
    assert_equal(land.ring_at(land.middle_x, land.middle_y), 0)
    assert_true(fine.half < land.rings[1].half)


def test_the_rings_step_out_and_cover_the_reach() raises:
    var land = build_landscape(small_plan(), small_settings())
    assert_almost_equal(land.rings[0].step, 5.0)
    assert_almost_equal(land.rings[1].step, 25.0)
    assert_almost_equal(land.rings[2].step, 100.0)
    assert_almost_equal(land.rings[3].step, 400.0)
    assert_almost_equal(land.rings[3].half, 6400.0)
    assert_almost_equal(land.rings[2].half, 1600.0)
    assert_almost_equal(land.rings[1].half, 400.0)
    assert_almost_equal(land.rings[1].hole, land.rings[0].half)
    # A point in each ring, and one beyond the last, which reads its edge.
    assert_equal(land.ring_at(land.middle_x + 300.0, land.middle_y), 1)
    assert_equal(land.ring_at(land.middle_x, land.middle_y - 1000.0), 2)
    assert_equal(land.ring_at(land.middle_x + 3000.0, land.middle_y), 3)
    assert_equal(land.ring_at(land.middle_x + 9000.0, land.middle_y), 3)


def test_two_rings_meet_with_no_crack() raises:
    var land = build_landscape(small_plan(), small_settings())
    for ring in range(3):
        ref fine = land.rings[ring]
        ref coarse = land.rings[ring + 1]
        var columns = fine.columns
        var width = 2.0 * fine.half
        for k in range(columns):
            var along = fine.x0 + Float64(k) * fine.step
            var across = fine.y0 + Float64(k) * fine.step
            # The four edges of the fine ring lie on the coarse ring's
            # triangles.
            assert_almost_equal(
                fine.heights[k], coarse.sample(along, fine.y0), atol=1.0e-9
            )
            assert_almost_equal(
                fine.heights[(columns - 1) * columns + k],
                coarse.sample(along, fine.y0 + width),
                atol=1.0e-9,
            )
            assert_almost_equal(
                fine.heights[k * columns],
                coarse.sample(fine.x0, across),
                atol=1.0e-9,
            )
            assert_almost_equal(
                fine.heights[k * columns + columns - 1],
                coarse.sample(fine.x0 + width, across),
                atol=1.0e-9,
            )


def test_the_mountains_rise_far_off_and_basins_hold_lakes() raises:
    var settings = small_settings()
    settings.relief = Length64(1500.0, METER)
    var land = build_landscape(small_plan(), settings)
    var highest = Float64(-1.0e30)
    var lowest = Float64(1.0e30)
    for j in range(60):
        for i in range(60):
            var x = land.middle_x + (Float64(i) - 30.0) * 200.0
            var y = land.middle_y + (Float64(j) - 30.0) * 200.0
            highest = max(highest, land.altitude(x, y))
            lowest = min(lowest, land.altitude(x, y))
    # The mountains stand hundreds of meters over the plain, and a basin
    # sinks under the water.
    assert_true(highest > 150.0)
    assert_true(lowest < 0.0)
    # The meadow round the castle is flat and dry.
    assert_true(
        land.flatness(land.middle_x + 130.0, land.middle_y + 130.0) > 0.99
    )
    assert_true(
        land.altitude(land.middle_x + 130.0, land.middle_y + 130.0) > 0.5
    )


def _plane(
    x0: Float64,
    y0: Float64,
    h0: Float64,
    x1: Float64,
    y1: Float64,
    h1: Float64,
    x2: Float64,
    y2: Float64,
    h2: Float64,
    x: Float64,
    y: Float64,
) -> Float64:
    """Return the height at a point of the plane through three points."""
    var e1x = x1 - x0
    var e1y = y1 - y0
    var e1z = h1 - h0
    var e2x = x2 - x0
    var e2y = y2 - y0
    var e2z = h2 - h0
    var nx = e1y * e2z - e1z * e2y
    var ny = e1z * e2x - e1x * e2z
    var nz = e1x * e2y - e1y * e2x
    return h0 - (nx * (x - x0) + ny * (y - y0)) / nz


def _flat_of(
    x0: Float64,
    y0: Float64,
    h0: Float64,
    x1: Float64,
    y1: Float64,
    h1: Float64,
    x2: Float64,
    y2: Float64,
    h2: Float64,
) -> Float64:
    """Return the vertical component of the unit normal of the plane through
    three points."""
    var e1x = x1 - x0
    var e1y = y1 - y0
    var e1z = h1 - h0
    var e2x = x2 - x0
    var e2y = y2 - y0
    var e2z = h2 - h0
    var nx = e1y * e2z - e1z * e2y
    var ny = e1z * e2x - e1x * e2z
    var nz = e1x * e2y - e1y * e2x
    return abs(nz) / sqrt(nx * nx + ny * ny + nz * nz)


def test_a_triangle_is_a_plane_through_its_corners() raises:
    var land = rolling()
    ref grid = land.rings[0]
    # Two cells, one of each diagonal: (3, 4) is odd, (4, 4) is even. A point
    # in each of their two triangles reads the plane through the corners.
    for cell in range(2):
        var i = 3 + cell
        var j = 4
        var a = grid.heights[j * 41 + i]
        var b = grid.heights[j * 41 + i + 1]
        var c = grid.heights[(j + 1) * 41 + i + 1]
        var d = grid.heights[(j + 1) * 41 + i]
        var left = grid.x0 + Float64(i) * 10.0
        var low = grid.y0 + Float64(j) * 10.0
        var right = left + 10.0
        var high = low + 10.0
        var shares: List[Float64] = [
            0.75,
            0.25,
            0.25,
            0.75,
            0.25,
            0.25,
            0.75,
            0.75,
        ]
        for place in range(4):
            var fx = shares[place * 2]
            var fy = shares[place * 2 + 1]
            var x = left + fx * 10.0
            var y = low + fy * 10.0
            var expected: Float64
            var flat: Float64
            if (i + j) % 2 == 0:
                # The diagonal runs from a to c.
                if fx >= fy:
                    expected = _plane(
                        left, low, a, right, low, b, right, high, c, x, y
                    )
                    flat = _flat_of(left, low, a, right, low, b, right, high, c)
                else:
                    expected = _plane(
                        left, low, a, right, high, c, left, high, d, x, y
                    )
                    flat = _flat_of(left, low, a, right, high, c, left, high, d)
            else:
                # The diagonal runs from b to d.
                if fx + fy <= 1.0:
                    expected = _plane(
                        left, low, a, right, low, b, left, high, d, x, y
                    )
                    flat = _flat_of(left, low, a, right, low, b, left, high, d)
                else:
                    expected = _plane(
                        right, low, b, right, high, c, left, high, d, x, y
                    )
                    flat = _flat_of(
                        right, low, b, right, high, c, left, high, d
                    )
            assert_almost_equal(land.height(x, y), expected, atol=1.0e-9)
            assert_almost_equal(land.flatness(x, y), flat, atol=1.0e-9)


def test_the_middle_of_a_cell_lies_on_its_diagonal() raises:
    var land = rolling()
    ref grid = land.rings[0]
    for j in range(6, 9):
        for i in range(6, 9):
            var a = grid.heights[j * 41 + i]
            var b = grid.heights[j * 41 + i + 1]
            var c = grid.heights[(j + 1) * 41 + i + 1]
            var d = grid.heights[(j + 1) * 41 + i]
            var x = grid.x0 + (Float64(i) + 0.5) * 10.0
            var y = grid.y0 + (Float64(j) + 0.5) * 10.0
            var through = (a + c) / 2.0 if (i + j) % 2 == 0 else (b + d) / 2.0
            assert_almost_equal(land.height(x, y), through, atol=1.0e-9)
    # At a corner the height is the grid's own, and the edges are straight.
    assert_almost_equal(
        land.height(-200.0, -200.0), grid.heights[0], atol=1.0e-9
    )
    assert_almost_equal(
        land.height(-195.0, -200.0),
        (grid.heights[0] + grid.heights[1]) / 2.0,
        atol=1.0e-9,
    )


def test_a_vertex_has_a_unit_normal_that_points_up() raises:
    var land = rolling()
    ref grid = land.rings[0]
    for k in range(4):
        var i = 0 if k == 0 or k == 1 else 40
        var j = 0 if k == 0 or k == 2 else 40
        var n = grid.normal(i, j)
        assert_almost_equal(n.length(), 1.0, atol=1.0e-9)
        assert_true(n.z > 0.0)
    var inside = grid.normal(20, 20)
    assert_almost_equal(inside.length(), 1.0, atol=1.0e-9)


def test_the_height_over_the_water_and_the_noise_are_in_range() raises:
    var land = rolling()
    assert_almost_equal(
        land.altitude(0.0, 0.0), land.height(0.0, 0.0) - land.level
    )
    assert_true(land.distance_from_moat(0.0, 0.0) > 3000.0)
    for k in range(20):
        var patches = land.patches(
            Float64(k) * 37.0, Float64(k) * 11.0, 80.0, k
        )
        var grove = land.grove(Float64(k) * 37.0, Float64(k) * 11.0)
        assert_true(patches >= 0.0 and patches <= 1.0)
        assert_true(grove >= 0.0 and grove <= 1.0)


def test_a_site_is_level_dry_and_clear_of_the_moat() raises:
    var land = plateau()
    # The place itself is good.
    var here = find_site(land, -100.0, 0.0, 20.0, 30.0)
    assert_almost_equal(here.x.value, -100.0, atol=1.0e-9)
    assert_almost_equal(here.y.value, 0.0, atol=1.0e-9)
    # A place on the steep ramp is not, and the nearest level ground is west
    # of it.
    var ramp = find_site(land, 115.0, 0.0, 6.0, 30.0)
    assert_true(ramp.x.value < 100.0)
    # A place on the high shelf is level but over the limit of 25 m.
    var shelf = find_site(land, 180.0, 0.0, 6.0, 30.0)
    assert_true(shelf.x.value < 100.0)
    # A place on the low field is under 2 m.
    var field = find_site(land, 0.0, -170.0, 6.0, 30.0)
    assert_true(field.y.value > -150.0)
    # A place by the moat is too near it.
    var bank = find_site(land, 0.0, -100.0, 6.0, 40.0)
    assert_true(land.distance_from_moat(bank.x.value, bank.y.value) >= 40.0)


def test_a_site_that_cannot_be_found_is_refused() raises:
    var land = plateau()
    with assert_raises(contains="No level dry ground"):
        _ = find_site(land, 0.0, 0.0, 20.0, 1.0e9)


def test_the_plan_of_wijnendale_has_room_for_the_landscape() raises:
    # The levels of the plan: water 3.59 m under the island, meadow 1.3 m.
    var plan = wijnendale_plan()
    var land = build_landscape(plan, small_settings())
    assert_almost_equal(
        land.level,
        plan.moat.water_level.value - plan.island_level.value,
        atol=1.0e-9,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
