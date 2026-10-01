# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Morph sequence frames follow target indices, not dictionary order."""

from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from animation.keyframe_track import MeshIndex
from materials.material import MaterialId
from objects.mesh import Mesh
from objects.morph_blend_mesh import MorphBlendMesh
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def make_scene(reverse: Bool = False) raises -> Scene:
    var scene = Scene()
    var mesh = Mesh(GeometryId(0), MaterialId(0), scene.add(Object3D()))
    if reverse:
        mesh.morph_target_dictionary["run2"] = 4
        mesh.morph_target_dictionary["idle3"] = 2
        mesh.morph_target_dictionary["run1"] = 3
        mesh.morph_target_dictionary["idle2"] = 1
        mesh.morph_target_dictionary["idle1"] = 0
    else:
        mesh.morph_target_dictionary["idle1"] = 0
        mesh.morph_target_dictionary["run1"] = 3
        mesh.morph_target_dictionary["idle2"] = 1
        mesh.morph_target_dictionary["run2"] = 4
        mesh.morph_target_dictionary["idle3"] = 2
    mesh.set_morph_influence(4, 0)
    scene.add_mesh(mesh^)
    return scene^


def test_animation_ranges_follow_the_dictionary_values() raises:
    var scene = make_scene()
    var blend = MorphBlendMesh(MeshIndex(0), scene)
    blend.auto_create_animations(scene, 6)
    assert_equal(blend.first_animation, "idle")
    assert_equal(blend.animations[1].start, 0)
    assert_equal(blend.animations[1].end, 2)
    assert_equal(blend.animations[2].start, 3)
    assert_equal(blend.animations[2].end, 4)


def test_reordering_changes_discovery_order_but_not_frame_indices() raises:
    var scene = make_scene(True)
    var blend = MorphBlendMesh(MeshIndex(0), scene)
    blend.auto_create_animations(scene, 6)
    assert_equal(blend.first_animation, "run")
    assert_equal(blend.animations[1].name, "run")
    assert_equal(blend.animations[1].start, 3)
    assert_equal(blend.animations[1].end, 4)
    assert_equal(blend.animations[2].start, 0)
    assert_equal(blend.animations[2].end, 2)


def test_playback_changes_the_named_target_run() raises:
    var scene = make_scene()
    var blend = MorphBlendMesh(MeshIndex(0), scene)
    blend.auto_create_animations(scene, 6)
    assert_true(blend.play_animation("run"))
    blend.update(scene, 0)
    blend.update(scene, 1.0 / 12.0)
    assert_equal(scene.meshes[0].morph_influence(3), 1)
    for frame in [0, 1, 2, 4]:
        assert_equal(scene.meshes[0].morph_influence(frame), 0)


def test_invalid_target_indices_leave_animations_unchanged() raises:
    for index in [-1, 5, Int.MAX]:
        var scene = make_scene()
        var blend = MorphBlendMesh(MeshIndex(0), scene)
        scene.meshes[0].morph_target_dictionary["broken1"] = index
        with assert_raises(contains="target index"):
            blend.auto_create_animations(scene, 6)
        assert_equal(len(blend.animations), 1)
        assert_equal(blend.first_animation, "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
