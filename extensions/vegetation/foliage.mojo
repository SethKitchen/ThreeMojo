# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Leaves, and the light that reaches each leaf through the others.

**The light inside a crown.** A leaf deep in a crown, or behind a lobe of
it, gets little sun and little sky. `LeafShade` counts the leaves of a
crown in a grid of cells: each leaf adds its area to the cell it is in.
A cell's leaf area over its volume, times `shade`, is how much a meter of
it dims light. `LeafShade.through` follows the ray from a leaf toward the
sun, cell by cell, and adds that up. The light that comes through is
`exp(-sum)`, Beer's law for a cloud of leaves. `LeafShade.sky` averages
the same over `SKY_RAYS` directions of the open sky. The grid is blurred
once, and read between its cells, so the light is smooth across a crown.

**The wind in a crown.** `sway_offset` moves a vertex of a leaf or of
the wood by a share of a swing along the wind and of a flutter up and
down. The share is read from where the vertex is in the tree: none at
the foot, more the higher and the further out from the trunk it is. A
position program reads no attribute, so the share cannot be baked. The
swing's phase changes slowly through the crown, so a limb and its leaves
move together and the lobes move apart. The flutter's phase changes
fast, so each spray flutters on its own. The leaves and the wood read the
same offset, so a leaf stays on its twig. The time is the `SWAY_TIME`
uniform.

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
    POSITION_NODE,
    RECEIVED_SHADOW_NODE,
    NodeGraph,
    NodeProgram,
    NodeRef,
)
from extensions.vegetation.checks import require_between
from extensions.vegetation.wind import CrownMotion
from math.vector3 import Vector3
from renderers.game_renderer import GameShading, SwayMotion
from std.math import cos, exp, floor, pi, sin, sqrt
from units.si import METER, PER_SECOND, Length

# The attributes that hold the light that reaches each leaf vertex.
comptime SUNLIT = "sunlit"
comptime SKYLIT = "skylit"
# The uniform that holds the wind's time, in seconds.
comptime SWAY_TIME = "sway_time"
# A vertex this high above a tree's foot sways a full swing, and one this
# far out from the trunk a full share of it, in meters. A vertex higher up
# sways more, up to `SWAY_MOST` swings.
comptime SWAY_HEIGHT = Float32(12)
comptime SWAY_SPREAD = Float32(4)
comptime SWAY_MOST = Float32(1.5)
# How fast the phase of the swing and of the flutter change through a
# crown, per meter along x, y and z: a swing's phase turns once in about
# 30 meters, and a flutter's in about 2.
comptime SWING_PHASE = (Float32(0.21), Float32(0.13), Float32(0.17))
comptime FLUTTER_PHASE = (Float32(2.3), Float32(3.1), Float32(2.9))
# How far each half of a leaf tilts its normal from the midrib.
comptime FOLD = Float32(0.45)
# The widths of the three pairs of edge vertices of an ovate leaf, as
# fractions of its width, and where along the leaf they are.
comptime OVATE_AT = [Float32(0.18), Float32(0.5), Float32(0.8)]
comptime OVATE_WIDTH = [Float32(0.7), Float32(1.0), Float32(0.62)]
# The open-sky directions that `LeafShade.sky` averages: straight up, six
# at 45 degrees round it, and six near the horizon.
comptime SKY_RAYS = 13
# How far a ray steps through a shade grid, as a fraction of a cell.
comptime MARCH = Float32(0.75)
# The most cells a shade grid can have.
comptime MAX_CELLS = 4_000_000


