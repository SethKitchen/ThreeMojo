# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the track and clip half of the animation API three.js has
beside playback: `shift`, `scale`, `trim`, `optimize`, `validate`, string
tracks, Bezier tracks, the new kinds and targets, and the clip helpers.

The expected numbers are three.js's, from r186 run in node: the Bezier
values from `BezierInterpolant`, the kept keys from `optimize` and `trim`,
and the keys `CreateFromMorphTargetSequence` makes.
"""

from animation.animation_clip import (
    AnimationClip,
    create_clips_from_morph_target_sequences,
    create_from_morph_target_sequence,
    find_by_name,
    get_keyframe_order,
    morph_sequence_name,
    sorted_array,
)
from animation.keyframe_track import (
    BEZIER,
    CAMERA_FAR,
    CAMERA_FOV,
    CAMERA_NEAR,
    CAMERA_ZOOM,
    CUBIC_SPLINE,
    KeyframeTrack,
    LIGHT_ANGLE,
    LIGHT_COLOR,
    LIGHT_DISTANCE,
    LIGHT_INTENSITY,
    LIGHT_PENUMBRA,
    LINEAR,
    LightIndex,
    MATERIAL_COLOR,
    MATERIAL_IOR,
    MATERIAL_OPACITY,
    MATERIAL_TRANSPARENT,
    MATERIAL_WIREFRAME,
    MORPH_INFLUENCE,
    MeshIndex,
    NODE_NAME,
    ORTHOGRAPHIC_SLOT,
    OrthographicCameraIndex,
    PERSPECTIVE_SLOT,
    POSITION,
    PerspectiveCameraIndex,
    QUATERNION,
    SCALE,
    SKINNED_MORPH_INFLUENCE,
    SMOOTH,
    STEP,
    SkinnedMeshIndex,
    TrackKind,
    TrackTarget,
    VISIBLE,
    check_interpolation,
    light_target,
    material_target,
    morph_target,
    node_target,
    orthographic_camera_target,
    perspective_camera_target,
    skinned_morph_target,
    solve_bezier_parameter,
)
from core.object3d import NodeId
from materials.material import MaterialId
from std.math import nan
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


def number(times: List[Float32], values: List[Float32]) raises -> KeyframeTrack:
    """Return a linear track of one number on material zero's opacity."""
    return KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        seconds(times),
        values.copy(),
    )


def bezier() raises -> KeyframeTrack:
    """Return three.js's reference Bezier track: 0 at 0 s and 4 at 2 s,
    the first key's out control point at (0.5, 0) and the second key's in
    control point at (1.5, 4)."""
    return KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_IOR),
        seconds([0, 2]),
        in_tangents=[0, 0, 1.5, 4],
        values=[0, 4],
        out_tangents=[0.5, 0, 2, 4],
        interpolation=BEZIER,
    )


# --- kinds and targets ------------------------------------------------------


def test_the_new_kinds_say_what_they_drive() raises:
    assert_true(TrackKind(39).is_valid())
    assert_false(TrackKind(40).is_valid())
    assert_true(NODE_NAME.is_node())
    assert_true(NODE_NAME.is_string())
    assert_true(NODE_NAME.is_discrete())
    assert_true(SKINNED_MORPH_INFLUENCE.is_morph())
    assert_true(SKINNED_MORPH_INFLUENCE.is_skinned())
    assert_false(MORPH_INFLUENCE.is_skinned())
    assert_true(MATERIAL_TRANSPARENT.is_material())
    assert_true(MATERIAL_WIREFRAME.is_boolean())
    assert_true(MATERIAL_WIREFRAME.is_discrete())
    assert_false(MATERIAL_OPACITY.is_discrete())
    assert_true(LIGHT_PENUMBRA.is_light())
    assert_false(CAMERA_FOV.is_light())
    assert_true(CAMERA_FAR.is_camera())
    assert_false(LIGHT_PENUMBRA.is_camera())
    assert_equal(CAMERA_ZOOM.component_count(), 1)
    assert_equal(NODE_NAME.component_count(), 1)


