# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regression tests for direct gradient refusal and the TAAU depth API."""

from materials.nodes import NodeSource
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.sampling import Untracked
from postprocessing.taau import previous_window_depth
from postprocessing.traa import FloatPlane, reproject_window_depth
from render.computation import ComputeNodes
from std.math import nan, pi
from std.testing import TestSuite, assert_almost_equal, assert_equal


def _check_refused[
    T: NodeSource
](source: T, u: Float32, v: Float32, dx: Vector2, dy: Vector2) raises:
    var color = source.sample_grad(0, u, v, dx, dy)
    assert_equal(color.r, 0)
    assert_equal(color.g, 0)
    assert_equal(color.b, 0)
    assert_equal(color.a, 0)


def test_nonfinite_gradients_refuse_before_reading_empty_backing() raises:
    # Empty backing makes any read of wraps, code or images invalid. Call
    # the NodeSource operation directly, without an evaluator's guard.
    var code = List[Float32]()
    var images = List[Float32]()
    var wraps = List[Int32]()
    var source = ComputeNodes(
        code.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked](),
        images.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked](),
        wraps.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked](),
        1,
        1,
        0,
        0,
    )
    var zero = Vector2(0, 0)
    var bad_values: List[Float32] = [
        nan[DType.float32](),
        Float32.MAX * 2,
        -Float32.MAX * 2,
    ]
    for bad in bad_values:
        _check_refused(source, bad, 0.5, zero, zero)
        _check_refused(source, 0.5, bad, zero, zero)
        _check_refused(source, 0.5, 0.5, Vector2(bad, 0), zero)
        _check_refused(source, 0.5, 0.5, Vector2(0, bad), zero)
        _check_refused(source, 0.5, 0.5, zero, Vector2(bad, 0))
        _check_refused(source, 0.5, 0.5, zero, Vector2(0, bad))
    _ = code^
    _ = images^
    _ = wraps^


def test_previous_window_depth_keeps_original_signature() raises:
    var depths: List[Float32] = [0.25, 0.375, 0.75, 1]
    var previous = FloatPlane(depths, 2, 2, 1)
    var identity = Matrix4()
    var projections: List[Bool] = [False, True]
    var coordinates: List[Float32] = [0.25, 0.75]
    for perspective in projections:
        for u in coordinates:
            var actual = previous_window_depth(
                previous,
                u,
                0.25,
                1,
                10,
                perspective,
                identity,
                identity,
                identity,
            )
            var expected = reproject_window_depth(
                previous,
                u,
                0.25,
                1,
                10,
                perspective,
                identity,
                identity,
                identity,
            )
            assert_equal(actual, expected)
    # Identity transforms map the first sample to view z = -0.5.
    assert_almost_equal(
        previous_window_depth(
            previous,
            0.25,
            0.25,
            1,
            10,
            False,
            identity,
            identity,
            identity,
        ),
        Float32(-0.5 / 9),
    )
    _ = depths^


def test_polyline_angles_use_radians_for_both_point_types() raises:
    assert_almost_equal(
        Vector2(1, 0).angle_to(Vector2(0, 1)).value, Float32(pi / 2)
    )
    assert_almost_equal(
        Vector3(1, 0, 0).angle_to(Vector3(0, 1, 0)).value, Float32(pi / 2)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
