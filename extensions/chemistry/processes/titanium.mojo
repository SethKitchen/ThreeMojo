# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Kroll process: titanium sponge from rutile, in four steps.

1. Chlorinate rutile with coke to TiCl4 in a fluidized bed.
2. Distill the TiCl4.
3. Reduce the TiCl4 with liquid magnesium in a steel retort.
4. Boil the leftover magnesium and MgCl2 out of the sponge under vacuum.

`kroll_loop` is the same route as a flowsheet with its recycle: an
electrolysis cell splits the MgCl2 back into magnesium for the reducer
and chlorine for the chlorinator.

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
from extensions.chemistry.flowsheet import Flowsheet
from extensions.chemistry.quantities import ATMOSPHERE, Amount64, MOLE
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


def kroll_loop() raises -> Flowsheet:
    """Return the Kroll route as a flowsheet that recycles Mg and Cl2.

    The feeds are one mole of rutile and of carbon, and 0.1 mole of
    make-up chlorine. The chlorinator converts the limiting reactant
    fully, and the TiCl4 goes to the reducer. The rest leaves as off-gas,
    with the chlorine beyond what the rutile needs. The reducer makes
    titanium sponge and MgCl2, and an electrolysis cell splits the MgCl2.
    Its magnesium returns to the reducer and its chlorine to the
    chlorinator. The magnesium loop starts with two moles.

    Returns:
        The flowsheet, ready to `solve`. Its streams are named "ore",
        "make-up Cl2", "Cl2 recycle", "Mg recycle", "chlorinator feed",
        "chlorinated", "TiCl4", "off-gas", "reducer feed", "reduced",
        "sponge", "salt" and "cell out".

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var sheet = Flowsheet(
        [
            rutile(),
            graphite(),
            chlorine(),
            titanium_tetrachloride_gas(),
            carbon_dioxide(),
            magnesium(),
            magnesium_chloride(),
            titanium(),
        ]
    )
    var ore = sheet.add_stream("ore")
    var makeup = sheet.add_stream("make-up Cl2")
    var cl2 = sheet.add_stream("Cl2 recycle")
    var mg = sheet.add_stream("Mg recycle")
    var feed = sheet.add_stream("chlorinator feed")
    var chlorinated = sheet.add_stream("chlorinated")
    var tet = sheet.add_stream("TiCl4")
    var offgas = sheet.add_stream("off-gas")
    var reducer = sheet.add_stream("reducer feed")
    var reduced = sheet.add_stream("reduced")
    var sponge = sheet.add_stream("sponge")
    var salt = sheet.add_stream("salt")
    var cell = sheet.add_stream("cell out")
    sheet.set_feed(
        ore, ["TiO2", "graphite"], [Amount64(1, MOLE), Amount64(1, MOLE)]
    )
    sheet.set_feed(makeup, ["Cl2(g)"], [Amount64(0.1, MOLE)])
    sheet.set_guess(mg, ["Mg"], [Amount64(2, MOLE)])
    sheet.mixer("chlorinator feed", [ore, makeup, cl2], feed)
    sheet.reactor(
        "chlorinator",
        feed,
        chlorinated,
        Reaction(
            [
                reactant(rutile()),
                reactant(chlorine(), 2),
                reactant(graphite()),
                product(titanium_tetrachloride_gas()),
                product(carbon_dioxide()),
            ]
        ),
        1,
    )
    sheet.splitter("condenser", chlorinated, tet, offgas, ["TiCl4(g)"], [1])
    sheet.mixer("reducer feed", [tet, mg], reducer)
    sheet.reactor(
        "reducer",
        reducer,
        reduced,
        Reaction(
            [
                reactant(titanium_tetrachloride_gas()),
                reactant(magnesium(), 2),
                product(titanium()),
                product(magnesium_chloride(), 2),
            ]
        ),
        1,
    )
    sheet.splitter("tapping", reduced, sponge, salt, ["Ti"], [1])
    sheet.reactor(
        "electrolysis cell",
        salt,
        cell,
        Reaction(
            [
                reactant(magnesium_chloride()),
                product(magnesium()),
                product(chlorine()),
            ]
        ),
        1,
    )
    sheet.splitter("cell taps", cell, mg, cl2, ["Mg"], [1])
    return sheet^
