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
    DEFAULT_IOR,
    DEPTH,
    MAX_IOR,
    MIN_IOR,
    DISTANCE,
    LAMBERT,
    MAX_IOR,
    MIN_IOR,
    MULTIPLY_OPERATION,
    NORMALS,
    MATCAP,
    OPAQUE,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    TOON,
    Blending,
    Combine,
    MaterialKind,
    DEFAULT_REFRACTION_RATIO,
    NormalMapType,
    OBJECT_SPACE_NORMAL_MAP,
    TANGENT_SPACE_NORMAL_MAP,
    combine_light,
)
from render.cube_texture import (
    Basis3,
    reflected,
    refracted,
    rough_reflection,
)
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    CubeTextureId,
    CubeTextureStore,
)
from render.target import RenderTarget
from render.fragment_flags import alpha_covers, dither, hashed_threshold
from render.raster_state import (
    REVERSED_DEPTH,
    RasterState,
    fragment_depth,
    shades,
)
from render.packing import (
    BASIC_DEPTH_PACKING,
    DepthPacking,
    check_distance_range,
    packed_depth_fragment,
    packed_distance_fragment,
)
from render.srgb import LINEAR
from render.texture import (
    COVERAGE,
    FLOAT_TYPE,
    IGNORED,
    UV_CHANNEL_1,
    Texture,
    UvPlacement,
    anisotropic_footprint,
    mix_straight,
)
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from materials.nodes import (
    AO_NODE,
    AT_RIGHT,
    AT_UP,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    DEPTH_NODE,
    EMISSIVE_NODE,
    MASK_NODE,
    NORMAL_NODE,
    NO_NODES,
    OPACITY_NODE,
    OUTPUT_NODE,
    NodeContext,
    NodeInputs,
    NodeProgram,
    NodeProgramId,
    NodeProgramStore,
    NodeSource,
    here_inputs,
    node_depth,
    offset_normal,
    has_output,
    perspective_shares,
    run_nodes,
)
from render.transmission import (
    TransmissionTarget,
    host_refraction,
    transmission_alpha,
)
from lights.lighting import (
    PERSPECTIVE_VIEW,
    RECIPROCAL_PI,
    Lighting,
    Reflected,
    ambient_occlusion,
    floored_roughness,
    geometry_roughness,
    occluded_light,
    physical_outgoing,
    physical_surface,
    toward_eye_at,
    view_direction,
)
from lights.physical_layers import (
    NO_ANISOTROPY_TEXEL,
    bent_normal,
    clearcoat_of,
    iridescence_thickness,
    layers_of,
    sheen_roughness_of,
    specular_reflectance,
)
from core.fog import FogView, fog_mix
from render.linerule import (
    dash_covers,
    first_other_at,
    major_at,
    major_is_x,
    share_at,
    span_of,
)
from render.fillrule import SUBPIXEL, bias, edge_at, sample, snap
from render.pointrule import (
    coord as point_coord,
    covers as point_covers,
    first_covered,
    last_covered,
    mip_level_of,
)
from std.math import ceil, floor, inf, isfinite, log2, max, min, sqrt

# `TaskGroup` moved behind an underscore in Mojo 1.1: `std.runtime` keeps
# only `parallelism_level` and `initialize_runtime` in public view, and
# nothing public in `std` runs work on the thread pool -- `std.algorithm.map`
# is sequential. So the private module is the only way to keep the bands
# parallel, and this import is the one place the project reaches past a
# leading underscore. It pins the toolchain to 1.1: 1.0 has no `_asyncrt`
# and 1.1 has no `asyncrt`, so one source cannot serve both.
from std.runtime._asyncrt import TaskGroup


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


# What a thin film is, in nanometers, when a material names no range:
# three.js's `iridescenceThicknessRange` of `[ 100, 400 ]`.
comptime DEFAULT_THICKNESS_MINIMUM = Float32(100)
comptime DEFAULT_THICKNESS_MAXIMUM = Float32(400)
# The film's index of refraction when a material names none: three.js's
# `iridescenceIOR` of 1.3.
comptime DEFAULT_IRIDESCENCE_IOR = Float32(1.3)
# The longest anisotropy vector a triangle can carry: a strength of one,
# with room for the rounding of its cosine and sine.
comptime MAX_ANISOTROPY_LENGTH = Float32(1.0001)


struct LayerFactors(ImplicitlyCopyable):
    """What a `PHYSICAL` triangle's sheen, iridescence and anisotropy are,
    and its specular and clearcoat maps, as the material says them: its
    numbers and its maps, per triangle.

    One value on every corner, read from the first and checked to agree,
    as the rest of a triangle's metadata is. `LayerFactors()` has no sheen,
    no film, no stretch and no map, which is what every other kind
    carries. The fragment's own layers are worked out from these by
    `lights.physical_layers.layers_of`.
    """

    # The sheen color, linear, already times the sheen, three.js's
    # `sheenColor` uniform, and the sheen roughness as authored.
    var sheen_color: Vector3
    var sheen_roughness: Float32
    # How much film there is, its index of refraction, and the range its
    # thickness map reads between, in nanometers.
    var iridescence: Float32
    var iridescence_ior: Float32
    var thickness_minimum: Float32
    var thickness_maximum: Float32
    # The stretch's strength along its rotation, as a vector: three.js's
    # `anisotropyVector`. The renderer negates it when it turns a corner
    # around, as it negates the normal scale.
    var anisotropy: Vector2
    # The maps: the sheen color's (its color), the sheen roughness's (its
    # alpha), the film's (its red), the thickness's (its green) and the
    # stretch's (its red and green a direction, its blue a strength).
    var sheen_color_map: TextureId
    var sheen_roughness_map: TextureId
    var iridescence_map: TextureId
    var thickness_map: TextureId
    var anisotropy_map: TextureId
    # The specular color, linear, three.js's `specularColor` uniform. Read
    # only with a specular map, when the reflectance head on is worked out
    # again per fragment; without one it rides in the corner's `specular`.
    var specular_color: Vector3
    # What the coat's normal map's x and y are scaled by, three.js's
    # `clearcoatNormalScale`. The renderer negates it when it turns a
    # corner around, as it negates the normal scale.
    var clearcoat_normal_scale: Vector2
    # The specular and coat maps: the specular intensity's (its alpha),
    # the specular color's (its color), the coat's (its red), the coat
    # roughness's (its green) and the coat's normals.
    var specular_intensity_map: TextureId
    var specular_color_map: TextureId
    var clearcoat_map: TextureId
    var clearcoat_roughness_map: TextureId
    var clearcoat_normal_map: TextureId

    def __init__(out self):
        """Describe a triangle with no sheen, no film, no stretch and no
        specular or clearcoat map, at three.js's defaults for each."""
        self.sheen_color = Vector3(0, 0, 0)
        self.sheen_roughness = 1
        self.iridescence = 0
        self.iridescence_ior = DEFAULT_IRIDESCENCE_IOR
        self.thickness_minimum = DEFAULT_THICKNESS_MINIMUM
        self.thickness_maximum = DEFAULT_THICKNESS_MAXIMUM
        self.anisotropy = Vector2(0, 0)
        self.sheen_color_map = NO_TEXTURE
        self.sheen_roughness_map = NO_TEXTURE
        self.iridescence_map = NO_TEXTURE
        self.thickness_map = NO_TEXTURE
        self.anisotropy_map = NO_TEXTURE
        self.specular_color = Vector3(1, 1, 1)
        self.clearcoat_normal_scale = Vector2(1, 1)
        self.specular_intensity_map = NO_TEXTURE
        self.specular_color_map = NO_TEXTURE
        self.clearcoat_map = NO_TEXTURE
        self.clearcoat_roughness_map = NO_TEXTURE
        self.clearcoat_normal_map = NO_TEXTURE

    def agrees(self, other: Self) -> Bool:
        """Return True if `other` holds the same numbers and maps.

        Args:
            other: The factors on another corner.

        Returns:
            Whether every field is equal.
        """
        return (
            self.sheen_color.x == other.sheen_color.x
            and self.sheen_color.y == other.sheen_color.y
            and self.sheen_color.z == other.sheen_color.z
            and self.sheen_roughness == other.sheen_roughness
            and self.iridescence == other.iridescence
            and self.iridescence_ior == other.iridescence_ior
            and self.thickness_minimum == other.thickness_minimum
            and self.thickness_maximum == other.thickness_maximum
            and self.anisotropy.x == other.anisotropy.x
            and self.anisotropy.y == other.anisotropy.y
            and self.sheen_color_map == other.sheen_color_map
            and self.sheen_roughness_map == other.sheen_roughness_map
            and self.iridescence_map == other.iridescence_map
            and self.thickness_map == other.thickness_map
            and self.anisotropy_map == other.anisotropy_map
            and self.specular_color.x == other.specular_color.x
            and self.specular_color.y == other.specular_color.y
            and self.specular_color.z == other.specular_color.z
            and self.clearcoat_normal_scale.x == other.clearcoat_normal_scale.x
            and self.clearcoat_normal_scale.y == other.clearcoat_normal_scale.y
            and self.specular_intensity_map == other.specular_intensity_map
            and self.specular_color_map == other.specular_color_map
            and self.clearcoat_map == other.clearcoat_map
            and self.clearcoat_roughness_map == other.clearcoat_roughness_map
            and self.clearcoat_normal_map == other.clearcoat_normal_map
        )

    def is_layered(self) -> Bool:
        """Return True if any number or map differs from `LayerFactors()`.

        Returns:
            Whether the triangle has a sheen, a film, a stretch, a
            specular color or a specular or clearcoat map to say.
        """
        return not self.agrees(LayerFactors())

    def is_anisotropic(self) -> Bool:
        """Return True if the lobe is stretched at all: three.js's
        `USE_ANISOTROPY`, which a strength above zero turns on.

        Returns:
            Whether the anisotropy vector is not zero.
        """
        return self.anisotropy.x != 0 or self.anisotropy.y != 0

    def is_specular_mapped(self) -> Bool:
        """Return True if a specular map changes the reflectance head on,
        so a fragment works it out again from `specular_color`.

        Returns:
            Whether the triangle names a specular intensity or color map.
        """
        return (
            self.specular_intensity_map != NO_TEXTURE
            or self.specular_color_map != NO_TEXTURE
        )

    def check(self) raises:
        """Refuse numbers no material can hold.

        Raises:
            Error: If any color channel of the sheen or the specular color
                is negative or not finite, the sheen roughness or the
                iridescence is outside zero to one, the film's index is
                outside one to 2.333, a thickness is negative or not
                finite, the anisotropy is not finite or longer than one,
                the clearcoat normal scale is not finite, or a map id is a
                negative other than `NO_TEXTURE`.
        """
        var color = self.sheen_color
        var darkest = min(min(color.x, color.y), color.z)
        if not isfinite(color.dot(color)) or darkest < 0:
            raise Error("A triangle's sheen color cannot be negative")
        if not _is_unit_fraction(self.sheen_roughness):
            raise Error(
                "A triangle's sheen roughness must be between zero and one"
            )
        if not _is_unit_fraction(self.iridescence):
            raise Error("A triangle's iridescence must be between zero and one")
        var ior = self.iridescence_ior
        if not isfinite(ior) or ior < MIN_IOR or ior > MAX_IOR:
            raise Error(
                "A triangle's iridescence index of refraction must be"
                " between one and 2.333"
            )
        var thinnest = min(self.thickness_minimum, self.thickness_maximum)
        var span = self.thickness_minimum + self.thickness_maximum
        if not isfinite(span) or thinnest < 0:
            raise Error("A triangle's film thickness cannot be negative")
        var reach = self.anisotropy.length()
        if not isfinite(reach) or reach > MAX_ANISOTROPY_LENGTH:
            raise Error("A triangle's anisotropy must be between zero and one")
        var lowest = min(
            min(self.sheen_color_map.value, self.sheen_roughness_map.value),
            min(
                min(self.iridescence_map.value, self.thickness_map.value),
                self.anisotropy_map.value,
            ),
        )
        if lowest < NO_TEXTURE.value:
            raise Error("A triangle names a layer map id that nothing can hold")
        var tint = self.specular_color
        var faintest = min(min(tint.x, tint.y), tint.z)
        if not isfinite(tint.dot(tint)) or faintest < 0:
            raise Error("A triangle's specular color cannot be negative")
        var scale = self.clearcoat_normal_scale
        if not isfinite(scale.x) or not isfinite(scale.y):
            raise Error("A triangle's clearcoat normal scale must be finite")
        var coat_lowest = min(
            min(
                self.specular_intensity_map.value,
                self.specular_color_map.value,
            ),
            min(
                min(
                    self.clearcoat_map.value, self.clearcoat_roughness_map.value
                ),
                self.clearcoat_normal_map.value,
            ),
        )
        if coat_lowest < NO_TEXTURE.value:
            raise Error(
                "A triangle names a specular or clearcoat map id that nothing"
                " can hold"
            )


@fieldwise_init
struct TextureFrames(Equatable, ImplicitlyCopyable):
    """The frames a triangle's environment and normal map are read in: how
    the environment is turned, how far a refraction bends the view, which
    frame the normal map holds, and the mesh's normal matrix for an
    object-space one.

    One struct on `RasterVertex`, per-triangle and read from the first
    corner as `layers` is, so both rasterizers check one agreement.
    """

    # The matrix that turns a lookup direction, three.js's `envMapRotation`
    # uniform; see `render.cube_texture.env_rotation`.
    var env_rotation: Basis3
    # three.js's `refractionRatio`, read under a refraction mapping.
    var refraction_ratio: Float32
    # three.js's `normalMapType`.
    var normal_map_type: NormalMapType
    # The mesh's normal matrix into the world, negated when the renderer
    # turns a corner around: what an object-space normal map's texel is
    # turned by, three.js's `normalMatrix * faceDirection`.
    var object_normal: Basis3

    def __init__(out self):
        """Create the frames three.js starts a material with: no turn, a
        ratio of 0.98, a tangent-space normal map, and the identity."""
        self.env_rotation = Basis3()
        self.refraction_ratio = DEFAULT_REFRACTION_RATIO
        self.normal_map_type = TANGENT_SPACE_NORMAL_MAP
        self.object_normal = Basis3()

    def validate(self) raises:
        """Refuse frames no shader can read.

        Raises:
            Error: If the normal map type is none of the two, or the
                refraction ratio is negative or not finite.
        """
        if not self.normal_map_type.is_valid():
            raise Error(
                "A triangle's normal map type must be TANGENT_SPACE_NORMAL_MAP"
                " or OBJECT_SPACE_NORMAL_MAP"
            )
        var ratio = self.refraction_ratio
        if not isfinite(ratio) or ratio < 0:
            raise Error("A triangle's refraction ratio cannot be negative")


def env_direction(
    toward_eye: Vector3, normal: Vector3, refracts: Bool, frames: TextureFrames
) -> Vector3:
    """Return the direction a basic, lambert or phong surface reads its
    environment in: three.js's `envmap_fragment`.

    The view turned back through the normal, `reflected`, or under a
    refraction mapping the view bent through the surface by the
    refraction ratio, `refracted`; then turned by the env map's rotation.
    Shared by both rasterizers.

    Args:
        toward_eye: Unit direction from the surface toward the camera.
        normal: The surface's unit normal.
        refracts: Whether the env map has a refraction mapping.
        frames: The triangle's frames, for the ratio and the rotation.

    Returns:
        The direction to read the environment in.
    """
    var looked = reflected(toward_eye, normal)
    if refracts:
        looked = refracted(toward_eye, normal, frames.refraction_ratio)
    return frames.env_rotation.turn(looked)


