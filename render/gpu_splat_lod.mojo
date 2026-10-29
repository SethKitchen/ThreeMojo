# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scan with levels of detail, drawn on the device, with the scan kept
there.

`render.splat_lod.draw_splat_lod` selects, projects, sorts and fills on the
host. On a scan of a building at 1920 by 1080 that is 46 milliseconds a frame
on 24 threads, 29 of them the fill. `render.gpu_splat_tiles` fills in 4
milliseconds, but its input is the host's 850,000 projected splats, and
sending them costs more than they save. This module moves the rest.

The scan's splats, the tree's own and its merged ones, go to the device once,
in `GpuSplatScene`. A frame then sends only the splats that the host's walk
of the tree selected, as places: 4 bytes each. The device does the rest, in
eight launches.

1. **Project.** One thread to each selected splat shades it with its
   spherical harmonics and projects it, as `render.splatrule.project_splat`
   does, and finds its depth bin, as `render.splat_lod` does. All the
   arithmetic on the device is 32-bit, so that a GPU without 64-bit floats
   runs it.
2. **Sort by depth.** A counting sort of the bins, in runs of the selection.
   Each run counts its splats in each bin, the runs' counts are summed bin by
   bin, and each run places its splats after the earlier runs' splats in
   each bin. So the splats of a bin keep the order of the tree. A splat that
   lies on the edge of a bin can fall in the next one, where the host's
   64-bit arithmetic puts it in this.
3. **Sort into tiles.** The same counting sort, of the sorted splats into
   the tiles that `render.splat_tiles.splat_tile_box` says they reach. So
   each tile's list is in draw order too.
4. **Fill.** `render.gpu_splat_tiles.splat_tile_kernel`.

The one thing the host reads in the middle of a frame is the length of the
tile lists, so that the list buffer is big enough.

The picture can differ from the host's by a level of the 255 that a channel
holds, where the device fuses a product that the host does not.
"""

from cameras.camera import Camera
from core.scene import Scene
from math.vector3 import Vector3
from max.gpu import block_dim, block_idx, thread_idx
from max.gpu.host import DeviceBuffer, DeviceContext, HostBuffer
from max.gpu.sync import barrier
from max.gpu.memory import AddressSpace
from objects.gaussian_splat import BIN_COUNT, MIN_SORT_RANGE
from render.framebuffer import Color, Framebuffer
from render.gpu_splat_tiles import (
    DevicePointer,
    device_pointer,
    splat_tile_kernel,
)
from render.raster_state import DepthMode, STANDARD_DEPTH, log_depth_factor
from render.rect import Rect
from render.splat_harmonics import sh_weights
from render.splat_lod import LOD_PIXELS, SplatLod, select_splats
from render.splat_tiles import SPLAT_TILE, splat_tile_box, tile_count_across
from render.splatrule import (
    CLIP_XY,
    KERNEL_2D_SIZE,
    MAX_SCREEN_SPACE_SPLAT_SIZE,
    NEAREST_VIEW_Z,
    SPLAT_FLOATS,
    ProjectedSplat,
    stored_splat_depth,
)
from math.norm import squared_length2
from std.math import ceildiv, copysign, floor, max, min, sqrt
from std.memory import stack_allocation, unsafe_memcpy
from std.sys import has_accelerator
from std.time import perf_counter_ns

comptime GPU_DEPTH_RUNS = 1024
"""How many runs the depth sort shares a frame's splats out in. Each run is
one thread, and walks its splats one after another, so more runs finish
sooner. Each run has a count for each of the `BIN_COUNT` bins."""
comptime GPU_TILE_RUN_LIMIT = 2048
"""The most runs the tile sort shares the splats out in."""
comptime GPU_TILE_TABLE = 16000000
"""How many counts the tile sort's table holds: a run has a count for each
tile, so a picture with more tiles has fewer runs."""
comptime _SCAN_THREADS = 1024
"""The threads of the block that sums the lists' lengths."""
comptime _BLOCK = 64
"""The threads of a block in the launches that have a thread to a run, a bin
or a tile."""
comptime _U_MODEL_VIEW = 0
comptime _U_PROJECTION = 16
comptime _U_EYE = 32
comptime _U_WIDTH = 35
comptime _U_HEIGHT = 36
comptime _U_LEFT = 37
comptime _U_TOP = 38
comptime _U_LOG_SCALE = 39
comptime _U_MODE = 40
comptime _U_DEGREE = 41
comptime _U_FLOATS = 42
"""The lanes of the frame's `Float32` uniforms."""
comptime _D_NEAR = 0
comptime _D_SCALE = 1
comptime _D_FLOATS = 2
"""The lanes of the frame's depth-bin uniforms."""


