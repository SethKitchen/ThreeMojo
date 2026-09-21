# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A glTF 2.0 file's nodes, meshes, materials and textures, read from a
`.gltf` or a `.glb` into a `Scene` and an `Assets`: three.js's
`GLTFLoader`.

**What a glTF file is.** A JSON document that names buffers of bytes, and
the bytes: beside it in `.bin` files, inside it as `data:` URIs, or after
it in the one binary container a `.glb` is. Accessors say how to read
numbers out of the buffers; meshes say which accessors are positions,
normals, texture coordinates, colors and indices; materials say what a
surface is made of in the metallic-roughness model this renderer already
shades; nodes hang meshes on a transform hierarchy; a scene names the
roots. `read_gltf` reads all of that into the scene and the assets it is
handed and returns a `GltfModel` that says what went where.

**What maps to what.** A primitive becomes a `BufferGeometry` with
`position`, and `normal`, `uv` and `color` when it has them, indexed when
it is; a material becomes a `standard_material`, which is three.js's
`MeshStandardMaterial` and what `GLTFLoader` builds; a texture becomes a
`Texture` at its sampler's wrap and filters, read as sRGB for a base color
or an emissive map and as linear for a metallic-roughness or a normal map;
a node becomes an `Object3D` at its translation, rotation and scale, or at
its matrix decomposed; each primitive on a node becomes a `Mesh`. The
metallic-roughness texture is one image read twice, as glTF stores it and
as the standard material reads it: roughness from green, metalness from
blue.

**Texture coordinates run down in glTF.** `(0, 0)` is an image's top
left, where this renderer's `v` runs up from the bottom. three.js answers
with `flipY = false` on every glTF texture; this answers with the texture's
own `repeat` and `offset` set to flip `v`, so the geometry's coordinates
are kept as the file has them.

**Not ported.** Skins, animations, cameras, morph targets and sparse
accessors, and every extension: a file whose `extensionsRequired` names
one is refused, since it could not be drawn as meant, and one that only
uses an extension is read without it. Only triangles are read; a primitive
of points, lines or strips is refused.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.json import (
    ARRAY,
    NO_NODE,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    parse_json,
)
from materials.material import (
    DOUBLE_SIDE,
    FRONT_SIDE,
    NO_TEXTURE,
    Material,
    MaterialId,
    standard_material,
)
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.jpeg import decode as decode_jpeg
from render.png import DecodedImage, decode as decode_png
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    MIRROR,
    NEAREST,
    REPEAT,
    Filter,
    Texture,
    Wrap,
    texture_from,
)
from render.texture_store import TextureId
from std.math import isfinite, sqrt
from std.memory import bitcast
from std.pathlib import Path

# The binary container's header: the magic `glTF`, the version, and the
# two chunk types, as little-endian words.
comptime GLB_MAGIC = 0x46546C67
comptime GLB_VERSION = 2
comptime GLB_HEADER_BYTES = 12
comptime GLB_CHUNK_HEADER_BYTES = 8
comptime GLB_JSON_CHUNK = 0x4E4F534A
comptime GLB_BIN_CHUNK = 0x004E4942

# The accessor component types glTF names, by their GL constants.
comptime COMPONENT_BYTE = 5120
comptime COMPONENT_UNSIGNED_BYTE = 5121
comptime COMPONENT_SHORT = 5122
comptime COMPONENT_UNSIGNED_SHORT = 5123
comptime COMPONENT_UNSIGNED_INT = 5125
comptime COMPONENT_FLOAT = 5126

# The one primitive mode that is read: triangles.
comptime MODE_TRIANGLES = 4

# The sampler's wrap and filter constants.
comptime WRAP_REPEAT = 10497
comptime WRAP_CLAMP = 33071
comptime WRAP_MIRROR = 33648
comptime FILTER_NEAREST = 9728
comptime FILTER_LINEAR = 9729
# The four minification filters that read a mipmap chain.
comptime FILTER_NEAREST_MIPMAP_NEAREST = 9984
comptime FILTER_LINEAR_MIPMAP_LINEAR = 9987

# What a material's `alphaCutoff` is when `MASK` names none.
comptime DEFAULT_ALPHA_CUTOFF = Float32(0.5)


