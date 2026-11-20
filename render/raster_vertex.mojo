# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Subpixel coverage, slim corners, surface records and shading modes.

Shared by `render.rasterizer` and `render.gpu`, and re-exported by
`render.rasterizer` so all existing import paths continue to resolve.
"""

from core.ordinal import (
    ordinal_valid,
    require_index_in_count,
    require_valid,
)

from math.scaled_products import (
    _Scaled,
    _sum_products as _scaled_products,
    _common_scale,
)

from math.cross import cross_vectors
from math.norm import length2, _ordinary_squared
from math.vector2 import Vector2, weighted_sum2
from math.utils import clamp, max3, min3, mix_delta
from math.vector3 import Vector3, weighted_sum3
from render.framebuffer import Color, FloatColor, Framebuffer
from units.si import Length, METER
from materials.material import (
    BLEND,
    DEFAULT_IOR,
    DEPTH,
    MAX_IOR,
    MIN_IOR,
    DISTANCE,
    GOURAUD,
    VOLUME,
    DEFAULT_STEPS,
    check_steps,
    require_dash_size,
    require_gap_size,
    require_unmixed_data,
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
from render.volume_texture_store import (
    Data3DTextureStore,
    DataArrayTextureStore,
)
from render.target import RenderTarget
from render.derivatives import (
    NO_EDGE_RAMP,
    SurfaceSteps,
    alpha_test_ramp,
    fwidth,
)
from render.fragment_flags import (
    alpha_covers,
    dither,
    edge_ramp_at,
    hashed_threshold,
    surface_steps,
)
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
    packed_normal,
)
from render.srgb import LINEAR
from render.texture import (
    COVERAGE,
    FLOAT_TYPE,
    IGNORED,
    UV_CHANNEL_1,
    Texture,
    UvPlacement,
    check_data_map,
    require_data_descriptors,
    require_linear_data,
    require_uv_channel,
    anisotropic_footprint,
    mix_straight,
)
from render.screen_coord import (
    pixel_frag_coord,
    sample_pixel,
    sampled_point_coord,
    screen_size_coord,
)
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from materials.nodes import (
    AO_NODE,
    BACKDROP_ALPHA_NODE,
    BACKDROP_NODE,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    DEPTH_NODE,
    EMISSIVE_NODE,
    FRAGMENT_NODE,
    METALNESS_NODE,
    ROUGHNESS_NODE,
    MASK_NODE,
    NORMAL_NODE,
    NO_NODES,
    OPACITY_NODE,
    OUTPUT_NODE,
    RECEIVED_SHADOW_NODE,
    OFFSET_NODE,
    SCATTERING_NODE,
    CAST_SHADOW_NODE,
    ProgramShape,
    NodeContext,
    NodeInputs,
    NodeProgramId,
    NodeProgramStore,
    NodeSource,
    here_inputs,
    node_depth,
    offset_normal,
    has_output,
    perspective_shares,
    perspective_shares_over,
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
    ambient_occlusion,
    floored_roughness,
    geometry_roughness,
    gouraud_light,
    occluded_light,
    physical_outgoing,
    physical_surface,
    toward_eye_at,
    view_direction,
)
from materials.mesh_sss_node_material import (
    scatters,
    subsurface_diffuse,
    thickness_of,
)
from materials.volume_node_material import LitRay, volumetric_light
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
    toward_at,
)
from render.fillrule import (
    SUBPIXEL,
    bias,
    edge_at,
    pixel_index,
    sample,
    shifted_pixel_index,
    snap,
)
from render.pointrule import (
    coord as point_coord,
    covers as point_covers,
    first_covered,
    last_covered,
    mip_level_of,
)
from math.curve_checks import require_at_least_one
from math.finite import (
    require_finite,
    require_positive_finite,
    require_finite_group,
    require_non_negative_finite,
    require_unit_finite,
)
from std.math import floor, inf, isfinite, log2, max, min, sqrt

from render.tasks import TaskGroup
from render.splatrule import ProjectedSplat
from render.splat_raster import rasterize_splat


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
        # A corner that is not finite snaps to some grid point, which can
        # give the triangle an area. It covers no pixel.
        var corners = SIMD[DType.float32, 8](
            triangle.a.x,
            triangle.a.y,
            triangle.b.x,
            triangle.b.y,
            triangle.c.x,
            triangle.c.y,
            0,
            0,
        )
        if not isfinite(corners).reduce_and():
            area = 0
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
    var left = min3(triangle.a.x, triangle.b.x, triangle.c.x)
    var right = max3(triangle.a.x, triangle.b.x, triangle.c.x)
    var top = min3(triangle.a.y, triangle.b.y, triangle.c.y)
    var bottom = max3(triangle.a.y, triangle.b.y, triangle.c.y)
    var lowest = height - 1
    if last_row >= 0:
        lowest = min(lowest, last_row)
    return _Bounds(
        max(0, pixel_index(left, False)),
        min(width - 1, pixel_index(right, True)),
        max(first_row, pixel_index(top, False)),
        min(lowest, pixel_index(bottom, True)),
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
# An origin the borrow checker does not track, for a view that reads a
# store it knows outlives it; `postprocessing.sampling` names the same.
comptime _Untracked = UntrackedOrigin[mut=False]

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
        require_unit_finite(
            Float64(self.sheen_roughness),
            "A triangle's sheen roughness must be between zero and one",
        )
        require_unit_finite(
            Float64(self.iridescence),
            "A triangle's iridescence must be between zero and one",
        )
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
        require_finite_group(
            scale.is_finite(),
            "A triangle's clearcoat normal scale must be finite",
        )
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
        require_valid(
            self.normal_map_type.is_valid(),
            (
                "A triangle's normal map type must be TANGENT_SPACE_NORMAL_MAP"
                " or OBJECT_SPACE_NORMAL_MAP"
            ),
        )
        var ratio = self.refraction_ratio
        require_non_negative_finite(
            Float64(ratio), "A triangle's refraction ratio cannot be negative"
        )


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
    # Whether the triangle is seen from its back, and whether its material
    # is `BACK_SIDE`, for a node program's facing. Per-triangle, read from
    # the first corner. Set after construction, by `Renderer.prepare`; the
    # default is a front seen from the front.
    var seen_from_behind: Bool
    var flip_sided: Bool
    # The custom attributes a node program reads, `MAX_ATTRIBUTE_FLOATS`
    # floats. Set after construction, by `Renderer.prepare`; zeros by
    # default.
    var custom: SIMD[DType.float32, 8]
    # A `GOURAUD` corner's light, three.js's `vLightFront` and
    # `vIndirectFront`, and the light of its far side, `vLightBack` and
    # `vIndirectBack`, which `Renderer.prepare` puts in front when the far
    # side is the one drawn. Set after construction; zeros by default.
    var gouraud_direct: Vector3
    var gouraud_indirect: Vector3
    var gouraud_back_direct: Vector3
    var gouraud_back_indirect: Vector3
    # A `PHONG` triangle's light through from behind, three.js's
    # `SubsurfaceScatteringShader`: the thickness map, or `NO_TEXTURE` for
    # none; the color, linear; and the distortion, ambient, attenuation,
    # power and scale. Per-triangle, read from the first corner. Set after
    # construction, by `Renderer.prepare`; off by default.
    var scatter_map: TextureId
    var scatter_color: FloatColor
    var scatter_distortion: Float32
    var scatter_ambient: Float32
    var scatter_attenuation: Float32
    var scatter_power: Float32
    var scatter_scale: Float32
    # Where this frame's and the last frame's matrices put the corner in
    # clip space, as x, y and w: what a velocity attachment reads,
    # three.js's `clipPositionCurrent` and `clipPositionPrevious`. Set
    # after construction, by `Renderer.prepare`, for a frame that keeps
    # velocities; zeros by default, which is no motion. See
    # `fragment_velocity`.
    var current: Vector3
    var previous: Vector3
    # Which of the frame's lightings lights the triangle, read from the
    # first corner: zero for the frame's own, every light the camera sees,
    # and one past that for each `LightMask` a material names, in
    # `Renderer.light_masks` order. See `rasterize_frame`'s `lightings`.
    var lights: Int
    # A `VOLUME` triangle's ray: how many steps it takes, three.js's
    # `steps`, and the mesh's bounding radius in world space, three.js's
    # `modelRadius`. Per-triangle, read from the first corner. Set after
    # construction, by `Renderer.prepare`; see
    # `materials.volume_node_material`.
    var steps: Int
    var model_radius: Float32
    var volume_scene_depth: Bool

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
        self.seen_from_behind = False
        self.flip_sided = False
        self.custom = SIMD[DType.float32, 8](0)
        self.gouraud_direct = Vector3(0, 0, 0)
        self.gouraud_indirect = Vector3(0, 0, 0)
        self.gouraud_back_direct = Vector3(0, 0, 0)
        self.gouraud_back_indirect = Vector3(0, 0, 0)
        self.scatter_map = NO_TEXTURE
        self.scatter_color = FloatColor(1.0, 1.0, 1.0, 1.0)
        self.scatter_distortion = 0.1
        self.scatter_ambient = 0
        self.scatter_attenuation = 0.1
        self.scatter_power = 2
        self.scatter_scale = 10
        self.current = Vector3(0, 0, 0)
        self.previous = Vector3(0, 0, 0)
        self.lights = 0
        self.steps = DEFAULT_STEPS
        self.volume_scene_depth = False
        self.model_radius = 0


@fieldwise_init
struct Corner(ImplicitlyCopyable):
    """The part of a `RasterVertex` that differs from corner to corner: its
    place on the screen and its varyings, and the index of its draw's
    `Surface` in the frame's list.

    A draw's corners share one `Surface`, so a frame of many triangles
    carries each material once rather than once a corner. `joined` puts the
    two back together.
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
    # Where this corner is in the world, for lights that have a position. A
    # directional light needs only the normal; a point light needs to know
    # how far the surface is from the bulb and in which direction, and the
    # projection threw that away. Interpolated perspective-correctly like the
    # normal, so a fragment knows where *it* is.
    var world: Vector3
    # Light this surface gives off, linear, added after the lights and
    # untouched by them: three.js's `emissive`. Interpolated like the color,
    # and multiplied per fragment by `emissive_map` when there is one.
    var emissive: FloatColor
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
    # How many pixels across a point is, on the image, with any
    # attenuation already applied: three.js's `gl_PointSize`. Read by a
    # point alone, which is one corner rather than three or two; a
    # triangle's corners and a segment's ends carry zero.
    var point_size: Float32
    # The second texture coordinates, raw: the geometry's `uv1`, or its
    # `uv` when it has none. A map whose texture's `channel` is
    # `UV_CHANNEL_1` is sampled here, placed by its own transform. A
    # varying, interpolated like `u` and `v`.
    var u1: Float32
    var v1: Float32
    # Whether the triangle is seen from its back, and whether its material
    # is `BACK_SIDE`, for a node program's facing. Per-triangle, read from
    # the first corner. Set after construction, by `Renderer.prepare`; the
    # default is a front seen from the front.
    var seen_from_behind: Bool
    # The custom attributes a node program reads, `MAX_ATTRIBUTE_FLOATS`
    # floats. Set after construction, by `Renderer.prepare`; zeros by
    # default.
    var custom: SIMD[DType.float32, 8]
    # A `GOURAUD` corner's light, three.js's `vLightFront` and
    # `vIndirectFront`, and the light of its far side, `vLightBack` and
    # `vIndirectBack`, which `Renderer.prepare` puts in front when the far
    # side is the one drawn. Set after construction; zeros by default.
    var gouraud_direct: Vector3
    var gouraud_indirect: Vector3
    var gouraud_back_direct: Vector3
    var gouraud_back_indirect: Vector3
    # Where this frame's and the last frame's matrices put the corner in
    # clip space, as x, y and w: what a velocity attachment reads,
    # three.js's `clipPositionCurrent` and `clipPositionPrevious`. Set
    # after construction, by `Renderer.prepare`, for a frame that keeps
    # velocities; zeros by default, which is no motion. See
    # `fragment_velocity`.
    var current: Vector3
    var previous: Vector3
    # How much light this surface sends toward the camera, linear: a
    # `PHONG` material's `specular`. Interpolated like the emissive, which
    # is also one color per material, and for the same reason -- a varying
    # costs the same as a constant here and needs no second mechanism.
    var specular: FloatColor
    # The index of the corner's `Surface` in the frame's list.
    var surface: Int


