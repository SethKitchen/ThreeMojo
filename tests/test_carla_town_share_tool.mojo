# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town's shared triangle cap and its grass.

One grass copy in ten stays. Each kind keeps the same share of its
cap, and never more than one. A far building keeps at least eight
triangles.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_share import share_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town share ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_share")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 15, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def test_one_grass_blade_in_ten_stays() raises:
    assert_equal(
        share_text('{"mode":"grass","start":0,"count":25}'),
        '{"indices":[0,10,20],"next":25}',
    )
    assert_equal(
        share_text('{"mode":"grass","start":8,"count":5}'),
        '{"indices":[2],"next":13}',
    )
    assert_equal(
        share_text('{"mode":"grass","start":3,"count":0}'),
        '{"indices":[],"next":3}',
    )
    with assert_raises(contains="grass count is negative"):
        _ = share_text('{"mode":"grass","start":-1,"count":1}')


def test_each_kind_shares_its_cap_and_a_building_keeps_eight() raises:
    var lines = _python(
        "import json\n"
        + "caps = {'vegetation': (1200000, 300000), 'building': (1500000,"
        " 300000),\n"
        + " 'fence': (250000, 50000), 'pole': (250000, 50000), 'prop': (300000,"
        " 1),\n"
        + " 'parked_vehicle': (200000, 1), 'traffic_light': (100000, 20000)}\n"
        + "def factor(kind, lod, count):\n"
        + "    if kind in caps and count:\n"
        + "        return min(1.0, caps[kind][lod] / count)\n"
        + "    return 1.0\n"
        + "items = [\n"
        + " ({'kind':'vegetation','lod':0,'count':10000000}, None),\n"
        + " ({'kind':'building','lod':1,'count':100}, None),\n"
        + " ({'kind':'road','lod':0,'count':50}, None),\n"
        + " ({'kind':'prop','lod':1,'count':0}, None),\n"
        + " ({'kind':'fence','lod':0,'count':1}, None),\n"
        + " ({'kind':'vegetation','lod':1,'count':7}, None),\n"
        + "]\n"
        + "rows = []\n"
        + "for item, _ in items:\n"
        + "    rows.append(factor(item['kind'], item['lod'], item['count']))\n"
        + "print(json.dumps([item for item, _ in items], separators=(',',"
        " ':')))\n"
        + "print(json.dumps(rows, separators=(',', ':')))\n"
        + "for limit, value in ((1000, 0.015), (3, 1.0), (8000, 0.0001), (8,"
        " 2.0)):\n"
        + "    print(json.dumps({'mode':'goal','limit':limit,'factor':value},"
        " separators=(',', ':')))\n"
        + "    print(max(8, int(limit * value)))\n"
    )
    var pending = String("")
    var stage = 0
    var request = String("")
    for line in lines.splitlines():
        var text = String(line)
        if text.byte_length() == 0:
            continue
        if stage == 0:
            request = '{"mode":"factors","items":' + text + "}"
            stage = 1
            continue
        if stage == 1:
            assert_equal(share_text(request), '{"factors":' + text + "}")
            stage = 2
            continue
        if pending.byte_length() == 0:
            pending = text
            continue
        assert_equal(share_text(pending), '{"goal":' + text + "}")
        pending = ""
    with assert_raises(contains="level is not 0 or 1"):
        _ = share_text(
            '{"mode":"factors","items":[{"kind":"building","lod":2,"count":1}]}'
        )
    with assert_raises(contains="triangle count is negative"):
        _ = share_text(
            '{"mode":"factors","items":[{"kind":"building","lod":0,"count":-1}]}'
        )


def test_the_command_prints_the_share_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/share.json"
    Path(path).write_text('{"mode":"grass","start":0,"count":10}')
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"indices":[0],"next":10}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_share FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_share:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_share"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
