# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The surface area that two chains bury in each other."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import ALL_LOCATIONS, ChainId, ModelId
from extensions.molecule.interface import ChainInterface, chain_interface
from extensions.molecule.structure import SQUARE_ANGSTROM, parse_pdb_structure
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _fixed(value: Float64) -> String:
    """Return a coordinate with three decimals, in 8 columns."""
    var text = String(value)
    var parts = text.split(".")
    var fraction = String(parts[1])
    while fraction.byte_length() < 3:
        fraction += "0"
    text = String(parts[0]) + "." + String(fraction[byte=0:3])
    while text.byte_length() < 8:
        text = " " + text
    return text


def _atom(
    serial: Int,
    name: String,
    residue: String,
    chain: String,
    seq: Int,
    x: Float64,
    y: Float64 = 0.0,
) -> String:
    """Return one ATOM record of a carbon in the plane z = 0."""
    var number = String(serial)
    while number.byte_length() < 5:
        number = " " + number
    var field = String(name)
    while field.byte_length() < 3:
        field += " "
    var seq_text = String(seq)
    while seq_text.byte_length() < 4:
        seq_text = " " + seq_text
    return (
        "ATOM  "
        + number
        + "  "
        + field
        + " "
        + residue
        + " "
        + chain
        + seq_text
        + "    "
        + _fixed(x)
        + _fixed(y)
        + "   0.000  1.00  0.00           C\n"
    )


def _probe() -> Length64:
    return Length64(1.4, ANGSTROM)


def test_two_carbons_bury_two_caps() raises:
    # Grown spheres of R = 1.7 + 1.4 = 3.1 angstroms, 3 angstroms apart:
    # each loses a cap of 2 pi R h, with h = R - 1.5.
    var text = (
        _atom(1, "CA", "ALA", "A", 1, 0.0)
        + "TER\n"
        + _atom(2, "CA", "ALA", "B", 1, 3.0)
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var face = chain_interface(
        s, ModelId(0), ChainId(0), ChainId(1), _probe(), 2000
    )
    var cap = 2.0 * pi * 3.1 * 1.6
    assert_almost_equal(face.total().to(SQUARE_ANGSTROM), 2 * cap, rtol=0.01)
    assert_equal(len(face.residues), 2)
    assert_equal(face.residues[0].value, 0)
    assert_almost_equal(face.buried(0).to(SQUARE_ANGSTROM), cap, rtol=0.01)
    assert_almost_equal(face.buried(1).to(SQUARE_ANGSTROM), cap, rtol=0.01)
    with assert_raises(contains="outside the interface"):
        _ = face.buried(2)
    with assert_raises(contains="outside the interface"):
        _ = face.buried(-1)


def test_far_chains_bury_nothing() raises:
    var text = (
        _atom(1, "CA", "ALA", "A", 1, 0.0)
        + "TER\n"
        + _atom(2, "CA", "ALA", "B", 1, 20.0)
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var face = chain_interface(
        s, ModelId(0), ChainId(0), ChainId(1), _probe(), 500
    )
    assert_equal(face.total().to(SQUARE_ANGSTROM), 0.0)
    assert_equal(len(face.residues), 0)
    assert_equal(len(face.atoms), 2)
    assert_equal(ChainInterface().total().to(SQUARE_ANGSTROM), 0.0)


def test_residues_and_a_third_chain() raises:
    # Chain A: residue 1 has two atoms near B, with a far atom between
    # them, and residue 2 is far. Chain C lies near both, and does not
    # count.
    var text = (
        _atom(1, "N", "GLY", "A", 1, 0.0, 2.5)
        + _atom(2, "CA", "GLY", "A", 1, -9.0)
        + _atom(3, "C", "GLY", "A", 1, 0.0, -2.5)
        + _atom(4, "CA", "ALA", "A", 2, -30.0)
        + "TER\n"
        + _atom(5, "CA", "SER", "B", 1, 3.0)
        + "TER\n"
        + _atom(6, "CA", "LYS", "C", 1, 1.5)
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var face = chain_interface(
        s, ModelId(0), ChainId(0), ChainId(1), _probe(), 1000
    )
    assert_equal(len(face.atoms), 5)
    assert_equal(len(face.residues), 2)
    assert_equal(face.residues[0].value, 0)
    assert_equal(face.residues[1].value, 2)
    # The residue's area is the sum of its two buried atoms.
    var first = face.atom_buried[0] + face.atom_buried[2]
    assert_almost_equal(face.buried(0).value, first, rtol=1e-12)
    assert_true(face.atom_buried[0] > 0 and face.atom_buried[2] > 0)
    assert_equal(face.atom_buried[1], 0.0)
    # Without chain C, the interface of A and B is the same.
    var pair = parse_pdb_structure(
        String(text.split("TER\n")[0])
        + "TER\n"
        + String(text.split("TER\n")[1]),
        ALL_LOCATIONS,
    )
    var same = chain_interface(
        pair, ModelId(0), ChainId(0), ChainId(1), _probe(), 1000
    )
    assert_almost_equal(same.total().value, face.total().value, rtol=1e-12)


def test_refusals() raises:
    var text = (
        "MODEL        1\n"
        + _atom(1, "CA", "ALA", "A", 1, 0.0)
        + "TER\n"
        + _atom(2, "CA", "ALA", "B", 1, 3.0)
        + "ENDMDL\nMODEL        2\n"
        + _atom(3, "CA", "ALA", "A", 1, 0.0)
        + "ENDMDL\n"
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    var p = _probe()
    with assert_raises(contains="two different chains"):
        _ = chain_interface(s, ModelId(0), ChainId(0), ChainId(0), p, 100)
    with assert_raises(contains="in the model"):
        _ = chain_interface(s, ModelId(0), ChainId(0), ChainId(2), p, 100)
    with assert_raises(contains="in the model"):
        _ = chain_interface(s, ModelId(1), ChainId(0), ChainId(2), p, 100)
    with assert_raises(contains="in the model"):
        _ = chain_interface(s, ModelId(0), ChainId(2), ChainId(0), p, 100)
    with assert_raises(contains="in the model"):
        _ = chain_interface(s, ModelId(1), ChainId(2), ChainId(0), p, 100)
    with assert_raises(contains="chain"):
        _ = chain_interface(s, ModelId(0), ChainId(0), ChainId(9), p, 100)
    with assert_raises(contains="model"):
        _ = chain_interface(s, ModelId(5), ChainId(0), ChainId(1), p, 100)
    with assert_raises(contains="probe"):
        _ = chain_interface(
            s, ModelId(0), ChainId(0), ChainId(1), Length64(-1.0, ANGSTROM), 100
        )
    with assert_raises(contains="points"):
        _ = chain_interface(s, ModelId(0), ChainId(0), ChainId(1), p, 0)
    # A chain without atoms, by an empty residue or by no residue.
    var hollow = s.copy()
    hollow.residues[1].atom_count = 0
    with assert_raises(contains="need atoms"):
        _ = chain_interface(hollow, ModelId(0), ChainId(0), ChainId(1), p, 100)
    var bare = s.copy()
    bare.chains[0].residue_count = 0
    with assert_raises(contains="need atoms"):
        _ = chain_interface(bare, ModelId(0), ChainId(0), ChainId(1), p, 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
