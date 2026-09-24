# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skeleton tools, from three.js `examples/jsm/utils/SkeletonUtils.js` and
the parts of `src/objects/Skeleton.js` that read a scene.

A `Skeleton` names its bones by node and holds their inverse binds. It
cannot read the scene, because `core.scene` imports it. So the three.js
methods that read a bone's name or its world matrix are free functions
here, each given the scene:

- `get_bone_by_name` is three.js's `Skeleton.getBoneByName`.
- `calculate_inverses` is three.js's `Skeleton.calculateInverses`, with
  the world matrices read from the scene.
- `restore_bind_pose` is three.js's `Skeleton.pose`, which puts every bone
  back where it was bound. `Skeleton.pose` here is three.js's
  `Skeleton.update`, so this has another name.
- `clone_skinned` is three.js's `SkeletonUtils.clone`.
- `retarget` is three.js's `SkeletonUtils.retarget`.

## Clone

`Scene.clone` copies a subtree and what its nodes carry. A copied skinned
mesh keeps its skeleton, as three.js's `Object3D.clone` shares it, so the
copy is still carried by the original bones. `clone_skinned` copies the
subtree, then points each copied skinned mesh at the copies of its bones.
The copies are matched by walking the two subtrees side by side, three.js's
`parallelTraverse`. A bone outside the copied subtree has no copy. three.js
then puts `undefined` in the skeleton. Here the copy keeps the original
bone.

## Retarget

