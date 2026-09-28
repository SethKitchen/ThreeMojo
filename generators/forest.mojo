# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Trees scattered over a terrain in one instanced draw, from three.js
`examples/jsm/generators/ForestGenerator.js`.

Each tree is one blob: an icosahedron welded to twelve vertices, squashed
into a lumpy, tapered teardrop that stands on y equals zero. Its normals
point up and out, so it shades as a soft canopy, and an `ao` attribute
runs from zero at the base to one at the crown.

The placement draws random points on the terrain and keeps the ones in the
altitude band, on ground flat enough, and inside a density mask of slow
Perlin noise that breaks the forest into patches and clearings. A kept
tree gets a small lean, a free turn about y and a scale that is mostly
small with rare giants. The draw gives up after fourteen tries a tree, so
a band that is too small does not hang.

A second generator, seeded apart, gives each tree a random threshold for
the distance cull and the offsets of a regional color drift. It does not
disturb the placement. The shader that culls and colors the trees is not
ported; `ForestInstances.keeps` answers the cull's question on the CPU.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.terrain import TerrainGenerator
from generators.utils import (
    Instances,
    Vec3d,
    check_finite,
    euler_matrix,
    generator_random,
    meters,
)
from geometries.polyhedron import icosahedron
from geometries.utils import merge_vertices
from math.noise import ImprovedNoise
from math.vector3 import Vector3
from std.math import pi, sin, sqrt
from units.si import InverseLength, Length, METER, PER_METER

# The name of the blob's base-to-crown attribute, as three.js names it.
comptime AO = "ao"


struct ForestParameters(Copyable, Movable):
    """The parameters of a forest, three.js's `ForestGenerator.defaults`."""

    # The seed of the placement.
    var seed: Int
    # How many trees to plant, at most.
    var count: Int
    # How finely the icosahedron is cut. Zero welds to twelve vertices.
    var detail: Int
    # The half width of a blob.
    var radius: Length
    # The height of a blob.
    var height: Length
    # How lumpy the blob's hull is.
    var distortion: Float64
    # How far a tree's base is pushed under the surface.
    var sink: Length
    # The band of altitude, from zero at the lowest point of the terrain
    # to one at the highest, that the forest occupies.
    var altitude_min: Float64
    var altitude_max: Float64
    # The least flatness, the y of the surface normal, a tree stands on.
    var min_slope: Float64
    # The frequency of the patches and clearings.
    var density_frequency: InverseLength
    # The range of a tree's scale.
    var min_scale: Float64
    var max_scale: Float64
    # Every tree nearer the camera than `from_distance` is drawn, and none
    # farther than `to_distance`; three.js's `from` and `to`.
    var from_distance: Length
    var to_distance: Length
    # Whether the trees cast and receive shadows.
    var cast_shadow: Bool

    def __init__(out self):
        """Create three.js's default forest."""
        self.seed = 1
        self.count = 500000
        self.detail = 0
        self.radius = Length(1.3, METER)
        self.height = Length(4, METER)
        self.distortion = 0.5
        self.sink = Length(0.4, METER)
        self.altitude_min = 0.12
        self.altitude_max = 0.46
        self.min_slope = 0.55
        self.density_frequency = InverseLength(0.012, PER_METER)
        self.min_scale = 0.7
        self.max_scale = 1.8
        self.from_distance = Length(300, METER)
        self.to_distance = Length(620, METER)
        self.cast_shadow = False

    def check(self) raises:
        """Refuse parameters that plant nothing sensible.

        Raises:
            Error: If the count or the detail is negative, the cull does
                not end past where it starts, or a number is not finite.
        """
        if self.count < 0:
            raise Error("A forest's tree count must be zero or more")
        if self.detail < 0:
            raise Error("A forest's blob detail must be zero or more")
        if not meters(self.to_distance) > meters(self.from_distance):
            raise Error("A forest's cull must end past where it starts")
        check_finite(
            meters(self.radius) + meters(self.height) + meters(self.sink),
            "A blob size",
        )
        check_finite(
            self.altitude_min + self.altitude_max + self.min_slope,
            "A placement band",
        )
        check_finite(self.min_scale + self.max_scale, "A tree scale")
        check_finite(
            self.distortion
            + Float64(self.density_frequency.to(PER_METER)),
            "A blob distortion or density",
        )


