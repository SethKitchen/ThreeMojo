# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A dependency keeps its token or its reviewed stored words."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import token_sha256
from tools._dependency_words import (
    dependency_word_choice,
    dependency_word_choices,
)


def _payload(
    token: String,
    expected: String,
    path: String,
) -> String:
    """Return one dependency choice document.

    Args:
        token: The current token digest.
        expected: The recorded token digest.
        path: The dependency path.

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
        + '","trig_path":"trig.mojo","trig_token":"trig-token",'
        + '"geometry_path":"geometry.mojo","geometry_token":"geometry-token"}'
    )


def test_a_dependency_keeps_its_reviewed_word_choice() raises:
    """An exact token matches, and each reviewed pair keeps its kind."""
    assert_equal(
        dependency_word_choice(_payload("same", "same", "other.mojo")), "match"
    )
    assert_equal(
        dependency_word_choice(
            _payload("trig-token", "trig-token", "trig.mojo")
        ),
        "match",
    )
    assert_equal(
        dependency_word_choice(_payload("changed", "trig-token", "trig.mojo")),
        "trig",
    )
    assert_equal(
        dependency_word_choice(
            _payload("changed", "geometry-token", "geometry.mojo")
        ),
        "geometry",
    )


def test_an_unreviewed_dependency_change_is_refused() raises:
    """A changed token outside the reviewed pairs keeps its message."""
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unchanged premise dependency"
            " changed: trig.mojo"
        )
    ):
        _ = dependency_word_choice(
            _payload("changed", "other-token", "trig.mojo")
        )
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unchanged premise dependency"
            " changed: other.mojo"
        )
    ):
        _ = dependency_word_choice(
            _payload("changed", "trig-token", "other.mojo")
        )
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unchanged premise dependency"
            " changed: geometry.mojo"
        )
    ):
        _ = dependency_word_choice(
            _payload("changed", "other-token", "geometry.mojo")
        )


def test_dependency_word_lists_keep_their_order() raises:
    """Each dependency keeps its own word check."""
    assert_equal(
        dependency_word_choices(
            "["
            + _payload("same", "same", "other.mojo")
            + ","
            + _payload("changed", "trig-token", "trig.mojo")
            + ","
            + _payload("changed", "geometry-token", "geometry.mojo")
            + "]"
        ),
        '["match","trig","geometry"]',
    )


def test_a_later_unreviewed_dependency_is_refused() raises:
    """A later changed token keeps its message."""
    with assert_raises(contains="changed: other.mojo"):
        _ = dependency_word_choices(
            "["
            + _payload("same", "same", "other.mojo")
            + ","
            + _payload("changed", "other-token", "other.mojo")
            + "]"
        )


def test_a_source_text_uses_its_kept_token_digest() raises:
    """A source is hashed when the payload has no token."""
    var source = "def f():\n    return 1\n"
    var digest = token_sha256(source)
    var payload = (
        '{"text":"def f():\\n    return 1\\n","expected":"'
        + digest
        + '","path":"other.mojo","trig_path":"trig.mojo",'
        + '"trig_token":"trig-token","geometry_path":"geometry.mojo",'
        + '"geometry_token":"geometry-token"}'
    )
    assert_equal(dependency_word_choice(payload), "match")


def main() raises:
    """Run the dependency word-choice tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
