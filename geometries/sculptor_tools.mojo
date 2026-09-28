# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sculpting tools and the adaptive topology, from three.js
`examples/jsm/misc/SculptorTools.js`, itself adapted from SculptGL by
Stéphane Ginier (MIT; see THIRD-PARTY-NOTICES.md).

Each tool moves the picked vertices of a `SculptorMesh` in place. The
weight of a move falls from one at the brush's center to zero at its rim;
see `sculptor_utils.falloff`.

| Tool | What it does |
|---|---|
| `tool_brush` | Moves along one normal, a tenth of the radius at full strength. |
| `tool_inflate` | Moves each vertex along its own normal. |
| `tool_flatten` | Moves toward a plane, from one side of it. |
| `tool_smooth` | Moves toward the mean of the neighbors. |
| `tool_pinch` | Moves toward the center. |
| `tool_crease` | Pinches, and pushes the center along a normal. |
| `tool_drag` | Moves by a vector. |
| `tool_scale` | Moves away from the center, or toward it. |

`subdivision_pass` splits the edges longer than a length, inside the
brush, and splits the neighbor faces so that no crack opens.
`decimation_pass` collapses the edges shorter than a length, or flips one
when a collapse would pinch the surface. Both keep the octree, the rings
and the flags in step.

**Where this differs.** three.js keys a split edge by a number, or by a
string when the number could overflow a double; the key here is an `Int`,
which holds the product of any two vertex counts a list can hold.
"""

from geometries.sculptor_mesh import SculptorMesh
from geometries.sculptor_utils import (
    Point3,
    falloff,
    point_of,
    remove_element,
    replace_element,
    sqr_dist,
    tidy,
    triangle_inside_sphere,
)
from std.math import acos, pi, pow, sqrt

# three.js's `Math.SQRT2`.
comptime _SQRT2 = 1.4142135623730951


def _set_point(mut values: List[Float32], vertex: Int, p: Point3):
    """Store a point in a packed list, rounded to `Float32`."""
    values[vertex * 3] = Float32(p.x)
    values[vertex * 3 + 1] = Float32(p.y)
    values[vertex * 3 + 2] = Float32(p.z)


def _set_face(mut mesh: SculptorMesh, face: Int, a: Int, b: Int, c: Int):
    """Write a face's three corners."""
    mesh.faces[face * 3] = a
    mesh.faces[face * 3 + 1] = b
    mesh.faces[face * 3 + 2] = c


def _put_ring(mut rings: List[List[Int]], vertex: Int, var ring: List[Int]):
    """Set a vertex's ring, appending it when the vertex is the next one,
    as a JavaScript array grows when written one past its end."""
    if vertex == len(rings):
        rings.append(ring^)
    else:
        rings[vertex] = ring^


def _truncate_rings(mut rings: List[List[Int]], length: Int):
    """Drop the rings past `length`, JavaScript's `array.length = n`."""
    while len(rings) > length:
        _ = rings.pop()


# --- subdivision -----------------------------------------------------------


struct _SubData(Movable):
    """What a subdivision pass shares, three.js's `SubData`."""

    var vertices_map: Dict[Int, Int]
    var edge_key_stride: Int
    var center: Point3
    var radius2: Float64
    var edge_max2: Float64

    def __init__(out self, center: Point3, radius2: Float64, edge_max2: Float64):
        """Start a pass about a brush."""
        self.vertices_map = Dict[Int, Int]()
        self.edge_key_stride = 0
        self.center = center
        self.radius2 = radius2
        self.edge_max2 = edge_max2

    def edge_key(self, a: Int, b: Int) -> Int:
        """Return the key of the edge between two vertices, either way
        round, three.js's `subEdgeKey`."""
        return min(a, b) * self.edge_key_stride + max(a, b)

    def split_vertex(self, a: Int, b: Int) -> Int:
        """Return the vertex that split an edge, or -1."""
        return self.vertices_map.get(self.edge_key(a, b), -1)


def _sub_fill_triangle(
    mut mesh: SculptorMesh, tri: Int, v1: Int, v2: Int, v3: Int, mid: Int
):
    """Split a face across an edge already split by a neighbor, three.js's
    `subFillTriangle`: the face keeps `v1, mid, v3` and a new face takes
    `mid, v2, v3`."""
    _set_face(mesh, tri, v1, mid, v3)
    var leaf = mesh.face_leaf[tri]
    mesh.vert_ring_vert[mid].append(v3)
    mesh.vert_ring_vert[v3].append(mid)
    var new_tri = mesh.nb_faces
    mesh.vert_ring_face[mid].append(tri)
    mesh.vert_ring_face[mid].append(new_tri)
    _set_face(mesh, new_tri, mid, v2, v3)
    mesh.face_leaf.append(leaf)
    mesh.face_pos_in_leaf[new_tri] = len(mesh.cells[leaf].faces)
    mesh.vert_ring_face[v3].append(new_tri)
    replace_element(mesh.vert_ring_face[v2], tri, new_tri)
    mesh.cells[leaf].faces.append(new_tri)
    mesh.add_nb_face(1)


def _fill_split(val1: Int, val2: Int, val3: Int, num1: Int, num2: Int, num3: Int) -> Int:
    """Return which split edge a face is cut across: 1 for its first edge,
    2 for its second, 3 for its third, 0 for none. With more than one, the
    one whose far corner has the fewest neighbors, as three.js chooses."""
    var has1 = val1 >= 0
    var has2 = val2 >= 0
    var has3 = val3 >= 0
    if has1 and has2 and has3:
        return 2 if (num1 < num2 and num1 < num3) else (3 if num2 < num3 else 1)
    if has1 and has2:
        return 2 if num1 < num3 else 1
    if has1:
        return 3 if (has3 and num2 < num3) else 1
    if has2:
        return 3 if (has3 and num2 < num1) else 2
    return 3 if has3 else 0


