# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact-rational controls for remainders, signs, ranges, and periodic waves."""

from math.remainder import remainder_float64
from math.utils import euclidean_modulo, pingpong
from std.math import inf, nan
from std.memory import bitcast
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true


def test_float32_rational_controls_for_all_exponents_and_signs() raises:
    var text = Path("assets/math_remainder/periodic32.txt").read_text()
    for line in text.splitlines():
        var fields = line.split(" ")
        var n_bits = UInt32(Int(fields[0]))
        var m_bits = UInt32(Int(fields[1]))
        for n_sign in [UInt32(0), UInt32(0x80000000)]:
            for m_sign in [UInt32(0), UInt32(0x80000000)]:
                var n = bitcast[DType.float32](n_bits | n_sign)
                var m = bitcast[DType.float32](m_bits | m_sign)
                var opposite = n_sign != m_sign and n_bits != 0
                var column = 3 if opposite else 2
                var expected = UInt32(Int(fields[column])) | m_sign
                assert_equal(
                    bitcast[DType.uint32](euclidean_modulo(n, m)), expected
                )
                var wave_column = 4 if m_sign == 0 else 5
                assert_equal(
                    bitcast[DType.uint32](pingpong(n, m)),
                    UInt32(Int(fields[wave_column])),
                )


def test_float64_exact_rational_controls_for_all_exponents_and_signs() raises:
    var text = Path("assets/math_remainder/remainder64.txt").read_text()
    for line in text.splitlines():
        var fields = line.split(" ")
        var n_bits = UInt64(Int(fields[0]))
        var m_bits = UInt64(Int(fields[1]))
        var expected = UInt64(Int(fields[2]))
        for n_sign in [UInt64(0), UInt64(0x8000000000000000)]:
            for m_sign in [UInt64(0), UInt64(0x8000000000000000)]:
                var n = bitcast[DType.float64](n_bits | n_sign)
                var m = bitcast[DType.float64](m_bits | m_sign)
                assert_equal(
                    bitcast[DType.uint64](remainder_float64(n, m)),
                    expected | n_sign,
                )


def test_remainder_fast_path_boundary_and_extreme_scaling() raises:
    # Fraction controls immediately below, at, and above a/b == 2,
    # plus the largest exponent scale and the subnormal output quantum.
    var cases: List[Tuple[Int, Int, Int]] = [
        (0x3FFFFFFFFFFFFFFF, 0x3FF0000000000000, 0x3FEFFFFFFFFFFFFE),
        (0x4000000000000000, 0x3FF0000000000000, 0x0000000000000000),
        (0x4000000000000001, 0x3FF0000000000000, 0x3CC0000000000000),
        (0x7FEFFFFFFFFFFFFF, 0x7FD8000000000000, 0x7FCFFFFFFFFFFFFC),
        (0x7FEFFFFFFFFFFFFF, 0x0010000000000001, 0x0000000000060000),
        (0x000FFFFFFFFFFFFF, 0x0000000000000003, 0x0000000000000000),
        (0x0000000000000001, 0x0000000000000001, 0x0000000000000000),
        (0x0000000000000002, 0x0000000000000001, 0x0000000000000000),
        (0x0000000000000003, 0x0000000000000001, 0x0000000000000000),
    ]
    for row in cases:
        for sign in [UInt64(0), UInt64(0x8000000000000000)]:
            assert_equal(
                bitcast[DType.uint64](
                    remainder_float64(
                        bitcast[DType.float64](UInt64(row[0]) | sign),
                        bitcast[DType.float64](UInt64(row[1])),
                    )
                ),
                UInt64(row[2]) | sign,
            )


def test_ordinary_three_js_values_and_reported_counterexamples() raises:
    assert_equal(euclidean_modulo(4, 1.5), Float32(1))
    assert_equal(euclidean_modulo(-1, 3), Float32(2))
    assert_equal(euclidean_modulo(1, -3), Float32(-2))
    assert_equal(euclidean_modulo(-1, -3), Float32(-1))
    assert_equal(pingpong(1.5), Float32(0.5))
    assert_equal(pingpong(-1.5), Float32(0.5))
    assert_equal(pingpong(0, -1), Float32(-2))
    assert_equal(pingpong(1, -1), Float32(-1))
    var large = bitcast[DType.float32](UInt32(0x71800000))
    assert_equal(euclidean_modulo(large, 1.5), Float32(1))
    assert_equal(pingpong(large, 0.75), Float32(0.5))
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var tiny = bitcast[DType.float32](UInt32(1))
    # The old unconditional add-divisor step overflows or erases tiny n.
    assert_equal(euclidean_modulo(largest / 2, largest), largest / 2)
    assert_equal(euclidean_modulo(tiny, 1), tiny)
    assert_equal(
        bitcast[DType.uint32](euclidean_modulo(-tiny, 1)), UInt32(0x3F7FFFFF)
    )
    # The mathematical positive wave stays finite even when 2*length
    # cannot fit Float32. A small phase must survive the final fold.
    assert_equal(pingpong(1, largest), Float32(1))
    assert_equal(pingpong(tiny, 1), tiny)
    assert_equal(pingpong(tiny * 3, tiny), tiny)
    assert_equal(pingpong(1, -largest), -inf[DType.float32]())


def test_exceptional_operands_and_signed_zero_contracts() raises:
    var infinity = inf[DType.float32]()
    var not_a_number = nan[DType.float32]()
    for invalid in [infinity, -infinity, not_a_number]:
        var dividend = euclidean_modulo(invalid, 1)
        var divisor = euclidean_modulo(1, invalid)
        var wave_input = pingpong(invalid, 1)
        var wave_length = pingpong(1, invalid)
        assert_true(dividend != dividend)
        assert_true(divisor != divisor)
        assert_true(wave_input != wave_input)
        assert_true(wave_length != wave_length)
    for zero in [Float32(0), bitcast[DType.float32](UInt32(0x80000000))]:
        var modulo = euclidean_modulo(1, zero)
        var wave = pingpong(1, zero)
        assert_true(modulo != modulo)
        assert_true(wave != wave)
        assert_equal(
            bitcast[DType.uint32](euclidean_modulo(zero, 3)), UInt32(0)
        )
        assert_equal(
            bitcast[DType.uint32](euclidean_modulo(zero, -3)),
            UInt32(0x80000000),
        )
        assert_equal(bitcast[DType.uint32](pingpong(zero)), UInt32(0))
    for invalid in [
        inf[DType.float64](),
        -inf[DType.float64](),
        nan[DType.float64](),
    ]:
        var remainder = remainder_float64(invalid, 1)
        assert_true(remainder != remainder)
    for invalid in [Float64(0), Float64(-0.0), nan[DType.float64]()]:
        var remainder = remainder_float64(1, invalid)
        assert_true(remainder != remainder)
    for sign in [UInt64(0), UInt64(0x8000000000000000)]:
        var zero = bitcast[DType.float64](sign)
        assert_equal(bitcast[DType.uint64](remainder_float64(zero, 1)), sign)
        assert_equal(bitcast[DType.uint64](remainder_float64(zero, -1)), sign)
        for divisor in [inf[DType.float64](), -inf[DType.float64]()]:
            assert_equal(
                bitcast[DType.uint64](remainder_float64(zero, divisor)), sign
            )
            assert_equal(remainder_float64(3, divisor), Float64(3))
            assert_equal(remainder_float64(-3, divisor), Float64(-3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
