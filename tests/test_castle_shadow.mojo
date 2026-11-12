# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the shadows of the castle on its courtyard."""

from extensions.castle.plan import Tower, point, polygon_contains
from extensions.castle.shadow import (
    courtyard_points,
    donjon_shadow,
    is_in_sun,
    lit_fraction,
)
from extensions.castle.sun import SunPosition
from extensions.castle.wijnendale import wijnendale_plan
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle64, Duration64, Length64, METER


def _sun(altitude: Float64, azimuth: Float64) -> SunPosition:
    return SunPosition(
        Angle64(altitude * pi / 180.0),
        Angle64(azimuth * pi / 180.0),
        Angle64(0.0),
        Duration64(0.0),
    )


def test_the_courtyard_is_the_island_outside_the_buildings() raises:
    var plan = wijnendale_plan()
    var points = courtyard_points(plan, Length64(2.0, METER))
    # 381 cells of 4 m^2: about 1500 m^2 of lawn and path.
    assert_true(len(points) > 370)
    assert_true(len(points) < 395)
    for at in points:
        assert_false(polygon_contains(plan.moat.outline, at))
    for tower in plan.towers:
        for at in points:
            var dx = at.x.value - tower.center.x.value
            var dy = at.y.value - tower.center.y.value
            assert_true(dx * dx + dy * dy >= tower.radius.value**2)


def test_a_courtyard_step_is_checked() raises:
    var plan = wijnendale_plan()
    with assert_raises(contains="step"):
        _ = courtyard_points(plan, Length64(0.0, METER))
    with assert_raises(contains="step"):
        _ = courtyard_points(plan, Length64(2.0e6, METER))
    with assert_raises(contains="no point"):
        _ = lit_fraction(plan, _sun(30.0, 180.0), Length64(1000.0, METER))


def test_a_low_sun_over_open_ground_lights_a_point() raises:
    """The ray runs its whole length without meeting a solid or climbing
    over the towers."""
    var plan = wijnendale_plan()
    assert_true(is_in_sun(plan, point(1000.0, 1000.0), _sun(0.5, 90.0)))


def test_the_sun_overhead_lights_all_of_it() raises:
    var plan = wijnendale_plan()
    assert_almost_equal(
        lit_fraction(plan, _sun(90.0, 180.0), Length64(2.0, METER)),
        1.0,
        atol=1.0e-12,
    )


def test_the_sun_under_the_horizon_lights_none_of_it() raises:
    var plan = wijnendale_plan()
    assert_almost_equal(
        lit_fraction(plan, _sun(-5.0, 180.0), Length64(2.0, METER)),
        0.0,
        atol=0.0,
    )
    assert_false(is_in_sun(plan, point(20.0, 40.0), _sun(-5.0, 180.0)))


def test_the_wings_and_the_gate_shade_the_courtyard() raises:
    var plan = wijnendale_plan()
    var step = Length64(2.0, METER)
    # From the south at 30 degrees the north wing and the donjon throw shade.
    assert_almost_equal(
        lit_fraction(plan, _sun(30.0, 180.0), step), 0.7427822, atol=1.0e-6
    )
    # From the south-west the lawn is open: the walls on that side are low.
    assert_almost_equal(
        lit_fraction(plan, _sun(30.0, 225.0), step), 0.9265092, atol=1.0e-6
    )
    # From the south-east, low, the gate block and the south wing shade most of
    # it.
    assert_almost_equal(
        lit_fraction(plan, _sun(10.0, 135.0), step), 0.2047244, atol=1.0e-6
    )
    # A lower sun shades more.
    assert_true(
        lit_fraction(plan, _sun(10.0, 135.0), step)
        < lit_fraction(plan, _sun(60.0, 135.0), step)
    )


def test_a_point_north_of_the_donjon_is_in_its_shadow() raises:
    var plan = wijnendale_plan()
    # The donjon stands at (13.6, 68.4) and is 25.7 m over the courtyard. With
    # the sun due south at 28.8 degrees its shadow reaches 46.7 m to the north.
    var sun = _sun(28.84, 180.0)
    assert_false(is_in_sun(plan, point(13.6, 82.0), sun))
    # A point west of the castle, on the island, is in the sun.
    assert_true(is_in_sun(plan, point(8.0, 30.0), sun))


def test_the_shadow_of_the_donjon_falls_away_from_the_sun() raises:
    var plan = wijnendale_plan()
    var shadow = donjon_shadow(plan, _sun(28.84, 180.0))
    assert_almost_equal(shadow[0].value, 46.6528, atol=0.01)
    assert_almost_equal(shadow[1].value, 0.0, atol=1.0e-6)
    assert_almost_equal(shadow[2].value, 46.6528, atol=0.01)
    var west = donjon_shadow(plan, _sun(28.84, 270.0))
    # With the sun in the west the shadow runs east.
    assert_almost_equal(west[1].value, 46.6528, atol=0.01)
    assert_almost_equal(west[2].value, 0.0, atol=1.0e-6)
    with assert_raises(contains="horizon"):
        _ = donjon_shadow(plan, _sun(-1.0, 180.0))
    var empty = wijnendale_plan()
    empty.towers = List[Tower]()
    with assert_raises(contains="tower"):
        _ = donjon_shadow(empty, _sun(30.0, 180.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
