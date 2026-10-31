# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Giant clips: each plays on a rig's bones for its move's time; a slam
raises the mace overhead, and a stomp lifts a knee high."""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import ONCE, AnimationAction, AnimationMixer
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.rig.giant_clips import (
    giant_call_clip,
    giant_charge_clip,
    giant_cleave_clip,
    giant_roar_clip,
    giant_slam_clip,
    giant_stomp_clip,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    JOINT_COUNT,
    LEFT_THIGH,
    LEFT_UPPER_ARM,
    RIGHT_UPPER_ARM,
    HumanoidRig,
    humanoid_rig,
    joint_parent,
    named_joints,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.torso.body import body_skin_mesh
from extensions.humanoid.spec import HumanoidSpec
from math.quaternion import Quaternion
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
        "giant_cleave",
        "giant_slam",
        "giant_stomp",
        "giant_charge",
        "giant_call",
        "giant_roar",
    ]
    var seconds: List[Float32] = [1.09, 0.75, 0.65, 1.44, 0.8, 1.1]
    var clips = List[AnimationClip]()
    clips.append(giant_cleave_clip(bones, rig))
    clips.append(giant_slam_clip(bones, rig))
    clips.append(giant_stomp_clip(bones, rig))
    clips.append(giant_charge_clip(bones, rig))
    clips.append(giant_call_clip(bones, rig))
    clips.append(giant_roar_clip(bones, rig))
    for k in range(len(clips)):
        assert_equal(clips[k].name, names[k])
        assert_equal(len(clips[k].tracks), JOINT_COUNT + 1)
        assert_almost_equal(
            clips[k].duration().to(SECOND), seconds[k], atol=1e-4
        )


def test_a_slam_raises_the_mace_and_a_stomp_lifts_a_knee() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    _play(scene, giant_slam_clip(bones, rig), 0.0)
    var ready = scene.node(bones[LEFT_UPPER_ARM.value]).quaternion
    var other = scene.node(bones[RIGHT_UPPER_ARM.value]).quaternion
    # Both arms go up over the head: the weapon arm on plus x, mirrored.
    _play(scene, giant_slam_clip(bones, rig), 0.12)
    var raised = scene.node(bones[LEFT_UPPER_ARM.value]).quaternion
    var both = scene.node(bones[RIGHT_UPPER_ARM.value]).quaternion
    assert_true(_turn(ready, raised) > 0.05)
    assert_true(_turn(other, both) > 0.05)
    # The stomp lifts the weapon side's knee high.
    _play(scene, giant_stomp_clip(bones, rig), 0.0)
    var standing = scene.node(bones[LEFT_THIGH.value]).quaternion
    _play(scene, giant_stomp_clip(bones, rig), 0.156)
    var lifted = scene.node(bones[LEFT_THIGH.value]).quaternion
    assert_true(_turn(standing, lifted) > 0.1)


def test_a_cleave_turns_the_body_across() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    _play(scene, giant_cleave_clip(bones, rig), 0.33)
    var wound = scene.node(bones[CHEST.value]).quaternion
    _play(scene, giant_cleave_clip(bones, rig), 0.57)
    var swept = scene.node(bones[CHEST.value]).quaternion
    assert_true(_turn(wound, swept) > 0.02)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
