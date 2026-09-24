# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""VRML 2.0 worlds, from three.js `examples/jsm/loaders/VRMLLoader.js`.

`read_vrml` reads a `.wrl` file into the scene and the assets, as
three.js's `VRMLLoader` builds its `Scene`. `loaders.vrml_parse` reads
the text into a tree, and this builds each node three.js builds:

- `Anchor`, `Group`, `Transform` and `Collision` become groups, with
  the translation, rotation and scale of a `Transform`.
- `Background` becomes a group of a sky sphere and a ground sphere,
  painted with the sky and ground colors at their angles.
- `Shape` becomes a mesh, points or lines, with the material of its
  `Appearance`: a `PHONG` material from a `Material` node, and a map
  from an `ImageTexture` or a `PixelTexture` with its
  `TextureTransform`.
- `IndexedFaceSet`, `IndexedLineSet`, `PointSet`, `ElevationGrid`,
  `Extrusion`, `Box`, `Cone`, `Cylinder` and `Sphere` become
  geometries. The faces are cut into fans, colors and normals are
  spread per vertex or per face, and missing normals are found with
  the crease angle, as `loaders.vrml_geometry` does it.
- The last `WorldInfo` at the top of the file gives the title and the
  information, three.js's `scene.userData.worldInfo`.

The other nodes, such as lights, sensors, interpolators and `Text`, are
read and not built, as in three.js. A field three.js does not read is
skipped. A `DEF` name names what the node builds: a node, a material, a
texture or a geometry. A `USE` of a group or a shape is a copy of it, and
a `USE` of an appearance is a copy of its material, as three.js clones
them. A `USE` of anything else is the same thing.

**What three.js does that this keeps.** A field's values are grouped by
kind, so `children [ USE A Shape { } ]` adds the shape first. A shape
that has no appearance is drawn in black by a `BASIC` material named
`__DEFAULT`. A shape that uses an appearance copies its material as
the first shape left it, with that shape's side and vertex colors. A
`texture` field that holds a `USE` is not read. A texture transform
with no `scale` gives a repeat of zero. The background's group has the
lowest render order. The primitives are three.js's `BoxGeometry`,
`ConeGeometry`, `CylinderGeometry` and `SphereGeometry`, with the
segments `VRMLLoader` gives them. A `PixelTexture` of one or three components has
an alpha of one, not 255, as three.js stores it. An elevation grid puts
its rows along x and its columns along z.

**Where this port differs.** three.js reads a missing number as `NaN`
and builds a geometry of it; this refuses a geometry with a `NaN` in
it, such as one whose index names no point. A field of the wrong kind,
such as a `coord` that holds no node, is refused where three.js throws
a `TypeError` or reads nonsense, and so is a `USE` of a name that no
`DEF` gives, and a node that uses itself. A cross section of odd length
and a spine that is not whole points are refused. A texture transform
with no `rotation` turns by zero; three.js sets a `Vector2` as the
rotation. A `Texture` here has one wrap: it repeats when both
`repeatS` and `repeatT` are true, and clamps otherwise. The records in
`VrmlModel` keep both. A `PixelTexture`'s rows are stored from the top,
reversed, so that it samples as three.js's `DataTexture` samples.
three.js loads an `ImageTexture` later; this decodes the file at once
when it is there, and keeps no image when it is not. A `PointSet`
needs whole points, and a color for each point when it has colors.
An `IndexedLineSet` colored per vertex by a `colorIndex` needs a
multiple of three segments: three.js reads past the end otherwise.

"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.gltf import decode_image
from loaders.vrml_geometry import (
    SurfaceData,
    box_data,
    cylinder_data,
    colors_to_linear,
    elevation_grid,
    expand_line_data,
    expand_line_index,
    extrusion_indices,
    extrusion_points,
    flatten_data,
    from_face_data,
    from_indexed_data,
    from_line_data,
    grid_uvs,
    grid_values,
    has_nan,
    normal_attribute,
    paint_faces,
    product,
    sphere_data,
    srgb_to_linear,
    to_non_indexed,
    triangulate_face_data,
    triangulate_face_index,
)
from loaders.vrml_parse import (
    VRML_BOOLEAN_VALUE,
    VRML_NODE_VALUE,
    VRML_NULL_VALUE,
    VRML_NUMBER_VALUE,
    VRML_STRING_VALUE,
    VRML_HEX_VALUE,
    VRML_USE_VALUE,
    VrmlField,
    VrmlTree,
    VrmlValue,
    parse_vrml_text,
)
from materials.material import (
    BACK_SIDE,
    BASIC,
    DOUBLE_SIDE,
    FRONT_SIDE,
    PHONG,
    Material,
    MaterialId,
    MaterialKind,
    Side,
    points_material,
)
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.line import SEGMENTS, Line
from objects.mesh import Mesh
from objects.points import Points
from render.framebuffer import Color, FloatColor
from render.srgb import SRGB, linear_to_srgb
from render.texture import BILINEAR, CLAMP, NEAREST, REPEAT, Texture, Wrap
from render.texture_store import NO_TEXTURE, TextureId
from std.collections import Dict
from std.math import cos, pi, sin, sqrt, trunc
from std.pathlib import Path
from units.si import METER, RADIAN, Angle, Length

# three.js's `Loader.DEFAULT_MATERIAL_NAME`.
comptime VRML_DEFAULT_MATERIAL_NAME = "__DEFAULT"
# The radius of a background's spheres, as three.js makes them.
comptime VRML_BACKGROUND_RADIUS = Length(10000.0, METER)


@fieldwise_init
struct VrmlObjectKind(Equatable, ImplicitlyCopyable, Writable):
    """What a node became, or what a geometry is drawn as, as a type
    rather than a bare int.

    `VrmlModel.count` refuses a kind that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the object kinds."""
        return self.value >= VRML_GROUP.value and (
            self.value <= VRML_EMPTY.value
        )


# A group: three.js's `Group`.
comptime VRML_GROUP = VrmlObjectKind(0)
# A mesh: three.js's `Mesh`.
comptime VRML_MESH = VrmlObjectKind(1)
# Points: three.js's `Points`.
comptime VRML_POINTS = VrmlObjectKind(2)
# Lines, two points a segment: three.js's `LineSegments`.
comptime VRML_LINES = VrmlObjectKind(3)
# A shape with nothing to draw: three.js's hidden `Object3D`.
comptime VRML_EMPTY = VrmlObjectKind(4)


struct VrmlObject(Copyable, Movable):
    """A node the loader made, and what it draws."""

    var node: NodeId
    var kind: VrmlObjectKind
    # An index into `VrmlModel.geometries`, or -1.
    var geometry: Int
    # An index into `VrmlModel.materials`, or -1.
    var material: Int

    def __init__(
        out self,
        node: NodeId,
        kind: VrmlObjectKind,
        geometry: Int,
        material: Int,
    ):
        """Hold what a node draws.

        Args:
            node: The scene node.
            kind: What it is.
            geometry: Its geometry record, or -1.
            material: Its material record, or -1.
        """
        self.node = node
        self.kind = kind
        self.geometry = geometry
        self.material = material


struct VrmlGeometry(Copyable, Movable):
    """A geometry the loader made, and three.js's hints on it."""

    var id: GeometryId
    var name: String
    # `VRML_MESH`, `VRML_LINES` or `VRML_POINTS`: three.js's `_type`.
    var kind: VrmlObjectKind
    # three.js's `_solid`, when the node gives one.
    var has_solid: Bool
    var solid: Bool
    # False for a face set with no `coordIndex`, which three.js hides.
    var has_position: Bool
    var has_color: Bool

    def __init__(out self, id: GeometryId, kind: VrmlObjectKind):
        """Hold a geometry with a position and no hints.

        Args:
            id: The geometry in the assets.
            kind: How it is drawn.
        """
        self.id = id
        self.name = String()
        self.kind = kind
        self.has_solid = False
        self.solid = True
        self.has_position = True
        self.has_color = False


