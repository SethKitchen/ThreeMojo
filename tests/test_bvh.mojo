# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.bvh` and `loaders.js_number`.

`assets/bvh/fixture.json` is what three.js 0.180's `BVHLoader` gives for
`assets/bvh/fixture.bvh` in node: the bones, their parents and
positions, and every track of the clip. The first test compares all of
it. Smaller files, written inline, reach every refusal.
"""

from animation.keyframe_track import POSITION, QUATERNION
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.bvh import (
    X_POSITION,
    X_ROTATION,
    Y_ROTATION,
    Z_POSITION,
    Z_ROTATION,
    BvhChannel,
    axis_rotation,
    bvh_channel,
    multiply_rotations,
    parse_bvh,
    read_bvh,
)
from loaders.js_number import js_parse_float, js_parse_int
from loaders.json import parse_json
from math.matrix4 import Matrix4
from std.math import isnan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND


def near(got: Float64, want: Float64, tolerance: Float64 = 1e-6) raises:
    """Assert two numbers agree within a tolerance relative to their size."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= tolerance * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def test_the_fixture_matches_three_js() raises:
    var scene = Scene()
    var model = read_bvh("assets/bvh/fixture.bvh", scene)
    var doc = parse_json(Path("assets/bvh/fixture.json").read_text())
    var bones = doc.get(doc.root(), "bones")
    assert_equal(len(model.nodes), doc.length(bones))
    assert_equal(model.skeleton.bone_count(), len(model.nodes))
    for i in range(len(model.nodes)):
        var want = doc.at(bones, i)
        var node = scene.get(model.nodes[i])
        assert_equal(node.name, doc.string(doc.get(want, "name")))
        var parent = doc.integer(doc.get(want, "parent"))
        if parent < 0:
            assert_true(node.parent == NO_PARENT)
        else:
            assert_true(node.parent == model.nodes[parent])
        var position = doc.get(want, "position")
        near(Float64(node.position.x), doc.number(doc.at(position, 0)))
        near(Float64(node.position.y), doc.number(doc.at(position, 1)))
        near(Float64(node.position.z), doc.number(doc.at(position, 2)))
        assert_true(model.skeleton.bones[i].inverse_bind == Matrix4())
    assert_equal(model.frame_count, 3)
    near(Float64(model.frame_time.to(SECOND)), 0.0333333)
    assert_true(Bool(model.clip))
    ref clip = model.clip.value()
    assert_equal(clip.name, doc.string(doc.get(doc.root(), "name")))
    near(
        Float64(clip.duration().to(SECOND)),
        doc.number(doc.get(doc.root(), "duration")),
    )
    var tracks = doc.get(doc.root(), "tracks")
    assert_equal(clip.track_count(), doc.length(tracks))
    for t in range(clip.track_count()):
        var want = doc.at(tracks, t)
        ref track = clip.tracks[t]
        var name = scene.get(NodeId(track.target.index)).name
        var suffix = ".position" if track.target.kind == POSITION else (
            ".quaternion"
        )
        assert_equal(name + suffix, doc.string(doc.get(want, "name")))
        var times = doc.get(want, "times")
        assert_equal(len(track.times), doc.length(times))
        for k in range(len(track.times)):
            near(Float64(track.times[k]), doc.number(doc.at(times, k)))
        var values = doc.get(want, "values")
        assert_equal(len(track.values), doc.length(values))
        for k in range(len(track.values)):
            near(Float64(track.values[k]), doc.number(doc.at(values, k)))


def test_channels_and_rotations() raises:
    assert_true(bvh_channel("Xposition") == X_POSITION)
    assert_true(bvh_channel("Zrotation") == Z_ROTATION)
    with assert_raises(contains="not known"):
        _ = bvh_channel("Wrotation")
    assert_false(BvhChannel(-1).is_valid())
    assert_false(BvhChannel(6).is_valid())
    assert_true(Y_ROTATION.is_rotation())
    assert_false(Z_POSITION.is_rotation())
    with assert_raises(contains="not one"):
        _ = axis_rotation(X_POSITION, 90)
    with assert_raises(contains="not one"):
        _ = axis_rotation(BvhChannel(9), 90)
    var q = axis_rotation(X_ROTATION, 180)
    near(q[0], 1)
    near(q[3], 0, 1e-12)
    var both = multiply_rotations(q, axis_rotation(Y_ROTATION, 180))
    near(both[2], 1)


