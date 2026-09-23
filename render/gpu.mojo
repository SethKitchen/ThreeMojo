# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rasterizing prepared triangles on the GPU, one thread per pixel.

`render.rasterizer` walks the pixels of one triangle at a time in a nested
loop. This turns that inside out: one thread owns one pixel for the whole
draw, walks every triangle, and keeps the nearest one it is covered by. The
two produce identical images, which `tests/test_gpu.mojo` checks pixel for
pixel, because both decide coverage with `render.fillrule` — the same module,
not a copy of it.

**One owner per pixel.** A thread per pixel is not the only way to divide the
work — a thread per triangle is the obvious alternative, and faster when
triangles are large — but it is the only one of the two that is correct
without synchronization. Independent triangle threads writing a shared color
and depth buffer race: `Framebuffer.test_depth` is a read followed by a write,
which is a depth test, not an atomic. Because each pixel here is owned
outright, its depth lives in a register that nothing else can touch. That
depth is written out alongside the color, so what comes back is a framebuffer
in the same sense the CPU produces one — a result that reports no depth at all
would silently let a later depth-tested triangle paint over a nearer surface.
Tiling and per-triangle binning can come later; they are optimizations of a
correct thing.

**The transform pipeline is still on the host.** Scene traversal, projection,
lighting and clipping run on the CPU, and only the finished screen-space
triangles come here. That is a deliberate stage, not an unfinished one: it
makes the GPU a second implementation of exactly one well-defined step, which
is what lets the parity tests be meaningful.

Colors cross the boundary packed into a `UInt32`. Kernel arguments must
conform to `DevicePassable`, which rules out the `Color` struct and, less
obviously, plain `Int` — the compiler asks for a fixed-width type instead.

Whether this is *faster* than the CPU is a separate question, and the answer
is size-dependent. `bench/raster_bench.mojo` measures where the crossover is.
"""

from math.vector2 import Vector2
from max.gpu.host import DeviceBuffer, DeviceContext
from render.blend import NORMAL_MODE, Rgba, blend_pixel
from render.raster_state import (
    REVERSED_DEPTH,
    STANDARD_DEPTH,
    DepthMode,
    RasterState,
    cleared_depth,
    fragment_depth,
    shades,
    test_fragment,
)
from render.fillrule import SUBPIXEL, bias, edge_at, sample, snap
from render.linerule import covers, dash_covers, major_is_x, share_at
from render.pointrule import (
    coord as point_coord,
    covers as point_covers,
    mip_level_of,
)
from render.rect import Rect
from render.framebuffer import Color, FloatColor, Framebuffer
from core.fog import NO_FOG, FogKind, FogView, fog_factor, fog_mix
from lights.shadow import (
    BASIC_SHADOW_MAP,
    CENTER_TAP,
    PCF_SOFT_SHADOW_MAP,
    PCF_TAPS,
    SHADOW_HEADER,
    SHADOW_TYPE_AT,
    SOFT_TAPS,
    SPOT_MAP_FLOATS,
    VSM_SHADOW_MAP,
    biased_position,
    bilinear,
    bilinear_texel,
    cube_tap,
    cube_texel,
    inside_point_shadow,
    inside_shadow_map,
    inside_spot_map,
    point_shadow_depth,
    point_shadow_spread,
    point_shadow_tap,
    shadow_coordinate,
    shadow_tap,
    shadow_texel,
    soft_fraction,
    soft_shadow,
    soft_texel,
    vsm_shadow,
)
from lights.ltc import (
    LTC_FLOATS,
    ltc_blend,
    ltc_neighbor,
    ltc_texel,
    ltc_uv,
    rect_area_light,
)
from lights.lighting import (
    PERSPECTIVE_VIEW,
    RECIPROCAL_PI,
    Lighting,
    Reflected,
    ambient_occlusion,
    blinn_phong,
    falloff,
    floored_roughness,
    occluded_light,
    physical_light,
    physical_outgoing,
    physical_surface,
    toon_coord,
    toon_index,
    toon_step,
    toward_eye_at,
)
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.rasterizer import (
    check_line_state,
    check_point_state,
    DRAW_POINTS,
    DRAW_SEGMENTS,
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    DRAW_TRIANGLES,
    Draw,
    RasterVertex,
    ShadeMode,
    Triangle,
    check_alpha_map,
    check_draws,
    check_output_kinds,
    check_triangle_state,
    bumped_normal,
    interpolate_alpha,
    mapped_normal,
    matcap_fallback,
    matcap_uv,
    packed_depth,
    packed_normal,
)
from materials.material import (
    OPAQUE,
    DEPTH,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    TOON,
    Combine,
    combine_light,
)
from render.cube_texture import (
    FACE_COUNT,
    face_of,
    face_uv,
    reflected,
    reflection_level,
    rough_reflection,
)
from render.cube_uv import cube_uv_taps
from math.spherical_harmonics3 import SH_COUNT, sh_irradiance_weight
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    CubeTextureId,
    CubeTextureStore,
)
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from render.srgb import LINEAR, SRGB, ColorSpace, decode_ramp
from render.tonemap import (
    NO_TONE_MAPPING,
    ToneMapping,
    check_tone_mapping,
    tone_map,
)
from render.texture import (
    BILINEAR,
    COVERAGE,
    FLOAT_TYPE,
    IGNORED,
    NEAREST,
    UNSIGNED_BYTE_TYPE,
    Alpha,
    Filter,
    Footprint,
    TexelType,
    Texture,
    Wrap,
    anisotropic_footprint,
    blend_texels,
    float_from_bytes,
    float_texel,
    mix_color,
    mix_straight,
    wrap_index,
)
from max.gpu import global_idx
from std.math import ceildiv, floor, inf, log2, sqrt
from std.memory import bitcast, unsafe_memcpy
from std.sys import has_accelerator

# 16x16 threads is a conventional starting point for a 2D grid: a multiple of
# the warp size on every vendor, and small enough that a narrow image still
# fills several blocks.
comptime TILE = 16

# How a `RasterVertex` is laid out in the flat float buffer the kernel reads.
# A struct would be tidier and is not an option — the buffer has to be plain
# floats to cross to the device — so each field's lane is named once here
# and used by both the host's `flatten` and the kernel's reads. Adding a
# varying means adding a lane, not editing offsets in two places; a stride
# change once meant missing one, which silently read a neighboring field as
# a coordinate. tests/test_gpu.mojo asserts the layout.
comptime LANE_X = 0
comptime LANE_Y = 1
comptime LANE_Z = 2
comptime LANE_INV_W = 3
comptime LANE_R = 4
comptime LANE_G = 5
comptime LANE_B = 6
comptime LANE_A = 7
comptime LANE_U = 8
comptime LANE_V = 9
comptime LANE_NX = 10
comptime LANE_NY = 11
comptime LANE_NZ = 12
# World position, for the point lights. See `RasterVertex.world`.
comptime LANE_WX = 13
comptime LANE_WY = 14
comptime LANE_WZ = 15
# Light the surface gives off, linear. See `RasterVertex.emissive`. Three
# lanes rather than four: the term never touches alpha.
comptime LANE_ER = 16
comptime LANE_EG = 17
comptime LANE_EB = 18
# Camera-space depth, for the fog. See `RasterVertex.view_depth`.
comptime LANE_DEPTH = 19
# The alpha a fragment must reach to be drawn. Per-triangle rather than a
# varying, and read from the first corner's lane: it is the only float
# among the per-triangle state, and the state table holds integers.
comptime LANE_ALPHA_TEST = 20
# How much light the surface sends toward the camera, linear: a `PHONG`
# material's `specular`. Three lanes rather than four, as the emissive is:
# a highlight never touches alpha.
comptime LANE_SPECULAR_R = 21
comptime LANE_SPECULAR_G = 22
comptime LANE_SPECULAR_B = 23
# How tight the highlight is. Per-triangle, read from the first corner's
# lane like the alpha test.
comptime LANE_SHININESS = 24
# How far along its line a corner is, scaled: a dashed line's varying.
# See `RasterVertex.line_distance`. A triangle's corners carry zero.
comptime LANE_LINE_DISTANCE = 25
# How long a dash is and how long the gap after it. Per-segment, read
# from the first end's lane like the alpha test, and floats like it, which
# is why they are lanes rather than entries in the segment state table.
comptime LANE_DASH = 26
comptime LANE_GAP = 27
# How many pixels across a point is. Per point, and a point is one corner,
# so it is a lane like everything else a point carries. A triangle's
# corners and a segment's ends carry zero.
comptime LANE_POINT_SIZE = 28
# How much of a reflection joins the surface's light. Per triangle, read
# from the first corner's lane like the shininess, and a float like it.
comptime LANE_REFLECTIVITY = 29
# A physical surface's roughness and metalness, what its environment is
# multiplied by, what its reflectance is scaled by at a grazing angle, and
# its clear coat's amount and roughness. Per triangle, read from the first
# corner's lane like the shininess, and floats like it.
comptime LANE_ROUGHNESS = 30
comptime LANE_METALNESS = 31
comptime LANE_ENV_INTENSITY = 32
comptime LANE_SPECULAR_INTENSITY = 33
comptime LANE_CLEARCOAT = 34
comptime LANE_CLEARCOAT_ROUGHNESS = 35
# What a normal map's x and y are scaled by, and what a bump map's height
# is scaled by. Per triangle, from the first corner's lane, and signed:
# the renderer negates them when it turns a corner around.
comptime LANE_NORMAL_SCALE_X = 36
comptime LANE_NORMAL_SCALE_Y = 37
comptime LANE_BUMP_SCALE = 38
# The second texture coordinates, where an ambient occlusion map and a
# light map are sampled: a varying like `LANE_U` and `LANE_V`, and next to
# each other so `_uv_at` reads either pair from its first lane. Then how
# strongly the ao map dims and what the light map is scaled by, per
# triangle, from the first corner's lanes.
comptime LANE_U1 = 39
comptime LANE_V1 = 40
comptime LANE_AO_INTENSITY = 41
comptime LANE_LIGHT_MAP_INTENSITY = 42
# three.js's `logDepthBufFC`, `RasterState.log_depth_scale`. Per
# primitive, read from the first corner's lane like the alpha test: it is
# a float, and the state table holds integers.
comptime LANE_LOG_DEPTH = 43
comptime FLOATS_PER_VERTEX = LANE_LOG_DEPTH + 1
comptime FLOATS_PER_TRIANGLE = FLOATS_PER_VERTEX * 3

# How a triangle's metadata is laid out in the state buffer beside the
# vertices: one entry per column, per triangle. Named here for the reason
# the lanes are, and read by `triangle_state` and the kernel alike.
comptime STATE_TEXTURE = 0
comptime STATE_BLEND = 1
comptime STATE_KIND = 2
comptime STATE_EMISSIVE_MAP = 3
comptime STATE_ALPHA_MAP = 4
# Which texture's top row is the ramp a `TOON` triangle steps through, or
# `NO_TEXTURE`. An index rather than a lane, because it is one number per
# triangle like every other map.
comptime STATE_GRADIENT_MAP = 5
# Which image a `MATCAP` triangle is looked up in, or `NO_TEXTURE`.
comptime STATE_MATCAP = 6
# Where the six faces of the cube a triangle reflects begin in the
# descriptor table, or -1 for none. A slot rather than a cube id, because
# the table holds faces: `set_textures` lays every cube's six faces out
# after the flat textures, and `triangle_state` turns the id into the slot
# of its first face. See `_sample_cube`.
comptime STATE_ENV_MAP = 7
# How the reflection joins the surface's light: a `Combine` value.
comptime STATE_COMBINE = 8
# Which textures multiply a physical triangle's roughness and metalness,
# and which perturb its normal: a map of normals, or a map of heights.
# Each `NO_TEXTURE` for none.
comptime STATE_ROUGHNESS_MAP = 9
comptime STATE_METALNESS_MAP = 10
comptime STATE_NORMAL_MAP = 11
comptime STATE_BUMP_MAP = 12
# Whether the lights' shadows fall on the triangle: one or zero.
comptime STATE_RECEIVES_SHADOW = 13
# The depth, color and stencil state, as `RasterState.ops_word` and
# `RasterState.stencil_word` pack it: two integers that ride the table the
# way a custom blending mode rides `STATE_BLEND`.
comptime STATE_OPS = 14
comptime STATE_STENCIL = 15
# Which texture dims the triangle's indirect light and which adds baked
# light to it, each `NO_TEXTURE` for none.
comptime STATE_AO_MAP = 16
comptime STATE_LIGHT_MAP = 17
# Which texture's red channel scales a triangle's highlight and its
# reflectivity, three.js's `specularMap`, or `NO_TEXTURE` for none.
comptime STATE_SPECULAR_MAP = 18
# How a segment's metadata is laid out in its state buffer: its blend
# policy, and how many pixels across it is drawn. A line is unlit and
# untextured, so it carries nothing else; see `line_state`. The width is
# one number per frame, carried per segment rather than as a kernel
# argument, because Metal binds at most thirty-one arguments to a kernel
# and this one has thirty-one.
comptime LINE_STATE_BLEND = 0
comptime LINE_STATE_WIDTH = 1
# The segment's depth, color and stencil state, packed as a triangle's is.
comptime LINE_STATE_OPS = 2
comptime LINE_STATE_STENCIL = 3
comptime STATE_PER_LINE = LINE_STATE_STENCIL + 1
# How a point's metadata is laid out in its state buffer: its texture, its
# blend policy and its alpha map. A point is unlit, so it has no kind to
# carry, no emissive map, no ramp and no matcap.
comptime POINT_STATE_TEXTURE = 0
comptime POINT_STATE_BLEND = 1
comptime POINT_STATE_ALPHA_MAP = 2
# The point's depth, color and stencil state, packed as a triangle's is.
comptime POINT_STATE_OPS = 3
comptime POINT_STATE_STENCIL = 4
comptime STATE_PER_POINT = POINT_STATE_STENCIL + 1
# How a `Draw` crosses to the device: its kind, its first primitive and its
# count, as three integers.
comptime INTS_PER_DRAW = 3
comptime STATE_PER_TRIANGLE = STATE_SPECULAR_MAP + 1

# How a `FogView` is laid out in the fog buffer: the two edges and the
# density, then the fog color, linear. Six floats, whatever the kind,
# which crosses as its own argument. Named here for the reason the lanes
# are, and read by `flatten_fog` and the kernel alike.
comptime FOG_NEAR = 0
comptime FOG_FAR = 1
comptime FOG_DENSITY = 2
comptime FOG_R = 3
comptime FOG_G = 4
comptime FOG_B = 5
comptime FOG_FLOATS = FOG_B + 1

# How the light buffer begins: where the camera is, the one direction
# toward it when its rays are parallel, then the ambient term, then the
# directional lights. Named here for the reason the vertex lanes are, and
# read by `flatten_lights`, `_arriving` and `_highlight` alike.
comptime LIGHTS_EYE = 0
comptime LIGHTS_TOWARD = 3
comptime LIGHTS_UP = 6
comptime LIGHTS_AMBIENT = 9
# What every sum of arriving light is multiplied by: `Lighting.scale`.
comptime LIGHTS_SCALE = 12
# How many rect area lights follow the spot lights. In the header rather
# than a kernel argument of its own, for the reason the shadow maps ride
# in this buffer: the kernel has no argument left.
comptime LIGHTS_RECT_COUNT = 13
# The light probes' nine coefficients summed, `Lighting.probe`, red, green
# and blue each. Zero when the scene has no probe.
comptime LIGHTS_PROBE = 14
comptime LIGHTS_FIRST = LIGHTS_PROBE + SH_COUNT * 3
# How many floats each kind of light takes in the buffer. A directional
# light's seventh, a point light's ninth and a spot light's fourteenth is
# where its shadow map begins in the same buffer, or -1 for none: the maps
# ride after the lights, each `SHADOW_HEADER` floats and then its depths,
# rather than in a buffer of their own, because Metal binds at most
# thirty-one arguments to a kernel and this one has thirty-one. A spot
# light's fifteenth is where its map's `SPOT_MAP_FLOATS` begin, after the
# shadow maps, or -1 for none.
comptime DIRECTIONAL_FLOATS = 7
comptime POINT_FLOATS = 9
comptime HEMISPHERE_FLOATS = 9
comptime SPOT_FLOATS = 15
# A rect area light: its center, its half width and its half height in
# world space, and its radiance. When there is at least one, the two LTC
# tables follow the last, `LTC_FLOATS` each; see `lights.ltc`.
comptime RECT_FLOATS = 12
comptime NO_SHADOW = Float32(-1)

# Further than any NDC depth, so the first covering triangle always wins. The
# host framebuffer uses an actual infinity; a literal keeps the kernel free of
# any dependency on how the host spells one.
comptime FURTHEST = Float32(1.0e30)

# One row per texture in the store: where its bytes start, how big it is, and
# how to sample it. A device cannot hold a `List` of `List`s, so every image
# goes into one buffer end to end and this says where each one begins.
comptime TABLE_COLUMNS = 10
# How many table rows a cube texture takes: its six faces, then its PMREM
# image, or one white byte texel for a cube that has none. The kernel tells
# the two apart by the texel type, since a PMREM always holds floats.
comptime CUBE_ROWS = FACE_COUNT + 1


def flatten_textures(
    textures: TextureStore,
    cubes: CubeTextureStore = CubeTextureStore(),
) raises -> Tuple[List[UInt8], List[Int32]]:
    """Return every texture's bytes end to end, and the table describing them.

    The flat textures first, one row each in id order, then every cube
    texture's six faces and its PMREM image in id order, one row each,
    `CUBE_ROWS` in all: cube `c` begins at row
    `textures.count() + c * CUBE_ROWS`, which is what `triangle_state`
    writes for a triangle that reflects it. A cube with no PMREM has the
    blank texture there, which crosses as one white byte texel.

    Args:
        textures: The store to upload.
        cubes: The cube textures to upload after it.

    Returns:
        The concatenated texels, and `TABLE_COLUMNS` entries per texture:
        byte offset, width, height, wrap mode, filter mode, color space,
        how many mip levels follow, the alpha mode, the anisotropy, and
        the texel type. A float texture's numbers cross as four
        little-endian bytes each, so every texture shares one buffer.

    Raises:
        Error: If a texture cannot be read, or its wrap, filter, color
            space or alpha mode is none of the named values -- a texture's
            fields are open, so one can have been edited since it was built,
            and the kernel cannot raise on what it finds in the table -- or
            a cube texture is refused by `CubeTexture.validate`.
    """
    var texels = List[UInt8]()
    var table = List[Int32]()
    for id in range(textures.count()):
        _flatten_one(textures.get(TextureId(id)), texels, table)
    for cube in range(cubes.count()):
        ref six = cubes.get(CubeTextureId(cube))
        six.validate()
        for face in range(FACE_COUNT):  # pragma: no branch
            _flatten_one(six.face(face), texels, table)
        _flatten_one(six.cube_uv, texels, table)
    # Never empty: a zero-length device buffer is not worth the special case,
    # and a vertex naming NO_TEXTURE never reads either of these.
    if len(texels) == 0:
        texels.append(0)
    if len(table) == 0:
        for _ in range(TABLE_COLUMNS):
            table.append(0)
    return (texels^, table^)


def _flatten_one(
    image: Texture, mut texels: List[UInt8], mut table: List[Int32]
) raises:
    """Append one texture's bytes and its row of the table.

    Raises:
        Error: If the texture's wrap, filter, color space or alpha mode is
            none of the named values.
    """
    image.validate()
    table.append(Int32(len(texels)))
    if image.is_blank():
        # A blank texture is a legitimate thing to store, and on the host
        # it samples as opaque white. Rather than teach the kernel a
        # second meaning for "no texture", it crosses as one white texel:
        # the device invariant stays "every descriptor has a real size",
        # and sampling a 1x1 white image gives white at any coordinate
        # under any wrap mode. Left as a zero width it reached
        # `wrap_index(..., 0, REPEAT)`, which is a modulo by zero, and the
        # GPU returned black where the CPU returned white.
        table.append(1)
        table.append(1)
        table.append(Int32(image.wrap.value))
        table.append(Int32(image.filter.value))
        table.append(Int32(image.color_space.value))
        table.append(1)
        table.append(Int32(COVERAGE.value))
        table.append(1)
        table.append(Int32(UNSIGNED_BYTE_TYPE.value))
        for _ in range(4):
            texels.append(255)
        return
    table.append(Int32(image.width))
    table.append(Int32(image.height))
    table.append(Int32(image.wrap.value))
    table.append(Int32(image.filter.value))
    table.append(Int32(image.color_space.value))
    table.append(Int32(image.levels))
    table.append(Int32(image.alpha.value))
    table.append(Int32(image.anisotropy))
    table.append(Int32(image.texel_type.value))
    if image.texel_type == FLOAT_TYPE:
        # Four bytes a number, least significant first: what
        # `float_from_bytes` reads back on the device.
        for index in range(len(image.data)):
            var bits = bitcast[DType.uint32](image.data[index])
            texels.append(UInt8(bits & 0xFF))
            texels.append(UInt8((bits >> 8) & 0xFF))
            texels.append(UInt8((bits >> 16) & 0xFF))
            texels.append(UInt8(bits >> 24))
        return
    # One bulk copy rather than an append per byte.
    texels.extend(image.pixels.copy())


def pack(color: Color) -> UInt32:
    """Return `color` packed into one big-endian RGBA word."""
    return (
        (UInt32(color.r) << 24)
        | (UInt32(color.g) << 16)
        | (UInt32(color.b) << 8)
        | UInt32(color.a)
    )


def available() -> Bool:
    """Return True if this machine has a GPU Mojo can target."""
    return has_accelerator()


def flatten(corners: List[RasterVertex]) -> List[Float32]:
    """Return `corners` as the flat float buffer the kernel reads.

    Args:
        corners: Raster vertices, three per triangle.

    Returns:
        `FLOATS_PER_VERTEX` floats per vertex, in the order the kernel
        unpacks them.
    """
    var flat = List[Float32]()
    for index in range(len(corners)):
        var corner = corners[index]
        flat.append(corner.x)
        flat.append(corner.y)
        flat.append(corner.z)
        flat.append(corner.inv_w)
        flat.append(corner.color.r)
        flat.append(corner.color.g)
        flat.append(corner.color.b)
        flat.append(corner.color.a)
        flat.append(corner.u)
        flat.append(corner.v)
        flat.append(corner.normal.x)
        flat.append(corner.normal.y)
        flat.append(corner.normal.z)
        flat.append(corner.world.x)
        flat.append(corner.world.y)
        flat.append(corner.world.z)
        flat.append(corner.emissive.r)
        flat.append(corner.emissive.g)
        flat.append(corner.emissive.b)
        flat.append(corner.view_depth)
        flat.append(corner.alpha_test)
        flat.append(corner.specular.r)
        flat.append(corner.specular.g)
        flat.append(corner.specular.b)
        flat.append(corner.shininess)
        flat.append(corner.line_distance)
        flat.append(corner.dash_size)
        flat.append(corner.gap_size)
        flat.append(corner.point_size)
        flat.append(corner.reflectivity)
        flat.append(corner.roughness)
        flat.append(corner.metalness)
        flat.append(corner.env_map_intensity)
        flat.append(corner.specular_intensity)
        flat.append(corner.clearcoat)
        flat.append(corner.clearcoat_roughness)
        flat.append(corner.normal_scale.x)
        flat.append(corner.normal_scale.y)
        flat.append(corner.bump_scale)
        flat.append(corner.u1)
        flat.append(corner.v1)
        flat.append(corner.ao_map_intensity)
        flat.append(corner.light_map_intensity)
        flat.append(corner.state.log_depth_scale)
    return flat^


def flatten_lights(lighting: Lighting) -> List[Float32]:
    """Return a scene's lights as the flat float buffer the kernel reads.

    Three floats of camera position, three of the one direction toward it
    under a parallel projection, three of the camera's own up axis, then
    three of ambient, one of `Lighting.scale`, one of how many rect area
    lights there are, 27 of the light probes' coefficients, then six per
    directional light -- a unit
    direction and the light it carries -- then nine per point light: where
    it is, the light it carries, its decay, its cutoff and its shadow. Then
    nine per
    hemisphere light: which way the sky is, what the sky carries and what
    the ground carries. Then fifteen per spot light: where it is, which way
    it points, what it carries, its decay, its cutoff, the cosines of its
    cone and of its penumbra, its shadow and its map. Already decoded and scaled by `Lighting`,
    so the device does no color-space work and both backends sum exactly
    the same numbers.

    The camera comes first because a `PHONG` material measures its
    highlight from there, and because putting it at the head leaves every
    light's offset one named constant away. The direction beside it is
    zero for a converging projection, which is what tells the kernel to
    work each fragment's direction out from the position instead; see
    `lights.lighting.toward_eye_at`.

    Args:
        lighting: The scene's lights, resolved to world space.

    Each directional light carries a seventh float, each point light a
    ninth and each spot light a fourteenth: where its shadow map begins in
    this same buffer, or `NO_SHADOW`. The maps follow the lights, each its
    size, its bias, its normal bias, its radius, its sixteen-float frame,
    its `ShadowMapType` and then its depths, row-major from the top, or
    under `VSM_SHADOW_MAP` its means and then its spreads; see
    `lights.shadow.ShadowMap`. A point light's cube holds its bulb's
    position, its near plane and its far plane where the frame would be,
    and six faces of depths. Each spot light carries a fifteenth float:
    where its map begins, or `NO_SHADOW`. The maps follow the shadow maps,
    each the texture's slot in the texture table, the normal bias and the
    sixteen-float frame; see `lights.shadow.SpotLightMap`.

    Returns:
        `LIGHTS_FIRST + 7 * count + 9 * point_count + 9 * hemisphere_count
        + 15 * spot_count + 12 * rect_count` floats, then the two LTC
        tables when `rect_count` is not zero, then the shadow maps, then
        the spot light maps.
    """
    var flat = List[Float32]()
    # Where each shadow map will begin, worked out before the lights that
    # name them are written.
    var starts = List[Int]()
    var next = (
        LIGHTS_FIRST
        + lighting.count() * DIRECTIONAL_FLOATS
        + lighting.point_count() * POINT_FLOATS
        + lighting.hemisphere_count() * HEMISPHERE_FLOATS
        + lighting.spot_count() * SPOT_FLOATS
        + lighting.rect_count() * RECT_FLOATS
    )
    if lighting.rect_count() > 0:
        next += 2 * LTC_FLOATS
    for slot in range(len(lighting.shadows)):
        starts.append(next)
        next += SHADOW_HEADER + len(lighting.shadows[slot].depths)
    var map_starts = List[Int]()
    for _ in range(len(lighting.spot_maps)):
        map_starts.append(next)
        next += SPOT_MAP_FLOATS
    flat.append(lighting.eye.x)
    flat.append(lighting.eye.y)
    flat.append(lighting.eye.z)
    flat.append(lighting.toward_eye.x)
    flat.append(lighting.toward_eye.y)
    flat.append(lighting.toward_eye.z)
    flat.append(lighting.up.x)
    flat.append(lighting.up.y)
    flat.append(lighting.up.z)
    flat.append(lighting.ambient.r)
    flat.append(lighting.ambient.g)
    flat.append(lighting.ambient.b)
    flat.append(lighting.scale)
    flat.append(Float32(lighting.rect_count()))
    for lane in range(SH_COUNT * 3):  # pragma: no branch
        flat.append(lighting.probe.lanes[lane])
    for index in range(lighting.count()):
        ref direction = lighting.directions[index]
        flat.append(direction.x)
        flat.append(direction.y)
        flat.append(direction.z)
        ref radiance = lighting.radiances[index]
        flat.append(radiance.r)
        flat.append(radiance.g)
        flat.append(radiance.b)
        flat.append(_shadow_start(starts, lighting.direction_shadows[index]))
    for index in range(lighting.point_count()):
        ref position = lighting.positions[index]
        flat.append(position.x)
        flat.append(position.y)
        flat.append(position.z)
        ref radiance = lighting.point_radiances[index]
        flat.append(radiance.r)
        flat.append(radiance.g)
        flat.append(radiance.b)
        flat.append(lighting.decays[index])
        flat.append(lighting.cutoffs[index])
        flat.append(_shadow_start(starts, lighting.point_shadows[index]))
    for index in range(lighting.hemisphere_count()):
        ref up = lighting.sky_directions[index]
        flat.append(up.x)
        flat.append(up.y)
        flat.append(up.z)
        ref sky = lighting.skies[index]
        flat.append(sky.r)
        flat.append(sky.g)
        flat.append(sky.b)
        ref ground = lighting.grounds[index]
        flat.append(ground.r)
        flat.append(ground.g)
        flat.append(ground.b)
    for index in range(lighting.spot_count()):
        ref position = lighting.spot_positions[index]
        flat.append(position.x)
        flat.append(position.y)
        flat.append(position.z)
        ref axis = lighting.spot_directions[index]
        flat.append(axis.x)
        flat.append(axis.y)
        flat.append(axis.z)
        ref radiance = lighting.spot_radiances[index]
        flat.append(radiance.r)
        flat.append(radiance.g)
        flat.append(radiance.b)
        flat.append(lighting.spot_decays[index])
        flat.append(lighting.spot_cutoffs[index])
        flat.append(lighting.cone_cosines[index])
        flat.append(lighting.penumbra_cosines[index])
        flat.append(_shadow_start(starts, lighting.spot_shadows[index]))
        flat.append(_shadow_start(map_starts, lighting.spot_map_slots[index]))
    for index in range(lighting.rect_count()):
        ref center = lighting.rect_positions[index]
        flat.append(center.x)
        flat.append(center.y)
        flat.append(center.z)
        ref half_width = lighting.rect_half_widths[index]
        flat.append(half_width.x)
        flat.append(half_width.y)
        flat.append(half_width.z)
        ref half_height = lighting.rect_half_heights[index]
        flat.append(half_height.x)
        flat.append(half_height.y)
        flat.append(half_height.z)
        ref glow = lighting.rect_radiances[index]
        flat.append(glow.r)
        flat.append(glow.g)
        flat.append(glow.b)
    if lighting.rect_count() > 0:
        for at in range(LTC_FLOATS):
            flat.append(lighting.ltc.first[at])
        for at in range(LTC_FLOATS):
            flat.append(lighting.ltc.second[at])
    for slot in range(len(lighting.shadows)):
        ref map = lighting.shadows[slot]
        flat.append(Float32(map.size))
        flat.append(map.bias)
        flat.append(map.normal_bias)
        flat.append(map.radius)
        var frame = map.frame
        if map.cube:
            frame[0] = map.origin.x
            frame[1] = map.origin.y
            frame[2] = map.origin.z
            frame[3] = map.near
            frame[4] = map.far
        for element in range(16):  # pragma: no branch
            flat.append(frame[element])
        flat.append(Float32(map.shadow_type.value))
        for texel in range(len(map.depths)):
            flat.append(map.depths[texel])
    for slot in range(len(lighting.spot_maps)):
        ref picture = lighting.spot_maps[slot]
        flat.append(Float32(picture.texture.value))
        flat.append(picture.normal_bias)
        for element in range(16):  # pragma: no branch
            flat.append(picture.frame[element])
    return flat^


def _shadow_start(starts: List[Int], slot: Int) -> Float32:
    """Return where a light's shadow map begins in the buffer, or
    `NO_SHADOW` for a light that drew none."""
    if slot < 0:
        return NO_SHADOW
    return Float32(starts[slot])


def _shadow_at(
    lights: MutPointer[Float32, MutAnyOrigin],
    block: Int,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return how much of one light reaches a surface past its shadow
    map: the device counterpart of `ShadowMap.lit`, from the same
    functions under each `ShadowMapType`, held to the same answer by the
    parity tests.

    `block` is where the map begins in the light buffer, as
    `flatten_lights` laid it out.
    """
    var size = Int(lights[unsafe_offset=block])
    var bias = lights[unsafe_offset=block + 1]
    var normal_bias = lights[unsafe_offset=block + 2]
    var radius = lights[unsafe_offset=block + 3]
    var frame = SIMD[DType.float32, 16](0)
    for element in range(16):
        frame[element] = lights[unsafe_offset=block + 4 + element]
    var place = shadow_coordinate(
        frame, biased_position(position, normal, normal_bias)
    )
    if not inside_shadow_map(place):
        return 1
    var depths = block + SHADOW_HEADER
    var kind = Int(lights[unsafe_offset=block + SHADOW_TYPE_AT])
    if kind == BASIC_SHADOW_MAP.value:
        return shadow_tap(
            lights[
                unsafe_offset=depths + shadow_texel(place, CENTER_TAP, 0, size)
            ],
            place.z,
            bias,
        )
    if kind == PCF_SOFT_SHADOW_MAP.value:
        var taps = SIMD[DType.float32, SOFT_TAPS](0)
        for tap in range(SOFT_TAPS):
            taps[tap] = shadow_tap(
                lights[unsafe_offset=depths + soft_texel(place, tap, size)],
                place.z,
                bias,
            )
        return soft_shadow(
            taps, soft_fraction(place.x, size), soft_fraction(place.y, size)
        )
    if kind == VSM_SHADOW_MAP.value:
        var across = place.x * Float32(size)
        var down = place.y * Float32(size)
        var corners = SIMD[DType.float32, 8](0)
        for corner in range(4):
            var texel = bilinear_texel(across, down, corner, size)
            corners[corner] = lights[unsafe_offset=depths + texel]
            corners[corner + 4] = lights[
                unsafe_offset=depths + size * size + texel
            ]
        return vsm_shadow(
            bilinear(corners, 0, across, down),
            bilinear(corners, 4, across, down),
            place.z + bias,
        )
    var total = Float32(0)
    for tap in range(PCF_TAPS):
        var texel = shadow_texel(place, tap, radius, size)
        total += shadow_tap(
            lights[unsafe_offset=block + SHADOW_HEADER + texel], place.z, bias
        )
    return total / Float32(PCF_TAPS)


