# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Integer source epochs retain their signed range, low bits and sentinels.

A Unix recorder date and a CAM epoch offset are absolute source-format
counters. They must not pass through Float32 or Float64 quantities.
"""

from extensions.carla.actor import ActorId
from extensions.carla.recorder import Recorder, now_seconds
from extensions.carla.recorder_packets import LogReader, RecorderInfo
from extensions.carla.sensor_data import ByteWriter
from extensions.carla.sensor_manager import SensorManager
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.v2x import CaService, CamNoise
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from tests.test_carla_sensors_world import _car, _world
from units.si import Duration


def _epochs() -> List[Int]:
    # The two large odd values cannot round-trip through Float64.
    return [
        0,
        1,
        65535,
        65536,
        9007199254740993,
        9223372036854775807,
        -1,
        -2,
        -9007199254740993,
        -9223372036854775807 - 1,
    ]


def test_recorder_header_keeps_all_signed_i64_date_bits() raises:
    for date in _epochs():
        var original = RecorderInfo(1, "CARLA_RECORDER", date, "epoch")
        var writer = ByteWriter()
        original.write(writer)
        var reader = LogReader(writer^.finish())
        var restored = RecorderInfo.read(reader)
        assert_equal(restored.date, date)
        assert_equal(restored.version, 1)
        assert_equal(restored.map_file, "epoch")


def test_named_recorder_date_retains_nonnegative_range_and_negative_aliases() raises:
    var recorder = Recorder()
    for date in _epochs():
        var before = now_seconds()
        _ = recorder.begin_unix_seconds("", "epoch", False, date)
        var reader = LogReader(recorder.bytes())
        var restored = RecorderInfo.read(reader)
        if date >= 0:
            assert_equal(restored.date, date)
        else:
            # Preserve the source behavior: every negative value selects now.
            assert_true(restored.date >= before)
            assert_true(restored.date <= now_seconds())
    recorder.stop()


def test_recorder_default_and_world_epoch_routes() raises:
    var world = _world()
    var recorder = Recorder()
    var before = now_seconds()
    _ = recorder.begin("", "default")
    var reader = LogReader(recorder.bytes())
    assert_true(RecorderInfo.read(reader).date >= before)
    _ = recorder.start(world, "", "default")
    reader = LogReader(recorder.bytes())
    assert_true(RecorderInfo.read(reader).date >= before)
    _ = recorder.start_unix_seconds(world, "", "exact", False, 9007199254740993)
    reader = LogReader(recorder.bytes())
    assert_equal(RecorderInfo.read(reader).date, 9007199254740993)
    recorder.stop()


def test_sensor_manager_epoch_adapter_keeps_every_int() raises:
    var ordinary = SensorManager()
    assert_equal(ordinary.generation_delta0, 0)
    for epoch in _epochs():
        var manager = SensorManager.from_cam_epoch_milliseconds(epoch)
        assert_equal(manager.generation_delta0, epoch)
        assert_equal(len(manager.slots), 0)


def test_cam_epoch_adapter_keeps_exact_storage_and_modulo_encoding() raises:
    var world = _world()
    var car = _car(world, 10, 1.75)
    var ordinary = CaService(
        world, car, Duration(0.1), Duration(1), True, CamNoise()
    )
    assert_equal(ordinary.generation_delta0, 0)
    world.elapsed_seconds = 0
    for epoch in _epochs():
        var service = CaService.from_cam_epoch_milliseconds(
            world, car, Duration(0.1), Duration(1), True, CamNoise(), epoch
        )
        assert_equal(service.generation_delta0, epoch)
        var rng = SensorRandom(0)
        var projection = world.map.geo_projection.copy()
        var message = service.trigger(
            world, projection, Duration(0.05), rng
        ).value()
        # Integer modulo is independent of any floating-point conversion.
        assert_equal(message.generation_delta_time, epoch % 65536)


def test_epoch_adapter_retains_typed_interval_and_owner_validation() raises:
    var world = _world()
    var car = _car(world, 10, 1.75)
    with assert_raises():
        _ = CaService.from_cam_epoch_milliseconds(
            world,
            car,
            Duration(0),
            Duration(1),
            True,
            CamNoise(),
            9007199254740993,
        )
    with assert_raises():
        _ = CaService.from_cam_epoch_milliseconds(
            world, car, Duration(2), Duration(1), True, CamNoise(), 0
        )
    with assert_raises():
        _ = CaService.from_cam_epoch_milliseconds(
            world, ActorId(-1), Duration(0.1), Duration(1), True, CamNoise(), 0
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
