# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.skeleton_utils` and `Skeleton.calculate_inverses`:
three.js's `SkeletonUtils` and the scene-reading half of `Skeleton`.
"""

from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from core.skeleton_utils import (
    RetargetOptions,
    bone_world_matrices,
    calculate_inverses,
    clone_skinned,
    get_bone_by_name,
    restore_bind_pose,
    retarget,
)
from materials.material import MaterialId
from math.matrix4 import Matrix4, rotation_z, scaling, translation
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.skeleton import Bone, Skeleton, bind_skeleton
from objects.skinned_mesh import SkinnedMesh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE

comptime TOLERANCE = Float64(1e-4)


def named(
    mut scene: Scene,
    name: String,
    parent: NodeId,
    x: Float32,
    y: Float32,
    z: Float32,
) raises -> NodeId:
    """Add a named node at a position under a parent."""
    var node = Object3D()
    node.name = name
    node.parent = parent
    node.set_position(x, y, z)
    return scene.add(node^)


def rig(
    mut scene: Scene, hip: String, spine: String, height: Float32
) raises -> Int:
    """Add a root holding a mesh node and two bones, a hip at `height` and
    a spine one meter above it, bound where they stand; return the skinned
    mesh's index."""
    var root = named(scene, "root", NO_PARENT, 0, 0, 0)
    var mesh = named(scene, "mesh", root, 0, 0, 0)
    var hips = named(scene, hip, root, 0, height, 0)
    var back = named(scene, spine, hips, 0, 1, 0)
    scene.update()
    var nodes: List[NodeId] = [hips, back]
    var skeleton = bind_skeleton(
        nodes, [scene.world_matrix(hips), scene.world_matrix(back)]
    )
    scene.add_skinned_mesh(
        SkinnedMesh(GeometryId(0), MaterialId(0), mesh, skeleton^)
    )
    scene.update()
    return len(scene.skinned_meshes) - 1


def close(a: Matrix4, b: Matrix4) raises:
    """Assert two matrices agree element by element."""
    for index in range(16):
        assert_almost_equal(
            a.elements[index], b.elements[index], atol=TOLERANCE
        )


# --- Skeleton -----------------------------------------------------------------


def test_bones_are_found_by_name() raises:
    var scene = Scene()
    var index = rig(scene, "Hips", "Spine", 1)
    ref skeleton = scene.skinned_meshes[index].skeleton
    var found = get_bone_by_name(scene, skeleton, "Spine")
    assert_true(Bool(found))
    assert_equal(found.value(), skeleton.node(1))
    assert_false(Bool(get_bone_by_name(scene, skeleton, "Tail")))


def test_inverses_are_calculated_where_the_bones_stand() raises:
    var scene = Scene()
    var index = rig(scene, "Hips", "Spine", 1)
    var skeleton = scene.skinned_meshes[index].skeleton.copy()
    scene.node(skeleton.node(0)).set_position(3, 0, 0)
    scene.update()
    calculate_inverses(scene, skeleton)
    # Bound where they stand now, so the pose is the identity.
    var pose = skeleton.pose(bone_world_matrices(scene, skeleton))
    close(pose[0], Matrix4())
    close(pose[1], Matrix4())


def test_calculating_inverses_refuses_what_has_no_inverse() raises:
    var scene = Scene()
    var index = rig(scene, "Hips", "Spine", 1)
    var skeleton = scene.skinned_meshes[index].skeleton.copy()
    var before = Matrix4(copy=skeleton.bones[0].inverse_bind)
    with assert_raises(contains="one world matrix for every bone"):
        skeleton.calculate_inverses([Matrix4()])
    with assert_raises(contains="no size"):
        skeleton.calculate_inverses([Matrix4(), scaling(0, 1, 1)])
    # Nothing changed.
    close(skeleton.bones[0].inverse_bind, before)


def test_the_bind_pose_is_restored() raises:
    var scene = Scene()
    var index = rig(scene, "Hips", "Spine", 1)
    var skeleton = scene.skinned_meshes[index].skeleton.copy()
    var bound = bone_world_matrices(scene, skeleton)
    scene.node(skeleton.node(0)).set_position(4, 0, 0)
    scene.node(skeleton.node(1)).rotate_z(Angle(40, DEGREE))
    scene.update()
    restore_bind_pose(scene, skeleton)
    var now = bone_world_matrices(scene, skeleton)
    close(now[0], bound[0])
    close(now[1], bound[1])


