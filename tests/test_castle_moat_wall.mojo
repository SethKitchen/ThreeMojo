# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the quay wall as a gravity retaining wall.

The reference numbers were worked by hand, per meter of wall, from Rankine's
active pressure, the hydrostatic pressure of the moat, and a linear uplift on
the base. The wall is 5.79 m high and holds 5.09 m of earth. The moat stands
1.5 m over its foot.
"""

from extensions.castle.masonry import historic_brick
from extensions.castle.moat_wall import (
    FillSoil,
    GravityWall,
    WaterLevels,
    island_fill,
    least_thickness,
    moat_drawn_down,
    moat_full,
    quay_wall,
    wall_stability,
)
from extensions.castle.wijnendale import wijnendale_plan
from extensions.geotech.quantities import (
    KILONEWTON_PER_CUBIC_METER,
    UnitWeight64,
)
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle64, DEGREE64, Length64, METER


def _wall(thickness: Float64) raises -> GravityWall:
    var wall = quay_wall(wijnendale_plan())
    wall.thickness = Length64(thickness, METER)
    return wall^


def test_the_quay_wall_comes_from_the_plan() raises:
    var wall = quay_wall(wijnendale_plan())
    assert_almost_equal(wall.height.value, 5.79, atol=1.0e-9)
    assert_almost_equal(wall.thickness.value, 0.9, atol=1.0e-12)
    # The ground of the island is 5.09 m over the foot.
    assert_almost_equal(wall.retained.value, 5.09, atol=1.0e-9)
    var plan = wijnendale_plan()
    var full = moat_full(plan)
    assert_almost_equal(full.behind.value, 1.5, atol=1.0e-9)
    assert_almost_equal(full.front.value, 1.5, atol=1.0e-9)
    var drawn = moat_drawn_down(plan)
    assert_almost_equal(drawn.behind.value, 1.5, atol=1.0e-9)
    assert_almost_equal(drawn.front.value, 0.0, atol=1.0e-12)


def test_the_assumed_soil_is_a_sandy_loam() raises:
    var soil = island_fill()
    soil.check()
    assert_almost_equal(soil.unit_weight.value, 18000.0, atol=1.0e-9)
    assert_almost_equal(soil.saturated_unit_weight.value, 20000.0, atol=1.0e-9)
    assert_almost_equal(soil.friction.to(DEGREE64), 28.0, atol=1.0e-9)
    assert_almost_equal(
        soil.base_friction.to(DEGREE64), 28.0 * 2.0 / 3.0, atol=1.0e-9
    )


def test_a_thin_wall_cannot_hold_the_earth() raises:
    # 0.9 m of brick against 5.09 m of earth: the weight is 92 kN/m, and the
    # earth pushes with 81 kN/m, at 1.8 m over the foot on average.
    var wall = _wall(0.9)
    var stable = wall_stability(wall, moat_full(wijnendale_plan()))
    assert_almost_equal(stable.weight.value, 91984.4157, atol=0.1)
    assert_almost_equal(stable.earth_thrust.value, 81012.4545, atol=0.1)
    # The levels are equal, so the water pressures cancel.
    assert_almost_equal(stable.water_thrust.value, 0.0, atol=1.0e-6)
    assert_almost_equal(stable.uplift.value, 13238.9775, atol=0.1)
    assert_almost_equal(stable.overturning_moment.value, 147203.0256, atol=0.5)
    assert_almost_equal(stable.resisting_moment.value, 41392.9871, atol=0.5)
    assert_almost_equal(stable.overturning_factor, 0.2811966, atol=1.0e-6)
    assert_almost_equal(stable.sliding_factor, 0.3283793, atol=1.0e-6)
    # The resultant lies outside the base, behind the toe.
    assert_almost_equal(
        stable.resultant_position.value, -1.3436974, atol=1.0e-6
    )
    assert_false(stable.middle_third)
    assert_false(stable.acceptable())
    assert_true(stable.toe_pressure.value > 1.0e8)
    assert_almost_equal(stable.heel_pressure.value, 0.0, atol=1.0e-12)


def test_draining_the_moat_makes_it_worse() raises:
    var wall = _wall(0.9)
    var drawn = wall_stability(wall, moat_drawn_down(wijnendale_plan()))
    # The water of the moat no longer pushes back: 11 kN/m more thrust.
    assert_almost_equal(drawn.water_thrust.value, 11032.4812, atol=0.1)
    assert_almost_equal(drawn.uplift.value, 6619.4888, atol=0.1)
    assert_almost_equal(drawn.overturning_factor, 0.2746105, atol=1.0e-6)
    assert_almost_equal(drawn.sliding_factor, 0.3133154, atol=1.0e-6)
    var full = wall_stability(wall, moat_full(wijnendale_plan()))
    assert_true(drawn.overturning_factor < full.overturning_factor)
    assert_true(drawn.sliding_factor < full.sliding_factor)


def test_the_resultant_enters_the_base_as_the_wall_thickens() raises:
    var levels = moat_full(wijnendale_plan())
    # Between the toe and a third of the base: a triangle of pressure.
    var narrow = wall_stability(_wall(2.5), levels)
    assert_almost_equal(narrow.resultant_position.value, 0.6042689, atol=1.0e-6)
    assert_false(narrow.middle_third)
    assert_almost_equal(narrow.toe_pressure.value, 241324.474, atol=1.0)
    assert_almost_equal(narrow.heel_pressure.value, 0.0, atol=1.0e-12)
    # In the middle third: a trapezoid, with pressure at the heel.
    var thick = wall_stability(_wall(4.0), levels)
    assert_true(thick.middle_third)
    assert_almost_equal(thick.resultant_position.value, 1.5964181, atol=1.0e-6)
    assert_almost_equal(thick.toe_pressure.value, 140461.988, atol=1.0)
    assert_almost_equal(thick.heel_pressure.value, 34527.874, atol=1.0)
    assert_almost_equal(thick.overturning_factor, 3.1578192, atol=1.0e-6)
    assert_almost_equal(thick.sliding_factor, 1.4594634, atol=1.0e-6)
    # Sliding still governs at 4 m.
    assert_false(thick.acceptable())
    assert_true(wall_stability(_wall(6.0), levels).acceptable())


def test_a_dry_wall_has_no_water_load() raises:
    var wall = _wall(3.0)
    var dry = wall_stability(wall, WaterLevels(Length64(0.0), Length64(0.0)))
    assert_almost_equal(dry.water_thrust.value, 0.0, atol=1.0e-12)
    assert_almost_equal(dry.uplift.value, 0.0, atol=1.0e-12)
    assert_almost_equal(dry.overturning_factor, 3.2200467, atol=1.0e-6)
    assert_almost_equal(dry.sliding_factor, 1.2304658, atol=1.0e-6)
    assert_almost_equal(dry.resultant_position.value, 1.0341683, atol=1.0e-6)


def test_a_wall_with_nothing_to_hold_is_not_pushed() raises:
    var wall = _wall(1.0)
    wall.retained = Length64(0.0)
    var free = wall_stability(wall, WaterLevels(Length64(0.0), Length64(0.0)))
    assert_true(free.overturning_factor > 1.0e8)
    assert_true(free.sliding_factor > 1.0e8)
    assert_true(free.middle_third)


def test_the_least_thickness_of_a_free_standing_wall() raises:
    var plan = wijnendale_plan()
    var wall = quay_wall(plan)
    # Sliding governs: a wall that holds this earth must be 4.1 m thick, which
    # is 0.71 of its height, as a rectangular gravity wall is.
    var least = least_thickness(wall, moat_full(plan))
    assert_almost_equal(least.value, 4.1111, atol=0.002)
    var at = wall.copy()
    at.thickness = least
    assert_true(wall_stability(at, moat_full(plan)).acceptable())
    var under = wall.copy()
    under.thickness = Length64(0.98 * least.value)
    assert_false(wall_stability(under, moat_full(plan)).acceptable())
    var drawn = least_thickness(wall, moat_drawn_down(plan))
    assert_almost_equal(drawn.value, 4.3088, atol=0.003)
    assert_true(drawn.value > least.value)
    # A lower factor of safety needs less.
    var loose = least_thickness(wall, moat_full(plan), 1.0, 1.0)
    assert_true(loose.value < least.value)


def test_a_wall_that_no_thickness_holds_is_refused() raises:
    var plan = wijnendale_plan()
    var wall = quay_wall(plan)
    wall.soil.base_friction = Angle64(0.1, DEGREE64)
    with assert_raises(contains="30 m"):
        _ = least_thickness(wall, moat_full(plan))
    with assert_raises(contains="positive"):
        _ = least_thickness(quay_wall(plan), moat_full(plan), 0.0, 1.5)
    with assert_raises(contains="positive"):
        _ = least_thickness(quay_wall(plan), moat_full(plan), 1.5, -1.0)


def test_a_wall_and_its_soil_are_checked() raises:
    var plan = wijnendale_plan()
    var good = quay_wall(plan)
    var flat = good.copy()
    flat.height = Length64(0.0)
    with assert_raises(contains="positive finite"):
        flat.check()
    var buried = good.copy()
    buried.retained = Length64(9.0, METER)
    with assert_raises(contains="stand higher"):
        buried.check()
    var light = good.copy()
    light.soil.unit_weight = UnitWeight64(0.0)
    with assert_raises(contains="unit weight"):
        light.check()
    var dry = good.copy()
    dry.soil.saturated_unit_weight = UnitWeight64(
        5.0, KILONEWTON_PER_CUBIC_METER
    )
    with assert_raises(contains="unit weight"):
        dry.check()
    var steep = good.copy()
    steep.soil.friction = Angle64(95.0, DEGREE64)
    with assert_raises(contains="friction angle"):
        steep.check()
    with assert_raises(contains="water level"):
        _ = wall_stability(good, WaterLevels(Length64(-1.0), Length64(0.0)))
    with assert_raises(contains="water level"):
        _ = wall_stability(good, WaterLevels(Length64(1.0), Length64(-1.0)))


def test_a_size_that_is_not_a_number_is_refused() raises:
    var good = quay_wall(wijnendale_plan())
    var not_a_number = nan[DType.float64]()
    var height = good.copy()
    height.height = Length64(not_a_number, METER)
    with assert_raises(contains="positive finite"):
        height.check()
    var thickness = good.copy()
    thickness.thickness = Length64(not_a_number, METER)
    with assert_raises(contains="positive finite"):
        thickness.check()
    thickness.thickness = Length64(0.0)
    with assert_raises(contains="positive finite"):
        thickness.check()
    var retained = good.copy()
    retained.retained = Length64(not_a_number, METER)
    with assert_raises(contains="positive finite"):
        retained.check()
    retained.retained = Length64(-1.0)
    with assert_raises(contains="positive finite"):
        retained.check()
    var heavy = good.copy()
    heavy.soil.unit_weight = UnitWeight64(not_a_number)
    with assert_raises(contains="unit weight"):
        heavy.check()
    var wet = good.copy()
    wet.soil.saturated_unit_weight = UnitWeight64(not_a_number)
    with assert_raises(contains="unit weight"):
        wet.check()
    with assert_raises(contains="water level"):
        _ = wall_stability(
            good, WaterLevels(Length64(not_a_number), Length64(0.0))
        )
    with assert_raises(contains="water level"):
        _ = wall_stability(
            good, WaterLevels(Length64(1.0), Length64(not_a_number))
        )


def test_an_angle_outside_zero_to_ninety_degrees_is_refused() raises:
    var good = quay_wall(wijnendale_plan())
    var below = good.copy()
    below.soil.friction = Angle64(-1.0, DEGREE64)
    with assert_raises(contains="friction angle"):
        below.check()
    var base_below = good.copy()
    base_below.soil.base_friction = Angle64(-1.0, DEGREE64)
    with assert_raises(contains="friction angle"):
        base_below.check()
    var base_above = good.copy()
    base_above.soil.base_friction = Angle64(95.0, DEGREE64)
    with assert_raises(contains="friction angle"):
        base_above.check()


def test_water_that_lifts_the_wall_leaves_no_weight_on_the_base() raises:
    """The uplift of deep water behind a light wall is more than its weight,
    so nothing presses on the base."""
    var wall = _wall(0.9)
    var lifted = wall_stability(
        wall, WaterLevels(Length64(30.0), Length64(0.0))
    )
    assert_true(lifted.uplift.value > lifted.weight.value)
    assert_almost_equal(lifted.resultant_position.value, 0.0, atol=1.0e-12)
    assert_false(lifted.middle_third)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
