# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Leaves in clumps, and the light that reaches each leaf through them.

**Clumps.** A broadleaf crown is not an even cloud of leaves. Each twig
holds a dense clump, and the crown is many clumps with gaps of sky
between them. A clump here is a sphere. Its leaves crowd its outer shell,
where the light is.

**The light inside a crown.** A leaf deep in a clump, or behind another
clump, gets little sun and little sky. `sun_through` follows the ray from
a leaf toward the sun and adds the length of every clump it crosses. The
light that comes through is `exp(-density * length)`, Beer's law for a
cloud of leaves. `sky_through` averages the same over `SKY_RAYS`
directions of the open sky. Both are exact for spheres, so they need no
voxel grid and no noise.

The two numbers are kept apart, as `SUNLIT` and `SKYLIT` attributes.
`foliage_program` multiplies the sun's light by the first and the sky's
light by the second. A leaf in the shade of its own crown then still has
the blue light of the sky, as a real leaf does.

**A leaf.** `OVATE` is the outline of a broad leaf: a base, three pairs of
edge vertices and a tip, six triangles. The two halves tilt their normals
away from the midrib, so the leaf is lit as if it were folded along it.
The tip droops. `CARD` is a diamond of two triangles, for far trees.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from materials.nodes import (
    AO_NODE,
    NODE_FLOAT,
    NORMAL_NODE,
    RECEIVED_SHADOW_NODE,
    NodeGraph,
    NodeProgram,
)
from math.vector3 import Vector3
from std.math import exp, sqrt

# The attributes that hold the light that reaches each leaf vertex.
comptime SUNLIT = "sunlit"
comptime SKYLIT = "skylit"
# How far each half of a leaf tilts its normal from the midrib.
comptime FOLD = Float32(0.45)
# The widths of the three pairs of edge vertices of an ovate leaf, as
# fractions of its width, and where along the leaf they are.
comptime OVATE_AT = [Float32(0.18), Float32(0.5), Float32(0.8)]
comptime OVATE_WIDTH = [Float32(0.7), Float32(1.0), Float32(0.62)]
# The open-sky directions that `sky_through` averages: straight up, and
# six at 45 degrees round it.
comptime SKY_RAYS = 7


@fieldwise_init
struct Clump(ImplicitlyCopyable):
    """One clump of leaves, as a sphere."""

    var center: Vector3
    var radius: Float32


def chord(origin: Vector3, toward: Vector3, clump: Clump) -> Float32:
    """Return how far a ray from `origin` runs inside a clump.

    Only the part of the ray ahead of the origin counts. A ray that starts
    inside the clump counts from the origin to the clump's edge.

    Args:
        origin: Where the ray starts, in meters.
        toward: The ray's direction, of unit length.
        clump: The clump.

    Returns:
        The length inside, in meters. Zero if the ray misses.
    """
    var offset = origin - clump.center
    var b = offset.dot(toward)
    var c = offset.dot(offset) - clump.radius * clump.radius
    var reach = b * b - c
    if reach <= 0:
        return 0
    var half = sqrt(reach)
    var leave = -b + half
    var enter = -b - half
    return max(Float32(0), leave) - max(Float32(0), min(enter, leave))


def sun_through(
    origin: Vector3, toward: Vector3, clumps: List[Clump], density: Float32
) -> Float32:
    """Return the share of light that reaches a point through the clumps.

    Args:
        origin: The point, in meters.
        toward: The direction the light comes from, of unit length.
        clumps: Every clump of the crown.
        density: How much a meter of clump dims the light, per meter.

    Returns:
        `exp(-density * length)`, with `length` the sum of the chords.
        One if there is no clump.
    """
    var length = Float32(0)
    for index in range(len(clumps)):
        length += chord(origin, toward, clumps[index])
    return exp(-density * length)


