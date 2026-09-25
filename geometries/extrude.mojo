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

## The order three.js builds it in

`ExtrudeGeometry.addShape` turns the outline clockwise when it runs the
other way, and only then turns every clockwise hole around. An outline
drawn clockwise keeps its holes as they were drawn. It then merges each
point that sits on the one before it, the closing point included, which
takes the *first* point of the list out rather than the last. The
vertices of a layer are the outline's points and then each hole's. This
builds them the same way, so an extrusion here is three.js's, vertex for
vertex.

## Moving a contour out

A bevel moves every point along three.js's `getBevelVec`: to the left
of its two edges, by one unit of each. That is the miter while it is no
longer than the square root of two, and the miter shrunk to that length
past it, which rounds a sharp corner off rather than drawing it out to a
spike. A point whose two edges are in a line moves square to them, or
back along them when they fold straight back. The arithmetic is three.js's
own, in doubles.

The caps are cut by earcut. Without a bevel it cuts the contours as they
are. With one, it cuts them moved out by `bevel_offset`, the layer three.js
cuts, which can take another diagonal than the contours themselves.

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
from geometries.earcut import triangulate_shape
from geometries.shape import Contours, extract_points, is_clockwise
from math.curve3 import Curve3, CurvePath3, FrenetFrames
from math.path import Shape
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
from units.si import Length, METER

# three.js's `UVGenerator.generateTopUV`: the texture coordinates of a cap
# triangle, from the vertices written so far, three floats each, and the
# indices of its three vertices among them.
comptime TopUV = def(List[Float64], Int, Int, Int) thin -> List[Vector2]
# three.js's `generateSideWallUV`: those of a wall quad's four corners.
comptime SideWallUV = def(List[Float64], Int, Int, Int, Int) thin -> List[
    Vector2
]


def world_top_uv(
    vertices: List[Float64], a: Int, b: Int, c: Int
) -> List[Vector2]:
    """Return a cap triangle's texture coordinates, three.js's
    `WorldUVGenerator.generateTopUV`: each vertex's x and y.

    Args:
        vertices: The vertices written so far, three numbers each, in
            doubles as three.js's `verticesArray` holds them.
        a: The first vertex's index among them.
        b: The second's.
        c: The third's.

    Returns:
        The three coordinates, in the vertices' order.
    """
    return [
        Vector2(Float32(vertices[a * 3]), Float32(vertices[a * 3 + 1])),
        Vector2(Float32(vertices[b * 3]), Float32(vertices[b * 3 + 1])),
        Vector2(Float32(vertices[c * 3]), Float32(vertices[c * 3 + 1])),
    ]


def world_side_wall_uv(
    vertices: List[Float64], a: Int, b: Int, c: Int, d: Int
) -> List[Vector2]:
    """Return a wall quad's texture coordinates, three.js's
    `WorldUVGenerator.generateSideWallUV`: x, or y where the quad's first
    edge covers more of y, and one minus z.

    Args:
        vertices: The vertices written so far, three numbers each, in
            doubles. A wall at a right angle to the diagonal is a tie that
            the doubles decide, as three.js's do.
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
            Vector2(
                Float32(vertices[corner * 3 + lane]),
                Float32(1 - vertices[corner * 3 + 2]),
            )
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


comptime _Offset = SIMD[DType.float64, 2]
"""How far and which way a bevel moves one point, per unit of bevel."""


# JavaScript's `Number.EPSILON`.
comptime _EPSILON = Float64(2.220446049250313e-16)


def _js_sign(value: Float64) -> Int:
    """Return JavaScript's `Math.sign`, with zero for zero."""
    if value > 0:
        return 1
    if value < 0:
        return -1
    return 0