struct VrmlTexture(Copyable, Movable):
    """A texture the loader made, as three.js holds it."""

    var name: String
    # The file an `ImageTexture` names, or empty for a `PixelTexture`.
    var url: String
    # The texture in the assets, or `NO_TEXTURE` when there is no image.
    var id: TextureId
    var wrap_s: Wrap
    var wrap_t: Wrap
    # The texture transform: three.js's `center`, `rotation`, `repeat`
    # and `offset`.
    var center: Vector2
    var rotation: Float64
    var repeat: Vector2
    var offset: Vector2
    # A `PixelTexture`'s components, three.js's `__type`, until an
    # appearance reads it: 1 to 4, or zero.
    var pending_type: Int
    # A `PixelTexture`'s bytes, rows from the bottom, as three.js's
    # `DataTexture` holds them.
    var width: Int
    var height: Int
    var data: List[UInt8]

    def __init__(out self, var name: String, var url: String):
        """Hold a texture with no image, repeating both ways.

        Args:
            name: Its `DEF` name.
            url: Its file, or empty.
        """
        self.name = name^
        self.url = url^
        self.id = NO_TEXTURE
        self.wrap_s = REPEAT
        self.wrap_t = REPEAT
        self.center = Vector2(0, 0)
        self.rotation = 0
        self.repeat = Vector2(1, 1)
        self.offset = Vector2(0, 0)
        self.pending_type = 0
        self.width = 0
        self.height = 0
        self.data = List[UInt8]()


struct VrmlMaterial(Copyable, Movable):
    """A material the loader made, as three.js holds it."""

    var name: String
    # `BASIC` or `PHONG`. Points and lines are `BASIC`.
    var kind: MaterialKind
    # Linear light, as three.js's `Color` holds it.
    var color: FloatColor
    var emissive: FloatColor
    var specular: FloatColor
    var shininess: Float64
    var opacity: Float64
    var transparent: Bool
    var side: Side
    var vertex_colors: Bool
    # An index into `VrmlModel.textures`, or -1.
    var map: Int
    var depth_write: Bool
    var depth_test: Bool
    var fog: Bool
    # The material in the assets, once a shape has drawn with it.
    var id: MaterialId

    def __init__(out self, kind: MaterialKind, color: FloatColor):
        """Start with three.js's defaults for a kind.

        Args:
            kind: `BASIC` or `PHONG`.
            color: Its color, linear.
        """
        self.name = String()
        self.kind = kind
        self.color = color
        self.emissive = FloatColor(0, 0, 0, 1)
        # three.js's `new Color( 0x111111 )`, an sRGB value.
        var dark = Float32(srgb_to_linear(17.0 / 255))
        self.specular = FloatColor(dark, dark, dark, 1)
        self.shininess = 30
        self.opacity = 1
        self.transparent = False
        self.side = FRONT_SIDE
        self.vertex_colors = False
        self.map = -1
        self.depth_write = True
        self.depth_test = True
        self.fog = True
        self.id = MaterialId(-1)

    def build(self, texture: TextureId) raises -> Material:
        """Return the material this record describes.

        Args:
            texture: Its map in the assets, or `NO_TEXTURE`.

        Returns:
            The material, its colors the sRGB bytes of the linear light.

        Raises:
            Error: If `Material` refuses a value, such as an opacity
                outside zero to one or a shininess below zero.
        """
        var material: Material
        if self.kind == PHONG:
            material = Material(
                _authored(self.color),
                map=texture,
                side=self.side,
                opacity=Float32(self.opacity),
                kind=PHONG,
                emissive=_authored(self.emissive),
                vertex_colors=self.vertex_colors,
                specular=_authored(self.specular),
                shininess=Float32(self.shininess),
                transparent=self.transparent,
            )
        else:
            material = Material(
                _authored(self.color),
                map=texture,
                side=self.side,
                opacity=Float32(self.opacity),
                kind=BASIC,
                vertex_colors=self.vertex_colors,
                transparent=self.transparent,
                fog=self.fog,
            )
        material.depth_write = self.depth_write
        material.depth_test = self.depth_test
        return material^


def _authored(color: FloatColor) -> Color:
    """Return linear light as the sRGB bytes a material holds."""
    return FloatColor(
        linear_to_srgb(color.r),
        linear_to_srgb(color.g),
        linear_to_srgb(color.b),
        1,
    ).quantize()


def _linear(r: Float64, g: Float64, b: Float64) -> FloatColor:
    """Return three.js's `setRGB( r, g, b, SRGBColorSpace )`."""
    return FloatColor(
        Float32(srgb_to_linear(r)),
        Float32(srgb_to_linear(g)),
        Float32(srgb_to_linear(b)),
        1,
    )


struct _MaterialData(Copyable, Movable):
    """What a `Material` node holds, three.js's `materialData`."""

    var diffuse: Optional[FloatColor]
    var emissive: Optional[FloatColor]
    var specular: Optional[FloatColor]
    var shininess: Optional[Float64]
    var transparency: Optional[Float64]

    def __init__(out self):
        """Hold nothing."""
        self.diffuse = None
        self.emissive = None
        self.specular = None
        self.shininess = None
        self.transparency = None


struct _TextureTransform(Copyable, Movable):
    """What a `TextureTransform` node holds, three.js's `transformData`."""

    var center: Vector2
    var rotation: Float64
    var scale: Vector2
    var translation: Vector2

    def __init__(out self):
        """Hold three.js's zero vectors."""
        self.center = Vector2(0, 0)
        self.rotation = 0
        self.scale = Vector2(0, 0)
        self.translation = Vector2(0, 0)


struct VrmlModel(Movable):
    """What `parse_vrml` put into the scene and the assets."""

    # The node three.js returns as its `Scene`. The nodes at the top of
    # the file are under it.
    var root: NodeId
    var tree: VrmlTree
    # The last `WorldInfo` at the top of the file: its title, when it has
    # one, and its information.
    var has_world_info: Bool
    var title: Optional[String]
    var info: List[String]
    var objects: List[VrmlObject]
    var geometries: List[VrmlGeometry]
    var materials: List[VrmlMaterial]
    var textures: List[VrmlTexture]

    def __init__(out self, root: NodeId, var tree: VrmlTree):
        """Hold an empty model.

        Args:
            root: The scene node.
            tree: The parsed file.
        """
        self.root = root
        self.tree = tree^
        self.has_world_info = False
        self.title = None
        self.info = List[String]()
        self.objects = List[VrmlObject]()
        self.geometries = List[VrmlGeometry]()
        self.materials = List[VrmlMaterial]()
        self.textures = List[VrmlTexture]()

    def object_of(self, node: NodeId) -> Int:
        """Return the object record of a node.

        Args:
            node: A node the loader made.

        Returns:
            An index into `objects`, or -1 for a node the loader did not
            make.
        """
        for i in range(len(self.objects)):
            if self.objects[i].node == node:
                return i
        return -1

    def count(self, kind: VrmlObjectKind) raises -> Int:
        """Return how many objects are of a kind.

        Args:
            kind: The kind.

        Returns:
            The count.

        Raises:
            Error: If the kind is not valid.
        """
        if not kind.is_valid():
            raise Error("VRML: an object kind that is not valid")
        var total = 0
        for o in self.objects:
            if o.kind == kind:
                total += 1
        return total


def _is_object(name: String) -> Bool:
    """Return True for a node that three.js builds as an `Object3D`."""
    return _is_group(name) or name == "Background" or name == "Shape"


def _is_group(name: String) -> Bool:
    """Return True for a node three.js builds as a `Group`."""
    return (
        name == "Anchor"
        or name == "Group"
        or name == "Transform"
        or name == "Collision"
    )


def _is_geometry(name: String) -> Bool:
    """Return True for a node three.js builds as a geometry."""
    return (
        name == "IndexedFaceSet"
        or name == "IndexedLineSet"
        or name == "PointSet"
        or name == "Box"
        or name == "Cone"
        or name == "Cylinder"
        or name == "Sphere"
        or name == "ElevationGrid"
        or name == "Extrusion"
    )


def _is_property(name: String) -> Bool:
    """Return True for a node whose first field three.js reads as a list
    of numbers."""
    return (
        name == "Color"
        or name == "Coordinate"
        or name == "Normal"
        or name == "TextureCoordinate"
    )


def _numbers(field: VrmlField) raises -> List[Float64]:
    """Return the values of a field, each a number."""
    var out = List[Float64]()
    for v in field.values:
        if v.kind != VRML_NUMBER_VALUE:
            raise Error("VRML: field `" + field.name + "` needs numbers")
        out.append(v.number)
    return out^


def _first_numbers(field: VrmlField, count: Int) raises -> List[Float64]:
    """Return the first `count` values of a field, each a number."""
    var all = _numbers(field)
    if len(all) < count:
        raise Error(
            "VRML: field `"
            + field.name
            + "` needs "
            + String(count)
            + " numbers"
        )
    return all^


