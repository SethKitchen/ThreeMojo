# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The JSON Object format of three.js, version 4, read into a `Scene` and
an `Assets`: three.js's `ObjectLoader`, and the other half of
`exporters.object_json`.

**What the format is.** One JSON document with a `metadata` object whose
`type` is `Object`, four libraries -- `geometries`, `materials`,
`textures` and `images`, each entry named by a `uuid` -- and an `object`,
the root of a tree of objects that name their geometry, material and
textures by those uuids. `Object3D.toJSON` writes it and `ObjectLoader`
reads it. `read_object_json` reads it into the scene and the assets it is
handed and returns an `ObjectModel` that says which node each object
became and which cameras it held.

**What maps to what.** Every object becomes one scene node at its
`matrix`, decomposed as three.js decomposes it, or at its `position`,
`quaternion` or `rotation`, and `scale`; with its `name`, `visible`,
`layers`, `renderOrder`, `userData` and `up`. A `matrixAutoUpdate` of false
keeps the matrix as it is. A `Group` becomes a node of `GROUP_TYPE`. Then
the object's type says what the node carries:

    Object3D, Group, Bone      nothing
    Mesh                       a `Mesh`
    InstancedMesh              an `InstancedMesh` and its matrices
    BatchedMesh                a `BatchedMesh` and its geometries
    SkinnedMesh                a `SkinnedMesh` on its skeleton
    Line, LineLoop, LineSegments   a `Line` of that `LineMode`
    Points                     `Points`
    Sprite                     a `Sprite`
    LOD                        an `Lod` of its levels
    AmbientLight ... RectAreaLight   a `Light` of that kind
    PerspectiveCamera          a `PerspectiveCamera` attached to the node,
                               with its `zoom`
    OrthographicCamera         an `OrthographicCamera` attached to it

A root of type `Scene` is not a node: its children are the scene's roots,
and its `fog` and `background` become the scene's. A light's `target`
names another object by uuid, or an object that is not in the file, which
is three.js's default target at the origin.

An `LOD`'s `levels` name objects by uuid, each of any type, and its
`autoUpdate` is read; `Scene.add_lod` makes each level a child of the
LOD, as three.js's `addLevel` does. A
`SkinnedMesh` names an entry of the `skeletons` library, whose `bones`
are objects of the document and whose `boneInverses` are their inverse
binds; it is bound after the whole tree is read, as three.js binds it. A
`BatchedMesh` splits its one geometry into the parts its `geometryInfo`
names, and places each active, visible instance of its `instanceInfo`
from the `Float32Array` images of its `matricesTexture` and
`colorsTexture`. Its joined geometry stays in the assets too.

A `BufferGeometry` is read with its name, its user data, its attributes
in any of the seven typed arrays, its index, its groups and its morph
targets. An interleaved attribute reads the
geometry's `interleavedBuffers` and `arrayBuffers`, and the attributes that
name one buffer share it. An `InstancedBufferGeometry` is read with its
`instanceCount` and its per-instance attributes' `meshPerAttribute`, which
three.js's loader leaves at their defaults. A `BoxGeometry`, a `PlaneGeometry` and a
`SphereGeometry` are built from their parameters by `geometries`, when
the parameters are ones those builders take. A material is built with
the `MaterialKind` its type names, three.js's defaults filling what the
entry leaves out: a `MeshPhongMaterial` without a `specular` has
`0x111111`, as in three.js. That covers the baked light, the
displacement, the flat shading, the depth packing, the volume, the sheen,
the film and the stretch of a physical surface, and the depth, stencil
and polygon offset state, each under three.js's key. A map's numbers --
`aoMapIntensity`, `lightMapIntensity`, `displacementScale` and
`displacementBias` -- are read only beside their map, where
`Material.toJSON` writes them. `LineBasicMaterial`,
`LineDashedMaterial`, `PointsMaterial` and `SpriteMaterial` are `BASIC`
materials with their width, dashes, size, attenuation and turn; a
`SpriteMaterial` is transparent unless it says otherwise, as three.js
builds one. A texture is read from its image's `data:` URL, or from a
file beside the document, as PNG, JPEG or TGA, with its `channel`.

**Cube textures and environments.** A texture whose image's `url` is an
array of six is a `CubeTexture`, as `ObjectLoader.parseTextures` decides.
Its images are in the OpenGL layout three.js keeps them in, so they are
read `SEEN_FROM_OUTSIDE`. It can be the scene's `background` or
`environment`, or a material's `envMap`. A standard or physical material
without an `envMap` reflects the scene's `environment`, as three.js's
renderer has it, and every other class reflects only its own. The
environment, and each cube a standard or physical material names, gets
its PMREM, since three.js's renderer prefilters what those surfaces
reflect. A mesh reads its `morphTargetInfluences`. A material reads its
`clippingPlanes`, `clipIntersection`, `clipShadows` and `dashOffset`, and
a `MeshDistanceMaterial` its `referencePosition`, `nearDistance` and
`farDistance`, which three.js's loader ignores. A skeleton without
`boneInverses` gets the inverse of each bone's world matrix, as
`Skeleton.calculateInverses` works them out.

**A texture's alpha comes from its use.** three.js has no alpha mode. Here
a texture is built with its alpha as `COVERAGE` when a material's `map`
or the background names it, and as `IGNORED` when a data map names it --
any other map but a sheen roughness map or a specular intensity map,
whose alpha is its data --
since the renderer reads a data map's alpha as nothing. A texture named
both ways is built twice.

**What is refused.** A document that is not JSON, a `metadata.type` that
is not `Object`, a version that is not 4, an object, geometry or material
type this port has no counterpart for, an attribute in a typed array
that is not one of the seven, an instanced attribute of integers, an object other than a mesh with more than one
material, a mesh with an empty material list, a
uuid named twice or named and not there, a `CustomBlending` material, a
depth function, stencil function or stencil operation that is none of
three.js's, a flat texture whose mapping is neither `UVMapping` nor an
equirectangular one or whose `channel` is neither of two, a cube texture
that is not six images or whose mapping is neither cube mapping, an
`envMap`, `environment` or blurred background that names a flat texture
that is not equirectangular, more than eight clipping planes, an LOD
level that names no object or is the LOD or above it, a skeleton with
fewer `boneInverses` than bones, a batch
whose info names what is not there, and every number the builders
refuse.

**Animations.** Every object's `animations` names clips of the
document's `animations` library by uuid, and each is read with
`animation.animation_json.read_clip`, as three.js's `parseAnimations`
reads it. A track's name is found below the object that names the clip,
as three.js's `PropertyBinding.findNode` finds it: the object itself for
no name or its own name or uuid, then a bone of its skeleton by name,
then the first object below it, depth first, by name or uuid. A track
whose object is not found, or does not have the property, is left out, as
three.js binds it to nothing; a clip left with no track is left out too.
A track on the scene itself is refused, since the scene is not a node.

**Samplers, panoramas and the scene's environment.** A texture reads its
`wrap` per axis, its `magFilter` and `minFilter`, its `flipY` and its
`mapping`. A flat texture with an equirectangular mapping, named as an
`envMap`, the `environment` or a blurred background, becomes a cube that
reads it directly, with its PMREM where a standard or physical surface
reflects it or the background is blurred, as three.js's `WebGLCubeUVMaps`
builds one. A material reads its `envMapRotation`, a basic, lambert or
phong material its `refractionRatio`, and a material with a normal map
its `normalMapType`. The scene reads its `backgroundBlurriness`,
`backgroundIntensity`, `backgroundRotation`, `environmentIntensity` and
`environmentRotation`.

**What is read without effect.** `up` and `matrixWorldAutoUpdate`;
a cube texture's wrap; an
`envMap` on a class whose shader reads none; the material keys this port
has no field for; a texture's `format`, `type`,
`premultiplyAlpha` and `unpackAlignment`; and a batch's sorting,
reserved ranges and bounds.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute, component_of_array
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
)
from core.interleaved_buffer import InterleavedBuffer
from core.morph import MorphInfluences
from core.background import (
    color_background,
    cube_background,
    texture_background,
)
from core.fog import exp2_fog, linear_fog
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import GROUP_TYPE, NO_PARENT, NodeId, Object3D
from core.scene import Scene
from core.user_data import user_data_of
from cameras.camera import ViewOffset
from animation.animation_clip import AnimationClip
from animation.animation_json import (
    parse_track_name,
    property_kind,
    read_clip,
    track_names,
)
from animation.keyframe_track import (
    CAMERA_FOV,
    LightIndex,
    MORPH_INFLUENCE,
    ORTHOGRAPHIC_SLOT,
    OrthographicCameraIndex,
    PERSPECTIVE_SLOT,
    PerspectiveCameraIndex,
    SKINNED_MORPH_INFLUENCE,
    TrackTarget,
    light_target,
    material_target,
    node_target,
    orthographic_camera_target,
    perspective_camera_target,
)
from cameras.camera_list import CameraList
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from geometries.box import box
from geometries.plane import plane
from geometries.sphere import sphere
from lights.light import (
    AMBIENT,
    DIRECTIONAL,
    HEMISPHERE,
    POINT,
    RECT_AREA,
    LIGHT_PROBE,
    SPOT,
    Light,
    LightKind,
    ambient_light,
    directional_light,
    hemisphere_light,
    point_light,
    rect_area_light,
    light_probe,
    spot_light,
)
from loaders.gltf import decode_base64, decode_image
from loaders.json import (
    ARRAY,
    NO_NODE,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    parse_json,
)
from materials.material import (
    ADDITIVE,
    MULTIPLY,
    NO_TEXTURE,
    OPAQUE,
    PHONG,
    SHADOW,
    SUBTRACTIVE,
    Blending,
    Combine,
    Material,
    MaterialId,
    MaterialKind,
    Side,
    BASIC,
    DEFAULT_LINE_WIDTH,
    DEFAULT_POINT_SIZE,
    DISTANCE,
    DEFAULT_FAR_DISTANCE,
    DEFAULT_NEAR_DISTANCE,
    LAMBERT,
    NO_DASH,
    NO_ROTATION,
    STANDARD,
    PHYSICAL,
    LineWidth,
    PointSize,
    DEFAULT_REFRACTION_RATIO,
    NO_ENV_ROTATION,
    NormalMapType,
    TANGENT_SPACE_NORMAL_MAP,
)
from math.euler import XYZ, XZY, YXZ, YZX, ZXY, ZYX, Euler, EulerOrder
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.utils import FLOAT32_COMPONENT
from math.spherical_harmonics3 import (
    SH_COUNT,
    SphericalHarmonics3,
    sh_from_array,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.line import Line, LineMode
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import Bone, Skeleton, bind_skeleton
from objects.skinned_mesh import ATTACHED, DETACHED, BindMode, SkinnedMesh
from objects.sprite import Sprite
from render.cube_texture import (
    SEEN_FROM_OUTSIDE,
    cube_of_panorama,
    cube_texture_from,
)
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.framebuffer import Color, FloatColor
from render.packing import BASIC_DEPTH_PACKING, DepthPacking
from render.pmrem import pmrem_from_cube
from render.png import DecodedImage
from render.raster_state import (
    ALWAYS_STENCIL_FUNC,
    KEEP_STENCIL_OP,
    LESS_EQUAL_DEPTH,
    STENCIL_MAX,
    DepthFunc,
    StencilFunc,
    StencilOp,
)
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    IGNORED,
    LINEAR_MIPMAP_LINEAR,
    LINEAR_MIPMAP_NEAREST,
    MIRROR,
    NEAREST,
    NEAREST_MIPMAP_LINEAR,
    NEAREST_MIPMAP_NEAREST,
    REPEAT,
    Alpha,
    Filter,
    Mapping,
    UvChannel,
    Wrap,
    texture_from,
)
from render.texture_store import TextureId
from std.collections import Dict
from std.math import inf, isfinite, pi, sqrt
from std.memory import bitcast
from std.pathlib import Path
from units.si import Angle, DEGREE, InverseLength, Length, METER, NANOMETER
from units.si import MILLIMETER
from units.si import PER_METER, RADIAN

# The format version `Object3D.toJSON` writes, and the one major version
# this reads.
comptime FORMAT_VERSION = Float32(4.6)
comptime FORMAT_MAJOR = 4

