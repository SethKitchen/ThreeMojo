# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Effective strains and the failure factor of Pistoia and others."""

from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.failure import effective_strains, pistoia_failure
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, MaterialId
from extensions.fem.mesh import box_mesh
from extensions.fem.static import StaticProblem, StaticResult, solve_static
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import CUBIC_METER, GIGAPASCAL, Length64, METER, Pressure64


def _bar(var problem: StaticProblem, stretch: Float64) raises -> StaticProblem:
    """Hold the end at x = 0 and pull the end at x = 2 by a stretch, with
    the sides held."""
    var near = Length64(1e-9, METER)
    var axes = [DOF_X, DOF_Y, DOF_Z]
    for n in problem.mesh.nodes_on_plane(DOF_X, Length64(0, METER), near):
        for axis in axes:
            problem.fix(n, axis, Length64(0, METER))
    for n in problem.mesh.nodes_on_plane(DOF_X, Length64(2, METER), near):
        problem.fix(n, DOF_X, Length64(stretch, METER))
        problem.fix(n, DOF_Y, Length64(0, METER))
        problem.fix(n, DOF_Z, Length64(0, METER))
    return problem^


def test_a_uniform_bar() raises:
    # A strain of 0.001 with Poisson's ratio 0: the effective strain is the
    # strain, so the bar fails at 7 times the load.
    var mesh = box_mesh(
        Length64(2, METER), Length64(1, METER), Length64(1, METER), 2, 1, 1
    )
    var problem = _bar(
        StaticProblem(
            mesh^, [IsotropicMaterial(Pressure64(10, GIGAPASCAL), 0.0)]
        ),
        0.002,
    )
    var result = solve_static(problem, 1e-12, 200)
    var strains = effective_strains(problem, result)
    assert_equal(len(strains), 12)
    for s in strains:
        assert_almost_equal(s, 0.001, atol=1e-12)
    var failure = pistoia_failure(problem, result, MaterialId(0), 0.007, 0.02)
    assert_almost_equal(failure.factor, 7.0, rtol=1e-9)
    assert_almost_equal(failure.threshold, 0.001, rtol=1e-9)
    assert_almost_equal(failure.volume.to(CUBIC_METER), 2.0, rtol=1e-12)
    assert_equal(failure.elements, 12)


def test_two_materials_in_series() raises:
    # A soft half and a stiff half carry one stress: the stiff half strains
    # half as much.
    var mesh = box_mesh(
        Length64(2, METER), Length64(1, METER), Length64(1, METER), 2, 1, 1
    )
    for e in range(mesh.element_count()):
        var at = 4 * e
        var x = 0.0
        for k in range(4):
            x += mesh.nodes[mesh.corners[at + k]].x / 4.0
        mesh.materials[e] = 0 if x < 1.0 else 1
    var problem = _bar(
        StaticProblem(
            mesh^,
            [
                IsotropicMaterial(Pressure64(10, GIGAPASCAL), 0.0),
                IsotropicMaterial(Pressure64(20, GIGAPASCAL), 0.0),
            ],
        ),
        0.003,
    )
    var result = solve_static(problem, 1e-12, 400)
    # The stress is 3 mm / (1 / 10 GPa + 1 / 20 GPa) = 20 MPa, so the strains
    # are 0.002 and 0.001.
    var soft = pistoia_failure(problem, result, MaterialId(0), 0.007, 0.5)
    var stiff = pistoia_failure(problem, result, MaterialId(1), 0.007, 0.5)
    assert_almost_equal(soft.threshold, 0.002, rtol=1e-9)
    assert_almost_equal(stiff.threshold, 0.001, rtol=1e-9)
    assert_almost_equal(soft.factor, 3.5, rtol=1e-9)
    assert_equal(stiff.elements, 6)


def test_the_critical_volume() raises:
    # Twelve elements of 1/6 m^3 with effective strains of 1e-4 to 12e-4.
    var mesh = box_mesh(
        Length64(2, METER), Length64(1, METER), Length64(1, METER), 2, 1, 1
    )
    var problem = StaticProblem(
        mesh^, [IsotropicMaterial(Pressure64(10, GIGAPASCAL), 0.0)]
    )
    var result = StaticResult(problem.mesh.node_count(), 12)
    for e in range(12):
        var strain = Float64(e + 1) * 1e-4
        result.strains[6 * e] = strain
        result.stresses[6 * e] = 1.0e10 * strain
    # A fifth of 2 m^3 is 0.4 m^3: the three largest reach it.
    var fifth = pistoia_failure(problem, result, MaterialId(0), 0.007, 0.2)
    assert_almost_equal(fifth.threshold, 10e-4, rtol=1e-12)
    assert_almost_equal(fifth.factor, 7.0, rtol=1e-12)
    # A twentieth is reached by the largest alone.
    var small = pistoia_failure(problem, result, MaterialId(0), 0.007, 0.05)
    assert_almost_equal(small.threshold, 12e-4, rtol=1e-12)
    # A negative energy, from a result that is not elastic, counts as 0.
    result.stresses[0] = -1.0
    assert_equal(effective_strains(problem, result)[0], 0.0)


def test_refusals() raises:
    var mesh = box_mesh(
        Length64(2, METER), Length64(1, METER), Length64(1, METER), 2, 1, 1
    )
    var problem = StaticProblem(
        mesh^,
        [
            IsotropicMaterial(Pressure64(10, GIGAPASCAL), 0.0),
            IsotropicMaterial(Pressure64(10, GIGAPASCAL), 0.0),
        ],
    )
    var result = StaticResult(problem.mesh.node_count(), 12)
    with assert_raises(contains="not for this problem"):
        _ = effective_strains(problem, StaticResult(2, 1))
    var bad_strains = StaticResult(problem.mesh.node_count(), 12)
    bad_strains.stresses = List[Float64](length=6, fill=0.0)
    with assert_raises(contains="not for this problem"):
        _ = effective_strains(problem, bad_strains)
    with assert_raises(contains="names no material"):
        _ = pistoia_failure(problem, result, MaterialId(-1), 0.007, 0.02)
    with assert_raises(contains="names no material"):
        _ = pistoia_failure(problem, result, MaterialId(2), 0.007, 0.02)
    var critical: List[Float64] = [
        0.0,
        inf[DType.float64](),
        nan[DType.float64](),
    ]
    for c in critical:
        with assert_raises(contains="critical strain"):
            _ = pistoia_failure(problem, result, MaterialId(0), c, 0.02)
    var shares: List[Float64] = [0.0, 1.0]
    for f in shares:
        with assert_raises(contains="between 0 and 1"):
            _ = pistoia_failure(problem, result, MaterialId(0), 0.007, f)
    with assert_raises(contains="no element"):
        _ = pistoia_failure(problem, result, MaterialId(1), 0.007, 0.02)
    with assert_raises(contains="no strain"):
        _ = pistoia_failure(problem, result, MaterialId(0), 0.007, 0.02)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
