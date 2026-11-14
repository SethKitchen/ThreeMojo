# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The outlines of a label, and the isolines of values, in a slice.

`slice_outlines` gives the outlines of a label in one slice, and
`slice_isolines` the lines where the values of a slice cross a level,
such as an SUV or a temperature. Each is a closed loop of points in
voxel units, `(i, j, k)`, with its length and the area that it closes.
`draw_outlines` draws either on a slice image.

Both use marching squares. An isoline crosses each side of a square
between a pixel at or past the level and a pixel below it, where the
linear blend of their values is the level, as scikit-image's
`find_contours` does. A pixel past the edge of the slice is below every
level, so an isoline closes through the centers of the edge pixels.

Marching squares looks at each square of four pixel centers. The outline
crosses each side of the square between a pixel of the label and a
pixel outside it, at the middle of the side, as `label_surface` does in
three dimensions. A pixel past the edge of the slice is outside, so
every outline closes. Two pixels of the label that touch only at a
corner have outlines of their own: pixels connect by their sides.

Take the slice's pixel `x` and `y` of `render_slice` as plane axes. An
outer outline goes counterclockwise in them, with the label on its left,
and the outline of a hole goes the other way. On the screen, where `y`
points down, both look turned. So the area of an outer outline is
positive and the area of a hole is negative. The sum over the outlines
of a slice is the area inside the label's outlines. It is a little less
than the area of the pixels, because the outline cuts each corner.
"""

from extensions.imaging.ids import (
    BACKGROUND,
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    SliceAxis,
    require_axis,
    require_label,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from extensions.sdf.vector import V3, v3
from render.framebuffer import Framebuffer
from std.collections import Dict
from std.math import floor, inf, isfinite, sqrt
from units.si import Area64, Length64, METER, SQUARE_METER


@fieldwise_init
struct Outline(Copyable, Movable):
    """One closed outline of a label in a slice."""

    var points: List[V3]
    """The points in voxel units, `(i, j, k)`. The last joins the first."""
    var length: Length64
    """The length of the closed loop."""
    var area: Area64
    """The area that the loop closes: positive for an outer outline and
    negative for a hole."""


def _plane(
    nx: Int,
    ny: Int,
    nz: Int,
    spacing: Tuple[Length64, Length64, Length64],
    axis: SliceAxis,
) -> Tuple[Int, Int, Int, Float64, Float64]:
    """Return a slice's width, height and depth, and the spacing of its
    pixel `x` and `y`, in meters."""
    var sx = spacing[0].to(METER)
    var sy = spacing[1].to(METER)
    var sz = spacing[2].to(METER)
    if axis == K_AXIS:
        return (nx, ny, nz, sx, sy)
    if axis == J_AXIS:
        return (nx, nz, ny, sx, sz)
    return (ny, nz, nx, sy, sz)


def _voxel_point(axis: SliceAxis, x: Float64, y: Float64, index: Int) -> V3:
    """Return the voxel point of a slice point."""
    var depth = Float64(index)
    if axis == K_AXIS:
        return v3(x, y, depth)
    if axis == J_AXIS:
        return v3(x, depth, y)
    return v3(depth, x, y)


def _slice_point(axis: SliceAxis, p: V3) -> Tuple[Float64, Float64]:
    """Return the slice `x` and `y` of a voxel point."""
    if axis == K_AXIS:
        return (p.x, p.y)
    if axis == J_AXIS:
        return (p.x, p.z)
    return (p.y, p.z)


def _march(
    values: List[Float64],
    w: Int,
    h: Int,
    level: Float64,
    axis: SliceAxis,
    index: Int,
    px: Float64,
    py: Float64,
) raises -> List[Outline]:
    """Return the closed lines where a padded grid of values crosses a
    level. `values` holds `(w + 2) * (h + 2)` values, row by row, with a
    border of one pixel past the slice."""
    # A side's middle in doubled coordinates, from -2 to 2 w or 2 h, names
    # the side; the line crosses it where the values cross the level.
    var stride = 2 * w + 5
    var next = Dict[Int, Int]()
    var at_x = Dict[Int, Float64]()
    var at_y = Dict[Int, Float64]()
    var starts = List[Int]()
    var cx: List[Int] = [0, 1, 1, 0]
    var cy: List[Int] = [0, 0, 1, 1]
    for y in range(-1, h):  # pragma: no branch
        for x in range(-1, w):  # pragma: no branch
            var v = List[Float64]()
            for c in range(4):  # pragma: no branch
                v.append(values[(y + 1 + cy[c]) * (w + 2) + (x + 1 + cx[c])])
            for a in range(4):  # pragma: no branch
                # A run of corners at or past the level, counterclockwise
                # from a.
                if not (v[a] >= level) or v[(a + 3) % 4] >= level:
                    continue
                var b = a
                while v[(b + 1) % 4] >= level:
                    b = (b + 1) % 4
                # From the side after the run to the side before it. Each
                # side is crossed from its corner at the level toward the
                # corner below it.
                var after = (b + 1) % 4
                var before = (a + 3) % 4
                var keys = List[Int]()
                for side in range(2):  # pragma: no branch
                    var high = b if side == 0 else a
                    var low = after if side == 0 else before
                    var key = (2 * y + cy[high] + cy[low] + 2) * stride + (
                        2 * x + cx[high] + cx[low] + 2
                    )
                    if key not in at_x:
                        var t = (level - v[high]) / (v[low] - v[high])
                        at_x[key] = Float64(x + cx[high]) + t * Float64(
                            cx[low] - cx[high]
                        )
                        at_y[key] = Float64(y + cy[high]) + t * Float64(
                            cy[low] - cy[high]
                        )
                    keys.append(key)
                next[keys[0]] = keys[1]
                starts.append(keys[0])
    var used = Dict[Int, Bool]()
    var out = List[Outline]()
    for first in starts:
        if first in used:
            continue
        var xs = List[Float64]()
        var ys = List[Float64]()
        var key = first
        while True:
            used[key] = True
            xs.append(at_x[key])
            ys.append(at_y[key])
            key = next[key]
            if key == first:
                break
        var n = len(xs)
        var length = 0.0
        var twice = 0.0
        var points = List[V3]()
        for p in range(n):  # pragma: no branch
            var q = (p + 1) % n
            var dx = (xs[q] - xs[p]) * px
            var dy = (ys[q] - ys[p]) * py
            length += sqrt(dx * dx + dy * dy)
            twice += xs[p] * ys[q] - xs[q] * ys[p]
            points.append(_voxel_point(axis, xs[p], ys[p], index))
        out.append(
            Outline(
                points^,
                Length64(length, METER),
                Area64(0.5 * twice * px * py, SQUARE_METER),
            )
        )
    return out^


def _voxel(axis: SliceAxis, x: Int, y: Int, index: Int) -> Tuple[Int, Int, Int]:
    """Return the voxel of a slice pixel."""
    if axis == J_AXIS:
        return (x, index, y)
    if axis == I_AXIS:
        return (index, x, y)
    return (x, y, index)


def slice_outlines(
    map: LabelMap, label: LabelId, axis: SliceAxis, index: Int
) raises -> List[Outline]:
    """Return the outlines of a label in one slice.

    Args:
        map: The label map.
        label: The label. Not the background.
        axis: The axis that the slice holds constant.
        index: The slice, from 0.

    Returns:
        The outlines, in the order of their first square, row by row. A
        slice without the label has none.

    Raises:
        Error: If the label is not valid or is the background, the axis is
            not valid, or the slice is outside the grid.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("An outline needs a label other than the background")
    require_axis(axis)
    var plane = _plane(
        map.nx,
        map.ny,
        map.nz,
        (map.spacing_x, map.spacing_y, map.spacing_z),
        axis,
    )
    var w = plane[0]
    var h = plane[1]
    if index < 0 or index >= plane[2]:
        raise Error("The slice index is outside the volume")
    var mark = UInt8(label.value)
    # The label is 1 and the rest 0, past the edge too, so each line
    # crosses a side at its middle.
    var values = List[Float64](length=(w + 2) * (h + 2), fill=0)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var v = _voxel(axis, x, y, index)
            if map.labels[map.index(v[0], v[1], v[2])] == mark:
                values[(y + 1) * (w + 2) + (x + 1)] = 1
    return _march(values, w, h, 0.5, axis, index, plane[3], plane[4])


