# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""CPU witnesses for the exact Float32-only scaled-product successor."""

from math.norm import (
    length2,
    length3,
    length4,
    normalized2,
    normalized3,
    normalized4,
    reciprocal_normalized3,
)
from math.scaled_products import _split
from std.math import frexp, inf, isnan, ldexp, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def _check_subnormal(significand: UInt32) raises:
    # Construct the reference directly from the integer significand. Every
    # result is normal Binary64; the oracle never consumes or widens the
    # Float32 subnormal whose device flush behavior is under test.
    for sign in [UInt32(0), UInt32(0x80000000)]:
        var value = bitcast[DType.float32](sign | significand)
        var reference = ldexp(Float64(significand), Int32(-149))
        if sign != 0:
            reference = -reference
        var expected = frexp(reference)
        for offset in [-19, 0, 23]:
            var actual = _split(value, offset)
            assert_equal(
                bitcast[DType.uint32](actual.fraction),
                bitcast[DType.uint32](Float32(expected[0])),
            )
            assert_equal(actual.exponent, Int(expected[1]) + offset)


def test_signed_subnormal_boundaries_and_spread_match_binary64() raises:
    _check_subnormal(UInt32(1))
    _check_subnormal(UInt32(0x7FFFFF))
    for top in range(23):
        var power = UInt32(1) << UInt32(top)
        _check_subnormal(power)
        if power > 1:
            _check_subnormal(power - 1)
        if power < UInt32(0x7FFFFF):
            _check_subnormal(power + 1)
    for index in range(1, 8192):
        _check_subnormal(UInt32(index))
        _check_subnormal(UInt32(index * 1023))


def test_float32_normal_and_zero_paths_keep_prior_bits_and_exponents() raises:
    for bits in [
        UInt32(0),
        UInt32(0x80000000),
        UInt32(0x00800000),
        UInt32(0x80800000),
        UInt32(0x3F800000),
        UInt32(0xBF800000),
        UInt32(0x7F7FFFFF),
        UInt32(0xFF7FFFFF),
    ]:
        var value = bitcast[DType.float32](bits)
        var expected = frexp(value)
        var actual = _split(value, 7)
        assert_equal(
            bitcast[DType.uint32](actual.fraction),
            bitcast[DType.uint32](expected[0]),
        )
        assert_equal(actual.exponent, Int(expected[1]) + 7)


def test_float32_nonfinite_path_replays_prior_frexp_fallback() raises:
    # _split accepts finite inputs. Its nonfinite fallback is unchanged,
    # but pinned frexp does not promise NaN or infinity output classes.
    for bits in [
        UInt32(0x7F800000),
        UInt32(0xFF800000),
        UInt32(0x7FC00000),
        UInt32(0xFFC00000),
        UInt32(0x7F812345),
        UInt32(0xFF812345),
    ]:
        var value = bitcast[DType.float32](bits)
        for offset in [-19, 0, 23]:
            var actual = _split(value, offset)
            var expected = frexp(value)
            assert_equal(
                bitcast[DType.uint32](actual.fraction),
                bitcast[DType.uint32](expected[0]),
            )
            assert_equal(actual.exponent, Int(expected[1]) + offset)


def test_float64_keeps_the_complete_prior_fraction_and_exponent() raises:
    # The new branch is eliminated for Float64. Replay the original finite
    # arithmetic directly, with subnormal, normal and signed-zero inputs.
    for bits in [
        UInt64(0),
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x8000000000000001),
        UInt64(0x000FFFFFFFFFFFFF),
        UInt64(0x800FFFFFFFFFFFFF),
        UInt64(0x0010000000000000),
        UInt64(0x8010000000000000),
        UInt64(0x3FF0000000000000),
        UInt64(0xBFF0000000000000),
        UInt64(0x7FEFFFFFFFFFFFFF),
        UInt64(0xFFEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](bits)
        for offset in [-19, 0, 23]:
            var actual = _split(value, offset)
            var expected = frexp(value)
            var exponent = Int(expected[1]) + offset
            if value != 0 and abs(value) < Float64(2.2250738585072014e-308):
                expected = frexp(value * ldexp(Float64(1), Int32(512)))
                exponent = Int(expected[1]) + offset - 512
            assert_equal(
                bitcast[DType.uint64](actual.fraction),
                bitcast[DType.uint64](expected[0]),
            )
            assert_equal(actual.exponent, exponent)


