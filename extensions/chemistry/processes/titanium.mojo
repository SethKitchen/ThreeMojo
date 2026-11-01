# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Kroll process: titanium sponge from rutile, in four steps.

1. Chlorinate rutile with coke to TiCl4 in a fluidized bed.
2. Distill the TiCl4.
3. Reduce the TiCl4 with liquid magnesium in a steel retort.
4. Boil the leftover magnesium and MgCl2 out of the sponge under vacuum.

The reduction runs where MgCl2 is liquid, magnesium does not boil, and the
steel retort stays below the Fe-Ti eutectic. These are models of the
steps' requirements. They are not operating procedures.
"""

from extensions.chemistry.catalog import (
    carbon_dioxide,
    chlorine,
    graphite,
    magnesium,
    magnesium_chloride,
    magnesium_chloride_gas,
    magnesium_gas,
    oxygen,
    rutile,
    titanium,
    titanium_tetrachloride,
    titanium_tetrachloride_gas,
)
from extensions.chemistry.kinds import (
    BURN,
    CORROSIVE,
    ENGINEERING,
    KINETIC,
    PHASE,
    PRESSURE_VESSEL,
    PYROPHORIC,
    THERMODYNAMIC,
    TOXIC_GAS,
)
from extensions.chemistry.quantities import ATMOSPHERE
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.requirement import (
    above,
    action,
    below,
    held_back,
    proceeds,
)
from extensions.chemistry.step import Step
from units.si import Pressure64
from units.temperature import CELSIUS, Temperature64

# The iron-titanium eutectic, 1085 degC (Murray, 1981). A steel retort that
# holds titanium must stay below it.
comptime FE_TI_EUTECTIC = Temperature64(1358.15)


def _celsius(value: Float64) -> Temperature64:
    """Return a temperature given in degrees Celsius."""
    return Temperature64(value, CELSIUS)


def titanium_chlorination() raises -> Step:
    """Return the chlorination of rutile with coke, which makes TiCl4.

    Returns:
        The step: an industrial fluidized bed near 1000 degC.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Chlorinate rutile with coke to titanium tetrachloride",
        Pressure64(1, ATMOSPHERE),
        Temperature64(600),
        Temperature64(1500),
        _celsius(1000),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction(
                [
                    reactant(rutile()),
                    reactant(chlorine(), 2),
                    reactant(graphite()),
                    product(titanium_tetrachloride_gas()),
                    product(carbon_dioxide()),
                ]
            ),
            "Carbon takes the oxygen, so the chlorination can proceed.",
        )
    )
    step.add(
        above(
            KINETIC,
            _celsius(900),
            "Below about 900 degC the chlorination rate falls too far.",
            "chloride-process practice: beds run near 1000 degC",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Feed rutile low in calcium and magnesium. Their chlorides"
                " melt in the bed and stick it together."
            ),
            "chloride-process practice",
        )
    )
    step.add_fact(
        Reaction(
            [
                reactant(rutile()),
                reactant(chlorine(), 2),
                product(titanium_tetrachloride_gas()),
                product(oxygen()),
            ]
        )
    )
    step.add_hazard(TOXIC_GAS)
    step.add_hazard(BURN)
    return step^


