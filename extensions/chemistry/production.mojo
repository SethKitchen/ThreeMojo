# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cost of a batch of grown crystals: energy, equipment time and
consumables, per kept carat.

A `GrowthRun` is one batch of a press or a reactor. Its crystals grow for
a time t. The equipment is busy for t plus a turnaround t0, the time to
load, heat, cool and unload. The cost of one run is

    cost = P t e + Q (t + t0) + C

P is the mean electric power while the crystals grow, e the price of
electric energy, Q the price of an hour of equipment time (capital,
upkeep and labor) and C the consumables of one run. The mass that is
sold is r n k t: r is the growth rate of one crystal, n the number of
crystals and k the share of the grown mass that is kept after rejects
and cutting. The cost per kept mass falls as t grows, toward the floor

    floor = (P e + Q) / (r n k)

The floor shows what makes a crystal cheap: a high growth rate on many
crystals at once, for each unit of power and of equipment time.

`Money64` is an amount of money in the caller's currency. A `Price` is
money per a quantity, so a price per kilowatt-hour and a price per carat
are different types:

    var e = EnergyPrice64(0.10, PER_KILOWATT_HOUR)
    var cost = run_cost(run, e)
    print(cost.per_mass().to(PER_CARAT))
"""

from std.math import isfinite
from loaders.js_number import js_to_fixed
from units.quantity import Quantity, Unit
from units.si import (
    Area64,
    Density64,
    Duration64,
    Energy64,
    HOUR,
    KILOWATT,
    KILOWATT_HOUR,
    Mass64,
    Power64,
    Velocity64,
)

# A mass per time: the growth rate of a crystal.
comptime MassRate64 = Quantity[0, 1, -1, 0, 0, DType.float64]
comptime MILLIGRAM_PER_HOUR = Unit[0, 1, -1, 0, 0, DType.float64](
    1.0e-6 / 3600.0, "mg/h"
)
# The metric carat is exactly 200 mg, by the 4th CGPM (1907).
comptime CARAT = Unit[0, 1, 0, 0, 0, DType.float64](2.0e-4, "ct")
# A layer's growth rate is quoted in micrometers per hour.
comptime MICROMETER_PER_HOUR = Unit[1, 0, -1, 0, 0, DType.float64](
    1.0e-6 / 3600.0, "um/h"
)
# Diamond's density at room temperature: 3.515 g/cm^3.
comptime DIAMOND_DENSITY = Density64(3515.0)


@fieldwise_init
struct Money64(ImplicitlyCopyable, Writable):
    """An amount of money, in the currency the caller chooses."""

    var value: Float64

    def __add__(self, other: Self) -> Self:
        """Add two amounts.

        Args:
            other: The amount to add.

        Returns:
            The sum.
        """
        return Self(self.value + other.value)

    def scaled(self, factor: Float64) -> Self:
        """Return this amount multiplied by a plain number.

        Args:
            factor: The number.

        Returns:
            The scaled amount.
        """
        return Self(self.value * factor)


@fieldwise_init
struct PriceUnit[length: Int, mass: Int, time: Int](ImplicitlyCopyable):
    """A named scale factor on a price.

    Parameters:
        length: The length exponent of the quantity the price is per.
        mass: The mass exponent.
        time: The time exponent.
    """

    # How much money per canonical unit one of these is worth: a price
    # of one per kilowatt-hour is 1 / 3.6e6 per joule.
    var scale: Float64
    var symbol: StaticString


@fieldwise_init
struct Price[length: Int, mass: Int, time: Int](ImplicitlyCopyable, Writable):
    """Money per a quantity, stored per canonical unit.

    Parameters:
        length: The length exponent of the quantity the price is per.
        mass: The mass exponent.
        time: The time exponent.
    """

    var value: Float64

    def __init__(
        out self,
        value: Float64,
        unit: PriceUnit[Self.length, Self.mass, Self.time],
    ):
        """Create a price from a magnitude in `unit`.

        Args:
            value: The magnitude in `unit`.
            unit: The unit the magnitude is written in.
        """
        self.value = value * unit.scale

    def to(self, unit: PriceUnit[Self.length, Self.mass, Self.time]) -> Float64:
        """Return the magnitude in `unit`.

        Args:
            unit: The unit to read the magnitude in.

        Returns:
            The magnitude in `unit`.
        """
        return self.value / unit.scale

    def times(
        self,
        quantity: Quantity[
            Self.length, Self.mass, Self.time, 0, 0, DType.float64
        ],
    ) -> Money64:
        """Return the money for a quantity at this price.

        Args:
            quantity: The quantity, such as an energy for a price per
                kilowatt-hour.

        Returns:
            The money.
        """
        return Money64(self.value * quantity.value)


# Money per energy, per mass and per time.
comptime EnergyPrice64 = Price[2, 1, -2]
comptime MassPrice64 = Price[0, 1, 0]
comptime TimePrice64 = Price[0, 0, 1]
comptime PER_KILOWATT_HOUR = PriceUnit[2, 1, -2](1.0 / 3.6e6, "/kWh")
comptime PER_CARAT = PriceUnit[0, 1, 0](1.0 / 2.0e-4, "/ct")
comptime PER_HOUR = PriceUnit[0, 0, 1](1.0 / 3600.0, "/h")


def _require_positive(value: Float64, message: String) raises:
    """Refuse a value that is not finite and positive."""
    if not (isfinite(value) and value > 0):
        raise Error(message)


def _require_not_negative(value: Float64, message: String) raises:
    """Refuse a value that is not finite and zero or more."""
    if not (isfinite(value) and value >= 0):
        raise Error(message)


def layer_rate(
    thickness_rate: Velocity64,
    area: Area64,
    density: Density64 = DIAMOND_DENSITY,
) raises -> MassRate64:
    """Return the mass rate of a layer that grows on one face.

    Args:
        thickness_rate: How fast the layer thickens.
        area: The face's area.
        density: The layer's density. Diamond's by default.

    Returns:
        The mass the face gains per time.

    Raises:
        Error: If a value is not finite and positive.
    """
    _require_positive(thickness_rate.value, "A growth rate must be positive")
    _require_positive(area.value, "An area must be finite and positive")
    _require_positive(density.value, "A density must be finite and positive")
    return MassRate64(thickness_rate.value * area.value * density.value)


struct GrowthRun(Copyable, Movable):
    """One batch of a press or a reactor that grows crystals."""

    var name: String
    # How long the crystals grow in one run.
    var growth: Duration64
    # The time the equipment is busy but does not grow: load, pump, heat,
    # cool and unload.
    var turnaround: Duration64
    # The mean electric power while the crystals grow.
    var power: Power64
    # How many crystals grow at once.
    var crystals: Int
    # The growth rate of one crystal, as a mass per time.
    var rate: MassRate64
    # The share of the grown mass that is sold, after rejects and cutting.
    var kept: Float64
    # Seeds, gases, cell parts and wear, for one run.
    var consumables: Money64
    # The price of an hour of equipment time: capital, upkeep and labor.
    var equipment: TimePrice64

    def __init__(
        out self,
        name: String,
        growth: Duration64,
        turnaround: Duration64,
        power: Power64,
        crystals: Int,
        rate: MassRate64,
        kept: Float64,
        consumables: Money64,
        equipment: TimePrice64,
    ) raises:
        """Make a run.

        Args:
            name: What the run grows, and how.
            growth: How long the crystals grow.
            turnaround: The busy time that does not grow.
            power: The mean electric power while the crystals grow.
            crystals: How many crystals grow at once.
            rate: The growth rate of one crystal.
            kept: The share of the grown mass that is sold, above 0 and
                at most 1.
            consumables: The consumables of one run.
            equipment: The price of an hour of equipment time.

        Raises:
            Error: If the growth time or the rate is not finite and
                positive, the turnaround, the power, the consumables or
                the equipment price is negative or not finite, there is
                no crystal, or the kept share is not above 0 and at most 1.
        """
        _require_positive(growth.value, "A growth time must be positive")
        _require_not_negative(
            turnaround.value, "A turnaround must be finite and not negative"
        )
        _require_not_negative(
            power.value, "A power must be finite and not negative"
        )
        if crystals < 1:
            raise Error("A run must grow one crystal at least")
        _require_positive(rate.value, "A growth rate must be positive")
        if not (kept > 0 and kept <= 1):
            raise Error("A kept share must be above 0 and at most 1")
        _require_not_negative(
            consumables.value, "Consumables must be finite and not negative"
        )
        _require_not_negative(
            equipment.value, "An equipment price must be finite, not negative"
        )
        self.name = name
        self.growth = growth
        self.turnaround = turnaround
        self.power = power
        self.crystals = crystals
        self.rate = rate
        self.kept = kept
        self.consumables = consumables
        self.equipment = equipment

    def grown_mass(self) -> Mass64:
        """Return the mass that one run grows on all its crystals.

        Returns:
            The rate times the growth time times the crystals.
        """
        return Mass64(
            self.rate.value * self.growth.value * Float64(self.crystals)
        )

    def kept_mass(self) -> Mass64:
        """Return the mass of one run that is sold.

        Returns:
            The grown mass times the kept share.
        """
        return Mass64(self.grown_mass().value * self.kept)

    def energy(self) -> Energy64:
        """Return the electric energy of one run.

        Returns:
            The power times the growth time.
        """
        return Energy64(self.power.value * self.growth.value)

    def output(self) -> MassRate64:
        """Return the kept mass per time that the equipment is busy.

        Returns:
            The kept mass over the growth time plus the turnaround.
        """
        return MassRate64(
            self.kept_mass().value / (self.growth.value + self.turnaround.value)
        )


@fieldwise_init
struct CostBreakdown(ImplicitlyCopyable):
    """The cost of one run, by what it is spent on, and its kept mass."""

    var energy: Money64
    var equipment: Money64
    var consumables: Money64
    # The mass of the run that is sold.
    var mass: Mass64

    def total(self) -> Money64:
        """Return the cost of the run.

        Returns:
            The energy, the equipment time and the consumables.
        """
        return self.energy + self.equipment + self.consumables

    def per_mass(self) -> MassPrice64:
        """Return the cost per kept mass.

        Returns:
            The total over the kept mass, which is above zero for a run
            this module made.
        """
        return MassPrice64(self.total().value / self.mass.value)


def _require_electricity(electricity: EnergyPrice64) raises:
    """Refuse a price of electric energy that is negative or not finite."""
    _require_not_negative(
        electricity.value, "An energy price must be finite and not negative"
    )


def run_cost(
    run: GrowthRun, electricity: EnergyPrice64
) raises -> CostBreakdown:
    """Return the cost of one run, by what it is spent on.

    Args:
        run: The run.
        electricity: The price of electric energy.

    Returns:
        The energy, the equipment time, the consumables and the kept mass.

    Raises:
        Error: If the energy price is negative or not finite.
    """
    _require_electricity(electricity)
    var busy = Duration64(run.growth.value + run.turnaround.value)
    return CostBreakdown(
        electricity.times(run.energy()),
        run.equipment.times(busy),
        run.consumables,
        run.kept_mass(),
    )


def _time_cost(run: GrowthRun, electricity: EnergyPrice64) -> Float64:
    """Return the money per second of growth that grows with time."""
    return run.power.value * electricity.value + run.equipment.value


def _kept_rate(run: GrowthRun) -> Float64:
    """Return the kept mass per second of growth, in kg/s."""
    return run.rate.value * Float64(run.crystals) * run.kept


def cost_floor(
    run: GrowthRun, electricity: EnergyPrice64
) raises -> MassPrice64:
    """Return the cost per kept mass that longer runs approach.

    The fixed costs of a run, its turnaround and its consumables, spread
    over more mass as the growth time grows. The energy and the equipment
    time of growth do not.

    Args:
        run: The run.
        electricity: The price of electric energy.

    Returns:
        (P e + Q) / (r n k): the cost per kept mass of a run that grows
        for ever.

    Raises:
        Error: If the energy price is negative or not finite.
    """
    _require_electricity(electricity)
    return MassPrice64(_time_cost(run, electricity) / _kept_rate(run))


def growth_for_price(
    run: GrowthRun, electricity: EnergyPrice64, target: MassPrice64
) raises -> Duration64:
    """Return the growth time at which a run reaches a cost per kept mass.

    Args:
        run: The run. Its own growth time is not used.
        electricity: The price of electric energy.
        target: The cost per kept mass to reach.

    Returns:
        The shortest growth time whose cost per kept mass is at or below
        the target. Zero when the run has no fixed cost.

    Raises:
        Error: If the energy price is negative or not finite, the target
            is not finite and positive, or the target is at or below the
            floor, which no growth time reaches.
    """
    _require_electricity(electricity)
    _require_positive(target.value, "A target price must be positive")
    var margin = target.value * _kept_rate(run) - _time_cost(run, electricity)
    if margin <= 0:
        raise Error("No growth time reaches a target at or below the floor")
    var fixed = (
        run.equipment.value * run.turnaround.value + run.consumables.value
    )
    return Duration64(fixed / margin)


def _share(part: Money64, total: Money64) raises -> String:
    """Return a part of a total as a percentage, to 0.1."""
    if total.value == 0:
        return "0.0"
    return js_to_fixed(100 * part.value / total.value, 1)


def cost_report(run: GrowthRun, electricity: EnergyPrice64) raises -> String:
    """Return a text report of what one run costs, and why.

    Args:
        run: The run.
        electricity: The price of electric energy.

    Returns:
        Lines that give the mass of a run, each cost with its share, the
        cost per kept carat, the floor for long runs and the output.

    Raises:
        Error: If the energy price is negative or not finite.
    """
    var cost = run_cost(run, electricity)
    var total = cost.total()
    var out = String(run.name, "\n")
    out += String(
        "  Per run: ",
        js_to_fixed(run.grown_mass().to(CARAT), 2),
        " ct grown on ",
        run.crystals,
        " crystals, ",
        js_to_fixed(run.kept_mass().to(CARAT), 2),
        " ct kept\n",
    )
    out += String(
        "  Time: ",
        js_to_fixed(run.growth.to(HOUR), 1),
        " h of growth and ",
        js_to_fixed(run.turnaround.to(HOUR), 1),
        " h of turnaround, at ",
        js_to_fixed(run.power.to(KILOWATT), 1),
        " kW\n",
    )
    out += String(
        "  Energy: ",
        js_to_fixed(run.energy().to(KILOWATT_HOUR), 1),
        " kWh, ",
        js_to_fixed(cost.energy.value, 2),
        " (",
        _share(cost.energy, total),
        " %)\n",
    )
    out += String(
        "  Equipment time: ",
        js_to_fixed(cost.equipment.value, 2),
        " (",
        _share(cost.equipment, total),
        " %)\n",
    )
    out += String(
        "  Consumables: ",
        js_to_fixed(cost.consumables.value, 2),
        " (",
        _share(cost.consumables, total),
        " %)\n",
    )
    out += String(
        "  Total: ",
        js_to_fixed(total.value, 2),
        " per run, ",
        js_to_fixed(cost.per_mass().to(PER_CARAT), 2),
        " per kept carat\n",
    )
    out += String(
        "  Floor for long runs: ",
        js_to_fixed(cost_floor(run, electricity).to(PER_CARAT), 2),
        " per kept carat\n",
    )
    out += String(
        "  Output: ",
        js_to_fixed(run.output().value * 86400.0 / CARAT.scale, 3),
        " kept carats per day of equipment time\n",
    )
    return out^