# three.js's texture constants, by their numbers in `constants.js`.
comptime UV_MAPPING = 300
comptime CUBE_REFLECTION_MAPPING = 301
comptime CUBE_REFRACTION_MAPPING = 302
comptime EQUIRECTANGULAR_REFLECTION_MAPPING = 303
comptime EQUIRECTANGULAR_REFRACTION_MAPPING = 304
comptime REPEAT_WRAPPING = 1000
comptime CLAMP_TO_EDGE_WRAPPING = 1001
comptime MIRRORED_REPEAT_WRAPPING = 1002
comptime NEAREST_FILTER = 1003
comptime NEAREST_MIPMAP_NEAREST_FILTER = 1004
comptime NEAREST_MIPMAP_LINEAR_FILTER = 1005
comptime LINEAR_FILTER = 1006
comptime LINEAR_MIPMAP_NEAREST_FILTER = 1007
comptime LINEAR_MIPMAP_LINEAR_FILTER = 1008
comptime UNSIGNED_BYTE_TYPE = 1009
comptime UNSIGNED_INT_TYPE = 1014
comptime FLOAT_TYPE = 1015
comptime RGBA_FORMAT = 1023
comptime RED_INTEGER_FORMAT = 1029
# three.js numbers its stencil functions from `NeverStencilFunc`, 512;
# `StencilFunc` numbers them from zero in the same order.
comptime STENCIL_FUNC_BASE = 512
# three.js's blending constants that have no `Blending` of the same number.
comptime NO_BLENDING = 0
comptime NORMAL_BLENDING = 1
comptime CUSTOM_BLENDING = 5
# three.js's two color space names this reads besides none, `""`.
comptime SRGB_COLOR_SPACE = "srgb"
comptime LINEAR_SRGB_COLOR_SPACE = "srgb-linear"
# What a `MeshPhongMaterial` has when its entry names no highlight.
comptime PHONG_SPECULAR = 0x111111
comptime PHONG_SHININESS = Float32(30)


def material_type_names() -> List[String]:
    """Return three.js's material class for each `MaterialKind`, by its
    value.

    Returns:
        Eleven names: `MeshBasicMaterial` for `BASIC` at zero through
        `MeshDistanceMaterial` for `DISTANCE` at ten.
    """
    return [
        "MeshBasicMaterial",
        "MeshLambertMaterial",
        "MeshNormalMaterial",
        "MeshDepthMaterial",
        "MeshPhongMaterial",
        "MeshToonMaterial",
        "MeshMatcapMaterial",
        "MeshStandardMaterial",
        "MeshPhysicalMaterial",
        "ShadowMaterial",
        "MeshDistanceMaterial",
    ]


def light_type_names() -> List[String]:
    """Return three.js's light class for each `LightKind`, by its value.

    Returns:
        Seven names: `AmbientLight` for `AMBIENT` at zero through
        `LightProbe` for `LIGHT_PROBE` at six.
    """
    return [
        "AmbientLight",
        "DirectionalLight",
        "PointLight",
        "HemisphereLight",
        "SpotLight",
        "RectAreaLight",
        "LightProbe",
    ]


def _position_of(names: List[String], name: String) -> Int:
    """Return where a name is in a list, or -1."""
    var found = -1
    # Every caller passes a list of four names or more.
    for at in range(len(names)):  # pragma: no branch
        if names[at] == name:
            found = at
    return found


def euler_order_of(name: String) raises -> EulerOrder:
    """Return the `EulerOrder` three.js names by a string.

    Args:
        name: `XYZ`, `YXZ`, `ZXY`, `ZYX`, `YZX` or `XZY`.

    Returns:
        The order.

    Raises:
        Error: If the name is none of the six.
    """
    var orders = [XYZ, YXZ, ZXY, ZYX, YZX, XZY]
    var at = _position_of(["XYZ", "YXZ", "ZXY", "ZYX", "YZX", "XZY"], name)
    if at < 0:
        raise Error("Object JSON: no Euler order is named " + name)
    return orders[at]


def wrap_of(code: Int) raises -> Wrap:
    """Return the `Wrap` a three.js wrapping constant names.

    Args:
        code: `RepeatWrapping`, `ClampToEdgeWrapping` or
            `MirroredRepeatWrapping`, by number.

    Returns:
        `REPEAT`, `CLAMP` or `MIRROR`.

    Raises:
        Error: If the number is none of the three.
    """
    if code < REPEAT_WRAPPING or code > MIRRORED_REPEAT_WRAPPING:
        raise Error("Object JSON: a wrap that is none of the three")
    return [REPEAT, CLAMP, MIRROR][code - REPEAT_WRAPPING]


def wrap_code(wrap: Wrap) -> Int:
    """Return the three.js wrapping constant for a valid `Wrap`.

    Args:
        wrap: `REPEAT`, `CLAMP` or `MIRROR`.

    Returns:
        Its number in three.js.
    """
    if wrap == CLAMP:
        return CLAMP_TO_EDGE_WRAPPING
    if wrap == MIRROR:
        return MIRRORED_REPEAT_WRAPPING
    return REPEAT_WRAPPING


def is_mipmap_filter(code: Int) -> Bool:
    """Return True for a three.js minification filter that reads a
    mipmap chain.

    Args:
        code: A filter constant.

    Returns:
        Whether it is one of the four `...Mipmap...` filters.
    """
    return (
        code >= NEAREST_MIPMAP_NEAREST_FILTER
        and code <= LINEAR_MIPMAP_LINEAR_FILTER
        and code != LINEAR_FILTER
    )


def _is_filter(code: Int) -> Bool:
    """Return True for any of three.js's six filter constants."""
    return code >= NEAREST_FILTER and code <= LINEAR_MIPMAP_LINEAR_FILTER


def filter_of(code: Int) raises -> Filter:
    """Return the `Filter` a three.js filter constant names.

    Args:
        code: `NearestFilter` through `LinearMipmapLinearFilter`, by number.

    Returns:
        The filter.

    Raises:
        Error: If the number is none of the six.
    """
    if not _is_filter(code):
        raise Error("Object JSON: a filter that is none of the six")
    return [
        NEAREST,
        NEAREST_MIPMAP_NEAREST,
        NEAREST_MIPMAP_LINEAR,
        BILINEAR,
        LINEAR_MIPMAP_NEAREST,
        LINEAR_MIPMAP_LINEAR,
    ][code - NEAREST_FILTER]


def filter_code(filter: Filter) -> Int:
    """Return the three.js filter constant for a valid `Filter`.

    Args:
        filter: Any of the six named filters.

    Returns:
        Its number in three.js.
    """
    if filter == NEAREST:
        return NEAREST_FILTER
    if filter == NEAREST_MIPMAP_NEAREST:
        return NEAREST_MIPMAP_NEAREST_FILTER
    if filter == NEAREST_MIPMAP_LINEAR:
        return NEAREST_MIPMAP_LINEAR_FILTER
    if filter == BILINEAR:
        return LINEAR_FILTER
    if filter == LINEAR_MIPMAP_NEAREST:
        return LINEAR_MIPMAP_NEAREST_FILTER
    return LINEAR_MIPMAP_LINEAR_FILTER


def blending_of(code: Int) raises -> Optional[Blending]:
    """Return the `Blending` a three.js blending constant names.

    Args:
        code: `NoBlending` through `MultiplyBlending`, by number.

    Returns:
        `OPAQUE` for `NoBlending`; nothing for `NormalBlending`, which
        follows `transparent` as three.js has it; and `ADDITIVE`,
        `SUBTRACTIVE` or `MULTIPLY` for the three of those names.

    Raises:
        Error: If the number is `CustomBlending`, which is not read, or
            none of the six.
    """
    if code == CUSTOM_BLENDING:
        raise Error("Object JSON: CustomBlending is not read")
    if code < NO_BLENDING or code > CUSTOM_BLENDING:
        raise Error("Object JSON: a blending that is none of the six")
    if code == NORMAL_BLENDING:
        return None
    return [OPAQUE, OPAQUE, ADDITIVE, SUBTRACTIVE, MULTIPLY][code]


def color_space_of(name: String) raises -> ColorSpace:
    """Return the `ColorSpace` a three.js color space name means.

    Args:
        name: `srgb`, `srgb-linear`, or empty for three.js's
            `NoColorSpace`.

    Returns:
        `SRGB` for the first, and `LINEAR` for the other two: neither is
        decoded when it is sampled.

    Raises:
        Error: If the name is none of the three.
    """
    if name == SRGB_COLOR_SPACE:
        return SRGB
    if name != "" and name != LINEAR_SRGB_COLOR_SPACE:
        raise Error("Object JSON: a color space that is not read: " + name)
    return LINEAR


def line_type_names() -> List[String]:
    """Return three.js's line class for each `LineMode`, by its value.

    Returns:
        Three names: `Line` for `STRIP`, `LineLoop` for `LOOP` and
        `LineSegments` for `SEGMENTS`.
    """
    return ["Line", "LineLoop", "LineSegments"]


def _shape_type_names() -> List[String]:
    """Return three.js's classes of a line, points or sprite material,
    each read as a `BASIC` material."""
    return [
        "LineBasicMaterial",
        "LineDashedMaterial",
        "PointsMaterial",
        "SpriteMaterial",
    ]


# Where each of those classes is in that list.
comptime _LINE_BASIC = 0
comptime _LINE_DASHED = 1
comptime _POINTS_MATERIAL = 2
comptime _SPRITE_MATERIAL = 3


def _stencil_op_codes() -> List[Int]:
    """Return three.js's number for each `StencilOp`, by its value: its
    WebGL constant."""
    return [0, 7680, 7681, 7682, 7683, 34055, 34056, 5386]


def stencil_op_code(op: StencilOp) raises -> Int:
    """Return the three.js stencil operation constant for a `StencilOp`.

    Args:
        op: `ZERO_STENCIL_OP` through `INVERT_STENCIL_OP`.

    Returns:
        Its number in three.js: `ZeroStencilOp` is 0, `KeepStencilOp`
        7680, and the rest are their WebGL constants.

    Raises:
        Error: If the operation is none of the eight.
    """
    if not op.is_valid():
        raise Error("Object JSON: a stencil operation that is none of eight")
    return _stencil_op_codes()[op.value]


def stencil_op_of(code: Int) raises -> StencilOp:
    """Return the `StencilOp` a three.js stencil operation constant names.

    Args:
        code: `ZeroStencilOp` through `InvertStencilOp`, by number.

    Returns:
        The operation.

    Raises:
        Error: If the number is none of the eight.
    """
    var codes = _stencil_op_codes()
    var found = -1
    for at in range(len(codes)):  # pragma: no branch
        if codes[at] == code:
            found = at
    if found < 0:
        raise Error("Object JSON: a stencil operation that is none of eight")
    return StencilOp(found)


def bind_mode_name(mode: BindMode) raises -> String:
    """Return three.js's name of a skinned mesh's bind mode.

    Args:
        mode: `ATTACHED` or `DETACHED`.

    Returns:
        `attached` or `detached`, three.js's `AttachedBindMode` and
        `DetachedBindMode`.

    Raises:
        Error: If the mode is neither of the two.
    """
    if not mode.is_valid():
        raise Error("Object JSON: a bind mode that is neither of the two")
    return "attached" if mode == ATTACHED else "detached"


def bind_mode_of(name: String) raises -> BindMode:
    """Return the `BindMode` three.js names by a string.

    Args:
        name: `attached` or `detached`.

    Returns:
        `ATTACHED` or `DETACHED`.

    Raises:
        Error: If the name is neither of the two.
    """
    if name == "attached":
        return ATTACHED
    if name != "detached":
        raise Error("Object JSON: no bind mode is named " + name)
    return DETACHED


# The cameras a document holds, or that a caller hands the writer. A camera
# is not a scene node here, so it is held beside the scene rather than in
# it, in a `CameraList`. Each one rides a node, by `attach`.
comptime ObjectCameras = CameraList


struct ObjectModel(Movable):
    """What `read_object_json` read: the node each object became, and
    the cameras."""

    var cameras: ObjectCameras
    # The node each object became, in the order they were read, and the
    # uuid of the object.
    var nodes: List[NodeId]
    var uuids: List[String]
    # The clips the objects' `animations` name, each bound below the
    # object that names it, and that object's node: `NO_PARENT` for the
    # scene. A clip two objects name is read once for each.
    var animations: List[AnimationClip]
    var animation_roots: List[NodeId]

    def __init__(out self):
        """Start with nothing read."""
        self.cameras = ObjectCameras()
        self.nodes = List[NodeId]()
        self.uuids = List[String]()
        self.animations = List[AnimationClip]()
        self.animation_roots = List[NodeId]()

    def node(self, uuid: String) raises -> NodeId:
        """Return the node the object with a uuid became.

        Args:
            uuid: The object's uuid.

        Returns:
            Its node.

        Raises:
            Error: If no object read had that uuid.
        """
        var at = _position_of(self.uuids, uuid) if len(self.uuids) > 0 else -1
        if at < 0:
            raise Error("Object JSON: no object has the uuid " + uuid)
        return self.nodes[at]


def read_object_json(
    text: String,
    mut scene: Scene,
    mut assets: Assets,
    directory: String = "",
) raises -> ObjectModel:
    """Read a three.js JSON Object document into a scene and its assets.

    Args:
        text: The document.
        scene: Where its objects go, after any nodes it holds already.
        assets: Where its geometries, materials and textures go.
        directory: Where an image named by a relative URL is read from,
            ending in `/`, or empty for the working directory.

    Returns:
        The node each object became, and its cameras.

    Raises:
        Error: If the document is refused; see the module docstring.
    """
    var loader = _Loader(parse_json(text), directory)
    var root = loader.document.root()
    if loader.document.kind(root) != OBJECT:
        raise Error("Object JSON: the document must be an object")
    loader.check_metadata()
    loader.read_textures()
    loader.read_geometries(assets)
    loader.read_materials(assets)
    var top = loader.document.get(root, "object")
    if top == NO_NODE:
        raise Error("Object JSON: the document has no object")
    loader.object(top, scene, assets)
    loader.bind_targets(scene)
    loader.bind_skeletons(scene)
    loader.read_animations(top, scene)
    var model = ObjectModel()
    swap(model, loader.model)
    return model^