def splat_project_kernel(
    projected: DevicePointer[Float32],
    bins: DevicePointer[Int32],
    boxes: DevicePointer[Int32],
    selected: DevicePointer[Int32],
    centers: DevicePointer[Float32],
    covariances: DevicePointer[Float32],
    colors: DevicePointer[UInt8],
    band1: DevicePointer[UInt8],
    band2: DevicePointer[UInt8],
    band3: DevicePointer[UInt8],
    u: DevicePointer[Float32],
    d: DevicePointer[Float32],
    count: Int32,
):
    """Shade, project and bin the selected splats: `render.splat_lod`'s
    `_project_selected` with a thread to each splat.

    Args:
        projected: Each selected splat's `SPLAT_FLOATS` lanes on the screen.
        bins: Each one's depth bin, furthest first, or -1 for a splat that
            is off the screen.
        boxes: Each one's box of tiles, four numbers: `splat_tile_box`.
        selected: The selected splats, as places in the scan.
        centers: The scan's centers, three floats a splat.
        covariances: The scan's covariances, six floats a splat.
        colors: The scan's color bytes, four a splat.
        band1: The first band's harmonics bytes.
        band2: The second band's.
        band3: The third band's.
        u: The frame's `Float32` uniforms.
        d: The frame's depth-bin uniforms.
        count: How many splats are selected.
    """
    var place = Int(block_idx.x) * Int(block_dim.x) + Int(thread_idx.x)
    if place >= Int(count):
        return
    bins[unsafe_offset=place] = -1
    var index = Int(selected[unsafe_offset=place])
    var cx = centers[unsafe_offset=index * 3]
    var cy = centers[unsafe_offset=index * 3 + 1]
    var cz = centers[unsafe_offset=index * 3 + 2]
    var red = Float32(colors[unsafe_offset=index * 4]) / 255
    var green = Float32(colors[unsafe_offset=index * 4 + 1]) / 255
    var blue = Float32(colors[unsafe_offset=index * 4 + 2]) / 255
    var opacity = Float32(colors[unsafe_offset=index * 4 + 3]) / 255
    var degree = Int(u[unsafe_offset=_U_DEGREE])
    if degree > 0:
        var eye = Vector3(
            u[unsafe_offset=_U_EYE],
            u[unsafe_offset=_U_EYE + 1],
            u[unsafe_offset=_U_EYE + 2],
        )
        var direction = Vector3(cx, cy, cz) - eye
        direction.normalize()
        for band in range(1, degree + 1):
            var weights = sh_weights(band, direction)
            var coefficients = band * 2 + 1
            var words = (coefficients * 3 + 3) // 4
            var base = index * words * 4
            for k in range(coefficients):
                var at = base + k * 3
                var w = weights[k]
                if band == 1:
                    red += (Float32(band1[unsafe_offset=at]) - 128) / 128 * w
                    green += (
                        (Float32(band1[unsafe_offset=at + 1]) - 128) / 128 * w
                    )
                    blue += (
                        (Float32(band1[unsafe_offset=at + 2]) - 128) / 128 * w
                    )
                elif band == 2:
                    red += (Float32(band2[unsafe_offset=at]) - 128) / 128 * w
                    green += (
                        (Float32(band2[unsafe_offset=at + 1]) - 128) / 128 * w
                    )
                    blue += (
                        (Float32(band2[unsafe_offset=at + 2]) - 128) / 128 * w
                    )
                else:
                    red += (Float32(band3[unsafe_offset=at]) - 128) / 128 * w
                    green += (
                        (Float32(band3[unsafe_offset=at + 1]) - 128) / 128 * w
                    )
                    blue += (
                        (Float32(band3[unsafe_offset=at + 2]) - 128) / 128 * w
                    )
    # The view and the projection, as `project_splat` reads them.
    var vx = (
        u[unsafe_offset=_U_MODEL_VIEW + 0] * cx
        + u[unsafe_offset=_U_MODEL_VIEW + 4] * cy
        + u[unsafe_offset=_U_MODEL_VIEW + 8] * cz
        + u[unsafe_offset=_U_MODEL_VIEW + 12]
    )
    var vy = (
        u[unsafe_offset=_U_MODEL_VIEW + 1] * cx
        + u[unsafe_offset=_U_MODEL_VIEW + 5] * cy
        + u[unsafe_offset=_U_MODEL_VIEW + 9] * cz
        + u[unsafe_offset=_U_MODEL_VIEW + 13]
    )
    var vz = (
        u[unsafe_offset=_U_MODEL_VIEW + 2] * cx
        + u[unsafe_offset=_U_MODEL_VIEW + 6] * cy
        + u[unsafe_offset=_U_MODEL_VIEW + 10] * cz
        + u[unsafe_offset=_U_MODEL_VIEW + 14]
    )
    var vw = (
        u[unsafe_offset=_U_MODEL_VIEW + 3] * cx
        + u[unsafe_offset=_U_MODEL_VIEW + 7] * cy
        + u[unsafe_offset=_U_MODEL_VIEW + 11] * cz
        + u[unsafe_offset=_U_MODEL_VIEW + 15]
    )
    var p0 = u[unsafe_offset=_U_PROJECTION + 0]
    var p5 = u[unsafe_offset=_U_PROJECTION + 5]
    var clip_x = (
        p0 * vx
        + u[unsafe_offset=_U_PROJECTION + 4] * vy
        + u[unsafe_offset=_U_PROJECTION + 8] * vz
        + u[unsafe_offset=_U_PROJECTION + 12] * vw
    )
    var clip_y = (
        u[unsafe_offset=_U_PROJECTION + 1] * vx
        + p5 * vy
        + u[unsafe_offset=_U_PROJECTION + 9] * vz
        + u[unsafe_offset=_U_PROJECTION + 13] * vw
    )
    var clip_z = (
        u[unsafe_offset=_U_PROJECTION + 2] * vx
        + u[unsafe_offset=_U_PROJECTION + 6] * vy
        + u[unsafe_offset=_U_PROJECTION + 10] * vz
        + u[unsafe_offset=_U_PROJECTION + 14] * vw
    )
    var clip_w = (
        u[unsafe_offset=_U_PROJECTION + 3] * vx
        + u[unsafe_offset=_U_PROJECTION + 7] * vy
        + u[unsafe_offset=_U_PROJECTION + 11] * vz
        + u[unsafe_offset=_U_PROJECTION + 15] * vw
    )
    var limit = clip_w * CLIP_XY
    if vz >= NEAREST_VIEW_Z or clip_z < -clip_w or clip_z > clip_w:
        return
    if clip_x < -limit or clip_x > limit or clip_y < -limit or clip_y > limit:
        return
    var r0 = Vector3(
        u[unsafe_offset=_U_MODEL_VIEW + 0],
        u[unsafe_offset=_U_MODEL_VIEW + 4],
        u[unsafe_offset=_U_MODEL_VIEW + 8],
    )
    var r1 = Vector3(
        u[unsafe_offset=_U_MODEL_VIEW + 1],
        u[unsafe_offset=_U_MODEL_VIEW + 5],
        u[unsafe_offset=_U_MODEL_VIEW + 9],
    )
    var r2 = Vector3(
        u[unsafe_offset=_U_MODEL_VIEW + 2],
        u[unsafe_offset=_U_MODEL_VIEW + 6],
        u[unsafe_offset=_U_MODEL_VIEW + 10],
    )
    var six = index * 6
    var cov0 = Vector3(
        covariances[unsafe_offset=six],
        covariances[unsafe_offset=six + 1],
        covariances[unsafe_offset=six + 2],
    )
    var cov1 = Vector3(
        covariances[unsafe_offset=six + 1],
        covariances[unsafe_offset=six + 3],
        covariances[unsafe_offset=six + 4],
    )
    var cov2 = Vector3(
        covariances[unsafe_offset=six + 2],
        covariances[unsafe_offset=six + 4],
        covariances[unsafe_offset=six + 5],
    )
    var vc0 = Vector3(r0.dot(cov0), r0.dot(cov1), r0.dot(cov2))
    var vc1 = Vector3(r1.dot(cov0), r1.dot(cov1), r1.dot(cov2))
    var vc2 = Vector3(r2.dot(cov0), r2.dot(cov1), r2.dot(cov2))
    var c00 = vc0.dot(r0)
    var c01 = vc0.dot(r1)
    var c02 = vc0.dot(r2)
    var c11 = vc1.dot(r1)
    var c12 = vc1.dot(r2)
    var c22 = vc2.dot(r2)
    var inv_z = 1 / min(vz, NEAREST_VIEW_Z)
    var inv_z2 = inv_z * inv_z
    var width = u[unsafe_offset=_U_WIDTH]
    var height = u[unsafe_offset=_U_HEIGHT]
    var fx = width * 0.5 * p0
    var fy = height * 0.5 * p5
    var j00 = -fx * inv_z
    var j11 = -fy * inv_z
    var j02 = fx * vx * inv_z2
    var j12 = fy * vy * inv_z2
    var a_base = j00 * j00 * c00 + j00 * j02 * c02 * 2 + j02 * j02 * c22
    var b = (
        j00 * j11 * c01 + j00 * j12 * c02 + j02 * j11 * c12 + (j02 * j12 * c22)
    )
    var c_base = j11 * j11 * c11 + j11 * j12 * c12 * 2 + j12 * j12 * c22
    var a = a_base + KERNEL_2D_SIZE
    var c = c_base + KERNEL_2D_SIZE
    var det_base = a_base * c_base - b * b
    var det = a * c - b * b
    var alpha_scale = sqrt(max(det_base / max(det, 0.000001), 0))
    var half_trace = (a + c) * 0.5
    var half_gap = (a - c) * 0.5
    var radius = sqrt(
        max(squared_length2[DType.float32](half_gap, b), 0.0000001)
    )
    var lambda1 = max(half_trace + radius, 0.0000001)
    var lambda2 = max(half_trace - radius, 0.0000001)
    var gap = sqrt(squared_length2[DType.float32](half_gap, b))
    var cos2 = half_gap / gap if gap > 0 else Float32(1)
    var axis_x = sqrt(max((1 + cos2) * 0.5, 0))
    var axis_y = copysign(sqrt(max((1 - cos2) * 0.5, 0)), b)
    var mode = DepthMode(Int(u[unsafe_offset=_U_MODE]))
    var at = place * SPLAT_FLOATS
    projected[unsafe_offset=at] = (clip_x / clip_w + 1) * 0.5 * width + u[
        unsafe_offset=_U_LEFT
    ]
    projected[unsafe_offset=at + 1] = (1 - clip_y / clip_w) * 0.5 * height + u[
        unsafe_offset=_U_TOP
    ]
    projected[unsafe_offset=at + 2] = stored_splat_depth(
        mode, clip_z / clip_w, clip_w, u[unsafe_offset=_U_LOG_SCALE]
    )
    projected[unsafe_offset=at + 3] = axis_x
    projected[unsafe_offset=at + 4] = axis_y
    projected[unsafe_offset=at + 5] = min(
        sqrt(lambda1), MAX_SCREEN_SPACE_SPLAT_SIZE
    )
    projected[unsafe_offset=at + 6] = min(
        sqrt(lambda2), MAX_SCREEN_SPACE_SPLAT_SIZE
    )
    projected[unsafe_offset=at + 7] = min(max(red, 0), 1)
    projected[unsafe_offset=at + 8] = min(max(green, 0), 1)
    projected[unsafe_offset=at + 9] = min(max(blue, 0), 1)
    projected[unsafe_offset=at + 10] = opacity * alpha_scale
    var box = splat_tile_box(
        ProjectedSplat(
            projected[unsafe_offset=at],
            projected[unsafe_offset=at + 1],
            projected[unsafe_offset=at + 2],
            axis_x,
            axis_y,
            projected[unsafe_offset=at + 5],
            projected[unsafe_offset=at + 6],
            0,
            0,
            0,
            0,
        ),
        Int(width),
        Int(height),
    )
    for lane in range(4):
        boxes[unsafe_offset=place * 4 + lane] = box[lane]
    # The depth bin, furthest first, as the host finds it.
    var depth = -(
        u[unsafe_offset=_U_MODEL_VIEW + 2] * cx
        + u[unsafe_offset=_U_MODEL_VIEW + 6] * cy
        + u[unsafe_offset=_U_MODEL_VIEW + 10] * cz
        + u[unsafe_offset=_U_MODEL_VIEW + 14]
    )
    var bin = (
        BIN_COUNT
        - 1
        - Int(
            min(
                Float32(BIN_COUNT - 1),
                max(
                    Float32(0),
                    floor(
                        (depth - d[unsafe_offset=_D_NEAR])
                        * d[unsafe_offset=_D_SCALE]
                    ),
                ),
            )
        )
    )
    bins[unsafe_offset=place] = Int32(bin)


