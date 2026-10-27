# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed lane-control record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.carla_lane_control_gate import (
    lane_control_record,
    lane_control_tokens,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(contains="lane-control migration record changed"):
        lane_control_record(String("").as_bytes())


def test_a_changed_declaration_is_refused() raises:
    """Different declaration texts fail closed."""
    var directory = "/tmp/lane-control-token-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '["lane-control successor module changed"]'
    )
    Path(directory + "/0.left").write_text("def changed():\n    pass\n")
    Path(directory + "/0.right").write_text("def original():\n    pass\n")
    with assert_raises(contains="lane-control successor module changed"):
        lane_control_tokens(directory)


def main() raises:
    """Run the lane-control gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
