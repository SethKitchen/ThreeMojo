# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene and its assets written in three.js's JSON Object format,
version 4.6: what `scene.toJSON()` writes, and the other half of
`loaders.object_loader`.

**The document.** A `metadata` object, the `geometries`, `materials`,
`textures` and `images` the scene draws with, each written once and named
by a uuid, and an `object` of type `Scene` whose children are the scene's
root nodes. three.js makes a random uuid for each thing; this writes one
from the thing's kind and its position, so the same scene gives the same
text every time.

**Nodes.** Every node in the scene becomes an object with its name, its
`visible`, its `layers`, its `renderOrder`, its `userData` and its local
`matrix`, as three.js writes an `Object3D`, or a `Group` for a node of
`GROUP_TYPE`. A removed node is not written, nor is anything under it or
on it. A node that carries one thing becomes that thing: a `Mesh`,
an `InstancedMesh`, a `BatchedMesh`, a `SkinnedMesh`, a `Line`, a
`LineLoop` or a `LineSegments`, a `Points`, a `Sprite`, an `LOD`, a light
of its kind or a camera. A node that carries more than one, or a light or
camera on other layers than its node, is an `Object3D` with one child
object per thing, each at the identity. A light with no node, as an
ambient light usually is, is a child of the scene. A node that carries
nothing and is a bone of a skeleton is a `Bone`.

**The other objects.** An `LOD` writes each level as a child `Mesh` at the
identity, and names it in `levels` with its `distance` and `hysteresis`,
as `LOD.toJSON` does. A `SkinnedMesh` writes its `bindMode`, its
`bindMatrix` and the uuid of its skeleton; the skeleton is an entry of a
`skeletons` library with the uuids of its bones and their `boneInverses`.
A `BatchedMesh` is written as three.js writes one: its geometries joined
into one `BufferGeometry`, a `geometryInfo` and an `instanceInfo` entry
for each, and the instance matrices and colors in the `Float32Array` data
textures `matricesTexture` and `colorsTexture`, with the
`indirectTexture` three.js also reads. A sprite's `center` is written
when it is not the middle; three.js writes none and reads none.

**Geometry** is a `BufferGeometry` with every attribute as a
`Float32Array`, the index as a `Uint16Array` or a `Uint32Array` as three.js
chooses, the groups, and the morph targets. An instanced geometry is an
`InstancedBufferGeometry` with its `instanceCount`, and a per-instance
attribute carries its `meshPerAttribute`. An interleaved attribute is
written with its own numbers, not as a view of a shared buffer: three.js
does the same when an attribute is written on its own. **A material** has the type
of its kind -- `MeshStandardMaterial` for `STANDARD` -- and the fields that
type has in three.js: the maps, the baked light, the displacement, the
flat shading, the depth packing, the volume, the specular and clearcoat
maps, the sheen, the film and the stretch of a physical surface, and the
depth, stencil and polygon offset
state of every class, each under three.js's key and left out where
`Material.toJSON` leaves it out. A line, points or a sprite writes its
`BASIC` material as three.js's class for it: `LineBasicMaterial`,
`LineDashedMaterial` for a dashed material, `PointsMaterial` and
`SpriteMaterial`, with their width, dashes, size, attenuation and turn.
One material that a mesh and a line share is written once for each. A
mesh that wears a material list writes `material` as a list of uuids,
as three.js's `Object3D.toJSON` does.
**A texture** is its sampler's settings -- both wraps, both filters --
its `flipY`, its `mapping`, its `channel` and an image, written as a PNG
`data:` URL of its full-size level. The image is written as its rows are
stored, and `flipY` says which way `v` reads them. A cube made from a
panorama is written as the panorama, a flat texture with its
equirectangular mapping, as three.js holds one.

**A cube texture** is a `CubeTexture` entry whose image's `url` is an
array of six PNG `data:` URLs, as `Source.toJSON` writes six images, with
`CubeReflectionMapping` and a `flipY` of false. Each face is mirrored on
the way out, into the OpenGL layout three.js keeps a cube's images in. It
is the scene's `background` or `environment`, or a material's `envMap`.
A basic, lambert or phong material that reflects the scene's environment
names that cube, since three.js reads the environment only where a
standard or physical material has no `envMap`. A mesh writes its
`morphTargetInfluences`. A material writes its own `clippingPlanes`,
`clipIntersection` and `clipShadows`, a reflecting material its
`envMapRotation` and a basic, lambert or phong one its `refractionRatio`,
a material with a normal map its `normalMapType`, and the scene its
background and environment settings, as `Scene.toJSON` writes them; a
distance material its
`referencePosition`, `nearDistance` and `farDistance`, and a material its
`dashOffset`: three.js's `Material.toJSON` writes none of these, and its
loader ignores them.

**Animations.** The clips handed to `object_to_json` are the scene's
`animations`, written with `animation.animation_json.write_clip` into an
`animations` library as `Object3D.toJSON` writes a scene's. Each track is
named by the uuid of the object its target is written as, and the path of
the property: a material's on the first mesh that draws with it.

**Not written.** Wide lines, which are an addon of three.js with no class
`ObjectLoader` reads; a cube's PMREM, which the reader builds again where
three.js's renderer would; and a texture's alpha mode, which three.js has
no field for: `loaders.object_loader` gives it back from the texture's
use. A cube of float faces, or of faces that differ in their sampling, is
refused. So is a cube that a standard or physical material or the
environment reflects without its PMREM, and a standard or physical
material that reflects nothing in a scene with an environment: three.js
would draw either another way. A material with custom blending, a material that blends
but is not transparent, a line width in world units, a perspective camera
with a view shift and a camera that rides no node are refused, since the
format has no place for them. So is a batch whose geometries do not share
their attributes and index, or carry morph targets, which three.js's
`BatchedMesh` cannot join.
"""

from animation.animation_clip import AnimationClip
from animation.animation_json import property_path, write_clip
from animation.keyframe_track import ORTHOGRAPHIC_SLOT, TrackTarget
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import (
    COLOR_BACKGROUND,
    CUBE_BACKGROUND,
    TEXTURE_BACKGROUND,
)
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import MAX_MORPH_TARGETS, BufferGeometry
from core.fog import EXP2_FOG, LINEAR_FOG
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import GROUP_TYPE, NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.gltf import encode_base64
from exporters.json_writer import JsonWriter
from lights.light import (
    DIRECTIONAL,
    HEMISPHERE,
    POINT,
    RECT_AREA,
    LIGHT_PROBE,
    SPOT,
    Light,
)
from loaders.object_loader import (
    CLAMP_TO_EDGE_WRAPPING,
    CUBE_REFLECTION_MAPPING,
    CUSTOM_BLENDING,
    FLOAT_TYPE,
    FORMAT_VERSION,
    LINEAR_SRGB_COLOR_SPACE,
    NEAREST_FILTER,
    NO_BLENDING,
    RED_INTEGER_FORMAT,
    RGBA_FORMAT,
    SRGB_COLOR_SPACE,
    STENCIL_FUNC_BASE,
    UNSIGNED_BYTE_TYPE,
    UNSIGNED_INT_TYPE,
    UV_MAPPING,
    ObjectCameras,
    filter_code,
    bind_mode_name,
    light_type_names,
    line_type_names,
    material_type_names,
    stencil_op_code,
    wrap_code,
)
from materials.material import (
    BASIC,
    BLEND,
    DEFAULT_LINE_WIDTH,
    DEPTH,
    DISTANCE,
    LAMBERT,
    NO_DASH,
    NO_TEXTURE,
    OPAQUE,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    TOON,
    Material,
    MaterialId,
    MaterialKind,
)
from math.euler import Euler, EulerOrder
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from objects.skeleton import Skeleton
from render.cube_texture import NEGATIVE_X
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.framebuffer import Color, FloatColor, Framebuffer
from render.png import encode as encode_png
from render.raster_state import (
    ALWAYS_STENCIL_FUNC,
    KEEP_STENCIL_OP,
    LESS_EQUAL_DEPTH,
    STENCIL_MAX,
)
from render.srgb import SRGB
from render.texture import FLOAT_TYPE as FLOAT_TEXELS
from render.texture import Mapping
from render.texture import Texture
from render.texture_store import TextureId
from std.math import ceil, isfinite, sqrt
from std.pathlib import Path
from cameras.camera import ViewOffset
from units.si import DEGREE, METER, MILLIMETER, NANOMETER, PER_METER, RADIAN

# What the leading hex digit of a uuid says it names.
comptime _SCENE_UUID = 1
comptime _NODE_UUID = 2
comptime _PART_UUID = 3
comptime _GEOMETRY_UUID = 4
comptime _MATERIAL_UUID = 5
comptime _TEXTURE_UUID = 6
comptime _IMAGE_UUID = 7
comptime _SKELETON_UUID = 8
comptime _CLIP_UUID = 9
# The largest vertex count whose index three.js writes as a `Uint16Array`.
comptime _MAX_SHORT_INDEX = 65535
comptime _HEX = "0123456789abcdef"
# An instance color that tints nothing, and the smallest side of a batch's
# matrix texture, as three.js's `_initMatricesTexture` has it.
comptime _WHITE_HEX = 0xFFFFFF
comptime _MATRICES_SIDE = 4
# What a texture key is for a cube texture: this, less its store id, so
# that it never meets a texture's id or a data texture's -1.
comptime _CUBE_KEY = -2


def object_uuid(kind: Int, index: Int) -> String:
    """Return the uuid this writer gives a thing.

    Args:
        kind: A digit that says what the thing is, one to fifteen.
        index: Its position among the things of that kind.

    Returns:
        A version 4 uuid in three.js's form: the kind in the first digit
        of the last group and the index in the other eleven.
    """
    var out = String("00000000-0000-4000-8000-")
    var value = (kind << 44) | index
    var digits = List[UInt8]()
    for shift in range(11, -1, -1):  # pragma: no branch
        digits.append(_HEX.as_bytes()[(value >> (shift * 4)) & 15])
    return out + String(unsafe_from_utf8=digits)


def _numbers(mut writer: JsonWriter, values: List[Float32]) raises:
    """Write an array of numbers."""
    writer.begin_array()
    for value in values:
        writer.number(value)
    writer.end_array()


def _matrix(mut writer: JsonWriter, matrix: Matrix4) raises:
    """Write a matrix's sixteen numbers, column by column."""
    var values = List[Float32]()
    for index in range(16):  # pragma: no branch
        values.append(matrix.elements[index])
    _numbers(writer, values)


