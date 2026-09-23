# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which pixels a line covers, in arithmetic both backends share.

`render.fillrule` is this module's opposite number for triangles, and it
exists for the same reason: the CPU path and the GPU kernel have to agree
about coverage exactly, so the rule lives in one place and both import it.
Nothing here allocates, raises, prints or touches a framebuffer, so it
compiles for a device as readily as for the host.

## The rule

A line is walked along whichever axis it covers more of -- its *major*
axis -- and it lights `width` pixels in each row or column of that axis.
That is the oldest rasterization rule there is, and with a width of one it
is what "a width of one pixel" means: no coverage, no anti-aliasing. A
diagonal line is a staircase.

`other_at` is the whole rule. Given a line and one coordinate along its
major axis, it says which pixel on the minor axis the line lights there.
Everything else follows:

    the CPU walks the major axis and asks `other_at` for the minor one
    the kernel asks `other_at` whether *this* pixel is the one

## The width is raster pixels, not a material's thickness

three.js has no line thickness -- WebGL ignores `linewidth`, which is why
three.js ships `Line2` as geometry -- and neither does this. The width here
is the renderer's *render scale*: how many raster pixels stand for one
output pixel. It is one in an ordinary frame and `SUPERSAMPLE` in a frame
drawn for anti-aliasing, where a line that lit one raster pixel would
average down to a fraction of an output pixel and a wireframe would fade
out the moment `antialias` was turned on. A width of `k` keeps the line one
*output* pixel thick, which is the thickness the caller asked for and the
thickness it had before. See `renderers.renderer.Renderer.render_scale`.

`first_other_at` places those `k` pixels: centered on where the line
actually crosses the minor axis, and at `k` of one it is `other_at`
exactly, so an ordinary frame is drawn by the rule it always was.

The two loops are shaped differently -- one walks a line, the other tests a
pixel -- and they cannot disagree, because both get the answer from the
same expression. Writing a walk on one side and a distance test on the
other is the obvious way to build this and the reason it would drift: a
pixel that a walk rounds one way and a distance rounds the other is a hole
in one backend and not the other.

## Why not a distance from the line

A distance test is the natural way to ask "is this pixel on the line" per
pixel, and it is what a line with real coverage would need. It is also a
different rule: it lights an extra pixel in a column wherever the line
passes near a boundary, and the walk lights the run it was given. The two
can be reconciled, and the reconciliation is more arithmetic than the rule
it protects.

