# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Watched-name mentions are checked before the observed consumers."""

from std.testing import TestSuite, assert_raises

from tools._optional_model_consumers import mentioned_consumers


def _frame(text: String) -> String:
    """Return one length-prefixed text.

    Args:
        text: The module text.

    Returns:
        A length line and the exact text bytes.
    """
    return String(len(text.as_bytes())) + "\n" + text


def test_a_comment_is_not_a_consumer() raises:
    """A mentioned comment stays allowed, and an empty frame passes."""
    var comment = "# _try_objective_model stays in a comment\n"
    mentioned_consumers(
        _frame(comment),
        '["extensions/carla/note.mojo"]',
        1,
    )
    mentioned_consumers("", "[]", 0)


def test_an_executable_model_name_is_refused_after_the_mention() raises:
    """The helper file may name itself. Another file may not."""
    var helper = "def _try_objective_model():\n    pass\n"
    mentioned_consumers(
        _frame(helper),
        '["extensions/carla/curve_objective_model.mojo"]',
        1,
    )
    var caller = "def use():\n    var model = _try_objective_model\n"
    with assert_raises(
        contains=(
            "optional runtime contract: containing-objective model production"
            " consumer reintroduced: extensions/carla/other.mojo"
        )
    ):
        mentioned_consumers(
            _frame(caller),
            '["extensions/carla/other.mojo"]',
            1,
        )
    var lane = "def use():\n    var cached_model = 1\n"
    with assert_raises(
        contains=(
            "optional runtime contract: containing-objective model search state"
            " reintroduced"
        )
    ):
        mentioned_consumers(
            _frame(lane),
            '["extensions/carla/lane_refinement.mojo"]',
            1,
        )


def test_a_bad_frame_fails_before_the_consumer_check() raises:
    """A short length line and a wrong count keep their earlier messages."""
    with assert_raises(contains="invalid model text length"):
        mentioned_consumers("5\nab", "[]", 0)
    with assert_raises(
        contains="optional runtime contract: model name set changed"
    ):
        mentioned_consumers("", "[]", 1)


def main() raises:
    """Run the mentioned-consumer tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