def _attribute(mut writer: JsonWriter, attribute: BufferAttribute) raises:
    """Write an attribute as three.js's `BufferAttribute.toJSON` does.

    An interleaved attribute is written with its own numbers, as three.js's
    `InterleavedBufferAttribute.toJSON` writes one when it is given no
    buffers to share. A per-instance attribute is marked as three.js's
    `InstancedBufferAttribute.toJSON` marks it.
    """
    writer.begin_object()
    writer.key("itemSize")
    writer.integer(attribute.item_size)
    writer.key("type")
    writer.string("Float32Array")
    writer.key("array")
    _numbers(writer, attribute.packed())
    writer.key("normalized")
    writer.boolean(False)
    if attribute.is_instanced():
        writer.key("meshPerAttribute")
        writer.integer(attribute.mesh_per_attribute())
        writer.key("isInstancedBufferAttribute")
        writer.boolean(True)
    writer.end_object()


def index_type(vertices: Int) -> String:
    """Return the typed array three.js writes an index as.

    Args:
        vertices: How many vertices the geometry has.

    Returns:
        `Uint16Array` when every index fits below 65535, and `Uint32Array`
        otherwise, as `BufferGeometry.setIndex` chooses.
    """
    return "Uint32Array" if vertices > _MAX_SHORT_INDEX else "Uint16Array"


def _order_name(order: EulerOrder) -> String:
    """Return an Euler order's name, as three.js's `Euler.toArray` writes
    it: `XYZ` and so on."""
    comptime axes = "XYZ"
    var name = String()
    name += axes[byte=order.first]
    name += axes[byte=order.second]
    name += axes[byte=order.third]
    return name^


def _euler(mut writer: JsonWriter, euler: Euler) raises:
    """Write a rotation as `Euler.toArray` does: three angles in radians
    and the order's name.

    Raises:
        Error: If an angle is not finite.
    """
    writer.begin_array()
    writer.number(euler.x.to(RADIAN))
    writer.number(euler.y.to(RADIAN))
    writer.number(euler.z.to(RADIAN))
    writer.string(_order_name(euler.order))
    writer.end_array()


def _has_emissive(kind: MaterialKind) -> Bool:
    """Return True for a kind whose three.js class has an emissive color."""
    return (
        kind == LAMBERT
        or kind == PHONG
        or kind == TOON
        or kind == STANDARD
        or kind == PHYSICAL
    )


def _has_color(kind: MaterialKind) -> Bool:
    """Return True for a kind whose three.js class has a color."""
    return not kind.is_data()


def _reflects(kind: MaterialKind) -> Bool:
    """Return True for a kind whose three.js class has `reflectivity` and
    `combine`."""
    return kind == BASIC or kind == LAMBERT or kind == PHONG


struct _Header(Copyable, Movable):
    """What every object says before what its type adds."""

    var uuid: String
    var type: String
    var name: String
    var cast_shadow: Bool
    var receive_shadow: Bool
    var visible: Bool
    var frustum_culled: Bool
    var render_order: Int
    # The node's `userData` as JSON text, or empty for none.
    var user_data: String
    var layers: Layers
    var matrix: Matrix4
    var auto: Bool

    def __init__(out self, uuid: String, node: Object3D) raises:
        """Start from a node: its type, name, visibility, user data,
        layers and matrix. Refuse a node of neither type."""
        if not node.object_type.is_valid():
            raise Error("Object JSON: a node must be an Object3D or a Group")
        self.uuid = uuid
        self.type = "Group" if node.object_type == GROUP_TYPE else "Object3D"
        self.name = node.name
        self.cast_shadow = False
        self.receive_shadow = False
        self.visible = node.visible
        self.frustum_culled = True
        self.render_order = node.render_order
        self.user_data = String()
        if node.user_data.count() > 0:
            self.user_data = node.user_data.to_json()
        self.layers = node.layers
        self.auto = node.matrix_auto_update
        self.matrix = node.local_matrix() if self.auto else node.matrix

    def __init__(out self, uuid: String, layers: Layers):
        """Start a part: unnamed, visible, at the identity."""
        self.uuid = uuid
        self.type = "Object3D"
        self.name = String()
        self.cast_shadow = False
        self.receive_shadow = False
        self.visible = True
        self.frustum_culled = True
        self.render_order = 0
        self.user_data = String()
        self.layers = layers
        self.matrix = Matrix4()
        self.auto = True

    def write(self, mut writer: JsonWriter) raises:
        """Write the fields, as `Object3D.toJSON` writes them."""
        writer.key("uuid")
        writer.string(self.uuid)
        writer.key("type")
        writer.string(self.type)
        if self.name != "":
            writer.key("name")
            writer.string(self.name)
        if self.cast_shadow:
            writer.key("castShadow")
            writer.boolean(True)
        if self.receive_shadow:
            writer.key("receiveShadow")
            writer.boolean(True)
        if not self.visible:
            writer.key("visible")
            writer.boolean(False)
        if not self.frustum_culled:
            writer.key("frustumCulled")
            writer.boolean(False)
        if self.render_order != 0:
            writer.key("renderOrder")
            writer.integer(self.render_order)
        if self.user_data != "":
            writer.key("userData")
            writer.raw(self.user_data)
        writer.key("layers")
        writer.integer(Int(self.layers.mask))
        writer.key("matrix")
        _matrix(writer, self.matrix)
        writer.key("up")
        _numbers(writer, [0, 1, 0])
        if not self.auto:
            writer.key("matrixAutoUpdate")
            writer.boolean(False)