def smooth_blend(edge0: Float64, edge1: Float64, x: Float64) -> Float64:
    """Return the smoothstep of `x` between two edges, three.js's
    `smoothBlend`. The edges may come in either order.

    Args:
        edge0: The edge that gives zero.
        edge1: The edge that gives one.
        x: The value.

    Returns:
        A number from zero to one.
    """
    var t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def blob_noise(x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the smooth lump over the unit sphere that makes the blob
    bumpy, three.js's `blobNoise`.

    Args:
        x: The x of a point on the unit sphere.
        y: The y of the point.
        z: The z of the point.

    Returns:
        A number from minus one to one.
    """
    return sin(x * 3.1) * sin(y * 2.7 + 1.3) * sin(z * 3.5 + 2.1)


def blob_geometry(p: ForestParameters) raises -> BufferGeometry:
    """Return one tree blob, three.js's `blobGeometry`.

    Args:
        p: The forest, for the blob's detail, size and distortion.

    Returns:
        An indexed geometry with `position`, `normal` and `ao`
        attributes, its base at y equals zero.

    Raises:
        Error: If the detail is negative.
    """
    var ball = icosahedron(Length(1, METER), p.detail)
    ball.delete_attribute("uv")
    ball.delete_attribute(String(NORMAL))
    var welded = merge_vertices(ball)
    var count = welded.vertex_count()
    var radius = meters(p.radius)
    var height = meters(p.height)
    var positions = List[Float32]()
    var normals = List[Float32]()
    var ao = List[Float32]()
    for i in range(count):  # pragma: no branch
        var u = welded.attribute_view(String(POSITION)).vector3(i)
        var ux = Float64(u.x)
        var uy = Float64(u.y)
        var uz = Float64(u.z)
        var h = (uy + 1) / 2
        var taper = 1 - 0.62 * h
        var r = taper * (1 + p.distortion * blob_noise(ux, uy, uz))
        positions.append(Float32(ux * r * radius))
        positions.append(Float32(h * height))
        positions.append(Float32(uz * r * radius))
        var inverse = 1 / sqrt(ux * ux + 0.55 * 0.55 + uz * uz)
        normals.append(Float32(ux * inverse))
        normals.append(Float32(0.55 * inverse))
        normals.append(Float32(uz * inverse))
        ao.append(Float32(h))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(AO), BufferAttribute(ao^, 1))
    geometry.set_index(welded.index.copy())
    return geometry^


struct ForestInstances(Movable):
    """A planted forest: the blob, one matrix a tree, and the per-tree
    data three.js keeps in instanced attributes.

    `instances.values` is three.js's `cull` attribute, four numbers a
    tree: the x, y and z of the tree and its random cull threshold.
    `region` is three.js's `region` attribute: the tree's regional color
    drift, zero to one.
    """

    var instances: Instances
    var region: List[Float32]
    # How many random points were tried.
    var attempts: Int
    # Whether the trees cast and receive shadows.
    var cast_shadow: Bool
    var receive_shadow: Bool
    # Where the cull starts and ends, three.js's `from` and `to` uniforms.
    var from_distance: Length
    var to_distance: Length

    def __init__(
        out self, var instances: Instances, p: ForestParameters
    ):
        """Create an empty forest of blobs.

        Args:
            instances: The blob, with no instance yet.
            p: The forest, for its shadows and its cull.
        """
        self.instances = instances^
        self.region = List[Float32]()
        self.attempts = 0
        self.cast_shadow = p.cast_shadow
        self.receive_shadow = p.cast_shadow
        self.from_distance = p.from_distance
        self.to_distance = p.to_distance

    def keeps(self, index: Int, camera: Vector3) raises -> Bool:
        """Return whether a tree is drawn from a camera position: the
        stochastic distance cull of three.js's forest material.

        A tree is drawn when its random threshold is at least the fraction
        of the way its distance is from `from_distance` to `to_distance`.
        So every tree nearer than the start is drawn, none past the end,
        and the band between thins out.

        Args:
            index: Which tree, from zero.
            camera: The position of the main camera, in meters.

        Returns:
            True if the tree is drawn.

        Raises:
            Error: If there is no such tree.
        """
        if index < 0 or index >= self.instances.count():
            raise Error("A forest has no tree at that index")
        var c = index * 4
        ref v = self.instances.values
        var d = Vec3d(
            Float64(v[c]) - Float64(camera.x),
            Float64(v[c + 1]) - Float64(camera.y),
            Float64(v[c + 2]) - Float64(camera.z),
        ).length()
        var start = meters(self.from_distance)
        var t = (d - start) / (meters(self.to_distance) - start)
        return Float64(v[c + 3]) >= t


struct ForestGenerator(Movable):
    """Carpets a terrain with trees, three.js's `ForestGenerator`.

    three.js returns a group named `Forest` holding one instanced mesh,
    dressed with a material that culls far trees and shades the canopy.
    The material is not ported; `build` returns the blob and the
    placements.
    """

    var parameters: ForestParameters

    def __init__(out self):
        """Create a generator with three.js's default forest."""
        self.parameters = ForestParameters()

    def __init__(out self, var parameters: ForestParameters):
        """Create a generator with given parameters.

        Args:
            parameters: The forest.
        """
        self.parameters = parameters^

    def build(self, terrain: TerrainGenerator) raises -> ForestInstances:
        """Plant the forest on a built terrain, three.js's `build`.

        Args:
            terrain: The terrain, built.

        Returns:
            The blob and one placement a planted tree. Fewer trees than the
            count are planted when the draw gives up.

        Raises:
            Error: If the parameters are refused (see
                `ForestParameters.check`), or the terrain is not built.
        """
        ref p = self.parameters
        p.check()
        if terrain.grid_size == 0:
            raise Error("A forest needs a built terrain")
        var forest = ForestInstances(
            Instances("Forest", blob_geometry(p)), p
        )
        forest.instances.item_size = 4
        var size = meters(terrain.parameters.size)
        var min_y = meters(terrain.min_y)
        var span = meters(terrain.max_y) - min_y
        var random = generator_random(p.seed)
        var perlin = ImprovedNoise()
        var density_x = random.next() * 256
        var density_z = random.next() * 256
        var density_slice = random.next() * 256
        var frequency = Float64(p.density_frequency.to(PER_METER))
        var cull_random = generator_random((p.seed & 0xFFFFFFFF) ^ 0x9E3779B9)
        var region_x = cull_random.next() * 256
        var region_z = cull_random.next() * 256
        var region_slice = cull_random.next() * 256
        var sink = meters(p.sink)
        var max_attempts = p.count * 14
        while (
            forest.instances.count() < p.count
            and forest.attempts < max_attempts
        ):
            forest.attempts += 1
            var x = (random.next() - 0.5) * size
            var z = (random.next() - 0.5) * size
            var y = terrain.height_at(x, z)
            var altitude = (y - min_y) / span
            if altitude < p.altitude_min or altitude > p.altitude_max:
                continue
            if terrain.slope_at(x, z) < p.min_slope:
                continue
            var density = smooth_blend(
                -0.12,
                0.22,
                perlin.noise(
                    x * frequency + density_x,
                    z * frequency + density_z,
                    density_slice,
                ),
            )
            density *= smooth_blend(
                p.altitude_max, p.altitude_max - 0.14, altitude
            )
            if random.next() >= density:
                continue
            var position = Vec3d(x, y - sink, z)
            var rx = (random.next() - 0.5) * 0.12
            var ry = random.next() * pi * 2
            var rz = (random.next() - 0.5) * 0.12
            var s = p.min_scale + random.next() * random.next() * (
                p.max_scale - p.min_scale
            )
            var sx = s * (0.85 + random.next() * 0.3)
            var sz = s * (0.85 + random.next() * 0.3)
            forest.instances.matrices.append(
                euler_matrix(position, rx, ry, rz, Vec3d(sx, s, sz))
            )
            forest.instances.values.append(Float32(x))
            forest.instances.values.append(Float32(position.y))
            forest.instances.values.append(Float32(z))
            forest.instances.values.append(Float32(cull_random.next()))
            var drift = perlin.noise(
                x * 0.02 + region_x, z * 0.02 + region_z, region_slice
            )
            forest.region.append(Float32(min(1.0, max(0.0, drift * 0.6 + 0.5))))
        return forest^
