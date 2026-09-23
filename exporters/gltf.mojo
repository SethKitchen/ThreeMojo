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

**What maps to what.** Each node becomes a glTF node with its name, its
translation, rotation and scale, and its children. A node whose
`matrix_auto_update` is off is written with its `matrix` instead, since
the matrix is what it draws with. The meshes on one node become one glTF
mesh with a primitive each, which `read_gltf` reads back as one `Mesh`
each on that node. A primitive carries `POSITION`, with the `min` and
`max` the specification asks for, and `NORMAL`, `TEXCOORD_0`, `COLOR_0`
and `indices` when the geometry has them. `COLOR_0` is written only when
the material turns `vertex_colors` on, since `read_gltf` turns it on for
a primitive that has one. A geometry or a material used twice is written
once.

**Materials are metallic-roughness.** A `STANDARD` or `PHYSICAL` material
is written with its color, opacity, metalness, roughness, emissive color,
alpha mode, side and maps. Every other kind is written as the nearest
metallic-roughness material, as three.js writes it: its color and opacity
with a metalness of zero and a roughness of one, and a `BASIC` material
also says `KHR_materials_unlit`. The emissive intensity is multiplied
into the emissive color, since `KHR_materials_emissive_strength` is not
written; a product brighter than one is refused. A transparent material
is `BLEND`, an alpha-tested one is `MASK` at its `alpha_test`, and a
`DOUBLE_SIDE` material is double-sided.

**Textures are PNG images.** Each texture is written once, as a PNG from
`render.png`, with a sampler for its wrap and filter. glTF's `v` runs down
from the image's top, where a texture here runs up from its bottom, so an
image is written upside down, as three.js writes a `flipY` texture. A
texture that `read_gltf` made already carries the flip in its `repeat`
and `offset`, so its image is written as it is. A texture moved, tiled or
turned any other way is refused, since `KHR_texture_transform` is not
written. glTF keeps roughness and metalness in one image, green and blue:
when a material's two maps are one texture it is written once, and when
they differ they are combined into one image of the same size, as
three.js's `buildMetalRoughTexture` combines them.

**Not written.** Lights, cameras, animations, skins, morph targets,
instanced, batched and skinned meshes, lines, points and sprites, and
every map glTF has no place for: bump, alpha, environment, matcap and
gradient maps. A `BACK_SIDE` material is written single-sided, as three.js
writes it, since glTF has no back side. A geometry's groups are not split
into primitives: a mesh here has one material.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.common import check_geometry, push_f32, push_word
from exporters.json_writer import JsonWriter
from loaders.gltf import (
    COMPONENT_FLOAT,
    COMPONENT_UNSIGNED_INT,
    COMPONENT_UNSIGNED_SHORT,
    FILTER_LINEAR,
    FILTER_LINEAR_MIPMAP_LINEAR,
    FILTER_NEAREST,
    FILTER_NEAREST_MIPMAP_NEAREST,
    GLB_BIN_CHUNK,
    GLB_JSON_CHUNK,
    GLB_MAGIC,
    GLB_VERSION,
    MODE_TRIANGLES,
    WRAP_CLAMP,
    WRAP_MIRROR,
    WRAP_REPEAT,
)
from materials.material import BASIC, NO_TEXTURE, DOUBLE_SIDE, MaterialId
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import FloatColor, Framebuffer
from render.png import encode as encode_png
from render.texture import CLAMP, FLOAT_TYPE, MIRROR, NEAREST, Texture
from render.texture_store import TextureId
from std.pathlib import Path

# The two buffer view targets: vertex attributes, and indices.
comptime ARRAY_BUFFER = 34962
comptime ELEMENT_ARRAY_BUFFER = 34963
# The largest vertex count whose indices fit an unsigned short. glTF
# keeps 65535 itself back, as a strip's restart.
comptime MAX_SHORT_VERTICES = 65535
# What a material says it needs to be drawn unlit.
comptime UNLIT = "KHR_materials_unlit"
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


def _is_upright(matrix: Matrix3) -> Bool:
    """Return True if a texture transform moves nothing."""
    return (
        _is_at(matrix.transform_point(Vector2(0, 0)), 0, 0)
        and _is_at(matrix.transform_point(Vector2(1, 0)), 1, 0)
        and _is_at(matrix.transform_point(Vector2(0, 1)), 0, 1)
    )


