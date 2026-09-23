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

from render.blend import NORMAL_MODE, Rgba, blend_pixel
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rect import Rect
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    Alpha,
    Filter,
    Texture,
    Wrap,
    depth_texture_of_buffer,
    texture_of,
)
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
    # The pixels that can be drawn: three.js's scissor, with the test on.
    # The whole target unless `set_scissor` narrows it. Every test and
    # every write asks it, so a fragment outside is neither tested nor
    # written, as a GPU's scissor test discards it before the depth test.
    var scissor: Rect

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
        self.scissor = Rect.whole(width, height)

    def set_scissor(mut self, rect: Rect) raises:
        """Draw only inside `rect` from now on, three.js's `setScissor`
        with `setScissorTest(true)`.

        The corner is measured from the bottom left, as three.js's is; see
        `render.rect`. Pass `Rect.whole(width, height)` to draw everywhere
        again.

        Args:
            rect: The pixels that can be drawn. It must lie wholly inside
                the target.

        Raises:
            Error: If the rectangle is empty or reaches outside the target.
        """
        if not rect.fits(self.width, self.height):
            raise Error("A scissor must lie inside the target")
        self.scissor = rect

    def clear_inside(mut self, rect: Rect, clear: Color) raises:
        """Reset every pixel inside `rect` to `clear`, its depth to the
        far distance and its flag to light, leaving the rest alone.

        What clearing under a scissor does on a GPU, and what lets two
        viewports share one target: each clears its own rectangle and
        draws into it, and neither touches the other's. `Renderer.render_into`
        calls this before it draws.

        Args:
            rect: The pixels to reset. It must lie wholly inside the target.
            clear: The color to fill with, decoded from sRGB, alpha kept.

        Raises:
            Error: If the rectangle is empty or reaches outside the target.
        """
        if not rect.fits(self.width, self.height):
            raise Error("A clear must lie inside the target")
        self.clear = FloatColor(srgb=clear).premultiplied()
        var top = rect.top(self.height)
        for y in range(top, top + rect.height):  # pragma: no branch
            for x in range(rect.x, rect.x + rect.width):  # pragma: no branch
                var slot = y * self.width + x
                self.colors[slot] = self.clear
                self.depth[slot] = inf[DType.float32]()
                self.data[slot] = False

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
        if not self.scissor.contains_pixel(x, y, self.height):
            return False
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
        var slot = self._slot(x, y)
        if not self.scissor.contains_pixel(x, y, self.height):
            return
        self.depth[slot] = z

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
        var slot = self._slot(x, y)
        if not self.scissor.contains_pixel(x, y, self.height):
            return False
        return z < self.depth[slot]

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
        if not self.scissor.contains_pixel(x, y, self.height):
            return
        self.colors[slot] = color.premultiplied()
        self.data[slot] = data

    def blend(
        mut self, x: Int, y: Int, color: FloatColor, mode: Int = NORMAL_MODE
    ) raises:
        """Mix `color` into pixel (x, y) by a blending mode.

        The result is light, whatever was there before. Only light blends:
        a fragment that shows data is refused a blend policy, so the mix is
        light over something, and a mixture with light in it is light. See
        the module docstring.

        Under the normal mode, source-over, a color whose alpha is zero
        hides nothing and contributes nothing, and this returns without
        touching the pixel -- its color, its alpha and its flag alike. The
        identity of source-over has to be the identity of the whole
        operation, not of the arithmetic alone. The other modes act at any
        alpha, as WebGL's do: a subtractive fragment darkens even where it
        is clear.

        Args:
            x: Column.
            y: Row.
            color: Linear color with straight (unassociated) alpha, where
                alpha is how much of what is behind it is hidden.
            mode: The blending mode's value, `render.blend`'s numbering.
                Source-over when left out.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        if not self.scissor.contains_pixel(x, y, self.height):
            return
        if mode == NORMAL_MODE and not color.a > 0:
            return
        self.data[slot] = False
        var behind = self.colors[slot]
        var out = blend_pixel(
            Rgba(behind.r, behind.g, behind.b, behind.a),
            Rgba(color.r, color.g, color.b, color.a),
            mode,
        )
        self.colors[slot] = FloatColor(out[0], out[1], out[2], out[3])

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

    def downsampled(self, factor: Int) raises -> Self:
        """Return this target shrunk by `factor` each way, every pixel of
        it the average of the `factor` by `factor` block it covers, still
        in linear light.

        **Where supersampling is resolved, and it has to be here.** The
        samples a frame is drawn with are scene radiance, and radiance is
        what an output pixel is the average of. Resolving each sample to
        bytes first and averaging those averages the *tone curve of* the
        samples instead, which is a different number: four samples of 4, 0,
        0, 0 -- one bright emissive sample on an edge -- average to a
        radiance of 1, and averaging their encoded bytes gives 137 with no
        curve, where the honest answer is 255. Clamping alone accounts for
        most of it; a curve accounts for the rest. So the average is taken
        here, on the light, and `resolve` still converts exactly once,
        afterward, on a target this size. See `render.antialias`.

        The colors are already premultiplied, which is what makes the
        average a plain sum: a sample covering nothing contributes nothing
        and drags no color in behind it.

        **The depth is the nearest of the block**, as a resolved
        multisample depth is, so a picture read back for its depth keeps
        its nearest surface.

        **A pixel is data only if every sample in it is.** A block holding
        a normal beside lit smoke is not a normal any more, and the module
        docstring's rule applies to it: what comes out is light, and light
        is what a tone curve is for. A block that is data throughout stays
        data, so a normal or depth view antialiases without being tone
        mapped.

        Args:
            factor: How many pixels across and down become one. One
                returns a copy.

        Returns:
            The smaller target, its clear color and scissor carried over,
            the scissor widened to the whole of it.

        Raises:
            Error: If the factor is less than one or does not divide both
                dimensions.
        """
        if factor < 1:
            raise Error("A downsample factor is at least one")
        if self.width % factor != 0 or self.height % factor != 0:
            raise Error("A downsample factor must divide the target's size")
        var width = self.width // factor
        var height = self.height // factor
        var count = width * height
        var colors = List[FloatColor](
            length=count, fill=FloatColor(0.0, 0.0, 0.0, 0.0)
        )
        var depths = List[Float32](length=count, fill=inf[DType.float32]())
        # Counted rather than flagged: a `Bool` raised in a loop and read
        # after it is the shape that hangs codegen; see
        # `docs/wiki/The-Mojo-compiler-hang.md`.
        var counts = List[Int](length=count, fill=0)
        # **Walked flat, over the source pixels, and not as four nested
        # loops over the blocks.** The nested spelling is the one this
        # reads like and the one `render.antialias.downsample` uses, and
        # it sends *this* function into the same codegen hang: a twenty
        # line program that called it stopped building, where the flat
        # walk compiles in a second. The arithmetic is the same either
        # way -- each source pixel belongs to exactly one block, so
        # adding it to that block's running total visits every sample
        # once, in a different order.
        # Both dimensions are positive, so this never runs zero times.
        for source in range(self.width * self.height):  # pragma: no branch
            var slot = (
                source // self.width // factor
            ) * width + source % self.width // factor
            var sampled = self.colors[source]
            var running = colors[slot]
            colors[slot] = FloatColor(
                running.r + sampled.r,
                running.g + sampled.g,
                running.b + sampled.b,
                running.a + sampled.a,
            )
            var z = self.depth[source]
            if z < depths[slot]:
                depths[slot] = z
            if self.data[source]:
                counts[slot] += 1
        # The average, taken once per output pixel rather than per sample,
        # so the sum is exact before anything divides it.
        var share = 1 / Float32(factor * factor)
        var flags = List[Bool](length=count, fill=False)
        var samples = factor * factor
        for slot in range(count):  # pragma: no branch
            var total = colors[slot]
            colors[slot] = FloatColor(
                total.r * share,
                total.g * share,
                total.b * share,
                total.a * share,
            )
            flags[slot] = counts[slot] == samples
        var small = RenderTarget(width, height, Color(0, 0, 0, 0))
        small.clear = self.clear
        small.colors = colors^
        small.depth = depths^
        small.data = flags^
        return small^

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

    def texture(
        self,
        wrap: Wrap = CLAMP,
        filter: Filter = BILINEAR,
        mipmapped: Bool = True,
        alpha: Alpha = COVERAGE,
        workers: Int = 1,
        tone_mapping: ToneMapping = NO_TONE_MAPPING,
        exposure: Float32 = 1.0,
    ) raises -> Texture:
        """Return what this target holds as a texture, so a later draw can
        sample it: three.js's `WebGLRenderTarget.texture`.

        `resolve` and then `render.texture.texture_of`: the light is
        encoded to bytes once, through the curve if one is asked for, and
        those bytes are what the texture decodes back. Ask before drawing
        into the target again; the texture is a copy, not a view.

        Args:
            wrap: How coordinates outside the unit square are resolved.
            filter: `NEAREST` or `BILINEAR`.
            mipmapped: Build the chain of halved copies.
            alpha: `COVERAGE` or `IGNORED`; see `texture_of`.
            workers: How many threads to encode with.
            tone_mapping: The curve to encode through; see `resolve`.
            exposure: What the light is scaled by before the curve.

        Returns:
            The texture, stored `SRGB`.

        Raises:
            Error: Everything `resolve` raises, or a wrap, filter or alpha
                mode that is none of the named values.
        """
        return texture_of(
            self.resolve(workers, tone_mapping, exposure),
            wrap,
            filter,
            mipmapped,
            alpha,
        )

    def depth_texture(self, wrap: Wrap = CLAMP) raises -> Texture:
        """Return this target's depth as a texture, three.js's
        `DepthTexture` on a render target.

        `render.texture.depth_texture_of` of the depth as it stands: the
        color is not resolved. See there for what a texel holds, and for
        why it is a preview at eight bits and not a depth to compare.

        Args:
            wrap: How coordinates outside the unit square are resolved.

        Returns:
            The texture.

        Raises:
            Error: If the wrap mode is none of the named values.
        """
        return depth_texture_of_buffer(
            self.width, self.height, self.depth, wrap
        )