def _sub_fill_triangles(
    mut mesh: SculptorMesh, sub: _SubData, tris: List[Int]
) -> List[Int]:
    """Split every face that has a split edge, three.js's
    `subFillTriangles`.

    Returns:
        Each face split and its new half, for the next round.
    """
    var next = List[Int]()
    for tri in tris:  # pragma: no branch
        var v1 = mesh.faces[tri * 3]
        var v2 = mesh.faces[tri * 3 + 1]
        var v3 = mesh.faces[tri * 3 + 2]
        var val1 = sub.split_vertex(v1, v2)
        var val2 = sub.split_vertex(v2, v3)
        var val3 = sub.split_vertex(v1, v3)
        var split = _fill_split(
            val1,
            val2,
            val3,
            len(mesh.vert_ring_vert[v1]),
            len(mesh.vert_ring_vert[v2]),
            len(mesh.vert_ring_vert[v3]),
        )
        if split == 0:
            continue
        if split == 1:
            _sub_fill_triangle(mesh, tri, v1, v2, v3, val1)
        elif split == 2:
            _sub_fill_triangle(mesh, tri, v2, v3, v1, val2)
        else:
            _sub_fill_triangle(mesh, tri, v3, v1, v2, val3)
        next.append(tri)
        next.append(mesh.nb_faces - 1)
    return next^


def _unit_or_x(n: Point3) -> Point3:
    """Return a normal made unit; a zero normal becomes (1, 0, 0), as
    three.js's `halfEdgeSplit` has it."""
    var length = n.x * n.x + n.y * n.y + n.z * n.z
    if length == 0:
        return Point3(1, n.y, n.z)
    length = 1 / sqrt(length)
    return Point3(n.x * length, n.y * length, n.z * length)


def _half_edge_split(
    mut mesh: SculptorMesh, mut sub: _SubData, tri: Int, v1: Int, v2: Int, v3: Int
):
    """Split the edge `v1, v2` of a face at its middle, three.js's
    `halfEdgeSplit`. A new middle vertex bulges along the mean normal, by
    how far the two normals turn, so a curved surface stays curved."""
    var key = sub.edge_key(v1, v2)
    var mid = sub.vertices_map.get(key, -1)
    var is_new = mid < 0
    if is_new:
        mid = mesh.nb_vertices
        sub.vertices_map[key] = mid
    mesh.vert_ring_vert[v3].append(mid)
    _set_face(mesh, tri, v1, mid, v3)
    var new_tri = mesh.nb_faces
    _set_face(mesh, new_tri, mid, v2, v3)
    mesh.vert_ring_face[v3].append(new_tri)
    replace_element(mesh.vert_ring_face[v2], tri, new_tri)
    var leaf = mesh.face_leaf[tri]
    mesh.face_leaf.append(leaf)
    mesh.face_pos_in_leaf[new_tri] = len(mesh.cells[leaf].faces)
    mesh.cells[leaf].faces.append(new_tri)
    if not is_new:
        mesh.vert_ring_vert[mid].append(v3)
        mesh.vert_ring_face[mid].append(tri)
        mesh.vert_ring_face[mid].append(new_tri)
        mesh.add_nb_face(1)
        return
    var p1 = point_of(mesh.vertices, v1)
    var p2 = point_of(mesh.vertices, v2)
    var n1 = point_of(mesh.normals, v1)
    var n2 = point_of(mesh.normals, v2)
    var sum = Point3(n1.x + n2.x, n1.y + n2.y, n1.z + n2.z)
    _set_point(mesh.normals, mid, Point3(sum.x * 0.5, sum.y * 0.5, sum.z * 0.5))
    var u1 = _unit_or_x(n1)
    var u2 = _unit_or_x(n2)
    var d = u1.x * u2.x + u1.y * u2.y + u1.z * u2.z
    var angle = pi if d <= -1 else (0.0 if d >= 1 else acos(d))
    var ex = p1.x - p2.x
    var ey = p1.y - p2.y
    var ez = p1.z - p2.z
    var offset = angle * 0.12 * sqrt(ex * ex + ey * ey + ez * ez)
    var length = sum.x * sum.x + sum.y * sum.y + sum.z * sum.z
    offset = offset / sqrt(length) if length > 0 else offset
    var turn = ex * (u1.x - u2.x) + ey * (u1.y - u2.y) + ez * (u1.z - u2.z)
    offset = -offset if turn < 0 else offset
    _set_point(
        mesh.vertices,
        mid,
        Point3(
            (p1.x + p2.x) * 0.5 + sum.x * offset,
            (p1.y + p2.y) * 0.5 + sum.y * offset,
            (p1.z + p2.z) * 0.5 + sum.z * offset,
        ),
    )
    _put_ring(mesh.vert_ring_vert, mid, [v1, v2, v3])
    _put_ring(mesh.vert_ring_face, mid, [tri, new_tri])
    replace_element(mesh.vert_ring_vert[v1], v2, mid)
    replace_element(mesh.vert_ring_vert[v2], v1, mid)
    mesh.add_nb_vertice(1)
    mesh.add_nb_face(1)


def _sub_find_split(
    mesh: SculptorMesh, sub: _SubData, tri: Int, check_inside_sphere: Bool
) -> Int:
    """Return which edge of a face to split: its longest, if longer than
    the limit, and if the face reaches into the brush when that is asked,
    three.js's `subFindSplit`.

    Returns:
        1, 2 or 3 for the edge `v1 v2`, `v2 v3` or `v1 v3`, or 0 for none.
    """
    var v1 = point_of(mesh.vertices, mesh.faces[tri * 3])
    var v2 = point_of(mesh.vertices, mesh.faces[tri * 3 + 1])
    var v3 = point_of(mesh.vertices, mesh.faces[tri * 3 + 2])
    if check_inside_sphere and not triangle_inside_sphere(
        sub.center, sub.radius2, v1, v2, v3
    ):
        return 0
    var length1 = sqr_dist(v1, v2)
    var length2 = sqr_dist(v2, v3)
    var length3 = sqr_dist(v1, v3)
    if length1 > length2 and length1 > length3:
        return 1 if length1 > sub.edge_max2 else 0
    if length2 > length3:
        return 2 if length2 > sub.edge_max2 else 0
    return 3 if length3 > sub.edge_max2 else 0


