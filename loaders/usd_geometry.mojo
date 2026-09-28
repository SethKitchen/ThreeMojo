# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A USD mesh's geometry, from three.js r186's
`examples/jsm/loaders/usd/USDComposer.js`: `_buildGeometry`,
`_buildGeometryWithSubsets` and the triangulation they share.

`build_usd_geometry` turns a mesh's arrays into a `BufferGeometry` with no
index, as three.js's `_buildGeometry` does. Each face is cut into
triangles: a triangle as it is, a quad into two, a face of more corners by
earcut after it is projected onto its plane, and a face with holes, which
Arnold's `primvars:arnold:polygon_holes` names, by earcut with the holes.
The cut is kept as a pattern of face corners, so normals and texture
coordinates that are given for each face corner follow the same cut. A
mesh with no normals gets the normals of its shared vertices.
`build_usd_geometry_with_subsets` does the same for a mesh with
`GeomSubset`s, and sorts the triangles into one group for each subset,
as three.js's `_buildGeometryWithSubsets` does.

**The numbers.** A number is a `Float64`, as a JavaScript number is. A
place that JavaScript reads as `undefined`, past a list or at a place
that is not a whole number, is NaN, and a `Float32Array` stores NaN
there too. `value_at` reads so.

**What is refused.** Where three.js throws: faces with no corner indices,
and a mesh with neither normals nor corners to compute them from. And
where this port holds less: points or attributes that are not whole
vertices, face counts whose triangle count is not whole, and a face of
more than 2^24 corners.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
    UV1,
)
from geometries.earcut import triangulate_shape
from std.math import nan, sqrt

# The most corners a face may have before the reader refuses it.
comptime MAX_CORNERS = 1 << 24


struct UsdArray(Copyable, Movable):
    """An array attribute of a mesh as the composer reads it: there or
    not, as JavaScript's truthiness says, and its numbers."""

    var present: Bool
    var values: List[Float64]

    def __init__(out self):
        """Make an array that is not there."""
        self.present = False
        self.values = List[Float64]()

    def __init__(out self, var values: List[Float64]):
        """Make an array that is there.

        Args:
            values: Its numbers.
        """
        self.present = True
        self.values = values^

    def filled(self) -> Bool:
        """Return `array && array.length > 0`.

        Returns:
            Whether it is there and not empty.
        """
        return self.present and len(self.values) > 0


struct UsdMeshArrays(Copyable, Movable):
    """The arrays of a mesh that its geometry is built from, each one
    what three.js reads from the mesh's attributes."""

    var points: UsdArray
    # `faceVertexIndices` and `faceVertexCounts`.
    var indices: UsdArray
    var counts: UsdArray
    # `primvars:arnold:polygon_holes`: a hole face, then its parent face.
    var holes: UsdArray
    var normals: UsdArray
    var normal_indices: UsdArray
    # The first set of texture coordinates and the second, `st1`.
    var uvs: UsdArray
    var uv_indices: UsdArray
    var uvs2: UsdArray
    var uv2_indices: UsdArray

    def __init__(out self):
        """Make a mesh with no arrays."""
        self.points = UsdArray()
        self.indices = UsdArray()
        self.counts = UsdArray()
        self.holes = UsdArray()
        self.normals = UsdArray()
        self.normal_indices = UsdArray()
        self.uvs = UsdArray()
        self.uv_indices = UsdArray()
        self.uvs2 = UsdArray()
        self.uv2_indices = UsdArray()


def value_at(values: List[Float64], index: Float64) -> Float64:
    """Return `values[ index ]` as a `Float32Array` stores it.

    Args:
        values: The list.
        index: The place.

    Returns:
        The value, or NaN when the place is not a whole number in the list.
    """
    var inside = index >= 0 and index < Float64(len(values))
    if inside and index == Float64(Int(index)):
        return values[Int(index)]
    return nan[DType.float64]()


def _loop_count(count: Float64) raises -> Int:
    """Return how many times `for ( j = 0; j < count; j ++ )` runs.

    Args:
        count: The bound.

    Returns:
        The count of whole numbers below it from zero.

    Raises:
        Error: If it is past `MAX_CORNERS`.
    """
    if not (count > 0):
        return 0
    if count > Float64(MAX_CORNERS):
        raise Error("USD: a face of more than 2^24 corners")
    var whole = Int(count)
    return whole + 1 if Float64(whole) < count else whole


