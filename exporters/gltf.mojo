# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene and its assets written as a glTF 2.0 file: three.js's
`GLTFExporter`, and the other half of `loaders.gltf`.

**Three containers.** `GLTF_EMBEDDED` writes one `.gltf` whose buffer and
images are `data:` URIs inside the JSON. `GLTF_SEPARATE` writes the
`.gltf` and a `.bin` beside it, which the buffer names by a relative URI;
the images stay `data:` URIs, as three.js keeps them. `GLB` writes one
binary container, the JSON chunk and then the binary chunk, with the
images in the binary chunk, as three.js's `binary: true` does.

**What maps to what.** Each node in the scene becomes a glTF node with its
name, its translation, rotation and scale, its `userData` as `extras`, as
three.js's `serializeUserData` writes it, and its children. A removed node
is not written, nor is anything under it. A node whose
`matrix_auto_update` is off is written with its `matrix` instead, since
the matrix is what it draws with. The meshes on one node become one glTF
mesh with a primitive each, which `read_gltf` reads back as one `Mesh`
each on that node. A primitive carries `POSITION`, with the `min` and
`max` the specification asks for, and `NORMAL`, `TEXCOORD_0`, `COLOR_0`
and `indices` when the geometry has them. A geometry's `uv1` becomes
`TEXCOORD_1`. `COLOR_0` is written only when
the material turns `vertex_colors` on, since `read_gltf` turns it on for
a primitive that has one. A geometry or a material used twice is written
once.

**Materials are metallic-roughness.** A `STANDARD` or `PHYSICAL` material
is written with its color, opacity, metalness, roughness, emissive color,
alpha mode, side and maps. Every other kind is written as the nearest
metallic-roughness material, as three.js writes it: its color and opacity
with a metalness of zero and a roughness of one. A `BASIC` material
also says `KHR_materials_unlit`, with a roughness of 0.9, as three.js's
unlit extension writes it. An ao map is the `occlusionTexture`, its
intensity the `strength`, and its texture's channel the `texCoord`. An
emissive intensity that is not one is `KHR_materials_emissive_strength`.
A transparent material is `BLEND`, an alpha-tested one is `MASK` at its
`alpha_test`, and a `DOUBLE_SIDE` material is double-sided.

**Physical extensions.** A `PHYSICAL` material writes the extensions
`read_gltf` reads for it: `KHR_materials_ior`, `KHR_materials_specular`,
`KHR_materials_clearcoat`, each with its maps,
`KHR_materials_transmission` with its map,
`KHR_materials_volume` with its map, and `KHR_materials_dispersion`. Each
is written when a field it holds is not at its default, so a file read and
written again keeps them. three.js writes a volume only for a material
that transmits, and a clear coat only when its factor is not zero; this
also writes one whose other fields say something. The specular intensity
is in its texture's alpha, and the image keeps the alpha. A clear coat's
normal texture carries the scale's x, as three.js writes it.

**Sheen, film and stretch.** `KHR_materials_sheen`,
`KHR_materials_iridescence` and `KHR_materials_anisotropy` are written
with their factors and maps when the sheen, the iridescence or the
anisotropy is not zero, as three.js writes them. A layer whose amount is
zero draws nothing, so its other fields are dropped. The sheen roughness
is in its texture's alpha, and the image keeps the alpha. The iridescence
thickness range is in nanometers and the anisotropy rotation in radians,
as `read_gltf` reads them. glTF's sheen has no amount, so the sheen color
is written times the amount; see `layer_extensions`.

**Textures are PNG images.** Each texture is written once, as a PNG from
`render.png`, with a sampler for its wrap and filter. Each distinct image
is written once, as three.js's `cache.images` keeps it: two textures of
the same pixels share one image. glTF's `v` runs down
from the image's top, where a texture here runs up from its bottom, so an
image of a texture with `flip_y` is written upside down, as three.js
writes a `flipY` texture. A texture that `read_gltf` made has `flip_y`
off, so its image is written as it is. Each sampler carries the texture's
`wrapS`, `wrapT`, `magFilter` and `minFilter`. A texture moved, tiled or
turned is written with `KHR_texture_transform`, as three.js's
`applyTextureTransform` writes it; see `GltfPlacement`. glTF keeps
roughness and metalness in one image, green and blue: when a material's
two maps are one texture it is written once, and when they differ they
are combined into one image of the same size, as three.js's
`buildMetalRoughTexture` combines them. Two maps combined must share one
transform and one channel, since one reference carries them.

**What a node carries.** A glTF node has one mesh, one skin, one camera
and one light, so everything that rides one scene node is written on it.
A directional, point or spot light is a `KHR_lights_punctual` light, as
three.js's `GLTFLightExtension` writes it; glTF aims it down its node's
-z axis, and the target is not written. A camera of the `CameraList`
handed in is a perspective or an orthographic camera, named by its
node; `xmag` and `ymag` are half the box, as the specification and
`read_gltf` have them, where three.js writes twice `right` and `top`. A
skinned mesh writes `JOINTS_0` and `WEIGHTS_0`, and its node a skin of
its bones' nodes, each inverse bind times the bind matrix, as three.js's
`processSkin` writes it. An instanced mesh writes
`EXT_mesh_gpu_instancing`, required, as three.js's
`GLTFMeshGpuInstancing` writes it. A line and points are primitives of
their own mode. Morph targets are the primitives' `targets`, as offsets,
with the mesh's `weights` and `extras.targetNames`. A skinned or an
instanced mesh shares its node with nothing else, and the meshes on one
node share one set of morph targets and weights: glTF gives a node one
mesh, one skin and one instancing.

**Animations.** Each `AnimationClip` handed in is a glTF animation, as
three.js's `processAnimation` writes it: a node's position, rotation and
scale tracks are channels, and the morph tracks of one node are merged
into one `weights` channel, as three.js's `mergeMorphTargetTracks`
merges them; see `_Merged`. Any other track is left out, as three.js
leaves it out.

**User data and options.** A node's `user_data`, a geometry's on each
primitive that draws it, and the scene's and each material's user data
from `GltfExportOptions`, are written as
`extras`, as three.js's `serializeUserData` writes them. A `Scene` and a
`Material` here hold no user data, so the options carry theirs. With
`include_custom_extensions` on, a `gltfExtensions` object in user data
is written as the object's `extensions` instead, each name also in
`extensionsUsed`, and it must be an object. A custom extension comes
before the ones this exporter writes, and one of the same name takes the
exporter's value, as three.js's plugins overwrite it. `max_texture_size`
clamps each side of an image, as three.js draws it on a canvas that
size. The image is resampled bilinear at each pixel's center, where
three.js lets the browser's canvas resample it.

**Not written.** Ambient, hemisphere and rect area lights and light
probes, a light's decay, batched meshes and sprites, and every map glTF
has no place for: alpha, light, specular, displacement, environment,
matcap and gradient maps. A bump map is `EXT_materials_bump` on a
standard or a physical material, as three.js writes it. An ao map on a
`BASIC` material is written, as three.js writes it, but `read_gltf` reads
no occlusion for an unlit material. A `BACK_SIDE` material is written single-sided, as three.js
writes it, since glTF has no back side. A geometry's groups are not split
into primitives for a mesh with one material, as three.js's are not. A
mesh that wears a material list writes one primitive a group, each with
its own slice of the index; see `_Exporter.mesh`. A group whose material
the list does not have, or that holds no whole triangle, writes nothing,
as nothing is drawn for it. three.js writes it with no material.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    CUBIC_SPLINE,
    MORPH_INFLUENCE,
    POSITION as TRANSLATION_KIND,
    QUATERNION,
    SCALE,
    STEP,
    Interpolation,
    KeyframeTrack,
    TrackKind,
)
from cameras.camera_list import CameraList
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    UV1,
    BufferGeometry,
)
from core.geometry_store import GeometryId
from core.morph import MorphInfluences
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from core.user_data import UserData, json_value_text
from exporters.common import (
    check_geometry,
    push_f32,
    push_word,
    resized_image,
)
from exporters.json_writer import JsonWriter
from loaders.gltf import (
    COMPONENT_BYTE,
    COMPONENT_FLOAT,
    COMPONENT_SHORT,
    COMPONENT_UNSIGNED_BYTE,
    COMPONENT_UNSIGNED_INT,
    COMPONENT_UNSIGNED_SHORT,
    EMISSIVE_STRENGTH,
    GLB_BIN_CHUNK,
    GLB_JSON_CHUNK,
    GLB_MAGIC,
    GLB_VERSION,
    GPU_INSTANCING,
    LIGHTS_PUNCTUAL,
    MATERIALS_BUMP,
    MATERIALS_ANISOTROPY,
    MATERIALS_CLEARCOAT,
    MATERIALS_DISPERSION,
    MATERIALS_IOR,
    MATERIALS_IRIDESCENCE,
    MATERIALS_SHEEN,
    MATERIALS_SPECULAR,
    MATERIALS_TRANSMISSION,
    MATERIALS_UNLIT,
    MATERIALS_VOLUME,
    MESH_QUANTIZATION,
    MODE_LINES,
    MODE_LINE_LOOP,
    MODE_LINE_STRIP,
    MODE_POINTS,
    MODE_TRIANGLES,
    TEXTURE_TRANSFORM,
    WRAP_CLAMP,
    WRAP_MIRROR,
    WRAP_REPEAT,
    gl_filter,
)
from loaders.json import OBJECT, parse_json, quote_json
from lights.light import DIRECTIONAL, POINT, SPOT, Light, LightKind
from materials.material import (
    BASIC,
    DEFAULT_IOR,
    DOUBLE_SIDE,
    NO_TEXTURE,
    PHYSICAL,
    STANDARD,
    Material,
    MaterialId,
)
from math.matrix4 import Matrix4
from math.utils import (
    ComponentType,
    INT16_COMPONENT,
    INT32_COMPONENT,
    INT8_COMPONENT,
    UINT16_COMPONENT,
    UINT32_COMPONENT,
    UINT8_COMPONENT,
)
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.line import LOOP, SEGMENTS, LineMode
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Color, FloatColor, Framebuffer
from render.png import encode as encode_png
from render.texture import CLAMP, FLOAT_TYPE, MIRROR, Texture, Wrap
from render.texture_store import TextureId
from std.math import floor, isfinite
from std.pathlib import Path
from units.si import METER, NANOMETER, RADIAN

# The two buffer view targets: vertex attributes, and indices.
comptime ARRAY_BUFFER = 34962
comptime ELEMENT_ARRAY_BUFFER = 34963
# The largest vertex count whose indices fit an unsigned short. glTF
# keeps 65535 itself back, as a strip's restart.
comptime MAX_SHORT_VERTICES = 65535
comptime _BASE64 = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
)


@fieldwise_init
struct GltfContainer(Equatable, ImplicitlyCopyable, Writable):
    """How a glTF file is packaged, as a type rather than a bare int.

    `export_gltf` refuses `GltfContainer(7)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three containers there are."""
        return self == GLTF_EMBEDDED or self == GLTF_SEPARATE or self == GLB


# One `.gltf`, its buffer and images as `data:` URIs.
comptime GLTF_EMBEDDED = GltfContainer(0)
# A `.gltf` and a `.bin` beside it; the images as `data:` URIs.
comptime GLTF_SEPARATE = GltfContainer(1)
# One `.glb`: a JSON chunk and a binary chunk.
comptime GLB = GltfContainer(2)


struct GltfFiles(Movable):
    """What `export_gltf` wrote: the file, and the `.bin` beside it."""

    # The `.gltf` text as UTF-8, or the whole `.glb`.
    var document: List[UInt8]
    # The `.bin` of `GLTF_SEPARATE`; empty for the other two, and for a
    # scene with nothing to put in a buffer.
    var binary: List[UInt8]

    def __init__(out self):
        """Start with two empty files."""
        self.document = List[UInt8]()
        self.binary = List[UInt8]()


def encode_base64(bytes: List[UInt8]) -> String:
    """Return bytes as base64, in the standard alphabet, padded with `=`.

    Args:
        bytes: The bytes.

    Returns:
        The text, which `loaders.gltf.decode_base64` reads back.
    """
    var alphabet = String(_BASE64).as_bytes()
    var out = List[UInt8]()
    var at = 0
    while at + 3 <= len(bytes):
        var word = (
            (Int(bytes[at]) << 16)
            | (Int(bytes[at + 1]) << 8)
            | Int(bytes[at + 2])
        )
        for shift in [18, 12, 6, 0]:  # pragma: no branch
            out.append(alphabet[(word >> shift) & 63])
        at += 3
    var left = len(bytes) - at
    if left > 0:
        var word = Int(bytes[at]) << 16
        if left == 2:
            word |= Int(bytes[at + 1]) << 8
        out.append(alphabet[(word >> 18) & 63])
        out.append(alphabet[(word >> 12) & 63])
        out.append(alphabet[(word >> 6) & 63] if left == 2 else UInt8(61))
        out.append(61)
    return String(unsafe_from_utf8=out)


def index_component(vertices: Int) -> Int:
    """Return the component type a primitive's indices are written as.

    Args:
        vertices: How many vertices the primitive has.

    Returns:
        `COMPONENT_UNSIGNED_SHORT` when every index fits one below 65535,
        and `COMPONENT_UNSIGNED_INT` otherwise.
    """
    return (
        COMPONENT_UNSIGNED_INT if vertices
        > MAX_SHORT_VERTICES else COMPONENT_UNSIGNED_SHORT
    )