def splat_depth_count_kernel(
    counts: DevicePointer[Int32],
    bins: DevicePointer[Int32],
    selected_count: Int32,
    runs: Int32,
):
    """Count, for each run of the selection, its splats in each depth bin.

    Args:
        counts: One count a run and a bin, run by run. It must start at zero.
        bins: Each selected splat's bin, or -1.
        selected_count: How many splats are selected.
        runs: How many runs share the selection.
    """
    var run = Int(block_idx.x) * Int(block_dim.x) + Int(thread_idx.x)
    if run >= Int(runs):
        return
    var n = Int(selected_count)
    var first = run * n // Int(runs)
    var past = (run + 1) * n // Int(runs)
    for place in range(first, past):
        var bin = Int(bins[unsafe_offset=place])
        if bin >= 0:
            counts[unsafe_offset=run * BIN_COUNT + bin] += 1


def splat_bin_total_kernel(
    counts: DevicePointer[Int32],
    totals: DevicePointer[Int32],
    runs: Int32,
):
    """Turn each bin's counts into the offsets of its runs, and add up the
    bin.

    Args:
        counts: The counts, run by run; on return each is how many splats of
            its bin the earlier runs hold.
        totals: One total a bin.
        runs: How many runs there are.
    """
    var bin = Int(block_idx.x) * Int(block_dim.x) + Int(thread_idx.x)
    if bin >= BIN_COUNT:
        return
    var running = Int32(0)
    for run in range(Int(runs)):
        var here = counts[unsafe_offset=run * BIN_COUNT + bin]
        counts[unsafe_offset=run * BIN_COUNT + bin] = running
        running += here
    totals[unsafe_offset=bin] = running


