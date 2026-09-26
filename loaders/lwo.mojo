# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""LightWave objects, LWO2 and LWO3, from three.js
`examples/jsm/loaders/LWOLoader.js`.

`parse_lwo` reads a file as three.js's `LWOLoader.parse` does: the chunks
into a tree with `loaders.lwo_iff`, the surfaces into materials, and each
layer into a mesh, lines or points. `load_lwo` puts what it read into a
scene and its assets. `read_lwo` reads a file, named and placed as
three.js's `load` names and places it.

- **Layers.** A layer's polygons are split into triangles: a quad into
  two, a polygon of more sides into a fan. A layer whose first polygon has
  one point is points, two is lines. Each layer is translated by its pivot,
  and its node placed by it, less its parent's. Its normals are computed,
  its texture coordinates taken from each UV map in turn, and its morph
  maps made absolute targets.
- **Groups.** A run of polygons with one surface is a group. The first
  surface's group index is not remembered, as three.js tests it for truth,
  so a later run of it gets a new index and a second name.
- **Materials.** An LWO2 surface is a Phong material. An LWO3 surface is a
  Phong, standard or physical material from its node attributes, with the
  maps of its image nodes and image maps. Points and lines get a plain
  material of the surface's color.

`LwoMaterial` holds what three.js's material holds, in doubles: its colors
are linear. `load_lwo` makes each into a `Material`, its colors stored as
sRGB bytes, and decodes each map's file if it is there.

**Where three.js's quirks are kept.** A surface's transparency in LWO2 is
not read. The morph maps are not translated by the pivot. Points are read
with x negated, and morph points with z negated. A surface with no side
is back-sided. A `Luminosity` without maps sets the emissive color to the
color. A `double` value is a 64-bit integer. Keys are walked in
JavaScript's order.

**Where this port differs.** A material three.js cannot name for a group
of a mesh, which it leaves undefined, is a hidden material. In the scene,
points and lines are read through their index, as the renderer draws them
from positions in order, and have no normals. What three.js
throws on is refused. So are what three.js reads in a way not followed
here: fewer surface tags than polygons, a polygon or a UV that names a
point the layer does not have, a surface value of the wrong shape, an
attribute with no value, and a texture wrap mode that is not 0 to 3. The
environment map is recorded in `LwoMaterial`, not bound: a `Material`'s
environment is a cube texture.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    MaterialIndex,
)
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.gltf import decode_image
from loaders.lwo_iff import LwoTree, LwoValue, parse_lwo_tree
from materials.material import (
    ADD_OPERATION,
    BACK_SIDE,
    BASIC,
    Combine,
    DOUBLE_SIDE,
    FRONT_SIDE,
    MULTIPLY_OPERATION,
    Material,
    MaterialId,
    PHONG,
    PHYSICAL,
    PointSize,
    STANDARD,
    Side,
    points_material,
)
from math.vector2 import Vector2
from objects.line import Line, SEGMENTS
from objects.mesh import Mesh
from objects.points import Points
from render.framebuffer import Color, FloatColor
from render.srgb import LINEAR, SRGB, linear_to_srgb
from render.texture import CLAMP, MIRROR, REPEAT, Wrap, texture_from
from render.texture_store import NO_TEXTURE, TextureId
from std.math import sqrt
from std.pathlib import Path

comptime Rgb = SIMD[DType.float64, 4]


def _hex(value: Int) -> Rgb:
    """Return three.js's `new Color( hex )`: sRGB bytes made linear."""
    var out = Rgb(0)
    for k in range(3):  # pragma: no branch
        var c = Float64((value >> (16 - 8 * k)) & 255) / 255
        out[k] = (
            c * 0.0773993808 if c
            < 0.04045 else (c * 0.9478672986 + 0.0521327014) ** 2.4
        )
    return out


struct LwoMap(Copyable, Movable):
    """A map of an LWO material: its file, as three.js loads it, and how it
    is laid."""

    # The resource path and the file name.
    var file: String
    var wrap_s: Wrap
    var wrap_t: Wrap
    # three.js's `SRGBColorSpace` for a color map, or linear.
    var srgb: Bool
    # The decoded file, or `NO_TEXTURE` when it is not there.
    var texture: TextureId

    def __init__(out self, var file: String):
        """Start a map of a file, clamped and linear.

        Args:
            file: The file.
        """
        self.file = file^
        self.wrap_s = CLAMP
        self.wrap_t = CLAMP
        self.srgb = False
        self.texture = NO_TEXTURE


struct LwoMaterial(Copyable, Movable):
    """A material as three.js's LWO loader makes it: a
    `MeshPhongMaterial`, `MeshStandardMaterial`, `MeshPhysicalMaterial`,
    `PointsMaterial` or `LineBasicMaterial`, with what it holds."""

    # three.js's class name.
    var type: String
    var name: String
    var side: Side
    var flat_shading: Bool
    # Linear colors.
    var color: Rgb
    var emissive: Rgb
    var specular: Rgb
    var emissive_intensity: Float64
    var shininess: Float64
    var reflectivity: Float64
    var refraction_ratio: Float64
    var combine: Combine
    var roughness: Float64
    var metalness: Float64
    var clearcoat: Float64
    var clearcoat_roughness: Float64
    var bump_scale: Float64
    var normal_scale: Vector2
    var opacity: Float64
    var transparent: Bool
    # A points material's size.
    var size: Float64
    var map: Optional[LwoMap]
    var ao_map: Optional[LwoMap]
    var roughness_map: Optional[LwoMap]
    var specular_map: Optional[LwoMap]
    var emissive_map: Optional[LwoMap]
    var metalness_map: Optional[LwoMap]
    var alpha_map: Optional[LwoMap]
    var normal_map: Optional[LwoMap]
    var bump_map: Optional[LwoMap]
    var env_map: Optional[LwoMap]
    # three.js's `EquirectangularRefractionMapping` for the environment, or
    # reflection.
    var env_refraction: Bool

    def __init__(out self, var type: String, var name: String):
        """Start a material at three.js's defaults for its class.

        Args:
            type: The class name.
            name: The name.
        """
        self.type = type^
        self.name = name^
        self.side = FRONT_SIDE
        self.flat_shading = False
        self.color = Rgb(1, 1, 1, 0)
        self.emissive = Rgb(0)
        self.specular = _hex(0x111111)
        self.emissive_intensity = 1
        self.shininess = 30
        self.reflectivity = 1
        self.refraction_ratio = 0.98
        self.combine = MULTIPLY_OPERATION
        self.roughness = 1
        self.metalness = 0
        self.clearcoat = 0
        self.clearcoat_roughness = 0
        self.bump_scale = 1
        self.normal_scale = Vector2(1, 1)
        self.opacity = 1
        self.transparent = False
        self.size = 1
        self.map = None
        self.ao_map = None
        self.roughness_map = None
        self.specular_map = None
        self.emissive_map = None
        self.metalness_map = None
        self.alpha_map = None
        self.normal_map = None
        self.bump_map = None
        self.env_map = None
        self.env_refraction = False
        if self.type == "MeshPhysicalMaterial":
            # three.js's getter at the default index of refraction, 1.5.
            self.reflectivity = 0.5


