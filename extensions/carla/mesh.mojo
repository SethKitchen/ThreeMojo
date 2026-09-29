# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's mesh container, `geom::Mesh`, from
`LibCarla/source/carla/geom/Mesh.h` and `Mesh.cpp`.

`MeshFactory` builds road meshes with this type, and the map writes them
as OBJ files for CARLA's simulator plugin and for Recast. A mesh is a list of vertices, a
list of normals, a list of UVs and a list of indices counted from one,
three to a triangle, as an OBJ file counts them. A material names a run
of indices. The lists need not have the same length: CARLA does not
check it, and neither does this port.

The vertices are `math.vector3.Vector3` values in meters, in CARLA's
frame, and the UVs are `math.vector2.Vector2` values.
`to_buffer_geometry` gives a ThreeMojo `BufferGeometry`, in the three.js
frame or in CARLA's, with one group for each material. `generate_ply`
writes that geometry with `exporters.ply.export_ply`.

`generate_obj` and `generate_obj_for_recast` write CARLA's own text, so
that a file matches the one CARLA writes byte for byte: its comments,
its material names in `usemtl` lines, and six digits after the point.
`exporters.obj.export_obj` writes three.js's OBJ, which has none of
those. `format_fixed` is C's `%.*f`, which CARLA's stream uses.

**Differences from CARLA.**

- `generate_ply` writes a PLY file. CARLA's `GeneratePLY` is a stub that
  returns an empty string.
- `add_material` and `is_valid` do not print their messages to standard
  output, as CARLA's do.
- `concat_mesh` refuses a link count that CARLA would wrap around.
- `generate_obj` stops looking for a material after the last one. CARLA
  reads past the end of its list there.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
)
from core.object3d import Object3D
from core.scene import Scene
from exporters.ply import export_ply
from extensions.carla.transform import carla_to_three
from materials.material import Material
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.memory import bitcast


def format_fixed(value: Float32, digits: Int) raises -> String:
    """Write a number as C's `printf("%.*f")` writes it as a double.

    The exact binary value is rounded to `digits` places, a tie to even,
    as the GNU C library rounds. This is what a C++ stream writes after
    `std::fixed`.

    Args:
        value: The number.
        digits: The digits after the point, from 0 to 18.

    Returns:
        The text: `1.500000` for 1.5 and six digits. A negative number,
        minus zero included, keeps its sign. Infinity is `inf` and NaN is
        `nan`, with a minus sign when the sign bit is set.

    Raises:
        Error: If `digits` is out of range.
    """
    if digits < 0 or digits > 18:
        raise Error("format_fixed: the digits must be from 0 to 18")
    var bits = bitcast[DType.uint32](value)
    var sign = "-" if (bits >> 31) != 0 else ""
    var exponent = Int((bits >> 23) & 0xFF)
    var fraction = UInt128(Int(bits & 0x7FFFFF))
    if exponent == 255:
        return sign + ("inf" if fraction == 0 else "nan")
    var mantissa = fraction
    var shift = 149
    if exponent > 0:
        mantissa = fraction | (UInt128(1) << 23)
        shift = 150 - exponent
    var scale = UInt128(1)
    for _ in range(digits):
        scale *= 10
    var whole: UInt128
    if shift <= 0:
        whole = (mantissa << UInt128(-shift)) * scale
    else:
        var scaled = mantissa * scale
        # Past 100 bits the value is below 2^-16 of a unit, and rounds to
        # zero at any number of digits allowed here.
        whole = 0
        if shift < 100:
            whole = scaled >> UInt128(shift)
            var rest = scaled - (whole << UInt128(shift))
            var half = UInt128(1) << UInt128(shift - 1)
            if rest > half or (rest == half and (whole & 1) == 1):
                whole += 1
    var text = String(whole)
    while text.byte_length() < digits + 1:
        text = "0" + text
    if digits == 0:
        return sign + text
    var cut = text.byte_length() - digits
    return sign + String(text[byte=:cut]) + "." + String(text[byte=cut:])


@fieldwise_init
struct MeshMaterial(Copyable, Movable):
    """A named run of indices, CARLA's `MeshMaterial`."""

    var name: String
    # The first index of the run, and the index after its last. An end of
    # zero means the material is still open.
    var index_start: Int
    var index_end: Int


