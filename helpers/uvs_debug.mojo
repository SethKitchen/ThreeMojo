# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A geometry's texture coordinates drawn as an image, from three.js
`examples/jsm/utils/UVsDebug.js`.

`uvs_debug` draws each triangle's outline where its texture coordinates
put it on a square image, white under dark gray lines, as three.js draws
it on a canvas. `u` runs right and `v` up, and a coordinate of one lands
one pixel short of the edge, as three.js's `* ( size - 2 ) + 0.5` puts it.

three.js also writes each triangle's number at its middle, and each
corner's letter and vertex number halfway to it, in Arial. This port has
no canvas text. So `UVsDebug.labels` holds each label: its text, where
three.js writes it, its size in pixels and its color. The image does not
show them.

**Where this differs.** A canvas antialiases its lines. Here a line is the
pixels a one-pixel pen crosses, with no blending.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, UV
from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from std.math import floor, isfinite

# three.js's colors: the background, the lines and the triangle numbers,
# and the corner labels.
comptime UVS_BACKGROUND = Color(255, 255, 255)
comptime UVS_LINE = Color(63, 63, 63)
comptime UVS_CORNER = Color(191, 191, 191)
# The label sizes three.js writes, in pixels: `18px` and `12px`.
comptime UVS_FACE_SIZE = 18
comptime UVS_CORNER_SIZE = 12


@fieldwise_init
struct UVsDebugLabel(Copyable, Movable):
    """One label three.js writes with `fillText`."""

    var text: String
    # Where its center is, in pixels from the top left.
    var x: Float32
    var y: Float32
    # How tall it is, in pixels.
    var size: Int
    var color: Color


struct UVsDebug(Movable):
    """What `uvs_debug` draws: the image, each triangle's outline, and the
    labels three.js writes over it."""

    var image: Framebuffer
    # Each triangle's three corners, in pixels from the top left, as
    # three.js's `moveTo` and `lineTo` take them.
    var outlines: List[List[Vector2]]
    var labels: List[UVsDebugLabel]

    def __init__(out self, var image: Framebuffer):
        """Start with an image and nothing on it.

        Args:
            image: The image.
        """
        self.image = image^
        self.outlines = List[List[Vector2]]()
        self.labels = List[UVsDebugLabel]()


def _wrap(x: Float32) -> Float32:
    """Return JavaScript's `x % 1`, for the labels of a triangle across
    the right edge.

    A coordinate that is not finite, or that does not fit in an integer,
    is zero.

    Args:
        x: The coordinate.

    Returns:
        The fractional part, from zero up to but not including one.
    """
    if not isfinite(x) or not (x < Float32(Int.MAX)):
        return 0
    var whole = floor(x)
    return x - whole


def _outcode(x: Float32, y: Float32, right: Float32, bottom: Float32) -> Int:
    """Return which sides of the image a point is outside.

    Args:
        x: The column, in pixels.
        y: The row, in pixels.
        right: The last column.
        bottom: The last row.

    Returns:
        A bit for the left, right, top and bottom, or zero inside.
    """
    var code = 0
    if x < 0:
        code |= 1
    elif x > right:
        code |= 2
    if y < 0:
        code |= 4
    elif y > bottom:
        code |= 8
    return code


def _clip_segment(
    start: Vector2, end: Vector2, width: Int, height: Int
) -> Tuple[Bool, Vector2, Vector2]:
    """Return the part of a segment that lies on the image.

    Args:
        start: One end, in pixels.
        end: The other end, in pixels.
        width: The image width in pixels.
        height: The image height in pixels.

    Returns:
        Whether any of the segment lies on the image, and that part.
    """
    if not (
        isfinite(start.x)
        and isfinite(start.y)
        and isfinite(end.x)
        and isfinite(end.y)
    ):
        return False, start, end
    var x0 = start.x
    var y0 = start.y
    var x1 = end.x
    var y1 = end.y
    var right = Float32(width - 1)
    var bottom = Float32(height - 1)
    # Each step clips one end to one side. An accept or a reject ends it.
    while True:
        var c0 = _outcode(x0, y0, right, bottom)
        var c1 = _outcode(x1, y1, right, bottom)
        if (c0 | c1) == 0:
            return True, Vector2(x0, y0), Vector2(x1, y1)
        if (c0 & c1) != 0:
            return False, start, end
        var code = c0 if c0 != 0 else c1
        # The left side is the remaining case, so this value is that crossing.
        var hit = Vector2(0, y0 + (y1 - y0) * (0 - x0) / (x1 - x0))
        if (code & 8) != 0:
            hit = Vector2(x0 + (x1 - x0) * (bottom - y0) / (y1 - y0), bottom)
        elif (code & 4) != 0:
            hit = Vector2(x0 + (x1 - x0) * (0 - y0) / (y1 - y0), 0)
        elif (code & 2) != 0:
            hit = Vector2(right, y0 + (y1 - y0) * (right - x0) / (x1 - x0))
        if code == c0:
            x0 = hit.x
            y0 = hit.y
        else:
            x1 = hit.x
            y1 = hit.y


