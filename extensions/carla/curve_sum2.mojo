# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Stored-term Sum2 accumulation and its uniform scalar-error bound.

The call boundary materializes each Float64 input before TwoSum. No global
floating-point mode changes. The bound describes the rounded sum of these
stored terms, not an exact clothoid or an unrounded dot product.
"""

from extensions.carla.curve_interval import _Interval
from std.math import inf, isfinite
from std.memory import bitcast, stack_allocation


@no_inline
def _sum2_update(
    total: Float64, correction: Float64, term: Float64
) -> Tuple[Float64, Float64]:
    # Knuth TwoSum. The six separately rounded additions/subtractions recover
    # the exact residual of total + term, including gradual underflow.
    var high = total + term
    var virtual_term = high - total
    var virtual_total = high - virtual_term
    var total_error = total - virtual_total
    var term_error = term - virtual_term
    var residual = total_error + term_error
    return (high, correction + residual)


@no_inline
def _sum2_supported_environment() -> Bool:
    # Volatile word loads are an invocation-local compiler barrier. They
    # prevent constant folding or cross-call reuse of these arithmetic probes.
    # No process/thread FP control mode is changed or success cached.
    # Like ordinary arithmetic, the probes can set sticky exception flags.
    var one_slot = stack_allocation[1, UInt64]()
    var half_slot = stack_allocation[1, UInt64]()
    var tiny_slot = stack_allocation[1, UInt64]()
    one_slot[unsafe_offset=0] = UInt64(0x3FF0000000000000)
    half_slot[unsafe_offset=0] = UInt64(0x3CA0000000000000)
    tiny_slot[unsafe_offset=0] = UInt64(1)
    var one_word = one_slot.unsafe_load[volatile=True]()
    var one = bitcast[DType.float64](one_word)
    var half = bitcast[DType.float64](half_slot.unsafe_load[volatile=True]())
    var tiny = bitcast[DType.float64](tiny_slot.unsafe_load[volatile=True]())
    var even = _sum2_update(one, 0.0, half)
    var odd = _sum2_update(
        bitcast[DType.float64](one_word + UInt64(1)), 0.0, half
    )
    if bitcast[DType.uint64](even[0]) != UInt64(0x3FF0000000000000) or bitcast[
        DType.uint64
    ](odd[0]) != UInt64(0x3FF0000000000002):
        return False
    var first = _sum2_update(one, 0.0, tiny)
    var last = _sum2_update(first[0], first[1], -one)
    # Compare words: DAZ can make a floating comparison treat eta as zero.
    return bitcast[DType.uint64](last[0] + last[1]) == UInt64(1)


def _require_sum2_environment() raises:
    if not _sum2_supported_environment():
        raise Error(
            "Canonical lane arithmetic requires round-to-nearest and gradual"
            " underflow"
        )


def _sum2_error(magnitude: Float64, inherited: Float64, count: Int) -> Float64:
    if not _sum2_supported_environment():
        return inf[DType.float64]()
    return _sum2_error_checked(magnitude, inherited, count)


def _sum2_error_checked(
    magnitude: Float64, inherited: Float64, count: Int
) -> Float64:
    # Caller has checked the FP environment for this invocation.
    # For every point in the complete input domain, magnitude bounds the sum
    # of absolute stored terms and inherited bounds their total input error.
    # Sum2: |computed - exact sum(stored terms)| <= u*|sum| + gamma_(n-1)^2*M.
    # We conservatively use |sum| <= M. The guarded range keeps the ordinary
    # partial sum, correction and every TwoSum subtraction below overflow.
    if (
        count < 1
        or count > 1073741824
        or not isfinite(magnitude)
        or magnitude < 0.0
        or magnitude > 8.452712498170644e270
        or not isfinite(inherited)
        or inherited < 0.0
    ):
        return inf[DType.float64]()
    if magnitude == 0.0:
        return inherited
    if count == 1:
        return inherited
    var u = _Interval.point(1.1102230246251565e-16)
    var nu = _Interval.point(Float64(count - 1)) * u
    var gamma = nu / (_Interval.point(1.0) - nu)
    return (
        _Interval.point(inherited)
        + (u + gamma * gamma) * _Interval.point(magnitude)
    ).high
