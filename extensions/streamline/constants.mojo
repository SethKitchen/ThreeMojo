# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The constants that Streamline wants once a frame, `sl::Constants`.

`slSetConstants` takes the camera of the frame, and of the one before, so
that DLSS can follow the pixels. `frame_constants` builds them from two
`CameraSnapshot`s, the way `sl_consts.h` of Streamline 2.14.16 defines them:

- `cameraViewToClip` and `clipToCameraView` are the projection and its
  inverse. `clipToPrevClip` takes a point from this frame's clip space to the
  last frame's, with the camera as the only thing that moved:
  `clipToView * viewToViewPrev * viewToClipPrev`. `prevClipToClip` is its
  inverse.
- None of the four matrices may carry the jitter. Take the snapshot of the
  camera before it is moved, and never of a `JitteredCamera`. The jitter goes
  in `jitter_offset`, in render pixels.
- The camera's position and axes are in world space, the field of view is
  vertical, and `reset` says the last frame has nothing to do with this one.

**The matrix layout is settled.** `Matrix4` is column-major and multiplies a
column vector. Streamline's `float4x4` is row-major and multiplies a row
vector: `sl_matrix_helpers.h` puts the translation in row 3, and builds
`clipToPrevClip` as `clipToCameraView * cameraViewToPrevCameraView *
cameraViewToClipPrev`, left to right. A column-major matrix of column vectors
holds the same sixteen floats in memory as the transposed, row-major matrix of
row vectors. A binding copies `Matrix4.elements` as it is, with no transpose.
`tests/test_streamline_constants.mojo` checks this against the order of
`matrixMul`.

