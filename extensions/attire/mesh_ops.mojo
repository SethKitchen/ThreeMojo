# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Mesh operations that garments are cut and joined with.

- `weld_groups` finds the vertices that share one position. A mesh that
  was parted, as the legs are, holds copies of a vertex.
- `vertex_neighbors` lists the welded neighbors of each vertex.
- `cut` keeps the part of a mesh where a value per vertex is at or above
  a level. A triangle that crosses the level is clipped, so the cut runs
  along the level's iso-line and not along the triangles' edges. Every
  attribute is carried to the new vertices by linear interpolation. Skin
  weights are merged, and the four heaviest bones are kept.
- `cut_attribute` cuts at a level of one of the mesh's own attributes, so
  a band between two levels is two cuts, each along a straight iso-line.
- `merge` joins two meshes that have the same attributes.
- `keep_triangles` drops the triangles a mask refuses.
- `normalize_normals` scales interpolated normals back to unit length.
- `top_four` keeps the four heaviest bones of a weight per bone.
- `add_rim` gives each open edge a rim, so a hem shows its thickness.
- `MeshWriter` writes a mesh with another mesh's attributes, vertex by
  vertex, so the two can be merged.

This is not a three.js port. See Extensions.

    var hemmed = cut(shell, cover, 0.5)
"""

from std.memory import bitcast

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.search import first_match
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime COVER = "cover"
"""The name of the attribute that carries each vertex's cover value."""
comptime ACCENT = "accent"
"""The name of the attribute that marks a hat's stones, horns and feather,
which take the accent dye: one there, zero elsewhere."""


def _bits(value: Float32) -> Int:
    """Return the bit pattern of a float, as a non-negative integer."""
    return Int(bitcast[DType.uint32](value))


def weld_groups(geometry: BufferGeometry) raises -> List[Int]:
    """Return, for each vertex, the first vertex at exactly its position.

    Args:
        geometry: A mesh with positions.

    Returns:
        One entry per vertex. A vertex with no earlier copy names itself.

    Raises:
        Error: If the mesh has no positions.
    """
    ref points = geometry.attribute_view(String(POSITION))
    # Keyed by the exact bit patterns, so two keys are one position.
    var first = Dict[String, Int]()
    var groups = List[Int](capacity=points.count())
    for v in range(points.count()):
        var p = points.vector3(v)
        var key = String(_bits(p.x), " ", _bits(p.y), " ", _bits(p.z))
        groups.append(first.setdefault(key, v))
    return groups^


def vertex_neighbors(
    geometry: BufferGeometry, groups: List[Int]
) raises -> List[List[Int]]:
    """Return the welded neighbors of each welded vertex.

    Args:
        geometry: A mesh with positions, indexed or not.
        groups: Its `weld_groups`.

    Returns:
        One list per vertex. A vertex that is its group's first holds the
        group's neighbors, each named by its group's first vertex. Any
        other vertex holds an empty list.

    Raises:
        Error: If `groups` is not one entry per vertex, or a triangle
            names a vertex the mesh does not have.
    """
    var count = geometry.vertex_count()
    if len(groups) != count:
        raise Error("Weld groups must be one entry per vertex")
    var neighbors = List[List[Int]](capacity=count)
    for _ in range(count):
        neighbors.append(List[Int]())
    for t in range(geometry.triangle_count()):
        var corners = List[Int](capacity=3)
        for c in range(3):  # pragma: no branch
            corners.append(groups[geometry.corner_index(t, c)])
        for c in range(3):  # pragma: no branch
            var a = corners[c]
            var b = corners[(c + 1) % 3]
            if a == b:
                continue
            if b not in neighbors[a]:
                neighbors[a].append(b)
            if a not in neighbors[b]:
                neighbors[b].append(a)
    return neighbors^