def object_space_normal(
    normal: Vector3, texel: FloatColor, frame: Basis3
) -> Vector3:
    """Return the normal an object-space normal map's texel gives: the
    `USE_NORMALMAP_OBJECTSPACE` branch of three.js's `normal_fragment_maps`.

    The texel's bytes are unpacked from zero to one into minus one to one
    and turned into the world by the mesh's normal matrix, which the
    renderer negates for a corner it turns around, as three.js multiplies
    by `faceDirection`. The geometry's normal is replaced, not perturbed,
    and `normalScale` is not read, as in three.js. A texel that unpacks to
    nothing leaves the geometry's normal alone. Shared by both rasterizers.

    Args:
        normal: The interpolated unit normal.
        texel: The map's texel, linear: red is x, green y, blue z.
        frame: The mesh's normal matrix into the world.

    Returns:
        The unit normal.
    """
    var turned = frame.turn(
        Vector3(texel.r * 2 - 1, texel.g * 2 - 1, texel.b * 2 - 1)
    )
    if turned.length() == 0:
        return normal
    turned.normalize()
    return turned


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
    # Raw: the geometry's `uv`, not moved by any map. Each map places them
    # at the fragment by its own `UvPlacement`.
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
    # Which image a `MATCAP` surface is looked up in, or `NO_TEXTURE`
    # for three.js's gray gradient. Per-triangle metadata like `texture`,
    # and sampled at a coordinate the normal decides rather than at the
    # surface's own, so its transform never applies.
    var matcap: TextureId
    # Which texture's top row is the ramp a `TOON` surface steps through,
    # or `NO_TEXTURE` for three.js's fallback: three.js's `gradientMap`.
    # Per-triangle metadata like `texture`, and read at no surface
    # coordinate, so its own transform never applies.
    var gradient_map: TextureId
    # How far in front of the camera this corner is, in meters: three.js's
    # `vFogDepth`, minus the camera-space z, taken from the clipped
    # position as it is projected. Interpolated with perspective correction
    # like the color, so a fragment reads its fog off a small number
    # rather than recovering it from a large world coordinate, which
    # rounds the depth away far from the origin. Read only by the fog.
    var view_depth: Float32
    # How far along its line this corner is, three.js's `vLineDistance`,
    # already scaled by the material. A varying, interpolated with
    # perspective correction like the color, and read by a dashed line
    # alone; a triangle's corners carry zero.
    var line_distance: Float32
    # How long each dash is and how long the gap after it, in the units
    # the distance is measured in: three.js's `dashSize` and `gapSize`.
    # Per-segment metadata like the blend policy, read from the first end
    # and checked to agree. A gap of zero is a solid line.
    var dash_size: Float32
    var gap_size: Float32
    # How many pixels across a point is, on the image, with any
    # attenuation already applied: three.js's `gl_PointSize`. Read by a
    # point alone, which is one corner rather than three or two; a
    # triangle's corners and a segment's ends carry zero.
    var point_size: Float32
    # Which cube texture this surface reflects, or `NO_CUBE_TEXTURE` for
    # none: three.js's `envMap`, already resolved from `SCENE_ENVIRONMENT`
    # by `Renderer.prepare`. Per-triangle metadata like `texture`, read
    # from the first corner and checked to agree. Sampled by the camera's
    # view turned back through the normal, so no surface coordinate and
    # no transform applies to it.
    var env_map: CubeTextureId
    # How much of the reflection joins the surface's light, three.js's
    # `reflectivity`, and how it joins, three.js's `combine`. Per-triangle
    # like the shininess and the blend policy, read from the first corner.
    var reflectivity: Float32
    var combine: Combine
    # How rough a physical surface is and how much of a metal, three.js's
    # `roughness` and `metalness`, and what its environment is multiplied
    # by, three.js's `envMapIntensity`. Per-triangle like the shininess,
    # read from the first corner; only a `STANDARD` or `PHYSICAL` triangle
    # reads them. The two maps multiply them per texel: green for the
    # roughness, blue for the metalness, as three.js reads them.
    var roughness: Float32
    var metalness: Float32
    var env_map_intensity: Float32
    var roughness_map: TextureId
    var metalness_map: TextureId
    # What a `PHYSICAL` surface's reflectance is scaled by at a grazing
    # angle, three.js's `specularIntensity`; its reflectance head on rides
    # in `specular`, as a `PHONG` triangle's does. How much clear coat
    # lies over it and how rough that coat is. Per-triangle, read from the
    # first corner.
    var specular_intensity: Float32
    var clearcoat: Float32
    var clearcoat_roughness: Float32
    # A texture of tangent-space normals and what its x and y are scaled
    # by, or a texture of heights and what they are scaled by: three.js's
    # `normalMap`, `normalScale`, `bumpMap` and `bumpScale`. Per-triangle.
    # The renderer negates both scales when it turns a corner around, so
    # a back face is perturbed the way three.js's `faceDirection` perturbs
    # it; see `mapped_normal`.
    var normal_map: TextureId
    var normal_scale: Vector2
    var bump_map: TextureId
    var bump_scale: Float32
    # Whether the lights' shadows fall on this surface, three.js's
    # `receiveShadow`. Per-triangle, read from the first corner. On by
    # default here, where a mesh's is off: a hand-built corner asks for
    # every shadow the lighting holds, and the renderer says otherwise.
    var receives_shadow: Bool
    # The depth, color and stencil state, three.js's `depthTest`,
    # `colorWrite`, `stencilFunc` and the rest; see `render.raster_state`.
    # Per-primitive metadata like the blend policy: read from the first
    # corner, checked to agree. Any polygon offset is already in `z`.
    var state: RasterState
    # The second texture coordinates, raw: the geometry's `uv1`, or its
    # `uv` when it has none. A map whose texture's `channel` is
    # `UV_CHANNEL_1` is sampled here, placed by its own transform. A
    # varying, interpolated like `u` and `v`.
    var u1: Float32
    var v1: Float32
    # A texture whose red channel dims the indirect light and how strongly,
    # three.js's `aoMap` and `aoMapIntensity`, and a texture of baked light
    # and what it is scaled by, three.js's `lightMap` and
    # `lightMapIntensity`. Per-triangle, read from the first corner.
    var ao_map: TextureId
    var ao_map_intensity: Float32
    var light_map: TextureId
    var light_map_intensity: Float32
    # Which texture's red channel scales the highlight and the reflection,
    # or `NO_TEXTURE`: three.js's `specularMap`. Per-triangle like
    # `texture`, and read by a `BASIC`, `LAMBERT` or `PHONG` triangle only.
    var specular_map: TextureId
    # How much of a `PHYSICAL` surface's diffuse light is the opaque scene
    # seen through it, three.js's `transmission`, and the texture whose red
    # multiplies it. How deep the volume is along each world axis: the
    # material's thickness times the length of each axis of the draw's
    # world matrix, three.js's `thickness * modelScale`, and the texture
    # whose green multiplies it. The color white light becomes inside,
    # linear, and how far it travels to become it, infinite for never. How
    # far the channels bend apart, and the index they bend at. All
    # per-triangle, read from the first corner. See `render.transmission`.
    var transmission: Float32
    var transmission_map: TextureId
    var thickness: Vector3
    var thickness_map: TextureId
    var attenuation_color: FloatColor
    var attenuation_distance: Float32
    var dispersion: Float32
    var ior: Float32
    # Whether the scene's fog veils this primitive, three.js's `fog`.
    # Per-primitive metadata like the blend policy: read from the first
    # corner, checked to agree. A data triangle is never fogged, whatever
    # this says.
    var fog: Bool
    # How a `DEPTH` triangle writes its depth, three.js's `depthPacking`.
    # Per-triangle metadata like the kind; see `render.packing`.
    var depth_packing: DepthPacking
    # Where a `DISTANCE` triangle measures from, in world space, and the
    # distances, in meters, that map to zero and to one: three.js's
    # `referencePosition`, `nearDistance` and `farDistance`. Per-triangle,
    # read from the first corner; no other kind reads them.
    var reference: Vector3
    var near_distance: Float32
    var far_distance: Float32
    # A `PHYSICAL` triangle's sheen, iridescence and anisotropy, and their
    # maps. Per-triangle, read from the first corner.
    var layers: LayerFactors
    # Which compiled node graph replaces parts of this triangle's shading,
    # or `NO_NODES`: a node material's program, in the store the
    # rasterizer is handed. Per-triangle like `texture`, read from the
    # first corner. See `materials.nodes`.
    var nodes: NodeProgramId
    # The frames the environment and the normal map are read in. Set after
    # construction, by `Renderer.prepare`; the defaults are three.js's.
    var frames: TextureFrames

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
        gradient_map: TextureId = NO_TEXTURE,
        matcap: TextureId = NO_TEXTURE,
        line_distance: Float32 = 0,
        dash_size: Float32 = 0,
        gap_size: Float32 = 0,
        point_size: Float32 = 0,
        env_map: CubeTextureId = NO_CUBE_TEXTURE,
        reflectivity: Float32 = 1,
        combine: Combine = MULTIPLY_OPERATION,
        roughness: Float32 = 1,
        metalness: Float32 = 0,
        env_map_intensity: Float32 = 1,
        roughness_map: TextureId = NO_TEXTURE,
        metalness_map: TextureId = NO_TEXTURE,
        specular_intensity: Float32 = 1,
        clearcoat: Float32 = 0,
        clearcoat_roughness: Float32 = 0,
        normal_map: TextureId = NO_TEXTURE,
        normal_scale: Vector2 = Vector2(1, 1),
        bump_map: TextureId = NO_TEXTURE,
        bump_scale: Float32 = 1,
        receives_shadow: Bool = True,
        state: RasterState = RasterState(),
        u1: Float32 = 0,
        v1: Float32 = 0,
        ao_map: TextureId = NO_TEXTURE,
        ao_map_intensity: Float32 = 1,
        light_map: TextureId = NO_TEXTURE,
        light_map_intensity: Float32 = 1,
        specular_map: TextureId = NO_TEXTURE,
        transmission: Float32 = 0,
        transmission_map: TextureId = NO_TEXTURE,
        thickness: Vector3 = Vector3(0, 0, 0),
        thickness_map: TextureId = NO_TEXTURE,
        attenuation_color: FloatColor = FloatColor(1.0, 1.0, 1.0),
        attenuation_distance: Float32 = inf[DType.float32](),
        dispersion: Float32 = 0,
        ior: Float32 = DEFAULT_IOR,
        fog: Bool = True,
        depth_packing: DepthPacking = BASIC_DEPTH_PACKING,
        reference: Vector3 = Vector3(0, 0, 0),
        near_distance: Float32 = 1,
        far_distance: Float32 = 1000,
        layers: LayerFactors = LayerFactors(),
        nodes: NodeProgramId = NO_NODES,
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
        to black, which is no highlight. The gradient map defaults to none,
        which is three.js's two-tone fallback for a `TOON` corner and is
        read by no other kind. The matcap defaults to none, which is
        three.js's gray gradient for a `MATCAP` corner. The line distance
        and the dash and gap default to zero, which is a solid line. The
        point size defaults to zero, which no point may carry: a corner
        that says nothing about it is not a point. The env map defaults
        to none, which reflects nothing, at three.js's reflectivity of one
        and its `MultiplyOperation`. The depth, color and stencil state
        defaults to three.js's: the depth tested and written, the color
        written, and no stencil test. The ambient occlusion map and the
        light map default to none, at intensities of one. The volume
        defaults to three.js's: no transmission, no thickness, white light
        that is never dimmed, no dispersion, and an index of 1.5. The fog
        reaches the corner, the depth packing is the basic one, and the
        distance is measured from the origin between one and a thousand
        meters, all three.js's defaults. The sheen, the film and the
        stretch default to none. No node graph replaces any of the shading.
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
        self.gradient_map = gradient_map
        self.matcap = matcap
        self.line_distance = line_distance
        self.dash_size = dash_size
        self.gap_size = gap_size
        self.point_size = point_size
        self.env_map = env_map
        self.reflectivity = reflectivity
        self.combine = combine
        self.roughness = roughness
        self.metalness = metalness
        self.env_map_intensity = env_map_intensity
        self.roughness_map = roughness_map
        self.metalness_map = metalness_map
        self.specular_intensity = specular_intensity
        self.clearcoat = clearcoat
        self.clearcoat_roughness = clearcoat_roughness
        self.normal_map = normal_map
        self.normal_scale = normal_scale
        self.bump_map = bump_map
        self.bump_scale = bump_scale
        self.receives_shadow = receives_shadow
        self.state = state
        self.u1 = u1
        self.v1 = v1
        self.ao_map = ao_map
        self.ao_map_intensity = ao_map_intensity
        self.light_map = light_map
        self.light_map_intensity = light_map_intensity
        self.specular_map = specular_map
        self.transmission = transmission
        self.transmission_map = transmission_map
        self.thickness = thickness
        self.thickness_map = thickness_map
        self.attenuation_color = attenuation_color
        self.attenuation_distance = attenuation_distance
        self.dispersion = dispersion
        self.ior = ior
        self.fog = fog
        self.depth_packing = depth_packing
        self.reference = reference
        self.near_distance = near_distance
        self.far_distance = far_distance
        self.layers = layers
        self.nodes = nodes
        self.frames = TextureFrames()


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
    second: Bool = False,
) -> Vector2:
    """Return the perspective-correct texture coordinates at one sample.

    The same correction `rasterize_shaded` applies to color, factored out
    because mip selection needs it at three sample points rather than one.
    `second` reads `u1` and `v1` rather than `u` and `v`: the coordinates
    a map on `UV_CHANNEL_1` is sampled at.
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
    if second:
        return Vector2(
            a.u1 * share_a + b.u1 * share_b + c.u1 * share_c,
            a.v1 * share_a + b.v1 * share_b + c.v1 * share_c,
        )
    return Vector2(
        a.u * share_a + b.u * share_b + c.u * share_c,
        a.v * share_a + b.v * share_b + c.v * share_c,
    )


def _world_at(
    a: RasterVertex,
    b: RasterVertex,
    c: RasterVertex,
    weights: _Fragment,
) -> Vector3:
    """Return the perspective-correct world position at one sample.

    `_coordinates_at` for the world position, factored out because the
    tangent frame a normal map needs is measured from the positions at the
    pixels one over and one up, as their coordinates are.
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
    return Vector3(
        a.world.x * share_a + b.world.x * share_b + c.world.x * share_c,
        a.world.y * share_a + b.world.y * share_b + c.world.y * share_c,
        a.world.z * share_a + b.world.z * share_b + c.world.z * share_c,
    )


def _cross(left: Vector3, right: Vector3) -> Vector3:
    """Return the cross product of two vectors, as a value."""
    var product = left
    product.cross(right)
    return product


@fieldwise_init
struct TangentFrame(ImplicitlyCopyable):
    """The first two columns of three.js's `getTangentFrame`: where `u`
    grows and where `v` grows, perpendicular to the normal, both scaled by
    one number so that the longer is a unit vector. Zero where the
    coordinates do not change across the pixel.
    """

    var tangent: Vector3
    var bitangent: Vector3


def tangent_frame(
    normal: Vector3,
    along_x: Vector3,
    along_y: Vector3,
    uv_along_x: Vector2,
    uv_along_y: Vector2,
) -> TangentFrame:
    """Return the tangent frame three.js's `getTangentFrame` builds from
    the derivatives of the position and the texture coordinates.

    What `mapped_normal` perturbs the normal along, and what an
    anisotropic surface stretches its lobe along. See `mapped_normal` for
    why the changes are measured one pixel right and one pixel up. Shared
    by both rasterizers.

    Args:
        normal: The interpolated unit normal, before any map.
        along_x: How the world position changes one pixel to the right.
        along_y: How it changes one pixel up.
        uv_along_x: How the texture coordinates change one pixel right.
        uv_along_y: How they change one pixel up.

    Returns:
        The tangent and the bitangent, each zero when the coordinates do
        not change at all.
    """
    var q1_perp = _cross(along_y, normal)
    var q0_perp = _cross(normal, along_x)
    var tangent = Vector3(
        q1_perp.x * uv_along_x.x + q0_perp.x * uv_along_y.x,
        q1_perp.y * uv_along_x.x + q0_perp.y * uv_along_y.x,
        q1_perp.z * uv_along_x.x + q0_perp.z * uv_along_y.x,
    )
    var bitangent = Vector3(
        q1_perp.x * uv_along_x.y + q0_perp.x * uv_along_y.y,
        q1_perp.y * uv_along_x.y + q0_perp.y * uv_along_y.y,
        q1_perp.z * uv_along_x.y + q0_perp.z * uv_along_y.y,
    )
    var extent = max(tangent.dot(tangent), bitangent.dot(bitangent))
    var frame = Float32(0)
    if extent != 0:
        frame = 1 / sqrt(extent)
    return TangentFrame(tangent * frame, bitangent * frame)


def mapped_normal(
    normal: Vector3,
    along_x: Vector3,
    along_y: Vector3,
    uv_along_x: Vector2,
    uv_along_y: Vector2,
    texel: FloatColor,
    scale: Vector2,
) -> Vector3:
    """Return a normal perturbed by a normal map's texel: three.js's
    `getTangentFrame` and the `USE_NORMALMAP_TANGENTSPACE` branch of
    `normal_fragment_maps`.

    The tangent frame is built from how the world position and the
    texture coordinates change across one pixel, as three.js builds it
    without a tangent attribute: the tangent is the direction along which
    `u` grows and the bitangent the one along which `v` grows, both made
    perpendicular to the normal. The two are scaled by one number, so an
    image stretched more one way than the other keeps that stretch. The
    texel's bytes are unpacked from zero to one into minus one to one,
    its x and y are scaled, and the three are summed along the frame.

    The changes are measured one pixel to the right and one pixel *up*,
    because that is the way `dFdy` points on a screen whose rows count
    upward, and the frame's handedness depends on it. A back face is
    handled by the renderer, which negates `scale` when it turns a
    corner around; see `renderers.renderer._turned_around`. Shared by
    both rasterizers.

    **Degenerate coordinates leave the normal alone.** Where the
    coordinates do not change across the pixel at all, there is no
    direction along which `u` grows, so no frame, and the geometric
    normal is returned as it is rather than the map's z alone, which
    would flip it for a texel below the horizon. Coordinates that change
    along one direction only make a frame whose tangent and bitangent
    are parallel, and the map's x and y both tilt along that one axis,
    as three.js's frame does; the result is still a unit normal.

    Args:
        normal: The interpolated unit normal.
        along_x: How the world position changes one pixel to the right.
        along_y: How it changes one pixel up.
        uv_along_x: How the texture coordinates change one pixel right.
        uv_along_y: How they change one pixel up.
        texel: The map's texel, linear: red is x, green y, blue z.
        scale: What the unpacked x and y are multiplied by.

    Returns:
        The perturbed unit normal.
    """
    var frame = tangent_frame(normal, along_x, along_y, uv_along_x, uv_along_y)
    var tangent = frame.tangent
    var bitangent = frame.bitangent
    if max(tangent.dot(tangent), bitangent.dot(bitangent)) == 0:
        return normal
    var map_x = (texel.r * 2 - 1) * scale.x
    var map_y = (texel.g * 2 - 1) * scale.y
    var map_z = texel.b * 2 - 1
    var perturbed = Vector3(
        tangent.x * map_x + bitangent.x * map_y + normal.x * map_z,
        tangent.y * map_x + bitangent.y * map_y + normal.y * map_z,
        tangent.z * map_x + bitangent.z * map_y + normal.z * map_z,
    )
    if perturbed.length() == 0:
        return normal
    perturbed.normalize()
    return perturbed


def bumped_normal(
    normal: Vector3,
    along_x: Vector3,
    along_y: Vector3,
    rise_x: Float32,
    rise_y: Float32,
) -> Vector3:
    """Return a normal perturbed by a bump map's slope: three.js's
    `perturbNormalArb`, Mikkelsen's bump mapping of an unparametrized
    surface.

    The height rises by `rise_x` over one pixel to the right and by
    `rise_y` over one pixel up, and the normal is tilted against the
    slope. The two position changes are normalized first, so the bump
    looks the same however the texture is scaled, as three.js's comment
    says. The determinant's sign takes care of a mirrored frame, and a
    back face is handled by the renderer, which negates the bump scale
    when it turns a corner around, exactly as three.js's `faceDirection`
    flips the sign here. Shared by both rasterizers.

    Args:
        normal: The interpolated unit normal.
        along_x: How the world position changes one pixel to the right.
        along_y: How it changes one pixel up.
        rise_x: How much the scaled height rises one pixel to the right.
        rise_y: How much it rises one pixel up.

    Returns:
        The perturbed unit normal.
    """
    var sigma_x = along_x
    if sigma_x.length() != 0:
        sigma_x.normalize()
    var sigma_y = along_y
    if sigma_y.length() != 0:
        sigma_y.normalize()
    var r1 = _cross(sigma_y, normal)
    var r2 = _cross(normal, sigma_x)
    var determinant = sigma_x.dot(r1)
    var sign = Float32(0)
    if determinant > 0:
        sign = 1
    elif determinant < 0:
        sign = -1
    var size = determinant
    if size < 0:
        size = -size
    var perturbed = Vector3(
        size * normal.x - sign * (rise_x * r1.x + rise_y * r2.x),
        size * normal.y - sign * (rise_x * r1.y + rise_y * r2.y),
        size * normal.z - sign * (rise_x * r1.z + rise_y * r2.z),
    )
    if perturbed.length() == 0:
        return normal
    perturbed.normalize()
    return perturbed


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
    placement: UvPlacement = UvPlacement(),
) -> FloatColor:
    """Return `image` sampled at (u, v) for the pixel at (x, y).

    Straight from the one level when the image has one and allows one
    tap. Otherwise from the level the pixel's footprint chooses, measured
    from the coordinates at the pixels one over and one down -- see
    `mip_level` and `anisotropic_footprint` -- with several taps along
    the footprint's long axis when the texture's anisotropy allows them.
    Shared by every map, so all are filtered alike, and mirrored on the
    device by `render.gpu._sample_slot`. (u, v) is already placed:
    `placement` says which raw pair the footprint is measured on and how
    that pair is moved, as the map's own varying moves in three.js. The
    identity on the first pair, the default, measures the raw `uv`, which
    is what a node graph samples at.
    """
    if image.levels == 1 and image.anisotropy == 1:
        return image.sample(u, v)
    # The center is evaluated by the same function as its neighbors, and
    # not taken from `u` and `v`, so the two differences are exact where
    # the coordinates do not move: `u` is the same sum spelled in the
    # fragment loop, and the compiler is free to fuse its multiplies and
    # adds differently there, which once left a difference of one ulp
    # along an axis the footprint did not cross. That ulp turned the long
    # axis a hair, put a tap a hair past a texel's edge, and read the
    # neighboring texel. The kernel's `_sample_slot` does the same.
    var second = placement.channel == UV_CHANNEL_1
    var here = placement.moved(
        _coordinates_at(a, b, c, _weights(coverage, x, y), second)
    )
    var right = placement.moved(
        _coordinates_at(a, b, c, _weights(coverage, x + 1, y), second)
    )
    var below = placement.moved(
        _coordinates_at(a, b, c, _weights(coverage, x, y + 1), second)
    )
    # The level, and the taps along the long axis when the texture
    # allows them: the same function the kernel asks. With one tap the
    # level is what `mip_level` gives.
    return image._sample_footprint(
        u,
        v,
        anisotropic_footprint(
            Vector2(right.x - here.x, right.y - here.y),
            Vector2(below.x - here.x, below.y - here.y),
            image.width,
            image.height,
            image.anisotropy,
        ),
    )


def _sample_placed(
    image: Texture,
    placement: UvPlacement,
    uv: Vector2,
    uv1: Vector2,
    a: RasterVertex,
    b: RasterVertex,
    c: RasterVertex,
    coverage: _Coverage,
    x: Int,
    y: Int,
) -> FloatColor:
    """Return a map sampled where its own placement puts the fragment:
    three.js's `texture2D(map, vMapUv)`, for any map.

    `uv` and `uv1` are the fragment's two raw pairs. The placement picks
    one and moves it, and `_sample_map` measures the footprint on the
    same pair, moved the same way.
    """
    var at = placement.place(uv, uv1)
    return _sample_map(image, at.x, at.y, a, b, c, coverage, x, y, placement)


def _placed_steps(
    a: RasterVertex,
    b: RasterVertex,
    c: RasterVertex,
    placement: UvPlacement,
    here: Vector2,
    right: _Fragment,
    up: _Fragment,
) -> Tuple[Vector2, Vector2]:
    """Return how one map's placed coordinates change one pixel right and
    one pixel up: three.js's `dFdx` and `dFdy` of that map's varying.

    Args:
        a: First corner.
        b: Second corner.
        c: Third corner.
        placement: The map's placement.
        here: The placed coordinates at the fragment.
        right: The weights one pixel right.
        up: The weights one pixel up.

    Returns:
        The change to the right, then the change up.
    """
    var second = placement.channel == UV_CHANNEL_1
    var to_right = placement.moved(_coordinates_at(a, b, c, right, second))
    var to_up = placement.moved(_coordinates_at(a, b, c, up, second))
    return (
        Vector2(to_right.x - here.x, to_right.y - here.y),
        Vector2(to_up.x - here.x, to_up.y - here.y),
    )


