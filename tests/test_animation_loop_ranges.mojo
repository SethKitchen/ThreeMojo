# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact dyadic animation counts, phase boundaries, and atomic range errors."""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import (
    AnimationAction,
    AnimationMixer,
    AnimationEvent,
    FINISHED,
    LOOPED,
    ONCE,
    REPEAT,
    PING_PONG,
    Loop,
)
from animation.keyframe_track import KeyframeTrack, POSITION
from cameras.camera_list import CameraList
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from std.math import inf, nan
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)
from units.si import Duration, SECOND


def _clip(length: Float32 = 1.5) raises -> AnimationClip:
    return AnimationClip(
        "counted",
        [
            KeyframeTrack(
                NodeId(0),
                POSITION,
                [Duration(0, SECOND), Duration(length, SECOND)],
                [Float32(0), 0, 0, 1, 0, 0],
            )
        ],
    )


def _number(text: StringSlice) raises -> Float32:
    return bitcast[DType.float32](UInt32(Int(text)))


def test_exact_fraction_controls() raises:
    var rows = Path("assets/animation/loop_reference.txt").read_text()
    for row in rows.splitlines():
        var fields = row.split(" ")
        var action = AnimationAction(
            _clip(_number(fields[0])),
            Loop(Int(fields[4])),
            time_scale=_number(fields[3]),
            clamp_when_finished=True,
        )
        action.play()
        action.phase = _number(fields[1])
        if Int(fields[5]) >= 0:
            action.set_loop(Loop(Int(fields[4])), Int(fields[5]))
        action.started = Int(fields[6]) != 0
        action.loop_count = Int(fields[7])
        action.loop_delta = 17
        action.just_finished = True
        var seconds = _number(fields[2])
        if Int(fields[8]) != 0:
            with assert_raises():
                action.advance(seconds)
        else:
            action.advance(seconds)
        assert_equal(
            bitcast[DType.uint32](action.phase), UInt32(Int(fields[9]))
        )
        assert_equal(action.loop_delta, Int(fields[10]))
        assert_equal(action.loop_count, Int(fields[11]))
        assert_equal(action.started, Int(fields[12]) != 0)
        assert_equal(action.just_finished, Int(fields[13]) != 0)
        assert_equal(action.direction, Int(fields[14]))
        assert_equal(action.paused, Int(fields[15]) != 0)
        assert_true(action.active)


def test_confirmed_large_jump_and_event_agree() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(_clip()))
    mixer.action(which).play()
    mixer.update(scene, Duration(33554432, SECOND))
    assert_equal(mixer.action(which).phase, Float32(0.5))
    assert_equal(mixer.action(which).loop_count, 22369621)
    var events = mixer.drain_events()
    assert_equal(len(events), 1)
    assert_equal(events[0].kind, LOOPED)
    assert_equal(events[0].loop_delta, 22369621)
    assert_equal(events[0].direction, 1)


def test_finite_huge_jump_finishes_without_loop_event() raises:
    for loop in [REPEAT, PING_PONG]:
        for scale in [Float32(1), Float32(-1)]:
            var scene = Scene()
            _ = scene.add(Object3D())
            var mixer = AnimationMixer()
            var action = AnimationAction(_clip(1), loop, time_scale=scale)
            action.set_loop(loop, Int.MAX)
            action.clamp_when_finished = True
            var which = mixer.add(action^)
            mixer.action(which).play()
            mixer.update(
                scene,
                Duration(bitcast[DType.float32](UInt32(0x71800000)), SECOND),
            )
            var events = mixer.drain_events()
            assert_equal(len(events), 1)
            assert_equal(events[0].kind, FINISHED)
            assert_equal(events[0].loop_delta, 0)
            assert_equal(events[0].direction, -1 if scale < 0 else 1)
            assert_equal(mixer.action(which).loop_count, -1)
            assert_false(mixer.action(which).started)
            assert_true(mixer.action(which).paused)


def test_unsupported_update_preserves_all_action_timing_and_events() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var mixer = AnimationMixer()
    var first = mixer.add(AnimationAction(_clip()))
    var second = mixer.add(AnimationAction(_clip()))
    mixer.action(first).play()
    mixer.action(second).play()
    mixer.update(scene, Duration(1.5, SECOND))
    var maximum = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    mixer.action(second).set_effective_time_scale(maximum)
    mixer.action(second).warp(maximum, maximum, Duration(0.5, SECOND))
    mixer.action(second).start_at(Duration(2, SECOND))
    var before = AnimationAction(copy=mixer.action(second))
    var old_elapsed = mixer.elapsed
    var old_first_phase = mixer.action(first).phase
    var old_events = mixer.events.copy()
    with assert_raises(contains="scaled advance"):
        mixer.update(scene, Duration(3, SECOND))
    assert_equal(mixer.elapsed, old_elapsed)
    assert_equal(mixer.action(first).phase, old_first_phase)
    assert_equal(len(mixer.events), len(old_events))
    for index in range(len(old_events)):
        assert_equal(mixer.events[index].kind, old_events[index].kind)
        assert_equal(mixer.events[index].action, old_events[index].action)
        assert_equal(
            mixer.events[index].loop_delta, old_events[index].loop_delta
        )
        assert_equal(mixer.events[index].direction, old_events[index].direction)
    var after = AnimationAction(copy=mixer.action(second))
    assert_equal(after.phase, before.phase)
    assert_equal(after.loop_count, before.loop_count)
    assert_equal(after.loop_delta, before.loop_delta)
    assert_equal(after.just_finished, before.just_finished)
    assert_equal(after.started, before.started)
    assert_equal(after.direction, before.direction)
    assert_equal(after.now, before.now)
    assert_equal(after.scheduled, before.scheduled)
    assert_equal(after.warping, before.warping)
    assert_equal(after.time_scale, before.time_scale)
    assert_equal(after.applied_time_scale, before.applied_time_scale)
    assert_equal(after.paused, before.paused)
    assert_equal(after.active, before.active)
    assert_equal(after.ending_start, before.ending_start)
    assert_equal(after.ending_end, before.ending_end)