struct _Library(Movable):
    """The libraries as JSON texts, and which store id each entry is."""

    var geometries: List[String]
    # The store id of each geometry entry, or -1 for a batch's joined one.
    var geometry_keys: List[Int]
    var materials: List[String]
    # Each material entry's store id and three.js class, as one text.
    var material_keys: List[String]
    var textures: List[String]
    var images: List[String]
    # The store id of each texture entry, or -1 for a batch's data texture.
    var texture_keys: List[Int]
    var skeletons: List[String]
    var parts: Int
    # The scene's environment, which a material without an `envMap` can
    # reflect.
    var environment: CubeTextureId

    def __init__(out self):
        """Start with empty libraries."""
        self.environment = NO_CUBE_TEXTURE
        self.geometries = List[String]()
        self.geometry_keys = List[Int]()
        self.materials = List[String]()
        self.material_keys = List[String]()
        self.textures = List[String]()
        self.images = List[String]()
        self.texture_keys = List[Int]()
        self.skeletons = List[String]()
        self.parts = 0

    def part_uuid(mut self) -> String:
        """Return a uuid for the next part object."""
        self.parts += 1
        return object_uuid(_PART_UUID, self.parts - 1)

    def geometry(mut self, id: GeometryId, assets: Assets) raises -> String:
        """Write a geometry once, and return its uuid."""
        var at = _find(self.geometry_keys, id.value)
        if at < 0:
            at = self.add_geometry(assets.geometries.get(id), id.value)
        return object_uuid(_GEOMETRY_UUID, at)

    def add_geometry(
        mut self, geometry: BufferGeometry, key: Int
    ) raises -> Int:
        """Write a geometry as a new entry, and return its position."""
        var at = len(self.geometry_keys)
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("uuid")
        writer.string(object_uuid(_GEOMETRY_UUID, at))
        writer.key("type")
        if geometry.instanced:
            # three.js's `InstancedBufferGeometry.toJSON`: `null` is
            # what `JSON.stringify` makes of its default `Infinity`.
            writer.string("InstancedBufferGeometry")
            writer.key("instanceCount")
            if Bool(geometry.instance_count):
                writer.integer(geometry.instance_count.value())
            else:
                writer.null()
            writer.key("isInstancedBufferGeometry")
            writer.boolean(True)
        else:
            writer.string("BufferGeometry")
        writer.key("data")
        writer.begin_object()
        writer.key("attributes")
        writer.begin_object()
        for slot in range(len(geometry.names)):
            writer.key(geometry.names[slot])
            _attribute(writer, geometry.values[slot])
        writer.end_object()
        if geometry.is_indexed():
            writer.key("index")
            writer.begin_object()
            writer.key("type")
            writer.string(index_type(geometry.vertex_count()))
            writer.key("array")
            writer.begin_array()
            for entry in geometry.index:  # pragma: no branch
                writer.integer(entry)
            writer.end_array()
            writer.end_object()
        if geometry.morph_count() > 0:
            writer.key("morphAttributes")
            writer.begin_object()
            writer.key("position")
            writer.begin_array()
            for target in geometry.morph_positions:  # pragma: no branch
                _attribute(writer, target)
            writer.end_array()
            if geometry.has_morph_normals():
                writer.key("normal")
                writer.begin_array()
                for target in geometry.morph_normals:  # pragma: no branch
                    _attribute(writer, target)
                writer.end_array()
            writer.end_object()
            writer.key("morphTargetsRelative")
            writer.boolean(geometry.morph_relative)
        if len(geometry.groups) > 0:
            writer.key("groups")
            writer.begin_array()
            for group in geometry.groups:  # pragma: no branch
                writer.begin_object()
                writer.key("start")
                writer.integer(group.start)
                writer.key("count")
                writer.integer(group.count)
                writer.key("materialIndex")
                writer.integer(group.material_index.value)
                writer.end_object()
            writer.end_array()
        writer.end_object()
        writer.end_object()
        self.geometries.append(writer.finish())
        self.geometry_keys.append(key)
        return at

    def texture(mut self, id: TextureId, assets: Assets) raises -> String:
        """Write a texture and its image once, and return its uuid."""
        var at = _find(self.texture_keys, id.value)
        if at < 0:
            at = len(self.texture_keys)
            ref texture = assets.textures.get(id)
            self.flat(texture, at, texture.mapping)
            self.texture_keys.append(id.value)
        return object_uuid(_TEXTURE_UUID, at)

    def flat(mut self, texture: Texture, at: Int, mapping: Mapping) raises:
        """Write one flat texture and its image as entry `at`, with a
        mapping: its own, or its cube's for a panorama. The caller records
        the key.

        The image is written as its rows are stored, and `flipY` says
        which way `v` reads them, as three.js's does.
        """
        if texture.width == 0:
            raise Error("Object JSON: a blank texture has no image")
        if texture.texel_type == FLOAT_TEXELS:
            raise Error(
                "Object JSON: a float texture is not written, as a PNG"
                " holds bytes"
            )
        texture.validate()
        var size = texture.width * texture.height * Texture.CHANNELS
        var pixels = List[UInt8](capacity=size)
        pixels.extend(Span(texture.pixels)[0:size])
        var png = encode_png(
            Framebuffer(texture.width, texture.height, pixels^)
        )
        var image = JsonWriter()
        image.begin_object()
        image.key("uuid")
        image.string(object_uuid(_IMAGE_UUID, at))
        image.key("url")
        image.string("data:image/png;base64," + encode_base64(png))
        image.end_object()
        self.images.append(image.finish())
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("uuid")
        writer.string(object_uuid(_TEXTURE_UUID, at))
        writer.key("name")
        writer.string("")
        writer.key("image")
        writer.string(object_uuid(_IMAGE_UUID, at))
        writer.key("mapping")
        writer.integer(mapping.value)
        writer.key("channel")
        writer.integer(texture.channel.value)
        writer.key("repeat")
        _numbers(writer, [texture.repeat.x, texture.repeat.y])
        writer.key("offset")
        _numbers(writer, [texture.offset.x, texture.offset.y])
        writer.key("center")
        _numbers(writer, [texture.center.x, texture.center.y])
        writer.key("rotation")
        writer.number(texture.rotation.to(RADIAN))
        writer.key("wrap")
        writer.begin_array()
        writer.integer(wrap_code(texture.wrap_s))
        writer.integer(wrap_code(texture.wrap_t))
        writer.end_array()
        writer.key("format")
        writer.integer(RGBA_FORMAT)
        writer.key("type")
        writer.integer(UNSIGNED_BYTE_TYPE)
        writer.key("colorSpace")
        writer.string(SRGB_COLOR_SPACE if texture.color_space == SRGB else "")
        writer.key("minFilter")
        writer.integer(filter_code(texture.min_filter))
        writer.key("magFilter")
        writer.integer(filter_code(texture.mag_filter))
        writer.key("anisotropy")
        writer.integer(texture.anisotropy)
        writer.key("flipY")
        writer.boolean(texture.flip_y)
        writer.key("generateMipmaps")
        writer.boolean(texture.levels > 1)
        writer.end_object()
        self.textures.append(writer.finish())

    def cube(mut self, id: CubeTextureId, assets: Assets) raises -> String:
        """Write a cube texture and its six images once, as three.js
        writes a `CubeTexture`, and return its uuid.

        The image entry's `url` is an array of six PNG `data:` URLs, as
        `Source.toJSON` writes the six images of a cube. The first two faces
        trade places on the way out and nothing is mirrored: three.js
        keeps a cube's images in the layout that `SEEN_FROM_OUTSIDE`
        reads, the px image along -x, and its `flipY` is false.
        """
        # Refuses an id that names no cube before it becomes a key.
        ref cube = assets.cube_textures.get(id)
        var key = _CUBE_KEY - id.value
        var at = _find(self.texture_keys, key)
        if at >= 0:
            return object_uuid(_TEXTURE_UUID, at)
        at = len(self.texture_keys)
        cube.validate()
        if cube.has_panorama():
            # three.js holds a panorama as the flat texture it is, with an
            # equirectangular mapping; the six faces are this port's.
            self.flat(cube.panorama, at, cube.mapping)
            self.texture_keys.append(key)
            return object_uuid(_TEXTURE_UUID, at)
        ref first = cube.faces[0]
        var image = JsonWriter()
        image.begin_object()
        image.key("uuid")
        image.string(object_uuid(_IMAGE_UUID, at))
        image.key("url")
        image.begin_array()
        # A valid cube holds six faces, so this never runs zero times.
        for index in range(len(cube.faces)):  # pragma: no branch
            var source = index
            if index < NEGATIVE_X + 1:
                # The px image is the face along -x, and the nx image the
                # face along +x.
                source = NEGATIVE_X - index
            ref face = cube.faces[source]
            if face.texel_type == FLOAT_TEXELS:
                raise Error(
                    "Object JSON: a cube of float faces is not written, as a"
                    " PNG holds bytes"
                )
            var same = (
                face.mag_filter == first.mag_filter
                and face.min_filter == first.min_filter
                and face.color_space == first.color_space
                and face.levels == first.levels
            )
            if not same:
                raise Error(
                    "Object JSON: a cube's faces must share their filters,"
                    " color space and mip chain, as three.js's CubeTexture"
                    " has one of each"
                )
            # The full-size image, without the chain that follows it.
            var size = face.width * face.height * Texture.CHANNELS
            var pixels = List[UInt8](capacity=size)
            pixels.extend(Span(face.pixels)[0:size])
            var png = encode_png(Framebuffer(face.width, face.height, pixels^))
            image.string("data:image/png;base64," + encode_base64(png))
        image.end_array()
        image.end_object()
        self.images.append(image.finish())
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("uuid")
        writer.string(object_uuid(_TEXTURE_UUID, at))
        writer.key("name")
        writer.string("")
        writer.key("image")
        writer.string(object_uuid(_IMAGE_UUID, at))
        writer.key("mapping")
        writer.integer(cube.mapping.value)
        writer.key("channel")
        writer.integer(0)
        writer.key("repeat")
        _numbers(writer, [1, 1])
        writer.key("offset")
        _numbers(writer, [0, 0])
        writer.key("center")
        _numbers(writer, [0, 0])
        writer.key("rotation")
        writer.integer(0)
        writer.key("wrap")
        writer.begin_array()
        writer.integer(CLAMP_TO_EDGE_WRAPPING)
        writer.integer(CLAMP_TO_EDGE_WRAPPING)
        writer.end_array()
        writer.key("format")
        writer.integer(RGBA_FORMAT)
        writer.key("type")
        writer.integer(UNSIGNED_BYTE_TYPE)
        writer.key("colorSpace")
        writer.string(SRGB_COLOR_SPACE if first.color_space == SRGB else "")
        writer.key("minFilter")
        writer.integer(filter_code(first.min_filter))
        writer.key("magFilter")
        writer.integer(filter_code(first.mag_filter))
        writer.key("anisotropy")
        writer.integer(1)
        writer.key("flipY")
        writer.boolean(False)
        writer.key("generateMipmaps")
        writer.boolean(first.levels > 1)
        writer.end_object()
        self.textures.append(writer.finish())
        self.texture_keys.append(key)
        return object_uuid(_TEXTURE_UUID, at)

    def env_map(
        mut self, mut writer: JsonWriter, material: Material, assets: Assets
    ) raises:
        """Write a reflecting material's `envMap` so that it reads back to
        the same reflection.

        three.js reads the scene's `environment` where a standard or
        physical material has no `envMap`, and nowhere else. So a basic,
        lambert or phong material that reflects the scene's environment
        names that cube itself, and a physical one that reflects nothing
        in a scene with an environment has no form. Each cube a physical
        material reflects must hold its PMREM, as three.js's renderer
        prefilters it.
        """
        var env = material.env_map
        var physical = material.kind.is_physical()
        if physical and env == SCENE_ENVIRONMENT:
            return
        if env == SCENE_ENVIRONMENT:
            env = self.environment
        if env == NO_CUBE_TEXTURE:
            if physical and self.environment != NO_CUBE_TEXTURE:
                raise Error(
                    "Object JSON: a standard or physical material that"
                    " reflects nothing in a scene with an environment has no"
                    " three.js form, as three.js reflects the environment"
                    " there"
                )
            return
        var uuid = self.cube(env, assets)
        if physical and not assets.cube_textures.get(env).is_prefiltered():
            raise Error(
                "Object JSON: a standard or physical material reflects a"
                " cube through its PMREM in three.js; build it with"
                " pmrem_from_cube"
            )
        writer.key("envMap")
        writer.string(uuid)

    def data_texture(
        mut self,
        values: List[Float32],
        side: Int,
        format: Int,
        type: Int,
        color_space: String,
    ) raises -> String:
        """Write a square three.js `DataTexture` and its image as new
        entries, as `Texture.toJSON` writes one, and return the texture's
        text: `BatchedMesh.toJSON` writes it inline as well."""
        var at = len(self.texture_keys)
        var image = JsonWriter()
        image.begin_object()
        image.key("uuid")
        image.string(object_uuid(_IMAGE_UUID, at))
        image.key("url")
        image.begin_object()
        image.key("data")
        image.begin_array()
        var floats = type == FLOAT_TYPE
        for value in values:
            if floats:
                image.number(value)
            else:
                image.integer(Int(value))
        image.end_array()
        image.key("width")
        image.integer(side)
        image.key("height")
        image.integer(side)
        image.key("type")
        image.string("Float32Array" if floats else "Uint32Array")
        image.end_object()
        image.end_object()
        self.images.append(image.finish())
        # What a `DataTexture` is built with: nearest, clamped, not flipped
        # and with no mip chain.
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("uuid")
        writer.string(object_uuid(_TEXTURE_UUID, at))
        writer.key("name")
        writer.string("")
        writer.key("image")
        writer.string(object_uuid(_IMAGE_UUID, at))
        writer.key("mapping")
        writer.integer(UV_MAPPING)
        writer.key("channel")
        writer.integer(0)
        writer.key("repeat")
        _numbers(writer, [1, 1])
        writer.key("offset")
        _numbers(writer, [0, 0])
        writer.key("center")
        _numbers(writer, [0, 0])
        writer.key("rotation")
        writer.integer(0)
        writer.key("wrap")
        writer.begin_array()
        writer.integer(CLAMP_TO_EDGE_WRAPPING)
        writer.integer(CLAMP_TO_EDGE_WRAPPING)
        writer.end_array()
        writer.key("format")
        writer.integer(format)
        writer.key("internalFormat")
        writer.null()
        writer.key("type")
        writer.integer(type)
        writer.key("colorSpace")
        writer.string(color_space)
        writer.key("minFilter")
        writer.integer(NEAREST_FILTER)
        writer.key("magFilter")
        writer.integer(NEAREST_FILTER)
        writer.key("anisotropy")
        writer.integer(1)
        writer.key("flipY")
        writer.boolean(False)
        writer.key("generateMipmaps")
        writer.boolean(False)
        writer.key("premultiplyAlpha")
        writer.boolean(False)
        writer.key("unpackAlignment")
        writer.integer(1)
        writer.end_object()
        var text = writer.finish()
        self.textures.append(text)
        self.texture_keys.append(-1)
        return text

    def skeleton(mut self, skeleton: Skeleton, nodes: Int) raises -> String:
        """Write a skeleton as `Skeleton.toJSON` does, and return its
        uuid."""
        var uuid = object_uuid(_SKELETON_UUID, len(self.skeletons))
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("uuid")
        writer.string(uuid)
        writer.key("bones")
        writer.begin_array()
        # A skeleton holds one bone at least; `Skeleton` refuses none.
        for bone in skeleton.bones:  # pragma: no branch
            writer.string(object_uuid(_NODE_UUID, _node_of(bone.node, nodes)))
        writer.end_array()
        writer.key("boneInverses")
        writer.begin_array()
        for bone in skeleton.bones:  # pragma: no branch
            _matrix(writer, bone.inverse_bind)
        writer.end_array()
        writer.end_object()
        self.skeletons.append(writer.finish())
        return uuid

    def map(
        mut self,
        mut writer: JsonWriter,
        key: String,
        id: TextureId,
        assets: Assets,
    ) raises:
        """Write `key` and a texture's uuid, when the id names one."""
        if id == NO_TEXTURE:
            return
        var uuid = self.texture(id, assets)
        writer.key(key)
        writer.string(uuid)

    def material(
        mut self, id: MaterialId, assets: Assets, use: String
    ) raises -> String:
        """Write a material once as a three.js class, and return its uuid.

        `use` is `_SURFACE_USE` for the class of the material's kind,
        `_LINE_USE` for `LineBasicMaterial` or `LineDashedMaterial`, or the
        name of the class to write, `PointsMaterial` or `SpriteMaterial`.
        """
        var material = assets.materials.get(id)
        var kind = material.kind
        if not kind.is_valid():
            raise Error("Object JSON: a material kind that is none of eleven")
        var type = material_type_names()[kind.value]
        if use == _LINE_USE:
            type = (
                "LineDashedMaterial" if material.is_dashed() else "LineBasicMaterial"
            )
        elif use != _SURFACE_USE:
            type = use
        var key = String(id.value) + " " + type
        var at = _find_text(self.material_keys, key)
        if at >= 0:
            return object_uuid(_MATERIAL_UUID, at)
        at = len(self.material_keys)
        var as_surface = use == _SURFACE_USE
        if not as_surface and kind != BASIC:
            raise Error(
                "Object JSON: a line, points or sprite material must be"
                " basic, as three.js's classes for them are unlit"
            )
        # The open fields, checked where they are read.
        _ = material.raster_state()
        _ = material.depth_offset()
        material.check_displacement()
        # A shadow material blends whatever it says, as three.js builds
        # its own `transparent`.
        var transparent = material.transparent or kind == SHADOW
        var blending = -1
        if material.blending == OPAQUE and transparent:
            blending = NO_BLENDING
        elif material.blending == BLEND and not transparent:
            raise Error(
                "Object JSON: a material that blends and is not transparent"
                " has no three.js form"
            )
        elif material.blending.value > BLEND.value:
            blending = material.blending.value
            if blending >= CUSTOM_BLENDING:
                raise Error("Object JSON: custom blending is not written")
        var writer = JsonWriter()
        writer.begin_object()
        writer.key("uuid")
        writer.string(object_uuid(_MATERIAL_UUID, at))
        writer.key("type")
        writer.string(type)
        if _has_color(kind):
            writer.key("color")
            writer.integer(material.color.hex())
        if as_surface:
            self.surface(writer, material, assets)
        elif use == _LINE_USE:
            _line_fields(writer, material)
        else:
            self.map(writer, "map", material.map, assets)
            self.map(writer, "alphaMap", material.alpha_map, assets)
            if type == "PointsMaterial":
                writer.key("size")
                writer.number(material.point_size.pixels)
            elif material.rotation.to(RADIAN) != 0:
                writer.key("rotation")
                writer.number(material.rotation.to(RADIAN))
            writer.key("sizeAttenuation")
            writer.boolean(material.size_attenuation)
        if material.side.value != 0:
            writer.key("side")
            writer.integer(material.side.value)
        if material.opacity < 1:
            writer.key("opacity")
            writer.number(material.opacity)
        if transparent:
            writer.key("transparent")
            writer.boolean(True)
        elif type == "SpriteMaterial":
            # A `SpriteMaterial` is built transparent, and three.js's own
            # writer leaves a false out, which its loader reads as true.
            writer.key("transparent")
            writer.boolean(False)
        if blending >= 0:
            writer.key("blending")
            writer.integer(blending)
        if material.alpha_test > 0:
            writer.key("alphaTest")
            writer.number(material.alpha_test)
        if material.vertex_colors:
            writer.key("vertexColors")
            writer.boolean(True)
        if material.wireframe:
            writer.key("wireframe")
            writer.boolean(True)
        _flags(writer, material)
        _raster(writer, material)
        _clipping(writer, material)
        if material.dash_offset != NO_DASH:
            writer.key("dashOffset")
            writer.number(material.dash_offset.to(METER))
        # three.js writes `fog` only when it is off, and its data materials
        # have no `fog` at all.
        var unfogged = not material.fog and not kind.is_data()
        if unfogged:
            writer.key("fog")
            writer.boolean(False)
        writer.end_object()
        self.materials.append(writer.finish())
        self.material_keys.append(key)
        return object_uuid(_MATERIAL_UUID, at)

    def surface(
        mut self, mut writer: JsonWriter, material: Material, assets: Assets
    ) raises:
        """Write what a mesh's material class has besides its color and
        the fields every class has."""
        var kind = material.kind
        if kind == STANDARD or kind == PHYSICAL:
            writer.key("roughness")
            writer.number(material.roughness)
            writer.key("metalness")
            writer.number(material.metalness)
            writer.key("envMapIntensity")
            writer.number(material.env_map_intensity)
            self.map(writer, "roughnessMap", material.roughness_map, assets)
            self.map(writer, "metalnessMap", material.metalness_map, assets)
        if kind == PHYSICAL:
            self.physical(writer, material, assets)
        if kind == PHONG:
            writer.key("specular")
            writer.integer(material.specular.hex())
            writer.key("shininess")
            writer.number(material.shininess)
        if _has_emissive(kind):
            writer.key("emissive")
            writer.integer(material.emissive.hex())
            writer.key("emissiveIntensity")
            writer.number(material.emissive_intensity)
        if kind.reflects():
            self.env_map(writer, material, assets)
            writer.key("envMapRotation")
            _euler(writer, material.env_map_rotation)
        if _reflects(kind):
            writer.key("reflectivity")
            writer.number(material.reflectivity)
            writer.key("refractionRatio")
            writer.number(material.refraction_ratio)
            writer.key("combine")
            writer.integer(material.combine.value)
        self.map(writer, "map", material.map, assets)
        self.map(writer, "emissiveMap", material.emissive_map, assets)
        self.map(writer, "alphaMap", material.alpha_map, assets)
        self.map(writer, "gradientMap", material.gradient_map, assets)
        self.map(writer, "matcap", material.matcap, assets)
        if material.normal_map != NO_TEXTURE:
            self.map(writer, "normalMap", material.normal_map, assets)
            writer.key("normalMapType")
            writer.integer(material.normal_map_type.value)
            writer.key("normalScale")
            _numbers(writer, [material.normal_scale.x, material.normal_scale.y])
        if material.bump_map != NO_TEXTURE:
            self.map(writer, "bumpMap", material.bump_map, assets)
            writer.key("bumpScale")
            writer.number(material.bump_scale)
        # The baked light and the displacement, each with its numbers, as
        # `Material.toJSON` writes them only beside their map.
        if material.light_map != NO_TEXTURE:
            self.map(writer, "lightMap", material.light_map, assets)
            writer.key("lightMapIntensity")
            writer.number(material.light_map_intensity)
        if material.ao_map != NO_TEXTURE:
            self.map(writer, "aoMap", material.ao_map, assets)
            writer.key("aoMapIntensity")
            writer.number(material.ao_map_intensity)
        if material.displacement_map != NO_TEXTURE:
            self.map(
                writer, "displacementMap", material.displacement_map, assets
            )
            writer.key("displacementScale")
            writer.number(material.displacement_scale.to(METER))
            writer.key("displacementBias")
            writer.number(material.displacement_bias.to(METER))
        self.map(writer, "specularMap", material.specular_map, assets)
        if material.flat_shading:
            writer.key("flatShading")
            writer.boolean(True)
        if kind == DEPTH:
            writer.key("depthPacking")
            writer.integer(material.depth_packing.value)
        if kind == DISTANCE:
            # The fields three.js's `MeshDistanceMaterial` once had, which
            # its `toJSON` never wrote: this port keeps them on the
            # material, so it writes them under their old names.
            ref point = material.reference_position
            writer.key("referencePosition")
            _numbers(writer, [point.x, point.y, point.z])
            writer.key("nearDistance")
            writer.number(material.near_distance.to(METER))
            writer.key("farDistance")
            writer.number(material.far_distance.to(METER))

    def physical(
        mut self, mut writer: JsonWriter, material: Material, assets: Assets
    ) raises:
        """Write what a `MeshPhysicalMaterial` adds to a standard one."""
        writer.key("ior")
        writer.number(material.ior)
        writer.key("specularColor")
        writer.integer(material.specular_color.hex())
        writer.key("specularIntensity")
        writer.number(material.specular_intensity)
        self.map(
            writer,
            "specularIntensityMap",
            material.specular_intensity_map,
            assets,
        )
        self.map(
            writer, "specularColorMap", material.specular_color_map, assets
        )
        writer.key("clearcoat")
        writer.number(material.clearcoat)
        writer.key("clearcoatRoughness")
        writer.number(material.clearcoat_roughness)
        self.map(writer, "clearcoatMap", material.clearcoat_map, assets)
        self.map(
            writer,
            "clearcoatRoughnessMap",
            material.clearcoat_roughness_map,
            assets,
        )
        # The scale beside its map, as `Material.toJSON` writes it.
        if material.clearcoat_normal_map != NO_TEXTURE:
            self.map(
                writer,
                "clearcoatNormalMap",
                material.clearcoat_normal_map,
                assets,
            )
            writer.key("clearcoatNormalScale")
            _numbers(
                writer,
                [
                    material.clearcoat_normal_scale.x,
                    material.clearcoat_normal_scale.y,
                ],
            )
        writer.key("sheen")
        writer.number(material.sheen)
        writer.key("sheenColor")
        writer.integer(material.sheen_color.hex())
        writer.key("sheenRoughness")
        writer.number(material.sheen_roughness)
        self.map(writer, "sheenColorMap", material.sheen_color_map, assets)
        self.map(
            writer, "sheenRoughnessMap", material.sheen_roughness_map, assets
        )
        writer.key("dispersion")
        writer.number(material.dispersion)
        writer.key("iridescence")
        writer.number(material.iridescence)
        writer.key("iridescenceIOR")
        writer.number(material.iridescence_ior)
        writer.key("iridescenceThicknessRange")
        _numbers(
            writer,
            [
                material.iridescence_thickness_minimum.to(NANOMETER),
                material.iridescence_thickness_maximum.to(NANOMETER),
            ],
        )
        self.map(writer, "iridescenceMap", material.iridescence_map, assets)
        self.map(
            writer,
            "iridescenceThicknessMap",
            material.iridescence_thickness_map,
            assets,
        )
        writer.key("anisotropy")
        writer.number(material.anisotropy)
        writer.key("anisotropyRotation")
        writer.number(material.anisotropy_rotation.to(RADIAN))
        self.map(writer, "anisotropyMap", material.anisotropy_map, assets)
        writer.key("transmission")
        writer.number(material.transmission)
        self.map(writer, "transmissionMap", material.transmission_map, assets)
        writer.key("thickness")
        writer.number(material.thickness.to(METER))
        self.map(writer, "thicknessMap", material.thickness_map, assets)
        # three.js leaves out its default distance, which is infinite.
        var distance = material.attenuation_distance.to(METER)
        if isfinite(distance):
            writer.key("attenuationDistance")
            writer.number(distance)
        writer.key("attenuationColor")
        writer.integer(material.attenuation_color.hex())


