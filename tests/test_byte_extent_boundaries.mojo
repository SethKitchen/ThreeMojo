# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Byte predicates bound indices; extent checks keep separate duties."""

from core.extent import (
    positive_extent,
    require_positive_extent,
    require_texel_count,
)
from loaders.bytes import ascii_space_at, ascii_digit_at, js_float_byte_at
from std.testing import TestSuite, assert_false, assert_true, assert_raises


def test_byte_predicates_refuse_indices_outside_the_span() raises:
    var text = " 7e!"
    var bytes = text.as_bytes()
    for at in [Int.MIN, -1, len(bytes), len(bytes) + 1]:
        assert_false(ascii_space_at(bytes, at))
        assert_false(ascii_digit_at(bytes, at))
        assert_false(js_float_byte_at(bytes, at))
    var empty = ""
    var empty_bytes = empty.as_bytes()
    for at in [Int.MIN, -1, 0, 1]:
        assert_false(ascii_space_at(empty_bytes, at))
        assert_false(ascii_digit_at(empty_bytes, at))
        assert_false(js_float_byte_at(empty_bytes, at))


def test_byte_predicates_keep_valid_index_classification() raises:
    var text = " 7e!"
    var bytes = text.as_bytes()
    assert_true(ascii_space_at(bytes, 0))
    assert_false(ascii_space_at(bytes, 1))
    assert_false(ascii_digit_at(bytes, 0))
    assert_true(ascii_digit_at(bytes, 1))
    assert_false(js_float_byte_at(bytes, 0))
    assert_true(js_float_byte_at(bytes, 1))
    assert_true(js_float_byte_at(bytes, 2))
    assert_false(ascii_space_at(bytes, 3))
    assert_false(ascii_digit_at(bytes, 3))
    assert_false(js_float_byte_at(bytes, 3))


def test_extent_positivity_checks_each_size_separately() raises:
    assert_true(positive_extent(4, 4))
    assert_true(positive_extent(4, 4, 4))
    for bad in [0, -4]:
        assert_false(positive_extent(bad, 4))
        assert_false(positive_extent(4, bad))
        assert_false(positive_extent(4, 4, bad))
    assert_false(positive_extent(-4, -4))
    with assert_raises(contains="positive sizes first"):
        require_positive_extent(-4, -4, "positive sizes first")
    require_positive_extent(4, 4, "positive sizes first")


def test_texel_count_only_checks_the_product() raises:
    require_texel_count(16, 4, 4, 1, "length mismatch")
    require_texel_count(64, 4, 4, 4, "length mismatch")
    # Positivity is a separate check, even when two signs cancel.
    require_texel_count(16, -4, -4, 1, "length mismatch")
    with assert_raises(contains="length mismatch"):
        require_texel_count(15, 4, 4, 1, "length mismatch")


def test_positive_size_error_precedes_length_error() raises:
    with assert_raises(contains="positive sizes first"):
        require_positive_extent(-4, -4, "positive sizes first")
        require_texel_count(15, -4, -4, 1, "length mismatch")
    with assert_raises(contains="length mismatch"):
        require_positive_extent(4, 4, "positive sizes first")
        require_texel_count(15, 4, 4, 1, "length mismatch")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
