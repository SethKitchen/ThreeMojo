# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The fluctuation of atoms over the models of an ensemble."""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ensemble import (
    Fluctuation,
    ensemble_fluctuation,
    fluctuation_b_factors,
)
from extensions.molecule.ids import (
    AS_GIVEN,
    AtomId,
    COIL,
    ChainId,
    EnsembleFit,
    FIT_TO_REFERENCE,
    HELIX,
    ModelId,
    ResidueId,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.structure import Model, SQUARE_ANGSTROM, Structure
from extensions.sdf.vector import V3, v3
from std.math import cos, pi, sin, sqrt
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


def _base() raises -> Structure:
    var kinds = List[SecondaryKind]()
    for _ in range(8):
        kinds.append(HELIX)
    return build_peptide("MAEKLAGK", kinds)


def _ensemble(base: Structure, count: Int) -> Structure:
    """Return `count` copies of the one model of `base`, numbered 1 on."""
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


def _ca(s: Structure, model: Int, residue: Int) raises -> Int:
    var per_model = len(s.residues) // len(s.models)
    return s.find_atom(ResidueId(model * per_model + residue), "CA").value


def _turn(p: V3, angle: Float64, shift: V3) -> V3:
    """Turn a point about the z axis, then shift it."""
    var c = cos(angle)
    var s = sin(angle)
    return v3(c * p.x - s * p.y, s * p.x + c * p.y, p.z) + shift


def test_one_atom_that_moves_as_given() raises:
    var s = _ensemble(_base(), 3)
    var d = 0.6 * _angstrom()
    s.atoms[_ca(s, 1, 3)].position = s.atoms[_ca(s, 1, 3)].position + v3(
        d, 0, 0
    )
    s.atoms[_ca(s, 2, 3)].position = s.atoms[_ca(s, 2, 3)].position - v3(
        d, 0, 0
    )
    var f = ensemble_fluctuation(s, "CA", ModelId(0), AS_GIVEN)
    assert_equal(f.count(), 8)
    for row in range(8):
        assert_equal(f.atoms[row].value, _ca(s, 0, row))
        var expected = 0.0
        if row == 3:
            # The mean stays, and two of three models are d away.
            expected = d * sqrt(2.0 / 3.0)
        assert_almost_equal(
            f.fluctuation(row).to(METER), expected, atol=1e-6 * d
        )
    assert_almost_equal(f.deviation(ModelId(0)).to(METER), 0.0)
    assert_almost_equal(
        f.deviation(ModelId(1)).to(METER), d / sqrt(8.0), rtol=1e-12
    )
    assert_almost_equal(
        f.deviation(ModelId(2)).to(METER), d / sqrt(8.0), rtol=1e-12
    )
    # Each atom of residue 3 gets B = 8 pi^2 RMSF^2 / 3.
    fluctuation_b_factors(s, f)
    var b = 16.0 * pi * pi * d * d / 9.0
    for a in range(s.residues[3].first_atom, s.residues[3].first_atom + 5):
        assert_almost_equal(s.atoms[a].b_factor.value, b, rtol=1e-9)
    assert_almost_equal(s.atoms[0].b_factor.value, 0.0)
    # The other models keep their B-factors.
    assert_almost_equal(s.atoms[_ca(s, 1, 3)].b_factor.value, 0.0)


def test_rigid_moves_fit_away() raises:
    var s = _ensemble(_base(), 3)
    var per_model = len(s.atoms) // 3
    for k in range(1, 3):
        var shift = v3(Float64(k) * 5, -3, 2) * _angstrom()
        for a in range(k * per_model, (k + 1) * per_model):
            s.atoms[a].position = _turn(
                s.atoms[a].position, 0.7 * Float64(k), shift
            )
    var fitted = ensemble_fluctuation(s, "CA", ModelId(0), FIT_TO_REFERENCE)
    var raw = ensemble_fluctuation(s, "CA", ModelId(0), AS_GIVEN)
    for row in range(fitted.count()):
        assert_true(fitted.fluctuation(row).to(ANGSTROM) < 1e-9)
        assert_true(raw.fluctuation(row).to(ANGSTROM) > 1.0)
    for k in range(3):
        assert_true(fitted.deviation(ModelId(k)).to(ANGSTROM) < 1e-9)
    # Any model can be the reference.
    var second = ensemble_fluctuation(s, "CA", ModelId(1), FIT_TO_REFERENCE)
    assert_equal(second.atoms[0].value, _ca(s, 1, 0))
    assert_true(second.fluctuation(0).to(ANGSTROM) < 1e-9)


def test_a_loop_that_moves_after_the_fit() raises:
    # Model 2 is model 1 with one CA moved by d, then turned and shifted.
    var s = _ensemble(_base(), 2)
    var d = 2.0 * _angstrom()
    var moved = _ca(s, 1, 6)
    s.atoms[moved].position = s.atoms[moved].position + v3(0, 0, d)
    var per_model = len(s.atoms) // 2
    for a in range(per_model, 2 * per_model):
        s.atoms[a].position = _turn(
            s.atoms[a].position, 1.1, v3(4, 4, 4) * _angstrom()
        )
    var f = ensemble_fluctuation(s, "CA", ModelId(0), FIT_TO_REFERENCE)
    # Two models d apart have an RMSF of d / 2. The fit takes up a
    # little of the move, and spreads a little over the other atoms.
    var top = f.fluctuation(6).to(METER)
    assert_true(top > 0.35 * d and top <= 0.5 * d)
    for row in range(8):
        if row != 6:
            assert_true(f.fluctuation(row).to(METER) < 0.15 * d)


def test_shared_atoms_only() raises:
    var s = _ensemble(_base(), 3)
    # Model 3 has no CA in residue 5, and glycine 7 has no CB.
    s.atoms[_ca(s, 2, 5)].name = "CX"
    var ca = ensemble_fluctuation(s, "CA", ModelId(0), AS_GIVEN)
    assert_equal(ca.count(), 7)
    for row in range(7):
        assert_true(ca.atoms[row].value != _ca(s, 0, 5))
    var cb = ensemble_fluctuation(s, "CB", ModelId(0), AS_GIVEN)
    assert_equal(cb.count(), 7)
    # An empty result changes nothing.
    fluctuation_b_factors(s, Fluctuation())


def test_refusals() raises:
    var s = _ensemble(_base(), 2)
    with assert_raises(contains="ensemble fit"):
        _ = ensemble_fluctuation(s, "CA", ModelId(0), EnsembleFit(2))
    with assert_raises(contains="model"):
        _ = ensemble_fluctuation(s, "CA", ModelId(2), AS_GIVEN)
    with assert_raises(contains="two or more models"):
        _ = ensemble_fluctuation(_base(), "CA", ModelId(0), AS_GIVEN)
    with assert_raises(contains="three shared atoms"):
        _ = ensemble_fluctuation(s, "XX", ModelId(0), AS_GIVEN)
    var kinds: List[SecondaryKind] = [COIL, COIL]
    var pair = _ensemble(build_peptide("AK", kinds), 2)
    with assert_raises(contains="three shared atoms"):
        _ = ensemble_fluctuation(pair, "CA", ModelId(0), FIT_TO_REFERENCE)
    # Two atoms are enough to compare as given.
    assert_equal(
        ensemble_fluctuation(pair, "CA", ModelId(0), AS_GIVEN).count(), 2
    )
    var f = ensemble_fluctuation(s, "CA", ModelId(0), AS_GIVEN)
    with assert_raises(contains="outside the result"):
        _ = f.fluctuation(8)
    with assert_raises(contains="outside the result"):
        _ = f.fluctuation(-1)
    with assert_raises(contains="outside the result"):
        _ = f.deviation(ModelId(2))
    with assert_raises(contains="outside the result"):
        _ = f.deviation(ModelId(-1))
    var stray = Fluctuation()
    stray.atoms.append(AtomId(99999))
    stray.rmsf.append(0.0)
    with assert_raises(contains="atom"):
        fluctuation_b_factors(s, stray)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
