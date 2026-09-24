# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An FBX file's meshes, materials, textures, model hierarchy, cameras
and lights, read into a `Scene` and an `Assets`: three.js's `FBXLoader`
and its `FBXTreeParser` and `GeometryParser`.

**What an FBX file is.** `loaders.fbx_tree` reads the file, ASCII or
binary, into a tree. Its `Objects` node holds every object -- `Model`,
`Geometry`, `Material`, `Texture`, `Video`, `NodeAttribute` -- each with
a 64-bit id, and its `Connections` node joins them: a geometry to the
model that draws it, a material to a model, a texture to a material
under the name of the map it is, a model to its parent model. A value an
object carries by name is a `P` entry of its `Properties70`.

**What maps to what.** A `Model` becomes an `Object3D` under its parent
model, at the transform three.js's `generateTransform` works out from
its translation, pre-rotation, rotation, post-rotation, scale, pivots,
offsets and inherit type. A `Mesh` model draws its geometry with the
materials connected to it: the geometry's polygons, cut into triangles,
with the normals, the first set of texture coordinates and the vertex
colors its layer elements give, moved by the model's geometric
transform. A `Material` becomes a `PHONG` or a `LAMBERT` material, as
three.js makes a `MeshPhongMaterial` or a `MeshLambertMaterial`. A
`Camera` model rides a `PerspectiveCamera`; a `Light` model carries a
point, directional or spot light.

**One geometry, a group per material run.** Each FBX geometry is one
geometry, with a group per run of polygons of one material index, as
three.js's `genGeometry` adds them. A layer mapped `AllSame` writes no
group. A model with more than one material connected is one `Mesh` that
wears them as a list, in the order they are connected, and a group draws
with the material its index names. A group whose index is past the
materials connected draws nothing, and a list with no group draws nothing,
as in three.js. A model with one material wears it over every polygon.
A skinned model with more than one is cut into a `SkinnedMesh` a group,
because a skinned mesh here wears one material. A geometry with no
polygon gets no mesh; three.js adds a mesh of nothing.

**Skins and blend shapes.** A `Skin` deformer on a geometry makes each
mesh that draws it a `SkinnedMesh`, as three.js's `parseDeformers`,
`buildSkeleton` and `bindSkeleton` bind it. Each `Cluster` of the skin is
a bone: the model connected to it. The inverse of its `TransformLink` is
the bone's inverse bind, and its `Indexes` and `Weights` are the
`skinIndex` and `skinWeight` of the vertices. A vertex with more than four
weights keeps its four largest, and the weights are normalized. The mesh
model's matrix in a `BindPose` is the bind matrix, or the identity when
there is none. A `BlendShape` deformer's channels are morph targets, held
as offsets, so `morph_relative` is set, and named by the channel. A
geometry of more than `MAX_MORPH_TARGETS` targets is refused: a mesh here
wears at most that many. `loaders.fbx_animation` reads the animation
stacks into clips.

**Not ported.** NURBS curves, a
`LookAtProperty`, an orthographic camera, layered textures past their
first layer, a second set of texture coordinates, and the ambient
occlusion, displacement, reflection and specular maps.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    MORPH_INFLUENCE,
    SKINNED_MORPH_INFLUENCE,
    TrackTarget,
)
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
    MaterialIndex,
)
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import (
    ambient_light,
    directional_light,
    point_light,
    spot_light,
)
from loaders.fbx_tree import (
    FBX_BYTES,
    FBX_STRING,
    NO_FBX_NODE,
    FbxDocument,
    FbxFormat,
    object_name,
    parse_fbx,
)
from loaders.fbx_animation import FbxAnimatedModel, read_fbx_animations
from loaders.gltf import decode_base64
from loaders.model_nodes import (
    authored_color,
    compose,
    decompose_onto,
    texture_from_bytes,
    texture_from_file,
)
from materials.material import (
    LAMBERT,
    NO_TEXTURE,
    PHONG,
    Material,
    MaterialId,
    MaterialKind,
)
from math.euler import XYZ, XZY, YXZ, YZX, ZXY, ZYX, Euler, EulerOrder
from math.matrix4 import Matrix4, scaling, translation
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import (
    SKIN_INDEX,
    SKIN_WEIGHT,
    SkinnedMesh,
    normalized_skin_weights,
)
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB, ColorSpace, srgb_to_linear
from render.texture import CLAMP, COVERAGE, IGNORED, REPEAT, Alpha
from render.texture_store import TextureId
from std.math import atan, pi
from std.pathlib import Path
from units.si import CENTIMETER, DEGREE, METER, Angle, Length

# How deep the model hierarchy can go. The models are placed by
# recursion, parent first.
comptime MAX_MODEL_DEPTH = 1024
# three.js's defaults for an FBX camera that leaves a number out.
comptime DEFAULT_FOV_DEGREES = Float64(45)
comptime DEFAULT_NEAR_PLANE = Float64(1)
comptime DEFAULT_FAR_PLANE = Float64(1000)
# three.js's `PerspectiveCamera.filmGauge`, which `setFocalLength` reads.
comptime FILM_GAUGE = Float64(35)
# The color three.js gives a mesh with no material connected.
comptime UNMATERIALED = Color(204, 204, 204)
comptime _WHITE = Color(255, 255, 255)


@fieldwise_init
struct FbxMapping(Equatable, ImplicitlyCopyable, Writable):
    """How a layer element's values are laid over a mesh, as a type
    rather than a bare int: FBX's `MappingInformationType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four mappings there are."""
        return (
            self == BY_POLYGON_VERTEX
            or self == BY_POLYGON
            or self == BY_VERTEX
            or self == ALL_SAME
        )


# One value per corner of every polygon: `ByPolygonVertex`.
comptime BY_POLYGON_VERTEX = FbxMapping(0)
# One value per polygon: `ByPolygon`.
comptime BY_POLYGON = FbxMapping(1)
# One value per position: `ByVertice`, or `ByVertex`.
comptime BY_VERTEX = FbxMapping(2)
# One value for the whole mesh: `AllSame`.
comptime ALL_SAME = FbxMapping(3)


@fieldwise_init
struct FbxReference(Equatable, ImplicitlyCopyable, Writable):
    """Whether a layer element's values are read directly or through an
    index, as a type rather than a bare int: FBX's
    `ReferenceInformationType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two references there are."""
        return self == DIRECT or self == INDEX_TO_DIRECT


# The mapping picks a value: `Direct`.
comptime DIRECT = FbxReference(0)
# The mapping picks an index, and the index picks a value:
# `IndexToDirect`, or the older `Index`.
comptime INDEX_TO_DIRECT = FbxReference(1)


struct FbxLayer(Copyable, Movable):
    """A layer element of a geometry: normals, texture coordinates, vertex
    colors or material indices, and how they are laid over the mesh."""

    var mapping: FbxMapping
    var reference: FbxReference
    var values: List[Float64]
    var indices: List[Int]
    # How many values make one: three for a normal, two for a texture
    # coordinate, four for a color, one for a material index.
    var size: Int

    def __init__(
        out self,
        mapping: FbxMapping,
        reference: FbxReference,
        var values: List[Float64],
        var indices: List[Int],
        size: Int,
    ):
        """Bundle a layer.

        Args:
            mapping: How the values are laid over the mesh.
            reference: Whether they are read through `indices`.
            values: The values, `size` at a time.
            indices: The index into the values, for `INDEX_TO_DIRECT`.
            size: How many values make one.
        """
        self.mapping = mapping
        self.reference = reference
        self.values = values^
        self.indices = indices^
        self.size = size

    def start(self, corner: Int, polygon: Int, vertex: Int) raises -> Int:
        """Return where the value for one polygon corner begins in
        `values`, as three.js's `getData` finds it.

        Args:
            corner: The corner's place among every polygon's corners.
            polygon: Which polygon it is a corner of.
            vertex: Which position it is.

        Returns:
            The index of the value's first number.

        Raises:
            Error: If the mapping or the reference is none of its named
                constants, or an index is outside what it indexes.
        """
        if not self.mapping.is_valid() or not self.reference.is_valid():
            raise Error("FBX: a layer mapping or reference that is not known")
        var index: Int
        if self.mapping == BY_POLYGON_VERTEX:
            index = corner
        elif self.mapping == BY_POLYGON:
            index = polygon
        elif self.mapping == BY_VERTEX:
            index = vertex
        else:
            # three.js reads `indices[0]` for `AllSame`, which a direct
            # layer does not have; its first value is meant.
            index = 0
            if len(self.indices) > 0:
                index = self.indices[0]
        if self.reference == INDEX_TO_DIRECT:
            if index < 0 or index >= len(self.indices):
                raise Error("FBX: a layer index outside its index array")
            index = self.indices[index]
        var begin = index * self.size
        if index < 0 or begin + self.size > len(self.values):
            raise Error("FBX: a layer index outside its values")
        return begin


def fbx_mapping(name: String) raises -> FbxMapping:
    """Return the mapping a `MappingInformationType` names.

    Args:
        name: `ByPolygonVertex`, `ByPolygon`, `ByVertice`, `ByVertex` or
            `AllSame`.

    Returns:
        The mapping.

    Raises:
        Error: If the name is none of those.
    """
    if name == "ByPolygonVertex":
        return BY_POLYGON_VERTEX
    if name == "ByPolygon":
        return BY_POLYGON
    if name == "ByVertice" or name == "ByVertex":
        return BY_VERTEX
    if name == "AllSame":
        return ALL_SAME
    raise Error("FBX: a mapping that is not known: " + name)


def fbx_reference(name: String) raises -> FbxReference:
    """Return the reference a `ReferenceInformationType` names.

    Args:
        name: `Direct`, `IndexToDirect` or `Index`.

    Returns:
        The reference.

    Raises:
        Error: If the name is none of those.
    """
    if name == "Direct":
        return DIRECT
    if name == "IndexToDirect" or name == "Index":
        return INDEX_TO_DIRECT
    raise Error("FBX: a reference that is not known: " + name)