def load_object_json(
    path: String, mut scene: Scene, mut assets: Assets
) raises -> ObjectModel:
    """Read a three.js JSON Object file into a scene and its assets.

    Args:
        path: The file. An image with a relative URL is read beside it.
        scene: Where its objects go.
        assets: Where its geometries, materials and textures go.

    Returns:
        What `read_object_json` returns.

    Raises:
        Error: If the file cannot be read, or anything `read_object_json`
            raises.
    """
    var directory = String(path[byte = 0 : path.rfind("/") + 1])
    return read_object_json(Path(path).read_text(), scene, assets, directory)


def decompose(mut node: Object3D, elements: List[Float32]) raises:
    """Set a node from a column-major matrix as three.js's
    `Matrix4.decompose` does.

    Args:
        node: The node.
        elements: Sixteen numbers, column by column.

    Raises:
        Error: If the matrix flattens an axis, which leaves no rotation.
    """
    var matrix = Matrix4()
    for index in range(16):  # pragma: no branch
        matrix.elements[index] = elements[index]
    var sx = _column_length(elements, 0)
    var sy = _column_length(elements, 4)
    var sz = _column_length(elements, 8)
    if matrix.determinant() < 0:
        sx = -sx
    if sx * sy * sz == 0:
        raise Error("Object JSON: a matrix that flattens an axis")
    var rotation = Matrix4()
    for row in range(3):  # pragma: no branch
        rotation.elements[row] = elements[row] / sx
        rotation.elements[4 + row] = elements[4 + row] / sy
        rotation.elements[8 + row] = elements[8 + row] / sz
    node.set_position(elements[12], elements[13], elements[14])
    node.set_quaternion(Quaternion.from_matrix(rotation))
    node.set_scale(sx, sy, sz)


def _column_length(elements: List[Float32], start: Int) -> Float32:
    """Return the length of a column's first three entries."""
    return sqrt(
        elements[start] * elements[start]
        + elements[start + 1] * elements[start + 1]
        + elements[start + 2] * elements[start + 2]
    )