def _physical_reflectivity(value: Float64) -> Float64:
    """Return a physical material's reflectivity after three.js's setter
    and getter: through the index of refraction and back."""
    var ior = (1 + 0.4 * value) / (1 - 0.4 * value)
    return max(0.0, min(1.0, 2.5 * (ior - 1) / (ior + 1)))


struct LwoGroup(Copyable, Movable):
    """A run of a geometry's index that wears one material."""

    var start: Int
    var count: Int
    var material_index: Int

    def __init__(out self, start: Int, count: Int, material_index: Int):
        """Hold a group.

        Args:
            start: Its first index.
            count: How many indices.
            material_index: Which material.
        """
        self.start = start
        self.count = count
        self.material_index = material_index


struct LwoMesh(Copyable, Movable):
    """A layer as three.js makes it: a `Mesh`, `LineSegments` or
    `Points`, its geometry and its materials."""

    # three.js's class name.
    var type: String
    var name: String
    var position: Rgb
    var pivot: Rgb
    # The mesh this one is under, as an index into `LwoModel.meshes`, or -1.
    var parent: Int
    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    var index: List[Int]
    var groups: List[LwoGroup]
    var morph_names: List[String]
    var morphs: List[List[Float32]]
    # The surface names of the groups, three.js's `userData.matNames`, and
    # whether each is named at all.
    var material_names: List[String]
    var named: List[Bool]
    # The materials, as indices into `LwoModel.materials`, -1 for one three.js
    # leaves undefined; and whether three.js gave the mesh one material
    # rather than a list.
    var materials: List[Int]
    var single: Bool

    def __init__(out self):
        """Start an empty mesh."""
        self.type = String()
        self.name = String()
        self.position = Rgb(0)
        self.pivot = Rgb(0)
        self.parent = -1
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.index = List[Int]()
        self.groups = List[LwoGroup]()
        self.morph_names = List[String]()
        self.morphs = List[List[Float32]]()
        self.material_names = List[String]()
        self.named = List[Bool]()
        self.materials = List[Int]()
        self.single = True


struct LwoModel(Movable):
    """What three.js's `LWOLoader.parse` gives: the materials and the
    meshes, and where `load_lwo` put them."""

    # The surfaces, three.js's `materials`, then the points and lines
    # materials three.js makes for each such layer.
    var materials: List[LwoMaterial]
    var surfaces: Int
    # Every mesh, in the order of the layers.
    var meshes: List[LwoMesh]
    # The meshes with no parent, three.js's `meshes`.
    var roots: List[Int]
    # Each mesh's node, once `load_lwo` has added it.
    var nodes: List[NodeId]

    def __init__(out self):
        """Start with nothing."""
        self.materials = List[LwoMaterial]()
        self.surfaces = 0
        self.meshes = List[LwoMesh]()
        self.roots = List[Int]()
        self.nodes = List[NodeId]()


# --- materials ---------------------------------------------------------------


def _truthy(tree: LwoTree, object: Int, key: String) -> Bool:
    return tree.get(object, key).truthy()


def _scalar(tree: LwoTree, attribute: Int, name: String) raises -> Float64:
    """Return an attribute's value, a number."""
    var value = tree.get(attribute, "value")
    if value.is_undefined():
        raise Error("LWO: the attribute " + name + " has no value")
    if not value.is_number():
        raise Error("LWO: the attribute " + name + " is not a number")
    return value.number


def _triple(tree: LwoTree, attribute: Int, name: String) raises -> Rgb:
    """Return an attribute's value, three numbers: three.js's
    `fromArray`."""
    var value = tree.get(attribute, "value")
    if value.is_undefined():
        raise Error("LWO: the attribute " + name + " has no value")
    # A `vparam3` is always three numbers.
    if not value.is_numbers():
        raise Error("LWO: the attribute " + name + " is not three numbers")
    return Rgb(value.numbers[0], value.numbers[1], value.numbers[2], 0)


def _wrap(value: LwoValue, what: String) raises -> Wrap:
    """Return three.js's `getWrappingType`: a wrap is a whole number of
    the file, never negative."""
    var mode = Int(value.number)
    if mode > 3:
        raise Error("LWO: a texture's " + what + " wrap is not 0 to 3")
    if mode == 1:
        return REPEAT
    if mode == 2:
        return MIRROR
    return CLAMP


def _in(names: List[String], key: String) -> Bool:
    for name in names:
        if name == key:
            return True
    return False


def _without(names: List[String], key: String) -> List[String]:
    var kept = List[String]()
    for name in names:  # pragma: no branch
        if name != key:
            kept.append(name)
    return kept^


struct _Params(Copyable, Movable):
    """The parameters three.js collects before it builds a material: what
    its `maps` object set, and what its attributes' `params` set, which
    three.js keeps apart until it merges them."""

    var maps: List[String]
    var attributes: List[String]
    var material: LwoMaterial

    def __init__(out self, var name: String):
        self.maps = List[String]()
        self.attributes = List[String]()
        self.material = LwoMaterial("", name^)

    def has(self, key: String) -> Bool:
        """Whether either set it: what the material is built from."""
        return _in(self.maps, key) or _in(self.attributes, key)

    def has_map(self, key: String) -> Bool:
        return _in(self.maps, key)

    def has_attribute(self, key: String) -> Bool:
        return _in(self.attributes, key)

    def mark(mut self, key: String):
        """Set by a map."""
        if not _in(self.maps, key):
            self.maps.append(key)

    def mark_attribute(mut self, key: String):
        if not _in(self.attributes, key):
            self.attributes.append(key)

    def drop(mut self, key: String):
        """Deleted from the maps."""
        self.maps = _without(self.maps, key)

    def drop_attribute(mut self, key: String):
        self.attributes = _without(self.attributes, key)


