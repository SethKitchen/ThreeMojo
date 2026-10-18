# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The original statement API and the node-returning placement helper."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.skeleton.arm.assembly import (
    place_mesh as original_arm_place_mesh,
)
from extensions.humanoid.skeleton.place import place_mesh, place_mesh_node
from materials.material import MaterialId
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_original_five_argument_statement_call() raises:
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    place_mesh(scene, assets, parent, BufferGeometry(), MaterialId(0))
    assert_equal(scene.count(), 2)
    assert_equal(len(scene.meshes), 1)
    assert_equal(assets.geometries.count(), 1)
    var child = scene.meshes[0].node
    assert_equal(scene.get(child).parent, parent)
    assert_true(scene.get(child).position == Vector3(0, 0, 0))


def test_original_arm_module_statement_call() raises:
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    original_arm_place_mesh(
        scene, assets, parent, BufferGeometry(), MaterialId(0)
    )
    assert_equal(scene.count(), 2)
    assert_equal(len(scene.meshes), 1)
    assert_equal(assets.geometries.count(), 1)
    var child = scene.meshes[0].node
    assert_equal(scene.get(child).parent, parent)
    assert_true(scene.get(child).position == Vector3(0, 0, 0))


def test_node_helper_returns_the_child_and_keeps_origin() raises:
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var child = place_mesh_node(
        scene, assets, parent, BufferGeometry(), MaterialId(0), Vector3(1, 2, 3)
    )
    assert_equal(scene.meshes[0].node, child)
    assert_equal(scene.get(child).parent, parent)
    assert_true(scene.get(child).position == Vector3(1, 2, 3))
    var at_origin = place_mesh_node(
        scene, assets, parent, BufferGeometry(), MaterialId(0)
    )
    assert_true(scene.get(at_origin).position == Vector3(0, 0, 0))


def test_invalid_parent_is_refused_before_geometry_storage() raises:
    var scene = Scene()
    var assets = Assets()
    with assert_raises():
        place_mesh(scene, assets, NodeId(4), BufferGeometry(), MaterialId(0))
    assert_equal(scene.count(), 0)
    assert_equal(len(scene.meshes), 0)
    assert_equal(assets.geometries.count(), 0)
    with assert_raises():
        _ = place_mesh_node(
            scene, assets, NodeId(4), BufferGeometry(), MaterialId(0)
        )
    assert_equal(scene.count(), 0)
    assert_equal(assets.geometries.count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
