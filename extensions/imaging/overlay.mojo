# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draw a slice of a volume, its labels and measurement lines.

A slice holds one index constant. Its pixels map to voxels like this:

| Axis | Pixel x | Pixel y | Size |
|---|---|---|---|
| `K_AXIS` | `i` | `j` | `nx` by `ny` |
| `J_AXIS` | `i` | `k` | `nx` by `nz` |
| `I_AXIS` | `j` | `k` | `ny` by `nz` |

`render_slice` shows the values through the volume's window, one pixel
for each voxel. `overlay_labels` blends a color over each labeled pixel.
`draw_measurement` draws the line between two points of the slice, with
a small cross at each end.
"""

from extensions.imaging.ids import (
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    MONOCHROME1,
    SliceAxis,
    require_axis,
    require_label,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.transfer import Rgba, WindowLevel, clamp_unit
from extensions.sdf.vector import V3
from render.framebuffer import Framebuffer
from std.math import floor


def slice_size(
    nx: Int, ny: Int, nz: Int, axis: SliceAxis
) raises -> Tuple[Int, Int]:
    """Return the width and the height of a slice image.

    Args:
        nx: Voxels along `i`.
        ny: Voxels along `j`.
        nz: Voxels along `k`.
        axis: The axis the slice holds constant.

    Returns:
        The width and the height in pixels.

    Raises:
        Error: If the axis is not valid.
    """
    require_axis(axis)
    if axis == K_AXIS:
        return (nx, ny)
    if axis == J_AXIS:
        return (nx, nz)
    return (ny, nz)


def _depth(nx: Int, ny: Int, nz: Int, axis: SliceAxis) -> Int:
    """Return how many slices there are along an axis."""
    if axis == K_AXIS:
        return nz
    if axis == J_AXIS:
        return ny
    return nx


def _voxel(axis: SliceAxis, x: Int, y: Int, index: Int) -> Tuple[Int, Int, Int]:
    """Return the voxel of a slice pixel."""
    if axis == K_AXIS:
        return (x, y, index)
    if axis == J_AXIS:
        return (x, index, y)
    return (index, x, y)


def _require_slice(
    nx: Int, ny: Int, nz: Int, axis: SliceAxis, index: Int
) raises:
    """Refuse an axis that is not valid, or a slice past the grid."""
    require_axis(axis)
    var depth = _depth(nx, ny, nz, axis)
    if index < 0 or index >= depth:
        raise Error("The slice index is outside the volume")


def _byte(value: Float32) -> UInt8:
    """Return a channel from zero to one as a byte."""
    return UInt8(Int(clamp_unit(value) * 255 + 0.5))


def render_slice(
    volume: ImageVolume, axis: SliceAxis, index: Int
) raises -> Framebuffer:
    """Return one slice of a volume as a gray image.

    Args:
        volume: The volume. Its window and photometric interpretation
            apply.
        axis: The axis the slice holds constant.
        index: The slice along that axis.

    Returns:
        The image, one pixel for each voxel.

    Raises:
        Error: If the axis is not valid, the index is outside the volume,
            or the volume's window is not finite with a positive width.
    """
    _require_slice(volume.nx, volume.ny, volume.nz, axis, index)
    var window = WindowLevel(volume.window_center, volume.window_width)
    var size = slice_size(volume.nx, volume.ny, volume.nz, axis)
    var width = size[0]
    var height = size[1]
    var inverted = volume.photometric == MONOCHROME1
    var pixels = List[UInt8](length=width * height * 4, fill=255)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var v = _voxel(axis, x, y, index)
            var value = Float64(volume.values[volume.index(v[0], v[1], v[2])])
            var gray = Float32(window.apply(value))
            if inverted:
                gray = 1 - gray
            var level = _byte(gray)
            var at = (y * width + x) * 4
            pixels[at] = level
            pixels[at + 1] = level
            pixels[at + 2] = level
    return Framebuffer(width, height, pixels^)


def label_color(label: LabelId) raises -> Rgba:
    """Return the default color of a label.

    Labels cycle through eight colors. The background is clear.

    Args:
        label: The label.

    Returns:
        The color, opaque, or clear for the background.

    Raises:
        Error: If the label is not valid.
    """
    require_label(label)
    if label.value == 0:
        return Rgba(0, 0, 0, 0)
    var palette: List[Rgba] = [
        Rgba(0.90, 0.10, 0.15, 1),
        Rgba(0.10, 0.70, 0.25, 1),
        Rgba(0.15, 0.40, 0.95, 1),
        Rgba(0.95, 0.80, 0.10, 1),
        Rgba(0.75, 0.25, 0.85, 1),
        Rgba(0.10, 0.80, 0.85, 1),
        Rgba(0.95, 0.50, 0.10, 1),
        Rgba(0.60, 0.85, 0.20, 1),
    ]
    return palette[(label.value - 1) % 8]


def overlay_labels(
    mut image: Framebuffer,
    map: LabelMap,
    axis: SliceAxis,
    index: Int,
    opacity: Float32,
) raises:
    """Blend the label colors of one slice over its image.

    Args:
        image: The slice image, from `render_slice` of the same slice.
        map: The label map.
        axis: The axis the slice holds constant.
        index: The slice along that axis.
        opacity: How much of a label color shows, from zero to one.

    Raises:
        Error: If the axis is not valid, the index is outside the map,
            the image is not the slice's size, or the opacity is outside
            zero to one.
    """
    _require_slice(map.nx, map.ny, map.nz, axis, index)
    if not (opacity >= 0) or not (opacity <= 1):
        raise Error("A label opacity must be from 0 to 1")
    var size = slice_size(map.nx, map.ny, map.nz, axis)
    var width = size[0]
    if image.width != width or image.height != size[1]:
        raise Error("The image is not the size of the slice")
    var colors = List[Rgba]()
    for value in range(256):
        colors.append(label_color(LabelId(value)))
    for y in range(image.height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var v = _voxel(axis, x, y, index)
            var label = Int(map.labels[map.index(v[0], v[1], v[2])])
            if label == 0:
                continue
            ref color = colors[label]
            var at = (y * width + x) * 4
            image.pixels[at] = _blend(image.pixels[at], color.r, opacity)
            image.pixels[at + 1] = _blend(
                image.pixels[at + 1], color.g, opacity
            )
            image.pixels[at + 2] = _blend(
                image.pixels[at + 2], color.b, opacity
            )


def _blend(base: UInt8, color: Float32, opacity: Float32) -> UInt8:
    """Return a byte channel with a color blended over it."""
    var under = Float32(Int(base)) / 255
    return _byte(under + (color - under) * opacity)


def _project(axis: SliceAxis, point: V3) -> Tuple[Float64, Float64]:
    """Return the slice coordinates of a point in voxel units."""
    if axis == K_AXIS:
        return (point.x, point.y)
    if axis == J_AXIS:
        return (point.x, point.z)
    return (point.y, point.z)


def _plot(mut image: Framebuffer, x: Int, y: Int, color: Rgba):
    """Set one pixel when it is inside the image."""
    if x < 0 or y < 0 or x >= image.width or y >= image.height:
        return
    var at = (y * image.width + x) * 4
    image.pixels[at] = _byte(color.r)
    image.pixels[at + 1] = _byte(color.g)
    image.pixels[at + 2] = _byte(color.b)


def _line(
    mut image: Framebuffer, x0: Int, y0: Int, x1: Int, y1: Int, color: Rgba
):
    """Draw a line of pixels with Bresenham's algorithm."""
    var dx = abs(x1 - x0)
    var dy = -abs(y1 - y0)
    var sx = 1 if x0 < x1 else -1
    var sy = 1 if y0 < y1 else -1
    var error = dx + dy
    var x = x0
    var y = y0
    while True:
        _plot(image, x, y, color)
        if x == x1 and y == y1:
            return
        var twice = 2 * error
        if twice >= dy:
            error += dy
            x += sx
        if twice <= dx:
            error += dx
            y += sy


