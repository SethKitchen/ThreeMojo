# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Worked processes: titanium, a diamond-coated tool, bismuth and lime.

Each function returns a `Step` with its requirements. A computed bound
comes from the NASA data. A stated bound names its source. Gases are at
the step's pressure unless the reaction gives a mole fraction.

- The Kroll process makes titanium metal from rutile in four steps:
  chlorinate, distill, reduce with magnesium, and boil off the leftovers
  under vacuum. It is for an industrial plant only.
- A hot-filament reactor grows a diamond coating on a cemented carbide
  tool. Two steps: the substrate, and the filament that splits hydrogen.
  It needs an equipped lab.
- Bismuth from a store grows colored hopper crystals in a home workshop.
- Limestone burns to quicklime in a kiln.

These are models for learning and planning. They are not operating
procedures. Check every bound against the equipment's own limits.
"""

from extensions.chemistry.catalog import (
    atomic_hydrogen,
    calcite,
    carbon_dioxide,
    chlorine,
    diamond,
    graphite,
    hydrogen,
    lime,
    magnesium,
    magnesium_chloride,
    magnesium_chloride_gas,
    magnesium_gas,
    methane,
    oxygen,
    rutile,
    titanium,
    titanium_tetrachloride,
    titanium_tetrachloride_gas,
)
from extensions.chemistry.coating import ElasticLayer
from extensions.chemistry.kinds import (
    BURN,
    CORROSIVE,
    ELECTRICAL,
    ENGINEERING,
    EQUIPPED_LAB,
    FLAMMABLE_GAS,
    HOME_WORKSHOP,
    INDUSTRIAL_PLANT,
    KINETIC,
    PHASE,
    PHYSICAL,
    PRESSURE_VESSEL,
    PYROPHORIC,
    THERMODYNAMIC,
    TOXIC_GAS,
)
from extensions.chemistry.process import (
    Step,
    above,
    action,
    below,
    held_back,
    pressure_above,
    pressure_below,
    proceeds,
)
from extensions.chemistry.quantities import ATMOSPHERE, TORR
from extensions.chemistry.reaction import Reaction, product, reactant
from units.si import Pressure64, ThermalExpansion64
from units.temperature import CELSIUS, Temperature64

# The iron-titanium eutectic, 1085 degC (Murray, 1981). A steel retort that
# holds titanium must stay below it.
comptime _FE_TI_EUTECTIC = 1358.15
# The methane fraction of a hot-filament feed gas.
comptime _METHANE = 0.01
# The atomic hydrogen fraction a filament must reach at equilibrium.
comptime _ATOMIC_H = 0.01

# Chemical vapor deposition (CVD) diamond: Klein and Cardinale (1993) give
# 1143 GPa and 0.069. The expansion is a mean from about 1e-6 /K at room
# temperature to about 4e-6 /K near 1100 K.
comptime CVD_DIAMOND = ElasticLayer(
    Pressure64(1143e9), 0.069, ThermalExpansion64(3.0e-6)
)
# Tungsten carbide with about 6 % cobalt binder: typical values. Use the
# grade's own data for a design.
comptime CEMENTED_CARBIDE = ElasticLayer(
    Pressure64(630e9), 0.22, ThermalExpansion64(5.5e-6)
)


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
        INDUSTRIAL_PLANT,
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
        INDUSTRIAL_PLANT,
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
        INDUSTRIAL_PLANT,
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
            Temperature64(_FE_TI_EUTECTIC),
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
        INDUSTRIAL_PLANT,
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
            Temperature64(_FE_TI_EUTECTIC),
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


def diamond_coating() raises -> Step:
    """Return diamond growth on a cemented carbide tool.

    Returns:
        The substrate step of a hot-filament reactor: 1 % methane in
        hydrogen at 30 Torr, with the substrate at 850 degC.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Grow a diamond coating on a cemented carbide tool",
        EQUIPPED_LAB,
        Pressure64(30, TORR),
        Temperature64(600),
        Temperature64(1500),
        _celsius(850),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction(
                [
                    reactant(methane(), 1, _METHANE),
                    product(diamond()),
                    product(hydrogen(), 2, 1 - _METHANE),
                ]
            ),
            "Methane must be able to deposit diamond on the substrate.",
        )
    )
    step.add(
        above(
            KINETIC,
            _celsius(700),
            "Below about 700 degC growth is slow and the film is poor.",
            "May (2000), Phil. Trans. R. Soc. A 358",
        )
    )
    step.add(
        below(
            ENGINEERING,
            _celsius(1000),
            "Hotter, cobalt reaches the surface faster and makes graphite.",
            "diamond-on-carbide practice",
        )
    )
    step.add(
        pressure_above(
            PHYSICAL,
            Pressure64(10, TORR),
            "The gas must be dense enough to carry atomic hydrogen.",
            "hot-filament practice: about 10 to 100 Torr",
        )
    )
    step.add(
        pressure_below(
            PHYSICAL,
            Pressure64(100, TORR),
            "Atomic hydrogen must reach the substrate before it recombines.",
            "hot-filament practice: about 10 to 100 Torr",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Etch the cobalt binder from the surface first. Cobalt makes"
                " graphite and weakens the bond."
            ),
            "diamond-on-carbide practice",
        )
    )
    step.add(
        action(
            KINETIC,
            "Seed the surface with fine diamond powder, so growth can start.",
            "May (2000)",
        )
    )
    step.add(
        action(
            KINETIC,
            (
                "Supply atomic hydrogen from the filament. It etches graphite"
                " faster than diamond, so the metastable diamond survives."
            ),
            "May (2000)",
        )
    )
    step.add_fact(Reaction([reactant(graphite()), product(diamond())]))
    step.add_fact(
        Reaction(
            [
                reactant(methane(), 1, _METHANE),
                product(graphite()),
                product(hydrogen(), 2, 1 - _METHANE),
            ]
        )
    )
    step.add_hazard(FLAMMABLE_GAS)
    step.add_hazard(CORROSIVE)
    step.add_hazard(ELECTRICAL)
    step.add_hazard(PRESSURE_VESSEL)
    step.add_hazard(BURN)
    return step^