def _count_up(start: Int, stop: Int) -> List[Int]:
    """Return the numbers from `start` up to `stop`, `stop` left out."""
    var out = List[Int](capacity=max(stop - start, 0))
    for i in range(start, stop):
        out.append(i)
    return out^


def _subdivide(
    mut mesh: SculptorMesh, mut sub: _SubData, tris: List[Int]
) -> List[Int]:
    """Split, once, each face in the brush whose longest edge is too long,
    and the faces about them that the splits crack, three.js's
    `subdivide`.

    Returns:
        The faces to look at again: the ones given, then the new ones.
    """
    var vertices_before = mesh.nb_vertices
    var faces_before = mesh.nb_faces
    sub.vertices_map = Dict[Int, Int]()
    var to_split = List[Int]()
    var splits = List[Int]()
    for tri in tris:
        var split = _sub_find_split(mesh, sub, tri, True)
        if split == 0:
            continue
        splits.append(split)
        to_split.append(tri)
    if len(to_split) == 0:
        mesh.re_allocate_arrays(0)
        return tris.copy()
    if len(to_split) > 5:
        to_split = mesh.expands_faces(to_split, 3)
        while len(splits) < len(to_split):
            splits.append(0)
    # One new vertex at most per face split, so no key can collide.
    sub.edge_key_stride = mesh.nb_vertices + len(to_split) + 1
    mesh.re_allocate_arrays(len(splits))
    for i in range(len(to_split)):  # pragma: no branch
        var tri = to_split[i]
        var split = splits[i]
        if split == 0:
            split = _sub_find_split(mesh, sub, tri, False)
        var a = mesh.faces[tri * 3]
        var b = mesh.faces[tri * 3 + 1]
        var c = mesh.faces[tri * 3 + 2]
        if split == 1:
            _half_edge_split(mesh, sub, tri, a, b, c)
        elif split == 2:
            _half_edge_split(mesh, sub, tri, b, c, a)
        elif split == 3:
            _half_edge_split(mesh, sub, tri, c, a, b)
    var new_tris = mesh.expands_faces(_count_up(faces_before, mesh.nb_faces), 1)
    var all_tris = tris.copy()
    all_tris.extend(new_tris.copy())
    var tag = mesh.next_tag_flag()
    var result = List[Int]()
    for tri in all_tris:  # pragma: no branch
        if mesh.faces_tag_flags[tri] == tag:
            continue
        mesh.faces_tag_flags[tri] = tag
        result.append(tri)
    # Split the neighboring faces to close the cracks.
    var faces_old = mesh.nb_faces
    while len(new_tris) > 0:
        mesh.re_allocate_arrays(len(new_tris))
        new_tris = _sub_fill_triangles(mesh, sub, new_tris)
    result.extend(_count_up(faces_old, mesh.nb_faces))
    # Smooth the new vertices' neighbors, then flag the new vertices.
    var new_count = mesh.nb_vertices - vertices_before
    var new_vertices = mesh.expands_vertices(
        _count_up(vertices_before, mesh.nb_vertices), 1
    )
    var expanded = List[Int](capacity=len(new_vertices) - new_count)
    for i in range(new_count, len(new_vertices)):
        expanded.append(new_vertices[i])
    smooth_tangent_verts(mesh, expanded, 1.0)
    var mask = mesh.sculpt_flag
    for vertex in new_vertices:  # pragma: no branch
        var p = point_of(mesh.vertices, vertex)
        var near = sqr_dist(p, sub.center) < sub.radius2
        mesh.vert_sculpt_flags[vertex] = mask if near else mask - 1
    return result^


def subdivision_pass(
    mut mesh: SculptorMesh,
    tris: List[Int],
    center: Point3,
    radius2: Float64,
    edge_max2: Float64,
) -> List[Int]:
    """Split edges longer than a length inside a brush until none is left,
    three.js's `subdivisionPass`.

    Args:
        mesh: The mesh to change.
        tris: The faces to look at.
        center: The brush's center.
        radius2: The brush's squared radius.
        edge_max2: The squared length above which an edge splits.

    Returns:
        The faces looked at and the faces made.
    """
    var sub = _SubData(center, radius2, edge_max2)
    var faces = tris.copy()
    var count = 0
    while count != mesh.nb_faces:
        count = mesh.nb_faces
        faces = _subdivide(mesh, sub, faces)
    return faces^


# --- decimation ------------------------------------------------------------


struct _DecData(Movable):
    """What a decimation pass collects, three.js's `DecData`."""

    var tris_to_delete: List[Int]
    var verts_to_delete: List[Int]
    var verts_decimated: List[Int]

    def __init__(out self):
        """Start with nothing collected."""
        self.tris_to_delete = List[Int]()
        self.verts_to_delete = List[Int]()
        self.verts_decimated = List[Int]()


def has_at_least_three_common_elements(a: List[Int], b: List[Int]) -> Bool:
    """Return True if two sorted lists share three values, three.js's
    `hasAtLeastThreeCommonElements`.

    Args:
        a: One sorted list.
        b: The other.

    Returns:
        Whether three values are in both.
    """
    var ai = 0
    var bi = 0
    var count = 0
    while ai < len(a) and bi < len(b):
        if a[ai] < b[bi]:
            ai += 1
        elif a[ai] > b[bi]:
            bi += 1
        else:
            count += 1
            if count == 3:
                return True
            ai += 1
            bi += 1
    return False


