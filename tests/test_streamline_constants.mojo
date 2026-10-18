# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the per-frame constants of Streamline: the matrices of two
cameras, the camera's axes, the motion scale and every value the checks
refuse."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from extensions.streamline.constants import (
    CameraSnapshot,
    FrameConstants,
    check_camera_snapshot,
    check_frame_constants,
    frame_constants,
    streamline_motion_vector,
)
from extensions.streamline.kinds import (
    MOTION_NORMALIZED,
    MOTION_PIXELS,
    MotionVectorSpace,
)
from extensions.streamline.sizing import FrameSize
from math.matrix4 import Matrix4, scaling, translation
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN


def perspective(x: Float32) raises -> PerspectiveCamera:
    """Return a camera that looks down the z axis from x across."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(x, 0, 5), Vector3(x, 0, 0))
    return camera^


def snapshot(x: Float32) raises -> CameraSnapshot:
    """Return the snapshot of the camera at x across."""
    return CameraSnapshot(perspective(x), Scene())


def assert_identity(matrix: Matrix4, atol: Float64 = 1e-4) raises:
    var identity = Matrix4()
    for at in range(16):
        assert_almost_equal(
            matrix.elements[at], identity.elements[at], atol=atol
        )


def test_a_snapshot_takes_a_camera_as_it_is() raises:
    var camera = perspective(2)
    var taken = CameraSnapshot(camera, Scene())
    assert_true(taken.projection == camera.projection_matrix())
    assert_true(taken.view == camera.view_matrix())
    assert_almost_equal(taken.near.to(METER), 0.1, atol=1e-6)
    assert_almost_equal(taken.far.to(METER), 100.0, atol=1e-4)
    var held = CameraSnapshot(
        taken.view, taken.projection, taken.near, taken.far
    )
    assert_true(held.view == taken.view)
    check_camera_snapshot(taken)


def test_the_constants_describe_the_camera() raises:
    var constants = frame_constants(
        snapshot(0),
        snapshot(0),
        FrameSize(1280, 720),
        Vector2(0.25, -0.25),
        MOTION_NORMALIZED,
        False,
    )
    assert_true(
        constants.camera_view_to_clip == perspective(0).projection_matrix()
    )
    var product = constants.camera_view_to_clip
    product.multiply(constants.clip_to_camera_view)
    assert_identity(product)
    assert_almost_equal(constants.camera_position.x, 0, atol=1e-5)
    assert_almost_equal(constants.camera_position.y, 0, atol=1e-5)
    assert_almost_equal(constants.camera_position.z, 5, atol=1e-5)
    assert_almost_equal(constants.camera_right.x, 1, atol=1e-6)
    assert_almost_equal(constants.camera_up.y, 1, atol=1e-6)
    assert_almost_equal(constants.camera_forward.z, -1, atol=1e-6)
    assert_almost_equal(constants.camera_near.to(METER), 0.1, atol=1e-6)
    assert_almost_equal(constants.camera_far.to(METER), 100.0, atol=1e-4)
    assert_almost_equal(constants.camera_fov.to(DEGREE), 50.0, atol=1e-3)
    assert_almost_equal(constants.camera_aspect, 16.0 / 9.0, atol=1e-5)
    # Streamline's `jitterOffset` is the negative of the `JitteredCamera`
    # offset: the evaluate probe measured it on a running `sl.dlss`.
    assert_equal(constants.jitter_offset.x, -0.25)
    assert_equal(constants.jitter_offset.y, 0.25)
    assert_false(constants.reset)
    assert_false(constants.orthographic)
    assert_false(constants.depth_inverted)
    assert_true(constants.camera_motion_included)
    assert_false(constants.motion_vectors_3d)
    assert_false(constants.motion_vectors_dilated)
    assert_false(constants.motion_vectors_jittered)


def test_the_axes_follow_a_camera_that_turns() raises:
    var camera = perspective(0)
    camera.place(Vector3(5, 0, 0), Vector3(0, 0, 0))
    var constants = frame_constants(
        CameraSnapshot(camera, Scene()),
        CameraSnapshot(camera, Scene()),
        FrameSize(64, 36),
        Vector2(0, 0),
        MOTION_NORMALIZED,
        False,
    )
    assert_almost_equal(constants.camera_position.x, 5, atol=1e-5)
    assert_almost_equal(constants.camera_forward.x, -1, atol=1e-5)
    assert_almost_equal(constants.camera_right.z, -1, atol=1e-5)
    assert_almost_equal(constants.camera_up.y, 1, atol=1e-5)


def test_the_motion_scale_follows_the_unit_of_the_vectors() raises:
    var render = FrameSize(1280, 720)
    var normalized = frame_constants(
        snapshot(0),
        snapshot(0),
        render,
        Vector2(0, 0),
        MOTION_NORMALIZED,
        False,
    )
    assert_equal(normalized.mvec_scale.x, 1)
    assert_equal(normalized.mvec_scale.y, 1)
    var pixels = frame_constants(
        snapshot(0), snapshot(0), render, Vector2(0, 0), MOTION_PIXELS, False
    )
    assert_equal(pixels.mvec_scale.x, 1.0 / 1280.0)
    assert_equal(pixels.mvec_scale.y, 1.0 / 720.0)


def test_the_previous_clip_matrix_follows_the_camera_motion() raises:
    var current = snapshot(0)
    var previous = snapshot(1)
    var constants = frame_constants(
        current,
        previous,
        FrameSize(1280, 720),
        Vector2(0, 0),
        MOTION_NORMALIZED,
        False,
    )
    var now = current.projection
    now.multiply(current.view)
    var before = previous.projection
    before.multiply(previous.view)
    for world in [Vector3(0.3, 0.2, 0), Vector3(-1, 0.5, -2), Vector3(0, 0, 1)]:
        var ndc_now = now.transform_point(world)
        var expected = before.transform_point(world)
        var got = constants.clip_to_prev_clip.transform_point(ndc_now)
        assert_almost_equal(got.x, expected.x, atol=1e-4)
        assert_almost_equal(got.y, expected.y, atol=1e-4)
        assert_almost_equal(got.z, expected.z, atol=1e-4)
        var back = constants.prev_clip_to_clip.transform_point(expected)
        assert_almost_equal(back.x, ndc_now.x, atol=1e-4)
        assert_almost_equal(back.y, ndc_now.y, atol=1e-4)
        assert_almost_equal(back.z, ndc_now.z, atol=1e-4)
    var round_trip = constants.clip_to_prev_clip
    round_trip.multiply(constants.prev_clip_to_clip)
    assert_identity(round_trip)


def test_a_reset_forgets_the_previous_camera() raises:
    var broken = CameraSnapshot(
        scaling(0, 1, 1), Matrix4(), Length(0.1, METER), Length(1.0, METER)
    )
    var constants = frame_constants(
        snapshot(0),
        broken,
        FrameSize(64, 36),
        Vector2(0, 0),
        MOTION_NORMALIZED,
        True,
    )
    assert_true(constants.reset)
    assert_identity(constants.clip_to_prev_clip)
    assert_identity(constants.prev_clip_to_clip)
    with assert_raises(contains="view matrix must be invertible"):
        _ = frame_constants(
            snapshot(0),
            broken,
            FrameSize(64, 36),
            Vector2(0, 0),
            MOTION_NORMALIZED,
            False,
        )


def test_an_orthographic_camera_has_no_field_of_view() raises:
    var camera = OrthographicCamera(
        Length(-8.0, METER),
        Length(8.0, METER),
        Length(4.5, METER),
        Length(-4.5, METER),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var taken = CameraSnapshot(camera, Scene())
    var constants = frame_constants(
        taken,
        taken,
        FrameSize(160, 90),
        Vector2(0, 0),
        MOTION_NORMALIZED,
        False,
    )
    assert_true(constants.orthographic)
    assert_equal(constants.camera_fov.to(RADIAN), 0)
    assert_almost_equal(constants.camera_aspect, 16.0 / 9.0, atol=1e-5)


def test_the_builder_refuses_a_bad_frame() raises:
    var render = FrameSize(64, 36)
    with assert_raises(contains="at least one pixel"):
        _ = frame_constants(
            snapshot(0),
            snapshot(0),
            FrameSize(0, 36),
            Vector2(0, 0),
            MOTION_PIXELS,
            False,
        )
    with assert_raises(contains="at least one pixel"):
        _ = frame_constants(
            snapshot(0),
            snapshot(0),
            FrameSize(64, 0),
            Vector2(0, 0),
            MOTION_PIXELS,
            False,
        )
    with assert_raises(contains="motion vector space"):
        _ = frame_constants(
            snapshot(0),
            snapshot(0),
            render,
            Vector2(0, 0),
            MotionVectorSpace(2),
            False,
        )
    with assert_raises(contains="jitter"):
        _ = frame_constants(
            snapshot(0),
            snapshot(0),
            render,
            Vector2(0.75, 0),
            MOTION_PIXELS,
            False,
        )
    var bad = snapshot(0)
    bad.near = Length(0.0, METER)
    with assert_raises(contains="clipping"):
        _ = frame_constants(
            bad, snapshot(0), render, Vector2(0, 0), MOTION_PIXELS, False
        )
    with assert_raises(contains="clipping"):
        _ = frame_constants(
            snapshot(0), bad, render, Vector2(0, 0), MOTION_PIXELS, False
        )


def test_the_snapshot_check_refuses_a_camera_dlss_cannot_follow() raises:
    var good = snapshot(0)
    var bad = snapshot(0)
    bad.view = translation(nan[DType.float32](), 0, 0)
    with assert_raises(contains="view matrix must be finite"):
        check_camera_snapshot(bad)
    bad = snapshot(0)
    bad.projection = translation(inf[DType.float32](), 0, 0)
    with assert_raises(contains="projection matrix must be finite"):
        check_camera_snapshot(bad)
    var nan32 = nan[DType.float32]()
    var nears: List[Float32] = [nan32, 0, -1, 1, 1, 2]
    var fars: List[Float32] = [1, 1, 1, nan32, 1, 1]
    for at in range(len(nears)):
        bad = snapshot(0)
        bad.near = Length(nears[at], METER)
        bad.far = Length(fars[at], METER)
        with assert_raises(contains="clipping"):
            check_camera_snapshot(bad)
    bad = snapshot(0)
    bad.view = scaling(0, 1, 1)
    with assert_raises(contains="view matrix must be invertible"):
        check_camera_snapshot(bad)
    bad = snapshot(0)
    bad.projection = scaling(1, 0, 1)
    with assert_raises(contains="projection matrix must be invertible"):
        check_camera_snapshot(bad)
    # A determinant that overflows is no better than none.
    bad = snapshot(0)
    bad.view = scaling(1e20, 1e20, 1e20)
    with assert_raises(contains="view matrix must be invertible"):
        check_camera_snapshot(bad)
    # A determinant that is too small to invert in Float32.
    bad = snapshot(0)
    var tiny = Matrix4()
    tiny.elements[0] = 1e-40
    bad.view = tiny
    with assert_raises(contains="view matrix must be invertible"):
        check_camera_snapshot(bad)
    check_camera_snapshot(good)


def test_the_projection_must_scale_across_and_up() raises:
    var bad = snapshot(0)
    var no_across = Matrix4()
    no_across.set(0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    bad.projection = no_across
    with assert_raises(contains="scale across and up"):
        check_camera_snapshot(bad)
    var no_up = Matrix4()
    no_up.set(1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    bad.projection = no_up
    with assert_raises(contains="scale across and up"):
        check_camera_snapshot(bad)


def test_the_defaults_are_constants_dlss_accepts() raises:
    var constants = FrameConstants()
    check_frame_constants(constants)
    assert_identity(constants.camera_view_to_clip)
    assert_equal(constants.mvec_scale.x, 1)
    assert_true(constants.camera_motion_included)


def test_the_constants_check_refuses_a_matrix_that_is_not_finite() raises:
    var bad = FrameConstants()
    bad.camera_view_to_clip = translation(nan[DType.float32](), 0, 0)
    with assert_raises(contains="projection matrices"):
        check_frame_constants(bad)
    bad = FrameConstants()
    bad.clip_to_camera_view = translation(inf[DType.float32](), 0, 0)
    with assert_raises(contains="projection matrices"):
        check_frame_constants(bad)
    bad = FrameConstants()
    bad.clip_to_prev_clip = translation(nan[DType.float32](), 0, 0)
    with assert_raises(contains="previous clip matrices"):
        check_frame_constants(bad)
    bad = FrameConstants()
    bad.prev_clip_to_clip = translation(inf[DType.float32](), 0, 0)
    with assert_raises(contains="previous clip matrices"):
        check_frame_constants(bad)


def test_the_constants_check_refuses_a_bad_jitter() raises:
    var bad = FrameConstants()
    bad.jitter_offset = Vector2(nan[DType.float32](), 0)
    with assert_raises(contains="jitter must be finite"):
        check_frame_constants(bad)
    bad.jitter_offset = Vector2(0, inf[DType.float32]())
    with assert_raises(contains="jitter must be finite"):
        check_frame_constants(bad)
    bad.jitter_offset = Vector2(0.5001, 0)
    with assert_raises(contains="half a pixel"):
        check_frame_constants(bad)
    bad.jitter_offset = Vector2(0, -0.5001)
    with assert_raises(contains="half a pixel"):
        check_frame_constants(bad)
    bad.jitter_offset = Vector2(-0.5, 0.5)
    check_frame_constants(bad)


def test_the_constants_check_refuses_a_bad_motion_scale() raises:
    var bad = FrameConstants()
    bad.mvec_scale = Vector2(nan[DType.float32](), 1)
    with assert_raises(contains="scale must be finite"):
        check_frame_constants(bad)
    bad.mvec_scale = Vector2(1, nan[DType.float32]())
    with assert_raises(contains="scale must be finite"):
        check_frame_constants(bad)
    bad.mvec_scale = Vector2(0, 1)
    with assert_raises(contains="scale must be positive"):
        check_frame_constants(bad)
    bad.mvec_scale = Vector2(1, -1)
    with assert_raises(contains="scale must be positive"):
        check_frame_constants(bad)


def test_the_constants_check_refuses_an_axis_that_is_not_a_unit_vector() raises:
    var bad = FrameConstants()
    bad.camera_up = Vector3(0, 2, 0)
    with assert_raises(contains="unit vectors"):
        check_frame_constants(bad)
    bad = FrameConstants()
    bad.camera_right = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises(contains="unit vectors"):
        check_frame_constants(bad)
    bad = FrameConstants()
    bad.camera_forward = Vector3(0, inf[DType.float32](), -1)
    with assert_raises(contains="unit vectors"):
        check_frame_constants(bad)
    bad = FrameConstants()
    bad.camera_forward = Vector3(0, 0, nan[DType.float32]())
    with assert_raises(contains="unit vectors"):
        check_frame_constants(bad)
    bad = FrameConstants()
    bad.camera_position = Vector3(0, nan[DType.float32](), 0)
    with assert_raises(contains="position"):
        check_frame_constants(bad)


def test_the_constants_check_refuses_a_bad_lens() raises:
    var nan32 = nan[DType.float32]()
    var nears: List[Float32] = [nan32, 0, 1, 2]
    var fars: List[Float32] = [1, 1, nan32, 1]
    for at in range(len(nears)):
        var bad = FrameConstants()
        bad.camera_near = Length(nears[at], METER)
        bad.camera_far = Length(fars[at], METER)
        with assert_raises(contains="clipping"):
            check_frame_constants(bad)
    var fovs: List[Float32] = [nan32, -0.1, 3.2]
    for fov in fovs:
        var bad = FrameConstants()
        bad.camera_fov = Angle(fov, RADIAN)
        with assert_raises(contains="field of view"):
            check_frame_constants(bad)
    var aspects: List[Float32] = [nan32, 0, -1]
    for aspect in aspects:
        var bad = FrameConstants()
        bad.camera_aspect = aspect
        with assert_raises(contains="aspect"):
            check_frame_constants(bad)


def memory(matrix: Matrix4) -> List[Float32]:
    """Return the sixteen floats of a matrix in memory order."""
    var floats = List[Float32]()
    for at in range(16):
        floats.append(matrix.elements[at])
    return floats^


def row_major_multiply(a: List[Float32], b: List[Float32]) -> List[Float32]:
    """Multiply two row-major matrices the way `sl::matrixMul` of
    `sl_matrix_helpers.h` does."""
    var product = List[Float32](length=16, fill=0)
    for row in range(4):
        for column in range(4):
            var sum = Float32(0)
            for at in range(4):
                sum += a[row * 4 + at] * b[at * 4 + column]
            product[row * 4 + column] = sum
    return product^


def test_a_matrix_has_streamline_s_layout_in_memory() raises:
    # `sl::float4x4` is row-major and puts the translation in row 3. A column
    # vector matrix of ThreeMojo holds the same floats, with no transpose.
    var moved = memory(translation(1, 2, 3))
    assert_equal(moved[12], 1)
    assert_equal(moved[13], 2)
    assert_equal(moved[14], 3)
    assert_equal(moved[15], 1)
    var scaled = memory(scaling(2, 3, 4))
    assert_equal(scaled[0], 2)
    assert_equal(scaled[5], 3)
    assert_equal(scaled[10], 4)


def test_the_previous_clip_matrix_is_the_row_vector_chain_of_streamline() raises:
    # `recalculateCameraMatrices` builds clipToPrevClip left to right as
    # clipToCameraView * cameraViewToPrevCameraView * cameraViewToClipPrev,
    # with row-major matrices that multiply a row vector. The floats of our
    # matrices in memory order must give the same product.
    var current = snapshot(2)
    var previous = snapshot(0)
    var constants = frame_constants(
        current,
        previous,
        FrameSize(1280, 720),
        Vector2(0, 0),
        MOTION_NORMALIZED,
        False,
    )
    var view_to_world = current.view
    view_to_world.invert()
    var chain = row_major_multiply(
        memory(constants.clip_to_camera_view), memory(view_to_world)
    )
    chain = row_major_multiply(chain, memory(previous.view))
    chain = row_major_multiply(chain, memory(previous.projection))
    var ours = memory(constants.clip_to_prev_clip)
    for at in range(16):
        assert_almost_equal(ours[at], chain[at], atol=1e-3, rtol=1e-4)
    var back = row_major_multiply(
        memory(constants.clip_to_prev_clip), memory(constants.prev_clip_to_clip)
    )
    for row in range(4):
        for column in range(4):
            var wanted = Float32(1) if row == column else Float32(0)
            assert_almost_equal(back[row * 4 + column], wanted, atol=1e-3)


def test_a_velocity_becomes_the_way_back_in_render_pixels() raises:
    # ThreeMojo: this frame less the last, in NDC with y up. Streamline: the
    # way back to the last frame, in render pixels with y down.
    var render = FrameSize(200, 100)
    var back = streamline_motion_vector(Vector2(0.1, 0.2), render)
    assert_almost_equal(back.x, -10, atol=1e-4)
    assert_almost_equal(back.y, 10, atol=1e-4)
    var still = streamline_motion_vector(Vector2(0, 0), render)
    assert_equal(still.x, 0)
    assert_equal(still.y, 0)
    with assert_raises(contains="finite"):
        _ = streamline_motion_vector(Vector2(nan[DType.float32](), 0), render)
    with assert_raises(contains="finite"):
        _ = streamline_motion_vector(Vector2(0, inf[DType.float32]()), render)
    with assert_raises(contains="render"):
        _ = streamline_motion_vector(Vector2(0, 0), FrameSize(0, 100))
    with assert_raises(contains="render"):
        _ = streamline_motion_vector(Vector2(0, 0), FrameSize(200, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
