# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The constants and the units of a warp drive analysis, in Float64.

The time coordinate of the grid is x⁰ = c t, so every coordinate is a
length and the metric is dimensionless. Every component of the
stress-energy tensor is then an energy density, in joules per cubic
meter. An energy density has the dimension of a pressure.

The expansion scalar is a rate per length. The shear and vorticity
scalars are its square, a rate per area.

The speed of light is exact by the definition of the meter. The
gravitational constant is the CODATA 2018 value that WarpFactory uses.
"""

from units.quantity import Quantity, Unit
from units.si import Length64, Mass64, Velocity64

comptime EnergyDensity64 = Quantity[-1, 1, -2, 0, 0, DType.float64]
"""Energy per volume: every component of the stress-energy tensor."""
comptime EnergyDensityUnit64 = Unit[-1, 1, -2, 0, 0, DType.float64]
"""A unit of energy density."""
comptime Compliance64 = Quantity[1, -1, 2, 0, 0, DType.float64]
"""Volume per energy: how far a flow line moves for each unit of momentum
density."""
comptime Gravitation64 = Quantity[3, -1, -2, 0, 0, DType.float64]
"""Volume per mass per time squared: the gravitational constant."""

comptime JOULE_PER_CUBIC_METER = EnergyDensityUnit64(1.0, "J/m^3")
"""The SI unit of energy density."""

comptime SPEED_OF_LIGHT = Velocity64(299792458.0)
"""The speed of light. It is exact: the meter is defined by it."""
comptime GRAVITATIONAL_CONSTANT = Gravitation64(6.67430e-11)
"""The gravitational constant: the CODATA 2018 value, as WarpFactory's
G() gives it."""


def fraction_of_light(beta: Float64) -> Velocity64:
    """Return a speed given as a fraction of the speed of light.

    WarpFactory gives a warp speed in factors of c. This builds the same
    speed as a velocity.

    Args:
        beta: The speed divided by c.

    Returns:
        The speed.
    """
    return Velocity64(beta * SPEED_OF_LIGHT.value)


def light_fraction(speed: Velocity64) -> Float64:
    """Return a speed as a fraction of the speed of light.

    Args:
        speed: The speed.

    Returns:
        The speed divided by c.
    """
    return speed.value / SPEED_OF_LIGHT.value


def schwarzschild_radius(mass: Mass64) -> Length64:
    """Return the Schwarzschild radius of a mass, 2 G M / c².

    Args:
        mass: The mass.

    Returns:
        The radius of the horizon of that mass.
    """
    var c = SPEED_OF_LIGHT.value
    return Length64(2.0 * GRAVITATIONAL_CONSTANT.value * mass.value / (c * c))


def einstein_coupling() -> Float64:
    """Return c⁴ / (8 π G), which turns curvature into energy density.

    Returns:
        The factor, in joules per meter. Times an Einstein tensor in
        inverse square meters, it gives joules per cubic meter.
    """
    var c = SPEED_OF_LIGHT.value
    return (c * c * c * c) / (
        8.0 * 3.141592653589793 * GRAVITATIONAL_CONSTANT.value
    )