def _cross(mut image: Framebuffer, x: Int, y: Int, color: Rgba):
    """Draw a cross of five pixels."""
    _plot(image, x, y, color)
    _plot(image, x - 1, y, color)
    _plot(image, x + 1, y, color)
    _plot(image, x, y - 1, color)
    _plot(image, x, y + 1, color)


def draw_measurement(
    mut image: Framebuffer, axis: SliceAxis, a: V3, b: V3, color: Rgba
) raises:
    """Draw the line between two points of a slice, with a cross at each end.

    The points are in voxel units. The coordinate along the slice axis is
    ignored, so a point off the slice is drawn where it projects. Pixels
    past the image edge are skipped.

    Args:
        image: The slice image.
        axis: The axis the slice holds constant.
        a: The first point, in voxel units.
        b: The second point, in voxel units.
        color: The line color. Its opacity is ignored.

    Raises:
        Error: If the axis is not valid, or a point is not finite.
    """
    require_axis(axis)
    var start = _project(axis, a)
    var end = _project(axis, b)
    if not _finite(start) or not _finite(end):
        raise Error("A measurement needs finite points")
    var x0 = Int(floor(start[0] + 0.5))
    var y0 = Int(floor(start[1] + 0.5))
    var x1 = Int(floor(end[0] + 0.5))
    var y1 = Int(floor(end[1] + 0.5))
    _line(image, x0, y0, x1, y1, color)
    _cross(image, x0, y0, color)
    _cross(image, x1, y1, color)


def _finite(point: Tuple[Float64, Float64]) -> Bool:
    """Return whether both coordinates are finite and of a sane size."""
    return abs(point[0]) < 1.0e9 and abs(point[1]) < 1.0e9
