# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene voxelized into a lit volume: three.js r186's
`examples/jsm/lighting/vxgi/VXGIVolume.js`.

**The grid.** The longest axis of the bounds gets `resolution` voxels. Each
axis gets one more voxel on each side, and is rounded up to a multiple of
the coarsest level's step. The chain has up to eight levels, two fewer
than the powers of two in the resolution.

**Voxelization.** Each voxel has two by two by two sub-voxels. Each
triangle is projected along its dominant axis and rasterized
conservatively into sub-voxels: a column is covered when its center is
within half a sub-voxel of every edge, and the depth range of the
triangle's plane over the column is filled. A voxel keeps a bit for each
sub-voxel that a triangle covers, and the last triangle that covers it.

**Opacity.** A voxel's opacity along each axis is a quarter for each of
the four sub-voxel columns along that axis that holds a bit. Its
occupancy is an eighth for each bit. A coarser level combines its two
children along each axis, `1 - (1 - a)(1 - b)`, and averages across it.
The opacity is stored as eight-bit texels, as three.js's is.

**Light.** Each occupied voxel is lit by up to `max_lights` directional,
point and spot lights, through the plane of its last triangle. Each light
is seen through a cone traced toward it through the opacity. The voxel's
radiance is its albedo times the irradiance over pi, plus its emissive
color, times its occupancy. Each bounce traces eight cosine-weighted cones
from every occupied voxel through the radiance of the pass before, and
adds its albedo times their mean. The radiance is stored as half floats,
as three.js's is.

**Both backends.** `update` runs every pass on the host.
`render.gpu_vxgi.GpuVxgi` runs them on the device. Both call the functions
here for each voxel, so the two agree.

