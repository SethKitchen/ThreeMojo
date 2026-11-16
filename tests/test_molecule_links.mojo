# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Disulfide bonds and salt bridges."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import ALL_LOCATIONS, ModelId
from extensions.molecule.links import disulfide_bonds, salt_bridges
from extensions.molecule.structure import parse_pdb_structure
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length64


def _fixed(value: Float64) -> String:
    var text = String(value)
    var parts = text.split(".")
    var fraction = String(parts[1])
    while fraction.byte_length() < 3:
        fraction += "0"
    text = String(parts[0]) + "." + String(fraction[byte=0:3])
    while text.byte_length() < 8:
        text = " " + text
    return text


def _atom(name: String, residue: String, seq: Int, x: Float64) -> String:
    """Return one ATOM record on the x axis, in chain A."""
    var field = String(name)
    while field.byte_length() < 3:
        field += " "
    var seq_text = String(seq)
    while seq_text.byte_length() < 4:
        seq_text = " " + seq_text
    return (
        "ATOM      1  "
        + field
        + " "
        + residue
        + " A"
        + seq_text
        + "    "
        + _fixed(x)
        + "   0.000   0.000  1.00  0.00           C\n"
    )


def _angstroms(value: Float64) -> Length64:
    return Length64(value, ANGSTROM)


def test_disulfide_bonds() raises:
    var text = (
        _atom("SG", "CYS", 1, 0.0)
        + _atom("SG", "CYS", 2, 2.05)
        + _atom("SG", "CYS", 3, 10.0)
        + _atom("CA", "CYS", 4, 11.0)
        + _atom("SG", "MET", 5, 12.0)
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var bonds = disulfide_bonds(s, ModelId(0), _angstroms(2.5))
    assert_equal(len(bonds), 1)
    assert_equal(bonds[0].first.value, 0)
    assert_equal(bonds[0].second.value, 1)
    assert_almost_equal(bonds[0].distance.to(ANGSTROM), 2.05, atol=1e-9)
    # A smaller cutoff finds none.
    assert_equal(len(disulfide_bonds(s, ModelId(0), _angstroms(2.0))), 0)


def test_salt_bridges() raises:
    var text = (
        # Residue 4's OD1 reaches lysine 9, and its OD2 lysine 5.
        _atom("OD1", "ASP", 4, 20.0)
        + _atom("OD2", "ASP", 4, 24.0)
        + _atom("NZ", "LYS", 5, 26.5)
        + _atom("OE2", "GLU", 6, 40.0)
        + _atom("NH1", "ARG", 7, 43.8)
        + _atom("NE", "ARG", 7, 44.5)
        + _atom("OE1", "GLU", 8, 60.0)
        + _atom("NZ", "LYS", 9, 17.0)
        # Too far, an asparagine, and a backbone atom of an aspartate.
        + _atom("NZ", "LYS", 10, 64.5)
        + _atom("OD1", "ASN", 11, 80.0)
        + _atom("NZ", "LYS", 12, 82.0)
        + _atom("CA", "ASP", 13, 100.0)
        + _atom("NZ", "LYS", 14, 101.0)
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var bridges = salt_bridges(s, ModelId(0), _angstroms(4.0))
    assert_equal(len(bridges), 3)
    # Sorted by the acid, then the base, though found in another order.
    assert_equal(bridges[0].first.value, 0)
    assert_equal(bridges[0].second.value, 1)
    assert_almost_equal(bridges[0].distance.to(ANGSTROM), 2.5, atol=1e-9)
    assert_equal(bridges[1].second.value, 5)
    assert_almost_equal(bridges[1].distance.to(ANGSTROM), 3.0, atol=1e-9)
    # The arginine's nearer nitrogen counts.
    assert_equal(bridges[2].first.value, 2)
    assert_almost_equal(bridges[2].distance.to(ANGSTROM), 3.8, atol=1e-9)


def test_one_pair_with_its_least_distance() raises:
    var text = (
        _atom("OD1", "ASP", 1, 0.0)
        + _atom("OD2", "ASP", 1, 1.0)
        + _atom("NZ", "LYS", 2, 3.5)
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var bridges = salt_bridges(s, ModelId(0), _angstroms(4.0))
    assert_equal(len(bridges), 1)
    assert_almost_equal(bridges[0].distance.to(ANGSTROM), 2.5, atol=1e-9)
    # The closer atom found first keeps its distance.
    var reverse = (
        _atom("OD1", "ASP", 1, 1.0)
        + _atom("OD2", "ASP", 1, 0.0)
        + _atom("NZ", "LYS", 2, 3.5)
    )
    var t = parse_pdb_structure(reverse, ALL_LOCATIONS)
    var again = salt_bridges(t, ModelId(0), _angstroms(4.0))
    assert_almost_equal(again[0].distance.to(ANGSTROM), 2.5, atol=1e-9)


def test_models_without_partners() raises:
    # No acid at all, and an acid without a base.
    var cys = parse_pdb_structure(_atom("SG", "CYS", 1, 0.0), ALL_LOCATIONS)
    assert_equal(len(salt_bridges(cys, ModelId(0), _angstroms(4.0))), 0)
    var acid = parse_pdb_structure(_atom("OD1", "ASP", 1, 0.0), ALL_LOCATIONS)
    assert_equal(len(salt_bridges(acid, ModelId(0), _angstroms(4.0))), 0)


def test_refusals() raises:
    var s = parse_pdb_structure(_atom("SG", "CYS", 1, 0.0), ALL_LOCATIONS)
    with assert_raises(contains="cutoff"):
        _ = disulfide_bonds(s, ModelId(0), _angstroms(0.0))
    with assert_raises(contains="cutoff"):
        _ = salt_bridges(
            s, ModelId(0), Length64(inf[DType.float64](), ANGSTROM)
        )
    with assert_raises(contains="model"):
        _ = salt_bridges(s, ModelId(1), _angstroms(4.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
