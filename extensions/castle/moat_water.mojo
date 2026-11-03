# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The water of the moat: a balance of what comes in and what goes out, with a
weir that holds the level.

The moat is a tank of a known surface area. Water comes in from a brook, from
the rain that falls on the water and on the ground that drains to it. Water
goes out over a weir, by seepage into the ground, and by evaporation. The level
changes by the net volume over the area:

    A dh/dt = Q_in + C R A_c - Q_weir(h) - Q_seep(h) + (P - E) A

with P the rain and E the evaporation as depths of water over the day, C the
runoff coefficient of the catchment of area A_c, and R the rain over it.

The weir is a thin-plate weir of the full width of its channel. Its discharge
is the Kindsvater-Carter formula of ISO 1438 and the Water Measurement Manual of
the US Bureau of Reclamation (chapter 7):

    Q = (2/3) Ce sqrt(2 g) L he^(3/2),  Ce = 0.602 + 0.075 h / p,  he = h + kh,

with h the head over the crest, p the height of the crest over the bed, L the
width, and kh of 0.003 ft, which is 0.9 mm, for the effect of viscosity and of
surface tension. The formula holds for a head of 0.061 m or more, a crest
height of 0.10 m or more, and a head under 2.4 times the crest height. The
correction of the width is under 1 mm for a weir of the full width of its
channel, and is left out.

The time step is an explicit Runge-Kutta step of the fourth order, taken in
small steps. A moat of this area answers a change of the weir head in hours, so
steps of a minute are far inside the stable range.

