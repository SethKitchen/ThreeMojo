# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the flowsheets and route search of `extensions.chemistry`.

The Kroll loop must settle to its stoichiometry: one mole of titanium per
mole of rutile, two moles each of magnesium and chlorine in the loops,
and every element in balance. The route search must find the Kroll route
and magnesiothermic reduction from rutile, and must not find carbothermic
reduction, which has no window below 1500 K.
"""

from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import (
    carbon_dioxide,
    chlorine,
    graphite,
    magnesia,
    magnesium,
    magnesium_chloride,
    oxygen,
    rutile,
    titanium,
    titanium_tetrachloride_gas,
)
from extensions.chemistry.elements import (
    CARBON,
    CHLORINE,
    MAGNESIUM,
    OXYGEN,
    TITANIUM,
)
from extensions.chemistry.flowsheet import (
    Flowsheet,
    MIXER,
    REACTOR,
    SPLITTER,
    StreamId,
    Unit,
    UnitKind,
)
from extensions.chemistry.processes.titanium import kroll_loop
from extensions.chemistry.quantities import ATMOSPHERE, Amount64, MOLE
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.routes import find_routes
from extensions.chemistry.thermo import Substance
from units.si import Pressure64
from units.temperature import Temperature64


def _mol(value: Float64) -> Amount64:
    return Amount64(value, MOLE)


def test_kroll_loop_settles() raises:
    var sheet = kroll_loop()
    var passes = sheet.solve()
    assert_true(passes > 2 and passes < 100)
    var sponge = StreamId(10)
    assert_equal(sheet.stream_names[sponge.value], "sponge")
    assert_almost_equal(sheet.amount(sponge, "Ti").value, 1.0, atol=1e-9)
    assert_almost_equal(
        sheet.amount(StreamId(2), "Cl2(g)").value, 2.0, atol=1e-9
    )
    assert_almost_equal(sheet.amount(StreamId(3), "Mg").value, 2.0, atol=1e-9)
    var offgas = StreamId(7)
    assert_almost_equal(sheet.amount(offgas, "CO2(g)").value, 1.0, atol=1e-9)
    assert_almost_equal(sheet.amount(offgas, "Cl2(g)").value, 0.1, atol=1e-9)
    for e in [TITANIUM, CHLORINE, MAGNESIUM, CARBON, OXYGEN]:
        assert_almost_equal(sheet.net(e), 0.0, atol=1e-9)


def _small() raises -> Flowsheet:
    return Flowsheet(
        [
            rutile(),
            chlorine(),
            graphite(),
            titanium_tetrachloride_gas(),
            carbon_dioxide(),
        ]
    )


def _chlorination() raises -> Reaction:
    return Reaction(
        [
            reactant(rutile()),
            reactant(chlorine(), 2),
            reactant(graphite()),
            product(titanium_tetrachloride_gas()),
            product(carbon_dioxide()),
        ]
    )


def test_units() raises:
    var sheet = _small()
    var a = sheet.add_stream("a")
    var b = sheet.add_stream("b")
    var mixed = sheet.add_stream("mixed")
    var reacted = sheet.add_stream("reacted")
    var top = sheet.add_stream("top")
    var bottom = sheet.add_stream("bottom")
    # Chlorine is limiting: 1 mol of Cl2 against 1 mol of rutile and C.
    sheet.set_feed(a, ["TiO2", "graphite"], [_mol(1), _mol(1)])
    sheet.set_feed(b, ["Cl2(g)"], [_mol(1)])
    sheet.mixer("mix", [a, b], mixed)
    sheet.reactor("chlorinate", mixed, reacted, _chlorination(), 0.5)
    sheet.splitter(
        "split", reacted, top, bottom, ["TiCl4(g)", "CO2(g)"], [1, 0.25]
    )
    _ = sheet.solve()
    # Half of the limiting extent of 0.5.
    assert_almost_equal(
        sheet.amount(reacted, "TiCl4(g)").value, 0.25, atol=1e-12
    )
    assert_almost_equal(sheet.amount(reacted, "Cl2(g)").value, 0.5, atol=1e-12)
    assert_almost_equal(sheet.amount(top, "CO2(g)").value, 0.0625, atol=1e-12)
    assert_almost_equal(
        sheet.amount(bottom, "CO2(g)").value, 0.1875, atol=1e-12
    )
    assert_almost_equal(sheet.amount(bottom, "TiO2").value, 0.75, atol=1e-12)
    for e in [TITANIUM, CHLORINE, CARBON, OXYGEN]:
        assert_almost_equal(sheet.net(e), 0.0, atol=1e-12)
    # Rutile limiting: plenty of chlorine.
    var rich = _small()
    var f = rich.add_stream("f")
    var out = rich.add_stream("out")
    rich.set_feed(
        f, ["TiO2", "Cl2(g)", "graphite"], [_mol(1), _mol(5), _mol(2)]
    )
    rich.reactor("chlorinate", f, out, _chlorination(), 1)
    _ = rich.solve()
    assert_almost_equal(rich.amount(out, "TiO2").value, 0.0, atol=1e-12)
    assert_almost_equal(rich.amount(out, "Cl2(g)").value, 3.0, atol=1e-12)


def test_kinds() raises:
    assert_true(MIXER.is_valid())
    assert_false(UnitKind(3).is_valid())
    assert_equal(MIXER.name(), "mixer")
    assert_equal(REACTOR.name(), "reactor")
    assert_equal(SPLITTER.name(), "splitter")
    assert_equal(UnitKind(-1).name(), "?")
    assert_true(StreamId(0).is_valid())
    assert_false(StreamId(-1).is_valid())
    with assert_raises(contains="unit kind is not valid"):
        _ = Unit(
            "x",
            UnitKind(7),
            List[StreamId](),
            List[StreamId](),
            List[Float64](),
            0,
            List[Float64](),
        )


def test_bad_sheets() raises:
    with assert_raises(contains="needs a component"):
        _ = Flowsheet(List[Substance]())
    with assert_raises(contains="share a name"):
        _ = Flowsheet([rutile(), rutile()])
    var sheet = _small()
    var a = sheet.add_stream("a")
    var b = sheet.add_stream("b")
    var c = sheet.add_stream("c")
    with assert_raises(contains="needs a unit"):
        _ = sheet.solve()
    with assert_raises(contains="out of range"):
        sheet.set_feed(StreamId(-1), ["TiO2"], [_mol(1)])
    with assert_raises(contains="out of range"):
        sheet.set_feed(StreamId(9), ["TiO2"], [_mol(1)])
    with assert_raises(contains="one amount per"):
        sheet.set_feed(a, ["TiO2", "graphite"], [_mol(1)])
    with assert_raises(contains="not negative"):
        sheet.set_feed(a, ["TiO2"], [_mol(-1)])
    with assert_raises(contains="not negative"):
        sheet.set_feed(a, ["TiO2"], [_mol(nan[DType.float64]())])
    with assert_raises(contains="No component is named 'Ti'"):
        sheet.set_feed(a, ["Ti"], [_mol(1)])
    with assert_raises(contains="needs an inlet"):
        sheet.mixer("m", List[StreamId](), b)
    sheet.set_feed(a, ["TiO2"], [_mol(1)])
    with assert_raises(contains="one source"):
        sheet.mixer("m", [b], a)
    sheet.mixer("m", [a], b)
    with assert_raises(contains="cannot be a feed"):
        sheet.set_feed(b, ["TiO2"], [_mol(1)])
    with assert_raises(contains="one source"):
        sheet.mixer("again", [c], b)
    with assert_raises(contains="goes to one unit"):
        sheet.mixer("twice", [a], c)
    with assert_raises(contains="conversion must lie"):
        sheet.reactor("r", b, c, _chlorination(), -0.1)
    with assert_raises(contains="conversion must lie"):
        sheet.reactor("r", b, c, _chlorination(), 1.1)
    var other = Reaction([reactant(magnesium()), product(magnesium())])
    with assert_raises(contains="No component is named 'Mg'"):
        sheet.reactor("r", b, c, other, 1)
    with assert_raises(contains="one share per"):
        sheet.splitter("s", b, c, a, ["TiO2"], List[Float64]())
    with assert_raises(contains="share must lie"):
        sheet.splitter("s", b, c, a, ["TiO2"], [1.5])
    with assert_raises(contains="share must lie"):
        sheet.splitter("s", b, c, a, ["TiO2"], [-0.5])
    with assert_raises(contains="out of range"):
        _ = sheet.amount(StreamId(5), "TiO2")


def test_empty_parts() raises:
    var sheet = _small()
    assert_almost_equal(sheet.net(TITANIUM), 0.0, atol=0)
    var a = sheet.add_stream("a")
    var b = sheet.add_stream("b")
    var c = sheet.add_stream("c")
    sheet.set_feed(a, List[String](), List[Amount64]())
    sheet.set_guess(b, List[String](), List[Amount64]())
    # No named share: everything goes to the second outlet.
    sheet.splitter("s", a, b, c, List[String](), List[Float64]())
    with assert_raises(contains="did not settle"):
        _ = sheet.solve(0)
    var none = find_routes(
        List[Reaction](),
        List[String](),
        "Ti",
        Temperature64(600),
        Temperature64(1500),
        Pressure64(1e5),
        2,
    )
    assert_equal(len(none), 0)


def test_a_loop_that_grows() raises:
    # A feed that recycles forever without a purge never settles.
    var sheet = _small()
    var feed = sheet.add_stream("feed")
    var loop = sheet.add_stream("loop")
    var mixed = sheet.add_stream("mixed")
    var purge = sheet.add_stream("purge")
    sheet.set_feed(feed, ["TiO2"], [_mol(1)])
    sheet.mixer("m", [feed, loop], mixed)
    sheet.splitter("s", mixed, loop, purge, ["TiO2"], [1])
    with assert_raises(contains="did not settle"):
        _ = sheet.solve(50)


def _library() raises -> List[Reaction]:
    return [
        # 0: carbothermic reduction: no window below 1500 K.
        Reaction(
            [
                reactant(rutile()),
                reactant(graphite()),
                product(titanium()),
                product(carbon_dioxide()),
            ]
        ),
        # 1: chlorination.
        Reaction(
            [
                reactant(rutile()),
                reactant(chlorine(), 2),
                reactant(graphite()),
                product(titanium_tetrachloride_gas()),
                product(carbon_dioxide()),
            ]
        ),
        # 2: the Kroll reduction.
        Reaction(
            [
                reactant(titanium_tetrachloride_gas()),
                reactant(magnesium(), 2),
                product(titanium()),
                product(magnesium_chloride(), 2),
            ]
        ),
        # 3: magnesiothermic reduction of rutile.
        Reaction(
            [
                reactant(rutile()),
                reactant(magnesium(), 2),
                product(titanium()),
                product(magnesia(), 2),
            ]
        ),
        # 4: burning carbon makes nothing new: CO2 is on hand.
        Reaction(
            [
                reactant(graphite()),
                reactant(oxygen()),
                product(carbon_dioxide()),
            ]
        ),
    ]


def test_routes_to_titanium() raises:
    var feeds: List[String] = [
        "TiO2",
        "graphite",
        "Cl2(g)",
        "Mg",
        "O2(g)",
        "CO2(g)",
    ]
    var t1 = Temperature64(600)
    var t2 = Temperature64(1500)
    var p = Pressure64(1, ATMOSPHERE)
    var routes = find_routes(_library(), feeds, "Ti", t1, t2, p, 3)
    assert_equal(len(routes), 2)
    assert_equal(len(routes[0]), 1)
    assert_equal(routes[0][0], 3)
    assert_equal(len(routes[1]), 2)
    assert_equal(routes[1][0], 1)
    assert_equal(routes[1][1], 2)
    var first = find_routes(_library(), feeds, "Ti", t1, t2, p, 3, 1)
    assert_equal(len(first), 1)
    var at_hand = find_routes(_library(), feeds, "Mg", t1, t2, p, 1)
    assert_equal(len(at_hand), 1)
    assert_equal(len(at_hand[0]), 0)
    var none = find_routes(_library(), feeds, "Fe", t1, t2, p, 2)
    assert_equal(len(none), 0)
    with assert_raises(contains="1 to 8 steps"):
        _ = find_routes(_library(), feeds, "Ti", t1, t2, p, 0)
    with assert_raises(contains="1 to 8 steps"):
        _ = find_routes(_library(), feeds, "Ti", t1, t2, p, 9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
