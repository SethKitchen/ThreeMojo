# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Neo-Hookean large deformation against the exact uniaxial stretch.

A block held on three planes of symmetry and stretched along x deforms
homogeneously: `F = diag(l1, l2, l2)`, with the side stress zero. Linear
tetrahedra hold that field exactly, so the solve must give it.
"""

from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.hyperelastic import solve_neo_hookean
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, DofAxis, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.static import StaticProblem, solve_static
from std.math import log, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER, PASCAL, Pressure64

comptime LENGTH = 0.02
comptime SIDE = 0.01
# A soft tissue: 10 kPa, nearly incompressible.
comptime YOUNG = 10000.0
comptime POISSON = 0.45


def _material() raises -> IsotropicMaterial:
    return IsotropicMaterial(Pressure64(YOUNG, PASCAL), POISSON)


def _block() raises -> StaticProblem:
    """A block of 2 by 1 by 1 cubes, held on its three planes at 0."""
    var mesh = box_mesh(
        Length64(LENGTH, METER),
        Length64(SIDE, METER),
        Length64(SIDE, METER),
        2,
        1,
        1,
    )
    var problem = StaticProblem(mesh^, [_material()])
    var axes: List[DofAxis] = [DOF_X, DOF_Y, DOF_Z]
    for n in range(problem.mesh.node_count()):
        var p = problem.mesh.nodes[n]
        var at: List[Float64] = [p.x, p.y, p.z]
        for a in range(3):
            if at[a] < 1e-12:
                problem.fix(NodeId(n), axes[a], Length64(0, METER))
    return problem^


def _stretch(mut problem: StaticProblem, stretch: Float64) raises:
    for n in range(problem.mesh.node_count()):
        if problem.mesh.nodes[n].x > LENGTH - 1e-12:
            problem.fix(
                NodeId(n), DOF_X, Length64((stretch - 1.0) * LENGTH, METER)
            )


def _exact(l1: Float64) -> Tuple[Float64, Float64]:
    """Return the side stretch and the nominal stress along x."""
    var nu = POISSON
    var lam = YOUNG * nu / ((1.0 + nu) * (1.0 - 2.0 * nu))
    var mu = YOUNG / (2.0 * (1.0 + nu))
    # The side stress mu (l2 - 1 / l2) + lambda ln J / l2 is zero.
    var l2 = 1.0
    for _ in range(50):
        var j = l1 * l2 * l2
        var f = mu * (l2 * l2 - 1.0) + lam * log(j)
        var d = 2.0 * mu * l2 + 2.0 * lam / l2
        l2 -= f / d
    var j = l1 * l2 * l2
    return (l2, mu * (l1 - 1.0 / l1) + lam * log(j) / l1)


def test_uniaxial_stretch() raises:
    var problem = _block()
    _stretch(problem, 1.3)
    var result = solve_neo_hookean(problem, 4, 1e-10, 20, 1e-13, 2000)
    assert_true(result.converged)
    var exact = _exact(1.3)
    var l2 = exact[0]
    # Every node moves with the homogeneous field.
    for n in range(problem.mesh.node_count()):
        var p = problem.mesh.nodes[n]
        assert_almost_equal(
            result.displacements[3 * n + 1], (l2 - 1.0) * p.y, atol=1e-12
        )
        assert_almost_equal(
            result.displacements[3 * n + 2], (l2 - 1.0) * p.z, atol=1e-12
        )
    # The pull on the stretched face is the nominal stress times its area.
    var pull = 0.0
    for n in range(problem.mesh.node_count()):
        if problem.mesh.nodes[n].x > LENGTH - 1e-12:
            pull += result.reactions[3 * n]
    assert_almost_equal(pull, exact[1] * SIDE * SIDE, rtol=1e-9)
    var j = 1.3 * l2 * l2
    for e in range(problem.mesh.element_count()):
        assert_almost_equal(result.jacobians[e], j, rtol=1e-9)
        assert_almost_equal(
            result.stresses[6 * e], exact[1] * 1.3 / j, rtol=1e-8
        )
        assert_almost_equal(result.stresses[6 * e + 1], 0.0, atol=1e-6)
        assert_almost_equal(result.stresses[6 * e + 3], 0.0, atol=1e-6)
        assert_almost_equal(
            result.von_mises[e].to(PASCAL), exact[1] * 1.3 / j, rtol=1e-8
        )
    assert_true(result.newton_steps > 4)


def test_dead_load() raises:
    # The nominal stress of a stretch of 1.3, as a dead load, gives back
    # the stretch.
    var problem = _block()
    var exact = _exact(1.3)
    _ = problem.press_plane(
        DOF_X,
        Length64(LENGTH, METER),
        Length64(1e-9, METER),
        Pressure64(exact[1], PASCAL),
    )
    var result = solve_neo_hookean(problem, 6, 1e-10, 30, 1e-13, 2000)
    assert_true(result.converged)
    for n in range(problem.mesh.node_count()):
        var p = problem.mesh.nodes[n]
        assert_almost_equal(result.displacements[3 * n], 0.3 * p.x, atol=1e-11)


def test_small_strain() raises:
    # A stretch of 1e-6 is the linear solution, to its square.
    var nonlinear = _block()
    _stretch(nonlinear, 1.0 + 1e-6)
    var linear = _block()
    _stretch(linear, 1.0 + 1e-6)
    var a = solve_neo_hookean(nonlinear, 1, 1e-10, 10, 1e-14, 2000)
    var b = solve_static(linear, 1e-14, 2000)
    for d in range(len(a.displacements)):
        assert_almost_equal(a.displacements[d], b.displacements[d], atol=1e-14)
    for e in range(nonlinear.mesh.element_count()):
        assert_almost_equal(a.stresses[6 * e], b.stresses[6 * e], rtol=1e-5)


def test_limits_and_refusals() raises:
    # Every degree of freedom held: nothing to solve.
    var held = _block()
    for n in range(held.mesh.node_count()):
        held.fix(NodeId(n), DOF_X, Length64(0, METER))
        held.fix(NodeId(n), DOF_Y, Length64(0, METER))
        held.fix(NodeId(n), DOF_Z, Length64(0, METER))
    var still = solve_neo_hookean(held, 1, 1e-8, 5, 1e-12, 100)
    assert_true(still.converged)
    assert_equal(still.newton_steps, 0)
    # One Newton step does not reach the tolerance.
    var short = _block()
    _stretch(short, 1.5)
    var partial = solve_neo_hookean(short, 2, 1e-12, 1, 1e-13, 2000)
    assert_false(partial.converged)
    # A compression that turns an element inside out in one step.
    var crushed = _block()
    _stretch(crushed, -0.5)
    with assert_raises(contains="inside out"):
        _ = solve_neo_hookean(crushed, 1, 1e-8, 5, 1e-12, 100)
    var problem = _block()
    var counts: List[Int] = [0, 1001]
    for s in counts:
        with assert_raises(contains="load steps"):
            _ = solve_neo_hookean(problem, s, 1e-8, 5, 1e-12, 100)
    var tolerances: List[Float64] = [0.0, 1.0]
    for t in tolerances:
        with assert_raises(contains="Newton tolerance"):
            _ = solve_neo_hookean(problem, 1, t, 5, 1e-12, 100)
    with assert_raises(contains="one Newton step"):
        _ = solve_neo_hookean(problem, 1, 1e-8, 0, 1e-12, 100)
    var quadratic = StaticProblem(quadratic_mesh(problem.mesh), [_material()])
    with assert_raises(contains="four-node"):
        _ = solve_neo_hookean(quadratic, 1, 1e-8, 5, 1e-12, 100)
    problem.thermal[0] = 1e-3
    with assert_raises(contains="thermal"):
        _ = solve_neo_hookean(problem, 1, 1e-8, 5, 1e-12, 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
