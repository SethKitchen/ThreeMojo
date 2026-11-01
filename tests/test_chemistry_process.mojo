# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the reactions, requirements, windows, coatings, energy
balances and recipes of `extensions.chemistry`.

References, independent of the NASA data the module reads:

- Normal boiling points, CRC Handbook: TiCl4 136.4 degC (409.6 K) and Mg
  1090 degC (1363 K).
- Limestone calcines in one atmosphere of CO2 near 898 degC (1171 K).
- The Boudouard reaction C + CO2 = 2 CO balances near 700 degC (973 K).
- Methane cracks to graphite and hydrogen above about 545 degC (818 K).
- The Berman-Simon line puts graphite and diamond in balance at about
  1.5 GPa at room temperature.
- Kroll practice runs the reduction near 800 to 900 degC, inside the
  window of 714 to 1085 degC that the requirements give.
"""

from std.math import inf, isinf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import (
    calcite,
    carbon_dioxide,
    carbon_monoxide,
    diamond,
    graphite,
    hydrogen,
    lime,
    magnesium,
    magnesium_chloride,
    magnesium_gas,
    methane,
    oxygen,
    rutile,
    titanium,
    titanium_tetrachloride,
    titanium_tetrachloride_gas,
)
from extensions.chemistry.coating import (
    ElasticLayer,
    delamination_thickness,
    mismatch_stress,
)
from extensions.chemistry.economics import (
    EnergyPrice64,
    Ledger,
    Money64,
    StreamItem,
    UnitPrice64,
    heat_duty,
    stream_enthalpy,
)
from extensions.chemistry.kinds import (
    ACTION,
    BURN,
    Check,
    ENGINEERING,
    Hazard,
    HOME_WORKSHOP,
    INDUSTRIAL_PLANT,
    KINETIC,
    PHASE,
    PHYSICAL,
    PROCEEDS,
    RequirementKind,
    Setting,
    THERMODYNAMIC,
)
from extensions.chemistry.process import (
    Interval,
    Requirement,
    Step,
    _intersect,
    above,
    action,
    below,
    held_back,
    interval_text,
    kelvin_text,
    met_intervals,
    operating_window,
    pressure_above,
    pressure_below,
    proceeds,
    report,
    unmet,
)
from extensions.chemistry.quantities import (
    ATMOSPHERE,
    Amount64,
    FractureEnergy64,
    KILOJOULE_PER_MOLE,
    MICROMETER,
    MOLE,
    TORR,
)
from extensions.chemistry.reaction import Reaction, Term, product, reactant
from extensions.chemistry.recipes import (
    CEMENTED_CARBIDE,
    CVD_DIAMOND,
    bismuth_crystals,
    diamond_coating,
    hydrogen_filament,
    kroll_reduction,
    kroll_route,
    lime_burning,
    tetrachloride_distillation,
    titanium_chlorination,
    vacuum_distillation,
)
from units.si import (
    GIGAPASCAL,
    KILOGRAM,
    KILOWATT_HOUR,
    Energy64,
    Mass64,
    Pressure64,
    ThermalExpansion64,
)
from units.temperature import CELSIUS, Temperature64

comptime NAN = nan[DType.float64]()
comptime INF = inf[DType.float64]()


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


def _atm() -> Pressure64:
    return Pressure64(1, ATMOSPHERE)


def _calcination() raises -> Reaction:
    return Reaction(
        [reactant(calcite()), product(lime()), product(carbon_dioxide())]
    )


def _boiling() raises -> Reaction:
    return Reaction([reactant(magnesium()), product(magnesium_gas())])


# --- reactions --------------------------------------------------------------


def test_reaction_text() raises:
    var kroll = Reaction(
        [
            reactant(titanium_tetrachloride_gas()),
            reactant(magnesium(), 2),
            product(titanium()),
            product(magnesium_chloride(), 2),
        ]
    )
    assert_equal(String(kroll), "TiCl4(g) + 2 Mg -> Ti + 2 MgCl2")
    var burn = Reaction(
        [
            reactant(carbon_monoxide()),
            reactant(oxygen(), 0.5),
            product(carbon_dioxide()),
        ]
    )
    assert_equal(String(burn), "CO(g) + 0.5 O2(g) -> CO2(g)")


def test_reaction_refuses_bad_terms() raises:
    with assert_raises(contains="needs a reactant"):
        _ = Reaction(List[Term]())
    with assert_raises(contains="needs a reactant"):
        _ = Reaction([product(lime())])
    with assert_raises(contains="needs a product"):
        _ = Reaction([reactant(lime())])
    with assert_raises(contains="finite"):
        _ = Reaction([reactant(graphite(), INF), product(diamond(), INF)])
    with assert_raises(contains="not be zero"):
        _ = Reaction([reactant(graphite(), 0), product(diamond())])
    with assert_raises(contains="mole fraction"):
        _ = Reaction([reactant(oxygen(), 1, 0), product(oxygen())])
    with assert_raises(contains="mole fraction"):
        _ = Reaction([reactant(oxygen(), 1, 1.5), product(oxygen())])
    with assert_raises(contains="pure"):
        _ = Reaction([reactant(graphite(), 1, 0.5), product(diamond())])
    with assert_raises(contains="balance"):
        _ = Reaction([reactant(graphite()), product(carbon_dioxide())])
    # A gas can have any fraction in (0, 1].
    var mix = Reaction([reactant(oxygen(), 1, 0.2), product(oxygen())])
    assert_true(mix.covers(_t(1000)))


def test_driving_force() raises:
    var r = _calcination()
    assert_true(r.covers(_t(1000)))
    assert_false(r.covers(_t(1300)))
    assert_true(r.delta_g(_t(1000), _atm()).value > 0)
    assert_true(r.delta_g(_t(1190), _atm()).value < 0)
    # About 178 kJ/mol of heat at room temperature (NBS tables). The CaO
    # data starts at 300 K.
    assert_almost_equal(
        r.delta_h(_t(300)).to(KILOJOULE_PER_MOLE), 178.3, atol=1.0
    )
    with assert_raises(contains="above absolute zero"):
        _ = r.delta_g(_t(-1), _atm())
    with assert_raises(contains="pressure must be finite"):
        _ = r.delta_g(_t(1000), Pressure64(NAN))
    with assert_raises(contains="pressure must be finite"):
        _ = r.delta_g(_t(1000), Pressure64(0))
    with assert_raises(contains="outside the range"):
        _ = r.delta_h(_t(1300))


def test_equilibrium_temperatures() raises:
    var atm = _atm()
    var lime_t = _calcination().equilibrium_temperature(_t(900), _t(1199), atm)
    assert_almost_equal(lime_t.kelvin, 1171.0, atol=6.0)
    var ticl4 = Reaction(
        [
            reactant(titanium_tetrachloride()),
            product(titanium_tetrachloride_gas()),
        ]
    ).equilibrium_temperature(_t(350), _t(500), atm)
    assert_almost_equal(ticl4.kelvin, 409.6, atol=1.0)
    var mg = _boiling().equilibrium_temperature(_t(1000), _t(1500), atm)
    assert_almost_equal(mg.kelvin, 1363.0, atol=4.0)
    var boudouard = Reaction(
        [
            reactant(graphite()),
            reactant(carbon_dioxide()),
            product(carbon_monoxide(), 2),
        ]
    ).equilibrium_temperature(_t(800), _t(1200), Pressure64(1e5))
    assert_almost_equal(boudouard.kelvin, 973.0, atol=5.0)
    var cracking = Reaction(
        [reactant(methane()), product(graphite()), product(hydrogen(), 2)]
    ).equilibrium_temperature(_t(500), _t(1200), Pressure64(1e5))
    assert_almost_equal(cracking.kelvin, 818.0, atol=10.0)
    with assert_raises(contains="one sign"):
        _ = _calcination().equilibrium_temperature(_t(900), _t(1000), atm)


def test_diamond_needs_pressure() raises:
    var change = Reaction([reactant(graphite()), product(diamond())])
    # Diamond is metastable at one bar...
    assert_true(change.delta_g(_t(298.15), Pressure64(1e5)).value > 0)
    # ...and stable above about 1.5 GPa at room temperature.
    assert_true(change.delta_g(_t(298.15), Pressure64(1.4e9)).value > 0)
    assert_true(change.delta_g(_t(298.15), Pressure64(1.7e9)).value < 0)


def test_mass_ratio() raises:
    var kroll = Reaction(
        [
            reactant(titanium_tetrachloride_gas()),
            reactant(magnesium(), 2),
            product(titanium()),
            product(magnesium_chloride(), 2),
        ]
    )
    # 2 * 24.305 / 47.867.
    assert_almost_equal(
        kroll.mass_ratio(magnesium(), titanium()), 1.015522176, atol=1e-8
    )
    var boil = _boiling()
    assert_almost_equal(boil.mass_ratio(magnesium(), magnesium_gas()), 1.0)
    with assert_raises(contains="not in the reaction"):
        _ = kroll.mass_ratio(oxygen(), titanium())


# --- requirements -----------------------------------------------------------


def test_requirement_construction() raises:
    with assert_raises(contains="kind is not valid"):
        _ = action(RequirementKind(9), "x", "y")
    with assert_raises(contains="check is not valid"):
        _ = Requirement(PHASE, Check(9), None, _t(0), Pressure64(0), "x", "y")
    with assert_raises(contains="needs a reaction"):
        _ = Requirement(PHASE, PROCEEDS, None, _t(0), Pressure64(0), "x", "y")
    with assert_raises(contains="bound is not valid"):
        _ = above(PHASE, _t(-5), "x", "y")
    with assert_raises(contains="bound is not valid"):
        _ = below(PHASE, _t(-5), "x", "y")
    with assert_raises(contains="pressure must be finite"):
        _ = pressure_above(PHYSICAL, Pressure64(NAN), "x", "y")
    with assert_raises(contains="pressure must be finite"):
        _ = pressure_below(PHYSICAL, Pressure64(-1), "x", "y")


def test_requirement_checks() raises:
    var atm = _atm()
    var go = proceeds(THERMODYNAMIC, _calcination(), "go")
    assert_true(go.is_met(_t(1190), atm))
    assert_false(go.is_met(_t(1000), atm))
    # Outside the data, a reaction check is not met.
    assert_false(go.is_met(_t(1300), atm))
    var stay = held_back(PHASE, _boiling(), "stay")
    assert_true(stay.is_met(_t(1200), atm))
    assert_false(stay.is_met(_t(1400), atm))
    var hot = above(KINETIC, _t(900), "hot", "src")
    assert_true(hot.is_met(_t(901), atm))
    assert_false(hot.is_met(_t(900), atm))
    var cool = below(ENGINEERING, _t(900), "cool", "src")
    assert_true(cool.is_met(_t(899), atm))
    assert_false(cool.is_met(_t(900), atm))
    var dense = pressure_above(PHYSICAL, Pressure64(1000), "dense", "src")
    assert_true(dense.is_met(_t(900), atm))
    assert_false(dense.is_met(_t(900), Pressure64(1000)))
    var thin = pressure_below(PHYSICAL, Pressure64(1000), "thin", "src")
    assert_true(thin.is_met(_t(900), Pressure64(10)))
    assert_false(thin.is_met(_t(900), atm))
    assert_true(action(ENGINEERING, "do", "src").is_met(_t(900), atm))


def test_requirement_descriptions() raises:
    var atm = _atm()
    var go = proceeds(THERMODYNAMIC, _calcination(), "go")
    assert_equal(
        go.describe(_t(1300), atm),
        String("CaCO3 -> CaO + CO2(g): the data does not reach ")
        + "1300.0 K (1026.8 degC)",
    )
    assert_true(go.describe(_t(1000), atm).startswith("CaCO3 -> CaO"))
    assert_true(go.describe(_t(1000), atm).endswith("kJ/mol"))
    assert_equal(
        above(KINETIC, _t(900), "x", "y").describe(_t(1), atm),
        "bound 900.0 K (626.9 degC)",
    )
    assert_equal(
        pressure_below(PHYSICAL, Pressure64(1500), "x", "y").describe(
            _t(1), atm
        ),
        "bound 1.500 kPa",
    )
    assert_equal(action(PHASE, "x", "y").describe(_t(1), atm), "action")


def test_text() raises:
    assert_equal(
        kelvin_text(Temperature64(850, CELSIUS)), "1123.2 K (850.0 degC)"
    )
    assert_equal(
        interval_text(Interval(_t(300), _t(400))),
        "300.0 K (26.9 degC) to 400.0 K (126.9 degC)",
    )


# --- steps and windows ------------------------------------------------------


def _step() raises -> Step:
    return Step("test", HOME_WORKSHOP, _atm(), _t(300), _t(1000), _t(500))


def test_step_refuses_bad_values() raises:
    with assert_raises(contains="setting is not valid"):
        _ = Step("x", Setting(4), _atm(), _t(300), _t(1000), _t(500))
    with assert_raises(contains="pressure must be finite"):
        _ = Step("x", HOME_WORKSHOP, Pressure64(0), _t(300), _t(1000), _t(500))
    with assert_raises(contains="physical temperatures"):
        _ = Step("x", HOME_WORKSHOP, _atm(), _t(-1), _t(1000), _t(500))
    with assert_raises(contains="physical temperatures"):
        _ = Step("x", HOME_WORKSHOP, _atm(), _t(300), _t(INF), _t(500))
    with assert_raises(contains="must increase"):
        _ = Step("x", HOME_WORKSHOP, _atm(), _t(300), _t(300), _t(300))
    with assert_raises(contains="planned"):
        _ = Step("x", HOME_WORKSHOP, _atm(), _t(300), _t(1000), _t(200))
    with assert_raises(contains="planned"):
        _ = Step("x", HOME_WORKSHOP, _atm(), _t(300), _t(1000), _t(2000))
    var step = _step()
    with assert_raises(contains="hazard is not valid"):
        step.add_hazard(Hazard(12))


def test_met_intervals() raises:
    var atm = _atm()
    var hot = above(KINETIC, _t(600), "x", "y")
    var met = met_intervals(hot, _t(300), _t(1000), atm)
    assert_equal(len(met), 1)
    assert_almost_equal(met[0].low.kelvin, 600.0, atol=1e-6)
    assert_almost_equal(met[0].high.kelvin, 1000.0, atol=0)
    var cool = below(KINETIC, _t(600), "x", "y")
    met = met_intervals(cool, _t(300), _t(1000), atm)
    assert_equal(len(met), 1)
    assert_almost_equal(met[0].low.kelvin, 300.0, atol=0)
    assert_almost_equal(met[0].high.kelvin, 600.0, atol=1e-6)
    met = met_intervals(cool, _t(700), _t(1000), atm)
    assert_equal(len(met), 0)
    with assert_raises(contains="pressure must be finite"):
        _ = met_intervals(cool, _t(300), _t(1000), Pressure64(NAN))
    with assert_raises(contains="physical and increase"):
        _ = met_intervals(cool, _t(-1), _t(1000), atm)
    with assert_raises(contains="physical and increase"):
        _ = met_intervals(cool, _t(300), _t(INF), atm)
    with assert_raises(contains="physical and increase"):
        _ = met_intervals(cool, _t(1000), _t(300), atm)


def test_intersect() raises:
    var short: List[Interval] = [Interval(_t(1), _t(2))]
    var long: List[Interval] = [Interval(_t(0), _t(5))]
    var a = _intersect(short, long)
    assert_equal(len(a), 1)
    assert_almost_equal(a[0].low.kelvin, 1.0, atol=0)
    var b = _intersect(long, short)
    assert_equal(len(b), 1)
    assert_almost_equal(b[0].high.kelvin, 2.0, atol=0)
    var apart: List[Interval] = [Interval(_t(3), _t(4))]
    assert_equal(len(_intersect(apart, short)), 0)
    assert_equal(len(_intersect(List[Interval](), short)), 0)


def test_window_and_report_edges() raises:
    var step = _step()
    # No requirement: the whole range, and nothing fails.
    var window = operating_window(step)
    assert_equal(len(window), 1)
    assert_equal(unmet(step), 0)
    var text = report(step)
    assert_true(text.find("Hazards: none listed") >= 0)
    assert_true(text.find("every requirement met") >= 0)
    # Two bounds that cannot both hold: no window.
    step.add(above(KINETIC, _t(800), "hot", "src"))
    step.add(below(ENGINEERING, _t(600), "cool", "src"))
    step.add(action(ENGINEERING, "do it", "src"))
    step.add_hazard(BURN)
    assert_equal(len(operating_window(step)), 0)
    assert_equal(unmet(step), 1)
    text = report(step)
    assert_true(text.find("Window: none in 300.0 K") >= 0)
    assert_true(text.find("1 requirement(s) not met") >= 0)
    assert_true(text.find("[NOT MET] kinetic: hot") >= 0)
    assert_true(text.find("[met] engineering: cool") >= 0)
    assert_true(text.find("[do] engineering: do it") >= 0)
    assert_true(text.find("Hazards: burn") >= 0)


# --- recipes ----------------------------------------------------------------


def _window(step: Step) raises -> Interval:
    var w = operating_window(step)
    assert_equal(len(w), 1)
    return w[0]


def test_kroll_route() raises:
    var route = kroll_route()
    assert_equal(len(route), 4)
    for s in route:
        assert_true(s.setting == INDUSTRIAL_PLANT)
        assert_equal(unmet(s), 0)
    # Chlorination: a kinetic floor at 900 degC.
    var chlorinate = _window(titanium_chlorination())
    assert_almost_equal(chlorinate.low.to(CELSIUS), 900.0, atol=1e-3)
    # Distillation: TiCl4 boils at 409.6 K.
    var distill = _window(tetrachloride_distillation())
    assert_almost_equal(distill.low.kelvin, 409.6, atol=1.0)
    # Reduction: MgCl2 melts at 987 K; the Fe-Ti eutectic is 1085 degC.
    var reduce = _window(kroll_reduction())
    assert_almost_equal(reduce.low.kelvin, 987.0, atol=1e-3)
    assert_almost_equal(reduce.high.to(CELSIUS), 1085.0, atol=1e-3)
    # Vacuum distillation: MgCl2 evaporates at 10 Pa above about 975 K.
    var vacuum = _window(vacuum_distillation())
    assert_true(vacuum.low.kelvin > 900 and vacuum.low.kelvin < 1050)


def test_kroll_report() raises:
    var text = report(kroll_reduction())
    assert_true(text.find("Reduce TiCl4 with magnesium (Kroll)") >= 0)
    assert_true(text.find("Hazards: toxic gas, pyrophoric, burn") >= 0)
    assert_true(text.find("every requirement met") >= 0)
    assert_true(text.find("Fact: Ti + O2(g) -> TiO2: dG -") >= 0)
    assert_true(text.find(", proceeds") >= 0)
    var chlorinate = report(titanium_chlorination())
    assert_true(chlorinate.find("does not proceed") >= 0)


def test_diamond_recipe() raises:
    var step = diamond_coating()
    var w = _window(step)
    assert_almost_equal(w.low.to(CELSIUS), 700.0, atol=1e-3)
    assert_almost_equal(w.high.to(CELSIUS), 1000.0, atol=1e-3)
    assert_equal(unmet(step), 0)
    # Methane can deposit diamond only above about 969 K at this mix.
    var deposit = met_intervals(
        step.requirements[0], step.low, step.high, step.pressure
    )
    assert_almost_equal(deposit[0].low.kelvin, 969.0, atol=2.0)
    # At 5 Torr the pressure floor fails.
    step.pressure = Pressure64(5, TORR)
    assert_equal(unmet(step), 1)
    var filament = _window(hydrogen_filament())
    assert_true(filament.low.kelvin > 1900 and filament.low.kelvin < 2200)
    assert_almost_equal(filament.high.to(CELSIUS), 3422.0, atol=1e-3)


def test_home_recipes() raises:
    var bismuth = bismuth_crystals()
    assert_true(bismuth.setting == HOME_WORKSHOP)
    assert_almost_equal(_window(bismuth).low.kelvin, 544.55, atol=1e-3)
    var lime_step = lime_burning()
    var w = _window(lime_step)
    assert_almost_equal(w.low.kelvin, 1171.0, atol=6.0)
    # The calcite data stops at 1200 K, so the window does too.
    assert_almost_equal(w.high.kelvin, 1200.0, atol=1e-6)


# --- coating ----------------------------------------------------------------


def test_coating_stress() raises:
    var stress = mismatch_stress(
        CVD_DIAMOND,
        CEMENTED_CARBIDE,
        Temperature64(850, CELSIUS),
        Temperature64(20, CELSIUS),
    )
    # 1143 GPa / (1 - 0.069) * 2.5e-6 /K * 830 K.
    var expected = 1143e9 / 0.931 * 2.5e-6 * 830
    assert_almost_equal(stress.value, expected, atol=1.0)
    assert_true(stress.to(GIGAPASCAL) > 2.0)
    var h = delamination_thickness(CVD_DIAMOND, stress, FractureEnergy64(30))
    var nu = 0.069
    var h_expected = 2 * 1143e9 * 30 / ((1 - nu * nu) * expected * expected)
    assert_almost_equal(h.value, h_expected, atol=1e-12)
    assert_true(h.to(MICROMETER) > 5 and h.to(MICROMETER) < 20)
    assert_true(
        isinf(
            delamination_thickness(
                CVD_DIAMOND, Pressure64(0), FractureEnergy64(30)
            ).value
        )
    )


def test_coating_refuses_bad_values() raises:
    var t = _t(300)
    var bad_modulus = ElasticLayer(
        Pressure64(NAN), 0.2, ThermalExpansion64(1e-6)
    )
    with assert_raises(contains="modulus"):
        _ = mismatch_stress(bad_modulus, CEMENTED_CARBIDE, t, t)
    var zero_modulus = ElasticLayer(
        Pressure64(0), 0.2, ThermalExpansion64(1e-6)
    )
    with assert_raises(contains="modulus"):
        _ = mismatch_stress(CVD_DIAMOND, zero_modulus, t, t)
    var low_nu = ElasticLayer(Pressure64(1e9), -1, ThermalExpansion64(1e-6))
    with assert_raises(contains="Poisson"):
        low_nu.check()
    var high_nu = ElasticLayer(Pressure64(1e9), 0.5, ThermalExpansion64(1e-6))
    with assert_raises(contains="Poisson"):
        high_nu.check()
    var bad_alpha = ElasticLayer(Pressure64(1e9), 0.2, ThermalExpansion64(INF))
    with assert_raises(contains="expansion"):
        bad_alpha.check()
    with assert_raises(contains="above absolute zero"):
        _ = mismatch_stress(CVD_DIAMOND, CEMENTED_CARBIDE, _t(-1), t)
    with assert_raises(contains="above absolute zero"):
        _ = mismatch_stress(CVD_DIAMOND, CEMENTED_CARBIDE, t, _t(INF))
    with assert_raises(contains="stress must be finite"):
        _ = delamination_thickness(
            CVD_DIAMOND, Pressure64(NAN), FractureEnergy64(1)
        )
    with assert_raises(contains="fracture energy"):
        _ = delamination_thickness(
            CVD_DIAMOND, Pressure64(1), FractureEnergy64(NAN)
        )
    with assert_raises(contains="fracture energy"):
        _ = delamination_thickness(
            CVD_DIAMOND, Pressure64(1), FractureEnergy64(0)
        )


# --- energy and money -------------------------------------------------------


def _limestone_duty() raises -> Energy64:
    var feed = List[StreamItem]()
    feed.append(StreamItem(calcite(), Amount64(1, MOLE), _t(298.15)))
    var out = List[StreamItem]()
    out.append(StreamItem(lime(), Amount64(1, MOLE), _t(1173.15)))
    out.append(StreamItem(carbon_dioxide(), Amount64(1, MOLE), _t(1173.15)))
    return heat_duty(feed, out)


def test_heat_duty() raises:
    var duty = _limestone_duty()
    # The 178 kJ of reaction, plus about 85 kJ to heat CaO and CO2.
    assert_true(duty.value > 230e3 and duty.value < 300e3)
    assert_almost_equal(stream_enthalpy(List[StreamItem]()).value, 0.0, atol=0)
    var bad = List[StreamItem]()
    bad.append(StreamItem(lime(), Amount64(NAN), _t(300)))
    with assert_raises(contains="amount"):
        _ = stream_enthalpy(bad)
    var negative = List[StreamItem]()
    negative.append(StreamItem(lime(), Amount64(-1), _t(300)))
    with assert_raises(contains="amount"):
        _ = stream_enthalpy(negative)


def test_ledger() raises:
    var book = Ledger()
    book.buy(Mass64(2, KILOGRAM), UnitPrice64(0.5))
    book.heat(
        Energy64(1, KILOWATT_HOUR), EnergyPrice64.per_kilowatt_hour(0.2), 0.5
    )
    # Heat given off costs nothing.
    book.heat(
        Energy64(-5, KILOWATT_HOUR), EnergyPrice64.per_kilowatt_hour(0.2), 0.5
    )
    book.sell(Mass64(1, KILOGRAM), UnitPrice64(3))
    assert_almost_equal(book.spent.value, 1.0 + 0.4, atol=1e-12)
    assert_almost_equal(book.earned.value, 3.0, atol=1e-12)
    assert_almost_equal(book.margin().value, 1.6, atol=1e-12)
    assert_almost_equal((Money64(2) + Money64(1)).value, 3.0, atol=0)
    var price = EnergyPrice64.per_kilowatt_hour(0.36)
    assert_almost_equal(price.cost(Energy64(1e7)).value, 1.0, atol=1e-12)
    with assert_raises(contains="mass must be finite"):
        book.buy(Mass64(NAN), UnitPrice64(1))
    with assert_raises(contains="price must be finite"):
        book.sell(Mass64(1), UnitPrice64(-1))
    with assert_raises(contains="heat duty"):
        book.heat(Energy64(INF), price, 0.5)
    with assert_raises(contains="price must be finite"):
        book.heat(Energy64(1), EnergyPrice64(NAN), 0.5)
    with assert_raises(contains="efficiency"):
        book.heat(Energy64(1), price, 0)
    with assert_raises(contains="efficiency"):
        book.heat(Energy64(1), price, 1.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
