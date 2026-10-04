# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Small synthetic inputs for the converted ICTF and THRS contract."""

from extensions.humanoid.skeleton.head.face_model import FaceModel
from extensions.humanoid.skeleton.head.hair.styles import HairStyleFile
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises
from test_scratch import TestScratch, temporary_path


def _put(mut bytes: List[UInt8], at: Int, value: Int, width: Int = 4):
    for k in range(width):
        bytes[at + k] = UInt8((value >> (k * 8)) & 255)


def _face() -> List[UInt8]:
    # Three vertices, three drawn vertices, one triangle in each domain,
    # one edge and one hole, three kept vertices and three followers.
    # One expression moves one vertex. One identity moves all three.
    var bytes = List[UInt8](length=240, fill=0)
    _put(bytes, 0, 0x46544349)
    var counts: List[Int] = [6, 3, 3, 1, 1, 1, 1, 1, 1, 3, 1, 20, 3, 1, 3]
    for k in range(len(counts)):
        _put(bytes, 4 + 4 * k, counts[k])
    # Neutral and UV values are zero. Index arrays begin at 124.
    var shorts: List[Int] = [
        0,
        1,
        2,  # drawn positions
        0,
        1,
        2,  # drawn triangle
        0,
        1,
        2,  # skin triangle
        0,
        1,  # skin edge
        3,  # hole length
        0,
        1,
        2,  # hole corners
        0,
        1,
        2,  # coarse triangle in skin domain
        0,
        1,
        2,  # kept vertices
        0,
        1,  # coarse edge in kept domain
        0,
        1,
        2,
        0,
        1,
        2,
        0,
        1,
        2,  # followed corners in kept domain
    ]
    for k in range(len(shorts)):
        _put(bytes, 124 + k * 2, shorts[k], 2)
    # Shorts end at 188, follower weights at 212, expression at 212.
    bytes[212] = 1
    bytes[213] = 97
    _put(bytes, 216, 1)
    _put(bytes, 220, 0x3F800000)
    _put(bytes, 232, 0x3F800000)
    # The identity needs 16 bytes (scale + nine signed bytes + padding).
    bytes.extend(List[UInt8](length=8, fill=0))
    return bytes^


def _write(bytes: List[UInt8]) raises -> String:
    var path = temporary_path("converted.bin")
    Path(path).write_bytes(bytes)
    return path


def _bad_face(bytes: List[UInt8], message: String) raises:
    with assert_raises(contains=message):
        _ = FaceModel(_write(bytes))


def test_small_face_and_lazy_prefix() raises:
    var bytes = _face()
    var model = FaceModel(_write(bytes))
    assert_equal(model.vertex_count(), 3)
    assert_equal(model.expressions(), 1)
    assert_equal(model.identities(), 1)
    assert_equal(len(model.hole(0)), 3)
    # Invalid unrequested mode data is not certified by a prefix-only load.
    _put(bytes, 232, 0x7FC00000)
    _ = FaceModel(_write(bytes), 0, True)
    _bad_face(bytes, "finite")
    # A skipped expression is still checked when identity reads cross it.
    _put(bytes, 232, 0x3F800000)
    _put(bytes, 220, 0x7FC00000)
    _ = FaceModel(_write(bytes), 0, False)
    with assert_raises(contains="finite"):
        _ = FaceModel(_write(bytes), 1, False)


def test_every_face_float_section_and_scale() raises:
    var positions: List[Int] = [100, 188, 220, 232]
    for at in range(64, 100, 4):
        positions.append(at)
    var nonfinite: List[Int] = [0x7F800000, 0xFF800000, 0x7FC00001]
    for at in positions:
        for value in nonfinite:
            var bytes = _face()
            _put(bytes, at, value)
            _bad_face(bytes, "finite")
    var scales: List[Int] = [220, 232]
    var invalid_scales: List[Int] = [0xBF800000, 0x7F7FFFFF]
    for at in scales:
        for value in invalid_scales:
            var bytes = _face()
            _put(bytes, at, value)
            _bad_face(bytes, "range")


