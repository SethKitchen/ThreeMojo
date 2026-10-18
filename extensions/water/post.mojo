# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bloom and glare sampling, one pixel at a time.

After the water is shaded, a frame gets bloom (the bright part, blurred) and
glare (a star on each glint). The CPU frame and the GPU frame read these same
functions, so they differ only where the hardware rounds a math function
differently. Each function reads a `RadianceView`, which holds a pointer, so
the same code reads a host list or device memory.

A view holds an untracked pointer. Keep the list or the device buffer alive
and unchanged while the view is in use. Mojo ends a value at its last use, so
use it after the last view read.
"""

from math.vector3 import Vector3
from std.memory import AddressSpace

comptime _Untracked = UntrackedOrigin[mut=False]


struct RadianceView[space: AddressSpace](ImplicitlyCopyable):
    """A frame of linear RGB, read in place.

    Parameters:
        space: The address space of the array.
    """

    var texels: Pointer[Float32, _Untracked, address_space=Self.space]
    """Three floats a pixel, row-major from the top."""
    var width: Int
    """Pixels in a row."""
    var height: Int
    """Rows."""

    def __init__(
        out self,
        texels: Pointer[Float32, _Untracked, address_space=Self.space],
        width: Int,
        height: Int,
    ):
        """Read a frame.

        Args:
            texels: Three floats a pixel.
            width: Pixels in a row.
            height: Rows.
        """
        self.texels = texels
        self.width = width
        self.height = height


def highlight_texel[
    space: AddressSpace
](
    image: RadianceView[space],
    x: Int,
    y: Int,
    threshold: Float32,
    scale: Float32,
) -> Vector3:
    """Return the part of one pixel's neighborhood that is brighter than a limit.

    The pixel is the mean of its 3 by 3 neighborhood, clipped at the edges.
    Its brightest channel `l` keeps the share `(l - threshold) / l` when it is
    over the limit, and nothing when it is under.

    Args:
        image: The frame of linear RGB.
        x: Pixel column.
        y: Pixel row, top down.
        threshold: The brightness below which nothing stays.
        scale: A factor applied last, after the result is rounded.

    Returns:
        The bright part, as linear RGB.
    """
    var r = Float32(0.0)
    var g = Float32(0.0)
    var b = Float32(0.0)
    var count = Float32(0.0)
    for oy in range(-1, 2):  # pragma: no branch
        for ox in range(-1, 2):  # pragma: no branch
            var sx = x + ox
            var sy = y + oy
            if sx >= 0 and sy >= 0 and sx < image.width and sy < image.height:
                var p = (sy * image.width + sx) * 3
                r += image.texels[unsafe_offset=p]
                g += image.texels[unsafe_offset=p + 1]
                b += image.texels[unsafe_offset=p + 2]
                count += 1.0
    r /= count
    g /= count
    b /= count
    var l = max(r, max(g, b))
    var k = l - threshold
    if k < 0.0:
        k = 0.0
    # The brightest glint in this model stays under the page's 160 cap.
    k /= max(l, Float32(1e-4))
    return Vector3((r * k) * scale, (g * k) * scale, (b * k) * scale)


def blur_texel[
    space: AddressSpace
](image: RadianceView[space], x: Int, y: Int, horizontal: Bool) -> Vector3:
    """Return one pixel of a five-tap Gaussian blur along one axis.

    The taps are at offsets 0, 1, -1, 3 and -3, and the image edge repeats.

    Args:
        image: The frame of linear RGB.
        x: Pixel column.
        y: Pixel row, top down.
        horizontal: True blurs along a row, false along a column.

    Returns:
        The blurred pixel.
    """
    var r = Float32(0.0)
    var g = Float32(0.0)
    var b = Float32(0.0)
    for tap in range(5):  # pragma: no branch
        var sx = x
        var sy = y
        if horizontal:
            sx = x + _tap_offset(tap)
        else:
            sy = y + _tap_offset(tap)
        if sx < 0:
            sx = 0
        if sy < 0:
            sy = 0
        if sx >= image.width:
            sx = image.width - 1
        if sy >= image.height:
            sy = image.height - 1
        var p = (sy * image.width + sx) * 3
        var weight = _tap_weight(tap)
        r += image.texels[unsafe_offset=p] * weight
        g += image.texels[unsafe_offset=p + 1] * weight
        b += image.texels[unsafe_offset=p + 2] * weight
    return Vector3(r, g, b)


def _tap_offset(tap: Int) -> Int:
    if tap == 0:
        return 0
    if tap == 1:
        return 1
    if tap == 2:
        return -1
    if tap == 3:
        return 3
    return -3


def _tap_weight(tap: Int) -> Float32:
    if tap == 0:
        return 0.2270270270
    if tap == 1 or tap == 2:
        return 0.3162162162
    return 0.0702702703
