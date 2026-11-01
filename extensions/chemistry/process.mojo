# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The steps of a process, their requirements and their operating windows.

A `Requirement` is one condition a step needs, with the science it comes
from and its reason. Its `Check` says how it is tested:

- `PROCEEDS` and `HELD_BACK` compute a reaction's Gibbs energy change.
  The reaction can be a phase change, such as a liquid boiling, so a
  melting or boiling point comes from the data too. Where a substance's
  data does not reach a temperature, the requirement is not met there.
- `ABOVE` and `BELOW` compare the temperature with a stated bound, such as
  the eutectic of a vessel's steel, or a rate that practice has measured.
- `PRESSURE_ABOVE` and `PRESSURE_BELOW` compare the step's pressure.
- `ACTION` is a stated action that no number tests. It does not limit the
  window, and the report lists it.

A `Step` holds its requirements, its hazards, the least equipped setting
for it, its pressure, a temperature range to search and the temperature
planned. `operating_window` returns the temperatures in the range where
every requirement holds. Each bound of the window is the bound of one
requirement, so the report says why each temperature was chosen.

A step can also list facts: reactions to report at the planned
temperature that do not limit the window, such as the reaction that a
rival process step would need.
"""

from std.math import isfinite
from core.ordinal import require_valid
from extensions.chemistry.kinds import (
    ABOVE,
    ACTION,
    BELOW,
    Check,
    HELD_BACK,
    Hazard,
    PRESSURE_ABOVE,
    PRESSURE_BELOW,
    PROCEEDS,
    RequirementKind,
    Setting,
)
from extensions.chemistry.quantities import KILOJOULE_PER_MOLE
from extensions.chemistry.reaction import Reaction
from loaders.js_number import js_to_fixed
from units.si import KILOPASCAL, Pressure64
from units.temperature import CELSIUS, Temperature64

# The samples of a requirement over a search range. A change between two
# samples is found by bisection.
comptime _SAMPLES = 400
# Bisection steps for a window edge.
comptime _BISECTIONS = 60
# The kelvin offset of the Celsius scale.
comptime _ZERO_CELSIUS = 273.15


def _require_pressure(pressure: Pressure64) raises:
    """Refuse a pressure that is not finite and positive."""
    if not (isfinite(pressure.value) and pressure.value > 0):
        raise Error("A pressure must be finite and positive")


struct Requirement(Copyable, Movable):
    """One condition a process step needs."""

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
    # Where a stated bound comes from.
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
            source: Where a stated bound comes from.

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

    def is_met(
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
            return text + ": dG " + _signed(g) + " kJ/mol"
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
        "computed from NASA TM-4513 data",
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
        "computed from NASA TM-4513 data",
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
        The requirement. It always holds, and the report lists it.

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


@fieldwise_init
struct Interval(ImplicitlyCopyable):
    """A range of temperature, low end first."""

    var low: Temperature64
    var high: Temperature64


def interval_text(interval: Interval) raises -> String:
    """Return a range in kelvin and degrees Celsius.

    Args:
        interval: The range.

    Returns:
        Text such as "987.0 K (713.9 degC) to 1356.4 K (1083.2 degC)".

    Raises:
        Error: Never. The digit count is a constant.
    """
    return kelvin_text(interval.low) + " to " + kelvin_text(interval.high)


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


def _signed(value: Float64) raises -> String:
    """Return a number to 0.1 with its sign."""
    var text = js_to_fixed(value, 1)
    if value >= 0:
        return "+" + text
    return text


struct Step(Copyable, Movable):
    """One step of a process, with what it needs."""

    var name: String
    var setting: Setting
    # The total pressure of the step.
    var pressure: Pressure64
    # The range of temperature to search for a window.
    var low: Temperature64
    var high: Temperature64
    # The temperature the step is planned to run at.
    var planned: Temperature64
    var requirements: List[Requirement]
    # Reactions to report at the planned temperature. They do not limit
    # the window.
    var facts: List[Reaction]
    var hazards: List[Hazard]

    def __init__(
        out self,
        name: String,
        setting: Setting,
        pressure: Pressure64,
        low: Temperature64,
        high: Temperature64,
        planned: Temperature64,
    ) raises:
        """Make a step with no requirements yet.

        Args:
            name: What the step does.
            setting: The least equipped place where it can be done.
            pressure: Its total pressure.
            low: The low end of the range to search.
            high: The high end of the range to search.
            planned: The temperature it is planned to run at.

        Raises:
            Error: If the setting is not valid, the pressure is not finite
                and positive, the range is not physical and increasing, or
                the planned temperature is outside it.
        """
        require_valid(setting.is_valid(), "A step setting is not valid")
        _require_pressure(pressure)
        if not (low.is_valid() and high.is_valid()):
            raise Error("A step's range must be physical temperatures")
        if not (low.kelvin < high.kelvin):
            raise Error("A step's range must increase")
        if not (planned.kelvin >= low.kelvin and planned.kelvin <= high.kelvin):
            raise Error("A step's planned temperature must lie in its range")
        self.name = name
        self.setting = setting
        self.pressure = pressure
        self.low = low
        self.high = high
        self.planned = planned
        self.requirements = List[Requirement]()
        self.facts = List[Reaction]()
        self.hazards = List[Hazard]()

    def add(mut self, var requirement: Requirement):
        """Add a requirement.

        Args:
            requirement: The requirement.
        """
        self.requirements.append(requirement^)

    def add_fact(mut self, var reaction: Reaction):
        """Add a reaction to report at the planned temperature.

        Args:
            reaction: The reaction.
        """
        self.facts.append(reaction^)

    def add_hazard(mut self, hazard: Hazard) raises:
        """Add a hazard.

        Args:
            hazard: The hazard.

        Raises:
            Error: If the hazard is not valid.
        """
        require_valid(hazard.is_valid(), "A hazard is not valid")
        self.hazards.append(hazard)


def _edge(
    requirement: Requirement,
    low: Float64,
    high: Float64,
    low_met: Bool,
    pressure: Pressure64,
) raises -> Float64:
    """Return where a requirement changes between two temperatures."""
    var lo = low
    var hi = high
    for _ in range(_BISECTIONS):  # pragma: no branch
        var mid = 0.5 * (lo + hi)
        if requirement.is_met(Temperature64(mid), pressure) == low_met:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def met_intervals(
    requirement: Requirement,
    low: Temperature64,
    high: Temperature64,
    pressure: Pressure64,
) raises -> List[Interval]:
    """Return where in a range a requirement holds.

    Args:
        requirement: The requirement.
        low: The low end of the range.
        high: The high end of the range.
        pressure: The pressure.

    Returns:
        The intervals, coldest first. A change narrower than the
        sampling, a 400th of the range, can be missed.

    Raises:
        Error: If the range or the pressure is not physical.
    """
    _require_pressure(pressure)
    if not (low.is_valid() and high.is_valid() and low.kelvin < high.kelvin):
        raise Error("A search range must be physical and increase")
    var out = List[Interval]()
    var a = low.kelvin
    var b = high.kelvin
    var previous = a
    var was_met = requirement.is_met(low, pressure)
    var start = a
    for i in range(1, _SAMPLES + 1):  # pragma: no branch
        var t = a + (b - a) * Float64(i) / Float64(_SAMPLES)
        var met = requirement.is_met(Temperature64(t), pressure)
        if met != was_met:
            var edge = _edge(requirement, previous, t, was_met, pressure)
            if met:
                start = edge
            else:
                out.append(Interval(Temperature64(start), Temperature64(edge)))
            was_met = met
        previous = t
    if was_met:
        out.append(Interval(Temperature64(start), high))
    return out^


def _intersect(a: List[Interval], b: List[Interval]) -> List[Interval]:
    """Return the temperatures in both lists of sorted intervals."""
    var out = List[Interval]()
    var i = 0
    var j = 0
    while i < len(a) and j < len(b):
        var lo = max(a[i].low.kelvin, b[j].low.kelvin)
        var hi = min(a[i].high.kelvin, b[j].high.kelvin)
        if lo < hi:
            out.append(Interval(Temperature64(lo), Temperature64(hi)))
        if a[i].high.kelvin < b[j].high.kelvin:
            i += 1
        else:
            j += 1
    return out^


def operating_window(step: Step) raises -> List[Interval]:
    """Return where in the step's range every requirement holds.

    Args:
        step: The step.

    Returns:
        The intervals, coldest first. An empty list means no temperature
        in the range meets every requirement.

    Raises:
        Error: Never for a step this module made.
    """
    var window = List[Interval]()
    window.append(Interval(step.low, step.high))
    for r in step.requirements:
        var met = met_intervals(r, step.low, step.high, step.pressure)
        window = _intersect(window, met)
    return window^


def unmet(step: Step) raises -> Int:
    """Return how many requirements fail at the planned temperature.

    Args:
        step: The step.

    Returns:
        The count. Zero means the plan meets every requirement.

    Raises:
        Error: Never for a step this module made.
    """
    var count = 0
    for r in step.requirements:
        if not r.is_met(step.planned, step.pressure):
            count += 1
    return count


def report(step: Step) raises -> String:
    """Return a text report of a step: its window and its requirements.

    Args:
        step: The step.

    Returns:
        Lines that give the setting, the hazards, the window, each
        requirement at the planned temperature, and the facts.

    Raises:
        Error: If a fact's data does not reach the planned temperature.
    """
    var out = String(step.name, "\n")
    out += String("  Setting: ", step.setting.name(), "\n")
    out += "  Hazards:"
    if len(step.hazards) == 0:
        out += " none listed"
    var separator = String(" ")
    for h in step.hazards:
        out += separator + h.name()
        separator = ", "
    out += String(
        "\n  Pressure: ", js_to_fixed(step.pressure.to(KILOPASCAL), 3), " kPa\n"
    )
    var window = operating_window(step)
    out += "  Window:"
    if len(window) == 0:
        out += " none in " + interval_text(Interval(step.low, step.high))
    separator = " "
    for w in window:
        out += separator + interval_text(w)
        separator = "; "
    var failed = unmet(step)
    out += String("\n  Planned: ", kelvin_text(step.planned), ", ")
    if failed == 0:
        out += "every requirement met\n"
    else:
        out += String(failed, " requirement(s) not met\n")
    for r in step.requirements:
        var mark = String("[met]")
        if r.check == ACTION:
            mark = "[do]"
        elif not r.is_met(step.planned, step.pressure):
            mark = "[NOT MET]"
        out += String("  ", mark, " ", r.kind.name(), ": ", r.statement, "\n")
        out += String(
            "      ",
            r.describe(step.planned, step.pressure),
            "; ",
            r.source,
            "\n",
        )
    for f in step.facts:
        var g = f.delta_g(step.planned, step.pressure).to(KILOJOULE_PER_MOLE)
        var verb = String("proceeds")
        if g > 0:
            verb = "does not proceed"
        out += String(
            "  Fact: ", f, ": dG ", _signed(g), " kJ/mol, ", verb, "\n"
        )
    return out^
