# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Real CARLA log playback with hand-calculated gait intervals, issue #290."""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.actor import ActorId, WALKER_ACTOR
from extensions.carla.recorder import Recorder
from extensions.carla.recorder_packets import (
    LogVector,
    RecordedAnimWalker,
    RecordedEventDel,
    RecorderFrame,
)
from extensions.carla.render_actors import ActorVisuals
from extensions.carla.replayer import Replayer
from extensions.carla.walker_gait import WalkerGait
from math.vector3 import Vector3
from std.math import exp, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_recorder import _add, _pos, _zero
from tests.test_carla_world import _world
from units.si import DEGREE, SECOND, TURN, Duration


def _log(
    first_speed: Float32 = 150, remove: Bool = False, bad_frame: Int = -1
) raises -> List[UInt8]:
    var recorder = Recorder()
    _ = recorder.begin("", "Town", False, 0)
    recorder.events_add.append(
        _add(
            50,
            WALKER_ACTOR,
            LogVector(2000, -450, 106),
            _zero(),
            15,
            "walker.pedestrian.0015",
        )
    )
    for k in range(6):
        var speed = first_speed
        if k == 1:
            speed = 300
        elif k == 2:
            speed = 0
        if k == bad_frame:
            speed = -1
        if remove and k == 3:
            recorder.events_del.append(RecordedEventDel(ActorId(50)))
        recorder.positions.append(
            _pos(50, LogVector(2000 + Float64(k) * 25, -450, 106), _zero())
        )
        recorder.walkers.append(RecordedAnimWalker(ActorId(50), speed))
        recorder.write_frame(0.25, Float64(k) * 0.25, 0)
    return recorder.bytes()


def _same(a: WalkerGait, b: WalkerGait) raises:
    assert_almost_equal(a.phase().value, b.phase().value, atol=1e-6)
    assert_almost_equal(a.amplitude().value, b.amplitude().value, atol=1e-6)


def test_partial_cross_frame_and_seek_reconstruct_same_gait() raises:
    var world = _world()
    var replay = Replayer()
    _ = replay.replay_bytes(world, _log(), "gait")
    var walker = replay.mapped(ActorId(50))
    assert_equal(world.get_walker_gait(walker).swing().value, 0)
    replay.tick(world, Duration(0.1, SECOND))
    replay.tick(world, Duration(0.3, SECOND))
    var gait = world.get_walker_gait(walker)
    # 0.25 s at 1.5 m/s plus 0.15 s at 3 m/s is 0.55 cycle.
    assert_almost_equal(gait.phase().to(TURN), 0.55, atol=1e-6)
    var amplitude = 18 * (1 - exp(Float64(-0.25 / 0.15)))
    amplitude = 30 + (amplitude - 30) * exp(Float64(-1))
    assert_almost_equal(
        Float64(gait.amplitude().to(DEGREE)), amplitude, atol=1e-5
    )
    replay.tick(world, Duration(0.25, SECOND))
    gait = world.get_walker_gait(walker)
    assert_almost_equal(gait.phase().to(TURN), 0.75, atol=1e-6)
    amplitude = 30 + (18 * (1 - exp(Float64(-0.25 / 0.15))) - 30) * exp(
        Float64(-0.25 / 0.15)
    )
    assert_almost_equal(
        Float64(gait.amplitude().to(DEGREE)),
        amplitude * exp(Float64(-1)),
        atol=1e-5,
    )
    var sought_world = _world()
    var sought = Replayer()
    _ = sought.replay_bytes(
        sought_world, _log(), "seek", Duration(0.65, SECOND)
    )
    _same(gait, sought_world.get_walker_gait(sought.mapped(ActorId(50))))
    var jump_world = _world()
    var jump = Replayer()
    _ = jump.replay_bytes(jump_world, _log(), "jump")
    jump.tick(jump_world, Duration(0.65, SECOND))
    _same(gait, jump_world.get_walker_gait(jump.mapped(ActorId(50))))
    # Reuse the same replayer: history is rebuilt, not added to the old gait.
    _ = replay.replay_bytes(world, _log(), "again", Duration(0.65, SECOND))
    _same(gait, world.get_walker_gait(replay.mapped(ActorId(50))))


