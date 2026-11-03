# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The quay wall of the island as a gravity retaining wall: the earth behind
it, the water of the moat in front of it, and what the two do to its base.

A brick wall of a thickness b and a height H holds back the earth of the
island. Per meter of wall it carries:

- its weight, `gamma_m b H`, at the middle of the base;
- the active thrust of the earth, Rankine's `Ka = tan^2(45 - phi / 2)` on the
  effective stress, with the soil below the water table weighing its
  buoyant weight;
- the water behind the wall, if the ground is wet, and the water in front of
  it, in the moat, whose net thrust is `net_hydrostatic` of the geotechnical
  extension;
- the uplift of the water on the base, which falls from the head at the heel
  to the head at the toe.

The checks are the classical ones for a gravity wall. The moment of the weight
about the toe must beat the moment of the thrust and the uplift by a factor.
The friction on the base must hold the net thrust by a factor. The resultant
of the forces must fall in the middle third of the base, so that no tension
opens a joint at the heel. A factor of 1.5 is the customary value for both.
The least thickness is the smallest at which all three hold.

Every figure of the soil and of the water table is an estimate: no survey of
the island or of the wall exists.
"""

from std.math import isfinite, tan
from extensions.castle.masonry import Masonry, historic_brick
from extensions.castle.plan import CastlePlan
from extensions.geotech.earth_pressure import rankine_active
from extensions.geotech.quantities import (
    KILONEWTON_PER_CUBIC_METER,
    MomentPerLength64,
    UnitWeight64,
    WATER_SI,
)
from extensions.geotech.water import net_hydrostatic
from units.si import Angle64, DEGREE64, Length64, LineLoad64, Pressure64

# A factor of safety or a pressure that is not limited, such as the factor
# against overturning of a wall that nothing tries to overturn.
comptime _LARGE = 1.0e9


@fieldwise_init
struct FillSoil(ImplicitlyCopyable):
    """The earth of the island that the wall holds back."""

    # The unit weight above the water table and below it.
    var unit_weight: UnitWeight64
    var saturated_unit_weight: UnitWeight64
    # The friction angle of the soil, as an effective stress.
    var friction: Angle64
    # The friction angle between the masonry and the ground under it.
    var base_friction: Angle64

    def check(self) raises:
        """Refuse a soil that cannot be.

        Raises:
            Error: If a unit weight is not positive and finite, the saturated
                unit weight is not above that of water, or an angle is not
                from 0 to 90 degrees.
        """
        if not (
            isfinite(self.unit_weight.value)
            and self.unit_weight.value > 0.0
            and isfinite(self.saturated_unit_weight.value)
            and self.saturated_unit_weight.value > WATER_SI.value
        ):
            raise Error(
                "A soil needs a positive unit weight, and a saturated unit"
                " weight over that of water"
            )
        var friction = self.friction.to(DEGREE64)
        var base = self.base_friction.to(DEGREE64)
        if not (
            friction >= 0.0 and friction < 90.0 and base >= 0.0 and base < 90.0
        ):
            raise Error("A friction angle must be from 0 up to 90 degrees")


def island_fill() -> FillSoil:
    """Return the soil assumed for the island: a sandy loam fill.

    The unit weight is 18 kN/m^3 above the water and 20 kN/m^3 below. The
    friction angle is 28 degrees, and under the base it is two thirds of that.
    These are typical values for the sandy loams of West Flanders. No test
    backs them.

    Returns:
        The soil.
    """
    return FillSoil(
        UnitWeight64(18.0, KILONEWTON_PER_CUBIC_METER),
        UnitWeight64(20.0, KILONEWTON_PER_CUBIC_METER),
        Angle64(28.0, DEGREE64),
        Angle64(28.0 * 2.0 / 3.0, DEGREE64),
    )


@fieldwise_init
struct GravityWall(Copyable, Movable):
    """A wall of masonry of one thickness, on a flat base."""

    # The height from the foot to the top.
    var height: Length64
    # The thickness, which is also the width of the base.
    var thickness: Length64
    # The height of the ground behind the wall over its foot.
    var retained: Length64
    var masonry: Masonry
    var soil: FillSoil

    def check(self) raises:
        """Refuse a wall that cannot be.

        Raises:
            Error: If a size is not positive and finite, the earth stands
                higher than the wall, or the soil or the masonry is not
                valid.
        """
        if not (
            isfinite(self.height.value)
            and self.height.value > 0.0
            and isfinite(self.thickness.value)
            and self.thickness.value > 0.0
            and isfinite(self.retained.value)
            and self.retained.value >= 0.0
        ):
            raise Error(
                "A wall needs a positive finite height and thickness, and a"
                " retained height of zero or more"
            )
        if self.retained.value > self.height.value:
            raise Error("The earth cannot stand higher than the wall")
        self.soil.check()
        self.masonry.check()


@fieldwise_init
struct WaterLevels(ImplicitlyCopyable):
    """The water on the two sides of the wall, as heights over its foot."""

    # The water table in the ground behind the wall.
    var behind: Length64
    # The water of the moat in front of it.
    var front: Length64


@fieldwise_init
struct WallStability(Copyable, Movable):
    """What the earth and the water do to a wall."""

    # The weight of the wall, the thrust of the earth, the net thrust of the
    # water, and the uplift on the base, each per meter of wall.
    var weight: LineLoad64
    var earth_thrust: LineLoad64
    var water_thrust: LineLoad64
    var uplift: LineLoad64
    # The moment about the toe that overturns the wall, and the moment of the
    # weight that resists it.
    var overturning_moment: MomentPerLength64
    var resisting_moment: MomentPerLength64
    # The factors of safety against overturning and against sliding.
    var overturning_factor: Float64
    var sliding_factor: Float64
    # The distance of the resultant from the toe, and whether it lies in the
    # middle third of the base.
    var resultant_position: Length64
    var middle_third: Bool
    # The pressure under the base at the toe and at the heel.
    var toe_pressure: Pressure64
    var heel_pressure: Pressure64

    def acceptable(
        self, overturning: Float64 = 1.5, sliding: Float64 = 1.5
    ) -> Bool:
        """Return True if the wall passes its three checks.

        Args:
            overturning: The least factor against overturning.
            sliding: The least factor against sliding.

        Returns:
            Whether both factors are enough and the resultant is in the
            middle third.
        """
        return (
            self.overturning_factor >= overturning
            and self.sliding_factor >= sliding
            and self.middle_third
        )


def wall_stability(
    wall: GravityWall, levels: WaterLevels
) raises -> WallStability:
    """Return the stability of a gravity wall.

    Args:
        wall: The wall.
        levels: The water behind it and in front of it.

    Returns:
        The loads, the factors of safety and the pressures under the base.

    Raises:
        Error: If the wall is not valid, or a level is negative or not
            finite.
    """
    wall.check()
    if not (
        isfinite(levels.behind.value)
        and levels.behind.value >= 0.0
        and isfinite(levels.front.value)
        and levels.front.value >= 0.0
    ):
        raise Error("A water level must be zero or more and finite")
    var gamma_w = WATER_SI.value
    var b = wall.thickness.value
    var height = wall.height.value
    var retained = wall.retained.value
    var ka = rankine_active(wall.soil.friction)
    var gamma = wall.soil.unit_weight.value
    var buoyant = wall.soil.saturated_unit_weight.value - gamma_w
    # The effective earth pressure: dry soil over the water table, buoyant
    # soil below it.
    var table = min(levels.behind.value, retained)
    var dry = retained - table
    var top_force = 0.5 * ka * gamma * dry * dry
    var top_arm = table + dry / 3.0
    var surcharge = ka * gamma * dry
    var rectangle = surcharge * table
    var triangle = 0.5 * ka * buoyant * table * table
    var earth = top_force + rectangle + triangle
    var earth_moment = (
        top_force * top_arm + rectangle * table / 2.0 + triangle * table / 3.0
    )
    # The water: the net of the two levels. The soil is below the table in the
    # buoyant weight, so the water behind the wall pushes on it separately.
    var water = net_hydrostatic(
        levels.behind, levels.front, wall.height, WATER_SI
    )
    var weight = wall.masonry.unit_weight().value * b * height
    # The pore pressure on the base falls from the heel to the toe.
    var heel = gamma_w * levels.behind.value
    var toe = gamma_w * levels.front.value
    var uplift = 0.5 * (heel + toe) * b
    var uplift_arm = 0.0
    if heel + toe > 0.0:
        uplift_arm = b * (toe + 2.0 * heel) / (3.0 * (toe + heel))
    var overturning = earth_moment + water.moment.value + uplift * uplift_arm
    var resisting = weight * b / 2.0
    var overturning_factor = _LARGE
    if overturning > 0.0:
        overturning_factor = resisting / overturning
    var thrust = earth + water.force.value
    var vertical = weight - uplift
    var sliding_factor = _LARGE
    if thrust > 0.0:
        sliding_factor = (
            max(vertical, 0.0) * tan(wall.soil.base_friction.value) / thrust
        )
    var position = 0.0
    if vertical > 0.0:
        position = (
            resisting
            - (earth_moment + water.moment.value + uplift * uplift_arm)
        ) / vertical
    var toe_pressure = _LARGE
    var heel_pressure = 0.0
    if position >= b / 3.0:
        var eccentricity = b / 2.0 - position
        toe_pressure = vertical / b * (1.0 + 6.0 * eccentricity / b)
        heel_pressure = vertical / b * (1.0 - 6.0 * eccentricity / b)
    elif position > 0.0:
        toe_pressure = 2.0 * vertical / (3.0 * position)
    return WallStability(
        LineLoad64(weight),
        LineLoad64(earth),
        LineLoad64(water.force.value),
        LineLoad64(uplift),
        MomentPerLength64(overturning),
        MomentPerLength64(resisting),
        overturning_factor,
        sliding_factor,
        Length64(position),
        position >= b / 3.0 and position <= 2.0 * b / 3.0,
        Pressure64(toe_pressure),
        Pressure64(heel_pressure),
    )


def least_thickness(
    wall: GravityWall,
    levels: WaterLevels,
    overturning: Float64 = 1.5,
    sliding: Float64 = 1.5,
) raises -> Length64:
    """Return the least thickness at which a wall stands.

    The thickness is found by bisection: a thicker wall is heavier, so if a
    wall passes, a thicker one does.

    Args:
        wall: The wall. Its own thickness is not used.
        levels: The water behind it and in front of it.
        overturning: The least factor of safety against overturning.
        sliding: The least factor of safety against sliding.

    Returns:
        The thickness.

    Raises:
        Error: If the wall is not valid, a factor is not positive, or no
            thickness up to 30 m is enough.
    """
    if not (overturning > 0.0 and sliding > 0.0):
        raise Error("A factor of safety must be positive")
    var trial = wall.copy()
    var low = 0.01
    var high = 30.0
    trial.thickness = Length64(high)
    if not wall_stability(trial, levels).acceptable(overturning, sliding):
        raise Error("No thickness up to 30 m holds this wall")
    for _ in range(80):
        var middle = (low + high) / 2.0
        trial.thickness = Length64(middle)
        if wall_stability(trial, levels).acceptable(overturning, sliding):
            high = middle
        else:
            low = middle
    return Length64(high)


def quay_wall(plan: CastlePlan) raises -> GravityWall:
    """Return the quay wall of a plan as a gravity wall.

    The wall runs from the foot to the top of the plan, and holds back the earth
    up to the ground of the island. Its thickness is that of the plan, an
    estimate.

    Args:
        plan: The plan.

    Returns:
        The wall, in the brick and the soil assumed for the castle.

    Raises:
        Error: If the plan is not valid.
    """
    var wall = GravityWall(
        Length64(plan.quay.height().value),
        Length64(plan.quay.thickness.value),
        Length64(plan.island_level.value - plan.quay.foot.value),
        historic_brick(),
        island_fill(),
    )
    wall.check()
    return wall^


def moat_full(plan: CastlePlan) -> WaterLevels:
    """Return the water levels with the moat at its level and the ground behind
    the wall as wet as the moat.

    Args:
        plan: The plan.

    Returns:
        The levels, as heights over the foot of the wall.
    """
    var level = plan.moat.water_level.value - plan.quay.foot.value
    return WaterLevels(Length64(level), Length64(level))


def moat_drawn_down(plan: CastlePlan) -> WaterLevels:
    """Return the water levels with the moat emptied and the ground behind the
    wall still as wet as it was.

    This is the worst case for a retaining wall: the water that held the wall
    in is gone, and the water in the ground has not drained.

    Args:
        plan: The plan.

    Returns:
        The levels, as heights over the foot of the wall.
    """
    var level = plan.moat.water_level.value - plan.quay.foot.value
    return WaterLevels(Length64(level), Length64(0.0))