def bevel_vector(point: Vector2, before: Vector2, after: Vector2) -> _Offset:
    """Return the way a bevel moves `point`, three.js's `getBevelVec`.

    Args:
        point: The point, in meters.
        before: The point before it in its contour.
        after: The point after it.

    Returns:
        The move for one unit of bevel, in doubles: the corner of the two
        edges moved one unit to their left, shrunk to a length of the
        square root of two when it is longer.
    """
    var x = Float64(point.x)
    var y = Float64(point.y)
    var bx = Float64(before.x)
    var by = Float64(before.y)
    var ax = Float64(after.x)
    var ay = Float64(after.y)
    var prev_x = x - bx
    var prev_y = y - by
    var next_x = ax - x
    var next_y = ay - y
    var prev_lensq = prev_x * prev_x + prev_y * prev_y
    var collinear = prev_x * next_y - prev_y * next_x
    var trans_x: Float64
    var trans_y: Float64
    var shrink_by: Float64
    if abs(collinear) > _EPSILON:
        var prev_len = sqrt(prev_lensq)
        var next_len = sqrt(next_x * next_x + next_y * next_y)
        var prev_shift_x = bx - prev_y / prev_len
        var prev_shift_y = by + prev_x / prev_len
        var next_shift_x = ax - next_y / next_len
        var next_shift_y = ay + next_x / next_len
        var sf = (
            (next_shift_x - prev_shift_x) * next_y
            - (next_shift_y - prev_shift_y) * next_x
        ) / (prev_x * next_y - prev_y * next_x)
        trans_x = prev_shift_x + prev_x * sf - x
        trans_y = prev_shift_y + prev_y * sf - y
        var trans_lensq = trans_x * trans_x + trans_y * trans_y
        if trans_lensq <= 2:
            return _Offset(trans_x, trans_y)
        shrink_by = sqrt(trans_lensq / 2)
    else:
        # The edges are in a line: running on, or folding straight back.
        var same: Bool
        if prev_x > _EPSILON:
            same = next_x > _EPSILON
        elif prev_x < -_EPSILON:
            same = next_x < -_EPSILON
        else:
            same = _js_sign(prev_y) == _js_sign(next_y)
        if same:
            trans_x = -prev_y
            trans_y = prev_x
            shrink_by = sqrt(prev_lensq)
        else:
            trans_x = prev_x
            trans_y = prev_y
            shrink_by = sqrt(prev_lensq / 2)
    return _Offset(trans_x / shrink_by, trans_y / shrink_by)


def _bevel_vectors(cut: Contours) -> List[_Offset]:
    """Return `bevel_vector` of every point, contour by contour, three.js's
    `verticesMovements`."""
    var out = List[_Offset]()
    for contour in range(cut.contour_count()):  # pragma: no branch
        var start = cut.starts[contour]
        var count = cut.counts[contour]
        for i in range(count):  # pragma: no branch
            out.append(
                bevel_vector(
                    cut.points[start + i],
                    cut.points[start + (i + count - 1) % count],
                    cut.points[start + (i + 1) % count],
                )
            )
    return out^


def merge_overlapping_points(mut points: List[Vector2]):
    """Drop every point that sits on the one before it, three.js's
    `mergeOverlappingPoints`.

    The last point is compared with the first too, so a closing point
    takes the first point out of the list.

    Args:
        points: A contour's points, changed in place.
    """
    var threshold_sq = Float64(1e-10) * Float64(1e-10)
    var before = points[0]
    var i = 1
    while i <= len(points):
        var at = i % len(points)
        var here = points[at]
        var dx = Float64(here.x) - Float64(before.x)
        var dy = Float64(here.y) - Float64(before.y)
        var scale = max(
            max(abs(Float64(here.x)), abs(Float64(here.y))),
            max(abs(Float64(before.x)), abs(Float64(before.y))),
        )
        if dx * dx + dy * dy <= threshold_sq * scale * scale:
            _ = points.pop(at)
            continue
        before = here
        i += 1


def _extrusion_contours(shape: Shape, curve_segments: Int) raises -> Contours:
    """Return `shape`'s points as three.js's `ExtrudeGeometry.addShape`
    orders them, cut by earcut as they are.

    Raises:
        Error: If the shape is refused; see
            `geometries.shape.extract_points`.
    """
    var sampled = extract_points(shape, curve_segments)
    var outline = sampled.outline.copy()
    var holes = sampled.holes.copy()
    if not is_clockwise(outline):
        outline.reverse()
        for at in range(len(holes)):
            if is_clockwise(holes[at]):
                holes[at].reverse()
    merge_overlapping_points(outline)
    for at in range(len(holes)):
        merge_overlapping_points(holes[at])
    return Contours(outline^, holes^)


def _layers(
    depth: Length,
    steps: Int,
    bevel_enabled: Bool,
    bevel_thickness: Length,
    bevel_size: Length,
    bevel_offset: Length,
    bevel_segments: Int,
    mut heights: List[Float64],
    mut insets: List[Float64],
):
    """Fill `heights` and `insets` with one entry per layer, back to front.

    A bevel's layers come first and last, each one further past the end
    face and less far out from the outline, by the cosine and the sine of
    how far around a quarter turn it is. The layers between are the
    extrusion itself, all the full distance out.
    """
    var thickness = Float64(bevel_thickness.value)
    var size = Float64(bevel_size.value)
    var offset = Float64(bevel_offset.value)
    var deep = Float64(depth.value)
    var full = Float64(0)
    if bevel_enabled:
        full = size + offset
        for band in range(bevel_segments):  # pragma: no branch
            var part = Float64(band) / Float64(bevel_segments) * pi / 2
            heights.append(-(thickness * cos(part)))
            insets.append(size * sin(part) + offset)
    heights.append(0)
    insets.append(full)
    for step in range(1, steps + 1):  # pragma: no branch
        heights.append(deep / Float64(steps) * Float64(step))
        insets.append(full)
    if bevel_enabled:
        for band in range(bevel_segments - 1, -1, -1):  # pragma: no branch
            var part = Float64(band) / Float64(bevel_segments) * pi / 2
            heights.append(deep + thickness * cos(part))
            insets.append(size * sin(part) + offset)