def _identity(length: Float64) raises -> List[Float64]:
    """Return `Array.from( { length }, ( _, i ) => i )`.

    Args:
        length: The length, cut to a whole number, and zero for NaN.

    Returns:
        Zero, one, two and on.

    Raises:
        Error: If it is past `MAX_CORNERS`.
    """
    var out = List[Float64]()
    for i in range(_loop_count(Float64(Int(length)) if length > 0 else 0)):
        out.append(Float64(i))
    return out^


struct HoleMap(Copyable, Movable):
    """three.js's `_buildHoleMap`: the holes of each parent face, and
    which faces are holes."""

    var parents: List[Float64]
    var holes: List[List[Float64]]
    var hole_faces: List[Float64]

    def __init__(out self):
        """Make a map with no holes."""
        self.parents = List[Float64]()
        self.holes = List[List[Float64]]()
        self.hole_faces = List[Float64]()

    def is_hole(self, face: Int) -> Bool:
        """Return `holeFaces.has( face )`.

        Args:
            face: The face.

        Returns:
            Whether it is a hole.
        """
        for hole in self.hole_faces:
            if hole == Float64(face):
                return True
        return False

    def holes_of(self, face: Int) -> List[Float64]:
        """Return `parentToHoles.get( face )`.

        Args:
            face: The face.

        Returns:
            Its holes, none when it has none.
        """
        for k in range(len(self.parents)):
            if self.parents[k] == Float64(face):
                return self.holes[k].copy()
        return List[Float64]()


def build_hole_map(holes: UsdArray) -> HoleMap:
    """Read Arnold's hole pairs, three.js's `_buildHoleMap`.

    Args:
        holes: A hole face, then its parent face, for each hole. A last
            hole with no parent has a NaN parent, which no face is.

    Returns:
        The map.
    """
    var out = HoleMap()
    if not holes.filled():
        return out^
    var i = 0
    while i < len(holes.values):
        var hole = holes.values[i]
        var parent = value_at(holes.values, Float64(i + 1))
        out.hole_faces.append(hole)
        var at = -1
        for k in range(len(out.parents)):
            # A `Map` finds NaN by NaN.
            var same = out.parents[k] == parent or (
                out.parents[k] != out.parents[k] and parent != parent
            )
            if same:
                at = k
        if at < 0:
            out.parents.append(parent)
            out.holes.append(List[Float64]())
            at = len(out.parents) - 1
        out.holes[at].append(hole)
        i += 2
    return out^


struct Triangulation(Movable):
    """What `triangulate_with_pattern` gives: the corners of each triangle
    as point indices, and as the face corners they came from."""

    var indices: List[Float64]
    var pattern: List[Float64]

    def __init__(out self):
        """Make an empty triangulation."""
        self.indices = List[Float64]()
        self.pattern = List[Float64]()


def _project(
    face: List[Float64], points: List[Float64]
) -> Tuple[List[Float64], List[Float64]]:
    """Return the plane a face projects onto: its tangent and bitangent,
    three.js's Newell normal and basis.

    Args:
        face: The face's point indices.
        points: The points, three numbers each.

    Returns:
        The tangent and the bitangent, three numbers each.
    """
    var n = len(face)
    var nx = Float64(0)
    var ny = Float64(0)
    var nz = Float64(0)
    # A face has a corner at least.
    for i in range(n):  # pragma: no branch
        var a = face[i]
        var b = face[(i + 1) % n]
        var ax = value_at(points, a * 3)
        var ay = value_at(points, a * 3 + 1)
        var az = value_at(points, a * 3 + 2)
        var bx = value_at(points, b * 3)
        var by = value_at(points, b * 3 + 1)
        var bz = value_at(points, b * 3 + 2)
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    var normal = _normalized(nx, ny, nz)
    var tx = Float64(1) if abs(normal[1]) > 0.9 else Float64(0)
    var ty = Float64(0) if abs(normal[1]) > 0.9 else Float64(1)
    var tz = Float64(0)
    # bitangent = normal x tangent, tangent = bitangent x normal.
    var bitangent = _normalized(
        normal[1] * tz - normal[2] * ty,
        normal[2] * tx - normal[0] * tz,
        normal[0] * ty - normal[1] * tx,
    )
    var tangent = _normalized(
        bitangent[1] * normal[2] - bitangent[2] * normal[1],
        bitangent[2] * normal[0] - bitangent[0] * normal[2],
        bitangent[0] * normal[1] - bitangent[1] * normal[0],
    )
    return (tangent^, bitangent^)