`retarget` poses one skinned mesh's bones like another skeleton's. Each
target bone takes the rotation of the source bone its name maps to, in
world space, and keeps its own position unless it is the hip. The
arithmetic is three.js's, step for step. `RetargetOptions` holds three.js's
options with its defaults. The target must be a skinned mesh; three.js
also takes a bare skeleton, which forces two of the options. three.js's
`getBoneName` function option and `retargetClip` are not ported.
"""

from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from math.matrix4 import Matrix4, compose
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.skeleton import Skeleton


def bone_world_matrices(
    scene: Scene, skeleton: Skeleton
) raises -> List[Matrix4]:
    """Return every bone's world matrix, in the skeleton's order.

    Args:
        scene: The scene the bones are in, updated.
        skeleton: The skeleton.

    Returns:
        One matrix per bone, for `Skeleton.pose` or
        `Skeleton.calculate_inverses`.

    Raises:
        Error: If a bone's node is not in the scene, or the scene is stale.
    """
    var placed = List[Matrix4]()
    for bone in range(skeleton.bone_count()):  # pragma: no branch
        placed.append(scene.world_matrix(skeleton.node(bone)))
    return placed^


def calculate_inverses(scene: Scene, mut skeleton: Skeleton) raises:
    """Bind every bone where it stands now, three.js's
    `Skeleton.calculateInverses`.

    Args:
        scene: The scene the bones are in, updated.
        skeleton: The skeleton, whose inverse binds are replaced.

    Raises:
        Error: If a bone's node is not in the scene, the scene is stale, or
            a bone stands at a scale of zero; see
            `Skeleton.calculate_inverses`.
    """
    skeleton.calculate_inverses(bone_world_matrices(scene, skeleton))


def get_bone_by_name(
    scene: Scene, skeleton: Skeleton, name: String
) raises -> Optional[NodeId]:
    """Return the first bone with a name, three.js's
    `Skeleton.getBoneByName`.

    Args:
        scene: The scene the bones are in.
        skeleton: The skeleton to search.
        name: The node name to find.

    Returns:
        The bone's node, or none when no bone has the name.

    Raises:
        Error: If a bone's node is not in the scene.
    """
    for bone in range(skeleton.bone_count()):  # pragma: no branch
        var node = skeleton.node(bone)
        if scene.get(node).name == name:
            return node
    return None


def _bone_index(skeleton: Skeleton, node: NodeId) raises -> Int:
    """Return which bone a node is, or -1 when it is none of them."""
    var found = -1
    for bone in range(skeleton.bone_count()):  # pragma: no branch
        if skeleton.node(bone) == node:
            found = bone
    return found


def restore_bind_pose(mut scene: Scene, skeleton: Skeleton) raises:
    """Put every bone back where it was bound, three.js's `Skeleton.pose`.

    Each bone's bind-time world matrix is the inverse of its inverse bind.
    A bone whose parent is also a bone of the skeleton takes the local
    transform that puts it there under that parent's bind-time matrix. Any
    other bone takes the world matrix itself as its local transform, as
    three.js takes it. three.js asks whether the parent `isBone`; here a
    bone is a node the skeleton names. The scene is updated after.

    Args:
        scene: The scene the bones are in.
        skeleton: The skeleton.

    Raises:
        Error: If a bone's node is not in the scene, or a bind-time matrix
            flattens an axis and so has no rotation to set.
    """
    var worlds = List[Matrix4]()
    for bone in range(skeleton.bone_count()):  # pragma: no branch
        var world = Matrix4(copy=skeleton.bones[bone].inverse_bind)
        world.invert()
        worlds.append(world^)
    for bone in range(skeleton.bone_count()):  # pragma: no branch
        var node = skeleton.node(bone)
        var parent = _bone_index(skeleton, scene.get(node).parent)
        var local = Matrix4(copy=worlds[bone])
        if parent >= 0:
            local = Matrix4(copy=worlds[parent])
            local.invert()
            local.multiply(worlds[bone])
        _place(scene, node, local)
    scene.update()


def _place(mut scene: Scene, node: NodeId, local: Matrix4) raises:
    """Give a node a local transform, three.js's
    `bone.matrix.decompose(bone.position, bone.quaternion, bone.scale)`."""
    ref moved = scene.node(node)
    moved.set_from_matrix(local)
    moved.matrix = Matrix4(copy=local)


def clone_skinned(mut scene: Scene, source: NodeId) raises -> NodeId:
    """Copy a node and what is under it, with each copied skinned mesh
    carried by the copies of its bones: three.js's `SkeletonUtils.clone`.

    Args:
        scene: The scene the node is in.
        source: The node to copy.

    Returns:
        The copy, with no parent and removed, as `Scene.clone` returns it.

    Raises:
        Error: For anything `Scene.clone` raises for.
    """
    var first = len(scene.skinned_meshes)
    var copy = scene.clone(source)
    var originals = scene.traverse(source)
    var copies = scene.traverse(copy)
    for index in range(first, len(scene.skinned_meshes)):
        ref skeleton = scene.skinned_meshes[index].skeleton
        for bone in range(len(skeleton.bones)):  # pragma: no branch
            for at in range(len(originals)):  # pragma: no branch
                if originals[at] == skeleton.bones[bone].node:
                    skeleton.bones[bone].node = copies[at]
    return copy


@fieldwise_init
struct RetargetOptions(Copyable, Movable):
    """The options of three.js's `retarget`, with its defaults."""

    # Undo the target mesh's own world matrix while the bones are set, so
    # that the bones are measured in the mesh's space: three.js's
    # `preserveBoneMatrix`.
    var preserve_bone_matrix: Bool
    # Keep every bone's position but the hip's: three.js's
    # `preserveBonePositions`.
    var preserve_bone_positions: Bool
    # Take the source bones' world matrices as they are, rather than
    # measured from the target mesh: three.js's `useTargetMatrix`.
    var use_target_matrix: Bool
    # The source bone name of the hip, whose position is carried over:
    # three.js's `hip`.
    var hip: String
    # How much of the hip's position is carried, along each axis:
    # three.js's `hipInfluence`.
    var hip_influence: Vector3
    # Where the hip is put, before the scale, if anywhere: three.js's
    # `hipPosition`.
    var hip_position: Optional[Vector3]
    # What the hip's position is scaled by: three.js's `scale`.
    var scale: Float32
    # For each target bone's name, the source bone's name: three.js's
    # `names`. A target bone not named here takes no source bone.
    var names: Dict[String, String]
    # A turn applied after the source's, by target bone name: three.js's
    # `localOffsets`.
    var local_offsets: Dict[String, Matrix4]

    def __init__(out self):
        """Return three.js's defaults: both preserves on, the target matrix
        off, a hip named `hip` carried at full influence and a scale of one,
        and no names and no offsets."""
        self.preserve_bone_matrix = True
        self.preserve_bone_positions = True
        self.use_target_matrix = False
        self.hip = "hip"
        self.hip_influence = Vector3(1, 1, 1)
        self.hip_position = None
        self.scale = 1
        self.names = Dict[String, String]()
        self.local_offsets = Dict[String, Matrix4]()


