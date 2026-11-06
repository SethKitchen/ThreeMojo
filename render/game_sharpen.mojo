# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sharpen a stretched frame by contrast-adaptive sharpening, on every core.

A frame drawn small and stretched to the window is soft. `sharpen` gives
back some of the contrast that the stretch took, the way AMD's CAS and
the last pass of FSR do:

1. Each pixel and its four neighbors across and down give each channel's
   least and greatest value.
2. The room to sharpen is the distance from those values to black or to
   white, as a share of the greatest. A flat area has much room; an edge
   that is already hard has little. The square root of that share is the
   amount.
3. The pixel takes its neighbors away by a weight that the amount and the
   strength set, and the result is divided by the weights' sum. So a flat
   area does not change, and the result does not ring past the
   neighborhood's own range.

The channels are sharpened as the sRGB bytes are, so the pass costs a
read of five pixels and a few multiplications a channel. The border's
pixels are kept. Each task reads a copy of the frame and writes its own
rows of 32, so the result does not depend on how the tasks run.
"""

from render.framebuffer import Framebuffer
from render.game_math import GAME_LANES
from render.tasks import TaskGroup
from std.math import max, min, sqrt

comptime ROWS_A_TASK = 32
"""Rows of the frame each task fills."""
comptime MOST_WEIGHT = Float32(-1.0 / 5)
"""The neighbors' weight at a strength of 1: the strongest that keeps the
weights' sum positive with room to spare."""


@always_inline
def sharpen_row(
    row: Pointer[UInt8, ImmutAnyOrigin],
    up: Pointer[UInt8, ImmutAnyOrigin],
    down: Pointer[UInt8, ImmutAnyOrigin],
    dest: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    peak: Float32,
):
    """Sharpen one row of pixels inside its first and last pixel.

    The first and the last pixel of `dest` are not written.

    Args:
        row: The row's bytes, four a pixel.
        up: The bytes of the row above it.
        down: The bytes of the row below it.
        dest: Where the sharpened row's bytes go.
        width: The row's pixels.
        peak: The neighbors' weight at full room: `MOST_WEIGHT` times the
            strength.
    """
    comptime F = SIMD[DType.float32, GAME_LANES]
    var last = width * 4 - 4
    var k = 4
    while k + GAME_LANES <= last:
        var c = row.unsafe_load[width=GAME_LANES](k).cast[DType.float32]()
        var w = row.unsafe_load[width=GAME_LANES](k - 4).cast[DType.float32]()
        var e = row.unsafe_load[width=GAME_LANES](k + 4).cast[DType.float32]()
        var n = up.unsafe_load[width=GAME_LANES](k).cast[DType.float32]()
        var s = down.unsafe_load[width=GAME_LANES](k).cast[DType.float32]()
        var low = min(min(min(c, w), min(e, n)), s)
        var high = max(max(max(c, w), max(e, n)), s)
        var room = min(low, F(255) - high) / max(high, F(1))
        var amount = sqrt(min(max(room, F(0)), F(1)))
        var weight = amount * peak
        var mixed = (c + (w + e + n + s) * weight) / (weight * 4 + 1)
        var held = min(max(mixed + 0.5, F(0)), F(255.5))
        dest.unsafe_store(k, held.cast[DType.uint8]())
        k += GAME_LANES
    while k < last:
        var c = Float32(row[unsafe_offset=k])
        var w = Float32(row[unsafe_offset=k - 4])
        var e = Float32(row[unsafe_offset=k + 4])
        var n = Float32(up[unsafe_offset=k])
        var s = Float32(down[unsafe_offset=k])
        var low = min(min(min(c, w), min(e, n)), s)
        var high = max(max(max(c, w), max(e, n)), s)
        var room = min(low, 255 - high) / max(high, 1)
        var amount = sqrt(min(max(room, 0), 1))
        var weight = amount * peak
        var mixed = (c + (w + e + n + s) * weight) / (weight * 4 + 1)
        dest[unsafe_offset=k] = UInt8(Int(min(max(mixed + 0.5, 0), 255.5)))
        k += 1


__async def _sharpen_task(
    source: Pointer[UInt8, ImmutAnyOrigin],
    width: Int,
    peak: Float32,
    target: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Sharpen rows `first` to `past`, inside the border."""
    var stride = width * 4
    for y in range(first, past):  # pragma: no branch
        sharpen_row(
            source.unsafe_offset(y * stride),
            source.unsafe_offset((y - 1) * stride),
            source.unsafe_offset((y + 1) * stride),
            target.unsafe_offset(y * stride),
            width,
            peak,
        )


def sharpen(mut frame: Framebuffer, strength: Float32) raises:
    """Sharpen a frame in place by contrast-adaptive sharpening.

    Args:
        frame: The frame. Its pixels are written; its depth is not.
        strength: How strongly to sharpen, from 0 to 1. At 0 the frame
            does not change.

    Raises:
        Error: If the strength is not from 0 to 1, or the frame's pixels
            do not match its size.
    """
    if not (strength >= 0 and strength <= 1):
        raise Error("A sharpening strength must be from 0 to 1")
    var width = frame.width
    var height = frame.height
    if len(frame.pixels) != width * height * 4:
        raise Error("A sharpened frame's pixels must match its size")
    if width < 3 or height < 3 or strength == 0:
        return
    var peak = MOST_WEIGHT * strength
    var source = frame.pixels.copy()
    var group = TaskGroup()
    var y = 1
    while y < height - 1:
        var past = min(height - 1, y + ROWS_A_TASK)
        group.create_task(
            _sharpen_task(
                source.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                width,
                peak,
                frame.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                y,
                past,
            )
        )
        y = past
    group.wait()
    _ = len(source)