def _normalized(x: Float64, y: Float64, z: Float64) -> List[Float64]:
    """Return three.js's `Vector3.normalize`: divided by its length, or by
    one when the length is zero or NaN.

    Args:
        x: The first number.
        y: The second.
        z: The third.

    Returns:
        The vector.
    """
    var length = sqrt(x * x + y * y + z * z)
    if not (length != 0 and length == length):
        length = 1
    return [x / length, y / length, z / length]


def _flat_2d(
    face: List[Float64],
    points: List[Float64],
    tangent: List[Float64],
    bitangent: List[Float64],
) -> List[Float64]:
    """Return a face's points on its plane, x then y for each.

    Args:
        face: The face's point indices.
        points: The points, three numbers each.
        tangent: The plane's first axis.
        bitangent: Its second.

    Returns:
        The projected points.
    """
    var out = List[Float64]()
    for index in face:
        var x = value_at(points, index * 3)
        var y = value_at(points, index * 3 + 1)
        var z = value_at(points, index * 3 + 2)
        out.append(x * tangent[0] + y * tangent[1] + z * tangent[2])
        out.append(x * bitangent[0] + y * bitangent[1] + z * bitangent[2])
    return out^


def triangulate_ngon(
    face: List[Float64], points: List[Float64]
) raises -> List[Float64]:
    """Cut a face of more than four corners, three.js's `_triangulateNGon`:
    it is projected onto the plane of its Newell normal and cut by earcut.

    Args:
        face: The face's point indices.
        points: The points, three numbers each.

    Returns:
        Three point indices for each triangle.

    Raises:
        Error: If earcut refuses the points.
    """
    var basis = _project(face, points)
    var flat = _flat_2d(face, points, basis[0], basis[1])
    var out = List[Float64]()
    for index in triangulate_shape(flat):
        out.append(face[index])
    return out^


def triangulate_ngon_with_holes(
    outer: List[Float64], holes: List[List[Float64]], points: List[Float64]
) raises -> List[Float64]:
    """Cut a face with holes, three.js's `_triangulateNGonWithHoles`.

    Args:
        outer: The face's point indices.
        holes: Each hole's point indices.
        points: The points, three numbers each.

    Returns:
        Three point indices for each triangle, from the face's and the
        holes' points.

    Raises:
        Error: If earcut refuses the points.
    """
    var basis = _project(outer, points)
    var flat_holes = List[List[Float64]]()
    var all = outer.copy()
    for hole in holes:
        flat_holes.append(_flat_2d(hole, points, basis[0], basis[1]))
        all.extend(hole.copy())
    var out = List[Float64]()
    var flat = _flat_2d(outer, points, basis[0], basis[1])
    for index in triangulate_shape(flat, flat_holes):
        out.append(value_at(all, Float64(index)))
    return out^


def _index_of(values: List[Float64], value: Float64) -> Float64:
    """Return `values.indexOf( value )`: NaN is never found.

    Args:
        values: The list.
        value: The value.

    Returns:
        The first place, or -1.
    """
    for k in range(len(values)):
        if values[k] == value:
            return Float64(k)
    return -1