def splat_scan_kernel(
    totals: DevicePointer[Int32],
    starts: DevicePointer[Int32],
    meta: DevicePointer[Int32],
    count: Int32,
    slot: Int32,
):
    """Turn totals into the places where each list starts, in one block.

    Each thread adds up a stretch of the totals, the block scans the sums of
    the stretches in shared memory, and each thread writes the starts of its
    stretch.

    Args:
        totals: One total a list.
        starts: Each list's first place, and the sum after the last.
        meta: Where the sum is also written, at `slot`.
        count: How many lists.
        slot: The place in `meta` for the sum.
    """
    var sums = stack_allocation[
        _SCAN_THREADS,
        Scalar[DType.int32],
        address_space=AddressSpace.SHARED,
    ]()
    var t = Int(thread_idx.x)
    var n = Int(count)
    var stretch = (n + _SCAN_THREADS - 1) // _SCAN_THREADS
    var first = min(t * stretch, n)
    var past = min(first + stretch, n)
    var own = Int32(0)
    for at in range(first, past):
        own += totals[unsafe_offset=at]
    sums[unsafe_offset=t] = own
    barrier()
    var offset = 1
    while offset < _SCAN_THREADS:
        var add = Int32(0)
        if t >= offset:
            add = sums[unsafe_offset=t - offset]
        barrier()
        sums[unsafe_offset=t] += add
        barrier()
        offset *= 2
    var running = sums[unsafe_offset=t] - own
    for at in range(first, past):
        starts[unsafe_offset=at] = running
        running += totals[unsafe_offset=at]
    if t == _SCAN_THREADS - 1:
        starts[unsafe_offset=n] = sums[unsafe_offset=t]
        meta[unsafe_offset=Int(slot)] = sums[unsafe_offset=t]


def splat_depth_place_kernel(
    order: DevicePointer[Int32],
    counts: DevicePointer[Int32],
    starts: DevicePointer[Int32],
    bins: DevicePointer[Int32],
    selected_count: Int32,
    runs: Int32,
):
    """Put each run's splats in the draw order, each at its bin's next
    place.

    Args:
        order: The selected splats' places in draw order.
        counts: The runs' offsets within each bin, advanced as they place.
        starts: Each bin's first place.
        bins: Each selected splat's bin, or -1.
        selected_count: How many splats are selected.
        runs: How many runs share the selection.
    """
    var run = Int(block_idx.x) * Int(block_dim.x) + Int(thread_idx.x)
    if run >= Int(runs):
        return
    var n = Int(selected_count)
    var first = run * n // Int(runs)
    var past = (run + 1) * n // Int(runs)
    for place in range(first, past):
        var bin = Int(bins[unsafe_offset=place])
        if bin >= 0:
            var slot = (
                starts[unsafe_offset=bin]
                + counts[unsafe_offset=run * BIN_COUNT + bin]
            )
            counts[unsafe_offset=run * BIN_COUNT + bin] += 1
            order[unsafe_offset=Int(slot)] = Int32(place)


def splat_tile_count_kernel(
    counts: DevicePointer[Int32],
    order: DevicePointer[Int32],
    boxes: DevicePointer[Int32],
    meta: DevicePointer[Int32],
    tiles_x: Int32,
    tiles: Int32,
    runs: Int32,
):
    """Count, for each run of the sorted splats, its splats in each tile.

    Args:
        counts: One count a run and a tile, run by run. It must start at
            zero.
        order: The selected splats in draw order.
        boxes: Each selected splat's box of tiles.
        meta: Holds the number of splats on the screen first.
        tiles_x: How many tiles across.
        tiles: How many tiles there are.
        runs: How many runs share the splats.
    """
    var run = Int(block_idx.x) * Int(block_dim.x) + Int(thread_idx.x)
    if run >= Int(runs):
        return
    var n = Int(meta[unsafe_offset=0])
    var first = run * n // Int(runs)
    var past = (run + 1) * n // Int(runs)
    for k in range(first, past):
        var at = Int(order[unsafe_offset=k]) * 4
        for ty in range(
            Int(boxes[unsafe_offset=at + 2]),
            Int(boxes[unsafe_offset=at + 3]) + 1,
        ):
            for tx in range(
                Int(boxes[unsafe_offset=at]),
                Int(boxes[unsafe_offset=at + 1]) + 1,
            ):
                counts[
                    unsafe_offset=run * Int(tiles) + ty * Int(tiles_x) + tx
                ] += 1


def splat_tile_total_kernel(
    counts: DevicePointer[Int32],
    totals: DevicePointer[Int32],
    tiles: Int32,
    runs: Int32,
):
    """Turn each tile's counts into the offsets of its runs, and add up the
    tile.

    Args:
        counts: The counts, run by run; on return each is how many splats of
            its tile the earlier runs hold.
        totals: One total a tile.
        tiles: How many tiles there are.
        runs: How many runs there are.
    """
    var tile = Int(block_idx.x) * Int(block_dim.x) + Int(thread_idx.x)
    if tile >= Int(tiles):
        return
    var running = Int32(0)
    for run in range(Int(runs)):
        var here = counts[unsafe_offset=run * Int(tiles) + tile]
        counts[unsafe_offset=run * Int(tiles) + tile] = running
        running += here
    totals[unsafe_offset=tile] = running


