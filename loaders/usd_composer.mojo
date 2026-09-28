# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene composed from USD layers, from three.js r186's
`examples/jsm/loaders/usd/USDComposer.js`.

`compose_usd` builds a layer into a scene, as three.js's `compose` builds
it into a `Group`. It is what `loaders.usd` calls for each file it reads.

**The hierarchy.** Each prim under `/` becomes a node under its parent,
in the order of the layer's paths. A `Mesh` is a mesh; a `Cube`, a
`Sphere`, a `Cylinder`, a `Cone` and a `Capsule` are meshes of three.js's
geometries; a `Material`, a `Shader`, a `GeomSubset` and a
`SkelAnimation` are not nodes; and any other prim is a node. The children
of the selected variant of each variant set are children too. A variant
is selected by the file that references the layer, then by the prim's
`variants`, then as the set's first.

**The transforms.** `xformOpOrder` lists the prim's operations, applied
in order: `xformOp:transform`, `xformOp:translate`,
`xformOp:translate:pivot`, `xformOp:scale`, `xformOp:rotateXYZ`,
`xformOp:rotateX`, `xformOp:rotateY`, `xformOp:rotateZ` and
`xformOp:orient`, and each of them inverted by `!invert!`. A prim with no
order has its translation, scale, rotation and orientation set
separately. The root layer's `metersPerUnit` scales the scene, and an
`upAxis` of `Z` turns it to Y up.

**References.** A prim's `prepend references` or `payload` names a layer
of the archive, and a prim in it. That layer is composed on its own, and
what it holds becomes the prim's children. When it holds one mesh, the
mesh takes the prim's place, as a `USDZExporter` file expects.

**Materials.** A mesh's material is bound by `material:binding`, on the
mesh, on a variant, or on a parent that is `strongerThanDescendants`. A
`UsdPreviewSurface` gives a physical material: its color, emissive
color, normal map, roughness, metalness, occlusion, index of refraction,
specular color, clear coat and opacity, each from a value or a
`UsdUVTexture`. A texture has the wrap its shader names, the placement of
a `UsdTransform2d`, and the second set of texture coordinates when its
primvar reader reads `st1`. A mesh with `GeomSubset`s has a material for
each subset.

**Textures.** A texture's file is found in the archive, by its path, then
by its path as written, then by its last part. A file read from a folder
finds a texture that is not in the archive on the disk beside it. A
texture whose image cannot be found or read is one black texel, as a
three.js texture with no image draws, and `UsdModel.missing_textures`
names it.

**Where three.js's quirks are kept.** A mesh with no binding wears the
first material under the root's `Looks` or `Materials`. A mesh with a
white material wears its `displayColor`. A diffuse color is read as sRGB,
so a color that `USDZExporter` wrote in linear reads back darker. Two maps
that share a texture share its color space, the last one set.

**What is refused.** Where three.js throws: a transform operation that is
not numbers, and a texture scale that is not a list. And where this port
holds less than three.js: an array attribute that is not an array, a
material value that is not a number, a color outside zero to one, a
texture that reads `st2`, which the port has no set of coordinates for,
and references that nest more than 64 deep.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import GROUP_TYPE, NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.box import box
from geometries.capsule import capsule
from geometries.cylinder import cone, cylinder
from geometries.sphere import sphere
from loaders.gltf import decode_image
from loaders.js_number import js_number_text
from loaders.model_nodes import authored_color, decompose_onto
from loaders.three_mf import js_key_order
from loaders.usd_geometry import (
    UsdArray,
    UsdMeshArrays,
    build_usd_geometry,
    build_usd_geometry_with_subsets,
)
from loaders.usd_specs import (
    NO_VALUE,
    SPEC_ATTRIBUTE,
    SPEC_PRIM,
    SPEC_RELATIONSHIP,
    USD_OBJECT,
    USD_SAMPLES,
    USD_STRINGS,
    UsdLayer,
    UsdSpec,
)
from materials.material import Material, MaterialId, physical_material
from math.euler import XYZ, ZYX, Euler
from math.matrix4 import (
    Matrix4,
    rotation_from_euler,
    rotation_from_quaternion,
    rotation_x,
    rotation_y,
    rotation_z,
    scaling,
    translation,
)
from math.quaternion import Quaternion
from math.vector2 import Vector2
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    IGNORED,
    MIRROR,
    NEAREST,
    REPEAT,
    Texture,
    UV_CHANNEL_0,
    UV_CHANNEL_1,
    UvChannel,
    Wrap,
)
from render.texture_store import NO_TEXTURE, TextureId
from std.math import nan, pi
from std.pathlib import Path
from units.si import DEGREE, METER, RADIAN, Angle, Length

# How deep references may nest before the composer refuses them.
comptime MAX_REFERENCE_DEPTH = 64
# The white of a new physical material.
comptime _WHITE = Color(255, 255, 255)


@fieldwise_init
struct UsdAssetKind(Equatable, ImplicitlyCopyable, Writable):
    """What a file of a USDZ archive is to the composer, as a type rather
    than a bare int: an image's bytes or a parsed layer, as three.js's
    `parseAssets` keeps them.

    `UsdAssets.add` refuses a kind that `is_valid` does not accept.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for `USD_IMAGE` and `USD_LAYER`."""
        return self == USD_IMAGE or self == USD_LAYER


# A PNG, a JPEG or an AVIF file.
comptime USD_IMAGE = UsdAssetKind(0)
# A `.usd`, `.usda` or `.usdc` layer.
comptime USD_LAYER = UsdAssetKind(1)


struct UsdAssets(Movable):
    """The counterpart of three.js's `assets`: each image and layer of an archive by its
    name, in JavaScript's key order."""

    var names: List[String]
    var kinds: List[UsdAssetKind]
    var images: List[List[UInt8]]
    var layers: List[UsdLayer]

    def __init__(out self):
        """Make an empty set."""
        self.names = List[String]()
        self.kinds = List[UsdAssetKind]()
        self.images = List[List[UInt8]]()
        self.layers = List[UsdLayer]()

    def add(
        mut self,
        name: String,
        kind: UsdAssetKind,
        var image: List[UInt8],
        var layer: UsdLayer,
    ) raises:
        """Add a file, replacing one of the same name in its place, as
        `data[ filename ] = ...` does.

        Args:
            name: Its name in the archive.
            kind: What it is.
            image: An image's bytes, empty for a layer.
            layer: A layer, empty for an image.

        Raises:
            Error: If the kind is not valid.
        """
        if not kind.is_valid():
            raise Error("USD: an asset of no kind: " + String(kind.value))
        var at = self.find(name)
        if at >= 0:
            self.kinds[at] = kind
            self.images[at] = image^
            self.layers[at] = layer^
            return
        self.names.append(name)
        self.kinds.append(kind)
        self.images.append(image^)
        self.layers.append(layer^)

    def find(self, name: String) -> Int:
        """Return where a file is.

        Args:
            name: Its name.

        Returns:
            Its place, or -1.
        """
        for k in range(len(self.names)):
            if self.names[k] == name:
                return k
        return -1

    def order(self) -> List[Int]:
        """Return the files' places in JavaScript's key order.

        Returns:
            The places.
        """
        var out = List[Int]()
        for name in js_key_order(self.names):
            out.append(self.find(name))
        return out^


@fieldwise_init
struct UsdObject(Copyable, Movable):
    """A node `compose_usd` added: a mesh, or a node with nothing to draw,
    as three.js adds a `Mesh`, an `Object3D` or a `Group`."""

    var node: NodeId
    # The place of its parent in `UsdModel.objects`, -1 for the root.
    var parent: Int
    var is_mesh: Bool
    # A mesh's geometry and materials; unset for a node.
    var geometry: GeometryId
    var materials: List[MaterialId]
    # Whether three.js gives the mesh a list of materials, one a subset.
    var material_list: Bool


@fieldwise_init
struct UsdTexture(Copyable, Movable):
    """A texture a material wears, and what three.js keeps beside it."""

    var id: TextureId
    # Its file: the name in the archive, or the path on the disk.
    var source: String
    var in_archive: Bool
    # Whether its image was found and read.
    var loaded: Bool
    # The `UsdUVTexture`'s `inputs:scale` and `inputs:bias`, three.js's
    # `userData.scale` and `userData.bias`, when it has them.
    var scale: Optional[List[Float64]]
    var bias: Optional[List[Float64]]


struct UsdModel(Movable):
    """What `compose_usd` added: the root, three.js's `Group`, first, and
    each node under it, depth first."""

    var root: NodeId
    var objects: List[UsdObject]
    var textures: List[UsdTexture]
    # The file of each texture whose image was not found or not read.
    var missing_textures: List[String]

    def __init__(out self, root: NodeId):
        """Start with a root and nothing under it.

        Args:
            root: The root node.
        """
        self.root = root
        self.objects = List[UsdObject]()
        self.textures = List[UsdTexture]()
        self.missing_textures = List[String]()


struct _Object(Copyable, Movable):
    """A node while the scene is built: three.js's object, before it goes
    into the `Scene`."""

    var node: Object3D
    var is_mesh: Bool
    var children: List[Int]
    var parent: Int
    var geometry: Int
    var materials: List[Int]
    var material_list: Bool

    def __init__(out self, name: String):
        """Make a node with nothing to draw.

        Args:
            name: Its name.
        """
        self.node = Object3D()
        self.node.name = name
        self.is_mesh = False
        self.children = List[Int]()
        self.parent = -1
        self.geometry = -1
        self.materials = List[Int]()
        self.material_list = False


struct _Image(Copyable, Movable):
    """A texture while the scene is built: its image and settings."""

    var source: String
    var in_archive: Bool
    var loaded: Bool
    var width: Int
    var height: Int
    var pixels: List[UInt8]
    var wrap_s: Wrap
    var wrap_t: Wrap
    var repeat: Vector2
    var offset: Vector2
    var rotation: Angle
    var channel: UvChannel
    var space: ColorSpace
    var scale: Optional[List[Float64]]
    var bias: Optional[List[Float64]]

    def __init__(out self, source: String, in_archive: Bool):
        """Make a texture with no image and three.js's defaults.

        Args:
            source: Its file.
            in_archive: Whether the file is in the archive.
        """
        self.source = source
        self.in_archive = in_archive
        self.loaded = False
        self.width = 1
        self.height = 1
        self.pixels = [0, 0, 0, 255]
        self.wrap_s = CLAMP
        self.wrap_t = CLAMP
        self.repeat = Vector2(1, 1)
        self.offset = Vector2(0, 0)
        self.rotation = Angle(0.0, RADIAN)
        self.channel = UV_CHANNEL_0
        self.space = LINEAR
        self.scale = None
        self.bias = None


