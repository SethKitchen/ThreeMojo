# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the morphable face model and its file."""

from core.buffer_geometry import NORMAL, POSITION, UV
from extensions.humanoid.skeleton.head.face_model import (
    EYELASHES,
    FACE_AND_HEAD,
    FACE_MODEL_PATH,
    FaceModel,
    FacePart,
    LEFT_EYEBALL,
    TEETH,
)
from math.vector3 import Vector3
from test_scratch import TestScratch, temporary_path
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _u32(mut bytes: List[UInt8], value: Int):
    """Append `value` as a little-endian 32-bit integer."""
    for k in range(4):  # pragma: no branch
        bytes.append(UInt8((value >> (8 * k)) & 0xFF))


def _file(name: String, counts: List[Int], body: List[UInt8]) raises -> String:
    """Write a face model file of version 6 with fourteen `counts` and a
    `body`, and return its path. With expressions, the body is theirs."""
    var bytes: List[UInt8] = [73, 67, 84, 70]
    _u32(bytes, 6)
    var header = counts.copy()
    if header[4] > 0:
        header[10] = len(body)
    for count in header:  # pragma: no branch
        _u32(bytes, count)
    bytes.extend(body.copy())
    var path = temporary_path("threemojo_face_") + name + ".bin"
    Path(path).write_bytes(bytes)
    return path


def test_a_face_part_is_a_run_of_vertices() raises:
    assert_true(TEETH.is_valid())
    assert_false(FacePart(-1, 4).is_valid())
    assert_false(FacePart(4, 4).is_valid())


