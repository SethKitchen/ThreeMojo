# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""3MF files, from three.js `examples/jsm/loaders/3MFLoader.js`.

A 3MF file is a ZIP archive of XML parts. `read_3mf` and `parse_3mf`
open the archive with `loaders.zip`, read its model parts with
`loaders.xml`, and add what the build names to a scene, as three.js's
`ThreeMFLoader.parse` builds a `Group`.

**The archive.** `_rels/.rels` names the root model part, the first
relationship whose target ends in `.model`. The root model is the one
`.model` file straight inside `3D/`; a `.model` file deeper in `3D/` is a
sub model, read first. `3D/_rels/*.model.rels` names the texture files,
which live in `3D/Texture/` or `3D/Textures/`.

**A model part.** Its root element is `<model>`, whose `unit` is one of
`micron`, `millimeter`, `centimeter`, `inch`, `foot` and `meter`, and
millimeter when it is missing. The unit is kept as a `Length` and not
applied, as three.js keeps it. `<metadata>` with one of three.js's eight
names is kept. `<resources>` holds `<basematerials>`, `<colorgroup>`,
`<texture2d>`, `<texture2dgroup>`, `<pbmetallicdisplayproperties>` and
`<object>`; `<build>` holds the `<item>`s placed. Elements match by their
local name, so `m:colorgroup` is a `colorgroup`, as a CSS selector
matches it.

**What is built.** Each object becomes a node. A mesh object's triangles
are grouped by their `pid`, or the object's, into one mesh each:

- A `basematerials` group: one mesh per material index, `p1` or the
  object's `pindex`, of positions only. Its material is `STANDARD`, with
  roughness and metalness, when the base material names
  `pbmetallicdisplayproperties`; otherwise `PHONG`. The color is the
  `displaycolor`, and a ninth and tenth hex digit are its opacity.
- A `texture2dgroup`: positions and texture coordinates from `p1`, `p2`
  and `p3`, with a `PHONG` material that maps the texture.
- A `colorgroup`: positions and a color at each corner, from `p1`, `p2`
  and `p3`, each falling back as three.js falls back, with a `PHONG`
  material of vertex colors.
- No `pid` at all: the whole mesh, indexed, with a white `PHONG`
  material named `__DEFAULT`.

Every material is flat shaded. A component object places its components'
nodes under its own, each at its `transform`. Every build item places its
object under the root node at its `transform`. A mesh sits on a node of
its own under its object's node, and both take the object's `name`, as
three.js's meshes and groups do. A geometry and a material are made once
and shared by every place that shows them, as three.js's clones share
them.

**Order.** three.js walks its dictionaries in JavaScript key order: keys
that are array indices first, by value, then the rest in the order they
were added. This walks them the same way, so the meshes come out in
three.js's order.

**Where this port differs.** A material has no
name here, so the names are in `ThreeMfModel.material_names`. three.js's
extensions and implicit functions are not read. three.js logs and
skips a `pid` that names no resource, a missing `.model` root and a
missing texture; this refuses them. It also refuses a vertex index,
a material index or a property index out of range, a number that is not
finite, a component that contains itself, and an object with neither a
mesh nor components, where three.js reads `undefined` or recurses without
end.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, UV, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.gltf import decode_image
from loaders.model_nodes import decompose_onto
from loaders.xml import NO_ELEMENT, XmlDocument, parse_xml
from loaders.zip import ZipEntry, unzip
from materials.material import PHONG, STANDARD, Material, MaterialId
from math.matrix4 import Matrix4
from objects.mesh import Mesh
from render.css_color import parse_style
from render.framebuffer import Color, FloatColor
from render.srgb import SRGB, linear_to_srgb
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    MIRROR,
    NEAREST,
    REPEAT,
    Filter,
    Wrap,
    texture_from,
)
from render.texture_store import NO_TEXTURE, TextureId
from std.math import isfinite
from std.pathlib import Path
from units.si import CENTIMETER, FOOT, INCH, METER, MILLIMETER, Length

# The name three.js gives the material of a mesh with no properties,
# `Loader.DEFAULT_MATERIAL_NAME`.
comptime DEFAULT_MATERIAL_NAME = "__DEFAULT"
# How deep components can nest before a file is refused as a loop.
comptime MAX_COMPONENT_DEPTH = 64


