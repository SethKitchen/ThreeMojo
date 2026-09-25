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

That denominator falls to zero as the two normals swing apart, and a
corner sharp enough sends it there in `Float32` while the shape is still a
perfectly ordinary one. A triangle ten meters long and a millimeter thick
does it: the two normals at its point come out as `(0, -1)` and
`(0.0001, 1)`, whose dot product rounds to exactly minus one, and the
miter is not a number.

So a bevel does what three.js's `getBevelVec` does: it keeps the exact
miter while it is no longer than the square root of two bevel widths and
shrinks a longer one to that length, which rounds a sharp corner off
rather than drawing it out to a spike. A corner whose two edges fold
straight back, where the sum of the normals has no direction left, is
moved along its incoming edge by the same length, as three.js's collinear
branch moves it. This used to refuse any corner sharper than about eleven
degrees, and stood every corner sharper than a right angle out further
than three.js does.

An extrusion without a bevel does not ask the question. It has no distance
to move a corner by, so it does not work out which way to move it, and the
thin triangle above extrudes without complaint. That is not how this was
written at first: the miters were built whatever the bevel did, and
multiplying a number that is not a number by an inset of zero leaves a
number that is not a number.

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

## Two groups

The caps are one group and the walls another, three.js's `addGroup` in
`buildLidFaces` and `buildSideFaces`: the caps wear material 0 and the
walls material 1. So a mesh that wears a list of two materials gives the
faces one and the sides the other, as a three.js text mesh does.

## Along a path

three.js can also sweep a shape along a curve, its `extrudePath`, and the
two overloads that take a `Curve3` or a `CurvePath3` do that. It is a tube
with a shape for a cross-section. The layers stand at `steps + 1` equal
distances along the curve, from `spaced_points`, and each is turned into
the curve's Frenet frame there, from `frenet_frames`: a point's x runs
along the frame's normal and its y along the binormal. The binormal is the
tangent crossed with the normal, so the tangent takes the place of z, and
the front cap faces on along the curve as it faces up z without one.

three.js turns the bevel off when it is given a path, so these overloads
take no bevel. It also has no `depth`: the curve is the depth. The
texture coordinates are the same world generator, read from the swept
vertices, so a cap's are its x and y wherever the curve has carried it.

A wall between two frames that turn is not flat, so the diagonal a quad
is split along is part of the surface. Both forms split it as three.js's
`f4` does, across the quad's second and fourth corners.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
)
from geometries.shape import Contours, triangulate
from math.curve3 import Curve3, CurvePath3, FrenetFrames
from math.path import Shape
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
from units.si import Length, METER

# The smallest `1 + n1 . n2` a corner is still turned rather than folded
# at. Two normals a quarter turn apart give one; opposite normals give
# zero, and there the two edges run straight back along each other and
# meet nowhere. Below this the sum of the normals has no direction a
# `Float32` can be trusted with, and three.js's collinear branch takes
# over: it moves the point along its incoming edge instead.
comptime FOLDED = Float32(1e-6)
# How far a bevel may stand a corner out, in bevel widths: three.js's
# `getBevelVec` keeps the exact miter while it is no longer than this and
# shrinks a longer one to it, so a sharp corner is rounded off rather
# than drawn out to a spike.
comptime MITER_LIMIT = Float32(1.4142135)

# three.js's `UVGenerator.generateTopUV`: the texture coordinates of a cap
# triangle, from the vertices written so far, three floats each, and the
# indices of its three vertices among them.
comptime TopUV = def(List[Float32], Int, Int, Int) thin -> List[Vector2]
# three.js's `generateSideWallUV`: those of a wall quad's four corners.
comptime SideWallUV = def(List[Float32], Int, Int, Int, Int) thin -> List[
    Vector2
]


def world_top_uv(
    vertices: List[Float32], a: Int, b: Int, c: Int
) -> List[Vector2]:
    """Return a cap triangle's texture coordinates, three.js's
    `WorldUVGenerator.generateTopUV`: each vertex's x and y.

    Args:
        vertices: The vertices written so far, three floats each.
        a: The first vertex's index among them.
        b: The second's.
        c: The third's.

    Returns:
        The three coordinates, in the vertices' order.
    """
    return [
        Vector2(vertices[a * 3], vertices[a * 3 + 1]),
        Vector2(vertices[b * 3], vertices[b * 3 + 1]),
        Vector2(vertices[c * 3], vertices[c * 3 + 1]),
    ]


