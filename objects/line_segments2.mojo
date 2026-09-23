# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Lines wider than a pixel, from three.js `examples/jsm/lines`.

three.js draws a `Line` one pixel wide, because WebGL ignores
`linewidth`. Its answer is `LineSegments2` and `Line2`: every segment is
drawn as a quad of two triangles that the vertex shader turns to face the
screen, with `LineMaterial` giving the width. This module is that answer.

## What a wide line is made of

A geometry whose `position` attribute holds its points in pairs, one pair
per segment: the layout `objects.line.SEGMENTS` reads, and the layout
three.js's `LineSegmentsGeometry` keeps in `instanceStart` and
`instanceEnd`. `line_segments_geometry` builds one from pairs of points.
`line_geometry` builds one from a path, three.js's `LineGeometry`, which
repeats every inner point so that each segment has its own two ends. A
`color` attribute, three floats per point, gives the vertex colors.

So an edges or a wireframe geometry is already a wide-line geometry.
three.js's `fromEdgesGeometry` and `fromWireframeGeometry` copy the pairs
across; here the same geometry id is named by a `LineSegments2`.

## Two objects, one struct

three.js's `Line2` is a `LineSegments2` whose geometry is a
`LineGeometry`. Nothing else differs, so here `Line2` is another name for
`LineSegments2`, and the difference is which function built the geometry.

## How a wide line is drawn

As triangles, through the pipeline every other triangle goes through.
`Renderer.prepare` builds them, as three.js's `LineMaterial` vertex shader
builds them: a quad per segment, and a round cap at each end. Both
rasterizers then fill them by the triangle rule, so they agree by
construction. See `renderers.renderer` and the wiki's Lines page.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from render.linerule import dash_covers
from std.math import ceil, floor, max, min, pi, sqrt

# How many dashes one segment may be cut into. A pattern much finer than
# the segment would build a triangle pair per dash, and a pattern of a
# millimeter along a kilometer would build a million of them. three.js
# folds the distance per fragment and never counts the dashes, so it has
# no such limit; this port refuses the pattern instead.
comptime MAX_DASHES_PER_SEGMENT = 4096
# The fewest and the most triangles one round cap is built from.
comptime MIN_CAP_STEPS = 2
comptime MAX_CAP_STEPS = 64


struct LineSegments2(ImplicitlyCopyable):
    """A list of wide sticks at a scene node, three.js's `LineSegments2`."""

    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId
    # Whether `Renderer.prepare` may leave this line out when the bounding
    # sphere of its points, carried to world space, lies outside the
    # camera frustum. The sphere bounds the points and not the width, as
    # three.js's does.
    var frustum_culled: Bool

    def __init__(
        out self,
        geometry: GeometryId,
        material: MaterialId,
        node: NodeId,
        *,
        frustum_culled: Bool = True,
    ) raises:
        """Bind a stored geometry and material to a scene node.

        Whether the ids exist is not checkable here, for the reason
        `objects.mesh.Mesh` gives. The renderer checks them.

        Args:
            geometry: Id of the geometry whose points to join, in pairs.
            material: Id of the material to draw them with. It must be
                `BASIC`, and `line_material` builds one.
            node: Index of the scene node giving its world transform.
            frustum_culled: Whether the renderer can skip this line when
                its bounds are out of view.

        Raises:
            Error: If any id is negative.
        """
        if node.value < 0:
            raise Error("A wide line must name a scene node")
        if geometry.value < 0:
            raise Error("A wide line must name a geometry")
        if material.value < 0:
            raise Error("A wide line must name a material")
        self.geometry = geometry
        self.material = material
        self.node = node
        self.frustum_culled = frustum_culled


# three.js's `Line2` is a `LineSegments2` with a path for a geometry; see
# the module docstring.
comptime Line2 = LineSegments2


def _geometry_of(
    points: List[Vector3], colors: List[FloatColor]
) raises -> BufferGeometry:
    """Return a geometry holding `points`, and `colors` when there are any.

    Args:
        points: The points, already in pairs.
        colors: One color per point, or none.

    Returns:
        The geometry.

    Raises:
        Error: If there are colors, but not one per point.
    """
    var has_colors = len(colors) > 0
    if has_colors and len(colors) != len(points):
        raise Error("A wide line needs one color per point, or none")
    var numbers = List[Float32]()
    for index in range(len(points)):
        numbers.append(points[index].x)
        numbers.append(points[index].y)
        numbers.append(points[index].z)
    var shape = BufferGeometry()
    shape.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    if has_colors:
        var channels = List[Float32]()
        # At least one: `has_colors` asked for a count above zero.
        for index in range(len(colors)):  # pragma: no branch
            channels.append(colors[index].r)
            channels.append(colors[index].g)
            channels.append(colors[index].b)
        shape.set_attribute(String(COLOR), BufferAttribute(channels^, 3))
    return shape^


