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
without synchronization. Independent triangle threads writing a shared colour
and depth buffer race: `Framebuffer.test_depth` is a read followed by a write,
which is a depth test, not an atomic. Because each pixel here is owned
outright, its depth lives in a register that nothing else can touch. That
depth is written out alongside the colour, so what comes back is a framebuffer
in the same sense the CPU produces one — a result that reports no depth at all
would silently let a later depth-tested triangle paint over a nearer surface.
Tiling and per-triangle binning can come later; they are optimizations of a
correct thing.

**The transform pipeline is still on the host.** Scene traversal, projection,
lighting and clipping run on the CPU, and only the finished screen-space
triangles come here. That is a deliberate stage, not an unfinished one: it
makes the GPU a second implementation of exactly one well-defined step, which
is what lets the parity tests be meaningful.

Colours cross the boundary packed into a `UInt32`. Kernel arguments must
conform to `DevicePassable`, which rules out the `Color` struct and, less
obviously, plain `Int` — the compiler asks for a fixed-width type instead.

Whether this is *faster* than the CPU is a separate question, and the answer
is size-dependent. `bench/raster_bench.mojo` measures where the crossover is.
"""

from math.vector2 import Vector2
from max.gpu.host import DeviceBuffer, DeviceContext
from render.fillrule import SUBPIXEL, bias, edge_at, sample, snap
from render.framebuffer import Color, FloatColor, Framebuffer
from lights.lighting import Lighting, falloff
from math.vector3 import Vector3
from render.rasterizer import (
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    ShadeMode,
    Triangle,
    check_triangle_state,
)
from materials.material import BLEND
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from render.srgb import SRGB, ColorSpace, decode_ramp
from render.texture import (
    BILINEAR,
    NEAREST,
    Filter,
    Texture,
    Wrap,
    blend_texels,
    mix_colour,
    wrap_index,
)
from std.gpu import global_idx
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
# change once meant missing one, which silently read a neighbouring field as
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
comptime FLOATS_PER_VERTEX = LANE_WZ + 1
comptime FLOATS_PER_TRIANGLE = FLOATS_PER_VERTEX * 3

# Further than any NDC depth, so the first covering triangle always wins. The
# host framebuffer uses an actual infinity; a literal keeps the kernel free of
# any dependency on how the host spells one.
comptime FURTHEST = Float32(1.0e30)

# One row per texture in the store: where its bytes start, how big it is, and
# how to sample it. A device cannot hold a `List` of `List`s, so every image
# goes into one buffer end to end and this says where each one begins.
comptime TABLE_COLUMNS = 7


def flatten_textures(
    textures: TextureStore,
) raises -> Tuple[List[UInt8], List[Int32]]:
    """Return every texture's bytes end to end, and the table describing them.

    Args:
        textures: The store to upload.

    Returns:
        The concatenated texels, and `TABLE_COLUMNS` entries per texture:
        byte offset, width, height, wrap mode, filter mode, colour space,
        and how many mip levels follow.

    Raises:
        Error: If a texture cannot be read, or its wrap, filter or colour
            space is none of the named values -- a texture's fields are open,
            so one can have been edited since it was built, and the kernel
            cannot raise on what it finds in the table.
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
            for _ in range(4):
                texels.append(255)
            continue
        table.append(Int32(image.width))
        table.append(Int32(image.height))
        table.append(Int32(image.wrap.value))
        table.append(Int32(image.filter.value))
        table.append(Int32(image.color_space.value))
        table.append(Int32(image.levels))
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
    return flat^


def flatten_lights(lighting: Lighting) -> List[Float32]:
    """Return a scene's lights as the flat float buffer the kernel reads.

    Three floats of ambient, then six per directional light -- a unit
    direction and the light it carries -- then eight per point light: where
    it is, the light it carries, its decay and its cutoff. Already decoded
    and scaled by `Lighting`, so the device does no colour-space work and
    both backends sum exactly the same numbers.

    Args:
        lighting: The scene's lights, resolved to world space.

    Returns:
        `3 + 6 * count + 8 * point_count` floats.
    """
    var flat = List[Float32]()
    flat.append(lighting.ambient.r)
    flat.append(lighting.ambient.g)
    flat.append(lighting.ambient.b)
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
    return flat^


