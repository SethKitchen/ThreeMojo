# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.object3d` and `core.scene`."""

from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from math.vector3 import Vector3
from math.matrix4 import Matrix4
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE

comptime TOLERANCE = Float64(1e-5)


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches the given components, within tolerance.

    Args:
        got: The point to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.

    Raises:
        Error: If any component differs.
    """
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def node_at(x: Float32, y: Float32, z: Float32) -> Object3D:
    """Return an untransformed node moved to the given position."""
    var node = Object3D()
    node.set_position(x, y, z)
    return node^


# --- Object3D ---------------------------------------------------------------


def test_a_new_node_is_untransformed_and_parentless() raises:
    var node = Object3D()
    assert_equal(node.parent, NO_PARENT)
    assert_point(node.position, 0, 0, 0)
    assert_point(node.scale, 1, 1, 1)
    assert_point(node.local_matrix().transform_point(Vector3(1, 2, 3)), 1, 2, 3)


def test_position_moves_the_local_transform() raises:
    assert_point(
        node_at(5, 6, 7).local_matrix().transform_point(Vector3(0, 0, 0)),
        5,
        6,
        7,
    )


def test_scale_applies_before_translation() raises:
    # Composition is translation * rotation * scale, so a point is scaled
    # about the node's own origin and then moved, not the other way round.
    var node = node_at(10, 0, 0)
    node.set_scale(2, 2, 2)
    assert_point(
        node.local_matrix().transform_point(Vector3(1, 0, 0)), 12, 0, 0
    )


def test_rotation_applies_before_translation() raises:
    var node = node_at(10, 0, 0)
    node.set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(90.0, DEGREE))
    assert_point(
        node.local_matrix().transform_point(Vector3(1, 0, 0)), 10, 1, 0
    )


def test_euler_angles_apply_x_then_y_then_z() raises:
    var node = Object3D()
    node.set_euler(Angle(90.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    # x turns +y onto +z, then y turns +z onto +x.
    assert_point(node.local_matrix().transform_point(Vector3(0, 1, 0)), 1, 0, 0)


def test_copying_a_node_leaves_the_original_alone() raises:
    var original = node_at(1, 2, 3)
    var copy = Object3D(copy=original)
    copy.set_position(9, 9, 9)
    assert_point(original.position, 1, 2, 3)


# --- Scene ------------------------------------------------------------------


def test_a_new_scene_is_empty() raises:
    assert_equal(Scene().count(), 0)


def test_adding_returns_increasing_indices() raises:
    var scene = Scene()
    assert_equal(scene.add(Object3D()), 0)
    assert_equal(scene.add(Object3D()), 1)
    assert_equal(scene.count(), 2)


def test_a_root_node_world_matrix_is_its_local_one() raises:
    var scene = Scene()
    var root = scene.add(node_at(5, 6, 7))
    scene.update()
    assert_point(scene.world_position(root), 5, 6, 7)


def test_a_child_is_positioned_relative_to_its_parent() raises:
    var scene = Scene()
    var parent = scene.add(node_at(10, 0, 0))
    var child = scene.attach(node_at(0, 5, 0), parent)
    scene.update()
    assert_point(scene.world_position(child), 10, 5, 0)


def test_transforms_compose_through_three_levels() raises:
    var scene = Scene()
    var a = scene.add(node_at(10, 0, 0))
    var b = scene.attach(node_at(0, 5, 0), a)
    var c = scene.attach(node_at(0, 0, 2), b)
    scene.update()
    assert_point(scene.world_position(c), 10, 5, 2)


def test_rotating_a_parent_carries_its_whole_subtree() raises:
    var scene = Scene()
    var root = node_at(0, 0, 0)
    root.set_euler(Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    var a = scene.add(root^)
    var b = scene.attach(node_at(0, 0, 2), a)
    var c = scene.attach(node_at(0, 0, 2), b)
    scene.update()
    # A yaw of 90 degrees turns +z into +x, twice over.
    assert_point(scene.world_position(c), 4, 0, 0)


def test_scaling_a_parent_scales_its_children_offsets() raises:
    var scene = Scene()
    var root = node_at(0, 0, 0)
    root.set_scale(3, 3, 3)
    var a = scene.add(root^)
    var b = scene.attach(node_at(0, 2, 0), a)
    scene.update()
    assert_point(scene.world_position(b), 0, 6, 0)


def test_siblings_do_not_affect_each_other() raises:
    var scene = Scene()
    var parent = scene.add(node_at(10, 0, 0))
    var first = scene.attach(node_at(0, 1, 0), parent)
    var second = scene.attach(node_at(0, -1, 0), parent)
    scene.update()
    assert_point(scene.world_position(first), 10, 1, 0)
    assert_point(scene.world_position(second), 10, -1, 0)


def test_updating_twice_gives_the_same_answer() raises:
    # The pass must not accumulate into the world matrices it computed last
    # time, which is an easy mistake when the array is reused.
    var scene = Scene()
    var a = scene.add(node_at(10, 0, 0))
    var b = scene.attach(node_at(0, 5, 0), a)
    scene.update()
    scene.update()
    assert_point(scene.world_position(b), 10, 5, 0)


def test_editing_a_node_and_updating_moves_its_children() raises:
    var scene = Scene()
    var a = scene.add(node_at(0, 0, 0))
    var b = scene.attach(node_at(0, 5, 0), a)
    scene.update()
    var moved = scene.get(a)
    moved.set_position(100, 0, 0)
    scene.set(a, moved^)
    scene.update()
    assert_point(scene.world_position(b), 100, 5, 0)


def test_get_returns_a_copy_not_a_handle() raises:
    var scene = Scene()
    var a = scene.add(node_at(1, 2, 3))
    var fetched = scene.get(a)
    fetched.set_position(9, 9, 9)
    scene.update()
    # The scene is unchanged until the edit is put back.
    assert_point(scene.world_position(a), 1, 2, 3)


def test_attaching_to_a_node_that_does_not_exist_is_rejected() raises:
    var scene = Scene()
    with assert_raises():
        _ = scene.attach(Object3D(), 0)


def test_attaching_to_a_negative_index_is_rejected() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    with assert_raises():
        _ = scene.attach(Object3D(), -5)


def test_a_parent_must_come_before_its_child() raises:
    # This ordering is what makes one forward pass correct, so breaking it
    # has to be refused rather than silently producing a stale matrix.
    var scene = Scene()
    var a = scene.add(Object3D())
    var b = scene.add(Object3D())
    var cyclic = scene.get(a)
    cyclic.parent = b
    with assert_raises():
        scene.set(a, cyclic^)


def test_replacing_a_node_with_a_negative_parent_is_rejected() raises:
    # NO_PARENT is -1 and legal; any other negative is not. `add` refused
    # these from the start, but `set` only checked the ordering half of the
    # rule, so -2 got through and reached the world array during `update`.
    var scene = Scene()
    var a = scene.add(Object3D())
    var _b = scene.attach(Object3D(), a)
    var broken = scene.get(a)
    broken.parent = -2
    with assert_raises():
        scene.set(a, broken^)


def test_replacing_a_root_with_no_parent_is_allowed() raises:
    # The other side of that check: NO_PARENT must stay acceptable at any
    # index, including one a stricter test would reject.
    var scene = Scene()
    var a = scene.add(node_at(1, 0, 0))
    var b = scene.attach(node_at(0, 1, 0), a)
    var freed = scene.get(b)
    freed.parent = NO_PARENT
    scene.set(b, freed^)
    scene.update()
    assert_point(scene.world_position(b), 0, 1, 0)


def test_reading_a_node_out_of_range_is_rejected() raises:
    var scene = Scene()
    with assert_raises():
        _ = scene.get(0)
    with assert_raises():
        _ = scene.world_matrix(0)
    with assert_raises():
        _ = scene.get(-1)


def test_replacing_a_node_out_of_range_is_rejected() raises:
    var scene = Scene()
    with assert_raises():
        scene.set(0, Object3D())
    with assert_raises():
        scene.set(-1, Object3D())


def test_updating_an_empty_scene_does_nothing() raises:
    var scene = Scene()
    scene.update()
    assert_equal(scene.count(), 0)


def test_a_child_can_be_replaced_keeping_its_parent() raises:
    # The valid half of the ordering rule: a parent earlier in the array.
    var scene = Scene()
    var parent = scene.add(node_at(10, 0, 0))
    var child = scene.attach(node_at(0, 5, 0), parent)
    var replacement = node_at(0, 9, 0)
    replacement.parent = parent
    scene.set(child, replacement^)
    scene.update()
    assert_point(scene.world_position(child), 10, 9, 0)


def test_a_negative_world_matrix_index_is_rejected() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    with assert_raises():
        _ = scene.world_matrix(-1)


# --- staleness and invariants -----------------------------------------------


def test_a_new_scene_is_not_stale() raises:
    # Nothing to recompute, so nothing is out of date.
    assert_false(Scene().is_stale())


def test_adding_a_node_makes_the_scene_stale() raises:
    var scene = Scene()
    _ = scene.add(node_at(1, 2, 3))
    assert_true(scene.is_stale())
    scene.update()
    assert_false(scene.is_stale())


def test_replacing_a_node_makes_the_scene_stale() raises:
    var scene = Scene()
    var a = scene.add(node_at(1, 2, 3))
    scene.update()
    assert_false(scene.is_stale())
    var moved = scene.get(a)
    moved.set_position(9, 9, 9)
    scene.set(a, moved^)
    assert_true(scene.is_stale())


def test_reading_a_world_matrix_while_stale_is_rejected() raises:
    # The whole point of tracking it. Serving the matrix from before the edit
    # would render a plausible wrong image and report nothing at all.
    var scene = Scene()
    var a = scene.add(node_at(1, 2, 3))
    with assert_raises():
        _ = scene.world_matrix(a)
    with assert_raises():
        _ = scene.world_position(a)
    scene.update()
    assert_point(scene.world_position(a), 1, 2, 3)


def test_an_out_of_range_index_is_rejected_before_staleness() raises:
    # A bad index is the caller's mistake either way; it should not be
    # reported as a stale scene.
    var scene = Scene()
    _ = scene.add(Object3D())
    with assert_raises():
        _ = scene.world_matrix(7)


def test_an_empty_scene_validates() raises:
    # Vacuously well formed: no nodes, no parents, both arrays empty.
    Scene().validate()


def test_a_well_formed_scene_validates() raises:
    var scene = Scene()
    var a = scene.add(node_at(1, 0, 0))
    var b = scene.attach(node_at(0, 1, 0), a)
    _ = scene.attach(node_at(0, 0, 1), b)
    _ = scene.add(Object3D())
    scene.update()
    scene.validate()


def test_validate_catches_a_parent_that_is_not_earlier() raises:
    # Reaching past the underscore is exactly what `validate` is for: Mojo
    # does not enforce private fields, so the convention can be broken and
    # the single-pass update would then read a matrix that is not ready.
    var scene = Scene()
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene._nodes[0].parent = 1
    with assert_raises():
        scene.validate()


def test_validate_catches_a_negative_parent() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    scene._nodes[0].parent = -4
    with assert_raises():
        scene.validate()


def test_validate_catches_arrays_that_have_drifted_apart() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    scene._world.append(Matrix4())
    with assert_raises():
        scene.validate()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
