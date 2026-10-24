# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The engine cube matches the reviewed Python box."""

from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.carla_town_cube import cube_text


comptime _SHA = (
    "c5266a04ac0c5a122c2b0e815163f03535c3db1f9931301178f53f28261b4431"
)
"""SHA-256 of the cube JSON, without a trailing newline."""


def test_the_box_matches_the_python_corners() raises:
    var text = cube_text()
    assert_equal(text.byte_length(), 1158)
    assert_equal(sha256_hex(text.as_bytes()), _SHA)
    assert_true(
        text.startswith(
            '{"material":"BasicShapeMaterial","positions":[[-0.5,-0.5,-0.5],'
        )
    )


def test_the_command_prints_the_cube() raises:
    var result = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_cube"],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(result.output, cube_text() + "\n")
    assert_true(result.errors.find("Crashpad") < 0)
    var extra = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_cube", "more"],
        30,
        merge_errors=False,
    )
    assert_equal(extra.status, 2)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_cube"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