**Conventions kept open.** Streamline's headers do not say which range its
clip-space depth has, or which way `jitterOffset` points. The unit of the
motion vectors is not open: `mvec_scale` is one and one for vectors that are
`MOTION_NORMALIZED`, and one over the render size for `MOTION_PIXELS`, as the
programming guides write them. The sign of the motion vectors is open, and so
is whether they point from the previous frame to this one or the other way. A
native binding must settle those against a running DLSS.
"""

from cameras.camera import Camera
from core.scene import Scene
from extensions.streamline.kinds import MOTION_PIXELS, MotionVectorSpace
from extensions.streamline.sizing import FrameSize
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import atan, isfinite, pi
from units.si import Angle, Length, METER, RADIAN


struct CameraSnapshot(Copyable, Movable):
    """A camera as one frame saw it, before any jitter."""

    # World space to camera space.
    var view: Matrix4
    # Camera space to clip space, without the jitter.
    var projection: Matrix4
    # The clipping distances.
    var near: Length
    var far: Length

    def __init__(
        out self,
        view: Matrix4,
        projection: Matrix4,
        near: Length,
        far: Length,
    ):
        """Hold the parts of a camera.

        Args:
            view: The matrix from world space to camera space.
            projection: The matrix from camera space to clip space, without
                the jitter.
            near: The near clipping distance.
            far: The far clipping distance.
        """
        self.view = view
        self.projection = projection
        self.near = near
        self.far = far

    def __init__[C: Camera](out self, camera: C, scene: Scene) raises:
        """Take a camera as it is now.

        Parameters:
            C: The camera's type. It must not be a `JitteredCamera`.

        Args:
            camera: The camera.
            scene: The scene the camera may ride a node of, updated.

        Raises:
            Error: If the camera's `view_matrix_in` or `projection_matrix`
                raises.
        """
        self.view = camera.view_matrix_in(scene)
        self.projection = camera.projection_matrix()
        self.near = Length(camera.near_distance(), METER)
        self.far = Length(camera.far_distance(), METER)


def _inverse(matrix: Matrix4, what: String) raises -> Matrix4:
    """Return the inverse of a matrix, or refuse one that has none."""
    var determinant = matrix.determinant()
    if determinant == 0 or not isfinite(determinant):
        raise Error("The " + what + " matrix must be invertible")
    var inverse = matrix
    inverse.invert()
    if not inverse.is_finite():
        raise Error("The " + what + " matrix must be invertible")
    return inverse^


def check_camera_snapshot(snapshot: CameraSnapshot) raises:
    """Refuse a camera that DLSS could not follow.

    Args:
        snapshot: The camera.

    Raises:
        Error: If a matrix is not finite or has no inverse, a distance is
            not finite, the near distance is not positive, the far distance
            is not beyond it, or the projection has no scale across or up.
    """
    if not snapshot.view.is_finite():
        raise Error("The view matrix must be finite")
    if not snapshot.projection.is_finite():
        raise Error("The projection matrix must be finite")
    var near = snapshot.near.to(METER)
    var far = snapshot.far.to(METER)
    if not (isfinite(near) and isfinite(far) and near > 0 and far > near):
        raise Error("The clipping distances must be finite, 0 < near < far")
    _ = _inverse(snapshot.view, "view")
    _ = _inverse(snapshot.projection, "projection")
    if (
        snapshot.projection.elements[0] == 0
        or snapshot.projection.elements[5] == 0
    ):
        raise Error("The projection must scale across and up")


struct FrameConstants(Copyable, Movable):
    """What `slSetConstants` gets, `sl::Constants`. `frame_constants` builds
    it from two cameras."""

    # `cameraViewToClip`, `clipToCameraView`, `clipToPrevClip` and
    # `prevClipToClip`, without the jitter.
    var camera_view_to_clip: Matrix4
    var clip_to_camera_view: Matrix4
    var clip_to_prev_clip: Matrix4
    var prev_clip_to_clip: Matrix4
    # `jitterOffset`, in render pixels.
    var jitter_offset: Vector2
    # `mvecScale`.
    var mvec_scale: Vector2
    # `cameraPos`, `cameraUp`, `cameraRight` and `cameraFwd`, in world space.
    var camera_position: Vector3
    var camera_up: Vector3
    var camera_right: Vector3
    var camera_forward: Vector3
    # `cameraNear`, `cameraFar`, `cameraFOV` (vertical) and
    # `cameraAspectRatio`.
    var camera_near: Length
    var camera_far: Length
    var camera_fov: Angle
    var camera_aspect: Float32
    # `depthInverted`: a nearer point has the larger depth.
    var depth_inverted: Bool
    # `cameraMotionIncluded`: the motion vectors hold the camera's motion.
    var camera_motion_included: Bool
    # `motionVectors3D`: the motion vectors have a depth component.
    var motion_vectors_3d: Bool
    # `reset`: the last frame has nothing to do with this one.
    var reset: Bool
    # `orthographicProjection`.
    var orthographic: Bool
    # `motionVectorsDilated` and `motionVectorsJittered`.
    var motion_vectors_dilated: Bool
    var motion_vectors_jittered: Bool

    def __init__(out self):
        """Start with identity matrices, no jitter, a camera at the origin
        that looks down minus z, and Streamline's default flags."""
        self.camera_view_to_clip = Matrix4()
        self.clip_to_camera_view = Matrix4()
        self.clip_to_prev_clip = Matrix4()
        self.prev_clip_to_clip = Matrix4()
        self.jitter_offset = Vector2(0, 0)
        self.mvec_scale = Vector2(1, 1)
        self.camera_position = Vector3(0, 0, 0)
        self.camera_up = Vector3(0, 1, 0)
        self.camera_right = Vector3(1, 0, 0)
        self.camera_forward = Vector3(0, 0, -1)
        self.camera_near = Length(0.1, METER)
        self.camera_far = Length(100.0, METER)
        self.camera_fov = Angle(1.0, RADIAN)
        self.camera_aspect = 1
        self.depth_inverted = False
        self.camera_motion_included = True
        self.motion_vectors_3d = False
        self.reset = False
        self.orthographic = False
        self.motion_vectors_dilated = False
        self.motion_vectors_jittered = False


def _finite2(vector: Vector2) -> Bool:
    """Return True if both components are finite."""
    return isfinite(vector.x) and isfinite(vector.y)


def _unit_axis(axis: Vector3) -> Bool:
    """Return True if an axis is finite and has a length of one."""
    if not (isfinite(axis.x) and isfinite(axis.y) and isfinite(axis.z)):
        return False
    return abs(axis.length() - 1) <= 1e-3


