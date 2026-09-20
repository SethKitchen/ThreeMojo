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

**The average is taken on the scene's own light, before anything is
converted for a display.** `Renderer.render` draws the large frame into a
`RenderTarget`, which holds premultiplied linear light at full precision,
averages the blocks *there* -- `RenderTarget.downsampled` -- and resolves
the small target once. Tone mapping and the sRGB encode happen after the
average, to the average, and to nothing else.

The order matters more than a rounding. Encoding first clamps every
sample to what a display can show and bends it through the tone curve, and
the mean of the curve is not the curve of the mean. Four subsamples
holding linear 4, 0, 0, 0 -- one bright emissive sample on an edge --
average to a radiance of 1. Resolve them to bytes first and the bright one
saturates to 255, which decodes to 1, so the average is a quarter of what
it should be: byte 137 with no curve where the honest answer is 255, and
123 against 188 under Reinhard. That is not rounding; it is the
information being thrown away before the average could use it.

**The depth is the nearest of the block**, so a picture read back for its
depth keeps its nearest surface, as a resolved multisample depth does.

**A size given in pixels is not a size in the scene.** A point's
`PointsMaterial` size and a line's one-pixel thickness are measured in
the pixels of the *finished* image, so drawing the frame larger has to
make them larger to match, or anti-aliasing would shrink them. The
renderer carries a `render_scale` for exactly that; see
`renderers.renderer.Renderer.render_scale`, `render.pointrule` and
`render.linerule`.

## `downsample` resizes an image, and that is a different job

`downsample` below takes a `Framebuffer` -- bytes -- and is what a caller
resizing a *finished picture* wants: it decodes, averages premultiplied
and encodes once, so that an edge is not darkened by averaging sRGB
directly (see `render.srgb`). It is also what a caller driving the GPU has
to use today, because `GpuRenderer` hands back a resolved image rather
than the linear target behind it, and averaging those bytes is the best
that can be done with them.

That path is display-referred, with the loss described above, and it is
named here rather than left to be discovered. Giving the GPU the same
resolve means keeping its linear target long enough to average it, which
is the same boundary the cube camera runs into: `Renderer.render_cube`
still captures its six faces through byte-oriented `Framebuffer` images,
and supersampling them does not give back range that was already gone.
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
