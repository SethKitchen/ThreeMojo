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
from std.math import ceildiv
from std.memory import unsafe_memcpy
from std.sys import has_accelerator

# 16x16 threads is a conventional starting point for a 2D grid: a multiple of
# the warp size on every vendor, and small enough that a narrow image still
# fills several blocks.
comptime TILE = 16


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

    # Sample at the pixel centre, matching the CPU rasterizer exactly.
    var px = Float32(x) + 0.5
    var py = Float32(y) + 0.5

    var area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    var e0 = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    var e1 = (cx - bx) * (py - by) - (cy - by) * (px - bx)
    var e2 = (ax - cx) * (py - cy) - (ay - cy) * (px - cx)

    var inside = False
    if area > 0:
        inside = e0 >= 0 and e1 >= 0 and e2 >= 0
    elif area < 0:
        inside = e0 <= 0 and e1 <= 0 and e2 <= 0

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
