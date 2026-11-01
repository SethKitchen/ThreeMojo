# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Style clips: each plays on a rig's bones for its move's time; a jab
reaches out with the lead hand, a kick lifts the rear leg, and a spin kick
turns the body round."""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import ONCE, AnimationAction, AnimationMixer
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.rig.joints import (
    HIPS,
    JOINT_COUNT,
    LEFT_THIGH,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    HumanoidRig,
    humanoid_rig,
    joint_parent,
    named_joints,
)
from extensions.humanoid.rig.style_clips import (
    aimed_shot_clip,
    bow_pose,
    bow_ready_clip,
    cross_clip,
    fists_guard_clip,
    fists_pose,
    fists_ready_clip,
    ground_punch_clip,
    haymaker_clip,
    jab_clip,
    kick_clip,
    leap_shot_clip,
    mend_clip,
    nova_clip,
    quick_shot_clip,
    rain_clip,
    spin_kick_clip,
    staff_blast_clip,
    staff_bolt_clip,
    staff_pose,
    staff_ready_clip,
    uppercut_clip,
    volley_clip,
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
        "fists_ready",
        "fists_guard",
        "jab",
        "cross",
        "kick",
        "haymaker",
        "uppercut",
        "spin_kick",
        "ground_punch",
        "staff_ready",
        "staff_bolt",
        "staff_blast",
        "nova",
        "mend",
        "bow_ready",
        "quick_shot",
        "aimed_shot",
        "volley",
        "leap_shot",
        "rain",
    ]
    var seconds: List[Float32] = [
        2.0,
        1.0,
        0.5,
        0.5,
        0.77,
        1.09,
        0.81,
        1.06,
        0.65,
        2.0,
        0.52,
        1.05,
        0.87,
        1.1,
        2.0,
        0.42,
        0.98,
        0.8,
        0.7,
        0.9,
    ]
    var clips = List[AnimationClip]()
    clips.append(fists_ready_clip(bones, rig))
    clips.append(fists_guard_clip(bones, rig))
    clips.append(jab_clip(bones, rig))
    clips.append(cross_clip(bones, rig))
    clips.append(kick_clip(bones, rig))
    clips.append(haymaker_clip(bones, rig))
    clips.append(uppercut_clip(bones, rig))
    clips.append(spin_kick_clip(bones, rig))
    clips.append(ground_punch_clip(bones, rig))
    clips.append(staff_ready_clip(bones, rig))
    clips.append(staff_bolt_clip(bones, rig))
    clips.append(staff_blast_clip(bones, rig))
    clips.append(nova_clip(bones, rig))
    clips.append(mend_clip(bones, rig))
    clips.append(bow_ready_clip(bones, rig))
    clips.append(quick_shot_clip(bones, rig))
    clips.append(aimed_shot_clip(bones, rig))
    clips.append(volley_clip(bones, rig))
    clips.append(leap_shot_clip(bones, rig))
    clips.append(rain_clip(bones, rig))
    for k in range(len(clips)):
        assert_equal(clips[k].name, names[k])
        assert_equal(len(clips[k].tracks), JOINT_COUNT + 1)
        assert_almost_equal(
            clips[k].duration().to(SECOND), seconds[k], atol=1e-4
        )


def test_each_style_has_its_own_stance() raises:
    var fists = fists_pose(1)
    var staff = staff_pose(1)
    var bow = bow_pose(1)
    # The fists' stance puts the other foot forward; the bow's turns side
    # on.
    var lead = fists.angles[LEFT_THIGH.value].x
    assert_true(lead < fists.angles[RIGHT_THIGH.value].x)
    assert_true(abs(bow.angles[HIPS.value].y) > abs(staff.angles[HIPS.value].y))


def test_a_jab_reaches_out_and_a_kick_lifts_the_rear_leg() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var rest = scene.node(bones[RIGHT_UPPER_ARM.value]).quaternion
    _play(scene, jab_clip(bones, rig), 0.19)
    var jab = scene.node(bones[RIGHT_UPPER_ARM.value]).quaternion
    assert_true(_turn(rest, jab) > 0.02)
    # The kick lifts the rear leg high: the leg on plus x, mirrored.
    var standing = scene.node(bones[LEFT_THIGH.value]).quaternion
    _play(scene, kick_clip(bones, rig), 0.3)
    var kicked = scene.node(bones[LEFT_THIGH.value]).quaternion
    assert_true(_turn(standing, kicked) > 0.1)


def test_a_spin_kick_turns_the_body_round() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    _play(scene, spin_kick_clip(bones, rig), 0.0)
    var first = scene.node(bones[HIPS.value]).quaternion
    _play(scene, spin_kick_clip(bones, rig), 0.45)
    var half = scene.node(bones[HIPS.value]).quaternion
    assert_true(_turn(first, half) > 0.3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
