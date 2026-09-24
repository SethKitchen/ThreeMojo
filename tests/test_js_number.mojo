# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`loaders.js_number`'s number text against V8.

`assets/js_number/v8.json` holds what node 22 writes for about 150
numbers: `String`, `toPrecision` of 1, 7 and 21, `toFixed` of 0, 7 and
20, and the shortest text of the nearest `Float32`. Each number is the
hex of its double.
"""

from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises

from loaders.js_number import (
    js_float32_text,
    js_number_text,
    js_to_fixed,
    js_to_precision,
    srgb_to_linear,
)
from loaders.json import parse_json


def _from_hex(text: String) raises -> Float64:
    """Return the double whose bits a hex text spells."""
    var bits: UInt64 = 0
    for b in text.as_bytes():
        var digit = Int(b) - 48 if b <= 57 else Int(b) - 87
        bits = (bits << 4) | UInt64(digit)
    return bitcast[DType.float64](bits)


def _read(text: String) raises -> Float64:
    """Return a number's text as a double, with the zeros at the end of a
    whole number as an exponent: Mojo's parser refuses a whole number
    past 64 bits."""
    var zeros = 0
    var digits = text
    while (
        digits.byte_length() > 1
        and digits.endswith("0")
        and not digits.__contains__(".")
        and not digits.__contains__("e")
    ):
        var shorter = String(digits[byte = : digits.byte_length() - 1])
        digits = shorter
        zeros += 1
    if zeros == 0:
        return Float64(digits)
    return Float64(digits + "e" + String(zeros))


def test_texts_match_v8() raises:
    var text = String(
        StringSlice(
            unsafe_from_utf8=open("assets/js_number/v8.json", "r").read_bytes()
        )
    )
    var doc = parse_json(text)
    var root = doc.root()
    for c in range(doc.length(root)):
        var entry = doc.at(root, c)
        var value = _from_hex(doc.string(doc.get(entry, "bits")))
        assert_equal(js_number_text(value), doc.string(doc.get(entry, "text")))
        assert_equal(
            js_to_precision(value, 7), doc.string(doc.get(entry, "p7"))
        )
        assert_equal(
            js_to_precision(value, 1), doc.string(doc.get(entry, "p1"))
        )
        assert_equal(
            js_to_precision(value, 21), doc.string(doc.get(entry, "p21"))
        )
        assert_equal(js_to_fixed(value, 7), doc.string(doc.get(entry, "f7")))
        assert_equal(js_to_fixed(value, 0), doc.string(doc.get(entry, "f0")))
        var f20 = doc.get(entry, "f20")
        if not doc.is_null(f20):
            assert_equal(js_to_fixed(value, 20), doc.string(f20))
        var f32 = doc.get(entry, "f32")
        if doc.is_null(f32):
            assert_equal(
                js_float32_text(Float32(value)),
                js_number_text(Float64(Float32(value))),
            )
        else:
            # The shortest text that reads back: at a tie of two, either.
            var mine = js_float32_text(Float32(value))
            assert_equal(mine.byte_length(), doc.string(f32).byte_length())
            assert_equal(Float32(_read(mine)), Float32(value))


def test_srgb_to_linear() raises:
    # The ends, and V8's double for 0x12, whose last digit Mojo's `pow`
    # and the C library's both get wrong.
    assert_equal(srgb_to_linear(0), 0)
    assert_equal(srgb_to_linear(255), 1)
    assert_equal(js_number_text(srgb_to_linear(0x12)), "0.0060488330203860696")
    # Below 0.04045 it is a straight line.
    assert_equal(srgb_to_linear(10), Float64(10) / 255 * 0.0773993808)


def test_ranges() raises:
    with assert_raises(contains="from 1 to 100"):
        _ = js_to_precision(1, 0)
    with assert_raises(contains="from 1 to 100"):
        _ = js_to_precision(1, 101)
    with assert_raises(contains="from 0 to 100"):
        _ = js_to_fixed(1, -1)
    with assert_raises(contains="from 0 to 100"):
        _ = js_to_fixed(1, 101)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