def test_every_kind_has_three_js_value_type_name() raises:
    assert_equal(POSITION.value_type_name(), "vector")
    assert_equal(SCALE.value_type_name(), "vector")
    assert_equal(QUATERNION.value_type_name(), "quaternion")
    assert_equal(VISIBLE.value_type_name(), "bool")
    assert_equal(NODE_NAME.value_type_name(), "string")
    assert_equal(LIGHT_COLOR.value_type_name(), "color")
    assert_equal(CAMERA_FOV.value_type_name(), "number")
    assert_equal(TrackKind(9).value_type_name(), "")


def test_the_new_indices_are_checked() raises:
    assert_true(SkinnedMeshIndex(0).is_valid())
    assert_false(SkinnedMeshIndex(-1).is_valid())
    assert_true(PerspectiveCameraIndex(0).is_valid())
    assert_false(PerspectiveCameraIndex(-1).is_valid())
    assert_true(OrthographicCameraIndex(0).is_valid())
    assert_false(OrthographicCameraIndex(-1).is_valid())


def test_a_camera_target_fits_its_list() raises:
    assert_true(TrackTarget(CAMERA_FOV, 0, PERSPECTIVE_SLOT).is_valid())
    assert_false(TrackTarget(CAMERA_FOV, 0, ORTHOGRAPHIC_SLOT).is_valid())
    assert_true(TrackTarget(CAMERA_ZOOM, 0, ORTHOGRAPHIC_SLOT).is_valid())
    assert_false(TrackTarget(CAMERA_ZOOM, 0, 2).is_valid())
    assert_true(TrackTarget(SKINNED_MORPH_INFLUENCE, 0, 7).is_valid())
    assert_false(TrackTarget(LIGHT_DISTANCE, 0, 1).is_valid())


def test_the_new_target_functions_take_their_ids() raises:
    var skin = skinned_morph_target(SkinnedMeshIndex(2), 3)
    assert_equal(skin.kind, SKINNED_MORPH_INFLUENCE)
    assert_equal(skin.index, 2)
    assert_equal(skin.slot, 3)
    with assert_raises(contains="eight"):
        _ = skinned_morph_target(SkinnedMeshIndex(0), -1)
    with assert_raises(contains="eight"):
        _ = skinned_morph_target(SkinnedMeshIndex(0), 8)
    var eye = perspective_camera_target(PerspectiveCameraIndex(1), CAMERA_FOV)
    assert_equal(eye.slot, PERSPECTIVE_SLOT)
    with assert_raises(contains="drives a camera"):
        _ = perspective_camera_target(PerspectiveCameraIndex(0), POSITION)
    var lens = orthographic_camera_target(
        OrthographicCameraIndex(1), CAMERA_NEAR
    )
    assert_equal(lens.slot, ORTHOGRAPHIC_SLOT)
    with assert_raises(contains="zoom, near or far"):
        _ = orthographic_camera_target(OrthographicCameraIndex(0), POSITION)
    with assert_raises(contains="zoom, near or far"):
        _ = orthographic_camera_target(OrthographicCameraIndex(0), CAMERA_FOV)
    assert_equal(light_target(LightIndex(0), LIGHT_ANGLE).kind, LIGHT_ANGLE)
    assert_equal(
        material_target(MaterialId(0), MATERIAL_WIREFRAME).kind,
        MATERIAL_WIREFRAME,
    )


def test_a_discrete_kind_is_step_alone() raises:
    check_interpolation(NODE_NAME, STEP)
    check_interpolation(MATERIAL_OPACITY, LINEAR)
    with assert_raises(contains="must be STEP"):
        check_interpolation(MATERIAL_TRANSPARENT, LINEAR)


# --- building tracks --------------------------------------------------------


def test_a_track_of_numbers_refuses_a_string_kind_and_missing_tangents() raises:
    with assert_raises(contains="takes strings"):
        _ = KeyframeTrack(node_target(NodeId(0), NODE_NAME), seconds([0]), [0])
    with assert_raises(contains="needs tangents"):
        _ = KeyframeTrack(
            material_target(MaterialId(0), MATERIAL_OPACITY),
            seconds([0, 1]),
            [0, 1],
            CUBIC_SPLINE,
        )
    with assert_raises(contains="needs tangents"):
        _ = KeyframeTrack(
            material_target(MaterialId(0), MATERIAL_OPACITY),
            seconds([0, 1]),
            [0, 1],
            BEZIER,
        )


