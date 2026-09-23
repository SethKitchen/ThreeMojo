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

**Nodes.** Every node becomes an object with its name, its `visible`, its
`layers`, its `renderOrder` and its local `matrix`, as three.js writes an
`Object3D`. A node that carries one thing becomes that thing: a `Mesh`,
an `InstancedMesh`, a light of its kind or a camera. A node that carries
more than one, or a light or camera on other layers than its node, is an
`Object3D` with one child object per thing, each at the identity. A light
with no node, as an ambient light usually is, is a child of the scene.

**Geometry** is a `BufferGeometry` with every attribute as a
`Float32Array`, the index as a `Uint16Array` or a `Uint32Array` as three.js
chooses, the groups, and the morph targets. **A material** has the type
of its kind -- `MeshStandardMaterial` for `STANDARD` -- and the fields that
type has in three.js. **A texture** is its sampler's settings and an
image, written as a PNG `data:` URL of its full-size level. A texture here
runs up from its bottom row as a three.js texture with `flipY` does, so
the image is written as it is and `flipY` is true.

**Not written.** Lines, points, sprites, LODs, batched and skinned meshes;
cube textures, so a cube background, the scene's environment and a
material's `envMap`; a mesh's morph influences; a material's clipping
planes and the dash, point and sprite settings; and a texture's alpha
mode, which three.js has no field for: `loaders.object_loader` gives it
back from the texture's use. A material with custom blending, a material
that blends but is not transparent, a perspective camera with a view
shift and a camera that rides no node are refused, since the format has
no place for them.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import COLOR_BACKGROUND, TEXTURE_BACKGROUND
from core.buffer_attribute import BufferAttribute
from core.fog import EXP2_FOG, LINEAR_FOG
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.gltf import encode_base64
from exporters.json_writer import JsonWriter
from lights.light import (
    DIRECTIONAL,
    HEMISPHERE,
    POINT,
    RECT_AREA,
    SPOT,
    Light,
)
from loaders.object_loader import (
    CUSTOM_BLENDING,
    FORMAT_VERSION,
    LINEAR_FILTER,
    LINEAR_MIPMAP_LINEAR_FILTER,
    NEAREST_FILTER,
    NEAREST_MIPMAP_NEAREST_FILTER,
    NO_BLENDING,
    RGBA_FORMAT,
    SRGB_COLOR_SPACE,
    UNSIGNED_BYTE_TYPE,
    UV_MAPPING,
    ObjectCameras,
    light_type_names,
    material_type_names,
    wrap_code,
)
from materials.material import (
    BASIC,
    BLEND,
    DEPTH,
    LAMBERT,
    NORMALS,
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
from math.matrix4 import Matrix4
from render.framebuffer import Framebuffer
from render.png import encode as encode_png
from render.srgb import SRGB
from render.texture import NEAREST, Texture
from render.texture_store import TextureId
from std.pathlib import Path
from units.si import DEGREE, METER, PER_METER, RADIAN

# What the leading hex digit of a uuid says it names.
comptime _SCENE_UUID = 1
comptime _NODE_UUID = 2
comptime _PART_UUID = 3
comptime _GEOMETRY_UUID = 4
comptime _MATERIAL_UUID = 5
comptime _TEXTURE_UUID = 6
comptime _IMAGE_UUID = 7
# The largest vertex count whose index three.js writes as a `Uint16Array`.
comptime _MAX_SHORT_INDEX = 65535
comptime _HEX = "0123456789abcdef"


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
    """Write an attribute as three.js's `BufferAttribute.toJSON` does."""
    writer.begin_object()
    writer.key("itemSize")
    writer.integer(attribute.item_size)
    writer.key("type")
    writer.string("Float32Array")
    writer.key("array")
    _numbers(writer, attribute.data)
    writer.key("normalized")
    writer.boolean(False)
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
    return kind != NORMALS and kind != DEPTH


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
    var layers: Layers
    var matrix: Matrix4
    var auto: Bool

    def __init__(out self, uuid: String, node: Object3D) raises:
        """Start from a node: its name, visibility, layers and matrix."""
        self.uuid = uuid
        self.type = "Object3D"
        self.name = node.name
        self.cast_shadow = False
        self.receive_shadow = False
        self.visible = node.visible
        self.frustum_culled = True
        self.render_order = node.render_order
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
    var geometry_keys: List[Int]
    var materials: List[String]
    var material_keys: List[Int]
    var textures: List[String]
    var images: List[String]
    var texture_keys: List[Int]
    var parts: Int

    def __init__(out self):
        """Start with empty libraries."""
        self.geometries = List[String]()
        self.geometry_keys = List[Int]()
        self.materials = List[String]()
        self.material_keys = List[Int]()
        self.textures = List[String]()
        self.images = List[String]()
        self.texture_keys = List[Int]()
        self.parts = 0

    def part_uuid(mut self) -> String:
        """Return a uuid for the next part object."""
        self.parts += 1
        return object_uuid(_PART_UUID, self.parts - 1)

    def geometry(mut self, id: GeometryId, assets: Assets) raises -> String:
        """Write a geometry once, and return its uuid."""
        var at = _find(self.geometry_keys, id.value)
        if at < 0:
            at = len(self.geometry_keys)
            ref geometry = assets.geometries.get(id)
            var writer = JsonWriter()
            writer.begin_object()
            writer.key("uuid")
            writer.string(object_uuid(_GEOMETRY_UUID, at))
            writer.key("type")
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
            self.geometry_keys.append(id.value)
        return object_uuid(_GEOMETRY_UUID, at)

    def texture(mut self, id: TextureId, assets: Assets) raises -> String:
        """Write a texture and its image once, and return its uuid."""
        var at = _find(self.texture_keys, id.value)
        if at < 0:
            at = len(self.texture_keys)
            ref texture = assets.textures.get(id)
            if texture.width == 0:
                raise Error("Object JSON: a blank texture has no image")
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
            var nearest = texture.filter == NEAREST
            var magnify = NEAREST_FILTER if nearest else LINEAR_FILTER
            var minify = magnify
            if texture.levels > 1:
                minify = (
                    NEAREST_MIPMAP_NEAREST_FILTER if nearest else LINEAR_MIPMAP_LINEAR_FILTER
                )
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
            _numbers(writer, [texture.repeat.x, texture.repeat.y])
            writer.key("offset")
            _numbers(writer, [texture.offset.x, texture.offset.y])
            writer.key("center")
            _numbers(writer, [texture.center.x, texture.center.y])
            writer.key("rotation")
            writer.number(texture.rotation.to(RADIAN))
            writer.key("wrap")
            var wrap = wrap_code(texture.wrap)
            writer.begin_array()
            writer.integer(wrap)
            writer.integer(wrap)
            writer.end_array()
            writer.key("format")
            writer.integer(RGBA_FORMAT)
            writer.key("type")
            writer.integer(UNSIGNED_BYTE_TYPE)
            writer.key("colorSpace")
            writer.string(
                SRGB_COLOR_SPACE if texture.color_space == SRGB else ""
            )
            writer.key("minFilter")
            writer.integer(minify)
            writer.key("magFilter")
            writer.integer(magnify)
            writer.key("anisotropy")
            writer.integer(texture.anisotropy)
            writer.key("flipY")
            writer.boolean(True)
            writer.key("generateMipmaps")
            writer.boolean(texture.levels > 1)
            writer.end_object()
            self.textures.append(writer.finish())
            self.texture_keys.append(id.value)
        return object_uuid(_TEXTURE_UUID, at)

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

    def material(mut self, id: MaterialId, assets: Assets) raises -> String:
        """Write a material once, and return its uuid."""
        var at = _find(self.material_keys, id.value)
        if at >= 0:
            return object_uuid(_MATERIAL_UUID, at)
        at = len(self.material_keys)
        var material = assets.materials.get(id)
        var kind = material.kind
        if not kind.is_valid():
            raise Error("Object JSON: a material kind that is none of ten")
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
        writer.string(material_type_names()[kind.value])
        if _has_color(kind):
            writer.key("color")
            writer.integer(material.color.hex())
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
            writer.key("ior")
            writer.number(material.ior)
            writer.key("specularColor")
            writer.integer(material.specular_color.hex())
            writer.key("specularIntensity")
            writer.number(material.specular_intensity)
            writer.key("clearcoat")
            writer.number(material.clearcoat)
            writer.key("clearcoatRoughness")
            writer.number(material.clearcoat_roughness)
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
        if _reflects(kind):
            writer.key("reflectivity")
            writer.number(material.reflectivity)
            writer.key("combine")
            writer.integer(material.combine.value)
        self.map(writer, "map", material.map, assets)
        self.map(writer, "emissiveMap", material.emissive_map, assets)
        self.map(writer, "alphaMap", material.alpha_map, assets)
        self.map(writer, "gradientMap", material.gradient_map, assets)
        self.map(writer, "matcap", material.matcap, assets)
        if material.normal_map != NO_TEXTURE:
            self.map(writer, "normalMap", material.normal_map, assets)
            writer.key("normalScale")
            _numbers(writer, [material.normal_scale.x, material.normal_scale.y])
        if material.bump_map != NO_TEXTURE:
            self.map(writer, "bumpMap", material.bump_map, assets)
            writer.key("bumpScale")
            writer.number(material.bump_scale)
        if material.side.value != 0:
            writer.key("side")
            writer.integer(material.side.value)
        if material.opacity < 1:
            writer.key("opacity")
            writer.number(material.opacity)
        if transparent:
            writer.key("transparent")
            writer.boolean(True)
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
        writer.end_object()
        self.materials.append(writer.finish())
        self.material_keys.append(id.value)
        return object_uuid(_MATERIAL_UUID, at)


def _find(keys: List[Int], key: Int) -> Int:
    """Return where a key is in a list, or -1."""
    var found = -1
    for at in range(len(keys)):
        if keys[at] == key:
            found = at
    return found


struct _Carried(Movable):
    """What each node carries, by position in the scene's lists."""

    var meshes: List[List[Int]]
    var instanced: List[List[Int]]
    var lights: List[List[Int]]
    var perspective: List[List[Int]]
    var orthographic: List[List[Int]]
    # The lights that ride no node.
    var loose: List[Int]

    def __init__(out self, scene: Scene, cameras: ObjectCameras) raises:
        """Sort a scene's things onto its nodes."""
        var count = scene.count()
        self.meshes = List[List[Int]]()
        self.instanced = List[List[Int]]()
        self.lights = List[List[Int]]()
        self.perspective = List[List[Int]]()
        self.orthographic = List[List[Int]]()
        self.loose = List[Int]()
        for _ in range(count):
            self.meshes.append(List[Int]())
            self.instanced.append(List[Int]())
            self.lights.append(List[Int]())
            self.perspective.append(List[Int]())
            self.orthographic.append(List[Int]())
        for at in range(len(scene.meshes)):
            self.meshes[_node_of(scene.meshes[at].node, count)].append(at)
        for at in range(len(scene.instanced_meshes)):
            var node = scene.instanced_meshes[at].node
            self.instanced[_node_of(node, count)].append(at)
        for at in range(len(scene.lights)):
            var node = scene.lights[at].node
            if node == NO_PARENT:
                self.loose.append(at)
            else:
                self.lights[_node_of(node, count)].append(at)
        for at in range(len(cameras.perspective)):
            var node = cameras.perspective[at].node
            self.perspective[_node_of(node, count)].append(at)
        for at in range(len(cameras.orthographic)):
            var node = cameras.orthographic[at].node
            self.orthographic[_node_of(node, count)].append(at)

    def total(self, node: Int) -> Int:
        """Return how many things a node carries."""
        return (
            len(self.meshes[node])
            + len(self.instanced[node])
            + len(self.lights[node])
            + len(self.perspective[node])
            + len(self.orthographic[node])
        )


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

    def __init__(out self):
        """Start with empty libraries."""
        self.library = _Library()

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
        writer.string(self.library.material(mesh.material, assets))

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
        writer.string(self.library.material(mesh.material, assets))
        writer.key("count")
        writer.integer(mesh.count())
        var data = List[Float32]()
        for matrix in mesh.matrices:
            for index in range(16):  # pragma: no branch
                data.append(matrix.elements[index])
        writer.key("instanceMatrix")
        _attribute(writer, BufferAttribute(data^, 16))

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
        header.type = "PerspectiveCamera"
        header.write(writer)
        writer.key("fov")
        writer.number(camera.fov.to(DEGREE))
        writer.key("zoom")
        writer.integer(1)
        writer.key("near")
        writer.number(camera.near.to(METER))
        writer.key("far")
        writer.number(camera.far.to(METER))
        writer.key("focus")
        writer.integer(10)
        writer.key("aspect")
        writer.number(camera.aspect)
        writer.key("filmGauge")
        writer.integer(35)
        writer.key("filmOffset")
        writer.integer(0)

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
        # The one thing the node becomes, when it carries one thing and
        # that thing is on the node's layers.
        var mesh = -1
        var instanced = -1
        var light = -1
        var perspective = -1
        var orthographic = -1
        if carried.total(index) == 1:
            if len(carried.meshes[index]) == 1:
                mesh = carried.meshes[index][0]
            elif len(carried.instanced[index]) == 1:
                instanced = carried.instanced[index][0]
            elif len(carried.lights[index]) == 1:
                light = carried.lights[index][0]
                if scene.lights[light].layers != node.layers:
                    light = -1
            elif len(carried.perspective[index]) == 1:
                perspective = carried.perspective[index][0]
                if cameras.perspective[perspective].layers != node.layers:
                    perspective = -1
            else:
                orthographic = carried.orthographic[index][0]
                if cameras.orthographic[orthographic].layers != node.layers:
                    orthographic = -1
        writer.begin_object()
        if mesh >= 0:
            self.mesh(writer, header^, scene, mesh, assets)
        elif instanced >= 0:
            self.instanced(writer, header^, scene, instanced, assets)
        elif light >= 0:
            self.light(writer, header^, scene, light)
        elif perspective >= 0:
            self.perspective(writer, header^, cameras.perspective[perspective])
        elif orthographic >= 0:
            self.orthographic(
                writer, header^, cameras.orthographic[orthographic]
            )
        else:
            header.write(writer)
        var children = scene.children(NodeId(index))
        var parts = carried.total(index)
        if mesh >= 0 or instanced >= 0 or light >= 0:
            parts -= 1
        if perspective >= 0 or orthographic >= 0:
            parts -= 1
        if len(children) + parts > 0:
            writer.key("children")
            writer.begin_array()
            for child in children:
                self.node(writer, scene, child.value, carried, cameras, assets)
            for which in carried.meshes[index]:
                if which != mesh:
                    writer.begin_object()
                    self.mesh(
                        writer,
                        _Header(self.library.part_uuid(), node.layers),
                        scene,
                        which,
                        assets,
                    )
                    writer.end_object()
            for which in carried.instanced[index]:
                if which != instanced:
                    writer.begin_object()
                    self.instanced(
                        writer,
                        _Header(self.library.part_uuid(), node.layers),
                        scene,
                        which,
                        assets,
                    )
                    writer.end_object()
            for which in carried.lights[index]:
                if which != light:
                    self.part_light(writer, scene, which)
            for which in carried.perspective[index]:
                if which != perspective:
                    ref camera = cameras.perspective[which]
                    writer.begin_object()
                    self.perspective(
                        writer,
                        _Header(self.library.part_uuid(), camera.layers),
                        camera,
                    )
                    writer.end_object()
            for which in carried.orthographic[index]:
                if which != orthographic:
                    ref camera = cameras.orthographic[which]
                    writer.begin_object()
                    self.orthographic(
                        writer,
                        _Header(self.library.part_uuid(), camera.layers),
                        camera,
                    )
                    writer.end_object()
            writer.end_array()
        writer.end_object()

    def part_light(
        mut self, mut writer: JsonWriter, scene: Scene, which: Int
    ) raises:
        """Write a light as an object of its own, at the identity."""
        writer.begin_object()
        self.light(
            writer,
            _Header(self.library.part_uuid(), scene.lights[which].layers),
            scene,
            which,
        )
        writer.end_object()


def _shadow(mut writer: JsonWriter, light: Light) raises:
    """Write a directional, point or spot light's shadow, as
    `LightShadow.toJSON` writes it: a point light's camera is ninety
    degrees wide, as `PointLightShadow` builds it."""
    ref shadow = light.shadow
    writer.key("shadow")
    writer.begin_object()
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
        var extent = shadow.extent.to(METER)
        writer.key("type")
        writer.string("OrthographicCamera")
        writer.key("left")
        writer.number(-extent)
        writer.key("right")
        writer.number(extent)
        writer.key("top")
        writer.number(extent)
        writer.key("bottom")
        writer.number(-extent)
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
    scene: Scene, assets: Assets, cameras: ObjectCameras = ObjectCameras()
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

    Returns:
        The document.

    Raises:
        Error: If a mesh, light, target or camera names a node that is not
            in the scene, a store id names nothing, a light is refused by
            `Light.validate`, a texture is blank or refused by
            `Texture.validate`, a material is refused as the module
            docstring says, a camera has a view shift, or a number is not
            finite.
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
    for index in range(scene.count()):
        if scene.get(NodeId(index)).parent == NO_PARENT:
            out.node(tree, scene, index, carried, cameras, assets)
    for which in carried.loose:
        out.part_light(tree, scene, which)
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
    writer.key("object")
    writer.raw(tree.finish())
    writer.end_object()
    return writer.finish()


def write_object_json(
    path: String,
    scene: Scene,
    assets: Assets,
    cameras: ObjectCameras = ObjectCameras(),
) raises:
    """Write a scene and its assets to a three.js JSON Object file.

    Args:
        path: The file, conventionally `.json`.
        scene: The scene.
        assets: Where its geometries, materials and textures are.
        cameras: The cameras to write; see `object_to_json`.

    Raises:
        Error: If the file cannot be written, or anything `object_to_json`
            raises.
    """
    Path(path).write_text(object_to_json(scene, assets, cameras))
