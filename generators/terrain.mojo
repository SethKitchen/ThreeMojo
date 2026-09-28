# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A procedural mountain range, from three.js
`examples/jsm/generators/TerrainGenerator.js`.

The height at a point is a sum of Perlin noise octaves. Each octave is
damped where the running slope is already steep, which keeps the ridges
sharp and the valleys smooth. The sample point is warped by a second,
slower noise first, so the ridges wander. A power curve flattens the low
ground.

The heights are baked on a square grid and then eroded: a cell that stands
more than the angle of repose above a neighbor sheds part of the excess to
it. The grid becomes one indexed geometry in the ground plane, y up.

`ImprovedNoise` has a fixed permutation, so the seed only moves the sample
window: three numbers from the seeded generator shift x and z and pick a
z slice. three.js does the same.

three.js keeps the heights in a `Float32Array`. The erosion reads and
writes that array, so the port rounds each height to `Float32` where
three.js stores one.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.utils import check_finite, generator_random, meters
from math.noise import ImprovedNoise
from std.math import floor, inf, pow, sqrt
from units.si import (
    InverseLength,
    Length,
    METER,
    PER_METER,
)


struct TerrainParameters(Copyable, Movable):
    """The parameters of a terrain, three.js's
    `TerrainGenerator.defaults`."""

    # The seed of the sample window.
    var seed: Int
    # The width of the square patch.
    var size: Length
    # The grid cells a side. The grid has one more vertex a side.
    var segments: Int
    # The height from the valley floor to the peaks.
    var height_scale: Length
    # The base frequency of the noise: one over a mountain's footprint.
    var frequency: InverseLength
    # How many octaves of noise are summed.
    var octaves: Int
    # The frequency step from one octave to the next.
    var lacunarity: Float64
    # The amplitude step from one octave to the next.
    var gain: Float64
    # How much a steep running slope damps an octave.
    var erosion: Float64
    # How far the warp moves the sample point, in noise units.
    var warp: Float64
    # The power curve over the height that flattens the valley floor.
    var valley_bias: Float64
    # The fraction of the height taken off, so the floor sinks below zero.
    var sea_level: Float64
    # The angle of repose of the erosion, as rise over run.
    var talus: Float64
    # How many erosion passes run. Zero turns the erosion off.
    var talus_passes: Int

    def __init__(out self):
        """Create three.js's default terrain."""
        self.seed = 1
        self.size = Length(200, METER)
        self.segments = 192
        self.height_scale = Length(65, METER)
        self.frequency = InverseLength(0.01, PER_METER)
        self.octaves = 5
        self.lacunarity = 1.97
        self.gain = 0.5
        self.erosion = 0.7
        self.warp = 0.35
        self.valley_bias = 1.2
        self.sea_level = 0.15
        self.talus = 1
        self.talus_passes = 12

    def check(self) raises:
        """Refuse parameters that bake no grid.

        Raises:
            Error: If the size or the segment count is not positive, the
                octave or pass count is negative, or a number is not
                finite.
        """
        if not meters(self.size) > 0:
            raise Error("A terrain's size must be positive")
        if self.segments < 1:
            raise Error("A terrain needs one segment a side at least")
        if self.octaves < 0:
            raise Error("A terrain's octave count must be zero or more")
        if self.talus_passes < 0:
            raise Error("A terrain's erosion pass count must be zero or more")
        check_finite(meters(self.height_scale), "A height scale")
        check_finite(Float64(self.frequency.to(PER_METER)), "A frequency")
        check_finite(
            self.lacunarity + self.gain + self.erosion + self.warp,
            "A noise parameter",
        )
        check_finite(self.valley_bias + self.sea_level, "A height curve")
        check_finite(self.talus, "A talus")