def _cube_shadow_at(
    lights: MutPointer[Float32, MutAnyOrigin],
    block: Int,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return how much of a point light reaches a surface past its cube:
    the device counterpart of `ShadowMap.lit` on a cube, from the same
    functions in the same order.

    `block` is where the cube begins in the light buffer, as
    `flatten_lights` laid it out.
    """
    var size = Int(lights[unsafe_offset=block])
    var bias = lights[unsafe_offset=block + 1]
    var normal_bias = lights[unsafe_offset=block + 2]
    var radius = lights[unsafe_offset=block + 3]
    var near = lights[unsafe_offset=block + 7]
    var far = lights[unsafe_offset=block + 8]
    var away = biased_position(position, normal, normal_bias)
    var toward = Vector3(
        away.x - lights[unsafe_offset=block + 4],
        away.y - lights[unsafe_offset=block + 5],
        away.z - lights[unsafe_offset=block + 6],
    )
    var distance = toward.length()
    if not inside_point_shadow(distance, near, far):
        return 1
    var depth = point_shadow_depth(distance, near, far) + (bias)
    var way = Vector3(
        toward.x / distance, toward.y / distance, toward.z / distance
    )
    if Int(lights[unsafe_offset=block + SHADOW_TYPE_AT]) == (
        BASIC_SHADOW_MAP.value
    ):
        return cube_tap(
            lights[unsafe_offset=block + SHADOW_HEADER + cube_texel(way, size)],
            depth,
        )
    var spread = point_shadow_spread(radius, size)
    var total = Float32(0)
    for tap in range(PCF_TAPS):
        var texel = cube_texel(point_shadow_tap(way, tap, spread), size)
        total += cube_tap(
            lights[unsafe_offset=block + SHADOW_HEADER + texel], depth
        )
    return total / Float32(PCF_TAPS)


def _point_through(
    lights: MutPointer[Float32, MutAnyOrigin],
    at: Int,
    receives: Bool,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return what a point light's cube lets through to a surface: the
    device counterpart of `Lighting.shadow_at` for a point light, reading
    the cube's start from the light's own record at `at`."""
    var block = lights[unsafe_offset=at]
    if block < 0 or not receives:
        return 1
    return _cube_shadow_at(lights, Int(block), position, normal)


def _spot_tint(
    lights: MutPointer[Float32, MutAnyOrigin],
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    at: Int,
    position: Vector3,
    normal: Vector3,
) -> Vector3:
    """Return what a spot light's color is multiplied by at a surface:
    the device counterpart of `Lighting.spot_tint`, reading the map's
    start from the light's own record at `at` and the picture from the
    texture buffer, at its full size, as `SpotLightMap.tint` reads it."""
    var block = lights[unsafe_offset=at]
    if block < 0:
        return Vector3(1, 1, 1)
    var start = Int(block)
    var frame = SIMD[DType.float32, 16](0)
    for element in range(16):
        frame[element] = lights[unsafe_offset=start + 2 + element]
    var place = shadow_coordinate(
        frame,
        biased_position(position, normal, lights[unsafe_offset=start + 1]),
    )
    if not inside_spot_map(place):
        return Vector3(1, 1, 1)
    var color = _sample_at(
        texels,
        ramp,
        _describe(table, Int(lights[unsafe_offset=start])),
        place.x,
        1 - place.y,
        0,
    )
    return Vector3(color.r, color.g, color.b)


def _through(
    lights: MutPointer[Float32, MutAnyOrigin],
    at: Int,
    receives: Bool,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return what one light's shadow lets through to a surface: the
    device counterpart of `Lighting.shadow_at`, reading the map's start
    from the light's own record at `at`."""
    var block = lights[unsafe_offset=at]
    if block < 0 or not receives:
        return 1
    return _shadow_at(lights, Int(block), position, normal)


def _shadow_mask(
    lights: MutPointer[Float32, MutAnyOrigin],
    count: Int,
    points: Int,
    hemispheres: Int,
    spots: Int,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return how much of every shadowing light reaches a surface: the
    device counterpart of `Lighting.shadow_mask`."""
    var mask = Float32(1)
    for index in range(count):
        var at = LIGHTS_FIRST + index * DIRECTIONAL_FLOATS
        mask *= _through(lights, at + 6, True, position, normal)
    var first_spot = (
        LIGHTS_FIRST
        + count * DIRECTIONAL_FLOATS
        + points * POINT_FLOATS
        + hemispheres * HEMISPHERE_FLOATS
    )
    for index in range(spots):
        var at = first_spot + index * SPOT_FLOATS
        mask *= _through(lights, at + 13, True, position, normal)
    for index in range(points):
        var at = (
            LIGHTS_FIRST + count * DIRECTIONAL_FLOATS + index * POINT_FLOATS
        )
        mask *= _point_through(lights, at + 8, True, position, normal)
    return mask


def flatten_fog(fog: FogView) -> List[Float32]:
    """Return a fog view as the flat float buffer the kernel reads.

    Args:
        fog: The scene's fog, as the rasterizers take it.

    Returns:
        `FOG_FLOATS` floats, in the order the kernel unpacks them. The
        kind is not among them: it crosses as a kernel argument of its own.
    """
    var flat = List[Float32]()
    flat.append(fog.near)
    flat.append(fog.far)
    flat.append(fog.density)
    flat.append(fog.color.r)
    flat.append(fog.color.g)
    flat.append(fog.color.b)
    return flat^


def _ambient_at(
    lights: MutPointer[Float32, MutAnyOrigin],
    nx: Float32,
    ny: Float32,
    nz: Float32,
) -> Vector3:
    """Return the ambient term and the light probes' irradiance at a
    normal: the device counterpart of `Lighting.ambient_at`, summed in its
    order, the probes' nine terms first and then the ambient color."""
    var normal = Vector3(nx, ny, nz)
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    for index in range(SH_COUNT):
        var weight = sh_irradiance_weight(index, normal)
        var at = LIGHTS_PROBE + index * 3
        red = red + lights[unsafe_offset=at] * weight
        green = green + lights[unsafe_offset=at + 1] * weight
        blue = blue + lights[unsafe_offset=at + 2] * weight
    return Vector3(
        lights[unsafe_offset=LIGHTS_AMBIENT] + red,
        lights[unsafe_offset=LIGHTS_AMBIENT + 1] + green,
        lights[unsafe_offset=LIGHTS_AMBIENT + 2] + blue,
    )


def _arriving(
    lights: MutPointer[Float32, MutAnyOrigin],
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    count: Int,
    points: Int,
    hemispheres: Int,
    spots: Int,
    nx: Float32,
    ny: Float32,
    nz: Float32,
    px: Float32,
    py: Float32,
    pz: Float32,
    receives: Bool = True,
) -> Vector3:
    """Return the light reaching a surface at (px, py, pz) facing (nx, ny, nz).

    The device counterpart of `Lighting.intensity_at`, and held to the same
    answer by the parity tests. A `Vector3` only because the kernel has no
    color type; the three components are red, green and blue.
    """
    var base = _ambient_at(lights, nx, ny, nz)
    var red = base.x
    var green = base.y
    var blue = base.z
    for index in range(count):
        var at = LIGHTS_FIRST + index * DIRECTIONAL_FLOATS
        var lambert = (
            nx * lights[unsafe_offset=at]
            + ny * lights[unsafe_offset=at + 1]
            + nz * lights[unsafe_offset=at + 2]
        )
        if lambert <= 0:
            continue
        lambert *= _through(
            lights, at + 6, receives, Vector3(px, py, pz), Vector3(nx, ny, nz)
        )
        red += lights[unsafe_offset=at + 3] * lambert
        green += lights[unsafe_offset=at + 4] * lambert
        blue += lights[unsafe_offset=at + 5] * lambert
    var first_point = LIGHTS_FIRST + count * DIRECTIONAL_FLOATS
    for index in range(points):
        var at = first_point + index * POINT_FLOATS
        # From the surface to the bulb: how far, and which way.
        var dx = lights[unsafe_offset=at] - px
        var dy = lights[unsafe_offset=at + 1] - py
        var dz = lights[unsafe_offset=at + 2] - pz
        var distance = sqrt(dx * dx + dy * dy + dz * dz)
        if distance == 0:
            continue
        var lambert = (nx * dx + ny * dy + nz * dz) / distance
        if lambert <= 0:
            continue
        var reach = (
            lambert
            * falloff(
                distance,
                lights[unsafe_offset=at + 6],
                lights[unsafe_offset=at + 7],
            )
            * _point_through(
                lights,
                at + 8,
                receives,
                Vector3(px, py, pz),
                Vector3(nx, ny, nz),
            )
        )
        red += lights[unsafe_offset=at + 3] * reach
        green += lights[unsafe_offset=at + 4] * reach
        blue += lights[unsafe_offset=at + 5] * reach
    var first_sky = first_point + points * POINT_FLOATS
    for index in range(hemispheres):
        var at = first_sky + index * HEMISPHERE_FLOATS
        # How far the surface is turned toward the sky, then ground to sky
        # by that weight, exactly as `Lighting.intensity_at` mixes them.
        var weight = (
            0.5
            * (
                nx * lights[unsafe_offset=at]
                + ny * lights[unsafe_offset=at + 1]
                + nz * lights[unsafe_offset=at + 2]
            )
            + 0.5
        )
        var lift_r = (
            lights[unsafe_offset=at + 6]
            + (lights[unsafe_offset=at + 3] - lights[unsafe_offset=at + 6])
            * weight
        )
        var lift_g = (
            lights[unsafe_offset=at + 7]
            + (lights[unsafe_offset=at + 4] - lights[unsafe_offset=at + 7])
            * weight
        )
        var lift_b = (
            lights[unsafe_offset=at + 8]
            + (lights[unsafe_offset=at + 5] - lights[unsafe_offset=at + 8])
            * weight
        )
        red += lift_r
        green += lift_g
        blue += lift_b
    var first_spot = first_sky + hemispheres * HEMISPHERE_FLOATS
    for index in range(spots):
        var at = first_spot + index * SPOT_FLOATS
        var dx = lights[unsafe_offset=at] - px
        var dy = lights[unsafe_offset=at + 1] - py
        var dz = lights[unsafe_offset=at + 2] - pz
        var distance = sqrt(dx * dx + dy * dy + dz * dz)
        if distance == 0:
            continue
        # The cosine of the angle off the cone's axis, and from it how far
        # inside the cone this is -- the host's arithmetic, in its order.
        var angle_cos = (
            dx * lights[unsafe_offset=at + 3]
            + dy * lights[unsafe_offset=at + 4]
            + dz * lights[unsafe_offset=at + 5]
        ) / distance
        var rim = smoothstep(
            lights[unsafe_offset=at + 11],
            lights[unsafe_offset=at + 12],
            angle_cos,
        )
        if rim <= 0:
            continue
        var lambert = (nx * dx + ny * dy + nz * dz) / distance
        if lambert <= 0:
            continue
        var reach = (
            lambert
            * rim
            * falloff(
                distance,
                lights[unsafe_offset=at + 9],
                lights[unsafe_offset=at + 10],
            )
            * _through(
                lights,
                at + 13,
                receives,
                Vector3(px, py, pz),
                Vector3(nx, ny, nz),
            )
        )
        var tint = _spot_tint(
            lights,
            texels,
            ramp,
            table,
            at + 14,
            Vector3(px, py, pz),
            Vector3(nx, ny, nz),
        )
        red += lights[unsafe_offset=at + 6] * tint.x * reach
        green += lights[unsafe_offset=at + 7] * tint.y * reach
        blue += lights[unsafe_offset=at + 8] * tint.z * reach
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    return Vector3(red * scale, green * scale, blue * scale)


def _toon_tone(
    texels: MutPointer[UInt8, MutAnyOrigin],
    start: Int,
    tones: Int,
    dot_nl: Float32,
) -> Float32:
    """Return how lit a `TOON` surface looks at this cosine.

    The device counterpart of `lights.lighting.toon_tone`: the same three
    shared functions, reading the ramp out of the device texel buffer
    rather than out of a list. The host reads texel (x, 0) of the gradient
    map and this reads the same byte of the same row, so the two cannot
    step at different places.

    Args:
        texels: Every texture's bytes end to end.
        start: Where this triangle's ramp begins in them.
        tones: How many texels across the ramp is, or zero for none.
        dot_nl: The cosine between the normal and the way to the light.

    Returns:
        How lit the surface looks, from zero to one.
    """
    var coord = toon_coord(dot_nl)
    if tones <= 0:
        return toon_step(coord)
    return (
        Float32(texels[unsafe_offset=start + toon_index(coord, tones) * 4])
        / 255
    )


def _toon_arriving(
    lights: MutPointer[Float32, MutAnyOrigin],
    count: Int,
    points: Int,
    hemispheres: Int,
    spots: Int,
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    start: Int,
    tones: Int,
    nx: Float32,
    ny: Float32,
    nz: Float32,
    px: Float32,
    py: Float32,
    pz: Float32,
    receives: Bool = True,
) -> Vector3:
    """Return the light reaching a `TOON` surface at (px, py, pz).

    The device counterpart of `Lighting.toon_at`, and held to the same
    answer by the parity tests. Every cosine a light makes is read off the
    ramp instead of used directly, and never clamped at zero, so a lamp
    behind the surface still lights it to the ramp's left end. The ambient
    term and the hemisphere lights are not stepped, because three.js
    reflects those through `RE_IndirectDiffuse`.
    """
    var base = _ambient_at(lights, nx, ny, nz)
    var red = base.x
    var green = base.y
    var blue = base.z
    for index in range(count):
        var at = LIGHTS_FIRST + index * DIRECTIONAL_FLOATS
        var tone = _toon_tone(
            texels,
            start,
            tones,
            nx * lights[unsafe_offset=at]
            + ny * lights[unsafe_offset=at + 1]
            + nz * lights[unsafe_offset=at + 2],
        )
        tone *= _through(
            lights, at + 6, receives, Vector3(px, py, pz), Vector3(nx, ny, nz)
        )
        red += lights[unsafe_offset=at + 3] * tone
        green += lights[unsafe_offset=at + 4] * tone
        blue += lights[unsafe_offset=at + 5] * tone
    var first_point = LIGHTS_FIRST + count * DIRECTIONAL_FLOATS
    for index in range(points):
        var at = first_point + index * POINT_FLOATS
        var dx = lights[unsafe_offset=at] - px
        var dy = lights[unsafe_offset=at + 1] - py
        var dz = lights[unsafe_offset=at + 2] - pz
        var distance = sqrt(dx * dx + dy * dy + dz * dz)
        if distance == 0:
            continue
        var tone = _toon_tone(
            texels, start, tones, (nx * dx + ny * dy + nz * dz) / distance
        )
        var reach = (
            tone
            * falloff(
                distance,
                lights[unsafe_offset=at + 6],
                lights[unsafe_offset=at + 7],
            )
            * _point_through(
                lights,
                at + 8,
                receives,
                Vector3(px, py, pz),
                Vector3(nx, ny, nz),
            )
        )
        red += lights[unsafe_offset=at + 3] * reach
        green += lights[unsafe_offset=at + 4] * reach
        blue += lights[unsafe_offset=at + 5] * reach
    var first_sky = first_point + points * POINT_FLOATS
    for index in range(hemispheres):
        var at = first_sky + index * HEMISPHERE_FLOATS
        # Indirect, so it is not stepped: the host's own sum, in its order.
        var weight = (
            0.5
            * (
                nx * lights[unsafe_offset=at]
                + ny * lights[unsafe_offset=at + 1]
                + nz * lights[unsafe_offset=at + 2]
            )
            + 0.5
        )
        var lift_r = (
            lights[unsafe_offset=at + 6]
            + (lights[unsafe_offset=at + 3] - lights[unsafe_offset=at + 6])
            * weight
        )
        var lift_g = (
            lights[unsafe_offset=at + 7]
            + (lights[unsafe_offset=at + 4] - lights[unsafe_offset=at + 7])
            * weight
        )
        var lift_b = (
            lights[unsafe_offset=at + 8]
            + (lights[unsafe_offset=at + 5] - lights[unsafe_offset=at + 8])
            * weight
        )
        red += lift_r
        green += lift_g
        blue += lift_b
    var first_spot = first_sky + hemispheres * HEMISPHERE_FLOATS
    for index in range(spots):
        var at = first_spot + index * SPOT_FLOATS
        var dx = lights[unsafe_offset=at] - px
        var dy = lights[unsafe_offset=at + 1] - py
        var dz = lights[unsafe_offset=at + 2] - pz
        var distance = sqrt(dx * dx + dy * dy + dz * dz)
        if distance == 0:
            continue
        var angle_cos = (
            dx * lights[unsafe_offset=at + 3]
            + dy * lights[unsafe_offset=at + 4]
            + dz * lights[unsafe_offset=at + 5]
        ) / distance
        var rim = smoothstep(
            lights[unsafe_offset=at + 11],
            lights[unsafe_offset=at + 12],
            angle_cos,
        )
        if rim <= 0:
            continue
        var tone = _toon_tone(
            texels, start, tones, (nx * dx + ny * dy + nz * dz) / distance
        )
        var reach = (
            tone
            * rim
            * falloff(
                distance,
                lights[unsafe_offset=at + 9],
                lights[unsafe_offset=at + 10],
            )
            * _through(
                lights,
                at + 13,
                receives,
                Vector3(px, py, pz),
                Vector3(nx, ny, nz),
            )
        )
        var tint = _spot_tint(
            lights,
            texels,
            ramp,
            table,
            at + 14,
            Vector3(px, py, pz),
            Vector3(nx, ny, nz),
        )
        red += lights[unsafe_offset=at + 6] * tint.x * reach
        green += lights[unsafe_offset=at + 7] * tint.y * reach
        blue += lights[unsafe_offset=at + 8] * tint.z * reach
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    return Vector3(red * scale, green * scale, blue * scale)


def _highlight(
    lights: MutPointer[Float32, MutAnyOrigin],
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    count: Int,
    points: Int,
    hemispheres: Int,
    spots: Int,
    nx: Float32,
    ny: Float32,
    nz: Float32,
    px: Float32,
    py: Float32,
    pz: Float32,
    specular: Vector3,
    shininess: Float32,
    receives: Bool = True,
) -> Vector3:
    """Return the highlight a `PHONG` surface sends toward the camera.

    The device counterpart of `Lighting.specular_at`, held to the same
    answer by the parity tests and summing the kinds in the same order.
    The ambient and hemisphere terms are absent from both: neither has a
    direction, so neither makes a highlight.
    """
    # One fixed direction under a parallel projection, and the way to the
    # camera's position under a converging one: the host's own function.
    var toward_eye = toward_eye_at(
        Vector3(
            lights[unsafe_offset=LIGHTS_EYE],
            lights[unsafe_offset=LIGHTS_EYE + 1],
            lights[unsafe_offset=LIGHTS_EYE + 2],
        ),
        Vector3(
            lights[unsafe_offset=LIGHTS_TOWARD],
            lights[unsafe_offset=LIGHTS_TOWARD + 1],
            lights[unsafe_offset=LIGHTS_TOWARD + 2],
        ),
        Vector3(px, py, pz),
    )
    if toward_eye.length() == 0:
        return Vector3(0, 0, 0)
    var normal = Vector3(nx, ny, nz)
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    for index in range(count):
        var at = LIGHTS_FIRST + index * DIRECTIONAL_FLOATS
        var toward = Vector3(
            lights[unsafe_offset=at],
            lights[unsafe_offset=at + 1],
            lights[unsafe_offset=at + 2],
        )
        var lambert = normal.dot(toward)
        if lambert <= 0:
            continue
        lambert *= _through(
            lights, at + 6, receives, Vector3(px, py, pz), normal
        )
        var sent = blinn_phong(toward, toward_eye, normal, specular, shininess)
        red += lights[unsafe_offset=at + 3] * lambert * sent.x
        green += lights[unsafe_offset=at + 4] * lambert * sent.y
        blue += lights[unsafe_offset=at + 5] * lambert * sent.z
    var first_point = LIGHTS_FIRST + count * DIRECTIONAL_FLOATS
    for index in range(points):
        var at = first_point + index * POINT_FLOATS
        var toward = Vector3(
            lights[unsafe_offset=at] - px,
            lights[unsafe_offset=at + 1] - py,
            lights[unsafe_offset=at + 2] - pz,
        )
        var distance = toward.length()
        if distance == 0:
            continue
        var lambert = normal.dot(toward) / distance
        if lambert <= 0:
            continue
        var reach = (
            lambert
            * falloff(
                distance,
                lights[unsafe_offset=at + 6],
                lights[unsafe_offset=at + 7],
            )
            * _point_through(
                lights, at + 8, receives, Vector3(px, py, pz), normal
            )
        )
        toward.normalize()
        var sent = blinn_phong(toward, toward_eye, normal, specular, shininess)
        red += lights[unsafe_offset=at + 3] * reach * sent.x
        green += lights[unsafe_offset=at + 4] * reach * sent.y
        blue += lights[unsafe_offset=at + 5] * reach * sent.z
    var first_spot = (
        first_point + points * POINT_FLOATS + hemispheres * HEMISPHERE_FLOATS
    )
    for index in range(spots):
        var at = first_spot + index * SPOT_FLOATS
        var toward = Vector3(
            lights[unsafe_offset=at] - px,
            lights[unsafe_offset=at + 1] - py,
            lights[unsafe_offset=at + 2] - pz,
        )
        var distance = toward.length()
        if distance == 0:
            continue
        var angle_cos = (
            toward.x * lights[unsafe_offset=at + 3]
            + toward.y * lights[unsafe_offset=at + 4]
            + toward.z * lights[unsafe_offset=at + 5]
        ) / distance
        var rim = smoothstep(
            lights[unsafe_offset=at + 11],
            lights[unsafe_offset=at + 12],
            angle_cos,
        )
        if rim <= 0:
            continue
        var lambert = normal.dot(toward) / distance
        if lambert <= 0:
            continue
        var reach = (
            lambert
            * rim
            * falloff(
                distance,
                lights[unsafe_offset=at + 9],
                lights[unsafe_offset=at + 10],
            )
            * _through(lights, at + 13, receives, Vector3(px, py, pz), normal)
        )
        toward.normalize()
        var sent = blinn_phong(toward, toward_eye, normal, specular, shininess)
        var tint = _spot_tint(
            lights, texels, ramp, table, at + 14, Vector3(px, py, pz), normal
        )
        red += lights[unsafe_offset=at + 6] * tint.x * reach * sent.x
        green += lights[unsafe_offset=at + 7] * tint.y * reach * sent.y
        blue += lights[unsafe_offset=at + 8] * tint.z * reach * sent.z
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    return Vector3(red * scale, green * scale, blue * scale)


def _world_at(
    corners: MutPointer[Float32, MutAnyOrigin],
    base: Int,
    ax: Int,
    ay: Int,
    bx: Int,
    by: Int,
    cx: Int,
    cy: Int,
    span_inv: Float32,
    swapped: Bool,
    px: Int,
    py: Int,
) -> Vector3:
    """Return the perspective-correct world position at a sample point:
    `_uv_at` for the world lanes, the device counterpart of
    `render.rasterizer._world_at`."""
    var b_base = base + FLOATS_PER_VERTEX
    var c_base = base + 2 * FLOATS_PER_VERTEX
    var e_ab = edge_at(ax, ay, bx, by, px, py)
    var e_bc = edge_at(bx, by, cx, cy, px, py)
    var e_ca = edge_at(cx, cy, ax, ay, px, py)
    var first = Float32(e_bc) * span_inv
    var second = Float32(e_ca) * span_inv
    var third = Float32(e_ab) * span_inv
    var wa = first
    var wb = second
    var wc = third
    if swapped:
        wb = third
        wc = second
    var aw = corners[unsafe_offset=base + LANE_INV_W]
    var bw = corners[unsafe_offset=b_base + LANE_INV_W]
    var cw = corners[unsafe_offset=c_base + LANE_INV_W]
    var inv_w = wa * aw + wb * bw + wc * cw
    var share_a = wa
    var share_b = wb
    var share_c = wc
    if inv_w != 0:
        var rcp = Float32(1) / inv_w
        share_a = wa * aw * rcp
        share_b = wb * bw * rcp
        share_c = wc * cw * rcp
    return Vector3(
        corners[unsafe_offset=base + LANE_WX] * share_a
        + corners[unsafe_offset=b_base + LANE_WX] * share_b
        + corners[unsafe_offset=c_base + LANE_WX] * share_c,
        corners[unsafe_offset=base + LANE_WY] * share_a
        + corners[unsafe_offset=b_base + LANE_WY] * share_b
        + corners[unsafe_offset=c_base + LANE_WY] * share_c,
        corners[unsafe_offset=base + LANE_WZ] * share_a
        + corners[unsafe_offset=b_base + LANE_WZ] * share_b
        + corners[unsafe_offset=c_base + LANE_WZ] * share_c,
    )


def _sample_cube_level(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    first: Int,
    direction: Vector3,
    level: Float32,
) -> FloatColor:
    """Sample a cube texture in a direction, `level` down its chain: the
    device counterpart of `CubeTexture.sample_level`."""
    var face = face_of(direction)
    var place = face_uv(face, direction)
    return _sample_level(
        texels, ramp, _describe(table, first + face), place.x, place.y, level
    )


def _sample_cube_rough(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    first: Int,
    direction: Vector3,
    roughness: Float32,
) -> FloatColor:
    """Return the environment a surface of some roughness reflects: the
    device counterpart of `CubeTexture.sample_rough`.

    The row after the six faces is the cube's PMREM when it holds floats,
    and then it is read at `cube_uv_taps`, the host's own arithmetic, and
    mixed as the host mixes it. Otherwise the faces are read down their
    chain at `reflection_level`."""
    var layout = _describe(table, first + FACE_COUNT)
    if layout.texel_type == FLOAT_TYPE:
        var taps = cube_uv_taps(
            direction, roughness, layout.width, layout.height
        )
        var near = _sample_at(texels, ramp, layout, taps.near.x, taps.near.y, 0)
        if taps.blend == 0:
            return FloatColor(near.r, near.g, near.b, 1.0)
        var far = _sample_at(texels, ramp, layout, taps.far.x, taps.far.y, 0)
        var mixed = mix_color(near, far, taps.blend)
        return FloatColor(mixed.r, mixed.g, mixed.b, 1.0)
    var levels = _describe(table, first).levels
    return _sample_cube_level(
        texels,
        ramp,
        table,
        first,
        direction,
        reflection_level(roughness, levels),
    )


def _indirect(
    lights: MutPointer[Float32, MutAnyOrigin],
    count: Int,
    points: Int,
    hemispheres: Int,
    nx: Float32,
    ny: Float32,
    nz: Float32,
) -> Vector3:
    """Return the light with no direction reaching a surface facing
    (nx, ny, nz): the device counterpart of `Lighting.indirect_at`."""
    var base = _ambient_at(lights, nx, ny, nz)
    var red = base.x
    var green = base.y
    var blue = base.z
    var first_sky = (
        LIGHTS_FIRST + count * DIRECTIONAL_FLOATS + points * POINT_FLOATS
    )
    for index in range(hemispheres):
        var at = first_sky + index * HEMISPHERE_FLOATS
        var weight = (
            0.5
            * (
                nx * lights[unsafe_offset=at]
                + ny * lights[unsafe_offset=at + 1]
                + nz * lights[unsafe_offset=at + 2]
            )
            + 0.5
        )
        var lift_r = (
            lights[unsafe_offset=at + 6]
            + (lights[unsafe_offset=at + 3] - lights[unsafe_offset=at + 6])
            * weight
        )
        var lift_g = (
            lights[unsafe_offset=at + 7]
            + (lights[unsafe_offset=at + 4] - lights[unsafe_offset=at + 7])
            * weight
        )
        var lift_b = (
            lights[unsafe_offset=at + 8]
            + (lights[unsafe_offset=at + 5] - lights[unsafe_offset=at + 8])
            * weight
        )
        red += lift_r
        green += lift_g
        blue += lift_b
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    return Vector3(red * scale, green * scale, blue * scale)


def _physical(
    lights: MutPointer[Float32, MutAnyOrigin],
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    count: Int,
    points: Int,
    hemispheres: Int,
    spots: Int,
    normal: Vector3,
    coat_normal: Vector3,
    position: Vector3,
    surface: Reflected,
    roughness: Float32,
    clearcoat: Float32,
    clearcoat_roughness: Float32,
    receives: Bool = True,
) -> Reflected:
    """Return what a physical surface sends toward the camera from the
    lights that have a direction: the device counterpart of
    `Lighting.physical_at`, held to the same answer by the parity tests
    and summing the kinds in the same order through the same
    `physical_light`."""
    var none = Reflected(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0))
    var toward_eye = toward_eye_at(
        Vector3(
            lights[unsafe_offset=LIGHTS_EYE],
            lights[unsafe_offset=LIGHTS_EYE + 1],
            lights[unsafe_offset=LIGHTS_EYE + 2],
        ),
        Vector3(
            lights[unsafe_offset=LIGHTS_TOWARD],
            lights[unsafe_offset=LIGHTS_TOWARD + 1],
            lights[unsafe_offset=LIGHTS_TOWARD + 2],
        ),
        position,
    )
    if toward_eye.length() == 0:
        return none
    var sum = none
    for index in range(count):
        var at = LIGHTS_FIRST + index * DIRECTIONAL_FLOATS
        var toward = Vector3(
            lights[unsafe_offset=at],
            lights[unsafe_offset=at + 1],
            lights[unsafe_offset=at + 2],
        )
        var lambert = max(Float32(0), normal.dot(toward))
        var coat_lambert = Float32(0)
        if clearcoat > 0:
            coat_lambert = max(Float32(0), coat_normal.dot(toward))
        if lambert == 0 and coat_lambert == 0:
            continue
        var through = _through(lights, at + 6, receives, position, normal)
        sum = physical_light(
            sum,
            Vector3(
                lights[unsafe_offset=at + 3] * through,
                lights[unsafe_offset=at + 4] * through,
                lights[unsafe_offset=at + 5] * through,
            ),
            lambert,
            coat_lambert,
            toward,
            toward_eye,
            normal,
            coat_normal,
            surface,
            roughness,
            clearcoat_roughness,
        )
    var first_point = LIGHTS_FIRST + count * DIRECTIONAL_FLOATS
    for index in range(points):
        var at = first_point + index * POINT_FLOATS
        var toward = Vector3(
            lights[unsafe_offset=at] - position.x,
            lights[unsafe_offset=at + 1] - position.y,
            lights[unsafe_offset=at + 2] - position.z,
        )
        var distance = toward.length()
        if distance == 0:
            continue
        var lambert = max(Float32(0), normal.dot(toward) / distance)
        var coat_lambert = Float32(0)
        if clearcoat > 0:
            coat_lambert = max(Float32(0), coat_normal.dot(toward) / distance)
        if lambert == 0 and coat_lambert == 0:
            continue
        var reach = falloff(
            distance, lights[unsafe_offset=at + 6], lights[unsafe_offset=at + 7]
        ) * _point_through(lights, at + 8, receives, position, normal)
        toward.normalize()
        sum = physical_light(
            sum,
            Vector3(
                lights[unsafe_offset=at + 3] * reach,
                lights[unsafe_offset=at + 4] * reach,
                lights[unsafe_offset=at + 5] * reach,
            ),
            lambert,
            coat_lambert,
            toward,
            toward_eye,
            normal,
            coat_normal,
            surface,
            roughness,
            clearcoat_roughness,
        )
    var first_spot = (
        first_point + points * POINT_FLOATS + hemispheres * HEMISPHERE_FLOATS
    )
    for index in range(spots):
        var at = first_spot + index * SPOT_FLOATS
        var toward = Vector3(
            lights[unsafe_offset=at] - position.x,
            lights[unsafe_offset=at + 1] - position.y,
            lights[unsafe_offset=at + 2] - position.z,
        )
        var distance = toward.length()
        if distance == 0:
            continue
        var angle_cos = (
            toward.x * lights[unsafe_offset=at + 3]
            + toward.y * lights[unsafe_offset=at + 4]
            + toward.z * lights[unsafe_offset=at + 5]
        ) / distance
        var rim = smoothstep(
            lights[unsafe_offset=at + 11],
            lights[unsafe_offset=at + 12],
            angle_cos,
        )
        if rim <= 0:
            continue
        var lambert = max(Float32(0), normal.dot(toward) / distance)
        var coat_lambert = Float32(0)
        if clearcoat > 0:
            coat_lambert = max(Float32(0), coat_normal.dot(toward) / distance)
        if lambert == 0 and coat_lambert == 0:
            continue
        var reach = (
            rim
            * falloff(
                distance,
                lights[unsafe_offset=at + 9],
                lights[unsafe_offset=at + 10],
            )
            * _through(lights, at + 13, receives, position, normal)
        )
        toward.normalize()
        var tint = _spot_tint(
            lights, texels, ramp, table, at + 14, position, normal
        )
        sum = physical_light(
            sum,
            Vector3(
                lights[unsafe_offset=at + 6] * tint.x * reach,
                lights[unsafe_offset=at + 7] * tint.y * reach,
                lights[unsafe_offset=at + 8] * tint.z * reach,
            ),
            lambert,
            coat_lambert,
            toward,
            toward_eye,
            normal,
            coat_normal,
            surface,
            roughness,
            clearcoat_roughness,
        )
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    var scaled = Reflected(
        sum.diffuse * scale, sum.specular * scale, sum.clearcoat * scale
    )
    # The rectangles after the scale, as `Lighting.physical_at` adds them:
    # one table lookup for the fragment, then every rectangle through it.
    var rects = Int(lights[unsafe_offset=LIGHTS_RECT_COUNT])
    if rects > 0:
        var first_rect = first_spot + spots * SPOT_FLOATS
        var first_table = first_rect + rects * RECT_FLOATS
        var dot_nv = max(Float32(0), min(Float32(1), normal.dot(toward_eye)))
        var uv = ltc_uv(dot_nv, roughness)
        var minv = _ltc_lookup(lights, first_table, uv)
        var fresnel = _ltc_lookup(lights, first_table + LTC_FLOATS, uv)
        var diffuse = scaled.diffuse
        var specular = scaled.specular
        for index in range(rects):
            var at = first_rect + index * RECT_FLOATS
            var added = rect_area_light(
                normal,
                toward_eye,
                position,
                Vector3(
                    lights[unsafe_offset=at],
                    lights[unsafe_offset=at + 1],
                    lights[unsafe_offset=at + 2],
                ),
                Vector3(
                    lights[unsafe_offset=at + 3],
                    lights[unsafe_offset=at + 4],
                    lights[unsafe_offset=at + 5],
                ),
                Vector3(
                    lights[unsafe_offset=at + 6],
                    lights[unsafe_offset=at + 7],
                    lights[unsafe_offset=at + 8],
                ),
                surface.diffuse,
                surface.specular,
                minv,
                fresnel,
            )
            diffuse = Vector3(
                diffuse.x + added.diffuse.x * lights[unsafe_offset=at + 9],
                diffuse.y + added.diffuse.y * lights[unsafe_offset=at + 10],
                diffuse.z + added.diffuse.z * lights[unsafe_offset=at + 11],
            )
            specular = Vector3(
                specular.x + added.specular.x * lights[unsafe_offset=at + 9],
                specular.y + added.specular.y * lights[unsafe_offset=at + 10],
                specular.z + added.specular.z * lights[unsafe_offset=at + 11],
            )
        scaled = Reflected(diffuse, specular, scaled.clearcoat)
    return scaled


def _ltc_texel(
    lights: MutPointer[Float32, MutAnyOrigin], at: Int
) -> SIMD[DType.float32, 4]:
    """Return the four floats of an LTC table from `at` in the buffer.

    Lane by lane: a `SIMD` built from four loads written straight into
    its constructor comes back all zero from the Metal compiler, while
    the same four loads assigned one lane at a time come back right.
    """
    var texel = SIMD[DType.float32, 4](0)
    for lane in range(4):  # pragma: no branch
        texel[lane] = lights[unsafe_offset=at + lane]
    return texel


def _ltc_lookup(
    lights: MutPointer[Float32, MutAnyOrigin], table: Int, uv: Vector2
) -> SIMD[DType.float32, 4]:
    """Return a table's four numbers at a coordinate, bilinearly
    filtered: the device counterpart of `ltc_lookup`, the same texels
    through the same `ltc_blend`."""
    var place = ltc_texel(uv)
    var column = Int(place[0])
    var row = Int(place[1])
    return ltc_blend(
        _ltc_texel(lights, table + ltc_neighbor(column, row)),
        _ltc_texel(lights, table + ltc_neighbor(column + 1, row)),
        _ltc_texel(lights, table + ltc_neighbor(column, row + 1)),
        _ltc_texel(lights, table + ltc_neighbor(column + 1, row + 1)),
        place[2],
        place[3],
    )


def _extent(extent: Int, level: Int) -> Int:
    """Return an image's size at `level`, never below one."""
    var at = extent >> level
    if at < 1:
        return 1
    return at


def _level_start(width: Int, height: Int, level: Int) -> Int:
    """Return where `level` begins, in bytes from the image's own start.

    The same walk `Texture.level_offset` does, for the same reason: the chain
    is stored end to end and a level's position is the sum of the sizes before
    it. Recomputed rather than tabulated so both sides derive it from the same
    two numbers and cannot drift.
    """
    var offset = 0
    for step in range(level):
        offset += _extent(width, step) * _extent(height, step) * 4
    return offset


@fieldwise_init
struct _Descriptor(ImplicitlyCopyable):
    """One texture's row of the table, as the sampler reads it.

    Read once per sample by `_describe` rather than carried through three
    helpers as seven arguments each, which is what this used to be.
    """

    var start: Int
    var width: Int
    var height: Int
    var wrap: Wrap
    var filter: Filter
    var space: ColorSpace
    var levels: Int
    var alpha: Alpha
    var anisotropy: Int
    var texel_type: TexelType


def _describe(table: MutPointer[Int32, MutAnyOrigin], slot: Int) -> _Descriptor:
    """Return texture `slot`'s row of the table, in the order
    `flatten_textures` wrote it."""
    var entry = slot * TABLE_COLUMNS
    return _Descriptor(
        Int(table[unsafe_offset=entry]),
        Int(table[unsafe_offset=entry + 1]),
        Int(table[unsafe_offset=entry + 2]),
        Wrap(Int(table[unsafe_offset=entry + 3])),
        Filter(Int(table[unsafe_offset=entry + 4])),
        ColorSpace(Int(table[unsafe_offset=entry + 5])),
        Int(table[unsafe_offset=entry + 6]),
        Alpha(Int(table[unsafe_offset=entry + 7])),
        Int(table[unsafe_offset=entry + 8]),
        TexelType(Int(table[unsafe_offset=entry + 9])),
    )


def _fetch(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    image: _Descriptor,
    x: Int,
    y: Int,
    level: Int,
) -> FloatColor:
    """Read one texel from the device buffer, decoded and wrapped.

    The device counterpart of `Texture.wrapped_texel`. Only the memory access
    differs between the two: the index arithmetic is `wrap_index`, shared; the
    decode is the same 256-entry table the host builds, uploaded once; and the
    blend on top of them is `blend`, also shared. Alpha is not color and is
    never decoded, and is not read at all when the texture ignores it, as
    `Texture._alpha_of` does not read it on the host.

    A float texture's channel is four bytes rather than one, so every
    position is four times as far into its image; the texel is then the
    four floats, read by `float_from_bytes` and made a color by
    `float_texel`, both shared with the host.
    """
    var wide = _extent(image.width, level)
    var tall = _extent(image.height, level)
    var channel = (
        _level_start(image.width, image.height, level)
        + (
            wrap_index(y, tall, image.wrap) * wide
            + wrap_index(x, wide, image.wrap)
        )
        * 4
    )
    if image.texel_type == FLOAT_TYPE:
        var at = image.start + channel * 4
        return float_texel(
            _float_at(texels, at),
            _float_at(texels, at + 4),
            _float_at(texels, at + 8),
            _float_at(texels, at + 12),
            image.alpha,
        )
    var offset = image.start + channel
    var alpha = Float32(texels[unsafe_offset=offset + 3]) / 255
    if image.alpha == IGNORED:
        alpha = 1
    # Asked the way the host asks it when it picks a ramp -- "is it SRGB?"
    # -- so a value that is neither reads as stored on both sides rather
    # than decoded on one.
    if image.space == SRGB:
        return FloatColor(
            ramp[unsafe_offset=Int(texels[unsafe_offset=offset])],
            ramp[unsafe_offset=Int(texels[unsafe_offset=offset + 1])],
            ramp[unsafe_offset=Int(texels[unsafe_offset=offset + 2])],
            alpha,
        )
    return FloatColor(
        Float32(texels[unsafe_offset=offset]) / 255,
        Float32(texels[unsafe_offset=offset + 1]) / 255,
        Float32(texels[unsafe_offset=offset + 2]) / 255,
        alpha,
    )


def _float_at(texels: MutPointer[UInt8, MutAnyOrigin], at: Int) -> Float32:
    """Return the float whose four little-endian bytes start at `at`."""
    return float_from_bytes(
        texels[unsafe_offset=at],
        texels[unsafe_offset=at + 1],
        texels[unsafe_offset=at + 2],
        texels[unsafe_offset=at + 3],
    )


def line_state(corners: List[RasterVertex], line_width: Int = 1) -> List[Int32]:
    """Return each segment's blend policy and width, `STATE_PER_LINE`
    entries each.

    A line carries far less per-primitive state than a triangle: it is
    unlit and untextured, so whether it composites is the only thing the
    kernel cannot read off a vertex. It is still a table rather than a
    float lane, for the reason the triangles' is -- a policy that decides
    both how a color is combined and whether depth is written is not an
    attribute to interpolate. The width rides beside it, the same on every
    segment of a frame, so the kernel needs no argument for it.

    Args:
        corners: Raster vertices, two per segment.
        line_width: How many pixels across every segment is drawn, never
            below one.

    Returns:
        The blend policy, the width, then the packed depth, color and
        stencil state per segment, from its first end.
    """
    var state = List[Int32]()
    for segment in range(len(corners) // 2):
        state.append(Int32(corners[segment * 2].blend.value))
        state.append(Int32(line_width))
        state.append(Int32(corners[segment * 2].state.ops_word()))
        state.append(Int32(corners[segment * 2].state.stencil_word()))
    return state^


def point_state(points: List[RasterVertex]) -> List[Int32]:
    """Return each point's texture, blend policy and alpha map,
    `STATE_PER_POINT` entries each.

    A table rather than three lanes, for the reason the triangles' is: a
    resource id crossed as a float loses exactness, and a policy that
    decides whether depth is written is not an attribute.

    Args:
        points: Raster vertices, one per point.

    Returns:
        Texture id, blend policy, alpha map id, then the packed depth,
        color and stencil state, per point.
    """
    var state = List[Int32]()
    for point in range(len(points)):
        state.append(Int32(points[point].texture.value))
        state.append(Int32(points[point].blend.value))
        state.append(Int32(points[point].alpha_map.value))
        state.append(Int32(points[point].state.ops_word()))
        state.append(Int32(points[point].state.stencil_word()))
    return state^


def triangle_state(
    corners: List[RasterVertex], cube_base: Int = 0
) -> List[Int32]:
    """Return each triangle's texture, blend policy, material kind and
    emissive map, `STATE_PER_TRIANGLE` entries each.

    Neither is a vertex attribute. A resource id was one for a commit —
    carried on all three corners, crossed as a `Float32`, read back from the
    first — which is to say it was already per-triangle in a per-vertex
    costume, and losing exactness above 2^24 on the way. Whether a surface
    composites is the same kind of thing, and worse to infer: it decides both
    how the color is combined *and* whether depth is written, so guessing it
    from a float alpha in one place and a material in another is how the two
    came to disagree.

    Args:
        corners: Raster vertices, three per triangle.
        cube_base: The table row the first cube texture's first face is
            on: how many flat textures were uploaded before the cubes.

    Returns:
        Texture id, blend policy, the material kind's value, the emissive
        map id, the alpha map id, the gradient map id, the matcap id, the
        row of the env map's first face or -1 for none, then the combine's
        value, then the roughness, metalness, normal and bump map ids, then
        one or zero for whether the shadows fall on it, then the packed
        depth, color and stencil state, then the ao and light map ids,
        then the specular map id, per triangle, from its first corner.
    """
    var state = List[Int32]()
    for triangle in range(len(corners) // 3):
        state.append(Int32(corners[triangle * 3].texture.value))
        state.append(Int32(corners[triangle * 3].blend.value))
        state.append(Int32(corners[triangle * 3].kind.value))
        state.append(Int32(corners[triangle * 3].emissive_map.value))
        state.append(Int32(corners[triangle * 3].alpha_map.value))
        state.append(Int32(corners[triangle * 3].gradient_map.value))
        state.append(Int32(corners[triangle * 3].matcap.value))
        var cube = corners[triangle * 3].env_map
        var row = -1
        if cube != NO_CUBE_TEXTURE:
            row = cube_base + cube.value * CUBE_ROWS
        state.append(Int32(row))
        state.append(Int32(corners[triangle * 3].combine.value))
        state.append(Int32(corners[triangle * 3].roughness_map.value))
        state.append(Int32(corners[triangle * 3].metalness_map.value))
        state.append(Int32(corners[triangle * 3].normal_map.value))
        state.append(Int32(corners[triangle * 3].bump_map.value))
        state.append(Int32(1 if corners[triangle * 3].receives_shadow else 0))
        state.append(Int32(corners[triangle * 3].state.ops_word()))
        state.append(Int32(corners[triangle * 3].state.stencil_word()))
        state.append(Int32(corners[triangle * 3].ao_map.value))
        state.append(Int32(corners[triangle * 3].light_map.value))
        state.append(Int32(corners[triangle * 3].specular_map.value))
    return state^


def _decoded(
    ramp: MutPointer[Float32, MutAnyOrigin], r: Float32, g: Float32, b: Float32
) -> FloatColor:
    """Return three channels of data as the light that encodes to their
    bytes: the device counterpart of `render.rasterizer.data_color`.

    Quantized to bytes without the curve, then decoded through the uploaded
    ramp, which holds the same 256 values the host's decode computes, so
    the two backends store the same light and resolve to the same bytes.
    Alpha is not touched and is left to the caller.
    """
    var bytes = FloatColor(r, g, b, 1.0).quantize()
    return FloatColor(
        ramp[unsafe_offset=Int(bytes.r)],
        ramp[unsafe_offset=Int(bytes.g)],
        ramp[unsafe_offset=Int(bytes.b)],
        1.0,
    )


def _uv_at(
    corners: MutPointer[Float32, MutAnyOrigin],
    base: Int,
    ax: Int,
    ay: Int,
    bx: Int,
    by: Int,
    cx: Int,
    cy: Int,
    span_inv: Float32,
    swapped: Bool,
    px: Int,
    py: Int,
    lane: Int = LANE_U,
) -> Vector2:
    """Return the perspective-correct texture coordinates at a sample point.

    Coverage is not tested: this is called for the pixels either side, which
    are routinely outside the triangle. Barycentric coordinates extrapolate
    perfectly well; it is only coverage that stops at the edge. That is what
    replaces the helper invocations a hardware quad would need. `lane` is
    the first of the pair to read: `LANE_U`, or `LANE_U1` for the second
    coordinates, as `render.rasterizer._coordinates_at` takes `second`.
    """
    var b_base = base + FLOATS_PER_VERTEX
    var c_base = base + 2 * FLOATS_PER_VERTEX
    var e_ab = edge_at(ax, ay, bx, by, px, py)
    var e_bc = edge_at(bx, by, cx, cy, px, py)
    var e_ca = edge_at(cx, cy, ax, ay, px, py)
    var first = Float32(e_bc) * span_inv
    var second = Float32(e_ca) * span_inv
    var third = Float32(e_ab) * span_inv
    var wa = first
    var wb = second
    var wc = third
    if swapped:
        wb = third
        wc = second

    var aw = corners[unsafe_offset=base + LANE_INV_W]
    var bw = corners[unsafe_offset=b_base + LANE_INV_W]
    var cw = corners[unsafe_offset=c_base + LANE_INV_W]
    var inv_w = wa * aw + wb * bw + wc * cw
    var share_a = wa
    var share_b = wb
    var share_c = wc
    if inv_w != 0:
        var rcp = Float32(1) / inv_w
        share_a = wa * aw * rcp
        share_b = wb * bw * rcp
        share_c = wc * cw * rcp
    return Vector2(
        corners[unsafe_offset=base + lane] * share_a
        + corners[unsafe_offset=b_base + lane] * share_b
        + corners[unsafe_offset=c_base + lane] * share_c,
        corners[unsafe_offset=base + lane + 1] * share_a
        + corners[unsafe_offset=b_base + lane + 1] * share_b
        + corners[unsafe_offset=c_base + lane + 1] * share_c,
    )


def _sample_at(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    image: _Descriptor,
    u: Float32,
    v: Float32,
    level: Int,
) -> FloatColor:
    """Sample one mip level, the device counterpart of `Texture.sample_at`."""
    var wide = _extent(image.width, level)
    var tall = _extent(image.height, level)
    if image.filter == NEAREST:
        return _fetch(
            texels,
            ramp,
            image,
            Int(floor(u * Float32(wide))),
            Int(floor((1 - v) * Float32(tall))),
            level,
        )
    # Texel centers sit at half-integers; see Texture.sample.
    var across = u * Float32(wide) - 0.5
    var down = (1 - v) * Float32(tall) - 0.5
    var column = Int(floor(across))
    var row = Int(floor(down))
    return blend_texels(
        _fetch(texels, ramp, image, column, row, level),
        _fetch(texels, ramp, image, column + 1, row, level),
        _fetch(texels, ramp, image, column, row + 1, level),
        _fetch(texels, ramp, image, column + 1, row + 1, level),
        across - Float32(column),
        down - Float32(row),
    )


def _sample_level(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    image: _Descriptor,
    u: Float32,
    v: Float32,
    level: Float32,
) -> FloatColor:
    """Trilinear across two mip levels, matching `Texture.sample_level`."""
    if image.levels == 1 or level <= 0:
        return _sample_at(texels, ramp, image, u, v, 0)
    if level >= Float32(image.levels - 1):
        return _sample_at(texels, ramp, image, u, v, image.levels - 1)
    var lower = Int(floor(level))
    var near = _sample_at(texels, ramp, image, u, v, lower)
    var far = _sample_at(texels, ramp, image, u, v, lower + 1)
    return mix_color(near, far, level - Float32(lower))


def _sample_cube(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    first: Int,
    direction: Vector3,
) -> FloatColor:
    """Sample a cube texture in a direction, the device counterpart of
    `CubeTexture.sample`.

    The six faces are six consecutive rows of the table from `first`, in
    `POSITIVE_X` through `NEGATIVE_Z` order, as `flatten_textures` laid
    them out. `face_of` picks the row and `face_uv` the place on it, both
    the host's own functions, and the face is read at its full size as the
    host reads it.
    """
    var face = face_of(direction)
    var place = face_uv(face, direction)
    return _sample_at(
        texels, ramp, _describe(table, first + face), place.x, place.y, 0
    )


def _sample_slot(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    slot: Int,
    corners: MutPointer[Float32, MutAnyOrigin],
    base: Int,
    ax: Int,
    ay: Int,
    bx: Int,
    by: Int,
    cx: Int,
    cy: Int,
    span_inv: Float32,
    swapped: Bool,
    px: Int,
    py: Int,
    u: Float32,
    v: Float32,
    lane: Int = LANE_U,
) -> FloatColor:
    """Sample texture `slot` at (u, v) for the pixel at (px, py).

    Every texture lives in one buffer end to end, so the table says where
    this one starts and how to read it. With one level there is no chain to
    choose from and so no footprint to measure; the CPU takes the same
    shortcut. Otherwise the level comes from where the coordinates land one
    pixel over and one down, evaluated from the triangle's own uv function
    rather than read from a neighboring thread -- see
    `render.rasterizer.mip_level`. Shared by the material's map and its
    emissive map, as `_sample_map` is on the host, so both are filtered
    alike on both sides. `lane` says which pair the footprint is measured
    on: `LANE_U`, or `LANE_U1` for an ambient occlusion map or a light map.
    """
    var image = _describe(table, slot)
    if image.levels == 1 and image.anisotropy == 1:
        return _sample_at(texels, ramp, image, u, v, 0)
    # The center from the same function as its neighbors, as
    # `render.rasterizer._sample_map` takes it, and for the same reason.
    var here = _uv_at(
        corners,
        base,
        ax,
        ay,
        bx,
        by,
        cx,
        cy,
        span_inv,
        swapped,
        px,
        py,
        lane,
    )
    var along_x = _uv_at(
        corners,
        base,
        ax,
        ay,
        bx,
        by,
        cx,
        cy,
        span_inv,
        swapped,
        px + SUBPIXEL,
        py,
        lane,
    )
    var along_y = _uv_at(
        corners,
        base,
        ax,
        ay,
        bx,
        by,
        cx,
        cy,
        span_inv,
        swapped,
        px,
        py + SUBPIXEL,
        lane,
    )
    # The level and the taps, from the host's own function, and v flipped
    # and wrapped by the same routine the host uses -- see render.texture.
    var footprint = anisotropic_footprint(
        Vector2(along_x.x - here.x, along_x.y - here.y),
        Vector2(along_y.x - here.x, along_y.y - here.y),
        image.width,
        image.height,
        image.anisotropy,
    )
    if footprint.taps == 1:
        return _sample_level(texels, ramp, image, u, v, footprint.level)
    # The taps along the long axis, averaged premultiplied, exactly as
    # `Texture.sample_footprint` averages them.
    var total = FloatColor(0.0, 0.0, 0.0, 0.0)
    for tap in range(footprint.taps):
        var along = Float32(tap) - Float32(footprint.taps - 1) / 2
        var sampled = _sample_level(
            texels,
            ramp,
            image,
            u + footprint.step.x * along,
            v + footprint.step.y * along,
            footprint.level,
        ).premultiplied()
        total = FloatColor(
            total.r + sampled.r,
            total.g + sampled.g,
            total.b + sampled.b,
            total.a + sampled.a,
        )
    var share = 1 / Float32(footprint.taps)
    return FloatColor(
        total.r * share, total.g * share, total.b * share, total.a * share
    ).unpremultiplied()


def rasterize_kernel(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    corners: MutPointer[Float32, MutAnyOrigin],
    maps: MutPointer[Int32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    background: UInt32,
    mode: Int32,
    texels: MutPointer[UInt8, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    lights: MutPointer[Float32, MutAnyOrigin],
    light_count: Int32,
    point_count: Int32,
    hemisphere_count: Int32,
    spot_count: Int32,
    fog: MutPointer[Float32, MutAnyOrigin],
    fog_kind: Int32,
    tone: Int32,
    exposure: Float32,
    segments: MutPointer[Float32, MutAnyOrigin],
    segment_maps: MutPointer[Int32, MutAnyOrigin],
    points: MutPointer[Float32, MutAnyOrigin],
    point_maps: MutPointer[Int32, MutAnyOrigin],
    draws: MutPointer[Int32, MutAnyOrigin],
    draw_count: Int32,
    scissor_x: Int32,
    scissor_y: Int32,
    scissor_width: Int32,
    scissor_height: Int32,
    backdrop: MutPointer[UInt8, MutAnyOrigin],
):
    """Color one pixel from the nearest primitive that covers it.

    The draws in the frame's order, each a run of triangles, of segments
    or of points, which is the order the host draws them in and the order
    that matters: a blended line has to mix over the surface behind it and
    under the one in front, and a line over an opaque surface has to test
    its depth against it. Both kinds composite into the same running
    color, in linear light, and the pixel is resolved once at the end --
    exactly as `Renderer.render` fills one target and resolves it once.
    """
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    # The grid is rounded up to whole tiles, so the edges overhang the image.
    if x >= Int(width) or y >= Int(height):
        return
    # A pixel outside the scissor is left as it was, depth included: not
    # cleared, not drawn. That is what a GPU's scissor test does to a
    # clear and to every fragment, and it is what lets two viewports share
    # one target. The host's target keeps the same pixels the same way.
    var scissor = Rect(
        Int(scissor_x), Int(scissor_y), Int(scissor_width), Int(scissor_height)
    )
    if not scissor.contains_pixel(x, y, Int(height)):
        return

    var px = sample(x)
    var py = sample(y)

    # Resolved by the material, not guessed at from an alpha. A debug view of
    # texture coordinates is always opaque: it shows the nearest surface's
    # coordinates, and averaging several surfaces' would mean nothing.
    # The depth the pixel holds: the nearest solid surface's under the
    # default depth function, and whatever the last depth write left under
    # another. Compared by `render.raster_state.test_fragment`, as the
    # host's target is.
    var nearest = FURTHEST
    var found = False
    # True once an *opaque* fragment has claimed this pixel's depth. A
    # translucent one tests depth without claiming it, exactly as on the host,
    # so the depth that comes back is the nearest solid surface.
    var solid = False
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    var alpha = Float32(0)
    # What the pixel holds so far, in *premultiplied* linear light — the
    # light it actually contributes, already scaled by its coverage. Starts as
    # the background decoded, so a translucent surface over nothing mixes with
    # the clear color rather than with black, and a transparent clear color
    # contributes nothing rather than black. See render.target.
    var mixed_a = Float32(background & 0xFF) / 255
    var mixed_r = ramp[unsafe_offset=Int((background >> 24) & 0xFF)] * mixed_a
    var mixed_g = ramp[unsafe_offset=Int((background >> 16) & 0xFF)] * mixed_a
    var mixed_b = ramp[unsafe_offset=Int((background >> 8) & 0xFF)] * mixed_a
    # A scene's image background, where it was painted: opaque bytes
    # decoded through the ramp, exactly as `Renderer.render_into` decodes
    # the same bytes into its target before it draws. A pixel the backdrop
    # left transparent keeps the clear color, and a frame with no backdrop
    # is handed a transparent buffer. Asked of the buffer rather than of a
    # flag, because Metal binds at most thirty-one arguments to a kernel
    # and this one has thirty-one. See `Renderer.backdrop`.
    var painted = (y * Int(width) + x) * 4
    if backdrop[unsafe_offset=painted + 3] == 255:
        mixed_r = ramp[unsafe_offset=Int(backdrop[unsafe_offset=painted])]
        mixed_g = ramp[unsafe_offset=Int(backdrop[unsafe_offset=painted + 1])]
        mixed_b = ramp[unsafe_offset=Int(backdrop[unsafe_offset=painted + 2])]
        mixed_a = 1
    # Whether the pixel holds data rather than light, decided by the last
    # fragment into it exactly as `RenderTarget.write` and `blend` decide
    # it: a normal or a depth, which the tone mapping must leave alone.
    var data = False
    # The pixel's stencil value, cleared to zero with the frame as
    # `RenderTarget.clear_inside` clears it, and changed only by a
    # primitive whose state has `stencil_write` on. A local and not a
    # buffer: one launch draws the whole frame, so nothing outlives it.
    var stencil = 0
    # Whether the fog can reach any fragment: never in the uv debug view,
    # exactly as `rasterize_shaded` decides it. A fragment that shows data
    # is left out below, per triangle.
    var fog_on = fog_kind != Int32(NO_FOG.value) and mode != Int32(
        SHADE_UV.value
    )

    for draw in range(Int(draw_count)):
        var kind = draws[unsafe_offset=draw * INTS_PER_DRAW]
        var first = Int(draws[unsafe_offset=draw * INTS_PER_DRAW + 1])
        var past = first + Int(draws[unsafe_offset=draw * INTS_PER_DRAW + 2])
        if kind == Int32(DRAW_POINTS.value):
            # A run of points. The question is "does this point cover me",
            # and `render.pointrule` answers it from the expression the
            # host walks its square with, so the two squares are the same
            # square. What follows is the triangle pass with nothing to
            # interpolate: one color, one depth, one fog depth, and a
            # coordinate of the point's own for the maps and the uv view.
            for index in range(first, past):
                var base = index * FLOATS_PER_VERTEX
                var center = Vector2(
                    points[unsafe_offset=base + LANE_X],
                    points[unsafe_offset=base + LANE_Y],
                )
                var size = points[unsafe_offset=base + LANE_POINT_SIZE]
                if not point_covers(center, size, x, y):
                    continue
                var z = points[unsafe_offset=base + LANE_Z]
                var threshold = points[unsafe_offset=base + LANE_ALPHA_TEST]
                var tested = threshold > 0 and mode != Int32(SHADE_UV.value)
                # The stencil and the depth tests, by the function the host
                # asks, and settled at once unless an alpha test could
                # still discard the point; see `rasterize_shaded`.
                var state = RasterState.unpacked(
                    Int(
                        point_maps[
                            unsafe_offset=index * STATE_PER_POINT
                            + POINT_STATE_OPS
                        ]
                    ),
                    Int(
                        point_maps[
                            unsafe_offset=index * STATE_PER_POINT
                            + POINT_STATE_STENCIL
                        ]
                    ),
                )
                # The depth the buffer tests and keeps, and what the pixel
                # holds: the clear of the point's own mode until a depth
                # is claimed; see `render.raster_state.fragment_depth`.
                state.log_depth_scale = points[
                    unsafe_offset=base + LANE_LOG_DEPTH
                ]
                var stored_z = fragment_depth(
                    state, z, points[unsafe_offset=base + LANE_INV_W]
                )
                var held = nearest
                if not solid:
                    held = cleared_depth(state.depth_mode)
                var test = test_fragment(state, stored_z, held, stencil)
                if not shades(test, tested):
                    stencil = test.stencil
                    continue
                red = points[unsafe_offset=base + LANE_R]
                green = points[unsafe_offset=base + LANE_G]
                blue = points[unsafe_offset=base + LANE_B]
                alpha = points[unsafe_offset=base + LANE_A]
                if mode != Int32(SHADE_LIT.value):
                    var place = point_coord(center, size, x, y)
                    if mode == Int32(SHADE_UV.value):
                        # Coordinates, not light, exactly as the triangle
                        # pass writes them.
                        var shown = _decoded(ramp, place.x, place.y, 0)
                        red = shown.r
                        green = shown.g
                        blue = shown.b
                        alpha = 1
                    else:
                        # Which level of the map a point reads is decided
                        # by its size alone, by the function the host
                        # asks; see `mip_level_of`.
                        var slot = Int(
                            point_maps[
                                unsafe_offset=index * STATE_PER_POINT
                                + POINT_STATE_TEXTURE
                            ]
                        )
                        if slot != NO_TEXTURE.value:
                            var image = _describe(table, slot)
                            var sampled = _sample_level(
                                texels,
                                ramp,
                                image,
                                place.x,
                                place.y,
                                mip_level_of(size, image.width, image.height),
                            )
                            red *= sampled.r
                            green *= sampled.g
                            blue *= sampled.b
                            alpha *= sampled.a
                        var mask_slot = Int(
                            point_maps[
                                unsafe_offset=index * STATE_PER_POINT
                                + POINT_STATE_ALPHA_MAP
                            ]
                        )
                        if mask_slot != NO_TEXTURE.value:
                            var mask = _describe(table, mask_slot)
                            var thinning = _sample_level(
                                texels,
                                ramp,
                                mask,
                                place.x,
                                place.y,
                                mip_level_of(size, mask.width, mask.height),
                            )
                            alpha *= thinning.g
                if tested and alpha < threshold:
                    continue
                stencil = test.stencil
                if not test.passes:
                    continue
                if fog_on:
                    var veiled = fog_mix(
                        FloatColor(red, green, blue, alpha),
                        FloatColor(
                            fog[unsafe_offset=FOG_R],
                            fog[unsafe_offset=FOG_G],
                            fog[unsafe_offset=FOG_B],
                            1.0,
                        ),
                        fog_factor(
                            FogKind(Int(fog_kind)),
                            points[unsafe_offset=base + LANE_DEPTH],
                            fog[unsafe_offset=FOG_NEAR],
                            fog[unsafe_offset=FOG_FAR],
                            fog[unsafe_offset=FOG_DENSITY],
                        ),
                    )
                    red = veiled.r
                    green = veiled.g
                    blue = veiled.b
                # Composited exactly as a triangle's fragment is; see the
                # triangle pass below for why each step is what it is.
                var share = alpha
                if share > 1:
                    share = 1
                if share < 0:
                    share = 0
                var policy = Int(
                    point_maps[
                        unsafe_offset=index * STATE_PER_POINT
                        + POINT_STATE_BLEND
                    ]
                )
                var mixes = policy != OPAQUE.value and mode != Int32(
                    SHADE_UV.value
                )
                if mixes and policy == NORMAL_MODE and share == 0:
                    continue
                found = True
                if not mixes:
                    if state.writes_depth(mixes):
                        nearest = stored_z
                        solid = True
                    if not state.color_write:
                        continue
                    share = 1
                    mixed_r = red * share
                    mixed_g = green * share
                    mixed_b = blue * share
                    mixed_a = share
                    # A point is light, never data, except in the uv view,
                    # which shows coordinates.
                    data = mode == Int32(SHADE_UV.value)
                elif state.color_write:
                    var out = blend_pixel(
                        Rgba(mixed_r, mixed_g, mixed_b, mixed_a),
                        Rgba(red, green, blue, share),
                        policy,
                    )
                    mixed_r = out[0]
                    mixed_g = out[1]
                    mixed_b = out[2]
                    mixed_a = out[3]
                    data = False
            continue
        if kind != Int32(DRAW_TRIANGLES.value):
            # A run of segments. One thread per pixel here too, so the
            # question is "does this segment light me" rather than "which
            # pixels does this segment light" -- and `render.linerule`
            # answers both from one expression, which is why the staircase
            # the host walks and the staircase the device tests are the
            # same one.
            for index in range(first, past):
                var base = index * 2 * FLOATS_PER_VERTEX
                var far_base = base + FLOATS_PER_VERTEX
                var first = Vector2(
                    segments[unsafe_offset=base + LANE_X],
                    segments[unsafe_offset=base + LANE_Y],
                )
                var second = Vector2(
                    segments[unsafe_offset=far_base + LANE_X],
                    segments[unsafe_offset=far_base + LANE_Y],
                )
                var strokes = Int(
                    segment_maps[
                        unsafe_offset=index * STATE_PER_LINE + LINE_STATE_WIDTH
                    ]
                )
                if not covers(first, second, x, y, strokes):
                    continue
                var along = y
                if major_is_x(first, second):
                    along = x
                var share = share_at(first, second, along)
                if share < 0:
                    share = 0
                if share > 1:
                    share = 1
                var az = segments[unsafe_offset=base + LANE_Z]
                var bz = segments[unsafe_offset=far_base + LANE_Z]
                var near = segments[unsafe_offset=base + LANE_INV_W] * (
                    1 - share
                )
                var away = segments[unsafe_offset=far_base + LANE_INV_W] * share
                var total = near + away
                if total == 0:
                    continue
                var toward = away / total
                # A pixel in a gap is thrown away before the depth is
                # tested, as the host throws it away: a gap claims nothing.
                var from_a = segments[unsafe_offset=base + LANE_LINE_DISTANCE]
                var from_b = segments[
                    unsafe_offset=far_base + LANE_LINE_DISTANCE
                ]
                if not dash_covers(
                    from_a + (from_b - from_a) * toward,
                    segments[unsafe_offset=base + LANE_DASH],
                    segments[unsafe_offset=base + LANE_GAP],
                ):
                    continue
                # The stencil and the depth tests, settled at once: a line
                # has no alpha test to discard it later.
                var state = RasterState.unpacked(
                    Int(
                        segment_maps[
                            unsafe_offset=index * STATE_PER_LINE
                            + LINE_STATE_OPS
                        ]
                    ),
                    Int(
                        segment_maps[
                            unsafe_offset=index * STATE_PER_LINE
                            + LINE_STATE_STENCIL
                        ]
                    ),
                )
                # The depth the buffer tests and keeps, as the host's line
                # pass finds it; see `rasterize_line`.
                state.log_depth_scale = segments[
                    unsafe_offset=base + LANE_LOG_DEPTH
                ]
                var stored_z = fragment_depth(
                    state, az + (bz - az) * share, total
                )
                var held = nearest
                if not solid:
                    held = cleared_depth(state.depth_mode)
                var test = test_fragment(state, stored_z, held, stencil)
                stencil = test.stencil
                if not test.passes:
                    continue
                # Straight, through the function the host calls, so the one
                # convention for a line's color lives in one place.
                var drawn = mix_straight(
                    FloatColor(
                        segments[unsafe_offset=base + LANE_R],
                        segments[unsafe_offset=base + LANE_G],
                        segments[unsafe_offset=base + LANE_B],
                        segments[unsafe_offset=base + LANE_A],
                    ),
                    FloatColor(
                        segments[unsafe_offset=far_base + LANE_R],
                        segments[unsafe_offset=far_base + LANE_G],
                        segments[unsafe_offset=far_base + LANE_B],
                        segments[unsafe_offset=far_base + LANE_A],
                    ),
                    toward,
                )
                # The host's line pass reads no shading mode: a line has no surface
                # coordinates, so there is no uv view of one, and it is veiled by
                # the fog whatever the mode. See `rasterize_line`.
                if fog_kind != Int32(NO_FOG.value):
                    var ad = segments[unsafe_offset=base + LANE_DEPTH]
                    var bd = segments[unsafe_offset=far_base + LANE_DEPTH]
                    var seen = ad + (bd - ad) * toward
                    # By name, as the triangle pass reads it. Written out as
                    # literal slots once, which took the color out of the near,
                    # far and density lanes and the distances out of the color: a
                    # white line in black fog came back yellow.
                    drawn = fog_mix(
                        drawn,
                        FloatColor(
                            fog[unsafe_offset=FOG_R],
                            fog[unsafe_offset=FOG_G],
                            fog[unsafe_offset=FOG_B],
                            1,
                        ),
                        fog_factor(
                            FogKind(Int(fog_kind)),
                            seen,
                            fog[unsafe_offset=FOG_NEAR],
                            fog[unsafe_offset=FOG_FAR],
                            fog[unsafe_offset=FOG_DENSITY],
                        ),
                    )
                var share_a = drawn.a
                if share_a > 1:
                    share_a = 1
                if share_a < 0:
                    share_a = 0
                var policy = Int(
                    segment_maps[
                        unsafe_offset=index * STATE_PER_LINE + LINE_STATE_BLEND
                    ]
                )
                var mixes = policy != OPAQUE.value
                if mixes and policy == NORMAL_MODE and share_a == 0:
                    continue
                found = True
                if not mixes:
                    if state.writes_depth(mixes):
                        nearest = stored_z
                        solid = True
                    if not state.color_write:
                        continue
                    # Opaque, so written with an alpha of one, as on the host.
                    share_a = 1
                    mixed_r = drawn.r * share_a
                    mixed_g = drawn.g * share_a
                    mixed_b = drawn.b * share_a
                    mixed_a = share_a
                    # A line is light, never data: it has no normal to show and no
                    # depth material to show one. `check_line_state` refuses any
                    # kind but an unlit one.
                    data = False
                elif state.color_write:
                    var out = blend_pixel(
                        Rgba(mixed_r, mixed_g, mixed_b, mixed_a),
                        Rgba(drawn.r, drawn.g, drawn.b, share_a),
                        policy,
                    )
                    mixed_r = out[0]
                    mixed_g = out[1]
                    mixed_b = out[2]
                    mixed_a = out[3]
                    data = False

            continue
        for index in range(first, past):
            var base = index * FLOATS_PER_TRIANGLE
            # Derived rather than written out: every offset past the first corner
            # used to be a literal, and changing the stride meant changing all of
            # them. Twice it meant missing one, which reads a neighboring field
            # as a coordinate and is invisible until a parity test disagrees.
            var b_base = base + FLOATS_PER_VERTEX
            var c_base = base + 2 * FLOATS_PER_VERTEX
            var ax = corners[unsafe_offset=base + LANE_X]
            var ay = corners[unsafe_offset=base + LANE_Y]
            var az = corners[unsafe_offset=base + LANE_Z]
            var aw = corners[unsafe_offset=base + LANE_INV_W]
            var bx = corners[unsafe_offset=b_base + LANE_X]
            var by = corners[unsafe_offset=b_base + LANE_Y]
            var bz = corners[unsafe_offset=b_base + LANE_Z]
            var bw = corners[unsafe_offset=b_base + LANE_INV_W]
            var cx = corners[unsafe_offset=c_base + LANE_X]
            var cy = corners[unsafe_offset=c_base + LANE_Y]
            var cz = corners[unsafe_offset=c_base + LANE_Z]
            var cw = corners[unsafe_offset=c_base + LANE_INV_W]

            # Exactly `_Coverage` on the host: snap, normalize the winding, then
            # test with the top-left bias. Only the snapped coordinates are
            # swapped; the attributes stay in the caller's order and the weights
            # are mapped back at the end.
            var sax = snap(ax)
            var say = snap(ay)
            var sbx = snap(bx)
            var sby = snap(by)
            var scx = snap(cx)
            var scy = snap(cy)

            var area = edge_at(sax, say, sbx, sby, scx, scy)
            var swapped = area < 0
            if swapped:
                var tx = sbx
                var ty = sby
                sbx = scx
                sby = scy
                scx = tx
                scy = ty
                area = -area
            if area == 0:
                continue

            var e_ab = edge_at(sax, say, sbx, sby, px, py)
            var e_bc = edge_at(sbx, sby, scx, scy, px, py)
            var e_ca = edge_at(scx, scy, sax, say, px, py)
            if (
                e_ab + bias(sax, say, sbx, sby) < 0
                or e_bc + bias(sbx, sby, scx, scy) < 0
                or e_ca + bias(scx, scy, sax, say) < 0
            ):
                continue

            # The edge opposite a corner is that corner's weight.
            # One reciprocal per triangle, three multiplies per pixel, exactly
            # as `_Coverage.inv_area` on the host.
            var span_inv = Float32(1) / Float32(area)
            var first = Float32(e_bc) * span_inv
            var second = Float32(e_ca) * span_inv
            var third = Float32(e_ab) * span_inv
            var wa = first
            var wb = second
            var wc = third
            if swapped:
                wb = third
                wc = second

            # Depth interpolates affinely; see `RasterVertex.z`.
            var z = wa * az + wb * bz + wc * cz
            # The alpha a fragment must reach to be drawn, from the first
            # corner's lane, and whether there is a test at all. The uv debug
            # view cuts nothing out, as it samples no texture.
            var threshold = corners[unsafe_offset=base + LANE_ALPHA_TEST]
            var tested = threshold > 0 and mode != Int32(SHADE_UV.value)
            # The stencil and the depth tests, by the function the host
            # asks, and settled at once unless an alpha test could still
            # discard the fragment; see `rasterize_shaded`.
            var state = RasterState.unpacked(
                Int(maps[unsafe_offset=index * STATE_PER_TRIANGLE + STATE_OPS]),
                Int(
                    maps[
                        unsafe_offset=index * STATE_PER_TRIANGLE + STATE_STENCIL
                    ]
                ),
            )
            # Color does not: weight by inv_w and divide by the interpolated
            # inv_w, matching `rasterize_shaded`.
            var inv_w = wa * aw + wb * bw + wc * cw
            # The depth the buffer tests and keeps, and what the pixel
            # holds: the clear of the triangle's own mode until a depth is
            # claimed; see `render.raster_state.fragment_depth`. A `DEPTH`
            # material still shows `z`.
            state.log_depth_scale = corners[unsafe_offset=base + LANE_LOG_DEPTH]
            var stored_z = fragment_depth(state, z, inv_w)
            var held = nearest
            if not solid:
                held = cleared_depth(state.depth_mode)
            var test = test_fragment(state, stored_z, held, stencil)
            if not shades(test, tested):
                stencil = test.stencil
                continue
            var share_a = wa
            var share_b = wb
            var share_c = wc
            if inv_w != 0:
                var rcp = Float32(1) / inv_w
                share_a = wa * aw * rcp
                share_b = wb * bw * rcp
                share_c = wc * cw * rcp

            # What kind of surface this is, per triangle from the state table:
            # lit, unlit, or showing its normal or its depth as data.
            var kind = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_KIND
            ]
            # Whether this surface is shaded by a roughness and a metalness,
            # which is lit, but lit below once its maps have had their say.
            var physical = kind == Int32(STANDARD.value) or kind == Int32(
                PHYSICAL.value
            )
            var lit = (
                kind == Int32(LAMBERT.value)
                or kind == Int32(PHONG.value)
                or kind == Int32(TOON.value)
                or physical
            )
            # Unlit, but looked up by which way the surface is turned, so it
            # needs the normal and the world position that a lit surface needs.
            var looked_up = kind == Int32(MATCAP.value)
            # Whether this surface shows the shadows falling on it and
            # nothing else, and whether the shadows fall on it at all.
            var catches = kind == Int32(SHADOW.value)
            var receives = (
                maps[
                    unsafe_offset=index * STATE_PER_TRIANGLE
                    + STATE_RECEIVES_SHADOW
                ]
                != 0
            )
            # Whether this surface reflects an environment, which needs the
            # same two whether or not it is lit, and only under the mode
            # that opens textures, as `rasterize_shaded` decides it.
            var env_slot = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_ENV_MAP
            ]
            var reflects = env_slot >= 0 and mode == Int32(SHADE_TEXTURE.value)
            var shows_normal = kind == Int32(NORMALS.value)
            var shows_data = shows_normal or kind == Int32(DEPTH.value)
            # The interpolated normal, made a unit vector again here. That
            # renormalization is the difference between per-fragment and
            # per-vertex shading: the average of two unit vectors is shorter than
            # either, so leaving it alone dims the middle of every triangle.
            # Only the two lit modes need it, and only a surface that is lit by
            # it or shows it: SHADE_UV writes coordinates rather than light,
            # and a BASIC material shows its own color.
            var arriving = Vector3(1, 1, 1)
            var highlight = Vector3(0, 0, 0)
            var nx = Float32(0)
            var ny = Float32(0)
            var nz = Float32(1)
            if mode != Int32(SHADE_UV.value) and (
                lit or shows_normal or looked_up or reflects or catches
            ):
                nx = (
                    corners[unsafe_offset=base + LANE_NX] * share_a
                    + corners[unsafe_offset=b_base + LANE_NX] * share_b
                    + corners[unsafe_offset=c_base + LANE_NX] * share_c
                )
                ny = (
                    corners[unsafe_offset=base + LANE_NY] * share_a
                    + corners[unsafe_offset=b_base + LANE_NY] * share_b
                    + corners[unsafe_offset=c_base + LANE_NY] * share_c
                )
                nz = (
                    corners[unsafe_offset=base + LANE_NZ] * share_a
                    + corners[unsafe_offset=b_base + LANE_NZ] * share_b
                    + corners[unsafe_offset=c_base + LANE_NZ] * share_c
                )
                var unit = sqrt(nx * nx + ny * ny + nz * nz)
                if unit != 0:
                    nx /= unit
                    ny /= unit
                    nz /= unit
            # Where this fragment is in the world, for the lights that have
            # a position, and for the direction a reflection turns back.
            var wx = Float32(0)
            var wy = Float32(0)
            var wz = Float32(0)
            if mode != Int32(SHADE_UV.value) and (
                lit or looked_up or reflects or catches
            ):
                wx = (
                    corners[unsafe_offset=base + LANE_WX] * share_a
                    + corners[unsafe_offset=b_base + LANE_WX] * share_b
                    + corners[unsafe_offset=c_base + LANE_WX] * share_c
                )
                wy = (
                    corners[unsafe_offset=base + LANE_WY] * share_a
                    + corners[unsafe_offset=b_base + LANE_WY] * share_b
                    + corners[unsafe_offset=c_base + LANE_WY] * share_c
                )
                wz = (
                    corners[unsafe_offset=base + LANE_WZ] * share_a
                    + corners[unsafe_offset=b_base + LANE_WZ] * share_b
                    + corners[unsafe_offset=c_base + LANE_WZ] * share_c
                )
            # Texture coordinates, for the two modes that read them.
            var u = Float32(0)
            var v = Float32(0)
            if mode != Int32(SHADE_LIT.value):
                u = (
                    corners[unsafe_offset=base + LANE_U] * share_a
                    + corners[unsafe_offset=b_base + LANE_U] * share_b
                    + corners[unsafe_offset=c_base + LANE_U] * share_c
                )
                v = (
                    corners[unsafe_offset=base + LANE_V] * share_a
                    + corners[unsafe_offset=b_base + LANE_V] * share_b
                    + corners[unsafe_offset=c_base + LANE_V] * share_c
                )
            # The normal before any map perturbs it: what a clear coat
            # lies on. Then the map, by the host's own two functions, from
            # the position and the coordinates one pixel right and one
            # pixel up, evaluated from the triangle's own functions --
            # exactly as `rasterize_shaded` measures them.
            var cnx = nx
            var cny = ny
            var cnz = nz
            var normal_slot = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_NORMAL_MAP
            ]
            var bump_slot = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_BUMP_MAP
            ]
            if (
                mode == Int32(SHADE_TEXTURE.value)
                and (normal_slot >= 0 or bump_slot >= 0)
                and (lit or looked_up)
            ):
                var here = Vector3(wx, wy, wz)
                var along_x = (
                    _world_at(
                        corners,
                        base,
                        sax,
                        say,
                        sbx,
                        sby,
                        scx,
                        scy,
                        span_inv,
                        swapped,
                        px + SUBPIXEL,
                        py,
                    )
                    - here
                )
                var along_y = (
                    _world_at(
                        corners,
                        base,
                        sax,
                        say,
                        sbx,
                        sby,
                        scx,
                        scy,
                        span_inv,
                        swapped,
                        px,
                        py - SUBPIXEL,
                    )
                    - here
                )
                var uv_right = _uv_at(
                    corners,
                    base,
                    sax,
                    say,
                    sbx,
                    sby,
                    scx,
                    scy,
                    span_inv,
                    swapped,
                    px + SUBPIXEL,
                    py,
                )
                var uv_up = _uv_at(
                    corners,
                    base,
                    sax,
                    say,
                    sbx,
                    sby,
                    scx,
                    scy,
                    span_inv,
                    swapped,
                    px,
                    py - SUBPIXEL,
                )
                var uv_along_x = Vector2(uv_right.x - u, uv_right.y - v)
                var uv_along_y = Vector2(uv_up.x - u, uv_up.y - v)
                var facing = Vector3(nx, ny, nz)
                if normal_slot >= 0:
                    facing = mapped_normal(
                        Vector3(nx, ny, nz),
                        along_x,
                        along_y,
                        uv_along_x,
                        uv_along_y,
                        _sample_slot(
                            texels,
                            ramp,
                            table,
                            Int(normal_slot),
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        ),
                        Vector2(
                            corners[unsafe_offset=base + LANE_NORMAL_SCALE_X],
                            corners[unsafe_offset=base + LANE_NORMAL_SCALE_Y],
                        ),
                    )
                else:
                    var bump_scale = corners[
                        unsafe_offset=base + LANE_BUMP_SCALE
                    ]
                    var height = (
                        bump_scale
                        * _sample_slot(
                            texels,
                            ramp,
                            table,
                            Int(bump_slot),
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        ).r
                    )
                    var rise_x = (
                        bump_scale
                        * _sample_slot(
                            texels,
                            ramp,
                            table,
                            Int(bump_slot),
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u + uv_along_x.x,
                            v + uv_along_x.y,
                        ).r
                        - height
                    )
                    var rise_y = (
                        bump_scale
                        * _sample_slot(
                            texels,
                            ramp,
                            table,
                            Int(bump_slot),
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u + uv_along_y.x,
                            v + uv_along_y.y,
                        ).r
                        - height
                    )
                    facing = bumped_normal(
                        Vector3(nx, ny, nz), along_x, along_y, rise_x, rise_y
                    )
                nx = facing.x
                ny = facing.y
                nz = facing.z
            if mode != Int32(SHADE_UV.value) and (lit or looked_up):
                if looked_up:
                    # Which way the surface is turned in the camera's frame,
                    # and the image read there: the host's own two functions.
                    # Measured from where the camera stands under either
                    # projection, because three.js reads `vViewPosition` and
                    # does not special-case a parallel one.
                    var place = matcap_uv(
                        toward_eye_at(
                            Vector3(
                                lights[unsafe_offset=LIGHTS_EYE],
                                lights[unsafe_offset=LIGHTS_EYE + 1],
                                lights[unsafe_offset=LIGHTS_EYE + 2],
                            ),
                            PERSPECTIVE_VIEW,
                            Vector3(wx, wy, wz),
                        ),
                        Vector3(
                            lights[unsafe_offset=LIGHTS_UP],
                            lights[unsafe_offset=LIGHTS_UP + 1],
                            lights[unsafe_offset=LIGHTS_UP + 2],
                        ),
                        Vector3(nx, ny, nz),
                    )
                    var ball = maps[
                        unsafe_offset=index * STATE_PER_TRIANGLE + STATE_MATCAP
                    ]
                    if ball >= 0:
                        # The full-size level, never a mip, as the host reads
                        # it: the coordinate comes from the normal rather than
                        # from the surface.
                        var looked = _sample_at(
                            texels,
                            ramp,
                            _describe(table, Int(ball)),
                            place.x,
                            place.y,
                            0,
                        )
                        arriving = Vector3(looked.r, looked.g, looked.b)
                    else:
                        var gray = matcap_fallback(place.y)
                        arriving = Vector3(gray, gray, gray)
                elif kind == Int32(TOON.value):
                    # Every cosine read off the ramp rather than faded, and
                    # never clamped at zero: see `_toon_arriving`. Where the
                    # ramp lives is looked up once here, not once per light.
                    var start = 0
                    var tones = 0
                    var ramp_slot = maps[
                        unsafe_offset=index * STATE_PER_TRIANGLE
                        + STATE_GRADIENT_MAP
                    ]
                    if ramp_slot >= 0:
                        var shades = _describe(table, Int(ramp_slot))
                        start = shades.start
                        tones = shades.width
                    arriving = _toon_arriving(
                        lights,
                        Int(light_count),
                        Int(point_count),
                        Int(hemisphere_count),
                        Int(spot_count),
                        texels,
                        ramp,
                        table,
                        start,
                        tones,
                        nx,
                        ny,
                        nz,
                        wx,
                        wy,
                        wz,
                        receives,
                    )
                elif not physical:
                    # A physical surface is lit below, once its maps have
                    # had their say, exactly as `rasterize_shaded` defers it.
                    arriving = _arriving(
                        lights,
                        texels,
                        ramp,
                        table,
                        Int(light_count),
                        Int(point_count),
                        Int(hemisphere_count),
                        Int(spot_count),
                        nx,
                        ny,
                        nz,
                        wx,
                        wy,
                        wz,
                        receives,
                    )
                if kind == Int32(PHONG.value):
                    # Interpolated like the emissive, and summed over the
                    # lights that have a direction; see `_highlight`.
                    var sheen = Vector3(
                        corners[unsafe_offset=base + LANE_SPECULAR_R] * share_a
                        + corners[unsafe_offset=b_base + LANE_SPECULAR_R]
                        * share_b
                        + corners[unsafe_offset=c_base + LANE_SPECULAR_R]
                        * share_c,
                        corners[unsafe_offset=base + LANE_SPECULAR_G] * share_a
                        + corners[unsafe_offset=b_base + LANE_SPECULAR_G]
                        * share_b
                        + corners[unsafe_offset=c_base + LANE_SPECULAR_G]
                        * share_c,
                        corners[unsafe_offset=base + LANE_SPECULAR_B] * share_a
                        + corners[unsafe_offset=b_base + LANE_SPECULAR_B]
                        * share_b
                        + corners[unsafe_offset=c_base + LANE_SPECULAR_B]
                        * share_c,
                    )
                    highlight = _highlight(
                        lights,
                        texels,
                        ramp,
                        table,
                        Int(light_count),
                        Int(point_count),
                        Int(hemisphere_count),
                        Int(spot_count),
                        nx,
                        ny,
                        nz,
                        wx,
                        wy,
                        wz,
                        sheen,
                        corners[unsafe_offset=base + LANE_SHININESS],
                        receives,
                    )

            # The baked maps, sampled at the second coordinates by the
            # host's own functions in the host's own order; see
            # `rasterize_shaded`. A physical surface takes both below.
            var occlusion = Float32(1)
            var baked = Vector3(0, 0, 0)
            var ao_slot = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_AO_MAP
            ]
            var light_slot = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_LIGHT_MAP
            ]
            if mode == Int32(SHADE_TEXTURE.value) and (
                ao_slot >= 0 or light_slot >= 0
            ):
                var u1 = (
                    corners[unsafe_offset=base + LANE_U1] * share_a
                    + corners[unsafe_offset=b_base + LANE_U1] * share_b
                    + corners[unsafe_offset=c_base + LANE_U1] * share_c
                )
                var v1 = (
                    corners[unsafe_offset=base + LANE_V1] * share_a
                    + corners[unsafe_offset=b_base + LANE_V1] * share_b
                    + corners[unsafe_offset=c_base + LANE_V1] * share_c
                )
                if ao_slot >= 0:
                    occlusion = ambient_occlusion(
                        _sample_slot(
                            texels,
                            ramp,
                            table,
                            Int(ao_slot),
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u1,
                            v1,
                            LANE_U1,
                        ).r,
                        corners[unsafe_offset=base + LANE_AO_INTENSITY],
                    )
                if light_slot >= 0:
                    var glowed = _sample_slot(
                        texels,
                        ramp,
                        table,
                        Int(light_slot),
                        corners,
                        base,
                        sax,
                        say,
                        sbx,
                        sby,
                        scx,
                        scy,
                        span_inv,
                        swapped,
                        px,
                        py,
                        u1,
                        v1,
                        LANE_U1,
                    )
                    var strength = corners[
                        unsafe_offset=base + LANE_LIGHT_MAP_INTENSITY
                    ] * (
                        lights[
                            unsafe_offset=LIGHTS_SCALE
                        ] if lit else RECIPROCAL_PI
                    )
                    baked = Vector3(
                        glowed.r * strength,
                        glowed.g * strength,
                        glowed.b * strength,
                    )
                    if not lit:
                        arriving = Vector3(0, 0, 0)
                if not physical:
                    var indirect = arriving
                    if lit:
                        indirect = _indirect(
                            lights,
                            Int(light_count),
                            Int(point_count),
                            Int(hemisphere_count),
                            nx,
                            ny,
                            nz,
                        )
                    arriving = occluded_light(
                        arriving, indirect, baked, occlusion
                    )
            # What a physical surface's roughness and metalness are
            # multiplied by: its maps' green and blue, or one for none.
            var rough_factor = Float32(1)
            var metal_factor = Float32(1)
            # What the highlight and the reflectivity are scaled by: the
            # specular map's red, or one for none.
            var specular_strength = Float32(1)
            if mode == Int32(SHADE_UV.value):
                # Coordinates, not light, through the same quantize and decode
                # the host's `data_color` uses, so the two backends hold the
                # same light and one resolve serves every pixel. Storing the
                # raw coordinate and quantizing the whole frame instead worked
                # only while every pixel in the frame was a coordinate. A line
                # in the uv view holds real light, and the frame-wide quantize
                # showed that light undecoded.
                var shown = _decoded(ramp, u, v, 0)
                red = shown.r
                green = shown.g
                blue = shown.b
                alpha = 1
            else:
                red = (
                    corners[unsafe_offset=base + LANE_R] * share_a
                    + corners[unsafe_offset=b_base + LANE_R] * share_b
                    + corners[unsafe_offset=c_base + LANE_R] * share_c
                )
                green = (
                    corners[unsafe_offset=base + LANE_G] * share_a
                    + corners[unsafe_offset=b_base + LANE_G] * share_b
                    + corners[unsafe_offset=c_base + LANE_G] * share_c
                )
                blue = (
                    corners[unsafe_offset=base + LANE_B] * share_a
                    + corners[unsafe_offset=b_base + LANE_B] * share_b
                    + corners[unsafe_offset=c_base + LANE_B] * share_c
                )
                # The difference form, so a constant alpha reaches the alpha
                # test exactly: the host's own function.
                alpha = interpolate_alpha(
                    corners[unsafe_offset=base + LANE_A],
                    corners[unsafe_offset=b_base + LANE_A],
                    corners[unsafe_offset=c_base + LANE_A],
                    share_b,
                    share_c,
                )
                red *= arriving.x
                green *= arriving.y
                blue *= arriving.z
                # Light the surface gives off, interpolated like its color and
                # added after the lights, exactly as `rasterize_shaded` adds it.
                var glow_r = (
                    corners[unsafe_offset=base + LANE_ER] * share_a
                    + corners[unsafe_offset=b_base + LANE_ER] * share_b
                    + corners[unsafe_offset=c_base + LANE_ER] * share_c
                )
                var glow_g = (
                    corners[unsafe_offset=base + LANE_EG] * share_a
                    + corners[unsafe_offset=b_base + LANE_EG] * share_b
                    + corners[unsafe_offset=c_base + LANE_EG] * share_c
                )
                var glow_b = (
                    corners[unsafe_offset=base + LANE_EB] * share_a
                    + corners[unsafe_offset=b_base + LANE_EB] * share_b
                    + corners[unsafe_offset=c_base + LANE_EB] * share_c
                )
                if mode == Int32(SHADE_TEXTURE.value):
                    # Which image, from the triangle; -1 is no texture, which
                    # samples as white and so leaves the lighting alone.
                    var slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_TEXTURE
                        ]
                    )
                    if slot != NO_TEXTURE.value:
                        var sampled = _sample_slot(
                            texels,
                            ramp,
                            table,
                            slot,
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        )
                        red *= sampled.r
                        green *= sampled.g
                        blue *= sampled.b
                        alpha *= sampled.a
                    # The emissive map multiplies the glow the same way, alpha
                    # aside: light given off has no coverage.
                    var glow_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_EMISSIVE_MAP
                        ]
                    )
                    # The alpha map's green channel thins the surface,
                    # three.js's `alphamap_fragment`, exactly as the host
                    # multiplies it.
                    var mask_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_ALPHA_MAP
                        ]
                    )
                    if mask_slot != NO_TEXTURE.value:
                        var thinning = _sample_slot(
                            texels,
                            ramp,
                            table,
                            mask_slot,
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        )
                        alpha *= thinning.g
                    if glow_slot != NO_TEXTURE.value:
                        var glowing = _sample_slot(
                            texels,
                            ramp,
                            table,
                            glow_slot,
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        )
                        glow_r *= glowing.r
                        glow_g *= glowing.g
                        glow_b *= glowing.b
                    # The roughness map's green and the metalness map's
                    # blue, exactly as `rasterize_shaded` reads them.
                    var rough_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_ROUGHNESS_MAP
                        ]
                    )
                    if rough_slot != NO_TEXTURE.value:
                        rough_factor = _sample_slot(
                            texels,
                            ramp,
                            table,
                            rough_slot,
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        ).g
                    var metal_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_METALNESS_MAP
                        ]
                    )
                    if metal_slot != NO_TEXTURE.value:
                        metal_factor = _sample_slot(
                            texels,
                            ramp,
                            table,
                            metal_slot,
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        ).b
                    # The specular map's red scales the highlight here and
                    # the reflectivity below, exactly as `rasterize_shaded`
                    # scales them.
                    var strength_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_SPECULAR_MAP
                        ]
                    )
                    if strength_slot != NO_TEXTURE.value:
                        specular_strength = _sample_slot(
                            texels,
                            ramp,
                            table,
                            strength_slot,
                            corners,
                            base,
                            sax,
                            say,
                            sbx,
                            sby,
                            scx,
                            scy,
                            span_inv,
                            swapped,
                            px,
                            py,
                            u,
                            v,
                        ).r
                        highlight = Vector3(
                            highlight.x * specular_strength,
                            highlight.y * specular_strength,
                            highlight.z * specular_strength,
                        )
                # Thrown away for being too transparent, three.js's
                # `alphatest_fragment`. Leaving `nearest` alone is the late
                # depth write the host makes with `claim_depth`: the hole
                # shows whatever is behind it.
                if tested and alpha < threshold:
                    continue
                if shows_data:
                    # Data rather than light, exactly as `rasterize_shaded`
                    # writes it: the packed normal, or the depth as a gray, as
                    # bytes decoded through the ramp. The color and the texture
                    # keep their say over alpha alone, so a cut-out map cuts a
                    # depth out. Neither the glow nor the fog reaches these.
                    var shown: FloatColor
                    if shows_normal:
                        var packed = packed_normal(Vector3(nx, ny, nz))
                        shown = _decoded(ramp, packed.x, packed.y, packed.z)
                    else:
                        var seen = packed_depth(z)
                        shown = _decoded(ramp, seen, seen, seen)
                    red = shown.r
                    green = shown.g
                    blue = shown.b
                elif catches:
                    # The shadow and nothing else, exactly as
                    # `rasterize_shaded` shows it: transparent where the
                    # lights that cast reach, the color where they are
                    # blocked.
                    alpha *= 1 - _shadow_mask(
                        lights,
                        Int(light_count),
                        Int(point_count),
                        Int(hemisphere_count),
                        Int(spot_count),
                        Vector3(wx, wy, wz),
                        Vector3(nx, ny, nz),
                    )
                elif physical:
                    # Lit here, once the map has multiplied the color, by
                    # the host's own functions in the host's own order;
                    # see `rasterize_shaded`. The reflectance head on
                    # rides in the specular lanes, from the first corner.
                    var surface = physical_surface(
                        Vector3(red, green, blue),
                        Vector3(
                            corners[unsafe_offset=base + LANE_SPECULAR_R],
                            corners[unsafe_offset=base + LANE_SPECULAR_G],
                            corners[unsafe_offset=base + LANE_SPECULAR_B],
                        ),
                        corners[unsafe_offset=base + LANE_METALNESS]
                        * metal_factor,
                        corners[unsafe_offset=base + LANE_SPECULAR_INTENSITY],
                    )
                    var rough = floored_roughness(
                        corners[unsafe_offset=base + LANE_ROUGHNESS]
                        * rough_factor
                    )
                    var coat = corners[unsafe_offset=base + LANE_CLEARCOAT]
                    var coat_rough = floored_roughness(
                        corners[unsafe_offset=base + LANE_CLEARCOAT_ROUGHNESS]
                    )
                    var facing = Vector3(nx, ny, nz)
                    var coat_facing = Vector3(cnx, cny, cnz)
                    var spot = Vector3(wx, wy, wz)
                    var direct = _physical(
                        lights,
                        texels,
                        ramp,
                        table,
                        Int(light_count),
                        Int(point_count),
                        Int(hemisphere_count),
                        Int(spot_count),
                        facing,
                        coat_facing,
                        spot,
                        surface,
                        rough,
                        coat,
                        coat_rough,
                        receives,
                    )
                    var around = _indirect(
                        lights,
                        Int(light_count),
                        Int(point_count),
                        Int(hemisphere_count),
                        nx,
                        ny,
                        nz,
                    )
                    var indirect = Vector3(
                        around.x + baked.x,
                        around.y + baked.y,
                        around.z + baked.z,
                    )
                    var toward_eye = toward_eye_at(
                        Vector3(
                            lights[unsafe_offset=LIGHTS_EYE],
                            lights[unsafe_offset=LIGHTS_EYE + 1],
                            lights[unsafe_offset=LIGHTS_EYE + 2],
                        ),
                        Vector3(
                            lights[unsafe_offset=LIGHTS_TOWARD],
                            lights[unsafe_offset=LIGHTS_TOWARD + 1],
                            lights[unsafe_offset=LIGHTS_TOWARD + 2],
                        ),
                        spot,
                    )
                    var dot_nv = max(
                        Float32(0), min(Float32(1), facing.dot(toward_eye))
                    )
                    var dot_nv_coat = max(
                        Float32(0),
                        min(Float32(1), coat_facing.dot(toward_eye)),
                    )
                    var radiance = Vector3(0, 0, 0)
                    var irradiance = Vector3(0, 0, 0)
                    var coat_radiance = Vector3(0, 0, 0)
                    if reflects:
                        var strength = corners[
                            unsafe_offset=base + LANE_ENV_INTENSITY
                        ]
                        var seen = _sample_cube_rough(
                            texels,
                            ramp,
                            table,
                            Int(env_slot),
                            rough_reflection(toward_eye, facing, rough),
                            rough,
                        )
                        var around = _sample_cube_rough(
                            texels, ramp, table, Int(env_slot), facing, 1
                        )
                        radiance = Vector3(
                            seen.r * strength,
                            seen.g * strength,
                            seen.b * strength,
                        )
                        irradiance = Vector3(
                            around.r * strength,
                            around.g * strength,
                            around.b * strength,
                        )
                        if coat > 0:
                            var gloss = _sample_cube_rough(
                                texels,
                                ramp,
                                table,
                                Int(env_slot),
                                rough_reflection(
                                    toward_eye, coat_facing, coat_rough
                                ),
                                coat_rough,
                            )
                            coat_radiance = Vector3(
                                gloss.r * strength,
                                gloss.g * strength,
                                gloss.b * strength,
                            )
                    var outgoing = physical_outgoing(
                        direct,
                        indirect,
                        surface,
                        rough,
                        dot_nv,
                        reflects,
                        radiance,
                        irradiance,
                        Vector3(glow_r, glow_g, glow_b),
                        coat,
                        coat_rough,
                        Vector3(dot_nv_coat, 0, 0),
                        coat_radiance,
                        occlusion,
                    )
                    red = outgoing.x
                    green = outgoing.y
                    blue = outgoing.z
                else:
                    # The highlight and then the glow, exactly as
                    # `rasterize_shaded` sums them.
                    red += highlight.x + glow_r
                    green += highlight.y + glow_g
                    blue += highlight.z + glow_b
                    # Then the reflection, by the host's own three
                    # functions: the view turned back through the normal,
                    # the cube read in that direction, and the two lights
                    # joined by the material's combine. The one fixed
                    # direction under a parallel projection, as
                    # `rasterize_shaded` takes it and as
                    # `envmap_fragment` takes it under `isOrthographic`.
                    # See `rasterize_shaded`.
                    if reflects:
                        var bounce = reflected(
                            toward_eye_at(
                                Vector3(
                                    lights[unsafe_offset=LIGHTS_EYE],
                                    lights[unsafe_offset=LIGHTS_EYE + 1],
                                    lights[unsafe_offset=LIGHTS_EYE + 2],
                                ),
                                Vector3(
                                    lights[unsafe_offset=LIGHTS_TOWARD],
                                    lights[unsafe_offset=LIGHTS_TOWARD + 1],
                                    lights[unsafe_offset=LIGHTS_TOWARD + 2],
                                ),
                                Vector3(wx, wy, wz),
                            ),
                            Vector3(nx, ny, nz),
                        )
                        var joined = combine_light(
                            FloatColor(red, green, blue, alpha),
                            _sample_cube(
                                texels, ramp, table, Int(env_slot), bounce
                            ),
                            corners[unsafe_offset=base + LANE_REFLECTIVITY]
                            * specular_strength,
                            Combine(
                                Int(
                                    maps[
                                        unsafe_offset=index * STATE_PER_TRIANGLE
                                        + STATE_COMBINE
                                    ]
                                )
                            ),
                        )
                        red = joined.r
                        green = joined.g
                        blue = joined.b
                # Veiled by the fog last, in linear light, from the same depth
                # lane and with the same function as `rasterize_shaded`. Alpha
                # is coverage and is left alone.
                if fog_on and not shows_data:
                    var depth = (
                        corners[unsafe_offset=base + LANE_DEPTH] * share_a
                        + corners[unsafe_offset=b_base + LANE_DEPTH] * share_b
                        + corners[unsafe_offset=c_base + LANE_DEPTH] * share_c
                    )
                    var veiled = fog_mix(
                        FloatColor(red, green, blue, alpha),
                        FloatColor(
                            fog[unsafe_offset=FOG_R],
                            fog[unsafe_offset=FOG_G],
                            fog[unsafe_offset=FOG_B],
                            1.0,
                        ),
                        fog_factor(
                            FogKind(Int(fog_kind)),
                            depth,
                            fog[unsafe_offset=FOG_NEAR],
                            fog[unsafe_offset=FOG_FAR],
                            fog[unsafe_offset=FOG_DENSITY],
                        ),
                    )
                    red = veiled.r
                    green = veiled.g
                    blue = veiled.b

            # The stencil and the depth the tests asked for, settled now that
            # the fragment has survived its alpha test. One that failed its
            # tests was shaded only to learn that, and is drawn no further.
            stencil = test.stencil
            if not test.passes:
                continue
            # Opaque replaces what is there; translucent mixes into it. One pass
            # is enough only because every opaque triangle is submitted before any
            # translucent one, so `nearest` is already final when the first
            # blended fragment arrives -- the same guarantee `rasterize_shaded`
            # relies on, and the reason `Renderer.prepare` sorts.
            var share = alpha
            if share > 1:
                share = 1
            if share < 0:
                share = 0
            # Asked the way the host asks it -- "is it BLEND?" -- so anything
            # else is opaque on both sides rather than opaque on one.
            var policy = Int(
                maps[unsafe_offset=index * STATE_PER_TRIANGLE + STATE_BLEND]
            )
            var mixes = policy != OPAQUE.value and mode != Int32(SHADE_UV.value)
            # A source-over fragment that covers nothing contributes no color,
            # so it must contribute no depth and no answer about what the pixel
            # holds either. `RenderTarget.blend` returns early for the same
            # reason; see `render.target`.
            if mixes and policy == NORMAL_MODE and share == 0:
                continue
            found = True
            if not mixes:
                if state.writes_depth(mixes):
                    nearest = stored_z
                    solid = True
                if not state.color_write:
                    continue
                # Nothing behind contributes, and the fragment is written with
                # an alpha of one, as three.js's `opaque_fragment` writes it
                # and as `rasterize_shaded` writes it; only a depth material
                # keeps its opacity as its alpha.
                if kind != Int32(DEPTH.value):
                    share = 1
                mixed_r = red * share
                mixed_g = green * share
                mixed_b = blue * share
                mixed_a = share
                # A write replaces the pixel, so its answer becomes this
                # fragment's, exactly as `RenderTarget.write` decides it.
                # The uv view shows coordinates, which the tone mapping has
                # to leave alone exactly as it leaves a normal alone.
                data = shows_data or mode == Int32(SHADE_UV.value)
            elif state.color_write:
                # The mode's arithmetic, shared with `RenderTarget.blend`.
                var out = blend_pixel(
                    Rgba(mixed_r, mixed_g, mixed_b, mixed_a),
                    Rgba(red, green, blue, share),
                    policy,
                )
                mixed_r = out[0]
                mixed_g = out[1]
                mixed_b = out[2]
                mixed_a = out[3]
                # A mixture with light in it is light, and only light blends:
                # a fragment that shows data is refused this policy by
                # `check_triangle_state`. See `render.target`.
                data = False

    var nearest_depth = inf[DType.float32]()
    # Unpremultiply, tone map, then encode, as `RenderTarget.resolve` does
    # it and from the same functions -- every pixel, covered or not. The
    # host's target holds its clear color as premultiplied light and
    # resolves it like any other pixel, so a pixel nothing covers is that
    # round trip and not the background's own bytes: for a clear color
    # with an alpha of zero the two differ, since no color survives being
    # unpremultiplied by nothing. PNG stores unassociated alpha, and alpha
    # is coverage rather than color so it skips the transfer function. A
    # pixel that holds data skips the curve, as the host's target skips it.
    var lit = FloatColor(mixed_r, mixed_g, mixed_b, mixed_a).unpremultiplied()
    var curve = Int(tone)
    if data:
        curve = NO_TONE_MAPPING.value
    var word = pack(tone_map(lit, ToneMapping(curve), exposure).encode())
    if solid:
        nearest_depth = nearest

    # Every pixel is written, background included. Clearing on the host and
    # uploading that buffer would cost more than the render; letting each
    # thread decide its own color costs nothing.
    var slot = y * Int(width) + x
    # The depth this thread settled on, written out rather than discarded.
    # A framebuffer that reports infinity everywhere would let a later
    # depth-tested triangle paint over a nearer surface already drawn here.
    depth[unsafe_offset=slot] = nearest_depth

    var offset = slot * 4
    pixels[unsafe_offset=offset] = UInt8((word >> 24) & 0xFF)
    pixels[unsafe_offset=offset + 1] = UInt8((word >> 16) & 0xFF)
    pixels[unsafe_offset=offset + 2] = UInt8((word >> 8) & 0xFF)
    pixels[unsafe_offset=offset + 3] = UInt8(word & 0xFF)


