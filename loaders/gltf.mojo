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
`position`, and `normal`, `uv`, `uv1` and `color` when it has them,
`TEXCOORD_1` becoming `uv1`, indexed when it is; a material becomes a `standard_material`, which is three.js's
`MeshStandardMaterial` and what `GLTFLoader` builds; a texture becomes a
`Texture` at its sampler's wrap and filters, read as sRGB for a base color
or an emissive map and as linear for a metallic-roughness, a normal or an
occlusion map;
a node becomes an `Object3D` at its translation, rotation and scale, or at
its matrix decomposed; each primitive on a node becomes a `Mesh`. A glTF
mesh of several primitives is a `Group` of meshes in three.js, and here
the node is that group: its meshes are not joined into one mesh that
wears a material list, as three.js does not join them. The
metallic-roughness texture is one image read twice, as glTF stores it and
as the standard material reads it: roughness from green, metalness from
blue.

**Occlusion.** A material's `occlusionTexture` becomes its `ao_map`, and
its `strength` the `ao_map_intensity`, as three.js reads them. Its red
channel dims the indirect light. An unlit material reads no occlusion,
as in three.js.

**Each map is placed on its own.** A `texCoord` of one gives the texture
the channel `UV_CHANNEL_1`, so the renderer samples it at `uv1`, and a
`KHR_texture_transform` gives it a transform of its own, whatever the
other maps of the material say, as three.js's `assignTexture` does.

**Texture coordinates run down in glTF.** `(0, 0)` is an image's top
left, where an image texture's `v` runs up from the bottom. three.js
answers with `flipY = false` on every glTF texture, and so does this: each
texture's `flip_y` is off, so `v` reads down from the first row, and the
geometry's coordinates and any `KHR_texture_transform` are kept as the file
has them.

**Samplers.** A texture takes its sampler's `wrapS` and `wrapT` and its
`magFilter` and `minFilter`, as three.js's `GLTFLoader` reads them; see
`GltfSampler`. A mipmap `minFilter` builds the chain.

**Skins, morph targets and animations.** A node with a `skin` draws each
primitive as a `SkinnedMesh`, its skeleton made of the joints' nodes and
the skin's inverse bind matrices, bound at the identity as three.js's
`GLTFLoader` binds it. `JOINTS_0` and `WEIGHTS_0` become `skinIndex` and
`skinWeight`, the weights normalized as three.js's `normalizeSkinWeights`
does. A primitive's `targets` become the geometry's morph targets, which
glTF holds as offsets, so `morph_relative` is set. A target's `COLOR_0`
becomes a color target, and the mesh's `extras.targetNames` name the
targets, which fills each mesh's `morph_target_dictionary`. `weights` on
the node, or on the mesh when the node has none, become the influences. Each
animation becomes an `AnimationClip`: a `translation`, `rotation` or
`scale` channel a track on the node, and a `weights` channel one
morph influence track per mesh and target. A `weights` channel drives
every mesh, plain or skinned, at its node and at every node below it that
has morph targets, as three.js's `GLTFLoader` traverses the node. `STEP` and `LINEAR` samplers
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
they were offsets. A target without a `COLOR_0` changes no color, where
three.js adds the base colors the same way. A channel on a node
the default scene does not reach is left out, and so is an animation left
with no channel. A skin joint the scene does not reach is refused. So is a specular
color factor outside zero to one, which a `Color` cannot hold; any map
that reads a third set of texture coordinates or past it, since a
geometry here has only `uv` and `uv1`; and a skinned node that is
instanced, where three.js drops the skin.

**Extras.** An object's `extras` become user data, as three.js's
`assignExtrasToUserData` makes them. A node's become its `user_data`,
after its `name`, which three.js also keeps as `userData.name`. A node
whose mesh has one primitive, and that has no camera and no light and is
not a joint, takes the mesh's `extras` first, since three.js's node is
that mesh. A primitive's `extras` become its geometry's `user_data`, as
three.js's `geometry.userData`. A `Mesh`, a `Material` and a `Scene` here
hold no user data,
so `GltfModel.mesh_extras`, `material_extras` and `scene_extras` hold
theirs. `extras` that are not an object are skipped, as three.js skips
them.

**Points and lines.** A primitive of points or of lines becomes a
`Points` or a `Line`, as three.js's `GLTFLoader.loadMesh` builds them,
with a `BASIC` material made from the file's: see `unlit_material`. An
index here holds triangles, so an indexed one is read out in index
order. A mesh's `extras.targetNames` name its morph targets, the
geometry's `morph_names`.

**Extensions.** Eighteen are read, the ones three.js's `GLTFLoader` reads
that map onto something this renderer has. `KHR_materials_unlit` makes a
`BASIC` material. `KHR_materials_ior`, `KHR_materials_specular` and
`KHR_materials_clearcoat` make a `PHYSICAL` one and set its factors and
maps: the specular texture's alpha, the specular color texture, and the
clear coat's red, roughness green and normal textures. A clear coat of
zero leaves its maps out, since three.js draws none of them then.
`KHR_materials_emissive_strength` sets `emissive_intensity`.
`KHR_materials_transmission`, `KHR_materials_volume` and
`KHR_materials_dispersion` make a `PHYSICAL` one that transmits, with the
transmission and thickness textures read as data.
`KHR_materials_sheen`, `KHR_materials_iridescence` and
`KHR_materials_anisotropy` make a `PHYSICAL` one and set its sheen, its
thin film and its stretched lobe, maps included, as three.js's plugins
set them. A film or a stretch of zero leaves its maps out, since three.js
draws none of them then.
`KHR_texture_transform` moves, turns and scales a map's coordinates.
`KHR_lights_punctual` adds directional, point and spot lights to the scene.
`EXT_mesh_gpu_instancing` draws a node's primitives as `InstancedMesh`es.
`KHR_mesh_quantization` needs nothing: every attribute is read at any
component type already.
`KHR_draco_mesh_compression` decodes a primitive's Draco data with
`loaders.draco`, as three.js's `DRACOLoader` decodes it: each attribute
the extension names is read from the Draco data at its accessor's
component type, normalized as the accessor says, and the triangles come
from the Draco data too. An attribute the extension does not name is read
from its accessor. Draco would round a float attribute read at an
integer type; a file that asks for that is not valid glTF, and it is
refused.
`EXT_materials_bump` makes a `PHYSICAL` one with a bump map, as three.js
reads it. `KHR_texture_basisu` reads the KTX 2.0 image it names through
`render.ktx2`; see `ktx2_texture`. `EXT_texture_webp` is not read: a
WebP image is not decoded, so a texture reads its fallback `source`, and
a file that requires the extension is refused.

**Not ported.** Every other extension: a file whose `extensionsRequired`
names one is refused, as three.js refuses it, and one that only uses an
extension is read without it. A primitive of triangle strips or fans is
refused, and so is a point or a line on a skinned or an instanced node.
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
    SkinnedMeshIndex,
    TrackKind,
    TrackTarget,
    morph_target,
    node_target,
    skinned_morph_target,
    POSITION as TRANSLATION,
)
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from math.utils import (
    ComponentType,
    INT16_COMPONENT,
    INT8_COMPONENT,
    UINT16_COMPONENT,
    UINT32_COMPONENT,
    UINT8_COMPONENT,
)
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    UV1,
    BufferGeometry,
)
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from core.user_data import UserData, user_data_of
from lights.light import directional_light, point_light, spot_light
from loaders.draco import (
    DRACO_TRIANGULAR_MESH,
    DracoGeometry,
    decode_draco,
)
from loaders.draco_attributes import DracoDataType
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
    BASIC,
    DEFAULT_IOR,
    DEFAULT_IRIDESCENCE_IOR,
    DEFAULT_THICKNESS_MAXIMUM,
    DEFAULT_THICKNESS_MINIMUM,
    DOUBLE_SIDE,
    FRONT_SIDE,
    NO_TEXTURE,
    PHYSICAL,
    STANDARD,
    Material,
    MaterialId,
    Side,
    points_material,
    standard_material,
)
from math.matrix4 import Matrix4
from objects.skeleton import Bone, Skeleton
from objects.instanced_mesh import InstancedMesh
from objects.skinned_mesh import (
    SKIN_INDEX,
    SKIN_WEIGHT,
    SkinnedMesh,
    normalized_skin_weights,
)
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.line import LOOP, SEGMENTS, STRIP, Line, LineMode
from objects.points import Points
from render.framebuffer import Color, FloatColor
from render.jpeg import decode as decode_jpeg
from render.png import DecodedImage, decode as decode_png
from render.srgb import LINEAR, SRGB, ColorSpace
from render.tga import decode as decode_tga
from render import ktx2
from render.texture import (
    Alpha,
    BILINEAR,
    CLAMP,
    COVERAGE,
    IGNORED,
    MIRROR,
    NEAREST,
    REPEAT,
    LINEAR_MIPMAP_LINEAR,
    LINEAR_MIPMAP_NEAREST,
    NEAREST_MIPMAP_LINEAR,
    NEAREST_MIPMAP_NEAREST,
    UV_CHANNEL_1,
    Filter,
    Texture,
    Wrap,
    texture_from,
)
from render.texture_store import TextureId
from std.math import inf, isfinite, pi, sqrt
from std.memory import bitcast
from std.pathlib import Path
from units.si import Angle, Duration, Length, METER, NANOMETER, RADIAN, SECOND

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

# The primitive modes that are read: points, the three kinds of line, and
# triangles. glTF names them by their GL constants.
comptime MODE_POINTS = 0
comptime MODE_LINES = 1
comptime MODE_LINE_LOOP = 2
comptime MODE_LINE_STRIP = 3
comptime MODE_TRIANGLES = 4

