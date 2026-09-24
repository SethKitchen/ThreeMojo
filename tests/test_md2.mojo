# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.md2`.

`assets/md2/fixture.json` is what three.js 0.180's `MD2Loader` gives for
`assets/md2/fixture.md2`, a model of eight frames, and
`assets/md2/many.md2`, one of ten: the geometry, the morph targets, and
each animation clip's tracks.
"""

from animation.keyframe_track import MeshIndex
from core.buffer_geometry import NORMAL, POSITION, UV
from loaders.json import JsonDocument, parse_json
from loaders.md2 import (
    Md2Animation,
    md2_animation_name,
    md2_clip,
    parse_md2,
    read_md2,
)
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND


def near(got: Float64, want: Float64) raises:
    """Assert two numbers agree to a `Float32`."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= 1e-6 * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def check(got: List[Float32], doc: JsonDocument, node: Int) raises:
    """Assert numbers match a JSON array."""
    assert_equal(len(got), doc.length(node))
    for i in range(len(got)):
        near(Float64(got[i]), doc.number(doc.at(node, i)))


def compare(file: String) raises:
    """Compare one fixture with three.js."""
    var model = read_md2("assets/md2/" + file)
    var doc = parse_json(Path("assets/md2/fixture.json").read_text())
    var want = doc.get(doc.root(), file)
    ref geometry = model.geometry
    check(
        geometry.clone_attribute(String(POSITION)).packed(),
        doc,
        doc.get(want, "position"),
    )
    check(
        geometry.clone_attribute(String(NORMAL)).packed(),
        doc,
        doc.get(want, "normal"),
    )
    check(
        geometry.clone_attribute(String(UV)).packed(), doc, doc.get(want, "uv")
    )
    var morphs = doc.get(want, "morphs")
    assert_equal(len(model.frames), doc.length(morphs))
    for i in range(len(model.frames)):
        var m = doc.at(morphs, i)
        assert_equal(model.frames[i].name, doc.string(doc.get(m, "name")))
        check(model.frames[i].positions, doc, doc.get(m, "position"))
        check(model.frames[i].normals, doc, doc.get(m, "normal"))
        if geometry.morph_count() > 0:
            check(
                geometry.morph_positions[i].packed(),
                doc,
                doc.get(m, "position"),
            )
            check(geometry.morph_normals[i].packed(), doc, doc.get(m, "normal"))
    var animations = doc.get(want, "animations")
    assert_equal(len(model.animations), doc.length(animations))
    for a in range(len(model.animations)):
        var wa = doc.at(animations, a)
        assert_equal(model.animations[a].name, doc.string(doc.get(wa, "name")))
        var tracks = doc.get(wa, "tracks")
        assert_equal(len(model.animations[a].frames), doc.length(tracks))
        if len(model.animations[a].frames) < 3:
            with assert_raises(contains="fewer than three"):
                _ = md2_clip(model, a, MeshIndex(0))
            continue

        var clip = md2_clip(model, a, MeshIndex(2))
        assert_equal(clip.name, model.animations[a].name)
        near(
            Float64(clip.duration().to(SECOND)),
            doc.number(doc.get(wa, "duration")),
        )
        for t in range(clip.track_count()):
            var wt = doc.at(tracks, t)
            ref track = clip.tracks[t]
            var frame = model.animations[a].frames[t]
            assert_equal(track.target.slot, frame)
            assert_equal(track.target.index, 2)
            assert_equal(
                ".morphTargetInfluences[" + model.frames[frame].name + "]",
                doc.string(doc.get(wt, "name")),
            )
            check(track.times, doc, doc.get(wt, "times"))
            check(track.values, doc, doc.get(wt, "values"))


def test_the_fixtures_match_three_js() raises:
    compare("fixture.md2")
    compare("many.md2")


