# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""AMF files, from three.js `examples/jsm/loaders/AMFLoader.js`.

The Additive Manufacturing File format is XML, alone or in a ZIP
archive. An `<amf>` holds metadata, `<material>`s and `<object>`s. An
object holds `<mesh>`es; a mesh holds `<vertices>` and `<volume>`s; a
volume is a list of triangles and can name a material. `parse_amf`
reads what three.js reads into a scene and its assets.

**What is built.** A root node, three.js's `Group`, named by the `name`
metadata. One node under it for each object, named by the object's
`name` metadata, in the order a JavaScript object walks their ids. One
mesh for each volume, on its object's node: the mesh's vertices and
normals, the volume's triangles, all scaled by the file's unit, in a
flat-shaded `PHONG` material. The material is the volume's, or the
object's color, or three.js's default of `0xaaaaff`.

**Units.** A millimeter is one, as in three.js: an inch is 25.4, a foot
304.8, a meter 1000 and a micron 0.001. A unit that is not known is one.
three.js scales the normals too, and makes them unit length again.

**Colors.** three.js hands the text of `<r>`, `<g>` and `<b>` to `Color`
as linear light, and the material keeps the sRGB bytes that give it.
When a color has an `<a>`, three.js compares the text with the number
1 and finds them different, so the material is transparent whatever the
alpha is. This port does the same.

**Where this port differs.** three.js logs and returns nothing for a
file whose root is not `<amf>`, and throws a `TypeError` when an object
has no `id` or a coordinate or a vertex index is missing. This port
refuses these, and a value that is not a number, which three.js reads
as `NaN`, and a vertex index past the last vertex. An empty value is
zero, as JavaScript's `Number("")` is.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.three_mf import js_key_order
from loaders.xml import NO_ELEMENT, XmlDocument, parse_xml
from loaders.zip import unzip
from materials.material import PHONG, Material, MaterialId
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.srgb import linear_to_srgb, srgb_to_linear
from std.math import isfinite, sqrt
from std.pathlib import Path


def amf_unit_scale(unit: String) -> Float64:
    """Return how many millimeters one unit is, three.js's `scaleUnits`.

    Args:
        unit: The root's `unit`, in any case.

    Returns:
        The scale; one for a unit that is not known.
    """
    var name = unit.lower()
    if name == "inch":
        return 25.4
    if name == "feet":
        return 304.8
    if name == "meter":
        return 1000.0
    if name == "micron":
        return 0.001
    return 1.0


def _number(text: String, what: String) raises -> Float64:
    """Return JavaScript's `Number(text)` for a value: zero for no text.

    Raises:
        Error: If the text is not a finite number.
    """
    var trimmed = String(text.strip())
    if trimmed.byte_length() == 0:
        return 0
    var value: Float64
    try:
        value = Float64(trimmed)
    except:
        raise Error("AMF: " + what + " is not a number: `" + text + "`")
    if not isfinite(value):
        raise Error("AMF: " + what + " is not a number: `" + text + "`")
    return value


struct AmfColor(Copyable, Movable):
    """A `<color>`: linear red, green and blue, and an alpha when one is
    given."""

    var r: Float64
    var g: Float64
    var b: Float64
    var a: Float64
    var has_alpha: Bool

    def __init__(out self):
        """Start white and opaque, with no alpha given."""
        self.r = 1
        self.g = 1
        self.b = 1
        self.a = 1
        self.has_alpha = False


def _first(doc: XmlDocument, element: Int, name: String) raises -> Int:
    """Return the first element of a name under another, at any depth,
    as `getElementsByTagName( name )[ 0 ]` finds it, or `NO_ELEMENT`."""
    for child in doc.children(element):
        if doc.name(child) == name:
            return child
        var found = _first(doc, child, name)
        if found != NO_ELEMENT:
            return found
    return NO_ELEMENT


def _text_of(doc: XmlDocument, element: Int, name: String) raises -> String:
    """Return the text of the first element of a name under another.

    Raises:
        Error: If there is none, where three.js throws a `TypeError`.
    """
    var found = _first(doc, element, name)
    if found == NO_ELEMENT:
        raise Error(
            "AMF: a `<" + doc.name(element) + ">` has no `<" + name + ">`"
        )
    return doc.text_content(found)