struct _HeightField:
    """The height at a point for one seed, three.js's `heightField`."""

    var p: TerrainParameters
    var perlin: ImprovedNoise
    var offset_x: Float64
    var offset_z: Float64
    var slice: Float64

    def __init__(out self, p: TerrainParameters):
        self.p = p.copy()
        self.perlin = ImprovedNoise()
        var random = generator_random(p.seed)
        self.offset_x = random.next() * 256
        self.offset_z = random.next() * 256
        self.slice = random.next() * 256

    def warp_field(self, x: Float64, z: Float64, zr: Float64) raises -> Float64:
        """Return the slow two-octave sum that warps the sample point."""
        var freq = 1.0
        var amp = 1.0
        var sum = 0.0
        var norm = 0.0
        for i in range(2):  # pragma: no branch
            sum += amp * self.perlin.noise(
                x * freq + self.offset_x,
                z * freq + self.offset_z,
                zr + Float64(i) * 1.7,
            )
            norm += amp
            freq *= self.p.lacunarity
            amp *= self.p.gain
        return sum / norm

    def eroded(self, x: Float64, z: Float64) raises -> Float64:
        """Return the slope-damped sum of octaves, from zero to one about.
        The domain turns about 37 degrees between octaves."""
        var sum = 0.0
        var amp = 1.0
        var dx = 0.0
        var dz = 0.0
        var px = x
        var pz = z
        var freq = 1.0
        var e = 0.004
        for i in range(self.p.octaves):
            var zr = self.slice + Float64(i) * 1.7
            var bx = px * freq + self.offset_x
            var bz = pz * freq + self.offset_z
            var n = self.perlin.noise(bx, bz, zr)
            var nx = self.perlin.noise(bx + e, bz, zr)
            var nz = self.perlin.noise(bx, bz + e, zr)
            dx += (nx - n) / e * freq
            dz += (nz - n) / e * freq
            sum += amp * n / (1 + self.p.erosion * (dx * dx + dz * dz))
            var rx = 0.8 * px - 0.6 * pz
            pz = 0.6 * px + 0.8 * pz
            px = rx
            freq *= self.p.lacunarity
            amp *= self.p.gain
        return sum * 0.5 + 0.5

    def height(self, world_x: Float64, world_z: Float64) raises -> Float64:
        """Return the height at a point of the ground plane, in meters."""
        var frequency = Float64(self.p.frequency.to(PER_METER))
        var x = world_x * frequency
        var z = world_z * frequency
        var wx = x + self.p.warp * self.warp_field(
            x + 1.3, z + 7.2, self.slice + 40
        )
        var wz = z + self.p.warp * self.warp_field(
            x + 5.2, z + 1.3, self.slice + 70
        )
        var h = pow(min(self.eroded(wx, wz) * 1.1, 1.0), self.p.valley_bias)
        return (h - self.p.sea_level) * meters(self.p.height_scale)


def thermal_erode(
    mut h: List[Float32], n: Int, cell_size: Float64, talus: Float64, passes: Int
):
    """Relax the slopes of a height grid to the angle of repose, three.js's
    `thermalErode`.

    In each pass every cell that stands more than `talus` times a cell
    above a neighbor moves half of its steepest excess downhill. The
    excess is split among the lower neighbors by how far each is below
    the line. The moves are gathered first and applied after, so the
    result does not depend on the order of the cells, and nothing is lost.

    Args:
        h: The heights, row by row, `n` a row, as `Float32` as three.js
            keeps them.
        n: The vertices a side.
        cell_size: The distance between neighbors, in meters.
        talus: The angle of repose, as rise over run.
        passes: How many passes.
    """
    var drop = talus * cell_size
    var offsets: List[Int] = [-1, 1, -n, n]
    for _ in range(passes):
        var delta = List[Float32](length=n * n, fill=0)
        for z in range(n):
            _erode_row(h, delta, n, z, drop, offsets)
        for k in range(n * n):
            h[k] = Float32(Float64(h[k]) + Float64(delta[k]))


def _excess(h: List[Float32], i: Int, j: Int, drop: Float64) -> Float64:
    """Return how far cell `i` stands above cell `j` past the drop."""
    return Float64(h[i]) - Float64(h[j]) - drop


