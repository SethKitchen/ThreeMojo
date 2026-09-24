# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The connectivity of a mesh as Draco's encoder writes it, from Draco
1.5.6: the other half of `loaders.draco_mesh`.

- `mesh/corner_table.cc`: `build_corner_table`, which finds the opposite
  corner of each corner, breaks the edges that more than two triangles
  share, and splits the vertices whose triangles do not form one fan.
- `mesh/mesh_attribute_corner_table.cc`: `seam_table`, the connectivity
  of an attribute, cut where its values differ across an edge.
- `compression/mesh/mesh_edgebreaker_encoder_impl.cc` with its standard
  and valence traversal encoders: `encode_edgebreaker`, which writes one
  symbol for each triangle, the topology splits, the start faces and the
  attribute seams.
- `compression/mesh/traverser`: `traverse`, the order in which the values
  of an attribute are stored, depth first or best predicted first.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**Indices.** A corner, vertex or face index is an `Int`, and `NONE`
(-1) stands for Draco's invalid index, as in `loaders.draco_mesh`.
"""

from exporters.draco_writer import (
    DEFAULT_SYMBOL_LEVEL,
    DracoBitWriter,
    DracoWriter,
    RAnsBitEncoder,
    encode_symbols,
)
from loaders.draco_buffer import draco_require
from loaders.draco_mesh import (
    DRACO_DEPTH_FIRST,
    NONE,
    DracoCornerTable,
    DracoTraversalMethod,
    attribute_connectivity,
)
from std.collections import Dict

# The symbols as their bit patterns, and the bits of each.
comptime _C = 0
comptime _S = 1
comptime _L = 3
comptime _R = 5
comptime _E = 7
# The edge of a split's source face that meets the split face.
comptime _LEFT_EDGE = 0
comptime _RIGHT_EDGE = 1


def _symbol_bits(symbol: Int) -> Int:
    """The bits of a symbol's pattern: one for `C`, three for the rest."""
    if symbol == _C:
        return 1
    return 3


def _symbol_id(symbol: Int) -> Int:
    """Draco's `edge_breaker_topology_to_symbol_id`: C, S, L, R, E as 0 to
    4."""
    if symbol == _C:
        return 0
    if symbol == _S:
        return 1
    if symbol == _L:
        return 2
    if symbol == _R:
        return 3
    return 4


struct EncoderTable(Copyable, Movable):
    """A corner table as Draco's encoder builds it from triangles."""

    var table: DracoCornerTable
    """The table."""
    var degenerated: Int
    """The triangles with a repeated vertex, which the table leaves out."""
    var isolated: Int
    """The vertices that no triangle of the table uses."""

    def __init__(out self, var table: DracoCornerTable):
        """Keep a table, with no counts yet.

        Args:
            table: The table.
        """
        self.table = table^
        self.degenerated = 0
        self.isolated = 0

    def is_degenerated(self, face: Int) -> Bool:
        """Return True if a triangle repeats a vertex.

        Args:
            face: The triangle.

        Returns:
            True when two of its corners have the same vertex.
        """
        var a = self.table.corner_to_vertex[3 * face]
        var b = self.table.corner_to_vertex[3 * face + 1]
        var c = self.table.corner_to_vertex[3 * face + 2]
        return a == b or a == c or b == c

    def valence(self, vertex: Int) raises -> Int:
        """Return the vertices joined to a vertex by an edge.

        Draco's `CornerTable::Valence`, which counts the steps of its
        `VertexRingIterator`.

        Args:
            vertex: The vertex.

        Returns:
            The count; zero for an isolated vertex.

        Raises:
            Error: If the vertex is not in the table.
        """
        var start = self.table.left_most(vertex)
        var count = 0
        var corner = start
        var left = True
        while corner != NONE:
            count += 1
            if left:
                corner = self.table.swing_left(corner)
                if corner == NONE:
                    corner = start
                    left = False
                elif corner == start:
                    corner = NONE
            else:
                corner = self.table.swing_right(corner)
        return count


