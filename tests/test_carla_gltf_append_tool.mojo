# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Packed glTF buffer views.

The bytes are what `struct.pack` writes, little-endian, after the zeros
that align the view to four bytes. A `VEC3` of floats also records min
and max.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_gltf_append import append_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test gltf append ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/append.json"
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_gltf_append")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_vec3_is_padded_and_records_its_bounds() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"length": 1, "viewIndex": 0, "accessorIndex": 0, "values": '
        + '[1.0, -2.0, 0.5], "form": "f", "component": 5126, "kind": "VEC3", '
        + '"target": 34962}',
    )
    assert_equal(
        append_text(path),
        '{"bytes": [0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 192, 0, 0, 0, 63], '
        + '"view": {"buffer": 0, "byteOffset": 4, "byteLength": 12, "target": '
        + '34962}, "accessor": {"bufferView": 0, "componentType": 5126, '
        + '"count": 1, "type": "VEC3", "min": [1.0, -2.0, 0.5], "max": '
        + '[1.0, -2.0, 0.5]}, "index": 0}',
    )
    _remove(root)


def test_integers_pack_little_endian_without_bounds() raises:
    var root = _dir()
    var indices = _file(
        root,
        '{"length": 4, "viewIndex": 2, "accessorIndex": 5, "values": [1, 2,'
        " 3], "
        + '"form": "I", "component": 5125, "kind": "SCALAR", "target": 34963}',
    )
    assert_equal(
        append_text(indices),
        '{"bytes": [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0], "view": {"buffer": 0, '
        + '"byteOffset": 4, "byteLength": 12, "target": 34963}, "accessor": '
        + '{"bufferView": 2, "componentType": 5125, "count": 3, "type": '
        + '"SCALAR"}, "index": 5}',
    )
    var shorts = _file(
        root,
        '{"length": 2, "viewIndex": 1, "accessorIndex": 1, "values": '
        + '[255, 256, 65535], "form": "H", "component": 5123, "kind":'
        ' "SCALAR", '
        + '"target": 34963}',
    )
    assert_equal(
        append_text(shorts),
        '{"bytes": [0, 0, 255, 0, 0, 1, 255, 255], "view": {"buffer": 0, '
        + '"byteOffset": 4, "byteLength": 6, "target": 34963}, "accessor": '
        + '{"bufferView": 1, "componentType": 5123, "count": 3, "type": '
        + '"SCALAR"}, "index": 1}',
    )
    var bad = _file(
        root,
        '{"length": 0, "viewIndex": 0, "accessorIndex": 0, "values": [256], '
        + '"form": "B", "component": 5121, "kind": "SCALAR", "target": 34963}',
    )
    with assert_raises(contains="value does not fit"):
        _ = append_text(bad)
    _remove(root)


def test_the_command_prints_the_view_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"length": 0, "viewIndex": 0, "accessorIndex": 3, "values": [7], '
        + '"form": "B", "component": 5121, "kind": "SCALAR", "target": 34963}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        '{"bytes": [7], "view": {"buffer": 0, "byteOffset": 0,'
        ' "byteLength": 1, '
        + '"target": 34963}, "accessor": {"bufferView": 0, "componentType": '
        + '5121, "count": 1, "type": "SCALAR"}, "index": 3}\n',
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_gltf_append FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_gltf_append:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_append"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