def _line_fields(mut writer: JsonWriter, material: Material) raises:
    """Write a `LineBasicMaterial`'s width and a `LineDashedMaterial`'s
    dashes."""
    var width = material.line_width
    if width.world_units:
        raise Error(
            "Object JSON: a line width in world units has no three.js form"
            " on a line"
        )
    if width != DEFAULT_LINE_WIDTH:
        writer.key("linewidth")
        writer.number(width.size)
    if material.is_dashed():
        writer.key("dashSize")
        writer.number(material.dash_size.to(METER))
        writer.key("gapSize")
        writer.number(material.gap_size.to(METER))
        writer.key("scale")
        writer.number(material.dash_scale)


def _flags(mut writer: JsonWriter, material: Material) raises:
    """Write the shadow side, the blend constant, the fragment flags and
    whether the material is visible, each where it is not three.js's
    default, as `Material.toJSON` writes them."""
    var sided = Bool(material.shadow_side)
    if sided:
        writer.key("shadowSide")
        writer.integer(material.shadow_face().value)
    if material.blend_color.hex() != 0:
        writer.key("blendColor")
        writer.integer(material.blend_color.hex())
    if material.blend_alpha != 0:
        writer.key("blendAlpha")
        writer.number(material.blend_alpha)
    if material.dithering:
        writer.key("dithering")
        writer.boolean(True)
    if material.alpha_hash:
        writer.key("alphaHash")
        writer.boolean(True)
    if material.alpha_to_coverage:
        writer.key("alphaToCoverage")
        writer.boolean(True)
    if material.premultiplied_alpha:
        writer.key("premultipliedAlpha")
        writer.boolean(True)
    if not material.visible:
        writer.key("visible")
        writer.boolean(False)
    if not material.tone_mapped:
        writer.key("toneMapped")
        writer.boolean(False)


