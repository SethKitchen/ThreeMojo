# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""PDB files read into the same structure as mmCIF files."""

from extensions.molecule.ids import (
    ALL_LOCATIONS,
    AltLocPolicy,
    COIL,
    FIRST_LOCATION,
    HELIX,
    HETATM_RECORD,
    ModelId,
    STRAND,
)
from extensions.molecule.structure import (
    SQUARE_ANGSTROM,
    parse_pdb_structure,
    read_pdb_structure,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _fixture() -> String:
    """Two models: a protein chain with alternate locations and an insertion,
    waters and an ion after TER, a second chain, and CR LF line ends."""
    var out = String("")
    out += (
        "HEADER    TEST FIXTURE                                        1ABC\r\n"
    )
    out += "HELIX    1   1 MET A    1  LYS A    2  1\r\n"
    out += "SHEET    1   S 1 GLY A   4  GLY A   4\r\n"
    out += "REMARK   1 A REMARK IS STEPPED OVER\r\n"
    out += (
        "ATOM      1  N   MET A   1       1.000   2.000   3.000  1.00 10.50    "
        "       N\r\n"
    )
    out += (
        "ATOM      2  CA AMET A   1       2.000   2.000   3.000  0.60 11.00    "
        "       C\r\n"
    )
    out += (
        "ATOM      3  CA BMET A   1       2.100   2.000   3.000  0.40 11.00    "
        "       C\r\n"
    )
    out += (
        "ATOM      4  N   LYS A   2       3.000   2.000   3.000  1.00 12.00    "
        "       N\r\n"
    )
    out += (
        "ATOM      5  N   LYS A   2A      3.500   2.000   3.000  1.00 12.00    "
        "       N\r\n"
    )
    out += "ATOM      6  CA  GLY A   4       4.000   2.000   3.000\r\n"
    out += "TER\r\n"
    out += (
        "HETATM    7  O   HOH A 101       9.000   9.000   9.000  1.00 30.00    "
        "       O\r\n"
    )
    out += (
        "HETATM    8 CA    CA A 102       8.000   9.000   9.000  1.00 20.00\r\n"
    )
    out += (
        "ATOM      9  N   ALA B   1      -1.000   0.000   0.000  1.00  5.00    "
        "       N\r\n"
    )
    out += "ENDMDL\r\n"
    out += "MODEL        2\r\n"
    out += (
        "ATOM     10  N   MET A   1      -2.000   0.000   0.000  1.00  5.00    "
        "       N\r\n"
    )
    out += "ENDMDL\r\n"
    out += "END\r\n"
    return out^


def test_hierarchy() raises:
    var s = parse_pdb_structure(_fixture(), FIRST_LOCATION)
    assert_equal(s.name, "1ABC")
    assert_equal(len(s.models), 2)
    assert_equal(s.models[0].chain_count, 3)
    assert_equal(len(s.chains), 4)
    # The waters after TER repeat chain A, as chain A2.
    assert_equal(s.chains[1].label, "A2")
    assert_equal(s.chains[1].author, "A")
    assert_equal(s.chains[2].label, "B")
    assert_equal(s.models[1].number, 2)
    # MET 1, LYS 2, LYS 2A, GLY 4, HOH 101, CA 102, ALA 1, and MET 1 again.
    assert_equal(len(s.residues), 8)
    assert_equal(s.residues[2].insertion, "A")
    assert_equal(s.residues[1].insertion, "?")
    assert_equal(s.residues[4].auth_seq_id, 101)
    # The B location of the CA is dropped.
    assert_equal(len(s.atoms), 9)
    assert_equal(len(parse_pdb_structure(_fixture(), ALL_LOCATIONS).atoms), 10)


def test_atoms() raises:
    var s = parse_pdb_structure(_fixture(), FIRST_LOCATION)
    ref ca = s.atoms[1]
    assert_equal(ca.name, "CA")
    assert_equal(ca.alt, "A")
    assert_equal(ca.serial, 2)
    assert_almost_equal(ca.position.x, 2.0e-10)
    assert_almost_equal(ca.occupancy, 0.6)
    assert_almost_equal(ca.b_factor.to(SQUARE_ANGSTROM), 11.0)
    assert_equal(s.atoms[0].alt, ".")
    # A short line has no occupancy, B-factor or element column.
    ref short = s.atoms[4]
    assert_equal(short.occupancy, 1.0)
    assert_equal(short.b_factor.value, 0.0)
    # Column 13 blank: carbon. Columns 13 and 14: calcium.
    assert_equal(short.element, "C")
    assert_equal(s.atoms[6].element, "CA")
    assert_true(s.atoms[5].group == HETATM_RECORD)
    var span = s.bounds(ModelId(0))
    assert_almost_equal(span[0].x, -1.0e-10)


def test_secondary_structure() raises:
    var s = parse_pdb_structure(_fixture(), FIRST_LOCATION)
    assert_true(s.residues[0].secondary == HELIX)
    assert_true(s.residues[1].secondary == HELIX)
    assert_true(s.residues[2].secondary == HELIX)
    assert_true(s.residues[3].secondary == STRAND)
    # The waters of chain A2 are not marked, nor chain B.
    assert_true(s.residues[4].secondary == COIL)
    assert_true(s.residues[6].secondary == COIL)
    # The helix marks the same residues of model 2.
    assert_true(s.residues[7].secondary == HELIX)


def test_three_js_fixture() raises:
    var s = read_pdb_structure("assets/pdb/fixture.pdb", ALL_LOCATIONS)
    assert_equal(len(s.atoms), 6)
    assert_equal(s.atoms[0].name, "C1")
    assert_equal(s.atoms[0].element, "C")
    assert_equal(s.name, "")


def test_refusals() raises:
    var row = String("ATOM      1  N   MET A   1       1.000   2.000")
    with assert_raises(contains="coordinate is missing"):
        _ = parse_pdb_structure(row, ALL_LOCATIONS)
    var bad = String("ATOM      1  N   MET A   1       1.000   x.000   3.000")
    with assert_raises(contains="y is not a number"):
        _ = parse_pdb_structure(bad, ALL_LOCATIONS)
    with assert_raises(contains="has no atoms"):
        _ = parse_pdb_structure("HEADER\nEND\n", ALL_LOCATIONS)
    with assert_raises(contains="has no atoms"):
        _ = parse_pdb_structure("", ALL_LOCATIONS)
    with assert_raises(contains="alternate location policy"):
        _ = parse_pdb_structure(_fixture(), AltLocPolicy(5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