def _dec_delete_triangle(mut mesh: SculptorMesh, mut dec: _DecData, tri: Int):
    """Delete a face by moving the last face into its place, three.js's
    `decDeleteTriangle`."""
    var old_pos = mesh.face_pos_in_leaf[tri]
    var leaf = mesh.face_leaf[tri]
    var last_tri = mesh.cells[leaf].faces[len(mesh.cells[leaf].faces) - 1]
    if tri != last_tri:
        mesh.cells[leaf].faces[old_pos] = last_tri
        mesh.face_pos_in_leaf[last_tri] = old_pos
    _ = mesh.cells[leaf].faces.pop()
    var last_pos = mesh.nb_faces - 1
    if last_pos == tri:
        _ = mesh.face_leaf.pop()
        mesh.add_nb_face(-1)
        return
    var v1 = mesh.faces[last_pos * 3]
    var v2 = mesh.faces[last_pos * 3 + 1]
    var v3 = mesh.faces[last_pos * 3 + 2]
    replace_element(mesh.vert_ring_face[v1], last_pos, tri)
    replace_element(mesh.vert_ring_face[v2], last_pos, tri)
    replace_element(mesh.vert_ring_face[v3], last_pos, tri)
    var leaf_last = mesh.face_leaf[last_pos]
    var pos_last = mesh.face_pos_in_leaf[last_pos]
    mesh.cells[leaf_last].faces[pos_last] = tri
    mesh.face_leaf[tri] = leaf_last
    mesh.face_pos_in_leaf[tri] = pos_last
    mesh.faces_tag_flags[tri] = mesh.faces_tag_flags[last_pos]
    _set_face(mesh, tri, v1, v2, v3)
    _ = mesh.face_leaf.pop()
    dec.verts_decimated.append(v1)
    dec.verts_decimated.append(v2)
    dec.verts_decimated.append(v3)
    mesh.add_nb_face(-1)


def _dec_delete_vertex(mut mesh: SculptorMesh, vertex: Int):
    """Delete a vertex by moving the last vertex into its place, three.js's
    `decDeleteVertex`."""
    var last_pos = mesh.nb_vertices - 1
    if vertex == last_pos:
        _truncate_rings(mesh.vert_ring_vert, last_pos)
        _truncate_rings(mesh.vert_ring_face, last_pos)
        mesh.add_nb_vertice(-1)
        return
    var tris = mesh.vert_ring_face[last_pos].copy()
    for tri in tris:
        var corner = tri * 3 + (
            0 if mesh.faces[tri * 3] == last_pos else (
                1 if mesh.faces[tri * 3 + 1] == last_pos else 2
            )
        )
        mesh.faces[corner] = vertex
    var ring = mesh.vert_ring_vert[last_pos].copy()
    for neighbor in ring:
        replace_element(mesh.vert_ring_vert[neighbor], last_pos, vertex)
    mesh.vert_ring_vert[vertex] = ring^
    mesh.vert_ring_face[vertex] = tris^
    mesh.vert_tag_flags[vertex] = mesh.vert_tag_flags[last_pos]
    mesh.vert_sculpt_flags[vertex] = mesh.vert_sculpt_flags[last_pos]
    _set_point(mesh.vertices, vertex, point_of(mesh.vertices, last_pos))
    _set_point(mesh.normals, vertex, point_of(mesh.normals, last_pos))
    _truncate_rings(mesh.vert_ring_vert, last_pos)
    _truncate_rings(mesh.vert_ring_face, last_pos)
    mesh.add_nb_vertice(-1)


def _replace_corner(mut mesh: SculptorMesh, tri: Int, old: Int, new: Int):
    """Replace a face's corner `old` with `new`, the third corner when
    neither of the first two is `old`."""
    var corner = tri * 3 + (
        0 if mesh.faces[tri * 3] == old else (
            1 if mesh.faces[tri * 3 + 1] == old else 2
        )
    )
    mesh.faces[corner] = new


