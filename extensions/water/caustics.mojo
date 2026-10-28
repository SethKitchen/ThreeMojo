# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refracted-grid caustics, the method Clearwater takes from Evan Wallace.

Each water cell is refracted along the sun onto the bed, once per color,
because the index changes. The flat-surface shift of the green channel is
removed so the pattern stays registered. What remains is dispersion.
The shader reads the texture through `CausticTexels`, so the same
arithmetic runs on a `CausticField` and on a copy in device memory.
"""

from core.ordinal import require_positive
from extensions.water.optics import channel_ior, refract
from extensions.water.rows import row_tasks
from extensions.water.spectrum import require_ocean_patch
from extensions.water.surface import SurfaceField, sample_surface
from math.utils import max3, min3
from math.vector3 import Vector3
from render.tasks import TaskGroup
from math.norm import squared_length3
from std.math import abs, floor, hypot, isfinite, sqrt
from units.si import Length

# Clearwater caps unresolved point focusing rather than emitting infinite light.
comptime MAX_CAUSTIC_INTENSITY = Float32(40.0)
# Clamp the flat-surface registration at grazing sun angles, as upstream does.
comptime MIN_SUN_Y = Float32(0.05)


trait CausticTexels:
    """Read access to a caustic texture and its mipmaps.

    Level 0 is the base texture. Level `k` is the `k`th coarser mip.
    """

    def caustic_patch(self) -> Float32:
        """Return the ocean patch length the texture tiles, in meters.

        Returns:
            The patch length.
        """
        ...

    def caustic_shift_x(self) -> Float32:
        """Return the x registration shift, in meters.

        Returns:
            The flat-surface shift along x.
        """
        ...

    def caustic_shift_z(self) -> Float32:
        """Return the z registration shift, in meters.

        Returns:
            The flat-surface shift along z.
        """
        ...

    def caustic_levels(self) -> Int:
        """Return how many mip levels follow the base texture.

        Returns:
            The count of coarser levels.
        """
        ...

    def caustic_side(self, level: Int) -> Int:
        """Return the texels on one side of a level.

        Args:
            level: The level. Zero or less is the base texture.

        Returns:
            The side length.
        """
        ...

    def caustic_channel(self, level: Int, x: Int, y: Int, c: Int) -> Float32:
        """Return one channel of one texel of a level.

        Args:
            level: The level. Zero or less is the base texture.
            x: Column inside that level.
            y: Row inside that level.
            c: 0 red, 1 green, 2 blue.

        Returns:
            The stored intensity.
        """
        ...


struct CausticField(CausticTexels, Movable):
    """A square caustic texture, three additive channels."""

    var n: Int
    var patch: Float32
    var samples: List[Float32]
    var shift_x: Float32
    var shift_z: Float32
    var mip_n: List[Int]
    var mip_off: List[Int]
    var mip_px: List[Float32]

    def __init__(out self, n: Int, patch: Length) raises:
        """Allocate a black texture.

        Args:
            n: Texels on one side. It must be positive.
            patch: The ocean patch length.

        Raises:
            Error: If `n` is not positive, the patch is not positive, or
                the texel buffer does not fit in an integer.
        """
        require_positive(n, "Caustic resolution must be positive")
        require_ocean_patch(patch.value)
        # Three floats a texel. A side past 2^31 wraps that product, so
        # the texture looks empty.
        if n > (Int.MAX // 3) // n:
            raise Error("A caustic texture is larger than this port builds")
        self.n = n
        self.patch = patch.value
        self.samples = List[Float32](length=n * n * 3, fill=0.0)
        self.shift_x = 0.0
        self.shift_z = 0.0
        self.mip_n = List[Int]()
        self.mip_off = List[Int]()
        self.mip_px = List[Float32]()

    def channel(self, x: Int, y: Int, c: Int) -> Float32:
        """Return one texel of one color.

        Args:
            x: Column.
            y: Row.
            c: 0 red, 1 green, 2 blue.

        Returns:
            The summed intensity.
        """
        return self.samples[(y * self.n + x) * 3 + c]

    def level_channel(self, level: Int, x: Int, y: Int, c: Int) -> Float32:
        """Return one channel of one mip texel.

        Args:
            level: 0 is the base texture. Larger values are coarser.
            x: Column inside that level.
            y: Row inside that level.
            c: 0 red, 1 green, 2 blue.

        Returns:
            The stored intensity.
        """
        if level <= 0:
            return self.channel(x, y, c)
        var w = self.mip_n[level - 1]
        var at = self.mip_off[level - 1] + (y * w + x) * 3 + c
        return self.mip_px[at]

    def caustic_patch(self) -> Float32:
        """Return the ocean patch length the texture tiles, in meters.

        Returns:
            The patch length.
        """
        return self.patch

    def caustic_shift_x(self) -> Float32:
        """Return the x registration shift, in meters.

        Returns:
            The flat-surface shift along x.
        """
        return self.shift_x

    def caustic_shift_z(self) -> Float32:
        """Return the z registration shift, in meters.

        Returns:
            The flat-surface shift along z.
        """
        return self.shift_z

    def caustic_levels(self) -> Int:
        """Return how many mip levels follow the base texture.

        Returns:
            The count of coarser levels.
        """
        return len(self.mip_n)

    def caustic_side(self, level: Int) -> Int:
        """Return the texels on one side of a level.

        Args:
            level: The level. Zero or less is the base texture.

        Returns:
            The side length.
        """
        if level <= 0:
            return self.n
        return self.mip_n[level - 1]

    def caustic_channel(self, level: Int, x: Int, y: Int, c: Int) -> Float32:
        """Return one channel of one texel of a level.

        Args:
            level: The level. Zero or less is the base texture.
            x: Column inside that level.
            y: Row inside that level.
            c: 0 red, 1 green, 2 blue.

        Returns:
            The stored intensity.
        """
        return self.level_channel(level, x, y, c)


def flat_shift(sun: Vector3, depth: Float32) -> Tuple[Float32, Float32]:
    """Return the green-channel shift of a flat surface.

    Args:
        sun: A unit sun direction, y up.
        depth: Mean depth, in meters.

    Returns:
        The world-space shift subtracted from the caustic lookup.
    """
    var sy = sun.y
    if sy < MIN_SUN_Y:
        sy = MIN_SUN_Y
    var sin_i2 = 1.0 - sy * sy
    if sin_i2 < 0.0:
        sin_i2 = 0.0
    var sin_i = sqrt(sin_i2)
    var ior = channel_ior(1)
    var sin_t = sin_i / ior
    var cos_t = sqrt(1.0 - sin_t * sin_t)
    var tan_t = sin_t / cos_t
    var hd = hypot(sun.x, sun.z)
    if hd < 1e-8:
        hd = 1.0
    return (-sun.x / hd * depth * tan_t, -sun.z / hd * depth * tan_t)


def render_caustics(
    surface: SurfaceField,
    sun: Vector3,
    depth: Length,
    grid: Int,
    resolution: Int,
    workers: Int = 0,
) raises -> CausticField:
    """Draw the caustic texture for one surface and one sun.

    The three channels are drawn in parallel, each into a plane of its
    own. Each takes the triangles in the serial order, so each texel sums
    the same values in the same order, bit for bit.

    Args:
        surface: The resolved ocean. Ripples are not part of this pass.
        sun: A unit sun direction.
        depth: Mean depth. It must be positive.
        grid: Water cells on one side of the ray grid. It must be positive.
        resolution: Caustic texels on one side. It must be positive.
        workers: The threads that share the drawing. Zero or less means
            every logical core, and one draws serially.

    Returns:
        The additive caustic image and the flat-surface shift.

    Raises:
        Error: If a size or the depth is not positive, or the ray grid's
            vertex buffer does not fit in an integer.
    """
    require_positive(grid, "Caustic ray grid must be positive")
    if depth.value <= 0.0:
        raise Error("Water depth must be positive")
    # One vertex past the last cell, three floats a color. A side of 2^31
    # wraps that product, so the ray buffer looks short and the walk does
    # not finish.
    if grid > Int.MAX - 1:
        raise Error("A caustic ray grid is larger than this port builds")
    var verts = grid + 1
    if verts > (Int.MAX // 3) // verts:
        raise Error("A caustic ray grid is larger than this port builds")
    var image = CausticField(resolution, surface.patch)
    var shift = flat_shift(sun, depth.value)
    image.shift_x = shift[0]
    image.shift_z = shift[1]
    var count = verts * verts
    var floor_x = List[Float32](length=count * 3, fill=0.0)
    var floor_z = List[Float32](length=count * 3, fill=0.0)
    var live = List[Int](length=count * 3, fill=0)
    var patch = surface.patch.value
    for j in range(verts):  # pragma: no branch
        for i in range(verts):  # pragma: no branch
            var u = Float32(i) / Float32(grid)
            var v = Float32(j) / Float32(grid)
            var sample = sample_surface(surface, u * patch, v * patch)
            var nx = -sample.slope_x
            var ny = Float32(1.0)
            var nz = -sample.slope_z
            var nl = sqrt(squared_length3[DType.float32](nx, ny, nz))
            nx /= nl
            ny /= nl
            nz /= nl
            var index = j * verts + i
            for channel in range(3):  # pragma: no branch
                var ray = refract(
                    -sun.x,
                    -sun.y,
                    -sun.z,
                    nx,
                    ny,
                    nz,
                    1.0 / channel_ior(channel),
                )
                var slot = index * 3 + channel
                # `eta` is below 1, so a miss returns y = 0 and this test catches it.
                if ray.y >= -1e-4:
                    live[slot] = 0
                else:
                    var travel = (-depth.value - sample.height) / ray.y
                    var fx = u * patch + ray.x * travel
                    var fz = v * patch + ray.z * travel
                    floor_x[slot] = fx
                    floor_z[slot] = fz
                    live[slot] = 1
    var cell = patch / Float32(grid)
    var source_area = cell * cell * 0.5
    var norm = (Float32(resolution) / patch) * (Float32(resolution) / patch)
    # Each channel sums into a plane of its own, so no two tasks write
    # one cache line, and the planes are woven into the image after.
    var texels = resolution * resolution
    var planes = List[Float32](length=texels * 3, fill=0.0)
    var serial = row_tasks(workers, 1, 3) == 1
    # A task reads its settings where they are kept, so they must outlive
    # the task group: one entry a channel.
    var splats = List[_Splat]()
    for channel in range(3):  # pragma: no branch
        splats.append(
            _Splat(
                image.n,
                image.patch,
                grid,
                channel,
                shift[0],
                shift[1],
                source_area,
                norm,
            )
        )
    var plane = planes.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var xs = (
        floor_x.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmutAnyOrigin]()
    )
    var zs = (
        floor_z.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmutAnyOrigin]()
    )
    var lives = (
        live.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmutAnyOrigin]()
    )
    var group = TaskGroup()
    for channel in range(3):  # pragma: no branch
        var settings = (
            Pointer(to=splats[channel])
            .unsafe_mut_cast[False]()
            .unsafe_origin_cast[ImmutAnyOrigin]()
        )
        if serial:
            _splat_channel(plane, xs, zs, lives, settings)
        else:
            group.create_task(_splat_task(plane, xs, zs, lives, settings))
    group.wait()
    _ = len(floor_x)
    _ = len(floor_z)
    _ = len(live)
    _ = len(splats)
    for k in range(texels):  # pragma: no branch
        for channel in range(3):  # pragma: no branch
            image.samples[k * 3 + channel] = planes[channel * texels + k]
    _build_caustic_mips(image)
    return image^


@fieldwise_init
struct _Splat(ImplicitlyCopyable):
    """What one channel of the caustic splat needs: the texture's side and
    patch, the ray grid, the channel, the flat shift, the source area and
    the norm."""

    var n: Int
    var patch: Float32
    var grid: Int
    var channel: Int
    var shift_x: Float32
    var shift_z: Float32
    var source_area: Float32
    var norm: Float32


__async def _splat_task(
    plane: MutPointer[Float32, MutAnyOrigin],
    floor_x: Pointer[Float32, ImmutAnyOrigin],
    floor_z: Pointer[Float32, ImmutAnyOrigin],
    live: Pointer[Int, ImmutAnyOrigin],
    splat: Pointer[_Splat, ImmutAnyOrigin],
):
    """Splat one channel on a worker."""
    _splat_channel(plane, floor_x, floor_z, live, splat)


def _splat_channel(
    plane: MutPointer[Float32, MutAnyOrigin],
    floor_x: Pointer[Float32, ImmutAnyOrigin],
    floor_z: Pointer[Float32, ImmutAnyOrigin],
    live: Pointer[Int, ImmutAnyOrigin],
    settings: Pointer[_Splat, ImmutAnyOrigin],
):
    """Splat every refracted triangle of one channel into its plane, in
    the serial order."""
    ref splat = settings[]
    var verts = splat.grid + 1
    var at = plane.unsafe_offset(splat.channel * splat.n * splat.n)
    var side = Float32(splat.n)
    for j in range(splat.grid):  # pragma: no branch
        for i in range(splat.grid):  # pragma: no branch
            var a = j * verts + i
            var b = a + 1
            var c = a + verts
            var d = c + 1
            # The cell's reach in patches, as `_splat` finds each corner.
            var reach = _cell_reach(floor_x, floor_z, a, b, c, d, splat)
            for instance in range(9):  # pragma: no branch
                var ox = Float32(instance % 3 - 1)
                var oz = Float32(instance // 3 - 1)
                # A copy wholly a texel past an edge covers no texel.
                if (
                    (reach[1] + ox) * side < -1
                    or (reach[0] + ox) * side > side + 1
                    or (reach[3] + oz) * side < -1
                    or (reach[2] + oz) * side > side + 1
                ):
                    continue
                _splat(at, floor_x, floor_z, live, a, b, c, ox, oz, splat)
                _splat(at, floor_x, floor_z, live, b, d, c, ox, oz, splat)


def _cell_reach(
    floor_x: Pointer[Float32, ImmutAnyOrigin],
    floor_z: Pointer[Float32, ImmutAnyOrigin],
    a: Int,
    b: Int,
    c: Int,
    d: Int,
    splat: _Splat,
) -> Tuple[Float32, Float32, Float32, Float32]:
    """Return the least and the greatest x, then z, of a cell's four
    corners on the floor, in patches from the texture's corner.

    Each corner is found as `_splat` finds it. Rounding keeps the order of
    values, so every copy of a corner that `_splat` finds lies inside the
    copy of the reach."""
    var pa = _floor_patches(floor_x, floor_z, a, splat)
    var pb = _floor_patches(floor_x, floor_z, b, splat)
    var pc = _floor_patches(floor_x, floor_z, c, splat)
    var pd = _floor_patches(floor_x, floor_z, d, splat)
    return (
        min(min(pa[0], pb[0]), min(pc[0], pd[0])),
        max(max(pa[0], pb[0]), max(pc[0], pd[0])),
        min(min(pa[1], pb[1]), min(pc[1], pd[1])),
        max(max(pa[1], pb[1]), max(pc[1], pd[1])),
    )


def _floor_patches(
    floor_x: Pointer[Float32, ImmutAnyOrigin],
    floor_z: Pointer[Float32, ImmutAnyOrigin],
    vertex: Int,
    splat: _Splat,
) -> Tuple[Float32, Float32]:
    """Return where one corner's ray meets the floor, in patches from the
    texture's corner, as `_splat` finds it."""
    var slot = vertex * 3 + splat.channel
    return (
        (floor_x[unsafe_offset=slot] - splat.shift_x) / splat.patch,
        (floor_z[unsafe_offset=slot] - splat.shift_z) / splat.patch,
    )