def _flip_rows(mut pixels: List[UInt8], width: Int, height: Int):
    """Turn an RGBA image upside down in place."""
    var row = width * 4
    for y in range(height // 2):
        var other = height - 1 - y
        for x in range(row):  # pragma: no branch
            var held = pixels[y * row + x]
            pixels[y * row + x] = pixels[other * row + x]
            pixels[other * row + x] = held


@fieldwise_init
struct _Sampling(ImplicitlyCopyable):
    """A texture entry's `magFilter` and `minFilter`, and whether it has a
    mip chain: a mipmap `minFilter` with `generateMipmaps` on."""

    var mag_filter: Filter
    var min_filter: Filter
    var mipmapped: Bool


struct _Loader(Movable):
    """The document, the uuids of its libraries, and what is built."""

    var document: JsonDocument
    var directory: String
    var model: ObjectModel
    # Each library's uuids, to the entry's position in its array.
    var images: Dict[String, Int]
    var textures: Dict[String, Int]
    # The geometry and material each uuid was built into.
    var geometries: Dict[String, Int]
    var materials: Dict[String, Int]
    # Each texture entry built with its alpha as coverage and as nothing,
    # or `NO_TEXTURE` until a use asks for it.
    var covered: List[TextureId]
    var ignored: List[TextureId]
    # The cube texture each cube texture entry was built into, by uuid.
    var cubes: Dict[String, Int]
    # The lights that name a target, and the uuid each names.
    var aimed: List[Int]
    var targets: List[String]
    # Every uuid an object has, to refuse a second.
    var seen: Dict[String, Int]
    # The skinned mesh objects and their nodes, bound once every bone is
    # read.
    var rigged: List[Int]
    var rigged_nodes: List[NodeId]
    # For each object read, in the order of `model.nodes`: its JSON object,
    # the object it is a child of or -1, and what it became, each -1 when
    # it is not that: a mesh, a skinned mesh by its place in `rigged`, a
    # light, and a camera and the list it is in.
    var items: List[Int]
    var parents: List[Int]
    var meshes: List[Int]
    var skins: List[Int]
    var lamps: List[Int]
    var lenses: List[Int]
    var lens_slots: List[Int]
    # Where the skinned meshes start in `scene.skinned_meshes`.
    var first_skin: Int

    def __init__(out self, var document: JsonDocument, directory: String):
        self.document = document^
        self.directory = directory
        self.model = ObjectModel()
        self.images = Dict[String, Int]()
        self.textures = Dict[String, Int]()
        self.geometries = Dict[String, Int]()
        self.materials = Dict[String, Int]()
        self.covered = List[TextureId]()
        self.ignored = List[TextureId]()
        self.cubes = Dict[String, Int]()
        self.aimed = List[Int]()
        self.targets = List[String]()
        self.seen = Dict[String, Int]()
        self.rigged = List[Int]()
        self.rigged_nodes = List[NodeId]()
        self.items = List[Int]()
        self.parents = List[Int]()
        self.meshes = List[Int]()
        self.skins = List[Int]()
        self.lamps = List[Int]()
        self.lenses = List[Int]()
        self.lens_slots = List[Int]()
        self.first_skin = 0

    # --- reading values -----------------------------------------------------

    def number(
        self, node: Int, key: String, default: Float32
    ) raises -> Float32:
        """Return an object's finite number under `key`, or `default`."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return default
        var value = Float32(self.document.number(found))
        if not isfinite(value):
            raise Error("Object JSON: " + key + " must be finite")
        return value

    def integer(self, node: Int, key: String, default: Int) raises -> Int:
        """Return an object's whole number under `key`, or `default`."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return default
        return self.document.integer(found)

    def text(self, node: Int, key: String, default: String) raises -> String:
        """Return an object's string under `key`, or `default`."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return default
        return self.document.string(found)

    def flag(self, node: Int, key: String, default: Bool) raises -> Bool:
        """Return an object's boolean under `key`, or `default`."""
        var found = self.document.get(node, key)
        if found == NO_NODE:
            return default
        return self.document.boolean(found)

    def color(self, node: Int, key: String, default: Int) raises -> Color:
        """Return an object's color under `key`, a 24-bit number, or
        `default`."""
        return Color(hex=self.integer(node, key, default))

    def array(self, node: Int, key: String) raises -> Int:
        """Return an object's array under `key`, or `NO_NODE`."""
        var found = self.document.get(node, key)
        if found != NO_NODE and self.document.kind(found) != ARRAY:
            raise Error("Object JSON: " + key + " must be an array")
        return found

    def entry(self, node: Int, key: String) raises -> Int:
        """Return an object's object under `key`, or `NO_NODE`."""
        var found = self.document.get(node, key)
        if found != NO_NODE and self.document.kind(found) != OBJECT:
            raise Error("Object JSON: " + key + " must be an object")
        return found

    def numbers_of(self, list: Int) raises -> List[Float32]:
        """Return every number of an array, each finite."""
        var out = List[Float32]()
        for at in range(self.document.length(list)):
            var value = Float32(
                self.document.number(self.document.at(list, at))
            )
            if not isfinite(value):
                raise Error("Object JSON: an array holds a number not finite")
            out.append(value)
        return out^

    def numbers(
        self, node: Int, key: String, count: Int
    ) raises -> List[Float32]:
        """Return an object's array of `count` numbers under `key`, or an
        empty list when the key is absent."""
        var found = self.array(node, key)
        if found == NO_NODE:
            return List[Float32]()
        var out = self.numbers_of(found)
        if len(out) != count:
            raise Error(
                "Object JSON: "
                + key
                + " must hold "
                + String(count)
                + " numbers"
            )
        return out^

    def uuid(self, node: Int) raises -> String:
        """Return an entry's uuid, which must be there."""
        var found = self.document.get(node, "uuid")
        if found == NO_NODE:
            raise Error("Object JSON: an entry has no uuid")
        return self.document.string(found)

    # --- the libraries ------------------------------------------------------

    def check_metadata(self) raises:
        """Refuse a document that is not an Object document of version 4."""
        var metadata = self.entry(self.document.root(), "metadata")
        if metadata == NO_NODE:
            raise Error("Object JSON: the document has no metadata")
        if self.text(metadata, "type", "") != "Object":
            raise Error("Object JSON: metadata.type must be Object")
        var version = Int(self.number(metadata, "version", 0))
        if version != FORMAT_MAJOR:
            raise Error("Object JSON: only version 4 of the format is read")

    def library(self, key: String) raises -> Int:
        """Return the root's array under `key`, or `NO_NODE`."""
        return self.array(self.document.root(), key)

    def index_library(self, key: String) raises -> Dict[String, Int]:
        """Map each entry of a library to its position, by uuid."""
        var uuids = Dict[String, Int]()
        var list = self.library(key)
        if list == NO_NODE:
            return uuids^
        for at in range(self.document.length(list)):
            var item = self.document.at(list, at)
            if self.document.kind(item) != OBJECT:
                raise Error(
                    "Object JSON: a " + key + " entry must be an object"
                )
            var name = self.uuid(item)
            if name in uuids:
                raise Error("Object JSON: a uuid named twice: " + name)
            uuids[name] = at
        return uuids^

    def read_textures(mut self) raises:
        """Map each image and texture to its position, building nothing."""
        self.images = self.index_library("images")
        self.textures = self.index_library("textures")
        for _ in range(len(self.textures)):
            self.covered.append(NO_TEXTURE)
            self.ignored.append(NO_TEXTURE)

    def read_geometries(mut self, mut assets: Assets) raises:
        """Build every geometry of the library."""
        var positions = self.index_library("geometries")
        var list = self.library("geometries")
        for at in range(len(positions)):
            var item = self.document.at(list, at)
            var id = assets.geometries.add(self.geometry(item))
            self.geometries[self.uuid(item)] = id.value

    def read_materials(mut self, mut assets: Assets) raises:
        """Build every material of the library."""
        var positions = self.index_library("materials")
        var list = self.library("materials")
        for at in range(len(positions)):
            var item = self.document.at(list, at)
            var id = assets.materials.add(self.material(item, assets))
            self.materials[self.uuid(item)] = id.value

    # --- geometries ---------------------------------------------------------

    def attribute(
        self,
        node: Int,
        data: Int,
        mut shared: Dict[String, InterleavedBuffer],
    ) raises -> BufferAttribute:
        """Return one attribute: a typed array per vertex, a `Float32Array`
        per instance, or a view of an interleaved buffer.

        Args:
            node: The attribute's entry.
            data: The geometry's `data` entry, which holds the interleaved
                buffers, or `NO_NODE` outside a geometry.
            shared: The interleaved buffers built so far, by uuid, so that
                two attributes naming one share it.

        Returns:
            The attribute.

        Raises:
            Error: If the entry is not an attribute this reads.
        """
        if self.document.kind(node) != OBJECT:
            raise Error("Object JSON: an attribute must be an object")
        var size = self.integer(node, "itemSize", 0)
        if self.flag(node, "isInterleavedBufferAttribute", False):
            return BufferAttribute(
                self.interleaved(data, self.text(node, "data", ""), shared),
                size,
                self.integer(node, "offset", 0),
            )
        var component = component_of_array(self.text(node, "type", ""))
        var list = self.array(node, "array")
        if list == NO_NODE:
            raise Error("Object JSON: an attribute has no array")
        var normalized = self.flag(node, "normalized", False)
        if component != FLOAT32_COMPONENT:
            # A typed array of integers, as three.js's `getTypedArray`
            # builds it. Only a per-vertex one is read.
            if self.flag(node, "isInstancedBufferAttribute", False):
                raise Error(
                    "Object JSON: an instanced attribute is read as floats"
                )
            var stored = List[Int]()
            for at in range(self.document.length(list)):
                stored.append(self.document.integer(self.document.at(list, at)))
            return BufferAttribute(stored, size, component, normalized)
        if self.flag(node, "isInstancedBufferAttribute", False):
            return BufferAttribute(
                self.numbers_of(list),
                size,
                mesh_per_attribute=self.integer(node, "meshPerAttribute", 1),
            )
        var floats = BufferAttribute(self.numbers_of(list), size)
        floats.set_normalized(normalized)
        return floats^

    def interleaved(
        self,
        data: Int,
        uuid: String,
        mut shared: Dict[String, InterleavedBuffer],
    ) raises -> InterleavedBuffer:
        """Return the interleaved buffer a geometry's `data` names, built
        the first time it is named, as three.js's `BufferGeometryLoader`
        builds it.

        Its numbers are the `arrayBuffers` entry it names, read as the
        32-bit words of the array's bytes and taken back to floats.

        Args:
            data: The geometry's `data` entry, or `NO_NODE`.
            uuid: The buffer's uuid.
            shared: The buffers built so far, by uuid. The new one is
                added.

        Returns:
            A handle on the buffer.

        Raises:
            Error: If there is no geometry, or the buffer or its array is
                not there, is not a `Float32Array`, holds a word that is not
                32 bits or a float that is not finite, or has a stride that
                does not fit it.
        """
        if uuid in shared:
            return shared[uuid].copy()
        if data == NO_NODE:
            raise Error(
                "Object JSON: an interleaved attribute outside a geometry"
            )
        var buffers = self.entry(data, "interleavedBuffers")
        var item = NO_NODE
        if buffers != NO_NODE:
            item = self.entry(buffers, uuid)
        if item == NO_NODE:
            raise Error("Object JSON: names no interleaved buffer: " + uuid)
        if self.text(item, "type", "") != "Float32Array":
            raise Error("Object JSON: only a Float32Array buffer is read")
        var arrays = self.entry(data, "arrayBuffers")
        var words = NO_NODE
        if arrays != NO_NODE:
            words = self.array(arrays, self.text(item, "buffer", ""))
        if words == NO_NODE:
            raise Error("Object JSON: an interleaved buffer has no array")
        var numbers = List[Float32]()
        for at in range(self.document.length(words)):
            var word = self.document.integer(self.document.at(words, at))
            if word < 0 or word > 0xFFFFFFFF:
                raise Error("Object JSON: an array buffer word is 32 bits")
            var value = bitcast[DType.float32](UInt32(word))
            if not isfinite(value):
                raise Error("Object JSON: an array holds a number not finite")
            numbers.append(value)
        var stride = self.integer(item, "stride", 0)
        var buffer: InterleavedBuffer
        if self.flag(item, "isInstancedInterleavedBuffer", False):
            buffer = InterleavedBuffer(
                numbers^,
                stride,
                mesh_per_attribute=self.integer(item, "meshPerAttribute", 1),
            )
        else:
            buffer = InterleavedBuffer(numbers^, stride)
        shared[uuid] = buffer.copy()
        return buffer^

    def geometry(self, item: Int) raises -> BufferGeometry:
        """Build one geometry entry."""
        var kind = self.text(item, "type", "")
        if kind == "BoxGeometry":
            var segments = (
                self.integer(item, "widthSegments", 1)
                * self.integer(item, "heightSegments", 1)
                * self.integer(item, "depthSegments", 1)
            )
            if segments != 1:
                raise Error(
                    "Object JSON: a box is read with one segment a side"
                )
            return box(
                Length(self.number(item, "width", 1), METER),
                Length(self.number(item, "height", 1), METER),
                Length(self.number(item, "depth", 1), METER),
            )
        if kind == "PlaneGeometry":
            return plane(
                Length(self.number(item, "width", 1), METER),
                Length(self.number(item, "height", 1), METER),
                self.integer(item, "widthSegments", 1),
                self.integer(item, "heightSegments", 1),
            )
        if kind == "SphereGeometry":
            if not self.is_whole_sphere(item):
                raise Error("Object JSON: a sphere is read whole, not a part")
            return sphere(
                Length(self.number(item, "radius", 1), METER),
                self.integer(item, "widthSegments", 32),
                self.integer(item, "heightSegments", 16),
            )
        if kind != "BufferGeometry" and kind != "InstancedBufferGeometry":
            raise Error(
                "Object JSON: a geometry type that is not read: " + kind
            )
        var data = self.entry(item, "data")
        if data == NO_NODE:
            raise Error("Object JSON: a BufferGeometry has no data")
        var geometry = BufferGeometry(
            instanced=self.flag(item, "isInstancedBufferGeometry", False)
        )
        # As three.js's `BufferGeometryLoader` reads them.
        geometry.name = self.text(item, "name", "")
        var user_data = self.document.get(item, "userData")
        if user_data != NO_NODE:
            geometry.user_data = user_data_of(self.document, user_data)
        var count = self.document.get(item, "instanceCount")
        if geometry.instanced and count != NO_NODE:
            if self.document.kind(count) != NULL:
                geometry.set_instance_count(self.document.integer(count))
        var shared = Dict[String, InterleavedBuffer]()
        var attributes = self.entry(data, "attributes")
        if attributes != NO_NODE:
            for at in range(self.document.length(attributes)):
                geometry.set_attribute(
                    self.document.key(attributes, at),
                    self.attribute(
                        self.document.at(attributes, at), data, shared
                    ),
                )
        var index = self.entry(data, "index")
        if index != NO_NODE:
            var kind_of_index = self.text(index, "type", "")
            if (
                kind_of_index != "Uint16Array"
                and kind_of_index != "Uint32Array"
            ):
                raise Error("Object JSON: an index must be Uint16 or Uint32")
            var list = self.array(index, "array")
            if list == NO_NODE:
                raise Error("Object JSON: an index has no array")
            var entries = List[Int]()
            for at in range(self.document.length(list)):
                entries.append(
                    self.document.integer(self.document.at(list, at))
                )
            geometry.set_index(entries^)
        var groups = self.array(data, "groups")
        if groups != NO_NODE:
            for at in range(self.document.length(groups)):
                var group = self.document.at(groups, at)
                geometry.add_group(
                    self.integer(group, "start", 0),
                    self.integer(group, "count", 0),
                    MaterialIndex(self.integer(group, "materialIndex", 0)),
                )
        self.morph_targets(data, geometry, shared)
        return geometry^

    def is_whole_sphere(self, item: Int) raises -> Bool:
        """Return True if a sphere's four angles are three.js's defaults."""
        var phi_start = self.number(item, "phiStart", 0)
        var phi_length = self.number(item, "phiLength", Float32(2 * pi))
        var theta_start = self.number(item, "thetaStart", 0)
        var theta_length = self.number(item, "thetaLength", Float32(pi))
        return (
            phi_start == 0
            and phi_length == Float32(2 * pi)
            and theta_start == 0
            and theta_length == Float32(pi)
        )

    def morph_targets(
        self,
        data: Int,
        mut geometry: BufferGeometry,
        mut shared: Dict[String, InterleavedBuffer],
    ) raises:
        """Add a geometry's morph targets: positions, maybe normals and
        maybe colors, each position named by its `name`."""
        var morphs = self.entry(data, "morphAttributes")
        if morphs == NO_NODE:
            return
        var positions = self.array(morphs, "position")
        var normals = self.array(morphs, "normal")
        var colors = self.array(morphs, "color")
        var count = 0
        if positions != NO_NODE:
            count = self.document.length(positions)
        var with_normals = normals != NO_NODE
        if with_normals and self.document.length(normals) != count:
            raise Error("Object JSON: every morph target needs a normal")
        for at in range(count):
            var entry = self.document.at(positions, at)
            var position = self.attribute(entry, data, shared)
            # `attribute` refused an entry that is not an object.
            var name = self.text(entry, "name", "")
            if with_normals:
                geometry.add_morph_target(
                    position^,
                    self.attribute(self.document.at(normals, at), data, shared),
                    name=name,
                )
            else:
                geometry.add_morph_target(position^, name=name)
        if colors != NO_NODE:
            var tints = List[BufferAttribute]()
            for at in range(self.document.length(colors)):
                tints.append(
                    self.attribute(self.document.at(colors, at), data, shared)
                )
            geometry.set_morph_colors(tints^)
        geometry.morph_relative = self.flag(data, "morphTargetsRelative", False)

    # --- textures -----------------------------------------------------------

    def image_url(self, uuid: String) raises -> Int:
        """Return an image's `url`, a string or the array of a cube's six,
        which must be there."""
        if uuid not in self.images:
            raise Error("Object JSON: a texture names no image: " + uuid)
        var item = self.document.at(self.library("images"), self.images[uuid])
        var url = self.document.get(item, "url")
        if url == NO_NODE:
            raise Error("Object JSON: an image has no URL")
        return url

    def is_cube(self, uuid: String) raises -> Bool:
        """Return True if a texture's image is six images, which makes it
        a `CubeTexture`, as `ObjectLoader.parseTextures` decides."""
        if uuid not in self.textures:
            raise Error("Object JSON: names no texture: " + uuid)
        var item = self.document.at(
            self.library("textures"), self.textures[uuid]
        )
        var url = self.image_url(self.text(item, "image", ""))
        return self.document.kind(url) == ARRAY

    def image_bytes(self, uuid: String) raises -> List[UInt8]:
        """Return an image's file bytes, from its `data:` URL or a file."""
        var url = self.image_url(uuid)
        if self.document.kind(url) != STRING:
            raise Error("Object JSON: an image is read only from one URL")
        return self.url_bytes(self.document.string(url))

    def url_bytes(self, text: String) raises -> List[UInt8]:
        """Return the file bytes a URL names: a `data:` URL or a file."""
        if text.startswith("data:"):
            var comma = text.find(",")
            if not String(text[byte = 0 : max(comma, 0)]).endswith(";base64"):
                raise Error("Object JSON: only a base64 data URL is read")
            return decode_base64(String(text[byte = comma + 1 :]))
        if text.find(":") >= 0:
            raise Error("Object JSON: an image URL with a scheme: " + text)
        return Path(self.directory + text).read_bytes()

    def texture(
        mut self, uuid: String, alpha: Alpha, mut assets: Assets
    ) raises -> TextureId:
        """Return a texture built with an alpha mode, building it the first
        time that mode asks for it."""
        if uuid not in self.textures:
            raise Error("Object JSON: a material names no texture: " + uuid)
        var at = self.textures[uuid]
        if alpha == COVERAGE and self.covered[at] != NO_TEXTURE:
            return self.covered[at]
        if alpha == IGNORED and self.ignored[at] != NO_TEXTURE:
            return self.ignored[at]
        var item = self.document.at(self.library("textures"), at)
        # A flat image is placed by `uv` or read as a panorama; the cube
        # mappings name six images, and a PMREM is built, not loaded.
        var mapping = Mapping(self.integer(item, "mapping", UV_MAPPING))
        if mapping != Mapping(UV_MAPPING) and not (
            mapping.is_equirectangular()
        ):
            raise Error(
                "Object JSON: a flat texture's mapping is UVMapping or an"
                " equirectangular one"
            )
        var wraps = self.numbers(item, "wrap", 2)
        # three.js's `Texture` clamps unless the entry says otherwise.
        var wrap_s = CLAMP
        var wrap_t = CLAMP
        if len(wraps) == 2:
            wrap_s = wrap_of(Int(wraps[0]))
            wrap_t = wrap_of(Int(wraps[1]))
        var sampling = self.sampling(item)
        var image = decode_image(self.image_bytes(self.text(item, "image", "")))
        var built = texture_from(
            image,
            wrap_s,
            sampling.mag_filter,
            color_space_of(self.text(item, "colorSpace", "")),
            sampling.mipmapped,
            alpha,
        )
        built.wrap_t = wrap_t
        built.min_filter = sampling.min_filter
        # The rows stay as the file has them; `flip_y` says which way `v`
        # reads them, as three.js's `flipY` does.
        built.flip_y = self.flag(item, "flipY", True)
        built.mapping = mapping
        var repeat = self.numbers(item, "repeat", 2)
        if len(repeat) == 2:
            built.repeat = Vector2(repeat[0], repeat[1])
        var offset = self.numbers(item, "offset", 2)
        if len(offset) == 2:
            built.offset = Vector2(offset[0], offset[1])
        var center = self.numbers(item, "center", 2)
        if len(center) == 2:
            built.center = Vector2(center[0], center[1])
        built.rotation = Angle(self.number(item, "rotation", 0), RADIAN)
        built.anisotropy = self.integer(item, "anisotropy", 1)
        built.channel = UvChannel(self.integer(item, "channel", 0))
        built.validate()
        var id = assets.textures.add(built^)
        if alpha == COVERAGE:
            self.covered[at] = id
        else:
            self.ignored[at] = id
        return id

    def cube(
        mut self, uuid: String, prefilter: Bool, mut assets: Assets
    ) raises -> CubeTextureId:
        """Return the cube texture an entry of six images makes, building
        it the first time it is named.

        Its images are read in the OpenGL layout of three.js's
        `CubeTextureLoader`, `SEEN_FROM_OUTSIDE`, and a `flipY` of true, which
        a three.js cube does not have, turns each upside down. Its wrap is
        not read: a face is always clamped here. With `prefilter`, the cube
        gets its PMREM, as three.js's renderer prefilters a cube that a
        standard or physical surface reflects; the faces stay as they are.
        """
        if not self.is_cube(uuid):
            return self.panorama(uuid, prefilter, assets)
        var at = self.textures[uuid]
        if uuid not in self.cubes:
            var item = self.document.at(self.library("textures"), at)
            var mapping = Mapping(
                self.integer(item, "mapping", CUBE_REFLECTION_MAPPING)
            )
            if not mapping.is_cube():
                raise Error(
                    "Object JSON: a cube's mapping is CubeReflectionMapping"
                    " or CubeRefractionMapping"
                )
            var urls = self.image_url(self.text(item, "image", ""))
            if self.document.length(urls) != 6:
                raise Error("Object JSON: a cube texture has six images")
            var flip = self.flag(item, "flipY", False)
            var images = List[DecodedImage]()
            for face in range(6):  # pragma: no branch
                var image = decode_image(
                    self.url_bytes(
                        self.document.string(self.document.at(urls, face))
                    )
                )
                if flip:
                    _flip_rows(image.pixels, image.width, image.height)
                images.append(image^)
            var sampling = self.sampling(item)
            var built = cube_texture_from(
                images,
                SEEN_FROM_OUTSIDE,
                sampling.mag_filter,
                color_space_of(self.text(item, "colorSpace", "")),
                sampling.mipmapped,
            )
            built.mapping = mapping
            # Six faces, always, so the loop never runs zero times.
            for face in range(6):  # pragma: no branch
                built.faces[face].min_filter = sampling.min_filter
            built.validate()
            self.cubes[uuid] = assets.cube_textures.add(built^).value
        var id = CubeTextureId(self.cubes[uuid])
        var bare = not assets.cube_textures.get(id).is_prefiltered()
        if prefilter and bare:
            assets.cube_textures.textures[id.value] = pmrem_from_cube(
                assets.cube_textures.get(id)
            )
        return id

    def is_panorama(self, uuid: String) raises -> Bool:
        """Return True if a flat texture's entry has an equirectangular
        mapping."""
        var item = self.document.at(
            self.library("textures"), self.textures[uuid]
        )
        return Mapping(
            self.integer(item, "mapping", UV_MAPPING)
        ).is_equirectangular()

    def euler(self, item: Int, key: String) raises -> Euler:
        """Return the rotation an entry's `key` holds, as `Euler.toArray`
        writes it: three angles in radians and an order, or no turn at all
        when the entry has no such key.

        Raises:
            Error: If the array holds fewer than three numbers, or names an
                order that is none of the six.
        """
        var rotation = self.array(item, key)
        if rotation == NO_NODE:
            return NO_ENV_ROTATION
        var angles = List[Float32]()
        for at in range(3):  # pragma: no branch
            angles.append(
                Float32(self.document.number(self.document.at(rotation, at)))
            )
        var order = XYZ
        if self.document.length(rotation) > 3:
            order = euler_order_of(
                self.document.string(self.document.at(rotation, 3))
            )
        return Euler(
            Angle(angles[0], RADIAN),
            Angle(angles[1], RADIAN),
            Angle(angles[2], RADIAN),
            order,
        )

    def panorama(
        mut self, uuid: String, prefilter: Bool, mut assets: Assets
    ) raises -> CubeTextureId:
        """Return the environment a flat texture with an equirectangular
        mapping makes, building it the first time it is named: a cube that
        reads the panorama directly, as `cube_of_panorama` builds it.

        With `prefilter`, the cube gets its PMREM, as three.js's
        `WebGLCubeUVMaps` prefilters a panorama that a standard or
        physical surface reflects or a blurred background shows.
        """
        var at = self.textures[uuid]
        var item = self.document.at(self.library("textures"), at)
        var mapping = Mapping(self.integer(item, "mapping", UV_MAPPING))
        if not mapping.is_equirectangular():
            raise Error(
                "Object JSON: an envMap, environment or blurred background"
                " names a flat texture that is not equirectangular: "
                + uuid
            )
        if uuid not in self.cubes:
            var flat = self.texture(uuid, COVERAGE, assets)
            var built = cube_of_panorama(assets.textures.get(flat))
            self.cubes[uuid] = assets.cube_textures.add(built^).value
        var id = CubeTextureId(self.cubes[uuid])
        var bare = not assets.cube_textures.get(id).is_prefiltered()
        if prefilter and bare:
            assets.cube_textures.textures[id.value] = pmrem_from_cube(
                assets.cube_textures.get(id)
            )
        return id

    def sampling(self, item: Int) raises -> _Sampling:
        """Return a texture entry's two filters, each checked, and whether
        it has a mip chain."""
        var magnify = self.integer(item, "magFilter", LINEAR_FILTER)
        if magnify != NEAREST_FILTER and magnify != LINEAR_FILTER:
            raise Error("Object JSON: a magFilter that is none of the two")
        var minify = self.integer(
            item, "minFilter", LINEAR_MIPMAP_LINEAR_FILTER
        )
        if not _is_filter(minify):
            raise Error("Object JSON: a minFilter that is none of the six")
        var mipmapped = is_mipmap_filter(minify) and self.flag(
            item, "generateMipmaps", True
        )
        return _Sampling(filter_of(magnify), filter_of(minify), mipmapped)

    def map(
        mut self, item: Int, key: String, alpha: Alpha, mut assets: Assets
    ) raises -> TextureId:
        """Return the texture a material's `key` names, or `NO_TEXTURE`."""
        var found = self.document.get(item, key)
        if found == NO_NODE:
            return NO_TEXTURE
        return self.texture(self.document.string(found), alpha, assets)

    # --- materials ----------------------------------------------------------

    def material(mut self, item: Int, mut assets: Assets) raises -> Material:
        """Build one material entry."""
        var name = self.text(item, "type", "")
        var at = _position_of(material_type_names(), name)
        var shape = _position_of(_shape_type_names(), name)
        if at < 0 and shape < 0:
            raise Error(
                "Object JSON: a material type that is not read: " + name
            )
        var kind = BASIC
        if at >= 0:
            kind = MaterialKind(at)
        var plain = kind.is_data()
        var reflects = kind == BASIC or kind == LAMBERT or kind == PHONG
        var physical = kind == STANDARD or kind == PHYSICAL
        var color = Color(255, 255, 255)
        if kind == SHADOW:
            color = Color(0, 0, 0)
        # three.js's data materials have no `fog`, and are never fogged.
        var fog = Optional[Bool](None)
        if not plain:
            color = self.color(item, "color", color.hex())
            fog = self.flag(item, "fog", True)
        var specular = 0
        var shininess = Float32(0)
        if kind == PHONG:
            specular = PHONG_SPECULAR
            shininess = PHONG_SHININESS
        var reflectivity = Float32(1)
        var combine = 0
        if reflects:
            reflectivity = self.number(item, "reflectivity", 1)
            combine = self.integer(item, "combine", 0)
        var env_map_intensity = Float32(1)
        if physical:
            env_map_intensity = self.number(item, "envMapIntensity", 1)
        # three.js reads the scene's `environment` where a standard or
        # physical surface has no `envMap` of its own, and prefilters what
        # either reflects. Only a mesh class that reflects reads an
        # `envMap`: the others and the line, points and sprite classes
        # have no shader that reads one.
        var env_map = SCENE_ENVIRONMENT if physical else NO_CUBE_TEXTURE
        var named = self.document.get(item, "envMap")
        if named != NO_NODE and kind.reflects() and shape < 0:
            env_map = self.cube(self.document.string(named), physical, assets)
        # How the environment is turned, on every mesh class that has one,
        # and the refraction ratio of the three that refract.
        var env_map_rotation = NO_ENV_ROTATION
        if kind.reflects() and shape < 0:
            env_map_rotation = self.euler(item, "envMapRotation")
        var refraction_ratio = DEFAULT_REFRACTION_RATIO
        if reflects and shape < 0:
            refraction_ratio = self.number(
                item, "refractionRatio", DEFAULT_REFRACTION_RATIO
            )
        # The normal map's frame, written beside the map as three.js
        # writes it.
        var normal_map_type = TANGENT_SPACE_NORMAL_MAP
        if self.document.has(item, "normalMap"):
            normal_map_type = NormalMapType(
                self.integer(item, "normalMapType", 0)
            )
        var normal_scale = self.numbers(item, "normalScale", 2)
        if len(normal_scale) == 0:
            normal_scale = [1, 1]
        var coat_scale = self.numbers(item, "clearcoatNormalScale", 2)
        if len(coat_scale) == 0:
            coat_scale = [1, 1]
        # What three.js's line, points and sprite classes add, with their
        # defaults: a `SpriteMaterial` is built transparent.
        var line_width = DEFAULT_LINE_WIDTH
        var dash_size = NO_DASH
        var gap_size = NO_DASH
        var dash_scale = Float32(1)
        var point_size = DEFAULT_POINT_SIZE
        var size_attenuation = True
        var rotation = NO_ROTATION
        var transparent = False
        var dash_offset = NO_DASH
        if kind == BASIC:
            dash_offset = Length(self.number(item, "dashOffset", 0), METER)
        if shape == _LINE_BASIC or shape == _LINE_DASHED:
            line_width = LineWidth(pixels=self.number(item, "linewidth", 1))
        if shape == _LINE_DASHED:
            dash_size = Length(self.number(item, "dashSize", 3), METER)
            gap_size = Length(self.number(item, "gapSize", 1), METER)
            dash_scale = self.number(item, "scale", 1)
        if shape == _POINTS_MATERIAL:
            point_size = PointSize(self.number(item, "size", 1))
        if shape >= _POINTS_MATERIAL:
            size_attenuation = self.flag(item, "sizeAttenuation", True)
        if shape == _SPRITE_MATERIAL:
            rotation = Angle(self.number(item, "rotation", 0), RADIAN)
            transparent = True
        # The baked maps' numbers are read beside their map, where
        # `Material.toJSON` writes them.
        var ao_map = self.map(item, "aoMap", IGNORED, assets)
        var ao_map_intensity = Float32(1)
        if ao_map != NO_TEXTURE:
            ao_map_intensity = self.number(item, "aoMapIntensity", 1)
        var light_map = self.map(item, "lightMap", IGNORED, assets)
        var light_map_intensity = Float32(1)
        if light_map != NO_TEXTURE:
            light_map_intensity = self.number(item, "lightMapIntensity", 1)
        var film = self.numbers(item, "iridescenceThicknessRange", 2)
        if len(film) == 0:
            film = [100, 400]
        var built = Material(
            color,
            map=self.map(item, "map", COVERAGE, assets),
            side=Side(self.integer(item, "side", 0)),
            opacity=self.number(item, "opacity", 1),
            blending=blending_of(
                self.integer(item, "blending", NORMAL_BLENDING)
            ),
            kind=kind,
            emissive=self.color(item, "emissive", 0),
            emissive_intensity=self.number(item, "emissiveIntensity", 1),
            emissive_map=self.map(item, "emissiveMap", IGNORED, assets),
            vertex_colors=self.flag(item, "vertexColors", False),
            alpha_map=self.map(item, "alphaMap", IGNORED, assets),
            alpha_test=self.number(item, "alphaTest", 0),
            specular=self.color(item, "specular", specular),
            shininess=self.number(item, "shininess", shininess),
            gradient_map=self.map(item, "gradientMap", IGNORED, assets),
            matcap=self.map(item, "matcap", IGNORED, assets),
            wireframe=self.flag(item, "wireframe", False),
            transparent=self.flag(item, "transparent", transparent),
            dash_size=dash_size,
            gap_size=gap_size,
            dash_scale=dash_scale,
            point_size=point_size,
            size_attenuation=size_attenuation,
            rotation=rotation,
            env_map=env_map,
            reflectivity=reflectivity,
            combine=Combine(combine),
            roughness=self.number(item, "roughness", 1),
            metalness=self.number(item, "metalness", 0),
            roughness_map=self.map(item, "roughnessMap", IGNORED, assets),
            metalness_map=self.map(item, "metalnessMap", IGNORED, assets),
            env_map_intensity=env_map_intensity,
            normal_map=self.map(item, "normalMap", IGNORED, assets),
            normal_scale=Vector2(normal_scale[0], normal_scale[1]),
            bump_map=self.map(item, "bumpMap", IGNORED, assets),
            bump_scale=self.number(item, "bumpScale", 1),
            ior=self.number(item, "ior", 1.5),
            specular_color=self.color(item, "specularColor", 0xFFFFFF),
            specular_intensity=self.number(item, "specularIntensity", 1),
            clearcoat=self.number(item, "clearcoat", 0),
            clearcoat_roughness=self.number(item, "clearcoatRoughness", 0),
            line_width=line_width,
            dash_offset=dash_offset,
            ao_map=ao_map,
            ao_map_intensity=ao_map_intensity,
            light_map=light_map,
            light_map_intensity=light_map_intensity,
            specular_map=self.map(item, "specularMap", IGNORED, assets),
            flat_shading=self.flag(item, "flatShading", False),
            transmission=self.number(item, "transmission", 0),
            transmission_map=self.map(item, "transmissionMap", IGNORED, assets),
            thickness=Length(self.number(item, "thickness", 0), METER),
            thickness_map=self.map(item, "thicknessMap", IGNORED, assets),
            attenuation_color=self.color(item, "attenuationColor", 0xFFFFFF),
            attenuation_distance=Length(
                self.number(item, "attenuationDistance", inf[DType.float32]()),
                METER,
            ),
            dispersion=self.number(item, "dispersion", 0),
            depth_packing=DepthPacking(
                self.integer(item, "depthPacking", BASIC_DEPTH_PACKING.value)
            ),
            fog=fog,
            sheen=self.number(item, "sheen", 0),
            sheen_color=self.color(item, "sheenColor", 0),
            sheen_color_map=self.map(item, "sheenColorMap", IGNORED, assets),
            sheen_roughness=self.number(item, "sheenRoughness", 1),
            sheen_roughness_map=self.map(
                item, "sheenRoughnessMap", COVERAGE, assets
            ),
            iridescence=self.number(item, "iridescence", 0),
            iridescence_ior=self.number(item, "iridescenceIOR", 1.3),
            iridescence_thickness_minimum=Length(film[0], NANOMETER),
            iridescence_thickness_maximum=Length(film[1], NANOMETER),
            iridescence_map=self.map(item, "iridescenceMap", IGNORED, assets),
            iridescence_thickness_map=self.map(
                item, "iridescenceThicknessMap", IGNORED, assets
            ),
            anisotropy=self.number(item, "anisotropy", 0),
            anisotropy_rotation=Angle(
                self.number(item, "anisotropyRotation", 0), RADIAN
            ),
            anisotropy_map=self.map(item, "anisotropyMap", IGNORED, assets),
            specular_intensity_map=self.map(
                item, "specularIntensityMap", COVERAGE, assets
            ),
            specular_color_map=self.map(
                item, "specularColorMap", IGNORED, assets
            ),
            clearcoat_map=self.map(item, "clearcoatMap", IGNORED, assets),
            clearcoat_roughness_map=self.map(
                item, "clearcoatRoughnessMap", IGNORED, assets
            ),
            clearcoat_normal_map=self.map(
                item, "clearcoatNormalMap", IGNORED, assets
            ),
            clearcoat_normal_scale=Vector2(coat_scale[0], coat_scale[1]),
            env_map_rotation=env_map_rotation,
            refraction_ratio=refraction_ratio,
            normal_map_type=normal_map_type,
        )
        # The displacement's numbers too are read beside its map.
        var displacement = self.map(item, "displacementMap", IGNORED, assets)
        if displacement != NO_TEXTURE:
            built.set_displacement(
                displacement,
                Length(self.number(item, "displacementScale", 1), METER),
                Length(self.number(item, "displacementBias", 0), METER),
            )
        if kind == DISTANCE:
            var point = self.numbers(item, "referencePosition", 3)
            if len(point) == 3:
                built.reference_position = Vector3(point[0], point[1], point[2])
            built.near_distance = Length(
                self.number(item, "nearDistance", 1), METER
            )
            built.far_distance = Length(
                self.number(item, "farDistance", 1000), METER
            )
            built.check_data()
        self.flags(item, built)
        self.raster(item, built)
        self.clipping(item, built)
        return built^

    def flags(self, item: Int, mut material: Material) raises:
        """Set a material's fragment flags, its blend constant, its shadow
        side and whether it is visible, from the keys three.js's
        `MaterialLoader` reads, at its defaults. `raster` checks the
        blend constant; the shadow side is checked here."""
        if self.document.get(item, "shadowSide") != NO_NODE:
            material.shadow_side = Side(self.integer(item, "shadowSide", 0))
            _ = material.shadow_face()
        material.blend_color = self.color(item, "blendColor", 0)
        material.blend_alpha = self.number(item, "blendAlpha", 0)
        material.dithering = self.flag(item, "dithering", False)
        material.alpha_hash = self.flag(item, "alphaHash", False)
        material.alpha_to_coverage = self.flag(item, "alphaToCoverage", False)
        material.premultiplied_alpha = self.flag(
            item, "premultipliedAlpha", False
        )
        material.visible = self.flag(item, "visible", True)
        material.tone_mapped = self.flag(item, "toneMapped", True)

    def clipping(self, item: Int, mut material: Material) raises:
        """Set a material's own clipping planes, `clipIntersection` and
        `clipShadows`, which three.js's `Material.toJSON` does not write.

        Each plane is an object with a `normal` of three numbers and a
        `constant`, as `JSON.stringify` writes a three.js `Plane`.
        """
        var planes = List[Plane]()
        var list = self.array(item, "clippingPlanes")
        if list != NO_NODE:
            for at in range(self.document.length(list)):
                var entry = self.document.at(list, at)
                if self.document.kind(entry) != OBJECT:
                    raise Error("Object JSON: a clipping plane is an object")
                var normal = self.numbers(entry, "normal", 3)
                if len(normal) == 0:
                    raise Error("Object JSON: a clipping plane has no normal")
                planes.append(
                    Plane(
                        Vector3(normal[0], normal[1], normal[2]),
                        self.number(entry, "constant", 0),
                    )
                )
        material.set_clipping_planes(
            planes,
            self.flag(item, "clipIntersection", False),
            self.flag(item, "clipShadows", False),
        )

    def raster(self, item: Int, mut material: Material) raises:
        """Set a material's depth, stencil and polygon offset state from
        three.js's keys and defaults, and check it."""
        material.depth_func = DepthFunc(
            self.integer(item, "depthFunc", LESS_EQUAL_DEPTH.value)
        )
        material.depth_test = self.flag(item, "depthTest", True)
        material.depth_write = self.flag(item, "depthWrite", True)
        material.color_write = self.flag(item, "colorWrite", True)
        material.stencil_write = self.flag(item, "stencilWrite", False)
        material.stencil_write_mask = self.integer(
            item, "stencilWriteMask", STENCIL_MAX
        )
        material.stencil_func = StencilFunc(
            self.integer(
                item,
                "stencilFunc",
                STENCIL_FUNC_BASE + ALWAYS_STENCIL_FUNC.value,
            )
            - STENCIL_FUNC_BASE
        )
        material.stencil_ref = self.integer(item, "stencilRef", 0)
        material.stencil_func_mask = self.integer(
            item, "stencilFuncMask", STENCIL_MAX
        )
        var keep = stencil_op_code(KEEP_STENCIL_OP)
        material.stencil_fail = stencil_op_of(
            self.integer(item, "stencilFail", keep)
        )
        material.stencil_z_fail = stencil_op_of(
            self.integer(item, "stencilZFail", keep)
        )
        material.stencil_z_pass = stencil_op_of(
            self.integer(item, "stencilZPass", keep)
        )
        material.polygon_offset = self.flag(item, "polygonOffset", False)
        material.polygon_offset_factor = self.number(
            item, "polygonOffsetFactor", 0
        )
        material.polygon_offset_units = self.number(
            item, "polygonOffsetUnits", 0
        )
        _ = material.raster_state()

    # --- objects ------------------------------------------------------------

    def object(
        mut self, item: Int, mut scene: Scene, mut assets: Assets
    ) raises:
        """Read the root object: a scene's children, or one object."""
        if self.document.kind(item) != OBJECT:
            raise Error("Object JSON: an object must be an object")
        if self.text(item, "type", "") != "Scene":
            self.place(item, NO_PARENT, scene, assets)
            return
        var fog = self.entry(item, "fog")
        if fog != NO_NODE:
            var kind = self.text(fog, "type", "")
            var color = self.color(fog, "color", 0xFFFFFF)
            if kind == "Fog":
                scene.fog = linear_fog(
                    color,
                    Length(self.number(fog, "near", 1), METER),
                    Length(self.number(fog, "far", 1000), METER),
                )
            elif kind == "FogExp2":
                scene.fog = exp2_fog(
                    color,
                    InverseLength(
                        self.number(fog, "density", 0.00025), PER_METER
                    ),
                )
            else:
                raise Error("Object JSON: a fog that is not read: " + kind)
        # The background's blur, strength and turn, and the environment's
        # strength and turn, as `Scene.toJSON` writes them.
        scene.background_blurriness = self.number(
            item, "backgroundBlurriness", 0
        )
        scene.background_intensity = self.number(item, "backgroundIntensity", 1)
        scene.background_rotation = self.euler(item, "backgroundRotation")
        scene.environment_intensity = self.number(
            item, "environmentIntensity", 1
        )
        scene.environment_rotation = self.euler(item, "environmentRotation")
        scene.validate_environment()
        var background = self.document.get(item, "background")
        if background != NO_NODE:
            if self.document.kind(background) == STRING:
                var uuid = self.document.string(background)
                # A blurred background is read from its PMREM, which
                # three.js's `WebGLBackground` builds for a cube or a
                # panorama: here the panorama becomes a cube to hold one.
                var blurred = scene.background_blurriness > 0
                if self.is_cube(uuid) or (blurred and self.is_panorama(uuid)):
                    scene.background = cube_background(
                        self.cube(uuid, blurred, assets)
                    )
                else:
                    scene.background = texture_background(
                        self.texture(uuid, COVERAGE, assets)
                    )
            else:
                scene.background = color_background(
                    Color(hex=self.document.integer(background))
                )
        var environment = self.document.get(item, "environment")
        if environment != NO_NODE:
            scene.environment = self.cube(
                self.document.string(environment), True, assets
            )
        self.children(item, NO_PARENT, scene, assets)

    def children(
        mut self,
        item: Int,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Read an object's children under a node."""
        var list = self.array(item, "children")
        if list == NO_NODE:
            return
        for at in range(self.document.length(list)):
            self.place(self.document.at(list, at), parent, scene, assets)

    def transform(self, item: Int, mut node: Object3D) raises:
        """Set a node from an object's matrix, or its separate parts, and
        its `up`."""
        var up = self.numbers(item, "up", 3)
        if len(up) == 3:
            node.up = Vector3(up[0], up[1], up[2])
        var matrix = self.numbers(item, "matrix", 16)
        if len(matrix) == 16:
            node.matrix_auto_update = self.flag(item, "matrixAutoUpdate", True)
            if node.matrix_auto_update:
                decompose(node, matrix)
            else:
                for index in range(16):  # pragma: no branch
                    node.matrix.elements[index] = matrix[index]
            return
        var position = self.numbers(item, "position", 3)
        if len(position) == 3:
            node.set_position(position[0], position[1], position[2])
        if self.array(item, "rotation") != NO_NODE:
            node.set_rotation(self.euler(item, "rotation"))
        var quaternion = self.numbers(item, "quaternion", 4)
        if len(quaternion) == 4:
            node.set_quaternion(
                Quaternion(
                    quaternion[0], quaternion[1], quaternion[2], quaternion[3]
                )
            )
        var scale = self.numbers(item, "scale", 3)
        if len(scale) == 3:
            node.set_scale(scale[0], scale[1], scale[2])

    def place(
        mut self,
        item: Int,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add one object as a node under its parent, what it carries, and
        then its children."""
        if self.document.kind(item) != OBJECT:
            raise Error("Object JSON: an object must be an object")
        var uuid = self.uuid(item)
        if uuid in self.seen:
            raise Error("Object JSON: a uuid named twice: " + uuid)
        self.seen[uuid] = 0
        var kind = self.text(item, "type", "")
        var node = Object3D()
        node.name = self.text(item, "name", "")
        node.visible = self.flag(item, "visible", True)
        node.render_order = self.integer(item, "renderOrder", 0)
        var mask = self.integer(item, "layers", 1)
        if mask < 0 or mask > 0xFFFFFFFF:
            raise Error("Object JSON: layers must be a 32-bit mask")
        node.layers = Layers(UInt32(mask))
        var data = self.document.get(item, "userData")
        if data != NO_NODE:
            node.user_data = user_data_of(self.document, data)
        if kind == "Group":
            node.object_type = GROUP_TYPE
        self.transform(item, node)
        node.parent = parent
        var id = scene.add(node^)
        self.items.append(item)
        var above = -1
        for at in range(len(self.model.nodes)):
            if self.model.nodes[at] == parent:
                above = at
        self.parents.append(above)
        self.meshes.append(-1)
        self.skins.append(-1)
        self.lamps.append(-1)
        self.lenses.append(-1)
        self.lens_slots.append(-1)
        var mine = len(self.model.nodes)
        self.model.nodes.append(id)
        self.model.uuids.append(uuid)
        var light = _position_of(light_type_names(), kind)
        var line = _position_of(line_type_names(), kind)
        var culled = self.flag(item, "frustumCulled", True)
        if kind == "Mesh":
            var geometry = self.geometry_named(item)
            var list = self.material_list(item)
            var mesh: Mesh
            if len(list) > 0:
                mesh = Mesh(
                    geometry,
                    list,
                    id,
                    frustum_culled=culled,
                    cast_shadow=self.flag(item, "castShadow", False),
                    receive_shadow=self.flag(item, "receiveShadow", False),
                )
            else:
                mesh = Mesh(
                    geometry,
                    self.material_named(item),
                    id,
                    frustum_culled=culled,
                    cast_shadow=self.flag(item, "castShadow", False),
                    receive_shadow=self.flag(item, "receiveShadow", False),
                )
            mesh.update_morph_targets(assets.geometries.get(geometry))
            self.wear(item, mesh.morph_influences)
            self.meshes[mine] = len(scene.meshes)
            scene.add_mesh(mesh)
        elif kind == "InstancedMesh":
            scene.add_instanced_mesh(self.instanced(item, id))
        elif light >= 0:
            self.lamps[mine] = len(scene.lights)
            self.light(item, LightKind(light), id, mask, scene)
        elif kind == "PerspectiveCamera":
            self.lenses[mine] = len(self.model.cameras.perspective)
            self.lens_slots[mine] = PERSPECTIVE_SLOT
            self.model.cameras.perspective.append(
                self.perspective(item, id, mask)
            )
        elif kind == "OrthographicCamera":
            self.lenses[mine] = len(self.model.cameras.orthographic)
            self.lens_slots[mine] = ORTHOGRAPHIC_SLOT
            self.model.cameras.orthographic.append(
                self.orthographic(item, id, mask)
            )
        elif kind == "BatchedMesh":
            scene.add_batched_mesh(self.batched(item, id, assets))
        elif kind == "SkinnedMesh":
            # Bound once every object is read, as its bones can come after
            # it, as three.js's `bindSkeletons` does.
            self.skins[mine] = len(self.rigged)
            self.rigged.append(item)
            self.rigged_nodes.append(id)
        elif line >= 0:
            scene.add_line(
                Line(
                    self.geometry_named(item),
                    self.material_named(item),
                    id,
                    mode=LineMode(line),
                    frustum_culled=culled,
                )
            )
        elif kind == "Points":
            scene.add_points(
                Points(
                    self.geometry_named(item),
                    self.material_named(item),
                    id,
                    frustum_culled=culled,
                )
            )
        elif kind == "Sprite":
            var center = self.numbers(item, "center", 2)
            if len(center) == 0:
                center = [0.5, 0.5]
            scene.add_sprite(
                Sprite(
                    self.material_named(item),
                    id,
                    center=Vector2(center[0], center[1]),
                    frustum_culled=culled,
                )
            )
        elif (
            kind != "LOD"
            and kind != "Object3D"
            and kind != "Group"
            and kind != "Bone"
        ):
            raise Error("Object JSON: an object type that is not read: " + kind)
        self.children(item, id, scene, assets)
        # An LOD's levels name objects under it, so they are read after
        # its children, as three.js's `ObjectLoader` binds them.
        if kind == "LOD":
            self.lod(item, id, scene)

    def wear(self, item: Int, mut worn: MorphInfluences) raises:
        """Set a mesh's weights from its `morphTargetInfluences`, when the
        object names them. There is no cap on how many."""
        var list = self.array(item, "morphTargetInfluences")
        if list == NO_NODE:
            return
        var weights = self.numbers_of(list)
        for target in range(len(weights)):
            worn.set(target, weights[target])

    def lod(mut self, item: Int, id: NodeId, mut scene: Scene) raises:
        """Build an LOD from its `levels` and `autoUpdate`, three.js's
        `ObjectLoader` for an `LOD`.

        Each level names an object already read, which may be any object.
        three.js's `getObjectByProperty` finds it among the LOD's
        descendants; this finds it anywhere read before, and `add_lod`
        makes it a child of the LOD, as three.js's `addLevel` does. That
        is how a second LOD on one node reads back: this writer puts its
        levels beside it. The distance is taken as its size, as three.js's
        `addLevel` takes `Math.abs` of it.
        """
        var built = Lod(id, auto_update=self.flag(item, "autoUpdate", True))
        var levels = self.array(item, "levels")
        if levels != NO_NODE:
            for at in range(self.document.length(levels)):
                var level = self.document.at(levels, at)
                built.add_level(
                    self.model.node(self.text(level, "object", "")),
                    Length(abs(self.number(level, "distance", 0)), METER),
                    self.number(level, "hysteresis", 0),
                )
        scene.add_lod(built^)

    def batched(
        self, item: Int, id: NodeId, mut assets: Assets
    ) raises -> BatchedMesh:
        """Build a batched mesh as `ObjectLoader` does: split the joined
        geometry into the geometries its `geometryInfo` names, and place
        the instances its `instanceInfo` names from its data textures.

        An instance that is not active is left out, so the instances after
        it take lower indices than three.js gives them. One that is not
        visible is added and hidden, as three.js keeps it.
        """
        var batch = BatchedMesh(
            self.material_named(item),
            id,
            frustum_culled=self.flag(item, "frustumCulled", True),
            per_object_frustum_culled=self.flag(
                item, "perObjectFrustumCulled", True
            ),
        )
        var whole = assets.geometries.get(self.geometry_named(item)).clone()
        var infos = self.array(item, "geometryInfo")
        var instances = self.array(item, "instanceInfo")
        if infos == NO_NODE or instances == NO_NODE:
            raise Error(
                "Object JSON: a BatchedMesh needs its geometryInfo and"
                " instanceInfo"
            )
        # Each geometry, or -1 for one that is not active.
        var geometries = List[Int]()
        for at in range(self.document.length(infos)):
            var info = self.document.at(infos, at)
            var part = -1
            if self.flag(info, "active", True):
                part = assets.geometries.add(self.slice(whole, info)).value
            geometries.append(part)
        var count = self.document.length(instances)
        var matrices = self.data_texture(item, "matricesTexture")
        var colors = self.data_texture(item, "colorsTexture")
        var tinted = len(colors) > 0
        if len(matrices) < count * 16:
            raise Error(
                "Object JSON: a BatchedMesh's matricesTexture must hold every"
                " instance"
            )
        if tinted and len(colors) < count * 4:
            raise Error(
                "Object JSON: a BatchedMesh's colorsTexture must hold every"
                " instance"
            )
        for at in range(count):
            var info = self.document.at(instances, at)
            if not self.flag(info, "active", True):
                continue
            var which = self.integer(info, "geometryIndex", -1)
            var named = which >= 0 and which < len(geometries)
            if not named:
                raise Error("Object JSON: an instance names no geometry")
            if geometries[which] < 0:
                raise Error("Object JSON: an instance names no active geometry")
            var matrix = Matrix4()
            for element in range(16):  # pragma: no branch
                matrix.elements[element] = matrices[at * 16 + element]
            var index = batch.add_instance(
                GeometryId(geometries[which]), matrix
            )
            batch.set_visible_at(index, self.flag(info, "visible", True))
            if tinted:
                batch.set_color_at(
                    index,
                    FloatColor(
                        colors[at * 4], colors[at * 4 + 1], colors[at * 4 + 2]
                    ).encode(),
                )
        return batch^

    def slice(self, whole: BufferGeometry, info: Int) raises -> BufferGeometry:
        """Return the part of a batch's joined geometry a `geometryInfo`
        entry names, its index counted from its own first vertex."""
        var start = self.integer(info, "vertexStart", 0)
        var count = self.integer(info, "vertexCount", 0)
        var inside = (
            start >= 0 and count >= 0 and start + count <= whole.vertex_count()
        )
        if not inside:
            raise Error(
                "Object JSON: a geometryInfo outside the joined geometry"
            )
        var part = BufferGeometry()
        # `vertex_count` above refuses a geometry with no positions.
        for slot in range(len(whole.names)):  # pragma: no branch
            var size = whole.values[slot].item_size
            var packed = whole.values[slot].packed()
            var numbers = List[Float32]()
            numbers.extend(Span(packed)[start * size : (start + count) * size])
            part.set_attribute(
                whole.names[slot], BufferAttribute(numbers^, size)
            )
        if not whole.is_indexed():
            return part^
        var first = self.integer(info, "indexStart", 0)
        var entries = self.integer(info, "indexCount", 0)
        var covered = (
            first >= 0 and entries >= 0 and first + entries <= len(whole.index)
        )
        if not covered:
            raise Error("Object JSON: a geometryInfo outside the joined index")
        var index = List[Int]()
        for at in range(first, first + entries):
            var entry = whole.index[at] - start
            var own = entry >= 0 and entry < count
            if not own:
                raise Error("Object JSON: a batched index outside its geometry")
            index.append(entry)
        part.set_index(index^)
        return part^

    def data_texture(self, item: Int, key: String) raises -> List[Float32]:
        """Return the numbers of the `Float32Array` image of the data
        texture an object's `key` holds, or none when the key is absent."""
        var entry = self.entry(item, key)
        if entry == NO_NODE:
            return List[Float32]()
        var uuid = self.uuid(entry)
        if uuid not in self.textures:
            raise Error("Object JSON: names no texture: " + uuid)
        var texture = self.document.at(
            self.library("textures"), self.textures[uuid]
        )
        var image = self.text(texture, "image", "")
        if image not in self.images:
            raise Error("Object JSON: a texture names no image: " + image)
        var url = self.entry(
            self.document.at(self.library("images"), self.images[image]),
            "url",
        )
        if url == NO_NODE or self.text(url, "type", "") != "Float32Array":
            raise Error(
                "Object JSON: a data texture's image must hold a Float32Array"
            )
        var data = self.array(url, "data")
        if data == NO_NODE:
            raise Error("Object JSON: a data texture's image has no data")
        return self.numbers_of(data)

    def geometry_named(self, item: Int) raises -> GeometryId:
        """Return the geometry an object's `geometry` uuid names."""
        var uuid = self.text(item, "geometry", "")
        if uuid not in self.geometries:
            raise Error("Object JSON: an object names no geometry: " + uuid)
        return GeometryId(self.geometries[uuid])

    def material_list(self, item: Int) raises -> List[MaterialId]:
        """Return the materials a mesh's `material` array names, three.js's
        `getMaterial` over an array, or none when it names one material.

        Args:
            item: The object.

        Returns:
            The materials, in order, or none.

        Raises:
            Error: If the array is empty, or an entry names no material.
        """
        var list = List[MaterialId]()
        var found = self.document.get(item, "material")
        if found == NO_NODE or self.document.kind(found) != ARRAY:
            return list^
        var count = self.document.length(found)
        if count == 0:
            raise Error("Object JSON: a mesh with an empty material list")
        for at in range(count):  # pragma: no branch
            var uuid = self.document.string(self.document.at(found, at))
            if uuid not in self.materials:
                raise Error("Object JSON: an object names no material: " + uuid)
            list.append(MaterialId(self.materials[uuid]))
        return list^

    def material_named(self, item: Int) raises -> MaterialId:
        """Return the one material an object's `material` uuid names.

        Only a mesh reads a list of materials; see `material_list`.
        """
        var found = self.document.get(item, "material")
        if found != NO_NODE and self.document.kind(found) == ARRAY:
            raise Error(
                "Object JSON: only a mesh can have more than one material"
            )
        var uuid = self.text(item, "material", "")
        if uuid not in self.materials:
            raise Error("Object JSON: an object names no material: " + uuid)
        return MaterialId(self.materials[uuid])

    def instanced(self, item: Int, id: NodeId) raises -> InstancedMesh:
        """Build an instanced mesh and place its instances."""
        var count = self.integer(item, "count", 0)
        var mesh = InstancedMesh(
            self.geometry_named(item),
            self.material_named(item),
            id,
            count,
            frustum_culled=self.flag(item, "frustumCulled", True),
        )
        var matrices = self.entry(item, "instanceMatrix")
        if matrices == NO_NODE:
            raise Error("Object JSON: an InstancedMesh has no instanceMatrix")
        var none = Dict[String, InterleavedBuffer]()
        var attribute = self.attribute(matrices, NO_NODE, none)
        if attribute.item_size != 16 or attribute.count() != count:
            raise Error("Object JSON: an instanceMatrix of count matrices")
        for index in range(count):
            var matrix = Matrix4()
            for element in range(16):  # pragma: no branch
                matrix.elements[element] = attribute.component(index, element)
            mesh.set_matrix_at(index, matrix)
        return mesh^

    def light(
        mut self,
        item: Int,
        kind: LightKind,
        id: NodeId,
        mask: Int,
        mut scene: Scene,
    ) raises:
        """Build a light on a node, and note the target it names."""
        var color = self.color(item, "color", 0xFFFFFF)
        var intensity = self.number(item, "intensity", 1)
        var distance = self.number(item, "distance", 0)
        var decay = self.number(item, "decay", 2)
        var built: Light
        if kind == AMBIENT:
            built = ambient_light(color, intensity)
            built.node = id
        elif kind == DIRECTIONAL:
            built = directional_light(color, id, intensity)
        elif kind == POINT:
            built = point_light(color, id, intensity, decay, distance)
        elif kind == HEMISPHERE:
            built = hemisphere_light(
                color, self.color(item, "groundColor", 0xFFFFFF), id, intensity
            )
        elif kind == LIGHT_PROBE:
            # three.js's `LightProbe.toJSON` writes its 27 numbers as `sh`;
            # a probe without them is darkness, as a new one is.
            var sh = SphericalHarmonics3()
            var numbers = self.numbers(item, "sh", SH_COUNT * 3)
            if len(numbers) > 0:
                sh = sh_from_array(numbers)
            built = light_probe(sh, intensity)
            built.node = id
        elif kind == SPOT:
            built = spot_light(
                color,
                id,
                intensity,
                distance,
                Angle(self.number(item, "angle", Float32(pi / 3)), RADIAN),
                self.number(item, "penumbra", 0),
                decay,
            )
        else:
            built = rect_area_light(
                color,
                id,
                intensity,
                Length(self.number(item, "width", 10), METER),
                Length(self.number(item, "height", 10), METER),
            )
        built.layers = Layers(UInt32(mask))
        built.cast_shadow = self.flag(item, "castShadow", False)
        var shadow = self.entry(item, "shadow")
        if shadow != NO_NODE:
            built.shadow.bias = self.number(shadow, "bias", 0)
            built.shadow.normal_bias = self.number(shadow, "normalBias", 0)
            built.shadow.radius = self.number(shadow, "radius", 1)
            built.shadow.intensity = self.number(shadow, "intensity", 1)
            var size = self.numbers(shadow, "mapSize", 2)
            if len(size) == 2:
                if size[0] != size[1]:
                    raise Error("Object JSON: a shadow map must be square")
                built.shadow.map_size = Int(size[0])
            var camera = self.entry(shadow, "camera")
            if camera != NO_NODE:
                built.shadow.near = Length(
                    self.number(camera, "near", 0.5), METER
                )
                built.shadow.far = Length(
                    self.number(camera, "far", 500), METER
                )
                built.shadow.left = Length(
                    self.number(camera, "left", -5), METER
                )
                built.shadow.right = Length(
                    self.number(camera, "right", 5), METER
                )
                built.shadow.top = Length(self.number(camera, "top", 5), METER)
                built.shadow.bottom = Length(
                    self.number(camera, "bottom", -5), METER
                )
            # Asked whether the light casts or not: a shadow a document
            # gives is refused here, not when a later edit turns it on.
            built.shadow.validate()
        built.validate()
        var target = self.document.get(item, "target")
        if target != NO_NODE:
            self.aimed.append(len(scene.lights))
            self.targets.append(self.document.string(target))
        scene.add_light(built)

    def perspective(
        self, item: Int, id: NodeId, mask: Int
    ) raises -> PerspectiveCamera:
        """Build a perspective camera riding a node, with three.js's zoom,
        focus, film and view. The film is in millimeters, three.js's
        convention."""
        var camera = PerspectiveCamera(
            Angle(self.number(item, "fov", 50), DEGREE),
            self.number(item, "aspect", 1),
            Length(self.number(item, "near", 0.1), METER),
            Length(self.number(item, "far", 2000), METER),
        )
        camera.zoom = self.number(item, "zoom", 1)
        camera.focus = Length(self.number(item, "focus", 10), METER)
        camera.film_gauge = Length(
            self.number(item, "filmGauge", 35), MILLIMETER
        )
        camera.film_offset = Length(
            self.number(item, "filmOffset", 0), MILLIMETER
        )
        camera.view = self.view_offset(item)
        camera.validate()
        camera.attach(id)
        camera.layers = Layers(UInt32(mask))
        return camera

    def view_offset(self, item: Int) raises -> Optional[ViewOffset]:
        """Return a camera's `view`, checked, or None when it has none.

        three.js copies the object as it is, so a key left out is
        `undefined`: `enabled` then reads as false, and a number as the
        one three.js's `setViewOffset` starts from.
        """
        var found = self.document.get(item, "view")
        if found == NO_NODE or self.document.is_null(found):
            return None
        var view = self.entry(item, "view")
        var tile = ViewOffset(
            self.flag(view, "enabled", False),
            self.number(view, "fullWidth", 1),
            self.number(view, "fullHeight", 1),
            self.number(view, "offsetX", 0),
            self.number(view, "offsetY", 0),
            self.number(view, "width", 1),
            self.number(view, "height", 1),
        )
        tile.validate()
        return tile

    def orthographic(
        self, item: Int, id: NodeId, mask: Int
    ) raises -> OrthographicCamera:
        """Build an orthographic camera riding a node."""
        var camera = OrthographicCamera(
            Length(self.number(item, "left", -1), METER),
            Length(self.number(item, "right", 1), METER),
            Length(self.number(item, "top", 1), METER),
            Length(self.number(item, "bottom", -1), METER),
            Length(self.number(item, "near", 0.1), METER),
            Length(self.number(item, "far", 2000), METER),
        )
        camera.zoom = self.number(item, "zoom", 1)
        camera.view = self.view_offset(item)
        camera.attach(id)
        camera.layers = Layers(UInt32(mask))
        return camera^

    def read_animations(mut self, top: Int, scene: Scene) raises:
        """Read the clips each object's `animations` names, three.js's
        `ObjectLoader.parseAnimations` and `getAnimations`, and bind each
        track below the object that names the clip."""
        var library = self.index_library("animations")
        var list = self.library("animations")
        var roots: List[Int] = [-1]
        var owners: List[Int] = [top]
        for at in range(len(self.items)):
            roots.append(at)
            owners.append(self.items[at])
        if self.text(top, "type", "") != "Scene":
            # The root object is the first object read, not the scene.
            _ = roots.pop(0)
            _ = owners.pop(0)
        # The scene, or the root object, which is the first read.
        for at in range(len(roots)):  # pragma: no branch
            var named = self.array(owners[at], "animations")
            if named == NO_NODE:
                continue
            for index in range(self.document.length(named)):
                var uuid = self.document.string(self.document.at(named, index))
                if uuid not in library:
                    raise Error(
                        "Object JSON: no animation has the uuid " + uuid
                    )
                var clip = self.document.at(list, library[uuid])
                var names = track_names(self.document, clip)
                var targets = List[Optional[TrackTarget]]()
                for track in range(len(names)):
                    targets.append(
                        self.track_target(
                            roots[at], owners[at], names[track], scene
                        )
                    )
                var read = read_clip(self.document, clip, targets)
                if not Bool(read):
                    continue
                self.model.animations.append(read.take())
                self.model.animation_roots.append(
                    NO_PARENT if roots[at] < 0 else self.model.nodes[roots[at]]
                )

    def find_object(
        self, root: Int, owner: Int, name: String, scene: Scene
    ) raises -> Int:
        """Return the object a track's node name names below a root,
        three.js's `PropertyBinding.findNode`: the root itself for no name
        or its own name or uuid, then a bone of the root's skeleton by name,
        then the first object below it, depth first, by name or uuid.

        Returns:
            The object's place in `model.nodes`, -1 for the scene, or -2
            when nothing has the name.
        """
        if (
            name == ""
            or name == "."
            or name == self.text(owner, "name", "")
            or name == self.text(owner, "uuid", "")
        ):
            return root
        if root >= 0 and self.skins[root] >= 0:
            var skin = self.first_skin + self.skins[root]
            # A skeleton has at least one bone; `Skeleton` refuses none.
            ref bones = scene.skinned_meshes[skin].skeleton.bones
            for bone in bones:  # pragma: no branch
                if scene.get(bone.node).name == name:
                    return self.object_of(bone.node)
        return self.search_below(root, name)

    def object_of(self, node: NodeId) -> Int:
        """Return the place in `model.nodes` of an object's node, which
        the caller knows is there."""
        var found = -1
        for at in range(len(self.model.nodes)):  # pragma: no branch
            if self.model.nodes[at] == node:
                found = at
        return found

    def search_below(self, root: Int, name: String) raises -> Int:
        """Return the first object below `root`, depth first and in
        document order, whose name or uuid is `name`, or -2."""
        for at in range(len(self.parents)):
            if self.parents[at] != root:
                continue
            var item = self.items[at]
            if (
                self.text(item, "name", "") == name
                or self.model.uuids[at] == name
            ):
                return at
            var below = self.search_below(at, name)
            if below != -2:
                return below
        return -2

    def track_target(
        self, root: Int, owner: Int, name: String, scene: Scene
    ) raises -> Optional[TrackTarget]:
        """Return what a track's name drives below a root, or None when
        three.js would bind it to nothing: no object has the node's name,
        or the object has no such property, material or bone.

        A `morphTargetInfluences` with no index is every morph target, as
        a glTF clip's weights track is: the target's slot is -1, and
        `read_clip` makes a track per target.
        """
        var path = parse_track_name(name)
        var kind = property_kind(path)
        var at = self.find_object(root, owner, path.node_name, scene)
        if at == -2:
            return None
        if at == -1:
            raise Error("Object JSON: a track on the scene itself is not read")
        if path.object_name == "bones":
            if self.skins[at] < 0:
                return None
            var skin = self.first_skin + self.skins[at]
            # A skeleton has at least one bone; `Skeleton` refuses none.
            ref bones = scene.skinned_meshes[skin].skeleton.bones
            for bone in bones:  # pragma: no branch
                if scene.get(bone.node).name == path.object_index:
                    return node_target(bone.node, kind)
            return None
        if path.object_name == "material":
            var item = self.items[at]
            if self.document.get(item, "material") == NO_NODE:
                return None
            return material_target(self.material_named(item), kind)
        if kind.is_morph():
            var slot = -1
            if path.property_index != "":
                slot = atol(path.property_index)
                if slot < 0:
                    raise Error(
                        "Object JSON: a morph target index cannot be negative"
                    )
            if self.meshes[at] >= 0:
                return TrackTarget(MORPH_INFLUENCE, self.meshes[at], slot)
            if self.skins[at] >= 0:
                return TrackTarget(
                    SKINNED_MORPH_INFLUENCE,
                    self.first_skin + self.skins[at],
                    slot,
                )
            return None
        if kind.is_light():
            if self.lamps[at] < 0:
                return None
            return light_target(LightIndex(self.lamps[at]), kind)
        if kind.is_camera():
            if self.lenses[at] < 0:
                return None
            if self.lens_slots[at] == ORTHOGRAPHIC_SLOT:
                if kind == CAMERA_FOV:
                    return None
                return orthographic_camera_target(
                    OrthographicCameraIndex(self.lenses[at]), kind
                )
            return perspective_camera_target(
                PerspectiveCameraIndex(self.lenses[at]), kind
            )
        return node_target(self.model.nodes[at], kind)

    def bind_targets(self, mut scene: Scene) raises:
        """Point each light that names a target at that object's node, or
        at the origin when the target is not in the document."""
        for at in range(len(self.aimed)):
            var target = NO_PARENT
            var found = _position_of(self.model.uuids, self.targets[at])
            if found >= 0:
                target = self.model.nodes[found]
            scene.lights[self.aimed[at]].target = target

    def bind_skeletons(mut self, mut scene: Scene) raises:
        """Build each skinned mesh on its skeleton, as three.js's
        `bindSkeletons` binds it once every bone is read.

        A skeleton's bones are the objects its `bones` name, and their
        inverse binds are its `boneInverses`. A skeleton that leaves them
        out, or gives none, gets the inverse of each bone's world matrix,
        as three.js's `Skeleton.calculateInverses` works them out.
        """
        var skeletons = self.index_library("skeletons")
        var list = self.library("skeletons")
        self.first_skin = len(scene.skinned_meshes)
        if len(self.rigged) > 0:
            # The bones' world matrices, for a skeleton without inverses.
            scene.update()
        for at in range(len(self.rigged)):
            var item = self.rigged[at]
            var uuid = self.text(item, "skeleton", "")
            if uuid not in skeletons:
                raise Error("Object JSON: a SkinnedMesh names no skeleton")
            var entry = self.document.at(list, skeletons[uuid])
            var bones = self.array(entry, "bones")
            if bones == NO_NODE:
                raise Error("Object JSON: a skeleton has no bones")
            var inverses = self.array(entry, "boneInverses")
            var count = self.document.length(bones)
            var given = 0
            if inverses != NO_NODE:
                given = self.document.length(inverses)
            # three.js's `Skeleton.fromJSON` reads one inverse for each
            # bone and ignores the rest. A short list fails there, reading
            # a matrix from nothing; here it is refused.
            if given != 0 and given < count:
                raise Error(
                    "Object JSON: a skeleton needs one of boneInverses for"
                    " each of its bones, or none"
                )
            var nodes = List[NodeId]()
            var placed = List[Matrix4]()
            var built = List[Bone]()
            for bone in range(count):
                var node = self.model.node(
                    self.document.string(self.document.at(bones, bone))
                )
                nodes.append(node)
                placed.append(scene.world_matrix(node))
                if given > 0:
                    var inverse = self.document.at(inverses, bone)
                    if self.document.kind(inverse) != ARRAY:
                        raise Error(
                            "Object JSON: a bone inverse must be an array"
                        )
                    var numbers = self.numbers_of(inverse)
                    if len(numbers) != 16:
                        raise Error("Object JSON: a bone inverse is 16 numbers")
                    built.append(Bone(node, _matrix_of(numbers)))
            var skeleton = bind_skeleton(
                nodes, placed
            ) if given == 0 else Skeleton(built^)
            var bind = Matrix4()
            var elements = self.numbers(item, "bindMatrix", 16)
            if len(elements) == 16:
                bind = _matrix_of(elements)
            var mesh = SkinnedMesh(
                self.geometry_named(item),
                self.material_named(item),
                self.rigged_nodes[at],
                skeleton^,
                bind^,
                bind_mode=bind_mode_of(self.text(item, "bindMode", "attached")),
                frustum_culled=self.flag(item, "frustumCulled", True),
            )
            self.wear(item, mesh.morph_influences)
            scene.add_skinned_mesh(mesh^)


def _matrix_of(elements: List[Float32]) -> Matrix4:
    """Return the matrix of sixteen numbers, column by column."""
    var matrix = Matrix4()
    for index in range(16):  # pragma: no branch
        matrix.elements[index] = elements[index]
    return matrix^
