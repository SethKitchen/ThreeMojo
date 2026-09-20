# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a connected stature-scaled leg."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg, assemble_leg
from extensions.humanoid.skeleton.leg.contents import (
    ALL,
    BONES,
    BOTH,
    HAIR,
    INTEGUMENT,
    LYMPH,
    MUSCLES,
    NERVES,
    SKIN,
    VESSELS,
    LegContents,
)
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    tendon_phong,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length

comptime TOLERANCE = Float64(1e-4)


def test_right_leg_puts_the_joint_at_the_origin() raises:
    var pose = assemble_leg(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var distal = pose.femur_origin.y - Float32(0.5) * pose.femur.length.value
    assert_almost_equal(
        distal, pose.knee.femoral_thickness.value, atol=TOLERANCE
    )
    var eminence = pose.tibia_origin.y + pose.tibia.eminence.y
    assert_almost_equal(
        eminence, -pose.knee.tibial_thickness.value, atol=TOLERANCE
    )
    assert_true(pose.side == RIGHT)


def test_fibula_head_sits_lateral_of_the_tibia() raises:
    var pose = assemble_leg(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var head = pose.fibula_origin + pose.fibula.head_center
    var lat = pose.tibia_origin + pose.tibia.lateral_condyle
    assert_true(head.x > lat.x)
    assert_true(head.y < lat.y + Float32(0.01))
    var left = assemble_leg(HumanoidSpec(Length(6.0, FOOT), MALE), LEFT)
    var left_head = left.fibula_origin + left.fibula.head_center
    var left_lat = left.tibia_origin + left.tibia.lateral_condyle
    assert_true(left_head.x < left_lat.x)


def test_patella_sits_anterior_of_the_trochlea() raises:
    var pose = assemble_leg(HumanoidSpec(Length(6.0, FOOT), FEMALE), RIGHT)
    assert_true(pose.patella_origin.z > pose.knee.trochlear_cartilage.z)
    assert_true(pose.knee.patellar_cartilage.z < pose.patella_origin.z)
    assert_true(
        pose.patella_origin.z - pose.knee.trochlear_cartilage.z
        > Float32(0.25) * pose.patella.thickness.value
    )


def test_hip_and_ankle_centers_follow_the_bones() raises:
    var pose = assemble_leg(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var hip = pose.hip_center()
    var ankle = pose.ankle_center()
    assert_almost_equal(
        hip.x,
        (pose.femur_origin + pose.femur.head_center).x,
        atol=TOLERANCE,
    )
    assert_true(hip.y > 0)
    assert_true(ankle.y < 0)
    assert_true(hip.y - ankle.y > Float32(0.7))


def test_left_and_right_hips_mirror() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var right = assemble_leg(person, RIGHT)
    var left = assemble_leg(person, LEFT)
    assert_almost_equal(
        left.hip_center().x, -right.hip_center().x, atol=Float64(1e-3)
    )
    assert_almost_equal(
        left.hip_center().y, right.hip_center().y, atol=Float64(1e-3)
    )


def test_add_leg_places_nine_meshes() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var node = add_leg(
        scene,
        assets,
        root,
        person,
        assets.materials.add(bone_phong()),
        assets.materials.add(cartilage_phong()),
        assets.materials.add(meniscus_phong()),
        assets.materials.add(ligament_phong()),
        assets.materials.add(muscle_phong()),
        assets.materials.add(tendon_phong()),
        RIGHT,
        BONES,
        8,
    )
    assert_equal(len(scene.meshes), 9)
    assert_true(node.value >= 0)
    scene.update()
    var origin = scene.world_matrix(node).transform_point(Vector3(0, 0, 0))
    assert_almost_equal(origin.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(origin.y, Float32(0), atol=TOLERANCE)


def test_leg_contents_toggles_named_layers() raises:
    assert_true(BONES.is_valid())
    assert_true(MUSCLES.is_valid())
    assert_true(VESSELS.is_valid())
    assert_true(LYMPH.is_valid())
    assert_true(NERVES.is_valid())
    assert_true(SKIN.is_valid())
    assert_true(HAIR.is_valid())
    assert_true(BOTH.is_valid())
    assert_true(INTEGUMENT.is_valid())
    assert_true(ALL.is_valid())
    assert_false(LegContents(0).is_valid())
    assert_false(LegContents(-1).is_valid())
    assert_false(LegContents(128).is_valid())
    assert_true(BONES.includes_bones())
    assert_false(BONES.includes_muscles())
    assert_false(BONES.includes_vessels())
    assert_false(BONES.includes_lymph())
    assert_false(BONES.includes_nerves())
    assert_false(BONES.includes_skin())
    assert_false(BONES.includes_hair())
    assert_false(MUSCLES.includes_bones())
    assert_true(MUSCLES.includes_muscles())
    assert_true(BOTH.includes_bones())
    assert_true(BOTH.includes_muscles())
    assert_true(VESSELS.includes_vessels())
    assert_true(LYMPH.includes_lymph())
    assert_true(NERVES.includes_nerves())
    assert_true(SKIN.includes_skin())
    assert_true(HAIR.includes_hair())
    assert_true(INTEGUMENT.includes_skin())
    assert_true(INTEGUMENT.includes_hair())
    assert_false(INTEGUMENT.includes_bones())
    assert_true(ALL.includes_bones())
    assert_true(ALL.includes_hair())
    var combined = BONES.plus(VESSELS)
    assert_true(combined.includes_bones())
    assert_true(combined.includes_vessels())
    assert_false(combined.includes_muscles())
    var layers = VESSELS.plus(LYMPH)
    layers = layers.plus(NERVES)
    layers = layers.plus(INTEGUMENT)
    assert_true(layers.includes_vessels())
    assert_true(layers.includes_skin())
    var bad = LegContents(0)
    with assert_raises():
        _ = bad.includes_bones()
    with assert_raises():
        _ = bad.includes_muscles()
    with assert_raises():
        _ = bad.includes_vessels()
    with assert_raises():
        _ = bad.includes_lymph()
    with assert_raises():
        _ = bad.includes_nerves()
    with assert_raises():
        _ = bad.includes_skin()
    with assert_raises():
        _ = bad.includes_hair()
    with assert_raises():
        _ = bad.plus(BONES)
    with assert_raises():
        _ = BONES.plus(LegContents(128))


def test_add_leg_refuses_invalid_contents() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = add_leg(
            scene,
            assets,
            root,
            person,
            assets.materials.add(bone_phong()),
            assets.materials.add(cartilage_phong()),
            assets.materials.add(meniscus_phong()),
            assets.materials.add(ligament_phong()),
            assets.materials.add(muscle_phong()),
            assets.materials.add(tendon_phong()),
            RIGHT,
            LegContents(0),
            8,
        )


def test_assemble_leg_carries_muscle_landmarks() raises:
    var pose = assemble_leg(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    assert_true(pose.muscles.hip.y > 0)
    assert_true(pose.muscles.heel.y < 0)


def test_add_leg_creates_default_paints_for_new_layers() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var layers = VESSELS.plus(LYMPH)
    layers = layers.plus(NERVES)
    _ = add_leg(
        scene,
        assets,
        root,
        person,
        assets.materials.add(bone_phong()),
        assets.materials.add(cartilage_phong()),
        assets.materials.add(meniscus_phong()),
        assets.materials.add(ligament_phong()),
        assets.materials.add(muscle_phong()),
        assets.materials.add(tendon_phong()),
        RIGHT,
        layers,
        8,
    )
    assert_equal(len(scene.meshes), 20)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
