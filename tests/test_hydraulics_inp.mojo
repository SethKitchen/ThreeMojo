# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the EPANET input files of `extensions.hydraulics`.

The format and the US head loss formula are those of Rossman, "EPANET 2
Users Manual", EPA/600/R-00/057, 2000, appendix C and table 3.1:
h = 4.727 C^-1.852 d^-4.871 L q^1.852, in feet and cubic feet per second.
The other references are the same networks built in code.
"""

from std.math import pi
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.hydraulics.headloss import GRAVITY, hazen_williams
from extensions.hydraulics.inp import InpNetwork, flow_unit, parse_inp, read_inp
from extensions.hydraulics.kinds import DARCY_WEISBACH, CHEZY_MANNING, PUMP
from extensions.hydraulics.network import PipeNetwork, WATER_VISCOSITY
from extensions.hydraulics.solve import default_options, solve_network
from tests.test_scratch import TestScratch, temporary_path
from units.si import (
    CUBIC_METER_PER_SECOND,
    FOOT,
    Length64,
    METER,
    VolumeFlowRate64,
)

comptime _US = """[TITLE]
A reservoir and one pipe ; the title has two lines
in US units

[JUNCTIONS]
;ID   Elev   Demand
 J1   50     500

[RESERVOIRS]
 R1   200

[PIPES]
;ID  Node1  Node2  Length  Diameter  Roughness  MinorLoss  Status
 P1  R1     J1     1000    12        100        0          Open

[COORDINATES]
 J1  10  20

[END]
"""

comptime _SI = """[TITLE]
Two loops in SI units
[OPTIONS]
 Units          LPS
 Headloss       H-W
 Accuracy       1e-10
 Trials         200
 Quality        None
[JUNCTIONS]
 A  20  30
 B  22  50
 C  18  40
 D  25  20
[RESERVOIRS]
 High  60
[TANKS]
;ID   Elev  InitLevel  MinLevel  MaxLevel  Diameter
 Low  50    2          0         5         10
[PIPES]
 1  High  A  600  350  120
 2  A     B  400  250  110  1
 3  A     C  500  250  100
 4  B     D  450  200  130
 5  C     D  350  200  100  0.5
 6  B     C  300  150  130
 7  Low   D  700  300  120
