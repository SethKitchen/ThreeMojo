# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A drawn outline given thickness, from three.js
`src/geometries/ExtrudeGeometry.js`.

An extrusion is a shape at two heights with walls between them. The shape
is filled in twice, once at each end, and every edge of every contour
becomes a quad running from one end to the other. A hole in the shape
becomes a shaft through the solid, with walls of its own facing inward.

## Layers

The vertices are built in layers. Each layer holds every contour point
once, at one height and drawn in by one distance, and the walls join each
layer to the next. Without a bevel there are `steps + 1` layers, all the
same size, from the back face to the front.

A bevel adds `bevel_segments` layers at each end. Those layers are drawn
in toward the middle of the shape and pushed out past the ends, by the
sine and the cosine of a quarter turn, so the edge is rounded rather than
square. three.js's arithmetic exactly, including `bevel_offset`, which
moves every layer in without rounding anything and makes a lip.

## Which way a bevel goes

three.js measures a bevel *out* from the shape drawn. The two end faces
are the outline itself, and the body between them stands `bevel_size`
proud of it all the way round. So a letter with a bevel is a little bolder
than the font drew it, and the rounded part is the run from the face out
to the body.

## Moving a contour out

A corner has two edges, and moving both out by the same distance moves the
corner along the line that keeps them parallel: the miter. The vector for
it is the one that has a dot product of one with each edge's outward
normal, which is the sum of the two normals over one plus their dot
product.

That denominator is zero when the two normals are opposite, which is a
corner that folds straight back on itself. `geometries.shape` has already
dropped every corner that turns by nothing, and such a corner turns by
nothing, so it cannot arrive here.

Outward means to the right of each edge, for every contour. The outline
runs counter-clockwise, so its right is away from the solid and the
outline grows. A hole runs clockwise, so its right is the hole's own
inside and the hole shrinks. One rule, and the solid grows by the same
distance everywhere, which is what three.js's bevel does.

## The faces are flat

three.js builds an extrusion without an index buffer and works its normals
out from the triangles, so every vertex belongs to one face and takes that
face's normal. A bevel of three segments is three flat bands and not a
curve. This is the same, because the texture coordinates on a wall are not
shared either: a wall is measured along x or along y, whichever it runs
further in, and two walls that meet at a corner disagree about which.

## What is not here

three.js can also sweep a shape along a path, its `extrudePath`. That is a
tube with a shape for a cross-section, and the frames it needs are the
ones `geometries.tube` already carries. It is not ported here.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, UV
from geometries.shape import Contours, triangulate
from math.path import Shape
from math.vector2 import Vector2
from std.math import cos, pi, sin
from units.si import Length, METER


def _miters(points: List[Vector2], start: Int, count: Int) -> List[Vector2]:
    """Return the direction each corner of one contour moves in when the
    contour is moved out, one vector per point.

    Moving a corner by `size` times its vector moves both of its edges out
    by exactly `size`, which is what keeps a bevel's band an even width.
    """
    var out = List[Vector2]()
    for index in range(count):  # pragma: no branch
        var here = points[start + index]
        var before = points[start + (index + count - 1) % count]
        var after = points[start + (index + 1) % count]
        var incoming = here - before
        incoming.normalize()
        var outgoing = after - here
        outgoing.normalize()
        # To the right of each edge, which is away from the solid for
        # every contour, the outline and its holes alike.
        var first = Vector2(incoming.y, -incoming.x)
        var second = Vector2(outgoing.y, -outgoing.x)
        var share = 1 + first.dot(second)
        out.append((first + second) * (1 / share))
    return out^


def _layers(
    depth: Length,
    steps: Int,
    bevel_enabled: Bool,
    bevel_thickness: Length,
    bevel_size: Length,
    bevel_offset: Length,
    bevel_segments: Int,
    mut heights: List[Float32],
    mut insets: List[Float32],
):
    """Fill `heights` and `insets` with one entry per layer, back to front.

    A bevel's layers come first and last, each one further past the end
    face and less far out from the outline, by the cosine and the sine of
    how far around a quarter turn it is. The layers between are the
    extrusion itself, all the full distance out.
    """
    var full = Float32(0)
    if bevel_enabled:
        full = bevel_size.value + bevel_offset.value
        for band in range(bevel_segments):  # pragma: no branch
            var part = Float32(band) / Float32(bevel_segments) * Float32(pi) / 2
            heights.append(-bevel_thickness.value * cos(part))
            insets.append(bevel_size.value * sin(part) + bevel_offset.value)
    heights.append(0)
    insets.append(full)
    for step in range(1, steps + 1):  # pragma: no branch
        heights.append(depth.value / Float32(steps) * Float32(step))
        insets.append(full)
    if bevel_enabled:
        for band in range(bevel_segments - 1, -1, -1):  # pragma: no branch
            var part = Float32(band) / Float32(bevel_segments) * Float32(pi) / 2
            heights.append(depth.value + bevel_thickness.value * cos(part))
            insets.append(bevel_size.value * sin(part) + bevel_offset.value)


def _place(
    cut: Contours,
    miters: List[Vector2],
    heights: List[Float32],
    insets: List[Float32],
) -> List[Float32]:
    """Return every layer's vertices, three numbers each, layer by layer.

    These are the positions the faces are copied from. They are not the
    geometry: a face takes its own copy, because the walls do not share a
    texture coordinate with the ends or with one another.
    """
    var out = List[Float32]()
    for layer in range(len(heights)):  # pragma: no branch
        for index in range(len(cut.points)):  # pragma: no branch
            var moved = cut.points[index] + miters[index] * insets[layer]
            out.append(moved.x)
            out.append(moved.y)
            out.append(heights[layer])
    return out^


