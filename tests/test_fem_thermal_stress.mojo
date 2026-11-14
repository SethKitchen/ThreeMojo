# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stresses from a temperature change."""

from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.static import StaticProblem, solve_static
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    GIGAPASCAL,
    Length64,
    METER,
    PASCAL,
    PER_KELVIN,
    Pressure64,
    ThermalExpansion64,
)
from units.temperature import KELVIN_DIFFERENCE, TemperatureDifference64

comptime LENGTH = 1.0
comptime YOUNG = 200.0e9
comptime ALPHA = 1.2e-5
comptime CHANGE = 50.0


def _bar(quadratic: Bool, held: Bool) raises -> StaticProblem:
    """A steel bar along x on symmetry planes, heated by 50 K."""
    var mesh = box_mesh(
        Length64(LENGTH, METER),
        Length64(0.1, METER),
        Length64(0.1, METER),
        4,
        1,
        1,
    )
    if quadratic:
        mesh = quadratic_mesh(mesh)
    var problem = StaticProblem(
        mesh^, [IsotropicMaterial(Pressure64(YOUNG / 1e9, GIGAPASCAL), 0.3)]
    )
    var near = Length64(1e-9, METER)
    var zero = Length64(0, METER)
    for node in problem.mesh.nodes_on_plane(DOF_X, zero, near):
        problem.fix(node, DOF_X, zero)
    for node in problem.mesh.nodes_on_plane(DOF_Y, zero, near):
        problem.fix(node, DOF_Y, zero)
    for node in problem.mesh.nodes_on_plane(DOF_Z, zero, near):
        problem.fix(node, DOF_Z, zero)
    if held:
        for node in problem.mesh.nodes_on_plane(
            DOF_X, Length64(LENGTH, METER), near
        ):
            problem.fix(node, DOF_X, zero)
    var changes = List[TemperatureDifference64]()
    for _ in range(problem.mesh.node_count()):
        changes.append(TemperatureDifference64(CHANGE, KELVIN_DIFFERENCE))
    problem.heat([ThermalExpansion64(ALPHA, PER_KELVIN)], changes)
    return problem^


def test_a_free_bar_only_grows() raises:
    for quadratic in [False, True]:
        var problem = _bar(quadratic, False)
        var result = solve_static(problem, 1e-13, 5000)
        # Each point moves by alpha dT times its distance from the planes.
        for n in range(problem.mesh.node_count()):
            var p = problem.mesh.nodes[n]
            var d = result.displacement(NodeId(n))
            assert_almost_equal(d.x, ALPHA * CHANGE * p.x, atol=1e-12)
            assert_almost_equal(d.y, ALPHA * CHANGE * p.y, atol=1e-12)
        for stress in result.von_mises:
            assert_true(stress.to(PASCAL) < 1e-3)


def test_a_held_bar_is_stressed() raises:
    for quadratic in [False, True]:
        var problem = _bar(quadratic, True)
        var result = solve_static(problem, 1e-13, 5000)
        # Held along x and free across: a uniaxial stress of -E alpha dT.
        var expected = -YOUNG * ALPHA * CHANGE
        for e in range(problem.mesh.element_count()):
            assert_almost_equal(result.stresses[6 * e], expected, rtol=1e-6)
            assert_almost_equal(result.stresses[6 * e + 1], 0, atol=1e-2)
        # The support pushes the far end back, along -x, with the stress
        # times the area.
        var push = 0.0
        for node in problem.mesh.nodes_on_plane(
            DOF_X, Length64(LENGTH, METER), Length64(1e-9, METER)
        ):
            push += result.reactions[3 * node.value]
        assert_almost_equal(push, expected * 0.01, rtol=1e-6)


def test_refusals() raises:
    var mesh = box_mesh(
        Length64(1, METER), Length64(1, METER), Length64(1, METER), 1, 1, 1
    )
    var problem = StaticProblem(
        mesh^, [IsotropicMaterial(Pressure64(200, GIGAPASCAL), 0.3)]
    )
    var changes = List[TemperatureDifference64]()
    for _ in range(problem.mesh.node_count()):
        changes.append(TemperatureDifference64(1, KELVIN_DIFFERENCE))
    var alpha = ThermalExpansion64(ALPHA, PER_KELVIN)
    with assert_raises(contains="one expansion for each material"):
        problem.heat(List[ThermalExpansion64](), changes)
    with assert_raises(contains="one temperature change for each node"):
        problem.heat([alpha], List[TemperatureDifference64]())
    with assert_raises(contains="expansion must be finite"):
        problem.heat(
            [ThermalExpansion64(inf[DType.float64](), PER_KELVIN)], changes
        )
    var bad = changes.copy()
    bad[0] = TemperatureDifference64(inf[DType.float64](), KELVIN_DIFFERENCE)
    with assert_raises(contains="temperature change must be finite"):
        problem.heat([alpha], bad)
    # Two calls add.
    problem.heat([alpha], changes)
    problem.heat([alpha], changes)
    assert_almost_equal(problem.thermal[0], 2 * ALPHA, rtol=1e-12)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
