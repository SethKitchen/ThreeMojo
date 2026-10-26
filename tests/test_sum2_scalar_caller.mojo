# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live scalar spiral caller keeps the SI constructor and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_scalar_caller import sum2_scalar_caller


def _copy(root: String) raises:
    """Copy the scalar-caller inputs.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/extensions/carla",
            root + "/tools/carla_lane_oracle",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/carla/lane_geometry.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_scalar_spiral_caller_holds() raises:
    """The live caller matches the pin after the SI constructor."""
    sum2_scalar_caller(".")
    sum2_scalar_caller("./")


def test_a_changed_scalar_spiral_body_is_refused() raises:
    """A changed scalar body is refused."""
    var root = "/tmp/sum2-scalar-caller-body"
    _copy(root)
    var lane = root + "/extensions/carla/lane_geometry.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "var work = ceil(d * (1.0 + reach))",
            "var work = ceil(d * (2.0 + reach))",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: lane_geometry:_lane_spiral"
        )
    ):
        sum2_scalar_caller(root)


def test_a_bare_directed_point_constructor_is_refused() raises:
    """A bare directed-point constructor is refused."""
    var root = "/tmp/sum2-scalar-caller-ctor"
    _copy(root)
    var lane = root + "/extensions/carla/lane_geometry.mojo"
    var source = Path(lane).read_text()
    var marker = "def _lane_spiral("
    var at = source.find(marker)
    if at < 0:
        raise Error("missing scalar spiral")
    var head = String(source[byte=0:at])
    var tail = String(source[byte=at:])
    var next = tail.find("\ndef ")
    if next < 0:
        raise Error("missing scalar spiral end")
    var body = String(tail[byte=0:next])
    var rest = String(tail[byte=next:])
    body = body.replace("DirectedPoint._from_si(", "DirectedPoint(")
    Path(lane).write_text(head + body + rest)
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: lane_geometry:_lane_spiral"
        )
    ):
        sum2_scalar_caller(root)


def main() raises:
    """Run the scalar spiral caller tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
