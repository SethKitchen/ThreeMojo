# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CIF tokenizer, CIF blocks and the mmCIF structure reader."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.cif import (
    CifBlock,
    cif_tokens,
    is_null,
    parse_cif,
    read_cif,
)
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    ATOM_RECORD,
    AltLocPolicy,
    AtomGroup,
    AtomId,
    BY_CHAIN,
    COIL,
    ChainId,
    FIRST_LOCATION,
    HELIX,
    HETATM_RECORD,
    ModelId,
    ResidueId,
    RibbonColoring,
    STRAND,
    SecondaryKind,
    require_coloring,
    require_group,
    require_policy,
    require_secondary,
)
from extensions.molecule.structure import (
    SQUARE_ANGSTROM,
    Structure,
    parse_mmcif,
    read_mmcif,
)
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_scratch import TestScratch, temporary_path

comptime FIXTURE = """data_1TST
# A test entry: two models, a protein chain and waters.
_entry.id 1TST
_struct.title 'A "quoted" title'
loop_
_struct_conf.conf_type_id
_struct_conf.beg_label_asym_id
_struct_conf.beg_label_seq_id
_struct_conf.end_label_asym_id
_struct_conf.end_label_seq_id
HELX_P A 1 A 2
TURN_P A 3 A 3
loop_
_struct_sheet_range.sheet_id
_struct_sheet_range.beg_label_asym_id
_struct_sheet_range.beg_label_seq_id
_struct_sheet_range.end_label_seq_id
S1 A 4 4
S2 Z 1 9
loop_
_atom_site.group_PDB
_atom_site.id
_atom_site.type_symbol
_atom_site.label_atom_id
_atom_site.label_alt_id
_atom_site.label_comp_id
_atom_site.label_asym_id
_atom_site.label_seq_id
_atom_site.pdbx_PDB_ins_code
_atom_site.Cartn_x
_atom_site.Cartn_y
_atom_site.Cartn_z
_atom_site.occupancy
_atom_site.B_iso_or_equiv
_atom_site.auth_seq_id
_atom_site.auth_asym_id
_atom_site.pdbx_PDB_model_num
ATOM 1 N N . MET A 1 ? 1.0 2.0 3.0 1.00 10.5 1 A 1
ATOM 2 C CA A MET A 1 ? 2.0 2.0 3.0 0.60 11.0 1 A 1
ATOM 3 C CA B MET A 1 ? 2.1 2.0 3.0 0.40 11.0 1 A 1
ATOM 4 C C A MET A 1 ? 2.5 3.0 3.0 0.60 11.0 1 A 1
ATOM 5 N N . LYS A 2 ? 3.0 2.0 3.0 1.00 12.0 2 A 1
ATOM 6 N N . LYS A 2 A 3.5 2.0 3.0 1.00 12.0 2 A 1
ATOM 7 N N . LYS A 3 ? 4.0 2.0 3.0 1.00 12.0 2 A 1
ATOM 8 N N . GLY A 3 ? 4.5 2.0 3.0 1.00 12.0 2 A 1
ATOM 9 N N . GLY A 4 ? 5.0 2.0 3.0 1.00 12.0 9 A 1
HETATM 10 O O . HOH B . ? 9.0 9.0 9.0 1.00 30.0 101 ? 1
ATOM 11 N N . MET A 1 ? -1.0 0.0 0.0 1.00 10.5 1 A 2
"""