def _raster(mut writer: JsonWriter, material: Material) raises:
    """Write the depth, stencil and polygon offset state that is not
    three.js's default, as `Material.toJSON` does."""
    if material.depth_func != LESS_EQUAL_DEPTH:
        writer.key("depthFunc")
        writer.integer(material.depth_func.value)
    if not material.depth_test:
        writer.key("depthTest")
        writer.boolean(False)
    if not material.depth_write:
        writer.key("depthWrite")
        writer.boolean(False)
    if not material.color_write:
        writer.key("colorWrite")
        writer.boolean(False)
    if material.stencil_write_mask != STENCIL_MAX:
        writer.key("stencilWriteMask")
        writer.integer(material.stencil_write_mask)
    if material.stencil_func != ALWAYS_STENCIL_FUNC:
        writer.key("stencilFunc")
        writer.integer(material.stencil_func.value + STENCIL_FUNC_BASE)
    if material.stencil_ref != 0:
        writer.key("stencilRef")
        writer.integer(material.stencil_ref)
    if material.stencil_func_mask != STENCIL_MAX:
        writer.key("stencilFuncMask")
        writer.integer(material.stencil_func_mask)
    if material.stencil_fail != KEEP_STENCIL_OP:
        writer.key("stencilFail")
        writer.integer(stencil_op_code(material.stencil_fail))
    if material.stencil_z_fail != KEEP_STENCIL_OP:
        writer.key("stencilZFail")
        writer.integer(stencil_op_code(material.stencil_z_fail))
    if material.stencil_z_pass != KEEP_STENCIL_OP:
        writer.key("stencilZPass")
        writer.integer(stencil_op_code(material.stencil_z_pass))
    if material.stencil_write:
        writer.key("stencilWrite")
        writer.boolean(True)
    if material.polygon_offset:
        writer.key("polygonOffset")
        writer.boolean(True)
    if material.polygon_offset_factor != 0:
        writer.key("polygonOffsetFactor")
        writer.number(material.polygon_offset_factor)
    if material.polygon_offset_units != 0:
        writer.key("polygonOffsetUnits")
        writer.number(material.polygon_offset_units)


def _clipping(mut writer: JsonWriter, material: Material) raises:
    """Write a material's own clipping planes and how they cut.

    three.js's `Material.toJSON` writes none of the three. Each plane is
    written as `JSON.stringify` writes a three.js `Plane`, a `normal` and a
    `constant`, with the normal as an array.
    """
    var planes = material.clipping_planes()
    if len(planes) > 0:
        writer.key("clippingPlanes")
        writer.begin_array()
        for plane in planes:  # pragma: no branch
            writer.begin_object()
            writer.key("normal")
            _numbers(writer, [plane.normal.x, plane.normal.y, plane.normal.z])
            writer.key("constant")
            writer.number(plane.constant)
            writer.end_object()
        writer.end_array()
    if material.clip_intersection:
        writer.key("clipIntersection")
        writer.boolean(True)
    if material.clip_shadows:
        writer.key("clipShadows")
        writer.boolean(True)


def _influences(
    mut writer: JsonWriter,
    influences: SIMD[DType.float32, MAX_MORPH_TARGETS],
    count: Int,
) raises:
    """Write a mesh's `morphTargetInfluences`, one for each of its
    geometry's morph targets, as three.js writes them."""
    if count == 0:
        return
    writer.key("morphTargetInfluences")
    writer.begin_array()
    for target in range(count):  # pragma: no branch
        writer.number(influences[target])
    writer.end_array()


def _find(keys: List[Int], key: Int) -> Int:
    """Return where a key is in a list, or -1."""
    var found = -1
    for at in range(len(keys)):
        if keys[at] == key:
            found = at
    return found


def _find_text(keys: List[String], key: String) -> Int:
    """Return where a text is in a list, or -1."""
    var found = -1
    for at in range(len(keys)):
        if keys[at] == key:
            found = at
    return found


struct _Joined(Movable):
    """A batch's geometries joined into one, as three.js's `BatchedMesh`
    holds them, and where each one starts."""

    var geometry: BufferGeometry
    var vertex_starts: List[Int]
    var vertex_counts: List[Int]
    var index_starts: List[Int]
    var index_counts: List[Int]
    var vertices: Int
    var indices: Int
    var indexed: Bool

    def __init__(out self, geometries: List[Int], assets: Assets) raises:
        """Join geometries, which must share their attributes and index."""
        self.geometry = BufferGeometry()
        self.vertex_starts = List[Int]()
        self.vertex_counts = List[Int]()
        self.index_starts = List[Int]()
        self.index_counts = List[Int]()
        self.vertices = 0
        self.indices = 0
        self.indexed = False
        if len(geometries) == 0:
            return
        ref first = assets.geometries.get(GeometryId(geometries[0]))
        self.indexed = first.is_indexed()
        # Refuses a geometry with no positions, so every geometry below
        # has one attribute at least.
        _ = first.vertex_count()
        var names = first.names.copy()
        var sizes = List[Int]()
        var data = List[List[Float32]]()
        for slot in range(len(names)):  # pragma: no branch
            sizes.append(first.values[slot].item_size)
            data.append(List[Float32]())
        var index = List[Int]()
        for id in geometries:  # pragma: no branch
            ref geometry = assets.geometries.get(GeometryId(id))
            var fits = (
                not geometry.instanced
                and geometry.morph_count() == 0
                and geometry.is_indexed() == self.indexed
                and len(geometry.names) == len(names)
            )
            if not fits:
                raise Error(
                    "Object JSON: a batch's geometries must share their"
                    " attributes and index and carry no morph targets, as"
                    " three.js's BatchedMesh joins them"
                )
            var vertices = geometry.vertex_count()
            for slot in range(len(names)):  # pragma: no branch
                if not geometry.has_attribute(names[slot]):
                    raise Error(
                        "Object JSON: a batch's geometries must share their"
                        " attributes"
                    )
                ref attribute = geometry.attribute_view(names[slot])
                if attribute.item_size != sizes[slot]:
                    raise Error(
                        "Object JSON: a batch's attributes must share their"
                        " item size"
                    )
                data[slot].extend(attribute.packed())
            self.vertex_starts.append(self.vertices)
            self.vertex_counts.append(vertices)
            self.index_starts.append(self.indices if self.indexed else -1)
            self.index_counts.append(
                len(geometry.index) if self.indexed else -1
            )
            for entry in geometry.index:
                index.append(entry + self.vertices)
            self.vertices += vertices
            self.indices += len(geometry.index)
        for slot in range(len(names)):  # pragma: no branch
            self.geometry.set_attribute(
                names[slot], BufferAttribute(data[slot].copy(), sizes[slot])
            )
        self.geometry.set_index(index^)


# What a thing a node carries is, in the order a node's parts are written.
comptime _MESH = 0
comptime _INSTANCED = 1
comptime _LIGHT = 2
comptime _PERSPECTIVE = 3
comptime _ORTHOGRAPHIC = 4
comptime _BATCHED = 5
comptime _SKINNED = 6
comptime _LINE = 7
comptime _POINTS = 8
comptime _SPRITE = 9
comptime _LOD = 10
# A thing is its category times this, plus its position in its list.
comptime _STRIDE = 1 << 32
# What `_Library.material` is asked to write a material as.
comptime _SURFACE_USE = ""
comptime _LINE_USE = "Line"


