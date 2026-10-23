# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Projected splats sorted into the tiles of the screen they reach.

A fill that goes tile by tile reads each splat only for the tiles that it
covers. `bin_splats` finds those tiles, `SPLAT_TILE` pixels on a side, and
lists each tile's splats in draw order. A pixel then takes the same blends
in the same order as it does in `render.splat_raster.rasterize_splats`, and
the list for a tile can be read by a thread block of a GPU, which holds the
tile's pixels, one thread to each.

The box of tiles that a splat reaches comes from `splat_reach`, the half
width and the half height of its quad, widened by one pixel on each side.
So every pixel that `splat_alpha` gives an opacity above zero is in a tile
of the splat's box, whatever the rounding of the two. The arithmetic is
32-bit, so that a GPU without 64-bit floats runs it. A tile that the box
holds and the disc does not reach costs a test and blends nothing.

The lists are made as `rasterize_splats` makes the lists of its bands: a
counting sort in runs of splats, the runs counted at once and placed at
once. Each run puts its splats after the earlier runs' splats in each tile,
so the lists are the same for any count of workers.
"""

from render.splatrule import ProjectedSplat, splat_reach
from render.tasks import TaskGroup
from std.math import ceil, floor, max, min

comptime SPLAT_TILE = 16
"""The side of a tile, in pixels: a multiple of the warp size of every
vendor squared, and a thread block that fits every device."""
comptime SPLAT_TILE_RUN = 4096
"""The fewest splats a binning worker takes: a shorter run is not worth a
task."""
comptime SPLAT_TILE_LIMIT = 2147483647
"""The most entries all the lists can hold, as a 32-bit count."""


struct SplatTiles(Movable):
    """The splats of each tile, in draw order."""

    var tiles_x: Int
    """How many tiles across."""
    var tiles_y: Int
    """How many tiles down."""
    var starts: List[Int32]
    """Where each tile's list starts in `items`, tile after tile, row by
    row. One more than there are tiles: the last is the length of `items`."""
    var items: List[Int32]
    """The splats of every tile, as places in the list that was binned."""

    def __init__(
        out self,
        tiles_x: Int,
        tiles_y: Int,
        var starts: List[Int32],
        var items: List[Int32],
    ):
        """Hold the lists of the tiles.

        Args:
            tiles_x: How many tiles across.
            tiles_y: How many tiles down.
            starts: Each tile's first place in `items`, and the length.
            items: Each tile's splats.
        """
        self.tiles_x = tiles_x
        self.tiles_y = tiles_y
        self.starts = starts^
        self.items = items^

    def tile_count(self) -> Int:
        """Return how many tiles there are.

        Returns:
            Across times down.
        """
        return self.tiles_x * self.tiles_y

    def count(self, tile: Int) -> Int:
        """Return how many splats a tile holds.

        Args:
            tile: The tile, row by row, from 0 up to the tile count.

        Returns:
            The length of its list.
        """
        return Int(self.starts[tile + 1] - self.starts[tile])

    def at(self, tile: Int, place: Int) -> Int:
        """Return one splat of a tile.

        Args:
            tile: The tile.
            place: The place in its list, from 0 up to its count.

        Returns:
            The splat's place in the list that was binned.
        """
        return Int(self.items[Int(self.starts[tile]) + place])


def tile_count_across(pixels: Int) -> Int:
    """Return how many tiles cover a number of pixels.

    Args:
        pixels: A width or a height, in pixels.

    Returns:
        The count, rounded up.
    """
    return (pixels + SPLAT_TILE - 1) // SPLAT_TILE


def splat_tile_box(
    splat: ProjectedSplat, width: Int, height: Int
) -> SIMD[DType.int32, 4]:
    """Return the tiles that a splat reaches.

    Args:
        splat: The splat.
        width: The target's width, in pixels.
        height: The target's height, in pixels.

    Returns:
        The first and last tile across, then the first and last down, all
        inside the target. The last is before the first for a splat that
        reaches no pixel.
    """
    var reach = splat_reach(splat)
    var left = floor(splat.x - reach[0] - 0.5) - 1
    var right = ceil(splat.x + reach[0] - 0.5) + 1
    var top = floor(splat.y - reach[1] - 0.5) - 1
    var bottom = ceil(splat.y + reach[1] - 0.5) + 1
    if (
        not (left <= Float32(width - 1))
        or not (right >= 0)
        or not (top <= Float32(height - 1))
        or not (bottom >= 0)
    ):
        return SIMD[DType.int32, 4](1, 0, 1, 0)
    var first_x = Int(max(left, 0.0)) // SPLAT_TILE
    var last_x = Int(min(right, Float32(width - 1))) // SPLAT_TILE
    var first_y = Int(max(top, 0.0)) // SPLAT_TILE
    var last_y = Int(min(bottom, Float32(height - 1))) // SPLAT_TILE
    return SIMD[DType.int32, 4](
        Int32(first_x), Int32(last_x), Int32(first_y), Int32(last_y)
    )


def _count_run(
    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],
    boxes: MutPointer[Int32, MutAnyOrigin],
    width: Int,
    height: Int,
    tiles_x: Int,
    counts: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Find the tiles that a run of splats reaches, and count them.

    Args:
        splats: The splats, in draw order.
        boxes: Each splat's box, four numbers each, written for the run.
        width: The target's width.
        height: The target's height.
        tiles_x: How many tiles across.
        counts: The run's count of the splats that reach each tile.
        first: The run's first splat.
        past: One past its last.
    """
    for index in range(first, past):
        var box = splat_tile_box(splats[unsafe_offset=index], width, height)
        for lane in range(4):
            boxes[unsafe_offset=index * 4 + lane] = box[lane]
        for ty in range(Int(box[2]), Int(box[3]) + 1):
            for tx in range(Int(box[0]), Int(box[1]) + 1):
                counts[unsafe_offset=ty * tiles_x + tx] += 1


