# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A dependency keeps its token or its reviewed stored words."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import token_sha256
from tools._dependency_words import (
    checked_dependency_words,
    dependency_word_choice,
    dependency_word_choices,
    pinned_dependency_words,
)
from tools._python_json import PyJson


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


def _add_dependency(
    mut doc: PyJson,
    rows: Int,
    text: String,
    token: String,
    expected: String,
    path: String,
    geometry_token: String,
):
    """Append one dependency choice.

    Args:
        doc: The payload document.
        rows: The dependency list.
        text: The module text.
        token: The current token digest.
        expected: The recorded token digest.
        path: The dependency path.
        geometry_token: The reviewed geometry token.
    """
    var row = doc.new_dict()
    doc.set(row, "text", doc.new_str(text))
    doc.set(row, "token", doc.new_str(token))
    doc.set(row, "expected", doc.new_str(expected))
    doc.set(row, "path", doc.new_str(path))
    doc.set(row, "trig_path", doc.new_str("extensions/carla/curve_trig.mojo"))
    doc.set(row, "trig_token", doc.new_str("trig-token"))
    doc.set(
        row,
        "geometry_path",
        doc.new_str("extensions/carla/geometry.mojo"),
    )
    doc.set(row, "geometry_token", doc.new_str(geometry_token))
    doc.append(rows, row)


def test_an_unreviewed_choice_fails_before_the_word_check() raises:
    """Every choice is decided before a selected word list is checked."""
    var zeros = (
        "comptime _GL_NODES: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0, 0.0]\n"
        + "comptime _GL_WEIGHTS: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0,"
        " 0.0]\n"
    )
    var doc = PyJson()
    var rows = doc.new_list()
    _add_dependency(
        doc,
        rows,
        zeros,
        "changed",
        "geometry-token",
        "extensions/carla/geometry.mojo",
        "geometry-token",
    )
    _add_dependency(
        doc,
        rows,
        "def f():\n    return 1\n",
        "changed",
        "other-token",
        "other.mojo",
        "geometry-token",
    )
    doc.root = rows
    with assert_raises(contains="changed: other.mojo"):
        checked_dependency_words(doc.dumps())


def test_a_matching_token_skips_the_word_check() raises:
    """An unchanged token does not read the stored-word declarations."""
    var doc = PyJson()
    var rows = doc.new_list()
    _add_dependency(
        doc,
        rows,
        "not stored words",
        "same",
        "same",
        "other.mojo",
        "geometry-token",
    )
    doc.root = rows
    checked_dependency_words(doc.dumps())


def test_empty_dependency_words_are_accepted() raises:
    """No dependencies need no word check."""
    checked_dependency_words("[]")


def test_a_changed_geometry_word_list_is_refused() raises:
    """A geometry choice with different stored words keeps the word message."""
    var zeros = (
        "comptime _GL_NODES: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0, 0.0]\n"
        + "comptime _GL_WEIGHTS: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0,"
        " 0.0]\n"
    )
    var doc = PyJson()
    var rows = doc.new_list()
    _add_dependency(
        doc,
        rows,
        zeros,
        "changed",
        "geometry-token",
        "extensions/carla/geometry.mojo",
        "geometry-token",
    )
    doc.root = rows
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unchanged premise dependency"
            " changed: extensions/carla/geometry.mojo"
        )
    ):
        checked_dependency_words(doc.dumps())


def _pinned_payload(
    text: String, expected: String, path: String
) raises -> String:
    """Return one pin-free dependency list.

    Args:
        text: The module text.
        expected: The recorded token digest.
        path: The dependency path.

    Returns:
        A JSON list with one item.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    var row = doc.new_dict()
    doc.set(row, "text", doc.new_str(text))
    doc.set(row, "expected", doc.new_str(expected))
    doc.set(row, "path", doc.new_str(path))
    doc.append(rows, row)
    doc.root = rows
    return doc.dumps()


def test_a_matching_token_reads_the_pins_before_the_words() raises:
    """An unchanged token is accepted after the pins are read."""
    var source = "def f():\n    return 1\n"
    pinned_dependency_words(
        _pinned_payload(source, token_sha256(source), "other.mojo")
    )


def test_an_unreviewed_path_fails_after_the_pins() raises:
    """A changed token outside the reviewed pairs fails after the pins."""
    with assert_raises(contains="changed: other.mojo"):
        pinned_dependency_words(
            _pinned_payload("def f():\n    return 1\n", "nope", "other.mojo")
        )


def test_the_reviewed_trig_pin_selects_the_word_check() raises:
    """The stored trig pin selects the word check before that declaration."""
    with assert_raises(
        contains=(
            "missing or ambiguous stored-word declaration: _COS_COEFFICIENTS"
        )
    ):
        pinned_dependency_words(
            _pinned_payload(
                "nope",
                "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f",
                "extensions/carla/curve_trig.mojo",
            )
        )


def main() raises:
    """Run the dependency word-choice tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
