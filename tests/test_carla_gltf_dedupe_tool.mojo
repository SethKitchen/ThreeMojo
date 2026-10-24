# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One glTF material of each name.

The text is what `json.dumps` writes after keeping the first material of
each name and pointing the primitives at that copy.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_gltf_dedupe import dedupe_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test gltf dedupe ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/mesh.gltf"
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_gltf_dedupe")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_the_first_material_of_each_name_stays() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"asset": {"version": "2.0"}, "materials": [{"name": "Glass", '
        + '"pbrMetallicRoughness": {"roughnessFactor": 0.1}}, {"name": "Body", '
        + '"extras": {"carla": "paint"}}, {"name": "Glass", '
        + '"pbrMetallicRoughness": {"roughnessFactor": 0.9}}], "meshes": '
        + '[{"primitives": [{"material": 2, "mode": 4}, {"mode": 4}, '
        + '{"material": 0}, {"material": 1}]}]}',
    )
    assert_equal(
        dedupe_text(path),
        '{"asset": {"version": "2.0"}, "materials": [{"name": "Glass", '
        + '"pbrMetallicRoughness": {"roughnessFactor": 0.1}}, {"name": "Body", '
        + '"extras": {"carla": "paint"}}], "meshes": [{"primitives": '
        + '[{"material": 0, "mode": 4}, {"mode": 4}, {"material": 0}, '
        + '{"material": 1}]}]}',
    )
    _remove(root)


def test_a_missing_name_matches_only_another_missing_name() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"materials": [{}, {"name": ""}, {"name": "A"}], "meshes": '
        + '[{"primitives": [{"material": 1}, {"material": 2}]}]}',
    )
    assert_equal(
        dedupe_text(path),
        '{"materials": [{}, {"name": "A"}], "meshes": [{"primitives": '
        + '[{"material": 0}, {"material": 1}]}]}',
    )
    var absent = _file(root, '{"meshes": [{"primitives": [{}]}]}')
    assert_equal(dedupe_text(absent), '{"meshes": [{"primitives": [{}]}]}')
    var empty = _file(root, '{"materials": [], "meshes": [{"primitives": []}]}')
    assert_equal(
        dedupe_text(empty),
        '{"materials": [], "meshes": [{"primitives": []}]}',
    )
    _remove(root)


def test_a_bad_index_is_refused() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"materials": [{"name": "A"}], "meshes": [{"primitives": '
        + '[{"material": 3}]}]}',
    )
    with assert_raises(contains="material index out of range"):
        _ = dedupe_text(path)
    _remove(root)


def test_the_command_prints_the_document_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"materials": [{"name": "A"}, {"name": "A"}], "meshes": '
        + '[{"primitives": [{"material": 1}]}]}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        '{"materials": [{"name": "A"}], "meshes": [{"primitives": '
        + '[{"material": 0}]}]}\n',
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_gltf_dedupe FILE\n")
    var failed = _cli(root + "/missing.gltf")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_gltf_dedupe:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_dedupe"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