def test_js_numbers() raises:
    near(js_parse_int("  -42.7x"), -42)
    near(js_parse_int("+7"), 7)
    assert_true(isnan(js_parse_int("x1")))
    assert_true(isnan(js_parse_int("-")))
    assert_true(isnan(js_parse_int("")))
    assert_true(isnan(js_parse_int("9" * 60)))
    near(js_parse_float("  12.5e3xyz"), 12500)
    near(js_parse_float("-.5"), -0.5)
    near(js_parse_float("+7."), 7)
    near(js_parse_float("1e"), 1)
    near(js_parse_float("1E+"), 1)
    near(js_parse_float("2E-1"), 0.2)
    assert_true(js_parse_float("Infinity") > 1e308)
    assert_true(js_parse_float("-Infinity") < -1e308)
    assert_true(isnan(js_parse_float("")))
    assert_true(isnan(js_parse_float(".")))
    assert_true(isnan(js_parse_float("abc")))
    assert_true(isnan(js_parse_float("0" * 60 + "1")))


def bvh(hierarchy: String, motion: String) -> String:
    """Return a file of a hierarchy and a motion."""
    return "HIERARCHY\n" + hierarchy + "\nMOTION\n" + motion


comptime ONE = (
    "ROOT A\n{\nOFFSET 1 2 3\nCHANNELS 2 Xposition Yrotation\n"
    + "End Site\n{\nOFFSET 0 1 0\n}\n}"
)


def test_options_and_short_files() raises:
    var scene = Scene()
    var parent = scene.add(Object3D())
    var both = parse_bvh(
        bvh(ONE, "Frames: 2\nFrame Time: 0.5\n1 90\n2 0"),
        scene,
        parent,
        False,
        True,
    )
    assert_true(scene.get(both.nodes[0]).parent == parent)
    assert_equal(both.clip.value().track_count(), 1)
    assert_true(both.clip.value().tracks[0].target.kind == QUATERNION)
    var positions = parse_bvh(
        bvh(ONE, "Frames: 2\nFrame Time: 0.5\n1 90\n2 0 extra"),
        scene,
        animate_rotations=False,
    )
    assert_equal(positions.clip.value().track_count(), 1)
    var none = parse_bvh(
        bvh(ONE, "Frames: 2\nFrame Time: 0.5\n1 90\n2 0"),
        scene,
        animate_positions=False,
        animate_rotations=False,
    )
    assert_false(Bool(none.clip))
    var one = parse_bvh(bvh(ONE, "Frames: 1\nFrame Time: 0.5\n1 90"), scene)
    assert_false(Bool(one.clip))
    var still = parse_bvh(
        bvh(ONE, "Frames: 2\nFrame Time: 0\n1 90\n1 90"), scene
    )
    assert_false(Bool(still.clip))
    var empty = parse_bvh(bvh(ONE, "Frames: -3\nFrame Time: 1"), scene)
    assert_equal(empty.frame_count, 0)
    # A joint with no channels keeps its offset in every frame.
    var fixed = parse_bvh(
        bvh(
            "ROOT A\n{\nOFFSET 0 0 0\nCHANNELS 1 Zrotation\nJOINT B\n{\n"
            + "OFFSET 0 4 0\nCHANNELS 0\n}\n}",
            "Frames: 2\nFrame Time: 1\n90\n0",
        ),
        scene,
    )
    assert_equal(fixed.clip.value().track_count(), 4)
    near(Float64(fixed.clip.value().tracks[2].values[4]), 4)


