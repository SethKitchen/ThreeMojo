# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The welded triangle mesh a sculptor changes, from three.js
`examples/jsm/misc/SculptorMesh.js`, itself adapted from SculptGL by
Stéphane Ginier (MIT; see THIRD-PARTY-NOTICES.md).

`SculptorMesh.init_from_geometry` welds a geometry's positions: two
positions nearer than a ten-millionth of the geometry's largest extent
become one vertex. It then builds what the tools need:

- each vertex's ring of neighbor vertices and ring of faces;
- which vertices lie on an open edge;
- each face's normal, box and center, and each vertex's normal: the mean
  of its faces' unnormalized normals, and that mean made unit for drawing;
- a loose octree of the faces, for the ray and the sphere queries.

The positions, normals and face data are `Float32`, as three.js keeps them
in typed arrays. The arithmetic between them is done in doubles, as
JavaScript does it, and each result is rounded when it is stored. So the
numbers match three.js's to the last bit where the operations match.

The lists keep spare room, as three.js's typed arrays do:
`re_allocate_arrays` grows them to twice what is needed, and shrinks them
when four times too large. `nb_vertices` and `nb_faces` say how much of
each list is in use.

**Where this differs.** An octree cell is an index into `cells`, not an
object; a pruned cell stays in the list, unused. A face is three corners;
three.js's fourth slot always held `TRI_INDEX`.
"""

from core.buffer_geometry import BufferGeometry, POSITION
from geometries.sculptor_utils import (
    MAX_FLAG,
    Point3,
    js_max,
    js_min,
    point_of,
)
from std.math import floor, inf, isfinite, sqrt

# A cell with more faces than this splits, unless it is this deep already.
comptime OCTREE_MAX_FACES = 100
comptime OCTREE_MAX_DEPTH = 8
# Two positions weld when nearer than this share of the largest extent.
comptime RELATIVE_WELD_TOLERANCE = 1e-7
# No cell, three.js's `null` leaf or parent.
comptime NO_CELL = -1


def _hash_position(x: Int, y: Int, z: Int) -> Int:
    """Return three.js's `hashPosition` of a weld cell: three rounds of
    `Math.imul` on the 32-bit patterns of the cell's coordinates."""
    var hash = UInt32(x & 0xFFFFFFFF) * UInt32(0x85EBCA6B)
    hash = (hash ^ (hash >> 13) ^ UInt32(y & 0xFFFFFFFF)) * UInt32(0xC2B2AE35)
    hash = (hash ^ (hash >> 16) ^ UInt32(z & 0xFFFFFFFF)) * UInt32(0x27D4EB2D)
    return Int(hash ^ (hash >> 15))


def _near_cell(grid: Float64, cell: Int) -> Int:
    """Return the neighbor cell nearer a grid position: the one below when
    it sits in the lower half of its cell."""
    return cell + (-1 if grid - Float64(cell) < 0.5 else 1)


def _resized_floats(values: List[Float32], required: Int) -> List[Float32]:
    """Return a list twice `required` long holding what fits of `values`,
    three.js's `_resizeArray`."""
    var resized = List[Float32](length=required * 2, fill=0)
    for i in range(min(len(values), len(resized))):  # pragma: no branch
        resized[i] = values[i]
    return resized^


def _resized_ints(values: List[Int], required: Int) -> List[Int]:
    """Return a list twice `required` long holding what fits of `values`,
    three.js's `_resizeArray`."""
    var resized = List[Int](length=required * 2, fill=0)
    for i in range(min(len(values), len(resized))):  # pragma: no branch
        resized[i] = values[i]
    return resized^


def _empty_box() -> List[Float64]:
    """Return an empty box: the lows at infinity, the highs below every
    number."""
    var far = inf[DType.float64]()
    return [far, far, far, -far, -far, -far]


def _reset_tag_flags(mut flags: List[Int], active_count: Int):
    """Set every tag to zero except a pending deletion's -1, three.js's
    `resetTagFlags`."""
    for i in range(len(flags)):  # pragma: no branch
        flags[i] = 0 if (i >= active_count or flags[i] >= 0) else flags[i]


@fieldwise_init
struct _Weld(Movable):
    """The welded positions, and which welded vertex each source position
    became."""

    var positions: List[Float32]
    var vertex_map: List[Int]


struct OctreeCell(Copyable, Movable):
    """A cell of the loose octree, three.js's `OctreeCell`.

    `aabb_split` is the box the cell owns: a face belongs to the cell its
    center falls in. `aabb_loose` bounds the faces the cell holds, which
    can reach outside it.
    """

    var parent: Int
    var depth: Int
    # None, or all eight children.
    var children: List[Int]
    # Six numbers each: the lows, then the highs.
    var aabb_loose: List[Float64]
    var aabb_split: List[Float64]
    # The faces of a leaf.
    var faces: List[Int]
    var queued_for_update: Bool

    def __init__(out self, parent: Int, depth: Int):
        """Create an empty cell with empty boxes.

        Args:
            parent: The parent cell, or `NO_CELL` for the root.
            depth: How deep the cell is; zero for the root.
        """
        self.parent = parent
        self.depth = depth
        self.children = List[Int]()
        self.aabb_loose = _empty_box()
        self.aabb_split = _empty_box()
        self.faces = List[Int]()
        self.queued_for_update = False


