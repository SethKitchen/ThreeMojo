# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fuse the values of a second volume over a slice, as PET over CT.

`overlay_values` blends a color over each pixel of a slice image whose
value in a second volume is at least `low`. The second volume must be on
the grid of the slice: bring a PET onto a CT with `resample_onto` first.

The color runs on the hot scale from `low` to `high`: `t = (v - low) /
(high - low)`, held from 0 to 1, gives

    red = 3 t, green = 3 t - 1, blue = 3 t - 2

each held from 0 to 1: dark, red, yellow and white. The color covers the
pixel with the weight `opacity * min(1, 3 t)`, so a value just past
`low` fades in instead of drawing a dark rim. A value below `low`
leaves the pixel as it is.
"""

from extensions.imaging.ids import (
    I_AXIS,
    J_AXIS,
    SliceAxis,
    require_axis,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.transfer import Rgba
from render.framebuffer import Framebuffer
from std.math import isfinite, max, min


def hot_color(t: Float64) -> Rgba:
    """Return the color of the hot scale at a share of its range.

    Args:
        t: The share, held from 0 to 1.

    Returns:
        Dark at 0, red at 1/3, yellow at 2/3 and white at 1. Opaque.
    """
    var s = min(1.0, max(0.0, t))
    return Rgba(
        Float32(min(1.0, 3.0 * s)),
        Float32(min(1.0, max(0.0, 3.0 * s - 1.0))),
        Float32(min(1.0, max(0.0, 3.0 * s - 2.0))),
        1,
    )


def overlay_values(
    mut image: Framebuffer,
    volume: ImageVolume,
    axis: SliceAxis,
    index: Int,
    low: Float64,
    high: Float64,
    opacity: Float64,
    zoom: Int,
) raises:
    """Blend the values of a volume's slice over a slice image.

    Args:
        image: The slice image, from `render_slice` or `zoom_image`.
        volume: The volume of values, on the grid of the slice, such as a
            PET volume after `resample_onto`.
        axis: The axis that the slice holds constant.
        index: The slice, from 0.
        low: The least value that shows.
        high: The value that shows white. Above `low`.
        opacity: The largest weight of the color, from 0 to 1.
        zoom: How many times the image is zoomed, from 1 to 64.

    Raises:
        Error: If the axis is not valid, the slice is outside the volume,
            the range is not finite or does not rise, the opacity or the
            zoom is out of range, or the image is not the slice's size
            times the zoom.
    """
    require_axis(axis)
    var width = volume.nx
    var height = volume.ny
    var depth = volume.nz
    if axis == J_AXIS:
        height = volume.nz
        depth = volume.ny
    elif axis == I_AXIS:
        width = volume.ny
        height = volume.nz
        depth = volume.nx
    if index < 0 or index >= depth:
        raise Error("The slice index is outside the volume")
    if not isfinite(low) or not isfinite(high) or not (high > low):
        raise Error("An overlay range must be finite and rise")
    if not (opacity >= 0) or not (opacity <= 1):
        raise Error("An overlay opacity is from 0 to 1")
    if zoom < 1 or zoom > 64:
        raise Error("An overlay is drawn at a zoom from 1 to 64")
    if image.width != width * zoom or image.height != height * zoom:
        raise Error("The image is not the slice's size times the zoom")
    for y in range(image.height):  # pragma: no branch
        for x in range(image.width):  # pragma: no branch
            var sx = x // zoom
            var sy = y // zoom
            var i = sx
            var j = sy
            var k = index
            if axis == J_AXIS:
                j = index
                k = sy
            elif axis == I_AXIS:
                i = index
                j = sx
                k = sy
            var v = Float64(volume.values[volume.index(i, j, k)])
            if not (v >= low):
                continue
            var t = min(1.0, (v - low) / (high - low))
            var color = hot_color(t)
            var weight = opacity * min(1.0, 3.0 * t)
            var at = (y * image.width + x) * 4
            for c in range(3):  # pragma: no branch
                var part = color.r
                if c == 1:
                    part = color.g
                elif c == 2:
                    part = color.b
                var base = Float64(image.pixels[at + c]) / 255.0
                var mixed = (1.0 - weight) * base + weight * Float64(part)
                image.pixels[at + c] = UInt8(
                    Int(min(255.0, max(0.0, mixed * 255.0 + 0.5)))
                )
