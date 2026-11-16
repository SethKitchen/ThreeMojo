# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The accessible area and the relative accessibility of residues."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.accessibility import (
    ResidueAccess,
    max_accessible_area,
    residue_accessibility,
)
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    HELIX,
    ModelId,
    ResidueId,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import (
    SQUARE_ANGSTROM,
    parse_pdb_structure,
)
from extensions.molecule.surface import accessible_areas
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Area64, Length64


def test_the_largest_areas() raises:
    var names: List[String] = [
        "ALA",
        "ARG",
        "ASN",
        "ASP",
        "CYS",
        "GLN",
        "GLU",
        "GLY",
        "HIS",
        "ILE",
        "LEU",
        "LYS",
        "MET",
        "PHE",
        "PRO",
        "SER",
        "THR",
        "TRP",
        "TYR",
        "VAL",
    ]
    # Tien and others (2013), theoretical, in square angstroms.
    var areas: List[Float64] = [
        129,
        274,
        195,
        193,
        167,
        225,
        223,
        104,
        224,
        197,
        201,
        236,
        224,
        240,
        159,
        155,
        172,
        285,
        263,
        174,
    ]
    for k in range(20):
        assert_almost_equal(
            max_accessible_area(names[k]).to(SQUARE_ANGSTROM), areas[k]
        )
    with assert_raises(contains="standard amino acid"):
        _ = max_accessible_area("HOH")


comptime MIXED = (
    "MODEL        1\nATOM      1  N   GLY A   5      11.104  -6.134   2.351"
    "  1.00 12.50           N\nATOM      2  CA  GLY A   5      12.000  -6.500"
    "   2.000  1.00 13.25           C\nATOM      3  N   SER A   6      13.000 "
    " -7.000   3.000  1.00 20.00           N\nTER\nHETATM    4 FE   HEM B   1"
    "      -1.500   2.250 -30.125  1.00 30.00          FE\nHETATM    5  O   HOH"
    " C   1       0.000   0.000   0.000  1.00 40.00           O\nENDMDL\nMODEL"
    "        2\nATOM      6  N   GLY A   5      11.204  -6.134   2.351  1.00"
    " 12.50           N\nENDMDL\n"
)


def test_the_sums_of_each_residue() raises:
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    var areas = List[Area64]()
    for k in range(5):
        areas.append(Area64(Float64(10 * (k + 1)), SQUARE_ANGSTROM))
    var access = residue_accessibility(s, ModelId(0), areas)
    assert_equal(len(access), 4)
    # GLY holds the atoms of 10 and 20 square angstroms.
    assert_equal(access[0].residue.value, 0)
    assert_almost_equal(access[0].area.to(SQUARE_ANGSTROM), 30.0)
    assert_almost_equal(access[0].relative, 30.0 / 104.0)
    assert_true(access[0].has_relative)
    assert_true(access[0].buried(0.5))
    assert_false(access[0].buried(0.25))
    assert_almost_equal(access[1].relative, 30.0 / 155.0)
    # A heme and a water have areas but no RSA.
    assert_almost_equal(access[2].area.to(SQUARE_ANGSTROM), 40.0)
    assert_false(access[2].has_relative)
    assert_equal(access[2].relative, 0.0)
    assert_false(access[3].has_relative)
    with assert_raises(contains="not a standard amino acid"):
        _ = access[3].buried(0.25)
    for bad in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        with assert_raises(contains="cutoff"):
            _ = access[0].buried(bad)
    # The second model has one atom.
    var one: List[Area64] = [Area64(5.0, SQUARE_ANGSTROM)]
    var second = residue_accessibility(s, ModelId(1), one)
    assert_equal(second[0].residue.value, 4)
    assert_almost_equal(second[0].area.to(SQUARE_ANGSTROM), 5.0)
    # A residue without atoms has no area.
    s.residues[1].atom_count = 0
    var empty = residue_accessibility(s, ModelId(0), areas)
    assert_equal(empty[1].area.to(SQUARE_ANGSTROM), 0.0)


def test_a_helix_buries_its_middle() raises:
    var kinds = List[SecondaryKind]()
    for _ in range(9):
        kinds.append(HELIX)
    var helix = build_peptide("AAAAAAAAA", kinds)
    var areas = accessible_areas(
        helix, ModelId(0), Length64(1.4, ANGSTROM), 400
    )
    var access = residue_accessibility(helix, ModelId(0), areas)
    assert_equal(len(access), 9)
    for entry in access:
        assert_true(entry.relative > 0 and entry.relative < 1.2)
    # The middle of a helix is more buried than its ends.
    assert_true(access[4].relative < access[0].relative)
    assert_true(access[4].relative < access[8].relative)


def test_refusals() raises:
    var s = parse_pdb_structure(String(MIXED), ALL_LOCATIONS)
    with assert_raises(contains="one value for each atom"):
        _ = residue_accessibility(s, ModelId(0), List[Area64]())
    with assert_raises(contains="model"):
        _ = residue_accessibility(s, ModelId(2), List[Area64]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
