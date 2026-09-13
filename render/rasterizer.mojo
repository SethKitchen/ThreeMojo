# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Software triangle rasterization.

`rasterize` fills a flat 2D triangle and writes every covered pixel.
`rasterize_depth` takes the same triangle with a depth per corner and writes
a pixel only when it is nearer than what is already there, which is what lets
geometry be submitted in any order.

No clipping and no top-left fill rule: a triangle crossing the near plane will
misbehave, and two triangles sharing an edge may both claim the pixels on it.
"""

from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer


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
    # A Framebuffer always has positive dimensions, so neither loop can run
    # zero times.
    for y in range(target.height):  # pragma: no branch
        for x in range(target.width):  # pragma: no branch
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

    # A Framebuffer always has positive dimensions, so neither loop can run
    # zero times.
    for y in range(target.height):  # pragma: no branch
        for x in range(target.width):  # pragma: no branch
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