struct ThreeMfModel(Copyable, Movable):
    """What `parse_3mf` put into the scene and the assets."""

    # The node three.js returns as its `Group`: every build item hangs
    # on it.
    var root: NodeId
    # The root model's `unit`, the length of one unit of the file.
    var unit: Length
    # The root model's metadata three.js keeps, in the order first seen.
    var metadata_names: List[String]
    var metadata_values: List[String]
    # Every node placed, in the order placed, and its name.
    var nodes: List[NodeId]
    var node_names: List[String]
    # Every material made, in the order made, and its name.
    var materials: List[MaterialId]
    var material_names: List[String]
    # Every geometry made, in the order made.
    var geometries: List[GeometryId]
    # Every texture read, in the order read.
    var textures: List[TextureId]
    # Where the meshes this file added begin in the scene's list, and how
    # many there are.
    var first_mesh: Int
    var mesh_count: Int

    def __init__(out self):
        """Start empty."""
        self.root = NO_PARENT
        self.unit = Length(1.0, MILLIMETER)
        self.metadata_names = List[String]()
        self.metadata_values = List[String]()
        self.nodes = List[NodeId]()
        self.node_names = List[String]()
        self.materials = List[MaterialId]()
        self.material_names = List[String]()
        self.geometries = List[GeometryId]()
        self.textures = List[TextureId]()
        self.first_mesh = 0
        self.mesh_count = 0


def three_mf_unit(name: String) raises -> Length:
    """Return the length one unit of a 3MF model stands for.

    Args:
        name: `micron`, `millimeter`, `centimeter`, `inch`, `foot` or
            `meter`.

    Returns:
        The length.

    Raises:
        Error: If the name is none of the six.
    """
    if name == "micron":
        return Length(1e-6, METER)
    if name == "millimeter":
        return Length(1.0, MILLIMETER)
    if name == "centimeter":
        return Length(1.0, CENTIMETER)
    if name == "inch":
        return Length(1.0, INCH)
    if name == "foot":
        return Length(1.0, FOOT)
    if name == "meter":
        return Length(1.0, METER)
    raise Error("3MF: a unit that is not known: `" + name + "`")


def three_mf_wrap(style: String) -> Wrap:
    """Return the wrap a `tilestyleu` or a `tilestylev` names, as three.js's `buildTexture`
    reads it.

    Args:
        style: `wrap`, `mirror`, `clamp` or `none`, or anything else.

    Returns:
        `MIRROR` for `mirror`, `CLAMP` for `clamp` and `none`, and
        `REPEAT` for anything else.
    """
    if style == "mirror":
        return MIRROR
    if style == "clamp" or style == "none":
        return CLAMP
    return REPEAT


def three_mf_transform(text: String) raises -> Matrix4:
    """Return the matrix a `transform` attribute names.

    The twelve numbers are the matrix's rows of three, the last row the
    translation, as 3MF writes them and three.js's `parseTransform`
    reads them.

    Args:
        text: Twelve numbers split by white space.

    Returns:
        The matrix.

    Raises:
        Error: If there are not twelve finite numbers.
    """
    var numbers = List[Float32]()
    for piece in text.split():
        numbers.append(_finite(String(piece), "a transform"))
    if len(numbers) != 12:
        raise Error("3MF: a transform must have twelve numbers: " + text)
    var matrix = Matrix4()
    for column in range(4):  # pragma: no branch
        for row in range(3):  # pragma: no branch
            matrix.elements[column * 4 + row] = numbers[column * 3 + row]
    return matrix^


def js_key_order(keys: List[String]) -> List[String]:
    """Return keys in the order a JavaScript object walks them.

    Args:
        keys: The keys, in the order they were added, each once.

    Returns:
        The keys that are array indices, from smallest, then the others
        in the order given.
    """
    var indices = List[Int]()
    var others = List[String]()
    for key in keys:
        var index = _array_index(key)
        if index >= 0:
            indices.append(index)
        else:
            others.append(key)
    sort(indices)
    var out = List[String]()
    for index in indices:
        out.append(String(index))
    for key in others:
        out.append(key)
    return out^


def _array_index(key: String) -> Int:
    """Return the array index a key is, or -1.

    Args:
        key: The key.

    Returns:
        Its value when it is a whole number written without a sign or a
        leading zero and below 2^32 - 1, or -1.
    """
    var bytes = key.as_bytes()
    if len(bytes) == 0 or len(bytes) > 10:
        return -1
    if len(bytes) > 1 and bytes[0] == 48:
        return -1
    var value = 0
    # The key is not empty here: the loop always runs.
    for byte in bytes:  # pragma: no branch
        if byte < 48 or byte > 57:
            return -1
        value = value * 10 + Int(byte) - 48
    if value >= 0xFFFFFFFF:
        return -1
    return value


def _finite(text: String, what: String) raises -> Float32:
    """Return a number an attribute gives.

    Args:
        text: The text.
        what: What it is, for the error.

    Returns:
        The number, as the `Float32` three.js's typed arrays hold.

    Raises:
        Error: If it is not a number, or is not finite as a `Float32`.
    """
    var value: Float64
    try:
        value = Float64(text)
    except:
        raise Error("3MF: " + what + " is not a number: `" + text + "`")
    var narrow = Float32(value)
    if not isfinite(narrow):
        raise Error("3MF: " + what + " is not finite: `" + text + "`")
    return narrow


