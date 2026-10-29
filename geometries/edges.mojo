# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A surface read as lines, from three.js `src/geometries/EdgesGeometry.js`
and `src/geometries/WireframeGeometry.js`.

Both take a geometry of triangles and give back a geometry of points, two
per segment, for a `Line` in `SEGMENTS` mode to draw. See `objects.line`.

`wireframe_geometry` keeps every edge. It shows how a surface is built.

`edges_geometry` keeps only the edges that show a shape: an edge where the
two faces meeting at it turn by at least a threshold angle, and an edge
with one face and no neighbor at all. A cube keeps its twelve edges and
loses the diagonal across each face.

It is a crease and boundary finder, not a silhouette finder. It is given
no camera, and its answer does not move when one does. What it keeps of a
sphere depends on how finely the sphere is divided and on the threshold:
a sphere of twenty-four segments turns fifteen degrees a facet, so the
default one-degree threshold keeps most of its edges rather than none.

## Positions, not indices

Two triangles that meet along an edge often hold two copies of each of its
two points, because a corner carries a normal and a texture coordinate as
well as a position and the two faces disagree about those. Pairing by
vertex index would then find no shared edge anywhere. So both builders
find an edge by the positions of its ends, as three.js does.

`wireframe_geometry` compares the positions exactly, as three.js's
`isUniqueEdge` compares the numbers it prints. Zero and minus zero are one
number, and so is every NaN. An indexed geometry with groups is read group
by group, as three.js reads it. A triangle in no group gives no edge. A
triangle with two corners at one place keeps its edge of no length, once.

`edges_geometry` rounds each coordinate first, as three.js does: the key
is `Math.round` of the coordinate times ten thousand. Two points nearer
than a ten-thousandth can still round apart, in three.js and here. A
triangle with two corners on one key has no area, and it is skipped.

An edge pairs only with the same edge run the other way. So two faces
that run an edge the same way do not pair. The first face keeps the edge,
and it is drawn as an edge with one face. A pair is drawn when its second
face is met, in that face's direction. The edges with one face come last,
in the order they were first met. The order is three.js's, so segment `s`
of the result is segment `s` of three.js's.

## Buckets, not a search

`triangle_edges` looks an edge up in a bucket chosen from its two vertex
indices. `welded_points` looks a point up in a bucket chosen from its
rounded position. Both then scan a few entries rather than the whole list.
Scanning the whole list is the obvious way to write this, and it is
quadratic: a sphere of a thousand points and three thousand edges does
millions of comparisons and takes visible time in the instrumented build.

