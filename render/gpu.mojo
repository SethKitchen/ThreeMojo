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
from render.rasterizer import RasterVertex, Triangle
from std.gpu import global_idx
from std.math import ceildiv, inf
from std.memory import unsafe_memcpy
from std.sys import has_accelerator

# 16x16 threads is a conventional starting point for a 2D grid: a multiple of
# the warp size on every vendor, and small enough that a narrow image still
# fills several blocks.
comptime TILE = 16

# How a `RasterVertex` is laid out in the flat float buffer the kernel reads:
# x, y, z, inv_w, r, g, b, a. A struct would be tidier and is not an option —
# the buffer has to be plain floats to cross to the device.
comptime FLOATS_PER_VERTEX = 8
comptime FLOATS_PER_TRIANGLE = FLOATS_PER_VERTEX * 3

# Further than any NDC depth, so the first covering triangle always wins. The
# host framebuffer uses an actual infinity; a literal keeps the kernel free of
# any dependency on how the host spells one.
comptime FURTHEST = Float32(1.0e30)


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
        Eight floats per vertex, in the order the kernel unpacks them.
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
    return flat^


def rasterize_kernel(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    corners: MutPointer[Float32, MutAnyOrigin],
    triangles: Int32,
    width: Int32,
    height: Int32,
    background: UInt32,
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
        var bx = corners[unsafe_offset=base + 8]
        var by = corners[unsafe_offset=base + 9]
        var bz = corners[unsafe_offset=base + 10]
        var bw = corners[unsafe_offset=base + 11]
        var cx = corners[unsafe_offset=base + 16]
        var cy = corners[unsafe_offset=base + 17]
        var cz = corners[unsafe_offset=base + 18]
        var cw = corners[unsafe_offset=base + 19]

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

        red = (
            corners[unsafe_offset=base + 4] * share_a
            + corners[unsafe_offset=base + 12] * share_b
            + corners[unsafe_offset=base + 20] * share_c
        )
        green = (
            corners[unsafe_offset=base + 5] * share_a
            + corners[unsafe_offset=base + 13] * share_b
            + corners[unsafe_offset=base + 21] * share_c
        )
        blue = (
            corners[unsafe_offset=base + 6] * share_a
            + corners[unsafe_offset=base + 14] * share_b
            + corners[unsafe_offset=base + 22] * share_c
        )
        alpha = (
            corners[unsafe_offset=base + 7] * share_a
            + corners[unsafe_offset=base + 15] * share_b
            + corners[unsafe_offset=base + 23] * share_c
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

    def draw(mut self, corners: List[RasterVertex], background: Color) raises:
        """Rasterize prepared triangles into the device render target.

        Args:
            corners: Raster vertices, three per triangle. An empty list is
                allowed and clears the target to `background`.
            background: Colour for pixels no triangle covers.

        Raises:
            Error: If the corner count is not a multiple of three.
        """
        if len(corners) % 3 != 0:
            raise Error("Rasterizing needs whole triangles")
        var triangles = len(corners) // 3

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
            grid_dim=(
                ceildiv(self.width, TILE),
                ceildiv(self.height, TILE),
            ),
            block_dim=(TILE, TILE),
        )
        self.drawn = True

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

    Returns:
        The rendered image.

    Raises:
        Error: If the dimensions are invalid, no GPU is present, or the
            corner count is not a multiple of three.
    """
    var renderer = GpuRenderer(width, height)
    renderer.draw(corners, background)
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
    corners.append(RasterVertex(triangle.a.x, triangle.a.y, 0, 1, tint))
    corners.append(RasterVertex(triangle.b.x, triangle.b.y, 0, 1, tint))
    corners.append(RasterVertex(triangle.c.x, triangle.c.y, 0, 1, tint))
    return render_triangles(corners^, width, height, background)