struct LeafShade(Movable):
    """The leaves of a crown counted in a grid of cells, and the light that
    comes through them."""

    # The corner of the grid with the least x, y and z, in meters.
    var low: Vector3
    # The side of a cell, in meters.
    var cell: Float32
    # The cells along x, y and z.
    var nx: Int
    var ny: Int
    var nz: Int
    # Each cell's leaf area until `finish`, then how much a meter of it
    # dims light, per meter. Cell `(x, y, z)` is entry
    # `(z * ny + y) * nx + x`.
    var density: List[Float32]

    def __init__(out self, low: Vector3, high: Vector3, cell: Length) raises:
        """Create an empty grid that covers a box.

        Args:
            low: The box's corner with the least x, y and z, in meters.
            high: Its corner with the most, in meters.
            cell: The side of a cell, from 1 centimeter to 10 meters.

        Raises:
            Error: If the cell is out of range, the box is not from 1
                millimeter to 1 kilometer on each side, or it needs more
                than 4 million cells.
        """
        var side = cell.to(METER)
        require_between(
            side,
            0.01,
            10,
            "A shade cell must be from 1 centimeter to 10 meters",
        )
        var size = high - low
        for axis in range(3):  # pragma: no branch
            require_between(
                size.get_component(axis),
                0.001,
                1000,
                "A shade grid must be from 1 millimeter to 1 kilometer across",
            )
        var nx = Int(size.x / side) + 1
        var ny = Int(size.y / side) + 1
        var nz = Int(size.z / side) + 1
        if nx * ny * nz > MAX_CELLS:
            raise Error("A shade grid must have at most 4 million cells")
        self.low = low
        self.cell = side
        self.nx = nx
        self.ny = ny
        self.nz = nz
        self.density = List[Float32](length=nx * ny * nz, fill=0)

    def _at(self, x: Int, y: Int, z: Int) -> Float32:
        """Return a cell's value, or zero outside the grid."""
        if (
            x < 0
            or y < 0
            or z < 0
            or x >= self.nx
            or y >= self.ny
            or z >= self.nz
        ):
            return 0
        return self.density[(z * self.ny + y) * self.nx + x]

    def add(mut self, p: Vector3, area: Float32):
        """Add a leaf's area to the cell it is in. A leaf outside the grid
        adds to the nearest cell.

        Args:
            p: Where the leaf is, in meters.
            area: Its area, in square meters.
        """
        var q = (p - self.low) / self.cell
        var x = max(0, min(self.nx - 1, Int(floor(q.x))))
        var y = max(0, min(self.ny - 1, Int(floor(q.y))))
        var z = max(0, min(self.nz - 1, Int(floor(q.z))))
        self.density[(z * self.ny + y) * self.nx + x] += area

    def finish(mut self, shade: Float32):
        """Turn the leaf areas into how much a meter dims light, and blur
        them once along each axis by a quarter, a half and a quarter.

        Args:
            shade: How much of its area a leaf shades along a ray: a half
                for leaves that face every way.
        """
        var volume = self.cell * self.cell * self.cell
        for index in range(len(self.density)):  # pragma: no branch
            self.density[index] *= shade / volume
        for axis in range(3):  # pragma: no branch
            var blurred = List[Float32](length=len(self.density), fill=0)
            for z in range(self.nz):  # pragma: no branch
                for y in range(self.ny):  # pragma: no branch
                    for x in range(self.nx):  # pragma: no branch
                        var dx = 1 if axis == 0 else 0
                        var dy = 1 if axis == 1 else 0
                        var dz = 1 if axis == 2 else 0
                        blurred[(z * self.ny + y) * self.nx + x] = (
                            0.5 * self._at(x, y, z)
                            + 0.25 * self._at(x - dx, y - dy, z - dz)
                            + 0.25 * self._at(x + dx, y + dy, z + dz)
                        )
            self.density = blurred^

    def dimming(self, p: Vector3) -> Float32:
        """Return how much a meter dims light at a point, read between the
        cells' middles. Zero outside the grid.

        Args:
            p: The point, in meters.

        Returns:
            The dimming, per meter.
        """
        var q = (p - self.low) / self.cell - Vector3(0.5, 0.5, 0.5)
        var fx = floor(q.x)
        var fy = floor(q.y)
        var fz = floor(q.z)
        var x = Int(fx)
        var y = Int(fy)
        var z = Int(fz)
        var sx = q.x - fx
        var sy = q.y - fy
        var sz = q.z - fz
        var near = (
            self._at(x, y, z) * (1 - sx) + self._at(x + 1, y, z) * sx
        ) * (1 - sy) + (
            self._at(x, y + 1, z) * (1 - sx) + self._at(x + 1, y + 1, z) * sx
        ) * sy
        var far = (
            self._at(x, y, z + 1) * (1 - sx) + self._at(x + 1, y, z + 1) * sx
        ) * (1 - sy) + (
            self._at(x, y + 1, z + 1) * (1 - sx)
            + self._at(x + 1, y + 1, z + 1) * sx
        ) * sy
        return near * (1 - sz) + far * sz

    def through(self, origin: Vector3, toward: Vector3) -> Float32:
        """Return the share of light that reaches a point from a direction.

        The ray starts half a cell out, so a leaf does not shade itself,
        and steps `MARCH` of a cell at a time until it leaves the grid.

        Args:
            origin: The point, in meters.
            toward: The direction the light comes from, of unit length.

        Returns:
            `exp(-sum)` of the dimming along the ray. One outside the
            grid.
        """
        var step = self.cell * MARCH
        var high = (
            self.low
            + Vector3(Float32(self.nx), Float32(self.ny), Float32(self.nz))
            * self.cell
        )
        var total = Float32(0)
        var p = origin + toward * (self.cell * 0.5)
        while (
            p.x >= self.low.x
            and p.y >= self.low.y
            and p.z >= self.low.z
            and p.x <= high.x
            and p.y <= high.y
            and p.z <= high.z
        ):
            total += self.dimming(p) * step
            p = p + toward * step
        return exp(-total)

    def sky(self, origin: Vector3, rays: List[Vector3]) -> Float32:
        """Return the share of the open sky a point sees.

        Args:
            origin: The point, in meters.
            rays: The sky's directions, from `sky_rays`.

        Returns:
            The mean of `through` over the rays. One with no ray.
        """
        if len(rays) == 0:
            return 1
        var total = Float32(0)
        for index in range(len(rays)):  # pragma: no branch
            total += self.through(origin, rays[index])
        return total / Float32(len(rays))