@fieldwise_init
struct Surface(ImplicitlyCopyable):
    """The part of a `RasterVertex` shared by corners with the same
    material and facing, as the rasterizer reads it. See `Corner`."""

    # `OPAQUE` or `BLEND`, resolved from the material by `Renderer.prepare`
    # rather than guessed at from this vertex's alpha. Per-triangle metadata,
    # like the texture below: the whole triangle comes from one material, so
    # all three corners carry the same answer and the first is read.
    var blend: Blending
    # Which texture to sample, or `NO_TEXTURE` for none. It travels with the
    # vertex because `Renderer.prepare` returns one flat list of triangles for
    # a whole scene, and the meshes in a scene need not share a material.
    var texture: TextureId
    # What kind of surface this is: `LAMBERT`, lit by the scene's lights;
    # `BASIC`, its own color whatever the lights do -- a sky, a sprite, an
    # overlay; `NORMALS`, the normal written as a color; or `DEPTH`, how
    # far away it is. The last two show data rather than light, and a
    # `NORMALS` corner's `normal` is in view space rather than world space,
    # since it is shown rather than lit. Per-triangle metadata like the
    # blend policy: read from the first corner, checked to agree.
    var kind: MaterialKind
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
    # How long each dash is and how long the gap after it, in the units
    # the distance is measured in: three.js's `dashSize` and `gapSize`.
    # Per-segment metadata like the blend policy, read from the first end
    # and checked to agree. A gap of zero is a solid line.
    var dash_size: Float32
    var gap_size: Float32
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
    var flip_sided: Bool
    # A `PHONG` triangle's light through from behind, three.js's
    # `SubsurfaceScatteringShader`: the thickness map, or `NO_TEXTURE` for
    # none; the color, linear; and the distortion, ambient, attenuation,
    # power and scale. Per-triangle, read from the first corner. Set after
    # construction, by `Renderer.prepare`; off by default.
    var scatter_map: TextureId
    var scatter_color: FloatColor
    var scatter_distortion: Float32
    var scatter_ambient: Float32
    var scatter_attenuation: Float32
    var scatter_power: Float32
    var scatter_scale: Float32
    # Which of the frame's lightings lights the triangle, read from the
    # first corner: zero for the frame's own, every light the camera sees,
    # and one past that for each `LightMask` a material names, in
    # `Renderer.light_masks` order. See `rasterize_frame`'s `lightings`.
    var lights: Int
    # A `VOLUME` triangle's ray: how many steps it takes, three.js's
    # `steps`, and the mesh's bounding radius in world space, three.js's
    # `modelRadius`. Per-triangle, read from the first corner. Set after
    # construction, by `Renderer.prepare`; see
    # `materials.volume_node_material`.
    var steps: Int
    var model_radius: Float32
    var volume_scene_depth: Bool