def test_tokens() raises:
    var tokens = cif_tokens(
        "_a.b 'O'Brien' \"two words\"\tbare # note\r\n;line one\nline"
        " two\n;\n x;y 'end'"
    )
    assert_equal(len(tokens), 7)
    assert_equal(tokens[0].text, "_a.b")
    assert_false(tokens[0].quoted)
    assert_equal(tokens[1].text, "O'Brien")
    assert_true(tokens[1].quoted)
    assert_equal(tokens[2].text, "two words")
    assert_equal(tokens[3].text, "bare")
    assert_equal(tokens[4].text, "line one\nline two")
    assert_equal(tokens[4].line, 2)
    assert_equal(tokens[5].text, "x;y")
    assert_equal(tokens[5].line, 5)
    assert_equal(tokens[6].text, "end")
    # A comment at the end of the text, and a text field with CR LF ends.
    var tail = cif_tokens("a # last")
    assert_equal(len(tail), 1)
    var crlf = cif_tokens(";text\r\n;")
    assert_equal(crlf[0].text, "text")
    var empty = cif_tokens(";\n;")
    assert_equal(empty[0].text, "")
    assert_true(empty[0].quoted)
    # A carriage return between tokens, and a semicolon that does not start
    # its line.
    var spaced = cif_tokens("a\r\nb ;c")
    assert_equal(len(spaced), 3)
    assert_equal(spaced[1].line, 2)
    assert_equal(spaced[2].text, ";c")


def test_token_refusals() raises:
    with assert_raises(contains="quoted value has no end"):
        _ = cif_tokens("'open")
    with assert_raises(contains="quoted value has no end"):
        _ = cif_tokens("'open\nnext'")
    with assert_raises(contains="text field has no end"):
        _ = cif_tokens(";open\nfield")


def test_nulls() raises:
    assert_true(is_null("."))
    assert_true(is_null("?"))
    assert_false(is_null("A"))


def test_block_tables() raises:
    var block = parse_cif(
        "value _x before\ndata_one\n_single.item 5\nloop_\n_t.a\n_t.b\n1 2"
        " 3 4\nloop_\n_e.only\ndata_two\n_ignored 1"
    )
    assert_equal(block.name, "one")
    assert_equal(len(block.tables), 3)
    assert_true(block.has("_SINGLE.ITEM"))
    assert_false(block.has("_ignored"))
    var b = block.column("_t.b")
    assert_equal(len(b), 2)
    assert_equal(b[1], "4")
    assert_equal(block.tables[1].rows(), 2)
    assert_equal(len(block.column("_e.only")), 0)
    with assert_raises(contains="has no _missing"):
        _ = block.column("_missing")
    var fallback = block.column_or("_missing", "?", 2)
    assert_equal(fallback[1], "?")
    assert_equal(block.column_or("_t.a", "?", 2)[1], "3")
    with assert_raises(contains="wrong row count"):
        _ = block.column_or("_t.a", "?", 3)
    var bare = parse_cif("data_empty")
    assert_equal(bare.find("_x")[0], -1)
    # A quoted name is a value, not a name.
    var quoted = parse_cif("data_q\n_v '_not_a_name'")
    assert_equal(quoted.column("_v")[0], "_not_a_name")


def test_block_refusals() raises:
    with assert_raises(contains="needs a data block"):
        _ = parse_cif("_a 1")
    with assert_raises(contains="is not a name"):
        _ = parse_cif("data_x\nstray")
    with assert_raises(contains="loop has no name"):
        _ = parse_cif("data_x\nloop_\n1 2")
    with assert_raises(contains="loop has no name"):
        _ = parse_cif("data_x\nloop_\nloop_")
    with assert_raises(contains="loop has no name"):
        _ = parse_cif("data_x\nloop_")
    with assert_raises(contains="do not fill its rows"):
        _ = parse_cif("data_x\nloop_\n_a\n_b\n1 2 3")
    with assert_raises(contains="has no value"):
        _ = parse_cif("data_x\n_a")
    with assert_raises(contains="has no value"):
        _ = parse_cif("data_x\n_a\n_b 1")


def test_read_cif_from_a_file() raises:
    var path = temporary_path("entry.cif")
    Path(path).write_text(String(FIXTURE))
    assert_equal(read_cif(path).name, "1TST")
    var structure = read_mmcif(path, ALL_LOCATIONS)
    assert_equal(len(structure.atoms), 11)


