# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the kinds, units, elements and thermochemical data of
`extensions.chemistry`.

References: the CODATA key values for thermodynamics (Cox, Wagman and
Medvedev, 1989) for 298.15 K enthalpies and entropies; the CRC Handbook
for boiling and melting points; IUPAC 2021 for atomic weights.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import (
    atomic_hydrogen,
    calcite,
    carbon_dioxide,
    carbon_monoxide,
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
from extensions.chemistry.elements import (
    ALUMINUM,
    COBALT,
    FLUORINE,
    SILICON,
    URANIUM,
    element_from_symbol,
    parse_formula,
    BISMUTH,
    CARBON,
    CHLORINE,
    Element,
    ElementCount,
    Formula,
    GOLD,
    HYDROGEN,
    MAGNESIUM,
    OXYGEN,
    TITANIUM,
    ZINC,
    formula_index,
)
from extensions.chemistry.kinds import (
    ABOVE,
    ACTION,
    BELOW,
    BURN,
    CORROSIVE,
    Check,
    ELECTRICAL,
    ENGINEERING,
    FLAMMABLE_GAS,
    GAS,
    HELD_BACK,
    Hazard,
    KINETIC,
    LIQUID,
    PHASE,
    PHYSICAL,
    PRESSURE_ABOVE,
    PRESSURE_BELOW,
    PRESSURE_VESSEL,
    PROCEEDS,
    PYROPHORIC,
    Phase,
    RequirementKind,
    SOLID,
    THERMODYNAMIC,
    TOXIC_GAS,
)
from extensions.chemistry.quantities import (
    ATMOSPHERE,
    Amount64,
    BAR,
    CUBIC_CENTIMETER_PER_MOLE,
    CUBIC_METER_PER_MOLE,
    FractureEnergy64,
    GAS_CONSTANT,
    GRAM_PER_MOLE,
    JOULE_PER_MOLE,
    JOULE_PER_MOLE_KELVIN,
    JOULE_PER_SQUARE_METER,
    KILOGRAM_PER_MOLE,
    KILOJOULE_PER_MOLE,
    KILOMOLE,
    MICROMETER,
    MOLE,
    MolarEnergy64,
    MolarEntropy64,
    MolarMass64,
    MolarVolume64,
    STANDARD_PRESSURE,
    TORR,
    amount_of,
)
from extensions.chemistry.thermo import Nasa7, Species, Substance
from units.si import GRAM, JOULE, KILOGRAM, Length64, Mass64, Pressure64
from units.temperature import Temperature64


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


def _kj(value: MolarEnergy64) -> Float64:
    return value.to(KILOJOULE_PER_MOLE)


# --- kinds ------------------------------------------------------------------


def test_phase() raises:
    assert_true(SOLID.is_valid())
    assert_true(GAS.is_valid())
    assert_false(Phase(-1).is_valid())
    assert_false(Phase(3).is_valid())
    assert_equal(SOLID.name(), "s")
    assert_equal(LIQUID.name(), "l")
    assert_equal(GAS.name(), "g")
    assert_equal(Phase(3).name(), "?")


def test_requirement_kind() raises:
    assert_false(RequirementKind(5).is_valid())
    assert_false(RequirementKind(-1).is_valid())
    assert_equal(THERMODYNAMIC.name(), "thermodynamic")
    assert_equal(PHASE.name(), "phase")
    assert_equal(KINETIC.name(), "kinetic")
    assert_equal(PHYSICAL.name(), "physical")
    assert_equal(ENGINEERING.name(), "engineering")
    assert_equal(RequirementKind(9).name(), "?")


def test_check() raises:
    assert_true(ACTION.is_valid())
    assert_false(Check(7).is_valid())
    assert_equal(PROCEEDS.name(), "proceeds")
    assert_equal(HELD_BACK.name(), "held back")
    assert_equal(ABOVE.name(), "above")
    assert_equal(BELOW.name(), "below")
    assert_equal(PRESSURE_ABOVE.name(), "pressure above")
    assert_equal(PRESSURE_BELOW.name(), "pressure below")
    assert_equal(ACTION.name(), "action")
    assert_equal(Check(-2).name(), "?")


def test_hazard() raises:
    assert_true(PRESSURE_VESSEL.is_valid())
    assert_false(Hazard(7).is_valid())
    assert_equal(BURN.name(), "burn")
    assert_equal(TOXIC_GAS.name(), "toxic gas")
    assert_equal(CORROSIVE.name(), "corrosive")
    assert_equal(FLAMMABLE_GAS.name(), "flammable gas")
    assert_equal(PYROPHORIC.name(), "pyrophoric")
    assert_equal(ELECTRICAL.name(), "electrical")
    assert_equal(PRESSURE_VESSEL.name(), "pressure vessel")
    assert_equal(Hazard(70).name(), "?")


# --- quantities -------------------------------------------------------------


def test_molar_units() raises:
    var g = MolarEnergy64(-312.5, KILOJOULE_PER_MOLE)
    assert_almost_equal(g.value, -312500.0, atol=1e-9)
    assert_almost_equal(g.to(JOULE_PER_MOLE), -312500.0, atol=1e-9)
    assert_almost_equal((g + g).to(KILOJOULE_PER_MOLE), -625.0, atol=1e-12)
    assert_almost_equal((g - g).value, 0.0, atol=1e-12)
    assert_almost_equal((-g).value, 312500.0, atol=1e-9)
    assert_almost_equal(g.scaled(2).value, -625000.0, atol=1e-9)
    assert_true(g < -g)
    assert_false(g > -g)
    var heat = g.times(Amount64(2, MOLE))
    assert_almost_equal(heat.to(JOULE), -625000.0, atol=1e-9)
    var s = MolarEntropy64(10, JOULE_PER_MOLE_KELVIN)
    assert_almost_equal(s.times_temperature(_t(300)).value, 3000.0, atol=1e-9)
    var m = MolarMass64(47.867, GRAM_PER_MOLE)
    assert_almost_equal(m.to(KILOGRAM_PER_MOLE), 0.047867, atol=1e-15)
    var v = MolarVolume64(3.4171, CUBIC_CENTIMETER_PER_MOLE)
    assert_almost_equal(v.to(CUBIC_METER_PER_MOLE), 3.4171e-6, atol=1e-18)
    assert_almost_equal(GAS_CONSTANT.value, 8.31446261815324, atol=0)


def test_amounts() raises:
    var n = Amount64(2, KILOMOLE)
    assert_almost_equal(n.value, 2000.0, atol=1e-12)
    assert_almost_equal(n.to(MOLE), 2000.0, atol=1e-12)
    assert_almost_equal(n.scaled(0.5).to(KILOMOLE), 1.0, atol=1e-12)
    var ti = amount_of(Mass64(47.867, GRAM), MolarMass64(47.867, GRAM_PER_MOLE))
    assert_almost_equal(ti.value, 1.0, atol=1e-12)
    with assert_raises(contains="molar mass"):
        _ = amount_of(Mass64(1), MolarMass64(nan[DType.float64]()))
    with assert_raises(contains="molar mass"):
        _ = amount_of(Mass64(1), MolarMass64(0))
    with assert_raises(contains="mass must be finite"):
        _ = amount_of(Mass64(inf[DType.float64]()), MolarMass64(1))


def test_pressure_and_coating_units() raises:
    assert_almost_equal(Pressure64(1, BAR).value, 1e5, atol=0)
    assert_almost_equal(Pressure64(1, ATMOSPHERE).value, 101325.0, atol=0)
    assert_almost_equal(Pressure64(760, TORR).value, 101325.0, atol=1e-9)
    assert_almost_equal(STANDARD_PRESSURE.value, 1e5, atol=0)
    assert_almost_equal(Length64(10, MICROMETER).value, 1e-5, atol=1e-20)
    var gamma = FractureEnergy64(30, JOULE_PER_SQUARE_METER)
    assert_almost_equal(gamma.value, 30.0, atol=0)


# --- elements ---------------------------------------------------------------


def test_elements() raises:
    assert_true(HYDROGEN.is_valid())
    assert_true(ZINC.is_valid())
    assert_true(BISMUTH.is_valid())
    assert_true(URANIUM.is_valid())
    # Technetium, promethium and polonium have no standard atomic weight.
    assert_false(Element(43).is_valid())
    assert_false(Element(61).is_valid())
    assert_false(Element(84).is_valid())
    assert_false(Element(0).is_valid())
    assert_false(Element(93).is_valid())
    assert_equal(TITANIUM.symbol(), "Ti")
    assert_equal(GOLD.symbol(), "Au")
    assert_equal(Element(43).symbol(), "?")
    assert_almost_equal(
        URANIUM.atomic_weight().to(GRAM_PER_MOLE), 238.03, atol=1e-12
    )
    assert_almost_equal(
        TITANIUM.atomic_weight().to(GRAM_PER_MOLE), 47.867, atol=1e-12
    )
    assert_almost_equal(
        BISMUTH.atomic_weight().to(GRAM_PER_MOLE), 208.98, atol=1e-12
    )
    with assert_raises(contains="in the table"):
        _ = Element(119).atomic_weight()


def test_formula() raises:
    var ticl4 = Formula([ElementCount(TITANIUM, 1), ElementCount(CHLORINE, 4)])
    assert_equal(String(ticl4), "TiCl4")
    assert_equal(ticl4.count_of(CHLORINE), 4)
    assert_equal(ticl4.count_of(OXYGEN), 0)
    # 47.867 + 4 * 35.45 g/mol.
    assert_almost_equal(
        ticl4.molar_mass().to(GRAM_PER_MOLE), 189.667, atol=1e-9
    )
    var flipped = Formula(
        [ElementCount(CHLORINE, 4), ElementCount(TITANIUM, 1)]
    )
    assert_true(ticl4.same(flipped))
    var ticl3 = Formula([ElementCount(TITANIUM, 1), ElementCount(CHLORINE, 3)])
    assert_false(ticl4.same(ticl3))
    assert_false(ticl4.same(Formula([ElementCount(TITANIUM, 1)])))
    with assert_raises(contains="at least one"):
        _ = Formula(List[ElementCount]())
    with assert_raises(contains="in the table"):
        _ = Formula([ElementCount(Element(200), 1)])
    with assert_raises(contains="positive"):
        _ = Formula([ElementCount(CARBON, 0)])
    with assert_raises(contains="once"):
        _ = Formula([ElementCount(CARBON, 1), ElementCount(CARBON, 2)])


def test_element_symbols() raises:
    assert_true(element_from_symbol("Ti") == TITANIUM)
    assert_true(element_from_symbol("TI") == TITANIUM)
    assert_true(element_from_symbol("cl") == CHLORINE)
    assert_true(element_from_symbol("U") == URANIUM)
    with assert_raises(contains="symbol 'Xx'"):
        _ = element_from_symbol("Xx")
    with assert_raises(contains="symbol 'Tc'"):
        _ = element_from_symbol("Tc")


def test_parse_formula() raises:
    var ticl4 = parse_formula("TiCl4")
    assert_equal(String(ticl4), "TiCl4")
    var hydroxide = parse_formula("Ca(OH)2")
    assert_equal(String(hydroxide), "CaO2H2")
    assert_equal(hydroxide.count_of(HYDROGEN), 2)
    # A repeated element is counted once, where it first appears.
    var acid = parse_formula("CH3COOH")
    assert_equal(String(acid), "C2H4O2")
    # Nested groups multiply.
    var nested = parse_formula("Mg3(Si2(O5))2")
    assert_equal(nested.count_of(OXYGEN), 10)
    assert_equal(nested.count_of(SILICON), 4)
    assert_equal(parse_formula("CO").count_of(CARBON), 1)
    assert_equal(parse_formula("Co").count_of(COBALT), 1)
    assert_equal(parse_formula("Al2O3").count_of(ALUMINUM), 2)
    assert_equal(parse_formula("UF6").count_of(FLUORINE), 6)
    assert_equal(parse_formula("C999999").count_of(CARBON), 999999)


def test_parse_formula_refuses_bad_text() raises:
    with assert_raises(contains="at least one element"):
        _ = parse_formula("")
    with assert_raises(contains="unmatched '('"):
        _ = parse_formula("Ca(OH")
    with assert_raises(contains="unmatched ')'"):
        _ = parse_formula("CaOH)2")
    with assert_raises(contains="must hold an element"):
        _ = parse_formula("Ca()2")
    with assert_raises(contains="must be positive"):
        _ = parse_formula("H0")
    with assert_raises(contains="too large"):
        _ = parse_formula("C1234567")
    with assert_raises(contains="too large"):
        _ = parse_formula("(C999999)999999(C999999)999999")
    with assert_raises(contains="only element symbols"):
        _ = parse_formula("H2O!")
    with assert_raises(contains="only element symbols"):
        _ = parse_formula("[H2O]")
    with assert_raises(contains="only element symbols"):
        _ = parse_formula("h2o")
    with assert_raises(contains="symbol 'Q'"):
        _ = parse_formula("Q2")
    # A small letter that follows a symbol is part of it.
    with assert_raises(contains="symbol 'Hz'"):
        _ = parse_formula("Hz")
    # A brace after a symbol is not a small letter.
    with assert_raises(contains="only element symbols"):
        _ = parse_formula("H{")


def test_formula_index() raises:
    var counts: List[ElementCount] = [
        ElementCount(CARBON, 1),
        ElementCount(OXYGEN, 2),
    ]
    assert_equal(formula_index(counts, OXYGEN), 1)
    assert_equal(formula_index(counts, HYDROGEN), -1)
    assert_equal(formula_index(List[ElementCount](), HYDROGEN), -1)


# --- NASA polynomials -------------------------------------------------------


def _constant_cp() raises -> Nasa7:
    """A gas with cp = 2.5 R, H = 0 and S = R ln(T / 1 K) at 1 K."""
    return Nasa7([100.0, 1000.0], [2.5, 0, 0, 0, 0, 0, 0])


def test_nasa_formulas() raises:
    var n = _constant_cp()
    var r = GAS_CONSTANT.value
    assert_almost_equal(n.heat_capacity(_t(500)).value, 2.5 * r, atol=1e-12)
    assert_almost_equal(n.enthalpy(_t(500)).value, 2.5 * r * 500, atol=1e-9)
    # S/R = 2.5 ln T.
    var s = 2.5 * r * 6.214608098422191
    assert_almost_equal(n.entropy(_t(500)).value, s, atol=1e-9)
    assert_almost_equal(
        n.gibbs(_t(500)).value, 2.5 * r * 500 - 500 * s, atol=1e-9
    )
    assert_almost_equal(n.t_min().kelvin, 100.0, atol=0)
    assert_almost_equal(n.t_max().kelvin, 1000.0, atol=0)
    assert_true(n.covers(_t(100)))
    assert_false(n.covers(_t(99)))
    assert_false(n.covers(_t(1001)))
    with assert_raises(contains="outside the range"):
        _ = n.enthalpy(_t(2000))


def test_nasa_segments() raises:
    # Two segments: the second has cp = 3.5 R.
    var n = Nasa7(
        [100.0, 500.0, 1000.0],
        [2.5, 0, 0, 0, 0, 0, 0, 3.5, 0, 0, 0, 0, 0, 0],
    )
    var r = GAS_CONSTANT.value
    assert_almost_equal(n.heat_capacity(_t(300)).value, 2.5 * r, atol=1e-12)
    # The shared end belongs to the lower segment.
    assert_almost_equal(n.heat_capacity(_t(500)).value, 2.5 * r, atol=1e-12)
    assert_almost_equal(n.heat_capacity(_t(800)).value, 3.5 * r, atol=1e-12)
    var moved = n.shifted(MolarEnergy64(100), MolarEntropy64(-2))
    assert_almost_equal(
        moved.enthalpy(_t(800)).value - n.enthalpy(_t(800)).value,
        100.0,
        atol=1e-9,
    )
    assert_almost_equal(
        moved.entropy(_t(300)).value - n.entropy(_t(300)).value,
        -2.0,
        atol=1e-12,
    )


def test_nasa_refuses_bad_data() raises:
    with assert_raises(contains="at least one segment"):
        _ = Nasa7([300.0], List[Float64]())
    with assert_raises(contains="seven coefficients"):
        _ = Nasa7([300.0, 400.0], [1.0, 2.0])
    with assert_raises(contains="finite and positive"):
        _ = Nasa7([nan[DType.float64](), 400.0], [0.0, 0, 0, 0, 0, 0, 0])
    with assert_raises(contains="finite and positive"):
        _ = Nasa7([0.0, 400.0], [0.0, 0, 0, 0, 0, 0, 0])
    with assert_raises(contains="ascend"):
        _ = Nasa7([400.0, 300.0], [0.0, 0, 0, 0, 0, 0, 0])
    with assert_raises(contains="coefficient must be finite"):
        _ = Nasa7([300.0, 400.0], [inf[DType.float64](), 0, 0, 0, 0, 0, 0])


# --- species and substances -------------------------------------------------


def _carbon() raises -> Formula:
    return Formula([ElementCount(CARBON, 1)])


def _species(phase: Phase, low: Float64, high: Float64) raises -> Species:
    return Species(
        "x",
        _carbon(),
        phase,
        Nasa7([low, high], [2.5, 0, 0, 0, 0, 0, 0]),
        MolarVolume64(0),
    )


def test_species() raises:
    var s = _species(SOLID, 100, 1000)
    assert_true(s.covers(_t(500)))
    assert_false(s.covers(_t(50)))
    assert_almost_equal(s.molar_mass().to(GRAM_PER_MOLE), 12.011, atol=1e-12)
    assert_equal(String(s), "x")
    with assert_raises(contains="SOLID, LIQUID or GAS"):
        _ = _species(Phase(5), 100, 1000)
    with assert_raises(contains="molar volume"):
        _ = Species(
            "x",
            _carbon(),
            SOLID,
            _constant_cp(),
            MolarVolume64(nan[DType.float64]()),
        )
    with assert_raises(contains="molar volume"):
        _ = Species("x", _carbon(), SOLID, _constant_cp(), MolarVolume64(-1))


def test_substance_refuses_bad_phases() raises:
    with assert_raises(contains="at least one phase"):
        _ = Substance("x", List[Species]())
    var other = Species(
        "y",
        Formula([ElementCount(OXYGEN, 2)]),
        LIQUID,
        Nasa7([500.0, 900.0], [2.5, 0, 0, 0, 0, 0, 0]),
        MolarVolume64(0),
    )
    with assert_raises(contains="share one formula"):
        _ = Substance("x", [_species(SOLID, 100, 500), other^])
    with assert_raises(contains="of its own"):
        _ = Substance("x", [_species(SOLID, 100, 500), _species(GAS, 500, 900)])
    with assert_raises(contains="of its own"):
        _ = Substance("x", [_species(GAS, 100, 500), _species(SOLID, 500, 900)])
    with assert_raises(contains="meet"):
        _ = Substance(
            "x", [_species(SOLID, 100, 500), _species(LIQUID, 600, 900)]
        )


def test_substance_phases() raises:
    var ti = titanium()
    assert_equal(String(ti), "Ti")
    assert_false(ti.is_gas())
    assert_true(oxygen().is_gas())
    assert_true(ti.covers(_t(1500)))
    assert_false(ti.covers(_t(100)))
    assert_false(ti.covers(_t(7000)))
    assert_true(ti.phase_at(_t(1000)) == SOLID)
    assert_true(ti.phase_at(_t(2500)) == LIQUID)
    assert_almost_equal(ti.transition(SOLID, SOLID).kelvin, 1156.0, atol=0)
    assert_almost_equal(ti.melting_point().kelvin, 1944.0, atol=0)
    assert_almost_equal(ti.molar_mass().to(GRAM_PER_MOLE), 47.867, atol=1e-12)
    assert_almost_equal(ti.molar_volume_at(_t(500)).value, 0.0, atol=0)
    with assert_raises(contains="outside the range of a substance"):
        _ = ti.gibbs(_t(100))
    with assert_raises(contains="does not have this transition"):
        _ = ti.transition(LIQUID, GAS)
    with assert_raises(contains="does not have this transition"):
        _ = rutile().melting_point()


def test_transitions_meet_in_the_data() raises:
    # Two phases have one Gibbs energy at their transition.
    var pairs: List[Substance] = [
        magnesium(),
        magnesium_chloride(),
        titanium(),
    ]
    for s in pairs:
        for i in range(1, len(s.phases)):
            var t = s.phases[i].thermo.t_min()
            var below = s.phases[i - 1].thermo.gibbs(t).value
            var above = s.phases[i].thermo.gibbs(t).value
            assert_almost_equal(below, above, atol=0.02)
    assert_almost_equal(magnesium().melting_point().kelvin, 923.0, atol=0)
    assert_almost_equal(
        magnesium_chloride().melting_point().kelvin, 987.0, atol=0
    )


# --- the catalog against reference values ------------------------------------


def test_catalog_at_room_temperature() raises:
    var t = _t(298.15)
    # CODATA: CO2 -393.51 kJ/mol and 213.785 J/(mol K).
    assert_almost_equal(_kj(carbon_dioxide().enthalpy(t)), -393.51, atol=0.05)
    var co2 = carbon_dioxide().phases[0].thermo.entropy(t).value
    assert_almost_equal(co2, 213.785, atol=0.05)
    # CODATA: CO -110.53 kJ/mol.
    assert_almost_equal(_kj(carbon_monoxide().enthalpy(t)), -110.53, atol=0.05)
    # Elements in their reference state have zero enthalpy.
    assert_almost_equal(_kj(oxygen().enthalpy(t)), 0.0, atol=0.01)
    assert_almost_equal(_kj(hydrogen().enthalpy(t)), 0.0, atol=0.01)
    assert_almost_equal(_kj(chlorine().enthalpy(t)), 0.0, atol=0.01)
    assert_almost_equal(_kj(graphite().enthalpy(t)), 0.0, atol=0.01)
    assert_almost_equal(_kj(magnesium().enthalpy(t)), 0.0, atol=0.01)
    assert_almost_equal(_kj(titanium().enthalpy(t)), 0.0, atol=0.01)
    # Atomic hydrogen: 217.998 kJ/mol. Methane: -74.6 kJ/mol.
    assert_almost_equal(_kj(atomic_hydrogen().enthalpy(t)), 218.0, atol=0.05)
    assert_almost_equal(_kj(methane().enthalpy(t)), -74.6, atol=0.3)
    # Diamond: 1.895 kJ/mol and 2.377 J/(mol K), from graphite's 5.740.
    assert_almost_equal(_kj(diamond().enthalpy(t)), 1.895, atol=0.01)
    var s_d = diamond().phases[0].thermo.entropy(t).value
    var s_g = graphite().phases[0].thermo.entropy(t).value
    assert_almost_equal(s_d - s_g, -3.363, atol=1e-9)
    assert_almost_equal(
        diamond().molar_volume_at(t).to(CUBIC_CENTIMETER_PER_MOLE),
        3.4171,
        atol=1e-12,
    )


def test_catalog_condensed_phases() raises:
    var t = _t(300)
    # CODATA: TiO2 rutile -944.0 kJ/mol; MgCl2 -641.3; CaO -634.9.
    assert_almost_equal(_kj(rutile().enthalpy(t)), -944.0, atol=1.0)
    assert_almost_equal(_kj(magnesium_chloride().enthalpy(t)), -641.3, atol=0.5)
    assert_almost_equal(_kj(lime().enthalpy(t)), -634.9, atol=0.5)
    # NBS: liquid TiCl4 -804.2 kJ/mol; calcite -1207.
    assert_almost_equal(
        _kj(titanium_tetrachloride().enthalpy(t)), -804.2, atol=0.5
    )
    assert_almost_equal(_kj(calcite().enthalpy(_t(298.15))), -1207.0, atol=1.5)
    # The gases are each one phase.
    assert_true(titanium_tetrachloride_gas().is_gas())
    assert_true(magnesium_gas().is_gas())
    assert_true(magnesium_chloride_gas().is_gas())
    assert_equal(len(magnesium_chloride_gas().phases), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
