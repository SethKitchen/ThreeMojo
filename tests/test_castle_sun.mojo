# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.sun`.

The references are the noon altitude of the sun, 90 degrees less the
latitude plus the declination, the length of a day at the solstices and in
the polar regions, and the right triangle that a shadow makes.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.castle.plan import wijnendale
from extensions.castle.sun import (
    castle_sun,
    day_length,
    scene_direction,
    shadow_length,
)
from extensions.energy.solar import (
    SunPosition,
    day_of_year,
    equation_of_time,
    solar_time,
    sun_position,
)
from std.math import tan
from units.si import (
    Angle64,
    DEGREE64,
    Duration64,
    HOUR,
    Length64,
    METER,
)


def _noon(day: Int) raises -> Duration64:
    """Return the clock time of solar noon at the castle on a day, in the
    time zone of one hour east of Greenwich."""
    var plan = wijnendale()
    var shift = solar_time(
        Duration64(12.0, HOUR), day, plan.longitude, Duration64(1.0, HOUR)
    ) - Duration64(12.0, HOUR)
    return Duration64(12.0, HOUR) - shift


def test_noon_altitude_at_the_solstices() raises:
    var plan = wijnendale()
    var latitude = plan.latitude.to(DEGREE64)
    var zone = Duration64(1.0, HOUR)
    var summer = castle_sun(plan, 172, _noon(172), zone)
    # 90 - 51.08 + 23.44 = 62.36 degrees.
    assert_almost_equal(
        summer.altitude().to(DEGREE64), 90.0 - latitude + 23.44, atol=0.3
    )
    var winter = castle_sun(plan, 355, _noon(355), zone)
    assert_almost_equal(
        winter.altitude().to(DEGREE64), 90.0 - latitude - 23.44, atol=0.3
    )
    assert_true(summer.is_up())


def test_the_sun_is_due_south_at_solar_noon() raises:
    var plan = wijnendale()
    var noon = castle_sun(plan, 292, _noon(292), Duration64(1.0, HOUR))
    assert_almost_equal(noon.azimuth.to(DEGREE64), 0.0, atol=0.1)


def test_the_sun_is_down_at_midnight() raises:
    var plan = wijnendale()
    var night = castle_sun(
        plan, 292, Duration64(0.0, HOUR), Duration64(1.0, HOUR)
    )
    assert_false(night.is_up())


def test_castle_sun_is_the_solar_position_of_the_site() raises:
    var plan = wijnendale()
    var day = day_of_year(10, 19)
    var clock = Duration64(15.5, HOUR)
    var zone = Duration64(2.0, HOUR)
    var a = castle_sun(plan, day, clock, zone)
    var b = sun_position(plan.latitude, plan.longitude, zone, day, clock)
    assert_almost_equal(a.zenith.value, b.zenith.value)
    assert_almost_equal(a.azimuth.value, b.azimuth.value)
    # In October the equation of time puts the sun ahead of the clock.
    assert_true(equation_of_time(day).to(HOUR) > 0.0)


def test_scene_direction_has_x_east_y_up_and_z_south() raises:
    # Due south and 45 degrees high.
    var south = scene_direction(
        SunPosition(Angle64(45.0, DEGREE64), Angle64(0.0))
    )
    assert_almost_equal(south.x, 0.0, atol=1e-12)
    assert_almost_equal(south.y, 0.7071067811865476, atol=1e-12)
    assert_almost_equal(south.z, 0.7071067811865476, atol=1e-12)
    # West is a positive azimuth, and west is toward negative x.
    var west = scene_direction(
        SunPosition(Angle64(90.0, DEGREE64), Angle64(90.0, DEGREE64))
    )
    assert_almost_equal(west.x, -1.0, atol=1e-12)
    assert_almost_equal(west.y, 0.0, atol=1e-12)
    var overhead = scene_direction(SunPosition(Angle64(0.0), Angle64(0.0)))
    assert_almost_equal(overhead.y, 1.0, atol=1e-12)


def test_shadow_is_height_over_the_tangent_of_the_altitude() raises:
    var height = Length64(28.0, METER)
    var high = SunPosition(Angle64(45.0, DEGREE64), Angle64(0.0))
    assert_almost_equal(shadow_length(height, high).value, 28.0, atol=1e-9)
    var low = SunPosition(Angle64(60.0, DEGREE64), Angle64(0.0))
    assert_almost_equal(
        shadow_length(height, low).value,
        28.0 / tan(30.0 * 3.141592653589793 / 180.0),
        atol=1e-9,
    )
    assert_true(
        shadow_length(height, low).value > shadow_length(height, high).value
    )


def test_shadow_refuses_the_night_and_a_bad_height() raises:
    var night = SunPosition(Angle64(100.0, DEGREE64), Angle64(0.0))
    with assert_raises(contains="The sun is below the horizon"):
        _ = shadow_length(Length64(10.0, METER), night)
    var day = SunPosition(Angle64(45.0, DEGREE64), Angle64(0.0))
    with assert_raises(contains="A height must be positive"):
        _ = shadow_length(Length64(0.0, METER), day)


def test_day_length_at_the_castle() raises:
    var latitude = wijnendale().latitude
    # Close to 12 hours at the equinox, 16.5 at midsummer, 7.7 at midwinter.
    assert_almost_equal(day_length(latitude, 80).to(HOUR), 12.0, atol=0.15)
    assert_almost_equal(day_length(latitude, 172).to(HOUR), 16.5, atol=0.2)
    assert_almost_equal(day_length(latitude, 355).to(HOUR), 7.7, atol=0.2)
    # 19 October, the day of the photograph.
    var october = day_length(latitude, day_of_year(10, 19)).to(HOUR)
    assert_true(october > 10.2)
    assert_true(october < 10.6)


def test_day_length_in_the_polar_regions() raises:
    var arctic = Angle64(80.0, DEGREE64)
    assert_almost_equal(day_length(arctic, 172).to(HOUR), 24.0)
    assert_almost_equal(day_length(arctic, 355).to(HOUR), 0.0)


def test_sun_refuses_a_day_outside_the_year() raises:
    var plan = wijnendale()
    with assert_raises(contains="A day of the year must be 1 to 366"):
        _ = castle_sun(plan, 0, Duration64(12.0, HOUR), Duration64(1.0, HOUR))
    with assert_raises(contains="A day of the year must be 1 to 366"):
        _ = day_length(plan.latitude, 400)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