`welded_points` welds by a distance, `WELD`, and not by a key. Neither
builder uses it.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules. A face normal of
`edges_geometry` is three.js's, in `Float64`. No product of `Float32`
coordinates overflows or underflows there.
"""

from core.ordinal import require_non_negative

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from math.norm import rounded_dot3, rounded_product
from math.utils import js_round
from math.vector3 import Vector3
from std.collections import Dict, Set
from std.math import cos, floor, isnan, sqrt
from std.memory import bitcast
from units.si import Angle, DEGREE

# How near two points must be to count as one point. A tenth of a
# millimeter, in meters: finer than any surface this draws and coarser
# than the rounding a transform leaves behind.
comptime WELD = Float32(1e-4)
# The angle three.js defaults `thresholdAngle` to. An edge whose two faces
# turn by less than this is not an edge of the shape, only of the mesh.
comptime DEFAULT_THRESHOLD = Angle(1.0, DEGREE)
# How far a cosine may fall short of the threshold's and still count as
# reaching it. The rule is inclusive -- an edge turning *at* the threshold
# is kept -- and without this it is not, because neither side of the
# comparison is exact. An `Angle` holds radians as a Float32, so an
# authored ninety degrees is 1.5707964 and its cosine is -4.37e-8 rather
# than zero, while two perpendicular faces give a dot product of exactly
# zero. A cube asked for its right angles lost all twelve of them. A
# millionth is several times both errors and is far below any angle an
# image can show: it is the tolerance `renderers.renderer.CULL_SLACK` and
# `geometries.shape.NOISE` are, for the same reason.
comptime ANGLE_SLACK = Float32(1e-6)
# What `edges_geometry` scales a coordinate by before it rounds it: three.js's
# `Math.pow( 10, precisionPoints )`, four decimal places.
comptime EDGE_PRECISION = Float64(1e4)

comptime _Vector = SIMD[DType.float64, 4]


def _hashed(value: Int, buckets: Int) -> Int:
    """Return which bucket a key belongs in.

    Mojo takes a remainder the way Python does, so a negative key gives a
    remainder that is not negative and there is nothing to fold back. A
    key here is negative often: a point at a negative coordinate lands in
    a cell at a negative number, and the cell is multiplied by a prime.

    Args:
        value: The key, which can be negative.
        buckets: How many buckets there are; at least one.

    Returns:
        A bucket index, from zero.
    """
    return value % buckets


def welded_points(geometry: BufferGeometry) raises -> List[Int]:
    """Return which welded point each vertex of a geometry stands on.

    Two vertices within `WELD` of each other on every axis are one point.
    That is what lets two faces be seen to share an edge when they hold
    their own copies of its ends; see the module docstring.

    Args:
        geometry: The surface, which must carry positions.

    Returns:
        One welded point number per vertex, counting from zero in the
        order the vertices are met.

    Raises:
        Error: If the geometry has no `position` attribute.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    var count = positions.count()
    var buckets = max(1, count)
    # One list of welded point numbers per bucket, and the position of
    # each welded point, so a candidate is compared against a few rather
    # than against all of them.
    var bucketed = List[List[Int]](length=buckets, fill=List[Int]())
    var places = List[Vector3]()
    var welded = List[Int]()
    for vertex in range(count):
        var point = Vector3(
            positions.component(vertex, 0),
            positions.component(vertex, 1),
            positions.component(vertex, 2),
        )
        # Rounded to the weld, so two points near enough to be one land in
        # one bucket -- unless they straddle a boundary, which is why the
        # neighboring cells are looked in as well.
        var cell_x = Int(floor(point.x / WELD))
        var cell_y = Int(floor(point.y / WELD))
        var cell_z = Int(floor(point.z / WELD))
        var found = -1
        for dx in range(-1, 2):  # pragma: no branch
            for dy in range(-1, 2):  # pragma: no branch
                for dz in range(-1, 2):  # pragma: no branch
                    if found >= 0:
                        continue
                    var slot = _hashed(
                        (cell_x + dx) * 73856093
                        + (cell_y + dy) * 19349663
                        + (cell_z + dz) * 83492791,
                        buckets,
                    )
                    ref nearby = bucketed[slot]
                    for index in range(len(nearby)):
                        var other = places[nearby[index]]
                        if (
                            abs(other.x - point.x) <= WELD
                            and abs(other.y - point.y) <= WELD
                            and abs(other.z - point.z) <= WELD
                        ):
                            found = nearby[index]
                            break
        if found < 0:
            found = len(places)
            places.append(point)
            bucketed[
                _hashed(
                    cell_x * 73856093 + cell_y * 19349663 + cell_z * 83492791,
                    buckets,
                )
            ].append(found)
        welded.append(found)
    return welded^


def _canonical(value: Float64) -> UInt64:
    """Return the bits that stand for a number in a key.

    three.js's keys are the numbers as JavaScript prints them. Zero and
    minus zero print the same, and so does every NaN.

    Args:
        value: The number.

    Returns:
        Its bits, with one zero and one NaN.
    """
    if value == 0:
        return 0
    if isnan(value):
        return 0x7FF8000000000000
    return bitcast[DType.uint64](value)


def _point_keys(positions: BufferAttribute, rounded: Bool) raises -> List[Int]:
    """Return a point number for each vertex, one number per key.

    Args:
        positions: The positions.
        rounded: True for the key `edges_geometry` makes, each coordinate
            times `EDGE_PRECISION` and rounded as `Math.round` rounds.
            False for the exact coordinates `wireframe_geometry` compares.

    Returns:
        One number per vertex, from zero, in the order the keys are met.

    Raises:
        Error: If a position cannot be read.
    """
    var numbers = Dict[String, Int]()
    var points = List[Int]()
    for vertex in range(positions.count()):
        var key = String()
        for axis in range(3):  # pragma: no branch
            var value = Float64(positions.component(vertex, axis))
            if rounded:
                value = js_round(value * EDGE_PRECISION)
            key += String(_canonical(value)) + ","
        if key not in numbers:
            numbers[key] = len(numbers)
        points.append(numbers[key])
    return points^


