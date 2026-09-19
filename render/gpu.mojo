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
from render.fillrule import SUBPIXEL, bias, edge_at, sample, snap
from render.linerule import covers, major_is_x, share_at
from render.framebuffer import Color, FloatColor, Framebuffer
from core.fog import NO_FOG, FogKind, FogView, fog_factor, fog_mix
from lights.lighting import (
    PERSPECTIVE_VIEW,
    Lighting,
    blinn_phong,
    falloff,
    toon_coord,
    toon_index,
    toon_step,
    toward_eye_at,
)
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.rasterizer import (
    check_line_state,
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
    interpolate_alpha,
    matcap_fallback,
    matcap_uv,
    packed_depth,
    packed_normal,
)
from materials.material import (
    BLEND,
    DEPTH,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    TOON,
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
    IGNORED,
    NEAREST,
    Alpha,
    Filter,
    Texture,
    Wrap,
    blend_texels,
    mix_color,
    mix_straight,
    wrap_index,
)
from max.gpu import global_idx
from std.math import ceildiv, floor, inf, log2, sqrt
from std.memory import unsafe_memcpy
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
comptime FLOATS_PER_VERTEX = LANE_SHININESS + 1
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
# How many integers a segment's state takes: its blend policy, and
# nothing else. A line is unlit and untextured; see `line_state`.
comptime STATE_PER_LINE = 1
# How a `Draw` crosses to the device: its kind, its first primitive and its
# count, as three integers.
comptime INTS_PER_DRAW = 3
comptime STATE_PER_TRIANGLE = STATE_MATCAP + 1

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
comptime LIGHTS_FIRST = 13

# Further than any NDC depth, so the first covering triangle always wins. The
# host framebuffer uses an actual infinity; a literal keeps the kernel free of
# any dependency on how the host spells one.
comptime FURTHEST = Float32(1.0e30)

# One row per texture in the store: where its bytes start, how big it is, and
# how to sample it. A device cannot hold a `List` of `List`s, so every image
# goes into one buffer end to end and this says where each one begins.
comptime TABLE_COLUMNS = 8


def flatten_textures(
    textures: TextureStore,
) raises -> Tuple[List[UInt8], List[Int32]]:
    """Return every texture's bytes end to end, and the table describing them.

    Args:
        textures: The store to upload.

    Returns:
        The concatenated texels, and `TABLE_COLUMNS` entries per texture:
        byte offset, width, height, wrap mode, filter mode, color space,
        how many mip levels follow, and the alpha mode.

    Raises:
        Error: If a texture cannot be read, or its wrap, filter, color
            space or alpha mode is none of the named values -- a texture's
            fields are open, so one can have been edited since it was built,
            and the kernel cannot raise on what it finds in the table.
    """
    var texels = List[UInt8]()
    var table = List[Int32]()
    for id in range(textures.count()):
        ref image = textures.get(TextureId(id))
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
            for _ in range(4):
                texels.append(255)
            continue
        table.append(Int32(image.width))
        table.append(Int32(image.height))
        table.append(Int32(image.wrap.value))
        table.append(Int32(image.filter.value))
        table.append(Int32(image.color_space.value))
        table.append(Int32(image.levels))
        table.append(Int32(image.alpha.value))
        # One bulk copy rather than an append per byte.
        texels.extend(image.pixels.copy())
    # Never empty: a zero-length device buffer is not worth the special case,
    # and a vertex naming NO_TEXTURE never reads either of these.
    if len(texels) == 0:
        texels.append(0)
    if len(table) == 0:
        for _ in range(TABLE_COLUMNS):
            table.append(0)
    return (texels^, table^)


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
    return flat^


