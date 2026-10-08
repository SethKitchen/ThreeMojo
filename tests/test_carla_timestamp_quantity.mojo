# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact Float64 timestamp boundaries and mutable-record refusal controls."""

from extensions.carla.world_snapshot import Timestamp, WorldSnapshot
from std.math import inf, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Duration64


def test_timestamp_preserves_independent_float64_bits() raises:
    # IEEE-754 encodings are the independent reference. No Float32 conversion
    # can retain the low bits of the large value or the two tiny values.
    var encodings: List[UInt64] = [
        UInt64(0x4270000000000200),
        UInt64(0x3FF0000000000001),
        UInt64(0x2B2BFF2EE48E0530),
        UInt64(1),
        UInt64(0),
        UInt64(0x8000000000000000),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]
    for bits in encodings:
        var seconds = bitcast[DType.float64](bits)
        var stamp = Timestamp(
            7, Duration64(seconds), Duration64(seconds), Duration64(seconds)
        )
        var elapsed: Duration64 = stamp.elapsed()
        var delta: Duration64 = stamp.delta()
        var platform: Duration64 = stamp.platform()
        assert_equal(bitcast[DType.uint64](elapsed.value), bits)
        assert_equal(bitcast[DType.uint64](delta.value), bits)
        assert_equal(bitcast[DType.uint64](platform.value), bits)
        assert_equal(bitcast[DType.uint64](stamp.elapsed_seconds), bits)
        assert_equal(bitcast[DType.uint64](stamp.delta_seconds), bits)
        assert_equal(bitcast[DType.uint64](stamp.platform_timestamp), bits)
        var record = Timestamp.from_seconds(7, seconds, seconds, seconds)
        assert_equal(bitcast[DType.uint64](record.elapsed().value), bits)
        assert_equal(bitcast[DType.uint64](record.delta().value), bits)
        assert_equal(bitcast[DType.uint64](record.platform().value), bits)


def test_timestamp_signed_platform_and_unchanged_record_semantics() raises:
    var stamp = Timestamp(
        3, Duration64(1.5), Duration64(0.5), Duration64(-12.25)
    )
    assert_equal(stamp.platform().value, Float64(-12.25))
    assert_true(stamp == Timestamp.from_seconds(3, 0, 0, 1))
    assert_true(stamp != Timestamp.from_seconds(4, 1.5, 0.5, 0))
    assert_equal(
        String(stamp),
        "Timestamp(frame=3,elapsed_seconds=1.5,delta_seconds=0.5,platform_timestamp=-12.25)",
    )
    var snapshot = WorldSnapshot(1, stamp)
    assert_equal(snapshot.frame(), 3)
    assert_equal(snapshot.timestamp.elapsed().value, Float64(1.5))
    assert_equal(snapshot.size(), 0)


def test_timestamp_construction_checks_domains() raises:
    for bad in [
        Float64(-1),
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        with assert_raises(contains="elapsed"):
            _ = Timestamp(0, Duration64(bad), Duration64(0), Duration64(0))
        with assert_raises(contains="delta"):
            _ = Timestamp.from_seconds(0, 0, bad, 0)
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        with assert_raises(contains="platform"):
            _ = Timestamp.from_seconds(0, 0, 0, bad)
    with assert_raises(contains="frame"):
        _ = Timestamp.from_seconds(-1, 0, 0, 0)


def test_timestamp_mutation_is_checked_before_runtime_use() raises:
    var stamp = Timestamp.from_seconds(1, 2, 0.5, -3)
    stamp.elapsed_seconds = nan[DType.float64]()
    with assert_raises(contains="elapsed"):
        _ = stamp.elapsed()
    with assert_raises(contains="elapsed"):
        _ = WorldSnapshot(1, stamp)
    stamp.elapsed_seconds = 2
    stamp.delta_seconds = -1
    with assert_raises(contains="delta"):
        _ = stamp.delta()
    with assert_raises(contains="delta"):
        _ = WorldSnapshot(1, stamp)
    stamp.delta_seconds = 0.5
    stamp.platform_timestamp = inf[DType.float64]()
    with assert_raises(contains="platform"):
        _ = stamp.platform()
    with assert_raises(contains="platform"):
        _ = WorldSnapshot(1, stamp)
    stamp.platform_timestamp = -3
    stamp.frame = -1
    with assert_raises(contains="frame"):
        stamp.check()
    assert_equal(stamp.elapsed_seconds, Float64(2))
    assert_equal(stamp.delta_seconds, Float64(0.5))
    assert_equal(stamp.platform_timestamp, Float64(-3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