def _normal_at(
    a: RasterVertex, b: RasterVertex, c: RasterVertex, weights: _Fragment
) -> Vector3:
    """Return the perspective-correct unit normal at one sample point,
    before any map, as the fragment loop works it out.

    `_coordinates_at` for the normal, factored out because the geometric
    roughness needs it at the pixels one right and one up. A zero normal
    stays zero, as it does in the loop.
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
    var facing = Vector3(
        a.normal.x * share_a + b.normal.x * share_b + c.normal.x * share_c,
        a.normal.y * share_a + b.normal.y * share_b + c.normal.y * share_c,
        a.normal.z * share_a + b.normal.z * share_b + c.normal.z * share_c,
    )
    if facing.length() != 0:
        facing.normalize()
    return facing


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


def _kept_normal(
    facing: Vector3, kind: MaterialKind, lighting: Lighting, kept: Bool
) -> Vector3:
    """Return the normal a fragment leaves in a normal attachment: its
    shading normal turned into view space, or as it is for a `NORMALS`
    triangle, whose normals the renderer turned already. Zero, and no
    work, when the target keeps no normals. See
    `lights.lighting.view_direction`, which the kernel calls too."""
    if not kept:
        return Vector3(0, 0, 0)
    if kind == NORMALS:
        return facing
    return view_direction(facing, lighting.up, lighting.back)


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


def check_data_state(a: RasterVertex, b: RasterVertex, c: RasterVertex) raises:
    """Refuse a triangle's fog switch, depth packing or distance range
    where its corners disagree or its kind cannot use it.

    Part of `check_triangle_state`, and shared by both backends through it.

    Args:
        a: The triangle's first corner, whose state is the authoritative one.
        b: Its second corner.
        c: Its third corner.

    Raises:
        Error: If the corners disagree on their fog switch or their depth
            packing; if the packing is none of the four, or is not
            `BASIC_DEPTH_PACKING` on a kind that is not `DEPTH`; or, on a
            `DISTANCE` triangle, if the range is refused by
            `render.packing.check_distance_range` or the corners disagree
            on it.
    """
    if b.fog != a.fog or c.fog != a.fog:
        raise Error("A triangle's corners disagree about the fog")
    if b.depth_packing != a.depth_packing or (
        c.depth_packing != a.depth_packing
    ):
        raise Error("A triangle's corners disagree about their depth packing")
    if not a.depth_packing.is_valid():
        raise Error("A triangle's depth packing is none of the four")
    if a.depth_packing != BASIC_DEPTH_PACKING and a.kind != DEPTH:
        raise Error("Only a depth triangle packs its depth")
    if a.kind == DISTANCE:
        # Before the agreement check, because not-a-number is not equal to
        # itself.
        check_distance_range(a.reference, a.near_distance, a.far_distance)
        if not _same_range(a, b) or not _same_range(a, c):
            raise Error(
                "A triangle's corners disagree about their distance range"
            )


def _same_range(a: RasterVertex, b: RasterVertex) -> Bool:
    """Return True if two corners name one reference point and one range."""
    return (
        a.reference.x == b.reference.x
        and a.reference.y == b.reference.y
        and a.reference.z == b.reference.z
        and a.near_distance == b.near_distance
        and a.far_distance == b.far_distance
    )


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
            alpha test, on their gradient map, on their matcap or on
            their shininess; if
            the agreed policy is
            neither `OPAQUE` nor `BLEND`, the agreed kind is none of the
            seven, a gradient map is named on a kind that is not `TOON`,
            a matcap on a kind that is not `MATCAP`,
            the agreed alpha test is outside zero to one or not
            finite, or the agreed shininess is negative or not finite; if
            the agreed kind shows data and the agreed policy is `BLEND`,
            which no pixel could resolve; or if any
            texture id is a negative other than `NO_TEXTURE`, which
            nothing can ever hold. The environment is asked the same
            three questions: the corners must agree on their env map,
            their reflectivity and their combine; the reflectivity must be
            finite and between zero and one and the combine one of the
            three; an env map is refused on a kind that does not reflect;
            and an env map id that is a negative other than
            `NO_CUBE_TEXTURE` is refused, `SCENE_ENVIRONMENT` included,
            which `Renderer.prepare` resolves before a corner is built.
            The corners must agree on their depth, color and stencil
            state, and it must be one `RasterState.check` accepts. The
            corners must agree on their ao map, their light map and their
            two intensities; either id that is a negative other than
            `NO_TEXTURE`, either intensity that is negative or not
            finite, and either map on a kind with no indirect term are
            refused. The corners must agree on their volume; a
            transmission outside zero to one, a thickness or an
            attenuation color that is negative or not finite, an
            attenuation distance that is not above zero, a dispersion that
            is negative or not finite, an index outside one to 2.333,
            either volume map id that is a negative other than
            `NO_TEXTURE`, and any of them but its default on a kind that
            is not `PHYSICAL` are refused. The fog switch, the depth
            packing and the distance range are refused as
            `check_data_state` refuses them. The corners must agree on
            their node program; an id that is a negative other than `NO_NODES`,
            or one on a kind that `MaterialKind.takes_nodes` refuses, is
            refused.
    """
    check_data_state(a, b, c)
    if b.blend != a.blend or c.blend != a.blend:
        raise Error("A triangle's corners disagree about blending")
    if b.texture != a.texture or c.texture != a.texture:
        raise Error("A triangle's corners disagree about their texture")
    if b.emissive_map != a.emissive_map or c.emissive_map != a.emissive_map:
        raise Error("A triangle's corners disagree about their emissive map")
    if b.alpha_map != a.alpha_map or c.alpha_map != a.alpha_map:
        raise Error("A triangle's corners disagree about their alpha map")
    if b.gradient_map != a.gradient_map or c.gradient_map != a.gradient_map:
        raise Error("A triangle's corners disagree about their gradient map")
    if b.matcap != a.matcap or c.matcap != a.matcap:
        raise Error("A triangle's corners disagree about their matcap")
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
        raise Error("A triangle's blend policy is not a blending mode there is")
    if not a.kind.is_valid():
        raise Error("A triangle's material kind is none of the eleven")
    if b.receives_shadow != a.receives_shadow or (
        c.receives_shadow != a.receives_shadow
    ):
        raise Error("A triangle's corners disagree about receiving shadows")
    if b.state != a.state or c.state != a.state:
        raise Error(
            "A triangle's corners disagree about their depth, color or"
            " stencil state"
        )
    a.state.check()
    # A shadow material is transparent wherever no shadow falls, and reads
    # no map: refused here as the material refuses it, so a hand-built
    # triangle cannot smuggle either past.
    if a.kind == SHADOW and a.blend != BLEND:
        raise Error("A shadow triangle blends: it is transparent where lit")
    if a.kind == SHADOW and (
        a.texture != NO_TEXTURE or a.alpha_map != NO_TEXTURE
    ):
        raise Error("A shadow triangle shows its shadow and no map")
    # Only a matcap shader looks a surface up in an image, so one on any
    # other kind is a mistake rather than a value to ignore.
    if a.kind != MATCAP and a.matcap != NO_TEXTURE:
        raise Error(
            "Only a matcap triangle is looked up in an image: no other"
            " shader reads one"
        )
    # Only a toon shader reads a ramp, so a ramp on any other kind is a
    # mistake rather than a value to ignore. Refused here, as the material
    # refuses it, so a hand-built triangle cannot smuggle one past.
    if a.kind != TOON and a.gradient_map != NO_TEXTURE:
        raise Error(
            "Only a toon triangle steps through a ramp: no other shader"
            " reads one"
        )
    # A fragment that shows data cannot be mixed into one that shows light:
    # the pixel would hold part of each and resolve as neither. Refused
    # here so that both backends refuse it, and so that `RenderTarget.blend`
    # can say a mixture is always light. See `render.target`.
    if a.kind.is_data() and a.blend.mixes():
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
    if a.gradient_map != NO_TEXTURE and a.gradient_map.value < 0:
        raise Error("A triangle names a gradient map id that nothing can hold")
    if a.matcap != NO_TEXTURE and a.matcap.value < 0:
        raise Error("A triangle names a matcap id that nothing can hold")
    # The environment, asked as the maps are: agreement first, the number
    # before its agreement check because not-a-number is not equal to
    # itself, then the value and the kind.
    if b.env_map != a.env_map or c.env_map != a.env_map:
        raise Error("A triangle's corners disagree about their env map")
    if (
        not isfinite(a.reflectivity)
        or a.reflectivity < 0
        or (a.reflectivity > 1)
    ):
        raise Error("A triangle's reflectivity must be between zero and one")
    if b.reflectivity != a.reflectivity or c.reflectivity != a.reflectivity:
        raise Error("A triangle's corners disagree about their reflectivity")
    if b.combine != a.combine or c.combine != a.combine:
        raise Error("A triangle's corners disagree about their combine")
    if not a.combine.is_valid():
        raise Error("A triangle's combine is none of the three operations")
    if not a.kind.reflects() and a.env_map != NO_CUBE_TEXTURE:
        raise Error(
            "Only a basic, lambert or phong triangle reflects an"
            " environment: no other shader reads an env map"
        )
    if a.env_map != NO_CUBE_TEXTURE and a.env_map.value < 0:
        raise Error(
            "A triangle names a cube texture id that nothing can hold: the"
            " renderer resolves SCENE_ENVIRONMENT before a corner is built"
        )
    # The frames the environment and the normal map are read in: the
    # numbers first, because not-a-number is not equal to itself.
    a.frames.validate()
    if b.frames != a.frames or c.frames != a.frames:
        raise Error("A triangle's corners disagree about their frames")
    # The physical terms and the normal maps, asked as the rest are: the
    # numbers before their agreement checks, then the maps, then the kind.
    if not _is_unit_fraction(a.roughness):
        raise Error("A triangle's roughness must be between zero and one")
    if not _is_unit_fraction(a.metalness):
        raise Error("A triangle's metalness must be between zero and one")
    if not isfinite(a.env_map_intensity) or a.env_map_intensity < 0:
        raise Error("A triangle's env map intensity cannot be negative")
    if not _is_unit_fraction(a.specular_intensity):
        raise Error(
            "A triangle's specular intensity must be between zero and one"
        )
    if not _is_unit_fraction(a.clearcoat):
        raise Error("A triangle's clearcoat must be between zero and one")
    if not _is_unit_fraction(a.clearcoat_roughness):
        raise Error(
            "A triangle's clearcoat roughness must be between zero and one"
        )
    if not isfinite(a.normal_scale.x) or not isfinite(a.normal_scale.y):
        raise Error("A triangle's normal scale must be finite")
    if not isfinite(a.bump_scale):
        raise Error("A triangle's bump scale must be finite")
    if (
        b.roughness != a.roughness
        or c.roughness != a.roughness
        or b.metalness != a.metalness
        or c.metalness != a.metalness
        or b.env_map_intensity != a.env_map_intensity
        or c.env_map_intensity != a.env_map_intensity
        or b.specular_intensity != a.specular_intensity
        or c.specular_intensity != a.specular_intensity
        or b.clearcoat != a.clearcoat
        or c.clearcoat != a.clearcoat
        or b.clearcoat_roughness != a.clearcoat_roughness
        or c.clearcoat_roughness != a.clearcoat_roughness
    ):
        raise Error("A triangle's corners disagree about their physical terms")
    if (
        b.roughness_map != a.roughness_map
        or c.roughness_map != a.roughness_map
        or b.metalness_map != a.metalness_map
        or c.metalness_map != a.metalness_map
        or b.normal_map != a.normal_map
        or c.normal_map != a.normal_map
        or b.bump_map != a.bump_map
        or c.bump_map != a.bump_map
        or b.specular_map != a.specular_map
        or c.specular_map != a.specular_map
    ):
        raise Error("A triangle's corners disagree about their maps")
    if (
        b.normal_scale.x != a.normal_scale.x
        or c.normal_scale.x != a.normal_scale.x
        or b.normal_scale.y != a.normal_scale.y
        or c.normal_scale.y != a.normal_scale.y
        or b.bump_scale != a.bump_scale
        or c.bump_scale != a.bump_scale
    ):
        raise Error("A triangle's corners disagree about their map scales")
    if a.roughness_map != NO_TEXTURE and a.roughness_map.value < 0:
        raise Error("A triangle names a roughness map id that nothing can hold")
    if a.metalness_map != NO_TEXTURE and a.metalness_map.value < 0:
        raise Error("A triangle names a metalness map id that nothing can hold")
    if a.normal_map != NO_TEXTURE and a.normal_map.value < 0:
        raise Error("A triangle names a normal map id that nothing can hold")
    if a.bump_map != NO_TEXTURE and a.bump_map.value < 0:
        raise Error("A triangle names a bump map id that nothing can hold")
    if a.specular_map != NO_TEXTURE and a.specular_map.value < 0:
        raise Error("A triangle names a specular map id that nothing can hold")
    if not a.kind.is_physical() and (
        a.roughness_map != NO_TEXTURE or a.metalness_map != NO_TEXTURE
    ):
        raise Error(
            "Only a standard or physical triangle reads a roughness or"
            " metalness map: no other shader reads one"
        )
    if a.normal_map != NO_TEXTURE and a.bump_map != NO_TEXTURE:
        raise Error("A triangle names a normal map or a bump map, not both")
    if not a.kind.has_normal() and (
        a.normal_map != NO_TEXTURE or a.bump_map != NO_TEXTURE
    ):
        raise Error(
            "Only a lit or matcap triangle has a normal map: no other"
            " shader reads a normal in the frame a map perturbs"
        )
    # The two baked maps and their intensities, asked as the material asks
    # them: agreed, finite, not negative, and only where an indirect
    # diffuse term is read. The numbers first, since a NaN never agrees.
    if not isfinite(a.ao_map_intensity) or a.ao_map_intensity < 0:
        raise Error("A triangle's ao map intensity cannot be negative")
    if not isfinite(a.light_map_intensity) or a.light_map_intensity < 0:
        raise Error("A triangle's light map intensity cannot be negative")
    if (
        b.ao_map != a.ao_map
        or c.ao_map != a.ao_map
        or b.light_map != a.light_map
        or c.light_map != a.light_map
        or b.ao_map_intensity != a.ao_map_intensity
        or c.ao_map_intensity != a.ao_map_intensity
        or b.light_map_intensity != a.light_map_intensity
        or c.light_map_intensity != a.light_map_intensity
    ):
        raise Error("A triangle's corners disagree about their baked maps")
    if a.ao_map != NO_TEXTURE and a.ao_map.value < 0:
        raise Error("A triangle names an ao map id that nothing can hold")
    if a.light_map != NO_TEXTURE and a.light_map.value < 0:
        raise Error("A triangle names a light map id that nothing can hold")
    if not a.kind.has_indirect() and (
        a.ao_map != NO_TEXTURE or a.light_map != NO_TEXTURE
    ):
        raise Error(
            "Only a basic or lit triangle has an ao map or a light map: no"
            " other shader has an indirect term for either to reach"
        )
    # Refused here, as the material refuses it, so a hand-built triangle
    # cannot smuggle one past.
    if a.specular_map != NO_TEXTURE and not a.kind.has_specular_map():
        raise Error(
            "Only a basic, lambert or phong triangle reads a specular map:"
            " no other shader reads one"
        )
    # The sheen, the film and the stretch, asked as the physical terms
    # are: the numbers before their agreement, then the kind.
    a.layers.check()
    if not b.layers.agrees(a.layers) or not c.layers.agrees(a.layers):
        raise Error(
            "A triangle's corners disagree about their sheen, iridescence,"
            " anisotropy or specular or clearcoat maps"
        )
    if a.kind != PHYSICAL and a.layers.is_layered():
        raise Error(
            "Only a physical triangle has a sheen, an iridescence, an"
            " anisotropy or a specular or clearcoat map: no other shader"
            " reads one"
        )
    # The volume, asked as the material asks it: the numbers first, since a
    # NaN never agrees, then the agreement, the ids and the kind.
    if not _is_unit_fraction(a.transmission):
        raise Error("A triangle's transmission must be between zero and one")
    if not _is_depth(a.thickness):
        raise Error("A triangle's thickness cannot be negative")
    var tint = a.attenuation_color
    if not _is_depth(Vector3(tint.r, tint.g, tint.b)):
        raise Error("A triangle's attenuation color cannot be negative")
    if not (a.attenuation_distance > 0):
        raise Error("A triangle's attenuation distance must be above zero")
    if not isfinite(a.dispersion) or a.dispersion < 0:
        raise Error("A triangle's dispersion cannot be negative")
    if not isfinite(a.ior) or a.ior < MIN_IOR or a.ior > MAX_IOR:
        raise Error(
            "A triangle's index of refraction must be between one and 2.333"
        )
    if not _same_volume(a, b) or not _same_volume(a, c):
        raise Error("A triangle's corners disagree about their volume")
    if a.transmission_map != NO_TEXTURE and a.transmission_map.value < 0:
        raise Error(
            "A triangle names a transmission map id that nothing can hold"
        )
    if a.thickness_map != NO_TEXTURE and a.thickness_map.value < 0:
        raise Error("A triangle names a thickness map id that nothing can hold")
    if a.kind != PHYSICAL and _has_volume(a):
        raise Error(
            "Only a physical triangle transmits: no other shader reads a volume"
        )
    # The node program, asked as the material asks it.
    if b.nodes != a.nodes or c.nodes != a.nodes:
        raise Error("A triangle's corners disagree about their node program")
    if not a.nodes.is_valid():
        raise Error("A triangle names a node program id that nothing can hold")
    if a.nodes != NO_NODES and not a.kind.takes_nodes():
        raise Error(
            "A data or shadow triangle runs no node graph: it shows"
            " data or a shadow, not a surface's color"
        )


def _is_depth(value: Vector3) -> Bool:
    """Return True if every axis of `value` is finite and not negative."""
    return (
        isfinite(value.x)
        and isfinite(value.y)
        and isfinite(value.z)
        and value.x >= 0
        and value.y >= 0
        and value.z >= 0
    )


def _same_volume(a: RasterVertex, b: RasterVertex) -> Bool:
    """Return True if two corners agree on every field of their volume."""
    return (
        a.transmission == b.transmission
        and a.transmission_map == b.transmission_map
        and a.thickness.x == b.thickness.x
        and a.thickness.y == b.thickness.y
        and a.thickness.z == b.thickness.z
        and a.thickness_map == b.thickness_map
        and a.attenuation_color.r == b.attenuation_color.r
        and a.attenuation_color.g == b.attenuation_color.g
        and a.attenuation_color.b == b.attenuation_color.b
        and a.attenuation_distance == b.attenuation_distance
        and a.dispersion == b.dispersion
        and a.ior == b.ior
    )


def _has_volume(a: RasterVertex) -> Bool:
    """Return True if a corner's volume is anything but the default: what
    a kind that does not transmit refuses."""
    return (
        a.transmission != 0
        or a.transmission_map != NO_TEXTURE
        or a.thickness.x != 0
        or a.thickness.y != 0
        or a.thickness.z != 0
        or a.thickness_map != NO_TEXTURE
        or a.attenuation_color.r != 1
        or a.attenuation_color.g != 1
        or a.attenuation_color.b != 1
        or a.attenuation_distance != inf[DType.float32]()
        or a.dispersion != 0
        or a.ior != DEFAULT_IOR
    )


def check_transmission(a: RasterVertex, mode: ShadeMode, ready: Bool) raises:
    """Refuse a transmissive triangle with no opaque scene to look through.

    A triangle transmits under `SHADE_TEXTURE` alone, since what it shows
    is read from a texture, the opaque scene drawn first. Shared by both
    rasterizers, and asked before the first fragment and before a launch.

    Args:
        a: The triangle's first corner.
        mode: What a fragment's color is taken from.
        ready: Whether a `TransmissionTarget` holding the opaque scene was
            given.

    Raises:
        Error: If the triangle transmits under this mode and no target was
            given.
    """
    if a.transmission > 0 and mode == SHADE_TEXTURE and not ready:
        raise Error(
            "A transmissive triangle needs the opaque scene behind it: pass"
            " a TransmissionTarget, as Renderer.render_into builds one"
        )


def _is_unit_fraction(value: Float32) -> Bool:
    """Return True if `value` is finite and between zero and one."""
    return isfinite(value) and value >= 0 and value <= 1


