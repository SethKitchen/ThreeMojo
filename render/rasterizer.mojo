# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Software triangle rasterization.

`rasterize` fills a flat 2D triangle and writes every covered pixel.
`rasterize_depth` takes the same triangle with a depth per corner and writes
a pixel only when it is nearer than what is already there, which is what lets
geometry be submitted in any order.

Each triangle is scanned only inside its own bounding box. Walking the whole
framebuffer per triangle is the obvious way to write this and costs the same
for a triangle covering four pixels as for one covering the screen; a sphere
of several hundred triangles made that difference impossible to ignore.

No top-left fill rule. Two triangles sharing an edge both test the pixels
along it, and because the edge function is evaluated from different corner
orderings for each, rounding can put a pixel fractionally outside *both* —
leaving a one-pixel crack along the shared diagonal of a quad. It is rare and
grows with triangle size. Fixing it properly means snapping vertices to a
fixed-point grid so the edge function is exact, which is what hardware does.
"""


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


from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import ceil, floor, max, min


def edge(a: Vector2, b: Vector2, p: Vector2) -> Float32:
    """Return the signed twice-area of triangle (a, b, p).

    The sign tells you which side of the line a->b the point p falls on, which
    is the whole basis of the inside test below.
    """
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


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
        """Return True if `p` lies inside the triangle or on its boundary."""
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


def rasterize(triangle: Triangle, mut target: Framebuffer, color: Color) raises:
    """Fill every pixel of `target` covered by `triangle` with `color`.

    Samples at each pixel's center, with the image origin at the top left.
    """
    var box = _bounds(triangle, target.width, target.height)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        for x in range(box.left, box.right + 1):
            var p = Vector2(Float32(x) + 0.5, Float32(y) + 0.5)
            if triangle.contains(p):
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
    var area = flat.area2()
    if area == 0:
        return

    var box = _bounds(flat, target.width, target.height)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        for x in range(box.left, box.right + 1):
            var p = Vector2(Float32(x) + 0.5, Float32(y) + 0.5)
            if not flat.contains(p):
                continue
            # The same three edge values the inside test used are, divided by
            # the total area, the barycentric weights of the opposite corners.
            var wa = edge(flat.b, flat.c, p) / area
            var wb = edge(flat.c, flat.a, p) / area
            var wc = edge(flat.a, flat.b, p) / area
            var z = wa * a.z + wb * b.z + wc * c.z
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
    var area = flat.area2()
    if area == 0:
        return

    var box = _bounds(flat, target.width, target.height)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        for x in range(box.left, box.right + 1):
            var p = Vector2(Float32(x) + 0.5, Float32(y) + 0.5)
            if not flat.contains(p):
                continue
            var wa = edge(flat.b, flat.c, p) / area
            var wb = edge(flat.c, flat.a, p) / area
            var wc = edge(flat.a, flat.b, p) / area
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
