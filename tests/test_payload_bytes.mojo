# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Hexadecimal payload text follows Python's `bytes.fromhex`."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._payload_bytes import from_hex


def _spell(bytes: List[UInt8]) -> String:
    var text = String("")
    for byte in bytes:
        if text.byte_length() > 0:
            text += ","
        text += String(Int(byte))
    return text


def test_hex_pairs_and_whitespace_match_python() raises:
    """Digits, case, and whitespace between pairs decode to bytes."""
    assert_equal(len(from_hex("")), 0)
    assert_equal(len(from_hex(" ")), 0)
    assert_equal(_spell(from_hex("aa")), "170")
    assert_equal(_spell(from_hex("AA")), "170")
    assert_equal(_spell(from_hex("FF00")), "255,0")
    assert_equal(_spell(from_hex("00ff 7A\n10")), "0,255,122,16")
    assert_equal(_spell(from_hex("\taa")), "170")
    assert_equal(_spell(from_hex("aa\rbb")), "170,187")
    assert_equal(_spell(from_hex("aa\x0bbb")), "170,187")
    assert_equal(_spell(from_hex("aa\x0cbb")), "170,187")
    assert_equal(_spell(from_hex("aF")), "175")


def test_a_broken_hex_pair_names_pythons_position() raises:
    """Odd length and a bad digit use Python's position text."""
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 1"
    ):
        _ = from_hex("0")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 3"
    ):
        _ = from_hex("abc")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 0"
    ):
        _ = from_hex("zz")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 1"
    ):
        _ = from_hex("0g")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 0"
    ):
        _ = from_hex("/0")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 0"
    ):
        _ = from_hex(":0")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 1"
    ):
        _ = from_hex("0/")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 1"
    ):
        _ = from_hex("0:")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 1"
    ):
        _ = from_hex("a a")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 4"
    ):
        _ = from_hex("ab c")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 0"
    ):
        _ = from_hex("\x080")
    with assert_raises(
        contains="non-hexadecimal number found in fromhex() arg at position 0"
    ):
        _ = from_hex("\x0e0")


def main() raises:
    """Run the payload byte tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
