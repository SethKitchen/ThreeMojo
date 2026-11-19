# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The local distance difference test of a model against a reference."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.confidence import confidence_summary
from extensions.molecule.ids import HELIX, ModelId, ResidueId, SecondaryKind
from extensions.molecule.lddt import (
    LddtScores,
    ca_lddt,
    lddt,
    lddt_b_factors,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from extensions.sdf.vector import V3, v3
from std.math import cos, inf, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _a() -> Float64:
    return Length64(1.0, ANGSTROM).to(METER)


def _line(shift: Float64) -> Tuple[List[V3], List[V3]]:
    """Three points 3.8 angstroms apart, and the last one moved along."""
    var a = _a()
    var reference: List[V3] = [
        v3(0, 0, 0),
        v3(3.8 * a, 0, 0),
        v3(7.6 * a, 0, 0),
    ]
    var model = reference.copy()
    model[2] = v3((7.6 + shift) * a, 0, 0)
    return (reference^, model^)


def test_a_moved_point() raises:
    var cutoff = Length64(15, ANGSTROM)
    # Moved by 0.7: its two pairs fail the 0.5 threshold only.
    var near = _line(0.7)
    var s = lddt(near[0], near[1], cutoff)
    assert_almost_equal(s.per_point[0], 0.875)
    assert_almost_equal(s.per_point[1], 0.875)
    assert_almost_equal(s.per_point[2], 0.75)
    assert_almost_equal(s.total, 2.5 / 3.0)
    assert_equal(s.pairs[2], 2)
    # Moved by 3: only the 4 angstrom threshold holds.
    var far = _line(3.0)
    var t = lddt(far[0], far[1], cutoff)
    assert_almost_equal(t.per_point[2], 0.25)
    # Moved by 5: no threshold holds.
    var gone = _line(5.0)
    assert_almost_equal(lddt(gone[0], gone[1], cutoff).per_point[2], 0.0)
    # A cutoff of 5 angstroms keeps only the neighbor pairs.
    var short = lddt(near[0], near[1], Length64(5, ANGSTROM))
    assert_equal(short.pairs[0], 1)
    assert_almost_equal(short.per_point[0], 1.0)
    assert_almost_equal(short.per_point[2], 0.75)


def test_no_superposition_is_needed() raises:
    var a = _a()
    var reference = List[V3]()
    for n in range(12):
        var t = Float64(n) * 1.7
        reference.append(
            v3(2.3 * a * cos(t), 2.3 * a * sin(t), 1.5 * a * Float64(n))
        )
    var turned = List[V3]()
    var c = cos(0.9)
    var s = sin(0.9)
    for p in reference:
        turned.append(
            v3(c * p.x - s * p.z, p.y, s * p.x + c * p.z)
            + v3(5 * a, -3 * a, 8 * a)
        )
    var scores = lddt(reference, turned, Length64(15, ANGSTROM))
    assert_almost_equal(scores.total, 1.0)
    for value in scores.per_point:
        assert_almost_equal(value, 1.0)
    # A point far from all others has no pair, and scores 1.
    var lonely: List[V3] = [v3(0, 0, 0), v3(40 * a, 0, 0)]
    var alone = lddt(lonely, lonely, Length64(15, ANGSTROM))
    assert_equal(alone.pairs[0], 0)
    assert_equal(alone.per_point[0], 1.0)
    assert_equal(alone.total, 1.0)


def _helix(count: Int) raises -> Structure:
    var kinds = List[SecondaryKind]()
    for _ in range(count):
        kinds.append(HELIX)
    return build_peptide(
        String(String("MAEKLAGKVLEELLKK")[byte=0:count]), kinds
    )


def test_models_and_b_factors() raises:
    var reference = _helix(10)
    var model = _helix(10)
    # Residue 4's CA moves 3 angstroms; residue 9 is renumbered away.
    var ca = model.find_atom(ResidueId(4), "CA").value
    model.atoms[ca].position = model.atoms[ca].position + v3(0, 0, 3 * _a())
    model.residues[9].auth_seq_id = 99
    var scores = ca_lddt(reference, ModelId(0), model, ModelId(0))
    assert_equal(len(scores.per_point), 9)
    assert_equal(len(scores.atoms), 9)
    assert_equal(scores.atoms[4][1], ca)
    # The moved residue scores lowest, and the others are partly hurt.
    var least = 0
    for p in range(9):
        if scores.per_point[p] < scores.per_point[least]:
            least = p
    assert_equal(least, 4)
    assert_true(scores.per_point[0] < 1.0)
    # The scores become B-factors, so the confidence bands read them.
    lddt_b_factors(model, scores)
    var first = model.residues[4].first_atom
    assert_almost_equal(
        model.atoms[first].b_factor.to(SQUARE_ANGSTROM),
        100.0 * scores.per_point[4],
    )
    var summary = confidence_summary(model, ModelId(0))
    assert_equal(summary.residues, 10)
    # A model against itself scores 1.
    var same = ca_lddt(reference, ModelId(0), reference, ModelId(0))
    assert_almost_equal(same.total, 1.0)


def test_refusals() raises:
    var a = _a()
    var two: List[V3] = [v3(0, 0, 0), v3(a, 0, 0)]
    var one: List[V3] = [v3(0, 0, 0)]
    with assert_raises(contains="one size"):
        _ = lddt(two, one, Length64(15, ANGSTROM))
    with assert_raises(contains="one size"):
        _ = lddt(List[V3](), List[V3](), Length64(15, ANGSTROM))
    for bad in [0.0, -1.0, inf[DType.float64]()]:
        with assert_raises(contains="cutoff"):
            _ = lddt(two, two, Length64(bad, METER))
    var reference = _helix(4)
    var other = _helix(4)
    for r in range(4):
        other.residues[r].auth_seq_id = 100 + r
    with assert_raises(contains="no CA"):
        _ = ca_lddt(reference, ModelId(0), other, ModelId(0))
    with assert_raises(contains="model"):
        _ = ca_lddt(reference, ModelId(2), other, ModelId(0))
    with assert_raises(contains="ca_lddt"):
        lddt_b_factors(other, lddt(two, two, Length64(15, ANGSTROM)))
    var scores = ca_lddt(reference, ModelId(0), reference, ModelId(0))
    var small = _helix(1)
    with assert_raises(contains="atom"):
        lddt_b_factors(small, scores)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
