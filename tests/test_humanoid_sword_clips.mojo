# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sword clips: each plays on a rig's bones for its move's time, the sword
arm is the arm on minus x, the tempest turns the body round, and the fall
ends on the ground."""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import ONCE, AnimationAction, AnimationMixer
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.rig.clips import Pose
from extensions.humanoid.rig.joints import (
    HIPS,
    JOINT_COUNT,
    LEFT_HAND,
    LEFT_TOES,
    LEFT_THIGH,
    LEFT_UPPER_ARM,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    HumanoidRig,
    humanoid_rig,
    joint_parent,
    named_joints,
)
from extensions.humanoid.rig.sword_clips import (
    burst_clip,
    cast_clip,
    dodge_clip,
    fang_clip,
    fall_clip,
    flinch_clip,
    guard_clip,
    heavy_clip,
    light_one_clip,
    light_three_clip,
    light_two_clip,
    mirrored,
    mystic_clip,
    mystic_twist,
    plunge_clip,
    ready_clip,
    rising_edge_clip,
    stagger_clip,
    tempest_clip,
    tempest_twist,
    twin_joint,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.torso.body import body_skin_mesh
from extensions.humanoid.spec import HumanoidSpec
from math.quaternion import Quaternion
from math.vector3 import Vector3
from renderers.renderer import available_workers
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import FOOT, SECOND, Duration, Length


def _spec() -> HumanoidSpec:
    """Return the six-foot male template."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def _rig() raises -> HumanoidRig:
    """Return the template's rig, placed on a coarse skin."""
    return humanoid_rig(
        _spec(), body_skin_mesh(_spec(), 12, available_workers(), 0.014)
    )


def _bones(mut scene: Scene, rig: HumanoidRig) raises -> List[NodeId]:
    """Return one scene node per joint, hung as the rig hangs them."""
    var bones = List[NodeId]()
    var root = scene.add(Object3D())
    for joint in named_joints():  # pragma: no branch
        var node = Object3D()
        var at = rig.local(joint)
        node.set_position(at.x, at.y, at.z)
        var hang = root
        if joint != HIPS:
            hang = bones[joint_parent(joint).value]
        bones.append(scene.attach(node^, hang))
    return bones^


def _play(mut scene: Scene, var clip: AnimationClip, seconds: Float32) raises:
    """Pose the bones as a clip that plays once stands after `seconds`."""
    var mixer = AnimationMixer()
    var action = mixer.add(AnimationAction(clip^))
    mixer.action(action).set_loop(ONCE)
    mixer.action(action).clamp_when_finished = True
    mixer.action(action).play()
    mixer.update(scene, Duration(seconds, SECOND))


def _turn(a: Quaternion, b: Quaternion) -> Float32:
    """Return how far apart two turns are: one less the size of their
    dot product."""
    return 1 - abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z)


def test_each_clip_lasts_as_long_as_its_move() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var names: List[String] = [
        "ready",
        "light_one",
        "light_two",
        "light_three",
        "heavy",
        "rising_edge",
        "tempest",
        "fang",
        "mystic",
        "plunge",
        "burst",
        "cast",
        "dodge",
        "guard",
        "flinch",
        "stagger",
        "fall",
    ]
    var seconds: List[Float32] = [
        2.0,
        0.5,
        0.5,
        0.77,
        1.09,
        0.81,
        1.06,
        0.65,
        2.1,
        0.75,
        1.44,
        0.8,
        0.48,
        1.0,
        0.4,
        1.6,
        2.0,
    ]
    var clips = List[AnimationClip]()
    clips.append(ready_clip(bones, rig))
    clips.append(light_one_clip(bones, rig))
    clips.append(light_two_clip(bones, rig))
    clips.append(light_three_clip(bones, rig))
    clips.append(heavy_clip(bones, rig))
    clips.append(rising_edge_clip(bones, rig))
    clips.append(tempest_clip(bones, rig))
    clips.append(fang_clip(bones, rig))
    clips.append(mystic_clip(bones, rig))
    clips.append(plunge_clip(bones, rig))
    clips.append(burst_clip(bones, rig))
    clips.append(cast_clip(bones, rig))
    clips.append(dodge_clip(bones, rig))
    clips.append(guard_clip(bones, rig))
    clips.append(flinch_clip(bones, rig))
    clips.append(stagger_clip(bones, rig))
    clips.append(fall_clip(bones, rig))
    for k in range(len(clips)):
        assert_equal(clips[k].name, names[k])
        assert_equal(len(clips[k].tracks), JOINT_COUNT + 1)
        assert_almost_equal(
            clips[k].duration().to(SECOND), seconds[k], atol=1e-4
        )


