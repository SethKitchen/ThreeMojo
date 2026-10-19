# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sun over a castle, and the shadows its towers throw.

The position of the sun comes from `extensions.energy.solar`, the equations
of Duffie and Beckman. The castle's latitude and longitude set the site.
The day length follows from the sunrise hour angle: cos(w) = -tan(phi)
tan(delta). The shadow of a point at a height h is h / tan(a) long for a sun
at altitude a, and it points away from the sun.
"""

from extensions.castle.plan import CastlePlan
from extensions.energy.solar import (
    SunPosition,
    declination,
    sun_position,
)
from generators.utils import Vec3d
from math.finite import require_positive_finite
from std.math import acos, pi, tan
from units.si import (
    Angle64,
    Duration64,
    HOUR,
    Length64,
)


def castle_sun(
    plan: CastlePlan, day: Int, clock: Duration64, time_zone: Duration64
) raises -> SunPosition:
    """Return the position of the sun over a castle.

    Args:
        plan: The castle, which gives the latitude and the longitude.
        day: The day of the year, 1 to 366.
        clock: The local standard time, from midnight.
        time_zone: The offset of standard time from universal time.

    Returns:
        The position of the sun.

    Raises:
        Error: If the day is out of range.
    """
    return sun_position(plan.latitude, plan.longitude, time_zone, day, clock)


def scene_direction(sun: SunPosition) -> Vec3d:
    """Return the unit vector toward the sun in scene coordinates.

    The scene has x to the east, y up and z to the south.

    Args:
        sun: The position of the sun.

    Returns:
        The vector as (east, up, south).
    """
    var d = sun.direction()
    return Vec3d(d.x, d.z, -d.y)


def shadow_length(height: Length64, sun: SunPosition) raises -> Length64:
    """Return the length of the shadow of a point on level ground.

    Args:
        height: The height of the point above the ground.
        sun: The position of the sun.

    Returns:
        The height over the tangent of the sun's altitude.

    Raises:
        Error: If the sun is not above the horizon, or the height is not
            positive and finite.
    """
    require_positive_finite(height.value, "A height must be positive")
    if not sun.is_up():
        raise Error("The sun is below the horizon")
    return height.scaled(1.0 / tan(sun.altitude().value))


def day_length(latitude: Angle64, day: Int) raises -> Duration64:
    """Return the time between sunrise and sunset.

    Args:
        latitude: The latitude, north positive.
        day: The day of the year, 1 to 366.

    Returns:
        The length of the day. It is zero in polar night and 24 hours in
        polar day.

    Raises:
        Error: If the day is out of range.
    """
    var cosine = -tan(latitude.value) * tan(declination(day).value)
    if cosine >= 1.0:
        return Duration64(0.0, HOUR)
    if cosine <= -1.0:
        return Duration64(24.0, HOUR)
    var hours = 2.0 * acos(cosine) * 12.0 / pi
    return Duration64(hours, HOUR)
