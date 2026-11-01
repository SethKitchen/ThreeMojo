# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the maps of `extensions.chemistry`.

The Ellingham lines of 2 C + O2 -> 2 CO and C + O2 -> CO2 must cross at
the Boudouard temperature, near 700 degC (973 K). Each boundary of a
predominance or oxide map must lie where its own reaction balances.
"""

from std.math import exp, inf, log
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import (
    carbon_dioxide,
    carbon_monoxide,
    chlorine,
    diamond,
    graphite,
    iron,
    magnetite,
    nitrogen,
    oxygen,
    rutile,
    titanium,
    titanium_tetrachloride_gas,
    wustite,
)
from extensions.chemistry.elements import (
    CARBON,
    OXYGEN,
    ElementCount,
    Formula,
    IRON,
    TITANIUM,
)
from extensions.chemistry.kinds import SOLID
from extensions.chemistry.quantities import MolarVolume64
from extensions.chemistry.kinds import KINETIC, PHYSICAL
from extensions.chemistry.maps import (
    Grid,
    LabelMap,
    boundary,
    ellingham,
    ellingham_crossing,
    oxide_map,
    oxygen_pressure,
    predominance,
    reducing_ratio,
    scan,
)
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.requirement import (
    Requirement,
    above,
    pressure_below,
)
from extensions.chemistry.thermo import Species, Substance, nasa7


def _iron_carbide() raises -> Substance:
    """A made-up FeC, to hold an element other than iron and oxygen."""
    var phases = List[Species]()
    phases.append(
        Species(
            "FeC",
            Formula([ElementCount(IRON, 1), ElementCount(CARBON, 1)]),
            SOLID,
            nasa7([200.0, 2000.0], [3.0, 0, 0, 0, 0, 0, 0]),
            MolarVolume64(0),
        )
    )
    return Substance("FeC", phases^)


from units.si import Pressure64
from units.temperature import Temperature64

comptime R = 8.31446261815324


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


def _co_line() raises -> Reaction:
    return Reaction(
        [
            reactant(graphite(), 2),
            reactant(oxygen()),
            product(carbon_monoxide(), 2),
        ]
    )


def _co2_line() raises -> Reaction:
    return Reaction(
        [reactant(graphite()), reactant(oxygen()), product(carbon_dioxide())]
    )


def _couple() raises -> Reaction:
    return Reaction(
        [
            reactant(carbon_monoxide(), 2),
            reactant(oxygen()),
            product(carbon_dioxide(), 2),
        ]
    )


def _iron_line() raises -> Reaction:
    return Reaction(
        [reactant(iron(), 2), reactant(oxygen()), product(wustite(), 2)]
    )


# --- grids ------------------------------------------------------------------


def test_scan_and_boundary() raises:
    var constraints: List[Requirement] = [
        above(KINETIC, _t(600), "hot", "x"),
        pressure_below(PHYSICAL, Pressure64(1e4), "thin", "x"),
    ]
    var grid = scan(
        constraints, _t(300), _t(1000), Pressure64(1e2), Pressure64(1e6), 36, 21
    )
    assert_true(grid.holds(35, 0))
    assert_true(not grid.holds(0, 0))
    assert_true(not grid.holds(35, 20))
    # 20 of 36 columns are above 600 K, and 10 of 21 rows below 1e4 Pa.
    assert_almost_equal(grid.share(), 20.0 * 10.0 / (36.0 * 21.0), atol=1e-12)
    var edges = boundary(grid)
    assert_true(len(edges) > 0)
    for e in edges:
        var near_t = (
            abs(e.t1.kelvin - 600) <= 20 and abs(e.t2.kelvin - 600) <= 20
        )
        var near_p = (
            abs(log(e.p1.value) / log(10.0) - 4) <= 0.2
            and abs(log(e.p2.value) / log(10.0) - 4) <= 0.2
        )
        assert_true(near_t or near_p)
    # No constraint: everything holds and there is no edge.
    var open = scan(
        List[Requirement](),
        _t(300),
        _t(1000),
        Pressure64(1),
        Pressure64(10),
        2,
        2,
    )
    assert_almost_equal(open.share(), 1.0, atol=0)
    assert_equal(len(boundary(open)), 0)


def test_every_marching_square() raises:
    # A 2 by 2 grid holds one cell. Each of its 16 corner cases gives no
    # edge, one edge, or two for the saddles.
    for corners in range(16):
        var grid = Grid(_t(300), _t(400), Pressure64(1), Pressure64(10), 2, 2)
        grid.held[0] = (corners & 1) != 0
        grid.held[1] = (corners & 2) != 0
        grid.held[3] = (corners & 4) != 0
        grid.held[2] = (corners & 8) != 0
        var expected = 1
        if corners == 0 or corners == 15:
            expected = 0
        elif corners == 5 or corners == 10:
            expected = 2
        assert_equal(len(boundary(grid)), expected)
    # Case 1, the lower-left corner: from the left edge to the bottom edge.
    var one = Grid(_t(300), _t(400), Pressure64(1), Pressure64(100), 2, 2)
    one.held[0] = True
    var e = boundary(one)[0]
    assert_almost_equal(e.t1.kelvin, 300.0, atol=1e-9)
    assert_almost_equal(e.p1.value, 10.0, atol=1e-9)
    assert_almost_equal(e.t2.kelvin, 350.0, atol=1e-9)
    assert_almost_equal(e.p2.value, 1.0, atol=1e-12)


def test_grid_refuses_bad_values() raises:
    var t1 = _t(300)
    var t2 = _t(400)
    var p1 = Pressure64(1)
    var p2 = Pressure64(10)
    with assert_raises(contains="temperature range"):
        _ = Grid(t2, t1, p1, p2, 2, 2)
    with assert_raises(contains="temperature range"):
        _ = Grid(_t(-1), t2, p1, p2, 2, 2)
    with assert_raises(contains="temperature range"):
        _ = Grid(t1, _t(inf[DType.float64]()), p1, p2, 2, 2)
    with assert_raises(contains="positive and increase"):
        _ = Grid(t1, t2, Pressure64(0), p2, 2, 2)
    with assert_raises(contains="positive and increase"):
        _ = Grid(t1, t2, p2, p1, 2, 2)
    with assert_raises(contains="finite and increase"):
        _ = Grid(t1, t2, p1, Pressure64(inf[DType.float64]()), 2, 2)
    with assert_raises(contains="2 to 2000 nodes"):
        _ = Grid(t1, t2, p1, p2, 1, 2)
    with assert_raises(contains="2 to 2000 nodes"):
        _ = Grid(t1, t2, p1, p2, 2, 2001)
    var grid = Grid(t1, t2, p1, p2, 2, 2)
    with assert_raises(contains="column is outside"):
        _ = grid.holds(-1, 0)
    with assert_raises(contains="column is outside"):
        _ = grid.holds(2, 0)
    with assert_raises(contains="row is outside"):
        _ = grid.holds(0, -1)
    with assert_raises(contains="row is outside"):
        _ = grid.holds(0, 2)


# --- Ellingham lines ----------------------------------------------------------


def test_ellingham_boudouard() raises:
    var crossing = ellingham_crossing(
        _co_line(), _co2_line(), _t(800), _t(1200)
    )
    assert_almost_equal(crossing.kelvin, 973.0, atol=5.0)
    # Per mole of O2: the CO line falls with temperature, the CO2 line is
    # almost flat.
    var low = ellingham(_co_line(), _t(500)).value
    var high = ellingham(_co_line(), _t(1500)).value
    assert_true(high < low)
    with assert_raises(contains="do not cross"):
        _ = ellingham_crossing(_co_line(), _co2_line(), _t(1100), _t(1200))
    with assert_raises(contains="temperature range"):
        _ = ellingham_crossing(_co_line(), _co2_line(), _t(1200), _t(1100))
    with assert_raises(contains="O2 gas as a reactant"):
        _ = ellingham(
            Reaction([reactant(graphite()), product(diamond())]), _t(1000)
        )


def test_oxygen_pressure_and_reducing_ratio() raises:
    var t = _t(1000)
    var p_o2 = oxygen_pressure(_iron_line(), t)
    # With pure O2 at that pressure, the oxidation is in balance.
    assert_almost_equal(_iron_line().delta_g(t, p_o2).value, 0.0, atol=1e-6)
    # With CO and CO2 at the ratio in balance, FeO + CO -> Fe + CO2 is too.
    var r = reducing_ratio(_couple(), _iron_line(), t)
    var x = r / (1 + r)
    var reduction = Reaction(
        [
            reactant(wustite()),
            reactant(carbon_monoxide(), 1, x),
            product(iron()),
            product(carbon_dioxide(), 1, 1 - x),
        ]
    )
    assert_almost_equal(
        reduction.delta_g(t, Pressure64(1e5)).value, 0.0, atol=1e-6
    )


# --- predominance ---------------------------------------------------------------


def _ti_candidates() raises -> List[Substance]:
    return [titanium(), rutile(), titanium_tetrachloride_gas()]


def test_titanium_predominance() raises:
    var t = _t(1000)
    var map = predominance(
        TITANIUM,
        _ti_candidates(),
        oxygen(),
        chlorine(),
        t,
        -40,
        0,
        -20,
        0,
        401,
        21,
    )
    assert_equal(map.name_at(400, 0), "TiO2")
    assert_equal(map.name_at(0, 20), "TiCl4(g)")
    assert_equal(map.name_at(0, 0), "Ti")
    # The TiO2 / TiCl4 boundary at one bar of Cl2: TiO2 + 2 Cl2 -> TiCl4 +
    # O2 balances where log10 p(O2) = -dG / (R T ln 10).
    var change = Reaction(
        [
            reactant(rutile()),
            reactant(chlorine(), 2),
            product(titanium_tetrachloride_gas()),
            product(oxygen()),
        ]
    ).delta_g(t, Pressure64(1e5))
    var edge = -change.value / (R * 1000 * log(10.0))
    var column = Int((edge + 40) / 0.1)
    assert_equal(map.name_at(column - 1, 20), "TiCl4(g)")
    assert_equal(map.name_at(column + 2, 20), "TiO2")
    assert_almost_equal(map.x(400), 0.0, atol=1e-12)
    assert_almost_equal(map.y(20), 0.0, atol=1e-12)


def test_predominance_refuses_bad_candidates() raises:
    var t = _t(1000)
    with assert_raises(contains="needs a candidate"):
        _ = predominance(
            TITANIUM,
            List[Substance](),
            oxygen(),
            chlorine(),
            t,
            -1,
            0,
            -1,
            0,
            2,
            2,
        )
    with assert_raises(contains="gas of one element"):
        _ = predominance(
            TITANIUM,
            _ti_candidates(),
            carbon_monoxide(),
            chlorine(),
            t,
            -1,
            0,
            -1,
            0,
            2,
            2,
        )
    with assert_raises(contains="gas of one element"):
        _ = predominance(
            TITANIUM,
            _ti_candidates(),
            oxygen(),
            rutile(),
            t,
            -1,
            0,
            -1,
            0,
            2,
            2,
        )
    with assert_raises(contains="lacks the base"):
        _ = predominance(
            TITANIUM, [graphite()], oxygen(), chlorine(), t, -1, 0, -1, 0, 2, 2
        )
    with assert_raises(contains="holds another element"):
        _ = predominance(
            TITANIUM,
            _ti_candidates(),
            oxygen(),
            nitrogen(),
            t,
            -1,
            0,
            -1,
            0,
            2,
            2,
        )


def _solid_oxygen() raises -> Substance:
    """A made-up solid O2, to test that a line needs O2 gas."""
    var phases = List[Species]()
    phases.append(
        Species(
            "O2(s)",
            Formula([ElementCount(OXYGEN, 2)]),
            SOLID,
            nasa7([20.0, 2000.0], [3.0, 0, 0, 0, 0, 0, 0]),
            MolarVolume64(0),
        )
    )
    return Substance("O2(s)", phases^)


def test_lines_need_oxygen_gas_used() raises:
    var t = _t(1000)
    # O2 as a product, and solid O2, are not an oxidation by O2 gas.
    var reduction = Reaction(
        [reactant(wustite(), 2), product(iron(), 2), product(oxygen())]
    )
    with assert_raises(contains="O2 gas as a reactant"):
        _ = ellingham(reduction, t)
    var solid = Reaction(
        [reactant(iron(), 2), reactant(_solid_oxygen()), product(wustite(), 2)]
    )
    with assert_raises(contains="O2 gas as a reactant"):
        _ = ellingham(solid, t)


def test_label_maps_refuse_bad_values() raises:
    var names: List[String] = ["a"]
    with assert_raises(contains="first axis"):
        _ = LabelMap(names.copy(), -inf[DType.float64](), 0, 0, 1, 2, 2)
    with assert_raises(contains="first axis"):
        _ = LabelMap(names.copy(), 1, 0, 0, 1, 2, 2)
    with assert_raises(contains="second axis"):
        _ = LabelMap(names.copy(), 0, 1, 0, inf[DType.float64](), 2, 2)
    with assert_raises(contains="2 to 2000 nodes"):
        _ = LabelMap(names.copy(), 0, 1, 0, 1, 2, 1)
    var map = LabelMap(names.copy(), 0, 1, 0, 1, 2, 2)
    assert_equal(map.name_at(1, 1), "a")
    with assert_raises(contains="column is outside"):
        _ = map.label(2, 0)
    with assert_raises(contains="column is outside"):
        _ = map.label(-1, 0)
    with assert_raises(contains="row is outside"):
        _ = map.label(0, 2)
    with assert_raises(contains="row is outside"):
        _ = map.label(0, -1)


# --- oxide maps -------------------------------------------------------------------


def test_iron_oxide_map() raises:
    var map = oxide_map(
        IRON,
        [iron(), wustite(), magnetite()],
        oxygen(),
        _couple(),
        _t(1000),
        _t(1300),
        0.01,
        0.99,
        4,
        99,
    )
    # At 1000 K, FeO + CO -> Fe + CO2 balances near 80 % CO in this data.
    var r = reducing_ratio(_couple(), _iron_line(), _t(1000))
    var edge = r / (1 + r)
    var row = Int((edge - 0.01) / 0.01)
    assert_equal(map.name_at(0, row - 1), "FeO")
    assert_equal(map.name_at(0, row + 2), "Fe")
    assert_equal(map.name_at(0, 0), "Fe3O4")
    with assert_raises(contains="between 0 and 1"):
        _ = oxide_map(
            IRON,
            [iron()],
            oxygen(),
            _couple(),
            _t(1000),
            _t(1100),
            0,
            0.5,
            2,
            2,
        )
    with assert_raises(contains="between 0 and 1"):
        _ = oxide_map(
            IRON,
            [iron()],
            oxygen(),
            _couple(),
            _t(1000),
            _t(1100),
            0.5,
            1,
            2,
            2,
        )
    with assert_raises(contains="temperature range"):
        _ = oxide_map(
            IRON,
            [iron()],
            oxygen(),
            _couple(),
            _t(1100),
            _t(1000),
            0.1,
            0.5,
            2,
            2,
        )
    with assert_raises(contains="needs a candidate"):
        _ = oxide_map(
            IRON,
            List[Substance](),
            oxygen(),
            _couple(),
            _t(1000),
            _t(1100),
            0.1,
            0.5,
            2,
            2,
        )
    with assert_raises(contains="lacks the base"):
        _ = oxide_map(
            IRON,
            [graphite()],
            oxygen(),
            _couple(),
            _t(1000),
            _t(1100),
            0.1,
            0.5,
            2,
            2,
        )
    with assert_raises(contains="holds another element"):
        _ = oxide_map(
            IRON,
            [iron(), _iron_carbide()],
            oxygen(),
            _couple(),
            _t(1000),
            _t(1100),
            0.1,
            0.5,
            2,
            2,
        )
    with assert_raises(contains="gas of one element"):
        _ = oxide_map(
            IRON,
            [iron()],
            carbon_monoxide(),
            _couple(),
            _t(1000),
            _t(1100),
            0.1,
            0.5,
            2,
            2,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
