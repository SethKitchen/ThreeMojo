# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wind on a tower, and what it does to the base of the shaft.

The peak velocity pressure follows EN 1991-1-4 (Eurocode 1, part 1-4),
clauses 4.2 to 4.5. The mean speed is vm(z) = kr ln(z / z0) vb, with the
terrain factor kr = 0.19 (z0 / 0.05)^0.07, and the turbulence intensity is
Iv(z) = 1 / ln(z / z0). The peak pressure is qp = (1 + 7 Iv) 0.5 rho vm^2.
Below zmin = 2 m the pressure at 2 m applies.

The force on a tower is a force coefficient times the peak pressure times
the width, summed over strips of the shaft. The coefficient is an input.
The structural factor cs cd is 1: `cantilever_frequency` gives the first
natural frequency, which says whether that is fair.

The base of the shaft is a hollow section. The checks are the stress at its
edge, the kern, the equilibrium limit state of EN 1990 (EQU, with 0.9 on
the stabilizing weight and 1.5 on the wind) and the strength of the
masonry with a partial factor.
"""

from extensions.castle.kinds import ROUND, SQUARE
from extensions.castle.masonry import GRAVITY, Masonry
from extensions.castle.plan import Tower
from math.finite import require_positive_finite
from std.math import log, pi, pow, sqrt
from units.si import (
    Density64,
    Force64,
    Frequency64,
    Length64,
    Moment64,
    Pressure64,
    Velocity64,
    KILOGRAM_PER_CUBIC_METER,
    METER,
    METER_PER_SECOND,
    NEWTON,
    NEWTON_METER,
    PASCAL,
    SecondMomentOfArea64,
)

# The roughness length of terrain category II, in meters: farmland with few
# hedges, which is flat Flanders.
comptime CATEGORY_II = 0.05
# The roughness length of terrain category III, in meters: villages and
# regular cover such as a forest edge.
comptime CATEGORY_III = 0.3
# The height below which the pressure at zmin applies, in meters.
comptime _MINIMUM_HEIGHT = 2.0
# The strips a shaft is cut into.
comptime _STRIPS = 40


@fieldwise_init
struct Wind(ImplicitlyCopyable):
    """The wind at a site."""

    # The basic wind speed, vb: ten-minute mean at 10 m over category II.
    var basic_speed: Velocity64
    # The roughness length of the terrain, z0.
    var roughness: Length64
    # The density of air.
    var air_density: Density64
    # The force coefficient of the shaft, with end effects.
    var force_coefficient: Float64


def flanders_wind() -> Wind:
    """Return a design wind for the flat country of West Flanders.

    Returns:
        A basic speed of 26 m/s, terrain category II, air at 1.25 kg/m3 and
        a force coefficient of 0.8 for a rough brick cylinder. These are
        typical values. A project reads its own from the national annex.
    """
    return Wind(
        Velocity64(26.0, METER_PER_SECOND),
        Length64(CATEGORY_II, METER),
        Density64(1.25, KILOGRAM_PER_CUBIC_METER),
        0.8,
    )


def peak_velocity_pressure(wind: Wind, height: Length64) raises -> Pressure64:
    """Return the peak velocity pressure at a height.

    EN 1991-1-4, equations 4.7 and 4.8 with the terrain factor of
    equation 4.5.

    Args:
        wind: The wind at the site.
        height: The height above the ground.

    Returns:
        The pressure qp.

    Raises:
        Error: If the wind or the height is not positive and finite.
    """
    require_positive_finite(
        wind.basic_speed.value, "A basic wind speed must be positive"
    )
    require_positive_finite(
        wind.roughness.value, "A roughness length must be positive"
    )
    require_positive_finite(
        wind.air_density.value, "An air density must be positive"
    )
    require_positive_finite(height.value, "A height must be positive")
    var z0 = wind.roughness.value
    var z = max(height.value, _MINIMUM_HEIGHT)
    require_positive_finite(
        log(z / z0), "A height must be above the roughness length"
    )
    var kr = 0.19 * pow(z0 / CATEGORY_II, 0.07)
    var lnz = log(z / z0)
    var mean = wind.basic_speed.scaled(kr * lnz)
    var intensity = 1.0 / lnz
    return (wind.air_density * mean * mean).scaled(
        0.5 * (1.0 + 7.0 * intensity)
    )


@fieldwise_init
struct WindLoad(ImplicitlyCopyable):
    """The wind force on a shaft and its moment about the base."""

    var force: Force64
    var moment: Moment64


def tower_wind_load(wind: Wind, tower: Tower) raises -> WindLoad:
    """Return the wind force on the shaft of a tower and its base moment.

    The shaft is cut into strips. A strip carries the force coefficient
    times the peak pressure at its middle times its width and height. The
    width is the diameter of a round tower and the side of a square one.
    The roof is left out.

    Args:
        wind: The wind at the site.
        tower: The tower.

    Returns:
        The total force and its moment about the base.

    Raises:
        Error: If the force coefficient is not positive and finite, or the
            wind or the tower is not valid.
    """
    require_positive_finite(
        wind.force_coefficient, "A force coefficient must be positive"
    )
    tower.check()
    var width = tower.radius.scaled(2.0)
    var step = tower.height.scaled(1.0 / Float64(_STRIPS))
    var force = Force64(0.0)
    var moment = Moment64(0.0)
    for k in range(_STRIPS):  # pragma: no branch
        var z = step.scaled(Float64(k) + 0.5)
        var q = peak_velocity_pressure(wind, z)
        var strip = (q * width * step).scaled(wind.force_coefficient)
        force = force + strip
        moment = moment + strip * z
    return WindLoad(force, moment)


def ring_inertia(tower: Tower) -> SecondMomentOfArea64:
    """Return the second moment of area of the base section of a shaft.

    Args:
        tower: The tower.

    Returns:
        The value pi/4 (R^4 - r^4) for a round shaft. For a square shaft
        of outer side S and inner side s it is (S^4 - s^4)/12.
    """
    var outer = tower.radius * tower.radius
    var inner = tower.core_radius() * tower.core_radius()
    var difference = outer * outer - inner * inner
    if tower.shape == ROUND:
        return difference.scaled(pi / 4.0)
    return difference.scaled(16.0 / 12.0)


def cantilever_frequency(tower: Tower, masonry: Masonry) raises -> Frequency64:
    """Return the first natural frequency of a shaft as a cantilever.

    A uniform Euler-Bernoulli cantilever has f1 = (1.8751^2 / 2 pi)
    sqrt(E I / (m L^4)), where m is the mass per length. The roof and the
    openings are left out.

    Args:
        tower: The tower.
        masonry: The masonry of the shaft.

    Returns:
        The frequency.

    Raises:
        Error: If the tower or the masonry is not valid.
    """
    tower.check()
    masonry.check()
    var area = tower.shaft_volume() / tower.height
    var mass = masonry.density * area
    var stiffness = masonry.modulus * ring_inertia(tower)
    var length = tower.height * tower.height
    var ratio = stiffness / (mass * length * length)
    return Frequency64(sqrt(ratio.value) * (1.8751 * 1.8751 / (2.0 * pi)))


@fieldwise_init
struct BaseCheck(ImplicitlyCopyable):
    """The result of the base check of a tower."""

    # The weight on the base section.
    var normal: Force64
    # The wind moment about the base.
    var moment: Moment64
    # The edge stress on the windward side: compression is positive.
    var leeward: Pressure64
    # The edge stress on the other side. A negative value is tension.
    var windward: Pressure64
    # The eccentricity of the resultant, moment over weight.
    var eccentricity: Length64
    # The kern radius of the section. The resultant must stay inside.
    var kern: Length64
    # The largest edge stress over the design strength.
    var utilization: Float64
    # The design restoring moment over the design overturning moment.
    var equ_ratio: Float64

    def passes(self) -> Bool:
        """Return True if the base meets every check.

        Returns:
            Whether the resultant is in the kern, the masonry is not
            overstressed and the equilibrium limit state holds.
        """
        return (
            self.eccentricity <= self.kern
            and self.utilization <= 1.0
            and self.equ_ratio >= 1.0
        )


def check_tower_base(
    tower: Tower,
    masonry: Masonry,
    wind: Wind,
    roof_weight: Force64,
    partial: Float64,
) raises -> BaseCheck:
    """Check the base of a tower shaft under its weight and the wind.

    The weight is the shaft plus the roof. The wind acts on the shaft. The
    section is the hollow shaft at the base, as one solid piece with no
    openings.

    Args:
        tower: The tower.
        masonry: The masonry of the shaft.
        wind: The wind at the site.
        roof_weight: The weight of the roof or the parapet on top.
        partial: The partial factor on the masonry, 1 or more.

    Returns:
        The weight, the moment, the edge stresses, the eccentricity, the
        kern, the utilization and the EQU ratio.

    Raises:
        Error: If the tower, masonry, wind or partial factor is not valid,
            or the roof weight is negative.
    """
    if not (roof_weight.value >= 0.0 and roof_weight.value < 1.0e12):
        raise Error("A roof weight must be zero or more")
    var load = tower_wind_load(wind, tower)
    var design = masonry.design_strength(partial)
    var area = tower.shaft_volume() / tower.height
    var weight = masonry.unit_weight() * tower.shaft_volume() + roof_weight
    var section = ring_inertia(tower) / tower.radius
    var direct = weight / area
    var bending = load.moment / section
    var eccentricity = load.moment / weight
    var kern = section / area
    var restoring = (weight * tower.radius).scaled(0.9)
    var overturning = load.moment.scaled(1.5)
    return BaseCheck(
        weight,
        load.moment,
        direct + bending,
        direct - bending,
        eccentricity,
        kern,
        ((direct + bending) / design).value,
        (restoring / overturning).value,
    )
