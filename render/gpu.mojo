# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rasterizing prepared triangles on the GPU, one thread per pixel.

`render.rasterizer` walks the pixels of one triangle at a time in a nested
loop. This turns that inside out: one thread owns one pixel for the whole
draw, walks every triangle, and keeps the nearest one it is covered by. The
two produce identical images, which `tests/test_gpu.mojo` checks pixel for
pixel, because both decide coverage with `render.fillrule` — the same module,
not a copy of it.

**One owner per pixel.** A thread per pixel is not the only way to divide the
work — a thread per triangle is the obvious alternative, and faster when
triangles are large — but it is the only one of the two that is correct
without synchronization. Independent triangle threads writing a shared colour
and depth buffer race: `Framebuffer.test_depth` is a read followed by a write,
which is a depth test, not an atomic. Because each pixel here is owned
outright, its depth lives in a register that nothing else can touch. That
depth is written out alongside the colour, so what comes back is a framebuffer
in the same sense the CPU produces one — a result that reports no depth at all
would silently let a later depth-tested triangle paint over a nearer surface.
Tiling and per-triangle binning can come later; they are optimizations of a
correct thing.

**The transform pipeline is still on the host.** Scene traversal, projection,
lighting and clipping run on the CPU, and only the finished screen-space
triangles come here. That is a deliberate stage, not an unfinished one: it
makes the GPU a second implementation of exactly one well-defined step, which
is what lets the parity tests be meaningful.

Colours cross the boundary packed into a `UInt32`. Kernel arguments must
conform to `DevicePassable`, which rules out the `Color` struct and, less
obviously, plain `Int` — the compiler asks for a fixed-width type instead.

