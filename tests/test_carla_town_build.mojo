# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The town builder refuses a missing layout and a bad command."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_build import build_town


def test_a_missing_layout_is_refused() raises:
    """A town with no layout file is refused."""
    with assert_raises():
        _ = build_town(
            "Fixture",
            512,
            32.0,
            "/tmp/town-build-missing-raw",
            "/tmp/town-build-missing-layout",
            "/tmp/town-build-missing-maps",
            "/tmp/town-build-missing-out",
        )


def test_the_command_requires_a_value_after_max_size() raises:
    """`--max-size` without a number is refused."""
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_build",
            "--max-size",
        ],
        30.0,
        merge_errors=False,
    )
    assert_equal(result.status, 2)
    assert_true(result.errors.startswith("usage: carla_town_build "))


def main() raises:
    """Run the town builder tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_build"],
        180.0,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