def tetrachloride_distillation() raises -> Step:
    """Return the distillation that purifies TiCl4.

    Returns:
        The step: a still at one atmosphere.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Distill titanium tetrachloride",
        Pressure64(1, ATMOSPHERE),
        Temperature64(300),
        Temperature64(600),
        Temperature64(420),
    )
    step.add(
        proceeds(
            PHASE,
            Reaction(
                [
                    reactant(titanium_tetrachloride()),
                    product(titanium_tetrachloride_gas()),
                ]
            ),
            "TiCl4 must boil off the still.",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Remove vanadium first, for example with copper. VOCl3 boils"
                " at 127 degC, too close to TiCl4 to distill apart."
            ),
            "boiling points from the CRC Handbook",
        )
    )
    step.add(
        action(
            ENGINEERING,
            "Draw off SiCl4 first. It boils at 58 degC.",
            "boiling points from the CRC Handbook",
        )
    )
    step.add_hazard(TOXIC_GAS)
    step.add_hazard(CORROSIVE)
    return step^


def kroll_reduction() raises -> Step:
    """Return the reduction of TiCl4 with magnesium: the Kroll step.

    Returns:
        The step: a steel retort under argon at about one atmosphere.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Reduce TiCl4 with magnesium (Kroll)",
        Pressure64(1, ATMOSPHERE),
        Temperature64(800),
        Temperature64(1500),
        _celsius(850),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction(
                [
                    reactant(titanium_tetrachloride_gas()),
                    reactant(magnesium(), 2),
                    product(titanium()),
                    product(magnesium_chloride(), 2),
                ]
            ),
            "Magnesium must reduce the chloride.",
        )
    )
    step.add(
        above(
            PHASE,
            magnesium().melting_point(),
            "Magnesium must be liquid to meet the TiCl4 vapor.",
            "melting point in the NASA TM-4513 data",
        )
    )
    step.add(
        above(
            PHASE,
            magnesium_chloride().melting_point(),
            "MgCl2 must be liquid, so it can be drained from the retort.",
            "melting point in the NASA TM-4513 data",
        )
    )
    step.add(
        held_back(
            PHASE,
            Reaction([reactant(magnesium()), product(magnesium_gas())]),
            "Magnesium must not boil away at the retort pressure.",
        )
    )
    step.add(
        below(
            ENGINEERING,
            FE_TI_EUTECTIC,
            "The steel retort must stay below the Fe-Ti eutectic.",
            "Murray (1981), the Fe-Ti phase diagram: 1085 degC",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Fill the retort with argon. Titanium takes up oxygen and"
                " nitrogen and becomes brittle."
            ),
            "Kroll-process practice",
        )
    )
    step.add(
        action(
            KINETIC,
            (
                "Feed the TiCl4 slowly. The reaction gives off much heat,"
                " and the feed rate holds the temperature."
            ),
            "the heat duty from the data",
        )
    )
    step.add_fact(
        Reaction([reactant(titanium()), reactant(oxygen()), product(rutile())])
    )
    step.add_hazard(TOXIC_GAS)
    step.add_hazard(PYROPHORIC)
    step.add_hazard(BURN)
    return step^


def vacuum_distillation() raises -> Step:
    """Return the vacuum distillation that cleans the titanium sponge.

    Returns:
        The step: the retort at 10 Pa, so the leftovers boil off.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Boil Mg and MgCl2 out of the titanium sponge under vacuum",
        Pressure64(10),
        Temperature64(600),
        Temperature64(1500),
        _celsius(1000),
    )
    step.add(
        proceeds(
            PHASE,
            Reaction([reactant(magnesium()), product(magnesium_gas())]),
            "Leftover magnesium must evaporate.",
        )
    )
    step.add(
        proceeds(
            PHASE,
            Reaction(
                [
                    reactant(magnesium_chloride()),
                    product(magnesium_chloride_gas()),
                ]
            ),
            "Leftover MgCl2 must evaporate.",
        )
    )
    step.add(
        below(
            ENGINEERING,
            FE_TI_EUTECTIC,
            "The steel retort must stay below the Fe-Ti eutectic.",
            "Murray (1981), the Fe-Ti phase diagram: 1085 degC",
        )
    )
    step.add_hazard(PRESSURE_VESSEL)
    step.add_hazard(PYROPHORIC)
    step.add_hazard(BURN)
    return step^


def kroll_route() raises -> List[Step]:
    """Return the four steps from rutile to titanium sponge.

    Returns:
        Chlorination, distillation, reduction and vacuum distillation.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var steps = List[Step]()
    steps.append(titanium_chlorination())
    steps.append(tetrachloride_distillation())
    steps.append(kroll_reduction())
    steps.append(vacuum_distillation())
    return steps^