struct _Built(Movable):
    """Everything the composers of a file and of its references build."""

    var objects: List[_Object]
    var geometries: List[BufferGeometry]
    var materials: List[Material]
    var images: List[_Image]

    def __init__(out self):
        """Start with nothing."""
        self.objects = List[_Object]()
        self.geometries = List[BufferGeometry]()
        self.materials = List[Material]()
        self.images = List[_Image]()

    def add(mut self, var item: _Object) -> Int:
        """Add a node.

        Args:
            item: The node.

        Returns:
            Its place.
        """
        self.objects.append(item^)
        return len(self.objects) - 1

    def attach(mut self, parent: Int, child: Int):
        """Put a node under another, three.js's `add`: it leaves its old
        parent.

        Args:
            parent: The new parent.
            child: The node.
        """
        self.detach(child)
        self.objects[parent].children.append(child)
        self.objects[child].parent = parent

    def detach(mut self, child: Int):
        """Take a node from its parent, three.js's `remove`.

        Args:
            child: The node.
        """
        var parent = self.objects[child].parent
        if parent < 0:
            return
        ref children = self.objects[parent].children
        for k in range(len(children)):  # pragma: no branch
            if children[k] == child:
                _ = children.pop(k)
                break
        self.objects[child].parent = -1

    def new_material(mut self) raises -> Int:
        """Add three.js's `new MeshPhysicalMaterial()`.

        Returns:
            Its place.

        Raises:
            Error: If the material cannot be made.
        """
        self.materials.append(physical_material(_WHITE))
        return len(self.materials) - 1


struct _Attrs(Copyable, Movable):
    """The object `_getAttributes` gives: each attribute's value by its
    name, in the order first set."""

    var names: List[String]
    var values: List[Int]
    var index: Dict[String, Int]

    def __init__(out self):
        """Make an empty set."""
        self.names = List[String]()
        self.values = List[Int]()
        self.index = Dict[String, Int]()

    def get(self, name: String) -> Int:
        """Return `attrs[ name ]`.

        Args:
            name: The attribute.

        Returns:
            The place of its value, or `NO_VALUE`.
        """
        var found = self.index.get(name)
        return self.values[found.value()] if found else NO_VALUE

    def has(self, name: String) -> Bool:
        """Return `name in attrs`.

        Args:
            name: The attribute.

        Returns:
            Whether it is set.
        """
        return Bool(self.index.get(name))

    def set(mut self, name: String, value: Int):
        """Set an attribute, keeping its place when it is there.

        Args:
            name: The attribute.
            value: The place of its value.
        """
        var found = self.index.get(name)
        if Bool(found):
            self.values[found.value()] = value
            return
        self.index[name] = len(self.names)
        self.names.append(name)
        self.values.append(value)


struct _Index(Movable):
    """A map from a path to a list of strings, in the order added."""

    var keys: Dict[String, Int]
    var lists: List[List[String]]

    def __init__(out self):
        """Make an empty map."""
        self.keys = Dict[String, Int]()
        self.lists = List[List[String]]()

    def add(mut self, key: String, value: String):
        """Add a string to a path's list.

        Args:
            key: The path.
            value: The string.
        """
        var found = self.keys.get(key)
        if found:
            self.lists[found.value()].append(value)
            return
        self.keys[key] = len(self.lists)
        self.lists.append([value])

    def get(self, key: String) -> List[String]:
        """Return a path's list.

        Args:
            key: The path.

        Returns:
            The list, empty when there is none.
        """
        var found = self.keys.get(key)
        if found:
            return self.lists[found.value()].copy()
        return List[String]()


struct _Subset(Copyable, Movable):
    """A `GeomSubset` as `_getGeomSubsets` gives it."""

    var indices: List[Float64]
    var material: String

    def __init__(out self, var indices: List[Float64], material: String):
        """Make a subset.

        Args:
            indices: Its faces.
            material: Its material's path, empty when it has none.
        """
        self.indices = indices^
        self.material = material


def _last_part(path: String) -> String:
    """Return `path.split( '/' ).pop()`.

    Args:
        path: The path.

    Returns:
        The text after the last `/`.
    """
    return String(path[byte = path.rfind("/") + 1 :])


def _split(path: String) -> List[String]:
    """Return `path.split( '/' )`.

    Args:
        path: The path.

    Returns:
        Its parts, an empty one before a leading `/`.
    """
    var out = List[String]()
    for part in path.split("/"):
        out.append(String(part))
    return out^


def _before(text: String, byte: String) -> String:
    """Return `text.split( byte )[ 0 ]`.

    Args:
        text: The text.
        byte: The separator.

    Returns:
        The text before the first separator.
    """
    var at = text.find(byte)
    return text if at < 0 else String(text[byte=:at])


def _no_angles(text: String) -> String:
    """Return `text.replace( /<|>/g, '' )`.

    Args:
        text: The text.

    Returns:
        The text less each `<` and `>`.
    """
    return text.replace("<", "").replace(">", "")


def _is_word(byte: UInt8) -> Bool:
    """Return True for a byte that `\\w` matches.

    Args:
        byte: The byte.

    Returns:
        Whether it is a letter, a digit or `_`.
    """
    return (
        (byte >= 0x30 and byte <= 0x39)
        or (byte >= 0x41 and byte <= 0x5A)
        or (byte >= 0x61 and byte <= 0x7A)
        or byte == 0x5F
    )


def variant_path_match(path: String) -> Optional[Tuple[String, String]]:
    """Match three.js's `VARIANT_PATH_REGEX`,
    `^(.+?)\\/\\{(\\w+)=(\\w+)\\}\\/(.+)$`: a path inside a variant.

    Args:
        path: The path.

    Returns:
        The path before the first variant and the path after it, or
        nothing.
    """
    var bytes = path.as_bytes()
    var n = len(bytes)
    for i in range(1, n):
        if bytes[i] != 0x2F or i + 1 >= n or bytes[i + 1] != 0x7B:
            continue
        var at = i + 2
        var first = at
        while at < n and _is_word(bytes[at]):
            at += 1
        if at == first or at >= n or bytes[at] != 0x3D:
            continue
        at += 1
        var second = at
        while at < n and _is_word(bytes[at]):
            at += 1
        var closes = at + 1 < n and bytes[at] == 0x7D and bytes[at + 1] == 0x2F
        if at == second or not closes or at + 2 >= n:
            continue
        return (String(path[byte=:i]), String(path[byte = at + 2 :]))
    return None


def reference_matches(text: String) -> List[Tuple[String, String, String]]:
    """Find each match of `@([^@]+)@(?:<([^>]+)>)?`, as `matchAll` does.

    Args:
        text: The text.

    Returns:
        For each match, its whole text, its file, and its prim path or
        the empty string.
    """
    var bytes = text.as_bytes()
    var n = len(bytes)
    var out = List[Tuple[String, String, String]]()
    var i = 0
    while i < n:
        if bytes[i] != 0x40:
            i += 1
            continue
        var close = i + 1
        while close < n and bytes[close] != 0x40:
            close += 1
        if close >= n or close == i + 1:
            i += 1
            continue
        var end = close + 1
        var prim = String("")
        if end < n and bytes[end] == 0x3C:
            var stop = end + 1
            while stop < n and bytes[stop] != 0x3E:
                stop += 1
            if stop < n and stop > end + 1:
                prim = String(text[byte = end + 1 : stop])
                end = stop + 1
        out.append(
            (
                String(text[byte=i:end]),
                String(text[byte = i + 1 : close]),
                prim,
            )
        )
        i = end
    return out^


def resolve_url(url: String, path: String) -> String:
    """Resolve a URL against a folder, three.js's
    `LoaderUtils.resolveURL`.

    Args:
        url: The URL.
        path: The folder, ending with `/`.

    Returns:
        The empty string for no URL; the URL itself when it is absolute,
        a data URI or a blob URL; and the folder and the URL joined
        otherwise, the folder cut to its host for a URL that starts with
        `/`.
    """
    if url == "":
        return ""
    var base = path
    var lower_path = path.lower()
    var http = lower_path.startswith("http://") or lower_path.startswith(
        "https://"
    )
    if http and url.startswith("/"):
        var host_start = path.find("//") + 2
        var host_end = path.find("/", host_start)
        base = path if host_end < 0 else String(path[byte=:host_end])
    var lower = url.lower()
    var absolute = (
        lower.startswith("//")
        or lower.startswith("http://")
        or lower.startswith("https://")
    )
    if absolute:
        return url
    if lower.startswith("data:") and url.find(",") >= 0:
        return url
    if lower.startswith("blob:"):
        return url
    return base + url


def _wrap_of(value: String) -> Wrap:
    """Return three.js's `_getWrapMode`.

    Args:
        value: The `inputs:wrapS` or `inputs:wrapT` token.

    Returns:
        `REPEAT` for `repeat` and any unknown token, `MIRROR` for
        `mirror`, and `CLAMP` for `clamp`.
    """
    if value == "mirror":
        return MIRROR
    if value == "clamp":
        return CLAMP
    return REPEAT