def slice_isolines(
    volume: ImageVolume, axis: SliceAxis, index: Int, level: Float64
) raises -> List[Outline]:
    """Return the lines where the values of a slice cross a level.

    The line crosses each side between a pixel at or past the level and a
    pixel below it, where the linear blend of their values is the level.
    A pixel past the edge of the slice is below every level, so each line
    closes through the centers of the edge pixels.

    Args:
        volume: The volume.
        axis: The axis that the slice holds constant.
        index: The slice, from 0.
        level: The level, such as an SUV or a temperature. Finite.

    Returns:
        The closed lines, as outlines: the area of a line around values
        at or past the level is positive, and around a dip below it
        negative.

    Raises:
        Error: If the axis is not valid, the slice is outside the volume,
            the level is not finite, or a value of the slice is not.
    """
    require_axis(axis)
    if not isfinite(level):
        raise Error("An isoline needs a finite level")
    var plane = _plane(
        volume.nx,
        volume.ny,
        volume.nz,
        (volume.spacing_x, volume.spacing_y, volume.spacing_z),
        axis,
    )
    var w = plane[0]
    var h = plane[1]
    if index < 0 or index >= plane[2]:
        raise Error("The slice index is outside the volume")
    var values = List[Float64](
        length=(w + 2) * (h + 2), fill=-inf[DType.float64]()
    )
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var v = _voxel(axis, x, y, index)
            var value = Float64(volume.values[volume.index(v[0], v[1], v[2])])
            if not isfinite(value):
                raise Error("An isoline needs finite values")
            values[(y + 1) * (w + 2) + (x + 1)] = value
    return _march(values, w, h, level, axis, index, plane[3], plane[4])


