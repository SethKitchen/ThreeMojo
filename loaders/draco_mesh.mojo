# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The connectivity of a Draco mesh, from Draco 1.5.6.

Draco codes the triangles of a mesh with Edgebreaker: one symbol for each
triangle, `C`, `L`, `R`, `S` or `E`, says how it joins the triangles
decoded before it. This module ports:

- `mesh/corner_table` and `mesh/mesh_attribute_corner_table`:
  `DracoCornerTable`, which finds the opposite corner and the next
  triangle around a vertex.
- `compression/mesh/mesh_edgebreaker_decoder_impl.cc` with its standard
  and valence traversal decoders: `decode_edgebreaker`.
- `compression/mesh/traverser`: `traverse_depth_first` and
  `traverse_prediction_degree`, the orders in which the values of an
  attribute are stored.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**What is read.** The Edgebreaker data of mesh bitstream 2.2, which is
what Draco 1.5 and three.js's encoder write. The deprecated predictive
traversal is refused.

**Indices.** A corner, vertex or face index is an `Int`, and `NONE`
(-1) stands for Draco's invalid index. An index that the file gives is
checked before it is used; Draco reads past the end of its arrays for
some bad files.
"""

from loaders.draco_buffer import (
    DracoBuffer,
    RAnsBitDecoder,
    decode_symbols,
    draco_require,
)

# No corner, vertex or face.
comptime NONE = -1


@fieldwise_init
struct DracoTraversal(Equatable, ImplicitlyCopyable, Writable):
    """How the Edgebreaker symbols of a mesh are coded, as a type rather
    than a bare int.

    `decode_edgebreaker` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the standard and the valence traversal.

        Returns:
            True for the two traversals this port reads.
        """
        return self == DRACO_STANDARD_TRAVERSAL or (
            self == DRACO_VALENCE_TRAVERSAL
        )


# Each symbol as one or three bits.
comptime DRACO_STANDARD_TRAVERSAL = DracoTraversal(0)
# Symbols in streams chosen by the valence of the active vertex.
comptime DRACO_VALENCE_TRAVERSAL = DracoTraversal(2)


@fieldwise_init
struct DracoTraversalMethod(Equatable, ImplicitlyCopyable, Writable):
    """The order in which the values of an attribute are stored, as a type
    rather than a bare int.

    The attribute decoders refuse one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for depth first and for prediction degree.

        Returns:
            True for the two orders there are.
        """
        return self.value == 0 or self.value == 1


# Triangle by triangle, depth first.
comptime DRACO_DEPTH_FIRST = DracoTraversalMethod(0)
# The triangle whose vertex has the most decoded neighbors first.
comptime DRACO_PREDICTION_DEGREE = DracoTraversalMethod(1)

# The symbols as their bit patterns.
comptime _C = 0
comptime _S = 1
comptime _L = 3
comptime _R = 5
comptime _E = 7
comptime _INVALID_SYMBOL = 8


struct DracoCornerTable(Copyable, Movable):
    """The corners of a triangle mesh and how they meet.

    Draco's `CornerTable`. Corner `c` is corner `c % 3` of face `c / 3`.
    Each corner knows its vertex and the corner opposite it across its
    edge; each vertex knows its left-most corner.

    A `MeshAttributeCornerTable`, the connectivity of an attribute with
    seams, is one of these too: its opposites are cut at the seams and
    its vertices are split there.
    """

    var corner_to_vertex: List[Int]
    """The vertex of each corner."""
    var opposites: List[Int]
    """The corner opposite each corner, or `NONE`."""
    var vertex_corners: List[Int]
    """The left-most corner of each vertex, or `NONE`."""

    def __init__(out self, faces: Int):
        """Make a table of `faces` faces whose corners are all unset.

        Args:
            faces: The faces.
        """
        self.corner_to_vertex = List[Int](length=faces * 3, fill=NONE)
        self.opposites = List[Int](length=faces * 3, fill=NONE)
        self.vertex_corners = List[Int]()

    def corners(self) -> Int:
        """Return the corners.

        Returns:
            Three for each face.
        """
        return len(self.corner_to_vertex)

    def faces(self) -> Int:
        """Return the faces.

        Returns:
            The count.
        """
        return len(self.corner_to_vertex) // 3

    def vertices(self) -> Int:
        """Return the vertices.

        Returns:
            The count.
        """
        return len(self.vertex_corners)

    def next(self, corner: Int) -> Int:
        """Return the next corner of the same face.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The next corner, or `NONE`.
        """
        if corner < 0:
            return NONE
        if (corner + 1) % 3 == 0:
            return corner - 2
        return corner + 1

    def previous(self, corner: Int) -> Int:
        """Return the previous corner of the same face.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The previous corner, or `NONE`.
        """
        if corner < 0:
            return NONE
        if corner % 3 == 0:
            return corner + 2
        return corner - 1

    def opposite(self, corner: Int) -> Int:
        """Return the corner across the edge a corner faces.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The opposite corner, or `NONE` on a border.
        """
        if corner < 0:
            return NONE
        return self.opposites[corner]

    def vertex(self, corner: Int) -> Int:
        """Return the vertex of a corner.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The vertex, or `NONE`.
        """
        if corner < 0:
            return NONE
        return self.corner_to_vertex[corner]

    def left_most(self, vertex: Int) raises -> Int:
        """Return the left-most corner of a vertex.

        Args:
            vertex: A vertex.

        Returns:
            The corner, or `NONE` for an isolated vertex.

        Raises:
            Error: If the vertex is not in the table.
        """
        draco_require(
            vertex >= 0 and vertex < len(self.vertex_corners),
            "the connectivity names a vertex that does not exist",
        )
        return self.vertex_corners[vertex]

    def swing_right(self, corner: Int) -> Int:
        """Return the next corner of the same vertex, clockwise.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The corner, or `NONE` at a border.
        """
        return self.previous(self.opposite(self.previous(corner)))

    def swing_left(self, corner: Int) -> Int:
        """Return the next corner of the same vertex, counterclockwise.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The corner, or `NONE` at a border.
        """
        return self.next(self.opposite(self.next(corner)))

    def right_corner(self, corner: Int) -> Int:
        """Return the corner of the face to the right of a corner.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The corner, or `NONE`.
        """
        return self.opposite(self.next(corner))

    def left_corner(self, corner: Int) -> Int:
        """Return the corner of the face to the left of a corner.

        Args:
            corner: A corner, or `NONE`.

        Returns:
            The corner, or `NONE`.
        """
        return self.opposite(self.previous(corner))

    def is_on_boundary(self, vertex: Int) raises -> Bool:
        """Return True if a vertex is on a border.

        Args:
            vertex: A vertex.

        Returns:
            True when its left-most corner has no neighbor to the left.

        Raises:
            Error: If the vertex is not in the table.
        """
        return self.swing_left(self.left_most(vertex)) == NONE

    def set_opposites(mut self, a: Int, b: Int):
        """Make two corners opposite each other.

        Args:
            a: A corner.
            b: The other corner.
        """
        self.opposites[a] = b
        self.opposites[b] = a

    def set_left_most(mut self, vertex: Int, corner: Int) raises:
        """Set the left-most corner of a vertex.

        Draco skips an invalid vertex here. A valid file never gives one,
        so this refuses it.

        Args:
            vertex: A vertex.
            corner: Its corner.

        Raises:
            Error: If the vertex is not in the table.
        """
        _ = self.left_most(vertex)
        self.vertex_corners[vertex] = corner

    def add_vertex(mut self) -> Int:
        """Add an isolated vertex.

        Returns:
            Its index.
        """
        self.vertex_corners.append(NONE)
        return len(self.vertex_corners) - 1

    def corners_of(self, start: Int) raises -> List[Int]:
        """Return the corners around the vertex of a corner.

        Draco's `VertexCornersIterator`: from `start` to the left until
        the ring closes or reaches a border, then from `start` to the
        right.

        Args:
            start: A corner, or `NONE`.

        Returns:
            The corners, `start` first. Empty for `NONE`.

        Raises:
            Error: If the ring does not end, which a bad file can cause.
        """
        var out = List[Int]()
        var corner = start
        var left = True
        while corner != NONE:
            draco_require(
                len(out) <= self.corners(), "a vertex ring does not close"
            )
            out.append(corner)
            if left:
                corner = self.swing_left(corner)
                if corner == NONE:
                    corner = self.swing_right(start)
                    left = False
                elif corner == start:
                    corner = NONE
            else:
                corner = self.swing_right(corner)
        return out^


struct DracoAttributeConnectivity(Copyable, Movable):
    """The connectivity of one attribute with seams.

    Draco's `MeshAttributeCornerTable` after `AddSeamEdge` and
    `RecomputeVertices`, with its table built out.
    """

    var table: DracoCornerTable
    """The table, with opposites cut at seams and vertices split there."""
    var on_seam: List[Bool]
    """For each vertex of the mesh, True if a seam touches it."""
    var decoder: Int
    """The attributes decoder that reads this attribute, or `NONE`."""
    var used: Bool
    """False when the attribute's values are stored by vertex."""

    def __init__(
        out self, var table: DracoCornerTable, var on_seam: List[Bool]
    ):
        """Keep a table and the seam flags of the mesh's vertices.

        Args:
            table: The attribute's table.
            on_seam: For each vertex of the mesh, True if on a seam.
        """
        self.table = table^
        self.on_seam = on_seam^
        self.decoder = NONE
        self.used = True


