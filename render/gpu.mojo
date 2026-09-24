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
from render.target import (
    UNSIGNED_BYTE_TARGET,
    RenderTarget,
    TargetOutput,
    TargetType,
    color_only,
)
from core.fog import NO_FOG, FogKind, FogView, fog_factor, fog_mix
from lights.shadow import (
    BASIC_SHADOW_MAP,
    CENTER_TAP,
    PCF_SOFT_SHADOW_MAP,
    PCF_TAPS,
    POINT_SHADOW_TAPS,
    SHADOW_HEADER,
    SHADOW_INTENSITY_AT,
    SHADOW_TYPE_AT,
    SOFT_TAPS,
    SPOT_MAP_FLOATS,
    VSM_SHADOW_MAP,
    biased_position,
    bilinear,
    bilinear_texel,
    cascade_reach,
    cube_tap,
    cube_texel,
    inside_point_shadow,
    inside_shadow_map,
    inside_spot_map,
    point_shadow_depth,
    point_shadow_spread,
    point_shadow_tap,
    shadow_coordinate,
    shadow_strength,
    shadow_tap,
    shadow_texel,
    soft_fraction,
    soft_shadow,
    soft_texel,
    view_depth,
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
from lights.physical_layers import (
    NO_ANISOTROPY_TEXEL,
    PhysicalLayers,
    bent_normal,
    clearcoat_of,
    iridescence_thickness,
    layers_of,
    sheen_roughness_of,
    specular_reflectance,
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
    geometry_roughness,
    occluded_light,
    physical_light,
    physical_outgoing,
    physical_surface,
    toon_coord,
    toon_index,
    toon_step,
    toward_eye_at,
    view_direction,
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
    TangentFrame,
    check_alpha_map,
    check_draws,
    check_output_kinds,
    check_transmission,
    check_triangle_state,
    bumped_normal,
    interpolate_alpha,
    mapped_normal,
    env_direction,
    object_space_normal,
    TextureFrames,
    matcap_fallback,
    matcap_uv,
    packed_normal,
    tangent_frame,
)
from render.packing import (
    DepthPacking,
    packed_depth_fragment,
    packed_distance_fragment,
)
from materials.material import (
    OPAQUE,
    DEPTH,
    DISTANCE,
    LAMBERT,
    MATCAP,
    NORMALS,
    OBJECT_SPACE_NORMAL_MAP,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    TANGENT_SPACE_NORMAL_MAP,
    TOON,
    Combine,
    combine_light,
)
from render.cube_texture import (
    FACE_COUNT,
    Basis3,
    equirect_uv,
    face_of,
    face_uv,
    reflected,
    refracted,
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
    VIEW_FLOATS,
    TransmissionSource,
    TransmissionTarget,
    transmission_alpha,
    volume_refraction,
)
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    FLOAT_TYPE,
    IGNORED,
    LINEAR_MIPMAP_LINEAR,
    NEAREST,
    UNSIGNED_BYTE_TYPE,
    UV_CHANNEL_1,
    UV_MAPPING,
    Alpha,
    Filter,
    Footprint,
    Mapping,
    TexelType,
    Texture,
    UvChannel,
    UvPlacement,
    Wrap,
    anisotropic_footprint,
    blend_texels,
    float_from_bytes,
    float_texel,
    level_filter,
    mix_color,
    mix_straight,
    plan_levels,
    row_coordinate,
    wrap_index,
)
from cameras.camera import Camera
from core.assets import Assets
from core.scene import Scene
from postprocessing.antialiasing import fxaa_pixel
from postprocessing.composer import (
    BLOOM,
    BLOOM_LEVELS,
    BLUR,
    CLEAR_MASK,
    COPY,
    DOT_SCREEN,
    FILM,
    FXAA,
    LUMINOSITY,
    MASK,
    OUTPUT,
    SEPIA,
    VIGNETTE,
    AFTERIMAGE,
    BOKEH,
    CLEAR,
    GLITCH,
    HALFTONE,
    LUT,
    TEXTURE,
    CUBE_TEXTURE,
    GOD_RAYS,
    SAVE,
    SHADER,
    SHADER_EFFECT,
    EffectComposer,
    Pass,
    PassKind,
    afterimage_pixel,
    bloom_glow,
    bloom_kernel,
    blur_pixel,
    bright_pixel,
    check_frame_time,
    check_pass,
    copy_pixel,
    depth_view,
    dot_screen_pixel,
    frame_outputs,
    film_pixel,
    glow_pixel,
    halved_size,
    luminosity_pixel,
    output_pixel,
    reads_frame_as_light,
    separable_blur_pixel,
    sepia_pixel,
    sun_on_screen,
    vignette_pixel,
)
from postprocessing.effects import (
    GlitchUniforms,
    HalftoneBlending,
    HalftoneSettings,
    HalftoneShape,
    bokeh_pixel,
    bokeh_reach,
    glitch_heightmap,
    glitch_pixel,
    glitch_uniforms,
    halftone_pixel,
    inside_mask,
    lut_pixel,
    texture_overlay,
    texture_pixel,
)
from postprocessing.render_passes import cube_overlay
from postprocessing.screen_space import DepthView
from postprocessing.sampling import LightView, Untracked, u_of, v_of
from postprocessing.shader_pass import (
    ScreenNodes,
    reads_assets,
    screen_code,
    screen_pixel,
)
from postprocessing.shaders import (
    GOD_RAYS_PASSES,
    GodRaysSettings,
    effect_floats,
    effect_from_floats,
    effect_pixel,
    god_rays_combine_pixel,
    god_rays_generate_pixel,
    god_rays_mask,
    god_rays_size,
    god_rays_step,
)
from render.target import RenderTarget
from render.volume_texture import DecodedVolume, decoded_texels
from renderers.renderer import Renderer
from units.si import Angle, Length, METER, RADIAN
from max.gpu import global_idx
from std.math import ceildiv, cos, floor, inf, log2, sin, sqrt
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
# A transmissive surface's volume, per triangle, from the first corner's
# lanes: how much it transmits, how deep it is along each world axis, the
# color white light becomes inside it and how far that takes, how far its
# channels bend apart, and its index of refraction. See
# `render.transmission`.
comptime LANE_TRANSMISSION = 44
comptime LANE_THICKNESS_X = 45
comptime LANE_THICKNESS_Y = 46
comptime LANE_THICKNESS_Z = 47
comptime LANE_ATTENUATION_R = 48
comptime LANE_ATTENUATION_G = 49
comptime LANE_ATTENUATION_B = 50
comptime LANE_ATTENUATION_DISTANCE = 51
comptime LANE_DISPERSION = 52
comptime LANE_IOR = 53
# Where a `DISTANCE` triangle measures from, in world space, and the
# distances that map to zero and to one. Per triangle, from the first
# corner's lane, and floats like the shininess.
comptime LANE_REFERENCE_X = 54
comptime LANE_REFERENCE_Y = 55
comptime LANE_REFERENCE_Z = 56
comptime LANE_NEAR_DISTANCE = 57
comptime LANE_FAR_DISTANCE = 58
# A physical triangle's sheen, film and stretch, per triangle from the
# first corner's lanes: the sheen color, linear and times the sheen, and
# the sheen roughness; how much film, its index and the range of its
# thickness in nanometers; the anisotropy vector. See `LayerFactors`.
comptime LANE_SHEEN_R = 59
comptime LANE_SHEEN_G = 60
comptime LANE_SHEEN_B = 61
comptime LANE_SHEEN_ROUGHNESS = 62
comptime LANE_IRIDESCENCE = 63
comptime LANE_IRIDESCENCE_IOR = 64
comptime LANE_THICKNESS_MINIMUM = 65
comptime LANE_THICKNESS_MAXIMUM = 66
comptime LANE_ANISOTROPY_X = 67
comptime LANE_ANISOTROPY_Y = 68
# A physical triangle's specular color, linear, which a fragment reads only
# under a specular map, and what its coat's normal map's x and y are
# scaled by. Per triangle, from the first corner. See `LayerFactors`.
comptime LANE_SPECULAR_COLOR_R = 69
comptime LANE_SPECULAR_COLOR_G = 70
comptime LANE_SPECULAR_COLOR_B = 71
comptime LANE_CLEARCOAT_NORMAL_SCALE_X = 72
comptime LANE_CLEARCOAT_NORMAL_SCALE_Y = 73
# A triangle's `TextureFrames`: the nine numbers of the matrix that turns
# an environment lookup, the refraction ratio, and the nine of the mesh's
# normal matrix an object-space normal map is turned by, each in
# `Basis3`'s order. Its normal map type rides in the state table.
comptime LANE_ENV_ROTATION = LANE_CLEARCOAT_NORMAL_SCALE_Y + 1
comptime LANE_REFRACTION_RATIO = LANE_ENV_ROTATION + 9
comptime LANE_OBJECT_NORMAL = LANE_REFRACTION_RATIO + 1
comptime FLOATS_PER_VERTEX = LANE_OBJECT_NORMAL + 9
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
# Which texture's red multiplies a triangle's transmission, and which
# texture's green multiplies its thickness, each `NO_TEXTURE` for none.
comptime STATE_TRANSMISSION_MAP = 19
comptime STATE_THICKNESS_MAP = 20
# How a `DEPTH` triangle packs its depth: a `DepthPacking` value.
comptime STATE_DEPTH_PACKING = 21
# Whether the scene's fog veils the triangle: one or zero.
comptime STATE_FOG = 22
# Which textures a physical triangle's sheen color, sheen roughness, film,
# film thickness and stretch read, each `NO_TEXTURE` for none.
comptime STATE_SHEEN_COLOR_MAP = 23
comptime STATE_SHEEN_ROUGHNESS_MAP = 24
comptime STATE_IRIDESCENCE_MAP = 25
comptime STATE_FILM_THICKNESS_MAP = 26
comptime STATE_ANISOTROPY_MAP = 27
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
# Whether the scene's fog veils the segment: one or zero.
comptime LINE_STATE_FOG = 4
comptime STATE_PER_LINE = LINE_STATE_FOG + 1
# How a point's metadata is laid out in its state buffer: its texture, its
# blend policy and its alpha map. A point is unlit, so it has no kind to
# carry, no emissive map, no ramp and no matcap.
comptime POINT_STATE_TEXTURE = 0
comptime POINT_STATE_BLEND = 1
comptime POINT_STATE_ALPHA_MAP = 2
# The point's depth, color and stencil state, packed as a triangle's is.
comptime POINT_STATE_OPS = 3
comptime POINT_STATE_STENCIL = 4
# Whether the scene's fog veils the point: one or zero.
comptime POINT_STATE_FOG = 5
comptime STATE_PER_POINT = POINT_STATE_FOG + 1
# How a `Draw` crosses to the device: its kind, its first primitive and its
# count, as three integers.
comptime INTS_PER_DRAW = 3
# Where a node material's program starts in the fog buffer, or -1 for
# none; see `program_starts`.
comptime STATE_NODES = STATE_ANISOTROPY_MAP + 1
# Which textures a physical triangle's specular intensity (the alpha),
# specular color, clear coat (the red), coat roughness (the green) and coat
# normals read, each `NO_TEXTURE` for none.
comptime STATE_SPECULAR_INTENSITY_MAP = STATE_NODES + 1
comptime STATE_SPECULAR_COLOR_MAP = STATE_NODES + 2
comptime STATE_CLEARCOAT_MAP = STATE_NODES + 3
comptime STATE_CLEARCOAT_ROUGHNESS_MAP = STATE_NODES + 4
comptime STATE_CLEARCOAT_NORMAL_MAP = STATE_NODES + 5
# The triangle's normal map type's value; see `TextureFrames`.
comptime STATE_NORMAL_MAP_TYPE = STATE_CLEARCOAT_NORMAL_MAP + 1
comptime STATE_PER_TRIANGLE = STATE_NORMAL_MAP_TYPE + 1
# How the transmission target rides in the backdrop buffer, after the
# backdrop's own pixels: a header of floats, then the chain's floats, each
# four little-endian bytes as a float texture's texels are. The kernel has
# no argument left to spare -- Metal binds at most thirty-one -- so the
# opaque scene shares the buffer that already holds what is behind the
# frame. The header is the world-to-target matrix, sixteen floats, then
# the width, the height and how many levels the chain holds.
comptime TRANSMISSION_WIDTH = VIEW_FLOATS
comptime TRANSMISSION_HEIGHT = VIEW_FLOATS + 1
comptime TRANSMISSION_LEVELS = VIEW_FLOATS + 2
comptime TRANSMISSION_HEADER = VIEW_FLOATS + 3

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
# The camera's back axis in world space, `Lighting.back`: with its up
# axis, the view rotation a normal attachment is written in.
comptime LIGHTS_BACK = LIGHTS_PROBE + SH_COUNT * 3
comptime LIGHTS_FIRST = LIGHTS_BACK + 3
# How the depth buffer is laid out: one float of depth a pixel, then the
# attachments a `RenderTarget` holds, each a plane of its own, so the
# kernel leaves a whole target behind with no argument more. Metal binds
# at most thirty-one arguments and the kernel has thirty-one.
# `GpuRenderer.read_back_target` reads them.
#
# The premultiplied linear color, four floats a pixel, before any curve.
comptime PLANE_COLOR = 1
# The view-space normal of the nearest opaque surface, three floats a
# pixel, zero where none was written.
comptime PLANE_NORMAL = PLANE_COLOR + 4
# One where the pixel holds data rather than light, zero where light.
comptime PLANE_DATA = PLANE_NORMAL + 3
# How many floats a pixel takes across every plane.
comptime PLANE_FLOATS = PLANE_DATA + 1
# How many floats each kind of light takes in the buffer. A directional
# light's seventh, a point light's ninth and a spot light's fourteenth is
# where its shadow map begins in the same buffer, or -1 for none. A
# directional light's last five are its `ShadowCascade`: its start, its
# end, its span in meters, zero for no cascade, and whether it is the
# last and whether it fades, as one or zero. The maps
# ride after the lights, each `SHADOW_HEADER` floats and then its depths,
# rather than in a buffer of their own, because Metal binds at most
# thirty-one arguments to a kernel and this one has thirty-one. A spot
# light's fifteenth is where its map's `SPOT_MAP_FLOATS` begin, after the
# shadow maps, or -1 for none.
comptime DIRECTIONAL_FLOATS = 12
# Where a directional light's cascade begins in its record.
comptime CASCADE_AT = 7
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
# goes into one buffer end to end and this says where each one begins. The
# last seven columns are where the texture is sampled as a map, its
# `UvPlacement`: six floats of the matrix, bit for bit, then the channel.
# A texture's transform is its own, as in three.js, so a row per texture
# holds every map's exactly, and a triangle carries no more than its ids.
# The first ten columns are where the texels start, the size, `wrap_s`,
# `mag_filter`, the color space, the level count, the alpha mode, the
# anisotropy and the texel type. The next four are `wrap_t`, `min_filter`,
# `flip_y` as one or zero, and the mapping.
comptime TABLE_WRAP_T = 10
comptime TABLE_MIN_FILTER = 11
comptime TABLE_FLIP_Y = 12
comptime TABLE_MAPPING = 13
comptime TABLE_PLACEMENT = 14
comptime TABLE_COLUMNS = TABLE_PLACEMENT + 7
# How many table rows a cube texture takes: its six faces, then its PMREM
# image, or one white byte texel for a cube that has none, then its
# panorama, or one white byte texel for a cube of six images. The kernel
# tells a PMREM from none by the texel type, since a PMREM always holds
# floats. The panorama's row carries the cube's own mapping, so the kernel
# reads there whether the cube is a panorama and whether it refracts.
comptime CUBE_ROWS = FACE_COUNT + 2
comptime CUBE_PANORAMA = FACE_COUNT + 1


