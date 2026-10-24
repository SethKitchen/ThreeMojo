# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One orthographic town view.

A lit triangle keeps the nearest red samples. A masked texel below the
cut stays empty. Two parts share one NumPy random stream.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_splat import splat_text


def _triangle() -> String:
    """Return one triangle and a normalized impostor light."""
    return (
        '"positions":[[0,0,0],[1,0,0],[0,1,1]],"normals":[[0,0,1],[0,0,1],'
        '[0,0,1]],"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
        '"factor":[1,0,0,1],"cut":0.5,"masked":false'
    )


def _axis() -> String:
    """Return a two-by-two view of one lit triangle."""
    return (
        '{"mode":"axis","columns":2,"rows":2,"samples":1,"cap":4,"seed":7,'
        '"across":0,"left":0,"top":1,"scale_u":2,"scale_v":2,"light":'
        "[0.3491282676376715,0.847882935691488,0.3990037344430532],"
        '"parts":[{'
        + _triangle()
        + "}]}"
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town splat ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_splat")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_lit_triangle_keeps_the_near_red_samples() raises:
    assert_equal(
        splat_text(_axis()),
        (
            "[[[0.6694520539436792, 0.0, 0.0, 1.0], [0.0, 0.0, 0.0, 0.0]], "
            "[[0.6694520539436792, 0.0, 0.0, 1.0], [0.0, 0.0, 0.0, 0.0]]]"
        ),
    )
    var absent = String(_axis())
    absent = absent.replace("}]}", ',"image":null}]}')
    assert_equal(splat_text(absent), splat_text(_axis()))


def test_a_mask_drops_a_sample_and_two_parts_share_one_stream() raises:
    assert_equal(
        splat_text(
            '{"mode":"axis","columns":2,"rows":2,"samples":1,"cap":4,"seed":7,'
            '"across":2,"left":0,"top":1,"scale_u":2,"scale_v":2,"light":'
            "[0.3491282676376715,0.847882935691488,0.3990037344430532],"
            '"parts":[{'
            + _triangle().replace(
                '"masked":false',
                '"masked":true,"image":{"width":1,"height":1,"rgba":[1,0,0,0.2]}',
            )
            + "}]}"
        ),
        (
            "[[[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]], [[0.0, 0.0, 0.0,"
            " 0.0], [0.0, 0.0, 0.0, 0.0]]]"
        ),
    )
    assert_equal(
        splat_text(
            '{"mode":"ortho","columns":2,"rows":2,"samples":1,"cap":4,"seed":11,'
            '"right":[0,0,-1],"up":[0,1,0],"forward":[1,0,0],"low_r":-1,'
            '"low_u":0,"height":1,"scale_u":2,"scale_v":2,"parts":[{'
            + _triangle()
            + '},{"positions":[[0,0,2],[1,0,2],[0,1,2]],"normals":[[0,1,0],'
            "[0,1,0],[0,1,0]],"
            '"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],"factor":[0,0,1,1],'
            '"cut":0.5,"masked":false}]}'
        ),
        (
            "[[[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]], [[0.0, 0.0, 0.0,"
            " 0.0], [1.0, 0.0, 0.0, 1.0]]]"
        ),
    )
    with assert_raises(contains="mode is not axis or ortho"):
        _ = splat_text(
            '{"mode":"side","columns":1,"rows":1,"samples":1,"cap":1,"seed":1,'
            '"parts":[]}'
        )
    with assert_raises(contains="index out of range"):
        _ = splat_text(
            '{"mode":"axis","columns":1,"rows":1,"samples":1,"cap":1,"seed":1,'
            '"across":0,"left":0,"top":1,"scale_u":1,"scale_v":1,"parts":[{'
            + _triangle().replace("[0,1,2]", "[0,1,9]")
            + "}]}"
        )


def test_the_command_prints_the_view_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/view.json"
    Path(path).write_text(_axis())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        (
            "[[[0.6694520539436792, 0.0, 0.0, 1.0], [0.0, 0.0, 0.0, 0.0]], "
            "[[0.6694520539436792, 0.0, 0.0, 1.0], [0.0, 0.0, 0.0, 0.0]]]\n"
        ),
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_splat FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_splat:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_splat"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
