# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Single-crystal diamond grown on seeds by microwave plasma CVD.

A microwave plasma in hydrogen with a few percent of methane sits over a
plate of diamond seeds. The plasma splits hydrogen into atoms. The atoms
take hydrogen off the seed's surface and etch graphite faster than
diamond, so methyl radicals add to the seed's lattice and the seed grows
as one crystal. Diamond is metastable at 200 Torr, as in a hot-filament
coating: see `processes.diamond`.

The plasma runs at 100 to 300 Torr, much denser than a hot filament, so
it splits more hydrogen and the crystal grows faster. A little nitrogen
raises the rate again. Each grown layer is cut off its seed, and the seed
grows again, so one seed serves many runs.

`plasma_hydrogen` is the plasma's core, where hydrogen splits. A
microwave plasma is not at equilibrium, so its window is a lower bound on
the gas temperature, not a prediction of it.
"""

from extensions.chemistry.catalog import (
    atomic_hydrogen,
    diamond,
    graphite,
    hydrogen,
    methane,
)
from extensions.chemistry.kinds import (
    BURN,
    ELECTRICAL,
    ENGINEERING,
    FLAMMABLE_GAS,
    KINETIC,
    PHYSICAL,
    PRESSURE_VESSEL,
    THERMODYNAMIC,
)
from extensions.chemistry.production import (
    GrowthRun,
    MICROMETER_PER_HOUR,
    Money64,
    PER_HOUR,
    TimePrice64,
    layer_rate,
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
from units.si import (
    Area64,
    Duration64,
    HOUR,
    KILOWATT,
    Power64,
    Pressure64,
    Velocity64,
)
from units.temperature import CELSIUS, Temperature64

# The methane fraction of the feed gas.
comptime SEED_METHANE_FRACTION = 0.06
# The atomic hydrogen fraction the plasma core must reach at equilibrium.
comptime PLASMA_HYDROGEN_FRACTION = 0.05
# The source of the stated bounds of the seed step.
comptime _HEMLEY = (
    "Hemley et al., US patent 7452420: about 700 to 1200 degC at 100 to"
    " 300 Torr"
)


def _plasma_pressure() -> Pressure64:
    """Return the pressure of the worked steps: 200 Torr."""
    return Pressure64(200, TORR)


def seed_growth() raises -> Step:
    """Return single-crystal growth on diamond seeds in a microwave plasma.

    Returns:
        The seed step: 6 % methane in hydrogen at 200 Torr, with the
        seeds at 1000 degC.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Grow single-crystal diamond on seeds in a microwave plasma",
        _plasma_pressure(),
        Temperature64(800),
        Temperature64(1700),
        Temperature64(1000, CELSIUS),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction(
                [
                    reactant(methane(), 1, SEED_METHANE_FRACTION),
                    product(diamond()),
                    product(hydrogen(), 2, 1 - SEED_METHANE_FRACTION),
                ]
            ),
            "Methane must be able to deposit diamond on the seeds.",
        )
    )
    step.add(
        above(
            KINETIC,
            Temperature64(700, CELSIUS),
            "Colder, the crystal grows slowly and takes up defects.",
            _HEMLEY,
        )
    )
    step.add(
        below(
            KINETIC,
            Temperature64(1200, CELSIUS),
            "Hotter, the crystal takes up non-diamond carbon and twins.",
            _HEMLEY,
        )
    )
    step.add(
        pressure_above(
            PHYSICAL,
            Pressure64(100, TORR),
            "The plasma must be dense, to split hydrogen for a fast rate.",
            _HEMLEY,
        )
    )
    step.add(
        pressure_below(
            PHYSICAL,
            Pressure64(300, TORR),
            "The plasma must stay stable over the seeds.",
            _HEMLEY,
        )
    )
    step.add(
        action(
            KINETIC,
            (
                "Add nitrogen at about 3 % of the methane to grow faster."
                " Nitrogen colors the crystal brown, so leave it out for"
                " the purest crystals."
            ),
            "Yan et al. (2002), PNAS 99, 12523: 50 to 150 um/h",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Polish the (100) faces of the seeds, then etch them in the"
                " hydrogen plasma before growth. Damage from polishing"
                " grows into defects."
            ),
            "single-crystal CVD practice",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Cut the grown layer off its seed with a laser and polish"
                " the seed again, so that one seed serves many runs."
            ),
            "single-crystal CVD practice",
        )
    )
    step.add_fact(Reaction([reactant(graphite()), product(diamond())]))
    step.add_fact(
        Reaction(
            [
                reactant(methane(), 1, SEED_METHANE_FRACTION),
                product(graphite()),
                product(hydrogen(), 2, 1 - SEED_METHANE_FRACTION),
            ]
        )
    )
    step.add_hazard(FLAMMABLE_GAS)
    step.add_hazard(ELECTRICAL)
    step.add_hazard(PRESSURE_VESSEL)
    step.add_hazard(BURN)
    return step^


def plasma_hydrogen() raises -> Step:
    """Return the core of the plasma, where hydrogen splits into atoms.

    Returns:
        The plasma step: the same gas at 200 Torr, planned at a gas
        temperature of 3000 K.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Split hydrogen in the core of a microwave plasma",
        _plasma_pressure(),
        Temperature64(1500),
        Temperature64(5000),
        Temperature64(3000),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction(
                [
                    reactant(hydrogen(), 1, 1 - PLASMA_HYDROGEN_FRACTION),
                    product(atomic_hydrogen(), 2, PLASMA_HYDROGEN_FRACTION),
                ]
            ),
            "The plasma must split hydrogen to 5 % atoms at equilibrium.",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Keep the plasma off the quartz window and the walls. A"
                " plasma that touches them etches them, and silicon gets"
                " into the crystal."
            ),
            "microwave plasma CVD practice",
        )
    )
    step.add_hazard(ELECTRICAL)
    step.add_hazard(FLAMMABLE_GAS)
    step.add_hazard(BURN)
    return step^


def mpcvd_run() raises -> GrowthRun:
    """Return an example batch of a microwave plasma reactor.

    The numbers are an example for the cost model, not a quote. Use the
    measured rates and the prices of a real plant.

    Returns:
        Thirty 7 mm square seeds that thicken at 10 um/h for 400 h, with
        24 h of turnaround at 6 kW. 30 % of the grown mass is kept after
        cutting. The consumables are 400 a run and an hour of the
        reactor is 4.

    Raises:
        Error: Never. The values are checked as they are built.
    """
    var side = 7.0e-3
    return GrowthRun(
        "Microwave plasma reactor, 30 seeds (example numbers)",
        Duration64(400, HOUR),
        Duration64(24, HOUR),
        Power64(6, KILOWATT),
        30,
        layer_rate(Velocity64(10, MICROMETER_PER_HOUR), Area64(side * side)),
        0.3,
        Money64(400),
        TimePrice64(4, PER_HOUR),
    )