def test_every_face_index_domain() raises:
    var arrays: List[Int] = [124, 130, 136, 142, 148, 154, 160, 166, 170, 224]
    for at in range(172, 188, 2):
        arrays.append(at)
    for at in arrays:
        var bytes = _face()
        _put(bytes, at, 3, 2)
        _bad_face(bytes, "index")
    var repeated = _face()
    _put(repeated, 162, 0, 2)
    _bad_face(repeated, "repeats")
    # In-range skin references still require membership in the kept set.
    var remapped: List[Int] = [148, 154]
    for at in remapped:
        var original = _face()
        var missing = List[UInt8]()
        for k in range(100):
            missing.append(original[k])
        missing.extend(List[UInt8](length=12, fill=0))
        for k in range(100, len(original)):
            missing.append(original[k])
        _put(missing, 8, 4)
        _put(missing, at + 12, 3, 2)
        _bad_face(missing, "missing")


def test_face_counts_and_sections_are_bounded() raises:
    var counts: List[Int] = [8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 52, 56, 60]
    for at in counts:
        var bytes = _face()
        _put(bytes, at, 0xFFFFFFFF)
        _bad_face(bytes, "limit")
    var domains: List[Int] = [8, 12, 52, 60]
    for at in domains:
        var bytes = _face()
        _put(bytes, at, 65537)
        _bad_face(bytes, "limit")
    for at in range(20, 28, 4):
        var bytes = _face()
        _put(bytes, at, 1025)
        _bad_face(bytes, "limit")
    var bytes = _face()
    _put(bytes, 48, 0xFFFFFFFF)
    _bad_face(bytes, "limit")
    bytes = _face()
    _put(bytes, 8, 65536)
    _put(bytes, 20, 1024)
    _bad_face(bytes, "byte limit")
    bytes = _face()
    _put(bytes, 48, 16)
    _bad_face(bytes, "inconsistent bytes")
    bytes = _face()
    _put(bytes, 48, 24)
    _bad_face(bytes, "inconsistent bytes")
    bytes = _face()
    _put(bytes, 216, 65537)
    _bad_face(bytes, "limit")
    var coarse_counts: List[Int] = [52, 60]
    for at in coarse_counts:
        bytes = _face()
        _put(bytes, at, 4)
        _bad_face(bytes, "inconsistent counts")
    var empty_hole = List[UInt8](length=68, fill=0)
    _put(empty_hole, 0, 0x46544349)
    _put(empty_hole, 4, 6)
    _put(empty_hole, 36, 1)
    _bad_face(empty_hole, "at least three")
    # Every byte boundary of this small valid file can truncate safely.
    var complete = _face()
    for length in range(len(complete)):
        var truncated = List[UInt8]()
        for k in range(length):
            truncated.append(complete[k])
        with assert_raises():
            _ = FaceModel(_write(truncated))


def _hair() -> List[UInt8]:
    var bytes = List[UInt8](length=40, fill=0)
    _put(bytes, 0, 0x53524854)
    _put(bytes, 4, 1)
    _put(bytes, 8, 1)
    _put(bytes, 12, 2)
    _put(bytes, 16, 0x3F800000)
    return bytes^


def test_hair_limits_scales_and_exact_length() raises:
    var bytes = _hair()
    assert_equal(HairStyleFile(_write(bytes)).points, 2)
    var bad: List[Int] = [
        0x7FC00001,
        0x7F800000,
        0xFF800000,
        0xBF800000,
        0x7F7FFFFF,
    ]
    for value in bad:
        bytes = _hair()
        _put(bytes, 16, value)
        with assert_raises(contains="scale"):
            _ = HairStyleFile(_write(bytes))
    for at in range(8, 16, 4):
        bytes = _hair()
        _put(bytes, at, 0xFFFFFFFF)
        with assert_raises(contains="limit"):
            _ = HairStyleFile(_write(bytes))
    bytes = _hair()
    _put(bytes, 8, 65536)
    _put(bytes, 12, 256)
    with assert_raises(contains="point total"):
        _ = HairStyleFile(_write(bytes))
    bytes = _hair()
    bytes.append(0)
    with assert_raises(contains="trailing"):
        _ = HairStyleFile(_write(bytes))
    var complete = _hair()
    for length in range(len(complete)):
        var truncated = List[UInt8]()
        for k in range(length):
            truncated.append(complete[k])
        with assert_raises():
            _ = HairStyleFile(_write(truncated))


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
