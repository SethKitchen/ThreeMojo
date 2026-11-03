# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the CHEMKIN thermo reader of `extensions.chemistry`.

The methane record is the NASA TM-4513 data that GRI-Mech 3.0 also
ships, written in the CHEMKIN columns. Read back, it must give the same
Gibbs energy as the built-in catalog.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import methane
from extensions.chemistry.chemkin import read_chemkin_thermo
from extensions.chemistry.elements import CARBON, HYDROGEN, MAGNESIUM
from extensions.chemistry.kinds import GAS, LIQUID, SOLID
from extensions.chemistry.thermo import Substance
from units.temperature import Temperature64

comptime CH4_1 = (
    "CH4               L 8/88C   1H   4          G   200.000  6000.000 1000.00 "
    "     1"
)
comptime CH4_2 = (
    " 1.63552643E+00 1.00842795E-02-3.36916254E-06"
    " 5.34958667E-10-3.15518833E-14    2"
)
comptime CH4_3 = (
    "-1.00056455E+04 9.99313326E+00 5.14987613E+00-1.36709788E-02"
    " 4.91800599E-05    3"
)
comptime CH4_4 = (
    "-4.84743026E-08 1.66693956E-11-1.02466476E+04-4.64130376E+00              "
    "     4"
)


def _ch4() -> String:
    return String(CH4_1, "\n", CH4_2, "\n", CH4_3, "\n", CH4_4, "\n")


def _with_head(head: String) -> String:
    """The methane record with another first line."""
    return String(head, "\n", CH4_2, "\n", CH4_3, "\n", CH4_4, "\n")


def _replace(text: String, at: Int, by: String) -> String:
    """Return text with the bytes from `at` replaced by `by`."""
    var end = at + by.byte_length()
    return String(text[byte=0:at], by, text[byte=end:])


def test_methane_matches_the_catalog() raises:
    var file = String(
        "! GRI-Mech style\n",
        "THERMO\n",
        "   300.000  1000.000  5000.000\n",
        "\n",
        _ch4(),
        "END\n",
        "This line is after END and is not read.\n",
    )
    var species = read_chemkin_thermo(file)
    assert_equal(len(species), 1)
    assert_equal(species[0].name, "CH4")
    assert_true(species[0].phase == GAS)
    assert_equal(species[0].formula.count_of(CARBON), 1)
    assert_equal(species[0].formula.count_of(HYDROGEN), 4)
    var read = Substance("CH4(g)", [species[0].copy()])
    for t in [300.0, 999.0, 1000.0, 1500.0, 3000.0]:
        var temperature = Temperature64(t)
        assert_almost_equal(
            read.gibbs(temperature).value,
            methane().gibbs(temperature).value,
            atol=1e-6,
        )


def test_records_without_an_end() raises:
    # Two records back to back, a Fortran exponent and a solid.
    var solid = _with_head(
        "MGX               TEST  MG  1               S   300.000  1500.000 "
        " 900.00      1"
    )
    var species = read_chemkin_thermo(
        String(_ch4(), _replace(solid, 81 + 11, "D"))
    )
    assert_equal(len(species), 2)
    assert_true(species[1].phase == SOLID)
    assert_equal(species[1].formula.count_of(MAGNESIUM), 1)
    assert_almost_equal(species[1].thermo.bounds[1], 900.0, atol=0)
    var liquid = _with_head(
        "XL                TEST  C   1H   0          l   200.000  6000.000"
        " 1000.00      1"
    )
    var one = read_chemkin_thermo(liquid)
    assert_true(one[0].phase == LIQUID)
    assert_equal(len(one[0].formula.counts), 1)
    assert_equal(len(read_chemkin_thermo("\n! nothing\n")), 0)
    assert_equal(len(read_chemkin_thermo("")), 0)


def test_bad_records() raises:
    with assert_raises(contains="needs four lines"):
        _ = read_chemkin_thermo(String(CH4_1, "\n", CH4_2, "\n"))
    with assert_raises(contains="Line 1: column 80 must hold 1"):
        _ = read_chemkin_thermo(_with_head("CH4  short"))
    with assert_raises(contains="Line 2: column 80 must hold 2"):
        _ = read_chemkin_thermo(_replace(_ch4(), 81 + 79, "7"))
    with assert_raises(contains="needs a name"):
        _ = read_chemkin_thermo(_replace(_ch4(), 0, "   "))
    with assert_raises(contains="is not a number"):
        _ = read_chemkin_thermo(_replace(_ch4(), 46, "x"))
    with assert_raises(contains="must be whole"):
        _ = read_chemkin_thermo(_replace(_ch4(), 26, "1.5"))
    with assert_raises(contains="must be whole"):
        _ = read_chemkin_thermo(_replace(_ch4(), 26, " -1"))
    with assert_raises(contains="symbol 'E'"):
        _ = read_chemkin_thermo(_replace(_ch4(), 24, "E "))
    with assert_raises(contains="G, L or S"):
        _ = read_chemkin_thermo(_replace(_ch4(), 44, "X"))
    with assert_raises(contains="ascend"):
        _ = read_chemkin_thermo(_replace(_ch4(), 65, "9000.00"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
