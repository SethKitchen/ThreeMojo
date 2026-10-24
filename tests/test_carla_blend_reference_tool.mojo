# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The blend ledger matches the former Python reference, and the native
fixture words come from that ledger.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.testing import TestSuite, assert_equal

from tools._sha256 import sha256_hex
from tools.carla_blend_reference import derive_rows, ledger_text, summary_text


def _words(source: String, name: String) raises -> List[String]:
    """Return the hexadecimal words of one native array.

    Args:
        source: The native suite.
        name: The array name.

    Returns:
        The words, lower case, including the `0x` prefix.

    Raises:
        Error: If the array is missing.
    """
    var marker = "var " + name + ": List[UInt64] = ["
    var start = source.find(marker)
    if start < 0:
        raise Error("missing " + name)
    var rest = String(source[byte = start + marker.byte_length() :])
    var end = rest.find("]")
    var body = String(rest[byte=:end])
    var words = List[String]()
    var at = 0
    while True:
        var found = String(body[byte=at:]).find("0x")
        if found < 0:
            break
        at += found
        words.append(String(body[byte = at : at + 18]).lower())
        at += 18
    return words^


def _hex(value: Float64) -> String:
    """Return a lowercase `0x` word.

    Args:
        value: The double.

    Returns:
        Sixteen hexadecimal digits.
    """
    var bits = bitcast[DType.uint64](value)
    var digits = String("0123456789abcdef")
    var text = String("0x")
    var shift = 15
    while shift >= 0:
        var nibble = Int((bits >> UInt64(shift * 4)) & 0xF)
        text += String(digits[byte = nibble : nibble + 1])
        shift -= 1
    return text


def test_the_ledger_matches_the_python_reference() raises:
    var ledger = ledger_text()
    var summary = summary_text()
    assert_equal(
        sha256_hex(Span(ledger.as_bytes())),
        "659b269a658288ede0b054a8bff738b98b63e44e523e7e4ac1fd8f28023f3686",
    )
    assert_equal(
        sha256_hex(Span(summary.as_bytes())),
        "93d566f783018289260a3c326fb8edee1df833b1508514fc7bebc09dc8f40b5b",
    )
    assert_equal(ledger.byte_length(), 9665)
    assert_equal(summary.byte_length(), 933)


def test_native_fixture_words_come_from_the_ledger() raises:
    var source = Path("tests/test_carla_tight_rounding.mojo").read_text()
    var rows = derive_rows()
    var coupled = _words(source, "coupled_error_words")
    var expected = _words(source, "expected_error_words")
    assert_equal(len(coupled), len(rows))
    assert_equal(len(expected), len(rows))
    for index in range(len(rows)):
        var row = rows[index].copy()
        assert_equal(coupled[index], _hex(row.coupled), String(index))
        assert_equal(expected[index], _hex(row.expected), String(index))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
