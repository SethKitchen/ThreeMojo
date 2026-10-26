# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stored spiral-moment endpoints are derived in Mojo."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._spiral_moment_derive import (
    derive_endpoints,
    stored_coefficient_words,
    stored_scalar_word,
)
from tools._spiral_moment_table_text import canonical_table, parse_table
from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._spiral_moment_words import (
    SIGN,
    decimal_word,
    fraction_of_word,
    nearest_even,
)


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


def test_rounded_node_sums_match_their_pins() raises:
    """The rounded one-plus-node words and the weight sum match their pins."""
    var geometry = Path(_GEOMETRY).read_text()
    var nodes = stored_coefficient_words(geometry, "_GL_NODES", 5)
    var expected = List[UInt64]()
    expected.append(UInt64(0x3FB80498FD662CB8))
    expected.append(UInt64(0x3FDD89B804CC91F6))
    expected.append(UInt64(0x3FF0000000000000))
    expected.append(UInt64(0x3FF89D91FECCDB82))
    expected.append(UInt64(0x3FFE7FB670299D34))
    var index = 0
    while index < 5:
        var rounded = nearest_even(Fraction(1) + fraction_of_word(nodes[index]))
        assert_equal(rounded, expected[index])
        index += 1
    var weights = stored_coefficient_words(geometry, "_GL_WEIGHTS", 5)
    var total = Fraction(0)
    for weight in weights:
        total = total + fraction_of_word(weight)
    var half = total / Fraction(2)
    var zeroth = Fraction(1) + Fraction.of(BigInt(3), BigInt.power_of_two(55))
    assert_equal(half == zeroth, True)


def _words(source: String, name: String, size: Int) raises -> List[UInt64]:
    """Return one stored array.

    Args:
        source: The module source.
        name: The array name.
        size: The declared length.

    Returns:
        The stored words.

    Raises:
        Error: The array is refused.
    """
    return stored_coefficient_words(source, name, size)


def _expect(words: List[UInt64], values: List[UInt64]) raises:
    """Require `words` to equal `values`.

    Args:
        words: The stored words.
        values: The pin words.
    """
    assert_equal(len(words), len(values))
    var index = 0
    while index < len(words):
        assert_equal(words[index], values[index])
        index += 1


def test_stored_scalar_and_array_words_match_their_pins() raises:
    """The four scalars and the four arrays match their stored words."""
    var trig = Path(_TRIG).read_text()
    var geometry = Path(_GEOMETRY).read_text()
    assert_equal(
        stored_scalar_word(trig, "_PHASE_LIMIT"), UInt64(0x4130000000000000)
    )
    assert_equal(
        stored_scalar_word(trig, "_INV_HALF_PI"), UInt64(0x3FE45F306DC9C883)
    )
    assert_equal(
        stored_scalar_word(trig, "_HALF_PI_HIGH"), UInt64(0x3FF921FB54400000)
    )
    assert_equal(
        stored_scalar_word(trig, "_HALF_PI_LOW"), UInt64(0x3DD0B4611A626331)
    )
    var nodes = _words(geometry, "_GL_NODES", 5)
    var node_pins = List[UInt64]()
    node_pins.append(UInt64(0xBFECFF6CE0533A69))
    node_pins.append(UInt64(0xBFE13B23FD99B705))
    node_pins.append(UInt64(0))
    node_pins.append(UInt64(0x3FE13B23FD99B705))
    node_pins.append(UInt64(0x3FECFF6CE0533A69))
    _expect(nodes, node_pins)
    var weights = _words(geometry, "_GL_WEIGHTS", 5)
    var weight_pins = List[UInt64]()
    weight_pins.append(UInt64(0x3FCE539EC36E038D))
    weight_pins.append(UInt64(0x3FDEA1DA25AE415C))
    weight_pins.append(UInt64(0x3FE23456789ABCDF))
    weight_pins.append(UInt64(0x3FDEA1DA25AE415C))
    weight_pins.append(UInt64(0x3FCE539EC36E038D))
    _expect(weights, weight_pins)
    var cosine = _words(trig, "_COS_COEFFICIENTS", 11)
    var cosine_pins = List[UInt64]()
    cosine_pins.append(UInt64(0x3FF0000000000000))
    cosine_pins.append(UInt64(0xBFE0000000000000))
    cosine_pins.append(UInt64(0x3FA5555555555555))
    cosine_pins.append(UInt64(0xBF56C16C16C16C17))
    cosine_pins.append(UInt64(0x3EFA01A01A01A01A))
    cosine_pins.append(UInt64(0xBE927E4FB7789F5C))
    cosine_pins.append(UInt64(0x3E21EED8EFF8D898))
    cosine_pins.append(UInt64(0xBDA93974A8C07C9D))
    cosine_pins.append(UInt64(0x3D2AE7F3E733B81F))
    cosine_pins.append(UInt64(0xBCA6827863B97D97))
    cosine_pins.append(UInt64(0x3C1E542BA4020225))
    _expect(cosine, cosine_pins)
    var sine = _words(trig, "_SIN_COEFFICIENTS", 11)
    var sine_pins = List[UInt64]()
    sine_pins.append(UInt64(0x3FF0000000000000))
    sine_pins.append(UInt64(0xBFC5555555555555))
    sine_pins.append(UInt64(0x3F81111111111111))
    sine_pins.append(UInt64(0xBF2A01A01A01A01A))
    sine_pins.append(UInt64(0x3EC71DE3A556C734))
    sine_pins.append(UInt64(0xBE5AE64567F544E4))
    sine_pins.append(UInt64(0x3DE6124613A86D09))
    sine_pins.append(UInt64(0xBD6AE7F3E733B81F))
    sine_pins.append(UInt64(0x3CE952C77030AD4A))
    sine_pins.append(UInt64(0xBC62F49B46814157))
    sine_pins.append(UInt64(0x3BD71B8EF6DCF572))
    _expect(sine, sine_pins)


def test_a_changed_scalar_word_is_refused() raises:
    """A longer spelling keeps the word, and a change or a suffix does not."""
    var trig = Path(_TRIG).read_text()
    var original = stored_scalar_word(trig, "_PHASE_LIMIT")
    var longer = trig.replace("Float64(1048576.0)", "Float64(1048576.000)")
    assert_equal(stored_scalar_word(longer, "_PHASE_LIMIT"), original)
    var changed = trig.replace("Float64(1048576.0)", "Float64(1048577.0)")
    assert_true(stored_scalar_word(changed, "_PHASE_LIMIT") != original)
    var suffix = trig.replace(
        "Float64(1048576.0)", "Float64(1048576.0) + Float64(1.0)"
    )
    with assert_raises(contains="unsupported scalar"):
        _ = stored_scalar_word(suffix, "_PHASE_LIMIT")
    var second = trig + "\ncomptime _PHASE_LIMIT = Float64(1.0)\n"
    with assert_raises(contains="ambiguous scalar"):
        _ = stored_scalar_word(second, "_PHASE_LIMIT")


def main() raises:
    """Run the spiral-moment derivation tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
