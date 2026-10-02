# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.mdd`: `assets/mdd/fixture.mdd` read as three.js
0.180's `MDDLoader` reads it, from `assets/mdd/three_mdd.mjs`."""

from animation.keyframe_track import MORPH_INFLUENCE, MeshIndex
from loaders.json import JsonDocument, parse_json
from loaders.mdd import mdd_clip, parse_mdd, read_mdd
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _reference() raises -> JsonDocument:
    """Return what three.js made of the fixture."""
    return parse_json(Path("assets/mdd/mdd.json").read_text())


def test_an_mdd_file_is_read_as_three_js_reads_it() raises:
    var model = read_mdd("assets/mdd/fixture.mdd")
    var doc = _reference()
    var targets = doc.get(doc.root(), "targets")
    var names = doc.get(doc.root(), "names")
    assert_equal(len(model.morph_targets), doc.length(targets))
    for frame in range(len(model.morph_targets)):
        assert_equal(model.names[frame], doc.string(doc.at(names, frame)))
        var want = doc.at(targets, frame)
        ref got = model.morph_targets[frame].data
        assert_equal(len(got), doc.length(want))
        for at in range(len(got)):
            assert_equal(Float64(got[at]), doc.number(doc.at(want, at)))


def test_the_clip_gives_three_js_s_weights() raises:
    var model = read_mdd("assets/mdd/fixture.mdd")
    var doc = _reference()
    var clip = mdd_clip(model, MeshIndex(2))
    assert_equal(clip.name, doc.string(doc.get(doc.root(), "clip")))
    assert_almost_equal(
        Float64(clip.length), doc.number(doc.get(doc.root(), "duration"))
    )
    var times = doc.get(doc.root(), "times")
    var values = doc.get(doc.root(), "values")
    var frames = doc.length(times)
    # three.js's one track holds every influence at each key; this port's
    # track `target` holds that influence's column.
    assert_equal(len(clip.tracks), frames)
    for target in range(frames):
        ref track = clip.tracks[target]
        assert_true(track.target.kind == MORPH_INFLUENCE)
        assert_equal(track.target.index, 2)
        assert_equal(track.target.slot, target)
        for key in range(frames):
            assert_equal(
                Float64(track.times[key]), doc.number(doc.at(times, key))
            )
            assert_equal(
                Float64(track.values[key]),
                doc.number(doc.at(values, key * frames + target)),
            )


def _file(frames: Int, points: Int, times: List[Float32]) -> List[UInt8]:
    """Return an MDD file of the frames and times, every position zero.

    Args:
        frames: The number of frames the header gives.
        points: The number of points the header gives.
        times: Each frame's time.

    Returns:
        The file.
    """
    var bytes = List[UInt8]()
    for word in [UInt32(frames), UInt32(points)]:
        for k in range(4):
            bytes.append(UInt8((word >> UInt32(24 - 8 * k)) & 255))
    for time in times:
        var word = bitcast[DType.uint32](time)
        for k in range(4):
            bytes.append(UInt8((word >> UInt32(24 - 8 * k)) & 255))
    for _ in range(frames * points * 12):
        bytes.append(0)
    return bytes^


def test_what_three_js_would_throw_on_is_refused() raises:
    with assert_raises(contains="ends inside a value, at byte 4"):
        _ = parse_mdd([0, 0, 0, 1, 0])
    var short = _file(1, 1, [0.5])
    _ = short.pop()
    with assert_raises(contains="ends inside a value, at byte 20"):
        _ = parse_mdd(short)
    with assert_raises(contains="at least one frame"):
        _ = mdd_clip(parse_mdd(_file(0, 3, [])), MeshIndex(0))
    with assert_raises(contains="longer than no time"):
        _ = mdd_clip(parse_mdd(_file(1, 1, [0])), MeshIndex(0))
    with assert_raises():
        _ = mdd_clip(parse_mdd(_file(2, 1, [1, 0.5])), MeshIndex(0))
    # A frame of no points is an empty target.
    var pointless = parse_mdd(_file(1, 0, [0.5]))
    assert_equal(len(pointless.morph_targets[0].data), 0)
    # Bytes after the last frame are stepped over.
    var long = _file(1, 1, [0.5])
    long.append(7)
    var one = parse_mdd(long)
    assert_equal(len(one.morph_targets), 1)
    assert_equal(mdd_clip(one, MeshIndex(0)).length, 0.5)


def _header(frames: UInt32, points: UInt32, time_count: Int = 0) -> List[UInt8]:
    """Build only a header and times, without allocating declared points."""
    var bytes = List[UInt8]()
    for word in [frames, points]:
        for k in range(4):
            bytes.append(UInt8((word >> UInt32(24 - 8 * k)) & 255))
    for _ in range(time_count * 4):
        bytes.append(0)
    return bytes^


def test_declared_payload_is_checked_before_allocating_points() raises:
    # These files are tiny. Never construct their declared position arrays.
    for frames in [UInt32(1), UInt32.MAX]:
        for points in [UInt32(1), UInt32.MAX]:
            with assert_raises(contains="MDD: the file ends inside a value"):
                _ = parse_mdd(_header(frames, points, 1))
    with assert_raises(contains="at byte 8"):
        _ = parse_mdd(_header(UInt32.MAX, 0))
    var empty = parse_mdd(_header(0, UInt32.MAX))
    assert_equal(len(empty.times), 0)
    assert_equal(len(empty.morph_targets), 0)


def test_payload_bounds_preserve_exact_and_trailing_data() raises:
    for frames in range(4):
        for points in range(4):
            var times = List[Float32](length=frames, fill=1)
            var bytes = _file(frames, points, times)
            var model = parse_mdd(bytes)
            assert_equal(len(model.times), frames)
            assert_equal(len(model.morph_targets), frames)
            for target in model.morph_targets:
                assert_equal(len(target.data), points * 3)
            bytes.extend([UInt8(0xFF), UInt8(0xFE), UInt8(0xFD)])
            assert_equal(len(parse_mdd(bytes).times), frames)
            if frames > 0:
                var short = _file(frames, points, times)
                _ = short.pop()
                with assert_raises(contains="ends inside a value"):
                    _ = parse_mdd(short)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
