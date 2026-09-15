# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.object3d` and `core.scene`."""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.object3d import NO_PARENT, Object3D
from math.euler import XYZ, XZY, YXZ, YZX, ZXY, ZYX, Euler
from math.projection import look_at
from math.quaternion import Quaternion
from core.scene import Scene
from materials.material import MaterialId
from math.vector3 import Vector3
from math.matrix4 import Matrix4
from objects.mesh import Mesh
from std.math import cos, sin
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


def test_euler_order_is_xyz_by_default_as_in_three_js() raises:
    var node = Object3D()
    node.set_euler(Angle(90.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    # Rx * Ry: a point meets the y turn first, which leaves +y alone, and
    # then the x turn, which carries +y onto +z. three.js gives the same.
    assert_point(node.local_matrix().transform_point(Vector3(0, 1, 0)), 0, 0, 1)


def test_zyx_order_turns_about_world_axes_x_first() raises:
    var node = Object3D()
    node.set_euler(
        Angle(90.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE), ZYX
    )
    # Rz * Ry * Rx: x turns +y onto +z, then y turns +z onto +x.
    assert_point(node.local_matrix().transform_point(Vector3(0, 1, 0)), 1, 0, 0)


def test_xyz_matches_three_js_make_rotation_from_euler() raises:
    # The formula from three.js `Matrix4.makeRotationFromEuler` for 'XYZ',
    # element by element, at angles where nothing cancels.
    var x = Angle(31.0, DEGREE)
    var y = Angle(-47.0, DEGREE)
    var z = Angle(113.0, DEGREE)
    var a = cos(x.value)
    var b = sin(x.value)
    var c = cos(y.value)
    var d = sin(y.value)
    var e = cos(z.value)
    var f = sin(z.value)
    var node = Object3D()
    node.set_euler(x, y, z)
    var got = node.local_matrix()
    var expected = Matrix4()
    expected.set(
        c * e,
        -c * f,
        d,
        0,
        a * f + b * e * d,
        a * e - b * f * d,
        -b * c,
        0,
        b * f - a * e * d,
        b * e + a * f * d,
        a * c,
        0,
        0,
        0,
        0,
        1,
    )
    for index in range(16):
        assert_almost_equal(
            got.elements[index], expected.elements[index], atol=TOLERANCE
        )


def test_every_euler_order_is_a_different_orientation() raises:
    # Six orders, six matrices. Generic angles so that no two coincide.
    var orders = [XYZ, YXZ, ZXY, ZYX, YZX, XZY]
    var matrices = List[Matrix4]()
    for order in orders:
        var node = Object3D()
        node.set_euler(
            Angle(31.0, DEGREE),
            Angle(-47.0, DEGREE),
            Angle(113.0, DEGREE),
            order,
        )
        matrices.append(node.local_matrix())
    for left in range(len(matrices)):
        for right in range(left + 1, len(matrices)):
            var differ = False
            for index in range(16):
                if (
                    abs(
                        matrices[left].elements[index]
                        - matrices[right].elements[index]
                    )
                    > 1e-4
                ):
                    differ = True
            assert_true(differ, "two orders gave the same matrix")


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
    assert_equal(scene.add(Object3D()), NodeId(0))
    assert_equal(scene.add(Object3D()), NodeId(1))
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
        _ = scene.attach(Object3D(), NodeId(0))


def test_attaching_to_a_negative_index_is_rejected() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    with assert_raises():
        _ = scene.attach(Object3D(), NodeId(-5))


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
    broken.parent = NodeId(-2)
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
        _ = scene.get(NodeId(0))
    with assert_raises():
        _ = scene.world_matrix(NodeId(0))
    with assert_raises():
        _ = scene.get(NodeId(-1))


def test_replacing_a_node_out_of_range_is_rejected() raises:
    var scene = Scene()
    with assert_raises():
        scene.set(NodeId(0), Object3D())
    with assert_raises():
        scene.set(NodeId(-1), Object3D())


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
        _ = scene.world_matrix(NodeId(-1))


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
        _ = scene.world_matrix(NodeId(7))


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
    scene._nodes[0].parent = NodeId(1)
    with assert_raises():
        scene.validate()


def test_validate_catches_a_negative_parent() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    scene._nodes[0].parent = NodeId(-4)
    with assert_raises():
        scene.validate()


def test_validate_catches_arrays_that_have_drifted_apart() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    scene._world.append(Matrix4())
    with assert_raises():
        scene.validate()


# --- rotations ---------------------------------------------------------------


def test_rotating_in_steps_adds_up() raises:
    var stepped = Object3D()
    for _ in range(3):
        stepped.rotate_y(Angle(30.0, DEGREE))
    var whole = Object3D()
    whole.set_euler(Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    assert_point(
        stepped.local_matrix().transform_point(Vector3(0, 0, 1)), 1, 0, 0
    )
    var a = stepped.local_matrix()
    var b = whole.local_matrix()
    for index in range(16):
        assert_almost_equal(
            a.elements[index], b.elements[index], atol=TOLERANCE
        )


def test_rotating_on_a_local_axis_follows_an_earlier_turn() raises:
    # Tilt forward, then turn about the node's *own* up. The own up is the
    # tilted one, so the turn is not about world y.
    var node = Object3D()
    node.rotate_x(Angle(90.0, DEGREE))
    node.rotate_y(Angle(90.0, DEGREE))
    # Rx(90) * Ry(90): +x goes to -z under Ry, then Rx sends -z to +y.
    assert_point(node.local_matrix().transform_point(Vector3(1, 0, 0)), 0, 1, 0)


def test_rotating_on_a_world_axis_ignores_earlier_turns() raises:
    var node = Object3D()
    node.rotate_x(Angle(90.0, DEGREE))
    node.rotate_on_world_axis(Vector3(0, 1, 0), Angle(90.0, DEGREE))
    # Ry(90) * Rx(90): +x is left alone by Rx, then Ry sends it to -z.
    assert_point(
        node.local_matrix().transform_point(Vector3(1, 0, 0)), 0, 0, -1
    )
    # And the tilted +y, which Rx made +z, is left where Ry cannot see it.
    var pre = Object3D()
    pre.rotate_x(Angle(90.0, DEGREE))
    pre.rotate_on_world_axis(Vector3(0, 1, 0), Angle(90.0, DEGREE))
    assert_point(pre.local_matrix().transform_point(Vector3(0, 1, 0)), 1, 0, 0)


def test_each_axis_turn_is_about_that_axis() raises:
    var node = Object3D()
    node.rotate_z(Angle(90.0, DEGREE))
    assert_point(node.local_matrix().transform_point(Vector3(1, 0, 0)), 0, 1, 0)
    var other = Object3D()
    other.rotate_x(Angle(90.0, DEGREE))
    assert_point(
        other.local_matrix().transform_point(Vector3(0, 1, 0)), 0, 0, 1
    )


def test_set_rotation_takes_an_euler() raises:
    var node = Object3D()
    node.set_rotation(
        Euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(90.0, DEGREE), XYZ)
    )
    assert_point(node.local_matrix().transform_point(Vector3(1, 0, 0)), 0, 1, 0)


def test_set_quaternion_is_taken_as_given() raises:
    var node = Object3D()
    node.set_quaternion(
        Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(90.0, DEGREE))
    )
    assert_point(node.local_matrix().transform_point(Vector3(0, 1, 0)), 0, 0, 1)


def test_an_object_looks_at_a_target_with_plus_z() raises:
    var node = node_at(0, 0, 0)
    node.look_at(Vector3(5, 0, 0))
    assert_point(
        node.local_matrix().transform_direction(Vector3(0, 0, 1)), 1, 0, 0
    )
    # Up stays up.
    assert_point(
        node.local_matrix().transform_direction(Vector3(0, 1, 0)), 0, 1, 0
    )


def test_a_camera_looks_at_a_target_with_minus_z() raises:
    # The camera convention, which is also what `projection.look_at` builds:
    # the inverse of this node's transform must be that view matrix.
    var node = node_at(1, 2, 4)
    node.look_at(Vector3(0, 0, 0), camera=True)
    var view = node.local_matrix()
    view.invert()
    var expected = look_at(Vector3(1, 2, 4), Vector3(0, 0, 0), Vector3(0, 1, 0))
    for index in range(16):
        assert_almost_equal(
            view.elements[index], expected.elements[index], atol=Float64(1e-4)
        )


def test_looking_at_the_nodes_own_position_is_rejected() raises:
    var node = node_at(1, 1, 1)
    with assert_raises():
        node.look_at(Vector3(1, 1, 1))


def test_looking_straight_up_is_rejected() raises:
    var node = node_at(0, 0, 0)
    with assert_raises():
        node.look_at(Vector3(0, 5, 0))
    with assert_raises():
        node.look_at(Vector3(0, -5, 0), camera=True)


def test_a_scene_look_at_is_in_world_space() raises:
    # The child sits inside a parent that is turned a quarter turn about y
    # and moved. Facing a world point means undoing that first.
    var scene = Scene()
    var parent = node_at(10, 0, 0)
    parent.set_euler(
        Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE)
    )
    var pivot = scene.add(parent^)
    var child = scene.attach(node_at(0, 0, 0), pivot)
    scene.update()
    scene.look_at(child, Vector3(10, 0, -7))
    scene.update()
    # The child's +z now points at the target in world space.
    var facing = scene.world_matrix(child).transform_direction(Vector3(0, 0, 1))
    assert_point(facing, 0, 0, -1)


