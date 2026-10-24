# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town mesh keeps nothing, stays whole, or comes back lowered."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_lower import lower_text


comptime _STRIP = (
    '{"positions":[[0,0,0],[1,0,0],[2,0,0],[3,0,0],[4,0,0],[5,0,0],'
    "[0,1,0],[1,1,0],[2,1,0],[3,1,0],[4,1,0],[5,1,0]],"
    '"normals":[[0,0,1],[0,0,1],[0,0,1],[0,0,1],[0,0,1],[0,0,1],'
    "[0,0,1],[0,0,1],[0,0,1],[0,0,1],[0,0,1],[0,0,1]],"
    '"uvs":[[0,0],[1,0],[2,0],[3,0],[4,0],[5,0],[0,1],[1,1],[2,1],[3,1],[4,1],[5,1]],'
    '"triangles":[[0,1,6],[1,7,6],[1,2,7],[2,8,7],[2,3,8],[3,9,8],'
    "[3,4,9],[4,10,9],[4,5,10],[5,11,10]],"
    '"material":"Wall","kind":"prop","mesh":"/Game/Carla/Static/Prop/Strip",'
    '"index":0,"total":10,"masked":false,"lod":0,"factor":0.1,"keep":400}'
)
"""Ten triangles of a prop, asked to keep a tenth."""


def test_a_far_prop_is_dropped_and_a_road_stays() raises:
    assert_equal(
        lower_text(
            '{"positions":[[0,0,0]],"normals":[[0,1,0]],"uvs":[[0,0]],'
            '"triangles":[[0,1,2]],"material":"Plain","kind":"prop",'
            '"mesh":"/Game/Carla/Static/Prop/Box","index":0,"total":1,'
            '"masked":false,"lod":1,"factor":1.0,"keep":400}'
        ),
        '{"action":"none"}',
    )
    assert_equal(
        lower_text(
            '{"positions":[[0,0,0]],"normals":[[0,1,0]],"uvs":[[0,0]],'
            '"triangles":[[0,1,2]],"material":"Asphalt","kind":"road",'
            '"mesh":"/Game/Carla/Static/Road/Lane","index":0,"total":1,'
            '"masked":false,"lod":0,"factor":1.0,"keep":400}'
        ),
        '{"action":"whole"}',
    )
    var lowered = lower_text(_STRIP)
    assert_true(lowered.startswith('{"action":"mesh","positions":'))
    assert_true(lowered.find('"triangles":') >= 0)


def test_one_leaf_card_stays_whole() raises:
    assert_equal(
        lower_text(
            '{"positions":[[0,0,0],[1,0,0],[0,1,0]],"normals":[[0,0,1],[0,0,1],[0,0,1]],'
            '"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],"material":"Leaf",'
            '"kind":"vegetation","mesh":"/Game/Carla/Static/Vegetation/Grass/Blade",'
            '"index":2,"total":1,"masked":true,"lod":0,"factor":0.5,"keep":400}'
        ),
        '{"action":"whole"}',
    )


def test_the_command_prints_the_level() raises:
    var path = String("/tmp/carla-town-lower.json")
    Path(path).write_text(
        '{"positions":[[0,0,0]],"normals":[[0,1,0]],"uvs":[[0,0]],'
        '"triangles":[[0,1,2]],"material":"Plain","kind":"prop",'
        '"mesh":"/Game/Carla/Static/Prop/Box","index":0,"total":1,'
        '"masked":false,"lod":1,"factor":1,"keep":400}'
    )
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_lower", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, '{"action":"none"}\n')
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_lower"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_lower FILE\n")
    with assert_raises(contains="lower request is not an object"):
        _ = lower_text("[]")
    with assert_raises(contains="count is negative"):
        _ = lower_text(
            '{"positions":[],"normals":[],"uvs":[],"triangles":[],'
            '"material":"Plain","kind":"prop","mesh":"/Game/Box",'
            '"index":0,"total":-1,"masked":false,"lod":0,"factor":1,"keep":400}'
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_lower"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