struct DracoEncodingData(Copyable, Movable):
    """The order in which the values of an attribute are stored.

    Draco's `MeshAttributeIndicesEncodingData`, filled by a traversal.
    """

    var value_corners: List[Int]
    """For each stored value, the corner it was reached at."""
    var vertex_values: List[Int]
    """For each vertex, its value; zero for a vertex not reached."""

    def __init__(out self, vertices: Int):
        """Make the data for a table of `vertices` vertices.

        Args:
            vertices: The vertices.
        """
        self.value_corners = List[Int]()
        self.vertex_values = List[Int](length=vertices, fill=0)

    def visit(
        mut self,
        vertex: Int,
        corner: Int,
        faces: List[Int],
        mut points: List[Int],
    ):
        """Store the next value, reached at a corner.

        Draco's `MeshAttributeIndicesEncodingObserver::OnNewVertexVisited`.

        Args:
            vertex: The vertex of the attribute's table.
            corner: The corner it was reached at.
            faces: The points of the mesh's corners.
            points: The points in the order their values are stored.
        """
        points.append(faces[corner])
        self.vertex_values[vertex] = len(self.value_corners)
        self.value_corners.append(corner)


struct EdgebreakerConnectivity(Movable):
    """What `decode_edgebreaker` reads."""

    var table: DracoCornerTable
    """The corner table of the mesh."""
    var faces: List[Int]
    """The point of each corner."""
    var points: Int
    """The points."""
    var attributes: List[DracoAttributeConnectivity]
    """The connectivity of each attribute with seams."""

    def __init__(out self, var table: DracoCornerTable):
        """Keep a table, with no points yet.

        Args:
            table: The corner table of the mesh.
        """
        self.table = table^
        self.faces = List[Int]()
        self.points = 0
        self.attributes = List[DracoAttributeConnectivity]()


