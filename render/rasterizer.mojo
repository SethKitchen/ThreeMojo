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

Which pixels a triangle covers is decided by `render.fillrule`, in exact
integer arithmetic, and that module explains why. It is shared with the GPU
kernel so that both answer identically — the property `tests/test_gpu.mojo`
asserts pixel for pixel.
"""

from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer
from render.fillrule import SUBPIXEL, bias, edge_at, sample, snap
from std.math import ceil, floor, max, min


def edge(a: Vector2, b: Vector2, p: Vector2) -> Float32:
    """Return the signed twice-area of triangle (a, b, p).

    The sign tells you which side of the line a->b the point p falls on. This
    is the floating-point form, kept for `area2` and for callers asking a
    geometric question — backface culling, say. Rasterization uses the exact
    fixed-point form in `render.fillrule` instead, for the reasons given
    there.
    """
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


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
        self.bias_ab = bias(self.ax, self.ay, self.bx, self.by)
        self.bias_bc = bias(self.bx, self.by, self.cx, self.cy)
        self.bias_ca = bias(self.cx, self.cy, self.ax, self.ay)

    def is_degenerate(self) -> Bool:
        """Return True if the three corners are collinear on the grid."""
        return self.area == 0


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
    var px = sample(x)
    var py = sample(y)

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


@fieldwise_init
struct RasterVertex(ImplicitlyCopyable):
    """One corner as the rasterizer wants it: screen position and varyings.

    This is the boundary between what a renderer works out and what a
    rasterizer fills in. Everything perspective has already been applied to
    `x`, `y` and `z`; `inv_w` is what is left of the divide, and it is what
    lets any *attribute* be interpolated correctly rather than only depth.

    Keeping it a named type rather than a pile of arguments is the point:
    texture coordinates and per-vertex properties go here when they arrive,
    without changing a signature or teaching the caller a new argument order.
    """

    # Screen-space pixel coordinates.
    var x: Float32
    var y: Float32
    # NDC depth, already divided. Interpolated affinely in screen space, which
    # is correct: the projection makes depth linear in screen space precisely
    # so that a depth buffer can work this way. Do not put this through
    # `inv_w` as well.
    var z: Float32
    # The reciprocal of the clip-space w this corner was divided by.
    var inv_w: Float32
    var color: FloatColor
    # Texture coordinates, interpolated the same perspective-correct way the
    # colour is. They reach the fragment rather than being folded into the
    # colour at the vertex, because that is what sampling a texture will need.
    var u: Float32
    var v: Float32


# What a fragment's colour is taken from. An Int rather than a richer type
# because there are two of them; when a texture arrives it becomes a third and
# the argument grows into something that carries the texture with it.
comptime SHADE_LIT = 0
comptime SHADE_UV = 1


def rasterize_shaded(
    a: RasterVertex,
    b: RasterVertex,
    c: RasterVertex,
    mut target: Framebuffer,
    mode: Int = SHADE_LIT,
) raises:
    """Fill a triangle whose corners each carry their own colour.

    The colour is mixed across the face by the triangle's barycentric weights,
    which is Gouraud shading: lighting is evaluated per corner and interpolated
    between, rather than once for the whole face.

    The mix is *perspective correct*. Screen-space barycentric weights are not
    the weights the surface itself sees — perspective compresses the far half
    of a triangle into fewer pixels — so an attribute interpolated straight
    across the screen drifts from what the geometry says. The correction is to
    weight by `inv_w` and divide by the interpolated `inv_w`:

        attribute = sum(w_i * a_i * inv_w_i) / sum(w_i * inv_w_i)

    which is the same rule a graphics API applies to any non-flat varying. The
    error it removes grows with how much perspective one triangle spans: it is
    invisible on a subdivided sphere and obvious on a floor drawn as two
    enormous triangles. Depth is deliberately *not* corrected this way; see
    `RasterVertex.z`.

    Args:
        a: First corner.
        b: Second corner.
        c: Third corner.
        target: The framebuffer to draw into.
        mode: `SHADE_LIT` to write the interpolated colour, or `SHADE_UV` to
            write the interpolated texture coordinates as red and green. The
            second exists to make the perspective correction visible: with it
            a floor plane drawn as two large triangles shows the difference
            between a correct interpolation and an affine one directly, which
            no assertion about a colour channel really does.

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
            if not target.test_depth(x, y, z):
                continue

            # The denominator of the perspective correction, and the
            # interpolated reciprocal depth in its own right.
            var inv_w = wa * a.inv_w + wb * b.inv_w + wc * c.inv_w
            # An orthographic or degenerate setup can leave this at zero, in
            # which case there is no perspective to correct for and the plain
            # screen-space weights are the right answer.
            var share_a = wa
            var share_b = wb
            var share_c = wc
            if inv_w != 0:
                share_a = wa * a.inv_w / inv_w
                share_b = wb * b.inv_w / inv_w
                share_c = wc * c.inv_w / inv_w

            var shaded = FloatColor(
                a.color.r * share_a + b.color.r * share_b + c.color.r * share_c,
                a.color.g * share_a + b.color.g * share_b + c.color.g * share_c,
                a.color.b * share_a + b.color.b * share_b + c.color.b * share_c,
                a.color.a * share_a + b.color.a * share_b + c.color.a * share_c,
            )
            if mode == SHADE_UV:
                shaded = FloatColor(
                    a.u * share_a + b.u * share_b + c.u * share_c,
                    a.v * share_a + b.v * share_b + c.v * share_c,
                    0.0,
                    1.0,
                )
            target.set_pixel(x, y, shaded.quantize())