# The sampler's wrap and filter constants.
comptime WRAP_REPEAT = 10497
comptime WRAP_CLAMP = 33071
comptime WRAP_MIRROR = 33648
comptime FILTER_NEAREST = 9728
comptime FILTER_LINEAR = 9729
# The four minification filters that read a mipmap chain.
comptime FILTER_NEAREST_MIPMAP_NEAREST = 9984
comptime FILTER_LINEAR_MIPMAP_NEAREST = 9985
comptime FILTER_NEAREST_MIPMAP_LINEAR = 9986
comptime FILTER_LINEAR_MIPMAP_LINEAR = 9987


@fieldwise_init
struct GltfSampler(ImplicitlyCopyable):
    """A glTF sampler as a texture reads it: its two wraps and its two
    filters, three.js's `wrapS`, `wrapT`, `magFilter` and `minFilter`.

    What `read_gltf` gives every texture of the sampler, and what the
    exporter writes one from.
    """

    var wrap_s: Wrap
    var wrap_t: Wrap
    var mag_filter: Filter
    var min_filter: Filter

    def __init__(out self):
        """Create glTF's sampler when a texture names none: repeated both
        ways, linear, and trilinear down a chain, as three.js reads it."""
        self.wrap_s = REPEAT
        self.wrap_t = REPEAT
        self.mag_filter = BILINEAR
        self.min_filter = LINEAR_MIPMAP_LINEAR


def gl_filter(filter: Filter) -> Int:
    """Return a filter as glTF's GL constant.

    Args:
        filter: Any of the six named filters.

    Returns:
        The constant: `FILTER_NEAREST` for `NEAREST`, and so on.
    """
    if filter == NEAREST:
        return FILTER_NEAREST
    if filter == BILINEAR:
        return FILTER_LINEAR
    if filter == NEAREST_MIPMAP_NEAREST:
        return FILTER_NEAREST_MIPMAP_NEAREST
    if filter == LINEAR_MIPMAP_NEAREST:
        return FILTER_LINEAR_MIPMAP_NEAREST
    if filter == NEAREST_MIPMAP_LINEAR:
        return FILTER_NEAREST_MIPMAP_LINEAR
    return FILTER_LINEAR_MIPMAP_LINEAR


def filter_of_gl(code: Int) raises -> Filter:
    """Return a glTF filter constant as a filter.

    Args:
        code: One of glTF's six filter constants.

    Returns:
        The filter.

    Raises:
        Error: If the constant is none of the six.
    """
    if code == FILTER_NEAREST:
        return NEAREST
    if code == FILTER_LINEAR:
        return BILINEAR
    if code == FILTER_NEAREST_MIPMAP_NEAREST:
        return NEAREST_MIPMAP_NEAREST
    if code == FILTER_LINEAR_MIPMAP_NEAREST:
        return LINEAR_MIPMAP_NEAREST
    if code == FILTER_NEAREST_MIPMAP_LINEAR:
        return NEAREST_MIPMAP_LINEAR
    if code == FILTER_LINEAR_MIPMAP_LINEAR:
        return LINEAR_MIPMAP_LINEAR
    raise Error("glTF: a filter that is not known")


# What a material's `alphaCutoff` is when `MASK` names none.
comptime DEFAULT_ALPHA_CUTOFF = Float32(0.5)

# What three.js's `GLTFLoader` gives a perspective camera that names no
# aspect ratio, and where it ends one that names no far plane: glTF's
# infinite projection, which a `PerspectiveCamera` cannot hold.
comptime DEFAULT_ASPECT = Float32(1)
comptime DEFAULT_FAR = Float32(2e6)

# The extensions this loader reads. A file that requires any other is
# refused, as three.js's `GLTFLoader` refuses one it has no plugin for.
comptime EMISSIVE_STRENGTH = "KHR_materials_emissive_strength"
comptime MATERIALS_IOR = "KHR_materials_ior"
comptime MATERIALS_SPECULAR = "KHR_materials_specular"
comptime MATERIALS_CLEARCOAT = "KHR_materials_clearcoat"
comptime MATERIALS_SHEEN = "KHR_materials_sheen"
comptime MATERIALS_IRIDESCENCE = "KHR_materials_iridescence"
comptime MATERIALS_ANISOTROPY = "KHR_materials_anisotropy"
comptime MATERIALS_UNLIT = "KHR_materials_unlit"
comptime MATERIALS_TRANSMISSION = "KHR_materials_transmission"
comptime MATERIALS_VOLUME = "KHR_materials_volume"
comptime MATERIALS_DISPERSION = "KHR_materials_dispersion"
comptime TEXTURE_TRANSFORM = "KHR_texture_transform"
comptime LIGHTS_PUNCTUAL = "KHR_lights_punctual"
comptime MESH_QUANTIZATION = "KHR_mesh_quantization"
comptime GPU_INSTANCING = "EXT_mesh_gpu_instancing"
comptime DRACO_MESH_COMPRESSION = "KHR_draco_mesh_compression"
comptime MATERIALS_BUMP = "EXT_materials_bump"
comptime TEXTURE_BASISU = "KHR_texture_basisu"
# WebP images, which this port does not decode. A texture that names a
# WebP image reads its fallback `source`, and a file that requires the
# extension is refused.
comptime TEXTURE_WEBP = "EXT_texture_webp"

