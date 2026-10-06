# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Measure adaptive predicate timings and requested runtime allocations.

Run without arguments for native timings. For separate allocation evidence,
build bench/navigation_allocations.c as a shared library, preload it with
LD_PRELOAD, and pass the same path as the first argument. The hook checks
itself before measurement. It measures the pinned Mojo runtime allocator
on the current thread, not C allocations, stack memory, or process RSS.
Unhooked zero allocation counters mean unmeasured. Hooked timings are only
diagnostic. Inputs, hook setup, printing, and checks stay outside each
measurement. Every sample is no-inline and consumes its varying index.

Modes 0 and 1 exercise certified ordinary orientation and tolerance filters.
Modes 2 and 3 force exact fallback after overflowing interval differences.
Mode 4 compares distances whose rounded normalized planes are identical.
Mode 5 exercises full-span exact normal estimation. Mode 6 covers exact
segment ranking. Mode 7 covers all remaining ordering APIs on full-span
inputs. The workload count is the number of predicate calls for modes 0-6,
and the number of eight-call groups for mode 7. Mode 8 measures the
certified ordinary normal estimate.
"""

from math.exact_predicates import (
    _Dyadic,
    _absolute_plane_distance_compare,
    _collinear,
    _difference_compare,
    _line_distance_compare,
    _normal_estimate,
    _orient3d,
    _plane_above,
    _plane_distance_compare,
    _same_plane_absolute_distance_compare,
    _same_plane_distance_compare,
    _segment_distance_compare,
)
from std.ffi import OwnedDLHandle
from std.memory import bitcast
from std.sys import argv, size_of
from std.testing import assert_equal
from std.time import perf_counter_ns

comptime _P = SIMD[DType.float64, 4]


@no_inline
def _sample(mode: Int, index: Int) -> Int:
    if mode < 2:
        var shift = Float64(index % 97)
        var a = _P(shift, 0, 0, 0)
        var b = _P(shift + 1, 0, 0, 0)
        var c = _P(shift, 1, 0, 0)
        var p = _P(shift + 0.25, 0.25, Float64(1 + index % 3), 0)
        if mode == 0:
            return _orient3d(a, b, c, p)
        return Int(_plane_above(a, b, c, p, 0.25))
    if mode == 8:
        var shift = Float64(index % 97) / 128
        var a = _P(shift, 0.125, 0.375, 0)
        var b = _P(-0.5, 0.5, 0.25, 0)
        var c = _P(0.75, 0.25, -0.125, 0)
        var normal = _normal_estimate(a, b, c)
        return Int(normal[0] * 1024)
    var h = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var t = bitcast[DType.float64](UInt64(1 + index % 7))
    var a = _P(h, t, 0, 0)
    var b = _P(-h, 0, t, 0)
    var c = _P(0, h, -t, 0)
    var p = _P(t, -h, h, 0)
    var q = _P(-t, h, -h, 0)
    if mode == 2:
        return _orient3d(a, b, c, p)
    if mode == 3:
        return Int(_plane_above(a, c, b, p, t))
    if mode == 4:
        var origin = _P(0, 0, 0, 0)
        var x = _P(h, 0, 0, 0)
        var y = _P(0, h, 0, 0)
        var tilted = _P(0, h, t, 0)
        var point = _P(0, 0, h, 0)
        return _plane_distance_compare(
            origin, x, y, point, origin, x, tilted, point
        )
    if mode == 5:
        var normal = _normal_estimate(a, b, c)
        return Int(normal[0] < 0) + Int(normal[1] < 0) + Int(normal[2] < 0)
    if mode == 6:
        return _segment_distance_compare(a, b, p, q)
    return (
        _absolute_plane_distance_compare(a, b, c, p, c, b, p, q)
        + _same_plane_distance_compare(a, b, c, p, q)
        + _same_plane_absolute_distance_compare(a, b, c, p, q)
        + _line_distance_compare(a, b, p, q)
        + _difference_compare(h, t, h, 0)
        + Int(_collinear(a, b, c))
        + _orient3d(a, b, c, a)
        + Int(_plane_above(a, b, c, a, t))
    )


@no_inline
def _run(mode: Int, count: Int) -> Int:
    var checksum = 0
    for index in range(count):
        checksum += _sample(mode, index)
    return checksum


def main() raises:
    var args = argv()
    var hooked = len(args) > 1
    var library = OwnedDLHandle(
        String(args[1]) if hooked else String("libc.so.6")
    )
    if hooked:
        assert_equal(
            library.call["navigation_allocations_selftest", UInt64](), 1
        )
        # Resolve symbols before enabling the meter. This also proves the
        # zero counters below come from a working interception path.
        _ = library.call["navigation_allocations_end", UInt64]()
        _ = library.call["navigation_allocations_total", UInt64]()
        _ = library.call["navigation_allocations_calls", UInt64]()
        _ = library.call["navigation_allocations_overflow", UInt64]()
    print("dyadic_bytes", size_of[_Dyadic](), sep=",")
    print(
        "trial,mode,count,nanoseconds,peak_requested_bytes,total_requested_bytes,allocations,hooked,checksum"
    )
    for trial in range(5):
        for mode in range(9):
            var count = 10000 if mode < 2 or mode == 8 else 200
            _ = _run(mode, 1)
            if hooked:
                _ = library.call["navigation_allocations_begin", UInt64]()
            var start = perf_counter_ns()
            var checksum = _run(mode, count)
            var elapsed = perf_counter_ns() - start
            var peak = UInt64(0)
            var total = UInt64(0)
            var calls = UInt64(0)
            if hooked:
                peak = library.call["navigation_allocations_end", UInt64]()
                total = library.call["navigation_allocations_total", UInt64]()
                calls = library.call["navigation_allocations_calls", UInt64]()
                assert_equal(
                    library.call["navigation_allocations_overflow", UInt64](), 0
                )
                assert_equal(peak, 0)
                assert_equal(total, 0)
                assert_equal(calls, 0)
            print(
                trial,
                mode,
                count,
                elapsed,
                peak,
                total,
                calls,
                hooked,
                checksum,
                sep=",",
            )