Whether this is *faster* than the CPU is a separate question, and the answer
is size-dependent. `bench/raster_bench.mojo` measures where the crossover is.
"""

from math.vector2 import Vector2
from max.gpu.host import DeviceBuffer, DeviceContext
from render.fillrule import bias, edge_at, sample, snap
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rasterizer import (
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    Triangle,
)
from materials.material import NO_TEXTURE
from render.texture import BILINEAR, NEAREST, Texture, blend, wrap_index
from render.texture_store import TextureStore
from std.gpu import global_idx
from std.math import ceildiv, floor, inf
from std.memory import unsafe_memcpy
from std.sys import has_accelerator

# 16x16 threads is a conventional starting point for a 2D grid: a multiple of
# the warp size on every vendor, and small enough that a narrow image still
# fills several blocks.
comptime TILE = 16

# How a `RasterVertex` is laid out in the flat float buffer the kernel reads:
# x, y, z, inv_w, r, g, b, a, u, v, texture id. A struct would be tidier and
# is not an
# option — the buffer has to be plain floats to cross to the device.
# tests/test_gpu.mojo asserts this layout, because the host packs it and the
# kernel unpacks it from two different places and nothing else would notice
# them drifting apart.
comptime FLOATS_PER_VERTEX = 11
comptime FLOATS_PER_TRIANGLE = FLOATS_PER_VERTEX * 3

# Further than any NDC depth, so the first covering triangle always wins. The
# host framebuffer uses an actual infinity; a literal keeps the kernel free of
# any dependency on how the host spells one.
comptime FURTHEST = Float32(1.0e30)

# One row per texture in the store: where its bytes start, how big it is, and
# how to sample it. A device cannot hold a `List` of `List`s, so every image
# goes into one buffer end to end and this says where each one begins.
comptime TABLE_COLUMNS = 5


def flatten_textures(
    textures: TextureStore,
) raises -> Tuple[List[UInt8], List[Int32]]:
    """Return every texture's bytes end to end, and the table describing them.

    Args:
        textures: The store to upload.

    Returns:
        The concatenated texels, and `TABLE_COLUMNS` entries per texture:
        byte offset, width, height, wrap mode, filter mode.

    Raises:
        Error: If a texture cannot be read.
    """
    var texels = List[UInt8]()
    var table = List[Int32]()
    for id in range(textures.count()):
        ref image = textures.get(id)
        table.append(Int32(len(texels)))
        if image.is_blank():
            # A blank texture is a legitimate thing to store, and on the host
            # it samples as opaque white. Rather than teach the kernel a
            # second meaning for "no texture", it crosses as one white texel:
            # the device invariant stays "every descriptor has a real size",
            # and sampling a 1x1 white image gives white at any coordinate
            # under any wrap mode. Left as a zero width it reached
            # `wrap_index(..., 0, REPEAT)`, which is a modulo by zero, and the
            # GPU returned black where the CPU returned white.
            table.append(1)
            table.append(1)
            table.append(Int32(image.wrap))
            table.append(Int32(image.filter))
            for _ in range(4):
                texels.append(255)
            continue
        table.append(Int32(image.width))
        table.append(Int32(image.height))
        table.append(Int32(image.wrap))
        table.append(Int32(image.filter))
        for byte in range(len(image.pixels)):
            texels.append(image.pixels[byte])
    # Never empty: a zero-length device buffer is not worth the special case,
    # and a vertex naming NO_TEXTURE never reads either of these.
    if len(texels) == 0:
        texels.append(0)
    if len(table) == 0:
        for _ in range(TABLE_COLUMNS):
            table.append(0)
    return (texels^, table^)


def pack(color: Color) -> UInt32:
    """Return `color` packed into one big-endian RGBA word."""
    return (
        (UInt32(color.r) << 24)
        | (UInt32(color.g) << 16)
        | (UInt32(color.b) << 8)
        | UInt32(color.a)
    )


def available() -> Bool:
    """Return True if this machine has a GPU Mojo can target."""
    return has_accelerator()


def flatten(corners: List[RasterVertex]) -> List[Float32]:
    """Return `corners` as the flat float buffer the kernel reads.

    Args:
        corners: Raster vertices, three per triangle.

    Returns:
        Eleven floats per vertex, in the order the kernel unpacks them.
    """
    var flat = List[Float32]()
    for index in range(len(corners)):
        var corner = corners[index]
        flat.append(corner.x)
        flat.append(corner.y)
        flat.append(corner.z)
        flat.append(corner.inv_w)
        flat.append(corner.color.r)
        flat.append(corner.color.g)
        flat.append(corner.color.b)
        flat.append(corner.color.a)
        flat.append(corner.u)
        flat.append(corner.v)
        flat.append(Float32(corner.texture))
    return flat^


def _fetch(
    texels: MutPointer[UInt8, MutAnyOrigin],
    start: Int,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    wrap: Int,
) -> FloatColor:
    """Read one texel from the device buffer, with the wrap mode applied.

    The device counterpart of `Texture.wrapped_texel`. Only the memory access
    differs between the two — the index arithmetic is `wrap_index`, shared,
    and so is the blend built on top of it.
    """
    var offset = (
        start
        + (wrap_index(y, height, wrap) * width + wrap_index(x, width, wrap)) * 4
    )
    return FloatColor(
        Float32(texels[unsafe_offset=offset]) / 255,
        Float32(texels[unsafe_offset=offset + 1]) / 255,
        Float32(texels[unsafe_offset=offset + 2]) / 255,
        Float32(texels[unsafe_offset=offset + 3]) / 255,
    )


def rasterize_kernel(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    corners: MutPointer[Float32, MutAnyOrigin],
    triangles: Int32,
    width: Int32,
    height: Int32,
    background: UInt32,
    mode: Int32,
    texels: MutPointer[UInt8, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
):
    """Colour one pixel from the nearest triangle that covers it."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    # The grid is rounded up to whole tiles, so the edges overhang the image.
    if x >= Int(width) or y >= Int(height):
        return

    var px = sample(x)
    var py = sample(y)

    var nearest = FURTHEST
    var found = False
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    var alpha = Float32(0)

    for index in range(Int(triangles)):
        var base = index * FLOATS_PER_TRIANGLE
        var ax = corners[unsafe_offset=base]
        var ay = corners[unsafe_offset=base + 1]
        var az = corners[unsafe_offset=base + 2]
        var aw = corners[unsafe_offset=base + 3]
        var bx = corners[unsafe_offset=base + 11]
        var by = corners[unsafe_offset=base + 12]
        var bz = corners[unsafe_offset=base + 13]
        var bw = corners[unsafe_offset=base + 14]
        var cx = corners[unsafe_offset=base + 22]
        var cy = corners[unsafe_offset=base + 23]
        var cz = corners[unsafe_offset=base + 24]
        var cw = corners[unsafe_offset=base + 25]

        # Exactly `_Coverage` on the host: snap, normalize the winding, then
        # test with the top-left bias. Only the snapped coordinates are
        # swapped; the attributes stay in the caller's order and the weights
        # are mapped back at the end.
        var sax = snap(ax)
        var say = snap(ay)
        var sbx = snap(bx)
        var sby = snap(by)
        var scx = snap(cx)
        var scy = snap(cy)

        var area = edge_at(sax, say, sbx, sby, scx, scy)
        var swapped = area < 0
        if swapped:
            var tx = sbx
            var ty = sby
            sbx = scx
            sby = scy
            scx = tx
            scy = ty
            area = -area
        if area == 0:
            continue

        var e_ab = edge_at(sax, say, sbx, sby, px, py)
        var e_bc = edge_at(sbx, sby, scx, scy, px, py)
        var e_ca = edge_at(scx, scy, sax, say, px, py)
        if (
            e_ab + bias(sax, say, sbx, sby) < 0
            or e_bc + bias(sbx, sby, scx, scy) < 0
            or e_ca + bias(scx, scy, sax, say) < 0
        ):
            continue

        # The edge opposite a corner is that corner's weight.
        var span = Float32(area)
        var first = Float32(e_bc) / span
        var second = Float32(e_ca) / span
        var third = Float32(e_ab) / span
        var wa = first
        var wb = second
        var wc = third
        if swapped:
            wb = third
            wc = second

        # Depth interpolates affinely; see `RasterVertex.z`.
        var z = wa * az + wb * bz + wc * cz
        if z >= nearest:
            continue
        nearest = z
        found = True

        # Colour does not: weight by inv_w and divide by the interpolated
        # inv_w, matching `rasterize_shaded`.
        var inv_w = wa * aw + wb * bw + wc * cw
        var share_a = wa
        var share_b = wb
        var share_c = wc
        if inv_w != 0:
            share_a = wa * aw / inv_w
            share_b = wb * bw / inv_w
            share_c = wc * cw / inv_w

        if mode == Int32(SHADE_TEXTURE):
            var u = (
                corners[unsafe_offset=base + 8] * share_a
                + corners[unsafe_offset=base + 19] * share_b
                + corners[unsafe_offset=base + 30] * share_c
            )
            var v = (
                corners[unsafe_offset=base + 9] * share_a
                + corners[unsafe_offset=base + 20] * share_b
                + corners[unsafe_offset=base + 31] * share_c
            )
            red = (
                corners[unsafe_offset=base + 4] * share_a
                + corners[unsafe_offset=base + 15] * share_b
                + corners[unsafe_offset=base + 26] * share_c
            )
            green = (
                corners[unsafe_offset=base + 5] * share_a
                + corners[unsafe_offset=base + 16] * share_b
                + corners[unsafe_offset=base + 27] * share_c
            )
            blue = (
                corners[unsafe_offset=base + 6] * share_a
                + corners[unsafe_offset=base + 17] * share_b
                + corners[unsafe_offset=base + 28] * share_c
            )
            alpha = (
                corners[unsafe_offset=base + 7] * share_a
                + corners[unsafe_offset=base + 18] * share_b
                + corners[unsafe_offset=base + 29] * share_c
            )
            # Which image, from the vertex; -1 is no texture, which samples
            # as white and so leaves the lighting alone.
            var slot = Int(corners[unsafe_offset=base + 10])
            if slot != NO_TEXTURE:
                # Every texture lives in one buffer end to end, so the table
                # says where this one starts and how to read it.
                var entry = slot * TABLE_COLUMNS
                var start = Int(table[unsafe_offset=entry])
                var width = Int(table[unsafe_offset=entry + 1])
                var height = Int(table[unsafe_offset=entry + 2])
                var wrap = Int(table[unsafe_offset=entry + 3])
                var filter = Int(table[unsafe_offset=entry + 4])
                # v flipped and wrapped by the same routine the host uses,
                # and blended by the same one -- see render.texture.
                var sampled = FloatColor(1, 1, 1, 1)
                if filter == NEAREST:
                    sampled = _fetch(
                        texels,
                        start,
                        Int(floor(u * Float32(width))),
                        Int(floor((1 - v) * Float32(height))),
                        width,
                        height,
                        wrap,
                    )
                else:
                    # Texel centres sit at half-integers; see Texture.sample.
                    var across = u * Float32(width) - 0.5
                    var down = (1 - v) * Float32(height) - 0.5
                    var column = Int(floor(across))
                    var row = Int(floor(down))
                    sampled = blend(
                        _fetch(
                            texels,
                            start,
                            column,
                            row,
                            width,
                            height,
                            wrap,
                        ),
                        _fetch(
                            texels,
                            start,
                            column + 1,
                            row,
                            width,
                            height,
                            wrap,
                        ),
                        _fetch(
                            texels,
                            start,
                            column,
                            row + 1,
                            width,
                            height,
                            wrap,
                        ),
                        _fetch(
                            texels,
                            start,
                            column + 1,
                            row + 1,
                            width,
                            height,
                            wrap,
                        ),
                        across - Float32(column),
                        down - Float32(row),
                    )
                red *= sampled.r
                green *= sampled.g
                blue *= sampled.b
                alpha *= sampled.a
        elif mode == Int32(SHADE_UV):
            # Texture coordinates straight out as red and green, matching
            # rasterize_shaded's SHADE_UV.
            red = (
                corners[unsafe_offset=base + 8] * share_a
                + corners[unsafe_offset=base + 19] * share_b
                + corners[unsafe_offset=base + 30] * share_c
            )
            green = (
                corners[unsafe_offset=base + 9] * share_a
                + corners[unsafe_offset=base + 20] * share_b
                + corners[unsafe_offset=base + 31] * share_c
            )
            blue = 0
            alpha = 1
        else:
            red = (
                corners[unsafe_offset=base + 4] * share_a
                + corners[unsafe_offset=base + 15] * share_b
                + corners[unsafe_offset=base + 26] * share_c
            )
            green = (
                corners[unsafe_offset=base + 5] * share_a
                + corners[unsafe_offset=base + 16] * share_b
                + corners[unsafe_offset=base + 27] * share_c
            )
            blue = (
                corners[unsafe_offset=base + 6] * share_a
                + corners[unsafe_offset=base + 17] * share_b
                + corners[unsafe_offset=base + 28] * share_c
            )
            alpha = (
                corners[unsafe_offset=base + 7] * share_a
                + corners[unsafe_offset=base + 18] * share_b
                + corners[unsafe_offset=base + 29] * share_c
            )

    var word = background
    var nearest_depth = inf[DType.float32]()
    if found:
        word = pack(FloatColor(red, green, blue, alpha).quantize())
        nearest_depth = nearest

    # Every pixel is written, background included. Clearing on the host and
    # uploading that buffer would cost more than the render; letting each
    # thread decide its own colour costs nothing.
    var slot = y * Int(width) + x
    # The depth this thread settled on, written out rather than discarded.
    # A framebuffer that reports infinity everywhere would let a later
    # depth-tested triangle paint over a nearer surface already drawn here.
    depth[unsafe_offset=slot] = nearest_depth

    var offset = slot * 4
    pixels[unsafe_offset=offset] = UInt8((word >> 24) & 0xFF)
    pixels[unsafe_offset=offset + 1] = UInt8((word >> 16) & 0xFF)
    pixels[unsafe_offset=offset + 2] = UInt8((word >> 8) & 0xFF)
    pixels[unsafe_offset=offset + 3] = UInt8(word & 0xFF)


