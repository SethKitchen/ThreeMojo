# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Resample a volume on any plane: an oblique multiplanar reformat.

A reformat is a slice on a plane that need not follow the volume's axes,
such as a plane along a vessel or square to a bone. `oblique_slice`
samples the volume at a grid of points on the plane, by trilinear
interpolation, and returns a volume of one slice. The slice keeps the
volume's window and photometric interpretation, so `render_slice` draws
it with `K_AXIS` and index 0.

A point outside the box of voxel centers takes the `outside` value, such
as -1000 for air in CT.
"""

from extensions.imaging.image_volume import ImageVolume, require_spacing
from extensions.sdf.vector import V3, cross, dot, length, v3
from std.math import isfinite, max, min
from units.si import Length64, METER

# Two directions are square when the cosine between them is below this.
comptime SQUARE_TOLERANCE = 1.0e-6
# The largest side of a reformat, in pixels.
comptime MAX_SIDE = 8192


def _unit(direction: V3, name: String) raises -> V3:
    """Return a direction made unit length, or refuse a zero direction."""
    var size = length(direction)
    if not (size > 0) or not isfinite(size):
        raise Error("The " + name + " direction of a reformat cannot be zero")
    return direction * (1.0 / size)


def oblique_slice(
    volume: ImageVolume,
    center: V3,
    right: V3,
    down: V3,
    width: Int,
    height: Int,
    spacing: Length64,
    outside: Float32,
) raises -> ImageVolume:
    """Return the volume sampled on a plane through a center point.

    Pixel `(x, y)` lies at `center + right * (x - (width - 1) / 2) * spacing
    + down * (y - (height - 1) / 2) * spacing` in patient space.

    Args:
        volume: The volume to sample.
        center: The center of the slice, in patient space, in meters.
        right: The direction of increasing x across the slice.
        down: The direction of increasing y. Square to `right`.
        width: The width in pixels, from 1 to 8192.
        height: The height in pixels, from 1 to 8192.
        spacing: The distance between two pixels.
        outside: The value of a point outside the volume.

    Returns:
        A volume of `width` by `height` by one, placed on the plane, with
        `axis_x` along `right` and `axis_y` along `down`.

    Raises:
        Error: If the center is not finite, a direction is zero, the two
            directions are not square, a size is out of range, or the
            spacing is not positive and finite.
    """
    if not isfinite(center.x + center.y + center.z):
        raise Error("A reformat needs a finite center")
    var across = _unit(right, "right")
    var below = _unit(down, "down")
    if abs(dot(across, below)) > SQUARE_TOLERANCE:
        raise Error("A reformat's right and down directions must be square")
    if width < 1 or height < 1 or width > MAX_SIDE or height > MAX_SIDE:
        raise Error("A reformat has from 1 to 8192 pixels a side")
    require_spacing(spacing)
    var step = spacing.to(METER)
    var out = ImageVolume(width, height, 1, spacing, spacing, spacing)
    out.axis_x = across
    out.axis_y = below
    out.axis_z = cross(across, below)
    out.origin = (
        center
        - across * (Float64(width - 1) / 2.0 * step)
        - below * (Float64(height - 1) / 2.0 * step)
    )
    out.window_center = volume.window_center
    out.window_width = volume.window_width
    out.photometric = volume.photometric
    var top = v3(
        Float64(volume.nx - 1), Float64(volume.ny - 1), Float64(volume.nz - 1)
    )
    var reach = 1.0e-9
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var p = out.patient_point(Float64(x), Float64(y), 0)
            var q = volume.voxel_point(p)
            var below_box = min(q.x, min(q.y, q.z))
            var past_box = max(q.x - top.x, max(q.y - top.y, q.z - top.z))
            var inside = below_box >= -reach and past_box <= reach
            var value = outside
            if inside:
                value = volume.trilinear(q.x, q.y, q.z)
            out.values[x + width * y] = value
    return out^
