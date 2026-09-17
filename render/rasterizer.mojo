# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Software triangle rasterization.

`rasterize` fills a flat 2D triangle and writes every covered pixel.
`rasterize_depth` takes the same triangle with a depth per corner and writes a
pixel only when it is nearer than what is already there, which is what lets
geometry be submitted in any order. `rasterize_shaded` additionally mixes a
color given per corner, and blends rather than replaces when that color is
translucent.

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
from materials.material import (
    BLEND,
    DEPTH,
    LAMBERT,
    NORMALS,
    OPAQUE,
    PHONG,
    Blending,
    MaterialKind,
)
from render.target import RenderTarget
from render.srgb import LINEAR
from render.texture import IGNORED, Texture
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from lights.lighting import Lighting
from core.fog import FogView, fog_mix
from render.fillrule import SUBPIXEL, bias, edge_at, sample, snap
from std.math import ceil, floor, isfinite, log2, max, min, sqrt
from std.runtime.asyncrt import TaskGroup


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
    # One over the area, taken once per triangle. Every covered pixel
    # multiplies three edge values by it; dividing by the area instead was
    # three divides per pixel, and a divide is several times the cost of a
    # multiply. The GPU kernel does the same, so the two still agree.
    var inv_area: Float32
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
        # A degenerate triangle has no area and is never scanned, so the
        # reciprocal of zero is never read; it is kept finite anyway.
        self.inv_area = Float32(0)
        if area != 0:
            self.inv_area = Float32(1) / Float32(area)

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


@fieldwise_init
struct _Edges(ImplicitlyCopyable):
    """The three edge functions of a prepared triangle at one sample point.

    Held as a value so that a scan can *step* them rather than recompute
    them. Each edge function is linear in the sample point, so moving one
    pixel right or one pixel down changes it by a constant, and the constant
    is an exact integer. Adding it is one instruction per edge per pixel
    where evaluating from scratch was six, and because every quantity is an
    integer the stepped value is bit-for-bit what a fresh evaluation gives;
    the fill rule reads the same numbers either way.
    """

    var ab: Int
    var bc: Int
    var ca: Int

    def __add__(self, other: Self) -> Self:
        """Return these edge values moved by `other`, a step."""
        return _Edges(
            self.ab + other.ab, self.bc + other.bc, self.ca + other.ca
        )


def _edges_at(coverage: _Coverage, x: Int, y: Int) -> _Edges:
    """Evaluate the three edge functions at pixel (x, y)'s center."""
    var px = sample(x)
    var py = sample(y)
    return _Edges(
        edge_at(coverage.ax, coverage.ay, coverage.bx, coverage.by, px, py),
        edge_at(coverage.bx, coverage.by, coverage.cx, coverage.cy, px, py),
        edge_at(coverage.cx, coverage.cy, coverage.ax, coverage.ay, px, py),
    )


def _step_right(coverage: _Coverage) -> _Edges:
    """Return how each edge value changes from one pixel to the next right.

    `edge_at(a, b, p)` is `(bx - ax) * (py - ay) - (by - ay) * (px - ax)`, so
    moving `px` by one pixel, which is `SUBPIXEL` grid steps, changes it by
    `-(by - ay) * SUBPIXEL`.
    """
    return _Edges(
        -(coverage.by - coverage.ay) * SUBPIXEL,
        -(coverage.cy - coverage.by) * SUBPIXEL,
        -(coverage.ay - coverage.cy) * SUBPIXEL,
    )


def _step_down(coverage: _Coverage) -> _Edges:
    """Return how each edge value changes from one row to the next down."""
    return _Edges(
        (coverage.bx - coverage.ax) * SUBPIXEL,
        (coverage.cx - coverage.bx) * SUBPIXEL,
        (coverage.ax - coverage.cx) * SUBPIXEL,
    )


def _covers(coverage: _Coverage, edges: _Edges) -> Bool:
    """Return True if a sample with these edge values is inside.

    The top-left rule is in the biases: a pixel exactly on an edge has an
    edge value of zero, and only a top or left edge keeps it.
    """
    return not (
        edges.ab + coverage.bias_ab < 0
        or edges.bc + coverage.bias_bc < 0
        or edges.ca + coverage.bias_ca < 0
    )


def _weights_of(coverage: _Coverage, edges: _Edges) -> _Fragment:
    """Return the barycentric weights for these edge values, covered or not.

    Coverage is not tested here, because mip selection needs the weights at
    the *neighboring* pixels and those are routinely outside the triangle.
    Barycentric coordinates extrapolate perfectly well; it is only coverage
    that stops at the edge. The edge opposite a corner is that corner's
    weight, and the winding swap is undone so the caller gets its own
    corner order back.
    """
    var first = Float32(edges.bc) * coverage.inv_area
    var second = Float32(edges.ca) * coverage.inv_area
    var third = Float32(edges.ab) * coverage.inv_area
    if coverage.swapped:
        return _Fragment(True, first, third, second)
    return _Fragment(True, first, second, third)


def _weights(coverage: _Coverage, x: Int, y: Int) -> _Fragment:
    """Return a pixel center's barycentric weights, covered or not."""
    return _weights_of(coverage, _edges_at(coverage, x, y))


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


def _bounds(
    triangle: Triangle,
    width: Int,
    height: Int,
    first_row: Int = 0,
    last_row: Int = -1,
) -> _Bounds:
    """Return the triangle's bounding box, clamped to the framebuffer.

    Args:
        triangle: The screen-space triangle.
        width: Framebuffer width.
        height: Framebuffer height.
        first_row: The first row this scan may touch, for a caller that has
            split the image into bands.
        last_row: The last row it may touch, or -1 for the bottom of the
            image.

    Returns:
        The rows and columns to scan, possibly empty.
    """
    var left = min(triangle.a.x, min(triangle.b.x, triangle.c.x))
    var right = max(triangle.a.x, max(triangle.b.x, triangle.c.x))
    var top = min(triangle.a.y, min(triangle.b.y, triangle.c.y))
    var bottom = max(triangle.a.y, max(triangle.b.y, triangle.c.y))
    var lowest = height - 1
    if last_row >= 0:
        lowest = min(lowest, last_row)
    return _Bounds(
        max(0, Int(floor(left))),
        min(width - 1, Int(ceil(right))),
        max(first_row, Int(floor(top))),
        min(lowest, Int(ceil(bottom))),
    )


