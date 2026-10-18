# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared helpers keep camera and curve refusal order."""

from cameras.perspective_camera import PerspectiveCamera
from cameras.orthographic_camera import OrthographicCamera
from math.curve import CurveKind, line
from math.curve_checks import curve_sample_count
from math.projection import viewport
from math.vector2 import Vector2
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Angle, DEGREE, Length, METER


def test_perspective_viewport_refusal_precedes_projection() raises:
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(1, METER), Length(100, METER)
    )
    camera.aspect = 0
    for width, height in [(0, 1), (1, 0), (-1, -1)]:
        with assert_raises(contains="Viewport dimensions must be positive"):
            _ = camera.view_to_screen_matrix(width, height)
        with assert_raises(contains="Viewport dimensions must be positive"):
            _ = camera.screen_matrix(width, height)
        # The main branch evaluates the viewport before the projection.
        with assert_raises(contains="Viewport dimensions must be positive"):
            var reference = viewport(width, height)
            reference.multiply(camera.projection_matrix())
    with assert_raises(contains="The aspect ratio must be positive and finite"):
        _ = camera.view_to_screen_matrix(1, 1)
    with assert_raises(contains="The aspect ratio must be positive and finite"):
        _ = camera.screen_matrix(1, 1)


def test_orthographic_viewport_refusal_precedes_projection() raises:
    var camera = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(1, METER),
        Length(100, METER),
    )
    camera.right = camera.left
    for width, height in [(0, 1), (1, 0), (-1, -1)]:
        with assert_raises(contains="Viewport dimensions must be positive"):
            _ = camera.view_to_screen_matrix(width, height)
        with assert_raises(contains="Viewport dimensions must be positive"):
            var reference = viewport(width, height)
            reference.multiply(camera.projection_matrix())
    with assert_raises(contains="The view volume needs right beyond left"):
        _ = camera.view_to_screen_matrix(1, 1)


def test_curve_division_refusal_precedes_table_validation() raises:
    var curve = line(Vector2(0, 0), Vector2(1, 0))
    curve.kind = CurveKind(-1)
    for count in [0, -1]:
        with assert_raises(contains="A curve needs at least one division"):
            _ = curve.spaced_points(count)
        with assert_raises(contains="A curve needs at least one division"):
            _ = curve_sample_count(count)
            _ = curve.lengths(curve.arc_divisions())
    with assert_raises(contains="A curve sample count cannot fit in Int"):
        _ = curve.spaced_points(Int.MAX)
    with assert_raises(contains="A curve needs a kind that exists"):
        _ = curve.spaced_points(1)


def test_valid_curve_still_samples_both_endpoints() raises:
    var curve = line(Vector2(0, 0), Vector2(1, 0))
    var points = curve.spaced_points(2)
    assert_equal(len(points), 3)
    assert_true(points[0] == Vector2(0, 0))
    assert_true(points[1] == Vector2(0.5, 0))
    assert_true(points[2] == Vector2(1, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