def _splat(
    plane: MutPointer[Float32, MutAnyOrigin],
    floor_x: Pointer[Float32, ImmutAnyOrigin],
    floor_z: Pointer[Float32, ImmutAnyOrigin],
    live: Pointer[Int, ImmutAnyOrigin],
    a: Int,
    b: Int,
    c: Int,
    ox: Float32,
    oz: Float32,
    splat: _Splat,
):
    var channel = splat.channel
    var sa = a * 3 + channel
    var sb = b * 3 + channel
    var sc = c * 3 + channel
    if live[unsafe_offset=sa] == 0:
        return
    if live[unsafe_offset=sb] == 0:
        return
    if live[unsafe_offset=sc] == 0:
        return
    var patch = splat.patch
    var n = splat.n
    var shift_x = splat.shift_x
    var shift_z = splat.shift_z
    var ax = ((floor_x[unsafe_offset=sa] - shift_x) / patch + ox) * Float32(n)
    var ay = ((floor_z[unsafe_offset=sa] - shift_z) / patch + oz) * Float32(n)
    var bx = ((floor_x[unsafe_offset=sb] - shift_x) / patch + ox) * Float32(n)
    var by = ((floor_z[unsafe_offset=sb] - shift_z) / patch + oz) * Float32(n)
    var cx = ((floor_x[unsafe_offset=sc] - shift_x) / patch + ox) * Float32(n)
    var cy = ((floor_z[unsafe_offset=sc] - shift_z) / patch + oz) * Float32(n)
    var area2 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    if area2 == 0.0:
        return
    var projected = abs(area2 * 0.5)
    # Pixel area is `projected`. Source meters per pixel times `(C/L)^2`
    # is the shader's `area * uNorm`, and a flat surface lands near 1.
    var intensity = splat.source_area / projected * splat.norm
    if intensity > MAX_CAUSTIC_INTENSITY:
        intensity = MAX_CAUSTIC_INTENSITY
    var min_x = min3(ax, bx, cx)
    var max_x = max3(ax, bx, cx)
    var min_y = min3(ay, by, cy)
    var max_y = max3(ay, by, cy)
    var x0 = _caustic_low(min_x)
    var x1 = _caustic_high(max_x)
    var y0 = _caustic_low(min_y)
    var y1 = _caustic_high(max_y)
    if x0 < 0:
        x0 = 0
    if y0 < 0:
        y0 = 0
    if x1 > n:
        x1 = n
    if y1 > n:
        y1 = n
    for y in range(y0, y1):
        for x in range(x0, x1):
            var px = Float32(x) + 0.5
            var py = Float32(y) + 0.5
            if caustic_covers(px, py, ax, ay, bx, by, cx, cy, area2):
                plane[unsafe_offset=y * n + x] += intensity