def hydrogen_filament() raises -> Step:
    """Return the filament that splits hydrogen for diamond growth.

    Returns:
        The filament step: tungsten in the same gas at 30 Torr, planned
        at 2200 degC.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Split hydrogen on a hot tungsten filament",
        EQUIPPED_LAB,
        Pressure64(30, TORR),
        Temperature64(1500),
        Temperature64(4000),
        _celsius(2200),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction(
                [
                    reactant(hydrogen(), 1, 1 - _ATOMIC_H),
                    product(atomic_hydrogen(), 2, _ATOMIC_H),
                ]
            ),
            "The filament must split hydrogen to 1 % atoms at equilibrium.",
        )
    )
    step.add(
        below(
            ENGINEERING,
            _celsius(3422),
            "Tungsten melts at 3422 degC. Stay far below to limit sag.",
            "melting point from the CRC Handbook",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Carburize a new filament in the process gas before growth."
                " A tungsten filament takes up carbon and turns brittle."
            ),
            "hot-filament practice",
        )
    )
    step.add_hazard(ELECTRICAL)
    step.add_hazard(FLAMMABLE_GAS)
    step.add_hazard(BURN)
    return step^


def bismuth_crystals() raises -> Step:
    """Return hopper crystals grown from a bismuth melt.

    Returns:
        The step: a steel pan on a hot plate, in air.

    Raises:
        Error: Never. The bounds are checked as they are built.
    """
    var step = Step(
        "Grow bismuth hopper crystals from a melt",
        HOME_WORKSHOP,
        Pressure64(1, ATMOSPHERE),
        Temperature64(300),
        Temperature64(900),
        _celsius(300),
    )
    step.add(
        above(
            PHASE,
            _celsius(271.4),
            "Bismuth must melt. TM-4513 has no bismuth data.",
            "melting point from the CRC Handbook: 271.4 degC",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Buy pure bismuth, not a low-melting alloy. Some of those"
                " hold lead or cadmium."
            ),
            "material safety",
        )
    )
    step.add(
        action(
            ENGINEERING,
            "Use a dry steel pan. Water on molten metal flashes to steam.",
            "foundry practice",
        )
    )
    step.add(
        action(
            KINETIC,
            (
                "Cool slowly without stirring. Crystal edges grow faster than"
                " faces, which makes the stepped hopper shape."
            ),
            "crystal growth",
        )
    )
    step.add(
        action(
            KINETIC,
            (
                "Pour off the liquid when crystals form under the skin, or"
                " the melt freezes around them."
            ),
            "hobby practice",
        )
    )
    step.add(
        action(
            PHYSICAL,
            (
                "Let the crystals cool in air. A thin oxide film forms, and"
                " its thickness sets the interference color."
            ),
            "thin-film optics",
        )
    )
    step.add_hazard(BURN)
    return step^


def lime_burning() raises -> Step:
    """Return the burning of limestone to quicklime.

    Returns:
        The step: a kiln at one atmosphere, planned at 900 degC.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var step = Step(
        "Burn limestone to quicklime",
        HOME_WORKSHOP,
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
                "Keep quicklime dry and off the skin. With water it heats"
                " strongly and forms caustic slaked lime."
            ),
            "material safety",
        )
    )
    step.add_hazard(BURN)
    step.add_hazard(CORROSIVE)
    return step^
