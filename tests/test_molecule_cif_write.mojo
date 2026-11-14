# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Writing structures as mmCIF files, and reading them back."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.cif import parse_cif
from extensions.molecule.cif_write import cif_value, encode_mmcif
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    COIL,
    HELIX,
    HETATM_RECORD,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import (
    Model,
    SQUARE_ANGSTROM,
    Structure,
    parse_mmcif,
    parse_pdb_structure,
)
from extensions.sdf.vector import distance
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


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
        assert_equal(x.serial, y.serial)
        assert_true(x.group == y.group)
        assert_equal(x.residue.value, y.residue.value)
        # Three decimals move a point by at most sqrt(3) * 0.0005 angstroms.
        assert_true(distance(x.position, y.position) < 1e-3 * angstrom)
        assert_almost_equal(x.occupancy, y.occupancy, atol=5e-3)
        assert_almost_equal(
            x.b_factor.to(SQUARE_ANGSTROM),
            y.b_factor.to(SQUARE_ANGSTROM),
            atol=5e-3,
        )
    for k in range(len(a.residues)):
        ref x = a.residues[k]
        ref y = b.residues[k]
        assert_equal(x.name, y.name)
        assert_equal(x.seq_id, y.seq_id)
        assert_equal(x.auth_seq_id, y.auth_seq_id)
        assert_equal(x.insertion, y.insertion)
        assert_equal(x.chain.value, y.chain.value)
        assert_true(x.secondary == y.secondary)
    for k in range(len(a.chains)):
        assert_equal(a.chains[k].label, b.chains[k].label)
        assert_equal(a.chains[k].author, b.chains[k].author)
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
    var text = encode_mmcif(peptide)
    assert_true(text.startswith("data_PEPTIDE\n#\n_entry.id PEPTIDE\n#\n"))
    assert_true("\nHELX_P HELX_P1 ALA A 2 ? GLY A 9 ? A 2 A 9\n" in text)
    assert_true("\nS1 1 TYR A 12 ? VAL A 16 ? A 12 A 16\n" in text)
    assert_true(
        "\nATOM 1 N N . MET A 1 ? 0.000 0.000 0.000 1.00 0.00 1 A 1\n" in text
    )
    _same(peptide, parse_mmcif(text, ALL_LOCATIONS))
    # Any CIF reader takes the block.
    var block = parse_cif(text)
    assert_equal(len(block.column("_atom_site.id")), len(peptide.atoms))


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
    var text = encode_mmcif(s)
    assert_true(text.startswith("data_9XYZ\n"))
    # No helix or strand: no range loops.
    assert_true("_struct_conf" not in text)
    assert_true("_struct_sheet_range" not in text)
    assert_true("\nATOM 2 C CA A GLY A 5 ? 12.000 -6.500 2.000 0.60" in text)
    assert_true("\nATOM 4 N N . SER A 5 A 13.000" in text)
    assert_true("\nHETATM 5 FE FE . HEM B 1 ? -1.500" in text)
    assert_true(" 11.204 -6.134 2.351 1.00 12.50 5 A 2\n" in text)
    var back = parse_mmcif(text, ALL_LOCATIONS)
    _same(s, back)
    assert_equal(back.name, "9XYZ")
    assert_true(back.atoms[4].group == HETATM_RECORD)


def test_what_a_pdb_file_cannot_hold() raises:
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    # A long chain id, a long atom name, a large residue number, a water
    # without a sequence number and a value with a space.
    s.chains[0].label = "AA"
    s.chains[0].author = "ALPHA"
    s.atoms[0].name = "LONGER"
    s.residues[0].seq_id = 123456
    s.residues[0].auth_seq_id = 123456
    s.residues[3].seq_id = 0
    s.residues[2].name = "A B"
    var text = encode_mmcif(s)
    assert_true("\nATOM 1 N LONGER . GLY AA 123456 ? " in text)
    assert_true(" 123456 ALPHA 1\n" in text)
    assert_true(" HOH C . ? " in text)
    assert_true(" 'A B' B 1 ? " in text)
    _same(s, parse_mmcif(text, ALL_LOCATIONS))
    # A structure without a name gets a block name.
    s.name = ""
    var unnamed = encode_mmcif(s)
    assert_true(unnamed.startswith("data_unnamed\n#\n_entry.id unnamed\n"))


def test_edge_cases() raises:
    # A strand that ends its chain, with no coil after it.
    var kinds = List[SecondaryKind]()
    for _ in range(4):
        kinds.append(STRAND)
    var strand = build_peptide("VKVE", kinds)
    var text = encode_mmcif(strand)
    assert_true("\nS1 1 VAL A 1 ? GLU A 4 ? A 1 A 4\n" in text)
    _same(strand, parse_mmcif(text, ALL_LOCATIONS))
    # A residue without atoms writes no rows.
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    s.residues[3].atom_count = 0
    var short = encode_mmcif(s)
    assert_true("HOH" not in short)
    assert_equal(len(parse_mmcif(short, ALL_LOCATIONS).atoms), 6)


def test_values_are_quoted_when_they_must_be() raises:
    assert_equal(cif_value("CA"), "CA")
    assert_equal(cif_value("O5'"), "O5'")
    assert_equal(cif_value(""), "''")
    assert_equal(cif_value("a b"), "'a b'")
    assert_equal(cif_value("a\tb"), "'a\tb'")
    for special in ["_x", "#x", "$x", "'x", '"x', "[x", "]x", ";x"]:
        assert_equal(cif_value(special), "'" + special + "'")
    for word in ["data_x", "SAVE_x", "loop_", "Global_", "stop_"]:
        assert_equal(cif_value(word), "'" + word + "'")
    assert_equal(cif_value("loop_x"), "loop_x")
    # A single quote and a blank close a single-quoted value.
    assert_equal(cif_value("a' b"), '"a\' b"')
    assert_equal(cif_value("a'\tb"), '"a\'\tb"')
    assert_equal(cif_value("a'b c"), "'a'b c'")
    with assert_raises(contains="both kinds"):
        _ = cif_value("a' b\" c")
    with assert_raises(contains="one line"):
        _ = cif_value("a\nb")
    with assert_raises(contains="one line"):
        _ = cif_value("a\rb")
    # Each quoted value reads back as it was.
    var tricky: List[String] = ["a' b", "'x", "a b", "", "data_x"]
    var text = String("data_t\nloop_\n_t.v\n")
    for value in tricky:
        text += cif_value(value) + "\n"
    var back = parse_cif(text).column("_t.v")
    for k in range(len(tricky)):
        assert_equal(back[k], tricky[k])


def test_refusals() raises:
    with assert_raises(contains="with a model"):
        _ = encode_mmcif(Structure("X"))
    var empty = Structure("X")
    empty.models.append(Model(1, 0, 0))
    with assert_raises(contains="at least one atom"):
        _ = encode_mmcif(empty)
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    s.name = "TWO WORDS"
    with assert_raises(contains="blank"):
        _ = encode_mmcif(s)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