def flatten_textures(
    textures: TextureStore,
    cubes: CubeTextureStore = CubeTextureStore(),
) raises -> Tuple[List[UInt8], List[Int32]]:
    """Return every texture's bytes end to end, and the table describing them.

    The flat textures first, one row each in id order, then every cube
    texture's six faces, its PMREM image and its panorama in id order, one
    row each, `CUBE_ROWS` in all: cube `c` begins at row
    `textures.count() + c * CUBE_ROWS`, which is what `triangle_state`
    writes for a triangle that reflects it. A cube with no PMREM, or no
    panorama, has the blank texture there, which crosses as one white byte
    texel. The panorama's row holds the cube's mapping.

    Args:
        textures: The store to upload.
        cubes: The cube textures to upload after it.

    Returns:
        The concatenated texels, and `TABLE_COLUMNS` entries per texture:
        byte offset, width, height, `wrap_s`, `mag_filter`, color space,
        how many mip levels follow, the alpha mode, the anisotropy, the
        texel type, `wrap_t`, `min_filter`, `flip_y` as one or zero, the
        mapping, then from `TABLE_PLACEMENT` the six numbers of its
        `Texture.placement` as their bits and its channel. A float
        texture's numbers cross as four little-endian bytes each, so every
        texture shares one buffer.

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
        _flatten_one(six.panorama, texels, table, six.mapping)
    # Never empty: a zero-length device buffer is not worth the special case,
    # and a vertex naming NO_TEXTURE never reads either of these.
    if len(texels) == 0:
        texels.append(0)
    if len(table) == 0:
        for _ in range(TABLE_COLUMNS):
            table.append(0)
    return (texels^, table^)


def _flatten_one(
    image: Texture,
    mut texels: List[UInt8],
    mut table: List[Int32],
    mapping: Optional[Mapping] = None,
) raises:
    """Append one texture's bytes and its row of the table, with
    `mapping` in place of the texture's own when one is given: a cube's
    panorama row carries the cube's.

    Raises:
        Error: If the texture's wrap, filter, color space or alpha mode is
            none of the named values.
    """
    image.validate()
    _flatten_row(image, texels, table)
    table.append(Int32(image.wrap_t.value))
    table.append(Int32(image.min_filter.value))
    table.append(Int32(1 if image.flip_y else 0))
    table.append(Int32(mapping.or_else(image.mapping).value))
    # Where it is sampled as a map, after the rest of the row: a blank
    # texture's is the identity, and a cube face's is never read.
    var placed = image.placement()
    table.append(bitcast[DType.int32](placed.xx))
    table.append(bitcast[DType.int32](placed.xy))
    table.append(bitcast[DType.int32](placed.x0))
    table.append(bitcast[DType.int32](placed.yx))
    table.append(bitcast[DType.int32](placed.yy))
    table.append(bitcast[DType.int32](placed.y0))
    table.append(Int32(placed.channel.value))


def _flatten_row(
    image: Texture, mut texels: List[UInt8], mut table: List[Int32]
):
    """Append one texture's bytes and the first `TABLE_WRAP_T` entries
    of its row."""
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
        table.append(Int32(image.wrap_s.value))
        table.append(Int32(image.mag_filter.value))
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
    table.append(Int32(image.wrap_s.value))
    table.append(Int32(image.mag_filter.value))
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
        flat.append(corner.transmission)
        flat.append(corner.thickness.x)
        flat.append(corner.thickness.y)
        flat.append(corner.thickness.z)
        flat.append(corner.attenuation_color.r)
        flat.append(corner.attenuation_color.g)
        flat.append(corner.attenuation_color.b)
        flat.append(corner.attenuation_distance)
        flat.append(corner.dispersion)
        flat.append(corner.ior)
        flat.append(corner.reference.x)
        flat.append(corner.reference.y)
        flat.append(corner.reference.z)
        flat.append(corner.near_distance)
        flat.append(corner.far_distance)
        flat.append(corner.layers.sheen_color.x)
        flat.append(corner.layers.sheen_color.y)
        flat.append(corner.layers.sheen_color.z)
        flat.append(corner.layers.sheen_roughness)
        flat.append(corner.layers.iridescence)
        flat.append(corner.layers.iridescence_ior)
        flat.append(corner.layers.thickness_minimum)
        flat.append(corner.layers.thickness_maximum)
        flat.append(corner.layers.anisotropy.x)
        flat.append(corner.layers.anisotropy.y)
        flat.append(corner.layers.specular_color.x)
        flat.append(corner.layers.specular_color.y)
        flat.append(corner.layers.specular_color.z)
        flat.append(corner.layers.clearcoat_normal_scale.x)
        flat.append(corner.layers.clearcoat_normal_scale.y)
        _append_basis(flat, corner.frames.env_rotation)
        flat.append(corner.frames.refraction_ratio)
        _append_basis(flat, corner.frames.object_normal)
    return flat^


def _append_basis(mut flat: List[Float32], basis: Basis3):
    """Append a 3x3 matrix's nine numbers in `Basis3`'s order."""
    flat.append(basis.e0)
    flat.append(basis.e1)
    flat.append(basis.e2)
    flat.append(basis.e3)
    flat.append(basis.e4)
    flat.append(basis.e5)
    flat.append(basis.e6)
    flat.append(basis.e7)
    flat.append(basis.e8)


def _basis_at(corners: MutPointer[Float32, MutAnyOrigin], at: Int) -> Basis3:
    """Return the 3x3 matrix whose nine numbers start at `at` in the
    vertex buffer, as `_append_basis` wrote them."""
    return Basis3(
        corners[unsafe_offset=at],
        corners[unsafe_offset=at + 1],
        corners[unsafe_offset=at + 2],
        corners[unsafe_offset=at + 3],
        corners[unsafe_offset=at + 4],
        corners[unsafe_offset=at + 5],
        corners[unsafe_offset=at + 6],
        corners[unsafe_offset=at + 7],
        corners[unsafe_offset=at + 8],
    )


def _append_float(mut bytes: List[UInt8], value: Float32):
    """Append one float as four little-endian bytes, what `_float_at`
    reads back on the device."""
    var bits = bitcast[DType.uint32](value)
    bytes.append(UInt8(bits & 0xFF))
    bytes.append(UInt8((bits >> 8) & 0xFF))
    bytes.append(UInt8((bits >> 16) & 0xFF))
    bytes.append(UInt8(bits >> 24))


def flatten_transmission(target: TransmissionTarget) -> List[UInt8]:
    """Return a transmission target as the bytes that follow the backdrop.

    Args:
        target: The opaque scene, built.

    Returns:
        `TRANSMISSION_HEADER` floats -- the matrix, the width, the height
        and the level count -- then the chain's floats, largest level
        first, each four little-endian bytes.
    """
    var bytes = List[UInt8]()
    for index in range(VIEW_FLOATS):  # pragma: no branch
        _append_float(bytes, target.view[index])
    _append_float(bytes, Float32(target.image.width))
    _append_float(bytes, Float32(target.image.height))
    _append_float(bytes, Float32(target.image.levels))
    for index in range(len(target.image.data)):
        _append_float(bytes, target.image.data[index])
    return bytes^


def flatten_lights(lighting: Lighting) -> List[Float32]:
    """Return a scene's lights as the flat float buffer the kernel reads.

    Three floats of camera position, three of the one direction toward it
    under a parallel projection, three of the camera's own up axis, then
    three of ambient, one of `Lighting.scale`, one of how many rect area
    lights there are, 27 of the light probes' coefficients, three of the
    camera's back axis, then twelve per
    directional light -- a unit
    direction, the light it carries, its shadow and its cascade -- then
    nine per point light: where
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
    its `ShadowMapType`, its intensity and then its depths, row-major from the top, or
    under `VSM_SHADOW_MAP` its means and then its spreads; see
    `lights.shadow.ShadowMap`. A point light's cube holds its bulb's
    position, its near plane and its far plane where the frame would be,
    and six faces of depths. Each spot light carries a fifteenth float:
    where its map begins, or `NO_SHADOW`. The maps follow the shadow maps,
    each the texture's slot in the texture table, the normal bias and the
    sixteen-float frame; see `lights.shadow.SpotLightMap`.

    Returns:
        `LIGHTS_FIRST + 12 * count + 9 * point_count + 9 * hemisphere_count
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
    flat.append(lighting.back.x)
    flat.append(lighting.back.y)
    flat.append(lighting.back.z)
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
        ref band = lighting.cascades[index]
        flat.append(band.start)
        flat.append(band.end)
        flat.append(band.span.to(METER))
        flat.append(Float32(1) if band.last else Float32(0))
        flat.append(Float32(1) if band.fade else Float32(0))
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
        flat.append(map.intensity)
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
    parity tests, weakened by the map's intensity by `shadow_strength`.

    `block` is where the map begins in the light buffer, as
    `flatten_lights` laid it out.
    """
    return shadow_strength(
        _unweakened_shadow_at(lights, block, position, normal),
        lights[unsafe_offset=block + SHADOW_INTENSITY_AT],
    )


def _unweakened_shadow_at(
    lights: MutPointer[Float32, MutAnyOrigin],
    block: Int,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return what one light's shadow map lets through at full intensity."""
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
    if not inside_shadow_map(place, bias):
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
    functions in the same order, weakened by the cube's intensity.

    `block` is where the cube begins in the light buffer, as
    `flatten_lights` laid it out.
    """
    return shadow_strength(
        _unweakened_cube_at(lights, block, position, normal),
        lights[unsafe_offset=block + SHADOW_INTENSITY_AT],
    )


def _unweakened_cube_at(
    lights: MutPointer[Float32, MutAnyOrigin],
    block: Int,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return what a point light's cube lets through at full intensity."""
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
    for tap in range(POINT_SHADOW_TAPS):
        var texel = cube_texel(point_shadow_tap(way, tap, spread), size)
        total += cube_tap(
            lights[unsafe_offset=block + SHADOW_HEADER + texel], depth
        )
    return total / Float32(POINT_SHADOW_TAPS)


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


def _direction_through(
    lights: MutPointer[Float32, MutAnyOrigin],
    at: Int,
    receives: Bool,
    position: Vector3,
    normal: Vector3,
) -> Float32:
    """Return how much of one directional light reaches a surface: the
    device counterpart of `Lighting.direction_through`, reading the
    light's shadow and cascade from its record at `at`."""
    var span = lights[unsafe_offset=at + CASCADE_AT + 2]
    if span == 0:
        return _through(lights, at + 6, receives, position, normal)
    var reach = cascade_reach(
        view_depth(
            position,
            Vector3(
                lights[unsafe_offset=LIGHTS_EYE],
                lights[unsafe_offset=LIGHTS_EYE + 1],
                lights[unsafe_offset=LIGHTS_EYE + 2],
            ),
            Vector3(
                lights[unsafe_offset=LIGHTS_BACK],
                lights[unsafe_offset=LIGHTS_BACK + 1],
                lights[unsafe_offset=LIGHTS_BACK + 2],
            ),
        )
        / span,
        lights[unsafe_offset=at + CASCADE_AT],
        lights[unsafe_offset=at + CASCADE_AT + 1],
        lights[unsafe_offset=at + CASCADE_AT + 3] != 0,
        lights[unsafe_offset=at + CASCADE_AT + 4] != 0,
    )
    if reach[0] == 0:
        return 0
    return reach[0] * shadow_strength(
        _through(lights, at + 6, receives, position, normal), reach[1]
    )


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


def program_starts(programs: NodeProgramStore) -> List[Int]:
    """Return where each node program starts in the fog buffer.

    The programs ride after the fog's `FOG_FLOATS`, end to end, rather than
    in a buffer of their own: the kernel has no argument left, and the fog
    buffer already holds floats. A program's offsets are its own, so the
    kernel reads one from wherever it starts.

    Args:
        programs: The store to lay out.

    Returns:
        One offset per program, in id order.
    """
    var starts = List[Int]()
    var at = FOG_FLOATS
    for index in range(programs.count()):
        starts.append(at)
        at += len(programs.programs[index].code)
    return starts^


def flatten_programs(programs: NodeProgramStore) -> List[Float32]:
    """Return every node program's floats end to end, as they follow the
    fog in the fog buffer.

    Args:
        programs: The store to flatten.

    Returns:
        The floats, in id order.
    """
    var flat = List[Float32]()
    for index in range(programs.count()):
        flat.extend(programs.programs[index].code.copy())
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
        lambert *= _direction_through(
            lights, at, receives, Vector3(px, py, pz), Vector3(nx, ny, nz)
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
        tone *= _direction_through(
            lights, at, receives, Vector3(px, py, pz), Vector3(nx, ny, nz)
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
        lambert *= _direction_through(
            lights, at, receives, Vector3(px, py, pz), normal
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


def _normal_at(
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
    """Return the perspective-correct unit normal at a sample point,
    before any map: the device counterpart of
    `render.rasterizer._normal_at`. A zero normal stays zero."""
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
    var facing = Vector3(
        corners[unsafe_offset=base + LANE_NX] * share_a
        + corners[unsafe_offset=b_base + LANE_NX] * share_b
        + corners[unsafe_offset=c_base + LANE_NX] * share_c,
        corners[unsafe_offset=base + LANE_NY] * share_a
        + corners[unsafe_offset=b_base + LANE_NY] * share_b
        + corners[unsafe_offset=c_base + LANE_NY] * share_c,
        corners[unsafe_offset=base + LANE_NZ] * share_a
        + corners[unsafe_offset=b_base + LANE_NZ] * share_b
        + corners[unsafe_offset=c_base + LANE_NZ] * share_c,
    )
    if facing.length() != 0:
        facing.normalize()
    return facing


def _sample_cube_level(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    table: MutPointer[Int32, MutAnyOrigin],
    first: Int,
    direction: Vector3,
    level: Float32,
) -> FloatColor:
    """Sample a cube texture in a direction, `level` down its chain: the
    device counterpart of `CubeTexture.sample_level`. A cube made from a
    panorama reads down the panorama's chain at `equirect_uv`."""
    var panorama = _describe(table, first + CUBE_PANORAMA)
    if panorama.mapping.is_equirectangular():
        var at = equirect_uv(direction)
        return _sample_level(texels, ramp, panorama, at.x, at.y, level)
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
    var panorama = _describe(table, first + CUBE_PANORAMA)
    if panorama.mapping.is_equirectangular():
        levels = panorama.levels
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
    layers: PhysicalLayers = PhysicalLayers(),
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
        var through = _direction_through(lights, at, receives, position, normal)
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
            layers,
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
            layers,
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
            layers,
        )
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    var scaled = Reflected(
        sum.diffuse * scale,
        sum.specular * scale,
        sum.clearcoat * scale,
        sum.sheen * scale,
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
        scaled = Reflected(diffuse, specular, scaled.clearcoat, scaled.sheen)
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
    var wrap_s: Wrap
    var mag_filter: Filter
    var space: ColorSpace
    var levels: Int
    var alpha: Alpha
    var anisotropy: Int
    var texel_type: TexelType
    var wrap_t: Wrap
    var min_filter: Filter
    var flip_y: Bool
    var mapping: Mapping


def _placement(
    table: MutPointer[Int32, MutAnyOrigin], slot: Int
) -> UvPlacement:
    """Return where texture `slot` is sampled as a map, from its row of
    the table: the device counterpart of `Texture.placement`, the same
    seven numbers `flatten_textures` wrote."""
    var entry = slot * TABLE_COLUMNS + TABLE_PLACEMENT
    return UvPlacement(
        bitcast[DType.float32](table[unsafe_offset=entry]),
        bitcast[DType.float32](table[unsafe_offset=entry + 1]),
        bitcast[DType.float32](table[unsafe_offset=entry + 2]),
        bitcast[DType.float32](table[unsafe_offset=entry + 3]),
        bitcast[DType.float32](table[unsafe_offset=entry + 4]),
        bitcast[DType.float32](table[unsafe_offset=entry + 5]),
        UvChannel(Int(table[unsafe_offset=entry + 6])),
    )


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
        Wrap(Int(table[unsafe_offset=entry + TABLE_WRAP_T])),
        Filter(Int(table[unsafe_offset=entry + TABLE_MIN_FILTER])),
        table[unsafe_offset=entry + TABLE_FLIP_Y] != 0,
        Mapping(Int(table[unsafe_offset=entry + TABLE_MAPPING])),
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
            wrap_index(y, tall, image.wrap_t) * wide
            + wrap_index(x, wide, image.wrap_s)
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
        stencil state, then one or zero for whether the fog veils it, per
        segment, from its first end.
    """
    var state = List[Int32]()
    for segment in range(len(corners) // 2):
        state.append(Int32(corners[segment * 2].blend.value))
        state.append(Int32(line_width))
        state.append(Int32(corners[segment * 2].state.ops_word()))
        state.append(Int32(corners[segment * 2].state.stencil_word()))
        state.append(Int32(1 if corners[segment * 2].fog else 0))
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
        color and stencil state, then one or zero for whether the fog
        veils it, per point.
    """
    var state = List[Int32]()
    for point in range(len(points)):
        state.append(Int32(points[point].texture.value))
        state.append(Int32(points[point].blend.value))
        state.append(Int32(points[point].alpha_map.value))
        state.append(Int32(points[point].state.ops_word()))
        state.append(Int32(points[point].state.stencil_word()))
        state.append(Int32(1 if points[point].fog else 0))
    return state^


def triangle_state(
    corners: List[RasterVertex],
    cube_base: Int = 0,
    starts: List[Int] = List[Int](),
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
        starts: Where each node program starts in the fog buffer, as
            `program_starts` lays them out. A triangle naming a program
            past it, as `GpuRenderer.draw` refuses, gets -1.

    Returns:
        Texture id, blend policy, the material kind's value, the emissive
        map id, the alpha map id, the gradient map id, the matcap id, the
        row of the env map's first face or -1 for none, then the combine's
        value, then the roughness, metalness, normal and bump map ids, then
        one or zero for whether the shadows fall on it, then the packed
        depth, color and stencil state, then the ao and light map ids,
        then the specular map id, then the transmission and thickness map
        ids, then the depth packing's value and one or zero for whether
        the fog veils it, then the sheen color, sheen roughness,
        iridescence, film thickness and anisotropy map ids, then where its
        node program starts or -1, then the specular intensity, specular
        color, clearcoat, clearcoat roughness and clearcoat normal map
        ids, then the normal map type's value, per triangle, from its
        first corner.
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
        state.append(Int32(corners[triangle * 3].transmission_map.value))
        state.append(Int32(corners[triangle * 3].thickness_map.value))
        state.append(Int32(corners[triangle * 3].depth_packing.value))
        state.append(Int32(1 if corners[triangle * 3].fog else 0))
        ref layers = corners[triangle * 3].layers
        state.append(Int32(layers.sheen_color_map.value))
        state.append(Int32(layers.sheen_roughness_map.value))
        state.append(Int32(layers.iridescence_map.value))
        state.append(Int32(layers.thickness_map.value))
        state.append(Int32(layers.anisotropy_map.value))
        var program = corners[triangle * 3].nodes.value
        state.append(
            Int32(starts[program]) if program >= 0
            and program < len(starts) else Int32(-1)
        )
        state.append(Int32(layers.specular_intensity_map.value))
        state.append(Int32(layers.specular_color_map.value))
        state.append(Int32(layers.clearcoat_map.value))
        state.append(Int32(layers.clearcoat_roughness_map.value))
        state.append(Int32(layers.clearcoat_normal_map.value))
        state.append(Int32(corners[triangle * 3].frames.normal_map_type.value))
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
    """Sample one mip level, the device counterpart of `Texture.sample_at`:
    through `level_filter`, the host's own choice."""
    return _sample_filtered(
        texels,
        ramp,
        image,
        u,
        v,
        level,
        level_filter(level, image.mag_filter, image.min_filter),
    )


def _sample_filtered(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    image: _Descriptor,
    u: Float32,
    v: Float32,
    level: Int,
    filter: Filter,
) -> FloatColor:
    """Sample one mip level through one filter, the device counterpart of
    `Texture._sample_at`."""
    var wide = _extent(image.width, level)
    var tall = _extent(image.height, level)
    var from_top = row_coordinate(v, image.flip_y)
    if filter == NEAREST:
        return _fetch(
            texels,
            ramp,
            image,
            Int(floor(u * Float32(wide))),
            Int(floor(from_top * Float32(tall))),
            level,
        )
    # Texel centers sit at half-integers; see Texture.sample.
    var across = u * Float32(wide) - 0.5
    var down = from_top * Float32(tall) - 0.5
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
    """Read at a fractional level through the texture's two filters,
    matching `Texture.sample_level`: `plan_levels`, the host's own plan."""
    var plan = plan_levels(
        level, image.levels, image.mag_filter, image.min_filter
    )
    var near = _sample_filtered(
        texels, ramp, image, u, v, plan.lower, plan.filter
    )
    if plan.upper == plan.lower:
        return near
    var far = _sample_filtered(
        texels, ramp, image, u, v, plan.upper, plan.filter
    )
    return mix_color(near, far, plan.blend)


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
    host reads it. A cube made from a panorama reads the panorama, its row
    after the PMREM's, at `equirect_uv` instead.
    """
    var panorama = _describe(table, first + CUBE_PANORAMA)
    if panorama.mapping.is_equirectangular():
        var at = equirect_uv(direction)
        return _sample_at(texels, ramp, panorama, at.x, at.y, 0)
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
    placement: UvPlacement = UvPlacement(),
) -> FloatColor:
    """Sample texture `slot` at (u, v) for the pixel at (px, py).

    Every texture lives in one buffer end to end, so the table says where
    this one starts and how to read it. With one level there is no chain to
    choose from and so no footprint to measure; the CPU takes the same
    shortcut. Otherwise the level comes from where the coordinates land one
    pixel over and one down, evaluated from the triangle's own uv function
    rather than read from a neighboring thread -- see
    `render.rasterizer.mip_level`. Shared by every map, as `_sample_map` is
    on the host, so all are filtered alike on both sides. (u, v) is
    already placed: `placement` says which pair the footprint is measured
    on, `LANE_U` or `LANE_U1` by its channel, and how that pair is moved.
    The identity on the first pair, the default, is what a node graph
    samples at.
    """
    var image = _describe(table, slot)
    if image.levels == 1 and image.anisotropy == 1:
        return _sample_at(texels, ramp, image, u, v, 0)
    var lane = LANE_U
    if placement.channel == UV_CHANNEL_1:
        lane = LANE_U1
    # The center from the same function as its neighbors, as
    # `render.rasterizer._sample_map` takes it, and for the same reason.
    var here = placement.moved(
        _uv_at(
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
    )
    var along_x = placement.moved(
        _uv_at(
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
    )
    var along_y = placement.moved(
        _uv_at(
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


def _placed_steps(
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
    placement: UvPlacement,
    here: Vector2,
) -> Tuple[Vector2, Vector2]:
    """Return how one map's placed coordinates change one pixel right and
    one pixel up, from `here`: the device counterpart of
    `render.rasterizer._placed_steps`."""
    var lane = LANE_U
    if placement.channel == UV_CHANNEL_1:
        lane = LANE_U1
    var to_right = placement.moved(
        _uv_at(
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
    )
    var to_up = placement.moved(
        _uv_at(
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
            py - SUBPIXEL,
            lane,
        )
    )
    return (
        Vector2(to_right.x - here.x, to_right.y - here.y),
        Vector2(to_up.x - here.x, to_up.y - here.y),
    )


def _sample_placed_slot(
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
    uv: Vector2,
    uv1: Vector2,
) -> FloatColor:
    """Sample map `slot` where its own placement puts the pixel: the
    device counterpart of `render.rasterizer._sample_placed`. `uv` and
    `uv1` are the pixel's two raw pairs; the table says which one the map
    reads and how it is moved."""
    var placement = _placement(table, slot)
    var at = placement.place(uv, uv1)
    return _sample_slot(
        texels,
        ramp,
        table,
        slot,
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
        at.x,
        at.y,
        placement,
    )


struct _DeviceSource[origin: Origin[mut=True]](TransmissionSource):
    """The kernel's `TransmissionSource`: the transmission target's chain
    in the backdrop buffer, read by `_sample_at` as the host's texture is
    read by its own."""

    var texels: MutPointer[UInt8, Self.origin]
    var ramp: MutPointer[Float32, Self.origin]
    var image: _Descriptor

    def __init__(
        out self,
        texels: MutPointer[UInt8, Self.origin],
        ramp: MutPointer[Float32, Self.origin],
        image: _Descriptor,
    ):
        """Read the chain `image` describes out of `texels`."""
        self.texels = texels
        self.ramp = ramp
        self.image = image

    def level_count(self) -> Int:
        """Return how many images the chain holds."""
        return self.image.levels

    def level_size(self, level: Int) -> Vector2:
        """Return the size of `level`, as `_extent` gives it."""
        return Vector2(
            Float32(_extent(self.image.width, level)),
            Float32(_extent(self.image.height, level)),
        )

    def fetch_level(self, u: Float32, v: Float32, level: Int) -> FloatColor:
        """Return the bilinear sample on `level`, as `Texture._sample_at`
        takes it."""
        return _sample_at(
            self.texels.unsafe_origin_cast[MutAnyOrigin](),
            self.ramp.unsafe_origin_cast[MutAnyOrigin](),
            self.image,
            u,
            v,
            level,
        )


struct _DeviceNodes[origin: Origin[mut=True]](NodeSource):
    """The kernel's `NodeSource`: a program in the fog buffer, and one
    triangle's own footprint for the textures it reads, as `_sample_slot`
    reads the material's map for the pixel."""

    var fog: MutPointer[Float32, Self.origin]
    var start: Int
    var texels: MutPointer[UInt8, Self.origin]
    var ramp: MutPointer[Float32, Self.origin]
    var table: MutPointer[Int32, Self.origin]
    var corners: MutPointer[Float32, Self.origin]
    var base: Int
    var ax: Int
    var ay: Int
    var bx: Int
    var by: Int
    var cx: Int
    var cy: Int
    var span_inv: Float32
    var swapped: Bool
    var px: Int
    var py: Int

    def __init__(
        out self,
        fog: MutPointer[Float32, Self.origin],
        start: Int,
        texels: MutPointer[UInt8, Self.origin],
        ramp: MutPointer[Float32, Self.origin],
        table: MutPointer[Int32, Self.origin],
        corners: MutPointer[Float32, Self.origin],
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
    ):
        """Read the program that starts `start` floats into `fog`."""
        self.fog = fog
        self.start = start
        self.texels = texels
        self.ramp = ramp
        self.table = table
        self.corners = corners
        self.base = base
        self.ax = ax
        self.ay = ay
        self.bx = bx
        self.by = by
        self.cx = cx
        self.cy = cy
        self.span_inv = span_inv
        self.swapped = swapped
        self.px = px
        self.py = py

    def word(self, at: Int) -> Float32:
        """Return one float of the program."""
        return self.fog[unsafe_offset=self.start + at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return a texture read at (u, v) for this pixel, as `_sample_slot`
        reads the material's map."""
        return _sample_slot(
            self.texels.unsafe_origin_cast[MutAnyOrigin](),
            self.ramp.unsafe_origin_cast[MutAnyOrigin](),
            self.table.unsafe_origin_cast[MutAnyOrigin](),
            slot,
            self.corners.unsafe_origin_cast[MutAnyOrigin](),
            self.base,
            self.ax,
            self.ay,
            self.bx,
            self.by,
            self.cx,
            self.cy,
            self.span_inv,
            self.swapped,
            self.px,
            self.py,
            u,
            v,
        )

    def shares(self, context: NodeContext) -> SIMD[DType.float32, 4]:
        """Return each corner's perspective-correct weight at this pixel,
        or at the pixel to its right or above it, from the triangle's own
        edge functions, as `_uv_at` reads the pixels either side."""
        var px = self.px + (SUBPIXEL if context == AT_RIGHT else 0)
        var py = self.py - (SUBPIXEL if context == AT_UP else 0)
        var e_ab = edge_at(self.ax, self.ay, self.bx, self.by, px, py)
        var e_bc = edge_at(self.bx, self.by, self.cx, self.cy, px, py)
        var e_ca = edge_at(self.cx, self.cy, self.ax, self.ay, px, py)
        var wa = Float32(e_bc) * self.span_inv
        var wb = Float32(e_ca) * self.span_inv
        var wc = Float32(e_ab) * self.span_inv
        if self.swapped:
            var held = wb
            wb = wc
            wc = held
        return perspective_shares(
            wa,
            wb,
            wc,
            self.corners[unsafe_offset=self.base + LANE_INV_W],
            self.corners[
                unsafe_offset=self.base + FLOATS_PER_VERTEX + LANE_INV_W
            ],
            self.corners[
                unsafe_offset=self.base + 2 * FLOATS_PER_VERTEX + LANE_INV_W
            ],
        )

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return one corner's coordinates, world position, normal and
        color, from its lanes."""
        var at = self.base + (
            0 if context
            == CORNER_A else (
                FLOATS_PER_VERTEX if context
                == CORNER_B else 2 * FLOATS_PER_VERTEX
            )
        )
        return NodeInputs(
            self.corners[unsafe_offset=at + LANE_U],
            self.corners[unsafe_offset=at + LANE_V],
            Vector3(
                self.corners[unsafe_offset=at + LANE_WX],
                self.corners[unsafe_offset=at + LANE_WY],
                self.corners[unsafe_offset=at + LANE_WZ],
            ),
            Vector3(
                self.corners[unsafe_offset=at + LANE_NX],
                self.corners[unsafe_offset=at + LANE_NY],
                self.corners[unsafe_offset=at + LANE_NZ],
            ),
            Vector3(
                self.corners[unsafe_offset=at + LANE_R],
                self.corners[unsafe_offset=at + LANE_G],
                self.corners[unsafe_offset=at + LANE_B],
            ),
            Vector3(0, 0, 0),
            False,
        )


def _transmitted(
    backdrop: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    start: Int,
    normal: Vector3,
    toward_eye: Vector3,
    roughness: Float32,
    surface: Reflected,
    position: Vector3,
    thickness: Vector3,
    dispersion: Float32,
    ior: Float32,
    attenuation_color: Vector3,
    attenuation_distance: Float32,
) -> FloatColor:
    """Return `volume_refraction` read from the transmission target that
    starts `start` bytes into the backdrop buffer: the device counterpart
    of `render.transmission.host_refraction`."""
    var view = SIMD[DType.float32, VIEW_FLOATS](0)
    for index in range(VIEW_FLOATS):
        view[index] = _float_at(backdrop, start + index * 4)
    var image = _Descriptor(
        start + TRANSMISSION_HEADER * 4,
        Int(_float_at(backdrop, start + TRANSMISSION_WIDTH * 4)),
        Int(_float_at(backdrop, start + TRANSMISSION_HEIGHT * 4)),
        CLAMP,
        BILINEAR,
        LINEAR,
        Int(_float_at(backdrop, start + TRANSMISSION_LEVELS * 4)),
        COVERAGE,
        1,
        FLOAT_TYPE,
        CLAMP,
        LINEAR_MIPMAP_LINEAR,
        True,
        UV_MAPPING,
    )
    return volume_refraction(
        _DeviceSource(backdrop, ramp, image),
        view,
        normal,
        toward_eye,
        roughness,
        surface.diffuse,
        surface.specular,
        surface.clearcoat.x,
        position,
        thickness,
        dispersion,
        ior,
        attenuation_color,
        attenuation_distance,
    )


def _behind(
    red: Float32, green: Float32, blue: Float32, alpha: Float32, data: Bool
) -> Rgba:
    """Return the color a pixel holds as premultiplied light, for a blend
    to mix over.

    A light pixel is held premultiplied already. A data pixel is held
    straight, as `RenderTarget.write` holds it, and is premultiplied here,
    as `RenderTarget.light_at` premultiplies it.
    """
    if data:
        return Rgba(red * alpha, green * alpha, blue * alpha, alpha)
    return Rgba(red, green, blue, alpha)


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
    # The view-space normal the pixel keeps for a target's normal
    # attachment: the last opaque triangle's, as `RenderTarget.write`
    # keeps it, and none until one is written. A blend leaves it alone.
    var kept_x = Float32(0)
    var kept_y = Float32(0)
    var kept_z = Float32(0)
    # The camera's up and back axes, the view rotation the normal is
    # turned by, read once rather than per fragment.
    var view_up = Vector3(
        lights[unsafe_offset=LIGHTS_UP],
        lights[unsafe_offset=LIGHTS_UP + 1],
        lights[unsafe_offset=LIGHTS_UP + 2],
    )
    var view_back = Vector3(
        lights[unsafe_offset=LIGHTS_BACK],
        lights[unsafe_offset=LIGHTS_BACK + 1],
        lights[unsafe_offset=LIGHTS_BACK + 2],
    )
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
                if fog_on and (
                    point_maps[
                        unsafe_offset=index * STATE_PER_POINT + POINT_STATE_FOG
                    ]
                    != 0
                ):
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
                    # which shows coordinates. It has no surface, so it
                    # leaves no normal, as `RenderTarget.write` keeps none.
                    data = mode == Int32(SHADE_UV.value)
                    kept_x = 0
                    kept_y = 0
                    kept_z = 0
                elif state.color_write:
                    var out = blend_pixel(
                        _behind(mixed_r, mixed_g, mixed_b, mixed_a, data),
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
                if fog_kind != Int32(NO_FOG.value) and (
                    segment_maps[
                        unsafe_offset=index * STATE_PER_LINE + LINE_STATE_FOG
                    ]
                    != 0
                ):
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
                    # kind but an unlit one. It leaves no normal either.
                    data = False
                    kept_x = 0
                    kept_y = 0
                    kept_z = 0
                elif state.color_write:
                    var out = blend_pixel(
                        _behind(mixed_r, mixed_g, mixed_b, mixed_a, data),
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
            # Whether a node graph replaces parts of the shading, as
            # `rasterize_shaded` decides it, and the program it runs,
            # read out of the fog buffer where it starts.
            var program = Int(
                maps[unsafe_offset=index * STATE_PER_TRIANGLE + STATE_NODES]
            )
            var noded = program >= 0 and mode != Int32(SHADE_UV.value)
            var textured = mode == Int32(SHADE_TEXTURE.value)
            var nodes = _DeviceNodes(
                fog,
                program,
                texels,
                ramp,
                table,
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
            )
            # Whether the graph can throw the fragment away, and its depth
            # in place of the plane's, as `rasterize_shaded` asks both.
            var masked = noded and has_output(nodes, MASK_NODE)
            if noded and has_output(nodes, DEPTH_NODE):
                stored_z = node_depth(
                    run_nodes(nodes, DEPTH_NODE, here_inputs(nodes, textured))[
                        0
                    ],
                    state.depth_mode == REVERSED_DEPTH,
                )
            var held = nearest
            if not solid:
                held = cleared_depth(state.depth_mode)
            var test = test_fragment(state, stored_z, held, stencil)
            if not shades(test, tested or masked):
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
            var measures = kind == Int32(DISTANCE.value)
            var shows_data = (
                shows_normal or kind == Int32(DEPTH.value) or measures
            )
            # The interpolated normal, made a unit vector again here. That
            # renormalization is the difference between per-fragment and
            # per-vertex shading: the average of two unit vectors is shorter than
            # either, so leaving it alone dims the middle of every triangle.
            # Worked out for every triangle, shaded by it or not: a target's
            # normal attachment keeps it, and the host works it out for every
            # triangle when its target has one. Only a surface that is lit, a
            # normal, a matcap, a reflection or a shadow reads it for a color.
            var arriving = Vector3(1, 1, 1)
            var highlight = Vector3(0, 0, 0)
            var nx = (
                corners[unsafe_offset=base + LANE_NX] * share_a
                + corners[unsafe_offset=b_base + LANE_NX] * share_b
                + corners[unsafe_offset=c_base + LANE_NX] * share_c
            )
            var ny = (
                corners[unsafe_offset=base + LANE_NY] * share_a
                + corners[unsafe_offset=b_base + LANE_NY] * share_b
                + corners[unsafe_offset=c_base + LANE_NY] * share_c
            )
            var nz = (
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
                lit or looked_up or reflects or catches or measures or noded
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
            # The raw texture coordinates, both pairs, for the two modes
            # that read them and for a node graph. Each map places them
            # for itself, by its row of the texture table.
            var u = Float32(0)
            var v = Float32(0)
            var uv1 = Vector2(0, 0)
            if mode != Int32(SHADE_LIT.value) or noded:
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
                uv1 = Vector2(
                    corners[unsafe_offset=base + LANE_U1] * share_a
                    + corners[unsafe_offset=b_base + LANE_U1] * share_b
                    + corners[unsafe_offset=c_base + LANE_U1] * share_c,
                    corners[unsafe_offset=base + LANE_V1] * share_a
                    + corners[unsafe_offset=b_base + LANE_V1] * share_b
                    + corners[unsafe_offset=c_base + LANE_V1] * share_c,
                )
            var uv = Vector2(u, v)
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
                # The map's own coordinates, placed, as three.js reads
                # `vNormalMapUv` or `vBumpMapUv`.
                var framed = _placement(
                    table,
                    Int(normal_slot) if normal_slot >= 0 else Int(bump_slot),
                )
                var at = framed.place(uv, uv1)
                var steps = _placed_steps(
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
                    framed,
                    at,
                )
                var uv_along_x = steps[0]
                var uv_along_y = steps[1]
                var facing = Vector3(nx, ny, nz)
                var object_space = maps[
                    unsafe_offset=index * STATE_PER_TRIANGLE
                    + STATE_NORMAL_MAP_TYPE
                ] == Int32(OBJECT_SPACE_NORMAL_MAP.value)
                if normal_slot >= 0:
                    var texel = _sample_slot(
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
                        at.x,
                        at.y,
                        framed,
                    )
                    if object_space:
                        facing = object_space_normal(
                            Vector3(nx, ny, nz),
                            texel,
                            _basis_at(corners, base + LANE_OBJECT_NORMAL),
                        )
                    else:
                        facing = mapped_normal(
                            Vector3(nx, ny, nz),
                            along_x,
                            along_y,
                            uv_along_x,
                            uv_along_y,
                            texel,
                            Vector2(
                                corners[
                                    unsafe_offset=base + LANE_NORMAL_SCALE_X
                                ],
                                corners[
                                    unsafe_offset=base + LANE_NORMAL_SCALE_Y
                                ],
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
                            at.x,
                            at.y,
                            framed,
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
                            at.x + uv_along_x.x,
                            at.y + uv_along_x.y,
                            framed,
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
                            at.x + uv_along_y.x,
                            at.y + uv_along_y.y,
                            framed,
                        ).r
                        - height
                    )
                    facing = bumped_normal(
                        Vector3(nx, ny, nz), along_x, along_y, rise_x, rise_y
                    )
                nx = facing.x
                ny = facing.y
                nz = facing.z
            # The corner color, interpolated here as well as below, for
            # the node graph's vertex color node.
            var tint = Vector3(0, 0, 0)
            if noded:
                tint = Vector3(
                    corners[unsafe_offset=base + LANE_R] * share_a
                    + corners[unsafe_offset=b_base + LANE_R] * share_b
                    + corners[unsafe_offset=c_base + LANE_R] * share_c,
                    corners[unsafe_offset=base + LANE_G] * share_a
                    + corners[unsafe_offset=b_base + LANE_G] * share_b
                    + corners[unsafe_offset=c_base + LANE_G] * share_c,
                    corners[unsafe_offset=base + LANE_B] * share_a
                    + corners[unsafe_offset=b_base + LANE_B] * share_b
                    + corners[unsafe_offset=c_base + LANE_B] * share_c,
                )
            # The node graph's normal offset, after any map and before the
            # lights, by the host's own function; see `rasterize_shaded`.
            if noded and has_output(nodes, NORMAL_NODE):
                var bent = offset_normal(
                    Vector3(nx, ny, nz),
                    run_nodes(
                        nodes,
                        NORMAL_NODE,
                        NodeInputs(
                            u,
                            v,
                            Vector3(wx, wy, wz),
                            Vector3(nx, ny, nz),
                            tint,
                            Vector3(0, 0, 0),
                            textured,
                        ),
                    ),
                )
                nx = bent.x
                ny = bent.y
                nz = bent.z
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

            # The baked maps, each sampled where its own placement puts
            # the pixel, by the host's own functions in the host's own
            # order; see
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
                if ao_slot >= 0:
                    occlusion = ambient_occlusion(
                        _sample_placed_slot(
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
                            uv,
                            uv1,
                        ).r,
                        corners[unsafe_offset=base + LANE_AO_INTENSITY],
                    )
                if light_slot >= 0:
                    var glowed = _sample_placed_slot(
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
                        uv,
                        uv1,
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
            # The node graph's ambient occlusion, as the host replaces the
            # map's with it.
            var occludes = noded and has_output(nodes, AO_NODE)
            if occludes:
                occlusion = run_nodes(
                    nodes,
                    AO_NODE,
                    NodeInputs(
                        u,
                        v,
                        Vector3(wx, wy, wz),
                        Vector3(nx, ny, nz),
                        tint,
                        Vector3(0, 0, 0),
                        textured,
                    ),
                )[0]
            if (
                (mode == Int32(SHADE_TEXTURE.value))
                and (ao_slot >= 0 or light_slot >= 0)
                or occludes
            ) and not physical:
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
                arriving = occluded_light(arriving, indirect, baked, occlusion)
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
                        var sampled = _sample_placed_slot(
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
                            uv,
                            uv1,
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
                        var thinning = _sample_placed_slot(
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
                            uv,
                            uv1,
                        )
                        alpha *= thinning.g
                    if glow_slot != NO_TEXTURE.value:
                        var glowing = _sample_placed_slot(
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
                            uv,
                            uv1,
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
                        rough_factor = _sample_placed_slot(
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
                            uv,
                            uv1,
                        ).g
                    var metal_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_METALNESS_MAP
                        ]
                    )
                    if metal_slot != NO_TEXTURE.value:
                        metal_factor = _sample_placed_slot(
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
                            uv,
                            uv1,
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
                        specular_strength = _sample_placed_slot(
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
                            uv,
                            uv1,
                        ).r
                        highlight = Vector3(
                            highlight.x * specular_strength,
                            highlight.y * specular_strength,
                            highlight.z * specular_strength,
                        )
                    # The layers' maps, exactly as `rasterize_shaded`
                    # reads them: a color, an alpha, a red, a green, and a
                    # whole texel.
                    var tint_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_SHEEN_COLOR_MAP
                        ]
                    )
                    if tint_slot != NO_TEXTURE.value:
                        var tint = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            tint_slot,
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
                            uv,
                            uv1,
                        )
                        sheen_tint = Vector3(tint.r, tint.g, tint.b)
                    var cloth_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_SHEEN_ROUGHNESS_MAP
                        ]
                    )
                    if cloth_slot != NO_TEXTURE.value:
                        sheen_alpha = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            cloth_slot,
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
                            uv,
                            uv1,
                        ).a
                    var film_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_IRIDESCENCE_MAP
                        ]
                    )
                    if film_slot != NO_TEXTURE.value:
                        film_factor = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            film_slot,
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
                            uv,
                            uv1,
                        ).r
                    var thick_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_FILM_THICKNESS_MAP
                        ]
                    )
                    if thick_slot != NO_TEXTURE.value:
                        thickness_texel = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            thick_slot,
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
                            uv,
                            uv1,
                        ).g
                        thickness_mapped = True
                    var turn_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_ANISOTROPY_MAP
                        ]
                    )
                    if turn_slot != NO_TEXTURE.value:
                        var turn = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            turn_slot,
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
                            uv,
                            uv1,
                        )
                        stretch_texel = Vector3(turn.r, turn.g, turn.b)
                    # The specular and coat maps, exactly as
                    # `rasterize_shaded` reads them: a color, an alpha, a
                    # red, a green, and a whole texel.
                    var specular_tint_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_SPECULAR_COLOR_MAP
                        ]
                    )
                    if specular_tint_slot != NO_TEXTURE.value:
                        var tint = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            specular_tint_slot,
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
                            uv,
                            uv1,
                        )
                        specular_texel = Vector3(tint.r, tint.g, tint.b)
                    var specular_alpha_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_SPECULAR_INTENSITY_MAP
                        ]
                    )
                    if specular_alpha_slot != NO_TEXTURE.value:
                        specular_alpha = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            specular_alpha_slot,
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
                            uv,
                            uv1,
                        ).a
                    var coat_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_CLEARCOAT_MAP
                        ]
                    )
                    if coat_slot != NO_TEXTURE.value:
                        coat_factor = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            coat_slot,
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
                            uv,
                            uv1,
                        ).r
                    var coat_rough_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_CLEARCOAT_ROUGHNESS_MAP
                        ]
                    )
                    if coat_rough_slot != NO_TEXTURE.value:
                        coat_rough_factor = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            coat_rough_slot,
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
                            uv,
                            uv1,
                        ).g
                    var coat_normal_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_CLEARCOAT_NORMAL_MAP
                        ]
                    )
                    if coat_normal_slot != NO_TEXTURE.value:
                        coat_texel = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            coat_normal_slot,
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
                            uv,
                            uv1,
                        )
                        coat_mapped = True
                    # The transmission map's red and the thickness map's
                    # green, sampled where the host samples them.
                    var through_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_TRANSMISSION_MAP
                        ]
                    )
                    if through_slot != NO_TEXTURE.value:
                        transmission_factor = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            through_slot,
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
                            uv,
                            uv1,
                        ).r
                    var deep_slot = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_THICKNESS_MAP
                        ]
                    )
                    if deep_slot != NO_TEXTURE.value:
                        thickness_factor = _sample_placed_slot(
                            texels,
                            ramp,
                            table,
                            deep_slot,
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
                            uv,
                            uv1,
                        ).g
                # The node graph's color, opacity and emissive, once the
                # maps have had their say, exactly as `rasterize_shaded`
                # replaces them.
                if noded:
                    var given = NodeInputs(
                        u,
                        v,
                        Vector3(wx, wy, wz),
                        Vector3(nx, ny, nz),
                        tint,
                        Vector3(0, 0, 0),
                        textured,
                    )
                    if has_output(nodes, COLOR_NODE):
                        var diffuse = run_nodes(nodes, COLOR_NODE, given)
                        red = diffuse[0] * arriving.x
                        green = diffuse[1] * arriving.y
                        blue = diffuse[2] * arriving.z
                    if has_output(nodes, OPACITY_NODE):
                        alpha = run_nodes(nodes, OPACITY_NODE, given)[0]
                    if has_output(nodes, EMISSIVE_NODE):
                        var given_off = run_nodes(nodes, EMISSIVE_NODE, given)
                        glow_r = given_off[0]
                        glow_g = given_off[1]
                        glow_b = given_off[2]
                    # The mask, before the alpha test, as the host asks it.
                    if masked and run_nodes(nodes, MASK_NODE, given)[0] == 0:
                        continue
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
                        # A depth by its packing, or a distance packed into
                        # four channels, by the host's own functions. A
                        # packed alpha is data too, and is kept.
                        var written: SIMD[DType.float32, 4]
                        if measures:
                            written = packed_distance_fragment(
                                Vector3(wx, wy, wz),
                                Vector3(
                                    corners[
                                        unsafe_offset=base + LANE_REFERENCE_X
                                    ],
                                    corners[
                                        unsafe_offset=base + LANE_REFERENCE_Y
                                    ],
                                    corners[
                                        unsafe_offset=base + LANE_REFERENCE_Z
                                    ],
                                ),
                                corners[
                                    unsafe_offset=base + LANE_NEAR_DISTANCE
                                ],
                                corners[unsafe_offset=base + LANE_FAR_DISTANCE],
                            )
                        else:
                            written = packed_depth_fragment(
                                DepthPacking(
                                    Int(
                                        maps[
                                            unsafe_offset=index
                                            * STATE_PER_TRIANGLE
                                            + STATE_DEPTH_PACKING
                                        ]
                                    )
                                ),
                                z,
                                alpha,
                            )
                        shown = _decoded(
                            ramp, written[0], written[1], written[2]
                        )
                        alpha = written[3]
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
                    # rides in the specular lanes, from the first corner,
                    # unless a specular map changes it.
                    var head_on = Vector3(
                        corners[unsafe_offset=base + LANE_SPECULAR_R],
                        corners[unsafe_offset=base + LANE_SPECULAR_G],
                        corners[unsafe_offset=base + LANE_SPECULAR_B],
                    )
                    var intensity = corners[
                        unsafe_offset=base + LANE_SPECULAR_INTENSITY
                    ]
                    var specular_mapped = maps[
                        unsafe_offset=index * STATE_PER_TRIANGLE
                        + STATE_SPECULAR_INTENSITY_MAP
                    ] != Int32(NO_TEXTURE.value) or maps[
                        unsafe_offset=index * STATE_PER_TRIANGLE
                        + STATE_SPECULAR_COLOR_MAP
                    ] != Int32(
                        NO_TEXTURE.value
                    )
                    if specular_mapped:
                        intensity = intensity * specular_alpha
                        head_on = specular_reflectance(
                            corners[unsafe_offset=base + LANE_IOR],
                            Vector3(
                                corners[
                                    unsafe_offset=base + LANE_SPECULAR_COLOR_R
                                ],
                                corners[
                                    unsafe_offset=base + LANE_SPECULAR_COLOR_G
                                ],
                                corners[
                                    unsafe_offset=base + LANE_SPECULAR_COLOR_B
                                ],
                            ),
                            intensity,
                            specular_texel,
                        )
                    var surface = physical_surface(
                        Vector3(red, green, blue),
                        head_on,
                        corners[unsafe_offset=base + LANE_METALNESS]
                        * metal_factor,
                        intensity,
                    )
                    # How fast the normal before any map turns across the
                    # pixel, in view space, as `rasterize_shaded` measures
                    # it: three.js's `geometryRoughness`.
                    var bare = _normal_at(
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
                    )
                    var curve = geometry_roughness(
                        view_direction(
                            _normal_at(
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
                            - bare,
                            view_up,
                            view_back,
                        ),
                        view_direction(
                            _normal_at(
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
                            - bare,
                            view_up,
                            view_back,
                        ),
                    )
                    var rough = floored_roughness(
                        corners[unsafe_offset=base + LANE_ROUGHNESS]
                        * rough_factor,
                        curve,
                    )
                    var coat_amount = corners[
                        unsafe_offset=base + LANE_CLEARCOAT
                    ]
                    var coat = clearcoat_of(coat_amount, coat_factor)
                    var coat_rough = floored_roughness(
                        corners[unsafe_offset=base + LANE_CLEARCOAT_ROUGHNESS]
                        * coat_rough_factor,
                        curve,
                    )
                    # The coat's normal map, for its own frame and for the
                    # anisotropic frame below.
                    var coat_map = Int(
                        maps[
                            unsafe_offset=index * STATE_PER_TRIANGLE
                            + STATE_CLEARCOAT_NORMAL_MAP
                        ]
                    )
                    var facing = Vector3(nx, ny, nz)
                    var coat_facing = Vector3(cnx, cny, cnz)
                    var spot = Vector3(wx, wy, wz)
                    # The coat's own normal, by the host's `mapped_normal`
                    # along the frame measured as `rasterize_shaded`
                    # measures it.
                    var coat_normal = coat_facing
                    if coat_amount > 0 and coat_mapped:
                        var coat_placed = _placement(table, coat_map)
                        var coat_steps = _placed_steps(
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
                            coat_placed,
                            coat_placed.place(uv, uv1),
                        )
                        coat_normal = mapped_normal(
                            coat_facing,
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
                            - spot,
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
                            - spot,
                            coat_steps[0],
                            coat_steps[1],
                            coat_texel,
                            Vector2(
                                corners[
                                    unsafe_offset=base
                                    + LANE_CLEARCOAT_NORMAL_SCALE_X
                                ],
                                corners[
                                    unsafe_offset=base
                                    + LANE_CLEARCOAT_NORMAL_SCALE_Y
                                ],
                            ),
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
                    # The tangent frame an anisotropic lobe is stretched
                    # along, measured as `rasterize_shaded` measures it,
                    # whatever the mode, on the normal map's coordinates,
                    # else the coat's normal map's, else the raw first
                    # pair.
                    var stretch = Vector2(
                        corners[unsafe_offset=base + LANE_ANISOTROPY_X],
                        corners[unsafe_offset=base + LANE_ANISOTROPY_Y],
                    )
                    var frame = TangentFrame(Vector3(0, 0, 0), Vector3(0, 0, 0))
                    if stretch.x != 0 or stretch.y != 0:
                        var framed = UvPlacement()
                        if textured and normal_slot >= 0:
                            framed = _placement(table, Int(normal_slot))
                        elif textured and coat_map >= 0:
                            framed = _placement(table, coat_map)
                        var here_lane = LANE_U
                        if framed.channel == UV_CHANNEL_1:
                            here_lane = LANE_U1
                        var frame_steps = _placed_steps(
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
                            framed,
                            framed.moved(
                                _uv_at(
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
                                    here_lane,
                                )
                            ),
                        )
                        frame = tangent_frame(
                            coat_facing,
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
                            - spot,
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
                            - spot,
                            frame_steps[0],
                            frame_steps[1],
                        )
                    # The sheen, the film and the stretch, by the host's
                    # own function from the same numbers and texels.
                    var layers = layers_of(
                        Vector3(
                            corners[unsafe_offset=base + LANE_SHEEN_R]
                            * sheen_tint.x,
                            corners[unsafe_offset=base + LANE_SHEEN_G]
                            * sheen_tint.y,
                            corners[unsafe_offset=base + LANE_SHEEN_B]
                            * sheen_tint.z,
                        ),
                        sheen_roughness_of(
                            corners[unsafe_offset=base + LANE_SHEEN_ROUGHNESS],
                            sheen_alpha,
                        ),
                        corners[unsafe_offset=base + LANE_IRIDESCENCE]
                        * film_factor,
                        corners[unsafe_offset=base + LANE_IRIDESCENCE_IOR],
                        iridescence_thickness(
                            corners[
                                unsafe_offset=base + LANE_THICKNESS_MINIMUM
                            ],
                            corners[
                                unsafe_offset=base + LANE_THICKNESS_MAXIMUM
                            ],
                            thickness_texel,
                            thickness_mapped,
                        ),
                        stretch,
                        stretch_texel,
                        frame.tangent,
                        frame.bitangent,
                        facing,
                        toward_eye,
                        surface.specular,
                        rough,
                    )
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
                        coat_normal,
                        spot,
                        surface,
                        rough,
                        coat,
                        coat_rough,
                        receives,
                        layers,
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
                    var dot_nv = max(
                        Float32(0), min(Float32(1), facing.dot(toward_eye))
                    )
                    var dot_nv_coat = max(
                        Float32(0),
                        min(Float32(1), coat_normal.dot(toward_eye)),
                    )
                    var radiance = Vector3(0, 0, 0)
                    var irradiance = Vector3(0, 0, 0)
                    var coat_radiance = Vector3(0, 0, 0)
                    if reflects:
                        var strength = corners[
                            unsafe_offset=base + LANE_ENV_INTENSITY
                        ]
                        # Turned by the env map's rotation, as the host
                        # turns every direction; see `rasterize_shaded`.
                        var spin = _basis_at(corners, base + LANE_ENV_ROTATION)
                        var seen = _sample_cube_rough(
                            texels,
                            ramp,
                            table,
                            Int(env_slot),
                            spin.turn(
                                rough_reflection(
                                    toward_eye,
                                    bent_normal(
                                        facing, toward_eye, layers, rough
                                    ),
                                    rough,
                                )
                            ),
                            rough,
                        )
                        var around = _sample_cube_rough(
                            texels,
                            ramp,
                            table,
                            Int(env_slot),
                            spin.turn(facing),
                            1,
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
                        if coat_amount > 0:
                            var gloss = _sample_cube_rough(
                                texels,
                                ramp,
                                table,
                                Int(env_slot),
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
                    # The opaque scene through the surface, by the host's
                    # own `volume_refraction` over the device's copy of
                    # the target; see `rasterize_shaded`.
                    var through = Float32(0)
                    var transmitted = Vector3(0, 0, 0)
                    var thinned = Float32(1)
                    var amount = corners[unsafe_offset=base + LANE_TRANSMISSION]
                    if amount > 0 and mode == Int32(SHADE_TEXTURE.value):
                        through = amount * transmission_factor
                        var seen = _transmitted(
                            backdrop,
                            ramp,
                            Int(width) * Int(height) * 4,
                            facing,
                            toward_eye_at(
                                Vector3(
                                    lights[unsafe_offset=LIGHTS_EYE],
                                    lights[unsafe_offset=LIGHTS_EYE + 1],
                                    lights[unsafe_offset=LIGHTS_EYE + 2],
                                ),
                                PERSPECTIVE_VIEW,
                                spot,
                            ),
                            rough,
                            surface,
                            spot,
                            Vector3(
                                corners[unsafe_offset=base + LANE_THICKNESS_X],
                                corners[unsafe_offset=base + LANE_THICKNESS_Y],
                                corners[unsafe_offset=base + LANE_THICKNESS_Z],
                            )
                            * thickness_factor,
                            corners[unsafe_offset=base + LANE_DISPERSION],
                            corners[unsafe_offset=base + LANE_IOR],
                            Vector3(
                                corners[
                                    unsafe_offset=base + LANE_ATTENUATION_R
                                ],
                                corners[
                                    unsafe_offset=base + LANE_ATTENUATION_G
                                ],
                                corners[
                                    unsafe_offset=base + LANE_ATTENUATION_B
                                ],
                            ),
                            corners[
                                unsafe_offset=base + LANE_ATTENUATION_DISTANCE
                            ],
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
                        Vector3(glow_r, glow_g, glow_b),
                        coat,
                        coat_rough,
                        Vector3(dot_nv_coat, 0, 0),
                        coat_radiance,
                        occlusion,
                        through,
                        transmitted,
                        layers=layers,
                    )
                    red = outgoing.x
                    green = outgoing.y
                    blue = outgoing.z
                    alpha *= thinned
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
                        # A refraction mapping, read off the cube's
                        # panorama row, bends the view instead; see
                        # `env_direction`.
                        var bounce = env_direction(
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
                            _describe(
                                table, Int(env_slot) + CUBE_PANORAMA
                            ).mapping.refracts(),
                            TextureFrames(
                                _basis_at(corners, base + LANE_ENV_ROTATION),
                                corners[
                                    unsafe_offset=base + LANE_REFRACTION_RATIO
                                ],
                                TANGENT_SPACE_NORMAL_MAP,
                                Basis3(),
                            ),
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
                if (
                    fog_on
                    and not shows_data
                    and maps[
                        unsafe_offset=index * STATE_PER_TRIANGLE + STATE_FOG
                    ]
                    != 0
                ):
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
                # The node graph's output last, reading the finished light,
                # exactly as `rasterize_shaded` runs it.
                if noded and has_output(nodes, OUTPUT_NODE):
                    var finished = run_nodes(
                        nodes,
                        OUTPUT_NODE,
                        NodeInputs(
                            u,
                            v,
                            Vector3(wx, wy, wz),
                            Vector3(nx, ny, nz),
                            tint,
                            Vector3(red, green, blue),
                            textured,
                        ),
                    )
                    red = finished[0]
                    green = finished[1]
                    blue = finished[2]

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
                # and as `rasterize_shaded` writes it; only a depth or a
                # distance material keeps its alpha. A fragment that shows
                # data is kept straight, as `RenderTarget.write` keeps it:
                # a packed alpha is data, and is often zero.
                if kind != Int32(DEPTH.value) and not measures:
                    share = 1
                var scale = share
                if shows_data:
                    scale = 1
                mixed_r = red * scale
                mixed_g = green * scale
                mixed_b = blue * scale
                mixed_a = share
                # A write replaces the pixel, so its answer becomes this
                # fragment's, exactly as `RenderTarget.write` decides it.
                # The uv view shows coordinates, which the tone mapping has
                # to leave alone exactly as it leaves a normal alone.
                data = shows_data or mode == Int32(SHADE_UV.value)
                # And its normal, turned into view space by the host's
                # function, or as it is for a normal material, whose
                # normals the renderer turned already.
                var turned = Vector3(nx, ny, nz)
                if not shows_normal:
                    turned = view_direction(turned, view_up, view_back)
                kept_x = turned.x
                kept_y = turned.y
                kept_z = turned.z
            elif state.color_write:
                # The mode's arithmetic, shared with `RenderTarget.blend`.
                var out = blend_pixel(
                    _behind(mixed_r, mixed_g, mixed_b, mixed_a, data),
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
    var lit = FloatColor(mixed_r, mixed_g, mixed_b, mixed_a)
    var curve = Int(tone)
    if data:
        curve = NO_TONE_MAPPING.value
    else:
        lit = lit.unpremultiplied()
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
    # And the attachments, in the planes after the depth: the light before
    # the curve, the normal and whether the pixel is data. What a host
    # target holds after the same draw; see `read_back_target`.
    var planes = Int(width) * Int(height)
    var color_at = planes * PLANE_COLOR + slot * 4
    depth[unsafe_offset=color_at] = mixed_r
    depth[unsafe_offset=color_at + 1] = mixed_g
    depth[unsafe_offset=color_at + 2] = mixed_b
    depth[unsafe_offset=color_at + 3] = mixed_a
    var normal_at = planes * PLANE_NORMAL + slot * 3
    depth[unsafe_offset=normal_at] = kept_x
    depth[unsafe_offset=normal_at + 1] = kept_y
    depth[unsafe_offset=normal_at + 2] = kept_z
    var flag = Float32(0)
    if data:
        flag = 1
    depth[unsafe_offset=planes * PLANE_DATA + slot] = flag

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
    # The depth, then the attachments a host target holds, one plane each;
    # see `PLANE_FLOATS`.
    var depth: DeviceBuffer[DType.float32]
    # The color the last draw cleared to, which a target read back holds
    # as its clear color.
    var cleared: Color
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
    # How many floats the fog buffer has room for: the fog's own, then the
    # node programs a draw passes, which ride after it; see
    # `program_starts`. Grown to fit.
    var fog_room: Int
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
    # How many bytes the backdrop buffer holds past the backdrop's own
    # pixels, for the transmission target a draw passes; see
    # `TRANSMISSION_HEADER`. Zero until a draw passes one, and grown to fit.
    var transmission_room: Int
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
            width * height * PLANE_FLOATS
        )
        self.cleared = Color(0, 0, 0, 0)
        # Room for the camera, its direction, its up axis, the ambient term
        # and one directional light to begin with.
        self.light_room = LIGHTS_FIRST + 6
        self.lights = self.context.enqueue_create_buffer[DType.float32](
            self.light_room
        )
        self.fog = self.context.enqueue_create_buffer[DType.float32](FOG_FLOATS)
        self.fog_room = FOG_FLOATS
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
        self.transmission_room = 0
        # The depth at the far distance and every attachment empty, so a
        # target read back after a scissored draw holds no garbage outside
        # the scissor: what a fresh host target holds. The far distance is
        # the mode's clear value, infinity until a draw names another mode;
        # the kernel writes infinity for an unclaimed pixel under every
        # mode, and the read backs turn it into the mode's own clear.
        var planes = width * height
        var blank = List[Float32](length=planes * PLANE_FLOATS, fill=0)
        for slot in range(planes):
            blank[slot] = cleared_depth(self.depth_mode)
        with self.depth.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=blank.unsafe_ptr(),
                count=planes * PLANE_FLOATS,
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

    def _upload_fog(mut self, fog: FogView, programs: NodeProgramStore) raises:
        """Put `fog` on the device, and the node programs after it.

        Args:
            fog: The scene's fog, as the rasterizers take it.
            programs: The node programs, laid out as `program_starts`
                says.

        Raises:
            Error: If the device buffer cannot be made or written.
        """
        var flat = flatten_fog(fog)
        flat.extend(flatten_programs(programs))
        if len(flat) > self.fog_room:
            # A draw still in flight may be reading the old buffer; see
            # `set_textures`, which waits for the same reason.
            self.context.synchronize()
            self.fog = self.context.enqueue_create_buffer[DType.float32](
                len(flat)
            )
            self.fog_room = len(flat)
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
        transmission: TransmissionTarget = TransmissionTarget(),
        programs: NodeProgramStore = NodeProgramStore(),
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
            transmission: The opaque scene the transmissive triangles
                show through themselves, as `Renderer.transmission_target`
                draws it on the host, or an empty target when none
                transmits. Uploaded with the draw, after the backdrop.
            programs: The node materials' programs, as
                `Renderer.prepare_frame` gives them with the frame's time
                and view. Uploaded with the draw, after the fog.

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
                uploaded, the backdrop is not the target's size, the
                depth mode is none of the three, or a triangle names a
                node program that is not in `programs` or one that reads
                a texture that is not uploaded under `SHADE_TEXTURE`.
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
        # Asked of the triangles a draw names, as `rasterize_frame` asks
        # it: the kernel reads the target wherever a triangle transmits.
        var ready = transmission.is_ready()
        for index in range(len(order)):
            ref run = order[index]
            if run.kind != DRAW_TRIANGLES:
                continue
            for triangle in range(run.first, run.first + run.count):
                check_transmission(corners[triangle * 3], mode, ready)
        # Every node program a triangle names, and every texture it reads,
        # asked here for the reason a texture id is: the kernel reads the
        # buffers at whatever offset the state hands it. The uv view runs
        # no program, as `check_triangle_maps` asks nothing of one there.
        if mode != SHADE_UV:
            for triangle in range(triangles):
                var named = corners[triangle * 3].nodes
                if named == NO_NODES:
                    continue
                ref program = programs.get(named)
                if mode != SHADE_TEXTURE:
                    continue
                for slot in range(len(program.textures)):
                    if program.textures[slot].value < 0:
                        raise Error(
                            "A node program reads a texture uniform that"
                            " names no texture; call set_texture() first"
                        )
                    if program.textures[slot].value >= self.uploaded:
                        raise Error(
                            "A node program reads a texture that has not"
                            " been uploaded; call set_textures() first"
                        )

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
                corners[index].transmission_map,
                corners[index].thickness_map,
                corners[index].layers.sheen_color_map,
                corners[index].layers.sheen_roughness_map,
                corners[index].layers.iridescence_map,
                corners[index].layers.thickness_map,
                corners[index].layers.anisotropy_map,
                corners[index].layers.specular_intensity_map,
                corners[index].layers.specular_color_map,
                corners[index].layers.clearcoat_map,
                corners[index].layers.clearcoat_roughness_map,
                corners[index].layers.clearcoat_normal_map,
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
                self._check_data_map(
                    corners[triangle * 3].transmission_map,
                    "A transmission map",
                )
                self._check_data_map(
                    corners[triangle * 3].thickness_map, "A thickness map"
                )
                # The layers' maps, by `check_triangle_maps`'s three rules.
                ref layered = corners[triangle * 3].layers
                var tint = layered.sheen_color_map
                if tint != NO_TEXTURE and not self.ignores_alpha[tint.value]:
                    raise Error(
                        "A sheen color map must ignore its alpha; build the"
                        " texture with alpha=IGNORED"
                    )
                var cloth = layered.sheen_roughness_map
                if cloth != NO_TEXTURE:
                    if not self.is_linear[cloth.value]:
                        raise Error(
                            "A sheen roughness map holds data, not color;"
                            " build the texture with color_space=LINEAR"
                        )
                    if self.ignores_alpha[cloth.value]:
                        raise Error(
                            "A sheen roughness map is read from its alpha;"
                            " build the texture with alpha=COVERAGE"
                        )
                self._check_data_map(
                    layered.iridescence_map, "An iridescence map"
                )
                self._check_data_map(
                    layered.thickness_map, "An iridescence thickness map"
                )
                self._check_data_map(
                    layered.anisotropy_map, "An anisotropy map"
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
            var state = triangle_state(
                corners, self.uploaded, program_starts(programs)
            )
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
        self._upload_fog(fog, programs)
        # The transmission target, flattened, and room for it made after
        # the backdrop before the backdrop is written: a new buffer holds
        # nothing, so it is cleared below as a painted one would be.
        var behind = self.width * self.height * Framebuffer.CHANNELS
        var scene_bytes = List[UInt8]()
        if ready:
            scene_bytes = flatten_transmission(transmission)
            if len(scene_bytes) > self.transmission_room:
                self.context.synchronize()
                self.backdrop = self.context.enqueue_create_buffer[DType.uint8](
                    behind + len(scene_bytes)
                )
                self.transmission_room = len(scene_bytes)
                self.painted = True
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
        if ready:
            with self.backdrop.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr().unsafe_offset(behind),
                    src=scene_bytes.unsafe_ptr(),
                    count=len(scene_bytes),
                )
        # The uv view is coordinates rather than light and is never tone
        # mapped, background included, exactly as `Renderer.render` turns
        # the curve off for it. The curve was checked above as given;
        # what the kernel is handed is what the host resolves with.
        var curve = tone_mapping
        if mode == SHADE_UV:
            curve = NO_TONE_MAPPING
        self.cleared = background
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

    def read_back_target(
        self,
        type: TargetType = UNSIGNED_BYTE_TARGET,
        outputs: List[TargetOutput] = color_only(),
    ) raises -> RenderTarget:
        """Copy the device's attachments into a host render target, before
        any curve or encode: three.js's float and multiple render targets.

        The kernel leaves the premultiplied light, the view-space normal
        and the data flag of every pixel beside its depth, so what comes
        back is the target `rasterize_frame` fills on the host from the
        same draw. Read its attachments with `RenderTarget.attachment`, or
        resolve it with `RenderTarget.resolve`. A pixel outside the last
        draw's scissor holds whatever the draw before it left.

        Args:
            type: What the target's attachments store; see
                `render.target.TargetType`.
            outputs: What each of its color attachments holds; see
                `render.target.TargetOutput`.

        Returns:
            The target, cleared to the last draw's background, in the
            last draw's depth mode.

        Raises:
            Error: If nothing has been drawn yet, or `check_target`
                refuses the type or the outputs.
        """
        if not self.drawn:
            raise Error(
                "Nothing has been drawn yet; call draw() before"
                " read_back_target()"
            )
        var target = RenderTarget(
            self.width, self.height, self.cleared, type, outputs
        )
        target.depth_mode = self.depth_mode
        var planes = self.width * self.height
        var flat = List[Float32](length=planes * PLANE_FLOATS, fill=0)
        with self.depth.map_to_host() as host:
            unsafe_memcpy(
                dest=flat.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=planes * PLANE_FLOATS,
            )
        var keeps = target.has_normals()
        var reversed = self.depth_mode == REVERSED_DEPTH
        for slot in range(planes):
            # Infinity where no primitive claimed the depth, which under
            # `REVERSED_DEPTH` is the mode's clear, as `read_back` has it.
            var z = flat[slot]
            if reversed and z == inf[DType.float32]():
                z = cleared_depth(REVERSED_DEPTH)
            target.depth[slot] = z
            var at = planes * PLANE_COLOR + slot * 4
            target.colors[slot] = FloatColor(
                flat[at], flat[at + 1], flat[at + 2], flat[at + 3]
            )
            target.data[slot] = flat[planes * PLANE_DATA + slot] != 0
            if keeps:
                var normal_at = planes * PLANE_NORMAL + slot * 3
                target.normals[slot] = Vector3(
                    flat[normal_at], flat[normal_at + 1], flat[normal_at + 2]
                )
        return target^


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
    transmission: TransmissionTarget = TransmissionTarget(),
    programs: NodeProgramStore = NodeProgramStore(),
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
        transmission: The opaque scene the transmissive triangles show
            through themselves; see `GpuRenderer.draw`.
        programs: The node materials' programs; see `GpuRenderer.draw`.

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
        transmission=transmission,
        programs=programs,
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


# --- post-processing ---------------------------------------------------------
#
# A composer's frame on the device: four floats of premultiplied light a
# pixel, one byte saying whether the pixel holds data, its depth and its
# stencil. The kernels below run the passes on it, one thread per pixel,
# each calling the per-pixel function the host pass calls. See
# `GpuComposer`.


def _load(light: MutPointer[Float32, MutAnyOrigin], slot: Int) -> FloatColor:
    """Return one pixel of a device frame."""
    var at = slot * 4
    return FloatColor(
        light[unsafe_offset=at],
        light[unsafe_offset=at + 1],
        light[unsafe_offset=at + 2],
        light[unsafe_offset=at + 3],
    )


def _store(
    light: MutPointer[Float32, MutAnyOrigin], slot: Int, color: FloatColor
):
    """Write one pixel of a device frame."""
    var at = slot * 4
    light[unsafe_offset=at] = color.r
    light[unsafe_offset=at + 1] = color.g
    light[unsafe_offset=at + 2] = color.b
    light[unsafe_offset=at + 3] = color.a


def copy_floats_kernel(
    destination: MutPointer[Float32, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    count: Int32,
):
    """Copy `count` floats, one thread each: what a pass that reads its
    neighbors reads, taken before it writes."""
    var at = Int(global_idx.x)
    if at >= Int(count):
        return
    destination[unsafe_offset=at] = source[unsafe_offset=at]


def copy_bytes_kernel(
    destination: MutPointer[UInt8, MutAnyOrigin],
    source: MutPointer[UInt8, MutAnyOrigin],
    count: Int32,
):
    """Copy `count` bytes, one thread each."""
    var at = Int(global_idx.x)
    if at >= Int(count):
        return
    destination[unsafe_offset=at] = source[unsafe_offset=at]


def post_pixel_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    width: Int32,
    height: Int32,
    kind: Int32,
    a: Float32,
    b: Float32,
    c: Float32,
    d: Float32,
    e: Float32,
    flag: Int32,
):
    """Run one pass that reads nothing but its own pixel: a copy, a film,
    a dot screen, a sepia, a vignette, a luminosity or an output pass.

    The numbers `a` through `e` and `flag` are the pass's settings, in the
    order `GpuComposer` hands them over; each kind reads its own.
    """
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var slot = y * w + x
    var color = _load(light, slot)
    var step = PassKind(Int(kind))
    var shown: FloatColor
    if step == COPY:
        shown = copy_pixel(color, a)
    elif step == FILM:
        shown = film_pixel(color, x, y, w, h, a, flag != 0, b)
    elif step == DOT_SCREEN:
        shown = dot_screen_pixel(color, x, y, w, h, Vector2(a, b), c, d, e)
    elif step == SEPIA:
        shown = sepia_pixel(color, a)
    elif step == VIGNETTE:
        shown = vignette_pixel(color, x, y, w, h, a, b)
    elif step == LUMINOSITY:
        shown = luminosity_pixel(color)
    else:
        # `OUTPUT`: a pixel that holds data keeps its numbers.
        if data[unsafe_offset=slot] != 0:
            return
        shown = output_pixel(color, ToneMapping(Int(flag)), a)
    _store(light, slot, shown)


def afterimage_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    memory: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    damp: Float32,
):
    """Keep the last frame fading under this one: `afterimage_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var slot = y * Int(width) + x
    _store(
        light,
        slot,
        afterimage_pixel(_load(light, slot), _load(memory, slot), damp),
    )