struct SculptorMesh(Movable):
    """A welded triangle mesh with its topology and its octree, three.js's
    `SculptorMesh`."""

    var nb_vertices: Int
    var nb_faces: Int
    # Three numbers per vertex: the position, the mean face normal, and
    # that normal made unit, which is what is drawn.
    var vertices: List[Float32]
    var normals: List[Float32]
    var render_normals: List[Float32]
    # Three vertices per face: the working copy, and the copy drawn.
    var faces: List[Int]
    var triangles: List[Int]
    var vert_ring_vert: List[List[Int]]
    var vert_ring_face: List[List[Int]]
    # One where a vertex has more neighbors than faces: an open edge.
    var vert_on_edge: List[Int]
    # Three numbers per face for the normal and the center, six for the box.
    var face_normals: List[Float32]
    var face_boxes: List[Float32]
    var face_centers: List[Float32]
    var face_pos_in_leaf: List[Int]
    var face_leaf: List[Int]
    var vert_tag_flags: List[Int]
    var vert_sculpt_flags: List[Int]
    var faces_tag_flags: List[Int]
    var cells: List[OctreeCell]
    var octree: Int
    var leaves_to_update: List[Int]
    var topology_version: Int
    var tag_flag: Int
    var sculpt_flag: Int
    # How many times `re_allocate_arrays` has replaced a list. three.js
    # sees this as a new typed array; the sculptor reads it to know the
    # geometry changed.
    var buffer_version: Int

    def __init__(out self):
        """Create an empty mesh; fill it with `init_from_geometry`."""
        self.nb_vertices = 0
        self.nb_faces = 0
        self.vertices = List[Float32]()
        self.normals = List[Float32]()
        self.render_normals = List[Float32]()
        self.faces = List[Int]()
        self.triangles = List[Int]()
        self.vert_ring_vert = List[List[Int]]()
        self.vert_ring_face = List[List[Int]]()
        self.vert_on_edge = List[Int]()
        self.face_normals = List[Float32]()
        self.face_boxes = List[Float32]()
        self.face_centers = List[Float32]()
        self.face_pos_in_leaf = List[Int]()
        self.face_leaf = List[Int]()
        self.vert_tag_flags = List[Int]()
        self.vert_sculpt_flags = List[Int]()
        self.faces_tag_flags = List[Int]()
        self.cells = List[OctreeCell]()
        self.octree = NO_CELL
        self.leaves_to_update = List[Int]()
        self.topology_version = 0
        self.tag_flag = 1
        self.sculpt_flag = 1
        self.buffer_version = 0

    # --- flags and counts ---------------------------------------------

    def next_tag_flag(mut self) -> Int:
        """Return a fresh tag, three.js's `nextTagFlag`. At `MAX_FLAG` the
        tags start again from one, and every tag but a pending deletion's
        -1 is cleared.

        Returns:
            The new tag.
        """
        if self.tag_flag >= MAX_FLAG:
            _reset_tag_flags(self.vert_tag_flags, self.nb_vertices)
            _reset_tag_flags(self.faces_tag_flags, self.nb_faces)
            self.tag_flag = 1
        else:
            self.tag_flag += 1
        return self.tag_flag

    def next_sculpt_flag(mut self) -> Int:
        """Return a fresh sculpt flag, three.js's `nextSculptFlag`.

        Returns:
            The new flag.
        """
        if self.sculpt_flag >= MAX_FLAG:
            for i in range(len(self.vert_sculpt_flags)):  # pragma: no branch
                self.vert_sculpt_flags[i] = 0
            self.sculpt_flag = 1
        else:
            self.sculpt_flag += 1
        return self.sculpt_flag

    def add_nb_vertice(mut self, nb: Int):
        """Change the vertex count, three.js's `addNbVertice`.

        Args:
            nb: How many vertices to add; negative to remove.
        """
        self.nb_vertices += nb

    def add_nb_face(mut self, nb: Int):
        """Change the face count and mark the topology changed, three.js's
        `addNbFace`.

        Args:
            nb: How many faces to add; negative to remove.
        """
        self.nb_faces += nb
        self.topology_version += 1

    def mark_topology_changed(mut self):
        """Mark the topology changed, three.js's `markTopologyChanged`."""
        self.topology_version += 1

    # --- building ------------------------------------------------------

    def init_from_geometry(mut self, geometry: BufferGeometry) raises:
        """Weld a geometry's triangles and build the topology and the
        octree, three.js's `initFromGeometry`.

        Args:
            geometry: The geometry: positions of three numbers, indexed or
                not, three per triangle.

        Raises:
            Error: If the positions are missing, empty or not three numbers
                each; the triangle list is empty or not whole; an index is
                out of range; a position is not finite; welding makes a
                triangle with a repeated vertex; or a triangle has no area,
                or a normal too large, in `Float32`.
        """
        self.tag_flag = 1
        self.sculpt_flag = 1
        if not geometry.has_attribute(String(POSITION)):
            raise Error(
                "SculptorMesh: A non-empty position attribute with itemSize"
                " 3 is required."
            )
        ref position = geometry.attribute_view(String(POSITION))
        if position.item_size != 3 or position.count() == 0:
            raise Error(
                "SculptorMesh: A non-empty position attribute with itemSize"
                " 3 is required."
            )
        var source_count = position.count()
        var element_count = (
            len(geometry.index) if geometry.is_indexed() else source_count
        )
        if element_count % 3 != 0:
            raise Error(
                "SculptorMesh: The geometry must contain triangles with a"
                " complete, non-empty element list."
            )
        var referenced = List[Int](
            length=source_count, fill=0 if geometry.is_indexed() else 1
        )
        var elements = List[Int](capacity=element_count)
        for i in range(element_count):  # pragma: no branch
            var source_index = geometry.index[i] if geometry.is_indexed() else i
            if source_index < 0 or source_index >= source_count:
                raise Error(
                    "SculptorMesh: Triangle indices must reference valid"
                    " positions."
                )
            elements.append(source_index)
            referenced[source_index] = 1
        var source = List[Float32](length=source_count * 3, fill=0)
        var bounds = _empty_box()
        for i in range(source_count):  # pragma: no branch
            if referenced[i] == 0:
                continue
            var p = position.vector3(i)
            if not (isfinite(p.x) and isfinite(p.y) and isfinite(p.z)):
                raise Error("SculptorMesh: Position values must be finite.")
            source[i * 3] = p.x
            source[i * 3 + 1] = p.y
            source[i * 3 + 2] = p.z
            bounds[0] = min(bounds[0], Float64(p.x))
            bounds[1] = min(bounds[1], Float64(p.y))
            bounds[2] = min(bounds[2], Float64(p.z))
            bounds[3] = max(bounds[3], Float64(p.x))
            bounds[4] = max(bounds[4], Float64(p.y))
            bounds[5] = max(bounds[5], Float64(p.z))
        var weld = _weld_positions(source, referenced, bounds)
        var triangle_count = element_count // 3
        var vertex_count = len(weld.positions) // 3
        self.faces = List[Int](capacity=element_count)
        for i in range(element_count):  # pragma: no branch
            self.faces.append(weld.vertex_map[elements[i]])
        _check_triangles(self.faces, weld.positions)
        self.triangles = self.faces.copy()
        self.nb_vertices = vertex_count
        self.nb_faces = triangle_count
        self.topology_version = 0
        self.leaves_to_update = List[Int]()
        self.vertices = weld.positions.copy()
        self.normals = List[Float32](length=vertex_count * 3, fill=0)
        self.render_normals = List[Float32](length=vertex_count * 3, fill=0)
        self.vert_on_edge = List[Int](length=vertex_count, fill=0)
        self.vert_tag_flags = List[Int](length=vertex_count, fill=0)
        self.vert_sculpt_flags = List[Int](length=vertex_count, fill=0)
        self.faces_tag_flags = List[Int](length=triangle_count, fill=0)
        self.face_boxes = List[Float32](length=triangle_count * 6, fill=0)
        self.face_normals = List[Float32](length=triangle_count * 3, fill=0)
        self.face_centers = List[Float32](length=triangle_count * 3, fill=0)
        self.face_pos_in_leaf = List[Int](length=triangle_count, fill=0)
        self.face_leaf = List[Int](length=triangle_count, fill=NO_CELL)
        self._init_topology()
        var all_faces = List[Int](capacity=triangle_count)
        for i in range(triangle_count):  # pragma: no branch
            all_faces.append(i)
        var all_vertices = List[Int](capacity=vertex_count)
        for i in range(vertex_count):  # pragma: no branch
            all_vertices.append(i)
        self._update_faces_aabb_and_normal(all_faces)
        self._update_vertices_normal(all_vertices)
        self._compute_octree()

    def _init_topology(mut self):
        """Build every vertex's rings and its open-edge mark, three.js's
        `_initTopology`."""
        self.vert_ring_vert = List[List[Int]](capacity=self.nb_vertices)
        self.vert_ring_face = List[List[Int]](capacity=self.nb_vertices)
        for _ in range(self.nb_vertices):  # pragma: no branch
            self.vert_ring_vert.append(List[Int]())
            self.vert_ring_face.append(List[Int]())
        for i in range(self.nb_faces):  # pragma: no branch
            self.vert_ring_face[self.triangles[i * 3]].append(i)
            self.vert_ring_face[self.triangles[i * 3 + 1]].append(i)
            self.vert_ring_face[self.triangles[i * 3 + 2]].append(i)
        for i in range(self.nb_vertices):  # pragma: no branch
            self.compute_ring_vertices(i)
            self.vert_on_edge[i] = (
                1 if len(self.vert_ring_face[i])
                != len(self.vert_ring_vert[i]) else 0
            )

    def compute_ring_vertices(mut self, vertex: Int):
        """Rebuild a vertex's ring of neighbors from its faces, in the
        order its faces name them, three.js's `_computeRingVertices`.

        Args:
            vertex: The vertex.
        """
        var tag = self.next_tag_flag()
        var ring = List[Int]()
        for j in range(len(self.vert_ring_face[vertex])):
            var face = self.vert_ring_face[vertex][j]
            var first = self.faces[face * 3]
            var second = self.faces[face * 3 + 1]
            var third = self.faces[face * 3 + 2]
            var one = third if first == vertex else first
            var two = third if (first != vertex and second == vertex) else second
            if self.vert_tag_flags[one] != tag:
                self.vert_tag_flags[one] = tag
                ring.append(one)
            if self.vert_tag_flags[two] != tag:
                self.vert_tag_flags[two] = tag
                ring.append(two)
        self.vert_ring_vert[vertex] = ring^

    # --- geometry updates ----------------------------------------------

    def update_geometry(mut self, faces: List[Int], vertices: List[Int]):
        """Refresh the faces' normals and boxes, the vertices' normals,
        and the faces' places in the octree, three.js's `_updateGeometry`.

        Args:
            faces: The faces that moved.
            vertices: The vertices whose normals to refresh.
        """
        self._update_faces_aabb_and_normal(faces)
        self._update_vertices_normal(vertices)
        self._update_octree_add(self._update_octree_remove(faces))

    def _update_faces_aabb_and_normal(mut self, faces: List[Int]):
        """Compute each face's normal, box and center, three.js's
        `_updateFacesAabbAndNormal`."""
        for face in faces:
            var v1 = point_of(self.vertices, self.faces[face * 3])
            var v2 = point_of(self.vertices, self.faces[face * 3 + 1])
            var v3 = point_of(self.vertices, self.faces[face * 3 + 2])
            var ax = v2.x - v1.x
            var ay = v2.y - v1.y
            var az = v2.z - v1.z
            var bx = v3.x - v1.x
            var by = v3.y - v1.y
            var bz = v3.z - v1.z
            self.face_normals[face * 3] = Float32(ay * bz - az * by)
            self.face_normals[face * 3 + 1] = Float32(az * bx - ax * bz)
            self.face_normals[face * 3 + 2] = Float32(ax * by - ay * bx)
            var xmin = min(min(v1.x, v2.x), v3.x)
            var ymin = min(min(v1.y, v2.y), v3.y)
            var zmin = min(min(v1.z, v2.z), v3.z)
            var xmax = max(max(v1.x, v2.x), v3.x)
            var ymax = max(max(v1.y, v2.y), v3.y)
            var zmax = max(max(v1.z, v2.z), v3.z)
            var box = face * 6
            self.face_boxes[box] = Float32(xmin)
            self.face_boxes[box + 1] = Float32(ymin)
            self.face_boxes[box + 2] = Float32(zmin)
            self.face_boxes[box + 3] = Float32(xmax)
            self.face_boxes[box + 4] = Float32(ymax)
            self.face_boxes[box + 5] = Float32(zmax)
            self.face_centers[face * 3] = Float32((xmin + xmax) * 0.5)
            self.face_centers[face * 3 + 1] = Float32((ymin + ymax) * 0.5)
            self.face_centers[face * 3 + 2] = Float32((zmin + zmax) * 0.5)

    def _update_vertices_normal(mut self, vertices: List[Int]):
        """Set each vertex's normal to the mean of its faces' normals, and
        its drawn normal to that made unit, three.js's
        `_updateVerticesNormal`."""
        for vertex in vertices:
            var nx = 0.0
            var ny = 0.0
            var nz = 0.0
            for face in self.vert_ring_face[vertex]:
                nx += Float64(self.face_normals[face * 3])
                ny += Float64(self.face_normals[face * 3 + 1])
                nz += Float64(self.face_normals[face * 3 + 2])
            var count = len(self.vert_ring_face[vertex])
            var inverse_count = 1.0 / Float64(count) if count > 0 else 0.0
            nx *= inverse_count
            ny *= inverse_count
            nz *= inverse_count
            self.normals[vertex * 3] = Float32(nx)
            self.normals[vertex * 3 + 1] = Float32(ny)
            self.normals[vertex * 3 + 2] = Float32(nz)
            var length = sqrt(nx * nx + ny * ny + nz * nz)
            var inverse_length = 1.0 / length if length > 0 else 0.0
            self.render_normals[vertex * 3] = Float32(nx * inverse_length)
            self.render_normals[vertex * 3 + 1] = Float32(ny * inverse_length)
            self.render_normals[vertex * 3 + 2] = Float32(nz * inverse_length)

    # --- the octree ------------------------------------------------------

    def _new_cell(mut self, parent: Int) -> Int:
        """Add a cell below `parent` and return its index."""
        var depth = 0 if parent == NO_CELL else self.cells[parent].depth + 1
        self.cells.append(OctreeCell(parent, depth))
        return len(self.cells) - 1

    def _queue_leaf(mut self, leaf: Int):
        """Put a leaf on the list `balance_octree` visits, once, three.js's
        `queueLeaf`."""
        if self.cells[leaf].queued_for_update:
            return
        self.cells[leaf].queued_for_update = True
        self.leaves_to_update.append(leaf)

    def _compute_octree(mut self):
        """Build the octree afresh around every vertex, three.js's
        `_computeOctree`."""
        var lows: List[Float64] = [
            inf[DType.float64](),
            inf[DType.float64](),
            inf[DType.float64](),
        ]
        var highs: List[Float64] = [
            -inf[DType.float64](),
            -inf[DType.float64](),
            -inf[DType.float64](),
        ]
        for i in range(self.nb_vertices):  # pragma: no branch
            for axis in range(3):  # pragma: no branch
                var value = Float64(self.vertices[i * 3 + axis])
                lows[axis] = min(lows[axis], value)
                highs[axis] = max(highs[axis], value)
        var dx = highs[0] - lows[0]
        var dy = highs[1] - lows[1]
        var dz = highs[2] - lows[2]
        var thickness = sqrt(dx * dx + dy * dy + dz * dz) * 0.2
        var spans = [dx, dy, dz]
        for axis in range(3):  # pragma: no branch
            if spans[axis] == 0:
                lows[axis] -= thickness
                highs[axis] += thickness
        self.cells = List[OctreeCell]()
        var root = self._new_cell(NO_CELL)
        for i in range(self.nb_faces):  # pragma: no branch
            self.cells[root].faces.append(i)
        self.cells[root].aabb_loose = [
            lows[0],
            lows[1],
            lows[2],
            highs[0],
            highs[1],
            highs[2],
        ]
        self.cells[root].aabb_split = [
            lows[0] - dx * 0.3,
            lows[1] - dy * 0.3,
            lows[2] - dz * 0.3,
            highs[0] + dx * 0.3,
            highs[1] + dy * 0.3,
            highs[2] + dz * 0.3,
        ]
        self.octree = root
        self._build(root)
        # The old cells are gone, and with them the queue.
        self.leaves_to_update = List[Int]()

    def _build(mut self, start: Int):
        """Split a cell until each leaf holds at most `OCTREE_MAX_FACES`
        faces or is `OCTREE_MAX_DEPTH` deep, three.js's `build`."""
        var stack: List[Int] = [start]
        var leaves = List[Int]()
        while len(stack) > 0:
            var cell = stack.pop()
            var count = len(self.cells[cell].faces)
            if (
                count > OCTREE_MAX_FACES
                and self.cells[cell].depth < OCTREE_MAX_DEPTH
            ):
                self._construct_children(cell)
                for i in range(8):  # pragma: no branch
                    stack.append(self.cells[cell].children[i])
            elif count > 0:
                leaves.append(cell)
        for leaf in leaves:  # pragma: no branch
            self._construct_leaf(leaf)

    def _construct_leaf(mut self, cell: Int):
        """Point each of a leaf's faces at it and grow its loose box around
        them, three.js's `_constructLeaf`."""
        var box = _empty_box()
        for i in range(len(self.cells[cell].faces)):  # pragma: no branch
            var face = self.cells[cell].faces[i]
            self.face_leaf[face] = cell
            self.face_pos_in_leaf[face] = i
            for axis in range(3):  # pragma: no branch
                box[axis] = min(
                    box[axis], Float64(self.face_boxes[face * 6 + axis])
                )
                box[axis + 3] = max(
                    box[axis + 3], Float64(self.face_boxes[face * 6 + axis + 3])
                )
        self._expand_aabb_loose(cell, box)

    def _construct_children(mut self, cell: Int):
        """Give a cell eight children and share its faces among them by
        center, three.js's `_constructChildren`."""
        var split = self.cells[cell].aabb_split.copy()
        var xcen = (split[3] + split[0]) * 0.5
        var ycen = (split[4] + split[1]) * 0.5
        var zcen = (split[5] + split[2]) * 0.5
        var children = List[Int]()
        for _ in range(8):  # pragma: no branch
            children.append(self._new_cell(cell))
        for face in self.cells[cell].faces.copy():  # pragma: no branch
            var cx = Float64(self.face_centers[face * 3])
            var cy = Float64(self.face_centers[face * 3 + 1])
            var cz = Float64(self.face_centers[face * 3 + 2])
            var high_z = cz > zcen
            var slot: Int
            if cx > xcen:
                if cy > ycen:
                    slot = 6 if high_z else 5
                else:
                    slot = 2 if high_z else 1
            elif cy > ycen:
                slot = 7 if high_z else 4
            else:
                slot = 3 if high_z else 0
            self.cells[children[slot]].faces.append(face)
        var x0 = split[0]
        var y0 = split[1]
        var z0 = split[2]
        var x1 = split[3]
        var y1 = split[4]
        var z1 = split[5]
        self.cells[children[0]].aabb_split = [x0, y0, z0, xcen, ycen, zcen]
        self.cells[children[1]].aabb_split = [xcen, y0, z0, x1, ycen, zcen]
        self.cells[children[2]].aabb_split = [xcen, y0, zcen, x1, ycen, z1]
        self.cells[children[3]].aabb_split = [x0, y0, zcen, xcen, ycen, z1]
        self.cells[children[4]].aabb_split = [x0, ycen, z0, xcen, y1, zcen]
        self.cells[children[5]].aabb_split = [xcen, ycen, z0, x1, y1, zcen]
        self.cells[children[6]].aabb_split = [xcen, ycen, zcen, x1, y1, z1]
        self.cells[children[7]].aabb_split = [x0, ycen, zcen, xcen, y1, z1]
        self.cells[cell].children = children^
        self.cells[cell].faces = List[Int]()

    def _expand_aabb_loose(mut self, cell: Int, box: List[Float64]):
        """Grow a cell's loose box, and its parents' while they grow too,
        three.js's `_expandAabbLoose`."""
        var parent = cell
        while parent != NO_CELL:
            var grown = 0
            for axis in range(3):  # pragma: no branch
                var low = self.cells[parent].aabb_loose[axis]
                var high = self.cells[parent].aabb_loose[axis + 3]
                grown += Int(box[axis] < low) + Int(box[axis + 3] > high)
                self.cells[parent].aabb_loose[axis] = min(low, box[axis])
                self.cells[parent].aabb_loose[axis + 3] = max(
                    high, box[axis + 3]
                )
            parent = self.cells[parent].parent if grown > 0 else NO_CELL

    def _split_holds(self, cell: Int, x: Float64, y: Float64, z: Float64) -> Bool:
        """Return True if a center falls in a cell's split box: above each
        low, at or below each high."""
        ref s = self.cells[cell].aabb_split
        return (
            x > s[0] and y > s[1] and z > s[2] and x <= s[3] and y <= s[4]
            and z <= s[5]
        )

    def _face_box(self, face: Int) -> List[Float64]:
        """Return a face's box as six doubles."""
        var box = List[Float64](capacity=6)
        for i in range(6):  # pragma: no branch
            box.append(Float64(self.face_boxes[face * 6 + i]))
        return box^

    def _update_octree_remove(mut self, faces: List[Int]) -> List[Int]:
        """Take out of their leaves the faces whose centers left them, and
        grow the leaves of the rest, three.js's `_updateOctreeRemove`.

        Returns:
            The faces taken out.
        """
        var to_move = List[Int]()
        for face in faces:
            var leaf = self.face_leaf[face]
            var inside = self._split_holds(
                leaf,
                Float64(self.face_centers[face * 3]),
                Float64(self.face_centers[face * 3 + 1]),
                Float64(self.face_centers[face * 3 + 2]),
            )
            if inside:
                self._expand_aabb_loose(leaf, self._face_box(face))
                continue
            to_move.append(face)
            var position = self.face_pos_in_leaf[face]
            var last = self.cells[leaf].faces[len(self.cells[leaf].faces) - 1]
            self.cells[leaf].faces[position] = last
            self.face_pos_in_leaf[last] = position
            _ = self.cells[leaf].faces.pop()
            self._queue_leaf(leaf)
        return to_move^

    def _update_octree_add(mut self, faces: List[Int]):
        """Put faces into the leaves their centers fall in, or build the
        octree afresh if one falls outside it, three.js's
        `_updateOctreeAdd`."""
        for face in faces:
            var leaf = self._add_face(face)
            if leaf == NO_CELL:
                self._compute_octree()
                return
            self.face_leaf[face] = leaf
            self.face_pos_in_leaf[face] = len(self.cells[leaf].faces) - 1
            self._queue_leaf(leaf)

    def _add_face(mut self, face: Int) -> Int:
        """Put a face into the leaf its center falls in, growing the loose
        boxes on the way down, three.js's `addFace`.

        Returns:
            The leaf, or `NO_CELL` if the center is outside the root.
        """
        var box = self._face_box(face)
        var cx = Float64(self.face_centers[face * 3])
        var cy = Float64(self.face_centers[face * 3 + 1])
        var cz = Float64(self.face_centers[face * 3 + 2])
        var stack: List[Int] = [self.octree]
        while len(stack) > 0:
            var cell = stack.pop()
            if not self._split_holds(cell, cx, cy, cz):
                continue
            for axis in range(3):  # pragma: no branch
                self.cells[cell].aabb_loose[axis] = min(
                    self.cells[cell].aabb_loose[axis], box[axis]
                )
                self.cells[cell].aabb_loose[axis + 3] = max(
                    self.cells[cell].aabb_loose[axis + 3], box[axis + 3]
                )
            if len(self.cells[cell].children) == 8:
                for i in range(8):  # pragma: no branch
                    stack.append(self.cells[cell].children[i])
                continue
            self.cells[cell].faces.append(face)
            return cell
        return NO_CELL

    def _prune_if_possible(mut self, leaf: Int):
        """Drop the children of each parent up the tree whose children all
        are empty leaves, three.js's `pruneIfPossible`."""
        var cell = leaf
        while self.cells[cell].parent != NO_CELL:
            var parent = self.cells[cell].parent
            if len(self.cells[parent].children) == 0:
                return
            var busy = 0
            for child in self.cells[parent].children:  # pragma: no branch
                busy += Int(
                    len(self.cells[child].faces) > 0
                    or len(self.cells[child].children) == 8
                )
            if busy > 0:
                return
            self.cells[parent].children = List[Int]()
            cell = parent

    def balance_octree(mut self):
        """Split the queued leaves that grew too full, and prune the ones
        left empty, three.js's `balanceOctree`."""
        var leaves = self.leaves_to_update.copy()
        for leaf in leaves:
            self.cells[leaf].queued_for_update = False
            var count = len(self.cells[leaf].faces)
            if count == 0:
                self._prune_if_possible(leaf)
            elif (
                count > OCTREE_MAX_FACES
                and self.cells[leaf].depth < OCTREE_MAX_DEPTH
            ):
                self._build(leaf)
        self.leaves_to_update = List[Int]()

    # --- queries ---------------------------------------------------------

    def intersect_ray(self, near: Point3, direction: Point3) -> List[Int]:
        """Return the faces in the leaves whose loose boxes a ray meets,
        three.js's `intersectRay`.

        Args:
            near: Where the ray starts.
            direction: Which way it goes.

        Returns:
            The faces, leaf by leaf in the octree's order.
        """
        var irx = 1.0 / direction.x
        var iry = 1.0 / direction.y
        var irz = 1.0 / direction.z
        var collected = List[Int]()
        var stack: List[Int] = [self.octree]
        while len(stack) > 0:
            var cell = stack.pop()
            ref loose = self.cells[cell].aabb_loose
            var t1 = (loose[0] - near.x) * irx
            var t2 = (loose[3] - near.x) * irx
            var t3 = (loose[1] - near.y) * iry
            var t4 = (loose[4] - near.y) * iry
            var t5 = (loose[2] - near.z) * irz
            var t6 = (loose[5] - near.z) * irz
            var tmin = js_max(
                js_max(js_min(t1, t2), js_min(t3, t4)), js_min(t5, t6)
            )
            var tmax = js_min(
                js_min(js_max(t1, t2), js_max(t3, t4)), js_max(t5, t6)
            )
            if tmax < 0 or tmin > tmax:
                continue
            self._collect(cell, stack, collected)
        return collected^

    def _collect(self, cell: Int, mut stack: List[Int], mut collected: List[Int]):
        """Push a cell's children, or collect a leaf's faces."""
        if len(self.cells[cell].children) == 8:
            for i in range(8):  # pragma: no branch
                stack.append(self.cells[cell].children[i])
            return
        for face in self.cells[cell].faces:
            collected.append(face)

    def intersect_sphere(
        mut self, center: Point3, radius_sq: Float64, collect_leaves: Bool
    ) -> List[Int]:
        """Return the faces in the leaves whose loose boxes reach a sphere,
        three.js's `intersectSphere`.

        Args:
            center: The sphere's center.
            radius_sq: Its squared radius.
            collect_leaves: Whether to queue the leaves met for
                `balance_octree`.

        Returns:
            The faces, leaf by leaf in the octree's order.
        """
        var collected = List[Int]()
        var stack: List[Int] = [self.octree]
        while len(stack) > 0:
            var cell = stack.pop()
            ref loose = self.cells[cell].aabb_loose
            var dx = _outside(loose[0], loose[3], center.x)
            var dy = _outside(loose[1], loose[4], center.y)
            var dz = _outside(loose[2], loose[5], center.z)
            if dx * dx + dy * dy + dz * dz > radius_sq:
                continue
            if collect_leaves and len(self.cells[cell].children) != 8:
                self._queue_leaf(cell)
            self._collect(cell, stack, collected)
        return collected^

    def get_vertices_from_faces(mut self, faces: List[Int]) -> List[Int]:
        """Return the faces' vertices, each once, in the order met,
        three.js's `getVerticesFromFaces`.

        Args:
            faces: The faces.

        Returns:
            The vertices.
        """
        var tag = self.next_tag_flag()
        var vertices = List[Int]()
        for face in faces:
            for corner in range(3):  # pragma: no branch
                var vertex = self.faces[face * 3 + corner]
                if self.vert_tag_flags[vertex] != tag:
                    self.vert_tag_flags[vertex] = tag
                    vertices.append(vertex)
        return vertices^

    def get_faces_from_vertices(mut self, vertices: List[Int]) -> List[Int]:
        """Return the faces around the vertices, each once, in the order
        met, three.js's `getFacesFromVertices`.

        Args:
            vertices: The vertices.

        Returns:
            The faces.
        """
        var tag = self.next_tag_flag()
        var faces = List[Int]()
        for vertex in vertices:
            self._add_ring_faces(vertex, tag, faces)
        return faces^

    def expands_faces(mut self, faces: List[Int], rings: Int) -> List[Int]:
        """Return the faces and the faces around them, `rings` times over,
        three.js's `expandsFaces`.

        Args:
            faces: The faces to start from.
            rings: How many rings of neighbors to add.

        Returns:
            The faces first, then each ring in the order met.
        """
        var tag = self.next_tag_flag()
        var expanded = faces.copy()
        for face in faces:
            self.faces_tag_flags[face] = tag
        var begin = 0
        for _ in range(rings):  # pragma: no branch
            var end = len(expanded)
            for i in range(begin, end):
                for corner in range(3):  # pragma: no branch
                    self._add_ring_faces(
                        self.faces[expanded[i] * 3 + corner], tag, expanded
                    )
            begin = end
        return expanded^

    def _add_ring_faces(mut self, vertex: Int, tag: Int, mut out: List[Int]):
        """Append a vertex's faces not yet tagged, tagging them."""
        for j in range(len(self.vert_ring_face[vertex])):  # pragma: no branch
            var face = self.vert_ring_face[vertex][j]
            if self.faces_tag_flags[face] != tag:
                self.faces_tag_flags[face] = tag
                out.append(face)

    def expands_vertices(mut self, vertices: List[Int], rings: Int) -> List[Int]:
        """Return the vertices and their neighbors, `rings` times over,
        three.js's `expandsVertices`.

        Args:
            vertices: The vertices to start from.
            rings: How many rings of neighbors to add.

        Returns:
            The vertices first, then each ring in the order met.
        """
        var tag = self.next_tag_flag()
        var expanded = vertices.copy()
        for vertex in vertices:
            self.vert_tag_flags[vertex] = tag
        var begin = 0
        for _ in range(rings):  # pragma: no branch
            var end = len(expanded)
            for i in range(begin, end):
                for neighbor in self.vert_ring_vert[expanded[i]].copy():
                    if self.vert_tag_flags[neighbor] != tag:
                        self.vert_tag_flags[neighbor] = tag
                        expanded.append(neighbor)
            begin = end
        return expanded^

    # --- dynamic topology --------------------------------------------------

    def update_render_triangles(mut self, faces: List[Int]):
        """Copy faces into the drawn triangles, three.js's
        `updateRenderTriangles`.

        Args:
            faces: The faces to copy.
        """
        for face in faces:
            for corner in range(3):  # pragma: no branch
                self.triangles[face * 3 + corner] = self.faces[face * 3 + corner]

    def update_vertices_on_edge(mut self, vertices: List[Int]):
        """Mark which vertices lie on an open edge, three.js's
        `updateVerticesOnEdge`.

        Args:
            vertices: The vertices to mark.
        """
        for vertex in vertices:
            self.vert_on_edge[vertex] = (
                1 if len(self.vert_ring_vert[vertex])
                != len(self.vert_ring_face[vertex]) else 0
            )

    def update_topology(mut self, faces: List[Int], vertices: List[Int]):
        """Copy faces to the drawn triangles and mark open edges, three.js's
        `updateTopology`.

        Args:
            faces: The faces that changed.
            vertices: The vertices that changed.
        """
        self.update_render_triangles(faces)
        self.update_vertices_on_edge(vertices)

    def re_allocate_arrays(mut self, nb_add_elements: Int):
        """Make room for more faces and vertices, three.js's
        `reAllocateArrays`: a list too small, or four times too large, is
        replaced with one twice what is needed.

        Args:
            nb_add_elements: How many faces, and how many vertices, to make
                room for.
        """
        var capacity = len(self.faces_tag_flags)
        var required = self.nb_faces + nb_add_elements
        if capacity < required or capacity > required * 4:
            self.faces = _resized_ints(self.faces, required * 3)
            self.triangles = _resized_ints(self.triangles, required * 3)
            self.face_boxes = _resized_floats(self.face_boxes, required * 6)
            self.face_normals = _resized_floats(self.face_normals, required * 3)
            self.face_centers = _resized_floats(self.face_centers, required * 3)
            self.faces_tag_flags = _resized_ints(self.faces_tag_flags, required)
            self.face_pos_in_leaf = _resized_ints(
                self.face_pos_in_leaf, required
            )
            self.buffer_version += 1
        capacity = len(self.vert_on_edge)
        required = self.nb_vertices + nb_add_elements
        if capacity < required or capacity > required * 4:
            self.vertices = _resized_floats(self.vertices, required * 3)
            self.normals = _resized_floats(self.normals, required * 3)
            self.render_normals = _resized_floats(
                self.render_normals, required * 3
            )
            self.vert_on_edge = _resized_ints(self.vert_on_edge, required)
            self.vert_tag_flags = _resized_ints(self.vert_tag_flags, required)
            self.vert_sculpt_flags = _resized_ints(
                self.vert_sculpt_flags, required
            )
            self.buffer_version += 1