struct _CornerMap(Movable):
    """A `Map` from a point index to a face corner: NaN finds NaN, and a
    key set again keeps its place."""

    var keys: List[Float64]
    var corners: List[Float64]

    def __init__(out self):
        """Make an empty map."""
        self.keys = List[Float64]()
        self.corners = List[Float64]()

    def find(self, key: Float64) -> Int:
        """Return where a key is.

        Args:
            key: The key.

        Returns:
            Its place, or -1.
        """
        for k in range(len(self.keys)):
            if self.keys[k] == key or (
                self.keys[k] != self.keys[k] and key != key
            ):
                return k
        return -1

    def set(mut self, key: Float64, corner: Float64):
        """Set a key's corner.

        Args:
            key: The point index.
            corner: The face corner.
        """
        var at = self.find(key)
        if at < 0:
            self.keys.append(key)
            self.corners.append(corner)
        else:
            self.corners[at] = corner

    def get(self, key: Float64) -> Float64:
        """Return a key's corner.

        Args:
            key: The point index.

        Returns:
            The corner. Every key asked for is set.
        """
        return self.corners[self.find(key)]


def triangulate_with_pattern(
    indices: List[Float64],
    counts: List[Float64],
    points: List[Float64],
    hole_map: HoleMap,
) raises -> Triangulation:
    """Cut faces into triangles, three.js's
    `_triangulateIndicesWithPattern`.

    Args:
        indices: `faceVertexIndices`.
        counts: `faceVertexCounts`.
        points: The points, three numbers each.
        hole_map: Which faces are holes of which.

    Returns:
        The triangles' point indices, and the face corner each came from.

    Raises:
        Error: If a face has more than 2^24 corners, or earcut refuses a
            face.
    """
    var offsets = List[Float64]()
    var sum = Float64(0)
    for count in counts:
        offsets.append(sum)
        sum += count
    var out = Triangulation()
    var offset = Float64(0)
    for i in range(len(counts)):
        var count = counts[i]
        if hole_map.is_hole(i):
            offset += count
            continue
        var holes = hole_map.holes_of(i)
        if len(holes) > 0 and len(points) > 0:
            var corners = _CornerMap()
            var face = List[Float64]()
            for j in range(_loop_count(count)):
                var vertex = value_at(indices, offset + Float64(j))
                face.append(vertex)
                corners.set(vertex, offset + Float64(j))
            var contours = List[List[Float64]]()
            for hole in holes:  # pragma: no branch
                var start = value_at(offsets, hole)
                var contour = List[Float64]()
                for j in range(_loop_count(value_at(counts, hole))):
                    var vertex = value_at(indices, start + Float64(j))
                    contour.append(vertex)
                    corners.set(vertex, start + Float64(j))
                contours.append(contour^)
            # A face of no corners has no triangles: earcut finds no
            # outline.
            if len(face) > 0:
                for vertex in triangulate_ngon_with_holes(
                    face, contours, points
                ):
                    out.indices.append(vertex)
                    out.pattern.append(corners.get(vertex))
        elif count == 3 or count == 4:
            var order: List[Int] = [0, 1, 2] if count == 3 else [
                0,
                1,
                2,
                0,
                2,
                3,
            ]
            for k in order:  # pragma: no branch
                out.indices.append(value_at(indices, offset + Float64(k)))
                out.pattern.append(offset + Float64(k))
        elif count > 4:
            var corners = _loop_count(count)
            if len(points) > 0:
                var face = List[Float64]()
                for j in range(corners):  # pragma: no branch
                    face.append(value_at(indices, offset + Float64(j)))
                for vertex in triangulate_ngon(face, points):
                    out.indices.append(vertex)
                    out.pattern.append(offset + _index_of(face, vertex))
            else:
                for j in range(1, corners - 1):  # pragma: no branch
                    for k in [0, j, j + 1]:  # pragma: no branch
                        out.indices.append(
                            value_at(indices, offset + Float64(k))
                        )
                        out.pattern.append(offset + Float64(k))
        offset += count
    return out^


def apply_pattern(
    indices: List[Float64], pattern: List[Float64]
) -> List[Float64]:
    """Pick the face corners a triangulation kept, three.js's
    `_applyTriangulationPattern`.

    Args:
        indices: One value for each face corner.
        pattern: The face corner of each triangle corner.

    Returns:
        The value of each triangle corner.
    """
    var out = List[Float64](capacity=len(pattern))
    for corner in pattern:
        out.append(value_at(indices, corner))
    return out^