def test_refusals() raises:
    var scene = Scene()
    with assert_raises(contains="HIERARCHY expected"):
        _ = parse_bvh("ROOT A", scene)
    with assert_raises(contains="ends early"):
        _ = parse_bvh("HIERARCHY\n\n", scene)
    with assert_raises(contains="type and a name"):
        _ = parse_bvh("HIERARCHY\nROOT\n", scene)
    with assert_raises(contains="expected `{`"):
        _ = parse_bvh("HIERARCHY\nROOT A\nOFFSET 0 0 0", scene)
    with assert_raises(contains="expected OFFSET"):
        _ = parse_bvh("HIERARCHY\nROOT A\n{\nOFFSETS 0 0 0", scene)
    with assert_raises(contains="three values"):
        _ = parse_bvh("HIERARCHY\nROOT A\n{\nOFFSET 0 0", scene)
    with assert_raises(contains="OFFSET is not a number"):
        _ = parse_bvh("HIERARCHY\nROOT A\n{\nOFFSET 0 x 0", scene)
    with assert_raises(contains="expected CHANNELS"):
        _ = parse_bvh("HIERARCHY\nROOT A\n{\nOFFSET 0 0 0\n}", scene)
    with assert_raises(contains="needs a count"):
        _ = parse_bvh("HIERARCHY\nROOT A\n{\nOFFSET 0 0 0\nCHANNELS", scene)
    with assert_raises(contains="as many as it counts"):
        _ = parse_bvh(
            "HIERARCHY\nROOT A\n{\nOFFSET 0 0 0\nCHANNELS 2 Xposition", scene
        )
    with assert_raises(contains="as many as it counts"):
        _ = parse_bvh("HIERARCHY\nROOT A\n{\nOFFSET 0 0 0\nCHANNELS -1", scene)
    with assert_raises(contains="as many as it counts"):
        _ = parse_bvh("HIERARCHY\nROOT A\n{\nOFFSET 0 0 0\nCHANNELS x", scene)
    with assert_raises(contains="not known"):
        _ = parse_bvh(
            "HIERARCHY\nROOT A\n{\nOFFSET 0 0 0\nCHANNELS 1 Wrotation", scene
        )
    with assert_raises(contains="no joints under it"):
        _ = parse_bvh(
            "HIERARCHY\nROOT A\n{\nOFFSET 0 0 0\nCHANNELS 0\nEnd Site\n{\n"
            + "OFFSET 0 0 0\nJOINT B\n",
            scene,
        )
    with assert_raises(contains="MOTION expected"):
        _ = parse_bvh(bvh(ONE, "").replace("MOTION", "MOTIONS"), scene)
    with assert_raises(contains="number of frames"):
        _ = parse_bvh(bvh(ONE, "Frames:\nFrame Time: 1"), scene)
    with assert_raises(contains="number of frames"):
        _ = parse_bvh(bvh(ONE, "Frames: x\nFrame Time: 1"), scene)
    with assert_raises(contains="frame time"):
        _ = parse_bvh(bvh(ONE, "Frames: 1\nFrame Time:"), scene)
    with assert_raises(contains="frame time"):
        _ = parse_bvh(bvh(ONE, "Frames: 1\nFrame Time: x"), scene)
    with assert_raises(contains="too few values"):
        _ = parse_bvh(bvh(ONE, "Frames: 1\nFrame Time: 1\n1"), scene)
    with assert_raises(contains="frame value is not a number"):
        _ = parse_bvh(bvh(ONE, "Frames: 1\nFrame Time: 1\n1 y"), scene)
    with assert_raises(contains="ends early"):
        _ = parse_bvh(bvh(ONE, "Frames: 2\nFrame Time: 1\n1 2"), scene)
    var deep = String("HIERARCHY\n")
    for _ in range(300):
        deep += "JOINT A\n{\nOFFSET 0 0 0\nCHANNELS 0\n"
    with assert_raises(contains="nested too deep"):
        _ = parse_bvh(deep, scene)
    with assert_raises():
        _ = read_bvh("assets/bvh/missing.bvh", scene)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