struct _Carrier(Movable):
    """The attributes of a mesh, read once, and the ones being written."""

    var names: List[String]
    var sizes: List[Int]
    var source: List[List[Float32]]
    var out: List[List[Float32]]
    var skin_at: Int
    var weight_at: Int

    def __init__(out self, geometry: BufferGeometry) raises:
        """Read every attribute of `geometry`.

        Args:
            geometry: The mesh to carry from.

        Raises:
            Error: If an attribute cannot be read.
        """
        self.names = geometry.names.copy()
        self.sizes = List[Int]()
        self.source = List[List[Float32]]()
        self.out = List[List[Float32]]()
        self.skin_at = -1
        self.weight_at = -1
        for k in range(len(self.names)):  # pragma: no branch
            ref attribute = geometry.attribute_view(self.names[k])
            self.sizes.append(attribute.item_size)
            self.source.append(attribute.packed())
            self.out.append(List[Float32]())
            if self.names[k] == String(SKIN_INDEX):
                self.skin_at = k
            elif self.names[k] == String(SKIN_WEIGHT):
                self.weight_at = k

    def copy_vertex(mut self, v: Int):
        """Append vertex `v` unchanged.

        Args:
            v: The source vertex.
        """
        for k in range(len(self.names)):  # pragma: no branch
            var size = self.sizes[k]
            for c in range(size):  # pragma: no branch
                self.out[k].append(self.source[k][v * size + c])

    def mix_vertex(mut self, a: Int, b: Int, t: Float32):
        """Append the vertex `t` of the way from `a` to `b`.

        Args:
            a: The first source vertex.
            b: The second source vertex.
            t: How far toward `b`, zero through one.
        """
        var skinned = self.skin_at >= 0 and self.weight_at >= 0
        for k in range(len(self.names)):  # pragma: no branch
            if skinned and (k == self.skin_at or k == self.weight_at):
                continue
            var size = self.sizes[k]
            for c in range(size):  # pragma: no branch
                var x = self.source[k][a * size + c]
                var y = self.source[k][b * size + c]
                self.out[k].append(x + (y - x) * t)
        if skinned:
            self._mix_skin(a, b, t)

    def _mix_skin(mut self, a: Int, b: Int, t: Float32):
        """Append merged skin weights: the four heaviest bones of both."""
        var bones = List[Int]()
        var weights = List[Float32]()
        for k in range(8):  # pragma: no branch
            var v = a
            var share = 1 - t
            if k >= 4:
                v = b
                share = t
            var c = k % 4
            var bone = Int(self.source[self.skin_at][v * 4 + c])
            var weight = self.source[self.weight_at][v * 4 + c] * share
            var at = -1
            for i in range(len(bones)):
                if bones[i] == bone:
                    at = i
            if at < 0:
                bones.append(bone)
                weights.append(weight)
            else:
                weights[at] += weight
        var kept = Float32(0)
        var chosen = List[Int]()
        for _ in range(4):  # pragma: no branch
            var best = -1
            var heaviest = Float32(-1)
            for i in range(len(bones)):  # pragma: no branch
                if weights[i] > heaviest and i not in chosen:
                    heaviest = weights[i]
                    best = i
            chosen.append(best)
            if best >= 0:
                kept += weights[best]
        for i in range(4):  # pragma: no branch
            var pick = chosen[i]
            if pick < 0:
                self.out[self.skin_at].append(0)
                self.out[self.weight_at].append(0)
            else:
                self.out[self.skin_at].append(Float32(bones[pick]))
                self.out[self.weight_at].append(
                    weights[pick] / max(kept, Float32(1e-30))
                )

    def build(mut self, var index: List[Int]) raises -> BufferGeometry:
        """Return the mesh written so far.

        Args:
            index: Three vertices per triangle.

        Returns:
            A mesh with every attribute and the index.

        Raises:
            Error: If an attribute or the index is malformed.
        """
        var mesh = BufferGeometry()
        for k in range(len(self.names)):  # pragma: no branch
            mesh.set_attribute(
                self.names[k],
                BufferAttribute(self.out[k].copy(), self.sizes[k]),
            )
        mesh.set_index(index^)
        return mesh^


def _edge_key(a: Int, b: Int, count: Int) -> Int:
    """Return one key for the edge between two vertices, either way."""
    if a < b:
        return a * count + b
    return b * count + a


