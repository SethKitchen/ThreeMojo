# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.gpu_splat_tiles` on a device: the tiled fill must give
the picture of the host's `rasterize_splats`.

Splats of every size, turned every way, over and around a target that is not
a whole number of tiles wide, are drawn on both. A channel may differ by one
level of 255, where the host and the device round a product differently, and
nearly every channel must be equal. A tile that holds more splats than a
block stages at once must read them in more than one batch, and is drawn
here too.
"""

from render.framebuffer import Color
from render.gpu_splat_tiles import GpuSplatTiles, gpu_splat_tiles_available
from render.splat_raster import rasterize_splats
from render.splatrule import ProjectedSplat
from render.working_space import resolve_srgb_working, srgb_working_target
from std.math import cos, sin
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

comptime WIDTH = 70
comptime HEIGHT = 50
comptime BACKGROUND = Color(7, 8, 15)


struct _Random:
    """A small repeatable source of numbers from 0 up to 1."""

    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def next(mut self) -> Float32:
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        return Float32(Int((self.state >> 40) & 0xFFFFFF)) / Float32(16777216)


def _splats(count: Int, seed: UInt64, spread: Float32) -> List[ProjectedSplat]:
    """Return splats scattered over and around the target, in a depth order
    that is the order they are made in."""
    var random = _Random(seed)
    var out = List[ProjectedSplat]()
    for index in range(count):
        var x = random.next() * spread * Float32(WIDTH + 40) - 20
        var y = random.next() * spread * Float32(HEIGHT + 40) - 20
        var angle = random.next() * 6.2831853
        out.append(
            ProjectedSplat(
                x,
                y,
                Float32(index) / Float32(count),
                cos(angle),
                sin(angle),
                0.5 + random.next() * 3,
                0.5 + random.next() * 6,
                random.next(),
                random.next(),
                random.next(),
                0.2 + 0.7 * random.next(),
            )
        )
    return out^


def _same_picture(splats: List[ProjectedSplat]) raises -> Tuple[Int, Int]:
    """Draw splats on the host and the device, and count how many channels
    differ, and by how much at most."""
    var host = srgb_working_target(WIDTH, HEIGHT, BACKGROUND)
    rasterize_splats(host, splats)
    var want = resolve_srgb_working(host)
    var device = GpuSplatTiles()
    var got = device.draw(splats, WIDTH, HEIGHT, BACKGROUND, 4)
    assert_equal(got.width, WIDTH)
    assert_equal(got.height, HEIGHT)
    var differing = 0
    var worst = 0
    for at in range(WIDTH * HEIGHT * 4):
        var step = abs(Int(want.pixels[at]) - Int(got.pixels[at]))
        if step > 0:
            differing += 1
        worst = max(worst, step)
    return (differing, worst)


def test_the_device_draws_the_picture_of_the_host() raises:
    """Eighty splats: no channel is more than a level off, and nearly all
    are exact."""
    if not gpu_splat_tiles_available():
        return
    var found = _same_picture(_splats(80, 3, 1.0))
    assert_true(found[1] <= 1)
    assert_true(found[0] * 100 < WIDTH * HEIGHT * 4)


def test_a_crowded_tile_is_read_in_batches() raises:
    """Three thousand splats on a fifth of the target put well over 256 in a
    tile, so a block stages them more than once."""
    if not gpu_splat_tiles_available():
        return
    var found = _same_picture(_splats(3000, 9, 0.2))
    assert_true(found[1] <= 1)
    assert_true(found[0] * 100 < WIDTH * HEIGHT * 4)


def test_no_splat_is_the_background() raises:
    """With nothing to draw, every pixel is the clear color."""
    if not gpu_splat_tiles_available():
        return
    var device = GpuSplatTiles()
    var got = device.draw(List[ProjectedSplat](), WIDTH, HEIGHT, BACKGROUND)
    for at in range(WIDTH * HEIGHT):
        assert_equal(got.pixels[at * 4], 7)
        assert_equal(got.pixels[at * 4 + 1], 8)
        assert_equal(got.pixels[at * 4 + 2], 15)
        assert_equal(got.pixels[at * 4 + 3], 255)


def test_a_device_draws_frame_after_frame_and_grows() raises:
    """One fill object draws a small view and then a larger one."""
    if not gpu_splat_tiles_available():
        return
    var device = GpuSplatTiles()
    var small = _splats(20, 1, 1.0)
    var large = _splats(2000, 2, 1.0)
    _ = device.draw(small, WIDTH, HEIGHT, BACKGROUND)
    var big = device.draw(large, WIDTH * 2, HEIGHT * 2, BACKGROUND, 2)
    assert_equal(big.width, WIDTH * 2)
    _ = device.draw(small, WIDTH, HEIGHT, BACKGROUND)


def test_the_background_must_be_opaque() raises:
    """A clear color with alpha is refused: the picture is opaque."""
    if not gpu_splat_tiles_available():
        return
    var device = GpuSplatTiles()
    with assert_raises(contains="needs an opaque background"):
        _ = device.draw(
            List[ProjectedSplat](), WIDTH, HEIGHT, Color(7, 8, 15, 200)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