def test_a_pose_mirrors_onto_its_twin_joints() raises:
    assert_equal(twin_joint(HIPS.value), HIPS.value)
    assert_equal(twin_joint(RIGHT_UPPER_ARM.value), LEFT_UPPER_ARM.value)
    assert_equal(twin_joint(LEFT_UPPER_ARM.value), RIGHT_UPPER_ARM.value)
    assert_equal(twin_joint(LEFT_HAND.value), LEFT_HAND.value - 3)
    assert_equal(twin_joint(RIGHT_THIGH.value), LEFT_THIGH.value)
    assert_equal(twin_joint(LEFT_THIGH.value), RIGHT_THIGH.value)
    assert_equal(twin_joint(LEFT_TOES.value), LEFT_TOES.value - 4)
    var pose = Pose()
    pose.turn(RIGHT_UPPER_ARM, 10, 20, 30)
    pose.turn(HIPS, 1, 2, 3)
    pose.lift = Vector3(0.1, 0.2, 0.3)
    var turned = mirrored(pose)
    var arm = turned.angles[LEFT_UPPER_ARM.value]
    assert_almost_equal(arm.x, 10, atol=1e-6)
    assert_almost_equal(arm.y, -20, atol=1e-6)
    assert_almost_equal(arm.z, -30, atol=1e-6)
    assert_almost_equal(turned.angles[RIGHT_UPPER_ARM.value].x, 0, atol=1e-6)
    assert_almost_equal(turned.angles[HIPS.value].y, -2, atol=1e-6)
    assert_almost_equal(turned.lift.x, -0.1, atol=1e-6)
    assert_almost_equal(turned.lift.z, 0.3, atol=1e-6)


def test_the_sword_arm_cuts_and_the_tempest_turns_round() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var sword = bones[LEFT_UPPER_ARM.value]
    var hips = bones[HIPS.value]
    _play(scene, ready_clip(bones, rig), 0)
    var ready_sword = scene.node(sword).quaternion
    # The wind-up of the first cut swings the sword arm far.
    _play(scene, light_one_clip(bones, rig), 0.12)
    assert_true(_turn(scene.node(sword).quaternion, ready_sword) > 0.1)
    # Halfway through its spin, the tempest faces the hips about.
    _play(scene, tempest_clip(bones, rig), 0)
    var start = scene.node(hips).quaternion
    _play(scene, tempest_clip(bones, rig), 0.42)
    assert_true(_turn(scene.node(hips).quaternion, start) > 0.5)
    # It ends facing forward again.
    _play(scene, tempest_clip(bones, rig), 1.06)
    assert_true(_turn(scene.node(hips).quaternion, start) < 0.01)


def test_the_tempest_winds_back_and_turns_round() raises:
    assert_almost_equal(tempest_twist(0), 0, atol=1e-5)
    # Wound back as the spin begins, and a whole turn round at its end.
    assert_almost_equal(tempest_twist(0.17), 40, atol=0.5)
    assert_almost_equal(tempest_twist(1), -360, atol=1e-3)


def test_the_mystic_arte_turns_round_twice() raises:
    # Still while the sword rises, then two whole turns, and still again.
    assert_almost_equal(mystic_twist(0), 0, atol=1e-5)
    assert_almost_equal(mystic_twist(0.2), 0, atol=1e-5)
    assert_almost_equal(mystic_twist(1000.0 / 2100), -360, atol=1e-2)
    assert_almost_equal(mystic_twist(0.8), -720, atol=1e-3)
    assert_almost_equal(mystic_twist(1), -720, atol=1e-3)


def test_a_fall_ends_on_the_ground() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var hips = bones[HIPS.value]
    var standing = rig.local(HIPS).y
    _play(scene, fall_clip(bones, rig), 2.0)
    var lying = scene.node(hips).position.y
    assert_true(standing - lying > 0.6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