def cut(
    geometry: BufferGeometry, values: List[Float32], level: Float32
) raises -> BufferGeometry:
    """Keep the part of a mesh where `values` is at or above `level`.

    A triangle wholly at or above the level is kept. A triangle wholly
    below it is dropped. A triangle that crosses it is clipped along the
    iso-line, which the values interpolate linearly along each edge. Two
    triangles that share an edge share the new vertex on it.

    Args:
        geometry: A mesh, indexed or not.
        values: One value per vertex.
        level: The value the cut runs along.

    Returns:
        An indexed mesh with every attribute of `geometry`. Skin weights
        keep the four heaviest bones of the two they are mixed from.

    Raises:
        Error: If `values` is not one per vertex, or the mesh is
            malformed.
    """
    var count = geometry.vertex_count()
    if len(values) != count:
        raise Error("A cut needs one value per vertex")
    var carrier = _Carrier(geometry)
    var kept = List[Int](length=count, fill=-1)
    var edges = Dict[Int, Int]()
    var written = 0
    var index = List[Int]()
    for t in range(geometry.triangle_count()):
        var corners = List[Int](capacity=3)
        for c in range(3):  # pragma: no branch
            corners.append(geometry.corner_index(t, c))
        # Sutherland-Hodgman against one level: walk the corners and
        # keep each inside corner and each crossing.
        var polygon = List[Int]()
        for c in range(3):  # pragma: no branch
            var a = corners[c]
            var b = corners[(c + 1) % 3]
            var inside_a = values[a] >= level
            var inside_b = values[b] >= level
            if inside_a:
                if kept[a] < 0:
                    carrier.copy_vertex(a)
                    kept[a] = written
                    written += 1
                polygon.append(kept[a])
            if inside_a != inside_b:
                var key = _edge_key(a, b, count)
                if key not in edges:
                    # Mix from the lower index, so both triangles that
                    # share the edge compute the same vertex.
                    var low = min(a, b)
                    var high = max(a, b)
                    var t_cross = (level - values[low]) / (
                        values[high] - values[low]
                    )
                    carrier.mix_vertex(low, high, t_cross)
                    edges[key] = written
                    written += 1
                polygon.append(edges[key])
        for k in range(1, len(polygon) - 1):
            index.append(polygon[0])
            index.append(polygon[k])
            index.append(polygon[k + 1])
    return carrier.build(index^)


def cut_attribute(
    geometry: BufferGeometry, name: String, level: Float32, keep_above: Bool
) raises -> BufferGeometry:
    """Keep the part of a mesh on one side of a level of an attribute.

    The attribute is carried to the new vertices, so a second cut can
    read it again.

    Args:
        geometry: A mesh with the attribute.
        name: An attribute of one component a vertex.
        level: The level the cut runs along.
        keep_above: Keep where the attribute is at or above the level;
            False keeps where it is at or below it.

    Returns:
        The kept part.

    Raises:
        Error: If the mesh has no such attribute or it is malformed.
    """
    ref attribute = geometry.attribute_view(name)
    var values = List[Float32](capacity=attribute.count())
    for v in range(attribute.count()):
        var value = attribute.component(v, 0) - level
        if not keep_above:
            value = -value
        values.append(value)
    return cut(geometry, values, 0)


def merge(
    first: BufferGeometry, second: BufferGeometry
) raises -> BufferGeometry:
    """Join two meshes into one.

    Args:
        first: A mesh.
        second: A mesh with the same attributes, of the same sizes.

    Returns:
        An indexed mesh: the first's vertices, then the second's.

    Raises:
        Error: If the attributes differ.
    """
    if len(first.names) != len(second.names):
        raise Error("Only meshes with the same attributes can be merged")
    var mesh = BufferGeometry()
    for name in first.names:
        if not second.has_attribute(name):
            raise Error("Only meshes with the same attributes can be merged")
        ref a = first.attribute_view(name)
        ref b = second.attribute_view(name)
        if a.item_size != b.item_size:
            raise Error("Only meshes with the same attributes can be merged")
        var data = a.packed()
        data.extend(b.packed())
        mesh.set_attribute(name, BufferAttribute(data^, a.item_size))
    var offset = first.vertex_count()
    var index = List[Int]()
    for t in range(first.triangle_count()):
        for c in range(3):  # pragma: no branch
            index.append(first.corner_index(t, c))
    for t in range(second.triangle_count()):
        for c in range(3):  # pragma: no branch
            index.append(second.corner_index(t, c) + offset)
    mesh.set_index(index^)
    return mesh^


def keep_triangles(mut geometry: BufferGeometry, keep: List[Bool]) raises:
    """Drop the triangles that `keep` refuses.

    The vertices stay. Only the index changes. When every triangle is
    dropped, one degenerate triangle stays: an empty index would draw
    every vertex as a triangle.

    Args:
        geometry: A mesh, indexed or not.
        keep: One flag per triangle.

    Raises:
        Error: If `keep` is not one flag per triangle.
    """
    var triangles = geometry.triangle_count()
    if len(keep) != triangles:
        raise Error("Keep one flag per triangle")
    var index = List[Int]()
    for t in range(triangles):
        if keep[t]:
            for c in range(3):  # pragma: no branch
                index.append(geometry.corner_index(t, c))
    if len(index) == 0 and triangles > 0:
        index = [0, 0, 0]
    geometry.set_index(index^)


