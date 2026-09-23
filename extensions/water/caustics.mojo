# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refracted-grid caustics, the method Clearwater takes from Evan Wallace.

Each water cell is refracted along the sun onto the bed, once per color,
because the index changes. The flat-surface shift of the green channel is
removed so the pattern stays registered. What remains is dispersion.
"""

from extensions.water.optics import channel_ior, refract
from extensions.water.surface import SurfaceField, sample_surface
from math.vector3 import Vector3
from std.math import abs, floor, hypot, sqrt
from units.si import Length


struct CausticField(Movable):
    """A square caustic texture, three additive channels."""

    var n: Int
    var patch: Float32
    var samples: List[Float32]
    var shift_x: Float32
    var shift_z: Float32

    def __init__(out self, n: Int, patch: Length) raises:
        """Allocate a black texture.

        Args:
            n: Texels on one side. It must be positive.
            patch: The ocean patch length.

        Raises:
            Error: If `n` is not positive, or the patch is not positive.
        """
        if n <= 0:
            raise Error("Caustic resolution must be positive")
        if patch.value <= 0.0:
            raise Error("Ocean patch length must be positive")
        self.n = n
        self.patch = patch.value
        self.samples = List[Float32](length=n * n * 3, fill=0.0)
        self.shift_x = 0.0
        self.shift_z = 0.0

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


def flat_shift(sun: Vector3, depth: Float32) -> Tuple[Float32, Float32]:
    """Return the green-channel shift of a flat surface.

    Args:
        sun: A unit sun direction, y up.
        depth: Mean depth, in meters.

    Returns:
        The world-space shift subtracted from the caustic lookup.
    """
    var sy = sun.y
    if sy < 0.05:
        sy = 0.05
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
) raises -> CausticField:
    """Draw the caustic texture for one surface and one sun.

    Args:
        surface: The resolved ocean. Ripples are not part of this pass.
        sun: A unit sun direction.
        depth: Mean depth. It must be positive.
        grid: Water cells on one side of the ray grid. It must be positive.
        resolution: Caustic texels on one side. It must be positive.

    Returns:
        The additive caustic image and the flat-surface shift.

    Raises:
        Error: If a size or the depth is not positive.
    """
    if grid <= 0:
        raise Error("Caustic ray grid must be positive")
    if depth.value <= 0.0:
        raise Error("Water depth must be positive")
    var image = CausticField(resolution, surface.patch)
    var shift = flat_shift(sun, depth.value)
    image.shift_x = shift[0]
    image.shift_z = shift[1]
    var verts = grid + 1
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
            var nl = sqrt(nx * nx + ny * ny + nz * nz)
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
    for channel in range(3):  # pragma: no branch
        for j in range(grid):  # pragma: no branch
            for i in range(grid):  # pragma: no branch
                var a = j * verts + i
                var b = a + 1
                var c = a + verts
                var d = c + 1
                _splat_pair(
                    image,
                    floor_x,
                    floor_z,
                    live,
                    a,
                    b,
                    c,
                    d,
                    channel,
                    shift[0],
                    shift[1],
                    source_area,
                    norm,
                )
    return image^


def _splat_pair(
    mut image: CausticField,
    floor_x: List[Float32],
    floor_z: List[Float32],
    live: List[Int],
    a: Int,
    b: Int,
    c: Int,
    d: Int,
    channel: Int,
    shift_x: Float32,
    shift_z: Float32,
    source_area: Float32,
    norm: Float32,
):
    for instance in range(9):  # pragma: no branch
        var ox = Float32(instance % 3 - 1)
        var oz = Float32(instance // 3 - 1)
        _splat(
            image,
            floor_x,
            floor_z,
            live,
            a,
            b,
            c,
            channel,
            ox,
            oz,
            shift_x,
            shift_z,
            source_area,
            norm,
        )
        _splat(
            image,
            floor_x,
            floor_z,
            live,
            b,
            d,
            c,
            channel,
            ox,
            oz,
            shift_x,
            shift_z,
            source_area,
            norm,
        )


def _splat(
    mut image: CausticField,
    floor_x: List[Float32],
    floor_z: List[Float32],
    live: List[Int],
    a: Int,
    b: Int,
    c: Int,
    channel: Int,
    ox: Float32,
    oz: Float32,
    shift_x: Float32,
    shift_z: Float32,
    source_area: Float32,
    norm: Float32,
):
    var sa = a * 3 + channel
    var sb = b * 3 + channel
    var sc = c * 3 + channel
    if live[sa] == 0:
        return
    if live[sb] == 0:
        return
    if live[sc] == 0:
        return
    var patch = image.patch
    var n = image.n
    var ax = ((floor_x[sa] - shift_x) / patch + ox) * Float32(n)
    var ay = ((floor_z[sa] - shift_z) / patch + oz) * Float32(n)
    var bx = ((floor_x[sb] - shift_x) / patch + ox) * Float32(n)
    var by = ((floor_z[sb] - shift_z) / patch + oz) * Float32(n)
    var cx = ((floor_x[sc] - shift_x) / patch + ox) * Float32(n)
    var cy = ((floor_z[sc] - shift_z) / patch + oz) * Float32(n)
    var area2 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    var projected = abs(area2 * 0.5)
    # Pixel area is `projected`. Source meters per pixel times `(C/L)^2`
    # is the shader's `area * uNorm`, and a flat surface lands near 1.
    var intensity = source_area / projected * norm
    if intensity > 40.0:
        intensity = 40.0
    var min_x = _min3(ax, bx, cx)
    var max_x = _max3(ax, bx, cx)
    var min_y = _min3(ay, by, cy)
    var max_y = _max3(ay, by, cy)
    var x0 = Int(floor(min_x))
    var x1 = Int(floor(max_x)) + 1
    var y0 = Int(floor(min_y))
    var y1 = Int(floor(max_y)) + 1
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
                image.samples[(y * n + x) * 3 + channel] += intensity


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
        True when the barycentric weights all share the triangle's sign.
    """
    var w0 = (bx - px) * (cy - py) - (by - py) * (cx - px)
    var w1 = (cx - px) * (ay - py) - (cy - py) * (ax - px)
    var w2 = (ax - px) * (by - py) - (ay - py) * (bx - px)
    if area2 < 0.0:
        return w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0
    return w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0


def _min3(a: Float32, b: Float32, c: Float32) -> Float32:
    var m = a
    if b < m:
        m = b
    if c < m:
        m = c
    return m


def _max3(a: Float32, b: Float32, c: Float32) -> Float32:
    var m = a
    if b > m:
        m = b
    if c > m:
        m = c
    return m
