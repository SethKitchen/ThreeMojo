# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Lime burning: limestone to quicklime and carbon dioxide.

The step must give off CO2 even into a kiln gas of pure CO2 at one
atmosphere, which sets its lower bound near 894 degC. A fact gives the
change into a kiln gas of 20 % CO2, where limestone decomposes at a lower
temperature. The calcite data stops at 1200 K, which ends the window.
"""

from extensions.chemistry.catalog import calcite, carbon_dioxide, lime
from extensions.chemistry.kinds import (
    BURN,
    CORROSIVE,
    ENGINEERING,
    THERMODYNAMIC,
)
from extensions.chemistry.quantities import ATMOSPHERE
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.requirement import action, proceeds
from extensions.chemistry.step import Step
from units.si import Pressure64
from units.temperature import CELSIUS, Temperature64


def _celsius(value: Float64) -> Temperature64:
    """Return a temperature given in degrees Celsius."""
    return Temperature64(value, CELSIUS)


def lime_burning() raises -> Step:
    """Return the burning of limestone to quicklime.

    Returns:
        The step: a kiln at one atmosphere, planned at 900 degC.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var step = Step(
        "Burn limestone to quicklime",
        Pressure64(1, ATMOSPHERE),
        Temperature64(800),
        Temperature64(1200),
        _celsius(900),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction(
                [
                    reactant(calcite()),
                    product(lime()),
                    product(carbon_dioxide()),
                ]
            ),
            "Limestone must give off CO2, even into pure CO2.",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Carry the CO2 away in the kiln gas. A lower CO2 pressure"
                " lowers the temperature where limestone decomposes."
            ),
            "the equilibrium in the data",
        )
    )
    step.add_fact(
        Reaction(
            [
                reactant(calcite()),
                product(lime()),
                product(carbon_dioxide(), 1, 0.2),
            ]
        )
    )
    step.add_hazard(BURN)
    step.add_hazard(CORROSIVE)
    return step^