def sky_rays() -> List[Vector3]:
    """Return the `SKY_RAYS` unit directions of the open sky.

    Returns:
        Straight up, six directions 45 degrees up a sixth of a turn
        apart, and six 10 degrees up between them, toward the horizon.
    """
    var rays: List[Vector3] = [Vector3(0, 1, 0)]
    var turn = Float32(2) * Float32(pi)
    var rings: List[Float32] = [Float32(45), Float32(10)]
    for ring in range(len(rings)):  # pragma: no branch
        var up = rings[ring] / 180 * Float32(pi)
        for k in range(6):  # pragma: no branch
            var round = turn * (Float32(k) + 0.5 * Float32(ring)) / 6
            rays.append(
                Vector3(cos(up) * cos(round), sin(up), cos(up) * sin(round))
            )
    return rays^


def sway_offset(mut graph: NodeGraph, motion: CrownMotion) raises -> NodeRef:
    """Add the nodes that move a crown's vertex in the wind, and return
    the offset.

    The offset is a swing of `motion.reach` along the wind and a flutter
    of `motion.flutter` up and down, each a sine of the `SWAY_TIME`
    uniform at its own rate, with a phase that changes through the crown.
    Both are scaled by the vertex's share: the square of its height over
    `SWAY_HEIGHT`, at most `SWAY_MOST`, times from 0.35 at the trunk to
    one at `SWAY_SPREAD` out from it.

    Args:
        graph: The graph to add the nodes to.
        motion: How the wind moves the crown.

    Returns:
        The offset node, a `vec3` in the tree's own frame.

    Raises:
        Error: Never; the nodes are fixed.
    """
    var turn = Float32(2) * Float32(pi)
    var time = graph.uniform(String(SWAY_TIME), Float32(0))
    var p = graph.position_local()
    var high = graph.clamp(
        graph.mul(graph.swizzle(p, "y"), graph.float(1 / SWAY_HEIGHT)),
        graph.float(0),
        graph.float(SWAY_MOST),
    )
    var spread = graph.clamp(
        graph.mul(
            graph.length(graph.swizzle(p, "xz")), graph.float(1 / SWAY_SPREAD)
        ),
        graph.float(0),
        graph.float(1),
    )
    var weight = graph.mul(
        graph.mul(high, high),
        graph.add(graph.float(0.35), graph.mul(spread, graph.float(0.65))),
    )
    var swing = graph.sin(
        graph.add(
            graph.mul(time, graph.float(turn * motion.rate.to(PER_SECOND))),
            graph.dot(
                p, graph.vec3(SWING_PHASE[0], SWING_PHASE[1], SWING_PHASE[2])
            ),
        )
    )
    var flutter = graph.sin(
        graph.add(
            graph.mul(
                time, graph.float(turn * motion.flutter_rate.to(PER_SECOND))
            ),
            graph.dot(
                p,
                graph.vec3(
                    FLUTTER_PHASE[0], FLUTTER_PHASE[1], FLUTTER_PHASE[2]
                ),
            ),
        )
    )
    var reach = motion.reach.to(METER)
    var along = graph.vec3(
        motion.downwind.x * reach, 0, motion.downwind.y * reach
    )
    var up = graph.vec3(0, motion.flutter.to(METER), 0)
    var moved = graph.add(graph.mul(along, swing), graph.mul(up, flutter))
    return graph.mul(moved, weight)


