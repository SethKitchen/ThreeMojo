# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Thermochemical data: NASA polynomials, species and substances.

A `Nasa7` holds the seven-coefficient polynomials of McBride, Gordon and
Reno (NASA TM-4513, 1993), one set for each temperature segment:

    cp/R  = a1 + a2 T + a3 T^2 + a4 T^3 + a5 T^4
    H/RT  = a1 + a2 T/2 + a3 T^2/3 + a4 T^3/4 + a5 T^4/5 + a6/T
    S/R   = a1 ln T + a2 T + a3 T^2/2 + a4 T^3/3 + a5 T^4/4 + a7

H is the enthalpy of formation at 298.15 K plus the heat taken up since.
So G = H - T S of each species is on one scale, and the sum over a
reaction is its Gibbs energy change. S is at the standard pressure of one
bar.

A `Species` is one phase of one formula, valid over the range of its data.
A `Substance` is a formula across its condensed phases, solid to liquid,
or one gas. It picks the phase whose range holds the temperature. The ends
of adjacent ranges are the transition temperatures, such as a melting
point.
"""

from std.math import isfinite, log
from extensions.chemistry.elements import Formula
from extensions.chemistry.kinds import GAS, LIQUID, Phase, SOLID
from extensions.chemistry.quantities import (
    GAS_CONSTANT,
    MolarEnergy64,
    MolarEntropy64,
    MolarMass64,
    MolarVolume64,
)
from units.temperature import Temperature64

# Phases whose ranges meet closer than this, in kelvin, meet.
comptime _MEET = 1e-6


struct Nasa7(Copyable, Movable):
    """Seven-coefficient NASA polynomials over one or more segments."""

    # The segment ends, in kelvin, ascending: one more than the segments.
    var bounds: List[Float64]
    # Seven coefficients per segment, the lowest segment first.
    var coefficients: List[Float64]

    def __init__(
        out self, var bounds: List[Float64], var coefficients: List[Float64]
    ) raises:
        """Make a polynomial set from its segment ends and coefficients.

        Args:
            bounds: The segment ends in kelvin, ascending.
            coefficients: Seven per segment, a1 to a7, lowest first.

        Raises:
            Error: If there is no segment, the coefficient count is not
                seven per segment, an end is not finite and positive, the
                ends do not ascend, or a coefficient is not finite.
        """
        if len(bounds) < 2:
            raise Error("NASA data needs at least one segment")
        if len(coefficients) != 7 * (len(bounds) - 1):
            raise Error("NASA data needs seven coefficients per segment")
        # There are two ends at least, so the loops always run.
        for b in bounds:  # pragma: no branch
            if not (isfinite(b) and b > 0):
                raise Error("A NASA segment end must be finite and positive")
        for i in range(1, len(bounds)):  # pragma: no branch
            if bounds[i] <= bounds[i - 1]:
                raise Error("NASA segment ends must ascend")
        for c in coefficients:  # pragma: no branch
            if not isfinite(c):
                raise Error("A NASA coefficient must be finite")
        self.bounds = bounds^
        self.coefficients = coefficients^

    def t_min(self) -> Temperature64:
        """Return the lowest temperature of the data.

        Returns:
            The first segment's lower end.
        """
        return Temperature64(self.bounds[0])

    def t_max(self) -> Temperature64:
        """Return the highest temperature of the data.

        Returns:
            The last segment's upper end.
        """
        return Temperature64(self.bounds[len(self.bounds) - 1])

    def covers(self, temperature: Temperature64) -> Bool:
        """Return True if the data reaches a temperature.

        Args:
            temperature: The temperature.

        Returns:
            Whether it lies from the lowest end through the highest.
        """
        var t = temperature.kelvin
        return t >= self.bounds[0] and t <= self.bounds[len(self.bounds) - 1]

    def _base(self, temperature: Temperature64) raises -> Int:
        """Return the index of the first coefficient of the segment."""
        if not self.covers(temperature):
            raise Error("A temperature is outside the range of its data")
        var t = temperature.kelvin
        for i in range(1, len(self.bounds) - 1):
            if t <= self.bounds[i]:
                return 7 * (i - 1)
        return 7 * (len(self.bounds) - 2)

    def heat_capacity(
        self, temperature: Temperature64
    ) raises -> MolarEntropy64:
        """Return the molar heat capacity at constant pressure.

        Args:
            temperature: The temperature.

        Returns:
            The heat capacity cp, in J/(mol K).

        Raises:
            Error: If the temperature is outside the data.
        """
        var k = self._base(temperature)
        var t = temperature.kelvin
        ref a = self.coefficients
        var r = a[k] + t * (
            a[k + 1] + t * (a[k + 2] + t * (a[k + 3] + t * a[k + 4]))
        )
        return MolarEntropy64(GAS_CONSTANT.value * r)

    def enthalpy(self, temperature: Temperature64) raises -> MolarEnergy64:
        """Return the molar enthalpy on the formation scale.

        Args:
            temperature: The temperature.

        Returns:
            The enthalpy of formation at 298.15 K plus the heat taken up
            from 298.15 K to this temperature.

        Raises:
            Error: If the temperature is outside the data.
        """
        var k = self._base(temperature)
        var t = temperature.kelvin
        ref a = self.coefficients
        var r = (
            a[k]
            + t
            * (
                a[k + 1] / 2
                + t * (a[k + 2] / 3 + t * (a[k + 3] / 4 + t * a[k + 4] / 5))
            )
            + a[k + 5] / t
        )
        return MolarEnergy64(GAS_CONSTANT.value * t * r)

    def entropy(self, temperature: Temperature64) raises -> MolarEntropy64:
        """Return the molar entropy at the standard pressure.

        Args:
            temperature: The temperature.

        Returns:
            The absolute entropy at one bar.

        Raises:
            Error: If the temperature is outside the data.
        """
        var k = self._base(temperature)
        var t = temperature.kelvin
        ref a = self.coefficients
        var r = (
            a[k] * log(t)
            + t
            * (
                a[k + 1]
                + t * (a[k + 2] / 2 + t * (a[k + 3] / 3 + t * a[k + 4] / 4))
            )
            + a[k + 6]
        )
        return MolarEntropy64(GAS_CONSTANT.value * r)

    def gibbs(self, temperature: Temperature64) raises -> MolarEnergy64:
        """Return the molar Gibbs energy at the standard pressure.

        Args:
            temperature: The temperature.

        Returns:
            H - T S, on the formation scale.

        Raises:
            Error: If the temperature is outside the data.
        """
        return self.enthalpy(temperature) - self.entropy(
            temperature
        ).times_temperature(temperature)

    def shifted(self, delta_h: MolarEnergy64, delta_s: MolarEntropy64) -> Nasa7:
        """Return the data moved by a constant enthalpy and entropy.

        This makes a phase from a neighbor when only the change at
        298.15 K is known. It assumes that both phases have the same heat
        capacity.

        Args:
            delta_h: The enthalpy change from this phase to the new one.
            delta_s: The entropy change from this phase to the new one.

        Returns:
            The new phase's data, over the same segments.
        """
        var out = self.copy()
        var segments = len(self.bounds) - 1
        for s in range(segments):  # pragma: no branch
            out.coefficients[7 * s + 5] += delta_h.value / GAS_CONSTANT.value
            out.coefficients[7 * s + 6] += delta_s.value / GAS_CONSTANT.value
        return out^


struct Species(Copyable, Movable, Writable):
    """One phase of one formula, with its thermochemical data."""

    var name: String
    var formula: Formula
    var phase: Phase
    var thermo: Nasa7
    # Zero for a gas, or where the volume does not matter. The pressure
    # term of a condensed phase uses it.
    var molar_volume: MolarVolume64

    def __init__(
        out self,
        name: String,
        var formula: Formula,
        phase: Phase,
        var thermo: Nasa7,
        molar_volume: MolarVolume64,
    ) raises:
        """Make a species.

        Args:
            name: The name, such as "TiCl4(g)" or "diamond".
            formula: The atoms.
            phase: `SOLID`, `LIQUID` or `GAS`.
            thermo: The NASA data of this phase.
            molar_volume: The volume of a mole of a condensed phase.

        Raises:
            Error: If the phase is not valid, or the molar volume is
                negative or not finite.
        """
        if not phase.is_valid():
            raise Error("A species phase must be SOLID, LIQUID or GAS")
        if not (isfinite(molar_volume.value) and molar_volume.value >= 0):
            raise Error("A molar volume must be finite and not negative")
        self.name = name
        self.formula = formula^
        self.phase = phase
        self.thermo = thermo^
        self.molar_volume = molar_volume

    def covers(self, temperature: Temperature64) -> Bool:
        """Return True if the data reaches a temperature.

        Args:
            temperature: The temperature.

        Returns:
            Whether the temperature lies in the data's range.
        """
        return self.thermo.covers(temperature)

    def molar_mass(self) raises -> MolarMass64:
        """Return the mass of a mole.

        Returns:
            The formula's molar mass.

        Raises:
            Error: Never for a valid formula.
        """
        return self.formula.molar_mass()

    def write_to(self, mut writer: Some[Writer]):
        """Write the species' name.

        Args:
            writer: Where to write.
        """
        writer.write(self.name)


struct Substance(Copyable, Movable, Writable):
    """A formula across its condensed phases, or one gas."""

    var name: String
    # The phases, coldest first. Each range starts where the last ends.
    var phases: List[Species]

    def __init__(out self, name: String, var phases: List[Species]) raises:
        """Make a substance from its phases.

        Args:
            name: The name a reaction writes, such as "MgCl2".
            phases: The phases, coldest first.

        Raises:
            Error: If there is no phase, the formulas differ, a gas is
                joined to another phase, or a phase's range does not
                start where the one before it ends.
        """
        if len(phases) == 0:
            raise Error("A substance needs at least one phase")
        for i in range(1, len(phases)):
            if not phases[i].formula.same(phases[0].formula):
                raise Error("The phases of a substance share one formula")
            if phases[i].phase == GAS or phases[i - 1].phase == GAS:
                raise Error("A gas is a substance of its own")
            var start = phases[i].thermo.bounds[0]
            var end = phases[i - 1].thermo.t_max().kelvin
            if abs(start - end) > _MEET:
                raise Error("Adjacent phases must meet at a transition")
        self.name = name
        self.phases = phases^

    def is_gas(self) -> Bool:
        """Return True if the substance is a gas.

        Returns:
            Whether its one phase is `GAS`.
        """
        return self.phases[0].phase == GAS

    def covers(self, temperature: Temperature64) -> Bool:
        """Return True if some phase's data reaches a temperature.

        Args:
            temperature: The temperature.

        Returns:
            Whether it lies from the coldest phase's start through the
            hottest phase's end.
        """
        var t = temperature.kelvin
        var last = len(self.phases) - 1
        return (
            t >= self.phases[0].thermo.bounds[0]
            and t <= self.phases[last].thermo.t_max().kelvin
        )

    def _index(self, temperature: Temperature64) raises -> Int:
        """Return the index of the phase whose range holds a temperature."""
        # A substance has a phase, so the loop always runs.
        for i in range(len(self.phases)):  # pragma: no branch
            if self.phases[i].covers(temperature):
                return i
        raise Error("A temperature is outside the range of a substance")

    def phase_at(self, temperature: Temperature64) raises -> Phase:
        """Return the phase that holds at a temperature.

        At a transition temperature, the colder phase is returned.

        Args:
            temperature: The temperature.

        Returns:
            `SOLID`, `LIQUID` or `GAS`.

        Raises:
            Error: If no phase's data reaches the temperature.
        """
        return self.phases[self._index(temperature)].phase

    def molar_volume_at(
        self, temperature: Temperature64
    ) raises -> MolarVolume64:
        """Return the molar volume of the phase at a temperature.

        Args:
            temperature: The temperature.

        Returns:
            The phase's molar volume, zero for a gas.

        Raises:
            Error: If no phase's data reaches the temperature.
        """
        return self.phases[self._index(temperature)].molar_volume

    def gibbs(self, temperature: Temperature64) raises -> MolarEnergy64:
        """Return the standard molar Gibbs energy of the phase that holds.

        Args:
            temperature: The temperature.

        Returns:
            G at one bar, on the formation scale.

        Raises:
            Error: If no phase's data reaches the temperature.
        """
        return self.phases[self._index(temperature)].thermo.gibbs(temperature)

    def enthalpy(self, temperature: Temperature64) raises -> MolarEnergy64:
        """Return the molar enthalpy of the phase that holds.

        Args:
            temperature: The temperature.

        Returns:
            H on the formation scale.

        Raises:
            Error: If no phase's data reaches the temperature.
        """
        return self.phases[self._index(temperature)].thermo.enthalpy(
            temperature
        )

    def molar_mass(self) raises -> MolarMass64:
        """Return the mass of a mole.

        Returns:
            The formula's molar mass.

        Raises:
            Error: Never for a valid formula.
        """
        return self.phases[0].formula.molar_mass()

    def transition(self, colder: Phase, hotter: Phase) raises -> Temperature64:
        """Return where one phase gives way to the next.

        Args:
            colder: The phase below the transition.
            hotter: The phase above it.

        Returns:
            The first temperature where `colder` ends and `hotter`
            starts: `SOLID` to `LIQUID` is the melting point.

        Raises:
            Error: If the substance has no such transition.
        """
        for i in range(1, len(self.phases)):
            var below = self.phases[i - 1].phase == colder
            if below and self.phases[i].phase == hotter:
                return self.phases[i].thermo.t_min()
        raise Error("A substance does not have this transition")

    def melting_point(self) raises -> Temperature64:
        """Return the melting point in the data.

        Returns:
            The temperature where the last solid phase gives way to the
            liquid.

        Raises:
            Error: If the substance has no solid-to-liquid transition.
        """
        return self.transition(SOLID, LIQUID)

    def write_to(self, mut writer: Some[Writer]):
        """Write the substance's name.

        Args:
            writer: Where to write.
        """
        writer.write(self.name)
