# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town mesh matches the previous bordered and welded simplification."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.carla_town_simplify import town_simplify_text


def _mesh(
    root: String, mode: String, size: String, target: String, keep: String
) raises -> String:
    """Write one grid and return the simplified JSON."""
    var script = String(
        "import json, sys\n"
        + "mode, size, target, keep, root = sys.argv[1:]\n"
        + "n = int(size)\n"
        + "positions, uvs, triangles = [], [], []\n"
        + "for z in range(n + 1):\n"
        + "    for x in range(n + 1):\n"
        + "        y = 1.0 if 0 < x < n and 0 < z < n else 0.0\n"
        + "        positions.append([float(x), y, float(z)])\n"
        + "        uvs.append([x / n, z / n])\n"
        + "for z in range(n):\n"
        + "    for x in range(n):\n"
        + "        a = z * (n + 1) + x\n"
        + "        b = a + 1\n"
        + "        c = a + (n + 1)\n"
        + "        d = c + 1\n"
        + "        triangles.append([a, c, b])\n"
        + "        triangles.append([b, c, d])\n"
        + "doc = {'mode': mode, 'positions': positions, 'uvs': uvs,\n"
        + "       'triangles': triangles, 'material': 'body', 'target':"
        " int(target),\n"
        + "       'keep': int(keep), 'small': False}\n"
        + "json.dump(doc, open(root + '/mesh.json', 'w'))\n"
    )
    var result = run_program(
        ["python3", "-c", script, mode, size, target, keep, root],
        30,
        merge_errors=False,
    )
    if result.status != 0:
        raise Error(result.errors)
    return town_simplify_text(Path(root + "/mesh.json").read_text())


def test_bordered_and_welded_meshes_match_the_previous_results() raises:
    var root = mkdtemp(prefix="test town simplify ")
    assert_equal(
        sha256_hex(_mesh(root, "border", "4", "4", "4").as_bytes()),
        "522eac6d5044bc4525cdb0b0650b574f961673cef116d9366af3e17f44be7ec1",
    )
    assert_equal(
        sha256_hex(_mesh(root, "weld", "4", "4", "4").as_bytes()),
        "b70a96332bf9238daa699ef9b72a32ba03c0eb62686a7128dbe635820f203b3c",
    )
    assert_equal(_mesh(root, "border", "1", "1", "400"), '{"same":true}')
    assert_equal(_mesh(root, "weld", "1", "4", "400"), '{"same":true}')
    with assert_raises(contains="mode is not border or weld"):
        _ = town_simplify_text('{"mode":"near"}')
    with assert_raises(contains="simplify request is not an object"):
        _ = town_simplify_text("[]")
    _ = run_program(["rm", "-rf", root], 10)


def test_the_command_prints_the_mesh_and_refuses_bad_use() raises:
    var root = mkdtemp(prefix="test town simplify cli ")
    var text = _mesh(root, "border", "1", "1", "400")
    var ran = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_simplify",
            root + "/mesh.json",
        ],
        30,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_equal(ran.errors, "")
    assert_equal(ran.output, text + "\n")
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_simplify"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_simplify FILE\n")
    var failed = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_simplify",
            root + "/missing.json",
        ],
        30,
        merge_errors=False,
    )
    assert_true(failed.status != 0)
    assert_true(failed.errors.startswith("carla_town_simplify:"))
    _ = run_program(["rm", "-rf", root], 10)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_simplify"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