def joined(corner: Corner, surface: Surface) -> RasterVertex:
    """Return the `RasterVertex` a corner and its surface make together.

    Args:
        corner: The corner's own values.
        surface: Its draw's material.

    Returns:
        The whole vertex.
    """
    var vertex = RasterVertex(
        corner.x, corner.y, corner.z, corner.inv_w, corner.color
    )
    vertex.normal = corner.normal
    vertex.u = corner.u
    vertex.v = corner.v
    vertex.world = corner.world
    vertex.emissive = corner.emissive
    vertex.view_depth = corner.view_depth
    vertex.line_distance = corner.line_distance
    vertex.point_size = corner.point_size
    vertex.u1 = corner.u1
    vertex.v1 = corner.v1
    vertex.seen_from_behind = corner.seen_from_behind
    vertex.custom = corner.custom
    vertex.gouraud_direct = corner.gouraud_direct
    vertex.gouraud_indirect = corner.gouraud_indirect
    vertex.gouraud_back_direct = corner.gouraud_back_direct
    vertex.gouraud_back_indirect = corner.gouraud_back_indirect
    vertex.current = corner.current
    vertex.previous = corner.previous
    vertex.blend = surface.blend
    vertex.texture = surface.texture
    vertex.kind = surface.kind
    vertex.emissive_map = surface.emissive_map
    vertex.alpha_map = surface.alpha_map
    vertex.alpha_test = surface.alpha_test
    vertex.specular = corner.specular
    vertex.shininess = surface.shininess
    vertex.matcap = surface.matcap
    vertex.gradient_map = surface.gradient_map
    vertex.dash_size = surface.dash_size
    vertex.gap_size = surface.gap_size
    vertex.env_map = surface.env_map
    vertex.reflectivity = surface.reflectivity
    vertex.combine = surface.combine
    vertex.roughness = surface.roughness
    vertex.metalness = surface.metalness
    vertex.env_map_intensity = surface.env_map_intensity
    vertex.roughness_map = surface.roughness_map
    vertex.metalness_map = surface.metalness_map
    vertex.specular_intensity = surface.specular_intensity
    vertex.clearcoat = surface.clearcoat
    vertex.clearcoat_roughness = surface.clearcoat_roughness
    vertex.normal_map = surface.normal_map
    vertex.normal_scale = surface.normal_scale
    vertex.bump_map = surface.bump_map
    vertex.bump_scale = surface.bump_scale
    vertex.receives_shadow = surface.receives_shadow
    vertex.state = surface.state
    vertex.ao_map = surface.ao_map
    vertex.ao_map_intensity = surface.ao_map_intensity
    vertex.light_map = surface.light_map
    vertex.light_map_intensity = surface.light_map_intensity
    vertex.specular_map = surface.specular_map
    vertex.transmission = surface.transmission
    vertex.transmission_map = surface.transmission_map
    vertex.thickness = surface.thickness
    vertex.thickness_map = surface.thickness_map
    vertex.attenuation_color = surface.attenuation_color
    vertex.attenuation_distance = surface.attenuation_distance
    vertex.dispersion = surface.dispersion
    vertex.ior = surface.ior
    vertex.fog = surface.fog
    vertex.depth_packing = surface.depth_packing
    vertex.reference = surface.reference
    vertex.near_distance = surface.near_distance
    vertex.far_distance = surface.far_distance
    vertex.layers = surface.layers
    vertex.nodes = surface.nodes
    vertex.frames = surface.frames
    vertex.flip_sided = surface.flip_sided
    vertex.scatter_map = surface.scatter_map
    vertex.scatter_color = surface.scatter_color
    vertex.scatter_distortion = surface.scatter_distortion
    vertex.scatter_ambient = surface.scatter_ambient
    vertex.scatter_attenuation = surface.scatter_attenuation
    vertex.scatter_power = surface.scatter_power
    vertex.scatter_scale = surface.scatter_scale
    vertex.lights = surface.lights
    vertex.steps = surface.steps
    vertex.volume_scene_depth = surface.volume_scene_depth
    vertex.model_radius = surface.model_radius
    return vertex^


