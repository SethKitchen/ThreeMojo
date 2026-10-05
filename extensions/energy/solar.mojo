# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The position of the sun and the irradiance on a tilted surface.

The equations are those of Duffie and Beckman, "Solar Engineering of
Thermal Processes", 4th edition, 2013, chapters 1 and 2:

- the day angle B = 360 (n - 1) / 365 degrees, eq. 1.4.2;
- the equation of time of Spencer (1971), eq. 1.5.3;
- the declination of Spencer (1971), eq. 1.6.1b, and of Cooper (1969),
  eq. 1.6.1a;
- the zenith angle, eq. 1.6.5, and the solar azimuth, eq. 1.6.6;
- the angle of incidence on a surface, eq. 1.6.3;
- the isotropic sky of Liu and Jordan (1963), eq. 2.15.1.

Angles follow Duffie and Beckman. A surface azimuth and the solar azimuth
are measured from south, west positive. The slope is the angle between
the surface and the horizontal: 0 for a roof, 90 degrees for a wall and
180 degrees for a surface that faces down. A longitude is east positive.
A time zone is the offset of local standard time from universal time,
east positive.
"""

from std.math import acos, atan2, cos, isfinite, pi, sin
from generators.utils import Vec3d
from units.si import (
    Angle64,
    DEGREE,
    DEGREE64,
    Duration64,
    HOUR,
    HeatFlux64,
    MINUTE,
    RADIAN,
    WATT_PER_SQUARE_METER,
)


def day_of_year(month: Int, day: Int) raises -> Int:
    """Return the day of the year of a date in a year without February 29.

    February 29 counts as day 60, the same day as March 1.

    Args:
        month: The month, 1 to 12.
        day: The day of the month, from 1.

    Returns:
        The day of the year, 1 to 365.

    Raises:
        Error: If the month or the day is not in the calendar.
    """
    if month < 1 or month > 12:
        raise Error("A month must be 1 to 12")
    var days: List[Int] = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if day < 1 or day > days[month - 1]:
        raise Error("A day is not in its month")
    var start: List[Int] = [
        0,
        31,
        59,
        90,
        120,
        151,
        181,
        212,
        243,
        273,
        304,
        334,
    ]
    return start[month - 1] + day


def _check_day(day: Int) raises:
    if day < 1 or day > 366:
        raise Error("A day of the year must be 1 to 366")


def _day_angle(day: Int) -> Float64:
    return 2 * pi * Float64(day - 1) / 365.0


def equation_of_time(day: Int) raises -> Duration64:
    """Return the equation of time of Spencer: solar time minus mean time.

    Duffie and Beckman, eq. 1.5.3.

    Args:
        day: The day of the year, 1 to 366.

    Returns:
        The equation of time, from about -14 to +16 minutes.

    Raises:
        Error: If the day is out of range.
    """
    _check_day(day)
    var b = _day_angle(day)
    var minutes = 229.2 * (
        0.000075
        + 0.001868 * cos(b)
        - 0.032077 * sin(b)
        - 0.014615 * cos(2 * b)
        - 0.04089 * sin(2 * b)
    )
    return Duration64(minutes, MINUTE)


def declination(day: Int) raises -> Angle64:
    """Return the solar declination by the series of Spencer.

    Duffie and Beckman, eq. 1.6.1b. It is within 0.035 degrees of the
    almanac.

    Args:
        day: The day of the year, 1 to 366.

    Returns:
        The declination, north positive.

    Raises:
        Error: If the day is out of range.
    """
    _check_day(day)
    var b = _day_angle(day)
    var radians = (
        0.006918
        - 0.399912 * cos(b)
        + 0.070257 * sin(b)
        - 0.006758 * cos(2 * b)
        + 0.000907 * sin(2 * b)
        - 0.002697 * cos(3 * b)
        + 0.00148 * sin(3 * b)
    )
    return Angle64(radians, RADIAN)


def declination_cooper(day: Int) raises -> Angle64:
    """Return the solar declination by the sine of Cooper.

    Duffie and Beckman, eq. 1.6.1a: 23.45 sin(360 (284 + n) / 365)
    degrees. The worked examples of Duffie and Beckman use it.

    Args:
        day: The day of the year, 1 to 366.

    Returns:
        The declination, north positive.

    Raises:
        Error: If the day is out of range.
    """
    _check_day(day)
    var degrees = 23.45 * sin(2 * pi * Float64(284 + day) / 365.0)
    return Angle64(degrees, DEGREE64)


def solar_time(
    clock: Duration64, day: Int, longitude: Angle64, time_zone: Duration64
) raises -> Duration64:
    """Return the apparent solar time of a local standard time.

    Duffie and Beckman, eq. 1.5.2: solar time = standard time
    + 4 minutes per degree (longitude - standard meridian) + E. The
    standard meridian is 15 degrees per hour of the time zone.

    Args:
        clock: The local standard time, from midnight.
        day: The day of the year, 1 to 366.
        longitude: The longitude, east positive.
        time_zone: The offset of standard time from universal time.

    Returns:
        The solar time, from the same midnight.

    Raises:
        Error: If the day is out of range.
    """
    var meridian = 15.0 * time_zone.to(HOUR)
    var shift = Duration64(4.0 * (longitude.to(DEGREE64) - meridian), MINUTE)
    return clock + shift + equation_of_time(day)


def hour_angle(solar: Duration64) -> Angle64:
    """Return the hour angle of a solar time.

    Fifteen degrees per hour from solar noon, morning negative.

    Args:
        solar: The solar time, from midnight.

    Returns:
        The hour angle.
    """
    return Angle64(15.0 * (solar.to(HOUR) - 12.0), DEGREE)


@fieldwise_init
struct SunPosition(ImplicitlyCopyable):
    """Where the sun is in the sky."""

    # From the vertical to the sun.
    var zenith: Angle64
    # From south to the sun's direction on the ground, west positive.
    var azimuth: Angle64

    def altitude(self) -> Angle64:
        """Return the angle of the sun above the horizon.

        Returns:
            90 degrees minus the zenith angle.
        """
        return Angle64(pi / 2) - self.zenith

    def is_up(self) -> Bool:
        """Return True if the sun is above the horizon.

        Returns:
            Whether the zenith angle is below 90 degrees.
        """
        return self.zenith.value < pi / 2

    def direction(self) -> Vec3d:
        """Return the unit vector toward the sun.

        Returns:
            The vector as (east, north, up).
        """
        var s = sin(self.zenith.value)
        return Vec3d(
            -s * sin(self.azimuth.value),
            -s * cos(self.azimuth.value),
            cos(self.zenith.value),
        )


def sun_angles(
    latitude: Angle64, declination: Angle64, hour_angle: Angle64
) -> SunPosition:
    """Return the sun's zenith and azimuth angles.

    Duffie and Beckman, eq. 1.6.5 for the zenith and eq. 1.6.6 for the
    azimuth. The azimuth is zero when the sun is at the zenith or the
    site is at a pole, where it has no meaning.

    Args:
        latitude: The latitude, north positive.
        declination: The solar declination.
        hour_angle: The hour angle, morning negative.

    Returns:
        The position of the sun.
    """
    var phi = latitude.value
    var delta = declination.value
    var omega = hour_angle.value
    var cos_z = cos(phi) * cos(delta) * cos(omega) + sin(phi) * sin(delta)
    cos_z = max(-1.0, min(1.0, cos_z))
    var zenith = acos(cos_z)
    var below = sin(zenith) * cos(phi)
    var azimuth = 0.0
    if below > 1e-9:
        var c = (cos_z * sin(phi) - sin(delta)) / below
        azimuth = acos(max(-1.0, min(1.0, c)))
        if omega < 0:
            azimuth = -azimuth
    return SunPosition(Angle64(zenith), Angle64(azimuth))


def sun_position(
    latitude: Angle64,
    longitude: Angle64,
    time_zone: Duration64,
    day: Int,
    clock: Duration64,
) raises -> SunPosition:
    """Return the position of the sun at a local standard time.

    The declination is that of Spencer and the solar time includes the
    equation of time.

    Args:
        latitude: The latitude, north positive.
        longitude: The longitude, east positive.
        time_zone: The offset of standard time from universal time.
        day: The day of the year, 1 to 366.
        clock: The local standard time, from midnight.

    Returns:
        The position of the sun.

    Raises:
        Error: If the day is out of range.
    """
    var solar = solar_time(clock, day, longitude, time_zone)
    return sun_angles(latitude, declination(day), hour_angle(solar))


@fieldwise_init
struct SurfaceOrientation(ImplicitlyCopyable):
    """The slope and the azimuth of a plane surface."""

    # From the horizontal: 0 faces up, 90 degrees is a wall.
    var slope: Angle64
    # The direction its normal faces, from south, west positive.
    var azimuth: Angle64


def orientation(normal: Vec3d, north: Angle64) raises -> SurfaceOrientation:
    """Return the orientation of a surface from its normal in a model.

    The model's x axis points east and its y axis north when `north` is
    zero. `north` is the angle from the model's +y axis to true north,
    counterclockwise seen from above.

    Args:
        normal: The direction the surface faces, in model coordinates.
        north: The angle from the model's +y axis to true north.

    Returns:
        The slope and the azimuth.

    Raises:
        Error: If the normal is zero or not finite.
    """
    var length = normal.length()
    if not (length > 0 and isfinite(length)):
        raise Error("A surface normal must be nonzero and finite")
    var n = normal * (1.0 / length)
    var a = north.value
    var east = n.x * cos(a) + n.y * sin(a)
    var northward = -n.x * sin(a) + n.y * cos(a)
    var slope = acos(max(-1.0, min(1.0, n.z)))
    var azimuth = atan2(0.0 - east, 0.0 - northward)
    return SurfaceOrientation(Angle64(slope), Angle64(azimuth))


def incidence_cosine(surface: SurfaceOrientation, sun: SunPosition) -> Float64:
    """Return the cosine of the angle between the beam and a surface normal.

    Duffie and Beckman, eq. 1.6.3: cos(theta) = cos(theta_z) cos(beta)
    + sin(theta_z) sin(beta) cos(gamma_s - gamma). A negative value means
    the sun is behind the surface.

    Args:
        surface: The surface.
        sun: The position of the sun.

    Returns:
        The cosine of the angle of incidence.
    """
    var z = sun.zenith.value
    var beta = surface.slope.value
    return cos(z) * cos(beta) + sin(z) * sin(beta) * cos(
        sun.azimuth.value - surface.azimuth.value
    )


def tilted_irradiance(
    surface: SurfaceOrientation,
    sun: SunPosition,
    direct_normal: HeatFlux64,
    diffuse_horizontal: HeatFlux64,
    global_horizontal: HeatFlux64,
    ground_reflectance: Float64,
) raises -> HeatFlux64:
    """Return the solar irradiance on a surface by the isotropic sky.

    Duffie and Beckman, eq. 2.15.1: I_T = I_bn max(cos theta, 0)
    + I_d (1 + cos beta) / 2 + I rho_g (1 - cos beta) / 2. The beam part
    is zero when the sun is below the horizon.

    Args:
        surface: The surface.
        sun: The position of the sun.
        direct_normal: The beam irradiance on a plane normal to the sun.
        diffuse_horizontal: The sky diffuse irradiance on the horizontal.
        global_horizontal: The total irradiance on the horizontal.
        ground_reflectance: The albedo of the ground, zero to one.

    Returns:
        The irradiance on the surface.

    Raises:
        Error: If an irradiance is negative or not finite, or the
            reflectance is outside zero to one.
    """
    var values = [
        direct_normal.value,
        diffuse_horizontal.value,
        global_horizontal.value,
    ]
    for i in range(len(values)):  # pragma: no branch
        if not (values[i] >= 0 and isfinite(values[i])):
            raise Error("An irradiance must be zero or more and finite")
    if not (ground_reflectance >= 0 and ground_reflectance <= 1):
        raise Error("A ground reflectance must be zero to one")
    var beam = 0.0
    if sun.is_up():
        beam = direct_normal.value * max(0.0, incidence_cosine(surface, sun))
    var c = cos(surface.slope.value)
    var sky = diffuse_horizontal.value * (1 + c) / 2
    var ground = global_horizontal.value * ground_reflectance * (1 - c) / 2
    return HeatFlux64(beam + sky + ground, WATT_PER_SQUARE_METER)
