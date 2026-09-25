# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `animation.animation_clip_creator`.

`assets/animation/three.json` holds, under `creator`, the times and values
of the clips three.js r180's `AnimationClipCreator` makes. `Math.random`
there draws from `MathUtils.seededRandom`, from the seed 7 for the shake
and 11 for the pulse: the numbers a `SeededRandom` of each gives here.
"""

from animation.animation_clip import AnimationClip
from animation.animation_clip_creator import (
    create_material_color_animation,
    create_pulsation_animation,
    create_rotation_animation,
    create_scale_axis_animation,
    create_shake_animation,
    create_visibility_animation,
)
from animation.keyframe_track import (
    MATERIAL_COLOR,
    POSITION,
    ROTATION_ELEMENT,
    SCALE,
    SCALE_ELEMENT,
    VISIBLE,
)
from core.object3d import NodeId
from loaders.json import JsonDocument, parse_json
from materials.material import MaterialId
from math.utils import SeededRandom
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Duration, SECOND

comptime TOLERANCE = Float64(1e-5)


def _check(clip: AnimationClip, name: String, length: Float32) raises:
    """Assert a clip's one track has three.js's times and values.

    Args:
        clip: The clip.
        name: Its entry under `creator`.
        length: The duration three.js gave it.

    Raises:
        Error: If they differ.
    """
    var doc = parse_json(Path("assets/animation/three.json").read_text())
    var tracks = doc.get(doc.get(doc.root(), "creator"), name)
    assert_equal(clip.track_count(), doc.length(tracks))
    assert_equal(clip.name, "")
    assert_almost_equal(clip.length, length, atol=1e-6)
    var want = doc.at(tracks, 0)
    ref track = clip.tracks[0]
    var times = doc.get(want, "times")
    assert_equal(len(track.times), doc.length(times))
    for at in range(len(track.times)):
        assert_almost_equal(
            Float64(track.times[at]),
            doc.number(doc.at(times, at)),
            atol=TOLERANCE,
        )
    var values = doc.get(want, "values")
    assert_equal(len(track.values), doc.length(values))
    for at in range(len(track.values)):
        assert_almost_equal(
            Float64(track.values[at]),
            doc.number(doc.at(values, at)),
            atol=TOLERANCE,
        )


def test_a_rotation_turns_one_axis() raises:
    var clip = create_rotation_animation(NodeId(3), Duration(2, SECOND), 1)
    _check(clip, "rotation", 2)
    assert_equal(clip.tracks[0].target.kind, ROTATION_ELEMENT)
    assert_equal(clip.tracks[0].target.slot, 1)
    assert_equal(clip.tracks[0].target.index, 3)
    # three.js's default axis is x.
    var x = create_rotation_animation(NodeId(0), Duration(1, SECOND))
    assert_equal(x.tracks[0].target.slot, 0)
    with assert_raises(contains="axis must be 0, 1 or 2"):
        _ = create_rotation_animation(NodeId(0), Duration(1, SECOND), 3)


def test_a_scale_grows_one_axis() raises:
    var clip = create_scale_axis_animation(NodeId(0), Duration(1.5, SECOND), 2)
    _check(clip, "scale_axis", 1.5)
    assert_equal(clip.tracks[0].target.kind, SCALE_ELEMENT)
    assert_equal(clip.tracks[0].target.slot, 2)


def test_a_shake_and_a_pulse_take_three_js_random_keys() raises:
    var random = SeededRandom(7)
    var shake = create_shake_animation(
        NodeId(0), Duration(0.35, SECOND), Vector3(1, 2, 3), random
    )
    _check(shake, "shake", 0.35)
    assert_equal(shake.tracks[0].target.kind, POSITION)
    var other = SeededRandom(11)
    var pulse = create_pulsation_animation(
        NodeId(0), Duration(0.25, SECOND), 4, other
    )
    _check(pulse, "pulsation", 0.25)
    assert_equal(pulse.tracks[0].target.kind, SCALE)
    # No time makes no key, and a track needs one.
    with assert_raises(contains="at least one key"):
        _ = create_shake_animation(
            NodeId(0), Duration(0, SECOND), Vector3(1, 1, 1), random
        )
    with assert_raises(contains="at least one key"):
        _ = create_pulsation_animation(NodeId(0), Duration(0, SECOND), 1, other)


def test_a_visibility_hides_the_second_half() raises:
    var clip = create_visibility_animation(NodeId(0), Duration(3, SECOND))
    _check(clip, "visibility", 3)
    assert_equal(clip.tracks[0].target.kind, VISIBLE)


def test_a_color_runs_through_the_list() raises:
    var colors: List[FloatColor] = [
        FloatColor(1, 0, 0),
        FloatColor(0, 0.5, 0),
        FloatColor(0.25, 0.25, 1),
    ]
    var clip = create_material_color_animation(
        MaterialId(1), Duration(2, SECOND), colors
    )
    _check(clip, "color", 2)
    assert_equal(clip.tracks[0].target.kind, MATERIAL_COLOR)
    assert_equal(clip.tracks[0].target.index, 1)
    # One color is one key at the start.
    var one: List[FloatColor] = [FloatColor(0, 0, 1)]
    var held = create_material_color_animation(
        MaterialId(0), Duration(2, SECOND), one
    )
    assert_equal(len(held.tracks[0].times), 1)
    assert_equal(held.tracks[0].times[0], 0)
    assert_almost_equal(held.length, 2, atol=1e-6)
    with assert_raises(contains="at least one color"):
        _ = create_material_color_animation(
            MaterialId(0), Duration(2, SECOND), List[FloatColor]()
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