def blur_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    spread: Float32,
    across: Int32,
):
    """Blur along one axis, nine taps: `blur_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var view = LightView(floats=source, width=w, height=h)
    _store(light, y * w + x, blur_pixel(view, x, y, spread, across != 0))


def bright_kernel(
    bright: MutPointer[Float32, MutAnyOrigin],
    light: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    threshold: Float32,
):
    """Keep the light above the bloom's threshold: `bright_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var slot = y * Int(width) + x
    _store(bright, slot, bright_pixel(_load(light, slot), threshold))


def bloom_blur_kernel(
    destination: MutPointer[Float32, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    source_width: Int32,
    source_height: Int32,
    width: Int32,
    height: Int32,
    kernel: Int32,
    across: Int32,
):
    """Blur one bloom level along one axis: `separable_blur_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var view = LightView(
        floats=source, width=Int(source_width), height=Int(source_height)
    )
    _store(
        destination,
        y * w + x,
        separable_blur_pixel(view, x, y, w, h, Int(kernel), across != 0),
    )


def bloom_composite_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    levels: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    radius: Float32,
    strength: Float32,
):
    """Add the five blurred levels to the frame: `bloom_glow` for each,
    then `glow_pixel`. The levels lie back to back, each half the size
    of the one before, as `GpuComposer` lays them out."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var u = u_of(x, w)
    var v = v_of(y, h)
    var glow = FloatColor(0, 0, 0, 0)
    var level_width = halved_size(w)
    var level_height = halved_size(h)
    var start = 0
    var level = 0
    while level < BLOOM_LEVELS:
        var view = LightView(
            floats=levels.unsafe_offset(start),
            width=level_width,
            height=level_height,
        )
        glow = bloom_glow(glow, view, level, u, v, radius, strength)
        start += level_width * level_height * 4
        level_width = halved_size(level_width)
        level_height = halved_size(level_height)
        level += 1
    var slot = y * w + x
    _store(light, slot, glow_pixel(_load(light, slot), glow))


def fxaa_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
):
    """Smooth jagged edges: `fxaa_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var view = LightView(floats=source, width=w, height=h)
    _store(light, y * w + x, fxaa_pixel(view, u_of(x, w), v_of(y, h)))


def bokeh_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    near: Float32,
    far: Float32,
    focus: Float32,
    aperture: Float32,
    max_blur: Float32,
):
    """Blur by distance from the focus: `bokeh_reach`, then
    `bokeh_pixel`. `depth` is the window depth of every pixel."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var slot = y * w + x
    var blur = bokeh_reach(
        Length(near, METER),
        Length(far, METER),
        depth[unsafe_offset=slot],
        Length(focus, METER),
        aperture,
        max_blur,
    )
    var view = LightView(floats=source, width=w, height=h)
    _store(light, slot, bokeh_pixel(view, x, y, blur))
    data[unsafe_offset=slot] = 0


