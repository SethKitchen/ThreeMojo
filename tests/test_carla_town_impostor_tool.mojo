# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A tree impostor's quads and its empty texels.

A box two meters wide and one meter tall has 128 rows across x and 64
across z. An empty texel takes the mean of the covered colors.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_impostor import impostor_text


def _frame() -> String:
    """Return a box from the origin to (2, 1, 4)."""
    return '{"mode":"frame","positions":[[0,0,0],[2,1,4]],"size":256}'


def _built() -> String:
    """Return the views and quads for `_frame`."""
    return (
        '{"low":[0.0,0.0,0.0],"high":[2.0,1.0,4.0],"views":[{"across":0,'
        '"left":0.0,"top":1.0,"width":2.0,"height":1.0,"rows":128},'
        '{"across":2,"left":0.0,"top":1.0,"width":4.0,"height":1.0,"rows":64}],'
        '"positions":[[0.0,0.0,2.0],[2.0,0.0,2.0],[2.0,1.0,2.0],[0.0,1.0,2.0],'
        '[1.0,0.0,0.0],[1.0,0.0,4.0],[1.0,1.0,4.0],[1.0,1.0,0.0]],"normals":'
        "[[0.0,1.0,0.0],[0.0,1.0,0.0],[0.0,1.0,0.0],[0.0,1.0,0.0],"
        '[0.0,1.0,0.0],[0.0,1.0,0.0],[0.0,1.0,0.0],[0.0,1.0,0.0]],"uvs":'
        "[[0.0,1.0],[0.5,1.0],[0.5,0.0],[0.0,0.0],[0.5,1.0],[1.0,1.0],"
        '[1.0,0.0],[0.5,0.0]],"triangles":[[0,1,2],[0,2,3],[4,5,6],[4,6,7]]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town impostor ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_impostor")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_box_sets_the_views_and_the_crossing_quads() raises:
    assert_equal(impostor_text(_frame()), _built())
    assert_equal(
        impostor_text(
            '{"mode":"fill","image":[[[0.2,0.4,0.6,1],[0,0,0,0]],'
            "[[0,0,0,0],[0.5,0.5,0,1]]]}"
        ),
        (
            "[[[0.2,0.4,0.6,1.0],[0.35,0.45,0.3,0.0]],[[0.35,0.45,0.3,0.0],"
            "[0.5,0.5,0.0,1.0]]]"
        ),
    )
    with assert_raises(contains="mode is not frame, fill or light"):
        _ = impostor_text('{"mode":"side"}')
    var light = run_program(
        [
            "python3",
            "-c",
            (
                "import json, numpy; v = numpy.array([0.35, 0.85, 0.4]);"
                " print(json.dumps((v / numpy.linalg.norm(v)).tolist(),"
                " separators=(',', ':')), end='')"
            ),
        ],
        10,
        merge_errors=False,
    )
    if light.status != 0:
        raise Error(light.errors)
    assert_equal(impostor_text('{"mode":"light"}'), light.output)


def test_the_command_prints_the_quads_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/impostor.json"
    Path(path).write_text(_frame())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, _built() + "\n")
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_impostor FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_impostor:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "--build",
            "carla_town_impostor",
        ],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