def flatten_lights(lighting: Lighting) -> List[Float32]:
    """Return a scene's lights as the flat float buffer the kernel reads.

    Three floats of camera position, three of the one direction toward it
    under a parallel projection, three of the camera's own up axis, then
    three of ambient, one of `Lighting.scale`, then six per
    directional light -- a unit
    direction and the light it carries -- then eight per point light: where
    it is, the light it carries, its decay and its cutoff. Then nine per
    hemisphere light: which way the sky is, what the sky carries and what
    the ground carries. Then thirteen per spot light: where it is, which way
    it points, what it carries, its decay, its cutoff, and the cosines of
    its cone and of its penumbra. Already decoded and scaled by `Lighting`,
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

    Returns:
        `LIGHTS_FIRST + 6 * count + 8 * point_count + 9 * hemisphere_count
        + 13 * spot_count` floats.
    """
    var flat = List[Float32]()
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
    for index in range(lighting.count()):
        ref direction = lighting.directions[index]
        flat.append(direction.x)
        flat.append(direction.y)
        flat.append(direction.z)
        ref radiance = lighting.radiances[index]
        flat.append(radiance.r)
        flat.append(radiance.g)
        flat.append(radiance.b)
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
    return flat^


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


def _arriving(
    lights: MutPointer[Float32, MutAnyOrigin],
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
) -> Vector3:
    """Return the light reaching a surface at (px, py, pz) facing (nx, ny, nz).

    The device counterpart of `Lighting.intensity_at`, and held to the same
    answer by the parity tests. A `Vector3` only because the kernel has no
    color type; the three components are red, green and blue.
    """
    var red = lights[unsafe_offset=LIGHTS_AMBIENT]
    var green = lights[unsafe_offset=LIGHTS_AMBIENT + 1]
    var blue = lights[unsafe_offset=LIGHTS_AMBIENT + 2]
    for index in range(count):
        var at = LIGHTS_FIRST + index * 6
        var lambert = (
            nx * lights[unsafe_offset=at]
            + ny * lights[unsafe_offset=at + 1]
            + nz * lights[unsafe_offset=at + 2]
        )
        if lambert <= 0:
            continue
        red += lights[unsafe_offset=at + 3] * lambert
        green += lights[unsafe_offset=at + 4] * lambert
        blue += lights[unsafe_offset=at + 5] * lambert
    var first_point = LIGHTS_FIRST + count * 6
    for index in range(points):
        var at = first_point + index * 8
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
        var reach = lambert * falloff(
            distance, lights[unsafe_offset=at + 6], lights[unsafe_offset=at + 7]
        )
        red += lights[unsafe_offset=at + 3] * reach
        green += lights[unsafe_offset=at + 4] * reach
        blue += lights[unsafe_offset=at + 5] * reach
    var first_sky = first_point + points * 8
    for index in range(hemispheres):
        var at = first_sky + index * 9
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
    var first_spot = first_sky + hemispheres * 9
    for index in range(spots):
        var at = first_spot + index * 13
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
        )
        red += lights[unsafe_offset=at + 6] * reach
        green += lights[unsafe_offset=at + 7] * reach
        blue += lights[unsafe_offset=at + 8] * reach
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
    start: Int,
    tones: Int,
    nx: Float32,
    ny: Float32,
    nz: Float32,
    px: Float32,
    py: Float32,
    pz: Float32,
) -> Vector3:
    """Return the light reaching a `TOON` surface at (px, py, pz).

    The device counterpart of `Lighting.toon_at`, and held to the same
    answer by the parity tests. Every cosine a light makes is read off the
    ramp instead of used directly, and never clamped at zero, so a lamp
    behind the surface still lights it to the ramp's left end. The ambient
    term and the hemisphere lights are not stepped, because three.js
    reflects those through `RE_IndirectDiffuse`.
    """
    var red = lights[unsafe_offset=LIGHTS_AMBIENT]
    var green = lights[unsafe_offset=LIGHTS_AMBIENT + 1]
    var blue = lights[unsafe_offset=LIGHTS_AMBIENT + 2]
    for index in range(count):
        var at = LIGHTS_FIRST + index * 6
        var tone = _toon_tone(
            texels,
            start,
            tones,
            nx * lights[unsafe_offset=at]
            + ny * lights[unsafe_offset=at + 1]
            + nz * lights[unsafe_offset=at + 2],
        )
        red += lights[unsafe_offset=at + 3] * tone
        green += lights[unsafe_offset=at + 4] * tone
        blue += lights[unsafe_offset=at + 5] * tone
    var first_point = LIGHTS_FIRST + count * 6
    for index in range(points):
        var at = first_point + index * 8
        var dx = lights[unsafe_offset=at] - px
        var dy = lights[unsafe_offset=at + 1] - py
        var dz = lights[unsafe_offset=at + 2] - pz
        var distance = sqrt(dx * dx + dy * dy + dz * dz)
        if distance == 0:
            continue
        var tone = _toon_tone(
            texels, start, tones, (nx * dx + ny * dy + nz * dz) / distance
        )
        var reach = tone * falloff(
            distance, lights[unsafe_offset=at + 6], lights[unsafe_offset=at + 7]
        )
        red += lights[unsafe_offset=at + 3] * reach
        green += lights[unsafe_offset=at + 4] * reach
        blue += lights[unsafe_offset=at + 5] * reach
    var first_sky = first_point + points * 8
    for index in range(hemispheres):
        var at = first_sky + index * 9
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
    var first_spot = first_sky + hemispheres * 9
    for index in range(spots):
        var at = first_spot + index * 13
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
        )
        red += lights[unsafe_offset=at + 6] * reach
        green += lights[unsafe_offset=at + 7] * reach
        blue += lights[unsafe_offset=at + 8] * reach
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    return Vector3(red * scale, green * scale, blue * scale)