def _arriving(
    lights: MutPointer[Float32, MutAnyOrigin],
    count: Int,
    points: Int,
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
    colour type; the three components are red, green and blue.
    """
    var red = lights[unsafe_offset=0]
    var green = lights[unsafe_offset=1]
    var blue = lights[unsafe_offset=2]
    for index in range(count):
        var at = 3 + index * 6
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
    var first_point = 3 + count * 6
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
    return Vector3(red, green, blue)


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


def _fetch(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    start: Int,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    wrap: Wrap,
    space: ColorSpace,
    level: Int,
) -> FloatColor:
    """Read one texel from the device buffer, decoded and wrapped.

    The device counterpart of `Texture.wrapped_texel`. Only the memory access
    differs between the two: the index arithmetic is `wrap_index`, shared; the
    decode is the same 256-entry table the host builds, uploaded once; and the
    blend on top of them is `blend`, also shared. Alpha is not colour and is
    never decoded.
    """
    var wide = _extent(width, level)
    var tall = _extent(height, level)
    var offset = (
        start
        + _level_start(width, height, level)
        + (wrap_index(y, tall, wrap) * wide + wrap_index(x, wide, wrap)) * 4
    )
    # Asked the way the host asks it when it picks a ramp -- "is it SRGB?"
    # -- so a value that is neither reads as stored on both sides rather
    # than decoded on one.
    if space == SRGB:
        return FloatColor(
            ramp[unsafe_offset=Int(texels[unsafe_offset=offset])],
            ramp[unsafe_offset=Int(texels[unsafe_offset=offset + 1])],
            ramp[unsafe_offset=Int(texels[unsafe_offset=offset + 2])],
            Float32(texels[unsafe_offset=offset + 3]) / 255,
        )
    return FloatColor(
        Float32(texels[unsafe_offset=offset]) / 255,
        Float32(texels[unsafe_offset=offset + 1]) / 255,
        Float32(texels[unsafe_offset=offset + 2]) / 255,
        Float32(texels[unsafe_offset=offset + 3]) / 255,
    )


def triangle_state(corners: List[RasterVertex]) -> List[Int32]:
    """Return each triangle's texture, blend policy and lit flag, three
    entries each.

    Neither is a vertex attribute. A resource id was one for a commit —
    carried on all three corners, crossed as a `Float32`, read back from the
    first — which is to say it was already per-triangle in a per-vertex
    costume, and losing exactness above 2^24 on the way. Whether a surface
    composites is the same kind of thing, and worse to infer: it decides both
    how the colour is combined *and* whether depth is written, so guessing it
    from a float alpha in one place and a material in another is how the two
    came to disagree.

    Args:
        corners: Raster vertices, three per triangle.

    Returns:
        Texture id, blend policy, then one or zero for lit or not, per
        triangle, from its first corner.
    """
    var state = List[Int32]()
    for triangle in range(len(corners) // 3):
        state.append(Int32(corners[triangle * 3].texture.value))
        state.append(Int32(corners[triangle * 3].blend.value))
        var lit = Int32(0)
        if corners[triangle * 3].lit:
            lit = Int32(1)
        state.append(lit)
    return state^


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
    start: Int,
    width: Int,
    height: Int,
    wrap: Wrap,
    filter: Filter,
    space: ColorSpace,
    u: Float32,
    v: Float32,
    level: Int,
) -> FloatColor:
    """Sample one mip level, the device counterpart of `Texture.sample_at`."""
    var wide = _extent(width, level)
    var tall = _extent(height, level)
    if filter == NEAREST:
        return _fetch(
            texels,
            ramp,
            start,
            Int(floor(u * Float32(wide))),
            Int(floor((1 - v) * Float32(tall))),
            width,
            height,
            wrap,
            space,
            level,
        )
    # Texel centres sit at half-integers; see Texture.sample.
    var across = u * Float32(wide) - 0.5
    var down = (1 - v) * Float32(tall) - 0.5
    var column = Int(floor(across))
    var row = Int(floor(down))
    return blend_texels(
        _fetch(
            texels, ramp, start, column, row, width, height, wrap, space, level
        ),
        _fetch(
            texels,
            ramp,
            start,
            column + 1,
            row,
            width,
            height,
            wrap,
            space,
            level,
        ),
        _fetch(
            texels,
            ramp,
            start,
            column,
            row + 1,
            width,
            height,
            wrap,
            space,
            level,
        ),
        _fetch(
            texels,
            ramp,
            start,
            column + 1,
            row + 1,
            width,
            height,
            wrap,
            space,
            level,
        ),
        across - Float32(column),
        down - Float32(row),
    )


def _sample_level(
    texels: MutPointer[UInt8, MutAnyOrigin],
    ramp: MutPointer[Float32, MutAnyOrigin],
    start: Int,
    width: Int,
    height: Int,
    wrap: Wrap,
    filter: Filter,
    space: ColorSpace,
    levels: Int,
    u: Float32,
    v: Float32,
    level: Float32,
) -> FloatColor:
    """Trilinear across two mip levels, matching `Texture.sample_level`."""
    if levels == 1 or level <= 0:
        return _sample_at(
            texels, ramp, start, width, height, wrap, filter, space, u, v, 0
        )
    if level >= Float32(levels - 1):
        return _sample_at(
            texels,
            ramp,
            start,
            width,
            height,
            wrap,
            filter,
            space,
            u,
            v,
            levels - 1,
        )
    var lower = Int(floor(level))
    var near = _sample_at(
        texels, ramp, start, width, height, wrap, filter, space, u, v, lower
    )
    var far = _sample_at(
        texels, ramp, start, width, height, wrap, filter, space, u, v, lower + 1
    )
    return mix_colour(near, far, level - Float32(lower))


def _mip_level(
    u: Float32,
    v: Float32,
    along_x: Vector2,
    along_y: Vector2,
    width: Float32,
    height: Float32,
) -> Float32:
    """How far down the chain this pixel's footprint reaches.

    `along_x` and `along_y` already hold the coordinates at the neighbouring
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


def rasterize_kernel(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    corners: MutPointer[Float32, MutAnyOrigin],
    maps: MutPointer[Int32, MutAnyOrigin],
    triangles: Int32,
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
):
    """Colour one pixel from the nearest triangle that covers it."""
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
    # the clear colour rather than with black, and a transparent clear colour
    # contributes nothing rather than black. See render.target.
    var mixed_a = Float32(background & 0xFF) / 255
    var mixed_r = ramp[unsafe_offset=Int((background >> 24) & 0xFF)] * mixed_a
    var mixed_g = ramp[unsafe_offset=Int((background >> 16) & 0xFF)] * mixed_a
    var mixed_b = ramp[unsafe_offset=Int((background >> 8) & 0xFF)] * mixed_a

    for index in range(Int(triangles)):
        var base = index * FLOATS_PER_TRIANGLE
        # Derived rather than written out: every offset past the first corner
        # used to be a literal, and changing the stride meant changing all of
        # them. Twice it meant missing one, which reads a neighbouring field
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

        # Colour does not: weight by inv_w and divide by the interpolated
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

        # The interpolated normal, made a unit vector again here. That
        # renormalization is the difference between per-fragment and
        # per-vertex shading: the average of two unit vectors is shorter than
        # either, so leaving it alone dims the middle of every triangle.
        # Only the two lit modes need it; SHADE_UV writes coordinates rather
        # than light, and used to pay for the lighting anyway.
        var arriving = Vector3(1, 1, 1)
        # Only the two lit modes need it, and only a lit surface: SHADE_UV
        # writes coordinates rather than light, and a BASIC material shows its
        # own colour. Lit or not is per triangle, from the state table.
        if (
            mode != Int32(SHADE_UV.value)
            and maps[unsafe_offset=index * 3 + 2] != 0
        ):
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
            # Where this fragment is in the world, for the point lights.
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
            arriving = _arriving(
                lights,
                Int(light_count),
                Int(point_count),
                nx,
                ny,
                nz,
                wx,
                wy,
                wz,
            )

        if mode == Int32(SHADE_TEXTURE.value):
            var u = (
                corners[unsafe_offset=base + LANE_U] * share_a
                + corners[unsafe_offset=b_base + LANE_U] * share_b
                + corners[unsafe_offset=c_base + LANE_U] * share_c
            )
            var v = (
                corners[unsafe_offset=base + LANE_V] * share_a
                + corners[unsafe_offset=b_base + LANE_V] * share_b
                + corners[unsafe_offset=c_base + LANE_V] * share_c
            )
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
            alpha = (
                corners[unsafe_offset=base + LANE_A] * share_a
                + corners[unsafe_offset=b_base + LANE_A] * share_b
                + corners[unsafe_offset=c_base + LANE_A] * share_c
            )
            red *= arriving.x
            green *= arriving.y
            blue *= arriving.z
            # Which image, from the triangle; -1 is no texture, which samples
            # as white and so leaves the lighting alone.
            var slot = Int(maps[unsafe_offset=index * 3])
            if slot != NO_TEXTURE.value:
                # Every texture lives in one buffer end to end, so the table
                # says where this one starts and how to read it.
                var entry = slot * TABLE_COLUMNS
                var start = Int(table[unsafe_offset=entry])
                var width = Int(table[unsafe_offset=entry + 1])
                var height = Int(table[unsafe_offset=entry + 2])
                var wrap = Wrap(Int(table[unsafe_offset=entry + 3]))
                var filter = Filter(Int(table[unsafe_offset=entry + 4]))
                var space = ColorSpace(Int(table[unsafe_offset=entry + 5]))
                var levels = Int(table[unsafe_offset=entry + 6])

                var sampled = FloatColor(1.0, 1.0, 1.0, 1.0)
                if levels == 1:
                    # No chain to choose from, so no footprint to measure.
                    # The CPU takes the same shortcut; without it the two
                    # neighbour evaluations and the log below are computed
                    # and then thrown away.
                    sampled = _sample_at(
                        texels,
                        ramp,
                        start,
                        width,
                        height,
                        wrap,
                        filter,
                        space,
                        u,
                        v,
                        0,
                    )
                else:
                    # Where the coordinates land one pixel over and one down,
                    # evaluated from the triangle's own uv function rather
                    # than read from a neighbouring thread -- see
                    # render.rasterizer.mip_level.
                    var along_x = _uv_at(
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
                    var along_y = _uv_at(
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
                        py + SUBPIXEL,
                    )
                    # v flipped and wrapped by the same routine the host uses,
                    # and blended by the same one -- see render.texture.
                    sampled = _sample_level(
                        texels,
                        ramp,
                        start,
                        width,
                        height,
                        wrap,
                        filter,
                        space,
                        levels,
                        u,
                        v,
                        _mip_level(
                            u,
                            v,
                            along_x,
                            along_y,
                            Float32(width),
                            Float32(height),
                        ),
                    )
                red *= sampled.r
                green *= sampled.g
                blue *= sampled.b
                alpha *= sampled.a
        elif mode == Int32(SHADE_UV.value):
            # Coordinates, not light; written raw. See rasterize_shaded.
            # Texture coordinates straight out as red and green, matching
            # rasterize_shaded's SHADE_UV.
            red = (
                corners[unsafe_offset=base + LANE_U] * share_a
                + corners[unsafe_offset=b_base + LANE_U] * share_b
                + corners[unsafe_offset=c_base + LANE_U] * share_c
            )
            green = (
                corners[unsafe_offset=base + LANE_V] * share_a
                + corners[unsafe_offset=b_base + LANE_V] * share_b
                + corners[unsafe_offset=c_base + LANE_V] * share_c
            )
            blue = 0
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
            alpha = (
                corners[unsafe_offset=base + LANE_A] * share_a
                + corners[unsafe_offset=b_base + LANE_A] * share_b
                + corners[unsafe_offset=c_base + LANE_A] * share_c
            )
            red *= arriving.x
            green *= arriving.y
            blue *= arriving.z

        # Opaque replaces what is there; translucent mixes into it. One pass
        # is enough only because every opaque triangle is submitted before any
        # translucent one, so `nearest` is already final when the first
        # blended fragment arrives -- the same guarantee `rasterize_shaded`
        # relies on, and the reason `Renderer.prepare` sorts.
        found = True
        var share = alpha
        if share > 1:
            share = 1
        if share < 0:
            share = 0
        # Asked the way the host asks it -- "is it BLEND?" -- so anything
        # else is opaque on both sides rather than opaque on one.
        if maps[unsafe_offset=index * 3 + 1] != Int32(
            BLEND.value
        ) or mode == Int32(SHADE_UV.value):
            # Nothing behind contributes. The surface's own alpha is kept
            # rather than forced to one, so an opaque material drawn with a
            # partly transparent texture resolves partly transparent.
            mixed_r = red * share
            mixed_g = green * share
            mixed_b = blue * share
            mixed_a = share
            nearest = z
            solid = True
        else:
            # Source-over, premultiplied: a weighted sum with no special case.
            var keep = 1 - share
            mixed_r = red * share + mixed_r * keep
            mixed_g = green * share + mixed_g * keep
            mixed_b = blue * share + mixed_b * keep
            mixed_a = share + mixed_a * keep

    var word = background
    var nearest_depth = inf[DType.float32]()
    if found:
        # Unpremultiply, then encode. PNG stores unassociated alpha, and alpha
        # is coverage rather than colour so it skips the transfer function.
        var lit = FloatColor(
            mixed_r, mixed_g, mixed_b, mixed_a
        ).unpremultiplied()
        # SHADE_UV writes coordinates rather than light, so it is not encoded;
        # see rasterize_shaded.
        if mode == Int32(SHADE_UV.value):
            word = pack(lit.quantize())
        else:
            word = pack(lit.encode())
    if solid:
        nearest_depth = nearest

    # Every pixel is written, background included. Clearing on the host and
    # uploading that buffer would cost more than the render; letting each
    # thread decide its own colour costs nothing.
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
    # `__del__` releases them in that order. The order is load-bearing; see
    # `__del__` for the hang it prevents.
    var pixels: DeviceBuffer[DType.uint8]
    var depth: DeviceBuffer[DType.float32]
    var corners: DeviceBuffer[DType.float32]
    # Three floats of ambient, six per directional light and eight per point
    # light. Grown on demand like the corner buffer; a scene's lights rarely
    # change count, so this settles after the first frame.
    var lights: DeviceBuffer[DType.float32]
    var light_room: Int
    # One texture id per triangle, beside the vertex buffer rather than in it.
    var maps: DeviceBuffer[DType.int32]
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
    # Declared last so that it is released last. See `__del__`.
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
        _ = self.maps^
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
        # Room for the ambient term and one directional light to begin with.
        self.light_room = 9
        self.lights = self.context.enqueue_create_buffer[DType.float32](
            self.light_room
        )
        # One triangle to start with; `draw` grows it as needed. Never zero,
        # because a zero-length device buffer is not worth the special case.
        self.capacity = 1
        self.corners = self.context.enqueue_create_buffer[DType.float32](
            FLOATS_PER_TRIANGLE
        )
        self.maps = self.context.enqueue_create_buffer[DType.int32](3)
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

    def draw(
        mut self,
        corners: List[RasterVertex],
        background: Color,
        mode: ShadeMode = SHADE_LIT,
        lighting: Lighting = Lighting.uniform(),
    ) raises:
        """Rasterize prepared triangles into the device render target.

        Args:
            corners: Raster vertices, three per triangle. An empty list is
                allowed and clears the target to `background`.
            background: Colour for pixels no triangle covers.
            mode: `SHADE_LIT` or `SHADE_UV`, as `rasterize_shaded` takes.
            lighting: The scene's lights, resolved to world space and
                evaluated per fragment against the interpolated normal.
                Defaults to `Lighting.uniform`, the identity for the multiply,
                exactly as the CPU rasterizer's does.

        Raises:
            Error: If the corner count is not a multiple of three, the mode
                is none of the three, a triangle's blend policy or texture
                disagrees between its corners or is a value neither backend
                knows, or a vertex names a texture that is not uploaded.
        """
        if len(corners) % 3 != 0:
            raise Error("Rasterizing needs whole triangles")
        if not mode.is_valid():
            raise Error("A shading mode that is none of the three")
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

        # Every texture reference is checked here because it cannot be checked
        # on the device: the kernel reads the descriptor table at whatever
        # index a vertex hands it, and an index past the end is an unchecked
        # read of device memory. The CPU rasterizer gets this for free from
        # `TextureStore.get`, which raises; without this the two backends
        # failed differently on the same bad input.
        for index in range(len(corners)):
            var slot = corners[index].texture
            if slot == NO_TEXTURE:
                continue
            if slot.value < 0 or slot.value >= self.uploaded:
                raise Error(
                    "A vertex names a texture that has not been uploaded;"
                    " call set_textures() first"
                )

        if triangles > self.capacity:
            # Grow to exactly what is asked for. Frames tend to submit the
            # same count repeatedly, so this settles after the first one.
            self.corners = self.context.enqueue_create_buffer[DType.float32](
                triangles * FLOATS_PER_TRIANGLE
            )
            self.maps = self.context.enqueue_create_buffer[DType.int32](
                triangles * 3
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

        self._upload_lights(lighting)
        self.context.enqueue_function[rasterize_kernel](
            self.pixels.unsafe_ptr(),
            self.depth.unsafe_ptr(),
            self.corners.unsafe_ptr(),
            self.maps.unsafe_ptr(),
            Int32(triangles),
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
            Error: If a texture holds a wrap, filter or colour space that is
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

    def read_back(self) raises -> Framebuffer:
        """Copy the device render target into a host framebuffer.

        Both the colour and the depth come back, so the result is the same
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
) raises -> Framebuffer:
    """Draw prepared triangles on the GPU and read the image back.

    A convenience for one-shot renders. Anything drawing repeatedly should
    hold a `GpuRenderer` instead, so the context and buffers survive between
    frames rather than being rebuilt for each one.

    Args:
        corners: Raster vertices, three per triangle.
        width: Image width in pixels.
        height: Image height in pixels.
        background: Colour for pixels no triangle covers.
        mode: `SHADE_LIT`, `SHADE_UV` or `SHADE_TEXTURE`.
        textures: The images `SHADE_TEXTURE` samples, named per vertex.
        lighting: The scene's lights, evaluated per fragment. Defaults to
            `Lighting.uniform`, which leaves the corner colours alone.

    Returns:
        The rendered image.

    Raises:
        Error: If the dimensions are invalid, no GPU is present, or the
            corner count is not a multiple of three.
    """
    var renderer = GpuRenderer(width, height)
    renderer.set_textures(textures)
    renderer.draw(corners, background, mode, lighting)
    return renderer.read_back()


def render(
    triangle: Triangle,
    width: Int,
    height: Int,
    background: Color,
    foreground: Color,
) raises -> Framebuffer:
    """Rasterize one flat triangle on the GPU, in a single colour.

    The shape the benchmark and the parity tests use. Depth and perspective
    are neutral here — one triangle at a constant depth with no perspective —
    so this measures coverage and nothing else.

    Args:
        triangle: Screen-space triangle to fill.
        width: Image width in pixels.
        height: Image height in pixels.
        background: Colour for pixels the triangle does not cover.
        foreground: Colour for pixels it does.

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
