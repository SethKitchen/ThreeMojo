# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A speaking face's still copy, drawn in its place at a distance."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.rig.game import (
    GameHumanoid,
    add_game_humanoid,
    game_build_settings,
)
from extensions.humanoid.rig.game_face import facial_correspondence
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length

comptime STILL = 300
"""The still face's triangles in these tests."""


def _distant(scene: Scene, assets: Assets, person: GameHumanoid) raises -> Int:
    """Count the triangles a distant view draws but the eyes: every shown
    mesh, the skins, the hair and the still face."""
    var total = 0
    for i in range(len(scene.meshes)):
        var node = scene.meshes[i].node
        var counted = (
            node == person.far_face.value() or node == person.hair.value()
        )
        if counted and scene.get(node).visible:
            total += assets.geometries.get(
                scene.meshes[i].geometry
            ).triangle_count()
    for i in range(len(scene.skinned_meshes)):
        total += assets.geometries.get(
            scene.skinned_meshes[i].geometry
        ).triangle_count()
    return total


def test_a_still_face_stands_in_at_a_distance_within_the_budget() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var budget = 2000
    var person = add_game_humanoid(
        scene,
        assets,
        root,
        HumanoidSpec(Length(6, FOOT), MALE),
        budget,
        detail=8,
        hand_detail=8,
        hair_detail=8,
        facial_animation=True,
        face_stand_in=STILL,
    )
    assert_true(Bool(person.far_face))
    var still = person.far_face.value()
    # The preserved face shows first.
    assert_false(scene.get(still).visible)
    var face = person.face.value().copy()
    var mark = facial_correspondence(
        assets.geometries.get(scene.meshes[face.meshes[0]].geometry)
    )
    person.show_face(scene, False)
    assert_true(scene.get(still).visible)
    for k in face.meshes:
        assert_false(scene.get(scene.meshes[k].node).visible)
    # The budget counts what a distant view draws but the eyes: the still
    # face, not the preserved one, which is far larger.
    assert_true(_distant(scene, assets, person) <= budget)
    person.show_face(scene, True)
    assert_false(scene.get(still).visible)
    for k in face.meshes:
        assert_true(scene.get(scene.meshes[k].node).visible)
    # The preserved face is as it was.
    face.validate(scene, assets)
    assert_equal(
        facial_correspondence(
            assets.geometries.get(scene.meshes[face.meshes[0]].geometry)
        ),
        mark,
    )
    var settings = game_build_settings(
        budget, facial_animation=True, face_stand_in=STILL
    )
    assert_equal(settings.string("face_stand_in"), String(STILL))


def test_a_person_without_a_still_face_keeps_its_face_shown() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = add_game_humanoid(
        scene,
        assets,
        root,
        HumanoidSpec(Length(6, FOOT), MALE),
        800,
        detail=8,
        hand_detail=8,
        hair_detail=8,
    )
    assert_false(Bool(person.far_face))
    person.show_face(scene, False)
    for i in range(len(scene.meshes)):
        assert_true(scene.get(scene.meshes[i].node).visible)
    assert_false(game_build_settings(800).has("face_stand_in"))


def test_a_still_face_needs_a_speaking_face_and_a_budget() raises:
    with assert_raises(contains="nonnegative"):
        _ = game_build_settings(1000, facial_animation=True, face_stand_in=-1)
    with assert_raises(contains="facial animation and a budget"):
        _ = game_build_settings(1000, face_stand_in=100)
    with assert_raises(contains="facial animation and a budget"):
        _ = game_build_settings(0, facial_animation=True, face_stand_in=100)
    with assert_raises(contains="32 triangles at least"):
        _ = game_build_settings(1000, facial_animation=True, face_stand_in=8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
