# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Smooth the edges of a game's frame, as FXAA does, on every core.

A frame drawn with one sample a pixel has stair steps along its edges,
and a frame stretched to the window makes each step larger. `smooth_edges`
finds the pixels where the brightness changes sharply, and blends each one
along its edge. It is the simplest form of NVIDIA's FXAA:

1. **Contrast.** A pixel and its four diagonal neighbors give a range of
   brightness. Where the range is less than `EDGE_LEAST`, or less than
   `EDGE_SHARE` of the brightest, the pixel keeps its color.
2. **Direction.** The edge runs across the larger change between the
   neighbors. The step along it is scaled so that its shorter part is one
   pixel, and each part is held within `SPAN_MOST` pixels.
3. **Blend.** The samples at a third and at two thirds of the step are
   averaged. The samples at its two ends are mixed in too, unless the mix
   leaves the range of brightness: then the ends crossed onto another
   surface, and the near pair is kept alone.

Each sample is bilinear between pixel centers. The brightness is the luma
of the sRGB bytes, as FXAA reads a gamma-encoded frame. Sixteen pixels of
a row are tested at once, and a run that holds an edge is blended at
once, each sample a gather of whole pixels. The rows are cut
into small runs, shared by the workers. Each run reads the frame as it was
and writes its own rows, so every count of workers gives the same frame.
"""

from render.framebuffer import Framebuffer
from render.game_math import GAME_LANES
from render.tasks import TaskGroup
from std.math import floor, max, min

comptime _F = SIMD[DType.float32, GAME_LANES]
comptime _I = SIMD[DType.int32, GAME_LANES]

comptime EDGE_LEAST = Float32(0.0833)
"""The least range of brightness, from 0 to 1, that marks an edge."""
comptime EDGE_SHARE = Float32(0.166)
"""The least range of brightness, as a share of the brightest, that marks
an edge."""
comptime REDUCE_SHARE = Float32(0.125)
"""The share of the neighbors' mean brightness added to the step's
shorter part before it is scaled, so a faint edge takes a short step."""
comptime REDUCE_LEAST = Float32(1.0 / 128)
"""The least that is added to the step's shorter part before it is
scaled."""
comptime SPAN_MOST = Float32(8)
"""The longest part of a step along an edge, in pixels."""
comptime RUNS_A_WORKER = 8
"""How many runs of rows each worker's share is cut into. The sky's rows
cost little and the grass's rows much, so small runs balance the
workers."""


@always_inline
def _luma(pixels: Pointer[UInt8, ImmutAnyOrigin], at: Int) -> Float32:
    """Return the brightness of the pixel whose bytes start at `at`, from
    0 to 1."""
    return (
        Float32(pixels[unsafe_offset=at]) * 0.299
        + Float32(pixels[unsafe_offset=at + 1]) * 0.587
        + Float32(pixels[unsafe_offset=at + 2]) * 0.114
    ) * (1.0 / 255)


@always_inline
def _channels(
    words: Pointer[UInt32, ImmutAnyOrigin], index: SIMD[DType.int64, GAME_LANES]
) -> Tuple[_F, _F, _F]:
    """Return the red, the green and the blue of a pixel in each lane."""
    var word = words.unsafe_gather(index)
    return (
        (word & 255).cast[DType.float32](),
        ((word >> 8) & 255).cast[DType.float32](),
        ((word >> 16) & 255).cast[DType.float32](),
    )


@always_inline
def _sample(
    words: Pointer[UInt32, ImmutAnyOrigin],
    width: Int,
    height: Int,
    x: _F,
    y: _F,
) -> Tuple[_F, _F, _F]:
    """Return the frame at a point in each lane, bilinear between pixel
    centers. A pixel's center is at its index plus a half, and a place
    past the frame's edge reads the nearest pixel."""
    var fx = x - 0.5
    var fy = y - 0.5
    var x0f = floor(fx)
    var y0f = floor(fy)
    var tx = fx - x0f
    var ty = fy - y0f
    var last_x = _I(Int32(width - 1))
    var last_y = _I(Int32(height - 1))
    var x0 = x0f.cast[DType.int32]()
    var y0 = y0f.cast[DType.int32]()
    var xa = min(max(x0, _I(0)), last_x).cast[DType.int64]()
    var xb = min(max(x0 + 1, _I(0)), last_x).cast[DType.int64]()
    var ya = min(max(y0, _I(0)), last_y).cast[DType.int64]() * Int64(width)
    var yb = min(max(y0 + 1, _I(0)), last_y).cast[DType.int64]() * Int64(width)
    var a = _channels(words, ya + xa)
    var b = _channels(words, ya + xb)
    var c = _channels(words, yb + xa)
    var d = _channels(words, yb + xb)
    var red_top = a[0] + (b[0] - a[0]) * tx
    var red_bottom = c[0] + (d[0] - c[0]) * tx
    var green_top = a[1] + (b[1] - a[1]) * tx
    var green_bottom = c[1] + (d[1] - c[1]) * tx
    var blue_top = a[2] + (b[2] - a[2]) * tx
    var blue_bottom = c[2] + (d[2] - c[2]) * tx
    return (
        red_top + (red_bottom - red_top) * ty,
        green_top + (green_bottom - green_top) * ty,
        blue_top + (blue_bottom - blue_top) * ty,
    )