def _is_name(doc: XmlDocument, element: Int) raises -> Bool:
    """Return True for a `<metadata type="name">`."""
    return doc.name(element) == "metadata" and (
        doc.attribute(element, "type") == "name"
    )


def _color(doc: XmlDocument, element: Int) raises -> AmfColor:
    """Read a `<color>`, three.js's `loadColor`.

    Raises:
        Error: If a channel is not a number.
    """
    var color = AmfColor()
    for child in doc.children(element):
        var name = doc.name(child)
        if name == "r":
            color.r = _number(doc.text_content(child), "a color")
        elif name == "g":
            color.g = _number(doc.text_content(child), "a color")
        elif name == "b":
            color.b = _number(doc.text_content(child), "a color")
        elif name == "a":
            color.a = _number(doc.text_content(child), "a color")
            color.has_alpha = True
    return color^


def _authored(color: AmfColor) -> Color:
    """Return a linear color as the sRGB bytes a material holds."""
    return FloatColor(
        linear_to_srgb(Float32(color.r)),
        linear_to_srgb(Float32(color.g)),
        linear_to_srgb(Float32(color.b)),
        1,
    ).quantize()


def amf_material(color: AmfColor) raises -> Material:
    """Return the flat-shaded `PHONG` material of a color, as three.js
    makes one.

    Args:
        color: The color; with an alpha, the material is transparent.

    Returns:
        The material.

    Raises:
        Error: If `Material` refuses the opacity, such as one above one.
    """
    return Material(
        _authored(color),
        opacity=Float32(color.a) if color.has_alpha else 1,
        kind=PHONG,
        specular=Color(17, 17, 17),
        shininess=30,
        transparent=color.has_alpha,
        flat_shading=True,
    )


struct _Volume(Copyable, Movable):
    """A `<volume>`: its triangles and its material's id."""

    var triangles: List[Int]
    var material_id: String
    var has_material: Bool

    def __init__(out self):
        """Start with no triangles and no material."""
        self.triangles = List[Int]()
        self.material_id = String()
        self.has_material = False


struct _Mesh(Copyable, Movable):
    """A `<mesh>`: its vertices, normals and volumes, and its object's
    color at the time."""

    var vertices: List[Float64]
    var normals: List[Float64]
    var volumes: List[_Volume]
    var color: Optional[AmfColor]

    def __init__(out self, color: Optional[AmfColor]):
        """Start empty."""
        self.vertices = List[Float64]()
        self.normals = List[Float64]()
        self.volumes = List[_Volume]()
        self.color = color.copy()


struct AmfModel(Movable):
    """What `parse_amf` put into the scene and the assets."""

    # The root node, three.js's `Group`, and the file's `name` and
    # `author` metadata.
    var root: NodeId
    var name: String
    var author: String
    # How many millimeters one unit of the file is.
    var scale: Float64
    # One node for each object, in the order three.js walks them, with
    # its name and id.
    var objects: List[NodeId]
    var object_names: List[String]
    var object_ids: List[String]
    # One entry for each mesh drawn, in order.
    var geometries: List[GeometryId]
    var materials: List[MaterialId]
    # Each mesh's material's three.js name: the `name` metadata of its
    # `<material>`, `AMF Material` without one, or `__DEFAULT`.
    var material_names: List[String]
    # Where the meshes start in `scene.meshes`, and how many there are.
    var first_mesh: Int
    var mesh_count: Int

    def __init__(out self):
        """Start empty."""
        self.root = NO_PARENT
        self.name = String()
        self.author = String()
        self.scale = 1
        self.objects = List[NodeId]()
        self.object_names = List[String]()
        self.object_ids = List[String]()
        self.geometries = List[GeometryId]()
        self.materials = List[MaterialId]()
        self.material_names = List[String]()
        self.first_mesh = 0
        self.mesh_count = 0


def _amf_text(bytes: List[UInt8]) raises -> String:
    """Return the XML of a file: the bytes, or the first `.amf` entry of
    a ZIP archive, or its last entry when none ends in `.amf`.

    Raises:
        Error: If the archive is refused or has no entries.
    """
    var zipped = len(bytes) >= 2 and bytes[0] == 0x50 and bytes[1] == 0x4B
    if not zipped:
        return String(from_utf8_lossy=Span(bytes))
    var entries = unzip(bytes)
    if len(entries) == 0:
        raise Error("AMF: an archive with no files")
    var chosen = len(entries) - 1
    for index in range(len(entries)):  # pragma: no branch
        if entries[index].name.lower().endswith(".amf"):
            chosen = index
            break
    return String(from_utf8_lossy=Span(entries[chosen].data))


