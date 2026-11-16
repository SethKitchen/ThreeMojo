# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The parameters of protein sequences, as ProtParam gives them.

`assets/protparam/protparam_expected.txt` holds the values of Biopython and
peptides for five sequences. See `assets/protparam/make_protparam.py`.
"""

from extensions.chemistry.quantities import GRAM_PER_MOLE
from extensions.molecule.protparam import (
    PER_MOLAR_CENTIMETER,
    aliphatic_index,
    aromaticity,
    average_mass,
    extinction_coefficients,
    gravy,
    isoelectric_point,
    net_charge,
)
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * max(abs(b), 1.0), rtol=0)


def test_against_references() raises:
    var text = open("assets/protparam/protparam_expected.txt", "r").read()
    var checked = 0
    for line in text.splitlines():
        var parts = line.split(" ")
        var sequence = String(parts[0])
        var row = List[Float64]()
        for at in range(1, len(parts)):
            row.append(atof(String(parts[at])))
        _close(net_charge(sequence, 7.0), row[0], 1e-13)
        _close(net_charge(sequence, 7.4), row[1], 1e-13)
        # peptides bisects until its ends agree to 1e-9.
        _close(isoelectric_point(sequence), row[2], 1e-8)
        _close(average_mass(sequence).to(GRAM_PER_MOLE), row[3], 1e-13)
        var extinction = extinction_coefficients(sequence)
        assert_equal(extinction[0].to(PER_MOLAR_CENTIMETER), row[4])
        assert_equal(extinction[1].to(PER_MOLAR_CENTIMETER), row[5])
        _close(gravy(sequence), row[6], 1e-14)
        _close(aromaticity(sequence), row[7], 1e-15)
        _close(aliphatic_index(sequence), row[8], 1e-14)
        checked += 1
    assert_equal(checked, 5)


def test_by_hand() raises:
    # Glycine alone has its two ends: +1 and -1 halfway between 3.6 and 8.6.
    _close(isoelectric_point("G"), 6.1, 1e-12)
    assert_almost_equal(net_charge("G", 6.1), 0.0, atol=1e-15)
    # Far below every pK, each base and the N terminus carry +1.
    _close(net_charge("KKRH", -10.0), 5.0, 1e-12)
    _close(net_charge("DDEY", 30.0), -5.0, 1e-12)
    # Two glycines lose one water.
    _close(average_mass("GG").to(GRAM_PER_MOLE), 2 * 75.0666 - 18.0153, 1e-15)
    var extinction = extinction_coefficients("WYCCC")
    assert_equal(extinction[0].to(PER_MOLAR_CENTIMETER), 6990.0)
    assert_equal(extinction[1].to(PER_MOLAR_CENTIMETER), 7115.0)
    _close(gravy("IR"), 0.0, 1e-15)
    assert_equal(aromaticity("FWYA"), 0.75)
    _close(aliphatic_index("AVIL"), 100.0 * (1.0 + 2.9 + 7.8) / 4.0, 1e-14)
    assert_true(net_charge("K", 7.0) > net_charge("K", 8.0))


def test_errors() raises:
    with assert_raises(contains="one residue or more"):
        _ = gravy("")
    with assert_raises(contains="twenty one-letter codes"):
        _ = aromaticity("AXA")
    with assert_raises(contains="pH must be finite"):
        _ = net_charge("A", inf[DType.float64]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