def _index(text: String, count: Int, what: String) raises -> Int:
    """Return an index an attribute gives, checked against a count.

    Args:
        text: The text.
        count: How many there are to index.
        what: What it indexes, for the error.

    Returns:
        The index.

    Raises:
        Error: If it is not a whole number from zero to `count` less one.
    """
    var value: Int
    try:
        value = Int(text)
    except:
        raise Error("3MF: " + what + " index is not a whole number: " + text)
    if value < 0 or value >= count:
        raise Error(
            "3MF: "
            + what
            + " index "
            + text
            + " is out of range, and there are "
            + String(count)
        )
    return value


def _kept_metadata(name: String) -> Bool:
    """Return True for the eight metadata names three.js keeps."""
    for kept in [
        "Title",
        "Designer",
        "Description",
        "Copyright",
        "LicenseTerms",
        "Rating",
        "CreationDate",
        "ModificationDate",
    ]:  # pragma: no branch
        if name == kept:
            return True
    return False


def _local(name: String) -> String:
    """Return an element's name without its prefix."""
    var colon = name.find(":")
    if colon < 0:
        return name
    return String(name[byte = colon + 1 :])


@fieldwise_init
struct _Triangle(Copyable, Movable):
    """One `<triangle>`: its corners and its properties, as text."""

    var v: List[Int]
    # `p1`, `p2` and `p3`, empty when absent.
    var p: List[String]
    var pid: String


@fieldwise_init
struct _Part(Movable):
    """One model part: its document and its resources by id."""

    var name: String
    var document: XmlDocument
    var unit: Length
    # Each resource kind's elements by `id`, in file order.
    var basematerials: Dict[String, Int]
    var colorgroups: Dict[String, Int]
    var texture2ds: Dict[String, Int]
    var texture2dgroups: Dict[String, Int]
    var displayproperties: Dict[String, Int]
    var objects: Dict[String, Int]
    var object_ids: List[String]
    var build: Int


@fieldwise_init
struct _Built(Copyable, Movable):
    """An object as built once: meshes, or components."""

    var name: String
    var geometries: List[GeometryId]
    var materials: List[MaterialId]
    # For a component object: each component's object id and transform.
    var component_ids: List[String]
    var component_transforms: List[Optional[Matrix4]]