**Where this port differs.** three.js reads a light's shadow map when the
light casts a shadow. Here every light is seen through a traced cone, as
three.js sees a light without a map. three.js detects a changed light by a
key of its numbers rounded to a few places. Here any change is detected.
The directionally filtered radiance, `directionalRadiance`, is not ported.
"""

from core.assets import Assets
from core.layers import Layers
from core.object3d import NO_PARENT
from core.scene import Scene
from lights.light import DIRECTIONAL, POINT, SPOT, Light
from lights.lighting import falloff
from lights.vxgi_cone_tracer import (
    Lanes,
    UNBOUNDED,
    Untracked,
    VOXEL_FLOATS,
    VxgiGrid,
    cosine_direction,
    floats_of,
    fract,
    half_rounded,
    ints_of,
    pcg_hash,
    tangent_frame,
    trace_cone,
    unorm8,
    voxel_at,
)
from lights.vxgi_scene_collector import (
    MAX_EDGE_SUBVOXELS,
    TRIANGLE_STRIDE,
    collect_scene_triangles,
    compute_scene_bounds,
)
from math.bounds import Box3
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from std.math import ceil, cos, floor, isfinite, log2, pi, tan
from units.si import Angle, DEGREE, Length, METER


# Floats a light record holds, three.js's four `vec4`s a light.
comptime LIGHT_FLOATS = 16

# The cones a bounce traces from each voxel, three.js's
# `BOUNCE_CONE_COUNT`.
comptime BOUNCE_CONE_COUNT = 8

# The steps of a cone toward a light, three.js's `maxSteps: 256`.
comptime SHADOW_STEPS = 256

# The steps of any other cone, three.js's `maxSteps` default.
comptime CONE_STEPS = 128

# How far a cone starts from its voxel, in voxels, three.js's `1.5`.
comptime ORIGIN_OFFSET = Float32(1.5)

# The most levels a chain has, three.js's clamp to eight.
comptime MAX_LEVELS = 8

# The fewest voxels on the longest axis, three.js's `Math.max( 8, ... )`.
comptime MIN_RESOLUTION = 8

# three.js's `PI`, which the irradiance is divided by.
comptime VXGI_PI = Float32(3.141592653589793)


@fieldwise_init
struct VxgiLightType(Equatable, ImplicitlyCopyable, Writable):
    """Which kind of light a light record holds, three.js's `type` in the
    record's first `vec4`, as a type rather than a bare int.

    `light_record` refuses `VxgiLightType(3)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three kinds a volume injects."""
        return (
            self == VXGI_DIRECTIONAL or self == VXGI_POINT or self == VXGI_SPOT
        )


# A light infinitely far away, three.js's `0`.
comptime VXGI_DIRECTIONAL = VxgiLightType(0)
# A bulb, three.js's `1`.
comptime VXGI_POINT = VxgiLightType(1)
# A bulb within a cone, three.js's `2`.
comptime VXGI_SPOT = VxgiLightType(2)


def light_record(
    kind: VxgiLightType,
    position: Vector3,
    direction: Vector3,
    light: Light,
) raises -> List[Float32]:
    """Return the sixteen floats of one light, as three.js's
    `_collectLights` writes them.

    Args:
        kind: What the light is.
        position: Where it is, in the world.
        direction: Toward the light for a directional light, along the
            axis for a spot light, and zero for a point light.
        light: The light, for its color, intensity, distance, decay, angle
            and penumbra.

    Returns:
        The position and kind, the direction and cutoff distance, the
        radiance and decay, and the spot's two cosines.

    Raises:
        Error: If the kind is none of the three.
    """
    if not kind.is_valid():
        raise Error("A VXGI light must be directional, point or spot")
    var radiance = light.radiance()
    var distance = Float32(0)
    var decay = Float32(2)
    var outer = Float32(0)
    var inner = Float32(0)
    if kind != VXGI_DIRECTIONAL:
        distance = light.distance
        decay = light.decay
    if kind == VXGI_SPOT:
        outer = cos(light.angle.value)
        inner = cos(light.angle.value * (1 - light.penumbra))
    return [
        position.x,
        position.y,
        position.z,
        Float32(kind.value),
        direction.x,
        direction.y,
        direction.z,
        distance,
        radiance.r,
        radiance.g,
        radiance.b,
        decay,
        outer,
        inner,
        0,
        0,
    ]


# --- voxelization ------------------------------------------------------------


@fieldwise_init
struct _Edge(ImplicitlyCopyable):
    """One conservative edge function of a projected triangle."""

    var ax: Float32
    var ay: Float32
    var nx: Float32
    var ny: Float32
    var bias: Float32

    def reaches(self, cx: Float32, cy: Float32) -> Bool:
        """Return True if a point is within half a sub-voxel inside."""
        return self.nx * (cx - self.ax) + self.ny * (cy - self.ay) + (
            self.bias
        ) >= 0


def _edge(
    ax: Float32, ay: Float32, bx: Float32, by: Float32, area_sign: Float32
) -> _Edge:
    """Return the conservative edge from one projected corner to the next:
    three.js's `edge( a, b )`."""
    var nx = (ay - by) * area_sign
    var ny = (bx - ax) * area_sign
    return _Edge(ax, ay, nx, ny, Float32(0.5) * (abs(nx) + abs(ny)))


def _swizzled(
    is_z: Bool, is_y: Bool, x: Float32, y: Float32, z: Float32
) -> Tuple[Float32, Float32, Float32]:
    """Return a vector turned so its dominant axis is last: three.js's
    `select( isZ, v.xyz, select( isY, v.zxy, v.yzx ) )`."""
    if is_z:
        return (x, y, z)
    if is_y:
        return (z, x, y)
    return (y, z, x)


def _sign(value: Float32) -> Float32:
    """Return minus one, zero or one: WGSL's `sign`."""
    if value > 0:
        return 1
    if value < 0:
        return -1
    return 0


struct VoxelTriangle(ImplicitlyCopyable):
    """One triangle record set up for conservative voxelization, in
    sub-voxel space and turned so its dominant axis is `k`: the first half
    of three.js's `VXGI.Voxelize` kernel.

    The host walks its columns, three.js's loops. A kernel asks it of the
    eight sub-voxels of its own voxel. Both decide with `column`.
    """

    # Whether the triangle covers anything: its plane has a dominant axis.
    var usable: Bool
    var is_z: Bool
    var is_y: Bool
    # The first corner and the normal, turned.
    var q0x: Float32
    var q0y: Float32
    var q0z: Float32
    var nx: Float32
    var ny: Float32
    var nz: Float32
    var e0: _Edge
    var e1: _Edge
    var e2: _Edge
    # How far the plane runs along `k` across one column, each way.
    var half_extent: Float32
    var low_k: Float32
    var high_k: Float32
    # The columns of the triangle's box, and the last sub-voxel along `k`.
    var i0: Int
    var i1: Int
    var j0: Int
    var j1: Int
    var top_k: Int

    def __init__(
        out self,
        triangles: Pointer[Float32, Untracked],
        triangle: Int,
        grid: VxgiGrid,
    ):
        """Set up one record.

        Args:
            triangles: The records, `TRIANGLE_STRIDE` floats each.
            triangle: Which record.
            grid: The grid it is voxelized into.
        """
        var base = triangle * TRIANGLE_STRIDE
        var scale = Float32(2) / grid.voxel_size
        var low = grid.bounds_min
        var p0x = (triangles[unsafe_offset=base] - low.x) * scale
        var p0y = (triangles[unsafe_offset=base + 1] - low.y) * scale
        var p0z = (triangles[unsafe_offset=base + 2] - low.z) * scale
        var p1x = (triangles[unsafe_offset=base + 4] - low.x) * scale
        var p1y = (triangles[unsafe_offset=base + 5] - low.y) * scale
        var p1z = (triangles[unsafe_offset=base + 6] - low.z) * scale
        var p2x = (triangles[unsafe_offset=base + 8] - low.x) * scale
        var p2y = (triangles[unsafe_offset=base + 9] - low.y) * scale
        var p2z = (triangles[unsafe_offset=base + 10] - low.z) * scale
        var ux = p1x - p0x
        var uy = p1y - p0y
        var uz = p1z - p0z
        var vx = p2x - p0x
        var vy = p2y - p0y
        var vz = p2z - p0z
        var cx = uy * vz - uz * vy
        var cy = uz * vx - ux * vz
        var cz = ux * vy - uy * vx
        var ax = abs(cx)
        var ay = abs(cy)
        var az = abs(cz)
        self.is_z = az >= ax and az >= ay
        self.is_y = not self.is_z and ay >= ax
        var q0 = _swizzled(self.is_z, self.is_y, p0x, p0y, p0z)
        var q1 = _swizzled(self.is_z, self.is_y, p1x, p1y, p1z)
        var q2 = _swizzled(self.is_z, self.is_y, p2x, p2y, p2z)
        var n = _swizzled(self.is_z, self.is_y, cx, cy, cz)
        var sd = _swizzled(
            self.is_z,
            self.is_y,
            Float32(grid.size_x * 2),
            Float32(grid.size_y * 2),
            Float32(grid.size_z * 2),
        )
        self.q0x = q0[0]
        self.q0y = q0[1]
        self.q0z = q0[2]
        self.nx = n[0]
        self.ny = n[1]
        self.nz = n[2]
        # A triangle with no area has no dominant axis to divide by.
        self.usable = n[2] != 0
        var min_i = min(q0[0], min(q1[0], q2[0]))
        var max_i = max(q0[0], max(q1[0], q2[0]))
        var min_j = min(q0[1], min(q1[1], q2[1]))
        var max_j = max(q0[1], max(q1[1], q2[1]))
        self.low_k = min(q0[2], min(q1[2], q2[2]))
        self.high_k = max(q0[2], max(q1[2], q2[2]))
        self.i0 = max(Int(floor(min_i)), 0)
        self.i1 = min(Int(floor(max_i)), Int(sd[0]) - 1)
        self.j0 = max(Int(floor(min_j)), 0)
        self.j1 = min(Int(floor(max_j)), Int(sd[1]) - 1)
        self.top_k = Int(sd[2]) - 1
        var area_sign = _sign(n[2])
        self.e0 = _edge(q0[0], q0[1], q1[0], q1[1], area_sign)
        self.e1 = _edge(q1[0], q1[1], q2[0], q2[1], area_sign)
        self.e2 = _edge(q2[0], q2[1], q0[0], q0[1], area_sign)
        self.half_extent = Float32(0)
        if self.usable:
            self.half_extent = (
                Float32(0.5) * (abs(n[0]) + abs(n[1])) / abs(n[2])
            )

    def column(self, i: Int, j: Int) -> Tuple[Bool, Int, Int]:
        """Return whether a column is covered, and the sub-voxels along `k`
        that the plane fills in it.

        Args:
            i: The column's first coordinate, turned.
            j: Its second.

        Returns:
            Whether the column's center is inside every edge, and the first
            and last `k` filled.
        """
        var cx = Float32(i) + 0.5
        var cy = Float32(j) + 0.5
        var inside = (
            self.e0.reaches(cx, cy)
            and self.e1.reaches(cx, cy)
            and self.e2.reaches(cx, cy)
        )
        var depth = self.q0z - (
            self.nx * (cx - self.q0x) + self.ny * (cy - self.q0y)
        ) / self.nz
        var k0 = max(
            Int(floor(max(depth - self.half_extent, self.low_k))), 0
        )
        var k1 = min(
            Int(floor(min(depth + self.half_extent, self.high_k))), self.top_k
        )
        return (inside, k0, k1)

    def covers(self, sx: Int, sy: Int, sz: Int) -> Bool:
        """Return True if the triangle covers a sub-voxel: what the host's
        walk would set, asked of one sub-voxel.

        Args:
            sx: The sub-voxel's column.
            sy: Its row.
            sz: Its slice.

        Returns:
            Whether the sub-voxel's bit is set by this triangle.
        """
        if not self.usable:
            return False
        var i = sx
        var j = sy
        var k = sz
        if self.is_y:
            i = sz
            j = sx
            k = sy
        elif not self.is_z:
            i = sy
            j = sz
            k = sx
        if i < self.i0 or i > self.i1 or j < self.j0 or j > self.j1:
            return False
        var found = self.column(i, j)
        return found[0] and k >= found[1] and k <= found[2]

    def sub_voxel(self, i: Int, j: Int, k: Int) -> Tuple[Int, Int, Int]:
        """Return the sub-voxel a turned coordinate names: three.js's
        `select( isZ, ivec3( i, j, k ), select( isY, ivec3( j, k, i ),
        ivec3( k, i, j ) ) )`.

        Args:
            i: The first turned coordinate.
            j: The second.
            k: The dominant one.

        Returns:
            The sub-voxel's column, row and slice.
        """
        if self.is_z:
            return (i, j, k)
        if self.is_y:
            return (j, k, i)
        return (k, i, j)


def sub_voxel_bit(sx: Int, sy: Int, sz: Int) -> Int:
    """Return the bit a sub-voxel sets in its voxel's occupancy: three.js's
    `(s.x & 1) | (s.y & 1) << 1 | (s.z & 1) << 2`.

    Args:
        sx: The sub-voxel's column.
        sy: Its row.
        sz: Its slice.

    Returns:
        One bit of eight.
    """
    return 1 << ((sx & 1) | ((sy & 1) << 1) | ((sz & 1) << 2))


def voxel_bits(
    triangles: Pointer[Float32, Untracked],
    triangle_count: Int,
    grid: VxgiGrid,
    x: Int,
    y: Int,
    z: Int,
) -> Tuple[Int, Int]:
    """Return one voxel's occupancy and last triangle, asked of every
    triangle in turn: how a kernel voxelizes, a thread a voxel, where
    three.js's kernel runs a thread a triangle.

    Args:
        triangles: The records.
        triangle_count: How many there are.
        grid: The grid.
        x: The voxel's column.
        y: Its row.
        z: Its slice.

    Returns:
        The eight bits, and one more than the last triangle that set one,
        or zero.
    """
    var bits = 0
    var last = 0
    for triangle in range(triangle_count):
        var setup = VoxelTriangle(triangles, triangle, grid)
        var mine = 0
        for child in range(8):
            var sx = 2 * x + (child & 1)
            var sy = 2 * y + ((child >> 1) & 1)
            var sz = 2 * z + ((child >> 2) & 1)
            if setup.covers(sx, sy, sz):
                mine |= sub_voxel_bit(sx, sy, sz)
        if mine != 0:
            bits |= mine
            last = triangle + 1
    return (bits, last)


def _coverage(bits: Int, m0: Int, m1: Int, m2: Int, m3: Int) -> Float32:
    """Return a quarter for each of four masks that meets the bits."""
    var total = Float32(0)
    for mask in [m0, m1, m2, m3]:  # pragma: no branch
        if bits & mask != 0:
            total += 0.25
    return total


def occupied_share(bits: Int) -> Float32:
    """Return an eighth for each sub-voxel bit: three.js's
    `countOneBits( bits ) / 8`.

    Args:
        bits: The eight bits.

    Returns:
        The occupancy, zero to one.
    """
    var count = 0
    for bit in range(8):  # pragma: no branch
        count += (bits >> bit) & 1
    return Float32(count) / 8


def resolve_voxel(bits: Int) -> Lanes:
    """Return a voxel's opacity texel from its sub-voxel bits: three.js's
    `VXGI.Resolve` kernel.

    Args:
        bits: The eight bits.

    Returns:
        The opacity along x, y and z and the occupancy, as eight-bit
        texels.
    """
    return Lanes(
        unorm8(_coverage(bits, 0x03, 0x0C, 0x30, 0xC0)),
        unorm8(_coverage(bits, 0x05, 0x0A, 0x50, 0xA0)),
        unorm8(_coverage(bits, 0x11, 0x22, 0x44, 0x88)),
        unorm8(occupied_share(bits)),
    )


def _child(
    volume: Pointer[Float32, Untracked],
    grid: VxgiGrid,
    level: Int,
    x: Int,
    y: Int,
    z: Int,
    dx: Int,
    dy: Int,
    dz: Int,
) -> Lanes:
    """Return one of the eight voxels a coarser voxel covers, one level
    finer."""
    return voxel_at(
        volume, grid.index(level - 1, 2 * x + dx, 2 * y + dy, 2 * z + dz)
    )


def _combine(a: Float32, b: Float32) -> Float32:
    """Return two opacities one behind the other: `1 - (1 - a)(1 - b)`."""
    return 1 - (1 - a) * (1 - b)


def opacity_mip_voxel(
    opacity: Pointer[Float32, Untracked],
    grid: VxgiGrid,
    level: Int,
    x: Int,
    y: Int,
    z: Int,
) -> Lanes:
    """Return a voxel of a coarser opacity level: three.js's
    `VXGI.OpacityMip` kernel. Along each axis two children are combined,
    across it the four pairs are averaged.

    Args:
        opacity: The opacity chain, with the level below filled.
        grid: The grid.
        level: The level, one or more.
        x: The voxel's column.
        y: Its row.
        z: Its slice.

    Returns:
        The texel, eight-bit.
    """
    var along_x = Float32(0)
    var along_y = Float32(0)
    var along_z = Float32(0)
    for pair in range(4):  # pragma: no branch
        var a = pair >> 1
        var b = pair & 1
        along_x += _combine(
            _child(opacity, grid, level, x, y, z, 0, a, b)[0],
            _child(opacity, grid, level, x, y, z, 1, a, b)[0],
        )
        along_y += _combine(
            _child(opacity, grid, level, x, y, z, a, 0, b)[1],
            _child(opacity, grid, level, x, y, z, a, 1, b)[1],
        )
        along_z += _combine(
            _child(opacity, grid, level, x, y, z, a, b, 0)[2],
            _child(opacity, grid, level, x, y, z, a, b, 1)[2],
        )
    var occupied = Float32(0)
    for child in range(8):  # pragma: no branch
        occupied += _child(
            opacity,
            grid,
            level,
            x,
            y,
            z,
            child & 1,
            (child >> 1) & 1,
            (child >> 2) & 1,
        )[3]
    return Lanes(
        unorm8(along_x * 0.25),
        unorm8(along_y * 0.25),
        unorm8(along_z * 0.25),
        unorm8(occupied * 0.125),
    )


def radiance_mip_voxel(
    radiance: Pointer[Float32, Untracked],
    grid: VxgiGrid,
    level: Int,
    x: Int,
    y: Int,
    z: Int,
) -> Lanes:
    """Return a voxel of a coarser radiance level, the mean of its eight
    children: three.js's `VXGI.RadianceMip` kernel.

    Args:
        radiance: The radiance chain, with the level below filled.
        grid: The grid.
        level: The level, one or more.
        x: The voxel's column.
        y: Its row.
        z: Its slice.

    Returns:
        The texel, as half floats.
    """
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    var alpha = Float32(0)
    for child in range(8):  # pragma: no branch
        var texel = _child(
            radiance,
            grid,
            level,
            x,
            y,
            z,
            child & 1,
            (child >> 1) & 1,
            (child >> 2) & 1,
        )
        red += texel[0]
        green += texel[1]
        blue += texel[2]
        alpha += texel[3]
    return Lanes(
        half_rounded(red * 0.125),
        half_rounded(green * 0.125),
        half_rounded(blue * 0.125),
        half_rounded(alpha * 0.125),
    )


# --- light -------------------------------------------------------------------


@fieldwise_init
struct VoxelSurface(ImplicitlyCopyable):
    """What a voxel reads of its last triangle: three.js's `_surface`."""

    # The voxel's center, in the world.
    var position: Vector3
    # The triangle's unit normal, turned for a back side.
    var normal: Vector3
    var albedo: Vector3
    # Zero for the front, one for the back and two for both.
    var side: Float32
    var emissive: Vector3


def voxel_surface(
    triangles: Pointer[Float32, Untracked],
    grid: VxgiGrid,
    triangle_id: Int,
    x: Int,
    y: Int,
    z: Int,
) -> VoxelSurface:
    """Return the surface of a voxel's last triangle.

    Args:
        triangles: The records.
        grid: The grid.
        triangle_id: One more than the triangle's record.
        x: The voxel's column.
        y: Its row.
        z: Its slice.

    Returns:
        The surface.
    """
    var base = (triangle_id - 1) * TRIANGLE_STRIDE
    var a = Vector3(
        triangles[unsafe_offset=base],
        triangles[unsafe_offset=base + 1],
        triangles[unsafe_offset=base + 2],
    )
    var b = Vector3(
        triangles[unsafe_offset=base + 4],
        triangles[unsafe_offset=base + 5],
        triangles[unsafe_offset=base + 6],
    )
    var c = Vector3(
        triangles[unsafe_offset=base + 8],
        triangles[unsafe_offset=base + 9],
        triangles[unsafe_offset=base + 10],
    )
    var normal = b - a
    normal.cross(c - a)
    normal.normalize()
    var side = triangles[unsafe_offset=base + 15]
    if side == 1:
        normal = -normal
    return VoxelSurface(
        grid.center(x, y, z),
        normal,
        Vector3(
            triangles[unsafe_offset=base + 12],
            triangles[unsafe_offset=base + 13],
            triangles[unsafe_offset=base + 14],
        ),
        side,
        Vector3(
            triangles[unsafe_offset=base + 16],
            triangles[unsafe_offset=base + 17],
            triangles[unsafe_offset=base + 18],
        ),
    )


def _light_irradiance(
    grid: VxgiGrid,
    lights: Pointer[Float32, Untracked],
    light: Int,
    opacity: Pointer[Float32, Untracked],
    surface: VoxelSurface,
    shadow_tan: Float32,
) -> Vector3:
    """Return the irradiance one light gives a voxel's surface, seen
    through a cone toward it: one light's block of three.js's
    `VXGI.Inject` kernel."""
    var base = light * LIGHT_FLOATS
    var at = Vector3(
        lights[unsafe_offset=base],
        lights[unsafe_offset=base + 1],
        lights[unsafe_offset=base + 2],
    )
    var kind = lights[unsafe_offset=base + 3]
    var axis = Vector3(
        lights[unsafe_offset=base + 4],
        lights[unsafe_offset=base + 5],
        lights[unsafe_offset=base + 6],
    )
    var toward = axis
    var distance = UNBOUNDED
    var attenuation = Float32(1)
    if kind != Float32(VXGI_DIRECTIONAL.value):
        var between = at - surface.position
        distance = between.length()
        toward = between / distance
        attenuation = falloff(
            distance,
            lights[unsafe_offset=base + 11],
            lights[unsafe_offset=base + 7],
        )
        if kind == Float32(VXGI_SPOT.value):
            attenuation *= smoothstep(
                lights[unsafe_offset=base + 12],
                lights[unsafe_offset=base + 13],
                axis.dot(-toward),
            )
    var ndl = surface.normal.dot(toward)
    if surface.side == 2:
        ndl = abs(ndl)
    else:
        ndl = max(ndl, Float32(0))
    if not (ndl > 0 and attenuation > 0):
        return Vector3(0, 0, 0)
    var origin = surface.position + surface.normal * (
        grid.voxel_size * ORIGIN_OFFSET
    )
    var cone = trace_cone(
        grid,
        opacity,
        opacity,
        False,
        origin,
        toward,
        shadow_tan,
        distance - grid.voxel_size,
        0,
        False,
        SHADOW_STEPS,
    )
    var visibility = 1 - cone.alpha
    var scale = attenuation * ndl * visibility
    return Vector3(
        lights[unsafe_offset=base + 8] * scale,
        lights[unsafe_offset=base + 9] * scale,
        lights[unsafe_offset=base + 10] * scale,
    )


def inject_voxel(
    grid: VxgiGrid,
    triangles: Pointer[Float32, Untracked],
    lights: Pointer[Float32, Untracked],
    light_count: Int,
    opacity: Pointer[Float32, Untracked],
    bits: Int,
    triangle_id: Int,
    x: Int,
    y: Int,
    z: Int,
    shadow_tan: Float32,
) -> Lanes:
    """Return a voxel's direct radiance: three.js's `VXGI.Inject` kernel.

    Args:
        grid: The grid.
        triangles: The records.
        lights: The light records, `LIGHT_FLOATS` each.
        light_count: How many lights.
        opacity: The opacity chain, whole.
        bits: The voxel's sub-voxel bits.
        triangle_id: One more than its last triangle, or zero.
        x: The voxel's column.
        y: Its row.
        z: Its slice.
        shadow_tan: The tangent of half the aperture of a cone toward a
            light.

    Returns:
        The radiance times the occupancy, and the occupancy, as half
        floats. Zero for an empty voxel.
    """
    if bits == 0:
        return Lanes(0, 0, 0, 0)
    var surface = voxel_surface(triangles, grid, triangle_id, x, y, z)
    var irradiance = Vector3(0, 0, 0)
    for light in range(light_count):
        irradiance = irradiance + _light_irradiance(
            grid, lights, light, opacity, surface, shadow_tan
        )
    var occupied = occupied_share(bits)
    var red = surface.albedo.x * irradiance.x / VXGI_PI + surface.emissive.x
    var green = surface.albedo.y * irradiance.y / VXGI_PI + surface.emissive.y
    var blue = surface.albedo.z * irradiance.z / VXGI_PI + surface.emissive.z
    return Lanes(
        half_rounded(red * occupied),
        half_rounded(green * occupied),
        half_rounded(blue * occupied),
        half_rounded(occupied),
    )


def bounce_voxel(
    grid: VxgiGrid,
    triangles: Pointer[Float32, Untracked],
    direct: Pointer[Float32, Untracked],
    source: Pointer[Float32, Untracked],
    opacity: Pointer[Float32, Untracked],
    bits: Int,
    triangle_id: Int,
    x: Int,
    y: Int,
    z: Int,
    tan_half: Float32,
    trace_distance: Float32,
) -> Lanes:
    """Return a voxel's radiance with one more bounce: three.js's
    `VXGI.Bounce` kernel. Eight cosine-weighted cones, turned by a hash of
    the voxel, gather the radiance of the pass before.

    Args:
        grid: The grid.
        triangles: The records.
        direct: The direct radiance of level zero.
        source: The radiance chain of the pass before.
        opacity: The opacity chain.
        bits: The voxel's sub-voxel bits.
        triangle_id: One more than its last triangle, or zero.
        x: The voxel's column.
        y: Its row.
        z: Its slice.
        tan_half: The tangent of half a cone's aperture.
        trace_distance: How far a cone may reach.

    Returns:
        The direct radiance plus the albedo times the gathered light,
        times the occupancy, and the occupancy, as half floats. Zero for
        an empty voxel.
    """
    if bits == 0:
        return Lanes(0, 0, 0, 0)
    var surface = voxel_surface(triangles, grid, triangle_id, x, y, z)
    var index = grid.index(0, x, y, z)
    var own = voxel_at(direct, index)
    var frame = tangent_frame(surface.normal)
    var rotation = pcg_hash(UInt32(index))
    var origin = surface.position + surface.normal * (
        grid.voxel_size * ORIGIN_OFFSET
    )
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    for cone in range(BOUNCE_CONE_COUNT):  # pragma: no branch
        var u1 = (Float32(cone) + 0.5) / Float32(BOUNCE_CONE_COUNT)
        var u2 = fract(Float32(cone) * Float32(0.618034) + rotation)
        var direction = cosine_direction(
            frame[0], frame[1], surface.normal, u1, u2
        )
        var gathered = trace_cone(
            grid,
            opacity,
            source,
            True,
            origin,
            direction,
            tan_half,
            trace_distance,
            0,
            False,
            CONE_STEPS,
        )
        red += gathered.red
        green += gathered.green
        blue += gathered.blue
    var count = Float32(BOUNCE_CONE_COUNT)
    var bx = surface.albedo.x * (red / count)
    var by = surface.albedo.y * (green / count)
    var bz = surface.albedo.z * (blue / count)
    return Lanes(
        half_rounded(own[0] + bx * own[3]),
        half_rounded(own[1] + by * own[3]),
        half_rounded(own[2] + bz * own[3]),
        half_rounded(own[3]),
    )


def voxel_coordinates(index: Int, wide: Int, tall: Int) -> Tuple[Int, Int, Int]:
    """Return the column, row and slice of a voxel's place in its level:
    three.js's `_coords`.

    Args:
        index: The place, x fastest.
        wide: The level's voxels across.
        tall: Its voxels up.

    Returns:
        The column, the row and the slice.
    """
    return (index % wide, (index // wide) % tall, index // (wide * tall))


# --- the volume --------------------------------------------------------------


struct VXGIVolume(Movable):
    """A scene voxelized into a lit volume: three.js's `VXGIVolume`. See
    the module docstring."""

    # Voxels along the longest axis of the bounds, at least eight.
    var resolution: Int
    # The requested world bounds, or empty, the default, to fit the scene.
    var bounds: Box3
    # The bounds the grid covers, after `update`.
    var world_bounds: Box3
    # Only a node that shares one of these layers is voxelized.
    var layers: Layers
    # How many bounces the volume caches, three.js's `bounces`.
    var bounces: Int
    # A triangle less opaque than this is not voxelized.
    var min_opacity: Float32
    # The most lights the volume injects.
    var max_lights: Int
    # Set to voxelize the scene again at the next update.
    var needs_update: Bool
    # Set to light the volume again at the next update. A changed light
    # sets it by itself.
    var lighting_needs_update: Bool
    # How far a cone may reach, or zero, the default, for no limit.
    var max_distance: Length
    # How far a cone steps, in texels of the level it reads.
    var step_scale: Float32
    # The aperture of a cone toward a light, three.js's
    # `shadowConeAngle`.
    var shadow_cone_angle: Angle
    # The aperture of a bounce's cones, three.js's `bounceConeAngle`.
    var bounce_cone_angle: Angle
    # The grid of the last voxelization.
    var grid: VxgiGrid
    # The triangle records, `TRIANGLE_STRIDE` floats each.
    var triangles: List[Float32]
    # The light records, `LIGHT_FLOATS` floats each.
    var lights: List[Float32]
    # Each voxel of level zero: its sub-voxel bits and one more than its
    # last triangle.
    var occupancy: List[Int32]
    var triangle_ids: List[Int32]
    # The opacity chain and the radiance chain, four floats a voxel.
    var opacity: List[Float32]
    var radiance: List[Float32]
    # The direct radiance of level zero.
    var direct: List[Float32]
    var _allocated: Bool
    var _light_key: List[Float32]

    def __init__(out self, resolution: Int = 128):
        """Make a volume with three.js's defaults.

        Args:
            resolution: Voxels along the longest axis of the bounds.
        """
        self.resolution = resolution
        self.bounds = Box3.empty()
        self.world_bounds = Box3.empty()
        self.layers = Layers()
        self.bounces = 1
        self.min_opacity = 0.1
        self.max_lights = 8
        self.needs_update = True
        self.lighting_needs_update = True
        self.max_distance = Length(0.0, METER)
        self.step_scale = 0.5
        self.shadow_cone_angle = Angle(10.0, DEGREE)
        self.bounce_cone_angle = Angle(60.0, DEGREE)
        self.grid = VxgiGrid(
            Vector3(0, 0, 0), Vector3(1, 1, 1), 1, 1, 1, 1, 1, 0.5
        )
        self.triangles = List[Float32]()
        self.lights = List[Float32]()
        self.occupancy = List[Int32]()
        self.triangle_ids = List[Int32]()
        self.opacity = List[Float32]()
        self.radiance = List[Float32]()
        self.direct = List[Float32]()
        self._allocated = False
        self._light_key = List[Float32]()

    def validate(self) raises:
        """Refuse settings three.js's volume cannot use.

        Raises:
            Error: If the resolution is not positive, the bounces or the
                lights are negative, the minimum opacity or the step scale
                is not finite, the step scale is not positive, the distance
                is negative or not finite, or a cone's aperture is not
                between zero and a half turn.
        """
        if self.resolution <= 0:
            raise Error("A VXGI volume's resolution must be positive")
        if self.bounces < 0:
            raise Error("A VXGI volume's bounces cannot be negative")
        if self.max_lights < 0:
            raise Error("A VXGI volume's light count cannot be negative")
        if not isfinite(self.min_opacity):
            raise Error("A VXGI volume's minimum opacity must be finite")
        if not (isfinite(self.step_scale) and self.step_scale > 0):
            raise Error("A VXGI volume's step scale must be positive")
        if not (
            isfinite(self.max_distance.value) and self.max_distance.value >= 0
        ):
            raise Error("A VXGI volume's distance must be zero or more")
        _check_aperture(self.shadow_cone_angle, "shadow")
        _check_aperture(self.bounce_cone_angle, "bounce")

    def trace_distance(self) -> Float32:
        """Return how far a cone may reach: `max_distance`, or three.js's
        `1e10` when it is zero.

        Returns:
            The distance, in meters.
        """
        if self.max_distance.value > 0:
            return self.max_distance.value
        return UNBOUNDED

    def needs_voxels(self) -> Bool:
        """Return True if the next update voxelizes the scene.

        Returns:
            Whether `needs_update` is set or nothing is voxelized yet.
        """
        return self.needs_update or not self._allocated

    def prepare_voxels(mut self, scene: Scene, assets: Assets) raises:
        """Fit the grid to the bounds and collect the triangles: the host
        half of three.js's `_voxelize`, which both backends share. The
        occupancy, the triangles and the opacity are left empty for a
        backend to fill.

        Args:
            scene: The scene. It must be current.
            assets: Where its meshes' geometries, materials and textures
                are.

        Raises:
            Error: If the settings are refused by `validate`, the bounds
                have no size, or anything the collector raises.
        """
        self.validate()
        var bounds = self.bounds
        if bounds.is_empty():
            bounds = compute_scene_bounds(scene, assets, self.layers)
        if bounds.is_empty():
            bounds = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
        var size = bounds.size()
        var sx = Float64(size.x)
        var sy = Float64(size.y)
        var sz = Float64(size.z)
        var resolution = max(MIN_RESOLUTION, self.resolution)
        var voxel = max(sx, max(sy, sz)) / Float64(resolution)
        if not voxel > 0:
            raise Error("A VXGI volume's bounds must have a size")
        var levels = max(
            1, min(MAX_LEVELS, Int(floor(log2(Float64(resolution)))) - 2)
        )
        var multiple = 1 << (levels - 1)
        var gx = _padded(sx, voxel, multiple)
        var gy = _padded(sy, voxel, multiple)
        var gz = _padded(sz, voxel, multiple)
        levels = min(levels, Int(floor(log2(Float64(max(gx, gy))))) + 1)
        var low = Vector3(
            Float32(Float64(bounds.min.x) - voxel),
            Float32(Float64(bounds.min.y) - voxel),
            Float32(Float64(bounds.min.z) - voxel),
        )
        var extent = Vector3(
            Float32(Float64(gx) * voxel),
            Float32(Float64(gy) * voxel),
            Float32(Float64(gz) * voxel),
        )
        self.grid = VxgiGrid(
            low, extent, Float32(voxel), gx, gy, gz, levels, self.step_scale
        )
        self.world_bounds = Box3(low, low + extent)
        self.triangles = collect_scene_triangles(
            scene,
            assets,
            self.world_bounds,
            self.layers,
            Float32(voxel * 0.5),
            MAX_EDGE_SUBVOXELS,
            self.min_opacity,
        )
        var count = self.grid.level_count(0)
        self.occupancy = List[Int32](length=count, fill=0)
        self.triangle_ids = List[Int32](length=count, fill=0)
        self.opacity = List[Float32](
            length=self.grid.total() * VOXEL_FLOATS, fill=0
        )

    def triangle_count(self) -> Int:
        """Return how many triangle records the volume holds.

        Returns:
            The count.
        """
        return len(self.triangles) // TRIANGLE_STRIDE

    def voxelize(mut self):
        """Voxelize the collected triangles and build the opacity chain on
        the host: three.js's `VXGI.Clear`, `VXGI.Voxelize`, `VXGI.Resolve`
        and `VXGI.OpacityMip` kernels. `prepare_voxels` must run first.
        """
        var records = floats_of(self.triangles)
        for triangle in range(self.triangle_count()):
            var setup = VoxelTriangle(records, triangle, self.grid)
            if setup.usable:
                self._rasterize(setup, triangle)
        for index in range(self.grid.level_count(0)):
            var texel = resolve_voxel(Int(self.occupancy[index]))
            _store(self.opacity, index, texel)
        for level in range(1, self.grid.levels):
            _fill_opacity_level(self.opacity, self.grid, level)

    def _rasterize(mut self, setup: VoxelTriangle, triangle: Int):
        """Walk the columns of one triangle's box, three.js's loops."""
        for i in range(setup.i0, setup.i1 + 1):
            for j in range(setup.j0, setup.j1 + 1):
                var found = setup.column(i, j)
                if found[0]:
                    self._fill_column(setup, triangle, i, j, found[1], found[2])

    def _fill_column(
        mut self, setup: VoxelTriangle, triangle: Int, i: Int, j: Int, k0: Int, k1: Int
    ):
        """Set the bits of one covered column's sub-voxels."""
        for k in range(k0, k1 + 1):
            var s = setup.sub_voxel(i, j, k)
            var voxel = (
                s[0] // 2
                + self.grid.size_x * (s[1] // 2 + self.grid.size_y * (s[2] // 2))
            )
            self.occupancy[voxel] = self.occupancy[voxel] | Int32(
                sub_voxel_bit(s[0], s[1], s[2])
            )
            self.triangle_ids[voxel] = Int32(triangle + 1)

    def voxels_done(mut self):
        """Mark the scene voxelized, and the light out of date."""
        self.needs_update = False
        self.lighting_needs_update = True
        self._allocated = True

    def collect_lights(mut self, scene: Scene) raises -> Bool:
        """Write the light records, and return True if the light needs
        injecting again: three.js's `_collectLights` and its key.

        Args:
            scene: The scene. It must be current.

        Returns:
            Whether `lighting_needs_update` is set, or a light or a setting
            that shapes the light has changed since the last injection.

        Raises:
            Error: If the settings are refused by `validate`, or a light
                names a node that is not there.
        """
        self.validate()
        self.grid.step_scale = self.step_scale
        var records = List[Float32]()
        var count = 0
        for light in scene.lights:
            if count >= self.max_lights:
                break
            if not scene.light_shown(light):
                continue
            var kind: VxgiLightType
            if light.kind == DIRECTIONAL:
                kind = VXGI_DIRECTIONAL
            elif light.kind == POINT:
                kind = VXGI_POINT
            elif light.kind == SPOT:
                kind = VXGI_SPOT
            else:
                continue
            var position = scene.world_position(light.node)
            var direction = Vector3(0, 0, 0)
            if kind != VXGI_POINT:
                var target = Vector3(0, 0, 0)
                if light.target != NO_PARENT:
                    target = scene.world_position(light.target)
                if kind == VXGI_DIRECTIONAL:
                    direction = position - target
                else:
                    direction = target - position
                direction.normalize()
            records.extend(light_record(kind, position, direction, light))
            count += 1
        self.lights = records^
        var key = self.lights.copy()
        key.extend(
            [
                Float32(self.bounces),
                self.bounce_cone_angle.value,
                self.shadow_cone_angle.value,
                self.step_scale,
                self.max_distance.value,
            ]
        )
        var changed = key != self._light_key
        self._light_key = key^
        return self.lighting_needs_update or changed

    def light_count(self) -> Int:
        """Return how many light records the volume holds.

        Returns:
            The count.
        """
        return len(self.lights) // LIGHT_FLOATS

    def shadow_tan(self) -> Float32:
        """Return the tangent of half the aperture of a cone toward a light.

        Returns:
            The tangent.
        """
        return tan(self.shadow_cone_angle.value * 0.5)

    def bounce_tan(self) -> Float32:
        """Return the tangent of half the aperture of a bounce's cone.

        Returns:
            The tangent.
        """
        return tan(self.bounce_cone_angle.value * 0.5)

    def update_lighting(mut self):
        """Inject the light and cache the bounces on the host: three.js's
        `_updateLighting`, with its `VXGI.Inject`, `VXGI.RadianceMip` and
        `VXGI.Bounce` kernels. The volume must be voxelized.
        """
        var count = self.grid.level_count(0)
        var records = floats_of(self.triangles)
        var shining = floats_of(self.lights)
        var seen = floats_of(self.opacity)
        var bits = ints_of(self.occupancy)
        var ids = ints_of(self.triangle_ids)
        self.direct = List[Float32](length=count * VOXEL_FLOATS, fill=0)
        self.radiance = List[Float32](
            length=self.grid.total() * VOXEL_FLOATS, fill=0
        )
        var wide = self.grid.size_x
        var tall = self.grid.size_y
        var shadow = self.shadow_tan()
        for index in range(count):
            var at = voxel_coordinates(index, wide, tall)
            var texel = inject_voxel(
                self.grid,
                records,
                shining,
                self.light_count(),
                seen,
                Int(bits[unsafe_offset=index]),
                Int(ids[unsafe_offset=index]),
                at[0],
                at[1],
                at[2],
                shadow,
            )
            _store(self.direct, index, texel)
            _store(self.radiance, index, texel)
        _fill_radiance_levels(self.radiance, self.grid)
        for _ in range(self.bounces):
            self.radiance = self._bounced()

    def _bounced(self) -> List[Float32]:
        """Return the radiance chain with one more bounce."""
        var count = self.grid.level_count(0)
        var next = List[Float32](
            length=self.grid.total() * VOXEL_FLOATS, fill=0
        )
        var wide = self.grid.size_x
        var tall = self.grid.size_y
        var tan_half = self.bounce_tan()
        var reach = self.trace_distance()
        for index in range(count):
            var at = voxel_coordinates(index, wide, tall)
            var texel = bounce_voxel(
                self.grid,
                floats_of(self.triangles),
                floats_of(self.direct),
                floats_of(self.radiance),
                floats_of(self.opacity),
                Int(self.occupancy[index]),
                Int(self.triangle_ids[index]),
                at[0],
                at[1],
                at[2],
                tan_half,
                reach,
            )
            _store(next, index, texel)
        _fill_radiance_levels(next, self.grid)
        return next^

    def lighting_done(mut self):
        """Mark the light injected."""
        self.lighting_needs_update = False

    def update(mut self, scene: Scene, assets: Assets) raises:
        """Voxelize the scene if it needs it, and inject the light if it or
        a light changed, on the host: three.js's `update`.

        Args:
            scene: The scene. It must be current.
            assets: Where its meshes' geometries, materials and textures
                are.

        Raises:
            Error: Anything `prepare_voxels` or `collect_lights` raises.
        """
        if self.needs_voxels():
            self.prepare_voxels(scene, assets)
            self.voxelize()
            self.voxels_done()
        if self.collect_lights(scene):
            self.update_lighting()
            self.lighting_done()

    def opacity_at(self, level: Int, x: Int, y: Int, z: Int) -> Lanes:
        """Return one opacity texel, unchecked.

        Args:
            level: The level.
            x: The column, inside the level.
            y: The row.
            z: The slice.

        Returns:
            The opacity along x, y and z, and the occupancy.
        """
        return voxel_at(floats_of(self.opacity), self.grid.index(level, x, y, z))

    def radiance_at(self, level: Int, x: Int, y: Int, z: Int) -> Lanes:
        """Return one radiance texel, unchecked.

        Args:
            level: The level.
            x: The column, inside the level.
            y: The row.
            z: The slice.

        Returns:
            The radiance times the occupancy, and the occupancy.
        """
        return voxel_at(
            floats_of(self.radiance), self.grid.index(level, x, y, z)
        )


def _check_aperture(angle: Angle, what: String) raises:
    """Refuse a cone aperture that is not between zero and a half turn."""
    var degrees = angle.to(DEGREE)
    if not (isfinite(angle.value) and degrees > 0 and degrees < 180):
        raise Error(
            "A VXGI volume's " + what + " cone must open between 0 and 180"
            " degrees"
        )


def _padded(size: Float64, voxel: Float64, multiple: Int) -> Int:
    """Return an axis's voxel count: its size, one voxel each side, rounded
    up to the coarsest level's step."""
    var cells = ceil(size / voxel) + 2
    return Int(ceil(cells / Float64(multiple))) * multiple


def _store(mut volume: List[Float32], index: Int, texel: Lanes):
    """Write one voxel's four floats."""
    var at = index * VOXEL_FLOATS
    volume[at] = texel[0]
    volume[at + 1] = texel[1]
    volume[at + 2] = texel[2]
    volume[at + 3] = texel[3]


def _fill_opacity_level(mut opacity: List[Float32], grid: VxgiGrid, level: Int):
    """Fill one coarser opacity level from the one below."""
    var wide = grid.level_x(level)
    var tall = grid.level_y(level)
    var start = grid.level_start(level)
    for index in range(grid.level_count(level)):  # pragma: no branch
        var at = voxel_coordinates(index, wide, tall)
        var texel = opacity_mip_voxel(
            floats_of(opacity), grid, level, at[0], at[1], at[2]
        )
        _store(opacity, start + index, texel)


def _fill_radiance_levels(mut radiance: List[Float32], grid: VxgiGrid):
    """Fill every coarser radiance level, each from the one below."""
    for level in range(1, grid.levels):
        var wide = grid.level_x(level)
        var tall = grid.level_y(level)
        var start = grid.level_start(level)
        for index in range(grid.level_count(level)):  # pragma: no branch
            var at = voxel_coordinates(index, wide, tall)
            var texel = radiance_mip_voxel(
                floats_of(radiance), grid, level, at[0], at[1], at[2]
            )
            _store(radiance, start + index, texel)
