# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Chain sequences, FASTA files and global alignments."""

from extensions.molecule.ids import (
    ALL_LOCATIONS,
    COIL,
    ChainId,
    ModelId,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.sequence import (
    SequenceAlignment,
    align_sequences,
    blosum62,
    chain_sequence,
    encode_fasta,
    one_letter,
)
from extensions.molecule.structure import parse_pdb_structure
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _coil(count: Int) -> List[SecondaryKind]:
    var out = List[SecondaryKind]()
    for _ in range(count):
        out.append(COIL)
    return out^


def test_blosum62() raises:
    var codes = "ARNDCQEGHILKMFPSTWYV"
    var diagonal: List[Int] = [
        4,
        5,
        6,
        6,
        9,
        5,
        5,
        6,
        8,
        4,
        4,
        5,
        5,
        6,
        7,
        4,
        5,
        11,
        7,
        4,
    ]
    for i in range(20):
        var a = String(codes[byte = i : i + 1])
        assert_equal(blosum62(a, a), diagonal[i])
        for j in range(20):
            var b = String(codes[byte = j : j + 1])
            assert_equal(blosum62(a, b), blosum62(b, a))
    assert_equal(blosum62("W", "C"), -2)
    assert_equal(blosum62("I", "V"), 3)
    assert_equal(blosum62("F", "Y"), 3)
    with assert_raises(contains="standard amino acid"):
        _ = blosum62("B", "A")
    with assert_raises(contains="one-letter"):
        _ = blosum62("AA", "A")
    with assert_raises(contains="one-letter"):
        _ = blosum62("A", "AA")


def test_sequences_and_fasta() raises:
    assert_equal(one_letter("TRP"), "W")
    assert_equal(one_letter("HOH"), "")
    # Each standard name gives back its code.
    var standard = "ARNDCQEGHILKMFPSTWYV"
    var built = build_peptide(standard, _coil(20))
    assert_equal(chain_sequence(built, ChainId(0)), standard)
    var peptide = build_peptide("MKTAYIAK", _coil(8))
    assert_equal(chain_sequence(peptide, ChainId(0)), "MKTAYIAK")
    # A water chain has no standard residue, and no FASTA record.
    var text = String(
        "ATOM      1  CA  GLY A   1       0.000   0.000   0.000  1.00  0.00"
        "           C\nATOM      2  CA  SER A   2       3.800   0.000   0.000"
        "  1.00  0.00           C\nTER\nHETATM    3  O   HOH B   1      10.000"
        "   0.000   0.000  1.00  0.00           O\nEND\n"
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    s.name = "TEST"
    assert_equal(chain_sequence(s, ChainId(1)), "")
    assert_equal(encode_fasta(s, ModelId(0)), ">TEST:A\nGS\n")
    # Lines of 80 codes.
    var codes = String("")
    for k in range(85):
        codes += "A" if k % 2 == 0 else "W"
    var long = build_peptide(codes, _coil(85))
    var fasta = encode_fasta(long, ModelId(0))
    var lines = fasta.split("\n")
    assert_equal(lines[0], ">PEPTIDE:A")
    assert_equal(lines[1].byte_length(), 80)
    assert_equal(lines[2].byte_length(), 5)
    with assert_raises(contains="model"):
        _ = encode_fasta(s, ModelId(3))
    with assert_raises(contains="chain"):
        _ = chain_sequence(s, ChainId(7))
    # A chain without residues has no sequence.
    s.chains[1].residue_count = 0
    assert_equal(chain_sequence(s, ChainId(1)), "")


def _check(
    first: String,
    second: String,
    top: String,
    bottom: String,
    score: Float64,
) raises:
    var a = align_sequences(first, second, -10, -0.5)
    assert_equal(a.first, top)
    assert_equal(a.second, bottom)
    assert_almost_equal(a.score, score)


def test_small_alignments() raises:
    # A gap at an end costs an opening.
    _check("AW", "W", "AW", "-W", 1.0)
    _check("W", "AW", "-W", "AW", 1.0)
    _check("AAW", "W", "AAW", "--W", 0.5)
    # An alignment can end in a gap of either sequence.
    _check("AW", "A", "AW", "A-", -6.0)
    _check("A", "AW", "A-", "AW", -6.0)
    # A gap inside, in either sequence, and a longer one.
    _check("WAW", "WW", "WAW", "W-W", 12.0)
    _check("WW", "WAAW", "W--W", "WAAW", 11.5)
    _check("WAAAW", "WW", "WAAAW", "W---W", 11.0)
    # One sequence against itself has its diagonal sum, and no gap.
    var same = align_sequences("MKTAYIAK", "MKTAYIAK", -10, -0.5)
    assert_almost_equal(same.score, 5 + 5 + 5 + 4 + 7 + 4 + 4 + 5)
    assert_equal(same.identity(), 1.0)
    # One change: 7 of 8 columns are the same.
    var one = align_sequences("MKTAYIAK", "MKTAYLAK", -10, -0.5)
    assert_equal(one.identical, 7)
    assert_equal(one.paired, 8)
    assert_almost_equal(one.identity(), 7.0 / 8.0)
    # With free gaps, the best path still pairs the shared residues.
    var free = align_sequences("WCW", "WW", 0, 0)
    assert_almost_equal(free.score, 22.0)
    assert_equal(free.identical, 2)


def test_refusals() raises:
    with assert_raises(contains="not empty"):
        _ = align_sequences("", "A", -10, -0.5)
    with assert_raises(contains="not empty"):
        _ = align_sequences("A", "", -10, -0.5)
    with assert_raises(contains="standard amino acid"):
        _ = align_sequences("AB", "A", -10, -0.5)
    with assert_raises(contains="opening"):
        _ = align_sequences("A", "A", 1, -0.5)
    with assert_raises(contains="opening"):
        _ = align_sequences("A", "A", -inf[DType.float64](), -0.5)
    with assert_raises(contains="extension"):
        _ = align_sequences("A", "A", -10, nan[DType.float64]())
    with assert_raises(contains="extension"):
        _ = align_sequences("A", "A", -10, 0.5)
    with assert_raises(contains="extension"):
        _ = align_sequences("A", "A", -10, -inf[DType.float64]())
    with assert_raises(contains="no identity"):
        _ = SequenceAlignment().identity()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
