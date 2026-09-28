# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Voxel cone tracing, three.js r186's
`examples/jsm/lighting/vxgi/VXGIConeTracer.js`, and the voxel grid it
walks.

**The grid.** `VxgiGrid` holds where a `VXGIVolume` stands in the world
and how many voxels it has. A volume is one flat list of four floats a
voxel. Level zero comes first, then each level at half the size on every
axis, as a texture's mip chain does. Inside a level, x runs fastest, then
y, then z.

**Sampling.** `sample_volume` reads a volume as a 3D texture with
`LinearMipmapLinearFilter` and `ClampToEdgeWrapping` reads it: trilinear
in each of the two levels around the level of detail, and mixed between
them.

**The cone.** `trace_cone` walks a cone from its origin, one voxel out,
in steps of `step_scale` texels of the level its diameter reads. At each
step it reads the opacity, three per-axis values blended by the squared
direction, and corrects it for the step. It composites the radiance front
to back, and it stops when the cone is nearly opaque or leaves the volume.
It is Crassin et al.'s approximate voxel cone tracing, as three.js has it.

**Both backends.** Every function here reads its volumes through a
`Pointer[Float32, Untracked]`. The host points one at a list, and a GPU
kernel points one at a device buffer. `render.gpu_vxgi` runs the same
functions on the device, so the two agree.
"""

from math.vector3 import Vector3
from std.math import cos, exp2, floor, log2, pow, sin, sqrt
from std.memory import bitcast


# A pointer the compiler does not track: whoever makes one keeps the memory
# alive for as long as it is read. See `postprocessing.sampling.LightView`.
comptime Untracked = UntrackedOrigin[mut=False]

# Four floats a voxel: red, green, blue and alpha, or three opacities and
# the occupancy.
comptime VOXEL_FLOATS = 4

# How many floats `VxgiGrid.header` holds.
comptime VXGI_HEADER = 12

# `intersectVolume`'s floor on a direction component.
comptime DIRECTION_FLOOR = Float32(1e-6)

# The alpha at which a cone stops, three.js's `0.98`.
comptime OPAQUE_ENOUGH = Float32(0.98)

# The weight a radiance sample is divided by at least, three.js's `1e-4`.
comptime WEIGHT_FLOOR = Float32(1e-4)

# three.js's `aoDistance` floor.
comptime AO_DISTANCE_FLOOR = Float32(1e-6)

# The distance an unbounded cone may reach, three.js's `1e10`.
comptime UNBOUNDED = Float32(1e10)

# The golden-ratio step that turns cone directions, three.js's `0.618034`.
comptime GOLDEN_STEP = Float32(0.618034)

# The two-pi of three.js's `PI.mul( 2 )`.
comptime TWO_PI = Float32(6.283185307179586)

# The largest `|n.y|` for which the tangent frame starts from `+y`.
comptime UP_LIMIT = Float32(0.99)

comptime Lanes = SIMD[DType.float32, 4]


def floats_of(values: List[Float32]) -> Pointer[Float32, Untracked]:
    """Return a pointer to the floats of a list, for the functions here.

    Args:
        values: The floats. The list must outlive every read.

    Returns:
        The pointer to the first float.
    """
    return (
        values.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )


def ints_of(values: List[Int32]) -> Pointer[Int32, Untracked]:
    """Return a pointer to the integers of a list, for the functions here.

    Args:
        values: The integers. The list must outlive every read.

    Returns:
        The pointer to the first integer.
    """
    return (
        values.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[Untracked]()
    )


struct VxgiGrid(ImplicitlyCopyable):
    """Where a voxel volume stands and how it is divided: three.js's
    `boundsMinNode`, `volumeSizeNode`, `voxelSizeNode`, `_gridSize`,
    `_levels` and `stepScale`."""

    # The volume's lowest corner, in meters.
    var bounds_min: Vector3
    # The volume's size on each axis, in meters: the voxel counts times
    # the voxel size, as the host works it out.
    var volume_size: Vector3
    # The edge of one voxel of level zero, in meters.
    var voxel_size: Float32
    # How many voxels level zero has on each axis.
    var size_x: Int
    var size_y: Int
    var size_z: Int
    # How many levels the chain holds, at least one.
    var levels: Int
    # How far a cone steps, in texels of the level it reads.
    var step_scale: Float32

    def __init__(
        out self,
        bounds_min: Vector3,
        volume_size: Vector3,
        voxel_size: Float32,
        size_x: Int,
        size_y: Int,
        size_z: Int,
        levels: Int,
        step_scale: Float32,
    ):
        """Describe a grid.

        Args:
            bounds_min: The lowest corner.
            volume_size: The size on each axis.
            voxel_size: The edge of one voxel.
            size_x: Voxels across.
            size_y: Voxels up.
            size_z: Voxels deep.
            levels: How many levels the chain holds.
            step_scale: How far a cone steps, in texels.
        """
        self.bounds_min = bounds_min
        self.volume_size = volume_size
        self.voxel_size = voxel_size
        self.size_x = size_x
        self.size_y = size_y
        self.size_z = size_z
        self.levels = levels
        self.step_scale = step_scale

    def __init__(out self, *, header: Pointer[Float32, Untracked]):
        """Read a grid back from the floats `header` wrote: how a kernel
        gets one.

        Args:
            header: The first of `VXGI_HEADER` floats.
        """
        self.bounds_min = Vector3(
            header[unsafe_offset=0],
            header[unsafe_offset=1],
            header[unsafe_offset=2],
        )
        self.volume_size = Vector3(
            header[unsafe_offset=3],
            header[unsafe_offset=4],
            header[unsafe_offset=5],
        )
        self.voxel_size = header[unsafe_offset=6]
        self.size_x = Int(header[unsafe_offset=7])
        self.size_y = Int(header[unsafe_offset=8])
        self.size_z = Int(header[unsafe_offset=9])
        self.levels = Int(header[unsafe_offset=10])
        self.step_scale = header[unsafe_offset=11]

    def header(self) -> List[Float32]:
        """Return the grid as `VXGI_HEADER` floats, for a kernel.

        Returns:
            The corner, the size, the voxel size, the three counts, the
            levels and the step scale.
        """
        return [
            self.bounds_min.x,
            self.bounds_min.y,
            self.bounds_min.z,
            self.volume_size.x,
            self.volume_size.y,
            self.volume_size.z,
            self.voxel_size,
            Float32(self.size_x),
            Float32(self.size_y),
            Float32(self.size_z),
            Float32(self.levels),
            self.step_scale,
        ]

    def max_level(self) -> Float32:
        """Return the highest level a cone reads, three.js's
        `maxLevelNode`.

        Returns:
            The level, as a float.
        """
        return Float32(self.levels - 1)

    def level_x(self, level: Int) -> Int:
        """Return how many voxels a level has across.

        Args:
            level: The level.

        Returns:
            The count.
        """
        return self.size_x >> level

    def level_y(self, level: Int) -> Int:
        """Return how many voxels a level has up.

        Args:
            level: The level.

        Returns:
            The count.
        """
        return self.size_y >> level

    def level_z(self, level: Int) -> Int:
        """Return how many voxels a level has deep.

        Args:
            level: The level.

        Returns:
            The count.
        """
        return self.size_z >> level

    def level_count(self, level: Int) -> Int:
        """Return how many voxels a level has.

        Args:
            level: The level.

        Returns:
            The count.
        """
        return self.level_x(level) * self.level_y(level) * self.level_z(level)

    def level_start(self, level: Int) -> Int:
        """Return the voxel a level starts at, in the flat chain.

        Args:
            level: The level, up to `levels` for the chain's end.

        Returns:
            The voxels of every level before it.
        """
        var start = 0
        for below in range(level):
            start += self.level_count(below)
        return start

    def total(self) -> Int:
        """Return how many voxels the whole chain holds.

        Returns:
            The count.
        """
        return self.level_start(self.levels)

    def index(self, level: Int, x: Int, y: Int, z: Int) -> Int:
        """Return a voxel's place in the flat chain.

        Args:
            level: The level.
            x: The column, inside the level.
            y: The row, inside the level.
            z: The slice, inside the level.

        Returns:
            The voxel's index: its floats start at four times it.
        """
        var wide = self.level_x(level)
        var tall = self.level_y(level)
        return self.level_start(level) + x + wide * (y + tall * z)

    def center(self, x: Int, y: Int, z: Int) -> Vector3:
        """Return the world point at the center of a voxel of level zero:
        `boundsMin + (coords + 0.5) * voxelSize`.

        Args:
            x: The column.
            y: The row.
            z: The slice.

        Returns:
            The point, in meters.
        """
        return self.bounds_min + Vector3(
            (Float32(x) + 0.5) * self.voxel_size,
            (Float32(y) + 0.5) * self.voxel_size,
            (Float32(z) + 0.5) * self.voxel_size,
        )


def voxel_at(volume: Pointer[Float32, Untracked], index: Int) -> Lanes:
    """Return the four floats of a voxel.

    Args:
        volume: The volume's floats.
        index: The voxel's place in the chain.

    Returns:
        Its four floats.
    """
    var at = index * VOXEL_FLOATS
    return Lanes(
        volume[unsafe_offset=at],
        volume[unsafe_offset=at + 1],
        volume[unsafe_offset=at + 2],
        volume[unsafe_offset=at + 3],
    )


def _axis(coordinate: Float32, extent: Int) -> Tuple[Int, Int, Float32]:
    """Return the two texels a coordinate falls between on one axis,
    clamped to the edge, and how far it is past the first."""
    # Past the volume the edge texel is read, so a far coordinate is held
    # first: an integer cannot hold every float.
    var texel = max(Float32(-1), min(Float32(extent), coordinate))
    var low = floor(texel)
    var fraction = texel - low
    var first = Int(low)
    var second = first + 1
    first = max(0, min(extent - 1, first))
    second = max(0, min(extent - 1, second))
    return (first, second, fraction)


def sample_level(
    volume: Pointer[Float32, Untracked],
    grid: VxgiGrid,
    uvw: Vector3,
    level: Int,
) -> Lanes:
    """Return a volume read at one level, trilinear and clamped to the
    edge, as a 3D texture's `LinearFilter` reads it.

    Args:
        volume: The volume's floats.
        grid: The grid.
        uvw: Where, from zero to one on each axis.
        level: The level, inside the chain.

    Returns:
        The blend of the eight voxels around the point.
    """
    var wide = grid.level_x(level)
    var tall = grid.level_y(level)
    var deep = grid.level_z(level)
    var ax = _axis(uvw.x * Float32(wide) - 0.5, wide)
    var ay = _axis(uvw.y * Float32(tall) - 0.5, tall)
    var az = _axis(uvw.z * Float32(deep) - 0.5, deep)
    var start = grid.level_start(level)
    var row0 = wide * (ay[0] + tall * az[0])
    var row1 = wide * (ay[1] + tall * az[0])
    var row2 = wide * (ay[0] + tall * az[1])
    var row3 = wide * (ay[1] + tall * az[1])
    var c000 = voxel_at(volume, start + row0 + ax[0])
    var c100 = voxel_at(volume, start + row0 + ax[1])
    var c010 = voxel_at(volume, start + row1 + ax[0])
    var c110 = voxel_at(volume, start + row1 + ax[1])
    var c001 = voxel_at(volume, start + row2 + ax[0])
    var c101 = voxel_at(volume, start + row2 + ax[1])
    var c011 = voxel_at(volume, start + row3 + ax[0])
    var c111 = voxel_at(volume, start + row3 + ax[1])
    var fx = ax[2]
    var fy = ay[2]
    var fz = az[2]
    var x00 = c000 + (c100 - c000) * fx
    var x10 = c010 + (c110 - c010) * fx
    var x01 = c001 + (c101 - c001) * fx
    var x11 = c011 + (c111 - c011) * fx
    var y0 = x00 + (x10 - x00) * fy
    var y1 = x01 + (x11 - x01) * fy
    return y0 + (y1 - y0) * fz


def sample_volume(
    volume: Pointer[Float32, Untracked],
    grid: VxgiGrid,
    uvw: Vector3,
    lod: Float32,
) -> Lanes:
    """Return a volume read at a level of detail, as a 3D texture's
    `LinearMipmapLinearFilter` reads it: trilinear in the level below and
    the level above, mixed by the fraction.

    Args:
        volume: The volume's floats.
        grid: The grid.
        uvw: Where, from zero to one on each axis.
        lod: The level of detail. It is held inside the chain.

    Returns:
        The blend.
    """
    var held = max(Float32(0), min(grid.max_level(), lod))
    var base = floor(held)
    var fraction = held - base
    var low = Int(base)
    var near = sample_level(volume, grid, uvw, low)
    if fraction <= 0:
        return near
    # A fraction above zero leaves the level below the top, so the one
    # above it is in the chain.
    var far = sample_level(volume, grid, uvw, low + 1)
    return near + (far - near) * fraction


def intersect_volume(
    grid: VxgiGrid, origin: Vector3, direction: Vector3
) -> Tuple[Float32, Float32]:
    """Return where a ray enters and leaves the volume: three.js's
    `intersectVolume`. The ray misses when the exit is not past the entry.

    Args:
        grid: The grid.
        origin: The ray's origin.
        direction: The ray's unit direction.

    Returns:
        The distance of the entry, zero or more, and of the exit.
    """
    var high = grid.bounds_min + grid.volume_size
    var dx = direction.x
    var dy = direction.y
    var dz = direction.z
    if abs(dx) < DIRECTION_FLOOR:
        dx = DIRECTION_FLOOR
    if abs(dy) < DIRECTION_FLOOR:
        dy = DIRECTION_FLOOR
    if abs(dz) < DIRECTION_FLOOR:
        dz = DIRECTION_FLOOR
    var ix = 1 / dx
    var iy = 1 / dy
    var iz = 1 / dz
    var ax = (grid.bounds_min.x - origin.x) * ix
    var ay = (grid.bounds_min.y - origin.y) * iy
    var az = (grid.bounds_min.z - origin.z) * iz
    var bx = (high.x - origin.x) * ix
    var by = (high.y - origin.y) * iy
    var bz = (high.z - origin.z) * iz
    var enter = max(max(min(ax, bx), min(ay, by)), max(min(az, bz), Float32(0)))
    var leave = min(min(max(ax, bx), max(ay, by)), max(az, bz))
    return (enter, leave)


@fieldwise_init
struct Cone(ImplicitlyCopyable):
    """What a cone gathers: three.js's `{ color, alpha, ao }`."""

    # The radiance, composited front to back.
    var red: Float32
    var green: Float32
    var blue: Float32
    # How much of the cone is blocked, zero to one.
    var alpha: Float32
    # The occlusion weighed by distance, for ambient occlusion.
    var ao: Float32


