# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which pixels a triangle covers, in exact integer arithmetic.

This is the one piece of the rasterizer that both the CPU path and the GPU
kernel must agree on *exactly*, so it lives in one place and both import it.
It was duplicated for a while, with a comment explaining that a kernel cannot
call into a module that prints — true of `render.rasterizer`, which writes
pixels, but not of arithmetic. Two copies of a rule whose entire purpose is
that two implementations agree is the wrong thing to have.

Nothing here allocates, raises, prints, or touches a framebuffer, so it
compiles for a device as readily as for the host.

Coverage is decided in fixed point, not floating point, and that is the
interesting part. Two triangles sharing an edge test it from opposite corner
orderings: one asks `edge_at(A, B, p)`, the other `edge_at(B, A, p)`. In exact
arithmetic those are negations of each other, so every pixel belongs to one
side or the other. In floating point they are computed from different
subtractions and need not negate exactly, so a pixel lying almost on the edge
could come out fractionally negative for *both* — belonging to neither, and
leaving a one-pixel crack along the shared diagonal of a quad.

Snapping vertices to a 1/16-pixel grid makes the edge function exact integer
arithmetic, where the two orderings do negate exactly and no pixel can be
missed. That leaves the opposite problem: a pixel exactly on the shared edge
now satisfies both triangles and would be drawn twice. The top-left fill rule
breaks that tie, giving each shared edge to exactly one of the two. Drawing
twice is invisible with an opaque depth test but doubles the contribution of
every shared edge once anything is blended.

This is what graphics hardware does, and for the same two reasons.
"""

from std.math import floor

# Vertices snap to a grid this many steps to the pixel. Four bits of subpixel
# precision is what most hardware rasterizers settled on: fine enough that the
# snapping is invisible, coarse enough that the edge function stays well
# clear of overflow. At 4096 pixels across, an edge value reaches about
# 4096*16 squared, roughly 4e9 -- comfortable in Mojo's 64-bit Int and not in
# a 32-bit one.
comptime SUBPIXEL_BITS = 4
comptime SUBPIXEL = 1 << SUBPIXEL_BITS


def snap(value: Float32) -> Int:
    """Return a screen coordinate on the subpixel grid, as an integer."""
    return Int(floor(value * Float32(SUBPIXEL) + 0.5))


def edge_at(ax: Int, ay: Int, bx: Int, by: Int, px: Int, py: Int) -> Int:
    """Return the signed twice-area of (a, b, p) on the subpixel grid.

    Exact: every input is an integer and so is every intermediate, which is
    the whole point. The sign says which side of a->b the point p falls on.
    """
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax)


def is_top_left(ax: Int, ay: Int, bx: Int, by: Int) -> Bool:
    """Return True if the edge a->b is a top or a left edge.

    Work it out from the edge function rather than from memory, because the
    horizontal case was wrong here for a while and reads plausibly either way.
    For the edge (0,0)->(16,0), `edge_at` is +256 at (8,16) and -256 at
    (8,-16). Screen y grows downwards, so the positive side — the interior of
    a positively wound triangle — lies *below* a left-to-right horizontal
    edge. A left-to-right horizontal edge is therefore the triangle's **top**
    edge, and `bx > ax` is what makes it one.

    The non-horizontal case asks the same question of x: an edge running
    upwards (`by < ay`) has the interior to its right, which is a left edge.

    Getting the horizontal half backwards does not crack or double-draw
    anything — swapping top for bottom is still a consistent tie-break, so
    each shared edge still belongs to exactly one triangle. It shows up
    instead as a triangle silently losing its top row of pixels whenever that
    edge lands exactly on pixel centers.
    """
    if ay == by:
        return bx > ax
    return by < ay


def bias(ax: Int, ay: Int, bx: Int, by: Int) -> Int:
    """Return 0 for a top or left edge, -1 for the others.

    Added to an edge value before the sign test, this expresses "strictly
    inside, unless this is a top or left edge" without a second comparison in
    the innermost loop.
    """
    if is_top_left(ax, ay, bx, by):
        return 0
    return -1


def sample(index: Int) -> Int:
    """Return the grid coordinate of the center of pixel row/column `index`.

    Sampling at the center rather than the corner is why a half-step is added;
    the same arithmetic serves both axes.
    """
    return index * SUBPIXEL + SUBPIXEL // 2
