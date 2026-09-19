# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a camera sees, drawn as lines, from three.js
`src/helpers/CameraHelper.js`.

The frustum's near and far rectangles and the four edges between them,
a cone from the camera's origin point to the near corners, a triangle
above the near plane that says which way is up, a line down the middle
from near to far, and a cross on each plane. Five colors, one a part.

Every point is a corner of clip space, `(±1, ±1, ±1)` and a few points
near them, carried back through the inverse of the projection. That is
three.js's `unproject` against a camera whose world matrix is the
identity, so the points come out in the camera's own frame: the near
rectangle is at `z = -near`, the far one at `z = -far`. The helper
belongs on the node the camera rides, as three.js's takes the camera's
`matrixWorld` for its own.

The cone's apex, `p`, is clip space's own origin carried back, which is
not the camera's position. Under a perspective projection it is a point
between the two planes, and the cone reaches it from the near corners:
that is what three.js draws, and it is kept.
"""

from cameras.camera import Camera
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor

# three.js's five colors, as authored.
comptime DEFAULT_FRUSTUM_COLOR = Color(0xFF, 0xAA, 0x00)
comptime DEFAULT_CONE_COLOR = Color(0xFF, 0x00, 0x00)
comptime DEFAULT_UP_COLOR = Color(0x00, 0xAA, 0xFF)
comptime DEFAULT_TARGET_COLOR = Color(0xFF, 0xFF, 0xFF)
comptime DEFAULT_CROSS_COLOR = Color(0x33, 0x33, 0x33)

# Clip-space depth of the near and far planes, three.js's WebGL
# convention, which `math.projection` follows.
comptime NEAR_Z = Float32(-1)
comptime FAR_Z = Float32(1)


def _push(
    mut positions: List[Float32],
    mut colors: List[Float32],
    unproject: Matrix4,
    x: Float32,
    y: Float32,
    z: Float32,
    color: FloatColor,
):
    """Append one clip-space point, carried back to the camera's frame."""
    var point = unproject.transform_point(Vector3(x, y, z))
    positions.append(point.x)
    positions.append(point.y)
    positions.append(point.z)
    colors.append(color.r)
    colors.append(color.g)
    colors.append(color.b)


def camera_helper[
    C: Camera
](
    camera: C,
    frustum_color: Color = DEFAULT_FRUSTUM_COLOR,
    cone_color: Color = DEFAULT_CONE_COLOR,
    up_color: Color = DEFAULT_UP_COLOR,
    target_color: Color = DEFAULT_TARGET_COLOR,
    cross_color: Color = DEFAULT_CROSS_COLOR,
) raises -> BufferGeometry:
    """Return the outline of what `camera` sees, in the camera's own frame,
    for a `Line` in `SEGMENTS` mode on the node the camera rides.

    Args:
        camera: The camera to outline. Its projection is read and nothing
            else: where it is comes from the node the helper is put on.
        frustum_color: The near and far rectangles and the edges between
            them, as authored in sRGB.
        cone_color: The four lines from the apex to the near corners.
        up_color: The triangle above the near plane.
        target_color: The line from the near plane's center to the far
            plane's.
        cross_color: The line from the apex to the near plane's center,
            and the cross on each plane.

    Returns:
        Fifty points, two per line, in three.js's order, with a `color`
        attribute in linear light.

    Raises:
        Error: If the camera's projection cannot be built.
    """
    var unproject = camera.projection_matrix()
    unproject.invert()
    var frustum = FloatColor(srgb=frustum_color)
    var cone = FloatColor(srgb=cone_color)
    var up = FloatColor(srgb=up_color)
    var target = FloatColor(srgb=target_color)
    var cross = FloatColor(srgb=cross_color)
    var positions = List[Float32]()
    var colors = List[Float32]()
    # Each line is two clip-space points and one color. The names are
    # three.js's: n for near, f for far, p the apex, u the up triangle,
    # c and t the two plane centers, cn and cf the two crosses.
    var lines: List[Float32] = [
        # near: n1 n2, n2 n4, n4 n3, n3 n1
        -1,
        -1,
        NEAR_Z,
        1,
        -1,
        NEAR_Z,
        1,
        -1,
        NEAR_Z,
        1,
        1,
        NEAR_Z,
        1,
        1,
        NEAR_Z,
        -1,
        1,
        NEAR_Z,
        -1,
        1,
        NEAR_Z,
        -1,
        -1,
        NEAR_Z,
        # far: f1 f2, f2 f4, f4 f3, f3 f1
        -1,
        -1,
        FAR_Z,
        1,
        -1,
        FAR_Z,
        1,
        -1,
        FAR_Z,
        1,
        1,
        FAR_Z,
        1,
        1,
        FAR_Z,
        -1,
        1,
        FAR_Z,
        -1,
        1,
        FAR_Z,
        -1,
        -1,
        FAR_Z,
        # sides: n1 f1, n2 f2, n3 f3, n4 f4
        -1,
        -1,
        NEAR_Z,
        -1,
        -1,
        FAR_Z,
        1,
        -1,
        NEAR_Z,
        1,
        -1,
        FAR_Z,
        -1,
        1,
        NEAR_Z,
        -1,
        1,
        FAR_Z,
        1,
        1,
        NEAR_Z,
        1,
        1,
        FAR_Z,
        # cone: p n1, p n2, p n3, p n4
        0,
        0,
        0,
        -1,
        -1,
        NEAR_Z,
        0,
        0,
        0,
        1,
        -1,
        NEAR_Z,
        0,
        0,
        0,
        -1,
        1,
        NEAR_Z,
        0,
        0,
        0,
        1,
        1,
        NEAR_Z,
        # up: u1 u2, u2 u3, u3 u1
        0.7,
        1.1,
        NEAR_Z,
        -0.7,
        1.1,
        NEAR_Z,
        -0.7,
        1.1,
        NEAR_Z,
        0,
        2,
        NEAR_Z,
        0,
        2,
        NEAR_Z,
        0.7,
        1.1,
        NEAR_Z,
        # target: c t, then p c
        0,
        0,
        NEAR_Z,
        0,
        0,
        FAR_Z,
        0,
        0,
        0,
        0,
        0,
        NEAR_Z,
        # cross: cn1 cn2, cn3 cn4, cf1 cf2, cf3 cf4
        -1,
        0,
        NEAR_Z,
        1,
        0,
        NEAR_Z,
        0,
        -1,
        NEAR_Z,
        0,
        1,
        NEAR_Z,
        -1,
        0,
        FAR_Z,
        1,
        0,
        FAR_Z,
        0,
        -1,
        FAR_Z,
        0,
        1,
        FAR_Z,
    ]
    # Which color each of the twenty-five lines takes, in that order.
    var paints = List[FloatColor]()
    for _ in range(12):  # pragma: no branch
        paints.append(frustum)
    for _ in range(4):  # pragma: no branch
        paints.append(cone)
    for _ in range(3):  # pragma: no branch
        paints.append(up)
    paints.append(target)
    for _ in range(5):  # pragma: no branch
        paints.append(cross)
    for line in range(len(paints)):  # pragma: no branch
        for end in range(2):  # pragma: no branch
            var at = (line * 2 + end) * 3
            _push(
                positions,
                colors,
                unproject,
                lines[at],
                lines[at + 1],
                lines[at + 2],
                paints[line],
            )
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^
