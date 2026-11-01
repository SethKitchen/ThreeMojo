# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print the requirements and operating windows of the process recipes.

    mojo run -I . tools/process_report.mojo [titanium|diamond|bismuth|lime]

With no name, the tool prints every recipe. Each step gives its setting,
its hazards, its operating window, and each requirement at the planned
temperature. The titanium recipe adds the magnesium and the heat per
kilogram of titanium. The diamond recipe adds the residual stress of the
coating and the thickest coating that does not peel. The lime recipe adds
a ledger.

The fracture energy and the prices are example inputs, not data. Replace
them with measured values and quotes. See the wiki page Process chemistry.
"""

from std.sys import argv, exit, stderr

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
from extensions.chemistry.economics import (
    EnergyPrice64,
    Ledger,
    StreamItem,
    UnitPrice64,
    heat_duty,
)
from extensions.chemistry.process import report
from extensions.chemistry.quantities import (
    FractureEnergy64,
    MICROMETER,
    amount_of,
)
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.recipes import (
    CEMENTED_CARBIDE,
    CVD_DIAMOND,
    bismuth_crystals,
    diamond_coating,
    hydrogen_filament,
    kroll_route,
    lime_burning,
)
from loaders.js_number import js_to_fixed
from units.si import GIGAPASCAL, KILOGRAM, KILOWATT_HOUR, Mass64
from units.temperature import CELSIUS, Temperature64

# Example inputs. They are not market data or measurements.
comptime _TOUGHNESS = 30.0
comptime _LIMESTONE_PRICE = 0.10
comptime _QUICKLIME_PRICE = 0.40
comptime _ELECTRICITY_PRICE = 0.15
comptime _KILN_EFFICIENCY = 0.25


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
    """Print the diamond recipe, then the coating's stress and limit."""
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
    """Print the lime recipe, then the heat and a ledger for one kg."""
    print(report(lime_burning()))
    var n = amount_of(Mass64(1, KILOGRAM), calcite().molar_mass())
    var feed = List[StreamItem]()
    feed.append(StreamItem(calcite(), n, Temperature64(298.15)))
    var out = List[StreamItem]()
    var hot = Temperature64(900, CELSIUS)
    out.append(StreamItem(lime(), n, hot))
    out.append(StreamItem(carbon_dioxide(), n, hot))
    var duty = heat_duty(feed, out)
    var quicklime = lime().molar_mass().times(n)
    var book = Ledger()
    book.buy(Mass64(1, KILOGRAM), UnitPrice64(_LIMESTONE_PRICE))
    book.heat(
        duty,
        EnergyPrice64.per_kilowatt_hour(_ELECTRICITY_PRICE),
        _KILN_EFFICIENCY,
    )
    book.sell(quicklime, UnitPrice64(_QUICKLIME_PRICE))
    print("Per kilogram of limestone, with example prices:")
    print("  Heat duty:", js_to_fixed(duty.to(KILOWATT_HOUR), 3), "kWh")
    print("  Quicklime:", js_to_fixed(quicklime.to(KILOGRAM), 3), "kg")
    print("  Margin:", js_to_fixed(book.margin().value, 3), "\n")


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
    if name == "all" or name == "bismuth":
        print(report(bismuth_crystals()))
        known = True
    if name == "all" or name == "lime":
        _lime()
        known = True
    if not known:
        print("Name a recipe: titanium, diamond, bismuth or lime.", file=stderr)
        exit(2)
