# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.gpu`.

The important property is not that the kernel runs but that it agrees with the
CPU rasterizer exactly, pixel for pixel. Two implementations of the same edge
test can easily drift at the boundary, and a triangle whose edge falls half a
pixel differently is a bug that no aggregate check would catch.

Tests needing hardware return early when none is present, so the suite passes
on a machine without a GPU rather than failing for the wrong reason.

Images are kept small deliberately. Comparing two renders means reading every
pixel of both, and `Framebuffer.get_pixel` is instrumented when the coverage
tool runs, so each pixel costs a record written to stderr. A 320x240
comparison produced 112 MB of them and dominated the entire coverage run.
"""

from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from render.gpu import available, pack, render
from render.rasterizer import Triangle, rasterize
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

comptime BACKGROUND = Color(20, 24, 32)
comptime FOREGROUND = Color(255, 128, 32)


def count_mismatches(left: Framebuffer, right: Framebuffer) raises -> Int:
    """Return how many pixels differ between two same-sized framebuffers.

    Args:
        left: First image.
        right: Second image.

    Returns:
        The number of differing pixels.

    Raises:
        Error: If a coordinate is out of bounds.
    """
    var differences = 0
    for y in range(left.height):
        for x in range(left.width):
            var a = left.get_pixel(x, y)
            var b = right.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b or a.a != b.a:
                differences += 1
    return differences


def cpu_render(
    triangle: Triangle, width: Int, height: Int
) raises -> Framebuffer:
    """Return the CPU rasterizer's output for the same inputs.

    Args:
        triangle: Screen-space triangle to fill.
        width: Image width.
        height: Image height.

    Returns:
        The rendered framebuffer.

    Raises:
        Error: If the dimensions are invalid.
    """
    var target = Framebuffer(width, height, BACKGROUND)
    rasterize(triangle, target, FOREGROUND)
    return target^


def test_colors_pack_into_a_big_endian_word() raises:
    assert_equal(pack(Color(0xAA, 0xBB, 0xCC, 0xDD)), UInt32(0xAABBCCDD))
    assert_equal(pack(Color(0, 0, 0, 0)), UInt32(0))
    assert_equal(pack(Color(255, 255, 255, 255)), UInt32(0xFFFFFFFF))


def test_alpha_survives_packing() raises:
    assert_equal(pack(Color(1, 2, 3, 128)) & UInt32(0xFF), UInt32(128))


def test_availability_is_answerable() raises:
    # Whatever the answer, asking must not raise.
    var present = available()
    assert_true(present or not present)


def test_gpu_matches_the_cpu_rasterizer() raises:
    if not available():
        return
    var triangle = Triangle(
        Vector2(50, 180), Vector2(160, 40), Vector2(275, 190)
    )
    var gpu = render(triangle, 80, 60, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 80, 60)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_gpu_matches_the_cpu_on_a_clockwise_triangle() raises:
    if not available():
        return
    # Opposite winding takes the other side of the kernel's area test.
    var triangle = Triangle(
        Vector2(50, 180), Vector2(275, 190), Vector2(160, 40)
    )
    var gpu = render(triangle, 64, 48, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 64, 48)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_gpu_matches_the_cpu_on_a_degenerate_triangle() raises:
    if not available():
        return
    # Three collinear points have zero area and must cover nothing.
    var triangle = Triangle(Vector2(0, 0), Vector2(10, 10), Vector2(20, 20))
    var gpu = render(triangle, 32, 32, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 32, 32)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_gpu_matches_the_cpu_when_the_triangle_is_offscreen() raises:
    if not available():
        return
    var triangle = Triangle(
        Vector2(-99, -99), Vector2(-80, -99), Vector2(-99, -80)
    )
    var gpu = render(triangle, 32, 32, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 32, 32)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_they_agree_on_pixels_lying_exactly_on_an_edge() raises:
    # Corners on whole pixels put sample points exactly on the edges, which is
    # where the fill rule decides and where a difference between the two
    # implementations would show. Before both used the same fixed-point rule,
    # these tests passed only because their triangles avoided such pixels.
    if not available():
        return
    var triangle = Triangle(Vector2(4, 4), Vector2(28, 4), Vector2(28, 20))
    var gpu = render(triangle, 32, 24, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 32, 24)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_they_agree_on_both_halves_of_a_shared_diagonal() raises:
    # The two triangles of a quad, drawn into one image by each renderer.
    if not available():
        return
    var upper = Triangle(Vector2(2, 2), Vector2(26, 2), Vector2(26, 18))
    var gpu = render(upper, 32, 24, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(upper, 32, 24)
    assert_equal(count_mismatches(cpu, gpu), 0)
    var lower = Triangle(Vector2(2, 2), Vector2(26, 18), Vector2(2, 18))
    var gpu_lower = render(lower, 32, 24, BACKGROUND, FOREGROUND)
    var cpu_lower = cpu_render(lower, 32, 24)
    assert_equal(count_mismatches(cpu_lower, gpu_lower), 0)


def test_size_not_divisible_by_the_tile_is_handled() raises:
    if not available():
        return
    # 17x13 leaves a partial tile on both edges, which the kernel must clip.
    var triangle = Triangle(Vector2(2, 11), Vector2(8, 2), Vector2(15, 12))
    var gpu = render(triangle, 17, 13, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 17, 13)
    assert_equal(gpu.width, 17)
    assert_equal(gpu.height, 13)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_zero_width_is_rejected() raises:
    with assert_raises():
        _ = render(
            Triangle(Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)),
            0,
            8,
            BACKGROUND,
            FOREGROUND,
        )


def test_negative_height_is_rejected() raises:
    with assert_raises():
        _ = render(
            Triangle(Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)),
            8,
            -1,
            BACKGROUND,
            FOREGROUND,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