def corner_of(vertex: RasterVertex, surface: Int) -> Corner:
    """Return the part of a vertex that is its own, naming its surface.

    Args:
        vertex: The whole vertex.
        surface: The index of its `Surface` in the frame's list.

    Returns:
        The corner.
    """
    return Corner(
        vertex.x,
        vertex.y,
        vertex.z,
        vertex.inv_w,
        vertex.color,
        vertex.normal,
        vertex.u,
        vertex.v,
        vertex.world,
        vertex.emissive,
        vertex.view_depth,
        vertex.line_distance,
        vertex.point_size,
        vertex.u1,
        vertex.v1,
        vertex.seen_from_behind,
        vertex.custom,
        vertex.gouraud_direct,
        vertex.gouraud_indirect,
        vertex.gouraud_back_direct,
        vertex.gouraud_back_indirect,
        vertex.current,
        vertex.previous,
        vertex.specular,
        surface,
    )


def surface_of(vertex: RasterVertex) -> Surface:
    """Return the part of a vertex its draw's other corners share.

    Args:
        vertex: The whole vertex.

    Returns:
        Its surface.
    """
    return Surface(
        vertex.blend,
        vertex.texture,
        vertex.kind,
        vertex.emissive_map,
        vertex.alpha_map,
        vertex.alpha_test,
        vertex.shininess,
        vertex.matcap,
        vertex.gradient_map,
        vertex.dash_size,
        vertex.gap_size,
        vertex.env_map,
        vertex.reflectivity,
        vertex.combine,
        vertex.roughness,
        vertex.metalness,
        vertex.env_map_intensity,
        vertex.roughness_map,
        vertex.metalness_map,
        vertex.specular_intensity,
        vertex.clearcoat,
        vertex.clearcoat_roughness,
        vertex.normal_map,
        vertex.normal_scale,
        vertex.bump_map,
        vertex.bump_scale,
        vertex.receives_shadow,
        vertex.state,
        vertex.ao_map,
        vertex.ao_map_intensity,
        vertex.light_map,
        vertex.light_map_intensity,
        vertex.specular_map,
        vertex.transmission,
        vertex.transmission_map,
        vertex.thickness,
        vertex.thickness_map,
        vertex.attenuation_color,
        vertex.attenuation_distance,
        vertex.dispersion,
        vertex.ior,
        vertex.fog,
        vertex.depth_packing,
        vertex.reference,
        vertex.near_distance,
        vertex.far_distance,
        vertex.layers,
        vertex.nodes,
        vertex.frames,
        vertex.flip_sided,
        vertex.scatter_map,
        vertex.scatter_color,
        vertex.scatter_distortion,
        vertex.scatter_ambient,
        vertex.scatter_attenuation,
        vertex.scatter_power,
        vertex.scatter_scale,
        vertex.lights,
        vertex.steps,
        vertex.model_radius,
        vertex.volume_scene_depth,
    )


