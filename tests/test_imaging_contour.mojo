# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Outlines of a label in a slice, and their drawing."""

from extensions.imaging.contour import Outline, draw_outlines, slice_outlines
from extensions.imaging.ids import (
    BACKGROUND,
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    SliceAxis,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.overlay import draw_line, render_slice, zoom_image
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.sdf.vector import V3
from units.si import Area64, Length64, METER, SQUARE_METER

comptime SQUARE_MM = 1e-6


def _map(
    nx: Int, ny: Int, nz: Int, sx: Float64, sy: Float64, sz: Float64
) raises -> LabelMap:
    return LabelMap(
        ImageVolume(
            nx,
            ny,
            nz,
            Length64(sx, MILLIMETER64),
            Length64(sy, MILLIMETER64),
            Length64(sz, MILLIMETER64),
        )
    )


def test_one_pixel_and_a_rectangle() raises:
    var map = _map(6, 5, 3, 1, 1, 1)
    var one = LabelId(1)
    map.set(2, 2, 1, one)
    var dot = slice_outlines(map, one, K_AXIS, 1)
    assert_equal(len(dot), 1)
    # A diamond through the middles of the pixel's sides.
    assert_equal(len(dot[0].points), 4)
    assert_almost_equal(dot[0].area.value / SQUARE_MM, 0.5)
    assert_almost_equal(dot[0].length.to(MILLIMETER64), 4 * sqrt(0.5))
    for p in dot[0].points:
        assert_equal(p.z, 1.0)
        var d = abs(p.x - 2) + abs(p.y - 2)
        assert_almost_equal(d, 0.5)
    # No outline in a slice without the label.
    assert_equal(len(slice_outlines(map, one, K_AXIS, 0)), 0)
    # A rectangle of 3 by 2 pixels of 0.5 by 0.8 mm cuts its four corners.
    var flat = _map(6, 5, 1, 0.5, 0.8, 2)
    for y in [1, 2]:
        for x in [1, 2, 3]:
            flat.set(x, y, 0, one)
    var box = slice_outlines(flat, one, K_AXIS, 0)
    assert_equal(len(box), 1)
    assert_almost_equal(box[0].area.value / SQUARE_MM, 5.5 * 0.5 * 0.8)
    var corner = sqrt(0.25**2 + 0.4**2)
    assert_almost_equal(
        box[0].length.to(MILLIMETER64), 2 * 2 * 0.5 + 2 * 1 * 0.8 + 4 * corner
    )


def test_holes_corners_and_edges() raises:
    var map = _map(7, 7, 1, 1, 1, 1)
    var one = LabelId(1)
    for y in range(1, 6):
        for x in range(1, 6):
            if x != 3 or y != 3:
                map.set(x, y, 0, one)
    var ring = slice_outlines(map, one, K_AXIS, 0)
    assert_equal(len(ring), 2)
    # The outer outline first, then the hole, which turns the other way.
    assert_almost_equal(ring[0].area.value / SQUARE_MM, 25 - 0.5)
    assert_almost_equal(ring[1].area.value / SQUARE_MM, -0.5)
    # Two pixels that share a corner only have an outline each.
    var pair = _map(4, 4, 1, 1, 1, 1)
    pair.set(1, 1, 0, one)
    pair.set(2, 2, 0, one)
    var two = slice_outlines(pair, one, K_AXIS, 0)
    assert_equal(len(two), 2)
    assert_almost_equal(two[0].area.value / SQUARE_MM, 0.5)
    assert_almost_equal(two[1].area.value / SQUARE_MM, 0.5)
    # Two pixels that share a side have one.
    pair.set(2, 1, 0, one)
    assert_equal(len(slice_outlines(pair, one, K_AXIS, 0)), 1)
    # A label on the slice's edge closes past it.
    var edge = _map(3, 3, 1, 1, 1, 1)
    for index in range(9):
        edge.labels[index] = 1
    var full = slice_outlines(edge, one, K_AXIS, 0)
    assert_equal(len(full), 1)
    assert_almost_equal(full[0].area.value / SQUARE_MM, 9 - 0.5)
    var least = 0.0
    for p in full[0].points:
        least = min(least, min(p.x, p.y))
    assert_almost_equal(least, -0.5)


def test_every_axis() raises:
    # One block of 2 by 3 by 4 voxels, cut across each axis.
    var map = _map(5, 6, 7, 0.5, 0.8, 2)
    var one = LabelId(4)
    for k in range(2, 6):
        for j in range(1, 4):
            for i in range(1, 3):
                map.set(i, j, k, one)
    # Across k: 2 by 3 pixels of 0.5 by 0.8 mm.
    var across_k = slice_outlines(map, one, K_AXIS, 3)
    assert_almost_equal(across_k[0].area.value / SQUARE_MM, 5.5 * 0.5 * 0.8)
    assert_equal(across_k[0].points[0].z, 3.0)
    # Across j: 2 by 4 pixels of 0.5 by 2 mm.
    var across_j = slice_outlines(map, one, J_AXIS, 2)
    assert_almost_equal(across_j[0].area.value / SQUARE_MM, 7.5 * 0.5 * 2)
    assert_equal(across_j[0].points[0].y, 2.0)
    # Across i: 3 by 4 pixels of 0.8 by 2 mm.
    var across_i = slice_outlines(map, one, I_AXIS, 1)
    assert_almost_equal(across_i[0].area.value / SQUARE_MM, 11.5 * 0.8 * 2)
    assert_equal(across_i[0].points[0].x, 1.0)
    assert_equal(len(slice_outlines(map, one, I_AXIS, 4)), 0)


def test_drawing() raises:
    var map = _map(5, 5, 1, 1, 1, 1)
    var one = LabelId(1)
    map.set(2, 2, 0, one)
    var image = zoom_image(
        render_slice(
            ImageVolume(
                5,
                5,
                1,
                Length64(1, MILLIMETER64),
                Length64(1, MILLIMETER64),
                Length64(1, MILLIMETER64),
            ),
            K_AXIS,
            0,
        ),
        4,
    )
    assert_equal(image.width, 20)
    var before = image.get_pixel(10, 10)
    var yellow = Rgba(1, 1, 0, 1)
    draw_outlines(image, K_AXIS, slice_outlines(map, one, K_AXIS, 0), 4, yellow)
    # The diamond runs from (12, 10) to (10, 12) on the zoomed image, about
    # the voxel's center at (9.5, 9.5).
    var on = image.get_pixel(11, 11)
    assert_equal(on.r, 255)
    assert_equal(on.b, 0)
    var center = image.get_pixel(10, 10)
    assert_equal(center.r, before.r)
    # Every axis draws.
    var tall = _map(1, 5, 5, 1, 1, 1)
    tall.set(0, 2, 2, one)
    var side = Framebuffer(5, 5, Color(0, 0, 0))
    draw_outlines(side, I_AXIS, slice_outlines(tall, one, I_AXIS, 0), 1, yellow)
    var wide = _map(5, 1, 5, 1, 1, 1)
    wide.set(2, 0, 2, one)
    var front = Framebuffer(5, 5, Color(0, 0, 0))
    draw_outlines(
        front, J_AXIS, slice_outlines(wide, one, J_AXIS, 0), 1, yellow
    )
    assert_equal(side.get_pixel(3, 2).r, 255)
    assert_equal(front.get_pixel(3, 2).r, 255)
    # No outline, or an outline without points, draws nothing.
    var blank = Framebuffer(3, 3, Color(0, 0, 0))
    draw_outlines(blank, K_AXIS, List[Outline](), 1, yellow)
    var empty = List[Outline]()
    empty.append(
        Outline(List[V3](), Length64(0, METER), Area64(0, SQUARE_METER))
    )
    draw_outlines(blank, K_AXIS, empty, 1, yellow)
    for y in range(3):
        for x in range(3):
            assert_equal(blank.get_pixel(x, y).r, 0)


def test_zoom_and_lines() raises:
    var small = Framebuffer(2, 2, Color(10, 20, 30))
    small.set_pixel(1, 1, Color(200, 100, 50))
    var big = zoom_image(small, 3)
    assert_equal(big.width, 6)
    assert_equal(big.height, 6)
    assert_equal(big.get_pixel(5, 5).r, 200)
    assert_equal(big.get_pixel(3, 3).g, 100)
    assert_equal(big.get_pixel(2, 2).r, 10)
    # A line past the edge draws its part inside.
    draw_line(big, -3, 0, 8, 0, Rgba(0, 1, 0, 1))
    assert_equal(big.get_pixel(0, 0).g, 255)
    assert_equal(big.get_pixel(5, 0).g, 255)
    with assert_raises(contains="1 to 64"):
        _ = zoom_image(small, 0)
    with assert_raises(contains="1 to 64"):
        _ = zoom_image(small, 65)


def test_refusals() raises:
    var map = _map(3, 4, 5, 1, 1, 1)
    var one = LabelId(1)
    with assert_raises(contains="background"):
        _ = slice_outlines(map, BACKGROUND, K_AXIS, 0)
    with assert_raises(contains="label"):
        _ = slice_outlines(map, LabelId(256), K_AXIS, 0)
    with assert_raises(contains="axis"):
        _ = slice_outlines(map, one, SliceAxis(3), 0)
    with assert_raises(contains="slice index"):
        _ = slice_outlines(map, one, K_AXIS, 5)
    with assert_raises(contains="slice index"):
        _ = slice_outlines(map, one, J_AXIS, -1)
    with assert_raises(contains="slice index"):
        _ = slice_outlines(map, one, I_AXIS, 3)
    var image = Framebuffer(3, 4, Color(0, 0, 0))
    var none = List[Outline]()
    with assert_raises(contains="axis"):
        draw_outlines(image, SliceAxis(-1), none, 1, Rgba(1, 1, 1, 1))
    with assert_raises(contains="zoom"):
        draw_outlines(image, K_AXIS, none, 0, Rgba(1, 1, 1, 1))
    with assert_raises(contains="zoom"):
        draw_outlines(image, K_AXIS, none, 65, Rgba(1, 1, 1, 1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