struct _MaterialParser:
    """three.js's `MaterialParser`."""

    var path: String

    def __init__(out self, path: String):
        self.path = path

    def texture(self, file: String) -> LwoMap:
        return LwoMap(self.path + file)

    def parse(self, tree: LwoTree) raises -> List[LwoMaterial]:
        var out = List[LwoMaterial]()
        var materials = tree.child(0, "materials")
        for name in tree.walk(materials):  # pragma: no branch
            var surface = tree.get(materials, name)
            if not surface.is_object():
                raise Error("LWO: the material " + name + " is not a surface")
            if tree.format == "LWO3":
                out.append(self.material(tree, surface.object, name))
            else:
                out.append(self.material_lwo2(tree, surface.object, name))
        return out^

    def side(self, tree: LwoTree, attributes: Int) raises -> Side:
        """three.js's `getSide`."""
        var side = tree.get(attributes, "side")
        if not side.truthy():
            return BACK_SIDE
        if side.number == 1:
            return BACK_SIDE
        if side.number == 3:
            return DOUBLE_SIDE
        # Two, and a value three.js's switch does not name, which leaves
        # the material's default.
        return FRONT_SIDE

    def flat(self, tree: LwoTree, attributes: Int) -> Bool:
        """three.js's `getSmooth`, which is `flatShading`."""
        return not _truthy(tree, attributes, "smooth")

    def material_lwo2(
        self, tree: LwoTree, surface: Int, name: String
    ) raises -> LwoMaterial:
        """three.js's `parseMaterialLwo2`: always Phong."""
        var attributes = tree.child(surface, "attributes")
        var params = _Params(name)
        params.material.side = self.side(tree, attributes)
        params.material.flat_shading = self.flat(tree, attributes)
        self.attributes(tree, attributes, params)
        return self.build(params^, "MeshPhongMaterial")

    def material(
        self, tree: LwoTree, surface: Int, name: String
    ) raises -> LwoMaterial:
        """three.js's `parseMaterial`, of LWO3."""
        var attributes = tree.child(surface, "attributes")
        var params = _Params(name)
        params.material.side = self.side(tree, attributes)
        params.material.flat_shading = self.flat(tree, attributes)
        var connections = tree.child(surface, "connections")
        var nodes = tree.child(surface, "nodes")
        var input_names = tree.get(connections, "inputName")
        if not input_names.is_strings():
            raise Error("LWO: the surface " + name + " has no connections")
        var input_nodes = tree.get(connections, "inputNodeName")
        var node_names = tree.get(connections, "nodeName")
        # three.js's `parseConnections`.
        var material_node = -1
        var material_name = String()
        var has_material = False
        for i in range(len(input_names.strings)):  # pragma: no branch
            if input_names.strings[i] == "Material":
                var ref_name = _at(input_nodes, i)
                material_node = _node(tree, nodes, ref_name)
                if material_node < 0:
                    raise Error(
                        "LWO: the material node " + ref_name + " is not there"
                    )
                material_name = ref_name
                has_material = True
        var node_attributes = -1
        if has_material:
            node_attributes = tree.child(material_node, "attributes")
        if not node_names.is_strings():
            raise Error("LWO: the surface " + name + " names no nodes")
        var map_names = List[String]()
        var map_nodes = List[Int]()
        for i in range(len(node_names.strings)):  # pragma: no branch
            if has_material and node_names.strings[i] == material_name:
                var input = (
                    input_names.strings[i] if i
                    < len(input_names.strings) else "undefined"
                )
                var found = _node(tree, nodes, _at(input_nodes, i))
                var at = -1
                for k in range(len(map_names)):
                    if map_names[k] == input:
                        at = k
                if at < 0:
                    map_names.append(input)
                    map_nodes.append(found)
                else:
                    map_nodes[at] = found
        self.texture_nodes(tree, map_names, map_nodes, params)
        if node_attributes >= 0:
            self.image_maps(tree, node_attributes, params)
            self.attributes(tree, node_attributes, params)
        else:
            raise Error("LWO: the surface " + name + " has no material node")
        # three.js's `parseEnvMap`. There is a material node here: without
        # one, there are no attributes, refused above.
        var file = tree.get(material_node, "fileName")
        if file.truthy():
            var env = self.texture(file.text)
            ref m = params.material
            if (
                params.has_attribute("transparent")
                and params.has_attribute("opacity")
                and m.opacity < 0.999
            ):
                m.env_refraction = True
                params.drop_attribute("reflectivity")
                params.drop_attribute("combine")
                if params.has_attribute("metalness"):
                    m.metalness = 1
                m.opacity = 1
            params.material.env_map = env^
        var kind = String("MeshPhongMaterial")
        var clearcoat = _entry(tree, node_attributes, "Clearcoat")
        if clearcoat >= 0 and _scalar(tree, clearcoat, "Clearcoat") > 0:
            kind = "MeshPhysicalMaterial"
        elif _entry(tree, node_attributes, "Roughness") >= 0:
            kind = "MeshStandardMaterial"
        if kind != "MeshPhongMaterial":
            params.drop_attribute("refractionRatio")
        return self.build(params^, kind)

    def texture_nodes(
        self,
        tree: LwoTree,
        names: List[String],
        nodes: List[Int],
        mut params: _Params,
    ) raises:
        """three.js's `parseTextureNodes`."""
        var order = js_order(names)
        for k in order:
            var name = names[k]
            var node = nodes[k]
            if node < 0:
                raise Error(
                    "LWO: the texture node for " + name + " is not there"
                )
            var file = tree.get(node, "fileName")
            if not file.truthy():
                raise Error(
                    "LWO: the texture node for " + name + " has no file"
                )
            var map = self.texture(file.text)
            var width = tree.get(node, "widthWrappingMode")
            if not width.is_undefined():
                map.wrap_s = _wrap(width, "width")
            var height = tree.get(node, "heightWrappingMode")
            if not height.is_undefined():
                map.wrap_t = _wrap(height, "height")
            ref m = params.material
            if name == "Color":
                map.srgb = True
                m.map = map^
                params.mark("map")
            elif name == "Roughness":
                m.roughness_map = map^
                m.roughness = 1
                params.mark("roughnessMap")
                params.mark("roughness")
            elif name == "Specular":
                map.srgb = True
                m.specular_map = map^
                m.specular = _hex(0xFFFFFF)
                params.mark("specularMap")
                params.mark("specular")
            elif name == "Luminous":
                map.srgb = True
                m.emissive_map = map^
                m.emissive = _hex(0x808080)
                params.mark("emissiveMap")
                params.mark("emissive")
            elif name == "Luminous Color":
                m.emissive = _hex(0x808080)
                params.mark("emissive")
            elif name == "Metallic":
                m.metalness_map = map^
                m.metalness = 1
                params.mark("metalnessMap")
                params.mark("metalness")
            elif name == "Transparency" or name == "Alpha":
                m.alpha_map = map^
                m.transparent = True
                params.mark("alphaMap")
                params.mark("transparent")
            elif name == "Normal":
                m.normal_map = map^
                params.mark("normalMap")
                var amplitude = tree.get(node, "amplitude")
                if amplitude.is_number():
                    m.normal_scale = Vector2(
                        Float32(amplitude.number), Float32(amplitude.number)
                    )
            elif name == "Bump":
                m.bump_map = map^
                params.mark("bumpMap")
        if params.has("roughnessMap") and params.has("specularMap"):
            params.material.specular_map = None
            params.drop("specularMap")

    def image_maps(
        self, tree: LwoTree, attributes: Int, mut params: _Params
    ) raises:
        """three.js's `parseAttributeImageMaps`: it stops at the first map
        whose clip has no file."""
        for name in tree.walk(attributes):  # pragma: no branch
            var attribute = tree.get(attributes, name)
            if not attribute.is_object():
                continue
            var maps = tree.get(attribute.object, "maps")
            if not maps.truthy():
                continue
            if not maps.is_objects():
                # A chunk named `maps` kept as text: its first character has
                # no image index, so three.js finds no file and stops.
                return
            var data = maps.objects[0]
            var index = tree.get(data, "imageIndex")
            var file = _texture_file(tree, index)
            if file.byte_length() == 0:
                return
            var map = self.texture(file)
            var wrap = tree.child(data, "wrap")
            if wrap >= 0:
                map.wrap_s = _wrap(tree.get(wrap, "w"), "width")
                map.wrap_t = _wrap(tree.get(wrap, "h"), "height")
            ref m = params.material
            if name == "Color":
                map.srgb = True
                m.map = map^
                params.mark("map")
            elif name == "Diffuse":
                m.ao_map = map^
                params.mark("aoMap")
            elif name == "Roughness":
                m.roughness_map = map^
                m.roughness = 1
                params.mark("roughnessMap")
                params.mark("roughness")
            elif name == "Specular":
                map.srgb = True
                m.specular_map = map^
                m.specular = _hex(0xFFFFFF)
                params.mark("specularMap")
                params.mark("specular")
            elif name == "Luminosity":
                map.srgb = True
                m.emissive_map = map^
                m.emissive = _hex(0x808080)
                params.mark("emissiveMap")
                params.mark("emissive")
            elif name == "Metallic":
                m.metalness_map = map^
                m.metalness = 1
                params.mark("metalnessMap")
                params.mark("metalness")
            elif name == "Transparency" or name == "Alpha":
                m.alpha_map = map^
                m.transparent = True
                params.mark("alphaMap")
                params.mark("transparent")
            elif name == "Normal":
                m.normal_map = map^
                params.mark("normalMap")
            elif name == "Bump":
                m.bump_map = map^
                params.mark("bumpMap")

    def attributes(
        self, tree: LwoTree, attributes: Int, mut params: _Params
    ) raises:
        """three.js's `parseAttributes`, with its physical, standard and
        Phong parts."""
        ref m = params.material
        var color = _entry(tree, attributes, "Color")
        if color >= 0 and not params.has_map("map"):
            m.color = _triple(tree, color, "Color")
        else:
            m.color = Rgb(1, 1, 1, 0)
        params.mark_attribute("color")
        var transparency = _entry(tree, attributes, "Transparency")
        if transparency >= 0:
            var value = _scalar(tree, transparency, "Transparency")
            if value != 0:
                m.opacity = 1 - value
                m.transparent = True
                params.mark_attribute("opacity")
                params.mark_attribute("transparent")
        var bump = _entry(tree, attributes, "Bump Height")
        if bump >= 0:
            m.bump_scale = _scalar(tree, bump, "Bump Height") * 0.1
        # Physical.
        var clearcoat = _entry(tree, attributes, "Clearcoat")
        if clearcoat >= 0 and _scalar(tree, clearcoat, "Clearcoat") > 0:
            m.clearcoat = _scalar(tree, clearcoat, "Clearcoat")
            var gloss = _entry(tree, attributes, "Clearcoat Gloss")
            if gloss >= 0:
                m.clearcoat_roughness = 0.5 * (
                    1 - _scalar(tree, gloss, "Clearcoat Gloss")
                )
        # Standard.
        var luminous = _entry(tree, attributes, "Luminous")
        if luminous >= 0:
            m.emissive_intensity = _scalar(tree, luminous, "Luminous")
            var light = _entry(tree, attributes, "Luminous Color")
            if light >= 0 and not params.has_map("emissive"):
                m.emissive = _triple(tree, light, "Luminous Color")
            else:
                m.emissive = _hex(0x808080)
            params.mark_attribute("emissive")
        var roughness = _entry(tree, attributes, "Roughness")
        if roughness >= 0 and not params.has_map("roughnessMap"):
            m.roughness = _scalar(tree, roughness, "Roughness")
            params.mark_attribute("roughness")
        var metallic = _entry(tree, attributes, "Metallic")
        if metallic >= 0 and not params.has_map("metalnessMap"):
            m.metalness = _scalar(tree, metallic, "Metallic")
            params.mark_attribute("metalness")
        # Phong.
        var refraction = _entry(tree, attributes, "Refraction Index")
        if refraction >= 0:
            m.refraction_ratio = 0.98 / _scalar(
                tree, refraction, "Refraction Index"
            )
            params.mark_attribute("refractionRatio")
        var diffuse = _entry(tree, attributes, "Diffuse")
        if diffuse >= 0:
            m.color = m.color * _scalar(tree, diffuse, "Diffuse")
        var reflection = _entry(tree, attributes, "Reflection")
        if reflection >= 0:
            m.reflectivity = _scalar(tree, reflection, "Reflection")
            m.combine = ADD_OPERATION
            params.mark_attribute("reflectivity")
            params.mark_attribute("combine")
        var luminosity = _entry(tree, attributes, "Luminosity")
        if luminosity >= 0:
            m.emissive_intensity = _scalar(tree, luminosity, "Luminosity")
            if not params.has_map("emissiveMap") and not params.has_map("map"):
                m.emissive = m.color
            else:
                m.emissive = _hex(0x808080)
            params.mark_attribute("emissive")
        var specular = _entry(tree, attributes, "Specular")
        if (
            roughness < 0
            and specular >= 0
            and not params.has_map("specularMap")
        ):
            var s = _scalar(tree, specular, "Specular")
            var highlight = _entry(tree, attributes, "Color Highlight")
            if highlight >= 0:
                var h = _scalar(tree, highlight, "Color Highlight")
                var tint = m.color * s
                var base = Rgb(s, s, s, 0)
                m.specular = base + (tint - base) * h
            else:
                m.specular = Rgb(s, s, s, 0)
            params.mark_attribute("specular")
        var glossiness = _entry(tree, attributes, "Glossiness")
        if params.has_attribute("specular") and glossiness >= 0:
            m.shininess = 7 + Float64(2) ** (
                _scalar(tree, glossiness, "Glossiness") * 12 + 2
            )
            params.mark_attribute("shininess")

    def build(self, var params: _Params, var kind: String) -> LwoMaterial:
        """Build a material of a class from the parameters: those the class
        does not have stay at its default, as three.js warns and skips
        them."""
        var out = LwoMaterial(kind.copy(), params.material.name.copy())
        ref p = params.material
        out.side = p.side
        out.flat_shading = p.flat_shading
        out.color = p.color
        out.emissive = p.emissive
        out.emissive_intensity = p.emissive_intensity
        out.opacity = p.opacity
        out.transparent = p.transparent
        out.bump_scale = p.bump_scale
        out.normal_scale = p.normal_scale
        out.map = p.map.copy()
        out.ao_map = p.ao_map.copy()
        out.emissive_map = p.emissive_map.copy()
        out.alpha_map = p.alpha_map.copy()
        out.normal_map = p.normal_map.copy()
        out.bump_map = p.bump_map.copy()
        out.env_map = p.env_map.copy()
        out.env_refraction = p.env_refraction
        var phong = kind == "MeshPhongMaterial"
        var physical = kind == "MeshPhysicalMaterial"
        if phong:
            out.specular = p.specular
            out.shininess = p.shininess
            out.specular_map = p.specular_map.copy()
            if params.has("reflectivity"):
                out.reflectivity = p.reflectivity
            if params.has("combine"):
                out.combine = p.combine
            if params.has("refractionRatio"):
                out.refraction_ratio = p.refraction_ratio
        else:
            out.roughness = p.roughness
            out.metalness = p.metalness
            out.roughness_map = p.roughness_map.copy()
            out.metalness_map = p.metalness_map.copy()
            if physical:
                out.clearcoat = p.clearcoat
                out.clearcoat_roughness = p.clearcoat_roughness
                if params.has("reflectivity"):
                    out.reflectivity = _physical_reflectivity(p.reflectivity)
        return out^