struct _Loader(Movable):
    """Builds every object of every part, then places the build."""

    var entries: List[ZipEntry]
    var parts: List[_Part]
    # The textures by the target their model relationship names.
    var texture_files: Dict[String, Int]
    var built: Dict[String, _Built]
    # A material made once per base material, by part, group and index.
    var base_cache: Dict[String, MaterialId]
    # A texture read once per texture group, by part and id.
    var texture_cache: Dict[String, TextureId]
    var model: ThreeMfModel

    def __init__(out self, var entries: List[ZipEntry]):
        """Start with the archive's entries.

        Args:
            entries: The archive.
        """
        self.entries = entries^
        self.parts = List[_Part]()
        self.texture_files = Dict[String, Int]()
        self.built = Dict[String, _Built]()
        self.base_cache = Dict[String, MaterialId]()
        self.texture_cache = Dict[String, TextureId]()
        self.model = ThreeMfModel()

    def text(self, entry: Int) -> String:
        """Return an entry's bytes as text."""
        return String(from_utf8_lossy=Span(self.entries[entry].data))

    def relationship_targets(self, entry: Int) raises -> List[String]:
        """Return the `Target` of every `<Relationship>` in a rels part.

        Args:
            entry: The part.

        Returns:
            The targets, in file order.

        Raises:
            Error: If the part is not XML.
        """
        var document = parse_xml(self.text(entry))
        var targets = List[String]()
        for element in _descendants(document, document.root(), "Relationship"):
            targets.append(document.attribute(element, "Target"))
        return targets^

    def read_part(mut self, name: String, entry: Int) raises:
        """Read one model part and index its resources.

        Args:
            name: The part's name in the archive.
            entry: Its entry.

        Raises:
            Error: If it is not XML, its root is not `<model>`, or its
                unit is not known.
        """
        var document = parse_xml(self.text(entry))
        var root = document.root()
        if _local(document.name(root)).lower() != "model":
            raise Error("3MF: the part `" + name + "` is not a <model>")
        var unit = three_mf_unit(document.attribute(root, "unit", "millimeter"))
        var part = _Part(
            name,
            document^,
            unit,
            Dict[String, Int](),
            Dict[String, Int](),
            Dict[String, Int](),
            Dict[String, Int](),
            Dict[String, Int](),
            Dict[String, Int](),
            List[String](),
            NO_ELEMENT,
        )
        ref doc = part.document
        var resources = _first(doc, root, "resources")
        if resources != NO_ELEMENT:
            _index_by_id(doc, resources, "basematerials", part.basematerials)
            _index_by_id(doc, resources, "texture2d", part.texture2ds)
            _index_by_id(doc, resources, "colorgroup", part.colorgroups)
            _index_by_id(
                doc,
                resources,
                "pbmetallicdisplayproperties",
                part.displayproperties,
            )
            _index_by_id(doc, resources, "texture2dgroup", part.texture2dgroups)
            var ids = List[String]()
            for element in _descendants(doc, resources, "object"):
                var id = doc.attribute(element, "id")
                if id not in part.objects:
                    ids.append(id)
                part.objects[id] = element
            part.object_ids = js_key_order(ids)
        part.build = _first(doc, root, "build")
        self.parts.append(part^)

    def metadata(mut self, part: Int) raises:
        """Keep a part's metadata that three.js keeps.

        Args:
            part: The part.

        Raises:
            Error: If an index is out of range; not expected.
        """
        ref doc = self.parts[part].document
        for element in _descendants(doc, doc.root(), "metadata"):
            var name = doc.attribute(element, "name")
            if not _kept_metadata(name):
                continue
            var value = doc.text_content(element)
            var found = False
            for index in range(len(self.model.metadata_names)):
                if self.model.metadata_names[index] == name:
                    self.model.metadata_values[index] = value
                    found = True
            if not found:
                self.model.metadata_names.append(name)
                self.model.metadata_values.append(value)

    def build_object(
        mut self, part: Int, id: String, mut assets: Assets
    ) raises:
        """Build an object of a part once, as three.js's `buildObject`.

        Args:
            part: The part.
            id: The object's `id`.
            assets: Where its geometries, materials and textures go.

        Raises:
            Error: If the object has neither a mesh nor components, or
                building a mesh fails.
        """
        ref doc = self.parts[part].document
        var element = self.parts[part].objects[id]
        var name = doc.attribute(element, "name")
        var built = _Built(
            name,
            List[GeometryId](),
            List[MaterialId](),
            List[String](),
            List[Optional[Matrix4]](),
        )
        var mesh = _first(doc, element, "mesh")
        var components = _first(doc, element, "components")
        if mesh != NO_ELEMENT:
            self.build_meshes(part, element, mesh, built, assets)
        elif components != NO_ELEMENT:
            for component in _descendants(doc, components, "component"):
                built.component_ids.append(doc.attribute(component, "objectid"))
                var transform = doc.attribute(component, "transform")
                if transform == "":
                    built.component_transforms.append(None)
                else:
                    built.component_transforms.append(
                        three_mf_transform(transform)
                    )
        else:
            raise Error(
                "3MF: object " + id + " has neither a <mesh> nor <components>"
            )
        self.built[id] = built^

    def build_meshes(
        mut self,
        part: Int,
        object: Int,
        mesh: Int,
        mut built: _Built,
        mut assets: Assets,
    ) raises:
        """Build a mesh object's meshes, one per property group, as
        three.js's `buildGroup`.

        Args:
            part: The part.
            object: The `<object>`.
            mesh: Its `<mesh>`.
            built: Where the meshes go.
            assets: Where the geometries, materials and textures go.

        Raises:
            Error: If a vertex is not three finite numbers, a triangle
                names a vertex out of range, a `pid` names no resource,
                or a group's mesh cannot be built.
        """
        ref doc = self.parts[part].document
        var vertices = List[Float32]()
        for element in _nested(doc, mesh, "vertices", "vertex"):
            for axis in ["x", "y", "z"]:  # pragma: no branch
                vertices.append(
                    _finite(doc.attribute(element, axis), "a vertex " + axis)
                )
        var count = len(vertices) // 3
        var triangles = List[_Triangle]()
        var object_pid = doc.attribute(object, "pid")
        var groups = Dict[String, List[Int]]()
        var keys = List[String]()
        for element in _nested(doc, mesh, "triangles", "triangle"):
            var corners = List[Int]()
            var properties = List[String]()
            for corner in ["1", "2", "3"]:  # pragma: no branch
                corners.append(
                    _index(
                        doc.attribute(element, "v" + corner), count, "vertex"
                    )
                )
                properties.append(doc.attribute(element, "p" + corner))
            var pid = doc.attribute(element, "pid")
            if pid == "":
                pid = object_pid
            if pid == "":
                pid = "default"
            if pid not in groups:
                groups[pid] = List[Int]()
                keys.append(pid)
            groups[pid].append(len(triangles))
            triangles.append(_Triangle(corners^, properties^, pid))
        for key in js_key_order(keys):
            var chosen = List[_Triangle]()
            # A group holds a triangle or more: the loop always runs.
            for at in groups[key]:  # pragma: no branch
                chosen.append(triangles[at].copy())
            var textured = key in self.parts[part].texture2dgroups
            var based = key in self.parts[part].basematerials
            var colored = key in self.parts[part].colorgroups
            if textured:
                self.textured_mesh(part, key, chosen, vertices, built, assets)
            elif based:
                self.material_meshes(
                    part, key, object, chosen, vertices, built, assets
                )
            elif colored:
                self.color_mesh(
                    part, key, object, chosen, vertices, built, assets
                )
            elif key == "default":
                self.default_mesh(triangles, vertices, built, assets)
            else:
                raise Error("3MF: a `pid` that names no resource: " + key)

    def add_mesh(
        mut self,
        var geometry: BufferGeometry,
        material: MaterialId,
        mut built: _Built,
        mut assets: Assets,
    ):
        """Keep one mesh of an object.

        Args:
            geometry: Its geometry, added to the assets.
            material: Its material.
            built: The object.
            assets: Where the geometry goes.
        """
        var id = assets.geometries.add(geometry^)
        self.model.geometries.append(id)
        built.geometries.append(id)
        built.materials.append(material)

    def add_material(
        mut self, material: Material, name: String, mut assets: Assets
    ) -> MaterialId:
        """Add a material and keep its name.

        Args:
            material: The material.
            name: Its name, as three.js names it.
            assets: Where it goes.

        Returns:
            Its id.
        """
        var id = assets.materials.add(material)
        self.model.materials.append(id)
        self.model.material_names.append(name)
        return id

    def material_meshes(
        mut self,
        part: Int,
        key: String,
        object: Int,
        triangles: List[_Triangle],
        vertices: List[Float32],
        mut built: _Built,
        mut assets: Assets,
    ) raises:
        """Build one mesh per base material of a group, as three.js's
        `buildBasematerialsMeshes`.

        Raises:
            Error: If a material index is missing or out of range, a
                color is not one `setStyle` reads, or a display
                properties entry is missing.
        """
        ref doc = self.parts[part].document
        var group = self.parts[part].basematerials[key]
        var bases = _descendants(doc, group, "base")
        var object_pindex = doc.attribute(object, "pindex")
        var by_index = Dict[String, List[Int]]()
        var keys = List[String]()
        # A group holds a triangle or more: these loops always run.
        for at in range(len(triangles)):  # pragma: no branch
            var pindex = triangles[at].p[0]
            if pindex == "":
                pindex = object_pindex
            var index = String(_index(pindex, len(bases), "material"))
            if index not in by_index:
                by_index[index] = List[Int]()
                keys.append(index)
            by_index[index].append(at)
        for index in js_key_order(keys):  # pragma: no branch
            var material = self.base_material(
                part, key, bases, Int(index), assets
            )
            var positions = List[Float32]()
            for at in by_index[index]:  # pragma: no branch
                _push_corners(positions, triangles[at], vertices)
            var geometry = BufferGeometry()
            geometry.set_attribute(
                String(POSITION), BufferAttribute(positions^, 3)
            )
            self.add_mesh(geometry^, material, built, assets)

    def base_material(
        mut self,
        part: Int,
        key: String,
        bases: List[Int],
        index: Int,
        mut assets: Assets,
    ) raises -> MaterialId:
        """Return a base material's material, made the first time, as
        three.js's `buildBasematerial` makes it.

        Raises:
            Error: If the color is not one `setStyle` reads, or the
                display properties have no entry for the index.
        """
        var cache = String(part) + "/" + key + "/" + String(index)
        if cache in self.base_cache:
            return self.base_cache[cache]
        ref doc = self.parts[part].document
        var base = bases[index]
        var name = doc.attribute(base, "name")
        var display = doc.attribute(base, "displaycolor")
        var color = _authored(display)
        var opacity = Float32(1)
        if display.byte_length() == 9:
            opacity = Float32(_hex_byte(display)) / 255
        var properties = doc.attribute(base, "displaypropertiesid")
        var material: Material
        if properties in self.parts[part].displayproperties:
            var metallic = _descendants(
                doc,
                self.parts[part].displayproperties[properties],
                "pbmetallic",
            )
            if index >= len(metallic):
                raise Error(
                    "3MF: display properties "
                    + properties
                    + " have no entry "
                    + String(index)
                )
            material = Material(
                color,
                kind=STANDARD,
                opacity=opacity,
                flat_shading=True,
                roughness=_finite(
                    doc.attribute(metallic[index], "roughness"), "a roughness"
                ),
                metalness=_finite(
                    doc.attribute(metallic[index], "metallicness"),
                    "a metallicness",
                ),
            )
        else:
            material = _phong(color, opacity)
        var id = self.add_material(material, name, assets)
        self.base_cache[cache] = id
        return id

    def textured_mesh(
        mut self,
        part: Int,
        key: String,
        triangles: List[_Triangle],
        vertices: List[Float32],
        mut built: _Built,
        mut assets: Assets,
    ) raises:
        """Build a group's textured mesh, as three.js's
        `buildTexturedMesh`.

        Raises:
            Error: If a coordinate is not finite, an index is missing or
                out of range, or the texture cannot be read.
        """
        ref doc = self.parts[part].document
        var group = self.parts[part].texture2dgroups[key]
        var uvs = List[Float32]()
        for element in _descendants(doc, group, "tex2coord"):
            uvs.append(_finite(doc.attribute(element, "u"), "a u"))
            uvs.append(_finite(doc.attribute(element, "v"), "a v"))
        var positions = List[Float32]()
        var coordinates = List[Float32]()
        # A group holds a triangle or more: the loop always runs.
        for triangle in triangles:  # pragma: no branch
            _push_corners(positions, triangle, vertices)
            for corner in range(3):  # pragma: no branch
                var at = _index(triangle.p[corner], len(uvs) // 2, "texture")
                coordinates.append(uvs[at * 2])
                coordinates.append(uvs[at * 2 + 1])
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        geometry.set_attribute(String(UV), BufferAttribute(coordinates^, 2))
        var map = self.group_texture(part, key, assets)
        var material = Material(
            Color(255, 255, 255),
            map=map,
            kind=PHONG,
            specular=Color(17, 17, 17),
            shininess=30,
            flat_shading=True,
        )
        var id = self.add_material(material, "", assets)
        self.add_mesh(geometry^, id, built, assets)

    def group_texture(
        mut self, part: Int, key: String, mut assets: Assets
    ) raises -> TextureId:
        """Return a texture group's texture, read the first time, as
        three.js's `buildTexture` reads it.

        Returns:
            The texture, or `NO_TEXTURE` when the group's `texid` names
            no `<texture2d>`, as three.js makes a material with no map.

        Raises:
            Error: If the texture's file is not in the archive or is not
                an image `decode_image` reads.
        """
        var cache = String(part) + "/" + key
        if cache in self.texture_cache:
            return self.texture_cache[cache]
        ref doc = self.parts[part].document
        var group = self.parts[part].texture2dgroups[key]
        var texid = doc.attribute(group, "texid")
        var id = NO_TEXTURE
        if texid in self.parts[part].texture2ds:
            var element = self.parts[part].texture2ds[texid]
            var path = doc.attribute(element, "path")
            if path not in self.texture_files:
                raise Error(
                    "3MF: the texture `"
                    + path
                    + "` is not in the archive and its model relationships"
                )
            var filter_name = doc.attribute(element, "filter")
            var filter = BILINEAR
            var mipmapped = True
            if filter_name == "linear":
                mipmapped = False
            elif filter_name == "nearest":
                filter = NEAREST
                mipmapped = False
            var texture = texture_from(
                decode_image(self.entries[self.texture_files[path]].data),
                three_mf_wrap(doc.attribute(element, "tilestyleu")),
                filter,
                SRGB,
                mipmapped,
                COVERAGE,
            )
            texture.wrap_t = three_mf_wrap(doc.attribute(element, "tilestylev"))
            id = assets.textures.add(texture^)
            self.model.textures.append(id)
        self.texture_cache[cache] = id
        return id

    def color_mesh(
        mut self,
        part: Int,
        key: String,
        object: Int,
        triangles: List[_Triangle],
        vertices: List[Float32],
        mut built: _Built,
        mut assets: Assets,
    ) raises:
        """Build a group's vertex-colored mesh, as three.js's
        `buildVertexColorMesh`.

        Raises:
            Error: If a color is not one `setStyle` reads, or an index is
                missing or out of range.
        """
        ref doc = self.parts[part].document
        var group = self.parts[part].colorgroups[key]
        var colors = List[FloatColor]()
        for element in _descendants(doc, group, "color"):
            colors.append(_linear(doc.attribute(element, "color")))
        var object_pindex = doc.attribute(object, "pindex")
        var positions = List[Float32]()
        var values = List[Float32]()
        # A group holds a triangle or more: the loop always runs.
        for triangle in triangles:  # pragma: no branch
            _push_corners(positions, triangle, vertices)
            var first = triangle.p[0]
            if first == "":
                first = object_pindex
            for corner in range(3):  # pragma: no branch
                var text = triangle.p[corner]
                if text == "":
                    text = first
                var color = colors[_index(text, len(colors), "color")]
                values.append(color.r)
                values.append(color.g)
                values.append(color.b)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        geometry.set_attribute(String(COLOR), BufferAttribute(values^, 3))
        var material = Material(
            Color(255, 255, 255),
            kind=PHONG,
            specular=Color(17, 17, 17),
            shininess=30,
            vertex_colors=True,
            flat_shading=True,
        )
        var id = self.add_material(material, "", assets)
        self.add_mesh(geometry^, id, built, assets)

    def default_mesh(
        mut self,
        triangles: List[_Triangle],
        vertices: List[Float32],
        mut built: _Built,
        mut assets: Assets,
    ) raises:
        """Build the whole mesh with the default material, as three.js's
        `buildDefaultMesh`: every triangle, not only those with no
        property."""
        var index = List[Int]()
        # A group holds a triangle or more: the loop always runs.
        for triangle in triangles:  # pragma: no branch
            index.extend(triangle.v.copy())
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(vertices.copy(), 3)
        )
        geometry.set_index(index^)
        var id = self.add_material(
            _phong(Color(255, 255, 255), 1), DEFAULT_MATERIAL_NAME, assets
        )
        self.add_mesh(geometry^, id, built, assets)

    def place(
        mut self,
        id: String,
        parent: NodeId,
        transform: Optional[Matrix4],
        mut scene: Scene,
        depth: Int,
    ) raises:
        """Place a built object under a node, as three.js's clone and
        `applyMatrix4` place it.

        Args:
            id: The object's id.
            parent: The node to place it under.
            transform: Its transform, or none.
            scene: The scene.
            depth: How many components deep this is.

        Raises:
            Error: If no object has the id, or components nest past
                `MAX_COMPONENT_DEPTH`.
        """
        if id not in self.built:
            raise Error("3MF: no object has the id `" + id + "`")
        if depth > MAX_COMPONENT_DEPTH:
            raise Error("3MF: components nest too deep, or contain themselves")
        var built = self.built[id].copy()
        var node = Object3D()
        node.name = built.name
        if Bool(transform):
            decompose_onto(node, transform.value(), "3MF")
        var at = scene.attach(node^, parent)
        self.model.nodes.append(at)
        self.model.node_names.append(built.name)
        for index in range(len(built.geometries)):
            var holder = Object3D()
            holder.name = built.name
            var slot = scene.attach(holder^, at)
            self.model.nodes.append(slot)
            self.model.node_names.append(built.name)
            scene.add_mesh(
                Mesh(built.geometries[index], built.materials[index], slot)
            )
        for index in range(len(built.component_ids)):
            self.place(
                built.component_ids[index],
                at,
                built.component_transforms[index],
                scene,
                depth + 1,
            )


