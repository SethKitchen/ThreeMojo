# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Requirements: the conditions a process step needs.

`Constraint` is the extension point. Any type that says whether it holds at
a temperature and a pressure, and describes the number behind it, is a
constraint. `window.met_intervals` and `window.window_of` accept any
constraint, so a new kind of requirement needs no change to this package.

`Requirement` is the built-in constraint. Its `Check` says how it is tested:

- `PROCEEDS` and `HELD_BACK` compute a reaction's Gibbs energy change. A
  phase change is a reaction too, so a melting or boiling point at the
  step's pressure comes from the data. Where a substance's data does not
  reach a temperature, the requirement is not met there.
- `ABOVE` and `BELOW` compare the temperature with a stated bound, such as
  a vessel's eutectic or a rate that experiments measured.
- `PRESSURE_ABOVE` and `PRESSURE_BELOW` compare the pressure with a bound.
- `ACTION` is a stated action that no number tests. It always holds.

A `RequirementKind` names the science a requirement comes from. A stated
bound names its source, so a report keeps computed and measured limits
apart.
"""

from std.math import isfinite
from core.ordinal import require_valid
from extensions.chemistry.kinds import (
    ABOVE,
    ACTION,
    BELOW,
    Check,
    HELD_BACK,
    PRESSURE_ABOVE,
    PRESSURE_BELOW,
    PROCEEDS,
    RequirementKind,
)
from extensions.chemistry.quantities import KILOJOULE_PER_MOLE
from extensions.chemistry.reaction import Reaction
from loaders.js_number import js_to_fixed
from units.si import KILOPASCAL, Pressure64
from units.temperature import Temperature64

# The kelvin offset of the Celsius scale.
comptime _ZERO_CELSIUS = 273.15
# The source of a bound that a reaction check computes.
comptime COMPUTED = "computed from the thermochemical data"


trait Constraint(Copyable, Movable):
    """A condition that holds or fails at a temperature and a pressure."""

    def holds(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> Bool:
        """Return True if the condition holds.

        Args:
            temperature: The temperature.
            pressure: The total pressure.

        Returns:
            Whether the condition holds there.

        Raises:
            Error: If the condition cannot be evaluated, for example at a
                temperature that is not physical.
        """
        ...

    def describe(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> String:
        """Return the number behind the condition, for a report.

        Args:
            temperature: The temperature.
            pressure: The total pressure.

        Returns:
            One line of text.

        Raises:
            Error: If the condition cannot be evaluated.
        """
        ...


def kelvin_text(temperature: Temperature64) raises -> String:
    """Return a temperature in kelvin and degrees Celsius, to 0.1.

    Args:
        temperature: The temperature.

    Returns:
        Text such as "987.0 K (713.9 degC)".

    Raises:
        Error: Never. The digit count is a constant.
    """
    var k = temperature.kelvin
    return (
        js_to_fixed(k, 1)
        + " K ("
        + js_to_fixed(k - _ZERO_CELSIUS, 1)
        + " degC)"
    )


def signed_text(value: Float64) raises -> String:
    """Return a number to 0.1 with its sign.

    Args:
        value: The number.

    Returns:
        Text such as "+5.7" or "-309.9".

    Raises:
        Error: Never. The digit count is a constant.
    """
    var text = js_to_fixed(value, 1)
    if value >= 0:
        return "+" + text
    return text


def _require_pressure(pressure: Pressure64) raises:
    """Refuse a pressure that is not finite and positive."""
    if not (isfinite(pressure.value) and pressure.value > 0):
        raise Error("A pressure must be finite and positive")


struct Requirement(Constraint):
    """One condition a process step needs: the built-in constraint."""

    var kind: RequirementKind
    var check: Check
    # The reaction a `PROCEEDS` or `HELD_BACK` check computes.
    var reaction: Optional[Reaction]
    # The bound of an `ABOVE` or `BELOW` check.
    var temperature: Temperature64
    # The bound of a `PRESSURE_ABOVE` or `PRESSURE_BELOW` check.
    var pressure: Pressure64
    # What must hold, and why.
    var statement: String
    # Where the bound comes from.
    var source: String

    def __init__(
        out self,
        kind: RequirementKind,
        check: Check,
        var reaction: Optional[Reaction],
        temperature: Temperature64,
        pressure: Pressure64,
        statement: String,
        source: String,
    ) raises:
        """Make a requirement. The functions below are shorter to call.

        Args:
            kind: The science it comes from.
            check: How it is tested.
            reaction: The reaction of a reaction check, else `None`.
            temperature: The bound of a temperature check.
            pressure: The bound of a pressure check.
            statement: What must hold, and why.
            source: Where the bound comes from.

        Raises:
            Error: If the kind or the check is not valid, or a reaction
                check has no reaction.
        """
        require_valid(kind.is_valid(), "A requirement kind is not valid")
        require_valid(check.is_valid(), "A requirement check is not valid")
        if check.value <= HELD_BACK.value and not reaction:
            raise Error("A reaction check needs a reaction")
        self.kind = kind
        self.check = check
        self.reaction = reaction^
        self.temperature = temperature
        self.pressure = pressure
        self.statement = statement
        self.source = source

    def holds(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> Bool:
        """Return True if the requirement holds.

        Args:
            temperature: The temperature of the step.
            pressure: The pressure of the step.

        Returns:
            Whether it holds. A reaction check outside its data does not.

        Raises:
            Error: If the temperature or the pressure is not physical.
        """
        if self.check.value <= HELD_BACK.value:
            ref r = self.reaction.value()
            if not r.covers(temperature):
                return False
            var g = r.delta_g(temperature, pressure).value
            if self.check == PROCEEDS:
                return g < 0
            return g > 0
        if self.check == ABOVE:
            return temperature.kelvin > self.temperature.kelvin
        if self.check == BELOW:
            return temperature.kelvin < self.temperature.kelvin
        if self.check == PRESSURE_ABOVE:
            return pressure.value > self.pressure.value
        if self.check == PRESSURE_BELOW:
            return pressure.value < self.pressure.value
        return True

    def describe(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> String:
        """Return the number behind the requirement at a condition.

        Args:
            temperature: The temperature of the step.
            pressure: The pressure of the step.

        Returns:
            The reaction and its Gibbs energy change, or the bound.

        Raises:
            Error: If the temperature or the pressure is not physical.
        """
        if self.check.value <= HELD_BACK.value:
            ref r = self.reaction.value()
            var text = String(r)
            if not r.covers(temperature):
                return (
                    text
                    + ": the data does not reach "
                    + kelvin_text(temperature)
                )
            var g = r.delta_g(temperature, pressure).to(KILOJOULE_PER_MOLE)
            return text + ": dG " + signed_text(g) + " kJ/mol"
        if self.check.value <= BELOW.value:
            return "bound " + kelvin_text(self.temperature)
        if self.check.value <= PRESSURE_BELOW.value:
            return (
                "bound " + js_to_fixed(self.pressure.to(KILOPASCAL), 3) + " kPa"
            )
        return "action"


def proceeds(
    kind: RequirementKind, var reaction: Reaction, statement: String
) raises -> Requirement:
    """Return a requirement that a reaction proceeds.

    Args:
        kind: Usually `THERMODYNAMIC`, or `PHASE` for a phase change.
        reaction: The reaction, with the step's mole fractions.
        statement: What must hold, and why.

    Returns:
        The requirement. It holds where the Gibbs energy change is below
        zero.

    Raises:
        Error: If the kind is not valid.
    """
    return Requirement(
        kind,
        PROCEEDS,
        reaction^,
        Temperature64(0),
        Pressure64(0),
        statement,
        COMPUTED,
    )


def held_back(
    kind: RequirementKind, var reaction: Reaction, statement: String
) raises -> Requirement:
    """Return a requirement that a reaction does not proceed.

    Args:
        kind: Usually `PHASE`, such as a liquid that must not boil.
        reaction: The reaction, with the step's mole fractions.
        statement: What must hold, and why.

    Returns:
        The requirement. It holds where the Gibbs energy change is above
        zero.

    Raises:
        Error: If the kind is not valid.
    """
    return Requirement(
        kind,
        HELD_BACK,
        reaction^,
        Temperature64(0),
        Pressure64(0),
        statement,
        COMPUTED,
    )


def above(
    kind: RequirementKind,
    temperature: Temperature64,
    statement: String,
    source: String,
) raises -> Requirement:
    """Return a requirement that the temperature is above a bound.

    Args:
        kind: The science the bound comes from.
        temperature: The bound.
        statement: What must hold, and why.
        source: Where the bound comes from.

    Returns:
        The requirement.

    Raises:
        Error: If the kind or the bound is not valid.
    """
    require_valid(temperature.is_valid(), "A temperature bound is not valid")
    return Requirement(
        kind, ABOVE, None, temperature, Pressure64(0), statement, source
    )


def below(
    kind: RequirementKind,
    temperature: Temperature64,
    statement: String,
    source: String,
) raises -> Requirement:
    """Return a requirement that the temperature is below a bound.

    Args:
        kind: The science the bound comes from.
        temperature: The bound.
        statement: What must hold, and why.
        source: Where the bound comes from.

    Returns:
        The requirement.

    Raises:
        Error: If the kind or the bound is not valid.
    """
    require_valid(temperature.is_valid(), "A temperature bound is not valid")
    return Requirement(
        kind, BELOW, None, temperature, Pressure64(0), statement, source
    )


def pressure_above(
    kind: RequirementKind,
    pressure: Pressure64,
    statement: String,
    source: String,
) raises -> Requirement:
    """Return a requirement that the pressure is above a bound.

    Args:
        kind: The science the bound comes from.
        pressure: The bound.
        statement: What must hold, and why.
        source: Where the bound comes from.

    Returns:
        The requirement.

    Raises:
        Error: If the kind is not valid or the bound is not finite and
            positive.
    """
    _require_pressure(pressure)
    return Requirement(
        kind,
        PRESSURE_ABOVE,
        None,
        Temperature64(0),
        pressure,
        statement,
        source,
    )


def pressure_below(
    kind: RequirementKind,
    pressure: Pressure64,
    statement: String,
    source: String,
) raises -> Requirement:
    """Return a requirement that the pressure is below a bound.

    Args:
        kind: The science the bound comes from.
        pressure: The bound.
        statement: What must hold, and why.
        source: Where the bound comes from.

    Returns:
        The requirement.

    Raises:
        Error: If the kind is not valid or the bound is not finite and
            positive.
    """
    _require_pressure(pressure)
    return Requirement(
        kind,
        PRESSURE_BELOW,
        None,
        Temperature64(0),
        pressure,
        statement,
        source,
    )


def action(
    kind: RequirementKind, statement: String, source: String
) raises -> Requirement:
    """Return an action the step needs that no number tests.

    Args:
        kind: The science the action comes from.
        statement: What to do, and why.
        source: Where the action comes from.

    Returns:
        The requirement. It always holds, and a report lists it.

    Raises:
        Error: If the kind is not valid.
    """
    return Requirement(
        kind,
        ACTION,
        None,
        Temperature64(0),
        Pressure64(0),
        statement,
        source,
    )
