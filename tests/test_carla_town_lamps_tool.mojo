# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Street lamp heads from a mesh, in the mesh frame.

Glass keeps one head for each connected piece. A lamp with no glass
keeps a head at the top of its bounds. Any other mesh has none.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_lamps import heads_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town lamps ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _file(root: String, name: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/" + name
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_lamps")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_mesh_that_is_not_a_lamp_has_no_head() raises:
    var text = (
        '{"mesh":"/Game/Carla/Static/Building/Fixture","primitives":'
        '[{"positions":[[0,0,0],[1,0,0],[0,1,0]],"triangles":[[0,1,2]]}]}'
    )
    assert_equal(heads_text(text), "null")
    assert_equal(
        heads_text('{"mesh":"/Game/Other","primitives":[]}'),
        "null",
    )


def test_a_lamp_without_glass_uses_its_top() raises:
    var text = (
        '{"mesh":"/Game/Carla/Static/Pole/SM_Lights/SM_StreetLightWall",'
        '"primitives":[{"positions":[[0,0,0],[2,4,6]],"triangles":[[0,0,1]]}]}'
    )
    assert_equal(heads_text(text), "[[1.0, 3.85, 3.0]]")
    var post = (
        '{"mesh":"/Chainbarrier/SM_LightPost","primitives":'
        '[{"positions":[[-2,1,0],[2,1,4]],"triangles":[]}]}'
    )
    assert_equal(heads_text(post), "[[0.0, 0.85, 2.0]]")


def test_glass_pieces_stay_apart() raises:
    var text = (
        '{"mesh":"Lamp_glass_ext","primitives":[{"positions":'
        "[[0,0,0],[1,0,0],[0,1,0],[10,10,10],[11,10,10],[10,11,10]],"
        '"triangles":[[0,1,2],[3,4,5]]}]}'
    )
    assert_equal(
        heads_text(text),
        "[[0.5, 0.5, 0.0], [10.5, 10.5, 10.0]]",
    )
    var split = (
        '{"mesh":"Lamp_glass_ext","primitives":['
        '{"positions":[[0,0,0],[1,0,0],[0,1,0]],"triangles":[[0,1,2]]},'
        '{"positions":[[10,10,10],[11,10,10],[10,11,10]],'
        '"triangles":[[0,1,2]]}]}'
    )
    assert_equal(heads_text(split), heads_text(text))
    var wrapped = (
        '{"mesh":"a_glass_ext","primitives":[{"positions":'
        "[[0,0,0],[1,0,0],[0,1,0],[5,5,5]],"
        '"triangles":[[0,1,2],[-1,-2,-3]]}]}'
    )
    assert_equal(heads_text(wrapped), "[[2.5, 2.5, 2.5]]")


def test_corners_that_share_a_millimeter_are_one_piece() raises:
    var text = (
        '{"mesh":"Lamp_glass_ext","primitives":[{"positions":'
        "[[0,0,0],[1,0,0],[0,1,0],[0.000001,0,0],[3,0,0],[3,1,0]],"
        '"triangles":[[0,1,2],[3,4,5]]}]}'
    )
    assert_equal(heads_text(text), "[[1.5, 0.5, 0.0]]")
    with assert_raises():
        _ = heads_text('{"mesh":"a_glass_ext","primitives":[]}')
    with assert_raises():
        _ = heads_text(
            '{"mesh":"a_glass_ext","primitives":[{"positions":[[0,0,0]],'
            '"triangles":[[4,0,0]]}]}'
        )


def test_every_copy_is_placed_from_its_matrix() raises:
    assert_equal(
        heads_text(
            '{"heads":[[1.0,2.0,3.0]],"matrices":['
            + "[[1,0,0,0],[0,1,0,0],[0,0,1,0],[3200,0,0,1]],"
            + "[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,100,0,1]]]}"
        ),
        "[[33.0,2.0,3.0],[1.0,2.0,4.0]]",
    )
    assert_equal(heads_text('{"heads":[[1,2,3]],"matrices":[]}'), "[]")
    with assert_raises(contains="matrices are not a list"):
        _ = heads_text('{"heads":[[1,2,3]],"matrices":{}}')


def test_a_head_is_placed_by_the_copy_matrix() raises:
    var lines = run_program(
        [
            "python3",
            "-c",
            "import json, numpy\n"
            + "rng = numpy.random.default_rng(761)\n"
            + "for _ in range(30):\n"
            + "    heads = rng.normal(size=(int(rng.integers(1, 5)), 3))\n"
            + "    linear = rng.normal(size=(3, 3))\n"
            + "    move = rng.normal(size=3)\n"
            + "    got = (heads @ linear.T + move).tolist()\n"
            + "    print(json.dumps({'heads': heads.tolist(), 'linear':"
            " linear.tolist(), 'move': move.tolist()}, separators=(',',"
            " ':')))\n"
            + "    print(json.dumps(got, separators=(',', ':')))\n"
            + "print(json.dumps({'heads': [], 'linear':"
            " [[1,0,0],[0,1,0],[0,0,1]], 'move': [0,0,0]}, separators=(',',"
            " ':')))\n"
            + "print('[]')\n",
        ],
        15,
        merge_errors=False,
    )
    if lines.status != 0:
        raise Error(lines.errors)
    var pending = String("")
    var count = 0
    for line in lines.output.splitlines():
        var text = String(line)
        if text.byte_length() == 0:
            continue
        if pending.byte_length() == 0:
            pending = text
            continue
        assert_equal(heads_text(pending), text)
        pending = ""
        count += 1
    assert_equal(count, 31)
    with assert_raises(contains="matrix is not 3 by 3"):
        _ = heads_text('{"heads":[[0,0,0]],"linear":[[1,0,0]],"move":[0,0,0]}')


def test_the_command_line() raises:
    var root = _dir()
    var path = _file(
        root,
        "lamp.json",
        '{"mesh":"/Game/Other","primitives":[]}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, "null\n")
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_lamps FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_lamps:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_lamps"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
