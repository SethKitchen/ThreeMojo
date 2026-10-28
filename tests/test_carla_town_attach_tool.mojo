# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A plain town material and a picture material use the package counts."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_attach import attach_text


def test_a_basic_shape_is_plain_and_a_wall_is_rebuilt() raises:
    var plain = (
        '{"action":"plain","material":{"name":"plain",'
        + '"pbrMetallicRoughness":{"baseColorFactor":[0.5,0.5,0.5,1],'
        + '"metallicFactor":0.0,"roughnessFactor":0.7}}}'
    )
    assert_equal(
        attach_text('{"mode":"resolve","name":"BasicShapeMaterial"}'), plain
    )
    assert_equal(attach_text('{"mode":"resolve","name":""}'), plain)
    assert_equal(
        attach_text('{"mode":"resolve","name":"dummy_material_2"}'), plain
    )
    assert_equal(
        attach_text('{"mode":"resolve","name":"Wall"}'),
        '{"action":"rebuild"}',
    )


def test_a_picture_uses_the_next_image_and_texture() raises:
    assert_equal(
        attach_text(
            '{"mode":"picture","kind":"impostor","name":"tree","uri":"textures/tree.png","images":2,"textures":2,"materials":5}'
        ),
        (
            '{"image":{"uri":"textures/tree.png"},"texture":{"sampler":0,"source":2},'
            + '"material":{"name":"tree","pbrMetallicRoughness":{"baseColorTexture":{"index":2},"metallicFactor":0.0,"roughnessFactor":0.9},"alphaMode":"MASK","alphaCutoff":0.5,"doubleSided":true},"index":5}'
        ),
    )
    assert_true(
        attach_text(
            '{"mode":"picture","kind":"baked","name":"block","uri":"textures/block.jpg","images":1,"textures":1,"materials":4}'
        ).find('"roughnessFactor":0.85')
        >= 0
    )


def test_the_command_prints_the_material() raises:
    var path = String("/tmp/carla-town-attach.json")
    Path(path).write_text('{"mode":"resolve","name":"BasicShapeMaterial"}')
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_attach", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_true(ran.output.startswith('{"action":"plain"'))
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_attach"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_attach FILE\n")
    with assert_raises(contains="attach request is not an object"):
        _ = attach_text("[]")
    with assert_raises(contains="mode is not resolve or picture"):
        _ = attach_text('{"mode":"other"}')
    with assert_raises(contains="kind is not impostor or baked"):
        _ = attach_text(
            '{"mode":"picture","kind":"road","name":"a","uri":"b","images":0,"textures":0,"materials":0}'
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_attach"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