def uvs_debug(geometry: BufferGeometry, size: Int = 1024) raises -> UVsDebug:
    """Draw a geometry's texture coordinates, three.js's `UVsDebug`.

    Args:
        geometry: The geometry. Its `uv` attribute is read, by its index
            when it has one.
        size: How wide and high the image is, in pixels.

    Returns:
        The image, the outlines and the labels.

    Raises:
        Error: If the geometry has no `uv`, or the size is below three.
    """
    if size < 3:
        raise Error("A UV image needs to be three pixels wide or more")
    if not geometry.has_attribute(String(UV)):
        raise Error("A UV image needs a geometry with texture coordinates")
    ref uvs = geometry.attribute_view(String(UV))
    var out = UVsDebug(Framebuffer(size, size, UVS_BACKGROUND))
    var indexed = len(geometry.index) > 0
    var count = len(geometry.index) if indexed else uvs.count()
    for i in range(0, count - 2, 3):  # pragma: no branch
        var face = List[Int]()
        for j in range(3):  # pragma: no branch
            face.append(geometry.index[i + j] if indexed else i + j)
        _face(out, uvs, face, i // 3, size)
    return out^


def _face(
    mut out: UVsDebug,
    uvs: BufferAttribute,
    face: List[Int],
    index: Int,
    size: Int,
) raises:
    """Outline one triangle and list its labels, three.js's
    `processFace`."""
    var width = Float32(size)
    var corners = List[Vector2]()
    var mean = Vector2(0, 0)
    for j in range(3):  # pragma: no branch
        var uv = Vector2(uvs.component(face[j], 0), uvs.component(face[j], 1))
        mean = Vector2(mean.x + uv.x, mean.y + uv.y)
        corners.append(
            Vector2(uv.x * (width - 2) + 0.5, (1 - uv.y) * (width - 2) + 0.5)
        )
    for j in range(3):  # pragma: no branch
        _line(out.image, corners[j], corners[(j + 1) % 3])
    out.outlines.append(corners^)
    mean = Vector2(mean.x / 3, mean.y / 3)
    var number = String(index)
    out.labels.append(
        UVsDebugLabel(
            number,
            mean.x * width,
            (1 - mean.y) * width,
            UVS_FACE_SIZE,
            UVS_LINE,
        )
    )
    if mean.x > 0.95:
        out.labels.append(
            UVsDebugLabel(
                number,
                _wrap(mean.x) * width,
                (1 - mean.y) * width,
                UVS_FACE_SIZE,
                UVS_LINE,
            )
        )
    var letters: List[String] = ["a", "b", "c"]
    for j in range(3):  # pragma: no branch
        var uv = Vector2(uvs.component(face[j], 0), uvs.component(face[j], 1))
        var half = Vector2((mean.x + uv.x) / 2, (mean.y + uv.y) / 2)
        var text = letters[j] + String(face[j])
        out.labels.append(
            UVsDebugLabel(
                text,
                half.x * width,
                (1 - half.y) * width,
                UVS_CORNER_SIZE,
                UVS_CORNER,
            )
        )
        if half.x > 0.95:
            out.labels.append(
                UVsDebugLabel(
                    text,
                    _wrap(half.x) * width,
                    (1 - half.y) * width,
                    UVS_CORNER_SIZE,
                    UVS_CORNER,
                )
            )


def _line(mut image: Framebuffer, start: Vector2, end: Vector2) raises:
    """Mark the pixels a one-pixel pen crosses from one point to another,
    those on the image."""
    var kept = _clip_segment(start, end, image.width, image.height)
    if not kept[0]:
        return
    var dx = kept[2].x - kept[1].x
    var dy = kept[2].y - kept[1].y
    var steps = Int(max(abs(dx), abs(dy))) + 1
    for step in range(steps + 1):  # pragma: no branch
        var t = Float32(step) / Float32(steps)
        var x = Int(floor(kept[1].x + dx * t))
        var y = Int(floor(kept[1].y + dy * t))
        if x >= 0 and x < image.width and y >= 0 and y < image.height:
            image.set_pixel(x, y, UVS_LINE)