def _highlight(
    lights: MutPointer[Float32, MutAnyOrigin],
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
        var at = LIGHTS_FIRST + index * 6
        var toward = Vector3(
            lights[unsafe_offset=at],
            lights[unsafe_offset=at + 1],
            lights[unsafe_offset=at + 2],
        )
        var lambert = normal.dot(toward)
        if lambert <= 0:
            continue
        var sent = blinn_phong(toward, toward_eye, normal, specular, shininess)
        red += lights[unsafe_offset=at + 3] * lambert * sent.x
        green += lights[unsafe_offset=at + 4] * lambert * sent.y
        blue += lights[unsafe_offset=at + 5] * lambert * sent.z
    var first_point = LIGHTS_FIRST + count * 6
    for index in range(points):
        var at = first_point + index * 8
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
        var reach = lambert * falloff(
            distance, lights[unsafe_offset=at + 6], lights[unsafe_offset=at + 7]
        )
        toward.normalize()
        var sent = blinn_phong(toward, toward_eye, normal, specular, shininess)
        red += lights[unsafe_offset=at + 3] * reach * sent.x
        green += lights[unsafe_offset=at + 4] * reach * sent.y
        blue += lights[unsafe_offset=at + 5] * reach * sent.z
    var first_spot = first_point + points * 8 + hemispheres * 9
    for index in range(spots):
        var at = first_spot + index * 13
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
        )
        toward.normalize()
        var sent = blinn_phong(toward, toward_eye, normal, specular, shininess)
        red += lights[unsafe_offset=at + 6] * reach * sent.x
        green += lights[unsafe_offset=at + 7] * reach * sent.y
        blue += lights[unsafe_offset=at + 8] * reach * sent.z
    var scale = lights[unsafe_offset=LIGHTS_SCALE]
    return Vector3(red * scale, green * scale, blue * scale)


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
    """
    var wide = _extent(image.width, level)
    var tall = _extent(image.height, level)
    var offset = (
        image.start
        + _level_start(image.width, image.height, level)
        + (
            wrap_index(y, tall, image.wrap) * wide
            + wrap_index(x, wide, image.wrap)
        )
        * 4
    )
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


def line_state(corners: List[RasterVertex]) -> List[Int32]:
    """Return each segment's blend policy, `STATE_PER_LINE` entries each.

    A line carries far less per-primitive state than a triangle: it is
    unlit and untextured, so whether it composites is the only thing the
    kernel cannot read off a vertex. It is still a table rather than a
    float lane, for the reason the triangles' is -- a policy that decides
    both how a color is combined and whether depth is written is not an
    attribute to interpolate.

    Args:
        corners: Raster vertices, two per segment.

    Returns:
        The blend policy per segment, from its first end.
    """
    var state = List[Int32]()
    for segment in range(len(corners) // 2):
        state.append(Int32(corners[segment * 2].blend.value))
    return state^


def triangle_state(corners: List[RasterVertex]) -> List[Int32]:
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

    Returns:
        Texture id, blend policy, the material kind's value, the emissive
        map id, the alpha map id, the gradient map id, then the matcap id,
        per triangle, from its first corner.
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
) -> Vector2:
    """Return the perspective-correct texture coordinates at a sample point.

    Coverage is not tested: this is called for the pixels either side, which
    are routinely outside the triangle. Barycentric coordinates extrapolate
    perfectly well; it is only coverage that stops at the edge. That is what
    replaces the helper invocations a hardware quad would need.
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
        corners[unsafe_offset=base + LANE_U] * share_a
        + corners[unsafe_offset=b_base + LANE_U] * share_b
        + corners[unsafe_offset=c_base + LANE_U] * share_c,
        corners[unsafe_offset=base + LANE_V] * share_a
        + corners[unsafe_offset=b_base + LANE_V] * share_b
        + corners[unsafe_offset=c_base + LANE_V] * share_c,
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