def _outside(low: Float64, high: Float64, value: Float64) -> Float64:
    """Return how far a value lies outside a range, signed as three.js's
    `collectIntersectSphere` has it; zero inside."""
    return low - value if low > value else (high - value if high < value else 0.0)


def _weld_positions(
    source: List[Float32], referenced: List[Int], bounds: List[Float64]
) -> _Weld:
    """Weld positions nearer than the tolerance, three.js's
    `weldPositions`: a spatial hash of cells twice the tolerance, searched
    in the cell and its nearest neighbor on each axis."""
    var extent = max(
        max(bounds[3] - bounds[0], bounds[4] - bounds[1]), bounds[5] - bounds[2]
    )
    var tolerance = extent * RELATIVE_WELD_TOLERANCE
    var tolerance_squared = tolerance * tolerance
    var inverse_cell_size = 0.5 / tolerance if tolerance > 0 else 0.0
    var search_count = 2 if inverse_cell_size > 0 else 1
    var cell_heads = Dict[Int, Int]()
    var next_entry = List[Int]()
    var merged = List[Float32]()
    var count = len(source) // 3
    var vertex_map = List[Int](length=count, fill=0)
    for i in range(count):  # pragma: no branch
        if referenced[i] == 0:
            continue
        var p = point_of(source, i)
        var grid = Point3(
            (p.x - bounds[0]) * inverse_cell_size,
            (p.y - bounds[1]) * inverse_cell_size,
            (p.z - bounds[2]) * inverse_cell_size,
        )
        var cells: List[Int] = [
            Int(floor(grid.x)),
            Int(floor(grid.y)),
            Int(floor(grid.z)),
        ]
        var neighbors: List[Int] = [
            _near_cell(grid.x, cells[0]),
            _near_cell(grid.y, cells[1]),
            _near_cell(grid.z, cells[2]),
        ]
        var found = _find_weld(
            cell_heads,
            next_entry,
            merged,
            cells,
            neighbors,
            search_count,
            p,
            tolerance_squared,
        )
        if found == NO_CELL:
            found = len(merged) // 3
            var hash = _hash_position(cells[0], cells[1], cells[2])
            next_entry.append(cell_heads.get(hash, NO_CELL))
            cell_heads[hash] = found
            merged.append(source[i * 3])
            merged.append(source[i * 3 + 1])
            merged.append(source[i * 3 + 2])
        vertex_map[i] = found
    return _Weld(merged^, vertex_map^)