def trace_cone(
    grid: VxgiGrid,
    opacity: Pointer[Float32, Untracked],
    radiance: Pointer[Float32, Untracked],
    gathers: Bool,
    origin: Vector3,
    direction: Vector3,
    tan_half_angle: Float32,
    max_distance: Float32,
    ao_distance: Float32,
    occludes: Bool,
    max_steps: Int,
) -> Cone:
    """March one cone through a volume: the function three.js's
    `createConeTracer` returns.

    Args:
        grid: The grid.
        opacity: The opacity chain.
        radiance: The radiance chain. Read only when `gathers`.
        gathers: Whether the cone gathers radiance, three.js's
            `radianceNode`. Without it, only the occlusion is found.
        origin: Where the cone starts.
        direction: Its unit direction.
        tan_half_angle: The tangent of half its aperture.
        max_distance: How far it may reach, in meters.
        ao_distance: The distance at which an occluder counts half.
            Zero or less gives no falloff.
        occludes: Whether to find the ambient occlusion, three.js's
            `aoDistance !== null`.
        max_steps: The most steps it takes.

    Returns:
        The radiance, the alpha and the occlusion.
    """
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    var alpha = Float32(0)
    var ao = Float32(0)
    var span = intersect_volume(grid, origin, direction)
    # A cone starts one voxel out, so the voxels its origin lies in are
    # not read.
    var t = max(span[0], grid.voxel_size)
    var limit = min(span[1], max_distance)
    var wx = direction.x * direction.x
    var wy = direction.y * direction.y
    var wz = direction.z * direction.z
    var ao_falloff = Float32(0)
    if occludes and ao_distance > 0:
        ao_falloff = 1 / max(ao_distance, AO_DISTANCE_FLOOR)
    if span[1] > t:
        for _ in range(max_steps):
            if t >= limit or alpha >= OPAQUE_ENOUGH:
                break
            var diameter = max(t * 2 * tan_half_angle, grid.voxel_size)
            var lod = max(
                Float32(0),
                min(grid.max_level(), log2(diameter / grid.voxel_size)),
            )
            var point = origin + direction * t
            var uvw = Vector3(
                (point.x - grid.bounds_min.x) / grid.volume_size.x,
                (point.y - grid.bounds_min.y) / grid.volume_size.y,
                (point.z - grid.bounds_min.z) / grid.volume_size.z,
            )
            var seen = sample_volume(opacity, grid, uvw, lod)
            var along = seen[0] * wx + seen[1] * wy + seen[2] * wz
            along = max(Float32(0), min(Float32(1), along))
            var a = 1 - pow(1 - along, grid.step_scale)
            var weight = a * (1 - alpha)
            if gathers:
                var light = sample_volume(radiance, grid, uvw, lod)
                var share = max(light[3], WEIGHT_FLOOR)
                red += light[0] / share * weight
                green += light[1] / share * weight
                blue += light[2] / share * weight
            alpha += weight
            if occludes:
                ao += a * (1 - ao) / (t * ao_falloff + 1)
            t += grid.voxel_size * exp2(lod) * grid.step_scale
    return Cone(red, green, blue, alpha, ao)


