# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Points joined by one-pixel lines, from three.js `src/objects/Line.js`.

three.js has three objects here and one class body: `Line` joins its points
into one open path, `LineLoop` closes that path, and `LineSegments` reads
its points two at a time as separate sticks. They differ only in how the
points are paired, which is what `LineMode` carries.

A `Line` names the same three ids a `Mesh` does -- a node, a geometry and a
material -- for the reasons `objects.mesh` gives. It adds the mode and
nothing else, so it stays as small and as copyable as a mesh.

## What a line is made of

A line geometry carries its points in order, in the `position` attribute,
and carries no index buffer. `BufferGeometry.set_index` demands whole
triangles, because an index buffer here is a triangle index, so it cannot
describe segments at all. `Renderer.prepare_lines` refuses an indexed
geometry rather than reading a triangle list as if it were a line list.
That is also the shape three.js produces: `EdgesGeometry` and
`WireframeGeometry` both build a plain array of point pairs.

## What a line is drawn with

`LineBasicMaterial` in three.js, and a `BASIC` material here. A line has no
surface, so it has no normal, and every lighting term needs one. It has no
surface coordinates either, so there is nothing to sample a map with.
`Renderer.prepare_lines` refuses a lit kind and a map, rather than carrying
either and quietly ignoring it. `render.rasterizer.check_line_state` makes
the same refusal of the kind at the boundary both backends read.

The material color, its opacity, its blending and the geometry vertex
colors all work as they do on a mesh. So does the fog: a line that recedes
is veiled like anything else.

## What a dashed line measures

A dashed material, three.js's `LineDashedMaterial`, needs to know how far
along the line every point is. three.js keeps that in a `lineDistance`
attribute that `computeLineDistances` fills in, and forgets the dashes
when nobody calls it. Here `line_distances` works it out from the points
themselves, in the geometry's own space, and `Renderer.prepare_lines`
calls it for every dashed line, so there is nothing to forget.

The arithmetic is three.js's. A strip accumulates from its first point.
A list of sticks accumulates across the sticks too, as three.js's
`LineSegments.computeLineDistances` does, so the pattern runs on from one
stick to the next. A loop is a strip: its closing segment runs from the
last point's distance back to zero, as three.js's does, so the pattern
along that one segment runs backward.

## What a line is not

It is one pixel wide, always. three.js is the same: WebGL ignores
`linewidth`, which is why three.js ships `Line2` as geometry rather than as
a line. See `render.linerule` for what a width of one pixel means and what
it would take to have another.

