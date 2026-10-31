# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wind pressure on a building by ASCE/SEI 7-16, chapters 26 and 27.

- `exposure_coefficient`: Kz of Table 26.10-1 by its note's formula,
  with z taken at least 15 ft.
- `elevation_factor`: Ke of Table 26.9-1 by its note's formula.
- `velocity_pressure`: qz = 0.00256 Kz Kzt Kd Ke V^2 psf (26.10-1).
- `leeward_wall_coefficient`: Cp of the leeward wall of Figure 27.3-1,
  by L / B.
- `wall_net_pressure`: the net horizontal pressure of the main wind
  force resisting system on a rigid low building, windward plus
  leeward, q G (0.8 - Cp,leeward). The internal pressures cancel.

The speed is the basic wind speed V, a strength-level value. ASD uses
0.6 W.
"""

from std.math import exp, log
from extensions.design.kinds import EXPOSURE_B, EXPOSURE_C, WindExposure
from extensions.design.quantities import MILE_PER_HOUR
from extensions.design.steel import require_positive
from extensions.geotech.quantities import PSF
from units.si import FOOT64, Length64, Pressure64, Velocity64

# The gust-effect factor of a rigid building, 26.11.1.
comptime RIGID_GUST = 0.85
# Kd of a building's main wind force resisting system, Table 26.6-1.
comptime BUILDING_DIRECTIONALITY = 0.85
# Cp of a windward wall, Figure 27.3-1.
comptime WINDWARD_WALL = 0.8


def _terrain(exposure: WindExposure) raises -> Tuple[Float64, Float64]:
    """Return alpha and z_g in feet of Table 26.11-1."""
    if not exposure.is_valid():
        raise Error("A wind exposure must be B, C or D")
    if exposure == EXPOSURE_B:
        return (7.0, 1200.0)
    if exposure == EXPOSURE_C:
        return (9.5, 900.0)
    return (11.5, 700.0)


def exposure_coefficient(
    height: Length64, exposure: WindExposure
) raises -> Float64:
    """Return Kz, the velocity pressure exposure coefficient.

    Args:
        height: z, the height above ground. Heights under 15 ft use 15 ft.
        exposure: B, C or D.

    Returns:
        2.01 (z / z_g)^(2 / alpha).

    Raises:
        Error: If the exposure is not valid, or the height is negative or
            above z_g.
    """
    var terrain = _terrain(exposure)
    var z = height.to(FOOT64)
    if not (z >= 0 and z <= terrain[1]):
        raise Error("A height must be from zero to the gradient height")
    z = max(z, 15.0)
    return 2.01 * exp(2 / terrain[0] * log(z / terrain[1]))


def elevation_factor(ground_elevation: Length64) raises -> Float64:
    """Return Ke, the ground elevation factor.

    Args:
        ground_elevation: The ground's height above sea level.

    Returns:
        e^(-0.0000362 z_e) with z_e in feet.

    Raises:
        Error: If the elevation is not finite.
    """
    var ze = ground_elevation.to(FOOT64)
    if not (ze > -Float64.MAX and ze < Float64.MAX):
        raise Error("A ground elevation must be finite")
    return exp(-0.0000362 * ze)


def velocity_pressure(
    speed: Velocity64,
    exposure_factor: Float64,
    topographic: Float64,
    directionality: Float64,
    elevation: Float64,
) raises -> Pressure64:
    """Return qz, the velocity pressure, equation 26.10-1.

    Args:
        speed: V, the basic wind speed.
        exposure_factor: Kz.
        topographic: Kzt, 1.0 on flat ground.
        directionality: Kd.
        elevation: Ke.

    Returns:
        0.00256 Kz Kzt Kd Ke V^2 psf, V in mph.

    Raises:
        Error: If a value is not positive.
    """
    var v = speed.to(MILE_PER_HOUR)
    require_positive(v, "A wind speed must be positive")
    require_positive(exposure_factor, "Kz must be positive")
    require_positive(topographic, "Kzt must be positive")
    require_positive(directionality, "Kd must be positive")
    require_positive(elevation, "Ke must be positive")
    return Pressure64(
        0.00256
        * exposure_factor
        * topographic
        * directionality
        * elevation
        * v
        * v,
        PSF,
    )


def leeward_wall_coefficient(depth_over_width: Float64) raises -> Float64:
    """Return Cp of a leeward wall, Figure 27.3-1.

    Args:
        depth_over_width: L / B, the building's depth along the wind over
            its width across it.

    Returns:
        -0.5 up to 1, -0.3 at 2, -0.2 from 4, linear between.

    Raises:
        Error: If L / B is not positive.
    """
    require_positive(depth_over_width, "L / B must be positive")
    var r = depth_over_width
    if r <= 1:
        return -0.5
    if r <= 2:
        return -0.5 + 0.2 * (r - 1)
    if r <= 4:
        return -0.3 + 0.1 * (r - 2) / 2
    return -0.2


def wall_net_pressure(
    velocity: Pressure64, depth_over_width: Float64
) raises -> Pressure64:
    """Return the net horizontal wall pressure of a rigid building.

    The windward wall uses the velocity pressure given, which is
    conservative when it is q_h.

    Args:
        velocity: The velocity pressure, q_h or q_z.
        depth_over_width: L / B.

    Returns:
        q G (0.8 - Cp,leeward), with G = 0.85.

    Raises:
        Error: If the velocity pressure or L / B is not positive.
    """
    require_positive(velocity.value, "A velocity pressure must be positive")
    var cp = leeward_wall_coefficient(depth_over_width)
    return velocity.scaled(RIGID_GUST * (WINDWARD_WALL - cp))
