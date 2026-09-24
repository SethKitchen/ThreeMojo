# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the `SMOOTH` and `CUBIC_SPLINE` interpolations of
`animation.keyframe_track`, the ending modes an `AnimationAction` sets for
them, and how `animation.animation_utils` carries a cubic spline track.

The expected numbers come from three.js r186 itself: `CubicInterpolant`,
`AnimationMixer`, and the `GLTFCubicSplineInterpolant` and
`GLTFCubicSplineQuaternionInterpolant` that `GLTFLoader.js` defines,
evaluated under Node.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import (
    AnimationAction,
    AnimationMixer,
    ONCE,
    PING_PONG,
    REPEAT,
)
from animation.animation_utils import make_clip_additive, subclip
from animation.keyframe_track import (
    CUBIC_SPLINE,
    Ending,
    Interpolation,
    KeyframeTrack,
    LIGHT_COLOR,
    LINEAR,
    LightIndex,
    MATERIAL_OPACITY,
    MORPH_INFLUENCE,
    MeshIndex,
    POSITION,
    QUATERNION,
    SCALE,
    SMOOTH,
    STEP,
    VISIBLE,
    WRAP_AROUND_ENDING,
    ZERO_CURVATURE_ENDING,
    ZERO_SLOPE_ENDING,
    light_target,
    material_target,
    morph_target,
    node_target,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import MaterialId
from std.math import nan, sqrt
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


def seconds(values: List[Float32]) -> List[Duration]:
    """Return the given numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


def at(value: Float32) -> Duration:
    """Return a time in seconds."""
    return Duration(value, SECOND)


def assert_numbers(got: List[Float32], want: List[Float32]) raises:
    """Assert two lists of numbers agree to within the tolerance."""
    assert_equal(len(got), len(want))
    for index in range(len(want)):
        assert_almost_equal(
            Float64(got[index]), Float64(want[index]), atol=TOLERANCE
        )


def uneven() raises -> KeyframeTrack:
    """Return a `SMOOTH` position track with unevenly spaced keys, the one
    the three.js numbers were taken from."""
    return KeyframeTrack(
        NodeId(0),
        POSITION,
        seconds([0, 0.5, 2, 3]),
        [0, 0, 0, 1, 2, -1, 3, 1, 0, 2, -2, 4],
        SMOOTH,
    )


def spline() raises -> KeyframeTrack:
    """Return a `CUBIC_SPLINE` position track of three keys. The first
    in-tangent and the last out-tangent are never read, so they are nines.
    """
    return KeyframeTrack(
        node_target(NodeId(0), POSITION),
        seconds([0, 1, 2.5]),
        in_tangents=[9, 9, 9, -1, 0, 2, 3, 1, 0],
        values=[0, 0, 0, 1, 1, 1, 2, 0, 1],
        out_tangents=[1, 2, 0, 0.5, 0, -1, 9, 9, 9],
    )


def turning() raises -> KeyframeTrack:
    """Return a `CUBIC_SPLINE` rotation track of two keys."""
    var half = Float32(sqrt(0.5))
    return KeyframeTrack(
        node_target(NodeId(0), QUATERNION),
        seconds([0, 1]),
        in_tangents=[0, 0, 0, 0, 0, 0.5, 0, -0.2],
        values=[0, 0, 0, 1, 0, half, 0, half],
        out_tangents=[0, 0.8, 0, 0.1, 0, 0, 0, 0],
    )


# --- the types --------------------------------------------------------------


def test_every_interpolation_is_valid_and_no_other() raises:
    assert_true(STEP.is_valid())
    assert_true(LINEAR.is_valid())
    assert_true(SMOOTH.is_valid())
    assert_true(CUBIC_SPLINE.is_valid())
    assert_false(Interpolation(5).is_valid())
    assert_false(Interpolation(-1).is_valid())


def test_every_ending_is_valid_and_no_other() raises:
    assert_true(ZERO_CURVATURE_ENDING.is_valid())
    assert_true(ZERO_SLOPE_ENDING.is_valid())
    assert_true(WRAP_AROUND_ENDING.is_valid())
    assert_false(Ending(3).is_valid())
    assert_false(Ending(-1).is_valid())


# --- SMOOTH -----------------------------------------------------------------


def test_smooth_matches_three_with_zero_curvature_ends() raises:
    var track = uneven()
    assert_numbers(
        track.sample(at(0.25)), [0.520833313, 1.14583337, -0.583333313]
    )
    assert_numbers(track.sample(at(1.1)), [2.03999996, 2.27200007, -1.12800002])
    assert_numbers(track.sample(at(2.7)), [2.37350011, -1.02649999, 2.69499993])


def test_smooth_matches_three_with_zero_slope_ends() raises:
    var track = uneven()
    var flat = ZERO_SLOPE_ENDING
    assert_numbers(
        track.sample(at(0.25), flat, flat),
        [0.395833343, 0.895833313, -0.458333343],
    )
    assert_numbers(
        track.sample(at(1.1), flat, flat), [2.03999996, 2.27200007, -1.12800002]
    )
    assert_numbers(
        track.sample(at(2.7), flat, flat), [2.29999995, -1.24699998, 2.98900008]
    )


def test_smooth_matches_three_with_wrap_around_ends() raises:
    var track = uneven()
    var wrap = WRAP_AROUND_ENDING
    assert_numbers(
        track.sample(at(0.25), wrap, wrap),
        [0.364583343, 0.989583313, -0.520833313],
    )
    assert_numbers(
        track.sample(at(2.7), wrap, wrap), [2.44700003, -1.83500004, 3.72399998]
    )


def test_smooth_reads_each_end_by_its_own_mode() raises:
    var track = uneven()
    assert_numbers(
        track.sample(at(0.25), ZERO_SLOPE_ENDING, WRAP_AROUND_ENDING),
        [0.395833343, 0.895833313, -0.458333343],
    )
    assert_numbers(
        track.sample(at(2.7), ZERO_SLOPE_ENDING, WRAP_AROUND_ENDING),
        [2.44700003, -1.83500004, 3.72399998],
    )
    assert_numbers(
        track.sample(at(0.25), WRAP_AROUND_ENDING, ZERO_CURVATURE_ENDING),
        [0.364583343, 0.989583313, -0.520833313],
    )
    assert_numbers(
        track.sample(at(2.7), WRAP_AROUND_ENDING, ZERO_CURVATURE_ENDING),
        [2.37350011, -1.02649999, 2.69499993],
    )


def test_smooth_holds_the_keys_and_the_ends() raises:
    var track = uneven()
    assert_numbers(track.sample(at(0)), [0, 0, 0])
    assert_numbers(track.sample(at(0.5)), [1, 2, -1])
    assert_numbers(track.sample(at(2)), [3, 1, 0])
    assert_numbers(track.sample(at(9)), [2, -2, 4])


def test_smooth_over_two_keys_matches_three_for_each_ending() raises:
    var track = KeyframeTrack(
        morph_target(MeshIndex(0), 0), seconds([0, 1]), [0, 4], SMOOTH
    )
    # A natural spline through two keys is the straight line.
    assert_numbers(track.sample(at(0.3)), [1.20000005])
    assert_numbers(
        track.sample(at(0.3), ZERO_SLOPE_ENDING, ZERO_SLOPE_ENDING),
        [0.737999976],
    )
    assert_numbers(
        track.sample(at(0.3), WRAP_AROUND_ENDING, WRAP_AROUND_ENDING),
        [1.03199995],
    )


def test_smooth_number_track_matches_three() raises:
    var track = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        seconds([0, 1, 3]),
        [0, 2, 1],
        SMOOTH,
    )
    assert_numbers(track.sample(at(0.6)), [1.38])
    assert_numbers(track.sample(at(2.2)), [1.63999999])


def test_smooth_scale_and_color_tracks_run_the_same_curve() raises:
    var scale = KeyframeTrack(
        NodeId(0),
        SCALE,
        seconds([0, 0.5, 2, 3]),
        [0, 0, 0, 1, 2, -1, 3, 1, 0, 2, -2, 4],
        SMOOTH,
    )
    assert_numbers(scale.sample(at(1.1)), [2.03999996, 2.27200007, -1.12800002])
    var color = KeyframeTrack(
        light_target(LightIndex(0), LIGHT_COLOR),
        seconds([0, 1]),
        [0, 0, 0, 1, 0.5, 0],
        SMOOTH,
    )
    assert_numbers(color.sample(at(0.5)), [0.5, 0.25, 0])


def test_smooth_sample_vector3_takes_endings() raises:
    var moved = uneven().sample_vector3(
        at(0.25), ZERO_SLOPE_ENDING, ZERO_SLOPE_ENDING
    )
    assert_almost_equal(Float64(moved.x), 0.395833343, atol=TOLERANCE)


def test_a_rotation_track_cannot_be_smooth() raises:
    # three.js's `QuaternionKeyframeTrack` has no smooth factory. It warns
    # and falls back to linear; this port refuses.
    with assert_raises(contains="SMOOTH"):
        _ = KeyframeTrack(
            NodeId(0),
            QUATERNION,
            seconds([0, 1]),
            [0, 0, 0, 1, 0, 0, 1, 0],
            SMOOTH,
        )


def test_a_flag_track_cannot_be_smooth() raises:
    with assert_raises(contains="STEP"):
        _ = KeyframeTrack(NodeId(0), VISIBLE, seconds([0, 1]), [1, 0], SMOOTH)


def test_an_interpolation_that_is_not_named_is_refused() raises:
    with assert_raises(contains="CUBIC_SPLINE"):
        _ = KeyframeTrack(
            NodeId(0), POSITION, seconds([0]), [0, 0, 0], Interpolation(5)
        )


def test_cubic_spline_without_tangents_is_refused() raises:
    with assert_raises(contains="tangents"):
        _ = KeyframeTrack(
            NodeId(0), POSITION, seconds([0]), [0, 0, 0], CUBIC_SPLINE
        )


def test_sample_refuses_an_ending_that_is_not_named() raises:
    var track = uneven()
    with assert_raises(contains="ending"):
        _ = track.sample(at(1), Ending(3), ZERO_SLOPE_ENDING)
    with assert_raises(contains="ending"):
        _ = track.sample(at(1), ZERO_SLOPE_ENDING, Ending(-1))


def test_sample_refuses_an_interpolation_set_afterward() raises:
    var track = KeyframeTrack(
        NodeId(0), QUATERNION, seconds([0, 1]), [0, 0, 0, 1, 0, 0, 1, 0]
    )
    track.interpolation = SMOOTH
    with assert_raises(contains="SMOOTH"):
        _ = track.sample(at(0.5))


# --- CUBIC_SPLINE -----------------------------------------------------------


def test_cubic_spline_matches_three() raises:
    var track = spline()
    assert_equal(track.interpolation, CUBIC_SPLINE)
    assert_numbers(
        track.sample(at(0.3)), [0.425999999, 0.50999999, 0.0900000036]
    )
    assert_numbers(track.sample(at(1.7)), [1.026963, 0.375703692, 0.800888896])
    assert_numbers(
        track.sample(at(2.4)), [1.72903705, -0.0743703693, 0.993777752]
    )


def test_cubic_spline_holds_the_values_at_the_keys_and_ends() raises:
    var track = spline()
    assert_numbers(track.sample(at(-1)), [0, 0, 0])
    assert_numbers(track.sample(at(1)), [1, 1, 1])
    assert_numbers(track.sample(at(5)), [2, 0, 1])


def test_cubic_spline_rotation_matches_three_and_is_unit() raises:
    var track = turning()
    assert_numbers(track.sample(at(0.4)), [0, 0.321657389, 0, 0.946856141])
    var turned = track.sample_quaternion(at(0.9))
    assert_almost_equal(Float64(turned.y), 0.666056693, atol=TOLERANCE)
    assert_almost_equal(Float64(turned.w), 0.745901108, atol=TOLERANCE)
    assert_almost_equal(Float64(turned.length()), 1, atol=TOLERANCE)


def test_cubic_spline_number_track() raises:
    var track = KeyframeTrack(
        morph_target(MeshIndex(0), 1),
        seconds([0, 1]),
        in_tangents=[0, 1],
        values=[0, 2],
        out_tangents=[1, 0],
    )
    assert_equal(track.kind(), MORPH_INFLUENCE)
    assert_numbers(track.sample(at(0.5)), [1])


def test_a_cubic_spline_track_copies_its_tangents() raises:
    var track = spline()
    var copied = KeyframeTrack(copy=track)
    assert_equal(len(copied.in_tangents), 9)
    assert_equal(len(copied.out_tangents), 9)
    assert_numbers(copied.sample(at(1.7)), [1.026963, 0.375703692, 0.800888896])


def test_cubic_spline_refuses_a_flag() raises:
    with assert_raises(contains="STEP"):
        _ = KeyframeTrack(
            node_target(NodeId(0), VISIBLE),
            seconds([0]),
            in_tangents=[0],
            values=[1],
            out_tangents=[0],
        )


def test_cubic_spline_refuses_tangents_of_the_wrong_length() raises:
    with assert_raises(contains="two tangents"):
        _ = KeyframeTrack(
            morph_target(MeshIndex(0), 0),
            seconds([0]),
            in_tangents=[0, 0],
            values=[1],
            out_tangents=[0],
        )
    with assert_raises(contains="two tangents"):
        _ = KeyframeTrack(
            morph_target(MeshIndex(0), 0),
            seconds([0]),
            in_tangents=[0],
            values=[1],
            out_tangents=[],
        )


def test_cubic_spline_refuses_a_tangent_that_is_not_a_number() raises:
    with assert_raises(contains="tangents must be numbers"):
        _ = KeyframeTrack(
            morph_target(MeshIndex(0), 0),
            seconds([0]),
            in_tangents=[nan[DType.float32]()],
            values=[1],
            out_tangents=[0],
        )
    with assert_raises(contains="tangents must be numbers"):
        _ = KeyframeTrack(
            morph_target(MeshIndex(0), 0),
            seconds([0]),
            in_tangents=[0],
            values=[1],
            out_tangents=[nan[DType.float32]()],
        )


def test_cubic_spline_refuses_no_keys_and_bad_rotations() raises:
    with assert_raises(contains="at least one key"):
        _ = KeyframeTrack(
            morph_target(MeshIndex(0), 0),
            List[Duration](),
            in_tangents=[],
            values=[],
            out_tangents=[],
        )
    with assert_raises(contains="unit length"):
        _ = KeyframeTrack(
            node_target(NodeId(0), QUATERNION),
            seconds([0]),
            in_tangents=[0, 0, 0, 0],
            values=[0, 0, 0, 2],
            out_tangents=[0, 0, 0, 0],
        )


def test_sample_refuses_tangents_cut_short_afterward() raises:
    var first = spline()
    _ = first.in_tangents.pop()
    with assert_raises(contains="tangents no longer match"):
        _ = first.sample(at(0.5))
    var second = spline()
    _ = second.out_tangents.pop()
    with assert_raises(contains="tangents no longer match"):
        _ = second.sample(at(0.5))


# --- the mixer's endings ----------------------------------------------------


def one_node_scene() raises -> Scene:
    """Return a scene with one node at the origin."""
    var scene = Scene()
    _ = scene.add(Object3D())
    return scene^


def smooth_action(loop: type_of(ONCE)) raises -> AnimationAction:
    """Return an action on a clip of the uneven `SMOOTH` track."""
    return AnimationAction(AnimationClip("smooth", [uneven()]), loop)


def assert_position(scene: Scene, want: List[Float32]) raises:
    """Assert where node zero is."""
    var node = scene.get(NodeId(0))
    assert_numbers([node.position.x, node.position.y, node.position.z], want)


def test_a_once_action_reads_smooth_tracks_flat_at_both_ends() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(smooth_action(ONCE))
    mixer.action(which).play()
    assert_equal(mixer.action(which).ending_start, ZERO_CURVATURE_ENDING)
    mixer.update(scene, at(0.25))
    assert_position(scene, [0.395833333, 0.895833333, -0.458333333])
    assert_equal(mixer.action(which).ending_start, ZERO_SLOPE_ENDING)
    assert_equal(mixer.action(which).ending_end, ZERO_SLOPE_ENDING)
    mixer.update(scene, at(1))
    assert_position(scene, [2.28125, 2.15625, -1.0625])
    mixer.update(scene, at(1.5))
    assert_position(scene, [2.234375, -1.40625, 3.203125])


def test_a_once_action_without_zero_slope_reads_a_natural_spline() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(smooth_action(ONCE))
    mixer.action(which).zero_slope_at_start = False
    mixer.action(which).zero_slope_at_end = False
    mixer.action(which).play()
    mixer.update(scene, at(0.25))
    assert_position(scene, [0.520833333, 1.14583333, -0.583333333])
    mixer.update(scene, at(2.45))
    assert_position(scene, [2.3735, -1.0265, 2.695])
    assert_equal(mixer.action(which).ending_end, ZERO_CURVATURE_ENDING)


def test_a_repeat_action_wraps_the_end_it_runs_on_past() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(smooth_action(REPEAT))
    mixer.action(which).play()
    mixer.update(scene, at(0.25))
    assert_position(scene, [0.395833333, 0.895833333, -0.458333333])
    assert_equal(mixer.action(which).ending_start, ZERO_SLOPE_ENDING)
    assert_equal(mixer.action(which).ending_end, WRAP_AROUND_ENDING)
    mixer.update(scene, at(1))
    assert_position(scene, [2.28125, 2.15625, -1.0625])
    mixer.update(scene, at(1.5))
    assert_position(scene, [2.375, -1.96875, 3.90625])
    mixer.update(scene, at(0.75))
    assert_position(scene, [1, 2, -1])
    assert_equal(mixer.action(which).ending_start, WRAP_AROUND_ENDING)
    assert_equal(mixer.action(which).ending_end, WRAP_AROUND_ENDING)
    mixer.update(scene, at(0.3))
    assert_position(scene, [1.52, 2.304, -1.136])


def test_a_repeat_action_run_backward_wraps_both_ends() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(smooth_action(REPEAT))
    mixer.action(which).time_scale = -1
    mixer.action(which).play()
    mixer.update(scene, at(0.25))
    assert_position(scene, [2.375, -1.96875, 3.90625])
    assert_equal(mixer.action(which).ending_start, WRAP_AROUND_ENDING)
    assert_equal(mixer.action(which).ending_end, WRAP_AROUND_ENDING)
    mixer.update(scene, at(0.5))
    assert_position(scene, [2.9375, 0.15625, 1.09375])


def test_a_backward_start_that_has_not_wrapped_flattens_the_end() raises:
    var action = smooth_action(REPEAT)
    action.phase = 2
    action.play()
    action.advance(-0.5)
    assert_false(action.started)
    assert_equal(action.ending_start, WRAP_AROUND_ENDING)
    assert_equal(action.ending_end, ZERO_SLOPE_ENDING)


def test_a_ping_pong_action_is_flat_at_both_ends() raises:
    var scene = one_node_scene()
    var mixer = AnimationMixer()
    var which = mixer.add(smooth_action(PING_PONG))
    mixer.action(which).play()
    mixer.update(scene, at(0.25))
    mixer.update(scene, at(1))
    mixer.update(scene, at(1.5))
    assert_position(scene, [2.234375, -1.40625, 3.203125])
    mixer.update(scene, at(0.75))
    assert_position(scene, [2.58333333, -0.541666667, 2.04166667])
    mixer.update(scene, at(0.3))
    assert_position(scene, [2.93333333, 0.501333333, 0.650666667])
    assert_equal(mixer.action(which).ending_start, ZERO_SLOPE_ENDING)
    assert_equal(mixer.action(which).ending_end, ZERO_SLOPE_ENDING)


def test_stopping_an_action_starts_its_endings_again() raises:
    var action = smooth_action(REPEAT)
    action.play()
    action.advance(3.5)
    assert_true(action.started)
    var copied = AnimationAction(copy=action)
    assert_true(copied.started)
    assert_equal(copied.ending_start, WRAP_AROUND_ENDING)
    action.stop()
    assert_false(action.started)
    action.play()
    action.advance(0.1)
    assert_equal(action.ending_start, ZERO_SLOPE_ENDING)


# --- subclips and additive clips ---------------------------------------------


def test_a_subclip_keeps_a_cubic_spline_key_whole() raises:
    var clip = AnimationClip("spline", [spline()])
    var cut = subclip(clip, "tail", 30, 90, 30)
    assert_equal(cut.tracks[0].interpolation, CUBIC_SPLINE)
    assert_equal(cut.tracks[0].key_count(), 2)
    assert_numbers(cut.tracks[0].in_tangents, [-1, 0, 2, 3, 1, 0])
    assert_numbers(cut.tracks[0].out_tangents, [0.5, 0, -1, 9, 9, 9])
    assert_numbers(
        cut.tracks[0].sample(at(0.7)), [1.026963, 0.375703692, 0.800888896]
    )


def test_make_clip_additive_takes_the_curve_off_and_keeps_tangents() raises:
    var track = KeyframeTrack(
        morph_target(MeshIndex(0), 0),
        seconds([0, 1]),
        in_tangents=[0, 1],
        values=[0, 2],
        out_tangents=[1, 0],
    )
    var made = make_clip_additive(AnimationClip("bump", [track^]), 15, 30)
    # The curve at half a second is one. three.js gets not a number here;
    # see `animation.animation_utils`.
    assert_numbers(made.tracks[0].values, [-1, 1])
    assert_numbers(made.tracks[0].in_tangents, [0, 1])
    assert_numbers(made.tracks[0].out_tangents, [1, 0])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