def check_output_kinds(
    corners: List[RasterVertex],
    mapped: Bool,
    segments: List[RasterVertex] = List[RasterVertex](),
    points: List[RasterVertex] = List[RasterVertex](),
) raises:
    """Refuse a tone-mapped frame that holds both data and blended light.

    **Two output representations cannot share a pixel, and a blend is what
    puts them there.** A `NORMALS` or `DEPTH` fragment writes bytes a
    display must show as they are; every other kind writes light that the
    tone mapping curve compresses. `RenderTarget.blend` resolves the
    mixture as light, because a mixture with light in it is light -- and
    that answer does not fade out with the alpha. A black surface at an
    alpha of 1e-8 leaves the stored color bit-for-bit identical, since
    `1 - alpha` rounds to one in Float32, and still turns the curve on for
    the normal underneath: (128, 128, 255) resolves as (117, 117, 188)
    through Reinhard. A fragment too faint to change a single channel
    should not be able to change the whole pixel's answer.

    No per-pixel rule fixes that. Making the mixture data instead lets
    scene light escape the curve, and a threshold only moves the jump to
    the threshold. So the frame is refused instead, once, before anything
    is drawn: draw the data materials in a pass of their own, or turn the
    tone mapping off. A blended data triangle is already refused outright
    by `check_triangle_state`; this is the other direction of the same
    rule.

    Asked of the whole list rather than per pixel, so both backends can ask
    it on the host before a launch. A kernel cannot raise part way through
    a frame, and a check that only fires where the two actually overlap
    would have to.

    Args:
        corners: Raster vertices, three per triangle, as submitted.
        mapped: Whether this frame resolves through a tone mapping curve.
            A frame with no curve has nothing to decide and is never
            refused.
        segments: Raster vertices, two per segment, as submitted alongside.
            A line is never data, but a blended one mixes light into
            whatever it crosses, a data pixel included, so it counts the
            same way a blended triangle does. Empty by default.
        points: Raster vertices, one per point, as submitted alongside. A
            point is never data either, and a blended one counts as a
            blended segment does. Empty by default.

    Raises:
        Error: If the curve is on and the frame holds both a surface that
            shows data, or a primitive whose material has `tone_mapped`
            off, and a surface, a segment or a point that blends.
    """
    if not mapped:
        return
    var shows_data = False
    var mixes_light = False
    for triangle in range(len(corners) // 3):
        ref first = corners[triangle * 3]
        # A triangle whose material turns the tone mapping off keeps the
        # curve off its pixels as a data triangle does, so it counts as
        # one. One that also blends is refused on its own: its pixels
        # would be mixtures.
        if first.kind.is_data() or not first.state.tone_mapped:
            shows_data = True
        if first.blend.mixes():
            mixes_light = True
    for segment in range(len(segments) // 2):
        ref start = segments[segment * 2]
        if not start.state.tone_mapped:
            shows_data = True
        if start.blend.mixes():
            mixes_light = True
    for point in range(len(points)):
        if not points[point].state.tone_mapped:
            shows_data = True
        if points[point].blend.mixes():
            mixes_light = True
    if shows_data and mixes_light:
        raise Error(
            "A tone-mapped frame cannot hold both a data material, or one"
            " with tone_mapped off, and a blended one: the curve is on for"
            " light and off for data, and a blend decides that for the"
            " pixel behind it however faint it is. Draw the data in its own"
            " pass, or set NO_TONE_MAPPING"
        )


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
    check_data_map(image, "An alpha map")


def check_data_map(image: Texture, name: String) raises:
    """Refuse a map that holds data and is not stored as data.

    The rule `check_alpha_map` states, for every map whose bytes are
    numbers rather than colors: an alpha map, a roughness map, a metalness
    map, a normal map and a bump map. Shared by both backends, so neither
    can accept what the other refuses, and the kernel's host side asks the
    same two questions of its descriptors with the same words.

    Args:
        image: The texture named as the map.
        name: What to call it in the error: "An alpha map", say.

    Raises:
        Error: If the texture's color space is not `LINEAR`, or it reads its
            alpha as coverage.
    """
    if image.color_space != LINEAR:
        raise Error(
            name
            + " holds data, not color; build the texture with"
            " color_space=LINEAR"
        )
    if image.alpha != IGNORED:
        raise Error(
            name
            + " must ignore its own alpha; build the texture with alpha=IGNORED"
        )


# How far off the middle of a matcap a surface square-on to the camera is
# looked up: three.js's own 0.495, which keeps the edge of the image out of
# the lookup and so out of any wrapping.
comptime MATCAP_SCALE = Float32(0.495)
# The two ends of three.js's fallback matcap, a gray gradient that reads as
# a sphere lit from above: `mix(0.2, 0.8, uv.y)`.
comptime MATCAP_FLOOR = Float32(0.2)
comptime MATCAP_CEILING = Float32(0.8)


def matcap_uv(toward_eye: Vector3, up: Vector3, normal: Vector3) -> Vector2:
    """Return where a `MATCAP` surface is looked up in its image.

    three.js's `matcap_fragment`, in world space rather than in view
    space. It builds a frame from the direction toward the camera and the
    camera's own up axis, then reads how far the normal leans along each:

        x = normalize(cross(up, toward_eye))
        y = cross(toward_eye, x)
        uv = (dot(x, normal), dot(y, normal)) * 0.495 + 0.5

    The same two dot products come out either way round, because the view
    transform is rigid and a dot product does not care how the pair is
    turned. Doing it here saves carrying a second normal and a second
    position per corner.

    Shared by both rasterizers, as `falloff` is, so neither can look a
    surface up somewhere the other does not.

    Args:
        toward_eye: Unit direction from the surface toward the camera.
        up: The camera's own up axis, in world space, already unit length.
        normal: The surface's unit normal, in world space.

    Returns:
        Where to sample, from 0.005 to 0.995 for unit inputs. The middle
        of the image when the frame collapses, which is when `up` and
        `toward_eye` are parallel or either is a zero vector.
    """
    var across = up
    across.cross(toward_eye)
    if across.length() == 0:
        return Vector2(0.5, 0.5)
    across.normalize()
    var upright = toward_eye
    upright.cross(across)
    return Vector2(
        across.dot(normal) * MATCAP_SCALE + 0.5,
        upright.dot(normal) * MATCAP_SCALE + 0.5,
    )


def matcap_fallback(v: Float32) -> Float32:
    """Return three.js's fallback matcap at a lookup height.

    `mix(0.2, 0.8, uv.y)`, a gray gradient: dark at the bottom, pale at
    the top, which reads as a sphere lit from above. Gray in all three
    channels, and in linear light rather than as an authored byte, because
    three.js writes it straight into the outgoing light.

    Args:
        v: How far up the image the surface is looked up, from zero to one.

    Returns:
        How much light the surface shows, in every channel.
    """
    return MATCAP_FLOOR + (MATCAP_CEILING - MATCAP_FLOOR) * v


def check_gradient_map(image: Texture) raises:
    """Refuse a ramp that is not stored as data.

    A gradient map is a lookup table and not a picture. Its red channel is
    how lit a surface looks, so it must be `LINEAR`, or the sRGB decode
    turns a byte of 128 into 0.216 rather than 0.502. And it must be
    `IGNORED`, or its own alpha weights the tones -- the reason an alpha
    map and an emissive map ask the same.

    **It must be exactly one row high.** three.js reads its gradient map at
    `vec2(coord, 0.0)`, and under this project's texture convention `v` of
    zero is the *bottom* row: every sampler here flips with `1 - v`, as
    `render.texture` explains. A ramp is read as a flat table instead, off
    the single row it has, so a taller image would leave two defensible
    answers and no way to tell which the author meant. One row has only one.

    A blank texture is refused as well. It has no row to read, and a ramp
    of no tones has no meaning; a material that wants the fallback names no
    map at all.

    Shared by both backends, so neither can accept what the other refuses.

    Args:
        image: The texture named as a gradient map.

    Raises:
        Error: If the texture is blank, it is more than one row high, its
            color space is not `LINEAR`, it reads its alpha as coverage, or
            it holds floats.
    """
    if image.is_blank():
        raise Error(
            "A gradient map must hold texels: name no map for the fallback"
        )
    if image.height != 1:
        raise Error(
            "A gradient map must be one row high: it is a lookup table, not"
            " a picture, and a taller image has no unambiguous row"
        )
    if image.color_space != LINEAR:
        raise Error(
            "A gradient map holds data, not color; build the texture with"
            " color_space=LINEAR"
        )
    if image.alpha != IGNORED:
        raise Error(
            "A gradient map must ignore its own alpha; build the texture"
            " with alpha=IGNORED"
        )
    if image.texel_type == FLOAT_TYPE:
        raise Error(
            "A gradient map must hold bytes: its tones are read one byte each"
        )


def gradient_ramp(image: Texture) raises -> List[Float32]:
    """Return a gradient map's top row as tones, left to right.

    The only row, because `check_gradient_map` refuses a taller image: a
    ramp is a flat table and `v` would otherwise be ambiguous. Only the red
    channel, because three.js reads `.r`. Read once per triangle rather
    than per fragment: the row is the same for every pixel, and a texture
    lookup per light per pixel would open it a hundred thousand times a
    frame.

    Args:
        image: The texture named as a gradient map, already checked by
            `check_gradient_map`.

    Returns:
        One tone per texel across, from zero to one.

    Raises:
        Error: If a texel cannot be read.
    """
    var tones = List[Float32]()
    # A checked map holds at least one texel, so this never runs zero times.
    for x in range(image.width):  # pragma: no branch
        tones.append(Float32(image.texel(x, 0).r) / 255)
    return tones^


def check_triangle_maps(
    a: RasterVertex,
    mode: ShadeMode,
    textures: TextureStore,
    cubes: CubeTextureStore = CubeTextureStore(),
    programs: NodeProgramStore = NodeProgramStore(),
) raises:
    """Refuse a triangle whose maps are not stored the way its shader reads
    them, under the mode that would read them.

    The four checks `rasterize_shaded` makes before its first fragment,
    asked of the first corner, which `check_triangle_state` has made
    authoritative. `rasterize_all` asks them of every triangle before any
    band starts, so a triangle a band's rows never reach is refused on
    four workers as it is on one; a band skips such a triangle before
    `rasterize_shaded` can look at it. The kernel asks the same four before
    a launch.

    Args:
        a: The triangle's first corner.
        mode: What a fragment's color is taken from; only `SHADE_TEXTURE`
            opens the base, emissive and alpha maps, and only the uv view
            opens neither the ramp nor the matcap.
        textures: Where the maps live.
        cubes: Where the env map lives. Only `SHADE_TEXTURE` opens it: a
            reflection is a texture, and the other two modes ignore every
            texture.
        programs: Where the node program lives. Every mode but the uv view
            runs it, and only `SHADE_TEXTURE` opens the textures it reads.

    Raises:
        Error: If a map the mode would open is not in the store; an
            emissive map or a matcap does not ignore its alpha; an alpha
            map is not stored as data; a gradient map is not a
            one-row linear table -- see `check_alpha_map` and
            `check_gradient_map`; an env map `SHADE_TEXTURE` would open
            is not in the cube store; an ao map is not stored as data; a
            light map does not ignore its alpha; a sheen color map does not
            ignore its alpha; a sheen roughness map is not linear or
            ignores its alpha; an iridescence, thickness or anisotropy map
            is not stored as data; a specular intensity map is not linear
            or ignores its alpha; a specular color map does not ignore its
            alpha; a clearcoat, clearcoat roughness or clearcoat normal map
            is not stored as data; or a node program a mode would run is
            not in its store, or names a texture `SHADE_TEXTURE` would open
            that is not in the store.
    """
    # An emissive map's alpha means nothing, and only a texture built to
    # ignore it filters accordingly -- see `render.texture.Alpha`. Asked
    # only when the map will be opened: SHADE_LIT never reads it.
    if a.emissive_map != NO_TEXTURE and mode == SHADE_TEXTURE:
        if textures.get(a.emissive_map).alpha != IGNORED:
            raise Error(
                "An emissive map must ignore its alpha; build the texture"
                " with alpha=IGNORED"
            )
    # An alpha map holds data, and says so twice: linear, or the sRGB curve
    # changes what its bytes mean, and alpha ignored, or filtering weights
    # its green by an alpha that means nothing.
    if a.alpha_map != NO_TEXTURE and mode == SHADE_TEXTURE:
        check_alpha_map(textures.get(a.alpha_map))
    # The ramp a `TOON` surface steps through. The uv debug view shades
    # nothing and reads none.
    if a.gradient_map != NO_TEXTURE and mode != SHADE_UV:
        check_gradient_map(textures.get(a.gradient_map))
    # A matcap's own alpha means nothing, so only a texture built to
    # ignore it filters accordingly -- the rule an emissive map follows.
    if a.matcap != NO_TEXTURE and mode != SHADE_UV:
        if textures.get(a.matcap).alpha != IGNORED:
            raise Error(
                "A matcap must ignore its alpha; build the texture with"
                " alpha=IGNORED"
            )
    # The environment a reflecting surface samples, which must be there:
    # asked before the first fragment, as the store's own `get` would ask
    # it at the first fragment and a band with no fragment would not.
    if a.env_map != NO_CUBE_TEXTURE and mode == SHADE_TEXTURE:
        _ = cubes.get(a.env_map).size
    # The five maps that hold numbers, each asked the alpha map's two
    # questions, and only under the mode that opens them.
    if mode == SHADE_TEXTURE:
        if a.roughness_map != NO_TEXTURE:
            check_data_map(textures.get(a.roughness_map), "A roughness map")
        if a.metalness_map != NO_TEXTURE:
            check_data_map(textures.get(a.metalness_map), "A metalness map")
        if a.normal_map != NO_TEXTURE:
            check_data_map(textures.get(a.normal_map), "A normal map")
        if a.bump_map != NO_TEXTURE:
            check_data_map(textures.get(a.bump_map), "A bump map")
        # An ao map holds a number, and a light map holds light whose
        # alpha means nothing, the rule an emissive map follows.
        if a.ao_map != NO_TEXTURE:
            check_data_map(textures.get(a.ao_map), "An ao map")
        if a.light_map != NO_TEXTURE:
            check_light_map(textures.get(a.light_map))
        if a.specular_map != NO_TEXTURE:
            check_data_map(textures.get(a.specular_map), "A specular map")
        if a.transmission_map != NO_TEXTURE:
            check_data_map(
                textures.get(a.transmission_map), "A transmission map"
            )
        if a.thickness_map != NO_TEXTURE:
            check_data_map(textures.get(a.thickness_map), "A thickness map")
        # The layers' maps: a color whose alpha means nothing, a number
        # read from the alpha, and three numbers read from the color.
        ref layers = a.layers
        if layers.sheen_color_map != NO_TEXTURE:
            check_color_map(
                textures.get(layers.sheen_color_map), "A sheen color map"
            )
        if layers.sheen_roughness_map != NO_TEXTURE:
            check_alpha_data_map(
                textures.get(layers.sheen_roughness_map),
                "A sheen roughness map",
            )
        if layers.iridescence_map != NO_TEXTURE:
            check_data_map(
                textures.get(layers.iridescence_map), "An iridescence map"
            )
        if layers.thickness_map != NO_TEXTURE:
            check_data_map(
                textures.get(layers.thickness_map),
                "An iridescence thickness map",
            )
        if layers.anisotropy_map != NO_TEXTURE:
            check_data_map(
                textures.get(layers.anisotropy_map), "An anisotropy map"
            )
        # The specular and coat maps: a number read from the alpha, a
        # color whose alpha means nothing, and three maps of data.
        if layers.specular_intensity_map != NO_TEXTURE:
            check_alpha_data_map(
                textures.get(layers.specular_intensity_map),
                "A specular intensity map",
            )
        if layers.specular_color_map != NO_TEXTURE:
            check_color_map(
                textures.get(layers.specular_color_map), "A specular color map"
            )
        if layers.clearcoat_map != NO_TEXTURE:
            check_data_map(
                textures.get(layers.clearcoat_map), "A clearcoat map"
            )
        if layers.clearcoat_roughness_map != NO_TEXTURE:
            check_data_map(
                textures.get(layers.clearcoat_roughness_map),
                "A clearcoat roughness map",
            )
        if layers.clearcoat_normal_map != NO_TEXTURE:
            check_data_map(
                textures.get(layers.clearcoat_normal_map),
                "A clearcoat normal map",
            )
        # Every map reads one of the two sets of coordinates, and no
        # other: its placement picks the pair by the channel.
        var named = surface_maps(a)
        for index in range(len(named)):  # pragma: no branch
            if named[index] != NO_TEXTURE:
                check_channel(textures.get(named[index]))
    # The node program, and every texture it reads: the kernel asks the
    # same before a launch.
    if a.nodes != NO_NODES and mode != SHADE_UV:
        ref program = programs.get(a.nodes)
        if mode == SHADE_TEXTURE:
            for index in range(len(program.textures)):
                if program.textures[index].value < 0:
                    raise Error(
                        "A node program reads a texture uniform that names"
                        " no texture; call set_texture() first"
                    )
                _ = textures.get(program.textures[index]).width


def check_channel(image: Texture) raises:
    """Refuse a map whose channel is neither of the two sets.

    A placement reads `uv1` for `UV_CHANNEL_1` and `uv` for anything
    else, so a third value would be read as the first on both sides
    without a word. Shared by both backends.

    Args:
        image: The texture named as a map.

    Raises:
        Error: If its channel is not `UV_CHANNEL_0` or `UV_CHANNEL_1`.
    """
    if not image.channel.is_valid():
        raise Error("A texture's channel must be UV_CHANNEL_0 or UV_CHANNEL_1")


# Where each map's placement is in `surface_maps` and `map_placements`:
# every map three.js samples at a varying of its own, `vMapUv` and the
# rest. The gradient map, the matcap and the env map are read at no
# surface coordinate and have no slot.
comptime MAP_SLOT = 0
comptime ALPHA_MAP_SLOT = 1
comptime EMISSIVE_MAP_SLOT = 2
comptime ROUGHNESS_MAP_SLOT = 3
comptime METALNESS_MAP_SLOT = 4
comptime SPECULAR_MAP_SLOT = 5
comptime NORMAL_MAP_SLOT = 6
comptime BUMP_MAP_SLOT = 7
comptime AO_MAP_SLOT = 8
comptime LIGHT_MAP_SLOT = 9
comptime TRANSMISSION_MAP_SLOT = 10
comptime THICKNESS_MAP_SLOT = 11
comptime SHEEN_COLOR_MAP_SLOT = 12
comptime SHEEN_ROUGHNESS_MAP_SLOT = 13
comptime IRIDESCENCE_MAP_SLOT = 14
comptime IRIDESCENCE_THICKNESS_MAP_SLOT = 15
comptime ANISOTROPY_MAP_SLOT = 16
comptime SPECULAR_COLOR_MAP_SLOT = 17
comptime SPECULAR_INTENSITY_MAP_SLOT = 18
comptime CLEARCOAT_MAP_SLOT = 19
comptime CLEARCOAT_ROUGHNESS_MAP_SLOT = 20
comptime CLEARCOAT_NORMAL_MAP_SLOT = 21
comptime MAP_SLOTS = CLEARCOAT_NORMAL_MAP_SLOT + 1


def surface_maps(a: RasterVertex) -> List[TextureId]:
    """Return every map a corner names that is sampled at a surface
    coordinate, `MAP_SLOTS` of them, in slot order.

    Args:
        a: The corner.

    Returns:
        The ids, `NO_TEXTURE` where the corner names none.
    """
    ref layers = a.layers
    return [
        a.texture,
        a.alpha_map,
        a.emissive_map,
        a.roughness_map,
        a.metalness_map,
        a.specular_map,
        a.normal_map,
        a.bump_map,
        a.ao_map,
        a.light_map,
        a.transmission_map,
        a.thickness_map,
        layers.sheen_color_map,
        layers.sheen_roughness_map,
        layers.iridescence_map,
        layers.thickness_map,
        layers.anisotropy_map,
        layers.specular_color_map,
        layers.specular_intensity_map,
        layers.clearcoat_map,
        layers.clearcoat_roughness_map,
        layers.clearcoat_normal_map,
    ]


def map_placements(
    a: RasterVertex, textures: TextureStore, opened: Bool
) raises -> List[UvPlacement]:
    """Return where each of a triangle's maps is sampled, in slot order.

    Worked out once a triangle rather than once a sample: a placement
    turns its texture's `rotation` into a sine and a cosine. The kernel
    reads the same numbers from its texture table instead.

    Args:
        a: The triangle's first corner.
        textures: Where the maps live.
        opened: Whether the mode opens the maps. When it does not, every
            slot is the identity and no texture is read.

    Returns:
        `MAP_SLOTS` placements: each named map's own, and the identity
        on `UV_CHANNEL_0` where the corner names none.

    Raises:
        Error: If an opened map is not in the store.
    """
    var named = surface_maps(a)
    var placed = List[UvPlacement](length=MAP_SLOTS, fill=UvPlacement())
    if not opened:
        return placed^
    for slot in range(MAP_SLOTS):  # pragma: no branch
        if named[slot] != NO_TEXTURE:
            placed[slot] = textures.get(named[slot]).placement()
    return placed^


def check_color_map(image: Texture, name: String) raises:
    """Refuse a map of color whose alpha is read as coverage.

    The rule `check_light_map` states, for a map that holds a color and
    no coverage: a sheen color map. Filtered as coverage, a texel with a
    low alpha would darken its neighbors. Shared by both backends.

    Args:
        image: The texture named as the map.
        name: What to call it in the error: "A sheen color map", say.

    Raises:
        Error: If the texture reads its alpha as coverage.
    """
    if image.alpha != IGNORED:
        raise Error(
            name
            + " must ignore its alpha; build the texture with alpha=IGNORED"
        )


def check_alpha_data_map(image: Texture, name: String) raises:
    """Refuse a map that holds a number in its alpha and is not stored so.

    three.js reads a sheen roughness map's *alpha*, as glTF's
    `KHR_materials_sheen` stores it. The number is data, so the texture
    must be linear, and it is the alpha, so the alpha must be read: a
    texture built to ignore it reads one everywhere. Shared by both
    backends.

    Args:
        image: The texture named as the map.
        name: What to call it in the error: "A sheen roughness map", say.

    Raises:
        Error: If the texture's color space is not `LINEAR`, or it ignores
            its alpha.
    """
    if image.color_space != LINEAR:
        raise Error(
            name
            + " holds data, not color; build the texture with"
            " color_space=LINEAR"
        )
    if image.alpha != COVERAGE:
        raise Error(
            name
            + " is read from its alpha; build the texture with alpha=COVERAGE"
        )


def check_light_map(image: Texture) raises:
    """Refuse a light map whose alpha is read as coverage.

    A light map holds light, so either color space is right, but its alpha
    means nothing: filtered as coverage, a texel with a low alpha would
    darken its neighbors, the reason an emissive map asks the same. Shared
    by both backends, so neither can accept what the other refuses.

    Args:
        image: The texture named as a light map.

    Raises:
        Error: If the texture reads its alpha as coverage.
    """
    if image.alpha != IGNORED:
        raise Error(
            "A light map must ignore its alpha; build the texture with"
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
    cubes: CubeTextureStore = CubeTextureStore(),
    transmission: TransmissionTarget = TransmissionTarget(),
    programs: NodeProgramStore = NodeProgramStore(),
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
        cubes: Where `SHADE_TEXTURE` looks the triangle's env map up. A
            triangle that names one reflects it after the lights, the
            highlight and the glow and before the fog, by
            `materials.material.combine_light`; see `render.cube_texture`.
        transmission: The opaque scene a transmissive triangle shows
            through itself under `SHADE_TEXTURE`, or an empty target for
            a frame with nothing transmissive; see `render.transmission`.
        programs: Where a node material's program lives. Every mode but
            the uv view runs it: its normal node before the lights, its
            color, opacity and emissive nodes once the maps have had their
            say, and its output node after the fog. See
            `materials.nodes`.

    Raises:
        Error: If the mode is none of the three, the fog view holds a kind
            or a number that `FogView.validate` refuses, a vertex names a
            texture the
            store does not have, the corners disagree about their maps,
            blend policy, material kind, alpha test or shininess or hold
            one that is none of the named values, an emissive map that
            `SHADE_TEXTURE` would open does not ignore its alpha, an alpha
            map it would open is not linear or does not ignore its alpha,
            an env map it would open is not in the cube store,
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
    # The maps, asked before the first fragment as the GPU asks before the
    # launch, and only under the mode that would open each.
    check_triangle_maps(a, mode, textures, cubes, programs)
    check_transmission(a, mode, transmission.is_ready())
    # The ramp a `TOON` surface steps through, read once here. Its top row
    # is the whole lookup table, and it is the same for every fragment, so
    # opening the texture per light per pixel would buy nothing. Empty for
    # a triangle that names no ramp, which is three.js's fallback. The uv
    # debug view shades nothing and reads none.
    var ramp = List[Float32]()
    if a.gradient_map != NO_TEXTURE and mode != SHADE_UV:
        ramp = gradient_ramp(textures.get(a.gradient_map))

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
    var blended = a.blend.mixes() and mode != SHADE_UV
    # Whether these fragments show data rather than light: a normal or a
    # depth. The lights, the glow and the fog leave them alone, and the
    # target keeps the tone mapping off them.
    var data = a.kind.is_data()
    # Whether the fog reaches these fragments: never in the uv debug view,
    # which shows coordinates rather than light, never a surface that
    # shows data, and never a surface whose material turns it off.
    var fogged = fog.is_on() and mode != SHADE_UV and not data and a.fog
    # Whether a fragment of this triangle can be thrown away for being too
    # transparent. Such a fragment must claim no depth until it survives,
    # or the hole it cuts hides what is behind it: the *late* depth write a
    # GPU makes for a shader that can discard. The uv debug view shows the
    # nearest surface's coordinates and cuts nothing out, as it samples no
    # texture.
    var tested = a.alpha_test > 0 and mode != SHADE_UV
    # Whether a hashed alpha test or the alpha's coverage can throw a
    # fragment away, three.js's `alphaHash` and `alphaToCoverage`: a
    # discard like the alpha test's, asked after it. The uv view cuts
    # nothing out. See `render.fragment_flags`.
    var hashed = a.state.alpha_hash and mode != SHADE_UV
    var covered = a.state.alpha_to_coverage and mode != SHADE_UV
    var may_discard = tested or hashed or covered
    # Whether the finished color is dithered, three.js's `dithering`.
    # Never data, which is bytes and not light.
    var dithered = a.state.dithering and not data
    # Whether an opaque fragment keeps the tone mapping off its pixel,
    # three.js's `toneMapped: false`, as a data fragment keeps it off.
    var untoned = data or not a.state.tone_mapped
    # Whether a fragment that passes writes its depth: one with the depth
    # test and the depth write on, blending or not, as in three.js; see
    # `render.raster_state.RasterState.writes_depth`.
    var writes_depth = a.state.writes_depth()
    # Whether these fragments reflect an environment: only when they name
    # one and the mode opens textures, since a reflection is one. A
    # reflecting surface needs its normal and its world position whether
    # or not it is lit, which is why the two are gated on this below.
    var reflects = a.env_map != NO_CUBE_TEXTURE and mode == SHADE_TEXTURE
    # Whether these fragments are shaded by a roughness and a metalness
    # rather than by a color and a highlight, and whether a clear coat
    # lies over them.
    var physical = a.kind.is_physical()
    var coated = physical and a.clearcoat > 0
    # Whether these fragments show the opaque scene through themselves:
    # only when the triangle transmits and the mode opens textures, since
    # the scene behind is read from one.
    var transmits = a.transmission > 0 and mode == SHADE_TEXTURE
    # Whether the normal is perturbed by a map before anything reads it:
    # only when the triangle names one and the mode opens textures, since
    # a normal map is one.
    var perturbed = (
        a.normal_map != NO_TEXTURE or a.bump_map != NO_TEXTURE
    ) and mode == SHADE_TEXTURE
    # Whether these fragments show the shadows falling on them and
    # nothing else: a `SHADOW` material, transparent wherever lit.
    var catches = a.kind == SHADOW and mode != SHADE_UV
    # Whether an ambient occlusion map or a light map acts on the indirect
    # light: only when the triangle names one and the mode opens textures.
    var bakes = (
        a.ao_map != NO_TEXTURE or a.light_map != NO_TEXTURE
    ) and mode == SHADE_TEXTURE
    # Whether the target keeps each opaque fragment's view-space normal,
    # a G-buffer's second attachment. Every triangle interpolates its
    # normal then, whatever it is shaded by; see `RenderTarget.write`.
    var keeps_normals = target.has_normals()
    # Whether a node graph replaces parts of the shading: under every mode
    # but the uv view, which shades nothing. It reads the normal, the
    # position and the coordinates whatever the kind, so it opens all three.
    var noded = a.nodes != NO_NODES and mode != SHADE_UV

    var flat = Triangle(Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
    var coverage = _Coverage(flat)
    if coverage.is_degenerate():
        return
    # The program, and this triangle's own footprint for the textures it
    # reads, moved to each fragment below.
    var nodes = _HostNodes(
        Pointer(to=programs).unsafe_origin_cast[ImmutAnyOrigin](),
        a.nodes.value,
        Pointer(to=textures).unsafe_origin_cast[ImmutAnyOrigin](),
        Pointer(to=a).unsafe_origin_cast[ImmutAnyOrigin](),
        Pointer(to=b).unsafe_origin_cast[ImmutAnyOrigin](),
        Pointer(to=c).unsafe_origin_cast[ImmutAnyOrigin](),
        coverage,
        target.height,
    )
    var textured = mode == SHADE_TEXTURE
    # Whether the graph can throw a fragment away, as an alpha test can:
    # its mask, which every `Discard` joins. And whether it sets the depth
    # itself, before the tests read it.
    var masked = noded and has_output(nodes, MASK_NODE)
    var deep = noded and has_output(nodes, DEPTH_NODE)
    var reversed = a.state.depth_mode == REVERSED_DEPTH
    # Where each map is sampled: its own channel and matrix, three.js's
    # `vMapUv`, `vNormalMapUv` and the rest. The corners carry the two raw
    # pairs, and each map places them for itself.
    var placed = map_placements(a, textures, textured)

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
            # The denominator of the perspective correction, and the
            # interpolated reciprocal depth in its own right.
            var inv_w = wa * a.inv_w + wb * b.inv_w + wc * c.inv_w
            # The depth the buffer tests and keeps: `z` itself, or its
            # logarithmic or reversed form; see
            # `render.raster_state.fragment_depth`. A `DEPTH` material
            # still shows `z`.
            var stored_z = fragment_depth(a.state, z, inv_w)
            # The node graph's depth replaces it, three.js's `depthNode`,
            # from the fragment's own interpolated attributes: the shading
            # that makes the rest has not run yet.
            nodes.x = x
            nodes.y = y
            nodes.depth = z
            if deep:
                stored_z = node_depth(
                    run_nodes(nodes, DEPTH_NODE, here_inputs(nodes, textured))[
                        0
                    ],
                    reversed,
                )
            # The stencil and the depth tests, asked without changing
            # anything: the depth and the stencil are written once the
            # fragment survives its alpha test, the *late* write a GPU
            # makes for a shader that can discard. A failing fragment
            # settles here unless an alpha test could still discard it;
            # see `render.raster_state.shades`.
            var test = target.test_fragment(x, y, stored_z, a.state)
            if not shades(test, may_discard or masked):
                target.keep_stencil(x, y, test)
                continue
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
            if (
                a.kind.is_lit()
                or a.kind == NORMALS
                or a.kind == MATCAP
                or reflects
                or catches
                or keeps_normals
                or noded
            ):
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
            # Where this fragment is in the world, for the lights that have
            # a position, and for the direction the camera sees it along --
            # which a reflection needs of an unlit surface too.
            var spot = Vector3(0, 0, 0)
            if (
                (
                    (a.kind.is_lit() or a.kind == MATCAP or a.kind == DISTANCE)
                    and mode != SHADE_UV
                )
                or reflects
                or catches
                or noded
            ):
                spot = Vector3(
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
            # The raw texture coordinates, both pairs, for the two modes
            # that read them and for a node graph. Each map places them
            # for itself below; the uv view and a node graph read the
            # first pair as it is, three.js's `vUv`.
            var u = Float32(0)
            var v = Float32(0)
            var uv1 = Vector2(0, 0)
            if mode != SHADE_LIT or noded:
                u = a.u * share_a + b.u * share_b + c.u * share_c
                v = a.v * share_a + b.v * share_b + c.v * share_c
                uv1 = Vector2(
                    a.u1 * share_a + b.u1 * share_b + c.u1 * share_c,
                    a.v1 * share_a + b.v1 * share_b + c.v1 * share_c,
                )
            var uv = Vector2(u, v)
            # The normal before any map perturbs it: what a clear coat lies
            # on, three.js's `nonPerturbedNormal`.
            var coat_facing = facing
            # `check_triangle_state` has refused a map on any kind that is
            # not lit or a matcap, so a perturbed triangle has a normal
            # above to perturb.
            if perturbed:
                # The tangent frame, from how the position and the
                # coordinates change one pixel to the right and one pixel
                # up, evaluated from the triangle's own functions rather
                # than read from a neighboring thread -- as `mip_level`
                # measures a footprint. Up rather than down, because the
                # frame's handedness follows the screen's rows counting
                # upward, as three.js's `dFdy` does; see `mapped_normal`.
                # The coordinates are the map's own, placed, as three.js
                # reads `vNormalMapUv` or `vBumpMapUv`.
                var right = _weights(coverage, x + 1, y)
                var up = _weights(coverage, x, y - 1)
                var along_x = _world_at(a, b, c, right) - spot
                var along_y = _world_at(a, b, c, up) - spot
                if a.normal_map != NO_TEXTURE:
                    ref normals = textures.get(a.normal_map)
                    var turned = placed[NORMAL_MAP_SLOT]
                    var at = turned.place(uv, uv1)
                    var steps = _placed_steps(a, b, c, turned, at, right, up)
                    var texel = _sample_map(
                        normals, at.x, at.y, a, b, c, coverage, x, y, turned
                    )
                    if a.frames.normal_map_type == OBJECT_SPACE_NORMAL_MAP:
                        facing = object_space_normal(
                            facing, texel, a.frames.object_normal
                        )
                    else:
                        facing = mapped_normal(
                            facing,
                            along_x,
                            along_y,
                            steps[0],
                            steps[1],
                            texel,
                            a.normal_scale,
                        )
                else:
                    # The height here and one pixel over each way, scaled:
                    # three.js's `dHdxy_fwd`.
                    ref heights = textures.get(a.bump_map)
                    var raised = placed[BUMP_MAP_SLOT]
                    var at = raised.place(uv, uv1)
                    var steps = _placed_steps(a, b, c, raised, at, right, up)
                    var here = (
                        a.bump_scale
                        * _sample_map(
                            heights, at.x, at.y, a, b, c, coverage, x, y, raised
                        ).r
                    )
                    var rise_x = (
                        a.bump_scale
                        * _sample_map(
                            heights,
                            at.x + steps[0].x,
                            at.y + steps[0].y,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                            raised,
                        ).r
                        - here
                    )
                    var rise_y = (
                        a.bump_scale
                        * _sample_map(
                            heights,
                            at.x + steps[1].x,
                            at.y + steps[1].y,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                            raised,
                        ).r
                        - here
                    )
                    facing = bumped_normal(
                        facing, along_x, along_y, rise_x, rise_y
                    )
            # The node graph's normal offset, after any map and before the
            # lights read the normal, as three.js's `normalNode` is.
            if noded and has_output(nodes, NORMAL_NODE):
                facing = offset_normal(
                    facing,
                    run_nodes(
                        nodes,
                        NORMAL_NODE,
                        NodeInputs(
                            u,
                            v,
                            spot,
                            facing,
                            Vector3(base.r, base.g, base.b),
                            Vector3(0, 0, 0),
                            textured,
                        ),
                    ),
                )
            if (a.kind.is_lit() or a.kind == MATCAP) and mode != SHADE_UV:
                if a.kind == MATCAP:
                    # Looked up by which way the surface is turned in the
                    # camera's frame, and multiplied into the color exactly
                    # as arriving light is: three.js's
                    # `outgoingLight = diffuseColor.rgb * matcapColor.rgb`.
                    # Measured from where the camera stands under either
                    # projection, because three.js reads `vViewPosition`
                    # and does not special-case a parallel one.
                    var place = matcap_uv(
                        toward_eye_at(lighting.eye, PERSPECTIVE_VIEW, spot),
                        lighting.up,
                        facing,
                    )
                    if a.matcap != NO_TEXTURE:
                        ref ball = textures.get(a.matcap)
                        # The full-size level, never a mip: the coordinate
                        # comes from the normal rather than from the
                        # surface, so a pixel's footprint in this image is
                        # not the footprint the chain was built for.
                        var looked = ball.sample(place.x, place.y)
                        arriving = FloatColor(looked.r, looked.g, looked.b, 1.0)
                    else:
                        var gray = matcap_fallback(place.y)
                        arriving = FloatColor(gray, gray, gray, 1.0)
                elif a.kind == TOON:
                    # Every cosine read off the ramp rather than faded, and
                    # never clamped at zero: see `Lighting.toon_at`.
                    arriving = lighting.toon_at(
                        facing, spot, ramp, a.receives_shadow
                    )
                elif not physical:
                    # A physical surface is lit below, once its maps have
                    # had their say over the color the lobe is tinted by.
                    arriving = lighting.intensity_at(
                        facing, spot, a.receives_shadow
                    )
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
                        a.receives_shadow,
                    )
            # The baked maps, three.js's `lights_fragment_maps` and
            # `aomap_fragment`, each sampled where its own placement puts
            # the fragment, usually on the second pair. The
            # light map's light joins the indirect diffuse light, and the
            # ao map's red dims the sum and leaves the direct lights alone.
            # A basic surface's whole color is indirect: a light map
            # replaces it, divided by pi as three.js's `meshbasic_frag`
            # divides it, and the ao map dims it. A physical surface
            # takes both below, where its indirect light is summed.
            var occlusion = Float32(1)
            var baked = Vector3(0, 0, 0)
            if bakes:
                if a.ao_map != NO_TEXTURE:
                    occlusion = ambient_occlusion(
                        _sample_placed(
                            textures.get(a.ao_map),
                            placed[AO_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).r,
                        a.ao_map_intensity,
                    )
                var lit = a.kind.is_lit()
                if a.light_map != NO_TEXTURE:
                    var glowed = _sample_placed(
                        textures.get(a.light_map),
                        placed[LIGHT_MAP_SLOT],
                        uv,
                        uv1,
                        a,
                        b,
                        c,
                        coverage,
                        x,
                        y,
                    )
                    var strength = a.light_map_intensity * (
                        lighting.scale if lit else RECIPROCAL_PI
                    )
                    baked = Vector3(
                        glowed.r * strength,
                        glowed.g * strength,
                        glowed.b * strength,
                    )
                    if not lit:
                        arriving = FloatColor(0.0, 0.0, 0.0, 1.0)
            # The node graph's ambient occlusion replaces the map's,
            # three.js's `aoNode`, under every mode that shades.
            var occludes = noded and has_output(nodes, AO_NODE)
            if occludes:
                occlusion = run_nodes(
                    nodes,
                    AO_NODE,
                    NodeInputs(
                        u,
                        v,
                        spot,
                        facing,
                        Vector3(base.r, base.g, base.b),
                        Vector3(0, 0, 0),
                        textured,
                    ),
                )[0]
            if (bakes or occludes) and not physical:
                var indirect = Vector3(arriving.r, arriving.g, arriving.b)
                if a.kind.is_lit():
                    var around = lighting.indirect_at(facing)
                    indirect = Vector3(around.r, around.g, around.b)
                var occluded = occluded_light(
                    Vector3(arriving.r, arriving.g, arriving.b),
                    indirect,
                    baked,
                    occlusion,
                )
                arriving = FloatColor(occluded.x, occluded.y, occluded.z, 1.0)
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
            # What a physical surface's roughness and metalness are
            # multiplied by: its maps' green and blue, or one for none.
            var rough_factor = Float32(1)
            var metal_factor = Float32(1)
            # What the highlight and the reflectivity are scaled by: the
            # specular map's red, or one for none.
            var specular_strength = Float32(1)
            # What the transmission and the thickness are multiplied by:
            # the transmission map's red and the thickness map's green, or
            # one for none.
            var transmission_factor = Float32(1)
            var thickness_factor = Float32(1)
            # What a physical surface's sheen, film and stretch read from
            # their maps, or what leaves each number alone.
            var sheen_tint = Vector3(1, 1, 1)
            var sheen_alpha = Float32(1)
            var film_factor = Float32(1)
            var thickness_texel = Float32(0)
            var thickness_mapped = False
            var stretch_texel = NO_ANISOTROPY_TEXEL
            # What a physical surface's specular color and intensity, its
            # coat and its coat's roughness are multiplied by, and the
            # coat's normal map's texel: one for none, and no texel.
            var specular_texel = Vector3(1, 1, 1)
            var specular_alpha = Float32(1)
            var coat_factor = Float32(1)
            var coat_rough_factor = Float32(1)
            var coat_texel = FloatColor(0.5, 0.5, 1.0, 1.0)
            var coat_mapped = False
            # Each mode by name, as the kernel does, so there is no "else"
            # for an unrecognized one to fall into differently on each side.
            if mode == SHADE_UV or mode == SHADE_TEXTURE:
                if mode == SHADE_UV:
                    # Coordinates, not light: written as data, which
                    # bypasses the transfer function and the tone mapping
                    # -- see `data_color`. Opaque, which is why the alpha
                    # is one. Never alpha tested, so the fragment passed.
                    target.keep_stencil(x, y, test)
                    if writes_depth:
                        target.claim_depth(x, y, stored_z)
                    if a.state.color_write:
                        target.write(
                            x,
                            y,
                            data_color(u, v, 0.0, 1.0),
                            True,
                            _kept_normal(
                                facing, a.kind, lighting, keeps_normals
                            ),
                        )
                    continue
                else:
                    # Modulate rather than replace: the texture says what
                    # color the surface is, the lighting says how much of it
                    # reaches the camera, and a renderer needs both.
                    var texel = FloatColor(1.0, 1.0, 1.0, 1.0)
                    if a.texture != NO_TEXTURE:
                        ref image = textures.get(a.texture)
                        texel = _sample_placed(
                            image,
                            placed[MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
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
                        var thinning = _sample_placed(
                            mask,
                            placed[ALPHA_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        )
                        shaded = FloatColor(
                            shaded.r, shaded.g, shaded.b, shaded.a * thinning.g
                        )
                    # The emissive map multiplies the glow the same way,
                    # alpha aside: light given off has no coverage.
                    if a.emissive_map != NO_TEXTURE:
                        ref glow_image = textures.get(a.emissive_map)
                        var glowing = _sample_placed(
                            glow_image,
                            placed[EMISSIVE_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        )
                        glow = FloatColor(
                            glow.r * glowing.r,
                            glow.g * glowing.g,
                            glow.b * glowing.b,
                            1.0,
                        )
                    # The roughness map's green and the metalness map's
                    # blue, three.js's `roughnessmap_fragment` and
                    # `metalnessmap_fragment`, which read those channels
                    # so one image can carry both.
                    if a.roughness_map != NO_TEXTURE:
                        ref rough_image = textures.get(a.roughness_map)
                        rough_factor = _sample_placed(
                            rough_image,
                            placed[ROUGHNESS_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).g
                    if a.metalness_map != NO_TEXTURE:
                        ref metal_image = textures.get(a.metalness_map)
                        metal_factor = _sample_placed(
                            metal_image,
                            placed[METALNESS_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).b
                    # The specular map's red, three.js's
                    # `specularmap_fragment`: it scales the highlight here
                    # and the reflectivity below, as three.js's
                    # `specularStrength` scales both.
                    if a.specular_map != NO_TEXTURE:
                        ref strength_image = textures.get(a.specular_map)
                        specular_strength = _sample_placed(
                            strength_image,
                            placed[SPECULAR_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).r
                        highlight = FloatColor(
                            highlight.r * specular_strength,
                            highlight.g * specular_strength,
                            highlight.b * specular_strength,
                            1.0,
                        )
                    # The layers' maps, three.js's `lights_physical_fragment`:
                    # the sheen color map's color, the sheen roughness map's
                    # *alpha*, the iridescence map's red, the thickness
                    # map's green, and the anisotropy map's whole texel.
                    ref layered = a.layers
                    if layered.sheen_color_map != NO_TEXTURE:
                        var tint = _sample_placed(
                            textures.get(layered.sheen_color_map),
                            placed[SHEEN_COLOR_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        )
                        sheen_tint = Vector3(tint.r, tint.g, tint.b)
                    if layered.sheen_roughness_map != NO_TEXTURE:
                        sheen_alpha = _sample_placed(
                            textures.get(layered.sheen_roughness_map),
                            placed[SHEEN_ROUGHNESS_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).a
                    if layered.iridescence_map != NO_TEXTURE:
                        film_factor = _sample_placed(
                            textures.get(layered.iridescence_map),
                            placed[IRIDESCENCE_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).r
                    if layered.thickness_map != NO_TEXTURE:
                        thickness_texel = _sample_placed(
                            textures.get(layered.thickness_map),
                            placed[IRIDESCENCE_THICKNESS_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).g
                        thickness_mapped = True
                    if layered.anisotropy_map != NO_TEXTURE:
                        var turn = _sample_placed(
                            textures.get(layered.anisotropy_map),
                            placed[ANISOTROPY_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        )
                        stretch_texel = Vector3(turn.r, turn.g, turn.b)
                    # The specular and coat maps, three.js's
                    # `lights_physical_fragment` and
                    # `clearcoat_normal_fragment_maps`: the specular
                    # color map's color, the specular intensity map's
                    # *alpha*, the clearcoat map's red, the clearcoat
                    # roughness map's green, and the coat's normal texel.
                    if layered.specular_color_map != NO_TEXTURE:
                        var tint = _sample_placed(
                            textures.get(layered.specular_color_map),
                            placed[SPECULAR_COLOR_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        )
                        specular_texel = Vector3(tint.r, tint.g, tint.b)
                    if layered.specular_intensity_map != NO_TEXTURE:
                        specular_alpha = _sample_placed(
                            textures.get(layered.specular_intensity_map),
                            placed[SPECULAR_INTENSITY_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).a
                    if layered.clearcoat_map != NO_TEXTURE:
                        coat_factor = _sample_placed(
                            textures.get(layered.clearcoat_map),
                            placed[CLEARCOAT_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).r
                    if layered.clearcoat_roughness_map != NO_TEXTURE:
                        coat_rough_factor = _sample_placed(
                            textures.get(layered.clearcoat_roughness_map),
                            placed[CLEARCOAT_ROUGHNESS_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).g
                    if layered.clearcoat_normal_map != NO_TEXTURE:
                        coat_texel = _sample_placed(
                            textures.get(layered.clearcoat_normal_map),
                            placed[CLEARCOAT_NORMAL_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        )
                        coat_mapped = True
                    # The transmission map's red and the thickness map's
                    # green, three.js's `transmission_fragment`.
                    if a.transmission_map != NO_TEXTURE:
                        transmission_factor = _sample_placed(
                            textures.get(a.transmission_map),
                            placed[TRANSMISSION_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).r
                    if a.thickness_map != NO_TEXTURE:
                        thickness_factor = _sample_placed(
                            textures.get(a.thickness_map),
                            placed[THICKNESS_MAP_SLOT],
                            uv,
                            uv1,
                            a,
                            b,
                            c,
                            coverage,
                            x,
                            y,
                        ).g
            # The node graph's color, opacity and emissive, once the maps
            # have had their say, which the graph replaces: three.js's
            # `colorNode` is the diffuse color the lights multiply, its
            # `opacityNode` the alpha the test reads, and its
            # `emissiveNode` the glow. The kernel does the same, here.
            if noded:
                var given = NodeInputs(
                    u,
                    v,
                    spot,
                    facing,
                    Vector3(base.r, base.g, base.b),
                    Vector3(0, 0, 0),
                    textured,
                )
                if has_output(nodes, COLOR_NODE):
                    var diffuse = run_nodes(nodes, COLOR_NODE, given)
                    shaded = FloatColor(
                        diffuse[0] * arriving.r,
                        diffuse[1] * arriving.g,
                        diffuse[2] * arriving.b,
                        shaded.a,
                    )
                if has_output(nodes, OPACITY_NODE):
                    shaded.a = run_nodes(nodes, OPACITY_NODE, given)[0]
                if has_output(nodes, EMISSIVE_NODE):
                    var given_off = run_nodes(nodes, EMISSIVE_NODE, given)
                    glow = FloatColor(
                        given_off[0], given_off[1], given_off[2], 1.0
                    )
                # Thrown away where the mask is zero, three.js's `maskNode`
                # and every `Discard`: before the alpha test, as three.js
                # discards it in `setupDiffuseColor`.
                if masked and run_nodes(nodes, MASK_NODE, given)[0] == 0:
                    continue
            # Thrown away for being too transparent, three.js's
            # `alphatest_fragment`: no color, and no depth either, so what
            # is behind this hole is drawn instead. Asked once the maps have
            # had their say over alpha and before anything is written.
            if tested and shaded.a < a.alpha_test:
                continue
            # Thrown away below a hashed threshold, three.js's
            # `alphahash_fragment`, from the world position here and at
            # the pixels beside it, as the kernel reads them.
            if hashed and shaded.a < hashed_threshold(nodes):
                continue
            # Not covering this sample, WebGL's alpha to coverage.
            if covered and not alpha_covers(shaded.a, x, y):
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
                    # A depth, packed by the material's packing, or a
                    # distance from the reference point, packed into four
                    # channels. A packed alpha is data too, and is kept.
                    var written: SIMD[DType.float32, 4]
                    if a.kind == DISTANCE:
                        written = packed_distance_fragment(
                            spot, a.reference, a.near_distance, a.far_distance
                        )
                    else:
                        written = packed_depth_fragment(
                            a.depth_packing, z, shaded.a
                        )
                    shaded = data_color(
                        written[0], written[1], written[2], written[3]
                    )
            elif catches:
                # The shadow and nothing else: the color where the lights
                # that cast are blocked, transparent where they reach,
                # three.js's `opacity * (1.0 - getShadowMask())`. Whether
                # this surface receives is not asked, because a shadow
                # material that received nothing would show nothing.
                shaded = FloatColor(
                    shaded.r,
                    shaded.g,
                    shaded.b,
                    shaded.a * (1 - lighting.shadow_mask(spot, facing)),
                )
            elif physical:
                # Lit here, once the map has multiplied the color: a metal
                # tints its lobe by that color, so the lobe cannot be
                # summed before the texel is known. `shaded` is the base
                # color times the map, three.js's `diffuseColor`, since a
                # physical surface's `arriving` is one. The reflectance
                # head on rides in `specular`, read from the first corner,
                # unless a specular map changes it: then it is worked out
                # again from the texels, as three.js works it out.
                var head_on = Vector3(a.specular.r, a.specular.g, a.specular.b)
                var intensity = a.specular_intensity
                if a.layers.is_specular_mapped():
                    intensity = a.specular_intensity * specular_alpha
                    head_on = specular_reflectance(
                        a.ior,
                        a.layers.specular_color,
                        intensity,
                        specular_texel,
                    )
                var surface = physical_surface(
                    Vector3(shaded.r, shaded.g, shaded.b),
                    head_on,
                    a.metalness * metal_factor,
                    intensity,
                )
                # How fast the normal before any map turns across the
                # pixel, in view space: three.js's `geometryRoughness`,
                # added to both roughnesses after the floor. The normal
                # one pixel right and one pixel up is worked out from the
                # triangle's own functions, as a footprint is.
                var bare = _normal_at(a, b, c, fragment)
                var curve = geometry_roughness(
                    view_direction(
                        _normal_at(a, b, c, _weights(coverage, x + 1, y))
                        - bare,
                        lighting.up,
                        lighting.back,
                    ),
                    view_direction(
                        _normal_at(a, b, c, _weights(coverage, x, y - 1))
                        - bare,
                        lighting.up,
                        lighting.back,
                    ),
                )
                var rough = floored_roughness(a.roughness * rough_factor, curve)
                # The coat times its map's red, and its roughness times its
                # map's green, before the floor, in three.js's order.
                var coat = clearcoat_of(a.clearcoat, coat_factor)
                var coat_rough = floored_roughness(
                    a.clearcoat_roughness * coat_rough_factor, curve
                )
                var toward_eye = toward_eye_at(
                    lighting.eye, lighting.toward_eye, spot
                )
                # The coat's own normal, three.js's `clearcoatNormal`: the
                # normal before any map, perturbed by the coat's normal
                # map along the frame three.js's `tbn2` builds from that
                # same normal. Its texel is unpacked, its x and y scaled,
                # and the sum normalized, in that order, by `mapped_normal`.
                var coat_normal = coat_facing
                if coated and coat_mapped:
                    var right = _weights(coverage, x + 1, y)
                    var up = _weights(coverage, x, y - 1)
                    var coat_placed = placed[CLEARCOAT_NORMAL_MAP_SLOT]
                    var steps = _placed_steps(
                        a,
                        b,
                        c,
                        coat_placed,
                        coat_placed.place(uv, uv1),
                        right,
                        up,
                    )
                    coat_normal = mapped_normal(
                        coat_facing,
                        _world_at(a, b, c, right) - spot,
                        _world_at(a, b, c, up) - spot,
                        steps[0],
                        steps[1],
                        coat_texel,
                        a.layers.clearcoat_normal_scale,
                    )
                # The tangent frame an anisotropic lobe is stretched along,
                # three.js's `tbn`, from the normal before any map and the
                # changes one pixel right and one pixel up, as a normal map
                # measures them. Coordinates are read whatever the mode:
                # the stretch is a number, not a texture. They are the
                # normal map's, else the coat's normal map's, else the
                # raw first pair, as three.js picks `vNormalMapUv`,
                # `vClearcoatNormalMapUv` or `vUv`. A mode that opens no
                # map places none of them.
                var frame = TangentFrame(Vector3(0, 0, 0), Vector3(0, 0, 0))
                if a.layers.is_anisotropic():
                    var right = _weights(coverage, x + 1, y)
                    var up = _weights(coverage, x, y - 1)
                    var framed = UvPlacement()
                    if a.normal_map != NO_TEXTURE:
                        framed = placed[NORMAL_MAP_SLOT]
                    elif a.layers.clearcoat_normal_map != NO_TEXTURE:
                        framed = placed[CLEARCOAT_NORMAL_MAP_SLOT]
                    var steps = _placed_steps(
                        a,
                        b,
                        c,
                        framed,
                        framed.moved(
                            _coordinates_at(
                                a,
                                b,
                                c,
                                fragment,
                                framed.channel == UV_CHANNEL_1,
                            )
                        ),
                        right,
                        up,
                    )
                    frame = tangent_frame(
                        coat_facing,
                        _world_at(a, b, c, right) - spot,
                        _world_at(a, b, c, up) - spot,
                        steps[0],
                        steps[1],
                    )
                # The sheen, the film and the stretch, from the material's
                # numbers times their maps; see `lights.physical_layers`.
                ref layered = a.layers
                var layers = layers_of(
                    Vector3(
                        layered.sheen_color.x * sheen_tint.x,
                        layered.sheen_color.y * sheen_tint.y,
                        layered.sheen_color.z * sheen_tint.z,
                    ),
                    sheen_roughness_of(layered.sheen_roughness, sheen_alpha),
                    layered.iridescence * film_factor,
                    layered.iridescence_ior,
                    iridescence_thickness(
                        layered.thickness_minimum,
                        layered.thickness_maximum,
                        thickness_texel,
                        thickness_mapped,
                    ),
                    layered.anisotropy,
                    stretch_texel,
                    frame.tangent,
                    frame.bitangent,
                    facing,
                    toward_eye,
                    surface.specular,
                    rough,
                )
                var direct = lighting.physical_at(
                    facing,
                    coat_normal,
                    spot,
                    surface,
                    rough,
                    coat,
                    coat_rough,
                    a.receives_shadow,
                    layers,
                )
                # The light map's light joins the indirect light here, as
                # three.js adds it to `irradiance`; zero adds nothing.
                var around = lighting.indirect_at(facing)
                var indirect = Vector3(
                    around.r + baked.x, around.g + baked.y, around.b + baked.z
                )
                var dot_nv = max(
                    Float32(0), min(Float32(1), facing.dot(toward_eye))
                )
                var dot_nv_coat = max(
                    Float32(0), min(Float32(1), coat_normal.dot(toward_eye))
                )
                # The environment along the rough reflection and around
                # the normal, three.js's `getIBLRadiance` and
                # `getIBLIrradiance`, each read at a roughness: the
                # irradiance at one, as three.js reads it. A prefiltered
                # cube reads its PMREM; any other reads down its chain.
                # See `CubeTexture.sample_rough`.
                var radiance = Vector3(0, 0, 0)
                var irradiance = Vector3(0, 0, 0)
                var coat_radiance = Vector3(0, 0, 0)
                if reflects:
                    ref cube = cubes.get(a.env_map)
                    # Every direction is turned by the env map's rotation
                    # before it is read, three.js's `envMapRotation`.
                    ref spin = a.frames.env_rotation
                    # An anisotropic surface reads along its bent normal,
                    # three.js's `getIBLAnisotropyRadiance`.
                    var seen = cube.sample_rough(
                        spin.turn(
                            rough_reflection(
                                toward_eye,
                                bent_normal(facing, toward_eye, layers, rough),
                                rough,
                            )
                        ),
                        rough,
                    )
                    var around = cube.sample_rough(spin.turn(facing), 1)
                    var strength = a.env_map_intensity
                    radiance = Vector3(
                        seen.r * strength, seen.g * strength, seen.b * strength
                    )
                    irradiance = Vector3(
                        around.r * strength,
                        around.g * strength,
                        around.b * strength,
                    )
                    if coated:
                        var gloss = cube.sample_rough(
                            spin.turn(
                                rough_reflection(
                                    toward_eye, coat_normal, coat_rough
                                )
                            ),
                            coat_rough,
                        )
                        coat_radiance = Vector3(
                            gloss.r * strength,
                            gloss.g * strength,
                            gloss.b * strength,
                        )
                # The opaque scene through the surface, three.js's
                # `transmission_fragment`, seen from where the camera
                # stands under either projection, as three.js measures its
                # `v` from `cameraPosition`.
                var through = Float32(0)
                var transmitted = Vector3(0, 0, 0)
                var thinned = Float32(1)
                if transmits:
                    through = a.transmission * transmission_factor
                    var seen = host_refraction(
                        transmission,
                        facing,
                        toward_eye_at(lighting.eye, PERSPECTIVE_VIEW, spot),
                        rough,
                        surface.diffuse,
                        surface.specular,
                        surface.clearcoat.x,
                        spot,
                        a.thickness * thickness_factor,
                        a.dispersion,
                        a.ior,
                        Vector3(
                            a.attenuation_color.r,
                            a.attenuation_color.g,
                            a.attenuation_color.b,
                        ),
                        a.attenuation_distance,
                    )
                    transmitted = Vector3(seen.r, seen.g, seen.b)
                    thinned = transmission_alpha(seen.a, through)
                var outgoing = physical_outgoing(
                    direct,
                    indirect,
                    surface,
                    rough,
                    dot_nv,
                    reflects,
                    radiance,
                    irradiance,
                    Vector3(glow.r, glow.g, glow.b),
                    coat,
                    coat_rough,
                    Vector3(dot_nv_coat, 0, 0),
                    coat_radiance,
                    occlusion,
                    through,
                    transmitted,
                    layers=layers,
                )
                shaded = FloatColor(
                    outgoing.x, outgoing.y, outgoing.z, shaded.a * thinned
                )
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
                # Then the reflection, joined to the finished light by the
                # material's combine, exactly where three.js's
                # `envmap_fragment` joins it: after the emissive term and
                # before the fog. The direction is the camera's view
                # turned back through the normal, and `envmap_fragment`
                # *does* special-case a parallel projection where the
                # matcap above does not: under `isOrthographic` it takes
                # the view's third column and only otherwise the way to
                # `cameraPosition`. That is what `lighting.toward_eye`
                # holds, so a reflection under a parallel projection stops
                # swimming as the camera slides along its own axis. Read
                # at the cube's full size; see `render.cube_texture`.
                # A refraction mapping bends the view through the surface
                # instead, by the material's `refractionRatio`; either way
                # the direction is turned by `envMapRotation` last.
                if reflects:
                    ref cube = cubes.get(a.env_map)
                    var bounce = env_direction(
                        toward_eye_at(lighting.eye, lighting.toward_eye, spot),
                        facing,
                        cube.mapping.refracts(),
                        a.frames,
                    )
                    shaded = combine_light(
                        shaded,
                        cube.sample(bounce),
                        a.reflectivity * specular_strength,
                        a.combine,
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
            # The node graph's output last, reading the finished light,
            # fog and all, as three.js's `outputNode` reads `output`.
            # Alpha is coverage and stays what the fragment said.
            if noded and has_output(nodes, OUTPUT_NODE):
                var finished = run_nodes(
                    nodes,
                    OUTPUT_NODE,
                    NodeInputs(
                        u,
                        v,
                        spot,
                        facing,
                        Vector3(base.r, base.g, base.b),
                        Vector3(shaded.r, shaded.g, shaded.b),
                        textured,
                    ),
                )
                shaded = FloatColor(
                    finished[0], finished[1], finished[2], shaded.a
                )
            # Dithered last, three.js's `dithering_fragment`; see
            # `render.fragment_flags.dither`.
            if dithered:
                shaded = dither(shaded, x, y, target.height)
            # The stencil and the depth the tests asked for, written now
            # that the fragment has survived. One that failed its tests
            # was shaded only to learn that, and is drawn no further.
            target.keep_stencil(x, y, test)
            if not test.passes:
                continue
            if writes_depth:
                target.claim_depth(x, y, stored_z)
            if not a.state.color_write:
                continue
            if blended:
                target.blend(
                    x,
                    y,
                    shaded,
                    a.blend.value,
                    a.state.premultiplied_alpha,
                    a.state.blend_constant(),
                )
            else:
                # An opaque fragment is written with an alpha of one, as
                # three.js's `opaque_fragment` writes it: the material's
                # opacity and its maps' alpha have had their say through
                # the alpha test, and a surface that does not blend hides
                # everything behind it. A depth material keeps its opacity
                # as its alpha, as three.js's `MeshDepthMaterial` writes it.
                # A distance material, and a packed depth, write their
                # alpha as data.
                if a.kind != DEPTH and a.kind != DISTANCE:
                    shaded.a = 1
                target.write(
                    x,
                    y,
                    shaded,
                    untoned,
                    _kept_normal(facing, a.kind, lighting, keeps_normals),
                )
        row = row + down


struct _HostNodes[origin: Origin[mut=False]](NodeSource):
    """The host's `NodeSource`: a program in its store, and one triangle's
    own footprint for the textures it reads, as `_sample_map` reads the
    material's map. `x` and `y` move with the fragment."""

    var programs: Pointer[NodeProgramStore, Self.origin]
    var program: Int
    var textures: Pointer[TextureStore, Self.origin]
    var a: Pointer[RasterVertex, Self.origin]
    var b: Pointer[RasterVertex, Self.origin]
    var c: Pointer[RasterVertex, Self.origin]
    var coverage: _Coverage
    var x: Int
    var y: Int
    # The target's height, and the fragment's depth in normalized device
    # space, for `frag_coord`.
    var height: Int
    var depth: Float32

    def __init__(
        out self,
        programs: Pointer[NodeProgramStore, Self.origin],
        program: Int,
        textures: Pointer[TextureStore, Self.origin],
        a: Pointer[RasterVertex, Self.origin],
        b: Pointer[RasterVertex, Self.origin],
        c: Pointer[RasterVertex, Self.origin],
        coverage: _Coverage,
        height: Int,
    ):
        """Borrow a program and a triangle on a target `height` pixels
        high, at the pixel (0, 0)."""
        self.programs = programs
        self.program = program
        self.textures = textures
        self.a = a
        self.b = b
        self.c = c
        self.coverage = coverage
        self.x = 0
        self.y = 0
        self.height = height
        self.depth = 0

    def word(self, at: Int) -> Float32:
        """Return one float of the program."""
        return self.programs[].programs[self.program].code[at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return a texture read at (u, v) for this fragment, as
        `_sample_map` reads the material's map."""
        return _sample_map(
            self.textures[].textures[slot],
            u,
            v,
            self.a[],
            self.b[],
            self.c[],
            self.coverage,
            self.x,
            self.y,
        )

    def shares(self, context: NodeContext) -> SIMD[DType.float32, 4]:
        """Return each corner's perspective-correct weight at this pixel,
        or at the pixel to its right or above it, from the triangle's own
        edge functions, as `_sample_map` measures a footprint."""
        var x = self.x + (1 if context == AT_RIGHT else 0)
        var y = self.y - (1 if context == AT_UP else 0)
        var weights = _weights(self.coverage, x, y)
        return perspective_shares(
            weights.wa,
            weights.wb,
            weights.wc,
            self.a[].inv_w,
            self.b[].inv_w,
            self.c[].inv_w,
        )

    def frag_coord(self, context: NodeContext) -> SIMD[DType.float32, 4]:
        """Return where the fragment is, GLSL's `gl_FragCoord`: the pixel's
        center, or its neighbor's for a derivative, in pixels from the
        bottom left; the fragment's depth from zero to one; and one.

        Args:
            context: Which sample.

        Returns:
            The four numbers.
        """
        var x = self.x + (1 if context == AT_RIGHT else 0)
        var y = self.y - (1 if context == AT_UP else 0)
        return SIMD[DType.float32, 4](
            Float32(x) + 0.5,
            Float32(self.height - y) - 0.5,
            self.depth * 0.5 + 0.5,
            1,
        )

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return one corner's coordinates, world position, normal and
        color."""
        ref at = self.a[] if context == CORNER_A else (
            self.b[] if context == CORNER_B else self.c[]
        )
        return NodeInputs(
            at.u,
            at.v,
            at.world,
            at.normal,
            Vector3(at.color.r, at.color.g, at.color.b),
            Vector3(0, 0, 0),
            False,
        )


# --- lines ------------------------------------------------------------------


def check_line_state(a: RasterVertex, b: RasterVertex) raises:
    """Refuse a segment whose two ends disagree, or whose material is lit.

    The same argument as `check_triangle_state`: per-segment metadata is
    carried on every corner and the first is read, so the two have to
    agree or the answer depends on which one is asked.

    A line is unlit. three.js's `LineBasicMaterial` catches no light
    either, and it cannot: a line has no surface, so it has no normal, and
    every lighting term here needs one. A lit material on a line would be
    shaded by whatever its corners happened to carry, which is nothing.

    The dashes are per-segment metadata too, and are checked the same
    way, and for being a length at all: a negative dash or gap is not a
    dash, and one that is not finite folds every distance to nothing.

    Args:
        a: One end.
        b: The other.

    Raises:
        Error: If the blend policies differ, if either is not a named
            policy, if the kinds differ, if the kind is not unlit, if the
            dash or the gap differ between the ends, if either is
            negative or not finite, or if the ends disagree about their
            depth, color or stencil state or it is refused by
            `RasterState.check`, or if they disagree about the fog, or if
            either end names a node program.
    """
    if not a.blend.is_valid():
        raise Error("A line needs a blend policy that exists")
    if a.blend != b.blend:
        raise Error("A line's ends must agree about blending")
    if not a.kind.is_valid():
        raise Error("A line needs a material kind that exists")
    if a.kind != b.kind:
        raise Error("A line's ends must agree about the material")
    if not a.kind.is_unlit():
        raise Error("A line's material must be unlit")
    if a.nodes != NO_NODES or b.nodes != NO_NODES:
        raise Error(
            "A line runs no node graph: it has no surface for one to shade"
        )
    # The first end is checked before the two are compared: a dash that
    # is not a number agrees with nothing, itself included.
    if not isfinite(a.dash_size) or a.dash_size < 0:
        raise Error("A dash size cannot be negative")
    if not isfinite(a.gap_size) or a.gap_size < 0:
        raise Error("A gap size cannot be negative")
    if a.dash_size != b.dash_size or a.gap_size != b.gap_size:
        raise Error("A line's ends must agree about the dashes")
    if a.state != b.state:
        raise Error(
            "A line's ends must agree about their depth, color or stencil state"
        )
    a.state.check()
    if a.fog != b.fog:
        raise Error("A line's ends must agree about the fog")


def rasterize_line(
    a: RasterVertex,
    b: RasterVertex,
    mut target: RenderTarget,
    first_row: Int = 0,
    last_row: Int = -1,
    fog: FogView = FogView.none(),
    line_width: Int = 1,
) raises:
    """Draw one segment, `line_width` raster pixels wide, into `target`.

    `render.linerule` decides which pixels, and the kernel asks it the same
    question, so the two staircases are the same staircase.

    What varies along a line is its color, its fog depth and its distance
    along itself, and all three are interpolated with the perspective
    correction a triangle's varyings get: weight by `inv_w`, divide by the
    interpolated `inv_w`. Depth is not corrected, for the reason it is not
    corrected across a triangle -- the projection already made it linear
    in screen space.

    A dashed line throws a pixel in a gap away before the depth is
    tested, as three.js's `discard` does, so a gap claims no depth and
    what is behind it shows through.

    Args:
        a: One end.
        b: The other.
        target: The linear render target to draw into.
        first_row: The first row this call owns. Below zero is the top.
        last_row: The last row it owns. Below zero, or past the last row,
            is the rest of the image.
        fog: The scene's fog, seen through the camera.
        line_width: How many raster pixels across the line is, the
            renderer's render scale. One, the default, is the one-pixel
            line and the rule this drew before there was a width. See
            `render.linerule`.

    Raises:
        Error: If the segment's metadata is refused by `check_line_state`,
            or the fog view is refused by `FogView.validate`.
    """
    check_line_state(a, b)
    # The rows this call owns, held inside the image. Clamped here rather
    # than tested per pixel: once the range is known to be inside, a pixel
    # inside the range is inside the image, and the loop below has only its
    # columns left to check.
    var bottom = last_row
    if bottom < 0 or bottom >= target.height:
        bottom = target.height - 1
    var top = first_row
    if top < 0:
        top = 0
    var first = Vector2(a.x, a.y)
    var second = Vector2(b.x, b.y)
    var steps = span_of(first, second)
    var horizontal = major_is_x(first, second)
    var fogged = fog.is_on() and a.fog
    # Whether a pixel that passes writes its depth; see `rasterize_shaded`.
    var writes_depth = a.state.writes_depth()
    # Which steps can land on the target at all, worked out before the
    # walk rather than discovered inside it. A projection can put an
    # endpoint a very long way off the image -- a segment from x = -1e6 to
    # x = 1e6 spans two million columns and lights eight of them -- and a
    # walk that visits every step to reject all but eight is the line
    # counterpart of rasterizing a triangle over the whole image.
    #
    # The endpoints themselves are untouched, so `share_at` and `other_at`
    # still answer about the original segment. Only which of their answers
    # are asked for changes, which is why this cannot move a pixel.
    var start = major_at(first, second, 0)
    var forward = second.y >= first.y
    if horizontal:
        forward = second.x >= first.x
    var lowest = 0
    var highest = target.width - 1
    if not horizontal:
        lowest = top
        highest = bottom
    var from_step: Int
    var past_step: Int
    if forward:
        from_step = max(0, lowest - start)
        past_step = min(steps, highest - start + 1)
    else:
        from_step = max(0, start - highest)
        past_step = min(steps, start - lowest + 1)
    # Clamped with `max` rather than an `if`: every caller passes a render
    # scale, which is one or more, so the guard has no reachable second
    # side and an `if` would be a branch no test could take.
    var width = max(1, line_width)
    for step in range(from_step, past_step):
        var major = major_at(first, second, step)
        var first_minor = first_other_at(first, second, major, width)
        # Held inside the segment: a pixel at either end can sit a hair
        # beyond it once the major coordinate is taken at a pixel center.
        var share = share_at(first, second, major)
        if share < 0:
            share = 0
        if share > 1:
            share = 1
        var near = a.inv_w * (1 - share)
        var far = b.inv_w * share
        var total = near + far
        if total == 0:
            continue
        # The depth the buffer tests and keeps, from the interpolated
        # `1 / w` as a triangle's is; see `rasterize_shaded`.
        var stored_z = fragment_depth(a.state, a.z + (b.z - a.z) * share, total)
        var toward = far / total
        # The gap test comes before the depth test, as a discard does: a
        # pixel in a gap is not drawn and claims nothing.
        var along = (
            a.line_distance + (b.line_distance - a.line_distance) * toward
        )
        if not dash_covers(along, a.dash_size, a.gap_size):
            continue
        # Straight, as a varying is everywhere else in this file and
        # as the kernel's line pass does it. `mix_color` premultiplies,
        # which is a filtering rule and not an interpolation rule; see
        # `render.texture.mix_straight`.
        var color = mix_straight(a.color, b.color, toward)
        if fogged:
            var depth = a.view_depth + (b.view_depth - a.view_depth) * toward
            color = fog_mix(color, fog.color, fog.factor_at(depth))
        # Everything above this line belongs to the step and not to the
        # pixel: the share, the depth, the dash and the color are the same
        # across the run, because the run is one place on the line drawn
        # at more than one pixel. Only the depth test and the write are
        # per pixel. Both loops run at least once.
        for offset in range(width):  # pragma: no branch
            var minor = first_minor + offset
            var x = major
            var y = minor
            if not horizontal:
                x = minor
                y = major
            # The minor axis only. The major one was bounded before the
            # walk, so a step that reaches here is on the target along it.
            if y < top or y > bottom:
                continue
            if x < 0 or x >= target.width:
                continue
            # Not covering this sample, WebGL's alpha to coverage, which
            # comes before the stencil and the depth tests.
            if a.state.alpha_to_coverage and not alpha_covers(color.a, x, y):
                continue
            # The stencil and the depth tests, settled at once: a line
            # has no alpha test to discard it later.
            var test = target.test_fragment(x, y, stored_z, a.state)
            target.keep_stencil(x, y, test)
            if not test.passes:
                continue
            # A blended segment claims its depth as a blended triangle
            # does, three.js's `depthWrite` on a transparent material. The
            # kernel claims it at the same step, so a later segment behind
            # it at a shared pixel is dropped on both backends.
            if writes_depth:
                target.claim_depth(x, y, stored_z)
            if not a.state.color_write:
                continue
            # Dithered, three.js's `dithering_fragment`, at this pixel.
            var drawn = color
            if a.state.dithering:
                drawn = dither(color, x, y, target.height)
            if a.blend.mixes():
                target.blend(
                    x,
                    y,
                    drawn,
                    a.blend.value,
                    a.state.premultiplied_alpha,
                    a.state.blend_constant(),
                )
            else:
                # Opaque, so written with an alpha of one, as a triangle
                # is.
                drawn.a = 1
                target.write(x, y, drawn, not a.state.tone_mapped)


# --- points -----------------------------------------------------------------


def check_point_state(point: RasterVertex) raises:
    """Refuse a point whose material is lit, whose size is not a size, or
    whose metadata holds a value neither backend knows.

    A point is one corner, so there is no agreement to check, only the
    values. It is unlit, as a line is and for the same reason: it has no
    surface, so it has no normal for a light to reach. three.js's
    `PointsMaterial` catches no light either.

    Args:
        point: The point.

    Raises:
        Error: If the blend policy is not a named one, the kind is not a
            named one or is not unlit, the size is not finite or not above
            zero, the alpha test is outside zero to one or not finite, or
            a texture id is a negative other than `NO_TEXTURE`, or the
            depth, color and stencil state is refused by
            `RasterState.check`, or the point names a node program.
    """
    if not point.blend.is_valid():
        raise Error("A point needs a blend policy that exists")
    if not point.kind.is_valid():
        raise Error("A point needs a material kind that exists")
    if not point.kind.is_unlit():
        raise Error("A point's material must be unlit")
    if point.nodes != NO_NODES:
        raise Error(
            "A point runs no node graph: it has no surface for one to shade"
        )
    if not isfinite(point.point_size) or point.point_size <= 0:
        raise Error("A point needs a size above zero")
    if (
        not isfinite(point.alpha_test)
        or point.alpha_test < 0
        or point.alpha_test > 1
    ):
        raise Error("A point's alpha test must be between zero and one")
    if point.texture != NO_TEXTURE and point.texture.value < 0:
        raise Error("A point names a texture id that nothing can hold")
    if point.alpha_map != NO_TEXTURE and point.alpha_map.value < 0:
        raise Error("A point names an alpha map id that nothing can hold")
    point.state.check()


def check_point_maps(
    point: RasterVertex, mode: ShadeMode, textures: TextureStore
) raises:
    """Refuse a point whose alpha map is not stored as data, under the mode
    that would read it.

    `check_triangle_maps` for a point, which carries a map and an alpha
    map and nothing else. Asked of every point before any band starts, as
    the triangles' is, so a point no band reaches is refused too.

    Args:
        point: The point.
        mode: What a pixel's color is taken from; only `SHADE_TEXTURE`
            opens the maps.
        textures: Where the maps live.

    Raises:
        Error: If an alpha map the mode would open is not in the store or
            is not stored as data -- see `check_alpha_map`.
    """
    if point.alpha_map != NO_TEXTURE and mode == SHADE_TEXTURE:
        check_alpha_map(textures.get(point.alpha_map))


def _sample_point_map(
    image: Texture, place: Vector2, level: Float32
) -> FloatColor:
    """Return `image` sampled at a point's own coordinate.

    Straight from the one level when the image has one, and otherwise from
    the level the point's size chooses, worked out once per point by
    `mip_level_of`. Mirrored on the device by `render.gpu._sample_level`.
    """
    if image.levels == 1:
        return image.sample(place.x, place.y)
    return image.sample_level(place.x, place.y, level)


def rasterize_point(
    point: RasterVertex,
    mut target: RenderTarget,
    mode: ShadeMode = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    first_row: Int = 0,
    last_row: Int = -1,
    fog: FogView = FogView.none(),
) raises:
    """Draw one point, a square of pixels, into `target`.

    `render.pointrule` decides which pixels, and the kernel asks it the
    same question, so the two squares are the same square.

    Nothing varies across a point but its coordinate: one color, one
    depth, one fog depth, as three.js's `gl_PointSize` square has. The
    coordinate samples the map and the alpha map, as a triangle's does,
    and the uv view shows it. The blend, the alpha test and the fog work
    exactly as they do on a triangle, and in the same order.

    Args:
        point: The point.
        target: The linear render target to draw into.
        mode: `SHADE_LIT` to write the color, `SHADE_UV` to write the
            point's own coordinate as red and green, or `SHADE_TEXTURE` to
            multiply the color by the maps.
        textures: Where `SHADE_TEXTURE` looks the point's maps up.
        first_row: The first row this call owns. Below zero is the top.
        last_row: The last row it owns. Below zero, or past the last row,
            is the rest of the image.
        fog: The scene's fog, seen through the camera.

    Raises:
        Error: If the mode is none of the three, the point is refused by
            `check_point_state` or its maps by `check_point_maps`, the fog
            view is refused by `FogView.validate`, or the point names a
            texture the store does not have.
    """
    if not mode.is_valid():
        raise Error("A shading mode that is none of the three")
    check_point_state(point)
    fog.validate()
    check_point_maps(point, mode, textures)
    # Decided by the material and carried here, as a triangle's are; see
    # `rasterize_shaded` for what each changes.
    var blended = point.blend.mixes() and mode != SHADE_UV
    var fogged = fog.is_on() and mode != SHADE_UV and point.fog
    var tested = point.alpha_test > 0 and mode != SHADE_UV
    var covered = point.state.alpha_to_coverage and mode != SHADE_UV
    var may_discard = tested or covered
    var writes_depth = point.state.writes_depth()
    var sampled = mode == SHADE_TEXTURE
    var center = Vector2(point.x, point.y)
    var size = point.point_size
    # The rows this call owns, held inside the image, and the square held
    # inside both. The bounds only limit the walk, and are rounded outward:
    # `covers` is asked of every pixel between them, so a bound cannot
    # move one; see `render.pointrule.first_covered`.
    var bottom = last_row
    if bottom < 0 or bottom >= target.height:
        bottom = target.height - 1
    var top = first_row
    if top < 0:
        top = 0
    var left = max(first_covered(center.x, size), 0)
    var right = min(last_covered(center.x, size), target.width - 1)
    var above = max(first_covered(center.y, size), top)
    var below = min(last_covered(center.y, size), bottom)
    # Which level of each map the point reads, once: a point's footprint
    # in its map is the same at every pixel of it.
    var level = Float32(0)
    if sampled and point.texture != NO_TEXTURE:
        ref image = textures.get(point.texture)
        level = mip_level_of(size, image.width, image.height)
    # The depth the buffer tests and keeps, the same at every pixel of
    # the square; see `render.raster_state.fragment_depth`.
    var stored_z = fragment_depth(point.state, point.z, point.inv_w)
    var mask_level = Float32(0)
    if sampled and point.alpha_map != NO_TEXTURE:
        ref mask = textures.get(point.alpha_map)
        mask_level = mip_level_of(size, mask.width, mask.height)
    for y in range(above, below + 1):
        for x in range(left, right + 1):
            if not point_covers(center, size, x, y):
                continue
            # Tested and settled as a triangle's fragment is; see
            # `rasterize_shaded`.
            var test = target.test_fragment(x, y, stored_z, point.state)
            if not shades(test, may_discard):
                target.keep_stencil(x, y, test)
                continue
            var shaded = point.color
            if mode != SHADE_LIT:
                var place = point_coord(center, size, x, y)
                if mode == SHADE_UV:
                    # Coordinates, not light, as the uv view of a triangle
                    # writes them; see `data_color`. Never alpha tested,
                    # so the point passed.
                    target.keep_stencil(x, y, test)
                    if writes_depth:
                        target.claim_depth(x, y, stored_z)
                    if point.state.color_write:
                        target.write(
                            x, y, data_color(place.x, place.y, 0.0, 1.0), True
                        )
                    continue
                if point.texture != NO_TEXTURE:
                    var texel = _sample_point_map(
                        textures.get(point.texture), place, level
                    )
                    shaded = FloatColor(
                        shaded.r * texel.r,
                        shaded.g * texel.g,
                        shaded.b * texel.b,
                        shaded.a * texel.a,
                    )
                # The alpha map's green channel thins the point, as it
                # thins a triangle.
                if point.alpha_map != NO_TEXTURE:
                    var thinning = _sample_point_map(
                        textures.get(point.alpha_map), place, mask_level
                    )
                    shaded = FloatColor(
                        shaded.r, shaded.g, shaded.b, shaded.a * thinning.g
                    )
            # Thrown away for being too transparent, claiming no depth, as
            # a triangle's fragment is.
            if tested and shaded.a < point.alpha_test:
                continue
            if covered and not alpha_covers(shaded.a, x, y):
                continue
            if fogged:
                shaded = fog_mix(
                    shaded, fog.color, fog.factor_at(point.view_depth)
                )
            target.keep_stencil(x, y, test)
            if not test.passes:
                continue
            if writes_depth:
                target.claim_depth(x, y, stored_z)
            if not point.state.color_write:
                continue
            if blended:
                target.blend(
                    x,
                    y,
                    shaded,
                    point.blend.value,
                    point.state.premultiplied_alpha,
                    point.state.blend_constant(),
                )
            else:
                # Opaque, so written with an alpha of one, as a triangle is.
                shaded.a = 1
                target.write(x, y, shaded, not point.state.tone_mapped)


# --- frames -----------------------------------------------------------------


@fieldwise_init
struct DrawKind(Equatable, ImplicitlyCopyable, Writable):
    """Which primitive a `Draw` runs over, as a type rather than an int.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `DrawKind(7)`, which `check_draws`
    refuses before anything is drawn. `value` is what crosses to the
    kernel.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `DRAW_TRIANGLES`, `DRAW_SEGMENTS` or
        `DRAW_POINTS`."""
        return (
            self == DRAW_TRIANGLES
            or self == DRAW_SEGMENTS
            or self == DRAW_POINTS
        )

    def stride(self) -> Int:
        """Return how many corners one primitive of this kind takes: three
        for a triangle, two for a segment, one for a point. Three for a
        kind that is none of them, which `check_draws` refuses before
        anything reads the answer."""
        if self == DRAW_SEGMENTS:
            return 2
        if self == DRAW_POINTS:
            return 1
        return 3


# A run of triangles, three corners each, out of a frame's corner list.
comptime DRAW_TRIANGLES = DrawKind(0)
# A run of segments, two corners each, out of a frame's segment list.
comptime DRAW_SEGMENTS = DrawKind(1)
# A run of points, one corner each, out of a frame's point list.
comptime DRAW_POINTS = DrawKind(2)


@fieldwise_init
struct Draw(ImplicitlyCopyable):
    """One run of primitives of one kind, drawn in one go.

    A frame is three lists, triangles, segments and points, and one order
    over all three: a list of these, each naming a run of one list. That is what lets a
    blended line be drawn after the blended surface behind it and before
    the one in front of it, which two lists drawn one after the other
    cannot. `Renderer.prepare_frame` writes the order once; both
    rasterizers walk it, so neither can put a primitive somewhere the other
    does not.
    """

    var kind: DrawKind
    # The first primitive of the run: a triangle, a segment or a point,
    # not a corner.
    var first: Int
    var count: Int


def check_draws(
    draws: List[Draw], triangles: Int, segments: Int, points: Int = 0
) raises:
    """Refuse a draw list that names what a frame does not hold.

    Shared by both backends, so neither can walk a run the other refuses:
    the kernel reads the corner buffers at whatever index a draw hands it,
    and an index past the end is an unchecked read of device memory.

    Args:
        draws: The order to draw in.
        triangles: How many triangles the frame's corner list holds.
        segments: How many segments its segment list holds.
        points: How many points its point list holds. None by default.

    Raises:
        Error: If a draw's kind is none of `DRAW_TRIANGLES`, `DRAW_SEGMENTS`
            and `DRAW_POINTS`, or its run starts before the first
            primitive, has a negative count, or reaches past the last
            primitive of its kind.
    """
    for index in range(len(draws)):
        ref draw = draws[index]
        if not draw.kind.is_valid():
            raise Error(
                "A draw needs a kind that exists: DRAW_TRIANGLES,"
                " DRAW_SEGMENTS or DRAW_POINTS"
            )
        var held = triangles
        if draw.kind == DRAW_SEGMENTS:
            held = segments
        if draw.kind == DRAW_POINTS:
            held = points
        if draw.first < 0 or draw.count < 0 or draw.first + draw.count > held:
            raise Error("A draw runs past the primitives the frame holds")


def _rows_of(
    corners: List[RasterVertex], stride: Int, pad: Int = 0
) -> List[Int]:
    """Return the first and last row each primitive can touch, in pairs.

    Worked out once for every band rather than once per band: most
    primitives miss most bands, and two integer compares say so; reading
    the corners to find out copied half a kilobyte per triangle per band,
    which was most of what a band did.

    Args:
        corners: The primitives' corners.
        stride: Corners per primitive: three for a triangle, two for a
            segment.
        pad: How many rows to widen the range by, each way. A segment more
            than one raster pixel wide reaches past its own endpoints by
            the width less one, and a band that skipped it on the strength
            of its corners alone would leave a gap across the seam between
            two workers. Zero, the default, is the range the corners give.

    Returns:
        Two entries per primitive, the first row then the last.
    """
    var rows = List[Int]()
    var count = len(corners) // stride
    rows.reserve(count * 2)
    for index in range(count):
        var top = corners[index * stride].y
        var bottom = top
        for corner in range(1, stride):  # pragma: no branch
            var y = corners[index * stride + corner].y
            top = min(top, y)
            bottom = max(bottom, y)
        rows.append(Int(floor(top)) - pad)
        rows.append(Int(ceil(bottom)) + pad)
    return rows^


def _point_rows(points: List[RasterVertex]) -> List[Int]:
    """Return the first and last row each point can touch, in pairs.

    `_rows_of` for points, whose rows come from the size rather than from
    a second corner: half the size above the center and half below.

    Args:
        points: The points.

    Returns:
        Two entries per point, the first row then the last.
    """
    var rows = List[Int]()
    rows.reserve(len(points) * 2)
    for index in range(len(points)):
        var half = points[index].point_size / 2
        rows.append(Int(floor(points[index].y - half)))
        rows.append(Int(ceil(points[index].y + half)))
    return rows^


async def _frame_band(
    corners: Pointer[RasterVertex, ImmutAnyOrigin],
    triangle_rows: MutPointer[Int, MutAnyOrigin],
    segments: Pointer[RasterVertex, ImmutAnyOrigin],
    segment_rows: MutPointer[Int, MutAnyOrigin],
    points: Pointer[RasterVertex, ImmutAnyOrigin],
    point_rows: MutPointer[Int, MutAnyOrigin],
    draws: Pointer[Draw, ImmutAnyOrigin],
    draw_count: Int,
    target: MutPointer[RenderTarget, MutAnyOrigin],
    mode: ShadeMode,
    textures: Pointer[TextureStore, ImmutAnyOrigin],
    lighting: Pointer[Lighting, ImmutAnyOrigin],
    errors: MutPointer[String, MutAnyOrigin],
    band: Int,
    first_row: Int,
    last_row: Int,
    fog: FogView,
    cubes: Pointer[CubeTextureStore, ImmutAnyOrigin],
    transmission: Pointer[TransmissionTarget, ImmutAnyOrigin],
    programs: Pointer[NodeProgramStore, ImmutAnyOrigin],
    line_width: Int = 1,
):
    """Draw a frame into one horizontal band of the target.

    One of these runs per worker, as a task on the standard library's
    thread pool. It takes pointers rather than references because a
    coroutine outlives the call that made it and must not borrow from it;
    `rasterize_frame` keeps everything alive until `TaskGroup.wait`
    returns.

    A band owns its rows outright, so the threads never touch the same
    pixel and the depth test needs no atomics -- the same argument the GPU
    kernel makes with one thread per pixel. Draw order within a band is
    the frame's order, exactly as on one thread, which is what keeps
    blending correct: the sort `Renderer.prepare_frame` did still holds
    row by row.

    The row pairs are from `_rows_of`: a primitive whose rows miss the
    band is skipped on two compares, without reading its corners.

    A task cannot raise, so an error is written into this band's slot and
    raised by `rasterize_frame` once every band has finished.
    """
    try:
        for index in range(draw_count):
            var draw = draws[unsafe_offset=index]
            var past = draw.first + draw.count
            if draw.kind == DRAW_TRIANGLES:
                for triangle in range(draw.first, past):
                    if (
                        triangle_rows[unsafe_offset=triangle * 2] > last_row
                        or triangle_rows[unsafe_offset=triangle * 2 + 1]
                        < first_row
                    ):
                        continue
                    rasterize_shaded(
                        corners[unsafe_offset=triangle * 3],
                        corners[unsafe_offset=triangle * 3 + 1],
                        corners[unsafe_offset=triangle * 3 + 2],
                        target[],
                        mode,
                        textures[],
                        lighting[],
                        first_row,
                        last_row,
                        fog,
                        cubes[],
                        transmission[],
                        programs[],
                    )
                continue
            if draw.kind == DRAW_POINTS:
                for point in range(draw.first, past):
                    if (
                        point_rows[unsafe_offset=point * 2] > last_row
                        or point_rows[unsafe_offset=point * 2 + 1] < first_row
                    ):
                        continue
                    rasterize_point(
                        points[unsafe_offset=point],
                        target[],
                        mode,
                        textures[],
                        first_row,
                        last_row,
                        fog,
                    )
                continue
            for segment in range(draw.first, past):
                if (
                    segment_rows[unsafe_offset=segment * 2] > last_row
                    or segment_rows[unsafe_offset=segment * 2 + 1] < first_row
                ):
                    continue
                rasterize_line(
                    segments[unsafe_offset=segment * 2],
                    segments[unsafe_offset=segment * 2 + 1],
                    target[],
                    first_row,
                    last_row,
                    fog,
                    line_width,
                )
    except e:
        errors[unsafe_offset=band] = String(e)


def _raise_band_errors(errors: List[String]) raises:
    """Raise the first error a band carried back, if one did.

    **`rasterize_frame` never gives a band an error to carry.** It refuses
    every input a band's three rasterizers refuse before any band starts:
    the mode, the fog, each triangle's state and maps, its transmission,
    each segment's and point's state and maps, and the draws. The one other
    error a band can meet is a pixel outside the target, and each
    rasterizer clamps its rows and columns to the target first. So this
    net catches only a check that a later change runs inside a band and
    not before. A task cannot raise, and without the net such an error
    would be dropped. The tests drive `_frame_band` itself with a segment
    the band refuses, which is how both halves of this are reached.

    Args:
        errors: One slot per band, empty where the band finished.

    Raises:
        Error: The first band's error, if any band has one.
    """
    for band in range(len(errors)):
        if errors[band] != "":
            raise Error(errors[band])


def rasterize_frame(
    corners: List[RasterVertex],
    segments: List[RasterVertex],
    draws: List[Draw],
    mut target: RenderTarget,
    mode: ShadeMode = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    lighting: Lighting = Lighting.uniform(),
    workers: Int = 1,
    fog: FogView = FogView.none(),
    points: List[RasterVertex] = List[RasterVertex](),
    cubes: CubeTextureStore = CubeTextureStore(),
    line_width: Int = 1,
    transmission: TransmissionTarget = TransmissionTarget(),
    programs: NodeProgramStore = NodeProgramStore(),
) raises:
    """Draw a frame -- triangles, segments and points, in one order --
    into `target`, on `workers` threads.

    `rasterize_shaded`, `rasterize_line` and `rasterize_point` for a whole
    frame. With one
    worker it is exactly the loop a caller would write: each draw in turn,
    each primitive of it in turn. With more, the image is cut into that
    many horizontal bands, each drawn by its own task on the standard
    library's thread pool, and every draw is offered to every band. The
    result is byte for byte what one thread produces -- a band owns its
    rows and draws in the same order -- so only the wall clock changes.
    More bands than rows collapse to one band per row.

    Everything is checked here, before any band starts, so malformed
    input is refused whether or not a primitive is visible and however
    many workers there are: a band skips a primitive its rows miss before
    the per-primitive rasterizer can look at it, and a single worker does
    not, so without this the same bad input raised on one thread and
    passed on four. A texture the store lacks is still found only when a
    fragment samples it -- `Renderer.prepare` refuses one long before here
    -- and that answer is the same on any number of workers, because some
    band covers whatever is visible.

    Threads rather than SIMD, first, because a band is the same code with a
    row range and needs no new arithmetic, and because the scene benchmark
    showed rasterization and the sRGB resolve were the frame.

    Args:
        corners: Raster vertices, three per triangle.
        segments: Raster vertices, two per segment.
        draws: The order to draw in; see `Draw`. A primitive no draw
            names is not drawn.
        target: The linear render target to draw into.
        mode: What a fragment's color comes from; see `rasterize_shaded`.
            A segment reads no mode.
        textures: Where `SHADE_TEXTURE` looks the triangles' maps up.
        lighting: The scene's lights, resolved to world space.
        workers: How many threads to draw with, at least one.
        fog: The scene's fog, seen through the camera; see
            `rasterize_shaded` and `rasterize_line`.
        points: Raster vertices, one per point. None by default.
        cubes: Where `SHADE_TEXTURE` looks the triangles' env maps up.
        line_width: How many raster pixels across every segment is, the
            renderer's render scale; see `rasterize_line` and
            `render.linerule`. One by default, the frame drawn at its own
            size.
        transmission: The opaque scene the transmissive triangles show
            through themselves, or an empty target when none transmits;
            see `render.transmission`.
        programs: Where the node materials' programs live; see
            `rasterize_shaded`.

    Raises:
        Error: If the corner count is not a multiple of three, the segment
            corner count is not a multiple of two, `workers` is less than
            one, the mode is none of the three, the fog view is refused by
            `FogView.validate`, any triangle's metadata is refused by
            `check_triangle_state` or its maps by `check_triangle_maps`,
            any segment's by `check_line_state`, any point's by
            `check_point_state` or its maps by `check_point_maps`, the
            draw list is refused by `check_draws`, or any primitive is
            refused as it is drawn -- on a worker that error is carried
            back and raised here.
    """
    if len(corners) % 3 != 0:
        raise Error("Rasterizing needs whole triangles")
    if len(segments) % 2 != 0:
        raise Error("Rasterizing needs whole segments")
    if workers < 1:
        raise Error("Rasterizing needs at least one worker")
    if not mode.is_valid():
        raise Error("A shading mode that is none of the three")
    # Refused here, before any band starts, for the reason the triangle
    # state is: whether or not a triangle is visible, and however many
    # workers there are.
    fog.validate()
    var triangles = len(corners) // 3
    var lines = len(segments) // 2
    for triangle in range(triangles):
        check_triangle_state(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
        )
        # And its maps, for the same reason: a band skips a triangle its
        # rows miss before `rasterize_shaded` can open them, so without
        # this a bad map on a triangle above the image was refused on one
        # worker and drawn around on four.
        check_triangle_maps(
            corners[triangle * 3], mode, textures, cubes, programs
        )
    for segment in range(lines):
        check_line_state(segments[segment * 2], segments[segment * 2 + 1])
    for point in range(len(points)):
        check_point_state(points[point])
        check_point_maps(points[point], mode, textures)
    check_draws(draws, triangles, lines, len(points))
    # Asked of the triangles a draw names rather than of the whole list:
    # the transmission pass draws the opaque runs of a frame that holds
    # transmissive triangles too, before there is a scene for them to
    # look through.
    var ready = transmission.is_ready()
    for index in range(len(draws)):
        ref draw = draws[index]
        if draw.kind != DRAW_TRIANGLES:
            continue
        for triangle in range(draw.first, draw.first + draw.count):
            check_transmission(corners[triangle * 3], mode, ready)

    var bands = min(workers, target.height)
    if bands == 1:
        for index in range(len(draws)):
            ref draw = draws[index]
            var past = draw.first + draw.count
            if draw.kind == DRAW_TRIANGLES:
                for triangle in range(draw.first, past):
                    rasterize_shaded(
                        corners[triangle * 3],
                        corners[triangle * 3 + 1],
                        corners[triangle * 3 + 2],
                        target,
                        mode,
                        textures,
                        lighting,
                        fog=fog,
                        cubes=cubes,
                        transmission=transmission,
                        programs=programs,
                    )
                continue
            if draw.kind == DRAW_POINTS:
                for point in range(draw.first, past):
                    rasterize_point(
                        points[point], target, mode, textures, fog=fog
                    )
                continue
            for segment in range(draw.first, past):
                rasterize_line(
                    segments[segment * 2],
                    segments[segment * 2 + 1],
                    target,
                    fog=fog,
                    line_width=line_width,
                )
        return

    # Every pointer below is to an argument or a local that outlives `wait`,
    # which is what makes handing it to a coroutine sound.
    var errors = List[String](length=bands, fill=String(""))
    var triangle_rows = _rows_of(corners, 3)
    var segment_rows = _rows_of(segments, 2, max(0, line_width - 1))
    var point_rows = _point_rows(points)
    var group = TaskGroup()
    # At least two bands past the early return above, so neither loop can
    # run zero times.
    for band in range(bands):  # pragma: no branch
        group.create_task(
            _frame_band(
                corners.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                triangle_rows.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                segments.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                segment_rows.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                points.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                point_rows.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                draws.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                len(draws),
                Pointer(to=target).unsafe_origin_cast[MutAnyOrigin](),
                mode,
                Pointer(to=textures).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=lighting).unsafe_origin_cast[ImmutAnyOrigin](),
                errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                band,
                band * target.height // bands,
                (band + 1) * target.height // bands - 1,
                fog,
                Pointer(to=cubes).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=transmission).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=programs).unsafe_origin_cast[ImmutAnyOrigin](),
                line_width,
            )
        )
    group.wait()
    # Mojo destroys a value after its last use, and the tasks read the row
    # pairs through pointers the compiler cannot see: these reads are what
    # keep the lists alive until every band has finished with them.
    _ = len(triangle_rows)
    _ = len(segment_rows)
    _ = len(point_rows)
    _raise_band_errors(errors)


def rasterize_all(
    corners: List[RasterVertex],
    mut target: RenderTarget,
    mode: ShadeMode = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    lighting: Lighting = Lighting.uniform(),
    workers: Int = 1,
    fog: FogView = FogView.none(),
    cubes: CubeTextureStore = CubeTextureStore(),
    transmission: TransmissionTarget = TransmissionTarget(),
    programs: NodeProgramStore = NodeProgramStore(),
) raises:
    """Draw every triangle in `corners` into `target`, on `workers` threads.

    `rasterize_frame` for a frame of triangles alone, in submission order:
    one draw over the whole list and no segments.

    Args:
        corners: Raster vertices, three per triangle.
        target: The linear render target to draw into.
        mode: What a fragment's color comes from; see `rasterize_shaded`.
        textures: Where `SHADE_TEXTURE` looks the triangles' maps up.
        lighting: The scene's lights, resolved to world space.
        workers: How many threads to draw with, at least one.
        fog: The scene's fog, seen through the camera; see
            `rasterize_shaded`.
        cubes: Where `SHADE_TEXTURE` looks the triangles' env maps up.
        transmission: The opaque scene the transmissive triangles show
            through themselves, or an empty target when none transmits.
        programs: Where the node materials' programs live.

    Raises:
        Error: Everything `rasterize_frame` raises of the triangles: a
            corner count that is not a multiple of three, `workers` less
            than one, a mode that is none of the three, a fog view that
            `FogView.validate` refuses, a triangle that
            `check_triangle_state` or `check_triangle_maps` refuses, or one
            refused as it is drawn.
    """
    var draws: List[Draw] = [Draw(DRAW_TRIANGLES, 0, len(corners) // 3)]
    rasterize_frame(
        corners,
        List[RasterVertex](),
        draws,
        target,
        mode,
        textures,
        lighting,
        workers,
        fog,
        cubes=cubes,
        transmission=transmission,
        programs=programs,
    )


def rasterize_lines_all(
    corners: List[RasterVertex],
    mut target: RenderTarget,
    workers: Int = 1,
    fog: FogView = FogView.none(),
) raises:
    """Draw every segment in `corners` into `target`, on `workers` threads.

    `rasterize_frame` for a frame of segments alone, in submission order:
    one draw over the whole list and no triangles. A segment reads no
    shading mode, no texture and no light.

    Args:
        corners: Raster vertices, two per segment.
        target: The linear render target to draw into.
        workers: How many threads to draw with, at least one.
        fog: The scene's fog, seen through the camera.

    Raises:
        Error: Everything `rasterize_frame` raises of the segments: an odd
            corner count, `workers` less than one, a fog view that
            `FogView.validate` refuses, or a segment that
            `check_line_state` refuses.
    """
    var draws: List[Draw] = [Draw(DRAW_SEGMENTS, 0, len(corners) // 2)]
    rasterize_frame(
        List[RasterVertex](),
        corners,
        draws,
        target,
        workers=workers,
        fog=fog,
    )


def rasterize_points_all(
    points: List[RasterVertex],
    mut target: RenderTarget,
    mode: ShadeMode = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    workers: Int = 1,
    fog: FogView = FogView.none(),
) raises:
    """Draw every point in `points` into `target`, on `workers` threads.

    `rasterize_frame` for a frame of points alone, in submission order:
    one draw over the whole list and no triangles or segments. A point
    reads no light.

    Args:
        points: Raster vertices, one per point.
        target: The linear render target to draw into.
        mode: What a pixel's color comes from; see `rasterize_point`.
        textures: Where `SHADE_TEXTURE` looks the points' maps up.
        workers: How many threads to draw with, at least one.
        fog: The scene's fog, seen through the camera.

    Raises:
        Error: Everything `rasterize_frame` raises of the points:
            `workers` less than one, a mode that is none of the three, a
            fog view that `FogView.validate` refuses, or a point that
            `check_point_state` or `check_point_maps` refuses.
    """
    var draws: List[Draw] = [Draw(DRAW_POINTS, 0, len(points))]
    rasterize_frame(
        List[RasterVertex](),
        List[RasterVertex](),
        draws,
        target,
        mode,
        textures,
        workers=workers,
        fog=fog,
        points=points,
    )
