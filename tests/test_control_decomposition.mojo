# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Transform controls reuse the scale-safe matrix decomposition."""

from controls.transform_controls import decompose
from math.matrix4 import Matrix4, compose, rotation_axis, scaling
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, RADIAN


def test_tiny_and_huge_scales_preserve_the_mirror_sign() raises:
    for magnitude in [Float32(1e-30), Float32(1e-15), Float32(1e30)]:
        for sign in [Float32(-1), Float32(1)]:
            var matrix = scaling(sign * magnitude, magnitude, magnitude)
            matrix.elements[12] = 7
            var pose = decompose(matrix)
            assert_true(pose.position == Vector3(7, 0, 0))
            assert_true(
                pose.scale == Vector3(sign * magnitude, magnitude, magnitude)
            )
            assert_true(pose.quaternion == Quaternion.identity())


def test_rotated_small_axes_reconstruct_the_transform() raises:
    var axis = Vector3(1, 2, 3)
    axis.normalize()
    var matrix = rotation_axis(axis, Angle(0.7, RADIAN))
    matrix.scale(Vector3(-1e-30, 2e-30, 3e-30))
    var pose = decompose(matrix)
    var restored = compose(pose.position, pose.quaternion, pose.scale)
    assert_true(restored.is_finite())
    for column in range(3):
        for row in range(3):
            var at = column * 4 + row
            assert_almost_equal(
                Float64(restored.elements[at]) / 1e-30,
                Float64(matrix.elements[at]) / 1e-30,
                atol=1e-6,
            )


def test_invalid_frames_are_refused_by_the_shared_boundary() raises:
    with assert_raises():
        _ = decompose(scaling(0, 1, 1))
    for value in [inf[DType.float32](), nan[DType.float32]()]:
        var matrix = Matrix4()
        matrix.elements[12] = value
        with assert_raises():
            _ = decompose(matrix)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
