# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""An 8-bit image resized as Pillow resizes it.

A box filter of a split square is its average. Lanczos of that square
matches Pillow. A premultiplied color is restored.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_image_resize import resize_text


def _split() -> String:
    """Return a 4 by 4 image, red-brown on the left and green on the right."""
    var pixel = String("")
    for index in range(16):
        if index > 0:
            pixel += ","
        if index % 4 < 2:
            pixel += "192,64,16"
        else:
            pixel += "0,128,32"
    return (
        '{"mode":"box","width":4,"height":4,"bands":3,'
        '"out_width":1,"out_height":1,"pixels":['
        + pixel
        + "]}"
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test image resize ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_image_resize")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_box_and_lanczos_match_pillow() raises:
    assert_equal(resize_text(_split()), '{"pixels":[96,96,24]}')
    assert_equal(
        resize_text(
            '{"mode":"lanczos","width":2,"height":1,"bands":4,'
            '"out_width":1,"out_height":1,'
            '"pixels":[255,0,0,128,0,0,255,64]}'
        ),
        '{"pixels":[170,0,85,96]}',
    )
    with assert_raises(contains="pixels do not match the image"):
        _ = resize_text(
            '{"mode":"lanczos","width":4,"height":4,"bands":3,'
            '"out_width":4,"out_height":4,"pixels":[1,2,3]}'
        )


def test_the_command_prints_the_pixels_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/resize.json"
    Path(path).write_text(_split())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"pixels":[96,96,24]}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_image_resize FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_image_resize:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    assert_equal(
        resize_text('{"mode":"bytes","pixels":[-0.2,0,0.5,1,1.2]}'),
        '{"pixels":[0,0,127,255,255]}',
    )
    with assert_raises(contains="mode is not lanczos, box, or bytes"):
        _ = resize_text(
            '{"mode":"near","width":1,"height":1,"bands":1,'
            '"out_width":1,"out_height":1,"pixels":[1]}'
        )
    with assert_raises(contains="pixels do not match the image"):
        _ = resize_text(
            '{"mode":"box","width":1,"height":1,"bands":1,'
            '"out_width":1,"out_height":1,"pixels":[]}'
        )
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_image_resize"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
