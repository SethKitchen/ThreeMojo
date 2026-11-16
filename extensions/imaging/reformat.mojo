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

`slab_projection` samples a thick slab instead: several planes, evenly
spaced along the normal `right x down` across the slab's thickness. Each
pixel keeps the largest, the least or the mean of its samples. A slab of
maximum intensity shows vessels with contrast, and a slab of minimum
intensity shows airways.
"""

from extensions.imaging.ids import (
    SLAB_MAXIMUM,
    SLAB_MINIMUM,
    SlabMode,
    require_slab_mode,
)
from extensions.imaging.image_volume import ImageVolume, require_spacing
from extensions.sdf.vector import V3, cross, dot, length, v3
from std.math import isfinite, max, min
from units.si import Length64, METER

# Two directions are square when the cosine between them is below this.
comptime SQUARE_TOLERANCE = 1.0e-6
# The largest side of a reformat, in pixels.
comptime MAX_SIDE = 8192
# The most planes in a slab.
comptime MAX_SLAB_SAMPLES = 256


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
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var p = out.patient_point(Float64(x), Float64(y), 0)
            out.values[x + width * y] = sample_point(volume, p, outside)
    return out^


def sample_point(volume: ImageVolume, p: V3, outside: Float32) -> Float32:
    """Return the trilinear value of a volume at a point in patient space.

    Args:
        volume: The volume.
        p: The point, in meters.
        outside: The value of a point outside the box of voxel centers.

    Returns:
        The interpolated value, or `outside`.
    """
    var q = volume.voxel_point(p)
    var reach = 1.0e-9
    var below_box = min(q.x, min(q.y, q.z))
    var past_box = max(
        q.x - Float64(volume.nx - 1),
        max(q.y - Float64(volume.ny - 1), q.z - Float64(volume.nz - 1)),
    )
    if below_box >= -reach and past_box <= reach:
        return volume.trilinear(q.x, q.y, q.z)
    return outside


def slab_projection(
    volume: ImageVolume,
    center: V3,
    right: V3,
    down: V3,
    width: Int,
    height: Int,
    spacing: Length64,
    thickness: Length64,
    samples: Int,
    mode: SlabMode,
    outside: Float32,
) raises -> ImageVolume:
    """Return a thick slab through a center point, projected on its plane.

    Plane `k` of the slab lies `(k + 0.5) / samples * thickness -
    thickness / 2` along the normal `right x down`, so the planes are
    evenly spaced and centered on the slab. A point outside the volume
    takes the `outside` value, and it counts in the projection.

    Args:
        volume: The volume to sample.
        center: The center of the slab, in patient space, in meters.
        right: The direction of increasing x across the slab.
        down: The direction of increasing y. Square to `right`.
        width: The width in pixels, from 1 to 8192.
        height: The height in pixels, from 1 to 8192.
        spacing: The distance between two pixels.
        thickness: The thickness of the slab. Positive and finite.
        samples: The planes across the thickness, from 1 to 256.
        mode: The largest, the least or the mean of the samples.
        outside: The value of a point outside the volume.

    Returns:
        A volume of one slice on the center plane, as `oblique_slice`
        gives.

    Raises:
        Error: If the mode is not valid, the thickness is not positive and
            finite, the samples are out of range, or `oblique_slice`
            refuses the plane.
    """
    require_slab_mode(mode)
    var depth = thickness.to(METER)
    if not (depth > 0) or not isfinite(depth):
        raise Error("A slab thickness must be positive and finite")
    if samples < 1 or samples > MAX_SLAB_SAMPLES:
        raise Error("A slab has from 1 to 256 planes")
    var normal = cross(_unit(right, "right"), _unit(down, "down"))
    var first = 0.5 / Float64(samples) * depth - depth / 2
    var out = oblique_slice(
        volume,
        center + normal * first,
        right,
        down,
        width,
        height,
        spacing,
        outside,
    )
    for k in range(1, samples):
        var offset = (Float64(k) + 0.5) / Float64(samples) * depth - depth / 2
        var plane = oblique_slice(
            volume,
            center + normal * offset,
            right,
            down,
            width,
            height,
            spacing,
            outside,
        )
        for index in range(len(plane.values)):  # pragma: no branch
            var value = plane.values[index]
            if mode == SLAB_MAXIMUM:
                out.values[index] = max(out.values[index], value)
            elif mode == SLAB_MINIMUM:
                out.values[index] = min(out.values[index], value)
            else:
                out.values[index] += value
    if mode != SLAB_MAXIMUM and mode != SLAB_MINIMUM:
        var share = Float32(1.0 / Float64(samples))
        for index in range(len(out.values)):  # pragma: no branch
            out.values[index] *= share
    # The first plane placed the slice. Move it back to the center plane.
    out.origin = out.origin - normal * first
    return out^