def test_the_model_reads_its_file() raises:
    var model = FaceModel(FACE_MODEL_PATH)
    assert_equal(model.identities(), 60)
    assert_equal(model.expressions(), 57)
    # The skin's holes: the base of the neck, the mouth and two eyes.
    assert_equal(model.holes(), 4)
    var corners = 0
    for index in range(model.holes()):  # pragma: no branch
        corners += len(model.hole(index))
    assert_equal(corners, 212)
    assert_equal(len(model.skin_triangles()) % 3, 0)
    assert_equal(len(model.skin_edges()) % 2, 0)
    # The coarse copy the skin is fitted on, and how the skin follows it.
    assert_true(len(model.coarse_vertices()) < FACE_AND_HEAD.end // 2)
    assert_equal(len(model.coarse_edges()) % 2, 0)
    assert_equal(len(model.followed()), FACE_AND_HEAD.end * 3)
    assert_equal(len(model.follow_weights()), FACE_AND_HEAD.end * 2)
    # Only as much is read as is asked for.
    var bare = FaceModel(FACE_MODEL_PATH, 0, False)
    assert_equal(bare.identities(), 0)
    assert_equal(bare.expressions(), 0)
    assert_equal(bare.vertex_count(), model.vertex_count())
    assert_equal(FaceModel(FACE_MODEL_PATH, 5, False).identities(), 5)
    assert_equal(FaceModel(FACE_MODEL_PATH, -1, False).identities(), 60)
    assert_equal(FaceModel(FACE_MODEL_PATH, 99, False).identities(), 60)
    # Expressions and some identity modes, or identity modes alone.
    var both = FaceModel(FACE_MODEL_PATH, 3, True)
    assert_equal(both.identities(), 3)
    assert_equal(both.expressions(), 57)
    assert_equal(FaceModel(FACE_MODEL_PATH, 0, True).identities(), 0)


def test_a_face_takes_an_identity_and_an_expression() raises:
    var model = FaceModel(FACE_MODEL_PATH)
    var mean = model.shape(model.no_identity(), model.no_expression())
    assert_equal(len(mean), model.vertex_count())
    # The first vertices alone.
    var few = model.shape(model.no_identity(), model.no_expression(), 10)
    assert_equal(len(few), 10)
    assert_equal(few[9].x, mean[9].x)
    var blinked = model.no_expression()
    blinked[model.expression("eyeBlink_L")] = 1
    assert_equal(len(model.shape(model.no_identity(), blinked, 10)), 10)
    var identity = model.no_identity()
    identity[0] = 2.0
    var other = model.shape(identity, model.no_expression())
    var moved = 0
    for v in range(len(mean)):  # pragma: no branch
        if (other[v] - mean[v]).length() > 1e-4:
            moved += 1
    assert_true(moved > 1000)
    # The jaw drops the chin.
    var open = model.no_expression()
    open[model.expression("jawOpen")] = 1.0
    var dropped = model.shape(model.no_identity(), open)
    var lowest = Float32(1)
    for v in range(FACE_AND_HEAD.end):  # pragma: no branch
        lowest = min(lowest, dropped[v].y - mean[v].y)
    assert_true(lowest < -0.005)
    with assert_raises(contains="no expression"):
        _ = model.expression("frown")
    with assert_raises(contains="identity mode"):
        _ = model.shape(List[Float32](), model.no_expression())
    with assert_raises(contains="expression"):
        _ = model.shape(model.no_identity(), List[Float32]())


def test_a_part_is_a_mesh() raises:
    var model = FaceModel(FACE_MODEL_PATH, 0, False)
    var points = model.shape(model.no_identity(), model.no_expression())
    var eye = model.part(points, LEFT_EYEBALL)
    var count = eye.attribute_view(String(POSITION)).count()
    assert_true(count > 100)
    assert_equal(eye.attribute_view(String(NORMAL)).count(), count)
    assert_equal(eye.attribute_view(String(UV)).count(), count)
    var parts: List[FacePart] = [TEETH, EYELASHES]
    assert_true(len(model.triangles_of(parts)) > 0)
    with assert_raises(contains="one point"):
        _ = model.part(List[Vector3](), TEETH)
    with assert_raises(contains="run of the model"):
        _ = model.part(points, FacePart(3, 3))
    with assert_raises(contains="run of the model"):
        _ = model.part(points, FacePart(0, len(points) + 1))
    var bad: List[FacePart] = [FacePart(-1, 2)]
    with assert_raises(contains="run of the model"):
        _ = model.triangles_of(bad)
    # One vertex makes no triangle.
    with assert_raises(contains="no triangles"):
        _ = model.part(points, FacePart(0, 1))


def test_a_bad_file_is_refused() raises:
    var junk: List[UInt8] = [1, 2, 3]
    var short = temporary_path("threemojo_face_short.bin")
    Path(short).write_bytes(junk)
    with assert_raises(contains="Not a face model"):
        _ = FaceModel(short)
    var zeros = List[Int](length=14, fill=0)
    var empty = List[UInt8]()
    var wrong = _file("wrong", zeros, empty)
    var bytes = Path(wrong).read_bytes()
    for index in range(1, 4):
        var invalid = bytes.copy()
        invalid[index] = 88
        Path(wrong).write_bytes(invalid)
        with assert_raises(contains="Not a face model"):
            _ = FaceModel(wrong)
    bytes[0] = 88
    Path(wrong).write_bytes(bytes)
    with assert_raises(contains="Not a face model"):
        _ = FaceModel(wrong)
    bytes[0] = 73
    bytes[4] = 5
    Path(wrong).write_bytes(bytes)
    with assert_raises(contains="another version"):
        _ = FaceModel(wrong)
    # A model with nothing in it reads.
    assert_equal(FaceModel(_file("empty", zeros, empty)).holes(), 0)
    # Counts the file cannot hold.
    var many = zeros.copy()
    many[0] = 10
    with assert_raises(contains="ends early"):
        _ = FaceModel(_file("cut", many, empty))
    var mode = zeros.copy()
    mode[3] = 1
    with assert_raises(contains="ends early"):
        _ = FaceModel(_file("mode", mode, empty))
    var named = zeros.copy()
    named[4] = 1
    with assert_raises(contains="ends early"):
        _ = FaceModel(_file("named", named, empty))
    var name: List[UInt8] = [4, 97]
    with assert_raises(contains="ends early"):
        _ = FaceModel(_file("name", named, name))
    var header: List[UInt8] = [1, 97, 0, 0]
    with assert_raises(contains="ends early"):
        _ = FaceModel(_file("header", named, header))
    var moved = header.copy()
    _u32(moved, 5)
    _u32(moved, 0)
    with assert_raises(contains="ends early"):
        _ = FaceModel(_file("moved", named, moved))
    # A hole's length that its corners do not fill.
    var hole = zeros.copy()
    hole[7] = 1
    var length: List[UInt8] = [1, 0, 0, 0]
    with assert_raises(contains="miscount"):
        _ = FaceModel(_file("hole", hole, length))


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