def _erode_row(
    h: List[Float32],
    mut delta: List[Float32],
    n: Int,
    z: Int,
    drop: Float64,
    offsets: List[Int],
):
    """Gather the moves of one row of cells."""
    for x in range(n):  # pragma: no branch
        var i = z * n + x
        var ex = [
            _excess(h, i, i - 1, drop) if x > 0 else 0.0,
            _excess(h, i, i + 1, drop) if x < n - 1 else 0.0,
            _excess(h, i, i - n, drop) if z > 0 else 0.0,
            _excess(h, i, i + n, drop) if z < n - 1 else 0.0,
        ]
        var sum = 0.0
        var peak = 0.0
        for k in range(4):  # pragma: no branch
            ex[k] = max(ex[k], 0.0)
            sum += ex[k]
            peak = max(peak, ex[k])
        if sum <= 0:
            continue
        var move = 0.5 * peak
        delta[i] = Float32(Float64(delta[i]) - move)
        for k in range(4):  # pragma: no branch
            if ex[k] > 0:
                var j = i + offsets[k]
                delta[j] = Float32(Float64(delta[j]) + move * ex[k] / sum)


struct TerrainGenerator(Movable):
    """Bakes a mountain range into one geometry, three.js's
    `TerrainGenerator`.

    `build` bakes the grid and keeps it, so `sample_height` and
    `sample_slope` can read the surface afterward: a forest stands on it
    that way. three.js also returns a group with one mesh and a material
    that shades grass, rock and snow from altitude and slope. The material
    is not ported; `build` returns the geometry.
    """

    var parameters: TerrainParameters
    # The baked heights, row by row from -z, each row from -x. Empty
    # until `build`.
    var heights: List[Float32]
    # The vertices a side of the baked grid, three.js's `gridSize`.
    var grid_size: Int
    # The lowest and highest baked heights, three.js's `minY` and `maxY`.
    var min_y: Length
    var max_y: Length

    def __init__(out self):
        """Create a generator with three.js's default terrain."""
        self.parameters = TerrainParameters()
        self.heights = List[Float32]()
        self.grid_size = 0
        self.min_y = Length(0, METER)
        self.max_y = Length(0, METER)

    def __init__(out self, var parameters: TerrainParameters):
        """Create a generator with given parameters.

        Args:
            parameters: The terrain.
        """
        self.parameters = parameters^
        self.heights = List[Float32]()
        self.grid_size = 0
        self.min_y = Length(0, METER)
        self.max_y = Length(0, METER)

    def build(mut self) raises -> BufferGeometry:
        """Bake the terrain, three.js's `build`.

        Returns:
            A geometry in the ground plane with `position` and `normal`
            attributes and an index. The diagonal of each quad turns on
            every other quad, so the mesh reads as diamonds.

        Raises:
            Error: If the parameters are refused; see
                `TerrainParameters.check`.
        """
        self.parameters.check()
        ref p = self.parameters
        var segments = p.segments
        var n = segments + 1
        var size = meters(p.size)
        var half = size / 2
        var coord = List[Float64]()
        for i in range(n):  # pragma: no branch
            coord.append(Float64(i) / Float64(segments) * size - half)
        var field = _HeightField(p)
        var heights = List[Float32]()
        for iz in range(n):  # pragma: no branch
            for ix in range(n):  # pragma: no branch
                heights.append(Float32(field.height(coord[ix], coord[iz])))
        var cell_size = size / Float64(segments)
        thermal_erode(heights, n, cell_size, p.talus, p.talus_passes)
        var positions = List[Float32]()
        var normals = List[Float32]()
        var lowest = inf[DType.float32]()
        var highest = -inf[DType.float32]()
        for iz in range(n):  # pragma: no branch
            for ix in range(n):  # pragma: no branch
                var y = heights[iz * n + ix]
                positions.append(Float32(coord[ix]))
                positions.append(y)
                positions.append(Float32(coord[iz]))
                _append_normal(normals, heights, n, ix, iz, cell_size)
                lowest = min(lowest, y)
                highest = max(highest, y)
        var index = List[Int]()
        for iz in range(segments):  # pragma: no branch
            for ix in range(segments):  # pragma: no branch
                _append_quad(index, n, ix, iz)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
        geometry.set_index(index^)
        self.heights = heights^
        self.grid_size = n
        self.min_y = Length(lowest, METER)
        self.max_y = Length(highest, METER)
        return geometry^

    def _height_at(self, x: Float64, z: Float64) -> Float64:
        """Return the bilinear height at a point, in meters, from the
        baked grid. The grid must be baked."""
        var segments = Float64(self.parameters.segments)
        var size = meters(self.parameters.size)
        var n = self.grid_size
        var half = size / 2
        var fx = max(0.0, min(segments, (x + half) / size * segments))
        var fz = max(0.0, min(segments, (z + half) / size * segments))
        var ix = min(n - 2, Int(floor(fx)))
        var iz = min(n - 2, Int(floor(fz)))
        var tx = fx - Float64(ix)
        var tz = fz - Float64(iz)
        var h00 = Float64(self.heights[iz * n + ix])
        var h10 = Float64(self.heights[iz * n + ix + 1])
        var h01 = Float64(self.heights[(iz + 1) * n + ix])
        var h11 = Float64(self.heights[(iz + 1) * n + ix + 1])
        return (h00 * (1 - tx) + h10 * tx) * (1 - tz) + (
            h01 * (1 - tx) + h11 * tx
        ) * tz

    def _check_built(self) raises:
        """Refuse to sample a terrain that is not baked."""
        if self.grid_size == 0:
            raise Error("A terrain must be built before it is sampled")

    def sample_height(self, x: Length, z: Length) raises -> Length:
        """Return the height of the baked surface at a point, three.js's
        `sampleHeight`: bilinear between the four grid vertices around
        it. A point off the patch reads the nearest edge.

        Args:
            x: The x of the point.
            z: The z of the point.

        Returns:
            The height.

        Raises:
            Error: If the terrain is not built.
        """
        self._check_built()
        return Length(Float32(self._height_at(meters(x), meters(z))), METER)

    def sample_slope(self, x: Length, z: Length) raises -> Float64:
        """Return how flat the baked surface is at a point, three.js's
        `sampleSlope`: the y of its normal, one on level ground and toward
        zero on a cliff.

        Args:
            x: The x of the point.
            z: The z of the point.

        Returns:
            The flatness.

        Raises:
            Error: If the terrain is not built.
        """
        self._check_built()
        return self.slope_at(meters(x), meters(z))

    def height_at(self, x: Float64, z: Float64) raises -> Float64:
        """Return `sample_height` in `Float64` meters, as three.js computes
        it, for a caller that tests many points.

        Args:
            x: The x of the point, in meters.
            z: The z of the point, in meters.

        Returns:
            The height, in meters.

        Raises:
            Error: If the terrain is not built.
        """
        self._check_built()
        return self._height_at(x, z)

    def slope_at(self, x: Float64, z: Float64) raises -> Float64:
        """Return `sample_slope` for a point in `Float64` meters.

        Args:
            x: The x of the point, in meters.
            z: The z of the point, in meters.

        Returns:
            The flatness.

        Raises:
            Error: If the terrain is not built.
        """
        self._check_built()
        var e = meters(self.parameters.size) / Float64(self.parameters.segments)
        var hx = self._height_at(x + e, z) - self._height_at(x - e, z)
        var hz = self._height_at(x, z + e) - self._height_at(x, z - e)
        return 2 * e / sqrt(hx * hx + 4 * e * e + hz * hz)


