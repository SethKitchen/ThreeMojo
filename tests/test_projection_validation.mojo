# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Finite projection and common look-at basis boundary regressions."""

from geometries.tube_painter import TubePainter
from math.frustum import Frustum
from math.matrix4 import Matrix4
from math.projection import look_at, orthographic, perspective
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def assert_basis(matrix: Matrix4) raises:
    var x = Vector3(0, 0, 0)
    var y = x
    var z = x
    matrix.extract_basis(x, y, z)
    for axis in [x, y, z]:
        assert_almost_equal(axis.length(), Float32(1), atol=1e-6)
    assert_almost_equal(x.dot(y), Float32(0), atol=1e-6)
    assert_almost_equal(x.dot(z), Float32(0), atol=1e-6)
    assert_almost_equal(y.dot(z), Float32(0), atol=1e-6)
    var cross = x
    cross.cross(y)
    assert_almost_equal(cross.dot(z), Float32(1), atol=1e-6)


def test_look_at_accepts_scaled_and_nearly_parallel_up() raises:
    for scale in [
        Float32(2),
        Float32(-2),
        Float32(1e-30),
        Float32(1e-22),
        Float32(1e-20),
        Float32(1e30),
        bitcast[DType.float32](UInt32(1)),
    ]:
        for up in [
            Vector3(0, 0, scale),
            Vector3(0, scale, 0),
            Vector3(scale, scale, scale),
        ]:
            var matrix = Matrix4()
            matrix.look_at(up, Vector3(0, 0, 0), up)
            assert_basis(matrix)
            var view = look_at(up, Vector3(0, 0, 0), up)
            assert_true(view.is_finite())
    var matrix = Matrix4()
    matrix.look_at(Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1e-30, 0, 1))
    assert_basis(matrix)


def test_look_at_handles_extreme_finite_separation() raises:
    for scale in [Float32(1e-30), Float32(1e30), Float32(3e38)]:
        var matrix = Matrix4()
        matrix.look_at(
            Vector3(scale, 0, 0), Vector3(-scale, 0, 0), Vector3(0, 1, 0)
        )
        assert_basis(matrix)
        assert_equal(matrix.elements[8], Float32(1))
        assert_true(
            look_at(
                Vector3(scale, 0, 0), Vector3(-scale, 0, 0), Vector3(0, 1, 0)
            ).is_finite()
        )


def test_look_at_preserves_other_entries_and_coincident_fallback() raises:
    var matrix = Matrix4()
    for at in [3, 7, 11, 12, 13, 14, 15]:
        matrix.elements[at] = Float32(at)
    matrix.look_at(Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 0, 2))
    assert_basis(matrix)
    for at in [3, 7, 11, 12, 13, 14, 15]:
        assert_equal(matrix.elements[at], Float32(at))
    matrix = Matrix4()
    matrix.look_at(Vector3(4, 5, 6), Vector3(4, 5, 6), Vector3(0, 2, 0))
    assert_true(matrix == Matrix4())


def test_invalid_look_at_input_keeps_matrix_unchanged() raises:
    var origin = Vector3(0, 0, 0)
    var eye = Vector3(0, 0, 1)
    var up = Vector3(0, 1, 0)
    var matrix = Matrix4()
    matrix.elements[12] = 7
    var before = matrix
    for bad in [
        Vector3(0, 0, 0),
        Vector3(nan[DType.float32](), 1, 0),
        Vector3(0, inf[DType.float32](), 1),
    ]:
        with assert_raises():
            matrix.look_at(eye, origin, bad)
        assert_true(matrix == before)
        with assert_raises():
            _ = look_at(eye, origin, bad)
    for bad in [
        Vector3(inf[DType.float32](), 0, 0),
        Vector3(0, nan[DType.float32](), 0),
    ]:
        with assert_raises():
            matrix.look_at(bad, origin, up)
        with assert_raises():
            matrix.look_at(eye, bad, up)
        assert_true(matrix == before)
    with assert_raises(contains="representable"):
        _ = look_at(Vector3(3e38, 3e38, 3e38), origin, up)


