# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact Float64 time in lane invasion events and sensor measurements."""

from extensions.carla.lane_invasion import LaneInvasionEvent
from extensions.carla.road_info import LaneMarking
from extensions.carla.sensor_manager import (
    GNSS,
    SensorManager,
    SensorMeasurement,
)
from std.math import inf, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises
from tests.test_carla_world import _pose, _world
from units.si import Duration64


def _encodings() -> List[UInt64]:
    # IEEE-754 encodings are the independent reference. A Float32 step
    # cannot keep the low bits of the large values or the tiny ones.
    return [
        UInt64(0x419D6F3454000043),
        UInt64(0x4270000000000200),
        UInt64(0x3FF0000000000001),
        UInt64(0x2B2BFF2EE48E0530),
        UInt64(1),
        UInt64(0),
        UInt64(0x8000000000000000),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]


def _bad() -> List[Float64]:
    return [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        Float64(-0.5),
        -Float64(5e-324),
    ]


def test_lane_invasion_event_keeps_float64_bits() raises:
    for bits in _encodings():
        var seconds = bitcast[DType.float64](bits)
        var event = LaneInvasionEvent(
            4, Duration64(seconds), _pose(1, 2, 3, 0), List[LaneMarking]()
        )
        var elapsed: Duration64 = event.elapsed()
        assert_equal(bitcast[DType.uint64](elapsed.value), bits)
        assert_equal(bitcast[DType.uint64](event.timestamp), bits)
        assert_equal(event.frame, 4)


def test_lane_invasion_event_tiny_step_at_large_time() raises:
    # One microsecond after about 3.9 years survives in both events.
    var start = 123456789.000001
    var first = LaneInvasionEvent(
        1, Duration64(start), _pose(0, 0, 0, 0), List[LaneMarking]()
    )
    var second = LaneInvasionEvent(
        2, Duration64(start + 1.0e-6), _pose(0, 0, 0, 0), List[LaneMarking]()
    )
    assert_equal(
        second.elapsed().value - first.elapsed().value,
        (start + 1.0e-6) - start,
    )
    assert_equal(Float32(start + 1.0e-6), Float32(start))


def test_lane_invasion_event_refuses_invalid_time() raises:
    for bad in _bad():
        with assert_raises(contains="lane invasion time"):
            _ = LaneInvasionEvent(
                1, Duration64(bad), _pose(0, 0, 0, 0), List[LaneMarking]()
            )
        # The raw field is mutable; the typed view checks it before use.
        var event = LaneInvasionEvent(
            1, Duration64(0.25), _pose(0, 0, 0, 0), List[LaneMarking]()
        )
        event.timestamp = bad
        with assert_raises(contains="lane invasion time"):
            _ = event.elapsed()


def _header_seconds(header: List[UInt8]) -> UInt64:
    # The header holds the type, the frame, then the Float64 time, all
    # little-endian.
    var bits = UInt64(0)
    for i in range(8):
        bits |= UInt64(header[16 + i]) << UInt64(8 * i)
    return bits


def test_measurement_time_round_trips_through_its_header() raises:
    var world = _world()
    var manager = SensorManager()
    var gnss = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.gnss"), _pose(0, 0, 0, 0)
    )
    for bits in _encodings():
        if bitcast[DType.float64](bits) < 0:
            continue
        world.elapsed_seconds = bitcast[DType.float64](bits)
        var measurement = SensorMeasurement(world, gnss, GNSS)
        assert_equal(bitcast[DType.uint64](measurement.elapsed().value), bits)
        assert_equal(_header_seconds(measurement.header), bits)
    for bad in _bad():
        world.elapsed_seconds = bad
        with assert_raises(contains="measurement time"):
            _ = SensorMeasurement(world, gnss, GNSS)
    world.elapsed_seconds = 0.5
    var measurement = SensorMeasurement(world, gnss, GNSS)
    for bad in _bad():
        measurement.timestamp = bad
        with assert_raises(contains="measurement time"):
            _ = measurement.elapsed()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