struct _Split(Copyable, Movable):
    """A topology split: an `S` symbol that joins an earlier boundary."""

    var split_symbol: Int
    var source_symbol: Int
    var source_edge: Int

    def __init__(out self, split_symbol: Int, source_symbol: Int):
        self.split_symbol = split_symbol
        self.source_symbol = source_symbol
        self.source_edge = 0


struct _Traversal(Movable):
    """The standard and the valence traversal decoders."""

    var kind: DracoTraversal
    var symbols: DracoBuffer
    var start_faces: RAnsBitDecoder
    var seams: List[RAnsBitDecoder]
    var valences: List[Int]
    var last_symbol: Int
    var context: Int
    var context_symbols: List[List[Int]]
    var context_left: List[Int]

    def __init__(out self, kind: DracoTraversal, var symbols: DracoBuffer):
        self.kind = kind
        self.symbols = symbols^
        self.start_faces = RAnsBitDecoder()
        self.seams = List[RAnsBitDecoder]()
        self.valences = List[Int]()
        self.last_symbol = NONE
        self.context = NONE
        self.context_symbols = List[List[Int]]()
        self.context_left = List[Int]()

    def start(
        mut self,
        mut buffer: DracoBuffer,
        attribute_data: Int,
        vertices: Int,
        faces: Int,
    ) raises:
        """Read the streams that follow the split events."""
        if self.kind == DRACO_STANDARD_TRAVERSAL:
            self.symbols = buffer.copy()
            var size = self.symbols.start_bits(True)
            buffer.pos = self.symbols.bit_start
            buffer.advance(size)
        self.start_faces.start(buffer)
        for _ in range(attribute_data):
            var seam = RAnsBitDecoder()
            seam.start(buffer)
            self.seams.append(seam^)
        if self.kind == DRACO_STANDARD_TRAVERSAL:
            return
        self.valences = List[Int](length=vertices, fill=0)
        for _ in range(6):  # pragma: no branch
            var count = buffer.varint32()
            draco_require(count <= faces, "a valence context is too long")
            self.context_symbols.append(decode_symbols(buffer, count, 1))
            self.context_left.append(count)

    def symbol(mut self) raises -> Int:
        """Read the next symbol, as its bit pattern."""
        if self.kind == DRACO_STANDARD_TRAVERSAL:
            var symbol = self.symbols.bits(1)
            if symbol == _C:
                return symbol
            return symbol | (self.symbols.bits(2) << 1)
        if self.context == NONE:
            self.last_symbol = _E
            return _E
        self.context_left[self.context] -= 1
        var left = self.context_left[self.context]
        if left < 0:
            return _INVALID_SYMBOL
        var id = self.context_symbols[self.context][left]
        if id > 4:
            return _INVALID_SYMBOL
        var patterns: List[Int] = [_C, _S, _L, _R, _E]
        self.last_symbol = patterns[id]
        return self.last_symbol

    def reached(mut self, corner: Int, table: DracoCornerTable) raises:
        """Count the valences at a new active corner."""
        if self.kind == DRACO_STANDARD_TRAVERSAL:
            return
        var next = table.next(corner)
        var previous = table.previous(corner)
        var at_corner = 0
        var at_next = 1
        var at_previous = 1
        if self.last_symbol == _R:
            at_corner = 1
            at_previous = 2
        elif self.last_symbol == _L:
            at_corner = 1
            at_next = 2
        elif self.last_symbol == _E:
            at_corner = 2
            at_next = 2
            at_previous = 2
        self._add(table.vertex(corner), at_corner)
        self._add(table.vertex(next), at_next)
        self._add(table.vertex(previous), at_previous)
        var valence = self.valences[table.vertex(next)]
        self.context = min(max(valence, 2), 7) - 2

    def _add(mut self, vertex: Int, count: Int) raises:
        draco_require(
            vertex >= 0 and vertex < len(self.valences),
            "a valence names a vertex that does not exist",
        )
        self.valences[vertex] += count

    def merge(mut self, target: Int, source: Int) raises:
        """Add the valence of a merged vertex to the one it joins."""
        if self.kind == DRACO_VALENCE_TRAVERSAL:
            self._add(source, 0)
            self._add(target, self.valences[source])