def glitch_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    heightmap: MutPointer[Float32, MutAnyOrigin],
    size: Int32,
    width: Int32,
    height: Int32,
    seed: Float32,
    amount: Float32,
    seed_x: Float32,
    seed_y: Float32,
    distortion_x: Float32,
    distortion_y: Float32,
    shift_x: Float32,
    shift_y: Float32,
):
    """Tear, shift and snow the frame: `glitch_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var uniforms = GlitchUniforms()
    uniforms.seed = seed
    uniforms.amount = amount
    uniforms.seed_x = seed_x
    uniforms.seed_y = seed_y
    uniforms.distortion_x = distortion_x
    uniforms.distortion_y = distortion_y
    var view = LightView(floats=source, width=w, height=h)
    var map = heightmap.unsafe_mut_cast[False]().unsafe_origin_cast[Untracked]()
    _store(
        light,
        y * w + x,
        glitch_pixel(view, map, Int(size), uniforms, shift_x, shift_y, x, y),
    )


def halftone_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    shape: Int32,
    radius: Float32,
    rotate_r: Float32,
    rotate_g: Float32,
    rotate_b: Float32,
    scatter: Float32,
    blending: Float32,
    blending_mode: Int32,
    grayscale: Int32,
):
    """Redraw each channel as a grid of dots: `halftone_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var settings = HalftoneSettings()
    settings.shape = HalftoneShape(Int(shape))
    settings.radius = radius
    settings.rotate_r = Angle(rotate_r, RADIAN)
    settings.rotate_g = Angle(rotate_g, RADIAN)
    settings.rotate_b = Angle(rotate_b, RADIAN)
    settings.scatter = scatter
    settings.blending = blending
    settings.blending_mode = HalftoneBlending(Int(blending_mode))
    settings.grayscale = grayscale != 0
    var view = LightView(floats=source, width=w, height=h)
    var slot = y * w + x
    _store(light, slot, halftone_pixel(view, x, y, settings))
    data[unsafe_offset=slot] = 0


def clear_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    stencil: MutPointer[UInt8, MutAnyOrigin],
    width: Int32,
    height: Int32,
    red: Float32,
    green: Float32,
    blue: Float32,
    alpha: Float32,
    cleared: Float32,
):
    """Clear the light, the data flags, the depth and the stencil:
    `clear_light`, whose color the host has already premultiplied."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var slot = y * Int(width) + x
    _store(light, slot, FloatColor(red, green, blue, alpha))
    data[unsafe_offset=slot] = 0
    depth[unsafe_offset=slot] = cleared
    stencil[unsafe_offset=slot] = 0


def data_alpha_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    width: Int32,
    height: Int32,
    premultiply: Int32,
):
    """Premultiply every data pixel, or unpremultiply it: what
    `EffectComposer.run_step` does on the host around a pass that
    `reads_frame_as_light`. A light pixel is left alone."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var slot = y * Int(width) + x
    if data[unsafe_offset=slot] == 0:
        return
    var color = _load(light, slot)
    if premultiply != 0:
        _store(light, slot, color.premultiplied())
    else:
        _store(light, slot, color.unpremultiplied())


def texture_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    overlay: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    opacity: Float32,
):
    """Add a texture sampled at every pixel: `texture_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var slot = y * Int(width) + x
    _store(
        light,
        slot,
        texture_pixel(_load(light, slot), _load(overlay, slot), opacity),
    )
    data[unsafe_offset=slot] = 0


