# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `animation.keyframe_track`, `animation.animation_clip` and
`animation.animation_mixer`.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import (
    AnimationAction,
    AnimationMixer,
    Loop,
    ONCE,
    PING_PONG,
    REPEAT,
    find_pile,
    mix_into_pile,
)
from animation.keyframe_track import (
    Interpolation,
    KeyframeTrack,
    LINEAR,
    POSITION,
    QUATERNION,
    SCALE,
    STEP,
    TrackKind,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Duration, RADIAN, SECOND

comptime TOLERANCE = Float64(1e-5)


def seconds(values: List[Float32]) -> List[Duration]:
    """Return the given numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


def at(value: Float32) -> Duration:
    """Return a time in seconds."""
    return Duration(value, SECOND)


def slide() raises -> KeyframeTrack:
    """Return a two-second track running node zero from the origin out
    along x to four meters."""
    return KeyframeTrack(
        NodeId(0), POSITION, seconds([0, 2]), [0, 0, 0, 4, 0, 0]
    )


# --- the kinds --------------------------------------------------------------


def test_track_kind_is_valid() raises:
    assert_true(POSITION.is_valid())
    assert_true(SCALE.is_valid())
    assert_true(QUATERNION.is_valid())
    assert_false(TrackKind(9).is_valid())


def test_track_kind_component_count() raises:
    assert_equal(QUATERNION.component_count(), 4)
    assert_equal(POSITION.component_count(), 3)
    assert_equal(SCALE.component_count(), 3)
    assert_equal(TrackKind(9).component_count(), 0)


def test_interpolation_is_valid() raises:
    assert_true(STEP.is_valid())
    assert_true(LINEAR.is_valid())
    assert_false(Interpolation(7).is_valid())


def test_loop_is_valid() raises:
    assert_true(ONCE.is_valid())
    assert_true(REPEAT.is_valid())
    assert_true(PING_PONG.is_valid())
    assert_false(Loop(9).is_valid())


# --- KeyframeTrack ----------------------------------------------------------


def test_a_track_holds_its_keys() raises:
    var track = slide()
    assert_equal(track.key_count(), 2)
    assert_almost_equal(track.duration().to(SECOND), Float32(2), atol=TOLERANCE)


def test_a_track_refuses_what_it_cannot_read() raises:
    with assert_raises():
        _ = KeyframeTrack(NodeId(0), TrackKind(9), seconds([0]), [0, 0, 0])
    with assert_raises():
        _ = KeyframeTrack(
            NodeId(0),
            POSITION,
            seconds([0]),
            [0, 0, 0],
            interpolation=Interpolation(7),
        )
    with assert_raises():
        _ = KeyframeTrack(
            NodeId(0), POSITION, List[Duration](), List[Float32]()
        )
    with assert_raises():
        _ = KeyframeTrack(NodeId(0), POSITION, seconds([0, 1]), [0, 0, 0])
    with assert_raises():
        _ = KeyframeTrack(NodeId(0), POSITION, seconds([-1]), [0, 0, 0])
    with assert_raises():
        _ = KeyframeTrack(
            NodeId(0), POSITION, seconds([1, 1]), [0, 0, 0, 1, 0, 0]
        )


def test_a_rotation_key_must_be_a_rotation() raises:
    with assert_raises():
        _ = KeyframeTrack(NodeId(0), QUATERNION, seconds([0]), [0, 0, 0, 2])
    var turned = KeyframeTrack(
        NodeId(0), QUATERNION, seconds([0]), [0, 0, 0, 1]
    )
    assert_equal(turned.key_count(), 1)


def test_a_track_copies() raises:
    var track = slide()
    var twin = KeyframeTrack(copy=track)
    assert_equal(twin.key_count(), 2)
    assert_true(twin.kind == POSITION)
    assert_almost_equal(
        twin.sample_vector3(at(1)).x, Float32(2), atol=TOLERANCE
    )


def test_a_track_holds_its_ends() raises:
    var track = slide()
    assert_almost_equal(
        track.sample_vector3(at(-5)).x, Float32(0), atol=TOLERANCE
    )
    assert_almost_equal(
        track.sample_vector3(at(99)).x, Float32(4), atol=TOLERANCE
    )


def test_a_linear_track_runs_evenly_between_its_keys() raises:
    var track = slide()
    assert_almost_equal(
        track.sample_vector3(at(0.5)).x, Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(
        track.sample_vector3(at(1.5)).x, Float32(3), atol=TOLERANCE
    )


def test_a_step_track_holds_each_key_until_the_next() raises:
    var track = KeyframeTrack(
        NodeId(0),
        SCALE,
        seconds([0, 1, 2]),
        [1, 1, 1, 2, 2, 2, 3, 3, 3],
        interpolation=STEP,
    )
    assert_almost_equal(
        track.sample_vector3(at(0.9)).x, Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(
        track.sample_vector3(at(1.0)).x, Float32(2), atol=TOLERANCE
    )
    assert_almost_equal(
        track.sample_vector3(at(1.9)).x, Float32(2), atol=TOLERANCE
    )


def test_a_rotation_track_turns_along_the_arc() raises:
    # A quarter turn about y, then a half turn: half way between them is
    # three eighths of a turn, which a straight average of four numbers
    # would not give.
    var quarter = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 2, RADIAN)
    )
    var half = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi), RADIAN)
    )
    var track = KeyframeTrack(
        NodeId(0),
        QUATERNION,
        seconds([0, 1]),
        [
            quarter.x,
            quarter.y,
            quarter.z,
            quarter.w,
            half.x,
            half.y,
            half.z,
            half.w,
        ],
    )
    var middle = track.sample_quaternion(at(0.5))
    var wanted = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) * 3 / 4, RADIAN)
    )
    assert_almost_equal(middle.y, wanted.y, atol=TOLERANCE)
    assert_almost_equal(middle.w, wanted.w, atol=TOLERANCE)
    assert_almost_equal(middle.length(), Float32(1), atol=TOLERANCE)


def test_a_track_says_which_kind_of_value_it_has() raises:
    var moving = slide()
    var turning = KeyframeTrack(
        NodeId(0), QUATERNION, seconds([0, 1]), [0, 0, 0, 1, 0, 0, 0, 1]
    )
    with assert_raises():
        _ = moving.sample_quaternion(at(0))
    with assert_raises():
        _ = turning.sample_vector3(at(0))


# --- AnimationClip ----------------------------------------------------------


def test_a_clip_lasts_as_long_as_its_longest_track() raises:
    var slow = KeyframeTrack(
        NodeId(0), POSITION, seconds([0, 3]), [0, 0, 0, 1, 0, 0]
    )
    var quick = KeyframeTrack(
        NodeId(1), SCALE, seconds([0, 1]), [1, 1, 1, 2, 2, 2]
    )
    # The longer one first, so the shorter one does not displace it, and
    # the other way round in the second clip.
    var first = AnimationClip(
        "first", [KeyframeTrack(copy=slow), KeyframeTrack(copy=quick)]
    )
    var second = AnimationClip("second", [quick^, slow^])
    assert_equal(first.track_count(), 2)
    assert_almost_equal(first.duration().to(SECOND), Float32(3), atol=TOLERANCE)
    assert_almost_equal(
        second.duration().to(SECOND), Float32(3), atol=TOLERANCE
    )
    assert_equal(String(first.name), String("first"))


def test_a_clip_refuses_to_last_no_time() raises:
    with assert_raises():
        _ = AnimationClip("empty", List[KeyframeTrack]())
    with assert_raises():
        _ = AnimationClip(
            "still",
            [KeyframeTrack(NodeId(0), POSITION, seconds([0]), [0, 0, 0])],
        )


def test_a_clip_copies() raises:
    var clip = AnimationClip("slide", [slide()])
    var twin = AnimationClip(copy=clip)
    assert_equal(twin.track_count(), 1)
    assert_equal(String(twin.name), String("slide"))


# --- the piles --------------------------------------------------------------


def test_find_pile_matches_a_node_and_a_property() raises:
    var nodes: List[Int] = [3, 3]
    var kinds: List[Int] = [POSITION.value, SCALE.value]
    assert_equal(find_pile(nodes, kinds, 3, POSITION.value), 0)
    assert_equal(find_pile(nodes, kinds, 3, SCALE.value), 1)
    # The right node and the wrong property, then no such node at all.
    assert_equal(find_pile(nodes, kinds, 3, QUATERNION.value), -1)
    assert_equal(find_pile(nodes, kinds, 4, POSITION.value), -1)
    assert_equal(find_pile(List[Int](), List[Int](), 0, 0), -1)


def test_mixing_a_pile_takes_the_weighted_mean() raises:
    var piles: List[Float32] = [0, 0, 0, 0]
    var value: List[Float32] = [4, 0, 0]
    # One unit of weight already in, one unit arriving: half way.
    mix_into_pile(piles, 0, 1, 1, value, POSITION)
    assert_almost_equal(piles[0], Float32(2), atol=TOLERANCE)
    # Two units in, two arriving at eight: half way again, to five.
    var further: List[Float32] = [8, 0, 0]
    mix_into_pile(piles, 0, 2, 2, further, POSITION)
    assert_almost_equal(piles[0], Float32(5), atol=TOLERANCE)


def test_mixing_a_rotation_pile_moves_along_the_arc() raises:
    var quarter = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 2, RADIAN)
    )
    var piles: List[Float32] = [0, 0, 0, 1]
    var value: List[Float32] = [quarter.x, quarter.y, quarter.z, quarter.w]
    mix_into_pile(piles, 0, 1, 1, value, QUATERNION)
    # Half way from no turn to a quarter turn is an eighth of a turn, which
    # a straight average of four numbers does not give. The pile is
    # compared by the size of its dot product with that turn: a quaternion
    # and its negative are the same rotation, and `slerp` may return
    # either.
    var mixed = Quaternion(piles[0], piles[1], piles[2], piles[3])
    var eighth = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 4, RADIAN)
    )
    assert_almost_equal(abs(mixed.dot(eighth)), Float32(1), atol=TOLERANCE)
    assert_almost_equal(mixed.length(), Float32(1), atol=TOLERANCE)


# --- AnimationAction --------------------------------------------------------


def sliding_action(loop: Loop = REPEAT) raises -> AnimationAction:
    """Return a stopped action on the two-second slide."""
    return AnimationAction(AnimationClip("slide", [slide()]), loop)


def test_an_action_starts_stopped_at_the_beginning() raises:
    var action = sliding_action()
    assert_false(action.is_playing())
    assert_almost_equal(action.at().to(SECOND), Float32(0), atol=TOLERANCE)
    action.play()
    assert_true(action.is_playing())
    action.advance(0.5)
    action.pause()
    assert_false(action.is_playing())
    assert_almost_equal(action.at().to(SECOND), Float32(0.5), atol=TOLERANCE)
    action.stop()
    assert_almost_equal(action.at().to(SECOND), Float32(0), atol=TOLERANCE)


def test_an_action_refuses_a_weight_it_cannot_share() raises:
    with assert_raises():
        _ = AnimationAction(AnimationClip("slide", [slide()]), REPEAT, -1)
    with assert_raises():
        _ = AnimationAction(AnimationClip("slide", [slide()]), Loop(9))
    var action = sliding_action()
    with assert_raises():
        action.set_weight(-0.5)
    action.set_weight(0.25)
    assert_almost_equal(action.weight, Float32(0.25), atol=TOLERANCE)


def test_an_action_copies() raises:
    var action = sliding_action()
    action.play()
    action.advance(0.5)
    var twin = AnimationAction(copy=action)
    action.advance(0.5)
    assert_almost_equal(twin.at().to(SECOND), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(action.at().to(SECOND), Float32(1), atol=TOLERANCE)


def test_a_looping_action_starts_over() raises:
    var action = sliding_action(REPEAT)
    action.play()
    action.advance(3)
    assert_almost_equal(action.at().to(SECOND), Float32(1), atol=TOLERANCE)
    assert_true(action.is_playing())


def test_an_action_that_plays_once_stops_at_each_end() raises:
    var forward = sliding_action(ONCE)
    forward.play()
    forward.advance(0.5)
    assert_true(forward.is_playing())
    forward.advance(5)
    assert_almost_equal(forward.at().to(SECOND), Float32(2), atol=TOLERANCE)
    assert_false(forward.is_playing())

    var backward = sliding_action(ONCE)
    backward.time_scale = -1
    backward.play()
    backward.advance(1)
    assert_almost_equal(backward.at().to(SECOND), Float32(0), atol=TOLERANCE)
    assert_false(backward.is_playing())


def test_a_ping_pong_action_runs_back_the_way_it_came() raises:
    var action = sliding_action(PING_PONG)
    action.play()
    action.advance(1)
    assert_almost_equal(action.at().to(SECOND), Float32(1), atol=TOLERANCE)
    # Past the end, and back down the far side.
    action.advance(2)
    assert_almost_equal(action.at().to(SECOND), Float32(1), atol=TOLERANCE)
    # Round again, and into the stretch below zero, which folds up again.
    action.advance(2.5)
    assert_true(action.at().to(SECOND) >= 0)
    assert_true(action.at().to(SECOND) <= 2)


# --- AnimationMixer ---------------------------------------------------------


def one_node_scene() raises -> Scene:
    """Return a scene with one node at the origin."""
    var scene = Scene()
    _ = scene.add(Object3D())
    return scene^


def test_a_mixer_plays_a_clip_into_the_scene() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(sliding_action())
    assert_equal(mixer.action_count(), 1)
    mixer.action(which).play()

    mixer.update(scene, at(1))
    assert_almost_equal(
        scene.get(NodeId(0)).position.x, Float32(2), atol=TOLERANCE
    )
    assert_almost_equal(mixer.time().to(SECOND), Float32(1), atol=TOLERANCE)

    mixer.update(scene, at(0.5))
    assert_almost_equal(
        scene.get(NodeId(0)).position.x, Float32(3), atol=TOLERANCE
    )


def test_a_mixer_leaves_a_stopped_or_weightless_action_alone() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var stopped = mixer.add(sliding_action())
    var weightless = mixer.add(sliding_action())
    mixer.action(weightless).play()
    mixer.action(weightless).set_weight(0)
    mixer.update(scene, at(1))
    # Neither wrote, so the node is where it started.
    assert_almost_equal(
        scene.get(NodeId(0)).position.x, Float32(0), atol=TOLERANCE
    )
    # The weightless one still moved on; the stopped one did not.
    assert_almost_equal(
        mixer.action(weightless).at().to(SECOND), Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(
        mixer.action(stopped).at().to(SECOND), Float32(0), atol=TOLERANCE
    )


def test_two_actions_on_one_node_make_one_pose() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var out = mixer.add(sliding_action())
    var back = mixer.add(
        AnimationAction(
            AnimationClip(
                "back",
                [
                    KeyframeTrack(
                        NodeId(0),
                        POSITION,
                        seconds([0, 2]),
                        [0, 0, 0, -4, 0, 0],
                    )
                ],
            )
        )
    )
    mixer.action(out).play()
    mixer.action(back).play()
    mixer.update(scene, at(1))
    # Two meters out and two meters back, at equal weight: the origin.
    assert_almost_equal(
        scene.get(NodeId(0)).position.x, Float32(0), atol=TOLERANCE
    )


def test_a_mixer_writes_every_kind_of_property() raises:
    var scene = one_node_scene()
    var quarter = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 2, RADIAN)
    )
    var mixer = AnimationMixer()
    var which = mixer.add(
        AnimationAction(
            AnimationClip(
                "everything",
                [
                    slide(),
                    KeyframeTrack(
                        NodeId(0),
                        SCALE,
                        seconds([0, 2]),
                        [1, 1, 1, 3, 3, 3],
                    ),
                    KeyframeTrack(
                        NodeId(0),
                        QUATERNION,
                        seconds([0, 2]),
                        [
                            0,
                            0,
                            0,
                            1,
                            quarter.x,
                            quarter.y,
                            quarter.z,
                            quarter.w,
                        ],
                    ),
                ],
            )
        )
    )
    mixer.action(which).play()
    # One second of a two-second clip: half way along every track. A whole
    # two seconds would wrap a repeating action back to its start.
    mixer.update(scene, at(1))
    var node = scene.get(NodeId(0))
    assert_almost_equal(node.position.x, Float32(2), atol=TOLERANCE)
    assert_almost_equal(node.scale.y, Float32(2), atol=TOLERANCE)
    var eighth = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 4, RADIAN)
    )
    assert_almost_equal(
        abs(node.quaternion.dot(eighth)), Float32(1), atol=TOLERANCE
    )


def test_a_mixer_refuses_an_action_or_a_node_it_does_not_have() raises:
    var mixer = AnimationMixer()
    _ = mixer.add(sliding_action())
    with assert_raises():
        _ = mixer.action(-1)
    with assert_raises():
        _ = mixer.action(1)

    var scene = one_node_scene()
    var stray = AnimationMixer()
    var which = stray.add(
        AnimationAction(
            AnimationClip(
                "stray",
                [
                    KeyframeTrack(
                        NodeId(7),
                        POSITION,
                        seconds([0, 1]),
                        [0, 0, 0, 1, 0, 0],
                    )
                ],
            )
        )
    )
    stray.action(which).play()
    with assert_raises():
        stray.update(scene, at(0.5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
