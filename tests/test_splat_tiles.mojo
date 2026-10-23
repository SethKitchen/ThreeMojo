# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.splat_tiles`, the lists of splats for each tile.

The lists are held to three things: they are the splats whose boxes reach
the tile, in draw order, as a brute-force walk finds them; they are the
same for every count of workers; and every pixel that a splat gives an
opacity is in a tile of its box.
"""

from render.splat_tiles import (
    SPLAT_TILE,
    SplatTiles,
    bin_splats,
    splat_tile_box,
    tile_count_across,
)
from render.splatrule import ProjectedSplat, splat_alpha
from std.math import cos, sin
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

comptime WIDTH = 70
comptime HEIGHT = 50


def _splat(
    x: Float32, y: Float32, scale1: Float32, scale2: Float32, angle: Float32
) -> ProjectedSplat:
    """Return a splat at a pixel, turned by an angle."""
    return ProjectedSplat(
        x,
        y,
        0.5,
        cos(angle),
        sin(angle),
        scale1,
        scale2,
        0.5,
        0.5,
        0.5,
        0.8,
    )


struct _Random:
    """A small repeatable source of numbers from 0 up to 1."""

    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def next(mut self) -> Float32:
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        return Float32(Int((self.state >> 40) & 0xFFFFFF)) / Float32(16777216)


def _splats(count: Int, seed: UInt64) -> List[ProjectedSplat]:
    """Return splats all over and around the target, of every size."""
    var random = _Random(seed)
    var out = List[ProjectedSplat]()
    for _ in range(count):
        var x = random.next() * Float32(WIDTH + 40) - 20
        var y = random.next() * Float32(HEIGHT + 40) - 20
        var small = 0.3 + random.next() * 4
        var wide = 0.3 + random.next() * 9
        out.append(_splat(x, y, small, wide, random.next() * 6.2831853))
    return out^


def _brute(
    splats: List[ProjectedSplat], tile: SplatTiles, at: Int
) -> List[Int]:
    """Return the splats whose boxes reach a tile, by walking all of them."""
    var tx = at % tile.tiles_x
    var ty = at // tile.tiles_x
    var out = List[Int]()
    for index in range(len(splats)):
        var box = splat_tile_box(splats[index], WIDTH, HEIGHT)
        if (
            Int(box[0]) <= tx
            and tx <= Int(box[1])
            and Int(box[2]) <= ty
            and ty <= Int(box[3])
        ):
            out.append(index)
    return out^


def test_the_tiles_cover_the_target() raises:
    """A target of 70 by 50 pixels has 5 by 4 tiles."""
    assert_equal(SPLAT_TILE, 16)
    assert_equal(tile_count_across(1), 1)
    assert_equal(tile_count_across(16), 1)
    assert_equal(tile_count_across(17), 2)
    assert_equal(tile_count_across(WIDTH), 5)
    assert_equal(tile_count_across(HEIGHT), 4)


def test_a_splats_box_is_its_reach_with_a_pixel_to_spare() raises:
    """A splat in a tile's middle reaches one tile; one on an edge, two;
    one off the target, none."""
    var middle = splat_tile_box(_splat(8, 8, 1, 1, 0), WIDTH, HEIGHT)
    assert_equal(middle, SIMD[DType.int32, 4](0, 0, 0, 0))
    var edge = splat_tile_box(_splat(16, 8, 1, 1, 0), WIDTH, HEIGHT)
    assert_equal(edge, SIMD[DType.int32, 4](0, 1, 0, 0))
    var corner = splat_tile_box(_splat(16, 16, 1, 1, 0), WIDTH, HEIGHT)
    assert_equal(corner, SIMD[DType.int32, 4](0, 1, 0, 1))
    var grazing = splat_tile_box(_splat(-10, 8, 6, 6, 0), WIDTH, HEIGHT)
    assert_equal(grazing, SIMD[DType.int32, 4](0, 0, 0, 1))
    var far = splat_tile_box(_splat(-100, 8, 1, 1, 0), WIDTH, HEIGHT)
    assert_true(far[1] < far[0])
    var past = splat_tile_box(_splat(500, 8, 1, 1, 0), WIDTH, HEIGHT)
    assert_true(past[1] < past[0])
    var above = splat_tile_box(_splat(8, -100, 1, 1, 0), WIDTH, HEIGHT)
    assert_true(above[3] < above[2])
    var below = splat_tile_box(_splat(8, 500, 1, 1, 0), WIDTH, HEIGHT)
    assert_true(below[3] < below[2])
    var wide = splat_tile_box(_splat(35, 25, 200, 200, 0), WIDTH, HEIGHT)
    assert_equal(wide, SIMD[DType.int32, 4](0, 4, 0, 3))


def test_a_tile_lists_its_splats_in_draw_order() raises:
    """Each tile holds the splats that reach it, as a walk of all of them
    finds them."""
    var splats = _splats(300, 7)
    var tiles = bin_splats(splats, WIDTH, HEIGHT)
    assert_equal(tiles.tile_count(), 20)
    assert_equal(len(tiles.starts), 21)
    var total = 0
    for tile in range(tiles.tile_count()):
        var want = _brute(splats, tiles, tile)
        assert_equal(tiles.count(tile), len(want))
        for place in range(len(want)):
            assert_equal(tiles.at(tile, place), want[place])
        total += len(want)
    assert_equal(total, len(tiles.items))
    assert_true(total > 300)


def test_every_count_of_workers_gives_the_same_lists() raises:
    """With runs of 4096 splats, 1, 3 and 24 workers share 20000 splats
    out differently and agree on every list."""
    var splats = _splats(20000, 11)
    var one = bin_splats(splats, WIDTH, HEIGHT, 1)
    for workers in [3, 24]:
        var many = bin_splats(splats, WIDTH, HEIGHT, workers)
        assert_equal(len(many.starts), len(one.starts))
        assert_equal(len(many.items), len(one.items))
        for at in range(len(one.starts)):
            assert_equal(many.starts[at], one.starts[at])
        for at in range(len(one.items)):
            assert_equal(many.items[at], one.items[at])


def test_every_pixel_a_splat_colors_is_in_its_tiles() raises:
    """A pixel where `splat_alpha` is above zero lies in a tile of the
    splat's box."""
    var splats = _splats(60, 5)
    for index in range(len(splats)):
        var box = splat_tile_box(splats[index], WIDTH, HEIGHT)
        for y in range(HEIGHT):
            for x in range(WIDTH):
                if splat_alpha(splats[index], x, y) > 0:
                    var tx = x // SPLAT_TILE
                    var ty = y // SPLAT_TILE
                    assert_true(Int(box[0]) <= tx and tx <= Int(box[1]))
                    assert_true(Int(box[2]) <= ty and ty <= Int(box[3]))


def test_no_splat_and_no_target_are_handled() raises:
    """An empty list gives empty tiles, and a target with no pixel is an
    error."""
    var none = bin_splats(List[ProjectedSplat](), WIDTH, HEIGHT)
    assert_equal(len(none.items), 0)
    assert_equal(none.count(0), 0)
    with assert_raises(contains="at least one pixel each way"):
        _ = bin_splats(List[ProjectedSplat](), 0, HEIGHT)
    with assert_raises(contains="at least one pixel each way"):
        _ = bin_splats(List[ProjectedSplat](), WIDTH, 0)


def test_lists_longer_than_the_limit_are_refused() raises:
    """Three splats in one tile make three entries, and a limit of two
    refuses them."""
    var splats = List[ProjectedSplat]()
    for _ in range(3):
        splats.append(_splat(8, 8, 1, 1, 0))
    assert_equal(len(bin_splats(splats, WIDTH, HEIGHT, limit=100).items), 3)
    with assert_raises(contains="more entries than a 32-bit count"):
        _ = bin_splats(splats, WIDTH, HEIGHT, limit=2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