def normalize_normals(mut geometry: BufferGeometry) raises:
    """Scale each normal back to unit length.

    A cut mixes normals linearly, which shortens them. A zero normal
    stays zero.

    Args:
        geometry: A mesh with normals.

    Raises:
        Error: If the mesh has no normals.
    """
    var normals = geometry.clone_attribute(String(NORMAL))
    for v in range(normals.count()):
        var n = normals.vector3(v)
        var length = n.length()
        if length > 0:
            n = n * (1 / length)
        normals.set_component(v, 0, n.x)
        normals.set_component(v, 1, n.y)
        normals.set_component(v, 2, n.z)
    geometry.set_attribute(String(NORMAL), normals^)


def top_four(all: List[Float32]) -> Tuple[List[Int], List[Float32]]:
    """Return the four heaviest bones of a weight per bone.

    Args:
        all: One weight per bone, at least four bones.

    Returns:
        The four heaviest bones, heaviest first, and their weights scaled
        to add up to one.
    """
    var bones = List[Int]()
    var total = Float32(0)
    for _ in range(4):  # pragma: no branch
        var best = 0
        var heaviest = Float32(-1)
        for j in range(len(all)):  # pragma: no branch
            if all[j] > heaviest and j not in bones:
                heaviest = all[j]
                best = j
        bones.append(best)
        total += all[best]
    var weights = List[Float32]()
    for k in range(4):  # pragma: no branch
        weights.append(all[bones[k]] / max(total, Float32(1e-30)))
    return (bones^, weights^)


struct MeshWriter(Movable):
    """A mesh with another mesh's attributes, written vertex by vertex.

    A garment's skirt and its lasts are made this way, so they can be
    merged with the shell they join."""

    var names: List[String]
    """The names of the attributes it writes."""
    var sizes: List[Int]
    """How many components each attribute has a vertex."""
    var out: List[List[Float32]]
    """Each attribute's values, written so far."""
    var index: List[Int]
    """The corners of its triangles, three a triangle."""

    def __init__(out self, like: BufferGeometry) raises:
        """Write the attributes `like` has.

        Args:
            like: The mesh whose attributes to write.

        Raises:
            Error: If an attribute cannot be read.
        """
        self.names = like.names.copy()
        self.sizes = List[Int]()
        self.out = List[List[Float32]]()
        self.index = List[Int]()
        for name in self.names:
            self.sizes.append(like.attribute_view(name).item_size)
            self.out.append(List[Float32]())

    def add(
        mut self,
        p: Vector3,
        cover: Float32,
        bones: List[Int],
        weights: List[Float32],
    ) -> Int:
        """Append one vertex. Any attribute it does not name is zero.

        Args:
            p: Its position.
            cover: Its cover value.
            bones: Its four bones.
            weights: Their four weights.

        Returns:
            The vertex's index.
        """
        var at = 0
        for k in range(len(self.names)):  # pragma: no branch
            at = len(self.out[k]) // self.sizes[k]
            var name = self.names[k]
            if name == String(POSITION):
                self.out[k].append(p.x)
                self.out[k].append(p.y)
                self.out[k].append(p.z)
            elif name == String(COVER):
                self.out[k].append(cover)
            elif name == String(SKIN_INDEX):
                for c in range(4):  # pragma: no branch
                    self.out[k].append(Float32(bones[c]))
            elif name == String(SKIN_WEIGHT):
                for c in range(4):  # pragma: no branch
                    self.out[k].append(weights[c])
            else:
                for _ in range(self.sizes[k]):  # pragma: no branch
                    self.out[k].append(0)
        return at

    def triangle(mut self, a: Int, b: Int, c: Int):
        """Append one triangle.

        Args:
            a: Its first corner.
            b: Its second corner.
            c: Its third corner.
        """
        self.index.append(a)
        self.index.append(b)
        self.index.append(c)

    def quad(mut self, a: Int, b: Int, c: Int, d: Int):
        """Append two triangles: `a, b, c` and `c, b, d`.

        Args:
            a: A corner.
            b: The next corner, down from `a`.
            c: The corner beside `a`.
            d: The corner beside `b`.
        """
        self.index.append(a)
        self.index.append(b)
        self.index.append(c)
        self.index.append(c)
        self.index.append(b)
        self.index.append(d)

    def build(mut self) raises -> BufferGeometry:
        """Return the mesh written, with normals computed from its faces.

        Returns:
            An indexed mesh with every attribute `like` has.

        Raises:
            Error: If an attribute is malformed.
        """
        var mesh = BufferGeometry()
        for k in range(len(self.names)):  # pragma: no branch
            mesh.set_attribute(
                self.names[k],
                BufferAttribute(self.out[k].copy(), self.sizes[k]),
            )
        mesh.set_index(self.index.copy())
        mesh.compute_vertex_normals()
        return mesh^