def test_a_track_with_tangents_is_checked() raises:
    var target = material_target(MaterialId(0), MATERIAL_IOR)
    with assert_raises(contains="fits its slot"):
        _ = KeyframeTrack(
            TrackTarget(TrackKind(9), 0, 0),
            seconds([0]),
            in_tangents=[0],
            values=[0],
            out_tangents=[0],
        )
    with assert_raises(contains="CUBIC_SPLINE or BEZIER"):
        _ = KeyframeTrack(
            target,
            seconds([0]),
            in_tangents=[0],
            values=[1.5],
            out_tangents=[0],
            interpolation=STEP,
        )
    with assert_raises(contains="two control points"):
        _ = KeyframeTrack(
            target,
            seconds([0]),
            in_tangents=[0],
            values=[1.5],
            out_tangents=[0, 0],
            interpolation=BEZIER,
        )
    with assert_raises(contains="two control points"):
        _ = KeyframeTrack(
            target,
            seconds([0]),
            in_tangents=[0, 0],
            values=[1.5],
            out_tangents=[0],
            interpolation=BEZIER,
        )
    with assert_raises(contains="tangents must be numbers"):
        _ = KeyframeTrack(
            target,
            seconds([0]),
            in_tangents=[nan[DType.float32](), 0],
            values=[1.5],
            out_tangents=[0, 0],
            interpolation=BEZIER,
        )
    with assert_raises(contains="tangents must be numbers"):
        _ = KeyframeTrack(
            target,
            seconds([0]),
            in_tangents=[0, 0],
            values=[1.5],
            out_tangents=[0, nan[DType.float32]()],
            interpolation=BEZIER,
        )
    # No keys and no tangents: the tangent loop runs no times, and the
    # keys are refused after it.
    with assert_raises(contains="at least one key"):
        _ = KeyframeTrack(
            target,
            List[Duration](),
            in_tangents=List[Float32](),
            values=List[Float32](),
            out_tangents=List[Float32](),
            interpolation=BEZIER,
        )


def test_a_string_track_keeps_each_string_once() raises:
    var name = node_target(NodeId(0), NODE_NAME)
    var track = KeyframeTrack(name, seconds([0, 1, 2]), ["a", "b", "a"])
    assert_equal(track.interpolation, STEP)
    assert_equal(len(track.strings), 2)
    assert_equal(track.values[2], 0)
    var keys = track.key_strings()
    assert_equal(keys[1], "b")
    assert_equal(keys[2], "a")
    assert_equal(track.sample_string(at(1.5)), "b")
    assert_equal(track.sample_string(at(5)), "a")
    with assert_raises(contains="fits its slot"):
        _ = KeyframeTrack(TrackTarget(TrackKind(9), 0, 0), seconds([0]), ["a"])
    with assert_raises(contains="Only a string track takes strings"):
        _ = KeyframeTrack(node_target(NodeId(0), VISIBLE), seconds([0]), ["a"])
    with assert_raises(contains="one value for every key"):
        _ = KeyframeTrack(name, seconds([0, 1]), ["a"])
    with assert_raises(contains="at least one key"):
        _ = KeyframeTrack(name, List[Duration](), List[String]())


def test_a_string_track_refuses_a_key_that_names_nothing() raises:
    var track = KeyframeTrack(
        node_target(NodeId(0), NODE_NAME), seconds([0, 1]), ["a", "b"]
    )
    with assert_raises(contains="Only a string track's keys"):
        _ = number([0], [1]).key_strings()
    with assert_raises(contains="Only a string track's value"):
        _ = number([0], [1]).sample_string(at(0))
    var edited = track.copy()
    edited.values[0] = 0.5
    with assert_raises(contains="names no string"):
        _ = edited.key_strings()
    edited.values[0] = -1
    with assert_raises(contains="names no string"):
        _ = edited.key_strings()
    with assert_raises(contains="names no string"):
        _ = edited.sample_string(at(0))
    edited.values[0] = 5
    with assert_raises(contains="names no string"):
        _ = edited.key_strings()
    with assert_raises(contains="names no string"):
        _ = edited.sample_string(at(0))
    edited.values = List[Float32]()
    assert_equal(len(edited.key_strings()), 0)
    assert_equal(track.value_size(), 1)


