# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The conservation of the columns of a protein alignment.

`assets/conservation/conservation_expected.txt` holds the values of numpy,
scipy and Biopython for a synthetic alignment. See
`tools/make_conservation.mojo` and `assets/conservation/make_conservation.py`.
"""

from extensions.molecule.conservation import (
    column_conservation,
    conservation_b_factors,
    henikoff_weights,
    parse_fasta,
    uniform_background,
)
from extensions.molecule.ids import COIL, ChainId, SecondaryKind
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import SQUARE_ANGSTROM
from std.math import inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def _rows() raises -> List[String]:
    var text = open("assets/conservation/conservation_msa.fasta", "r").read()
    return parse_fasta(text).sequences.copy()


def _expected(kind: String) raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/conservation/conservation_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != kind:
            continue
        var first = 1 if kind == "background" else 2
        var row = List[Float64]()
        for at in range(first, len(parts)):
            row.append(atof(String(parts[at])))
        out.append(row^)
    return out^


def _check(rows: List[String], weights: List[Float64], kind: String) raises:
    var background = _expected("background")[0].copy()
    var found = column_conservation(rows, weights, background)
    var expected = _expected(kind)
    assert_equal(len(found), 48)
    assert_equal(len(expected), 48)
    for c in range(48):
        ref e = expected[c]
        assert_almost_equal(found[c].gaps, e[0], atol=1e-15, rtol=0)
        assert_almost_equal(found[c].entropy, e[1], atol=1e-14, rtol=0)
        assert_almost_equal(found[c].relative_entropy, e[2], atol=1e-13, rtol=0)
        assert_almost_equal(found[c].divergence, e[3], atol=1e-14, rtol=0)
        # The score is the divergence times one less the share of gaps.
        assert_almost_equal(
            found[c].score, e[3] * (1.0 - e[0]), atol=1e-14, rtol=0
        )


def test_against_references() raises:
    var rows = _rows()
    assert_equal(len(rows), 12)
    _check(rows, List[Float64](length=12, fill=1.0), "uniform")


def test_by_hand() raises:
    # A held column has no entropy. Two kinds in equal shares have 1 bit.
    var rows: List[String] = ["AAW", "ACW", "A-W", "AC-"]
    var found = column_conservation(
        rows, List[Float64](length=4, fill=0.25), uniform_background()
    )
    assert_equal(found[0].entropy, 0.0)
    assert_almost_equal(
        found[0].relative_entropy, log(20.0) / log(2.0), atol=1e-15
    )
    assert_almost_equal(found[1].entropy, 0.9182958340544896, atol=1e-15)
    assert_equal(found[1].gaps, 0.25)
    assert_equal(found[2].gaps, 0.25)
    # Against a uniform background, the relative entropy is log2(20) - H.
    for c in range(3):
        assert_almost_equal(
            found[c].relative_entropy,
            log(20.0) / log(2.0) - found[c].entropy,
            atol=1e-14,
        )
    # A column of gaps only has no residue to score.
    var empty = column_conservation(
        ["A-", "C-"], [1.0, 1.0], uniform_background()
    )
    assert_equal(empty[1].gaps, 1.0)
    assert_equal(empty[1].score, 0.0)
    assert_equal(empty[1].entropy, 0.0)
    # Two copies of one row share the weight of a third, distinct row.
    var weights = henikoff_weights(["AC", "AC", "WY"])
    assert_almost_equal(weights[0], 0.25, atol=1e-16)
    assert_almost_equal(weights[2], 0.5, atol=1e-16)
    # With those weights, A has a share of 1/4 + 1/4 and W of 1/2: 1 bit.
    var weighted = column_conservation(
        ["A", "A", "W"],
        henikoff_weights(["AC", "AC", "WY"]),
        uniform_background(),
    )
    assert_almost_equal(weighted[0].entropy, 1.0, atol=1e-15)
    assert_almost_equal(
        weighted[0].relative_entropy, log(20.0) / log(2.0) - 1.0, atol=1e-14
    )
    # A gap column of `.` counts as gaps too, and a row of gaps weighs 0.
    weights = henikoff_weights(["A.", "--", "CW"])
    assert_equal(weights[1], 0.0)


def test_fasta() raises:
    var records = parse_fasta(">one first\nAC\nDE\n\n> two\nWY\n")
    assert_equal(len(records.names), 2)
    assert_equal(records.names[0], "one first")
    assert_equal(records.names[1], "two")
    assert_equal(records.sequences[0], "ACDE")
    assert_equal(records.sequences[1], "WY")


def test_b_factors() raises:
    var kinds = List[SecondaryKind](length=4, fill=COIL)
    var structure = build_peptide("ACDE", kinds)
    var values: List[Float64] = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
    conservation_b_factors(structure, ChainId(0), "A-CD-E", values)
    ref chain = structure.chains[0]
    var expected: List[Float64] = [10.0, 30.0, 40.0, 60.0]
    for r in range(chain.residue_count):
        var residue = structure.residues[chain.first_residue + r].copy()
        for a in range(
            residue.first_atom, residue.first_atom + residue.atom_count
        ):
            assert_almost_equal(
                structure.atoms[a].b_factor.to(SQUARE_ANGSTROM),
                expected[r],
                atol=1e-12,
            )


def test_other_residue() raises:
    # A residue that is not one of the twenty has no column, and keeps its
    # B-factor.
    var kinds = List[SecondaryKind](length=3, fill=COIL)
    var structure = build_peptide("ACD", kinds)
    var start = structure.chains[0].first_residue
    var middle = start + 1
    structure.residues[middle].name = "UNK"
    var before = structure.atoms[structure.residues[middle].first_atom].b_factor
    conservation_b_factors(structure, ChainId(0), "A-D", [1.0, 2.0, 3.0])
    var first = structure.residues[start].first_atom
    var last = structure.residues[start + 2].first_atom
    assert_equal(structure.atoms[first].b_factor.to(SQUARE_ANGSTROM), 1.0)
    assert_equal(structure.atoms[last].b_factor.to(SQUARE_ANGSTROM), 3.0)
    assert_equal(
        structure.atoms[structure.residues[middle].first_atom].b_factor.to(
            SQUARE_ANGSTROM
        ),
        before.to(SQUARE_ANGSTROM),
    )


def test_errors() raises:
    with assert_raises(contains="one record or more"):
        _ = parse_fasta("\n\n")
    with assert_raises(contains="name line before"):
        _ = parse_fasta("ACD\n>x\nA")
    with assert_raises(contains="needs a sequence"):
        _ = parse_fasta(">x\n>y\nA")
    with assert_raises(contains="one row or more"):
        _ = henikoff_weights(List[String]())
    with assert_raises(contains="one column or more"):
        _ = henikoff_weights([""])
    with assert_raises(contains="one length"):
        _ = henikoff_weights(["AC", "A"])
    with assert_raises(contains="twenty one-letter codes"):
        _ = henikoff_weights(["AX"])
    with assert_raises(contains="gaps only"):
        _ = henikoff_weights(["--", ".."])
    var rows: List[String] = ["AC", "AD"]
    var even: List[Float64] = [1.0, 1.0]
    var flat = uniform_background()
    with assert_raises(contains="one weight for each row"):
        _ = column_conservation(rows, [1.0], flat)
    var bad: List[Float64] = [-1.0, inf[DType.float64](), nan[DType.float64]()]
    for w in bad:
        with assert_raises(contains="0 or more, and finite"):
            _ = column_conservation(rows, [w, 1.0], flat)
    with assert_raises(contains="sum above 0"):
        _ = column_conservation(rows, [0.0, 0.0], flat)
    with assert_raises(contains="one share for each"):
        _ = column_conservation(rows, even, [1.0])
    var zero = uniform_background()
    zero[0] = 0.0
    with assert_raises(contains="above 0, and finite"):
        _ = column_conservation(rows, even, zero)
    var endless = uniform_background()
    endless[0] = inf[DType.float64]()
    with assert_raises(contains="above 0, and finite"):
        _ = column_conservation(rows, even, endless)
    var heavy = uniform_background()
    heavy[0] = 0.5
    with assert_raises(contains="sum to 1"):
        _ = column_conservation(rows, even, heavy)
    var kinds = List[SecondaryKind](length=2, fill=COIL)
    var structure = build_peptide("AC", kinds)
    with assert_raises(contains="one value for each column"):
        conservation_b_factors(structure, ChainId(0), "AC", [1.0])
    with assert_raises(contains="chain's sequence"):
        conservation_b_factors(structure, ChainId(0), "AD", [1.0, 2.0])
    with assert_raises(contains="must be finite"):
        conservation_b_factors(
            structure, ChainId(0), "AC", [1.0, nan[DType.float64]()]
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