struct _Edgebreaker(Movable):
    """The state of `MeshEdgebreakerDecoderImpl` while it decodes."""

    var table: DracoCornerTable
    var splits: List[_Split]
    var holes: List[Bool]
    var traversal: _Traversal
    var attribute_data: Int

    def __init__(
        out self,
        faces: Int,
        vertices: Int,
        kind: DracoTraversal,
        attribute_data: Int,
    ):
        self.table = DracoCornerTable(faces)
        self.splits = List[_Split]()
        self.holes = List[Bool](length=vertices, fill=True)
        self.traversal = _Traversal(kind, DracoBuffer(List[UInt8]()))
        self.attribute_data = attribute_data

    def read_splits(mut self, mut buffer: DracoBuffer) raises:
        """Draco's `DecodeHoleAndTopologySplitEvents`, for bitstream 2.2."""
        var count = buffer.varint32()
        if count == 0:
            return
        draco_require(
            count <= self.table.faces(), "there are too many topology splits"
        )
        var last = 0
        for _ in range(count):  # pragma: no branch
            var source = (buffer.varint32() + last) & 0xFFFFFFFF
            var delta = buffer.varint32()
            draco_require(delta <= source, "a topology split is not valid")
            self.splits.append(_Split(source - delta, source))
            last = source
        _ = buffer.start_bits(False)
        for i in range(count):  # pragma: no branch
            self.splits[i].source_edge = buffer.bits(1)
        buffer.end_bits()

    def split_at(mut self, symbol: Int) -> Tuple[Bool, Int, Int]:
        """Draco's `IsTopologySplit`: the next split whose source is
        `symbol`, as (found, edge, split symbol)."""
        if len(self.splits) == 0:
            return (False, 0, 0)
        var last = self.splits[len(self.splits) - 1].copy()
        if last.source_symbol > symbol:
            return (True, 0, NONE)
        if last.source_symbol != symbol:
            return (False, 0, 0)
        _ = self.splits.pop()
        return (True, last.source_edge, last.split_symbol)

    def connect(mut self, symbols: Int) raises -> Int:
        """Draco's `DecodeConnectivity(num_symbols)`.

        Returns:
            The vertices of the connectivity.
        """
        var active = List[Int]()
        var split_corners = Dict[Int, Int]()
        var invalid = List[Int]()
        var remove_invalid = self.attribute_data == 0
        var max_vertices = len(self.holes)
        var faces = 0
        for symbol_id in range(symbols):
            var corner = 3 * faces
            faces += 1
            var check_split = False
            var symbol = self.traversal.symbol()
            if symbol == _C:
                draco_require(len(active) > 0, "a C symbol has no active edge")
                var corner_a = active[len(active) - 1]
                var vertex_x = self.table.vertex(self.table.next(corner_a))
                var corner_b = self.table.next(self.table.left_most(vertex_x))
                draco_require(
                    corner_a != corner_b
                    and self.table.opposite(corner_a) == NONE
                    and self.table.opposite(corner_b) == NONE,
                    "a C symbol does not close a gap",
                )
                self.table.set_opposites(corner_a, corner + 1)
                self.table.set_opposites(corner_b, corner + 2)
                var a_previous = self.table.vertex(
                    self.table.previous(corner_a)
                )
                var b_next = self.table.vertex(self.table.next(corner_b))
                draco_require(
                    vertex_x != a_previous and vertex_x != b_next,
                    "a C symbol makes a degenerate face",
                )
                self.table.corner_to_vertex[corner] = vertex_x
                self.table.corner_to_vertex[corner + 1] = b_next
                self.table.corner_to_vertex[corner + 2] = a_previous
                self.table.set_left_most(a_previous, corner + 2)
                self.holes[vertex_x] = False
                active[len(active) - 1] = corner
            elif symbol == _R or symbol == _L:
                draco_require(
                    len(active) > 0, "an R or L symbol has no active edge"
                )
                var corner_a = active[len(active) - 1]
                draco_require(
                    self.table.opposite(corner_a) == NONE,
                    "an R or L symbol reuses an edge",
                )
                var opposite = corner + 1
                var corner_l = corner
                var corner_r = corner + 2
                if symbol == _R:
                    opposite = corner + 2
                    corner_l = corner + 1
                    corner_r = corner
                self.table.set_opposites(opposite, corner_a)
                var vertex = self.table.add_vertex()
                draco_require(
                    self.table.vertices() <= max_vertices,
                    "there are more vertices than declared",
                )
                self.table.corner_to_vertex[opposite] = vertex
                self.table.set_left_most(vertex, opposite)
                var vertex_r = self.table.vertex(self.table.previous(corner_a))
                self.table.corner_to_vertex[corner_r] = vertex_r
                self.table.set_left_most(vertex_r, corner_r)
                self.table.corner_to_vertex[corner_l] = self.table.vertex(
                    self.table.next(corner_a)
                )
                active[len(active) - 1] = corner
                check_split = True
            elif symbol == _S:
                draco_require(len(active) > 0, "an S symbol has no active edge")
                var corner_b = active.pop()
                if symbol_id in split_corners:
                    active.append(split_corners[symbol_id])
                draco_require(len(active) > 0, "an S symbol has no second edge")
                var corner_a = active[len(active) - 1]
                draco_require(
                    corner_a != corner_b
                    and self.table.opposite(corner_a) == NONE
                    and self.table.opposite(corner_b) == NONE,
                    "an S symbol does not join two gaps",
                )
                self.table.set_opposites(corner_a, corner + 2)
                self.table.set_opposites(corner_b, corner + 1)
                var vertex_p = self.table.vertex(self.table.previous(corner_a))
                self.table.corner_to_vertex[corner] = vertex_p
                self.table.corner_to_vertex[corner + 1] = self.table.vertex(
                    self.table.next(corner_a)
                )
                var b_previous = self.table.vertex(
                    self.table.previous(corner_b)
                )
                self.table.corner_to_vertex[corner + 2] = b_previous
                self.table.set_left_most(b_previous, corner + 2)
                var corner_n = self.table.next(corner_b)
                var vertex_n = self.table.vertex(corner_n)
                self.traversal.merge(vertex_p, vertex_n)
                self.table.set_left_most(
                    vertex_p, self.table.left_most(vertex_n)
                )
                var first = corner_n
                while corner_n != NONE:
                    self.table.corner_to_vertex[corner_n] = vertex_p
                    corner_n = self.table.swing_left(corner_n)
                    draco_require(corner_n != first, "an S symbol makes a ring")
                self.table.set_left_most(vertex_n, NONE)
                if remove_invalid:
                    invalid.append(vertex_n)
                active[len(active) - 1] = corner
            else:
                draco_require(
                    symbol == _E, "an Edgebreaker symbol is not valid"
                )
                var first = self.table.add_vertex()
                self.table.corner_to_vertex[corner] = first
                self.table.corner_to_vertex[
                    corner + 1
                ] = self.table.add_vertex()
                self.table.corner_to_vertex[
                    corner + 2
                ] = self.table.add_vertex()
                draco_require(
                    self.table.vertices() <= max_vertices,
                    "there are more vertices than declared",
                )
                self.table.set_left_most(first, corner)
                self.table.set_left_most(first + 1, corner + 1)
                self.table.set_left_most(first + 2, corner + 2)
                active.append(corner)
                check_split = True
            self.traversal.reached(active[len(active) - 1], self.table)
            if check_split:
                var encoder_symbol = symbols - symbol_id - 1
                while True:
                    var split = self.split_at(encoder_symbol)
                    if not split[0]:
                        break
                    draco_require(split[2] >= 0, "a split symbol is not valid")
                    var top = active[len(active) - 1]
                    var new_corner = self.table.previous(top)
                    if split[1] == 1:
                        new_corner = self.table.next(top)
                    split_corners[symbols - split[2] - 1] = new_corner
        return self._close(active^, faces, invalid^)

    def _close(
        mut self, var active: List[Int], var faces: Int, invalid: List[Int]
    ) raises -> Int:
        """Add the interior start faces and drop merged vertices."""
        while len(active) > 0:
            var corner = active.pop()
            if self.traversal.start_faces.bit():
                draco_require(
                    faces < self.table.faces(), "there are too many faces"
                )
                var vertex_n = self.table.vertex(self.table.next(corner))
                var corner_b = self.table.next(self.table.left_most(vertex_n))
                var vertex_x = self.table.vertex(self.table.next(corner_b))
                var corner_c = self.table.next(self.table.left_most(vertex_x))
                draco_require(
                    corner != corner_b
                    and corner != corner_c
                    and corner_b != corner_c
                    and self.table.opposite(corner) == NONE
                    and self.table.opposite(corner_b) == NONE
                    and self.table.opposite(corner_c) == NONE,
                    "a start face does not close a hole",
                )
                var vertex_p = self.table.vertex(self.table.next(corner_c))
                var new_corner = 3 * faces
                faces += 1
                self.table.set_opposites(new_corner, corner)
                self.table.set_opposites(new_corner + 1, corner_b)
                self.table.set_opposites(new_corner + 2, corner_c)
                self.table.corner_to_vertex[new_corner] = vertex_x
                self.table.corner_to_vertex[new_corner + 1] = vertex_p
                self.table.corner_to_vertex[new_corner + 2] = vertex_n
                for k in range(3):  # pragma: no branch
                    self.holes[self.table.vertex(new_corner + k)] = False
        draco_require(
            faces == self.table.faces(), "the faces are not as declared"
        )
        var vertices = self.table.vertices()
        for vertex in invalid:
            var source = vertices - 1
            while self.table.left_most(source) == NONE:
                vertices -= 1
                source = vertices - 1
            if source < vertex:
                continue
            var ring = self.table.corners_of(self.table.left_most(source))
            for corner in ring:  # pragma: no branch
                draco_require(
                    self.table.vertex(corner) == source,
                    "a vertex ring is not valid",
                )
                self.table.corner_to_vertex[corner] = vertex
            self.table.set_left_most(vertex, self.table.left_most(source))
            self.table.set_left_most(source, NONE)
            self.holes[vertex] = self.holes[source]
            self.holes[source] = False
            vertices -= 1
        return vertices

    def read_seams(mut self) raises -> List[List[Int]]:
        """Draco's `DecodeAttributeConnectivitiesOnFace` for every face.

        Returns:
            For each attribute data, its seam corners.
        """
        var seams = List[List[Int]]()
        for _ in range(self.attribute_data):
            seams.append(List[Int]())
        if self.attribute_data == 0:
            return seams^
        for face in range(self.table.faces()):  # pragma: no branch
            var first = 3 * face
            var corners: List[Int] = [
                first,
                self.table.next(first),
                self.table.previous(first),
            ]
            for corner in corners:  # pragma: no branch
                var opposite = self.table.opposite(corner)
                if opposite == NONE:
                    for i in range(self.attribute_data):  # pragma: no branch
                        seams[i].append(corner)
                    continue
                if opposite // 3 < face:
                    continue
                for i in range(self.attribute_data):  # pragma: no branch
                    if self.traversal.seams[i].bit():
                        seams[i].append(corner)
        return seams^