def binary_name_for(path: String) -> String:
    """Return the name of the `.bin` that `write_gltf` puts beside a
    `.gltf`: the file's own name with its extension changed.

    Args:
        path: The `.gltf` file.

    Returns:
        The `.bin`'s name, without the directory: `scene.gltf` gives
        `scene.bin`, and a name with no extension gains one.
    """
    var name = String(path[byte = path.rfind("/") + 1 :])
    var dot = name.rfind(".")
    var stem = String(name[byte=0:dot]) if dot > 0 else name
    return stem + ".bin"


def _is_relative_name(name: String) -> Bool:
    """Return True if a buffer URI is a name `read_gltf` reads beside the
    file: not empty, and with no scheme."""
    return name != "" and name.find(":") < 0


def _is_zero(vector: Vector3) -> Bool:
    """Return True if all three components are zero."""
    return vector.x == 0 and vector.y == 0 and vector.z == 0


def _is_one(vector: Vector3) -> Bool:
    """Return True if all three components are one."""
    return vector.x == 1 and vector.y == 1 and vector.z == 1


def _is_identity_rotation(rotation: Quaternion) -> Bool:
    """Return True if a quaternion turns nothing."""
    return (
        rotation.x == 0
        and rotation.y == 0
        and rotation.z == 0
        and rotation.w == 1
    )


def _is_identity_matrix(matrix: Matrix4) -> Bool:
    """Return True if a matrix moves nothing."""
    var identity = Matrix4()
    var same = True
    for index in range(16):  # pragma: no branch
        same = same and matrix.elements[index] == identity.elements[index]
    return same


def _is_at(point: Vector2, u: Float32, v: Float32) -> Bool:
    """Return True if a point is exactly at `(u, v)`."""
    return point.x == u and point.y == v


def _is_written_upside_down(texture: Texture) -> Bool:
    """Return True if a texture's image is written upside down: one with
    `flip_y`, whose `v` counts up from its bottom row, where glTF's counts
    down from the top, as three.js's `GLTFExporter` flips a `flipY`
    texture's image. `read_gltf` turns `flip_y` off, and such a texture's
    image is written as it is. Either way the texture's own transform
    samples the written image where the texture samples its own.
    """
    return texture.flip_y


@fieldwise_init
struct GltfPlacement(Equatable, ImplicitlyCopyable):
    """Where a texture reference samples its image, as glTF writes it: the
    set of texture coordinates, and the `KHR_texture_transform` applied to
    them.

    glTF's `v` runs down from the image's top. `gltf_pixels` writes an
    image upside down or as it is, and the transform here is the one that
    samples that image where the texture samples its own.
    """

    # `KHR_texture_transform`'s `offset`, `scale` and `rotation`, the
    # last in radians.
    var offset: Vector2
    var scale: Vector2
    var rotation: Float32
    # The `texCoord`: the texture's `channel`.
    var set: Int

    @staticmethod
    def of(texture: Texture) raises -> GltfPlacement:
        """Return where a texture samples its image, as glTF writes it.

        three.js's `GLTFExporter` writes `offset`, `repeat` and `rotation`
        as they are and drops `center`. This writes the offset the whole
        matrix has, so a texture turned or scaled about a center samples
        the same. The image is written the way `v` reads it, so the
        transform needs no flip.

        Args:
            texture: The texture.

        Returns:
            The placement.

        Raises:
            Error: Never, in practice: the matrix is three by three.
        """
        var to_uv = texture.uv_transform()
        var u = to_uv.get(0, 2)
        var v = to_uv.get(1, 2)
        var turn = texture.rotation.to(RADIAN)
        var set = texture.channel.value
        return GltfPlacement(
            Vector2(u, v),
            Vector2(texture.repeat.x, texture.repeat.y),
            turn,
            set,
        )

    def moves(self) -> Bool:
        """Return True if the transform moves, turns or scales anything.

        Returns:
            False for glTF's identity, which is written as no transform.
        """
        return not (
            _is_at(self.offset, 0, 0)
            and _is_at(self.scale, 1, 1)
            and self.rotation == 0
        )

    def __eq__(self, other: Self) -> Bool:
        """Return True if two placements sample at the same coordinates.

        Args:
            other: The other placement.

        Returns:
            True if every part is equal.
        """
        return (
            _is_at(self.offset, other.offset.x, other.offset.y)
            and _is_at(self.scale, other.scale.x, other.scale.y)
            and self.rotation == other.rotation
            and self.set == other.set
        )


def gltf_pixels(texture: Texture) raises -> List[UInt8]:
    """Return a texture's full-size image as glTF writes it.

    The image is written upside down when the texture has `flip_y`, as
    three.js writes a `flipY` texture, and as it is otherwise, as
    `read_gltf` leaves it. `GltfPlacement.of` gives the transform that
    samples it where the texture samples its own.

    Args:
        texture: The texture.

    Returns:
        RGBA bytes, row by row, `width * height * 4` of them.

    Raises:
        Error: If the texture is blank, holds floats, or holds a mode that
            is none of its named values.
    """
    if texture.width == 0:
        raise Error("glTF: a blank texture has no image to write")
    # A glTF image is a PNG or a JPEG, eight bits a channel: light above
    # one has no byte to go in, and clipping it silently is not writing it.
    if texture.texel_type == FLOAT_TYPE:
        raise Error("glTF: a float texture has no eight-bit image to write")
    texture.validate()
    var flip = _is_written_upside_down(texture)
    var row = texture.width * Texture.CHANNELS
    var out = List[UInt8](capacity=row * texture.height)
    var pixels = Span(texture.pixels)
    # A texture that is not blank has at least one row.
    for y in range(texture.height):  # pragma: no branch
        var source = texture.height - 1 - y if flip else y
        out.extend(pixels[source * row : source * row + row])
    return out^


def _same_image(
    written: List[UInt8], written_width: Int, pixels: List[UInt8], width: Int
) -> Bool:
    """Return True if two images are one: the same width and the same bytes,
    which fix the height too."""
    return written_width == width and written == pixels


def _wrap_code(wrap: Wrap) -> Int:
    """Return a wrap as glTF's constant; the wrap is valid."""
    if wrap == CLAMP:
        return WRAP_CLAMP
    if wrap == MIRROR:
        return WRAP_MIRROR
    return WRAP_REPEAT


struct GltfExportOptions(Copyable, Movable):
    """The options of three.js's `GLTFExporter.parse` that go beyond the
    arguments of `export_gltf`, and the user data that a `Scene` and a
    `Material` here do not hold."""

    # The largest width and height an image is written at, three.js's
    # `maxTextureSize`, or none for no limit, three.js's `Infinity`.
    var max_texture_size: Optional[Int]
    # Write a `userData.gltfExtensions` object as `extensions`, three.js's
    # `includeCustomExtensions`.
    var include_custom_extensions: Bool
    # The scene's user data, three.js's `scene.userData`, written as the
    # glTF scene's `extras`.
    var scene_user_data: UserData
    # Each material's user data, three.js's `material.userData`, written
    # as its `extras`: `material_user_data[i]` belongs to
    # `material_ids[i]`. Set with `set_material_user_data`.
    var material_ids: List[MaterialId]
    var material_user_data: List[UserData]

    def __init__(out self):
        """Take three.js's defaults: no limit, no custom extensions, and
        no user data."""
        self.max_texture_size = None
        self.include_custom_extensions = False
        self.scene_user_data = UserData()
        self.material_ids = List[MaterialId]()
        self.material_user_data = List[UserData]()

    def set_material_user_data(mut self, id: MaterialId, data: UserData):
        """Give a material its user data, replacing what it had.

        Args:
            id: The material.
            data: Its user data.
        """
        for at in range(len(self.material_ids)):
            if self.material_ids[at] == id:
                self.material_user_data[at] = data.copy()
                return
        self.material_ids.append(id)
        self.material_user_data.append(data.copy())

    def material_data(self, id: MaterialId) -> UserData:
        """Return a material's user data.

        Args:
            id: The material.

        Returns:
            Its user data, or none when it was given none.
        """
        for at in range(len(self.material_ids)):
            if self.material_ids[at] == id:
                return self.material_user_data[at].copy()
        return UserData()


struct _UserParts(Movable):
    """User data split as three.js's `serializeUserData` splits it: the
    `extras`, and the custom extensions."""

    # The `extras` object's text, or empty for none.
    var extras: String
    # Each custom extension's name and its value's text.
    var names: List[String]
    var values: List[String]

    def __init__(out self):
        """Start with neither."""
        self.extras = String()
        self.names = List[String]()
        self.values = List[String]()


def _user_parts(data: UserData, include: Bool) raises -> _UserParts:
    """Split user data into `extras` and, when `include` is on, the custom
    extensions its `gltfExtensions` holds, as three.js's
    `serializeUserData` does."""
    var parts = _UserParts()
    var rest = data.copy()
    if include and data.has("gltfExtensions"):
        if data.kind("gltfExtensions") != OBJECT:
            raise Error("glTF: userData.gltfExtensions must be an object")
        var document = parse_json(data.json("gltfExtensions"))
        for at in range(document.length(0)):
            var name = document.key(0, at)
            parts.names.append(name)
            parts.values.append(
                json_value_text(document, document.get(0, name))
            )
        _ = rest.remove("gltfExtensions")
    if rest.count() > 0:
        parts.extras = rest.to_json()
    return parts^


def _with_custom(parts: _UserParts, plugins: String) raises -> String:
    """Return an `extensions` object: the custom extensions first, then the
    ones this exporter writes, as three.js's plugins add theirs after
    `serializeUserData`. A name in both keeps its first place and the
    exporter's value, as three.js's plugin overwrites it. Empty for
    none."""
    if len(parts.names) == 0:
        return plugins
    var names = parts.names.copy()
    var values = parts.values.copy()
    if plugins != "":
        var document = parse_json(plugins)
        # The exporter writes an object only when it holds a key, and
        # `names` holds one: both loops always run.
        for at in range(document.length(0)):  # pragma: no branch
            var name = document.key(0, at)
            var text = json_value_text(document, document.get(0, name))
            var slot = -1
            for known in range(len(names)):  # pragma: no branch
                if names[known] == name:
                    slot = known
            if slot >= 0:
                values[slot] = text
            else:
                names.append(name)
                values.append(text)
    var out = String("{")
    # `names` holds at least the custom extensions: the loop always runs.
    for at in range(len(names)):  # pragma: no branch
        if at > 0:
            out += ","
        out += quote_json(names[at]) + ":" + values[at]
    return out + "}"