def splat_tile_place_kernel(
    items: DevicePointer[Int32],
    counts: DevicePointer[Int32],
    starts: DevicePointer[Int32],
    order: DevicePointer[Int32],
    boxes: DevicePointer[Int32],
    meta: DevicePointer[Int32],
    tiles_x: Int32,
    tiles: Int32,
    runs: Int32,
):
    """Put each run's sorted splats in the lists of the tiles they reach.

    Args:
        items: The splats of every tile, in draw order, as places in
            `projected`.
        counts: The runs' offsets within each tile, advanced as they place.
        starts: Each tile's first place.
        order: The selected splats in draw order.
        boxes: Each selected splat's box of tiles.
        meta: Holds the number of splats on the screen first.
        tiles_x: How many tiles across.
        tiles: How many tiles there are.
        runs: How many runs share the splats.
    """
    var run = Int(block_idx.x) * Int(block_dim.x) + Int(thread_idx.x)
    if run >= Int(runs):
        return
    var n = Int(meta[unsafe_offset=0])
    var first = run * n // Int(runs)
    var past = (run + 1) * n // Int(runs)
    for k in range(first, past):
        var index = Int(order[unsafe_offset=k])
        var at = index * 4
        for ty in range(
            Int(boxes[unsafe_offset=at + 2]),
            Int(boxes[unsafe_offset=at + 3]) + 1,
        ):
            for tx in range(
                Int(boxes[unsafe_offset=at]),
                Int(boxes[unsafe_offset=at + 1]) + 1,
            ):
                var tile = ty * Int(tiles_x) + tx
                var slot = (
                    starts[unsafe_offset=tile]
                    + counts[unsafe_offset=run * Int(tiles) + tile]
                )
                counts[unsafe_offset=run * Int(tiles) + tile] += 1
                items[unsafe_offset=Int(slot)] = Int32(index)


def _fill[
    dtype: DType, origin: Origin
](
    context: DeviceContext, host: Pointer[Scalar[dtype], origin], count: Int
) raises -> DeviceBuffer[dtype]:
    """Make a device buffer hold a host array, through a pinned buffer.

    Args:
        context: The device.
        host: The array.
        count: How many elements, 1 or more.

    Returns:
        The device buffer.

    Raises:
        Error: If a buffer cannot be made.
    """
    var staged = context.enqueue_create_host_buffer[dtype](count)
    unsafe_memcpy(dest=staged.unsafe_ptr(), src=host, count=count)
    var device = context.enqueue_create_buffer[dtype](count)
    context.enqueue_copy(dst_buf=device, src_buf=staged)
    context.synchronize()
    return device^