def line_segments_geometry(
    points: List[Vector3], colors: List[FloatColor] = List[FloatColor]()
) raises -> BufferGeometry:
    """Return a geometry of separate sticks, three.js's
    `LineSegmentsGeometry.setPositions` and `setColors`.

    Args:
        points: The sticks' ends, two per stick, in order.
        colors: One linear color per point, or none. The alpha is not
            kept: three.js's `setColors` keeps three channels.

    Returns:
        The geometry, for a `LineSegments2`.

    Raises:
        Error: If the point count is odd, or there are colors but not one
            per point.
    """
    if len(points) % 2 != 0:
        raise Error("Wide line segments come in pairs of points")
    return _geometry_of(points, colors)


def line_geometry(
    points: List[Vector3], colors: List[FloatColor] = List[FloatColor]()
) raises -> BufferGeometry:
    """Return a geometry of one path through `points`, three.js's
    `LineGeometry.setPositions` and `setColors`.

    Every inner point is written twice, once as the end of one segment and
    once as the start of the next, as three.js writes it. A path of fewer
    than two points has no segment.

    Args:
        points: The path, in order.
        colors: One linear color per point, or none. The alpha is not
            kept, as in `line_segments_geometry`.

    Returns:
        The geometry, for a `Line2`.

    Raises:
        Error: If there are colors, but not one per point.
    """
    if len(colors) > 0 and len(colors) != len(points):
        raise Error("A wide line needs one color per point, or none")
    var pairs = List[Vector3]()
    var tints = List[FloatColor]()
    for index in range(len(points) - 1):
        pairs.append(points[index])
        pairs.append(points[index + 1])
        if len(colors) > 0:
            tints.append(colors[index])
            tints.append(colors[index + 1])
    return _geometry_of(pairs, tints)


def cap_steps(radius: Float32) -> Int:
    """Return how many triangles one round cap is built from.

    three.js's `LineMaterial` cuts a round cap out of a square per
    fragment. Here the cap is built as a fan of triangles, so that it is
    drawn by the triangle rule like the rest of the line. The count grows
    with the square root of the radius, which keeps the fan within an
    eighth of a pixel of the true circle: a fan of n steps over a half
    turn misses it by about `r * pi^2 / (8 * n^2)`, and n is `pi * sqrt(r)`.

    Args:
        radius: The cap's radius, in pixels on the image.

    Returns:
        The count, from `MIN_CAP_STEPS` to `MAX_CAP_STEPS`.
    """
    var wanted = ceil(Float32(pi) * sqrt(max(radius, Float32(0))))
    return Int(min(max(wanted, Float32(MIN_CAP_STEPS)), Float32(MAX_CAP_STEPS)))


def dash_spans(
    start: Float32, end: Float32, dash: Float32, gap: Float32
) raises -> List[Float32]:
    """Return which parts of a segment a dash pattern draws.

    three.js's `LineMaterial` folds the distance along the line per
    fragment and throws a fragment in a gap away. Here the segment is cut
    at the dash boundaries instead, and each dash becomes a quad of its
    own. The distance varies linearly along the segment, in the scene, so
    the cut lands where the fold would change its answer. `dash_covers`
    is the fold, and a segment whose distance does not change asks it.

    Args:
        start: The distance at the segment's start, scaled and offset.
        end: The distance at its end.
        dash: How long each dash is.
        gap: How long the gap after it is. Zero draws the whole segment.

    Returns:
        Pairs of fractions of the way from start to end, each pair a
        drawn part, the smaller first.

    Raises:
        Error: If the pattern repeats more than `MAX_DASHES_PER_SEGMENT`
            times along the segment.
    """
    var spans = List[Float32]()
    if start == end or gap <= 0:
        if dash_covers(start, dash, gap):
            spans.append(0)
            spans.append(1)
        return spans^
    var period = dash + gap
    var low = min(start, end)
    var high = max(start, end)
    var first = Int(floor(low / period))
    var last = Int(floor(high / period))
    if last - first >= MAX_DASHES_PER_SEGMENT:
        raise Error(
            "A wide line's dash pattern is too fine for its length: one"
            " segment would be cut into more than 4096 dashes"
        )
    var span = end - start
    for repeat in range(first, last + 1):  # pragma: no branch
        var on = max(Float32(repeat) * period, low)
        var off = min(Float32(repeat) * period + dash, high)
        if off > on:
            var one = (on - start) / span
            var two = (off - start) / span
            spans.append(min(one, two))
            spans.append(max(one, two))
    return spans^