def _copy_vertex(
    placed: List[Float32], vertex: Int, mut data: List[Float32]
) -> Vector2:
    """Append one placed vertex to `data`, and return the two numbers a
    cap's texture coordinate is made of."""
    data.append(placed[vertex * 3])
    data.append(placed[vertex * 3 + 1])
    data.append(placed[vertex * 3 + 2])
    return Vector2(placed[vertex * 3], placed[vertex * 3 + 1])


def extrude(
    shape: Shape,
    depth: Length,
    steps: Int = 1,
    curve_segments: Int = 12,
    bevel_enabled: Bool = False,
    bevel_thickness: Length = Length(0.2, METER),
    bevel_size: Length = Length(0.1, METER),
    bevel_offset: Length = Length(0, METER),
    bevel_segments: Int = 3,
) raises -> BufferGeometry:
    """Return `shape` extruded along the z axis, from zero to `depth`.

    Args:
        shape: The outline and its holes.
        depth: How thick the solid is; positive.
        steps: How many layers the extrusion is cut into; at least one.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.
        bevel_enabled: True to round the two edges off.
        bevel_thickness: How far past each end face the bevel reaches;
            positive when there is a bevel.
        bevel_size: How far out from the outline the body stands; not
            negative.
        bevel_offset: How far out every layer is moved before the bevel is
            measured, the end faces included, which makes a lip rather
            than rounding an edge.
        bevel_segments: How many bands each bevel is cut into; at least one
            when there is a bevel.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and no
        index buffer, wound counter-clockwise seen from outside. The
        normals are worked out from the triangles, so every face is flat,
        as three.js's are. A cap's texture coordinate is the point itself;
        a wall's runs along x or y, whichever the wall covers more of, and
        up the negative of z, which is three.js's own generator.

    Raises:
        Error: If the depth is not positive, if there are fewer than one
            step or one curve segment, if a bevel has no thickness, a
            negative size or fewer than one band, or if the shape cannot be
            filled in; see `geometries.shape.triangulate`.
    """
    if depth.value <= 0:
        raise Error("An extrusion needs a positive depth")
    if steps < 1:
        raise Error("An extrusion needs at least one step")
    if bevel_enabled and bevel_segments < 1:
        raise Error("A bevel needs at least one band")
    if bevel_enabled and bevel_thickness.value <= 0:
        raise Error("A bevel needs a positive thickness")
    if bevel_enabled and bevel_size.value < 0:
        raise Error("A bevel cannot reach a negative distance in")

    var cut = triangulate(shape, curve_segments)
    var miters = List[Vector2]()
    for contour in range(cut.contour_count()):  # pragma: no branch
        var ring = _miters(cut.points, cut.starts[contour], cut.counts[contour])
        for index in range(len(ring)):  # pragma: no branch
            miters.append(ring[index])

    var heights = List[Float32]()
    var insets = List[Float32]()
    _layers(
        depth,
        steps,
        bevel_enabled,
        bevel_thickness,
        bevel_size,
        bevel_offset,
        bevel_segments,
        heights,
        insets,
    )
    var placed = _place(cut, miters, heights, insets)

    var wide = len(cut.points)
    var top = (len(heights) - 1) * wide
    var data = List[Float32]()
    var uvs = List[Float32]()

    # The two ends. The back one faces away from the camera's half of the
    # z axis, so its triangles are wound the other way round.
    for triangle in range(cut.triangle_count()):  # pragma: no branch
        var first = cut.index[triangle * 3]
        var second = cut.index[triangle * 3 + 1]
        var third = cut.index[triangle * 3 + 2]
        var back: List[Int] = [third, second, first]
        for corner in range(3):  # pragma: no branch
            var flat = _copy_vertex(placed, back[corner], data)
            uvs.append(flat.x)
            uvs.append(flat.y)
        var front: List[Int] = [first, second, third]
        for corner in range(3):  # pragma: no branch
            var flat = _copy_vertex(placed, top + front[corner], data)
            uvs.append(flat.x)
            uvs.append(flat.y)

    # The walls: one quad per edge per layer, two triangles each.
    for contour in range(cut.contour_count()):  # pragma: no branch
        var start = cut.starts[contour]
        var count = cut.counts[contour]
        for edge in range(count):  # pragma: no branch
            var here = start + edge
            var next = start + (edge + 1) % count
            for layer in range(len(heights) - 1):  # pragma: no branch
                var low = layer * wide
                var high = (layer + 1) * wide
                var quad: List[Int] = [
                    low + here,
                    low + next,
                    high + next,
                    high + here,
                ]
                # Which way the wall runs: three.js measures it along the
                # axis the first edge covers more of.
                var along_x = abs(
                    placed[quad[0] * 3 + 1] - placed[quad[1] * 3 + 1]
                ) < abs(placed[quad[0] * 3] - placed[quad[1] * 3])
                var corners: List[Int] = [
                    quad[0],
                    quad[1],
                    quad[2],
                    quad[0],
                    quad[2],
                    quad[3],
                ]
                for corner in range(6):  # pragma: no branch
                    var vertex = corners[corner]
                    _ = _copy_vertex(placed, vertex, data)
                    if along_x:
                        uvs.append(placed[vertex * 3])
                    else:
                        uvs.append(placed[vertex * 3 + 1])
                    uvs.append(1 - placed[vertex * 3 + 2])

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.compute_vertex_normals()
    return geometry^