def test_structure_hierarchy() raises:
    var s = parse_mmcif(String(FIXTURE), FIRST_LOCATION)
    assert_equal(s.name, "1TST")
    assert_equal(len(s.models), 2)
    assert_equal(len(s.chains), 3)
    # MET 1, LYS 2, LYS 2A, LYS 3 (label 3), GLY 3, GLY 4 (auth 9), HOH,
    # and MET 1 of model 2.
    assert_equal(len(s.residues), 8)
    # The B location of the CA is dropped; the A location of C stays.
    assert_equal(len(s.atoms), 10)
    assert_equal(s.models[0].chain_count, 2)
    assert_equal(s.models[1].number, 2)
    assert_equal(s.chains[1].label, "B")
    # A null author chain falls back to the label.
    assert_equal(s.chains[1].author, "B")
    assert_equal(s.residues[2].insertion, "A")
    assert_equal(s.residues[5].auth_seq_id, 9)
    assert_equal(s.residues[6].name, "HOH")
    assert_equal(s.residues[6].seq_id, 0)
    assert_equal(s.residues[6].auth_seq_id, 101)
    ref ca = s.atoms[1]
    assert_equal(ca.name, "CA")
    assert_equal(ca.alt, "A")
    assert_almost_equal(ca.position.x, 2.0e-10)
    assert_almost_equal(ca.occupancy, 0.6)
    assert_almost_equal(ca.b_factor.to(SQUARE_ANGSTROM), 11.0)
    assert_true(ca.group == ATOM_RECORD)
    assert_true(s.atoms[8].group == HETATM_RECORD)
    assert_true(ca.residue == ResidueId(0))
    var every = parse_mmcif(String(FIXTURE), ALL_LOCATIONS)
    assert_equal(len(every.atoms), 11)


def test_secondary_structure() raises:
    var s = parse_mmcif(String(FIXTURE), FIRST_LOCATION)
    # HELX_P runs over label_seq_id 1 and 2, in both models.
    assert_true(s.residues[0].secondary == HELIX)
    assert_true(s.residues[1].secondary == HELIX)
    assert_true(s.residues[2].secondary == HELIX)
    # The TURN_P row is not a helix.
    assert_true(s.residues[3].secondary == COIL)
    assert_true(s.residues[5].secondary == STRAND)
    assert_true(s.residues[7].secondary == HELIX)


def test_structure_lookups() raises:
    var s = parse_mmcif(String(FIXTURE), FIRST_LOCATION)
    assert_equal(s.find_atom(ResidueId(0), "CA").value, 1)
    assert_equal(s.find_atom(ResidueId(0), "CB").value, -1)
    var span = s.model_atoms(ModelId(0))
    assert_equal(span[0], 0)
    assert_equal(span[1], 9)
    var corners = s.bounds(ModelId(0))
    assert_almost_equal(corners[0].x, 1.0e-10)
    assert_almost_equal(corners[1].x, 9.0e-10)
    assert_almost_equal(corners[1].y, 9.0e-10)
    s.require_atom(AtomId(9))
    s.require_chain(ChainId(2))
    with assert_raises(contains="atom id"):
        s.require_atom(AtomId(10))
    with assert_raises(contains="atom id"):
        s.require_atom(AtomId(-1))
    with assert_raises(contains="residue id"):
        _ = s.find_atom(ResidueId(8), "CA")
    with assert_raises(contains="chain id"):
        s.require_chain(ChainId(3))
    with assert_raises(contains="model id"):
        _ = s.bounds(ModelId(2))


comptime HEADER = """data_X
loop_
_atom_site.group_PDB
_atom_site.type_symbol
_atom_site.label_atom_id
_atom_site.label_comp_id
_atom_site.label_asym_id
_atom_site.label_seq_id
_atom_site.Cartn_x
_atom_site.Cartn_y
_atom_site.Cartn_z
"""