struct GltfModel(Copyable, Movable):
    """What `read_gltf` put into the scene and the assets, by the file's
    own indices."""

    # One entry per glTF node: the scene node it became, or `NO_PARENT`
    # for a node the loaded scene does not reach.
    var nodes: List[NodeId]
    # Each node's `name`, or empty.
    var node_names: List[String]
    # One entry per glTF mesh: where its primitives' geometries begin in
    # `geometries`, and how many there are.
    var first_primitives: List[Int]
    var primitive_counts: List[Int]
    # One geometry per primitive, mesh by mesh.
    var geometries: List[GeometryId]
    # One entry per glTF material.
    var materials: List[MaterialId]
    # One entry per glTF texture, as read for a base color or an emissive
    # map, or `NO_TEXTURE` when no material read it that way.
    var color_textures: List[TextureId]
    # The same textures as read for a metallic-roughness or a normal map.
    var data_textures: List[TextureId]
    # Where the meshes this file added begin in `scene.meshes`, and how
    # many there are.
    var first_mesh: Int
    var mesh_count: Int

    def __init__(out self):
        """Start empty."""
        self.nodes = List[NodeId]()
        self.node_names = List[String]()
        self.first_primitives = List[Int]()
        self.primitive_counts = List[Int]()
        self.geometries = List[GeometryId]()
        self.materials = List[MaterialId]()
        self.color_textures = List[TextureId]()
        self.data_textures = List[TextureId]()
        self.first_mesh = 0
        self.mesh_count = 0

    def node_count(self) -> Int:
        """Return how many nodes the file has."""
        return len(self.nodes)

    def mesh_geometries(self, mesh: Int) raises -> List[GeometryId]:
        """Return the geometries of one glTF mesh's primitives.

        Args:
            mesh: The mesh's index in the file.

        Returns:
            One geometry id per primitive.

        Raises:
            Error: If the index names no mesh.
        """
        if mesh < 0 or mesh >= len(self.first_primitives):
            raise Error("glTF: no mesh at index " + String(mesh))
        var found = List[GeometryId]()
        for offset in range(self.primitive_counts[mesh]):
            found.append(self.geometries[self.first_primitives[mesh] + offset])
        return found^


def read_gltf(
    path: String, mut scene: Scene, mut assets: Assets
) raises -> GltfModel:
    """Read a `.gltf` or a `.glb` file into a scene and its assets.

    A `.glb` is told by its magic; anything else is read as JSON. A
    buffer or an image named by a relative URI is read from the file's
    own directory.

    Args:
        path: The file.
        scene: The scene to add the nodes and meshes to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where.

    Raises:
        Error: If the file cannot be read, or everything `load_gltf`
            raises.
    """
    var bytes = Path(path).read_bytes()
    # Up to and including the last slash, or nothing for a bare name.
    var directory = _slice(path, 0, path.rfind("/") + 1)
    if len(bytes) >= 4 and _le32(bytes, 0) == GLB_MAGIC:
        var parts = split_glb(bytes)
        return load_gltf(parts[0], parts[1], directory, scene, assets)
    return load_gltf(
        String(unsafe_from_utf8=bytes), List[UInt8](), directory, scene, assets
    )


def split_glb(bytes: List[UInt8]) raises -> Tuple[String, List[UInt8]]:
    """Return a `.glb` container's JSON text and its binary chunk.

    Args:
        bytes: The whole file.

    Returns:
        The JSON, and the binary chunk's bytes, empty when there is none.

    Raises:
        Error: If the magic, the version or the length is wrong, the first
            chunk is not JSON, a chunk runs past the file, or a chunk is
            of a type that is neither JSON nor binary.
    """
    if len(bytes) < GLB_HEADER_BYTES or _le32(bytes, 0) != GLB_MAGIC:
        raise Error("glTF: not a .glb container")
    if _le32(bytes, 4) != GLB_VERSION:
        raise Error("glTF: only version 2 of the binary container is read")
    if _le32(bytes, 8) != len(bytes):
        raise Error("glTF: the container's length does not match the file")
    var at = GLB_HEADER_BYTES
    var json = String()
    var bin = List[UInt8]()
    var seen_json = False
    while at < len(bytes):
        if at + GLB_CHUNK_HEADER_BYTES > len(bytes):
            raise Error("glTF: a chunk header runs past the file")
        var length = _le32(bytes, at)
        var kind = _le32(bytes, at + 4)
        var start = at + GLB_CHUNK_HEADER_BYTES
        if start + length > len(bytes):
            raise Error("glTF: a chunk runs past the file")
        var chunk = List[UInt8]()
        for index in range(start, start + length):
            chunk.append(bytes[index])
        if kind == GLB_JSON_CHUNK:
            if seen_json:
                raise Error("glTF: two JSON chunks")
            seen_json = True
            json = String(unsafe_from_utf8=chunk)
        elif kind == GLB_BIN_CHUNK:
            if not seen_json:
                raise Error("glTF: the first chunk must be JSON")
            if len(bin) > 0:
                raise Error("glTF: two binary chunks")
            bin = chunk^
        else:
            raise Error("glTF: a chunk of an unknown type")
        at = start + length
    if not seen_json:
        raise Error("glTF: the container holds no JSON chunk")
    return (json^, bin^)


