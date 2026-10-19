# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The gravity wall at the edge of the moat.

The island is fill held back by a masonry wall that stands in the water.
The wall is a rectangle on a unit length. The fill is a dry soil with a
Rankine active thrust, with the water table behind the wall at a level
that can be higher than the water in front. That is the case after the
moat has been lowered for repair. The water in front pushes back, the
water behind pushes out, and the pressure under the base lifts the wall.

The checks are the classical ones for a gravity wall: the factor of safety
against overturning about the toe, the factor against sliding on the base,
the eccentricity of the resultant on the base and the base pressure. The
base pressure is trapezoidal while the resultant is in the middle third, and
triangular over the contact length beyond it.
"""

from extensions.castle.kinds import (
    BEARING,
    LimitState,
    OVERTURNING,
    SLIDING,
)
from extensions.castle.masonry import Masonry
from extensions.geotech.earth_pressure import rankine_active
from extensions.geotech.quantities import UnitWeight64, WATER_SI
from extensions.geotech.water import net_hydrostatic
from math.finite import require_positive_finite
from std.math import inf
from units.si import (
    Angle64,
    Force64,
    Length64,
    LineLoad64,
    Moment64,
    Pressure64,
)


@fieldwise_init
struct GravityWall(Copyable, Movable):
    """A rectangular masonry wall that retains fill, on a unit length."""

    # The height from the base to the top of the wall and the fill.
    var height: Length64
    # The thickness of the wall, which is the width of its base.
    var thickness: Length64
    var masonry: Masonry
    # The unit weight of the fill above the water table.
    var fill_weight: UnitWeight64
    # The friction angle of the fill.
    var friction_angle: Angle64
    # The friction coefficient between the base and the ground.
    var base_friction: Float64
    # A uniform load on the fill behind the wall.
    var surcharge: Pressure64
    # The bearing pressure that the ground carries at the toe.
    var allowable: Pressure64

    def check(self) raises:
        """Refuse a wall that has a size no wall has.

        Nothing. The call returns when every number is positive and finite.

        Raises:
            Error: If a size, weight, friction or pressure is not positive
                and finite, or the surcharge is negative.
        """
        self.masonry.check()
        require_positive_finite(
            self.height.value, "A wall height must be positive"
        )
        require_positive_finite(
            self.thickness.value, "A wall thickness must be positive"
        )
        require_positive_finite(
            self.fill_weight.value, "A fill weight must be positive"
        )
        require_positive_finite(
            self.friction_angle.value, "A friction angle must be positive"
        )
        require_positive_finite(
            self.base_friction, "A base friction must be positive"
        )
        require_positive_finite(
            self.allowable.value, "An allowable pressure must be positive"
        )
        if not (self.surcharge.value >= 0.0 and self.surcharge.value < 1.0e12):
            raise Error("A surcharge must be zero or more")


@fieldwise_init
struct WallCheck(ImplicitlyCopyable):
    """The result of a wall check for one water case."""

    # The overturning moment over the restoring moment, about the toe.
    var overturning: Float64
    # The sliding resistance over the sliding force.
    var sliding: Float64
    # The distance of the resultant from the middle of the base.
    var eccentricity: Length64
    # The largest base pressure, at the edge that the resultant nears.
    var base_pressure: Pressure64
    # The allowable pressure over the base pressure.
    var bearing: Float64
    # The weight of the wall, after the uplift.
    var vertical: LineLoad64
    # The horizontal force, earth and water together.
    var horizontal: LineLoad64

    def governing(self) -> LimitState:
        """Return the limit state with the smallest safety factor.

        Returns:
            OVERTURNING, SLIDING or BEARING. A tie goes to the first of
            them in that order.
        """
        var state = OVERTURNING
        var least = self.overturning
        if self.sliding < least:
            state = SLIDING
            least = self.sliding
        if self.bearing < least:
            state = BEARING
        return state

    def passes(self, base: Length64) -> Bool:
        """Return True if the wall meets the classical limits.

        The overturning and sliding factors must be at least 1.5. The
        bearing factor must be at least 1. The resultant must be in the
        middle third of the base.

        Args:
            base: The width of the base.

        Returns:
            Whether every limit holds.
        """
        return (
            self.overturning >= 1.5
            and self.sliding >= 1.5
            and self.bearing >= 1.0
            and self.eccentricity <= base.scaled(1.0 / 6.0)
        )


def check_wall(
    wall: GravityWall, back_water: Length64, front_water: Length64
) raises -> WallCheck:
    """Check a gravity wall for one pair of water levels.

    The levels are heights above the base. The fill is dry above the water
    table behind the wall and weighs its buoyant weight below it. The
    pressure of the water on the base falls in a line from the heel to the
    toe. A resultant outside the base gives an infinite base pressure and a
    bearing factor of zero. The wall always outweighs its uplift, because
    masonry is heavier than water.

    Args:
        wall: The wall.
        back_water: The water table behind the wall.
        front_water: The water in front of the wall.

    Returns:
        The factors of safety, the eccentricity and the base pressure.

    Raises:
        Error: If the wall is not valid, or a water level is negative or
            above the top of the wall.
    """
    wall.check()
    var h = wall.height.value
    var b = wall.thickness.value
    if not (back_water.value >= 0.0 and back_water.value <= h):
        raise Error("The water table must be between the base and the top")
    if not (front_water.value >= 0.0 and front_water.value <= h):
        raise Error("The front water must be between the base and the top")
    var ka = rankine_active(wall.friction_angle)
    var gamma = wall.fill_weight.value
    var buoyant = gamma - WATER_SI.value
    var q = wall.surcharge.value
    var hb = back_water.value
    var zw = h - hb
    var f_dry = ka * (q * zw + gamma * zw * zw / 2.0)
    var m_dry = ka * (
        q * (h * zw - zw * zw / 2.0)
        + gamma * (h * zw * zw / 2.0 - zw * zw * zw / 3.0)
    )
    var c0 = q + gamma * zw
    var f_wet = ka * (c0 * hb + buoyant * hb * hb / 2.0)
    var m_wet = ka * (c0 * hb * hb / 2.0 + buoyant * hb * hb * hb / 6.0)
    var water = net_hydrostatic(back_water, front_water, wall.height, WATER_SI)
    var earth_force = f_dry + f_wet
    var earth_moment = m_dry + m_wet
    var weight = wall.masonry.unit_weight().value * b * h
    var uplift = (
        WATER_SI.value * b * (front_water.value + back_water.value) / 2.0
    )
    var uplift_moment = (
        WATER_SI.value
        * b
        * b
        * (front_water.value + 2.0 * back_water.value)
        / 6.0
    )
    var vertical = weight - uplift
    var horizontal = earth_force + water.force.value
    var overturning_moment = earth_moment + water.moment.value + uplift_moment
    var restoring_moment = weight * b / 2.0
    var net_moment = restoring_moment - overturning_moment
    var reach = net_moment / vertical
    var eccentricity = abs(b / 2.0 - reach)
    var edge = b / 2.0 - eccentricity
    var peak = inf[DType.float64]()
    if eccentricity <= b / 6.0:
        peak = vertical / b * (1.0 + 6.0 * eccentricity / b)
    elif edge > 0.0:
        peak = 2.0 * vertical / (3.0 * edge)
    return WallCheck(
        restoring_moment / overturning_moment,
        wall.base_friction * vertical / horizontal,
        Length64(eccentricity),
        Pressure64(peak),
        wall.allowable.value / peak,
        LineLoad64(vertical),
        LineLoad64(horizontal),
    )


def required_thickness(
    wall: GravityWall, back_water: Length64, front_water: Length64
) raises -> Length64:
    """Return the least thickness at which a wall passes every limit.

    The search halves a bracket from 5 percent of the height to four times
    the height. The thickness of `wall` is not read.

    Args:
        wall: The wall, whose thickness is ignored.
        back_water: The water table behind the wall.
        front_water: The water in front of the wall.

    Returns:
        The thickness, to a millionth of the height.

    Raises:
        Error: If the wall is not valid, or no thickness up to four times
            the height passes, as when the ground cannot carry the wall.
    """
    var trial = wall.copy()
    var low = wall.height.value * 0.05
    var high = wall.height.value * 4.0
    trial.thickness = Length64(high)
    if not check_wall(trial, back_water, front_water).passes(trial.thickness):
        raise Error("No thickness up to four times the height holds the wall")
    for _ in range(60):
        var middle = (low + high) / 2.0
        trial.thickness = Length64(middle)
        if check_wall(trial, back_water, front_water).passes(trial.thickness):
            high = middle
        else:
            low = middle
    return Length64(high)