def js_order(names: List[String]) -> List[Int]:
    """Return the places of keys in the order JavaScript walks them.

    Args:
        names: The keys, each once, in the order they were added.

    Returns:
        Their places, array indices first.
    """
    from loaders.three_mf import js_key_order

    var ordered = js_key_order(names)
    var out = List[Int]()
    for name in ordered:
        for k in range(len(names)):  # pragma: no branch
            if names[k] == name:
                out.append(k)
    return out^


def _at(value: LwoValue, i: Int) -> String:
    """Return a string of an array, or `undefined` past it."""
    if value.is_strings() and i < len(value.strings):
        return value.strings[i]
    return "undefined"


def _node(tree: LwoTree, nodes: Int, ref_name: String) -> Int:
    """Return three.js's `getNodeByRefName`: the first node, in key order,
    whose reference name is the one given, or -1."""
    for key in tree.walk(nodes):  # pragma: no branch
        # `NNME` is the only chunk that adds a node: an object.
        var node = tree.get(nodes, key)
        # `NNME` gives a node its reference name, a string.
        var name = tree.get(node.object, "refName")
        if name.text == ref_name:
            return node.object
    return -1


def _entry(tree: LwoTree, attributes: Int, name: String) -> Int:
    """Return an attribute's object, or -1 when it is not there."""
    var value = tree.get(attributes, name)
    if value.is_object():
        return value.object
    return -1


