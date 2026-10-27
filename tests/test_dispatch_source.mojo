# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The dispatch source choice and premise text comparison stay reviewed."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._dispatch_source import reviewed_source_choice, texts_match


def _choice(token: String, expected: String, path: String) -> String:
    """Return one source-choice document.

    Args:
        token: The current token digest.
        expected: The recorded token digest.
        path: The source path.

    Returns:
        The JSON payload.
    """
    return (
        '{"token":"'
        + token
        + '","expected":"'
        + expected
        + '","path":"'
        + path
        + '","dispatch_path":"extensions/carla/curve_sample_dispatch.mojo"}'
    )


def test_the_dispatch_source_choice_keeps_a_matching_token() raises:
    """A matching token stays current, and the dispatch path may restore."""
    assert_equal(
        reviewed_source_choice(_choice("aa", "aa", "other.mojo")), "current"
    )
    assert_equal(
        reviewed_source_choice(
            _choice("aa", "aa", "extensions/carla/curve_sample_dispatch.mojo")
        ),
        "current",
    )
    assert_equal(
        reviewed_source_choice(
            _choice("bb", "aa", "extensions/carla/curve_sample_dispatch.mojo")
        ),
        "restore",
    )


def test_an_unreviewed_dispatch_successor_is_refused() raises:
    """A changed token outside the dispatch module keeps its message."""
    with assert_raises(
        contains=(
            "curve support/dispatch contract: unreviewed source successor:"
            " other.mojo"
        )
    ):
        _ = reviewed_source_choice(_choice("bb", "aa", "other.mojo"))


def test_premise_texts_compare_as_strings() raises:
    """Equal texts match, including the empty text, and a change does not."""
    assert_equal(
        texts_match('{"actual":"same\\nline","expected":"same\\nline"}'), "true"
    )
    assert_equal(texts_match('{"actual":"","expected":""}'), "true")
    assert_equal(texts_match('{"actual":"same","expected":"changed"}'), "false")


def main() raises:
    """Run the dispatch source tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