struct _Carried(Movable):
    """What each node carries, by category and position in the scene's
    lists."""

    # Each node's things, in the order of their categories.
    var things: List[List[Int]]
    # The lights that ride no node.
    var loose: List[Int]
    # Whether each node is a bone of a skinned mesh.
    var bones: List[Bool]

    def __init__(out self, scene: Scene, cameras: ObjectCameras) raises:
        """Sort a scene's things onto its nodes."""
        var count = scene.count()
        self.things = List[List[Int]]()
        self.loose = List[Int]()
        self.bones = List[Bool](length=count, fill=False)
        for _ in range(count):
            self.things.append(List[Int]())
        for at in range(len(scene.meshes)):
            self.add(_MESH, at, scene.meshes[at].node, count)
        for at in range(len(scene.instanced_meshes)):
            self.add(_INSTANCED, at, scene.instanced_meshes[at].node, count)
        for at in range(len(scene.lights)):
            var node = scene.lights[at].node
            if node == NO_PARENT:
                self.loose.append(at)
            else:
                self.add(_LIGHT, at, node, count)
        for at in range(len(cameras.perspective)):
            self.add(_PERSPECTIVE, at, cameras.perspective[at].node, count)
        for at in range(len(cameras.orthographic)):
            self.add(_ORTHOGRAPHIC, at, cameras.orthographic[at].node, count)
        for at in range(len(scene.batched_meshes)):
            self.add(_BATCHED, at, scene.batched_meshes[at].node, count)
        for at in range(len(scene.skinned_meshes)):
            ref mesh = scene.skinned_meshes[at]
            self.add(_SKINNED, at, mesh.node, count)
            for bone in mesh.skeleton.bones:  # pragma: no branch
                self.bones[_node_of(bone.node, count)] = True
        for at in range(len(scene.lines)):
            self.add(_LINE, at, scene.lines[at].node, count)
        for at in range(len(scene.points)):
            self.add(_POINTS, at, scene.points[at].node, count)
        for at in range(len(scene.sprites)):
            self.add(_SPRITE, at, scene.sprites[at].node, count)
        for at in range(len(scene.lods)):
            self.add(_LOD, at, scene.lods[at].node, count)

    def add(mut self, category: Int, at: Int, node: NodeId, count: Int) raises:
        """Put a thing on its node."""
        self.things[_node_of(node, count)].append(category * _STRIDE + at)


def _node_of(node: NodeId, count: Int) raises -> Int:
    """Return a node's position, refusing one that is not in the scene."""
    if node.value < 0 or node.value >= count:
        raise Error(
            "Object JSON: a thing names a node that is not in the scene;"
            " attach a camera to a node to write it"
        )
    return node.value