struct GpuSplatScene(Movable):
    """A scan with levels of detail, kept on the device and drawn there; see
    the module docstring.

    The work buffers stay between frames and grow when a frame needs more.
    """

    # Every device buffer is declared before the context that owns it,
    # and `__deinit__` releases them first; see `GpuRenderer.__deinit__`.
    var centers: DeviceBuffer[DType.float32]
    var covariances: DeviceBuffer[DType.float32]
    var colors: DeviceBuffer[DType.uint8]
    var band1: DeviceBuffer[DType.uint8]
    var band2: DeviceBuffer[DType.uint8]
    var band3: DeviceBuffer[DType.uint8]
    var selected: DeviceBuffer[DType.int32]
    var bins: DeviceBuffer[DType.int32]
    var boxes: DeviceBuffer[DType.int32]
    var order: DeviceBuffer[DType.int32]
    var projected: DeviceBuffer[DType.float32]
    var bin_counts: DeviceBuffer[DType.int32]
    var bin_totals: DeviceBuffer[DType.int32]
    var bin_starts: DeviceBuffer[DType.int32]
    var tile_counts: DeviceBuffer[DType.int32]
    var tile_totals: DeviceBuffer[DType.int32]
    var tile_starts: DeviceBuffer[DType.int32]
    var items: DeviceBuffer[DType.int32]
    var meta: DeviceBuffer[DType.int32]
    var uniforms: DeviceBuffer[DType.float32]
    var wide: DeviceBuffer[DType.float32]
    var pixels: DeviceBuffer[DType.uint8]
    var selected_host: HostBuffer[DType.int32]
    var uniforms_host: HostBuffer[DType.float32]
    var wide_host: HostBuffer[DType.float32]
    var meta_host: HostBuffer[DType.int32]
    var pixels_host: HostBuffer[DType.uint8]
    var degree: Int
    """The scan's spherical harmonics degree, 0 through 3."""
    var count: Int
    """How many splats the scan holds, merged ones included."""
    var select_room: Int
    var tile_room: Int
    var item_room: Int
    var pixel_room: Int
    var select_ms: Float64
    """How long the last draw's walk of the tree took on the host."""
    var device_ms: Float64
    """How long the last draw's launches took, from the first to the picture
    being back."""
    var profile: Bool
    """Whether a draw waits for the device after each stage and records the
    stage's time in `phase_ms`. It slows the draw down."""
    var phase_ms: List[Float64]
    """The milliseconds of each stage of the last profiled draw: upload and
    clearing, project, depth sort, tile counts, the wait for the lists' length,
    tile placement, fill, the picture's return, and last the host's own
    preparation before any launch."""
    var context: DeviceContext

    def __deinit__(deinit self):
        """Drain the queue, release the buffers, then the context."""
        try:
            self.context.synchronize()
        except:
            pass
        _ = self.centers^
        _ = self.covariances^
        _ = self.colors^
        _ = self.band1^
        _ = self.band2^
        _ = self.band3^
        _ = self.selected^
        _ = self.bins^
        _ = self.boxes^
        _ = self.order^
        _ = self.projected^
        _ = self.bin_counts^
        _ = self.bin_totals^
        _ = self.bin_starts^
        _ = self.tile_counts^
        _ = self.tile_totals^
        _ = self.tile_starts^
        _ = self.items^
        _ = self.meta^
        _ = self.uniforms^
        _ = self.wide^
        _ = self.pixels^
        _ = self.selected_host^
        _ = self.uniforms_host^
        _ = self.wide_host^
        _ = self.meta_host^
        _ = self.pixels_host^
        _ = self.context^

    def __init__(out self, lod: SplatLod) raises:
        """Send a tree's splats to the device.

        Args:
            lod: The tree. Its scan's splats and its merged splats go.

        Raises:
            Error: If no GPU is present, or the tree holds no splat.
        """
        if not has_accelerator():
            raise Error("No GPU available")
        ref g = lod.splat.splat_geometry
        if g.count() == 0:
            raise Error("A GPU splat scene needs at least one splat")
        self.context = DeviceContext()
        self.count = g.count()
        self.degree = g.spherical_harmonics_degree()
        self.centers = _fill(
            self.context, g.centers.unsafe_ptr(), len(g.centers)
        )
        self.covariances = _fill(
            self.context, g.covariances.unsafe_ptr(), len(g.covariances)
        )
        self.colors = _fill(self.context, g.colors.unsafe_ptr(), len(g.colors))
        var none = List[UInt8](length=4, fill=0)
        self.band1 = _fill(
            self.context,
            g.sh1.unsafe_ptr() if len(g.sh1) > 0 else none.unsafe_ptr(),
            max(len(g.sh1), 4),
        )
        self.band2 = _fill(
            self.context,
            g.sh2.unsafe_ptr() if len(g.sh2) > 0 else none.unsafe_ptr(),
            max(len(g.sh2), 4),
        )
        self.band3 = _fill(
            self.context,
            g.sh3.unsafe_ptr() if len(g.sh3) > 0 else none.unsafe_ptr(),
            max(len(g.sh3), 4),
        )
        self.selected = self.context.enqueue_create_buffer[DType.int32](4)
        self.bins = self.context.enqueue_create_buffer[DType.int32](4)
        self.boxes = self.context.enqueue_create_buffer[DType.int32](4)
        self.order = self.context.enqueue_create_buffer[DType.int32](4)
        self.projected = self.context.enqueue_create_buffer[DType.float32](
            SPLAT_FLOATS
        )
        self.bin_counts = self.context.enqueue_create_buffer[DType.int32](
            GPU_DEPTH_RUNS * BIN_COUNT
        )
        self.bin_totals = self.context.enqueue_create_buffer[DType.int32](
            BIN_COUNT
        )
        self.bin_starts = self.context.enqueue_create_buffer[DType.int32](
            BIN_COUNT + 1
        )
        self.tile_counts = self.context.enqueue_create_buffer[DType.int32](
            GPU_TILE_TABLE
        )
        self.tile_totals = self.context.enqueue_create_buffer[DType.int32](4)
        self.tile_starts = self.context.enqueue_create_buffer[DType.int32](4)
        self.items = self.context.enqueue_create_buffer[DType.int32](4)
        self.meta = self.context.enqueue_create_buffer[DType.int32](4)
        self.uniforms = self.context.enqueue_create_buffer[DType.float32](
            _U_FLOATS
        )
        self.wide = self.context.enqueue_create_buffer[DType.float32](_D_FLOATS)
        self.pixels = self.context.enqueue_create_buffer[DType.uint8](4)
        self.selected_host = self.context.enqueue_create_host_buffer[
            DType.int32
        ](4)
        self.uniforms_host = self.context.enqueue_create_host_buffer[
            DType.float32
        ](_U_FLOATS)
        self.wide_host = self.context.enqueue_create_host_buffer[DType.float32](
            _D_FLOATS
        )
        self.meta_host = self.context.enqueue_create_host_buffer[DType.int32](4)
        self.pixels_host = self.context.enqueue_create_host_buffer[DType.uint8](
            4
        )
        self.select_room = 4
        self.tile_room = 4
        self.item_room = 4
        self.pixel_room = 4
        self.select_ms = 0
        self.device_ms = 0
        self.profile = False
        self.phase_ms = List[Float64](length=9, fill=0)
        self.context.synchronize()

    def _mark(mut self, stage: Int, mut since: Int) raises:
        """Record how long a stage took, if profiling.

        Args:
            stage: Which stage, 0 through 7.
            since: When the stage began, in nanoseconds; set to now.

        Raises:
            Error: If the device fails.
        """
        if self.profile:
            self.context.synchronize()
            var now = perf_counter_ns()
            self.phase_ms[stage] = Float64(now - since) / 1e6
            since = now

    def _room(mut self, selected: Int, tiles: Int, pixels: Int) raises:
        """Make the work buffers big enough for a frame.

        Args:
            selected: How many splats the frame selected.
            tiles: How many tiles the picture has.
            pixels: How many bytes the picture has.

        Raises:
            Error: If a buffer cannot be made.
        """
        # A launch in flight may still read the old buffers.
        self.context.synchronize()
        if selected > self.select_room:
            self.select_room = selected * 2
            self.selected = self.context.enqueue_create_buffer[DType.int32](
                self.select_room
            )
            self.bins = self.context.enqueue_create_buffer[DType.int32](
                self.select_room
            )
            self.boxes = self.context.enqueue_create_buffer[DType.int32](
                self.select_room * 4
            )
            self.order = self.context.enqueue_create_buffer[DType.int32](
                self.select_room
            )
            self.projected = self.context.enqueue_create_buffer[DType.float32](
                self.select_room * SPLAT_FLOATS
            )
            self.selected_host = self.context.enqueue_create_host_buffer[
                DType.int32
            ](self.select_room)
        if tiles + 1 > self.tile_room:
            self.tile_room = (tiles + 1) * 2
            self.tile_totals = self.context.enqueue_create_buffer[DType.int32](
                self.tile_room
            )
            self.tile_starts = self.context.enqueue_create_buffer[DType.int32](
                self.tile_room
            )
        if pixels > self.pixel_room:
            self.pixel_room = pixels * 2
            self.pixels = self.context.enqueue_create_buffer[DType.uint8](
                self.pixel_room
            )
            self.pixels_host = self.context.enqueue_create_host_buffer[
                DType.uint8
            ](self.pixel_room)

    def draw_bytes[
        C: Camera
    ](
        mut self,
        scene: Scene,
        lod: SplatLod,
        camera: C,
        width: Int,
        height: Int,
        background: Color,
        mut picture: List[UInt8],
        workers: Int = 1,
        pixels: Float32 = LOD_PIXELS,
    ) raises:
        """Draw the scan into a list of bytes, four a pixel, row by row.

        Args:
            scene: The scene, updated, that holds the tree's node.
            lod: The tree this scene was made from, whose node and whose
                tree select the splats.
            camera: The camera to project through.
            width: The picture's width in pixels, 1 or more.
            height: The picture's height, 1 or more.
            background: The color to clear to. It must be opaque.
            picture: The bytes, set to the picture's size and filled.
            workers: How many host threads walk the tree.
            pixels: How many pixels a node's sphere covers, at most, for the
                node to draw as its merged splat; see
                `render.splat_lod.select_splats`.

        Raises:
            Error: If the size is not valid, the background is not opaque,
                the tree is not the scan the scene holds, the node is not
                in the scene, the scene is stale, or a matrix cannot be
                inverted.
        """
        if background.a != 255:
            raise Error("A GPU splat fill needs an opaque background")
        if width < 1 or height < 1:
            raise Error("A GPU splat draw is at least one pixel each way")
        if lod.splat.splat_geometry.count() != self.count:
            raise Error("The tree is not the scan that the scene holds")
        var bytes = width * height * 4
        if len(picture) != bytes:
            picture = List[UInt8](length=bytes, fill=0)
        var rect = Rect.whole(width, height)
        var selected = List[Int]()
        var world = scene.world_matrix(lod.splat.node)
        var view = camera.view_matrix_in(scene)
        var model_view = view * world
        var projection = camera.projection_matrix()
        var began = perf_counter_ns()
        if scene.shows(lod.splat.node, camera.visible_layers()):
            selected = select_splats(
                lod, model_view, projection, rect.height, pixels, workers
            )
        self.select_ms = Float64(perf_counter_ns() - began) / 1e6
        var count = len(selected)
        if count == 0:
            for at in range(width * height):
                picture[at * 4] = background.r
                picture[at * 4 + 1] = background.g
                picture[at * 4 + 2] = background.b
                picture[at * 4 + 3] = 255
            return
        var tiles_x = tile_count_across(width)
        var tiles_y = tile_count_across(height)
        var tiles = tiles_x * tiles_y
        if tiles > GPU_TILE_TABLE:
            raise Error("A GPU splat draw has too many tiles")
        var tile_runs = max(1, min(GPU_TILE_RUN_LIMIT, GPU_TILE_TABLE // tiles))
        self._room(count, tiles, bytes)
        began = perf_counter_ns()
        var mark = began

        # The view, as `prepare_splat_lod` makes it.
        var camera_world = view
        camera_world.invert()
        var local = world
        local.invert()
        var eye = local.transform_point(
            camera_world.transform_point(Vector3(0, 0, 0))
        )
        ref m = model_view.elements
        var c = lod.nodes[0].center
        var radius = Float64(lod.nodes[0].radius)
        var depth = -Float64(m[2] * c.x + m[6] * c.y + m[10] * c.z + m[14])
        var near = max(Float64(camera.near_distance()), depth - radius)
        var far = max(near + MIN_SORT_RANGE, depth + radius)
        var mode = STANDARD_DEPTH
        for lane in range(16):
            self.uniforms_host[_U_MODEL_VIEW + lane] = model_view.elements[lane]
            self.uniforms_host[_U_PROJECTION + lane] = projection.elements[lane]
        self.uniforms_host[_U_EYE] = eye.x
        self.uniforms_host[_U_EYE + 1] = eye.y
        self.uniforms_host[_U_EYE + 2] = eye.z
        self.uniforms_host[_U_WIDTH] = Float32(rect.width)
        self.uniforms_host[_U_HEIGHT] = Float32(rect.height)
        self.uniforms_host[_U_LEFT] = Float32(rect.x)
        self.uniforms_host[_U_TOP] = Float32(rect.top(height))
        self.uniforms_host[_U_LOG_SCALE] = log_depth_factor(
            camera.far_distance()
        )
        self.uniforms_host[_U_MODE] = Float32(mode.value)
        self.uniforms_host[_U_DEGREE] = Float32(self.degree)
        self.wide_host[_D_NEAR] = Float32(near)
        self.wide_host[_D_SCALE] = Float32(
            Float64(BIN_COUNT - 1) / (far - near)
        )
        var places = self.selected_host.unsafe_ptr()
        for place in range(count):
            places[unsafe_offset=place] = Int32(selected[place])
        self.meta_host[0] = 0
        self.meta_host[1] = 0
        if self.profile:
            self.phase_ms[8] = Float64(perf_counter_ns() - began) / 1e6
            mark = perf_counter_ns()
        var selected_sub = self.selected.create_sub_buffer[DType.int32](
            0, count
        )
        var selected_from = self.selected_host.create_sub_buffer[DType.int32](
            0, count
        )
        self.context.enqueue_copy(dst_buf=selected_sub, src_buf=selected_from)
        self.context.enqueue_copy(
            dst_buf=self.uniforms, src_buf=self.uniforms_host
        )
        self.context.enqueue_copy(dst_buf=self.wide, src_buf=self.wide_host)
        self.context.enqueue_copy(dst_buf=self.meta, src_buf=self.meta_host)
        self.bin_counts.enqueue_fill(0)
        var tile_counts = self.tile_counts.create_sub_buffer[DType.int32](
            0, tile_runs * tiles
        )
        tile_counts.enqueue_fill(0)

        self._mark(0, mark)
        # 1. Project.
        self.context.enqueue_function[splat_project_kernel](
            device_pointer(self.projected),
            device_pointer(self.bins),
            device_pointer(self.boxes),
            device_pointer(self.selected),
            device_pointer(self.centers),
            device_pointer(self.covariances),
            device_pointer(self.colors),
            device_pointer(self.band1),
            device_pointer(self.band2),
            device_pointer(self.band3),
            device_pointer(self.uniforms),
            device_pointer(self.wide),
            Int32(count),
            grid_dim=ceildiv(count, _BLOCK),
            block_dim=_BLOCK,
        )
        self._mark(1, mark)
        # 2. Sort by depth.
        self.context.enqueue_function[splat_depth_count_kernel](
            device_pointer(self.bin_counts),
            device_pointer(self.bins),
            Int32(count),
            Int32(GPU_DEPTH_RUNS),
            grid_dim=ceildiv(GPU_DEPTH_RUNS, _BLOCK),
            block_dim=_BLOCK,
        )
        self.context.enqueue_function[splat_bin_total_kernel](
            device_pointer(self.bin_counts),
            device_pointer(self.bin_totals),
            Int32(GPU_DEPTH_RUNS),
            grid_dim=ceildiv(BIN_COUNT, _BLOCK),
            block_dim=_BLOCK,
        )
        self.context.enqueue_function[splat_scan_kernel](
            device_pointer(self.bin_totals),
            device_pointer(self.bin_starts),
            device_pointer(self.meta),
            Int32(BIN_COUNT),
            Int32(0),
            grid_dim=1,
            block_dim=_SCAN_THREADS,
        )
        self.context.enqueue_function[splat_depth_place_kernel](
            device_pointer(self.order),
            device_pointer(self.bin_counts),
            device_pointer(self.bin_starts),
            device_pointer(self.bins),
            Int32(count),
            Int32(GPU_DEPTH_RUNS),
            grid_dim=ceildiv(GPU_DEPTH_RUNS, _BLOCK),
            block_dim=_BLOCK,
        )
        self._mark(2, mark)
        # 3. Sort into tiles.
        self.context.enqueue_function[splat_tile_count_kernel](
            device_pointer(self.tile_counts),
            device_pointer(self.order),
            device_pointer(self.boxes),
            device_pointer(self.meta),
            Int32(tiles_x),
            Int32(tiles),
            Int32(tile_runs),
            grid_dim=ceildiv(tile_runs, _BLOCK),
            block_dim=_BLOCK,
        )
        self.context.enqueue_function[splat_tile_total_kernel](
            device_pointer(self.tile_counts),
            device_pointer(self.tile_totals),
            Int32(tiles),
            Int32(tile_runs),
            grid_dim=ceildiv(tiles, _BLOCK),
            block_dim=_BLOCK,
        )
        self.context.enqueue_function[splat_scan_kernel](
            device_pointer(self.tile_totals),
            device_pointer(self.tile_starts),
            device_pointer(self.meta),
            Int32(tiles),
            Int32(1),
            grid_dim=1,
            block_dim=_SCAN_THREADS,
        )
        self._mark(3, mark)
        self.context.enqueue_copy(dst_buf=self.meta_host, src_buf=self.meta)
        self.context.synchronize()
        self._mark(4, mark)
        var pairs = Int(self.meta_host[1])
        if pairs > self.item_room:
            self.item_room = pairs * 2
            self.items = self.context.enqueue_create_buffer[DType.int32](
                self.item_room
            )
        self.context.enqueue_function[splat_tile_place_kernel](
            device_pointer(self.items),
            device_pointer(self.tile_counts),
            device_pointer(self.tile_starts),
            device_pointer(self.order),
            device_pointer(self.boxes),
            device_pointer(self.meta),
            Int32(tiles_x),
            Int32(tiles),
            Int32(tile_runs),
            grid_dim=ceildiv(tile_runs, _BLOCK),
            block_dim=_BLOCK,
        )
        self._mark(5, mark)
        # 4. Fill.
        self.context.enqueue_function[splat_tile_kernel](
            device_pointer(self.pixels),
            device_pointer(self.projected),
            device_pointer(self.tile_starts),
            device_pointer(self.items),
            Int32(width),
            Int32(height),
            Int32(tiles_x),
            Float32(background.r) / 255,
            Float32(background.g) / 255,
            Float32(background.b) / 255,
            grid_dim=(tiles_x, tiles_y),
            block_dim=(SPLAT_TILE, SPLAT_TILE),
        )
        self._mark(6, mark)
        var picture_sub = self.pixels.create_sub_buffer[DType.uint8](0, bytes)
        var picture_to = self.pixels_host.create_sub_buffer[DType.uint8](
            0, bytes
        )
        self.context.enqueue_copy(dst_buf=picture_to, src_buf=picture_sub)
        self.context.synchronize()
        unsafe_memcpy(
            dest=picture.unsafe_ptr(),
            src=self.pixels_host.unsafe_ptr(),
            count=bytes,
        )
        self._mark(7, mark)
        self.device_ms = Float64(perf_counter_ns() - began) / 1e6

    def draw[
        C: Camera
    ](
        mut self,
        scene: Scene,
        lod: SplatLod,
        camera: C,
        width: Int,
        height: Int,
        background: Color,
        workers: Int = 1,
        pixels: Float32 = LOD_PIXELS,
    ) raises -> Framebuffer:
        """Draw the scan into a picture; see `draw_bytes`.

        Args:
            scene: The scene, updated, that holds the tree's node.
            lod: The tree this scene was made from.
            camera: The camera to project through.
            width: The picture's width in pixels.
            height: The picture's height.
            background: The color to clear to. It must be opaque.
            workers: How many host threads walk the tree.
            pixels: How many pixels a node's sphere covers, at most, for the
                node to draw as its merged splat.

        Returns:
            The picture.

        Raises:
            Error: Everything `draw_bytes` raises.
        """
        var picture = List[UInt8]()
        self.draw_bytes(
            scene,
            lod,
            camera,
            width,
            height,
            background,
            picture,
            workers,
            pixels,
        )
        return Framebuffer(width, height, picture^)