def attribute_connectivity(
    base: DracoCornerTable, seams: List[Int]
) raises -> DracoAttributeConnectivity:
    """Build the table of an attribute from the mesh's table and seams.

    Draco's `MeshAttributeCornerTable::InitEmpty`, `AddSeamEdge` and
    `RecomputeVertices` with no attribute.

    Args:
        base: The corner table of the mesh.
        seams: The corners that face a seam edge.

    Returns:
        The attribute's connectivity.

    Raises:
        Error: If a vertex ring does not end, which a bad file can cause.
    """
    var on_edge = List[Bool](length=base.corners(), fill=False)
    var on_seam = List[Bool](length=base.vertices(), fill=False)
    for corner in seams:
        on_edge[corner] = True
        on_seam[base.vertex(base.next(corner))] = True
        on_seam[base.vertex(base.previous(corner))] = True
        var opposite = base.opposite(corner)
        if opposite != NONE:
            on_edge[opposite] = True
            on_seam[base.vertex(base.next(opposite))] = True
            on_seam[base.vertex(base.previous(opposite))] = True
    var table = DracoCornerTable(base.faces())
    for corner in range(base.corners()):
        if not on_edge[corner]:
            table.opposites[corner] = base.opposites[corner]
    for vertex in range(base.vertices()):
        var c = base.vertex_corners[vertex]
        if c == NONE:
            continue
        var value = table.add_vertex()
        var first = c
        if on_seam[vertex]:
            var at = table.swing_left(first)
            while at != NONE:
                first = at
                at = table.swing_left(at)
                draco_require(at != c, "a seam ring does not end")
        table.corner_to_vertex[first] = value
        table.vertex_corners[value] = first
        var at = base.swing_right(first)
        while at != NONE and at != first:
            if on_edge[base.next(at)]:
                value = table.add_vertex()
                table.vertex_corners[value] = at
            table.corner_to_vertex[at] = value
            at = base.swing_right(at)
    return DracoAttributeConnectivity(table^, on_seam^)