def _dec_edge_collapse(
    mut mesh: SculptorMesh,
    mut dec: _DecData,
    tri1: Int,
    tri2: Int,
    v1: Int,
    v2: Int,
    opp1: Int,
    opp2: Int,
    mut tris: List[Int],
):
    """Collapse the edge `v1 v2` shared by two faces, or flip it when the
    two ends share a third neighbor, three.js's `decEdgeCollapse`. Nothing
    happens at an open edge, at two vertices of three neighbors each, or
    where the flip would make an edge that exists."""
    if len(mesh.vert_ring_vert[v1]) != len(mesh.vert_ring_face[v1]) or len(
        mesh.vert_ring_vert[v2]
    ) != len(mesh.vert_ring_face[v2]):
        return
    if len(mesh.vert_ring_vert[opp1]) != len(mesh.vert_ring_face[opp1]) or len(
        mesh.vert_ring_vert[opp2]
    ) != len(mesh.vert_ring_face[opp2]):
        return
    # A tetrahedron cannot collapse without leaving coincident triangles.
    if len(mesh.vert_ring_vert[v1]) == 3 and len(mesh.vert_ring_vert[v2]) == 3:
        return
    sort(mesh.vert_ring_vert[v1])
    sort(mesh.vert_ring_vert[v2])
    if has_at_least_three_common_elements(
        mesh.vert_ring_vert[v1], mesh.vert_ring_vert[v2]
    ):
        # A flip would leave four triangles sharing an edge.
        if opp2 in mesh.vert_ring_vert[opp1]:
            return
        dec.verts_decimated.append(v1)
        dec.verts_decimated.append(v2)
        remove_element(mesh.vert_ring_face[v1], tri2)
        remove_element(mesh.vert_ring_face[v2], tri1)
        mesh.vert_ring_face[opp1].append(tri2)
        mesh.vert_ring_face[opp2].append(tri1)
        _replace_corner(mesh, tri1, v2, opp2)
        _replace_corner(mesh, tri2, v1, opp1)
        mesh.compute_ring_vertices(v1)
        mesh.compute_ring_vertices(v2)
        mesh.compute_ring_vertices(opp1)
        mesh.compute_ring_vertices(opp2)
        mesh.mark_topology_changed()
        return
    dec.verts_decimated.append(v1)
    dec.verts_decimated.append(v2)
    var n1 = point_of(mesh.normals, v1)
    var n2 = point_of(mesh.normals, v2)
    var n = _unit_or_x(Point3(n1.x + n2.x, n1.y + n2.y, n1.z + n2.z))
    _set_point(mesh.normals, v1, n)
    remove_element(mesh.vert_ring_face[v1], tri1)
    remove_element(mesh.vert_ring_face[v1], tri2)
    remove_element(mesh.vert_ring_face[v2], tri1)
    remove_element(mesh.vert_ring_face[v2], tri2)
    remove_element(mesh.vert_ring_face[opp1], tri1)
    remove_element(mesh.vert_ring_face[opp2], tri2)
    for tri in mesh.vert_ring_face[v2].copy():
        mesh.vert_ring_face[v1].append(tri)
        _replace_corner(mesh, tri, v2, v1)
    for neighbor in mesh.vert_ring_vert[v2].copy():  # pragma: no branch
        mesh.vert_ring_vert[v1].append(neighbor)
    mesh.compute_ring_vertices(v1)
    # Project the neighbors' mean onto the tangent plane.
    var ring_count = len(mesh.vert_ring_vert[v1])
    var mean_x = 0.0
    var mean_y = 0.0
    var mean_z = 0.0
    for i in range(ring_count):  # pragma: no branch
        var neighbor = mesh.vert_ring_vert[v1][i]
        mesh.compute_ring_vertices(neighbor)
        var p = point_of(mesh.vertices, neighbor)
        mean_x += p.x
        mean_y += p.y
        mean_z += p.z
    mean_x /= Float64(ring_count)
    mean_y /= Float64(ring_count)
    mean_z /= Float64(ring_count)
    var p1 = point_of(mesh.vertices, v1)
    var dot_n = (
        n.x * (mean_x - p1.x) + n.y * (mean_y - p1.y) + n.z * (mean_z - p1.z)
    )
    _set_point(
        mesh.vertices,
        v1,
        Point3(mean_x - n.x * dot_n, mean_y - n.y * dot_n, mean_z - n.z * dot_n),
    )
    mesh.vert_tag_flags[v2] = -1
    mesh.faces_tag_flags[tri1] = -1
    mesh.faces_tag_flags[tri2] = -1
    dec.verts_to_delete.append(v2)
    dec.tris_to_delete.append(tri1)
    dec.tris_to_delete.append(tri2)
    for tri in mesh.vert_ring_face[v1]:  # pragma: no branch
        tris.append(tri)


def _dec_decimate_triangles(
    mut mesh: SculptorMesh,
    mut dec: _DecData,
    tri1: Int,
    tri2: Int,
    mut tris: List[Int],
):
    """Find the edge two faces share and collapse it, three.js's
    `decDecimateTriangles`. `tri2` is -1 when there is no second face."""
    if tri2 == -1:
        return
    var a1 = mesh.faces[tri1 * 3]
    var b1 = mesh.faces[tri1 * 3 + 1]
    var c1 = mesh.faces[tri1 * 3 + 2]
    var a2 = mesh.faces[tri2 * 3]
    var b2 = mesh.faces[tri2 * 3 + 1]
    var c2 = mesh.faces[tri2 * 3 + 2]
    if a1 == a2:
        if b1 == c2:
            _dec_edge_collapse(mesh, dec, tri1, tri2, a1, b1, c1, b2, tris)
        else:
            _dec_edge_collapse(mesh, dec, tri1, tri2, a1, c1, b1, c2, tris)
    elif a1 == b2:
        if b1 == a2:
            _dec_edge_collapse(mesh, dec, tri1, tri2, a1, b1, c1, c2, tris)
        else:
            _dec_edge_collapse(mesh, dec, tri1, tri2, a1, c1, b1, a2, tris)
    elif a1 == c2:
        if b1 == b2:
            _dec_edge_collapse(mesh, dec, tri1, tri2, a1, b1, c1, a2, tris)
        else:
            _dec_edge_collapse(mesh, dec, tri1, tri2, a1, c1, b1, b2, tris)
    elif b1 == a2:
        _dec_edge_collapse(mesh, dec, tri1, tri2, c1, b1, a1, b2, tris)
    elif b1 == b2:
        _dec_edge_collapse(mesh, dec, tri1, tri2, c1, b1, a1, c2, tris)
    else:
        _dec_edge_collapse(mesh, dec, tri1, tri2, c1, b1, a1, a2, tris)


def _dec_find_opposite_triangle(mesh: SculptorMesh, tri: Int, v1: Int, v2: Int) -> Int:
    """Return the other face on the edge `v1 v2`, or -1 when the edge has
    one face or more than two, three.js's `decFindOppositeTriangle`."""
    var count = 0
    var opposite = -1
    for candidate in mesh.vert_ring_face[v1]:  # pragma: no branch
        if candidate in mesh.vert_ring_face[v2]:
            count += 1
            opposite = opposite if candidate == tri else candidate
    return opposite if count == 2 else -1


