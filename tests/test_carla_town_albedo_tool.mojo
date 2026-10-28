# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town material's base color is four unit numbers."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_png import png_bytes
from tools.carla_town_albedo import albedo_text


def test_a_missing_texture_keeps_the_factor() raises:
    assert_equal(
        albedo_text(
            '{"out_dir":"/tmp","material":{"name":"plain"},"textures":[],"images":[]}'
        ),
        '{"factor":[1.0,1.0,1.0,1.0]}',
    )
    assert_equal(
        albedo_text(
            '{"out_dir":"/tmp","material":{"pbrMetallicRoughness":'
            + '{"baseColorFactor":[0.5,0.5,0.5,1]}},"textures":[],"images":[]}'
        ),
        '{"factor":[0.5,0.5,0.5,1.0]}',
    )


def test_a_red_pixel_becomes_unit_color() raises:
    var root = mkdtemp(prefix="town albedo ")
    var pixels = List[UInt8]()
    pixels.append(255)
    pixels.append(0)
    pixels.append(0)
    pixels.append(128)
    var png = png_bytes("RGBA", 1, 1, pixels, True, 4, 6)
    Path(root + "/red.png").write_bytes(Span(png))
    var doc = albedo_text(
        '{"out_dir":"'
        + root
        + '","material":{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},'
        + '"baseColorFactor":[1,1,1,1]}},"textures":[{"source":0}],'
        + '"images":[{"uri":"red.png"}]}'
    )
    assert_true(doc.find('"width":1') >= 0)
    assert_true(doc.find('"height":1') >= 0)
    assert_true(doc.find('"rgba":[1.0,0.0,0.0,') >= 0)
    _ = run_program(["rm", "-rf", root], 10)


def test_the_command_prints_the_factor() raises:
    var path = String("/tmp/carla-town-albedo.json")
    Path(path).write_text(
        '{"out_dir":"/tmp","material":{},"textures":[],"images":[]}'
    )
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_albedo", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, '{"factor":[1.0,1.0,1.0,1.0]}\n')
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_albedo"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_albedo FILE\n")
    with assert_raises(contains="albedo request is not an object"):
        _ = albedo_text("[]")
    with assert_raises(contains="factor is not 4 numbers"):
        _ = albedo_text(
            '{"out_dir":"/tmp","material":{"pbrMetallicRoughness":'
            + '{"baseColorFactor":[1]}},"textures":[],"images":[]}'
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_albedo"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