The width above is not coverage and does not pretend to be. It keeps a
line the same thickness in the finished image whatever the frame was drawn
at; it does not soften the line's own two edges, which stay as hard as a
staircase. A material's thickness -- three.js's `Line2` -- is a separate
feature: `objects.line_segments2`, drawn as quads, and quads are
triangles, which `fillrule` already covers.
"""

from math.vector2 import Vector2
from std.math import floor


def major_is_x(a: Vector2, b: Vector2) -> Bool:
    """Return True if the line covers more columns than rows.

    The axis it covers more of is the one it is walked along, so that it
    lights one pixel per step rather than leaving gaps between them.

    Args:
        a: One end, in pixels.
        b: The other end, in pixels.

    Returns:
        True when the line is more horizontal than vertical. A line of no
        length is horizontal by this test, which is the answer that makes
        it one pixel rather than none.
    """
    return abs(b.x - a.x) >= abs(b.y - a.y)


def span_of(a: Vector2, b: Vector2) -> Int:
    """Return how many pixels the line lights.

    One per step along the major axis, both ends included. A line whose
    two ends land on one pixel lights that pixel.

    Args:
        a: One end, in pixels.
        b: The other end, in pixels.

    Returns:
        The count, never less than one.
    """
    if major_is_x(a, b):
        return Int(abs(floor(b.x) - floor(a.x))) + 1
    return Int(abs(floor(b.y) - floor(a.y))) + 1


def major_at(a: Vector2, b: Vector2, step: Int) -> Int:
    """Return the major-axis pixel the line reaches at one step.

    Args:
        a: The end the walk starts from, in pixels.
        b: The end it walks toward, in pixels.
        step: Which step, from zero.

    Returns:
        The column, or the row for a line walked down its y axis.
    """
    if major_is_x(a, b):
        var start = Int(floor(a.x))
        if b.x >= a.x:
            return start + step
        return start - step
    var start = Int(floor(a.y))
    if b.y >= a.y:
        return start + step
    return start - step


def share_at(a: Vector2, b: Vector2, major: Int) -> Float32:
    """Return how far along the line one major-axis pixel is, from zero at
    `a` to one at `b`.

    Measured in screen space, which is what an attribute's perspective
    correction expects to be given; see `render.rasterizer`.

    Args:
        a: One end, in pixels.
        b: The other end, in pixels.
        major: The column, or the row for a line walked down its y axis.

    Returns:
        The fraction, not clamped: a caller asking about a pixel off the
        end of the line gets a number outside zero through one, which is
        what tells it so.
    """
    if major_is_x(a, b):
        var run = b.x - a.x
        if run == 0:
            return 0
        return (Float32(major) + 0.5 - a.x) / run
    # No guard on the rise here, where the x branch guards its run. A line
    # is walked down its y axis only when it covers more rows than columns,
    # and one that covers more rows than columns covers at least one row.
    # The zero-length line -- the only one with neither -- is horizontal by
    # `major_is_x` and never reaches this.
    return (Float32(major) + 0.5 - a.y) / (b.y - a.y)


def minor_at(a: Vector2, b: Vector2, major: Int) -> Float32:
    """Return where on the minor axis the line crosses one major-axis
    pixel, unrounded.

    `other_at` is this floored. Kept apart from it because a line more than
    one pixel wide has to be centered on where the line *is* rather than on
    the pixel that holds it, and rounding first would lose the half pixel
    that centering needs.

    Args:
        a: One end, in pixels.
        b: The other end, in pixels.
        major: The column, or the row for a line walked down its y axis.

    Returns:
        The row, or the column for a line walked down its y axis, in
        pixels rather than in whole pixels.
    """
    var share = share_at(a, b, major)
    if major_is_x(a, b):
        return a.y + (b.y - a.y) * share
    return a.x + (b.x - a.x) * share


def other_at(a: Vector2, b: Vector2, major: Int) -> Int:
    """Return the minor-axis pixel the line lights at one major-axis pixel.

    The whole rule. The CPU walks the major axis and asks this for the
    other coordinate; the kernel asks it whether the pixel it is shading is
    the one the line lights in that column. Same expression, same answer,
    so a staircase drawn on the host and a staircase drawn on the device
    are the same staircase.

    Args:
        a: One end, in pixels.
        b: The other end, in pixels.
        major: The column, or the row for a line walked down its y axis.

    Returns:
        The row, or the column for a line walked down its y axis.
    """
    return Int(floor(minor_at(a, b, major)))


def first_other_at(a: Vector2, b: Vector2, major: Int, width: Int) -> Int:
    """Return the first of the `width` minor-axis pixels the line lights at
    one major-axis pixel.

    The line lights `first_other_at` through `first_other_at + width - 1`.
    The run is centered on `minor_at`, the unrounded crossing:

        first = floor(minor - (width - 1) / 2)

    At a width of one that is `floor(minor)`, which is `other_at` -- the
    same expression, the same rounding, the same pixel -- so turning the
    width up is the only thing that changes a frame. At a width of two the
    run straddles the crossing, off center by at most half a raster pixel,
    which is a quarter of an output pixel at `SUPERSAMPLE` and is the
    closest two whole pixels can come to centering on one place.

    Args:
        a: One end, in pixels.
        b: The other end, in pixels.
        major: The column, or the row for a line walked down its y axis.
        width: How many pixels across the line is, at least one.

    Returns:
        The first row, or the first column for a line walked down its y
        axis.
    """
    return Int(floor(minor_at(a, b, major) - Float32(width - 1) / 2))


def covers(a: Vector2, b: Vector2, x: Int, y: Int, width: Int = 1) -> Bool:
    """Return True if the line lights the pixel at `x`, `y`.

    What the kernel asks, once per segment per pixel. A pixel is lit when
    it is inside the line's run along the major axis and is one of the
    `width` pixels the rule picks in that column or row.

    Args:
        a: One end, in pixels.
        b: The other end, in pixels.
        x: The pixel's column.
        y: The pixel's row.
        width: How many pixels across the line is, the renderer's render
            scale. One, the default, is the one-pixel line.

    Returns:
        True if the pixel is on the line.
    """
    var horizontal = major_is_x(a, b)
    var major = y
    if horizontal:
        major = x
    var first = Int(floor(a.y))
    var last = Int(floor(b.y))
    if horizontal:
        first = Int(floor(a.x))
        last = Int(floor(b.x))
    if major < min(first, last) or major > max(first, last):
        return False
    var lowest = first_other_at(a, b, major, width)
    var other = x
    if horizontal:
        other = y
    return other >= lowest and other < lowest + width


def dash_covers(distance: Float32, dash: Float32, gap: Float32) -> Bool:
    """Return True if a dashed line shows the pixel at `distance` along it.

    three.js's `linedashed_fragment`: the distance is folded into one
    period of dash plus gap, and the pixel is in the dash when the fold
    lands at or before the dash's end. A gap of zero draws every pixel,
    which is what a solid line is, so a solid line asks this too and is
    never refused.

    The fold is GLSL's `mod`, which follows the sign of the divisor and
    so is never negative here: a distance below zero, which a scale
    below zero can make, still lands inside the period.

    Args:
        distance: How far along the line the pixel is, in the line's own
            units, already scaled.
        dash: How long each dash is, in those units.
        gap: How long the gap after it is, in those units.

    Returns:
        True if the pixel is drawn.
    """
    if gap <= 0:
        return True
    var period = dash + gap
    var folded = distance - period * floor(distance / period)
    return folded <= dash
