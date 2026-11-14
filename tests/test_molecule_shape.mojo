# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mass center, radius of gyration and principal axes of a model."""

from extensions.chemistry.quantities import ANGSTROM, GRAM_PER_MOLE
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    HELIX,
    ModelId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.shape import molecular_shape
from extensions.molecule.structure import parse_pdb_structure
from extensions.sdf.vector import dot, length
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER

comptime TWO_CARBONS = (
    "ATOM      1  CA  ALA A   1      -2.000   0.000   0.000  1.00 10.00   "
    "        C\n"
    "ATOM      2  CA  ALA A   2       2.000   0.000   0.000  1.00 10.00   "
    "        C\n"
)

comptime CARBON_OXYGEN = (
    "ATOM      1  C   ALA A   1       0.000   0.000   0.000  1.00 10.00   "
    "        C\n"
    "ATOM      2  O   ALA A   1       0.000   3.000   4.000  1.00 10.00   "
    "        O\n"
)


def _angstroms(value: Length64) -> Float64:
    return value.to(METER) / Length64(1.0, ANGSTROM).to(METER)


def test_two_equal_atoms() raises:
    var s = parse_pdb_structure(String(TWO_CARBONS), ALL_LOCATIONS)
    var shape = molecular_shape(s, ModelId(0))
    assert_almost_equal(shape.mass.to(GRAM_PER_MOLE), 2 * 12.011, atol=0.01)
    assert_almost_equal(length(shape.center), 0, atol=1e-20)
    # Each atom is 2 angstroms from the center, along x.
    assert_almost_equal(_angstroms(shape.radius_of_gyration), 2, rtol=1e-9)
    assert_almost_equal(_angstroms(shape.extents[0]), 2, rtol=1e-9)
    assert_almost_equal(_angstroms(shape.extents[1]), 0, atol=1e-6)
    assert_almost_equal(abs(shape.axes[0].x), 1, atol=1e-9)
    assert_almost_equal(dot(shape.axes[0], shape.axes[1]), 0, atol=1e-9)


def test_the_heavier_atom_pulls_the_center() raises:
    var s = parse_pdb_structure(String(CARBON_OXYGEN), ALL_LOCATIONS)
    var shape = molecular_shape(s, ModelId(0))
    var carbon = 12.011
    var oxygen = 15.999
    var share = oxygen / (carbon + oxygen)
    var angstrom = Length64(1.0, ANGSTROM).to(METER)
    # The center lies on the bond, 5 angstroms long, nearer the oxygen.
    assert_almost_equal(length(shape.center) / angstrom, 5 * share, rtol=1e-4)
    # The radius of gyration of two masses: L sqrt(m1 m2) / (m1 + m2).
    var expected = 5 * sqrt(carbon * oxygen) / (carbon + oxygen)
    assert_almost_equal(
        _angstroms(shape.radius_of_gyration), expected, rtol=1e-4
    )
    # The long axis runs along the bond, (0, 0.6, 0.8).
    assert_almost_equal(abs(shape.axes[0].z), 0.8, atol=1e-9)


def _kinds(kind: SecondaryKind, count: Int) -> List[SecondaryKind]:
    var out = List[SecondaryKind]()
    for _ in range(count):
        out.append(kind)
    return out^


def test_a_strand_is_longer_than_a_helix() raises:
    var helix = molecular_shape(
        build_peptide("AAAAAAAAAAAA", _kinds(HELIX, 12)), ModelId(0)
    )
    var strand = molecular_shape(
        build_peptide("AAAAAAAAAAAA", _kinds(STRAND, 12)), ModelId(0)
    )
    assert_true(
        strand.radius_of_gyration.to(METER) > helix.radius_of_gyration.to(METER)
    )
    # A strand is long and thin.
    assert_true(strand.extents[0].to(METER) > 4 * strand.extents[1].to(METER))
    assert_equal(len(strand.axes), 3)


def test_refusals() raises:
    var text = String(
        "ATOM      1  X   ALA A   1       0.000   0.000   0.000  1.00 10.00   "
        "        XX\n"
    )
    var s = parse_pdb_structure(text, ALL_LOCATIONS)
    with assert_raises(contains="no standard weight"):
        _ = molecular_shape(s, ModelId(0))
    with assert_raises(contains="model"):
        _ = molecular_shape(s, ModelId(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