async def _count_task(
    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],
    boxes: MutPointer[Int32, MutAnyOrigin],
    width: Int,
    height: Int,
    tiles_x: Int,
    counts: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_count_run` as a task of `bin_splats`.

    Args:
        splats: The splats.
        boxes: Each splat's box.
        width: The target's width.
        height: The target's height.
        tiles_x: How many tiles across.
        counts: The run's counts.
        first: The run's first splat.
        past: One past its last.
    """
    _count_run(splats, boxes, width, height, tiles_x, counts, first, past)


def _place_run(
    items: MutPointer[Int32, MutAnyOrigin],
    boxes: MutPointer[Int32, MutAnyOrigin],
    tiles_x: Int,
    next: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Put each splat of a run among the splats of the tiles it reaches.

    Args:
        items: Each tile's splats, tile after tile.
        boxes: Each splat's box.
        tiles_x: How many tiles across.
        next: The run's next place in each tile.
        first: The run's first splat.
        past: One past its last.
    """
    for index in range(first, past):
        for ty in range(
            Int(boxes[unsafe_offset=index * 4 + 2]),
            Int(boxes[unsafe_offset=index * 4 + 3]) + 1,
        ):
            for tx in range(
                Int(boxes[unsafe_offset=index * 4]),
                Int(boxes[unsafe_offset=index * 4 + 1]) + 1,
            ):
                var tile = ty * tiles_x + tx
                items[unsafe_offset=next[unsafe_offset=tile]] = Int32(index)
                next[unsafe_offset=tile] += 1


async def _place_task(
    items: MutPointer[Int32, MutAnyOrigin],
    boxes: MutPointer[Int32, MutAnyOrigin],
    tiles_x: Int,
    next: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_place_run` as a task of `bin_splats`.

    Args:
        items: Each tile's splats.
        boxes: Each splat's box.
        tiles_x: How many tiles across.
        next: The run's next places.
        first: The run's first splat.
        past: One past its last.
    """
    _place_run(items, boxes, tiles_x, next, first, past)


def bin_splats(
    splats: List[ProjectedSplat],
    width: Int,
    height: Int,
    workers: Int = 1,
    limit: Int = SPLAT_TILE_LIMIT,
) raises -> SplatTiles:
    """Sort projected splats into the tiles they reach; see the module
    docstring.

    Args:
        splats: The splats, in the order to draw them.
        width: The target's width, in pixels, 1 or more.
        height: The target's height, in pixels, 1 or more.
        workers: How many runs of splats are counted and placed at once.
        limit: The most entries the lists may hold, at most the largest
            32-bit count.

    Returns:
        The lists. A tile's splats are in the order of `splats`, and the
        lists are the same for any count of workers.

    Raises:
        Error: If the target has no pixel, or the lists would hold more
            entries than a 32-bit count.
    """
    if width < 1 or height < 1:
        raise Error("Splat tiles: a target is at least one pixel each way")
    var tiles_x = tile_count_across(width)
    var tiles_y = tile_count_across(height)
    var tiles = tiles_x * tiles_y
    var count = len(splats)
    var runs = max(1, min(workers, count // SPLAT_TILE_RUN))
    var boxes = List[Int32](length=count * 4, fill=0)
    var counts = List[Int](length=runs * tiles, fill=0)
    var splats_at = splats.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var box_at = boxes.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var count_at = counts.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    if runs == 1:
        _count_run(
            splats_at, box_at, width, height, tiles_x, count_at, 0, count
        )
    else:
        var counting = TaskGroup()
        for run in range(runs):  # pragma: no branch
            counting.create_task(
                _count_task(
                    splats_at,
                    box_at,
                    width,
                    height,
                    tiles_x,
                    count_at.unsafe_offset(run * tiles),
                    run * count // runs,
                    (run + 1) * count // runs,
                )
            )
        counting.wait()
    # Each run's first place in each tile: tile by tile, run by run.
    var starts = List[Int32](length=tiles + 1, fill=0)
    var sum = 0
    for tile in range(tiles):  # pragma: no branch
        starts[tile] = Int32(min(sum, limit))
        for run in range(runs):  # pragma: no branch
            var here = counts[run * tiles + tile]
            counts[run * tiles + tile] = sum
            sum += here
    if sum > limit:
        raise Error("Splat tiles: more entries than a 32-bit count holds")
    starts[tiles] = Int32(sum)
    var items = List[Int32](length=sum, fill=0)
    var item_at = items.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    if runs == 1:
        _place_run(item_at, box_at, tiles_x, count_at, 0, count)
    else:
        var placing = TaskGroup()
        for run in range(runs):  # pragma: no branch
            placing.create_task(
                _place_task(
                    item_at,
                    box_at,
                    tiles_x,
                    count_at.unsafe_offset(run * tiles),
                    run * count // runs,
                    (run + 1) * count // runs,
                )
            )
        placing.wait()
    # The tasks read the lists through pointers the compiler cannot see.
    # These reads keep them alive until every task has finished.
    _ = len(splats)
    _ = len(boxes)
    _ = len(counts)
    _ = len(items)
    return SplatTiles(tiles_x, tiles_y, starts^, items^)
