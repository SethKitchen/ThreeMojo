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
The GPU kept its running color in registers and resolved once, so the two
backends did not merely round differently, they had different contracts.

**Alpha.** Compositing two translucent things needs the *destination's* alpha
as well as the source's, and a byte buffer that has already been flattened to
opaque has thrown it away. Blending 50% red over transparent blue used to give
opaque purple; the blue was invisible and should have contributed nothing.

So color lives here as linear `FloatColor` until the image is finished, and
`resolve` converts once.

**Data.** Not every pixel holds light. A normal material writes its normal
as bytes, a depth material its depth, the uv debug view its coordinates,
and a display must show those bytes as they are. They are stored decoded,
so the encode gives the bytes back -- see `render.rasterizer.data_color` --
and a flag per pixel says so, which keeps the tone mapping off them: a
curve that compresses light would make a normal lie about its own numbers.

**One flag cannot describe a mixture**, so the policy is that nothing is
mixed. A `write` replaces the pixel outright and the pixel's flag becomes
the fragment's. A `blend` mixes into what is there and the result is
light, whatever it mixed with, because a fragment that shows data is
refused a blend policy in the first place -- see
`render.rasterizer.check_triangle_state`. That leaves one reachable
mixture, a translucent lit surface over a data pixel, and calling the
result light is the honest answer: light is in it, and tone mapping is for
light. A pixel showing a normal that is half covered by smoke is not a
normal any more.

**Source-over with no coverage changes nothing at all.** A blend of alpha
zero contributes no color, so it must not contribute a flag either. It
used to: the flag was assigned before the alpha was looked at, and a fully
transparent normal material could switch the tone mapping off a lit pixel
behind it and brighten the image. `blend` now returns before it touches
anything, and the kernel skips such a fragment for the same reason.

**Premultiplied.** The stored color is the light a pixel actually contributes,
already scaled by its coverage — `(r*a, g*a, b*a, a)`. Source-over in that form
is a weighted sum with no special cases:

    out.rgb = src.rgb + dst.rgb * (1 - src.a)
    out.a   = src.a   + dst.a   * (1 - src.a)