struct _Composer(Movable):
    """The counterpart of three.js's `USDComposer` as it composes one layer."""

    var layer: UsdLayer
    var base_path: String
    # The variant selections of the file that references this layer.
    var variant_sets: List[String]
    var variant_choices: List[String]
    var depth: Int
    var cache_keys: List[String]
    var cache_images: List[Int]
    var children: _Index
    var attribute_names: Dict[String, Int]
    var attribute_lists: List[List[String]]
    var materials_by_root: _Index
    var shaders_by_material: _Index
    var subsets_by_mesh: _Index

    def __init__(
        out self,
        var layer: UsdLayer,
        base_path: String,
        var variant_sets: List[String],
        var variant_choices: List[String],
        depth: Int,
    ):
        """Start composing a layer.

        Args:
            layer: The layer.
            base_path: The folder its files are found in.
            variant_sets: The variant sets the referencing file selects.
            variant_choices: The variant each selects.
            depth: How deep in references this layer is.
        """
        self.layer = layer^
        self.base_path = base_path
        self.variant_sets = variant_sets^
        self.variant_choices = variant_choices^
        self.depth = depth
        self.cache_keys = List[String]()
        self.cache_images = List[Int]()
        self.children = _Index()
        self.attribute_names = Dict[String, Int]()
        self.attribute_lists = List[List[String]]()
        self.materials_by_root = _Index()
        self.shaders_by_material = _Index()
        self.subsets_by_mesh = _Index()

    def type_name(self, spec: Int) -> String:
        """Return a prim's `typeName`, as the composer compares it.

        Args:
            spec: The prim's spec.

        Returns:
            Its type, the empty string when it has none, and a text no
            type has when it is not a string.
        """
        var id = self.layer.specs[spec].field("typeName")
        if self.layer.is_string(id):
            return self.layer.text(id)
        return "" if not self.layer.truthy(id) else "\x00"

    def string_field(self, path: String, name: String) -> String:
        """Return a string field of a spec.

        Args:
            path: The spec's path.
            name: The field.

        Returns:
            Its text, or the empty string when it is not a string.
        """
        var id = self.layer.field(path, name)
        return self.layer.text(id) if self.layer.is_string(id) else ""

    def build_indexes(mut self):
        """Index the layer's prims and properties, three.js's
        `_buildIndexes`."""
        for k in range(len(self.layer.paths)):
            var path = self.layer.paths[k]
            var spec_type = self.layer.specs[k].spec_type
            if spec_type == SPEC_PRIM:
                self.index_prim(k, path)
            elif spec_type == SPEC_ATTRIBUTE or spec_type == SPEC_RELATIONSHIP:
                var dot = path.rfind(".")
                if dot > 0:
                    var prim = String(path[byte=:dot])
                    var name = String(path[byte = dot + 1 :])
                    var found = self.attribute_names.get(prim)
                    if found:
                        self.attribute_lists[found.value()].append(name)
                    else:
                        self.attribute_names[prim] = len(self.attribute_lists)
                        self.attribute_lists.append([name])

    def index_prim(mut self, spec: Int, path: String):
        """Index one prim: under its parent, and as a material, a shader
        or a subset.

        Args:
            spec: The prim's spec.
            path: Its path.
        """
        var slash = path.rfind("/")
        if slash > 0:
            self.children.add(String(path[byte=:slash]), path)
        elif slash == 0 and path.byte_length() > 1:
            self.children.add("/", path)
        var type_name = self.type_name(spec)
        if type_name == "Material":
            var parts = _split(path)
            var root = "/" + parts[1] if len(parts) > 1 else String("/")
            self.materials_by_root.add(root, path)
        if type_name == "Shader" and slash > 0:
            var ancestor = String(path[byte=:slash])
            # The walk ends at a material or at the top.
            while ancestor.byte_length() > 0:  # pragma: no branch
                var at = self.layer.spec(ancestor)
                var is_material = (
                    at >= 0
                    and self.layer.specs[at].spec_type == SPEC_PRIM
                    and self.type_name(at) == "Material"
                )
                if is_material:
                    self.shaders_by_material.add(ancestor, path)
                    break
                var up = ancestor.rfind("/")
                if up <= 0:
                    break
                var cut = String(ancestor[byte=:up])
                ancestor = cut
        if type_name == "GeomSubset" and slash > 0:
            self.subsets_by_mesh.add(String(path[byte=:slash]), path)

    def variant_choice(self, set_name: String) -> String:
        """Return the referencing file's selection for a variant set.

        Args:
            set_name: The variant set.

        Returns:
            The variant, or the empty string.
        """
        for k in range(len(self.variant_sets)):
            if self.variant_sets[k] == set_name:
                return self.variant_choices[k]
        return ""

    def variant_paths(self, parent: String) raises -> List[String]:
        """Return the paths of a prim's selected variants, three.js's
        `_getVariantPaths`.

        Args:
            parent: The prim's path.

        Returns:
            `parent/{set=variant}` for each variant set that has a
            selection.

        Raises:
            Error: If `variantSetChildren` is not a list of names.
        """
        var out = List[String]()
        var sets = self.layer.field(parent, "variantSetChildren")
        if not self.layer.truthy(sets):
            return out^
        if self.layer.kind(sets) != USD_STRINGS:
            raise Error("USD: variantSetChildren that is not a list of names")
        var selections = self.layer.field(parent, "variantSelection")
        for set_name in self.layer.values[sets].strings.copy():
            var chosen = self.variant_choice(set_name)
            if chosen == "" and self.layer.truthy(selections):
                var id = self.layer.object_value(selections, set_name)
                if self.layer.is_string(id):
                    chosen = self.layer.text(id)
            if chosen == "":
                var children = self.layer.field(
                    parent + "/{" + set_name + "=}", "variantChildren"
                )
                var first = self.layer.element_string(children, 0)
                if first:
                    chosen = first.value()
            if chosen != "":
                out.append(parent + "/{" + set_name + "=" + chosen + "}")
        return out^

    def resolve_value(self, path: String, visited: List[String]) -> Int:
        """Return an attribute's value, following its connections first,
        three.js's `_resolveAttributeValue`.

        Args:
            path: The attribute's path.
            visited: The paths already followed.

        Returns:
            The first connection's value that is there, or the default, or
            the sample at time zero or the first sample; or `NO_VALUE`.
        """
        var clean = _no_angles(path)
        if clean in visited:
            return NO_VALUE
        var at = self.layer.spec(clean)
        if at < 0:
            return NO_VALUE
        var next = visited.copy()
        next.append(clean)
        var connections = self.layer.specs[at].field("connectionPaths")
        if self.layer.truthy(connections):
            for k in range(self.layer.length(connections)):
                var target = self.layer.element_string(connections, k)
                if Bool(target):
                    var value = self.resolve_value(target.value(), next)
                    if self.layer.defined(value):
                        return value
        var value = self.layer.specs[at].field("default")
        if self.layer.defined(value):
            return value
        var samples = self.layer.specs[at].field("timeSamples")
        var has_samples = (
            self.layer.kind(samples) == USD_SAMPLES
            and len(self.layer.values[samples].numbers) > 0
        )
        if has_samples:
            ref times = self.layer.values[samples].numbers
            var chosen = 0
            for k in range(len(times)):  # pragma: no branch
                if times[k] == 0:
                    chosen = k
                    break
            if chosen < len(self.layer.values[samples].items):
                return self.layer.values[samples].items[chosen]
        return NO_VALUE

    def collect(self, path: String, mut attrs: _Attrs):
        """Add a prim's attributes to a set, three.js's
        `_collectAttributesFromPath`.

        Args:
            path: The prim's path.
            attrs: The set.
        """
        var found = self.attribute_names.get(path)
        if not found:
            return
        for name in self.attribute_lists[found.value()]:  # pragma: no branch
            var full = path + "." + name
            var value = self.resolve_value(full, List[String]())
            if self.layer.defined(value):
                attrs.set(name, value)
            var size = self.layer.field(full, "elementSize")
            if self.layer.defined(size):
                attrs.set(name + ":elementSize", size)
            var type_name = self.layer.field(full, "typeName")
            if name.startswith("primvars:") and self.layer.defined(type_name):
                attrs.set(name + ":typeName", type_name)

    def attributes(self, path: String) raises -> _Attrs:
        """Return a prim's attributes with the overrides of the selected
        variants, three.js's `_getAttributes`.

        Args:
            path: The prim's path.

        Returns:
            Each attribute's value by its name.

        Raises:
            Error: If a variant set is not a list of names.
        """
        var attrs = _Attrs()
        self.collect(path, attrs)
        var inside = variant_path_match(path)
        if inside:
            var base = inside.value()[0]
            var relative = inside.value()[1]
            for variant in self.variant_paths(base):
                if path.startswith(variant):
                    continue
                self.collect(variant + "/" + relative, attrs)
            return attrs^
        var parts = _split(path)
        for i in range(1, len(parts) - 1):
            var ancestor = String("/").join(parts[: i + 1])
            var relative = String("/").join(parts[i + 1 :])
            for variant in self.variant_paths(ancestor):
                self.collect(variant + "/" + relative, attrs)
        return attrs^

    def resolve_file(self, reference: String) -> String:
        """Resolve a file against this layer's folder, three.js's
        `_resolveFilePath`.

        Args:
            reference: The file, as the layer writes it.

        Returns:
            Its path in the archive or on the disk.
        """
        var clean = reference
        if clean.startswith("./"):
            var cut = String(clean[byte=2:])
            clean = cut
        if self.base_path == "":
            return clean
        var base = self.base_path
        if not base.endswith("/"):
            base += "/"
        return resolve_url(clean, base)

    def references(self, spec: Int) -> List[String]:
        """Return a prim's references, or its payload, three.js's
        `_getReferences`.

        Args:
            spec: The prim's spec.

        Returns:
            Each `@file@<prim>` it names.
        """
        var out = List[String]()
        var references = self.layer.specs[spec].field("references")
        if self.layer.truthy(references) and self.layer.length(references) > 0:
            var first = self.layer.element_string(references, 0)
            if first:
                for found in reference_matches(first.value()):
                    out.append(found[0])
        var payload = self.layer.specs[spec].field("payload")
        if len(out) == 0 and self.layer.is_string(payload):
            if self.layer.truthy(payload):
                out.append(self.layer.text(payload))
        return out^

    def local_variants(self, spec: Int) -> Tuple[List[String], List[String]]:
        """Return a prim's `variantSelection`, three.js's
        `_getLocalVariantSelections`.

        Args:
            spec: The prim's spec.

        Returns:
            The variant sets and the variant each selects.
        """
        var sets = List[String]()
        var choices = List[String]()
        var selection = self.layer.specs[spec].field("variantSelection")
        if self.layer.kind(selection) == USD_OBJECT:
            ref value = self.layer.values[selection]
            for k in range(len(value.strings)):
                var chosen = value.items[k]
                sets.append(value.strings[k])
                choices.append(
                    self.layer.text(chosen) if self.layer.is_string(
                        chosen
                    ) else ""
                )
        return (sets^, choices^)

    def resolve_reference(
        self,
        reference: String,
        var sets: List[String],
        var choices: List[String],
        assets: UsdAssets,
        mut built: _Built,
    ) raises -> Int:
        """Compose a referenced layer, three.js's `_resolveReference`.

        Args:
            reference: The `@file@<prim>` text.
            sets: The prim's own variant sets.
            choices: The variant each selects.
            assets: The archive's files.
            built: What is being built.

        Returns:
            A group of what the layer holds, or of its named prim alone; or
            -1 when the file is not a layer of the archive.

        Raises:
            Error: If references nest past `MAX_REFERENCE_DEPTH`, or the
                layer refuses to compose.
        """
        var found = reference_matches(reference)
        if len(found) == 0:
            return -1
        var file = self.resolve_file(found[0][1])
        var prim = found[0][2]
        # The referencing file's selections win over the prim's own.
        for k in range(len(self.variant_sets)):
            var at = -1
            for j in range(len(sets)):
                if sets[j] == self.variant_sets[k]:
                    at = j
            if at >= 0:
                choices[at] = self.variant_choices[k]
            else:
                sets.append(self.variant_sets[k])
                choices.append(self.variant_choices[k])
        var asset = assets.find(file)
        if asset < 0 or assets.kinds[asset] != USD_LAYER:
            return -1
        if self.depth >= MAX_REFERENCE_DEPTH:
            raise Error("USD: references nest more than 64 deep")
        var slash = file.rfind("/")
        var base = String(file[byte=:slash]) if slash >= 0 else String("")
        var composer = _Composer(
            assets.layers[asset].copy(), base, sets^, choices^, self.depth + 1
        )
        var group = composer.compose(assets, built)
        if prim == "":
            return group
        var name = _last_part(prim)
        for child in built.objects[group].children.copy():
            if built.objects[child].node.name == name:
                var wrapper = _Object("")
                wrapper.node.object_type = GROUP_TYPE
                var at = built.add(wrapper^)
                built.attach(at, child)
                return at
        return group

    def single_mesh(self, group: Int, mut built: _Built) raises -> Int:
        """Take the one mesh of a referenced group, three.js's
        `_findSingleMesh`: a mesh among its children, or the only
        grandchild of its only child when that child is not moved.

        Args:
            group: The group.
            built: What is being built.

        Returns:
            The mesh, now without a parent, or -1.

        Raises:
            Error: If a rotation cannot be read.
        """
        for child in built.objects[group].children.copy():
            if built.objects[child].is_mesh:
                built.detach(child)
                return child
        if len(built.objects[group].children) != 1:
            return -1
        var child = built.objects[group].children[0]
        if len(built.objects[child].children) != 1:
            return -1
        var grandchild = built.objects[child].children[0]
        if built.objects[grandchild].is_mesh and not moved(
            built.objects[child].node
        ):
            built.detach(grandchild)
            return grandchild
        return -1

    def compose(mut self, assets: UsdAssets, mut built: _Built) raises -> Int:
        """Compose the layer into a group, three.js's `compose`.

        Args:
            assets: The archive's files.
            built: What is being built.

        Returns:
            The group.

        Raises:
            Error: For anything the module docstring lists.
        """
        self.build_indexes()
        var root = _Object("")
        root.node.object_type = GROUP_TYPE
        var group = built.add(root^)
        self.build_hierarchy(group, "/", assets, built)
        var meters = self.layer.field("/", "metersPerUnit")
        if self.layer.defined(meters):
            if not self.layer.is_number(meters):
                raise Error("USD: metersPerUnit that is not a number")
            var scale = Float32(self.layer.number(meters))
            if self.layer.number(meters) != 1:
                built.objects[group].node.set_scale(scale, scale, scale)
        if self.string_field("/", "upAxis") == "Z":
            built.objects[group].node.set_euler(
                Angle(Float32(-pi / 2), RADIAN),
                Angle(0.0, RADIAN),
                Angle(0.0, RADIAN),
            )
        return group

    def build_hierarchy(
        mut self,
        parent: Int,
        parent_path: String,
        assets: UsdAssets,
        mut built: _Built,
    ) raises:
        """Build the prims under a path, three.js's `_buildHierarchy`.

        Args:
            parent: The node they go under.
            parent_path: The path.
            assets: The archive's files.
            built: What is being built.

        Raises:
            Error: For anything the module docstring lists.
        """
        var entries = self.children.get(parent_path)
        for variant in self.variant_paths(parent_path):
            # A variant's paths hold its `{set=choice}`, so none is a direct
            # child's.
            entries.extend(self.children.get(variant))
        # The index holds only prims.
        for path in entries:
            var spec = self.layer.spec(path)
            var name = _last_part(path)
            var type_name = self.type_name(spec)
            if self.build_references(
                parent, path, spec, type_name, assets, built
            ):
                continue
            if type_name == "Skeleton":
                # The skeleton is not built; its children still are.
                self.build_hierarchy(parent, path, assets, built)
                continue
            var skipped = (
                type_name == "SkelAnimation"
                or type_name == "Material"
                or type_name == "Shader"
                or type_name == "GeomSubset"
            )
            if skipped:
                continue
            var object: Int
            if type_name == "Mesh":
                object = self.build_mesh(path, spec, assets, built)
            elif _is_primitive(type_name):
                object = self.build_primitive(
                    path, spec, type_name, assets, built
                )
            else:
                object = built.add(_Object(name))
                if type_name == "SkelRoot":
                    built.objects[object].node.user_data.set_boolean(
                        "isSkelRoot", True
                    )
                var attrs = self.attributes(path)
                self.apply_transform(object, spec, attrs, built)
            built.attach(parent, object)
            self.build_hierarchy(object, path, assets, built)

    def build_references(
        mut self,
        parent: Int,
        path: String,
        spec: Int,
        type_name: String,
        assets: UsdAssets,
        mut built: _Built,
    ) raises -> Bool:
        """Build a prim that references other layers, as
        `_buildHierarchy` does.

        Args:
            parent: The node it goes under.
            path: The prim's path.
            spec: Its spec.
            type_name: Its type.
            assets: The archive's files.
            built: What is being built.

        Returns:
            Whether it was built: False when no reference resolved.

        Raises:
            Error: For anything the module docstring lists.
        """
        var references = self.references(spec)
        if len(references) == 0:
            return False
        var local = self.local_variants(spec)
        var groups = List[Int]()
        for reference in references:  # pragma: no branch
            var group = self.resolve_reference(
                reference, local[0].copy(), local[1].copy(), assets, built
            )
            if group >= 0:
                groups.append(group)
        if len(groups) == 0:
            return False
        var attrs = self.attributes(path)
        if len(groups) == 1:
            var mesh = self.single_mesh(groups[0], built)
            if mesh >= 0 and (type_name == "Xform" or type_name == ""):
                built.objects[mesh].node.name = _last_part(path)
                self.apply_transform(mesh, spec, attrs, built)
                self.apply_material_binding(mesh, path, assets, built)
                built.attach(parent, mesh)
                self.build_hierarchy(mesh, path, assets, built)
                return True
        var object = built.add(_Object(_last_part(path)))
        self.apply_transform(object, spec, attrs, built)
        for group in groups:  # pragma: no branch
            for child in built.objects[group].children.copy():
                built.attach(object, child)
        built.attach(parent, object)
        self.build_hierarchy(object, path, assets, built)
        return True

    def data(self, name: String, spec: Int, attrs: _Attrs) -> Int:
        """Return `{ ...fields, ...attrs }[ name ]`.

        Args:
            name: The name.
            spec: The prim's spec.
            attrs: Its attributes.

        Returns:
            The attribute's value, or the field's.
        """
        if attrs.has(name):
            return attrs.get(name)
        return self.layer.specs[spec].field(name)

    def vector(self, id: Int, what: String) raises -> List[Float64]:
        """Return the three numbers of an operation's value.

        Args:
            id: The value.
            what: The operation, for the message.

        Returns:
            The numbers.

        Raises:
            Error: If the value is not a list of three numbers at least,
                where three.js would read `undefined`.
        """
        if not self.layer.is_array(id) or self.layer.length(id) < 3:
            raise Error("USD: " + what + " is not three numbers")
        return [
            self.layer.element_number(id, 0),
            self.layer.element_number(id, 1),
            self.layer.element_number(id, 2),
        ]

    def operation(
        self,
        op: String,
        spec: Int,
        attrs: _Attrs,
        mut scale: Optional[List[Float64]],
    ) raises -> Optional[Matrix4]:
        """Return one operation of `xformOpOrder` as a matrix.

        Args:
            op: The operation, without `!invert!`.
            spec: The prim's spec.
            attrs: Its attributes.
            scale: The last scale, set by a scale operation.

        Returns:
            The matrix, or nothing when the prim has no such value.

        Raises:
            Error: If the value is not the numbers the operation takes.
        """
        var value = self.data(op, spec, attrs)
        if op == "xformOp:transform":
            if not self.layer.truthy(value) or self.layer.length(value) != 16:
                return None
            var matrix = Matrix4()
            for k in range(16):  # pragma: no branch
                matrix.elements[k] = Float32(
                    self.layer.element_number(value, k)
                )
            return matrix
        if op == "xformOp:translate" or op == "xformOp:translate:pivot":
            if not self.layer.truthy(value):
                return None
            var t = self.vector(value, op)
            return translation(Float32(t[0]), Float32(t[1]), Float32(t[2]))
        if op == "xformOp:scale":
            if not self.layer.truthy(value):
                return None
            var s: List[Float64]
            if self.layer.is_array(value):
                s = [
                    self.layer.element_number(value, 0),
                    self.layer.element_number(value, 1),
                    self.layer.element_number(value, 2),
                ]
            else:
                var n = self.layer.to_number(value)
                s = [n, n, n]
            scale = s.copy()
            return scaling(Float32(s[0]), Float32(s[1]), Float32(s[2]))
        if op == "xformOp:rotateXYZ":
            if not self.layer.truthy(value):
                return None
            var r = self.vector(value, op)
            return rotation_from_euler(
                Euler(
                    Angle(Float32(r[0]), DEGREE),
                    Angle(Float32(r[1]), DEGREE),
                    Angle(Float32(r[2]), DEGREE),
                    ZYX,
                )
            )
        if (
            op == "xformOp:rotateX"
            or op == "xformOp:rotateY"
            or op == "xformOp:rotateZ"
        ):
            if not self.layer.defined(value):
                return None
            var angle = Angle(Float32(self.layer.to_number(value)), DEGREE)
            if op == "xformOp:rotateX":
                return rotation_x(angle)
            if op == "xformOp:rotateY":
                return rotation_y(angle)
            return rotation_z(angle)
        if op == "xformOp:orient":
            if not self.layer.truthy(value) or self.layer.length(value) != 4:
                return None
            return rotation_from_quaternion(self.quaternion(value))
        return None

    def quaternion(self, id: Int) -> Quaternion:
        """Return a four-number value as a quaternion, x, y, z then w.

        Args:
            id: The value.

        Returns:
            The quaternion, as given.
        """
        return Quaternion(
            Float32(self.layer.element_number(id, 0)),
            Float32(self.layer.element_number(id, 1)),
            Float32(self.layer.element_number(id, 2)),
            Float32(self.layer.element_number(id, 3)),
        )

    def apply_transform(
        self, object: Int, spec: Int, attrs: _Attrs, mut built: _Built
    ) raises:
        """Place a node by its prim's transform, three.js's
        `applyTransform`.

        Args:
            object: The node.
            spec: The prim's spec.
            attrs: Its attributes.
            built: What is being built.

        Raises:
            Error: If an operation's value is not the numbers it takes, or
                the matrix flattens an axis.
        """
        var order = self.data("xformOpOrder", spec, attrs)
        var ordered = self.layer.truthy(order) and self.layer.length(order) > 0
        if ordered:
            if self.layer.kind(order) != USD_STRINGS:
                raise Error("USD: an xformOpOrder that is not a list of names")
            var matrix = Matrix4()
            var scale: Optional[List[Float64]] = None
            for op in self.layer.values[
                order
            ].strings.copy():  # pragma: no branch
                var inverse = op.startswith("!invert!")
                var name = String(op[byte=8:]) if inverse else op
                var step = self.operation(name, spec, attrs, scale)
                if step:
                    var m = step.value()
                    if inverse:
                        m.invert()
                    matrix.multiply(m)
            ref node = built.objects[object].node
            decompose_onto(node, matrix, "USD")
            if Bool(scale):
                var s = scale.value().copy()
                if s[0] < 0 and s[1] < 0 and s[2] < 0:
                    node.set_scale(Float32(s[0]), Float32(s[1]), Float32(s[2]))
                    var q = node.quaternion
                    node.quaternion = Quaternion(q.x, -q.y, q.z, -q.w)
            return
        ref node = built.objects[object].node
        var translate = self.data("xformOp:translate", spec, attrs)
        if self.layer.truthy(translate):
            var t = self.vector(translate, "xformOp:translate")
            node.set_position(Float32(t[0]), Float32(t[1]), Float32(t[2]))
        var scale = self.data("xformOp:scale", spec, attrs)
        if self.layer.truthy(scale):
            if self.layer.is_array(scale):
                node.set_scale(
                    Float32(self.layer.element_number(scale, 0)),
                    Float32(self.layer.element_number(scale, 1)),
                    Float32(self.layer.element_number(scale, 2)),
                )
            else:
                var n = Float32(self.layer.to_number(scale))
                node.set_scale(n, n, n)
        var rotate = self.data("xformOp:rotateXYZ", spec, attrs)
        if self.layer.truthy(rotate):
            var r = self.vector(rotate, "xformOp:rotateXYZ")
            node.set_euler(
                Angle(Float32(r[0]), DEGREE),
                Angle(Float32(r[1]), DEGREE),
                Angle(Float32(r[2]), DEGREE),
            )
        var orient = self.data("xformOp:orient", spec, attrs)
        if self.layer.truthy(orient) and self.layer.length(orient) == 4:
            node.quaternion = self.quaternion(orient)

    def array(self, attrs: _Attrs, name: String) raises -> UsdArray:
        """Return an array attribute as the geometry reads it.

        Args:
            attrs: The attributes.
            name: The attribute.

        Returns:
            Its numbers, or an array that is not there when it is falsy.

        Raises:
            Error: If it is there and not an array.
        """
        return self.array_of(attrs.get(name), name)

    def array_of(self, id: Int, name: String) raises -> UsdArray:
        """Return a value as an array the geometry reads.

        Args:
            id: The value.
            name: Its name, for the message.

        Returns:
            Its numbers, or an array that is not there when it is falsy.

        Raises:
            Error: If it is there and not an array.
        """
        if not self.layer.truthy(id):
            return UsdArray()
        if not self.layer.is_array(id):
            raise Error("USD: " + name + " is not an array")
        return UsdArray(self.layer.numbers(id))

    def either(self, attrs: _Attrs, first: String, second: String) -> Int:
        """Return `attrs[ first ] || attrs[ second ]`.

        Args:
            attrs: The attributes.
            first: The first name.
            second: The second.

        Returns:
            The first's value when it is truthy, and the second's otherwise.
        """
        var a = attrs.get(first)
        return a if self.layer.truthy(a) else attrs.get(second)

    def uv_primvar(self, attrs: _Attrs) -> Tuple[Int, Int]:
        """Find the texture coordinates, three.js's `_findUVPrimvar`: the
        first primvar whose type holds `texCoord`, or `primvars:st`, or
        `primvars:UVMap`.

        Args:
            attrs: The mesh's attributes.

        Returns:
            The coordinates' value and their indices' value.
        """
        for name in attrs.names:
            if not name.startswith("primvars:"):
                continue
            var tail = (
                name.endswith(":typeName")
                or name.endswith(":elementSize")
                or name.endswith(":indices")
            )
            if tail or name.find("skel:") >= 0:
                continue
            var type_name = attrs.get(name + ":typeName")
            if self.layer.is_string(type_name):
                if self.layer.text(type_name).find("texCoord") >= 0:
                    return (attrs.get(name), attrs.get(name + ":indices"))
        return (
            self.either(attrs, "primvars:st", "primvars:UVMap"),
            attrs.get("primvars:st:indices"),
        )

    def mesh_arrays(self, attrs: _Attrs) raises -> UsdMeshArrays:
        """Read a mesh's arrays from its attributes.

        Args:
            attrs: The mesh's attributes.

        Returns:
            The arrays.

        Raises:
            Error: If one is there and not an array.
        """
        var mesh = UsdMeshArrays()
        mesh.points = self.array(attrs, "points")
        mesh.indices = self.array(attrs, "faceVertexIndices")
        mesh.counts = self.array(attrs, "faceVertexCounts")
        mesh.holes = self.array(attrs, "primvars:arnold:polygon_holes")
        mesh.normals = self.array_of(
            self.either(attrs, "normals", "primvars:normals"), "normals"
        )
        mesh.normal_indices = self.array_of(
            self.either(attrs, "normals:indices", "primvars:normals:indices"),
            "normal indices",
        )
        var uv = self.uv_primvar(attrs)
        mesh.uvs = self.array_of(uv[0], "texture coordinates")
        mesh.uv_indices = self.array_of(uv[1], "texture coordinate indices")
        mesh.uvs2 = self.array(attrs, "primvars:st1")
        mesh.uv2_indices = self.array(attrs, "primvars:st1:indices")
        return mesh^

    def subsets(self, path: String) raises -> List[_Subset]:
        """Return a mesh's subsets that have faces, three.js's
        `_getGeomSubsets`.

        Args:
            path: The mesh's path.

        Returns:
            The subsets, each with its faces and its material's path.

        Raises:
            Error: If a subset's `indices` is not an array.
        """
        var out = List[_Subset]()
        for subset in self.subsets_by_mesh.get(path):
            var attrs = self.attributes(subset)
            var indices = self.array(attrs, "indices")
            if not indices.filled():
                continue
            out.append(
                _Subset(indices.values.copy(), self.binding_target(subset))
            )
        return out^

    def binding_spec(self, prim: String) raises -> Int:
        """Return the spec of a prim's `material:binding`, a selected
        variant's overriding it, three.js's `_getMaterialBindingSpec`.

        Args:
            prim: The prim's path.

        Returns:
            The spec, or -1.

        Raises:
            Error: If a variant set is not a list of names.
        """
        var name = String("material:binding")
        var found = self.layer.spec(prim + "." + name)
        var parts = _split(prim)
        for i in range(1, len(parts)):  # pragma: no branch
            var ancestor = String("/").join(parts[: i + 1])
            var relative = String("/").join(parts[i + 1 :])
            for variant in self.variant_paths(ancestor):
                var override = (
                    variant + "/" + relative + "." + name if relative
                    != "" else variant + "." + name
                )
                var at = self.layer.spec(override)
                if at >= 0 and self.targets(at) > 0:
                    found = at
        return found

    def targets(self, spec: Int) -> Int:
        """Return `spec.fields.targetPaths.length`.

        Args:
            spec: The spec.

        Returns:
            The count, zero when there are none.
        """
        var id = self.layer.specs[spec].field("targetPaths")
        return max(self.layer.length(id), 0)

    def binding_target(self, prim: String) raises -> String:
        """Return the material bound to a prim, three.js's
        `_getMaterialBindingTarget`: the binding of the prim or of a
        parent, the nearest one unless a parent's is
        `strongerThanDescendants`.

        Args:
            prim: The prim's path.

        Returns:
            The material's path, or the empty string.

        Raises:
            Error: If a variant set is not a list of names.
        """
        var resolved = -1
        var ancestor = String("")
        for part in _split(prim):  # pragma: no branch
            if part == "":
                continue
            ancestor += "/" + part
            var spec = self.binding_spec(ancestor)
            if spec < 0 or self.targets(spec) == 0:
                continue
            var stronger = False
            if resolved >= 0:
                var how = self.layer.specs[resolved].field("bindMaterialAs")
                stronger = (
                    self.layer.is_string(how)
                    and self.layer.text(how) == "strongerThanDescendants"
                )
            if not stronger:
                resolved = spec
        if resolved < 0:
            return ""
        var id = self.layer.specs[resolved].field("targetPaths")
        return self.layer.element_string(id, 0).or_else("")

    def material_path(self, path: String, spec: Int) raises -> String:
        """Return a mesh's material, three.js's `_getMaterialPath`.

        Args:
            path: The mesh's path.
            spec: Its spec.

        Returns:
            The material's path, or the empty string.

        Raises:
            Error: If the prim's own binding is not a path.
        """
        var own = self.own_binding(spec)
        return own if own != "" else self.binding_target(path)

    def own_binding(self, spec: Int) raises -> String:
        """Return a prim's own `material:binding` field.

        Args:
            spec: The prim's spec.

        Returns:
            The path, or the empty string when there is none.

        Raises:
            Error: If it is there and not a path.
        """
        var id = self.layer.specs[spec].field("material:binding")
        if not self.layer.truthy(id):
            return ""
        if self.layer.is_array(id):
            return self.layer.element_string(id, 0).or_else("")
        if self.layer.is_string(id):
            return self.layer.text(id)
        raise Error("USD: a material binding that is not a path")

    def build_material(
        mut self, path: String, spec: Int, assets: UsdAssets, mut built: _Built
    ) raises -> Int:
        """Build a mesh's material, three.js's `_buildMaterial`.

        Args:
            path: The mesh's path.
            spec: Its spec.
            assets: The archive's files.
            built: What is being built.

        Returns:
            The material.

        Raises:
            Error: For anything the module docstring lists.
        """
        var material = built.new_material()
        var bound = self.material_path(path, spec)
        if bound == "":
            var found = List[String]()
            for k in range(len(self.layer.paths)):  # pragma: no branch
                var p = self.layer.paths[k]
                var below = p.startswith(path + "/") and p.endswith(
                    ".material:binding"
                )
                if below and self.targets(k) > 0:
                    var id = self.layer.specs[k].field("targetPaths")
                    found.append(self.layer.element_string(id, 0).or_else(""))
            if len(found) > 0:
                bound = self.best_material(found)
        if bound == "":
            var root = "/" + _split(path)[1]
            for candidate in self.materials_by_root.get(root):
                var looks = candidate.startswith(
                    root + "/Looks/"
                ) or candidate.startswith(root + "/Materials/")
                if looks:
                    bound = candidate
                    break
        if bound != "":
            self.apply_material(material, bound, assets, built)
        return material

    def best_material(self, paths: List[String]) raises -> String:
        """Return the first material with a texture, three.js's
        `_pickBestMaterial`.

        Args:
            paths: The materials.

        Returns:
            The first whose shaders read a file, or the first.

        Raises:
            Error: If a variant set is not a list of names.
        """
        for path in paths:  # pragma: no branch
            for shader in self.shaders_by_material.get(path):
                var attrs = self.attributes(shader)
                var id = attrs.get("info:id")
                var is_texture = (
                    self.layer.is_string(id)
                    and self.layer.text(id) == "UsdUVTexture"
                )
                if is_texture and self.layer.truthy(attrs.get("inputs:file")):
                    return path
        return paths[0]

    def apply_material_binding(
        mut self, mesh: Int, prim: String, assets: UsdAssets, mut built: _Built
    ) raises:
        """Give a referenced mesh the material its prim binds, three.js's
        `_applyMaterialBinding`.

        Args:
            mesh: The mesh.
            prim: The referencing prim's path.
            assets: The archive's files.
            built: What is being built.

        Raises:
            Error: For anything the module docstring lists.
        """
        var bound = self.binding_target(prim)
        if bound == "":
            return
        if bound.startswith("<"):
            var cut = String(bound[byte=1:])
            bound = cut
        if bound.endswith(">"):
            var cut = String(bound[byte = : bound.byte_length() - 1])
            bound = cut
        var material = built.new_material()
        self.apply_material(material, bound, assets, built)
        built.objects[mesh].materials = [material]
        built.objects[mesh].material_list = False

    def apply_material(
        mut self,
        material: Int,
        path: String,
        assets: UsdAssets,
        mut built: _Built,
    ) raises:
        """Apply each `UsdPreviewSurface` of a material, three.js's
        `_applyMaterial`.

        Args:
            material: The material.
            path: The material's path.
            assets: The archive's files.
            built: What is being built.

        Raises:
            Error: For anything the module docstring lists.
        """
        if self.layer.spec(path) < 0:
            return
        for shader in self.shaders_by_material.get(path):
            var spec = self.layer.spec(shader)
            var attrs = self.attributes(shader)
            var id = attrs.get("info:id")
            if not self.layer.truthy(id):
                id = self.layer.specs[spec].field("info:id")
            var info = self.layer.text(id) if self.layer.is_string(id) else ""
            if (
                info == "UsdPreviewSurface"
                or info == "ND_UsdPreviewSurface_surfaceshader"
            ):
                self.preview_surface(material, shader, assets, built)

    def connected_texture(
        mut self,
        shader: String,
        input: String,
        space: ColorSpace,
        assets: UsdAssets,
        mut built: _Built,
    ) raises -> Int:
        """Return the texture an input is connected to, the texture step of
        three.js's `_applyTextureOrValue`, and set its color space.

        Args:
            shader: The shader's path.
            input: The input, such as `inputs:diffuseColor`.
            space: The color space the map reads its texture in.
            assets: The archive's files.
            built: What is being built.

        Returns:
            The texture, or -1.

        Raises:
            Error: For anything the module docstring lists.
        """
        var connections = self.layer.field(
            shader + "." + input, "connectionPaths"
        )
        if (
            not self.layer.truthy(connections)
            or self.layer.length(connections) <= 0
        ):
            return -1
        var first = self.layer.element_string(connections, 0)
        if not first:
            return -1
        var image = self.texture_from_connection(first.value(), assets, built)
        if image >= 0:
            built.images[image].space = space
        return image

    def color(self, id: Int, what: String) raises -> Optional[Color]:
        """Return a color value, as three.js's `setRGB` from sRGB reads it.

        Args:
            id: The value.
            what: The input, for the message.

        Returns:
            The color, or nothing when the value is not an array of three
            numbers at least.

        Raises:
            Error: If a channel is outside zero to one.
        """
        if not self.layer.is_array(id) or self.layer.length(id) < 3:
            return None
        return authored_color(
            self.layer.element_number(id, 0),
            self.layer.element_number(id, 1),
            self.layer.element_number(id, 2),
            "USD " + what,
        )

    def scalar(self, id: Int, what: String) raises -> Float32:
        """Return a material value that must be a number.

        Args:
            id: The value.
            what: The input, for the message.

        Returns:
            The number.

        Raises:
            Error: If it is not a number.
        """
        if not self.layer.is_number(id):
            raise Error("USD: " + what + " is not a number")
        return Float32(self.layer.number(id))

    def scaled(self, image: Int, built: _Built) -> Optional[List[Float64]]:
        """Return a texture's `userData.scale`.

        Args:
            image: The texture, or -1.
            built: What is being built.

        Returns:
            The scale, or nothing.
        """
        if image < 0:
            return None
        return built.images[image].scale.copy()

    def preview_surface(
        mut self,
        material: Int,
        shader: String,
        assets: UsdAssets,
        mut built: _Built,
    ) raises:
        """Read a `UsdPreviewSurface` into a material, three.js's
        `_applyPreviewSurface`.

        Args:
            material: The material.
            shader: The shader's path.
            assets: The archive's files.
            built: What is being built.

        Raises:
            Error: For anything the module docstring lists.
        """
        var fields = self.attributes(shader)
        var map = self.connected_texture(
            shader, "inputs:diffuseColor", SRGB, assets, built
        )
        if map >= 0:
            built.materials[material].map = TextureId(map)
        elif self.layer.defined(fields.get("inputs:diffuseColor")):
            var c = self.color(
                fields.get("inputs:diffuseColor"), "diffuseColor"
            )
            if c:
                built.materials[material].color = c.value()
        var map_scale = self.scaled(built.materials[material].map.value, built)
        if map_scale and len(map_scale.value()) >= 3:
            var s = map_scale.value().copy()
            built.materials[material].color = authored_color(
                s[0], s[1], s[2], "USD scale"
            )
        var emissive = self.connected_texture(
            shader, "inputs:emissiveColor", SRGB, assets, built
        )
        if emissive >= 0:
            built.materials[material].emissive_map = TextureId(emissive)
        elif self.layer.defined(fields.get("inputs:emissiveColor")):
            var c = self.color(
                fields.get("inputs:emissiveColor"), "emissiveColor"
            )
            if c:
                built.materials[material].emissive = c.value()
        var emissive_map = built.materials[material].emissive_map.value
        if emissive_map >= 0:
            var s = self.scaled(emissive_map, built)
            if s:
                if len(s.value()) >= 3:
                    var v = s.value().copy()
                    built.materials[material].emissive = authored_color(
                        v[0], v[1], v[2], "USD scale"
                    )
            else:
                built.materials[material].emissive = _WHITE
        var normal = self.connected_texture(
            shader, "inputs:normal", LINEAR, assets, built
        )
        if normal >= 0:
            built.materials[material].normal_map = TextureId(normal)
        var normal_map = built.materials[material].normal_map.value
        if normal_map >= 0:
            var s = self.scaled(normal_map, built)
            if s:
                var v = s.value().copy()
                var x = v[0] if len(v) > 0 else nan[DType.float64]()
                var y = v[1] if len(v) > 1 else nan[DType.float64]()
                built.materials[material].normal_scale = Vector2(
                    Float32(x), Float32(y)
                )
        var roughness = self.connected_texture(
            shader, "inputs:roughness", LINEAR, assets, built
        )
        if roughness >= 0:
            built.materials[material].roughness_map = TextureId(roughness)
            built.materials[material].roughness = 1
        elif self.layer.defined(fields.get("inputs:roughness")):
            built.materials[material].roughness = self.scalar(
                fields.get("inputs:roughness"), "roughness"
            )
        var metallic = self.connected_texture(
            shader, "inputs:metallic", LINEAR, assets, built
        )
        if metallic >= 0:
            built.materials[material].metalness_map = TextureId(metallic)
            built.materials[material].metalness = 1
        elif self.layer.defined(fields.get("inputs:metallic")):
            built.materials[material].metalness = self.scalar(
                fields.get("inputs:metallic"), "metallic"
            )
        var occlusion = self.connected_texture(
            shader, "inputs:occlusion", LINEAR, assets, built
        )
        if occlusion >= 0:
            built.materials[material].ao_map = TextureId(occlusion)
        if self.layer.defined(fields.get("inputs:ior")):
            built.materials[material].ior = self.scalar(
                fields.get("inputs:ior"), "ior"
            )
        var specular = self.connected_texture(
            shader, "inputs:specularColor", SRGB, assets, built
        )
        if specular >= 0:
            built.materials[material].specular_color_map = TextureId(specular)
        elif self.layer.defined(fields.get("inputs:specularColor")):
            var c = self.color(
                fields.get("inputs:specularColor"), "specularColor"
            )
            if c:
                built.materials[material].specular_color = c.value()
        var specular_scale = self.scaled(
            built.materials[material].specular_color_map.value, built
        )
        if specular_scale and len(specular_scale.value()) >= 3:
            var s = specular_scale.value().copy()
            built.materials[material].specular_color = authored_color(
                s[0], s[1], s[2], "USD scale"
            )
        if self.layer.defined(fields.get("inputs:clearcoat")):
            built.materials[material].clearcoat = self.scalar(
                fields.get("inputs:clearcoat"), "clearcoat"
            )
        if self.layer.defined(fields.get("inputs:clearcoatRoughness")):
            built.materials[material].clearcoat_roughness = self.scalar(
                fields.get("inputs:clearcoatRoughness"), "clearcoatRoughness"
            )
        var threshold = Float32(0)
        if self.layer.defined(fields.get("inputs:opacityThreshold")):
            threshold = self.scalar(
                fields.get("inputs:opacityThreshold"), "opacityThreshold"
            )
        var opacity_links = self.layer.field(
            shader + ".inputs:opacity", "connectionPaths"
        )
        if self.layer.length(opacity_links) > 0:
            if threshold > 0:
                built.materials[material].alpha_test = threshold
                built.materials[material].transparent = False
            else:
                built.materials[material].transparent = True
        else:
            var opacity = Float32(1)
            if self.layer.defined(fields.get("inputs:opacity")):
                opacity = self.scalar(fields.get("inputs:opacity"), "opacity")
            if opacity < 1:
                built.materials[material].transparent = True
                built.materials[material].opacity = opacity

    def shader_info(self, path: String, attrs: _Attrs) -> String:
        """Return a shader's `info:id`: its attribute, or its field.

        Args:
            path: The shader's path.
            attrs: Its attributes.

        Returns:
            The id, or the empty string.
        """
        var id = attrs.get("info:id")
        if not self.layer.truthy(id):
            id = self.layer.field(path, "info:id")
        return self.layer.text(id) if self.layer.is_string(id) else ""

    def first_connection(self, path: String) -> String:
        """Return the prim of an input's first connection, less `<` and
        `>`.

        Args:
            path: The input's path.

        Returns:
            The connected prim's path, or the empty string.
        """
        var links = self.layer.field(path, "connectionPaths")
        if self.layer.length(links) <= 0:
            return ""
        var first = self.layer.element_string(links, 0).or_else("")
        return _before(_no_angles(first), ".")

    def uv_channel(self, attrs: _Attrs) raises -> UvChannel:
        """Return the set of coordinates a primvar reader reads.

        Args:
            attrs: The reader's attributes.

        Returns:
            `UV_CHANNEL_1` for `st1`, and `UV_CHANNEL_0` otherwise.

        Raises:
            Error: For `st2`, a third set, which this port has not got.
        """
        var id = attrs.get("inputs:varname")
        var name = self.layer.text(id) if self.layer.is_string(id) else ""
        if name == "st2":
            raise Error("USD: a texture reads st2, a third set of coordinates")
        return UV_CHANNEL_1 if name == "st1" else UV_CHANNEL_0

    def joined(self, id: Int, what: String) raises -> String:
        """Return `value.join( ',' )`.

        Args:
            id: The value.
            what: The input, for the message.

        Returns:
            Each element's text, joined by commas.

        Raises:
            Error: If the value is not an array, which has no `join`.
        """
        if not self.layer.is_array(id):
            raise Error("USD: a texture " + what + " that is not a list")
        var out = String("")
        for k in range(self.layer.length(id)):
            if k > 0:
                out += ","
            var text = self.layer.element_string(id, k)
            if text:
                out += text.value()
            else:
                out += js_number_text(self.layer.element_number(id, k))
        return out^

    def texture_from_connection(
        mut self, connection: String, assets: UsdAssets, mut built: _Built
    ) raises -> Int:
        """Return the texture of a `UsdUVTexture` output, three.js's
        `_getTextureFromConnection`.

        Args:
            connection: The output's path, such as `/Mat/Tex.outputs:rgb`.
            assets: The archive's files.
            built: What is being built.

        Returns:
            The texture, or -1.

        Raises:
            Error: For anything the module docstring lists.
        """
        var shader = _before(connection, ".")
        if self.layer.spec(shader) < 0:
            return -1
        var attrs = self.attributes(shader)
        if self.shader_info(shader, attrs) != "UsdUVTexture":
            return -1
        var file = attrs.get("inputs:file")
        if not self.layer.truthy(file):
            return -1
        if not self.layer.is_string(file):
            raise Error("USD: a texture file that is not a path")
        var transform: Optional[_Attrs] = None
        var channel = UV_CHANNEL_0
        var st = self.first_connection(shader + ".inputs:st")
        if st != "" and self.layer.spec(st) >= 0:
            var st_attrs = self.attributes(st)
            var info = self.shader_info(st, st_attrs)
            if info == "UsdTransform2d":
                var reader = self.first_connection(st + ".inputs:in")
                if reader != "":
                    channel = self.uv_channel(self.attributes(reader))
                transform = st_attrs^
            elif info == "UsdPrimvarReader_float2":
                channel = self.uv_channel(st_attrs)
        var scale = attrs.get("inputs:scale")
        var bias = attrs.get("inputs:bias")
        var key = self.layer.text(file)
        if self.layer.truthy(scale):
            key += ":s" + self.joined(scale, "scale")
        if self.layer.truthy(bias):
            key += ":b" + self.joined(bias, "bias")
        for k in range(len(self.cache_keys)):
            if self.cache_keys[k] == key:
                return self.cache_images[k]
        var image = self.load_texture(
            self.layer.text(file), attrs, transform, assets, built
        )
        if image < 0:
            return -1
        if self.layer.truthy(scale):
            built.images[image].scale = self.layer.numbers(scale)
        if self.layer.truthy(bias):
            built.images[image].bias = self.layer.numbers(bias)
        built.images[image].channel = channel
        self.cache_keys.append(key)
        self.cache_images.append(image)
        return image

    def load_texture(
        self,
        file: String,
        attrs: _Attrs,
        transform: Optional[_Attrs],
        assets: UsdAssets,
        mut built: _Built,
    ) raises -> Int:
        """Find a texture's image, three.js's `_loadTexture`.

        Args:
            file: The file, as the shader names it.
            attrs: The texture shader's attributes.
            transform: The `UsdTransform2d`'s attributes, when it has one.
            assets: The archive's files.
            built: What is being built.

        Returns:
            The texture, or -1 when the file is nowhere.

        Raises:
            Error: If a placement is not numbers.
        """
        var clean = file
        if clean.startswith("@"):
            var cut = String(clean[byte=1:])
            clean = cut
        if clean.endswith("@"):
            var cut = String(clean[byte = : clean.byte_length() - 1])
            clean = cut
        var resolved = self.resolve_file(clean)
        var asset = assets.find(resolved)
        if asset < 0:
            asset = assets.find(clean)
        if asset < 0:
            var base = _last_part(clean)
            for k in assets.order():
                var name = assets.names[k]
                # three.js also asks `endsWith( '/' + baseName )`, which
                # `endsWith( baseName )` answers.
                if name.endswith(base):
                    return self.create_texture(
                        k, "", attrs, transform, assets, built
                    )
            if self.base_path != "":
                return self.create_texture(
                    -1, resolved, attrs, transform, assets, built
                )
            return -1
        return self.create_texture(asset, "", attrs, transform, assets, built)

    def create_texture(
        self,
        asset: Int,
        url: String,
        attrs: _Attrs,
        transform: Optional[_Attrs],
        assets: UsdAssets,
        mut built: _Built,
    ) raises -> Int:
        """Make a texture and load its image, three.js's
        `_createTextureFromData`: on a load, the wraps and the placement
        are set; on an error, the texture keeps no image.

        Args:
            asset: The archive's file, or -1 for a file on the disk.
            url: The file on the disk, when `asset` is -1.
            attrs: The texture shader's attributes.
            transform: The `UsdTransform2d`'s attributes, when it has one.
            assets: The archive's files.
            built: What is being built.

        Returns:
            The texture, or -1 when the archive's file is a layer.

        Raises:
            Error: If a placement is not numbers.
        """
        var bytes = List[UInt8]()
        var image: _Image
        if asset >= 0:
            if assets.kinds[asset] != USD_IMAGE:
                return -1
            image = _Image(assets.names[asset], True)
            bytes = assets.images[asset].copy()
        else:
            image = _Image(url, False)
            try:
                bytes = Path(url).read_bytes()
            except:
                pass
        if len(bytes) > 0:
            try:
                var decoded = decode_image(bytes)
                image.width = decoded.width
                image.height = decoded.height
                image.pixels = decoded.pixels.copy()
                image.loaded = True
            except:
                pass
        if image.loaded:
            image.wrap_s = _wrap_of(self.string_of(attrs.get("inputs:wrapS")))
            image.wrap_t = _wrap_of(self.string_of(attrs.get("inputs:wrapT")))
            if Bool(transform):
                self.place(image, transform.value())
        built.images.append(image^)
        return len(built.images) - 1

    def string_of(self, id: Int) -> String:
        """Return a value's text when it is a string.

        Args:
            id: The value.

        Returns:
            The text, or the empty string.
        """
        return self.layer.text(id) if self.layer.is_string(id) else ""

    def place(self, mut image: _Image, attrs: _Attrs) raises:
        """Set a texture's placement, three.js's `_applyTextureTransforms`:
        the repeat, the offset, and the rotation in degrees.

        Args:
            image: The texture.
            attrs: The `UsdTransform2d`'s attributes.

        Raises:
            Error: If the layer refuses a read.
        """
        var scale = attrs.get("inputs:scale")
        if self.layer.is_array(scale) and self.layer.length(scale) >= 2:
            image.repeat = Vector2(
                Float32(self.layer.element_number(scale, 0)),
                Float32(self.layer.element_number(scale, 1)),
            )
        var translation = attrs.get("inputs:translation")
        if (
            self.layer.is_array(translation)
            and self.layer.length(translation) >= 2
        ):
            image.offset = Vector2(
                Float32(self.layer.element_number(translation, 0)),
                Float32(self.layer.element_number(translation, 1)),
            )
        var rotation = attrs.get("inputs:rotation")
        if self.layer.is_number(rotation):
            image.rotation = Angle(Float32(self.layer.number(rotation)), DEGREE)

    def build_mesh(
        mut self, path: String, spec: Int, assets: UsdAssets, mut built: _Built
    ) raises -> Int:
        """Build a `Mesh` prim, three.js's `_buildMesh`.

        Args:
            path: The prim's path.
            spec: Its spec.
            assets: The archive's files.
            built: What is being built.

        Returns:
            The mesh.

        Raises:
            Error: For anything the module docstring lists.
        """
        var attrs = self.attributes(path)
        var subsets = self.subsets(path)
        var arrays = self.mesh_arrays(attrs)
        var object = _Object(_last_part(path))
        object.is_mesh = True
        if len(subsets) > 0:
            var faces = List[List[Float64]]()
            for subset in subsets:  # pragma: no branch
                faces.append(subset.indices.copy())
            built.geometries.append(
                build_usd_geometry_with_subsets(arrays, faces)
            )
            var own = self.material_path(path, spec)
            for subset in subsets:  # pragma: no branch
                var material = built.new_material()
                var bound = subset.material if subset.material != "" else own
                if bound != "":
                    self.apply_material(material, bound, assets, built)
                object.materials.append(material)
            object.material_list = True
        else:
            built.geometries.append(build_usd_geometry(arrays))
            object.materials.append(
                self.build_material(path, spec, assets, built)
            )
        object.geometry = len(built.geometries) - 1
        var tint = attrs.get("primvars:displayColor")
        if self.layer.truthy(tint) and self.layer.length(tint) >= 3:
            for material in object.materials:  # pragma: no branch
                var white = _is_white(built.materials[material].color)
                if white and built.materials[material].map == NO_TEXTURE:
                    var color = self.color(tint, "displayColor")
                    if color:
                        built.materials[material].color = color.value()
        var fade = attrs.get("primvars:displayOpacity")
        var fades = (
            self.layer.truthy(fade)
            and self.layer.length(fade) == 1
            and len(subsets) == 0
        )
        if fades:
            var opacity = Float32(self.layer.element_number(fade, 0))
            for material in object.materials:  # pragma: no branch
                var opaque = built.materials[material].opacity == 1
                var solid = not built.materials[material].transparent
                if opacity < 1 and opaque and solid:
                    built.materials[material].opacity = opacity
                    built.materials[material].transparent = True
        var at = built.add(object^)
        self.apply_transform(at, spec, attrs, built)
        return at

    def size(
        self, attrs: _Attrs, name: String, fallback: Float64
    ) raises -> Float64:
        """Return `attrs[ name ] || fallback`.

        Args:
            attrs: The attributes.
            name: The attribute.
            fallback: The default.

        Returns:
            The value when it is truthy, and the default otherwise.

        Raises:
            Error: If the value is truthy and not a number.
        """
        var id = attrs.get(name)
        if not self.layer.truthy(id):
            return fallback
        if not self.layer.is_number(id):
            raise Error("USD: a " + name + " that is not a number")
        return self.layer.number(id)

    def build_primitive(
        mut self,
        path: String,
        spec: Int,
        type_name: String,
        assets: UsdAssets,
        mut built: _Built,
    ) raises -> Int:
        """Build a `Cube`, `Sphere`, `Cylinder`, `Cone` or `Capsule` prim,
        three.js's `_buildGeomPrimitive`: its geometry turned from USD's
        default Z axis, or its `axis`, to Y.

        Args:
            path: The prim's path.
            spec: Its spec.
            type_name: Its type.
            assets: The archive's files.
            built: What is being built.

        Returns:
            The mesh.

        Raises:
            Error: For anything the module docstring lists.
        """
        var attrs = self.attributes(path)
        var geometry: BufferGeometry
        if type_name == "Cube":
            var edge = Length(Float32(self.size(attrs, "size", 2)), METER)
            geometry = box(edge, edge, edge)
        elif type_name == "Sphere":
            geometry = sphere(
                Length(Float32(self.size(attrs, "radius", 1)), METER), 32, 16
            )
        elif type_name == "Cylinder":
            var height = Length(Float32(self.size(attrs, "height", 2)), METER)
            var radius = Length(Float32(self.size(attrs, "radius", 1)), METER)
            geometry = cylinder(radius, radius, height, 32)
        elif type_name == "Cone":
            var height = Length(Float32(self.size(attrs, "height", 2)), METER)
            var radius = Length(Float32(self.size(attrs, "radius", 1)), METER)
            geometry = cone(radius, height, 32)
        else:
            var height = Length(Float32(self.size(attrs, "height", 1)), METER)
            var radius = Length(Float32(self.size(attrs, "radius", 0.5)), METER)
            geometry = capsule(radius, height, 16, 32)
        var axis = attrs.get("axis")
        var name = String("Z")
        if self.layer.truthy(axis):
            name = self.layer.text(axis) if self.layer.is_string(axis) else ""
        if name == "X":
            geometry.rotate_z(Angle(Float32(-pi / 2), RADIAN))
        elif name == "Z":
            geometry.rotate_x(Angle(Float32(pi / 2), RADIAN))
        built.geometries.append(geometry^)
        var object = _Object(_last_part(path))
        object.is_mesh = True
        object.geometry = len(built.geometries) - 1
        object.materials.append(self.build_material(path, spec, assets, built))
        var at = built.add(object^)
        self.apply_transform(at, spec, attrs, built)
        return at