def _one_row(row: String) raises -> Structure:
    return parse_mmcif(String(HEADER) + row + "\n", ALL_LOCATIONS)


comptime WATERS = """data_W
loop_
_atom_site.group_PDB
_atom_site.type_symbol
_atom_site.label_atom_id
_atom_site.label_comp_id
_atom_site.label_asym_id
_atom_site.label_seq_id
_atom_site.auth_seq_id
_atom_site.Cartn_x
_atom_site.Cartn_y
_atom_site.Cartn_z
HETATM O O HOH W . 1 0 0 0
HETATM O O HOH W . 2 3 0 0
loop_
_struct_conf.conf_type_id
loop_
_struct_sheet_range.beg_label_seq_id
"""


def test_waters_and_empty_tables() raises:
    # Two waters share a null label_seq_id and differ by auth_seq_id.
    var s = parse_mmcif(String(WATERS), ALL_LOCATIONS)
    assert_equal(len(s.residues), 2)
    assert_equal(s.residues[1].auth_seq_id, 2)
    assert_true(s.residues[1].secondary == COIL)
    # A residue that holds no atoms has none of any name.
    s.residues[1].atom_count = 0
    assert_equal(s.find_atom(ResidueId(1), "O").value, -1)


def test_minimal_columns() raises:
    var s = _one_row("ATOM C CA ALA A 1 1 2 3")
    assert_equal(len(s.atoms), 1)
    # Absent columns take their defaults.
    assert_equal(s.atoms[0].serial, 1)
    assert_equal(s.atoms[0].occupancy, 1.0)
    assert_equal(s.atoms[0].alt, ".")
    assert_equal(s.chains[0].author, "A")
    assert_equal(s.models[0].number, 1)
    assert_equal(s.residues[0].auth_seq_id, 1)


def test_atom_refusals() raises:
    with assert_raises(contains="x is not a number"):
        _ = _one_row("ATOM C CA ALA A 1 x 2 3")
    with assert_raises(contains="y is not finite"):
        _ = _one_row("ATOM C CA ALA A 1 1 1e999 3")
    with assert_raises(contains="label_seq_id is not an integer"):
        _ = _one_row("ATOM C CA ALA A one 1 2 3")
    with assert_raises(contains="group is not ATOM or HETATM"):
        _ = _one_row("ANISOU C CA ALA A 1 1 2 3")
    with assert_raises(contains="has no atoms"):
        _ = parse_mmcif(String(HEADER), ALL_LOCATIONS)
    with assert_raises(contains="has no _atom_site.group_PDB"):
        _ = parse_mmcif("data_X\n_entry.id X", ALL_LOCATIONS)
    with assert_raises(contains="alternate location policy"):
        _ = parse_mmcif(String(FIXTURE), AltLocPolicy(2))
    var bad_helix = String(HEADER) + "ATOM C CA ALA A 1 1 2 3\n"
    bad_helix += "_struct_conf.conf_type_id HELX_P\n"
    bad_helix += "_struct_conf.beg_label_seq_id one\n"
    with assert_raises(contains="helix start is not an integer"):
        _ = parse_mmcif(bad_helix, ALL_LOCATIONS)


def test_kinds() raises:
    require_group(HETATM_RECORD)
    with assert_raises(contains="atom group"):
        require_group(AtomGroup(2))
    require_secondary(STRAND)
    with assert_raises(contains="secondary structure"):
        require_secondary(SecondaryKind(3))
    require_policy(FIRST_LOCATION)
    with assert_raises(contains="alternate location policy"):
        require_policy(AltLocPolicy(-1))
    require_coloring(BY_CHAIN)
    with assert_raises(contains="ribbon coloring"):
        require_coloring(RibbonColoring(2))
    assert_true(ModelId(0).is_valid())
    assert_false(ChainId(-1).is_valid())


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
