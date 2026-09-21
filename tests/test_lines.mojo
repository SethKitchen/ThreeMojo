# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.linerule` and the line rasterizer beside it."""

from core.fog import FogView, linear_fog
from materials.material import (
    BASIC,
    BLEND,
    Blending,
    LAMBERT,
    MaterialKind,
    OPAQUE,
)
from math.vector2 import Vector2
from render.framebuffer import Color, FloatColor, Framebuffer
from render.linerule import (
    covers,
    dash_covers,
    major_at,
    major_is_x,
    other_at,
    share_at,
    span_of,
)
from render.rasterizer import (
    RasterVertex,
    check_line_state,
    rasterize_line,
    rasterize_lines_all,
)
from render.target import RenderTarget
from render.texture_store import NO_TEXTURE
from render.tonemap import NO_TONE_MAPPING
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOLERANCE = Float64(1e-5)


def end(
    x: Float32,
    y: Float32,
    z: Float32 = 0.5,
    color: FloatColor = FloatColor(1, 1, 1),
    blend: Blending = OPAQUE,
    inv_w: Float32 = 1,
    depth: Float32 = 0,
) raises -> RasterVertex:
    """Return one end of a line, unlit as a line must be."""
    return RasterVertex(
        x,
        y,
        z,
        inv_w,
        color,
        0,
        0,
        NO_TEXTURE,
        blend,
        kind=BASIC,
        view_depth=depth,
    )


def lit(target: RenderTarget) raises -> Int:
    """Return how many pixels are not still the clear color."""
    var count = 0
    var image = target.resolve(1, NO_TONE_MAPPING, 1.0)
    for y in range(image.height):
        for x in range(image.width):
            var pixel = image.get_pixel(x, y)
            if pixel.r != 0 or pixel.g != 0 or pixel.b != 0:
                count += 1
    return count


def is_lit(target: RenderTarget, x: Int, y: Int) raises -> Bool:
    """Return True if one pixel is not still the clear color."""
    var image = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var pixel = image.get_pixel(x, y)
    return pixel.r != 0 or pixel.g != 0 or pixel.b != 0


# --- the rule ---------------------------------------------------------------


def test_the_major_axis_is_the_one_it_covers_more_of() raises:
    assert_true(major_is_x(Vector2(0, 0), Vector2(10, 2)))
    assert_false(major_is_x(Vector2(0, 0), Vector2(2, 10)))
    # A line of no length is walked along x, which lights one pixel.
    assert_true(major_is_x(Vector2(3, 3), Vector2(3, 3)))
    # Exactly diagonal: x wins, and either answer draws the same staircase.
    assert_true(major_is_x(Vector2(0, 0), Vector2(5, 5)))


def test_a_span_counts_both_ends() raises:
    assert_equal(span_of(Vector2(0.5, 0.5), Vector2(4.5, 0.5)), 5)
    assert_equal(span_of(Vector2(0.5, 0.5), Vector2(0.5, 4.5)), 5)
    assert_equal(span_of(Vector2(2.5, 2.5), Vector2(2.5, 2.5)), 1)
    # Walked backwards, the same count.
    assert_equal(span_of(Vector2(4.5, 0.5), Vector2(0.5, 0.5)), 5)


def test_the_walk_steps_toward_the_far_end() raises:
    var left = Vector2(1.5, 0.5)
    var right = Vector2(5.5, 0.5)
    assert_equal(major_at(left, right, 0), 1)
    assert_equal(major_at(left, right, 3), 4)
    # And the other way, it counts down.
    assert_equal(major_at(right, left, 0), 5)
    assert_equal(major_at(right, left, 3), 2)
    # Down a column, the major axis is y, and it counts both ways there
    # too: a line drawn upward steps back through the rows.
    var top = Vector2(0.5, 1.5)
    var bottom = Vector2(0.5, 5.5)
    assert_equal(major_at(top, bottom, 2), 3)
    assert_equal(major_at(bottom, top, 0), 5)
    assert_equal(major_at(bottom, top, 2), 3)


