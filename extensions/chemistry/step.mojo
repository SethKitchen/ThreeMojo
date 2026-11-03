# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A process step: its conditions, its requirements and its report.

A `Step` holds a pressure, a temperature range to search, the planned
temperature, its requirements, its hazards and its facts. A fact is a
reaction that the report evaluates at the planned temperature without
limiting the window, such as the reaction a rival step would need.

`operating_window` returns where in the range every requirement holds.
Each bound of the window is the bound of one requirement, so `report`
can say why the step runs where it does. `unmet` counts the requirements
that fail at the planned temperature.
"""

from std.math import isfinite
from core.ordinal import require_valid
from extensions.chemistry.kinds import ACTION, Hazard
from extensions.chemistry.quantities import KILOJOULE_PER_MOLE
from extensions.chemistry.reaction import Reaction
from extensions.chemistry.requirement import (
    Requirement,
    kelvin_text,
    signed_text,
)
from extensions.chemistry.window import (
    Interval,
    interval_text,
    window_of,
)
from loaders.js_number import js_to_fixed
from units.si import KILOPASCAL, Pressure64
from units.temperature import Temperature64


struct Step(Copyable, Movable):
    """One step of a process, with what it needs."""

    var name: String
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
        pressure: Pressure64,
        low: Temperature64,
        high: Temperature64,
        planned: Temperature64,
    ) raises:
        """Make a step with no requirements yet.

        Args:
            name: What the step does.
            pressure: Its total pressure.
            low: The low end of the range to search.
            high: The high end of the range to search.
            planned: The temperature it is planned to run at.

        Raises:
            Error: If the pressure is not finite and positive, the range
                is not physical and increasing, or the planned temperature
                is outside it.
        """
        if not (isfinite(pressure.value) and pressure.value > 0):
            raise Error("A pressure must be finite and positive")
        if not (low.is_valid() and high.is_valid()):
            raise Error("A step's range must be physical temperatures")
        if not (low.kelvin < high.kelvin):
            raise Error("A step's range must increase")
        if not (planned.kelvin >= low.kelvin and planned.kelvin <= high.kelvin):
            raise Error("A step's planned temperature must lie in its range")
        self.name = name
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
    return window_of(step.requirements, step.low, step.high, step.pressure)


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
        if not r.holds(step.planned, step.pressure):
            count += 1
    return count


def report(step: Step) raises -> String:
    """Return a text report of a step: its window and its requirements.

    Args:
        step: The step.

    Returns:
        Lines that give the hazards, the pressure, the window, each
        requirement at the planned temperature, and the facts.

    Raises:
        Error: If a fact's data does not reach the planned temperature.
    """
    var out = String(step.name, "\n")
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
        elif not r.holds(step.planned, step.pressure):
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
            "  Fact: ", f, ": dG ", signed_text(g), " kJ/mol, ", verb, "\n"
        )
    return out^
