# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The cut-out channel of a foliage mask.

The channel with the most near-black or near-white samples wins. An
equal count keeps the earlier channel.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_mask_channel import mask_text


def _green() -> String:
    """Return one pixel whose green sample is white."""
    return '{"width":1,"height":1,"pixels":[128,255,10]}'


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test mask channel ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_mask_channel")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_the_extreme_channel_wins_and_a_tie_keeps_red() raises:
    assert_equal(mask_text(_green()), '{"channel":1,"pixels":[255]}')
    assert_equal(
        mask_text('{"width":2,"height":1,"pixels":[0,128,0,0,128,0]}'),
        '{"channel":0,"pixels":[0,0]}',
    )
    assert_equal(
        mask_text('{"width":1,"height":1,"pixels":[128,128,250]}'),
        '{"channel":2,"pixels":[250]}',
    )
    with assert_raises(contains="mask request is not an object"):
        _ = mask_text("[]")
    with assert_raises(contains="pixels do not match the image"):
        _ = mask_text('{"width":1,"height":1,"pixels":[1,2]}')
    with assert_raises(contains="pixel is out of range"):
        _ = mask_text('{"width":1,"height":1,"pixels":[1,2,256]}')
    with assert_raises(contains="size is not positive"):
        _ = mask_text('{"width":0,"height":1,"pixels":[]}')


def test_the_command_prints_the_channel_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/mask.json"
    Path(path).write_text(_green())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"channel":1,"pixels":[255]}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_mask_channel FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_mask_channel:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_mask_channel"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