def test_a_root_scene_look_at_matches_the_node_form() raises:
    var scene = Scene()
    var id = scene.add(node_at(3, 0, 0))
    scene.update()
    scene.look_at(id, Vector3(0, 0, 0))
    scene.update()
    var facing = scene.world_matrix(id).transform_direction(Vector3(0, 0, 1))
    assert_point(facing, -1, 0, 0)


def test_a_scene_look_at_needs_a_current_scene_and_a_real_node() raises:
    var scene = Scene()
    var id = scene.add(node_at(3, 0, 0))
    with assert_raises():
        scene.look_at(NodeId(4), Vector3(0, 0, 0))
    with assert_raises():
        scene.look_at(NodeId(-1), Vector3(0, 0, 0))
    # Stale: `add` invalidated the world matrices and no update has run.
    scene.update()
    var parent = scene.add(node_at(1, 0, 0))
    var child = scene.attach(node_at(0, 0, 2), parent)
    with assert_raises():
        scene.look_at(child, Vector3(0, 0, 0))
    _ = id


# --- meshes and in-place editing --------------------------------------------


def test_a_mesh_can_be_added_once_its_node_exists() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), NodeId(0)))
    assert_equal(len(scene.meshes), 1)
    assert_equal(scene.meshes[0].node, NodeId(0))
    # A mesh holds no transform, so adding one leaves the world matrices
    # exactly as current as they were, like adding a light.
    assert_false(scene.is_stale())


