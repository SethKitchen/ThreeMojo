# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""An environment record rounds each position to four decimal places."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_environment_record import record_text


def test_positions_round_half_to_even() raises:
    assert_equal(
        record_text(
            '{"objects":[{"id":7,"name":"A \\"b\\"","label":"caf\\u00e9",'
            + '"location":[1.23456789,-5e-05,-1e-08],'
            + '"rotation":[0.0,-0.0,180.00004],'
            + '"box_center":[0.00015,9.99995,-1.23456789],'
            + '"box_extent":[1e-08,2.675,1e+20],'
            + '"box_rotation":[-0.00025,123456.78901,5e-05]}]}'
        ),
        '{"objects":[{"id":7,"name":"A \\"b\\"","label":"caf\\u00e9",'
        + '"location":[1.2346,-0.0001,-0.0],'
        + '"rotation":[0.0,-0.0,180.0],'
        + '"box_center":[0.0001,10.0,-1.2346],'
        + '"box_extent":[0.0,2.675,1e+20],'
        + '"box_rotation":[-0.0003,123456.789,0.0001]}]}',
    )


def test_a_batch_keeps_non_finite_values() raises:
    assert_equal(record_text('{"objects":[]}'), '{"objects":[]}')
    assert_equal(
        record_text(
            '{"objects":[{"id":1,"name":"a","label":"b",'
            + '"location":[Infinity,-Infinity,NaN],'
            + '"rotation":[1,2,3],"box_center":[0,0,0],'
            + '"box_extent":[0,0,0],"box_rotation":[0,0,0]},'
            + '{"id":-4,"name":"c","label":"d",'
            + '"location":[0,0,0],"rotation":[0,0,0],'
            + '"box_center":[0,0,0],"box_extent":[0,0,0],'
            + '"box_rotation":[0,0,0]}]}'
        ),
        '{"objects":[{"id":1,"name":"a","label":"b",'
        + '"location":[Infinity,-Infinity,NaN],'
        + '"rotation":[1.0,2.0,3.0],"box_center":[0.0,0.0,0.0],'
        + '"box_extent":[0.0,0.0,0.0],"box_rotation":[0.0,0.0,0.0]},'
        + '{"id":-4,"name":"c","label":"d",'
        + '"location":[0.0,0.0,0.0],"rotation":[0.0,0.0,0.0],'
        + '"box_center":[0.0,0.0,0.0],"box_extent":[0.0,0.0,0.0],'
        + '"box_rotation":[0.0,0.0,0.0]}]}',
    )


def test_the_command_prints_the_records() raises:
    var path = String("/tmp/carla-environment-record.json")
    Path(path).write_text('{"objects":[]}')
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_environment_record", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, '{"objects":[]}\n')
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_environment_record"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_environment_record FILE\n")
    with assert_raises(contains="environment record is not an object"):
        _ = record_text("[]")
    with assert_raises(contains="objects are not a list"):
        _ = record_text("{}")
    with assert_raises(contains="vector is not 3 numbers"):
        _ = record_text(
            '{"objects":[{"id":1,"name":"a","label":"b","location":[1,2],'
            + '"rotation":[0,0,0],"box_center":[0,0,0],"box_extent":[0,0,0],'
            + '"box_rotation":[0,0,0]}]}'
        )
    with assert_raises(contains="id is not an integer"):
        _ = record_text(
            '{"objects":[{"id":1.5,"name":"a","label":"b",'
            + '"location":[0,0,0],"rotation":[0,0,0],"box_center":[0,0,0],'
            + '"box_extent":[0,0,0],"box_rotation":[0,0,0]}]}'
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "--build",
            "carla_environment_record",
        ],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