def _held_world(
    scene: Scene, node: NodeId, target: NodeId, held: Bool
) raises -> Matrix4:
    """Return a node's world matrix as `retarget` sees it.

    With `held`, the target mesh's node stands at the identity and the
    nodes under it follow, three.js's `target.matrixWorld.identity()` and
    `updateMatrixWorld` on its children. Other nodes keep their world
    matrices.
    """
    if not held:
        return scene.world_matrix(node)
    var chain = List[NodeId]()
    var at = node
    while at != NO_PARENT and at != target:
        chain.append(at)
        at = scene.get(at).parent
    if at == NO_PARENT:
        return scene.world_matrix(node)
    var world = Matrix4()
    for index in range(len(chain) - 1, -1, -1):
        world.multiply(scene.get(chain[index]).matrix)
    return world^


def _column_lengths(matrix: Matrix4) -> Vector3:
    """Return the lengths of the first three columns, three.js's
    `setFromMatrixScale`: no sign for a mirror."""
    ref e = matrix.elements
    return Vector3(
        Vector3(e[0], e[1], e[2]).length(),
        Vector3(e[4], e[5], e[6]).length(),
        Vector3(e[8], e[9], e[10]).length(),
    )


def retarget(
    mut scene: Scene,
    target: Int,
    source: Skeleton,
    options: RetargetOptions = RetargetOptions(),
) raises:
    """Pose one skinned mesh's bones like another skeleton's bones,
    three.js's `SkeletonUtils.retarget`.

    The target's bones are first put back in their bind pose. Then each
    bone, in the skeleton's order, whose name `options.names` maps to a
    source bone takes that bone's world rotation, turned by its local
    offset, and the source bone's world position. The hip's position is
    scaled by `options.scale` and its influence, and moved by
    `options.hip_position`. With `preserve_bone_positions`, every other
    bone then takes back the position it had in the bind pose. The scene
    is updated after.

    Args:
        scene: The scene both skeletons' bones are in, updated.
        target: Which skinned mesh to pose, as its position in
            `scene.skinned_meshes`.
        source: The skeleton to copy the pose of.
        options: The options; see `RetargetOptions`.

    Raises:
        Error: If no skinned mesh has that index, a bone's node is not in
            the scene, the scene is stale, or a matrix flattens an axis and
            so has no rotation to read or set.
    """
    if target < 0 or target >= len(scene.skinned_meshes):
        raise Error("No skinned mesh has that index")
    var bones = scene.skinned_meshes[target].skeleton.copy()
    var mesh = scene.skinned_meshes[target].node
    var held = options.preserve_bone_matrix
    restore_bind_pose(scene, bones)
    var positions = List[Vector3]()
    for bone in range(bones.bone_count()):  # pragma: no branch
        positions.append(scene.get(bones.node(bone)).position)
    for bone in range(bones.bone_count()):  # pragma: no branch
        var node = bones.node(bone)
        var own = scene.get(node)
        var name = options.names.get(own.name)
        var placed = _held_world(scene, node, mesh, held)
        var found = Optional[NodeId](None)
        if Bool(name):
            found = get_bone_by_name(scene, source, name.value())
        if Bool(found):
            var relative = _held_world(scene, found.value(), mesh, held)
            if not options.use_target_matrix:
                var undo = _held_world(scene, mesh, mesh, held)
                undo.invert()
                relative.premultiply(undo)
            var size = _column_lengths(relative)
            if size.x * size.y * size.z == 0:
                raise Error("A source bone that flattens an axis has no turn")
            relative.scale(Vector3(1 / size.x, 1 / size.y, 1 / size.z))
            placed = compose(
                Vector3(0, 0, 0),
                Quaternion.from_matrix(relative),
                Vector3(1, 1, 1),
            )
            var offset = options.local_offsets.get(own.name)
            if Bool(offset):
                placed.multiply(offset.value())
            placed.copy_position(relative)
        if Bool(name) and name.value() == options.hip:
            var reach = options.hip_influence * options.scale
            placed.elements[12] *= reach.x
            placed.elements[13] *= reach.y
            placed.elements[14] *= reach.z
            if Bool(options.hip_position):
                var moved = options.hip_position.value() * options.scale
                placed.elements[12] += moved.x
                placed.elements[13] += moved.y
                placed.elements[14] += moved.z
        var local = Matrix4(copy=placed)
        if own.parent != NO_PARENT:
            local = _held_world(scene, own.parent, mesh, held)
            local.invert()
            local.multiply(placed)
        _place(scene, node, local)
        scene.update()
    if options.preserve_bone_positions:
        for bone in range(bones.bone_count()):  # pragma: no branch
            var node = bones.node(bone)
            var own = scene.get(node).name
            var name = options.names.get(own).or_else(own)
            if name != options.hip:
                scene.node(node).position = positions[bone]
        scene.update()