def fbx_euler_order(order: Int) -> EulerOrder:
    """Return the three.js order that turns as an FBX `RotationOrder`
    does, three.js's `getEulerOrder`.

    FBX names its orders by the axes turned about in the fixed frame,
    three.js by the axes of the turning frame, so each name reverses:
    FBX's `eEulerXYZ`, zero, is three.js's `ZYX`. A spheric order, six,
    and any number past it, is taken as zero, as three.js takes them.

    Args:
        order: The `RotationOrder` value.

    Returns:
        The order.
    """
    if order == 1:
        return YZX
    if order == 2:
        return XZY
    if order == 3:
        return ZXY
    if order == 4:
        return YXZ
    if order == 5:
        return XYZ
    return ZYX


def sanitize_node_name(name: String) -> String:
    """Return a name as three.js's `PropertyBinding.sanitizeNodeName`
    makes it: each white space byte an underscore, and `[`, `]`, `.`,
    `:` and `/` dropped.

    Args:
        name: The name.

    Returns:
        The sanitized name.
    """
    var out = List[UInt8]()
    for byte in name.as_bytes():
        if byte == 32 or byte == 9 or byte == 10 or byte == 13:
            out.append(95)
        elif (
            byte != 91
            and byte != 93
            and byte != 46
            and byte != 58
            and byte != 47
        ):
            out.append(byte)
    return String(unsafe_from_utf8=out)


struct FbxTransform(Copyable, Movable):
    """What a model says about its transform, and its parent's matrices,
    as three.js's `generateTransform` reads them. A value the model leaves
    out is its identity: zero, or one for the scale."""

    var translation: Vector3
    # In degrees, as FBX writes them.
    var pre_rotation: Vector3
    var rotation: Vector3
    var post_rotation: Vector3
    var scale: Vector3
    var rotation_offset: Vector3
    var rotation_pivot: Vector3
    var scaling_offset: Vector3
    var scaling_pivot: Vector3
    var order: EulerOrder
    # 0 for `RrSs`, 1 for `RSrs`, 2 for `Rrs`.
    var inherit_type: Int
    var parent_matrix: Matrix4
    var parent_world: Matrix4

    def __init__(out self):
        """Start at the identity, under an untransformed parent."""
        self.translation = Vector3(0, 0, 0)
        self.pre_rotation = Vector3(0, 0, 0)
        self.rotation = Vector3(0, 0, 0)
        self.post_rotation = Vector3(0, 0, 0)
        self.scale = Vector3(1, 1, 1)
        self.rotation_offset = Vector3(0, 0, 0)
        self.rotation_pivot = Vector3(0, 0, 0)
        self.scaling_offset = Vector3(0, 0, 0)
        self.scaling_pivot = Vector3(0, 0, 0)
        self.order = ZYX
        self.inherit_type = 0
        self.parent_matrix = Matrix4()
        self.parent_world = Matrix4()


def _moved(v: Vector3) -> Matrix4:
    """Return a translation by `v`."""
    return translation(v.x, v.y, v.z)


def _turned(degrees: Vector3, order: EulerOrder) raises -> Matrix4:
    """Return the rotation three angles in degrees make in an order."""
    return Euler(
        Angle(degrees.x, DEGREE),
        Angle(degrees.y, DEGREE),
        Angle(degrees.z, DEGREE),
        order,
    ).to_matrix()


def _position_only(matrix: Matrix4) -> Matrix4:
    """Return the identity with `matrix`'s translation, three.js's
    `copyPosition` onto a new matrix."""
    var out = Matrix4()
    out.elements[12] = matrix.elements[12]
    out.elements[13] = matrix.elements[13]
    out.elements[14] = matrix.elements[14]
    return out^


def _inverse(matrix: Matrix4) -> Matrix4:
    """Return the inverse of a matrix, zeros for a singular one, as
    three.js's `invert` gives."""
    var out = Matrix4(copy=matrix)
    out.invert()
    return out^


def _product(a: Matrix4, b: Matrix4) -> Matrix4:
    """Return `a * b`."""
    var out = Matrix4(copy=a)
    out.multiply(b)
    return out^


def generate_transform(data: FbxTransform) raises -> Matrix4:
    """Return a model's matrix relative to its parent, three.js's
    `generateTransform`.

    The local matrix is FBX's chain: translation, rotation offset,
    rotation pivot, pre-rotation, rotation, inverse post-rotation, inverse
    rotation pivot, scaling offset, scaling pivot, scale, inverse scaling
    pivot. Its rotation and scale are then combined with the parent's
    world rotation and scale in the order the inherit type names, and the
    result is taken back into the parent's frame. The pre- and
    post-rotations turn in `ZYX`, the model's rotation in its own order,
    as three.js turns them.

    Args:
        data: The model's values and its parent's matrices.

    Returns:
        The matrix.

    Raises:
        Error: If the order names no three axes, or the parent's world
            matrix flattens an axis, leaving no rotation to extract.
    """
    var t = _moved(data.translation)
    var pre = _turned(data.pre_rotation, ZYX)
    var rotation = _turned(data.rotation, data.order)
    var post = _inverse(_turned(data.post_rotation, ZYX))
    var s = scaling(data.scale.x, data.scale.y, data.scale.z)
    var scaling_offset = _moved(data.scaling_offset)
    var scaling_pivot = _moved(data.scaling_pivot)
    var rotation_offset = _moved(data.rotation_offset)
    var rotation_pivot = _moved(data.rotation_pivot)
    ref parent_world = data.parent_world
    var local_rotation = _product(_product(pre, rotation), post)
    var parent_rotation = parent_world.extract_rotation()
    var parent_scale_shear = _product(
        _inverse(_position_only(parent_world)), parent_world
    )
    var parent_scale = _product(_inverse(parent_rotation), parent_scale_shear)
    var global_rs: Matrix4
    if data.inherit_type == 0:
        global_rs = _product(
            _product(_product(parent_rotation, local_rotation), parent_scale), s
        )
    elif data.inherit_type == 1:
        global_rs = _product(
            _product(_product(parent_rotation, parent_scale), local_rotation), s
        )
    else:
        ref m = data.parent_matrix.elements
        var local_scale = scaling(
            Vector3(m[0], m[1], m[2]).length(),
            Vector3(m[4], m[5], m[6]).length(),
            Vector3(m[8], m[9], m[10]).length(),
        )
        var without_local = _product(parent_scale, _inverse(local_scale))
        global_rs = _product(
            _product(_product(parent_rotation, local_rotation), without_local),
            s,
        )
    var chain = Matrix4(copy=t)
    for step in [
        rotation_offset,
        rotation_pivot,
        pre,
        rotation,
        post,
        _inverse(rotation_pivot),
        scaling_offset,
        scaling_pivot,
        s,
        _inverse(scaling_pivot),
    ]:  # pragma: no branch
        chain.multiply(step)
    var global_translation = _product(parent_world, _position_only(chain))
    var transform = _product(_position_only(global_translation), global_rs)
    transform.premultiply(_inverse(parent_world))
    return transform^


def _triangulate(points: List[Vector3]) raises -> List[Int]:
    """Return the triangles that fill a polygon of four or more corners,
    three corner numbers each, in the polygon's own winding.

    The corners are laid flat on the plane of the polygon's Newell normal,
    as three.js's `getNormalTangentAndBitangent` lays them, and then cut
    by ear clipping, searching from the second corner, so a convex polygon
    is cut into a fan from its first corner. three.js cuts with earcut,
    which picks other diagonals: the surface of a flat polygon is the
    same.

    Args:
        points: The corners, in order.

    Returns:
        Three corner numbers per triangle.

    Raises:
        Error: If the polygon has no area, or crosses itself so that no
            ear is left to clip.
    """
    var count = len(points)
    var normal = Vector3(0, 0, 0)
    for index in range(count):  # pragma: no branch
        var a = points[index]
        var b = points[(index + 1) % count]
        normal.x += (a.y - b.y) * (a.z + b.z)
        normal.y += (a.z - b.z) * (a.x + b.x)
        normal.z += (a.x - b.x) * (a.y + b.y)
    if normal.length() == 0:
        raise Error("FBX: a polygon has no area")
    normal.normalize()
    var up = Vector3(0, 0, 1)
    if abs(normal.z) > 0.5:
        up = Vector3(0, 1, 0)
    var tangent = up
    tangent.cross(normal)
    tangent.normalize()
    var bitangent = normal
    bitangent.cross(tangent)
    bitangent.normalize()
    var flat = List[Vector2]()
    for point in points:  # pragma: no branch
        flat.append(Vector2(point.dot(tangent), point.dot(bitangent)))
    var ring = List[Int]()
    for index in range(count):  # pragma: no branch
        ring.append(index)
    var out = List[Int]()
    while len(ring) > 3:
        var ear = _find_ear(flat, ring)
        if ear < 0:
            raise Error("FBX: a polygon crosses itself")
        var size = len(ring)
        out.append(ring[(ear + size - 1) % size])
        out.append(ring[ear])
        out.append(ring[(ear + 1) % size])
        _ = ring.pop(ear)
    out.extend(ring^)
    return out^


def _turn(a: Vector2, b: Vector2, c: Vector2) -> Float32:
    """Return twice the signed area of the triangle `a`, `b`, `c`:
    positive when it turns counterclockwise."""
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


