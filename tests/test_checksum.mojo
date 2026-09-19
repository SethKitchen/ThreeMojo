# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.checksum`.

The expected values come from zlib, through Python's `zlib.crc32` and
`zlib.adler32`, over a fixed pattern of bytes. Both checksums are stepped
through their fast paths here -- the CRC's eight-byte slices and its table
threshold, the Adler-32's run of 5552 -- at the lengths where each path
begins, ends and leaves a tail, so a mistake in any of them is caught at the
boundary rather than averaged away. The bitwise CRC is spelled out here as
well, independently, so the tables have something to be measured against
that is not themselves.
"""

from render.checksum import (
    ADLER_RUN,
    CRC_TABLE_WORTH,
    Crc32,
    adler32,
    crc32,
)
from std.testing import TestSuite, assert_equal, assert_true


def pattern(count: Int) -> List[UInt8]:
    """Return `count` bytes of `(index * 7 + 3) mod 256`, the pattern the
    expected values were computed over."""
    var bytes = List[UInt8]()
    for index in range(count):
        bytes.append(UInt8((index * 7 + 3) & 0xFF))
    return bytes^


def crc32_bitwise(bytes: List[UInt8]) -> UInt32:
    """The definition, eight shifts a byte, as a check on the tables."""
    var crc = UInt32(0xFFFFFFFF)
    for index in range(len(bytes)):
        crc ^= UInt32(bytes[index])
        for _ in range(8):
            if (crc & UInt32(1)) != 0:
                crc = (crc >> 1) ^ UInt32(0xEDB88320)
            else:
                crc = crc >> 1
    return crc ^ UInt32(0xFFFFFFFF)


def adler32_by_the_byte(bytes: List[UInt8]) -> UInt32:
    """The definition, a modulo after every byte, as a check on the runs."""
    var low = UInt32(1)
    var high = UInt32(0)
    for index in range(len(bytes)):
        low = (low + UInt32(bytes[index])) % 65521
        high = (high + low) % 65521
    return (high << 16) | low


def ascii(text: String) -> List[UInt8]:
    """Return the bytes of an ASCII string."""
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    return bytes^


def test_crc32_of_the_check_value() raises:
    # The CRC-32 check value: "123456789" gives 0xCBF43926.
    assert_equal(crc32(ascii("123456789")), UInt32(0xCBF43926))


def test_adler32_of_the_check_value() raises:
    assert_equal(adler32(ascii("123456789")), UInt32(0x091E01DE))


def test_checksums_of_nothing() raises:
    assert_equal(crc32(List[UInt8]()), UInt32(0))
    assert_equal(adler32(List[UInt8]()), UInt32(1))


def test_crc32_below_a_slice_is_bitwise_and_right() raises:
    # Shorter than one eight-byte step, and than the table threshold.
    assert_equal(crc32(pattern(1)), UInt32(0x4B0BBE37))
    assert_equal(crc32(pattern(7)), UInt32(0x54491CDB))


def test_crc32_around_one_slice() raises:
    assert_equal(crc32(pattern(8)), UInt32(0xE2E35978))
    assert_equal(crc32(pattern(9)), UInt32(0x3D351CFE))
    assert_equal(crc32(pattern(15)), UInt32(0x7C619EDC))
    assert_equal(crc32(pattern(16)), UInt32(0x191F3D9F))
    assert_equal(crc32(pattern(17)), UInt32(0x7BA75EE3))


def test_crc32_either_side_of_the_table_threshold() raises:
    # One byte below the threshold is still bitwise; at it the tables are
    # built and every byte goes through them, tail included.
    assert_equal(CRC_TABLE_WORTH, 480)
    assert_equal(crc32(pattern(479)), UInt32(0x61A9E53C))
    assert_equal(crc32(pattern(480)), UInt32(0xE90D66A0))
    assert_equal(crc32(pattern(481)), UInt32(0xA65A3071))
    assert_equal(crc32(pattern(4096)), UInt32(0x5E4E1995))


def test_crc32_tables_agree_with_the_definition() raises:
    for count in [480, 481, 487, 488, 1000, 4097]:
        var bytes = pattern(count)
        assert_equal(crc32(bytes), crc32_bitwise(bytes))
    var ones = List[UInt8](length=12000, fill=UInt8(255))
    assert_equal(crc32(ones), UInt32(0x0036738F))
    assert_equal(crc32(ones), crc32_bitwise(ones))


def test_crc32_fed_in_pieces_is_the_crc32_of_the_whole() raises:
    var whole = pattern(1000)
    var first = pattern(1000)
    first.resize(300, UInt8(0))
    var second = List[UInt8]()
    second.extend(Span(whole)[300:1000])
    var crc = Crc32()
    crc.update(Span(first))
    crc.update(Span(second))
    assert_equal(crc.finish(), crc32(whole))
    # The chunk case: a four-byte type, then its data, in two pieces.
    var typed = Crc32()
    typed.update(Span(ascii("IDAT")))
    typed.update(Span(whole))
    var joined = ascii("IDAT")
    joined.extend(Span(whole))
    assert_equal(typed.finish(), crc32(joined))


def test_crc32_keeps_its_tables_for_a_short_span_after_a_long_one() raises:
    # Once built, the tables serve every later span, however short.
    var whole = pattern(500)
    var crc = Crc32()
    crc.update(Span(whole)[0:490])
    assert_true(crc.built)
    crc.update(Span(whole)[490:500])
    assert_true(crc.built)
    assert_equal(crc.finish(), crc32(whole))


def test_crc32_stays_bitwise_for_short_spans() raises:
    var crc = Crc32()
    crc.update(Span(pattern(100)))
    crc.update(Span(pattern(100)))
    assert_true(not crc.built)
    var both = pattern(100)
    both.extend(Span(pattern(100)))
    assert_equal(crc.finish(), crc32(both))


def test_adler32_across_one_run() raises:
    assert_equal(ADLER_RUN, 5552)
    assert_equal(adler32(pattern(5551)), UInt32(0x4E91CA73))
    assert_equal(adler32(pattern(5552)), UInt32(0x19DFCB3F))
    assert_equal(adler32(pattern(5553)), UInt32(0xE5F1CC12))


def test_adler32_across_two_runs() raises:
    assert_equal(adler32(pattern(11104)), UInt32(0x415F978C))
    assert_equal(adler32(pattern(11105)), UInt32(0xD98E982F))
    assert_equal(adler32(pattern(12000)), UInt32(0x3D0A57EA))


def test_adler32_runs_agree_with_the_definition() raises:
    # All ones grow the sums fastest, which is the case the run length is
    # chosen for.
    var ones = List[UInt8](length=12000, fill=UInt8(255))
    assert_equal(adler32(ones), UInt32(0x09B1B3D3))
    assert_equal(adler32(ones), adler32_by_the_byte(ones))
    for count in [1, 16, 5552, 5553, 12000]:
        var bytes = pattern(count)
        assert_equal(adler32(bytes), adler32_by_the_byte(bytes))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
