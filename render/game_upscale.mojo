# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stretch a small frame to the window: Catmull-Rom, in two passes, on
every core.

A game draws at a lower resolution and stretches the frame to the window,
as FSR and DLSS do. A bilinear stretch mixes only the two nearest pixels,
so it smears each edge over a whole small pixel, and a moving edge looks
soft. `upscale` mixes the four nearest pixels on each axis by the
Catmull-Rom cubic. The cubic gives the far two a small negative weight,
so an edge keeps its contrast. It does it in two passes, the way a GPU's
filter is often split:

1. **Across.** Each row of the small frame is stretched to the window's
   width. There are few rows, so the gathers this needs are cheap.
2. **Down.** Each row of the window is the mix of the four stretched rows
   nearest it. Every pixel of a row mixes by the same weights, so this
   pass is a plain blend of four rows, sixteen channels at a time.

Each pixel's sample point is its center, mapped to the small frame's
pixel centers, as a GPU's filter places it. A tap past an edge reads the
edge pixel. The channels are mixed as the sRGB bytes are, and each result
is clamped to the bytes' range. The depth is not carried: compose
anything that needs it, such as water, before the frame is stretched.
"""

from render.framebuffer import Framebuffer
from render.game_math import GAME_LANES
from render.tasks import TaskGroup
from std.math import floor, max, min

comptime ROWS_A_TASK = 32
"""Rows of the window each task of the second pass fills."""


@always_inline
def _weights(t: Float32) -> SIMD[DType.float32, 4]:
    """Return the Catmull-Rom weights of the four taps around a point
    that is `t` of the way from the second tap to the third."""
    var t2 = t * t
    var t3 = t2 * t
    return SIMD[DType.float32, 4](
        -0.5 * t3 + t2 - 0.5 * t,
        1.5 * t3 - 2.5 * t2 + 1,
        -1.5 * t3 + 2 * t2 + 0.5 * t,
        0.5 * t3 - 0.5 * t2,
    )


def _places(source: Int, target: Int) -> Tuple[List[Int], List[Float32]]:
    """Return, for each target pixel, its four source taps and their
    weights: four indices, clamped to the source, and four weights."""
    var taps = List[Int](length=target * 4, fill=0)
    var weights = List[Float32](length=target * 4, fill=0)
    var scale = Float32(source) / Float32(target)
    for i in range(target):  # pragma: no branch
        var at = (Float32(i) + 0.5) * scale - 0.5
        var low = floor(at)
        var w = _weights(at - low)
        var index = Int(low)
        for k in range(4):  # pragma: no branch
            taps[i * 4 + k] = min(max(index - 1 + k, 0), source - 1)
            weights[i * 4 + k] = w[k]
    return (taps^, weights^)


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
            # A pixel's four channels mix at once, each as it would alone.
            var mixed = SIMD[DType.float32, 4](0)
            for k in range(4):  # pragma: no branch
                var c = columns[unsafe_offset=x * 4 + k]
                var tap = source.unsafe_offset(c * 4)
                mixed += (
                    tap.unsafe_load[width=4]().cast[DType.float32]()
                    * shares[unsafe_offset=x * 4 + k]
                )
            line_out.unsafe_offset(x * 4).unsafe_store(mixed)


__async def _down_task(
    rows: Pointer[Float32, ImmutAnyOrigin],
    target_width: Int,
    lines: Pointer[Int, ImmutAnyOrigin],
    shares: Pointer[Float32, ImmutAnyOrigin],
    target: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Fill window rows `first` to `past` from the stretched rows."""
    var channels = target_width * 4
    comptime F = SIMD[DType.float32, GAME_LANES]
    for y in range(first, past):  # pragma: no branch
        var r0 = rows.unsafe_offset(lines[unsafe_offset=y * 4] * channels)
        var r1 = rows.unsafe_offset(lines[unsafe_offset=y * 4 + 1] * channels)
        var r2 = rows.unsafe_offset(lines[unsafe_offset=y * 4 + 2] * channels)
        var r3 = rows.unsafe_offset(lines[unsafe_offset=y * 4 + 3] * channels)
        var w0 = shares[unsafe_offset=y * 4]
        var w1 = shares[unsafe_offset=y * 4 + 1]
        var w2 = shares[unsafe_offset=y * 4 + 2]
        var w3 = shares[unsafe_offset=y * 4 + 3]
        var dest = target.unsafe_offset(y * channels)
        var k = 0
        while k + GAME_LANES <= channels:
            var mixed = (
                r0.unsafe_load[width=GAME_LANES](k) * w0
                + r1.unsafe_load[width=GAME_LANES](k) * w1
                + r2.unsafe_load[width=GAME_LANES](k) * w2
                + r3.unsafe_load[width=GAME_LANES](k) * w3
                + 0.5
            )
            var held = min(max(mixed, F(0)), F(255.5))
            dest.unsafe_store(k, held.cast[DType.uint8]())
            k += GAME_LANES
        while k < channels:
            var mixed = (
                r0[unsafe_offset=k] * w0
                + r1[unsafe_offset=k] * w1
                + r2[unsafe_offset=k] * w2
                + r3[unsafe_offset=k] * w3
                + 0.5
            )
            dest[unsafe_offset=k] = UInt8(Int(min(max(mixed, 0), 255.5)))
            k += 1


def upscale(
    frame: Framebuffer, width: Int, height: Int, workers: Int
) raises -> Framebuffer:
    """Return a frame stretched to a size, by the Catmull-Rom cubic.

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
    """Stretch a frame over another frame's pixels, by the Catmull-Rom
    cubic.

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