def sky_rays() -> List[Vector3]:
    """Return the `SKY_RAYS` unit directions of the open sky.

    Returns:
        Straight up, then six directions 45 degrees up, a sixth of a turn
        apart.
    """
    var rays: List[Vector3] = [Vector3(0, 1, 0)]
    var side = Float32(0.70710678)
    var rim: List[Vector3] = [
        Vector3(1, 0, 0),
        Vector3(0.5, 0, 0.8660254),
        Vector3(-0.5, 0, 0.8660254),
        Vector3(-1, 0, 0),
        Vector3(-0.5, 0, -0.8660254),
        Vector3(0.5, 0, -0.8660254),
    ]
    for index in range(len(rim)):  # pragma: no branch
        rays.append(Vector3(rim[index].x * side, side, rim[index].z * side))
    return rays^


def sky_through(
    origin: Vector3,
    rays: List[Vector3],
    clumps: List[Clump],
    density: Float32,
) -> Float32:
    """Return the share of the open sky a point sees through the clumps.

    Args:
        origin: The point, in meters.
        rays: The sky's directions, from `sky_rays`.
        clumps: Every clump of the crown.
        density: How much a meter of clump dims the light, per meter.

    Returns:
        The mean of `sun_through` over the rays. One with no ray.
    """
    if len(rays) == 0:
        return 1
    var total = Float32(0)
    for index in range(len(rays)):  # pragma: no branch
        total += sun_through(origin, rays[index], clumps, density)
    return total / Float32(len(rays))


def foliage_program() raises -> NodeProgram:
    """Return the node program that lights leaves as their attributes say.

    The normal of a back face turns to the front, as `two_sided_program`
    turns it: a leaf with the sun behind it glows. Each light's shadow is
    the leaf's `SUNLIT`, and the indirect light is dimmed by its `SKYLIT`.

    Returns:
        The compiled program, with a `NORMAL_NODE`, a
        `RECEIVED_SHADOW_NODE` and an `AO_NODE`.

    Raises:
        Error: Never; the graph is fixed.
    """
    var graph = NodeGraph()
    var behind = graph.mul(
        graph.sub(graph.front_facing(), graph.float(1.0)), graph.float(2.0)
    )
    graph.set_output(NORMAL_NODE, graph.mul(graph.normal_world(), behind))
    var sun = graph.attribute(String(SUNLIT), NODE_FLOAT)
    graph.set_output(RECEIVED_SHADOW_NODE, graph.mul(graph.vec3(1, 1, 1), sun))
    graph.set_output(AO_NODE, graph.attribute(String(SKYLIT), NODE_FLOAT))
    return graph.compile()


