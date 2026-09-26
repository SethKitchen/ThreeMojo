# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.js_text`: text as JavaScript's UTF-16 code units."""

from loaders.js_text import is_js_space, js_part, js_string, js_trim, js_units
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_a_string_is_held_as_javascript_holds_it() raises:
    # One unit each below U+10000, and a surrogate pair above it.
    var text = "a" + chr(0xE9) + chr(0xFFFD) + chr(0x1F600) + "z"
    var units = js_units(text)
    assert_equal(len(units), 6)
    assert_equal(units[2], 0xFFFD)
    assert_equal(units[3], 0xD83D)
    assert_equal(units[4], 0xDE00)
    assert_equal(js_string(units, 0, len(units)), text)
    assert_equal(js_string(units, 3, 5), chr(0x1F600))
    assert_equal(len(js_part(units, 1, 3)), 2)


def test_white_space_is_javascript_s() raises:
    for unit in [9, 13, 32, 0xA0, 0x2000, 0x200A, 0x2028, 0xFEFF]:
        assert_true(is_js_space(unit))
    for unit in [8, 14, 0x1FFF, 0x200B, 65]:
        assert_false(is_js_space(unit))
    var trimmed = js_trim(js_units(chr(0x3000) + " x y\t" + chr(0x205F)))
    assert_equal(js_string(trimmed, 0, len(trimmed)), "x y")
    assert_equal(len(js_trim(js_units("  "))), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
