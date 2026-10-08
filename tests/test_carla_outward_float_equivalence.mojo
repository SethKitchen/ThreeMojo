# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Native parity with the frozen original outward conversion graph."""

from extensions.carla.junction_bounds import _outward_float
from std.math import inf, isfinite, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _reference_outward_float(value: Float64, lower: Bool) raises -> Float32:
    var result = Float32(value)
    if not isfinite(result):
        raise Error(
            "Junction canonical enclosure is not finite in public storage"
        )
    if (lower and Float64(result) > value) or (
        not lower and Float64(result) < value
    ):
        if result == 0.0:
            return bitcast[DType.float32](
                UInt32(0x80000001) if lower else UInt32(1)
            )
        var bits = bitcast[DType.uint32](result)
        if (result > 0.0) == lower:
            bits -= 1
        else:
            bits += 1
        result = bitcast[DType.float32](bits)
        if not isfinite(result):
            raise Error(
                "Junction canonical enclosure is not finite in public storage"
            )
    return result


def _same(value: Float64, lower: Bool) raises:
    var original: Optional[UInt32] = None
    var candidate: Optional[UInt32] = None
    try:
        original = bitcast[DType.uint32](_reference_outward_float(value, lower))
    except:
        pass
    try:
        candidate = bitcast[DType.uint32](_outward_float(value, lower))
    except:
        pass
    assert_equal(Bool(original), Bool(candidate))
    if original:
        assert_equal(original.value(), candidate.value())


def test_all_float32_exponent_strata_and_adjacent_float64_words() raises:
    for exponent in range(255):
        for mantissa in [UInt32(0), 1, 0x3FFFFF, 0x7FFFFF]:
            for sign in [UInt32(0), 0x80000000]:
                var word = sign | (UInt32(exponent) << 23) | mantissa
                var value = Float64(bitcast[DType.float32](word))
                var promoted = bitcast[DType.uint64](value)
                for lower in [False, True]:
                    _same(value, lower)
                    if promoted > 0:
                        _same(bitcast[DType.float64](promoted - 1), lower)
                    if promoted < UInt64.MAX:
                        _same(bitcast[DType.float64](promoted + 1), lower)


def test_signed_zero_subnormal_and_halfway_neighbors() raises:
    for value in [Float64(0), -0.0, 1e-320, -1e-320, 1e-45, -1e-45]:
        for lower in [False, True]:
            _same(value, lower)
    var one = bitcast[DType.uint64](Float64(1))
    for offset in [UInt64(0x0FFFFFFF), 0x10000000, 0x10000001]:
        for lower in [False, True]:
            _same(bitcast[DType.float64](one + offset), lower)
            _same(-bitcast[DType.float64](one + offset), lower)


def test_initial_and_adjacent_step_nonfinite_refusals_match() raises:
    for value in [
        inf[DType.float64](),
        -inf[DType.float64](),
        nan[DType.float64](),
    ]:
        assert_false(isfinite(Float32(value)))
        for lower in [False, True]:
            _same(value, lower)
            with assert_raises(contains="not finite in public storage"):
                _ = _outward_float(value, lower)
    var maximum = Float64(bitcast[DType.float32](UInt32(0x7F7FFFFF)))
    var beyond = bitcast[DType.float64](bitcast[DType.uint64](maximum) + 1)
    assert_true(isfinite(Float32(beyond)))
    assert_equal(bitcast[DType.uint32](Float32(beyond)), UInt32(0x7F7FFFFF))
    _same(beyond, False)
    _same(-beyond, True)
    with assert_raises(contains="not finite in public storage"):
        _ = _outward_float(beyond, False)
    with assert_raises(contains="not finite in public storage"):
        _ = _outward_float(-beyond, True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