The level of the moat at Wijnendale, 34.31 m above TAW, is that of the airborne
laser scan, which is one date of an unknown weather. The module takes it as the
level of dry weather and sets the crest of the weir so that the base inflow
holds it there. The inflow, the weir width and the catchment have no survey, so
they are `ESTIMATED`.
"""

from std.math import isfinite, sqrt
from extensions.castle.plan import CastlePlan
from units.si import (
    Area64,
    Duration64,
    Length64,
    METER,
    VolumeFlowRate64,
)

# Standard gravity, in meters per second squared.
comptime _GRAVITY = 9.80665
# The correction of the head of a thin-plate weir, in meters: 0.003 ft.
comptime _HEAD_CORRECTION = 0.0009144
# The longest step of the integration, in seconds.
comptime _STEP = 60.0


@fieldwise_init
struct Weir(Copyable, Movable):
    """A thin-plate weir of the full width of its channel."""

    # The elevation of the crest, above the datum.
    var crest: Length64
    # The width of the crest, across the flow.
    var width: Length64
    # The height of the crest over the bed of the channel upstream.
    var crest_height: Length64

    def check(self) raises:
        """Refuse a weir that cannot be.

        Raises:
            Error: If the width or the crest height is not positive and
                finite, or the crest is not finite.
        """
        if not (
            isfinite(self.crest.value)
            and isfinite(self.width.value)
            and self.width.value > 0.0
            and isfinite(self.crest_height.value)
            and self.crest_height.value > 0.0
        ):
            raise Error(
                "A weir needs a finite crest and a positive finite width and"
                " crest height"
            )

    def discharge(self, level: Length64) raises -> VolumeFlowRate64:
        """Return the flow over the weir at a level of the water.

        Args:
            level: The elevation of the water upstream, above the datum.

        Returns:
            Zero if the water is at or under the crest, else the
            Kindsvater-Carter discharge.

        Raises:
            Error: If the weir is not valid, the level is not finite, or the
                head is 2.4 crest heights or more, outside the formula.
        """
        self.check()
        if not isfinite(level.value):
            raise Error("A level must be finite")
        var head = level.value - self.crest.value
        if head <= 0.0:
            return VolumeFlowRate64(0.0)
        if head >= 2.4 * self.crest_height.value:
            raise Error("The head is too high for the weir formula: h/p >= 2.4")
        var coefficient = 0.602 + 0.075 * head / self.crest_height.value
        var effective = head + _HEAD_CORRECTION
        return VolumeFlowRate64(
            2.0
            / 3.0
            * coefficient
            * sqrt(2.0 * _GRAVITY)
            * self.width.value
            * effective**1.5
        )


@fieldwise_init
struct DayWeather(ImplicitlyCopyable):
    """The rain and the evaporation of a day, as depths of water."""

    var rain: Length64
    var evaporation: Length64


@fieldwise_init
struct MoatBalance(Copyable, Movable):
    """A moat, as a tank with inflows and outflows."""

    # The area of the water, taken as constant over the range of levels.
    var area: Area64
    # The weir that holds the level.
    var weir: Weir
    # The flow of the brook that feeds the moat, in dry weather.
    var base_inflow: VolumeFlowRate64
    # The area that drains to the moat, and the share of its rain that runs
    # off.
    var catchment: Area64
    var runoff_coefficient: Float64
    # Seepage into the ground, in cubic meters a second for each meter of
    # head of the water over the groundwater.
    var seepage_conductance: Float64
    var groundwater: Length64

    def check(self) raises:
        """Refuse a balance that cannot be.

        Raises:
            Error: If the area is not positive, the inflow, the catchment or
                the conductance is negative, the runoff coefficient is not
                from 0 to 1, or the weir is not valid.
        """
        if not (isfinite(self.area.value) and self.area.value > 0.0):
            raise Error("A moat needs a positive finite area")
        if not (
            isfinite(self.base_inflow.value)
            and self.base_inflow.value >= 0.0
            and isfinite(self.catchment.value)
            and self.catchment.value >= 0.0
            and isfinite(self.seepage_conductance)
            and self.seepage_conductance >= 0.0
            and isfinite(self.groundwater.value)
        ):
            raise Error(
                "The inflow, the catchment and the seepage must be zero or"
                " more and finite"
            )
        if not (
            self.runoff_coefficient >= 0.0 and self.runoff_coefficient <= 1.0
        ):
            raise Error("A runoff coefficient must be from 0 to 1")
        self.weir.check()

    def net_rate(
        self, level: Length64, weather: DayWeather, seconds_a_day: Float64
    ) raises -> Float64:
        """Return the rate of change of the level, in meters a second.

        Args:
            level: The elevation of the water.
            weather: The rain and the evaporation of the day.
            seconds_a_day: The length of the day, in seconds, which spreads the
                depths of the weather over it.

        Returns:
            The net flow over the area.

        Raises:
            Error: If the balance is not valid, or the level is out of the
                range of the weir formula.
        """
        self.check()
        var rain = weather.rain.value
        var evaporation = weather.evaporation.value
        var inflow = (
            self.base_inflow.value
            + self.runoff_coefficient
            * rain
            * self.catchment.value
            / seconds_a_day
        )
        var outflow = self.weir.discharge(
            level
        ).value + self.seepage_conductance * max(
            level.value - self.groundwater.value, 0.0
        )
        var surface = (rain - evaporation) / seconds_a_day * self.area.value
        return (inflow - outflow + surface) / self.area.value

    def step(
        self,
        level: Length64,
        weather: DayWeather,
        duration: Duration64,
    ) raises -> Length64:
        """Return the level after a time, in weather that does not change.

        Args:
            level: The elevation of the water at the start.
            weather: The rain and the evaporation of a day. They are
                spread evenly over each day.
            duration: How long the weather lasts.

        Returns:
            The elevation at the end.

        Raises:
            Error: If the balance is not valid, the duration is negative or not
                finite, or the level leaves the range of the weir formula.
        """
        self.check()
        if not (isfinite(duration.value) and duration.value >= 0.0):
            raise Error("A duration must be zero or more and finite")
        var day = 86400.0
        var steps = max(1, Int(duration.value / _STEP + 0.999999))
        var dt = duration.value / Float64(steps)
        var h = level.value
        for _ in range(steps):
            var k1 = self.net_rate(Length64(h), weather, day)
            var k2 = self.net_rate(Length64(h + 0.5 * dt * k1), weather, day)
            var k3 = self.net_rate(Length64(h + 0.5 * dt * k2), weather, day)
            var k4 = self.net_rate(Length64(h + dt * k3), weather, day)
            h += dt / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
        return Length64(h)

    def storage(self, level: Length64, bed: Length64) -> Float64:
        """Return the volume of water above the bed, in cubic meters.

        Args:
            level: The elevation of the water.
            bed: The elevation of the bed.

        Returns:
            The area times the depth.
        """
        return self.area.value * (level.value - bed.value)

    def residence_time(
        self, level: Length64, bed: Length64
    ) raises -> Duration64:
        """Return how long the flow over the weir takes to fill the moat.

        Args:
            level: The elevation of the water.
            bed: The elevation of the bed.

        Returns:
            The stored volume over the discharge of the weir.

        Raises:
            Error: If the weir passes no flow at this level.
        """
        var flow = self.weir.discharge(level).value
        if not (flow > 0.0):
            raise Error("The weir passes no flow at this level")
        return Duration64(self.storage(level, bed) / flow)


def wijnendale_moat(plan: CastlePlan) raises -> MoatBalance:
    """Return the water balance of the moat of a plan.

    The area is that of the surveyed water. The weir is a channel of 1.2 m with
    a crest 1.4 m over the bed. The base inflow of the brook is 25 liters a
    second, and the crest is set so that this flow holds the water at the level
    that the laser scan found. The catchment is half a square kilometer of
    forest and field, of which 15 percent of the rain runs off. The seepage is
    none, with the moat sealed by silt. All of these are estimates.

    Args:
        plan: The plan.

    Returns:
        The balance.

    Raises:
        Error: If the plan is not valid.
    """
    var level = plan.moat.water_level.value
    var base = 0.025
    var width = 1.2
    var height = 1.4
    # The head that passes the base flow, by bisection: the discharge grows
    # with the head.
    var low = Float64(0)
    var high = 1.0
    for _ in range(200):
        var middle = (low + high) / 2.0
        var coefficient = 0.602 + 0.075 * middle / height
        var flow = (
            2.0
            / 3.0
            * coefficient
            * sqrt(2.0 * _GRAVITY)
            * width
            * (middle + _HEAD_CORRECTION) ** 1.5
        )
        if flow < base:
            low = middle
        else:
            high = middle
    var balance = MoatBalance(
        plan.moat.area(),
        Weir(
            Length64(level - high),
            Length64(width, METER),
            Length64(height, METER),
        ),
        VolumeFlowRate64(base),
        Area64(0.5e6),
        0.15,
        0.0,
        Length64(level - 1.0),
    )
    balance.check()
    return balance^