@fieldwise_init
struct ShadeMode(Equatable, ImplicitlyCopyable, Writable):
    """What a fragment's color is taken from, as a type rather than an int.

    The first three cases differ in which numbers they read, not in what the
    rasterizer does around them. `SHADE_TEXTURE` multiplies the sampled texel
    by the interpolated lighting, so a white texture shades exactly as
    `SHADE_LIT` does and an unlit white mesh shows the image unchanged.
    `SHADE_SHADOW` is the shadow pass's own: each fragment writes what a
    light sees through it, its `CAST_SHADOW_NODE` or opaque black, times
    its maps' alpha, three.js's shadow material under
    `shadowMap.transmitted`. It writes the depth whatever the draw's state
    says, as that material does. Only the host draws a shadow map, so only the
    host rasterizer takes it.

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
        """Return True if this is one of the four modes there are."""
        return ordinal_valid(self.value, SHADE_SHADOW.value)


comptime SHADE_LIT = ShadeMode(0)
comptime SHADE_UV = ShadeMode(1)
comptime SHADE_TEXTURE = ShadeMode(2)
comptime SHADE_SHADOW = ShadeMode(3)


def require_shade_mode(mode: ShadeMode) raises:
    """Refuse a shading mode that is none of the four.

    Nothing. The call returns when the mode is named.

    Args:
        mode: The mode to check.

    Raises:
        Error: If `mode` is none of the four.
    """
    require_valid(mode.is_valid(), "A shading mode that is none of the four")


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
    var shares = perspective_shares(
        weights.wa, weights.wb, weights.wc, a.inv_w, b.inv_w, c.inv_w
    )
    var share_a = shares[0]
    var share_b = shares[1]
    var share_c = shares[2]
    if second:
        return weighted_sum2(
            Vector2(a.u1, a.v1),
            Vector2(b.u1, b.v1),
            Vector2(c.u1, c.v1),
            share_a,
            share_b,
            share_c,
        )
    return weighted_sum2(
        Vector2(a.u, a.v),
        Vector2(b.u, b.v),
        Vector2(c.u, c.v),
        share_a,
        share_b,
        share_c,
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
    var shares = perspective_shares(
        weights.wa, weights.wb, weights.wc, a.inv_w, b.inv_w, c.inv_w
    )
    var share_a = shares[0]
    var share_b = shares[1]
    var share_c = shares[2]
    return weighted_sum3(a.world, b.world, c.world, share_a, share_b, share_c)