def lut_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    texels: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
    lut_width: Int32,
    lut_height: Int32,
    lut_depth: Int32,
    wrap_s: Int32,
    wrap_t: Int32,
    wrap_r: Int32,
    filter: Int32,
    intensity: Float32,
):
    """Grade through a color lookup table: `lut_pixel` on a
    `DecodedVolume`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var lut = DecodedVolume(
        floats=texels,
        width=Int(lut_width),
        height=Int(lut_height),
        depth=Int(lut_depth),
        wrap_s=Wrap(Int(wrap_s)),
        wrap_t=Wrap(Int(wrap_t)),
        wrap_r=Wrap(Int(wrap_r)),
        filter=Filter(Int(filter)),
    )
    var slot = y * Int(width) + x
    _store(light, slot, lut_pixel(_load(light, slot), lut, intensity))


def keep_outside_mask_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    stencil: MutPointer[UInt8, MutAnyOrigin],
    saved_light: MutPointer[Float32, MutAnyOrigin],
    saved_data: MutPointer[UInt8, MutAnyOrigin],
    saved_depth: MutPointer[Float32, MutAnyOrigin],
    saved_stencil: MutPointer[UInt8, MutAnyOrigin],
    width: Int32,
    height: Int32,
):
    """Put back every pixel the mask keeps, and the whole stencil:
    `keep_outside_mask`, deciding each pixel by `inside_mask`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var slot = y * Int(width) + x
    var stored = saved_stencil[unsafe_offset=slot]
    if not inside_mask(Int(stored)):
        _store(light, slot, _load(saved_light, slot))
        data[unsafe_offset=slot] = saved_data[unsafe_offset=slot]
        depth[unsafe_offset=slot] = saved_depth[unsafe_offset=slot]
    stencil[unsafe_offset=slot] = stored