def world_side_wall_uv(
    vertices: List[Float32], a: Int, b: Int, c: Int, d: Int
) -> List[Vector2]:
    """Return a wall quad's texture coordinates, three.js's
    `WorldUVGenerator.generateSideWallUV`: x, or y where the quad's first
    edge covers more of y, and one minus z.

    Args:
        vertices: The vertices written so far, three floats each.
        a: The first corner's index among them.
        b: The second's.
        c: The third's.
        d: The fourth's.

    Returns:
        The four coordinates, in the corners' order.
    """
    var along_x = abs(vertices[a * 3 + 1] - vertices[b * 3 + 1]) < abs(
        vertices[a * 3] - vertices[b * 3]
    )
    var lane = 0 if along_x else 1
    var out = List[Vector2](capacity=4)
    for corner in [a, b, c, d]:  # pragma: no branch
        out.append(
            Vector2(vertices[corner * 3 + lane], 1 - vertices[corner * 3 + 2])
        )
    return out^


struct UVGenerator(Copyable, Movable):
    """How an extrusion's texture coordinates are made: three.js's
    `UVGenerator` option, `WorldUVGenerator` by default."""

    var top: TopUV
    var side_wall: SideWallUV

    def __init__(out self):
        """Return three.js's `WorldUVGenerator`."""
        self.top = world_top_uv
        self.side_wall = world_side_wall_uv

    def __init__(out self, top: TopUV, side_wall: SideWallUV):
        """Return a generator of one's own, three.js's `UVGenerator` option.

        Args:
            top: The coordinates of a cap triangle.
            side_wall: The coordinates of a wall quad.
        """
        self.top = top
        self.side_wall = side_wall


