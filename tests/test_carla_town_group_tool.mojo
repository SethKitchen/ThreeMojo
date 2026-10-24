# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Town copies land in the tile of their origin and merge there."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_group import group_text
from tools.carla_town_place import matrix_rows, matrix_text, place_rigid
from tools.carla_town_spline import spline_text


def test_copies_merge_when_they_share_a_tile() raises:
    var first = matrix_text(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 3200.0, 0.0, 0.0)
    var second = matrix_text(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 100.0, 0.0, 0.0)
    var third = matrix_text(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 3200.0, 50.0, 0.0)
    var request = (
        '{"tile":32.0,"parts":[{"lod":0,"kind":"prop","material":4,'
        '"positions":[[-0.5,-0.5,-0.5]],"normals":[[0.0,1.0,0.0]],'
        '"uvs":[[0.25,0.5]],"triangles":[[0,1,2]],"copies":[{"matrix":'
        + first
        + '},{"matrix":'
        + second
        + '},{"matrix":'
        + third
        + "}]}]}"
    )
    var grouped = group_text(request)
    var placed = _rigid(3200.0, 0.0, 0.0)
    assert_true(grouped.find(_array_of(placed, "points")) >= 0)
    assert_true(grouped.find("[31.5,-0.5,-0.5]") >= 0)
    assert_true(grouped.find('"cell":[1,0]') >= 0)
    assert_true(grouped.find('"cell":[0,0]') >= 0)
    assert_true(grouped.find('"uvs":[[[0.25,0.5]],[[0.25,0.5]]]') >= 0)
    assert_equal(grouped.count('"cell":'), 2)
    var apart = group_text(
        '{"tile":32,"parts":['
        '{"lod":0,"kind":"prop","material":4,"positions":[[0,0,0]],'
        '"normals":[[0,1,0]],"uvs":[[0,0]],"triangles":[[0,1,2]],'
        '"copies":[{"matrix":'
        + first
        + "}]},"
        '{"lod":0,"kind":"prop","material":5,"positions":[[0,0,0]],'
        '"normals":[[0,1,0]],"uvs":[[1,1]],"triangles":[[0,1,2]],'
        '"copies":[{"matrix":'
        + first
        + "}]}]}"
    )
    assert_equal(apart.count('"material":'), 2)
    assert_equal(group_text('{"tile":32,"parts":[]}'), '{"groups":[]}')


def test_a_spline_copy_uses_the_bent_mesh() raises:
    var request = (
        '{"tile":32,"parts":[{"lod":1,"kind":"road","material":2,'
        '"positions":[[0,0,0],[0.5,0.1,-0.2],[1,0,0]],'
        '"normals":[[0,1,0],[0,0,1],[1,0,0]],'
        '"uvs":[[0,0],[1,0],[1,1]],"triangles":[[0,1,2]],"copies":[{'
        '"matrix":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],'
        '"spline":{"forward_axis":0,"start":[0,0,0],"end":[100,0,0],'
        '"start_tangent":[100,0,0],"end_tangent":[100,0,0],'
        '"start_roll":0,"end_roll":0,"start_scale":[1,1],"end_scale":[1,1]}}]}]}'
    )
    var direct = spline_text(
        '{"matrix":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],'
        '"positions":[[0.0,0.0,0.0],[50.0,-20.0,10.0],[100.0,0.0,0.0]],'
        '"normals":[[0.0,0.0,1.0],[0.0,1.0,0.0],[1.0,0.0,0.0]],'
        '"triangles":[[0,1,2]]}'
    )
    var grouped = group_text(request)
    assert_true(grouped.find(_array_of(direct, "points")) >= 0)
    assert_true(grouped.find(_array_of(direct, "normals")) >= 0)
    assert_true(grouped.find(_array_of(direct, "triangles")) >= 0)
    assert_true(grouped.find('"cell":[0,0]') >= 0)
    assert_true(grouped.find('"uvs":[[[0,0],[1,0],[1,1]]]') >= 0)
    with assert_raises(contains="singular matrix"):
        _ = group_text(
            '{"tile":1,"parts":[{"lod":0,"kind":"road","material":0,'
            '"positions":[[0,0,0]],"normals":[[0,1,0]],"uvs":[[0,0]],'
            '"triangles":[[0,0,0]],"copies":[{"matrix":[[0,0,0,0],[0,0,0,0],'
            '[0,0,0,0],[0,0,0,1]],"spline":{"forward_axis":0,"start":[0,0,0],'
            '"end":[100,0,0],"start_tangent":[100,0,0],"end_tangent":[100,0,0],'
            '"start_roll":0,"end_roll":0,"start_scale":[1,1],"end_scale":[1,1]'
            "}}]}]}"
        )


def test_the_command_prints_the_groups() raises:
    var path = String("/tmp/carla-town-group.json")
    Path(path).write_text('{"tile":32,"parts":[]}')
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_group", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, '{"groups":[]}\n')
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_group"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_group FILE\n")
    with assert_raises(contains="group request is not an object"):
        _ = group_text("[]")
    with assert_raises(contains="parts are not a list"):
        _ = group_text('{"tile":32,"parts":{}}')
    with assert_raises(contains="tile is not positive"):
        _ = group_text('{"tile":0,"parts":[]}')
    with assert_raises(contains="the placement matrix cannot be inverted"):
        _ = group_text(
            '{"tile":32,"parts":[{"lod":0,"kind":"prop","material":1,'
            '"positions":[[0,0,0]],"normals":[[0,1,0]],"uvs":[[0,0]],'
            '"triangles":[[0,1,2]],"copies":[{"matrix":[[0,0,0,0],[0,0,0,0],'
            "[0,0,0,0],[0,0,0,1]]}]}]}"
        )


def _rigid(x: Float64, y: Float64, z: Float64) raises -> String:
    """Return one placed point at a translation in centimeters."""
    var matrix = matrix_rows(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, x, y, z)
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
    return place_rigid(matrix, positions, normals, triangles)


def _array_of(text: String, key: String) raises -> String:
    """Return the JSON array stored at `key`."""
    var marker = String('"') + key + '":'
    var start = text.find(marker)
    var raw = text.as_bytes()
    var at = start + len(marker.as_bytes())
    while at < len(raw) and raw[at] == 32:
        at += 1
    var depth = 0
    var end = at
    for index in range(at, len(raw)):
        var byte = raw[index]
        if byte == 91:
            depth += 1
        elif byte == 93:
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    return String(text[byte=at:end])


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_group"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