def draw_outlines(
    mut image: Framebuffer,
    axis: SliceAxis,
    outlines: List[Outline],
    zoom: Int,
    color: Rgba,
) raises:
    """Draw outlines on a slice image.

    A voxel's pixel center on an image zoomed `zoom` times by `zoom_image`
    is at `zoom x + (zoom - 1) / 2`. Each point of an outline goes there,
    and a line of pixels joins each point to the next.

    Args:
        image: The slice image, from `render_slice` or `zoom_image`.
        axis: The axis that the slice holds constant.
        outlines: The outlines, from `slice_outlines` with this axis.
        zoom: How many times the image is zoomed, from 1 to 64.
        color: The line color. Its opacity is ignored.

    Raises:
        Error: If the axis is not valid, or `zoom` is out of range.
    """
    require_axis(axis)
    if zoom < 1 or zoom > 64:
        raise Error("An outline is drawn at a zoom from 1 to 64")
    var scale = Float64(zoom)
    var shift = (scale - 1.0) / 2.0
    for outline in outlines:
        var n = len(outline.points)
        for p in range(n):
            var a = _slice_point(axis, outline.points[p])
            var b = _slice_point(axis, outline.points[(p + 1) % n])
            draw_line(
                image,
                Int(floor(a[0] * scale + shift + 0.5)),
                Int(floor(a[1] * scale + shift + 0.5)),
                Int(floor(b[0] * scale + shift + 0.5)),
                Int(floor(b[1] * scale + shift + 0.5)),
                color,
            )