# --- Bezier -----------------------------------------------------------------


def test_a_bezier_track_matches_three_js() raises:
    var track = bezier()
    var expected: List[Float64] = [0.234318, 0.729425, 2.0, 3.270576, 3.954544]
    var times: List[Float32] = [0.25, 0.5, 1, 1.5, 1.9]
    for index in range(len(times)):
        assert_almost_equal(
            Float64(track.sample(at(times[index]))[0]),
            expected[index],
            atol=TOLERANCE,
        )


def test_a_bezier_search_stops_on_a_flat_curve() raises:
    # Control times of 0 and 1 over keys at 0 and 1 make the curve flat at
    # both ends. From 0.9 the first step overshoots past one, and the
    # slope there is nothing, so the search takes no step.
    assert_almost_equal(solve_bezier_parameter(0.9, 0, 0, 1, 1), 1.0, atol=0.2)
    # An exact start stops at once.
    assert_equal(solve_bezier_parameter(0.5, 0, 0.25, 0.75, 1), 0.5)


def test_a_bezier_rotation_is_made_of_unit_length() raises:
    var turn = KeyframeTrack(
        node_target(NodeId(0), QUATERNION),
        seconds([0, 1]),
        in_tangents=[0, 0, 0, 0, 0, 0, 0, 1, 0.5, 0, 0.5, 0, 0.5, 0, 0.5, 1],
        values=[0, 0, 0, 1, 0, 0, 1, 0],
        out_tangents=[0.5, 0, 0.5, 0, 0.5, 0, 0.5, 1, 1, 0, 1, 0, 1, 1, 1, 0],
        interpolation=BEZIER,
    )
    var mid = turn.sample_quaternion(at(0.5))
    assert_almost_equal(Float64(mid.length()), 1, atol=TOLERANCE)


# --- shift, scale, trim, optimize, validate --------------------------------


def test_shift_moves_every_key_and_control_point() raises:
    var track = bezier()
    track.shift(at(1))
    assert_equal(track.times[0], 1)
    assert_equal(track.times[1], 3)
    assert_equal(track.out_tangents[0], 1.5)
    assert_equal(track.in_tangents[2], 2.5)
    assert_almost_equal(
        Float64(track.sample(at(1.25))[0]), 0.234318, atol=TOLERANCE
    )
    var plain = number([1, 2], [0, 1])
    plain.shift(at(-1))
    assert_equal(plain.times[0], 0)
    with assert_raises(contains="cannot be negative"):
        plain.shift(at(-0.5))
    with assert_raises(contains="not a number"):
        plain.shift(at(nan[DType.float32]()))
    var empty = number([0], [1])
    empty.times = List[Float32]()
    with assert_raises(contains="removed"):
        empty.shift(at(1))
    # A Bezier track whose control points were emptied shifts its keys.
    var bare = bezier()
    bare.in_tangents = List[Float32]()
    bare.out_tangents = List[Float32]()
    bare.shift(at(1))
    assert_equal(bare.times[1], 3)


def test_scale_multiplies_the_times() raises:
    var track = bezier()
    track.scale(2)
    assert_equal(track.times[1], 4)
    assert_equal(track.out_tangents[0], 1)
    assert_equal(track.out_tangents[1], 0)
    assert_almost_equal(
        Float64(track.sample(at(0.5))[0]), 0.234318, atol=TOLERANCE
    )
    var spline = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_IOR),
        seconds([0, 1]),
        in_tangents=[0, 2],
        values=[1.5, 2],
        out_tangents=[4, 0],
    )
    var before = spline.sample(at(0.5))[0]
    spline.scale(2)
    # A tangent is value per second, so the curve keeps its shape.
    assert_almost_equal(
        Float64(spline.sample(at(1))[0]), Float64(before), atol=TOLERANCE
    )
    assert_equal(spline.out_tangents[0], 2)
    var plain = number([0, 1], [0, 1])
    plain.scale(3)
    assert_equal(plain.times[1], 3)
    with assert_raises(contains="above zero"):
        plain.scale(0)
    with assert_raises(contains="above zero"):
        plain.scale(nan[DType.float32]())
    var bare = bezier()
    bare.in_tangents = List[Float32]()
    bare.out_tangents = List[Float32]()
    bare.times = List[Float32]()
    bare.scale(2)
    var flat = spline.copy()
    flat.in_tangents = List[Float32]()
    flat.out_tangents = List[Float32]()
    flat.scale(2)
    assert_equal(flat.times[1], 4)


