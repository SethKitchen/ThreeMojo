# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Values read from a glTF accessor.

The lists are what `struct.unpack_from` returns for the same bytes. A
float32 widens to float64. An unsigned integer stays an integer.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_gltf_read import read_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test gltf read ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/read.json"
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_gltf_read")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_float_vector_skips_the_offset() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"bytes": [17, 34, 0, 0, 128, 63, 0, 0, 0, 192, 0, 0, 0, 63], '
        + '"bufferViews": [{"buffer": 0, "byteOffset": 2}], "accessors": '
        + '[{"bufferView": 0, "componentType": 5126, "count": 1, "type": '
        + '"VEC3"}], "accessor": 0}',
    )
    assert_equal(read_text(path), '{"values": [1.0, -2.0, 0.5], "width": 3}')
    var negative = _file(
        root,
        '{"bytes": [0, 0, 0, 128], "bufferViews": [{"buffer": 0}], '
        + '"accessors": [{"bufferView": 0, "componentType": 5126, "count": 1, '
        + '"type": "SCALAR"}], "accessor": -1}',
    )
    assert_equal(read_text(negative), '{"values": [-0.0], "width": 1}')
    _remove(root)


def test_unsigned_integers_and_a_short_buffer() raises:
    var root = _dir()
    var shorts = _file(
        root,
        '{"bytes": [0, 0, 255, 0, 0, 1, 255, 255], "bufferViews": '
        + '[{"buffer": 0}], "accessors": [{"bufferView": 0, "byteOffset": 2, '
        + '"componentType": 5123, "count": 3, "type": "SCALAR"}],'
        ' "accessor": 0}',
    )
    assert_equal(read_text(shorts), '{"values": [255, 256, 65535], "width": 1}')
    var bytes = _file(
        root,
        '{"bytes": [7, 8, 9], "bufferViews": [{"buffer": 0}], "accessors": '
        + '[{"bufferView": 0, "componentType": 5121, "count": 3, "type": '
        + '"SCALAR"}], "accessor": 0}',
    )
    assert_equal(read_text(bytes), '{"values": [7, 8, 9], "width": 1}')
    var short = _file(
        root,
        '{"bytes": [1], "bufferViews": [{"buffer": 0}], "accessors": '
        + '[{"bufferView": 0, "componentType": 5126, "count": 1, "type": '
        + '"SCALAR"}], "accessor": 0}',
    )
    with assert_raises(contains="buffer is short"):
        _ = read_text(short)
    _remove(root)


def test_the_command_prints_the_values_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"bytes": [7, 8, 9], "bufferViews": [{"buffer": 0}], "accessors": '
        + '[{"bufferView": 0, "componentType": 5121, "count": 3, "type": '
        + '"SCALAR"}], "accessor": 0}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"values": [7, 8, 9], "width": 1}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_gltf_read FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_gltf_read:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_read"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
