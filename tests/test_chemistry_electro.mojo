# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the electrochemistry and thin-film optics of
`extensions.chemistry`.

References:

- Water decomposes at 1.229 V at 25 degC, with a thermoneutral voltage
  of 1.481 V.
- Aluminum smelting with a carbon anode has a reversible voltage near
  1.18 V to 1.20 V at 960 degC, and about 2.2 V without carbon.
- Magnesium chloride electrolysis needs about 2.5 V at 700 degC.
- Smelters use about 13 to 15 kWh per kilogram of aluminum at about
  4.2 V and 95 % current efficiency.
- CIE 1931: y-bar(555 nm) = 1.000, x-bar(600 nm) = 1.062, y-bar(600 nm)
  = 0.631, and the three functions have equal integrals.
- A quarter-wave film of index sqrt(n) on a substrate of index n
  reflects nothing at its design wavelength.
"""

from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import (
    alumina,
    aluminum,
    carbon_dioxide,
    chlorine,
    graphite,
    hydrogen,
    magnesium,
    magnesium_chloride,
    oxygen,
    water,
)
from extensions.chemistry.electrochemistry import (
    CellVoltage,
    Current64,
    FARADAY,
    KILOWATT_HOUR_PER_KILOGRAM,
    Voltage64,
    decomposition_voltage,
    faraday_mass,
    faraday_time,
    reversible_voltage,
    specific_energy,
    thermoneutral_voltage,
)
from extensions.chemistry.optics import (
    ComplexIndex,
    Tristimulus,
    anodic_thickness,
    color_matching,
    film_color,
    film_reflectance,
    linear_srgb,
)
from extensions.chemistry.quantities import GRAM_PER_MOLE, MolarMass64
from extensions.chemistry.reaction import Reaction, product, reactant
from units.si import Duration64, HOUR, Length64, Mass64, NANOMETER, Pressure64
from units.temperature import CELSIUS, Temperature64

comptime NAN = nan[DType.float64]()
comptime ATM = 101325.0


def _al() -> MolarMass64:
    return MolarMass64(26.982, GRAM_PER_MOLE)


def test_water_electrolysis() raises:
    var t = Temperature64(298.15)
    var split = Reaction(
        [reactant(water()), product(hydrogen()), product(oxygen(), 0.5)]
    )
    var e = decomposition_voltage(split, 2, t, Pressure64(1e5))
    assert_almost_equal(e.value, 1.229, atol=0.002)
    assert_almost_equal(
        thermoneutral_voltage(split, 2, t).value, 1.481, atol=0.002
    )
    # The reverse runs by itself: a fuel cell.
    var cell = Reaction(
        [reactant(hydrogen()), reactant(oxygen(), 0.5), product(water())]
    )
    assert_almost_equal(
        reversible_voltage(cell, 2, t, Pressure64(1e5)).value,
        e.value,
        atol=1e-12,
    )
    with assert_raises(contains="electron count"):
        _ = reversible_voltage(cell, 0, t, Pressure64(1e5))
    with assert_raises(contains="electron count"):
        _ = thermoneutral_voltage(cell, NAN, t)


def test_metal_electrolysis() raises:
    var p = Pressure64(ATM)
    var smelt = Reaction(
        [
            reactant(alumina(), 0.5),
            reactant(graphite(), 0.75),
            product(aluminum()),
            product(carbon_dioxide(), 0.75),
        ]
    )
    var hot = Temperature64(960, CELSIUS)
    var e = decomposition_voltage(smelt, 3, hot, p)
    assert_true(e.value > 1.17 and e.value < 1.21)
    var bare = Reaction(
        [reactant(alumina(), 0.5), product(aluminum()), product(oxygen(), 0.75)]
    )
    assert_almost_equal(
        decomposition_voltage(bare, 3, hot, p).value, 2.2, atol=0.05
    )
    var chloride = Reaction(
        [
            reactant(magnesium_chloride()),
            product(magnesium()),
            product(chlorine()),
        ]
    )
    var mg = decomposition_voltage(chloride, 2, Temperature64(700, CELSIUS), p)
    assert_almost_equal(mg.value, 2.5, atol=0.05)


def test_faraday() raises:
    # One faraday frees one mole of a one-electron product.
    var m = faraday_mass(Current64(FARADAY), Duration64(1), MolarMass64(0.1), 1)
    assert_almost_equal(m.value, 0.1, atol=1e-12)
    var al = faraday_mass(
        Current64(100000), Duration64(1, HOUR), _al(), 3, 0.95
    )
    assert_almost_equal(
        al.value, 100000 * 3600 * 0.95 * 0.026982 / (3 * FARADAY), atol=1e-9
    )
    var t = faraday_time(al, Current64(100000), _al(), 3, 0.95)
    assert_almost_equal(t.to(HOUR), 1.0, atol=1e-9)
    with assert_raises(contains="finite, not negative"):
        _ = faraday_mass(Current64(-1), Duration64(1), _al(), 3)
    with assert_raises(contains="finite, not negative"):
        _ = faraday_mass(Current64(1), Duration64(NAN), _al(), 3)
    with assert_raises(contains="molar mass"):
        _ = faraday_mass(Current64(1), Duration64(1), MolarMass64(0), 3)
    with assert_raises(contains="molar mass"):
        _ = faraday_mass(Current64(1), Duration64(1), MolarMass64(NAN), 3)
    with assert_raises(contains="current efficiency"):
        _ = faraday_mass(Current64(1), Duration64(1), _al(), 3, 0)
    with assert_raises(contains="current efficiency"):
        _ = faraday_mass(Current64(1), Duration64(1), _al(), 3, 1.2)
    with assert_raises(contains="mass must be"):
        _ = faraday_time(Mass64(-1), Current64(1), _al(), 3)
    with assert_raises(contains="mass must be"):
        _ = faraday_time(Mass64(NAN), Current64(1), _al(), 3)
    with assert_raises(contains="current must be"):
        _ = faraday_time(Mass64(1), Current64(0), _al(), 3)
    with assert_raises(contains="current must be"):
        _ = faraday_time(Mass64(1), Current64(inf[DType.float64]()), _al(), 3)


def test_cell_voltage_and_energy() raises:
    var cell = CellVoltage(
        Voltage64(1.2), Voltage64(0.5), Voltage64(0.1), Voltage64(2.4)
    )
    assert_almost_equal(cell.total().value, 4.2, atol=1e-12)
    var energy = specific_energy(cell.total(), _al(), 3, 0.95)
    var kwh = energy.to(KILOWATT_HOUR_PER_KILOGRAM)
    assert_true(kwh > 13 and kwh < 15)
    with assert_raises(contains="loss must be"):
        _ = CellVoltage(
            Voltage64(1), Voltage64(-1), Voltage64(0), Voltage64(0)
        ).total()
    with assert_raises(contains="loss must be"):
        _ = CellVoltage(
            Voltage64(1), Voltage64(0), Voltage64(0), Voltage64(NAN)
        ).total()
    with assert_raises(contains="reversible voltage"):
        _ = CellVoltage(
            Voltage64(NAN), Voltage64(0), Voltage64(0), Voltage64(0)
        ).total()
    with assert_raises(contains="cell voltage"):
        _ = specific_energy(Voltage64(-1), _al(), 3)
    with assert_raises(contains="cell voltage"):
        _ = specific_energy(Voltage64(NAN), _al(), 3)
    with assert_raises(contains="molar mass"):
        _ = specific_energy(Voltage64(1), MolarMass64(0), 3)
    with assert_raises(contains="molar mass"):
        _ = specific_energy(Voltage64(1), MolarMass64(NAN), 3)


# --- thin films -------------------------------------------------------------


def test_color_matching_functions() raises:
    assert_almost_equal(color_matching(555).y, 1.0, atol=0.01)
    assert_almost_equal(color_matching(600).x, 1.062, atol=0.01)
    assert_almost_equal(color_matching(600).y, 0.631, atol=0.01)
    # A flat reflector looks equal-energy white: X = Y = Z.
    var white = film_color(Length64(0), 1, ComplexIndex(1e9, 0))
    assert_almost_equal(white.y, 1.0, atol=1e-6)
    assert_almost_equal(white.x, 1.0, atol=0.01)
    assert_almost_equal(white.z, 1.0, atol=0.01)
    var rgb = linear_srgb(Tristimulus(0.95047, 1.0, 1.08883))
    assert_almost_equal(rgb[0], 1.0, atol=1e-3)
    assert_almost_equal(rgb[1], 1.0, atol=1e-3)
    assert_almost_equal(rgb[2], 1.0, atol=1e-3)


def test_film_reflectance() raises:
    var wave = Length64(550, NANOMETER)
    var glass = ComplexIndex(2.25, 0)
    # A quarter-wave film of index sqrt(2.25) reflects nothing.
    var quarter = Length64(550.0 / (4 * 1.5), NANOMETER)
    assert_almost_equal(
        film_reflectance(quarter, 1.5, glass, wave), 0.0, atol=1e-12
    )
    # A half-wave film is absent: the bare substrate's reflectance.
    var bare = ((1 - 2.25) / (1 + 2.25)) ** 2
    var half = Length64(550.0 / (2 * 1.5), NANOMETER)
    assert_almost_equal(
        film_reflectance(half, 1.5, glass, wave), bare, atol=1e-12
    )
    # A metal: |(1 - N) / (1 + N)|^2 with N = n + i k.
    var metal = ComplexIndex(2.0, 3.0)
    var expected = ((1 - 2.0) ** 2 + 9.0) / ((1 + 2.0) ** 2 + 9.0)
    assert_almost_equal(
        film_reflectance(Length64(0), 2.5, metal, wave), expected, atol=1e-12
    )
    # A film shifts the color away from the bare metal's.
    var colored = film_color(Length64(60, NANOMETER), 2.5, metal)
    var plain = film_color(Length64(0), 2.5, metal)
    assert_true(
        abs(colored.x - plain.x) > 0.01 or abs(colored.z - plain.z) > 0.01
    )
    with assert_raises(contains="thickness must be"):
        _ = film_reflectance(Length64(-1), 1.5, glass, wave)
    with assert_raises(contains="thickness must be"):
        _ = film_reflectance(Length64(NAN), 1.5, glass, wave)
    with assert_raises(contains="film index"):
        _ = film_reflectance(quarter, 0.5, glass, wave)
    with assert_raises(contains="film index"):
        _ = film_reflectance(quarter, NAN, glass, wave)
    with assert_raises(contains="substrate index"):
        _ = film_reflectance(quarter, 1.5, ComplexIndex(-1, 0), wave)
    with assert_raises(contains="substrate index"):
        _ = film_reflectance(quarter, 1.5, ComplexIndex(1, -1), wave)
    with assert_raises(contains="wavelength"):
        _ = film_reflectance(quarter, 1.5, glass, Length64(0))
    with assert_raises(contains="wavelength"):
        _ = film_reflectance(quarter, 1.5, glass, Length64(NAN))


def test_anodic_thickness() raises:
    var t = anodic_thickness(30, Length64(2, NANOMETER))
    assert_almost_equal(t.to(NANOMETER), 60.0, atol=1e-9)
    with assert_raises(contains="voltage must be"):
        _ = anodic_thickness(-1, Length64(2, NANOMETER))
    with assert_raises(contains="voltage must be"):
        _ = anodic_thickness(NAN, Length64(2, NANOMETER))
    with assert_raises(contains="growth per volt"):
        _ = anodic_thickness(10, Length64(0))
    with assert_raises(contains="growth per volt"):
        _ = anodic_thickness(10, Length64(NAN))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
