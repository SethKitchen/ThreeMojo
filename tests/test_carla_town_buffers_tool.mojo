# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One town tile packed into a glTF buffer.

Three corners become little-endian float32 values. Lamp heads round to
three decimal places, half to even. A later kind sorts after an earlier one.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_buffers import buffer_text


def _request(bin_path: String) -> String:
    """Return one building triangle and three lamp numbers."""
    return (
        '{"bin":"'
        + bin_path
        + '","name":"town","lamps":[[0.0015,-1.0005,1.0005]],"groups":[{'
        '"lod":0,"kind":"building","cell":[0,0],"material":3,'
        '"positions":[[[0,0,0],[1,0,0],[0,1,0]]],'
        '"normals":[[[0,0,1],[0,0,1],[0,0,1]]],'
        '"uvs":[[[0,0],[1,0],[0,1]]],"triangles":[[[0,1,2]]]}]}'
    )


def _tables() -> String:
    """Return the glTF tables for `_request`."""
    return (
        '{"triangles":[1,0],"bufferViews":[{"buffer":0,"byteOffset":0,'
        '"byteLength":36,"target":34962},{"buffer":0,"byteOffset":36,'
        '"byteLength":36,"target":34962},{"buffer":0,"byteOffset":72,'
        '"byteLength":24,"target":34962},{"buffer":0,"byteOffset":96,'
        '"byteLength":12,"target":34963}],"accessors":[{"bufferView":0,'
        '"componentType":5126,"count":3,"type":"VEC3","min":[0.0,0.0,0.0],'
        '"max":[1.0,1.0,0.0]},{"bufferView":1,"componentType":5126,"count":3,'
        '"type":"VEC3","min":[0.0,0.0,1.0],"max":[0.0,0.0,1.0]},{"bufferView":2,'
        '"componentType":5126,"count":3,"type":"VEC2"},{"bufferView":3,'
        '"componentType":5125,"count":3,"type":"SCALAR"}],"meshes":'
        '[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},'
        '"indices":3,"material":3}]}],"nodes":[{"name":"building_0_0_lod0",'
        '"mesh":0,"extras":{"carla_kind":"building","carla_lod":0}}],'
        '"scenes":[{"nodes":[0],"extras":{"carla_lamps":[0.002,-1.0,1.0]}}],'
        '"buffers":[{"byteLength":108,"uri":"town.bin"}]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town buffers ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_buffers")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_one_triangle_packs_little_endian_floats() raises:
    var root = _dir()
    var bin_path = root + "/town.bin"
    assert_equal(buffer_text(_request(bin_path)), _tables())
    var data = Path(bin_path).read_bytes()
    assert_equal(len(data), 108)
    assert_equal(Int(data[12]), 0)
    assert_equal(Int(data[13]), 0)
    assert_equal(Int(data[14]), 128)
    assert_equal(Int(data[15]), 63)
    _remove(root)


def test_kinds_sort_and_an_empty_group_is_refused() raises:
    var root = _dir()
    var printed = buffer_text(
        '{"bin":"'
        + root
        + '/out.bin","name":"town","lamps":[],"groups":['
        '{"lod":0,"kind":"vegetation","cell":[0,0],"material":1,'
        '"positions":[[[0,0,0]]],"normals":[[[0,1,0]]],"uvs":[[[0,0]]],'
        '"triangles":[[[0,0,0]]]},'
        '{"lod":0,"kind":"building","cell":[0,0],"material":1,'
        '"positions":[[[1,0,0]]],"normals":[[[0,1,0]]],"uvs":[[[1,0]]],'
        '"triangles":[[[0,0,0]]]}]}'
    )
    var building = printed.find("building_0_0_lod0")
    var vegetation = printed.find("vegetation_0_0_lod0")
    assert_true(building >= 0 and vegetation > building)
    with assert_raises(contains="empty vector"):
        _ = buffer_text(
            '{"bin":"'
            + root
            + '/empty.bin","name":"town","lamps":[],"groups":[{"lod":0,'
            '"kind":"pole","cell":[0,0],"material":0,"positions":[],'
            '"normals":[],"uvs":[],"triangles":[]}]}'
        )
    _remove(root)


def test_the_command_prints_the_tables_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/buffers.json"
    var bin_path = root + "/town.bin"
    Path(path).write_text(_request(bin_path))
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, _tables() + "\n")
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_buffers FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_buffers:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_buffers"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
