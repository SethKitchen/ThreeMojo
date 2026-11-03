# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the equilibrium solver of `extensions.chemistry`.

Each multiphase result is checked against a closed form:

- At the temperature where C + CO2 = 2 CO has K = 1 at one bar, excess
  carbon leaves a CO mole fraction x with x^2 / (1 - x) = 1: the golden
  ratio, 0.618034.
- Limestone in argon leaves CO2 at its decomposition pressure while
  calcite and lime coexist, and all lime once the CO2 is spent.
- H2 = 2 H at 3000 K gives x^2 / (1 - x) = K.
"""

from std.math import exp, inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import (
    argon,
    atomic_hydrogen,
    calcite,
    carbon_dioxide,
    carbon_monoxide,
    chlorine,
    diamond,
    graphite,
    hydrogen,
    lime,
    oxygen,
    rutile,
    titanium_tetrachloride_gas,
)
from extensions.chemistry.elements import CALCIUM, IRON, TITANIUM, Element
from extensions.chemistry.equilibrium import (
    Charge,
    Equilibrium,
    EquilibriumShare,
    equilibrate,
)
from extensions.chemistry.quantities import Amount64, MOLE
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.thermo import Substance
from extensions.chemistry.window import met_intervals
from units.si import Pressure64
from units.temperature import Temperature64

comptime BAR = 1e5
comptime ATM = 101325.0


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


def _mol(value: Float64) -> Amount64:
    return Amount64(value, MOLE)


def _carbon_gases() raises -> List[Substance]:
    return [graphite(), carbon_monoxide(), carbon_dioxide(), oxygen()]


def _boudouard_feed() raises -> List[Charge]:
    var feed = List[Charge]()
    feed.append(Charge(graphite(), _mol(5)))
    feed.append(Charge(carbon_dioxide(), _mol(1)))
    return feed^


def test_boudouard_golden_ratio() raises:
    var p = Pressure64(BAR)
    var crossing = Reaction(
        [
            reactant(graphite()),
            reactant(carbon_dioxide()),
            product(carbon_monoxide(), 2),
        ]
    ).equilibrium_temperature(_t(800), _t(1200), p)
    var result = equilibrate(_carbon_gases(), _boudouard_feed(), crossing, p)
    assert_almost_equal(
        result.mole_fraction("CO(g)"), (sqrt(5.0) - 1) / 2, atol=1e-8
    )
    assert_true(result.amount_of("graphite").value > 4)
    assert_true(result.iterations > 0)
    # Element balance: 6 C and 2 O.
    var c = (
        result.amount_of("graphite").value
        + result.amount_of("CO(g)").value
        + result.amount_of("CO2(g)").value
    )
    assert_almost_equal(c, 6.0, atol=1e-9)


def test_calcination_in_argon() raises:
    var p = Pressure64(ATM)
    var candidates: List[Substance] = [
        calcite(),
        lime(),
        carbon_dioxide(),
        argon(),
        oxygen(),
        carbon_monoxide(),
    ]
    var feed = List[Charge]()
    feed.append(Charge(calcite(), _mol(1)))
    feed.append(Charge(argon(), _mol(1)))
    var calc = Reaction(
        [reactant(calcite()), product(lime()), product(carbon_dioxide())]
    )
    # Below the decomposition point both solids stay, and the CO2 sits at
    # its decomposition pressure.
    var both = equilibrate(candidates, feed, _t(1050), p)
    var p_eq = calc.equilibrium_pressure(
        _t(1050), Pressure64(1e-3), Pressure64(1e7)
    )
    assert_almost_equal(
        both.mole_fraction("CO2(g)"), p_eq.value / ATM, atol=1e-8
    )
    assert_true(both.amount_of("CaCO3").value > 0.5)
    assert_almost_equal(
        both.amount_of("CaCO3").value + both.amount_of("CaO").value,
        1.0,
        atol=1e-9,
    )
    assert_almost_equal(both.share(CALCIUM, "CaO"), both.amount_of("CaO").value)
    # Hotter, the calcite would need more CO2 than there is: it all goes.
    var spent = equilibrate(candidates, feed, _t(1150), p)
    assert_almost_equal(spent.amount_of("CaCO3").value, 0.0, atol=0)
    assert_almost_equal(spent.amount_of("CaO").value, 1.0, atol=1e-9)
    # Above 1200 K the calcite data stops, so calcite does not take part.
    var hot = equilibrate(candidates, feed, _t(1300), p)
    with assert_raises(contains="No substance named 'CaCO3'"):
        _ = hot.amount_of("CaCO3")
    # The candidates in the other order give the same answer.
    var reversed: List[Substance] = [
        lime(),
        calcite(),
        carbon_dioxide(),
        argon(),
    ]
    var again = equilibrate(reversed, feed, _t(1050), p)
    assert_almost_equal(
        again.amount_of("CaO").value, both.amount_of("CaO").value, atol=1e-7
    )


def test_hydrogen_dissociation() raises:
    var p = Pressure64(BAR)
    var feed = List[Charge]()
    feed.append(Charge(hydrogen(), _mol(1)))
    var result = equilibrate([hydrogen(), atomic_hydrogen()], feed, _t(3000), p)
    var change = Reaction(
        [reactant(hydrogen()), product(atomic_hydrogen(), 2)]
    ).delta_g(_t(3000), p)
    var k = exp(-change.value / (8.31446261815324 * 3000))
    var x = (-k + sqrt(k * k + 4 * k)) / 2
    assert_almost_equal(result.mole_fraction("H(g)"), x, atol=1e-9)


def test_chlorination_and_stable_forms() raises:
    var p = Pressure64(ATM)
    var candidates: List[Substance] = [
        rutile(),
        chlorine(),
        graphite(),
        diamond(),
        titanium_tetrachloride_gas(),
        carbon_dioxide(),
        carbon_monoxide(),
        oxygen(),
    ]
    var feed = List[Charge]()
    feed.append(Charge(rutile(), _mol(1)))
    feed.append(Charge(chlorine(), _mol(2.05)))
    feed.append(Charge(graphite(), _mol(1.2)))
    var result = equilibrate(candidates, feed, _t(1273), p)
    assert_true(result.share(TITANIUM, "TiCl4(g)") > 0.999)
    # Diamond is metastable, so it does not form.
    assert_almost_equal(result.amount_of("diamond").value, 0.0, atol=0)


def test_candidates_outside_the_charge() raises:
    var p = Pressure64(BAR)
    # Rutile holds titanium, which the charge lacks, so it is left out.
    var candidates = _carbon_gases()
    candidates.append(rutile())
    var result = equilibrate(candidates, _boudouard_feed(), _t(1000), p)
    with assert_raises(contains="No substance named 'TiO2'"):
        _ = result.amount_of("TiO2")
    with assert_raises(contains="mole fraction is of a gas"):
        _ = result.mole_fraction("graphite")
    with assert_raises(contains="No substance at equilibrium holds"):
        _ = result.share(IRON, "graphite")


def test_bad_problems() raises:
    var p = Pressure64(BAR)
    var t = _t(1000)
    with assert_raises(contains="needs a charge"):
        _ = equilibrate(_carbon_gases(), List[Charge](), t, p)
    var negative = List[Charge]()
    negative.append(Charge(graphite(), _mol(-1)))
    with assert_raises(contains="not negative"):
        _ = equilibrate(_carbon_gases(), negative, t, p)
    var nan_charge = List[Charge]()
    nan_charge.append(Charge(graphite(), _mol(nan[DType.float64]())))
    with assert_raises(contains="not negative"):
        _ = equilibrate(_carbon_gases(), nan_charge, t, p)
    var twice = _carbon_gases()
    twice.append(oxygen())
    with assert_raises(contains="Two candidates are named 'O2(g)'"):
        _ = equilibrate(twice, _boudouard_feed(), t, p)
    with assert_raises(contains="needs a gas candidate"):
        _ = equilibrate(List[Substance](), _boudouard_feed(), t, p)
    with assert_raises(contains="needs a gas candidate"):
        _ = equilibrate([graphite()], _boudouard_feed(), t, p)
    with assert_raises(contains="does not reach the temperature"):
        _ = equilibrate(_carbon_gases(), _boudouard_feed(), _t(9000), p)
    var mixed = List[Charge]()
    mixed.append(Charge(hydrogen(), _mol(1)))
    mixed.append(Charge(graphite(), _mol(1)))
    with assert_raises(contains="No candidate holds C"):
        _ = equilibrate([hydrogen(), atomic_hydrogen()], mixed, t, p)
    # Carbon and lime: the candidates CO2 and CaO hold carbon only with
    # twice its oxygen, which the charge does not have.
    var lean = List[Charge]()
    lean.append(Charge(graphite(), _mol(1)))
    lean.append(Charge(lime(), _mol(1)))
    with assert_raises(contains="cannot hold the charge's elements"):
        _ = equilibrate([carbon_dioxide(), lime(), argon()], lean, t, p)
    with assert_raises(contains="above absolute zero"):
        _ = equilibrate(_carbon_gases(), _boudouard_feed(), _t(-1), p)
    with assert_raises(contains="pressure must be finite"):
        _ = equilibrate(_carbon_gases(), _boudouard_feed(), t, Pressure64(0))
    with assert_raises(contains="pressure must be finite"):
        _ = equilibrate(
            _carbon_gases(),
            _boudouard_feed(),
            t,
            Pressure64(inf[DType.float64]()),
        )
    with assert_raises(contains="did not converge"):
        _ = equilibrate(_carbon_gases(), _boudouard_feed(), t, p, 1)
    with assert_raises(contains="did not converge"):
        _ = equilibrate(_carbon_gases(), _boudouard_feed(), t, p, 0)
    with assert_raises(contains="did not settle"):
        _ = equilibrate(_carbon_gases(), _boudouard_feed(), t, p, 100, 0)
    # Carbon-rich gas with no solid carbon to hold the excess.
    with assert_raises(contains="No set of these candidates"):
        _ = equilibrate(
            [carbon_monoxide(), carbon_dioxide(), oxygen()],
            _boudouard_feed(),
            t,
            p,
        )


def test_an_empty_result() raises:
    var empty = Equilibrium(
        List[Substance](), List[Float64](), _t(300), Pressure64(BAR), 0
    )
    assert_almost_equal(empty.gas_amount().value, 0.0, atol=0)
    with assert_raises(contains="No substance named"):
        _ = empty.amount_of("x")
    with assert_raises(contains="No substance at equilibrium holds"):
        _ = empty.share(TITANIUM, "x")


def _chlorination() raises -> EquilibriumShare:
    var feed = List[Charge]()
    feed.append(Charge(rutile(), _mol(1)))
    feed.append(Charge(chlorine(), _mol(2)))
    feed.append(Charge(graphite(), _mol(1)))
    return EquilibriumShare(
        [
            rutile(),
            chlorine(),
            graphite(),
            titanium_tetrachloride_gas(),
            carbon_dioxide(),
            carbon_monoxide(),
            oxygen(),
        ],
        feed^,
        TITANIUM,
        "TiCl4(g)",
        0.99,
    )


def test_equilibrium_share_constraint() raises:
    var p = Pressure64(ATM)
    var share = _chlorination()
    assert_true(share.holds(_t(1273), p))
    var text = share.describe(_t(1273), p)
    assert_true(text.startswith("Ti in TiCl4(g): "))
    assert_true(text.endswith(" of 0.9900 needed"))
    var met = met_intervals(share, _t(900), _t(1500), p, 20)
    assert_equal(len(met), 1)
    # A share of a whole mole of chlorine per titanium short of TiCl4 is
    # not met.
    var feed = List[Charge]()
    feed.append(Charge(rutile(), _mol(1)))
    feed.append(Charge(chlorine(), _mol(1)))
    feed.append(Charge(graphite(), _mol(1)))
    var short = EquilibriumShare(
        [
            rutile(),
            chlorine(),
            graphite(),
            titanium_tetrachloride_gas(),
            carbon_dioxide(),
            carbon_monoxide(),
            oxygen(),
        ],
        feed^,
        TITANIUM,
        "TiCl4(g)",
        0.99,
    )
    assert_false(short.holds(_t(1273), p))
    with assert_raises(contains="in the table"):
        _ = EquilibriumShare(
            List[Substance](), List[Charge](), Element(0), "x", 0.5
        )
    with assert_raises(contains="share must be above 0"):
        _ = EquilibriumShare(
            List[Substance](), List[Charge](), TITANIUM, "x", 0
        )
    with assert_raises(contains="share must be above 0"):
        _ = EquilibriumShare(
            List[Substance](), List[Charge](), TITANIUM, "x", 1.5
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
