# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The convex hull of a set of points, from three.js
`examples/jsm/math/ConvexHull.js`.

three.js ports quickhull, and this ports three.js step by step. The hull
starts as the tetrahedron of four extreme points. Each point outside it is
given to one face that can see it. Then, face by face, the farthest point
a face can see is added: every face that point can see is removed, the
edge of the hole they leave is the horizon, and a fan of new faces joins
the horizon to the point. The points the removed faces held go to the new
faces, or are dropped when they are now inside. It stops when no face can
see any point.

three.js links faces, half edges and points with object references. Here
they are rows in parallel lists, and a reference is a row number, with -1
for JavaScript's `null`. A face that is removed keeps its row and is marked
deleted, as in three.js, and `faces` lists the rows still on the hull.

The arithmetic is `Float64`, as JavaScript's is. The tolerance that decides
whether a face can see a point is three.js's, three times the `Float64`
epsilon times the size of the point set, and it is only meaningful at that
precision.

three.js returns an empty hull for fewer than four points, and a flat or
broken one for points that are all on a line or a plane. This port refuses
all three.
"""

from math.vector3 import Vector3
from std.math import isfinite, sqrt

# JavaScript's `Number.EPSILON`: the gap between one and the next `Float64`.
comptime DOUBLE_EPSILON = Float64(2.220446049250313e-16)


@fieldwise_init
struct _Point(ImplicitlyCopyable):
    """A point in `Float64`, for the hull's own arithmetic."""

    var x: Float64
    var y: Float64
    var z: Float64

    def dot(self, other: Self) -> Float64:
        """Return the dot product, summed in three.js's order."""
        return self.x * other.x + self.y * other.y + self.z * other.z

    def __sub__(self, other: Self) -> Self:
        """Return the component-wise difference."""
        return _Point(self.x - other.x, self.y - other.y, self.z - other.z)

    def __add__(self, other: Self) -> Self:
        """Return the component-wise sum."""
        return _Point(self.x + other.x, self.y + other.y, self.z + other.z)

    def __mul__(self, factor: Float64) -> Self:
        """Return this point scaled by a number."""
        return _Point(self.x * factor, self.y * factor, self.z * factor)

    def cross(self, other: Self) -> Self:
        """Return the cross product, three.js's `crossVectors`."""
        return _Point(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )

    def component(self, axis: Int) -> Float64:
        """Return x, y or z for an axis of zero, one or two."""
        if axis == 0:
            return self.x
        if axis == 1:
            return self.y
        return self.z


def _unit_or_zero(normal: _Point) -> _Point:
    """Return `normal` made unit length, or zero if it has no length, as
    three.js's `Triangle.getNormal` does."""
    var length_squared = normal.dot(normal)
    return normal * (
        1 / sqrt(length_squared)
    ) if length_squared > 0 else _Point(0, 0, 0)


