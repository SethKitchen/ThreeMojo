# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sun over a site: where it stands at a time, when it rises and sets, and
how far a tower throws its shadow.

The position follows Meeus, Astronomical Algorithms, 2nd edition, 1998: the
low-accuracy coordinates of the sun of chapter 25, the equation of time of
chapter 28, and the hour angle and the altitude of chapter 13. Their error is
about 0.01 degree in the declination, and a few seconds in the equation of
time. That is far inside the width of the edge of a shadow.

Times are hours of Coordinated Universal Time. Local time at Torhout is two
hours ahead on 19 October 2026, for summer time ends on 25 October. A day is
its number in the year, counted from 1 on 1 January.

Azimuth runs clockwise from north: 90 degrees is east, 180 degrees south.
"""

from std.math import acos, asin, atan2, cos, floor, pi, sin, sqrt, tan
from units.si import Angle64, DEGREE64, Duration64, Length64

# The zenith distance of the center of the sun at sunrise and sunset: 90
# degrees, plus 34 arc minutes of refraction and 16 of the radius of the disc.
comptime _SUNRISE_ZENITH = 1.5853349194640094


@fieldwise_init
struct SunPosition(Copyable, Movable):
    """Where the sun is, and the two numbers that the position follows from."""

    # The height of the center of the sun over the horizon.
    var altitude: Angle64
    # The bearing of the sun, clockwise from north.
    var azimuth: Angle64
    # The angle of the sun north of the equator of the sky.
    var declination: Angle64
    # How far apparent solar time is ahead of mean solar time.
    var equation_of_time: Duration64

    def above_horizon(self) -> Bool:
        """Return True if the center of the sun is over the horizon.

        Returns:
            Whether the altitude is positive.
        """
        return self.altitude.value > 0.0

    def toward(self) -> Tuple[Float64, Float64, Float64]:
        """Return the unit direction toward the sun.

        Returns:
            The east, the north and the up component.
        """
        var altitude = self.altitude.value
        var azimuth = self.azimuth.value
        var flat = cos(altitude)
        return (flat * sin(azimuth), flat * cos(azimuth), sin(altitude))


def is_leap_year(year: Int) -> Bool:
    """Return True if a year has 366 days.

    Args:
        year: The year of the Gregorian calendar.

    Returns:
        Whether it is a leap year.
    """
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


def day_of_year(year: Int, month: Int, day: Int) raises -> Int:
    """Return the number of a day in its year.

    Args:
        year: The year of the Gregorian calendar.
        month: The month, 1 to 12.
        day: The day of the month, from 1 to the length of the month.

    Returns:
        The day number, from 1 on 1 January.

    Raises:
        Error: If the month or the day does not exist.
    """
    var lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if is_leap_year(year):
        lengths[1] = 29
    if month < 1 or month > 12:
        raise Error("A month must be from 1 to 12")
    if day < 1 or day > lengths[month - 1]:
        raise Error("A day must be from 1 to the length of its month")
    var total = day
    for at in range(month - 1):
        total += lengths[at]
    return total


def _julian_day(year: Int, day: Int, hours: Float64) -> Float64:
    """Return the Julian day of an instant: of the day of a year, at an hour
    of Coordinated Universal Time."""
    # The Julian day number of noon on 1 January, by the Gregorian rule.
    var y = year + 4799
    var number = (
        1 + (153 * 10 + 2) // 5 + 365 * y + y // 4 - y // 100 + y // 400 - 32045
    )
    return Float64(number) - 0.5 + Float64(day - 1) + hours / 24.0


def _wrap(angle: Float64) -> Float64:
    """Return an angle in degrees folded into 0 up to 360."""
    return angle - 360.0 * floor(angle / 360.0)


def _coordinates(julian_day: Float64) -> Tuple[Float64, Float64]:
    """Return the declination of the sun in radians and the equation of time
    in minutes at an instant."""
    var t = (julian_day - 2451545.0) / 36525.0
    var mean_longitude = _wrap(280.46646 + 36000.76983 * t)
    var anomaly = _wrap(357.52911 + 35999.05029 * t) * pi / 180.0
    var center = (
        (1.914602 - 0.004817 * t) * sin(anomaly)
        + 0.019993 * sin(2.0 * anomaly)
        + 0.000289 * sin(3.0 * anomaly)
    )
    var node = (125.04 - 1934.136 * t) * pi / 180.0
    var longitude = (
        (mean_longitude + center - 0.00569 - 0.00478 * sin(node)) * pi / 180.0
    )
    var obliquity = (
        (23.439291 - 0.0130042 * t + 0.00256 * cos(node)) * pi / 180.0
    )
    var declination = asin(sin(obliquity) * sin(longitude))
    var y = tan(obliquity / 2.0) ** 2
    var eccentricity = 0.016708634 - 0.000042037 * t
    var l0 = mean_longitude * pi / 180.0
    var equation = (
        4.0
        * (
            y * sin(2.0 * l0)
            - 2.0 * eccentricity * sin(anomaly)
            + 4.0 * eccentricity * y * sin(anomaly) * cos(2.0 * l0)
            - 0.5 * y * y * sin(4.0 * l0)
            - 1.25 * eccentricity * eccentricity * sin(2.0 * anomaly)
        )
        * 180.0
        / pi
    )
    return (declination, equation)


def _check_site(latitude: Angle64, longitude: Angle64) raises:
    """Refuse a latitude or a longitude that is not on the Earth."""
    var phi = latitude.to(DEGREE64)
    var lambda_ = longitude.to(DEGREE64)
    if not (phi >= -90.0 and phi <= 90.0):
        raise Error("A latitude must be from -90 to 90 degrees")
    if not (lambda_ >= -180.0 and lambda_ <= 180.0):
        raise Error("A longitude must be from -180 to 180 degrees")


def solar_position(
    latitude: Angle64,
    longitude: Angle64,
    year: Int,
    day: Int,
    hours_utc: Float64,
) raises -> SunPosition:
    """Return where the sun is.

    Args:
        latitude: The latitude of the site, north positive.
        longitude: The longitude of the site, east positive.
        year: The year, which only decides whether it has 366 days.
        day: The number of the day in the year.
        hours_utc: The time of day in hours of Coordinated Universal Time.
            It can lie outside 0 to 24 to reach a neighboring day.

    Returns:
        The altitude and the azimuth, with the declination and the equation
        of time that they follow from.

    Raises:
        Error: If the site is not on the Earth, the day is not in the year
            or the time is not finite.
    """
    _check_site(latitude, longitude)
    var days = 366 if is_leap_year(year) else 365
    if day < 1 or day > days:
        raise Error("A day number must be from 1 to the days of its year")
    if not (hours_utc == hours_utc and abs(hours_utc) < 1.0e6):
        raise Error("A time must be finite")
    var found = _coordinates(_julian_day(year, day, hours_utc))
    var declination = found[0]
    var equation = found[1]
    var phi = latitude.value
    # True solar time in minutes, then the hour angle, zero at solar noon and
    # growing by 15 degrees an hour toward the afternoon.
    var solar_minutes = (
        hours_utc * 60.0 + equation + 4.0 * longitude.to(DEGREE64)
    )
    var hour_angle = (solar_minutes / 4.0 - 180.0) * pi / 180.0
    var sine_altitude = sin(phi) * sin(declination) + cos(phi) * cos(
        declination
    ) * cos(hour_angle)
    var altitude = asin(min(max(sine_altitude, -1.0), 1.0))
    # Meeus measures the azimuth westward from south. Add a half turn to
    # measure it clockwise from north.
    var from_south = atan2(
        sin(hour_angle),
        cos(hour_angle) * sin(phi) - tan(declination) * cos(phi),
    )
    var azimuth = from_south + pi
    azimuth -= 2.0 * pi * floor(azimuth / (2.0 * pi))
    return SunPosition(
        Angle64(altitude),
        Angle64(azimuth),
        Angle64(declination),
        Duration64(equation * 60.0),
    )


def solar_noon(longitude: Angle64, year: Int, day: Int) raises -> Duration64:
    """Return the time of day when the sun is due south.

    Args:
        longitude: The longitude of the site, east positive.
        year: The year, which only decides whether it has 366 days.
        day: The number of the day in the year.

    Returns:
        The time in seconds after midnight Coordinated Universal Time.

    Raises:
        Error: If the longitude is not on the Earth or the day is not in the
            year.
    """
    _check_site(Angle64(0.0), longitude)
    var days = 366 if is_leap_year(year) else 365
    if day < 1 or day > days:
        raise Error("A day number must be from 1 to the days of its year")
    var minutes = 720.0 - 4.0 * longitude.to(DEGREE64)
    # The equation of time changes by about 30 seconds a day, so a
    # refinement at the time that the first pass found is enough.
    for _ in range(2):
        var equation = _coordinates(_julian_day(year, day, minutes / 60.0))[1]
        minutes = 720.0 - 4.0 * longitude.to(DEGREE64) - equation
    return Duration64(minutes * 60.0)


def _half_day(latitude: Float64, declination: Float64) raises -> Float64:
    """Return the hour angle of the horizon, in degrees: half the length of
    the day in the sky, at 4 minutes a degree."""
    var cosine = cos(_SUNRISE_ZENITH) / (
        cos(latitude) * cos(declination)
    ) - tan(latitude) * tan(declination)
    if not (cosine > -1.0 and cosine < 1.0):
        raise Error("The sun does not rise and set on this day at this site")
    return acos(cosine) * 180.0 / pi


def sunrise_and_sunset(
    latitude: Angle64, longitude: Angle64, year: Int, day: Int
) raises -> Tuple[Duration64, Duration64]:
    """Return the times of sunrise and sunset.

    Sunrise is when the upper edge of the sun meets the horizon, after
    the refraction of the air has lifted it.

    Args:
        latitude: The latitude of the site, north positive.
        longitude: The longitude of the site, east positive.
        year: The year, which only decides whether it has 366 days.
        day: The number of the day in the year.

    Returns:
        The two times, in seconds after midnight Coordinated Universal Time.

    Raises:
        Error: If the site is not on the Earth, the day is not in the year,
            or the sun does not rise and set on that day, as in the polar
            summer and winter.
    """
    _check_site(latitude, longitude)
    var days = 366 if is_leap_year(year) else 365
    if day < 1 or day > days:
        raise Error("A day number must be from 1 to the days of its year")
    var phi = latitude.value
    var east = longitude.to(DEGREE64)
    var rise = 720.0 - 4.0 * east
    var set = rise
    # Each pass finds the hour angle of the horizon at the instant that the
    # last pass found, so the declination follows the sun through the day.
    for _ in range(3):
        var at_rise = _coordinates(_julian_day(year, day, rise / 60.0))
        var at_set = _coordinates(_julian_day(year, day, set / 60.0))
        var rise_half = _half_day(phi, at_rise[0])
        var set_half = _half_day(phi, at_set[0])
        rise = 720.0 - 4.0 * (east + rise_half) - at_rise[1]
        set = 720.0 - 4.0 * (east - set_half) - at_set[1]
    return (Duration64(rise * 60.0), Duration64(set * 60.0))


def shadow_length(height: Length64, position: SunPosition) raises -> Length64:
    """Return how far a vertical post of a height throws its shadow on flat
    ground.

    Args:
        height: The height of the post over the ground.
        position: Where the sun is.

    Returns:
        The distance from the foot to the tip of the shadow.

    Raises:
        Error: If the height is negative or not finite, or the sun is not
            over the horizon.
    """
    if not (height.value >= 0.0 and height.value < 1.0e9):
        raise Error("A height must be zero or more and finite")
    if not position.above_horizon():
        raise Error("The sun must be over the horizon to cast a shadow")
    return Length64(height.value / tan(position.altitude.value))


def shadow_tip(
    height: Length64, position: SunPosition
) raises -> Tuple[Length64, Length64]:
    """Return where the tip of a post's shadow falls, east and north of its
    foot.

    The shadow falls away from the sun.

    Args:
        height: The height of the post over the ground.
        position: Where the sun is.

    Returns:
        The east and the north offset of the tip from the foot.

    Raises:
        Error: If the height is negative or not finite, or the sun is not
            over the horizon.
    """
    var length = shadow_length(height, position).value
    var toward = position.toward()
    var flat = sqrt(toward[0] * toward[0] + toward[1] * toward[1])
    return (
        Length64(-length * toward[0] / flat),
        Length64(-length * toward[1] / flat),
    )
