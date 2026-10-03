# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bit controls for reusing identical pure directed endpoint operations."""
from extensions.carla.curve_interval import (
    _Interval,
    _directed_endpoint_product,
    _directed_endpoint_quotient,
    _tight_product_bound,
    _tight_quotient_bound,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def _original_product(one: _Interval, two: _Interval) -> _Interval:
    return (
        _directed_endpoint_product(one.low, two.low)
        .hull(_directed_endpoint_product(one.low, two.high))
        .hull(_directed_endpoint_product(one.high, two.low))
        .hull(_directed_endpoint_product(one.high, two.high))
    )


def _original_quotient(one: _Interval, two: _Interval) -> _Interval:
    if two.contains(0.0):
        return _Interval.whole()
    return (
        _directed_endpoint_quotient(one.low, two.low)
        .hull(_directed_endpoint_quotient(one.low, two.high))
        .hull(_directed_endpoint_quotient(one.high, two.low))
        .hull(_directed_endpoint_quotient(one.high, two.high))
    )


def _boxes() -> List[_Interval]:
    var words: List[UInt64] = [
        0,
        UInt64(0x8000000000000000),
        1,
        UInt64(0x8000000000000001),
        UInt64(0x000FFFFFFFFFFFFF),
        UInt64(0x0010000000000000),
        UInt64(0x8010000000000000),
        UInt64(0x26EFFFFFFFFFFFFF),
        UInt64(0x26F0000000000000),
        UInt64(0x26F0000000000001),
        UInt64(0x3FEFFFFFFFFFFFFF),
        UInt64(0x3FF0000000000000),
        UInt64(0x3FF0000000000001),
        UInt64(0xBFF0000000000000),
        UInt64(0x58EFFFFFFFFFFFFF),
        UInt64(0x58F0000000000000),
        UInt64(0x58F0000000000001),
        UInt64(0x7FEFFFFFFFFFFFFF),
        UInt64(0xFFEFFFFFFFFFFFFF),
        UInt64(0x7FF0000000000000),
        UInt64(0xFFF0000000000000),
        UInt64(0x7FF8000000000001),
    ]
    var result = List[_Interval]()
    for i in range(len(words)):
        var first = bitcast[DType.float64](words[i])
        var second = bitcast[DType.float64](words[(i + 1) % len(words)])
        result.append(_Interval.point(first))
        result.append(_Interval.point(first).hull(_Interval.point(second)))
    result.append(_Interval(-0.0, 0.0))
    result.append(_Interval(-1.0, 1.0))
    return result^


def _same_bits(one: _Interval, two: _Interval) raises:
    assert_equal(bitcast[DType.uint64](one.low), bitcast[DType.uint64](two.low))
    assert_equal(
        bitcast[DType.uint64](one.high), bitcast[DType.uint64](two.high)
    )


def test_product_endpoint_reuse_matches_four_pair_reference_bits() raises:
    var boxes = _boxes()
    var checked = 0
    for one in boxes:
        for two in boxes:
            _same_bits(
                _tight_product_bound(one, two), _original_product(one, two)
            )
            checked += 1
    assert_equal(checked, 2116)


def test_quotient_endpoint_reuse_matches_four_pair_reference_bits() raises:
    var boxes = _boxes()
    var checked = 0
    for one in boxes:
        for two in boxes:
            _same_bits(
                _tight_quotient_bound(one, two), _original_quotient(one, two)
            )
            checked += 1
    assert_equal(checked, 2116)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