def test_a_share_runs_from_zero_to_one() raises:
    var left = Vector2(0.5, 0.5)
    var right = Vector2(4.5, 0.5)
    assert_almost_equal(share_at(left, right, 0), Float32(0), atol=TOLERANCE)
    assert_almost_equal(share_at(left, right, 4), Float32(1), atol=TOLERANCE)
    assert_almost_equal(share_at(left, right, 2), Float32(0.5), atol=TOLERANCE)
    # A line of no length is everywhere at once, and reports zero.
    var still = Vector2(2.5, 2.5)
    assert_almost_equal(share_at(still, still, 2), Float32(0), atol=TOLERANCE)
    var upright = Vector2(2.5, 6.5)
    assert_almost_equal(share_at(still, upright, 2), Float32(0), atol=TOLERANCE)


def test_the_rule_lights_one_pixel_a_column() raises:
    var a = Vector2(0.5, 0.5)
    var b = Vector2(4.5, 4.5)
    # A true diagonal steps one row per column.
    for column in range(5):
        assert_equal(other_at(a, b, column), column)
    # And a flat line stays on its row.
    var flat = Vector2(4.5, 0.5)
    assert_equal(other_at(a, flat, 3), 0)


def test_a_pixel_is_covered_only_where_the_line_is() raises:
    var a = Vector2(0.5, 0.5)
    var b = Vector2(4.5, 4.5)
    assert_true(covers(a, b, 2, 2))
    assert_false(covers(a, b, 2, 3))
    # Past either end, nothing is covered.
    assert_false(covers(a, b, 5, 5))
    assert_false(covers(a, b, -1, -1))
    # A steep line is walked down its rows, and the same holds.
    var steep = Vector2(0.5, 8.5)
    assert_true(covers(a, steep, 0, 4))
    assert_false(covers(a, steep, 1, 4))
    assert_false(covers(a, steep, 0, 9))


# --- the rasterizer ---------------------------------------------------------


def test_a_flat_line_lights_its_own_row() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(1.5, 3.5), end(5.5, 3.5), target)
    assert_equal(lit(target), 5)
    for x in range(1, 6):
        assert_true(is_lit(target, x, 3))
    assert_false(is_lit(target, 0, 3))
    assert_false(is_lit(target, 6, 3))


def test_an_upright_line_drawn_upward_lights_the_same_column() raises:
    var down = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(2.5, 1.5), end(2.5, 6.5), down)
    var up = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(2.5, 6.5), end(2.5, 1.5), up)
    for y in range(8):
        for x in range(8):
            assert_equal(is_lit(down, x, y), is_lit(up, x, y))


def test_an_upright_line_lights_its_own_column() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(2.5, 1.5), end(2.5, 6.5), target)
    assert_equal(lit(target), 6)
    for y in range(1, 7):
        assert_true(is_lit(target, 2, y))


def test_a_diagonal_line_is_a_staircase() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(0.5, 0.5), end(6.5, 6.5), target)
    assert_equal(lit(target), 7)
    for step in range(7):
        assert_true(is_lit(target, step, step))


def test_a_line_drawn_backwards_lights_the_same_pixels() raises:
    var forward = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(1.5, 1.5), end(6.5, 4.5), forward)
    var backward = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(6.5, 4.5), end(1.5, 1.5), backward)
    for y in range(8):
        for x in range(8):
            assert_equal(is_lit(forward, x, y), is_lit(backward, x, y))


def test_a_line_of_no_length_lights_one_pixel() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(3.5, 3.5), end(3.5, 3.5), target)
    assert_equal(lit(target), 1)
    assert_true(is_lit(target, 3, 3))


def test_a_line_is_clipped_to_the_image() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(-4.5, 3.5), end(12.5, 3.5), target)
    assert_equal(lit(target), 8)


def test_a_row_range_outside_the_image_is_held_inside_it() raises:
    # A band's rows are always inside, but the argument is public and a
    # caller may name rows the image does not have.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(0.5, 3.5), end(7.5, 3.5), target, -4, 99)
    assert_equal(lit(target), 8)
    # And a range that names none of the line's rows draws none of it.
    var none = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(0.5, 3.5), end(7.5, 3.5), none, 5, 7)
    assert_equal(lit(none), 0)