struct _Exporter(Movable):
    """The document's arrays as JSON texts, the buffer's bytes, and what
    has been written already."""

    # Images as `data:` URIs rather than buffer views.
    var embed: Bool
    var bin: List[UInt8]
    var views: List[String]
    var accessors: List[String]
    var images: List[String]
    # The pixels and size of each image written, so that two textures of
    # one image write it once, as three.js's `cache.images` does.
    var image_pixels: List[List[UInt8]]
    var image_sizes: List[Int]
    var samplers: List[String]
    var sampler_keys: List[Int]
    # A texture per pair of texture ids: one id twice for a plain
    # texture, and a roughness map and a metalness map for a combined one.
    var textures: List[String]
    var texture_firsts: List[Int]
    var texture_seconds: List[Int]
    var materials: List[String]
    var material_keys: List[Int]
    var meshes: List[String]
    # Each geometry written, and its accessors, or -1 for none yet.
    var geometry_keys: List[Int]
    var positions: List[Int]
    var normals: List[Int]
    var uvs: List[Int]
    var uv1s: List[Int]
    var colors: List[Int]
    var indices: List[Int]
    # Each geometry's morph targets as glTF's offsets: a `POSITION`
    # accessor and a `NORMAL` accessor, or -1 for none, per target.
    var targets: List[List[Int]]
    # Each geometry's `JOINTS_0` and `WEIGHTS_0`, or -1 until a skinned
    # mesh asks for them.
    var joints: List[Int]
    var skin_weights: List[Int]
    # `KHR_lights_punctual`'s lights, and the cameras, skins and
    # animations, as JSON texts.
    var lights: List[String]
    var cameras: List[String]
    var skins: List[String]
    var animations: List[String]
    # The extensions written, each once, in the order first written, and
    # the ones a reader must know.
    var used: List[String]
    var required: List[String]
    var options: GltfExportOptions

    def __init__(out self, embed: Bool, var options: GltfExportOptions):
        """Start an empty document.

        Args:
            embed: True to write images as `data:` URIs.
            options: The options to write by.
        """
        self.embed = embed
        self.options = options^
        self.bin = List[UInt8]()
        self.views = List[String]()
        self.accessors = List[String]()
        self.images = List[String]()
        self.image_pixels = List[List[UInt8]]()
        self.image_sizes = List[Int]()
        self.samplers = List[String]()
        self.sampler_keys = List[Int]()
        self.textures = List[String]()
        self.texture_firsts = List[Int]()
        self.texture_seconds = List[Int]()
        self.materials = List[String]()
        self.material_keys = List[Int]()
        self.meshes = List[String]()
        self.geometry_keys = List[Int]()
        self.positions = List[Int]()
        self.normals = List[Int]()
        self.uvs = List[Int]()
        self.uv1s = List[Int]()
        self.colors = List[Int]()
        self.indices = List[Int]()
        self.targets = List[List[Int]]()
        self.joints = List[Int]()
        self.skin_weights = List[Int]()
        self.lights = List[String]()
        self.cameras = List[String]()
        self.skins = List[String]()
        self.animations = List[String]()
        self.used = List[String]()
        self.required = List[String]()

    def use(mut self, name: String):
        """Add an extension to `extensionsUsed`, once."""
        for known in self.used:
            if known == name:
                return
        self.used.append(name)

    def require(mut self, name: String):
        """Add an extension to `extensionsUsed` and `extensionsRequired`,
        once."""
        self.use(name)
        if not (name in self.required):
            self.required.append(name)

    def user_parts(mut self, data: UserData) raises -> _UserParts:
        """Split user data into `extras` and custom extensions, and record
        each custom extension as used, as three.js's `serializeUserData`
        does."""
        var parts = _user_parts(data, self.options.include_custom_extensions)
        for name in parts.names:
            self.use(name)
        return parts^

    def pad(mut self):
        """Pad the buffer to a multiple of four bytes, where every view
        starts, as the specification aligns them."""
        while len(self.bin) % 4 != 0:
            self.bin.append(0)

    def view(
        mut self, bytes: List[UInt8], target: Int, stride: Int
    ) raises -> Int:
        """Append bytes to the buffer as a new view, and return its index."""
        self.pad()
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("buffer")
        writer.integer(0)
        writer.key("byteOffset")
        writer.integer(len(self.bin))
        writer.key("byteLength")
        writer.integer(len(bytes))
        if stride > 0:
            writer.key("byteStride")
            writer.integer(stride)
        if target > 0:
            writer.key("target")
            writer.integer(target)
        writer.end_object()
        self.bin.extend(Span(bytes))
        self.views.append(writer.finish())
        return len(self.views) - 1

    def float_accessor(
        mut self,
        data: List[Float32],
        width: Int,
        kind: String,
        bounded: Bool,
        vertex: Bool = True,
    ) raises -> Int:
        """Write `Float32`s and return their accessor: a vertex attribute,
        in an array buffer view with a stride, or with `vertex` off the
        keys, the matrices or the instances, in a plain view."""
        var bytes = List[UInt8](capacity=len(data) * 4)
        # Every caller writes at least one element: `geometry` refuses a
        # geometry with no vertices, a track has a key, a skeleton a bone,
        # and `instancing` refuses an instanced mesh with no instances.
        for value in data:  # pragma: no branch
            push_f32(bytes, value, True)
        var view = self.view(
            bytes, ARRAY_BUFFER if vertex else 0, width * 4 if vertex else 0
        )
        var count = len(data) // width
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("bufferView")
        writer.integer(view)
        writer.key("componentType")
        writer.integer(COMPONENT_FLOAT)
        writer.key("count")
        writer.integer(count)
        writer.key("type")
        writer.string(kind)
        if bounded:
            # A geometry with no vertices is refused before this, so the
            # first vertex is there.
            var low = List[Float32]()
            var high = List[Float32]()
            for lane in range(width):  # pragma: no branch
                low.append(data[lane])
                high.append(data[lane])
            for vertex in range(1, count):
                for lane in range(width):  # pragma: no branch
                    var value = data[vertex * width + lane]
                    low[lane] = min(low[lane], value)
                    high[lane] = max(high[lane], value)
            writer.key("min")
            _write_numbers(writer, low)
            writer.key("max")
            _write_numbers(writer, high)
        writer.end_object()
        self.accessors.append(writer.finish())
        return len(self.accessors) - 1

    def attribute_accessor(
        mut self,
        attribute: BufferAttribute,
        kind: String,
        bounded: Bool,
        semantic: String,
    ) raises -> Int:
        """Write a vertex attribute and return its accessor, as three.js's
        `processAccessor` writes one: a `Float32` attribute as floats, and
        an integer one in its own component type with its `normalized`
        flag. A 32-bit integer attribute is written as floats, as three.js
        converts one of a named attribute. A quantized type that
        `KHR_mesh_quantization` allows for `semantic` requires that
        extension, as three.js's `detectMeshQuantization` requires it."""
        var type = attribute.component_type()
        if (
            not attribute.is_integer()
            or type == UINT32_COMPONENT
            or type == INT32_COMPONENT
        ):
            return self.float_accessor(
                attribute.packed(), attribute.item_size, kind, bounded
            )
        var size = 1 if type == UINT8_COMPONENT or type == INT8_COMPONENT else 2
        var width = attribute.item_size
        # Each element starts on four bytes, as the specification has a
        # vertex attribute's elements aligned.
        var stride = (width * size + 3) // 4 * 4
        var stored = attribute.stored_values()
        var count = attribute.count()
        var bytes = List[UInt8](capacity=count * stride)
        # A geometry with no vertices is refused before this, so there is
        # an element, and an item size is positive.
        for element in range(count):  # pragma: no branch
            for lane in range(width):  # pragma: no branch
                push_word(bytes, stored[element * width + lane], size, True)
            while len(bytes) % stride != 0:
                bytes.append(0)
        var view = self.view(bytes, ARRAY_BUFFER, stride)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("bufferView")
        writer.integer(view)
        writer.key("componentType")
        writer.integer(_gl_component(type))
        if attribute.is_normalized():
            writer.key("normalized")
            writer.boolean(True)
        writer.key("count")
        writer.integer(count)
        writer.key("type")
        writer.string(kind)
        if bounded:
            var low = List[Int]()
            var high = List[Int]()
            for lane in range(width):  # pragma: no branch
                low.append(stored[lane])
                high.append(stored[lane])
            for element in range(1, count):
                for lane in range(width):  # pragma: no branch
                    var value = stored[element * width + lane]
                    low[lane] = min(low[lane], value)
                    high[lane] = max(high[lane], value)
            writer.key("min")
            _write_integers(writer, low)
            writer.key("max")
            _write_integers(writer, high)
        writer.end_object()
        self.accessors.append(writer.finish())
        if _is_quantized(semantic, type, attribute.is_normalized()):
            self.require(MESH_QUANTIZATION)
        return len(self.accessors) - 1

    def joint_accessor(mut self, joints: List[Float32]) raises -> Int:
        """Write a `JOINTS_0` of unsigned shorts, as three.js's
        `GLTFExporter` converts a `skinIndex` to them, and return its
        accessor. `primitive` has checked every index."""
        var bytes = List[UInt8](capacity=len(joints) * 2)
        # A skinned geometry has at least one vertex.
        for value in joints:  # pragma: no branch
            push_word(bytes, Int(value), 2, True)
        var view = self.view(bytes, ARRAY_BUFFER, 8)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("bufferView")
        writer.integer(view)
        writer.key("componentType")
        writer.integer(COMPONENT_UNSIGNED_SHORT)
        writer.key("count")
        writer.integer(len(joints) // 4)
        writer.key("type")
        writer.string("VEC4")
        writer.end_object()
        self.accessors.append(writer.finish())
        return len(self.accessors) - 1

    def index_accessor(mut self, index: List[Int], vertices: Int) raises -> Int:
        """Write a primitive's indices and return their accessor."""
        var component = index_component(vertices)
        var size = 4 if component == COMPONENT_UNSIGNED_INT else 2
        var bytes = List[UInt8](capacity=len(index) * size)
        # An indexed geometry has at least one triangle.
        for entry in index:  # pragma: no branch
            push_word(bytes, entry, size, True)
        var view = self.view(bytes, ELEMENT_ARRAY_BUFFER, 0)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("bufferView")
        writer.integer(view)
        writer.key("componentType")
        writer.integer(component)
        writer.key("count")
        writer.integer(len(index))
        writer.key("type")
        writer.string("SCALAR")
        writer.end_object()
        self.accessors.append(writer.finish())
        return len(self.accessors) - 1

    def geometry(
        mut self,
        id: GeometryId,
        colored: Bool,
        assets: Assets,
        skinned: Bool = False,
        triangles: Bool = True,
    ) raises -> Int:
        """Write a geometry's accessors and its morph targets, once, and
        its colors and its skin once they are asked for; return its slot in
        the geometry lists."""
        ref geometry = assets.geometries.get(id)
        # Checked each time, since a line's geometry need not hold whole
        # triangles and a mesh's must.
        var count = check_geometry(geometry, triangles)
        var slot = -1
        for at in range(len(self.geometry_keys)):
            if self.geometry_keys[at] == id.value:
                slot = at
        if slot < 0:
            if count == 0:
                raise Error("glTF: a geometry with no vertices is not written")
            self.geometry_keys.append(id.value)
            self.positions.append(
                self.attribute_accessor(
                    geometry.attribute_view(POSITION), "VEC3", True, "POSITION"
                )
            )
            var normal = -1
            if geometry.has_attribute(NORMAL):
                normal = self.attribute_accessor(
                    geometry.attribute_view(NORMAL), "VEC3", False, "NORMAL"
                )
            self.normals.append(normal)
            var uv = -1
            if geometry.has_attribute(UV):
                uv = self.attribute_accessor(
                    geometry.attribute_view(UV), "VEC2", False, "TEXCOORD"
                )
            self.uvs.append(uv)
            var uv1 = -1
            if geometry.has_attribute(UV1):
                uv1 = self.attribute_accessor(
                    geometry.attribute_view(UV1), "VEC2", False, "TEXCOORD"
                )
            self.uv1s.append(uv1)
            self.colors.append(-1)
            var indices = -1
            if geometry.is_indexed():
                indices = self.index_accessor(geometry.index, count)
            self.indices.append(indices)
            self.targets.append(self.morph_targets(geometry))
            self.joints.append(-1)
            self.skin_weights.append(-1)
            slot = len(self.geometry_keys) - 1
        if skinned and self.joints[slot] < 0:
            self.joints[slot] = self.joint_accessor(
                geometry.attribute_view(SKIN_INDEX).packed()
            )
            self.skin_weights[slot] = self.attribute_accessor(
                geometry.attribute_view(SKIN_WEIGHT), "VEC4", False, "WEIGHTS"
            )
        if colored and self.colors[slot] < 0:
            ref color = geometry.attribute_view(COLOR)
            self.colors[slot] = self.attribute_accessor(
                color,
                "VEC3" if color.item_size == 3 else "VEC4",
                False,
                "COLOR",
            )
        return slot

    def morph_targets(mut self, geometry: BufferGeometry) raises -> List[Int]:
        """Write a geometry's morph targets as glTF's offsets, as three.js's
        `GLTFExporter` writes them: a target that holds finished positions
        has the base taken off. Return a `POSITION` accessor and a `NORMAL`
        accessor or -1 per target."""
        var found = List[Int]()
        for target in range(geometry.morph_count()):
            found.append(
                self.float_accessor(
                    _offsets(
                        geometry, geometry.morph_positions[target], POSITION
                    ),
                    3,
                    "VEC3",
                    True,
                )
            )
            var normal = -1
            if geometry.has_morph_normals():
                normal = self.float_accessor(
                    _offsets(geometry, geometry.morph_normals[target], NORMAL),
                    3,
                    "VEC3",
                    False,
                )
            found.append(normal)
        return found^

    def sampler(mut self, texture: Texture) raises -> Int:
        """Write the sampler for a texture's two wraps and two filters,
        once, as three.js's `processSampler` writes `wrapS`, `wrapT`,
        `magFilter` and `minFilter`.

        A mipmap `minFilter` on a texture with no chain is written as the
        filter it reads inside a level, since only a chain can be read
        by level and glTF says nothing about whether one is built."""
        var minify = texture.min_filter
        if texture.levels == 1:
            minify = minify.within_level()
        var key = (
            (texture.wrap_s.value * 3 + texture.wrap_t.value) * 2
            + texture.mag_filter.value
        ) * 6 + minify.value
        for at in range(len(self.sampler_keys)):
            if self.sampler_keys[at] == key:
                return at
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("magFilter")
        writer.integer(gl_filter(texture.mag_filter))
        writer.key("minFilter")
        writer.integer(gl_filter(minify))
        writer.key("wrapS")
        writer.integer(_wrap_code(texture.wrap_s))
        writer.key("wrapT")
        writer.integer(_wrap_code(texture.wrap_t))
        writer.end_object()
        self.sampler_keys.append(key)
        self.samplers.append(writer.finish())
        return len(self.samplers) - 1

    def image(
        mut self, var pixels: List[UInt8], width: Int, height: Int
    ) raises -> Int:
        """Write an image as a PNG once and return its index.

        three.js's `processImage` caches each image by its source, so
        several textures of one image write one image. A texture here
        holds its own pixels, so the same pixels at the same size are the
        same image.
        """
        for at in range(len(self.images)):
            if _same_image(
                self.image_pixels[at], self.image_sizes[at], pixels, width
            ):
                return at
        self.image_pixels.append(pixels.copy())
        self.image_sizes.append(width)
        var png = encode_png(Framebuffer(width, height, pixels^))
        var writer = JsonWriter()
        writer.begin_object()
        if self.embed:
            writer.key("uri")
            writer.string("data:image/png;base64," + encode_base64(png))
        else:
            writer.key("mimeType")
            writer.string("image/png")
            writer.key("bufferView")
            writer.integer(self.view(png, 0, 0))
        writer.end_object()
        self.images.append(writer.finish())
        return len(self.images) - 1

    def texture(
        mut self, first: TextureId, second: TextureId, assets: Assets
    ) raises -> Int:
        """Write a texture once and return its index: one texture when the
        two ids are the same, and a roughness map in green and a metalness
        map in blue combined when they differ."""
        for at in range(len(self.texture_firsts)):
            if (
                self.texture_firsts[at] == first.value
                and self.texture_seconds[at] == second.value
            ):
                return at
        # The first id that names a texture sets the size and the sampler.
        var lead = first if first != NO_TEXTURE else second
        ref leader = assets.textures.get(lead)
        var pixels: List[UInt8]
        if first == second:
            pixels = gltf_pixels(leader)
        else:
            pixels = List[UInt8](capacity=leader.width * leader.height * 4)
            for _ in range(leader.width * leader.height):
                pixels.append(0)
                pixels.append(255)
                pixels.append(255)
                pixels.append(255)
            _copy_channel(pixels, first, 1, leader, assets)
            _copy_channel(pixels, second, 2, leader, assets)
        var sampler = self.sampler(leader)
        var width = leader.width
        var height = leader.height
        if Bool(self.options.max_texture_size):
            # three.js draws the image on a canvas of at most this size a
            # side, each side clamped on its own.
            var most = self.options.max_texture_size.value()
            if width > most or height > most:
                var wide = min(width, most)
                var high = min(height, most)
                pixels = resized_image(pixels, width, height, wide, high)
                width = wide
                height = high
        var image = self.image(pixels^, width, height)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("sampler")
        writer.integer(sampler)
        writer.key("source")
        writer.integer(image)
        writer.end_object()
        self.texture_firsts.append(first.value)
        self.texture_seconds.append(second.value)
        self.textures.append(writer.finish())
        return len(self.textures) - 1

    def texture_info(
        mut self,
        mut writer: JsonWriter,
        key: String,
        first: TextureId,
        second: TextureId,
        assets: Assets,
        amount_key: String = "",
        amount: Float32 = 1,
    ) raises:
        """Write `key` and a texture reference to it: its index, its
        `texCoord` when that is not the first set, `amount_key` when
        `amount` is not one, and its `KHR_texture_transform` when that
        moves anything, as three.js's `applyTextureTransform` writes it.
        """
        var index = self.texture(first, second, assets)
        var lead = first if first != NO_TEXTURE else second
        var placed = GltfPlacement.of(assets.textures.get(lead))
        writer.key(key)
        writer.begin_object()
        writer.key("index")
        writer.integer(index)
        if placed.set != 0:
            writer.key("texCoord")
            writer.integer(placed.set)
        if amount != 1:
            writer.key(amount_key)
            writer.number(amount)
        if placed.moves():
            self.use(TEXTURE_TRANSFORM)
            writer.key("extensions")
            writer.begin_object()
            writer.key(TEXTURE_TRANSFORM)
            writer.begin_object()
            if not _is_at(placed.offset, 0, 0):
                writer.key("offset")
                _write_numbers(writer, [placed.offset.x, placed.offset.y])
            if placed.rotation != 0:
                writer.key("rotation")
                writer.number(placed.rotation)
            if not _is_at(placed.scale, 1, 1):
                writer.key("scale")
                _write_numbers(writer, [placed.scale.x, placed.scale.y])
            writer.end_object()
            writer.end_object()
        writer.end_object()

    def material(mut self, id: MaterialId, assets: Assets) raises -> Int:
        """Write a material once, as metallic-roughness, and return its
        index."""
        for at in range(len(self.material_keys)):
            if self.material_keys[at] == id.value:
                return at
        var material = assets.materials.get(id)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("pbrMetallicRoughness")
        writer.begin_object()
        var base = FloatColor(srgb=material.color)
        if not _is_opaque_white(base, material.opacity):
            writer.key("baseColorFactor")
            writer.begin_array()
            writer.number(base.r)
            writer.number(base.g)
            writer.number(base.b)
            writer.number(material.opacity)
            writer.end_array()
        var physical = material.is_physical()
        writer.key("metallicFactor")
        writer.number(material.metalness if physical else 0)
        # three.js's `GLTFMaterialsUnlitExtension` sets an unlit material's
        # roughness to 0.9; every other kind it has no roughness for is 1.
        var roughness = Float32(0.9) if material.kind == BASIC else 1
        writer.key("roughnessFactor")
        writer.number(material.roughness if physical else roughness)
        if material.map != NO_TEXTURE:
            self.texture_info(
                writer, "baseColorTexture", material.map, material.map, assets
            )
        if (
            material.roughness_map != NO_TEXTURE
            or material.metalness_map != NO_TEXTURE
        ):
            self.texture_info(
                writer,
                "metallicRoughnessTexture",
                material.roughness_map,
                material.metalness_map,
                assets,
            )
        writer.end_object()
        if material.normal_map != NO_TEXTURE:
            self.texture_info(
                writer,
                "normalTexture",
                material.normal_map,
                material.normal_map,
                assets,
                "scale",
                material.normal_scale.x,
            )
        if material.ao_map != NO_TEXTURE:
            self.texture_info(
                writer,
                "occlusionTexture",
                material.ao_map,
                material.ao_map,
                assets,
                "strength",
                material.ao_map_intensity,
            )
        var glow = FloatColor(srgb=material.emissive)
        if max(glow.r, max(glow.g, glow.b)) > 0:
            writer.key("emissiveFactor")
            writer.begin_array()
            writer.number(glow.r)
            writer.number(glow.g)
            writer.number(glow.b)
            writer.end_array()
        if material.emissive_map != NO_TEXTURE:
            self.texture_info(
                writer,
                "emissiveTexture",
                material.emissive_map,
                material.emissive_map,
                assets,
            )
        if material.is_transparent():
            writer.key("alphaMode")
            writer.string("BLEND")
        elif material.alpha_test > 0:
            writer.key("alphaMode")
            writer.string("MASK")
            writer.key("alphaCutoff")
            writer.number(material.alpha_test)
        if material.side == DOUBLE_SIDE:
            writer.key("doubleSided")
            writer.boolean(True)
        var parts = self.user_parts(self.options.material_data(id))
        if parts.extras != "":
            writer.key("extras")
            writer.raw(parts.extras)
        var extensions = _with_custom(parts, self.extensions(material, assets))
        if extensions != "":
            writer.key("extensions")
            writer.raw(extensions)
        writer.end_object()
        self.material_keys.append(id.value)
        self.materials.append(writer.finish())
        return len(self.materials) - 1

    def open_extension(mut self, mut writer: JsonWriter, name: String) raises:
        """Write an extension's key and open its object."""
        self.use(name)
        writer.key(name)
        writer.begin_object()

    def extensions(
        mut self, material: Material, assets: Assets
    ) raises -> String:
        """Return a material's `extensions` object as JSON, or an empty
        string when it has none.

        `KHR_materials_unlit` for a `BASIC` material, and
        `KHR_materials_emissive_strength` for an emissive intensity that
        is not one. A `PHYSICAL` material also writes each extension that
        `read_gltf` reads for it, when a field the extension holds is not
        at its default.
        """
        var writer = JsonWriter()
        writer.begin_object()
        var written = 0
        if material.kind == BASIC:
            self.open_extension(writer, MATERIALS_UNLIT)
            writer.end_object()
            written += 1
        if material.emissive_intensity != 1:
            self.open_extension(writer, EMISSIVE_STRENGTH)
            writer.key("emissiveStrength")
            writer.number(material.emissive_intensity)
            writer.end_object()
            written += 1
        if material.bump_map != NO_TEXTURE and material.is_physical():
            # three.js's `GLTFMaterialsBumpExtension`, for a standard or a
            # physical material. A material here has a bump scale that is
            # not one only when it has a bump map.
            self.open_extension(writer, MATERIALS_BUMP)
            self.texture_info(
                writer,
                "bumpTexture",
                material.bump_map,
                material.bump_map,
                assets,
            )
            writer.key("bumpFactor")
            writer.number(material.bump_scale)
            writer.end_object()
            written += 1
        if material.kind == PHYSICAL:
            written += self.physical_extensions(writer, material, assets)
        writer.end_object()
        if written == 0:
            return ""
        return writer.finish()

    def physical_extensions(
        mut self, mut writer: JsonWriter, material: Material, assets: Assets
    ) raises -> Int:
        """Write a physical material's extensions and return how many.

        Each is written as three.js's `GLTFExporter` writes it, when a
        field it holds is not at its default. Colors are written linear,
        as glTF holds them.
        """
        var written = 0
        if material.ior != DEFAULT_IOR:
            self.open_extension(writer, MATERIALS_IOR)
            writer.key("ior")
            writer.number(material.ior)
            writer.end_object()
            written += 1
        if _has_specular(material):
            self.open_extension(writer, MATERIALS_SPECULAR)
            writer.key("specularFactor")
            writer.number(material.specular_intensity)
            writer.key("specularColorFactor")
            _write_color(writer, material.specular_color)
            # The intensity is in the texture's alpha, which the image
            # keeps; `read_gltf` reads it back with `keep_alpha`.
            self.optional_map(
                writer,
                "specularTexture",
                material.specular_intensity_map,
                assets,
            )
            self.optional_map(
                writer,
                "specularColorTexture",
                material.specular_color_map,
                assets,
            )
            writer.end_object()
            written += 1
        if _has_clearcoat(material):
            self.open_extension(writer, MATERIALS_CLEARCOAT)
            writer.key("clearcoatFactor")
            writer.number(material.clearcoat)
            writer.key("clearcoatRoughnessFactor")
            writer.number(material.clearcoat_roughness)
            self.optional_map(
                writer, "clearcoatTexture", material.clearcoat_map, assets
            )
            self.optional_map(
                writer,
                "clearcoatRoughnessTexture",
                material.clearcoat_roughness_map,
                assets,
            )
            # The scale's x alone, as three.js writes it: glTF has one.
            if material.clearcoat_normal_map != NO_TEXTURE:
                self.texture_info(
                    writer,
                    "clearcoatNormalTexture",
                    material.clearcoat_normal_map,
                    material.clearcoat_normal_map,
                    assets,
                    "scale",
                    material.clearcoat_normal_scale.x,
                )
            writer.end_object()
            written += 1
        if _has_transmission(material):
            self.open_extension(writer, MATERIALS_TRANSMISSION)
            writer.key("transmissionFactor")
            writer.number(material.transmission)
            self.optional_map(
                writer,
                "transmissionTexture",
                material.transmission_map,
                assets,
            )
            writer.end_object()
            written += 1
        if _has_volume(material):
            self.open_extension(writer, MATERIALS_VOLUME)
            writer.key("thicknessFactor")
            writer.number(material.thickness.to(METER))
            self.optional_map(
                writer, "thicknessTexture", material.thickness_map, assets
            )
            var distance = material.attenuation_distance.to(METER)
            if isfinite(distance):
                writer.key("attenuationDistance")
                writer.number(distance)
            writer.key("attenuationColor")
            _write_color(writer, material.attenuation_color)
            writer.end_object()
            written += 1
        if material.dispersion != 0:
            self.open_extension(writer, MATERIALS_DISPERSION)
            writer.key("dispersion")
            writer.number(material.dispersion)
            writer.end_object()
            written += 1
        return written + self.layer_extensions(writer, material, assets)

    def optional_map(
        mut self,
        mut writer: JsonWriter,
        key: String,
        id: TextureId,
        assets: Assets,
    ) raises:
        """Write `key` and a reference to one texture, when `id` names
        one; see `texture_info`."""
        if id != NO_TEXTURE:
            self.texture_info(writer, key, id, id, assets)

    def layer_extensions(
        mut self, mut writer: JsonWriter, material: Material, assets: Assets
    ) raises -> Int:
        """Write a physical material's sheen, thin film and stretched lobe
        and return how many of the three were written.

        Each is written when its amount is not zero, as three.js's
        `GLTFExporter` writes it, with every factor and its maps. glTF's
        sheen has no amount: `read_gltf` reads a sheen of one, as three.js
        reads it. The renderer multiplies the sheen color by the amount,
        as three.js's `sheenColor` uniform does, so the color is written
        times the amount and draws the same. three.js writes the color as
        it is and loses the amount.
        """
        var written = 0
        if material.sheen != 0:
            self.open_extension(writer, MATERIALS_SHEEN)
            var tint = FloatColor(srgb=material.sheen_color)
            writer.key("sheenColorFactor")
            _write_numbers(
                writer,
                [
                    tint.r * material.sheen,
                    tint.g * material.sheen,
                    tint.b * material.sheen,
                ],
            )
            writer.key("sheenRoughnessFactor")
            writer.number(material.sheen_roughness)
            # The roughness is in the texture's alpha, which the image
            # keeps; `read_gltf` reads it back with `keep_alpha`.
            self.optional_map(
                writer, "sheenColorTexture", material.sheen_color_map, assets
            )
            self.optional_map(
                writer,
                "sheenRoughnessTexture",
                material.sheen_roughness_map,
                assets,
            )
            writer.end_object()
            written += 1
        if material.iridescence != 0:
            self.open_extension(writer, MATERIALS_IRIDESCENCE)
            writer.key("iridescenceFactor")
            writer.number(material.iridescence)
            writer.key("iridescenceIor")
            writer.number(material.iridescence_ior)
            writer.key("iridescenceThicknessMinimum")
            writer.number(material.iridescence_thickness_minimum.to(NANOMETER))
            writer.key("iridescenceThicknessMaximum")
            writer.number(material.iridescence_thickness_maximum.to(NANOMETER))
            self.optional_map(
                writer, "iridescenceTexture", material.iridescence_map, assets
            )
            self.optional_map(
                writer,
                "iridescenceThicknessTexture",
                material.iridescence_thickness_map,
                assets,
            )
            writer.end_object()
            written += 1
        if material.anisotropy != 0:
            self.open_extension(writer, MATERIALS_ANISOTROPY)
            writer.key("anisotropyStrength")
            writer.number(material.anisotropy)
            writer.key("anisotropyRotation")
            writer.number(material.anisotropy_rotation.to(RADIAN))
            self.optional_map(
                writer, "anisotropyTexture", material.anisotropy_map, assets
            )
            writer.end_object()
            written += 1
        return written

    def mesh(
        mut self, scene: Scene, carried: _Carried, assets: Assets
    ) raises -> Int:
        """Write what one node draws as one glTF mesh, a primitive each,
        and return its index.

        A mesh that wears a material list writes a primitive for each
        group it draws, with the group's slice of the index, as three.js's
        `processMesh` does. A skinned mesh, an instanced mesh, a line and
        points write a primitive each, of their own mode. A mesh whose
        list draws nothing writes no primitive, and a node whose meshes
        write none gets no mesh: -1. A node with morph targets writes its
        `weights` and its `targetNames`, as three.js writes them.
        """
        var skinned = len(carried.skinned) > 0
        var instanced = len(carried.instanced) > 0
        var others = (
            len(carried.meshes) + len(carried.lines) + len(carried.points)
        )
        if skinned and (instanced or others > 0):
            raise Error(
                "glTF: a node that carries a skinned mesh carries nothing"
                " else: glTF gives a node one mesh and one skin"
            )
        if instanced and others > 0:
            raise Error(
                "glTF: a node that carries an instanced mesh carries nothing"
                " else: glTF instances a node's whole mesh"
            )
        var shapes = _geometries(scene, carried)
        var morphs = _morph_count(shapes, assets)
        var weights = _weights(scene, carried, morphs)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("primitives")
        writer.begin_array()
        var primitives = 0
        for which in carried.meshes:
            ref mesh = scene.meshes[which]
            if not mesh.is_multi_material():
                self.primitive(
                    writer,
                    mesh.geometry,
                    mesh.material,
                    List[Int](),
                    assets,
                    MODE_TRIANGLES,
                )
                primitives += 1
                continue
            ref geometry = assets.geometries.get(mesh.geometry)
            for group in geometry.groups:
                var worn = mesh.group_material(group.material_index)
                var run = geometry.triangle_run(group.start, group.count)
                if not Bool(worn) or run[1] == 0:
                    continue
                # A geometry without an index is given one here, as
                # three.js's `didForceIndices` gives it one.
                # A run of no whole triangle was skipped above, so this
                # always runs.
                var slice = List[Int]()
                var last = run[0] + run[1] * 3
                for slot in range(run[0], last):  # pragma: no branch
                    slice.append(geometry.vertex_at(slot))
                self.primitive(
                    writer,
                    mesh.geometry,
                    worn.value(),
                    slice,
                    assets,
                    MODE_TRIANGLES,
                )
                primitives += 1
        for which in carried.skinned:
            ref skin = scene.skinned_meshes[which]
            self.primitive(
                writer,
                skin.geometry,
                skin.material,
                List[Int](),
                assets,
                MODE_TRIANGLES,
                skin.skeleton.bone_count(),
            )
            primitives += 1
        for which in carried.instanced:
            ref crowd = scene.instanced_meshes[which]
            self.primitive(
                writer,
                crowd.geometry,
                crowd.material,
                List[Int](),
                assets,
                MODE_TRIANGLES,
            )
            primitives += 1
        for which in carried.lines:
            ref line = scene.lines[which]
            self.primitive(
                writer,
                line.geometry,
                line.material,
                List[Int](),
                assets,
                line_mode_code(line.mode),
            )
            primitives += 1
        for which in carried.points:
            ref dots = scene.points[which]
            self.primitive(
                writer,
                dots.geometry,
                dots.material,
                List[Int](),
                assets,
                MODE_POINTS,
            )
            primitives += 1
        writer.end_array()
        if morphs > 0:
            writer.key("weights")
            _write_numbers(writer, weights)
            ref first = assets.geometries.get(shapes[0])
            writer.key("extras")
            writer.begin_object()
            writer.key("targetNames")
            writer.begin_array()
            # A geometry with morph targets has at least one.
            for target in range(morphs):  # pragma: no branch
                writer.string(target_name(first, target))
            writer.end_array()
            writer.end_object()
        writer.end_object()
        if primitives == 0:
            return -1
        self.meshes.append(writer.finish())
        return len(self.meshes) - 1

    def primitive(
        mut self,
        mut writer: JsonWriter,
        id: GeometryId,
        material_id: MaterialId,
        slice: List[Int],
        assets: Assets,
        mode: Int,
        bones: Int = 0,
    ) raises:
        """Write one primitive: a geometry drawn in one material and one
        mode, over its own index or, when `slice` is not empty, over that
        slice of it. `bones` is the skeleton's size for a skinned mesh,
        whose `JOINTS_0` and `WEIGHTS_0` are written, and zero otherwise.
        """
        var material = assets.materials.get(material_id)
        ref shape = assets.geometries.get(id)
        if mode != MODE_TRIANGLES and shape.is_indexed():
            raise Error(
                "glTF: a line or points geometry has no index: an index"
                " here is a triangle index"
            )
        if bones > 0:
            _check_skin(shape, bones)
        var colored = material.vertex_colors and shape.has_attribute(COLOR)
        var slot = self.geometry(
            id, colored, assets, bones > 0, mode == MODE_TRIANGLES
        )
        var index = self.material(material_id, assets)
        var indices = self.indices[slot]
        if len(slice) > 0:
            indices = self.index_accessor(slice, shape.vertex_count())
        writer.begin_object()
        writer.key("attributes")
        writer.begin_object()
        writer.key("POSITION")
        writer.integer(self.positions[slot])
        if self.normals[slot] >= 0:
            writer.key("NORMAL")
            writer.integer(self.normals[slot])
        if self.uvs[slot] >= 0:
            writer.key("TEXCOORD_0")
            writer.integer(self.uvs[slot])
        if self.uv1s[slot] >= 0:
            writer.key("TEXCOORD_1")
            writer.integer(self.uv1s[slot])
        if colored:
            writer.key("COLOR_0")
            writer.integer(self.colors[slot])
        if bones > 0:
            writer.key("JOINTS_0")
            writer.integer(self.joints[slot])
            writer.key("WEIGHTS_0")
            writer.integer(self.skin_weights[slot])
        writer.end_object()
        if indices >= 0:
            writer.key("indices")
            writer.integer(indices)
        writer.key("material")
        writer.integer(index)
        writer.key("mode")
        writer.integer(mode)
        if len(self.targets[slot]) > 0:
            writer.key("targets")
            writer.begin_array()
            var pairs = len(self.targets[slot]) // 2
            for target in range(pairs):  # pragma: no branch
                writer.begin_object()
                writer.key("POSITION")
                writer.integer(self.targets[slot][target * 2])
                if self.targets[slot][target * 2 + 1] >= 0:
                    writer.key("NORMAL")
                    writer.integer(self.targets[slot][target * 2 + 1])
                writer.end_object()
            writer.end_array()
        # The geometry's user data, three.js's `serializeUserData( geometry,
        # primitive )`.
        var parts = self.user_parts(shape.user_data)
        if parts.extras != "":
            writer.key("extras")
            writer.raw(parts.extras)
        var custom = _with_custom(parts, "")
        if custom != "":
            writer.key("extensions")
            writer.raw(custom)
        writer.end_object()

    def instancing(mut self, scene: Scene, carried: _Carried) raises -> String:
        """Return a node's `EXT_mesh_gpu_instancing` as JSON, or an empty
        string when it carries no instanced mesh, as three.js's
        `GLTFMeshGpuInstancing` writes it: each instance's matrix split
        into a `TRANSLATION`, a `ROTATION` and a `SCALE`, and its color as
        `_COLOR_0` when the mesh colors its instances. The extension is
        required, since a reader without it draws one instance."""
        if len(carried.instanced) == 0:
            return ""
        ref first = scene.instanced_meshes[carried.instanced[0]]
        for at in range(1, len(carried.instanced)):
            if not _same_instances(
                first, scene.instanced_meshes[carried.instanced[at]]
            ):
                raise Error(
                    "glTF: the instanced meshes on one node must place their"
                    " instances alike: glTF instances a node's whole mesh"
                )
        if first.count() == 0:
            raise Error(
                "glTF: an instanced mesh of no instances is not written: an"
                " accessor holds at least one element"
            )
        var moves = List[Float32]()
        var turns = List[Float32]()
        var sizes = List[Float32]()
        var tints = List[Float32]()
        # Refused above when there are no instances.
        for at in range(first.count()):  # pragma: no branch
            var position = Vector3(0, 0, 0)
            var rotation = Quaternion(0, 0, 0, 1)
            var scale = Vector3(1, 1, 1)
            first.matrices[at].decompose(position, rotation, scale)
            moves.extend([position.x, position.y, position.z])
            turns.extend([rotation.x, rotation.y, rotation.z, rotation.w])
            sizes.extend([scale.x, scale.y, scale.z])
            var tint = FloatColor(srgb=first.color_at(at))
            tints.extend([tint.r, tint.g, tint.b])
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("attributes")
        writer.begin_object()
        writer.key("TRANSLATION")
        writer.integer(self.float_accessor(moves, 3, "VEC3", False, False))
        writer.key("ROTATION")
        writer.integer(self.float_accessor(turns, 4, "VEC4", False, False))
        writer.key("SCALE")
        writer.integer(self.float_accessor(sizes, 3, "VEC3", False, False))
        if len(first.colors) > 0:
            writer.key("_COLOR_0")
            writer.integer(self.float_accessor(tints, 3, "VEC3", False, False))
        writer.end_object()
        writer.end_object()
        self.require(GPU_INSTANCING)
        return writer.finish()

    def skin(
        mut self, scene: Scene, carried: _Carried, written: List[Int]
    ) raises -> Int:
        """Write the skin of a node's skinned meshes and return its index,
        or -1 when it carries none, as three.js's `processSkin` writes
        one: each bone's node as a joint, the first the `skeleton`, and
        each inverse bind matrix times the mesh's bind matrix."""
        if len(carried.skinned) == 0:
            return -1
        ref first = scene.skinned_meshes[carried.skinned[0]]
        for at in range(1, len(carried.skinned)):
            if not _same_skin(first, scene.skinned_meshes[carried.skinned[at]]):
                raise Error(
                    "glTF: the skinned meshes on one node must share one"
                    " skeleton and one bind matrix: glTF gives a node one"
                    " skin"
                )
        var joints = List[Int]()
        var inverses = List[Float32]()
        # A skeleton has at least one bone.
        for bone in first.skeleton.bones:  # pragma: no branch
            var joint = _written_slot(bone.node, written, "a bone")
            if joint < 0:
                raise Error(
                    "glTF: a bone rides a node that is not written: show it,"
                    " or write every node"
                )
            joints.append(joint)
            var inverse = bone.inverse_bind * first.bind_matrix
            for element in range(16):  # pragma: no branch
                inverses.append(inverse.elements[element])
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("inverseBindMatrices")
        writer.integer(self.float_accessor(inverses, 16, "MAT4", False, False))
        writer.key("joints")
        _write_integers(writer, joints)
        writer.key("skeleton")
        writer.integer(joints[0])
        writer.end_object()
        self.skins.append(writer.finish())
        return len(self.skins) - 1

    def light(mut self, light: Light, name: String) raises -> Int:
        """Write a directional, point or spot light to
        `KHR_lights_punctual` and return its index, as three.js's
        `GLTFLightExtension` writes it: the color linear, the distance as
        its `range` when it has one, and a spot light's cone as its outer
        angle, with the penumbra's part of it outside the inner one."""
        self.use(LIGHTS_PUNCTUAL)
        var writer = JsonWriter()
        writer.begin_object()
        if name != "":
            writer.key("name")
            writer.string(name)
        writer.key("color")
        _write_color(writer, light.color)
        writer.key("intensity")
        writer.number(light.intensity)
        writer.key("type")
        writer.string(_light_type(light.kind))
        if light.kind != DIRECTIONAL and light.distance > 0:
            writer.key("range")
            writer.number(light.distance)
        if light.kind == SPOT:
            var outer = light.angle.to(RADIAN)
            writer.key("spot")
            writer.begin_object()
            writer.key("innerConeAngle")
            writer.number((1 - light.penumbra) * outer)
            writer.key("outerConeAngle")
            writer.number(outer)
            writer.end_object()
        writer.end_object()
        self.lights.append(writer.finish())
        return len(self.lights) - 1

    def perspective(
        mut self, camera: PerspectiveCamera, name: String
    ) raises -> Int:
        """Write a perspective camera and return its index, as three.js's
        `processCamera` writes one."""
        camera.validate()
        var writer = JsonWriter()
        writer.begin_object()
        if name != "":
            writer.key("name")
            writer.string(name)
        writer.key("type")
        writer.string("perspective")
        writer.key("perspective")
        writer.begin_object()
        writer.key("aspectRatio")
        writer.number(camera.aspect)
        writer.key("yfov")
        writer.number(camera.fov.to(RADIAN))
        writer.key("zfar")
        writer.number(camera.far.to(METER))
        writer.key("znear")
        writer.number(camera.near.to(METER))
        writer.end_object()
        writer.end_object()
        self.cameras.append(writer.finish())
        return len(self.cameras) - 1

    def orthographic(
        mut self, camera: OrthographicCamera, name: String
    ) raises -> Int:
        """Write an orthographic camera and return its index. `xmag` and
        `ymag` are half the width and half the height, as the
        specification and `read_gltf` read them; three.js writes twice
        `right` and twice `top`. glTF's box is centered on the camera's
        axis, so a box that is not is refused."""
        var right = camera.right.to(METER)
        var top = camera.top.to(METER)
        if camera.left.to(METER) != -right or camera.bottom.to(METER) != -top:
            raise Error(
                "glTF: an orthographic camera's box is centered on its axis:"
                " left must be minus right, and bottom minus top"
            )
        var writer = JsonWriter()
        writer.begin_object()
        if name != "":
            writer.key("name")
            writer.string(name)
        writer.key("type")
        writer.string("orthographic")
        writer.key("orthographic")
        writer.begin_object()
        writer.key("xmag")
        writer.number(right)
        writer.key("ymag")
        writer.number(top)
        writer.key("zfar")
        writer.number(camera.far.to(METER))
        writer.key("znear")
        writer.number(camera.near.to(METER))
        writer.end_object()
        writer.end_object()
        self.cameras.append(writer.finish())
        return len(self.cameras) - 1

    def animation(
        mut self,
        clip: AnimationClip,
        scene: Scene,
        written: List[Int],
        morphs: List[Int],
    ) raises:
        """Write one clip as a glTF animation, as three.js's
        `processAnimation` writes it.

        A node's `POSITION`, `QUATERNION` and `SCALE` tracks are its
        `translation`, `rotation` and `scale` channels. The morph tracks of
        the meshes on one node are merged into one `weights` channel, as
        three.js's `mergeMorphTargetTracks` merges them. A track on a node
        that is not written, and a track of any other kind, is left out,
        as three.js leaves out a track it cannot write. A clip left with
        no channel is not written, since a glTF animation has at least
        one.
        """
        var entries = List[Int]()
        var merged = List[_Merged]()
        # A clip has at least one track.
        for at in range(len(clip.tracks)):  # pragma: no branch
            ref track = clip.tracks[at]
            var kind = track.target.kind
            if kind.is_morph():
                var slot = _written_slot(
                    _morph_node(track, scene), written, "a mesh"
                )
                if slot < 0:
                    continue
                if track.target.slot >= morphs[slot]:
                    raise Error(
                        "glTF: a morph track names a target the mesh on its"
                        " node has not got"
                    )
                var found = -1
                for index in range(len(merged)):
                    if merged[index].node == slot:
                        found = index
                if found < 0:
                    merged.append(_Merged(slot, morphs[slot], track))
                    entries.append(-len(merged))
                else:
                    merged[found].merge(track)
                continue
            if (
                kind != TRANSLATION_KIND
                and kind != QUATERNION
                and kind != SCALE
            ):
                continue
            var node = NodeId(track.target.index)
            if _written_slot(node, written, "a track") < 0:
                continue
            entries.append(at)
        if len(entries) == 0:
            return
        var samplers = List[String]()
        var channels = List[String]()
        # Refused above when there is no entry.
        for entry in entries:  # pragma: no branch
            if entry >= 0:
                ref track = clip.tracks[entry]
                var kind = track.target.kind
                self.channel(
                    samplers,
                    channels,
                    written[track.target.index],
                    _path_of(kind),
                    track.times,
                    _output(track),
                    kind.component_count(),
                    _interpolation_name(track.interpolation),
                )
            else:
                ref one = merged[-entry - 1]
                self.channel(
                    samplers,
                    channels,
                    one.node,
                    "weights",
                    one.times,
                    one.output(),
                    1,
                    one.interpolation(),
                )
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("name")
        if clip.name != "":
            writer.string(clip.name)
        else:
            writer.string("clip_" + String(len(self.animations)))
        _write_array(writer, "samplers", samplers)
        _write_array(writer, "channels", channels)
        writer.end_object()
        self.animations.append(writer.finish())

    def channel(
        mut self,
        mut samplers: List[String],
        mut channels: List[String],
        node: Int,
        path: String,
        times: List[Float32],
        output: List[Float32],
        width: Int,
        interpolation: String,
    ) raises:
        """Write one sampler, its key times with the bounds the
        specification asks for and its values, and the channel that
        drives a node's `path` with it."""
        var input = self.float_accessor(times, 1, "SCALAR", True, False)
        var kind = "SCALAR" if width == 1 else "VEC" + String(width)
        var values = self.float_accessor(output, width, kind, False, False)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("input")
        writer.integer(input)
        writer.key("output")
        writer.integer(values)
        writer.key("interpolation")
        writer.string(interpolation)
        writer.end_object()
        samplers.append(writer.finish())
        var channel = JsonWriter()
        channel.begin_object()
        channel.key("sampler")
        channel.integer(len(samplers) - 1)
        channel.key("target")
        channel.begin_object()
        channel.key("node")
        channel.integer(node)
        channel.key("path")
        channel.string(path)
        channel.end_object()
        channel.end_object()
        channels.append(channel.finish())

    def document(
        self,
        roots: List[Int],
        nodes: List[String],
        uri: String,
        scene: _UserParts,
    ) raises -> String:
        """Return the whole JSON document. The buffer is padded already."""
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("asset")
        writer.begin_object()
        writer.key("version")
        writer.string("2.0")
        writer.key("generator")
        writer.string("ThreeMojo GLTFExporter")
        writer.end_object()
        if len(self.used) > 0:
            writer.key("extensionsUsed")
            writer.begin_array()
            for name in self.used:  # pragma: no branch
                writer.string(name)
            writer.end_array()
        if len(self.required) > 0:
            writer.key("extensionsRequired")
            writer.begin_array()
            for name in self.required:  # pragma: no branch
                writer.string(name)
            writer.end_array()
        if len(self.lights) > 0:
            writer.key("extensions")
            writer.begin_object()
            writer.key(LIGHTS_PUNCTUAL)
            writer.begin_object()
            _write_array(writer, "lights", self.lights)
            writer.end_object()
            writer.end_object()
        writer.key("scene")
        writer.integer(0)
        writer.key("scenes")
        writer.begin_array()
        writer.begin_object()
        if len(roots) > 0:
            writer.key("nodes")
            _write_integers(writer, roots)
        if scene.extras != "":
            writer.key("extras")
            writer.raw(scene.extras)
        if len(scene.names) > 0:
            writer.key("extensions")
            writer.raw(_with_custom(scene, ""))
        writer.end_object()
        writer.end_array()
        _write_array(writer, "nodes", nodes)
        _write_array(writer, "meshes", self.meshes)
        _write_array(writer, "cameras", self.cameras)
        _write_array(writer, "skins", self.skins)
        _write_array(writer, "animations", self.animations)
        _write_array(writer, "materials", self.materials)
        _write_array(writer, "textures", self.textures)
        _write_array(writer, "images", self.images)
        _write_array(writer, "samplers", self.samplers)
        _write_array(writer, "accessors", self.accessors)
        _write_array(writer, "bufferViews", self.views)
        if len(self.bin) > 0:
            writer.key("buffers")
            writer.begin_array()
            writer.begin_object()
            writer.key("byteLength")
            writer.integer(len(self.bin))
            if uri != "":
                writer.key("uri")
                writer.string(uri)
            writer.end_object()
            writer.end_array()
        writer.end_object()
        return writer.finish()


struct _Carried(Copyable, Movable):
    """What one written node carries, by its index in each of the scene's
    lists, or -1 for no light and no camera."""

    var meshes: List[Int]
    var skinned: List[Int]
    var instanced: List[Int]
    var lines: List[Int]
    var points: List[Int]
    var light: Int
    var perspective: Int
    var orthographic: Int

    def __init__(out self):
        """Carry nothing."""
        self.meshes = List[Int]()
        self.skinned = List[Int]()
        self.instanced = List[Int]()
        self.lines = List[Int]()
        self.points = List[Int]()
        self.light = -1
        self.perspective = -1
        self.orthographic = -1

    def has_camera(self) -> Bool:
        """Return True if a camera rides the node already."""
        return self.perspective >= 0 or self.orthographic >= 0


struct _Merged(Copyable, Movable):
    """The morph tracks of one node merged into one `weights` channel, as
    three.js's `mergeMorphTargetTracks` merges them: every key of every
    track, and at each key a weight for every target."""

    # The node's index in the file, and how many targets its mesh has.
    var node: Int
    var count: Int
    # Whether the channel is a cubic spline, which merges only with cubic
    # splines at the same times, or steps.
    var cubic: Bool
    var step: Bool
    var times: List[Float32]
    # `count` weights a key, and for a cubic spline its two tangents.
    var values: List[Float32]
    var ins: List[Float32]
    var outs: List[Float32]

    def __init__(out self, node: Int, count: Int, track: KeyframeTrack):
        """Start from a node's first morph track, as three.js clones it.
        A track that is neither a cubic spline nor steps is linear.

        Args:
            node: The node's index in the file.
            count: How many morph targets its mesh has.
            track: The first morph track.
        """
        self.node = node
        self.count = count
        self.cubic = track.interpolation == CUBIC_SPLINE
        self.step = track.interpolation == STEP
        self.times = track.times.copy()
        var size = len(self.times) * count
        self.values = List[Float32](length=size, fill=0)
        self.ins = List[Float32](length=size if self.cubic else 0, fill=0)
        self.outs = List[Float32](length=size if self.cubic else 0, fill=0)
        self.fill(track)

    def fill(mut self, track: KeyframeTrack):
        """Copy a track keyed at the same times into its target's lane."""
        var target = track.target.slot
        # A track has at least one key.
        for key in range(len(self.times)):  # pragma: no branch
            var at = key * self.count + target
            self.values[at] = track.values[key]
            if self.cubic:
                self.ins[at] = track.in_tangents[key]
                self.outs[at] = track.out_tangents[key]

    def merge(mut self, track: KeyframeTrack) raises:
        """Merge one more of the node's morph tracks in.

        Its lane takes its value at every key the channel has, and each
        of its own keys is added to the channel when no key is within a
        millisecond of it, with every other lane's value there, as
        three.js's `insertKeyframe` adds it.

        Args:
            track: The track.

        Raises:
            Error: If either is a cubic spline and they are not both cubic
                splines at the same times, as three.js refuses to merge a
                cubic spline.
        """
        var cubic = track.interpolation == CUBIC_SPLINE
        if self.cubic or cubic:
            if not (self.cubic and cubic and self.times == track.times):
                raise Error(
                    "glTF: the morph tracks of one node are one weights"
                    " channel, and a cubic spline merges only with cubic"
                    " splines at the same times"
                )
            self.fill(track)
            return
        var target = track.target.slot
        var step = track.interpolation == STEP
        # The channel and a track each have at least one key.
        for key in range(len(self.times)):  # pragma: no branch
            self.values[key * self.count + target] = _sample(
                track.times, track.values, 1, self.times[key], step
            )[0]
        for key in range(len(track.times)):  # pragma: no branch
            var at = self.insert(track.times[key])
            self.values[at * self.count + target] = track.values[key]

    def insert(mut self, time: Float32) -> Int:
        """Return the key within a millisecond of `time`, or add one there
        with the channel's own value at that time, and return it."""
        var at = 0
        while at < len(self.times) and self.times[at] < time:
            at += 1
        if at > 0 and abs(self.times[at - 1] - time) < KEY_TOLERANCE:
            return at - 1
        if at < len(self.times) and abs(self.times[at] - time) < KEY_TOLERANCE:
            return at
        var sampled = _sample(
            self.times, self.values, self.count, time, self.step
        )
        self.times.insert(at, time)
        # A node with a morph track has at least one target.
        for lane in range(self.count):  # pragma: no branch
            self.values.insert(at * self.count + lane, sampled[lane])
        return at

    def output(self) -> List[Float32]:
        """Return the sampler's output: the weights key by key, and for a
        cubic spline each key's in-tangents, weights and out-tangents, as
        glTF lays them out."""
        if not self.cubic:
            return self.values.copy()
        var out = List[Float32]()
        # A track has at least one key.
        for key in range(len(self.times)):  # pragma: no branch
            var start = key * self.count
            out.extend(self.ins[start : start + self.count])
            out.extend(self.values[start : start + self.count])
            out.extend(self.outs[start : start + self.count])
        return out^

    def interpolation(self) -> String:
        """Return the sampler's interpolation."""
        if self.cubic:
            return "CUBICSPLINE"
        return "STEP" if self.step else "LINEAR"


# How close two key times are to be one key, in seconds: three.js's
# `insertKeyframe` tolerance of a millisecond.
comptime KEY_TOLERANCE = Float32(0.001)


def _sample(
    times: List[Float32],
    values: List[Float32],
    width: Int,
    at: Float32,
    step: Bool,
) -> List[Float32]:
    """Return a run of keys' value at a time, as three.js's
    `LinearInterpolant` and `DiscreteInterpolant` give it: the first key's
    before it, the last key's after it, and between two keys the value
    blended linearly or the earlier key's."""
    var last = len(times) - 1
    var key = 0
    while key < last and times[key + 1] <= at:
        key += 1
    var blend = Float32(0)
    if key < last and not step and at > times[key]:
        blend = (at - times[key]) / (times[key + 1] - times[key])
    var out = List[Float32]()
    var next = min(key + 1, last)
    # Every caller reads at least one lane.
    for lane in range(width):  # pragma: no branch
        var here = values[key * width + lane]
        out.append(here + (values[next * width + lane] - here) * blend)
    return out^


def _output(track: KeyframeTrack) -> List[Float32]:
    """Return a node track's sampler output: its values, and for a cubic
    spline each key's in-tangent, value and out-tangent, as glTF lays
    them out."""
    if track.interpolation != CUBIC_SPLINE:
        return track.values.copy()
    var width = track.target.kind.component_count()
    var out = List[Float32]()
    # A track has at least one key.
    for key in range(len(track.times)):  # pragma: no branch
        var start = key * width
        out.extend(track.in_tangents[start : start + width])
        out.extend(track.values[start : start + width])
        out.extend(track.out_tangents[start : start + width])
    return out^


def _path_of(kind: TrackKind) -> String:
    """Return the channel path a node track drives, three.js's
    `PATH_PROPERTIES`."""
    if kind == TRANSLATION_KIND:
        return "translation"
    if kind == QUATERNION:
        return "rotation"
    return "scale"


def _interpolation_name(how: Interpolation) -> String:
    """Return a track's interpolation as glTF names it. Only a step and a
    cubic spline have names of their own there, and every other track is
    written `LINEAR`, as three.js writes one."""
    if how == STEP:
        return "STEP"
    if how == CUBIC_SPLINE:
        return "CUBICSPLINE"
    return "LINEAR"


def _morph_node(track: KeyframeTrack, scene: Scene) raises -> NodeId:
    """Return the node of the mesh or the skinned mesh a morph track
    drives."""
    var index = track.target.index
    if track.target.kind == MORPH_INFLUENCE:
        if index < 0 or index >= len(scene.meshes):
            raise Error("glTF: a morph track names a mesh that is not there")
        return scene.meshes[index].node
    if index < 0 or index >= len(scene.skinned_meshes):
        raise Error("glTF: a morph track names a mesh that is not there")
    return scene.skinned_meshes[index].node


def _written_slot(node: NodeId, written: List[Int], what: String) raises -> Int:
    """Return a scene node's index in the file, or -1 when it is left out."""
    if node.value < 0 or node.value >= len(written):
        raise Error("glTF: " + what + " names a node that is not in the scene")
    return written[node.value]


def _geometries(scene: Scene, carried: _Carried) -> List[GeometryId]:
    """Return the geometry of everything a node draws, in the order its
    primitives are written."""
    var found = List[GeometryId]()
    for which in carried.meshes:
        found.append(scene.meshes[which].geometry)
    for which in carried.skinned:
        found.append(scene.skinned_meshes[which].geometry)
    for which in carried.instanced:
        found.append(scene.instanced_meshes[which].geometry)
    for which in carried.lines:
        found.append(scene.lines[which].geometry)
    for which in carried.points:
        found.append(scene.points[which].geometry)
    return found^


def _morph_count(shapes: List[GeometryId], assets: Assets) raises -> Int:
    """Return how many morph targets the geometries of one glTF mesh carry,
    which must be as many for each: the specification asks it."""
    var count = 0
    for at in range(len(shapes)):
        var own = assets.geometries.get(shapes[at]).morph_count()
        if at > 0 and own != count:
            raise Error(
                "glTF: the meshes on one node must carry as many morph"
                " targets: glTF gives the primitives of a mesh one set"
            )
        count = own
    return count


def _weights(
    scene: Scene, carried: _Carried, morphs: Int
) raises -> List[Float32]:
    """Return the morph influences the meshes on one node wear, which must
    be one set: glTF gives a mesh one `weights`. Zero for a node whose
    geometry has targets and whose things wear none, as three.js's
    `InstancedMesh`, `Line` and `Points` start at zero."""
    var worn = List[MorphInfluences]()
    for which in carried.meshes:
        worn.append(scene.meshes[which].morph_influences)
    for which in carried.skinned:
        worn.append(scene.skinned_meshes[which].morph_influences)
    var weights = List[Float32](length=morphs, fill=0)
    for at in range(len(worn)):
        for target in range(morphs):
            if at > 0 and worn[at][target] != weights[target]:
                raise Error(
                    "glTF: the meshes on one node must wear one set of morph"
                    " influences: glTF gives a mesh one set of weights"
                )
            weights[target] = worn[at][target]
    return weights^


def target_name(geometry: BufferGeometry, target: Int) -> String:
    """Return a morph target's name as three.js's `GLTFExporter` writes it
    in `targetNames`: its own name, or its index when it has none, as
    three.js's `updateMorphTargets` names it.

    Args:
        geometry: The geometry.
        target: Which morph target, from zero.

    Returns:
        The name.
    """
    var named = target < len(geometry.morph_names)
    return geometry.morph_names[target] if named and geometry.morph_names[
        target
    ] != "" else String(target)


def line_mode_code(mode: LineMode) -> Int:
    """Return a line's mode as glTF's primitive mode.

    Args:
        mode: A valid line mode.

    Returns:
        `MODE_LINES` for `SEGMENTS`, `MODE_LINE_LOOP` for `LOOP`, and
        `MODE_LINE_STRIP` for `STRIP`.
    """
    if mode == SEGMENTS:
        return MODE_LINES
    if mode == LOOP:
        return MODE_LINE_LOOP
    return MODE_LINE_STRIP


def _is_punctual(kind: LightKind) -> Bool:
    """Return True for the three kinds `KHR_lights_punctual` holds."""
    return kind == DIRECTIONAL or kind == POINT or kind == SPOT


def _light_type(kind: LightKind) -> String:
    """Return a punctual light's `type`."""
    if kind == DIRECTIONAL:
        return "directional"
    if kind == POINT:
        return "point"
    return "spot"


def _check_skin(shape: BufferGeometry, bones: Int) raises:
    """Refuse a skinned geometry whose `skinIndex` and `skinWeight` glTF
    cannot hold: four of each a vertex, and every index a whole number
    that names a bone."""
    if not shape.has_attribute(String(SKIN_INDEX)) or not shape.has_attribute(
        String(SKIN_WEIGHT)
    ):
        raise Error("glTF: a skinned geometry needs skinIndex and skinWeight")
    ref joints = shape.attribute_view(String(SKIN_INDEX))
    if (
        joints.item_size != 4
        or shape.attribute_view(String(SKIN_WEIGHT)).item_size != 4
    ):
        raise Error("glTF: a skinned geometry has four bones a vertex")
    # A skinned geometry has at least one vertex.
    for value in joints.packed():  # pragma: no branch
        if value < 0 or value >= Float32(bones) or value != floor(value):
            raise Error(
                "glTF: a skin index must be a whole number that names a bone"
            )


def _same_instances(first: InstancedMesh, other: InstancedMesh) raises -> Bool:
    """Return True if two instanced meshes place and color their instances
    alike."""
    var same = first.count() == other.count() and len(first.colors) == len(
        other.colors
    )
    for at in range(min(first.count(), other.count())):
        same = (
            same
            and first.matrices[at] == other.matrices[at]
            and _same_color(first.color_at(at), other.color_at(at))
        )
    return same


def _same_color(first: Color, other: Color) -> Bool:
    """Return True if two colors are one."""
    return (
        first.r == other.r
        and first.g == other.g
        and first.b == other.b
        and first.a == other.a
    )


def _same_skin(first: SkinnedMesh, other: SkinnedMesh) -> Bool:
    """Return True if two skinned meshes share one skeleton and one bind
    matrix."""
    var same = (
        first.bind_matrix == other.bind_matrix
        and first.skeleton.bone_count() == other.skeleton.bone_count()
    )
    # A skeleton has at least one bone.
    for at in range(
        min(first.skeleton.bone_count(), other.skeleton.bone_count())
    ):  # pragma: no branch
        same = (
            same
            and first.skeleton.bones[at].node == other.skeleton.bones[at].node
            and first.skeleton.bones[at].inverse_bind
            == other.skeleton.bones[at].inverse_bind
        )
    return same


def _offsets(
    geometry: BufferGeometry, target: BufferAttribute, name: String
) raises -> List[Float32]:
    """Return one morph target as glTF's offsets: as it is when the
    geometry holds offsets, and less the base attribute when it holds
    finished values, as three.js's `GLTFExporter` takes them off."""
    var moved = target.packed()
    if geometry.morph_relative:
        return moved^
    if not geometry.has_attribute(name):
        raise Error(
            "glTF: a geometry's morph normals need its normals, to be"
            " written as offsets"
        )
    var base = geometry.attribute_view(name).packed()
    # A morph target covers every vertex, and there is at least one.
    for at in range(len(moved)):  # pragma: no branch
        moved[at] -= base[at]
    return moved^


def _is_opaque_white(color: FloatColor, opacity: Float32) -> Bool:
    """Return True for glTF's default base color: white, opaque."""
    return color.r == 1 and color.g == 1 and color.b == 1 and opacity == 1


def _is_white(color: Color) -> Bool:
    """Return True for white, the default specular and attenuation color."""
    return color.r == 255 and color.g == 255 and color.b == 255


def _has_specular(material: Material) -> Bool:
    """Return True if `KHR_materials_specular` has something to say."""
    return (
        material.specular_intensity != 1
        or not _is_white(material.specular_color)
        or material.specular_intensity_map != NO_TEXTURE
        or material.specular_color_map != NO_TEXTURE
    )


def _has_clearcoat(material: Material) -> Bool:
    """Return True if `KHR_materials_clearcoat` has something to say."""
    return material.clearcoat != 0 or material.clearcoat_roughness != 0


def _has_transmission(material: Material) -> Bool:
    """Return True if `KHR_materials_transmission` has something to say."""
    return material.transmission != 0 or material.transmission_map != NO_TEXTURE


def _has_volume(material: Material) -> Bool:
    """Return True if `KHR_materials_volume` has something to say."""
    return (
        material.thickness.to(METER) != 0
        or material.thickness_map != NO_TEXTURE
        or isfinite(material.attenuation_distance.to(METER))
        or not _is_white(material.attenuation_color)
    )


def _write_color(mut writer: JsonWriter, color: Color) raises:
    """Write a color as glTF holds a factor: three linear numbers."""
    var linear = FloatColor(srgb=color)
    _write_numbers(writer, [linear.r, linear.g, linear.b])


def _copy_channel(
    mut pixels: List[UInt8],
    id: TextureId,
    channel: Int,
    leader: Texture,
    assets: Assets,
) raises:
    """Copy one channel of a texture into a combined image, when the id
    names a texture."""
    if id == NO_TEXTURE:
        return
    ref texture = assets.textures.get(id)
    if texture.width != leader.width or texture.height != leader.height:
        raise Error(
            "glTF: a roughness map and a metalness map must be one size to"
            " be combined"
        )
    # One texture reference carries one transform and one set.
    if GltfPlacement.of(texture) != GltfPlacement.of(leader):
        raise Error(
            "glTF: a roughness map and a metalness map must share one"
            " transform and one channel to be combined"
        )
    var source = gltf_pixels(texture)
    # A texture `gltf_pixels` accepts has at least one texel.
    for texel in range(texture.width * texture.height):  # pragma: no branch
        pixels[texel * 4 + channel] = source[texel * 4 + channel]


def _write_numbers(mut writer: JsonWriter, numbers: List[Float32]) raises:
    """Write an array of numbers."""
    writer.begin_array()
    # Every caller writes at least one number.
    for value in numbers:  # pragma: no branch
        writer.number(value)
    writer.end_array()


def _gl_component(type: ComponentType) -> Int:
    """Return the glTF component type of an 8- or 16-bit typed array, as
    three.js's `processAccessor` reads it off the array."""
    if type == INT8_COMPONENT:
        return COMPONENT_BYTE
    if type == UINT8_COMPONENT:
        return COMPONENT_UNSIGNED_BYTE
    if type == INT16_COMPONENT:
        return COMPONENT_SHORT
    return COMPONENT_UNSIGNED_SHORT


def _is_quantized(
    semantic: String, type: ComponentType, normalized: Bool
) -> Bool:
    """Return True if `KHR_mesh_quantization` is what allows an 8- or
    16-bit attribute, three.js's `KHR_mesh_quantization_ExtraAttrTypes`.

    Args:
        semantic: The attribute's name without its set number: `POSITION`,
            `NORMAL`, `TEXCOORD`, `COLOR` or `WEIGHTS`.
        type: Its component type.
        normalized: Whether it is normalized.

    Returns:
        Whether the extension must be required.
    """
    var signed = type == INT8_COMPONENT or type == INT16_COMPONENT
    if semantic == "POSITION":
        return True
    if semantic == "NORMAL":
        return signed and normalized
    if semantic == "TEXCOORD":
        # Every type but the normalized unsigned ones, which glTF allows.
        return signed or not normalized
    return False


def _write_integers(mut writer: JsonWriter, numbers: List[Int]) raises:
    """Write an array of whole numbers."""
    writer.begin_array()
    # Every caller writes at least one number.
    for value in numbers:  # pragma: no branch
        writer.integer(value)
    writer.end_array()


def _write_array(
    mut writer: JsonWriter, key: String, entries: List[String]
) raises:
    """Write a top-level array of JSON texts under `key`, or nothing when
    it is empty: the specification asks for at least one entry."""
    if len(entries) == 0:
        return
    writer.key(key)
    writer.begin_array()
    for entry in entries:  # pragma: no branch
        writer.raw(entry)
    writer.end_array()


def _node_json(
    node: Object3D,
    mesh: Int,
    children: List[Int],
    camera: Int,
    skin: Int,
    extras: String,
    extensions: String,
) raises -> String:
    """Return one node as glTF writes it: -1 for no mesh, camera or
    skin, and an empty string for no extras and no extensions."""
    var writer = JsonWriter()
    writer.begin_object()
    if node.name != "":
        writer.key("name")
        writer.string(node.name)
    if node.matrix_auto_update:
        if not _is_zero(node.position):
            writer.key("translation")
            _write_numbers(
                writer, [node.position.x, node.position.y, node.position.z]
            )
        if not _is_identity_rotation(node.quaternion):
            writer.key("rotation")
            _write_numbers(
                writer,
                [
                    node.quaternion.x,
                    node.quaternion.y,
                    node.quaternion.z,
                    node.quaternion.w,
                ],
            )
        if not _is_one(node.scale):
            writer.key("scale")
            _write_numbers(writer, [node.scale.x, node.scale.y, node.scale.z])
    elif not _is_identity_matrix(node.matrix):
        var elements = List[Float32]()
        for index in range(16):  # pragma: no branch
            elements.append(node.matrix.elements[index])
        writer.key("matrix")
        _write_numbers(writer, elements)
    if extras != "":
        writer.key("extras")
        writer.raw(extras)
    if mesh >= 0:
        writer.key("mesh")
        writer.integer(mesh)
    if camera >= 0:
        writer.key("camera")
        writer.integer(camera)
    if skin >= 0:
        writer.key("skin")
        writer.integer(skin)
    if len(children) > 0:
        writer.key("children")
        _write_integers(writer, children)
    if extensions != "":
        writer.key("extensions")
        writer.raw(extensions)
    writer.end_object()
    return writer.finish()


def _glb(json: String, bin: List[UInt8]) -> List[UInt8]:
    """Return the binary container: the header, the JSON chunk padded
    with spaces, and the binary chunk when there is one."""
    var text = List[UInt8]()
    text.extend(json.as_bytes())
    while len(text) % 4 != 0:
        text.append(32)
    var total = 12 + 8 + len(text)
    if len(bin) > 0:
        total += 8 + len(bin)
    var out = List[UInt8](capacity=total)
    push_word(out, GLB_MAGIC, 4, True)
    push_word(out, GLB_VERSION, 4, True)
    push_word(out, total, 4, True)
    push_word(out, len(text), 4, True)
    push_word(out, GLB_JSON_CHUNK, 4, True)
    out.extend(Span(text))
    if len(bin) > 0:
        push_word(out, len(bin), 4, True)
        push_word(out, GLB_BIN_CHUNK, 4, True)
        out.extend(Span(bin))
    return out^


def export_gltf(
    scene: Scene,
    assets: Assets,
    container: GltfContainer = GLTF_EMBEDDED,
    binary_name: String = "scene.bin",
    only_visible: Bool = True,
    cameras: CameraList = CameraList(),
    animations: List[AnimationClip] = List[AnimationClip](),
    options: GltfExportOptions = GltfExportOptions(),
) raises -> GltfFiles:
    """Return a scene and the assets it draws with as a glTF 2.0 file.

    Nodes are written in `Scene.traverse` order, a parent before its
    children, so node `k` of the file is the `k`th node written.

    Args:
        scene: The scene. It need not be current: nodes are written by
            their own transforms, and no world matrix is read.
        assets: Where its geometries, materials and textures are.
        container: `GLTF_EMBEDDED`, `GLTF_SEPARATE` or `GLB`.
        binary_name: The name the buffer's URI gives the `.bin`, for
            `GLTF_SEPARATE`; read beside the `.gltf`.
        only_visible: True, as three.js's `onlyVisible` is, to leave out
            a node that is hidden, what is under it, and what it carries.
        cameras: The cameras to write, each riding a node of the scene, as
            three.js writes a camera in the scene graph.
        animations: The clips to write, as three.js's `animations` option
            writes them.
        options: The texture size limit, the custom extensions, and the
            user data of the scene and the materials.

    Returns:
        The file, and the `.bin` for `GLTF_SEPARATE`.

    Raises:
        Error: If the container is none of the three, the `.bin` name is
            empty or has a scheme, a mesh, a light, a camera, a bone or a
            track names a node that is not in the scene, or a geometry,
            material or texture that is not there, a geometry is refused
            by `exporters.common.check_geometry` or has no vertices, a
            texture is refused by `gltf_pixels`, a combined roughness and
            metalness map are not one size or do not share one transform
            and one channel, or a number is not finite. Also if one node
            carries two lights or two cameras, or what the module
            docstring says a node cannot carry together, a light or a
            camera is refused by its own checks, an orthographic camera is
            not centered, a bone's node is not written, a skinned
            geometry's skin is not four whole bone indices and four
            weights a vertex, an instanced mesh has no instances, a line
            or points geometry is indexed, or a clip's morph tracks name a
            target that is not there or cannot be merged. Also if
            `max_texture_size` is below one, or custom extensions are
            written and a `gltfExtensions` is not an object.
    """
    if not container.is_valid():
        raise Error("glTF: a container that is none of the three")
    if Bool(options.max_texture_size) and options.max_texture_size.value() < 1:
        raise Error("glTF: maxTextureSize must be one pixel or more")
    if container == GLTF_SEPARATE and not _is_relative_name(binary_name):
        raise Error("glTF: the .bin needs a relative name: " + binary_name)
    var count = scene.count()
    # Each scene node's index in the file, or -1 when it is left out.
    var written = List[Int](length=count, fill=-1)
    var kept = List[Int]()
    var roots = List[Int]()
    var children = List[List[Int]]()
    var carried = List[_Carried]()
    for id in scene.traverse():
        var index = id.value
        var node = scene.get(id)
        var parent = node.parent
        var shown = (not only_visible or node.visible) and (
            parent == NO_PARENT or written[parent.value] >= 0
        )
        if not shown:
            continue
        written[index] = len(kept)
        kept.append(index)
        children.append(List[Int]())
        carried.append(_Carried())
        if parent == NO_PARENT:
            roots.append(written[index])
        else:
            children[written[parent.value]].append(written[index])
    _carry(scene, cameras, written, carried)
    var exporter = _Exporter(container != GLB, options.copy())
    var meshes = List[Int]()
    var instancing = List[String]()
    var morphs = List[Int]()
    for at in range(len(kept)):
        meshes.append(exporter.mesh(scene, carried[at], assets))
        instancing.append(exporter.instancing(scene, carried[at]))
        morphs.append(_morph_count(_geometries(scene, carried[at]), assets))
    var skins = List[Int]()
    for at in range(len(kept)):
        skins.append(exporter.skin(scene, carried[at], written))
    var nodes = List[String]()
    for at in range(len(kept)):
        var node = scene.get(NodeId(kept[at]))
        var camera = -1
        if carried[at].perspective >= 0:
            camera = exporter.perspective(
                cameras.perspective[carried[at].perspective], node.name
            )
        elif carried[at].orthographic >= 0:
            camera = exporter.orthographic(
                cameras.orthographic[carried[at].orthographic], node.name
            )
        var parts = exporter.user_parts(node.user_data)
        var extensions = JsonWriter()
        extensions.begin_object()
        if carried[at].light >= 0:
            extensions.key(LIGHTS_PUNCTUAL)
            extensions.begin_object()
            extensions.key("light")
            extensions.integer(
                exporter.light(scene.lights[carried[at].light], node.name)
            )
            extensions.end_object()
        if instancing[at] != "":
            extensions.key(GPU_INSTANCING)
            extensions.raw(instancing[at])
        extensions.end_object()
        var extended = carried[at].light >= 0 or instancing[at] != ""
        nodes.append(
            _node_json(
                node,
                meshes[at],
                children[at],
                camera,
                skins[at],
                parts.extras,
                _with_custom(parts, extensions.finish() if extended else ""),
            )
        )
    for clip in animations:
        exporter.animation(clip, scene, written, morphs)
    var top = exporter.user_parts(options.scene_user_data)
    exporter.pad()
    var files = GltfFiles()
    if container == GLB:
        files.document = _glb(
            exporter.document(roots, nodes, "", top), exporter.bin
        )
        return files^
    var uri = binary_name
    if container == GLTF_SEPARATE:
        files.binary = exporter.bin.copy()
    else:
        uri = "data:application/octet-stream;base64," + encode_base64(
            exporter.bin
        )
    files.document.extend(exporter.document(roots, nodes, uri, top).as_bytes())
    return files^


def _carry(
    scene: Scene,
    cameras: CameraList,
    written: List[Int],
    mut carried: List[_Carried],
) raises:
    """Hand everything the scene draws, lights and the cameras see to the
    written node it rides. What rides a node that is left out is left out
    with it; what rides a node the scene has not got is refused."""
    for which in range(len(scene.meshes)):
        var slot = _written_slot(scene.meshes[which].node, written, "a mesh")
        if slot >= 0:
            carried[slot].meshes.append(which)
    for which in range(len(scene.skinned_meshes)):
        var slot = _written_slot(
            scene.skinned_meshes[which].node, written, "a mesh"
        )
        if slot >= 0:
            carried[slot].skinned.append(which)
    for which in range(len(scene.instanced_meshes)):
        var slot = _written_slot(
            scene.instanced_meshes[which].node, written, "a mesh"
        )
        if slot >= 0:
            carried[slot].instanced.append(which)
    for which in range(len(scene.lines)):
        var slot = _written_slot(scene.lines[which].node, written, "a line")
        if slot >= 0:
            carried[slot].lines.append(which)
    for which in range(len(scene.points)):
        var slot = _written_slot(scene.points[which].node, written, "points")
        if slot >= 0:
            carried[slot].points.append(which)
    for which in range(len(scene.lights)):
        ref light = scene.lights[which]
        if not light.kind.is_valid():
            raise Error("glTF: a light of a kind that is none of the named")
        light.validate()
        if not _is_punctual(light.kind):
            continue
        var slot = _written_slot(light.node, written, "a light")
        if slot < 0:
            continue
        if carried[slot].light >= 0:
            raise Error("glTF: a node carries one light, and two ride one")
        carried[slot].light = which
    for which in range(len(cameras.perspective)):
        var slot = _written_slot(
            cameras.perspective[which].node, written, "a camera"
        )
        if slot < 0:
            continue
        if carried[slot].has_camera():
            raise Error("glTF: a node carries one camera, and two ride one")
        carried[slot].perspective = which
    for which in range(len(cameras.orthographic)):
        var slot = _written_slot(
            cameras.orthographic[which].node, written, "a camera"
        )
        if slot < 0:
            continue
        if carried[slot].has_camera():
            raise Error("glTF: a node carries one camera, and two ride one")
        carried[slot].orthographic = which


def write_gltf(
    path: String,
    scene: Scene,
    assets: Assets,
    container: GltfContainer = GLTF_EMBEDDED,
    only_visible: Bool = True,
    cameras: CameraList = CameraList(),
    animations: List[AnimationClip] = List[AnimationClip](),
    options: GltfExportOptions = GltfExportOptions(),
) raises:
    """Write a scene and its assets to a `.gltf` or a `.glb` file.

    For `GLTF_SEPARATE` the `.bin` goes beside the file, named by
    `binary_name_for`, and is written only when the scene has something
    to put in it.

    Args:
        path: The file.
        scene: The scene.
        assets: Where its geometries, materials and textures are.
        container: `GLTF_EMBEDDED`, `GLTF_SEPARATE` or `GLB`.
        only_visible: True to leave out what is hidden; see
            `export_gltf`.
        cameras: The cameras to write; see `export_gltf`.
        animations: The clips to write; see `export_gltf`.
        options: The other options; see `export_gltf`.

    Raises:
        Error: If a file cannot be written, or anything `export_gltf`
            raises.
    """
    var name = binary_name_for(path)
    var files = export_gltf(
        scene,
        assets,
        container,
        name,
        only_visible,
        cameras,
        animations,
        options,
    )
    Path(path).write_bytes(files.document)
    if len(files.binary) > 0:
        var directory = String(path[byte = 0 : path.rfind("/") + 1])
        Path(directory + name).write_bytes(files.binary)
