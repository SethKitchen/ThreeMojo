# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Energy balances and a ledger of money.

A `StreamItem` is an amount of a substance at a temperature. The enthalpy
of a stream is the sum of amount times molar enthalpy, on the formation
scale. A step's heat duty is the enthalpy that leaves minus the enthalpy
that enters. A positive duty is heat the step needs. A negative duty is
heat the step gives off, which the equipment must remove.

`Money64` is an amount in one currency, which the caller chooses.
`UnitPrice64` is money per kilogram. `EnergyPrice64` is money per joule.
A `Ledger` adds up purchases, heat and sales, and returns the margin. It
leaves out labor, equipment, waste, losses and taxes.
"""

from std.math import isfinite
from extensions.chemistry.quantities import Amount64
from extensions.chemistry.thermo import Substance
from units.si import Energy64, Mass64
from units.temperature import Temperature64

# Joules in a kilowatt hour.
comptime _KILOWATT_HOUR = 3.6e6


struct StreamItem(Copyable, Movable):
    """An amount of a substance at a temperature."""

    var substance: Substance
    var amount: Amount64
    var temperature: Temperature64

    def __init__(
        out self,
        var substance: Substance,
        amount: Amount64,
        temperature: Temperature64,
    ):
        """Make a stream item. `stream_enthalpy` checks it.

        Args:
            substance: The substance.
            amount: How many moles.
            temperature: Its temperature.
        """
        self.substance = substance^
        self.amount = amount
        self.temperature = temperature


def stream_enthalpy(items: List[StreamItem]) raises -> Energy64:
    """Return the enthalpy of a stream, on the formation scale.

    Args:
        items: The substances in the stream.

    Returns:
        The sum of amount times molar enthalpy. An empty stream is zero.

    Raises:
        Error: If an amount is negative or not finite, or a substance's
            data does not reach its temperature.
    """
    var total = Float64(0)
    for item in items:
        if not (isfinite(item.amount.value) and item.amount.value >= 0):
            raise Error("An amount must be finite and not negative")
        var h = item.substance.enthalpy(item.temperature)
        total += h.times(item.amount).value
    return Energy64(total)


def heat_duty(
    entering: List[StreamItem], leaving: List[StreamItem]
) raises -> Energy64:
    """Return the heat a step needs: what leaves minus what enters.

    Args:
        entering: The feed, at its temperatures.
        leaving: The products, at theirs.

    Returns:
        The duty. Below zero, the step gives off heat.

    Raises:
        Error: If a stream is not valid.
    """
    return stream_enthalpy(leaving) - stream_enthalpy(entering)


def _require_amount(value: Float64, message: String) raises:
    """Refuse a value that is negative or not finite."""
    if not (isfinite(value) and value >= 0):
        raise Error(message)


@fieldwise_init
struct Money64(ImplicitlyCopyable, Writable):
    """An amount of money in one currency, which the caller chooses."""

    var value: Float64

    def __add__(self, other: Self) -> Self:
        """Add two amounts.

        Args:
            other: The amount to add.

        Returns:
            The sum.
        """
        return Self(self.value + other.value)

    def __sub__(self, other: Self) -> Self:
        """Subtract an amount.

        Args:
            other: The amount to subtract.

        Returns:
            The difference.
        """
        return Self(self.value - other.value)


@fieldwise_init
struct UnitPrice64(ImplicitlyCopyable):
    """A price per kilogram, in the ledger's currency."""

    var value: Float64

    def cost(self, mass: Mass64) -> Money64:
        """Return the price of a mass.

        Args:
            mass: The mass.

        Returns:
            Price times mass.
        """
        return Money64(self.value * mass.value)


@fieldwise_init
struct EnergyPrice64(ImplicitlyCopyable):
    """A price per joule, in the ledger's currency."""

    var value: Float64

    @staticmethod
    def per_kilowatt_hour(price: Float64) -> EnergyPrice64:
        """Return a price given per kilowatt hour, as utilities bill it.

        Args:
            price: The price of one kilowatt hour.

        Returns:
            The price per joule.
        """
        return EnergyPrice64(price / _KILOWATT_HOUR)

    def cost(self, energy: Energy64) -> Money64:
        """Return the price of an energy.

        Args:
            energy: The energy.

        Returns:
            Price times energy.
        """
        return Money64(self.value * energy.value)


struct Ledger(Copyable, Movable):
    """The money a process spends and earns."""

    var spent: Money64
    var earned: Money64

    def __init__(out self):
        """Make an empty ledger."""
        self.spent = Money64(0)
        self.earned = Money64(0)

    def buy(mut self, mass: Mass64, price: UnitPrice64) raises:
        """Record a purchase of material.

        Args:
            mass: The mass bought.
            price: Its price per kilogram.

        Raises:
            Error: If the mass or the price is negative or not finite.
        """
        _require_amount(mass.value, "A mass must be finite and not negative")
        _require_amount(price.value, "A price must be finite and not negative")
        self.spent = self.spent + price.cost(mass)

    def heat(
        mut self, duty: Energy64, price: EnergyPrice64, efficiency: Float64
    ) raises:
        """Record the energy bought to supply a heat duty.

        A duty of zero or below costs nothing. The ledger does not credit
        heat that a step gives off.

        Args:
            duty: The heat the step needs.
            price: The price of the energy bought.
            efficiency: The fraction of bought energy that reaches the
                step, above 0 and at most 1.

        Raises:
            Error: If the duty is not finite, the price is negative or not
                finite, or the efficiency is out of range.
        """
        if not isfinite(duty.value):
            raise Error("A heat duty must be finite")
        _require_amount(price.value, "A price must be finite and not negative")
        if not (efficiency > 0 and efficiency <= 1):
            raise Error("An efficiency must be above 0 and at most 1")
        if duty.value <= 0:
            return
        self.spent = self.spent + price.cost(Energy64(duty.value / efficiency))

    def sell(mut self, mass: Mass64, price: UnitPrice64) raises:
        """Record a sale of product.

        Args:
            mass: The mass sold.
            price: Its price per kilogram.

        Raises:
            Error: If the mass or the price is negative or not finite.
        """
        _require_amount(mass.value, "A mass must be finite and not negative")
        _require_amount(price.value, "A price must be finite and not negative")
        self.earned = self.earned + price.cost(mass)

    def margin(self) -> Money64:
        """Return what was earned minus what was spent.

        Returns:
            The margin. Below zero, the process loses money.
        """
        return self.earned - self.spent