struct GpuRenderer(Movable):
    """A GPU rasterizer that keeps its device context and buffers.

    Creating a `DeviceContext` and allocating a render target are not cheap,
    and an animation does the same draw hundreds of times at the same size.
    Holding them here means a frame costs an upload, a launch and a readback
    rather than a fresh allocation of everything.

    Reading the image back is a separate call, because it is a separate cost:
    a pipeline that draws several times before showing anything should pay it
    once, not once per draw.
    """

    var width: Int
    var height: Int
    # How many triangles the vertex buffer can currently hold.
    var capacity: Int
    # False until the first successful `draw`, so `read_back` cannot hand
    # back whatever the allocation happened to contain.
    var drawn: Bool
    # The depth mode of the last `draw`, which says what a pixel no
    # primitive claimed reads back as: see `read_back`.
    var depth_mode: DepthMode
    # Every device buffer is declared before the context that owns it, and
    # `__deinit__` releases them in that order. The order is load-bearing;
    # see `__deinit__` for the hang it prevents.
    var pixels: DeviceBuffer[DType.uint8]
    var depth: DeviceBuffer[DType.float32]
    var corners: DeviceBuffer[DType.float32]
    # The camera's position, then the ambient term, then six floats per
    # directional light, eight per point light, nine per hemisphere light
    # and thirteen per spot light. Grown on demand like the corner buffer;
    # a scene's lights rarely change count, so this settles after the first
    # frame.
    var lights: DeviceBuffer[DType.float32]
    var light_room: Int
    # The scene's fog as the rasterizers take it, `FOG_FLOATS` floats,
    # rewritten every draw. Its kind crosses as a kernel argument.
    var fog: DeviceBuffer[DType.float32]
    # One texture id per triangle, beside the vertex buffer rather than in it.
    var maps: DeviceBuffer[DType.int32]
    # The segments, and how many the two line buffers have room for. Their
    # own pair rather than a second use of the triangle buffers: a frame
    # usually has both, and reusing one would mean two launches where the
    # kernel does both passes in one.
    var segments: DeviceBuffer[DType.float32]
    var segment_maps: DeviceBuffer[DType.int32]
    var line_capacity: Int
    # The points, their state and how many the two have room for: a third
    # pair, for the reason the segments have their own.
    var points: DeviceBuffer[DType.float32]
    var point_maps: DeviceBuffer[DType.int32]
    var point_capacity: Int
    # The frame's draw order, `INTS_PER_DRAW` integers a draw, and how many
    # draws the buffer has room for.
    var draw_list: DeviceBuffer[DType.int32]
    var draw_room: Int
    # Every texture the scene can sample, uploaded once rather than per draw.
    var texels: DeviceBuffer[DType.uint8]
    var table: DeviceBuffer[DType.int32]
    # The 256 linear values an sRGB byte stands for. One copy for every
    # texture, uploaded once: it is the same table for all of them.
    var ramp: DeviceBuffer[DType.float32]
    # How many descriptors the table actually holds. The kernel indexes it
    # with a number that arrived on a vertex, so something has to know where
    # the table ends; nothing on the device can find out.
    var uploaded: Int
    # Per uploaded texture, whether it ignores its alpha: what an emissive
    # map must do, and a question the host answers before the launch, as the
    # CPU rasterizer answers it before the first fragment.
    var ignores_alpha: List[Bool]
    # Per uploaded texture, whether it is stored linear. An alpha map must
    # be, since its green is a coverage rather than a color.
    var is_linear: List[Bool]
    # Per uploaded texture, whether it holds texels at all. A blank texture
    # crosses as one white texel so the kernel never reads a zero width, so
    # a gradient map of no tones would step nowhere; refused here instead.
    var has_texels: List[Bool]
    # Per uploaded texture, how many rows it has. A gradient map must have
    # exactly one: the kernel reads the row the host reads, and a taller
    # image has no unambiguous one. See `check_gradient_map`.
    var heights: List[Int]
    # Per uploaded texture, whether it holds floats. A gradient map must
    # not: the kernel reads its ramp one byte a tone, as the host does.
    var holds_floats: List[Bool]
    # How many cube textures the last upload laid out after the flat
    # textures, six rows each. A triangle's env map id is checked against
    # it before the launch, as its texture id is against `uploaded`.
    var uploaded_cubes: Int
    # A scene's image background, one pixel per pixel of the target, read
    # by the kernel where its alpha is full; see `Renderer.backdrop`.
    # Rewritten by every draw that has one, and cleared to transparent by
    # the first draw after it that has none: `painted` says which.
    var backdrop: DeviceBuffer[DType.uint8]
    var painted: Bool
    # Declared last so that it is released last. See `__deinit__`.
    var context: DeviceContext

    def __deinit__(deinit self):
        """Drain the queue, release the buffers, then release the context.

        Both the wait and the order are load-bearing. Under CUDA on WSL 2 with
        MAX 26.5.0, two things each leave the driver in a state where the
        *next* context's first allocation never returns: tearing a context
        down while buffers it allocated are still alive, and tearing it down
        while a launch it enqueued is still in flight. This struct used to
        declare `context` first, so it was destroyed first, and nothing waited
        for an unread `draw`; a second `GpuRenderer` in the same process then
        hung in its constructor, and every GPU test after it sat forever.
        Metal tolerated both, which is why neither was seen.

        Spelled out rather than left to declaration order, so a field reorder
        cannot quietly bring the hang back. Reproducer and notes are in
        `docs/max-gpu-teardown-issue/`.
        """
        # A destructor cannot raise, and a context that cannot even be waited
        # on has nothing left worth reporting.
        try:
            self.context.synchronize()
        except:
            pass
        _ = self.pixels^
        _ = self.depth^
        _ = self.corners^
        _ = self.lights^
        _ = self.fog^
        _ = self.maps^
        _ = self.segments^
        _ = self.segment_maps^
        _ = self.points^
        _ = self.point_maps^
        _ = self.draw_list^
        _ = self.texels^
        _ = self.table^
        _ = self.ramp^
        _ = self.backdrop^
        _ = self.context^

    def __init__(out self, width: Int, height: Int) raises:
        """Create a renderer and its device buffers for a fixed image size.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.

        Raises:
            Error: If the dimensions are not positive, or no GPU is present.
        """
        if width <= 0 or height <= 0:
            raise Error("Framebuffer dimensions must be positive")
        if not available():
            raise Error("No GPU available")
        self.width = width
        self.height = height
        self.drawn = False
        self.depth_mode = STANDARD_DEPTH
        self.context = DeviceContext()
        self.pixels = self.context.enqueue_create_buffer[DType.uint8](
            width * height * Framebuffer.CHANNELS
        )
        self.depth = self.context.enqueue_create_buffer[DType.float32](
            width * height
        )
        # Room for the camera, its direction, its up axis, the ambient term
        # and one directional light to begin with.
        self.light_room = LIGHTS_FIRST + 6
        self.lights = self.context.enqueue_create_buffer[DType.float32](
            self.light_room
        )
        self.fog = self.context.enqueue_create_buffer[DType.float32](FOG_FLOATS)
        # One triangle to start with; `draw` grows it as needed. Never zero,
        # because a zero-length device buffer is not worth the special case.
        self.capacity = 1
        self.corners = self.context.enqueue_create_buffer[DType.float32](
            FLOATS_PER_TRIANGLE
        )
        self.maps = self.context.enqueue_create_buffer[DType.int32](
            STATE_PER_TRIANGLE
        )
        # One segment's worth, for the reason one triangle's is allocated
        # here: a frame with no lines still hands the kernel a pointer.
        self.line_capacity = 1
        self.segments = self.context.enqueue_create_buffer[DType.float32](
            2 * FLOATS_PER_VERTEX
        )
        self.segment_maps = self.context.enqueue_create_buffer[DType.int32](
            STATE_PER_LINE
        )
        # One point's worth, for the same reason.
        self.point_capacity = 1
        self.points = self.context.enqueue_create_buffer[DType.float32](
            FLOATS_PER_VERTEX
        )
        self.point_maps = self.context.enqueue_create_buffer[DType.int32](
            STATE_PER_POINT
        )
        # Three draws' worth: the order a frame with no list of its own
        # gets, every triangle, then every segment, then every point.
        self.draw_room = 3
        self.draw_list = self.context.enqueue_create_buffer[DType.int32](
            self.draw_room * INTS_PER_DRAW
        )
        # One texel's worth, standing in for the blank texture. A zero-length
        # device buffer is not worth the special case, and a width of zero is
        # what the kernel actually reads to mean "no texture".
        self.texels = self.context.enqueue_create_buffer[DType.uint8](4)
        self.table = self.context.enqueue_create_buffer[DType.int32](
            TABLE_COLUMNS
        )
        # Allocated but never filled, so until `set_textures` runs the only
        # legal reference is NO_TEXTURE.
        self.uploaded = 0
        self.uploaded_cubes = 0
        self.ignores_alpha = List[Bool]()
        self.is_linear = List[Bool]()
        self.has_texels = List[Bool]()
        self.heights = List[Int]()
        self.holds_floats = List[Bool]()
        self.backdrop = self.context.enqueue_create_buffer[DType.uint8](
            width * height * Framebuffer.CHANNELS
        )
        self.ramp = self.context.enqueue_create_buffer[DType.float32](256)
        var steps = decode_ramp()
        with self.ramp.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(), src=steps.unsafe_ptr(), count=256
            )
        # Transparent everywhere, so the first draw reads the clear color
        # rather than whatever the allocation held. Last, once every
        # field is set, because it is a method.
        self.painted = True
        self._clear_backdrop()

    def _clear_backdrop(mut self) raises:
        """Make every backdrop pixel transparent, once, after a draw that
        painted one is followed by a draw that does not.

        Raises:
            Error: If the device buffer cannot be written.
        """
        if not self.painted:
            return
        var count = self.width * self.height * Framebuffer.CHANNELS
        var clear = List[UInt8](length=count, fill=0)
        with self.backdrop.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(), src=clear.unsafe_ptr(), count=count
            )
        self.painted = False

    def _upload_lights(mut self, lighting: Lighting) raises:
        """Put `lighting` on the device.

        Args:
            lighting: The scene's lights, resolved to world space.

        Raises:
            Error: If the device buffer cannot be made or written.
        """
        var flat = flatten_lights(lighting)
        if len(flat) > self.light_room:
            # A draw still in flight may be reading the old buffer; see
            # `set_textures`, which waits for the same reason.
            self.context.synchronize()
            self.lights = self.context.enqueue_create_buffer[DType.float32](
                len(flat)
            )
            self.light_room = len(flat)
        with self.lights.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=flat.unsafe_ptr(),
                count=len(flat),
            )

    def _upload_fog(mut self, fog: FogView) raises:
        """Put `fog` on the device.

        Args:
            fog: The scene's fog, as the rasterizers take it.

        Raises:
            Error: If the device buffer cannot be written.
        """
        var flat = flatten_fog(fog)
        with self.fog.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=flat.unsafe_ptr(),
                count=len(flat),
            )

    def draw(
        mut self,
        corners: List[RasterVertex],
        background: Color,
        mode: ShadeMode = SHADE_LIT,
        lighting: Lighting = Lighting.uniform(),
        fog: FogView = FogView.none(),
        tone_mapping: ToneMapping = NO_TONE_MAPPING,
        exposure: Float32 = 1.0,
        lines: List[RasterVertex] = List[RasterVertex](),
        draws: List[Draw] = List[Draw](),
        scissor: Optional[Rect] = None,
        points: List[RasterVertex] = List[RasterVertex](),
        backdrop: Optional[Framebuffer] = None,
        line_width: Int = 1,
        depth_mode: DepthMode = STANDARD_DEPTH,
    ) raises:
        """Rasterize prepared triangles, lines and points into the device
        target.

        Args:
            corners: Raster vertices, three per triangle. An empty list is
                allowed and clears the target to `background`.
            background: Color for pixels no triangle covers.
            mode: `SHADE_LIT`, `SHADE_UV` or `SHADE_TEXTURE`, as
                `rasterize_shaded` takes.
            lighting: The scene's lights, resolved to world space and
                evaluated per fragment against the interpolated normal.
                Defaults to `Lighting.uniform`, the identity for the multiply,
                exactly as the CPU rasterizer's does. A `NORMALS` or `DEPTH`
                triangle shows data instead, kept out of the lights, the
                fog and the tone mapping as the CPU keeps it.
            fog: The scene's fog, as `rasterize_shaded` takes it. Defaults
                to `FogView.none`.
            tone_mapping: The curve that compresses each finished pixel's
                light, as `RenderTarget.resolve` takes it. Defaults to
                `NO_TONE_MAPPING`. The uv view is never tone mapped.
            exposure: What the light is scaled by before the curve.
            lines: Raster vertices, two per segment. Empty by default.
            draws: The order to draw in, as runs of triangles, of
                segments or of points; see `render.rasterizer.Draw`.
                Empty, the default, draws every triangle, then every
                segment, then every point, which is the order
                `rasterize_all`, `rasterize_lines_all` and
                `rasterize_points_all` draw them in. `Renderer.prepare_frame`
                gives the order `Renderer.render` uses, with blended
                triangles, segments and points sorted together.
            scissor: The pixels this draw may touch, or none for all of
                them: three.js's `setScissor` with the test on. A pixel
                outside is neither cleared nor drawn, so a second draw
                into another rectangle leaves this one's pixels alone.
                The corner counts up from the bottom; see `render.rect`.
            points: Raster vertices, one per point. Empty by default.
            backdrop: A scene's image background, as `Renderer.backdrop`
                paints it: a pixel with full alpha is what the pixel holds
                before anything is drawn, and any other pixel holds the
                clear color. None, the default, clears to `background`
                alone. It must be the target's size.
            line_width: How many raster pixels across every segment is,
                the renderer's render scale, which the host passes to
                `render.rasterizer.rasterize_frame` and both backends read
                from `render.linerule`. One, the default, is a frame drawn
                at its own size; a caller preparing a supersampled frame
                through `Renderer.supersampled` passes that renderer's
                `render_scale`, or the lines it draws thin out when the
                frame is averaged down. Below one is treated as one.
            depth_mode: The mode the frame's primitives carry,
                `Renderer.depth_mode_for` of the camera. Each primitive
                stores and compares by its own state; this says only what
                `read_back` gives a pixel none of them claimed. The
                default is `STANDARD_DEPTH`.

        Raises:
            Error: If the corner count is not a multiple of three, the
                line corner count is not a multiple of two, a segment's
                ends disagree or its material is lit, a point is refused
                by `check_point_state` or names a map that is not
                uploaded, a draw is refused
                by `check_draws`, the mode
                is none of the three, the tone mapping is none of the
                seven, the exposure is negative or not finite, the fog
                view is refused by `FogView.validate`, a triangle's blend
                policy, material kind, texture or
                emissive map disagrees between its corners or is a value
                neither backend knows, a vertex names a texture, an
                emissive map or an alpha map that is not uploaded, an
                emissive map that
                `SHADE_TEXTURE` would open does not ignore its alpha, an
                alpha map it would open is not linear or does not ignore
                its alpha, a vertex names a cube texture that is not
                uploaded, a spot light's map names a texture that is not
                uploaded, the backdrop is not the target's size, or the
                depth mode is none of the three.
        """
        if not depth_mode.is_valid():
            raise Error("A depth mode that is none of the three")
        if len(corners) % 3 != 0:
            raise Error("Rasterizing needs whole triangles")
        if len(lines) % 2 != 0:
            raise Error("Rasterizing needs whole segments")
        if not mode.is_valid():
            raise Error("A shading mode that is none of the three")
        # The kernel cannot raise on a curve or a fog it does not know, so
        # the refusals `RenderTarget.resolve` and `rasterize_all` make are
        # made here, before the launch, by the same functions.
        check_tone_mapping(tone_mapping, exposure)
        fog.validate()
        # Clamped once here rather than per pixel in the kernel, and
        # clamped the same way `rasterize_line` clamps it on the host.
        var strokes = line_width
        if strokes < 1:
            strokes = 1
        var kept = Rect.whole(self.width, self.height)
        var narrowed = Bool(scissor)
        if narrowed:
            kept = scissor.value()
            if not kept.fits(self.width, self.height):
                raise Error("A scissor must lie inside the target")
            # A pixel outside the scissor is left as it was, and on a
            # fresh target "as it was" is whatever the device buffer held.
            # The first draw clears the whole target first, so the rest
            # is the background -- resolved through this draw's own mode,
            # curve and exposure, as the host resolves a whole fresh target
            # through one curve. Cleared with the defaults, a white
            # background under Reinhard came back white outside the
            # scissor and gray inside it.
            if not self.drawn:
                self.draw(
                    List[RasterVertex](),
                    background,
                    mode,
                    tone_mapping=tone_mapping,
                    exposure=exposure,
                    depth_mode=depth_mode,
                )
        var triangles = len(corners) // 3

        # The same per-triangle check the CPU makes, from the same function,
        # so an unknown blend policy cannot mean one thing here and another
        # there -- see `check_triangle_state`.
        for triangle in range(triangles):
            check_triangle_state(
                corners[triangle * 3],
                corners[triangle * 3 + 1],
                corners[triangle * 3 + 2],
            )

        # The same per-segment check the host makes, from the same
        # function, for the reason the triangles' is made here: the kernel
        # cannot raise on a policy it does not know.
        for segment in range(len(lines) // 2):
            check_line_state(lines[segment * 2], lines[segment * 2 + 1])
        # And the same per-point check, for the same reason.
        for point in range(len(points)):
            check_point_state(points[point])
        # The order, or the three-pass one when none is given. Checked by
        # the function the host checks with: the kernel reads the corner
        # buffers at whatever index a draw hands it.
        var order = draws.copy()
        if len(order) == 0:
            order.append(Draw(DRAW_TRIANGLES, 0, triangles))
            order.append(Draw(DRAW_SEGMENTS, 0, len(lines) // 2))
            order.append(Draw(DRAW_POINTS, 0, len(points)))
        check_draws(order, triangles, len(lines) // 2, len(points))

        # Every texture reference is checked here because it cannot be checked
        # on the device: the kernel reads the descriptor table at whatever
        # index a vertex hands it, and an index past the end is an unchecked
        # read of device memory. The CPU rasterizer gets this for free from
        # `TextureStore.get`, which raises; without this the two backends
        # failed differently on the same bad input.
        for index in range(len(corners)):
            for slot in [
                corners[index].texture,
                corners[index].emissive_map,
                corners[index].alpha_map,
                corners[index].gradient_map,
                corners[index].matcap,
                corners[index].roughness_map,
                corners[index].metalness_map,
                corners[index].normal_map,
                corners[index].bump_map,
                corners[index].ao_map,
                corners[index].light_map,
                corners[index].specular_map,
            ]:
                if slot == NO_TEXTURE:
                    continue
                if slot.value < 0 or slot.value >= self.uploaded:
                    raise Error(
                        "A vertex names a texture that has not been uploaded;"
                        " call set_textures() first"
                    )
            # The env map, checked the same way against the cubes the last
            # upload laid out. `check_triangle_state` has refused every
            # negative but `NO_CUBE_TEXTURE`.
            var cube = corners[index].env_map
            if cube != NO_CUBE_TEXTURE and cube.value >= self.uploaded_cubes:
                raise Error(
                    "A vertex names a cube texture that has not been"
                    " uploaded; call set_textures() first"
                )
        # A spot light's map, checked the same way: the kernel samples it
        # through the same table.
        for slot in range(len(lighting.spot_maps)):
            var named = lighting.spot_maps[slot].texture
            if named.value < 0 or named.value >= self.uploaded:
                raise Error(
                    "A spot light's map names a texture that has not been"
                    " uploaded; call set_textures() first"
                )
        # A point's two maps, checked the same way and for the same
        # reason, and its alpha map for holding data as a triangle's is.
        for index in range(len(points)):
            for slot in [points[index].texture, points[index].alpha_map]:
                if slot == NO_TEXTURE:
                    continue
                if slot.value < 0 or slot.value >= self.uploaded:
                    raise Error(
                        "A point names a texture that has not been uploaded;"
                        " call set_textures() first"
                    )
            var mask = points[index].alpha_map
            if mask != NO_TEXTURE and mode == SHADE_TEXTURE:
                if not self.is_linear[mask.value]:
                    raise Error(
                        "An alpha map holds data, not color; build the"
                        " texture with color_space=LINEAR"
                    )
                if not self.ignores_alpha[mask.value]:
                    raise Error(
                        "An alpha map must ignore its own alpha; build"
                        " the texture with alpha=IGNORED"
                    )
        # An emissive map's alpha means nothing, and only a texture built to
        # ignore it filters accordingly -- see `render.texture.Alpha`. Asked
        # here, before the launch, exactly where `rasterize_shaded` asks it
        # before the first fragment, and only when the map will be opened.
        if mode == SHADE_TEXTURE:
            for triangle in range(triangles):
                var glow = corners[triangle * 3].emissive_map
                if glow != NO_TEXTURE and not self.ignores_alpha[glow.value]:
                    raise Error(
                        "An emissive map must ignore its alpha; build the"
                        " texture with alpha=IGNORED"
                    )
                # An alpha map holds data and must say so twice; the same
                # question `check_alpha_map` asks on the host, asked of the
                # descriptors this renderer uploaded.
                var mask = corners[triangle * 3].alpha_map
                if mask != NO_TEXTURE:
                    if not self.is_linear[mask.value]:
                        raise Error(
                            "An alpha map holds data, not color; build the"
                            " texture with color_space=LINEAR"
                        )
                    if not self.ignores_alpha[mask.value]:
                        raise Error(
                            "An alpha map must ignore its own alpha; build"
                            " the texture with alpha=IGNORED"
                        )
                # The maps that hold numbers, asked the same two
                # questions with the same words `check_data_map` uses.
                self._check_data_map(
                    corners[triangle * 3].roughness_map, "A roughness map"
                )
                self._check_data_map(
                    corners[triangle * 3].metalness_map, "A metalness map"
                )
                self._check_data_map(
                    corners[triangle * 3].normal_map, "A normal map"
                )
                self._check_data_map(
                    corners[triangle * 3].bump_map, "A bump map"
                )
                # An ao map holds a number, and a light map light whose
                # alpha means nothing: `check_triangle_maps`'s two rules.
                self._check_data_map(corners[triangle * 3].ao_map, "An ao map")
                var baked = corners[triangle * 3].light_map
                if baked != NO_TEXTURE and not self.ignores_alpha[baked.value]:
                    raise Error(
                        "A light map must ignore its alpha; build the"
                        " texture with alpha=IGNORED"
                    )
                self._check_data_map(
                    corners[triangle * 3].specular_map, "A specular map"
                )
        # Two output representations cannot share a tone-mapped frame.
        # Asked here, before the launch, exactly where `Renderer.render`
        # asks it before it draws. The uv view is data throughout and is
        # never tone mapped, so it is never refused.
        check_output_kinds(
            corners,
            mode != SHADE_UV and tone_mapping != NO_TONE_MAPPING,
            lines,
            points,
        )
        # A ramp holds data and says so the same two ways, and must hold
        # texels to step through. Asked under every mode that lights the
        # surface rather than under `SHADE_TEXTURE` alone, because
        # `SHADE_LIT` shades a toon surface and reads the ramp -- exactly
        # where `rasterize_shaded` asks it.
        if mode != SHADE_UV:
            for triangle in range(triangles):
                var tones = corners[triangle * 3].gradient_map
                if tones == NO_TEXTURE:
                    continue
                if not self.has_texels[tones.value]:
                    raise Error(
                        "A gradient map must hold texels: name no map for"
                        " the fallback"
                    )
                if self.heights[tones.value] != 1:
                    raise Error(
                        "A gradient map must be one row high: it is a lookup"
                        " table, not a picture, and a taller image has no"
                        " unambiguous row"
                    )
                if not self.is_linear[tones.value]:
                    raise Error(
                        "A gradient map holds data, not color; build the"
                        " texture with color_space=LINEAR"
                    )
                if not self.ignores_alpha[tones.value]:
                    raise Error(
                        "A gradient map must ignore its own alpha; build"
                        " the texture with alpha=IGNORED"
                    )
                if self.holds_floats[tones.value]:
                    raise Error(
                        "A gradient map must hold bytes: its tones are read"
                        " one byte each"
                    )
            # A matcap's own alpha means nothing either, and only a
            # texture built to ignore it filters correctly. Its own loop,
            # because a triangle with a matcap rarely has a ramp as well.
            for triangle in range(triangles):
                var ball = corners[triangle * 3].matcap
                if ball == NO_TEXTURE:
                    continue
                if not self.ignores_alpha[ball.value]:
                    raise Error(
                        "A matcap must ignore its alpha; build the texture"
                        " with alpha=IGNORED"
                    )

        if triangles > self.capacity:
            # Grow to exactly what is asked for. Frames tend to submit the
            # same count repeatedly, so this settles after the first one.
            # A draw still in flight may be reading the old buffers; see
            # `set_textures`, which waits for the same reason.
            self.context.synchronize()
            self.corners = self.context.enqueue_create_buffer[DType.float32](
                triangles * FLOATS_PER_TRIANGLE
            )
            self.maps = self.context.enqueue_create_buffer[DType.int32](
                triangles * STATE_PER_TRIANGLE
            )
            self.capacity = triangles

        if triangles > 0:
            var flat = flatten(corners)
            with self.corners.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=flat.unsafe_ptr(),
                    count=len(flat),
                )
            var state = triangle_state(corners, self.uploaded)
            with self.maps.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=state.unsafe_ptr(),
                    count=len(state),
                )

        var line_count = len(lines) // 2
        if line_count > self.line_capacity:
            self.context.synchronize()
            self.segments = self.context.enqueue_create_buffer[DType.float32](
                line_count * 2 * FLOATS_PER_VERTEX
            )
            self.segment_maps = self.context.enqueue_create_buffer[DType.int32](
                line_count * STATE_PER_LINE
            )
            self.line_capacity = line_count

        if line_count > 0:
            var drawn = flatten(lines)
            with self.segments.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=drawn.unsafe_ptr(),
                    count=len(drawn),
                )
            var policies = line_state(lines, strokes)
            with self.segment_maps.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=policies.unsafe_ptr(),
                    count=len(policies),
                )

        var point_count = len(points)
        if point_count > self.point_capacity:
            self.context.synchronize()
            self.points = self.context.enqueue_create_buffer[DType.float32](
                point_count * FLOATS_PER_VERTEX
            )
            self.point_maps = self.context.enqueue_create_buffer[DType.int32](
                point_count * STATE_PER_POINT
            )
            self.point_capacity = point_count

        if point_count > 0:
            var dots = flatten(points)
            with self.points.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=dots.unsafe_ptr(),
                    count=len(dots),
                )
            var dot_state = point_state(points)
            with self.point_maps.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=dot_state.unsafe_ptr(),
                    count=len(dot_state),
                )

        if len(order) > self.draw_room:
            self.context.synchronize()
            self.draw_list = self.context.enqueue_create_buffer[DType.int32](
                len(order) * INTS_PER_DRAW
            )
            self.draw_room = len(order)
        var flat_draws = List[Int32]()
        flat_draws.reserve(len(order) * INTS_PER_DRAW)
        for index in range(len(order)):  # pragma: no branch
            flat_draws.append(Int32(order[index].kind.value))
            flat_draws.append(Int32(order[index].first))
            flat_draws.append(Int32(order[index].count))
        with self.draw_list.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=flat_draws.unsafe_ptr(),
                count=len(flat_draws),
            )

        self._upload_lights(lighting)
        self._upload_fog(fog)
        # The backdrop, whole, rewritten for this draw, or cleared if the
        # last draw painted one and this one does not. A pixel it leaves
        # transparent is the clear color on the device as on the host.
        # Spelled as a Bool for the coverage instrumenter's probe, as
        # `scissor` is above.
        var given = Bool(backdrop)
        if given:
            ref image = backdrop.value()
            if image.width != self.width or image.height != self.height:
                raise Error("A backdrop must be the target's size")
            with self.backdrop.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=image.pixels.unsafe_ptr(),
                    count=len(image.pixels),
                )
            self.painted = True
        else:
            self._clear_backdrop()
        # The uv view is coordinates rather than light and is never tone
        # mapped, background included, exactly as `Renderer.render` turns
        # the curve off for it. The curve was checked above as given;
        # what the kernel is handed is what the host resolves with.
        var curve = tone_mapping
        if mode == SHADE_UV:
            curve = NO_TONE_MAPPING
        self.context.enqueue_function[rasterize_kernel](
            self.pixels.unsafe_ptr(),
            self.depth.unsafe_ptr(),
            self.corners.unsafe_ptr(),
            self.maps.unsafe_ptr(),
            Int32(self.width),
            Int32(self.height),
            pack(background),
            Int32(mode.value),
            self.texels.unsafe_ptr(),
            self.table.unsafe_ptr(),
            self.ramp.unsafe_ptr(),
            self.lights.unsafe_ptr(),
            Int32(lighting.count()),
            Int32(lighting.point_count()),
            Int32(lighting.hemisphere_count()),
            Int32(lighting.spot_count()),
            self.fog.unsafe_ptr(),
            Int32(fog.kind.value),
            Int32(curve.value),
            exposure,
            self.segments.unsafe_ptr(),
            self.segment_maps.unsafe_ptr(),
            self.points.unsafe_ptr(),
            self.point_maps.unsafe_ptr(),
            self.draw_list.unsafe_ptr(),
            Int32(len(order)),
            Int32(kept.x),
            Int32(kept.y),
            Int32(kept.width),
            Int32(kept.height),
            self.backdrop.unsafe_ptr(),
            grid_dim=(
                ceildiv(self.width, TILE),
                ceildiv(self.height, TILE),
            ),
            block_dim=(TILE, TILE),
        )
        self.drawn = True
        self.depth_mode = depth_mode

    def set_textures(
        mut self,
        textures: TextureStore,
        cubes: CubeTextureStore = CubeTextureStore(),
    ) raises:
        """Upload every texture in `textures` and every cube texture in
        `cubes`, replacing any previous set.

        Separate from `draw` on purpose: an animation samples the same images
        every frame, and re-uploading them each time would cost more than the
        rasterization does.

        **The replacement is all or nothing.** The new texel buffer and the
        new descriptor table are built and filled as locals, and only once
        both exist are they moved into place together with the count that
        describes them. This used to replace the fields one at a time and
        set the count last, which kept the old *count* after a failure but
        not the old *resources*: a table allocation that failed left the new
        texels under the old table, and a draw that passed the id check then
        read the new bytes with the old offsets. What a failure leaves now is
        the previous upload, whole.

        Args:
            textures: The store to upload. An empty one is allowed and means
                no mesh can be textured.
            cubes: The cube textures to upload after it, six faces each.
                An empty one is allowed and means no mesh can reflect.

        Raises:
            Error: If a texture holds a wrap, filter or color space that is
                none of the named values, a cube texture is refused by
                `CubeTexture.validate`, or the device buffers cannot be
                made or filled. Either way nothing on the device has changed.
        """
        var flattened = flatten_textures(textures, cubes)
        ref bytes = flattened[0]
        ref rows = flattened[1]

        var texels = self.context.enqueue_create_buffer[DType.uint8](len(bytes))
        with texels.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=bytes.unsafe_ptr(),
                count=len(bytes),
            )
        var table = self.context.enqueue_create_buffer[DType.int32](len(rows))
        with table.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=rows.unsafe_ptr(),
                count=len(rows),
            )
        # Everything that can fail has. A draw already in flight may still be
        # reading the old buffers, so let it finish before they are released
        # by the moves below; replacing a resource and tearing the renderer
        # down are two different lifetimes, and `__deinit__` only covers the
        # second.
        self.context.synchronize()
        self.texels = texels^
        self.table = table^
        self.uploaded = textures.count()
        self.uploaded_cubes = cubes.count()
        # Every one of these describes the upload that has just
        # replaced the last, so every one of them is replaced. `heights`
        # was appended to instead, which left a second upload validating
        # its gradient maps against the first upload's rows: a good
        # one-row ramp was refused because the texture that used to hold
        # that id was two rows tall.
        self.ignores_alpha = List[Bool]()
        self.is_linear = List[Bool]()
        self.has_texels = List[Bool]()
        self.heights = List[Int]()
        self.holds_floats = List[Bool]()
        for id in range(textures.count()):
            ref image = textures.get(TextureId(id))
            self.ignores_alpha.append(image.alpha == IGNORED)
            self.is_linear.append(image.color_space == LINEAR)
            self.has_texels.append(not image.is_blank())
            self.heights.append(image.height)
            self.holds_floats.append(image.texel_type == FLOAT_TYPE)

    def _check_data_map(self, map: TextureId, name: String) raises:
        """Refuse a map that holds data and was not uploaded as data: the
        question `check_data_map` asks on the host, asked of the
        descriptors this renderer uploaded.

        Args:
            map: The id a triangle names, or `NO_TEXTURE` for none.
            name: What to call it in the error.

        Raises:
            Error: If the texture is not linear or reads its alpha as
                coverage.
        """
        if map == NO_TEXTURE:
            return
        if not self.is_linear[map.value]:
            raise Error(
                name
                + " holds data, not color; build the texture with"
                " color_space=LINEAR"
            )
        if not self.ignores_alpha[map.value]:
            raise Error(
                name
                + " must ignore its own alpha; build the texture with"
                " alpha=IGNORED"
            )

    def read_back(self) raises -> Framebuffer:
        """Copy the device render target into a host framebuffer.

        Both the color and the depth come back, so the result is the same
        kind of thing the CPU renderer produces and can be drawn into again.

        Returns:
            The rendered image, with its depth buffer.

        Raises:
            Error: If nothing has been drawn yet, or the framebuffer cannot
                be built from the bytes.
        """
        if not self.drawn:
            raise Error(
                "Nothing has been drawn yet; call draw() before read_back()"
            )
        var count = self.width * self.height * Framebuffer.CHANNELS
        var pixels = List[UInt8](length=count, fill=0)
        with self.pixels.map_to_host() as host:
            # One bulk copy, not a loop. Copying byte by byte here costs more
            # than the kernel does by an order of magnitude and dominates the
            # render.
            unsafe_memcpy(
                dest=pixels.unsafe_ptr(), src=host.unsafe_ptr(), count=count
            )
        var depth = List[Float32](
            length=self.width * self.height, fill=inf[DType.float32]()
        )
        with self.depth.map_to_host() as host:
            unsafe_memcpy(
                dest=depth.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=self.width * self.height,
            )
        # The kernel writes infinity where no primitive claimed the depth.
        # Under `REVERSED_DEPTH` the clear is minus infinity, as the host's
        # target holds it.
        if self.depth_mode == REVERSED_DEPTH:
            for slot in range(len(depth)):
                if depth[slot] == inf[DType.float32]():
                    depth[slot] = cleared_depth(REVERSED_DEPTH)
        return Framebuffer(self.width, self.height, pixels^, depth^)


