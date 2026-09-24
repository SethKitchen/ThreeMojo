# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""3DS files, from three.js `examples/jsm/loaders/TDSLoader.js`.

Autodesk's 3D Studio format is a tree of chunks. Each chunk is a
little-endian 16-bit id, a 32-bit size that counts its own six bytes,
and a body that holds values and more chunks. `parse_3ds` reads the
chunks three.js reads and steps over the others.

**What is read.** The main chunk `0x4D4D` (or `0x3DAA`, `0xC23D`) holds
the editor chunk `0x3D3D`. In it:

- The master scale scales the root node, as three.js scales its `Group`.
- Each material entry becomes a `PHONG` material: its name, diffuse
  and ambient colors (the later one wins, as in three.js), specular
  color, shininess, transparency, two sides, additive blending,
  wireframe and wireframe width, and four maps: color, bump, opacity and
  specular.
- Each named object with a triangle mesh becomes a node under the root:
  its points, texture coordinates, faces, material groups and matrix.

**Colors.** three.js reads a color's bytes over 255 as linear light,
and the material keeps them as the sRGB bytes that give that light.

**Materials of a mesh.** A mesh takes the materials its groups name, in
order, as three.js does, and skips a name no material entry has had yet.
Each group runs three index entries a face from where the one before
ended, whatever faces it lists: three.js's own assumption. With one
material, the mesh draws the whole geometry in it. With none and no
groups, it draws in a new white `PHONG` material, three.js's default.
With more than one, each group whose material is there is drawn as a
mesh of its own, since a mesh here draws one material. With groups but
no materials, three.js's material list is empty and draws nothing, and
so does this.

**Maps.** three.js's `TextureLoader` loads each map's file from the
directory the model is in. This port reads it with `decode_image` when
the file is there, as a linear texture: three.js leaves the color space
of a loaded texture unset. When the file is not there, the map is kept
with no texture, as three.js keeps a texture whose image never loads.

**Where this port differs.** three.js reads past a chunk that runs past
the end of the file until a read throws a `RangeError`, and a float read
past the end is zero. This port refuses such a file, and a chunk that
says it is shorter than its own header, which three.js reads forever.
three.js throws a `TypeError` for a map that sets an offset or a scale
before its file name; this refuses it. A face index past the last point
is refused. A `Material` here draws a wireframe only when it is `BASIC`,
so the wireframe and its width stay in `TdsMaterial`.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, UV, BufferGeometry, MaterialIndex
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.gltf import decode_image
from loaders.model_nodes import decompose_onto
from materials.material import (
    ADDITIVE,
    DOUBLE_SIDE,
    FRONT_SIDE,
    PHONG,
    Material,
    MaterialId,
)
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.srgb import LINEAR, linear_to_srgb, srgb_to_linear
from render.texture import BILINEAR, CLAMP, COVERAGE, texture_from
from render.texture_store import NO_TEXTURE, TextureId
from std.memory import bitcast
from std.pathlib import Path

comptime _M3DMAGIC = 0x4D4D
comptime _MLIBMAGIC = 0x3DAA
comptime _CMAGIC = 0xC23D
comptime _COLOR_F = 0x0010
comptime _COLOR_24 = 0x0011
comptime _LIN_COLOR_24 = 0x0012
comptime _LIN_COLOR_F = 0x0013
comptime _INT_PERCENTAGE = 0x0030
comptime _FLOAT_PERCENTAGE = 0x0031
comptime _MDATA = 0x3D3D
comptime _MASTER_SCALE = 0x0100
comptime _MAT_ENTRY = 0xAFFF
comptime _MAT_NAME = 0xA000
comptime _MAT_AMBIENT = 0xA010
comptime _MAT_DIFFUSE = 0xA020
comptime _MAT_SPECULAR = 0xA030
comptime _MAT_SHININESS = 0xA040
comptime _MAT_TRANSPARENCY = 0xA050
comptime _MAT_TWO_SIDE = 0xA081
comptime _MAT_ADDITIVE = 0xA083
comptime _MAT_WIRE = 0xA085
comptime _MAT_WIRE_SIZE = 0xA087
comptime _MAT_TEXMAP = 0xA200
comptime _MAT_OPACMAP = 0xA210
comptime _MAT_BUMPMAP = 0xA230
comptime _MAT_SPECMAP = 0xA204
comptime _MAT_MAPNAME = 0xA300
comptime _MAT_MAP_USCALE = 0xA354
comptime _MAT_MAP_VSCALE = 0xA356
comptime _MAT_MAP_UOFFSET = 0xA358
comptime _MAT_MAP_VOFFSET = 0xA35A
comptime _NAMED_OBJECT = 0x4000
comptime _N_TRI_OBJECT = 0x4100
comptime _POINT_ARRAY = 0x4110
comptime _FACE_ARRAY = 0x4120
comptime _MSH_MAT_GROUP = 0x4130
comptime _TEX_VERTS = 0x4140
comptime _MESH_MATRIX = 0x4160


