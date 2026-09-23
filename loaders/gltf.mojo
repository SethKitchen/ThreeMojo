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

**Skins, morph targets and animations.** A node with a `skin` draws each
primitive as a `SkinnedMesh`, its skeleton made of the joints' nodes and
the skin's inverse bind matrices, bound at the identity as three.js's
`GLTFLoader` binds it. `JOINTS_0` and `WEIGHTS_0` become `skinIndex` and
`skinWeight`, the weights normalized as three.js's `normalizeSkinWeights`
does. A primitive's `targets` become the geometry's morph targets, which
glTF holds as offsets, so `morph_relative` is set; `weights` on the node,
or on the mesh when the node has none, become the influences. Each
animation becomes an `AnimationClip`: a `translation`, `rotation` or
`scale` channel a track on the node, and a `weights` channel one
`MORPH_INFLUENCE` track per mesh and target. `STEP` and `LINEAR` samplers
keep their names, and `CUBICSPLINE` becomes `CUBIC_SPLINE` with the
tangents split out of the keys.

**Cameras.** A node with a `camera` gets a `PerspectiveCamera` or an
`OrthographicCamera` riding it, as three.js builds one: a perspective
camera with no `aspectRatio` is square and one with no `zfar` ends at two
million meters, and an orthographic one spans `xmag` and `ymag` either
side of its axis.

**Sparse accessors.** The values a sparse accessor names replace the
elements of its buffer view, or of zeros when it has none.

**Where this differs from three.js.** A morph target without a `POSITION`
moves nothing here, where three.js adds the base positions to it as if
they were offsets. A `weights` channel drives the meshes on its own node,
not those of the node's children, and none of a skinned mesh's, since the
mixer drives morph influences on `scene.meshes` alone. A channel on a node
the default scene does not reach is left out, and so is an animation left
with no channel. A skin joint the scene does not reach, a morph color, and
more than `MAX_MORPH_TARGETS` targets are refused.

**Not ported.** Every extension: a file whose `extensionsRequired` names
one is refused, since it could not be drawn as meant, and one that only
uses an extension is read without it. Only triangles are read; a primitive
of points, lines or strips is refused.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    CUBIC_SPLINE,
    LINEAR as LINEAR_KEYS,
    QUATERNION,
    SCALE,
    STEP,
    Interpolation,
    KeyframeTrack,
    MORPH_INFLUENCE,
    MeshIndex,
    TrackKind,
    TrackTarget,
    morph_target,
    node_target,
    POSITION as TRANSLATION,
)
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    MAX_MORPH_TARGETS,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
)
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
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.jpeg import decode as decode_jpeg
from render.png import DecodedImage, decode as decode_png
from render.srgb import LINEAR, SRGB, ColorSpace
from render.tga import decode as decode_tga
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
from units.si import Angle, Duration, Length, METER, RADIAN, SECOND

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

# What three.js's `GLTFLoader` gives a perspective camera that names no
# aspect ratio, and where it ends one that names no far plane: glTF's
# infinite projection, which a `PerspectiveCamera` cannot hold.
comptime DEFAULT_ASPECT = Float32(1)
comptime DEFAULT_FAR = Float32(2e6)