def pcg_hash(seed: UInt32) -> Float32:
    """Return a number from zero to one for a seed: three.js's TSL `hash`,
    the PCG hash of shadertoy's `XlGcRh`.

    Args:
        seed: The seed.

    Returns:
        The hash, scaled to zero through one.
    """
    var state = seed * 747796405 + 2891336453
    var word = ((state >> ((state >> 28) + 4)) ^ state) * 277803737
    var result = (word >> 22) ^ word
    return Float32(result) * Float32(2.3283064365386963e-10)


def fract(value: Float32) -> Float32:
    """Return what is left of a number past its floor: GLSL's `fract`.

    Args:
        value: The number.

    Returns:
        The fraction, zero to one.
    """
    return value - floor(value)


def interleaved_gradient_noise(x: Float32, y: Float32) -> Float32:
    """Return Jimenez's interleaved gradient noise at a point: three.js's
    TSL `interleavedGradientNoise`.

    Args:
        x: The point's column, in pixels.
        y: The point's row, in pixels.

    Returns:
        The noise, zero to one.
    """
    return fract(
        Float32(52.9829189)
        * fract(x * Float32(0.06711056) + y * Float32(0.00583715))
    )


def tangent_frame(normal: Vector3) -> Tuple[Vector3, Vector3]:
    """Return two directions square to a normal and to each other, as
    three.js's VXGI builds its cones' frame: from `+y`, or from `+x` when
    the normal is nearly vertical.

    Args:
        normal: The unit normal.

    Returns:
        The tangent and the bitangent.
    """
    var up = Vector3(0, 1, 0)
    if abs(normal.y) >= UP_LIMIT:
        up = Vector3(1, 0, 0)
    var tangent = normal
    tangent.cross(up)
    tangent.normalize()
    var bitangent = normal
    bitangent.cross(tangent)
    return (tangent, bitangent)


