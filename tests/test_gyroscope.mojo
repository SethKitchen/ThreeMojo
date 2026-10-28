# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.gyroscope` and how `Scene.update` places one.

The expected world matrices come from three.js r180's `Gyroscope`, run in
Node. A root at (1, 2, 3), turned (0.3, 0.5, 0.7) radians about x, y and z
and scaled two times, holds a gyroscope at (0.5, -1, 2) turned 0.4 radians
about y. The gyroscope holds a node at (0, 1, 0) turned 0.2 radians about
x.
"""

from core.assets import Assets
from core.object3d import GYROSCOPE_TYPE, NodeId, Object3D, OBJECT3D_TYPE
from core.scene import Scene
from exporters.object_json import object_to_json
from math.matrix4 import Matrix4
from objects.gyroscope import gyroscope
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import Angle, RADIAN


def _assert_matrix(got: Matrix4, want: List[Float32]) raises:
    """Assert a matrix's sixteen elements, column by column.

    Args:
        got: The matrix.
        want: three.js's `elements`.

    Raises:
        Error: If an element differs.
    """
    for at in range(16):
        assert_almost_equal(got.elements[at], want[at], atol=1e-5)


def _world() raises -> Scene:
    """Return the scene of the module docstring, updated.

    Returns:
        The scene: the root, the gyroscope and the child, in that order.

    Raises:
        Error: Never.
    """
    var scene = Scene()
    var root = Object3D()
    root.set_position(1, 2, 3)
    root.set_euler(Angle(0.3, RADIAN), Angle(0.5, RADIAN), Angle(0.7, RADIAN))
    root.set_scale(2, 2, 2)
    var top = scene.add(root^)
    var spinner = gyroscope()
    spinner.set_position(0.5, -1, 2)
    spinner.set_euler(
        Angle(0.0, RADIAN), Angle(0.4, RADIAN), Angle(0.0, RADIAN)
    )
    var middle = scene.attach(spinner^, top)
    var child = Object3D()
    child.set_position(0, 1, 0)
    child.set_euler(Angle(0.2, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN))
    _ = scene.attach(child^, middle)
    scene.update()
    return scene^


def test_a_gyroscope_keeps_its_own_turn() raises:
    var scene = _world()
    _assert_matrix(
        scene.world_matrix(NodeId(1)),
        [
            1.842122,
            0,
            -0.778837,
            0,
            0,
            2,
            0,
            0,
            0.778837,
            0,
            1.842122,
            0,
            4.719623,
            0.407616,
            5.151446,
            1,
        ],
    )


def test_a_parent_scaled_to_nothing_keeps_the_gyroscope_finite() raises:
    # The first frame of a scale-in animation: the parent has no extent, so
    # there is no turn to read. The gyroscope still lands where its parent
    # carries it, as a plain node does, and so does a gyroscope that is
    # itself scaled to nothing.
    var scene = Scene()
    var car = Object3D()
    car.set_position(10, 0, 0)
    car.set_scale(0, 0, 0)
    var car_id = scene.add(car^)
    var held = gyroscope()
    held.parent = car_id
    held.set_position(0, 0, 1)
    var held_id = scene.add(held^)
    var flat = gyroscope()
    flat.parent = held_id
    flat.set_scale(0, 1, 1)
    var flat_id = scene.add(flat^)
    scene.update()
    var at = scene.world_position(held_id)
    assert_almost_equal(at.x, 10, atol=1e-6)
    assert_almost_equal(at.z, 0, atol=1e-6)
    assert_almost_equal(scene.world_position(flat_id).x, 10, atol=1e-6)
    # Grown back, the gyroscope decomposes as before.
    scene.node(car_id).set_scale(1, 1, 1)
    scene.update()
    assert_almost_equal(scene.world_position(held_id).z, 1, atol=1e-6)


def test_a_gyroscopes_children_ride_it() raises:
    var scene = _world()
    _assert_matrix(
        scene.world_matrix(NodeId(2)),
        [
            1.842122,
            0,
            -0.778837,
            0,
            0.154731,
            1.960133,
            0.365973,
            0,
            0.763312,
            -0.397339,
            1.805402,
            0,
            4.719623,
            2.407616,
            5.151446,
            1,
        ],
    )


def test_a_gyroscope_at_the_top_is_a_plain_node() raises:
    var scene = Scene()
    var spinner = gyroscope()
    spinner.set_position(1, 2, 3)
    spinner.set_euler(
        Angle(0.4, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN)
    )
    var local = spinner.local_matrix()
    var id = scene.add(spinner^)
    scene.update()
    var want = List[Float32]()
    for at in range(16):
        want.append(local.elements[at])
    _assert_matrix(scene.world_matrix(id), want)
    assert_equal(scene.get(id).object_type, GYROSCOPE_TYPE)
    assert_true(GYROSCOPE_TYPE.is_valid())


def test_a_gyroscope_is_written_as_an_object3d() raises:
    var scene = Scene()
    _ = scene.add(gyroscope())
    scene.update()
    var text = object_to_json(scene, Assets())
    assert_true(text.find('"type":"Object3D"') >= 0)
    assert_equal(Object3D().object_type, OBJECT3D_TYPE)


def test_a_gyroscope_inherits_ancestor_visibility() raises:
    var scene = _world()
    var spinner = NodeId(1)
    var child = NodeId(2)
    var before = scene.world_position(spinner)
    assert_true(scene.is_shown(spinner))
    assert_true(scene.is_shown(child))
    scene.node(NodeId(0)).visible = False
    scene.update()
    assert_false(scene.is_shown(spinner))
    assert_false(scene.is_shown(child))
    var after = scene.world_position(spinner)
    assert_equal(after.x, before.x)
    assert_equal(after.y, before.y)
    assert_equal(after.z, before.z)
    scene.node(NodeId(0)).visible = True
    scene.update()
    assert_true(scene.is_shown(spinner))
    assert_true(scene.is_shown(child))
    scene.node(spinner).visible = False
    scene.update()
    assert_false(scene.is_shown(spinner))
    assert_false(scene.is_shown(child))


def test_a_removed_ancestor_hides_a_gyroscope_until_reattached() raises:
    var scene = _world()
    var root = NodeId(0)
    var spinner = NodeId(1)
    var child = NodeId(2)
    scene.remove(root)
    scene.update()
    assert_false(scene.in_scene(spinner))
    assert_false(scene.is_shown(spinner))
    assert_false(scene.is_shown(child))
    scene.add(root)
    scene.update()
    assert_true(scene.is_shown(spinner))
    assert_true(scene.is_shown(child))
    scene.node(root).visible = False
    scene.update()
    assert_false(scene.is_shown(spinner))
    scene.add(spinner)
    scene.update()
    assert_true(scene.is_shown(spinner))
    assert_true(scene.is_shown(child))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