def expand_attribute(
    data: List[Float64], indices: List[Float64], size: Int
) -> List[Float64]:
    """Give each index its item, three.js's `_expandAttribute`.

    Args:
        data: The items end to end.
        indices: The item of each vertex.
        size: Numbers an item.

    Returns:
        The items, end to end.
    """
    var out = List[Float64](capacity=len(indices) * size)
    for index in indices:
        for j in range(size):  # pragma: no branch
            out.append(value_at(data, index * Float64(size) + Float64(j)))
    return out^


def _whole_vertices(length: Int) raises -> Int:
    """Return how many vertices of three numbers a list holds.

    Args:
        length: The list's length.

    Returns:
        The count.

    Raises:
        Error: If the length is not a multiple of three, which a
            `Float32Array` cannot be made of.
    """
    if length % 3 != 0:
        raise Error("USD: points that are not whole vertices")
    return length // 3


def compute_vertex_normals(
    points: List[Float64], indices: List[Float64]
) raises -> List[Float64]:
    """Sum each triangle's normal onto its corners' points and normalize
    them, three.js's `_computeVertexNormals`.

    A triangle's normal is the cross product of its edges, so a larger
    triangle counts for more. Each sum is held as a `Float32Array` holds
    it. A corner that names no point adds to nothing.

    Args:
        points: The points, three numbers each.
        indices: Three point indices for each triangle.

    Returns:
        A normal for each point, three numbers each.

    Raises:
        Error: If the points are not whole vertices.
    """
    var count = _whole_vertices(len(points))
    var normals = List[Float32](length=count * 3, fill=0)
    var i = 0
    while i < len(indices):
        var corners: List[Float64] = [
            value_at(indices, Float64(i)),
            value_at(indices, Float64(i + 1)),
            value_at(indices, Float64(i + 2)),
        ]
        var p = List[Float64]()
        for corner in corners:  # pragma: no branch
            for k in range(3):  # pragma: no branch
                p.append(value_at(points, corner * 3 + Float64(k)))
        var e1x = p[3] - p[0]
        var e1y = p[4] - p[1]
        var e1z = p[5] - p[2]
        var e2x = p[6] - p[0]
        var e2y = p[7] - p[1]
        var e2z = p[8] - p[2]
        var n: List[Float64] = [
            e1y * e2z - e1z * e2y,
            e1z * e2x - e1x * e2z,
            e1x * e2y - e1y * e2x,
        ]
        for corner in corners:  # pragma: no branch
            var inside = corner >= 0 and corner < Float64(count)
            if inside and corner == Float64(Int(corner)):
                for k in range(3):  # pragma: no branch
                    var at = Int(corner) * 3 + k
                    normals[at] = Float32(Float64(normals[at]) + n[k])
        i += 3
    var out = List[Float64](capacity=count * 3)
    for v in range(count):
        var x = Float64(normals[v * 3])
        var y = Float64(normals[v * 3 + 1])
        var z = Float64(normals[v * 3 + 2])
        var length = sqrt(x * x + y * y + z * z)
        if length > 0:
            x = Float64(Float32(x / length))
            y = Float64(Float32(y / length))
            z = Float64(Float32(z / length))
        out.append(x)
        out.append(y)
        out.append(z)
    return out^


def _attribute(values: List[Float64], size: Int) raises -> BufferAttribute:
    """Return a `Float32Array` attribute.

    Args:
        values: The numbers.
        size: Numbers a vertex.

    Returns:
        The attribute.

    Raises:
        Error: If the numbers are not whole vertices.
    """
    var floats = List[Float32](capacity=len(values))
    for value in values:
        floats.append(Float32(value))
    return BufferAttribute(floats^, size)


def _coordinates(
    uvs: UsdArray,
    uv_indices: UsdArray,
    pattern: Optional[List[Float64]],
    indices: UsdArray,
    points: Int,
    face_vertices: Int,
) raises -> List[Float64]:
    """Return a set of texture coordinates for each triangle corner, as
    `_buildGeometry` reads `uv` and `uv1`.

    Args:
        uvs: The coordinates.
        uv_indices: Their indices, one for each face corner.
        pattern: The triangulation's face corners, when there are faces.
        indices: The corners' point indices.
        points: The count of points.
        face_vertices: The count of face corners.

    Returns:
        The coordinates: by their indices, by the points, by the face
        corners, or as they are, in that order of choice.

    Raises:
        Error: If the identity is too long.
    """
    if uv_indices.filled() and pattern:
        return expand_attribute(
            uvs.values, apply_pattern(uv_indices.values, pattern.value()), 2
        )
    var pairs = Float64(len(uvs.values)) / 2
    if indices.present and pairs == Float64(points) / 3:
        return expand_attribute(uvs.values, indices.values, 2)
    if pattern and pairs == Float64(face_vertices):
        var corners = apply_pattern(
            _identity(Float64(face_vertices)), pattern.value()
        )
        return expand_attribute(uvs.values, corners, 2)
    return uvs.values.copy()