def test_step_tick_pause_capture_and_stop_continuity() raises:
    var a = _world()
    var b = _world()
    var replay_a = Replayer()
    var replay_b = Replayer()
    _ = replay_a.replay_bytes(a, _log(), "step")
    _ = replay_b.replay_bytes(b, _log(), "tick")
    var id_a = replay_a.mapped(ActorId(50))
    var id_b = replay_b.mapped(ActorId(50))
    var scene = Scene()
    var assets = Assets()
    var visuals = ActorVisuals()
    for _ in range(7):
        _ = replay_a.step(a)
        _ = b.tick()
        replay_b.tick(b, Duration(0.05, SECOND))
        visuals.sync(a, scene, assets)
        visuals.sync(a, scene, assets)
        _same(a.get_walker_gait(id_a), b.get_walker_gait(id_b))
    var before = a.get_walker_gait(id_a)
    var displayed = scene.node(visuals.walkers[0].limbs[0]).quaternion.z
    replay_a.set_time_factor(0)
    _ = replay_a.step(a)
    _same(before, a.get_walker_gait(id_a))
    visuals.sync(a, scene, assets)
    assert_equal(
        scene.node(visuals.walkers[0].limbs[0]).quaternion.z, displayed
    )
    replay_a.tick(a, Duration(0, SECOND))
    _same(before, a.get_walker_gait(id_a))
    replay_a.stop(a, True)
    _same(before, a.get_walker_gait(id_a))
    a.set_target_velocity(id_a, Vector3(0, 0, 0))
    _ = a.tick()
    assert_equal(a.get_walker_gait(id_a).phase().value, before.phase().value)
    assert_true(
        a.get_walker_gait(id_a).amplitude().value < before.amplitude().value
    )
    assert_false(replay_a.is_enabled())
    # A stopped replayer cannot overwrite a later live pose.
    before = a.get_walker_gait(id_a)
    replay_a.tick(a, Duration(1, SECOND))
    _same(before, a.get_walker_gait(id_a))


def test_replay_destroy_and_early_stop_do_not_leave_control_state() raises:
    var world = _world()
    var replay = Replayer()
    _ = replay.replay_bytes(world, _log(remove=True), "gone")
    var walker = replay.mapped(ActorId(50))
    replay.tick(world, Duration(0.6, SECOND))
    _ = world.destroy_actor(walker)
    replay.tick(world, Duration(0.1, SECOND))
    replay.tick(world, Duration(0.1, SECOND))
    assert_false(world.is_alive(walker))
    assert_equal(len(replay._walker_gaits), 0)
    assert_equal(len(replay._walker_speeds), 0)
    replay.stop(world)
    assert_false(replay.is_enabled())
    _ = replay.replay_bytes(world, _log(), "fresh")
    var fresh = replay.mapped(ActorId(50))
    assert_true(fresh != walker)
    assert_equal(world.get_walker_gait(fresh).amplitude().value, 0)
    replay.tick(world, Duration(0.1, SECOND))
    var before = world.get_walker_gait(fresh)
    replay.stop(world)
    _same(before, world.get_walker_gait(fresh))


def test_invalid_playback_time_and_speed_do_not_publish_bad_gait() raises:
    var world = _world()
    var replay = Replayer()
    _ = replay.replay_bytes(world, _log(), "valid")
    var walker = replay.mapped(ActorId(50))
    replay.tick(world, Duration(0.1, SECOND))
    var before = world.get_walker_gait(walker)
    for value in [-Float32(1), inf[DType.float32](), nan[DType.float32]()]:
        with assert_raises(contains="time advance"):
            replay.tick(world, Duration(value, SECOND))
        _same(before, world.get_walker_gait(walker))
    replay.current_time = 1e308
    replay.time_factor = 1e308
    with assert_raises(contains="remain finite"):
        replay.tick(world, Duration(1, SECOND))
    _same(before, world.get_walker_gait(walker))
    replay.current_time = 0.1
    replay.time_factor = 1
    replay.frame = RecorderFrame(1, 1e308, 1e308)
    with assert_raises(contains="replay frame"):
        replay.tick(world, Duration(0, SECOND))
    replay.frame = RecorderFrame(1, -2, 0)
    with assert_raises(contains="replay frame"):
        replay.tick(world, Duration(0, SECOND))
    _same(before, world.get_walker_gait(walker))
    # Failed setup can leave ordinary actors, but no persistent gait owner.
    var invalid = Replayer()
    var bad_world = _world()
    with assert_raises(contains="speed"):
        _ = invalid.replay_bytes(bad_world, _log(first_speed=-1), "invalid")
    var bad_id = invalid.mapped(ActorId(50))
    assert_equal(bad_world.get_walker_gait(bad_id).amplitude().value, 0)
    _ = bad_world.tick()
    assert_equal(bad_world.get_walker_gait(bad_id).amplitude().value, 0)