def _mip_level(
    u: Float32,
    v: Float32,
    along_x: Vector2,
    along_y: Vector2,
    width: Float32,
    height: Float32,
) -> Float32:
    """How far down the chain this pixel's footprint reaches.

    `along_x` and `along_y` already hold the coordinates at the neighboring
    pixels, worked out from the same analytic expression the host uses; see
    `render.rasterizer.mip_level`.
    """
    var dx_u = (along_x.x - u) * width
    var dx_v = (along_x.y - v) * height
    var dy_u = (along_y.x - u) * width
    var dy_v = (along_y.y - v) * height
    var in_x = sqrt(dx_u * dx_u + dx_v * dx_v)
    var in_y = sqrt(dy_u * dy_u + dy_v * dy_v)
    var longest = in_x
    if in_y > longest:
        longest = in_y
    if longest <= 0:
        return 0
    return log2(longest)


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
    alike on both sides.
    """
    var image = _describe(table, slot)
    if image.levels == 1:
        return _sample_at(texels, ramp, image, u, v, 0)
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
    )
    # v flipped and wrapped by the same routine the host uses, and blended
    # by the same one -- see render.texture.
    return _sample_level(
        texels,
        ramp,
        image,
        u,
        v,
        _mip_level(
            u,
            v,
            along_x,
            along_y,
            Float32(image.width),
            Float32(image.height),
        ),
    )


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
    draws: MutPointer[Int32, MutAnyOrigin],
    draw_count: Int32,
):
    """Color one pixel from the nearest primitive that covers it.

    The draws in the frame's order, each a run of triangles or of
    segments, which is the order the host draws them in and the order
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

    var px = sample(x)
    var py = sample(y)

    # Resolved by the material, not guessed at from an alpha. A debug view of
    # texture coordinates is always opaque: it shows the nearest surface's
    # coordinates, and averaging several surfaces' would mean nothing.
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
    # Whether the pixel holds data rather than light, decided by the last
    # fragment into it exactly as `RenderTarget.write` and `blend` decide
    # it: a normal or a depth, which the tone mapping must leave alone.
    var data = False
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
                if not covers(first, second, x, y):
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
                var z = az + (bz - az) * share
                if z >= nearest:
                    continue
                var near = segments[unsafe_offset=base + LANE_INV_W] * (
                    1 - share
                )
                var away = segments[unsafe_offset=far_base + LANE_INV_W] * share
                var total = near + away
                if total == 0:
                    continue
                var toward = away / total
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
                var mixes = segment_maps[
                    unsafe_offset=index * STATE_PER_LINE
                ] == Int32(BLEND.value)
                if mixes and share_a == 0:
                    continue
                found = True
                if not mixes:
                    # Opaque, so written with an alpha of one, as on the host.
                    share_a = 1
                    mixed_r = drawn.r * share_a
                    mixed_g = drawn.g * share_a
                    mixed_b = drawn.b * share_a
                    mixed_a = share_a
                    nearest = z
                    solid = True
                    # A line is light, never data: it has no normal to show and no
                    # depth material to show one. `check_line_state` refuses any
                    # kind but an unlit one.
                    data = False
                else:
                    var keep = 1 - share_a
                    mixed_r = drawn.r * share_a + mixed_r * keep
                    mixed_g = drawn.g * share_a + mixed_g * keep
                    mixed_b = drawn.b * share_a + mixed_b * keep
                    mixed_a = share_a + mixed_a * keep
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
            if z >= nearest:
                continue

            # Color does not: weight by inv_w and divide by the interpolated
            # inv_w, matching `rasterize_shaded`.
            var inv_w = wa * aw + wb * bw + wc * cw
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
            # The alpha a fragment must reach to be drawn, from the first
            # corner's lane, and whether there is a test at all. The uv debug
            # view cuts nothing out, as it samples no texture.
            var threshold = corners[unsafe_offset=base + LANE_ALPHA_TEST]
            var tested = threshold > 0 and mode != Int32(SHADE_UV.value)
            var kind = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_KIND
            ]
            var lit = (
                kind == Int32(LAMBERT.value)
                or kind == Int32(PHONG.value)
                or kind == Int32(TOON.value)
            )
            # Unlit, but looked up by which way the surface is turned, so it
            # needs the normal and the world position that a lit surface needs.
            var looked_up = kind == Int32(MATCAP.value)
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
                lit or shows_normal or looked_up
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
            if mode != Int32(SHADE_UV.value) and (lit or looked_up):
                # Where this fragment is in the world, for the lights that have
                # a position.
                var wx = (
                    corners[unsafe_offset=base + LANE_WX] * share_a
                    + corners[unsafe_offset=b_base + LANE_WX] * share_b
                    + corners[unsafe_offset=c_base + LANE_WX] * share_c
                )
                var wy = (
                    corners[unsafe_offset=base + LANE_WY] * share_a
                    + corners[unsafe_offset=b_base + LANE_WY] * share_b
                    + corners[unsafe_offset=c_base + LANE_WY] * share_c
                )
                var wz = (
                    corners[unsafe_offset=base + LANE_WZ] * share_a
                    + corners[unsafe_offset=b_base + LANE_WZ] * share_b
                    + corners[unsafe_offset=c_base + LANE_WZ] * share_c
                )
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
                        start,
                        tones,
                        nx,
                        ny,
                        nz,
                        wx,
                        wy,
                        wz,
                    )
                else:
                    arriving = _arriving(
                        lights,
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
                else:
                    # The highlight and then the glow, exactly as
                    # `rasterize_shaded` sums them.
                    red += highlight.x + glow_r
                    green += highlight.y + glow_g
                    blue += highlight.z + glow_b
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
            var mixes = maps[
                unsafe_offset=index * STATE_PER_TRIANGLE + STATE_BLEND
            ] == Int32(BLEND.value) and mode != Int32(SHADE_UV.value)
            # A source-over fragment that covers nothing contributes no color,
            # so it must contribute no depth and no answer about what the pixel
            # holds either. `RenderTarget.blend` returns early for the same
            # reason; see `render.target`.
            if mixes and share == 0:
                continue
            found = True
            if not mixes:
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
                nearest = z
                solid = True
                # A write replaces the pixel, so its answer becomes this
                # fragment's, exactly as `RenderTarget.write` decides it.
                # The uv view shows coordinates, which the tone mapping has
                # to leave alone exactly as it leaves a normal alone.
                data = shows_data or mode == Int32(SHADE_UV.value)
            else:
                # Source-over, premultiplied: a weighted sum with no special case.
                var keep = 1 - share
                mixed_r = red * share + mixed_r * keep
                mixed_g = green * share + mixed_g * keep
                mixed_b = blue * share + mixed_b * keep
                mixed_a = share + mixed_a * keep
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
        _ = self.draw_list^
        _ = self.texels^
        _ = self.table^
        _ = self.ramp^
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
        # Two draws' worth: the order a frame with no list of its own gets,
        # every triangle and then every segment.
        self.draw_room = 2
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
        self.ignores_alpha = List[Bool]()
        self.is_linear = List[Bool]()
        self.has_texels = List[Bool]()
        self.heights = List[Int]()
        self.ramp = self.context.enqueue_create_buffer[DType.float32](256)
        var steps = decode_ramp()
        with self.ramp.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(), src=steps.unsafe_ptr(), count=256
            )

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
    ) raises:
        """Rasterize prepared triangles and lines into the device target.

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
            draws: The order to draw in, as runs of triangles or of
                segments; see `render.rasterizer.Draw`. Empty, the
                default, draws every triangle and then every segment,
                which is the order `rasterize_all` followed by
                `rasterize_lines_all` draws them in. `Renderer.prepare_frame`
                gives the order `Renderer.render` uses, with blended
                triangles and segments sorted together.

        Raises:
            Error: If the corner count is not a multiple of three, the
                line corner count is not a multiple of two, a segment's
                ends disagree or its material is lit, a draw is refused
                by `check_draws`, the mode
                is none of the three, the tone mapping is none of the
                seven, the exposure is negative or not finite, the fog
                view is refused by `FogView.validate`, a triangle's blend
                policy, material kind, texture or
                emissive map disagrees between its corners or is a value
                neither backend knows, a vertex names a texture, an
                emissive map or an alpha map that is not uploaded, an
                emissive map that
                `SHADE_TEXTURE` would open does not ignore its alpha, or an
                alpha map it would open is not linear or does not ignore
                its alpha.
        """
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
        # The order, or the two-pass one when none is given. Checked by
        # the function the host checks with: the kernel reads the corner
        # buffers at whatever index a draw hands it.
        var order = draws.copy()
        if len(order) == 0:
            order.append(Draw(DRAW_TRIANGLES, 0, triangles))
            order.append(Draw(DRAW_SEGMENTS, 0, len(lines) // 2))
        check_draws(order, triangles, len(lines) // 2)

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
            ]:
                if slot == NO_TEXTURE:
                    continue
                if slot.value < 0 or slot.value >= self.uploaded:
                    raise Error(
                        "A vertex names a texture that has not been uploaded;"
                        " call set_textures() first"
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
        # Two output representations cannot share a tone-mapped frame.
        # Asked here, before the launch, exactly where `Renderer.render`
        # asks it before it draws. The uv view is data throughout and is
        # never tone mapped, so it is never refused.
        check_output_kinds(
            corners,
            mode != SHADE_UV and tone_mapping != NO_TONE_MAPPING,
            lines,
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
            var state = triangle_state(corners)
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
            var policies = line_state(lines)
            with self.segment_maps.map_to_host() as host:
                unsafe_memcpy(
                    dest=host.unsafe_ptr(),
                    src=policies.unsafe_ptr(),
                    count=len(policies),
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
            self.draw_list.unsafe_ptr(),
            Int32(len(order)),
            grid_dim=(
                ceildiv(self.width, TILE),
                ceildiv(self.height, TILE),
            ),
            block_dim=(TILE, TILE),
        )
        self.drawn = True

    def set_textures(mut self, textures: TextureStore) raises:
        """Upload every texture in `textures`, replacing any previous set.

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

        Raises:
            Error: If a texture holds a wrap, filter or color space that is
                none of the named values, or the device buffers cannot be
                made or filled. Either way nothing on the device has changed.
        """
        var flattened = flatten_textures(textures)
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
        for id in range(textures.count()):
            ref image = textures.get(TextureId(id))
            self.ignores_alpha.append(image.alpha == IGNORED)
            self.is_linear.append(image.color_space == LINEAR)
            self.has_texels.append(not image.is_blank())
            self.heights.append(image.height)

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
) raises -> Framebuffer:
    """Draw prepared triangles and lines on the GPU and read the image back.

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

    Returns:
        The rendered image.

    Raises:
        Error: If the dimensions are invalid, no GPU is present, the corner
            count is not a multiple of three, or the line corner count is
            not a multiple of two.
    """
    var renderer = GpuRenderer(width, height)
    renderer.set_textures(textures)
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
