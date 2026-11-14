# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Straighten a curved structure along a path: a curved planar reformat.

A vessel, an airway or a spine bends through the volume, so no plane
holds all of it. `curved_reformat` follows a path of points in patient
space, such as a centerline, and samples the volume on the surface that
the path sweeps along a lateral direction. The result is one image of
the whole structure, straightened: column `x` lies at the arc length
`x * spacing` along the path, and row `y` lies across it.

At each point of the path, the lateral direction is `up` with the part
along the path's tangent taken away. Row 0 is the farthest along it, so
`up` points up in the image. The tangent changes at each corner of the
path, and so does the lateral direction. A path of many short segments
gives a smooth image.

The result keeps the volume's window and photometric interpretation, so
`render_slice` draws it with `K_AXIS` and index 0. It is not a plane in
patient space: its origin is zero and its axes are those of the grid.
"""

from extensions.imaging.image_volume import ImageVolume, require_spacing
from extensions.imaging.reformat import sample_point
from extensions.sdf.vector import V3, dot, length
from std.math import floor, isfinite
from units.si import Length64, METER

# The most columns, and the most rows on each side of the path.
comptime MAX_COLUMNS = 8192
comptime MAX_HALF_HEIGHT = 4096
# An up direction with less than this part square to a segment is along it.
comptime ALONG = 1.0e-6


def curved_reformat(
    volume: ImageVolume,
    path: List[V3],
    up: V3,
    half_height: Int,
    spacing: Length64,
    outside: Float32,
) raises -> ImageVolume:
    """Return the volume sampled on the surface that a path sweeps.

    Args:
        volume: The volume to sample.
        path: Two or more points in patient space, in meters. Two points
            in a row must differ.
        up: The lateral direction. Not along any segment of the path.
        half_height: The rows on each side of the path, from 0 to 4096.
        spacing: The distance between two pixels, along and across.
        outside: The value of a point outside the volume.

    Returns:
        A volume of one slice, with one column for each `spacing` of the
        path's length and `2 * half_height + 1` rows. The path runs along
        the middle row.

    Raises:
        Error: If the path has fewer than two points, a point is not
            finite, two points in a row are one, `up` is zero or along a
            segment, a size is out of range, or the spacing is not
            positive and finite.
    """
    if len(path) < 2:
        raise Error("A curved reformat needs a path of two or more points")
    for p in path:  # pragma: no branch
        if not isfinite(p.x + p.y + p.z):
            raise Error("A curved reformat needs finite points")
    if half_height < 0 or half_height > MAX_HALF_HEIGHT:
        raise Error("A curved reformat has from 0 to 4096 rows on each side")
    require_spacing(spacing)
    var step = spacing.to(METER)
    var size = length(up)
    if not (size > 0) or not isfinite(size):
        raise Error("The up direction of a curved reformat cannot be zero")
    var lift = up * (1.0 / size)
    # The tangent, lateral direction and start of each segment.
    var tangents = List[V3]()
    var sides = List[V3]()
    var starts = List[Float64]()
    var total = 0.0
    for k in range(len(path) - 1):  # pragma: no branch
        var d = path[k + 1] - path[k]
        var piece = length(d)
        if not (piece > 0):
            raise Error("Two points in a row of a curved reformat are one")
        var t = d * (1.0 / piece)
        var side = lift - t * dot(lift, t)
        var across = length(side)
        if across < ALONG:
            raise Error("The up direction runs along a segment of the path")
        tangents.append(t)
        sides.append(side * (1.0 / across))
        starts.append(total)
        total += piece
    var columns = Int(floor(total / step + 1e-9)) + 1
    if columns > MAX_COLUMNS:
        raise Error("A curved reformat has at most 8192 columns")
    var rows = 2 * half_height + 1
    var out = ImageVolume(columns, rows, 1, spacing, spacing, spacing)
    out.window_center = volume.window_center
    out.window_width = volume.window_width
    out.photometric = volume.photometric
    var segment = 0
    for x in range(columns):  # pragma: no branch
        var s = Float64(x) * step
        while segment + 1 < len(starts) and s >= starts[segment + 1]:
            segment += 1
        var center = path[segment] + tangents[segment] * (s - starts[segment])
        for y in range(rows):  # pragma: no branch
            var offset = Float64(half_height - y) * step
            var p = center + sides[segment] * offset
            out.values[x + columns * y] = sample_point(volume, p, outside)
    return out^