def effect_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    params: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
):
    """Run one of the fifteen screen shaders: `effect_pixel`, its settings
    read back from `params` by `effect_from_floats`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var view = LightView(floats=source, width=w, height=h)
    var slot = y * w + x
    _store(light, slot, effect_pixel(view, x, y, effect_from_floats(params)))
    data[unsafe_offset=slot] = 0


def god_rays_generate_kernel(
    destination: MutPointer[Float32, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    source_width: Int32,
    source_height: Int32,
    width: Int32,
    height: Int32,
    sun_x: Float32,
    sun_y: Float32,
    sun_z: Float32,
    step: Float32,
):
    """Walk the mask or the rays toward the sun: `god_rays_generate_pixel`."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var view = LightView(
        floats=source, width=Int(source_width), height=Int(source_height)
    )
    _store(
        destination,
        y * w + x,
        god_rays_generate_pixel(
            view, u_of(x, w), v_of(y, h), Vector3(sun_x, sun_y, sun_z), step
        ),
    )


def god_rays_combine_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    mask: MutPointer[Float32, MutAnyOrigin],
    rays: MutPointer[Float32, MutAnyOrigin],
    params: MutPointer[Float32, MutAnyOrigin],
    rays_width: Int32,
    rays_height: Int32,
    width: Int32,
    height: Int32,
):
    """Add the rays to the frame, over the fake sun where asked:
    `god_rays_combine_pixel`. The mask's red is the window depth, and
    `params` holds what `GpuComposer` packs: the sun, the intensity, the
    fake sun's switch and its two colors."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var settings = GodRaysSettings()
    settings.intensity = params[unsafe_offset=3]
    settings.fake_sun = params[unsafe_offset=4] != 0
    settings.sun_color = Color(
        UInt8(Int(params[unsafe_offset=5])),
        UInt8(Int(params[unsafe_offset=6])),
        UInt8(Int(params[unsafe_offset=7])),
    )
    settings.bg_color = Color(
        UInt8(Int(params[unsafe_offset=8])),
        UInt8(Int(params[unsafe_offset=9])),
        UInt8(Int(params[unsafe_offset=10])),
    )
    var sun = Vector3(
        params[unsafe_offset=0],
        params[unsafe_offset=1],
        params[unsafe_offset=2],
    )
    var view = LightView(
        floats=rays, width=Int(rays_width), height=Int(rays_height)
    )
    var slot = y * w + x
    var u = u_of(x, w)
    var v = v_of(y, h)
    _store(
        light,
        slot,
        god_rays_combine_pixel(
            _load(light, slot),
            view.sample(u, v).r,
            mask[unsafe_offset=slot * 4],
            u,
            v,
            Float32(w) / Float32(h),
            sun,
            settings,
        ),
    )
    data[unsafe_offset=slot] = 0


def shader_kernel(
    light: MutPointer[Float32, MutAnyOrigin],
    data: MutPointer[UInt8, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    code: MutPointer[Float32, MutAnyOrigin],
    saved_start: Int32,
    saved_width: Int32,
    saved_height: Int32,
    width: Int32,
    height: Int32,
):
    """Run a node program over the screen: `screen_pixel` on a
    `ScreenNodes`. `code` holds the program's floats, bound by
    `screen_code`, and the saved image `saved_start` floats in."""
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    var w = Int(width)
    var h = Int(height)
    if x >= w or y >= h:
        return
    var input = LightView(floats=source, width=w, height=h)
    var saved = LightView(
        floats=code.unsafe_offset(Int(saved_start)),
        width=Int(saved_width),
        height=Int(saved_height),
    )
    var words = code.unsafe_mut_cast[False]().unsafe_origin_cast[Untracked]()
    var slot = y * w + x
    _store(
        light,
        slot,
        screen_pixel(
            ScreenNodes(words, input, saved, x, y),
            _load(source, slot),
            u_of(x, w),
            v_of(y, h),
        ),
    )
    data[unsafe_offset=slot] = 0


def runs_on_device(kind: PassKind) -> Bool:
    """Return True if `GpuComposer` runs a pass of this kind on the
    device, and False if it reads the frame back and runs it on the host.

    The host runs every pass that draws the scene into the frame --
    render, SSAA, TAA, SSAO, SAO, SSR, outline and mask -- because the
    GPU rasterizer resolves to bytes and a pass needs the light. It runs
    SMAA too: its three stages walk rows and columns of edges. A bokeh
    and a god-rays pass draw their depth on the host and run the rest on
    the device. The pixelated, GTAO and transition passes draw the scene,
    so the host runs them. A shader pass whose program reads a texture in
    the assets also runs on the host; see `GpuComposer.render`.

    Args:
        kind: The pass's kind.

    Returns:
        Whether a kernel runs it.
    """
    return (
        kind == CUBE_TEXTURE
        or kind == SAVE
        or kind == SHADER
        or kind == SHADER_EFFECT
        or kind == GOD_RAYS
        or kind == COPY
        or kind == BLUR
        or kind == BLOOM
        or kind == FILM
        or kind == DOT_SCREEN
        or kind == SEPIA
        or kind == VIGNETTE
        or kind == LUMINOSITY
        or kind == AFTERIMAGE
        or kind == OUTPUT
        or kind == FXAA
        or kind == BOKEH
        or kind == GLITCH
        or kind == HALFTONE
        or kind == CLEAR
        or kind == TEXTURE
        or kind == LUT
    )


def _bloom_floats(width: Int, height: Int) -> Int:
    """Return how many floats the five bloom levels take back to back."""
    var total = 0
    var level_width = halved_size(width)
    var level_height = halved_size(height)
    for _ in range(BLOOM_LEVELS):
        total += level_width * level_height * 4
        level_width = halved_size(level_width)
        level_height = halved_size(level_height)
    return total


struct GpuComposer(Movable):
    """An `EffectComposer`'s frame kept on the GPU between passes.

    `render` runs a composer's passes as `EffectComposer.render` does,
    on a frame that lives in device buffers. A pass `runs_on_device`
    says yes to is one or more kernel launches, and the frame does not
    cross the bus. Any other pass reads the frame back, runs on the host
    through `EffectComposer.run_step`, and puts it back: a round trip,
    counted in `round_trips`. Every kernel calls the per-pixel function
    the host pass calls, so the two agree; `tests/test_gpu.mojo` checks
    each pass.
    """

    var width: Int
    var height: Int
    # How many passes of the last `render` ran on the host.
    var round_trips: Int
    # How many floats `extra` has room for.
    var extra_room: Int
    # Every device buffer is declared before the context that owns it,
    # and `__deinit__` releases them first; see `GpuRenderer.__deinit__`.
    # The frame: four floats a pixel, premultiplied light or, where the
    # pixel holds data, the data straight, as a host frame holds it; a
    # byte of whether it holds data, its depth and its stencil.
    var light: DeviceBuffer[DType.float32]
    var data: DeviceBuffer[DType.uint8]
    var depth: DeviceBuffer[DType.float32]
    var stencil: DeviceBuffer[DType.uint8]
    # The light before a pass that reads its neighbors, or the bloom's
    # bright light.
    var source: DeviceBuffer[DType.float32]
    # The frame before a pass inside a mask.
    var saved_light: DeviceBuffer[DType.float32]
    var saved_data: DeviceBuffer[DType.uint8]
    var saved_depth: DeviceBuffer[DType.float32]
    var saved_stencil: DeviceBuffer[DType.uint8]
    # The bloom's five levels back to back, and one level blurred across.
    var levels: DeviceBuffer[DType.float32]
    var across: DeviceBuffer[DType.float32]
    # What one pass reads besides the frame: a depth, a displacement map,
    # a texture, a table or a trail. Grown on demand.
    var extra: DeviceBuffer[DType.float32]
    # Declared last so that it is released last.
    var context: DeviceContext

    def __deinit__(deinit self):
        """Drain the queue, release the buffers, then the context, for the
        reason `GpuRenderer.__deinit__` gives."""
        try:
            self.context.synchronize()
        except:
            pass
        _ = self.light^
        _ = self.data^
        _ = self.depth^
        _ = self.stencil^
        _ = self.source^
        _ = self.saved_light^
        _ = self.saved_data^
        _ = self.saved_depth^
        _ = self.saved_stencil^
        _ = self.levels^
        _ = self.across^
        _ = self.extra^
        _ = self.context^

    def __init__(out self, width: Int, height: Int) raises:
        """Create the device frame for one size.

        Args:
            width: The frame's width in pixels.
            height: The frame's height in pixels.

        Raises:
            Error: If the dimensions are not positive, or no GPU is
                present.
        """
        if width <= 0 or height <= 0:
            raise Error("Framebuffer dimensions must be positive")
        if not available():
            raise Error("No GPU available")
        self.width = width
        self.height = height
        self.round_trips = 0
        var count = width * height
        self.context = DeviceContext()
        self.light = self.context.enqueue_create_buffer[DType.float32](
            count * 4
        )
        self.data = self.context.enqueue_create_buffer[DType.uint8](count)
        self.depth = self.context.enqueue_create_buffer[DType.float32](count)
        self.stencil = self.context.enqueue_create_buffer[DType.uint8](count)
        self.source = self.context.enqueue_create_buffer[DType.float32](
            count * 4
        )
        self.saved_light = self.context.enqueue_create_buffer[DType.float32](
            count * 4
        )
        self.saved_data = self.context.enqueue_create_buffer[DType.uint8](count)
        self.saved_depth = self.context.enqueue_create_buffer[DType.float32](
            count
        )
        self.saved_stencil = self.context.enqueue_create_buffer[DType.uint8](
            count
        )
        self.levels = self.context.enqueue_create_buffer[DType.float32](
            _bloom_floats(width, height)
        )
        self.across = self.context.enqueue_create_buffer[DType.float32](
            halved_size(width) * halved_size(height) * 4
        )
        # One pixel's worth to begin with; never zero, as `GpuRenderer`
        # never allocates zero.
        self.extra_room = 4
        self.extra = self.context.enqueue_create_buffer[DType.float32](4)

    def upload(mut self, frame: RenderTarget) raises:
        """Put a host frame's light, data flags, depth and stencil on the
        device.

        Args:
            frame: The frame, of this composer's size.

        Raises:
            Error: If the frame is another size, or a buffer cannot be
                written.
        """
        if frame.width != self.width or frame.height != self.height:
            raise Error("A GPU composer's frame must be its own size")
        var count = self.width * self.height
        var flags = List[UInt8](length=count, fill=0)
        for slot in range(count):
            if frame.data[slot]:
                flags[slot] = 1
        with self.light.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=frame.colors.unsafe_ptr().unsafe_bitcast[Float32](),
                count=count * 4,
            )
        with self.data.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(), src=flags.unsafe_ptr(), count=count
            )
        with self.depth.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=frame.depth.unsafe_ptr(),
                count=count,
            )
        with self.stencil.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=frame.stencil.unsafe_ptr(),
                count=count,
            )

    def download(self, mut frame: RenderTarget) raises:
        """Copy the device frame into a host frame of the same size,
        keeping the host frame's clear color, scissor, depth mode and
        normal attachment.

        Args:
            frame: The frame, overwritten.

        Raises:
            Error: If the frame is another size, or a buffer cannot be
                read.
        """
        if frame.width != self.width or frame.height != self.height:
            raise Error("A GPU composer's frame must be its own size")
        var count = self.width * self.height
        var flags = List[UInt8](length=count, fill=0)
        with self.light.map_to_host() as host:
            unsafe_memcpy(
                dest=frame.colors.unsafe_ptr().unsafe_bitcast[Float32](),
                src=host.unsafe_ptr(),
                count=count * 4,
            )
        with self.data.map_to_host() as host:
            unsafe_memcpy(
                dest=flags.unsafe_ptr(), src=host.unsafe_ptr(), count=count
            )
        with self.depth.map_to_host() as host:
            unsafe_memcpy(
                dest=frame.depth.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=count,
            )
        with self.stencil.map_to_host() as host:
            unsafe_memcpy(
                dest=frame.stencil.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=count,
            )
        for slot in range(count):
            frame.data[slot] = flags[slot] != 0

    def _room(mut self, count: Int) raises:
        """Grow `extra` to hold `count` floats."""
        if count <= self.extra_room:
            return
        # The old buffer may still be read by a launch in flight.
        self.context.synchronize()
        self.extra = self.context.enqueue_create_buffer[DType.float32](count)
        self.extra_room = count

    def _put_floats(mut self, values: List[Float32]) raises:
        """Write `values` to the start of `extra`."""
        self._room(len(values))
        with self.extra.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=values.unsafe_ptr(),
                count=len(values),
            )

    def _put_colors(mut self, colors: List[FloatColor]) raises:
        """Write `colors`, four floats each, to the start of `extra`."""
        self._room(len(colors) * 4)
        with self.extra.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=colors.unsafe_ptr().unsafe_bitcast[Float32](),
                count=len(colors) * 4,
            )

    def _data_alpha(mut self, premultiply: Bool) raises:
        """Premultiply the device frame's data pixels, or store them
        straight again; see `data_alpha_kernel`."""
        self.context.enqueue_function[data_alpha_kernel](
            self.light.unsafe_ptr(),
            self.data.unsafe_ptr(),
            Int32(self.width),
            Int32(self.height),
            Int32(1 if premultiply else 0),
            grid_dim=self._grid(),
            block_dim=(TILE, TILE),
        )

    def _grid(self) -> Tuple[Int, Int]:
        """Return the 2D grid that covers the frame in whole tiles."""
        return (ceildiv(self.width, TILE), ceildiv(self.height, TILE))

    def _copy_floats(
        self,
        destination: DeviceBuffer[DType.float32],
        source: DeviceBuffer[DType.float32],
        count: Int,
    ) raises:
        """Copy `count` floats from one device buffer to another."""
        self.context.enqueue_function[copy_floats_kernel](
            destination.unsafe_ptr(),
            source.unsafe_ptr(),
            Int32(count),
            grid_dim=ceildiv(count, TILE * TILE),
            block_dim=TILE * TILE,
        )

    def _copy_bytes(
        self,
        destination: DeviceBuffer[DType.uint8],
        source: DeviceBuffer[DType.uint8],
        count: Int,
    ) raises:
        """Copy `count` bytes from one device buffer to another."""
        self.context.enqueue_function[copy_bytes_kernel](
            destination.unsafe_ptr(),
            source.unsafe_ptr(),
            Int32(count),
            grid_dim=ceildiv(count, TILE * TILE),
            block_dim=TILE * TILE,
        )

    def _take_source(mut self) raises:
        """Copy the light to `source`, for a pass that reads its
        neighbors as they were."""
        self._copy_floats(self.source, self.light, self.width * self.height * 4)

    def _save(mut self) raises:
        """Copy the whole frame aside, before a pass inside a mask."""
        var count = self.width * self.height
        self._copy_floats(self.saved_light, self.light, count * 4)
        self._copy_bytes(self.saved_data, self.data, count)
        self._copy_floats(self.saved_depth, self.depth, count)
        self._copy_bytes(self.saved_stencil, self.stencil, count)

    def _keep_outside_mask(mut self) raises:
        """Put back what the mask keeps, after a pass inside it."""
        var grid = self._grid()
        self.context.enqueue_function[keep_outside_mask_kernel](
            self.light.unsafe_ptr(),
            self.data.unsafe_ptr(),
            self.depth.unsafe_ptr(),
            self.stencil.unsafe_ptr(),
            self.saved_light.unsafe_ptr(),
            self.saved_data.unsafe_ptr(),
            self.saved_depth.unsafe_ptr(),
            self.saved_stencil.unsafe_ptr(),
            Int32(self.width),
            Int32(self.height),
            grid_dim=grid,
            block_dim=(TILE, TILE),
        )

    def _per_pixel(
        mut self,
        kind: PassKind,
        a: Float32 = 0,
        b: Float32 = 0,
        c: Float32 = 0,
        d: Float32 = 0,
        e: Float32 = 0,
        flag: Int = 0,
    ) raises:
        """Launch `post_pixel_kernel` for one pass."""
        var grid = self._grid()
        self.context.enqueue_function[post_pixel_kernel](
            self.light.unsafe_ptr(),
            self.data.unsafe_ptr(),
            Int32(self.width),
            Int32(self.height),
            Int32(kind.value),
            a,
            b,
            c,
            d,
            e,
            Int32(flag),
            grid_dim=grid,
            block_dim=(TILE, TILE),
        )

    def _blur(mut self, spread: Float32, across: Bool) raises:
        """Blur the frame along one axis."""
        self._take_source()
        var grid = self._grid()
        self.context.enqueue_function[blur_kernel](
            self.light.unsafe_ptr(),
            self.source.unsafe_ptr(),
            Int32(self.width),
            Int32(self.height),
            spread,
            Int32(1 if across else 0),
            grid_dim=grid,
            block_dim=(TILE, TILE),
        )

    def _bloom(
        mut self, strength: Float32, radius: Float32, threshold: Float32
    ) raises:
        """Run `bloom_light`'s stages as kernels: the bright light, five
        levels each blurred across and then down, and the composite."""
        var grid = self._grid()
        self.context.enqueue_function[bright_kernel](
            self.source.unsafe_ptr(),
            self.light.unsafe_ptr(),
            Int32(self.width),
            Int32(self.height),
            threshold,
            grid_dim=grid,
            block_dim=(TILE, TILE),
        )
        var from_pointer = self.source.unsafe_ptr().unsafe_origin_cast[
            MutAnyOrigin
        ]()
        var from_width = self.width
        var from_height = self.height
        var level_width = halved_size(self.width)
        var level_height = halved_size(self.height)
        var start = 0
        for level in range(BLOOM_LEVELS):
            var level_grid = (
                ceildiv(level_width, TILE),
                ceildiv(level_height, TILE),
            )
            var kernel = bloom_kernel(level)
            self.context.enqueue_function[bloom_blur_kernel](
                self.across.unsafe_ptr(),
                from_pointer,
                Int32(from_width),
                Int32(from_height),
                Int32(level_width),
                Int32(level_height),
                Int32(kernel),
                Int32(1),
                grid_dim=level_grid,
                block_dim=(TILE, TILE),
            )
            var to_pointer = (
                self.levels.unsafe_ptr()
                .unsafe_offset(start)
                .unsafe_origin_cast[MutAnyOrigin]()
            )
            self.context.enqueue_function[bloom_blur_kernel](
                to_pointer,
                self.across.unsafe_ptr(),
                Int32(level_width),
                Int32(level_height),
                Int32(level_width),
                Int32(level_height),
                Int32(kernel),
                Int32(0),
                grid_dim=level_grid,
                block_dim=(TILE, TILE),
            )
            from_pointer = to_pointer
            from_width = level_width
            from_height = level_height
            start += level_width * level_height * 4
            level_width = halved_size(level_width)
            level_height = halved_size(level_height)
        self.context.enqueue_function[bloom_composite_kernel](
            self.light.unsafe_ptr(),
            self.levels.unsafe_ptr(),
            Int32(self.width),
            Int32(self.height),
            radius,
            strength,
            grid_dim=grid,
            block_dim=(TILE, TILE),
        )

    def _shader(
        mut self, composer: EffectComposer, index: Int, assets: Assets
    ) raises:
        """Run a shader pass's program over the device frame: its floats,
        bound by `screen_code`, and the saved image after them, in
        `extra`."""
        ref step = composer.passes[index]
        ref program = assets.programs.get(step.shader.program)
        var floats = screen_code(program, step.shader, step.time)
        var saved_start = len(floats)
        var saved_width = 1
        var saved_height = 1
        var saved = List[FloatColor]()
        if step.shader.saved.byte_length() > 0:
            saved = composer.saved_image(step.shader.saved_pass)
        if len(saved) == self.width * self.height:
            saved_width = self.width
            saved_height = self.height
        elif len(saved) != 0:
            raise Error("A saved image must be the frame's size")
        else:
            saved = [FloatColor(0, 0, 0, 0)]
        for slot in range(len(saved)):
            floats.append(saved[slot].r)
            floats.append(saved[slot].g)
            floats.append(saved[slot].b)
            floats.append(saved[slot].a)
        self._put_floats(floats)
        self._take_source()
        self.context.enqueue_function[shader_kernel](
            self.light.unsafe_ptr(),
            self.data.unsafe_ptr(),
            self.source.unsafe_ptr(),
            self.extra.unsafe_ptr(),
            Int32(saved_start),
            Int32(saved_width),
            Int32(saved_height),
            Int32(self.width),
            Int32(self.height),
            grid_dim=self._grid(),
            block_dim=(TILE, TILE),
        )

    def _god_rays(
        mut self, settings: GodRaysSettings, view: DepthView, sun: Vector3
    ) raises:
        """Run the god-rays chain on the device: the mask, the three
        generate passes and the combine, `god_rays_light`'s stages. The
        mask, the two rays images and the combine's settings lie back to
        back in `extra`."""
        var mask = god_rays_mask(view)
        var rays_width = god_rays_size(self.width, settings.resolution_scale)
        var rays_height = god_rays_size(self.height, settings.resolution_scale)
        var mask_floats = len(mask) * 4
        var rays_floats = rays_width * rays_height * 4
        var floats = List[Float32](capacity=mask_floats + rays_floats * 2 + 11)
        for slot in range(len(mask)):
            floats.append(mask[slot].r)
            floats.append(mask[slot].g)
            floats.append(mask[slot].b)
            floats.append(mask[slot].a)
        for _ in range(rays_floats * 2):
            floats.append(0)
        floats.append(sun.x)
        floats.append(sun.y)
        floats.append(sun.z)
        floats.append(settings.intensity)
        floats.append(Float32(1) if settings.fake_sun else Float32(0))
        floats.append(Float32(settings.sun_color.r))
        floats.append(Float32(settings.sun_color.g))
        floats.append(Float32(settings.sun_color.b))
        floats.append(Float32(settings.bg_color.r))
        floats.append(Float32(settings.bg_color.g))
        floats.append(Float32(settings.bg_color.b))
        self._put_floats(floats)
        var base = self.extra.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
        var first = base.unsafe_offset(mask_floats)
        var second = base.unsafe_offset(mask_floats + rays_floats)
        var params = base.unsafe_offset(mask_floats + rays_floats * 2)
        var rays_grid = (
            ceildiv(rays_width, TILE),
            ceildiv(rays_height, TILE),
        )
        # The first pass reads the mask at the frame's size; each pass
        # after it reads the one before, the two images taking turns.
        var from_pointer = base
        var from_width = self.width
        var from_height = self.height
        var to_pointer = first
        var into_first = True
        for index in range(1, GOD_RAYS_PASSES + 1):
            self.context.enqueue_function[god_rays_generate_kernel](
                to_pointer,
                from_pointer,
                Int32(from_width),
                Int32(from_height),
                Int32(rays_width),
                Int32(rays_height),
                sun.x,
                sun.y,
                sun.z,
                god_rays_step(settings.filter_length, index),
                grid_dim=rays_grid,
                block_dim=(TILE, TILE),
            )
            from_pointer = to_pointer
            from_width = rays_width
            from_height = rays_height
            into_first = not into_first
            to_pointer = first if into_first else second
        self.context.enqueue_function[god_rays_combine_kernel](
            self.light.unsafe_ptr(),
            self.data.unsafe_ptr(),
            base,
            from_pointer,
            params,
            Int32(rays_width),
            Int32(rays_height),
            Int32(self.width),
            Int32(self.height),
            grid_dim=self._grid(),
            block_dim=(TILE, TILE),
        )

    def _on_device(self, step: Pass, assets: Assets) raises -> Bool:
        """Return True if a pass runs on the device: `runs_on_device` of
        its kind, less a shader pass whose program reads a texture in the
        assets, which the device does not hold."""
        if not runs_on_device(step.kind):
            return False
        if step.kind != SHADER:
            return True
        return not reads_assets(
            assets.programs.get(step.shader.program), step.shader
        )

    def _run[
        C: Camera
    ](
        mut self,
        mut composer: EffectComposer,
        index: Int,
        frame: RenderTarget,
        renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: C,
        delta_time: Float32,
    ) raises:
        """Run one pass `runs_on_device` says yes to, as
        `EffectComposer.run_step` runs it on the host."""
        var grid = self._grid()
        var kind = composer.passes[index].kind
        var count = self.width * self.height
        if kind == COPY:
            self._per_pixel(COPY, composer.passes[index].strength)
        elif kind == BLUR:
            self._blur(composer.passes[index].radius, True)
            self._blur(composer.passes[index].radius, False)
        elif kind == BLOOM:
            self._bloom(
                composer.passes[index].strength,
                composer.passes[index].radius,
                composer.passes[index].threshold,
            )
        elif kind == FILM:
            composer.passes[index].time += delta_time
            ref step = composer.passes[index]
            self._per_pixel(
                FILM,
                step.strength,
                step.time,
                flag=1 if step.grayscale else 0,
            )
        elif kind == DOT_SCREEN:
            ref step = composer.passes[index]
            self._per_pixel(
                DOT_SCREEN,
                step.center.x,
                step.center.y,
                sin(step.angle.value),
                cos(step.angle.value),
                step.scale,
            )
        elif kind == SEPIA:
            self._per_pixel(SEPIA, composer.passes[index].strength)
        elif kind == VIGNETTE:
            self._per_pixel(
                VIGNETTE,
                composer.passes[index].offset,
                composer.passes[index].strength,
            )
        elif kind == LUMINOSITY:
            self._per_pixel(LUMINOSITY)
        elif kind == AFTERIMAGE:
            # The trail is kept on the host, in the composer, so both
            # backends share it and `reset` forgets it.
            if len(composer.memories[index]) == count:
                self._put_colors(composer.memories[index])
                self.context.enqueue_function[afterimage_kernel](
                    self.light.unsafe_ptr(),
                    self.extra.unsafe_ptr(),
                    Int32(self.width),
                    Int32(self.height),
                    composer.passes[index].strength,
                    grid_dim=grid,
                    block_dim=(TILE, TILE),
                )
            var trail = List[FloatColor](
                length=count, fill=FloatColor(0, 0, 0, 0)
            )
            with self.light.map_to_host() as host:
                unsafe_memcpy(
                    dest=trail.unsafe_ptr().unsafe_bitcast[Float32](),
                    src=host.unsafe_ptr(),
                    count=count * 4,
                )
            composer.memories[index] = trail^
        elif kind == OUTPUT:
            var curve = renderer.tone_curve()
            if curve != NO_TONE_MAPPING:
                self._per_pixel(
                    OUTPUT, renderer.tone_mapping_exposure, flag=curve.value
                )
        elif kind == FXAA:
            self._take_source()
            self.context.enqueue_function[fxaa_kernel](
                self.light.unsafe_ptr(),
                self.source.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == BOKEH:
            var view = depth_view(renderer, scene, assets, camera)
            self._put_floats(view.depth)
            self._take_source()
            ref settings = composer.passes[index].bokeh
            self.context.enqueue_function[bokeh_kernel](
                self.light.unsafe_ptr(),
                self.data.unsafe_ptr(),
                self.source.unsafe_ptr(),
                self.extra.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                view.near,
                view.far,
                settings.focus.value,
                settings.aperture,
                settings.max_blur,
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == GLITCH:
            var uniforms = glitch_uniforms(composer.passes[index].glitch)
            if uniforms.bypass:
                return
            ref glitch = composer.passes[index].glitch
            self._put_floats(glitch_heightmap(glitch.size, glitch.seed))
            self._take_source()
            self.context.enqueue_function[glitch_kernel](
                self.light.unsafe_ptr(),
                self.source.unsafe_ptr(),
                self.extra.unsafe_ptr(),
                Int32(glitch.size),
                Int32(self.width),
                Int32(self.height),
                uniforms.seed,
                uniforms.amount,
                uniforms.seed_x,
                uniforms.seed_y,
                uniforms.distortion_x,
                uniforms.distortion_y,
                uniforms.amount * cos(uniforms.angle.value),
                uniforms.amount * sin(uniforms.angle.value),
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == HALFTONE:
            ref settings = composer.passes[index].halftone
            if settings.disable:
                return
            self._take_source()
            self.context.enqueue_function[halftone_kernel](
                self.light.unsafe_ptr(),
                self.data.unsafe_ptr(),
                self.source.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                Int32(settings.shape.value),
                settings.radius,
                settings.rotate_r.value,
                settings.rotate_g.value,
                settings.rotate_b.value,
                settings.scatter,
                settings.blending,
                Int32(settings.blending_mode.value),
                Int32(1 if settings.grayscale else 0),
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == CLEAR:
            var value = FloatColor(
                srgb=composer.passes[index].clear_color
            ).premultiplied()
            self.context.enqueue_function[clear_kernel](
                self.light.unsafe_ptr(),
                self.data.unsafe_ptr(),
                self.depth.unsafe_ptr(),
                self.stencil.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                value.r,
                value.g,
                value.b,
                value.a,
                cleared_depth(frame.depth_mode),
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == TEXTURE:
            self._put_colors(
                texture_overlay(
                    assets.textures.get(composer.passes[index].texture),
                    self.width,
                    self.height,
                )
            )
            self.context.enqueue_function[texture_kernel](
                self.light.unsafe_ptr(),
                self.data.unsafe_ptr(),
                self.extra.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                composer.passes[index].strength,
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == CUBE_TEXTURE:
            self._put_colors(
                cube_overlay(
                    assets.cube_textures.get(composer.passes[index].cube),
                    camera,
                    scene,
                    self.width,
                    self.height,
                )
            )
            self.context.enqueue_function[texture_kernel](
                self.light.unsafe_ptr(),
                self.data.unsafe_ptr(),
                self.extra.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                composer.passes[index].strength,
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == SAVE:
            # The copy is kept on the host, in the composer, so both
            # backends share it, as the afterimage's trail is kept.
            var kept = List[FloatColor](
                length=count, fill=FloatColor(0, 0, 0, 0)
            )
            with self.light.map_to_host() as host:
                unsafe_memcpy(
                    dest=kept.unsafe_ptr().unsafe_bitcast[Float32](),
                    src=host.unsafe_ptr(),
                    count=count * 4,
                )
            composer.memories[index] = kept^
        elif kind == SHADER:
            composer.passes[index].time += delta_time
            self._shader(composer, index, assets)
        elif kind == SHADER_EFFECT:
            self._put_floats(effect_floats(composer.passes[index].effect))
            self._take_source()
            self.context.enqueue_function[effect_kernel](
                self.light.unsafe_ptr(),
                self.data.unsafe_ptr(),
                self.source.unsafe_ptr(),
                self.extra.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )
        elif kind == GOD_RAYS:
            self._god_rays(
                composer.passes[index].god_rays,
                depth_view(renderer, scene, assets, camera),
                sun_on_screen(
                    camera, scene, composer.passes[index].god_rays.sun
                ),
            )
        else:
            # `LUT`: the last kind `runs_on_device` says yes to.
            ref lut = assets.data_3d_textures.get(composer.passes[index].lut)
            lut.validate()
            self._put_colors(decoded_texels(lut))
            self.context.enqueue_function[lut_kernel](
                self.light.unsafe_ptr(),
                self.extra.unsafe_ptr(),
                Int32(self.width),
                Int32(self.height),
                Int32(lut.image.width),
                Int32(lut.image.height),
                Int32(lut.image.depth),
                Int32(lut.wrap_s.value),
                Int32(lut.wrap_t.value),
                Int32(lut.wrap_r.value),
                Int32(lut.filter.value),
                composer.passes[index].strength,
                grid_dim=grid,
                block_dim=(TILE, TILE),
            )

    def render[
        C: Camera
    ](
        mut self,
        mut composer: EffectComposer,
        renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: C,
        delta_time: Float32 = 0.0,
    ) raises -> Framebuffer:
        """Run every enabled pass of `composer` in order on one frame and
        return it: `EffectComposer.render`, with the frame on the device.

        The frame starts cleared to the renderer's background, on the
        host, and goes up once. Each pass then runs on the device, or on
        the host through a round trip; see `runs_on_device`. A mask works
        as on the host: the frame is copied aside on the device before a
        pass inside it and put back outside it after. The frame comes back
        once at the end and is resolved through no curve, as the host
        composer resolves it.

        Args:
            composer: The passes, and what the afterimage and TAA passes
                keep between frames.
            renderer: What a render pass draws with, and whose size,
                background, workers and curve the frame takes.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera a render pass projects through.
            delta_time: How many seconds since the last frame.

        Returns:
            The rendered image.

        Raises:
            Error: Everything `EffectComposer.render` raises, if the
                renderer is not this composer's size, or if a device
                buffer cannot be read or written.
        """
        check_frame_time(delta_time)
        if renderer.width != self.width or renderer.height != self.height:
            raise Error("A GPU composer must be the renderer's size")
        # A pass appended to or popped from the open list gets or drops
        # its memory before an afterimage pass reads one, as on the host.
        composer.fit_memories()
        # The frame carries the normal attachment the host composer's
        # frame carries. The normals stay on the host: only a render
        # writes them and only a screen-space pass reads them, and both
        # run on the host frame, which `download` and `upload` leave them
        # in.
        var frame = RenderTarget(
            self.width,
            self.height,
            renderer.background,
            outputs=frame_outputs(composer.passes),
        )
        self.upload(frame)
        self.round_trips = 0
        var mask_active = False
        for index in range(composer.pass_count()):
            check_pass(composer.passes[index])
            if not composer.passes[index].enabled:
                continue
            var kind = composer.passes[index].kind
            if kind == CLEAR_MASK:
                mask_active = False
                continue
            var masked = mask_active and kind != MASK
            if masked:
                self._save()
            if self._on_device(composer.passes[index], assets):
                # The device frame keeps its data pixels straight, as the
                # host frame does, and premultiplies them around a pass
                # that reads light, as `EffectComposer.run_step` does.
                var wraps = reads_frame_as_light(kind)
                if wraps:
                    self._data_alpha(True)
                self._run(
                    composer,
                    index,
                    frame,
                    renderer,
                    scene,
                    assets,
                    camera,
                    delta_time,
                )
                if wraps:
                    self._data_alpha(False)
            else:
                self.download(frame)
                composer.run_step(
                    index, frame, renderer, scene, assets, camera, delta_time
                )
                self.upload(frame)
                self.round_trips += 1
            if kind == MASK:
                mask_active = True
            elif masked:
                self._keep_outside_mask()
        self.download(frame)
        return frame.resolve(renderer.workers, NO_TONE_MAPPING, 1.0)