def _is_white(color: Color) -> Bool:
    """Return three.js's `color.r === 1 && color.g === 1 && color.b === 1`.

    Args:
        color: The color.

    Returns:
        Whether it is white.
    """
    return color.r == 255 and color.g == 255 and color.b == 255


def _is_primitive(type_name: String) -> Bool:
    """Return True for the prims three.js builds from its geometries.

    Args:
        type_name: The prim's type.

    Returns:
        Whether it is a `Cube`, `Sphere`, `Cylinder`, `Cone` or `Capsule`.
    """
    return (
        type_name == "Cube"
        or type_name == "Sphere"
        or type_name == "Cylinder"
        or type_name == "Cone"
        or type_name == "Capsule"
    )


def moved(node: Object3D) raises -> Bool:
    """Return three.js's `_hasNonIdentityTransform`: a position, a turn or
    a scale that is not the identity's.

    Args:
        node: The node.

    Returns:
        Whether it moves what is under it.

    Raises:
        Error: If the rotation cannot be read.
    """
    var p = node.position
    var s = node.scale
    var r = Euler.from_quaternion(node.quaternion, XYZ)
    var position = p.x != 0 or p.y != 0 or p.z != 0
    var rotation = r.x.value != 0 or r.y.value != 0 or r.z.value != 0
    var scale = s.x != 1 or s.y != 1 or s.z != 1
    return position or rotation or scale


