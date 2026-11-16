# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Backbone hydrogen bonds, listed and drawn."""

from core.buffer_geometry import COLOR, POSITION
from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.dssp import (
    HydrogenBond,
    KILOCALORIE_PER_MOLE,
    hydrogen_bonds,
)
from extensions.molecule.hbonds import bond_geometry
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import parse_pdb_structure
from extensions.chemistry.quantities import MolarEnergy64
from extensions.sdf.vector import V3, cross, dot, length, v3
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _kinds(kind: SecondaryKind, count: Int) -> List[SecondaryKind]:
    var out = List[SecondaryKind]()
    for _ in range(count):
        out.append(kind)
    return out^


def test_a_helix_bonds_i_to_i_plus_4() raises:
    var helix = build_peptide("AAAAAAAAAAAAAA", _kinds(HELIX, 14))
    var bonds = hydrogen_bonds(helix, ModelId(0))
    # The N-H of each residue from the fifth bonds to the C=O four back.
    assert_equal(len(bonds), 10)
    for bond in bonds:
        assert_equal(bond.donor.value - bond.acceptor.value, 4)
        var kcal = bond.energy.to(KILOCALORIE_PER_MOLE)
        assert_true(kcal < -0.5 and kcal > -5)
    var strand = build_peptide("VVVVVVVV", _kinds(STRAND, 8))
    assert_equal(len(hydrogen_bonds(strand, ModelId(0))), 0)
    with assert_raises(contains="model"):
        _ = hydrogen_bonds(strand, ModelId(3))


def test_dashes_follow_each_bond() raises:
    var helix = build_peptide("AAAAAAAAAA", _kinds(HELIX, 10))
    var bonds = hydrogen_bonds(helix, ModelId(0))
    var radius = Length64(0.1, ANGSTROM)
    var drawn = bond_geometry(helix, bonds, radius, 6)
    # Four dashes of two rings of six vertices for each bond.
    assert_equal(drawn.vertex_count(), len(bonds) * 4 * 2 * 6)
    assert_equal(drawn.triangle_count(), len(bonds) * 4 * 6 * 2)
    assert_true(drawn.has_attribute(COLOR))
    # Each vertex of the first bond lies one radius from its axis.
    var n = helix.atoms[helix.find_atom(bonds[0].donor, "N").value].position
    var o = helix.atoms[helix.find_atom(bonds[0].acceptor, "O").value].position
    var axis = (o - n) * (1.0 / length(o - n))
    ref points = drawn.attribute_view(POSITION)
    for v in range(48):
        var p = points.vector3(v)
        var d = v3(Float64(p.x), Float64(p.y), Float64(p.z)) - n
        var off = d - axis * dot(d, axis)
        assert_almost_equal(length(off), radius.to(METER), rtol=1e-4)
    assert_equal(
        bond_geometry(helix, List[HydrogenBond](), radius, 6).vertex_count(), 0
    )


comptime ALONG_X = (
    "ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00 10.00   "
    "        N\n"
    "ATOM      2  O   ALA A   2       2.900   0.000   0.000  1.00 10.00   "
    "        O\n"
    "HETATM    3  O   HOH W   1       9.000   9.000   9.000  1.00 10.00   "
    "        O\n"
)


def _one(bond: HydrogenBond) -> List[HydrogenBond]:
    var out = List[HydrogenBond]()
    out.append(bond)
    return out^


def test_a_bond_along_x_and_refusals() raises:
    var s = parse_pdb_structure(String(ALONG_X), ALL_LOCATIONS)
    # No residue has a whole backbone, so DSSP finds no bond.
    assert_equal(len(hydrogen_bonds(s, ModelId(0))), 0)
    var energy = MolarEnergy64(-2, KILOCALORIE_PER_MOLE)
    var along = _one(HydrogenBond(ResidueId(0), ResidueId(1), energy))
    var radius = Length64(0.1, ANGSTROM)
    assert_equal(bond_geometry(s, along, radius, 3).vertex_count(), 24)
    # The water has no N, and the first residue has no O.
    with assert_raises(contains="N of its donor"):
        _ = bond_geometry(
            s, _one(HydrogenBond(ResidueId(2), ResidueId(1), energy)), radius, 3
        )
    with assert_raises(contains="N of its donor"):
        _ = bond_geometry(
            s, _one(HydrogenBond(ResidueId(0), ResidueId(0), energy)), radius, 3
        )
    with assert_raises(contains="radius"):
        _ = bond_geometry(s, along, Length64(0, METER), 3)
    with assert_raises(contains="radius"):
        _ = bond_geometry(s, along, Length64(inf[DType.float64](), METER), 3)
    with assert_raises(contains="from 3 to 64 sides"):
        _ = bond_geometry(s, along, radius, 2)
    with assert_raises(contains="from 3 to 64 sides"):
        _ = bond_geometry(s, along, radius, 65)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
