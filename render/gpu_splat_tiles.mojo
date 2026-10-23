# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gaussian splats filled on the device, a tile of the screen at a time.

`render.gpu.GpuSplats` gives each pixel a thread, and every thread walks
every splat. A scan of a building has hundreds of thousands of splats on
the screen, and a pixel is reached by a few hundred of them. This fill
sorts the splats into tiles first, `render.splat_tiles.bin_splats`, and a
thread block takes one tile. The block's 256 threads each own a pixel of
the tile. The block reads the tile's splats in batches of 256 into shared
memory, one splat to each thread, and every thread blends the batch into its
pixel, in draw order.

A pixel takes the splats that reach it, with the arithmetic of the host's
`rasterize_splats`: the opacity is `splat_alpha`, and the blend is source
over with straight alpha, each sum of products one fused multiply-add. The
picture is the host's to within a level of the 255 that a channel holds,
where the two round a product differently. `tests/test_splat_tiles_gpu.mojo`
checks it.

The target is one that nothing has been drawn into: the clear color, with
no depth. A scene with meshes in front of the splats draws on the host,
where the depth is. The picture comes back as bytes that need no
resolve, in the working space that the splats were projected for.
"""

from max.gpu import block_idx, thread_idx
from max.gpu.host import DeviceBuffer, DeviceContext
from max.gpu.memory import AddressSpace
from max.gpu.sync import barrier
from render.framebuffer import Color, Framebuffer
from render.splat_tiles import SPLAT_TILE, bin_splats, tile_count_across
from render.splatrule import (
    SPLAT_A,
    SPLAT_AXIS_X,
    SPLAT_AXIS_Y,
    SPLAT_B,
    SPLAT_DEPTH,
    SPLAT_FLOATS,
    SPLAT_G,
    SPLAT_R,
    SPLAT_SCALE1,
    SPLAT_SCALE2,
    SPLAT_X,
    SPLAT_Y,
    ProjectedSplat,
    splat_alpha,
)
from std.math import fma, max, min
from std.memory import stack_allocation, unsafe_memcpy
from std.sys import has_accelerator
from std.time import perf_counter_ns

comptime SPLAT_BATCH = SPLAT_TILE * SPLAT_TILE
"""The splats a block stages at once: one for each thread of the tile."""
comptime SPLAT_TILE_GROWTH = 2
"""How many times larger than needed a buffer is made when it must grow, so
a view that gains splats does not allocate on every frame."""

# Device memory is typed in the global address space; see `render.gpu`.
comptime DevicePointer[
    T: AnyType, origin: Origin[mut=True] = MutAnyOrigin
] = MutPointer[T, origin, address_space=AddressSpace.GLOBAL]
"""A mutable pointer into device memory, in the global address space."""


def device_pointer[
    dtype: DType
](buffer: DeviceBuffer[dtype]) -> DevicePointer[Scalar[dtype]]:
    """Return a device buffer's memory as a kernel argument.

    Args:
        buffer: The buffer.

    Returns:
        Its pointer, in the global address space.
    """
    return (
        buffer.unsafe_ptr()
        .unsafe_mut_cast[True]()
        .unsafe_origin_cast[MutAnyOrigin]()
        .unsafe_address_space_cast[AddressSpace.GLOBAL]()
    )


def _byte(value: Float32) -> UInt8:
    """Return a channel from 0 to 1 as a rounded, clamped byte, as
    `render.framebuffer` does.

    Args:
        value: The channel.

    Returns:
        The byte.
    """
    var scaled = value * 255 + 0.5
    if scaled <= 0:
        return 0
    if scaled >= 255:
        return 255
    return UInt8(scaled)


def splat_tile_kernel(
    pixels: DevicePointer[UInt8],
    splats: DevicePointer[Float32],
    starts: DevicePointer[Int32],
    items: DevicePointer[Int32],
    width: Int32,
    height: Int32,
    tiles_x: Int32,
    red: Float32,
    green: Float32,
    blue: Float32,
):
    """Fill one tile: its block blends the tile's splats into its pixels.

    Every thread must reach each barrier, so a thread outside the target
    still takes part in the loads and the barriers, and only skips the
    blend and the write.

    Args:
        pixels: The picture, four bytes a pixel, row by row.
        splats: Each projected splat's `SPLAT_FLOATS` lanes.
        starts: Where each tile's list starts in `items`, and the length.
        items: The splats of every tile, in draw order.
        width: The picture's width.
        height: The picture's height.
        tiles_x: How many tiles across.
        red: The clear color's red, from 0 to 1.
        green: Its green.
        blue: Its blue.
    """
    var staged = stack_allocation[
        SPLAT_BATCH * SPLAT_FLOATS,
        Scalar[DType.float32],
        address_space=AddressSpace.SHARED,
    ]()
    var lane = Int(thread_idx.y) * SPLAT_TILE + Int(thread_idx.x)
    var x = Int(block_idx.x) * SPLAT_TILE + Int(thread_idx.x)
    var y = Int(block_idx.y) * SPLAT_TILE + Int(thread_idx.y)
    var tile = Int(block_idx.y) * Int(tiles_x) + Int(block_idx.x)
    var at = Int(starts[unsafe_offset=tile])
    var past = Int(starts[unsafe_offset=tile + 1])
    var inside = x < Int(width) and y < Int(height)
    var r = red
    var g = green
    var b = blue
    var a = Float32(1)
    while at < past:
        var batch = min(SPLAT_BATCH, past - at)
        if lane < batch:
            var from_lane = Int(items[unsafe_offset=at + lane]) * SPLAT_FLOATS
            for k in range(SPLAT_FLOATS):
                staged[unsafe_offset=lane * SPLAT_FLOATS + k] = splats[
                    unsafe_offset=from_lane + k
                ]
        barrier()
        if inside:
            for member in range(batch):
                var s = member * SPLAT_FLOATS
                var splat = ProjectedSplat(
                    staged[unsafe_offset=s + SPLAT_X],
                    staged[unsafe_offset=s + SPLAT_Y],
                    staged[unsafe_offset=s + SPLAT_DEPTH],
                    staged[unsafe_offset=s + SPLAT_AXIS_X],
                    staged[unsafe_offset=s + SPLAT_AXIS_Y],
                    staged[unsafe_offset=s + SPLAT_SCALE1],
                    staged[unsafe_offset=s + SPLAT_SCALE2],
                    staged[unsafe_offset=s + SPLAT_R],
                    staged[unsafe_offset=s + SPLAT_G],
                    staged[unsafe_offset=s + SPLAT_B],
                    staged[unsafe_offset=s + SPLAT_A],
                )
                var alpha = splat_alpha(splat, x, y)
                if alpha > 0:
                    var share = min(max(alpha, 0), 1)
                    var keep = 1 - share
                    r = max(Float32(0), fma(splat.r, share, r * keep))
                    g = max(Float32(0), fma(splat.g, share, g * keep))
                    b = max(Float32(0), fma(splat.b, share, b * keep))
                    a = min(max(fma(a, keep, share), 0), 1)
        barrier()
        at += batch
    if inside:
        var slot = (y * Int(width) + x) * 4
        pixels[unsafe_offset=slot] = _byte(r)
        pixels[unsafe_offset=slot + 1] = _byte(g)
        pixels[unsafe_offset=slot + 2] = _byte(b)
        pixels[unsafe_offset=slot + 3] = _byte(a)


def gpu_splat_tiles_available() -> Bool:
    """Return whether this machine has a device to fill splats on.

    Returns:
        Whether an accelerator is present.
    """
    return has_accelerator()


struct GpuSplatTiles(Movable):
    """Fills projected splats into a picture on the device; see the module
    docstring.

    The buffers stay between frames and grow when a frame needs more, so a
    scene that draws every frame allocates only when it gets bigger.
    """

    # Every device buffer is declared before the context that owns it,
    # and `__deinit__` releases them first; see `GpuRenderer.__deinit__`.
    var pixels: DeviceBuffer[DType.uint8]
    var splats: DeviceBuffer[DType.float32]
    var starts: DeviceBuffer[DType.int32]
    var items: DeviceBuffer[DType.int32]
    var pixel_room: Int
    var splat_room: Int
    var tile_room: Int
    var item_room: Int
    var upload_ms: Float64
    """How long the last draw took to put the splats and the lists on the
    device, in milliseconds."""
    var kernel_ms: Float64
    """How long the last draw's kernel ran, in milliseconds."""
    var readback_ms: Float64
    """How long the last draw took to bring the picture back."""
    var context: DeviceContext

    def __deinit__(deinit self):
        """Drain the queue, release the buffers, then the context."""
        try:
            self.context.synchronize()
        except:
            pass
        _ = self.pixels^
        _ = self.splats^
        _ = self.starts^
        _ = self.items^
        _ = self.context^

    def __init__(out self) raises:
        """Open the device.

        Raises:
            Error: If no GPU is present.
        """
        if not has_accelerator():
            raise Error("No GPU available")
        self.context = DeviceContext()
        self.pixels = self.context.enqueue_create_buffer[DType.uint8](4)
        self.splats = self.context.enqueue_create_buffer[DType.float32](4)
        self.starts = self.context.enqueue_create_buffer[DType.int32](4)
        self.items = self.context.enqueue_create_buffer[DType.int32](4)
        self.pixel_room = 4
        self.splat_room = 4
        self.tile_room = 4
        self.item_room = 4
        self.upload_ms = 0
        self.kernel_ms = 0
        self.readback_ms = 0

    def draw(
        mut self,
        splats: List[ProjectedSplat],
        width: Int,
        height: Int,
        background: Color,
        workers: Int = 1,
    ) raises -> Framebuffer:
        """Fill projected splats into a picture.

        Args:
            splats: The splats, in the order to draw them, from
                `render.splat_lod.prepare_splat_lod` or
                `render.splat_raster.prepare_gaussian_splat`.
            width: The picture's width, in pixels, 1 or more.
            height: The picture's height, in pixels, 1 or more.
            background: The color to clear to. It must be opaque.
            workers: How many threads sort the splats into tiles.

        Returns:
            The picture, with the splats blended over the background.

        Raises:
            Error: If the size is not valid, the background is not
                opaque, or the lists of tiles are too long.
        """
        if background.a != 255:
            raise Error("A GPU splat fill needs an opaque background")
        var tiles = bin_splats(splats, width, height, workers)
        var pixels = width * height * 4
        var floats = len(splats) * SPLAT_FLOATS
        # A launch in flight may still read the old buffers.
        self.context.synchronize()
        if pixels > self.pixel_room:
            self.pixel_room = pixels * SPLAT_TILE_GROWTH
            self.pixels = self.context.enqueue_create_buffer[DType.uint8](
                self.pixel_room
            )
        if floats > self.splat_room:
            self.splat_room = floats * SPLAT_TILE_GROWTH
            self.splats = self.context.enqueue_create_buffer[DType.float32](
                self.splat_room
            )
        if len(tiles.starts) > self.tile_room:
            self.tile_room = len(tiles.starts) * SPLAT_TILE_GROWTH
            self.starts = self.context.enqueue_create_buffer[DType.int32](
                self.tile_room
            )
        if len(tiles.items) > self.item_room:
            self.item_room = len(tiles.items) * SPLAT_TILE_GROWTH
            self.items = self.context.enqueue_create_buffer[DType.int32](
                self.item_room
            )
        var began = perf_counter_ns()
        if floats > 0:
            with self.splats.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=splats.unsafe_ptr().unsafe_bitcast[Float32](),
                    count=floats,
                )
        with self.starts.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=tiles.starts.unsafe_ptr(),
                count=len(tiles.starts),
            )
        if len(tiles.items) > 0:
            with self.items.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=tiles.items.unsafe_ptr(),
                    count=len(tiles.items),
                )
        self.upload_ms = Float64(perf_counter_ns() - began) / 1e6
        began = perf_counter_ns()
        self.context.enqueue_function[splat_tile_kernel](
            device_pointer(self.pixels),
            device_pointer(self.splats),
            device_pointer(self.starts),
            device_pointer(self.items),
            Int32(width),
            Int32(height),
            Int32(tiles.tiles_x),
            Float32(background.r) / 255,
            Float32(background.g) / 255,
            Float32(background.b) / 255,
            grid_dim=(tile_count_across(width), tile_count_across(height)),
            block_dim=(SPLAT_TILE, SPLAT_TILE),
        )
        self.context.synchronize()
        self.kernel_ms = Float64(perf_counter_ns() - began) / 1e6
        began = perf_counter_ns()
        var picture = List[UInt8](length=pixels, fill=0)
        with self.pixels.map_to_host() as host:
            unsafe_memcpy(
                dest=picture.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=pixels,
            )
        self.readback_ms = Float64(perf_counter_ns() - began) / 1e6
        return Framebuffer(width, height, picture^)