struct LeafMesh(Movable):
    """Leaves, filled one at a time, with the light that reaches each.

    `geometry` hands them over as one indexed geometry.
    """

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]
    var sunlit: List[Float32]
    var skylit: List[Float32]
    var index: List[Int]
    var leaves: Int

    def __init__(out self):
        """Create an empty buffer."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()
        self.sunlit = List[Float32]()
        self.skylit = List[Float32]()
        self.index = List[Int]()
        self.leaves = 0

    def leaf_count(self) -> Int:
        """Return how many leaves the buffer holds.

        Returns:
            The count of leaves added.
        """
        return self.leaves

    def vertex_count(self) -> Int:
        """Return how many vertices the buffer holds.

        Returns:
            The vertex count.
        """
        return len(self.positions) // 3

    def triangle_count(self) -> Int:
        """Return how many triangles the buffer holds.

        Returns:
            The triangle count.
        """
        return len(self.index) // 3

    def _vertex(
        mut self, p: Vector3, n: Vector3, c: Vector3, sun: Float32, sky: Float32
    ):
        """Append one vertex, with its normal made unit length."""
        self.positions.append(p.x)
        self.positions.append(p.y)
        self.positions.append(p.z)
        var scale = 1 / sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
        self.normals.append(n.x * scale)
        self.normals.append(n.y * scale)
        self.normals.append(n.z * scale)
        self.colors.append(c.x)
        self.colors.append(c.y)
        self.colors.append(c.z)
        self.sunlit.append(sun)
        self.skylit.append(sky)

    def _triangle(mut self, a: Int, b: Int, c: Int):
        """Append one triangle."""
        self.index.append(a)
        self.index.append(b)
        self.index.append(c)

    def add_ovate(
        mut self,
        base: Vector3,
        along: Vector3,
        across: Vector3,
        normal: Vector3,
        size: Vector3,
        color: Vector3,
        sun: Float32,
        sky: Float32,
    ):
        """Add one broad leaf: eight vertices and six triangles.

        Args:
            base: Where the leaf meets its stalk, in meters.
            along: The midrib's direction, of unit length.
            across: The direction across the leaf, of unit length.
            normal: The leaf's face, of unit length.
            size: The length, the width and the droop of the tip, in
                meters, as x, y and z.
            color: The leaf's linear color.
            sun: The share of the sun that reaches the leaf.
            sky: The share of the sky the leaf sees.
        """
        var first = self.vertex_count()
        var length = size.x
        var half = size.y * 0.5
        var droop = size.z
        self._vertex(base, normal, color, sun, sky)
        for row in range(3):  # pragma: no branch
            var s = materialize[OVATE_AT]()[row]
            var w = half * materialize[OVATE_WIDTH]()[row]
            var spine = base + along * (length * s) - normal * (droop * s * s)
            var left = across * w
            var tilt = across * FOLD
            self._vertex(spine - left, normal - tilt, color, sun, sky)
            self._vertex(spine + left, normal + tilt, color, sun, sky)
        self._vertex(
            base + along * length - normal * droop, normal, color, sun, sky
        )
        self._triangle(first, first + 1, first + 2)
        for row in range(2):  # pragma: no branch
            var a = first + 1 + 2 * row
            self._triangle(a, a + 2, a + 3)
            self._triangle(a, a + 3, a + 1)
        self._triangle(first + 5, first + 7, first + 6)
        self.leaves += 1

    def add_card(
        mut self,
        base: Vector3,
        along: Vector3,
        across: Vector3,
        normal: Vector3,
        size: Vector3,
        color: Vector3,
        sun: Float32,
        sky: Float32,
    ):
        """Add one far leaf: a diamond of four vertices and two triangles.

        The diamond spans the same length and width as an ovate leaf.

        Args:
            base: Where the leaf meets its stalk, in meters.
            along: The midrib's direction, of unit length.
            across: The direction across the leaf, of unit length.
            normal: The leaf's face, of unit length.
            size: The length, the width and the droop, in meters, as x, y
                and z. The droop is not used.
            color: The leaf's linear color.
            sun: The share of the sun that reaches the leaf.
            sky: The share of the sky the leaf sees.
        """
        var first = self.vertex_count()
        var middle = base + along * (size.x * 0.5)
        var half = across * (size.y * 0.5)
        self._vertex(base, normal, color, sun, sky)
        self._vertex(middle - half, normal, color, sun, sky)
        self._vertex(base + along * size.x, normal, color, sun, sky)
        self._vertex(middle + half, normal, color, sun, sky)
        self._triangle(first, first + 1, first + 2)
        self._triangle(first, first + 2, first + 3)
        self.leaves += 1

    def geometry(deinit self) raises -> BufferGeometry:
        """Hand the buffer over as one indexed geometry.

        Returns:
            The geometry, with `position`, `normal`, `color`, `SUNLIT`,
            `SKYLIT` and an index.

        Raises:
            Error: If the buffer is empty.
        """
        if len(self.index) == 0:
            raise Error("A leaf mesh with no leaves makes no geometry")
        var geometry = BufferGeometry()
        geometry.set_attribute(POSITION, BufferAttribute(self.positions^, 3))
        geometry.set_attribute(NORMAL, BufferAttribute(self.normals^, 3))
        geometry.set_attribute(COLOR, BufferAttribute(self.colors^, 3))
        geometry.set_attribute(SUNLIT, BufferAttribute(self.sunlit^, 1))
        geometry.set_attribute(SKYLIT, BufferAttribute(self.skylit^, 1))
        geometry.set_index(self.index^)
        return geometry^