def check_frame_constants(constants: FrameConstants) raises:
    """Refuse constants that DLSS could not use.

    Args:
        constants: The constants.

    Raises:
        Error: If a matrix is not finite, the jitter lies outside a half
            pixel each way or is not finite, the motion scale is not
            positive, an axis is not a unit vector, a clipping distance is
            wrong, or the field of view or the aspect ratio is.
    """
    if not (
        constants.camera_view_to_clip.is_finite()
        and constants.clip_to_camera_view.is_finite()
    ):
        raise Error("The projection matrices must be finite")
    if not (
        constants.clip_to_prev_clip.is_finite()
        and constants.prev_clip_to_clip.is_finite()
    ):
        raise Error("The previous clip matrices must be finite")
    if not _finite2(constants.jitter_offset):
        raise Error("The jitter must be finite")
    if (
        abs(constants.jitter_offset.x) > 0.5
        or abs(constants.jitter_offset.y) > 0.5
    ):
        raise Error("The jitter must lie within half a pixel each way")
    if not _finite2(constants.mvec_scale):
        raise Error("The motion vector scale must be finite")
    if constants.mvec_scale.x <= 0 or constants.mvec_scale.y <= 0:
        raise Error("The motion vector scale must be positive")
    if not (
        _unit_axis(constants.camera_up)
        and _unit_axis(constants.camera_right)
        and _unit_axis(constants.camera_forward)
    ):
        raise Error("The camera axes must be unit vectors")
    if not isfinite(
        constants.camera_position.x
        + constants.camera_position.y
        + constants.camera_position.z
    ):
        raise Error("The camera position must be finite")
    var near = constants.camera_near.to(METER)
    var far = constants.camera_far.to(METER)
    if not (isfinite(near) and isfinite(far) and near > 0 and far > near):
        raise Error("The clipping distances must be finite, 0 < near < far")
    var fov = constants.camera_fov.to(RADIAN)
    if not (isfinite(fov) and fov >= 0 and fov < pi):
        raise Error("The field of view must be from 0 up to pi")
    if not (isfinite(constants.camera_aspect) and constants.camera_aspect > 0):
        raise Error("The aspect ratio must be finite and positive")


def frame_constants(
    current: CameraSnapshot,
    previous: CameraSnapshot,
    render: FrameSize,
    jitter: Vector2,
    motion: MotionVectorSpace,
    reset: Bool,
) raises -> FrameConstants:
    """Build the constants of a frame from two cameras.

    Args:
        current: The camera of this frame, before the jitter.
        previous: The camera of the last frame, before its jitter. It is
            ignored when `reset` is true.
        render: The size the scene is rendered at.
        jitter: The offset of this frame, in render pixels.
        motion: The unit of the motion vectors.
        reset: Whether the last frame has nothing to do with this one.

    Returns:
        The constants. The depth is not inverted, the motion vectors hold
        the camera's motion, and they are neither 3D, dilated nor jittered.

    Raises:
        Error: If a camera is refused by `check_camera_snapshot`, the render
            has a side below one pixel, the motion space is not valid, or
            `check_frame_constants` refuses the result.
    """
    check_camera_snapshot(current)
    if not reset:
        check_camera_snapshot(previous)
    if render.width < 1 or render.height < 1:
        raise Error("A render must be at least one pixel each way")
    if not motion.is_valid():
        raise Error("A motion vector space must be normalized or pixels")
    var last = current.copy() if reset else previous.copy()
    var constants = FrameConstants()
    constants.camera_view_to_clip = current.projection
    constants.clip_to_camera_view = _inverse(current.projection, "projection")
    # P' V' V^-1 P^-1: a clip point to the world, and on to the last clip.
    var to_prev = last.projection
    to_prev.multiply(last.view)
    to_prev.multiply(_inverse(current.view, "view"))
    to_prev.multiply(constants.clip_to_camera_view)
    constants.clip_to_prev_clip = to_prev
    # P V V'^-1 P'^-1: the same trip the other way.
    var to_clip = current.projection
    to_clip.multiply(current.view)
    to_clip.multiply(_inverse(last.view, "view"))
    to_clip.multiply(_inverse(last.projection, "projection"))
    constants.prev_clip_to_clip = to_clip
    constants.jitter_offset = jitter
    if motion == MOTION_PIXELS:
        constants.mvec_scale = Vector2(
            1 / Float32(render.width), 1 / Float32(render.height)
        )
    else:
        constants.mvec_scale = Vector2(1, 1)
    var camera_to_world = _inverse(current.view, "view")
    constants.camera_position = camera_to_world.transform_point(
        Vector3(0, 0, 0)
    )
    var right = camera_to_world.transform_direction(Vector3(1, 0, 0))
    right.normalize()
    var up = camera_to_world.transform_direction(Vector3(0, 1, 0))
    up.normalize()
    var forward = camera_to_world.transform_direction(Vector3(0, 0, -1))
    forward.normalize()
    constants.camera_right = right
    constants.camera_up = up
    constants.camera_forward = forward
    constants.camera_near = current.near
    constants.camera_far = current.far
    var scale_across = current.projection.elements[0]
    var scale_up = current.projection.elements[5]
    constants.camera_aspect = abs(scale_up / scale_across)
    constants.orthographic = current.projection.elements[15] != 0
    if constants.orthographic:
        constants.camera_fov = Angle(0.0, RADIAN)
    else:
        constants.camera_fov = Angle(2 * atan(1 / abs(scale_up)), RADIAN)
    constants.reset = reset
    check_frame_constants(constants)
    return constants^
