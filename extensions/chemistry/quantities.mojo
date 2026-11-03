# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The units of chemistry, in Float64.

`units.quantity.Quantity` has no dimension for an amount of substance. A
`Molar` value is a quantity per mole. Its parameters are the exponents of
the quantity it is per mole of, so a `MolarEnergy64` is joules per mole and
a `MolarMass64` is kilograms per mole. A molar value times an `Amount64`
is the plain `Quantity`. A molar entropy times a temperature is a molar
energy.

    var g = MolarEnergy64(-312.2, KILOJOULE_PER_MOLE)
    var heat = g.times(Amount64(2, MOLE))      # an Energy64, in joules

The pressure units and `FractureEnergy64` serve the steps and the
coatings of a process.
"""

from std.math import isfinite
from units.quantity import Quantity, Unit
from units.si import Mass64, Pressure64
from units.temperature import Temperature64


@fieldwise_init
struct MolarUnit[length: Int, mass: Int, time: Int, temperature: Int](
    ImplicitlyCopyable
):
    """A named scale factor on one molar dimension.

    Parameters:
        length: The length exponent of the quantity per mole.
        mass: The mass exponent.
        time: The time exponent.
        temperature: The temperature exponent.
    """

    # How many canonical units per mole one of these is worth.
    var scale: Float64
    var symbol: StaticString


@fieldwise_init
struct Molar[length: Int, mass: Int, time: Int, temperature: Int](
    ImplicitlyCopyable, Writable
):
    """A quantity per mole of substance, stored in SI units per mole.

    Parameters:
        length: The length exponent of the quantity per mole.
        mass: The mass exponent.
        time: The time exponent.
        temperature: The temperature exponent.
    """

    var value: Float64

    def __init__(
        out self,
        value: Float64,
        unit: MolarUnit[Self.length, Self.mass, Self.time, Self.temperature],
    ):
        """Create a molar value from a magnitude in `unit`.

        Args:
            value: The magnitude in `unit`.
            unit: The unit the magnitude is written in.
        """
        self.value = value * unit.scale

    def to(
        self,
        unit: MolarUnit[Self.length, Self.mass, Self.time, Self.temperature],
    ) -> Float64:
        """Return the magnitude in `unit`.

        Args:
            unit: The unit to read the magnitude in.

        Returns:
            The magnitude in `unit`.
        """
        return self.value / unit.scale

    def __add__(self, other: Self) -> Self:
        """Add two molar values of the same dimension.

        Args:
            other: The value to add.

        Returns:
            The sum.
        """
        return Self(self.value + other.value)

    def __sub__(self, other: Self) -> Self:
        """Subtract two molar values of the same dimension.

        Args:
            other: The value to subtract.

        Returns:
            The difference.
        """
        return Self(self.value - other.value)

    def __neg__(self) -> Self:
        """Return this value negated.

        Returns:
            The negated value.
        """
        return Self(-self.value)

    def scaled(self, factor: Float64) -> Self:
        """Return this value multiplied by a plain number.

        Args:
            factor: The number, such as a stoichiometric coefficient.

        Returns:
            The scaled value.
        """
        return Self(self.value * factor)

    def __lt__(self, other: Self) -> Bool:
        """Return True if this value is the smaller.

        Args:
            other: The value to compare with.

        Returns:
            Whether this value is less than `other`.
        """
        return self.value < other.value

    def __gt__(self, other: Self) -> Bool:
        """Return True if this value is the larger.

        Args:
            other: The value to compare with.

        Returns:
            Whether this value is greater than `other`.
        """
        return self.value > other.value

    def times(
        self, amount: Amount64
    ) -> Quantity[
        Self.length,
        Self.mass,
        Self.time,
        0,
        Self.temperature,
        DType.float64,
    ]:
        """Return this value for an amount of substance.

        Args:
            amount: How many moles.

        Returns:
            The plain quantity: a molar energy gives an energy.
        """
        return Quantity[
            Self.length,
            Self.mass,
            Self.time,
            0,
            Self.temperature,
            DType.float64,
        ](self.value * amount.value)

    def times_temperature(
        self, t: Temperature64
    ) -> Molar[Self.length, Self.mass, Self.time, Self.temperature + 1]:
        """Return this value multiplied by a thermodynamic temperature.

        Args:
            t: The temperature, from absolute zero.

        Returns:
            The product: a molar entropy gives a molar energy.
        """
        return Molar[Self.length, Self.mass, Self.time, Self.temperature + 1](
            self.value * t.kelvin
        )


@fieldwise_init
struct AmountUnit(ImplicitlyCopyable):
    """A named scale factor on an amount of substance."""

    # How many moles one of these is.
    var scale: Float64
    var symbol: StaticString


@fieldwise_init
struct Amount64(ImplicitlyCopyable, Writable):
    """An amount of substance, stored in moles."""

    var value: Float64

    def __init__(out self, value: Float64, unit: AmountUnit):
        """Create an amount from a magnitude in `unit`.

        Args:
            value: The magnitude in `unit`.
            unit: The unit the magnitude is written in.
        """
        self.value = value * unit.scale

    def to(self, unit: AmountUnit) -> Float64:
        """Return the magnitude in `unit`.

        Args:
            unit: The unit to read the magnitude in.

        Returns:
            The magnitude in `unit`.
        """
        return self.value / unit.scale

    def scaled(self, factor: Float64) -> Self:
        """Return this amount multiplied by a plain number.

        Args:
            factor: The number, such as a stoichiometric coefficient.

        Returns:
            The scaled amount.
        """
        return Self(self.value * factor)


comptime MolarEnergy64 = Molar[2, 1, -2, 0]
comptime MolarEnergyUnit = MolarUnit[2, 1, -2, 0]
# A molar entropy, and a molar heat capacity, which has the same dimension.
comptime MolarEntropy64 = Molar[2, 1, -2, -1]
comptime MolarEntropyUnit = MolarUnit[2, 1, -2, -1]
comptime MolarMass64 = Molar[0, 1, 0, 0]
comptime MolarMassUnit = MolarUnit[0, 1, 0, 0]
comptime MolarVolume64 = Molar[3, 0, 0, 0]
comptime MolarVolumeUnit = MolarUnit[3, 0, 0, 0]

comptime JOULE_PER_MOLE = MolarEnergyUnit(1.0, "J/mol")
comptime KILOJOULE_PER_MOLE = MolarEnergyUnit(1000.0, "kJ/mol")
comptime JOULE_PER_MOLE_KELVIN = MolarEntropyUnit(1.0, "J/(mol K)")
comptime KILOGRAM_PER_MOLE = MolarMassUnit(1.0, "kg/mol")
comptime GRAM_PER_MOLE = MolarMassUnit(0.001, "g/mol")
comptime CUBIC_METER_PER_MOLE = MolarVolumeUnit(1.0, "m^3/mol")
comptime CUBIC_CENTIMETER_PER_MOLE = MolarVolumeUnit(1.0e-6, "cm^3/mol")
comptime MOLE = AmountUnit(1.0, "mol")
comptime KILOMOLE = AmountUnit(1000.0, "kmol")

# The molar gas constant. It is exact since the 2019 SI: N_A times k.
comptime GAS_CONSTANT = MolarEntropy64(8.31446261815324)

comptime PressureUnit64 = Unit[-1, 1, -2, 0, 0, DType.float64]
# The standard-state pressure of the NASA and IUPAC tables: one bar.
comptime STANDARD_PRESSURE = Pressure64(1.0e5)
comptime BAR = PressureUnit64(1.0e5, "bar")
comptime ATMOSPHERE = PressureUnit64(101325.0, "atm")
# One torr is exactly 101325/760 Pa. Vacuum and coating work quote it.
comptime TORR = PressureUnit64(133.32236842105263, "Torr")

# Coating thickness is quoted in micrometers.
comptime MICROMETER = Unit[1, 0, 0, 0, 0, DType.float64](1.0e-6, "um")
# Crystal cells and bonds are quoted in angstroms.
comptime ANGSTROM = Unit[1, 0, 0, 0, 0, DType.float64](1.0e-10, "angstrom")

# The energy to open a unit area of crack along an interface: J/m^2. It has
# the dimension of a force per length.
comptime FractureEnergy64 = Quantity[0, 1, -2, 0, 0, DType.float64]
comptime JOULE_PER_SQUARE_METER = Unit[0, 1, -2, 0, 0, DType.float64](
    1.0, "J/m^2"
)


def amount_of(mass: Mass64, molar_mass: MolarMass64) raises -> Amount64:
    """Return how many moles a mass of a substance holds.

    Args:
        mass: The mass.
        molar_mass: The substance's molar mass.

    Returns:
        The amount of substance.

    Raises:
        Error: If the molar mass is not finite and positive, or the mass
            is not finite.
    """
    if not (isfinite(molar_mass.value) and molar_mass.value > 0):
        raise Error("A molar mass must be finite and positive")
    if not isfinite(mass.value):
        raise Error("A mass must be finite")
    return Amount64(mass.value / molar_mass.value)