def _dec_try(
    mut mesh: SculptorMesh,
    mut dec: _DecData,
    tri: Int,
    center: Point3,
    radius2: Float64,
    detail2: Float64,
    mut tris: List[Int],
):
    """Collapse a face's shortest edge if it is shorter than the limit,
    which shrinks to nothing from the brush's rim to 1.4 radii out."""
    if mesh.faces_tag_flags[tri] < 0:
        return
    var i1 = mesh.faces[tri * 3]
    var i2 = mesh.faces[tri * 3 + 1]
    var i3 = mesh.faces[tri * 3 + 2]
    var v1 = point_of(mesh.vertices, i1)
    var v2 = point_of(mesh.vertices, i2)
    var v3 = point_of(mesh.vertices, i3)
    var dx = (v1.x + v2.x + v3.x) / 3.0 - center.x
    var dy = (v1.y + v2.y + v3.y) / 3.0 - center.y
    var dz = (v1.z + v2.z + v3.z) / 3.0 - center.z
    var fall_off = dx * dx + dy * dy + dz * dz
    if fall_off >= radius2 * 2.0:
        return
    if fall_off < radius2:
        fall_off = 1.0
    else:
        var radius = sqrt(radius2)
        fall_off = (sqrt(fall_off) - radius) / (radius * _SQRT2 - radius)
        var f2 = fall_off * fall_off
        fall_off = 3.0 * f2 * f2 - 4.0 * f2 * fall_off + 1.0
    var len1 = sqr_dist(v2, v1)
    var len2 = sqr_dist(v2, v3)
    var len3 = sqr_dist(v1, v3)
    var limit = detail2 * fall_off
    if len1 < len2 and len1 < len3:
        if len1 < limit:
            _dec_decimate_triangles(
                mesh, dec, tri, _dec_find_opposite_triangle(mesh, tri, i1, i2), tris
            )
    elif len2 < len3:
        if len2 < limit:
            _dec_decimate_triangles(
                mesh, dec, tri, _dec_find_opposite_triangle(mesh, tri, i2, i3), tris
            )
    elif len3 < limit:
        _dec_decimate_triangles(
            mesh, dec, tri, _dec_find_opposite_triangle(mesh, tri, i1, i3), tris
        )


def decimation_pass(
    mut mesh: SculptorMesh,
    tris: List[Int],
    center: Point3,
    radius2: Float64,
    detail2: Float64,
) -> List[Int]:
    """Collapse the edges shorter than a length near a brush, three.js's
    `decimationPass`.

    Args:
        mesh: The mesh to change.
        tris: The faces to look at.
        center: The brush's center.
        radius2: The brush's squared radius.
        detail2: The squared length below which an edge collapses, at the
            brush's center.

    Returns:
        The faces that are left of those looked at, and the faces about
        the vertices that moved.
    """
    var dec = _DecData()
    var queue = tris.copy()
    var i = 0
    while i < len(queue):
        var tri = queue[i]
        i += 1
        _dec_try(mesh, dec, tri, center, radius2, detail2, queue)
    # Delete the highest first, so each move keeps the pending indices.
    tidy(dec.tris_to_delete)
    for k in range(len(dec.tris_to_delete) - 1, -1, -1):
        _dec_delete_triangle(mesh, dec, dec.tris_to_delete[k])
    tidy(dec.verts_to_delete)
    for k in range(len(dec.verts_to_delete) - 1, -1, -1):
        _dec_delete_vertex(mesh, dec.verts_to_delete[k])
    var tag = mesh.next_tag_flag()
    var valid_vertices = List[Int]()
    for vertex in dec.verts_decimated:
        if vertex >= mesh.nb_vertices or mesh.vert_tag_flags[vertex] == tag:
            continue
        mesh.vert_tag_flags[vertex] = tag
        valid_vertices.append(vertex)
    var candidates = queue^
    candidates.extend(mesh.get_faces_from_vertices(valid_vertices))
    tag = mesh.next_tag_flag()
    var valid_tris = List[Int]()
    for tri in candidates:  # pragma: no branch
        if tri >= mesh.nb_faces or mesh.faces_tag_flags[tri] == tag:
            continue
        mesh.faces_tag_flags[tri] = tag
        valid_tris.append(tri)
    return valid_tris^


# --- tool helpers ----------------------------------------------------------


def laplacian_smooth(mesh: SculptorMesh, vertices: List[Int]) -> List[Float32]:
    """Return each vertex's smoothed place: the mean of its neighbors, or
    of its neighbors on the open edge when it is on one, three.js's
    `laplacianSmooth`. A vertex with two neighbors or fewer stays.

    Args:
        mesh: The mesh.
        vertices: The vertices to smooth.

    Returns:
        Three numbers per vertex, rounded to `Float32` as three.js's
        scratch array rounds them.
    """
    var smooth = List[Float32](capacity=len(vertices) * 3)
    for vertex in vertices:
        var p = _smoothed(mesh, vertex)
        smooth.append(Float32(p.x))
        smooth.append(Float32(p.y))
        smooth.append(Float32(p.z))
    return smooth^


def _smoothed(mesh: SculptorMesh, vertex: Int) -> Point3:
    """Return one vertex's smoothed place; see `laplacian_smooth`."""
    var count = len(mesh.vert_ring_vert[vertex])
    if count <= 2:
        return point_of(mesh.vertices, vertex)
    if mesh.vert_on_edge[vertex] == 1:
        var edge_sum = Point3(0, 0, 0)
        var edge_count = 0
        for neighbor in mesh.vert_ring_vert[vertex]:  # pragma: no branch
            if mesh.vert_on_edge[neighbor] == 1:
                var q = point_of(mesh.vertices, neighbor)
                edge_sum = Point3(edge_sum.x + q.x, edge_sum.y + q.y, edge_sum.z + q.z)
                edge_count += 1
        if edge_count >= 2:
            var n = Float64(edge_count)
            return Point3(edge_sum.x / n, edge_sum.y / n, edge_sum.z / n)
    var sum = Point3(0, 0, 0)
    for neighbor in mesh.vert_ring_vert[vertex]:  # pragma: no branch
        var q = point_of(mesh.vertices, neighbor)
        sum = Point3(sum.x + q.x, sum.y + q.y, sum.z + q.z)
    var n = Float64(count)
    return Point3(sum.x / n, sum.y / n, sum.z / n)


