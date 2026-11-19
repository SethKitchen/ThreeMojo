# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The RMSD between every two models of an ensemble, and their clusters."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.clusters import (
    ModelDistances,
    cluster_models,
    model_distances,
)
from extensions.molecule.ids import (
    AS_GIVEN,
    ChainId,
    EnsembleFit,
    FIT_TO_REFERENCE,
    HELIX,
    ModelId,
    ResidueId,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import Model, Structure
from extensions.sdf.vector import V3, v3
from std.math import cos, inf, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _angstrom() -> Float64:
    return Length64(1.0, ANGSTROM).value


def _ensemble(count: Int) raises -> Structure:
    """Return `count` copies of one helix of eight residues."""
    var kinds = List[SecondaryKind]()
    for _ in range(8):
        kinds.append(HELIX)
    var base = build_peptide("MAEKLAGK", kinds)
    var out = base.copy()
    for k in range(1, count):
        var chain0 = len(out.chains)
        var residue0 = len(out.residues)
        var atom0 = len(out.atoms)
        out.models.append(Model(k + 1, chain0, len(base.chains)))
        for c in base.chains:
            var chain = c.copy()
            chain.model = ModelId(k)
            chain.first_residue += residue0
            out.chains.append(chain^)
        for r in base.residues:
            var residue = r.copy()
            residue.chain = ChainId(r.chain.value + chain0)
            residue.first_atom += atom0
            out.residues.append(residue^)
        for a in base.atoms:
            var atom = a.copy()
            atom.residue = ResidueId(a.residue.value + residue0)
            out.atoms.append(atom^)
    return out^


def _move(mut s: Structure, model: Int, angle: Float64, shift: V3):
    """Turn every atom of a model about z, then shift it."""
    var per_model = len(s.atoms) // len(s.models)
    var c = cos(angle)
    var t = sin(angle)
    for a in range(model * per_model, (model + 1) * per_model):
        var p = s.atoms[a].position
        s.atoms[a].position = v3(c * p.x - t * p.y, t * p.x + c * p.y, p.z) + (
            shift
        )


def test_shifts_as_given_and_fitted() raises:
    var s = _ensemble(4)
    for k in range(1, 4):
        _move(s, k, 0, v3(Float64(k), 0, 0) * _angstrom())
    var raw = model_distances(s, "CA", AS_GIVEN)
    assert_equal(raw.models, 4)
    assert_equal(raw.atoms, 8)
    for a in range(4):
        for b in range(4):
            var d = raw.distance(ModelId(a), ModelId(b)).to(ANGSTROM)
            assert_almost_equal(d, Float64(abs(a - b)), atol=1e-9)
    # Models 1 and 2 have the least sum, 4 angstroms; the lower counts.
    assert_equal(raw.medoid().value, 1)
    # A fit takes the shifts and a turn away.
    _move(s, 3, 1.2, v3(2, -3, 1) * _angstrom())
    var fitted = model_distances(s, "CA", FIT_TO_REFERENCE)
    for a in range(4):
        for b in range(4):
            assert_true(
                fitted.distance(ModelId(a), ModelId(b)).to(ANGSTROM) < 1e-9
            )


def test_a_moved_atom() raises:
    # In model 2 one CA of eight moves by 3 angstroms.
    var s = _ensemble(3)
    var per_model = len(s.atoms) // 3
    var ca = s.find_atom(ResidueId(2 * 8 + 4), "CA").value
    assert_true(ca >= 2 * per_model)
    s.atoms[ca].position = s.atoms[ca].position + v3(0, 0, 3) * _angstrom()
    var raw = model_distances(s, "CA", AS_GIVEN)
    var expected = 3.0 / sqrt(8.0)
    assert_almost_equal(
        raw.distance(ModelId(0), ModelId(2)).to(ANGSTROM), expected, rtol=1e-9
    )
    assert_almost_equal(
        raw.distance(ModelId(2), ModelId(1)).to(ANGSTROM), expected, rtol=1e-9
    )
    assert_equal(raw.distance(ModelId(0), ModelId(1)).to(METER), 0.0)
    # The fit takes up a little of the move.
    var fitted = model_distances(s, "CA", FIT_TO_REFERENCE)
    var d = fitted.distance(ModelId(0), ModelId(2)).to(ANGSTROM)
    assert_true(d > 0.8 * expected and d <= expected)
    assert_equal(fitted.medoid().value, 0)


def test_clusters() raises:
    var shifts: List[Float64] = [0, 0.5, 1.0, 5.0, 5.4, 20]
    var s = _ensemble(len(shifts))
    for k in range(1, len(shifts)):
        _move(s, k, 0, v3(shifts[k], 0, 0) * _angstrom())
    var table = model_distances(s, "CA", AS_GIVEN)
    var groups = cluster_models(table, Length64(1.0, ANGSTROM))
    # Models 0, 1 and 2 each have three neighbors; 0 is the center.
    assert_equal(len(groups), 3)
    assert_equal(len(groups[0]), 3)
    assert_equal(groups[0][0].value, 0)
    assert_equal(groups[0][1].value, 1)
    assert_equal(groups[0][2].value, 2)
    assert_equal(len(groups[1]), 2)
    assert_equal(groups[1][0].value, 3)
    assert_equal(groups[1][1].value, 4)
    assert_equal(len(groups[2]), 1)
    assert_equal(groups[2][0].value, 5)
    # With a cutoff of 0.5, model 1 has three neighbors and centers.
    var tight = cluster_models(table, Length64(0.5, ANGSTROM))
    assert_equal(tight[0][0].value, 1)
    assert_equal(len(tight[0]), 3)
    # With 0, each model is a cluster.
    assert_equal(len(cluster_models(table, Length64(0, METER))), 6)
    # With a wide cutoff, one cluster holds all.
    assert_equal(len(cluster_models(table, Length64(30, ANGSTROM))[0]), 6)


def test_refusals() raises:
    var one = _ensemble(1)
    with assert_raises(contains="two or more"):
        _ = model_distances(one, "CA", AS_GIVEN)
    var s = _ensemble(2)
    with assert_raises(contains="fit"):
        _ = model_distances(s, "CA", EnsembleFit(2))
    with assert_raises(contains="three shared"):
        _ = model_distances(s, "XX", AS_GIVEN)
    # One shared atom is enough to compare, but not to fit.
    var t = _ensemble(2)
    for a in range(len(t.atoms)):
        if t.atoms[a].name == "CA" and t.atoms[a].residue.value % 8 != 0:
            t.atoms[a].name = "CX"
    _ = model_distances(t, "CA", AS_GIVEN)
    with assert_raises(contains="three shared"):
        _ = model_distances(t, "CA", FIT_TO_REFERENCE)
    var table = model_distances(s, "CA", AS_GIVEN)
    with assert_raises(contains="outside"):
        _ = table.distance(ModelId(2), ModelId(0))
    with assert_raises(contains="outside"):
        _ = table.distance(ModelId(0), ModelId(-1))
    with assert_raises(contains="cutoff"):
        _ = cluster_models(table, Length64(-1, METER))
    with assert_raises(contains="cutoff"):
        _ = cluster_models(table, Length64(inf[DType.float64](), METER))
    # An empty table has no clusters.
    assert_equal(
        len(cluster_models(ModelDistances(0, 0), Length64(1, METER))), 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
