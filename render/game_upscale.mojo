# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stretch a small frame to the window: bilinear, in two passes, on every
core.

A game draws at a lower resolution and stretches the frame to the window,
as FSR and DLSS do. `upscale` does it in two passes, the way a GPU's
filter is often split:

1. **Across.** Each row of the small frame is stretched to the window's
   width. There are few rows, so the gathers this needs are cheap.
2. **Down.** Each row of the window is the mix of the two stretched rows
   above and below it. Every pixel of a row mixes by the same weight, so
   this pass is a plain blend of two rows, sixteen channels at a time.

Each pixel's sample point is its center, mapped to the small frame's
pixel centers, as a GPU's bilinear filter places it. The channels are
mixed as the sRGB bytes are. The depth is not carried: compose anything
that needs it, such as water, before the frame is stretched.
"""

from render.framebuffer import Framebuffer
from render.game_math import GAME_LANES
from render.tasks import TaskGroup
from std.math import floor, max, min

comptime ROWS_A_TASK = 32
"""Rows of the window each task of the second pass fills."""


def _places(source: Int, target: Int) -> Tuple[List[Int], List[Float32]]:
    """Return, for each target pixel, the source pixel left of or above its
    sample point and the share of the next one."""
    var first = List[Int](length=target, fill=0)
    var share = List[Float32](length=target, fill=0)
    var scale = Float32(source) / Float32(target)
    for i in range(target):  # pragma: no branch
        var at = (Float32(i) + 0.5) * scale - 0.5
        var low = floor(at)
        var f = at - low
        var index = Int(low)
        if index < 0:
            index = 0
            f = 0
        if index >= source - 1:
            index = source - 1
            f = 0
        first[i] = index
        share[i] = f
    return (first^, share^)


__async def _across_task(
    pixels: Pointer[UInt8, ImmutAnyOrigin],
    width: Int,
    target_width: Int,
    columns: Pointer[Int, ImmutAnyOrigin],
    shares: Pointer[Float32, ImmutAnyOrigin],
    rows: MutPointer[Float32, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Stretch source rows `first` to `past` to the target's width."""
    for y in range(first, past):
        var source = pixels.unsafe_offset(y * width * 4)
        var line_out = rows.unsafe_offset(y * target_width * 4)
        for x in range(target_width):  # pragma: no branch
            var c = columns[unsafe_offset=x]
            var f = shares[unsafe_offset=x]
            var a = source.unsafe_offset(c * 4)
            var b = a.unsafe_offset(4 if c + 1 < width else 0)
            for ch in range(4):
                var low = Float32(a[unsafe_offset=ch])
                line_out[unsafe_offset=x * 4 + ch] = (
                    low + (Float32(b[unsafe_offset=ch]) - low) * f
                )


__async def _down_task(
    rows: Pointer[Float32, ImmutAnyOrigin],
    target_width: Int,
    lines: Pointer[Int, ImmutAnyOrigin],
    shares: Pointer[Float32, ImmutAnyOrigin],
    height: Int,
    target: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Fill window rows `first` to `past` from the stretched rows."""
    var channels = target_width * 4
    for y in range(first, past):  # pragma: no branch
        var line = lines[unsafe_offset=y]
        var f = shares[unsafe_offset=y]
        var top = rows.unsafe_offset(line * channels)
        var bottom = top.unsafe_offset(channels if line + 1 < height else 0)
        var dest = target.unsafe_offset(y * channels)
        var k = 0
        while k + GAME_LANES <= channels:
            var a = top.unsafe_load[width=GAME_LANES](k)
            var b = bottom.unsafe_load[width=GAME_LANES](k)
            var mixed = a + (b - a) * f + 0.5
            dest.unsafe_store(k, mixed.cast[DType.uint8]())
            k += GAME_LANES
        while k < channels:
            var a = top[unsafe_offset=k]
            dest[unsafe_offset=k] = UInt8(
                Int(a + (bottom[unsafe_offset=k] - a) * f + 0.5)
            )
            k += 1


def upscale(
    frame: Framebuffer, width: Int, height: Int, workers: Int
) raises -> Framebuffer:
    """Return a frame stretched to a size, bilinear.

    Args:
        frame: The small frame.
        width: The window's width, in pixels.
        height: The window's height, in pixels.
        workers: How many tasks share each pass; at least one.

    Returns:
        The stretched frame, with no depth: infinity everywhere.

    Raises:
        Error: If a size is not positive.
    """
    if width <= 0 or height <= 0:
        raise Error("An upscaled frame's size must be positive")
    var target = Framebuffer(
        width, height, List[UInt8](length=width * height * 4, fill=0)
    )
    upscale_into(frame, target, workers)
    return target^


def upscale_into(
    frame: Framebuffer, mut target: Framebuffer, workers: Int
) raises:
    """Stretch a frame over another frame's pixels, bilinear.

    A game keeps one window-sized frame and stretches each small frame
    over it. This does not allocate the window's eight megabytes again
    each frame. The target's depth is not changed.

    Args:
        frame: The small frame.
        target: The window-sized frame. Its pixels are written.
        workers: How many tasks share each pass; at least one.

    Raises:
        Error: If the target's pixels do not match its size.
    """
    var width = target.width
    var height = target.height
    if len(target.pixels) != width * height * 4:
        raise Error("An upscale target's pixels must match its size")
    var across = _places(frame.width, width)
    var down = _places(frame.height, height)
    var rows = List[Float32]()
    rows.resize(unsafe_uninit_length=frame.height * width * 4)
    var tasks = max(1, workers)
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _across_task(
                frame.pixels.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                frame.width,
                width,
                across[0]
                .unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                across[1]
                .unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                rows.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                t * frame.height // tasks,
                (t + 1) * frame.height // tasks,
            )
        )
    group.wait()
    var second = TaskGroup()
    var y = 0
    while y < height:
        var past = min(height, y + ROWS_A_TASK)
        second.create_task(
            _down_task(
                rows.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                width,
                down[0]
                .unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                down[1]
                .unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                frame.height,
                target.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                y,
                past,
            )
        )
        y = past
    second.wait()
    _ = len(rows)
    _ = len(across[0])
    _ = len(down[0])
    _ = len(frame.pixels)