def test_two_replayers_and_changed_hero_policy_keep_other_gaits() raises:
    var world = _world()
    var first = Replayer()
    var second = Replayer()
    _ = first.replay_bytes(world, _log(), "first")
    var a = first.mapped(ActorId(50))
    _ = second.replay_bytes(world, _log(), "second")
    var b = second.mapped(ActorId(50))
    assert_true(a != b)
    first.tick(world, Duration(0.2, SECOND))
    var pose_a = world.get_walker_gait(a)
    second.tick(world, Duration(0.4, SECOND))
    _same(pose_a, world.get_walker_gait(a))
    var pose_b = world.get_walker_gait(b)
    first.stop(world, True)
    _same(pose_b, world.get_walker_gait(b))
    second.tick(world, Duration(0, SECOND))
    _same(pose_b, world.get_walker_gait(b))
    # The public hero option can change while a replay is active.
    second.is_hero_map[b.value] = True
    second.set_ignore_hero(True)
    _ = world.tick()
    var live = world.get_walker_gait(b)
    second.tick(world, Duration(0.2, SECOND))
    _same(live, world.get_walker_gait(b))
    # A record mapped to a nonwalker must not index a walker record.
    second.mapped_id[50] = world.get_spectator().value
    second.tick(world, Duration(0.2, SECOND))


def test_mid_record_failure_disables_replay_until_restart() raises:
    var world = _world()
    var replay = Replayer()
    _ = replay.replay_bytes(world, _log(bad_frame=1), "bad later frame")
    var walker = replay.mapped(ActorId(50))
    replay.tick(world, Duration(0.1, SECOND))
    var before = world.get_walker_gait(walker)
    with assert_raises(contains="speed"):
        replay.tick(world, Duration(0.3, SECOND))
    assert_false(replay.is_enabled())
    _same(before, world.get_walker_gait(walker))
    # The partially read frame must not silently resume with stale speed.
    replay.tick(world, Duration(0.1, SECOND))
    _same(before, world.get_walker_gait(walker))
    _ = world.tick()
    assert_true(
        world.get_walker_gait(walker).phase().value > before.phase().value
    )
    _ = replay.replay_bytes(world, _log(), "recovered")
    var fresh = replay.mapped(ActorId(50))
    assert_equal(world.get_walker_gait(fresh).amplitude().value, 0)
    replay.tick(world, Duration(0.1, SECOND))
    assert_true(world.get_walker_gait(fresh).amplitude().value > 0)


def test_step_rejects_bad_timing_before_world_tick() raises:
    var world = _world()
    var replay = Replayer()
    _ = replay.replay_bytes(world, _log(), "timing")
    var walker = replay.mapped(ActorId(50))
    var frame = world.frame
    var before = world.get_walker_gait(walker)
    replay.set_time_factor(-1)
    with assert_raises(contains="time advance"):
        _ = replay.step(world)
    assert_equal(world.frame, frame)
    _same(before, world.get_walker_gait(walker))
    assert_true(replay.is_enabled())
    replay.set_time_factor(1)
    # A missing fixed step is still the world's own validation error.
    world.settings.fixed_delta_seconds = None
    with assert_raises(contains="fixed_delta_seconds"):
        _ = replay.step(world)
    assert_equal(world.frame, frame)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