def _texture_file(tree: LwoTree, index: LwoValue) -> String:
    """Return three.js's `getTexturePathByIndex`: the file of the last
    clip of the index, or nothing."""
    var out = String()
    var textures = tree.get(0, "textures")
    for texture in textures.objects:  # pragma: no branch
        var i = tree.get(texture, "index")
        # A clip's index is a number; an image map's may be missing.
        if index.is_number() and i.number == index.number:
            var file = tree.get(texture, "fileName")
            out = file.text if file.is_string() else String()
    return out^


# --- geometry ----------------------------------------------------------------


def _numbers(tree: LwoTree, object: Int, key: String) -> List[Float64]:
    var value = tree.get(object, key)
    return value.numbers.copy() if value.is_numbers() else List[Float64]()


def _split_indices(indices: List[Float64], dims: List[Float64]) -> List[Int]:
    """three.js's `splitIndices`: quads into two triangles, and polygons of
    more sides into a fan."""
    var out = List[Int]()
    var i = 0
    for d in dims:
        var dim = Int(d)
        if dim < 4:
            for k in range(dim):
                out.append(Int(indices[i + k]))
        elif dim == 4:
            for k in [0, 1, 2, 0, 2, 3]:  # pragma: no branch
                out.append(Int(indices[i + k]))
        else:
            for k in range(1, dim - 1):  # pragma: no branch
                out.append(Int(indices[i]))
                out.append(Int(indices[i + k]))
                out.append(Int(indices[i + k + 1]))
        i += dim
    return out^


def _split_material_indices(
    dims: List[Float64], indices: List[Float64]
) raises -> List[Int]:
    """three.js's `splitMaterialIndices`: a tag pair for each triangle,
    taken by polygon order."""
    var out = List[Int]()
    for i in range(len(dims)):
        if i * 2 + 1 >= len(indices):
            raise Error("LWO: fewer surface tags than polygons")
        var repeat = 1
        var dim = Int(dims[i])
        if dim == 4:
            repeat = 2
        elif dim > 4:
            repeat = dim - 2
        for _ in range(repeat):  # pragma: no branch
            out.append(Int(indices[i * 2]))
            out.append(Int(indices[i * 2 + 1]))
    return out^


def _tag(tags: List[String], index: Int) -> String:
    """Return a tag, or `undefined` past the list, as a JavaScript key."""
    # A tag index is a two-byte number, never negative.
    if index < len(tags):
        return tags[index]
    return "undefined"


