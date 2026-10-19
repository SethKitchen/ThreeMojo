# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The water balance of a moat over a year, one day at a time.

The moat gains water from a stream and from rain. It loses water by
evaporation, by leakage through its lining and over a weir. Each day the
volume changes by the sum of those flows. The sides of the moat are taken as
vertical, so a volume change is a change of level over the water area.

The weir is a sharp-crested rectangular weir: Q = Cd (2/3) sqrt(2 g) b h^1.5
for a head h over the crest. The weir answers within hours. A daily step
therefore passes the whole surplus of a day over the weir and reports the
steady head for the mean flow. A deficit lowers the level below the crest.

`flanders_climate` holds monthly values for the Flemish lowland. The rain is
the 1991-2020 normal of the station at Uccle, 837 mm a year, from the Royal
Meteorological Institute. The open water evaporation, 608 mm a year, and the
stream are assumptions. Replace them with measurements of the site.
"""

from extensions.castle.plan import Moat
from math.finite import require_non_negative_finite, require_positive_finite
from std.math import pow, sqrt
from units.si import (
    Area64,
    Length64,
    METER,
    MILLIMETER,
    Velocity64,
    Volume64,
    VolumeFlowRate64,
    CUBIC_METER_PER_SECOND,
)
from extensions.castle.masonry import GRAVITY

# The seconds in a day.
comptime _DAY = 86400.0


struct Climate(Copyable, Movable):
    """Twelve monthly values of rain, evaporation and stream inflow."""

    # The depth of rain that falls in each month, January first.
    var precipitation: List[Length64]
    # The depth of water that evaporates from open water in each month.
    var evaporation: List[Length64]
    # The mean flow of the stream into the moat in each month.
    var inflow: List[VolumeFlowRate64]

    def __init__(
        out self,
        var precipitation: List[Length64],
        var evaporation: List[Length64],
        var inflow: List[VolumeFlowRate64],
    ):
        """Hold twelve months of each value.

        Args:
            precipitation: The rain depth of each month.
            evaporation: The evaporation depth of each month.
            inflow: The stream flow of each month.
        """
        self.precipitation = precipitation^
        self.evaporation = evaporation^
        self.inflow = inflow^

    def check(self) raises:
        """Refuse a climate that is not twelve months of real values.

        Nothing. The call returns when every month has a value that is zero
        or more and finite.

        Raises:
            Error: If a list does not hold 12 values, or a value is
                negative or not finite.
        """
        if len(self.precipitation) != 12:
            raise Error("A climate needs 12 monthly rain depths")
        if len(self.evaporation) != 12:
            raise Error("A climate needs 12 monthly evaporation depths")
        if len(self.inflow) != 12:
            raise Error("A climate needs 12 monthly stream flows")
        for month in range(12):  # pragma: no branch
            require_non_negative_finite(
                self.precipitation[month].value,
                "A rain depth must be zero or more",
            )
            require_non_negative_finite(
                self.evaporation[month].value,
                "An evaporation depth must be zero or more",
            )
            require_non_negative_finite(
                self.inflow[month].value,
                "A stream flow must be zero or more",
            )


def _days(month: Int) -> Int:
    """Return the days of a month, 0 for January, in a year of 365 days."""
    var days: List[Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return days[month]


def _mm(value: Float64) -> Length64:
    """Return millimeters as a length."""
    return Length64(value, MILLIMETER)


def flanders_climate() -> Climate:
    """Return monthly values for the Flemish lowland.

    Returns:
        Rain of 837 mm a year, open water evaporation of 608 mm and a
        stream that carries 10 L/s in winter and under 1 L/s in late
        summer. January comes first. The rain is the 1991-2020 normal of
        the station at Uccle. The evaporation and the stream are
        assumptions.
    """
    var rain_mm: List[Float64] = [
        75.5,
        65.1,
        59.3,
        46.7,
        59.7,
        70.8,
        76.9,
        86.5,
        65.3,
        67.8,
        76.2,
        87.4,
    ]
    var evaporation_mm: List[Float64] = [
        8.0,
        14.0,
        33.0,
        58.0,
        90.0,
        105.0,
        108.0,
        90.0,
        55.0,
        28.0,
        12.0,
        7.0,
    ]
    var stream_liters: List[Float64] = [
        10.0,
        10.0,
        8.0,
        6.0,
        3.0,
        1.5,
        0.8,
        0.5,
        0.8,
        2.0,
        5.0,
        9.0,
    ]
    var rain = List[Length64]()
    var evaporation = List[Length64]()
    var inflow = List[VolumeFlowRate64]()
    for month in range(12):
        rain.append(_mm(rain_mm[month]))
        evaporation.append(_mm(evaporation_mm[month]))
        inflow.append(VolumeFlowRate64(stream_liters[month] * 1.0e-3))
    return Climate(rain^, evaporation^, inflow^)


@fieldwise_init
struct Weir(ImplicitlyCopyable):
    """A sharp-crested rectangular weir that holds the level of the moat."""

    # The length of the crest across the flow.
    var crest: Length64
    # The discharge coefficient, Cd.
    var coefficient: Float64

    def check(self) raises:
        """Refuse a weir that passes no water.

        Nothing. The call returns when the crest and the coefficient are
        positive and finite.

        Raises:
            Error: If the crest or the coefficient is not positive and
                finite.
        """
        require_positive_finite(
            self.crest.value, "A weir crest must be positive"
        )
        require_positive_finite(
            self.coefficient, "A weir coefficient must be positive"
        )

    def head(self, flow: VolumeFlowRate64) raises -> Length64:
        """Return the head over the crest that passes a flow.

        Args:
            flow: The flow over the weir, zero or more.

        Returns:
            (Q / (Cd (2/3) sqrt(2 g) b))^(2/3).

        Raises:
            Error: If the weir is not valid or the flow is negative.
        """
        self.check()
        require_non_negative_finite(
            flow.value, "A weir flow must be zero or more"
        )
        var k = self._factor()
        return Length64(pow(flow.value / k, 2.0 / 3.0))

    def discharge(self, head: Length64) raises -> VolumeFlowRate64:
        """Return the flow that a head over the crest passes.

        Args:
            head: The head over the crest, zero or more.

        Returns:
            Cd (2/3) sqrt(2 g) b h^1.5.

        Raises:
            Error: If the weir is not valid or the head is negative.
        """
        self.check()
        require_non_negative_finite(
            head.value, "A weir head must be zero or more"
        )
        return VolumeFlowRate64(self._factor() * pow(head.value, 1.5))

    def _factor(self) -> Float64:
        return (
            self.coefficient
            * (2.0 / 3.0)
            * sqrt(2.0 * GRAVITY.value)
            * self.crest.value
        )


struct YearResult(Movable):
    """What a year of the water balance gives."""

    # How far the level stands below the weir crest at the end of each
    # day. Zero means the water is at the crest or over it.
    var drawdown: List[Length64]
    # The head over the crest on each day.
    var head: List[Length64]
    # The volume that went over the weir in the year.
    var spilled: Volume64
    # The volume that evaporated in the year.
    var evaporated: Volume64
    # The volume that leaked through the lining in the year.
    var leaked: Volume64

    def __init__(out self):
        """Start with no days."""
        self.drawdown = List[Length64]()
        self.head = List[Length64]()
        self.spilled = Volume64(0.0)
        self.evaporated = Volume64(0.0)
        self.leaked = Volume64(0.0)

    def lowest(self) -> Length64:
        """Return the greatest drawdown of the year.

        Returns:
            The most that the level stood below the crest.
        """
        var low = Length64(0.0)
        for day in range(len(self.drawdown)):
            if self.drawdown[day] > low:
                low = self.drawdown[day]
        return low

    def days_below(self, limit: Length64) -> Int:
        """Count the days on which the drawdown was more than a limit.

        Args:
            limit: The drawdown that counts.

        Returns:
            The number of days.
        """
        var count = 0
        for day in range(len(self.drawdown)):
            if self.drawdown[day] > limit:
                count += 1
        return count


def simulate_year(
    moat: Moat,
    climate: Climate,
    weir: Weir,
    leakage: Velocity64,
    rain_scale: Float64,
    inflow_scale: Float64,
) raises -> YearResult:
    """Run the water balance of a moat through a year.

    The year starts on 1 January with the water at the crest. Each day
    adds the stream inflow and the rain, and takes away the evaporation and
    the leakage. The rain and the evaporation of a month fall evenly over
    its days. A surplus goes over the weir. A deficit lowers the level.

    Args:
        moat: The moat. Its water area sets the level change of a volume.
        climate: The monthly rain, evaporation and stream flow.
        weir: The weir at the outlet.
        leakage: The speed at which water leaks through the lining, over
            the water area.
        rain_scale: A factor on the rain, 1 for a normal year and less for
            a dry one.
        inflow_scale: A factor on the stream flow, 0 if the stream fails.

    Returns:
        The daily drawdown and head, and the volumes that left.

    Raises:
        Error: If the moat, climate or weir is not valid, or the leakage
            or a scale is negative or not finite.
    """
    moat.check()
    climate.check()
    weir.check()
    require_non_negative_finite(leakage.value, "A leakage must be zero or more")
    require_non_negative_finite(rain_scale, "A rain scale must be zero or more")
    require_non_negative_finite(
        inflow_scale, "An inflow scale must be zero or more"
    )
    var area = moat.water_area().value
    var result = YearResult()
    var drawdown = 0.0
    for month in range(12):
        var days = _days(month)
        var rain = (
            climate.precipitation[month].value * rain_scale / Float64(days)
        )
        var evaporation = climate.evaporation[month].value / Float64(days)
        # A month has 28 days at least, so the loop always runs.
        for _ in range(days):  # pragma: no branch
            var gained = (
                climate.inflow[month].value * inflow_scale * _DAY + rain * area
            )
            var lost_evaporation = evaporation * area
            var lost_leakage = leakage.value * _DAY * area
            var net = gained - lost_evaporation - lost_leakage
            result.evaporated = result.evaporated + Volume64(lost_evaporation)
            result.leaked = result.leaked + Volume64(lost_leakage)
            var level = net / area - drawdown
            var head = 0.0
            if level >= 0.0:
                drawdown = 0.0
                var overflow = level * area
                result.spilled = result.spilled + Volume64(overflow)
                head = weir.head(VolumeFlowRate64(overflow / _DAY)).value
            else:
                drawdown = -level
            result.drawdown.append(Length64(drawdown))
            result.head.append(Length64(head))
    return result^


def required_inflow(
    moat: Moat,
    climate: Climate,
    leakage: Velocity64,
    month: Int,
    rain_scale: Float64,
) raises -> VolumeFlowRate64:
    """Return the stream flow that holds the level through one month.

    The flow balances the evaporation and the leakage less the rain.

    Args:
        moat: The moat.
        climate: The monthly values.
        leakage: The speed at which water leaks through the lining.
        month: The month, from 0 for January to 11 for December.
        rain_scale: A factor on the rain.

    Returns:
        The flow, or zero where the rain alone is enough.

    Raises:
        Error: If the moat, climate or leakage is not valid, the month is
            not 0 to 11, or the rain scale is negative.
    """
    moat.check()
    climate.check()
    require_non_negative_finite(leakage.value, "A leakage must be zero or more")
    require_non_negative_finite(rain_scale, "A rain scale must be zero or more")
    if month < 0 or month > 11:
        raise Error("A month must be 0 to 11")
    var seconds = Float64(_days(month)) * _DAY
    var depth = (
        climate.evaporation[month].value
        - climate.precipitation[month].value * rain_scale
    )
    var rate = depth / seconds + leakage.value
    return VolumeFlowRate64(max(rate, 0.0) * moat.water_area().value)