def _miters(points: List[Vector2], start: Int, count: Int) -> List[Vector2]:
    """Return the direction each corner of one contour moves in when the
    contour is moved out, one vector per point.

    Moving a corner by `size` times its vector moves both of its edges out
    by exactly `size`, which is what keeps a bevel's band an even width --
    up to a corner sharper than a right angle. There the exact miter grows
    without limit, and three.js's `getBevelVec` caps it at `MITER_LIMIT`
    bevel widths, which is what this does too: the band narrows at a sharp
    corner rather than running out to a spike. A corner whose two edges
    fold straight back is moved along its incoming edge by the same limit,
    as three.js's collinear branch moves it.

    Args:
        points: Every contour's points.
        start: Where this contour begins.
        count: How many points it has.

    Returns:
        One vector per point, in the order the points are in.
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
        if share <= FOLDED:
            out.append(incoming * MITER_LIMIT)
        elif share < 1:
            # The exact miter has a length of the square root of two over
            # `share`, which is past the limit here; scaled back onto it,
            # the direction kept.
            out.append((first + second) * (1 / sqrt(share)))
        else:
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


def _faces(
    cut: Contours,
    placed: List[Float32],
    layers: Int,
    uv_generator: UVGenerator,
) raises -> BufferGeometry:
    """Return the two caps and the walls between `layers` layers of placed
    vertices, as three.js's `buildLidFaces` and `buildSideWalls` write
    them.

    The texture coordinates come from `uv_generator`, asked as three.js
    asks it: of each cap triangle once its three vertices are written,
    and of each wall quad once its six are, the quad's corners being the
    first, fourth, fifth and sixth.

    Raises:
        Error: If the generator gives a cap other than three coordinates
            or a wall other than four.
    """
    var wide = len(cut.points)
    var top = (layers - 1) * wide
    var data = List[Float32]()
    var uvs = List[Float32]()

    # The two ends. The back one faces away from the front one, so its
    # triangles are wound the other way round.
    for triangle in range(cut.triangle_count()):  # pragma: no branch
        var first = cut.index[triangle * 3]
        var second = cut.index[triangle * 3 + 1]
        var third = cut.index[triangle * 3 + 2]
        var back: List[Int] = [third, second, first]
        for corner in range(3):  # pragma: no branch
            _ = _copy_vertex(placed, back[corner], data)
        _cap_uvs(uv_generator, data, uvs)
        var front: List[Int] = [first, second, third]
        for corner in range(3):  # pragma: no branch
            _ = _copy_vertex(placed, top + front[corner], data)
        _cap_uvs(uv_generator, data, uvs)

    var lids = len(data) // 3

    # The walls: one quad per edge per layer, two triangles each.
    for contour in range(cut.contour_count()):  # pragma: no branch
        var start = cut.starts[contour]
        var count = cut.counts[contour]
        for edge in range(count):  # pragma: no branch
            var here = start + edge
            var next = start + (edge + 1) % count
            for layer in range(layers - 1):  # pragma: no branch
                var low = layer * wide
                var high = (layer + 1) * wide
                var quad: List[Int] = [
                    low + here,
                    low + next,
                    high + next,
                    high + here,
                ]
                # three.js's `f4` splits the quad across its second and
                # fourth corners. A wall swept along a twisting path is
                # not flat, so the diagonal is part of the surface.
                var corners: List[Int] = [
                    quad[0],
                    quad[1],
                    quad[3],
                    quad[1],
                    quad[2],
                    quad[3],
                ]
                for corner in range(6):  # pragma: no branch
                    _ = _copy_vertex(placed, corners[corner], data)
                # three.js's `f4`: the generator is asked of the quad's
                # corners as written, and its four answers go to the six
                # vertices in the quad's order a, b, d, b, c, d.
                var n = len(data) // 3
                var wall = uv_generator.side_wall(
                    data, n - 6, n - 3, n - 2, n - 1
                )
                if len(wall) != 4:
                    raise Error("A side wall UV generator must give four")
                for pick in [0, 1, 3, 1, 2, 3]:  # pragma: no branch
                    uvs.append(wall[pick].x)
                    uvs.append(wall[pick].y)

    var walls = len(data) // 3 - lids
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.compute_vertex_normals()
    # The caps wear material 0 and the walls material 1, three.js's
    # `addGroup` in `buildLidFaces` and `buildSideFaces`.
    geometry.add_group(0, lids, MaterialIndex(0))
    geometry.add_group(lids, walls, MaterialIndex(1))
    return geometry^


def _sweep(
    cut: Contours,
    spine: List[Vector3],
    frames: FrenetFrames,
    uv_generator: UVGenerator,
) raises -> BufferGeometry:
    """Return `cut` swept through one layer per point of `spine`, each
    point of the shape placed `x` along that step's normal and `y` along
    its binormal, as three.js's `extrudePath` places it."""
    var placed = List[Float32]()
    for step in range(len(spine)):  # pragma: no branch
        # At least two steps, so this runs.
        for index in range(len(cut.points)):  # pragma: no branch
            # At least three points in a contour, so this runs.
            var flat = cut.points[index]
            var moved = (
                spine[step]
                + frames.normals[step] * flat.x
                + frames.binormals[step] * flat.y
            )
            placed.append(moved.x)
            placed.append(moved.y)
            placed.append(moved.z)
    return _faces(cut, placed, len(spine), uv_generator)


def _check_sweep(steps: Int) raises:
    """Refuse a sweep of fewer than one step."""
    if steps < 1:
        raise Error("An extrusion needs at least one step")


