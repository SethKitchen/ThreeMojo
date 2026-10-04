# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Destroyed sensor bookkeeping must not change recording identities."""

from extensions.carla.actor import NO_ACTOR
from extensions.carla.recorder import Recorder
from extensions.carla.recorder_packets import (
    PACKET_COLLISION,
    PACKET_EVENT_ADD,
    PACKET_EVENT_DEL,
    RecordedCollision,
    RecordedEventAdd,
    RecordedEventDel,
)
from extensions.carla.replayer import Replayer
from extensions.physics.world import CollisionEvent
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from test_carla_recorder_world import (
    _find,
    _hero,
    _packets,
    _pose,
    _reader_at,
    _spawn,
    _world,
)
from test_scratch import TestScratch


def test_destroyed_sensor_keeps_survivor_state_and_queued_records() raises:
    var world = _world()
    var car = _hero(world, _pose(20, 1.75, 0.6, 0))
    var other = _spawn(world, "vehicle.mini.cooper", _pose(100, 1.75, 0.6, 0))
    var gone = _spawn(world, "sensor.other.collision", _pose(0, 0, 0, 0), car)
    var survivor = _spawn(
        world, "sensor.other.collision", _pose(0, 0, 0, 0), car
    )
    var recorder = Recorder()
    _ = recorder.start(world, "", "Town", False, 0)
    _ = world.tick()
    # An explicit event avoids depending on contact solver timing.
    world.physics.events = [
        CollisionEvent(
            world.actor(car).body,
            world.actor(other).body,
            Vector3(1, 0, 0),
        ),
    ]
    recorder.record(world)
    assert_equal(len(recorder._sensors), 2)
    var frame = recorder._sensors[survivor.value].frame
    var reported = recorder._sensors[survivor.value].reported.copy()
    assert_equal(len(reported), 1)
    assert_equal(reported[0], world.actor(other).body.value)
    var queued_id = recorder.next_collision_id
    recorder.add_collision(world, car, other)
    assert_true(world.destroy_actor(gone))
    # Same world frame: the survivor must retain its per-frame dedup state.
    recorder.record(world)
    assert_equal(len(recorder._sensors), 1)
    assert_false(gone.value in recorder._sensors)
    assert_equal(recorder._sensors[survivor.value].frame, frame)
    assert_equal(recorder._sensors[survivor.value].reported, reported)
    # Recreating the survivor would consume another collision id even if
    # the queued pair suppressed the duplicate output record.
    assert_equal(recorder.next_collision_id, queued_id + 1)
    var bytes = recorder.bytes()
    var packets = _packets(bytes)
    var deletion = _find(packets, 2, PACKET_EVENT_DEL.value)
    var collision = _find(packets, 2, PACKET_COLLISION.value)
    assert_true(deletion.start < collision.start)
    var deleted = _reader_at(bytes, deletion)
    assert_equal(deleted.u16(), 1)
    assert_equal(RecordedEventDel.read(deleted).database_id, gone)
    var hits = _reader_at(bytes, collision)
    assert_equal(hits.u16(), 1)
    var hit = RecordedCollision.read(hits)
    assert_equal(hit.id, queued_id)
    assert_equal(hit.database_id1, car)
    assert_equal(hit.database_id2, other)
    assert_true(hit.is_actor1_hero)
    assert_false(hit.is_actor2_hero)
    assert_false(world.destroy_actor(gone))
    recorder.record(world)
    var repeated = recorder.bytes()
    packets = _packets(repeated)
    # The format keeps empty packets; only their record counts must be zero.
    var repeated_deleted = _reader_at(
        repeated, _find(packets, 3, PACKET_EVENT_DEL.value)
    )
    assert_equal(repeated_deleted.u16(), 0)
    var repeated_hits = _reader_at(
        repeated, _find(packets, 3, PACKET_COLLISION.value)
    )
    assert_equal(repeated_hits.u16(), 0)
    assert_equal(recorder.next_collision_id, queued_id + 1)
    assert_equal(len(recorder._sensors), 1)
    # The surviving sensor still collects that pair on the next world frame.
    _ = world.tick()
    world.physics.events = [
        CollisionEvent(
            world.actor(car).body,
            world.actor(other).body,
            Vector3(1, 0, 0),
        ),
    ]
    var next_id = recorder.next_collision_id
    recorder.record(world)
    assert_equal(recorder._sensors[survivor.value].frame, world.frame)
    assert_equal(recorder._sensors[survivor.value].reported, reported)
    assert_equal(recorder.next_collision_id, next_id + 1)
    bytes = recorder.bytes()
    packets = _packets(bytes)
    hits = _reader_at(bytes, _find(packets, 4, PACKET_COLLISION.value))
    assert_equal(hits.u16(), 1)
    hit = RecordedCollision.read(hits)
    assert_equal(hit.id, next_id)
    assert_equal(hit.database_id1, car)
    assert_equal(hit.database_id2, other)