def _caustic_low(value: Float32) -> Int:
    """Return the first texel at or before a caustic edge.

    A value that is not finite, or that does not fit in an integer, is
    past every texel. `Int` of such a float is not that coordinate.

    Args:
        value: The near edge, in texels.

    Returns:
        The floor, or `Int.MAX` or `Int.MIN` when `value` does not fit.
    """
    # `Float32(Int.MAX)` is 2^63, as `Float64(Int.MAX)` is, and the floor
    # of a `Float32` is a `Float32`: the same test and index without
    # `Float64`, which a Metal kernel cannot run.
    if not isfinite(value) or value >= Float32(Int.MAX):
        return Int.MAX
    if value <= -Float32(Int.MAX):
        return Int.MIN
    return Int(floor(value))


def _caustic_high(value: Float32) -> Int:
    """Return the texel just past a caustic edge.

    See `_caustic_low`. The walk is half-open, so the far edge moves one
    texel outward when that step still fits.

    Args:
        value: The far edge, in texels.

    Returns:
        The floor plus one, or `Int.MAX` or `Int.MIN` when `value` does
        not fit.
    """
    # The test and the floor in `Float32`, as in `_caustic_low`.
    if not isfinite(value) or value >= Float32(Int.MAX):
        return Int.MAX
    if value <= -Float32(Int.MAX):
        return Int.MIN
    return Int(floor(value)) + 1