struct GpuRenderer(Movable):
    """A GPU rasterizer that keeps its device context and buffers.

    Creating a `DeviceContext` and allocating a render target are not cheap,
    and an animation does the same draw hundreds of times at the same size.
    Holding them here means a frame costs an upload, a launch and a readback
    rather than a fresh allocation of everything.

    Reading the image back is a separate call, because it is a separate cost:
    a pipeline that draws several times before showing anything should pay it
    once, not once per draw.
    """

    var width: Int
    var height: Int
    # How many triangles the vertex buffer can currently hold.
    var capacity: Int
    # False until the first successful `draw`, so `read_back` cannot hand
    # back whatever the allocation happened to contain.
    var drawn: Bool
    var context: DeviceContext
    var pixels: DeviceBuffer[DType.uint8]
    var depth: DeviceBuffer[DType.float32]
    var corners: DeviceBuffer[DType.float32]
    # Every texture the scene can sample, uploaded once rather than per draw.
    var texels: DeviceBuffer[DType.uint8]
    var table: DeviceBuffer[DType.int32]
    # How many descriptors the table actually holds. The kernel indexes it
    # with a number that arrived on a vertex, so something has to know where
    # the table ends; nothing on the device can find out.
    var uploaded: Int

    def __init__(out self, width: Int, height: Int) raises:
        """Create a renderer and its device buffers for a fixed image size.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.

        Raises:
            Error: If the dimensions are not positive, or no GPU is present.
        """
        if width <= 0 or height <= 0:
            raise Error("Framebuffer dimensions must be positive")
        if not available():
            raise Error("No GPU available")
        self.width = width
        self.height = height
        self.drawn = False
        self.context = DeviceContext()
        self.pixels = self.context.enqueue_create_buffer[DType.uint8](
            width * height * Framebuffer.CHANNELS
        )
        self.depth = self.context.enqueue_create_buffer[DType.float32](
            width * height
        )
        # One triangle to start with; `draw` grows it as needed. Never zero,
        # because a zero-length device buffer is not worth the special case.
        self.capacity = 1
        self.corners = self.context.enqueue_create_buffer[DType.float32](
            FLOATS_PER_TRIANGLE
        )
        # One texel's worth, standing in for the blank texture. A zero-length
        # device buffer is not worth the special case, and a width of zero is
        # what the kernel actually reads to mean "no texture".
        self.texels = self.context.enqueue_create_buffer[DType.uint8](4)
        self.table = self.context.enqueue_create_buffer[DType.int32](
            TABLE_COLUMNS
        )
        # Allocated but never filled, so until `set_textures` runs the only
        # legal reference is NO_TEXTURE.
        self.uploaded = 0

    def draw(
        mut self,
        corners: List[RasterVertex],
        background: Color,
        mode: Int = SHADE_LIT,
    ) raises:
        """Rasterize prepared triangles into the device render target.

        Args:
            corners: Raster vertices, three per triangle. An empty list is
                allowed and clears the target to `background`.
            background: Colour for pixels no triangle covers.
            mode: `SHADE_LIT` or `SHADE_UV`, as `rasterize_shaded` takes.

        Raises:
            Error: If the corner count is not a multiple of three, the mode is
                unknown, or a vertex names a texture that is not uploaded.
        """
        if len(corners) % 3 != 0:
            raise Error("Rasterizing needs whole triangles")
        if mode != SHADE_LIT and mode != SHADE_UV and mode != SHADE_TEXTURE:
            raise Error("Unknown shading mode")
        var triangles = len(corners) // 3

        # Every texture reference is checked here because it cannot be checked
        # on the device: the kernel reads the descriptor table at whatever
        # index a vertex hands it, and an index past the end is an unchecked
        # read of device memory. The CPU rasterizer gets this for free from
        # `TextureStore.get`, which raises; without this the two backends
        # failed differently on the same bad input.
        for index in range(len(corners)):
            var slot = corners[index].texture
            if slot == NO_TEXTURE:
                continue
            if slot < 0 or slot >= self.uploaded:
                raise Error(
                    "A vertex names a texture that has not been uploaded;"
                    " call set_textures() first"
                )
            # Ids cross to the device as Float32, which represents every
            # integer exactly only up to 2^24. Far beyond any real scene, and
            # cheap to refuse rather than silently round.
            if slot > 16777215:
                raise Error("Too many textures for the device layout")

        if triangles > self.capacity:
            # Grow to exactly what is asked for. Frames tend to submit the
            # same count repeatedly, so this settles after the first one.
            self.corners = self.context.enqueue_create_buffer[DType.float32](
                triangles * FLOATS_PER_TRIANGLE
            )
            self.capacity = triangles

        if triangles > 0:
            var flat = flatten(corners)
            with self.corners.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=flat.unsafe_ptr(),
                    count=len(flat),
                )

        self.context.enqueue_function[rasterize_kernel](
            self.pixels.unsafe_ptr(),
            self.depth.unsafe_ptr(),
            self.corners.unsafe_ptr(),
            Int32(triangles),
            Int32(self.width),
            Int32(self.height),
            pack(background),
            Int32(mode),
            self.texels.unsafe_ptr(),
            self.table.unsafe_ptr(),
            grid_dim=(
                ceildiv(self.width, TILE),
                ceildiv(self.height, TILE),
            ),
            block_dim=(TILE, TILE),
        )
        self.drawn = True

    def set_textures(mut self, textures: TextureStore) raises:
        """Upload every texture in `textures`, replacing any previous set.

        Separate from `draw` on purpose: an animation samples the same images
        every frame, and re-uploading them each time would cost more than the
        rasterization does.

        Args:
            textures: The store to upload. An empty one is allowed and means
                no mesh can be textured.

        Raises:
            Error: If the device buffers cannot be filled.
        """
        var flattened = flatten_textures(textures)
        ref bytes = flattened[0]
        ref rows = flattened[1]

        self.texels = self.context.enqueue_create_buffer[DType.uint8](
            len(bytes)
        )
        with self.texels.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=bytes.unsafe_ptr(),
                count=len(bytes),
            )
        self.table = self.context.enqueue_create_buffer[DType.int32](len(rows))
        with self.table.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=rows.unsafe_ptr(),
                count=len(rows),
            )
        # Set last, so a failed upload leaves the previous count rather than
        # advertising descriptors that are not there.
        self.uploaded = textures.count()

    def read_back(self) raises -> Framebuffer:
        """Copy the device render target into a host framebuffer.

        Both the colour and the depth come back, so the result is the same
        kind of thing the CPU renderer produces and can be drawn into again.

        Returns:
            The rendered image, with its depth buffer.

        Raises:
            Error: If nothing has been drawn yet, or the framebuffer cannot
                be built from the bytes.
        """
        if not self.drawn:
            raise Error(
                "Nothing has been drawn yet; call draw() before read_back()"
            )
        var count = self.width * self.height * Framebuffer.CHANNELS
        var pixels = List[UInt8](length=count, fill=0)
        with self.pixels.map_to_host() as host:
            # One bulk copy, not a loop. Copying byte by byte here costs more
            # than the kernel does by an order of magnitude and dominates the
            # render.
            unsafe_memcpy(
                dest=pixels.unsafe_ptr(), src=host.unsafe_ptr(), count=count
            )
        var depth = List[Float32](
            length=self.width * self.height, fill=inf[DType.float32]()
        )
        with self.depth.map_to_host() as host:
            unsafe_memcpy(
                dest=depth.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=self.width * self.height,
            )
        return Framebuffer(self.width, self.height, pixels^, depth^)