def test_trim_keeps_the_keys_in_range_as_three_js_does() raises:
    var track = number([0, 1, 2, 3], [0, 1, 2, 3])
    track.trim(at(0.5), at(2.5))
    assert_equal(len(track.times), 2)
    assert_equal(track.times[0], 1)
    assert_equal(track.values[1], 2)
    # Every key before the range: the last is kept.
    var after = number([0, 1, 2, 3], [0, 1, 2, 3])
    after.trim(at(5), at(6))
    assert_equal(len(after.times), 1)
    assert_equal(after.values[0], 3)
    # Every key after the range: the first is kept.
    var before = number([1, 2, 3], [1, 2, 3])
    before.trim(at(0), at(0.5))
    assert_equal(len(before.times), 1)
    assert_equal(before.values[0], 1)
    # A range holding every key leaves the track as it is.
    var whole = number([0, 1], [0, 1])
    whole.trim(at(0), at(1))
    assert_equal(len(whole.times), 2)
    # A range that cuts only the start.
    var tail = number([0, 1, 2], [0, 1, 2])
    tail.trim(at(0.5), at(10))
    assert_equal(len(tail.times), 2)
    # The tangents of the keys kept are kept.
    var curve = bezier()
    curve.trim(at(1), at(3))
    assert_equal(len(curve.in_tangents), 2)
    assert_equal(curve.in_tangents[0], 1.5)
    with assert_raises(contains="not a number"):
        track.trim(at(nan[DType.float32]()), at(1))
    with assert_raises(contains="not a number"):
        track.trim(at(0), at(nan[DType.float32]()))
    var broken = number([0, 1], [0, 1])
    broken.values = List[Float32]()
    with assert_raises(contains="no longer match"):
        broken.trim(at(0), at(1))


def test_optimize_drops_the_keys_three_js_drops() raises:
    var track = number([0, 1, 2, 3, 4, 5, 6, 7], [0, 0, 0, 1, 1, 1, 0, 0])
    track.optimize()
    var times: List[Float32] = [0, 2, 3, 5, 6, 7]
    var values: List[Float32] = [0, 0, 1, 1, 0, 0]
    assert_equal(len(track.times), len(times))
    for index in range(len(times)):
        assert_equal(track.times[index], times[index])
        assert_equal(track.values[index], values[index])
    # A smooth track keeps every key.
    var smooth = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        seconds([0, 1, 2]),
        [0, 0, 0],
        SMOOTH,
    )
    smooth.optimize()
    assert_equal(len(smooth.times), 3)
    # A key the same as the one before but not the one after stays.
    var rising = number([0, 1, 2], [0, 0, 1])
    rising.optimize()
    assert_equal(len(rising.times), 3)
    # One key, and two, are kept as they are.
    var single = number([0], [1])
    single.optimize()
    assert_equal(len(single.times), 1)
    var pair = number([0, 1], [1, 1])
    pair.optimize()
    assert_equal(len(pair.times), 2)
    var broken = number([0, 1], [0, 1])
    broken.times = List[Float32]()
    with assert_raises(contains="removed"):
        broken.optimize()


def test_optimize_keeps_a_key_whose_tangents_differ() raises:
    var target = material_target(MaterialId(0), MATERIAL_IOR)
    var same = KeyframeTrack(
        target,
        seconds([0, 1, 2]),
        in_tangents=[0, 0, 0],
        values=[1.5, 1.5, 1.5],
        out_tangents=[0, 0, 0],
    )
    same.optimize()
    assert_equal(len(same.times), 2)
    assert_equal(len(same.in_tangents), 2)
    var bent_in = KeyframeTrack(
        target,
        seconds([0, 1, 2]),
        in_tangents=[0, 1, 0],
        values=[1.5, 1.5, 1.5],
        out_tangents=[0, 0, 0],
    )
    bent_in.optimize()
    assert_equal(len(bent_in.times), 3)
    var bent_out = KeyframeTrack(
        target,
        seconds([0, 1, 2]),
        in_tangents=[0, 0, 0],
        values=[1.5, 1.5, 1.5],
        out_tangents=[0, 1, 0],
    )
    bent_out.optimize()
    assert_equal(len(bent_out.times), 3)


