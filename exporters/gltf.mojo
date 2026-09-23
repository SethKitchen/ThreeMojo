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
with a metalness of zero and a roughness of one, and a `BASIC` material
also says `KHR_materials_unlit`. An ao map is the `occlusionTexture`, its
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
image is written upside down, as three.js writes a `flipY` texture. A
texture that `read_gltf` made already carries the flip in its `repeat`
and `offset`, so its image is written as it is. A texture moved, tiled or
turned is written with `KHR_texture_transform`, as three.js's
`applyTextureTransform` writes it; see `GltfPlacement`. glTF keeps
roughness and metalness in one image, green and blue: when a material's
two maps are one texture it is written once, and when they differ they
are combined into one image of the same size, as three.js's
`buildMetalRoughTexture` combines them. Two maps combined must share one
transform and one channel, since one reference carries them.

**Not written.** Lights, cameras, animations, skins, morph targets,
instanced, batched and skinned meshes, lines, points and sprites, and
every map glTF has no place for: bump, alpha, light, specular,
displacement, environment, matcap and gradient maps. An ao map on a
`BASIC` material is written, as three.js writes it, but `read_gltf` reads
no occlusion for an unlit material. A `BACK_SIDE` material is written single-sided, as three.js
writes it, since glTF has no back side. A geometry's groups are not split
into primitives: a mesh here has one material.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, UV1
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.common import check_geometry, push_f32, push_word
from exporters.json_writer import JsonWriter
from loaders.gltf import (
    COMPONENT_FLOAT,
    COMPONENT_UNSIGNED_INT,
    COMPONENT_UNSIGNED_SHORT,
    EMISSIVE_STRENGTH,
    FILTER_LINEAR,
    FILTER_LINEAR_MIPMAP_LINEAR,
    FILTER_NEAREST,
    FILTER_NEAREST_MIPMAP_NEAREST,
    GLB_BIN_CHUNK,
    GLB_JSON_CHUNK,
    GLB_MAGIC,
    GLB_VERSION,
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
    MODE_TRIANGLES,
    TEXTURE_TRANSFORM,
    WRAP_CLAMP,
    WRAP_MIRROR,
    WRAP_REPEAT,
)
from materials.material import (
    BASIC,
    DEFAULT_IOR,
    DOUBLE_SIDE,
    NO_TEXTURE,
    PHYSICAL,
    Material,
    MaterialId,
)
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer
from render.png import encode as encode_png
from render.texture import CLAMP, FLOAT_TYPE, MIRROR, NEAREST, Texture
from render.texture_store import TextureId
from std.math import isfinite
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
    """Return True if a texture's image is written upside down: one whose
    `repeat.y` is not negative, where `read_gltf` sets it to minus one.

    Either way the texture samples as it does here, since
    `GltfPlacement.of` writes the transform that matches the image.
    """
    return texture.repeat.y >= 0


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
        the same. Where its image is written as it is, the flip of `v` is
        folded in: the offset's `v` is one minus the matrix's, and the
        scale's `v` is negated.

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
        if _is_written_upside_down(texture):
            return GltfPlacement(
                Vector2(u, v),
                Vector2(texture.repeat.x, texture.repeat.y),
                turn,
                set,
            )
        return GltfPlacement(
            Vector2(u, 1 - v),
            Vector2(texture.repeat.x, -texture.repeat.y),
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

    The image is written upside down when its `repeat.y` is not negative,
    as three.js writes a `flipY` texture, and as it is otherwise, as
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


def _wrap_code(texture: Texture) -> Int:
    """Return a texture's wrap as glTF's constant; the texture is valid."""
    if texture.wrap == CLAMP:
        return WRAP_CLAMP
    if texture.wrap == MIRROR:
        return WRAP_MIRROR
    return WRAP_REPEAT


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
    # The extensions written, each once, in the order first written.
    var used: List[String]

    def __init__(out self, embed: Bool):
        """Start an empty document.

        Args:
            embed: True to write images as `data:` URIs.
        """
        self.embed = embed
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
        self.used = List[String]()

    def use(mut self, name: String):
        """Add an extension to `extensionsUsed`, once."""
        for known in self.used:
            if known == name:
                return
        self.used.append(name)

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
        mut self, data: List[Float32], width: Int, kind: String, bounded: Bool
    ) raises -> Int:
        """Write an attribute of `Float32`s and return its accessor."""
        var bytes = List[UInt8](capacity=len(data) * 4)
        # `geometry` refuses a geometry with no vertices before this.
        for value in data:  # pragma: no branch
            push_f32(bytes, value, True)
        var view = self.view(bytes, ARRAY_BUFFER, width * 4)
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
        mut self, id: GeometryId, colored: Bool, assets: Assets
    ) raises -> Int:
        """Write a geometry's accessors, once, and its colors once they
        are asked for; return its slot in the geometry lists."""
        ref geometry = assets.geometries.get(id)
        var slot = -1
        for at in range(len(self.geometry_keys)):
            if self.geometry_keys[at] == id.value:
                slot = at
        if slot < 0:
            var count = check_geometry(geometry)
            if count == 0:
                raise Error("glTF: a geometry with no vertices is not written")
            self.geometry_keys.append(id.value)
            self.positions.append(
                self.float_accessor(
                    geometry.attribute_view(POSITION).packed(), 3, "VEC3", True
                )
            )
            var normal = -1
            if geometry.has_attribute(NORMAL):
                normal = self.float_accessor(
                    geometry.attribute_view(NORMAL).packed(), 3, "VEC3", False
                )
            self.normals.append(normal)
            var uv = -1
            if geometry.has_attribute(UV):
                uv = self.float_accessor(
                    geometry.attribute_view(UV).packed(), 2, "VEC2", False
                )
            self.uvs.append(uv)
            var uv1 = -1
            if geometry.has_attribute(UV1):
                uv1 = self.float_accessor(
                    geometry.attribute_view(UV1).packed(), 2, "VEC2", False
                )
            self.uv1s.append(uv1)
            self.colors.append(-1)
            var indices = -1
            if geometry.is_indexed():
                indices = self.index_accessor(geometry.index, count)
            self.indices.append(indices)
            slot = len(self.geometry_keys) - 1
        if colored and self.colors[slot] < 0:
            ref color = geometry.attribute_view(COLOR)
            self.colors[slot] = self.float_accessor(
                color.packed(),
                color.item_size,
                "VEC3" if color.item_size == 3 else "VEC4",
                False,
            )
        return slot

    def sampler(mut self, texture: Texture) raises -> Int:
        """Write the sampler for a texture's wrap and filter, once."""
        var mipmapped = texture.levels > 1
        var key = (
            texture.wrap.value * 4
            + texture.filter.value * 2
            + (1 if mipmapped else 0)
        )
        for at in range(len(self.sampler_keys)):
            if self.sampler_keys[at] == key:
                return at
        var nearest = texture.filter == NEAREST
        var magnify = FILTER_NEAREST if nearest else FILTER_LINEAR
        var minify = magnify
        if mipmapped:
            minify = (
                FILTER_NEAREST_MIPMAP_NEAREST if nearest else FILTER_LINEAR_MIPMAP_LINEAR
            )
        var wrap = _wrap_code(texture)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("magFilter")
        writer.integer(magnify)
        writer.key("minFilter")
        writer.integer(minify)
        writer.key("wrapS")
        writer.integer(wrap)
        writer.key("wrapT")
        writer.integer(wrap)
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
        var image = self.image(pixels^, leader.width, leader.height)
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
        writer.key("roughnessFactor")
        writer.number(material.roughness if physical else 1)
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
        var extensions = self.extensions(material, assets)
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
        mut self, scene: Scene, drawn: List[Int], assets: Assets
    ) raises -> Int:
        """Write the meshes on one node as one glTF mesh, a primitive
        each, and return its index."""
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("primitives")
        writer.begin_array()
        # `export_gltf` asks only for a node that carries a mesh.
        for which in drawn:  # pragma: no branch
            ref mesh = scene.meshes[which]
            var material = assets.materials.get(mesh.material)
            var colored = material.vertex_colors and assets.geometries.get(
                mesh.geometry
            ).has_attribute(COLOR)
            var slot = self.geometry(mesh.geometry, colored, assets)
            var index = self.material(mesh.material, assets)
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
            writer.end_object()
            if self.indices[slot] >= 0:
                writer.key("indices")
                writer.integer(self.indices[slot])
            writer.key("material")
            writer.integer(index)
            writer.key("mode")
            writer.integer(MODE_TRIANGLES)
            writer.end_object()
        writer.end_array()
        writer.end_object()
        self.meshes.append(writer.finish())
        return len(self.meshes) - 1

    def document(
        self, roots: List[Int], nodes: List[String], uri: String
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
        writer.key("scene")
        writer.integer(0)
        writer.key("scenes")
        writer.begin_array()
        writer.begin_object()
        if len(roots) > 0:
            writer.key("nodes")
            _write_integers(writer, roots)
        writer.end_object()
        writer.end_array()
        _write_array(writer, "nodes", nodes)
        _write_array(writer, "meshes", self.meshes)
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


def _node_json(node: Object3D, mesh: Int, children: List[Int]) raises -> String:
    """Return one node as glTF writes it."""
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
    if node.user_data.count() > 0:
        writer.key("extras")
        writer.raw(node.user_data.to_json())
    if mesh >= 0:
        writer.key("mesh")
        writer.integer(mesh)
    if len(children) > 0:
        writer.key("children")
        _write_integers(writer, children)
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

    Returns:
        The file, and the `.bin` for `GLTF_SEPARATE`.

    Raises:
        Error: If the container is none of the three, the `.bin` name is
            empty or has a scheme, a mesh names a node, geometry,
            material or texture that is not there, a geometry is refused
            by `exporters.common.check_geometry` or has no vertices, a
            texture is refused by `gltf_pixels`, a combined roughness and
            metalness map are not one size or do not share one transform
            and one channel, or a number is not finite.
    """
    if not container.is_valid():
        raise Error("glTF: a container that is none of the three")
    if container == GLTF_SEPARATE and not _is_relative_name(binary_name):
        raise Error("glTF: the .bin needs a relative name: " + binary_name)
    var count = scene.count()
    # Each scene node's index in the file, or -1 when it is left out.
    var written = List[Int](length=count, fill=-1)
    var kept = List[Int]()
    var roots = List[Int]()
    var children = List[List[Int]]()
    var drawn = List[List[Int]]()
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
        drawn.append(List[Int]())
        if parent == NO_PARENT:
            roots.append(written[index])
        else:
            children[written[parent.value]].append(written[index])
    for which in range(len(scene.meshes)):
        var node = scene.meshes[which].node
        if node.value < 0 or node.value >= count:
            raise Error("glTF: a mesh names a node that is not in the scene")
        if written[node.value] >= 0:
            drawn[written[node.value]].append(which)
    var exporter = _Exporter(container != GLB)
    var nodes = List[String]()
    for at in range(len(kept)):
        var mesh = -1
        if len(drawn[at]) > 0:
            mesh = exporter.mesh(scene, drawn[at], assets)
        nodes.append(
            _node_json(scene.get(NodeId(kept[at])), mesh, children[at])
        )
    exporter.pad()
    var files = GltfFiles()
    if container == GLB:
        files.document = _glb(exporter.document(roots, nodes, ""), exporter.bin)
        return files^
    var uri = binary_name
    if container == GLTF_SEPARATE:
        files.binary = exporter.bin.copy()
    else:
        uri = "data:application/octet-stream;base64," + encode_base64(
            exporter.bin
        )
    files.document.extend(exporter.document(roots, nodes, uri).as_bytes())
    return files^


def write_gltf(
    path: String,
    scene: Scene,
    assets: Assets,
    container: GltfContainer = GLTF_EMBEDDED,
    only_visible: Bool = True,
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

    Raises:
        Error: If a file cannot be written, or anything `export_gltf`
            raises.
    """
    var name = binary_name_for(path)
    var files = export_gltf(scene, assets, container, name, only_visible)
    Path(path).write_bytes(files.document)
    if len(files.binary) > 0:
        var directory = String(path[byte = 0 : path.rfind("/") + 1])
        Path(directory + name).write_bytes(files.binary)
