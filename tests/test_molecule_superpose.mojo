# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The superposition of two sets of atoms, and their RMSD."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import (
    ALL_LOCATIONS,
    HELIX,
    ModelId,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import parse_pdb_structure
from extensions.molecule.superpose import (
    Superposition,
    matched_atoms,
    rmsd,
    superpose,
)
from extensions.sdf.vector import V3, cross, dot, length, v3
from std.math import cos, inf, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _turn(p: V3, axis: V3, angle: Float64) -> V3:
    """Rodrigues' rotation of a point about a unit axis."""
    var c = cos(angle)
    var s = sin(angle)
    return p * c + cross(axis, p) * s + axis * (dot(axis, p) * (1 - c))


def _cloud() -> List[V3]:
    """Eight points that span three dimensions."""
    return [
        v3(0, 0, 0),
        v3(1.5, 0.2, -0.3),
        v3(0.4, 2.1, 0.7),
        v3(-1.2, 0.9, 1.6),
        v3(2.2, -1.4, 0.5),
        v3(-0.6, -0.8, -2.0),
        v3(0.9, 1.1, 1.3),
        v3(-1.7, 2.4, -0.4),
    ]


def test_recovers_a_rotation_and_a_shift() raises:
    var fixed = _cloud()
    var axis = v3(1, 2, 3) * (1.0 / sqrt(14.0))
    var moving = List[V3]()
    for p in fixed:
        moving.append(_turn(p, axis, 0.7) + v3(5, -3, 2))
    var fit = superpose(fixed, moving)
    assert_true(fit.rmsd.to(METER) < 1e-12)
    for index in range(len(fixed)):
        var back = fit.apply(moving[index])
        assert_almost_equal(back.x, fixed[index].x, atol=1e-12)
        assert_almost_equal(back.z, fixed[index].z, atol=1e-12)
    # The rotation is proper: its rows are unit, square and right-handed.
    var r = fit.rotation.copy()
    var x = v3(r[0], r[1], r[2])
    var y = v3(r[3], r[4], r[5])
    var z = v3(r[6], r[7], r[8])
    assert_almost_equal(length(x), 1, atol=1e-12)
    assert_almost_equal(dot(x, y), 0, atol=1e-12)
    assert_almost_equal(dot(cross(x, y), z), 1, atol=1e-12)
    # Before the fit, the sets are far apart.
    assert_true(rmsd(fixed, moving).to(METER) > 1)


def test_a_half_turn_and_identity() raises:
    var fixed = _cloud()
    var moving = List[V3]()
    for p in fixed:
        moving.append(_turn(p, v3(0, 0, 1), 3.14159265358979))
    assert_true(superpose(fixed, moving).rmsd.to(METER) < 1e-9)
    assert_true(superpose(fixed, fixed).rmsd.to(METER) < 1e-12)


def test_a_mirror_is_not_reached() raises:
    var fixed = _cloud()
    var mirror = List[V3]()
    for p in fixed:
        mirror.append(v3(-p.x, p.y, p.z))
    # A rotation cannot turn a set into its mirror image.
    var fit = superpose(fixed, mirror)
    assert_true(fit.rmsd.to(METER) > 0.1)
    var r = fit.rotation.copy()
    var det = dot(
        cross(v3(r[0], r[1], r[2]), v3(r[3], r[4], r[5])), v3(r[6], r[7], r[8])
    )
    assert_almost_equal(det, 1, atol=1e-12)


def test_the_fit_is_the_least() raises:
    var fixed = _cloud()
    var moving = List[V3]()
    var shifts = _cloud()
    for index in range(len(fixed)):
        var noise = shifts[(index + 3) % len(shifts)] * 0.05
        moving.append(_turn(fixed[index], v3(0, 1, 0), -0.4) + noise)
    var fit = superpose(fixed, moving)
    var best = fit.rmsd.to(METER)
    assert_true(best > 0)
    # A small turn about any axis away from the fit gives a larger RMSD.
    for axis in [v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)]:
        for angle in [-0.01, 0.01]:
            var moved = List[V3]()
            var center = v3(0, 0, 0)
            for p in fixed:
                center = center + p
            center = center * (1.0 / Float64(len(fixed)))
            for p in moving:
                var q = fit.apply(p) - center
                moved.append(_turn(q, axis, angle) + center)
            assert_true(rmsd(fixed, moved).to(METER) > best)


def test_refusals() raises:
    var three: List[V3] = [v3(0, 0, 0), v3(1, 0, 0), v3(0, 1, 0)]
    var two: List[V3] = [v3(0, 0, 0), v3(1, 0, 0)]
    with assert_raises(contains="three or more"):
        _ = superpose(two, two)
    with assert_raises(contains="three or more"):
        _ = superpose(three, two)
    var bad: List[V3] = [
        v3(0, 0, 0),
        v3(1, 0, 0),
        v3(0, inf[DType.float64](), 0),
    ]
    with assert_raises(contains="finite"):
        _ = superpose(three, bad)
    with assert_raises(contains="one size"):
        _ = rmsd(three, two)
    with assert_raises(contains="one size"):
        _ = rmsd(List[V3](), List[V3]())


def _helix(count: Int) raises -> List[SecondaryKind]:
    var kinds = List[SecondaryKind]()
    for _ in range(count):
        kinds.append(HELIX)
    return kinds^


def test_two_models_of_a_peptide() raises:
    var first = build_peptide("MKTAYIAKQR", _helix(10))
    var second = build_peptide("MKTAYIAKQR", _helix(10))
    # Turn and shift the second copy as a rigid body.
    for index in range(len(second.atoms)):
        var p = second.atoms[index].position
        second.atoms[index].position = _turn(p, v3(0, 0, 1), 1.1) + v3(
            1e-9, 2e-9, 0
        )
    var pairs = matched_atoms(first, ModelId(0), second, ModelId(0), "CA")
    assert_equal(len(pairs), 10)
    var a = List[V3]()
    var b = List[V3]()
    for pair in pairs:
        a.append(first.atoms[pair[0]].position)
        b.append(second.atoms[pair[1]].position)
    var fit = superpose(a, b)
    var angstrom = Length64(1.0, ANGSTROM).to(METER)
    assert_true(fit.rmsd.to(METER) < 1e-6 * angstrom)
    # A shorter peptide pairs only the residues it has.
    var short = build_peptide("MKTAY", _helix(5))
    assert_equal(
        len(matched_atoms(first, ModelId(0), short, ModelId(0), "CA")), 5
    )
    assert_equal(
        len(matched_atoms(first, ModelId(0), short, ModelId(0), "XX")), 0
    )
    with assert_raises(contains="model"):
        _ = matched_atoms(first, ModelId(1), short, ModelId(0), "CA")


comptime ALTERNATES = (
    "ATOM      1  CA AALA A   1       0.000   0.000   0.000  0.50 10.00   "
    "        C\n"
    "ATOM      2  CA BALA A   1       0.500   0.000   0.000  0.50 10.00   "
    "        C\n"
    "ATOM      3  CA  GLY A   2       3.800   0.000   0.000  1.00 10.00   "
    "        C\n"
)


def test_alternate_locations_pair_once() raises:
    var s = parse_pdb_structure(String(ALTERNATES), ALL_LOCATIONS)
    assert_equal(len(s.atoms), 3)
    var pairs = matched_atoms(s, ModelId(0), s, ModelId(0), "CA")
    # The first location pairs with itself, and the second is skipped.
    assert_equal(len(pairs), 2)
    assert_equal(pairs[0][0], 0)
    assert_equal(pairs[0][1], 0)
    assert_equal(pairs[1][1], 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