def render_triangles(
    corners: List[RasterVertex],
    width: Int,
    height: Int,
    background: Color,
    mode: Int = SHADE_LIT,
    textures: TextureStore = TextureStore(),
) raises -> Framebuffer:
    """Draw prepared triangles on the GPU and read the image back.

    A convenience for one-shot renders. Anything drawing repeatedly should
    hold a `GpuRenderer` instead, so the context and buffers survive between
    frames rather than being rebuilt for each one.

    Args:
        corners: Raster vertices, three per triangle.
        width: Image width in pixels.
        height: Image height in pixels.
        background: Colour for pixels no triangle covers.
        mode: `SHADE_LIT`, `SHADE_UV` or `SHADE_TEXTURE`.
        textures: The images `SHADE_TEXTURE` samples, named per vertex.

    Returns:
        The rendered image.

    Raises:
        Error: If the dimensions are invalid, no GPU is present, or the
            corner count is not a multiple of three.
    """
    var renderer = GpuRenderer(width, height)
    renderer.set_textures(textures)
    renderer.draw(corners, background, mode)
    return renderer.read_back()


def render(
    triangle: Triangle,
    width: Int,
    height: Int,
    background: Color,
    foreground: Color,
) raises -> Framebuffer:
    """Rasterize one flat triangle on the GPU, in a single colour.

    The shape the benchmark and the parity tests use. Depth and perspective
    are neutral here — one triangle at a constant depth with no perspective —
    so this measures coverage and nothing else.

    Args:
        triangle: Screen-space triangle to fill.
        width: Image width in pixels.
        height: Image height in pixels.
        background: Colour for pixels the triangle does not cover.
        foreground: Colour for pixels it does.

    Returns:
        A framebuffer holding the rendered image.

    Raises:
        Error: If the dimensions are not positive, or no GPU is present.
    """
    var tint = FloatColor(of=foreground)
    var corners = List[RasterVertex]()
    corners.append(RasterVertex(triangle.a.x, triangle.a.y, 0, 1, tint, 0, 0))
    corners.append(RasterVertex(triangle.b.x, triangle.b.y, 0, 1, tint, 0, 0))
    corners.append(RasterVertex(triangle.c.x, triangle.c.y, 0, 1, tint, 0, 0))
    return render_triangles(corners^, width, height, background)