def _remap(texture: TextureId, ids: List[TextureId]) -> TextureId:
    """Return the stored texture a built texture became.

    Args:
        texture: The built texture, or `NO_TEXTURE`.
        ids: The stored texture of each built texture.

    Returns:
        The stored texture, or `NO_TEXTURE`.
    """
    if texture == NO_TEXTURE:
        return NO_TEXTURE
    return ids[texture.value]


def _store_texture(
    image: _Image, mut store: Assets, mut model: UsdModel
) raises -> TextureId:
    """Store a built texture and name it in the model.

    Args:
        image: The texture.
        store: Where it goes.
        model: What was added.

    Returns:
        Its id.

    Raises:
        Error: If the texture cannot be made.
    """
    var alpha = COVERAGE if image.space == SRGB else IGNORED
    var texture: Texture
    if image.loaded:
        texture = Texture(
            image.width,
            image.height,
            image.pixels.copy(),
            image.wrap_s,
            BILINEAR,
            image.space,
            True,
            alpha,
        )
    else:
        texture = Texture(
            1, 1, [0, 0, 0, 255], CLAMP, NEAREST, image.space, False, alpha
        )
        model.missing_textures.append(image.source)
    texture.wrap_s = image.wrap_s
    texture.wrap_t = image.wrap_t
    texture.repeat = image.repeat
    texture.offset = image.offset
    texture.rotation = image.rotation
    texture.channel = image.channel
    var id = store.textures.add(texture^)
    model.textures.append(
        UsdTexture(
            id,
            image.source,
            image.in_archive,
            image.loaded,
            image.scale.copy(),
            image.bias.copy(),
        )
    )
    return id


