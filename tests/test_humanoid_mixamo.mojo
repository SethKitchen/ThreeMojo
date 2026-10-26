# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the Mixamo retarget on a game humanoid.

The skeleton in `tests/_mixamo_fixture.mojo` has Mixamo's bone names and
its T-pose, so every expected direction is worked out by hand: a Mixamo
left arm along +x, turned 90 degrees about z by minus ninety, points down.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import QUATERNION, SCALE, VISIBLE, KeyframeTrack
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    JOINT_COUNT,
    LEFT_FOOT,
    LEFT_FOREARM,
    LEFT_THIGH,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
    humanoid_rig,
    joint_parent,
    named_joints,
)
from extensions.humanoid.rig.mixamo import (
    ROLE_COUNT,
    MixamoOptions,
    _clip_name,
    mixamo_key,
    mixamo_role,
    read_mixamo,
    retarget_mixamo,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.torso.body import body_skin_mesh
from extensions.humanoid.spec import HumanoidSpec
from loaders.fbx import load_fbx
from loaders.fbx_tree import parse_fbx_text
from math.vector3 import Vector3
from renderers.renderer import available_workers
from std.os import remove, rmdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._mixamo_fixture import Motion, mixamo_text
from units.si import FOOT, SECOND, Duration, Length


def _rig() raises -> HumanoidRig:
    """Return a six-foot man's rig, placed on a coarse skin."""
    var spec = HumanoidSpec(Length(6.0, FOOT), MALE)
    return humanoid_rig(
        spec, body_skin_mesh(spec, 12, available_workers(), 0.014)
    )


def _mirrored(rig: HumanoidRig) raises -> HumanoidRig:
    """Return the rig with its right side at -x, as a right-handed rig has
    it."""
    var joints = List[Vector3]()
    var ends = List[Vector3]()
    for index in range(JOINT_COUNT):
        joints.append(
            Vector3(
                -rig.joints[index].x, rig.joints[index].y, rig.joints[index].z
            )
        )
        ends.append(
            Vector3(-rig.ends[index].x, rig.ends[index].y, rig.ends[index].z)
        )
    return HumanoidRig(joints^, ends^, rig.stature)


def _bones(mut scene: Scene, rig: HumanoidRig) raises -> List[NodeId]:
    """Return one scene node per joint, hung as the rig hangs them."""
    var bones = List[NodeId]()
    var root = scene.add(Object3D())
    for joint in named_joints():
        var node = Object3D()
        var at = rig.local(joint)
        node.set_position(at.x, at.y, at.z)
        var hang = root
        if joint != HIPS:
            hang = bones[joint_parent(joint).value]
        bones.append(scene.attach(node^, hang))
    return bones^


def _hold() -> List[Motion]:
    """Return an animation that moves nothing: the hips stay at rest."""
    var motions = List[Motion]()
    motions.append(
        Motion(
            "Hips",
            "T",
            [0.0, 1.0],
            [0.0, 0.0],
            [100.0, 100.0],
            [0.0, 0.0],
        )
    )
    return motions^


def _turn(bone: String, x: Float64, y: Float64, z: Float64) -> Motion:
    """Return a turn of one bone from rest to the given angles in a second."""
    return Motion(bone, "R", [0.0, 1.0], [0.0, x], [0.0, y], [0.0, z])


def _retarget(
    text: String,
    rig: HumanoidRig,
    bones: List[NodeId],
    options: MixamoOptions = MixamoOptions(),
) raises -> List[AnimationClip]:
    """Retarget an ASCII FBX text."""
    var scratch = Scene()
    var assets = Assets()
    var source = load_fbx(parse_fbx_text(text), "", scratch, assets)
    return retarget_mixamo(scratch, source, bones, rig, options)


def _show(
    mut scene: Scene,
    clip: AnimationClip,
    seconds: Float32,
) raises:
    """Pose the humanoid's bones as a clip has them at a time."""
    for track in clip.tracks:
        var node = NodeId(track.target.index)
        var at = Duration(seconds, SECOND)
        if track.target.kind == QUATERNION:
            scene.node(node).quaternion = track.sample_quaternion(at)
        else:
            scene.node(node).position = track.sample_vector3(at)
    scene.update()


def _points(
    scene: Scene, bones: List[NodeId], joint_value: Int
) raises -> Vector3:
    """Return the direction from a joint to the one below it, of length one."""
    var way = scene.world_position(
        bones[joint_value + 1]
    ) - scene.world_position(bones[joint_value])
    way.normalize()
    return way


def _expect(actual: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert that a direction is the one given."""
    assert_almost_equal(actual.x, x, atol=2e-3)
    assert_almost_equal(actual.y, y, atol=2e-3)
    assert_almost_equal(actual.z, z, atol=2e-3)


def test_names_are_read_with_or_without_the_prefix() raises:
    assert_equal(mixamo_key("mixamorig:Hips"), "hips")
    assert_equal(mixamo_key("mixamorigHips"), "hips")
    assert_equal(mixamo_key("mixamorig1:LeftArm"), "leftarm")
    assert_equal(mixamo_key("Model::mixamorig:Spine1"), "spine1")
    assert_equal(mixamo_key("Left_Toe_End"), "lefttoeend")
    assert_equal(mixamo_role("mixamorig:Hips"), 0)
    assert_equal(mixamo_role("mixamorig:LeftToe_End"), 14)
    assert_equal(mixamo_role("mixamorig:RightToe_End"), ROLE_COUNT - 1)
    assert_equal(mixamo_role("mixamorig:LeftHandThumb1"), -1)
    assert_equal(mixamo_role("Armature"), -1)


def test_a_rest_pose_stands_the_humanoid_in_the_t_pose() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var clips = _retarget(mixamo_text(_hold()), rig, bones)
    assert_equal(len(clips), 1)
    assert_equal(clips[0].name, "mixamo.com")
    _show(scene, clips[0], 0)
    # A Mixamo left arm stands at +x, as the humanoid's right arm does.
    _expect(_points(scene, bones, RIGHT_UPPER_ARM.value), 1, 0, 0)
    _expect(_points(scene, bones, RIGHT_FOREARM.value), 1, 0, 0)
    _expect(_points(scene, bones, LEFT_UPPER_ARM.value), -1, 0, 0)
    _expect(_points(scene, bones, LEFT_FOREARM.value), -1, 0, 0)
    _expect(_points(scene, bones, RIGHT_THIGH.value), 0, -1, 0)
    _expect(_points(scene, bones, LEFT_THIGH.value), 0, -1, 0)
    _expect(_points(scene, bones, HIPS.value), 0, 1, 0)
    _expect(_points(scene, bones, SPINE.value), 0, 1, 0)
    _expect(_points(scene, bones, CHEST.value), 0, 1, 0)
    _expect(_points(scene, bones, NECK.value), 0, 1, 0)
    # The fixture's foot points down and forward: 8 down, 13 ahead.
    _expect(_points(scene, bones, RIGHT_FOOT.value), 0, -0.5241, 0.8517)
    _expect(_points(scene, bones, LEFT_FOOT.value), 0, -0.5241, 0.8517)


def test_an_arm_that_turns_down_points_down() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var motions = _hold()
    motions.append(_turn("LeftArm", 0, 0, -90))
    var clips = _retarget(mixamo_text(motions), rig, bones)
    _show(scene, clips[0], 1)
    _expect(_points(scene, bones, RIGHT_UPPER_ARM.value), 0, -1, 0)
    # The forearm hangs from the arm and goes with it.
    _expect(_points(scene, bones, RIGHT_FOREARM.value), 0, -1, 0)
    # The other arm did not move.
    _expect(_points(scene, bones, LEFT_UPPER_ARM.value), -1, 0, 0)


def test_a_leg_that_swings_forward_points_forward() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var motions = _hold()
    motions.append(_turn("LeftUpLeg", -90, 0, 0))
    var clips = _retarget(mixamo_text(motions), rig, bones)
    _show(scene, clips[0], 1)
    _expect(_points(scene, bones, RIGHT_THIGH.value), 0, 0, 1)
    _expect(_points(scene, bones, LEFT_THIGH.value), 0, -1, 0)


def test_a_turn_of_the_spine_carries_the_arms_with_it() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var motions = _hold()
    # Two steps of 170 degrees: the second leaves a quaternion whose sign
    # a matrix cannot keep.
    motions.append(
        Motion(
            "Spine1",
            "R",
            [0.0, 0.5, 1.0],
            [0.0, 0.0, 0.0],
            [0.0, 170.0, 340.0],
            [0.0, 0.0, 0.0],
        )
    )
    var clips = _retarget(mixamo_text(motions), rig, bones)
    _show(scene, clips[0], 1)
    # +x turned 340 degrees about y.
    _expect(_points(scene, bones, RIGHT_UPPER_ARM.value), 0.9397, 0, 0.3420)
    for track in clips[0].tracks:
        if track.target.kind != QUATERNION:
            continue
        for key in range(1, track.key_count()):
            var before = track.values[4 * key - 4 : 4 * key]
            var after = track.values[4 * key : 4 * key + 4]
            var dot = Float32(0)
            for part in range(4):
                dot += before[part] * after[part]
            assert_true(dot >= 0)


def test_the_hips_travel_by_the_ratio_of_the_hip_heights() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var motions = List[Motion]()
    motions.append(
        Motion(
            "Hips",
            "T",
            [0.0, 0.5, 1.0],
            [0.0, 0.0, 0.0],
            [100.0, 95.0, 100.0],
            [0.0, 30.0, 60.0],
        )
    )
    var kept = _retarget(
        mixamo_text(motions), rig, bones, MixamoOptions(in_place=False)
    )
    # The Mixamo hips stand 93 cm above the ankles, and the humanoid's
    # stand this far above its own.
    var own = rig.joints[HIPS.value].y - rig.joints[RIGHT_FOOT.value].y
    var ratio = own / 93.0
    var rest = rig.local(HIPS)
    _show(scene, kept[0], 0.5)
    var at = scene.world_position(bones[HIPS.value])
    assert_almost_equal(at.x, rest.x, atol=1e-4)
    assert_almost_equal(at.y, rest.y - 5 * ratio, atol=1e-4)
    assert_almost_equal(at.z, rest.z + 30 * ratio, atol=1e-4)
    _show(scene, kept[0], 1)
    assert_almost_equal(
        scene.world_position(bones[HIPS.value]).z,
        rest.z + 60 * ratio,
        atol=1e-4,
    )
    # In place, the straight line of the travel goes and the dip stays.
    var held = _retarget(mixamo_text(motions), rig, bones)
    _show(scene, held[0], 0.5)
    at = scene.world_position(bones[HIPS.value])
    assert_almost_equal(at.y, rest.y - 5 * ratio, atol=1e-4)
    assert_almost_equal(at.z, rest.z, atol=1e-4)
    _show(scene, held[0], 1)
    assert_almost_equal(
        scene.world_position(bones[HIPS.value]).z, rest.z, atol=1e-4
    )


def test_a_clip_is_sampled_every_step_and_at_its_end() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var clips = _retarget(mixamo_text(_hold()), rig, bones)
    assert_equal(len(clips[0].tracks), JOINT_COUNT + 1)
    assert_equal(clips[0].tracks[0].key_count(), 31)
    var coarse = _retarget(
        mixamo_text(_hold()), rig, bones, MixamoOptions(samples_per_second=4)
    )
    assert_equal(coarse[0].tracks[0].key_count(), 5)
    # A rate that does not divide the length ends on the end itself.
    var long = List[Motion]()
    long.append(
        Motion("Hips", "T", [0.0, 1.2], [0.0, 0.0], [100.0, 100.0], [0.0, 0.0])
    )
    var odd = _retarget(
        mixamo_text(long), rig, bones, MixamoOptions(samples_per_second=4)
    )
    assert_equal(odd[0].tracks[0].key_count(), 6)
    assert_almost_equal(odd[0].tracks[0].times[5], Float32(1.2))
    assert_almost_equal(odd[0].duration().to(SECOND), Float32(1.2))


def test_a_rig_that_stands_the_other_way_pairs_the_other_way() raises:
    var rig = _mirrored(_rig())
    var scene = Scene()
    var bones = _bones(scene, rig)
    var motions = _hold()
    motions.append(_turn("LeftArm", 0, 0, -90))
    var clips = _retarget(mixamo_text(motions), rig, bones)
    _show(scene, clips[0], 1)
    # The humanoid's left arm now stands at +x, and a Mixamo left arm
    # drives it.
    _expect(_points(scene, bones, LEFT_UPPER_ARM.value), 0, -1, 0)
    _expect(_points(scene, bones, RIGHT_UPPER_ARM.value), -1, 0, 0)


def test_marks_that_are_not_letters_or_digits_are_dropped() raises:
    assert_equal(mixamo_key(""), "")
    # A space, a dash and a dot stand below the digits.
    assert_equal(mixamo_key("Left Arm-1.x"), "leftarm1x")
    # A brace stands above the letters, and so do the bytes of an accent.
    assert_equal(mixamo_key("Hips~{\u00e9"), "hips")
    # A prefix with nothing after it, and one with only a number.
    assert_equal(mixamo_key("mixamorig"), "")
    assert_equal(mixamo_key("mixamorig12"), "")
    assert_equal(mixamo_role("mixamorig12:Hips"), 0)


def test_the_first_of_two_bones_with_one_name_drives_the_joint() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var motions = _hold()
    motions.append(_turn("LeftArm", 0, 0, -90))
    var clips = _retarget(mixamo_text(motions, duplicate="LeftArm"), rig, bones)
    _show(scene, clips[0], 1)
    _expect(_points(scene, bones, RIGHT_UPPER_ARM.value), 0, -1, 0)


def test_scales_and_other_tracks_do_not_turn_the_humanoid() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var motions = _hold()
    motions.append(_turn("LeftArm", 0, 0, -90))
    motions.append(
        Motion("LeftArm", "S", [0.0, 1.0], [1.0, 2.0], [1.0, 2.0], [1.0, 2.0])
    )
    var scratch = Scene()
    var assets = Assets()
    var source = load_fbx(
        parse_fbx_text(mixamo_text(motions)), "", scratch, assets
    )
    var scaled = False
    for track in source.animations[0].tracks:
        if track.target.kind == SCALE:
            scaled = True
    assert_true(scaled)
    # A flag on a node is a track that the retarget does not read.
    var times: List[Duration] = [Duration(0.0, SECOND)]
    var flag: List[Float32] = [1.0]
    source.animations[0].tracks.append(
        KeyframeTrack(source.models[0], VISIBLE, times, flag^)
    )
    var clips = retarget_mixamo(scratch, source, bones, rig)
    _show(scene, clips[0], 1)
    _expect(_points(scene, bones, RIGHT_UPPER_ARM.value), 0, -1, 0)


def test_a_file_may_lack_the_bones_of_the_spine_and_the_head() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    for missing in ["Spine1", "Spine2", "HeadTop_End", "LeftToe_End", "Neck"]:
        var motions = _hold()
        motions.append(_turn("LeftArm", 0, 0, -90))
        var clips = _retarget(
            mixamo_text(motions, leave_out=String(missing)), rig, bones
        )
        _show(scene, clips[0], 1)
        _expect(_points(scene, bones, RIGHT_UPPER_ARM.value), 0, -1, 0)


def test_a_file_without_a_needed_bone_is_refused() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    with assert_raises(contains="no bone named leftleg"):
        _ = _retarget(mixamo_text(_hold(), leave_out="LeftLeg"), rig, bones)
    var spine = List[Motion]()
    spine.append(_turn("Spine", 0, 0, 10))
    with assert_raises(contains="no bone named hips"):
        _ = _retarget(mixamo_text(spine, leave_out="Hips"), rig, bones)


def test_a_file_without_animation_is_refused() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    with assert_raises(contains="holds no animation"):
        _ = _retarget(mixamo_text(List[Motion]()), rig, bones)


def test_hips_below_the_feet_are_refused() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    with assert_raises(contains="hips must stand above the feet"):
        _ = _retarget(mixamo_text(_hold(), upside_down=True), rig, bones)


def test_the_options_and_the_bones_are_checked() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    with assert_raises(contains="sampling rate"):
        _ = _retarget(
            mixamo_text(_hold()),
            rig,
            bones,
            MixamoOptions(samples_per_second=0),
        )
    var few = List[NodeId]()
    few.append(bones[0])
    with assert_raises(contains="one bone per joint"):
        _ = _retarget(mixamo_text(_hold()), rig, few)


def test_a_file_names_its_clip() raises:
    assert_equal(_clip_name("a/b/Walking.fbx", "mixamo.com", 1), "Walking")
    assert_equal(_clip_name("Idle", "mixamo.com", 1), "Idle")
    assert_equal(_clip_name("a/Walking.fbx", "Take 2", 2), "Walking Take 2")
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var folder = mkdtemp(prefix="mixamo test ")
    var path = folder + "/Walking.fbx"
    Path(path).write_text(mixamo_text(_hold()))
    var clips = read_mixamo(path, bones, rig)
    assert_equal(len(clips), 1)
    assert_equal(clips[0].name, "Walking")
    remove(path)
    rmdir(folder)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