def _append_normal(
    mut normals: List[Float32],
    h: List[Float32],
    n: Int,
    ix: Int,
    iz: Int,
    cell_size: Float64,
):
    """Append the normal of one grid vertex, from the height differences
    of its neighbors, one-sided at an edge."""
    var left = max(0, ix - 1)
    var right = min(n - 1, ix + 1)
    var back = max(0, iz - 1)
    var front = min(n - 1, iz + 1)
    var nx = (Float64(h[iz * n + left]) - Float64(h[iz * n + right])) / (
        Float64(right - left) * cell_size
    )
    var nz = (Float64(h[back * n + ix]) - Float64(h[front * n + ix])) / (
        Float64(front - back) * cell_size
    )
    var length = sqrt(nx * nx + 1 + nz * nz)
    normals.append(Float32(nx / length))
    normals.append(Float32(1 / length))
    normals.append(Float32(nz / length))


def _append_quad(mut index: List[Int], n: Int, ix: Int, iz: Int):
    """Append the two triangles of one grid quad, its diagonal turned on
    every other quad."""
    var a = iz * n + ix
    var b = a + 1
    var c = a + n
    var d = c + 1
    var even = (ix + iz) % 2 == 0
    index.append(a)
    index.append(c)
    index.append(b if even else d)
    index.append(b if even else a)
    index.append(c if even else d)
    index.append(d if even else b)
