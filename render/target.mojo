# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a rasterizer draws into: linear light, kept at full precision.

A `Framebuffer` holds eight-bit sRGB — what a display should show, what a PNG
should store. That is the right thing to *finish* with and the wrong thing to
*accumulate* in, for two separate reasons, and both were live bugs.

**Rounding.** Blending used to read the byte back, decode it, mix, and encode
again, once per translucent layer. Each round trip loses a little, and the loss
compounds: a hundred layers of alpha 0.0001 over black should come to about
0.00995 of the light, which displays as byte 25 — and rounding after every
layer gives 0, because each contribution on its own rounds back down to black.
The GPU kept its running colour in registers and resolved once, so the two
backends did not merely round differently, they had different contracts.

**Alpha.** Compositing two translucent things needs the *destination's* alpha
as well as the source's, and a byte buffer that has already been flattened to
opaque has thrown it away. Blending 50% red over transparent blue used to give
opaque purple; the blue was invisible and should have contributed nothing.

So colour lives here as linear `FloatColor` until the image is finished, and
`resolve` converts once.

**Premultiplied.** The stored colour is the light a pixel actually contributes,
already scaled by its coverage — `(r*a, g*a, b*a, a)`. Source-over in that form
is a weighted sum with no special cases:

    out.rgb = src.rgb + dst.rgb * (1 - src.a)
    out.a   = src.a   + dst.a   * (1 - src.a)

Straight alpha needs a divide to recover the same answer, and gets it wrong
wherever alpha is zero, because a colour that contributes no light has no
colour to recover. `resolve` unpremultiplies at the end, because PNG stores
unassociated alpha.
"""

from render.framebuffer import Color, FloatColor, Framebuffer
from std.math import inf, min
from std.runtime.asyncrt import TaskGroup


def _encode_run(
    colors: Pointer[FloatColor, ImmutAnyOrigin],
    pixels: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Encode the pixels in `[first, past)` from linear light to bytes.

    The body of `RenderTarget.resolve`, shared by the single-threaded path
    and each band of the parallel one so the two cannot differ.
    """
    # A run is never empty: `resolve` never makes more bands than pixels.
    for slot in range(first, past):  # pragma: no branch
        var shown = colors[unsafe_offset=slot].unpremultiplied().encode()
        var at = slot * Framebuffer.CHANNELS
        pixels[unsafe_offset=at] = shown.r
        pixels[unsafe_offset=at + 1] = shown.g
        pixels[unsafe_offset=at + 2] = shown.b
        pixels[unsafe_offset=at + 3] = shown.a


