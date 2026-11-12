# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Diamond crystals from graphite at high pressure and high temperature.

The temperature-gradient method of Wentorf (1971) grows single crystals
in a press. A cell holds a carbon source at its hot end, diamond seeds at
its cold end, and a metal solvent between them. At the working pressure
the solvent melts and dissolves the carbon. The carbon moves down the
gradient and grows on the seeds as diamond, because there the melt holds
more carbon than diamond can stay dissolved beside.

The window has two stated bounds. The solvent must melt: the Fe-Ni-C
eutectic is about 1665 K at 5.7 GPa. Diamond must be the stable form of
carbon: the step must stay below the graphite-diamond line of Kennedy and
Kennedy (1976), 1504 degC at 5.7 GPa. `graphite_temperature` and
`diamond_pressure` give that line.

The built-in data puts the line far too hot: graphite and diamond balance
near 2625 K at 5.7 GPa in that data. The data takes the two heat
capacities as equal and the solids as incompressible. So the step states
the measured line, and keeps the computed reaction as a check of its
sign.
"""

from extensions.chemistry.catalog import diamond, graphite
from extensions.chemistry.kinds import (
    BURN,
    ELECTRICAL,
    ENGINEERING,
    KINETIC,
    PHASE,
    PRESSURE_VESSEL,
    THERMODYNAMIC,
)
from extensions.chemistry.production import (
    GrowthRun,
    MILLIGRAM_PER_HOUR,
    MassRate64,
    Money64,
    PER_HOUR,
    TimePrice64,
)
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.requirement import above, action, below, proceeds
from extensions.chemistry.step import Step
from std.math import isfinite
from units.si import Duration64, HOUR, KILOWATT, Power64, Pressure64
from units.temperature import CELSIUS, Temperature64

# The graphite-diamond line of Kennedy and Kennedy (1976):
# P = 19.4 kbar + T / 40 kbar per degC, measured from 1100 to 1625 degC.
comptime KENNEDY_INTERCEPT = Pressure64(1.94e9)
# 1/40 kbar per kelvin is 2.5 MPa per kelvin.
comptime KENNEDY_SLOPE = 2.5e6
comptime KENNEDY_LOW = 1100.0
comptime KENNEDY_HIGH = 1625.0
comptime _ZERO_CELSIUS = 273.15

# The pressure of the worked step: the pressure of the Fe-Ni-C diagram.
comptime HPHT_PRESSURE = Pressure64(5.7e9)
# The Fe-Ni-C eutectic near 63Fe-18Ni-19C (atomic %) at 5.7 GPa.
comptime FE_NI_EUTECTIC = Temperature64(1665)


def diamond_pressure(temperature: Temperature64) raises -> Pressure64:
    """Return the pressure where graphite and diamond balance.

    Above this pressure diamond is the stable form of carbon.

    Args:
        temperature: The temperature, 1100 to 1625 degC, where Kennedy
            and Kennedy measured the line.

    Returns:
        The pressure on the line.

    Raises:
        Error: If the temperature is outside the measured range.
    """
    var celsius = temperature.kelvin - _ZERO_CELSIUS
    if not (celsius >= KENNEDY_LOW and celsius <= KENNEDY_HIGH):
        raise Error("The graphite-diamond line is measured at 1100-1625 degC")
    return Pressure64(KENNEDY_INTERCEPT.value + KENNEDY_SLOPE * celsius)


def graphite_temperature(pressure: Pressure64) raises -> Temperature64:
    """Return the temperature where graphite and diamond balance.

    Below this temperature diamond is the stable form of carbon.

    Args:
        pressure: The pressure, 4.69 to 6.0025 GPa, the measured range
            of the line.

    Returns:
        The temperature on the line.

    Raises:
        Error: If the pressure is not finite, or the line at that
            pressure is outside the measured range.
    """
    if not isfinite(pressure.value):
        raise Error("A pressure must be finite")
    var celsius = (pressure.value - KENNEDY_INTERCEPT.value) / KENNEDY_SLOPE
    if not (celsius >= KENNEDY_LOW and celsius <= KENNEDY_HIGH):
        raise Error("The graphite-diamond line is measured at 4.69-6.0 GPa")
    return Temperature64(celsius + _ZERO_CELSIUS)


def hpht_growth() raises -> Step:
    """Return diamond growth on seeds from a molten Fe-Ni solvent.

    Returns:
        The step at 5.7 GPa, planned at 1450 degC: between the melting
        of the solvent and the graphite-diamond line.

    Raises:
        Error: Never. The data and bounds are checked as they are built.
    """
    var step = Step(
        "Grow diamond on seeds from carbon in a molten Fe-Ni solvent",
        HPHT_PRESSURE,
        Temperature64(1300),
        Temperature64(2200),
        Temperature64(1450, CELSIUS),
    )
    step.add(
        proceeds(
            THERMODYNAMIC,
            Reaction([reactant(graphite()), product(diamond())]),
            "Graphite must be able to turn to diamond at this pressure.",
        )
    )
    step.add(
        below(
            THERMODYNAMIC,
            graphite_temperature(HPHT_PRESSURE),
            (
                "Diamond must stay the stable form of carbon. Hotter, the"
                " carbon grows as graphite."
            ),
            (
                "Kennedy and Kennedy (1976), J. Geophys. Res. 81, 2467:"
                " P = 19.4 kbar + T / 40 kbar per degC"
            ),
        )
    )
    step.add(
        above(
            PHASE,
            FE_NI_EUTECTIC,
            (
                "The Fe-Ni solvent must melt, to dissolve the carbon and"
                " carry it to the seeds."
            ),
            (
                "Fe-Ni-C eutectic at 5.7 GPa, about 1665 K: Pavel et al."
                " (1991), OSTI 5278513"
            ),
        )
    )
    step.add(
        action(
            KINETIC,
            (
                "Keep the carbon source a few tens of kelvin hotter than the"
                " seeds. The gradient moves the carbon to the seeds."
            ),
            "temperature-gradient method: Wentorf (1971), J. Phys. Chem. 75",
        )
    )
    step.add(
        action(
            KINETIC,
            (
                "Grow slowly. A crystal that grows too fast traps the solvent"
                " as metal inclusions."
            ),
            "Strong and Chrenko (1971), J. Phys. Chem. 75",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Add aluminum or titanium to the solvent. They take up"
                " nitrogen, so the crystals grow colorless."
            ),
            "Strong and Chrenko (1971), J. Phys. Chem. 75",
        )
    )
    step.add(
        action(
            ENGINEERING,
            (
                "Set the temperature by the heater power after a calibration"
                " run. A thermocouple does not survive in each cell."
            ),
            "large-volume press practice",
        )
    )
    step.add_fact(Reaction([reactant(graphite()), product(diamond())]))
    step.add_hazard(PRESSURE_VESSEL)
    step.add_hazard(BURN)
    step.add_hazard(ELECTRICAL)
    return step^


def hpht_run() raises -> GrowthRun:
    """Return an example batch of a temperature-gradient press.

    The numbers are an example for the cost model, not a quote. Use the
    measured rates and the prices of a real plant.

    Returns:
        Twelve seeds that grow at 3 mg/h each for 60 h, with 4 h of
        turnaround at 15 kW. 35 % of the grown mass is kept after
        cutting. The consumables are 150 a run and an hour of the press
        is 8.

    Raises:
        Error: Never. The values are checked as they are built.
    """
    return GrowthRun(
        "Temperature-gradient press, 12 seeds (example numbers)",
        Duration64(60, HOUR),
        Duration64(4, HOUR),
        Power64(15, KILOWATT),
        12,
        MassRate64(3, MILLIGRAM_PER_HOUR),
        0.35,
        Money64(150),
        TimePrice64(8, PER_HOUR),
    )