# A spot light's cone when `KHR_lights_punctual` names none: no inner cone,
# and an outer one of a quarter of a half turn, the specification's.
comptime DEFAULT_OUTER_CONE = Float32(pi / 4)


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
    # The same for the instanced meshes `EXT_mesh_gpu_instancing` added to
    # `scene.instanced_meshes`.
    var first_instanced_mesh: Int
    var instanced_mesh_count: Int
    # The same for the lines and the points that primitives of lines and
    # of points added to `scene.lines` and `scene.points`.
    var first_line: Int
    var line_count: Int
    var first_points: Int
    var points_count: Int
    # The same for the lights `KHR_lights_punctual` added to
    # `scene.lights`, one per node that carries a light.
    var first_light: Int
    var light_count: Int
    # One entry per node that carries a camera and that the loaded scene
    # reaches, in the order the nodes were placed.
    var cameras: List[GltfCamera]
    # One clip per glTF animation that drives something the loaded scene
    # reaches, in the file's order.
    var animations: List[AnimationClip]
    # Each glTF mesh's `extras`, three.js's `mesh.userData`, or empty.
    var mesh_extras: List[UserData]
    # Each glTF material's `extras`, three.js's `material.userData`, or
    # empty. A `Material` here holds no user data; see `read_gltf`.
    var material_extras: List[UserData]
    # The loaded scene's `extras`, three.js's `scene.userData`, or empty.
    var scene_extras: UserData

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
        self.first_instanced_mesh = 0
        self.instanced_mesh_count = 0
        self.first_line = 0
        self.line_count = 0
        self.first_points = 0
        self.points_count = 0
        self.first_light = 0
        self.light_count = 0
        self.cameras = List[GltfCamera]()
        self.animations = List[AnimationClip]()
        self.mesh_extras = List[UserData]()
        self.material_extras = List[UserData]()
        self.scene_extras = UserData()

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
        Error: If the JSON is not JSON or not glTF 2, an extension this
            loader does not read is required, a buffer, accessor, image, material, mesh, node,
            skin, camera or animation is malformed or names something the
            file does not have, a primitive is a strip or a fan of
            triangles, a skin names a joint the scene does not reach, or a
            camera, a skeleton, a morph target or a track is one its type
            refuses. Also if an extension is malformed, a material's
            texture transforms differ, a specular color factor is outside
            zero to one, a skinned node is instanced, a point or a line is
            on a skinned or an instanced node, `targetNames` do not name
            each target, a texture names no image or only a WebP one, a
            KTX 2.0 image is refused by `render.ktx2`, or a material, a
            light or an instance matrix is one its type refuses.
    """
    var document = parse_json(text)
    var root = document.root()
    if document.kind(root) != OBJECT:
        raise Error("glTF: the document is not an object")
    _check_asset(document, root)
    var required = document.get(root, "extensionsRequired")
    if required != NO_NODE:
        for slot in range(document.length(required)):
            var name = document.string(document.at(required, slot))
            if name == TEXTURE_WEBP:
                raise Error(
                    "glTF: the file requires EXT_texture_webp, and WebP"
                    " images are not decoded: give each texture a PNG or"
                    " JPEG source as well"
                )
            if not is_supported_extension(name):
                raise Error(
                    "glTF: the file requires an extension that is not read: "
                    + name
                )
    var loader = _Loader(document^, bin, directory)
    loader.read_buffers()
    loader.read_textures()
    loader.read_materials(assets)
    loader.read_meshes(assets)
    loader.read_nodes(scene, assets)
    loader.read_animations()
    return loader.model.copy()


def is_supported_extension(name: String) -> Bool:
    """Return True if this loader reads an extension, so a file can
    require it.

    Args:
        name: The extension's name, as `extensionsRequired` lists it.

    Returns:
        Whether it is one of the eighteen this loader reads.
    """
    return (
        name == EMISSIVE_STRENGTH
        or name == MATERIALS_BUMP
        or name == TEXTURE_BASISU
        or name == MATERIALS_IOR
        or name == MATERIALS_SPECULAR
        or name == MATERIALS_CLEARCOAT
        or name == MATERIALS_SHEEN
        or name == MATERIALS_IRIDESCENCE
        or name == MATERIALS_ANISOTROPY
        or name == MATERIALS_UNLIT
        or name == MATERIALS_TRANSMISSION
        or name == MATERIALS_VOLUME
        or name == MATERIALS_DISPERSION
        or name == TEXTURE_TRANSFORM
        or name == LIGHTS_PUNCTUAL
        or name == MESH_QUANTIZATION
        or name == GPU_INSTANCING
        or name == DRACO_MESH_COMPRESSION
    )


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


struct _DracoPrimitive(Movable):
    """A primitive's decoded `KHR_draco_mesh_compression` data, and the
    Draco unique id of each glTF attribute it holds."""

    var geometry: DracoGeometry
    var names: List[String]
    var ids: List[Int]

    def __init__(
        out self,
        var geometry: DracoGeometry,
        var names: List[String],
        var ids: List[Int],
    ):
        self.geometry = geometry^
        self.names = names^
        self.ids = ids^


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
    var texture_samplers: List[GltfSampler]
    # Each glTF texture read linear with its alpha kept, as a sheen
    # roughness texture is, or `NO_TEXTURE` until one asks for it.
    var alpha_textures: List[TextureId]
    # How many morph targets each glTF mesh's primitives carry.
    var morph_counts: List[Int]
    # Each primitive's mode, mesh by mesh, as `model.geometries` lists them.
    var primitive_modes: List[Int]
    # Per glTF node, the indices in `scene.meshes` of the meshes drawn at
    # it, which a `weights` channel drives.
    var node_meshes: List[List[Int]]
    # Per glTF node, the indices in `scene.skinned_meshes` of the skinned
    # meshes drawn at it, which a `weights` channel drives too.
    var node_skins: List[List[Int]]
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
        self.texture_samplers = List[GltfSampler]()
        self.alpha_textures = List[TextureId]()
        self.morph_counts = List[Int]()
        self.primitive_modes = List[Int]()
        self.node_meshes = List[List[Int]]()
        self.node_skins = List[List[Int]]()
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

    def extras(self, node: Int) raises -> UserData:
        """Return an object's `extras` as user data, three.js's
        `assignExtrasToUserData`: empty when there are none, and when they
        are not an object, which three.js ignores."""
        var found = self.document.get(node, "extras")
        if found == NO_NODE or self.document.kind(found) != OBJECT:
            return UserData()
        return user_data_of(self.document, found)

    def is_joint(self, index: Int) raises -> Bool:
        """Return True if a skin names a node as a joint, which three.js's
        `GLTFLoader` makes a `Bone` rather than the node's mesh."""
        for skin in range(self.count("skins")):
            var joints = self.array_of(self.entry("skins", skin), "joints")
            for slot in range(self.document.length(joints)):
                if self.document.integer(self.document.at(joints, slot)) == (
                    index
                ):
                    return True
        return False

    def flag(self, node: Int, key: String) raises -> Bool:
        """Return an object's boolean under `key`, or False."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return False
        return self.document.boolean(found)

    def extension(self, node: Int, name: String) raises -> Int:
        """Return the object an extension keeps under an object's
        `extensions`, or `NO_NODE` when it keeps none there."""
        var all = self.document.get(node, "extensions")
        if all == NO_NODE:
            return NO_NODE
        if self.document.kind(all) != OBJECT:
            raise Error("glTF: extensions must be an object")
        var found = self.document.get(all, name)
        if found != NO_NODE and self.document.kind(found) != OBJECT:
            raise Error("glTF: " + name + " must be an object")
        return found

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
        mut self, index: Int, raw: Bool = False
    ) raises -> Tuple[List[Float32], Int]:
        """Return an accessor's numbers as floats, normalized when it says
        so and `raw` is not set, and how many make one element, with its
        sparse values put in place."""
        var accessor = self.entry("accessors", index)
        var component = self.required_integer(accessor, "componentType")
        var count = self.required_integer(accessor, "count")
        var kind = self.text(accessor, "type")
        var width = _components_of(kind)
        var size = _component_size(component)
        var normalized = self.flag(accessor, "normalized") and not raw
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
            var image = self.image_of(texture)
            if image < 0 or image >= self.count("images"):
                raise Error("glTF: a texture names an image that is not there")
            # glTF's defaults, three.js's `GLTFLoader` reads them: repeat
            # both ways, linear, and trilinear down a chain.
            var sampling = GltfSampler()
            var sampler_index = self.integer(texture, "sampler", -1)
            if sampler_index >= 0:
                var sampler = self.entry("samplers", sampler_index)
                sampling.wrap_s = _wrap_of(
                    self.integer(sampler, "wrapS", WRAP_REPEAT)
                )
                sampling.wrap_t = _wrap_of(
                    self.integer(sampler, "wrapT", WRAP_REPEAT)
                )
                sampling.mag_filter = filter_of_gl(
                    self.integer(sampler, "magFilter", FILTER_LINEAR)
                )
                if not sampling.mag_filter.magnifies():
                    raise Error("glTF: a magFilter must be NEAREST or LINEAR")
                sampling.min_filter = filter_of_gl(
                    self.integer(
                        sampler, "minFilter", FILTER_LINEAR_MIPMAP_LINEAR
                    )
                )
            self.texture_images.append(image)
            self.texture_samplers.append(sampling)
            self.alpha_textures.append(NO_TEXTURE)
            self.model.color_textures.append(NO_TEXTURE)
            self.model.data_textures.append(NO_TEXTURE)

    def image_of(self, texture: Int) raises -> Int:
        """Return the image a texture reads: its `KHR_texture_basisu`
        source when it has one, as three.js's plugin reads it first, and
        its own `source` otherwise. A texture that names only a WebP image
        is refused: see `TEXTURE_WEBP`."""
        var basis = self.extension(texture, TEXTURE_BASISU)
        if basis != NO_NODE:
            return self.required_integer(basis, "source")
        if self.document.has(texture, "source"):
            return self.required_integer(texture, "source")
        if self.extension(texture, TEXTURE_WEBP) != NO_NODE:
            raise Error(
                "glTF: a texture names only a WebP image, and WebP images"
                " are not decoded"
            )
        raise Error("glTF: source is required")

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
        mut self,
        index: Int,
        space: ColorSpace,
        mut assets: Assets,
        keep_alpha: Bool = False,
    ) raises -> TextureId:
        """Return a glTF texture as read in one color space, decoding its
        image the first time that space asks for it. `keep_alpha` reads a
        linear texture's alpha as a number, as a sheen roughness texture
        holds one, rather than ignoring it."""
        # Never negative: `texture_reference` refused that already.
        if index >= len(self.texture_images):
            raise Error("glTF: a material names a texture that is not there")
        if keep_alpha and self.alpha_textures[index] != NO_TEXTURE:
            return self.alpha_textures[index]
        if (
            not keep_alpha
            and space == SRGB
            and self.model.color_textures[index] != NO_TEXTURE
        ):
            return self.model.color_textures[index]
        if (
            not keep_alpha
            and space == LINEAR
            and self.model.data_textures[index] != NO_TEXTURE
        ):
            return self.model.data_textures[index]
        var bytes = self.image_bytes(self.texture_images[index])
        # A linear texture holds numbers -- metalness and roughness, a
        # normal, occlusion -- and its alpha is not coverage: the renderer
        # refuses a data map that reads alpha as coverage, so one built
        # with the default could not be drawn.
        ref sampling = self.texture_samplers[index]
        var alpha = IGNORED if space == LINEAR and not keep_alpha else COVERAGE
        var built: Texture
        if is_ktx2(bytes):
            built = ktx2_texture(bytes, sampling, space, alpha)
        else:
            built = texture_from(
                decode_image(bytes),
                sampling.wrap_s,
                sampling.mag_filter,
                space,
                sampling.min_filter.is_mipmap(),
                alpha=alpha,
            )
        built.wrap_t = sampling.wrap_t
        built.min_filter = sampling.min_filter
        # glTF's `v` runs down from the top, as the image's rows do: three.js
        # reads it with `flipY = false`, and so does this.
        built.flip_y = False
        var id = assets.textures.add(built^)
        if keep_alpha:
            self.alpha_textures[index] = id
        elif space == SRGB:
            self.model.color_textures[index] = id
        else:
            self.model.data_textures[index] = id
        return id

    def texture_set(self, found: Int) raises -> Int:
        """Return the set of texture coordinates a texture reference reads:
        its `texCoord`, or its `KHR_texture_transform`'s when that names
        one, as three.js lets the transform's win.

        Args:
            found: The texture reference object.

        Returns:
            The set: zero for `TEXCOORD_0`, one for `TEXCOORD_1`.

        Raises:
            Error: If a `texCoord` is not a whole number.
        """
        var set = self.integer(found, "texCoord", 0)
        var transform = self.extension(found, TEXTURE_TRANSFORM)
        if transform != NO_NODE:
            set = self.integer(transform, "texCoord", set)
        return set

    def texture_reference(self, material: Int, key: String) raises -> Int:
        """Return the texture index a material's `key` object names, or -1.

        The texture coordinates it reads must be the first set or the
        second, `uv` or `uv1`: a geometry here has no third. See
        `texture_set`.
        """
        var found = self.document.get(material, key)
        if found == NO_NODE:
            return -1
        if self.document.kind(found) != OBJECT:
            raise Error("glTF: " + key + " must be an object")
        var set = self.texture_set(found)
        if set < 0 or set > 1:
            raise Error(
                "glTF: a texture reads only the first two sets of texture"
                " coordinates"
            )
        var index = self.required_integer(found, "index")
        if index < 0:
            raise Error("glTF: a texture index must not be negative")
        return index

    def map_of(
        mut self,
        material: Int,
        key: String,
        space: ColorSpace,
        mut assets: Assets,
        keep_alpha: Bool = False,
    ) raises -> TextureId:
        """Return the texture a material's `key` object names, read in one
        color space, or `NO_TEXTURE`. `keep_alpha` is `texture`'s.

        A `KHR_texture_transform` that moves, turns or scales it makes a
        copy of the texture, as three.js's `GLTFTextureTransformExtension`
        clones it. The copy's transform is the file's, as three.js's
        `offset`, `repeat` and `rotation`: every glTF texture has
        `flip_y` off, so glTF's coordinates need no flip. A reference that
        reads the second set of coordinates makes a copy whose `channel`
        is `UV_CHANNEL_1`, as three.js's `assignTexture` clones one. Each
        map keeps its own transform and channel, as in three.js.
        """
        var index = self.texture_reference(material, key)
        if index < 0:
            return NO_TEXTURE
        var id = self.texture(index, space, assets, keep_alpha)
        var found = self.document.get(material, key)
        if self.texture_set(found) == 1:
            var second = Texture(copy=assets.textures.get(id))
            second.channel = UV_CHANNEL_1
            id = assets.textures.add(second^)
        var transform = self.extension(found, TEXTURE_TRANSFORM)
        if transform == NO_NODE:
            return id
        var offset = self.numbers(transform, "offset", 2)
        var scale = self.numbers(transform, "scale", 2)
        var turned = self.document.has(transform, "rotation")
        if len(offset) == 0 and len(scale) == 0 and not turned:
            # Only a `texCoord`, which the channel above settled.
            return id
        if len(offset) == 0:
            offset = [0, 0]
        if len(scale) == 0:
            scale = [1, 1]
        var moved = Texture(copy=assets.textures.get(id))
        moved.offset = Vector2(offset[0], offset[1])
        moved.repeat = Vector2(scale[0], scale[1])
        moved.rotation = Angle(self.number(transform, "rotation", 0), RADIAN)
        return assets.textures.add(moved^)

    def data_map_of(
        mut self, owner: Int, key: String, mut assets: Assets
    ) raises -> TextureId:
        """Return the texture an object's `key` names, read as data: linear,
        and with its alpha ignored, as the renderer reads a map that holds
        numbers. Or `NO_TEXTURE` when there is none.

        Args:
            owner: The object that holds the texture reference.
            key: The reference's name.
            assets: Where the texture is added.

        Returns:
            The texture's id.

        Raises:
            Error: Everything `map_of` raises.
        """
        var id = self.map_of(owner, key, LINEAR, assets)
        if id == NO_TEXTURE:
            return id
        return assets.textures.add(assets.textures.get(id).ignoring_alpha())

    def occlusion_of(
        mut self, material: Int, mut assets: Assets
    ) raises -> Tuple[TextureId, Float32]:
        """Return a material's `occlusionTexture` as an ao map and its
        intensity, as three.js's `GLTFLoader` reads it: the texture as
        data and `strength` as `aoMapIntensity`. Its channel is what
        `map_of` gives every map.

        Args:
            material: The glTF material object.
            assets: Where the texture is added.

        Returns:
            The texture's id and the intensity: `NO_TEXTURE` and one for
            a material with no occlusion texture.

        Raises:
            Error: Everything `map_of` raises.
        """
        var id = self.map_of(material, "occlusionTexture", LINEAR, assets)
        if id == NO_TEXTURE:
            return (id, Float32(1))
        var found = self.document.get(material, "occlusionTexture")
        return (id, self.number(found, "strength", 1))

    # --- materials ----------------------------------------------------------

    def read_materials(mut self, mut assets: Assets) raises:
        """Build a material per glTF material, of the kind three.js's
        `GLTFLoader` picks: `BASIC` for one that is unlit, `PHYSICAL` for
        one with an index of refraction, a specular or a clear coat, and
        `STANDARD` for the rest."""
        for index in range(self.count("materials")):
            var material = self.entry("materials", index)
            var color = Color(255, 255, 255)
            var opacity = Float32(1)
            var map = NO_TEXTURE
            var pbr = self.document.get(material, "pbrMetallicRoughness")
            if pbr != NO_NODE:
                var factor = self.numbers(pbr, "baseColorFactor", 4)
                if len(factor) == 4:
                    color = FloatColor(
                        factor[0], factor[1], factor[2], 1
                    ).encode()
                    opacity = factor[3]
                map = self.map_of(pbr, "baseColorTexture", SRGB, assets)
            var side = FRONT_SIDE
            if self.flag(material, "doubleSided"):
                side = DOUBLE_SIDE
            var mode = self.text(material, "alphaMode")
            var transparent = mode == "BLEND"
            var built: Material
            if self.extension(material, MATERIALS_UNLIT) != NO_NODE:
                # three.js's `MeshBasicMaterial`: the base color alone,
                # with no emissive, normal or metallic-roughness term and
                # no other material extension read.
                built = Material(
                    color,
                    map=map,
                    side=side,
                    opacity=opacity,
                    transparent=transparent,
                    kind=BASIC,
                )
            else:
                built = self.lit_material(
                    material,
                    pbr,
                    color,
                    map,
                    side,
                    opacity,
                    transparent,
                    assets,
                )
            if mode == "MASK":
                built.alpha_test = self.number(
                    material, "alphaCutoff", DEFAULT_ALPHA_CUTOFF
                )
            elif mode != "" and mode != "OPAQUE" and mode != "BLEND":
                raise Error("glTF: alphaMode must be OPAQUE, MASK or BLEND")
            self.model.materials.append(assets.materials.add(built))
            self.model.material_extras.append(self.extras(material))
            self.tinted_materials.append(MaterialId(0))
            self.has_tinted.append(False)

    def lit_material(
        mut self,
        material: Int,
        pbr: Int,
        color: Color,
        map: TextureId,
        side: Side,
        opacity: Float32,
        transparent: Bool,
        mut assets: Assets,
    ) raises -> Material:
        """Build a material that is not unlit: `STANDARD`, or `PHYSICAL`
        when `KHR_materials_ior`, `KHR_materials_specular`,
        `KHR_materials_clearcoat`, `KHR_materials_transmission`,
        `KHR_materials_volume`, `KHR_materials_dispersion`,
        `KHR_materials_sheen`, `KHR_materials_iridescence` or
        `KHR_materials_anisotropy` is on it, with the emissive scaled by
        `KHR_materials_emissive_strength` and the occlusion texture read as
        its ao map; see `occlusion_of`.

        The volume is three.js's reading of it: a thickness of zero and an
        infinite attenuation distance unless the file says otherwise, and
        an attenuation distance of zero read as infinite, as three.js's
        `|| Infinity` reads it."""
        var roughness = Float32(1)
        var metalness = Float32(1)
        var roughness_map = NO_TEXTURE
        if pbr != NO_NODE:
            roughness = self.number(pbr, "roughnessFactor", 1)
            metalness = self.number(pbr, "metallicFactor", 1)
            roughness_map = self.map_of(
                pbr, "metallicRoughnessTexture", LINEAR, assets
            )
        var normal_map = self.map_of(material, "normalTexture", LINEAR, assets)
        var normal_scale = Float32(1)
        if normal_map != NO_TEXTURE:
            normal_scale = self.number(
                self.document.get(material, "normalTexture"), "scale", 1
            )
        var occlusion = self.occlusion_of(material, assets)
        var emissive = Color(0, 0, 0)
        var glow = self.numbers(material, "emissiveFactor", 3)
        if len(glow) == 3:
            emissive = FloatColor(glow[0], glow[1], glow[2], 1).encode()
        var emissive_map = self.map_of(
            material, "emissiveTexture", SRGB, assets
        )
        var strength = Float32(1)
        var bright = self.extension(material, EMISSIVE_STRENGTH)
        if bright != NO_NODE:
            strength = self.number(bright, "emissiveStrength", 1)
        var kind = STANDARD
        # three.js's `GLTFMaterialsBumpExtension`: a physical material with
        # a height map read as data. three.js draws the normal map of a
        # material that has both and ignores the bump map, and a material
        # here holds one or the other; a bump factor with no map draws
        # nothing.
        var bump_map = NO_TEXTURE
        var bump_scale = Float32(1)
        var bump = self.extension(material, MATERIALS_BUMP)
        if bump != NO_NODE:
            kind = PHYSICAL
            if normal_map == NO_TEXTURE:
                bump_map = self.data_map_of(bump, "bumpTexture", assets)
            if bump_map != NO_TEXTURE:
                bump_scale = self.number(bump, "bumpFactor", 1)
        var ior = DEFAULT_IOR
        var refraction = self.extension(material, MATERIALS_IOR)
        if refraction != NO_NODE:
            kind = PHYSICAL
            ior = self.number(refraction, "ior", DEFAULT_IOR)
        var specular_color = Color(255, 255, 255)
        var specular_intensity = Float32(1)
        var specular_intensity_map = NO_TEXTURE
        var specular_color_map = NO_TEXTURE
        var specular = self.extension(material, MATERIALS_SPECULAR)
        if specular != NO_NODE:
            kind = PHYSICAL
            specular_intensity = self.number(specular, "specularFactor", 1)
            var tint = self.numbers(specular, "specularColorFactor", 3)
            if len(tint) == 3:
                specular_color = _unit_color(tint, "specularColorFactor")
            # A number held in the alpha, and a color whose alpha means
            # nothing, each read as the renderer reads it, as the sheen's
            # two maps are.
            specular_intensity_map = self.map_of(
                specular, "specularTexture", LINEAR, assets, keep_alpha=True
            )
            specular_color_map = self.map_of(
                specular, "specularColorTexture", SRGB, assets
            )
            if specular_color_map != NO_TEXTURE:
                specular_color_map = assets.textures.add(
                    assets.textures.get(specular_color_map).ignoring_alpha()
                )
        var clearcoat = Float32(0)
        var clearcoat_roughness = Float32(0)
        var clearcoat_map = NO_TEXTURE
        var clearcoat_roughness_map = NO_TEXTURE
        var clearcoat_normal_map = NO_TEXTURE
        var clearcoat_normal_scale = Float32(1)
        var coat = self.extension(material, MATERIALS_CLEARCOAT)
        if coat != NO_NODE:
            kind = PHYSICAL
            clearcoat = self.number(coat, "clearcoatFactor", 0)
            clearcoat_roughness = self.number(
                coat, "clearcoatRoughnessFactor", 0
            )
            # three.js's `GLTFMaterialsClearcoatExtension`: three maps of
            # data, and the normal texture's `scale` on both axes.
            if clearcoat > 0:
                clearcoat_map = self.data_map_of(
                    coat, "clearcoatTexture", assets
                )
                clearcoat_roughness_map = self.data_map_of(
                    coat, "clearcoatRoughnessTexture", assets
                )
                clearcoat_normal_map = self.data_map_of(
                    coat, "clearcoatNormalTexture", assets
                )
            if clearcoat_normal_map != NO_TEXTURE:
                clearcoat_normal_scale = self.number(
                    self.document.get(coat, "clearcoatNormalTexture"),
                    "scale",
                    1,
                )
        var transmission = Float32(0)
        var transmission_map = NO_TEXTURE
        var through = self.extension(material, MATERIALS_TRANSMISSION)
        if through != NO_NODE:
            kind = PHYSICAL
            transmission = self.number(through, "transmissionFactor", 0)
            transmission_map = self.data_map_of(
                through, "transmissionTexture", assets
            )
        var thickness = Float32(0)
        var thickness_map = NO_TEXTURE
        var attenuation_color = Color(255, 255, 255)
        var attenuation_distance = inf[DType.float32]()
        var volume = self.extension(material, MATERIALS_VOLUME)
        if volume != NO_NODE:
            kind = PHYSICAL
            thickness = self.number(volume, "thicknessFactor", 0)
            thickness_map = self.data_map_of(volume, "thicknessTexture", assets)
            attenuation_distance = self.number(
                volume, "attenuationDistance", inf[DType.float32]()
            )
            if attenuation_distance == 0:
                attenuation_distance = inf[DType.float32]()
            var tint = self.numbers(volume, "attenuationColor", 3)
            if len(tint) == 3:
                attenuation_color = _unit_color(tint, "attenuationColor")
        var dispersion = Float32(0)
        var spread = self.extension(material, MATERIALS_DISPERSION)
        if spread != NO_NODE:
            kind = PHYSICAL
            dispersion = self.number(spread, "dispersion", 0)
        # three.js's `GLTFMaterialsSheenExtension`: a sheen of one, black
        # and smooth unless the file says otherwise.
        var sheen = Float32(0)
        var sheen_color = Color(0, 0, 0)
        var sheen_roughness = Float32(1)
        var sheen_color_map = NO_TEXTURE
        var sheen_roughness_map = NO_TEXTURE
        var cloth = self.extension(material, MATERIALS_SHEEN)
        if cloth != NO_NODE:
            kind = PHYSICAL
            sheen = 1
            sheen_roughness = self.number(cloth, "sheenRoughnessFactor", 0)
            var tint = self.numbers(cloth, "sheenColorFactor", 3)
            if len(tint) == 3:
                sheen_color = _unit_color(tint, "sheenColorFactor")
            # A color whose alpha means nothing, and a number held in the
            # alpha, which the linear textures above ignore: each read as
            # the renderer reads it.
            sheen_color_map = self.map_of(
                cloth, "sheenColorTexture", SRGB, assets
            )
            if sheen_color_map != NO_TEXTURE:
                sheen_color_map = assets.textures.add(
                    assets.textures.get(sheen_color_map).ignoring_alpha()
                )
            sheen_roughness_map = self.map_of(
                cloth, "sheenRoughnessTexture", LINEAR, assets, keep_alpha=True
            )
        # three.js's `GLTFMaterialsIridescenceExtension`.
        var iridescence = Float32(0)
        var iridescence_ior = DEFAULT_IRIDESCENCE_IOR
        var thinnest = DEFAULT_THICKNESS_MINIMUM
        var thickest = DEFAULT_THICKNESS_MAXIMUM
        var iridescence_map = NO_TEXTURE
        var film_thickness_map = NO_TEXTURE
        var film = self.extension(material, MATERIALS_IRIDESCENCE)
        if film != NO_NODE:
            kind = PHYSICAL
            iridescence = self.number(film, "iridescenceFactor", 0)
            iridescence_ior = self.number(
                film, "iridescenceIor", DEFAULT_IRIDESCENCE_IOR
            )
            thinnest = Length(
                self.number(film, "iridescenceThicknessMinimum", 100),
                NANOMETER,
            )
            thickest = Length(
                self.number(film, "iridescenceThicknessMaximum", 400),
                NANOMETER,
            )
            if iridescence > 0:
                iridescence_map = self.data_map_of(
                    film, "iridescenceTexture", assets
                )
                film_thickness_map = self.data_map_of(
                    film, "iridescenceThicknessTexture", assets
                )
        # three.js's `GLTFMaterialsAnisotropyExtension`.
        var anisotropy = Float32(0)
        var anisotropy_rotation = Angle(0.0, RADIAN)
        var anisotropy_map = NO_TEXTURE
        var stretch = self.extension(material, MATERIALS_ANISOTROPY)
        if stretch != NO_NODE:
            kind = PHYSICAL
            anisotropy = self.number(stretch, "anisotropyStrength", 0)
            anisotropy_rotation = Angle(
                self.number(stretch, "anisotropyRotation", 0), RADIAN
            )
            if anisotropy > 0:
                anisotropy_map = self.data_map_of(
                    stretch, "anisotropyTexture", assets
                )
        return Material(
            color,
            map=map,
            side=side,
            opacity=opacity,
            transparent=transparent,
            kind=kind,
            emissive=emissive,
            emissive_intensity=strength,
            emissive_map=emissive_map,
            roughness=roughness,
            metalness=metalness,
            roughness_map=roughness_map,
            metalness_map=roughness_map,
            normal_map=normal_map,
            normal_scale=Vector2(normal_scale, normal_scale),
            bump_map=bump_map,
            bump_scale=bump_scale,
            ao_map=occlusion[0],
            ao_map_intensity=occlusion[1],
            ior=ior,
            specular_color=specular_color,
            specular_intensity=specular_intensity,
            clearcoat=clearcoat,
            clearcoat_roughness=clearcoat_roughness,
            transmission=transmission,
            transmission_map=transmission_map,
            thickness=Length(thickness, METER),
            thickness_map=thickness_map,
            attenuation_color=attenuation_color,
            attenuation_distance=Length(attenuation_distance, METER),
            dispersion=dispersion,
            sheen=sheen,
            sheen_color=sheen_color,
            sheen_color_map=sheen_color_map,
            sheen_roughness=sheen_roughness,
            sheen_roughness_map=sheen_roughness_map,
            iridescence=iridescence,
            iridescence_ior=iridescence_ior,
            iridescence_thickness_minimum=thinnest,
            iridescence_thickness_maximum=thickest,
            iridescence_map=iridescence_map,
            iridescence_thickness_map=film_thickness_map,
            anisotropy=anisotropy,
            anisotropy_rotation=anisotropy_rotation,
            anisotropy_map=anisotropy_map,
            specular_intensity_map=specular_intensity_map,
            specular_color_map=specular_color_map,
            clearcoat_map=clearcoat_map,
            clearcoat_roughness_map=clearcoat_roughness_map,
            clearcoat_normal_map=clearcoat_normal_map,
            clearcoat_normal_scale=Vector2(
                clearcoat_normal_scale, clearcoat_normal_scale
            ),
        )

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
            self.model.mesh_extras.append(self.extras(mesh))
            var targets = 0
            var names = self.target_names(mesh)
            for slot in range(count):
                var primitive = self.document.at(primitives, slot)
                var mode = self.integer(primitive, "mode", MODE_TRIANGLES)
                if mode < MODE_POINTS or mode > MODE_TRIANGLES:
                    raise Error(
                        "glTF: a primitive must be points, lines, a line"
                        " loop, a line strip or triangles: strips and fans"
                        " of triangles are not read"
                    )
                var geometry = self.geometry_of(primitive, mode)
                # three.js's `assignExtrasToUserData( geometry,
                # primitiveDef )`.
                geometry.user_data = self.extras(primitive)
                if len(names) > 0:
                    if len(names) != geometry.morph_count():
                        raise Error(
                            "glTF: targetNames must hold one name per morph"
                            " target"
                        )
                    geometry.morph_names = names.copy()
                self.primitive_modes.append(mode)
                if slot == 0:
                    targets = geometry.morph_count()
                elif geometry.morph_count() != targets:
                    raise Error(
                        "glTF: every primitive of a mesh must carry as many"
                        " morph targets"
                    )
                self.model.geometries.append(assets.geometries.add(geometry^))
            self.morph_counts.append(targets)

    def draco_of(mut self, primitive: Int) raises -> Optional[_DracoPrimitive]:
        """Decode a primitive's `KHR_draco_mesh_compression` data, as
        three.js's `GLTFDracoMeshCompressionExtension` does, or return
        None when it has none."""
        var found = self.extension(primitive, DRACO_MESH_COMPRESSION)
        if found == NO_NODE:
            return None
        var view = self.view_bytes(self.required_integer(found, "bufferView"))
        var ids = self.document.get(found, "attributes")
        if ids == NO_NODE or self.document.kind(ids) != OBJECT:
            raise Error("glTF: KHR_draco_mesh_compression needs attributes")
        var names = List[String]()
        var uids = List[Int]()
        for slot in range(self.document.length(ids)):
            names.append(self.document.key(ids, slot))
            uids.append(self.document.integer(self.document.at(ids, slot)))
        var data = List[UInt8](capacity=view[2])
        ref bytes = self.buffers[view[0]]
        for at in range(view[1], view[1] + view[2]):
            data.append(bytes[at])
        return _DracoPrimitive(decode_draco(data), names^, uids^)

    def attribute_floats(
        mut self,
        name: String,
        accessor: Int,
        draco: Optional[_DracoPrimitive],
        raw: Bool = False,
    ) raises -> Tuple[List[Float32], Int]:
        """Return an attribute's numbers: from the Draco data when the
        primitive's `KHR_draco_mesh_compression` names it, and from its
        accessor otherwise. With `raw` set, an integer is not
        normalized."""
        if Bool(draco):
            ref found = draco.value()
            for slot in range(len(found.names)):
                if found.names[slot] == name:
                    return self.draco_floats(found, slot, accessor, raw)
        return self.accessor_floats(accessor, raw)

    def vertex_attribute(
        mut self,
        name: String,
        accessor: Int,
        draco: Optional[_DracoPrimitive],
    ) raises -> BufferAttribute:
        """Return an attribute as three.js's `GLTFLoader` builds it: in
        the typed array of its accessor's component type, normalized as
        the accessor says. A quantized attribute of `KHR_mesh_quantization`
        keeps its integers, so an exporter writes them back."""
        var component = self.component_of(accessor)
        if component == COMPONENT_FLOAT:
            var floats = self.attribute_floats(name, accessor, draco)
            return BufferAttribute(floats[0].copy(), floats[1])
        var raw = self.attribute_floats(name, accessor, draco, True)
        var stored = List[Int](capacity=len(raw[0]))
        for value in raw[0]:
            stored.append(Int(value))
        # glTF forbids a normalized unsigned int, and one is read as it
        # is, as `_integer_component` reads it.
        var normalized = (
            self.flag(self.entry("accessors", accessor), "normalized")
            and component != COMPONENT_UNSIGNED_INT
        )
        return BufferAttribute(
            stored, raw[1], _component_type_of(component), normalized
        )

    def draco_floats(
        self,
        draco: _DracoPrimitive,
        slot: Int,
        accessor_index: Int,
        raw: Bool = False,
    ) raises -> Tuple[List[Float32], Int]:
        """Return a Draco attribute's values at its accessor's component
        type, as three.js's `DRACOLoader` decodes them, then normalized as
        the accessor says unless `raw` is set. The attribute's own
        components make an element, as they make three.js's item size."""
        var accessor = self.entry("accessors", accessor_index)
        var component = self.required_integer(accessor, "componentType")
        var normalized = self.flag(accessor, "normalized") and not raw
        ref geometry = draco.geometry
        var index = geometry.unique_attribute(draco.ids[slot])
        if index < 0:
            raise Error("glTF: a Draco attribute id is not in the Draco data")
        var width = geometry.attributes[index].components
        if component == COMPONENT_FLOAT:
            return (geometry.float32_values(index), width)
        var values = geometry.integer_values(index, _draco_type_of(component))
        var out = List[Float32](capacity=len(values))
        for value in values:
            out.append(_integer_component(value, component, normalized))
        return (out^, width)

    def target_names(self, mesh: Int) raises -> List[String]:
        """Return the morph target names a mesh's `extras` holds in
        `targetNames`, as three.js's `GLTFLoader` reads them into
        `morphTargetDictionary`, or none when it holds no such array."""
        var names = List[String]()
        var extras = self.document.get(mesh, "extras")
        if extras == NO_NODE or self.document.kind(extras) != OBJECT:
            return names^
        var found = self.document.get(extras, "targetNames")
        if found == NO_NODE or self.document.kind(found) != ARRAY:
            return names^
        for slot in range(self.document.length(found)):
            names.append(self.document.string(self.document.at(found, slot)))
        return names^

    def geometry_of(
        mut self, primitive: Int, mode: Int
    ) raises -> BufferGeometry:
        """Build a primitive's geometry. A primitive of points or lines
        with indices is read out in index order, since an index here is a
        triangle index."""
        var attributes = self.document.get(primitive, "attributes")
        if attributes == NO_NODE or self.document.kind(attributes) != OBJECT:
            raise Error("glTF: a primitive needs attributes")
        var geometry = BufferGeometry()
        var position = self.integer(attributes, "POSITION", -1)
        if position < 0:
            raise Error("glTF: a primitive needs a POSITION")
        var draco = self.draco_of(primitive)
        var positions = self.vertex_attribute("POSITION", position, draco)
        if positions.item_size != 3:
            raise Error("glTF: POSITION must be a VEC3")
        var floats = positions.count() * 3
        geometry.set_attribute(String(POSITION), positions^)
        var normal = self.integer(attributes, "NORMAL", -1)
        if normal >= 0:
            var normals = self.vertex_attribute("NORMAL", normal, draco)
            if normals.item_size != 3:
                raise Error("glTF: NORMAL must be a VEC3")
            geometry.set_attribute(String(NORMAL), normals^)
        var uv = self.integer(attributes, "TEXCOORD_0", -1)
        if uv >= 0:
            var uvs = self.vertex_attribute("TEXCOORD_0", uv, draco)
            if uvs.item_size != 2:
                raise Error("glTF: TEXCOORD_0 must be a VEC2")
            geometry.set_attribute(String(UV), uvs^)
        var uv1 = self.integer(attributes, "TEXCOORD_1", -1)
        if uv1 >= 0:
            var second = self.vertex_attribute("TEXCOORD_1", uv1, draco)
            if second.item_size != 2:
                raise Error("glTF: TEXCOORD_1 must be a VEC2")
            geometry.set_attribute(String(UV1), second^)
        var color = self.integer(attributes, "COLOR_0", -1)
        if color >= 0:
            var colors = self.vertex_attribute("COLOR_0", color, draco)
            if colors.item_size != 3 and colors.item_size != 4:
                raise Error("glTF: COLOR_0 must be a VEC3 or a VEC4")
            geometry.set_attribute(String(COLOR), colors^)
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
            var bones = self.vertex_attribute("JOINTS_0", joints, draco)
            if bones.item_size != 4:
                raise Error("glTF: JOINTS_0 must be a VEC4")
            geometry.set_attribute(String(SKIN_INDEX), bones^)
        var weights = self.integer(attributes, "WEIGHTS_0", -1)
        if weights >= 0:
            var shares = self.attribute_floats("WEIGHTS_0", weights, draco)
            if shares[1] != 4:
                raise Error("glTF: WEIGHTS_0 must be a VEC4")
            geometry.set_attribute(
                String(SKIN_WEIGHT),
                BufferAttribute(_normalize_skin_weights(shares[0]), 4),
            )
        self.read_targets(primitive, geometry, floats)
        var indices = self.integer(primitive, "indices", -1)
        # three.js keeps a Draco mesh's own triangles over the accessor's.
        if Bool(draco) and (
            draco.value().geometry.geometry_type == DRACO_TRIANGULAR_MESH
        ):
            geometry.set_index(draco.value().geometry.faces.copy())
            return geometry^
        if indices < 0:
            return geometry^
        var order = self.accessor_indices(indices)
        if mode == MODE_TRIANGLES:
            geometry.set_index(order^)
            return geometry^
        return _gathered(geometry, order)

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
        var any_colors = False
        for slot in range(count):
            var target = self.object_at(targets, slot)
            if self.document.has(target, "COLOR_0"):
                any_colors = True
            if self.document.has(target, "NORMAL"):
                any_normals = True
        geometry.morph_relative = True
        var tints = List[BufferAttribute]()
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
            if any_colors:
                tints.append(self.target_colors(target, geometry))
        if any_colors:
            geometry.set_morph_colors(tints^)

    def target_colors(
        mut self, target: Int, geometry: BufferGeometry
    ) raises -> BufferAttribute:
        """Return one morph target's `COLOR_0` offsets, or zeros when it
        names none: a target without a color changes no color, as one
        without a `POSITION` moves nothing."""
        var index = self.integer(target, "COLOR_0", -1)
        if index < 0:
            return BufferAttribute(
                List[Float32](length=geometry.vertex_count() * 4, fill=0), 4
            )
        var colors = self.accessor_floats(index)
        if colors[1] != 3 and colors[1] != 4:
            raise Error(
                "glTF: a morph target's COLOR_0 must be a VEC3 or a VEC4"
            )
        return BufferAttribute(colors[0].copy(), colors[1])

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
            self.node_skins.append(List[Int]())
        for index in range(count):
            self.model.node_names[index] = self.text(
                self.entry("nodes", index), "name"
            )
        self.model.first_mesh = len(scene.meshes)
        self.model.first_skinned_mesh = len(scene.skinned_meshes)
        self.model.first_instanced_mesh = len(scene.instanced_meshes)
        self.model.first_light = len(scene.lights)
        self.model.first_line = len(scene.lines)
        self.model.first_points = len(scene.points)
        var scenes = self.count("scenes")
        if scenes == 0:
            return
        var chosen = self.integer(self.document.root(), "scene", 0)
        var top = self.entry("scenes", chosen)
        self.model.scene_extras = self.extras(top)
        var roots = self.document.get(top, "nodes")
        if roots == NO_NODE:
            return
        if self.document.kind(roots) != ARRAY:
            raise Error("glTF: a scene's nodes must be an array")
        for slot in range(self.document.length(roots)):
            var root = self.document.integer(self.document.at(roots, slot))
            self.place(root, NO_PARENT, scene, assets)
        self.model.mesh_count = len(scene.meshes) - self.model.first_mesh
        self.model.instanced_mesh_count = (
            len(scene.instanced_meshes) - self.model.first_instanced_mesh
        )
        self.model.light_count = len(scene.lights) - self.model.first_light
        self.model.line_count = len(scene.lines) - self.model.first_line
        self.model.points_count = len(scene.points) - self.model.first_points
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
        placed.user_data = self.node_user_data(node, index)
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
        var instancing = self.extension(node, GPU_INSTANCING)
        if mesh >= 0:
            var skinned = self.document.has(node, "skin")
            if skinned and instancing != NO_NODE:
                raise Error(
                    "glTF: a skinned node cannot be instanced: an instanced"
                    " skinned mesh is not ported"
                )
            if skinned:
                self.skinned_nodes.append(index)
                self.skinned_ids.append(id)
            elif instancing != NO_NODE:
                self.draw_instanced(mesh, index, id, instancing, scene, assets)
            else:
                self.draw(mesh, index, id, scene, assets)
        var camera = self.integer(node, "camera", -1)
        if camera >= 0:
            self.model.cameras.append(self.camera_of(camera, id))
        var lamp = self.extension(node, LIGHTS_PUNCTUAL)
        if lamp != NO_NODE:
            self.add_light(self.required_integer(lamp, "light"), id, scene)
        var children = self.document.get(node, "children")
        if children != NO_NODE:
            if self.document.kind(children) != ARRAY:
                raise Error("glTF: a node's children must be an array")
            for slot in range(self.document.length(children)):
                var child = self.document.integer(
                    self.document.at(children, slot)
                )
                self.place(child, id, scene, assets)

    def node_user_data(self, node: Int, index: Int) raises -> UserData:
        """Return a node's user data as three.js's `GLTFLoader.loadNode`
        leaves it: its mesh's `extras` when the mesh is the node, its
        `name`, and its own `extras`, each over the one before."""
        var data = UserData()
        var mesh = self.integer(node, "mesh", -1)
        # three.js's node is its mesh when the mesh is the one object it
        # makes: one primitive, no camera, no light, and not a joint.
        var alone = (
            mesh >= 0
            and mesh < len(self.model.mesh_extras)
            and self.model.primitive_counts[mesh] == 1
            and not self.document.has(node, "camera")
            and self.extension(node, LIGHTS_PUNCTUAL) == NO_NODE
        )
        if alone and not self.is_joint(index):
            data = UserData(copy=self.model.mesh_extras[mesh])
        var name = self.model.node_names[index]
        if name != "":
            data.set_string("name", name)
        var own = self.extras(node)
        for at in range(own.count()):
            var key = own.key(at)
            data.set_json(key, own.json(key))
        return data^

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
        """Add a `Mesh` per primitive of triangles of a glTF mesh at a
        node, a `Line` per primitive of lines and a `Points` per primitive
        of points, as three.js's `GLTFLoader.loadMesh` builds them."""
        # `place` asks only for a mesh the node named, zero or more.
        if mesh >= len(self.model.first_primitives):
            raise Error("glTF: a node names a mesh that is not there")
        var weights = self.morph_weights(self.entry("nodes", index), mesh)
        var entry = self.entry("meshes", mesh)
        var primitives = self.document.get(entry, "primitives")
        for slot in range(self.model.primitive_counts[mesh]):
            var primitive = self.document.at(primitives, slot)
            var at = self.model.first_primitives[mesh] + slot
            var geometry = self.model.geometries[at]
            var tinted = assets.geometries.get(geometry).has_attribute(
                String(COLOR)
            )
            var chosen = self.integer(primitive, "material", -1)
            var mode = self.primitive_modes[at]
            if mode != MODE_TRIANGLES:
                var worn = self.unlit_material(chosen, tinted, mode, assets)
                if mode == MODE_POINTS:
                    scene.add_points(Points(geometry, worn, node))
                else:
                    scene.add_line(
                        Line(geometry, worn, node, mode=_line_mode(mode))
                    )
                continue
            var material = self.material_for(chosen, tinted, assets)
            var drawn = Mesh(geometry, material, node)
            drawn.update_morph_targets(assets.geometries.get(geometry))
            for target in range(len(weights)):
                drawn.set_morph_influence(target, weights[target])
            self.node_meshes[index].append(len(scene.meshes))
            scene.add_mesh(drawn)

    def unlit_material(
        mut self, index: Int, tinted: Bool, mode: Int, mut assets: Assets
    ) raises -> MaterialId:
        """Return the material a primitive of points or lines draws with,
        as three.js's `GLTFLoader` makes a `PointsMaterial` or a
        `LineBasicMaterial` from the file's: its color, opacity and
        transparency, vertex colors when the primitive carries them, and
        for points its map and alpha test, at a size of one pixel that
        does not shrink with distance. A line here carries no map."""
        var base = assets.materials.get(self.material_for(index, False, assets))
        if mode == MODE_POINTS:
            return assets.materials.add(
                points_material(
                    base.color,
                    size_attenuation=False,
                    map=base.map,
                    alpha_test=base.alpha_test,
                    opacity=base.opacity,
                    transparent=base.transparent,
                    vertex_colors=tinted,
                )
            )
        return assets.materials.add(
            Material(
                base.color,
                kind=BASIC,
                opacity=base.opacity,
                transparent=base.transparent,
                vertex_colors=tinted,
            )
        )

    def draw_instanced(
        mut self,
        mesh: Int,
        index: Int,
        node: NodeId,
        instancing: Int,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add an `InstancedMesh` per primitive of a glTF mesh at a node
        that `EXT_mesh_gpu_instancing` places many times, as three.js's
        `GLTFMeshGpuInstancing` builds one.

        Each instance is `TRANSLATION`, `ROTATION` and `SCALE` composed,
        each the identity's part when the file names none. `_COLOR_0`
        colors the instances, as three.js reads it into `instanceColor`.
        Any other attribute is for a custom shader, which this renderer
        has not got, and is only counted. With no attribute at all the
        node draws plain meshes, as three.js draws them.
        """
        var attributes = self.document.get(instancing, "attributes")
        if attributes == NO_NODE or self.document.kind(attributes) != OBJECT:
            raise Error("glTF: " + GPU_INSTANCING + " needs attributes")
        var count = -1
        var moves = List[Float32]()
        var turns = List[Float32]()
        var sizes = List[Float32]()
        var tints = List[Float32]()
        for slot in range(self.document.length(attributes)):
            var name = self.document.key(attributes, slot)
            var values = self.accessor_floats(
                self.document.integer(self.document.at(attributes, slot))
            )
            var elements = len(values[0]) // values[1]
            if count >= 0 and elements != count:
                raise Error(
                    "glTF: every instancing attribute must hold as many"
                    " elements"
                )
            count = elements
            if name == "TRANSLATION":
                moves = _instance_attribute(values, 3, name)
            elif name == "ROTATION":
                turns = _instance_attribute(values, 4, name)
            elif name == "SCALE":
                sizes = _instance_attribute(values, 3, name)
            elif name == "_COLOR_0":
                tints = _instance_attribute(values, 3, name)
        if count < 0:
            self.draw(mesh, index, node, scene, assets)
            return
        var placings = List[Matrix4]()
        for at in range(count):
            var placed = Object3D()
            if len(moves) > 0:
                placed.set_position(
                    moves[at * 3], moves[at * 3 + 1], moves[at * 3 + 2]
                )
            if len(turns) > 0:
                placed.set_quaternion(
                    Quaternion(
                        turns[at * 4],
                        turns[at * 4 + 1],
                        turns[at * 4 + 2],
                        turns[at * 4 + 3],
                    )
                )
            if len(sizes) > 0:
                placed.set_scale(
                    sizes[at * 3], sizes[at * 3 + 1], sizes[at * 3 + 2]
                )
            placings.append(placed.local_matrix())
        # `place` asks only for a mesh the node named, zero or more.
        if mesh >= len(self.model.first_primitives):
            raise Error("glTF: a node names a mesh that is not there")
        var primitives = self.document.get(
            self.entry("meshes", mesh), "primitives"
        )
        for slot in range(self.model.primitive_counts[mesh]):
            var primitive = self.document.at(primitives, slot)
            var at = self.model.first_primitives[mesh] + slot
            if self.primitive_modes[at] != MODE_TRIANGLES:
                raise Error(
                    "glTF: an instanced node draws triangles only: an"
                    " instanced line or points is not ported"
                )
            var geometry = self.model.geometries[at]
            var tinted = assets.geometries.get(geometry).has_attribute(
                String(COLOR)
            )
            var material = self.material_for(
                self.integer(primitive, "material", -1), tinted, assets
            )
            var drawn = InstancedMesh(geometry, material, node, count)
            for at in range(count):
                drawn.set_matrix_at(at, placings[at])
                if len(tints) > 0:
                    drawn.set_color_at(
                        at,
                        FloatColor(
                            tints[at * 3],
                            tints[at * 3 + 1],
                            tints[at * 3 + 2],
                            1,
                        ).encode(),
                    )
            scene.add_instanced_mesh(drawn^)

    # --- lights -------------------------------------------------------------

    def add_light(mut self, index: Int, node: NodeId, mut scene: Scene) raises:
        """Add a `KHR_lights_punctual` light riding a scene node, as
        three.js's `GLTFLightsExtension` builds it.

        The color is linear, as glTF writes it, and the intensity one when
        the file names none. A point or spot light's `range` is its
        `distance`, and it falls off at the physical decay of two. A spot
        light's cone is its `outerConeAngle`, and its penumbra is the part
        of that cone outside `innerConeAngle`. A directional or spot light
        shines down the node's -z axis: toward a target node one meter down
        it, as three.js adds its `target` to the light.
        """
        var root = self.extension(self.document.root(), LIGHTS_PUNCTUAL)
        if root == NO_NODE:
            raise Error("glTF: a node names a light and the file has none")
        var lights = self.array_of(root, "lights")
        if index < 0 or index >= self.document.length(lights):
            raise Error("glTF: a node names a light that is not there")
        var entry = self.object_at(lights, index)
        var color = Color(255, 255, 255)
        var hue = self.numbers(entry, "color", 3)
        if len(hue) == 3:
            color = FloatColor(hue[0], hue[1], hue[2], 1).encode()
        var intensity = self.number(entry, "intensity", 1)
        var distance = self.number(entry, "range", 0)
        if self.document.has(entry, "range") and distance <= 0:
            raise Error("glTF: a light's range must be above zero")
        var kind = self.text(entry, "type")
        if kind == "point":
            scene.add_light(
                point_light(color, node, intensity, distance=distance)
            )
            return
        if kind != "directional" and kind != "spot":
            raise Error(
                "glTF: a light's type must be directional, point or spot"
            )
        var aim = Object3D()
        aim.set_position(0, 0, -1)
        var target = scene.attach(aim^, node)
        if kind == "directional":
            scene.add_light(directional_light(color, node, intensity, target))
            return
        var cone = self.document.get(entry, "spot")
        if cone == NO_NODE or self.document.kind(cone) != OBJECT:
            raise Error("glTF: a spot light needs a spot object")
        var inner = self.number(cone, "innerConeAngle", 0)
        var outer = self.number(cone, "outerConeAngle", DEFAULT_OUTER_CONE)
        scene.add_light(
            spot_light(
                color,
                node,
                intensity,
                distance=distance,
                angle=Angle(outer, RADIAN),
                penumbra=1 - inner / outer,
                target=target,
            )
        )

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
            var at = self.model.first_primitives[mesh] + slot
            if self.primitive_modes[at] != MODE_TRIANGLES:
                raise Error(
                    "glTF: a skinned node draws triangles only: a skinned"
                    " line or points is not ported"
                )
            var geometry = self.model.geometries[at]
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
            drawn.update_morph_targets(assets.geometries.get(geometry))
            for target in range(len(weights)):
                drawn.set_morph_influence(target, weights[target])
            self.node_skins[index].append(len(scene.skinned_meshes))
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
        if len(input[0]) == 0:
            raise Error("glTF: a sampler needs at least one key")
        var times = List[Duration]()
        for key in range(len(input[0])):  # pragma: no branch
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
        var parts = 3 if how == CUBIC_SPLINE else 1
        var keys = len(times) * parts
        if len(output[0]) % keys != 0:
            raise Error(
                "glTF: a weights output must hold the same number of weights"
                " for every key"
            )
        var stride = len(output[0]) // keys
        # Every mesh, plain or skinned, at the node and at every node below
        # it that has morph targets, as three.js's `GLTFLoader` traverses
        # the node for `morphTargetInfluences`. Each takes as many weights
        # as it has targets, and as the sampler has.
        var below: List[Int] = [node]
        var at = 0
        while at < len(below):
            var children = self.document.get(
                self.entry("nodes", below[at]), "children"
            )
            at += 1
            if children == NO_NODE:
                continue
            for slot in range(self.document.length(children)):
                below.append(
                    self.document.integer(self.document.at(children, slot))
                )
        for each in range(len(below)):  # pragma: no branch
            var reached = below[each]
            var mesh = self.integer(self.entry("nodes", reached), "mesh", -1)
            if mesh < 0:
                continue
            var morphs = min(self.morph_counts[mesh], stride)
            var drawn = List[TrackTarget]()
            for slot in range(len(self.node_meshes[reached])):
                drawn.append(
                    morph_target(MeshIndex(self.node_meshes[reached][slot]), 0)
                )
            for slot in range(len(self.node_skins[reached])):
                drawn.append(
                    skinned_morph_target(
                        SkinnedMeshIndex(self.node_skins[reached][slot]), 0
                    )
                )
            # A node with a mesh draws at least one primitive of it.
            for slot in range(len(drawn)):  # pragma: no branch
                for target in range(morphs):
                    tracks.append(
                        _track(
                            TrackTarget(
                                drawn[slot].kind, drawn[slot].index, target
                            ),
                            times,
                            output[0],
                            how,
                            stride,
                            target,
                        )
                    )


def _line_mode(mode: Int) -> LineMode:
    """Return a primitive mode of lines as a line's mode."""
    if mode == MODE_LINES:
        return SEGMENTS
    if mode == MODE_LINE_LOOP:
        return LOOP
    return STRIP


def _gathered(
    geometry: BufferGeometry, order: List[Int]
) raises -> BufferGeometry:
    """Return a geometry's vertices copied out in index order, its morph
    targets with them, as three.js's `toNonIndexed` copies them."""
    var out = BufferGeometry()
    # A primitive has a POSITION, so the loop always runs.
    for slot in range(len(geometry.names)):  # pragma: no branch
        out.set_attribute(
            geometry.names[slot], geometry.values[slot].gather(order)
        )
    for target in range(geometry.morph_count()):
        out.morph_positions.append(
            geometry.morph_positions[target].gather(order)
        )
    for target in range(len(geometry.morph_normals)):
        out.morph_normals.append(geometry.morph_normals[target].gather(order))
    out.morph_relative = geometry.morph_relative
    return out^


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
        # A sampler has at least one key; `channel_tracks` refuses none.
        for key in range(len(times)):  # pragma: no branch
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


def _instance_attribute(
    values: Tuple[List[Float32], Int], width: Int, name: String
) raises -> List[Float32]:
    """Return an instancing attribute's numbers, which must come `width`
    to an element."""
    if values[1] != width:
        raise Error(
            "glTF: an instancing " + name + " must be a VEC" + String(width)
        )
    return values[0].copy()


def _unit_color(factors: List[Float32], key: String) raises -> Color:
    """Return three linear factors as the sRGB color a material holds,
    refusing one outside zero to one, which a `Color` cannot hold."""
    for lane in range(3):  # pragma: no branch
        if factors[lane] < 0 or factors[lane] > 1:
            raise Error("glTF: " + key + " must be from zero to one")
    return FloatColor(factors[0], factors[1], factors[2], 1).encode()


def _normalize_skin_weights(weights: List[Float32]) -> List[Float32]:
    """Return each vertex's four weights scaled to sum to one, by
    `normalized_skin_weights`, three.js's `normalizeSkinWeights`."""
    var out = List[Float32]()
    for vertex in range(len(weights) // 4):
        var four = SIMD[DType.float32, 4](0)
        for lane in range(4):  # pragma: no branch
            four[lane] = weights[vertex * 4 + lane]
        var scaled = normalized_skin_weights(four)
        for lane in range(4):  # pragma: no branch
            out.append(scaled[lane])
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
    var raw: Int
    if component == COMPONENT_UNSIGNED_BYTE:
        raw = Int(bytes[at])
    elif component == COMPONENT_BYTE:
        raw = Int(bytes[at])
        if raw >= 128:
            raw -= 256
    elif component == COMPONENT_UNSIGNED_SHORT:
        raw = Int(bytes[at]) | (Int(bytes[at + 1]) << 8)
    elif component == COMPONENT_SHORT:
        raw = Int(bytes[at]) | (Int(bytes[at + 1]) << 8)
        if raw >= 32768:
            raw -= 65536
    else:
        # `COMPONENT_UNSIGNED_INT`, the last `_component_size` admits.
        raw = _le32(bytes, at)
    return _integer_component(raw, component, normalized)


def _component_type_of(component: Int) -> ComponentType:
    """Return the typed array an integer accessor's component type is
    read into, as three.js's `WEBGL_COMPONENT_TYPES` maps it."""
    if component == COMPONENT_BYTE:
        return INT8_COMPONENT
    if component == COMPONENT_UNSIGNED_BYTE:
        return UINT8_COMPONENT
    if component == COMPONENT_SHORT:
        return INT16_COMPONENT
    if component == COMPONENT_UNSIGNED_SHORT:
        return UINT16_COMPONENT
    # `COMPONENT_UNSIGNED_INT`, the last `_component_size` admits: the
    # accessor has been read by the time this is asked.
    return UINT32_COMPONENT


def _draco_type_of(component: Int) raises -> DracoDataType:
    """Return the Draco type an integer accessor's component type asks
    for, as three.js's `DRACOLoader` maps a typed array."""
    if component == COMPONENT_BYTE:
        return DracoDataType(1)
    if component == COMPONENT_UNSIGNED_BYTE:
        return DracoDataType(2)
    if component == COMPONENT_SHORT:
        return DracoDataType(3)
    if component == COMPONENT_UNSIGNED_SHORT:
        return DracoDataType(4)
    if component == COMPONENT_UNSIGNED_INT:
        return DracoDataType(6)
    raise Error("glTF: a component type that is not known")


def _integer_component(value: Int, component: Int, normalized: Bool) -> Float32:
    """Return an integer component as a float, normalized to zero through
    one or minus one through one when the accessor says so. An unsigned
    int is never normalized: glTF allows none, and three.js reads one as
    it is."""
    var number = Float32(value)
    if not normalized:
        return number
    if component == COMPONENT_UNSIGNED_BYTE:
        return number / 255
    if component == COMPONENT_BYTE:
        return max(number / 127, Float32(-1))
    if component == COMPONENT_UNSIGNED_SHORT:
        return number / 65535
    if component == COMPONENT_SHORT:
        return max(number / 32767, Float32(-1))
    return number


def _wrap_of(mode: Int) raises -> Wrap:
    """Return a sampler's wrap as a texture's."""
    if mode == WRAP_REPEAT:
        return REPEAT
    if mode == WRAP_CLAMP:
        return CLAMP
    if mode == WRAP_MIRROR:
        return MIRROR
    raise Error("glTF: a wrap mode that is not known")


def is_ktx2(bytes: List[UInt8]) -> Bool:
    """Return True if bytes begin with the KTX 2.0 identifier, as the image
    a `KHR_texture_basisu` texture names does.

    Args:
        bytes: An image file.

    Returns:
        Whether it is a KTX 2.0 file.
    """
    var magic = ktx2.identifier()
    if len(bytes) < len(magic):
        return False
    # The identifier is twelve bytes, so the loop always runs.
    for at in range(len(magic)):  # pragma: no branch
        if bytes[at] != magic[at]:
            return False
    return True


def ktx2_texture(
    bytes: List[UInt8], sampling: GltfSampler, space: ColorSpace, alpha: Alpha
) raises -> Texture:
    """Return a KTX 2.0 image as a glTF texture, as three.js's
    `KTX2Loader` decodes the one a `KHR_texture_basisu` texture names.

    The first level of the first face is read, through `render.ktx2`. A
    byte texture takes the color space the material asks for, as every
    other glTF image does here, and builds its own chain when the sampler
    reads one. A texture that decodes to floats, UASTC HDR for one, is
    linear whatever the material asks.

    Args:
        bytes: The KTX 2.0 file.
        sampling: The glTF sampler's wraps and filters.
        space: `SRGB` for a color map, `LINEAR` for data.
        alpha: `COVERAGE` or `IGNORED`.

    Returns:
        The texture. `flip_y` is off, as glTF has it.

    Raises:
        Error: If `render.ktx2` refuses the file or cannot decode it.
    """
    var container = ktx2.read(bytes)
    var chain = sampling.min_filter.is_mipmap()
    if container.decodes_to_floats():
        return container.texture(
            wrap=sampling.wrap_s,
            filter=sampling.mag_filter,
            mipmapped=chain,
            alpha=alpha,
        )
    var first = container.texture()
    return Texture(
        first.width,
        first.height,
        first.pixels.copy(),
        sampling.wrap_s,
        sampling.mag_filter,
        space,
        chain,
        alpha,
    )


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
