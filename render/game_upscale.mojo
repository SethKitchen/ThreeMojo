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
from render.game_sharpen import MOST_WEIGHT, sharpen_row
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


@always_inline
def _blend_row(
    rows: Pointer[Float32, ImmutAnyOrigin],
    channels: Int,
    lines: Pointer[Int, ImmutAnyOrigin],
    shares: Pointer[Float32, ImmutAnyOrigin],
    y: Int,
    dest: MutPointer[UInt8, MutAnyOrigin],
):
    """Write window row `y`: the mix of the four stretched rows nearest
    it."""
    comptime F = SIMD[DType.float32, GAME_LANES]
    var r0 = rows.unsafe_offset(lines[unsafe_offset=y * 4] * channels)
    var r1 = rows.unsafe_offset(lines[unsafe_offset=y * 4 + 1] * channels)
    var r2 = rows.unsafe_offset(lines[unsafe_offset=y * 4 + 2] * channels)
    var r3 = rows.unsafe_offset(lines[unsafe_offset=y * 4 + 3] * channels)
    var w0 = shares[unsafe_offset=y * 4]
    var w1 = shares[unsafe_offset=y * 4 + 1]
    var w2 = shares[unsafe_offset=y * 4 + 2]
    var w3 = shares[unsafe_offset=y * 4 + 3]
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


@always_inline
def _copy_bytes(
    source: Pointer[UInt8, ImmutAnyOrigin],
    dest: MutPointer[UInt8, MutAnyOrigin],
    count: Int,
):
    """Copy `count` bytes."""
    var k = 0
    while k + GAME_LANES <= count:
        dest.unsafe_store(k, source.unsafe_load[width=GAME_LANES](k))
        k += GAME_LANES
    while k < count:
        dest[unsafe_offset=k] = source[unsafe_offset=k]
        k += 1


__async def _down_task(
    rows: Pointer[Float32, ImmutAnyOrigin],
    target_width: Int,
    target_height: Int,
    lines: Pointer[Int, ImmutAnyOrigin],
    shares: Pointer[Float32, ImmutAnyOrigin],
    peak: Float32,
    target: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Fill window rows `first` to `past` from the stretched rows, and
    sharpen them by `peak` if it is not zero.

    To sharpen, the task stretches its rows and one more above and below
    into a band of its own, and sharpens from the band into the window.
    So the window is written once, and no copy of it is made."""
    var channels = target_width * 4
    if peak == 0:
        for y in range(first, past):  # pragma: no branch
            _blend_row(
                rows,
                channels,
                lines,
                shares,
                y,
                target.unsafe_offset(y * channels),
            )
        return
    var low = max(0, first - 1)
    var high = min(target_height, past + 1)
    var band = List[UInt8]()
    band.resize(unsafe_uninit_length=(high - low) * channels)
    var held = band.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    for y in range(low, high):  # pragma: no branch
        _blend_row(
            rows,
            channels,
            lines,
            shares,
            y,
            held.unsafe_offset((y - low) * channels),
        )
    var read = held.unsafe_mut_cast[False]().unsafe_origin_cast[
        ImmutAnyOrigin
    ]()
    var edge = target_height - 1
    for y in range(first, past):  # pragma: no branch
        var row = read.unsafe_offset((y - low) * channels)
        var dest = target.unsafe_offset(y * channels)
        # The border's rows and pixels are kept as stretched.
        if y == 0 or y == edge or target_width < 3:
            _copy_bytes(row, dest, channels)
            continue
        sharpen_row(
            row,
            row.unsafe_offset(-channels),
            row.unsafe_offset(channels),
            dest,
            target_width,
            peak,
        )
        _copy_bytes(row, dest, 4)
        _copy_bytes(
            row.unsafe_offset(channels - 4), dest.unsafe_offset(channels - 4), 4
        )
    _ = len(band)


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
    frame: Framebuffer,
    mut target: Framebuffer,
    workers: Int,
    sharpness: Float32 = 0,
) raises:
    """Stretch a frame over another frame's pixels, by the Catmull-Rom
    cubic, and sharpen it as it is written.

    A game keeps one window-sized frame and stretches each small frame
    over it. This does not allocate the window's eight megabytes again
    each frame. The target's depth is not changed. With a sharpness, the
    frame is the one that the stretch and then
    `render.game_sharpen.sharpen` give, to the byte, in one pass over the
    window.

    Args:
        frame: The small frame.
        target: The window-sized frame. Its pixels are written.
        workers: How many tasks share each pass; at least one.
        sharpness: How strongly to sharpen, from 0 to 1; 0 leaves the
            stretch as it is.

    Raises:
        Error: If the target's pixels do not match its size, or the
            sharpness is not from 0 to 1.
    """
    var width = target.width
    var height = target.height
    if len(target.pixels) != width * height * 4:
        raise Error("An upscale target's pixels must match its size")
    if not (sharpness >= 0 and sharpness <= 1):
        raise Error("A sharpening strength must be from 0 to 1")
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
                height,
                down[0]
                .unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                down[1]
                .unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                MOST_WEIGHT * sharpness,
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
