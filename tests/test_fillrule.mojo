# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.fillrule`.

This module exists because the CPU rasterizer and the GPU kernel must decide
coverage identically, and they now do so by calling the *same* code rather than
two copies of it. That closes one failure mode and opens another: a CPU/GPU
parity test can no longer catch a bug in here, because both sides would be
wrong together and agree perfectly.

So every expectation below is worked out from the definitions rather than read
off the implementation, and the two properties the design actually rests on —
exact negation, and each shared edge belonging to exactly one triangle — are
asserted directly.
"""

from render.fillrule import (
    SUBPIXEL,
    SUBPIXEL_BITS,
    bias,
    edge_at,
    is_top_left,
    sample,
    snap,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true


# --- the grid ---------------------------------------------------------------


def test_the_grid_is_sixteen_steps_to_the_pixel() raises:
    assert_equal(SUBPIXEL_BITS, 4)
    assert_equal(SUBPIXEL, 16)


def test_snap_rounds_to_the_nearest_grid_step() raises:
    # floor(value * 16 + 0.5), worked out by hand.
    assert_equal(snap(0.0), 0)
    assert_equal(snap(1.0), 16)
    assert_equal(snap(0.5), 8)
    assert_equal(snap(2.5), 40)
    # A sixteenth of a pixel is exactly one step.
    assert_equal(snap(1.0 / 16.0), 1)
    # Just under half a step rounds down, just over rounds up.
    assert_equal(snap(0.03), 0)
    assert_equal(snap(0.04), 1)


def test_snap_handles_coordinates_left_of_the_origin() raises:
    # Off-screen geometry is ordinary, so negatives must not be a special
    # case. floor(-1 * 16 + 0.5) = floor(-15.5) = -16.
    assert_equal(snap(-1.0), -16)
    assert_equal(snap(-0.5), -8)


def test_sample_lands_on_the_pixel_centre() raises:
    # Half a pixel in, on the same grid: sampling at the corner would put the
    # sample point exactly on shared edges for every pixel.
    assert_equal(sample(0), SUBPIXEL // 2)
    assert_equal(sample(0), 8)
    assert_equal(sample(1), 24)
    assert_equal(sample(3), 56)


# --- the edge function ------------------------------------------------------


def test_edge_is_positive_on_one_side_and_negative_on_the_other() raises:
    # a->b points along +x; screen y runs downwards.
    var above = edge_at(0, 0, 16, 0, 8, -16)
    var below = edge_at(0, 0, 16, 0, 8, 16)
    assert_true(above < 0)
    assert_true(below > 0)


def test_edge_is_zero_exactly_on_the_line() raises:
    assert_equal(edge_at(0, 0, 16, 0, 8, 0), 0)
    assert_equal(edge_at(0, 0, 32, 32, 16, 16), 0)


def test_edge_is_twice_the_triangle_area() raises:
    # A right triangle one pixel on each leg: 16 by 16 grid steps, so twice
    # its area is 256.
    assert_equal(edge_at(0, 0, 16, 0, 0, 16), 256)


def test_reversing_an_edge_negates_it_exactly() raises:
    # The property the whole fixed-point scheme exists for. Two triangles
    # sharing an edge ask about it from opposite orderings; if these are not
    # exact negations, a pixel can fall outside both and leave a crack.
    # Deliberately awkward coordinates, not round ones.
    var points = [-2039, -17, 0, 3, 511, 4097, 65535]
    for first in range(len(points)):
        for second in range(len(points)):
            var ax = points[first]
            var ay = points[second]
            var bx = points[(first + 3) % len(points)]
            var by = points[(second + 5) % len(points)]
            var px = points[(first + 1) % len(points)]
            var py = points[(second + 2) % len(points)]
            assert_equal(
                edge_at(ax, ay, bx, by, px, py),
                -edge_at(bx, by, ax, ay, px, py),
            )


# --- the top-left rule ------------------------------------------------------


def test_a_horizontal_edge_is_a_top_edge_only_right_to_left() raises:
    # With the winding normalized to a positive area and y downwards, a
    # horizontal edge running right-to-left has the interior below it.
    assert_true(is_top_left(16, 0, 0, 0))
    assert_false(is_top_left(0, 0, 16, 0))


def test_an_upward_edge_is_a_left_edge() raises:
    # Screen y grows downwards, so "upwards" means the end point has the
    # smaller y.
    assert_true(is_top_left(0, 16, 0, 0))
    assert_false(is_top_left(0, 0, 0, 16))


def test_bias_is_zero_for_kept_edges_and_minus_one_otherwise() raises:
    # Added before the sign test, so a zero edge value survives on a top or
    # left edge and fails on the others without a second comparison.
    assert_equal(bias(16, 0, 0, 0), 0)
    assert_equal(bias(0, 0, 16, 0), -1)
    assert_equal(bias(0, 16, 0, 0), 0)
    assert_equal(bias(0, 0, 0, 16), -1)


def test_exactly_one_of_two_triangles_claims_a_shared_edge() raises:
    # The rule's whole purpose, checked on the quad the renderer actually
    # builds: two triangles meeting along a diagonal. Every sample point on
    # that diagonal must be claimed once -- never twice (which double-blends)
    # and never zero times (which leaves a crack).
    #
    # Quad corners, in pixels: (0,0) (4,0) (4,4) (0,4).
    # Upper triangle (0,0) (4,0) (4,4); lower (0,0) (4,4) (0,4).
    var claims = 0
    var contested = 0
    for y in range(4):
        for x in range(4):
            var px = sample(x)
            var py = sample(y)
            var upper = _covers(
                snap(0), snap(0), snap(4), snap(0), snap(4), snap(4), px, py
            )
            var lower = _covers(
                snap(0), snap(0), snap(4), snap(4), snap(0), snap(4), px, py
            )
            if upper and lower:
                contested += 1
            if upper or lower:
                claims += 1
    assert_equal(contested, 0)
    # Every pixel of the quad belongs to one of the two.
    assert_equal(claims, 16)


def _covers(
    ax: Int,
    ay: Int,
    bx: Int,
    by: Int,
    cx: Int,
    cy: Int,
    px: Int,
    py: Int,
) -> Bool:
    """Return True if the sample point is claimed by this triangle.

    The fill rule assembled from its parts, as both rasterizers assemble it:
    normalize the winding, then require every biased edge value to be
    non-negative.

    Args:
        ax: First corner x, on the subpixel grid.
        ay: First corner y.
        bx: Second corner x.
        by: Second corner y.
        cx: Third corner x.
        cy: Third corner y.
        px: Sample point x.
        py: Sample point y.

    Returns:
        True if the triangle claims that sample point.
    """
    var sbx = bx
    var sby = by
    var scx = cx
    var scy = cy
    var area = edge_at(ax, ay, sbx, sby, scx, scy)
    if area < 0:
        sbx = cx
        sby = cy
        scx = bx
        scy = by
        area = -area
    if area == 0:
        return False
    return (
        edge_at(ax, ay, sbx, sby, px, py) + bias(ax, ay, sbx, sby) >= 0
        and edge_at(sbx, sby, scx, scy, px, py) + bias(sbx, sby, scx, scy) >= 0
        and edge_at(scx, scy, ax, ay, px, py) + bias(scx, scy, ax, ay) >= 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