def extrude(
    shape: Shape,
    path: Curve3,
    steps: Int = 1,
    curve_segments: Int = 12,
    uv_generator: UVGenerator = UVGenerator(),
) raises -> BufferGeometry:
    """Return `shape` swept along `path`, three.js's `ExtrudeGeometry`
    with an `extrudePath`.

    The shape stands at `steps + 1` equal distances along the curve, in
    the curve's Frenet frames: its x runs along the frame's normal and its
    y along the binormal. The back cap is at the start of the curve and
    the front cap at the end. There is no bevel, as three.js turns its
    bevel off when it is given a path.

    Args:
        shape: The outline and its holes, the cross-section of the sweep.
        path: The curve the shape is swept along.
        steps: How many equal runs the curve is cut into; at least one.
        curve_segments: How many straight runs each curve of the shape is
            sampled into; at least one.
        uv_generator: How the texture coordinates are made, three.js's
            `UVGenerator`. `WorldUVGenerator` by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and no
        index buffer, wound counter-clockwise seen from outside. The
        texture coordinates are three.js's `WorldUVGenerator` on the swept
        vertices.

    Raises:
        Error: If there are fewer than one step or one curve segment, if
            the shape cannot be filled in (see
            `geometries.shape.triangulate`), or if the curve has no frame
            at one of the steps (see `Curve3.frenet_frames`).
    """
    _check_sweep(steps)
    var cut = triangulate(shape, curve_segments)
    return _sweep(
        cut,
        path.spaced_points(steps),
        path.frenet_frames(steps, False),
        uv_generator,
    )


def extrude(
    shape: Shape,
    path: CurvePath3,
    steps: Int = 1,
    curve_segments: Int = 12,
    uv_generator: UVGenerator = UVGenerator(),
) raises -> BufferGeometry:
    """Return `shape` swept along a path of curves, three.js's
    `ExtrudeGeometry` with a `CurvePath` for its `extrudePath`.

    The same sweep as the `Curve3` form, measured along the whole path by
    distance.

    Args:
        shape: The outline and its holes, the cross-section of the sweep.
        path: The curves the shape is swept along, end to end.
        steps: How many equal runs the path is cut into; at least one.
        curve_segments: How many straight runs each curve of the shape is
            sampled into; at least one.
        uv_generator: How the texture coordinates are made, three.js's
            `UVGenerator`. `WorldUVGenerator` by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and no
        index buffer, wound counter-clockwise seen from outside.

    Raises:
        Error: If there are fewer than one step or one curve segment, if
            the shape cannot be filled in, if the path has no curves, or
            if it has no frame at one of the steps (see
            `CurvePath3.frenet_frames`).
    """
    _check_sweep(steps)
    var cut = triangulate(shape, curve_segments)
    return _sweep(
        cut,
        path.spaced_points(steps),
        path.frenet_frames(steps, False),
        uv_generator,
    )


def check_extrusion(
    depth: Length,
    steps: Int,
    curve_segments: Int,
    bevel_enabled: Bool,
    bevel_thickness: Length,
    bevel_size: Length,
    bevel_segments: Int,
) raises:
    """Refuse the options an extrusion along z cannot be built with.

    `extrude` calls this before it looks at the shape, and so does a
    caller such as `text_geometry` that may have no shape to hand it.

    Args:
        depth: How thick the solid is; positive.
        steps: How many layers the extrusion is cut into; at least one.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.
        bevel_enabled: True to round the two edges off.
        bevel_thickness: How far past each end face the bevel reaches;
            positive when there is a bevel.
        bevel_size: How far out from the outline the body stands; not
            negative when there is a bevel.
        bevel_segments: How many bands each bevel is cut into; at least one
            when there is a bevel.

    Raises:
        Error: If any option is outside the range given above.
    """
    if depth.value <= 0:
        raise Error("An extrusion needs a positive depth")
    if steps < 1:
        raise Error("An extrusion needs at least one step")
    if curve_segments < 1:
        raise Error("An extrusion needs at least one curve segment")
    if bevel_enabled and bevel_segments < 1:
        raise Error("A bevel needs at least one band")
    if bevel_enabled and bevel_thickness.value <= 0:
        raise Error("A bevel needs a positive thickness")
    if bevel_enabled and bevel_size.value < 0:
        raise Error("A bevel cannot reach a negative distance in")


def _cap_uvs(
    uv_generator: UVGenerator, data: List[Float32], mut uvs: List[Float32]
) raises:
    """Append the texture coordinates of the cap triangle just written,
    three.js's `generateTopUV` of its three vertices."""
    var n = len(data) // 3
    var cap = uv_generator.top(data, n - 3, n - 2, n - 1)
    if len(cap) != 3:
        raise Error("A top UV generator must give three")
    for point in cap:  # pragma: no branch
        uvs.append(point.x)
        uvs.append(point.y)


