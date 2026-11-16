# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The values inside a circle on one slice of a volume.

A reader measures a region of an image by drawing a circle on a slice,
such as a CT number in a lesion or the noise in a uniform region.
`circle_statistics` gives the pixel count, the area, the mean, the
standard deviation, the least and the largest value of the pixels whose
centers lie in the circle.

The circle has a radius in units. With pixels that are not square, it
covers an ellipse of pixels. The center is in the pixel coordinates of
the slice, which can be between pixels:

| Axis | Pixel x | Pixel y |
|---|---|---|
| `K_AXIS` | `i` | `j` |
| `J_AXIS` | `i` | `k` |
| `I_AXIS` | `j` | `k` |

The standard deviation is the sample one, with `n - 1`, as ImageJ
reports it. A circle of one pixel has a deviation of zero.
"""

from extensions.imaging.ids import (
    I_AXIS,
    J_AXIS,
    K_AXIS,
    SliceAxis,
    require_axis,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.overlay import slice_size
from std.math import ceil, floor, isfinite, max, min, sqrt
from units.si import Area64, Length64, METER, SQUARE_METER


struct RegionStatistics(Copyable, Movable):
    """The values of the pixels inside a region of a slice."""

    var pixels: Int
    """The number of pixels."""
    var area: Area64
    """The pixel count times the area of one pixel."""
    var mean: Float64
    """The mean value, in the units of the volume."""
    var deviation: Float64
    """The sample standard deviation, in the units of the volume."""
    var minimum: Float64
    """The least value."""
    var maximum: Float64
    """The largest value."""

    def __init__(out self):
        """Create empty statistics."""
        self.pixels = 0
        self.area = Area64(0, SQUARE_METER)
        self.mean = 0
        self.deviation = 0
        self.minimum = 0
        self.maximum = 0


def _spacing(volume: ImageVolume, axis: SliceAxis) -> Tuple[Float64, Float64]:
    """Return the pixel width and height of a slice, in meters."""
    var sx = volume.spacing_x.to(METER)
    var sy = volume.spacing_y.to(METER)
    var sz = volume.spacing_z.to(METER)
    if axis == K_AXIS:
        return (sx, sy)
    if axis == J_AXIS:
        return (sx, sz)
    return (sy, sz)


def _value(
    volume: ImageVolume, axis: SliceAxis, x: Int, y: Int, index: Int
) raises -> Float64:
    """Return the value of one pixel of a slice."""
    if axis == K_AXIS:
        return Float64(volume.get(x, y, index))
    if axis == J_AXIS:
        return Float64(volume.get(x, index, y))
    return Float64(volume.get(index, x, y))


def circle_statistics(
    volume: ImageVolume,
    axis: SliceAxis,
    index: Int,
    x: Float64,
    y: Float64,
    radius: Length64,
) raises -> RegionStatistics:
    """Return the statistics of the pixels inside a circle on a slice.

    A pixel is inside when its center is at most `radius` from the
    center of the circle.

    Args:
        volume: The volume.
        axis: The axis that the slice holds constant.
        index: The slice along that axis.
        x: The center along the slice's pixel x, in pixels.
        y: The center along the slice's pixel y, in pixels.
        radius: The radius of the circle. Positive and finite.

    Returns:
        The statistics.

    Raises:
        Error: If the axis is not valid, the slice is outside the volume,
            the center is not finite, the radius is not positive and
            finite, or no pixel center lies in the circle.
    """
    require_axis(axis)
    var depth = volume.nz
    if axis == J_AXIS:
        depth = volume.ny
    elif axis == I_AXIS:
        depth = volume.nx
    if index < 0 or index >= depth:
        raise Error("The slice index is outside the volume")
    if not isfinite(x) or not isfinite(y):
        raise Error("The center of a circle must be finite")
    var r = radius.to(METER)
    if not (r > 0) or not isfinite(r):
        raise Error("The radius of a circle must be positive and finite")
    var size = slice_size(volume.nx, volume.ny, volume.nz, axis)
    var pixel = _spacing(volume, axis)
    var reach_x = r / pixel[0]
    var reach_y = r / pixel[1]
    # Clamp in floating point first, so a far center cannot overflow.
    var width = Float64(size[0])
    var height = Float64(size[1])
    var x0 = Int(min(width, max(0.0, ceil(x - reach_x))))
    var x1 = Int(max(-1.0, min(width - 1, floor(x + reach_x))))
    var y0 = Int(min(height, max(0.0, ceil(y - reach_y))))
    var y1 = Int(max(-1.0, min(height - 1, floor(y + reach_y))))
    var out = RegionStatistics()
    var sum = 0.0
    var values = List[Float64]()
    for py in range(y0, y1 + 1):
        for px in range(x0, x1 + 1):
            var dx = (Float64(px) - x) * pixel[0]
            var dy = (Float64(py) - y) * pixel[1]
            if dx * dx + dy * dy > r * r:
                continue
            var value = _value(volume, axis, px, py, index)
            if len(values) == 0:
                out.minimum = value
                out.maximum = value
            out.minimum = min(out.minimum, value)
            out.maximum = max(out.maximum, value)
            sum += value
            values.append(value)
    var n = len(values)
    if n == 0:
        raise Error("No pixel center lies in the circle")
    out.pixels = n
    out.area = Area64(Float64(n) * pixel[0] * pixel[1], SQUARE_METER)
    out.mean = sum / Float64(n)
    if n > 1:
        var squares = 0.0
        for value in values:  # pragma: no branch
            var d = value - out.mean
            squares += d * d
        out.deviation = sqrt(squares / Float64(n - 1))
    return out^
