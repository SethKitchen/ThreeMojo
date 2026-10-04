# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The arrangement of polygons in a plane: the faces their edges cut.

Each input polygon is a `Region` on a layer. The edges of every region are
split where they cross, where an end of one touches another, and where
two overlap. The split edges form a planar graph. Its faces are traced
with half-edges: at each vertex the outgoing half-edges are sorted by
angle, and the face to the left of a half-edge continues along the
outgoing half-edge just clockwise of its twin.

A bounded face winds counterclockwise. Each bounded face carries one
label per layer: the region of that layer that covers it, or `NO_REGION`.
Regions of one layer must not overlap. Two layers can overlap: the faces
of a two-layer arrangement are the overlay of a plan above on a plan
below.

A component of the graph can lie inside a face of another component, as
the plan of a smaller crown lies inside the shaft below it. The face
would then have a hole. A bridge edge joins the inner component's
leftmost vertex to the nearest vertex it can see, and the faces are
traced again. The face loop then runs along the bridge in both
directions, so every face is one loop. A bridge has the same face on both
sides.

See de Berg, Cheong, van Kreveld and Overmars, "Computational Geometry:
Algorithms and Applications" (3rd edition, 2008), chapter 2.
"""

from std.math import atan2, isfinite
from extensions.topology.ids import NO_REGION, RegionId
from extensions.topology.weld import Welder
from generators.utils import Vec3d
from units.si import Length64, METER


@fieldwise_init
struct Point2(ImplicitlyCopyable, Writable):
    """A point in the plan, in meters."""

    var x: Float64
    var y: Float64

    def __sub__(self, other: Self) -> Self:
        """Return the difference.

        Args:
            other: The point to take away.

        Returns:
            The vector from `other` to this point.
        """
        return Point2(self.x - other.x, self.y - other.y)

    def cross(self, other: Self) -> Float64:
        """Return the z component of the cross product.

        Args:
            other: The other vector.

        Returns:
            Positive when `other` turns counterclockwise from this vector.
        """
        return self.x * other.y - self.y * other.x

    def dot(self, other: Self) -> Float64:
        """Return the dot product.

        Args:
            other: The other vector.

        Returns:
            The dot product.
        """
        return self.x * other.x + self.y * other.y


struct Region(Copyable, Movable):
    """One input polygon: its layer, its caller-chosen id and its corners."""

    var layer: Int
    var id: RegionId
    var points: List[Point2]

    def __init__(out self, layer: Int, id: RegionId, var points: List[Point2]):
        """Create a region.

        Args:
            layer: The layer, from zero to the layer count less one.
            id: The caller's name for the region. Zero or more.
            points: The corners in order, either winding.
        """
        self.layer = layer
        self.id = id
        self.points = points^


@fieldwise_init
struct ArrangementEdge(ImplicitlyCopyable):
    """An edge of the arrangement and the faces on its two sides.

    `left` and `right` index `Arrangement.faces`, seen along the edge from
    vertex `a` to vertex `b`. -1 is the unbounded outside.
    """

    var a: Int
    var b: Int
    var left: Int
    var right: Int


struct ArrangementFace(Copyable, Movable):
    """A bounded face: its corners counterclockwise and its labels."""

    var loop: List[Int]
    var labels: List[RegionId]

    def __init__(out self, var loop: List[Int], var labels: List[RegionId]):
        """Create a face.

        Args:
            loop: The vertex indices, counterclockwise.
            labels: One region per layer, `NO_REGION` where none covers it.
        """
        self.loop = loop^
        self.labels = labels^


struct Arrangement(Movable):
    """The vertices, edges and bounded faces cut by a set of regions."""

    var points: List[Point2]
    var edges: List[ArrangementEdge]
    var faces: List[ArrangementFace]
    var layers: Int

    def __init__(
        out self,
        var points: List[Point2],
        var edges: List[ArrangementEdge],
        var faces: List[ArrangementFace],
        layers: Int,
    ):
        """Hold an arrangement. `arrange` makes these.

        Args:
            points: The vertices.
            edges: The edges, each with its two faces.
            faces: The bounded faces.
            layers: The number of layers.
        """
        self.points = points^
        self.edges = edges^
        self.faces = faces^
        self.layers = layers

    def face_area(self, face: Int) -> Float64:
        """Return the area of a bounded face. The index must be in range.

        Args:
            face: The face index.

        Returns:
            The area, in square meters.
        """
        return signed_area(self.points, self.faces[face].loop)


def signed_area(points: List[Point2], loop: List[Int]) -> Float64:
    """Return the signed area of a loop of points, by the shoelace formula.

    Args:
        points: The points.
        loop: The indices of the loop's corners in order.

    Returns:
        The area, positive for a counterclockwise loop.
    """
    var total = Float64(0)
    var n = len(loop)
    for i in range(n):  # pragma: no branch
        var p = points[loop[i]]
        var q = points[loop[(i + 1) % n]]
        total += p.x * q.y - q.x * p.y
    return total / 2


def polygon_area(points: List[Point2]) -> Float64:
    """Return the signed area of a polygon given by its corners.

    Args:
        points: The corners in order.

    Returns:
        The area, positive for a counterclockwise polygon.
    """
    var total = Float64(0)
    var n = len(points)
    for i in range(n):
        var p = points[i]
        var q = points[(i + 1) % n]
        total += p.x * q.y - q.x * p.y
    return total / 2


def contains(points: List[Point2], p: Point2) -> Bool:
    """Return True if a point is inside a polygon, by the crossing number.

    A point on the boundary can go either way.

    Args:
        points: The polygon's corners in order.
        p: The point.

    Returns:
        Whether a ray from the point crosses the boundary an odd number
        of times.
    """
    var inside = False
    var n = len(points)
    var j = n - 1
    for i in range(n):
        var a = points[i]
        var b = points[j]
        if (a.y > p.y) != (b.y > p.y):
            var x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
            if p.x < x:
                inside = not inside
        j = i
    return inside


def _on_segment(p: Point2, a: Point2, b: Point2, tolerance: Float64) -> Float64:
    """Return where a point lies on a segment, strictly inside, or -1.

    Returns the parameter from 0 at `a` to 1 at `b` when the point is
    within the tolerance of the segment and farther than the tolerance
    from both ends.
    """
    var d = b - a
    var length_squared = d.dot(d)
    var t = (p - a).dot(d) / length_squared
    var foot = Point2(a.x + t * d.x, a.y + t * d.y)
    var offset = p - foot
    if offset.dot(offset) > tolerance * tolerance:
        return -1
    var along = t * t * length_squared
    var beyond = (1 - t) * (1 - t) * length_squared
    var tol2 = tolerance * tolerance
    if t <= 0 or t >= 1 or along <= tol2 or beyond <= tol2:
        return -1
    return t


def _segments_cross(a: Point2, b: Point2, c: Point2, d: Point2) -> Bool:
    """Return True if two segments cross at a point inside both."""
    var r = b - a
    var s = d - c
    var denominator = r.cross(s)
    if denominator == 0:
        return False
    var t = (c - a).cross(s) / denominator
    var u = (c - a).cross(r) / denominator
    return t > 0 and t < 1 and u > 0 and u < 1


def _check_region(region: Region, layers: Int, tolerance: Float64) raises:
    """Refuse a region that is not a simple polygon on a known layer."""
    if region.layer < 0 or region.layer >= layers:
        raise Error("A region's layer must be from zero to the count less one")
    if not region.id.is_valid():
        raise Error("A region id must be zero or more")
    var n = len(region.points)
    if n < 3:
        raise Error("A region needs three corners or more")
    for i in range(n):  # pragma: no branch
        var p = region.points[i]
        if not (isfinite(p.x) and isfinite(p.y)):
            raise Error("A region corner must have finite coordinates")
    for i in range(n):  # pragma: no branch
        var a = region.points[i]
        var b = region.points[(i + 1) % n]
        var d = b - a
        if d.dot(d) <= tolerance * tolerance:
            raise Error("A region edge must be longer than the tolerance")
    if abs(polygon_area(region.points)) <= tolerance * tolerance:
        raise Error("A region must have an area")
    # Simple: no two edges that do not share a corner may cross or touch.
    for i in range(n):  # pragma: no branch
        var a = region.points[i]
        var b = region.points[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            var c = region.points[j]
            var d = region.points[(j + 1) % n]
            if _segments_cross(a, b, c, d):
                raise Error("A region must not cross itself")
            if (
                _on_segment(c, a, b, tolerance) >= 0
                or _on_segment(a, c, d, tolerance) >= 0
            ):
                raise Error("A region must not touch itself")


def _interior_point(points: List[Point2], loop: List[Int]) -> Point2:
    """Return a point strictly inside a counterclockwise loop.

    The lowest-leftmost corner v is convex. If no other corner lies inside
    the triangle of v and its two neighbors, the triangle's centroid is
    inside the loop. Otherwise the corner inside that triangle farthest
    from the neighbors' line is visible from v, and the midpoint of the two
    is inside. See O'Rourke, "Computational Geometry in C" (2nd edition,
    1998), section 1.6.
    """
    var n = len(loop)
    var m = 0
    for i in range(1, n):  # pragma: no branch
        var p = points[loop[i]]
        var q = points[loop[m]]
        if p.x < q.x or (p.x == q.x and p.y < q.y):
            m = i
    var a = points[loop[(m + n - 1) % n]]
    var v = points[loop[m]]
    var b = points[loop[(m + 1) % n]]
    var best = -1
    var best_distance = Float64(0)
    for k in range(n):  # pragma: no branch
        var p = points[loop[k]]
        var inside = (
            (v - a).cross(p - a) > 0
            and (b - v).cross(p - v) > 0
            and (a - b).cross(p - b) > 0
        )
        if inside:
            var distance = abs((b - a).cross(p - a))
            if best < 0 or distance > best_distance:
                best = k
                best_distance = distance
    if best < 0:
        return Point2((a.x + v.x + b.x) / 3, (a.y + v.y + b.y) / 3)
    var q = points[loop[best]]
    return Point2((v.x + q.x) / 2, (v.y + q.y) / 2)


def arrange(
    regions: List[Region], layers: Int, tolerance: Length64
) raises -> Arrangement:
    """Return the arrangement cut by a set of regions.

    Args:
        regions: The input polygons.
        layers: How many layers the regions use. One or more.
        tolerance: Points closer than this are one point. Positive.

    Returns:
        The vertices, edges and labeled bounded faces.

    Raises:
        Error: If the layer count is not positive, the tolerance is not
            positive and finite, a region is not a simple polygon, or two
            regions of one layer overlap.
    """
    if layers < 1:
        raise Error("An arrangement needs one layer or more")
    var tol = tolerance.to(METER)
    var welder = Welder(tol)
    for r in range(len(regions)):
        _check_region(regions[r], layers, tol)
    # Every edge of every region, as a segment.
    var seg_a = List[Point2]()
    var seg_b = List[Point2]()
    for r in range(len(regions)):
        var n = len(regions[r].points)
        for i in range(n):  # pragma: no branch
            seg_a.append(regions[r].points[i])
            seg_b.append(regions[r].points[(i + 1) % n])
    var count = len(seg_a)
    # The split points of each segment, with their parameters.
    var split_t = List[List[Float64]](capacity=count)
    var split_p = List[List[Point2]](capacity=count)
    for i in range(count):
        split_t.append([Float64(0), Float64(1)])
        split_p.append([seg_a[i], seg_b[i]])
    for i in range(count):
        for j in range(i + 1, count):
            var a = seg_a[i]
            var b = seg_b[i]
            var c = seg_a[j]
            var d = seg_b[j]
            # An end of one segment on the other.
            var ends = [c, d]
            for e in range(2):  # pragma: no branch
                var t = _on_segment(ends[e], a, b, tol)
                if t >= 0:
                    split_t[i].append(t)
                    split_p[i].append(ends[e])
            var others = [a, b]
            for e in range(2):  # pragma: no branch
                var t = _on_segment(others[e], c, d, tol)
                if t >= 0:
                    split_t[j].append(t)
                    split_p[j].append(others[e])
            # A proper crossing.
            if _segments_cross(a, b, c, d):
                var r = b - a
                var s = d - c
                var t = (c - a).cross(s) / r.cross(s)
                var p = Point2(a.x + t * r.x, a.y + t * r.y)
                var u = (p - c).dot(s) / s.dot(s)
                split_t[i].append(t)
                split_p[i].append(p)
                split_t[j].append(u)
                split_p[j].append(p)
    # Weld the split points and join consecutive ones into edges.
    var edge_index = Dict[Int, Int]()
    var ea = List[Int]()
    var eb = List[Int]()
    for i in range(count):
        var m = len(split_t[i])
        # Insertion sort by parameter.
        var k = 1
        while k < m:
            var held_t = split_t[i][k]
            var held_p = split_p[i][k]
            # The first parameter is zero, so the search stops there.
            var j = k - 1
            while split_t[i][j] > held_t:
                split_t[i][j + 1] = split_t[i][j]
                split_p[i][j + 1] = split_p[i][j]
                j -= 1
            split_t[i][j + 1] = held_t
            split_p[i][j + 1] = held_p
            k += 1
        var previous = welder.weld(Vec3d(split_p[i][0].x, split_p[i][0].y, 0))
        k = 1
        while k < m:
            var p = split_p[i][k]
            var current = welder.weld(Vec3d(p.x, p.y, 0))
            if current != previous:
                var low = min(previous, current)
                var high = max(previous, current)
                var key = low * 1000003 + high
                if key not in edge_index:
                    edge_index[key] = len(ea)
                    ea.append(low)
                    eb.append(high)
            previous = current
            k += 1
    var points = List[Point2](capacity=len(welder.points))
    for i in range(len(welder.points)):
        points.append(Point2(welder.points[i].x, welder.points[i].y))
    var faces = List[ArrangementFace]()
    var edges = List[ArrangementEdge]()
    var loops = List[List[Int]]()
    var loop_of: List[Int]
    var face_of_loop = List[Int]()
    # Trace; bridge each enclosed component to the face around it; repeat.
    while True:
        loops.clear()
        loop_of = _trace(points, ea, eb, loops)
        faces.clear()
        face_of_loop.clear()
        for l in range(len(loops)):
            if signed_area(points, loops[l]) > 0:
                face_of_loop.append(len(faces))
                faces.append(ArrangementFace(loops[l].copy(), List[RegionId]()))
            else:
                face_of_loop.append(-1)
        var enclosed = -1
        for l in range(len(loops)):
            if face_of_loop[l] >= 0:
                continue
            # A component has a bounded face, so faces is not empty here.
            var probe = points[loops[l][0]]
            for f in range(len(faces)):  # pragma: no branch
                if _loop_holds(points, faces[f].loop, loops[l], probe):
                    enclosed = l
        if enclosed < 0:
            break
        _bridge(points, ea, eb, edge_index, loops[enclosed], tol)
    # Labels.
    for f in range(len(faces)):
        var inside = _interior_point(points, faces[f].loop)
        for layer in range(layers):  # pragma: no branch
            var label = NO_REGION
            for r in range(len(regions)):  # pragma: no branch
                if regions[r].layer != layer:
                    continue
                if contains(regions[r].points, inside):
                    if label.is_valid():
                        raise Error("Regions of one layer must not overlap")
                    label = regions[r].id
            faces[f].labels.append(label)
    for e in range(len(ea)):
        edges.append(
            ArrangementEdge(
                ea[e],
                eb[e],
                face_of_loop[loop_of[2 * e]],
                face_of_loop[loop_of[2 * e + 1]],
            )
        )
    return Arrangement(points^, edges^, faces^, layers)


def _tail(ea: List[Int], eb: List[Int], h: Int) -> Int:
    """Return the start vertex of a half-edge: even from a, odd from b."""
    return ea[h >> 1] if h & 1 == 0 else eb[h >> 1]


def _angle(
    points: List[Point2], ea: List[Int], eb: List[Int], h: Int
) -> Float64:
    """Return the direction of a half-edge, in radians."""
    var tail = points[_tail(ea, eb, h)]
    var head = points[_tail(ea, eb, h ^ 1)]
    return atan2(head.y - tail.y, head.x - tail.x)


def _loop_holds(
    points: List[Point2], face: List[Int], other: List[Int], probe: Point2
) -> Bool:
    """Return True if a face strictly holds a loop that shares none of its
    vertices."""
    for i in range(len(other)):  # pragma: no branch
        for k in range(len(face)):  # pragma: no branch
            if other[i] == face[k]:
                return False
    var corners = List[Point2](capacity=len(face))
    for k in range(len(face)):  # pragma: no branch
        corners.append(points[face[k]])
    return contains(corners, probe)


def _trace(
    points: List[Point2],
    ea: List[Int],
    eb: List[Int],
    mut loops: List[List[Int]],
) -> List[Int]:
    """Trace every loop of half-edges and return each half-edge's loop.

    At each vertex the outgoing half-edges are sorted counterclockwise.
    The loop to the left of a half-edge continues along the outgoing
    half-edge just clockwise of its twin.
    """
    var half_count = 2 * len(ea)
    var outgoing = List[List[Int]](capacity=len(points))
    for _ in range(len(points)):
        outgoing.append(List[Int]())
    for h in range(half_count):
        outgoing[_tail(ea, eb, h)].append(h)
    for v in range(len(points)):
        var out = outgoing[v].copy()
        var k = 1
        while k < len(out):
            var held = out[k]
            var held_angle = _angle(points, ea, eb, held)
            var j = k - 1
            while j >= 0 and _angle(points, ea, eb, out[j]) > held_angle:
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = held
            k += 1
        outgoing[v] = out^
    var loop_of = List[Int](capacity=half_count)
    for _ in range(half_count):
        loop_of.append(-1)
    for start in range(half_count):
        if loop_of[start] >= 0:
            continue
        var loop = List[Int]()
        var h = start
        while loop_of[h] < 0:
            loop_of[h] = len(loops)
            loop.append(_tail(ea, eb, h))
            var head = _tail(ea, eb, h ^ 1)
            ref around = outgoing[head]
            var position = 0
            while around[position] != (h ^ 1):
                position += 1
            h = around[(position + len(around) - 1) % len(around)]
        loops.append(loop^)
    return loop_of^


def _bridge(
    points: List[Point2],
    mut ea: List[Int],
    mut eb: List[Int],
    mut edge_index: Dict[Int, Int],
    hole: List[Int],
    tolerance: Float64,
) raises:
    """Join an enclosed loop to the nearest vertex it can see outside it.

    The bridge starts at the loop's leftmost vertex. A candidate is any
    vertex not on the loop. The segment to it must not cross an edge and
    must not pass near another vertex.
    """
    var start = hole[0]
    for i in range(len(hole)):  # pragma: no branch
        if points[hole[i]].x < points[start].x:
            start = hole[i]
    var on_hole = List[Bool](capacity=len(points))
    for _ in range(len(points)):  # pragma: no branch
        on_hole.append(False)
    for i in range(len(hole)):  # pragma: no branch
        on_hole[hole[i]] = True
    var best = -1
    var best_distance = Float64(0)
    var a = points[start]
    for v in range(len(points)):  # pragma: no branch
        if on_hole[v]:
            continue
        var b = points[v]
        var d = b - a
        var distance = d.dot(d)
        if best >= 0 and distance >= best_distance:
            continue
        var visible = True
        for e in range(len(ea)):  # pragma: no branch
            if _segments_cross(a, b, points[ea[e]], points[eb[e]]):
                visible = False
                break
        if visible:
            for w in range(len(points)):  # pragma: no branch
                if w != v and w != start:
                    if _on_segment(points[w], a, b, tolerance) >= 0:
                        visible = False
                        break
        if visible:
            best = v
            best_distance = distance
    # The leftmost corner of a hole always sees a corner outside it.
    debug_assert(best >= 0, "a hole must see a corner outside it")
    var low = min(start, best)
    var high = max(start, best)
    edge_index[low * 1000003 + high] = len(ea)
    ea.append(low)
    eb.append(high)