def rasterize(triangle: Triangle, mut target: Framebuffer, color: Color) raises:
    """Fill every pixel of `target` covered by `triangle` with `color`.

    Samples at each pixel's center, with the image origin at the top left.
    """
    var coverage = _Coverage(triangle)
    if coverage.is_degenerate():
        return

    var box = _bounds(triangle, target.width, target.height)
    var right = _step_right(coverage)
    var down = _step_down(coverage)
    var row = _edges_at(coverage, box.left, box.top)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        var edges = row
        for x in range(box.left, box.right + 1):
            if _covers(coverage, edges):
                target.set_pixel(x, y, color)
            edges = edges + right
        row = row + down


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
    explicit about because the neighboring rule is the opposite: *world* depth
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
        color: The color to write where the triangle wins.

    Raises:
        Error: If a pixel write lands out of bounds, which the loop prevents.
    """
    var flat = Triangle(Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
    var coverage = _Coverage(flat)
    if coverage.is_degenerate():
        return

    var box = _bounds(flat, target.width, target.height)
    var right = _step_right(coverage)
    var down = _step_down(coverage)
    var row = _edges_at(coverage, box.left, box.top)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        var edges = row
        for x in range(box.left, box.right + 1):
            if _covers(coverage, edges):
                var fragment = _weights_of(coverage, edges)
                var z = (
                    fragment.wa * a.z + fragment.wb * b.z + fragment.wc * c.z
                )
                if target.test_depth(x, y, z):
                    target.set_pixel(x, y, color)
            edges = edges + right
        row = row + down


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
    # The surface's own color, in linear light, with the material's opacity
    # already in its alpha. Not lit: lighting happens per fragment now, so
    # what a corner carries is what the material says rather than what that
    # one corner caught.
    var color: FloatColor
    # The world-space normal. Interpolated across the triangle and normalized
    # again at every fragment, which is what makes the shading per-fragment
    # rather than per-vertex. Already flipped by `Renderer.prepare` if this
    # triangle is being seen from behind.
    var normal: Vector3
    # Texture coordinates, interpolated the same perspective-correct way the
    # color is. They reach the fragment rather than being folded into the
    # color at the vertex, because that is what sampling a texture will need.
    var u: Float32
    var v: Float32
    # `OPAQUE` or `BLEND`, resolved from the material by `Renderer.prepare`
    # rather than guessed at from this vertex's alpha. Per-triangle metadata,
    # like the texture below: the whole triangle comes from one material, so
    # all three corners carry the same answer and the first is read.
    var blend: Blending
    # Which texture to sample, or `NO_TEXTURE` for none. It travels with the
    # vertex because `Renderer.prepare` returns one flat list of triangles for
    # a whole scene, and the meshes in a scene need not share a material.
    var texture: TextureId
    # Where this corner is in the world, for lights that have a position. A
    # directional light needs only the normal; a point light needs to know
    # how far the surface is from the bulb and in which direction, and the
    # projection threw that away. Interpolated perspective-correctly like the
    # normal, so a fragment knows where *it* is.
    var world: Vector3
    # What kind of surface this is: `LAMBERT`, lit by the scene's lights;
    # `BASIC`, its own color whatever the lights do -- a sky, a sprite, an
    # overlay; `NORMALS`, the normal written as a color; or `DEPTH`, how
    # far away it is. The last two show data rather than light, and a
    # `NORMALS` corner's `normal` is in view space rather than world space,
    # since it is shown rather than lit. Per-triangle metadata like the
    # blend policy: read from the first corner, checked to agree.
    var kind: MaterialKind
    # Light this surface gives off, linear, added after the lights and
    # untouched by them: three.js's `emissive`. Interpolated like the color,
    # and multiplied per fragment by `emissive_map` when there is one.
    var emissive: FloatColor
    # Which texture multiplies the emissive, or `NO_TEXTURE`. Per-triangle
    # metadata like `texture`: read from the first corner, checked to agree.
    var emissive_map: TextureId
    # Which texture's green channel thins this surface, or `NO_TEXTURE`:
    # three.js's `alphaMap`. Per-triangle metadata like `texture`.
    var alpha_map: TextureId
    # The alpha a fragment must reach to be drawn, three.js's `alphaTest`.
    # Zero draws every fragment. Per-triangle metadata rather than a
    # varying, and the only float among it: all three corners carry the
    # material's number and the first is read.
    var alpha_test: Float32
    # How much light this surface sends toward the camera, linear: a
    # `PHONG` material's `specular`. Interpolated like the emissive, which
    # is also one color per material, and for the same reason -- a varying
    # costs the same as a constant here and needs no second mechanism.
    var specular: FloatColor
    # How tight that highlight is, three.js's `shininess`. Per-triangle
    # like the alpha test, and read from the first corner.
    var shininess: Float32
    # How far in front of the camera this corner is, in meters: three.js's
    # `vFogDepth`, minus the camera-space z, taken from the clipped
    # position as it is projected. Interpolated with perspective correction
    # like the color, so a fragment reads its fog off a small number
    # rather than recovering it from a large world coordinate, which
    # rounds the depth away far from the origin. Read only by the fog.
    var view_depth: Float32

    def __init__(
        out self,
        x: Float32,
        y: Float32,
        z: Float32,
        inv_w: Float32,
        color: FloatColor,
        u: Float32 = 0,
        v: Float32 = 0,
        texture: TextureId = NO_TEXTURE,
        blend: Blending = OPAQUE,
        normal: Vector3 = Vector3(0, 0, 1),
        world: Vector3 = Vector3(0, 0, 0),
        kind: MaterialKind = LAMBERT,
        emissive: FloatColor = FloatColor(0.0, 0.0, 0.0),
        emissive_map: TextureId = NO_TEXTURE,
        view_depth: Float32 = 0,
        alpha_map: TextureId = NO_TEXTURE,
        alpha_test: Float32 = 0,
        specular: FloatColor = FloatColor(0.0, 0.0, 0.0),
        shininess: Float32 = 0,
    ):
        """Create a corner. Texture coordinates and maps default to none.

        The normal defaults to facing the camera, so a hand-built triangle
        that does not care about lighting is lit square-on rather than edge-on
        or, worse, from behind. The world position defaults to the origin,
        which only a point light would notice, and the corner defaults to
        `LAMBERT`, lit, which under `Lighting.uniform` changes nothing. The
        emissive defaults to black: no light given off. The depth defaults
        to zero, which is at the camera and in no fog. The alpha test
        defaults to zero, which throws no fragment away, and the specular
        to black, which is no highlight.
        """
        self.x = x
        self.y = y
        self.z = z
        self.inv_w = inv_w
        self.color = color
        self.normal = normal
        self.u = u
        self.v = v
        self.texture = texture
        self.blend = blend
        self.world = world
        self.kind = kind
        self.emissive = emissive
        self.emissive_map = emissive_map
        self.view_depth = view_depth
        self.alpha_map = alpha_map
        self.alpha_test = alpha_test
        self.specular = specular
        self.shininess = shininess


@fieldwise_init
struct ShadeMode(Equatable, ImplicitlyCopyable, Writable):
    """What a fragment's color is taken from, as a type rather than an int.

    The three cases differ in which numbers they read, not in what the
    rasterizer does around them. `SHADE_TEXTURE` multiplies the sampled texel
    by the interpolated lighting, so a white texture shades exactly as
    `SHADE_LIT` does and an unlit white mesh shows the image unchanged.

    A type because an unrecognized integer here was once read in opposite
    directions by the two backends: the CPU's last branch treated it as
    textured and the GPU's as lit. The type stops a bare integer at compile
    time. It does not stop `ShadeMode(99)` -- a struct's fields are open --
    so both rasterizers refuse one with `is_valid` before drawing, and their
    branches now ask for each mode by name rather than falling through.
    `value` is what crosses to the kernel.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three modes there are."""
        return self == SHADE_LIT or self == SHADE_UV or self == SHADE_TEXTURE


comptime SHADE_LIT = ShadeMode(0)
comptime SHADE_UV = ShadeMode(1)
comptime SHADE_TEXTURE = ShadeMode(2)


def _coordinates_at(
    a: RasterVertex,
    b: RasterVertex,
    c: RasterVertex,
    weights: _Fragment,
) -> Vector2:
    """Return the perspective-correct texture coordinates at one sample.

    The same correction `rasterize_shaded` applies to color, factored out
    because mip selection needs it at three sample points rather than one.
    """
    var inv_w = (
        weights.wa * a.inv_w + weights.wb * b.inv_w + weights.wc * c.inv_w
    )
    var share_a = weights.wa
    var share_b = weights.wb
    var share_c = weights.wc
    if inv_w != 0:
        var rcp = Float32(1) / inv_w
        share_a = weights.wa * a.inv_w * rcp
        share_b = weights.wb * b.inv_w * rcp
        share_c = weights.wc * c.inv_w * rcp
    return Vector2(
        a.u * share_a + b.u * share_b + c.u * share_c,
        a.v * share_a + b.v * share_b + c.v * share_c,
    )


def _sample_map(
    image: Texture,
    u: Float32,
    v: Float32,
    a: RasterVertex,
    b: RasterVertex,
    c: RasterVertex,
    coverage: _Coverage,
    x: Int,
    y: Int,
) -> FloatColor:
    """Return `image` sampled at (u, v) for the pixel at (x, y).

    Straight from the one level when the image has one. Otherwise from the
    level the pixel's footprint chooses, measured from the coordinates at
    the pixels one over and one down -- see `mip_level`. Shared by the
    material's map and its emissive map, so both are filtered alike, and
    mirrored on the device by `render.gpu._sample_slot`.
    """
    if image.levels == 1:
        return image.sample(u, v)
    var here = Vector2(u, v)
    var right = _coordinates_at(a, b, c, _weights(coverage, x + 1, y))
    var below = _coordinates_at(a, b, c, _weights(coverage, x, y + 1))
    return image.sample_level(
        u,
        v,
        mip_level(
            Vector2(right.x - here.x, right.y - here.y),
            Vector2(below.x - here.x, below.y - here.y),
            image.width,
            image.height,
        ),
    )


def mip_level(
    along_x: Vector2, along_y: Vector2, width: Int, height: Int
) -> Float32:
    """Return how far down the mip chain one pixel's footprint reaches.

    A hardware rasterizer shades pixels in 2x2 quads and estimates the
    derivative by subtracting a neighbor's value from its own, running extra
    *helper invocations* outside the primitive where a quad is not fully
    covered so that those neighbors exist. This one shades each pixel alone
    and needs no helpers, because the function is known: texture coordinates
    across a triangle are an analytic expression, so the value one pixel over
    can simply be evaluated.

    What that buys is independence from neighboring threads, not extra
    precision. The footprint is still a finite difference — the *exact*
    displacement to the next pixel center, which is what a footprint is, but
    not the exact derivative of a perspective-correct coordinate, which
    curves between the two samples. For `u(x) = x / (1 + x)` at `x = 0` the
    difference over one pixel is 0.5 where the derivative is 1. That is the
    same estimate hardware makes, and it is the right order of magnitude for
    choosing between levels that differ by a factor of two.

    The level is the log of the longer footprint edge measured in texels: a
    pixel covering two texels across is one level down, four is two, and so
    on, which is exactly the halving the chain stores. The longer edge rather
    than the shorter or an average, because a surface seen edge-on is
    compressed in one direction only and it is the compressed direction that
    has to stop aliasing.

    Args:
        along_x: How far the coordinates move over one pixel in x, in uv.
        along_y: The same down one pixel in y.
        width: The texture's full-size width in texels.
        height: Its full-size height.

    Returns:
        The fractional level. Negative where the surface is magnified, which
        is where the full-size image is already the right answer.
    """
    var across = Float32(width)
    var down = Float32(height)
    var in_x = _length(along_x.x * across, along_x.y * down)
    var in_y = _length(along_y.x * across, along_y.y * down)
    var longest = in_x
    if in_y > longest:
        longest = in_y
    if longest <= 0:
        return 0
    return log2(longest)


def _length(x: Float32, y: Float32) -> Float32:
    """Return the length of a two-component vector."""
    return sqrt(x * x + y * y)


def data_color(r: Float32, g: Float32, b: Float32, a: Float32) -> FloatColor:
    """Return three channels of data as the light that resolves to their bytes.

    Texture coordinates in the uv debug view, a normal under a `NORMALS`
    material, a depth under a `DEPTH` material: none of them is light, and
    the sRGB curve describes how a display turns light into brightness.
    Putting them through it would make the view lie about its own numbers.
    So each channel is quantized to the byte it should show, without the
    curve, and that byte is decoded back through the curve into the linear
    buffer, where `RenderTarget.resolve`'s encode returns it unchanged. The
    target is told the pixel holds data, and keeps the tone mapping off it.

    The alpha is coverage, not data, and is carried as it is. The kernel
    does the same through its uploaded ramp, which holds the same 256
    values this decode computes.

    Args:
        r: The red channel to show, nominally zero to one.
        g: The green channel.
        b: The blue channel.
        a: The fragment's alpha, kept as it is.

    Returns:
        The linear color that resolves to those bytes.
    """
    var bytes = FloatColor(r, g, b, 1.0).quantize()
    var decoded = FloatColor(srgb=bytes)
    return FloatColor(decoded.r, decoded.g, decoded.b, a)


def packed_normal(facing: Vector3) -> Vector3:
    """Return a unit normal mapped into zero to one per axis, three.js's
    `packNormalToRGB`: each component halved and moved up by a half, so a
    surface square-on to the camera is (0.5, 0.5, 1).

    Args:
        facing: The unit normal, in the space it is to be shown in.

    Returns:
        The three channels, before quantization.
    """
    return Vector3(
        facing.x * 0.5 + 0.5, facing.y * 0.5 + 0.5, facing.z * 0.5 + 0.5
    )


def packed_depth(z: Float32) -> Float32:
    """Return an NDC depth as the gray a `DEPTH` material shows for it: one
    at the near plane, zero at the far plane, three.js's `MeshDepthMaterial`
    under `BasicDepthPacking`.

    three.js reads `gl_FragCoord.z`, the window-space depth from zero to
    one, and writes one minus it. NDC depth runs from -1 to 1 here, as it
    does there before the viewport, so the window-space depth is half of
    it plus a half.

    Args:
        z: The NDC depth, -1 at the near plane and 1 at the far.

    Returns:
        The gray, nominally zero to one.
    """
    return 1 - (z * 0.5 + 0.5)


def interpolate_alpha(
    first: Float32,
    second: Float32,
    third: Float32,
    share_b: Float32,
    share_c: Float32,
) -> Float32:
    """Return a fragment's alpha, in the one form that keeps a constant one
    constant.

    The obvious spelling, `a * sa + b * sb + c * sc`, is three rounded
    products and two rounded sums, and the three weights sum to one only up
    to rounding. So a triangle whose corners all carry an alpha of one can
    reach a fragment holding 0.99999994, which is invisible everywhere it
    is quantized and fatal where it is *compared*: an alpha test of one
    then throws away a fully opaque surface, and one of a half cuts holes
    in a uniformly half-covered one.

    Written as a difference from the first corner instead:

        alpha = a + sb * (b - a) + sc * (c - a)

    which is the same number in exact arithmetic, because the weights sum
    to one. When the three alphas are equal the differences are exactly
    zero and the first corner's value comes back untouched, whatever the
    weights rounded to. Where the alphas really do differ this rounds no
    worse than the sum it replaces.

    Only alpha is spelled this way. Red, green and blue reach a
    quantization and cannot show a last-bit error; alpha reaches a
    threshold and can. Both rasterizers call this, so neither can cut a
    hole the other keeps.

    Args:
        first: The first corner's alpha, the one the others are measured
            from.
        second: The second corner's alpha.
        third: The third corner's alpha.
        share_b: The second corner's perspective-correct weight.
        share_c: The third corner's weight.

    Returns:
        The interpolated alpha.
    """
    return first + share_b * (second - first) + share_c * (third - first)


def check_triangle_state(
    a: RasterVertex, b: RasterVertex, c: RasterVertex
) raises:
    """Reject per-triangle metadata neither backend could agree on.

    Both rasterizers read a triangle's texture and blend policy from its
    *first* corner, because both come from the material and are therefore the
    same on all three. That shortcut is only safe if the three really do
    agree, and that was not checked.

    The policy's *value* needs checking as well. The two backends once read
    an unknown one in opposite directions -- the CPU asked "is it `BLEND`?"
    and treated anything else as opaque, the GPU asked "is it `OPAQUE`?" and
    treated anything else as blended. `Blending` is a type now, which stops
    a bare 7 at compile time but not `Blending(7)`: a struct's fields are
    open, so the value check was wrongly dropped and is back. Shared here so
    that both refuse the same thing, and both now ask the host's question of
    whatever gets through.

    Args:
        a: The triangle's first corner, whose state is the authoritative one.
        b: Its second corner.
        c: Its third corner.

    Raises:
        Error: If the three corners do not agree on their blend policy, on
            any of their three maps, on their material kind, on their
            alpha test or on their shininess; if the agreed policy is
            neither `OPAQUE` nor `BLEND`, the agreed kind is none of the
            five, the agreed alpha test is outside zero to one or not
            finite, or the agreed shininess is negative or not finite; if
            the agreed kind shows data and the agreed policy is `BLEND`,
            which no pixel could resolve; or if any
            texture id is a negative other than `NO_TEXTURE`, which
            nothing can ever hold.
    """
    if b.blend != a.blend or c.blend != a.blend:
        raise Error("A triangle's corners disagree about blending")
    if b.texture != a.texture or c.texture != a.texture:
        raise Error("A triangle's corners disagree about their texture")
    if b.emissive_map != a.emissive_map or c.emissive_map != a.emissive_map:
        raise Error("A triangle's corners disagree about their emissive map")
    if b.alpha_map != a.alpha_map or c.alpha_map != a.alpha_map:
        raise Error("A triangle's corners disagree about their alpha map")
    if b.kind != a.kind or c.kind != a.kind:
        raise Error("A triangle's corners disagree about their material kind")
    # Before the agreement check below, because not-a-number is not equal
    # to itself: a NaN threshold would be reported as three corners
    # disagreeing when what is wrong is the number.
    if not isfinite(a.alpha_test) or a.alpha_test < 0 or a.alpha_test > 1:
        raise Error("A triangle's alpha test must be between zero and one")
    # Before its agreement check for the reason above: not a number is not
    # equal to itself.
    if not isfinite(a.shininess) or a.shininess < 0:
        raise Error("A triangle's shininess cannot be negative")
    if b.shininess != a.shininess or c.shininess != a.shininess:
        raise Error("A triangle's corners disagree about their shininess")
    if b.alpha_test != a.alpha_test or c.alpha_test != a.alpha_test:
        raise Error("A triangle's corners disagree about their alpha test")
    if not a.blend.is_valid():
        raise Error("A triangle's blend policy is neither OPAQUE nor BLEND")
    if not a.kind.is_valid():
        raise Error("A triangle's material kind is none of the five")
    # A fragment that shows data cannot be mixed into one that shows light:
    # the pixel would hold part of each and resolve as neither. Refused
    # here so that both backends refuse it, and so that `RenderTarget.blend`
    # can say a mixture is always light. See `render.target`.
    if a.kind.is_data() and a.blend == BLEND:
        raise Error(
            "A normal or depth material cannot blend: a pixel holds its"
            " bytes or the scene's light, not a mixture of the two"
        )
    if a.texture != NO_TEXTURE and a.texture.value < 0:
        raise Error("A triangle names a texture id that nothing can hold")
    if a.emissive_map != NO_TEXTURE and a.emissive_map.value < 0:
        raise Error("A triangle names an emissive map id that nothing can hold")
    if a.alpha_map != NO_TEXTURE and a.alpha_map.value < 0:
        raise Error("A triangle names an alpha map id that nothing can hold")


def check_alpha_map(image: Texture) raises:
    """Refuse an alpha map that is not stored as data.

    Its green channel is a coverage, so it must be `LINEAR`, or the sRGB
    decode turns a byte of 128 into 0.216 rather than 0.502. And it must be
    `IGNORED`, or bilinear filtering and the mip chain weight that green by
    an alpha that means nothing -- the reason an emissive map asks the same.

    Shared by both backends, so neither can accept what the other refuses.

    Args:
        image: The texture named as an alpha map.

    Raises:
        Error: If the texture's color space is not `LINEAR`, or it reads its
            alpha as coverage.
    """
    if image.color_space != LINEAR:
        raise Error(
            "An alpha map holds data, not color; build the texture with"
            " color_space=LINEAR"
        )
    if image.alpha != IGNORED:
        raise Error(
            "An alpha map must ignore its own alpha; build the texture with"
            " alpha=IGNORED"
        )


def rasterize_shaded(
    a: RasterVertex,
    b: RasterVertex,
    c: RasterVertex,
    mut target: RenderTarget,
    mode: ShadeMode = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    lighting: Lighting = Lighting.uniform(),
    first_row: Int = 0,
    last_row: Int = -1,
    fog: FogView = FogView.none(),
) raises:
    """Fill a triangle whose corners each carry their own color.

    The color is mixed across the face by the triangle's barycentric weights,
    which is how the surface's own color reaches a fragment. The *lighting*
    is not mixed: each fragment interpolates the normal instead, makes it a
    unit vector again, and evaluates every light there. Interpolating light
    computed at the corners is cheaper and is what this used to do, but a
    triangle can then only be as round as its corners.

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
        mode: `SHADE_LIT` to write the interpolated color, `SHADE_UV` to
            write the interpolated texture coordinates as red and green, or
            `SHADE_TEXTURE` to look the color up in `texture` and modulate
            it by the lighting. `SHADE_UV` exists to make the perspective
            correction visible: with it a floor plane drawn as two large
            triangles shows the difference between a correct interpolation
            and an affine one directly, which no assertion about a color
            channel really does.
        textures: Where `SHADE_TEXTURE` looks the triangle's map up. Which
            one it wants is on the vertices, so a single call can draw a
            scene whose meshes use different images. A vertex naming
            `NO_TEXTURE` samples the blank texture, which is opaque white and
            so leaves the lighting untouched — "no texture" is a value here
            rather than a branch.
        lighting: The scene's lights, resolved to world space. Evaluated once
            per fragment against the interpolated normal and world position.
            Defaults to `Lighting.uniform`, which leaves the corner colors
            alone — the same identity the blank texture provides, and what a
            hand-built triangle asking about coverage or depth wants. Only a
            `LAMBERT` triangle evaluates it. A `BASIC` one shows its own
            color; a `NORMALS` one shows its normal as a color and a `DEPTH`
            one its depth as a gray, both as data the fog and the tone
            mapping leave alone -- see `data_color`.
        first_row: The first row this call may write. `Renderer.render`
            splits the image into horizontal bands and rasterizes every
            triangle once per band on its own thread; a band owns its rows
            outright, so no two threads ever touch one pixel.
        last_row: The last row it may write, or -1 for the bottom.
        fog: The scene's fog, seen through the camera. Every fragment is
            mixed toward its color by its camera-space depth, after the
            lights and the emissive term, in linear light. Defaults to
            `FogView.none`, which leaves every fragment alone. `SHADE_UV`
            is never fogged, and nor is a `NORMALS` or `DEPTH` triangle:
            they show data, not light.

    Raises:
        Error: If the mode is none of the three, the fog view holds a kind
            or a number that `FogView.validate` refuses, a vertex names a
            texture the
            store does not have, the corners disagree about their maps,
            blend policy, material kind, alpha test or shininess or hold
            one that is none of the named values, an emissive map that
            `SHADE_TEXTURE` would open does not ignore its alpha, an alpha
            map it would open is not linear or does not ignore its alpha,
            or a pixel
            write lands out of bounds — the last of which the loop prevents.
    """
    if not mode.is_valid():
        raise Error("A shading mode that is none of the three")
    check_triangle_state(a, b, c)
    # A view of the fog can be built by hand, and its fields are open:
    # refused here, before a fragment reads it, as the GPU refuses it
    # before the launch.
    fog.validate()
    # An emissive map's alpha means nothing, and only a texture built to
    # ignore it filters accordingly -- see `render.texture.Alpha`. Asked
    # before the first fragment, as the GPU asks it before the launch, and
    # only when the map will be opened: SHADE_LIT never reads it.
    if a.emissive_map != NO_TEXTURE and mode == SHADE_TEXTURE:
        if textures.get(a.emissive_map).alpha != IGNORED:
            raise Error(
                "An emissive map must ignore its alpha; build the texture"
                " with alpha=IGNORED"
            )
    # An alpha map holds data, and says so twice: linear, or the sRGB curve
    # changes what its bytes mean, and alpha ignored, or filtering weights
    # its green by an alpha that means nothing. Asked here, as the GPU asks
    # it before the launch, and only when the map will be opened.
    if a.alpha_map != NO_TEXTURE and mode == SHADE_TEXTURE:
        check_alpha_map(textures.get(a.alpha_map))

    # Whether this surface composites, decided by the material and carried
    # here rather than inferred from a color. It changes two things
    # together: the fragment is mixed into what is already there rather than
    # replacing it, and it tests depth without *claiming* it, so a second
    # translucent surface behind this one still contributes.
    #
    # A debug view of texture coordinates is always opaque: it shows the
    # nearest surface's coordinates, and averaging several surfaces' would
    # mean nothing.
    #
    # The consequence is that the caller owns draw order: translucent surfaces
    # have to arrive after the opaque ones and back to front. `prepare` sorts.
    var blended = a.blend == BLEND and mode != SHADE_UV
    # Whether these fragments show data rather than light: a normal or a
    # depth. The lights, the glow and the fog leave them alone, and the
    # target keeps the tone mapping off them.
    var data = a.kind.is_data()
    # Whether the fog reaches these fragments: never in the uv debug view,
    # which shows coordinates rather than light, and never a surface that
    # shows data.
    var fogged = fog.is_on() and mode != SHADE_UV and not data
    # Whether a fragment of this triangle can be thrown away for being too
    # transparent. Such a fragment must claim no depth until it survives,
    # or the hole it cuts hides what is behind it: the *late* depth write a
    # GPU makes for a shader that can discard. The uv debug view shows the
    # nearest surface's coordinates and cuts nothing out, as it samples no
    # texture.
    var tested = a.alpha_test > 0 and mode != SHADE_UV

    var flat = Triangle(Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
    var coverage = _Coverage(flat)
    if coverage.is_degenerate():
        return

    var box = _bounds(flat, target.width, target.height, first_row, last_row)
    # The edge functions are evaluated once, at the box's top-left pixel,
    # and stepped from there: one integer add per edge per pixel, exact.
    var right = _step_right(coverage)
    var down = _step_down(coverage)
    var row = _edges_at(coverage, box.left, box.top)
    # A triangle entirely off-screen leaves an empty box, so these can run
    # zero times.
    for y in range(box.top, box.bottom + 1):
        var edges = row
        for x in range(box.left, box.right + 1):
            var here = edges
            edges = edges + right
            if not _covers(coverage, here):
                continue
            var fragment = _weights_of(coverage, here)
            var wa = fragment.wa
            var wb = fragment.wb
            var wc = fragment.wc
            var z = wa * a.z + wb * b.z + wc * c.z
            if blended or tested:
                # Hidden by what is in front, but hiding nothing behind --
                # a translucent surface never, an alpha-tested one not yet.
                if not target.depth_passes(x, y, z):
                    continue
            elif not target.test_depth(x, y, z):
                continue

            # The denominator of the perspective correction, and the
            # interpolated reciprocal depth in its own right.
            var inv_w = wa * a.inv_w + wb * b.inv_w + wc * c.inv_w
            # Nothing in the renderer produces a zero here: clipping removes
            # everything at or in front of the near plane, and an
            # *orthographic* camera leaves w at one, not zero — so its inv_w
            # is one and the correction divides by one rather than needing
            # this branch. The guard is for hand-built input, where the
            # alternative is silent infinities.
            var share_a = wa
            var share_b = wb
            var share_c = wc
            if inv_w != 0:
                # One reciprocal, three multiplies: the same arithmetic the
                # GPU kernel does, so the two still round alike.
                var rcp = Float32(1) / inv_w
                share_a = wa * a.inv_w * rcp
                share_b = wb * b.inv_w * rcp
                share_c = wc * c.inv_w * rcp

            var base = FloatColor(
                a.color.r * share_a + b.color.r * share_b + c.color.r * share_c,
                a.color.g * share_a + b.color.g * share_b + c.color.g * share_c,
                a.color.b * share_a + b.color.b * share_b + c.color.b * share_c,
                interpolate_alpha(
                    a.color.a, b.color.a, c.color.a, share_b, share_c
                ),
            )
            # An unlit surface shows its own color: neither the lights nor
            # the normal are consulted. A normal material consults the
            # normal alone, since the normal is what it shows.
            var arriving = FloatColor(1.0, 1.0, 1.0, 1.0)
            # The highlight a `PHONG` surface sends toward the camera, added
            # after the texture has had its say over the diffuse color and
            # before the emissive, exactly where three.js sums it.
            var highlight = FloatColor(0.0, 0.0, 0.0, 1.0)
            var facing = Vector3(0, 0, 1)
            if a.kind.is_lit() or a.kind == NORMALS:
                # The normal is interpolated like every other varying and
                # made a unit vector again here. That renormalization is the
                # whole difference between this and shading at the corners:
                # the average of two unit vectors is shorter than either, so
                # a normal interpolated and left alone dims the middle of
                # every triangle.
                facing = Vector3(
                    a.normal.x * share_a
                    + b.normal.x * share_b
                    + c.normal.x * share_c,
                    a.normal.y * share_a
                    + b.normal.y * share_b
                    + c.normal.y * share_c,
                    a.normal.z * share_a
                    + b.normal.z * share_b
                    + c.normal.z * share_c,
                )
                if facing.length() != 0:
                    facing.normalize()
            if a.kind.is_lit():
                # Where this fragment is in the world, for the lights that
                # have a position, and for the direction the camera sees it
                # along.
                var spot = Vector3(
                    a.world.x * share_a
                    + b.world.x * share_b
                    + c.world.x * share_c,
                    a.world.y * share_a
                    + b.world.y * share_b
                    + c.world.y * share_c,
                    a.world.z * share_a
                    + b.world.z * share_b
                    + c.world.z * share_c,
                )
                arriving = lighting.intensity_at(facing, spot)
                if a.kind == PHONG:
                    # Interpolated like the emissive, and summed over the
                    # lights that have a direction; see `specular_at`.
                    var sheen = FloatColor(
                        a.specular.r * share_a
                        + b.specular.r * share_b
                        + c.specular.r * share_c,
                        a.specular.g * share_a
                        + b.specular.g * share_b
                        + c.specular.g * share_c,
                        a.specular.b * share_a
                        + b.specular.b * share_b
                        + c.specular.b * share_c,
                        1.0,
                    )
                    highlight = lighting.specular_at(
                        facing,
                        spot,
                        Vector3(sheen.r, sheen.g, sheen.b),
                        a.shininess,
                    )
            var shaded = FloatColor(
                base.r * arriving.r,
                base.g * arriving.g,
                base.b * arriving.b,
                base.a,
            )
            # Light the surface gives off, interpolated like its color. Added
            # below, after the lights, and multiplied by its own map first
            # when there is one.
            var glow = FloatColor(
                a.emissive.r * share_a
                + b.emissive.r * share_b
                + c.emissive.r * share_c,
                a.emissive.g * share_a
                + b.emissive.g * share_b
                + c.emissive.g * share_c,
                a.emissive.b * share_a
                + b.emissive.b * share_b
                + c.emissive.b * share_c,
                1.0,
            )
            # Each mode by name, as the kernel does, so there is no "else"
            # for an unrecognized one to fall into differently on each side.
            if mode == SHADE_UV or mode == SHADE_TEXTURE:
                var u = a.u * share_a + b.u * share_b + c.u * share_c
                var v = a.v * share_a + b.v * share_b + c.v * share_c
                if mode == SHADE_UV:
                    # Coordinates, not light: written as data, which
                    # bypasses the transfer function and the tone mapping
                    # -- see `data_color`. Opaque, which is why the alpha
                    # is one.
                    target.write(x, y, data_color(u, v, 0.0, 1.0), True)
                    continue
                else:
                    # Modulate rather than replace: the texture says what
                    # color the surface is, the lighting says how much of it
                    # reaches the camera, and a renderer needs both.
                    var texel = FloatColor(1.0, 1.0, 1.0, 1.0)
                    if a.texture != NO_TEXTURE:
                        ref image = textures.get(a.texture)
                        texel = _sample_map(
                            image, u, v, a, b, c, coverage, x, y
                        )
                    shaded = FloatColor(
                        shaded.r * texel.r,
                        shaded.g * texel.g,
                        shaded.b * texel.b,
                        shaded.a * texel.a,
                    )
                    # The alpha map's *green* channel thins the surface,
                    # three.js's `alphamap_fragment`, which reads `.g` and
                    # nothing else. It is data, so the texture is linear
                    # and the byte arrives as it was stored.
                    if a.alpha_map != NO_TEXTURE:
                        ref mask = textures.get(a.alpha_map)
                        var thinning = _sample_map(
                            mask, u, v, a, b, c, coverage, x, y
                        )
                        shaded = FloatColor(
                            shaded.r, shaded.g, shaded.b, shaded.a * thinning.g
                        )
                    # The emissive map multiplies the glow the same way,
                    # alpha aside: light given off has no coverage.
                    if a.emissive_map != NO_TEXTURE:
                        ref glow_image = textures.get(a.emissive_map)
                        var glowing = _sample_map(
                            glow_image, u, v, a, b, c, coverage, x, y
                        )
                        glow = FloatColor(
                            glow.r * glowing.r,
                            glow.g * glowing.g,
                            glow.b * glowing.b,
                            1.0,
                        )
            # Thrown away for being too transparent, three.js's
            # `alphatest_fragment`: no color, and no depth either, so what
            # is behind this hole is drawn instead. Asked once the maps have
            # had their say over alpha and before anything is written.
            if tested and shaded.a < a.alpha_test:
                continue
            if data:
                # Data rather than light, as bytes the display shows as they
                # are: the normal, three.js's `packNormalToRGB`, or the
                # depth, near white and far black. Whatever the color and
                # the texture said about red, green and blue is discarded;
                # what they said about alpha is kept, so a cut-out map cuts
                # a depth out as three.js's does. Neither the glow nor the
                # fog reaches these -- see `data_color`.
                if a.kind == NORMALS:
                    var packed = packed_normal(facing)
                    shaded = data_color(packed.x, packed.y, packed.z, shaded.a)
                else:
                    var seen = packed_depth(z)
                    shaded = data_color(seen, seen, seen, shaded.a)
            else:
                # The highlight and then the glow, both added after the
                # lights and neither touched by the texture: three.js sums
                # `directSpecular` and `totalEmissiveRadiance` into the
                # outgoing light the same way. Alpha is coverage rather
                # than light, so it stays what the material said.
                shaded = FloatColor(
                    shaded.r + highlight.r + glow.r,
                    shaded.g + highlight.g + glow.g,
                    shaded.b + highlight.b + glow.b,
                    shaded.a,
                )
            # Veiled by the fog last, after the lights and the glow, as
            # three.js mixes its finished color -- but in linear light,
            # before anything is encoded. The depth is a varying of its
            # own, interpolated like the color: a small number, where a
            # world coordinate a million meters out rounds it away. The
            # kernel interpolates the same lane and mixes with the same
            # function.
            if fogged:
                var depth = (
                    a.view_depth * share_a
                    + b.view_depth * share_b
                    + c.view_depth * share_c
                )
                shaded = fog_mix(shaded, fog.color, fog.factor_at(depth))
            if blended:
                target.blend(x, y, shaded)
            else:
                # The depth an alpha-tested fragment did not claim before it
                # was shaded, claimed now that it has survived.
                if tested:
                    target.claim_depth(x, y, z)
                target.write(x, y, shaded, data)
        row = row + down


async def _band(
    corners: Pointer[RasterVertex, ImmutAnyOrigin],
    triangles: Int,
    target: MutPointer[RenderTarget, MutAnyOrigin],
    mode: ShadeMode,
    textures: Pointer[TextureStore, ImmutAnyOrigin],
    lighting: Pointer[Lighting, ImmutAnyOrigin],
    errors: MutPointer[String, MutAnyOrigin],
    band: Int,
    first_row: Int,
    last_row: Int,
    fog: FogView,
):
    """Rasterize every triangle into one horizontal band of the target.

    One of these runs per worker, as a task on the standard library's thread
    pool. It takes pointers rather than references because a coroutine
    outlives the call that made it and must not borrow from it; `rasterize_all`
    keeps everything alive until `TaskGroup.wait` returns.

    A band owns its rows outright, so the threads never touch the same
    pixel and the depth test needs no atomics -- the same argument the GPU
    kernel makes with one thread per pixel. Draw order within a band is
    submission order, exactly as on one thread, which is what keeps blending
    correct: the sort `Renderer.prepare` did still holds row by row.

    A task cannot raise, so an error is written into this band's slot and
    raised by `rasterize_all` once every band has finished.
    """
    try:
        for triangle in range(triangles):
            var a = corners[unsafe_offset=triangle * 3]
            var b = corners[unsafe_offset=triangle * 3 + 1]
            var c = corners[unsafe_offset=triangle * 3 + 2]
            # Most triangles miss most bands. Saying so here, from three
            # corners, is cheaper than letting `rasterize_shaded` snap the
            # triangle, bias its edges and clamp an empty box before finding
            # out.
            var top = min(a.y, min(b.y, c.y))
            var bottom = max(a.y, max(b.y, c.y))
            if Int(floor(top)) > last_row or Int(ceil(bottom)) < first_row:
                continue
            rasterize_shaded(
                a,
                b,
                c,
                target[],
                mode,
                textures[],
                lighting[],
                first_row,
                last_row,
                fog,
            )
    except e:
        errors[unsafe_offset=band] = String(e)


def rasterize_all(
    corners: List[RasterVertex],
    mut target: RenderTarget,
    mode: ShadeMode = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    lighting: Lighting = Lighting.uniform(),
    workers: Int = 1,
    fog: FogView = FogView.none(),
) raises:
    """Draw every triangle in `corners` into `target`, on `workers` threads.

    `rasterize_shaded` for a whole list. With one worker it is exactly the
    loop a caller would write. With more, the image is cut into that many
    horizontal bands, each drawn by its own task on the standard library's
    thread pool, and every triangle is offered to every band. The result is
    byte for byte what one thread produces -- a band owns its rows and draws
    in the same order -- so only the wall clock changes. More bands than
    rows collapse to one band per row.

    Threads rather than SIMD, first, because a band is the same code with a
    row range and needs no new arithmetic, and because the scene benchmark
    showed rasterization and the sRGB resolve were the frame; `prepare`,
    still single-threaded, is now the largest single piece.

    Args:
        corners: Raster vertices, three per triangle.
        target: The linear render target to draw into.
        mode: What a fragment's color comes from; see `rasterize_shaded`.
        textures: Where `SHADE_TEXTURE` looks the triangles' maps up.
        lighting: The scene's lights, resolved to world space.
        workers: How many threads to draw with, at least one.
        fog: The scene's fog, seen through the camera; see
            `rasterize_shaded`.

    Raises:
        Error: If the corner count is not a multiple of three, `workers` is
            less than one, the mode is none of the three, the fog view is
            refused by `FogView.validate`, any triangle's
            metadata is refused by `check_triangle_state`, or any triangle is
            refused by `rasterize_shaded` -- on a worker that error is
            carried back and raised here.
    """
    if len(corners) % 3 != 0:
        raise Error("Rasterizing needs whole triangles")
    if workers < 1:
        raise Error("Rasterizing needs at least one worker")
    if not mode.is_valid():
        raise Error("A shading mode that is none of the three")
    # Refused here, before any band starts, for the reason the triangle
    # state is: whether or not a triangle is visible, and however many
    # workers there are.
    fog.validate()
    var triangles = len(corners) // 3
    # Every triangle's metadata is checked here, before any band starts, so
    # malformed input is refused whether or not the triangle is visible and
    # however many workers there are. A band skips triangles outside its
    # rows before `rasterize_shaded` can look at them, and a single worker
    # does not, so without this the same bad input raised on one thread and
    # passed on four. A texture the store lacks is still found only when a
    # fragment samples it -- `Renderer.prepare` refuses one long before here
    # -- and that answer is the same on any number of workers, because some
    # band covers whatever is visible.
    for triangle in range(triangles):
        check_triangle_state(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
        )
    var bands = min(workers, target.height)
    if bands == 1:
        for triangle in range(triangles):
            rasterize_shaded(
                corners[triangle * 3],
                corners[triangle * 3 + 1],
                corners[triangle * 3 + 2],
                target,
                mode,
                textures,
                lighting,
                fog=fog,
            )
        return

    # Every pointer below is to an argument or a local that outlives `wait`,
    # which is what makes handing it to a coroutine sound.
    var errors = List[String](length=bands, fill=String(""))
    var group = TaskGroup()
    # At least two bands past the early return above, so neither loop can
    # run zero times.
    for band in range(bands):  # pragma: no branch
        group.create_task(
            _band(
                corners.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                triangles,
                Pointer(to=target).unsafe_origin_cast[MutAnyOrigin](),
                mode,
                Pointer(to=textures).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=lighting).unsafe_origin_cast[ImmutAnyOrigin](),
                errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                band,
                band * target.height // bands,
                (band + 1) * target.height // bands - 1,
                fog,
            )
        )
    group.wait()
    for band in range(bands):  # pragma: no branch
        if errors[band] != "":
            raise Error(errors[band])
