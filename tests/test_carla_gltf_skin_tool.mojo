# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Skin, joints, weights and vertex colors leave a glTF document.

The text is what `json.dumps` writes after those members are removed. Bone
nodes and other attributes stay.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_gltf_skin import strip_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test gltf skin ")


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
    command.append("carla_gltf_skin")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_skin_joints_weights_and_colors_go() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"nodes": [{"name": "Wheel", "skin": 0}, {"name": "Body"}], '
        + '"skins": [{"joints": [0]}], "meshes": [{"primitives": '
        + '[{"attributes": {"POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2, '
        + '"COLOR_0": 3, "color_0": 4}}]}]}',
    )
    assert_equal(
        strip_text(path),
        '{"nodes": [{"name": "Wheel"}, {"name": "Body"}], "meshes": '
        + '[{"primitives": [{"attributes": {"POSITION": 0, "color_0": 4}}]}]}',
    )
    _remove(root)


def test_a_plain_mesh_stays_and_a_missing_node_list_fails() raises:
    var root = _dir()
    var plain = _file(
        root,
        '{"nodes": [{"name": "Body"}], "meshes": [{"primitives": '
        + '[{"attributes": {"POSITION": 1, "NORMAL": 2}}]}]}',
    )
    assert_equal(
        strip_text(plain),
        '{"nodes": [{"name": "Body"}], "meshes": [{"primitives": '
        + '[{"attributes": {"POSITION": 1, "NORMAL": 2}}]}]}',
    )
    var missing = _file(root, '{"meshes": []}')
    with assert_raises(contains="KeyError"):
        _ = strip_text(missing)
    _remove(root)


def test_the_command_prints_the_document_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"nodes": [{"name": "Body", "skin": 0}], "skins": [], "meshes": '
        + '[{"primitives": [{"attributes": {"WEIGHTS_1": 1}}]}]}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        '{"nodes": [{"name": "Body"}], "meshes": [{"primitives": '
        + '[{"attributes": {}}]}]}\n',
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_gltf_skin FILE\n")
    var failed = _cli(root + "/missing.gltf")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_gltf_skin:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_skin"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