@fieldwise_init
struct GltfCameraKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of glTF's two projections a camera has, as a type rather than a
    bare int.

    `GltfCamera.perspective` and `GltfCamera.orthographic` stop
    `GltfCameraKind(9)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `GLTF_PERSPECTIVE` or `GLTF_ORTHOGRAPHIC`."""
        return self == GLTF_PERSPECTIVE or self == GLTF_ORTHOGRAPHIC


# A camera of glTF's `perspective` type, three.js's `PerspectiveCamera`.
comptime GLTF_PERSPECTIVE = GltfCameraKind(0)
# A camera of glTF's `orthographic` type, three.js's `OrthographicCamera`.
comptime GLTF_ORTHOGRAPHIC = GltfCameraKind(1)


struct GltfCamera(Copyable, Movable):
    """One camera a node of the file carries, already riding that node."""

    var kind: GltfCameraKind
    # The camera's index in the file's `cameras`, and its `name`.
    var index: Int
    var name: String
    # The scene node the camera rides.
    var node: NodeId
    var _perspective: Optional[PerspectiveCamera]
    var _orthographic: Optional[OrthographicCamera]

    def __init__(
        out self,
        index: Int,
        name: String,
        node: NodeId,
        camera: PerspectiveCamera,
    ):
        """Hold a perspective camera.

        Args:
            index: The camera's index in the file.
            name: The camera's name, or empty.
            node: The scene node it rides.
            camera: The camera.
        """
        self.kind = GLTF_PERSPECTIVE
        self.index = index
        self.name = name
        self.node = node
        self._perspective = camera
        self._orthographic = None

    def __init__(
        out self,
        index: Int,
        name: String,
        node: NodeId,
        var camera: OrthographicCamera,
    ):
        """Hold an orthographic camera.

        Args:
            index: The camera's index in the file.
            name: The camera's name, or empty.
            node: The scene node it rides.
            camera: The camera, consumed.
        """
        self.kind = GLTF_ORTHOGRAPHIC
        self.index = index
        self.name = name
        self.node = node
        self._perspective = None
        self._orthographic = camera^

    def perspective(self) raises -> PerspectiveCamera:
        """Return the camera as a perspective camera.

        Returns:
            The camera, riding its node.

        Raises:
            Error: If the kind is not one there is, or it is not
                `GLTF_PERSPECTIVE`, or no perspective camera is held.
        """
        if not self.kind.is_valid():
            raise Error("glTF: a camera kind that is not known")
        if self.kind != GLTF_PERSPECTIVE:
            raise Error("glTF: the camera is not a perspective camera")
        if not Bool(self._perspective):
            raise Error("glTF: the camera holds no perspective camera")
        return self._perspective.value()

    def orthographic(self) raises -> OrthographicCamera:
        """Return the camera as an orthographic camera.

        Returns:
            The camera, riding its node.

        Raises:
            Error: If the kind is not one there is, or it is not
                `GLTF_ORTHOGRAPHIC`, or no orthographic camera is held.
        """
        if not self.kind.is_valid():
            raise Error("glTF: a camera kind that is not known")
        if self.kind != GLTF_ORTHOGRAPHIC:
            raise Error("glTF: the camera is not an orthographic camera")
        if not Bool(self._orthographic):
            raise Error("glTF: the camera holds no orthographic camera")
        return self._orthographic.value().copy()


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
    # The same for the skinned meshes this file added to
    # `scene.skinned_meshes`.
    var first_skinned_mesh: Int
    var skinned_mesh_count: Int
    # One entry per node that carries a camera and that the loaded scene
    # reaches, in the order the nodes were placed.
    var cameras: List[GltfCamera]
    # One clip per glTF animation that drives something the loaded scene
    # reaches, in the file's order.
    var animations: List[AnimationClip]

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
        self.first_skinned_mesh = 0
        self.skinned_mesh_count = 0
        self.cameras = List[GltfCamera]()
        self.animations = List[AnimationClip]()

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
            required, a buffer, accessor, image, material, mesh, node,
            skin, camera or animation is malformed or names something the
            file does not have, a primitive is not triangles, a skin names
            a joint the scene does not reach, or a camera, a skeleton, a
            morph target or a track is one its type refuses.
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
    loader.read_animations()
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
    # How many morph targets each glTF mesh's primitives carry.
    var morph_counts: List[Int]
    # Per glTF node, the indices in `scene.meshes` of the meshes drawn at
    # it, which a `weights` channel drives.
    var node_meshes: List[List[Int]]
    # Each skinned node waiting for every joint to be placed: its glTF
    # index and the scene node it became.
    var skinned_nodes: List[Int]
    var skinned_ids: List[NodeId]

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
        self.morph_counts = List[Int]()
        self.node_meshes = List[List[Int]]()
        self.skinned_nodes = List[Int]()
        self.skinned_ids = List[NodeId]()

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

    def required_number(self, node: Int, key: String) raises -> Float32:
        """Return an object's number under `key`, which must be there."""
        if not self.document.has(node, key):
            raise Error("glTF: " + key + " is required")
        return self.number(node, key, 0)

    def number_list(self, node: Int, key: String) raises -> List[Float32]:
        """Return an object's array of numbers under `key`, of any length,
        or an empty list when the key is absent."""
        var found = self.document.get(node, key)
        var out = List[Float32]()
        if found == NO_NODE:
            return out^
        if self.document.kind(found) != ARRAY:
            raise Error("glTF: " + key + " must be an array of numbers")
        for index in range(self.document.length(found)):
            var value = Float32(
                self.document.number(self.document.at(found, index))
            )
            if not isfinite(value):
                raise Error("glTF: " + key + " must be finite")
            out.append(value)
        return out^

    def object_at(self, array: Int, index: Int) raises -> Int:
        """Return one entry of an array, which must be an object."""
        var node = self.document.at(array, index)
        if self.document.kind(node) != OBJECT:
            raise Error("glTF: an entry that must be an object is not")
        return node

    def array_of(self, node: Int, key: String) raises -> Int:
        """Return an object's array under `key`, which must be there."""
        var found = self.document.get(node, key)
        if found == NO_NODE or self.document.kind(found) != ARRAY:
            raise Error("glTF: " + key + " must be an array")
        return found

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
        so, and how many make one element, with its sparse values put in
        place."""
        var accessor = self.entry("accessors", index)
        var component = self.required_integer(accessor, "componentType")
        var count = self.required_integer(accessor, "count")
        var kind = self.text(accessor, "type")
        var width = _components_of(kind)
        var size = _component_size(component)
        var normalized = self.flag(accessor, "normalized")
        var out = List[Float32]()
        var view_index = self.integer(accessor, "bufferView", -1)
        if count < 0:
            raise Error("glTF: an accessor's count must not be negative")
        if view_index < 0:
            # No view: every number is zero, as the specification has it.
            for _ in range(count * width):
                out.append(0)
        else:
            var view = self.view_bytes(view_index)
            var start = view[1] + self.integer(accessor, "byteOffset", 0)
            var stride = view[3]
            if stride == 0:
                stride = size * width
            if (
                count > 0
                and start + (count - 1) * stride + size * width
                > view[1] + view[2]
            ):
                raise Error("glTF: an accessor runs past its buffer view")
            ref bytes = self.buffers[view[0]]
            for element in range(count):
                var at = start + element * stride
                for lane in range(width):  # pragma: no branch
                    out.append(
                        _read_component(
                            bytes, at + lane * size, component, normalized
                        )
                    )
        var sparse = self.document.get(accessor, "sparse")
        if sparse != NO_NODE:
            self.apply_sparse(sparse, out, count, width, component, normalized)
        return (out^, width)

    def sparse_view(self, part: Int, length: Int) raises -> Tuple[Int, Int]:
        """Return the buffer and the first byte of a sparse accessor's
        `indices` or `values`, checked to hold `length` bytes."""
        var view_index = self.required_integer(part, "bufferView")
        var view = self.view_bytes(view_index)
        var offset = self.integer(part, "byteOffset", 0)
        if offset < 0 or offset + length > view[2]:
            raise Error("glTF: a sparse accessor runs past its buffer view")
        return (view[0], view[1] + offset)

    def apply_sparse(
        self,
        sparse: Int,
        mut out: List[Float32],
        count: Int,
        width: Int,
        component: Int,
        normalized: Bool,
    ) raises:
        """Put a sparse accessor's values over the elements its indices
        name, as three.js's `GLTFLoader` does."""
        if self.document.kind(sparse) != OBJECT:
            raise Error("glTF: sparse must be an object")
        var changed = self.required_integer(sparse, "count")
        if changed < 1 or changed > count:
            raise Error(
                "glTF: a sparse count must be at least one and at most the"
                " accessor's"
            )
        var indices = self.document.get(sparse, "indices")
        var values = self.document.get(sparse, "values")
        if (
            indices == NO_NODE
            or values == NO_NODE
            or self.document.kind(indices) != OBJECT
            or self.document.kind(values) != OBJECT
        ):
            raise Error("glTF: sparse needs indices and values objects")
        var index_type = self.required_integer(indices, "componentType")
        if (
            index_type != COMPONENT_UNSIGNED_BYTE
            and index_type != COMPONENT_UNSIGNED_SHORT
            and index_type != COMPONENT_UNSIGNED_INT
        ):
            raise Error("glTF: sparse indices must be unsigned integers")
        var index_size = _component_size(index_type)
        var size = _component_size(component)
        var found = self.sparse_view(indices, changed * index_size)
        var what = self.sparse_view(values, changed * width * size)
        ref index_bytes = self.buffers[found[0]]
        ref value_bytes = self.buffers[what[0]]
        var last = -1
        for slot in range(changed):  # pragma: no branch
            var element = Int(
                _read_component(
                    index_bytes,
                    found[1] + slot * index_size,
                    index_type,
                    False,
                )
            )
            # The specification has them strictly rising, which also keeps
            # each one inside the accessor once the last is.
            if element <= last or element >= count:
                raise Error(
                    "glTF: sparse indices must rise and stay inside the"
                    " accessor"
                )
            last = element
            for lane in range(width):  # pragma: no branch
                out[element * width + lane] = _read_component(
                    value_bytes,
                    what[1] + (slot * width + lane) * size,
                    component,
                    normalized,
                )

    def component_of(self, index: Int) raises -> Int:
        """Return an accessor's component type."""
        return self.required_integer(
            self.entry("accessors", index), "componentType"
        )

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
            var targets = 0
            for slot in range(count):
                var primitive = self.document.at(primitives, slot)
                var geometry = self.geometry_of(primitive)
                if slot == 0:
                    targets = geometry.morph_count()
                elif geometry.morph_count() != targets:
                    raise Error(
                        "glTF: every primitive of a mesh must carry as many"
                        " morph targets"
                    )
                self.model.geometries.append(assets.geometries.add(geometry^))
            self.morph_counts.append(targets)

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
        var joints = self.integer(attributes, "JOINTS_0", -1)
        if joints >= 0:
            var component = self.component_of(joints)
            if (
                component != COMPONENT_UNSIGNED_BYTE
                and component != COMPONENT_UNSIGNED_SHORT
            ):
                raise Error(
                    "glTF: JOINTS_0 must be unsigned bytes or unsigned shorts"
                )
            var bones = self.accessor_floats(joints)
            if bones[1] != 4:
                raise Error("glTF: JOINTS_0 must be a VEC4")
            geometry.set_attribute(
                String(SKIN_INDEX), BufferAttribute(bones[0].copy(), 4)
            )
        var weights = self.integer(attributes, "WEIGHTS_0", -1)
        if weights >= 0:
            var shares = self.accessor_floats(weights)
            if shares[1] != 4:
                raise Error("glTF: WEIGHTS_0 must be a VEC4")
            geometry.set_attribute(
                String(SKIN_WEIGHT),
                BufferAttribute(_normalize_skin_weights(shares[0]), 4),
            )
        self.read_targets(primitive, geometry, len(positions[0]))
        var indices = self.integer(primitive, "indices", -1)
        if indices >= 0:
            geometry.set_index(self.accessor_indices(indices))
        return geometry^

    def read_targets(
        mut self, primitive: Int, mut geometry: BufferGeometry, floats: Int
    ) raises:
        """Add a primitive's morph targets to its geometry, as offsets.

        Every target carries normals when any one does, since a geometry
        takes them for all or for none; a target that names no `POSITION`
        or no `NORMAL` moves that attribute by nothing.
        """
        var targets = self.document.get(primitive, "targets")
        if targets == NO_NODE:
            return
        if self.document.kind(targets) != ARRAY:
            raise Error("glTF: a primitive's targets must be an array")
        var count = self.document.length(targets)
        var any_normals = False
        for slot in range(count):
            var target = self.object_at(targets, slot)
            if self.document.has(target, "COLOR_0"):
                raise Error("glTF: a morph target of colors is not read")
            if self.document.has(target, "NORMAL"):
                any_normals = True
        geometry.morph_relative = True
        for slot in range(count):
            var target = self.document.at(targets, slot)
            var moved = self.target_offsets(target, "POSITION", floats)
            if any_normals:
                var turned = self.target_offsets(target, "NORMAL", floats)
                geometry.add_morph_target(
                    BufferAttribute(moved^, 3), BufferAttribute(turned^, 3)
                )
            else:
                geometry.add_morph_target(BufferAttribute(moved^, 3))

    def target_offsets(
        mut self, target: Int, key: String, floats: Int
    ) raises -> List[Float32]:
        """Return one morph target's offsets under `key`, or zeros when it
        names none."""
        var index = self.integer(target, key, -1)
        if index < 0:
            return List[Float32](length=floats, fill=0)
        var offsets = self.accessor_floats(index)
        if offsets[1] != 3:
            raise Error("glTF: a morph target's " + key + " must be a VEC3")
        return offsets[0].copy()

    # --- nodes --------------------------------------------------------------

    def read_nodes(mut self, mut scene: Scene, mut assets: Assets) raises:
        """Walk the default scene's roots and add every node they reach,
        each after its parent, with its meshes and cameras, then the
        skinned meshes, once every joint is in the scene."""
        var count = self.count("nodes")
        for _ in range(count):
            self.model.nodes.append(NO_PARENT)
            self.model.node_names.append(String())
            self.node_meshes.append(List[Int]())
        for index in range(count):
            self.model.node_names[index] = self.text(
                self.entry("nodes", index), "name"
            )
        self.model.first_mesh = len(scene.meshes)
        self.model.first_skinned_mesh = len(scene.skinned_meshes)
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
        for slot in range(len(self.skinned_nodes)):
            var index = self.skinned_nodes[slot]
            var id = self.skinned_ids[slot]
            self.draw_skinned(index, id, scene, assets)
        self.model.skinned_mesh_count = (
            len(scene.skinned_meshes) - self.model.first_skinned_mesh
        )

    def place(
        mut self,
        index: Int,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add one node under its parent, then its meshes and its camera,
        then its children. A skinned node's meshes wait for its joints."""
        if index < 0 or index >= len(self.model.nodes):
            raise Error("glTF: a node index that is not there")
        # A hierarchy that loops reaches a node twice before it can go
        # deeper than there are nodes, so this is the one check needed.
        if self.model.nodes[index] != NO_PARENT:
            raise Error("glTF: a node is reached twice")
        var node = self.entry("nodes", index)
        var placed = Object3D()
        placed.name = self.model.node_names[index]
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
            if self.document.has(node, "skin"):
                self.skinned_nodes.append(index)
                self.skinned_ids.append(id)
            else:
                self.draw(mesh, index, id, scene, assets)
        var camera = self.integer(node, "camera", -1)
        if camera >= 0:
            self.model.cameras.append(self.camera_of(camera, id))
        var children = self.document.get(node, "children")
        if children != NO_NODE:
            if self.document.kind(children) != ARRAY:
                raise Error("glTF: a node's children must be an array")
            for slot in range(self.document.length(children)):
                var child = self.document.integer(
                    self.document.at(children, slot)
                )
                self.place(child, id, scene, assets)

    def morph_weights(self, node: Int, mesh: Int) raises -> List[Float32]:
        """Return the morph influences a node's mesh starts at: the node's
        `weights`, or the mesh's when the node has none, or none at all."""
        var weights = self.number_list(node, "weights")
        if not self.document.has(node, "weights"):
            weights = self.number_list(self.entry("meshes", mesh), "weights")
        if len(weights) > 0 and len(weights) != self.morph_counts[mesh]:
            raise Error("glTF: weights must hold one number per morph target")
        return weights^

    def draw(
        mut self,
        mesh: Int,
        index: Int,
        node: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add a `Mesh` per primitive of a glTF mesh at a node."""
        # `place` asks only for a mesh the node named, zero or more.
        if mesh >= len(self.model.first_primitives):
            raise Error("glTF: a node names a mesh that is not there")
        var weights = self.morph_weights(self.entry("nodes", index), mesh)
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
            var drawn = Mesh(geometry, material, node)
            for target in range(len(weights)):
                drawn.set_morph_influence(target, weights[target])
            self.node_meshes[index].append(len(scene.meshes))
            scene.add_mesh(drawn)

    # --- skins --------------------------------------------------------------

    def skeleton_of(mut self, skin: Int) raises -> Skeleton:
        """Build a skin's skeleton from its joints, which must all be in
        the scene, and its inverse bind matrices, or the identity for each
        joint when it names none."""
        var entry = self.entry("skins", skin)
        var joints = self.array_of(entry, "joints")
        var count = self.document.length(joints)
        var inverses = List[Float32]()
        var accessor = self.integer(entry, "inverseBindMatrices", -1)
        if accessor >= 0:
            var read = self.accessor_floats(accessor)
            if read[1] != 16 or len(read[0]) != count * 16:
                raise Error(
                    "glTF: inverseBindMatrices must be one MAT4 per joint"
                )
            inverses = read[0].copy()
        var bones = List[Bone]()
        for slot in range(count):
            var joint = self.document.integer(self.document.at(joints, slot))
            if joint < 0 or joint >= len(self.model.nodes):
                raise Error("glTF: a skin names a joint that is not there")
            var id = self.model.nodes[joint]
            if id == NO_PARENT:
                raise Error(
                    "glTF: a skin names a joint the loaded scene does not reach"
                )
            var inverse = Matrix4()
            if len(inverses) > 0:
                for element in range(16):  # pragma: no branch
                    inverse.elements[element] = inverses[slot * 16 + element]
            bones.append(Bone(id, inverse^))
        return Skeleton(bones^)

    def draw_skinned(
        mut self,
        index: Int,
        node: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add a `SkinnedMesh` per primitive of a skinned node's mesh, bound
        at the identity as three.js's `GLTFLoader` binds it."""
        var entry = self.entry("nodes", index)
        var mesh = self.required_integer(entry, "mesh")
        if mesh >= len(self.model.first_primitives):
            raise Error("glTF: a node names a mesh that is not there")
        var skeleton = self.skeleton_of(self.required_integer(entry, "skin"))
        var weights = self.morph_weights(entry, mesh)
        var primitives = self.document.get(
            self.entry("meshes", mesh), "primitives"
        )
        for slot in range(self.model.primitive_counts[mesh]):
            var primitive = self.document.at(primitives, slot)
            var geometry = self.model.geometries[
                self.model.first_primitives[mesh] + slot
            ]
            ref shape = assets.geometries.get(geometry)
            var bones = shape.has_attribute(String(SKIN_INDEX))
            var shares = shape.has_attribute(String(SKIN_WEIGHT))
            if not bones or not shares:
                raise Error(
                    "glTF: a skinned primitive needs JOINTS_0 and WEIGHTS_0"
                )
            var tinted = shape.has_attribute(String(COLOR))
            var material = self.material_for(
                self.integer(primitive, "material", -1), tinted, assets
            )
            var drawn = SkinnedMesh(geometry, material, node, skeleton.copy())
            for target in range(len(weights)):
                drawn.set_morph_influence(target, weights[target])
            scene.add_skinned_mesh(drawn^)

    # --- cameras ------------------------------------------------------------

    def camera_of(self, index: Int, node: NodeId) raises -> GltfCamera:
        """Build a glTF camera riding a scene node, as three.js's
        `GLTFLoader.loadCamera` builds it."""
        var entry = self.entry("cameras", index)
        var name = self.text(entry, "name")
        var kind = self.text(entry, "type")
        if kind == "perspective":
            var lens = self.document.get(entry, "perspective")
            if lens == NO_NODE or self.document.kind(lens) != OBJECT:
                raise Error("glTF: a perspective camera needs a perspective")
            var camera = PerspectiveCamera(
                Angle(self.required_number(lens, "yfov"), RADIAN),
                self.number(lens, "aspectRatio", DEFAULT_ASPECT),
                Length(self.required_number(lens, "znear"), METER),
                Length(self.number(lens, "zfar", DEFAULT_FAR), METER),
            )
            camera.attach(node)
            return GltfCamera(index, name, node, camera)
        if kind == "orthographic":
            var box = self.document.get(entry, "orthographic")
            if box == NO_NODE or self.document.kind(box) != OBJECT:
                raise Error(
                    "glTF: an orthographic camera needs an orthographic"
                )
            var x = self.required_number(box, "xmag")
            var y = self.required_number(box, "ymag")
            var camera = OrthographicCamera(
                Length(-x, METER),
                Length(x, METER),
                Length(y, METER),
                Length(-y, METER),
                Length(self.required_number(box, "znear"), METER),
                Length(self.required_number(box, "zfar"), METER),
            )
            camera.attach(node)
            return GltfCamera(index, name, node, camera^)
        raise Error("glTF: a camera type must be perspective or orthographic")

    # --- animations ---------------------------------------------------------

    def read_animations(mut self) raises:
        """Build one clip per animation that drives something the loaded
        scene reaches."""
        for index in range(self.count("animations")):
            var animation = self.entry("animations", index)
            var channels = self.array_of(animation, "channels")
            var samplers = self.array_of(animation, "samplers")
            var tracks = List[KeyframeTrack]()
            for slot in range(self.document.length(channels)):
                var channel = self.object_at(channels, slot)
                var sampler = self.required_integer(channel, "sampler")
                if sampler < 0 or sampler >= self.document.length(samplers):
                    raise Error(
                        "glTF: a channel names a sampler that is not there"
                    )
                var target = self.document.get(channel, "target")
                if target == NO_NODE or self.document.kind(target) != OBJECT:
                    raise Error("glTF: a channel needs a target object")
                self.channel_tracks(
                    self.object_at(samplers, sampler), target, tracks
                )
            if len(tracks) == 0:
                continue
            var name = self.text(animation, "name")
            if name == "":
                name = "animation_" + String(index)
            self.model.animations.append(AnimationClip(name, tracks^))

    def channel_tracks(
        mut self, sampler: Int, target: Int, mut tracks: List[KeyframeTrack]
    ) raises:
        """Add the tracks one channel makes: one for a node's translation,
        rotation or scale, and one per mesh and morph target for its
        weights. A channel on no node, or on a node the scene does not
        reach, adds none."""
        var node = self.integer(target, "node", -1)
        if node < 0:
            # An extension's channel, which names its target elsewhere.
            return
        if node >= len(self.model.nodes):
            raise Error("glTF: a channel names a node that is not there")
        var path = self.text(target, "path")
        var kind = _path_kind(path)
        var id = self.model.nodes[node]
        if id == NO_PARENT:
            return
        var input = self.accessor_floats(
            self.required_integer(sampler, "input")
        )
        if input[1] != 1:
            raise Error("glTF: a sampler's input must be a SCALAR")
        var times = List[Duration]()
        for key in range(len(input[0])):
            times.append(Duration(input[0][key], SECOND))
        var how = _interpolation_of(self.text(sampler, "interpolation"))
        var output = self.accessor_floats(
            self.required_integer(sampler, "output")
        )
        if path != "weights":
            var width = kind.component_count()
            if output[1] != width:
                raise Error(
                    "glTF: a " + path + " output must be a VEC" + String(width)
                )
            tracks.append(
                _track(node_target(id, kind), times, output[0], how, width, 0)
            )
            return
        if output[1] != 1:
            raise Error("glTF: a weights output must be a SCALAR")
        var drawn = self.node_meshes[node].copy()
        if len(drawn) == 0:
            # No plain mesh at the node: none, or a skinned one, whose
            # influences the mixer does not drive.
            return
        var morphs = self.morph_counts[
            self.required_integer(self.entry("nodes", node), "mesh")
        ]
        for at in range(len(drawn)):  # pragma: no branch
            for slot in range(morphs):
                tracks.append(
                    _track(
                        morph_target(MeshIndex(drawn[at]), slot),
                        times,
                        output[0],
                        how,
                        morphs,
                        slot,
                    )
                )


def _path_kind(path: String) raises -> TrackKind:
    """Return the track kind a channel's path drives: `MORPH_INFLUENCE` for
    `weights`, whose target is made per morph target."""
    if path == "translation":
        return TRANSLATION
    if path == "rotation":
        return QUATERNION
    if path == "scale":
        return SCALE
    if path == "weights":
        return MORPH_INFLUENCE
    raise Error(
        "glTF: a channel path must be translation, rotation, scale or weights"
    )


def _interpolation_of(name: String) raises -> Interpolation:
    """Return a sampler's interpolation as a track's: `LINEAR` when it
    names none."""
    if name == "" or name == "LINEAR":
        return LINEAR_KEYS
    if name == "STEP":
        return STEP
    if name == "CUBICSPLINE":
        return CUBIC_SPLINE
    raise Error("glTF: an interpolation must be LINEAR, STEP or CUBICSPLINE")


def _track(
    target: TrackTarget,
    times: List[Duration],
    output: List[Float32],
    how: Interpolation,
    stride: Int,
    lane: Int,
) raises -> KeyframeTrack:
    """Return one track read out of a sampler's output.

    Each key holds `stride` numbers, of which the track takes
    `target.kind.component_count()` from `lane` on. A cubic spline key holds
    three such runs, in-tangent, value and out-tangent, as glTF lays them
    out.
    """
    var width = target.kind.component_count()
    var parts = 3 if how == CUBIC_SPLINE else 1
    if len(output) != len(times) * parts * stride:
        raise Error(
            "glTF: a sampler's output must hold one value per key, and a"
            " cubic spline's two tangents as well"
        )
    var runs = List[List[Float32]]()
    for part in range(parts):  # pragma: no branch
        var run = List[Float32]()
        for key in range(len(times)):
            var at = (key * parts + part) * stride + lane
            for offset in range(width):  # pragma: no branch
                run.append(output[at + offset])
        runs.append(run^)
    if how == CUBIC_SPLINE:
        return KeyframeTrack(
            target,
            times,
            in_tangents=runs[0].copy(),
            values=runs[1].copy(),
            out_tangents=runs[2].copy(),
        )
    return KeyframeTrack(target, times, runs[0].copy(), how)


def _normalize_skin_weights(weights: List[Float32]) -> List[Float32]:
    """Return each vertex's four weights scaled to sum to one, as three.js's
    `SkinnedMesh.normalizeSkinWeights` scales them: by their Manhattan
    length, and to the first bone alone when they are all zero."""
    var out = List[Float32]()
    for vertex in range(len(weights) // 4):
        var total = Float32(0)
        for lane in range(4):  # pragma: no branch
            total += abs(weights[vertex * 4 + lane])
        for lane in range(4):  # pragma: no branch
            if total == 0:
                out.append(Float32(1) if lane == 0 else Float32(0))
            else:
                out.append(weights[vertex * 4 + lane] / total)
    return out^


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

    A PNG and a JPEG each begin with a signature. A TGA has none, so bytes
    that begin as neither are read as a TGA, whose header check refuses
    most other files. glTF itself names only PNG and JPEG; the TGA
    fallback is this port's, for a model that points at a TGA texture.

    Args:
        bytes: A PNG, a JPEG or a TGA file.

    Returns:
        The image.

    Raises:
        Error: If the bytes begin as neither PNG nor JPEG and are not a
            TGA either, or the decoder refuses them.
    """
    if len(bytes) >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50:
        return decode_png(bytes)
    if len(bytes) >= 2 and bytes[0] == 0xFF and bytes[1] == 0xD8:
        return decode_jpeg(bytes)
    try:
        return decode_tga(bytes)
    except error:
        raise Error(
            "glTF: an image that is neither PNG nor JPEG, and not a TGA: "
            + String(error)
        )


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