def _flag(field: VrmlField) raises -> Bool:
    """Return the first value of a field, a boolean."""
    var boolean = len(field.values) > 0 and (
        field.values[0].kind == VRML_BOOLEAN_VALUE
    )
    if not boolean:
        raise Error("VRML: field `" + field.name + "` needs TRUE or FALSE")
    return field.values[0].boolean


def _is_false(field: VrmlField) -> Bool:
    """Return three.js's `fieldValues[ 0 ] === false`."""
    var boolean = len(field.values) > 0 and (
        field.values[0].kind == VRML_BOOLEAN_VALUE
    )
    return boolean and not field.values[0].boolean


def _strings(field: VrmlField) raises -> List[String]:
    """Return the values of a field, each a string."""
    var out = List[String]()
    for v in field.values:
        if v.kind != VRML_STRING_VALUE:
            raise Error("VRML: field `" + field.name + "` needs strings")
        out.append(v.text)
    return out^


def _is_null(field: VrmlField) -> Bool:
    """Return three.js's `fieldValues[ 0 ] === null`."""
    return len(field.values) > 0 and field.values[0].kind == VRML_NULL_VALUE


def _whole(value: Float64, name: String) raises -> Int:
    """Return a count that is a whole number, zero or more."""
    var whole = value == trunc(value) and value >= 0 and value < 1e15
    if not whole:
        raise Error("VRML: field `" + name + "` needs a whole number")
    return Int(value)


def _attribute(values: List[Float64], size: Int) raises -> BufferAttribute:
    """Return an attribute of values, refused when one is `NaN`."""
    if has_nan(values):
        raise Error(
            "VRML: a geometry reads a value that is not there, as an index"
            " that names no entry"
        )
    var data = List[Float32]()
    for v in values:
        data.append(Float32(v))
    return BufferAttribute(data^, size)


def _hex_digit(byte: UInt8) -> Int:
    """Return the value of a hex digit the lexer took."""
    if byte <= 57:
        return Int(byte) - 48
    return Int(byte | 32) - 87


def _hex_pair(hex: String, start: Int) -> UInt8:
    """Return three.js's `parseInt( '0x' + hex.substring( start, start + 2
    ) )` as a `Uint8Array` stores it: zero when nothing is there."""
    var bytes = hex.as_bytes()
    var value = 0
    for i in range(start, min(start + 2, len(bytes))):
        value = value * 16 + _hex_digit(bytes[i])
    return UInt8(value)


def _intensity(value: VrmlValue) raises -> UInt8:
    """Return three.js's `parseInt( hex )` of an intensity, as a
    `Uint8Array` stores it: modulo 256."""
    if value.kind == VRML_HEX_VALUE:
        var bytes = value.text.as_bytes()
        var low = 0
        # A hex number has a digit after `0x`. The loop always runs.
        for i in range(max(2, len(bytes) - 2), len(bytes)):  # pragma: no branch
            low = low * 16 + _hex_digit(bytes[i])
        return UInt8(low)
    var v = value.number
    var plain = v == 0 or (abs(v) >= 1e-6 and abs(v) < 1e21)
    if not plain:
        raise Error("VRML: a pixel value that three.js reads by its exponent")
    var whole = Int(trunc(v))
    return UInt8(((whole % 256) + 256) % 256)


