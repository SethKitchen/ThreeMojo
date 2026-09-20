# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Anti-aliasing by supersampling, three.js's `WebGLRenderer` `antialias`.

An edge drawn by a rule that says a pixel is in or out is a staircase, and
the staircase crawls as the edge moves. three.js asks the browser for a
multisampled canvas, which keeps several coverage samples per pixel and
resolves them into one. This project's coverage is decided by
`render.fillrule`, one sample per pixel, on two backends that agree to the
bit, and a multisampled fill rule would be a second rule for both to agree
on. Supersampling is the same answer with no new rule: the frame is drawn
at twice the size, each way, and every output pixel is the average of the
four it covers. Four samples a pixel is what a browser gives three.js by
default.

**The average is taken in linear light.** The supersampled frame is
resolved to bytes first, as every frame is, and `downsample` decodes them,
averages premultiplied, and encodes the result once more. Averaging bytes
would darken every edge; see `render.srgb`. Going through bytes at all
costs a rounding, and buys the two backends one path: a GPU frame comes
back as bytes, and the same function makes the same image of it.

**The depth is the nearest of the four**, so a picture read back for its
depth keeps its nearest surface, as a resolved multisample depth does.
"""

from render.framebuffer import Color, FloatColor, Framebuffer

# How many samples across and down each output pixel is drawn with when a
# renderer is antialiased: two, for four samples a pixel.
comptime SUPERSAMPLE = 2


def downsample(image: Framebuffer, factor: Int) raises -> Framebuffer:
    """Return `image` shrunk by `factor` each way, every output pixel the
    average of the `factor` by `factor` block it covers.

    Args:
        image: The supersampled image, its width and height multiples of
            `factor`.
        factor: How many pixels across and down become one. One returns
            a copy.

    Returns:
        The image, `factor` times smaller each way, with the block's
        nearest depth.

    Raises:
        Error: If the factor is less than one or does not divide both
            dimensions.
    """
    if factor < 1:
        raise Error("A downsample factor is at least one")
    if image.width % factor != 0 or image.height % factor != 0:
        raise Error("A downsample factor must divide the image's size")
    var width = image.width // factor
    var height = image.height // factor
    var pixels = List[UInt8]()
    pixels.reserve(width * height * Framebuffer.CHANNELS)
    var depth = List[Float32]()
    depth.reserve(width * height)
    var share = 1 / Float32(factor * factor)
    # Both dimensions are positive, so neither loop runs zero times.
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var total = FloatColor(0.0, 0.0, 0.0, 0.0)
            var nearest = image.depth_at(x * factor, y * factor)
            for row in range(factor):  # pragma: no branch
                for column in range(factor):  # pragma: no branch
                    var sx = x * factor + column
                    var sy = y * factor + row
                    var sampled = FloatColor(
                        srgb=image.get_pixel(sx, sy)
                    ).premultiplied()
                    total = FloatColor(
                        total.r + sampled.r,
                        total.g + sampled.g,
                        total.b + sampled.b,
                        total.a + sampled.a,
                    )
                    var z = image.depth_at(sx, sy)
                    if z < nearest:
                        nearest = z
            var shown = (
                FloatColor(
                    total.r * share,
                    total.g * share,
                    total.b * share,
                    total.a * share,
                )
                .unpremultiplied()
                .encode()
            )
            pixels.append(shown.r)
            pixels.append(shown.g)
            pixels.append(shown.b)
            pixels.append(shown.a)
            depth.append(nearest)
    return Framebuffer(width, height, pixels^, depth^)
