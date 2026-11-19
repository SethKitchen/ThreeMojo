# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Solved fields sampled at points inside a mesh."""

from extensions.fem.ids import DOF_X, ElementId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh, signed_volume
from extensions.fem.probe import (
    MeshPoint,
    locate_point,
    sample_displacement,
    sample_field,
    sample_temperature,
)
from extensions.fem.static import StaticResult
from extensions.fem.thermal import (
    ThermalMaterial,
    ThermalProblem,
    ThermalResult,
    solve_thermal,
)
from extensions.sdf.vector import V3, v3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Length64,
    METER,
    ThermalConductivity64,
    WATT_PER_METER_KELVIN,
)
from units.temperature import KELVIN, Temperature64


def _box(quadratic: Bool) raises -> TetMesh:
    var mesh = box_mesh(
        Length64(0.04, METER),
        Length64(0.03, METER),
        Length64(0.02, METER),
        4,
        3,
        2,
    )
    if quadratic:
        return quadratic_mesh(mesh)
    return mesh^


def _points() -> List[V3]:
    """Return points inside the box, off the nodes."""
    var out = List[V3]()
    for n in range(12):
        var t = Float64(n) / 12.0
        out.append(
            v3(
                0.001 + 0.037 * t,
                0.029 * (1 - t) + 0.0005,
                0.0013 + 0.017 * t * t,
            )
        )
    return out^


def _linear(p: V3) -> Float64:
    return 300 + 1000 * p.x - 500 * p.y + 200 * p.z


def _quadratic(p: V3) -> Float64:
    return _linear(p) + 4e4 * p.x * p.y - 3e4 * p.z * p.z + 2e4 * p.x * p.x


def test_fields_the_elements_hold() raises:
    for quadratic in [False, True]:
        var mesh = _box(quadratic)
        var temperatures = List[Float64]()
        var bent = List[Float64]()
        for p in mesh.nodes:
            temperatures.append(_linear(p))
            bent.append(_quadratic(p))
        for p in _points():
            var at = locate_point(mesh, p)
            var total = 0.0
            for w in at.weights:
                assert_true(w >= -1e-9)
                total += w
            assert_almost_equal(total, 1.0, atol=1e-12)
            var t = sample_field(mesh, at, temperatures, 1)
            assert_almost_equal(t[0], _linear(p), atol=1e-9)
            var q = sample_field(mesh, at, bent, 1)[0]
            if quadratic:
                # Ten nodes hold a quadratic field exactly.
                assert_almost_equal(q, _quadratic(p), atol=1e-9)
        # Four nodes do not: midway between nodes the sample is off.
        if not quadratic:
            var mid = v3(0.005, 0.005, 0.005)
            var q = sample_field(mesh, locate_point(mesh, mid), bent, 1)[0]
            assert_true(abs(q - _quadratic(mid)) > 1e-3)


