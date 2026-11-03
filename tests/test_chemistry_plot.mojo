# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the charts of `extensions.chemistry`.

The ticks must be round and lie in the range. The axes must map the data
box onto the pixel box with y up. The drawing calls must color the pixels
they cover, and leave the others alone.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.maps import LabelMap
from extensions.chemistry.plot import Axes, nice_ticks, tick_text
from extensions.visual.overlay import Overlay
from render.framebuffer import Color, Framebuffer

comptime FONT = "assets/ttf/kenpixel.ttf"
comptime NAN = nan[DType.float64]()
comptime BLACK = Color(0, 0, 0)
comptime WHITE = Color(255, 255, 255)
comptime RED = Color(255, 0, 0)
comptime BLUE = Color(0, 0, 255)


def _axes() raises -> Axes:
    return Axes(20, 10, 120, 90, 0, 1000, -10, 10)


def test_ticks() raises:
    # A raw step of 243 rounds up to 500.
    var ticks = nice_ticks(300, 2000, 8)
    assert_equal(len(ticks), 4)
    assert_almost_equal(ticks[0], 500, atol=0)
    assert_almost_equal(ticks[3], 2000, atol=0)
    # A raw step of 0.7 rounds up to 1: the next step after 5 times 0.1.
    var tens = nice_ticks(0, 6.3, 10)
    assert_almost_equal(tens[1] - tens[0], 1.0, atol=1e-12)
    var twos = nice_ticks(-1, 1, 11)
    assert_almost_equal(twos[1] - twos[0], 0.2, atol=1e-12)
    var fives = nice_ticks(0, 0.2, 5)
    assert_almost_equal(fives[1] - fives[0], 0.05, atol=1e-12)
    for bad in [inf[DType.float64](), NAN]:
        with assert_raises(contains="finite and ascend"):
            _ = nice_ticks(0, bad, 5)
        with assert_raises(contains="finite and ascend"):
            _ = nice_ticks(bad, 1, 5)
    with assert_raises(contains="finite and ascend"):
        _ = nice_ticks(1, 1, 5)
    with assert_raises(contains="2 to 50 ticks"):
        _ = nice_ticks(0, 1, 1)
    with assert_raises(contains="2 to 50 ticks"):
        _ = nice_ticks(0, 1, 51)


def test_tick_text() raises:
    assert_equal(tick_text(1500, 500), "1500")
    assert_equal(tick_text(0.25, 0.05), "0.25")
    assert_equal(tick_text(0.05, 0.05), "0.05")
    assert_equal(tick_text(-5, 1), "-5")
    assert_equal(tick_text(-0.0001, 1), "0")
    assert_equal(tick_text(-1.5, 0.5), "-1.5")
    # The decimals stop at twelve.
    assert_equal(tick_text(0, 1e-15), "0.000000000000")


def test_mapping() raises:
    var axes = _axes()
    assert_almost_equal(axes.x(0), 20, atol=1e-12)
    assert_almost_equal(axes.x(1000), 120, atol=1e-12)
    assert_almost_equal(axes.y(-10), 90, atol=1e-12)
    assert_almost_equal(axes.y(10), 10, atol=1e-12)
    assert_almost_equal(axes.y(0), 50, atol=1e-12)
    var values: List[Float64] = [20, 10, 120, 90, 0, 1, 0, 1]
    for i in range(8):
        var copy = values.copy()
        copy[i] = NAN
        with assert_raises(contains="must be finite"):
            _ = Axes(
                copy[0],
                copy[1],
                copy[2],
                copy[3],
                copy[4],
                copy[5],
                copy[6],
                copy[7],
            )
    with assert_raises(contains="size in pixels"):
        _ = Axes(20, 10, 20, 90, 0, 1, 0, 1)
    with assert_raises(contains="size in pixels"):
        _ = Axes(20, 10, 120, 10, 0, 1, 0, 1)
    with assert_raises(contains="range must ascend"):
        _ = Axes(20, 10, 120, 90, 1, 1, 0, 1)
    with assert_raises(contains="range must ascend"):
        _ = Axes(20, 10, 120, 90, 0, 1, 1, 1)


def test_drawing() raises:
    var axes = _axes()
    var frame = Framebuffer(140, 120, BLACK)
    var font = Overlay.from_ttf(FONT)
    axes.frame(frame, font, "T / K", "G", 8, WHITE)
    # The bottom edge of the box is drawn, and the middle is not.
    assert_true(frame.get_pixel(70, 90).r > 0)
    assert_equal(frame.get_pixel(70, 50).r, 0)
    axes.line(frame, [0.0, 1000.0], [0.0, 0.0], 2, RED)
    assert_equal(frame.get_pixel(70, 50).r, 255)
    axes.band(frame, 0, 100, 5, 10, BLUE)
    assert_equal(frame.get_pixel(22, 15).b, 255)
    axes.line(frame, List[Float64](), List[Float64](), 2, RED)
    # A step of 0.1 has no multiple between 0.11 and 0.19, so no tick.
    var bare = Axes(20, 10, 120, 90, 0.11, 0.19, 0.11, 0.19)
    var empty = Framebuffer(140, 120, BLACK)
    bare.frame(empty, font, "x", "y", 8, WHITE, ticks=2)
    assert_equal(empty.get_pixel(70, 50).r, 0)
    # A chart of rows has no y numbers: the y axis's tick at 0 is absent.
    var rows = Framebuffer(140, 120, BLACK)
    axes.frame(rows, font, "x", "", 8, WHITE, y_numbers=False)
    assert_equal(rows.get_pixel(23, 50).r, 0)
    assert_true(frame.get_pixel(23, 50).r > 0)
    with assert_raises(contains="one y value per x"):
        axes.line(frame, [0.0], List[Float64](), 2, RED)


def test_cells() raises:
    var axes = Axes(0, 0, 40, 40, 0, 1, 0, 1)
    var map = LabelMap(["a", "b"], 0, 1, 0, 1, 3, 2)
    # Row 0 is a, a, b; row 1 is b, b, b.
    map.labels[2] = 1
    map.labels[3] = 1
    map.labels[4] = 1
    map.labels[5] = 1
    var frame = Framebuffer(40, 40, BLACK)
    axes.cells(frame, map, [RED, BLUE])
    assert_equal(frame.get_pixel(5, 35).r, 255)
    assert_equal(frame.get_pixel(35, 35).b, 255)
    assert_equal(frame.get_pixel(5, 5).b, 255)
    with assert_raises(contains="has no color"):
        axes.cells(frame, map, [RED])
    map.labels[0] = -1
    with assert_raises(contains="has no color"):
        axes.cells(frame, map, [RED, BLUE])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