def _find_ear(flat: List[Vector2], ring: List[Int]) -> Int:
    """Return where in `ring` a corner stands that can be clipped: one
    that turns counterclockwise with no other corner inside its triangle,
    searched from the second; or -1 when there is none."""
    var size = len(ring)
    for step in range(size):  # pragma: no branch
        var at = (step + 1) % size
        var a = flat[ring[(at + size - 1) % size]]
        var b = flat[ring[at]]
        var c = flat[ring[(at + 1) % size]]
        if _turn(a, b, c) <= 0:
            continue
        var clear = True
        for other in range(size):  # pragma: no branch
            var p = flat[ring[other]]
            if _turn(a, b, p) > 0 and _turn(b, c, p) > 0 and _turn(c, a, p) > 0:
                clear = False
        if clear:
            return at
    return -1


struct _Part(Movable):
    """The triangles of a geometry, gathered, and the material index of
    each corner, three.js's `buffers.materialIndex`."""

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]
    var uvs: List[Float32]
    # The position each corner names, for its skin and morph targets.
    var vertices: List[Int]
    var materials: List[Int]

    def __init__(out self):
        self.materials = List[Int]()
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()
        self.uvs = List[Float32]()
        self.vertices = List[Int]()


@fieldwise_init
struct _Link(Copyable, Movable):
    """One end of a connection: the other object's id, and the
    connection's name, such as `DiffuseColor`, or empty."""

    var id: Int
    var relation: String


@fieldwise_init
struct _Cluster(Copyable, Movable):
    """One `Cluster` of a skin: the vertices it carries, how much of each,
    and where its bone stood at bind time."""

    var id: Int
    var indices: List[Int]
    var weights: List[Float64]
    var link: Matrix4


@fieldwise_init
struct _Waiting(Copyable, Movable):
    """A piece of a skinned model's geometry, waiting for its bones to be
    placed."""

    var model: Int
    var source: Int
    var geometry: GeometryId
    var material: MaterialId
    var node: NodeId


struct _RigRows(Movable):
    """A geometry's skin and morph targets, one row per position: four
    bones and four weights each, and each target's offset, moved by the
    geometric transform."""

    var skinned: Bool
    var bones: List[Float32]
    var weights: List[Float32]
    var morphs: List[List[Vector3]]

    def __init__(out self):
        self.skinned = False
        self.bones = List[Float32]()
        self.weights = List[Float32]()
        self.morphs = List[List[Vector3]]()

    def apply(self, vertices: List[Int], mut geometry: BufferGeometry) raises:
        """Give a piece of the geometry its skin and morph attributes, one
        value per corner, read by the position each corner names."""
        if self.skinned:
            var bones = List[Float32]()
            var weights = List[Float32]()
            # A piece has the corners of a triangle at least.
            for vertex in vertices:  # pragma: no branch
                for lane in range(4):  # pragma: no branch
                    bones.append(self.bones[vertex * 4 + lane])
                    weights.append(self.weights[vertex * 4 + lane])
            geometry.set_attribute(
                String(SKIN_INDEX), BufferAttribute(bones^, 4)
            )
            geometry.set_attribute(
                String(SKIN_WEIGHT), BufferAttribute(weights^, 4)
            )
        if len(self.morphs) == 0:
            return
        geometry.morph_relative = True
        # There is a target, or the function returned above; and a piece
        # has the corners of a triangle at least.
        for target in self.morphs:  # pragma: no branch
            var offsets = List[Float32]()
            for vertex in vertices:  # pragma: no branch
                var moved = target[vertex]
                offsets.append(moved.x)
                offsets.append(moved.y)
                offsets.append(moved.z)
            geometry.add_morph_target(BufferAttribute(offsets^, 3))


struct _Rig(Movable):
    """What a file's deformers, bind poses and pieces say about skins,
    blend shapes and animation."""

    # Each skin's clusters, in the order connected, by the skin's id.
    var clusters: Dict[Int, List[_Cluster]]
    # The skin of each geometry: the last one connected to it.
    var skin_of: Dict[Int, Int]
    # Each geometry's blend shape channels that have a shape, in order,
    # and each channel's shape geometry node.
    var channels: Dict[Int, List[Int]]
    var shapes: Dict[Int, Int]
    # Each channel's morph target, by the channel's id.
    var slots: Dict[Int, Int]
    # Every model connected to a cluster: three.js makes it a `Bone`.
    var bones: Dict[Int, Bool]
    # Each model's matrix in a `BindPose`.
    var poses: Dict[Int, Matrix4]
    # The skinned pieces, waiting for every bone.
    var waiting: List[_Waiting]
    # Each model's meshes and skinned meshes that wear morph targets.
    var morphs: Dict[Int, List[TrackTarget]]

    def __init__(out self):
        self.clusters = Dict[Int, List[_Cluster]]()
        self.skin_of = Dict[Int, Int]()
        self.channels = Dict[Int, List[Int]]()
        self.shapes = Dict[Int, Int]()
        self.slots = Dict[Int, Int]()
        self.bones = Dict[Int, Bool]()
        self.poses = Dict[Int, Matrix4]()
        self.waiting = List[_Waiting]()
        self.morphs = Dict[Int, List[TrackTarget]]()


struct FbxModel(Copyable, Movable):
    """What `load_fbx` put into the scene and the assets."""

    # The node every root model hangs on, three.js's `sceneGraph` group.
    var root: NodeId
    var format: FbxFormat
    var version: Int
    # One entry per `Model`, in the order placed: parents first. Its FBX
    # id and its sanitized name.
    var models: List[NodeId]
    var model_ids: List[Int]
    var model_names: List[String]
    # One entry per `Material` connected to anything, in file order.
    var materials: List[MaterialId]
    var material_ids: List[Int]
    var material_names: List[String]
    # One geometry per FBX geometry, in the order built.
    var geometries: List[GeometryId]
    # One texture per texture and color space a material read.
    var textures: List[TextureId]
    # Each camera a `Camera` model rides.
    var cameras: List[PerspectiveCamera]
    # How long one unit of the file is: `GlobalSettings`'s
    # `UnitScaleFactor`, in centimeters. three.js keeps it and does not
    # apply it.
    var unit: Length
    # Where the meshes and lights this file added begin in the scene's
    # lists, and how many there are.
    var first_mesh: Int
    var mesh_count: Int
    var first_light: Int
    var light_count: Int
    # The same for the skinned meshes, in `scene.skinned_meshes`.
    var first_skinned_mesh: Int
    var skinned_mesh_count: Int
    # One clip per animation stack that makes a track.
    var animations: List[AnimationClip]

    def __init__(out self, format: FbxFormat, version: Int):
        """Start empty.

        Args:
            format: Which form the file was written in.
            version: The file's version.
        """
        self.root = NO_PARENT
        self.format = format
        self.version = version
        self.models = List[NodeId]()
        self.model_ids = List[Int]()
        self.model_names = List[String]()
        self.materials = List[MaterialId]()
        self.material_ids = List[Int]()
        self.material_names = List[String]()
        self.geometries = List[GeometryId]()
        self.textures = List[TextureId]()
        self.cameras = List[PerspectiveCamera]()
        self.unit = Length(1.0, CENTIMETER)
        self.first_mesh = 0
        self.mesh_count = 0
        self.first_light = 0
        self.light_count = 0
        self.first_skinned_mesh = 0
        self.skinned_mesh_count = 0
        self.animations = List[AnimationClip]()

    def model(self, name: String) raises -> NodeId:
        """Return the node of the first model of a name.

        Args:
            name: The model's name, sanitized as three.js sanitizes it.

        Returns:
            Its node.

        Raises:
            Error: If no model has the name.
        """
        for index in range(len(self.model_names)):
            if self.model_names[index] == name:
                return self.models[index]
        raise Error("FBX: no model named " + name)


def read_fbx(
    path: String, mut scene: Scene, mut assets: Assets
) raises -> FbxModel:
    """Read a `.fbx` file, binary or ASCII, into a scene and its assets.

    A texture's image is read from the file's own directory, or from the
    file itself when it is embedded.

    Args:
        path: The file.
        scene: The scene to add the nodes, meshes and lights to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where.

    Raises:
        Error: If the file cannot be read, `parse_fbx` refuses it, or
            everything `load_fbx` raises.
    """
    var directory = String(path[byte = 0 : path.rfind("/") + 1])
    return load_fbx(
        parse_fbx(Path(path).read_bytes()), directory, scene, assets
    )


def load_fbx(
    var document: FbxDocument,
    directory: String,
    mut scene: Scene,
    mut assets: Assets,
) raises -> FbxModel:
    """Read a parsed FBX document into a scene and its assets.

    Args:
        document: The tree `parse_fbx` read.
        directory: Where a texture's relative path is read from, ending
            in a slash, or empty for the working directory.
        scene: The scene to add the nodes, meshes and lights to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What went where.

    Raises:
        Error: If the document's format is neither ASCII nor binary; it has
            no `Objects`; a connection, a geometry, a layer element, a
            material, a texture or a model is malformed or names what is
            not there; a polygon is not closed, has no area or crosses
            itself; models are connected in a loop or nest deeper than
            `MAX_MODEL_DEPTH`; a mesh model has no geometry; or a camera,
            a light or a material is refused by its builder; or a skin, a
            blend shape or an animation stack is malformed or names what
            is not there, or a geometry has more blend shape channels than
            `MAX_MORPH_TARGETS`.
    """
    if not document.format.is_valid():
        raise Error("FBX: a format that is neither ASCII nor binary")
    var objects = document.child(document.root(), "Objects")
    if objects == NO_FBX_NODE:
        raise Error("FBX: the file has no Objects")
    var loader = _Loader(document^, directory, objects)
    loader.model.first_mesh = len(scene.meshes)
    loader.model.first_light = len(scene.lights)
    loader.model.first_skinned_mesh = len(scene.skinned_meshes)
    loader.read_materials(assets)
    loader.read_deformers()
    loader.read_models(scene, assets)
    loader.bind_skins(scene)
    loader.read_global_settings(scene)
    loader.read_animations(scene)
    loader.model.skinned_mesh_count = (
        len(scene.skinned_meshes) - loader.model.first_skinned_mesh
    )
    loader.model.mesh_count = len(scene.meshes) - loader.model.first_mesh
    loader.model.light_count = len(scene.lights) - loader.model.first_light
    return loader.model.copy()


