# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Per-instance morph weights follow picking, sorting, and conversion."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.morph import MorphInfluences
from core.object3d import Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from core.scene_utils import (
    create_meshes_from_instanced_mesh,
    sort_instanced_mesh,
)
from materials.material import BASIC, Material, MaterialId
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from render.framebuffer import Color
from std.testing import TestSuite, assert_equal


def shape() raises -> BufferGeometry:
    """Return a triangle with a target ten meters to its right."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([-0.5, -0.5, 0, 0.5, -0.5, 0, 0, 0.5, 0], 3)
    )
    geometry.add_morph_target(
        BufferAttribute([9.5, -0.5, 0, 10.5, -0.5, 0, 10, 0.5, 0], 3)
    )
    return geometry^


def weights(value: Float32) raises -> MorphInfluences:
    """Return one morph weight."""
    var result = MorphInfluences()
    result.set(0, value)
    return result^


def test_picking_reads_each_instances_morph_weights() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(shape())
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    var mesh = InstancedMesh(geometry, material, node, 2)
    mesh.set_morph_at(0, weights(1))
    scene.add_instanced_mesh(mesh^)
    scene.update()
    for expected in range(2):
        var x = Float32(10) if expected == 0 else Float32(0)
        var ray = Raycaster(Vector3(x, 0, 2), Vector3(0, 0, -1))
        var hits = ray.intersect_instanced_mesh(scene, assets, 0)
        assert_equal(len(hits), 1)
        assert_equal(hits[0].instance, expected)


def test_sorting_keeps_weights_with_instance_matrices() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(shape())
    var scene = Scene()
    var node = scene.add(Object3D())
    var mesh = InstancedMesh(geometry, MaterialId(0), node, 2)
    mesh.set_matrix_at(1, translation(1, 0, 0))
    mesh.set_morph_at(0, weights(0.25))
    mesh.set_morph_at(1, weights(0.75))
    scene.add_instanced_mesh(mesh^)
    sort_instanced_mesh(scene, assets, 0, [1, 0])
    assert_equal(scene.instanced_meshes[0].matrix_at(0).elements[12], 1)
    assert_equal(scene.instanced_meshes[0].morph_at(0)[0], 0.75)
    assert_equal(scene.instanced_meshes[0].morph_at(1)[0], 0.25)


def test_sorting_an_appended_instance_keeps_its_empty_weights() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(shape())
    var scene = Scene()
    var node = scene.add(Object3D())
    var mesh = InstancedMesh(geometry, MaterialId(0), node, 1)
    mesh.set_morph_at(0, weights(0.75))
    mesh.matrices.append(Matrix4())
    scene.add_instanced_mesh(mesh^)
    sort_instanced_mesh(scene, assets, 0, [1, 0])
    assert_equal(len(scene.instanced_meshes[0].morph_at(0)), 0)
    assert_equal(scene.instanced_meshes[0].morph_at(1)[0], 0.75)


def test_sorted_morphs_are_picked_at_the_same_world_positions() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(shape())
    var material = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    var mesh = InstancedMesh(geometry, material, node, 2)
    mesh.set_matrix_at(1, translation(20, 0, 0))
    mesh.set_morph_at(0, weights(1))
    mesh.set_morph_at(1, weights(0.5))
    scene.add_instanced_mesh(mesh^)
    sort_instanced_mesh(scene, assets, 0, [1, 0])
    scene.update()
    var ray = Raycaster(Vector3(10, 0, 2), Vector3(0, 0, -1))
    var hits = ray.intersect_instanced_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].instance, 1)


def test_converted_instances_keep_independent_morph_weights() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var mesh = InstancedMesh(GeometryId(0), MaterialId(0), node, 2)
    mesh.set_morph_at(0, weights(0.25))
    mesh.set_morph_at(1, weights(0.75))
    scene.add_instanced_mesh(mesh^)
    _ = create_meshes_from_instanced_mesh(scene, 0)
    assert_equal(scene.meshes[0].morph_influence(0), 0.25)
    assert_equal(scene.meshes[1].morph_influence(0), 0.75)
    scene.meshes[0].set_morph_influence(0, 1)
    assert_equal(scene.instanced_meshes[0].morph_at(0)[0], 0.25)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