struct _Writer(Movable):
    """The libraries being filled while the object tree is written."""

    var library: _Library
    # The uuid each thing was written with, by its category and position,
    # which a track on it is named by.
    var named: Dict[Int, String]

    def __init__(out self):
        """Start with empty libraries."""
        self.library = _Library()
        self.named = Dict[Int, String]()

    def thing(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        thing: Int,
        scene: Scene,
        cameras: ObjectCameras,
        assets: Assets,
    ) raises -> List[String]:
        """Write one thing's header and fields, and return the objects of
        an LOD's levels, which are its children."""
        var category = thing // _STRIDE
        var which = thing % _STRIDE
        if category == _LOD:
            return self.lod(writer, header^, scene, which, assets)
        if category == _MESH:
            self.mesh(writer, header^, scene, which, assets)
        elif category == _INSTANCED:
            self.instanced(writer, header^, scene, which, assets)
        elif category == _LIGHT:
            self.light(writer, header^, scene, which)
        elif category == _PERSPECTIVE:
            self.perspective(writer, header^, cameras.perspective[which])
        elif category == _ORTHOGRAPHIC:
            self.orthographic(writer, header^, cameras.orthographic[which])
        elif category == _BATCHED:
            self.batched(writer, header^, scene, which, assets)
        elif category == _SKINNED:
            self.skinned(writer, header^, scene, which, assets)
        elif category == _LINE:
            self.line(writer, header^, scene, which, assets)
        elif category == _POINTS:
            self.points(writer, header^, scene, which, assets)
        else:
            self.sprite(writer, header^, scene, which, assets)
        return List[String]()

    def mesh(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises:
        """Write a mesh's header and fields."""
        ref mesh = scene.meshes[which]
        header.type = "Mesh"
        header.cast_shadow = mesh.cast_shadow
        header.receive_shadow = mesh.receive_shadow
        header.frustum_culled = mesh.frustum_culled
        header.write(writer)
        writer.key("geometry")
        writer.string(self.library.geometry(mesh.geometry, assets))
        writer.key("material")
        if mesh.is_multi_material():
            # three.js's `toJSON` writes a list of uuids for a list.
            writer.begin_array()
            for material in mesh.materials:  # pragma: no branch
                writer.string(
                    self.library.material(material, assets, _SURFACE_USE)
                )
            writer.end_array()
        else:
            writer.string(
                self.library.material(mesh.material, assets, _SURFACE_USE)
            )
        _influences(
            writer,
            mesh.morph_influences,
            assets.geometries.get(mesh.geometry).morph_count(),
        )

    def instanced(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises:
        """Write an instanced mesh's header and fields."""
        ref mesh = scene.instanced_meshes[which]
        header.type = "InstancedMesh"
        header.frustum_culled = mesh.frustum_culled
        header.write(writer)
        writer.key("geometry")
        writer.string(self.library.geometry(mesh.geometry, assets))
        writer.key("material")
        writer.string(
            self.library.material(mesh.material, assets, _SURFACE_USE)
        )
        writer.key("count")
        writer.integer(mesh.count())
        var data = List[Float32]()
        for matrix in mesh.matrices:
            for index in range(16):  # pragma: no branch
                data.append(matrix.elements[index])
        writer.key("instanceMatrix")
        _attribute(writer, BufferAttribute(data^, 16))

    def batched(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises:
        """Write a batched mesh as `Object3D.toJSON` writes one."""
        ref batch = scene.batched_meshes[which]
        var count = batch.count()
        # Each geometry once, in the order the instances first name them.
        var geometries = List[Int]()
        var chosen = List[Int]()
        var tinted = False
        for instance in batch.instances:
            var at = _find(geometries, instance.geometry.value)
            if at < 0:
                at = len(geometries)
                geometries.append(instance.geometry.value)
            chosen.append(at)
            if instance.color.hex() != _WHITE_HEX:
                tinted = True
        var joined = _Joined(geometries, assets)
        var geometry = self.library.add_geometry(joined.geometry, -1)
        header.type = "BatchedMesh"
        header.write(writer)
        writer.key("geometry")
        writer.string(object_uuid(_GEOMETRY_UUID, geometry))
        writer.key("material")
        writer.string(
            self.library.material(batch.material, assets, _SURFACE_USE)
        )
        writer.key("perObjectFrustumCulled")
        writer.boolean(batch.frustum_culled)
        writer.key("sortObjects")
        writer.boolean(True)
        writer.key("geometryInfo")
        writer.begin_array()
        for at in range(len(geometries)):
            var first = joined.vertex_starts[at]
            var vertices = joined.vertex_counts[at]
            var start = joined.index_starts[at]
            var indices = joined.index_counts[at]
            writer.begin_object()
            writer.key("vertexStart")
            writer.integer(first)
            writer.key("vertexCount")
            writer.integer(vertices)
            writer.key("reservedVertexCount")
            writer.integer(vertices)
            writer.key("indexStart")
            writer.integer(start)
            writer.key("indexCount")
            writer.integer(indices)
            writer.key("reservedIndexCount")
            writer.integer(indices)
            writer.key("start")
            writer.integer(start if joined.indexed else first)
            writer.key("count")
            writer.integer(indices if joined.indexed else vertices)
            writer.key("active")
            writer.boolean(True)
            writer.end_object()
        writer.end_array()
        writer.key("instanceInfo")
        writer.begin_array()
        for at in chosen:
            writer.begin_object()
            writer.key("visible")
            writer.boolean(True)
            writer.key("active")
            writer.boolean(True)
            writer.key("geometryIndex")
            writer.integer(at)
            writer.end_object()
        writer.end_array()
        writer.key("availableInstanceIds")
        writer.begin_array()
        writer.end_array()
        writer.key("availableGeometryIds")
        writer.begin_array()
        writer.end_array()
        writer.key("nextIndexStart")
        writer.integer(joined.indices)
        writer.key("nextVertexStart")
        writer.integer(joined.vertices)
        writer.key("geometryCount")
        writer.integer(len(geometries))
        writer.key("maxInstanceCount")
        writer.integer(count)
        writer.key("maxVertexCount")
        writer.integer(joined.vertices)
        writer.key("maxIndexCount")
        writer.integer(joined.indices)
        writer.key("geometryInitialized")
        writer.boolean(True)
        # three.js's `_initMatricesTexture`: four texels a matrix, in a
        # square whose side is a multiple of four.
        var side = max(
            Int(ceil(sqrt(Float64(count * 4)) / 4)) * 4, _MATRICES_SIDE
        )
        var matrices = List[Float32](length=side * side * 4, fill=0)
        for at in range(count):
            ref matrix = batch.instances[at].matrix
            for element in range(16):  # pragma: no branch
                matrices[at * 16 + element] = matrix.elements[element]
        writer.key("matricesTexture")
        writer.raw(
            self.library.data_texture(
                matrices, side, RGBA_FORMAT, FLOAT_TYPE, ""
            )
        )
        # `_initIndirectTexture` and `_initColorsTexture`: a texel an
        # instance. The indirect texture is filled when three.js draws.
        var square = Int(ceil(sqrt(Float64(count))))
        writer.key("indirectTexture")
        writer.raw(
            self.library.data_texture(
                List[Float32](length=square * square, fill=0),
                square,
                RED_INTEGER_FORMAT,
                UNSIGNED_INT_TYPE,
                "",
            )
        )
        if tinted:
            var colors = List[Float32](length=square * square * 4, fill=1)
            for at in range(count):  # pragma: no branch
                var linear = FloatColor(srgb=batch.instances[at].color)
                colors[at * 4] = linear.r
                colors[at * 4 + 1] = linear.g
                colors[at * 4 + 2] = linear.b
            writer.key("colorsTexture")
            writer.raw(
                self.library.data_texture(
                    colors,
                    square,
                    RGBA_FORMAT,
                    FLOAT_TYPE,
                    LINEAR_SRGB_COLOR_SPACE,
                )
            )

    def skinned(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises:
        """Write a skinned mesh and its skeleton, as `SkinnedMesh.toJSON`
        does."""
        ref mesh = scene.skinned_meshes[which]
        var mode = bind_mode_name(mesh.bind_mode)
        header.type = "SkinnedMesh"
        header.frustum_culled = mesh.frustum_culled
        header.write(writer)
        writer.key("geometry")
        writer.string(self.library.geometry(mesh.geometry, assets))
        writer.key("material")
        writer.string(
            self.library.material(mesh.material, assets, _SURFACE_USE)
        )
        _influences(
            writer,
            mesh.morph_influences,
            assets.geometries.get(mesh.geometry).morph_count(),
        )
        writer.key("bindMode")
        writer.string(mode)
        writer.key("bindMatrix")
        _matrix(writer, mesh.bind_matrix)
        writer.key("skeleton")
        writer.string(self.library.skeleton(mesh.skeleton, scene.count()))

    def line(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises:
        """Write a line as the three.js class of its mode."""
        ref line = scene.lines[which]
        if not line.mode.is_valid():
            raise Error("Object JSON: a line mode that is none of the three")
        header.type = line_type_names()[line.mode.value]
        header.frustum_culled = line.frustum_culled
        header.write(writer)
        writer.key("geometry")
        writer.string(self.library.geometry(line.geometry, assets))
        writer.key("material")
        writer.string(self.library.material(line.material, assets, _LINE_USE))

    def points(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises:
        """Write points and their `PointsMaterial`."""
        ref points = scene.points[which]
        header.type = "Points"
        header.frustum_culled = points.frustum_culled
        header.write(writer)
        writer.key("geometry")
        writer.string(self.library.geometry(points.geometry, assets))
        writer.key("material")
        writer.string(
            self.library.material(points.material, assets, "PointsMaterial")
        )

    def sprite(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises:
        """Write a sprite and its `SpriteMaterial`, and its center when it
        is not the middle."""
        ref sprite = scene.sprites[which]
        header.type = "Sprite"
        header.frustum_culled = sprite.frustum_culled
        header.write(writer)
        writer.key("material")
        writer.string(
            self.library.material(sprite.material, assets, "SpriteMaterial")
        )
        var center = sprite.center
        var middle = center.x == 0.5 and center.y == 0.5
        if not middle:
            writer.key("center")
            _numbers(writer, [center.x, center.y])

    def lod(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
        assets: Assets,
    ) raises -> List[String]:
        """Write an LOD as `LOD.toJSON` does, and return its levels, each a
        mesh object at the identity."""
        ref lod = scene.lods[which]
        header.type = "LOD"
        header.frustum_culled = lod.frustum_culled
        header.write(writer)
        writer.key("autoUpdate")
        writer.boolean(True)
        writer.key("levels")
        writer.begin_array()
        var levels = List[String]()
        for level in lod.levels:
            var uuid = self.library.part_uuid()
            var part = _Header(uuid, header.layers)
            part.type = "Mesh"
            part.frustum_culled = lod.frustum_culled
            var mesh = JsonWriter()
            mesh.begin_object()
            part.write(mesh)
            mesh.key("geometry")
            mesh.string(self.library.geometry(level.geometry, assets))
            mesh.key("material")
            mesh.string(
                self.library.material(level.material, assets, _SURFACE_USE)
            )
            mesh.end_object()
            levels.append(mesh.finish())
            writer.begin_object()
            writer.key("object")
            writer.string(uuid)
            writer.key("distance")
            writer.number(level.distance.to(METER))
            writer.key("hysteresis")
            writer.number(level.hysteresis)
            writer.end_object()
        writer.end_array()
        return levels^

    def light(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        scene: Scene,
        which: Int,
    ) raises:
        """Write a light's header and fields."""
        var light = scene.lights[which]
        light.validate()
        header.type = light_type_names()[light.kind.value]
        header.cast_shadow = light.cast_shadow
        header.write(writer)
        writer.key("color")
        writer.integer(light.color.hex())
        writer.key("intensity")
        writer.number(light.intensity)
        var kind = light.kind
        if kind == HEMISPHERE:
            writer.key("groundColor")
            writer.integer(light.ground.hex())
        if kind == POINT or kind == SPOT:
            writer.key("distance")
            writer.number(light.distance)
            writer.key("decay")
            writer.number(light.decay)
        if kind == SPOT:
            writer.key("angle")
            writer.number(light.angle.to(RADIAN))
            writer.key("penumbra")
            writer.number(light.penumbra)
        if kind == LIGHT_PROBE:
            # three.js's `LightProbe.toJSON`: the 27 numbers, `sh.toArray`.
            writer.key("sh")
            writer.begin_array()
            for value in light.sh.to_array():  # pragma: no branch
                writer.number(value)
            writer.end_array()
        if kind == RECT_AREA:
            writer.key("width")
            writer.number(light.width.to(METER))
            writer.key("height")
            writer.number(light.height.to(METER))
        if kind == POINT:
            _shadow(writer, light)
        if kind == DIRECTIONAL or kind == SPOT:
            _shadow(writer, light)
            if light.target != NO_PARENT:
                writer.key("target")
                writer.string(
                    object_uuid(
                        _NODE_UUID, _node_of(light.target, scene.count())
                    )
                )

    def perspective(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        camera: PerspectiveCamera,
    ) raises:
        """Write a perspective camera's header and fields."""
        if camera.view_shift.value != 0:
            raise Error("Object JSON: a camera's view shift is not written")
        camera.validate()
        header.type = "PerspectiveCamera"
        header.write(writer)
        writer.key("fov")
        writer.number(camera.fov.to(DEGREE))
        writer.key("zoom")
        writer.number(camera.zoom)
        writer.key("near")
        writer.number(camera.near.to(METER))
        writer.key("far")
        writer.number(camera.far.to(METER))
        writer.key("focus")
        writer.number(camera.focus.to(METER))
        writer.key("aspect")
        writer.number(camera.aspect)
        if Bool(camera.view):
            _view(writer, camera.view.value())
        writer.key("filmGauge")
        writer.number(camera.film_gauge.to(MILLIMETER))
        writer.key("filmOffset")
        writer.number(camera.film_offset.to(MILLIMETER))

    def orthographic(
        mut self,
        mut writer: JsonWriter,
        var header: _Header,
        camera: OrthographicCamera,
    ) raises:
        """Write an orthographic camera's header and fields."""
        header.type = "OrthographicCamera"
        header.write(writer)
        writer.key("zoom")
        writer.number(camera.zoom)
        writer.key("left")
        writer.number(camera.left.to(METER))
        writer.key("right")
        writer.number(camera.right.to(METER))
        writer.key("top")
        writer.number(camera.top.to(METER))
        writer.key("bottom")
        writer.number(camera.bottom.to(METER))
        writer.key("near")
        writer.number(camera.near.to(METER))
        writer.key("far")
        writer.number(camera.far.to(METER))
        if Bool(camera.view):
            _view(writer, camera.view.value())

    def on_layers(
        self, thing: Int, layers: Layers, scene: Scene, cameras: ObjectCameras
    ) -> Bool:
        """Return True unless a thing is a light or a camera on other layers
        than `layers`."""
        var category = thing // _STRIDE
        var which = thing % _STRIDE
        if category == _LIGHT:
            return scene.lights[which].layers == layers
        if category == _PERSPECTIVE:
            return cameras.perspective[which].layers == layers
        if category == _ORTHOGRAPHIC:
            return cameras.orthographic[which].layers == layers
        return True

    def node(
        mut self,
        mut writer: JsonWriter,
        scene: Scene,
        index: Int,
        carried: _Carried,
        cameras: ObjectCameras,
        assets: Assets,
    ) raises:
        """Write one node as an object, what it carries, and its children."""
        var node = scene.get(NodeId(index))
        var header = _Header(object_uuid(_NODE_UUID, index), node)
        ref things = carried.things[index]
        # The one thing the node becomes, when it carries one thing and
        # that thing is on the node's layers.
        var chosen = -1
        if len(things) == 1:
            if self.on_layers(things[0], node.layers, scene, cameras):
                chosen = things[0]
        if chosen < 0 and carried.bones[index]:
            header.type = "Bone"
        writer.begin_object()
        var levels = List[String]()
        if chosen >= 0:
            self.named[chosen] = header.uuid
            levels = self.thing(writer, header^, chosen, scene, cameras, assets)
        else:
            header.write(writer)
        var children = scene.children(NodeId(index))
        var parts = len(things) + len(levels)
        if chosen >= 0:
            parts -= 1
        if len(children) + parts > 0:
            writer.key("children")
            writer.begin_array()
            for child in children:
                self.node(writer, scene, child.value, carried, cameras, assets)
            for level in levels:
                writer.raw(level)
            for thing in things:
                if thing != chosen:
                    self.part(
                        writer, thing, node.layers, scene, cameras, assets
                    )
            writer.end_array()
        writer.end_object()

    def part(
        mut self,
        mut writer: JsonWriter,
        thing: Int,
        layers: Layers,
        scene: Scene,
        cameras: ObjectCameras,
        assets: Assets,
    ) raises:
        """Write a thing as an object of its own at the identity: on its
        own layers for a light or a camera, and on `layers` otherwise."""
        var category = thing // _STRIDE
        var which = thing % _STRIDE
        var own = layers
        if category == _LIGHT:
            own = scene.lights[which].layers
        elif category == _PERSPECTIVE:
            own = cameras.perspective[which].layers
        elif category == _ORTHOGRAPHIC:
            own = cameras.orthographic[which].layers
        writer.begin_object()
        var uuid = self.library.part_uuid()
        self.named[thing] = uuid
        var levels = self.thing(
            writer,
            _Header(uuid, own),
            thing,
            scene,
            cameras,
            assets,
        )
        if len(levels) > 0:
            writer.key("children")
            writer.begin_array()
            for level in levels:  # pragma: no branch
                writer.raw(level)
            writer.end_array()
        writer.end_object()


def _view(mut writer: JsonWriter, view: ViewOffset) raises:
    """Write a camera's `view`, as three.js's `Object.assign` copies it.

    Args:
        writer: The writer, inside the camera's object.
        view: The tile.

    Raises:
        Error: If `ViewOffset.validate` refuses the tile.
    """
    view.validate()
    writer.key("view")
    writer.begin_object()
    writer.key("enabled")
    writer.boolean(view.enabled)
    writer.key("fullWidth")
    writer.number(view.full_width)
    writer.key("fullHeight")
    writer.number(view.full_height)
    writer.key("offsetX")
    writer.number(view.offset_x)
    writer.key("offsetY")
    writer.number(view.offset_y)
    writer.key("width")
    writer.number(view.width)
    writer.key("height")
    writer.number(view.height)
    writer.end_object()


def _shadow(mut writer: JsonWriter, light: Light) raises:
    """Write a directional, point or spot light's shadow, as
    `LightShadow.toJSON` writes it: a point light's camera is ninety
    degrees wide, as `PointLightShadow` builds it."""
    ref shadow = light.shadow
    writer.key("shadow")
    writer.begin_object()
    if shadow.intensity != 1:
        writer.key("intensity")
        writer.number(shadow.intensity)
    writer.key("bias")
    writer.number(shadow.bias)
    writer.key("normalBias")
    writer.number(shadow.normal_bias)
    writer.key("radius")
    writer.number(shadow.radius)
    writer.key("mapSize")
    writer.begin_array()
    writer.integer(shadow.map_size)
    writer.integer(shadow.map_size)
    writer.end_array()
    writer.key("camera")
    writer.begin_object()
    if light.kind == DIRECTIONAL:
        writer.key("type")
        writer.string("OrthographicCamera")
        writer.key("left")
        writer.number(shadow.left.to(METER))
        writer.key("right")
        writer.number(shadow.right.to(METER))
        writer.key("top")
        writer.number(shadow.top.to(METER))
        writer.key("bottom")
        writer.number(shadow.bottom.to(METER))
    else:
        var fov = Float32(90)
        if light.kind == SPOT:
            fov = 2 * light.angle.to(DEGREE)
        writer.key("type")
        writer.string("PerspectiveCamera")
        writer.key("fov")
        writer.number(fov)
        writer.key("aspect")
        writer.integer(1)
    writer.key("near")
    writer.number(shadow.near.to(METER))
    writer.key("far")
    writer.number(shadow.far.to(METER))
    writer.end_object()
    writer.end_object()


def _track_name(
    target: TrackTarget, named: Dict[Int, String], scene: Scene
) raises -> String:
    """Return a track's name: the uuid of the object its target is on, and
    the path of the property, as three.js's `PropertyBinding` reads it
    below the scene."""
    var kind = target.kind
    var thing = -1
    if kind.is_node():
        return object_uuid(
            _NODE_UUID, _node_of(NodeId(target.index), scene.count())
        ) + property_path(target)
    if kind.is_skinned():
        thing = _SKINNED * _STRIDE + target.index
    elif kind.is_morph():
        thing = _MESH * _STRIDE + target.index
    elif kind.is_light():
        thing = _LIGHT * _STRIDE + target.index
    elif kind.is_camera():
        thing = (
            _ORTHOGRAPHIC if target.slot == ORTHOGRAPHIC_SLOT else _PERSPECTIVE
        ) * _STRIDE + target.index
    else:
        # A material is not an object: the track is on a mesh that draws
        # with it, as three.js's `.material` path is.
        for mesh in range(len(scene.meshes)):
            if scene.meshes[mesh].material.value == target.index:
                thing = _MESH * _STRIDE + mesh
                break
        if thing < 0:
            for mesh in range(len(scene.skinned_meshes)):
                if scene.skinned_meshes[mesh].material.value == target.index:
                    thing = _SKINNED * _STRIDE + mesh
                    break
    if thing not in named:
        raise Error(
            "Object JSON: a track names something the document does not hold: "
            + property_path(target)
        )
    return named[thing] + property_path(target)


def _library(mut writer: JsonWriter, key: String, entries: List[String]) raises:
    """Write a library under `key`, or nothing when it is empty."""
    if len(entries) == 0:
        return
    writer.key(key)
    writer.begin_array()
    for entry in entries:  # pragma: no branch
        writer.raw(entry)
    writer.end_array()


def object_to_json(
    scene: Scene,
    assets: Assets,
    cameras: ObjectCameras = ObjectCameras(),
    animations: List[AnimationClip] = List[AnimationClip](),
) raises -> String:
    """Return a scene and what it draws with as a three.js JSON Object
    document, as `scene.toJSON()` returns it.

    Node `k` of the scene is written with the uuid `object_uuid(2, k)`, so
    `loaders.object_loader.ObjectModel.node` finds it again.

    Args:
        scene: The scene. It need not be current: nodes are written by
            their own transforms.
        assets: Where its geometries, materials and textures are.
        cameras: The cameras to write, each riding a node of the scene.
        animations: The clips to write as the scene's `animations`, as
            three.js writes a scene's. Each track is named by the uuid of
            the object its target is on, so `ObjectLoader` binds it below
            the scene. A material track is named on the first mesh that
            draws with the material.

    Returns:
        The document.

    Raises:
        Error: If a thing, a target, a bone or a camera names a node that
            is not in the scene, a store id names nothing, a light is
            refused by `Light.validate`, a texture is blank or refused by
            `Texture.validate`, a material is refused as the module
            docstring says or by its own checks of its open fields, a line
            material is not `BASIC`, a line's mode or a skinned mesh's bind
            mode is none of its named values, a batch's geometries cannot
            be joined, a camera has a view shift, a number is not
            finite, or a clip is refused by `animation_json.write_clip` or
            has a track on a thing the document does not hold.
    """
    var carried = _Carried(scene, cameras)
    var out = _Writer()
    var tree = JsonWriter()
    tree.begin_object()
    tree.key("uuid")
    tree.string(object_uuid(_SCENE_UUID, 0))
    tree.key("type")
    tree.string("Scene")
    tree.key("layers")
    tree.integer(1)
    tree.key("matrix")
    _matrix(tree, Matrix4())
    tree.key("up")
    _numbers(tree, [0, 1, 0])
    if scene.background.kind == COLOR_BACKGROUND:
        tree.key("background")
        tree.integer(scene.background.color.hex())
    elif scene.background.kind == TEXTURE_BACKGROUND:
        var uuid = out.library.texture(scene.background.texture, assets)
        tree.key("background")
        tree.string(uuid)
    elif scene.background.kind == CUBE_BACKGROUND:
        var uuid = out.library.cube(scene.background.cube, assets)
        tree.key("background")
        tree.string(uuid)
    # As `Scene.toJSON` writes them: the blur and the two intensities only
    # when they are not the default, the two rotations always.
    scene.validate_environment()
    if scene.background_blurriness > 0:
        tree.key("backgroundBlurriness")
        tree.number(scene.background_blurriness)
    if scene.background_intensity != 1:
        tree.key("backgroundIntensity")
        tree.number(scene.background_intensity)
    tree.key("backgroundRotation")
    _euler(tree, scene.background_rotation)
    if scene.environment_intensity != 1:
        tree.key("environmentIntensity")
        tree.number(scene.environment_intensity)
    tree.key("environmentRotation")
    _euler(tree, scene.environment_rotation)
    out.library.environment = scene.environment
    if scene.environment != NO_CUBE_TEXTURE:
        var uuid = out.library.cube(scene.environment, assets)
        if not assets.cube_textures.get(scene.environment).is_prefiltered():
            raise Error(
                "Object JSON: three.js's renderer prefilters the scene's"
                " environment; build it with pmrem_from_cube"
            )
        tree.key("environment")
        tree.string(uuid)
    ref fog = scene.fog
    if fog.kind == LINEAR_FOG:
        tree.key("fog")
        tree.begin_object()
        tree.key("type")
        tree.string("Fog")
        tree.key("name")
        tree.string("")
        tree.key("color")
        tree.integer(fog.color.hex())
        tree.key("near")
        tree.number(fog.near.to(METER))
        tree.key("far")
        tree.number(fog.far.to(METER))
        tree.end_object()
    elif fog.kind == EXP2_FOG:
        tree.key("fog")
        tree.begin_object()
        tree.key("type")
        tree.string("FogExp2")
        tree.key("name")
        tree.string("")
        tree.key("color")
        tree.integer(fog.color.hex())
        tree.key("density")
        tree.number(fog.density.to(PER_METER))
        tree.end_object()
    tree.key("children")
    tree.begin_array()
    for root in scene.children(NO_PARENT):
        out.node(tree, scene, root.value, carried, cameras, assets)
    for which in carried.loose:
        out.part(
            tree,
            _LIGHT * _STRIDE + which,
            scene.lights[which].layers,
            scene,
            cameras,
            assets,
        )
    tree.end_array()
    var clips = List[String]()
    if len(animations) > 0:
        tree.key("animations")
        tree.begin_array()
        for index in range(len(animations)):  # pragma: no branch
            ref clip = animations[index]
            var names = List[String]()
            for track in range(len(clip.tracks)):  # pragma: no branch
                names.append(
                    _track_name(clip.tracks[track].target, out.named, scene)
                )
            var entry = JsonWriter()
            var uuid = object_uuid(_CLIP_UUID, index)
            write_clip(entry, clip, names, uuid)
            clips.append(entry.finish())
            tree.string(uuid)
        tree.end_array()
    tree.end_object()
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("metadata")
    writer.begin_object()
    writer.key("version")
    writer.number(FORMAT_VERSION)
    writer.key("type")
    writer.string("Object")
    writer.key("generator")
    writer.string("Object3D.toJSON")
    writer.end_object()
    _library(writer, "geometries", out.library.geometries)
    _library(writer, "materials", out.library.materials)
    _library(writer, "textures", out.library.textures)
    _library(writer, "images", out.library.images)
    _library(writer, "skeletons", out.library.skeletons)
    _library(writer, "animations", clips)
    writer.key("object")
    writer.raw(tree.finish())
    writer.end_object()
    return writer.finish()


def write_object_json(
    path: String,
    scene: Scene,
    assets: Assets,
    cameras: ObjectCameras = ObjectCameras(),
    animations: List[AnimationClip] = List[AnimationClip](),
) raises:
    """Write a scene and its assets to a three.js JSON Object file.

    Args:
        path: The file, conventionally `.json`.
        scene: The scene.
        assets: Where its geometries, materials and textures are.
        cameras: The cameras to write; see `object_to_json`.
        animations: The clips to write; see `object_to_json`.

    Raises:
        Error: If the file cannot be written, or anything `object_to_json`
            raises.
    """
    Path(path).write_text(object_to_json(scene, assets, cameras, animations))