def _emit(
    mut built: _Built,
    root: Int,
    mut scene: Scene,
    mut store: Assets,
    parent: NodeId,
) raises -> UsdModel:
    """Put what was built into the scene and the store, depth first.

    Args:
        built: What was built.
        root: The root group.
        scene: The scene.
        store: Where the geometries, materials and textures go.
        parent: The node the root goes under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: If the scene or the store refuses an item.
    """
    var texture_ids = List[TextureId](length=len(built.images), fill=NO_TEXTURE)
    var root_node = scene.attach(
        Object3D(copy=built.objects[root].node), parent
    )
    var model = UsdModel(root_node)
    model.objects.append(
        UsdObject(
            root_node, -1, False, GeometryId(0), List[MaterialId](), False
        )
    )
    var stack: List[Tuple[Int, Int]] = []
    for child in reversed(built.objects[root].children):
        stack.append((child, 0))
    while len(stack) > 0:
        var entry = stack.pop()
        var object = entry[0]
        var parent_place = entry[1]
        var node = scene.attach(
            Object3D(copy=built.objects[object].node),
            model.objects[parent_place].node,
        )
        var materials = List[MaterialId]()
        var geometry = GeometryId(0)
        if built.objects[object].is_mesh:
            geometry = store.geometries.add(
                built.geometries[built.objects[object].geometry].clone()
            )
            for material in built.objects[
                object
            ].materials:  # pragma: no branch
                var m = built.materials[material]
                var textures: List[TextureId] = [
                    m.map,
                    m.emissive_map,
                    m.normal_map,
                    m.roughness_map,
                    m.metalness_map,
                    m.ao_map,
                    m.specular_color_map,
                ]
                for texture in textures:  # pragma: no branch
                    var ok = (
                        texture != NO_TEXTURE
                        and texture_ids[texture.value] == NO_TEXTURE
                    )
                    if ok:
                        texture_ids[texture.value] = _store_texture(
                            built.images[texture.value], store, model
                        )
                m.map = _remap(m.map, texture_ids)
                m.emissive_map = _remap(m.emissive_map, texture_ids)
                m.normal_map = _remap(m.normal_map, texture_ids)
                m.roughness_map = _remap(m.roughness_map, texture_ids)
                m.metalness_map = _remap(m.metalness_map, texture_ids)
                m.ao_map = _remap(m.ao_map, texture_ids)
                m.specular_color_map = _remap(m.specular_color_map, texture_ids)
                materials.append(store.materials.add(m))
            if built.objects[object].material_list:
                scene.add_mesh(Mesh(geometry, materials, node))
            else:
                scene.add_mesh(Mesh(geometry, materials[0], node))
        model.objects.append(
            UsdObject(
                node,
                parent_place,
                built.objects[object].is_mesh,
                geometry,
                materials^,
                built.objects[object].material_list,
            )
        )
        var place = len(model.objects) - 1
        for child in reversed(built.objects[object].children):
            stack.append((child, place))
    return model^


def compose_usd(
    var layer: UsdLayer,
    assets: UsdAssets,
    base_path: String,
    mut scene: Scene,
    mut store: Assets,
    parent: NodeId = NO_PARENT,
) raises -> UsdModel:
    """Compose a layer into a scene, three.js's `USDComposer.compose`.

    Args:
        layer: The root layer.
        assets: The archive's images and layers, which references and
            textures name.
        base_path: The folder the layer's files are found in: the root
            layer's folder in the archive, or the file's folder on the
            disk, or the empty string.
        scene: The scene.
        store: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: For anything the module docstring lists.
    """
    var built = _Built()
    var composer = _Composer(
        layer^, base_path, List[String](), List[String](), 0
    )
    var root = composer.compose(assets, built)
    return _emit(built, root, scene, store, parent)