def test_validate_answers_what_the_constructors_check() raises:
    assert_true(number([0, 1], [0, 1]).validate())
    assert_true(bezier().validate())
    var spline = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_IOR),
        seconds([0, 1]),
        in_tangents=[0, 0],
        values=[1.5, 2],
        out_tangents=[0, 0],
    )
    assert_true(spline.validate())
    var name = KeyframeTrack(
        node_target(NodeId(0), NODE_NAME), seconds([0]), ["a"]
    )
    assert_true(name.validate())
    var falling = number([0, 1], [0, 1])
    falling.times[1] = -1
    assert_false(falling.validate())
    var empty = number([0, 1], [0, 1])
    empty.times = List[Float32]()
    assert_false(empty.validate())
    name.values[0] = 3
    assert_false(name.validate())


def test_a_track_whose_tangents_were_edited_is_refused() raises:
    var curve = bezier()
    curve.in_tangents = [0]
    with assert_raises(contains="tangents no longer match"):
        _ = curve.sample(at(1))
    var other = bezier()
    other.out_tangents = [0]
    with assert_raises(contains="tangents no longer match"):
        _ = other.sample(at(1))


# --- clips ------------------------------------------------------------------


def test_a_clip_can_be_given_a_length() raises:
    var clip = AnimationClip("c", [number([0, 1], [0, 1])], duration=at(3))
    assert_equal(clip.duration().to(SECOND), 3)
    clip.reset_duration()
    assert_equal(clip.duration().to(SECOND), 1)
    var still = AnimationClip("s", [number([0], [1])], duration=at(2))
    assert_equal(still.duration().to(SECOND), 2)
    with assert_raises(contains="must be a number"):
        _ = AnimationClip(
            "c", [number([0, 1], [0, 1])], duration=at(nan[DType.float32]())
        )
    with assert_raises(contains="longer than no time"):
        _ = AnimationClip("c", [number([0, 1], [0, 1])], duration=at(0))
    with assert_raises(contains="longer than no time"):
        still.reset_duration()
    var gone = AnimationClip("g", [number([0, 1], [0, 1])])
    gone.tracks = List[KeyframeTrack]()
    with assert_raises(contains="longer than no time"):
        gone.reset_duration()
    assert_true(gone.validate())


def test_a_clip_trims_optimizes_and_validates_its_tracks() raises:
    var clip = AnimationClip(
        "c",
        [number([0, 1, 2, 3], [0, 0, 0, 1]), number([0, 1], [1, 1])],
        duration=at(2),
    )
    clip.trim()
    assert_equal(len(clip.tracks[0].times), 3)
    clip.optimize()
    assert_equal(len(clip.tracks[0].times), 2)
    assert_true(clip.validate())
    clip.tracks[1].times[1] = 0
    assert_false(clip.validate())


def test_find_by_name_finds_the_first() raises:
    var clips = List[AnimationClip]()
    assert_false(Bool(find_by_name(clips, "walk")))
    clips.append(AnimationClip("run", [number([0, 1], [0, 1])]))
    clips.append(AnimationClip("walk", [number([0, 1], [0, 1])]))
    clips.append(AnimationClip("walk", [number([0, 2], [0, 1])]))
    assert_equal(find_by_name(clips, "walk").value(), 1)
    assert_false(Bool(find_by_name(clips, "jump")))


def test_keyframe_order_is_stable() raises:
    var order = get_keyframe_order([2, 0, 1, 0])
    assert_equal(order[0], 1)
    assert_equal(order[1], 3)
    assert_equal(order[2], 2)
    assert_equal(order[3], 0)
    assert_equal(len(get_keyframe_order(List[Float32]())), 0)
    var sorted = sorted_array([10, 11, 20, 21], 2, [1, 0])
    assert_equal(sorted[0], 20)
    assert_equal(sorted[3], 11)
    assert_equal(len(sorted_array([1], 0, [0])), 0)
    assert_equal(len(sorted_array([1], 1, List[Int]())), 0)


