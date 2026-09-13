# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Software triangle rasterization.

`rasterize` fills a flat 2D triangle and writes every covered pixel.
`rasterize_depth` takes the same triangle with a depth per corner and writes a
pixel only when it is nearer than what is already there, which is what lets
geometry be submitted in any order. `rasterize_shaded` additionally mixes a
colour given per corner.

Each triangle is scanned only inside its own bounding box. Walking the whole
framebuffer per triangle is the obvious way to write this and costs the same
for a triangle covering four pixels as for one covering the screen; a sphere
of several hundred triangles made that difference impossible to ignore.

Coverage is decided in fixed point, not floating point, and that is the
interesting part. Two triangles sharing an edge test it from opposite corner
orderings: one asks `edge(A, B, p)`, the other `edge(B, A, p)`. In exact
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

from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import ceil, floor, max, min

# Vertices snap to a grid this many steps to the pixel. Four bits of subpixel
# precision is what most hardware rasterizers settled on: fine enough that the
# snapping is invisible, coarse enough that the edge function stays well
# clear of overflow. At 4096 pixels across, an edge value reaches about
# 4096*16 squared, roughly 4e9 -- comfortable in Mojo's 64-bit Int and not in
# a 32-bit one.
comptime SUBPIXEL_BITS = 4
comptime SUBPIXEL = 1 << SUBPIXEL_BITS


def edge(a: Vector2, b: Vector2, p: Vector2) -> Float32:
    """Return the signed twice-area of triangle (a, b, p).

    The sign tells you which side of the line a->b the point p falls on. This
    is the floating-point form, kept for `area2` and for callers asking a
    geometric question — backface culling, say. Rasterization uses the exact
    fixed-point form below instead.
    """
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


def snap(value: Float32) -> Int:
    """Return a screen coordinate on the subpixel grid, as an integer."""
    return Int(floor(value * Float32(SUBPIXEL) + 0.5))


def edge_at(ax: Int, ay: Int, bx: Int, by: Int, px: Int, py: Int) -> Int:
    """Return the signed twice-area of (a, b, p), all on the subpixel grid.

    Integer arithmetic, so `edge_at(a, b, p)` is exactly `-edge_at(b, a, p)`
    and a pixel can never fall outside both of two triangles sharing an edge.
    """
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax)


def _is_top_left(ax: Int, ay: Int, bx: Int, by: Int) -> Bool:
    """Return True if the directed edge a->b is a top or a left edge.

    With the winding normalized so the triangle's area is positive and screen
    y running downwards, an edge heading upwards has the interior to its left,
    and a horizontal edge heading left has the interior below it. Those are
    the edges that keep the pixels lying exactly on them; the other two give
    theirs to the neighbouring triangle.
    """
    if ay == by:
        return bx < ax
    return by < ay


struct _Coverage(ImplicitlyCopyable):
    """A triangle prepared for exact coverage testing on the subpixel grid.

    The winding is normalized on construction so the area is positive, which
    removes the "either winding" branch from the inner loop. `swapped` records
    whether that happened, so barycentric weights can be handed back in the
    caller's original corner order.
    """

    var ax: Int
    var ay: Int
    var bx: Int
    var by: Int
    var cx: Int
    var cy: Int
    var area: Int
    var bias_ab: Int
    var bias_bc: Int
    var bias_ca: Int
    var swapped: Bool

    def __init__(out self, triangle: Triangle):
        """Snap `triangle` to the grid and work out its fill-rule biases."""
        self.ax = snap(triangle.a.x)
        self.ay = snap(triangle.a.y)
        self.bx = snap(triangle.b.x)
        self.by = snap(triangle.b.y)
        self.cx = snap(triangle.c.x)
        self.cy = snap(triangle.c.y)

        var area = edge_at(self.ax, self.ay, self.bx, self.by, self.cx, self.cy)
        self.swapped = area < 0
        if self.swapped:
            # Exchange b and c to make the winding positive. Doing it here
            # means the per-pixel test never has to ask which way round it is.
            var tx = self.bx
            var ty = self.by
            self.bx = self.cx
            self.by = self.cy
            self.cx = tx
            self.cy = ty
            area = -area
        self.area = area

        # A pixel exactly on an edge has an edge value of zero. Top and left
        # edges keep it; the others need a strictly positive value, which a
        # bias of -1 expresses without a second comparison in the loop.
        self.bias_ab = 0 if _is_top_left(
            self.ax, self.ay, self.bx, self.by
        ) else -1
        self.bias_bc = 0 if _is_top_left(
            self.bx, self.by, self.cx, self.cy
        ) else -1
        self.bias_ca = 0 if _is_top_left(
            self.cx, self.cy, self.ax, self.ay
        ) else -1

    def is_degenerate(self) -> Bool:
        """Return True if the three corners are collinear on the grid."""
        return self.area == 0

    def sample(self, index: Int) -> Int:
        """Return the grid coordinate of the centre of pixel row/column `index`.

        Sampling at the centre rather than the corner is why a half-step is
        added; the same arithmetic serves both axes.
        """
        return index * SUBPIXEL + SUBPIXEL // 2