def _groups(
    tree: LwoTree, geometry: Int, kind: String, mut mesh: LwoMesh
) raises:
    """three.js's `parseGroups`, keeping its test of a group index for
    truth."""
    var tags_value = tree.get(0, "tags")
    var tags = tags_value.strings.copy()
    var size = 3
    if kind == "lines":
        size = 2
    elif kind == "points":
        size = 1
    var dims = _numbers(tree, geometry, "polygonDimensions")
    var material_indices = tree.get(geometry, "materialIndices")
    if len(dims) > 0 and not material_indices.is_numbers():
        raise Error("LWO: a layer's polygons have no surface tags")
    var pairs = _split_material_indices(dims, material_indices.numbers)
    var names = List[String]()
    var named = List[Bool]()
    var pair_names = List[String]()
    var pair_values = List[Int]()
    var index_count = 0
    var previous = -1
    var has_previous = False
    var material = -1
    var start = 0
    var count = 0
    for i in range(0, len(pairs), 2):
        material = pairs[i + 1]
        if i == 0:
            _set_name(names, named, index_count, tags, material)
        if not has_previous:
            previous = material
            has_previous = True
        if material != previous:
            var key = _tag(tags, previous)
            var current = _lookup(pair_names, pair_values, key)
            if current <= 0:
                current = index_count
                _store(pair_names, pair_values, key, index_count)
                _set_name(names, named, index_count, tags, previous)
                index_count += 1
            mesh.groups.append(LwoGroup(start, count, current))
            start += count
            previous = material
            count = 0
        count += size
    if len(mesh.groups) > 0:
        var key = _tag(tags, material)
        var current = _lookup(pair_names, pair_values, key)
        if current <= 0:
            current = index_count
            _store(pair_names, pair_values, key, index_count)
            _set_name(names, named, index_count, tags, material)
        mesh.groups.append(LwoGroup(start, count, current))
    mesh.material_names = names^
    mesh.named = named^


def _set_name(
    mut names: List[String],
    mut named: List[Bool],
    at: Int,
    tags: List[String],
    tag: Int,
):
    """Set `matNames[ at ]` to a tag, or `undefined` past the list."""
    while len(names) <= at:
        names.append(String())
        named.append(False)
    names[at] = _tag(tags, tag)
    named[at] = tag >= 0 and tag < len(tags)


def _lookup(names: List[String], values: List[Int], key: String) -> Int:
    """Return a key's value, or 0 when it is not there: three.js tests the
    value for truth, so 0 and absent are one."""
    for k in range(len(names)):
        if names[k] == key:
            return values[k]
    return 0


def _store(mut names: List[String], mut values: List[Int], key: String, v: Int):
    for k in range(len(names)):
        if names[k] == key:
            values[k] = v
            return
    names.append(key)
    values.append(v)


def _vertex_normals(
    positions: List[Float32], index: List[Int]
) -> List[Float32]:
    """three.js's `computeVertexNormals` for an indexed geometry: a corner
    past the index reads NaN and writes nowhere."""
    var count = len(positions) // 3
    var normals = List[Float32](length=count * 3, fill=0)
    var nan = Float64(0) / Float64(0)
    for i in range(0, len(index), 3):
        var corners = List[Int]()
        var places = List[Rgb]()
        for k in range(3):  # pragma: no branch
            var v = index[i + k] if i + k < len(index) else -1
            corners.append(v)
            # The index names only points the layer has; past the index
            # three.js reads `undefined`.
            if v < 0:
                places.append(Rgb(nan, nan, nan, 0))
            else:
                places.append(
                    Rgb(
                        Float64(positions[v * 3]),
                        Float64(positions[v * 3 + 1]),
                        Float64(positions[v * 3 + 2]),
                        0,
                    )
                )
        var cb = places[2] - places[1]
        var ab = places[0] - places[1]
        var n = Rgb(
            cb[1] * ab[2] - cb[2] * ab[1],
            cb[2] * ab[0] - cb[0] * ab[2],
            cb[0] * ab[1] - cb[1] * ab[0],
            0,
        )
        for v in corners:  # pragma: no branch
            if v < 0:
                continue
            for c in range(3):  # pragma: no branch
                normals[v * 3 + c] = Float32(Float64(normals[v * 3 + c]) + n[c])
    _normalize(normals)
    return normals^