def test_mixer_clock_overflow_is_atomic() raises:
    var scene = Scene()
    var mixer = AnimationMixer()
    mixer.elapsed = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    mixer.events.append(AnimationEvent(LOOPED, 0, 3, 1))
    with assert_raises(contains="advanced clock"):
        mixer.update(
            scene, Duration(bitcast[DType.float32](UInt32(0x7F7FFFFF)), SECOND)
        )
    assert_equal(mixer.elapsed, bitcast[DType.float32](UInt32(0x7F7FFFFF)))
    assert_equal(len(mixer.events), 1)


def test_nonfinite_steps_and_zero_step_preserve_existing_contract() raises:
    var action = AnimationAction(_clip(), ONCE, clamp_when_finished=True)
    action.advance(2)
    for invalid in [inf[DType.float32](), nan[DType.float32]()]:
        with assert_raises():
            action.advance(invalid)
        assert_equal(action.phase, Float32(1.5))
        assert_true(action.just_finished)
    action.advance(0)
    assert_false(action.just_finished)
    assert_equal(action.phase, Float32(1.5))
    assert_equal(action.loop_count, 0)
    assert_true(action.started)
    var tracks: List[KeyframeTrack] = [
        KeyframeTrack(
            NodeId(0), POSITION, [Duration(0, SECOND)], [Float32(0), 0, 0]
        )
    ]
    with assert_raises(contains="last longer"):
        _ = AnimationClip("static", tracks^)


def test_static_track_with_explicit_positive_duration_still_loops() raises:
    var clip = AnimationClip(
        "held",
        [
            KeyframeTrack(
                NodeId(0), POSITION, [Duration(0, SECOND)], [Float32(0), 0, 0]
            )
        ],
        duration=Duration(2, SECOND),
    )
    var action = AnimationAction(clip^)
    action.advance(2.5)
    assert_equal(action.phase, Float32(0.5))
    assert_equal(action.loop_count, 1)
    assert_equal(action.loop_delta, 1)


def test_initial_reverse_finite_ping_pong_has_the_short_step_endpoint() raises:
    for repetitions in range(5):
        var whole = AnimationAction(
            _clip(1), PING_PONG, clamp_when_finished=True
        )
        whole.set_loop(PING_PONG, repetitions)
        whole.advance(-8)
        var stepped = AnimationAction(
            _clip(1), PING_PONG, clamp_when_finished=True
        )
        stepped.set_loop(PING_PONG, repetitions)
        for _ in range(32):
            if not stepped.paused:
                stepped.advance(-0.25)
        var expected = Float32(
            1
        ) if repetitions > 0 and repetitions % 2 == 0 else Float32(0)
        assert_equal(whole.phase, expected)
        assert_equal(stepped.phase, expected)
        assert_equal(whole.loop_delta, 0)
        assert_equal(whole.loop_count, -1)
        assert_false(whole.started)
        assert_true(whole.just_finished)
        assert_true(stepped.paused)


def test_set_time_preflight_preserves_prior_state_for_all_overloads() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var assets = Assets()
    var cameras = CameraList()
    var mixer = AnimationMixer()
    var first = mixer.add(AnimationAction(_clip()))
    var second = mixer.add(AnimationAction(_clip()))
    mixer.action(first).play()
    mixer.action(second).play()
    mixer.update(scene, Duration(2, SECOND))
    mixer.action(second).set_effective_time_scale(
        bitcast[DType.float32](UInt32(0x7F7FFFFF))
    )
    for overload in range(3):
        with assert_raises(contains="scaled advance"):
            if overload == 0:
                mixer.set_time(scene, Duration(2, SECOND))
            elif overload == 1:
                mixer.set_time(scene, assets, Duration(2, SECOND))
            else:
                mixer.set_time(scene, assets, cameras, Duration(2, SECOND))
        assert_equal(mixer.elapsed, Float32(2))
        assert_equal(mixer.action(first).phase, Float32(0.5))
        assert_equal(mixer.action(second).phase, Float32(0.5))
        assert_equal(mixer.action(first).loop_count, 1)
        assert_equal(mixer.action(second).loop_count, 1)
        assert_equal(mixer.action(second).loop_delta, 1)
        assert_true(mixer.action(second).started)
        assert_false(mixer.action(second).just_finished)
        assert_equal(len(mixer.events), 2)
        assert_equal(mixer.events[0].kind, LOOPED)
        assert_equal(mixer.events[1].kind, LOOPED)


