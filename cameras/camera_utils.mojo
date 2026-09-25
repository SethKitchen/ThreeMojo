# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera fitted to a rectangle in the world, from three.js
`examples/jsm/utils/CameraUtils.js`.

`frame_corners` makes a perspective camera see through a rectangle, as a
window in a wall is seen: the frustum's near plane lies parallel to the
rectangle, and its edges pass through the rectangle's edges. The camera
stays where it is. It turns to face the rectangle square on, and its
projection becomes three.js's off-axis matrix, set in
`projection_override`. This is Kooima's generalized perspective
projection, which three.js follows.

The rectangle is given by three corners: the bottom left, the bottom
right and the top left. The camera's up follows the rectangle's left
edge.
"""

from cameras.perspective_camera import PerspectiveCamera
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import atan
from units.si import Angle, DEGREE, RADIAN, METER


def frame_corners(
    mut camera: PerspectiveCamera,
    bottom_left: Vector3,
    bottom_right: Vector3,
    top_left: Vector3,
    estimate_view_frustum: Bool = False,
) raises:
    """Fit a camera's view to a rectangle, three.js's `frameCorners`.

    Args:
        camera: The camera. Its position is the eye, and its near and far
            planes are kept.
        bottom_left: The rectangle's bottom left corner.
        bottom_right: Its bottom right corner.
        top_left: Its top left corner.
        estimate_view_frustum: True to also set the camera's field of view
            to three.js's estimate of the angle the rectangle takes, for
            the code that reads `fov`.

    Raises:
        Error: If the corners lie on one line, or the eye lies in the
            rectangle's plane.
    """
    var eye = camera.position
    var near = camera.near.to(METER)
    var far = camera.far.to(METER)
    var right = bottom_right - bottom_left
    var up = top_left - bottom_left
    if right.length() == 0 or up.length() == 0:
        raise Error("A frame needs three corners that are not on one line")
    right.normalize()
    up.normalize()
    var normal = right
    normal.cross(up)
    if normal.length() == 0:
        raise Error("A frame needs three corners that are not on one line")
    normal.normalize()
    var to_bottom_left = bottom_left - eye
    var to_bottom_right = bottom_right - eye
    var to_top_left = top_left - eye
    var distance = -to_bottom_left.dot(normal)
    if distance == 0:
        raise Error("A frame cannot be seen from its own plane")
    var left_edge = right.dot(to_bottom_left) * near / distance
    var right_edge = right.dot(to_bottom_right) * near / distance
    var bottom_edge = up.dot(to_bottom_left) * near / distance
    var top_edge = up.dot(to_top_left) * near / distance
    # three.js turns the camera's y to the rectangle's up and its z to the
    # rectangle's normal; the camera here looks down -z from its position.
    camera.target = eye - normal
    camera.up = up
    var projection = Matrix4()
    projection.set(
        2 * near / (right_edge - left_edge),
        0,
        (right_edge + left_edge) / (right_edge - left_edge),
        0,
        0,
        2 * near / (top_edge - bottom_edge),
        (top_edge + bottom_edge) / (top_edge - bottom_edge),
        0,
        0,
        0,
        (far + near) / (near - far),
        2 * far * near / (near - far),
        0,
        0,
        -1,
        0,
    )
    camera.projection_override = projection
    if estimate_view_frustum:
        var across = (bottom_right - bottom_left).length() + (
            top_left - bottom_left
        ).length()
        var degrees = (
            Angle(1.0, RADIAN).to(DEGREE)
            / min(Float32(1), camera.aspect)
            * atan(across / to_bottom_left.length())
        )
        camera.fov = Angle(degrees, DEGREE)