[END]
"""


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _lps(v: Float64) -> VolumeFlowRate64:
    return VolumeFlowRate64(v / 1000, CUBIC_METER_PER_SECOND)


def test_us_file_meets_the_epanet_formula() raises:
    """A reservoir at 200 ft, 1000 ft of 12 in pipe and 500 gal/min.

    Reference: the US formula of EPANET, with the flow in cubic feet per
    second and the diameter in feet. The SI formula of this port gives
    the same loss within 0.1%. The defaults are gallons per minute and
    Hazen-Williams.
    """
    var file = parse_inp(_US)
    assert_equal(file.title, "A reservoir and one pipe in US units")
    assert_equal(len(file.node_names), 2)
    assert_equal(file.node_names[0], "J1")
    assert_equal(file.link_names[0], "P1")
    assert_almost_equal(file.options.accuracy, 0.001, atol=0)
    assert_equal(file.options.iterations, 40)
    var result = solve_network(file.network, default_options())
    var flow = 500 * 231 / 1728.0 / 60
    var loss = 4.727 * 100.0**-1.852 * 1000 * flow**1.852
    var head = result.head(file.node("j1")).to(FOOT)
    assert_true(abs((200 - head) / loss - 1) < 1e-3, String(head))
    assert_almost_equal(
        result.pressure_head(file.node("J1")).to(FOOT), head - 50, atol=1e-9
    )
    assert_almost_equal(
        result.flow(file.link("p1")).to(CUBIC_METER_PER_SECOND),
        flow * 0.3048**3,
        atol=1e-12,
    )
    with assert_raises(contains="no node J9"):
        _ = file.node("J9")
    with assert_raises(contains="no link P9"):
        _ = file.link("P9")


def test_si_file_matches_the_network_built_in_code() raises:
    """Two loops, a reservoir and a tank, in liters per second.

    Reference: the same network built with `PipeNetwork`. A length is in
    meters and a diameter in millimeters. The tank is a node of fixed
    head at its elevation plus its first level.
    """
    var file = parse_inp(_SI)
    assert_almost_equal(file.options.accuracy, 1e-10, atol=0)
    assert_equal(file.options.iterations, 200)
    var network = PipeNetwork()
    var a = network.add_junction(_m(20), _lps(30))
    var b = network.add_junction(_m(22), _lps(50))
    var c = network.add_junction(_m(18), _lps(40))
    var d = network.add_junction(_m(25), _lps(20))
    var high = network.add_reservoir(_m(60))
    var low = network.add_reservoir(_m(52))
    _ = network.add_pipe(high, a, _m(600), _m(0.35), hazen_williams(120), 0)
    _ = network.add_pipe(a, b, _m(400), _m(0.25), hazen_williams(110), 1)
    _ = network.add_pipe(a, c, _m(500), _m(0.25), hazen_williams(100), 0)
    _ = network.add_pipe(b, d, _m(450), _m(0.2), hazen_williams(130), 0)
    _ = network.add_pipe(c, d, _m(350), _m(0.2), hazen_williams(100), 0.5)
    _ = network.add_pipe(b, c, _m(300), _m(0.15), hazen_williams(130), 0)
    _ = network.add_pipe(low, d, _m(700), _m(0.3), hazen_williams(120), 0)
    var expected = solve_network(network, default_options())
    var got = solve_network(file.network, file.options)
    for n in range(6):
        assert_almost_equal(got.heads[n], expected.heads[n], atol=1e-9)
    for l in range(7):
        assert_almost_equal(got.flows[l], expected.flows[l], atol=1e-12)
    assert_equal(file.node("LOW").value, 5)
    assert_equal(file.link("7").value, 6)


def _swap_si(old: String, new: String) raises -> InpNetwork:
    assert_true(old in String(_SI), old)
    return parse_inp(String(_SI).replace(old, new))


def test_options_and_patterns() raises:
    """The options that change a steady result, and the demand patterns.

    Reference: a demand is its base value times the demand multiplier and
    the first multiplier of its pattern. A roughness for Darcy-Weisbach
    is in millimeters, or in thousandths of a foot with a US flow unit.
    """
    var darcy = _swap_si("Headloss       H-W", "Headloss       D-W")
    assert_true(darcy.network.links[0].roughness.formula == DARCY_WEISBACH)
    assert_almost_equal(
        darcy.network.links[0].roughness.value, 0.12, atol=1e-15
    )
    var manning = _swap_si("Headloss       H-W", "Headloss       C-M")
    assert_true(manning.network.links[0].roughness.formula == CHEZY_MANNING)
    var feet = parse_inp(
        String(_US).replace(
            "[JUNCTIONS]", "[OPTIONS]\n Headloss D-W\n[JUNCTIONS]"
        )
    )
    assert_almost_equal(
        feet.network.links[0].roughness.value, 100 * 0.3048 / 1000, atol=1e-15
    )
    var thick = _swap_si("Quality        None", "Viscosity      2.5")
    assert_almost_equal(
        thick.network.viscosity, 2.5 * WATER_VISCOSITY, atol=1e-20
    )
    var scaled = _swap_si(
        "Quality        None",
        "Demand Multiplier 2\n Pattern        Day\n[PATTERNS]\n Day 1.5 0.8\n"
        + " Day 0.6\n Night 0.5\n[OPTIONS]",
    )
    # 30 L/s times 2 times 1.5.
    assert_almost_equal(scaled.network.demands[0], 0.09, atol=1e-15)
    var night = _swap_si(
        " A  20  30\n",
        " A  20  30  Night\n[PATTERNS]\n Night 0.5\n[JUNCTIONS]\n",
    )
    assert_almost_equal(night.network.demands[0], 0.015, atol=1e-15)
    assert_almost_equal(night.network.demands[1], 0.05, atol=1e-15)
    # A junction with no demand, and a pattern named 1 that is the default.
    var plain = _swap_si(
        " A  20  30\n", " A  20\n[PATTERNS]\n 1 3\n[JUNCTIONS]\n"
    )
    assert_almost_equal(plain.network.demands[0], 0.0, atol=0)
    assert_almost_equal(plain.network.demands[1], 0.15, atol=1e-15)
    var units = [
        "CFS",
        "GPM",
        "MGD",
        "IMGD",
        "AFD",
        "LPS",
        "LPM",
        "MLD",
        "CMH",
        "CMD",
    ]
    var factors = [
        0.028316846592,
        6.30901964e-5,
        0.0438126364,
        0.0526167824,
        0.0142764102,
        0.001,
        1.6666666667e-5,
        0.0115740741,
        2.7777777778e-4,
        1.1574074074e-5,
    ]
    for i in range(10):
        assert_true(abs(flow_unit(units[i]) / factors[i] - 1) < 1e-8, units[i])
        var file = _swap_si("Units          LPS", "Units          " + units[i])
        assert_almost_equal(
            file.network.demands[0],
            30 * factors[i],
            atol=1e-8 * 30 * factors[i],
        )
        # The first five units are US units, with lengths in feet.
        var length = 600.0
        if i < 5:
            length = 600 * 0.3048
        assert_almost_equal(file.network.links[0].length, length, atol=1e-12)


def test_pump_with_a_head_curve() raises:
    """A pump with a curve of one point lifts water to a reservoir.

    Reference: the same pump built in code, with the design flow and the
    design head of the curve.
    """
    var text = String(_SI).replace(
        "[END]",
        "[RESERVOIRS]\n Well 10\n[PUMPS]\n 9 Well A HEAD C1 ; a comment\n"
        + "[CURVES]\n C1 40 55\n C2 10 30\n C2 20 25\n[END]",
    )
    var file = parse_inp(text)
    assert_equal(len(file.network.links), 8)
    ref pump = file.network.links[file.link("9").value]
    assert_true(pump.kind == PUMP)
    assert_almost_equal(pump.shutoff, 4 * 55.0 / 3, atol=1e-12)
    assert_almost_equal(pump.curve, 55 / (3 * 0.04 * 0.04), atol=1e-9)
    var result = solve_network(file.network, default_options())
    assert_true(result.flow(file.link("9")).to(CUBIC_METER_PER_SECOND) > 0)
    with assert_raises(contains="one point"):
        _ = parse_inp(text.replace("HEAD C1", "HEAD C2"))
    with assert_raises(contains="one point"):
        _ = parse_inp(text.replace("HEAD C1", "HEAD C7"))
    with assert_raises(contains="HEAD and a curve"):
        _ = parse_inp(text.replace("HEAD C1", "POWER 50"))
    with assert_raises(contains="HEAD and a curve"):
        _ = parse_inp(text.replace("HEAD C1", "HEAD"))
    with assert_raises(contains="an x and a y"):
        _ = parse_inp(text.replace("C1 40 55", "C1 40"))
    with assert_raises(contains="link 7 repeats"):
        _ = parse_inp(text.replace("9 Well A", "7 Well A"))


def test_inp_file() raises:
    var path = temporary_path("net.inp")
    Path(path).write_text(_SI)
    assert_equal(len(read_inp(path).network.links), 7)


def _refuse(old: String, new: String, part: String) raises:
    assert_true(old in String(_SI), old)
    with assert_raises(contains=part):
        _ = parse_inp(String(_SI).replace(old, new))


def test_inp_refusals() raises:
    _refuse("[TITLE]", "stray\n[TITLE]", "before a section")
    _refuse("Units          LPS", "Units", "needs a value")
    _refuse("Units          LPS", "Units          XYZ", "not an EPANET unit")
    _refuse("Headloss       H-W", "Headloss       X", "H-W, D-W or C-M")
    _refuse("Accuracy       1e-10", "Accuracy       tight", "is not a number")
    _refuse("Accuracy       1e-10", "Accuracy       1e999", "must be finite")
    _refuse(" A  20  30\n", " A\n", "a name and an elevation")
    _refuse(" A  20  30\n", " A  20  30  Noon\n", "no pattern NOON")
    _refuse(" B  22  50\n", " A  22  50\n", "node A repeats")
    _refuse(" High  60\n", " High\n", "a name and a head")
    _refuse(" Low  50    2 ", " Low  50 ;", "a first level")
    _refuse(
        " 1  High  A  600  350  120", " 1  High  A  600  350", "a roughness"
    )
    _refuse(
        " 2  A     B  400  250  110  1",
        " 2  A     B  400  250  110  1  CV",
        "must be OPEN",
    )
    _refuse(
        " 2  A     B  400  250  110  1",
        " 2  A     B  400  250  110  1  Closed",
        "must be OPEN",
    )
    _refuse(" 3  A     C  500", " 3  A     Z  500", "no node Z")
    _refuse("[END]", "[PATTERNS]\n Day\n[END]", "a name and a multiplier")
    var sections = [
        "VALVES",
        "STATUS",
        "CONTROLS",
        "RULES",
        "EMITTERS",
        "DEMANDS",
    ]
    for i in range(6):
        _refuse(
            "[END]",
            "[" + sections[i] + "]\n 1 x y\n[END]",
            sections[i] + "] is not supported",
        )
    # A file with a title alone gives an empty network.
    var bare = parse_inp("[TITLE]\nNothing here\n[END]\n")
    assert_equal(len(bare.network.kinds), 0)
    assert_equal(bare.title, "Nothing here")
    # An empty section of that kind is passed over.
    var empty = parse_inp(
        String(_SI).replace("[END]", "[VALVES]\n;none\n[END]")
    )
    assert_equal(len(empty.network.links), 7)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