def parse_amf(
    bytes: List[UInt8],
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> AmfModel:
    """Read an AMF file's bytes into a scene and its assets, three.js's
    `AMFLoader.parse`.

    Args:
        bytes: The file, XML or a ZIP archive.
        scene: Where the nodes and meshes go.
        assets: Where the geometries and materials go.
        parent: The node the root goes under.

    Returns:
        What was read; see `AmfModel`.

    Raises:
        Error: If the archive or the XML is refused, the root is not
            `<amf>`, an object or a material has no `id`, a coordinate,
            a normal or a vertex index is missing or not a number, or an
            index is past the last vertex.
    """
    var doc = parse_xml(_amf_text(bytes))
    var root = doc.root()
    if doc.name(root).lower() != "amf":
        raise Error("AMF: no `<amf>` document found")
    var model = AmfModel()
    model.scale = amf_unit_scale(doc.attribute(root, "unit"))
    var material_ids = List[String]()
    var material_colors = List[AmfColor]()
    var material_names = List[String]()
    var object_order = List[String]()
    var object_names = List[String]()
    var object_meshes = List[List[_Mesh]]()
    for child in doc.children(root):
        var name = doc.name(child)
        if name == "metadata":
            var type = doc.attribute(child, "type")
            if type == "name":
                model.name = doc.text_content(child)
            elif type == "author":
                model.author = doc.text_content(child)
        elif name == "material":
            if not doc.has_attribute(child, "id"):
                raise Error("AMF: a `<material>` has no `id`")
            var color = AmfColor()
            var material_name = String("AMF Material")
            for part in doc.children(child):
                if _is_name(doc, part):
                    material_name = doc.text_content(part)
                elif doc.name(part) == "color":
                    color = _color(doc, part)
            material_ids.append(doc.attribute(child, "id"))
            material_colors.append(color^)
            material_names.append(material_name^)
        elif name == "object":
            if not doc.has_attribute(child, "id"):
                raise Error("AMF: an `<object>` has no `id`")
            var id = doc.attribute(child, "id")
            var object_name = String("amfobject")
            var color: Optional[AmfColor] = None
            var meshes = List[_Mesh]()
            for part in doc.children(child):
                var kind = doc.name(part)
                if _is_name(doc, part):
                    object_name = doc.text_content(part)
                elif kind == "color":
                    color = _color(doc, part)
                elif kind == "mesh":
                    meshes.append(_read_mesh(doc, part, color))
            var slot = -1
            for index in range(len(object_order)):
                if object_order[index] == id:
                    slot = index
            if slot < 0:
                object_order.append(id)
                object_names.append(object_name^)
                object_meshes.append(meshes^)
            else:
                object_names[slot] = object_name^
                object_meshes[slot] = meshes^

    var group = Object3D()
    group.name = model.name
    group.parent = parent
    model.root = scene.add(group^)
    model.first_mesh = len(scene.meshes)
    var walked = js_key_order(object_order)
    for id in walked:
        var slot = 0
        while object_order[slot] != id:
            slot += 1
        var node = Object3D()
        node.name = object_names[slot]
        node.parent = model.root
        var at = scene.add(node^)
        model.objects.append(at)
        model.object_names.append(object_names[slot])
        model.object_ids.append(id)
        for mesh in object_meshes[slot]:
            _place_mesh(
                mesh,
                material_ids,
                material_colors,
                material_names,
                at,
                model,
                scene,
                assets,
            )
    model.mesh_count = len(scene.meshes) - model.first_mesh
    return model^


def _read_mesh(
    doc: XmlDocument, element: Int, color: Optional[AmfColor]
) raises -> _Mesh:
    """Read a `<mesh>`, three.js's `loadMeshVertices` and
    `loadMeshVolume`.

    Raises:
        Error: If a coordinate, a normal or a vertex index is missing or
            not a number.
    """
    var mesh = _Mesh(color)
    for part in doc.children(element):
        var kind = doc.name(part)
        if kind == "vertices":
            for vertex in doc.children(part):
                if doc.name(vertex) != "vertex":
                    continue
                for value in doc.children(vertex):
                    var what = doc.name(value)
                    if what == "coordinates":
                        for axis in ["x", "y", "z"]:  # pragma: no branch
                            mesh.vertices.append(
                                _number(
                                    _text_of(doc, value, axis), "a coordinate"
                                )
                            )
                    elif what == "normal":
                        for axis in ["nx", "ny", "nz"]:  # pragma: no branch
                            mesh.normals.append(
                                _number(_text_of(doc, value, axis), "a normal")
                            )
        elif kind == "volume":
            var volume = _Volume()
            if doc.has_attribute(part, "materialid"):
                volume.material_id = doc.attribute(part, "materialid")
                volume.has_material = True
            for triangle in doc.children(part):
                if doc.name(triangle) != "triangle":
                    continue
                for corner in ["v1", "v2", "v3"]:  # pragma: no branch
                    var value = _number(
                        _text_of(doc, triangle, corner), "a vertex index"
                    )
                    volume.triangles.append(_index(value))
            mesh.volumes.append(volume^)
    return mesh^


def _index(value: Float64) raises -> Int:
    """Return a vertex index.

    Raises:
        Error: If it is not a whole number of zero or more.
    """
    var whole = Int(value)
    var bad = value < 0 or Float64(whole) != value
    if bad:
        raise Error("AMF: a vertex index that is not a whole number")
    return whole


def _place_mesh(
    mesh: _Mesh,
    material_ids: List[String],
    material_colors: List[AmfColor],
    material_names: List[String],
    node: NodeId,
    mut model: AmfModel,
    mut scene: Scene,
    mut assets: Assets,
) raises:
    """Add one mesh for each volume of a mesh, three.js's loop over
    `volumes`.

    Raises:
        Error: If a triangle names a vertex that is not there.
    """
    var scale = model.scale
    var positions = List[Float32]()
    for v in mesh.vertices:
        positions.append(Float32(v * scale))
    var normals = List[Float32]()
    for k in range(0, len(mesh.normals), 3):
        var x = mesh.normals[k]
        var y = mesh.normals[k + 1]
        var z = mesh.normals[k + 2]
        # three.js's `scale` turns the normals by the normal matrix, a
        # scale of one over `scale`, and makes them unit length.
        x /= scale
        y /= scale
        z /= scale
        var length = sqrt(x * x + y * y + z * z)
        if length == 0:
            length = 1
        normals.append(Float32(x / length))
        normals.append(Float32(y / length))
        normals.append(Float32(z / length))
    var count = len(mesh.vertices) // 3
    var mismatched = len(normals) > 0 and len(normals) != len(mesh.vertices)
    if mismatched:
        raise Error("AMF: a mesh has normals for some vertices only")
    for volume in mesh.volumes:
        for index in volume.triangles:
            if index >= count:
                raise Error("AMF: a triangle names a vertex that is not there")
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(positions.copy(), 3)
        )
        if len(normals) > 0:
            geometry.set_attribute(
                String(NORMAL), BufferAttribute(normals.copy(), 3)
            )
        geometry.set_index(volume.triangles.copy())
        var found = -1
        if volume.has_material:
            for index in range(len(material_ids)):
                if material_ids[index] == volume.material_id:
                    found = index
        var material: Material
        var name: String
        if found >= 0:
            material = amf_material(material_colors[found])
            name = material_names[found]
        elif Bool(mesh.color):
            material = amf_material(mesh.color.value())
            name = "__DEFAULT"
        else:
            material = _default_material()
            name = "__DEFAULT"
        var geometry_id = assets.geometries.add(geometry^)
        var material_id = assets.materials.add(material)
        scene.add_mesh(Mesh(geometry_id, material_id, node))
        model.geometries.append(geometry_id)
        model.materials.append(material_id)
        model.material_names.append(name^)


def _default_material() raises -> Material:
    """Return three.js's default: `0xaaaaff`, flat-shaded."""
    return Material(
        Color(0xAA, 0xAA, 0xFF),
        kind=PHONG,
        specular=Color(17, 17, 17),
        shininess=30,
        flat_shading=True,
    )


def read_amf(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> AmfModel:
    """Read an AMF file.

    Args:
        path: The file.
        scene: Where the nodes and meshes go.
        assets: Where the geometries and materials go.
        parent: The node the root goes under.

    Returns:
        What `parse_amf` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_amf`
            refuses.
    """
    return parse_amf(Path(path).read_bytes(), scene, assets, parent)
