# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Town material slots match the reviewed name and position rules."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_slots import choose_text


def test_a_dynamic_slot_keeps_the_mesh_name() raises:
    assert_equal(
        choose_text(
            '{"materials":[null,"MaterialInstanceDynamic'
            ' /Game/Fixture/Runtime.Runtime"],"own":["Own0","Own1"]}'
        ),
        '["Own0","Own1"]',
    )
    assert_equal(
        choose_text('{"materials":[],"own":["Own0","Own1"]}'),
        '["Own0","Own1"]',
    )


def test_a_static_slot_uses_its_object_name() raises:
    assert_equal(
        choose_text(
            '{"materials":["Material /Game/Fixture/Red.Red","Material'
            ' /Game/Fixture/Green.Green"],"own":["Own0","Own1"]}'
        ),
        '["Red","Green"]',
    )
    assert_equal(
        choose_text(
            '{"materials":["Material /Game/Fixture/Own0.Own0","Material'
            ' /Game/Fixture/Green.Green"],"own":["Own0","Own1"]}'
        ),
        '["Own0","Green"]',
    )
    with assert_raises():
        _ = choose_text('{"materials":["NoDot"],"own":["Own0"]}')


def test_the_command_prints_the_chosen_names() raises:
    var directory = mkdtemp(prefix="town slots ")
    var path = directory + "/slots.json"
    var request = (
        '{"materials":["Material /Game/Fixture/Red.Red"],"own":["Own0"]}'
    )
    Path(path).write_text(request)
    var result = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_slots", path],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(result.output, '["Red"]\n')
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_slots"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_slots"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