def _check_keys(
    track: KeyframeTrack, times: List[Float32], values: List[Float32]
) raises:
    """Assert a track's keys, times at a tolerance."""
    assert_equal(len(track.times), len(times))
    for index in range(len(times)):
        assert_almost_equal(
            Float64(track.times[index]), Float64(times[index]), atol=TOLERANCE
        )
        assert_equal(track.values[index], values[index])


def test_a_morph_target_sequence_matches_three_js() raises:
    var four = List[TrackTarget]()
    for slot in range(4):
        four.append(morph_target(MeshIndex(0), slot))
    var clip = create_from_morph_target_sequence("s", four, 10)
    assert_almost_equal(clip.duration().to(SECOND), 0.4, atol=TOLERANCE)
    _check_keys(clip.tracks[0], [0, 0.1, 0.3, 0.4], [1, 0, 0, 1])
    _check_keys(clip.tracks[1], [0, 0.1, 0.2, 0.4], [0, 1, 0, 0])
    # No key at frame zero, so no key closes the loop.
    _check_keys(clip.tracks[2], [0.1, 0.2, 0.3], [0, 1, 0])
    _check_keys(clip.tracks[3], [0, 0.2, 0.3, 0.4], [0, 0, 1, 0])
    var three = List[TrackTarget]()
    for slot in range(3):
        three.append(morph_target(MeshIndex(0), slot))
    var open = create_from_morph_target_sequence("o", three, 10, no_loop=True)
    _check_keys(open.tracks[0], [0, 0.1, 0.2], [1, 0, 0])
    # Two targets: three.js makes keys at one time, and the later stands.
    var two: List[TrackTarget] = [
        skinned_morph_target(SkinnedMeshIndex(0), 0),
        skinned_morph_target(SkinnedMeshIndex(0), 1),
    ]
    var pair = create_from_morph_target_sequence("p", two, 10)
    _check_keys(pair.tracks[0], [0, 0.1, 0.2], [1, 0, 1])
    _check_keys(pair.tracks[1], [0, 0.1, 0.2], [0, 1, 0])
    with assert_raises(contains="frame rate"):
        _ = create_from_morph_target_sequence("s", four, 0)
    with assert_raises(contains="frame rate"):
        _ = create_from_morph_target_sequence("s", four, nan[DType.float32]())
    with assert_raises(contains="at least one target"):
        _ = create_from_morph_target_sequence("s", List[TrackTarget](), 10)
    with assert_raises(contains="morph targets only"):
        _ = create_from_morph_target_sequence(
            "s", [node_target(NodeId(0), POSITION)], 10
        )


def test_morph_names_sort_into_animations() raises:
    assert_equal(morph_sequence_name("Walk_001").value(), "Walk_")
    assert_equal(morph_sequence_name("crdeath0059").value(), "crdeath")
    assert_equal(morph_sequence_name("a-1").value(), "a-")
    assert_equal(morph_sequence_name("123").value(), "")
    assert_false(Bool(morph_sequence_name("idle")))
    assert_false(Bool(morph_sequence_name("a.b1")))
    var names: List[String] = [
        "Walk_001",
        "Walk_002",
        "Run_001",
        "idle",
        "Walk_003",
        "a.b1",
    ]
    var targets = List[TrackTarget]()
    for slot in range(len(names)):
        targets.append(morph_target(MeshIndex(0), slot))
    var clips = create_clips_from_morph_target_sequences(names, targets, 30)
    assert_equal(len(clips), 2)
    assert_equal(clips[0].name, "Walk_")
    assert_equal(clips[0].track_count(), 3)
    assert_equal(clips[0].tracks[2].target.slot, 4)
    assert_equal(clips[1].name, "Run_")
    assert_equal(
        len(
            create_clips_from_morph_target_sequences(
                List[String](), List[TrackTarget](), 30
            )
        ),
        0,
    )
    with assert_raises(contains="one target a name"):
        _ = create_clips_from_morph_target_sequences(
            names, List[TrackTarget](), 30
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