def build_usd_geometry(mesh: UsdMeshArrays) raises -> BufferGeometry:
    """Build a mesh's geometry, three.js's `_buildGeometry`.

    Args:
        mesh: The mesh's arrays.

    Returns:
        The geometry: `position`, `normal`, and `uv` and `uv1` when the
        mesh has them. It is empty when the mesh has no points.

    Raises:
        Error: For anything the module docstring lists.
    """
    var geometry = BufferGeometry()
    if not mesh.points.filled():
        return geometry^
    var points = mesh.points.values.copy()
    var hole_map = build_hole_map(mesh.holes)
    var indices = UsdArray()
    if mesh.indices.present:
        indices = UsdArray(mesh.indices.values.copy())
    var pattern: Optional[List[Float64]] = None
    if mesh.counts.filled():
        if not mesh.indices.present:
            raise Error("USD: faces with no corner indices")
        var cut = triangulate_with_pattern(
            mesh.indices.values, mesh.counts.values, points, hole_map
        )
        indices = UsdArray(cut.indices.copy())
        pattern = cut.pattern.copy()
    var positions = points.copy()
    if indices.filled():
        positions = expand_attribute(points, indices.values, 3)
    geometry.set_attribute(String(POSITION), _attribute(positions, 3))
    if mesh.normals.filled():
        var normals = mesh.normals.values.copy()
        if mesh.normal_indices.filled() and pattern:
            normals = expand_attribute(
                mesh.normals.values,
                apply_pattern(mesh.normal_indices.values, pattern.value()),
                3,
            )
        elif len(mesh.normals.values) == len(points):
            if indices.filled():
                normals = expand_attribute(
                    mesh.normals.values, indices.values, 3
                )
        elif pattern:
            var corners = apply_pattern(
                _identity(Float64(len(mesh.normals.values)) / 3),
                pattern.value(),
            )
            normals = expand_attribute(mesh.normals.values, corners, 3)
        geometry.set_attribute(String(NORMAL), _attribute(normals, 3))
    else:
        if not indices.present:
            raise Error("USD: a mesh with no normals and no corners")
        var computed = compute_vertex_normals(points, indices.values)
        geometry.set_attribute(
            String(NORMAL),
            _attribute(expand_attribute(computed, indices.values, 3), 3),
        )
    var face_vertices = len(mesh.indices.values) if mesh.indices.present else 0
    if mesh.uvs.filled():
        var uvs = _coordinates(
            mesh.uvs,
            mesh.uv_indices,
            pattern,
            indices,
            len(points),
            face_vertices,
        )
        geometry.set_attribute(String(UV), _attribute(uvs, 2))
    if mesh.uvs2.filled():
        var uvs = _coordinates(
            mesh.uvs2,
            mesh.uv2_indices,
            pattern,
            indices,
            len(points),
            face_vertices,
        )
        geometry.set_attribute(String(UV1), _attribute(uvs, 2))
    return geometry^


def _triangle_count(
    counts: List[Float64], hole_map: HoleMap
) raises -> Tuple[Int, List[Float64]]:
    """Count the triangles of each face as `_buildGeometryWithSubsets`
    does: a face of `n` corners and its holes' corners gives `n - 2`.

    Args:
        counts: `faceVertexCounts`.
        hole_map: Which faces are holes of which.

    Returns:
        The count, and the first triangle of each face.

    Raises:
        Error: If the count is negative or not whole.
    """
    var starts = List[Float64]()
    var total = Float64(0)
    for i in range(len(counts)):  # pragma: no branch
        starts.append(total)
        if hole_map.is_hole(i):
            continue
        var count = counts[i]
        var holes = hole_map.holes_of(i)
        if len(holes) > 0:
            var corners = count
            for hole in holes:  # pragma: no branch
                corners += value_at(counts, hole)
            total += corners - 2
        elif count >= 3:
            total += count - 2
    if total != total:
        # `new Int32Array( NaN )` is empty.
        total = 0
    if total < 0 or total != Float64(Int(total)):
        raise Error("USD: face counts whose triangle count is not whole")
    return (Int(total), starts^)