def _descendants(
    document: XmlDocument, element: Int, name: String
) raises -> List[Int]:
    """Return every element under one with a local name, in document
    order, as `querySelectorAll` finds them.

    Args:
        document: The document.
        element: Where to search under.
        name: The local name.

    Returns:
        The elements.

    Raises:
        Error: If the index names no element; not expected.
    """
    var found = List[Int]()
    for child in document.children(element):
        if _local(document.name(child)) == name:
            found.append(child)
        found.extend(_descendants(document, child, name))
    return found^


def _first(document: XmlDocument, element: Int, name: String) raises -> Int:
    """Return the first element under one with a local name, or
    `NO_ELEMENT`, as `querySelector` finds it."""
    var found = _descendants(document, element, name)
    if len(found) == 0:
        return NO_ELEMENT
    return found[0]


def _nested(
    document: XmlDocument, element: Int, outer: String, inner: String
) raises -> List[Int]:
    """Return every `inner` inside an `outer` under an element, as the
    selector `outer inner` finds them."""
    var found = List[Int]()
    for container in _descendants(document, element, outer):
        found.extend(_descendants(document, container, inner))
    return found^


def _index_by_id(
    document: XmlDocument,
    resources: Int,
    name: String,
    mut into: Dict[String, Int],
) raises:
    """Index the resources of one kind by `id`; a later one wins, as a
    later key wins in three.js's dictionaries."""
    for element in _descendants(document, resources, name):
        into[document.attribute(element, "id")] = element