__async def _luma_task(
    pixels: Pointer[UInt8, ImmutAnyOrigin],
    lumas: MutPointer[Float32, MutAnyOrigin],
    width: Int,
    height: Int,
    stride: Int,
    first: Int,
    past: Int,
):
    """Find the brightness of rows `first` to `past` of the padded plane:
    its rows and columns are the frame's, one more on each side, the
    nearest pixel's past the frame's edge."""
    for row in range(first, past):
        var y = min(height - 1, max(0, row - 1))
        for column in range(stride):  # pragma: no branch
            var x = min(width - 1, max(0, column - 1))
            lumas[unsafe_offset=row * stride + column] = _luma(
                pixels, (y * width + x) * 4
            )


__async def _smooth_task(
    source: Pointer[UInt8, ImmutAnyOrigin],
    lumas: Pointer[Float32, ImmutAnyOrigin],
    target: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    height: Int,
    stride: Int,
    first: Int,
    past: Int,
):
    """Smooth rows `first` to `past` of `target` from `source`."""
    _smooth_rows(source, lumas, target, width, height, stride, first, past)


def _smooth_rows(
    source: Pointer[UInt8, ImmutAnyOrigin],
    lumas: Pointer[Float32, ImmutAnyOrigin],
    target: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    height: Int,
    stride: Int,
    first: Int,
    past: Int,
):
    """Smooth rows `first` to `past` of `target` from `source`, as
    `smooth_edges` does, sixteen pixels at a time. A pixel off an edge is
    not written. `lumas` is the padded plane of brightness, `stride`
    values a row."""
    var words = source.unsafe_bitcast[UInt32]()
    var lane = _F(0)
    for k in range(GAME_LANES):  # pragma: no branch
        lane[k] = Float32(k)
    # Each run has a row or more.
    for y in range(first, past):  # pragma: no branch
        # The padded plane's rows above, at and below this one.
        var up = lumas.unsafe_offset(y * stride)
        var at = lumas.unsafe_offset((y + 1) * stride)
        var down = lumas.unsafe_offset((y + 2) * stride)
        var cy = _F(Float32(y) + 0.5)
        for x in range(0, width, GAME_LANES):  # pragma: no branch
            var nw = up.unsafe_load[width=GAME_LANES](x)
            var ne = up.unsafe_load[width=GAME_LANES](x + 2)
            var sw = down.unsafe_load[width=GAME_LANES](x)
            var se = down.unsafe_load[width=GAME_LANES](x + 2)
            var middle = at.unsafe_load[width=GAME_LANES](x + 1)
            var low = min(middle, min(min(nw, ne), min(sw, se)))
            var high = max(middle, max(max(nw, ne), max(sw, se)))
            var edge = (high - low).ge(max(_F(EDGE_LEAST), high * EDGE_SHARE))
            edge = edge & lane.lt(Float32(width - x))
            if not edge.reduce_or():
                continue
            # Across the larger change: the edge runs that way.
            var dx = (sw + se) - (nw + ne)
            var dy = (nw + sw) - (ne + se)
            var reduce = max(
                (nw + ne + sw + se) * (0.25 * REDUCE_SHARE), _F(REDUCE_LEAST)
            )
            var scale = 1 / (min(abs(dx), abs(dy)) + reduce)
            dx = max(_F(-SPAN_MOST), min(_F(SPAN_MOST), dx * scale))
            dy = max(_F(-SPAN_MOST), min(_F(SPAN_MOST), dy * scale))
            var cx = lane + (Float32(x) + 0.5)
            var n0 = _sample(
                words, width, height, cx - dx * (1.0 / 6), cy - dy * (1.0 / 6)
            )
            var n1 = _sample(
                words, width, height, cx + dx * (1.0 / 6), cy + dy * (1.0 / 6)
            )
            var f0 = _sample(words, width, height, cx - dx * 0.5, cy - dy * 0.5)
            var f1 = _sample(words, width, height, cx + dx * 0.5, cy + dy * 0.5)
            var near_r = (n0[0] + n1[0]) * 0.5
            var near_g = (n0[1] + n1[1]) * 0.5
            var near_b = (n0[2] + n1[2]) * 0.5
            var far_r = near_r * 0.5 + (f0[0] + f1[0]) * 0.25
            var far_g = near_g * 0.5 + (f0[1] + f1[1]) * 0.25
            var far_b = near_b * 0.5 + (f0[2] + f1[2]) * 0.25
            var bright = (far_r * 0.299 + far_g * 0.587 + far_b * 0.114) * (
                1.0 / 255
            )
            # Outside the range when below its low end or above its high.
            var outside = ((bright - low) * (bright - high)).gt(0)
            var red = outside.select(near_r, far_r) + 0.5
            var green = outside.select(near_g, far_g) + 0.5
            var blue = outside.select(near_b, far_b) + 0.5
            for k in range(GAME_LANES):  # pragma: no branch
                if not edge[k]:
                    continue
                var out = target.unsafe_offset((y * width + x + k) * 4)
                out[unsafe_offset=0] = UInt8(Int(red[k]))
                out[unsafe_offset=1] = UInt8(Int(green[k]))
                out[unsafe_offset=2] = UInt8(Int(blue[k]))