@fieldwise_init
struct _Chunk(Copyable, Movable):
    """One chunk: its id, where its body is read from, and its end."""

    var id: Int
    var position: Int
    var end: Int

    def at_end(self) -> Bool:
        """Return True when the body has nothing more, three.js's
        `endOfChunk`."""
        return self.position >= self.end


struct _Reader:
    """Reads chunks and values from the bytes of a file."""

    var bytes: List[UInt8]

    def __init__(out self, var bytes: List[UInt8]):
        """Hold the file."""
        self.bytes = bytes^

    def need(self, at: Int, size: Int) raises:
        """Refuse a read that runs past the end of the file."""
        if at + size > len(self.bytes):
            raise Error(
                "3DS: the file ends inside a value, at byte " + String(at)
            )

    def chunk(self, at: Int) raises -> _Chunk:
        """Return the chunk whose header starts at `at`, three.js's
        `new Chunk`.

        Raises:
            Error: If the header or the body runs past the end of the
                file, or the size is less than the header.
        """
        self.need(at, 6)
        var id = Int(self.bytes[at]) | (Int(self.bytes[at + 1]) << 8)
        var size = 0
        for k in range(4):  # pragma: no branch
            size |= Int(self.bytes[at + 2 + k]) << (8 * k)
        if size < 6:
            raise Error(
                "3DS: a chunk shorter than its header, at " + String(at)
            )
        if at + size > len(self.bytes):
            raise Error("3DS: a chunk runs past the end of the file")
        return _Chunk(id, at + 6, at + size)

    def next(self, mut parent: _Chunk) raises -> Optional[_Chunk]:
        """Return the next chunk inside `parent`, or none at its end,
        three.js's `readChunk`.

        Raises:
            Error: If `chunk` refuses the next chunk.
        """
        if parent.at_end():
            return None
        var child = self.chunk(parent.position)
        parent.position = child.end
        return child^

    def byte(self, mut c: _Chunk) raises -> Int:
        """Read one byte."""
        self.need(c.position, 1)
        c.position += 1
        return Int(self.bytes[c.position - 1])

    def word(self, mut c: _Chunk) raises -> Int:
        """Read an unsigned 16-bit value."""
        self.need(c.position, 2)
        var v = Int(self.bytes[c.position]) | (
            Int(self.bytes[c.position + 1]) << 8
        )
        c.position += 2
        return v

    def short(self, mut c: _Chunk) raises -> Int:
        """Read a signed 16-bit value."""
        var v = self.word(c)
        return v - 65536 if v >= 32768 else v

    def float(self, mut c: _Chunk) raises -> Float32:
        """Read a little-endian 32-bit float."""
        self.need(c.position, 4)
        var raw = UInt32(0)
        for k in range(4):  # pragma: no branch
            raw |= UInt32(self.bytes[c.position + k]) << UInt32(8 * k)
        c.position += 4
        return bitcast[DType.float32](raw)

    def string(self, mut c: _Chunk) raises -> String:
        """Read bytes up to a zero, each a Latin-1 character, three.js's
        `readString`."""
        var out = String()
        var b = self.byte(c)
        while b != 0:
            out += chr(b)
            b = self.byte(c)
        return out^


struct TdsMap(Copyable, Movable):
    """A material's map: its file, where it sits, and its texture."""

    # The file name as the model gives it.
    var file: String
    # three.js's `texture.offset` and `texture.repeat`.
    var offset: Vector2
    var repeat: Vector2
    # The texture, or `NO_TEXTURE` when the file is not there.
    var texture: TextureId

    def __init__(out self, var file: String):
        """Start a map with no offset and no repeat.

        Args:
            file: The file name.
        """
        self.file = file^
        self.offset = Vector2(0, 0)
        self.repeat = Vector2(1, 1)
        self.texture = NO_TEXTURE