def _push_corners(
    mut positions: List[Float32], triangle: _Triangle, vertices: List[Float32]
):
    """Append a triangle's three corners' positions."""
    for corner in triangle.v:  # pragma: no branch
        for axis in range(3):  # pragma: no branch
            positions.append(vertices[corner * 3 + axis])


def _linear(style: String) raises -> FloatColor:
    """Return the linear color a 3MF color names, as three.js's
    `setStyle( color.substring( 0, 7 ), SRGBColorSpace )` reads it.

    Raises:
        Error: If the text is not a color `setStyle` reads.
    """
    var head = String(style[byte = 0 : min(7, style.byte_length())])
    return parse_style(head, SRGB)


def _authored(style: String) raises -> Color:
    """Return a 3MF color as the eight-bit sRGB color a material holds.

    Raises:
        Error: If the text is not a color `setStyle` reads.
    """
    var linear = _linear(style)
    return FloatColor(
        linear_to_srgb(linear.r),
        linear_to_srgb(linear.g),
        linear_to_srgb(linear.b),
        1,
    ).quantize()


def _hex_byte(display: String) raises -> Int:
    """Return the alpha a nine-character `#RRGGBBAA` color ends with, as
    three.js's `parseInt( charAt( 7 ) + charAt( 8 ), 16 )` reads it.

    Raises:
        Error: If the two characters are not hex digits.
    """
    var value = 0
    for byte in display.as_bytes()[7:9]:  # pragma: no branch
        var digit: Int
        if byte >= 48 and byte <= 57:
            digit = Int(byte) - 48
        elif byte >= 97 and byte <= 102:
            digit = Int(byte) - 87
        elif byte >= 65 and byte <= 70:
            digit = Int(byte) - 55
        else:
            raise Error("3MF: a color's alpha is not hex: " + display)
        value = value * 16 + digit
    return value