def smooth_edges(mut frame: Framebuffer, workers: Int) raises:
    """Smooth the stair steps along a frame's edges, in place.

    Args:
        frame: The frame. Its colors are changed; its depth is not.
        workers: How many tasks share each pass; at least one.

    Raises:
        Error: If the frame's pixels do not match its size.
    """
    var width = frame.width
    var height = frame.height
    if len(frame.pixels) != width * height * 4:
        raise Error("A smoothed frame's pixels must match its size")
    var source = frame.pixels.copy()
    # One column more each side, and a run of lanes more at the right, so
    # every load of a row's sixteen pixels and their neighbors is whole.
    var stride = width + 2 + GAME_LANES
    var rows = height + 2
    var lumas = List[Float32]()
    lumas.resize(unsafe_uninit_length=stride * rows)
    var tasks = max(1, workers)
    var pixels = (
        source.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmutAnyOrigin]()
    )
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _luma_task(
                pixels,
                lumas.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                width,
                height,
                stride,
                t * rows // tasks,
                (t + 1) * rows // tasks,
            )
        )
    group.wait()
    var runs = min(height, tasks * RUNS_A_WORKER)
    var smoothing = TaskGroup()
    for t in range(runs):  # pragma: no branch
        smoothing.create_task(
            _smooth_task(
                pixels,
                lumas.unsafe_ptr()
                .unsafe_mut_cast[False]()
                .unsafe_origin_cast[ImmutAnyOrigin](),
                frame.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                width,
                height,
                stride,
                t * height // runs,
                (t + 1) * height // runs,
            )
        )
    smoothing.wait()
    _ = len(source)
    _ = len(lumas)