def _place(
    cut: Contours,
    moves: List[_Offset],
    heights: List[Float64],
    insets: List[Float64],
) -> List[Float64]:
    """Return every layer's vertices, three numbers each, layer by layer.

    These are the positions the faces are copied from. They are not the
    geometry: a face takes its own copy, because the walls do not share a
    texture coordinate with the ends or with one another.
    """
    var out = List[Float64]()
    for layer in range(len(heights)):  # pragma: no branch
        for index in range(len(cut.points)):  # pragma: no branch
            # three.js's `scalePt2`, in doubles.
            ref point = cut.points[index]
            out.append(Float64(point.x) + moves[index][0] * insets[layer])
            out.append(Float64(point.y) + moves[index][1] * insets[layer])
            out.append(heights[layer])
    return out^


def _copy_vertex(placed: List[Float64], vertex: Int, mut data: List[Float64]):
    """Append one placed vertex to `data`, three.js's `addVertex`."""
    data.append(placed[vertex * 3])
    data.append(placed[vertex * 3 + 1])
    data.append(placed[vertex * 3 + 2])


def _faces(
    cut: Contours,
    placed: List[Float64],
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
    var data = List[Float64]()
    var uvs = List[Float32]()

    # The two ends, three.js's `buildLidFaces`: every back triangle, then
    # every front one. The back faces away from the front, so its
    # triangles are wound the other way round.
    for triangle in range(cut.triangle_count()):  # pragma: no branch
        for corner in range(2, -1, -1):  # pragma: no branch
            _copy_vertex(placed, cut.index[triangle * 3 + corner], data)
        _cap_uvs(uv_generator, data, uvs)
    for triangle in range(cut.triangle_count()):  # pragma: no branch
        for corner in range(3):  # pragma: no branch
            _copy_vertex(placed, top + cut.index[triangle * 3 + corner], data)
        _cap_uvs(uv_generator, data, uvs)

    var lids = len(data) // 3

    # The walls, three.js's `sidewalls`: one quad per edge per layer, two
    # triangles each, each contour walked from its last point back.
    for contour in range(cut.contour_count()):  # pragma: no branch
        var start = cut.starts[contour]
        var count = cut.counts[contour]
        for edge in range(count - 1, -1, -1):  # pragma: no branch
            var here = start + edge
            var next = start + (edge + count - 1) % count
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
                    _copy_vertex(placed, corners[corner], data)
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
    # Rounded once, as three.js's `Float32BufferAttribute` rounds them.
    var positions = List[Float32](capacity=len(data))
    for value in data:  # pragma: no branch
        positions.append(Float32(value))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
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
    var placed = List[Float64]()
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
            placed.append(Float64(moved.x))
            placed.append(Float64(moved.y))
            placed.append(Float64(moved.z))
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
            `geometries.shape.extract_points`), or if the curve has no frame
            at one of the steps (see `Curve3.frenet_frames`).
    """
    _check_sweep(steps)
    var cut = _extrusion_contours(shape, curve_segments)
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
    var cut = _extrusion_contours(shape, curve_segments)
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
    uv_generator: UVGenerator, data: List[Float64], mut uvs: List[Float32]
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
            be filled in; see `geometries.shape.extract_points`.
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
    var cut = _extrusion_contours(shape, curve_segments)
    # Without a bevel every layer sits on the outline itself, so nothing
    # moves, whatever way three.js works out to move it.
    var moves = List[_Offset]()
    if bevel_enabled:
        moves = _bevel_vectors(cut)
        # three.js cuts the contours moved out by the offset alone, its
        # first bevel layer's `bs`.
        var offset = Float64(bevel_offset.value)
        var contour = List[Float64]()
        var holes = List[List[Float64]]()
        for at in range(cut.contour_count()):  # pragma: no branch
            var flat = List[Float64]()
            for i in range(cut.counts[at]):  # pragma: no branch
                var index = cut.starts[at] + i
                flat.append(
                    Float64(cut.points[index].x) + moves[index][0] * offset
                )
                flat.append(
                    Float64(cut.points[index].y) + moves[index][1] * offset
                )
            if at == 0:
                contour = flat^
            else:
                holes.append(flat^)
        cut.index = triangulate_shape(contour, holes)
    else:
        for _ in range(len(cut.points)):  # pragma: no branch
            moves.append(_Offset(0, 0))

    var heights = List[Float64]()
    var insets = List[Float64]()
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
    var placed = _place(cut, moves, heights, insets)
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
