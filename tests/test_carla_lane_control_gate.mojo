# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed lane-control record fails the gate."""

from std.os import makedirs
from std.pathlib import Path

from std.testing import TestSuite, assert_equal, assert_raises

from tools.carla_lane_control_gate import (
    lane_control_record,
    lane_control_tokens,
    lane_control_tokens_then_predecessors,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(contains="lane-control migration record changed"):
        lane_control_record(String("").as_bytes())
    with assert_raises(contains="lane-control migration record changed"):
        lane_control_record(String('{"a":1,"a":2}').as_bytes())


def test_the_reviewed_lane_control_record_passes() raises:
    """The reviewed record passes the digest and the repeated-key check."""
    lane_control_record(
        Path("tools/carla_lane_oracle/lane-control-migration.json").read_bytes()
    )


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


def test_a_token_mismatch_fails_before_the_predecessors() raises:
    """A bad token pair fails before the predecessor document is read."""
    var directory = "/tmp/lane-tokens-before-predecessors"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text('["lane token changed"]')
    Path(directory + "/0.left").write_text("def changed():\n    pass\n")
    Path(directory + "/0.right").write_text("def original():\n    pass\n")
    Path(directory + "/predecessor.json").write_text("not-json")
    with assert_raises(contains="lane token changed"):
        _ = lane_control_tokens_then_predecessors(directory)


def test_matching_tokens_return_the_predecessor_flags() raises:
    """An owned candidate is false after the token pair matches."""
    var directory = "/tmp/lane-tokens-then-predecessors"
    makedirs(directory, exist_ok=True)
    var source = "def f():\n    return 1\n"
    Path(directory + "/labels.json").write_text('["lane token changed"]')
    Path(directory + "/0.left").write_text(source)
    Path(directory + "/0.right").write_text(source)
    Path(directory + "/predecessor.json").write_text(
        '{"declarations":[{"path":"p","name":"n","before":"b"}],'
        + '"items":[{"owner":["x"],"path":"p","name":"n","expected":"e"}]}'
    )
    assert_equal(
        lane_control_tokens_then_predecessors(directory),
        '["false"]',
    )


def main() raises:
    """Run the lane-control gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
