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

## Welding first

Both weld before they pair. Two triangles that meet along an edge often
hold two copies of each of its two points, because a corner carries a
normal and a texture coordinate as well as a position and the two faces
disagree about those. Pairing by vertex index would then find no shared
edge anywhere, and `edges_geometry` would keep every edge of everything.

So the points are welded by position first, to a tolerance, and the edges
are paired by welded point. `WELD` is that tolerance. It is a distance and
not a fraction, which is the same bargain three.js makes with its
four-decimal position hash: a geometry built at a scale far from one meter
has to be welded at its own scale, and neither library does that for you.

## Buckets, not a search

An edge is looked up in a bucket chosen from its two welded points, and a
point in a bucket chosen from its rounded position. Both then scan a few
entries rather than the whole list. Scanning the whole list is the obvious
way to write this, and it is quadratic: a sphere of a thousand points and
three thousand edges does millions of comparisons and takes visible time
in the instrumented build.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from math.vector3 import Vector3
from std.math import cos, floor
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


def _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    """Return the unit normal of one triangle, or zero if it has no area.

    Its own rather than `renderers.renderer.face_normal`, because a
    geometry does not depend on a renderer.
    """
    var edge = b - a
    var other = c - a
    edge.cross(other)
    edge.normalize()
    return edge


def _degenerate(a: Int, b: Int, c: Int) -> Bool:
    """Return True if two of a face's three welded points are one point.

    Args:
        a: The first corner's welded point.
        b: The second's.
        c: The third's.

    Returns:
        True for a face with no area to have a normal.
    """
    if a == b:
        return True
    if b == c:
        return True
    return a == c


