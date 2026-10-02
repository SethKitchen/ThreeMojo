# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Camera API boundary regressions for issue #353."""

from cameras.cube_camera import CubeCamera
from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from cameras.stereo_camera import StereoCamera
from core.scene import Scene
from std.math import isfinite, nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Angle, DEGREE, Length, METER


def _perspective() raises -> PerspectiveCamera:
    """Return a valid square camera for a boundary test."""
    return PerspectiveCamera(
        Angle(90, DEGREE), 1, Length(1, METER), Length(10, METER)
    )


def _bad_numbers() -> List[Float32]:
    """Return NaN and both infinities."""
    return [nan[DType.float32](), Float32.MAX * 2, -Float32.MAX * 2]


def test_perspective_construction_refuses_nonfinite_frustums() raises:
    var bad = _bad_numbers()
    for at in range(len(bad)):
        for field in range(5):
            var values: List[Float32] = [90, 1, 1, 10, 0]
            values[field] = bad[at]
            with assert_raises():
                _ = PerspectiveCamera(
                    Angle(values[0], DEGREE),
                    values[1],
                    Length(values[2], METER),
                    Length(values[3], METER),
                    view_shift=Length(values[4], METER),
                )


def test_perspective_projection_rechecks_mutated_frustums() raises:
    var bad = _bad_numbers()
    for at in range(len(bad)):
        for field in range(5):
            var camera = _perspective()
            if field == 0:
                camera.fov = Angle(bad[at], DEGREE)
            elif field == 1:
                camera.aspect = bad[at]
            elif field == 2:
                camera.near = Length(bad[at], METER)
            elif field == 3:
                camera.far = Length(bad[at], METER)
            else:
                camera.view_shift = Length(bad[at], METER)
            with assert_raises():
                _ = camera.projection_matrix()


def test_perspective_fov_cannot_wrap_through_tangent() raises:
    var degrees: List[Float32] = [-1, 0, 180, 270, 360, 450, 720]
    for at in range(len(degrees)):
        with assert_raises(contains="field of view"):
            _ = PerspectiveCamera(
                Angle(degrees[at], DEGREE),
                1,
                Length(1, METER),
                Length(10, METER),
            )
        var camera = _perspective()
        camera.fov = Angle(degrees[at], DEGREE)
        with assert_raises(contains="field of view"):
            _ = camera.projection_matrix()
    var valid_degrees: List[Float32] = [1, 90, 179]
    for degrees in valid_degrees:
        var camera = PerspectiveCamera(
            Angle(degrees, DEGREE), 1, Length(1, METER), Length(10, METER)
        )
        assert_true(isfinite(camera.projection_matrix().elements[0]))


def test_orthographic_construction_refuses_each_nonfinite_plane() raises:
    var bad = _bad_numbers()
    for at in range(len(bad)):
        for field in range(6):
            var values: List[Float32] = [-1, 1, 1, -1, 0, 10]
            values[field] = bad[at]
            with assert_raises(contains="finite"):
                _ = OrthographicCamera(
                    Length(values[0], METER),
                    Length(values[1], METER),
                    Length(values[2], METER),
                    Length(values[3], METER),
                    Length(values[4], METER),
                    Length(values[5], METER),
                )


def test_orthographic_projection_rechecks_mutated_planes() raises:
    var bad = _bad_numbers()
    for at in range(len(bad)):
        for field in range(6):
            var camera = centered(
                Length(2, METER), 1, Length(0, METER), Length(10, METER)
            )
            var value = Length(bad[at], METER)
            if field == 0:
                camera.left = value
            elif field == 1:
                camera.right = value
            elif field == 2:
                camera.top = value
            elif field == 3:
                camera.bottom = value
            elif field == 4:
                camera.near = value
            else:
                camera.far = value
            with assert_raises(contains="finite"):
                _ = camera.projection_matrix()


def test_orthographic_near_can_stay_behind_the_camera() raises:
    var camera = centered(
        Length(2, METER), 1, Length(-10, METER), Length(10, METER)
    )
    var projection = camera.projection_matrix()
    assert_true(isfinite(projection.elements[10]))
    assert_equal(projection.elements[14], Float32(0))
    var bad = _bad_numbers()
    for at in range(len(bad)):
        with assert_raises():
            _ = centered(
                Length(bad[at], METER), 1, Length(0, METER), Length(10, METER)
            )
        with assert_raises():
            _ = centered(
                Length(2, METER), bad[at], Length(0, METER), Length(10, METER)
            )


def test_cube_planes_are_finite_at_construction_and_face_use() raises:
    var bad = _bad_numbers()
    for at in range(len(bad)):
        with assert_raises():
            _ = CubeCamera(Length(bad[at], METER), Length(10, METER), 8)
        with assert_raises():
            _ = CubeCamera(Length(1, METER), Length(bad[at], METER), 8)
        var cube = CubeCamera(Length(1, METER), Length(10, METER), 8)
        cube.near = Length(bad[at], METER)
        with assert_raises():
            _ = cube.face_camera(0, Scene())


def test_stereo_invalid_zoom_leaves_both_eyes_unchanged() raises:
    var stereo = StereoCamera()
    var camera = _perspective()
    stereo.update(camera, Scene())
    var left = stereo.left
    var right = stereo.right
    var zooms = _bad_numbers()
    zooms.append(0)
    zooms.append(-1)
    for at in range(len(zooms)):
        camera.zoom = zooms[at]
        with assert_raises(contains="zoom"):
            stereo.update(camera, Scene())
        assert_equal(stereo.left.zoom, left.zoom)
        assert_equal(stereo.right.zoom, right.zoom)
        assert_equal(stereo.left.position.x, left.position.x)
        assert_equal(stereo.right.position.x, right.position.x)


def test_stereo_rejects_overflow_and_collapsed_eye_frustums() raises:
    var stereo = StereoCamera()
    var camera = _perspective()
    stereo.update(camera, Scene())
    var old_left = stereo.left
    var old_right = stereo.right
    stereo.aspect = 2
    camera.aspect = Float32.MAX
    with assert_raises():
        stereo.update(camera, Scene())
    camera = _perspective()
    stereo.aspect = 1
    stereo.focus = Length(1e-37, METER)
    with assert_raises():
        stereo.update(camera, Scene())
    assert_equal(stereo.left.view_shift.value, old_left.view_shift.value)
    assert_equal(stereo.right.view_shift.value, old_right.view_shift.value)


def test_view_offset_refuses_aspect_overflow_without_mutation() raises:
    var camera = _perspective()
    camera.set_view_offset(8, 4, 1, 1, 2, 2)
    var before = camera.view.value()
    with assert_raises(contains="aspect"):
        camera.set_view_offset(1e30, 1e-30, 0, 0, 1, 1)
    assert_equal(camera.aspect, Float32(2))
    assert_equal(camera.view.value().full_width, before.full_width)
    assert_equal(camera.view.value().offset_x, before.offset_x)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
