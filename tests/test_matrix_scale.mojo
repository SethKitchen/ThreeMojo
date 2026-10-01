# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Scale-safe matrix axis, decomposition and rotation contracts."""

from math.matrix4 import Matrix4, compose, rotation_axis, scaling
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, RADIAN


def test_diagonal_scales_keep_mirror_sign_across_the_float32_range() raises:
    for magnitude in [
        bitcast[DType.float32](UInt32(1)),
        Float32(1e-30),
        Float32(1e-15),
        Float32(1e-14),
        Float32(1e15),
        Float32(1e30),
        Float32(3e38),
    ]:
        for sign in [Float32(-1), Float32(1)]:
            var matrix = scaling(sign * magnitude, magnitude, magnitude)
            matrix.elements[12] = 7
            var position = Vector3(0, 0, 0)
            var turn = Quaternion.identity()
            var size = position
            matrix.decompose(position, turn, size)
            assert_true(position == Vector3(7, 0, 0))
            assert_true(size == Vector3(sign * magnitude, magnitude, magnitude))
            assert_true(turn == Quaternion.identity())
            assert_equal(matrix.max_scale(), magnitude)


def test_rotated_extreme_scales_reconstruct_the_original_transform() raises:
    var axis = Vector3(1, 2, 3)
    axis.normalize()
    var rotation = rotation_axis(axis, Angle(0.7, RADIAN))
    for magnitude in [
        Float32(1e-30),
        Float32(1e-15),
        Float32(1e-14),
        Float32(1),
        Float32(1e15),
        Float32(1e30),
    ]:
        for sign in [Float32(-1), Float32(1)]:
            var matrix = rotation
            matrix.scale(
                Vector3(sign * magnitude, magnitude / 2, magnitude * 2)
            )
            matrix.elements[12] = 3
            matrix.elements[13] = -4
            var position = Vector3(0, 0, 0)
            var turn = Quaternion.identity()
            var size = position
            matrix.decompose(position, turn, size)
            assert_true(size.x * sign > 0)
            var restored = compose(position, turn, size)
            assert_true(restored.is_finite())
            for column in range(3):
                for row in range(3):
                    var at = column * 4 + row
                    assert_almost_equal(
                        Float64(restored.elements[at]) / Float64(magnitude),
                        Float64(matrix.elements[at]) / Float64(magnitude),
                        atol=1e-6,
                    )
            assert_true(position == Vector3(3, -4, 0))


def enormous_frame() -> Matrix4:
    # A Householder frame with one flipped column: unit orthogonal columns
    # scaled by 4e38. Every entry fits Float32, but no axis length does.
    var matrix = Matrix4()
    for column in range(3):
        for row in range(3):
            var entry = Float64(1) / 3 if row == column else Float64(-2) / 3
            if column == 0:
                entry = -entry
            matrix.elements[column * 4 + row] = Float32(entry * 4e38)
    return matrix^


def test_rotation_extraction_handles_lengths_that_do_not_fit_float32() raises:
    var matrix = enormous_frame()
    var rotation = matrix.extract_rotation()
    assert_true(rotation.is_finite())
    assert_true(rotation.is_rotation())
    assert_true(matrix.is_scaled_rotation())
    assert_equal(matrix.max_scale(), inf[DType.float32]())
    for magnitude in [Float32(1e-30), Float32(1e30)]:
        var small = scaling(magnitude, magnitude, magnitude)
        assert_true(small.extract_rotation() == Matrix4())


def test_decompose_refuses_invalid_inputs_before_mutating_outputs() raises:
    var position = Vector3(7, 8, 9)
    var turn = Quaternion(0, 1, 0, 0)
    var size = Vector3(2, 3, 4)
    var original_position = position
    var original_turn = turn
    var original_size = size
    for at in range(16):
        for bad in [nan[DType.float32](), inf[DType.float32]()]:
            var matrix = Matrix4()
            matrix.elements[at] = bad
            with assert_raises(contains="finite"):
                matrix.decompose(position, turn, size)
            assert_true(position == original_position)
            assert_true(turn == original_turn)
            assert_true(size == original_size)
    with assert_raises(contains="fit"):
        enormous_frame().decompose(position, turn, size)
    with assert_raises(contains="no extent"):
        scaling(1, 0, 1).decompose(position, turn, size)
    assert_true(position == original_position)
    assert_true(turn == original_turn)
    assert_true(size == original_size)


def test_rotation_classification_is_independent_of_finite_scale() raises:
    var axis = Vector3(1, 2, 3)
    axis.normalize()
    var rotation = rotation_axis(axis, Angle(0.7, RADIAN))
    for magnitude in [
        Float32(1e-30),
        Float32(1e-15),
        Float32(1e-14),
        Float32(1e15),
        Float32(1e30),
    ]:
        var matrix = rotation
        matrix.scale(Vector3(magnitude, magnitude, magnitude))
        assert_true(matrix.is_scaled_rotation())
        assert_false(matrix.is_rotation())
        matrix.scale(Vector3(-1, 1, 1))
        assert_false(matrix.is_scaled_rotation())
        var nonuniform = scaling(magnitude, 2 * magnitude, magnitude)
        assert_false(nonuniform.is_scaled_rotation())
        var shear = Matrix4()
        shear.set(
            magnitude,
            0.6 * magnitude,
            0,
            0,
            0,
            0.8 * magnitude,
            0,
            0,
            0,
            0,
            magnitude,
            0,
            0,
            0,
            0,
            1,
        )
        assert_false(shear.is_scaled_rotation())
    assert_false(scaling(0, 0, 0).is_scaled_rotation())


def test_rotation_predicates_refuse_nonfinite_axes_and_bad_tolerances() raises:
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        for at in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
            var matrix = Matrix4()
            matrix.elements[at] = value
            assert_false(matrix.is_scaled_rotation())
            assert_false(matrix.is_rotation())
            with assert_raises(contains="finite"):
                _ = matrix.extract_rotation()
        assert_false(Matrix4().is_scaled_rotation(value))
        assert_false(Matrix4().is_rotation(value))
    assert_false(Matrix4().is_scaled_rotation(-1))
    var matrix = Matrix4()
    matrix.elements[12] = nan[DType.float32]()
    matrix.elements[15] = -1
    # Classification and extraction concern only the linear block.
    assert_true(matrix.is_scaled_rotation())
    assert_true(matrix.extract_rotation() == Matrix4())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