def load_gltf(
    text: String,
    bin: List[UInt8],
    directory: String,
    mut scene: Scene,
    mut assets: Assets,
) raises -> GltfModel:
    """Read a glTF document into a scene and its assets.

    Args:
        text: The JSON.
        bin: A `.glb`'s binary chunk, which the first buffer without a URI
            names; empty for a `.gltf`.
        directory: Where a relative URI is read from, ending in a slash,
            or empty for the working directory.
        scene: The scene to add the nodes and meshes to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where.

    Raises:
        Error: If the JSON is not JSON or not glTF 2, an extension is
            required, a buffer, accessor, image, material, mesh or node
            is malformed or names something the file does not have, a
            primitive is not triangles, or an accessor is sparse.
    """
    var document = parse_json(text)
    var root = document.root()
    if document.kind(root) != OBJECT:
        raise Error("glTF: the document is not an object")
    _check_asset(document, root)
    var required = document.get(root, "extensionsRequired")
    if required != NO_NODE and document.length(required) > 0:
        raise Error(
            "glTF: the file requires an extension that is not read: "
            + document.string(document.at(required, 0))
        )
    var loader = _Loader(document^, bin, directory)
    loader.read_buffers()
    loader.read_textures()
    loader.read_materials(assets)
    loader.read_meshes(assets)
    loader.read_nodes(scene, assets)
    return loader.model.copy()


def _check_asset(document: JsonDocument, root: Int) raises:
    """Refuse a document that is not glTF 2.x."""
    var asset = document.get(root, "asset")
    if asset == NO_NODE or document.kind(asset) != OBJECT:
        raise Error("glTF: no asset object")
    var version = document.get(asset, "version")
    if version == NO_NODE or document.kind(version) != STRING:
        raise Error("glTF: no asset version")
    if not document.string(version).startswith("2."):
        raise Error("glTF: only version 2 is read")


