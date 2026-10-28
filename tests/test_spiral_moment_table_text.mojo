# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stored spiral-moment table declaration is read in Mojo."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._sha256 import sha256_hex
from tools._spiral_moment_table_text import (
    WORD_COUNT,
    canonical_table,
    parse_table,
)


comptime _PATH = "extensions/carla/spiral_moment_table_data.mojo"
comptime _PAYLOAD = (
    "72f5e5d09a6f4091e1a537aa89bf80493a427576b5ff86619830721edbc5f446"
)


def _payload(words: List[UInt64]) -> String:
    """Return the big-endian SHA-256 of `words`.

    Args:
        words: Coefficient encodings.

    Returns:
        The digest of those words packed as big-endian UInt64 values.
    """
    var packed = List[UInt8]()
    for word in words:
        packed.append(UInt8((word >> 56) & 255))
        packed.append(UInt8((word >> 48) & 255))
        packed.append(UInt8((word >> 40) & 255))
        packed.append(UInt8((word >> 32) & 255))
        packed.append(UInt8((word >> 24) & 255))
        packed.append(UInt8((word >> 16) & 255))
        packed.append(UInt8((word >> 8) & 255))
        packed.append(UInt8(word & 255))
    return sha256_hex(Span(packed))


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


def _push(mut out: List[UInt8], text: String):
    """Append `text` to `out`.

    Args:
        out: The destination bytes.
        text: The ASCII text to append.
    """
    for byte in text.as_bytes():
        out.append(byte)


def _declaration(
    size: String, count: Int, word: String, gap: String
) -> List[UInt8]:
    """Build one table declaration.

    Args:
        size: The declared array length.
        count: The number of words to write.
        word: One `0x` literal, including the prefix.
        gap: The whitespace before each word.

    Returns:
        The UTF-8 declaration.
    """
    var out = List[UInt8]()
    _push(out, "comptime _SPIRAL_MOMENT_WORDS: Array[UInt64, ")
    _push(out, size)
    _push(out, "] = [\n")
    var index = 0
    while index < count:
        _push(out, gap)
        _push(out, "UInt64(")
        _push(out, word)
        _push(out, "),\n")
        index += 1
    _push(out, "]\n")
    return out^


def _parse(text: String) raises -> List[UInt64]:
    """Parse `text`.

    Args:
        text: UTF-8 source.

    Returns:
        The coefficient words.

    Raises:
        Error: The declaration is refused.
    """
    return parse_table(text.as_bytes())


def test_live_table_words() raises:
    """The live table has 2816 words and the checked payload digest."""
    var data = Path(_PATH).read_bytes()
    var words = parse_table(Span(data))
    assert_equal(len(words), WORD_COUNT)
    assert_equal(words[0], UInt64(0x3FF0000000000000))
    assert_equal(words[1], UInt64(0x3FF0000000000001))
    assert_equal(words[WORD_COUNT - 1], UInt64(0x3B813246ABCE1BD3))
    assert_equal(_payload(words), _PAYLOAD)


def test_comments_and_paired_layout_keep_words() raises:
    """A comment and a paired layout keep the same words."""
    var text = Path(_PATH).read_text()
    var words = _parse(text)
    var commented = _parse(text + "# extra comment\n")
    assert_equal(_payload(commented), _payload(words))
    var paired = _replace_once(text, "),\n    UInt64(", "), UInt64(")
    assert_equal(_payload(_parse(paired)), _payload(words))


def test_leading_zero_shape_is_accepted() raises:
    """A declared length of 0002816 is the stored length."""
    var mixed = _declaration(
        "0002816", WORD_COUNT, "0x0A0000000000000a", " \t\v\f\r"
    )
    var words = parse_table(Span(mixed))
    assert_equal(words[0], UInt64(0x0A0000000000000A))
    assert_equal(words[WORD_COUNT - 1], UInt64(0x0A0000000000000A))


def test_bad_encoding_is_refused() raises:
    """A byte that is not UTF-8 is refused."""
    var raw = List[UInt8]()
    raw.append(0xFF)
    with assert_raises(contains="not UTF-8"):
        _ = parse_table(Span(raw))


def test_bad_declaration_is_refused() raises:
    """An empty file, a trailer, and a broken header are refused."""
    var empty = List[UInt8]()
    with assert_raises(contains="malformed table declaration"):
        _ = parse_table(Span(empty))
    var text = Path(_PATH).read_text()
    with assert_raises(contains="malformed table declaration"):
        _ = _parse(text + "comptime unexpected = 1\n")
    with assert_raises(contains="malformed table declaration"):
        _ = _parse(
            "comptime _SPIRAL_MOMENT_WORDS: Array[UInt64,  2816] = [\n]\n"
        )
    with assert_raises(contains="malformed table declaration"):
        _ = _parse("comptime _SPIRAL_MOMENT_WORDS: Array[UInt64, 2816] = [\n")


def test_bad_shape_is_refused() raises:
    """A declared length other than 2816 is refused."""
    var text = Path(_PATH).read_text()
    var changed = _replace_once(
        text, "Array[UInt64, 2816]", "Array[UInt64, 2815]"
    )
    with assert_raises(contains="declaration shape"):
        _ = _parse(changed)


def test_bad_word_is_refused() raises:
    """A short word, a bad digit, and a broken closer are refused."""
    var text = Path(_PATH).read_text()
    var short = _replace_once(text, "0x3FF0000000000000", "0x3FF000000000000")
    with assert_raises(contains="malformed coefficient"):
        _ = _parse(short)
    var upper = _declaration(String(WORD_COUNT), 1, "0X0000000000000000", " ")
    with assert_raises(contains="malformed coefficient"):
        _ = parse_table(Span(upper))
    var digit = _declaration(String(WORD_COUNT), 1, "0x000000000000000g", " ")
    with assert_raises(contains="malformed coefficient"):
        _ = parse_table(Span(digit))
    var closer = _declaration(String(WORD_COUNT), 1, "0x0000000000000000", " ")
    var broken = String(from_utf8=Span(closer)).replace("),", "].")
    with assert_raises(contains="malformed coefficient"):
        _ = _parse(broken)


def test_wrong_word_count_is_refused() raises:
    """One missing word and one extra word are refused."""
    var text = Path(_PATH).read_text()
    var missing = _replace_once(text, "UInt64(0x3FF0000000000000),", "")
    with assert_raises(contains="missing or extra"):
        _ = _parse(missing)
    var extra = _replace_once(
        text, "\n]\n", "\n    UInt64(0x0000000000000000),\n]\n"
    )
    with assert_raises(contains="missing or extra"):
        _ = _parse(extra)
    var zeros = _declaration("0002816", 0, "0x0000000000000000", " ")
    with assert_raises(contains="missing or extra"):
        _ = parse_table(Span(zeros))


def test_canonical_bytes_match_the_live_table() raises:
    """The live file is the canonical generated source."""
    var text = Path(_PATH).read_text()
    assert_equal(canonical_table(_parse(text)), text)


def test_a_paired_layout_is_not_canonical() raises:
    """A paired layout keeps the words and changes the bytes."""
    var text = Path(_PATH).read_text()
    var paired = _replace_once(text, "),\n    UInt64(", "), UInt64(")
    assert_equal(_payload(_parse(paired)), _payload(_parse(text)))
    assert_true(canonical_table(_parse(paired)) != paired)
    var extra = text + "# extra comment\n"
    assert_equal(_payload(_parse(extra)), _payload(_parse(text)))
    assert_true(canonical_table(_parse(extra)) != extra)


def main() raises:
    """Run the spiral-moment table tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