def test_a_line_takes_its_color_from_its_ends() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(
        end(0.5, 0.5, color=FloatColor(1, 0, 0)),
        end(4.5, 0.5, color=FloatColor(0, 0, 1)),
        target,
    )
    var left = target.color_at(0, 0)
    var right = target.color_at(4, 0)
    assert_almost_equal(left.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(right.b, Float32(1), atol=TOLERANCE)
    # And half way along it is half of each.
    var middle = target.color_at(2, 0)
    assert_almost_equal(middle.r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(middle.b, Float32(0.5), atol=TOLERANCE)


def test_a_line_behind_something_is_hidden() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(0.5, 0.5, 0.1), end(7.5, 0.5, 0.1), target)
    rasterize_line(
        end(0.5, 0.5, 0.9, FloatColor(1, 0, 0)),
        end(7.5, 0.5, 0.9, FloatColor(1, 0, 0)),
        target,
    )
    # The near one is still there: the far one failed the depth test.
    assert_almost_equal(target.color_at(3, 0).r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(target.color_at(3, 0).g, Float32(1), atol=TOLERANCE)


def test_a_blended_line_mixes_with_what_is_there() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(0.5, 0.5, 0.1), end(7.5, 0.5, 0.1), target)
    rasterize_line(
        end(0.5, 0.5, 0.05, FloatColor(1, 0, 0, 0.5), BLEND),
        end(7.5, 0.5, 0.05, FloatColor(1, 0, 0, 0.5), BLEND),
        target,
    )
    var mixed = target.color_at(3, 0)
    # Half red over white: full red, and the other channels halved.
    assert_almost_equal(mixed.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(mixed.g, Float32(0.5), atol=TOLERANCE)


def test_a_blended_line_claims_no_depth() raises:
    # Two blended segments crossing: the second is behind the first and
    # still contributes, because a blended segment tests the depth without
    # claiming it, as a blended triangle does. Claiming it dropped the
    # second at the crossing, and the kernel never did.
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_line(
        end(2.5, 8.5, 0.2, FloatColor(1, 0, 0, 0.5), BLEND),
        end(14.5, 8.5, 0.2, FloatColor(1, 0, 0, 0.5), BLEND),
        target,
    )
    rasterize_line(
        end(8.5, 2.5, 0.6, FloatColor(0, 0, 1, 0.5), BLEND),
        end(8.5, 14.5, 0.6, FloatColor(0, 0, 1, 0.5), BLEND),
        target,
    )
    var crossing = target.color_at(8, 8)
    # Half blue over half red over opaque black, premultiplied: a quarter
    # red and a half blue, and the clear color's full coverage kept.
    assert_almost_equal(crossing.r, Float32(0.25), atol=TOLERANCE)
    assert_almost_equal(crossing.b, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(crossing.a, Float32(1), atol=TOLERANCE)
    # And neither claimed the pixel's depth.
    assert_equal(target.depth_at(8, 8), inf[DType.float32]())
    # An opaque segment still claims it.
    rasterize_line(end(2.5, 8.5, 0.1), end(14.5, 8.5, 0.1), target)
    assert_almost_equal(target.depth_at(8, 8), Float32(0.1), atol=TOLERANCE)
    # And a blended segment behind that opaque one is hidden by it: the
    # test is still made, only the claim is not.
    rasterize_line(
        end(8.5, 2.5, 0.4, FloatColor(0, 1, 0, 0.5), BLEND),
        end(8.5, 14.5, 0.4, FloatColor(0, 1, 0, 0.5), BLEND),
        target,
    )
    assert_almost_equal(target.color_at(8, 8).g, Float32(1), atol=TOLERANCE)
    assert_almost_equal(target.color_at(8, 8).r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(target.color_at(8, 8).b, Float32(1), atol=TOLERANCE)


def test_fog_veils_a_line_by_its_depth() raises:
    var near = RenderTarget(8, 8, Color(0, 0, 0))
    var view = FogView(
        linear_fog(Color(0, 0, 0), Length(1.0, METER), Length(10.0, METER))
    )
    rasterize_line(
        end(0.5, 0.5, depth=1), end(7.5, 0.5, depth=1), near, fog=view
    )
    var far = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(
        end(0.5, 0.5, depth=9), end(7.5, 0.5, depth=9), far, fog=view
    )
    # Black fog: the far line is darker than the near one.
    assert_true(far.color_at(3, 0).r < near.color_at(3, 0).r)


def test_an_end_that_is_not_on_a_pixel_center_is_held_in() raises:
    # A projected vertex lands wherever it lands. The last column of a line
    # ending at 6.2 is column six, whose center is 6.5 -- past the end --
    # so the share comes out above one and has to be held there before it
    # is interpolated by.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(
        end(0.5, 0.5, color=FloatColor(1, 0, 0)),
        end(6.2, 0.5, color=FloatColor(0, 0, 1)),
        target,
    )
    assert_equal(lit(target), 7)
    # The far end is the far end's color and no further.
    var last = target.color_at(6, 0)
    assert_almost_equal(last.b, Float32(1), atol=TOLERANCE)
    assert_almost_equal(last.r, Float32(0), atol=TOLERANCE)

    # And the near end the same way round: a line starting at 0.9 has its
    # first column's center at 0.5, behind the start, so the share comes
    # out below zero there.
    var other = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(
        end(0.9, 2.5, color=FloatColor(1, 0, 0)),
        end(6.5, 2.5, color=FloatColor(0, 0, 1)),
        other,
    )
    var firstly = other.color_at(0, 2)
    assert_almost_equal(firstly.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(firstly.b, Float32(0), atol=TOLERANCE)


def test_a_line_with_no_perspective_left_draws_nothing() raises:
    # `inv_w` is what is left of the perspective divide, and a corner that
    # kept none of it has no weight to interpolate by. A renderer never
    # makes one -- the clip has already removed everything at the near
    # plane -- but a `RasterVertex` is an open struct, and dividing by the
    # sum of two zeroes is not an answer.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_line(end(0.5, 0.5, inv_w=0), end(6.5, 0.5, inv_w=0), target)
    assert_equal(lit(target), 0)


# --- the batch --------------------------------------------------------------


def two_lines() raises -> List[RasterVertex]:
    """Return two segments, two corners each."""
    return [
        end(0.5, 1.5),
        end(6.5, 1.5),
        end(0.5, 4.5),
        end(6.5, 4.5),
    ]


def test_a_batch_draws_every_segment() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(two_lines(), target)
    assert_equal(lit(target), 14)


def test_a_scene_with_no_lines_draws_nothing() raises:
    # The ordinary case: almost every frame has triangles and no lines, so
    # the batch has to do nothing gracefully rather than not be called.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(List[RasterVertex](), target)
    assert_equal(lit(target), 0)
    rasterize_lines_all(List[RasterVertex](), target, 4)
    assert_equal(lit(target), 0)


def test_more_workers_draw_the_same_image() raises:
    var one = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(two_lines(), one)
    var many = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(two_lines(), many, 4)
    for y in range(8):
        for x in range(8):
            assert_equal(is_lit(one, x, y), is_lit(many, x, y))
    # And more bands than rows collapses rather than failing.
    var crowded = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(two_lines(), crowded, 64)
    for y in range(8):
        for x in range(8):
            assert_equal(is_lit(one, x, y), is_lit(crowded, x, y))
    # Bands that do not divide the image evenly. Five over eight rows
    # takes two each, so the fifth band starts past the last row and has
    # nothing to draw. Three takes three each, so the last band runs off
    # the bottom and is clipped to it. A count that divides evenly reaches
    # neither case.
    var uneven = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(two_lines(), uneven, 5)
    var clipped = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(two_lines(), clipped, 3)
    for y in range(8):
        for x in range(8):
            assert_equal(is_lit(one, x, y), is_lit(uneven, x, y))
            assert_equal(is_lit(one, x, y), is_lit(clipped, x, y))


# --- what is refused --------------------------------------------------------


def test_a_batch_needs_whole_segments_and_a_worker() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var odd: List[RasterVertex] = [end(0.5, 0.5), end(1.5, 0.5), end(2.5, 0.5)]
    with assert_raises():
        rasterize_lines_all(odd, target)
    with assert_raises():
        rasterize_lines_all(two_lines(), target, 0)


def test_a_line_must_agree_with_itself() raises:
    # A blend policy that is not one of the two.
    with assert_raises():
        check_line_state(
            end(0.5, 0.5, blend=Blending(7)), end(1.5, 0.5, blend=Blending(7))
        )
    # Two ends that disagree about blending.
    with assert_raises():
        check_line_state(end(0.5, 0.5), end(1.5, 0.5, blend=BLEND))


def test_a_line_cannot_be_lit() raises:
    # A line has no surface, so it has no normal, so nothing can light it.
    var first = end(0.5, 0.5)
    first.kind = LAMBERT
    var second = end(4.5, 0.5)
    second.kind = LAMBERT
    with assert_raises():
        check_line_state(first, second)
    # Two ends that disagree about the material.
    var odd = end(0.5, 0.5)
    odd.kind = BASIC
    var other = end(4.5, 0.5)
    other.kind = LAMBERT
    with assert_raises():
        check_line_state(odd, other)
    # And a kind that is not a kind at all, on both ends, so it is the
    # kind itself being refused rather than the disagreement.
    var unknown = end(0.5, 0.5)
    unknown.kind = MaterialKind(10)
    var also = end(4.5, 0.5)
    also.kind = MaterialKind(10)
    with assert_raises():
        check_line_state(unknown, also)


def painted_pixels(image: Framebuffer, clear: Color) raises -> List[Int]:
    """Return every pixel of `image` that is not the clear color, as
    `x + y * width`.

    Args:
        image: The resolved frame.
        clear: What the target was cleared to.

    Returns:
        The lit pixels, in row order.

    Raises:
        Error: If a coordinate is out of bounds.
    """
    var lit = List[Int]()
    for y in range(image.height):
        for x in range(image.width):
            var pixel = image.get_pixel(x, y)
            if pixel.r != clear.r or pixel.g != clear.g or pixel.b != clear.b:
                lit.append(x + y * image.width)
    return lit^


def drawn_line(
    ax: Float32, ay: Float32, bx: Float32, by: Float32, workers: Int = 1
) raises -> Framebuffer:
    """Return an eight by eight frame holding one white segment.

    Args:
        ax: One end's column, in pixels.
        ay: Its row.
        bx: The other end's column.
        by: Its row.
        workers: How many threads to draw with.

    Returns:
        The resolved frame, cleared to black.

    Raises:
        Error: If the segment or the target is refused.
    """
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    rasterize_lines_all(
        [end(ax, ay), end(bx, by)], target, workers, FogView.none()
    )
    return target.resolve()


def test_a_mostly_offscreen_line_paints_only_what_is_on_the_image() raises:
    """A segment a million columns wide lights the eight that are there."""
    # The walk is bounded to the target before it starts, so this costs
    # eight steps rather than two million. What the test can see is that
    # bounding it moved nothing: the same row, the same eight columns.
    var wide = painted_pixels(
        drawn_line(-1000000.0, 3.5, 1000000.0, 3.5), Color(0, 0, 0)
    )
    assert_equal(len(wide), 8)
    for column in range(8):
        assert_equal(wide[column], column + 3 * 8)
    # Drawn the other way round, which walks the major axis downward and
    # so bounds it from the other end.
    var backwards = painted_pixels(
        drawn_line(1000000.0, 3.5, -1000000.0, 3.5), Color(0, 0, 0)
    )
    assert_equal(len(backwards), 8)
    for column in range(8):
        assert_equal(backwards[column], column + 3 * 8)


def test_a_mostly_offscreen_upright_line_is_bounded_by_the_band() raises:
    """A y-major segment is held to the rows its band owns."""
    var tall = painted_pixels(
        drawn_line(2.5, -1000000.0, 2.5, 1000000.0), Color(0, 0, 0)
    )
    assert_equal(len(tall), 8)
    for row in range(8):
        assert_equal(tall[row], 2 + row * 8)
    # And on more workers, where each band bounds the walk to its own rows
    # rather than to the whole image.
    var banded = painted_pixels(
        drawn_line(2.5, -1000000.0, 2.5, 1000000.0, workers=4),
        Color(0, 0, 0),
    )
    assert_equal(len(banded), 8)


def test_a_line_that_misses_the_image_paints_nothing() raises:
    """A segment wholly off one side leaves an empty step range."""
    var beside = painted_pixels(
        drawn_line(-40.5, 3.5, -10.5, 3.5), Color(0, 0, 0)
    )
    assert_equal(len(beside), 0)
    var below = painted_pixels(drawn_line(3.5, 40.5, 3.5, 90.5), Color(0, 0, 0))
    assert_equal(len(below), 0)


def test_a_line_interpolates_its_color_straight() raises:
    """A transparent end still lends its color, as a varying does."""
    # `mix_color` premultiplies, which is right for filtering texels and
    # wrong for a varying: it would drop the red entirely. See
    # `render.texture.mix_straight`.
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    var near = end(0.5, 3.5, color=FloatColor(1, 0, 0, 0), blend=BLEND)
    var far = end(7.5, 3.5, color=FloatColor(0, 0, 1, 1), blend=BLEND)
    rasterize_lines_all([near, far], target, 1, FogView.none())
    var image = target.resolve()
    var reds = 0
    for x in range(8):
        if image.get_pixel(x, 3).r > 40:
            reds += 1
    assert_true(reds > 0)


def test_a_steep_line_that_wanders_off_the_side_is_held_in() raises:
    """A y-major segment checks its columns, and an x-major one its rows."""
    # The major axis is bounded before the walk; the minor one is still
    # checked per pixel, because a line can leave the image sideways while
    # every step of its major axis is on it.
    var steep = painted_pixels(drawn_line(-3.0, 0.5, 3.0, 7.5), Color(0, 0, 0))
    assert_true(len(steep) > 0)
    assert_true(len(steep) < 8)
    # And off the other side, so both halves of the column guard are met.
    var leaning = painted_pixels(
        drawn_line(5.0, 0.5, 11.0, 7.5), Color(0, 0, 0)
    )
    assert_true(len(leaning) > 0)
    assert_true(len(leaning) < 8)
    # Flat, and above the image: every column is on the target and no row
    # is, which is the other half of the same guard.
    var above = painted_pixels(drawn_line(0.5, 90.5, 7.5, 90.5), Color(0, 0, 0))
    assert_equal(len(above), 0)
    var under = painted_pixels(
        drawn_line(0.5, -90.5, 7.5, -90.5), Color(0, 0, 0)
    )
    assert_equal(len(under), 0)


def dashed(
    x: Float32,
    y: Float32,
    along: Float32,
    dash: Float32,
    gap: Float32,
    z: Float32 = 0.5,
    inv_w: Float32 = 1,
) raises -> RasterVertex:
    """Return one end of a dashed line, `along` units along it."""
    return RasterVertex(
        x,
        y,
        z,
        inv_w,
        FloatColor(1, 1, 1),
        0,
        0,
        NO_TEXTURE,
        OPAQUE,
        kind=BASIC,
        line_distance=along,
        dash_size=dash,
        gap_size=gap,
    )


def test_a_gap_of_zero_draws_every_pixel() raises:
    # A solid line asks the same question and is never refused, whatever
    # the dash says: three.js's fold into a period of the dash alone
    # never passes the dash's end.
    assert_true(dash_covers(0, 0, 0))
    assert_true(dash_covers(7.5, 0, 0))
    assert_true(dash_covers(7.5, 3, 0))
    assert_true(dash_covers(-2, 3, 0))


def test_a_distance_is_folded_into_one_period() raises:
    # A dash of three and a gap of one, three.js's defaults: drawn for the
    # first three of every four units, and the fold is inclusive at the
    # dash's end, as `mod(d, 4) > 3` discards only past it.
    assert_true(dash_covers(0, 3, 1))
    assert_true(dash_covers(2.9, 3, 1))
    assert_true(dash_covers(3, 3, 1))
    assert_false(dash_covers(3.5, 3, 1))
    assert_false(dash_covers(3.999, 3, 1))
    assert_true(dash_covers(4, 3, 1))
    assert_true(dash_covers(10.5, 3, 1))
    assert_false(dash_covers(11.5, 3, 1))


def test_a_negative_distance_folds_like_glsl_mod() raises:
    # A scale below zero runs the distance backward. GLSL's `mod` follows
    # the divisor's sign, so -0.5 folds to 3.5, which is in the gap, and
    # -1.5 folds to 2.5, which is in the dash.
    assert_false(dash_covers(-0.5, 3, 1))
    assert_true(dash_covers(-1.5, 3, 1))


def test_a_dashed_line_leaves_its_gaps_unpainted() raises:
    # Sixteen columns, a distance of one per column measured at the pixel
    # center, a dash of four and a gap of four: columns 0 to 3 and 8 to 11
    # fold at or under four, and the rest past it.
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_line(dashed(0, 8.5, 0, 4, 4), dashed(16, 8.5, 16, 4, 4), target)
    for x in range(16):
        var drawn = target.color_at(x, 8).r > 0.5
        var expected = (x % 8) < 4
        assert_equal(drawn, expected, "column " + String(x))
    assert_equal(lit(target), 8)


def test_a_dash_is_measured_with_perspective_correction() raises:
    # The near end is three times as close as the far one, so the far
    # half of the line in the world is squeezed into the last third or
    # so of the screen. A dash covering the first half of the line ends
    # past column 11 rather than at column 8, where an affine measure
    # would end it.
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_line(
        dashed(0, 8.5, 0, 8, 8, inv_w=3),
        dashed(16, 8.5, 16, 8, 8, inv_w=1),
        target,
    )
    # Column 8 is 4.4 units along and column 11 is 7.4: both in the dash.
    assert_true(target.color_at(8, 8).r > 0.5)
    assert_true(target.color_at(11, 8).r > 0.5)
    # Column 12 is 8.7 units along and column 15 is 14.6: both in the gap.
    assert_false(target.color_at(12, 8).r > 0.5)
    assert_false(target.color_at(15, 8).r > 0.5)


def test_a_gap_claims_no_depth() raises:
    # A dashed line in front, then a solid line behind it. The pixels in
    # the gaps were never drawn, so they claim nothing and the line behind
    # shows through them; the dashes hide it.
    var target = RenderTarget(16, 16, Color(0, 0, 0))
    rasterize_line(
        dashed(0, 8.5, 0, 4, 4, z=0.2), dashed(16, 8.5, 16, 4, 4, z=0.2), target
    )
    rasterize_line(
        end(0, 8.5, 0.6, FloatColor(0, 0, 1)),
        end(16, 8.5, 0.6, FloatColor(0, 0, 1)),
        target,
    )
    assert_almost_equal(target.color_at(2, 8).b, Float32(1), atol=TOLERANCE)
    assert_almost_equal(target.color_at(2, 8).r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(target.color_at(5, 8).b, Float32(1), atol=TOLERANCE)
    assert_almost_equal(target.color_at(5, 8).r, Float32(0), atol=TOLERANCE)
    assert_almost_equal(target.depth_at(5, 8), Float32(0.6), atol=TOLERANCE)


def test_a_line_must_agree_with_itself_about_the_dashes() raises:
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    with assert_raises(contains="agree about the dashes"):
        rasterize_line(dashed(0, 1.5, 0, 4, 4), dashed(4, 1.5, 4, 2, 4), target)
    with assert_raises(contains="agree about the dashes"):
        rasterize_line(dashed(0, 1.5, 0, 4, 4), dashed(4, 1.5, 4, 4, 2), target)


def test_a_dash_or_a_gap_must_be_a_length() raises:
    var target = RenderTarget(4, 4, Color(0, 0, 0))
    with assert_raises(contains="dash size cannot be negative"):
        rasterize_line(
            dashed(0, 1.5, 0, -1, 4), dashed(4, 1.5, 4, -1, 4), target
        )
    with assert_raises(contains="dash size cannot be negative"):
        var bad = nan[DType.float32]()
        rasterize_line(
            dashed(0, 1.5, 0, bad, 4), dashed(4, 1.5, 4, bad, 4), target
        )
    with assert_raises(contains="gap size cannot be negative"):
        rasterize_line(
            dashed(0, 1.5, 0, 4, -1), dashed(4, 1.5, 4, 4, -1), target
        )
    with assert_raises(contains="gap size cannot be negative"):
        var bad = nan[DType.float32]()
        rasterize_line(
            dashed(0, 1.5, 0, 4, bad), dashed(4, 1.5, 4, 4, bad), target
        )


def test_a_segment_no_band_draws_is_still_refused() raises:
    """A band checks the segments its rows miss, so four workers and one
    answer alike."""
    var target = RenderTarget(8, 8, Color(0, 0, 0))
    # Off the bottom of every band, and lit, which a line may not be.
    var one = end(0.5, 90.5)
    one.kind = LAMBERT
    var two = end(7.5, 90.5)
    two.kind = LAMBERT
    with assert_raises():
        rasterize_lines_all([one, two], target, 4, FogView.none())
    with assert_raises():
        rasterize_lines_all([one, two], target, 1, FogView.none())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
