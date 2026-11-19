# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Host-side vertex, light, texture, volume and tile-bin packing for the GPU.

Contains standard-library-only layout constants, buffer packers and tile
binning (`bin_triangles`, `flatten`, `flatten_textures`, `flatten_lights`,
`volume_blocks` and state tables), shared by `render.gpu` without importing
`max.gpu`. Every symbol is re-exported by `render.gpu`.
"""

from core.extent import positive_extent
from core.fog import FogView
from lights.light_probe_grid import GRID_HEADER
from lights.lighting import Lighting
from lights.ltc import LTC_FLOATS
from lights.shadow import NODE_BLEND, SHADOW_HEADER, SPOT_MAP_FLOATS
from materials.node_program import NodeProgramStore
from materials.nodes import NO_NODES
from math.spherical_harmonics3 import SH_COUNT
from render.color_spaces import OUTPUT_FLOATS, OutputEncoding
from render.cube_texture import Basis3, FACE_COUNT
from render.cube_texture_store import (
    CubeTextureId,
    CubeTextureStore,
    NO_CUBE_TEXTURE,
)
from render.fillrule import SUBPIXEL, snap
from render.framebuffer import Color, FloatColor
from render.rasterizer import Corner, RasterVertex, Surface, joined
from render.tasks import TaskGroup
from render.texture import (
    COVERAGE,
    FLOAT_TYPE,
    Mapping,
    Texture,
    UNSIGNED_BYTE_TYPE,
    plan_levels,
)
from render.texture_store import TextureId, TextureStore
from render.transmission import TransmissionTarget, VIEW_FLOATS
from render.volume_texture import decoded_layers, decoded_texels
from render.volume_texture_store import (
    Data3DTextureStore,
    DataArrayTextureStore,
)
from renderers.renderer import Frame
from std.math import ceildiv, isfinite
from std.memory import bitcast
from std.sys import has_accelerator, num_logical_cores
from units.si import METER


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
# The constant color the constant blend factors read, three.js's
# `blendColor` and `blendAlpha`: `RasterState.blend_constant`, four floats.
comptime LANE_BLEND_CONSTANT = LANE_OBJECT_NORMAL + 9
# The custom attributes a node program reads: `RasterVertex.custom`.
comptime LANE_CUSTOM = LANE_BLEND_CONSTANT + 4
# A `GOURAUD` corner's direct and indirect light, three floats each:
# `RasterVertex.gouraud_direct` and `gouraud_indirect`.
comptime LANE_GOURAUD_DIRECT = LANE_CUSTOM + 8
comptime LANE_GOURAUD_INDIRECT = LANE_GOURAUD_DIRECT + 3
# A `PHONG` triangle's light through from behind: its color, then its
# distortion, ambient, attenuation, power and scale; see
# `RasterVertex.scatter_color`.
comptime LANE_SCATTER = LANE_GOURAUD_INDIRECT + 3
# Where this frame and the last had the corner in clip space, three floats
# each: `RasterVertex.current` and `RasterVertex.previous`, which a
# velocity attachment reads.
comptime LANE_CURRENT = LANE_SCATTER + 8
comptime LANE_PREVIOUS = LANE_CURRENT + 3
# A `VOLUME` triangle's ray: its steps, bounding radius in world space,
# and explicit scene-depth switch; see `RasterVertex.steps`.
comptime LANE_VOLUME = LANE_PREVIOUS + 3
comptime FLOATS_PER_VERTEX = LANE_VOLUME + 3
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
# Where the segment's node program starts in the fog buffer, or -1 for
# none; see `program_starts`.
comptime LINE_STATE_NODES = 5
comptime STATE_PER_LINE = LINE_STATE_NODES + 1
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
# Where the point's node program starts in the fog buffer, or -1 for none;
# see `program_starts`.
comptime POINT_STATE_NODES = 6
comptime STATE_PER_POINT = POINT_STATE_NODES + 1
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
# The triangle's facing: one if it is seen from its back, plus two if its
# material is `BACK_SIDE`; see `RasterVertex.seen_from_behind`.
comptime STATE_FACING = STATE_NORMAL_MAP_TYPE + 1
# Which texture's red is a `PHONG` triangle's thickness, or `NO_TEXTURE`
# for none; see `RasterVertex.scatter_map`.
comptime STATE_SCATTER_MAP = STATE_FACING + 1
# Where the triangle's light block starts in the light buffer: zero for
# the frame's own lights; see `flatten_frame_lights`.
comptime STATE_LIGHTS = STATE_SCATTER_MAP + 1
comptime STATE_PER_TRIANGLE = STATE_LIGHTS + 1
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
# Relative float offset of immutable volume depth, or zero when absent.
comptime TRANSMISSION_DEPTH = VIEW_FLOATS + 3
comptime TRANSMISSION_HEADER = VIEW_FLOATS + 4

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
# Where the custom tone mapping curve's program starts in the fog buffer,
# or -1 for none: the kernel has no argument left for it. See
# `render.tonemap.custom_tone_map`.
comptime FOG_TONE_PROGRAM = 6
# Where the output color space's encoding starts, `OUTPUT_FLOATS` floats:
# three.js's `outputColorSpace`. See `render.color_spaces.OutputEncoding`.
comptime FOG_OUTPUT = 7
comptime FOG_FLOATS = FOG_OUTPUT + OUTPUT_FLOATS

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
# How many directional, point, hemisphere and spot lights the block holds:
# what a triangle lit by a block of its own reads in place of the kernel's
# arguments. See `flatten_frame_lights`.
comptime LIGHTS_COUNTS = LIGHTS_BACK + 3
# Where the probe grid's block begins in this same buffer, or `NO_SHADOW`
# for none: `LightProbeGrid.flatten`, after the spot profiles. See
# `lights.light_probe_grid`.
comptime LIGHTS_GRID = LIGHTS_COUNTS + 4
comptime LIGHTS_FIRST = LIGHTS_GRID + 1
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
# The velocity of the nearest opaque surface, two floats a pixel, zero
# where none was written.
comptime PLANE_VELOCITY = PLANE_DATA + 1
# The metalness and roughness of the nearest opaque surface, two floats a
# pixel, zero where none was written.
comptime PLANE_METAL_ROUGH = PLANE_VELOCITY + 2
# How many floats a pixel takes across every plane.
comptime PLANE_FLOATS = PLANE_METAL_ROUGH + 2
# How many floats each kind of light takes in the buffer. A directional
# light's seventh, a point light's ninth and a spot light's fourteenth is
# where its shadow map begins in the same buffer, or -1 for none. A
# directional light's last eight are its `ShadowCascade`: its start, its
# end, its span in meters, zero for no cascade, whether it is the last
# and whether it fades, as one or zero, its `CascadeBlend`, and under
# `SUN_BLEND` its fade start and where the cascade before it ends. Under
# `NODE_BLEND` the first of those two is its near plane over its span. The maps
# ride after the lights, each `SHADOW_HEADER` floats and then its depths,
# rather than in a buffer of their own, because Metal binds at most
# thirty-one arguments to a kernel and this one has thirty-one. A spot
# light's fifteenth is where its map's `SPOT_MAP_FLOATS` begin, after the
# shadow maps, or -1 for none.
comptime DIRECTIONAL_FLOATS = 15
# Where a directional light's cascade begins in its record.
comptime CASCADE_AT = 7
comptime POINT_FLOATS = 9
comptime HEMISPHERE_FLOATS = 9
comptime SPOT_FLOATS = 16
# A spot light's sixteenth float is where its `SpotProfile` begins, after
# the spot light maps, or -1 for a cone: its `SpotShape`, the IES
# profile's slot in the texture table or -1, and the sixteen-float frame.
# See `lights.spot_profile`.
comptime SPOT_PROFILE_FLOATS = 18
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
# How many floats begin a decoded 3D or array texture's block in the fog
# buffer: its width, height, depth, three wrap modes and filter, and one
# spare; see `volume_blocks`.
comptime VOLUME_HEADER = 8
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


def require_gpu() raises:
    """Refuse a launch when this machine has no GPU.

    Nothing. The call returns when a GPU is present.

    Raises:
        Error: If no GPU is present.
    """
    if not available():
        raise Error("No GPU available")


def require_volume_address(used: Int, size: Int) raises:
    """Refuse a volume block that cannot be addressed as an Int32.

    Nothing. The call returns when the block fits.

    Args:
        used: How many floats are already stored.
        size: How many floats the next block adds.

    Raises:
        Error: If the block exceeds Int32 addressing.
    """
    if used > 2147483647 - size:
        raise Error("GPU volume blocks must fit Int32 addressing")


def require_composer_frame(
    width: Int, height: Int, frame_width: Int, frame_height: Int
) raises:
    """Refuse a composer frame that is not the composer's size.

    Nothing. The call returns when the sizes match.

    Args:
        width: The composer's width in pixels.
        height: The composer's height in pixels.
        frame_width: The frame's width in pixels.
        frame_height: The frame's height in pixels.

    Raises:
        Error: If the frame is another size.
    """
    if frame_width != width or frame_height != height:
        raise Error("A GPU composer's frame must be its own size")


def flatten(corners: List[RasterVertex]) -> List[Float32]:
    """Return `corners` as the flat float buffer the kernel reads.

    Args:
        corners: Raster vertices, three per triangle.

    Returns:
        `FLOATS_PER_VERTEX` floats per vertex, in the order the kernel
        unpacks them.
    """
    var flat = List[Float32](length=len(corners) * FLOATS_PER_VERTEX, fill=0)
    var dest = flat.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    for index in range(len(corners)):
        _write_corner(dest, index * FLOATS_PER_VERTEX, corners[index])
    return flat^


def flatten_into(
    corners: List[RasterVertex],
    dest: MutPointer[Float32, MutAnyOrigin],
    workers: Int,
):
    """Write `corners` to `dest` as `flatten` lays them out, on `workers`
    threads.

    The upload writes straight into the device buffer's host mapping, so
    a frame of strand hair does not build its gigabytes twice. Each worker
    owns a run of whole vertices, so no two write the same float.

    Args:
        corners: Raster vertices, three per triangle.
        dest: Room for `FLOATS_PER_VERTEX` floats per vertex.
        workers: How many threads to use; one or fewer writes on the
            calling thread.
    """
    var count = len(corners)
    var bands = min(max(1, workers), max(1, count // _FLATTEN_GRAIN))
    if bands == 1:
        for index in range(count):
            _write_corner(dest, index * FLOATS_PER_VERTEX, corners[index])
        return
    var source = corners.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var group = TaskGroup()
    for band in range(bands):
        group.create_task(
            _flatten_band(
                source,
                dest,
                band * count // bands,
                (band + 1) * count // bands,
            )
        )
    group.wait()
    # The tasks read the corners through a pointer the compiler cannot
    # see; this read keeps the list alive until every band has finished.
    _ = len(corners)


def join_corners(frame: Frame, workers: Int = 0) -> List[RasterVertex]:
    """Return a frame's triangle corners whole, as `Frame.whole_corners` does,
    joined on `workers` threads.

    A frame of strand hair has millions of corners, and `draw` takes them
    whole. Each worker writes its own run of the list.

    Args:
        frame: What `Renderer.prepare_frame` returned.
        workers: How many threads to join on; zero or fewer means one for
            each logical core.

    Returns:
        Each corner joined to its surface, in the frame's order.
    """
    var count = len(frame.corners)
    var whole = List[RasterVertex]()
    # Every slot is written below. A vertex holds no heap storage, so
    # writing over an unset slot runs no destructor that matters.
    whole.resize(unsafe_uninit_length=count)
    var threads = workers if workers > 0 else num_logical_cores()
    var bands = min(threads, max(1, count // _FLATTEN_GRAIN))
    var group = TaskGroup()
    for band in range(bands):
        group.create_task(
            _join_band(
                frame.corners.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
                frame.surfaces.unsafe_ptr().unsafe_origin_cast[
                    ImmutAnyOrigin
                ](),
                whole.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                band * count // bands,
                (band + 1) * count // bands,
            )
        )
    group.wait()
    # The tasks read the frame through pointers the compiler cannot see;
    # this read keeps it alive until every band has finished.
    _ = len(frame.corners)
    return whole^


__async def _join_band(
    corners: Pointer[Corner, ImmutAnyOrigin],
    surfaces: Pointer[Surface, ImmutAnyOrigin],
    whole: MutPointer[RasterVertex, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Join corners `first` to `past` of `join_corners`'s frame to their
    surfaces, into `whole`."""
    for index in range(first, past):
        ref corner = corners[unsafe_offset=index]
        whole[unsafe_offset=index] = joined(
            corner, surfaces[unsafe_offset=corner.surface]
        )


