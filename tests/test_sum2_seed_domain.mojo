# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live seed-domain caller keeps its two guards and the pin."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_seed_domain import sum2_seed_domain


def _copy(root: String) raises:
    """Copy the seed-domain inputs.

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
    files.append("extensions/carla/map.mojo")
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_seed_domain_caller_holds() raises:
    """The live caller matches the pin after the two guards."""
    sum2_seed_domain(".")
    sum2_seed_domain("./")


def test_a_changed_seed_domain_body_is_refused() raises:
    """A changed seed-domain body is refused."""
    var root = "/tmp/sum2-seed-domain-body"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "if not isfinite(geometry.length) or geometry.length <= 0.0:",
            "if not isfinite(geometry.length) or geometry.length < 0.0:",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: map:_seed_reference_domain"
        )
    ):
        sum2_seed_domain(root)


def test_a_changed_seed_domain_error_guard_is_refused() raises:
    """A changed error guard is refused."""
    var root = "/tmp/sum2-seed-domain-guard"
    _copy(root)
    var map_path = root + "/extensions/carla/map.mojo"
    Path(map_path).write_text(
        Path(map_path)
        .read_text()
        .replace(
            "or not d.error < 1.0:",
            "or not d.error <= 1.0:",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: map:_seed_reference_domain"
        )
    ):
        sum2_seed_domain(root)


def main() raises:
    """Run the seed-domain caller tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