def test_a_mesh_naming_a_node_that_is_not_there_is_rejected() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    with assert_raises():
        scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), NodeId(3)))
    assert_equal(len(scene.meshes), 0)


def test_a_node_can_be_edited_in_place() raises:
    var scene = Scene()
    var id = scene.add(Object3D())
    scene.update()
    scene.node(id).set_position(1, 2, 3)
    # The scene cannot see what was done through the reference, so it
    # assumes the worst and asks for an update.
    assert_true(scene.is_stale())
    scene.update()
    assert_point(scene.world_position(id), 1, 2, 3)


def test_editing_a_node_carries_its_children() raises:
    var scene = Scene()
    var parent = scene.add(Object3D())
    var child = scene.attach(node_at(0, 0, 2), parent)
    scene.update()
    scene.node(parent).set_euler(
        Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.update()
    assert_point(scene.world_position(child), 2, 0, 0)


def test_editing_a_node_out_of_range_is_rejected() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    with assert_raises():
        scene.node(NodeId(1)).set_position(1, 1, 1)
    with assert_raises():
        scene.node(NodeId(-1)).set_position(1, 1, 1)


def test_update_refuses_a_parent_link_broken_through_a_reference() raises:
    # `set` checks parent links; a mutable reference bypasses it. `update`
    # validates first rather than indexing with whatever it finds.
    var scene = Scene()
    var first = scene.add(Object3D())
    var second = scene.add(Object3D())
    scene.node(first).parent = second
    with assert_raises():
        scene.update()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
