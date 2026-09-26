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
stick to the next -- but the empty space between two sticks is no line,
and measures nothing: each stick starts where the last one ended. A loop
is a strip: its closing segment runs from the
last point's distance back to zero, as three.js's does, so the pattern
along that one segment runs backward.

## What a line is not

It is one pixel wide, always. three.js is the same: WebGL ignores
`linewidth`, which is why three.js ships `Line2` as geometry rather than as
a line. See `render.linerule` for what a width of one pixel means, and
`objects.line_segments2` for `Line2`, which is drawn as triangles.
`Renderer.prepare_lines` refuses a material with a width, rather than
drawing it one pixel wide.

A line is not morphed and not skinned. three.js allows both, and neither
has a caller here yet. Adding one is a matter of routing `core.deform` the
way `Renderer.prepare` routes it, and the mode arithmetic below does not
change.
"""

from core.buffer_attribute import BufferAttribute
from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import sqrt

# The attributes a conditional line reads at each vertex: its two control
# points, and the direction of its segment, as three.js's LDraw loader
# names them.
comptime CONTROL0 = "control0"
comptime CONTROL1 = "control1"
comptime DIRECTION = "direction"
# A conditional line's flag is drawn as a dash: a pixel whose flag, blended
# along the segment, is past one half is left out, as three.js's shader
# discards it. So the dash is one half long and the gap after it one.
comptime CONDITIONAL_DASH = Float32(0.5)
comptime CONDITIONAL_GAP = Float32(1.0)


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
    # Whether the line is drawn into the lights' shadow maps, three.js's
    # `castShadow`, and whether it counts as a receiver, `receiveShadow`.
    # Both off by default, as there. A line is unlit, so no shadow falls
    # on it; a receiving line is drawn into a variance map, as three.js
    # draws every receiver into one. See `Renderer.shadow_maps`.
    var cast_shadow: Bool
    var receive_shadow: Bool
    # Whether each segment is drawn only where its two control points lie
    # on one side of it on screen: three.js's `ConditionalLineSegments`
    # with an `LDrawConditionalLineMaterial`. Its geometry carries
    # `CONTROL0`, `CONTROL1` and `DIRECTION`, and its mode is `SEGMENTS`.
    # See `conditional_discard`.
    var conditional: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        *,
        mode: LineMode = STRIP,
        frustum_culled: Bool = True,
        cast_shadow: Bool = False,
        receive_shadow: Bool = False,
        conditional: Bool = False,
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
            cast_shadow: Whether the line is drawn into the shadow maps,
                three.js's `castShadow`. Off unless said otherwise.
            receive_shadow: Whether the line is a receiver, three.js's
                `receiveShadow`. Off unless said otherwise.
            conditional: Whether each segment is drawn only where its
                control points lie on one side of it, three.js's
                `ConditionalLineSegments`. Off unless said otherwise.

        Raises:
            Error: If any id is negative, the mode is not a named one, or
                a conditional line's mode is not `SEGMENTS`.
        """
        if node.value < 0:
            raise Error("A line must name a scene node")
        if geometry.value < 0:
            raise Error("A line must name a geometry")
        if material.value < 0:
            raise Error("A line must name a material")
        if not mode.is_valid():
            raise Error("A line needs a mode that exists")
        if conditional and not (mode == SEGMENTS):
            raise Error(
                "A conditional line is a list of sticks: its mode is SEGMENTS"
            )
        self.geometry = geometry
        self.material = material
        self.node = node
        self.mode = mode
        self.frustum_culled = frustum_culled
        self.cast_shadow = cast_shadow
        self.receive_shadow = receive_shadow
        self.conditional = conditional

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


def _on_screen(mvp: Matrix4, point: Vector3) -> SIMD[DType.float32, 2]:
    """Return a point's x and y in clip space over its w, as the shader
    divides them."""
    ref e = mvp.elements
    var x = e[0] * point.x + e[4] * point.y + e[8] * point.z + e[12]
    var y = e[1] * point.x + e[5] * point.y + e[9] * point.z + e[13]
    var w = e[3] * point.x + e[7] * point.y + e[11] * point.z + e[15]
    return SIMD[DType.float32, 2](x / w, y / w)


def _unit(v: SIMD[DType.float32, 2]) -> SIMD[DType.float32, 2]:
    """Return GLSL's `normalize`: no guard for a vector of no length."""
    return v / sqrt(v[0] * v[0] + v[1] * v[1])


def _sign(x: Float32) -> Float32:
    """Return GLSL's `sign`, and zero for NaN."""
    if x > 0:
        return 1
    if x < 0:
        return -1
    return 0


def conditional_discard(
    mvp: Matrix4,
    position: Vector3,
    direction: Vector3,
    control0: Vector3,
    control1: Vector3,
) -> Float32:
    """Return a vertex's `discardFlag` of three.js's
    `LDrawConditionalLineMaterial`: one if the segment's two control points
    lie on opposite sides of it on screen, else zero.

    The shader puts the segment through the vertex and its end one
    `direction` further, and measures each control point from that end.
    Each vertex does this for itself, so the two ends of a segment can
    disagree, and the flag is blended between them.

    Args:
        mvp: The projection, times the view, times the line's world.
        position: The vertex.
        direction: Its segment's direction, three.js's `direction`.
        control0: The first control point.
        control1: The second.

    Returns:
        One or zero.
    """
    var p0 = _on_screen(mvp, position)
    var p1 = _on_screen(mvp, position + direction)
    var dir = p1 - p0
    var norm = _unit(SIMD[DType.float32, 2](-dir[1], dir[0]))
    var c0 = _unit(_on_screen(mvp, control0) - p1)
    var c1 = _unit(_on_screen(mvp, control1) - p1)
    var d0 = norm[0] * c0[0] + norm[1] * c0[1]
    var d1 = norm[0] * c1[0] + norm[1] * c1[1]
    return 1.0 if _sign(d0) != _sign(d1) else 0.0


def line_distances(
    mode: LineMode, positions: BufferAttribute
) raises -> List[Float32]:
    """Return how far along the line each point is, in the geometry's units.

    three.js's `Line.computeLineDistances` and
    `LineSegments.computeLineDistances`, which agree: both accumulate
    from the first point on, and a stick starts at the distance the last
    stick ended at, not at the gap's far side. A loop
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
        # A stick's first point picks up where the last stick ended, not
        # where it was: the empty space between two sticks is no line,
        # and measures nothing. `LineSegments.computeLineDistances` carries
        # `lineDistances[i - 1]` forward the same way.
        var joined = point > 0
        if mode == SEGMENTS and point % 2 == 0:
            joined = False
        if joined:
            var before = positions.vector3(point - 1)
            var here = positions.vector3(point)
            so_far += (here - before).length()
        distances.append(so_far)
    return distances^