struct ConvexHull(Movable):
    """The smallest convex solid that holds every point of a set.

    Build one with `ConvexHull(points)`. Its faces are triangles, wound
    counter-clockwise seen from outside, and coplanar faces are not merged,
    as in three.js.
    """

    # How far outside a face a point must be before the face can see it.
    var tolerance: Float64
    # The rows of the faces on the hull, in three.js's order.
    var faces: List[Int]
    # The points, one row each, with the list links three.js's `VertexNode`
    # has, and the face that can see the point.
    var _points: List[_Point]
    var _vertex_prev: List[Int]
    var _vertex_next: List[Int]
    var _vertex_face: List[Int]
    # The faces, one row each: three.js's `Face`.
    var _normal: List[_Point]
    var _constant: List[Float64]
    var _outside: List[Int]
    var _visible: List[Bool]
    var _face_edge: List[Int]
    # The half edges, one row each: three.js's `HalfEdge`.
    var _edge_vertex: List[Int]
    var _edge_prev: List[Int]
    var _edge_next: List[Int]
    var _edge_twin: List[Int]
    var _edge_face: List[Int]
    # The two vertex lists, by their first and last rows.
    var _assigned_head: Int
    var _assigned_tail: Int
    var _unassigned_head: Int
    var _unassigned_tail: Int
    # The faces made while one point is added.
    var _new_faces: List[Int]

    def __init__(out self, points: List[Vector3]) raises:
        """Compute the hull of `points`, three.js's `setFromPoints`.

        Args:
            points: The points, in meters.

        Raises:
            Error: If there are fewer than four points, any number is not
                finite, or the points all lie on one point, one line or one
                plane.
        """
        var doubles = List[SIMD[DType.float64, 4]]()
        for point in points:  # pragma: no branch
            doubles.append(
                SIMD[DType.float64, 4](
                    Float64(point.x), Float64(point.y), Float64(point.z), 0
                )
            )
        self = Self(doubles)

    def __init__(out self, points: List[SIMD[DType.float64, 4]]) raises:
        """Compute the hull of points given in doubles, as three.js's are:
        the first three numbers of each, in meters.

        Args:
            points: The points.

        Raises:
            Error: If there are fewer than four points, any number is not
                finite, or the points all lie on one point, one line or one
                plane.
        """
        if len(points) < 4:
            raise Error("A convex hull needs at least four points")
        self.tolerance = -1
        self.faces = List[Int]()
        self._points = List[_Point]()
        self._vertex_prev = List[Int]()
        self._vertex_next = List[Int]()
        self._vertex_face = List[Int]()
        self._normal = List[_Point]()
        self._constant = List[Float64]()
        self._outside = List[Int]()
        self._visible = List[Bool]()
        self._face_edge = List[Int]()
        self._edge_vertex = List[Int]()
        self._edge_prev = List[Int]()
        self._edge_next = List[Int]()
        self._edge_twin = List[Int]()
        self._edge_face = List[Int]()
        self._assigned_head = -1
        self._assigned_tail = -1
        self._unassigned_head = -1
        self._unassigned_tail = -1
        self._new_faces = List[Int]()
        # Four points at least, checked above.
        for point in points:  # pragma: no branch
            if not (
                isfinite(point[0]) and isfinite(point[1]) and isfinite(point[2])
            ):
                raise Error("A convex hull needs finite points")
            self._points.append(_Point(point[0], point[1], point[2]))
            self._vertex_prev.append(-1)
            self._vertex_next.append(-1)
            self._vertex_face.append(-1)
        self._compute()

    # --- The public reading side -------------------------------------------

    def face_count(self) -> Int:
        """Return how many triangles the hull has.

        Returns:
            The face count.
        """
        return len(self.faces)

    def face_vertex(self, face: Int, corner: Int) raises -> Int:
        """Return which input point stands at one corner of one face.

        The corners are in three.js's order: the head of the face's first
        half edge, then of the next, then of the last.

        Args:
            face: Which face, from zero, in `faces` order.
            corner: Which corner, zero to two.

        Returns:
            The point's position in the list the hull was built from.

        Raises:
            Error: If either number is out of range.
        """
        if face < 0 or face >= len(self.faces):
            raise Error("A face index is out of range")
        if corner < 0 or corner > 2:
            raise Error("A face has three corners")
        return self._edge_vertex[self._edge(self.faces[face], corner)]

    def face_normal(self, face: Int) raises -> Vector3:
        """Return the outward unit normal of one face.

        Args:
            face: Which face, from zero, in `faces` order.

        Returns:
            The normal.

        Raises:
            Error: If `face` is out of range.
        """
        if face < 0 or face >= len(self.faces):
            raise Error("A face index is out of range")
        var n = self._normal[self.faces[face]]
        return Vector3(Float32(n.x), Float32(n.y), Float32(n.z))

    def contains_point(self, point: Vector3) -> Bool:
        """Return True if `point` is inside the hull or on it, three.js's
        `containsPoint`.

        Args:
            point: The point, in meters.

        Returns:
            Whether no face sees the point from more than the tolerance.
        """
        var p = _Point(Float64(point.x), Float64(point.y), Float64(point.z))
        # A hull always has four faces at least.
        for face in self.faces:  # pragma: no branch
            if self._distance(face, p) > self.tolerance:
                return False
        return True

    # --- Faces and half edges ----------------------------------------------

    def _distance(self, face: Int, point: _Point) -> Float64:
        """Return how far `point` is outside a face's plane."""
        return self._normal[face].dot(point) - self._constant[face]

    def _edge(self, face: Int, steps: Int) -> Int:
        """Return a face's half edge `steps` on from its first, three.js's
        `getEdge`: a negative count walks backwards."""
        var edge = self._face_edge[face]
        var count = steps
        while count > 0:
            edge = self._edge_next[edge]
            count -= 1
        while count < 0:
            edge = self._edge_prev[edge]
            count += 1
        return edge

    def _tail(self, edge: Int) -> Int:
        """Return the point a half edge starts from."""
        return self._edge_vertex[self._edge_prev[edge]]

    def _set_twin(mut self, a: Int, b: Int):
        """Make two half edges each other's twin."""
        self._edge_twin[a] = b
        self._edge_twin[b] = a

    def _create_face(mut self, a: Int, b: Int, c: Int) -> Int:
        """Add a triangle over three points, three.js's `Face.create`.

        Returns:
            The new face's row.
        """
        var face = len(self._face_edge)
        var e0 = len(self._edge_vertex)
        var corners = [a, b, c]
        for k in range(3):  # pragma: no branch
            self._edge_vertex.append(corners[k])
            self._edge_prev.append(e0 + (k + 2) % 3)
            self._edge_next.append(e0 + (k + 1) % 3)
            self._edge_twin.append(-1)
            self._edge_face.append(face)
        self._face_edge.append(e0)
        self._outside.append(-1)
        self._visible.append(True)
        # three.js's `Face.compute`: a triangle over the first edge's tail,
        # its head and the next head, which is c, a and b.
        var pa = self._points[c]
        var pb = self._points[a]
        var pc = self._points[b]
        var normal = _unit_or_zero((pc - pb).cross(pa - pb))
        var midpoint = (pa + pb + pc) * (Float64(1) / 3)
        self._normal.append(normal)
        self._constant.append(normal.dot(midpoint))
        return face

    # --- The two vertex lists ----------------------------------------------

    def _append(mut self, vertex: Int):
        """Add one point at the end of the assigned list, three.js's
        `append`."""
        var tail = self._assigned_tail
        if tail == -1:
            self._assigned_head = vertex
        else:
            self._vertex_next[tail] = vertex
        self._vertex_prev[vertex] = tail
        self._vertex_next[vertex] = -1
        self._assigned_tail = vertex

    def _insert_before(mut self, target: Int, vertex: Int):
        """Put a point before another in the assigned list."""
        self._vertex_prev[vertex] = self._vertex_prev[target]
        self._vertex_next[vertex] = target
        if self._vertex_prev[vertex] == -1:
            self._assigned_head = vertex
        else:
            self._vertex_next[self._vertex_prev[vertex]] = vertex
        self._vertex_prev[target] = vertex

    def _remove_sub_list(mut self, a: Int, b: Int):
        """Unlink the run of points from `a` to `b` from the assigned list,
        three.js's `removeSubList`; `remove` is the run of one."""
        var before = self._vertex_prev[a]
        var after = self._vertex_next[b]
        if before == -1:
            self._assigned_head = after
        else:
            self._vertex_next[before] = after
        if after == -1:
            self._assigned_tail = before
        else:
            self._vertex_prev[after] = before

    def _append_chain(mut self, vertex: Int):
        """Add a linked run of points at the end of the unassigned list."""
        if self._unassigned_head == -1:
            self._unassigned_head = vertex
        else:
            self._vertex_next[self._unassigned_tail] = vertex
        self._vertex_prev[vertex] = self._unassigned_tail
        var last = vertex
        while self._vertex_next[last] != -1:
            last = self._vertex_next[last]
        self._unassigned_tail = last

    # --- Quickhull ---------------------------------------------------------

    def _add_vertex_to_face(mut self, vertex: Int, face: Int):
        """Give a point to a face that can see it."""
        self._vertex_face[vertex] = face
        if self._outside[face] == -1:
            self._append(vertex)
        else:
            self._insert_before(self._outside[face], vertex)
        self._outside[face] = vertex

    def _remove_vertex_from_face(mut self, vertex: Int, face: Int):
        """Take a point back from the face that held it."""
        if vertex == self._outside[face]:
            var next = self._vertex_next[vertex]
            if next != -1 and self._vertex_face[next] == face:
                self._outside[face] = next
            else:
                self._outside[face] = -1
        self._remove_sub_list(vertex, vertex)

    def _delete_face_vertices(mut self, face: Int):
        """Move every point a face holds to the unassigned list.

        three.js's `_removeAllVerticesFromFace` and `_deleteFaceVertices`.
        three.js can also offer them to an absorbing face first. Nothing in
        three.js passes one, so that branch is not ported.
        """
        var start = self._outside[face]
        if start == -1:
            return
        var end = start
        var next = self._vertex_next[end]
        while next != -1 and self._vertex_face[next] == face:
            end = next
            next = self._vertex_next[end]
        self._remove_sub_list(start, end)
        self._vertex_prev[start] = -1
        self._vertex_next[end] = -1
        self._outside[face] = -1
        self._append_chain(start)

    def _resolve_unassigned_points(mut self):
        """Give each unassigned point to the new face that sees it farthest,
        or drop it when none can."""
        var vertex = self._unassigned_head
        while vertex != -1:
            var next = self._vertex_next[vertex]
            var max_distance = self.tolerance
            var max_face = -1
            # Every face in `_new_faces` was made in this step and none has
            # been removed yet, so three.js's `mark === Visible` test always
            # passes here and is left out.
            for face in self._new_faces:  # pragma: no branch
                var distance = self._distance(face, self._points[vertex])
                if distance > max_distance:
                    max_distance = distance
                    max_face = face
                if max_distance > 1000 * self.tolerance:
                    break
            if max_face != -1:
                self._add_vertex_to_face(vertex, max_face)
            vertex = next

    def _compute_extremes(mut self) -> Tuple[List[Int], List[Int]]:
        """Find the points at the least and the greatest x, y and z, and set
        the tolerance from them."""
        var min_vertices = List[Int](length=3, fill=0)
        var max_vertices = List[Int](length=3, fill=0)
        var low = [self._points[0].x, self._points[0].y, self._points[0].z]
        var high = low.copy()
        for vertex in range(len(self._points)):  # pragma: no branch
            var point = self._points[vertex]
            for axis in range(3):  # pragma: no branch
                if point.component(axis) < low[axis]:
                    low[axis] = point.component(axis)
                    min_vertices[axis] = vertex
            for axis in range(3):  # pragma: no branch
                if point.component(axis) > high[axis]:
                    high[axis] = point.component(axis)
                    max_vertices[axis] = vertex
        self.tolerance = (
            3
            * DOUBLE_EPSILON
            * (
                max(abs(low[0]), abs(high[0]))
                + max(abs(low[1]), abs(high[1]))
                + max(abs(low[2]), abs(high[2]))
            )
        )
        return (min_vertices^, max_vertices^)

    def _compute_initial_hull(mut self) raises:
        """Build the first tetrahedron and hand every other point to the
        face that sees it farthest."""
        var extremes = self._compute_extremes()
        ref low = extremes[0]
        ref high = extremes[1]

        # 1. The two points farthest apart along one axis.
        var max_distance = Float64(0)
        var index = 0
        for axis in range(3):  # pragma: no branch
            var distance = self._points[high[axis]].component(
                axis
            ) - self._points[low[axis]].component(axis)
            if distance > max_distance:
                max_distance = distance
                index = axis
        if max_distance == 0:
            raise Error("A convex hull needs points in more than one place")
        var v0 = low[index]
        var v1 = high[index]

        # 2. The point farthest from the segment between them.
        max_distance = 0
        var v2 = -1
        var start = self._points[v0]
        var delta = self._points[v1] - start
        var delta_squared = delta.dot(delta)
        for vertex in range(len(self._points)):  # pragma: no branch
            if vertex != v0 and vertex != v1:
                var point = self._points[vertex]
                var t = delta.dot(point - start) / delta_squared
                t = min(max(t, 0), 1)
                var closest = delta * t + start
                var gap = closest - point
                var distance = gap.dot(gap)
                if distance > max_distance:
                    max_distance = distance
                    v2 = vertex
        if v2 == -1:
            raise Error("A convex hull needs points that are not in a line")

        # 3. The point farthest from the plane of those three.
        var p0 = self._points[v0]
        var p1 = self._points[v1]
        var p2 = self._points[v2]
        var normal = (p2 - p1).cross(p0 - p1)
        # three.js's `normalize`, which multiplies by one over the length.
        normal = normal * (1 / sqrt(normal.dot(normal)))
        var constant = -p0.dot(normal)
        max_distance = -1
        var v3 = -1
        for vertex in range(len(self._points)):  # pragma: no branch
            if vertex != v0 and vertex != v1 and vertex != v2:
                var distance = abs(normal.dot(self._points[vertex]) + constant)
                if distance > max_distance:
                    max_distance = distance
                    v3 = vertex
        if max_distance <= self.tolerance:
            raise Error("A convex hull needs points that are not in a plane")

        var first = List[Int]()
        if normal.dot(self._points[v3]) + constant < 0:
            # The plane cannot see the fourth point, so its normal points out
            # of the tetrahedron.
            first.append(self._create_face(v0, v1, v2))
            first.append(self._create_face(v3, v1, v0))
            first.append(self._create_face(v3, v2, v1))
            first.append(self._create_face(v3, v0, v2))
            for i in range(3):  # pragma: no branch
                var j = (i + 1) % 3
                self._set_twin(
                    self._edge(first[i + 1], 2), self._edge(first[0], j)
                )
                self._set_twin(
                    self._edge(first[i + 1], 1), self._edge(first[j + 1], 0)
                )
        else:
            first.append(self._create_face(v0, v2, v1))
            first.append(self._create_face(v3, v0, v1))
            first.append(self._create_face(v3, v1, v2))
            first.append(self._create_face(v3, v2, v0))
            for i in range(3):  # pragma: no branch
                var j = (i + 1) % 3
                self._set_twin(
                    self._edge(first[i + 1], 2),
                    self._edge(first[0], (3 - i) % 3),
                )
                self._set_twin(
                    self._edge(first[i + 1], 0), self._edge(first[j + 1], 1)
                )
        for i in range(4):  # pragma: no branch
            self.faces.append(first[i])

        for vertex in range(len(self._points)):  # pragma: no branch
            if vertex != v0 and vertex != v1 and vertex != v2 and vertex != v3:
                max_distance = self.tolerance
                var max_face = -1
                for j in range(4):  # pragma: no branch
                    var distance = self._distance(
                        self.faces[j], self._points[vertex]
                    )
                    if distance > max_distance:
                        max_distance = distance
                        max_face = self.faces[j]
                if max_face != -1:
                    self._add_vertex_to_face(vertex, max_face)

    def _next_vertex_to_add(self) -> Int:
        """Return the point the first face with points sees farthest, or -1
        when no face sees any point."""
        if self._assigned_head == -1:
            return -1
        var eye_face = self._vertex_face[self._assigned_head]
        var eye_vertex = -1
        var max_distance = Float64(0)
        var vertex = self._outside[eye_face]
        while vertex != -1 and self._vertex_face[vertex] == eye_face:
            var distance = self._distance(eye_face, self._points[vertex])
            if distance > max_distance:
                max_distance = distance
                eye_vertex = vertex
            vertex = self._vertex_next[vertex]
        return eye_vertex

    def _compute_horizon(
        mut self,
        eye_point: _Point,
        cross_edge: Int,
        face: Int,
        mut horizon: List[Int],
    ):
        """Remove every face the eye point can see, starting from `face`,
        and collect the edges between them and the rest in order."""
        self._delete_face_vertices(face)
        self._visible[face] = False
        var stop = cross_edge
        var edge: Int
        if cross_edge == -1:
            edge = self._edge(face, 0)
            stop = edge
        else:
            # The edge the walk came in by was looked at from the other
            # side already, so start at the one after it.
            edge = self._edge_next[cross_edge]
        while True:
            var twin = self._edge_twin[edge]
            var opposite = self._edge_face[twin]
            if self._visible[opposite]:
                if self._distance(opposite, eye_point) > self.tolerance:
                    self._compute_horizon(eye_point, twin, opposite, horizon)
                else:
                    horizon.append(edge)
            edge = self._edge_next[edge]
            if edge == stop:
                break

    def _add_new_faces(mut self, eye_vertex: Int, horizon: List[Int]):
        """Join each horizon edge to the eye point with a new face, and join
        the new faces to each other."""
        self._new_faces = List[Int]()
        var first_side = -1
        var previous_side = -1
        # A point that a face sees always leaves a horizon of three edges or
        # more, so this loop cannot run zero times.
        for horizon_edge in horizon:  # pragma: no branch
            var face = self._create_face(
                eye_vertex,
                self._tail(horizon_edge),
                self._edge_vertex[horizon_edge],
            )
            self.faces.append(face)
            self._set_twin(self._edge(face, -1), self._edge_twin[horizon_edge])
            var side = self._edge(face, 0)
            if first_side == -1:
                first_side = side
            else:
                self._set_twin(self._edge_next[side], previous_side)
            self._new_faces.append(face)
            previous_side = side
        self._set_twin(self._edge_next[first_side], previous_side)

    def _add_vertex_to_hull(mut self, eye_vertex: Int):
        """Add one point to the hull."""
        var horizon = List[Int]()
        self._unassigned_head = -1
        self._unassigned_tail = -1
        var face = self._vertex_face[eye_vertex]
        self._remove_vertex_from_face(eye_vertex, face)
        var eye_point = self._points[eye_vertex]
        self._compute_horizon(eye_point, -1, face, horizon)
        self._add_new_faces(eye_vertex, horizon)
        self._resolve_unassigned_points()

    def _compute(mut self) raises:
        """Run quickhull to the end, then keep only the faces on the hull."""
        self._compute_initial_hull()
        var vertex = self._next_vertex_to_add()
        while vertex != -1:
            self._add_vertex_to_hull(vertex)
            vertex = self._next_vertex_to_add()
        var active = List[Int]()
        for face in self.faces:  # pragma: no branch
            if self._visible[face]:
                active.append(face)
        self.faces = active^
        self._new_faces = List[Int]()
        self._assigned_head = -1
        self._assigned_tail = -1
        self._unassigned_head = -1
        self._unassigned_tail = -1