def _phong(color: Color, opacity: Float32) raises -> Material:
    """Return three.js's flat `MeshPhongMaterial` of a color.

    Raises:
        Error: If the opacity is outside zero to one; not expected.
    """
    return Material(
        color,
        kind=PHONG,
        opacity=opacity,
        specular=Color(17, 17, 17),
        shininess=30,
        flat_shading=True,
    )


def _entry_role(name: String) -> Int:
    """Return what an archive path is to three.js's `loadDocument`.

    Returns:
        0 for the root relationships, 1 for the model relationships, 2
        for the root model, 3 for a sub model, 4 for a texture, and -1
        for anything else.
    """
    var length = name.byte_length()
    var tail = String(name[byte = max(0, length - 11) : max(0, length - 5)])
    if length >= 11 and tail == "_rels/" and name.endswith("rels"):
        return 0
    var rels_at = name.find("3D/_rels/")
    if rels_at >= 0 and length >= rels_at + 20 and name.endswith(".model.rels"):
        return 1
    if name.startswith("3D/") and name.endswith(".model"):
        if String(name[byte=3:]).find("/") < 0:
            return 2
        return 3
    if name.startswith("3D/Texture/") or name.startswith("3D/Textures/"):
        return 4
    return -1


def parse_3mf(
    bytes: List[UInt8], mut scene: Scene, mut assets: Assets
) raises -> ThreeMfModel:
    """Read a 3MF archive's bytes into a scene and its assets.

    Args:
        bytes: The archive.
        scene: The scene to add the nodes and meshes to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where.

    Raises:
        Error: If the archive is not one `unzip` reads; it has no
            `_rels/.rels`, no root model, or no relationship to a
            `.model` part; a part is not XML or not a `<model>`; or
            building or placing an object fails. See the module
            docstring.
    """
    var loader = _Loader(unzip(bytes))
    var rels = -1
    var model_rels = -1
    var root_model = -1
    var models = List[Int]()
    var textures = Dict[String, Int]()
    for index in range(len(loader.entries)):
        var role = _entry_role(loader.entries[index].name)
        if role == 0:
            rels = index
        elif role == 1:
            model_rels = index
        elif role == 2:
            root_model = index
        elif role == 3:
            models.append(index)
        elif role == 4:
            textures[loader.entries[index].name] = index
    if rels < 0:
        raise Error("3MF: the archive has no relationship file `_rels/.rels`")
    if root_model < 0:
        raise Error("3MF: the archive has no root model in `3D/`")
    models.append(root_model)
    var targets = loader.relationship_targets(rels)
    if model_rels >= 0:
        for target in loader.relationship_targets(model_rels):
            var key = String(target[byte=1:])
            if key in textures:
                loader.texture_files[target] = textures[key]
    # The root model is always there: these loops always run.
    for index in models:  # pragma: no branch
        var name = loader.entries[index].name
        loader.read_part(name, index)
    for part in range(len(loader.parts)):  # pragma: no branch
        for id in loader.parts[part].object_ids.copy():
            loader.build_object(part, id, assets)
    var start = -1
    for target in targets:
        var dot = target.rfind(".")
        if start < 0 and String(target[byte = dot + 1 :]).lower() == "model":
            var name = String(target[byte=1:])
            for part in range(len(loader.parts)):  # pragma: no branch
                if loader.parts[part].name == name:
                    start = part
    if start < 0:
        raise Error("3MF: `_rels/.rels` names no model part the archive has")
    loader.model.unit = loader.parts[start].unit
    loader.metadata(start)
    loader.model.first_mesh = len(scene.meshes)
    loader.model.root = scene.add(Object3D())
    var root = loader.model.root
    var ids = List[String]()
    var transforms = List[String]()
    ref doc = loader.parts[start].document
    var build = loader.parts[start].build
    if build != NO_ELEMENT:
        for item in _descendants(doc, build, "item"):
            ids.append(doc.attribute(item, "objectid"))
            transforms.append(doc.attribute(item, "transform"))
    for index in range(len(ids)):
        var matrix: Optional[Matrix4] = None
        if transforms[index] != "":
            matrix = three_mf_transform(transforms[index])
        loader.place(ids[index], root, matrix, scene, 0)
    loader.model.mesh_count = len(scene.meshes) - loader.model.first_mesh
    return loader.model.copy()


def read_3mf(
    path: String, mut scene: Scene, mut assets: Assets
) raises -> ThreeMfModel:
    """Read a 3MF file into a scene and its assets.

    Args:
        path: The file.
        scene: The scene to add the nodes and meshes to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where; see `parse_3mf`.

    Raises:
        Error: If the file cannot be read, or for anything `parse_3mf`
            refuses.
    """
    return parse_3mf(Path(path).read_bytes(), scene, assets)