def caustic_covers(
    px: Float32,
    py: Float32,
    ax: Float32,
    ay: Float32,
    bx: Float32,
    by: Float32,
    cx: Float32,
    cy: Float32,
    area2: Float32,
) -> Bool:
    """Return True if one caustic pixel sits inside a refracted triangle.

    Args:
        px: Pixel center x.
        py: Pixel center y.
        ax: First vertex x.
        ay: First vertex y.
        bx: Second vertex x.
        by: Second vertex y.
        cx: Third vertex x.
        cy: Third vertex y.
        area2: Twice the signed area of the triangle, in pixel space.

    Returns:
        True for interior pixels and one side of each shared edge. A
        degenerate triangle covers no pixel.
    """
    var w0 = (bx - px) * (cy - py) - (by - py) * (cx - px)
    var w1 = (cx - px) * (ay - py) - (cy - py) * (ax - px)
    var w2 = (ax - px) * (by - py) - (ay - py) * (bx - px)
    if area2 == 0.0:
        return False
    var sign = Float32(1.0)
    if area2 < 0.0:
        sign = -1.0
    return (
        _edge_covers(w0 * sign, (cx - bx) * sign, (cy - by) * sign)
        and _edge_covers(w1 * sign, (ax - cx) * sign, (ay - cy) * sign)
        and _edge_covers(w2 * sign, (bx - ax) * sign, (by - ay) * sign)
    )