def _face_normal(a: Vector3, b: Vector3, c: Vector3) -> _Vector:
    """Return three.js's `Triangle.getNormal`, in `Float64`.

    The cross product of `c - b` and `a - b`, each product rounded, times
    one over its length. A face with no area has a zero normal.

    Args:
        a: The first corner.
        b: The second corner.
        c: The third corner.

    Returns:
        The unit normal, or zero.
    """
    var cb = _Vector(
        Float64(c.x) - Float64(b.x),
        Float64(c.y) - Float64(b.y),
        Float64(c.z) - Float64(b.z),
        0,
    )
    var ab = _Vector(
        Float64(a.x) - Float64(b.x),
        Float64(a.y) - Float64(b.y),
        Float64(a.z) - Float64(b.z),
        0,
    )
    var normal = _Vector(
        rounded_product(cb[1], ab[2]) - rounded_product(cb[2], ab[1]),
        rounded_product(cb[2], ab[0]) - rounded_product(cb[0], ab[2]),
        rounded_product(cb[0], ab[1]) - rounded_product(cb[1], ab[0]),
        0,
    )
    var squared = rounded_dot3(
        normal[0], normal[1], normal[2], normal[0], normal[1], normal[2]
    )
    if squared > 0:
        return normal * (1 / sqrt(squared))
    return _Vector(0)


def _as_segments(
    geometry: BufferGeometry, first: List[Int], second: List[Int]
) raises -> BufferGeometry:
    """Return a geometry of point pairs, two per named edge.

    Args:
        geometry: Where the positions come from.
        first: The vertex index of one end of each edge.
        second: The vertex index of the other end.

    Returns:
        A geometry carrying positions only, for a `SEGMENTS` line.

    Raises:
        Error: If the geometry has no positions.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    var numbers = List[Float32]()
    for edge in range(len(first)):
        for end in [first[edge], second[edge]]:  # pragma: no branch
            numbers.append(positions.component(end, 0))
            numbers.append(positions.component(end, 1))
            numbers.append(positions.component(end, 2))
    var drawn = BufferGeometry()
    drawn.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return drawn^


def triangle_edges(
    geometry: BufferGeometry, start: Int = 0, count: Int = -1
) raises -> Tuple[List[Int], List[Int]]:
    """Return each edge of a geometry's triangles once, by vertex index.

    What `material.wireframe` draws, and what three.js's
    `getWireframeAttribute` builds: the edges of the triangles as they are
    indexed, with an edge shared by two triangles kept once.

    Paired by vertex index and not by position, which is the one
    way it differs from `wireframe_geometry`. three.js draws the same
    distinction, and it is the right one here: a wireframe is drawn from
    the mesh's own vertices, already morphed, skinned and carried into
    view, and two indices that happen to stand at one place are still two
    vertices with their own colors. Welding them would be a second
    opinion about what the mesh is.

    A group of a mesh that wears a material list is drawn in its own
    material, so its wireframe is the edges of its own triangles: `start`
    and `count` name the run, read as `BufferGeometry.triangle_run` reads
    it. three.js draws the same run of its wireframe index.

    Args:
        geometry: The surface, which must carry positions.
        start: The first slot of the run of the triangle stream.
        count: How many slots it holds, or minus one for all of them.

    Returns:
        The vertex index of each end of each unique edge.

    Raises:
        Error: If the geometry has no positions, an index entry points
            past the last vertex, or `start` is negative.
    """
    var run = geometry.triangle_run(start, count)
    var triangles = run[1]
    var buckets = max(1, triangles * 3)
    var bucketed = List[List[Int]](length=buckets, fill=List[Int]())
    var keys = List[Int]()
    var first = List[Int]()
    var second = List[Int]()
    ref positions = geometry.attribute_view(String(POSITION))
    var spread = positions.count() + 1
    for triangle in range(triangles):
        var corners = List[Int]()
        for corner in range(3):  # pragma: no branch
            corners.append(geometry.vertex_at(run[0] + triangle * 3 + corner))
        for corner in range(3):  # pragma: no branch
            var start = corners[corner]
            var finish = corners[(corner + 1) % 3]
            var low = start
            var high = finish
            if low > high:
                low, high = high, low
            var key = low * spread + high
            var slot = _hashed(low * 73856093 + high * 19349663, buckets)
            var found = False
            ref nearby = bucketed[slot]
            for index in range(len(nearby)):
                if keys[nearby[index]] == key:
                    found = True
                    break
            if not found:
                bucketed[slot].append(len(keys))
                keys.append(key)
                first.append(start)
                second.append(finish)
    return (first^, second^)


def wireframe_geometry(geometry: BufferGeometry) raises -> BufferGeometry:
    """Return every edge of a surface, once each, as segments.

    three.js's `WireframeGeometry`. It shows how a surface is built, which
    is what a modeler and a bug hunt both want to see. Every edge is kept,
    including the diagonal that splits a quad into two triangles. Two edges
    whose ends are at the same two places are one edge. An indexed geometry
    with groups gives the edges of its groups. The groups are read as the
    renderer reads them, clamped to whole triangles in the stream.

    Args:
        geometry: The surface, which must carry positions.

    Returns:
        A geometry carrying positions only, two points per edge, in the
        order three.js gives them. Draw it with a `Line` in `SEGMENTS`
        mode.

    Raises:
        Error: If the geometry has no positions, or an index entry points
            past the last vertex.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    var points = _point_keys(positions, False)
    var spread = len(points) + 1
    var runs = List[Tuple[Int, Int]]()
    if geometry.is_indexed() and len(geometry.groups) > 0:
        for group in geometry.groups:  # pragma: no branch
            runs.append(geometry.triangle_run(group.start, group.count))
    else:
        runs.append(geometry.triangle_run(0, -1))
    var seen = Set[Int]()
    var first = List[Int]()
    var second = List[Int]()
    for run in runs:  # pragma: no branch
        for triangle in range(run[1]):
            var slot = run[0] + triangle * 3
            for corner in range(3):  # pragma: no branch
                var start = geometry.vertex_at(slot + corner)
                var finish = geometry.vertex_at(slot + (corner + 1) % 3)
                var low = min(points[start], points[finish])
                var high = max(points[start], points[finish])
                var key = low * spread + high
                if key not in seen:
                    seen.add(key)
                    first.append(start)
                    second.append(finish)
    return _as_segments(geometry, first, second)


