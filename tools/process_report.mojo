# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print the requirements and operating windows of the worked processes.

    mojo run -I . tools/process_report.mojo [titanium|diamond|lime|hpht|mpcvd]

With no name, the tool prints every process. Each step gives its hazards,
its pressure, its operating window, and each requirement at the planned
temperature. The titanium process adds the magnesium and the heat duty
per kilogram of titanium. The diamond process adds the residual stress of
the coating and the thickest coating that does not peel, for an example
interface fracture energy. The lime process adds its heat duty. The
two processes that grow diamond crystals, `hpht` and `mpcvd`, add the
cost of an example run per kept carat, at an example electricity price.

See the wiki page Process chemistry.
"""

from std.sys import argv, exit, stderr

from extensions.chemistry.balance import StreamItem, heat_duty
from extensions.chemistry.catalog import (
    calcite,
    carbon_dioxide,
    lime,
    magnesium,
    magnesium_chloride,
    titanium,
    titanium_tetrachloride,
)
from extensions.chemistry.coating import (
    delamination_thickness,
    mismatch_stress,
)
from extensions.chemistry.processes.diamond import (
    CEMENTED_CARBIDE,
    CVD_DIAMOND,
    diamond_coating,
    hydrogen_filament,
)
from extensions.chemistry.processes.hpht import hpht_growth, hpht_run
from extensions.chemistry.processes.lime import lime_burning
from extensions.chemistry.processes.mpcvd import (
    mpcvd_run,
    plasma_hydrogen,
    seed_growth,
)
from extensions.chemistry.production import (
    EnergyPrice64,
    PER_KILOWATT_HOUR,
    cost_report,
)
from extensions.chemistry.processes.titanium import kroll_route
from extensions.chemistry.quantities import (
    FractureEnergy64,
    MICROMETER,
    amount_of,
)
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.step import report
from loaders.js_number import js_to_fixed
from units.si import GIGAPASCAL, KILOGRAM, KILOWATT_HOUR, Mass64
from units.temperature import CELSIUS, Temperature64

# An example interface fracture energy, J/m^2. Measure it on the surface.
comptime _TOUGHNESS = 30.0
# An example price of electric energy, per kWh, in any currency.
comptime _ELECTRICITY = 0.10


def _titanium() raises:
    """Print the Kroll route, then its magnesium and heat per kg of Ti."""
    for step in kroll_route():
        print(report(step))
    var reduction = Reaction(
        [
            reactant(titanium_tetrachloride()),
            reactant(magnesium(), 2),
            product(titanium()),
            product(magnesium_chloride(), 2),
        ]
    )
    var ti = amount_of(Mass64(1, KILOGRAM), titanium().molar_mass())
    # The TiCl4 data starts at 300 K, so the feed enters at 300 K.
    var room = Temperature64(300)
    var feed = List[StreamItem]()
    feed.append(StreamItem(titanium_tetrachloride(), ti, room))
    feed.append(StreamItem(magnesium(), ti.scaled(2), room))
    var out = List[StreamItem]()
    var hot = Temperature64(850, CELSIUS)
    out.append(StreamItem(titanium(), ti, hot))
    out.append(StreamItem(magnesium_chloride(), ti.scaled(2), hot))
    var duty = heat_duty(feed, out)
    print("Per kilogram of titanium sponge:")
    print(
        "  Magnesium:",
        js_to_fixed(reduction.mass_ratio(magnesium(), titanium()), 3),
        "kg",
    )
    print(
        "  Heat duty, feed at 300 K to products at 850 degC:",
        js_to_fixed(duty.to(KILOWATT_HOUR), 2),
        "kWh. Below zero, the retort must shed this heat.\n",
    )


def _diamond() raises:
    """Print the diamond process, then the coating's stress and limit."""
    print(report(diamond_coating()))
    print(report(hydrogen_filament()))
    var stress = mismatch_stress(
        CVD_DIAMOND,
        CEMENTED_CARBIDE,
        Temperature64(850, CELSIUS),
        Temperature64(20, CELSIUS),
    )
    var limit = delamination_thickness(
        CVD_DIAMOND, stress, FractureEnergy64(_TOUGHNESS)
    )
    print("Diamond on cemented carbide, cooled from 850 to 20 degC:")
    print(
        "  Residual stress:",
        js_to_fixed(stress.to(GIGAPASCAL), 2),
        "GPa, compressive",
    )
    print(
        "  Thickest coating that does not peel, at an example 30 J/m^2:",
        js_to_fixed(limit.to(MICROMETER), 1),
        "micrometers\n",
    )


def _lime() raises:
    """Print the lime process, then its heat duty per kg of limestone."""
    print(report(lime_burning()))
    var n = amount_of(Mass64(1, KILOGRAM), calcite().molar_mass())
    var feed = List[StreamItem]()
    feed.append(StreamItem(calcite(), n, Temperature64(298.15)))
    var out = List[StreamItem]()
    var hot = Temperature64(900, CELSIUS)
    out.append(StreamItem(lime(), n, hot))
    out.append(StreamItem(carbon_dioxide(), n, hot))
    var duty = heat_duty(feed, out)
    print("Per kilogram of limestone, from 25 degC to 900 degC:")
    print("  Heat duty:", js_to_fixed(duty.to(KILOWATT_HOUR), 3), "kWh")
    print(
        "  Quicklime:",
        js_to_fixed(lime().molar_mass().times(n).to(KILOGRAM), 3),
        "kg\n",
    )


def _hpht() raises:
    """Print the HPHT growth step, then the cost of an example run."""
    print(report(hpht_growth()))
    print(
        cost_report(hpht_run(), EnergyPrice64(_ELECTRICITY, PER_KILOWATT_HOUR))
    )


def _mpcvd() raises:
    """Print the plasma CVD steps, then the cost of an example run."""
    print(report(seed_growth()))
    print(report(plasma_hydrogen()))
    print(
        cost_report(mpcvd_run(), EnergyPrice64(_ELECTRICITY, PER_KILOWATT_HOUR))
    )


def main() raises:
    var name = String("all")
    if len(argv()) > 1:
        name = String(argv()[1])
    var known = False
    if name == "all" or name == "titanium":
        _titanium()
        known = True
    if name == "all" or name == "diamond":
        _diamond()
        known = True
    if name == "all" or name == "lime":
        _lime()
        known = True
    if name == "all" or name == "hpht":
        _hpht()
        known = True
    if name == "all" or name == "mpcvd":
        _mpcvd()
        known = True
    if not known:
        print(
            "Name a process: titanium, diamond, lime, hpht or mpcvd.",
            file=stderr,
        )
        exit(2)
