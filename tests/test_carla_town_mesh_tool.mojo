# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town mesh reader matches NumPy's glTF arrays."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_mesh import mesh_text


comptime _GLTF = '{"buffers":[{"uri":"mesh.bin","byteLength":12}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":9},{"buffer":0,"byteOffset":9,"byteLength":3}],"accessors":[{"bufferView":0,"componentType":5121,"count":3,"type":"VEC3"},{"bufferView":1,"componentType":5121,"count":3,"type":"SCALAR"}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}]}'
"""A triangle of unsigned bytes, with no normals, coordinates or material."""


def _mesh(directory: String) raises -> String:
    """Write the sample mesh and return its glTF path."""
    var path = directory + "/mesh.gltf"
    Path(path).write_text(_GLTF)
    var blob = List[UInt8]()
    for value in range(1, 10):
        blob.append(UInt8(value))
    blob.append(0)
    blob.append(1)
    blob.append(2)
    Path(directory + "/mesh.bin").write_bytes(Span(blob))
    return path


def test_missing_attributes_follow_numpy() raises:
    var directory = mkdtemp(prefix="town mesh ")
    var text = mesh_text(_mesh(directory))
    assert_true(
        text.startswith(
            '[{"material":"","positions":[[1.0,2.0,3.0],[4.0,5.0,6.0],[7.0,8.0,9.0]]'
        )
    )
    assert_true(
        text.find('"normals":[[0.0,1.0,0.0],[0.0,1.0,0.0],[0.0,1.0,0.0]]') >= 0
    )
    assert_true(text.find('"uvs":[[0.0,0.0],[0.0,0.0],[0.0,0.0]]') >= 0)
    assert_true(text.find('"triangles":[[0,1,2]]') >= 0)
    Path(directory + "/mesh.bin").write_bytes(Span(List[UInt8]()))
    with assert_raises():
        _ = mesh_text(directory + "/mesh.gltf")
    _ = run_program(["rm", "-rf", directory], 10)


def test_the_command_prints_the_primitives() raises:
    var directory = mkdtemp(prefix="town mesh ")
    var path = _mesh(directory)
    var result = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_mesh", path],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(result.output, mesh_text(path) + "\n")
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_mesh"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_mesh"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
