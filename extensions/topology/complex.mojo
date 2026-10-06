# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cell complex: vertices, edges, faces and cells that share them.

A face is a planar polygon given by a loop of vertices. Its normal follows
the right-hand rule around the loop. The cell on the side the normal
points to is the face's `positive` cell; the cell behind it is its
`negative` cell. A side with no cell is the outside.

A cell is the region bounded by its faces. A face belongs to at most two
cells, so two rooms that share a wall share one face. `validate` checks
that every cell is closed: each edge of its boundary, oriented outward,
is used once in each direction.

This is the non-manifold topology that architectural design tools use to
reason about spaces and their boundaries. See Aish and Pratap, "Spatial
information modeling of buildings using non-manifold topology with ASM
and DesignScript" (2013).
"""

from std.math import isfinite, sqrt
from extensions.topology.ids import CellId, EdgeId, FaceId, VertexId
from extensions.topology.weld import Welder
from generators.utils import Vec3d


@fieldwise_init
struct FaceKind(Equatable, ImplicitlyCopyable, Writable):
    """Whether a face stands up, like a wall, or lies flat, like a floor."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two kinds.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1


comptime VERTICAL = FaceKind(0)
comptime HORIZONTAL = FaceKind(1)


struct Face(Copyable, Movable):
    """A planar polygon and the cells on its two sides."""

    var loop: List[VertexId]
    var positive: Optional[CellId]
    var negative: Optional[CellId]
    var kind: FaceKind

    def __init__(
        out self,
        var loop: List[VertexId],
        positive: Optional[CellId],
        negative: Optional[CellId],
        kind: FaceKind,
    ):
        """Create a face.

        Args:
            loop: The corners, counterclockwise seen from the positive side.
            positive: The cell the normal points into, or None outside.
            negative: The cell behind the face, or None outside.
            kind: Whether the face is vertical or horizontal.
        """
        self.loop = loop^
        self.positive = positive
        self.negative = negative
        self.kind = kind


@fieldwise_init
struct Edge(ImplicitlyCopyable):
    """An edge between two vertices, the lower index first."""

    var a: VertexId
    var b: VertexId