def _paired(
    geometry: BufferGeometry,
) raises -> Tuple[List[Int], List[Int], List[Float32]]:
    """Return every edge of a geometry once, with how its faces turn.

    Args:
        geometry: The surface, which must carry positions.

    Returns:
        Three lists of one entry per unique edge: the vertex index of each
        end, taken from the first face that used the edge, and the cosine
        of the angle between the two faces that meet at it. An edge with
        one face carries a cosine of minus two, which no angle gives and
        which every threshold therefore keeps.

    Raises:
        Error: If the geometry has no positions, or an index entry points
            past the last vertex.
    """
    var welded = welded_points(geometry)
    ref positions = geometry.attribute_view(String(POSITION))
    var spread = positions.count() + 1
    var triangles = geometry.triangle_count()
    var buckets = max(1, triangles * 3)
    var bucketed = List[List[Int]](length=buckets, fill=List[Int]())
    # Per unique edge: the one number its two welded points make, the two
    # vertices to draw it with, the first face's normal and how the second
    # face turns from it. One number and not two, because two numbers
    # compared one after the other is a pair of conditions where the edge
    # is one thing.
    var keys = List[Int]()
    var first_end = List[Int]()
    var second_end = List[Int]()
    var normals = List[Vector3]()
    var turns = List[Float32]()
    for triangle in range(triangles):
        var corners = List[Int]()
        for corner in range(3):  # pragma: no branch
            corners.append(geometry.corner_index(triangle, corner))
        # A face with two corners on one welded point has no area and no
        # normal, and three.js's `EdgesGeometry` skips it. Counted, it
        # lent the edges it shares a turn of ninety degrees -- a zero
        # normal dots to zero -- and drew a crease across a flat surface
        # wherever a generator left a degenerate pole fan.
        if _degenerate(
            welded[corners[0]], welded[corners[1]], welded[corners[2]]
        ):
            continue
        var normal = _face_normal(
            geometry.corner(triangle, 0),
            geometry.corner(triangle, 1),
            geometry.corner(triangle, 2),
        )
        for corner in range(3):  # pragma: no branch
            var start = corners[corner]
            var finish = corners[(corner + 1) % 3]
            # `corner_index` has already refused an entry past the last
            # vertex, so a welded point is there to be read.
            var one = welded[start]
            var two = welded[finish]
            if one > two:
                one, two = two, one
            # The lower point times one more than the point count, plus the
            # higher: one number that no other pair of points makes.
            var key = one * spread + two
            var slot = _hashed(one * 73856093 + two * 19349663, buckets)
            var found = -1
            ref nearby = bucketed[slot]
            for index in range(len(nearby)):
                var edge = nearby[index]
                if keys[edge] == key:
                    found = edge
                    break
            if found < 0:
                bucketed[slot].append(len(keys))
                keys.append(key)
                first_end.append(start)
                second_end.append(finish)
                normals.append(normal)
                # Minus two until a second face is met: no angle gives it,
                # so a boundary edge survives every threshold.
                turns.append(-2)
            elif turns[found] == -2:
                turns[found] = normals[found].dot(normal)
    return (first_end^, second_end^, turns^)


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
    geometry: BufferGeometry,
) raises -> Tuple[List[Int], List[Int]]:
    """Return each edge of a geometry's triangles once, by vertex index.

    What `material.wireframe` draws, and what three.js's
    `getWireframeAttribute` builds: the edges of the triangles as they are
    indexed, with an edge shared by two triangles kept once.

    Paired by vertex index and not by welded position, which is the one
    way it differs from `wireframe_geometry`. three.js draws the same
    distinction, and it is the right one here: a wireframe is drawn from
    the mesh's own vertices, already morphed, skinned and carried into
    view, and two indices that happen to stand at one place are still two
    vertices with their own colors. Welding them would be a second
    opinion about what the mesh is.

    Args:
        geometry: The surface, which must carry positions.

    Returns:
        The vertex index of each end of each unique edge.

    Raises:
        Error: If the geometry has no positions, or an index entry points
            past the last vertex.
    """
    var triangles = geometry.triangle_count()
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
            corners.append(geometry.corner_index(triangle, corner))
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
    including the diagonal that splits a quad into two triangles.

    Args:
        geometry: The surface, which must carry positions.

    Returns:
        A geometry carrying positions only, two points per edge. Draw it
        with a `Line` in `SEGMENTS` mode.

    Raises:
        Error: If the geometry has no positions, or an index entry points
            past the last vertex.
    """
    var paired = _paired(geometry)
    return _as_segments(geometry, paired[0], paired[1])


def edges_geometry(
    geometry: BufferGeometry, threshold: Angle = DEFAULT_THRESHOLD
) raises -> BufferGeometry:
    """Return the edges that show a surface's shape, as segments.

    three.js's `EdgesGeometry`. An edge is kept when the two faces meeting
    at it turn by more than `threshold`, and when it has one face and no
    neighbor. A cube keeps its twelve edges and loses the diagonal across
    each face. A smooth sphere keeps nothing but its open ends.

    Args:
        geometry: The surface, which must carry positions.
        threshold: How far two faces must turn for their shared edge to be
            drawn. One degree unless said otherwise, as three.js defaults
            `thresholdAngle`.

    Returns:
        A geometry carrying positions only, two points per edge. Draw it
        with a `Line` in `SEGMENTS` mode.

    Raises:
        Error: If the geometry has no positions, if an index entry points
            past the last vertex, or if the threshold is negative.
    """
    if threshold.value < 0:
        raise Error("An edge threshold cannot be a negative angle")
    var paired = _paired(geometry)
    # Widened by the slack, so an edge turning exactly as far as the
    # threshold is kept rather than lost to the rounding of a float32
    # cosine. See `ANGLE_SLACK`.
    var limit = cos(threshold.value) + ANGLE_SLACK
    var first = List[Int]()
    var second = List[Int]()
    for edge in range(len(paired[2])):
        # A cosine at or below the threshold's is an angle at or above it.
        # A boundary edge carries minus two and is always below.
        if paired[2][edge] <= limit:
            first.append(paired[0][edge])
            second.append(paired[1][edge])
    return _as_segments(geometry, first, second)