def build_corner_table(faces: List[Int]) raises -> EncoderTable:
    """Build the corner table of a list of triangles.

    Draco's `CornerTable::Create`: `ComputeOppositeCorners`,
    `BreakNonManifoldEdges` and `ComputeVertexCorners`.

    Args:
        faces: The vertex of each corner, three for each triangle.

    Returns:
        The table, with its counts of degenerate triangles and isolated
        vertices.

    Raises:
        Error: Never for triangles whose vertices are zero or more.
    """
    var table = DracoCornerTable(len(faces) // 3)
    for c in range(len(faces)):
        table.corner_to_vertex[c] = faces[c]
    var out = EncoderTable(table^)
    var vertices = _opposite_corners(out)
    _break_non_manifold_edges(out.table)
    _vertex_corners(out, vertices)
    return out^


def _opposite_corners(mut out: EncoderTable) -> Int:
    """Draco's `ComputeOppositeCorners`: join each half-edge to the first
    free half-edge that runs the other way, and count the degenerate
    triangles. Returns the vertices."""
    ref table = out.table
    var corners = table.corners()
    var counts = List[Int]()
    for c in range(corners):
        var v = table.corner_to_vertex[c]
        while v >= len(counts):
            counts.append(0)
        counts[v] += 1
    var sinks = List[Int](length=corners, fill=NONE)
    var edges = List[Int](length=corners, fill=NONE)
    var offsets = List[Int](capacity=len(counts))
    var offset = 0
    for count in counts:
        offsets.append(offset)
        offset += count
    var c = 0
    while c < corners:
        var tip = table.vertex(c)
        var source = table.vertex(table.next(c))
        var sink = table.vertex(table.previous(c))
        if c % 3 == 0 and (tip == source or tip == sink or source == sink):
            out.degenerated += 1
            c += 3
            continue
        var opposite = NONE
        var at = offsets[sink]
        var i = 0
        while i < counts[sink]:
            var other = sinks[at]
            if other == NONE:
                break
            if other == source and tip != table.vertex(edges[at]):
                opposite = edges[at]
                var j = i + 1
                while j < counts[sink]:
                    sinks[at] = sinks[at + 1]
                    edges[at] = edges[at + 1]
                    if sinks[at] == NONE:
                        break
                    j += 1
                    at += 1
                sinks[at] = NONE
                break
            i += 1
            at += 1
        if opposite == NONE:
            at = offsets[source]
            for _ in range(counts[source]):  # pragma: no branch
                if sinks[at] == NONE:
                    sinks[at] = sink
                    edges[at] = c
                    break
                at += 1
        else:
            table.set_opposites(c, opposite)
        c += 1
    return len(counts)


def _break_non_manifold_edges(mut table: DracoCornerTable):
    """Draco's `BreakNonManifoldEdges`: where the fan of a vertex meets
    the same neighbor twice, cut both edges, until no fan does."""
    var corners = table.corners()
    # Draco keeps the visited corners from one pass to the next.
    var visited = List[Bool](length=corners, fill=False)
    var updated = True
    while updated:
        updated = False
        for c in range(corners):
            if visited[c]:
                continue
            var first = c
            var current = c
            var next = table.swing_left(current)
            # Draco also stops at a visited corner. A fan is walked from its
            # left end, and a cut takes the opposites out in both
            # directions, so a corner to the left of one not visited is
            # never visited itself.
            while next != first and next != NONE:
                current = next
                next = table.swing_left(current)
            first = current
            var sinks = List[Tuple[Int, Int]]()
            while True:
                visited[current] = True
                var sink_corner = table.next(current)
                var sink = table.corner_to_vertex[sink_corner]
                var edge = table.previous(current)
                var cut = False
                for attached in sinks:
                    if attached[0] != sink:
                        continue
                    var other = attached[1]
                    var opposite = table.opposite(edge)
                    if opposite == other:
                        continue
                    var other_opposite = table.opposite(other)
                    if opposite != NONE:
                        table.opposites[opposite] = NONE
                    if other_opposite != NONE:
                        table.opposites[other_opposite] = NONE
                    table.opposites[edge] = NONE
                    table.opposites[other] = NONE
                    cut = True
                    break
                if cut:
                    updated = True
                    break
                sinks.append(
                    (
                        table.corner_to_vertex[table.previous(current)],
                        sink_corner,
                    )
                )
                current = table.swing_right(current)
                if current == first or current == NONE:
                    break


def _vertex_corners(mut out: EncoderTable, var vertices: Int):
    """Draco's `ComputeVertexCorners`: the left-most corner of each
    vertex, with a new vertex for each further fan of a vertex, and the
    count of isolated vertices."""
    ref table = out.table
    table.vertex_corners = List[Int](length=vertices, fill=NONE)
    var vertex_done = List[Bool](length=vertices, fill=False)
    var corner_done = List[Bool](length=table.corners(), fill=False)
    for f in range(table.faces()):
        if out.is_degenerated(f):
            continue
        for k in range(3):  # pragma: no branch
            var c = 3 * f + k
            if corner_done[c]:
                continue
            var v = table.corner_to_vertex[c]
            var split = False
            if vertex_done[v]:
                table.vertex_corners.append(NONE)
                vertex_done.append(False)
                v = vertices
                vertices += 1
                split = True
            vertex_done[v] = True
            var at = c
            while at != NONE:
                corner_done[at] = True
                table.vertex_corners[v] = at
                if split:
                    table.corner_to_vertex[at] = v
                at = table.swing_left(at)
                if at == c:
                    break
            if at == NONE:
                at = table.swing_right(c)
                while at != NONE:
                    corner_done[at] = True
                    if split:
                        table.corner_to_vertex[at] = v
                    at = table.swing_right(at)
    out.isolated = 0
    for done in vertex_done:
        if not done:
            out.isolated += 1


struct SeamTable(Copyable, Movable):
    """The connectivity of one attribute, cut at its seams.

    Draco's `MeshAttributeCornerTable` after `InitFromAttribute`.
    """

    var table: DracoCornerTable
    """The table: opposites cut at seams, vertices split there."""
    var on_edge: List[Bool]
    """For each corner, True if the edge it faces is a seam or a border."""
    var no_interior_seams: Bool
    """True if the only seams are the borders of the mesh."""

    def __init__(
        out self,
        var table: DracoCornerTable,
        var on_edge: List[Bool],
        no_interior_seams: Bool,
    ):
        """Keep a table and its seams.

        Args:
            table: The table.
            on_edge: The seam flag of each corner.
            no_interior_seams: True if the only seams are borders.
        """
        self.table = table^
        self.on_edge = on_edge^
        self.no_interior_seams = no_interior_seams


def seam_table(
    base: EncoderTable, points: List[Int], values: List[Int]
) raises -> SeamTable:
    """Build the table of an attribute from the mesh's table.

    Draco's `MeshAttributeCornerTable::InitFromAttribute`: an edge is a
    seam where it is a border, or where a corner of it has another value
    on each side.

    Args:
        base: The table of the mesh.
        points: The point of each corner.
        values: The attribute's value for each point.

    Returns:
        The attribute's table.

    Raises:
        Error: Never for a table that `build_corner_table` built.
    """
    ref table = base.table
    var seams = List[Int]()
    var on_edge = List[Bool](length=table.corners(), fill=False)
    var no_interior_seams = True
    # A mesh past the check has a triangle: the loop runs.
    for c in range(table.corners()):  # pragma: no branch
        if base.is_degenerated(c // 3):
            continue
        var opposite = table.opposite(c)
        if opposite == NONE:
            seams.append(c)
            on_edge[c] = True
            continue
        if opposite < c:
            continue
        var at = c
        var sibling = opposite
        for _ in range(2):  # pragma: no branch
            at = table.next(at)
            sibling = table.previous(sibling)
            if values[points[at]] != values[points[sibling]]:
                no_interior_seams = False
                seams.append(c)
                on_edge[c] = True
                on_edge[opposite] = True
                break
    var connectivity = attribute_connectivity(table, seams)
    return SeamTable(connectivity.table.copy(), on_edge^, no_interior_seams)


struct EncodingData(Copyable, Movable):
    """The order in which the values of an attribute are stored.

    Draco's `MeshAttributeIndicesEncodingData`, filled by `traverse`.
    """

    var value_corners: List[Int]
    """For each stored value, the corner it was reached at."""
    var vertex_values: List[Int]
    """For each vertex, its value; -1 for a vertex not reached."""
    var points: List[Int]
    """The point of each stored value."""

    def __init__(out self, vertices: Int):
        """Make the data for a table of `vertices` vertices.

        Args:
            vertices: The vertices.
        """
        self.value_corners = List[Int]()
        self.vertex_values = List[Int](length=vertices, fill=NONE)
        self.points = List[Int]()

    def visit(mut self, vertex: Int, corner: Int, faces: List[Int]):
        """Store the next value, reached at a corner.

        Draco's `MeshAttributeIndicesEncodingObserver::OnNewVertexVisited`.

        Args:
            vertex: The vertex of the table.
            corner: The corner it was reached at.
            faces: The point of each corner.
        """
        self.points.append(faces[corner])
        self.vertex_values[vertex] = len(self.value_corners)
        self.value_corners.append(corner)


def traverse(
    table: DracoCornerTable,
    faces: List[Int],
    order: List[Int],
    method: DracoTraversalMethod,
) raises -> EncodingData:
    """Visit the vertices of a table from each corner of an order.

    Draco's `MeshTraversalSequencer` with its `DepthFirstTraverser` or
    `MaxPredictionDegreeTraverser`.

    Args:
        table: The table to walk: the mesh's or an attribute's.
        faces: The point of each corner.
        order: The corners to start from, in turn.
        method: `DRACO_DEPTH_FIRST` or `DRACO_PREDICTION_DEGREE`.

    Returns:
        The order of the values and the point of each.

    Raises:
        Error: If the table has a corner with no vertex.
    """
    var data = EncodingData(table.vertices())
    if method == DRACO_DEPTH_FIRST:
        _depth_first(table, faces, order, data)
    else:
        _prediction_degree(table, faces, order, data)
    return data^


def _depth_first(
    table: DracoCornerTable,
    faces: List[Int],
    order: List[Int],
    mut data: EncodingData,
) raises:
    """Draco's `DepthFirstTraverser::TraverseFromCorner`, from each corner
    of the order."""
    var face_done = List[Bool](length=table.faces(), fill=False)
    var vertex_done = List[Bool](length=table.vertices(), fill=False)
    var stack = List[Int]()
    # A mesh past the check has a triangle: the loop runs.
    for start in order:  # pragma: no branch
        if face_done[start // 3]:
            continue
        stack.clear()
        stack.append(start)
        var ends: List[Int] = [table.next(start), table.previous(start)]
        for corner in ends:  # pragma: no branch
            var vertex = table.vertex(corner)
            draco_require(vertex != NONE, "a corner has no vertex")
            if not vertex_done[vertex]:
                vertex_done[vertex] = True
                data.visit(vertex, corner, faces)
        while len(stack) > 0:
            var corner = stack[len(stack) - 1]
            if face_done[corner // 3]:
                _ = stack.pop()
                continue
            while True:
                face_done[corner // 3] = True
                var vertex = table.vertex(corner)
                draco_require(vertex != NONE, "a corner has no vertex")
                if not vertex_done[vertex]:
                    var on_boundary = table.is_on_boundary(vertex)
                    vertex_done[vertex] = True
                    data.visit(vertex, corner, faces)
                    if not on_boundary:
                        corner = table.right_corner(corner)
                        continue
                var right = table.right_corner(corner)
                var left = table.left_corner(corner)
                var right_done = right == NONE or face_done[right // 3]
                var left_done = left == NONE or face_done[left // 3]
                if right_done:
                    if left_done:
                        _ = stack.pop()
                        break
                    corner = left
                elif left_done:
                    corner = right
                else:
                    stack[len(stack) - 1] = left
                    stack.append(right)
                    break


def _prediction_degree(
    table: DracoCornerTable,
    faces: List[Int],
    order: List[Int],
    mut data: EncodingData,
) raises:
    """Draco's `MaxPredictionDegreeTraverser::TraverseFromCorner`, from
    each corner of the order."""
    var face_done = List[Bool](length=table.faces(), fill=False)
    var vertex_done = List[Bool](length=table.vertices(), fill=False)
    var degree = List[Int](length=table.vertices(), fill=0)
    var stacks: List[List[Int]] = [List[Int](), List[Int](), List[Int]()]
    # A mesh past the check has a triangle: the loop runs.
    for start in order:  # pragma: no branch
        stacks[0].append(start)
        var best = 0
        var ends: List[Int] = [table.next(start), table.previous(start), start]
        for corner in ends:  # pragma: no branch
            var vertex = table.vertex(corner)
            if not vertex_done[vertex]:
                vertex_done[vertex] = True
                data.visit(vertex, corner, faces)
        while True:
            var corner = NONE
            # The best priority is 0, 1 or 2. The loop always runs.
            for priority in range(best, 3):  # pragma: no branch
                if len(stacks[priority]) > 0:
                    corner = stacks[priority].pop()
                    best = priority
                    break
            if corner == NONE:
                break
            if face_done[corner // 3]:
                continue
            while True:
                face_done[corner // 3] = True
                var vertex = table.vertex(corner)
                if not vertex_done[vertex]:
                    vertex_done[vertex] = True
                    data.visit(vertex, corner, faces)
                var right = table.right_corner(corner)
                var left = table.left_corner(corner)
                var right_done = right == NONE or face_done[right // 3]
                var left_done = left == NONE or face_done[left // 3]
                if not left_done:
                    var priority = _priority(table, left, vertex_done, degree)
                    if right_done and priority <= best:
                        corner = left
                        continue
                    stacks[priority].append(left)
                    best = min(best, priority)
                if not right_done:
                    var priority = _priority(table, right, vertex_done, degree)
                    if priority <= best:
                        corner = right
                        continue
                    stacks[priority].append(right)
                    best = min(best, priority)
                break


def _priority(
    table: DracoCornerTable,
    corner: Int,
    vertex_done: List[Bool],
    mut degree: List[Int],
) -> Int:
    """Draco's `ComputePriority`: 0 for a reached tip, 1 for a tip that
    two faces predict, 2 otherwise."""
    var tip = table.vertex(corner)
    if vertex_done[tip]:
        return 0
    degree[tip] += 1
    if degree[tip] > 1:
        return 1
    return 2


struct _Valence(Movable):
    """The state of Draco's `MeshEdgebreakerTraversalValenceEncoder`."""

    var corner_vertex: List[Int]
    var valences: List[Int]
    var previous_symbol: Int
    var last_corner: Int
    var contexts: List[List[Int]]

    def __init__(out self, base: EncoderTable) raises:
        var table = base.table.copy()
        self.corner_vertex = table.corner_to_vertex.copy()
        self.valences = List[Int](capacity=table.vertices())
        # A mesh past the check has a triangle: the loop runs.
        for v in range(table.vertices()):  # pragma: no branch
            self.valences.append(base.valence(v))
        self.previous_symbol = NONE
        self.last_corner = NONE
        self.contexts = List[List[Int]]()
        for _ in range(6):  # pragma: no branch
            self.contexts.append(List[Int]())


struct EdgebreakerData(Movable):
    """What the attribute encoders need from the connectivity."""

    var base: EncoderTable
    """The corner table of the mesh."""
    var order: List[Int]
    """The corners to traverse the attributes from, in turn."""
    var attributes: List[Int]
    """The attribute of each attribute data: each attribute but the
    position, when their tables are kept apart."""
    var seams: List[SeamTable]
    """The table of each attribute data."""

    def __init__(out self, var base: EncoderTable):
        """Keep the table of the mesh.

        Args:
            base: The table.
        """
        self.base = base^
        self.order = List[Int]()
        self.attributes = List[Int]()
        self.seams = List[SeamTable]()


struct _Edgebreaker(Movable):
    """The state of `MeshEdgebreakerEncoderImpl` while it encodes."""

    var base: EncoderTable
    var valence: Optional[_Valence]
    var face_done: List[Bool]
    var vertex_done: List[Bool]
    var hole_of: List[Int]
    var holes_done: List[Bool]
    var processed: List[Int]
    var symbols: List[Int]
    var last_symbol: Int
    var splits: Int
    var split_faces: Dict[Int, Int]
    var events: List[Tuple[Int, Int, Int]]
    var start_faces: RAnsBitEncoder
    var stack: List[Int]

    def __init__(out self, var base: EncoderTable, valence: Bool) raises:
        var vertices = base.table.vertices()
        var faces = base.table.faces()
        self.valence = None
        if valence:
            self.valence = _Valence(base)
        self.base = base^
        self.face_done = List[Bool](length=faces, fill=False)
        self.vertex_done = List[Bool](length=vertices, fill=False)
        self.hole_of = List[Int](length=vertices, fill=NONE)
        self.holes_done = List[Bool]()
        self.processed = List[Int]()
        self.symbols = List[Int]()
        self.last_symbol = NONE
        self.splits = 0
        self.split_faces = Dict[Int, Int]()
        self.events = List[Tuple[Int, Int, Int]]()
        self.start_faces = RAnsBitEncoder()
        self.stack = List[Int]()

    def find_holes(mut self):
        """Draco's `FindHoles`: number each border loop, and mark its
        vertices."""
        ref table = self.base.table
        # A mesh past the check has a triangle: the loop runs.
        for i in range(table.corners()):  # pragma: no branch
            if self.base.is_degenerated(i // 3):
                continue
            if table.opposite(i) != NONE:
                continue
            var vertex = table.vertex(table.next(i))
            if self.hole_of[vertex] != NONE:
                continue
            var hole = len(self.holes_done)
            self.holes_done.append(False)
            var corner = i
            while self.hole_of[vertex] == NONE:
                self.hole_of[vertex] = hole
                corner = table.next(corner)
                while table.opposite(corner) != NONE:
                    corner = table.next(table.opposite(corner))
                vertex = table.vertex(table.next(corner))

    def start_face(self, face: Int) -> Tuple[Bool, Int]:
        """Draco's `FindInitFaceConfiguration`: an interior face starts at
        any corner; a face on a border starts where the border is."""
        ref table = self.base.table
        var corner = 3 * face
        for _ in range(3):  # pragma: no branch
            if table.opposite(corner) == NONE:
                return (False, corner)
            if self.hole_of[table.vertex(corner)] != NONE:
                var right = corner
                while right != NONE:
                    corner = right
                    right = table.swing_right(right)
                return (False, table.previous(corner))
            corner = table.next(corner)
        return (True, corner)

    def encode_hole(mut self, start: Int, first_vertex: Bool):
        """Draco's `EncodeHole`: mark the vertices of the border loop that
        a corner starts."""
        ref table = self.base.table
        var corner = table.previous(start)
        while table.opposite(corner) != NONE:
            corner = table.next(table.opposite(corner))
        var start_vertex = table.vertex(start)
        if first_vertex:
            self.vertex_done[start_vertex] = True
        self.holes_done[self.hole_of[start_vertex]] = True
        var vertex = table.vertex(table.previous(corner))
        while vertex != start_vertex:
            self.vertex_done[vertex] = True
            corner = table.next(corner)
            while table.opposite(corner) != NONE:
                corner = table.next(table.opposite(corner))
            vertex = table.vertex(table.previous(corner))

    def symbol(mut self, symbol: Int, corner: Int) raises:
        """Record a symbol, and count valences for the valence traversal."""
        self.symbols.append(symbol)
        if not Bool(self.valence):
            return
        ref table = self.base.table
        ref v = self.valence.value()
        var next = table.next(corner)
        var prev = table.previous(corner)
        var active = v.valences[v.corner_vertex[next]]
        if symbol == _C or symbol == _S:
            v.valences[v.corner_vertex[next]] -= 1
            v.valences[v.corner_vertex[prev]] -= 1
            if symbol == _S:
                var left = 0
                var at = table.opposite(prev)
                while at != NONE:
                    if self.face_done[at // 3]:
                        break
                    left += 1
                    at = table.opposite(table.next(at))
                v.valences[v.corner_vertex[corner]] = left + 1
                var new_vertex = len(v.valences)
                var right = 0
                at = table.opposite(next)
                while at != NONE:
                    if self.face_done[at // 3]:
                        break
                    right += 1
                    v.corner_vertex[table.next(at)] = new_vertex
                    at = table.opposite(table.previous(at))
                v.valences.append(right + 1)
        elif symbol == _R:
            v.valences[v.corner_vertex[corner]] -= 1
            v.valences[v.corner_vertex[next]] -= 1
            v.valences[v.corner_vertex[prev]] -= 2
        elif symbol == _L:
            v.valences[v.corner_vertex[corner]] -= 1
            v.valences[v.corner_vertex[next]] -= 2
            v.valences[v.corner_vertex[prev]] -= 1
        else:
            v.valences[v.corner_vertex[corner]] -= 2
            v.valences[v.corner_vertex[next]] -= 2
            v.valences[v.corner_vertex[prev]] -= 2
        if v.previous_symbol != NONE:
            var context = min(max(active, 2), 7) - 2
            v.contexts[context].append(_symbol_id(v.previous_symbol))
        v.previous_symbol = symbol

    def split_event(mut self, source: Int, edge: Int, neighbor: Int):
        """Draco's `CheckAndStoreTopologySplitEvent`."""
        var split = self.split_faces.get(neighbor, NONE)
        if split == NONE:
            return
        self.events.append((split, source, edge))

    def face_done_at(self, corner: Int) -> Bool:
        """True if the face of a corner is encoded, or there is none."""
        if corner == NONE:
            return True
        return self.face_done[corner // 3]

    def from_corner(mut self, start: Int) raises:
        """Draco's `EncodeConnectivityFromCorner`."""
        ref table = self.base.table
        self.stack.clear()
        self.stack.append(start)
        while len(self.stack) > 0:
            var corner = self.stack[len(self.stack) - 1]
            if self.face_done[corner // 3]:
                _ = self.stack.pop()
                continue
            while True:
                self.last_symbol += 1
                var face = corner // 3
                self.face_done[face] = True
                self.processed.append(corner)
                var vertex = table.vertex(corner)
                var on_boundary = self.hole_of[vertex] != NONE
                if not self.vertex_done[vertex]:
                    self.vertex_done[vertex] = True
                    if not on_boundary:
                        self.symbol(_C, corner)
                        corner = table.right_corner(corner)
                        continue
                var right = table.right_corner(corner)
                var left = table.left_corner(corner)
                if self.face_done_at(right):
                    if right != NONE:
                        self.split_event(
                            self.last_symbol, _RIGHT_EDGE, right // 3
                        )
                    if self.face_done_at(left):
                        if left != NONE:
                            self.split_event(
                                self.last_symbol, _LEFT_EDGE, left // 3
                            )
                        self.symbol(_E, corner)
                        _ = self.stack.pop()
                        break
                    self.symbol(_R, corner)
                    corner = left
                elif self.face_done_at(left):
                    if left != NONE:
                        self.split_event(
                            self.last_symbol, _LEFT_EDGE, left // 3
                        )
                    self.symbol(_L, corner)
                    corner = right
                else:
                    self.symbol(_S, corner)
                    self.splits += 1
                    if (
                        on_boundary
                        and not self.holes_done[self.hole_of[vertex]]
                    ):
                        self.encode_hole(corner, False)
                    self.split_faces[face] = self.last_symbol
                    self.stack[len(self.stack) - 1] = left
                    self.stack.append(right)
                    break


def encode_edgebreaker(
    mut out: DracoWriter,
    faces: List[Int],
    corner_vertices: List[Int],
    attribute_values: List[List[Int]],
    valence: Bool,
) raises -> EdgebreakerData:
    """Write the Edgebreaker connectivity of a mesh.

    Draco's `MeshEdgebreakerEncoderImpl::EncodeConnectivity`: the counts,
    the traversal of the triangles as symbols, the topology splits, the
    start faces and the seams of each attribute.

    Args:
        out: Where to write it.
        faces: The point of each corner.
        corner_vertices: The vertex of each corner that the table is
            built from: the position value, or the point when every
            attribute shares the table.
        attribute_values: The value of each point for each attribute that
            has a table of its own.
        valence: True for the valence traversal, False for the standard.

    Returns:
        The table, the order of the corners, and the seam tables.

    Raises:
        Error: If every triangle is degenerate, as Draco fails.
    """
    var base = build_corner_table(corner_vertices)
    draco_require(
        base.table.faces() != base.degenerated,
        "all triangles are degenerate",
    )
    var state = _Edgebreaker(base.copy(), valence)
    ref table = base.table
    out.varint(table.vertices() - base.isolated)
    out.varint(table.faces() - base.degenerated)
    state.find_holes()
    var data = EdgebreakerData(base.copy())
    for values in attribute_values:
        data.seams.append(seam_table(base, faces, values))
    out.u8(len(attribute_values))
    var init_corners = List[Int]()
    # A mesh past the check has a triangle: the loop runs.
    for c in range(table.corners()):  # pragma: no branch
        var face = c // 3
        if state.face_done[face] or base.is_degenerated(face):
            continue
        var start = state.start_face(face)
        state.start_faces.encode_bit(start[0])
        var corner = start[1]
        if start[0]:
            state.vertex_done[table.vertex(corner)] = True
            state.vertex_done[table.vertex(table.next(corner))] = True
            state.vertex_done[table.vertex(table.previous(corner))] = True
            state.face_done[face] = True
            init_corners.append(table.next(corner))
            # Draco goes on only when the face across is not encoded yet.
            # A face whose corners all have opposites starts a new part of
            # the mesh, so the face across is never encoded yet.
            state.from_corner(table.opposite(table.next(corner)))
        else:
            state.encode_hole(table.next(corner), True)
            state.from_corner(corner)
    state.processed.reverse()
    state.processed.extend(init_corners^)
    var seams = List[RAnsBitEncoder]()
    for _ in range(len(attribute_values)):
        seams.append(RAnsBitEncoder())
    if len(attribute_values) > 0:
        var face_done = List[Bool](length=table.faces(), fill=False)
        # A mesh past the check has a triangle: the loop runs.
        for corner in state.processed:  # pragma: no branch
            var corners: List[Int] = [
                corner,
                table.next(corner),
                table.previous(corner),
            ]
            face_done[corner // 3] = True
            for c in corners:  # pragma: no branch
                var opposite = table.opposite(c)
                if opposite == NONE or face_done[opposite // 3]:
                    continue
                for i in range(len(seams)):  # pragma: no branch
                    seams[i].encode_bit(data.seams[i].on_edge[c])
    var traversal = DracoWriter()
    if not Bool(state.valence):
        var bits = DracoBitWriter()
        var i = len(state.symbols) - 1
        while i >= 0:
            bits.put(_symbol_bits(state.symbols[i]), state.symbols[i])
            i -= 1
        bits.end(traversal, True)
    state.start_faces.end(traversal)
    for seam in seams:
        seam.end(traversal)
    if Bool(state.valence):
        for context in state.valence.value().contexts:  # pragma: no branch
            traversal.varint(len(context))
            encode_symbols(traversal, context, 1, DEFAULT_SYMBOL_LEVEL)
    out.varint(len(state.symbols))
    out.varint(state.splits)
    out.varint(len(state.events))
    if len(state.events) > 0:
        var last = 0
        # The events are there: the loop runs.
        for event in state.events:  # pragma: no branch
            out.varint(event[1] - last)
            out.varint(event[1] - event[0])
            last = event[1]
        var bits = DracoBitWriter()
        # The events are there: the loop runs.
        for event in state.events:  # pragma: no branch
            bits.put(1, event[2])
        bits.end(out, False)
    out.append(traversal.bytes)
    data.order = state.processed.copy()
    return data^