Straight alpha needs a divide to recover the same answer, and gets it wrong
wherever alpha is zero, because a color that contributes no light has no
color to recover. `resolve` unpremultiplies at the end, because PNG stores
unassociated alpha.
"""

from render.framebuffer import Color, FloatColor, Framebuffer
from render.tonemap import (
    NO_TONE_MAPPING,
    ToneMapping,
    check_tone_mapping,
    tone_map,
)
from std.math import inf, min

# `TaskGroup` moved behind an underscore in Mojo 1.1: `std.runtime` keeps
# only `parallelism_level` and `initialize_runtime` in public view, and
# nothing public in `std` runs work on the thread pool -- `std.algorithm.map`
# is sequential. So the private module is the only way to keep the bands
# parallel, and this import is the one place the project reaches past a
# leading underscore. It pins the toolchain to 1.1: 1.0 has no `_asyncrt`
# and 1.1 has no `asyncrt`, so one source cannot serve both.
from std.runtime._asyncrt import TaskGroup


def _encode_run(
    colors: Pointer[FloatColor, ImmutAnyOrigin],
    data: Pointer[Bool, ImmutAnyOrigin],
    pixels: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
    tone_mapping: ToneMapping,
    exposure: Float32,
    clear: FloatColor,
    clear_shown: Color,
):
    """Encode the pixels in `[first, past)` from linear light to bytes.

    The body of `RenderTarget.resolve`, shared by the single-threaded path
    and each band of the parallel one so the two cannot differ. Each
    pixel is unpremultiplied, tone mapped, then encoded, in that order:
    the curve sees the straight color a display is about to show, as the
    GPU kernel applies it to the same color at the same point. A pixel
    that holds data skips the curve, as the kernel skips it.

    A pixel still holding the clear color is written as `clear_shown`,
    which `resolve` encoded once by the same three steps. Most of most
    frames is background, and three `pow` calls a pixel were the second
    largest cost of a frame; the bytes are the ones the steps would give,
    because they are the ones the steps gave.
    """
    # A run is never empty: `resolve` never makes more bands than pixels.
    for slot in range(first, past):  # pragma: no branch
        var shown: Color
        if not data[unsafe_offset=slot] and colors[unsafe_offset=slot] == clear:
            shown = clear_shown
        else:
            var curve = tone_mapping
            if data[unsafe_offset=slot]:
                curve = NO_TONE_MAPPING
            shown = tone_map(
                colors[unsafe_offset=slot].unpremultiplied(),
                curve,
                exposure,
            ).encode()
        var at = slot * Framebuffer.CHANNELS
        pixels[unsafe_offset=at] = shown.r
        pixels[unsafe_offset=at + 1] = shown.g
        pixels[unsafe_offset=at + 2] = shown.b
        pixels[unsafe_offset=at + 3] = shown.a


async def _encode_band(
    colors: Pointer[FloatColor, ImmutAnyOrigin],
    data: Pointer[Bool, ImmutAnyOrigin],
    pixels: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
    tone_mapping: ToneMapping,
    exposure: Float32,
    clear: FloatColor,
    clear_shown: Color,
):
    """`_encode_run` as a task, one per worker; see `resolve`."""
    _encode_run(
        colors,
        data,
        pixels,
        first,
        past,
        tone_mapping,
        exposure,
        clear,
        clear_shown,
    )


struct RenderTarget(Movable):
    """A width x height buffer of premultiplied linear color, plus depth."""

    var width: Int
    var height: Int
    # Premultiplied linear light, one entry per pixel.
    var colors: List[FloatColor]
    # What every pixel held before anything was drawn, premultiplied like
    # the pixels. `resolve` encodes it once and writes the answer wherever
    # a pixel still holds it.
    var clear: FloatColor
    var depth: List[Float32]
    # Whether each pixel holds data rather than light -- a normal, a depth,
    # a coordinate -- which the tone mapping must leave alone. Set by the
    # last `write` into the pixel and cleared by any `blend` that
    # contributes; a cleared pixel holds light. See the module docstring.
    var data: List[Bool]

    def __init__(out self, width: Int, height: Int, clear: Color) raises:
        """Create a target cleared to `clear`.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
            clear: The color to fill with, decoded from sRGB. Its alpha is
                kept, so clearing to something transparent gives a target that
                stays transparent where nothing is drawn.

        Raises:
            Error: If either dimension is not positive.
        """
        if width <= 0 or height <= 0:
            raise Error("Render target dimensions must be positive")
        self.width = width
        self.height = height
        self.clear = FloatColor(srgb=clear).premultiplied()
        self.colors = List[FloatColor](length=width * height, fill=self.clear)
        self.depth = List[Float32](
            length=width * height, fill=inf[DType.float32]()
        )
        self.data = List[Bool](length=width * height, fill=False)

    def _slot(self, x: Int, y: Int) raises -> Int:
        """Return the index of pixel (x, y), checking it is inside."""
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Pixel coordinate out of bounds")
        return y * self.width + x

    def depth_at(self, x: Int, y: Int) raises -> Float32:
        """Return the depth recorded at pixel (x, y)."""
        return self.depth[self._slot(x, y)]

    def color_at(self, x: Int, y: Int) raises -> FloatColor:
        """Return the premultiplied linear color at pixel (x, y)."""
        return self.colors[self._slot(x, y)]

    def is_data(self, x: Int, y: Int) raises -> Bool:
        """Return True if pixel (x, y) holds data rather than light, and
        so is not tone mapped when resolved."""
        return self.data[self._slot(x, y)]

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

    def claim_depth(mut self, x: Int, y: Int, z: Float32) raises:
        """Record `z` as this pixel's depth, testing nothing.

        The other half of a *late* depth write. A fragment that an alpha
        test can throw away must not claim the depth before it is shaded,
        or the hole it cuts hides whatever is behind it. Such a fragment
        asks `depth_passes` first and calls this once it survives, which is
        what a GPU does for a shader that can discard.

        Only safe because a band owns its rows outright: nothing else can
        write this pixel between the test and the claim. See
        `render.rasterizer.rasterize_all`.

        Args:
            x: Column.
            y: Row.
            z: The NDC depth to record.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        self.depth[self._slot(x, y)] = z

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

    def write(
        mut self, x: Int, y: Int, color: FloatColor, data: Bool = False
    ) raises:
        """Replace pixel (x, y) with `color`, given in straight alpha.

        What an opaque surface does: it is the only thing visible there, so
        nothing behind it contributes. Its own alpha is kept rather than
        forced to one, so an opaque material drawn with a partly transparent
        texture resolves to a partly transparent pixel.

        Args:
            x: Column.
            y: Row.
            color: Linear color with straight (unassociated) alpha.
            data: True if the color is data rather than light -- a normal,
                a depth, a coordinate -- which `resolve` must encode
                without tone mapping. See `render.rasterizer.data_color`.
                A write replaces the pixel, so the pixel's answer becomes
                this one.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        self.colors[slot] = color.premultiplied()
        self.data[slot] = data

    def blend(mut self, x: Int, y: Int, color: FloatColor) raises:
        """Mix `color` into pixel (x, y) with source-over compositing.

        The result is light, whatever was there before. Only light blends:
        a fragment that shows data is refused a blend policy, so the mix is
        light over something, and a mixture with light in it is light. See
        the module docstring.

        A color whose alpha is zero hides nothing and contributes nothing,
        and this returns without touching the pixel -- its color, its alpha
        and its flag alike. The identity of source-over has to be the
        identity of the whole operation, not of the arithmetic alone.

        Args:
            x: Column.
            y: Row.
            color: Linear color with straight (unassociated) alpha, where
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
        if share == 0:
            return
        self.data[slot] = False
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

    def shown(
        self,
        x: Int,
        y: Int,
        tone_mapping: ToneMapping = NO_TONE_MAPPING,
        exposure: Float32 = 1.0,
    ) raises -> Color:
        """Return what a display should show for pixel (x, y).

        `resolve` for one pixel. A read rather than a second representation:
        there is still exactly one buffer, and this is a view of it.

        Args:
            x: Column.
            y: Row.
            tone_mapping: The curve to compress the light with; see
                `resolve`.
            exposure: What the light is scaled by before the curve.

        Returns:
            The resolved eight-bit color.

        Raises:
            Error: If the coordinate is out of bounds, the curve is none of
                the seven, or the exposure is negative or not finite.
        """
        check_tone_mapping(tone_mapping, exposure)
        var slot = self._slot(x, y)
        var curve = tone_mapping
        if self.data[slot]:
            curve = NO_TONE_MAPPING
        return tone_map(
            self.colors[slot].unpremultiplied(), curve, exposure
        ).encode()

    def resolve(
        self,
        workers: Int = 1,
        tone_mapping: ToneMapping = NO_TONE_MAPPING,
        exposure: Float32 = 1.0,
    ) raises -> Framebuffer:
        """Return the finished image, encoded for a display.

        The one place linear stops: unpremultiply, tone map, encode the
        color channels through the sRGB curve, and quantize. Alpha is
        coverage rather than color and is quantized without any transfer
        function, and the curve leaves it alone too.

        Tone mapping happens here, to the composited light of each pixel,
        rather than per fragment as three.js does it: the curve sees what
        reaches the camera, as a camera does. See `render.tonemap`. A
        pixel that holds data rather than light -- see `write` -- is
        encoded without it.

        Three `pow` calls per pixel is the most expensive thing a frame does
        after rasterizing it -- at 1280x720 it is nearly three million of
        them -- and it parallelizes perfectly, so `Renderer.render` hands it
        the same worker count it rasterized with. Each band encodes its own
        run of pixels into a buffer sized up front; nothing is appended.
        The clear color is encoded once here and copied to every pixel
        that still holds it, which in most frames is most of them.

        Args:
            workers: How many threads to encode with. One encodes in place
                on the calling thread.
            tone_mapping: The curve that compresses the light into what a
                display can show, or `NO_TONE_MAPPING`, the default, to
                clamp and nothing else.
            exposure: What the light is scaled by before the curve,
                three.js's `toneMappingExposure`. Not applied without a
                curve.

        Returns:
            The image as eight-bit sRGB with unassociated alpha, which is what
            PNG stores.

        Raises:
            Error: If `workers` is less than one, the curve is none of the
                seven, the exposure is negative or not finite, or the
                framebuffer cannot be built.
        """
        if workers < 1:
            raise Error("Resolving needs at least one worker")
        check_tone_mapping(tone_mapping, exposure)
        var count = self.width * self.height
        var pixels = List[UInt8](length=count * Framebuffer.CHANNELS, fill=0)
        # The background, by the same three steps every other pixel takes.
        var clear_shown = tone_map(
            self.clear.unpremultiplied(), tone_mapping, exposure
        ).encode()
        var bands = min(workers, count)
        if bands == 1:
            _encode_run(
                self.colors.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                self.data.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                0,
                count,
                tone_mapping,
                exposure,
                self.clear,
                clear_shown,
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
                        self.data.unsafe_ptr().unsafe_origin_cast[
                            ImmutAnyOrigin
                        ](),
                        pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                        band * count // bands,
                        (band + 1) * count // bands,
                        tone_mapping,
                        exposure,
                        self.clear,
                        clear_shown,
                    )
                )
            group.wait()
        return Framebuffer(self.width, self.height, pixels^, self.depth.copy())