def _is_flipped(matrix: Matrix3) -> Bool:
    """Return True if a texture transform turns `v` upside down and
    nothing else, as `read_gltf` sets it."""
    return (
        _is_at(matrix.transform_point(Vector2(0, 0)), 0, 1)
        and _is_at(matrix.transform_point(Vector2(1, 0)), 1, 1)
        and _is_at(matrix.transform_point(Vector2(0, 1)), 0, 0)
    )


def gltf_pixels(texture: Texture) raises -> List[UInt8]:
    """Return a texture's full-size image as glTF lays it out: the row
    that `v = 0` reads first.

    Args:
        texture: The texture.

    Returns:
        RGBA bytes, row by row, `width * height * 4` of them.

    Raises:
        Error: If the texture is blank, holds floats, holds a mode that is
            none of its named values, or is moved, tiled or turned by
            anything but the flip `read_gltf` sets.
    """
    if texture.width == 0:
        raise Error("glTF: a blank texture has no image to write")
    # A glTF image is a PNG or a JPEG, eight bits a channel: light above
    # one has no byte to go in, and clipping it silently is not writing it.
    if texture.texel_type == FLOAT_TYPE:
        raise Error("glTF: a float texture has no eight-bit image to write")
    texture.validate()
    var transform = texture.uv_transform()
    var flip: Bool
    if _is_upright(transform):
        flip = True
    elif _is_flipped(transform):
        flip = False
    else:
        raise Error(
            "glTF: a texture's offset, repeat, rotation and center are not"
            " written; KHR_texture_transform is not ported"
        )
    var row = texture.width * Texture.CHANNELS
    var out = List[UInt8](capacity=row * texture.height)
    var pixels = Span(texture.pixels)
    # A texture that is not blank has at least one row.
    for y in range(texture.height):  # pragma: no branch
        var source = texture.height - 1 - y if flip else y
        out.extend(pixels[source * row : source * row + row])
    return out^


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
    var colors: List[Int]
    var indices: List[Int]
    # Whether a material asked for `KHR_materials_unlit`.
    var unlit: Bool

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
        self.colors = List[Int]()
        self.indices = List[Int]()
        self.unlit = False

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
                    geometry.attribute_view(POSITION).data, 3, "VEC3", True
                )
            )
            var normal = -1
            if geometry.has_attribute(NORMAL):
                normal = self.float_accessor(
                    geometry.attribute_view(NORMAL).data, 3, "VEC3", False
                )
            self.normals.append(normal)
            var uv = -1
            if geometry.has_attribute(UV):
                uv = self.float_accessor(
                    geometry.attribute_view(UV).data, 2, "VEC2", False
                )
            self.uvs.append(uv)
            self.colors.append(-1)
            var indices = -1
            if geometry.is_indexed():
                indices = self.index_accessor(geometry.index, count)
            self.indices.append(indices)
            slot = len(self.geometry_keys) - 1
        if colored and self.colors[slot] < 0:
            ref color = geometry.attribute_view(COLOR)
            self.colors[slot] = self.float_accessor(
                color.data,
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
        """Write an image as a PNG and return its index."""
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
    ) raises:
        """Write `key` and a texture reference to it."""
        var index = self.texture(first, second, assets)
        writer.key(key)
        writer.begin_object()
        writer.key("index")
        writer.integer(index)
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
            var normal = self.texture(
                material.normal_map, material.normal_map, assets
            )
            writer.key("normalTexture")
            writer.begin_object()
            writer.key("index")
            writer.integer(normal)
            if material.normal_scale.x != 1:
                writer.key("scale")
                writer.number(material.normal_scale.x)
            writer.end_object()
        var glow = material.emissive_light()
        var brightest = max(glow.r, max(glow.g, glow.b))
        if brightest > 1:
            raise Error(
                "glTF: an emissive color times its intensity must not pass"
                " one; KHR_materials_emissive_strength is not written"
            )
        if brightest > 0:
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
        if material.kind == BASIC:
            writer.key("extensions")
            writer.begin_object()
            writer.key(UNLIT)
            writer.begin_object()
            writer.end_object()
            writer.end_object()
            self.unlit = True
        writer.end_object()
        self.material_keys.append(id.value)
        self.materials.append(writer.finish())
        return len(self.materials) - 1

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
        if self.unlit:
            writer.key("extensionsUsed")
            writer.begin_array()
            writer.string(UNLIT)
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

    Nodes are written in the scene's order, a parent before its children,
    so node `k` of the file is the `k`th node written.

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
            metalness map are not one size, an emissive term passes one,
            or a number is not finite.
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
    for index in range(count):
        var node = scene.get(NodeId(index))
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