def test_sensor_destroyed_before_first_capture_keeps_add_delete_order() raises:
    var world = _world()
    var car = _hero(world, _pose(20, 1.75, 0.6, 0))
    var sensor = _spawn(world, "sensor.other.collision", _pose(0, 0, 0, 0), car)
    var recorder = Recorder()
    _ = recorder.start(world, "", "Town", False, 0)
    assert_equal(len(recorder._sensors), 0)
    assert_true(world.destroy_actor(sensor))
    _ = recorder.tick(world)
    assert_equal(len(recorder._sensors), 0)
    var bytes = recorder.bytes()
    var packets = _packets(bytes)
    var add_packet = _find(packets, 1, PACKET_EVENT_ADD.value)
    var delete_packet = _find(packets, 1, PACKET_EVENT_DEL.value)
    assert_true(add_packet.start < delete_packet.start)
    var added = _reader_at(bytes, add_packet)
    var count = added.u16()
    var found = False
    for _ in range(count):
        if RecordedEventAdd.read(added).database_id == sensor:
            found = True
    assert_true(found)
    var deleted = _reader_at(bytes, delete_packet)
    assert_equal(deleted.u16(), 1)
    assert_equal(RecordedEventDel.read(deleted).database_id, sensor)


def test_sensor_registry_count_plateaus_during_recording() raises:
    var world = _world()
    var car = _hero(world, _pose(20, 1.75, 0.6, 0))
    var survivor = _spawn(
        world, "sensor.other.collision", _pose(0, 0, 0, 0), car
    )
    var recorder = Recorder()
    _ = recorder.start(world, "", "Town", False, 0)
    _ = recorder.tick(world)
    for _ in range(32):
        var sensor = _spawn(
            world, "sensor.other.collision", _pose(0, 0, 0, 0), car
        )
        _ = recorder.tick(world)
        assert_equal(len(recorder._sensors), 2)
        assert_true(world.destroy_actor(sensor))
        _ = recorder.tick(world)
        assert_equal(len(recorder._sensors), 1)
        assert_true(survivor.value in recorder._sensors)
        assert_false(sensor.value in recorder._sensors)
    # Recorded output and the world's actor table intentionally still grow.
    assert_true(len(recorder.bytes()) > 0)


def test_sensor_deletion_replays_with_its_original_recorded_id() raises:
    var world = _world()
    var car = _hero(world, _pose(20, 1.75, 0.6, 0))
    var recorder = Recorder()
    _ = recorder.start(world, "", "Town", False, 0)
    # Newly observed sensors emit parent packets in the first capture.
    var gone = _spawn(world, "sensor.other.collision", _pose(0, 0, 0, 0), car)
    var survivor = _spawn(
        world, "sensor.other.collision", _pose(0, 0, 0, 0), car
    )
    _ = recorder.tick(world)
    assert_true(world.destroy_actor(gone))
    _ = recorder.tick(world)
    _ = recorder.tick(world)
    assert_equal(len(recorder._sensors), 1)
    var target = _world()
    _ = _spawn(target, "walker.pedestrian.0015", _pose(120, -4, 1.2, 0))
    var replay = Replayer()
    _ = replay.replay_bytes(
        target, recorder.bytes(), "sensor-cleanup", replay_sensors=True
    )
    var mapped_gone = replay.mapped(gone)
    var mapped_survivor = replay.mapped(survivor)
    var mapped_car = replay.mapped(car)
    assert_true(mapped_gone != NO_ACTOR)
    assert_true(mapped_survivor != NO_ACTOR)
    assert_true(mapped_gone != gone)
    assert_equal(target.actor(mapped_gone).parent, mapped_car)
    assert_equal(target.actor(mapped_survivor).parent, mapped_car)
    _ = replay.step(target)
    assert_equal(replay.mapped(gone), NO_ACTOR)
    assert_false(target.is_alive(mapped_gone))
    assert_equal(replay.mapped(survivor), mapped_survivor)
    assert_true(target.is_alive(mapped_survivor))
    assert_equal(target.actor(mapped_survivor).parent, mapped_car)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