# The fewest vertices a flatten worker takes: below this, starting a task
# costs more than the copy it saves.
comptime _FLATTEN_GRAIN = 4096


__async def _flatten_band(
    corners: Pointer[RasterVertex, ImmutAnyOrigin],
    dest: MutPointer[Float32, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Write vertices `first` to `past` of `flatten_into`'s corners."""
    for index in range(first, past):
        _write_corner(
            dest, index * FLOATS_PER_VERTEX, corners[unsafe_offset=index]
        )


@always_inline
def _put(dest: MutPointer[Float32, MutAnyOrigin], mut at: Int, value: Float32):
    """Write one lane and move to the next."""
    dest[unsafe_offset=at] = value
    at += 1


def _put_basis(
    dest: MutPointer[Float32, MutAnyOrigin], mut at: Int, basis: Basis3
):
    """Write a 3x3 matrix's nine numbers in `Basis3`'s order."""
    _put(dest, at, basis.e0)
    _put(dest, at, basis.e1)
    _put(dest, at, basis.e2)
    _put(dest, at, basis.e3)
    _put(dest, at, basis.e4)
    _put(dest, at, basis.e5)
    _put(dest, at, basis.e6)
    _put(dest, at, basis.e7)
    _put(dest, at, basis.e8)


def _write_corner(
    dest: MutPointer[Float32, MutAnyOrigin], start: Int, corner: RasterVertex
):
    """Write one vertex's `FLOATS_PER_VERTEX` lanes from `start`, in the
    order the kernel unpacks them. `flatten` and `flatten_into` share it,
    so the two layouts cannot differ."""
    var at = start
    _put(dest, at, corner.x)
    _put(dest, at, corner.y)
    _put(dest, at, corner.z)
    _put(dest, at, corner.inv_w)
    _put(dest, at, corner.color.r)
    _put(dest, at, corner.color.g)
    _put(dest, at, corner.color.b)
    _put(dest, at, corner.color.a)
    _put(dest, at, corner.u)
    _put(dest, at, corner.v)
    _put(dest, at, corner.normal.x)
    _put(dest, at, corner.normal.y)
    _put(dest, at, corner.normal.z)
    _put(dest, at, corner.world.x)
    _put(dest, at, corner.world.y)
    _put(dest, at, corner.world.z)
    _put(dest, at, corner.emissive.r)
    _put(dest, at, corner.emissive.g)
    _put(dest, at, corner.emissive.b)
    _put(dest, at, corner.view_depth)
    _put(dest, at, corner.alpha_test)
    _put(dest, at, corner.specular.r)
    _put(dest, at, corner.specular.g)
    _put(dest, at, corner.specular.b)
    _put(dest, at, corner.shininess)
    _put(dest, at, corner.line_distance)
    _put(dest, at, corner.dash_size)
    _put(dest, at, corner.gap_size)
    _put(dest, at, corner.point_size)
    _put(dest, at, corner.reflectivity)
    _put(dest, at, corner.roughness)
    _put(dest, at, corner.metalness)
    _put(dest, at, corner.env_map_intensity)
    _put(dest, at, corner.specular_intensity)
    _put(dest, at, corner.clearcoat)
    _put(dest, at, corner.clearcoat_roughness)
    _put(dest, at, corner.normal_scale.x)
    _put(dest, at, corner.normal_scale.y)
    _put(dest, at, corner.bump_scale)
    _put(dest, at, corner.u1)
    _put(dest, at, corner.v1)
    _put(dest, at, corner.ao_map_intensity)
    _put(dest, at, corner.light_map_intensity)
    _put(dest, at, corner.state.log_depth_scale)
    _put(dest, at, corner.transmission)
    _put(dest, at, corner.thickness.x)
    _put(dest, at, corner.thickness.y)
    _put(dest, at, corner.thickness.z)
    _put(dest, at, corner.attenuation_color.r)
    _put(dest, at, corner.attenuation_color.g)
    _put(dest, at, corner.attenuation_color.b)
    _put(dest, at, corner.attenuation_distance)
    _put(dest, at, corner.dispersion)
    _put(dest, at, corner.ior)
    _put(dest, at, corner.reference.x)
    _put(dest, at, corner.reference.y)
    _put(dest, at, corner.reference.z)
    _put(dest, at, corner.near_distance)
    _put(dest, at, corner.far_distance)
    _put(dest, at, corner.layers.sheen_color.x)
    _put(dest, at, corner.layers.sheen_color.y)
    _put(dest, at, corner.layers.sheen_color.z)
    _put(dest, at, corner.layers.sheen_roughness)
    _put(dest, at, corner.layers.iridescence)
    _put(dest, at, corner.layers.iridescence_ior)
    _put(dest, at, corner.layers.thickness_minimum)
    _put(dest, at, corner.layers.thickness_maximum)
    _put(dest, at, corner.layers.anisotropy.x)
    _put(dest, at, corner.layers.anisotropy.y)
    _put(dest, at, corner.layers.specular_color.x)
    _put(dest, at, corner.layers.specular_color.y)
    _put(dest, at, corner.layers.specular_color.z)
    _put(dest, at, corner.layers.clearcoat_normal_scale.x)
    _put(dest, at, corner.layers.clearcoat_normal_scale.y)
    _put_basis(dest, at, corner.frames.env_rotation)
    _put(dest, at, corner.frames.refraction_ratio)
    _put_basis(dest, at, corner.frames.object_normal)
    _put(dest, at, corner.state.blend_red)
    _put(dest, at, corner.state.blend_green)
    _put(dest, at, corner.state.blend_blue)
    _put(dest, at, corner.state.blend_alpha)
    for lane in range(8):
        _put(dest, at, corner.custom[lane])
    _put(dest, at, corner.gouraud_direct.x)
    _put(dest, at, corner.gouraud_direct.y)
    _put(dest, at, corner.gouraud_direct.z)
    _put(dest, at, corner.gouraud_indirect.x)
    _put(dest, at, corner.gouraud_indirect.y)
    _put(dest, at, corner.gouraud_indirect.z)
    _put(dest, at, corner.scatter_color.r)
    _put(dest, at, corner.scatter_color.g)
    _put(dest, at, corner.scatter_color.b)
    _put(dest, at, corner.scatter_distortion)
    _put(dest, at, corner.scatter_ambient)
    _put(dest, at, corner.scatter_attenuation)
    _put(dest, at, corner.scatter_power)
    _put(dest, at, corner.scatter_scale)
    _put(dest, at, corner.current.x)
    _put(dest, at, corner.current.y)
    _put(dest, at, corner.current.z)
    _put(dest, at, corner.previous.x)
    _put(dest, at, corner.previous.y)
    _put(dest, at, corner.previous.z)
    _put(dest, at, Float32(corner.steps))
    _put(dest, at, corner.model_radius)
    _put(dest, at, Float32(1) if corner.volume_scene_depth else Float32(0))


@always_inline
def _append_float(mut bytes: List[UInt8], value: Float32):
    """Append one float as four little-endian bytes, what `_float_at`
    reads back on the device."""
    var bits = bitcast[DType.uint32](value)
    bytes.append(UInt8(bits & 0xFF))
    bytes.append(UInt8((bits >> 8) & 0xFF))
    bytes.append(UInt8((bits >> 16) & 0xFF))
    bytes.append(UInt8(bits >> 24))


def flatten_transmission(target: TransmissionTarget) raises -> List[UInt8]:
    """Return a transmission target as the bytes that follow the backdrop.

    Args:
        target: The opaque scene, built.

    Returns:
        `TRANSMISSION_HEADER` floats -- the matrix, the width, the height
        and level count, plus the relative float offset of volume depth
        or zero when absent. The color chain comes first, then immutable
        camera-axis depth samples, each four little-endian bytes.

    Raises:
        Error: If the depth offset cannot be represented exactly.
    """
    var bytes = List[UInt8]()
    for index in range(VIEW_FLOATS):  # pragma: no branch
        _append_float(bytes, target.view[index])
    _append_float(bytes, Float32(target.image.width))
    _append_float(bytes, Float32(target.image.height))
    _append_float(bytes, Float32(target.image.levels))
    var depth_offset = Float32(0)
    if len(target.volume_depth) > 0:
        depth_offset = _packed_offset(
            TRANSMISSION_HEADER, len(target.image.data)
        )
    _append_float(bytes, depth_offset)
    for index in range(len(target.image.data)):
        _append_float(bytes, target.image.data[index])
    for index in range(len(target.volume_depth)):
        _append_float(bytes, target.volume_depth[index])
    return bytes^


def flatten_lights(lighting: Lighting) -> List[Float32]:
    """Return a scene's lights as the flat float buffer the kernel reads.

    Three floats of camera position, three of the one direction toward it
    under a parallel projection, three of the camera's own up axis, then
    three of ambient, one of `Lighting.scale`, one of how many rect area
    lights there are, 27 of the light probes' coefficients, three of the
    camera's back axis, four of how many directional, point, hemisphere
    and spot lights there are, then fifteen per
    directional light -- a unit
    direction, the light it carries, its shadow and its cascade -- then
    nine per point light: where
    it is, the light it carries, its decay, its cutoff and its shadow. Then
    nine per
    hemisphere light: which way the sky is, what the sky carries and what
    the ground carries. Then sixteen per spot light: where it is, which way
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
    sixteen-float frame; see `lights.shadow.SpotLightMap`. Each spot light
    carries a sixteenth float: where its `SpotProfile` begins, or
    `NO_SHADOW` for a cone. The profiles follow the spot light maps, each
    its shape, the IES profile's slot and the frame; see
    `lights.spot_profile`. The probe grid follows them, as
    `LightProbeGrid.flatten` lays it out, and the header's `LIGHTS_GRID`
    says where it begins.

    Returns:
        `LIGHTS_FIRST + 15 * count + 9 * point_count + 9 * hemisphere_count
        + 16 * spot_count + 12 * rect_count` floats, then the two LTC
        tables when `rect_count` is not zero, then the shadow maps, then
        the spot light maps, then the spot profiles, then the probe
        grid.
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
        next += (
            SHADOW_HEADER
            + len(lighting.shadows[slot].depths)
            + len(lighting.shadows[slot].colors)
        )
    var map_starts = List[Int]()
    for _ in range(len(lighting.spot_maps)):
        map_starts.append(next)
        next += SPOT_MAP_FLOATS
    var profile_starts = List[Int]()
    for _ in range(len(lighting.spot_profiles)):
        profile_starts.append(next)
        next += SPOT_PROFILE_FLOATS
    var grid_start = NO_SHADOW
    if not lighting.grid.is_empty():
        grid_start = Float32(next)
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
    flat.append(Float32(lighting.count()))
    flat.append(Float32(lighting.point_count()))
    flat.append(Float32(lighting.hemisphere_count()))
    flat.append(Float32(lighting.spot_count()))
    flat.append(grid_start)
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
        flat.append(Float32(band.blend.value))
        # `fade_start` is a sun's alone and `near` a shadow node's alone,
        # so the two share a float.
        if band.blend == NODE_BLEND:
            flat.append(band.near)
        else:
            flat.append(band.fade_start)
        flat.append(band.ramp_end)
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
        flat.append(
            _shadow_start(profile_starts, lighting.spot_profile_slots[index])
        )
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
        # Where the colors start, past the depths, or zero for none.
        flat.append(
            Float32(SHADOW_HEADER + len(map.depths)) if len(map.colors)
            > 0 else 0
        )
        for texel in range(len(map.depths)):
            flat.append(map.depths[texel])
        for element in range(len(map.colors)):
            flat.append(map.colors[element])
    for slot in range(len(lighting.spot_maps)):
        ref picture = lighting.spot_maps[slot]
        flat.append(Float32(picture.texture.value))
        flat.append(picture.normal_bias)
        for element in range(16):  # pragma: no branch
            flat.append(picture.frame[element])
    for slot in range(len(lighting.spot_profiles)):
        ref profile = lighting.spot_profiles[slot]
        flat.append(Float32(profile.shape.value))
        flat.append(Float32(profile.texture.value))
        for element in range(16):  # pragma: no branch
            flat.append(profile.frame[element])
    flat.extend(lighting.grid.flatten())
    return flat^


def _shadow_start(starts: List[Int], slot: Int) -> Float32:
    """Return where a light's shadow map begins in the buffer, or
    `NO_SHADOW` for a light that drew none."""
    if slot < 0:
        return NO_SHADOW
    return Float32(starts[slot])


def flatten_fog(
    fog: FogView,
    curve_start: Int = -1,
    output: OutputEncoding = OutputEncoding(),
) -> List[Float32]:
    """Return a fog view as the flat float buffer the kernel reads.

    Args:
        fog: The scene's fog, as the rasterizers take it.
        curve_start: Where the custom tone mapping curve's program starts
            in the fog buffer, or -1, the default, for none.
        output: How the kernel writes light out; sRGB by default.

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
    flat.append(Float32(curve_start))
    flat.extend(output.flatten())
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


def _packed_index(value: Int) raises -> Float32:
    """Encode an address or extent without rounding its integer value."""
    if value < 0 or value > 2147483647:
        raise Error("A GPU packed index must fit a nonnegative Int32")
    var packed = Float32(value)
    if Int(packed) != value:
        raise Error(
            "A GPU packed index must be exactly representable as Float32"
        )
    return packed


def _packed_offset(base: Int, offset: Int) raises -> Float32:
    """Encode a combined buffer offset after checking addition bounds."""
    if (
        base < 0
        or offset < 0
        or base > 2147483647
        or offset > 2147483647 - base
    ):
        raise Error("A GPU packed offset must fit a nonnegative Int32")
    return _packed_index(base + offset)


def _volume_block_size(width: Int, height: Int, depth: Int) raises -> Int:
    """Check the header and block size before decoding a volume."""
    if not positive_extent(width, height, depth):
        raise Error("A GPU volume needs positive dimensions")
    _ = _packed_index(width)
    _ = _packed_index(height)
    _ = _packed_index(depth)
    var limit = (2147483647 - VOLUME_HEADER) // 4
    if width > limit // height // depth:
        raise Error("A GPU volume block must fit Int32 addressing")
    return VOLUME_HEADER + width * height * depth * 4


def volume_blocks(
    volumes: Data3DTextureStore, arrays: DataArrayTextureStore
) raises -> Tuple[List[Float32], List[Int], List[Int]]:
    """Return every 3D and array texture decoded, each a block of
    `VOLUME_HEADER` floats -- width, height, depth, the three wrap modes
    and the filter -- and then its texels, four floats each; and where each
    3D and each array texture's block starts.

    Args:
        volumes: The 3D textures.
        arrays: The array textures.

    Returns:
        The floats, the 3D textures' starts and the array textures'.

    Raises:
        Error: If a texture is invalid, a dimension cannot be stored
            exactly in its Float32 header, or a block exceeds Int32 addressing.
    """
    var floats = List[Float32]()
    var volume_starts = List[Int]()
    var array_starts = List[Int]()
    for index in range(volumes.count()):
        ref volume = volumes.textures[index]
        var size = _volume_block_size(
            volume.image.width, volume.image.height, volume.image.depth
        )
        require_volume_address(len(floats), size)
        volume.validate()
        volume_starts.append(len(floats))
        _append_block(
            floats,
            volume.image.width,
            volume.image.height,
            volume.image.depth,
            volume.wrap_s.value,
            volume.wrap_t.value,
            volume.wrap_r.value,
            volume.filter.value,
            decoded_texels(volume),
        )
    for index in range(arrays.count()):
        ref array = arrays.textures[index]
        var size = _volume_block_size(
            array.image.width, array.image.height, array.image.depth
        )
        require_volume_address(len(floats), size)
        array.validate()
        array_starts.append(len(floats))
        _append_block(
            floats,
            array.image.width,
            array.image.height,
            array.image.depth,
            array.wrap_s.value,
            array.wrap_t.value,
            0,
            array.filter.value,
            decoded_layers(array),
        )
    return (floats^, volume_starts^, array_starts^)


def _append_block(
    mut floats: List[Float32],
    width: Int,
    height: Int,
    depth: Int,
    wrap_s: Int,
    wrap_t: Int,
    wrap_r: Int,
    filter: Int,
    texels: List[FloatColor],
) raises:
    """Append one decoded texture's exact header and texels."""
    var w = _packed_index(width)
    var h = _packed_index(height)
    var d = _packed_index(depth)
    floats.append(w)
    floats.append(h)
    floats.append(d)
    floats.append(Float32(wrap_s))
    floats.append(Float32(wrap_t))
    floats.append(Float32(wrap_r))
    floats.append(Float32(filter))
    floats.append(0)
    for index in range(len(texels)):
        floats.append(texels[index].r)
        floats.append(texels[index].g)
        floats.append(texels[index].b)
        floats.append(texels[index].a)


def flatten_programs(
    programs: NodeProgramStore,
    cube_base: Int = 0,
    blocks_base: Int = 0,
    volume_starts: List[Int] = List[Int](),
    array_starts: List[Int] = List[Int](),
) raises -> List[Float32]:
    """Return every node program's floats end to end, as they follow the
    fog in the fog buffer.

    Args:
        programs: The store to flatten.
        cube_base: The texture table's row of the first cube's first face:
            how many flat textures were uploaded before the cubes.
        blocks_base: Where the decoded 3D and array textures start in the
            fog buffer, after every program.
        volume_starts: Where each 3D texture's block starts, from
            `blocks_base`; see `volume_blocks`.
        array_starts: Where each array texture's block starts, the same.

    Returns:
        The floats, in id order.

    Raises:
        Error: If a remapped texture address cannot be stored exactly
            as a nonnegative Int32 value in a Float32 slot.
    """
    var flat = List[Float32]()
    for index in range(programs.count()):
        var start = len(flat)
        ref program = programs.programs[index]
        flat.extend(program.code.copy())
        # A cube read keeps its cube's first row in the texture table on
        # the device, where the host keeps its id, and a 3D or an array
        # texture read where its block starts in the fog buffer.
        for at in range(len(program.cube_offsets)):
            var cube = Int(program.code[program.cube_offsets[at]])
            if cube >= 0:
                if cube > 2147483647 // CUBE_ROWS:
                    raise Error("A GPU cube row must fit Int32 addressing")
                flat[start + program.cube_offsets[at]] = _packed_offset(
                    cube_base, cube * CUBE_ROWS
                )
        for at in range(len(program.volume_offsets)):
            var volume = Int(program.code[program.volume_offsets[at]])
            if volume >= 0 and volume < len(volume_starts):
                flat[start + program.volume_offsets[at]] = _packed_offset(
                    blocks_base, volume_starts[volume]
                )
        for at in range(len(program.array_offsets)):
            var array = Int(program.code[program.array_offsets[at]])
            if array >= 0 and array < len(array_starts):
                flat[start + program.array_offsets[at]] = _packed_offset(
                    blocks_base, array_starts[array]
                )
    return flat^


def line_state(
    corners: List[RasterVertex],
    line_width: Int = 1,
    starts: List[Int] = List[Int](),
) -> List[Int32]:
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
        starts: Where each node program starts in the fog buffer, as
            `program_starts` lays them out. A segment naming a program
            past it, as `GpuRenderer.draw` refuses, gets -1.

    Returns:
        The blend policy, the width, then the packed depth, color and
        stencil state, then one or zero for whether the fog veils it, then
        where its node program starts or -1, per segment, from its first
        end.
    """
    var state = List[Int32]()
    for segment in range(len(corners) // 2):
        state.append(Int32(corners[segment * 2].blend.value))
        state.append(Int32(line_width))
        state.append(Int32(corners[segment * 2].state.ops_word()))
        state.append(Int32(corners[segment * 2].state.stencil_word()))
        state.append(Int32(1 if corners[segment * 2].fog else 0))
        var named = corners[segment * 2].nodes.value
        state.append(
            Int32(starts[named] if named >= 0 and named < len(starts) else -1)
        )
    return state^


def point_state(
    points: List[RasterVertex], starts: List[Int] = List[Int]()
) -> List[Int32]:
    """Return each point's texture, blend policy and alpha map,
    `STATE_PER_POINT` entries each.

    A table rather than three lanes, for the reason the triangles' is: a
    resource id crossed as a float loses exactness, and a policy that
    decides whether depth is written is not an attribute.

    Args:
        points: Raster vertices, one per point.
        starts: Where each node program starts in the fog buffer, as
            `program_starts` lays them out. A point naming a program past
            it, as `GpuRenderer.draw` refuses, gets -1.

    Returns:
        Texture id, blend policy, alpha map id, then the packed depth,
        color and stencil state, then one or zero for whether the fog
        veils it, then where its node program starts or -1, per point.
    """
    var state = List[Int32]()
    for point in range(len(points)):
        state.append(Int32(points[point].texture.value))
        state.append(Int32(points[point].blend.value))
        state.append(Int32(points[point].alpha_map.value))
        state.append(Int32(points[point].state.ops_word()))
        state.append(Int32(points[point].state.stencil_word()))
        state.append(Int32(1 if points[point].fog else 0))
        var named = points[point].nodes.value
        state.append(
            Int32(starts[named] if named >= 0 and named < len(starts) else -1)
        )
    return state^


# The most entries a frame's bins may hold, about 512 MiB of indices. A
# frame whose triangles reach more tiles than this is drawn unbinned: each
# pixel walks every triangle, as it did before bins.
comptime BIN_LIMIT = 1 << 27


def bin_triangles(
    corners: List[RasterVertex],
    width: Int,
    height: Int,
    base: Int,
    limit: Int = BIN_LIMIT,
) -> List[Int32]:
    """Return each `TILE` x `TILE` tile's triangles, for the kernel to walk
    in place of every triangle.

    A pixel is covered only where its sample, snapped as `render.fillrule`
    snaps it, lies inside the snapped triangle. So a triangle can cover
    only the pixels whose samples lie in its snapped bounds, and the tiles
    those pixels are in. The bounds are computed here with the kernel's own
    `snap` and `sample`, so a triangle is never left out of a tile it can
    cover. A triangle with a coordinate that is not finite, or too large to
    snap exactly, goes in every tile, and the kernel decides it as before.

    Args:
        corners: Raster vertices, three per triangle.
        width: The image's width in pixels.
        height: The image's height in pixels.
        base: Where the result starts in the draw buffer, after the draw
            table. The offsets it holds count from the buffer's start.
        limit: The most entries the bins may hold.

    Returns:
        One flag, then the tiles' offsets, then the triangle indices. The
        flag is 1 when the triangles are binned. Then come `tiles + 1`
        offsets, in row-major tile order, and tile t's triangles are the
        indices from offset t up to offset t + 1, in increasing order. The
        flag is 0, with nothing after it, when the bins would hold more
        than `limit` entries.
    """
    var across = ceildiv(width, TILE)
    var down = ceildiv(height, TILE)
    var tiles = across * down
    var triangles = len(corners) // 3
    # Each triangle's tile rectangle: first and last column, first and last
    # row. An empty rectangle has its first after its last.
    var spans = List[Int](length=triangles * 4, fill=0)
    var counts = List[Int](length=tiles, fill=0)
    var total = 0
    for triangle in range(triangles):
        _tile_span(corners, triangle, width, height, spans)
        var at = triangle * 4
        var columns = spans[at + 1] - spans[at] + 1
        var rows = spans[at + 3] - spans[at + 2] + 1
        if columns <= 0 or rows <= 0:
            continue
        total += columns * rows
        if total > limit:
            return [Int32(0)]
        for row in range(spans[at + 2], spans[at + 3] + 1):
            for column in range(spans[at], spans[at + 1] + 1):
                counts[row * across + column] += 1
    var bins = List[Int32](length=1 + tiles + 1 + total, fill=0)
    bins[0] = 1
    var start = base + 1 + tiles + 1
    var next = List[Int](length=tiles, fill=0)
    for tile in range(tiles):
        bins[1 + tile] = Int32(start)
        next[tile] = start - base
        start += counts[tile]
    bins[1 + tiles] = Int32(start)
    for triangle in range(triangles):
        for row in range(spans[triangle * 4 + 2], spans[triangle * 4 + 3] + 1):
            for column in range(
                spans[triangle * 4], spans[triangle * 4 + 1] + 1
            ):
                var tile = row * across + column
                bins[next[tile]] = Int32(triangle)
                next[tile] += 1
    return bins^


# The largest coordinate magnitude `_tile_span` snaps: its subpixel value
# and every edge product stay exact far inside 64-bit integers.
comptime _SNAP_LIMIT = Float32(1 << 24)


def _tile_span(
    corners: List[RasterVertex],
    triangle: Int,
    width: Int,
    height: Int,
    mut spans: List[Int],
):
    """Write the first and last tile column, then the first and last tile
    row, whose pixels a triangle can cover, to the triangle's four entries
    of `spans`: every tile when a corner cannot be snapped exactly, and a
    first after its last when no pixel can be covered."""
    var across = ceildiv(width, TILE)
    var down = ceildiv(height, TILE)
    var at = triangle * 4
    var low_x = Int.MAX
    var high_x = Int.MIN
    var low_y = Int.MAX
    var high_y = Int.MIN
    var all_finite = True
    var min_fx = Float32.MAX
    var max_fx = -Float32.MAX
    var min_fy = Float32.MAX
    var max_fy = -Float32.MAX
    for corner in range(3):
        ref v = corners[triangle * 3 + corner]
        if isfinite(v.x) and isfinite(v.y):
            min_fx = min(min_fx, v.x)
            max_fx = max(max_fx, v.x)
            min_fy = min(min_fy, v.y)
            max_fy = max(max_fy, v.y)
        else:
            all_finite = False
    # A triangle wholly past one side of the image covers no pixel, however
    # large its corners are. `snap` never decreases, so a corner left of
    # x = 0 snaps left of the first sample, and a corner right of x = width
    # snaps right of the last sample. A corner in the half pixel between an
    # edge of the image and its nearest sample can snap onto that sample.
    # The exact test below decides such a triangle.
    if all_finite and (
        max_fx < Float32(0)
        or min_fx > Float32(width)
        or max_fy < Float32(0)
        or min_fy > Float32(height)
    ):
        spans[at] = 1
        spans[at + 1] = 0
        spans[at + 2] = 1
        spans[at + 3] = 0
        return
    for corner in range(3):
        ref vertex = corners[triangle * 3 + corner]
        if not (abs(vertex.x) <= _SNAP_LIMIT and abs(vertex.y) <= _SNAP_LIMIT):
            spans[at] = 0
            spans[at + 1] = across - 1
            spans[at + 2] = 0
            spans[at + 3] = down - 1
            return
        var x = snap(vertex.x)
        var y = snap(vertex.y)
        low_x = min(low_x, x)
        high_x = max(high_x, x)
        low_y = min(low_y, y)
        high_y = max(high_y, y)
    var columns = _pixel_span(low_x, high_x, width)
    var rows = _pixel_span(low_y, high_y, height)
    if columns[0] > columns[1] or rows[0] > rows[1]:
        spans[at] = 1
        spans[at + 1] = 0
        spans[at + 2] = 1
        spans[at + 3] = 0
        return
    spans[at] = columns[0] // TILE
    spans[at + 1] = columns[1] // TILE
    spans[at + 2] = rows[0] // TILE
    spans[at + 3] = rows[1] // TILE


def _pixel_span(low: Int, high: Int, pixels: Int) -> Tuple[Int, Int]:
    """Return the first and last of `pixels` whose sample lies from `low` to
    `high` on the subpixel grid, the first after the last when none does.

    Pixel p's sample is `sample(p)`, p * SUBPIXEL + SUBPIXEL / 2."""
    var half = SUBPIXEL // 2
    # The first p with sample(p) >= low, and the last with sample(p) <= high.
    var first = -((half - low) // SUBPIXEL)
    var last = (high - half) // SUBPIXEL
    first = max(first, 0)
    last = min(last, pixels - 1)
    if first > last:
        return (1, 0)
    return (first, last)


def triangle_state(
    corners: List[RasterVertex],
    cube_base: Int = 0,
    starts: List[Int] = List[Int](),
    light_starts: List[Int] = List[Int](),
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
        light_starts: Where each light block starts, as
            `flatten_frame_lights` lays them out. A triangle whose
            `lights` is past it gets zero, the frame's own.

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
        ids, then the normal map type's value, then its facing, then its
        thickness map's id, then where its light block starts, per
        triangle, from its first corner.
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
        state.append(
            Int32(
                (1 if corners[triangle * 3].seen_from_behind else 0)
                + (2 if corners[triangle * 3].flip_sided else 0)
            )
        )
        state.append(Int32(corners[triangle * 3].scatter_map.value))
        var named = corners[triangle * 3].lights
        state.append(
            Int32(light_starts[named]) if named < len(light_starts) else 0
        )
    return state^


def flatten_frame_lights(
    lighting: Lighting, lightings: List[Lighting]
) -> Tuple[List[Float32], List[Int]]:
    """Return a frame's lighting and the lightings its light masks resolve
    to, one `flatten_lights` block after another, and where each block
    starts: what `rasterize_frame`'s `lightings` are on the host.

    Each block's own offsets, of its shadow maps and its spot light maps,
    are from its own start, so a triangle reads its block through the
    buffer moved to that start.

    Args:
        lighting: The frame's own lights, the first block.
        lightings: The lights of each light mask, in order.

    Returns:
        The buffer, and the start of each block: zero for the first.
    """
    var flat = flatten_lights(lighting)
    var starts: List[Int] = [0]
    for index in range(len(lightings)):
        starts.append(len(flat))
        flat.extend(flatten_lights(lightings[index]))
    return (flat^, starts^)
