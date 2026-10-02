# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scene optimization preserves nodes with semantic state and references."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import Object3D, NO_PARENT
from core.scene import Scene
from core.scene_optimizer import SceneOptimizer
from lights.light import directional_light
from materials.material import BASIC, Material, MaterialId
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.clipping_group import ClippingGroup
from objects.gyroscope import gyroscope
from objects.lod import Lod
from objects.mesh import Mesh
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from render.framebuffer import Color
from std.testing import TestSuite, assert_equal, assert_true
from units.si import Length, METER


def geometry() raises -> BufferGeometry:
    """Return one triangle."""
    var shape = BufferGeometry()
    shape.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    return shape^


def test_clipped_meshes_are_not_batched_out_of_their_scope() raises:
    var scene = Scene()
    var assets = Assets()
    var id = assets.geometries.add(geometry())
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var clipped = scene.add(Object3D())
    var plain = scene.add(Object3D())
    scene.add_mesh(Mesh(id, material, clipped))
    scene.add_mesh(Mesh(id, material, plain))
    scene.add_clipping_group(
        ClippingGroup(clipped, [Plane(Vector3(1, 0, 0), 0)])
    )
    _ = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_true(scene.in_scene(clipped))
    assert_true(scene.in_scene(plain))
    assert_equal(len(scene.batched_meshes), 0)


def test_empty_clipping_groups_are_not_pruned() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_clipping_group(ClippingGroup(node, [Plane(Vector3(1, 0, 0), 0)]))
    SceneOptimizer().remove_empty_nodes(scene, NO_PARENT)
    assert_true(scene.in_scene(node))


def test_a_light_target_stays_in_the_scene() raises:
    var scene = Scene()
    var lamp = scene.add(Object3D())
    var target = scene.add(Object3D())
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp, target=target)
    )
    SceneOptimizer().remove_empty_nodes(scene, NO_PARENT)
    assert_true(scene.in_scene(lamp))
    assert_true(scene.in_scene(target))


def test_empty_lod_levels_are_not_pruned() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var first = scene.add(Object3D())
    var second = scene.add(Object3D())
    var lod = Lod(node)
    lod.add_level(first)
    lod.add_level(second, Length(5, METER))
    scene.add_lod(lod^)
    SceneOptimizer().remove_empty_nodes(scene, NO_PARENT)
    assert_true(scene.in_scene(first))
    assert_true(scene.in_scene(second))


def test_skeleton_bones_are_not_pruned_as_empty_nodes() raises:
    var scene = Scene()
    var mesh = scene.add(Object3D())
    var bone = scene.add(Object3D())
    scene.add_skinned_mesh(
        SkinnedMesh(
            GeometryId(0),
            MaterialId(0),
            mesh,
            Skeleton([Bone(bone, Matrix4())]),
        )
    )
    SceneOptimizer().remove_empty_nodes(scene, NO_PARENT)
    assert_true(scene.in_scene(bone))


def test_gyroscope_meshes_keep_their_transform_behavior() raises:
    var scene = Scene()
    var assets = Assets()
    var id = assets.geometries.add(geometry())
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var parent = scene.add(Object3D())
    var gyro = scene.attach(gyroscope(), parent)
    var plain = scene.attach(Object3D(), parent)
    scene.add_mesh(Mesh(id, material, gyro))
    scene.add_mesh(Mesh(id, material, plain))
    _ = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_true(scene.in_scene(gyro))
    assert_true(scene.in_scene(plain))
    assert_equal(len(scene.batched_meshes), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