def smooth_tangent_verts(
    mut mesh: SculptorMesh, vertices: List[Int], strength: Float64
):
    """Move vertices toward their smoothed places, along the surface only,
    three.js's `smoothTangentVerts`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices to move.
        strength: How far, from zero to one.
    """
    var intensity = min(strength, 1.0)
    var smooth = laplacian_smooth(mesh, vertices)
    for i in range(len(vertices)):
        var vertex = vertices[i]
        var v = point_of(mesh.vertices, vertex)
        var n = point_of(mesh.normals, vertex)
        var length = n.x * n.x + n.y * n.y + n.z * n.z
        if length == 0:
            continue
        length = 1 / sqrt(length)
        n = Point3(n.x * length, n.y * length, n.z * length)
        var s = point_of(smooth, i)
        var d = n.x * (s.x - v.x) + n.y * (s.y - v.y) + n.z * (s.z - v.z)
        _set_point(
            mesh.vertices,
            vertex,
            Point3(
                v.x + (s.x - n.x * d - v.x) * intensity,
                v.y + (s.y - n.y * d - v.y) * intensity,
                v.z + (s.z - n.z * d - v.z) * intensity,
            ),
        )


def get_front_vertices(
    mesh: SculptorMesh, vertices: List[Int], eye_dir: Point3
) -> List[Int]:
    """Return the vertices whose normals face the eye, three.js's
    `getFrontVertices`.

    Args:
        mesh: The mesh.
        vertices: The vertices to sort out.
        eye_dir: Which way the eye looks.

    Returns:
        The vertices whose normal does not point along `eye_dir`.
    """
    var front = List[Int]()
    for vertex in vertices:  # pragma: no branch
        var n = point_of(mesh.normals, vertex)
        if n.x * eye_dir.x + n.y * eye_dir.y + n.z * eye_dir.z <= 0:
            front.append(vertex)
    return front^


def area_normal(mesh: SculptorMesh, vertices: List[Int]) -> Optional[Point3]:
    """Return the unit mean of the vertices' normals, three.js's
    `areaNormal`.

    Args:
        mesh: The mesh.
        vertices: The vertices.

    Returns:
        The normal, or `None` when the normals cancel or there are none.
    """
    var sum = Point3(0, 0, 0)
    for vertex in vertices:
        var n = point_of(mesh.normals, vertex)
        sum = Point3(sum.x + n.x, sum.y + n.y, sum.z + n.z)
    var length = sqrt(sum.x * sum.x + sum.y * sum.y + sum.z * sum.z)
    if length == 0:
        return None
    var inverse = 1.0 / length
    return Point3(sum.x * inverse, sum.y * inverse, sum.z * inverse)


def area_center(mesh: SculptorMesh, vertices: List[Int]) -> Point3:
    """Return the mean of the vertices' places, three.js's `areaCenter`.

    Args:
        mesh: The mesh.
        vertices: The vertices; at least one.

    Returns:
        The mean.
    """
    var sum = Point3(0, 0, 0)
    for vertex in vertices:  # pragma: no branch
        var p = point_of(mesh.vertices, vertex)
        sum = Point3(sum.x + p.x, sum.y + p.y, sum.z + p.z)
    var n = Float64(len(vertices))
    return Point3(sum.x / n, sum.y / n, sum.z / n)


def _reach(mesh: SculptorMesh, vertex: Int, center: Point3, radius: Float64) -> Float64:
    """Return how far a vertex is from the center, as a share of the
    radius: the vertex minus the center, as three.js measures it."""
    var p = point_of(mesh.vertices, vertex)
    var dx = p.x - center.x
    var dy = p.y - center.y
    var dz = p.z - center.z
    return sqrt(dx * dx + dy * dy + dz * dz) / radius


# --- tools -----------------------------------------------------------------


def tool_brush(
    mut mesh: SculptorMesh,
    vertices: List[Int],
    normal: Point3,
    center: Point3,
    radius_sq: Float64,
    strength: Float64,
    negative: Bool,
):
    """Raise the surface along one normal, three.js's `toolBrush`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        normal: Which way to raise; a unit vector.
        center: The brush's center.
        radius_sq: The brush's squared radius.
        strength: How far, from zero to one: a tenth of the radius at one.
        negative: Whether to lower instead.
    """
    var radius = sqrt(radius_sq)
    var deform = strength * radius * 0.1
    deform = -deform if negative else deform
    for vertex in vertices:  # pragma: no branch
        var dist = _reach(mesh, vertex, center, radius)
        if dist >= 1.0:
            continue
        var fall_off = falloff(dist) * deform
        var p = point_of(mesh.vertices, vertex)
        _set_point(
            mesh.vertices,
            vertex,
            Point3(
                p.x + normal.x * fall_off,
                p.y + normal.y * fall_off,
                p.z + normal.z * fall_off,
            ),
        )


def tool_flatten(
    mut mesh: SculptorMesh,
    vertices: List[Int],
    normal: Point3,
    plane_point: Point3,
    center: Point3,
    radius_sq: Float64,
    strength: Float64,
    negative: Bool,
):
    """Move the surface toward a plane, three.js's `toolFlatten`. Only the
    vertices below the plane move, or above it when `negative`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        normal: The plane's unit normal.
        plane_point: A point on the plane.
        center: The brush's center.
        radius_sq: The brush's squared radius.
        strength: How far, from zero to one: all the way at one.
        negative: Whether to move the vertices above the plane instead.
    """
    var radius = sqrt(radius_sq)
    var comp = -1.0 if negative else 1.0
    for vertex in vertices:  # pragma: no branch
        var p = point_of(mesh.vertices, vertex)
        var dist_to_plane = (
            (p.x - plane_point.x) * normal.x
            + (p.y - plane_point.y) * normal.y
            + (p.z - plane_point.z) * normal.z
        )
        if dist_to_plane * comp > 0:
            continue
        var dist = _reach(mesh, vertex, center, radius)
        if dist >= 1.0:
            continue
        var fall_off = falloff(dist) * dist_to_plane * strength
        _set_point(
            mesh.vertices,
            vertex,
            Point3(
                p.x - normal.x * fall_off,
                p.y - normal.y * fall_off,
                p.z - normal.z * fall_off,
            ),
        )