async def _encode_band(
    colors: Pointer[FloatColor, ImmutAnyOrigin],
    pixels: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_encode_run` as a task, one per worker; see `resolve`."""
    _encode_run(colors, pixels, first, past)


struct RenderTarget(Movable):
    """A width x height buffer of premultiplied linear colour, plus depth."""

    var width: Int
    var height: Int
    # Premultiplied linear light, one entry per pixel.
    var colors: List[FloatColor]
    var depth: List[Float32]

    def __init__(out self, width: Int, height: Int, clear: Color) raises:
        """Create a target cleared to `clear`.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
            clear: The colour to fill with, decoded from sRGB. Its alpha is
                kept, so clearing to something transparent gives a target that
                stays transparent where nothing is drawn.

        Raises:
            Error: If either dimension is not positive.
        """
        if width <= 0 or height <= 0:
            raise Error("Render target dimensions must be positive")
        self.width = width
        self.height = height
        self.colors = List[FloatColor](
            length=width * height, fill=FloatColor(srgb=clear).premultiplied()
        )
        self.depth = List[Float32](
            length=width * height, fill=inf[DType.float32]()
        )

    def _slot(self, x: Int, y: Int) raises -> Int:
        """Return the index of pixel (x, y), checking it is inside."""
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Pixel coordinate out of bounds")
        return y * self.width + x

    def depth_at(self, x: Int, y: Int) raises -> Float32:
        """Return the depth recorded at pixel (x, y)."""
        return self.depth[self._slot(x, y)]

    def color_at(self, x: Int, y: Int) raises -> FloatColor:
        """Return the premultiplied linear colour at pixel (x, y)."""
        return self.colors[self._slot(x, y)]

    def test_depth(mut self, x: Int, y: Int, z: Float32) raises -> Bool:
        """Return True if `z` is nearer than what is stored, and claim it.

        The test and the write are one operation because separating them
        invites the caller to do one without the other, which is how a depth
        buffer quietly stops working. What a translucent surface wants is
        `depth_passes`, which does not claim.
        """
        var slot = self._slot(x, y)
        if z >= self.depth[slot]:
            return False
        self.depth[slot] = z
        return True

    def depth_passes(self, x: Int, y: Int, z: Float32) raises -> Bool:
        """Return True if `z` is nearer than what is stored, claiming nothing.

        For surfaces that must be *hidden* by what is in front of them without
        *hiding* what is behind them: two translucent panes one behind the
        other both contribute, so neither may take ownership of the depth.

        Args:
            x: Column.
            y: Row.
            z: The NDC depth to test.

        Returns:
            True if the fragment is in front of what is recorded.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        return z < self.depth[self._slot(x, y)]

    def write(mut self, x: Int, y: Int, color: FloatColor) raises:
        """Replace pixel (x, y) with `color`, given in straight alpha.

        What an opaque surface does: it is the only thing visible there, so
        nothing behind it contributes. Its own alpha is kept rather than
        forced to one, so an opaque material drawn with a partly transparent
        texture resolves to a partly transparent pixel.

        Args:
            x: Column.
            y: Row.
            color: Linear colour with straight (unassociated) alpha.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        self.colors[slot] = color.premultiplied()

    def blend(mut self, x: Int, y: Int, color: FloatColor) raises:
        """Mix `color` into pixel (x, y) with source-over compositing.

        Args:
            x: Column.
            y: Row.
            color: Linear colour with straight (unassociated) alpha, where
                alpha is how much of what is behind it is hidden.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        var share = color.a
        if share > 1:
            share = 1
        if share < 0:
            share = 0
        var source = FloatColor(
            color.r, color.g, color.b, share
        ).premultiplied()
        var behind = self.colors[slot]
        var keep = 1 - share
        self.colors[slot] = FloatColor(
            source.r + behind.r * keep,
            source.g + behind.g * keep,
            source.b + behind.b * keep,
            source.a + behind.a * keep,
        )

    def shown(self, x: Int, y: Int) raises -> Color:
        """Return what a display should show for pixel (x, y).

        `resolve` for one pixel. A read rather than a second representation:
        there is still exactly one buffer, and this is a view of it.

        Args:
            x: Column.
            y: Row.

        Returns:
            The resolved eight-bit colour.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        return self.colors[self._slot(x, y)].unpremultiplied().encode()

    def resolve(self, workers: Int = 1) raises -> Framebuffer:
        """Return the finished image, encoded for a display.

        The one place linear stops: unpremultiply, encode the colour channels
        through the sRGB curve, and quantize. Alpha is coverage rather than
        colour and is quantized without any transfer function.

        Three `pow` calls per pixel is the most expensive thing a frame does
        after rasterizing it -- at 1280x720 it is nearly three million of
        them -- and it parallelizes perfectly, so `Renderer.render` hands it
        the same worker count it rasterized with. Each band encodes its own
        run of pixels into a buffer sized up front; nothing is appended.

        Args:
            workers: How many threads to encode with. One encodes in place
                on the calling thread.

        Returns:
            The image as eight-bit sRGB with unassociated alpha, which is what
            PNG stores.

        Raises:
            Error: If `workers` is less than one, or the framebuffer cannot
                be built.
        """
        if workers < 1:
            raise Error("Resolving needs at least one worker")
        var count = self.width * self.height
        var pixels = List[UInt8](length=count * Framebuffer.CHANNELS, fill=0)
        var bands = min(workers, count)
        if bands == 1:
            _encode_run(
                self.colors.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                0,
                count,
            )
        else:
            var group = TaskGroup()
            # At least two bands on this branch, so never zero.
            for band in range(bands):  # pragma: no branch
                group.create_task(
                    _encode_band(
                        self.colors.unsafe_ptr().unsafe_origin_cast[
                            ImmutAnyOrigin
                        ](),
                        pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                        band * count // bands,
                        (band + 1) * count // bands,
                    )
                )
            group.wait()
        return Framebuffer(self.width, self.height, pixels^, self.depth.copy())