A line is not morphed and not skinned. three.js allows both, and neither
has a caller here yet. Adding one is a matter of routing `core.deform` the
way `Renderer.prepare` routes it, and the mode arithmetic below does not
change.
"""

from core.buffer_attribute import BufferAttribute
from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId


@fieldwise_init
struct LineMode(Equatable, ImplicitlyCopyable, Writable):
    """How the points of a line are paired into segments, as a type rather
    than a bare int.

    The same argument as `objects.skinned_mesh.BindMode`: three small
    integers that mean three different things must not be interchangeable,
    and the type stops a bare integer at compile time. `Line.__init__`
    stops `LineMode(9)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `STRIP`, `LOOP` or `SEGMENTS`."""
        return self == STRIP or self == LOOP or self == SEGMENTS


# One open path through every point in order: the three.js `Line`, and the
# default here as it is the base of the three there.
comptime STRIP = LineMode(0)
# The same path, with the last point joined back to the first: the three.js
# `LineLoop`.
comptime LOOP = LineMode(1)
# Points read two at a time as separate sticks: the three.js `LineSegments`,
# and what `EdgesGeometry` and `WireframeGeometry` are drawn with.
comptime SEGMENTS = LineMode(2)


def segment_count(mode: LineMode, vertices: Int) raises -> Int:
    """Return how many segments `vertices` points make in `mode`.

    Args:
        mode: How the points are paired.
        vertices: How many points there are.

    Returns:
        The count. A strip of one point and a loop of one point make no
        segment, because a segment needs two ends.

    Raises:
        Error: If the mode is not a named one, if the count is negative,
            or if `SEGMENTS` is given an odd count, which leaves a point
            with nothing to join it to.
    """
    if not mode.is_valid():
        raise Error("A line needs a mode that exists")
    if vertices < 0:
        raise Error("A line cannot have fewer than no points")
    if mode == SEGMENTS:
        if vertices % 2 != 0:
            raise Error("Line segments come in pairs of points")
        return vertices // 2
    if vertices < 2:
        return 0
    if mode == LOOP:
        return vertices
    return vertices - 1


def segment_ends(
    mode: LineMode, vertices: Int, segment: Int
) raises -> Tuple[Int, Int]:
    """Return which two points one segment joins.

    The whole of the difference between the three modes. Everything that
    draws a line walks `segment_count` and asks this, so a strip, a loop
    and a list of sticks share one path through the renderer.

    Args:
        mode: How the points are paired.
        vertices: How many points there are.
        segment: Which segment, from zero.

    Returns:
        The index of each end, in order.

    Raises:
        Error: If the mode is not a named one, if the point count is
            negative or is odd under `SEGMENTS`, or if there is no such
            segment.
    """
    var count = segment_count(mode, vertices)
    if segment < 0 or segment >= count:
        raise Error("Line segment index out of range")
    if mode == SEGMENTS:
        return (segment * 2, segment * 2 + 1)
    # The closing segment of a loop is the only one that wraps, and taking
    # the remainder is how it does: every other segment of every mode ends
    # one past where it starts.
    return (segment, (segment + 1) % vertices)


struct Line(ImplicitlyCopyable):
    """A path or a list of sticks, drawn one pixel wide at a scene node."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId
    # How the points of the geometry are paired into segments.
    var mode: LineMode
    # Whether `Renderer.prepare_lines` may leave this line out when its
    # bounding sphere, carried to world space, lies outside the camera
    # frustum. On by default, as the flag of a `Mesh` is and as the
    # three.js `frustumCulled` is.
    var frustum_culled: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        *,
        mode: LineMode = STRIP,
        frustum_culled: Bool = True,
    ) raises:
        """Bind a stored geometry and material to a scene node.

        Whether the ids exist is not checkable here, for the reason
        `objects.mesh.Mesh` gives: a line holds none of the stores. The
        renderer has them all and raises if any id is out of range.

        Args:
            geometry: Id of the geometry whose points to join.
            material: Id of the material to draw them with. It must be
                `BASIC` and carry no map. The renderer checks that, where
                it can see the store.
            node: Index of the scene node giving its world transform.
            mode: How the points are paired. `STRIP` unless said
                otherwise, as the three.js `Line` is the base of the three.
            frustum_culled: Whether the renderer can skip this line when
                its bounds are out of view.

        Raises:
            Error: If any id is negative, or the mode is not a named one.
        """
        if node.value < 0:
            raise Error("A line must name a scene node")
        if geometry.value < 0:
            raise Error("A line must name a geometry")
        if material.value < 0:
            raise Error("A line must name a material")
        if not mode.is_valid():
            raise Error("A line needs a mode that exists")
        self.geometry = geometry
        self.material = material
        self.node = node
        self.mode = mode
        self.frustum_culled = frustum_culled

    def segment_count(self, vertices: Int) raises -> Int:
        """Return how many segments this line makes of `vertices` points.

        Args:
            vertices: How many points its geometry holds.

        Returns:
            The count, from `segment_count` in this module.

        Raises:
            Error: If the count is negative, or is odd under `SEGMENTS`.
        """
        return segment_count(self.mode, vertices)


def line_distances(
    mode: LineMode, positions: BufferAttribute
) raises -> List[Float32]:
    """Return how far along the line each point is, in the geometry's units.

    three.js's `Line.computeLineDistances` and
    `LineSegments.computeLineDistances`, which agree: both accumulate the
    distance from each point to the next from the first point on. A loop
    accumulates as a strip does, so its closing segment runs the pattern
    backward, as three.js's does. See the module docstring.

    Args:
        mode: How the points are paired.
        positions: The points, three floats each, in order.

    Returns:
        One distance per point, from zero at the first.

    Raises:
        Error: If the mode is not a named one, if the count is odd under
            `SEGMENTS`, or if the attribute holds fewer than three floats
            per point.
    """
    var count = positions.count()
    _ = segment_count(mode, count)
    var distances = List[Float32]()
    var so_far = Float32(0)
    for point in range(count):
        if point > 0:
            var before = positions.vector3(point - 1)
            var here = positions.vector3(point)
            so_far += (here - before).length()
        distances.append(so_far)
    return distances^
