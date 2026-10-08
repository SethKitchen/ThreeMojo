# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact cache word comparisons through the engine's actual helper."""

from extensions.carla.lane_refinement import _same_cache_key
from std.testing import TestSuite, assert_equal


def test_cache_key_both_equal() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000002),
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000002),
        ),
        True,
    )


def test_cache_key_station_only() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000002),
            UInt64(0x0000000000000003),
            UInt64(0x0000000000000002),
        ),
        False,
    )


def test_cache_key_scale_only() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000002),
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000003),
        ),
        False,
    )


def test_cache_key_both_mismatch() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000002),
            UInt64(0x0000000000000003),
            UInt64(0x0000000000000004),
        ),
        False,
    )


def test_cache_key_high_bits_equal() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0xFFFFFFFFFFFFFFFF),
            UInt64(0x8000000000000000),
            UInt64(0xFFFFFFFFFFFFFFFF),
            UInt64(0x8000000000000000),
        ),
        True,
    )


def test_cache_key_high_station_mismatch() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0xFFFFFFFFFFFFFFFF),
            UInt64(0x8000000000000000),
            UInt64(0x7FFFFFFFFFFFFFFF),
            UInt64(0x8000000000000000),
        ),
        False,
    )


def test_cache_key_high_scale_mismatch() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x8000000000000000),
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000000),
        ),
        False,
    )


def test_cache_key_signed_zero_station() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000000),
            UInt64(0x0000000000000001),
            UInt64(0x8000000000000000),
            UInt64(0x0000000000000001),
        ),
        False,
    )


def test_cache_key_signed_zero_scale() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x0000000000000000),
            UInt64(0x0000000000000001),
            UInt64(0x8000000000000000),
        ),
        False,
    )


def test_cache_key_nan_same_bits() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x7FF8000000000001),
            UInt64(0xFFF8000000000002),
            UInt64(0x7FF8000000000001),
            UInt64(0xFFF8000000000002),
        ),
        True,
    )


def test_cache_key_nan_station_payload() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x7FF8000000000001),
            UInt64(0x0000000000000001),
            UInt64(0x7FF8000000000002),
            UInt64(0x0000000000000001),
        ),
        False,
    )


def test_cache_key_nan_scale_payload() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x7FF8000000000001),
            UInt64(0x0000000000000001),
            UInt64(0x7FF8000000000002),
        ),
        False,
    )


def test_cache_key_nan_quiet_signaling() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x7FF8000000000001),
            UInt64(0x0000000000000001),
            UInt64(0x7FF0000000000001),
            UInt64(0x0000000000000001),
        ),
        False,
    )


def test_cache_key_nan_sign_difference() raises:
    assert_equal(
        _same_cache_key(
            UInt64(0x0000000000000001),
            UInt64(0x7FF8000000000001),
            UInt64(0x0000000000000001),
            UInt64(0xFFF8000000000001),
        ),
        False,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