def _find_weld(
    cell_heads: Dict[Int, Int],
    next_entry: List[Int],
    merged: List[Float32],
    cells: List[Int],
    neighbors: List[Int],
    search_count: Int,
    p: Point3,
    tolerance_squared: Float64,
) -> Int:
    """Return the welded vertex a position joins: the first at exactly its
    place, else the nearest within the tolerance, else `NO_CELL`. The
    cells are searched z, then y, then x, the cell before its neighbor."""
    var found = NO_CELL
    var closest = inf[DType.float64]()
    for k in range(search_count * search_count * search_count):  # pragma: no branch
        var sx = cells[0] if k % search_count == 0 else neighbors[0]
        var sy = cells[1] if (k // search_count) % search_count == 0 else neighbors[1]
        var sz = cells[2] if k // (search_count * search_count) == 0 else neighbors[2]
        var candidate = cell_heads.get(_hash_position(sx, sy, sz), NO_CELL)
        while candidate != NO_CELL:
            var distance_squared = _sqr_dist_to(merged, candidate, p)
            if distance_squared == 0:
                return candidate
            if (
                distance_squared <= tolerance_squared
                and distance_squared < closest
            ):
                found = candidate
                closest = distance_squared
            candidate = next_entry[candidate]
    return found


def _sqr_dist_to(merged: List[Float32], candidate: Int, p: Point3) -> Float64:
    """Return the squared distance from a welded vertex to a position, in
    three.js's order: the vertex minus the position."""
    var q = point_of(merged, candidate)
    var dx = q.x - p.x
    var dy = q.y - p.y
    var dz = q.z - p.z
    return dx * dx + dy * dy + dz * dz


def _check_triangles(faces: List[Int], positions: List[Float32]) raises:
    """Refuse a welded triangle with a repeated vertex, no area, or a
    normal too large, three.js's checks in `buildTriangleBuffers`."""
    for i in range(len(faces) // 3):  # pragma: no branch
        var a = faces[i * 3]
        var b = faces[i * 3 + 1]
        var c = faces[i * 3 + 2]
        if a == b or b == c or c == a:
            raise Error("SculptorMesh: Welding produced a degenerate triangle.")
        var pa = point_of(positions, a)
        var pb = point_of(positions, b)
        var pc = point_of(positions, c)
        var abx = pb.x - pa.x
        var aby = pb.y - pa.y
        var abz = pb.z - pa.z
        var acx = pc.x - pa.x
        var acy = pc.y - pa.y
        var acz = pc.z - pa.z
        var nx = Float32(aby * acz - abz * acy)
        var ny = Float32(abz * acx - abx * acz)
        var nz = Float32(abx * acy - aby * acx)
        if not (isfinite(nx) and isfinite(ny) and isfinite(nz)):
            raise Error(
                "SculptorMesh: Triangle normals must fit in Float32 storage."
            )
        if nx == 0 and ny == 0 and nz == 0:
            raise Error(
                "SculptorMesh: The geometry contains a zero-area triangle at"
                " Float32 precision after welding."
            )
