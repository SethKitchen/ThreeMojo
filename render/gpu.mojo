# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The same triangle rasterization, one GPU thread per pixel.

`render.rasterizer` walks every pixel in a nested loop. Each iteration is
independent of every other, which is exactly the shape a GPU wants, so the
kernel below is the CPU loop body with the loop removed and the coordinates
read from the thread's position in the grid.

Two differences from the CPU path are deliberate:

* The kernel writes *every* pixel, background included, rather than only the
  covered ones. Clearing on the host and uploading that buffer would cost more
  than the render; letting each thread decide its own colour costs nothing.
* Colours cross the boundary packed into a `UInt32`. Kernel arguments must
  conform to `DevicePassable`, which rules out our `Color` struct and, less
  obviously, plain `Int` — the compiler asks for a fixed-width type instead.

Whether this is *faster* than the CPU is a separate question, and the answer
is size-dependent. `bench/raster_bench.mojo` measures where the crossover is.
"""

from math.vector2 import Vector2
from max.gpu.host import DeviceContext
from render.framebuffer import Color, Framebuffer
from render.rasterizer import Triangle
from std.gpu import global_idx
from render.rasterizer import SUBPIXEL
from std.math import ceildiv, floor
from std.memory import unsafe_memcpy
from std.sys import has_accelerator

# 16x16 threads is a conventional starting point for a 2D grid: a multiple of
# the warp size on every vendor, and small enough that a narrow image still
# fills several blocks.
comptime TILE = 16


def _snap(value: Float32) -> Int:
    """Return a screen coordinate on the subpixel grid, as an integer.

    Deliberately duplicated from `render.rasterizer` rather than imported: a
    kernel cannot call into a module that prints, and the coverage tool
    rewrites that module anyway.
    """
    return Int(floor(value * Float32(SUBPIXEL) + 0.5))


def _edge(ax: Int, ay: Int, bx: Int, by: Int, px: Int, py: Int) -> Int:
    """Return the signed twice-area of (a, b, p) on the subpixel grid."""
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax)


def _bias(ax: Int, ay: Int, bx: Int, by: Int) -> Int:
    """Return 0 if a->b is a top or left edge, -1 otherwise."""
    if ay == by:
        return 0 if bx < ax else -1
    return 0 if by < ay else -1


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


def rasterize_kernel(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    width: Int32,
    height: Int32,
    ax: Float32,
    ay: Float32,
    bx: Float32,
    by: Float32,
    cx: Float32,
    cy: Float32,
    foreground: UInt32,
    background: UInt32,
):
    """Colour one pixel according to whether it falls inside the triangle."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    # The grid is rounded up to whole tiles, so the edges overhang the image.
    if x >= Int(width) or y >= Int(height):
        return

    # Coverage is decided exactly as `render.rasterizer` decides it: vertices
    # snapped to the subpixel grid, edge functions in integers, winding
    # normalized, and the top-left rule breaking ties on shared edges. Any
    # divergence here would show up as single pixels differing between the two
    # renderers, which is precisely what tests/test_gpu.mojo asserts cannot
    # happen -- so the rule has to be the same rule, not merely a similar one.
    var sax = _snap(ax)
    var say = _snap(ay)
    var sbx = _snap(bx)
    var sby = _snap(by)
    var scx = _snap(cx)
    var scy = _snap(cy)

    var area = _edge(sax, say, sbx, sby, scx, scy)
    if area < 0:
        var tx = sbx
        var ty = sby
        sbx = scx
        sby = scy
        scx = tx
        scy = ty
        area = -area

    var inside = False
    if area != 0:
        # Sample at the pixel centre, on the same grid.
        var px = x * SUBPIXEL + SUBPIXEL // 2
        var py = y * SUBPIXEL + SUBPIXEL // 2
        var e_ab = _edge(sax, say, sbx, sby, px, py) + _bias(sax, say, sbx, sby)
        var e_bc = _edge(sbx, sby, scx, scy, px, py) + _bias(sbx, sby, scx, scy)
        var e_ca = _edge(scx, scy, sax, say, px, py) + _bias(scx, scy, sax, say)
        inside = e_ab >= 0 and e_bc >= 0 and e_ca >= 0

    var color = background
    if inside:
        color = foreground

    var offset = (y * Int(width) + x) * 4
    pixels[unsafe_offset=offset] = UInt8((color >> 24) & 0xFF)
    pixels[unsafe_offset=offset + 1] = UInt8((color >> 16) & 0xFF)
    pixels[unsafe_offset=offset + 2] = UInt8((color >> 8) & 0xFF)
    pixels[unsafe_offset=offset + 3] = UInt8(color & 0xFF)


def render(
    triangle: Triangle,
    width: Int,
    height: Int,
    background: Color,
    foreground: Color,
) raises -> Framebuffer:
    """Rasterize `triangle` on the GPU and return the finished framebuffer.

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
    if width <= 0 or height <= 0:
        raise Error("Framebuffer dimensions must be positive")
    if not available():
        raise Error("No GPU available")

    var count = width * height * Framebuffer.CHANNELS
    var ctx = DeviceContext()
    var device_pixels = ctx.enqueue_create_buffer[DType.uint8](count)

    ctx.enqueue_function[rasterize_kernel](
        device_pixels.unsafe_ptr(),
        Int32(width),
        Int32(height),
        triangle.a.x,
        triangle.a.y,
        triangle.b.x,
        triangle.b.y,
        triangle.c.x,
        triangle.c.y,
        pack(foreground),
        pack(background),
        grid_dim=(ceildiv(width, TILE), ceildiv(height, TILE)),
        block_dim=(TILE, TILE),
    )

    var pixels = List[UInt8](length=count, fill=0)
    with device_pixels.map_to_host() as host:
        # One bulk copy, not a loop. Copying byte by byte here costs more than
        # the kernel does by an order of magnitude and dominates the render.
        unsafe_memcpy(
            dest=pixels.unsafe_ptr(), src=host.unsafe_ptr(), count=count
        )
    return Framebuffer(width, height, pixels^)
