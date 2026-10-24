# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Rigid town placement matches the reviewed axis swap and matrix."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_place import (
    cell_text,
    matrix_rows,
    matrix_text,
    place_rigid,
)


def test_an_identity_copy_moves_in_meters() raises:
    var text = matrix_text(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 3200.0, 0.0, 0.0)
    assert_true(text.startswith("[[1.0,0.0,0.0,0.0],"))
    assert_true(text.find("[3200.0,0.0,0.0,1.0]") >= 0)
    var matrix = matrix_rows(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 3200.0, 0.0, 0.0)
    var positions = List[Float64]()
    positions.append(-0.5)
    positions.append(-0.5)
    positions.append(-0.5)
    var normals = List[Float64]()
    normals.append(0.0)
    normals.append(1.0)
    normals.append(0.0)
    var triangles = List[Int]()
    triangles.append(0)
    triangles.append(1)
    triangles.append(2)
    var placed = place_rigid(matrix, positions, normals, triangles)
    assert_true(placed.find("[31.5,-0.5,-0.5]") >= 0)
    assert_true(placed.find('"triangles":[[0,1,2]]') >= 0)


def test_a_negative_scale_reverses_a_triangle() raises:
    var matrix = matrix_rows(0.0, 0.0, 0.0, -1.0, 1.0, 1.0, 0.0, 0.0, 0.0)
    var positions = List[Float64]()
    positions.append(1.0)
    positions.append(0.0)
    positions.append(0.0)
    var normals = List[Float64]()
    normals.append(1.0)
    normals.append(0.0)
    normals.append(0.0)
    var triangles = List[Int]()
    triangles.append(0)
    triangles.append(1)
    triangles.append(2)
    var placed = place_rigid(matrix, positions, normals, triangles)
    assert_true(placed.find('"triangles":[[2,1,0]]') >= 0)


def test_a_negative_origin_uses_the_lower_tile() raises:
    assert_equal(cell_text(3200.0, 0.0, 32.0), "1\t0")
    assert_equal(cell_text(-1.0, -3200.0, 32.0), "-1\t-1")
    assert_equal(cell_text(0.0, -3201.0, 32.0), "0\t-2")
    assert_equal(cell_text(0.0, 100.0, 32.0), "0\t0")
    with assert_raises(contains="tile is not positive"):
        _ = cell_text(0.0, 0.0, 0.0)


def test_the_command_prints_a_matrix() raises:
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_place",
            "matrix",
            "0",
            "0",
            "0",
            "1",
            "1",
            "1",
            "3200",
            "0",
            "0",
        ],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(
        result.output,
        matrix_text(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 3200.0, 0.0, 0.0) + "\n",
    )
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_place"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_place"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