def add_rim(geometry: BufferGeometry, depth: Float32) raises -> BufferGeometry:
    """Return a mesh with a rim along each open edge, `depth` deep.

    A garment is one face of its fabric. At a hem its edge has no
    thickness, and a plate looks as thin as paper. The rim is a strip of
    two triangles along each open edge, from the edge in along its
    vertices' normals, facing out of the edge. Each rim vertex takes the
    attributes of the edge vertex it is made from, and the strip's own
    normal, so the edge catches the light as a rolled edge does.

    An edge is open when one triangle holds it. Copies of a vertex at one
    position are one vertex here, so a seam where a mesh was parted is
    not an edge.

    Args:
        geometry: A mesh with positions and normals, indexed or not.
        depth: How deep the rim runs, in meters.

    Returns:
        The mesh and its rims.

    Raises:
        Error: If the mesh has no positions or no normals.
    """
    var groups = weld_groups(geometry)
    var count = geometry.vertex_count()
    var holders = Dict[Int, Int]()
    for t in range(geometry.triangle_count()):
        for c in range(3):  # pragma: no branch
            var a = groups[geometry.corner_index(t, c)]
            var b = groups[geometry.corner_index(t, (c + 1) % 3)]
            var key = _edge_key(a, b, count)
            holders[key] = holders.get(key, 0) + 1
    ref placed = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    var carrier = _Carrier(geometry)
    var position_at = first_match(carrier.names, String(POSITION))
    var normal_at = first_match(carrier.names, String(NORMAL))
    var written = 0
    var index = List[Int]()
    for t in range(geometry.triangle_count()):
        for c in range(3):  # pragma: no branch
            var a = geometry.corner_index(t, c)
            var b = geometry.corner_index(t, (c + 1) % 3)
            if holders[_edge_key(groups[a], groups[b], count)] != 1:
                continue
            var pa = placed.vector3(a)
            var pb = placed.vector3(b)
            # The face's normal, as its corners wind.
            var face = pb - pa
            face.cross(
                placed.vector3(geometry.corner_index(t, (c + 2) % 3)) - pa
            )
            # Out of the edge: along it, crossed with the face's normal.
            var outward = pb - pa
            outward.cross(face)
            var length = outward.length()
            if length <= 0:
                continue
            outward = outward * (1 / length)
            # In from the face, along each vertex's normal turned to the
            # face's side.
            var na = normals.vector3(a)
            var nb = normals.vector3(b)
            if na.dot(face) < 0:
                na = na * -1
            if nb.dot(face) < 0:
                nb = nb * -1
            var corners: List[Vector3] = [
                pa,
                pa - na * depth,
                pb - nb * depth,
                pb,
            ]
            var from_vertex: List[Int] = [a, a, b, b]
            for k in range(4):  # pragma: no branch
                carrier.copy_vertex(from_vertex[k])
                _set_vector(carrier, position_at, written + k, corners[k])
                _set_vector(carrier, normal_at, written + k, outward)
            index.append(written)
            index.append(written + 1)
            index.append(written + 2)
            index.append(written)
            index.append(written + 2)
            index.append(written + 3)
            written += 4
    var rims = carrier.build(index^)
    return merge(geometry, rims)


def _set_vector(mut carrier: _Carrier, at: Int, vertex: Int, value: Vector3):
    """Overwrite one vertex's three components of one written attribute."""
    carrier.out[at][vertex * 3] = value.x
    carrier.out[at][vertex * 3 + 1] = value.y
    carrier.out[at][vertex * 3 + 2] = value.z