def cosine_direction(
    tangent: Vector3,
    bitangent: Vector3,
    normal: Vector3,
    u1: Float32,
    u2: Float32,
) -> Vector3:
    """Return a direction of a cosine-weighted hemisphere: three.js's
    `sinTheta = sqrt(u1)`, `cosTheta = sqrt(1 - u1)`, `phi = 2 pi u2`.

    Args:
        tangent: The frame's first axis.
        bitangent: Its second.
        normal: Its pole.
        u1: How far from the pole, zero to one.
        u2: How far around, zero to one.

    Returns:
        The unit direction.
    """
    var sin_theta = sqrt(u1)
    var cos_theta = sqrt(1 - u1)
    var phi = u2 * TWO_PI
    var direction = (
        tangent * (cos(phi) * sin_theta)
        + bitangent * (sin(phi) * sin_theta)
        + normal * cos_theta
    )
    direction.normalize()
    return direction


def unorm8(value: Float32) -> Float32:
    """Return a number as an eight-bit unsigned-normalized texel holds it:
    three.js's `UnsignedByteType` opacity texture.

    Args:
        value: The number.

    Returns:
        The nearest of the 256 steps from zero to one.
    """
    var held = max(Float32(0), min(Float32(1), value))
    return floor(held * 255 + 0.5) / 255