def _le32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian unsigned word at `at`."""
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def decode_base64(text: String) raises -> List[UInt8]:
    """Return the bytes a base64 text encodes.

    Args:
        text: The text, in the standard alphabet, padded with `=` or
            not.

    Returns:
        The bytes.

    Raises:
        Error: If a character is outside the alphabet or the padding is
            misplaced.
    """
    var out = List[UInt8]()
    var held = 0
    var bits = 0
    var ended = False
    for byte in text.as_bytes():
        var value = Int(byte)
        var digit: Int
        if value >= 65 and value <= 90:
            digit = value - 65
        elif value >= 97 and value <= 122:
            digit = value - 71
        elif value >= 48 and value <= 57:
            digit = value + 4
        elif value == 43:
            digit = 62
        elif value == 47:
            digit = 63
        elif value == 61:
            ended = True
            continue
        else:
            raise Error("base64: a character outside the alphabet")
        if ended:
            raise Error("base64: a digit after the padding")
        held = (held << 6) | digit
        bits += 6
        if bits >= 8:
            bits -= 8
            out.append(UInt8((held >> bits) & 0xFF))
            held &= (1 << bits) - 1
    return out^


def _data_uri_bytes(uri: String) raises -> List[UInt8]:
    """Return the bytes of a `data:` URI, which must be base64."""
    var comma = uri.find(",")
    if comma < 0:
        raise Error("glTF: a data URI without a comma")
    var header = _slice(uri, 0, comma)
    if not header.endswith(";base64"):
        raise Error("glTF: only a base64 data URI is read")
    return decode_base64(_slice(uri, comma + 1, uri.byte_length()))


def _slice(text: String, start: Int, end: Int) -> String:
    """Return the bytes of `text` from `start` to `end` as a string."""
    var out = List[UInt8]()
    var bytes = text.as_bytes()
    for index in range(start, end):
        out.append(bytes[index])
    return String(unsafe_from_utf8=out)


def _uri_bytes(uri: String, directory: String) raises -> List[UInt8]:
    """Return the bytes a URI names: decoded from a `data:` URI, or read
    from a file beside the document."""
    if uri.startswith("data:"):
        return _data_uri_bytes(uri)
    if uri.find(":") >= 0:
        raise Error("glTF: only a data URI or a relative path is read: " + uri)
    return Path(directory + uri).read_bytes()


struct _Loader(Movable):
    """The document, its bytes, and the ids handed out so far."""

    var document: JsonDocument
    var bin: List[UInt8]
    var directory: String
    var buffers: List[List[UInt8]]
    var model: GltfModel
    # The material a primitive without one draws with, made once.
    var default_material: MaterialId
    var has_default_material: Bool
    # A material with vertex colors on, made once per material that a
    # colored primitive asks for; `NO_MATERIAL_VARIANT` until then.
    var tinted_materials: List[MaterialId]
    var has_tinted: List[Bool]
    # Each glTF texture's image index and sampler settings, resolved once
    # and read twice when both a color and a data map ask for it.
    var texture_images: List[Int]
    var texture_wraps: List[Wrap]
    var texture_filters: List[Filter]
    var texture_mipmapped: List[Bool]

    def __init__(
        out self,
        var document: JsonDocument,
        bin: List[UInt8],
        directory: String,
    ):
        self.document = document^
        self.bin = bin.copy()
        self.directory = directory
        self.buffers = List[List[UInt8]]()
        self.model = GltfModel()
        self.default_material = MaterialId(0)
        self.has_default_material = False
        self.tinted_materials = List[MaterialId]()
        self.has_tinted = List[Bool]()
        self.texture_images = List[Int]()
        self.texture_wraps = List[Wrap]()
        self.texture_filters = List[Filter]()
        self.texture_mipmapped = List[Bool]()

    def list(self, key: String) raises -> Int:
        """Return the root's array under `key`, or `NO_NODE`."""
        var found = self.document.get(self.document.root(), key)
        if found != NO_NODE and self.document.kind(found) != ARRAY:
            raise Error("glTF: " + key + " must be an array")
        return found

    def count(self, key: String) raises -> Int:
        """Return how many entries the root's array under `key` has."""
        var found = self.list(key)
        if found == NO_NODE:
            return 0
        return self.document.length(found)

    def entry(self, key: String, index: Int) raises -> Int:
        """Return one object of the root's array under `key`."""
        var found = self.list(key)
        if (
            found == NO_NODE
            or index < 0
            or index >= self.document.length(found)
        ):
            raise Error("glTF: no " + key + " entry at index " + String(index))
        var node = self.document.at(found, index)
        if self.document.kind(node) != OBJECT:
            raise Error("glTF: a " + key + " entry must be an object")
        return node

    def integer(self, node: Int, key: String, default: Int) raises -> Int:
        """Return an object's whole number under `key`, or `default`."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return default
        return self.document.integer(found)

    def required_integer(self, node: Int, key: String) raises -> Int:
        """Return an object's whole number under `key`, which must be there."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            raise Error("glTF: " + key + " is required")
        return self.document.integer(found)

    def number(
        self, node: Int, key: String, default: Float32
    ) raises -> Float32:
        """Return an object's number under `key`, or `default`."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return default
        var value = Float32(self.document.number(found))
        if not isfinite(value):
            raise Error("glTF: " + key + " must be finite")
        return value

    def text(self, node: Int, key: String) raises -> String:
        """Return an object's string under `key`, or empty."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return String()
        return self.document.string(found)

    def flag(self, node: Int, key: String) raises -> Bool:
        """Return an object's boolean under `key`, or False."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return False
        return self.document.boolean(found)

    def numbers(
        self, node: Int, key: String, count: Int
    ) raises -> List[Float32]:
        """Return an object's array of `count` numbers under `key`, or an
        empty list when the key is absent."""
        var found = self.document.get(node, key)
        var out = List[Float32]()
        if found == NO_NODE:
            return out^
        if (
            self.document.kind(found) != ARRAY
            or self.document.length(found) != count
        ):
            raise Error(
                "glTF: " + key + " must hold " + String(count) + " numbers"
            )
        for index in range(count):  # pragma: no branch
            var value = Float32(
                self.document.number(self.document.at(found, index))
            )
            if not isfinite(value):
                raise Error("glTF: " + key + " must be finite")
            out.append(value)
        return out^

    # --- buffers and accessors ----------------------------------------------

    def read_buffers(mut self) raises:
        """Read every buffer's bytes: the binary chunk for the first without
        a URI, the URI otherwise."""
        for index in range(self.count("buffers")):
            var buffer = self.entry("buffers", index)
            var length = self.required_integer(buffer, "byteLength")
            var uri = self.text(buffer, "uri")
            var bytes: List[UInt8]
            if uri == "":
                if index != 0 or len(self.bin) == 0:
                    raise Error(
                        "glTF: only the first buffer of a .glb can have no URI"
                    )
                bytes = self.bin.copy()
            else:
                bytes = _uri_bytes(uri, self.directory)
            if len(bytes) < length:
                raise Error("glTF: a buffer is shorter than its byteLength")
            self.buffers.append(bytes^)

    def view_bytes(self, index: Int) raises -> Tuple[Int, Int, Int, Int]:
        """Return a buffer view's buffer, byte offset, byte length and byte
        stride, checked against the buffer."""
        var view = self.entry("bufferViews", index)
        var buffer = self.required_integer(view, "buffer")
        if buffer < 0 or buffer >= len(self.buffers):
            raise Error("glTF: a buffer view names a buffer that is not there")
        var offset = self.integer(view, "byteOffset", 0)
        var length = self.required_integer(view, "byteLength")
        var stride = self.integer(view, "byteStride", 0)
        if (
            offset < 0
            or length < 0
            or offset + length > len(self.buffers[buffer])
        ):
            raise Error("glTF: a buffer view runs past its buffer")
        return (buffer, offset, length, stride)

    def accessor_floats(
        mut self, index: Int
    ) raises -> Tuple[List[Float32], Int]:
        """Return an accessor's numbers as floats, normalized when it says
        so, and how many make one element."""
        var accessor = self.entry("accessors", index)
        if self.document.has(accessor, "sparse"):
            raise Error("glTF: a sparse accessor is not read")
        var component = self.required_integer(accessor, "componentType")
        var count = self.required_integer(accessor, "count")
        var kind = self.text(accessor, "type")
        var width = _components_of(kind)
        var size = _component_size(component)
        var normalized = self.flag(accessor, "normalized")
        var out = List[Float32]()
        var view_index = self.integer(accessor, "bufferView", -1)
        if view_index < 0:
            # No view: every number is zero, as the specification has it.
            for _ in range(count * width):
                out.append(0)
            return (out^, width)
        var view = self.view_bytes(view_index)
        var buffer = view[0]
        var start = view[1] + self.integer(accessor, "byteOffset", 0)
        var stride = view[3]
        if stride == 0:
            stride = size * width
        if count < 0 or (
            count > 0
            and start + (count - 1) * stride + size * width > view[1] + view[2]
        ):
            raise Error("glTF: an accessor runs past its buffer view")
        ref bytes = self.buffers[buffer]
        for element in range(count):
            var at = start + element * stride
            for lane in range(width):  # pragma: no branch
                out.append(
                    _read_component(
                        bytes, at + lane * size, component, normalized
                    )
                )
        return (out^, width)

    def accessor_indices(mut self, index: Int) raises -> List[Int]:
        """Return an accessor's numbers as whole indices."""
        var accessor = self.entry("accessors", index)
        var component = self.required_integer(accessor, "componentType")
        if (
            component != COMPONENT_UNSIGNED_BYTE
            and component != COMPONENT_UNSIGNED_SHORT
            and component != COMPONENT_UNSIGNED_INT
        ):
            raise Error("glTF: indices must be unsigned integers")
        if self.text(accessor, "type") != "SCALAR":
            raise Error("glTF: indices must be scalars")
        var floats = self.accessor_floats(index)
        var out = List[Int]()
        for at in range(len(floats[0])):
            out.append(Int(floats[0][at]))
        return out^

    # --- images and textures ------------------------------------------------

    def read_textures(mut self) raises:
        """Resolve each texture's image and sampler, reading nothing yet."""
        for index in range(self.count("textures")):
            var texture = self.entry("textures", index)
            var image = self.required_integer(texture, "source")
            if image < 0 or image >= self.count("images"):
                raise Error("glTF: a texture names an image that is not there")
            var wrap = REPEAT
            var filter = BILINEAR
            var mipmapped = True
            var sampler_index = self.integer(texture, "sampler", -1)
            if sampler_index >= 0:
                var sampler = self.entry("samplers", sampler_index)
                wrap = _wrap_of(self.integer(sampler, "wrapS", WRAP_REPEAT))
                if (
                    self.integer(sampler, "magFilter", FILTER_LINEAR)
                    == FILTER_NEAREST
                ):
                    filter = NEAREST
                var minifier = self.integer(
                    sampler, "minFilter", FILTER_LINEAR_MIPMAP_LINEAR
                )
                mipmapped = minifier >= FILTER_NEAREST_MIPMAP_NEAREST
            self.texture_images.append(image)
            self.texture_wraps.append(wrap)
            self.texture_filters.append(filter)
            self.texture_mipmapped.append(mipmapped)
            self.model.color_textures.append(NO_TEXTURE)
            self.model.data_textures.append(NO_TEXTURE)

    def image_bytes(self, index: Int) raises -> List[UInt8]:
        """Return an image's file bytes, from its URI or its buffer view."""
        var image = self.entry("images", index)
        var uri = self.text(image, "uri")
        if uri != "":
            return _uri_bytes(uri, self.directory)
        var view_index = self.integer(image, "bufferView", -1)
        if view_index < 0:
            raise Error("glTF: an image needs a uri or a bufferView")
        var view = self.view_bytes(view_index)
        var out = List[UInt8]()
        for at in range(view[1], view[1] + view[2]):
            out.append(self.buffers[view[0]][at])
        return out^

    def texture(
        mut self, index: Int, space: ColorSpace, mut assets: Assets
    ) raises -> TextureId:
        """Return a glTF texture as read in one color space, decoding its
        image the first time that space asks for it."""
        # Never negative: `texture_reference` refused that already.
        if index >= len(self.texture_images):
            raise Error("glTF: a material names a texture that is not there")
        if space == SRGB and self.model.color_textures[index] != NO_TEXTURE:
            return self.model.color_textures[index]
        if space == LINEAR and self.model.data_textures[index] != NO_TEXTURE:
            return self.model.data_textures[index]
        var bytes = self.image_bytes(self.texture_images[index])
        var image = decode_image(bytes)
        var built = texture_from(
            image,
            self.texture_wraps[index],
            self.texture_filters[index],
            space,
            self.texture_mipmapped[index],
        )
        # glTF's `v` runs down from the top: flipped here, as three.js
        # flips it with `flipY = false`.
        built.repeat = Vector2(1, -1)
        built.offset = Vector2(0, 1)
        var id = assets.textures.add(built^)
        if space == SRGB:
            self.model.color_textures[index] = id
        else:
            self.model.data_textures[index] = id
        return id

    def texture_reference(self, material: Int, key: String) raises -> Int:
        """Return the texture index a material's `key` object names, or -1."""
        var found = self.document.get(material, key)
        if found == NO_NODE:
            return -1
        if self.document.kind(found) != OBJECT:
            raise Error("glTF: " + key + " must be an object")
        if self.integer(found, "texCoord", 0) != 0:
            raise Error(
                "glTF: only the first set of texture coordinates is read"
            )
        var index = self.required_integer(found, "index")
        if index < 0:
            raise Error("glTF: a texture index must not be negative")
        return index

    # --- materials ----------------------------------------------------------

    def read_materials(mut self, mut assets: Assets) raises:
        """Build a standard material per glTF material."""
        for index in range(self.count("materials")):
            var material = self.entry("materials", index)
            var color = Color(255, 255, 255)
            var opacity = Float32(1)
            var map = NO_TEXTURE
            var roughness = Float32(1)
            var metalness = Float32(1)
            var roughness_map = NO_TEXTURE
            var pbr = self.document.get(material, "pbrMetallicRoughness")
            if pbr != NO_NODE:
                var factor = self.numbers(pbr, "baseColorFactor", 4)
                if len(factor) == 4:
                    color = FloatColor(
                        factor[0], factor[1], factor[2], 1
                    ).encode()
                    opacity = factor[3]
                var base = self.texture_reference(pbr, "baseColorTexture")
                if base >= 0:
                    map = self.texture(base, SRGB, assets)
                roughness = self.number(pbr, "roughnessFactor", 1)
                metalness = self.number(pbr, "metallicFactor", 1)
                var both = self.texture_reference(
                    pbr, "metallicRoughnessTexture"
                )
                if both >= 0:
                    roughness_map = self.texture(both, LINEAR, assets)
            var normal_map = NO_TEXTURE
            var normal_scale = Float32(1)
            var normal = self.texture_reference(material, "normalTexture")
            if normal >= 0:
                normal_map = self.texture(normal, LINEAR, assets)
                normal_scale = self.number(
                    self.document.get(material, "normalTexture"), "scale", 1
                )
            var emissive = Color(0, 0, 0)
            var glow = self.numbers(material, "emissiveFactor", 3)
            if len(glow) == 3:
                emissive = FloatColor(glow[0], glow[1], glow[2], 1).encode()
            var emissive_map = NO_TEXTURE
            var shine = self.texture_reference(material, "emissiveTexture")
            if shine >= 0:
                emissive_map = self.texture(shine, SRGB, assets)
            var side = FRONT_SIDE
            if self.flag(material, "doubleSided"):
                side = DOUBLE_SIDE
            var mode = self.text(material, "alphaMode")
            var transparent = mode == "BLEND"
            var built = standard_material(
                color,
                map=map,
                roughness=roughness,
                metalness=metalness,
                side=side,
                opacity=opacity,
                transparent=transparent,
                roughness_map=roughness_map,
                metalness_map=roughness_map,
                normal_map=normal_map,
                normal_scale=Vector2(normal_scale, normal_scale),
                emissive=emissive,
                emissive_map=emissive_map,
            )
            if mode == "MASK":
                built.alpha_test = self.number(
                    material, "alphaCutoff", DEFAULT_ALPHA_CUTOFF
                )
            elif mode != "" and mode != "OPAQUE" and mode != "BLEND":
                raise Error("glTF: alphaMode must be OPAQUE, MASK or BLEND")
            self.model.materials.append(assets.materials.add(built))
            self.tinted_materials.append(MaterialId(0))
            self.has_tinted.append(False)

    def material_for(
        mut self, index: Int, tinted: Bool, mut assets: Assets
    ) raises -> MaterialId:
        """Return the material a primitive draws with: the file's, the
        default when it names none, and a copy with vertex colors on when
        the primitive carries them."""
        if index < 0:
            if not self.has_default_material:
                self.default_material = assets.materials.add(
                    standard_material(Color(255, 255, 255))
                )
                self.has_default_material = True
            if not tinted:
                return self.default_material
            var plain = assets.materials.get(self.default_material)
            plain.vertex_colors = True
            return assets.materials.add(plain)
        if index >= len(self.model.materials):
            raise Error("glTF: a primitive names a material that is not there")
        if not tinted:
            return self.model.materials[index]
        if not self.has_tinted[index]:
            var copy = assets.materials.get(self.model.materials[index])
            copy.vertex_colors = True
            self.tinted_materials[index] = assets.materials.add(copy)
            self.has_tinted[index] = True
        return self.tinted_materials[index]

    # --- meshes -------------------------------------------------------------

    def read_meshes(mut self, mut assets: Assets) raises:
        """Build one geometry per primitive of every mesh."""
        for index in range(self.count("meshes")):
            var mesh = self.entry("meshes", index)
            var primitives = self.document.get(mesh, "primitives")
            if primitives == NO_NODE or self.document.kind(primitives) != ARRAY:
                raise Error("glTF: a mesh needs a primitives array")
            self.model.first_primitives.append(len(self.model.geometries))
            var count = self.document.length(primitives)
            self.model.primitive_counts.append(count)
            for slot in range(count):
                var primitive = self.document.at(primitives, slot)
                self.model.geometries.append(
                    assets.geometries.add(self.geometry_of(primitive))
                )

    def geometry_of(mut self, primitive: Int) raises -> BufferGeometry:
        """Build a primitive's geometry."""
        if self.integer(primitive, "mode", MODE_TRIANGLES) != MODE_TRIANGLES:
            raise Error("glTF: only a primitive of triangles is read")
        var attributes = self.document.get(primitive, "attributes")
        if attributes == NO_NODE or self.document.kind(attributes) != OBJECT:
            raise Error("glTF: a primitive needs attributes")
        var geometry = BufferGeometry()
        var position = self.integer(attributes, "POSITION", -1)
        if position < 0:
            raise Error("glTF: a primitive needs a POSITION")
        var positions = self.accessor_floats(position)
        if positions[1] != 3:
            raise Error("glTF: POSITION must be a VEC3")
        geometry.set_attribute(
            String(POSITION), BufferAttribute(positions[0].copy(), 3)
        )
        var normal = self.integer(attributes, "NORMAL", -1)
        if normal >= 0:
            var normals = self.accessor_floats(normal)
            if normals[1] != 3:
                raise Error("glTF: NORMAL must be a VEC3")
            geometry.set_attribute(
                String(NORMAL), BufferAttribute(normals[0].copy(), 3)
            )
        var uv = self.integer(attributes, "TEXCOORD_0", -1)
        if uv >= 0:
            var uvs = self.accessor_floats(uv)
            if uvs[1] != 2:
                raise Error("glTF: TEXCOORD_0 must be a VEC2")
            geometry.set_attribute(
                String(UV), BufferAttribute(uvs[0].copy(), 2)
            )
        var color = self.integer(attributes, "COLOR_0", -1)
        if color >= 0:
            var colors = self.accessor_floats(color)
            if colors[1] != 3 and colors[1] != 4:
                raise Error("glTF: COLOR_0 must be a VEC3 or a VEC4")
            geometry.set_attribute(
                String(COLOR), BufferAttribute(colors[0].copy(), colors[1])
            )
        var indices = self.integer(primitive, "indices", -1)
        if indices >= 0:
            geometry.set_index(self.accessor_indices(indices))
        return geometry^

    # --- nodes --------------------------------------------------------------

    def read_nodes(mut self, mut scene: Scene, mut assets: Assets) raises:
        """Walk the default scene's roots and add every node they reach,
        each after its parent, with its meshes."""
        var count = self.count("nodes")
        for _ in range(count):
            self.model.nodes.append(NO_PARENT)
            self.model.node_names.append(String())
        for index in range(count):
            self.model.node_names[index] = self.text(
                self.entry("nodes", index), "name"
            )
        self.model.first_mesh = len(scene.meshes)
        var scenes = self.count("scenes")
        if scenes == 0:
            return
        var chosen = self.integer(self.document.root(), "scene", 0)
        var top = self.entry("scenes", chosen)
        var roots = self.document.get(top, "nodes")
        if roots == NO_NODE:
            return
        if self.document.kind(roots) != ARRAY:
            raise Error("glTF: a scene's nodes must be an array")
        for slot in range(self.document.length(roots)):
            var root = self.document.integer(self.document.at(roots, slot))
            self.place(root, NO_PARENT, scene, assets)
        self.model.mesh_count = len(scene.meshes) - self.model.first_mesh

    def place(
        mut self,
        index: Int,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add one node under its parent, then its meshes, then its
        children."""
        if index < 0 or index >= len(self.model.nodes):
            raise Error("glTF: a node index that is not there")
        # A hierarchy that loops reaches a node twice before it can go
        # deeper than there are nodes, so this is the one check needed.
        if self.model.nodes[index] != NO_PARENT:
            raise Error("glTF: a node is reached twice")
        var node = self.entry("nodes", index)
        var placed = Object3D()
        var matrix = self.numbers(node, "matrix", 16)
        if len(matrix) == 16:
            _apply_matrix(placed, matrix)
        else:
            var translation = self.numbers(node, "translation", 3)
            if len(translation) == 3:
                placed.set_position(
                    translation[0], translation[1], translation[2]
                )
            var rotation = self.numbers(node, "rotation", 4)
            if len(rotation) == 4:
                placed.set_quaternion(
                    Quaternion(
                        rotation[0], rotation[1], rotation[2], rotation[3]
                    )
                )
            var scale = self.numbers(node, "scale", 3)
            if len(scale) == 3:
                placed.set_scale(scale[0], scale[1], scale[2])
        var id: NodeId
        if parent == NO_PARENT:
            id = scene.add(placed^)
        else:
            id = scene.attach(placed^, parent)
        self.model.nodes[index] = id
        var mesh = self.integer(node, "mesh", -1)
        if mesh >= 0:
            self.draw(mesh, id, scene, assets)
        var children = self.document.get(node, "children")
        if children != NO_NODE:
            if self.document.kind(children) != ARRAY:
                raise Error("glTF: a node's children must be an array")
            for slot in range(self.document.length(children)):
                var child = self.document.integer(
                    self.document.at(children, slot)
                )
                self.place(child, id, scene, assets)

    def draw(
        mut self, mesh: Int, node: NodeId, mut scene: Scene, mut assets: Assets
    ) raises:
        """Add a `Mesh` per primitive of a glTF mesh at a node."""
        # `place` asks only for a mesh the node named, zero or more.
        if mesh >= len(self.model.first_primitives):
            raise Error("glTF: a node names a mesh that is not there")
        var entry = self.entry("meshes", mesh)
        var primitives = self.document.get(entry, "primitives")
        for slot in range(self.model.primitive_counts[mesh]):
            var primitive = self.document.at(primitives, slot)
            var geometry = self.model.geometries[
                self.model.first_primitives[mesh] + slot
            ]
            var tinted = assets.geometries.get(geometry).has_attribute(
                String(COLOR)
            )
            var material = self.material_for(
                self.integer(primitive, "material", -1), tinted, assets
            )
            scene.add_mesh(Mesh(geometry, material, node))


def _components_of(kind: String) raises -> Int:
    """Return how many numbers an accessor type holds."""
    if kind == "SCALAR":
        return 1
    if kind == "VEC2":
        return 2
    if kind == "VEC3":
        return 3
    if kind == "VEC4" or kind == "MAT2":
        return 4
    if kind == "MAT3":
        return 9
    if kind == "MAT4":
        return 16
    raise Error("glTF: an accessor type that is not known: " + kind)


def _component_size(component: Int) raises -> Int:
    """Return how many bytes a component type takes."""
    if component == COMPONENT_BYTE or component == COMPONENT_UNSIGNED_BYTE:
        return 1
    if component == COMPONENT_SHORT or component == COMPONENT_UNSIGNED_SHORT:
        return 2
    if component == COMPONENT_UNSIGNED_INT or component == COMPONENT_FLOAT:
        return 4
    raise Error("glTF: a component type that is not known")


def _read_component(
    bytes: List[UInt8], at: Int, component: Int, normalized: Bool
) -> Float32:
    """Return one component as a float, normalized to zero through one or
    minus one through one when the accessor says so."""
    if component == COMPONENT_FLOAT:
        return bitcast[DType.float32](UInt32(_le32(bytes, at)))
    if component == COMPONENT_UNSIGNED_BYTE:
        var value = Float32(Int(bytes[at]))
        if normalized:
            return value / 255
        return value
    if component == COMPONENT_BYTE:
        var raw = Int(bytes[at])
        if raw >= 128:
            raw -= 256
        var value = Float32(raw)
        if normalized:
            return max(value / 127, Float32(-1))
        return value
    if component == COMPONENT_UNSIGNED_SHORT:
        var value = Float32(Int(bytes[at]) | (Int(bytes[at + 1]) << 8))
        if normalized:
            return value / 65535
        return value
    if component == COMPONENT_SHORT:
        var raw = Int(bytes[at]) | (Int(bytes[at + 1]) << 8)
        if raw >= 32768:
            raw -= 65536
        var value = Float32(raw)
        if normalized:
            return max(value / 32767, Float32(-1))
        return value
    # `COMPONENT_UNSIGNED_INT`, the last `_component_size` admits.
    return Float32(_le32(bytes, at))


def _wrap_of(mode: Int) raises -> Wrap:
    """Return a sampler's wrap as a texture's."""
    if mode == WRAP_REPEAT:
        return REPEAT
    if mode == WRAP_CLAMP:
        return CLAMP
    if mode == WRAP_MIRROR:
        return MIRROR
    raise Error("glTF: a wrap mode that is not known")


def decode_image(bytes: List[UInt8]) raises -> DecodedImage:
    """Return an image decoded by what its first bytes say it is.

    Args:
        bytes: A PNG or a JPEG file.

    Returns:
        The image.

    Raises:
        Error: If the bytes begin as neither, or the decoder refuses them.
    """
    if len(bytes) >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50:
        return decode_png(bytes)
    if len(bytes) >= 2 and bytes[0] == 0xFF and bytes[1] == 0xD8:
        return decode_jpeg(bytes)
    raise Error("glTF: an image that is neither PNG nor JPEG")


def _apply_matrix(mut node: Object3D, matrix: List[Float32]) raises:
    """Set a node from a column-major matrix, decomposed as three.js's
    `Matrix4.decompose` decomposes it: the scale is each column's
    length, negated all three when the determinant is negative, and the
    rotation is what is left once the columns are divided by it."""
    var m = Matrix4()
    for index in range(16):  # pragma: no branch
        m.elements[index] = matrix[index]
    var sx = _column_length(matrix, 0)
    var sy = _column_length(matrix, 4)
    var sz = _column_length(matrix, 8)
    if m.determinant() < 0:
        sx = -sx
    if sx == 0 or sy == 0 or sz == 0:
        raise Error("glTF: a node matrix that flattens an axis")
    var rotation = Matrix4()
    for row in range(3):  # pragma: no branch
        rotation.elements[row] = matrix[row] / sx
        rotation.elements[4 + row] = matrix[4 + row] / sy
        rotation.elements[8 + row] = matrix[8 + row] / sz
    node.set_position(matrix[12], matrix[13], matrix[14])
    node.set_quaternion(Quaternion.from_matrix(rotation))
    node.set_scale(sx, sy, sz)


def _column_length(matrix: List[Float32], start: Int) -> Float32:
    """Return the length of a column's first three entries."""
    return sqrt(
        matrix[start] * matrix[start]
        + matrix[start + 1] * matrix[start + 1]
        + matrix[start + 2] * matrix[start + 2]
    )