def _assign_points(
    mut out: EdgebreakerConnectivity, holes: List[Bool], vertices: Int
) raises:
    """Draco's `AssignPointsToCorners`: split the vertices at seams into
    points, and give each corner its point."""
    var table = out.table.copy()
    if len(out.attributes) == 0:
        out.faces = table.corner_to_vertex.copy()
        out.points = vertices
        return
    var point_corners = 0
    var corner_points = List[Int](length=table.corners(), fill=0)
    for v in range(table.vertices()):
        var c = table.vertex_corners[v]
        if c == NONE:
            continue
        var first = c
        if not holes[v]:
            # There are attributes here. The loop always runs.
            for data in out.attributes:  # pragma: no branch
                if not data.on_seam[v]:
                    continue
                var vertex = data.table.vertex(c)
                var at = table.swing_right(c)
                var found = False
                while at != c:
                    draco_require(at != NONE, "a seam vertex is not closed")
                    if data.table.vertex(at) != vertex:
                        first = at
                        found = True
                        break
                    at = table.swing_right(at)
                if found:
                    break
        corner_points[first] = point_corners
        point_corners += 1
        var previous = first
        var at = table.swing_right(first)
        while at != NONE and at != first:
            var seam = False
            for data in out.attributes:  # pragma: no branch
                if data.table.vertex(at) != data.table.vertex(previous):
                    seam = True
                    break
            if seam:
                corner_points[at] = point_corners
                point_corners += 1
            else:
                corner_points[at] = corner_points[previous]
            previous = at
            at = table.swing_right(at)
    out.faces = corner_points^
    out.points = point_corners