def render_triangles(
    corners: List[RasterVertex],
    width: Int,
    height: Int,
    background: Color,
    mode: ShadeMode = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    lighting: Lighting = Lighting.uniform(),
    fog: FogView = FogView.none(),
    tone_mapping: ToneMapping = NO_TONE_MAPPING,
    exposure: Float32 = 1.0,
    lines: List[RasterVertex] = List[RasterVertex](),
    draws: List[Draw] = List[Draw](),
    scissor: Optional[Rect] = None,
    points: List[RasterVertex] = List[RasterVertex](),
    cubes: CubeTextureStore = CubeTextureStore(),
    backdrop: Optional[Framebuffer] = None,
) raises -> Framebuffer:
    """Draw prepared triangles, lines and points on the GPU and read the
    image back.

    A convenience for one-shot renders. Anything drawing repeatedly should
    hold a `GpuRenderer` instead, so the context and buffers survive between
    frames rather than being rebuilt for each one.

    Args:
        corners: Raster vertices, three per triangle.
        width: Image width in pixels.
        height: Image height in pixels.
        background: Color for pixels no triangle covers.
        mode: `SHADE_LIT`, `SHADE_UV` or `SHADE_TEXTURE`.
        textures: The images `SHADE_TEXTURE` samples, named per vertex.
        lighting: The scene's lights, evaluated per fragment. Defaults to
            `Lighting.uniform`, which leaves the corner colors alone.
        fog: The scene's fog, as the rasterizers take it. Defaults to
            `FogView.none`, which leaves every fragment alone.
        tone_mapping: The curve that compresses each pixel's light, as
            `RenderTarget.resolve` takes it. Defaults to `NO_TONE_MAPPING`.
        exposure: What the light is scaled by before the curve.
        lines: Raster vertices, two per segment. Empty by default.
        draws: The order to draw in, or empty for every triangle and then
            every segment; see `GpuRenderer.draw`.
        scissor: The pixels the draw may touch, or none for all of them.
        points: Raster vertices, one per point. Empty by default.
        cubes: The cube textures the triangles reflect. Empty by default.
        backdrop: A scene's image background, or none; see
            `GpuRenderer.draw`.

    Returns:
        The rendered image.

    Raises:
        Error: If the dimensions are invalid, no GPU is present, the corner
            count is not a multiple of three, or the line corner count is
            not a multiple of two.
    """
    var renderer = GpuRenderer(width, height)
    renderer.set_textures(textures, cubes)
    renderer.draw(
        corners,
        background,
        mode,
        lighting,
        fog,
        tone_mapping,
        exposure,
        lines,
        draws,
        scissor,
        points,
        backdrop,
    )
    return renderer.read_back()


def render(
    triangle: Triangle,
    width: Int,
    height: Int,
    background: Color,
    foreground: Color,
) raises -> Framebuffer:
    """Rasterize one flat triangle on the GPU, in a single color.

    The shape the benchmark and the parity tests use. Depth and perspective
    are neutral here — one triangle at a constant depth with no perspective —
    so this measures coverage and nothing else.

    Args:
        triangle: Screen-space triangle to fill.
        width: Image width in pixels.
        height: Image height in pixels.
        background: Color for pixels the triangle does not cover.
        foreground: Color for pixels it does.

    Returns:
        A framebuffer holding the rendered image.

    Raises:
        Error: If the dimensions are not positive, or no GPU is present.
    """
    var tint = FloatColor(srgb=foreground)
    var corners = List[RasterVertex]()
    corners.append(RasterVertex(triangle.a.x, triangle.a.y, 0, 1, tint, 0, 0))
    corners.append(RasterVertex(triangle.b.x, triangle.b.y, 0, 1, tint, 0, 0))
    corners.append(RasterVertex(triangle.c.x, triangle.c.y, 0, 1, tint, 0, 0))
    return render_triangles(corners^, width, height, background)
