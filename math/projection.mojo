# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The matrices that get a scene from world space onto a screen.

Three transforms in sequence, each answering one question:

    look_at      where is the camera, and which way is it facing?
    perspective  how does distance shrink things?
    orthographic ...or what if it does not?
    viewport     where on the image does a normalized point land?

Between the second and third, coordinates are in **normalized device
coordinates**: x and y run -1 to +1 across the visible frustum, and z runs
-1 (near plane) to +1 (far plane). NDC is dimensionless, which is the point.
World space is metres, screen space is pixels, and NDC is the neutral ground
between them where neither unit applies.

`perspective` matches three.js's `Matrix4.makePerspective` with the WebGL
coordinate system. three.js also supports WebGPU's convention, where z runs
0 to 1 rather than -1 to +1; only the WebGL form is ported here.
"""

from math.matrix4 import Matrix4
from math.vector3 import Vector3


def perspective(
    left: Float32,
    right: Float32,
    top: Float32,
    bottom: Float32,
    near: Float32,
    far: Float32,
) raises -> Matrix4:
    """Return a perspective projection for an arbitrary view frustum.

    The frustum is given by where its edges cut the near plane, which allows
    an off-centre projection; `PerspectiveCamera` builds a symmetric one.

    Args:
        left: Left edge of the frustum at the near plane.
        right: Right edge at the near plane.
        top: Top edge at the near plane.
        bottom: Bottom edge at the near plane.
        near: Distance to the near clipping plane; must be positive.
        far: Distance to the far clipping plane; must exceed `near`.

    Returns:
        A projection matrix mapping the frustum onto the NDC cube.

    Raises:
        Error: If the frustum is degenerate, or the planes are not ordered.
    """
    if near <= 0:
        raise Error("The near plane must be in front of the camera")
    if far <= near:
        raise Error("The far plane must be beyond the near plane")
    if right == left or top == bottom:
        raise Error("The frustum has no width or no height")

    var x = 2 * near / (right - left)
    var y = 2 * near / (top - bottom)
    # How far the frustum's centre line is skewed from straight ahead.
    var a = (right + left) / (right - left)
    var b = (top + bottom) / (top - bottom)
    var c = -(far + near) / (far - near)
    var d = -2 * far * near / (far - near)

    var matrix = Matrix4()
    # The -1 in the bottom row is what copies z into w, and dividing by w is
    # what makes distant things small. Everything else is scale and offset.
    matrix.set(x, 0, a, 0, 0, y, b, 0, 0, 0, c, d, 0, 0, -1, 0)
    return matrix^


def orthographic(
    left: Float32,
    right: Float32,
    top: Float32,
    bottom: Float32,
    near: Float32,
    far: Float32,
) raises -> Matrix4:
    """Return an orthographic projection for a box-shaped view volume.

    The parallel counterpart to `perspective`: distance no longer shrinks
    anything, so the frustum is a box rather than a pyramid and the edges are
    given in world units at any depth rather than at the near plane.

    The bottom row stays (0, 0, 0, 1), so the transformed w is always one and
    `transform_point`'s divide does nothing. That is the whole difference, and
    it is why the perspective-correct interpolation in the rasterizer quietly
    becomes a no-op here: every `inv_w` is one, the correction's denominator
    is one, and the weights come through unchanged.

    Matches three.js's `Matrix4.makeOrthographic` with the WebGL convention,
    where z runs -1 at the near plane to +1 at the far one.

    Args:
        left: Left edge of the view volume.
        right: Right edge.
        top: Top edge.
        bottom: Bottom edge.
        near: Distance to the near clipping plane; must be positive.
        far: Distance to the far clipping plane; must exceed `near`.

    Returns:
        A projection matrix mapping the box onto the NDC cube.

    Raises:
        Error: If the volume is degenerate, or the planes are not ordered.
            three.js allows a non-positive `near` here, since nothing divides
            by depth; this does not, because the clipper in `renderers.clip`
            is shared with the perspective path and the near plane has to sit
            in front of the camera for that to mean anything.
    """
    if near <= 0:
        raise Error("The near plane must be in front of the camera")
    if far <= near:
        raise Error("The far plane must be beyond the near plane")
    if right == left or top == bottom:
        raise Error("The view volume has no width or no height")

    var w = 1 / (right - left)
    var h = 1 / (top - bottom)
    var p = 1 / (far - near)

    var matrix = Matrix4()
    matrix.set(
        2 * w,
        0,
        0,
        -(right + left) * w,
        0,
        2 * h,
        0,
        -(top + bottom) * h,
        0,
        0,
        -2 * p,
        -(far + near) * p,
        0,
        0,
        0,
        1,
    )
    return matrix^


def look_at(eye: Vector3, target: Vector3, up: Vector3) raises -> Matrix4:
    """Return the view matrix for a camera at `eye` facing `target`.

    This is the inverse of the camera's own placement: it moves the world so
    the camera sits at the origin looking down -z, which is the convention
    three.js and OpenGL share.

    Args:
        eye: Camera position in world space.
        target: The point the camera looks at.
        up: Which way is up; need not be perpendicular to the view direction.

    Returns:
        A matrix transforming world space into camera space.

    Raises:
        Error: If the camera is at its own target, or `up` is parallel to the
            view direction, either of which leaves the basis undefined.
    """
    # z points back towards the camera, because the camera looks down -z.
    var forward = eye
    forward.sub(target)
    if forward.length() == 0:
        raise Error("The camera cannot sit at its own target")
    forward.normalize()

    var right = up
    right.cross(forward)
    if right.length() == 0:
        raise Error("Up is parallel to the view direction")
    right.normalize()

    # Already perpendicular unit vectors, so this needs no normalizing.
    var above = forward
    above.cross(right)

    var matrix = Matrix4()
    matrix.set(
        right.x,
        right.y,
        right.z,
        -right.dot(eye),
        above.x,
        above.y,
        above.z,
        -above.dot(eye),
        forward.x,
        forward.y,
        forward.z,
        -forward.dot(eye),
        0,
        0,
        0,
        1,
    )
    return matrix^


def viewport(width: Int, height: Int) raises -> Matrix4:
    """Return the matrix taking NDC to pixel coordinates.

    NDC has x and y running -1 to +1 with y upwards; an image has x running 0
    to width and y running *downwards* from the top. The y flip is that
    disagreement, and forgetting it renders everything upside down.

    Args:
        width: Image width in pixels.
        height: Image height in pixels.

    Returns:
        A matrix mapping the NDC cube onto the image.

    Raises:
        Error: If either dimension is not positive.
    """
    if width <= 0 or height <= 0:
        raise Error("Viewport dimensions must be positive")

    var half_width = Float32(width) / 2
    var half_height = Float32(height) / 2
    var matrix = Matrix4()
    matrix.set(
        half_width,
        0,
        0,
        half_width,
        0,
        -half_height,
        0,
        half_height,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
    )
    return matrix^