struct CellComplex(Movable):
    """Vertices, edges, faces and cells that share them."""

    var welder: Welder
    var edges: List[Edge]
    var faces: List[Face]
    # The faces of each cell.
    var cell_faces: List[List[FaceId]]
    # The faces that use each edge.
    var edge_faces: List[List[FaceId]]
    var _edge_index: Dict[Int, Int]

    def __init__(out self, tolerance: Float64) raises:
        """Create an empty complex.

        Args:
            tolerance: Vertices closer than this, in meters, are one vertex.

        Raises:
            Error: If the tolerance is not positive and finite.
        """
        self.welder = Welder(tolerance)
        self.edges = List[Edge]()
        self.faces = List[Face]()
        self.cell_faces = List[List[FaceId]]()
        self.edge_faces = List[List[FaceId]]()
        self._edge_index = Dict[Int, Int]()

    # --- building ---------------------------------------------------------

    def add_vertex(mut self, p: Vec3d) raises -> VertexId:
        """Return the vertex at a point, adding it if there is none near.

        Args:
            p: The point, in meters.

        Returns:
            The vertex.

        Raises:
            Error: If a coordinate is not finite.
        """
        return VertexId(self.welder.weld(p))

    def add_cell(mut self) -> CellId:
        """Add a cell with no faces yet.

        Returns:
            The new cell.
        """
        self.cell_faces.append(List[FaceId]())
        return CellId(len(self.cell_faces) - 1)

    def add_face(
        mut self,
        var loop: List[VertexId],
        positive: Optional[CellId],
        negative: Optional[CellId],
        kind: FaceKind,
    ) raises -> FaceId:
        """Add a face and record it on its cells and edges.

        Args:
            loop: The corners, counterclockwise seen from the positive side.
            positive: The cell the normal points into, or None outside.
            negative: The cell behind the face, or None outside.
            kind: Whether the face is vertical or horizontal.

        Returns:
            The new face.

        Raises:
            Error: If the loop has fewer than three distinct corners, a
                vertex or cell is out of range, both sides are the same
                cell, or the kind is not valid.
        """
        if not kind.is_valid():
            raise Error("A face kind must be vertical or horizontal")
        if len(loop) < 3:
            raise Error("A face needs three corners or more")
        for i in range(len(loop)):  # pragma: no branch
            self._check_vertex(loop[i])
            if loop[i] == loop[(i + 1) % len(loop)]:
                raise Error("A face must not repeat a corner")
        if positive:
            self._check_cell(positive.value())
        if negative:
            self._check_cell(negative.value())
        if positive and negative and positive.value() == negative.value():
            raise Error("A face must not have one cell on both sides")
        var face = FaceId(len(self.faces))
        var n = len(loop)
        for i in range(n):  # pragma: no branch
            var edge = self._edge(loop[i], loop[(i + 1) % n])
            self.edge_faces[edge.value].append(face)
        if positive:
            self.cell_faces[positive.value().value].append(face)
        if negative:
            self.cell_faces[negative.value().value].append(face)
        self.faces.append(Face(loop^, positive, negative, kind))
        return face

    def _edge(mut self, u: VertexId, v: VertexId) -> EdgeId:
        """Return the edge between two vertices, adding it if needed."""
        var low = min(u.value, v.value)
        var high = max(u.value, v.value)
        var key = low * 4294967296 + high
        if key in self._edge_index:
            return EdgeId(self._edge_index.get(key, 0))
        self._edge_index[key] = len(self.edges)
        self.edges.append(Edge(VertexId(low), VertexId(high)))
        self.edge_faces.append(List[FaceId]())
        return EdgeId(len(self.edges) - 1)

    # --- checks -----------------------------------------------------------

    def _check_vertex(self, v: VertexId) raises:
        """Refuse a vertex id that is not in range."""
        if not v.is_valid() or v.value >= len(self.welder.points):
            raise Error("A vertex id is out of range")

    def _check_cell(self, c: CellId) raises:
        """Refuse a cell id that is not in range."""
        if not c.is_valid() or c.value >= len(self.cell_faces):
            raise Error("A cell id is out of range")

    def _check_face(self, f: FaceId) raises:
        """Refuse a face id that is not in range."""
        if not f.is_valid() or f.value >= len(self.faces):
            raise Error("A face id is out of range")

    # --- queries ----------------------------------------------------------

    def vertex_count(self) -> Int:
        """Return how many vertices there are.

        Returns:
            The vertex count.
        """
        return len(self.welder.points)

    def cell_count(self) -> Int:
        """Return how many cells there are.

        Returns:
            The cell count.
        """
        return len(self.cell_faces)

    def vertex(self, v: VertexId) raises -> Vec3d:
        """Return where a vertex is.

        Args:
            v: The vertex.

        Returns:
            Its position, in meters.

        Raises:
            Error: If the id is out of range.
        """
        self._check_vertex(v)
        return self.welder.points[v.value]

    def face_points(self, f: FaceId) raises -> List[Vec3d]:
        """Return the corners of a face in loop order.

        Args:
            f: The face.

        Returns:
            The corners, in meters.

        Raises:
            Error: If the id is out of range.
        """
        self._check_face(f)
        var out = List[Vec3d]()
        ref loop = self.faces[f.value].loop
        for i in range(len(loop)):  # pragma: no branch
            out.append(self.vertex(loop[i]))
        return out^

    def faces_of(self, c: CellId) raises -> List[FaceId]:
        """Return the faces that bound a cell.

        Args:
            c: The cell.

        Returns:
            Its faces.

        Raises:
            Error: If the id is out of range.
        """
        self._check_cell(c)
        return self.cell_faces[c.value].copy()

    def other_side(self, f: FaceId, c: CellId) raises -> Optional[CellId]:
        """Return the cell across a face from a cell, or None outside.

        Args:
            f: The face.
            c: A cell on one side of it.

        Returns:
            The cell on the other side, or None for the outside.

        Raises:
            Error: If an id is out of range or the cell is not on either
                side of the face.
        """
        self._check_face(f)
        self._check_cell(c)
        ref face = self.faces[f.value]
        if face.positive and face.positive.value() == c:
            return face.negative
        if face.negative and face.negative.value() == c:
            return face.positive
        raise Error("The cell is not on either side of the face")

    def neighbors(self, c: CellId) raises -> List[CellId]:
        """Return the cells that share a face with a cell, once each.

        Args:
            c: The cell.

        Returns:
            The neighboring cells, in order of first shared face.

        Raises:
            Error: If the id is out of range.
        """
        var out = List[CellId]()
        var faces = self.faces_of(c)
        for i in range(len(faces)):
            var other = self.other_side(faces[i], c)
            if not other:
                continue
            var seen = False
            for k in range(len(out)):
                if out[k] == other.value():
                    seen = True
            if not seen:
                out.append(other.value())
        return out^

    def shared_faces(self, c: CellId, d: CellId) raises -> List[FaceId]:
        """Return the faces two cells share.

        Args:
            c: One cell.
            d: The other cell.

        Returns:
            The faces with `c` on one side and `d` on the other.

        Raises:
            Error: If an id is out of range.
        """
        self._check_cell(d)
        var out = List[FaceId]()
        var faces = self.faces_of(c)
        for i in range(len(faces)):
            var other = self.other_side(faces[i], c)
            if other and other.value() == d:
                out.append(faces[i])
        return out^

    def exterior_faces(self, c: CellId) raises -> List[FaceId]:
        """Return the faces of a cell that have the outside across them.

        Args:
            c: The cell.

        Returns:
            Those faces.

        Raises:
            Error: If the id is out of range.
        """
        var out = List[FaceId]()
        var faces = self.faces_of(c)
        for i in range(len(faces)):
            if not self.other_side(faces[i], c):
                out.append(faces[i])
        return out^

    def face_vector_area(self, f: FaceId) raises -> Vec3d:
        """Return a face's normal scaled by its area, by Newell's method.

        Args:
            f: The face.

        Returns:
            The vector area, in square meters. Its direction is the normal.

        Raises:
            Error: If the id is out of range.
        """
        var p = self.face_points(f)
        var n = len(p)
        var total = Vec3d(0, 0, 0)
        for i in range(n):  # pragma: no branch
            var a = p[i]
            var b = p[(i + 1) % n]
            total = total + Vec3d(
                (a.y - b.y) * (a.z + b.z),
                (a.z - b.z) * (a.x + b.x),
                (a.x - b.x) * (a.y + b.y),
            )
        return total * 0.5

    def face_area(self, f: FaceId) raises -> Float64:
        """Return the area of a face.

        Args:
            f: The face.

        Returns:
            The area, in square meters.

        Raises:
            Error: If the id is out of range.
        """
        return self.face_vector_area(f).length()

    def face_normal(self, f: FaceId) raises -> Vec3d:
        """Return the unit normal of a face, toward its positive side.

        Args:
            f: The face.

        Returns:
            The unit normal.

        Raises:
            Error: If the id is out of range.
        """
        return self.face_vector_area(f).normalized()

    def face_centroid(self, f: FaceId) raises -> Vec3d:
        """Return the mean of a face's corners.

        Args:
            f: The face.

        Returns:
            The mean corner, in meters. It is inside a convex face.

        Raises:
            Error: If the id is out of range.
        """
        var p = self.face_points(f)
        var total = Vec3d(0, 0, 0)
        for i in range(len(p)):  # pragma: no branch
            total = total + p[i]
        return total * (1.0 / Float64(len(p)))

    def outward_normal(self, f: FaceId, c: CellId) raises -> Vec3d:
        """Return a face's unit normal pointing out of a cell.

        Args:
            f: The face.
            c: A cell on one side of it.

        Returns:
            The unit normal, away from `c`.

        Raises:
            Error: If an id is out of range or the cell is not on either
                side of the face.
        """
        _ = self.other_side(f, c)
        var n = self.face_normal(f)
        ref face = self.faces[f.value]
        if face.positive and face.positive.value() == c:
            return n * -1.0
        return n

    def cell_volume(self, c: CellId) raises -> Float64:
        """Return the volume of a cell, by the divergence theorem.

        Args:
            c: The cell.

        Returns:
            The volume, in cubic meters.

        Raises:
            Error: If the id is out of range.
        """
        var faces = self.faces_of(c)
        var total = Float64(0)
        for i in range(len(faces)):
            var p = self.face_points(faces[i])
            var sign = Float64(1)
            ref face = self.faces[faces[i].value]
            if face.positive and face.positive.value() == c:
                sign = -1
            var a = p[0]
            var k = 1
            while k + 1 < len(p):
                var b = p[k]
                var d = p[k + 1]
                total += sign * a.dot(b.cross(d))
                k += 1
        return total / 6

    def validate(self) raises:
        """Refuse a complex with a cell that is not closed.

        Each cell's faces, oriented outward, must use every edge once in
        each direction.

        Raises:
            Error: If a cell is open or a face is used twice by one cell.
        """
        # Public arrays can be edited after construction. Check every
        # reference before the closure walk indexes it.
        if not (self.welder.tolerance > 0 and isfinite(self.welder.tolerance)):
            raise Error("A weld tolerance must be positive and finite")
        for i in range(len(self.welder.points)):
            var point = self.welder.points[i]
            if not (
                isfinite(point.x) and isfinite(point.y) and isfinite(point.z)
            ):
                raise Error("A vertex must have finite coordinates")
        if len(self.edge_faces) != len(self.edges):
            raise Error("Each edge needs an incident-face list")
        for i in range(len(self.edges)):
            self._check_vertex(self.edges[i].a)
            self._check_vertex(self.edges[i].b)
            if self.edges[i].a == self.edges[i].b:
                raise Error("An edge needs distinct vertices")
            for k in range(len(self.edge_faces[i])):
                self._check_face(self.edge_faces[i][k])
        for i in range(len(self.faces)):
            ref face = self.faces[i]
            if not face.kind.is_valid():
                raise Error("A face kind must be vertical or horizontal")
            if len(face.loop) < 3:
                raise Error("A face needs three corners or more")
            # The preceding guard guarantees at least three corners.
            for k in range(len(face.loop)):  # pragma: no branch
                self._check_vertex(face.loop[k])
                if face.loop[k] == face.loop[(k + 1) % len(face.loop)]:
                    raise Error("A face must not repeat a corner")
            if face.positive:
                self._check_cell(face.positive.value())
            if face.negative:
                self._check_cell(face.negative.value())
            if face.positive and face.negative:
                if face.positive.value() == face.negative.value():
                    raise Error("A face must not have one cell on both sides")
            var sides = [face.positive, face.negative]
            # This list always contains the two optional sides.
            for side in sides:  # pragma: no branch
                if side:
                    ref incident = self.cell_faces[side.value().value]
                    var matches = 0
                    for k in range(len(incident)):
                        if incident[k] == FaceId(i):
                            matches += 1
                    if matches != 1:
                        raise Error(
                            "Face and cell incidence must be reciprocal"
                        )
        for c in range(len(self.cell_faces)):
            var directed = Dict[Int, Int]()
            ref faces = self.cell_faces[c]
            for i in range(len(faces)):
                self._check_face(faces[i])
                ref face = self.faces[faces[i].value]
                var on_positive = (
                    face.positive and face.positive.value() == CellId(c)
                )
                var on_negative = (
                    face.negative and face.negative.value() == CellId(c)
                )
                if not (on_positive or on_negative):
                    raise Error("A cell's face must name that cell")
                var outward = not (
                    face.positive and face.positive.value() == CellId(c)
                )
                var n = len(face.loop)
                for k in range(n):  # pragma: no branch
                    var u = face.loop[k].value
                    var v = face.loop[(k + 1) % n].value
                    if not outward:
                        var held = u
                        u = v
                        v = held
                    var key = u * 4294967296 + v
                    if key in directed:
                        raise Error("A cell uses one edge twice the same way")
                    directed[key] = 1
            for entry in directed.items():
                var u = entry.key // 4294967296
                var v = entry.key % 4294967296
                if (v * 4294967296 + u) not in directed:
                    raise Error(
                        String(
                            "A cell is not closed: cell ",
                            c,
                            " edge ",
                            u,
                            " ",
                            v,
                        )
                    )