def test_a_root_bone_takes_its_world_matrix_as_its_own() raises:
    # three.js's `Skeleton.pose` sets a bone whose parent is no bone to its
    # bind-time world matrix, whatever the parent's transform.
    var scene = Scene()
    var index = rig(scene, "Hips", "Spine", 1)
    var skeleton = scene.skinned_meshes[index].skeleton.copy()
    var root = scene.get(skeleton.node(0)).parent
    scene.node(root).set_position(0, 5, 0)
    scene.update()
    restore_bind_pose(scene, skeleton)
    assert_almost_equal(
        scene.get(skeleton.node(0)).position.y, Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(
        scene.world_position(skeleton.node(0)).y, Float32(6), atol=TOLERANCE
    )


def test_the_bind_pose_refuses_a_flat_bind() raises:
    var scene = Scene()
    _ = rig(scene, "Hips", "Spine", 1)
    var flat = Skeleton([Bone(NodeId(2), Matrix4())])
    flat.bones[0].inverse_bind = scaling(0, 1, 1)
    with assert_raises(contains="flattens an axis"):
        restore_bind_pose(scene, flat)


# --- clone ------------------------------------------------------------------


def test_a_clone_is_carried_by_its_own_bones() raises:
    var scene = Scene()
    var index = rig(scene, "Hips", "Spine", 1)
    var root = scene.get(scene.skinned_meshes[index].node).parent
    var copy = clone_skinned(scene, root)
    assert_equal(len(scene.skinned_meshes), 2)
    ref cloned = scene.skinned_meshes[1]
    ref original = scene.skinned_meshes[0]
    assert_true(cloned.skeleton.node(0) != original.skeleton.node(0))
    assert_true(cloned.skeleton.node(1) != original.skeleton.node(1))
    assert_equal(scene.get(cloned.skeleton.node(0)).name, "Hips")
    assert_equal(
        scene.get(cloned.skeleton.node(1)).parent, cloned.skeleton.node(0)
    )
    # The bones are under the copy.
    var under = scene.traverse(copy)
    var inside = False
    for node in under:
        if node == cloned.skeleton.node(1):
            inside = True
    assert_true(inside)
    close(
        cloned.skeleton.bones[1].inverse_bind,
        original.skeleton.bones[1].inverse_bind,
    )


def test_a_bone_outside_the_clone_is_kept() raises:
    # Only the mesh node is copied, so neither bone has a copy.
    var scene = Scene()
    var index = rig(scene, "Hips", "Spine", 1)
    var mesh = scene.skinned_meshes[index].node
    _ = clone_skinned(scene, mesh)
    assert_equal(
        scene.skinned_meshes[1].skeleton.node(0),
        scene.skinned_meshes[0].skeleton.node(0),
    )


def test_a_clone_of_nothing_skinned_changes_no_skeleton() raises:
    var scene = Scene()
    _ = rig(scene, "Hips", "Spine", 1)
    var lone = named(scene, "lone", NO_PARENT, 0, 0, 0)
    scene.update()
    _ = clone_skinned(scene, lone)
    assert_equal(len(scene.skinned_meshes), 1)


# --- retarget ---------------------------------------------------------------


def two_rigs(mut scene: Scene) raises -> Tuple[Int, Int]:
    """Return a target rig, `Hips` and `Spine` at one meter, and a source
    rig, `hip` and `spine` at two meters, its spine turned 90 degrees."""
    var target = rig(scene, "Hips", "Spine", 1)
    var source = rig(scene, "hip", "spine", 2)
    var spine = scene.skinned_meshes[source].skeleton.node(1)
    scene.node(spine).rotate_z(Angle(90, DEGREE))
    scene.update()
    return (target, source)


def mapping() -> Dict[String, String]:
    """Return the target-to-source bone names."""
    var names = Dict[String, String]()
    names["Hips"] = "hip"
    names["Spine"] = "spine"
    return names^


def test_retarget_copies_the_turn_and_keeps_the_positions() raises:
    var scene = Scene()
    var pair = two_rigs(scene)
    var options = RetargetOptions()
    options.names = mapping()
    var source = scene.skinned_meshes[pair[1]].skeleton.copy()
    retarget(scene, pair[0], source, options)
    ref target = scene.skinned_meshes[pair[0]].skeleton
    var turned = scene.world_quaternion(target.node(1))
    var wanted = scene.world_quaternion(source.node(1))
    assert_almost_equal(abs(turned.dot(wanted)), Float32(1), atol=TOLERANCE)
    # The spine keeps its own position; the hip takes the source's.
    assert_almost_equal(
        scene.get(target.node(1)).position.y, Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(
        scene.world_position(target.node(0)).y, Float32(2), atol=TOLERANCE
    )


def test_retarget_moves_and_scales_the_hip() raises:
    var scene = Scene()
    var pair = two_rigs(scene)
    var options = RetargetOptions()
    options.names = mapping()
    options.scale = 2
    options.hip_influence = Vector3(1, 0.5, 1)
    options.hip_position = Vector3(1, 0, 0)
    var source = scene.skinned_meshes[pair[1]].skeleton.copy()
    retarget(scene, pair[0], source, options)
    ref target = scene.skinned_meshes[pair[0]].skeleton
    # y: 2 * 2 * 0.5; x: 0 + 1 * 2.
    var hip = scene.world_position(target.node(0))
    assert_almost_equal(hip.y, Float32(2), atol=TOLERANCE)
    assert_almost_equal(hip.x, Float32(2), atol=TOLERANCE)


def test_retarget_without_preserving_positions_moves_every_bone() raises:
    var scene = Scene()
    var pair = two_rigs(scene)
    var options = RetargetOptions()
    options.names = mapping()
    options.preserve_bone_positions = False
    var source = scene.skinned_meshes[pair[1]].skeleton.copy()
    retarget(scene, pair[0], source, options)
    ref target = scene.skinned_meshes[pair[0]].skeleton
    assert_almost_equal(
        scene.world_position(target.node(1)).y,
        scene.world_position(source.node(1)).y,
        atol=TOLERANCE,
    )


def test_retarget_measures_from_the_mesh_or_not() raises:
    # The target mesh's node moved: held, it is undone; not held, the
    # source bones are measured from it; with the target matrix, they are
    # taken as they are.
    var answers = List[Float32]()
    for which in range(3):
        var scene = Scene()
        var pair = two_rigs(scene)
        var carrier = scene.skinned_meshes[pair[0]].node
        scene.node(carrier).set_position(0, 3, 0)
        scene.update()
        var options = RetargetOptions()
        options.names = mapping()
        options.preserve_bone_matrix = which != 1
        options.use_target_matrix = which == 2
        options.preserve_bone_positions = False
        var source = scene.skinned_meshes[pair[1]].skeleton.copy()
        retarget(scene, pair[0], source, options)
        answers.append(
            scene.world_position(
                scene.skinned_meshes[pair[0]].skeleton.node(0)
            ).y
        )
    assert_almost_equal(answers[0], Float32(2), atol=TOLERANCE)
    assert_almost_equal(answers[1], Float32(-1), atol=TOLERANCE)
    assert_almost_equal(answers[2], Float32(2), atol=TOLERANCE)


def test_retarget_turns_by_a_local_offset() raises:
    var scene = Scene()
    var pair = two_rigs(scene)
    var options = RetargetOptions()
    options.names = mapping()
    options.local_offsets["Spine"] = rotation_z(Angle(-90, DEGREE))
    var source = scene.skinned_meshes[pair[1]].skeleton.copy()
    retarget(scene, pair[0], source, options)
    ref target = scene.skinned_meshes[pair[0]].skeleton
    # The offset undoes the source's turn.
    var turned = scene.world_quaternion(target.node(1))
    assert_almost_equal(abs(turned.w), Float32(1), atol=TOLERANCE)


def test_retarget_leaves_an_unnamed_bone_in_its_bind_pose() raises:
    var scene = Scene()
    var pair = two_rigs(scene)
    var source = scene.skinned_meshes[pair[1]].skeleton.copy()
    # No names: three.js maps nothing without them.
    retarget(scene, pair[0], source)
    var target = scene.skinned_meshes[pair[0]].skeleton.copy()
    assert_almost_equal(
        scene.world_position(target.node(0)).y, Float32(1), atol=TOLERANCE
    )
    # A name that maps to no source bone.
    var options = RetargetOptions()
    options.names["Spine"] = "tail"
    retarget(scene, pair[0], source, options)
    assert_almost_equal(
        abs(scene.world_quaternion(target.node(1)).w),
        Float32(1),
        atol=TOLERANCE,
    )


def test_retarget_measures_bones_under_the_mesh() raises:
    # The target's hip is a root of the scene, with no parent, and its
    # spine hangs under the mesh's node: held, the mesh's node stands at
    # the identity and the spine is measured from it.
    var scene = Scene()
    var mesh = named(scene, "mesh", NO_PARENT, 0, 5, 0)
    var hips = named(scene, "Hips", NO_PARENT, 0, 1, 0)
    var back = named(scene, "Spine", mesh, 0, 1, 0)
    scene.update()
    var nodes: List[NodeId] = [hips, back]
    var skeleton = bind_skeleton(
        nodes, [scene.world_matrix(hips), scene.world_matrix(back)]
    )
    scene.add_skinned_mesh(
        SkinnedMesh(GeometryId(0), MaterialId(0), mesh, skeleton^)
    )
    var source = rig(scene, "hip", "spine", 2)
    var spine = scene.skinned_meshes[source].skeleton.node(1)
    scene.node(spine).rotate_z(Angle(90, DEGREE))
    scene.update()
    var options = RetargetOptions()
    options.names = mapping()
    options.preserve_bone_positions = False
    var bones = scene.skinned_meshes[source].skeleton.copy()
    retarget(scene, 0, bones, options)
    # The spine's own transform is the source spine's world transform,
    # since its held parent is the identity.
    assert_almost_equal(
        scene.get(back).position.y,
        scene.world_position(bones.node(1)).y,
        atol=TOLERANCE,
    )
    assert_almost_equal(
        scene.world_position(hips).y, Float32(2), atol=TOLERANCE
    )


def test_retarget_refuses_what_it_cannot_read() raises:
    var scene = Scene()
    var pair = two_rigs(scene)
    var source = scene.skinned_meshes[pair[1]].skeleton.copy()
    with assert_raises(contains="No skinned mesh"):
        retarget(scene, 5, source)
    with assert_raises(contains="No skinned mesh"):
        retarget(scene, -1, source)
    scene.node(source.node(1)).set_scale(0, 1, 1)
    scene.update()
    var options = RetargetOptions()
    options.names = mapping()
    with assert_raises(contains="flattens an axis"):
        retarget(scene, pair[0], source, options)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
