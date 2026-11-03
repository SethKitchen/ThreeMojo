# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.wall`.

The references are hand calculations of a dry wall: Rankine's thrust
Ka gamma H^2 / 2 with Ka = 1/3 at 30 degrees, and its moment gamma H^3 / 6,
and a numerical integration of the pressure diagram when water stands in the
fill.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.castle.kinds import BEARING, OVERTURNING, SLIDING
from extensions.castle.masonry import clay_brick_masonry
from extensions.castle.wall import (
    GravityWall,
    WallCheck,
    check_wall,
    required_thickness,
)
from extensions.geotech.quantities import (
    KILONEWTON_PER_CUBIC_METER,
    UnitWeight64,
)
from std.math import isinf, nan, pi, tan
from units.si import (
    Angle64,
    DEGREE,
    KILOPASCAL,
    Length64,
    LineLoad64,
    METER,
    Pressure64,
    Density64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _wall(thickness: Float64) raises -> GravityWall:
    return GravityWall(
        _m(3.0),
        _m(thickness),
        clay_brick_masonry(),
        UnitWeight64(18.0, KILONEWTON_PER_CUBIC_METER),
        Angle64(30.0, DEGREE),
        0.4,
        Pressure64(0.0),
        Pressure64(150.0, KILOPASCAL),
    )


def test_dry_wall_matches_the_hand_calculation() raises:
    var c = check_wall(_wall(2.0), _m(0.0), _m(0.0))
    # Ka = 1/3, so the thrust is (1/3) 18000 x 9 / 2 and its moment is
    # (1/3) 18000 x 27 / 6, both per meter of wall.
    var thrust = 27000.0
    var moment = 27000.0
    var weight = 1800.0 * 9.80665 * 2.0 * 3.0
    assert_almost_equal(c.horizontal.value, thrust, atol=1e-6 * thrust)
    assert_almost_equal(c.vertical.value, weight, atol=1e-6)
    var resisting = weight * 1.0
    assert_almost_equal(c.overturning, resisting / moment, atol=1e-6)
    assert_almost_equal(c.sliding, 0.4 * weight / thrust, atol=1e-6)
    var reach = (resisting - moment) / weight
    assert_almost_equal(c.eccentricity.value, abs(1.0 - reach), atol=1e-6)
    # The resultant is in the middle third: the base is a trapezoid.
    var e = c.eccentricity.value
    assert_true(e <= 2.0 / 6.0)
    assert_almost_equal(
        c.base_pressure.value, weight / 2.0 * (1.0 + 6.0 * e / 2.0), atol=1e-6
    )
    assert_almost_equal(c.bearing, 150000.0 / c.base_pressure.value)


def test_a_thin_dry_wall_leaves_the_middle_third() raises:
    var c = check_wall(_wall(1.5), _m(0.0), _m(0.0))
    var weight = 1800.0 * 9.80665 * 1.5 * 3.0
    var reach = (weight * 0.75 - 27000.0) / weight
    assert_true(c.eccentricity.value > 1.5 / 6.0)
    # The contact is a triangle over three times the distance to the edge.
    var edge = 0.75 - abs(0.75 - reach)
    assert_almost_equal(
        c.base_pressure.value, 2.0 * weight / (3.0 * edge), atol=1e-3
    )
    assert_false(c.passes(_m(1.5)))


def test_a_wall_that_tips_has_an_infinite_pressure() raises:
    var c = check_wall(_wall(0.8), _m(0.0), _m(0.0))
    assert_true(c.overturning < 1.0)
    assert_true(isinf(c.base_pressure.value))
    assert_equal(c.bearing, 0.0)
    assert_false(c.passes(_m(0.8)))


def test_water_in_the_fill_adds_thrust_and_uplift() raises:
    var wall = _wall(2.0)
    var c = check_wall(wall, _m(1.8), _m(0.0))
    # Integrate the effective pressure of the fill, with the buoyant weight
    # below the water table at 1.2 m depth, and add the water thrust.
    var gamma = 18000.0
    var gw = 9806.65
    var n = 20000
    var earth = 0.0
    var h = 3.0
    var zw = 1.2
    for k in range(n):
        var z = h * (Float64(k) + 0.5) / Float64(n)
        var sigma = gamma * z
        if z > zw:
            sigma = gamma * zw + (gamma - gw) * (z - zw)
        earth += sigma / 3.0 * h / Float64(n)
    var water = 0.5 * gw * 1.8 * 1.8
    assert_almost_equal(c.horizontal.value, earth + water, atol=0.5)
    var uplift = gw * 2.0 * 0.9
    var weight = 1800.0 * 9.80665 * 6.0
    assert_almost_equal(c.vertical.value, weight - uplift, atol=1e-6)
    var dry = check_wall(wall, _m(0.0), _m(0.0))
    assert_true(c.overturning < dry.overturning)
    assert_true(c.sliding < dry.sliding)


def test_equal_water_levels_cancel_their_lateral_thrust() raises:
    var wall = _wall(2.0)
    var same = check_wall(wall, _m(1.8), _m(1.8))
    var drawn_down = check_wall(wall, _m(1.8), _m(0.0))
    assert_true(same.horizontal.value < drawn_down.horizontal.value)
    # The water under the base is higher at the toe, so it lifts the wall more.
    assert_true(same.vertical.value < drawn_down.vertical.value)
    # The net water thrust is zero, so the horizontal force is the earth's
    # alone: the drawn-down case adds the water thrust, 0.5 gw h^2.
    assert_almost_equal(
        drawn_down.horizontal.value - same.horizontal.value,
        0.5 * 9806.65 * 1.8 * 1.8,
        atol=1e-6,
    )


def test_surcharge_adds_thrust() raises:
    var plain = _wall(2.0)
    var loaded = _wall(2.0)
    loaded.surcharge = Pressure64(10.0, KILOPASCAL)
    var a = check_wall(plain, _m(0.0), _m(0.0))
    var b = check_wall(loaded, _m(0.0), _m(0.0))
    # A uniform load q adds Ka q H to the thrust.
    assert_almost_equal(
        b.horizontal.value - a.horizontal.value,
        10000.0 * 3.0 / 3.0,
        atol=1e-6,
    )


def test_governing_names_the_least_factor() raises:
    var c = WallCheck(
        2.0,
        1.0,
        _m(0.1),
        Pressure64(1.0),
        3.0,
        LineLoad64(1.0),
        LineLoad64(1.0),
    )
    assert_equal(c.governing(), SLIDING)
    c.overturning = 0.5
    assert_equal(c.governing(), OVERTURNING)
    c.overturning = 2.0
    c.sliding = 2.0
    c.bearing = 1.5
    assert_equal(c.governing(), BEARING)
    c.bearing = 2.0
    assert_equal(c.governing(), OVERTURNING)


def test_passes_needs_every_limit() raises:
    var good = WallCheck(
        2.0,
        2.0,
        _m(0.2),
        Pressure64(1.0),
        2.0,
        LineLoad64(1.0),
        LineLoad64(1.0),
    )
    assert_true(good.passes(_m(2.0)))
    var tips = good
    tips.overturning = 1.4
    assert_false(tips.passes(_m(2.0)))
    var slides = good
    slides.sliding = 1.4
    assert_false(slides.passes(_m(2.0)))
    var sinks = good
    sinks.bearing = 0.9
    assert_false(sinks.passes(_m(2.0)))
    var off_center = good
    off_center.eccentricity = _m(0.5)
    assert_false(off_center.passes(_m(2.0)))


def test_required_thickness_is_the_least_that_passes() raises:
    var wall = _wall(1.0)
    var t = required_thickness(wall, _m(0.0), _m(0.0))
    var ok = _wall(t.value)
    assert_true(check_wall(ok, _m(0.0), _m(0.0)).passes(t))
    var short = _wall(t.value * 0.99)
    assert_false(check_wall(short, _m(0.0), _m(0.0)).passes(short.thickness))
    # Water in the fill, with the moat down, asks for a thicker wall.
    var wet = required_thickness(wall, _m(1.8), _m(0.0))
    assert_true(wet.value > t.value)
    # The thickness of the argument is not read.
    var other = required_thickness(_wall(5.0), _m(0.0), _m(0.0))
    assert_almost_equal(other.value, t.value)


def test_required_thickness_refuses_ground_that_cannot_carry_the_wall() raises:
    var wall = _wall(1.0)
    wall.allowable = Pressure64(1.0, KILOPASCAL)
    with assert_raises(contains="No thickness up to four times the height"):
        _ = required_thickness(wall, _m(0.0), _m(0.0))


def test_check_refuses_what_is_not_a_wall() raises:
    var wall = _wall(2.0)
    wall.masonry.density = Density64(0.0)
    with assert_raises(contains="A masonry density must be positive"):
        wall.check()
    wall = _wall(2.0)
    wall.height = _m(0.0)
    with assert_raises(contains="A wall height must be positive"):
        wall.check()
    wall = _wall(2.0)
    wall.thickness = _m(0.0)
    with assert_raises(contains="A wall thickness must be positive"):
        wall.check()
    wall = _wall(2.0)
    wall.fill_weight = UnitWeight64(0.0)
    with assert_raises(contains="A fill weight must be positive"):
        wall.check()
    wall = _wall(2.0)
    wall.friction_angle = Angle64(0.0)
    with assert_raises(contains="A friction angle must be positive"):
        wall.check()
    wall = _wall(2.0)
    wall.base_friction = nan[DType.float64]()
    with assert_raises(contains="A base friction must be positive"):
        wall.check()
    wall = _wall(2.0)
    wall.allowable = Pressure64(0.0)
    with assert_raises(contains="An allowable pressure must be positive"):
        wall.check()
    wall = _wall(2.0)
    wall.surcharge = Pressure64(-1.0)
    with assert_raises(contains="A surcharge must be zero or more"):
        wall.check()
    wall.surcharge = Pressure64(1.0e13)
    with assert_raises(contains="A surcharge must be zero or more"):
        wall.check()


def test_check_wall_refuses_water_outside_the_wall() raises:
    var wall = _wall(2.0)
    with assert_raises(contains="The water table must be between"):
        _ = check_wall(wall, _m(-0.1), _m(0.0))
    with assert_raises(contains="The water table must be between"):
        _ = check_wall(wall, _m(3.5), _m(0.0))
    with assert_raises(contains="The front water must be between"):
        _ = check_wall(wall, _m(1.0), _m(-0.1))
    with assert_raises(contains="The front water must be between"):
        _ = check_wall(wall, _m(1.0), _m(3.5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
