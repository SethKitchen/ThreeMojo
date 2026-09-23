# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the fades, warps, start times and events of
`animation.animation_mixer`.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import (
    AnimationAction,
    AnimationEvent,
    AnimationEventKind,
    AnimationMixer,
    FINISHED,
    LOOPED,
    ONCE,
    PING_PONG,
    REPEAT,
    Loop,
    Ramp,
    checked_span,
)
from animation.keyframe_track import KeyframeTrack, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration, SECOND

comptime TOLERANCE = Float64(1e-5)


def at(value: Float32) -> Duration:
    """Return a time in seconds."""
    return Duration(value, SECOND)


def seconds(values: List[Float32]) -> List[Duration]:
    """Return the given numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


def holding(x: Float32, length: Float32 = 2) raises -> AnimationAction:
    """Return an action whose clip holds node zero at `x` for `length`
    seconds."""
    return AnimationAction(
        AnimationClip(
            "hold",
            [
                KeyframeTrack(
                    NodeId(0),
                    POSITION,
                    seconds([0, length]),
                    [x, 0, 0, x, 0, 0],
                )
            ],
        )
    )


def sliding(loop: Loop = REPEAT) raises -> AnimationAction:
    """Return an action on a two-second slide of node zero along x."""
    return AnimationAction(
        AnimationClip(
            "slide",
            [
                KeyframeTrack(
                    NodeId(0), POSITION, seconds([0, 2]), [0, 0, 0, 4, 0, 0]
                )
            ],
        ),
        loop,
    )


def one_node_scene() raises -> Scene:
    """Return a scene with one node at the origin."""
    var scene = Scene()
    _ = scene.add(Object3D())
    return scene^


def x_of(scene: Scene) raises -> Float32:
    """Return where node zero is along x."""
    return scene.get(NodeId(0)).position.x


# --- the pieces -------------------------------------------------------------


def test_event_kind_is_valid() raises:
    assert_true(LOOPED.is_valid())
    assert_true(FINISHED.is_valid())
    assert_false(AnimationEventKind(7).is_valid())


def test_an_event_holds_what_happened() raises:
    var event = AnimationEvent(LOOPED, 2, -1, -1)
    assert_true(event.kind == LOOPED)
    assert_equal(event.action, 2)
    assert_equal(event.loop_delta, -1)
    assert_equal(event.direction, -1)


def test_a_ramp_runs_straight_and_holds_its_ends() raises:
    var ramp = Ramp(1, 3, 0, 1)
    assert_almost_equal(ramp.at(0), Float32(0), atol=TOLERANCE)
    assert_almost_equal(ramp.at(1), Float32(0), atol=TOLERANCE)
    assert_almost_equal(ramp.at(2), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(ramp.at(3), Float32(1), atol=TOLERANCE)
    assert_almost_equal(ramp.at(4), Float32(1), atol=TOLERANCE)
    # A ramp of no length is at its end from its start on, as three.js's
    # interpolant is.
    assert_almost_equal(Ramp(1, 1, 0, 1).at(1), Float32(1), atol=TOLERANCE)


def test_a_span_must_be_a_time_that_is_not_negative() raises:
    assert_almost_equal(
        checked_span(at(2), "A fade"), Float32(2), atol=TOLERANCE
    )
    with assert_raises():
        _ = checked_span(at(-1), "A fade")
    with assert_raises():
        _ = checked_span(at(Float32.MAX * 2), "A fade")


# --- fades ------------------------------------------------------------------


def test_a_fade_in_raises_the_weight_along_a_line() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(holding(10))
    mixer.action(which).play()
    mixer.action(which).fade_in(at(2))
    mixer.update(scene, at(0.5))
    assert_almost_equal(
        mixer.action(which).get_effective_weight(),
        Float32(0.25),
        atol=TOLERANCE,
    )
    assert_almost_equal(x_of(scene), Float32(2.5), atol=TOLERANCE)
    # At the end the fade is done but not yet over: three.js ends it on
    # the update after the clock passes the end.
    mixer.update(scene, at(1.5))
    assert_almost_equal(x_of(scene), Float32(10), atol=TOLERANCE)
    assert_true(mixer.action(which).fading)
    mixer.update(scene, at(0.5))
    assert_false(mixer.action(which).fading)
    assert_true(mixer.action(which).is_active())
    assert_almost_equal(x_of(scene), Float32(10), atol=TOLERANCE)


def test_a_fade_out_ends_by_taking_the_action_out() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(holding(10))
    mixer.action(which).play()
    mixer.update(scene, at(1))
    mixer.action(which).fade_out(at(1))
    mixer.update(scene, at(0.5))
    assert_almost_equal(x_of(scene), Float32(5), atol=TOLERANCE)
    mixer.update(scene, at(0.5))
    # A weight of nothing lets the node go back to where it was.
    assert_almost_equal(x_of(scene), Float32(0), atol=TOLERANCE)
    assert_true(mixer.action(which).is_active())
    mixer.update(scene, at(0.5))
    assert_false(mixer.action(which).is_active())
    assert_false(mixer.action(which).fading)
    assert_almost_equal(
        mixer.action(which).get_effective_weight(), Float32(0), atol=TOLERANCE
    )
    # Out of the pose, it is kept in step with the mixer's clock.
    mixer.update(scene, at(0.5))
    assert_almost_equal(mixer.action(which).now, Float32(3), atol=TOLERANCE)


def test_a_fade_starts_at_the_mixers_time_now() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    mixer.update(scene, at(2))
    var early = mixer.add(holding(10))
    assert_almost_equal(mixer.action(early).now, Float32(2), atol=TOLERANCE)
    mixer.update(scene, at(1))
    mixer.action(early).fade_in(at(1))
    assert_almost_equal(
        mixer.action(early).fade.start, Float32(3), atol=TOLERANCE
    )
    assert_almost_equal(
        mixer.action(early).fade.end, Float32(4), atol=TOLERANCE
    )
    with assert_raises():
        mixer.action(early).fade_out(at(-1))


def test_setting_the_effective_weight_stops_a_fade() raises:
    var action = holding(10)
    action.fade_in(at(1))
    action.set_effective_weight(0.5)
    assert_false(action.fading)
    assert_almost_equal(action.weight, Float32(0.5), atol=TOLERANCE)
    # Not playing, so it contributes nothing yet.
    assert_almost_equal(
        action.get_effective_weight(), Float32(0), atol=TOLERANCE
    )
    action.play()
    action.set_effective_weight(0.75)
    assert_almost_equal(
        action.get_effective_weight(), Float32(0.75), atol=TOLERANCE
    )
    with assert_raises():
        action.set_effective_weight(-1)


# --- warps ------------------------------------------------------------------


def test_a_warp_changes_the_time_scale_along_a_line() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(holding(0, 100))
    mixer.action(which).play()
    mixer.action(which).warp(1, 3, at(2))
    mixer.update(scene, at(1))
    assert_almost_equal(
        mixer.action(which).get_effective_time_scale(),
        Float32(2),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        mixer.action(which).at().to(SECOND), Float32(2), atol=TOLERANCE
    )
    mixer.update(scene, at(1.5))
    # Past its end, the warp leaves the time scale at its end value.
    assert_false(mixer.action(which).warping)
    assert_almost_equal(
        mixer.action(which).time_scale, Float32(3), atol=TOLERANCE
    )
    assert_almost_equal(
        mixer.action(which).at().to(SECOND), Float32(6.5), atol=TOLERANCE
    )


def test_a_warp_holds_shares_of_the_time_scale() raises:
    var action = holding(0)
    action.time_scale = 2
    action.warp(1, 4, at(1))
    assert_almost_equal(
        action.warp_ramp.from_value, Float32(0.5), atol=TOLERANCE
    )
    assert_almost_equal(action.warp_ramp.to_value, Float32(2), atol=TOLERANCE)


def test_halting_slows_the_action_to_a_pause() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(holding(0, 100))
    mixer.action(which).play()
    mixer.action(which).halt(at(1))
    mixer.update(scene, at(0.5))
    assert_almost_equal(
        mixer.action(which).get_effective_time_scale(),
        Float32(0.5),
        atol=TOLERANCE,
    )
    mixer.update(scene, at(1))
    assert_true(mixer.action(which).is_active())
    assert_false(mixer.action(which).is_playing())
    # The time scale is left as it was, ready for `play`.
    assert_almost_equal(
        mixer.action(which).time_scale, Float32(1), atol=TOLERANCE
    )
    mixer.update(scene, at(1))
    assert_almost_equal(
        mixer.action(which).get_effective_time_scale(),
        Float32(0),
        atol=TOLERANCE,
    )


def test_a_warp_refuses_what_it_cannot_share() raises:
    var action = holding(0)
    var nan = Float32.MAX * 2 - Float32.MAX * 2
    with assert_raises():
        action.warp(nan, 1, at(1))
    with assert_raises():
        action.warp(1, nan, at(1))
    with assert_raises():
        action.warp(1, 2, at(-1))
    action.time_scale = 0
    with assert_raises():
        action.warp(1, 2, at(1))
    assert_false(action.warping)


def test_setting_the_effective_time_scale_stops_a_warp() raises:
    var action = holding(0)
    action.warp(1, 2, at(1))
    action.set_effective_time_scale(3)
    assert_false(action.warping)
    assert_almost_equal(
        action.get_effective_time_scale(), Float32(3), atol=TOLERANCE
    )
    action.pause()
    action.set_effective_time_scale(4)
    assert_almost_equal(
        action.get_effective_time_scale(), Float32(0), atol=TOLERANCE
    )
    assert_almost_equal(action.time_scale, Float32(4), atol=TOLERANCE)
    with assert_raises():
        action.set_effective_time_scale(Float32.MAX * 2)


# --- start times ------------------------------------------------------------


def test_an_action_waits_for_its_start_time() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(sliding())
    mixer.action(which).play()
    mixer.action(which).start_at(at(1))
    mixer.update(scene, at(0.5))
    assert_almost_equal(
        mixer.action(which).at().to(SECOND), Float32(0), atol=TOLERANCE
    )
    # It contributes its pose while it waits.
    assert_equal(mixer.binding_count(), 1)
    # A delta of nothing goes nowhere, whatever the start time.
    mixer.update(scene, at(0))
    assert_true(mixer.action(which).scheduled)
    # The update that passes the start runs only the part after it.
    mixer.update(scene, at(1))
    assert_false(mixer.action(which).scheduled)
    assert_almost_equal(
        mixer.action(which).at().to(SECOND), Float32(0.5), atol=TOLERANCE
    )
    with assert_raises():
        mixer.action(which).start_at(at(Float32.MAX * 2))


def test_a_start_time_behind_a_backward_clock_waits_too() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    mixer.update(scene, at(5))
    var which = mixer.add(sliding())
    mixer.action(which).play()
    mixer.action(which).start_at(at(3))
    # The clock runs back from five to four, which has not reached three.
    mixer.update(scene, at(-1))
    assert_true(mixer.action(which).scheduled)
    assert_almost_equal(
        mixer.action(which).at().to(SECOND), Float32(0), atol=TOLERANCE
    )


def test_stopping_drops_fades_warps_and_start_times() raises:
    var action = holding(0)
    action.fade_in(at(1))
    action.warp(1, 2, at(1))
    action.start_at(at(1))
    action.stop()
    assert_false(action.fading)
    assert_false(action.warping)
    assert_false(action.scheduled)


def test_an_action_copies_its_fade_and_warp() raises:
    var action = holding(0)
    action.fade_out(at(2))
    action.warp(1, 2, at(3))
    action.start_at(at(4))
    var twin = AnimationAction(copy=action)
    assert_true(twin.fading)
    assert_true(twin.warping)
    assert_true(twin.scheduled)
    assert_almost_equal(twin.fade.end, Float32(2), atol=TOLERANCE)
    assert_almost_equal(twin.warp_ramp.end, Float32(3), atol=TOLERANCE)
    assert_almost_equal(twin.start_time, Float32(4), atol=TOLERANCE)


# --- cross-fades ------------------------------------------------------------


def test_a_cross_fade_hands_the_node_from_one_action_to_another() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var low = mixer.add(holding(0))
    var high = mixer.add(holding(10))
    mixer.action(low).play()
    mixer.update(scene, at(1))
    mixer.action(high).play()
    mixer.cross_fade_from(high, low, at(2))
    mixer.update(scene, at(1))
    assert_almost_equal(x_of(scene), Float32(5), atol=TOLERANCE)
    mixer.update(scene, at(1))
    assert_almost_equal(x_of(scene), Float32(10), atol=TOLERANCE)
    mixer.update(scene, at(0.5))
    assert_false(mixer.action(low).is_active())
    assert_true(mixer.action(high).is_active())
    assert_false(mixer.action(low).warping)


def test_cross_fading_to_is_cross_fading_from_turned_round() raises:
    var mixer = AnimationMixer()
    var first = mixer.add(holding(0))
    var second = mixer.add(holding(10))
    mixer.cross_fade_to(first, second, at(1))
    assert_almost_equal(
        mixer.action(first).fade.to_value, Float32(0), atol=TOLERANCE
    )
    assert_almost_equal(
        mixer.action(second).fade.to_value, Float32(1), atol=TOLERANCE
    )


def test_a_warped_cross_fade_lines_up_the_two_clips() raises:
    var mixer = AnimationMixer()
    var short = mixer.add(holding(0, 2))
    var long = mixer.add(holding(10, 4))
    mixer.cross_fade_from(long, short, at(1), warp=True)
    # The one going out ends at the pace of the one coming in, and the one
    # coming in starts at the pace of the one going out.
    assert_almost_equal(
        mixer.action(short).warp_ramp.from_value, Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(
        mixer.action(short).warp_ramp.to_value, Float32(0.5), atol=TOLERANCE
    )
    assert_almost_equal(
        mixer.action(long).warp_ramp.from_value, Float32(2), atol=TOLERANCE
    )
    assert_almost_equal(
        mixer.action(long).warp_ramp.to_value, Float32(1), atol=TOLERANCE
    )


def test_a_cross_fade_refuses_and_changes_nothing() raises:
    var mixer = AnimationMixer()
    var first = mixer.add(holding(0))
    var second = mixer.add(holding(10))
    with assert_raises():
        mixer.cross_fade_from(-1, second, at(1))
    with assert_raises():
        mixer.cross_fade_from(5, second, at(1))
    with assert_raises():
        mixer.cross_fade_from(first, -1, at(1))
    with assert_raises():
        mixer.cross_fade_from(first, 5, at(1))
    with assert_raises():
        mixer.cross_fade_from(first, first, at(1))
    with assert_raises():
        mixer.cross_fade_from(first, second, at(-1))
    mixer.action(first).time_scale = 0
    with assert_raises():
        mixer.cross_fade_from(first, second, at(1), warp=True)
    mixer.action(first).time_scale = 1
    mixer.action(second).time_scale = 0
    with assert_raises():
        mixer.cross_fade_from(first, second, at(1), warp=True)
    assert_false(mixer.action(first).fading)
    assert_false(mixer.action(second).fading)
    # Without a warp a time scale of zero does not matter.
    mixer.cross_fade_from(first, second, at(1))
    assert_true(mixer.action(first).fading)
    assert_false(mixer.action(first).warping)


# --- events -----------------------------------------------------------------


def test_a_repeating_action_says_when_it_loops() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(sliding(REPEAT))
    mixer.action(which).play()
    mixer.update(scene, at(0.5))
    assert_equal(mixer.event_count(), 0)
    mixer.update(scene, at(2))
    assert_equal(mixer.event_count(), 1)
    var events = mixer.drain_events()
    assert_equal(len(events), 1)
    assert_true(events[0].kind == LOOPED)
    assert_equal(events[0].action, which)
    assert_equal(events[0].loop_delta, 1)
    assert_equal(events[0].direction, 1)
    assert_equal(mixer.event_count(), 0)
    # Several ends in one update are one event that counts them.
    mixer.update(scene, at(4))
    events = mixer.drain_events()
    assert_equal(events[0].loop_delta, 2)
    # Each update starts a new list, drained or not.
    mixer.update(scene, at(2))
    assert_equal(mixer.event_count(), 1)
    mixer.update(scene, at(0.1))
    assert_equal(mixer.event_count(), 0)


def test_a_backward_action_loops_the_other_way() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(sliding(REPEAT))
    mixer.action(which).time_scale = -1
    mixer.action(which).play()
    mixer.update(scene, at(0.5))
    var events = mixer.drain_events()
    assert_equal(len(events), 1)
    assert_equal(events[0].loop_delta, -1)
    assert_equal(events[0].direction, -1)


def test_a_ping_pong_action_loops_at_both_ends() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(sliding(PING_PONG))
    mixer.action(which).play()
    mixer.update(scene, at(2.5))
    assert_equal(mixer.drain_events()[0].loop_delta, 1)
    mixer.update(scene, at(1))
    assert_equal(mixer.event_count(), 0)
    mixer.update(scene, at(1))
    assert_equal(mixer.drain_events()[0].loop_delta, 1)


def test_a_once_action_says_when_it_finishes_and_which_way() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var forward = mixer.add(sliding(ONCE))
    var backward = mixer.add(sliding(ONCE))
    mixer.action(forward).play()
    mixer.action(backward).time_scale = -1
    mixer.action(backward).clamp_when_finished = True
    mixer.action(backward).play()
    mixer.update(scene, at(3))
    var events = mixer.drain_events()
    assert_equal(len(events), 2)
    assert_true(events[0].kind == FINISHED)
    assert_equal(events[0].action, forward)
    assert_equal(events[0].direction, 1)
    assert_equal(events[0].loop_delta, 0)
    assert_equal(events[1].action, backward)
    assert_equal(events[1].direction, -1)
    # Finished is said once, not every update after.
    mixer.update(scene, at(1))
    assert_equal(mixer.event_count(), 0)


def test_a_move_of_nothing_finishes_nothing() raises:
    # A held `ONCE` action played again at its end does not finish again
    # until it moves, as three.js's `_updateTime` returns early on zero.
    var action = AnimationAction(
        AnimationClip(
            "slide",
            [
                KeyframeTrack(
                    NodeId(0), POSITION, seconds([0, 2]), [0, 0, 0, 4, 0, 0]
                )
            ],
        ),
        ONCE,
        clamp_when_finished=True,
    )
    action.play()
    action.advance(5)
    assert_true(action.just_finished)
    action.play()
    action.advance(0)
    assert_false(action.just_finished)
    assert_true(action.is_playing())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