struct TdsMaterial(Copyable, Movable):
    """A material entry as three.js's `MeshPhongMaterial` holds it."""

    var name: String
    # Linear light, as three.js's `Color` holds it.
    var color: FloatColor
    var specular: FloatColor
    var shininess: Float32
    var opacity: Float32
    var transparent: Bool
    var double_sided: Bool
    var additive: Bool
    var wireframe: Bool
    var wireframe_width: Int
    # The color, bump, opacity and specular maps, when the entry has them.
    var map: Optional[TdsMap]
    var bump_map: Optional[TdsMap]
    var alpha_map: Optional[TdsMap]
    var specular_map: Optional[TdsMap]

    def __init__(out self):
        """Start with three.js's `MeshPhongMaterial` defaults."""
        self.name = String()
        self.color = FloatColor(1, 1, 1)
        # three.js's `new Color( 0x111111 )`, an sRGB value.
        var dark = srgb_to_linear(Float32(17) / 255)
        self.specular = FloatColor(dark, dark, dark)
        self.shininess = 30
        self.opacity = 1
        self.transparent = False
        self.double_sided = False
        self.additive = False
        self.wireframe = False
        self.wireframe_width = 1
        self.map = None
        self.bump_map = None
        self.alpha_map = None
        self.specular_map = None

    def build(self) raises -> Material:
        """Return the `PHONG` material this entry describes.

        A `Material` draws a wireframe only when it is `BASIC`, so the
        wireframe and its width stay here, and the material draws the
        surface.

        Returns:
            The material, its colors the sRGB bytes of the linear light.

        Raises:
            Error: If `Material` refuses a value, such as a shininess below
                zero.
        """
        return Material(
            _authored(self.color),
            map=_texture(self.map),
            side=DOUBLE_SIDE if self.double_sided else FRONT_SIDE,
            opacity=self.opacity,
            blending=Optional(ADDITIVE) if self.additive else None,
            kind=PHONG,
            alpha_map=_texture(self.alpha_map),
            specular=_authored(self.specular),
            shininess=self.shininess,
            transparent=self.transparent,
            bump_map=_texture(self.bump_map),
            specular_map=_texture(self.specular_map),
        )


def _texture(map: Optional[TdsMap]) -> TextureId:
    """Return a map's texture, or `NO_TEXTURE` for no map."""
    if Bool(map):
        return map.value().texture
    return NO_TEXTURE


def _authored(color: FloatColor) -> Color:
    """Return linear light as the sRGB bytes a material holds."""
    return FloatColor(
        linear_to_srgb(color.r),
        linear_to_srgb(color.g),
        linear_to_srgb(color.b),
        1,
    ).quantize()


struct TdsModel(Movable):
    """What `parse_3ds` put into the scene and the assets."""

    # The node three.js returns as its `Group`, scaled by the master
    # scale. Each mesh's node is under it.
    var root: NodeId
    var scale: Float32
    # One entry per triangle mesh, in file order: its node, its name, its
    # geometry, and three.js's list of its materials.
    var nodes: List[NodeId]
    var names: List[String]
    var geometries: List[GeometryId]
    var mesh_materials: List[List[MaterialId]]
    # One entry per material entry, in file order.
    var materials: List[TdsMaterial]
    var material_ids: List[MaterialId]
    # Each texture that the loader read.
    var textures: List[TextureId]
    # Where this file's meshes start in `scene.meshes`, and how many.
    var first_mesh: Int
    var mesh_count: Int

    def __init__(out self):
        """Start empty."""
        self.root = NO_PARENT
        self.scale = 1
        self.nodes = List[NodeId]()
        self.names = List[String]()
        self.geometries = List[GeometryId]()
        self.mesh_materials = List[List[MaterialId]]()
        self.materials = List[TdsMaterial]()
        self.material_ids = List[MaterialId]()
        self.textures = List[TextureId]()
        self.first_mesh = 0
        self.mesh_count = 0