def _joined(parts: List[BufferGeometry]) raises -> BufferGeometry:
    """Return extrusions end to end, each part's groups moved past the
    parts before it, as three.js's `ExtrudeGeometry` adds shape after shape
    to one geometry."""
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var starts = List[Int]()
    var counts = List[Int]()
    var materials = List[Int]()
    for at in range(len(parts)):  # pragma: no branch
        ref part = parts[at]
        var offset = len(data) // 3
        data.extend(part.attribute_view(String(POSITION)).packed())
        normals.extend(part.attribute_view(String(NORMAL)).packed())
        uvs.extend(part.attribute_view(String(UV)).packed())
        for group in part.groups:  # pragma: no branch
            starts.append(group.start + offset)
            counts.append(group.count)
            materials.append(group.material_index.value)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    for at in range(len(starts)):  # pragma: no branch
        geometry.add_group(starts[at], counts[at], MaterialIndex(materials[at]))
    return geometry^


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
    uv_generator: UVGenerator = UVGenerator(),
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
        uv_generator: How the texture coordinates are made, three.js's
            `UVGenerator`. `WorldUVGenerator` by default.

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
            negative size or fewer than one band, or if the shape cannot
            be filled in; see `geometries.shape.triangulate`.
    """
    check_extrusion(
        depth,
        steps,
        curve_segments,
        bevel_enabled,
        bevel_thickness,
        bevel_size,
        bevel_segments,
    )
    var cut = triangulate(shape, curve_segments)
    # Without a bevel every layer sits on the outline itself, so there is
    # no distance to move a corner by and no miter to work out.
    var miters = List[Vector2]()
    if bevel_enabled:
        for contour in range(cut.contour_count()):  # pragma: no branch
            var ring = _miters(
                cut.points, cut.starts[contour], cut.counts[contour]
            )
            for index in range(len(ring)):  # pragma: no branch
                miters.append(ring[index])
    else:
        for _ in range(len(cut.points)):  # pragma: no branch
            miters.append(Vector2(0, 0))

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
    return _faces(cut, placed, len(heights), uv_generator)


def extrude(
    shapes: List[Shape],
    depth: Length,
    steps: Int = 1,
    curve_segments: Int = 12,
    bevel_enabled: Bool = False,
    bevel_thickness: Length = Length(0.2, METER),
    bevel_size: Length = Length(0.1, METER),
    bevel_offset: Length = Length(0, METER),
    bevel_segments: Int = 3,
    uv_generator: UVGenerator = UVGenerator(),
) raises -> BufferGeometry:
    """Return several shapes extruded along the z axis, three.js's
    `ExtrudeGeometry` given an array of shapes.

    Each shape is extruded as the one-shape form extrudes it, and the
    shapes follow one another in one geometry. Each adds its own two
    groups, its caps wearing material 0 and its walls material 1, as
    three.js's `addShape` adds them shape by shape.

    Args:
        shapes: The outlines, each with its holes; at least one.
        depth: How thick the solid is; positive.
        steps: How many layers the extrusion is cut into; at least one.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.
        bevel_enabled: True to round the two edges off.
        bevel_thickness: How far past each end face the bevel reaches.
        bevel_size: How far out from the outline the body stands.
        bevel_offset: How far out every layer is moved before the bevel is
            measured.
        bevel_segments: How many bands each bevel is cut into.
        uv_generator: How the texture coordinates are made, three.js's
            `UVGenerator`.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and no
        index buffer, and two groups per shape.

    Raises:
        Error: If there is no shape, or for anything the one-shape form
            raises for.
    """
    if len(shapes) == 0:
        raise Error("An extrusion needs at least one shape")
    var parts = List[BufferGeometry]()
    for shape in shapes:  # pragma: no branch
        parts.append(
            extrude(
                shape,
                depth,
                steps,
                curve_segments,
                bevel_enabled,
                bevel_thickness,
                bevel_size,
                bevel_offset,
                bevel_segments,
                uv_generator,
            )
        )
    return _joined(parts)
