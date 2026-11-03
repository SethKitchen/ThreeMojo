# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A diamond coating on a cemented carbide tool, by hot-filament CVD.

Two steps share one gas, 1 % methane in hydrogen at 30 Torr: the
substrate where diamond grows, and the filament that splits hydrogen into
atoms. Diamond is metastable here. Atomic hydrogen etches graphite faster
than diamond, so the diamond survives. `CVD_DIAMOND` and
`CEMENTED_CARBIDE` hold typical elastic and thermal properties for the
coating mechanics in `extensions.chemistry.coating`.
"""

from extensions.chemistry.catalog import (
    atomic_hydrogen,
    diamond,
    graphite,
    hydrogen,
    methane,
)
from extensions.chemistry.coating import ElasticLayer
from extensions.chemistry.kinds import (
    BURN,
    CORROSIVE,
    ELECTRICAL,
    ENGINEERING,
    FLAMMABLE_GAS,
    KINETIC,
    PHYSICAL,
    PRESSURE_VESSEL,
    THERMODYNAMIC,
)
from extensions.chemistry.quantities import TORR
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.requirement import (
    above,
    action,
    below,
    pressure_above,
    pressure_below,
    proceeds,
)
from extensions.chemistry.step import Step
from units.si import Pressure64, ThermalExpansion64
from units.temperature import CELSIUS, Temperature64

# The methane fraction of a hot-filament feed gas.
comptime METHANE_FRACTION = 0.01
# The atomic hydrogen fraction a filament must reach at equilibrium.
comptime ATOMIC_HYDROGEN_FRACTION = 0.01

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
                    reactant(methane(), 1, METHANE_FRACTION),
                    product(diamond()),
                    product(hydrogen(), 2, 1 - METHANE_FRACTION),
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
                reactant(methane(), 1, METHANE_FRACTION),
                product(graphite()),
                product(hydrogen(), 2, 1 - METHANE_FRACTION),
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
                    reactant(hydrogen(), 1, 1 - ATOMIC_HYDROGEN_FRACTION),
                    product(atomic_hydrogen(), 2, ATOMIC_HYDROGEN_FRACTION),
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