def game_sway(motion: CrownMotion) -> SwayMotion:
    """Return the sway that `sway_offset` makes, for `GameRenderer`.

    The game renderer reckons the same offset at each vertex without the
    node program: see `SwayMotion`.

    Args:
        motion: How the wind moves the crown.

    Returns:
        The sway, its rates in radians a second.
    """
    var turn = Float32(2) * Float32(pi)
    var reach = motion.reach.to(METER)
    return SwayMotion(
        motion.downwind.x * reach,
        motion.downwind.y * reach,
        motion.flutter.to(METER),
        turn * motion.rate.to(PER_SECOND),
        turn * motion.flutter_rate.to(PER_SECOND),
        SIMD[DType.float32, 4](
            SWING_PHASE[0], SWING_PHASE[1], SWING_PHASE[2], 0
        ),
        SIMD[DType.float32, 4](
            FLUTTER_PHASE[0], FLUTTER_PHASE[1], FLUTTER_PHASE[2], 0
        ),
        SWAY_HEIGHT,
        SWAY_SPREAD,
        SWAY_MOST,
    )


def leaf_shading(sway: Optional[SwayMotion]) -> GameShading:
    """Return what `foliage_program` does, for `GameRenderer`: a back face
    lit as its front, the baked `SUNLIT` in place of the shadow, the baked
    `SKYLIT` on the indirect light, and the sway, if any.

    Args:
        sway: The sway of `foliage_program(motion)`, or None for the still
            program.

    Returns:
        The shading.
    """
    return GameShading(True, String(SUNLIT), String(SKYLIT), sway)


def wood_shading(sway: SwayMotion) -> GameShading:
    """Return what `wood_program` does, for `GameRenderer`: the sway alone.

    Args:
        sway: The sway of `wood_program(motion)`.

    Returns:
        The shading.
    """
    return GameShading(False, String(""), String(""), sway)


def foliage_program() raises -> NodeProgram:
    """Return the node program that lights still leaves as their
    attributes say.

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
    _light_leaves(graph)
    return graph.compile()


def foliage_program(motion: CrownMotion) raises -> NodeProgram:
    """Return the node program that lights leaves as their attributes say
    and sways them in the wind.

    Args:
        motion: How the wind moves the crowns.

    Returns:
        The compiled program, with a `POSITION_NODE` from `sway_offset`,
        and the outputs of the still program.

    Raises:
        Error: Never; the graph is fixed.
    """
    var graph = NodeGraph()
    _light_leaves(graph)
    graph.set_output(POSITION_NODE, sway_offset(graph, motion))
    return graph.compile()


def wood_program(motion: CrownMotion) raises -> NodeProgram:
    """Return the node program that sways a crown's wood in the wind, as
    its leaves sway.

    Args:
        motion: How the wind moves the crowns.

    Returns:
        The compiled program, with a `POSITION_NODE` and no other output.

    Raises:
        Error: Never; the graph is fixed.
    """
    var graph = NodeGraph()
    graph.set_output(POSITION_NODE, sway_offset(graph, motion))
    return graph.compile()


def _light_leaves(mut graph: NodeGraph) raises:
    """Set the outputs that light a leaf: its normal turned to the front,
    its baked sun as the shadow, and its baked sky as the occlusion."""
    var behind = graph.mul(
        graph.sub(graph.front_facing(), graph.float(1.0)), graph.float(2.0)
    )
    graph.set_output(NORMAL_NODE, graph.mul(graph.normal_world(), behind))
    var sun = graph.attribute(String(SUNLIT), NODE_FLOAT)
    graph.set_output(RECEIVED_SHADOW_NODE, graph.mul(graph.vec3(1, 1, 1), sun))
    graph.set_output(AO_NODE, graph.attribute(String(SKYLIT), NODE_FLOAT))


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
        mut self,
        p: Vector3,
        n: Vector3,
        c: Vector3,
        sun: Float32,
        sky: Float32,
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
            base + along * length - normal * droop,
            normal,
            color,
            sun,
            sky,
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
