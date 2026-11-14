# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Legacy VTK files of tetrahedral meshes and their results."""

from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.export import vtk_mesh, vtk_result
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, MaterialId, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.static import StaticProblem, StaticResult, solve_static
from extensions.sdf.vector import v3
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import GIGAPASCAL, Length64, METER, PASCAL, Pressure64


def _one() raises -> TetMesh:
    var mesh = TetMesh()
    _ = mesh.add_node(v3(0, 0, 0))
    _ = mesh.add_node(v3(0.5, 0, 0))
    _ = mesh.add_node(v3(0, 0.25, 0))
    _ = mesh.add_node(v3(0, 0, 2))
    _ = mesh.add_element(
        NodeId(0), NodeId(1), NodeId(2), NodeId(3), MaterialId(3)
    )
    return mesh^


def test_linear_mesh_text() raises:
    var text = vtk_mesh(_one())
    var expected = String(
        "# vtk DataFile Version 3.0\n"
        "ThreeMojo tetrahedral mesh, meters\n"
        "ASCII\n"
        "DATASET UNSTRUCTURED_GRID\n"
        "POINTS 4 double\n"
        "0.0 0.0 0.0\n"
        "0.5 0.0 0.0\n"
        "0.0 0.25 0.0\n"
        "0.0 0.0 2.0\n"
        "CELLS 1 5\n"
        "4 0 1 2 3\n"
        "CELL_TYPES 1\n"
        "10\n"
        "CELL_DATA 1\n"
        "SCALARS material int 1\n"
        "LOOKUP_TABLE default\n"
        "3\n"
    )
    assert_equal(text, expected)


def test_quadratic_cells() raises:
    var mesh = quadratic_mesh(_one())
    var text = vtk_mesh(mesh)
    assert_true("CELLS 1 11\n10 0 1 2 3 4 5 6 7 8 9\n" in text)
    assert_true("CELL_TYPES 1\n24\n" in text)
    assert_true("POINTS 10 double\n" in text)


def test_result_fields() raises:
    var mesh = box_mesh(
        Length64(2, METER), Length64(1, METER), Length64(1, METER), 1, 1, 1
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
    var result = solve_static(problem, 1e-12, 100)
    var text = vtk_result(problem.mesh, result)
    # With Poisson's ratio zero and the sides held, a strain of 0.001 gives
    # 200 MPa along x and nothing else.
    assert_true("SCALARS von_mises double 1\nLOOKUP_TABLE default\n" in text)
    assert_true("TENSORS stress double\n" in text)
    assert_true("POINT_DATA 8\nVECTORS displacement double\n" in text)
    assert_true("\n0.002 0.0 0.0\n" in text)
    var lines = text.split("\n")
    var tensor_line = 0
    for index in range(len(lines)):
        if lines[index] == "TENSORS stress double":
            tensor_line = index + 1
    var first = String(lines[tensor_line]).split(" ")
    assert_equal(len(first), 9)
    assert_true(abs(atof(first[0]) - 200e6) < 1e-3)
    assert_true(abs(atof(first[4])) < 1e-3)
    assert_true(abs(result.von_mises[0].to(PASCAL) - 200e6) < 1e-3)


def test_empty_and_refusals() raises:
    var empty = vtk_result(TetMesh(), StaticResult(0, 0))
    assert_true("POINTS 0 double\nCELLS 0 0\n" in empty)
    var mesh = _one()
    with assert_raises(contains="not for this mesh"):
        _ = vtk_result(mesh, StaticResult(5, 1))
    with assert_raises(contains="not for this mesh"):
        _ = vtk_result(mesh, StaticResult(4, 2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
