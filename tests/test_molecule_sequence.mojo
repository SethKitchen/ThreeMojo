# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Chain sequences, FASTA files and global alignments."""

from extensions.molecule.ids import (
    AlignmentMode,
    LOCAL_ALIGNMENT,
    ResidueId,
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
    aligned_atoms,
    blosum62,
    chain_sequence,
    encode_fasta,
    one_letter,
)
from extensions.molecule.structure import Structure, parse_pdb_structure
from extensions.molecule.superpose import matched_atoms, superpose
from extensions.sdf.vector import V3, v3
from units.si import METER
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


def _renumbered(sequence: String) raises -> Structure:
    """Return a peptide numbered from 101, turned and moved."""
    var s = build_peptide(sequence, _coil(sequence.byte_length()))
    for k in range(len(s.residues)):
        s.residues[k].seq_id += 100
        s.residues[k].auth_seq_id += 100
    for k in range(len(s.atoms)):
        var p = s.atoms[k].position
        s.atoms[k].position = v3(-p.y, p.x, p.z) + v3(1e-9, 2e-9, -1e-9)
    return s^


def test_atoms_paired_through_the_alignment() raises:
    var crystal = build_peptide("MKTAYIAKQRQ", _coil(11))
    var moved = _renumbered("MKTAYIAKQRQ")
    # The numbers differ, so no atom pairs by number.
    assert_equal(
        len(matched_atoms(crystal, ModelId(0), moved, ModelId(0), "CA")), 0
    )
    var pairs = aligned_atoms(
        crystal, ChainId(0), moved, ChainId(0), "CA", -10, -0.5
    )
    assert_equal(len(pairs), 11)
    var fixed = List[V3]()
    var moving = List[V3]()
    for pair in pairs:
        fixed.append(crystal.atoms[pair[0]].position)
        moving.append(moved.atoms[pair[1]].position)
    var fit = superpose(fixed, moving)
    assert_true(fit.rmsd.to(METER) < 1e-15)
    # An inserted residue pairs with nothing.
    var longer = _renumbered("MKTAYGIAKQRQ")
    var gapped = aligned_atoms(
        crystal, ChainId(0), longer, ChainId(0), "CA", -10, -0.5
    )
    assert_equal(len(gapped), 11)
    for pair in gapped:
        var a = crystal.residues[crystal.atoms[pair[0]].residue.value].name
        var b = longer.residues[longer.atoms[pair[1]].residue.value].name
        assert_equal(a, b)
    # And so does a residue that only the first chain has.
    var reverse = aligned_atoms(
        longer, ChainId(0), crystal, ChainId(0), "CA", -10, -0.5
    )
    assert_equal(len(reverse), 11)
    # A residue without the atom on either side pairs nothing.
    var bare = moved.copy()
    bare.atoms[bare.find_atom(ResidueId(3), "CA").value].name = "CX"
    assert_equal(
        len(
            aligned_atoms(
                crystal, ChainId(0), bare, ChainId(0), "CA", -10, -0.5
            )
        ),
        10,
    )
    assert_equal(
        len(
            aligned_atoms(
                bare, ChainId(0), crystal, ChainId(0), "CA", -10, -0.5
            )
        ),
        10,
    )
    # A water inside a chain is not part of its sequence.
    var text = String(
        "ATOM      1  CA  GLY A   1       0.000   0.000   0.000  1.00  0.00    "
        "       C\nHETATM    2  O   HOH A   2       9.000   0.000   0.000  1.00"
        "  0.00           O\nATOM      3  CA  SER A   3       3.800   0.000  "
        " 0.000  1.00  0.00           C\nEND\n"
    )
    var wet = parse_pdb_structure(text, ALL_LOCATIONS)
    var two = aligned_atoms(
        wet,
        ChainId(0),
        build_peptide("GS", _coil(2)),
        ChainId(0),
        "CA",
        -10,
        -0.5,
    )
    assert_equal(len(two), 2)
    assert_equal(two[1][0], 2)
    with assert_raises(contains="chain"):
        _ = aligned_atoms(wet, ChainId(4), wet, ChainId(0), "CA", -10, -0.5)


def test_local_alignments() raises:
    # Three tryptophans inside other residues: the local alignment is
    # them alone, at 11 each.
    var local = align_sequences(
        "AAAWWWAAA", "CCWWWCC", -10, -0.5, LOCAL_ALIGNMENT
    )
    assert_almost_equal(local.score, 33.0)
    assert_equal(local.first, "WWW")
    assert_equal(local.second, "WWW")
    assert_equal(local.first_start, 3)
    assert_equal(local.second_start, 2)
    assert_equal(local.identity(), 1.0)
    # A gap inside a local alignment, when the pairs around it pay for it.
    var gapped = align_sequences(
        "WWWWAWWWW", "WWWWWWWW", -10, -0.5, LOCAL_ALIGNMENT
    )
    assert_almost_equal(gapped.score, 8 * 11.0 - 10.0)
    assert_equal(gapped.first, "WWWWAWWWW")
    assert_equal(gapped.second, "WWWW-WWWW")
    # The best pair can be the first cell.
    var first = align_sequences("WA", "WC", -10, -0.5, LOCAL_ALIGNMENT)
    assert_equal(first.first, "W")
    assert_equal(first.first_start, 0)
    # A global alignment starts at 0.
    assert_equal(align_sequences("AW", "W", -10, -0.5).second_start, 0)
    with assert_raises(contains="alignment mode"):
        _ = align_sequences("A", "A", -10, -0.5, AlignmentMode(2))


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
