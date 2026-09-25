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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
