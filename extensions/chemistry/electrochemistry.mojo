# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Electrochemistry: cell voltages, Faraday's law and cell energy.

A reaction that moves n electrons per mole has the reversible voltage
E = -dG / (n F). A reaction that runs by itself gives a positive E: a
battery. An electrolysis drives a reaction with a positive dG, and needs
at least its decomposition voltage, dG / (n F). The reaction's mole
fractions and activities make this the Nernst equation. The
thermoneutral voltage dH / (n F) is the voltage at which the cell neither
heats nor cools.

Faraday's law gives the mass a current deposits or frees: m = I t M eta /
(n F), with eta the current efficiency. `CellVoltage` adds the
overpotentials and the ohmic drop to the reversible voltage, and
`specific_energy` turns a cell voltage into energy per kilogram of
product.

`units.quantity.Quantity` has no electric dimension, so `Voltage64` and
`Current64` are their own types here.
"""

from std.math import isfinite
from extensions.chemistry.quantities import MolarMass64
from extensions.chemistry.reaction import Reaction
from units.quantity import Quantity, Unit
from units.si import Duration64, Mass64, Pressure64
from units.temperature import Temperature64

# The Faraday constant, C/mol. It is exact since the 2019 SI: e N_A.
comptime FARADAY = 96485.33212331001
# An energy per mass: J/kg.
comptime SpecificEnergy64 = Quantity[2, 0, -2, 0, 0, DType.float64]
comptime KILOWATT_HOUR_PER_KILOGRAM = Unit[2, 0, -2, 0, 0, DType.float64](
    3.6e6, "kWh/kg"
)


@fieldwise_init
struct Voltage64(ImplicitlyCopyable, Writable):
    """An electric potential difference, in volts."""

    var value: Float64

    def __add__(self, other: Self) -> Self:
        """Add two voltages.

        Args:
            other: The voltage to add.

        Returns:
            The sum.
        """
        return Self(self.value + other.value)


@fieldwise_init
struct Current64(ImplicitlyCopyable, Writable):
    """An electric current, in amperes."""

    var value: Float64


def _require_electrons(electrons: Float64) raises:
    """Refuse an electron count that is not finite and positive."""
    if not (isfinite(electrons) and electrons > 0):
        raise Error("An electron count must be finite and positive")


def _require_efficiency(efficiency: Float64) raises:
    """Refuse a current efficiency outside (0, 1]."""
    if not (efficiency > 0 and efficiency <= 1):
        raise Error("A current efficiency must be above 0 and at most 1")


def reversible_voltage(
    reaction: Reaction,
    electrons: Float64,
    temperature: Temperature64,
    pressure: Pressure64,
) raises -> Voltage64:
    """Return the reversible voltage of a cell reaction.

    Args:
        reaction: The cell reaction, with its mole fractions and
            activities.
        electrons: The electrons moved per mole of reaction, n.
        temperature: The temperature.
        pressure: The total pressure.

    Returns:
        The voltage E = -dG / (n F). Positive for a reaction that runs
            by itself.

    Raises:
        Error: If the electron count is not positive, or the change
            cannot be evaluated.
    """
    _require_electrons(electrons)
    var g = reaction.delta_g(temperature, pressure).value
    return Voltage64(-g / (electrons * FARADAY))


def decomposition_voltage(
    reaction: Reaction,
    electrons: Float64,
    temperature: Temperature64,
    pressure: Pressure64,
) raises -> Voltage64:
    """Return the least voltage that drives an electrolysis.

    Args:
        reaction: The decomposition, such as MgCl2 -> Mg + Cl2.
        electrons: The electrons moved per mole of reaction, n.
        temperature: The temperature.
        pressure: The total pressure.

    Returns:
        The voltage dG / (n F).

    Raises:
        Error: If the electron count is not positive, or the change
            cannot be evaluated.
    """
    var e = reversible_voltage(reaction, electrons, temperature, pressure)
    return Voltage64(-e.value)


def thermoneutral_voltage(
    reaction: Reaction, electrons: Float64, temperature: Temperature64
) raises -> Voltage64:
    """Return the voltage at which an electrolysis neither heats nor cools.

    Args:
        reaction: The decomposition.
        electrons: The electrons moved per mole of reaction, n.
        temperature: The temperature.

    Returns:
        The voltage dH / (n F).

    Raises:
        Error: If the electron count is not positive, or the change
            cannot be evaluated.
    """
    _require_electrons(electrons)
    return Voltage64(
        reaction.delta_h(temperature).value / (electrons * FARADAY)
    )


def faraday_mass(
    current: Current64,
    time: Duration64,
    molar_mass: MolarMass64,
    electrons: Float64,
    efficiency: Float64 = 1,
) raises -> Mass64:
    """Return the mass a current deposits or frees.

    Args:
        current: The current.
        time: How long it flows.
        molar_mass: The product's molar mass.
        electrons: The electrons per mole of product.
        efficiency: The share of the current that makes product.

    Returns:
        The mass m = I t M eta / (n F).

    Raises:
        Error: If the current or the time is negative or not finite, the
            molar mass or electron count is not positive, or the
            efficiency is out of range.
    """
    var values: List[Float64] = [current.value, time.value]
    for v in values:  # pragma: no branch
        if not (isfinite(v) and v >= 0):
            raise Error("A current and a time must be finite, not negative")
    if not (isfinite(molar_mass.value) and molar_mass.value > 0):
        raise Error("A molar mass must be finite and positive")
    _require_electrons(electrons)
    _require_efficiency(efficiency)
    var moles = current.value * time.value * efficiency / (electrons * FARADAY)
    return Mass64(moles * molar_mass.value)


def faraday_time(
    mass: Mass64,
    current: Current64,
    molar_mass: MolarMass64,
    electrons: Float64,
    efficiency: Float64 = 1,
) raises -> Duration64:
    """Return how long a current takes to make a mass.

    Args:
        mass: The mass wanted.
        current: The current, above zero.
        molar_mass: The product's molar mass.
        electrons: The electrons per mole of product.
        efficiency: The share of the current that makes product.

    Returns:
        The time t = m n F / (I M eta).

    Raises:
        Error: If the mass is negative, the current is not positive, or
            another value is out of range.
    """
    if not (isfinite(mass.value) and mass.value >= 0):
        raise Error("A mass must be finite and not negative")
    if not (isfinite(current.value) and current.value > 0):
        raise Error("A current must be finite and positive")
    var per_second = faraday_mass(
        current, Duration64(1), molar_mass, electrons, efficiency
    )
    return Duration64(mass.value / per_second.value)


@fieldwise_init
struct CellVoltage(ImplicitlyCopyable):
    """The parts of an electrolysis cell's voltage."""

    var reversible: Voltage64
    # The overpotential at each electrode, as a magnitude.
    var anode: Voltage64
    var cathode: Voltage64
    # The current times the resistance of the electrolyte and the leads.
    var ohmic: Voltage64

    def total(self) raises -> Voltage64:
        """Return the voltage the cell runs at.

        Returns:
            The reversible voltage plus the losses.

        Raises:
            Error: If a part is not finite or a loss is negative.
        """
        var losses: List[Float64] = [
            self.anode.value,
            self.cathode.value,
            self.ohmic.value,
        ]
        for v in losses:  # pragma: no branch
            if not (isfinite(v) and v >= 0):
                raise Error("A loss must be finite and not negative")
        if not isfinite(self.reversible.value):
            raise Error("A reversible voltage must be finite")
        return self.reversible + self.anode + self.cathode + self.ohmic


def specific_energy(
    voltage: Voltage64,
    molar_mass: MolarMass64,
    electrons: Float64,
    efficiency: Float64 = 1,
) raises -> SpecificEnergy64:
    """Return the electric energy per kilogram of product.

    Args:
        voltage: The cell voltage.
        molar_mass: The product's molar mass.
        electrons: The electrons per mole of product.
        efficiency: The current efficiency.

    Returns:
        The energy V n F / (M eta).

    Raises:
        Error: If the voltage is negative or not finite, or another value
            is out of range.
    """
    if not (isfinite(voltage.value) and voltage.value >= 0):
        raise Error("A cell voltage must be finite and not negative")
    if not (isfinite(molar_mass.value) and molar_mass.value > 0):
        raise Error("A molar mass must be finite and positive")
    _require_electrons(electrons)
    _require_efficiency(efficiency)
    return SpecificEnergy64(
        voltage.value * electrons * FARADAY / (molar_mass.value * efficiency)
    )