def tool_inflate(
    mut mesh: SculptorMesh,
    vertices: List[Int],
    center: Point3,
    radius_sq: Float64,
    strength: Float64,
    negative: Bool,
):
    """Move each vertex along its own normal, three.js's `toolInflate`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        center: The brush's center.
        radius_sq: The brush's squared radius.
        strength: How far, from zero to one: a tenth of the radius at one.
        negative: Whether to deflate instead.
    """
    var radius = sqrt(radius_sq)
    var deform = strength * radius * 0.1
    deform = -deform if negative else deform
    for vertex in vertices:  # pragma: no branch
        var dist = _reach(mesh, vertex, center, radius)
        if dist >= 1.0:
            continue
        var fall_off = falloff(dist) * deform
        var n = point_of(mesh.normals, vertex)
        var n_len = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
        fall_off = fall_off / n_len if n_len > 0 else fall_off
        var p = point_of(mesh.vertices, vertex)
        _set_point(
            mesh.vertices,
            vertex,
            Point3(
                p.x + n.x * fall_off, p.y + n.y * fall_off, p.z + n.z * fall_off
            ),
        )


def tool_smooth(mut mesh: SculptorMesh, vertices: List[Int], strength: Float64):
    """Move each vertex toward its neighbors' mean, three.js's
    `toolSmooth`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        strength: How far, from zero to one: all the way at one.
    """
    var intensity = min(strength, 1.0)
    var keep = 1.0 - intensity
    var smooth = laplacian_smooth(mesh, vertices)
    for i in range(len(vertices)):  # pragma: no branch
        var p = point_of(mesh.vertices, vertices[i])
        var s = point_of(smooth, i)
        _set_point(
            mesh.vertices,
            vertices[i],
            Point3(
                p.x * keep + s.x * intensity,
                p.y * keep + s.y * intensity,
                p.z * keep + s.z * intensity,
            ),
        )


def tool_pinch(
    mut mesh: SculptorMesh,
    vertices: List[Int],
    center: Point3,
    radius_sq: Float64,
    strength: Float64,
    negative: Bool,
):
    """Move the vertices toward the center, three.js's `toolPinch`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        center: The brush's center.
        radius_sq: The brush's squared radius.
        strength: How far, from zero to one: a twentieth of the way at one.
        negative: Whether to push away instead.
    """
    var radius = sqrt(radius_sq)
    var deform = strength * 0.05
    deform = -deform if negative else deform
    for vertex in vertices:  # pragma: no branch
        var p = point_of(mesh.vertices, vertex)
        var dx = center.x - p.x
        var dy = center.y - p.y
        var dz = center.z - p.z
        var dist = sqrt(dx * dx + dy * dy + dz * dz) / radius
        var fall_off = falloff(dist) * deform
        _set_point(
            mesh.vertices,
            vertex,
            Point3(p.x + dx * fall_off, p.y + dy * fall_off, p.z + dz * fall_off),
        )


def tool_crease(
    mut mesh: SculptorMesh,
    vertices: List[Int],
    normal: Point3,
    center: Point3,
    radius_sq: Float64,
    strength: Float64,
    negative: Bool,
):
    """Pinch toward the center and push the middle along a normal,
    three.js's `toolCrease`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        normal: Which way to push; a unit vector.
        center: The brush's center.
        radius_sq: The brush's squared radius.
        strength: How far, from zero to one.
        negative: Whether to push the other way.
    """
    var radius = sqrt(radius_sq)
    var deform = strength * 0.07
    var brush_factor = deform * radius
    brush_factor = -brush_factor if negative else brush_factor
    for vertex in vertices:  # pragma: no branch
        var p = point_of(mesh.vertices, vertex)
        var dx = center.x - p.x
        var dy = center.y - p.y
        var dz = center.z - p.z
        var dist = sqrt(dx * dx + dy * dy + dz * dz) / radius
        if dist >= 1.0:
            continue
        var fall_off = falloff(dist)
        var brush_mod = pow(fall_off, 5.0) * brush_factor
        var pinch = fall_off * deform
        _set_point(
            mesh.vertices,
            vertex,
            Point3(
                p.x + dx * pinch + normal.x * brush_mod,
                p.y + dy * pinch + normal.y * brush_mod,
                p.z + dz * pinch + normal.z * brush_mod,
            ),
        )


def tool_drag(
    mut mesh: SculptorMesh,
    vertices: List[Int],
    center: Point3,
    radius_sq: Float64,
    drag_dir: Point3,
):
    """Move the vertices by a vector, fading to the rim, three.js's
    `toolDrag`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        center: The brush's center.
        radius_sq: The brush's squared radius.
        drag_dir: How far and which way the center moves.
    """
    var radius = sqrt(radius_sq)
    for vertex in vertices:  # pragma: no branch
        var p = point_of(mesh.vertices, vertex)
        var fall_off = falloff(_reach(mesh, vertex, center, radius))
        _set_point(
            mesh.vertices,
            vertex,
            Point3(
                p.x + drag_dir.x * fall_off,
                p.y + drag_dir.y * fall_off,
                p.z + drag_dir.z * fall_off,
            ),
        )


def tool_scale(
    mut mesh: SculptorMesh,
    vertices: List[Int],
    center: Point3,
    radius_sq: Float64,
    delta_scale: Float64,
):
    """Move the vertices away from the center, or toward it, three.js's
    `toolScale`.

    Args:
        mesh: The mesh to change.
        vertices: The vertices in the brush.
        center: The brush's center.
        radius_sq: The brush's squared radius.
        delta_scale: How far: a hundredth of the distance per unit, away
            when positive.
    """
    var radius = sqrt(radius_sq)
    var scale = delta_scale * 0.01
    for vertex in vertices:  # pragma: no branch
        var p = point_of(mesh.vertices, vertex)
        var dx = p.x - center.x
        var dy = p.y - center.y
        var dz = p.z - center.z
        var fall_off = falloff(sqrt(dx * dx + dy * dy + dz * dz) / radius) * scale
        _set_point(
            mesh.vertices,
            vertex,
            Point3(p.x + dx * fall_off, p.y + dy * fall_off, p.z + dz * fall_off),
        )