def build_usd_geometry_with_subsets(
    mesh: UsdMeshArrays, subsets: List[List[Float64]]
) raises -> BufferGeometry:
    """Build a mesh's geometry with a group for each subset, three.js's
    `_buildGeometryWithSubsets`.

    The triangles are sorted by their subset, those of no subset first,
    and each subset's run is a group whose material index is the
    subset's place.

    Args:
        mesh: The mesh's arrays.
        subsets: Each subset's face indices.

    Returns:
        The geometry: `position` and `normal`, and `uv` and `uv1` when the
        mesh has them. It is empty when the mesh has no points or faces.

    Raises:
        Error: For anything the module docstring lists.
    """
    var geometry = BufferGeometry()
    if not mesh.points.filled() or not mesh.counts.filled():
        return geometry^
    ref points = mesh.points.values
    ref counts = mesh.counts.values
    var hole_map = build_hole_map(mesh.holes)
    var counted = _triangle_count(counts, hole_map)
    var triangles = counted[0]
    ref starts = counted[1]
    var owner = List[Int](length=triangles, fill=-1)
    for s in range(len(subsets)):
        for face in subsets[s]:
            if face >= Float64(len(counts)):
                continue
            # A face's first triangle is a whole number from zero, as the
            # count is. A hole face's triangles can run past the last.
            for t in range(_loop_count(value_at(counts, face) - 2)):
                var at = Int(value_at(starts, face)) + t
                if at < triangles:
                    owner[at] = s
    # A stable sort by subset, as JavaScript's sort is.
    var order = List[Int]()
    for s in range(-1, len(subsets)):  # pragma: no branch
        for t in range(triangles):
            if owner[t] == s:
                order.append(t)
    if len(order) > 0:
        var current = owner[order[0]]
        var start = 0
        for i in range(len(order)):  # pragma: no branch
            if owner[order[i]] != current:
                if current >= 0:
                    geometry.add_group(
                        start * 3, (i - start) * 3, MaterialIndex(current)
                    )
                current = owner[order[i]]
                start = i
        if current >= 0:
            geometry.add_group(
                start * 3, (len(order) - start) * 3, MaterialIndex(current)
            )
    if not mesh.indices.present:
        raise Error("USD: faces with no corner indices")
    var cut = triangulate_with_pattern(
        mesh.indices.values, counts, points, hole_map
    )
    var face_vertices = Float64(0)
    for count in counts:  # pragma: no branch
        face_vertices += count
    var identity = List[Float64]()
    var uv_identity = (
        mesh.uvs.present
        and not mesh.uv_indices.present
        and Float64(len(mesh.uvs.values)) / 2 == face_vertices
    ) or (
        mesh.uvs2.present
        and not mesh.uv2_indices.present
        and Float64(len(mesh.uvs2.values)) / 2 == face_vertices
    )
    if uv_identity:
        identity = apply_pattern(_identity(face_vertices), cut.pattern)
    var uv_corners = _subset_corners(
        mesh.uvs, mesh.uv_indices, cut.pattern, identity, face_vertices
    )
    var uv2_corners = _subset_corners(
        mesh.uvs2, mesh.uv2_indices, cut.pattern, identity, face_vertices
    )
    var normal_corners: Optional[List[Float64]] = None
    if mesh.normals.present and mesh.normal_indices.filled():
        normal_corners = apply_pattern(mesh.normal_indices.values, cut.pattern)
    elif (
        mesh.normals.present
        and Float64(len(mesh.normals.values)) / 3 == face_vertices
    ):
        normal_corners = apply_pattern(_identity(face_vertices), cut.pattern)
    var computed = List[Float64]()
    var has_computed = not mesh.normals.present and len(cut.indices) > 0
    if has_computed:
        computed = compute_vertex_normals(points, cut.indices)
    if not mesh.normals.present and not has_computed:
        raise Error("USD: a mesh with no normals and no corners")
    var count = triangles * 3
    var positions = List[Float64](length=count * 3, fill=0)
    var uvs = List[Float64](length=count * 2, fill=0)
    var uvs2 = List[Float64](length=count * 2, fill=0)
    var normals = List[Float64](length=count * 3, fill=0)
    var per_point_uvs = (
        Float64(len(mesh.uvs.values)) / 2 == Float64(len(points)) / 3
    )
    var per_point_uvs2 = (
        Float64(len(mesh.uvs2.values)) / 2 == Float64(len(points)) / 3
    )
    var per_point_normals = len(mesh.normals.values) == len(points)
    var normal_data = (
        mesh.normals.values.copy() if mesh.normals.present else computed.copy()
    )
    for i in range(len(order)):
        for v in range(3):  # pragma: no branch
            var original = Float64(order[i] * 3 + v)
            var vertex = i * 3 + v
            var point = value_at(cut.indices, original)
            for k in range(3):  # pragma: no branch
                positions[vertex * 3 + k] = value_at(
                    points, point * 3 + Float64(k)
                )
            _corner_pair(
                uvs,
                vertex,
                mesh.uvs,
                uv_corners,
                per_point_uvs,
                original,
                point,
            )
            _corner_pair(
                uvs2,
                vertex,
                mesh.uvs2,
                uv2_corners,
                per_point_uvs2,
                original,
                point,
            )
            var source = point
            if mesh.normals.present and normal_corners:
                source = value_at(normal_corners.value(), original)
            var sourced = (
                (mesh.normals.present and normal_corners)
                or (mesh.normals.present and per_point_normals)
                or has_computed
            )
            if sourced:
                for k in range(3):  # pragma: no branch
                    normals[vertex * 3 + k] = value_at(
                        normal_data, source * 3 + Float64(k)
                    )
    geometry.set_attribute(String(POSITION), _attribute(positions, 3))
    if mesh.uvs.present:
        geometry.set_attribute(String(UV), _attribute(uvs, 2))
    if mesh.uvs2.present:
        geometry.set_attribute(String(UV1), _attribute(uvs2, 2))
    geometry.set_attribute(String(NORMAL), _attribute(normals, 3))
    return geometry^


