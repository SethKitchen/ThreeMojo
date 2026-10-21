# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""String animation weights select whole names instead of numeric indices."""

from animation.animation_clip import (
    AnimationClip,
    ADDITIVE_BLEND_MODE,
    NORMAL_BLEND_MODE,
)
from animation.animation_mixer import AnimationAction, AnimationMixer
from animation.animation_utils import make_clip_additive
from animation.keyframe_track import KeyframeTrack, NODE_NAME, node_target
from core.object3d import NodeId, Object3D
from core.scene import Scene
from std.testing import TestSuite, assert_equal
from units.si import Duration, SECOND


def named_scene() raises -> Scene:
    """Return one node named original."""
    var scene = Scene()
    var node = Object3D()
    node.name = "original"
    _ = scene.add(node^)
    return scene^


def add_name(
    mut mixer: AnimationMixer,
    name: String,
    weight: Float32,
    additive: Bool = False,
) raises -> Int:
    """Play a constant name track with the requested blend and weight."""
    var mode = ADDITIVE_BLEND_MODE if additive else NORMAL_BLEND_MODE
    var clip = AnimationClip(
        name,
        [
            KeyframeTrack(
                node_target(NodeId(0), NODE_NAME),
                [Duration(0, SECOND), Duration(1, SECOND)],
                [name, name],
            )
        ],
        mode,
    )
    var index = mixer.add(AnimationAction(clip^, weight=weight))
    mixer.action(index).play()
    return index


def test_make_clip_additive_keeps_string_keys_and_tables() raises:
    var target = AnimationClip(
        "names",
        [
            KeyframeTrack(
                node_target(NodeId(0), NODE_NAME),
                [Duration(0), Duration(1)],
                ["first", "second"],
            )
        ],
    )
    var reference = AnimationClip(
        "reference names",
        [
            KeyframeTrack(
                node_target(NodeId(0), NODE_NAME),
                [Duration(0), Duration(1)],
                ["reference first", "reference second"],
            )
        ],
    )
    # Reference key one is an interned-string index, not a numeric pose.
    var made = make_clip_additive(target, 30, reference, 30)
    assert_equal(made.blend_mode, ADDITIVE_BLEND_MODE)
    assert_equal(target.blend_mode, NORMAL_BLEND_MODE)
    for index in range(2):
        assert_equal(
            made.tracks[0].values[index], target.tracks[0].values[index]
        )
        assert_equal(
            made.tracks[0].strings[index], target.tracks[0].strings[index]
        )
        assert_equal(
            made.tracks[0].sample_string(Duration(Float32(index))),
            target.tracks[0].sample_string(Duration(Float32(index))),
        )
    assert_equal(made.tracks[0].sample_string(Duration(0)), "first")
    assert_equal(made.tracks[0].sample_string(Duration(1)), "second")
    assert_equal(
        reference.tracks[0].sample_string(Duration(1)), "reference second"
    )


def test_a_name_fade_selects_the_original_at_half_weight() raises:
    for weight in [Float32(0.25), Float32(0.5), Float32(0.75)]:
        var scene = named_scene()
        var mixer = AnimationMixer()
        _ = add_name(mixer, "animated", weight)
        mixer.update(scene, Duration(0, SECOND))
        assert_equal(
            scene.get(NodeId(0)).name,
            "animated" if weight > 0.5 else "original",
        )
        mixer.stop_all_action()
        mixer.update(scene, Duration(0, SECOND))
        assert_equal(scene.get(NodeId(0)).name, "original")


def test_two_name_tracks_select_by_weight_with_later_ties() raises:
    for weights in [
        (Float32(1), Float32(1)),
        (Float32(2), Float32(1)),
        (Float32(1), Float32(2)),
    ]:
        var scene = named_scene()
        var mixer = AnimationMixer()
        _ = add_name(mixer, "first", weights[0])
        _ = add_name(mixer, "second", weights[1])
        mixer.update(scene, Duration(0, SECOND))
        assert_equal(
            scene.get(NodeId(0)).name,
            "second" if weights[1] >= weights[0] else "first",
        )


def test_three_names_use_running_discrete_selection() raises:
    var scene = named_scene()
    var mixer = AnimationMixer()
    _ = add_name(mixer, "first", 1)
    _ = add_name(mixer, "second", 1)
    _ = add_name(mixer, "third", 2)
    mixer.update(scene, Duration(0, SECOND))
    assert_equal(scene.get(NodeId(0)).name, "third")


def test_additive_name_selects_from_original_at_half_weight() raises:
    for weight in [Float32(0.25), Float32(0.5), Float32(0.75)]:
        var scene = named_scene()
        var mixer = AnimationMixer()
        _ = add_name(mixer, "normal", 1)
        _ = add_name(mixer, "added", weight, True)
        mixer.update(scene, Duration(0, SECOND))
        assert_equal(
            scene.get(NodeId(0)).name, "added" if weight >= 0.5 else "original"
        )


def test_an_additive_name_pile_keeps_its_last_selected_name() raises:
    var scene = named_scene()
    var mixer = AnimationMixer()
    _ = add_name(mixer, "first", 0.75, True)
    _ = add_name(mixer, "too light", 0.25, True)
    var last = add_name(mixer, "last", 0.5, True)
    mixer.update(scene, Duration(0, SECOND))
    assert_equal(scene.get(NodeId(0)).name, "last")
    mixer.action(last).stop()
    mixer.update(scene, Duration(0, SECOND))
    assert_equal(scene.get(NodeId(0)).name, "first")
    mixer.stop_all_action()
    mixer.update(scene, Duration(0, SECOND))
    assert_equal(scene.get(NodeId(0)).name, "original")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
