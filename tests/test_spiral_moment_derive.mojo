# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stored spiral-moment endpoints are derived in Mojo."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools.spiral_moment_derive import (
    derive_endpoints,
    stored_coefficient_words,
)
from tools.spiral_moment_table_text import canonical_table, parse_table
from tools.spiral_moment_words import SIGN, decimal_word


comptime _GEOMETRY = "extensions/carla/geometry.mojo"
comptime _TRIG = "extensions/carla/curve_trig.mojo"
comptime _TABLE = "extensions/carla/spiral_moment_table_data.mojo"


def _replace_once(text: String, before: String, after: String) raises -> String:
    """Replace the first `before` in `text`.

    Args:
        text: The source text.
        before: The text to find.
        after: The replacement.

    Returns:
        The text with one replacement.

    Raises:
        Error: `before` is absent.
    """
    var at = text.find(before)
    if at < 0:
        raise Error("missing text")
    var head = text[byte=0:at]
    var tail = text[byte = at + before.byte_length() :]
    return String(head) + after + String(tail)


def _live_words() raises -> List[UInt64]:
    """Return the endpoints derived from the live constants.

    Returns:
        The 2816 coefficient encodings.

    Raises:
        Error: A live constant or an endpoint is refused.
    """
    var geometry = Path(_GEOMETRY).read_text()
    var trig = Path(_TRIG).read_text()
    return derive_endpoints(
        stored_coefficient_words(geometry, "_GL_NODES", 5),
        stored_coefficient_words(geometry, "_GL_WEIGHTS", 5),
        stored_coefficient_words(trig, "_COS_COEFFICIENTS", 11),
        stored_coefficient_words(trig, "_SIN_COEFFICIENTS", 11),
    )


def test_derived_endpoints_match_the_live_table() raises:
    """The live constants produce the live table and its canonical bytes."""
    var text = Path(_TABLE).read_text()
    var derived = _live_words()
    var stored = parse_table(text.as_bytes())
    assert_equal(len(derived), len(stored))
    var index = 0
    while index < len(derived):
        if derived[index] != stored[index]:
            raise Error("endpoint " + String(index))
        index += 1
    assert_equal(canonical_table(derived), text)


def test_equivalent_spellings_keep_the_stored_words() raises:
    """A longer spelling, a space, and a comment keep the stored words."""
    var geometry = Path(_GEOMETRY).read_text()
    var original = stored_coefficient_words(geometry, "_GL_WEIGHTS", 5)
    var longer = _replace_once(
        geometry, "0.2369268850561891,", "0.23692688505618910000,"
    )
    assert_equal(
        stored_coefficient_words(longer, "_GL_WEIGHTS", 5)[0], original[0]
    )
    var spaced = _replace_once(
        geometry,
        "comptime _GL_NODES: Array[Float64, 5]",
        "comptime _GL_NODES : Array[Float64, 5]",
    )
    var nodes = stored_coefficient_words(geometry, "_GL_NODES", 5)
    var spaced_nodes = stored_coefficient_words(spaced, "_GL_NODES", 5)
    assert_equal(spaced_nodes[0], nodes[0])
    assert_equal(spaced_nodes[2], nodes[2])
    var commented = _replace_once(
        geometry,
        "comptime _GL_NODES: Array[Float64, 5] = [\n",
        "comptime _GL_NODES: Array[Float64, 5] = [  # literal-only array\n",
    )
    assert_equal(
        stored_coefficient_words(commented, "_GL_NODES", 5)[0], nodes[0]
    )


def test_signed_zero_changes_the_stored_word() raises:
    """A negative zero node keeps the sign bit."""
    var geometry = Path(_GEOMETRY).read_text()
    var nodes = stored_coefficient_words(geometry, "_GL_NODES", 5)
    assert_equal(nodes[2], UInt64(0))
    var changed = _replace_once(
        geometry,
        "    0.0,\n    0.5384693101056831",
        "    -0.0,\n    0.5384693101056831",
    )
    assert_equal(stored_coefficient_words(changed, "_GL_NODES", 5)[2], SIGN)


def test_a_string_decoy_keeps_the_stored_words() raises:
    """A declaration inside a string is not a second array."""
    var geometry = Path(_GEOMETRY).read_text()
    var nodes = stored_coefficient_words(geometry, "_GL_NODES", 5)
    var decoy = (
        String(
            '"""\ncomptime _GL_NODES: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0,'
            ' 0.0]\n"""\n'
        )
        + geometry
    )
    var words = stored_coefficient_words(decoy, "_GL_NODES", 5)
    assert_equal(words[0], nodes[0])
    assert_equal(words[4], nodes[4])


def test_a_bad_declaration_is_refused() raises:
    """A suffix, a second array, and a bad literal are refused."""
    var geometry = Path(_GEOMETRY).read_text()
    var suffix = _replace_once(
        geometry,
        "    0.9061798459386640,\n]\ncomptime _GL_WEIGHTS:",
        "    0.9061798459386640,\n] + [0.0]\ncomptime _GL_WEIGHTS:",
    )
    with assert_raises(contains="unsupported constant array"):
        _ = stored_coefficient_words(suffix, "_GL_NODES", 5)
    var second = (
        geometry
        + "\ncomptime _GL_NODES: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0,"
        " 0.0]\n"
    )
    with assert_raises(contains="ambiguous"):
        _ = stored_coefficient_words(second, "_GL_NODES", 5)
    with assert_raises(contains="ambiguous"):
        _ = stored_coefficient_words(geometry, "_ABSENT", 1)
    var broken = "comptime _GL_NODES: Array[Float64, 2] = [0.0 1.0]\n"
    with assert_raises(contains="unsupported constant literal"):
        _ = stored_coefficient_words(broken, "_GL_NODES", 2)
    var continued = (
        "comptime _GL_NODES: Array[Float64, 1] = [0.0] \\\n    + [0.0]\n"
    )
    with assert_raises(contains="unsupported constant array"):
        _ = stored_coefficient_words(continued, "_GL_NODES", 1)


def test_one_decimal_literal_keeps_its_encoding() raises:
    """One exact literal keeps the reviewed binary64 encoding."""
    var source = "comptime _PHASE: Array[Float64, 1] = [1e1]\n"
    var words = stored_coefficient_words(source, "_PHASE", 1)
    assert_equal(words[0], decimal_word("1e1"))


def main() raises:
    """Run the spiral-moment derivation tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