def half_rounded(value: Float32) -> Float32:
    """Return a number as a half-float texel holds it: three.js's
    `HalfFloatType` radiance texture, rounded to the nearest half, ties to
    even, as a GPU stores it.

    Args:
        value: The number.

    Returns:
        The nearest half: an infinity past the largest, 65504, and a zero
        below the smallest.
    """
    var bits = bitcast[DType.uint32](value)
    var sign = bits & 0x80000000
    var magnitude = bits & 0x7FFFFFFF
    if magnitude >= 0x7F800000:
        # An infinity or a number that is not a number stays itself.
        return value
    if magnitude >= 0x477FF000:
        # 65520 and above round past the largest half.
        return bitcast[DType.float32](sign | 0x7F800000)
    var exponent = Int(magnitude >> 23)
    if exponent >= 113:
        # A normal half keeps ten bits of fraction.
        var odd = (magnitude >> 13) & 1
        var rounded = (magnitude + 0xFFF + odd) & 0xFFFFE000
        return bitcast[DType.float32](sign | rounded)
    if exponent < 102:
        # Below half the smallest half: a zero with the sign.
        return bitcast[DType.float32](sign)
    # A subnormal half: a whole number of 2^-24.
    var fraction = Int((magnitude & 0x7FFFFF) | 0x800000)
    var shift = 126 - exponent
    var kept = fraction >> shift
    var rest = fraction & ((1 << shift) - 1)
    var middle = 1 << (shift - 1)
    if rest > middle or (rest == middle and (kept & 1) == 1):
        kept += 1
    var result = Float32(kept) * Float32(5.9604644775390625e-8)
    if sign != 0:
        return -result
    return result