@fieldwise_init
struct _Fragment(ImplicitlyCopyable):
    """Whether a pixel is covered, and its barycentric weights if so."""

    var covered: Bool
    var wa: Float32
    var wb: Float32
    var wc: Float32


def _test(coverage: _Coverage, x: Int, y: Int) -> _Fragment:
    """Test one pixel centre against a prepared triangle.

    Returns the weights of the caller's original corners, undoing the winding
    swap if there was one.
    """
    var px = coverage.sample(x)
    var py = coverage.sample(y)

    var e_ab = edge_at(
        coverage.ax, coverage.ay, coverage.bx, coverage.by, px, py
    )
    var e_bc = edge_at(
        coverage.bx, coverage.by, coverage.cx, coverage.cy, px, py
    )
    var e_ca = edge_at(
        coverage.cx, coverage.cy, coverage.ax, coverage.ay, px, py
    )

    if (
        e_ab + coverage.bias_ab < 0
        or e_bc + coverage.bias_bc < 0
        or e_ca + coverage.bias_ca < 0
    ):
        return _Fragment(False, Float32(0), Float32(0), Float32(0))

    # The edge opposite a corner is that corner's weight.
    var area = Float32(coverage.area)
    var first = Float32(e_bc) / area
    var second = Float32(e_ca) / area
    var third = Float32(e_ab) / area
    if coverage.swapped:
        return _Fragment(True, first, third, second)
    return _Fragment(True, first, second, third)


@fieldwise_init
struct Triangle(ImplicitlyCopyable):
    """Three 2D vertices in screen space."""

    var a: Vector2
    var b: Vector2
    var c: Vector2

    def area2(self) -> Float32:
        """Return the signed twice-area, negative for clockwise winding."""
        return edge(self.a, self.b, self.c)

    def contains(self, p: Vector2) -> Bool:
        """Return True if `p` lies inside the triangle or on its boundary.

        The geometric predicate, inclusive on every edge and accepting either
        winding. Rasterization deliberately does not use this: filling wants
        each shared edge to belong to exactly one triangle, which is the
        opposite of inclusive.
        """
        var area = self.area2()
        if area == 0:
            return False

        var e0 = edge(self.a, self.b, p)
        var e1 = edge(self.b, self.c, p)
        var e2 = edge(self.c, self.a, p)

        # Accept either winding order. All boundary edges are inclusive.
        if area > 0:
            return e0 >= 0 and e1 >= 0 and e2 >= 0
        return e0 <= 0 and e1 <= 0 and e2 <= 0


@fieldwise_init
struct _Bounds(ImplicitlyCopyable):
    """The pixel rows and columns a triangle can possibly touch."""

    var left: Int
    var right: Int
    var top: Int
    var bottom: Int


def _bounds(triangle: Triangle, width: Int, height: Int) -> _Bounds:
    """Return the triangle's bounding box, clamped to the framebuffer."""
    var left = min(triangle.a.x, min(triangle.b.x, triangle.c.x))
    var right = max(triangle.a.x, max(triangle.b.x, triangle.c.x))
    var top = min(triangle.a.y, min(triangle.b.y, triangle.c.y))
    var bottom = max(triangle.a.y, max(triangle.b.y, triangle.c.y))
    return _Bounds(
        max(0, Int(floor(left))),
        min(width - 1, Int(ceil(right))),
        max(0, Int(floor(top))),
        min(height - 1, Int(ceil(bottom))),
    )