def test_a_node_and_a_shared_face() raises:
    var mesh = _box(False)
    var node = mesh.nodes[7]
    var at = locate_point(mesh, node)
    var values = List[Float64]()
    for n in range(mesh.node_count()):
        values.append(Float64(n))
    # At a node the sample is the node's value.
    assert_almost_equal(sample_field(mesh, at, values, 1)[0], 7.0, atol=1e-9)
    # A point on the face between two cubes is in an element of each;
    # the lower element counts.
    var face = v3(0.01, 0.004, 0.003)
    var first = locate_point(mesh, face)
    var holders = List[Int]()
    for e in range(mesh.element_count()):
        var c = mesh.element_nodes(ElementId(e))
        var a = mesh.nodes[c[0]]
        var b = mesh.nodes[c[1]]
        var d = mesh.nodes[c[2]]
        var f = mesh.nodes[c[3]]
        var v = signed_volume(a, b, d, f)
        if (
            signed_volume(face, b, d, f) / v >= -1e-9
            and signed_volume(a, face, d, f) / v >= -1e-9
            and signed_volume(a, b, face, f) / v >= -1e-9
            and signed_volume(a, b, d, face) / v >= -1e-9
        ):
            holders.append(e)
    assert_equal(len(holders), 2)
    assert_equal(first.element.value, holders[0])
    # The field is continuous across the face.
    var other = MeshPoint(ElementId(holders[1]), [0.0, 0.0, 0.0, 0.0])
    var c = mesh.element_nodes(ElementId(holders[1]))
    var v = signed_volume(
        mesh.nodes[c[0]], mesh.nodes[c[1]], mesh.nodes[c[2]], mesh.nodes[c[3]]
    )
    other.weights[0] = (
        signed_volume(
            face, mesh.nodes[c[1]], mesh.nodes[c[2]], mesh.nodes[c[3]]
        )
        / v
    )
    other.weights[1] = (
        signed_volume(
            mesh.nodes[c[0]], face, mesh.nodes[c[2]], mesh.nodes[c[3]]
        )
        / v
    )
    other.weights[2] = (
        signed_volume(
            mesh.nodes[c[0]], mesh.nodes[c[1]], face, mesh.nodes[c[3]]
        )
        / v
    )
    other.weights[3] = (
        signed_volume(
            mesh.nodes[c[0]], mesh.nodes[c[1]], mesh.nodes[c[2]], face
        )
        / v
    )
    assert_almost_equal(
        sample_field(mesh, first, values, 1)[0],
        sample_field(mesh, other, values, 1)[0],
        atol=1e-9,
    )


def test_solved_results() raises:
    # Steady conduction from 300 K at x = 0 to 400 K at x = 0.04 m.
    for quadratic in [False, True]:
        var problem = ThermalProblem(
            _box(quadratic),
            [
                ThermalMaterial(
                    ThermalConductivity64(0.5, WATT_PER_METER_KELVIN)
                )
            ],
        )
        var near = Length64(1e-9, METER)
        for x in [0.0, 0.04]:
            for node in problem.mesh.nodes_on_plane(
                DOF_X, Length64(x, METER), near
            ):
                problem.fix(node, Temperature64(300 + 2500 * x, KELVIN))
        var result = solve_thermal(problem, 1e-12, 500)
        for p in _points():
            var t = sample_temperature(problem.mesh, result, p)
            assert_almost_equal(t.to(KELVIN), 300 + 2500 * p.x, atol=1e-6)
    # A displacement that grows along x, sampled between nodes.
    var mesh = _box(True)
    var result = StaticResult(mesh.node_count(), mesh.element_count())
    for n in range(mesh.node_count()):
        var p = mesh.nodes[n]
        result.displacements[3 * n] = 1e-3 * p.x
        result.displacements[3 * n + 1] = -2e-3 * p.x * p.y * 100
        result.displacements[3 * n + 2] = 5e-6
    for p in _points():
        var u = sample_displacement(mesh, result, p)
        assert_almost_equal(u.x, 1e-3 * p.x, atol=1e-15)
        assert_almost_equal(u.y, -2e-3 * p.x * p.y * 100, atol=1e-15)
        assert_almost_equal(u.z, 5e-6, atol=1e-15)


def test_refusals() raises:
    var mesh = _box(False)
    with assert_raises(contains="No element"):
        _ = locate_point(mesh, v3(0.05, 0.01, 0.01))
    with assert_raises(contains="No element"):
        _ = locate_point(TetMesh(), v3(0, 0, 0))
    var values = List[Float64](length=mesh.node_count(), fill=1)
    var at = locate_point(mesh, v3(0.01, 0.01, 0.01))
    with assert_raises(contains="element"):
        _ = sample_field(
            mesh, MeshPoint(ElementId(9999), at.weights.copy()), values, 1
        )
    with assert_raises(contains="four volume"):
        _ = sample_field(mesh, MeshPoint(at.element, [0.5, 0.5]), values, 1)
    with assert_raises(contains="1 to 64"):
        _ = sample_field(mesh, at, values, 0)
    with assert_raises(contains="1 to 64"):
        _ = sample_field(mesh, at, values, 65)
    with assert_raises(contains="every node"):
        _ = sample_field(mesh, at, values, 3)
    with assert_raises(contains="every node"):
        _ = sample_temperature(
            mesh, ThermalResult(List[Float64]()), v3(0.01, 0.01, 0.01)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