struct CarlaMesh(Copyable, Movable):
    """A mesh's lists, CARLA's `geom::Mesh`."""

    # In meters, in CARLA's frame.
    var vertices: List[Vector3]
    var normals: List[Vector3]
    # Counted from one, three to a triangle.
    var indexes: List[Int]
    var uvs: List[Vector2]
    var materials: List[MeshMaterial]

    def __init__(out self):
        """Create an empty mesh."""
        self.vertices = List[Vector3]()
        self.normals = List[Vector3]()
        self.indexes = List[Int]()
        self.uvs = List[Vector2]()
        self.materials = List[MeshMaterial]()

    def __init__(
        out self,
        var vertices: List[Vector3],
        var normals: List[Vector3],
        var indexes: List[Int],
        var uvs: List[Vector2],
    ):
        """Create a mesh from its lists, CARLA's constructor.

        Args:
            vertices: The vertices, in meters.
            normals: The normals.
            indexes: The indices, counted from one.
            uvs: The texture coordinates.
        """
        self.vertices = vertices^
        self.normals = normals^
        self.indexes = indexes^
        self.uvs = uvs^
        self.materials = List[MeshMaterial]()

    def is_valid(self) -> Bool:
        """Return whether the mesh can be written, `IsValid`.

        Returns:
            False if there are no vertices, if the index count is not a
            multiple of three, or if the last material is still open.
        """
        if len(self.vertices) == 0:
            return False
        if len(self.indexes) > 0 and len(self.indexes) % 3 != 0:
            return False
        if (
            len(self.materials) > 0
            and self.materials[len(self.materials) - 1].index_end == 0
        ):
            return False
        return True

    def add_triangle_strip(mut self, vertices: List[Vector3]):
        """Add a triangle strip, `AddTriangleStrip`.

        The first triangle is (1, 2, 3) of the new vertices, the next
        (4, 3, 2), and so on, turning the same way.

        Args:
            vertices: The strip's vertices. An empty list adds nothing.
        """
        if len(vertices) == 0:
            return
        var i = len(self.vertices) + 2
        self.add_vertices(vertices)
        var index_clockwise = True
        while i < len(self.vertices):
            index_clockwise = not index_clockwise
            if index_clockwise:
                self.add_index(i + 1)
                self.add_index(i)
                self.add_index(i - 1)
            else:
                self.add_index(i - 1)
                self.add_index(i)
                self.add_index(i + 1)
            i += 1

    def add_triangle_fan(mut self, vertices: List[Vector3]):
        """Add a triangle fan about the first vertex, `AddTriangleFan`.

        Args:
            vertices: The fan's vertices, the center first.
        """
        var initial_index = len(self.vertices) + 1
        var i = len(self.vertices) + 2
        self.add_vertices(vertices)
        while i < len(self.vertices):
            self.add_index(initial_index)
            self.add_index(i)
            self.add_index(i + 1)
            i += 1

    def add_vertex(mut self, vertex: Vector3):
        """Append a vertex, `AddVertex`.

        Args:
            vertex: The vertex, in meters.
        """
        self.vertices.append(vertex)

    def add_vertices(mut self, vertices: List[Vector3]):
        """Append vertices, `AddVertices`.

        Args:
            vertices: The vertices, in meters.
        """
        self.vertices.extend(vertices.copy())

    def add_normal(mut self, normal: Vector3):
        """Append a normal, `AddNormal`.

        Args:
            normal: The normal.
        """
        self.normals.append(normal)

    def add_index(mut self, index: Int):
        """Append an index, `AddIndex`.

        Args:
            index: A vertex, counted from one.
        """
        self.indexes.append(index)

    def add_uv(mut self, uv: Vector2):
        """Append a texture coordinate, `AddUV`.

        Args:
            uv: The coordinate.
        """
        self.uvs.append(uv)

    def add_uvs(mut self, uvs: List[Vector2]):
        """Append texture coordinates, `AddUVs`.

        Args:
            uvs: The coordinates.
        """
        self.uvs.extend(uvs.copy())

    def add_material(mut self, material_name: String):
        """Start a material at the next index, `AddMaterial`.

        An open material is closed first. Nothing starts when the index
        count is not a multiple of three.

        Args:
            material_name: The material's name.
        """
        var open_index = len(self.indexes)
        if (
            len(self.materials) > 0
            and self.materials[len(self.materials) - 1].index_end == 0
        ):
            self.end_material()
        if open_index % 3 != 0:
            return
        self.materials.append(MeshMaterial(material_name, open_index, 0))

    def end_material(mut self):
        """Close the open material at the next index, `EndMaterial`.

        Nothing happens when no material is open, when the open one has no
        index yet, or when the index count is not a multiple of three.
        """
        var close_index = len(self.indexes)
        if (
            len(self.materials) == 0
            or self.materials[len(self.materials) - 1].index_start
            == close_index
            or self.materials[len(self.materials) - 1].index_end != 0
        ):
            return
        if close_index % 3 != 0:
            return
        self.materials[len(self.materials) - 1].index_end = close_index

    def _faces(self, mut out: String, recast: Bool):
        out += "\n# Polygonal face element.\n"
        var material = 0
        var i = 0
        while i < len(self.indexes):
            if material < len(self.materials):
                if self.materials[material].index_end == i:
                    material += 1
                if (
                    material < len(self.materials)
                    and self.materials[material].index_start == i
                ):
                    out += "\nusemtl " + self.materials[material].name + "\n"
            var a = self.indexes[i]
            var b = self.indexes[i + 1]
            var c = self.indexes[i + 2]
            if recast:
                out += (
                    "f " + String(a) + " " + String(c) + " " + String(b) + "\n"
                )
            else:
                out += (
                    "f " + String(a) + " " + String(b) + " " + String(c) + "\n"
                )
            i += 3

    def generate_obj(self) raises -> String:
        """Write the mesh as CARLA's OBJ text, `GenerateOBJ`.

        Returns:
            The text, with six digits after the point, in CARLA's frame.
            An empty string for a mesh that is not valid.

        Raises:
            Error: If a number cannot be written.
        """
        if not self.is_valid():
            return ""
        var out = String(
            "# List of geometric vertices, with (x, y, z) coordinates.\n"
        )
        for v in self.vertices:  # pragma: no branch
            out += (
                "v "
                + format_fixed(v.x, 6)
                + " "
                + format_fixed(v.y, 6)
                + " "
                + format_fixed(v.z, 6)
                + "\n"
            )
        if len(self.uvs) > 0:
            out += (
                "\n# List of texture coordinates, in (u, v) coordinates,"
                " these will vary between 0 and 1.\n"
            )
            for vt in self.uvs:  # pragma: no branch
                out += (
                    "vt "
                    + format_fixed(vt.x, 6)
                    + " "
                    + format_fixed(vt.y, 6)
                    + "\n"
                )
        if len(self.normals) > 0:
            out += (
                "\n# List of vertex normals in (x, y, z) form; normals might"
                " not be unit vectors.\n"
            )
            for vn in self.normals:  # pragma: no branch
                out += (
                    "vn "
                    + format_fixed(vn.x, 6)
                    + " "
                    + format_fixed(vn.y, 6)
                    + " "
                    + format_fixed(vn.z, 6)
                    + "\n"
                )
        if len(self.indexes) > 0:
            self._faces(out, False)
        return out^

    def generate_obj_for_recast(self) raises -> String:
        """Write the mesh as the OBJ text CARLA gives Recast,
        `GenerateOBJForRecast`.

        Returns:
            The text with y and z swapped in each vertex and the last two
            corners of each face swapped, and no UVs or normals. An empty
            string for a mesh that is not valid.

        Raises:
            Error: If a number cannot be written.
        """
        if not self.is_valid():
            return ""
        var out = String(
            "# List of geometric vertices, with (x, y, z) coordinates.\n"
        )
        for v in self.vertices:  # pragma: no branch
            out += (
                "v "
                + format_fixed(v.x, 6)
                + " "
                + format_fixed(v.z, 6)
                + " "
                + format_fixed(v.y, 6)
                + "\n"
            )
        if len(self.indexes) > 0:
            self._faces(out, True)
        return out^

    def to_buffer_geometry(
        self, three_frame: Bool = True
    ) raises -> BufferGeometry:
        """Return the mesh as a ThreeMojo geometry.

        Args:
            three_frame: True to move the vertices and normals into the
                three.js frame with `carla_to_three`, which keeps a CARLA
                strip facing up. False to keep CARLA's frame.

        Returns:
            An indexed geometry with `position`, with `normal` and `uv`
            when there is one for each vertex, and one group for each
            material, in order. The indices count from zero.

        Raises:
            Error: If the mesh is not valid or an index names no vertex.
        """
        if not self.is_valid():
            raise Error("A CARLA mesh that is not valid has no geometry")
        var positions = List[Float32]()
        for v in self.vertices:  # pragma: no branch
            var p = carla_to_three(v) if three_frame else v
            positions.extend([p.x, p.y, p.z])
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        if len(self.normals) == len(self.vertices):
            var normals = List[Float32]()
            for n in self.normals:  # pragma: no branch
                var q = carla_to_three(n) if three_frame else n
                normals.extend([q.x, q.y, q.z])
            geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
        if len(self.uvs) == len(self.vertices):
            var uvs = List[Float32]()
            for uv in self.uvs:  # pragma: no branch
                uvs.extend([uv.x, uv.y])
            geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
        var index = List[Int]()
        for i in self.indexes:
            if i < 1 or i > len(self.vertices):
                raise Error("A CARLA mesh index must name a vertex")
            index.append(i - 1)
        geometry.set_index(index^)
        for m in range(len(self.materials)):
            ref material = self.materials[m]
            geometry.add_group(
                material.index_start,
                material.index_end - material.index_start,
                MaterialIndex(m),
            )
        return geometry^

    def generate_ply(self) raises -> String:
        """Write the mesh as an ASCII PLY file, `GeneratePLY`.

        The file is `exporters.ply.export_ply`'s, of `to_buffer_geometry`
        in CARLA's frame.

        Returns:
            The text, or `Invalid Mesh` for a mesh that is not valid, as in
            CARLA.

        Raises:
            Error: If an index names no vertex or the file cannot be
                written.
        """
        if not self.is_valid():
            return "Invalid Mesh"
        var assets = Assets()
        var shape = assets.geometries.add(self.to_buffer_geometry(False))
        var paint = assets.materials.add(Material(Color(255, 255, 255)))
        var scene = Scene()
        var node = scene.add(Object3D())
        scene.add_mesh(Mesh(shape, paint, node))
        scene.update()
        return String(unsafe_from_utf8=export_ply(scene, assets))

    def vertices_num(self) -> Int:
        """Return how many vertices there are, `GetVerticesNum`.

        Returns:
            The count.
        """
        return len(self.vertices)

    def indexes_num(self) -> Int:
        """Return how many indices there are, `GetIndexesNum`.

        Returns:
            The count.
        """
        return len(self.indexes)

    def last_vertex_index(self) -> Int:
        """Return the index of the last vertex, `GetLastVertexIndex`.

        Returns:
            The vertex count, which counting from one is the last vertex.
        """
        return len(self.vertices)

    def _append(mut self, rhs: CarlaMesh):
        var v_num = len(self.vertices)
        var i_num = len(self.indexes)
        self.vertices.extend(rhs.vertices.copy())
        self.normals.extend(rhs.normals.copy())
        for index in rhs.indexes:
            self.indexes.append(index + v_num)
        self.uvs.extend(rhs.uvs.copy())
        for material in rhs.materials:
            self.materials.append(
                MeshMaterial(
                    material.name,
                    material.index_start + i_num,
                    material.index_end + i_num,
                )
            )

    def concat_mesh(mut self, rhs: CarlaMesh, num_vertices_to_link: Int) raises:
        """Join a mesh on, stitching the seam, `ConcatMesh`.

        The last `num_vertices_to_link` vertices of this mesh and the first
        of `rhs` are joined by two triangles a step. A mesh `rhs` that is
        not valid is appended as `+=` does.

        Args:
            rhs: The mesh to join.
            num_vertices_to_link: How many vertices each side of the seam
                has.

        Raises:
            Error: If the link count is negative or larger than either
                mesh's vertex count.
        """
        if not rhs.is_valid():
            self += rhs
            return
        var v_num = len(self.vertices)
        if (
            num_vertices_to_link < 0
            or num_vertices_to_link > v_num
            or num_vertices_to_link > len(rhs.vertices)
        ):
            raise Error("A CARLA mesh seam needs a link count both meshes have")
        var i_num = len(self.indexes)
        self.vertices.extend(rhs.vertices.copy())
        self.normals.extend(rhs.normals.copy())
        var start = v_num - num_vertices_to_link
        for i in range(1, num_vertices_to_link):
            self.indexes.extend(
                [
                    start + i,
                    start + i + 1,
                    v_num + i,
                    start + i + 1,
                    v_num + i + 1,
                    v_num + i,
                ]
            )
        for index in rhs.indexes:
            self.indexes.append(index + v_num)
        self.uvs.extend(rhs.uvs.copy())
        for material in rhs.materials:
            self.materials.append(
                MeshMaterial(
                    material.name,
                    material.index_start + i_num,
                    material.index_end + i_num,
                )
            )

    def __iadd__(mut self, rhs: CarlaMesh):
        """Append a mesh, `operator+=`.

        Args:
            rhs: The mesh to append. Its indices and material runs are
                moved past this mesh's.
        """
        self._append(rhs)

    def __add__(self, rhs: CarlaMesh) -> CarlaMesh:
        """Join two meshes, `operator+`.

        Args:
            rhs: The mesh to append.

        Returns:
            A copy of this mesh with `rhs` appended.
        """
        var out = self.copy()
        out += rhs
        return out^
