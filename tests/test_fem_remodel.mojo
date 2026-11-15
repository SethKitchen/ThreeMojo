# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Strain-adaptive bone remodeling.

A box on rollers under a uniform pressure has the same uniaxial stress in
every element, so its equilibrium density has a closed form:
`rho^(gamma + 1) = sigma^2 rho0^gamma / (2 C k)`.
"""

from extensions.clinical.distributions import precise_exp
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, ElementId, MaterialId
from extensions.fem.mesh import box_mesh, quadratic_mesh
from extensions.fem.remodel import (
    BoneLaw,
    JOULE_PER_KILOGRAM,
    RemodelingRule,
    SpecificEnergy64,
    remodel,
)
from extensions.fem.static import StaticProblem
from std.math import inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Density64,
    GIGAPASCAL,
    GRAM_PER_CUBIC_CENTIMETER,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    PASCAL,
    Pressure64,
)

comptime SIGMA = 1.0e6
comptime C = 3.79e9
comptime GAMMA = 3.0
comptime K = 0.02
comptime SIDE = 0.004


def _density(g: Float64) -> Density64:
    return Density64(g, GRAM_PER_CUBIC_CENTIMETER)


def _law() raises -> BoneLaw:
    return BoneLaw(Pressure64(C, PASCAL), GAMMA, 0.3)


def _rule(
    k: Float64, lazy: Float64, relaxation: Float64
) raises -> RemodelingRule:
    return RemodelingRule(
        SpecificEnergy64(k, JOULE_PER_KILOGRAM),
        lazy,
        _density(0.01),
        _density(2.0),
        relaxation,
    )


def _equilibrium(k: Float64) -> Float64:
    """The density in kg/m^3 at which a uniform stress SIGMA gives S = k."""
    return precise_exp(log(SIGMA * SIGMA * 1e9 / (2.0 * C * k)) / (GAMMA + 1.0))


def _box(stress: Float64, implant: Bool) raises -> StaticProblem:
    """A box of 4 mm on rollers, pressed on its top face. With `implant`,
    the elements whose center is below x = 2 mm are a stiff material 1."""
    var side = Length64(SIDE, METER)
    var mesh = box_mesh(side, side, side, 2, 2, 2)
    var materials: List[IsotropicMaterial] = [
        IsotropicMaterial(Pressure64(1, GIGAPASCAL), 0.3)
    ]
    if implant:
        materials.append(IsotropicMaterial(Pressure64(100, GIGAPASCAL), 0.3))
        for e in range(mesh.element_count()):
            var x = 0.0
            for node in mesh.element_nodes(ElementId(e)):
                x += mesh.nodes[node].x / 4.0
            if x < SIDE / 2.0:
                mesh.materials[e] = 1
    var problem = StaticProblem(mesh^, materials^)
    var near = Length64(1e-9, METER)
    var zero = Length64(0, METER)
    for node in problem.mesh.nodes_on_plane(DOF_X, zero, near):
        problem.fix(node, DOF_X, zero)
    for node in problem.mesh.nodes_on_plane(DOF_Y, zero, near):
        problem.fix(node, DOF_Y, zero)
    for node in problem.mesh.nodes_on_plane(DOF_Z, zero, near):
        problem.fix(node, DOF_Z, zero)
    if stress != 0:
        _ = problem.press_plane(DOF_Z, side, near, Pressure64(-stress, PASCAL))
    return problem^


def test_exact_equilibrium() raises:
    var target = _equilibrium(K)
    var found = remodel(
        _box(SIGMA, False),
        MaterialId(0),
        _law(),
        _rule(K, 0.0, 1.0),
        _density(1.0),
        50,
        1e-10,
        5000,
    )
    assert_true(found.converged)
    assert_equal(found.steps, 2)
    for e in range(len(found.densities)):
        assert_almost_equal(
            found.densities[e].to(KILOGRAM_PER_CUBIC_METER),
            target,
            rtol=1e-12,
        )
        assert_almost_equal(
            found.stimuli[e].to(JOULE_PER_KILOGRAM), K, rtol=1e-11
        )


def test_relaxed_steps() raises:
    # With a relaxation of a half, one step takes the geometric mean.
    var target = _equilibrium(K)
    var one = remodel(
        _box(SIGMA, False),
        MaterialId(0),
        _law(),
        _rule(K, 0.0, 0.5),
        _density(1.0),
        1,
        1e-10,
        5000,
    )
    assert_false(one.converged)
    assert_almost_equal(
        one.densities[0].to(KILOGRAM_PER_CUBIC_METER),
        (1000.0 * target) ** 0.5,
        rtol=1e-12,
    )
    var many = remodel(
        _box(SIGMA, False),
        MaterialId(0),
        _law(),
        _rule(K, 0.0, 0.5),
        _density(1.0),
        100,
        1e-9,
        5000,
    )
    assert_true(many.converged)
    assert_almost_equal(
        many.densities[5].to(KILOGRAM_PER_CUBIC_METER), target, rtol=2e-9
    )


def test_lazy_zone() raises:
    # Above the zone, the density goes to the stimulus (1 + s) k.
    var high = remodel(
        _box(SIGMA, False),
        MaterialId(0),
        _law(),
        _rule(K, 0.5, 1.0),
        _density(0.5),
        50,
        1e-10,
        5000,
    )
    assert_true(high.converged)
    assert_almost_equal(
        high.densities[0].to(KILOGRAM_PER_CUBIC_METER),
        _equilibrium(1.5 * K),
        rtol=1e-12,
    )
    # Below it, to (1 - s) k.
    var low = remodel(
        _box(SIGMA, False),
        MaterialId(0),
        _law(),
        _rule(K, 0.1, 1.0),
        _density(1.99),
        50,
        1e-10,
        5000,
    )
    assert_almost_equal(
        low.densities[0].to(KILOGRAM_PER_CUBIC_METER),
        _equilibrium(0.9 * K),
        rtol=1e-12,
    )
    # Inside it, nothing changes.
    var start = Density64(_equilibrium(K), KILOGRAM_PER_CUBIC_METER)
    var still = remodel(
        _box(SIGMA, False),
        MaterialId(0),
        _law(),
        _rule(K, 0.5, 1.0),
        start,
        50,
        1e-10,
        5000,
    )
    assert_equal(still.steps, 1)
    assert_equal(still.change, 0.0)
    assert_equal(
        still.densities[0].to(KILOGRAM_PER_CUBIC_METER),
        start.to(KILOGRAM_PER_CUBIC_METER),
    )


def test_bounds_and_shielding() raises:
    # A tiny stimulus asks for more than the most density, and a huge one
    # for less than the least.
    var dense = remodel(
        _box(SIGMA, False),
        MaterialId(0),
        _law(),
        _rule(1e-6, 0.0, 1.0),
        _density(1.0),
        50,
        1e-10,
        5000,
    )
    assert_almost_equal(
        dense.densities[0].to(GRAM_PER_CUBIC_CENTIMETER), 2.0, rtol=1e-15
    )
    var light = remodel(
        _box(0.0, False),
        MaterialId(0),
        _law(),
        _rule(K, 0.0, 1.0),
        _density(1.0),
        50,
        1e-10,
        5000,
    )
    assert_true(light.converged)
    assert_almost_equal(
        light.densities[0].to(GRAM_PER_CUBIC_CENTIMETER), 0.01, rtol=1e-15
    )
    # A stiff implant beside the bone carries the load: the bone thins.
    var shielded = remodel(
        _box(SIGMA, True),
        MaterialId(0),
        _law(),
        _rule(K, 0.0, 1.0),
        _density(1.0),
        200,
        1e-6,
        5000,
    )
    var total = 0.0
    var count = 0
    for d in shielded.densities:
        var rho = d.to(KILOGRAM_PER_CUBIC_METER)
        if rho > 0:
            total += rho
            count += 1
    assert_equal(count, 24)
    assert_true(total / Float64(count) < 0.9 * _equilibrium(K))


def test_errors() raises:
    with assert_raises(contains="coefficient"):
        _ = BoneLaw(Pressure64(0, PASCAL), 2.0, 0.3)
    with assert_raises(contains="coefficient"):
        _ = BoneLaw(Pressure64(inf[DType.float64](), PASCAL), 2.0, 0.3)
    var exponents: List[Float64] = [0.5, 5.0, nan[DType.float64]()]
    for g in exponents:
        with assert_raises(contains="exponent"):
            _ = BoneLaw(Pressure64(C, PASCAL), g, 0.3)
    var ratios: List[Float64] = [-1.0, 0.5]
    for nu in ratios:
        with assert_raises(contains="Poisson"):
            _ = BoneLaw(Pressure64(C, PASCAL), 2.0, nu)
    var stimuli: List[Float64] = [0.0, inf[DType.float64]()]
    for k in stimuli:
        with assert_raises(contains="stimulus"):
            _ = _rule(k, 0.0, 1.0)
    var lazies: List[Float64] = [-0.1, 1.0]
    for s in lazies:
        with assert_raises(contains="lazy zone"):
            _ = _rule(K, s, 1.0)
    var relaxations: List[Float64] = [0.0, 1.5]
    for w in relaxations:
        with assert_raises(contains="relaxation"):
            _ = _rule(K, 0.0, w)
    var bounds: List[Tuple[Float64, Float64]] = [
        (0.0, 1.0),
        (1.0, 0.5),
        (0.1, inf[DType.float64]()),
    ]
    for b in bounds:
        with assert_raises(contains="least < most"):
            _ = RemodelingRule(
                SpecificEnergy64(K, JOULE_PER_KILOGRAM),
                0.0,
                _density(b[0]),
                _density(b[1]),
                1.0,
            )
    var rule = _rule(K, 0.0, 1.0)
    var side = Length64(SIDE, METER)
    var quadratic = quadratic_mesh(box_mesh(side, side, side, 1, 1, 1))
    var materials: List[IsotropicMaterial] = [
        IsotropicMaterial(Pressure64(1, GIGAPASCAL), 0.3)
    ]
    with assert_raises(contains="four-node"):
        _ = remodel(
            StaticProblem(quadratic^, materials.copy()),
            MaterialId(0),
            _law(),
            rule.copy(),
            _density(1.0),
            5,
            1e-6,
            100,
        )
    with assert_raises(contains="material"):
        _ = remodel(
            _box(SIGMA, False),
            MaterialId(3),
            _law(),
            rule.copy(),
            _density(1.0),
            5,
            1e-6,
            100,
        )
    var starts: List[Float64] = [0.001, 3.0]
    for g in starts:
        with assert_raises(contains="start density"):
            _ = remodel(
                _box(SIGMA, False),
                MaterialId(0),
                _law(),
                rule.copy(),
                _density(g),
                5,
                1e-6,
                100,
            )
    var counts: List[Int] = [0, 1001]
    for n in counts:
        with assert_raises(contains="from 1 to 1000 steps"):
            _ = remodel(
                _box(SIGMA, False),
                MaterialId(0),
                _law(),
                rule.copy(),
                _density(1.0),
                n,
                1e-6,
                100,
            )
    var tolerances: List[Float64] = [0.0, 1.0]
    for t in tolerances:
        with assert_raises(contains="tolerance"):
            _ = remodel(
                _box(SIGMA, False),
                MaterialId(0),
                _law(),
                rule.copy(),
                _density(1.0),
                5,
                t,
                100,
            )
    with assert_raises(contains="iteration budget"):
        _ = remodel(
            _box(SIGMA, False),
            MaterialId(0),
            _law(),
            rule.copy(),
            _density(1.0),
            5,
            1e-6,
            1,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