def _normalize(mut normals: List[Float32]):
    """three.js's `normalizeNormals`, or a normal matrix's `normalize`."""
    for v in range(len(normals) // 3):  # pragma: no branch
        var x = Float64(normals[v * 3])
        var y = Float64(normals[v * 3 + 1])
        var z = Float64(normals[v * 3 + 2])
        var length = sqrt(x * x + y * y + z * z)
        var scale = 1 / (length if length != 0 else 1)
        normals[v * 3] = Float32(x * scale)
        normals[v * 3 + 1] = Float32(y * scale)
        normals[v * 3 + 2] = Float32(z * scale)


def _geometry(tree: LwoTree, layer: Int, mut mesh: LwoMesh) raises:
    """three.js's `GeometryParser.parse`."""
    var geometry = tree.child(layer, "geometry")
    if geometry < 0:
        raise Error("LWO: a layer has no polygons")
    var points = _numbers(tree, geometry, "points")
    for p in points:  # pragma: no branch
        mesh.positions.append(Float32(p))
    var count = len(mesh.positions) // 3
    var dims = _numbers(tree, geometry, "polygonDimensions")
    var indices = _numbers(tree, geometry, "vertexIndices")
    mesh.index = _split_indices(indices, dims)
    for v in mesh.index:
        if v >= count:
            raise Error("LWO: a polygon names a point the layer does not have")
    var kind = tree.get(geometry, "type")
    _groups(tree, geometry, kind.text if kind.is_string() else "", mesh)
    mesh.normals = _vertex_normals(mesh.positions, mesh.index)
    # three.js's `parseUVs`: each map in turn, the last one written kept.
    mesh.uvs = List[Float32](length=count * 2, fill=0)
    var uv_maps = tree.child(layer, "uvs")
    if uv_maps >= 0:
        for name in tree.walk(uv_maps):  # pragma: no branch
            var map = tree.child(uv_maps, name)
            var at = _numbers(tree, map, "uvIndices")
            var uvs = _numbers(tree, map, "uvs")
            for j in range(len(at)):  # pragma: no branch
                var i = Int(at[j])
                if i >= count:
                    raise Error(
                        "LWO: a UV names a point the layer does not have"
                    )
                mesh.uvs[i * 2] = Float32(uvs[j * 2])
                mesh.uvs[i * 2 + 1] = Float32(uvs[j * 2 + 1])
    # three.js's `parseMorphTargets`: absolute, from the untranslated
    # positions.
    var morphs = tree.child(layer, "morphTargets")
    if morphs >= 0:
        for name in tree.walk(morphs):  # pragma: no branch
            var target = tree.child(morphs, name)
            var moved = mesh.positions.copy()
            var at = _numbers(tree, target, "indices")
            var offsets = _numbers(tree, target, "points")
            var relative = tree.get(target, "type").text == "relative"
            for j in range(len(at)):  # pragma: no branch
                var i = Int(at[j])
                if i >= count:
                    continue
                for c in range(3):  # pragma: no branch
                    if relative:
                        moved[i * 3 + c] = Float32(
                            Float64(moved[i * 3 + c]) + offsets[j * 3 + c]
                        )
                    else:
                        moved[i * 3 + c] = Float32(offsets[j * 3 + c])
            mesh.morph_names.append(name)
            mesh.morphs.append(moved^)
    # three.js's `translate( -pivot )`: the positions moved, the normals
    # normalized again, the morph targets left.
    for v in range(count):  # pragma: no branch
        for c in range(3):  # pragma: no branch
            mesh.positions[v * 3 + c] = Float32(
                Float64(mesh.positions[v * 3 + c]) - mesh.pivot[c]
            )
    _normalize(mesh.normals)


# --- the file ------------------------------------------------------------------


def parse_lwo(
    bytes: List[UInt8], model_name: String, path: String = ""
) raises -> LwoModel:
    """Read a LightWave object, three.js's `LWOLoader.parse`.

    Args:
        bytes: The whole file.
        model_name: The name of a layer that has none, before `_layer_`
            and its number.
        path: What each texture's file name is put after.

    Returns:
        The materials and the meshes.

    Raises:
        Error: For anything the module docstring and `parse_lwo_tree`
            list.
    """
    var tree = parse_lwo_tree(bytes)
    var model = LwoModel()
    model.materials = _MaterialParser(path).parse(tree)
    model.surfaces = len(model.materials)
    var layers = tree.get(0, "layers")
    var by_number = Dict[Int, Int]()
    for layer in layers.objects:  # pragma: no branch
        var mesh = LwoMesh()
        var number = Int(tree.get(layer, "number").number)
        var pivot = _numbers(tree, layer, "pivot")
        mesh.pivot = Rgb(pivot[0], pivot[1], pivot[2], 0)
        _geometry(tree, layer, mesh)
        var geometry = tree.child(layer, "geometry")
        var kind = tree.get(geometry, "type").text
        mesh.type = "Points" if kind == "points" else (
            "LineSegments" if kind == "lines" else "Mesh"
        )
        var name = tree.get(layer, "name")
        if name.truthy():
            mesh.name = name.text
        else:
            mesh.name = model_name + "_layer_" + String(number)
        _materials(model, mesh, kind)
        var parent = Int(tree.get(layer, "parent").number)
        if parent != -1:
            if parent not in by_number:
                raise Error(
                    "LWO: a layer's parent "
                    + String(parent)
                    + " is not an earlier layer"
                )
            mesh.parent = by_number[parent]
        by_number[number] = len(model.meshes)
        if mesh.parent < 0:
            model.roots.append(len(model.meshes))
        model.meshes.append(mesh^)
    # three.js's `applyPivots`.
    for k in range(len(model.meshes)):  # pragma: no branch
        var pivot = model.meshes[k].pivot
        var place = pivot
        var parent = model.meshes[k].parent
        if parent >= 0:
            place = place - model.meshes[parent].pivot
        model.meshes[k].position = place
    return model^


def _materials(mut model: LwoModel, mut mesh: LwoMesh, kind: String) raises:
    """three.js's `getMaterials`."""
    var found = List[Int]()
    for k in range(len(mesh.material_names)):
        var at = -1
        if mesh.named[k]:
            for m in range(model.surfaces):  # pragma: no branch
                if at < 0 and model.materials[m].name == mesh.material_names[k]:
                    at = m
        found.append(at)
    if kind == "points" or kind == "lines":
        for k in range(len(found)):  # pragma: no branch
            if found[k] < 0:
                raise Error(
                    "LWO: points or lines name a surface that is not there"
                )
            ref surface = model.materials[found[k]]
            var made: LwoMaterial
            if kind == "points":
                made = LwoMaterial("PointsMaterial", "")
                made.size = 0.1
                made.map = surface.map.copy()
            else:
                made = LwoMaterial("LineBasicMaterial", "")
            made.color = surface.color
            model.materials.append(made^)
            found[k] = len(model.materials) - 1
    var defined = 0
    var only = -1
    for m in found:
        if m >= 0:
            defined += 1
            only = m
    if defined == 1:
        mesh.materials = [only]
        mesh.single = True
    else:
        mesh.materials = found^
        mesh.single = False


def lwo_model_name(url: String) -> String:
    """Return the name three.js's `LWOLoader.load` gives a file: what is
    after the folder above `Objects`, or the whole path, up to its first
    dot.

    Args:
        url: The file's path.

    Returns:
        The name.
    """
    var path = lwo_resource_path(url)
    var rest: String
    if path.byte_length() == 0:
        # A path that starts with `Objects`: three.js splits it into its
        # characters and keeps the last.
        var units = url.as_bytes()
        rest = String(url[byte = len(units) - 1 :]) if len(units) > 0 else ""
    else:
        var parts = url.split(path)
        rest = String(parts[len(parts) - 1])
    return String(rest.split(".")[0])


def lwo_resource_path(url: String) -> String:
    """Return three.js's `extractParentUrl( url, 'Objects' )`: the path
    before `Objects`, or `./`.

    Args:
        url: The file's path.

    Returns:
        The folder textures are read from.
    """
    var at = url.find("Objects")
    if at < 0:
        return "./"
    return String(url[byte=0:at])


# --- into a scene ------------------------------------------------------------


def _authored(color: Rgb) -> Color:
    """Return linear light as the sRGB bytes a material holds."""
    return FloatColor(
        linear_to_srgb(Float32(color[0])),
        linear_to_srgb(Float32(color[1])),
        linear_to_srgb(Float32(color[2])),
        1,
    ).quantize()


def _load(mut map: Optional[LwoMap], mut assets: Assets) raises -> TextureId:
    """Decode a map's file if it is there."""
    if not Bool(map):
        return NO_TEXTURE
    ref m = map.value()
    var file = Path(m.file)
    if file.exists():
        var texture = texture_from(
            decode_image(file.read_bytes()),
            m.wrap_s,
            color_space=SRGB if m.srgb else LINEAR,
        )
        texture.wrap_t = m.wrap_t
        m.texture = assets.textures.add(texture^)
    return m.texture


def _material(mut made: LwoMaterial, mut assets: Assets) raises -> Material:
    """Return the `Material` of an LWO material."""
    var color = _authored(made.color)
    if made.type == "PointsMaterial":
        var out = points_material(color, PointSize(Float32(made.size)))
        out.map = _load(made.map, assets)
        return out^
    if made.type == "LineBasicMaterial":
        return Material(color, kind=BASIC)
    var kind = PHONG
    if made.type == "MeshStandardMaterial":
        kind = STANDARD
    elif made.type == "MeshPhysicalMaterial":
        kind = PHYSICAL
    var out = Material(
        color,
        kind=kind,
        side=made.side,
        opacity=Float32(made.opacity),
        transparent=made.transparent,
        emissive=_authored(made.emissive),
        emissive_intensity=Float32(made.emissive_intensity),
        flat_shading=made.flat_shading,
    )
    out.specular = _authored(made.specular)
    out.shininess = Float32(made.shininess)
    out.reflectivity = Float32(made.reflectivity)
    out.combine = made.combine
    out.refraction_ratio = Float32(made.refraction_ratio)
    out.roughness = Float32(made.roughness)
    out.metalness = Float32(made.metalness)
    out.clearcoat = Float32(made.clearcoat)
    out.clearcoat_roughness = Float32(made.clearcoat_roughness)
    out.bump_scale = Float32(made.bump_scale)
    out.normal_scale = made.normal_scale
    out.map = _load(made.map, assets)
    out.ao_map = _load(made.ao_map, assets)
    out.roughness_map = _load(made.roughness_map, assets)
    out.specular_map = _load(made.specular_map, assets)
    out.emissive_map = _load(made.emissive_map, assets)
    out.metalness_map = _load(made.metalness_map, assets)
    out.alpha_map = _load(made.alpha_map, assets)
    out.normal_map = _load(made.normal_map, assets)
    out.bump_map = _load(made.bump_map, assets)
    return out^


def _hidden(mut hidden_id: MaterialId, mut assets: Assets) raises -> MaterialId:
    """Return the one hidden material of a load, made the first time."""
    if hidden_id.value < 0:
        var hidden = Material(Color(255, 255, 255), kind=BASIC)
        hidden.visible = False
        hidden_id = assets.materials.add(hidden^)
    return hidden_id


def _expanded(
    values: List[Float32], index: List[Int], size: Int
) -> List[Float32]:
    """Return an attribute read through an index, one item a corner."""
    var out = List[Float32](capacity=len(index) * size)
    for v in index:  # pragma: no branch
        for c in range(size):  # pragma: no branch
            out.append(values[v * size + c])
    return out^


def _scene_geometry(mesh: LwoMesh) raises -> BufferGeometry:
    """Return a mesh's geometry for the scene. Points and lines are drawn
    here from positions in order, so theirs are read through the index,
    as three.js draws them; their normals, which three.js computes from
    triangles they do not have, are left out."""
    var geometry = BufferGeometry()
    if mesh.type != "Mesh":
        geometry.set_attribute(
            String(POSITION),
            BufferAttribute(_expanded(mesh.positions, mesh.index, 3), 3),
        )
        geometry.set_attribute(
            String(UV), BufferAttribute(_expanded(mesh.uvs, mesh.index, 2), 2)
        )
        return geometry^
    geometry.set_attribute(
        String(POSITION), BufferAttribute(mesh.positions.copy(), 3)
    )
    geometry.set_attribute(
        String(NORMAL), BufferAttribute(mesh.normals.copy(), 3)
    )
    geometry.set_attribute(String(UV), BufferAttribute(mesh.uvs.copy(), 2))
    geometry.index = mesh.index.copy()
    for group in mesh.groups:
        geometry.add_group(
            group.start, group.count, MaterialIndex(group.material_index)
        )
    for t in range(len(mesh.morphs)):
        geometry.add_morph_target(
            BufferAttribute(mesh.morphs[t].copy(), 3),
            name=mesh.morph_names[t],
        )
    return geometry^


def load_lwo(
    bytes: List[UInt8],
    mut scene: Scene,
    mut assets: Assets,
    model_name: String,
    path: String = "",
    parent: NodeId = NO_PARENT,
) raises -> LwoModel:
    """Read a LightWave object into a scene and its assets.

    Args:
        bytes: The whole file.
        scene: Where the nodes and the meshes, lines and points go.
        assets: Where the geometries, materials and textures go.
        model_name: The name of a layer that has none, before `_layer_`.
        path: The folder the maps' files are read from.
        parent: The node the top meshes go under.

    Returns:
        What `parse_lwo` read, with each mesh's node.

    Raises:
        Error: For anything `parse_lwo` refuses, and a map's file that is
            there but is not an image `decode_image` reads.
    """
    var model = parse_lwo(bytes, model_name, path)
    var ids = List[MaterialId]()
    for k in range(len(model.materials)):  # pragma: no branch
        ids.append(assets.materials.add(_material(model.materials[k], assets)))
    var hidden_id = MaterialId(-1)
    for k in range(len(model.meshes)):  # pragma: no branch
        ref mesh = model.meshes[k]
        var node = Object3D()
        node.name = mesh.name
        node.set_position(
            Float32(mesh.position[0]),
            Float32(mesh.position[1]),
            Float32(mesh.position[2]),
        )
        var above = parent if mesh.parent < 0 else model.nodes[mesh.parent]
        var id: NodeId
        if above == NO_PARENT:
            id = scene.add(node^)
        else:
            id = scene.attach(node^, above)
        model.nodes.append(id)
        var shape = assets.geometries.add(_scene_geometry(mesh))
        var worn = List[MaterialId]()
        for m in mesh.materials:
            if m >= 0:
                worn.append(ids[m])
            else:
                worn.append(_hidden(hidden_id, assets))
        if len(worn) == 0:
            # A layer with no surface tags: three.js gives it an empty list.
            worn.append(_hidden(hidden_id, assets))
        if mesh.type == "Points":
            scene.add_points(Points(shape, worn[0], id))
        elif mesh.type == "LineSegments":
            scene.add_line(Line(shape, worn[0], id, mode=SEGMENTS))
        elif mesh.single or len(worn) == 1:
            scene.add_mesh(Mesh(shape, worn[0], id))
        else:
            scene.add_mesh(Mesh(shape, worn, id))
    return model^


def read_lwo(
    url: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> LwoModel:
    """Read a LightWave object file, named and with its maps' folder as
    three.js's `LWOLoader.load` finds them.

    Args:
        url: The file.
        scene: Where the meshes go.
        assets: Where the geometries, materials and textures go.
        parent: The node the top meshes go under.

    Returns:
        What `load_lwo` gives.

    Raises:
        Error: If the file cannot be read, and for anything `load_lwo`
            refuses.
    """
    return load_lwo(
        Path(url).read_bytes(),
        scene,
        assets,
        lwo_model_name(url),
        lwo_resource_path(url),
        parent,
    )