def test_float64_nonfinite_path_replays_prior_frexp_fallback() raises:
    # Compare both fallback fields, without imposing private class rules.
    for bits in [
        UInt64(0x7FF0000000000000),
        UInt64(0xFFF0000000000000),
        UInt64(0x7FF8000000000000),
        UInt64(0xFFF8000000000000),
        UInt64(0x7FF0123456789ABC),
        UInt64(0xFFF0123456789ABC),
    ]:
        var value = bitcast[DType.float64](bits)
        for offset in [-19, 0, 23]:
            var actual = _split(value, offset)
            var expected = frexp(value)
            assert_equal(
                bitcast[DType.uint64](actual.fraction),
                bitcast[DType.uint64](expected[0]),
            )
            assert_equal(actual.exponent, Int(expected[1]) + offset)


def _check_public_nonfinite_norms[dtype: DType]() raises:
    # Public norm contracts are independent of private _split behavior.
    comptime assert dtype == DType.float32 or dtype == DType.float64
    var zero = SIMD[dtype, 1](0)
    var one = SIMD[dtype, 1](1)
    var two = SIMD[dtype, 1](2)
    var three = SIMD[dtype, 1](3)
    var infinite = inf[dtype]()
    var invalid = nan[dtype]()

    for signed_infinite in [infinite, -infinite]:
        assert_equal(length2(signed_infinite, one), infinite)
        assert_equal(length3(one, signed_infinite, -two), infinite)
        assert_equal(length4(one, -two, signed_infinite, three), infinite)
        var n2 = normalized2(signed_infinite, -two)
        var n3 = normalized3(one, signed_infinite, -two)
        var n4 = normalized4(one, -two, signed_infinite, three)
        assert_true(isnan(n2[0]))
        assert_equal(n2[1], zero)
        assert_equal(n3[0], zero)
        assert_true(isnan(n3[1]))
        assert_equal(n3[2], zero)
        assert_equal(n4[0], zero)
        assert_equal(n4[1], zero)
        assert_true(isnan(n4[2]))
        assert_equal(n4[3], zero)
        var reciprocal = reciprocal_normalized3(one, signed_infinite, -two)
        assert_equal(reciprocal[0], zero)
        assert_true(isnan(reciprocal[1]))
        assert_equal(reciprocal[2], zero)

    assert_true(isnan(length2(invalid, one)))
    assert_true(isnan(length3(one, invalid, -two)))
    assert_true(isnan(length4(one, -two, invalid, three)))
    assert_true(isnan(length2(infinite, invalid)))
    assert_true(isnan(length3(invalid, infinite, -two)))
    assert_true(isnan(length4(one, invalid, infinite, three)))

    # A NaN squared norm leaves all normalized input components unchanged.
    var n2 = normalized2(invalid, -two)
    var n3 = normalized3(one, invalid, -two)
    var n4 = normalized4(one, -two, invalid, three)
    assert_true(isnan(n2[0]))
    assert_equal(n2[1], -two)
    assert_equal(n3[0], one)
    assert_true(isnan(n3[1]))
    assert_equal(n3[2], -two)
    assert_equal(n4[0], one)
    assert_equal(n4[1], -two)
    assert_true(isnan(n4[2]))
    assert_equal(n4[3], three)

    n3 = normalized3(infinite, invalid, -two)
    assert_equal(n3[0], infinite)
    assert_true(isnan(n3[1]))
    assert_equal(n3[2], -two)

    # Reciprocal normalization retains its direct IEEE arithmetic policy.
    var reciprocal = reciprocal_normalized3(one, invalid, -two)
    assert_true(isnan(reciprocal[0]))
    assert_true(isnan(reciprocal[1]))
    assert_true(isnan(reciprocal[2]))


def test_public_float32_norm_nonfinite_contracts() raises:
    _check_public_nonfinite_norms[DType.float32]()


def test_public_float64_norm_nonfinite_contracts() raises:
    _check_public_nonfinite_norms[DType.float64]()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