struct _Loader:
    """Walks the chunks, three.js's `TDSLoader` methods."""

    var r: _Reader
    var model: TdsModel
    var resource_path: String

    def __init__(out self, var bytes: List[UInt8], resource_path: String):
        """Start reading a file."""
        self.r = _Reader(bytes^)
        self.model = TdsModel()
        self.resource_path = resource_path

    def material_named(self, name: String) -> Int:
        """Return the last material entry of a name read so far, or -1."""
        var found = -1
        for i in range(len(self.model.materials)):
            if self.model.materials[i].name == name:
                found = i
        return found

    def _value(self, mut c: _Chunk, what: String) raises -> _Chunk:
        """Return the chunk inside a color or a percentage.

        Raises:
            Error: If there is none, where three.js throws a `TypeError`.
        """
        var sub = self.r.next(c)
        if not Bool(sub):
            raise Error("3DS: a " + what + " chunk with no value")
        return sub.value().copy()

    def color(self, mut c: _Chunk) raises -> FloatColor:
        """Read a color chunk, three.js's `readColor`: white when the
        chunk under it is not a color."""
        var sub = self._value(c, "color")
        var bytes = sub.id == _COLOR_24 or sub.id == _LIN_COLOR_24
        var floats = sub.id == _COLOR_F or sub.id == _LIN_COLOR_F
        if bytes:
            var rgb = List[Float32]()
            for _ in range(3):  # pragma: no branch
                rgb.append(Float32(self.r.byte(sub)) / 255)
            return FloatColor(rgb[0], rgb[1], rgb[2])
        if floats:
            var red = self.r.float(sub)
            var green = self.r.float(sub)
            var blue = self.r.float(sub)
            return FloatColor(red, green, blue)
        return FloatColor(1, 1, 1)

    def percentage(self, mut c: _Chunk) raises -> Float32:
        """Read a percentage chunk as a fraction, three.js's
        `readPercentage`: zero when the chunk under it is not one."""
        var sub = self._value(c, "percentage")
        if sub.id == _INT_PERCENTAGE:
            return Float32(self.r.short(sub)) / 100
        if sub.id == _FLOAT_PERCENTAGE:
            return self.r.float(sub)
        return 0

    def map(mut self, mut c: _Chunk, mut assets: Assets) raises -> TdsMap:
        """Read a map, three.js's `readMap`.

        Raises:
            Error: If an offset or a scale comes before the file name, or
                the file is there and `decode_image` refuses it.
        """
        var map: Optional[TdsMap] = None
        var next = self.r.next(c)
        while Bool(next):
            var sub = next.value().copy()
            if sub.id == _MAT_MAPNAME:
                map = TdsMap(self.r.string(sub))
            elif _map_value(sub.id):
                if not Bool(map):
                    raise Error("3DS: a map sets a value before its file")
                var value = self.r.float(sub)
                ref m = map.value()
                if sub.id == _MAT_MAP_UOFFSET:
                    m.offset.x = value
                elif sub.id == _MAT_MAP_VOFFSET:
                    m.offset.y = value
                elif sub.id == _MAT_MAP_USCALE:
                    m.repeat.x = value
                else:
                    m.repeat.y = value
            next = self.r.next(c)
        if not Bool(map):
            raise Error("3DS: a map with no file")
        var made = map.value().copy()
        var file = Path(self.resource_path + made.file)
        if file.exists():
            var texture = texture_from(
                decode_image(file.read_bytes()),
                CLAMP,
                BILINEAR,
                LINEAR,
                True,
                COVERAGE,
            )
            texture.offset = made.offset
            texture.repeat = made.repeat
            made.texture = assets.textures.add(texture^)
            self.model.textures.append(made.texture)
        return made^

    def material(mut self, mut c: _Chunk, mut assets: Assets) raises:
        """Read a material entry, three.js's `readMaterialEntry`.

        Raises:
            Error: If a value runs past its chunk, or a map is refused.
        """
        var m = TdsMaterial()
        var next = self.r.next(c)
        while Bool(next):
            var sub = next.value().copy()
            if sub.id == _MAT_NAME:
                m.name = self.r.string(sub)
            elif sub.id == _MAT_WIRE:
                m.wireframe = True
            elif sub.id == _MAT_WIRE_SIZE:
                m.wireframe_width = self.r.byte(sub)
            elif sub.id == _MAT_TWO_SIDE:
                m.double_sided = True
            elif sub.id == _MAT_ADDITIVE:
                m.additive = True
            elif sub.id == _MAT_DIFFUSE:
                m.color = self.color(sub)
            elif sub.id == _MAT_SPECULAR:
                m.specular = self.color(sub)
            elif sub.id == _MAT_AMBIENT:
                m.color = self.color(sub)
            elif sub.id == _MAT_SHININESS:
                m.shininess = self.percentage(sub) * 100
            elif sub.id == _MAT_TRANSPARENCY:
                m.opacity = 1 - self.percentage(sub)
                m.transparent = m.opacity < 1
            elif sub.id == _MAT_TEXMAP:
                m.map = self.map(sub, assets)
            elif sub.id == _MAT_BUMPMAP:
                m.bump_map = self.map(sub, assets)
            elif sub.id == _MAT_OPACMAP:
                m.alpha_map = self.map(sub, assets)
            elif sub.id == _MAT_SPECMAP:
                m.specular_map = self.map(sub, assets)
            next = self.r.next(c)
        var id = assets.materials.add(m.build())
        self.model.materials.append(m^)
        self.model.material_ids.append(id)

    def mesh(
        mut self,
        mut c: _Chunk,
        var name: String,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Read a triangle mesh, three.js's `readMesh` and
        `readFaceArray`, and place it.

        Raises:
            Error: If the mesh has no points, a face names a point that is
                not there, a value runs past its chunk, or the scene
                refuses the node.
        """
        var geometry = BufferGeometry()
        var positions = List[Float32]()
        var node = Object3D()
        node.name = name
        var materials = List[MaterialId]()
        var has_groups = False
        var has_points = False
        var matrix: Optional[Matrix4] = None
        var index = List[Int]()
        var starts = List[Int]()
        var counts = List[Int]()
        var next = self.r.next(c)
        while Bool(next):
            var sub = next.value().copy()
            if sub.id == _POINT_ARRAY:
                var points = self.r.word(sub)
                positions = List[Float32]()
                for _ in range(points * 3):
                    positions.append(self.r.float(sub))
                has_points = True
            elif sub.id == _TEX_VERTS:
                var texels = self.r.word(sub)
                var values = List[Float32]()
                for _ in range(texels * 2):
                    values.append(self.r.float(sub))
                geometry.set_attribute(String(UV), BufferAttribute(values^, 2))
            elif sub.id == _FACE_ARRAY:
                var faces = self.r.word(sub)
                index = List[Int]()
                for _ in range(faces):
                    for _ in range(3):  # pragma: no branch
                        index.append(self.r.word(sub))
                    _ = self.r.word(sub)
                var group = self.r.next(sub)
                while Bool(group):
                    var g = group.value().copy()
                    if g.id == _MSH_MAT_GROUP:
                        var material_name = self.r.string(g)
                        var count = self.r.word(g) * 3
                        var start = 0 if len(starts) == 0 else (
                            starts[len(starts) - 1] + counts[len(counts) - 1]
                        )
                        starts.append(start)
                        counts.append(count)
                        has_groups = True
                        var found = self.material_named(material_name)
                        if found >= 0:
                            materials.append(self.model.material_ids[found])
                    group = self.r.next(sub)
            elif sub.id == _MESH_MATRIX:
                var v = List[Float32]()
                for _ in range(12):  # pragma: no branch
                    v.append(self.r.float(sub))
                var m = Matrix4()
                # three.js's order, then its transpose: the columns are
                # (v0, v2, v1), (v6, v8, v7), (v3, v5, v4) and
                # (v9, v11, v10).
                var order: List[Int] = [0, 2, 1, 6, 8, 7, 3, 5, 4, 9, 11, 10]
                for k in range(12):  # pragma: no branch
                    m.elements[(k // 3) * 4 + k % 3] = v[order[k]]
                matrix = m^
            next = self.r.next(c)
        if not has_points:
            raise Error("3DS: the mesh `" + name + "` has no points")
        if Bool(matrix):
            var inverse = matrix.value().copy()
            inverse.invert()
            for k in range(0, len(positions), 3):
                var p = Vector3(
                    positions[k], positions[k + 1], positions[k + 2]
                )
                p.apply_matrix4(inverse)
                positions[k] = p.x
                positions[k + 1] = p.y
                positions[k + 2] = p.z
            decompose_onto(node, matrix.value(), "3DS")
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        if len(index) > 0:
            geometry.set_index(index^)
        for g in range(len(starts)):
            geometry.add_group(starts[g], counts[g], MaterialIndex(g))
        geometry.compute_vertex_normals()
        if not has_groups:
            materials.append(assets.materials.add(TdsMaterial().build()))
        node.parent = self.model.root
        var id = scene.add(node^)
        var geometry_id = assets.geometries.add(geometry.clone())
        if len(materials) == 1:
            scene.add_mesh(Mesh(geometry_id, materials[0], id))
        elif len(materials) > 1:
            # A group past the last material draws nothing, as three.js's
            # `material[ materialIndex ]` is `undefined` there. More than
            # one material means two groups or more: the loop runs.
            for g in range(
                min(len(starts), len(materials))
            ):  # pragma: no branch
                var part = geometry.clone()
                var slice = List[Int]()
                var end = min(starts[g] + counts[g], len(part.index))
                for k in range(starts[g], end):
                    slice.append(part.index[k])
                part.clear_groups()
                part.set_index(slice^)
                scene.add_mesh(
                    Mesh(assets.geometries.add(part^), materials[g], id)
                )
        self.model.nodes.append(id)
        self.model.names.append(name)
        self.model.geometries.append(geometry_id)
        self.model.mesh_materials.append(materials^)

    def data(
        mut self, mut c: _Chunk, mut scene: Scene, mut assets: Assets
    ) raises:
        """Read the editor chunk, three.js's `readMeshData` and
        `readNamedObject`.

        Raises:
            Error: For anything a mesh or a material refuses.
        """
        var next = self.r.next(c)
        while Bool(next):
            var sub = next.value().copy()
            if sub.id == _MASTER_SCALE:
                self.model.scale = self.r.float(sub)
            elif sub.id == _NAMED_OBJECT:
                var name = self.r.string(sub)
                var inner = self.r.next(sub)
                while Bool(inner):
                    var tri = inner.value().copy()
                    if tri.id == _N_TRI_OBJECT:
                        self.mesh(tri, name, scene, assets)
                    inner = self.r.next(sub)
            elif sub.id == _MAT_ENTRY:
                self.material(sub, assets)
            next = self.r.next(c)

    def take(deinit self) -> TdsModel:
        """Return what was read."""
        return self.model^


def _map_value(id: Int) -> Bool:
    """Return True for the four chunks that set a map's offset or scale."""
    return (
        id == _MAT_MAP_UOFFSET
        or id == _MAT_MAP_VOFFSET
        or id == _MAT_MAP_USCALE
        or id == _MAT_MAP_VSCALE
    )


def parse_3ds(
    bytes: List[UInt8],
    mut scene: Scene,
    mut assets: Assets,
    resource_path: String = "",
    parent: NodeId = NO_PARENT,
) raises -> TdsModel:
    """Read a 3DS file's bytes into a scene and its assets, three.js's
    `TDSLoader.parse`.

    Args:
        bytes: The whole file.
        scene: Where the root node, the mesh nodes and the meshes go.
        assets: Where the geometries, materials and textures go.
        resource_path: The directory the maps' files are read from.
        parent: The node the root goes under.

    Returns:
        What was read; see `TdsModel`. A file whose first chunk is not a
        main chunk gives a root with nothing under it, as in three.js.

    Raises:
        Error: If a chunk or a value runs past the end of the file, a
            chunk is shorter than its header, a mesh has no points or a
            face names a point that is not there, a map sets a value
            before its file, or a map's file is not an image
            `decode_image` reads.
    """
    var loader = _Loader(bytes.copy(), resource_path)
    var group = Object3D()
    group.parent = parent
    loader.model.root = scene.add(group^)
    loader.model.first_mesh = len(scene.meshes)
    var top = loader.r.chunk(0)
    var main = top.id == _M3DMAGIC or top.id == _MLIBMAGIC or top.id == _CMAGIC
    if main:
        var next = loader.r.next(top)
        while Bool(next):
            var sub = next.value().copy()
            if sub.id == _MDATA:
                loader.data(sub, scene, assets)
            next = loader.r.next(top)
    var scale = loader.model.scale
    var root = scene.get(loader.model.root)
    root.set_scale(scale, scale, scale)
    scene.set(loader.model.root, root^)
    var model = loader^.take()
    model.mesh_count = len(scene.meshes) - model.first_mesh
    return model^


def read_3ds(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> TdsModel:
    """Read a 3DS file, its maps from the directory it is in.

    Args:
        path: The file.
        scene: Where the nodes and meshes go.
        assets: Where the geometries, materials and textures go.
        parent: The node the root goes under.

    Returns:
        What `parse_3ds` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_3ds`
            refuses.
    """
    var slash = path.rfind("/")
    var directory = String(path[byte = : slash + 1])
    return parse_3ds(Path(path).read_bytes(), scene, assets, directory, parent)
