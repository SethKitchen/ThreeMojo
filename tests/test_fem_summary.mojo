# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stress summary of each material of a solved model."""

from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z
from extensions.fem.mesh import TetMesh, box_mesh
from extensions.fem.static import StaticProblem, StaticResult, solve_static
from extensions.fem.summary import stress_summary
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import (
    CUBIC_METER,
    GIGAPASCAL,
    Length64,
    MEGAPASCAL,
    METER,
    PASCAL,
    Pressure64,
)


def test_given_stresses() raises:
    # Two cubes of 1 m: twelve Kuhn tetrahedra of 1/6 m^3 each.
    var mesh = box_mesh(
        Length64(2, METER), Length64(1, METER), Length64(1, METER), 2, 1, 1
    )
    var count = mesh.element_count()
    assert_equal(count, 12)
    var result = StaticResult(mesh.node_count(), count)
    # Even elements are material 0, with 10 to 15 Pa; odd ones material 2,
    # with 100 Pa. Material 1 has no element.
    for e in range(count):
        if e % 2 == 0:
            mesh.materials[e] = 0
            result.von_mises[e] = Pressure64(Float64(10 + e // 2), PASCAL)
        else:
            mesh.materials[e] = 2
            result.von_mises[e] = Pressure64(100, PASCAL)
    var rows = stress_summary(mesh, result, Pressure64(12, PASCAL))
    assert_equal(len(rows), 2)
    assert_equal(rows[0].material.value, 0)
    assert_equal(rows[1].material.value, 2)
    assert_equal(rows[0].elements, 6)
    assert_almost_equal(rows[0].volume.to(CUBIC_METER), 1.0, rtol=1e-12)
    assert_almost_equal(rows[0].peak.to(PASCAL), 15.0)
    assert_almost_equal(rows[0].mean.to(PASCAL), 12.5, rtol=1e-12)
    # 12, 13, 14 and 15 Pa are at or above 12 Pa.
    assert_almost_equal(rows[0].over.to(CUBIC_METER), 4.0 / 6.0, rtol=1e-12)
    assert_almost_equal(rows[1].mean.to(PASCAL), 100.0, rtol=1e-12)
    assert_almost_equal(rows[1].over.to(CUBIC_METER), 1.0, rtol=1e-12)
    var none = stress_summary(mesh, result, Pressure64(1000, PASCAL))
    assert_equal(none[1].over.to(CUBIC_METER), 0.0)


def test_a_pulled_bar() raises:
    # A strain of 0.001 along x with the sides held and Poisson's ratio
    # zero: 200 MPa in every element.
    var mesh = box_mesh(
        Length64(2, METER), Length64(1, METER), Length64(1, METER), 2, 1, 1
    )
    var problem = StaticProblem(
        mesh^, [IsotropicMaterial(Pressure64(200, GIGAPASCAL), 0.0)]
    )
    var near = Length64(1e-9, METER)
    for n in problem.mesh.nodes_on_plane(DOF_X, Length64(0, METER), near):
        problem.fix(n, DOF_X, Length64(0, METER))
        problem.fix(n, DOF_Y, Length64(0, METER))
        problem.fix(n, DOF_Z, Length64(0, METER))
    for n in problem.mesh.nodes_on_plane(DOF_X, Length64(2, METER), near):
        problem.fix(n, DOF_X, Length64(0.002, METER))
        problem.fix(n, DOF_Y, Length64(0, METER))
        problem.fix(n, DOF_Z, Length64(0, METER))
    var result = solve_static(problem, 1e-12, 200)
    var rows = stress_summary(problem.mesh, result, Pressure64(199, MEGAPASCAL))
    assert_equal(len(rows), 1)
    assert_almost_equal(rows[0].peak.to(MEGAPASCAL), 200.0, rtol=1e-6)
    assert_almost_equal(rows[0].mean.to(MEGAPASCAL), 200.0, rtol=1e-6)
    assert_almost_equal(rows[0].over.to(CUBIC_METER), 2.0, rtol=1e-12)


def test_refusals() raises:
    var mesh = box_mesh(
        Length64(1, METER), Length64(1, METER), Length64(1, METER), 1, 1, 1
    )
    var result = StaticResult(mesh.node_count(), mesh.element_count())
    # A mesh without elements has no material.
    assert_equal(
        len(
            stress_summary(TetMesh(), StaticResult(0, 0), Pressure64(0, PASCAL))
        ),
        0,
    )
    with assert_raises(contains="not for this mesh"):
        _ = stress_summary(mesh, StaticResult(8, 2), Pressure64(0, PASCAL))
    with assert_raises(contains="threshold"):
        _ = stress_summary(mesh, result, Pressure64(-1, PASCAL))
    with assert_raises(contains="threshold"):
        _ = stress_summary(
            mesh, result, Pressure64(inf[DType.float64](), PASCAL)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