def edges_geometry(
    geometry: BufferGeometry, threshold: Angle = DEFAULT_THRESHOLD
) raises -> BufferGeometry:
    """Return the edges that show a surface's shape, as segments.

    three.js's `EdgesGeometry`. An edge is kept when the two faces meeting
    at it turn by at least `threshold`, and when it has one face and no
    neighbor. A cube keeps its twelve edges and loses the diagonal across
    each face. A smooth sphere keeps nothing but its open ends. An edge
    pairs with the same edge run the other way; see the module docstring.

    Args:
        geometry: The surface, which must carry positions.
        threshold: How far two faces must turn for their shared edge to be
            drawn. One degree unless said otherwise, as three.js defaults
            `thresholdAngle`.

    Returns:
        A geometry carrying positions only, two points per edge, in the
        order three.js gives them. Draw it with a `Line` in `SEGMENTS`
        mode.

    Raises:
        Error: If the geometry has no positions, if an index entry points
            past the last vertex, or if the threshold is negative.
    """
    require_non_negative(
        threshold.value, "An edge threshold cannot be a negative angle"
    )
    # Widened by the slack, so an edge turning exactly as far as the
    # threshold is kept rather than lost to the rounding of a float32
    # angle. See `ANGLE_SLACK`.
    var limit = cos(Float64(threshold.value)) + Float64(ANGLE_SLACK)
    ref positions = geometry.attribute_view(String(POSITION))
    var points = _point_keys(positions, True)
    var spread = len(points) + 1
    # three.js's `edgeData`: each edge run one way, by the key of its two
    # points in order. A pair closes the entry, and its key stays taken.
    var entries = Dict[Int, Int]()
    var starts = List[Int]()
    var ends = List[Int]()
    var normals = List[_Vector]()
    var open = List[Bool]()
    var first = List[Int]()
    var second = List[Int]()
    for triangle in range(geometry.triangle_count()):
        var corners = List[Int]()
        var keys = List[Int]()
        for corner in range(3):  # pragma: no branch
            corners.append(geometry.corner_index(triangle, corner))
            keys.append(points[corners[corner]])
        # A face with two corners on one key has no area and no normal,
        # and three.js skips it.
        if keys[0] == keys[1] or keys[1] == keys[2] or keys[2] == keys[0]:
            continue
        var normal = _face_normal(
            positions.vector3(corners[0]),
            positions.vector3(corners[1]),
            positions.vector3(corners[2]),
        )
        for corner in range(3):  # pragma: no branch
            var after = (corner + 1) % 3
            var forward = keys[corner] * spread + keys[after]
            var backward = keys[after] * spread + keys[corner]
            if backward in entries and open[entries[backward]]:
                var sibling = entries[backward]
                var turn = rounded_dot3(
                    normal[0],
                    normal[1],
                    normal[2],
                    normals[sibling][0],
                    normals[sibling][1],
                    normals[sibling][2],
                )
                # A cosine at or below the threshold's is an angle at or
                # above it.
                if turn <= limit:
                    first.append(corners[corner])
                    second.append(corners[after])
                open[sibling] = False
            elif forward not in entries:
                entries[forward] = len(starts)
                starts.append(corners[corner])
                ends.append(corners[after])
                normals.append(normal)
                open.append(True)
    # The edges no second face paired with, in the order they were met.
    for entry in range(len(starts)):
        if open[entry]:
            first.append(starts[entry])
            second.append(ends[entry])
    return _as_segments(geometry, first, second)