def decode_edgebreaker(
    mut buffer: DracoBuffer, kind: DracoTraversal
) raises -> EdgebreakerConnectivity:
    """Read the Edgebreaker connectivity of a mesh.

    Draco's `MeshEdgebreakerDecoderImpl::DecodeConnectivity` for
    bitstream 2.2: the counts, the topology splits, the traversal
    streams, the symbols, the start faces and the attribute seams. The
    cursor ends where the attributes start.

    Args:
        buffer: The cursor, after the traversal byte.
        kind: The traversal that codes the symbols.

    Returns:
        The corner table, the point of each corner and the seams.

    Raises:
        Error: If the traversal is not known, or the data does not make
            a valid mesh.
    """
    draco_require(kind.is_valid(), "an Edgebreaker traversal is not known")
    var vertices = buffer.varint32()
    var faces = buffer.varint32()
    draco_require(faces <= 0xFFFFFFFF // 3, "there are too many faces")
    draco_require(vertices <= faces * 3, "there are too many vertices")
    var attribute_data = buffer.u8()
    var symbols = buffer.varint32()
    draco_require(symbols <= faces, "there are more symbols than faces")
    draco_require(faces <= symbols + symbols // 3, "there are too many faces")
    var split_symbols = buffer.varint32()
    draco_require(split_symbols <= symbols, "there are too many split symbols")
    var decoder = _Edgebreaker(
        faces, vertices + split_symbols, kind, attribute_data
    )
    decoder.read_splits(buffer)
    decoder.traversal.start(
        buffer, attribute_data, vertices + split_symbols, faces
    )
    var connected = decoder.connect(symbols)
    var seams = decoder.read_seams()
    var out = EdgebreakerConnectivity(decoder.table.copy())
    for i in range(attribute_data):
        out.attributes.append(attribute_connectivity(out.table, seams[i]))
    _assign_points(out, decoder.holes, connected)
    return out^


def traverse_depth_first(
    table: DracoCornerTable,
    faces: List[Int],
    mut data: DracoEncodingData,
) raises -> List[Int]:
    """Visit the vertices of a table depth first.

    Draco's `DepthFirstTraverser`, run from each face in turn by
    `MeshTraversalSequencer`.

    Args:
        table: The table to walk: the mesh's or an attribute's.
        faces: The point of each corner.
        data: The order of the values, filled as vertices are reached.

    Returns:
        The point of each stored value, in order.

    Raises:
        Error: If the table has a corner with no vertex.
    """
    var points = List[Int]()
    var face_done = List[Bool](length=table.faces(), fill=False)
    var vertex_done = List[Bool](length=table.vertices(), fill=False)
    var stack = List[Int]()
    for face in range(table.faces()):
        var start = 3 * face
        if face_done[face]:
            continue
        stack.clear()
        stack.append(start)
        var ends: List[Int] = [table.next(start), table.previous(start)]
        for corner in ends:  # pragma: no branch
            var vertex = table.vertex(corner)
            draco_require(vertex != NONE, "a corner has no vertex")
            if not vertex_done[vertex]:
                vertex_done[vertex] = True
                data.visit(vertex, corner, faces, points)
        while len(stack) > 0:
            # Draco also pops an invalid corner here, but only corners of
            # faces not yet visited are pushed.
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
                    data.visit(vertex, corner, faces, points)
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
    return points^


def traverse_prediction_degree(
    table: DracoCornerTable,
    faces: List[Int],
    mut data: DracoEncodingData,
) raises -> List[Int]:
    """Visit the vertices of a table, best predicted first.

    Draco's `MaxPredictionDegreeTraverser`: a face whose tip vertex is
    already predicted from more neighbors is visited first.

    Args:
        table: The mesh's table.
        faces: The point of each corner.
        data: The order of the values, filled as vertices are reached.

    Returns:
        The point of each stored value, in order.

    Raises:
        Error: If the table has a corner with no vertex.
    """
    var points = List[Int]()
    var face_done = List[Bool](length=table.faces(), fill=False)
    var vertex_done = List[Bool](length=table.vertices(), fill=False)
    var degree = List[Int](length=table.vertices(), fill=0)
    var stacks: List[List[Int]] = [List[Int](), List[Int](), List[Int]()]
    if table.vertices() == 0:
        return points^
    for face in range(table.faces()):  # pragma: no branch
        var start = 3 * face
        stacks[0].append(start)
        var best = 0
        var ends: List[Int] = [table.next(start), table.previous(start), start]
        for corner in ends:  # pragma: no branch
            var vertex = table.vertex(corner)
            draco_require(vertex != NONE, "a corner has no vertex")
            if not vertex_done[vertex]:
                vertex_done[vertex] = True
                data.visit(vertex, corner, faces, points)
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
                    data.visit(vertex, corner, faces, points)
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
    return points^


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
