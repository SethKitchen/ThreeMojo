# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Writing structures as PDB files, and reading them back."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    COIL,
    HELIX,
    HETATM_RECORD,
    ModelId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.pdb_write import encode_pdb
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import (
    SQUARE_ANGSTROM,
    Structure,
    parse_pdb_structure,
)
from extensions.sdf.vector import distance, v3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Area64, Length64


def _same(a: Structure, b: Structure) raises:
    assert_equal(len(a.models), len(b.models))
    assert_equal(len(a.chains), len(b.chains))
    assert_equal(len(a.residues), len(b.residues))
    assert_equal(len(a.atoms), len(b.atoms))
    var angstrom = Length64(1.0, ANGSTROM).value
    for k in range(len(a.atoms)):
        ref x = a.atoms[k]
        ref y = b.atoms[k]
        assert_equal(x.name, y.name)
        assert_equal(x.element, y.element)
        assert_equal(x.alt, y.alt)
        assert_true(x.group == y.group)
        # Three decimals of each coordinate move a point by at most
        # sqrt(3) * 0.0005 angstroms.
        assert_true(distance(x.position, y.position) < 1e-3 * angstrom)
        assert_almost_equal(x.occupancy, y.occupancy, atol=5e-3)
        assert_almost_equal(
            x.b_factor.to(SQUARE_ANGSTROM),
            y.b_factor.to(SQUARE_ANGSTROM),
            atol=5e-3,
        )
    for k in range(len(a.residues)):
        assert_equal(a.residues[k].name, b.residues[k].name)
        assert_equal(a.residues[k].seq_id, b.residues[k].seq_id)
        assert_equal(a.residues[k].insertion, b.residues[k].insertion)
        assert_true(a.residues[k].secondary == b.residues[k].secondary)
    for k in range(len(a.models)):
        assert_equal(a.models[k].number, b.models[k].number)


def _kinds() -> List[SecondaryKind]:
    var spec: List[Tuple[SecondaryKind, Int]] = [
        (COIL, 1),
        (HELIX, 8),
        (COIL, 2),
        (STRAND, 5),
        (COIL, 1),
    ]
    var out = List[SecondaryKind]()
    for part in spec:
        for _ in range(part[1]):
            out.append(part[0])
    return out^


def test_a_peptide_round_trips() raises:
    var peptide = build_peptide("MAEELLKKGNTYKVEVK", _kinds())
    var text = encode_pdb(peptide)
    # The name is longer than a PDB id, so it is a title.
    assert_true(
        text.startswith("TITLE     PEPTIDE\nHELIX    1   1 ALA A    2  ")
    )
    assert_true("\nSHEET    1   1 1 TYR A  12  " in text)
    assert_true("\nTER\nEND\n" in text)
    _same(peptide, parse_pdb_structure(text, ALL_LOCATIONS))


comptime MIXED = (
    "HEADER    TEST                                    14-NOV-26   9XYZ\nMODEL "
    "       1\nATOM      1  N   GLY A   5      11.104  -6.134   2.351  1.00"
    " 12.50           N\nATOM      2  CA AGLY A   5      12.000  -6.500   2.000"
    "  0.60 13.25           C\nATOM      3  CA BGLY A   5      12.100  -6.400  "
    " 2.100  0.40 13.25           C\nATOM      4  N   SER A   5A     13.000 "
    " -7.000   3.000  1.00 20.00           N\nTER\nHETATM    5 FE   HEM B   1  "
    "    -1.500   2.250 -30.125  1.00 30.00          FE\nHETATM    6  O   HOH C"
    "   1       0.000   0.000   0.000  1.00 40.00           O\nENDMDL\nMODEL   "
    "     2\nATOM      7  N   GLY A   5      11.204  -6.134   2.351  1.00 12.50"
    "           N\nENDMDL\n"
)


def test_models_hetero_atoms_and_alternates() raises:
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    var text = encode_pdb(s)
    assert_true(text.startswith("HEADER"))
    assert_true("MODEL        2\n" in text)
    # An iron's name starts in column 13, and a nitrogen's in column 14.
    assert_true("\nHETATM    5 FE   HEM B   1" in text)
    assert_true("\nATOM      1  N   GLY A   5" in text)
    assert_true("\nATOM      2  CA AGLY A   5" in text)
    assert_true("SER A   5A" in text)
    var back = parse_pdb_structure(text, ALL_LOCATIONS)
    _same(s, back)
    assert_equal(back.name, "9XYZ")
    assert_true(back.atoms[4].group == HETATM_RECORD)


def test_edge_cases() raises:
    # A strand that ends its chain, with no coil after it.
    var kinds = List[SecondaryKind]()
    for _ in range(4):
        kinds.append(STRAND)
    var strand = build_peptide("VKVE", kinds)
    var text = encode_pdb(strand)
    assert_true(
        text.startswith("TITLE     PEPTIDE\nSHEET    1   1 1 VAL A   1  ")
    )
    _same(strand, parse_pdb_structure(text, ALL_LOCATIONS))
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    # A four-letter name of a one-letter element starts in column 13, and
    # a "." insertion code is blank.
    s.atoms[0].name = "HD21"
    s.residues[0].insertion = "."
    var odd = encode_pdb(s)
    assert_true("\nATOM      1 HD21 GLY A   5      11.104" in odd)
    # A blank name is blank columns.
    s.atoms[0].name = ""
    assert_true("\nATOM      1      GLY A   5" in encode_pdb(s))
    # A structure without a name has no HEADER or TITLE.
    s.name = ""
    assert_true(encode_pdb(s).startswith("MODEL        1\n"))


def test_refusals() raises:
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    var long_chain = s.copy()
    long_chain.chains[0].author = "AB"
    with assert_raises(contains="one character"):
        _ = encode_pdb(long_chain)
    var far = s.copy()
    far.atoms[0].position = v3(1.0, 0, 0)
    with assert_raises(contains="coordinate"):
        _ = encode_pdb(far)
    var named = s.copy()
    named.atoms[0].name = "LONGER"
    with assert_raises(contains="atom name"):
        _ = encode_pdb(named)
    var numbered = s.copy()
    numbered.residues[0].seq_id = 10000
    with assert_raises(contains="residue number"):
        _ = encode_pdb(numbered)
    numbered.residues[0].seq_id = -1000
    with assert_raises(contains="residue number"):
        _ = encode_pdb(numbered)
    var titled = s.copy()
    titled.name = String("x") * 71
    with assert_raises(contains="title"):
        _ = encode_pdb(titled)
    var empty = Structure("")
    with assert_raises(contains="with a model"):
        _ = encode_pdb(empty)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