def test_names_and_clips() raises:
    assert_equal(md2_animation_name("run12").value(), "run")
    assert_equal(md2_animation_name("a-b_1").value(), "a-b_")
    assert_equal(md2_animation_name("123").value(), "")
    assert_false(Bool(md2_animation_name("pose")))
    assert_false(Bool(md2_animation_name("")))
    assert_false(Bool(md2_animation_name("a.b1")))
    var model = read_md2("assets/md2/fixture.md2")
    with assert_raises(contains="no animation"):
        _ = md2_clip(model, 5, MeshIndex(0))
    with assert_raises(contains="no animation"):
        _ = md2_clip(model, -1, MeshIndex(0))
    with assert_raises(contains="above zero"):
        _ = md2_clip(model, 0, MeshIndex(0), 0)
    # Without the loop, a track whose first key is at zero gets no last
    # key.
    var once = md2_clip(model, 0, MeshIndex(0), 20, False)
    assert_equal(len(once.tracks[0].times), 3)
    near(Float64(once.duration().to(SECOND)), 0.1)


def i32(value: Int) -> List[UInt8]:
    """Return a little-endian 32-bit value."""
    var out = List[UInt8]()
    for k in range(4):
        out.append(UInt8((value >> (8 * k)) & 0xFF))
    return out^


def header(values: List[Int]) -> List[UInt8]:
    """Return a header of seventeen values."""
    var out = List[UInt8]()
    for v in values:
        out.extend(i32(v))
    return out^


def patched(at: Int, value: UInt8) raises -> List[UInt8]:
    """Return the fixture with one byte changed."""
    var bytes = Path("assets/md2/fixture.md2").read_bytes()
    bytes[at] = value
    return bytes^


def test_refusals() raises:
    with assert_raises(contains="ends inside a value"):
        _ = parse_md2([0, 1, 2])
    var bad = header([1, 8, 1, 1, 0, 0, 0, 0, 0, 0, 1, 68, 68, 68, 68, 68, 68])
    with assert_raises(contains="not a valid"):
        _ = parse_md2(bad)
    var version = header(
        [844121161, 7, 1, 1, 0, 0, 0, 0, 0, 0, 1, 68, 68, 68, 68, 68, 68]
    )
    with assert_raises(contains="not a valid"):
        _ = parse_md2(version)
    var size = header(
        [844121161, 8, 1, 1, 0, 0, 0, 0, 0, 0, 1, 68, 68, 68, 68, 68, 99]
    )
    with assert_raises(contains="header's end"):
        _ = parse_md2(size)
    var none = header(
        [844121161, 8, 1, 1, 0, 0, 0, 0, 0, 0, 0, 68, 68, 68, 68, 68, 68]
    )
    with assert_raises(contains="no frames"):
        _ = parse_md2(none)
    var short = header(
        [844121161, 8, 1, 1, 0, 0, 0, 0, 0, 0, 1, 68, 68, 68, 68, 68, 68]
    )
    with assert_raises(contains="ends inside a value"):
        _ = parse_md2(short)
    # The triangles start at byte 88: a vertex index, then a texture
    # coordinate index. The first frame's first normal is at byte 167.
    with assert_raises(contains="names a vertex"):
        _ = parse_md2(patched(88, 9))
    with assert_raises(contains="names a texture coordinate"):
        _ = parse_md2(patched(94, 9))
    with assert_raises(contains="past the table"):
        _ = parse_md2(patched(167, 200))
    with assert_raises():
        _ = read_md2("assets/md2/missing.md2")
    # A model of one frame and no vertices.
    var empty = header(
        [844121161, 8, 1, 1, 40, 0, 0, 0, 0, 0, 1, 68, 68, 68, 68, 108, 108]
    )
    for _ in range(24):
        empty.append(0)
    for byte in "pose".as_bytes():
        empty.append(byte)
    for _ in range(12):
        empty.append(0)
    var model = parse_md2(empty)
    assert_equal(model.geometry.vertex_count(), 0)
    assert_equal(model.frames[0].name, "pose")
    assert_equal(len(model.animations), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