def _edge_covers(weight: Float32, dx: Float32, dy: Float32) -> Bool:
    # A half-open edge rule gives a shared edge to exactly one triangle.
    # Reverse-wound triangles reverse the edge before reaching this rule.
    if weight > 0.0:
        return True
    if weight < 0.0:
        return False
    return dy < 0.0 or (dy == 0.0 and dx > 0.0)


def _build_caustic_mips(mut image: CausticField):
    var n = image.n
    var level = 0
    for _step in range(16):  # pragma: no branch
        if n <= 1:
            break
        var half = n // 2
        var dst = List[Float32](length=half * half * 3, fill=0.0)
        for y in range(half):  # pragma: no branch
            var y0 = y * n // half
            var y1 = (y + 1) * n // half
            for x in range(half):  # pragma: no branch
                var x0 = x * n // half
                var x1 = (x + 1) * n // half
                var r = Float32(0.0)
                var g = Float32(0.0)
                var b = Float32(0.0)
                var count = Float32(0.0)
                for sy in range(y0, y1):  # pragma: no branch
                    for sx in range(x0, x1):  # pragma: no branch
                        r += image.level_channel(level, sx, sy, 0)
                        g += image.level_channel(level, sx, sy, 1)
                        b += image.level_channel(level, sx, sy, 2)
                        count += 1.0
                var inv = 1.0 / count
                var at = (y * half + x) * 3
                dst[at] = r * inv
                dst[at + 1] = g * inv
                dst[at + 2] = b * inv
        image.mip_off.append(len(image.mip_px))
        image.mip_n.append(half)
        for index in range(len(dst)):  # pragma: no branch
            image.mip_px.append(dst[index])
        n = half
        level += 1