def _subset_corners(
    uvs: UsdArray,
    uv_indices: UsdArray,
    pattern: List[Float64],
    identity: List[Float64],
    face_vertices: Float64,
) -> Optional[List[Float64]]:
    """Return which coordinate each triangle corner of a subset mesh
    takes: `origUvIndices` of `_buildGeometryWithSubsets`.

    Args:
        uvs: The coordinates.
        uv_indices: Their indices.
        pattern: The triangulation's face corners.
        identity: The face corners of each triangle corner.
        face_vertices: The count of face corners.

    Returns:
        The coordinate of each triangle corner, or nothing when the
        coordinates are by point or not there.
    """
    if uv_indices.present:
        return apply_pattern(uv_indices.values, pattern)
    if uvs.present and Float64(len(uvs.values)) / 2 == face_vertices:
        return identity.copy()
    return None


def _corner_pair(
    mut out: List[Float64],
    vertex: Int,
    uvs: UsdArray,
    corners: Optional[List[Float64]],
    per_point: Bool,
    original: Float64,
    point: Float64,
):
    """Set one triangle corner's texture coordinates in a subset mesh.

    Args:
        out: The coordinates being built.
        vertex: The triangle corner's place.
        uvs: The coordinates.
        corners: Which coordinate each original triangle corner takes.
        per_point: Whether there is one coordinate for each point.
        original: The triangle corner's place before sorting.
        point: Its point.
    """
    if not uvs.present or not (corners or per_point):
        return
    var source = value_at(corners.value(), original) if corners else point
    out[vertex * 2] = value_at(uvs.values, source * 2)
    out[vertex * 2 + 1] = value_at(uvs.values, source * 2 + 1)