struct _Loader(Movable):
    """The document, its objects and connections by id, and what has been
    built."""

    var document: FbxDocument
    var directory: String
    var objects_node: Int
    var model: FbxModel
    # Every object by id, as a node index.
    var objects: Dict[Int, Int]
    # Each object's connections, both ways, in file order.
    var parents: Dict[Int, List[_Link]]
    var children: Dict[Int, List[_Link]]
    # Each connected Material's index in `model.materials`, by id.
    var material_at: Dict[Int, Int]
    # Each texture already made, by texture id and use.
    var textures: Dict[String, TextureId]
    # Each geometry built, by id, and whether it has vertex colors.
    var built: Dict[Int, GeometryId]
    var colored: Dict[Int, Bool]
    # The materials three.js makes for a mesh with none connected, and for
    # a material index past those connected, each made once.
    var defaults: Dict[String, MaterialId]
    # Every `Model` node, in file order, and each one's children by place
    # in that list.
    var model_nodes: List[Int]
    var model_children: List[List[Int]]
    # The skins, blend shapes and bind poses, and what they are on.
    var rig: _Rig

    def __init__(
        out self, var document: FbxDocument, directory: String, objects: Int
    ) raises:
        self.model = FbxModel(document.format, document.version)
        self.directory = directory
        self.objects_node = objects
        self.objects = Dict[Int, Int]()
        self.parents = Dict[Int, List[_Link]]()
        self.children = Dict[Int, List[_Link]]()
        self.material_at = Dict[Int, Int]()
        self.textures = Dict[String, TextureId]()
        self.built = Dict[Int, GeometryId]()
        self.colored = Dict[Int, Bool]()
        self.defaults = Dict[String, MaterialId]()
        self.model_nodes = List[Int]()
        self.model_children = List[List[Int]]()
        self.rig = _Rig()
        for node in document.children(objects):
            if document.property_count(node) > 0:
                self.objects[document.integer(node, 0)] = node
        var connections = document.child(document.root(), "Connections")
        if connections != NO_FBX_NODE:
            for link in document.children_named(connections, "C"):
                var child = document.integer(link, 1)
                var parent = document.integer(link, 2)
                var relation = String()
                if document.property_count(link) > 3:
                    relation = document.string(link, 3)
                if child not in self.parents:
                    self.parents[child] = List[_Link]()
                self.parents[child].append(_Link(parent, relation))
                if parent not in self.children:
                    self.children[parent] = List[_Link]()
                self.children[parent].append(_Link(child, relation))
        self.document = document^

    # --- small readers ------------------------------------------------------

    def kind(self, id: Int) raises -> String:
        """Return what an object is -- `Model`, `Geometry`, `Material` --
        or empty for an id the file has no object of."""
        if id not in self.objects:
            return String()
        return self.document.name(self.objects[id])

    def subtype(self, node: Int) raises -> String:
        """Return an object's third property, such as `Mesh` or `Light`,
        or empty."""
        if self.document.property_count(node) < 3:
            return String()
        return self.document.string(node, 2)

    def label(self, node: Int) raises -> String:
        """Return an object's name, as three.js reads it."""
        if self.document.property_count(node) < 2:
            return String()
        return object_name(self.document.string(node, 1), self.document.format)

    def links(
        self, table: Dict[Int, List[_Link]], id: Int
    ) raises -> List[_Link]:
        """Return an object's connections one way, or none."""
        if id not in table:
            return List[_Link]()
        return table[id].copy()

    def text_of(self, node: Int, name: String) raises -> String:
        """Return the string a required child node holds.

        Raises:
            Error: If the node has no such child.
        """
        var found = self.document.child(node, name)
        if found == NO_FBX_NODE:
            raise Error("FBX: " + self.document.name(node) + " has no " + name)
        return self.document.string(found, 0)

    def entry(self, node: Int, name: String) raises -> Int:
        """Return the `P` entry of a name in a node's `Properties70`, or
        `NO_FBX_NODE`."""
        var properties = self.document.child(node, "Properties70")
        if properties == NO_FBX_NODE:
            return NO_FBX_NODE
        for entry in self.document.children_named(properties, "P"):
            if self.document.string(entry, 0) == name:
                return entry
        return NO_FBX_NODE

    def value(
        self, node: Int, name: String, default: Float64
    ) raises -> Float64:
        """Return a `P` entry's number, or a default when there is none."""
        var entry = self.entry(node, name)
        if entry == NO_FBX_NODE:
            return default
        return self.document.number(entry, 4)

    def vector(
        self, node: Int, name: String, default: Vector3
    ) raises -> Vector3:
        """Return a `P` entry's three numbers, or a default."""
        var entry = self.entry(node, name)
        if entry == NO_FBX_NODE:
            return default
        return Vector3(
            Float32(self.document.number(entry, 4)),
            Float32(self.document.number(entry, 5)),
            Float32(self.document.number(entry, 6)),
        )

    def entry_color(self, entry: Int) raises -> Color:
        """Return a `P` entry's three numbers as a color as authored."""
        return authored_color(
            self.document.number(entry, 4),
            self.document.number(entry, 5),
            self.document.number(entry, 6),
            "FBX",
        )

    def color_entry(
        self, node: Int, first: String, second: String
    ) raises -> Int:
        """Return the `P` entry three.js reads a color from: `first`, or
        `second` when it is typed `Color` or `ColorRGB`, as the Blender
        exporter writes it; or `NO_FBX_NODE`."""
        var entry = self.entry(node, first)
        if entry != NO_FBX_NODE:
            return entry
        entry = self.entry(node, second)
        if entry == NO_FBX_NODE:
            return NO_FBX_NODE
        var kind = self.document.string(entry, 1)
        if kind == "Color" or kind == "ColorRGB":
            return entry
        return NO_FBX_NODE

    # --- materials ------------------------------------------------------------

    def read_materials(mut self, mut assets: Assets) raises:
        """Build each `Material` that is connected to anything, in file
        order, as three.js's `parseMaterials` builds them."""
        for node in self.document.children_named(self.objects_node, "Material"):
            var id = self.document.integer(node, 0)
            if id not in self.parents and id not in self.children:
                continue
            var built = self.build_material(node, id, assets)
            self.material_at[id] = len(self.model.materials)
            self.model.materials.append(assets.materials.add(built))
            self.model.material_ids.append(id)
            self.model.material_names.append(self.label(node))

    def shading_model(self, node: Int) raises -> String:
        """Return a material's `ShadingModel`, lowercased, from its own
        node or its `Properties70`."""
        if self.document.child(node, "ShadingModel") != NO_FBX_NODE:
            return self.text_of(node, "ShadingModel").lower()
        var entry = self.entry(node, "ShadingModel")
        if entry == NO_FBX_NODE:
            raise Error("FBX: a material has no ShadingModel")
        return self.document.string(entry, 4).lower()

    def build_material(
        mut self, node: Int, id: Int, mut assets: Assets
    ) raises -> Material:
        """Build one material, as three.js's `parseParameters` reads it.

        A `lambert` shading model is a `LAMBERT` material and anything
        else a `PHONG` one, as three.js defaults to `MeshPhongMaterial`.

        Raises:
            Error: If it has no shading model, a color or a number is
                malformed, a texture cannot be read, or `Material` refuses
                the result.
        """
        var kind = PHONG
        if self.shading_model(node) == "lambert":
            kind = LAMBERT
        var color = _WHITE
        var diffuse = self.color_entry(node, "Diffuse", "DiffuseColor")
        if diffuse != NO_FBX_NODE:
            color = self.entry_color(diffuse)
        var emissive = Color(0, 0, 0)
        var glow = self.color_entry(node, "Emissive", "EmissiveColor")
        if glow != NO_FBX_NODE:
            emissive = self.entry_color(glow)
        var emissive_intensity = Float32(self.value(node, "EmissiveFactor", 1))
        # Blender's and Unity's reading, which three.js follows: one minus
        # the transparency factor, unless that is exactly zero or one, when
        # `Opacity` decides, or else one minus the transparent color's red.
        var opacity = 1 - self.value(node, "TransparencyFactor", 0)
        if opacity == 1 or opacity == 0:
            opacity = self.value(
                node, "Opacity", 1 - self.value(node, "TransparentColor", 0)
            )
        var transparent = opacity < 1
        var reflectivity = Float32(self.value(node, "ReflectionFactor", 1))
        var specular = Color(0, 0, 0)
        var shininess = Float32(0)
        if kind == PHONG:
            specular = Color(17, 17, 17)
            shininess = Float32(self.value(node, "Shininess", 30))
            var shine = self.entry(node, "Specular")
            if shine == NO_FBX_NODE:
                shine = self.entry(node, "SpecularColor")
                if (
                    shine != NO_FBX_NODE
                    and self.document.string(shine, 1) != "Color"
                ):
                    shine = NO_FBX_NODE
            if shine != NO_FBX_NODE:
                specular = self.entry_color(shine)
        var bump_scale = Float32(self.value(node, "BumpFactor", 1))
        var map = NO_TEXTURE
        var emissive_map = NO_TEXTURE
        var normal_map = NO_TEXTURE
        var bump_map = NO_TEXTURE
        var alpha_map = NO_TEXTURE
        for link in self.links(self.children, id):
            var relation = link.relation
            if relation == "DiffuseColor" or relation == "Maya|TEX_color_map":
                map = self.texture(link.id, SRGB, COVERAGE, assets)
            elif relation == "EmissiveColor":
                emissive_map = self.texture(link.id, SRGB, IGNORED, assets)
            elif relation == "NormalMap" or relation == "Maya|TEX_normal_map":
                normal_map = self.texture(link.id, LINEAR, IGNORED, assets)
            elif relation == "Bump":
                bump_map = self.texture(link.id, LINEAR, IGNORED, assets)
            elif (
                relation == "TransparentColor"
                or relation == "TransparencyFactor"
            ):
                alpha_map = self.texture(link.id, LINEAR, IGNORED, assets)
                transparent = True
        if normal_map != NO_TEXTURE:
            # A material here takes one of the two, and three.js's shader
            # reads the normal map when it has both.
            bump_map = NO_TEXTURE
        if bump_map == NO_TEXTURE:
            # three.js keeps a bump scale with no bump map to scale, and
            # reads nothing of it; `Material` refuses one.
            bump_scale = 1
        return Material(
            color,
            map=map,
            opacity=Float32(opacity),
            kind=kind,
            emissive=emissive,
            emissive_intensity=emissive_intensity,
            emissive_map=emissive_map,
            alpha_map=alpha_map,
            specular=specular,
            shininess=shininess,
            transparent=transparent,
            reflectivity=reflectivity,
            normal_map=normal_map,
            bump_map=bump_map,
            bump_scale=bump_scale,
        )

    # --- textures -------------------------------------------------------------

    def video_bytes(self, node: Int) raises -> List[UInt8]:
        """Return a `Video`'s embedded image, or nothing: raw bytes in a
        binary file, base64 in an ASCII one."""
        var content = self.document.child(node, "Content")
        if content == NO_FBX_NODE:
            return List[UInt8]()
        if self.document.property_count(content) == 0:
            return List[UInt8]()
        var held = self.document.property(content, 0)
        if held.kind == FBX_BYTES:
            return held.bytes.copy()
        if held.kind == FBX_STRING:
            return decode_base64(held.text)
        raise Error("FBX: a video's Content is neither bytes nor base64")

    def video_name(self, node: Int) raises -> String:
        """Return a `Video`'s `RelativeFilename`, or its `Filename`."""
        for key in ["RelativeFilename", "Filename"]:  # pragma: no branch
            if self.document.child(node, key) != NO_FBX_NODE:
                var name = self.text_of(node, key)
                if name != "":
                    return name
        return String()

    def texture(
        mut self, id: Int, space: ColorSpace, alpha: Alpha, mut assets: Assets
    ) raises -> TextureId:
        """Return the texture a material's connection names, as three.js's
        `parseTexture` and `loadTexture` read it, made once per use.

        A layered texture is read as its first layer, as three.js reads
        it. A texture with no image connected is `NO_TEXTURE`, where
        three.js makes an empty placeholder.

        Raises:
            Error: If the connection names no texture, the image path is
                not relative, or the image cannot be read or decoded.
        """
        var chosen = id
        if self.kind(chosen) == "LayeredTexture":
            var layers = self.links(self.children, chosen)
            if len(layers) == 0:
                return NO_TEXTURE
            chosen = layers[0].id
        if self.kind(chosen) != "Texture":
            raise Error("FBX: a material names a texture that is not there")
        var key = String(chosen, " ", space.value, " ", alpha.value)
        if key in self.textures:
            return self.textures[key]
        var node = self.objects[chosen]
        var images = self.links(self.children, chosen)
        if len(images) == 0:
            return NO_TEXTURE
        if self.kind(images[0].id) != "Video":
            return NO_TEXTURE
        var video = self.objects[images[0].id]
        var name = self.video_name(video)
        var bytes = self.video_bytes(video)
        # three.js uses the bytes any `Video` of the same name embeds, and
        # otherwise the file, named by what follows its last `\`.
        # The video read above is one of them: the loop always runs.
        for other in self.document.children_named(  # pragma: no branch
            self.objects_node, "Video"
        ):
            if len(bytes) == 0 and self.video_name(other) == name:
                bytes = self.video_bytes(other)
        if len(bytes) == 0:
            var file = String(name[byte = name.rfind("\\") + 1 :])
            if file == "" or file.find(":") >= 0:
                raise Error("FBX: only a relative image path is read: " + name)
            bytes = Path(self.directory + file).read_bytes()
        var wrap = REPEAT
        if self.value(node, "WrapModeU", 0) != 0:
            wrap = CLAMP
        var built = texture_from_bytes(bytes, space, wrap, alpha)
        var scale = self.vector(node, "Scaling", Vector3(1, 1, 1))
        var shift = self.vector(node, "Translation", Vector3(0, 0, 0))
        built.repeat = Vector2(scale.x, scale.y)
        built.offset = Vector2(shift.x, shift.y)
        var made = assets.textures.add(built^)
        self.textures[key] = made
        self.model.textures.append(made)
        return made

    # --- geometry -------------------------------------------------------------

    def find_layer(
        self, node: Int, element: String, values: String
    ) raises -> Int:
        """Return the first layer element of a name that holds its values,
        or `NO_FBX_NODE`."""
        for holder in self.document.children_named(node, element):
            if self.document.child(holder, values) != NO_FBX_NODE:
                return holder
        return NO_FBX_NODE

    def layer(
        self, holder: Int, values: String, index: String, size: Int
    ) raises -> FbxLayer:
        """Read a layer element's mapping, reference, values and indices.

        Args:
            holder: The `LayerElement...` node.
            values: The name of its values: `Normals`, `UV`, `Colors`.
            index: The name of its indices: `NormalsIndex`, `UVIndex`,
                `ColorIndex`. A normal layer's can also be `NormalIndex`.
            size: How many values make one.

        Returns:
            The layer.

        Raises:
            Error: If the mapping or the reference is not known, or a value
                or an index is malformed.
        """
        var mapping = fbx_mapping(
            self.text_of(holder, "MappingInformationType")
        )
        var reference = DIRECT
        if (
            self.document.child(holder, "ReferenceInformationType")
            != NO_FBX_NODE
        ):
            reference = fbx_reference(
                self.text_of(holder, "ReferenceInformationType")
            )
        var indices = List[Int]()
        if reference == INDEX_TO_DIRECT:
            for name in [index, String("NormalIndex")]:  # pragma: no branch
                var found = self.document.child(holder, name)
                if found != NO_FBX_NODE and len(indices) == 0:
                    indices = self.document.integers(found)
        return FbxLayer(
            mapping,
            reference,
            self.document.numbers(self.document.child(holder, values)),
            indices^,
            size,
        )

    def first_model(self, id: Int) raises -> Int:
        """Return the node of the first model a geometry is connected to,
        whose geometric transform three.js applies to it.

        A geometry is built only when a model that it is connected to
        draws it, so there is one to find.
        """
        var links = self.links(self.parents, id)
        var at = 0
        while self.kind(links[at].id) != "Model":
            at += 1
        return self.objects[links[at].id]

    def geometric_transform(self, model: Int) raises -> Matrix4:
        """Return a model's geometric transform, which three.js applies to
        the geometry's positions and normals and not to the node."""
        var data = FbxTransform()
        data.translation = self.vector(
            model, "GeometricTranslation", Vector3(0, 0, 0)
        )
        data.rotation = self.vector(
            model, "GeometricRotation", Vector3(0, 0, 0)
        )
        data.scale = self.vector(model, "GeometricScaling", Vector3(1, 1, 1))
        data.order = fbx_euler_order(Int(self.value(model, "RotationOrder", 0)))
        data.inherit_type = Int(self.value(model, "InheritType", 0))
        return generate_transform(data)

    def build_geometry(mut self, id: Int, mut assets: Assets) raises:
        """Build an FBX geometry, with a group per run of one material
        index, the first time a model draws it, as three.js's
        `genGeometry` builds its buffers and `addGroup`s.

        Raises:
            Error: If a layer is malformed, an index is out of range, a
                polygon has no area or crosses itself, or the last polygon
                is not closed by a negative index.
        """
        if id in self.built:
            return
        var node = self.objects[id]
        var pre = self.geometric_transform(self.first_model(id))
        var turn = pre.normal_matrix()
        var positions = List[Float64]()
        var found = self.document.child(node, "Vertices")
        if found != NO_FBX_NODE:
            positions = self.document.numbers(found)
        var polygons = List[Int]()
        found = self.document.child(node, "PolygonVertexIndex")
        if found != NO_FBX_NODE:
            polygons = self.document.integers(found)
        var has_normal = False
        var normals = FbxLayer(
            ALL_SAME, DIRECT, List[Float64](), List[Int](), 3
        )
        var holder = self.find_layer(node, "LayerElementNormal", "Normals")
        if holder != NO_FBX_NODE:
            normals = self.layer(holder, "Normals", "NormalsIndex", 3)
            has_normal = True
        var has_uv = False
        var uvs = FbxLayer(ALL_SAME, DIRECT, List[Float64](), List[Int](), 2)
        holder = self.find_layer(node, "LayerElementUV", "UV")
        if holder != NO_FBX_NODE:
            uvs = self.layer(holder, "UV", "UVIndex", 2)
            has_uv = True
        var has_color = False
        var colors = FbxLayer(ALL_SAME, DIRECT, List[Float64](), List[Int](), 4)
        holder = self.find_layer(node, "LayerElementColor", "Colors")
        if holder != NO_FBX_NODE:
            colors = self.layer(holder, "Colors", "ColorIndex", 4)
            has_color = True
            # A vertex color is sRGB, and a geometry's is linear.
            for at in range(len(colors.values)):
                if at % 4 < 3:
                    colors.values[at] = Float64(
                        srgb_to_linear(Float32(colors.values[at]))
                    )
        var has_material = False
        var materials = FbxLayer(
            ALL_SAME, DIRECT, List[Float64](), List[Int](), 1
        )
        holder = self.find_layer(node, "LayerElementMaterial", "Materials")
        if holder != NO_FBX_NODE:
            if (
                self.text_of(holder, "MappingInformationType")
                != "NoMappingInformation"
            ):
                materials = FbxLayer(
                    fbx_mapping(self.text_of(holder, "MappingInformationType")),
                    DIRECT,
                    self.document.numbers(
                        self.document.child(holder, "Materials")
                    ),
                    List[Int](),
                    1,
                )
                has_material = True
        var part = _Part()
        var face = _Face()
        var polygon = 0
        for corner in range(len(polygons)):
            var vertex = polygons[corner]
            var end = vertex < 0
            if end:
                vertex = -vertex - 1
            if vertex * 3 + 3 > len(positions):
                raise Error("FBX: a polygon names a position that is not there")
            face.vertices.append(vertex)
            face.points.append(
                pre.transform_point(
                    Vector3(
                        Float32(positions[vertex * 3]),
                        Float32(positions[vertex * 3 + 1]),
                        Float32(positions[vertex * 3 + 2]),
                    )
                )
            )
            if has_normal:
                var at = normals.start(corner, polygon, vertex)
                var normal = turn.transform_direction(
                    Vector3(
                        Float32(normals.values[at]),
                        Float32(normals.values[at + 1]),
                        Float32(normals.values[at + 2]),
                    )
                )
                normal.normalize()
                face.normals.append(normal)
            if has_uv:
                var at = uvs.start(corner, polygon, vertex)
                face.uvs.append(
                    Vector2(
                        Float32(uvs.values[at]), Float32(uvs.values[at + 1])
                    )
                )
            if has_color:
                var at = colors.start(corner, polygon, vertex)
                face.colors.append(
                    Vector3(
                        Float32(colors.values[at]),
                        Float32(colors.values[at + 1]),
                        Float32(colors.values[at + 2]),
                    )
                )
            if has_material:
                var at = materials.start(corner, polygon, vertex)
                # three.js falls back to the first material for a negative
                # index.
                face.material = max(Int(materials.values[at]), 0)
            if end:
                var before = len(part.positions) // 3
                face.emit(part)
                for _ in range(before, len(part.positions) // 3):
                    part.materials.append(face.material)
                face = _Face()
                polygon += 1
        if len(face.points) > 0:
            raise Error(
                "FBX: the last polygon is not closed by a negative index"
            )
        var rows = self.rig_rows(id, len(positions) // 3, pre)
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(part.positions.copy(), 3)
        )
        if has_normal:
            geometry.set_attribute(
                String(NORMAL), BufferAttribute(part.normals.copy(), 3)
            )
        if has_color:
            geometry.set_attribute(
                String(COLOR), BufferAttribute(part.colors.copy(), 3)
            )
        if has_uv:
            geometry.set_attribute(
                String(UV), BufferAttribute(part.uvs.copy(), 2)
            )
        rows.apply(part.vertices, geometry)
        if has_material and materials.mapping != ALL_SAME:
            _add_material_groups(geometry, part.materials)
        var made = assets.geometries.add(geometry^)
        self.model.geometries.append(made)
        self.built[id] = made
        self.colored[id] = has_color

    # --- models ---------------------------------------------------------------

    def read_models(mut self, mut scene: Scene, mut assets: Assets) raises:
        """Place every `Model` under its parent model, parents first, as
        three.js's `parseScene` hangs them."""
        var position = Dict[Int, Int]()
        for node in self.document.children_named(self.objects_node, "Model"):
            position[self.document.integer(node, 0)] = len(self.model_nodes)
            self.model_nodes.append(node)
            self.model_children.append(List[Int]())
        var roots = List[Int]()
        for place in range(len(self.model_nodes)):
            var id = self.document.integer(self.model_nodes[place], 0)
            # three.js adds a model to each parent model in turn, and the
            # last one keeps it.
            var parent = -1
            for link in self.links(self.parents, id):
                if link.id in position:
                    parent = position[link.id]
            if parent < 0:
                roots.append(place)
            else:
                self.model_children[parent].append(place)
        self.model.root = scene.add(Object3D())
        var top = self.model.root
        for place in roots:
            self.place(place, top, Matrix4(), Matrix4(), 0, scene, assets)
        if len(self.model.models) != len(self.model_nodes):
            raise Error("FBX: models are connected in a loop")

    def attribute(self, id: Int) raises -> Int:
        """Return the `NodeAttribute` connected to a model: the last one,
        as three.js keeps the last; or `NO_FBX_NODE`."""
        var found = NO_FBX_NODE
        for link in self.links(self.children, id):
            if self.kind(link.id) == "NodeAttribute":
                found = self.objects[link.id]
        return found

    def place(
        mut self,
        place: Int,
        parent: NodeId,
        parent_matrix: Matrix4,
        parent_world: Matrix4,
        depth: Int,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add one model under its parent, with what it carries, then its
        children."""
        if depth > MAX_MODEL_DEPTH:
            raise Error("FBX: models nest too deep")
        var node = self.model_nodes[place]
        var id = self.document.integer(node, 0)
        var kind = self.subtype(node)
        if id in self.rig.bones:
            # three.js makes a model connected to a cluster a `Bone`,
            # whatever it was.
            kind = "LimbNode"
        var data = FbxTransform()
        data.translation = self.vector(
            node, "Lcl Translation", Vector3(0, 0, 0)
        )
        data.pre_rotation = self.vector(node, "PreRotation", Vector3(0, 0, 0))
        data.rotation = self.vector(node, "Lcl Rotation", Vector3(0, 0, 0))
        data.post_rotation = self.vector(node, "PostRotation", Vector3(0, 0, 0))
        data.scale = self.vector(node, "Lcl Scaling", Vector3(1, 1, 1))
        data.rotation_offset = self.vector(
            node, "RotationOffset", Vector3(0, 0, 0)
        )
        data.rotation_pivot = self.vector(
            node, "RotationPivot", Vector3(0, 0, 0)
        )
        data.scaling_offset = self.vector(
            node, "ScalingOffset", Vector3(0, 0, 0)
        )
        data.scaling_pivot = self.vector(node, "ScalingPivot", Vector3(0, 0, 0))
        data.order = fbx_euler_order(Int(self.value(node, "RotationOrder", 0)))
        data.inherit_type = Int(self.value(node, "InheritType", 0))
        data.parent_matrix = parent_matrix
        data.parent_world = parent_world
        var local = generate_transform(data)
        var attribute = self.attribute(id)
        var light_type = -1
        if kind == "Light" and attribute != NO_FBX_NODE:
            light_type = Int(self.value(attribute, "LightType", 0))
        if light_type == 1 or light_type == 2:
            # three.js's directional and spot lights stand one unit up their
            # own y before the model's transform is applied to them.
            local.multiply(translation(0, 1, 0))
        var placed = Object3D()
        decompose_onto(placed, local, "FBX")
        var name = sanitize_node_name(self.label(node))
        placed.name = name
        var matrix = compose(placed)
        var world = _product(parent_world, matrix)
        var at = scene.attach(placed^, parent)
        self.model.models.append(at)
        self.model.model_ids.append(id)
        self.model.model_names.append(name)
        if kind == "Camera" and attribute != NO_FBX_NODE:
            self.place_camera(attribute, at)
        elif light_type >= 0:
            self.place_light(attribute, light_type, at, scene)
        elif kind == "Mesh":
            self.place_meshes(id, at, scene, assets)
        for child in self.model_children[place].copy():
            self.place(child, at, matrix, world, depth + 1, scene, assets)

    def place_camera(mut self, attribute: Int, node: NodeId) raises:
        """Add the camera a `Camera` model's attribute describes, as
        three.js's `createCamera` builds it. An orthographic one is left
        out, as three.js leaves it out."""
        if Int(self.value(attribute, "CameraProjectionType", 0)) == 1:
            return
        var near = DEFAULT_NEAR_PLANE
        if self.entry(attribute, "NearPlane") != NO_FBX_NODE:
            near = self.value(attribute, "NearPlane", 0) / 1000
        var far = DEFAULT_FAR_PLANE
        if self.entry(attribute, "FarPlane") != NO_FBX_NODE:
            far = self.value(attribute, "FarPlane", 0) / 1000
        # three.js falls back to the window's shape, which a file loaded
        # here has none of: a square.
        var aspect = Float64(1)
        var width = self.entry(attribute, "AspectWidth")
        var height = self.entry(attribute, "AspectHeight")
        if width != NO_FBX_NODE and height != NO_FBX_NODE:
            aspect = self.document.number(width, 4) / self.document.number(
                height, 4
            )
        var fov = self.value(attribute, "FieldOfView", DEFAULT_FOV_DEGREES)
        if self.entry(attribute, "FocalLength") != NO_FBX_NODE:
            # three.js's `setFocalLength`: the height of a 35 mm film gauge,
            # seen from the focal length.
            var film = FILM_GAUGE / max(aspect, 1)
            var focal = self.value(attribute, "FocalLength", 0)
            fov = 2 * atan(0.5 * film / focal) * 180 / pi
        var camera = PerspectiveCamera(
            Angle(Float32(fov), DEGREE),
            Float32(aspect),
            Length(Float32(near), METER),
            Length(Float32(far), METER),
        )
        camera.attach(node)
        self.model.cameras.append(camera)

    def place_light(
        mut self,
        attribute: Int,
        light_type: Int,
        node: NodeId,
        mut scene: Scene,
    ) raises:
        """Add the light a `Light` model's attribute describes, as three.js's
        `createLight` builds it."""
        var color = _WHITE
        if self.entry(attribute, "Color") != NO_FBX_NODE:
            color = self.entry_color(self.entry(attribute, "Color"))
        var intensity = Float32(self.value(attribute, "Intensity", 100) / 100)
        if self.value(attribute, "CastLightOnObject", 1) == 0:
            intensity = 0
        var distance = Float32(self.value(attribute, "FarAttenuationEnd", 0))
        if self.value(attribute, "EnableFarAttenuation", 1) == 0:
            distance = 0
        var shadow = self.value(attribute, "CastShadows", 0) == 1
        if light_type == 1:
            var light = directional_light(color, node, intensity)
            light.cast_shadow = shadow
            light.validate()
            scene.add_light(light)
        elif light_type == 2:
            var penumbra = Float32(0)
            if self.entry(attribute, "OuterAngle") != NO_FBX_NODE:
                # three.js sets the penumbra to the outer angle in radians,
                # at least one: one, the widest it can be.
                penumbra = 1
            var light = spot_light(
                color,
                node,
                intensity,
                distance=distance,
                angle=Angle(
                    Float32(self.value(attribute, "InnerAngle", 60)), DEGREE
                ),
                penumbra=penumbra,
                decay=1,
            )
            light.cast_shadow = shadow
            light.validate()
            scene.add_light(light)
        elif light_type == 0:
            var light = point_light(
                color, node, intensity, decay=1, distance=distance
            )
            light.cast_shadow = shadow
            light.validate()
            scene.add_light(light)
        else:
            # An unknown type is a point light at three.js's defaults, and
            # casts as three.js's `createLight` lets any light cast.
            var light = point_light(color, node, intensity)
            light.cast_shadow = shadow
            scene.add_light(light)

    def default_material(
        mut self, key: String, material: Material, mut assets: Assets
    ) -> MaterialId:
        """Return a material three.js makes when a file names none, making
        it the first time."""
        if key not in self.defaults:
            self.defaults[key] = assets.materials.add(material)
        return self.defaults.get(key, MaterialId(0))

    def place_meshes(
        mut self, id: Int, node: NodeId, mut scene: Scene, mut assets: Assets
    ) raises:
        """Add the mesh of a `Mesh` model: its geometry, with the one
        material connected to it or the list of them, as three.js's
        `parseMesh` binds them."""
        var geometry = -1
        var materials = List[MaterialId]()
        for link in self.links(self.children, id):
            var kind = self.kind(link.id)
            if kind == "Geometry":
                if self.subtype(self.objects[link.id]) == "Mesh":
                    geometry = link.id
            elif link.id in self.material_at:
                materials.append(
                    self.model.materials[self.material_at[link.id]]
                )
        if geometry < 0:
            raise Error("FBX: a mesh model has no mesh geometry")
        self.build_geometry(geometry, assets)
        var colored = self.colored[geometry]
        if len(materials) == 0:
            var key = String("plain")
            if colored:
                key = "tinted"
            materials.append(
                self.default_material(
                    key,
                    Material(
                        UNMATERIALED,
                        kind=PHONG,
                        specular=Color(17, 17, 17),
                        shininess=30,
                        vertex_colors=colored,
                    ),
                    assets,
                )
            )
        elif colored:
            # three.js turns vertex colors on for every material of a mesh
            # whose geometry has them, shared or not.
            # `materials` is not empty here: the loop always runs.
            for material in materials:  # pragma: no branch
                assets.materials.materials[material.value].vertex_colors = True
        var made = self.built[geometry]
        # A geometry of no triangles draws nothing, and is given no mesh.
        # three.js adds a mesh of nothing.
        if assets.geometries.get(made).vertex_count() == 0:
            return
        self.add_piece(id, geometry, made, materials, node, scene, assets)

    def read_global_settings(mut self, mut scene: Scene) raises:
        """Read `GlobalSettings`: an ambient light for an `AmbientColor`
        that is not black, and the `UnitScaleFactor`, as three.js's
        `addGlobalSceneSettings` reads them."""
        var settings = self.document.child(
            self.document.root(), "GlobalSettings"
        )
        if settings == NO_FBX_NODE:
            return
        var ambient = self.entry(settings, "AmbientColor")
        if ambient != NO_FBX_NODE:
            var color = self.entry_color(ambient)
            if Int(color.r) + Int(color.g) + Int(color.b) > 0:
                scene.add_light(ambient_light(color))
        self.model.unit = Length(
            Float32(self.value(settings, "UnitScaleFactor", 1)), CENTIMETER
        )

    # --- skins, blend shapes and animation --------------------------------

    def matrix_of(self, node: Int, name: String) raises -> Matrix4:
        """Return the matrix a child node holds, sixteen numbers column by
        column, as three.js's `Matrix4.fromArray` reads them.

        Raises:
            Error: If the node has no such child, or it does not hold
                sixteen numbers.
        """
        var found = self.document.child(node, name)
        if found == NO_FBX_NODE:
            raise Error("FBX: " + self.document.name(node) + " has no " + name)
        var values = self.document.numbers(found)
        if len(values) != 16:
            raise Error("FBX: a " + name + " needs sixteen numbers")
        var out = Matrix4()
        for at in range(16):  # pragma: no branch
            out.elements[at] = Float32(values[at])
        return out^

    def read_deformers(mut self) raises:
        """Read every skin, its clusters and their bones, every blend
        shape and its channels, and every bind pose, as three.js's
        `parseDeformers` and `parsePoseNodes` read them."""
        for node in self.document.children_named(self.objects_node, "Deformer"):
            var id = self.document.integer(node, 0)
            var kind = self.subtype(node)
            if kind == "Skin":
                self.read_skin(id)
            elif kind == "BlendShape":
                self.read_blend_shape(id)
        for node in self.document.children_named(self.objects_node, "Pose"):
            if self.subtype(node) != "BindPose":
                continue
            for entry in self.document.children_named(node, "PoseNode"):
                var model = self.document.integer(
                    self.document.child(entry, "Node"), 0
                )
                self.rig.poses[model] = self.matrix_of(entry, "Matrix")

    def read_skin(mut self, id: Int) raises:
        """Read one skin's clusters, the geometry it deforms, and the model
        each cluster names as its bone.

        Raises:
            Error: If the skin deforms no geometry, or a cluster has no
                `TransformLink`, or not as many `Weights` as `Indexes`.
        """
        var clusters = List[_Cluster]()
        for link in self.links(self.children, id):
            if self.kind(link.id) != "Deformer":
                continue
            var node = self.objects[link.id]
            if self.subtype(node) != "Cluster":
                continue
            var indices = List[Int]()
            var weights = List[Float64]()
            var found = self.document.child(node, "Indexes")
            if found != NO_FBX_NODE:
                indices = self.document.integers(found)
                found = self.document.child(node, "Weights")
                if found != NO_FBX_NODE:
                    weights = self.document.numbers(found)
                if len(weights) != len(indices):
                    raise Error("FBX: a cluster needs one weight per index")
            clusters.append(
                _Cluster(
                    link.id,
                    indices^,
                    weights^,
                    self.matrix_of(node, "TransformLink"),
                )
            )
            for bone in self.links(self.children, link.id):
                if self.kind(bone.id) == "Model":
                    self.rig.bones[bone.id] = True
        var owners = self.links(self.parents, id)
        if len(owners) == 0:
            raise Error("FBX: a skin deforms no geometry")
        self.rig.clusters[id] = clusters^
        # A geometry keeps the last skin connected to it, as three.js's
        # `parseMeshGeometry` keeps it. The skin is a child of its owner:
        # the loop always runs.
        for link in self.links(  # pragma: no branch
            self.children, owners[0].id
        ):
            if link.id in self.rig.clusters:
                self.rig.skin_of[owners[0].id] = link.id

    def read_blend_shape(mut self, id: Int) raises:
        """Read one blend shape's channels onto the geometries it deforms,
        as three.js's `parseMorphTargets` reads them.

        Raises:
            Error: If a child of the blend shape is not a
                `BlendShapeChannel`, or a channel has no shape.
        """
        var channels = List[Int]()
        for link in self.links(self.children, id):
            if not self.is_channel(link.id):
                raise Error(
                    "FBX: a blend shape holds what is not a BlendShapeChannel"
                )
            var shape = -1
            for below in self.links(self.children, link.id):
                if below.relation == "":
                    shape = below.id
                    break
            if shape < 0:
                raise Error("FBX: a blend shape channel has no shape")
            # three.js adds the channel only when its shape is a geometry.
            if self.kind(shape) == "Geometry":
                self.rig.shapes[link.id] = self.objects[shape]
                channels.append(link.id)
        for owner in self.links(self.parents, id):
            if owner.id not in self.rig.channels:
                self.rig.channels[owner.id] = List[Int]()
            self.rig.channels[owner.id].extend(channels.copy())

    def is_channel(self, id: Int) raises -> Bool:
        """Return True if an object is a `BlendShapeChannel` deformer."""
        return (
            self.kind(id) == "Deformer"
            and self.subtype(self.objects[id]) == "BlendShapeChannel"
        )

    def rig_rows(
        mut self, id: Int, count: Int, pre: Matrix4
    ) raises -> _RigRows:
        """Return a geometry's skin and morph targets, one row per
        position, as three.js's `parseGeoNode`, `genBuffers` and
        `genMorphGeometry` work them out.

        A vertex with more than four weights keeps the four largest, as
        three.js's insertion keeps them, and the weights are normalized as
        `normalizeSkinWeights` scales them. A morph target is moved by the
        whole geometric transform, its translation too, as three.js's
        `applyMatrix4` moves it.

        Raises:
            Error: If the geometry has more morph targets than a mesh
                wears, a shape names a position the geometry does not
                have, or a shape has not three numbers per index.
        """
        var rows = _RigRows()
        if id in self.rig.skin_of:
            rows.skinned = True
            var bones = List[List[Int]](length=count, fill=List[Int]())
            var shares = List[List[Float64]](length=count, fill=List[Float64]())
            var clusters = self.rig.clusters[self.rig.skin_of[id]].copy()
            for bone in range(len(clusters)):
                ref cluster = clusters[bone]
                for at in range(len(cluster.indices)):
                    var vertex = cluster.indices[at]
                    # three.js looks up only the positions a polygon names.
                    if _within(vertex, count):
                        bones[vertex].append(bone)
                        shares[vertex].append(cluster.weights[at])
            for vertex in range(count):
                var four = _four_largest(bones[vertex], shares[vertex])
                var scaled = normalized_skin_weights(
                    SIMD[DType.float32, 4](
                        Float32(four[1][0]),
                        Float32(four[1][1]),
                        Float32(four[1][2]),
                        Float32(four[1][3]),
                    )
                )
                for lane in range(4):  # pragma: no branch
                    rows.bones.append(Float32(four[0][lane]))
                    rows.weights.append(scaled[lane])
        if id not in self.rig.channels:
            return rows^
        var channels = self.rig.channels[id].copy()
        if len(channels) > MAX_MORPH_TARGETS:
            raise Error(
                "FBX: a geometry has "
                + String(len(channels))
                + " blend shape targets, and a mesh wears at most "
                + String(MAX_MORPH_TARGETS)
            )
        for slot in range(len(channels)):
            var shape = self.rig.shapes[channels[slot]]
            self.rig.slots[channels[slot]] = slot
            var offsets = List[Vector3](length=count, fill=Vector3(0, 0, 0))
            var indices = List[Int]()
            var found = self.document.child(shape, "Indexes")
            if found != NO_FBX_NODE:
                indices = self.document.integers(found)
            var moved = List[Float64]()
            found = self.document.child(shape, "Vertices")
            if found != NO_FBX_NODE:
                moved = self.document.numbers(found)
            if len(moved) != len(indices) * 3:
                raise Error("FBX: a shape needs three numbers per index")
            for at in range(len(indices)):
                var vertex = indices[at]
                if not _within(vertex, count):
                    raise Error(
                        "FBX: a shape names a position that is not there"
                    )
                offsets[vertex] = Vector3(
                    Float32(moved[at * 3]),
                    Float32(moved[at * 3 + 1]),
                    Float32(moved[at * 3 + 2]),
                )
            for vertex in range(count):
                offsets[vertex] = pre.transform_point(offsets[vertex])
            rows.morphs.append(offsets^)
        return rows^

    def add_piece(
        mut self,
        model: Int,
        source: Int,
        geometry: GeometryId,
        materials: List[MaterialId],
        node: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add a model's geometry: a mesh with its one material or its
        list, or, for a skinned geometry, a skinned mesh once every bone
        is placed.

        A skinned mesh here wears one material. A skinned geometry with
        more than one material is cut into a geometry for each group it
        draws, each a skinned mesh in its group's material. three.js
        keeps one `SkinnedMesh` with the list.
        """
        if source in self.rig.skin_of:
            if len(materials) == 1:
                self.rig.waiting.append(
                    _Waiting(model, source, geometry, materials[0], node)
                )
                return
            var groups = assets.geometries.get(geometry).groups.copy()
            for group in groups:
                if group.material_index.value >= len(materials):
                    continue
                var cut = assets.geometries.get(geometry).group_part(group)
                var made = assets.geometries.add(cut^)
                self.model.geometries.append(made)
                self.rig.waiting.append(
                    _Waiting(
                        model,
                        source,
                        made,
                        materials[group.material_index.value],
                        node,
                    )
                )
            return
        if source in self.rig.channels:
            self.morph_target_of(
                model, TrackTarget(MORPH_INFLUENCE, len(scene.meshes), 0)
            )
        if len(materials) > 1:
            scene.add_mesh(Mesh(geometry, materials, node))
        else:
            scene.add_mesh(Mesh(geometry, materials[0], node))

    def morph_target_of(mut self, model: Int, target: TrackTarget) raises:
        """Record a mesh of a model that wears morph targets."""
        if model not in self.rig.morphs:
            self.rig.morphs[model] = List[TrackTarget]()
        self.rig.morphs[model].append(target)

    def bind_skins(mut self, mut scene: Scene) raises:
        """Add every skinned piece, bound to its skin's bones, as three.js's
        `bindSkeleton` binds it.

        Raises:
            Error: If a cluster has no bone, or a bind matrix or an inverse
                bind is one `SkinnedMesh` or `Skeleton` refuses.
        """
        if len(self.rig.waiting) == 0:
            return
        var placed = Dict[Int, NodeId]()
        # A piece waits for a model that drew it, and the list is not
        # empty: both loops run.
        for at in range(len(self.model.model_ids)):  # pragma: no branch
            placed[self.model.model_ids[at]] = self.model.models[at]
        for waiting in self.rig.waiting:  # pragma: no branch
            var skin = self.rig.skin_of[waiting.source]
            var bones = List[Bone]()
            for cluster in self.rig.clusters[skin]:
                var bone = -1
                for link in self.links(self.children, cluster.id):
                    if link.id in placed:
                        bone = link.id
                if bone < 0:
                    raise Error("FBX: a cluster has no bone")
                bones.append(Bone(placed[bone], _inverse(cluster.link)))
            var bind = Matrix4()
            if waiting.model in self.rig.poses:
                bind = self.rig.poses[waiting.model]
            if waiting.source in self.rig.channels:
                self.morph_target_of(
                    waiting.model,
                    TrackTarget(
                        SKINNED_MORPH_INFLUENCE, len(scene.skinned_meshes), 0
                    ),
                )
            scene.add_skinned_mesh(
                SkinnedMesh(
                    waiting.geometry,
                    waiting.material,
                    waiting.node,
                    Skeleton(bones^),
                    bind,
                )
            )

    def read_animations(mut self, scene: Scene) raises:
        """Read the animation stacks into clips on the placed models."""
        var models = Dict[Int, FbxAnimatedModel]()
        for at in range(len(self.model.model_ids)):
            var id = self.model.model_ids[at]
            var node = self.objects[id]
            var placed = scene.get(self.model.models[at])
            var animated = FbxAnimatedModel(
                self.model.models[at],
                placed.position,
                placed.scale,
                fbx_euler_order(Int(self.value(node, "RotationOrder", 0))),
                self.vector(node, "PreRotation", Vector3(0, 0, 0)),
                self.vector(node, "PostRotation", Vector3(0, 0, 0)),
            )
            if id in self.rig.morphs:
                animated.morphs = self.rig.morphs[id].copy()
            models[id] = animated^
        self.model.animations = read_fbx_animations(
            self.document, self.objects_node, models, self.rig.slots
        )


def _within(index: Int, count: Int) -> Bool:
    """Return True if an index is from zero to below a count."""
    return index >= 0 and index < count


def _four_largest(
    bones: List[Int], weights: List[Float64]
) -> Tuple[List[Int], List[Float64]]:
    """Return a vertex's bones and weights, four of each: as they come when
    there are four or fewer, padded with bone zero at weight zero, and the
    four largest, largest first, when there are more, as three.js's
    `genBuffers` keeps them."""
    if len(weights) <= 4:
        var kept = bones.copy()
        var shares = weights.copy()
        while len(shares) < 4:
            kept.append(0)
            shares.append(0)
        return (kept^, shares^)
    var kept: List[Int] = [0, 0, 0, 0]
    var shares: List[Float64] = [0, 0, 0, 0]
    for at in range(len(weights)):  # pragma: no branch
        var weight = weights[at]
        var bone = bones[at]
        for lane in range(4):  # pragma: no branch
            if weight > shares[lane]:
                var held = shares[lane]
                shares[lane] = weight
                weight = held
                var named = kept[lane]
                kept[lane] = bone
                bone = named
    return (kept^, shares^)


def _add_material_groups(
    mut geometry: BufferGeometry, indices: List[Int]
) raises:
    """Add a group per run of corners of one material index, three.js's
    `addGroup` loop in `genGeometry`.

    A run ends where the index changes, and the last run is added after
    the loop. A geometry with no corners gets one group of none, at the
    first material, as three.js adds one when the loop added none.

    Args:
        geometry: The geometry, which the groups are added to.
        indices: The material index of each corner.

    Raises:
        Error: Never: every run starts and counts at zero or more.
    """
    if len(indices) == 0:
        geometry.add_group(0, 0, MaterialIndex(0))
        return
    var start = 0
    # The corners come three a triangle, so there are three at least here
    # and the loop always runs.
    for at in range(1, len(indices)):  # pragma: no branch
        if indices[at] != indices[at - 1]:
            geometry.add_group(start, at - start, MaterialIndex(indices[start]))
            start = at
    geometry.add_group(
        start, len(indices) - start, MaterialIndex(indices[start])
    )


struct _Face(Movable):
    """The corners of the polygon being read, and its material index."""

    var points: List[Vector3]
    var normals: List[Vector3]
    var uvs: List[Vector2]
    var colors: List[Vector3]
    var vertices: List[Int]
    var material: Int

    def __init__(out self):
        self.points = List[Vector3]()
        self.normals = List[Vector3]()
        self.uvs = List[Vector2]()
        self.colors = List[Vector3]()
        self.vertices = List[Int]()
        self.material = 0

    def emit(self, mut part: _Part) raises:
        """Append this polygon's triangles to a part: itself when it is a
        triangle, cut by `_triangulate` when it has more corners, and
        nothing when it has fewer than three, which has no surface."""
        var count = len(self.points)
        if count < 3:
            return
        var order: List[Int] = [0, 1, 2]
        if count > 3:
            order = _triangulate(self.points)
        # Three corners or more: the loop always runs.
        for corner in order:  # pragma: no branch
            var p = self.points[corner]
            part.vertices.append(self.vertices[corner])
            part.positions.append(p.x)
            part.positions.append(p.y)
            part.positions.append(p.z)
            if len(self.normals) > 0:
                var n = self.normals[corner]
                part.normals.append(n.x)
                part.normals.append(n.y)
                part.normals.append(n.z)
            if len(self.uvs) > 0:
                part.uvs.append(self.uvs[corner].x)
                part.uvs.append(self.uvs[corner].y)
            if len(self.colors) > 0:
                var c = self.colors[corner]
                part.colors.append(c.x)
                part.colors.append(c.y)
                part.colors.append(c.z)
