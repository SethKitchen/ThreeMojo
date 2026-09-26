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

**Type and attachments.** three.js's `WebGLRenderTarget` takes a `type` and
a `count`. Every target here accumulates in floats whatever its type, so
the type decides what a readout holds -- `attachment` and
`attachment_texture` -- and nothing else: `UNSIGNED_BYTE_TARGET` clamps
and quantizes, `HALF_FLOAT_TARGET` rounds to a half, and `FLOAT_TARGET`
keeps the light as it is, above one included, with no curve and no
encode. The outputs say what each color attachment holds, three.js's
`count` with the fragment shader's `layout(location = i)` outputs: the
lit color first, then optionally the view-space normal of the nearest
opaque surface, a G-buffer the screen-space passes read. See
`TargetType` and `TargetOutput`.

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

**A data pixel is stored straight.** Its alpha is data too: a depth packed
into four channels puts its last eight bits there, and that alpha is often
zero. Premultiplied, such a pixel would keep no color at all. So `write`
stores a data fragment as it is, `resolve` shows it as it is, and `blend`
and `light_at` premultiply it first, where they read it as light. The
kernel keeps its running color the same way.
"""

from math.vector3 import Vector3
from render.blend import NORMAL_MODE, Rgba, blend_fragment
from render.color_spaces import OutputEncoding
from render.float_image import FloatImage
from render.raster_state import (
    STANDARD_DEPTH,
    DepthMode,
    FragmentTest,
    RasterState,
    cleared_depth,
    is_nearer,
    test_fragment,
    window_depth,
)
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
    NEAREST,
    IGNORED,
    depth_texture_of_buffer,
    float_texture,
    texture_of,
)
from render.tonemap import (
    NO_TONE_MAPPING,
    ProgramCurve,
    ToneMapping,
    check_tone_mapping,
    tone_map_with,
)
from std.math import inf, isfinite, max, min

# `TaskGroup` moved behind an underscore in Mojo 1.1: `std.runtime` keeps
# only `parallelism_level` and `initialize_runtime` in public view, and
# nothing public in `std` runs work on the thread pool -- `std.algorithm.map`
# is sequential. So the private module is the only way to keep the bands
# parallel, and this import is the one place the project reaches past a
# leading underscore. It pins the toolchain to 1.1: 1.0 has no `_asyncrt`
# and 1.1 has no `asyncrt`, so one source cannot serve both.
from std.runtime._asyncrt import TaskGroup


@fieldwise_init
struct TargetType(Equatable, ImplicitlyCopyable, Writable):
    """What a render target's attachments store, three.js's
    `WebGLRenderTarget` `type`, as a type rather than a bare int.

    The target accumulates in floats whatever this says; the type decides
    what `RenderTarget.attachment` reads back. The type stops a bare
    integer at compile time; it does not stop `TargetType(3)`, which
    `check_target` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three types there are.

        Returns:
            True for `UNSIGNED_BYTE_TARGET`, `HALF_FLOAT_TARGET` and
            `FLOAT_TARGET`.
        """
        return (
            self == UNSIGNED_BYTE_TARGET
            or self == HALF_FLOAT_TARGET
            or self == FLOAT_TARGET
        )


# Eight bits a channel, zero to one: three.js's `UnsignedByteType`, the
# default. A readout clamps each channel and rounds it to a 255th.
comptime UNSIGNED_BYTE_TARGET = TargetType(0)
# Sixteen-bit floats: three.js's `HalfFloatType`. Kept as floats, and a
# readout rounds each channel to the nearest half, held at the largest.
comptime HALF_FLOAT_TARGET = TargetType(1)
# Thirty-two-bit floats: three.js's `FloatType`. A readout is the light as
# it is, above one included.
comptime FLOAT_TARGET = TargetType(2)

# The largest finite half: what a half float target holds for anything
# brighter, where a GPU writing one would round it to infinity. A texture
# refuses infinity, so the port holds the largest number instead.
comptime HALF_MAX = Float32(65504)


@fieldwise_init
struct TargetOutput(Equatable, ImplicitlyCopyable, Writable):
    """What one color attachment of a render target holds, as a type
    rather than a bare int: the meaning of three.js's
    `layout(location = i) out` for a target with a `count` above one.

    The port has no user shaders, so the outputs a fragment can write are
    named here. The type stops a bare integer at compile time; it does not
    stop `TargetOutput(2)`, which `check_target` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two outputs there are.

        Returns:
            True for `OUTPUT_COLOR` and `OUTPUT_NORMAL`.
        """
        return self == OUTPUT_COLOR or self == OUTPUT_NORMAL


# The lit color, what a single-attachment target holds: `pc_fragColor`.
comptime OUTPUT_COLOR = TargetOutput(0)
# The view-space unit normal of the nearest opaque surface, after any
# normal or bump map: three.js's `gNormal` in its multiple render targets
# example. Zero where no triangle wrote one.
comptime OUTPUT_NORMAL = TargetOutput(1)


def color_only() -> List[TargetOutput]:
    """Return the outputs of a target with one attachment: the lit color.

    Returns:
        A list holding `OUTPUT_COLOR` alone.
    """
    return [OUTPUT_COLOR]


def check_target(type: TargetType, outputs: List[TargetOutput]) raises:
    """Refuse a type or a list of outputs no target can have.

    Args:
        type: The attachments' storage.
        outputs: What each color attachment holds, in order.

    Raises:
        Error: If the type is none of the three, the list is empty, its
            first output is not `OUTPUT_COLOR`, an output is none of the
            two, or an output repeats.
    """
    if not type.is_valid():
        raise Error("A render target type must be one of the three")
    if len(outputs) == 0 or outputs[0] != OUTPUT_COLOR:
        raise Error("A render target's first output must be the color")
    for index in range(1, len(outputs)):
        var output = outputs[index]
        if not output.is_valid():
            raise Error("A render target output must be one of the two")
        # An output written twice is one attachment too many. `index` is
        # at least one, so this loop always runs.
        for earlier in range(index):  # pragma: no branch
            if outputs[earlier] == output:
                raise Error("A render target output must not repeat")


def stored(value: Float32, type: TargetType) -> Float32:
    """Return one channel as an attachment of `type` holds it.

    Args:
        value: The channel, as the target accumulated it.
        type: The attachment's storage.

    Returns:
        The value clamped to zero through one and rounded to a 255th for
        `UNSIGNED_BYTE_TARGET`; rounded to the nearest half and held
        inside the halves' range for `HALF_FLOAT_TARGET`; and the value
        itself for `FLOAT_TARGET`.
    """
    if type == UNSIGNED_BYTE_TARGET:
        var held = max(Float32(0), min(Float32(1), value))
        return Float32(Int(held * 255 + 0.5)) / 255
    if type == HALF_FLOAT_TARGET:
        var held = max(-HALF_MAX, min(HALF_MAX, value))
        return held.cast[DType.float16]().cast[DType.float32]()
    return value


# The most samples a pixel of a multisampled target can take: a grid of
# four by four. WebGL 2 promises at least four, and sixteen is what a
# desktop GPU usually allows.
comptime MAX_SAMPLES = 16


def sample_grid(samples: Int) -> Int:
    """Return how many samples across and down each pixel of a target
    with `samples` takes.

    Args:
        samples: The target's sample count, as `check_samples` accepts it.

    Returns:
        The side of the grid: one for zero or one sample, two for four,
        three for nine and four for sixteen.
    """
    var side = 1
    while (side + 1) * (side + 1) <= samples:
        side += 1
    return side


def check_samples(samples: Int) raises:
    """Refuse a sample count no target here can take.

    The port takes its samples on a regular grid inside the pixel, so the
    count is a square. three.js takes any count, and the driver rounds it
    to one the hardware has.

    Args:
        samples: Three.js's `samples`: zero or one for none, or a square
            from four to `MAX_SAMPLES`.

    Raises:
        Error: If the count is negative, above `MAX_SAMPLES`, or neither
            zero nor a square.
    """
    if samples < 0 or samples > MAX_SAMPLES:
        raise Error("A render target takes zero through sixteen samples")
    var side = sample_grid(samples)
    if samples > 1 and side * side != samples:
        raise Error("A render target's samples must be a square: 4, 9 or 16")


trait SampleSource:
    """Where a multisample resolve reads its samples: a host target, or
    the kernel's planes. `resolve_block` asks these four things and
    nothing else, so both backends resolve with one function."""

    def light_at(self, slot: Int) -> FloatColor:
        """Return one sample's premultiplied linear light.

        Args:
            slot: The sample's index, row by row.

        Returns:
            The light, scaled by its alpha.
        """
        ...

    def depth_in(self, slot: Int) -> Float32:
        """Return one sample's depth, as its depth mode stores it.

        Args:
            slot: The sample's index, row by row.

        Returns:
            The depth. The mode's clear value where nothing was drawn.
        """
        ...

    def data_in(self, slot: Int) -> Bool:
        """Return True if one sample holds data rather than light.

        Args:
            slot: The sample's index, row by row.

        Returns:
            The sample's flag.
        """
        ...

    def normal_in(self, slot: Int) -> Vector3:
        """Return one sample's view-space normal.

        Args:
            slot: The sample's index, row by row.

        Returns:
            The normal, or zero where no surface wrote one.
        """
        ...


@fieldwise_init
struct ResolvedSample(ImplicitlyCopyable):
    """One pixel of a resolved multisample block, as a target stores it."""

    # Premultiplied light, or straight for a pixel that is data.
    var color: FloatColor
    # The nearest depth of the block, in the block's depth mode.
    var depth: Float32
    # True only if every sample of the block is data.
    var data: Bool
    # The block's normals summed and made unit length, or zero.
    var normal: Vector3


def resolve_block[
    S: SampleSource
](
    source: S,
    width: Int,
    factor: Int,
    x: Int,
    y: Int,
    depth_mode: DepthMode,
    normals: Bool,
) -> ResolvedSample:
    """Return the pixel a `factor` by `factor` block of samples resolves
    to: three.js's multisample resolve, and the supersampling average.

    The one function both backends resolve with. `RenderTarget.
    downsampled` and `RenderTarget.resolve_samples` call it on the host,
    and `render.gpu`'s resolve kernel calls it on the device, so the two
    resolves cannot differ. The samples are added row by row, then
    scaled once by the share of each. The light is premultiplied, so a
    sample that covers nothing adds nothing. The depth is the nearest of
    the block. The pixel is data only if every sample is, and a data
    pixel is stored straight. The normals are summed and made unit length
    again.

    Args:
        source: Where the samples are read.
        width: How many samples a row of `source` holds.
        factor: How many samples across and down become one pixel.
        x: The pixel's column in the resolved image.
        y: The pixel's row in the resolved image, from the top.
        depth_mode: How the depth is stored, which says what is nearest.
        normals: Whether to resolve the normals too.

    Returns:
        The resolved pixel.
    """
    var total = FloatColor(0.0, 0.0, 0.0, 0.0)
    var nearest = cleared_depth(depth_mode)
    # Counted rather than flagged: a `Bool` raised in a nested loop and
    # read after it hangs codegen; see `docs/wiki/The-Mojo-compiler-hang.md`.
    var datas = 0
    var normal = Vector3(0, 0, 0)
    # One loop over the block, row by row, and not two nested ones: the
    # nested spelling inside a caller's own loop sends codegen into the
    # hang `downsampled` once hit. A factor is at least one, so the loop
    # runs.
    for sample in range(factor * factor):  # pragma: no branch
        var row = sample // factor
        var column = sample % factor
        var slot = (y * factor + row) * width + x * factor + column
        var sampled = source.light_at(slot)
        total = FloatColor(
            total.r + sampled.r,
            total.g + sampled.g,
            total.b + sampled.b,
            total.a + sampled.a,
        )
        var z = source.depth_in(slot)
        if is_nearer(depth_mode, z, nearest):
            nearest = z
        if source.data_in(slot):
            datas += 1
        if normals:
            normal = normal + source.normal_in(slot)
    var share = 1 / Float32(factor * factor)
    var color = FloatColor(
        total.r * share, total.g * share, total.b * share, total.a * share
    )
    var data = datas == factor * factor
    # A data pixel is stored straight; see the module docstring.
    if data:
        color = color.unpremultiplied()
    # The average of two unit vectors is shorter than either. A block no
    # surface reached sums to zero and keeps no normal.
    if normal.length() != 0:
        normal.normalize()
    return ResolvedSample(color, nearest, data, normal)


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
    program: Pointer[List[Float32], ImmutAnyOrigin],
    output: OutputEncoding,
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
            var straight = colors[unsafe_offset=slot]
            if data[unsafe_offset=slot]:
                curve = NO_TONE_MAPPING
            else:
                straight = straight.unpremultiplied()
            var mapped = tone_map_with(
                straight, curve, exposure, ProgramCurve(program)
            )
            # A data pixel skips the output space, as three.js's normal
            # and depth materials skip `linearToOutputTexel`: it is stored
            # so that sRGB's curve gives back its bytes.
            if data[unsafe_offset=slot]:
                shown = mapped.encode()
            else:
                shown = output.encode(mapped)
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
    program: Pointer[List[Float32], ImmutAnyOrigin],
    output: OutputEncoding,
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
        program,
        output,
    )


struct RenderTarget(Movable, SampleSource):
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
    # How `depth` is stored, set by the last `clear_inside`: the
    # projection's depth, its logarithmic form or its reversed form. See
    # `render.raster_state.DepthMode`.
    var depth_mode: DepthMode
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
    # The stencil buffer, eight bits a pixel, cleared to zero with the
    # frame as three.js clears it. Read and written only by a primitive
    # whose state has `stencil_write` on; see `render.raster_state`.
    var stencil: List[UInt8]
    # What the attachments store, three.js's `type`; see `TargetType`.
    var type: TargetType
    # What each color attachment holds, in order, three.js's `count` and
    # the shader's outputs: the color first. See `TargetOutput`.
    var outputs: List[TargetOutput]
    # The view-space normal of each pixel's nearest opaque surface, zero
    # where none wrote one: the `OUTPUT_NORMAL` attachment. Empty when the
    # target has no such output, so a plain target pays nothing for it.
    var normals: List[Vector3]
    # How many samples each pixel takes when the renderer draws into it,
    # three.js's `samples`: zero or one for none, or a square up to
    # `MAX_SAMPLES`. The samples live only while one draw lasts; the
    # target keeps what they resolve to. See `resolve_samples`.
    var samples: Int

    def __init__(
        out self,
        width: Int,
        height: Int,
        clear: Color,
        type: TargetType = UNSIGNED_BYTE_TARGET,
        outputs: List[TargetOutput] = color_only(),
        samples: Int = 0,
    ) raises:
        """Create a target cleared to `clear`.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
            clear: The color to fill with, decoded from sRGB. Its alpha is
                kept, so clearing to something transparent gives a target that
                stays transparent where nothing is drawn.
            type: What the attachments store, three.js's `type`:
                `UNSIGNED_BYTE_TARGET`, the default, `HALF_FLOAT_TARGET` or
                `FLOAT_TARGET`. It changes what `attachment` reads back.
            outputs: What each color attachment holds, in order: three.js's
                `count` and the shader's outputs. The color alone by
                default. Add `OUTPUT_NORMAL` for a normal attachment.
            samples: How many samples each pixel takes when the renderer
                draws into the target, three.js's `samples`. Zero, the
                default, takes one.

        Raises:
            Error: If either dimension is not positive, `check_target`
                refuses the type or the outputs, or `check_samples`
                refuses the sample count.
        """
        if width <= 0 or height <= 0:
            raise Error("Render target dimensions must be positive")
        check_target(type, outputs)
        check_samples(samples)
        self.samples = samples
        self.type = type
        self.outputs = outputs.copy()
        self.normals = List[Vector3]()
        if OUTPUT_NORMAL in outputs:
            self.normals = List[Vector3](
                length=width * height, fill=Vector3(0, 0, 0)
            )
        self.width = width
        self.height = height
        self.clear = FloatColor(srgb=clear).premultiplied()
        self.colors = List[FloatColor](length=width * height, fill=self.clear)
        self.depth = List[Float32](
            length=width * height, fill=inf[DType.float32]()
        )
        self.depth_mode = STANDARD_DEPTH
        self.data = List[Bool](length=width * height, fill=False)
        self.scissor = Rect.whole(width, height)
        self.stencil = List[UInt8](length=width * height, fill=0)

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

    def clear_inside(
        mut self,
        rect: Rect,
        clear: Color,
        depth_mode: DepthMode = STANDARD_DEPTH,
        color: Bool = True,
        depth: Bool = True,
        stencil: Bool = True,
    ) raises:
        """Reset every pixel inside `rect` to `clear`, its depth to the
        far distance, its stencil to zero, its normal to none and its flag
        to light, leaving the rest alone.

        Each of the three buffers can be left as it is, three.js's
        `clear(color, depth, stencil)`: the color takes the normal and the
        flag with it, and the depth takes the depth mode.

        The far distance is the depth mode's: infinity, or minus infinity
        under `REVERSED_DEPTH`, three.js's clear of the reversed buffer.
        The target records the mode, so what reads the depth later knows
        how it is stored.

        What clearing under a scissor does on a GPU, and what lets two
        viewports share one target: each clears its own rectangle and
        draws into it, and neither touches the other's. `Renderer.render_into`
        calls this before it draws.

        Args:
            rect: The pixels to reset. It must lie wholly inside the target.
            clear: The color to fill with, decoded from sRGB, alpha kept.
            depth_mode: How the depth is stored from now on.
            color: Whether the color is cleared. On by default.
            depth: Whether the depth is cleared. On by default.
            stencil: Whether the stencil is cleared. On by default.

        Raises:
            Error: If the rectangle is empty or reaches outside the target,
                or the depth mode is none of the three.
        """
        if not rect.fits(self.width, self.height):
            raise Error("A clear must lie inside the target")
        if not depth_mode.is_valid():
            raise Error("A depth mode that is none of the three")
        if color:
            self.clear = FloatColor(srgb=clear).premultiplied()
        if depth:
            self.depth_mode = depth_mode
        var far = cleared_depth(self.depth_mode)
        var top = rect.top(self.height)
        for y in range(top, top + rect.height):  # pragma: no branch
            for x in range(rect.x, rect.x + rect.width):  # pragma: no branch
                var slot = y * self.width + x
                if color:
                    self.colors[slot] = self.clear
                    self.data[slot] = False
                if depth:
                    self.depth[slot] = far
                if stencil:
                    self.stencil[slot] = 0
        if color and self.has_normals():
            for y in range(top, top + rect.height):  # pragma: no branch
                for x in range(
                    rect.x, rect.x + rect.width
                ):  # pragma: no branch
                    self.normals[y * self.width + x] = Vector3(0, 0, 0)

    def _slot(self, x: Int, y: Int) raises -> Int:
        """Return the index of pixel (x, y), checking it is inside."""
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Pixel coordinate out of bounds")
        return y * self.width + x

    def depth_at(self, x: Int, y: Int) raises -> Float32:
        """Return the depth recorded at pixel (x, y)."""
        return self.depth[self._slot(x, y)]

    def stencil_at(self, x: Int, y: Int) raises -> Int:
        """Return the stencil value recorded at pixel (x, y).

        Args:
            x: Column.
            y: Row.

        Returns:
            The value, from 0 to 255.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        return Int(self.stencil[self._slot(x, y)])

    def test_fragment(
        self, x: Int, y: Int, z: Float32, state: RasterState
    ) raises -> FragmentTest:
        """Return what the stencil and the depth tests say about a
        fragment at pixel (x, y), changing nothing.

        `render.raster_state.test_fragment` against this pixel, the
        function the kernel calls against its own. A pixel outside the
        scissor fails and changes nothing, as a GPU's scissor test
        discards a fragment before the stencil test.

        Args:
            x: Column.
            y: Row.
            z: The fragment's NDC depth.
            state: The primitive's depth, color and stencil state.

        Returns:
            Whether the fragment passes and the stencil value it leaves.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        var stored = Int(self.stencil[slot])
        if not self.scissor.contains_pixel(x, y, self.height):
            return FragmentTest(False, stored, False)
        return test_fragment(state, z, self.depth[slot], stored)

    def keep_stencil(mut self, x: Int, y: Int, test: FragmentTest) raises:
        """Record the stencil value a fragment leaves, testing nothing.

        The stencil half of settling a fragment, called with what
        `test_fragment` returned once the fragment survives its alpha
        test, or at once when it fails and cannot be discarded. A test
        that changes nothing writes nothing.

        Args:
            x: Column.
            y: Row.
            test: What `test_fragment` returned for this pixel.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        if not test.changes:
            return
        self.stencil[slot] = UInt8(test.stencil)

    def color_at(self, x: Int, y: Int) raises -> FloatColor:
        """Return the premultiplied linear color at pixel (x, y)."""
        return self.light_at(self._slot(x, y))

    def straight_at(self, slot: Int) -> FloatColor:
        """Return the straight linear color in slot `slot`.

        A light pixel is unpremultiplied here. A data pixel is stored
        straight, and is returned as it is; see the module docstring.

        Args:
            slot: The pixel's index, row by row.

        Returns:
            The color, not scaled by its alpha.
        """
        if self.data[slot]:
            return self.colors[slot]
        return self.colors[slot].unpremultiplied()

    def light_at(self, slot: Int) -> FloatColor:
        """Return the premultiplied linear color in slot `slot`.

        A light pixel is stored so. A data pixel is stored straight, and is
        premultiplied here; see the module docstring.

        Args:
            slot: The pixel's index, row by row.

        Returns:
            The color, scaled by its alpha.
        """
        if self.data[slot]:
            return self.colors[slot].premultiplied()
        return self.colors[slot]

    def depth_in(self, slot: Int) -> Float32:
        """Return the depth in slot `slot`, as the depth mode stores it.

        Args:
            slot: The pixel's index, row by row.

        Returns:
            The depth.
        """
        return self.depth[slot]

    def data_in(self, slot: Int) -> Bool:
        """Return True if slot `slot` holds data rather than light.

        Args:
            slot: The pixel's index, row by row.

        Returns:
            The pixel's flag.
        """
        return self.data[slot]

    def normal_in(self, slot: Int) -> Vector3:
        """Return the view-space normal in slot `slot`.

        Args:
            slot: The pixel's index, row by row.

        Returns:
            The normal, or zero where no surface wrote one or the target
            has no normal attachment.
        """
        if not self.has_normals():
            return Vector3(0, 0, 0)
        return self.normals[slot]

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
        mut self,
        x: Int,
        y: Int,
        color: FloatColor,
        data: Bool = False,
        normal: Vector3 = Vector3(0, 0, 0),
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
            normal: The surface's view-space unit normal, kept when the
                target has an `OUTPUT_NORMAL` attachment. Zero, the
                default, is no surface: what a line or a point leaves.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        if not self.scissor.contains_pixel(x, y, self.height):
            return
        # A data pixel is stored straight: its alpha is data too, and a
        # packed depth's is often zero. See the module docstring.
        if data:
            self.colors[slot] = color
        else:
            self.colors[slot] = color.premultiplied()
        self.data[slot] = data
        if self.has_normals():
            self.normals[slot] = normal

    def blend(
        mut self,
        x: Int,
        y: Int,
        color: FloatColor,
        mode: Int = NORMAL_MODE,
        premultiplied: Bool = False,
        constant: Rgba = Rgba(0),
    ) raises:
        """Mix `color` into pixel (x, y) by a blending mode.

        The normal attachment is left alone, so it stays the one of the
        opaque surface behind. The kernel keeps it the same way. The
        result is light, whatever was there before. Only light blends:
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
            premultiplied: Whether the material's `premultipliedAlpha` is
                on; see `render.blend.blend_fragment`. Off by default.
            constant: The constant color the constant factors read,
                `RasterState.blend_constant`. Clear black by default.

        Raises:
            Error: If the coordinate is out of bounds.
        """
        var slot = self._slot(x, y)
        if not self.scissor.contains_pixel(x, y, self.height):
            return
        if mode == NORMAL_MODE and not color.a > 0:
            return
        var behind = self.light_at(slot)
        self.data[slot] = False
        var out = blend_fragment(
            Rgba(behind.r, behind.g, behind.b, behind.a),
            Rgba(color.r, color.g, color.b, color.a),
            mode,
            premultiplied,
            constant,
        )
        self.colors[slot] = FloatColor(out[0], out[1], out[2], out[3])

    def shown(
        self,
        x: Int,
        y: Int,
        tone_mapping: ToneMapping = NO_TONE_MAPPING,
        exposure: Float32 = 1.0,
        program: List[Float32] = List[Float32](),
        output: OutputEncoding = OutputEncoding(),
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
            program: The custom curve's program, `NodeProgram.code`, read
                under `CUSTOM_TONE_MAPPING`; see `render.tonemap`. None by
                default, which leaves the light as it is.
            output: How the light is written out; see `resolve`.

        Returns:
            The resolved eight-bit color.

        Raises:
            Error: If the coordinate is out of bounds, the curve is none of
                the eight, or the exposure is negative or not finite.
        """
        check_tone_mapping(tone_mapping, exposure)
        var slot = self._slot(x, y)
        var curve = tone_mapping
        var straight = self.colors[slot]
        if self.data[slot]:
            curve = NO_TONE_MAPPING
        else:
            straight = straight.unpremultiplied()
        var mapped = tone_map_with(
            straight, curve, exposure, ProgramCurve(Pointer(to=program))
        )
        if self.data[slot]:
            return mapped.encode()
        return output.encode(mapped)

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
        its nearest surface. Nearest is the target's depth mode's: the
        largest depth under `REVERSED_DEPTH`.

        **The normal is the average of the block's, made unit length
        again**, when the target has a normal attachment.

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
            The smaller target, its clear color, depth mode, type,
            outputs and samples carried over, the scissor widened to the
            whole of it. Each pixel is `resolve_block` of its block, and
            its stencil is the block's first sample's.

        Raises:
            Error: If the factor is less than one or does not divide both
                dimensions.
        """
        if factor < 1:
            raise Error("A downsample factor is at least one")
        if self.width % factor != 0 or self.height % factor != 0:
            raise Error("A downsample factor must divide the target's size")
        var small = RenderTarget(
            self.width // factor,
            self.height // factor,
            Color(0, 0, 0, 0),
            self.type,
            self.outputs,
            self.samples,
        )
        small._resolve_blocks(
            self, factor, Rect.whole(small.width, small.height)
        )
        return small^

    def multisample_buffer(self) raises -> RenderTarget:
        """Return the buffer a draw into this target takes its samples in:
        three.js's multisampled renderbuffer.

        `sample_grid(samples)` times this target's size each way, with its
        type and its outputs and no samples of its own.
        `Renderer.render_into` draws into it and then calls
        `resolve_samples`.

        Every sample starts as its pixel: its color, depth, data flag,
        stencil and normal. So a draw that clears nothing, with the
        renderer's `auto_clear` off, draws over what the target holds, as
        three.js draws over its multisampled renderbuffer. The clear color
        and the depth mode are the target's too.

        Returns:
            The larger target.

        Raises:
            Error: If the larger target cannot be built.
        """
        var grid = sample_grid(self.samples)
        var buffer = RenderTarget(
            self.width * grid,
            self.height * grid,
            Color(0, 0, 0, 0),
            self.type,
            self.outputs,
        )
        buffer.clear = self.clear
        buffer.depth_mode = self.depth_mode
        var keeps = self.has_normals()
        # Walked flat, over the samples; both sides are positive, so it
        # runs.
        for sample in range(buffer.width * buffer.height):  # pragma: no branch
            var x = sample % buffer.width // grid
            var y = sample // buffer.width // grid
            var slot = y * self.width + x
            buffer.colors[sample] = self.colors[slot]
            buffer.depth[sample] = self.depth[slot]
            buffer.data[sample] = self.data[slot]
            buffer.stencil[sample] = self.stencil[slot]
            if keeps:
                buffer.normals[sample] = self.normals[slot]
        return buffer^

    def resolve_samples(mut self, buffer: RenderTarget, rect: Rect) raises:
        """Resolve a multisample buffer into the pixels inside `rect`:
        three.js's resolve of `samples` into the target's textures.

        Each pixel inside `rect` becomes `resolve_block` of its block of
        samples: the average light, the nearest depth, the unit normal
        and the data flag, as `downsampled` resolves them. The stencil
        takes the first sample of the block, as a blit of a stencil takes
        one sample and never an average. Pixels outside `rect` are left
        as they were. The target takes the buffer's clear color and depth
        mode.

        Args:
            buffer: The samples, as `multisample_buffer` shapes them.
            rect: The pixels to resolve, its corner at the bottom left.

        Raises:
            Error: If the buffer is not `sample_grid(samples)` times this
                target's size each way, its outputs differ from this
                target's, or the rectangle is empty or reaches outside
                the target.
        """
        var grid = sample_grid(self.samples)
        if (
            buffer.width != self.width * grid
            or buffer.height != self.height * grid
        ):
            raise Error(
                "A multisample buffer must be the sample grid times the"
                " target's size"
            )
        if buffer.has_normals() != self.has_normals():
            raise Error("A multisample buffer must have the target's outputs")
        if not rect.fits(self.width, self.height):
            raise Error("A resolve must lie inside the target")
        self._resolve_blocks(buffer, grid, rect)

    def _resolve_blocks(
        mut self, source: RenderTarget, factor: Int, rect: Rect
    ):
        """Set every pixel inside `rect` to `resolve_block` of its block
        in `source`, which is `factor` times this target's size and holds
        the same outputs. See `resolve_samples`."""
        self.clear = source.clear
        self.depth_mode = source.depth_mode
        var keeps = self.has_normals()
        var top = rect.top(self.height)
        # Walked flat, over the rectangle's pixels: two loops around the
        # two inside `resolve_block` is the nesting that has hung codegen
        # before. A rectangle that fits holds a pixel, so this runs.
        for index in range(rect.width * rect.height):  # pragma: no branch
            var x = rect.x + index % rect.width
            var y = top + index // rect.width
            var resolved = resolve_block(
                source, source.width, factor, x, y, source.depth_mode, keeps
            )
            var slot = y * self.width + x
            self.colors[slot] = resolved.color
            self.depth[slot] = resolved.depth
            self.data[slot] = resolved.data
            self.stencil[slot] = source.stencil[
                y * factor * source.width + x * factor
            ]
            if keeps:
                self.normals[slot] = resolved.normal

    def resolve(
        self,
        workers: Int = 1,
        tone_mapping: ToneMapping = NO_TONE_MAPPING,
        exposure: Float32 = 1.0,
        program: List[Float32] = List[Float32](),
        output: OutputEncoding = OutputEncoding(),
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
            program: The custom curve's program, `NodeProgram.code`, read
                under `CUSTOM_TONE_MAPPING`; see `render.tonemap`. None by
                default, which leaves the light as it is.
            output: How the light is written out, three.js's
                `outputColorSpace`; see `render.color_spaces.
                output_encoding`. sRGB by default.

        Returns:
            The image as eight-bit color in the output space, sRGB unless
            `output` says otherwise, with unassociated alpha, which is what
            PNG stores.

        Raises:
            Error: If `workers` is less than one, the curve is none of the
                eight, the exposure is negative or not finite, or the
                framebuffer cannot be built.
        """
        if workers < 1:
            raise Error("Resolving needs at least one worker")
        check_tone_mapping(tone_mapping, exposure)
        var count = self.width * self.height
        var pixels = List[UInt8](length=count * Framebuffer.CHANNELS, fill=0)
        # The background, by the same three steps every other pixel takes.
        var words = Pointer(to=program).unsafe_origin_cast[ImmutAnyOrigin]()
        var clear_shown = output.encode(
            tone_map_with(
                self.clear.unpremultiplied(),
                tone_mapping,
                exposure,
                ProgramCurve(words),
            )
        )
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
                words,
                output,
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
                        words,
                        output,
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

    def depth_texture(
        self, wrap: Wrap = CLAMP, type: TargetType = UNSIGNED_BYTE_TARGET
    ) raises -> Texture:
        """Return this target's depth as a texture, three.js's
        `DepthTexture` on a render target.

        The depth as it stands: the color is not resolved. Each texel is
        `render.raster_state.window_depth` of the stored depth in the
        target's depth mode, from zero to one, in red, green and blue,
        with an alpha of one: one at the far plane and where nothing was
        drawn, or zero under a reversed depth, which shows white near and
        black far, as three.js's texture holds it. It is read nearest with
        no chain: two depths averaged are the depth of nothing.

        With `UNSIGNED_BYTE_TARGET`, the default, it is
        `render.texture.depth_texture_of`: a preview at eight bits, and not
        a depth to compare. With `FLOAT_TARGET` it is the depth itself, as
        three.js's `DepthTexture` with a `type` of `FloatType` holds it,
        in a float texture. `HALF_FLOAT_TARGET` rounds it to a half.

        Args:
            wrap: How coordinates outside the unit square are resolved.
            type: What each texel stores.

        Returns:
            The texture.

        Raises:
            Error: If the wrap mode is none of the named values, or the
                type is none of the three.
        """
        if not type.is_valid():
            raise Error("A render target type must be one of the three")
        if type == UNSIGNED_BYTE_TARGET:
            return depth_texture_of_buffer(
                self.width, self.height, self.depth, wrap, self.depth_mode
            )
        var count = self.width * self.height
        var data = List[Float32](capacity=count * Texture.CHANNELS)
        # Both dimensions are positive, so the loop always runs.
        for slot in range(count):  # pragma: no branch
            var window = stored(
                window_depth(self.depth_mode, self.depth[slot]), type
            )
            data.append(window)
            data.append(window)
            data.append(window)
            data.append(1)
        return float_texture(
            self.width, self.height, data^, wrap, NEAREST, False, IGNORED
        )

    def count(self) -> Int:
        """Return how many color attachments this target has, three.js's
        `count`.

        Returns:
            The length of `outputs`, at least one.
        """
        return len(self.outputs)

    def has_normals(self) -> Bool:
        """Return True if this target has an `OUTPUT_NORMAL` attachment.

        Returns:
            Whether a triangle's opaque write keeps its normal here.
        """
        return len(self.normals) != 0

    def normal_at(self, x: Int, y: Int) raises -> Vector3:
        """Return the view-space normal kept at pixel (x, y).

        Args:
            x: Column.
            y: Row.

        Returns:
            The unit normal of the nearest opaque surface, or zero where
            no triangle wrote one.

        Raises:
            Error: If the coordinate is out of bounds, or the target has no
                normal attachment.
        """
        var slot = self._slot(x, y)
        if not self.has_normals():
            raise Error("This render target has no normal attachment")
        return self.normals[slot]

    def attachment(self, index: Int) raises -> FloatImage:
        """Return one color attachment as its type stores it, three.js's
        `readRenderTargetPixels` on `textures[index]`.

        The color attachment holds the light with straight alpha: not tone
        mapped, not encoded, and not clamped in a float target, as three.js
        writes into a render target. A pixel that holds data -- a normal
        material's bytes, the uv view's coordinates -- reads as the
        fractions its bytes show. The normal attachment holds the view-space
        normal with an alpha of one, and zero where no surface wrote one.
        In an `UNSIGNED_BYTE_TARGET` a normal cannot be negative, so it is
        packed first, halved and moved up by a half, three.js's
        `packNormalToRGB`; a pixel with no normal stays zero.

        Args:
            index: Which attachment, from zero to `count() - 1`.

        Returns:
            Four floats a pixel, row-major from the top, each passed
            through `stored` for the target's type.

        Raises:
            Error: If the index is outside the attachments.
        """
        if index < 0 or index >= self.count():
            raise Error("A render target attachment index is out of range")
        var total = self.width * self.height
        var pixels = List[Float32](capacity=total * FloatImage.CHANNELS)
        var packs = self.type == UNSIGNED_BYTE_TARGET
        var normal = self.outputs[index] == OUTPUT_NORMAL
        # Both dimensions are positive, so the loop always runs.
        for slot in range(total):  # pragma: no branch
            var value: FloatColor
            if normal:
                var n = self.normals[slot]
                value = FloatColor(n.x, n.y, n.z, 1)
                if n.length() == 0:
                    value = FloatColor(0, 0, 0, 0)
                elif packs:
                    value = FloatColor(
                        n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1
                    )
            else:
                value = self.straight_at(slot)
                if self.data[slot]:
                    # Stored decoded so the encode gives the bytes back;
                    # the fraction is those bytes. See `data_color`.
                    var shown = value.encode()
                    value = FloatColor(
                        Float32(shown.r) / 255,
                        Float32(shown.g) / 255,
                        Float32(shown.b) / 255,
                        value.a,
                    )
            pixels.append(stored(value.r, self.type))
            pixels.append(stored(value.g, self.type))
            pixels.append(stored(value.b, self.type))
            pixels.append(stored(value.a, self.type))
        return FloatImage(self.width, self.height, pixels^)

    def attachment_texture(
        self,
        index: Int,
        wrap: Wrap = CLAMP,
        filter: Filter = BILINEAR,
        mipmapped: Bool = False,
    ) raises -> Texture:
        """Return one color attachment as a texture a later draw can
        sample, three.js's `WebGLRenderTarget.textures[index]`.

        `attachment` in a float texture, so the numbers are sampled as
        they are stored: light above one stays above one, and a normal
        keeps its sign. The texture's alpha hides color, as the target's
        alpha does.

        Args:
            index: Which attachment, from zero to `count() - 1`.
            wrap: How coordinates outside the unit square are resolved.
            filter: `NEAREST` or `BILINEAR`.
            mipmapped: Build the chain of halved copies.

        Returns:
            The texture: `FLOAT_TYPE`, `LINEAR`.

        Raises:
            Error: Everything `attachment` raises, or a wrap or filter mode
                that is none of the named values.
        """
        var image = self.attachment(index)
        return float_texture(
            self.width,
            self.height,
            image.pixels.copy(),
            wrap,
            filter,
            mipmapped,
            COVERAGE,
        )