def rasterize(triangle: Triangle, mut target: Framebuffer, color: Color) raises:
    """Fill every pixel of `target` covered by `triangle` with `color`.

    Samples at each pixel's center, with the image origin at the top left.
    """
    var coverage = _Coverage(triangle)
    if coverage.is_degenerate():
        return

    var box = _bounds(triangle, target.width, target.height)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        for x in range(box.left, box.right + 1):
            if _test(coverage, x, y).covered:
                target.set_pixel(x, y, color)


def rasterize_depth(
    a: Vector3,
    b: Vector3,
    c: Vector3,
    mut target: Framebuffer,
    color: Color,
) raises:
    """Fill a triangle, keeping only fragments nearer than the depth buffer.

    Each corner carries screen-space x and y with its NDC depth in z, which is
    exactly what `PerspectiveCamera.project` returns.

    Interpolating that z linearly across the screen is correct, and worth being
    explicit about because the neighbouring rule is the opposite: *world* depth
    and attributes like texture coordinates need perspective-correct
    interpolation through 1/w. NDC depth does not, because the perspective
    divide has already happened, and the result is a function that varies
    linearly in screen space. It is the reason hardware depth buffers store
    this value rather than distance.

    Args:
        a: First corner, screen x and y with NDC depth in z.
        b: Second corner.
        c: Third corner.
        target: The framebuffer to draw into.
        color: The colour to write where the triangle wins.

    Raises:
        Error: If a pixel write lands out of bounds, which the loop prevents.
    """
    var flat = Triangle(Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
    var coverage = _Coverage(flat)
    if coverage.is_degenerate():
        return

    var box = _bounds(flat, target.width, target.height)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        for x in range(box.left, box.right + 1):
            var fragment = _test(coverage, x, y)
            if not fragment.covered:
                continue
            var z = fragment.wa * a.z + fragment.wb * b.z + fragment.wc * c.z
            if target.test_depth(x, y, z):
                target.set_pixel(x, y, color)


def _blend(
    a: UInt8, b: UInt8, c: UInt8, wa: Float32, wb: Float32, wc: Float32
) -> UInt8:
    """Return one colour channel mixed by three barycentric weights."""
    # Inside a triangle every barycentric weight is non-negative and they sum
    # to one, so the mix stays between the inputs and cannot go negative; only
    # the rounding on a 255 needs clamping.
    var value = Float32(a) * wa + Float32(b) * wb + Float32(c) * wc + 0.5
    if value > 255:
        return 255
    return UInt8(value)


def rasterize_shaded(
    a: Vector3,
    b: Vector3,
    c: Vector3,
    color_a: Color,
    color_b: Color,
    color_c: Color,
    mut target: Framebuffer,
) raises:
    """Fill a triangle whose corners each carry their own colour.

    The colour is mixed across the face by the same barycentric weights the
    depth uses, which is Gouraud shading: lighting is evaluated per corner and
    interpolated between, rather than once for the whole face.

    Unlike depth, colour interpolated linearly in screen space is only an
    approximation — strictly it should go through 1/w like any other vertex
    attribute. The error grows with how much perspective a single triangle
    spans, so it is invisible on a subdivided sphere and would show on a floor
    plane drawn as two enormous triangles.

    Args:
        a: First corner, screen x and y with NDC depth in z.
        b: Second corner.
        c: Third corner.
        color_a: Colour at the first corner.
        color_b: Colour at the second.
        color_c: Colour at the third.
        target: The framebuffer to draw into.

    Raises:
        Error: If a pixel write lands out of bounds, which the loop prevents.
    """
    var flat = Triangle(Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
    var coverage = _Coverage(flat)
    if coverage.is_degenerate():
        return

    var box = _bounds(flat, target.width, target.height)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        for x in range(box.left, box.right + 1):
            var fragment = _test(coverage, x, y)
            if not fragment.covered:
                continue
            var wa = fragment.wa
            var wb = fragment.wb
            var wc = fragment.wc
            var z = wa * a.z + wb * b.z + wc * c.z
            if target.test_depth(x, y, z):
                target.set_pixel(
                    x,
                    y,
                    Color(
                        _blend(color_a.r, color_b.r, color_c.r, wa, wb, wc),
                        _blend(color_a.g, color_b.g, color_c.g, wa, wb, wc),
                        _blend(color_a.b, color_b.b, color_c.b, wa, wb, wc),
                        _blend(color_a.a, color_b.a, color_c.a, wa, wb, wc),
                    ),
                )
