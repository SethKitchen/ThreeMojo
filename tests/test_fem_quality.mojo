# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The radius ratio and the dihedral angles of tetrahedra."""

from extensions.fem.ids import ElementId, MaterialId, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.quality import element_quality, mesh_quality
from extensions.sdf.vector import V3, v3
from std.math import acos, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import DEGREE64, Length64, METER, RADIAN


def _add(mut mesh: TetMesh, a: V3, b: V3, c: V3, d: V3) raises:
    var n = mesh.node_count()
    _ = mesh.add_node(a)
    _ = mesh.add_node(b)
    _ = mesh.add_node(c)
    _ = mesh.add_node(d)
    _ = mesh.add_element(
        NodeId(n), NodeId(n + 1), NodeId(n + 2), NodeId(n + 3), MaterialId(0)
    )


def test_the_regular_tetrahedron() raises:
    var mesh = TetMesh()
    _add(mesh, v3(1, 1, 1), v3(1, -1, -1), v3(-1, 1, -1), v3(-1, -1, 1))
    var q = element_quality(mesh, ElementId(0))
    assert_almost_equal(q.radius_ratio, 1.0, atol=1e-12)
    var angle = acos(1.0 / 3.0)
    assert_almost_equal(q.smallest_angle.to(RADIAN), angle, atol=1e-12)
    assert_almost_equal(q.largest_angle.to(RADIAN), angle, atol=1e-12)


def test_the_tetrahedra_of_a_cube() raises:
    # A path through a unit cube: corners on its circumsphere, R = sqrt(3) / 2.
    var mesh = TetMesh()
    _add(mesh, v3(0, 0, 0), v3(1, 0, 0), v3(1, 1, 0), v3(1, 1, 1))
    var q = element_quality(mesh, ElementId(0))
    var kuhn = sqrt(3.0) / (1.0 + sqrt(2.0))
    assert_almost_equal(q.radius_ratio, kuhn, rtol=1e-12)
    assert_almost_equal(q.smallest_angle.to(DEGREE64), 45.0, atol=1e-9)
    assert_almost_equal(q.largest_angle.to(DEGREE64), 90.0, atol=1e-9)
    # Every element of a box of cubes is such a tetrahedron, for both orders.
    var side = Length64(0.02, METER)
    var box = box_mesh(side, side, side, 2, 2, 2)
    for m in [box.copy(), quadratic_mesh(box)]:
        var all = mesh_quality(m)
        assert_almost_equal(all.worst_ratio, kuhn, rtol=1e-9)
        assert_almost_equal(all.mean_ratio, kuhn, rtol=1e-9)
        assert_almost_equal(all.smallest_angle.to(DEGREE64), 45.0, atol=1e-7)
        assert_almost_equal(all.largest_angle.to(DEGREE64), 90.0, atol=1e-7)
        # The elements tie, to rounding, so any of them can be the worst.
        assert_true(
            all.worst_element.value >= 0
            and all.worst_element.value < m.element_count()
        )


def test_a_sliver_is_the_worst() raises:
    var mesh = TetMesh()
    _add(mesh, v3(1, 1, 1), v3(1, -1, -1), v3(-1, 1, -1), v3(-1, -1, 1))
    _add(mesh, v3(0, 0, 0), v3(1, 0, 0), v3(0, 1, 0), v3(0.4, 0.4, 0.01))
    _add(mesh, v3(0, 0, 5), v3(1, 0, 5), v3(1, 1, 5), v3(1, 1, 6))
    var sliver = element_quality(mesh, ElementId(1))
    assert_true(sliver.radius_ratio < 0.1)
    assert_true(sliver.largest_angle.to(DEGREE64) > 170)
    assert_true(sliver.smallest_angle.to(DEGREE64) < 5)
    var all = mesh_quality(mesh)
    assert_equal(all.worst_element.value, 1)
    assert_almost_equal(all.worst_ratio, sliver.radius_ratio)
    assert_almost_equal(
        all.smallest_angle.to(RADIAN), sliver.smallest_angle.to(RADIAN)
    )
    assert_almost_equal(
        all.largest_angle.to(RADIAN), sliver.largest_angle.to(RADIAN)
    )
    var kuhn = sqrt(3.0) / (1.0 + sqrt(2.0))
    assert_almost_equal(
        all.mean_ratio, (1.0 + sliver.radius_ratio + kuhn) / 3.0, rtol=1e-12
    )


def test_refusals() raises:
    var mesh = TetMesh()
    with assert_raises(contains="no quality"):
        _ = mesh_quality(mesh)
    _add(mesh, v3(0, 0, 0), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
    with assert_raises(contains="element"):
        _ = element_quality(mesh, ElementId(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