def test_reachable_large_ping_pong_phase_error_and_finite_finish() raises:
    var maximum = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var action = AnimationAction(
        _clip(maximum), PING_PONG, clamp_when_finished=True
    )
    action.play()
    action.advance(-maximum)
    assert_equal(action.phase, Float32(0))
    assert_equal(action.loop_count, 0)
    assert_equal(action.loop_delta, -1)
    assert_true(action.started)
    with assert_raises(contains="reduced phase"):
        action.advance(-1)
    assert_equal(action.phase, Float32(0))
    assert_equal(action.loop_count, 0)
    assert_equal(action.loop_delta, -1)
    assert_false(action.just_finished)
    assert_true(action.active)
    assert_false(action.paused)
    action.set_loop(PING_PONG, 1)
    action.advance(-1)
    assert_equal(action.phase, Float32(0))
    assert_equal(action.loop_count, 0)
    assert_equal(action.loop_delta, 0)
    assert_true(action.just_finished)
    assert_true(action.paused)


def test_phase_sum_overflow_keeps_a_reachable_action_unchanged() raises:
    var maximum = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var action = AnimationAction(_clip(maximum), PING_PONG)
    action.advance(maximum)
    assert_equal(action.phase, maximum)
    assert_equal(action.loop_count, 1)
    with assert_raises(contains="advanced phase"):
        action.advance(maximum)
    assert_equal(action.phase, maximum)
    assert_equal(action.loop_count, 1)
    assert_equal(action.loop_delta, 1)
    assert_true(action.started)
    assert_false(action.just_finished)


def test_reverse_scheduled_updates_wait_and_release_at_the_boundary() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var mixer = AnimationMixer()
    mixer.elapsed = 5
    var which = mixer.add(AnimationAction(_clip()))
    mixer.action(which).play()
    mixer.action(which).start_at(Duration(3, SECOND))
    mixer.update(scene, Duration(-1, SECOND))
    assert_true(mixer.action(which).scheduled)
    assert_equal(mixer.action(which).phase, Float32(0))
    mixer.update(scene, Duration(-1, SECOND))
    assert_false(mixer.action(which).scheduled)
    assert_equal(mixer.action(which).phase, Float32(0))
    mixer.update(scene, Duration(-0.25, SECOND))
    assert_equal(mixer.action(which).phase, Float32(1.25))
    assert_equal(mixer.action(which).loop_delta, -1)
    mixer.action(which).start_at(Duration(2, SECOND))
    mixer.update(scene, Duration(0, SECOND))
    assert_true(mixer.action(which).scheduled)
    mixer.update(scene, Duration(-1, SECOND))
    assert_false(mixer.action(which).scheduled)
    assert_equal(mixer.action(which).phase, Float32(1))


def test_numeric_plan_capacity_is_bounded_in_sparse_caches() raises:
    var mixer = AnimationMixer()
    for _ in range(33):
        _ = mixer.add(AnimationAction(_clip()))
    mixer.action(0).play()
    var one = mixer._prepare_update(Duration(0.125, SECOND))
    assert_equal(one.others.capacity(), 0)
    mixer.action(1).play()
    var sparse = mixer._prepare_update(Duration(0.125, SECOND))
    assert_equal(len(sparse.others), 1)
    assert_equal(sparse.others.capacity(), 8)
    for index in range(2, 17):
        mixer.action(index).play()
    var crowded = mixer._prepare_update(Duration(0.125, SECOND))
    assert_equal(len(crowded.others), 16)
    for index in range(16):
        assert_equal(crowded.others[index].move.phase, Float32(0.125))
    # Every staged record is a value; preparing it has moved no action.
    for index in range(33):
        assert_equal(mixer.action(index).phase, Float32(0))


def test_failure_after_multiple_staged_plans_preserves_every_action() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var mixer = AnimationMixer()
    for _ in range(4):
        var which = mixer.add(AnimationAction(_clip()))
        mixer.action(which).play()
    mixer.update(scene, Duration(2, SECOND))
    mixer.action(3).set_effective_time_scale(
        bitcast[DType.float32](UInt32(0x7F7FFFFF))
    )
    with assert_raises(contains="scaled advance"):
        mixer.update(scene, Duration(2, SECOND))
    assert_equal(mixer.elapsed, Float32(2))
    assert_equal(len(mixer.events), 4)
    for index in range(4):
        assert_equal(mixer.action(index).phase, Float32(0.5))
        assert_equal(mixer.action(index).now, Float32(2))
        assert_equal(mixer.action(index).loop_count, 1)
        assert_equal(mixer.action(index).loop_delta, 1)
        assert_true(mixer.action(index).started)
        assert_false(mixer.action(index).just_finished)
        assert_equal(mixer.events[index].kind, LOOPED)
        assert_equal(mixer.events[index].loop_delta, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
