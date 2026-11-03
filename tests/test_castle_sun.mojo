# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the position of the sun.

The references are facts of the sky: the declination at the solstices, the
altitude of the sun at noon, the length of the day at Torhout in October,
and the symmetry of a day about solar noon.
"""

from extensions.castle.sun import (
    SunPosition,
    day_of_year,
    is_leap_year,
    shadow_length,
    shadow_tip,
    solar_noon,
    solar_position,
    sunrise_and_sunset,
)
from extensions.castle.wijnendale import latitude, longitude
from std.math import nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle64, DEGREE64, Duration64, Length64, METER

# 19 October 2026 is the 292nd day of a year of 365 days.
comptime _DAY = 292


def _degrees(angle: Angle64) -> Float64:
    return angle.to(DEGREE64)


def test_the_days_of_the_year_are_counted() raises:
    assert_equal(day_of_year(2026, 1, 1), 1)
    assert_equal(day_of_year(2026, 10, 19), 292)
    assert_equal(day_of_year(2026, 12, 31), 365)
    assert_equal(day_of_year(2028, 12, 31), 366)
    assert_equal(day_of_year(2028, 3, 1), 61)
    with assert_raises():
        _ = day_of_year(2026, 13, 1)
    with assert_raises():
        _ = day_of_year(2026, 0, 1)
    with assert_raises():
        _ = day_of_year(2026, 2, 29)
    with assert_raises():
        _ = day_of_year(2026, 4, 0)


def test_leap_years_follow_the_gregorian_rule() raises:
    assert_true(is_leap_year(2028))
    assert_false(is_leap_year(2026))
    assert_false(is_leap_year(1900))
    assert_true(is_leap_year(2000))


def test_the_declination_reaches_the_tilt_of_the_earth_at_the_solstices() raises:
    var summer = solar_position(latitude(), longitude(), 2026, 172, 12.0)
    var winter = solar_position(latitude(), longitude(), 2026, 355, 12.0)
    assert_almost_equal(_degrees(summer.declination), 23.44, atol=0.05)
    assert_almost_equal(_degrees(winter.declination), -23.43, atol=0.05)


def test_the_declination_is_near_zero_at_the_equinox() raises:
    var march = solar_position(latitude(), longitude(), 2026, 80, 12.0)
    assert_true(abs(_degrees(march.declination)) < 0.8)


def test_the_sun_stands_at_the_height_the_latitude_allows_at_noon() raises:
    # The noon altitude is 90 degrees less the latitude plus the declination.
    var hours = solar_noon(longitude(), 2026, 172).value / 3600.0
    var position = solar_position(latitude(), longitude(), 2026, 172, hours)
    var wanted = 90.0 - _degrees(latitude()) + _degrees(position.declination)
    assert_almost_equal(_degrees(position.altitude), wanted, atol=0.05)
    assert_almost_equal(_degrees(position.altitude), 62.36, atol=0.3)
    # Due south at noon.
    assert_almost_equal(_degrees(position.azimuth), 180.0, atol=0.5)


def test_the_october_day_at_torhout() raises:
    var noon = solar_noon(longitude(), 2026, _DAY).value / 3600.0
    # The equation of time is about 15 minutes on 19 October and the site is
    # 3.06 degrees east, so noon falls at 11:33 UTC, 13:33 local time.
    assert_almost_equal(noon, 11.55, atol=0.01)
    var position = solar_position(latitude(), longitude(), 2026, _DAY, noon)
    # The values of Meeus for 12:00 UTC on 19 October 2026.
    assert_almost_equal(_degrees(position.declination), -10.08, atol=0.05)
    assert_almost_equal(_degrees(position.altitude), 28.84, atol=0.1)
    assert_almost_equal(
        position.equation_of_time.value / 60.0, 15.06, atol=0.15
    )
    var times = sunrise_and_sunset(latitude(), longitude(), 2026, _DAY)
    var rise = times[0].value / 3600.0
    var set = times[1].value / 3600.0
    var length = set - rise
    # The day is 10 hours 29 minutes long: the hour angle of the horizon is
    # 78.7 degrees for a declination of -10.1 degrees at this latitude.
    assert_almost_equal(length, 10.49, atol=0.03)
    # A day is symmetric about solar noon, to the change of the declination
    # and of the equation of time during it.
    assert_almost_equal((rise + set) / 2.0, noon, atol=0.02)
    # The sun is on the horizon at sunrise and at sunset.
    var at_rise = solar_position(latitude(), longitude(), 2026, _DAY, rise)
    var at_set = solar_position(latitude(), longitude(), 2026, _DAY, set)
    assert_almost_equal(_degrees(at_rise.altitude), -0.833, atol=0.3)
    assert_almost_equal(_degrees(at_set.altitude), -0.833, atol=0.3)
    # It rises in the south-east and sets in the south-west.
    assert_true(_degrees(at_rise.azimuth) > 100.0)
    assert_true(_degrees(at_rise.azimuth) < 130.0)
    assert_true(_degrees(at_set.azimuth) > 230.0)
    assert_true(_degrees(at_set.azimuth) < 260.0)


def test_the_sun_rises_in_the_east_at_the_equinox_on_the_equator() raises:
    var equator = Angle64(0.0)
    var meridian = Angle64(0.0)
    var times = sunrise_and_sunset(equator, meridian, 2026, 80)
    var rise = times[0].value / 3600.0
    var position = solar_position(equator, meridian, 2026, 80, rise)
    assert_almost_equal(_degrees(position.azimuth), 90.0, atol=2.0)
    # Noon at the equator at the equinox, the sun is overhead.
    var noon = solar_noon(meridian, 2026, 80).value / 3600.0
    var high = solar_position(equator, meridian, 2026, 80, noon)
    assert_almost_equal(_degrees(high.altitude), 90.0, atol=1.5)


def test_the_sun_is_below_the_horizon_at_midnight() raises:
    var position = solar_position(latitude(), longitude(), 2026, _DAY, 0.0)
    assert_false(position.above_horizon())
    assert_true(_degrees(position.altitude) < -30.0)


def test_the_direction_toward_the_sun_is_a_unit_vector() raises:
    var position = solar_position(latitude(), longitude(), 2026, _DAY, 14.0)
    var toward = position.toward()
    var length2 = (
        toward[0] * toward[0] + toward[1] * toward[1] + toward[2] * toward[2]
    )
    assert_almost_equal(length2, 1.0, atol=1.0e-12)
    assert_true(toward[2] > 0.0)
    # In the afternoon the sun is in the south and the west.
    assert_true(toward[0] < 0.0)
    assert_true(toward[1] < 0.0)


def test_a_shadow_is_as_long_as_the_post_at_forty_five_degrees() raises:
    var position = SunPosition(
        Angle64(pi / 4.0), Angle64(pi), Angle64(0.0), Duration64(0.0)
    )
    var length = shadow_length(Length64(10.0, METER), position)
    assert_almost_equal(length.value, 10.0, atol=1.0e-9)
    # With the sun due south, the shadow runs due north.
    var tip = shadow_tip(Length64(10.0, METER), position)
    assert_almost_equal(tip[0].value, 0.0, atol=1.0e-9)
    assert_almost_equal(tip[1].value, 10.0, atol=1.0e-9)


def test_the_donjon_throws_a_long_shadow_in_october() raises:
    var noon = solar_noon(longitude(), 2026, _DAY).value / 3600.0
    var position = solar_position(latitude(), longitude(), 2026, _DAY, noon)
    # The donjon stands 25.7 m over the courtyard.
    var length = shadow_length(Length64(25.7, METER), position)
    assert_true(length.value > 45.0)
    assert_true(length.value < 50.0)


def test_a_shadow_needs_the_sun_over_the_horizon() raises:
    var night = solar_position(latitude(), longitude(), 2026, _DAY, 0.0)
    with assert_raises(contains="horizon"):
        _ = shadow_length(Length64(10.0, METER), night)
    var day = solar_position(latitude(), longitude(), 2026, _DAY, 12.0)
    with assert_raises(contains="height"):
        _ = shadow_length(Length64(-1.0, METER), day)
    with assert_raises(contains="height"):
        _ = shadow_length(Length64(2.0e9, METER), day)
    with assert_raises(contains="height"):
        _ = shadow_tip(Length64(-1.0, METER), day)


def test_a_site_must_be_on_the_earth() raises:
    with assert_raises(contains="latitude"):
        _ = solar_position(Angle64(2.0), longitude(), 2026, _DAY, 12.0)
    with assert_raises(contains="latitude"):
        _ = solar_position(Angle64(-2.0), longitude(), 2026, _DAY, 12.0)
    with assert_raises(contains="longitude"):
        _ = solar_position(latitude(), Angle64(4.0), 2026, _DAY, 12.0)
    with assert_raises(contains="longitude"):
        _ = solar_position(latitude(), Angle64(-4.0), 2026, _DAY, 12.0)
    with assert_raises(contains="longitude"):
        _ = solar_noon(Angle64(4.0), 2026, _DAY)
    with assert_raises(contains="latitude"):
        _ = sunrise_and_sunset(Angle64(2.0), longitude(), 2026, _DAY)


def test_a_day_and_a_time_must_exist() raises:
    with assert_raises(contains="day number"):
        _ = solar_position(latitude(), longitude(), 2026, 366, 12.0)
    with assert_raises(contains="day number"):
        _ = solar_position(latitude(), longitude(), 2026, 0, 12.0)
    with assert_raises(contains="day number"):
        _ = solar_noon(longitude(), 2026, 0)
    with assert_raises(contains="day number"):
        _ = solar_noon(longitude(), 2026, 366)
    with assert_raises(contains="day number"):
        _ = sunrise_and_sunset(latitude(), longitude(), 2026, 400)
    with assert_raises(contains="day number"):
        _ = sunrise_and_sunset(latitude(), longitude(), 2026, 0)
    with assert_raises(contains="time"):
        _ = solar_position(latitude(), longitude(), 2026, _DAY, 1.0e9)
    with assert_raises(contains="time"):
        _ = solar_position(
            latitude(), longitude(), 2026, _DAY, nan[DType.float64]()
        )


def test_the_sun_does_not_set_in_a_polar_summer() raises:
    with assert_raises(contains="rise and set"):
        _ = sunrise_and_sunset(
            Angle64(80.0 * pi / 180.0), Angle64(0.0), 2026, 172
        )


def test_the_sun_does_not_rise_in_a_polar_winter() raises:
    with assert_raises(contains="rise and set"):
        _ = sunrise_and_sunset(
            Angle64(80.0 * pi / 180.0), Angle64(0.0), 2026, 355
        )


def test_a_leap_year_has_a_day_366() raises:
    var position = solar_position(latitude(), longitude(), 2028, 366, 12.0)
    assert_true(abs(_degrees(position.declination) + 23.2) < 0.4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