struct _Builder(Movable):
    """Builds the nodes of a tree, three.js's `getNode` and `buildNode`."""

    var model: VrmlModel
    var resource_path: String
    # Each node's build, or -1 when it has none yet.
    var built: List[Int]
    var building: List[Bool]
    # three.js's `nodeMap`: the node each `DEF` name names last.
    var defs: Dict[String, Int]
    var material_data: List[_MaterialData]
    var transforms: List[_TextureTransform]
    # What each `WorldInfo` holds.
    var titles: List[Optional[String]]
    var infos: List[List[String]]

    def __init__(out self, var model: VrmlModel, var resource_path: String):
        """Start with nothing built."""
        var count = len(model.tree.nodes)
        self.model = model^
        self.resource_path = resource_path^
        self.built = List[Int](length=count, fill=-1)
        self.building = List[Bool](length=count, fill=False)
        self.defs = Dict[String, Int]()
        self.material_data = List[_MaterialData]()
        self.transforms = List[_TextureTransform]()
        self.titles = List[Optional[String]]()
        self.infos = List[List[String]]()
        # three.js's `buildNodeMap`: a node's fields are walked when the
        # last kind of their values is a node.
        # The grammar gives one root at least. The loop always runs.
        for root in self.model.tree.roots:  # pragma: no branch
            self.map_names(root)

    def map_names(mut self, root: Int):
        """Record each `DEF` name under a node, in the order three.js's
        `buildNodeMap` walks them."""
        var stack: List[Int] = [root]
        while len(stack) > 0:
            var node = stack.pop()
            if self.model.tree.nodes[node].has_def:
                self.defs[self.model.tree.nodes[node].def_name] = node
            var children = List[Int]()
            for field in self.model.tree.nodes[node].fields:
                if field.kind != VRML_NODE_VALUE:
                    continue
                # A field of nodes has one at least. The loop always runs.
                for v in field.values:  # pragma: no branch
                    children.append(v.node)
            # Last first, so that the first child comes off the stack next.
            for i in range(len(children) - 1, -1, -1):
                stack.append(children[i])

    def result(deinit self) -> VrmlModel:
        """Give up the model."""
        return self.model^

    def get(
        mut self, value: VrmlValue, mut scene: Scene, mut assets: Assets
    ) raises -> Tuple[Int, Int]:
        """Build a node value or resolve a `USE`, three.js's `getNode`.

        Returns:
            The tree node, and its build: an object, a material, a
            texture, a transform, a geometry or a world info index, or -1.

        Raises:
            Error: If the value is not a node or a `USE`, or the `USE`
                names nothing.
        """
        if value.kind == VRML_USE_VALUE:
            return self.resolve(value.text, scene, assets)
        if value.kind != VRML_NODE_VALUE:
            raise Error("VRML: a field needs a node where it has another value")
        return (value.node, self.build(value.node, scene, assets))

    def resolve(
        mut self, name: String, mut scene: Scene, mut assets: Assets
    ) raises -> Tuple[Int, Int]:
        """Return a copy of a group or a shape, or of an appearance's
        material, or else the build itself, three.js's `resolveUSE`."""
        var found = self.defs.get(name)
        if not Bool(found):
            raise Error("VRML: USE of `" + name + "`, which no DEF names")
        var node = found.value()
        var result = self.build(node, scene, assets)
        var kind = self.model.tree.nodes[node].name
        if _is_object(kind):
            return (node, self.clone(result, scene))
        if kind == "Appearance":
            var copy = self.model.materials[result].copy()
            copy.id = MaterialId(-1)
            self.model.materials.append(copy^)
            return (node, len(self.model.materials) - 1)
        return (node, result)

    def clone(mut self, object: Int, mut scene: Scene) raises -> Int:
        """Copy an object and each object under it, with what each draws,
        three.js's `clone`."""
        var source = self.model.objects[object].node
        var copy = scene.clone(source)
        var sources = scene.traverse(source)
        var copies = scene.traverse(copy)
        # A node is its own first entry: the loop always runs.
        for i in range(len(sources)):  # pragma: no branch
            var found = self.model.object_of(sources[i])
            var record = self.model.objects[found].copy()
            record.node = copies[i]
            self.model.objects.append(record^)
        return self.model.object_of(copy)

    def build(
        mut self, node: Int, mut scene: Scene, mut assets: Assets
    ) raises -> Int:
        """Build a node once, three.js's `getNode` for a node."""
        if self.built[node] >= 0:
            return self.built[node]
        if self.building[node]:
            raise Error("VRML: a node that uses itself")
        for field in self.model.tree.nodes[node].fields:
            if not field.kind.is_valid():
                raise Error("VRML: a field whose kind is not valid")
        self.building[node] = True
        var result = self.build_node(node, scene, assets)
        self.building[node] = False
        self.built[node] = result
        return result

    def build_node(
        mut self, node: Int, mut scene: Scene, mut assets: Assets
    ) raises -> Int:
        """Build a node by its name, three.js's `buildNode`."""
        var name = self.model.tree.nodes[node].name
        var def_name = self.model.tree.nodes[node].def_name
        if _is_group(name):
            return self.group(node, def_name, scene, assets)
        if name == "Background":
            return self.background(node, def_name, scene, assets)
        if name == "Shape":
            return self.shape(node, def_name, scene, assets)
        if name == "Appearance":
            return self.appearance(node, def_name, scene, assets)
        if name == "Material":
            return self.material_node(node)
        if name == "ImageTexture":
            return self.image_texture(node, def_name, assets)
        if name == "PixelTexture":
            return self.pixel_texture(node, def_name, assets)
        if name == "TextureTransform":
            return self.texture_transform(node)
        if _is_geometry(name):
            var geometry = self.geometry(node, name, scene, assets)
            self.model.geometries[geometry].name = def_name
            return geometry
        if name == "WorldInfo":
            return self.world_info(node)
        # A `Color`, `Coordinate`, `Normal` or `TextureCoordinate` is read
        # where it is used; the other nodes are not built.
        return -1

    def add_object(
        mut self,
        var object: Object3D,
        kind: VrmlObjectKind,
        geometry: Int,
        material: Int,
        mut scene: Scene,
    ) raises -> Int:
        """Add a node out of the scene, until a parent takes it, and its
        record."""
        var id = scene.add(object^)
        scene.remove_from_parent(id)
        self.model.objects.append(VrmlObject(id, kind, geometry, material))
        return len(self.model.objects) - 1

    def children(
        mut self,
        field: VrmlField,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Build each child and add each object, three.js's
        `parseFieldChildren`."""
        for v in field.values:
            var built = self.get(v, scene, assets)
            if _is_object(self.model.tree.nodes[built[0]].name):
                scene.add(self.model.objects[built[1]].node, parent=parent)

    def group(
        mut self,
        node: Int,
        name: String,
        mut scene: Scene,
        mut assets: Assets,
    ) raises -> Int:
        """Build a group, three.js's `buildGroupingNode`."""
        var object = Object3D()
        object.name = name
        var kids = List[Int]()
        var fields = self.model.tree.nodes[node].fields.copy()
        for f in range(len(fields)):
            ref field = fields[f]
            if field.name == "children":
                kids.append(f)
            elif field.name == "rotation":
                var v = _first_numbers(field, 4)
                var length = sqrt(
                    product(v[0], v[0])
                    + product(v[1], v[1])
                    + product(v[2], v[2])
                )
                # three.js's `normalize` multiplies by one over the length.
                var inverse = 1 / (length if length != 0 else Float64(1))
                var s = sin(v[3] / 2)
                object.quaternion = Quaternion(
                    Float32(product(product(v[0], inverse), s)),
                    Float32(product(product(v[1], inverse), s)),
                    Float32(product(product(v[2], inverse), s)),
                    Float32(cos(v[3] / 2)),
                )
            elif field.name == "scale":
                var v = _first_numbers(field, 3)
                object.scale = Vector3(
                    Float32(v[0]), Float32(v[1]), Float32(v[2])
                )
            elif field.name == "translation":
                var v = _first_numbers(field, 3)
                object.set_position(Float32(v[0]), Float32(v[1]), Float32(v[2]))
        var index = self.add_object(object^, VRML_GROUP, -1, -1, scene)
        var id = self.model.objects[index].node
        for f in kids:
            self.children(fields[f], id, scene, assets)
        return index

    def background(
        mut self,
        node: Int,
        name: String,
        mut scene: Scene,
        mut assets: Assets,
    ) raises -> Int:
        """Build a background, three.js's `buildBackgroundNode`."""
        var ground_angle: Optional[List[Float64]] = None
        var ground_color: Optional[List[Float64]] = None
        var sky_angle: Optional[List[Float64]] = None
        var sky_color: Optional[List[Float64]] = None
        for field in self.model.tree.nodes[node].fields:
            if field.name == "groundAngle":
                ground_angle = _numbers(field)
            elif field.name == "groundColor":
                ground_color = _numbers(field)
            elif field.name == "skyAngle":
                sky_angle = _numbers(field)
            elif field.name == "skyColor":
                sky_color = _numbers(field)
        var object = Object3D()
        object.name = name
        object.render_order = Int.MIN
        var index = self.add_object(object^, VRML_GROUP, -1, -1, scene)
        var group = self.model.objects[index].node
        var radius = Float64(VRML_BACKGROUND_RADIUS.value)
        if Bool(sky_color):
            var colors = sky_color.value().copy()
            var sphere = sphere_data(radius, 32, 16)
            var material = VrmlMaterial(BASIC, FloatColor(1, 1, 1, 1))
            if len(colors) > 3:
                if not Bool(sky_angle):
                    raise Error(
                        "VRML: a sky of more than one color needs skyAngle"
                    )
                var painted = paint_faces(
                    sphere, radius, sky_angle.value(), colors, True
                )
                material.vertex_colors = True
                self.sphere_mesh(
                    sphere, painted, material^, group, scene, assets
                )
            else:
                if len(colors) < 3:
                    raise Error("VRML: field `skyColor` needs 3 numbers")
                material.color = _linear(colors[0], colors[1], colors[2])
                self.sphere_mesh(
                    sphere, List[Float64](), material^, group, scene, assets
                )
        if Bool(ground_color):
            var colors = ground_color.value().copy()
            if len(colors) > 0:
                if len(colors) <= 3:
                    raise Error("VRML: a ground needs two colors or more")
                if not Bool(ground_angle):
                    raise Error("VRML: a ground needs groundAngle")
                var sphere = sphere_data(
                    radius, 32, 16, 0, 2 * pi, 0.5 * pi, 1.5 * pi
                )
                var material = VrmlMaterial(BASIC, FloatColor(1, 1, 1, 1))
                material.vertex_colors = True
                var painted = paint_faces(
                    sphere, radius, ground_angle.value(), colors, False
                )
                self.sphere_mesh(
                    sphere, painted, material^, group, scene, assets
                )
        return index

    def sphere_mesh(
        mut self,
        sphere: SurfaceData,
        colors: List[Float64],
        var material: VrmlMaterial,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add a background sphere: back faces, drawn first and behind
        everything, with no fog."""
        var record = VrmlGeometry(GeometryId(-1), VRML_MESH)
        record.has_color = len(colors) > 0
        record.id = assets.geometries.add(_surface(sphere, colors))
        material.side = BACK_SIDE
        material.depth_write = False
        material.depth_test = False
        material.fog = False
        material.id = assets.materials.add(material.build(NO_TEXTURE))
        var mesh_material = material.id
        self.model.materials.append(material^)
        self.model.geometries.append(record^)
        var index = self.add_object(
            Object3D(),
            VRML_MESH,
            len(self.model.geometries) - 1,
            len(self.model.materials) - 1,
            scene,
        )
        var id = self.model.objects[index].node
        scene.add(id, parent=parent)
        scene.add_mesh(
            Mesh(
                self.model.geometries[len(self.model.geometries) - 1].id,
                mesh_material,
                id,
            )
        )

    def shape(
        mut self,
        node: Int,
        name: String,
        mut scene: Scene,
        mut assets: Assets,
    ) raises -> Int:
        """Build a shape, three.js's `buildShapeNode`."""
        var material = -1
        var geometry = -1
        var fields = self.model.tree.nodes[node].fields.copy()
        for field in fields:
            if field.name == "appearance":
                if _is_null(field):
                    continue
                var built = self.get(_first(field), scene, assets)
                if self.model.tree.nodes[built[0]].name != "Appearance":
                    raise Error("VRML: field `appearance` needs an Appearance")
                material = built[1]
            elif field.name == "geometry":
                if _is_null(field):
                    continue
                var built = self.get(_first(field), scene, assets)
                ref kind = self.model.tree.nodes[built[0]].name
                var usable = _is_geometry(kind) or kind == "Text"
                if not usable:
                    raise Error("VRML: field `geometry` needs a geometry node")
                geometry = built[1]
        if material < 0:
            var fallback = VrmlMaterial(BASIC, FloatColor(0, 0, 0, 1))
            fallback.name = VRML_DEFAULT_MATERIAL_NAME
            self.model.materials.append(fallback^)
            material = len(self.model.materials) - 1
        var object = Object3D()
        object.name = name
        var drawn = (
            geometry >= 0 and self.model.geometries[geometry].has_position
        )
        if not drawn:
            object.visible = False
            return self.add_object(object^, VRML_EMPTY, -1, -1, scene)
        var record = self.model.geometries[geometry].copy()
        if record.kind == VRML_MESH:
            if record.has_solid:
                var side = FRONT_SIDE if record.solid else DOUBLE_SIDE
                self.model.materials[material].side = side
            if record.has_color:
                self.model.materials[material].vertex_colors = True
            var map = self.texture_id(self.model.materials[material].map)
            var id = assets.materials.add(
                self.model.materials[material].build(map)
            )
            self.model.materials[material].id = id
            var index = self.add_object(
                object^, VRML_MESH, geometry, material, scene
            )
            scene.add_mesh(Mesh(record.id, id, self.model.objects[index].node))
            return index
        # three.js's `PointsMaterial` or `LineBasicMaterial`: white, or the
        # emissive color of a phong material when there are no colors.
        var look = self.model.materials[material].copy()
        var drawn_with = VrmlMaterial(BASIC, FloatColor(1, 1, 1, 1))
        drawn_with.name = VRML_DEFAULT_MATERIAL_NAME
        drawn_with.opacity = look.opacity
        drawn_with.transparent = look.transparent
        if record.has_color:
            drawn_with.vertex_colors = True
        elif look.kind == PHONG:
            drawn_with.color = look.emissive
        var kind = VRML_POINTS if record.kind == VRML_POINTS else VRML_LINES
        var built: Material
        if kind == VRML_POINTS:
            built = points_material(
                _authored(drawn_with.color),
                opacity=Float32(drawn_with.opacity),
                transparent=drawn_with.transparent,
                vertex_colors=drawn_with.vertex_colors,
            )
        else:
            built = drawn_with.build(NO_TEXTURE)
        drawn_with.id = assets.materials.add(built)
        var id = drawn_with.id
        self.model.materials.append(drawn_with^)
        var index = self.add_object(
            object^, kind, geometry, len(self.model.materials) - 1, scene
        )
        var at = self.model.objects[index].node
        if kind == VRML_POINTS:
            scene.add_points(Points(record.id, id, at))
        else:
            scene.add_line(Line(record.id, id, at, mode=SEGMENTS))
        return index

    def texture_id(self, map: Int) -> TextureId:
        """Return a texture record's texture, or `NO_TEXTURE`."""
        if map < 0:
            return NO_TEXTURE
        return self.model.textures[map].id

    def appearance(
        mut self,
        node: Int,
        name: String,
        mut scene: Scene,
        mut assets: Assets,
    ) raises -> Int:
        """Build an appearance's material, three.js's
        `buildAppearanceNode`."""
        var look = VrmlMaterial(PHONG, FloatColor(1, 1, 1, 1))
        var transform = -1
        var fields = self.model.tree.nodes[node].fields.copy()
        for field in fields:
            if field.name == "material":
                if _is_null(field):
                    look = VrmlMaterial(BASIC, FloatColor(0, 0, 0, 1))
                    look.name = VRML_DEFAULT_MATERIAL_NAME
                    continue
                var built = self.get(_first(field), scene, assets)
                if self.model.tree.nodes[built[0]].name != "Material":
                    raise Error("VRML: field `material` needs a Material")
                self.apply(look, self.material_data[built[1]])
            elif field.name == "texture":
                if _is_null(field):
                    continue
                var value = _first(field)
                if value.kind != VRML_NODE_VALUE:
                    continue
                ref kind = self.model.tree.nodes[value.node].name
                var image = kind == "ImageTexture" or kind == "PixelTexture"
                if image:
                    look.map = self.get(value, scene, assets)[1]
            elif field.name == "textureTransform":
                if _is_null(field):
                    continue
                var built = self.get(_first(field), scene, assets)
                if self.model.tree.nodes[built[0]].name != "TextureTransform":
                    raise Error(
                        "VRML: field `textureTransform` needs a"
                        " TextureTransform"
                    )
                transform = built[1]
        if look.map >= 0:
            var kind = self.model.textures[look.map].pending_type
            if kind == 2:
                look.opacity = 1
            elif kind >= 3:
                look.color = FloatColor(1, 1, 1, 1)
                if kind == 4:
                    look.opacity = 1
            self.model.textures[look.map].pending_type = 0
            if transform >= 0:
                var data = self.transforms[transform].copy()
                self.model.textures[look.map].center = data.center
                self.model.textures[look.map].rotation = data.rotation
                self.model.textures[look.map].repeat = data.scale
                self.model.textures[look.map].offset = data.translation
        look.name = name if name.byte_length() > 0 else look.name
        self.model.materials.append(look^)
        return len(self.model.materials) - 1

    def apply(self, mut look: VrmlMaterial, data: _MaterialData) raises:
        """Copy a `Material` node's values onto a material, as three.js's
        `buildAppearanceNode` copies them."""
        if Bool(data.diffuse):
            look.color = data.diffuse.value()
        var lit = Bool(data.emissive) or Bool(data.specular)
        var throws = look.kind == BASIC and lit
        if throws:
            raise Error(
                "VRML: an emissive or specular color after `material NULL`,"
                " where three.js throws"
            )
        if Bool(data.emissive):
            look.emissive = data.emissive.value()
        if Bool(data.shininess):
            var shininess = data.shininess.value()
            if shininess != 0:
                look.shininess = shininess
        if Bool(data.specular):
            look.specular = data.specular.value()
        if Bool(data.transparency):
            var transparency = data.transparency.value()
            if transparency != 0:
                look.opacity = 1 - transparency
            if transparency > 0:
                look.transparent = True

    def material_node(mut self, node: Int) raises -> Int:
        """Read a `Material` node, three.js's `buildMaterialNode`."""
        var data = _MaterialData()
        for field in self.model.tree.nodes[node].fields:
            if field.name == "diffuseColor":
                var v = _first_numbers(field, 3)
                data.diffuse = _linear(v[0], v[1], v[2])
            elif field.name == "emissiveColor":
                var v = _first_numbers(field, 3)
                data.emissive = _linear(v[0], v[1], v[2])
            elif field.name == "shininess":
                data.shininess = _first_numbers(field, 1)[0]
            elif field.name == "specularColor":
                var v = _first_numbers(field, 3)
                data.specular = _linear(v[0], v[1], v[2])
            elif field.name == "transparency":
                data.transparency = _first_numbers(field, 1)[0]
        self.material_data.append(data^)
        return len(self.material_data) - 1

    def image_texture(
        mut self, node: Int, name: String, mut assets: Assets
    ) raises -> Int:
        """Read an `ImageTexture`, three.js's `buildImageTextureNode`."""
        var url = String()
        var wrap_s = REPEAT
        var wrap_t = REPEAT
        for field in self.model.tree.nodes[node].fields:
            if field.name == "url":
                var urls = _strings(field)
                # three.js keeps the texture it has for an empty url.
                if len(urls) > 0 and urls[0].byte_length() > 0:
                    url = urls[0]
            elif field.name == "repeatS":
                if _is_false(field):
                    wrap_s = CLAMP
            elif field.name == "repeatT":
                if _is_false(field):
                    wrap_t = CLAMP
        if url.byte_length() == 0:
            return -1
        var record = VrmlTexture(name, url)
        record.wrap_s = wrap_s
        record.wrap_t = wrap_t
        var file = Path(self.resource_path + url)
        if file.exists():
            var image = decode_image(file.read_bytes())
            var texture = Texture(
                image.width,
                image.height,
                image.pixels.copy(),
                _wrap(wrap_s, wrap_t),
                BILINEAR,
                SRGB,
            )
            record.id = assets.textures.add(texture^)
        self.model.textures.append(record^)
        return len(self.model.textures) - 1

    def pixel_texture(
        mut self, node: Int, name: String, mut assets: Assets
    ) raises -> Int:
        """Read a `PixelTexture`, three.js's `buildPixelTextureNode`."""
        var record: Optional[VrmlTexture] = None
        var wrap_s = REPEAT
        var wrap_t = REPEAT
        for field in self.model.tree.nodes[node].fields:
            if field.name == "image":
                record = _pixels(field, name)
            elif field.name == "repeatS":
                if _is_false(field):
                    wrap_s = CLAMP
            elif field.name == "repeatT":
                if _is_false(field):
                    wrap_t = CLAMP
        if not Bool(record):
            return -1
        var texture = record.take()
        texture.wrap_s = wrap_s
        texture.wrap_t = wrap_t
        var drawn = texture.width > 0 and texture.height > 0
        if drawn:
            # Rows from the top, reversed: three.js's `DataTexture` samples
            # its first row at the bottom.
            var pixels = List[UInt8]()
            var row = texture.width * 4
            # Both sizes are above zero here. The loop always runs.
            for y in range(texture.height - 1, -1, -1):  # pragma: no branch
                # Both sizes are above zero here. The loop always runs.
                for x in range(row):  # pragma: no branch
                    pixels.append(texture.data[y * row + x])
            texture.id = assets.textures.add(
                Texture(
                    texture.width,
                    texture.height,
                    pixels^,
                    _wrap(wrap_s, wrap_t),
                    NEAREST,
                    SRGB,
                    mipmapped=False,
                )
            )
        self.model.textures.append(texture^)
        return len(self.model.textures) - 1

    def texture_transform(mut self, node: Int) raises -> Int:
        """Read a `TextureTransform`, three.js's
        `buildTextureTransformNode`."""
        var data = _TextureTransform()
        for field in self.model.tree.nodes[node].fields:
            if field.name == "center":
                data.center = _pair(field)
            elif field.name == "rotation":
                data.rotation = _first_numbers(field, 1)[0]
            elif field.name == "scale":
                data.scale = _pair(field)
            elif field.name == "translation":
                data.translation = _pair(field)
        self.transforms.append(data^)
        return len(self.transforms) - 1

    def world_info(mut self, node: Int) raises -> Int:
        """Read a `WorldInfo`, three.js's `buildWorldInfoNode`. The caller
        keeps it only at the top of the file."""
        var title: Optional[String] = None
        var info = List[String]()
        for field in self.model.tree.nodes[node].fields:
            if field.name == "title":
                var titles = _strings(field)
                if len(titles) == 0:
                    raise Error("VRML: field `title` needs a string")
                title = titles[0]
            elif field.name == "info":
                info = _strings(field)
        self.titles.append(title^)
        self.infos.append(info^)
        return len(self.titles) - 1

    def values(
        mut self, field: VrmlField, mut scene: Scene, mut assets: Assets
    ) raises -> Optional[List[Float64]]:
        """Return the numbers of a `Color`, `Coordinate`, `Normal` or
        `TextureCoordinate` node a field holds, three.js's
        `buildGeometricNode`, or none for `NULL`."""
        if _is_null(field):
            return None
        var built = self.get(_first(field), scene, assets)
        ref property = self.model.tree.nodes[built[0]]
        if not _is_property(property.name):
            raise Error(
                "VRML: field `"
                + field.name
                + "` needs a Color, Coordinate, Normal or TextureCoordinate"
            )
        if len(property.fields) == 0:
            raise Error("VRML: a `" + property.name + "` with no values")
        return _numbers(property.fields[0])

    def geometry(
        mut self,
        node: Int,
        name: String,
        mut scene: Scene,
        mut assets: Assets,
    ) raises -> Int:
        """Build a geometry node."""
        var record: VrmlGeometry
        if name == "IndexedFaceSet":
            record = self.face_set(node, scene, assets)
        elif name == "IndexedLineSet":
            record = self.line_set(node, scene, assets)
        elif name == "PointSet":
            record = self.point_set(node, scene, assets)
        elif name == "ElevationGrid":
            record = self.elevation(node, scene, assets)
        elif name == "Extrusion":
            record = self.extrusion(node, assets)
        else:
            record = self.primitive(node, name, assets)
        self.model.geometries.append(record^)
        return len(self.model.geometries) - 1

    def face_set(
        mut self, node: Int, mut scene: Scene, mut assets: Assets
    ) raises -> VrmlGeometry:
        """Build an `IndexedFaceSet`, three.js's `buildIndexedFaceSetNode`."""
        var color: Optional[List[Float64]] = None
        var coord = List[Float64]()
        var normal: Optional[List[Float64]] = None
        var tex_coord: Optional[List[Float64]] = None
        var ccw = True
        var solid = True
        var crease = Float64(0)
        var color_index = List[Float64]()
        var coord_index: Optional[List[Float64]] = None
        var normal_index = List[Float64]()
        var tex_coord_index = List[Float64]()
        var color_per_vertex = True
        var normal_per_vertex = True
        var fields = self.model.tree.nodes[node].fields.copy()
        for field in fields:
            if field.name == "color":
                color = self.values(field, scene, assets)
            elif field.name == "coord":
                var got = self.values(field, scene, assets)
                if Bool(got):
                    coord = got.take()
            elif field.name == "normal":
                normal = self.values(field, scene, assets)
            elif field.name == "texCoord":
                tex_coord = self.values(field, scene, assets)
            elif field.name == "ccw":
                ccw = _flag(field)
            elif field.name == "colorIndex":
                color_index = _numbers(field)
            elif field.name == "colorPerVertex":
                color_per_vertex = _flag(field)
            elif field.name == "coordIndex":
                coord_index = _numbers(field)
            elif field.name == "creaseAngle":
                crease = _first_numbers(field, 1)[0]
            elif field.name == "normalIndex":
                normal_index = _numbers(field)
            elif field.name == "normalPerVertex":
                normal_per_vertex = _flag(field)
            elif field.name == "solid":
                solid = _flag(field)
            elif field.name == "texCoordIndex":
                tex_coord_index = _numbers(field)
        if not Bool(coord_index):
            # three.js warns and returns an empty geometry, which its shape
            # hides.
            var empty = VrmlGeometry(
                assets.geometries.add(BufferGeometry()), VRML_MESH
            )
            empty.has_position = False
            return empty^
        var faces = coord_index.take()
        var triangles = triangulate_face_index(faces, ccw)
        var geometry = BufferGeometry()
        var record = VrmlGeometry(GeometryId(-1), VRML_MESH)
        record.has_solid = True
        record.solid = solid
        var normals: List[Float64]
        if Bool(normal):
            normals = _spread(
                normal.value(),
                normal_index,
                normal_per_vertex,
                faces,
                triangles,
                ccw,
            )
        else:
            normals = normal_attribute(triangles, coord, crease)
        var positions = to_non_indexed(triangles, coord, 3)
        geometry.set_attribute(POSITION, _attribute(positions, 3))
        geometry.set_attribute(NORMAL, _attribute(normals, 3))
        if Bool(color):
            var colors = _spread(
                color.value(),
                color_index,
                color_per_vertex,
                faces,
                triangles,
                ccw,
            )
            colors_to_linear(colors)
            geometry.set_attribute(COLOR, _attribute(colors, 3))
            record.has_color = True
        if Bool(tex_coord):
            var uvs: List[Float64]
            if len(tex_coord_index) > 0:
                var uv_triangles = triangulate_face_index(tex_coord_index, ccw)
                uvs = from_indexed_data(
                    triangles, uv_triangles, tex_coord.value(), 2
                )
            else:
                uvs = to_non_indexed(triangles, tex_coord.value(), 2)
            geometry.set_attribute(UV, _attribute(uvs, 2))
        record.id = assets.geometries.add(geometry^)
        return record^

    def line_set(
        mut self, node: Int, mut scene: Scene, mut assets: Assets
    ) raises -> VrmlGeometry:
        """Build an `IndexedLineSet`, three.js's `buildIndexedLineSetNode`."""
        var color: Optional[List[Float64]] = None
        var coord = List[Float64]()
        var color_index: Optional[List[Float64]] = None
        var coord_index: Optional[List[Float64]] = None
        var color_per_vertex = True
        var fields = self.model.tree.nodes[node].fields.copy()
        for field in fields:
            if field.name == "color":
                color = self.values(field, scene, assets)
            elif field.name == "coord":
                var got = self.values(field, scene, assets)
                if Bool(got):
                    coord = got.take()
            elif field.name == "colorIndex":
                color_index = _numbers(field)
            elif field.name == "colorPerVertex":
                color_per_vertex = _flag(field)
            elif field.name == "coordIndex":
                coord_index = _numbers(field)
        if not Bool(coord_index):
            raise Error("VRML: an IndexedLineSet with no coordIndex")
        var lines = coord_index.take()
        var segments = expand_line_index(lines)
        var geometry = BufferGeometry()
        var record = VrmlGeometry(GeometryId(-1), VRML_LINES)
        geometry.set_attribute(
            POSITION, _attribute(to_non_indexed(segments, coord, 3), 3)
        )
        if Bool(color):
            if not Bool(color_index):
                raise Error(
                    "VRML: an IndexedLineSet with colors and no colorIndex"
                )
            var picks = color_index.take()
            var colors: List[Float64]
            if color_per_vertex:
                if len(picks) > 0:
                    colors = from_indexed_data(
                        segments, expand_line_index(picks), color.value(), 3
                    )
                else:
                    colors = to_non_indexed(segments, color.value(), 3)
            else:
                var per_line = (
                    flatten_data(color.value(), picks) if len(picks)
                    > 0 else color.value().copy()
                )
                colors = from_line_data(
                    segments, expand_line_data(per_line, lines)
                )
            colors_to_linear(colors)
            geometry.set_attribute(COLOR, _attribute(colors, 3))
            record.has_color = True
        record.id = assets.geometries.add(geometry^)
        return record^

    def point_set(
        mut self, node: Int, mut scene: Scene, mut assets: Assets
    ) raises -> VrmlGeometry:
        """Build a `PointSet`, three.js's `buildPointSetNode`."""
        var color: Optional[List[Float64]] = None
        var coord = List[Float64]()
        var fields = self.model.tree.nodes[node].fields.copy()
        for field in fields:
            if field.name == "color":
                color = self.values(field, scene, assets)
            elif field.name == "coord":
                var got = self.values(field, scene, assets)
                if Bool(got):
                    coord = got.take()
        var geometry = BufferGeometry()
        var record = VrmlGeometry(GeometryId(-1), VRML_POINTS)
        if len(coord) % 3 != 0:
            raise Error("VRML: a PointSet whose coord is not whole points")
        geometry.set_attribute(POSITION, _attribute(coord, 3))
        if Bool(color):
            var colors = color.value().copy()
            if len(colors) != len(coord):
                raise Error("VRML: a PointSet needs a color for each point")
            colors_to_linear(colors)
            geometry.set_attribute(COLOR, _attribute(colors, 3))
            record.has_color = True
        record.id = assets.geometries.add(geometry^)
        return record^

    def elevation(
        mut self, node: Int, mut scene: Scene, mut assets: Assets
    ) raises -> VrmlGeometry:
        """Build an `ElevationGrid`, three.js's `buildElevationGridNode`."""
        var color: Optional[List[Float64]] = None
        var normal: Optional[List[Float64]] = None
        var tex_coord: Optional[List[Float64]] = None
        var height = List[Float64]()
        var color_per_vertex = True
        var normal_per_vertex = True
        var solid = True
        var ccw = True
        var crease = Float64(0)
        var x_dimension = 2
        var z_dimension = 2
        var x_spacing = Float64(1)
        var z_spacing = Float64(1)
        var fields = self.model.tree.nodes[node].fields.copy()
        for field in fields:
            if field.name == "color":
                color = self.values(field, scene, assets)
            elif field.name == "normal":
                normal = self.values(field, scene, assets)
            elif field.name == "texCoord":
                tex_coord = self.values(field, scene, assets)
            elif field.name == "height":
                height = _numbers(field)
            elif field.name == "ccw":
                ccw = _flag(field)
            elif field.name == "colorPerVertex":
                color_per_vertex = _flag(field)
            elif field.name == "creaseAngle":
                crease = _first_numbers(field, 1)[0]
            elif field.name == "normalPerVertex":
                normal_per_vertex = _flag(field)
            elif field.name == "solid":
                solid = _flag(field)
            elif field.name == "xDimension":
                x_dimension = _whole(_first_numbers(field, 1)[0], field.name)
            elif field.name == "xSpacing":
                x_spacing = _first_numbers(field, 1)[0]
            elif field.name == "zDimension":
                z_dimension = _whole(_first_numbers(field, 1)[0], field.name)
            elif field.name == "zSpacing":
                z_spacing = _first_numbers(field, 1)[0]
        var grid = elevation_grid(
            height, x_dimension, z_dimension, x_spacing, z_spacing, ccw
        )
        ref vertices = grid[0]
        ref indices = grid[1]
        var geometry = BufferGeometry()
        var record = VrmlGeometry(GeometryId(-1), VRML_MESH)
        record.has_solid = True
        record.solid = solid
        geometry.set_attribute(
            POSITION, _attribute(to_non_indexed(indices, vertices, 3), 3)
        )
        var uvs = grid_uvs(
            tex_coord.value().copy() if Bool(tex_coord) else List[Float64](),
            Bool(tex_coord),
            x_dimension,
            z_dimension,
        )
        geometry.set_attribute(
            UV, _attribute(to_non_indexed(indices, uvs, 2), 2)
        )
        var normals: List[Float64]
        if Bool(normal):
            normals = self.grid_attribute(
                normal.value(),
                normal_per_vertex,
                x_dimension,
                z_dimension,
                indices,
            )
        else:
            normals = normal_attribute(indices, vertices, crease)
        geometry.set_attribute(NORMAL, _attribute(normals, 3))
        if Bool(color):
            var colors = self.grid_attribute(
                color.value(),
                color_per_vertex,
                x_dimension,
                z_dimension,
                indices,
            )
            colors_to_linear(colors)
            geometry.set_attribute(COLOR, _attribute(colors, 3))
            record.has_color = True
        record.id = assets.geometries.add(geometry^)
        return record^

    def grid_attribute(
        self,
        data: List[Float64],
        per_vertex: Bool,
        x_dimension: Int,
        z_dimension: Int,
        indices: List[Float64],
    ) -> List[Float64]:
        """Return an elevation grid's colors or normals, a vertex each."""
        var values = grid_values(data, x_dimension, z_dimension, per_vertex)
        if per_vertex:
            return to_non_indexed(indices, values, 3)
        var rounded = List[Float64]()
        for v in values:
            rounded.append(Float64(Float32(v)))
        return rounded^

    def extrusion(
        mut self, node: Int, mut assets: Assets
    ) raises -> VrmlGeometry:
        """Build an `Extrusion`, three.js's `buildExtrusionNode`."""
        var cross_section: List[Float64] = [1, 1, 1, -1, -1, -1, -1, 1, 1, 1]
        var spine: List[Float64] = [0, 0, 0, 0, 1, 0]
        var scale: Optional[List[Float64]] = None
        var orientation: Optional[List[Float64]] = None
        var begin_cap = True
        var ccw = True
        var crease = Float64(0)
        var end_cap = True
        var solid = True
        for field in self.model.tree.nodes[node].fields:
            if field.name == "beginCap":
                begin_cap = _flag(field)
            elif field.name == "ccw":
                ccw = _flag(field)
            elif field.name == "creaseAngle":
                crease = _first_numbers(field, 1)[0]
            elif field.name == "crossSection":
                cross_section = _numbers(field)
            elif field.name == "endCap":
                end_cap = _flag(field)
            elif field.name == "orientation":
                orientation = _numbers(field)
            elif field.name == "scale":
                scale = _numbers(field)
            elif field.name == "solid":
                solid = _flag(field)
            elif field.name == "spine":
                spine = _numbers(field)
        if len(cross_section) % 2 != 0:
            raise Error("VRML: a crossSection of an odd count of numbers")
        if len(spine) % 3 != 0:
            raise Error("VRML: a spine that is not whole points")
        var vertices = extrusion_points(
            cross_section,
            spine,
            scale.value().copy() if Bool(scale) else List[Float64](),
            Bool(scale),
            orientation.value().copy() if Bool(orientation) else List[
                Float64
            ](),
            Bool(orientation),
        )
        var indices = extrusion_indices(
            cross_section, len(spine) // 3, begin_cap, end_cap, ccw
        )
        var geometry = BufferGeometry()
        var record = VrmlGeometry(GeometryId(-1), VRML_MESH)
        record.has_solid = True
        record.solid = solid
        var normals = normal_attribute(indices, vertices, crease)
        geometry.set_attribute(
            POSITION, _attribute(to_non_indexed(indices, vertices, 3), 3)
        )
        geometry.set_attribute(NORMAL, _attribute(normals, 3))
        record.id = assets.geometries.add(geometry^)
        return record^

    def primitive(
        mut self, node: Int, name: String, mut assets: Assets
    ) raises -> VrmlGeometry:
        """Build a `Box`, a `Cone`, a `Cylinder` or a `Sphere`."""
        var size: List[Float64] = [2, 2, 2]
        var radius = Float64(1)
        var height = Float64(2)
        var open_ended = False
        # The fields each node reads: `size` for a box, `bottom`,
        # `bottomRadius` and `height` for a cone, `radius` and `height` for
        # a cylinder, and `radius` for a sphere.
        var radius_field = "bottomRadius" if name == "Cone" else "radius"
        var box_like = name == "Box"
        for field in self.model.tree.nodes[node].fields:
            var sized = box_like and field.name == "size"
            var bottom = name == "Cone" and field.name == "bottom"
            var tall = (
                not box_like and name != "Sphere" and (field.name == "height")
            )
            var round = not box_like and field.name == radius_field
            if sized:
                size = _first_numbers(field, 3)
            elif bottom:
                open_ended = not _flag(field)
            elif round:
                radius = _first_numbers(field, 1)[0]
            elif tall:
                height = _first_numbers(field, 1)[0]
        var surface: SurfaceData
        if name == "Box":
            surface = box_data(size[0], size[1], size[2])
        elif name == "Cone":
            surface = cylinder_data(0, radius, height, 16, open_ended)
        elif name == "Cylinder":
            surface = cylinder_data(radius, radius, height, 16, False)
        else:
            surface = sphere_data(radius, 16, 16)
        return VrmlGeometry(
            assets.geometries.add(_surface(surface, List[Float64]())), VRML_MESH
        )


def _surface(
    surface: SurfaceData, colors: List[Float64]
) raises -> BufferGeometry:
    """Return a sphere's or a box's geometry, with colors when given."""
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, _attribute(surface.positions, 3))
    geometry.set_attribute(NORMAL, _attribute(surface.normals, 3))
    geometry.set_attribute(UV, _attribute(surface.uvs, 2))
    if len(colors) > 0:
        geometry.set_attribute(COLOR, _attribute(colors, 3))
    geometry.set_index(surface.index.copy())
    return geometry^


def _first(field: VrmlField) raises -> VrmlValue:
    """Return the first value of a field."""
    if len(field.values) == 0:
        raise Error("VRML: field `" + field.name + "` needs a value")
    return field.values[0].copy()


def _pair(field: VrmlField) raises -> Vector2:
    """Return the first two numbers of a field."""
    var v = _first_numbers(field, 2)
    return Vector2(Float32(v[0]), Float32(v[1]))


def _wrap(s: Wrap, t: Wrap) -> Wrap:
    """Return the one wrap a texture here has: repeat when both repeat."""
    var both = s == REPEAT and t == REPEAT
    return REPEAT if both else CLAMP


def _spread(
    data: List[Float64],
    index: List[Float64],
    per_vertex: Bool,
    faces: List[Float64],
    triangles: List[Float64],
    ccw: Bool,
) -> List[Float64]:
    """Return a face set's colors or normals, a vertex each, as three.js's
    `buildIndexedFaceSetNode` spreads them."""
    if per_vertex:
        if len(index) > 0:
            return from_indexed_data(
                triangles, triangulate_face_index(index, ccw), data, 3
            )
        return to_non_indexed(triangles, data, 3)
    var per_face = flatten_data(data, index) if len(index) > 0 else data.copy()
    return from_face_data(triangles, triangulate_face_data(per_face, faces))


def _pixels(field: VrmlField, name: String) raises -> VrmlTexture:
    """Read a `PixelTexture`'s `image`: width, height, components, then
    one value a pixel, as three.js's `parseHexColor` reads them."""
    if len(field.values) < 3:
        raise Error(
            "VRML: field `image` needs a width, a height and components"
        )
    var head = List[Float64]()
    # Three values. The loop always runs.
    for k in range(3):  # pragma: no branch
        if field.values[k].kind != VRML_NUMBER_VALUE:
            raise Error(
                "VRML: field `image` needs a width, a height and components"
            )
        head.append(field.values[k].number)
    var record = VrmlTexture(name, String())
    record.width = _whole(head[0], "image")
    record.height = _whole(head[1], "image")
    var components = head[2]
    var kind = (
        Int(components) if components == trunc(components)
        and (components >= 1 and components <= 4) else 0
    )
    record.pending_type = kind
    var size = 4 * record.width * record.height
    record.data = List[UInt8](length=size, fill=0)
    var rgba: List[UInt8] = [0, 0, 0, 0]
    for j in range(3, len(field.values)):
        ref value = field.values[j]
        var number = value.kind == VRML_NUMBER_VALUE
        var usable = number or value.kind == VRML_HEX_VALUE
        if not usable:
            raise Error("VRML: a pixel that is not a number")
        if kind == 1:
            var v = _intensity(value)
            rgba = [v, v, v, 1]
        elif kind > 1:
            if number:
                raise Error(
                    "VRML: a pixel of more than one component needs a hex"
                    " number"
                )
            var r = _hex_pair(value.text, 2)
            var g = _hex_pair(value.text, 4)
            if kind == 2:
                rgba = [r, r, r, g]
            elif kind == 3:
                rgba = [r, g, _hex_pair(value.text, 6), 1]
            else:
                rgba = [
                    r,
                    g,
                    _hex_pair(value.text, 6),
                    _hex_pair(value.text, 8),
                ]
        var stride = (j - 3) * 4
        # Four channels. The loop always runs.
        for c in range(4):  # pragma: no branch
            if stride + c < size:
                record.data[stride + c] = rgba[c]
    return record^


def vrml_scene(
    var tree: VrmlTree,
    mut scene: Scene,
    mut assets: Assets,
    resource_path: String,
    parent: NodeId = NO_PARENT,
) raises -> VrmlModel:
    """Build a parsed file into the scene, three.js's `parseTree`.

    Args:
        tree: What `parse_vrml_text` gives.
        scene: The scene to add the nodes to.
        assets: Where the geometries, materials and textures go.
        resource_path: The directory an `ImageTexture`'s file is in.
        parent: The node to put the root under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: For a field of a kind that is not valid, and for anything
            the builders refuse: see the module docstring.
    """
    var root = scene.attach(Object3D(), parent)
    var builder = _Builder(VrmlModel(root, tree^), resource_path)
    var roots = builder.model.tree.roots.copy()
    # The grammar gives one root at least. The loop always runs.
    for node in roots:  # pragma: no branch
        var result = builder.build(node, scene, assets)
        ref name = builder.model.tree.nodes[node].name
        if _is_object(name):
            scene.add(builder.model.objects[result].node, parent=root)
        if name == "WorldInfo":
            builder.model.has_world_info = True
            builder.model.title = builder.titles[result]
            builder.model.info = builder.infos[result].copy()
    var model = builder^.result()
    # A texture's transform is its last appearance's, as three.js's
    # appearances share the texture.
    for texture in model.textures:
        if texture.id != NO_TEXTURE:
            ref image = assets.textures.textures[texture.id.value]
            image.center = texture.center
            image.rotation = Angle(Float32(texture.rotation), RADIAN)
            image.repeat = texture.repeat
            image.offset = texture.offset
    return model^


def parse_vrml(
    text: String,
    mut scene: Scene,
    mut assets: Assets,
    resource_path: String = "",
    parent: NodeId = NO_PARENT,
) raises -> VrmlModel:
    """Read the text of a VRML 2.0 file, three.js's `VRMLLoader.parse`.

    Args:
        text: The whole file.
        scene: The scene to add the nodes to.
        assets: Where the geometries, materials and textures go.
        resource_path: The directory an `ImageTexture`'s file is in.
        parent: The node to put the root under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: If the text has no `#VRML V2.0`, and for anything
            `parse_vrml_text` or `vrml_scene` refuses.
    """
    if text.find("#VRML V2.0") < 0:
        raise Error("VRML: only version 2.0 is read")
    return vrml_scene(
        parse_vrml_text(text), scene, assets, resource_path, parent
    )


def read_vrml(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> VrmlModel:
    """Read a `.wrl` file. An `ImageTexture` is read from the file's
    directory.

    Args:
        path: The file.
        scene: The scene to add the nodes to.
        assets: Where the geometries, materials and textures go.
        parent: The node to put the root under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: If the file cannot be read, and for anything `parse_vrml`
            refuses.
    """
    var slash = path.rfind("/")
    var directory = String(path[byte = : slash + 1])
    return parse_vrml(Path(path).read_text(), scene, assets, directory, parent)