def test_view_rotation_is_the_common_basis_transpose() raises:
    var eye = Vector3(3, -2, 4)
    var target = Vector3(1, 0, -1)
    var up = Vector3(0.3, 2, 0.4)
    var basis = Matrix4()
    basis.look_at(eye, target, up)
    var view = look_at(eye, target, up)
    for row in range(3):
        for column in range(3):
            assert_equal(
                view.elements[column * 4 + row],
                basis.elements[row * 4 + column],
            )
    var zero = view.transform_point(eye)
    assert_almost_equal(zero.length(), Float32(0), atol=1e-6)


def test_projection_rejects_every_nonfinite_bound() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for at in range(6):
            var args: Array[Float32, 6] = [-1, 1, 1, -1, 1, 100]
            args[at] = bad
            with assert_raises(contains="finite"):
                _ = perspective(
                    args[0], args[1], args[2], args[3], args[4], args[5]
                )
            with assert_raises(contains="finite"):
                _ = orthographic(
                    args[0], args[1], args[2], args[3], args[4], args[5]
                )


def test_representable_projections_avoid_intermediate_overflow() raises:
    var wide = perspective(-3e38, 3e38, 3e38, -3e38, 1, 3e38)
    assert_true(wide.is_finite())
    assert_true(wide.elements[0] > 0)
    assert_equal(wide.elements[14], Float32(-2))
    var tiny = perspective(-1, 1, 1, -1, 1e-30, 2e-30)
    assert_almost_equal(tiny.elements[14], Float32(-4e-30), atol=1e-36)
    var ortho = orthographic(-3e38, 3e38, 3e38, -3e38, -3e38, 3e38)
    assert_true(ortho.is_finite())
    assert_true(ortho.elements[0] > 0)
    assert_true(ortho.elements[10] < 0)
    assert_equal(ortho.elements[12], Float32(0))
    assert_equal(ortho.elements[14], Float32(0))


def test_unrepresentable_projection_coefficients_raise() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    with assert_raises(contains="representable"):
        _ = orthographic(0, tiny, 1, -1, 0, 1)
    with assert_raises(contains="representable"):
        _ = perspective(-tiny, tiny, tiny, -tiny, 1, 2)
    with assert_raises(contains="representable"):
        _ = perspective(-3e38, 3e38, 1, -1, tiny, 1)


def test_frustum_rejects_nonfinite_direct_depths() raises:
    var projection = perspective(-1, 1, 1, -1, 1, 100)
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="finite"):
            _ = Frustum.from_camera(projection, Matrix4(), bad, 100)
        with assert_raises(contains="finite"):
            _ = Frustum.from_camera(projection, Matrix4(), 1, bad)


def test_frustum_refuses_nonfinite_matrix_entries() raises:
    var projection = perspective(-1, 1, 1, -1, 1, 100)
    for at in [0, 12, 15]:
        var bad = projection
        bad.elements[at] = nan[DType.float32]()
        with assert_raises(contains="finite"):
            _ = Frustum.from_projection_matrix(bad)
        with assert_raises(contains="finite"):
            _ = Frustum.side_planes(bad)
        with assert_raises(contains="finite"):
            _ = Frustum.from_camera(bad, Matrix4(), 1, 100)
        with assert_raises(contains="finite"):
            _ = Frustum.from_camera(projection, bad, 1, 100)


def test_tube_painter_rejects_nonfinite_positions_atomically() raises:
    var painter = TubePainter()
    painter.move_to(Vector3(0, 0, 1))
    painter.line_to(Vector3(1, 1, 1))
    var before = painter.count()
    with assert_raises(contains="finite"):
        painter.move_to(Vector3(nan[DType.float32](), 0, 0))
    with assert_raises(contains="finite"):
        painter.line_to(Vector3(0, inf[DType.float32](), 0))
    assert_equal(painter.count(), before)
    painter.line_to(Vector3(2, 1, 1))
    assert_true(painter.count() > before)


def test_vertical_projection_scale_underflow_is_rejected_independently() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    # The horizontal scale and depth translation remain nonzero. Only
    # the vertical scale is too small to represent after wide arithmetic.
    with assert_raises(contains="representable"):
        _ = perspective(-tiny, tiny, 3e38, -3e38, tiny, 1)


def test_smallest_near_plane_keeps_nonzero_depth_translation() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    var projection = perspective(-tiny, tiny, tiny, -tiny, tiny, 2 * tiny)
    assert_true(projection.is_finite())
    assert_equal(projection.elements[0], Float32(1))
    assert_equal(projection.elements[5], Float32(1))
    assert_equal(projection.elements[14], -4 * tiny)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
