# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Animation clips for a game humanoid: idle, walk, run, jump and wave.

Each clip is worked out from the motion itself, not captured, so it
fits any rig a genome makes. A clip samples a pose many times a cycle:
each joint's turn as three angles, and how far the hips move. A joint
flexes about the body's side-to-side axis, twists about the vertical
and leans about the front-to-back axis, as plus x, y and z of the pelvis
frame turn. Each sample becomes one key of a quaternion track per joint
and of a position track for the hips, so the clips play in an
`AnimationMixer` and fade into one another.

- `walk_clip`: a gait of 1.1 s a stride. The hip swings from 26 degrees
  forward at heel strike to 10 back at toe-off; the knee bends 15
  degrees as the foot takes the weight and 60 in the swing; the ankle
  pushes off; the arms swing against the legs; the pelvis bobs, sways
  over the standing foot and turns with the swing.
- `run_clip`: a stride of 0.7 s, with a flight between the steps, the
  arms bent and pumping, and the trunk leaning forward.
- `idle_clip`: four seconds of breathing, a slow shift of the weight
  from foot to foot, and the head looking a little about. It loops.
- `jump_clip`: a crouch, a spring with the arms swung up, a tuck in the
  air and a landing that gives at the knees. It plays once.
- `wave_clip`: the right arm raised and the hand waving, two seconds a
  loop.

The angles follow the joint ranges of an ordinary gait: Winter, "The
Biomechanics and Motor Control of Human Gait", 1991.

This is not a three.js port. See Extensions.

    var mixer = AnimationMixer()
    var walk = mixer.add(AnimationAction(walk_clip(person)))
    mixer.action(walk).play()
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import POSITION, QUATERNION, KeyframeTrack
from core.object3d import NodeId
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    JOINT_COUNT,
    LEFT_FOOT,
    LEFT_FOREARM,
    LEFT_HAND,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_TOES,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_HAND,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
    Joint,
)
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import cos, exp, pi, sin
from units.si import DEGREE, SECOND, Angle, Duration

# How many poses a clip samples per second.
comptime SAMPLES_PER_SECOND = 30


struct Pose(Copyable, Movable):
    """Every joint's turn, as flexion, twist and lean in degrees, and how
    far the hips move from rest, in meters."""

    var angles: List[Vector3]
    var lift: Vector3

    def __init__(out self):
        """Start at rest."""
        self.angles = List[Vector3](length=JOINT_COUNT, fill=Vector3(0, 0, 0))
        self.lift = Vector3(0, 0, 0)

    def turn(
        mut self,
        joint: Joint,
        flex: Float32,
        twist: Float32 = 0,
        lean: Float32 = 0,
    ):
        """Add to one joint's turn.

        Args:
            joint: A named joint.
            flex: About plus x, in degrees.
            twist: About plus y, in degrees.
            lean: About plus z, in degrees.
        """
        self.angles[joint.value] = self.angles[joint.value] + Vector3(
            flex, twist, lean
        )

    def blend(self, other: Pose, t: Float32) -> Pose:
        """Return the pose a fraction `t` of the way to `other`.

        Args:
            other: The pose at one.
            t: Zero for this pose, one for `other`.

        Returns:
            The blend.
        """
        var out = Pose()
        for j in range(JOINT_COUNT):  # pragma: no branch
            out.angles[j] = (
                self.angles[j] + (other.angles[j] - self.angles[j]) * t
            )
        out.lift = self.lift + (other.lift - self.lift) * t
        return out^


def joint_rotation(angles: Vector3) -> Quaternion:
    """Return a joint's turn as a quaternion: the twist, then the
    flexion, then the lean.

    Args:
        angles: Flexion, twist and lean, in degrees.

    Returns:
        The rotation.
    """
    var qx = Quaternion.from_axis_angle(
        Vector3(1, 0, 0), Angle(angles.x, DEGREE)
    )
    var qy = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(angles.y, DEGREE)
    )
    var qz = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(angles.z, DEGREE)
    )
    return qy * qx * qz


def clip_from_poses(
    name: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    poses: List[Pose],
    seconds: Float32,
) raises -> AnimationClip:
    """Return a clip that plays `poses` evenly over `seconds`.

    Args:
        name: The clip's name.
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.
        poses: Two or more poses; the last is shown at `seconds`.
        seconds: How long the clip lasts.

    Returns:
        One quaternion track per joint and a position track for the hips.

    Raises:
        Error: If there is not one bone per joint, fewer than two poses,
            or the length is not above zero.
    """
    if len(bones) != JOINT_COUNT:
        raise Error("A humanoid clip needs one bone per joint")
    if len(poses) < 2 or not (seconds > 0):
        raise Error("A clip needs two poses or more over a time above zero")
    var times = List[Duration](capacity=len(poses))
    for k in range(len(poses)):  # pragma: no branch
        times.append(
            Duration(seconds * Float32(k) / Float32(len(poses) - 1), SECOND)
        )
    var tracks = List[KeyframeTrack]()
    for j in range(JOINT_COUNT):  # pragma: no branch
        var values = List[Float32](capacity=4 * len(poses))
        for k in range(len(poses)):  # pragma: no branch
            var q = joint_rotation(poses[k].angles[j])
            values.append(q.x)
            values.append(q.y)
            values.append(q.z)
            values.append(q.w)
        tracks.append(KeyframeTrack(bones[j], QUATERNION, times, values^))
    var rest = rig.local(HIPS)
    var places = List[Float32](capacity=3 * len(poses))
    for k in range(len(poses)):  # pragma: no branch
        var p = rest + poses[k].lift
        places.append(p.x)
        places.append(p.y)
        places.append(p.z)
    tracks.append(KeyframeTrack(bones[HIPS.value], POSITION, times, places^))
    return AnimationClip(name, tracks^)


def _bump(phase: Float32, center: Float32, width: Float32) -> Float32:
    """Return a bell, one at `center`, on a cycle that wraps at one."""
    var d = phase - center
    d = d - Float32(Int(d + Float32(0.5) + Float32(1000))) + Float32(1000)
    return exp(-(d / width) * (d / width))


def _wave(phase: Float32) -> Float32:
    """Return the cosine of a cycle at `phase`."""
    return cos(Float32(2 * pi) * phase)


def _leg(
    mut pose: Pose,
    thigh: Joint,
    phase: Float32,
    hip_mean: Float32,
    hip_swing: Float32,
    load: Float32,
    swing_knee: Float32,
    swing_at: Float32,
    push: Float32,
    push_at: Float32,
):
    """Turn one leg at a point of its stride: zero at heel strike."""
    var hip = hip_mean + hip_swing * _wave(phase)
    var knee = (
        Float32(4)
        + load * _bump(phase, 0.12, 0.1)
        + swing_knee * _bump(phase, swing_at, 0.16)
    )
    var ankle = (
        push * _bump(phase, push_at, 0.08)
        - Float32(6) * _bump(phase, 0.15, 0.12)
        - Float32(5) * _bump(phase, swing_at + 0.08, 0.1)
    )
    var toes = Float32(-25) * _bump(phase, push_at - 0.02, 0.07)
    pose.turn(thigh, -hip)
    pose.turn(Joint(thigh.value + 1), knee)
    pose.turn(Joint(thigh.value + 2), ankle)
    pose.turn(Joint(thigh.value + 3), toes)


def _sampled(seconds: Float32) -> Int:
    """Return how many poses a clip of `seconds` samples, ends included."""
    return Int(seconds * SAMPLES_PER_SECOND) + 1


def walk_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a walk of one stride, 1.1 s, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"walk"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(1.1)
    var scale = rig.stature / Float32(1.8288)
    var poses = List[Pose]()
    var count = _sampled(seconds)
    for k in range(count):  # pragma: no branch
        var phase = Float32(k) / Float32(count - 1)
        var pose = Pose()
        _leg(pose, RIGHT_THIGH, phase, 8, 18, 15, 60, 0.72, 16, 0.6)
        _leg(pose, LEFT_THIGH, phase + 0.5, 8, 18, 15, 60, 0.72, 16, 0.6)
        var w = _wave(phase)
        # The pelvis bobs twice a stride, sways over the standing foot
        # and turns with the swinging leg; the chest turns against it.
        pose.lift = (
            Vector3(
                Float32(0.018) * sin(Float32(2 * pi) * phase),
                -Float32(0.014) * cos(Float32(4 * pi) * phase),
                0,
            )
            * scale
        )
        pose.turn(HIPS, 0, -6 * w, 3 * sin(Float32(2 * pi) * phase))
        pose.turn(SPINE, 2, 4 * w)
        pose.turn(CHEST, 1, 5 * w)
        pose.turn(HEAD, 0, -2 * w)
        # The arms swing against the legs, the elbows bending as they
        # come forward.
        pose.turn(RIGHT_UPPER_ARM, 16 * w, 0, -4)
        pose.turn(LEFT_UPPER_ARM, -16 * w, 0, 4)
        pose.turn(RIGHT_FOREARM, -(14 + 10 * w))
        pose.turn(LEFT_FOREARM, -(14 - 10 * w))
        poses.append(pose^)
    return clip_from_poses("walk", bones, rig, poses, seconds)


def run_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a run of one stride, 0.7 s, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"run"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(0.7)
    var scale = rig.stature / Float32(1.8288)
    var poses = List[Pose]()
    var count = _sampled(seconds)
    for k in range(count):  # pragma: no branch
        var phase = Float32(k) / Float32(count - 1)
        var pose = Pose()
        _leg(pose, RIGHT_THIGH, phase, 18, 30, 30, 100, 0.68, 22, 0.42)
        _leg(pose, LEFT_THIGH, phase + 0.5, 18, 30, 30, 100, 0.68, 22, 0.42)
        var w = _wave(phase)
        # Highest in the flight between the steps.
        pose.lift = (
            Vector3(
                0,
                Float32(0.03) * cos(Float32(4 * pi) * (phase - 0.25)) - 0.03,
                0,
            )
            * scale
        )
        pose.turn(HIPS, 0, -8 * w)
        pose.turn(SPINE, 8, 6 * w)
        pose.turn(CHEST, 4, 6 * w)
        pose.turn(NECK, -6)
        pose.turn(RIGHT_UPPER_ARM, 35 * w, 0, -6)
        pose.turn(LEFT_UPPER_ARM, -35 * w, 0, 6)
        pose.turn(RIGHT_FOREARM, -(80 + 15 * w))
        pose.turn(LEFT_FOREARM, -(80 - 15 * w))
        poses.append(pose^)
    return clip_from_poses("run", bones, rig, poses, seconds)


def idle_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return four seconds of standing at ease, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"idle"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(4.0)
    var scale = rig.stature / Float32(1.8288)
    var poses = List[Pose]()
    var count = _sampled(seconds)
    for k in range(count):  # pragma: no branch
        var phase = Float32(k) / Float32(count - 1)
        var pose = Pose()
        # Two breaths, one shift of the weight, a glance to each side.
        var breath = sin(Float32(4 * pi) * phase)
        var shift = sin(Float32(2 * pi) * phase)
        pose.lift = (
            Vector3(Float32(0.012) * shift, -0.004 + 0.003 * breath, 0) * scale
        )
        pose.turn(HIPS, 0, 0, -2 * shift)
        pose.turn(SPINE, -1 * breath, 0, 1.5 * shift)
        pose.turn(CHEST, -1.2 * breath)
        pose.turn(
            HEAD,
            2 * sin(Float32(2 * pi) * phase + 1.0),
            6 * sin(Float32(2 * pi) * phase + 2.0),
        )
        # Soft knees, the weight leg the straighter.
        pose.turn(RIGHT_SHIN, 4 - 3 * shift)
        pose.turn(LEFT_SHIN, 4 + 3 * shift)
        pose.turn(RIGHT_THIGH, -2 + 1.5 * shift, 0, 2 * shift)
        pose.turn(LEFT_THIGH, -2 - 1.5 * shift, 0, 2 * shift)
        pose.turn(RIGHT_FOOT, -1 + 1.5 * shift)
        pose.turn(LEFT_FOOT, -1 - 1.5 * shift)
        pose.turn(RIGHT_UPPER_ARM, 2 * breath, 0, -6)
        pose.turn(LEFT_UPPER_ARM, 2 * breath, 0, 6)
        pose.turn(RIGHT_FOREARM, -10)
        pose.turn(LEFT_FOREARM, -10)
        poses.append(pose^)
    return clip_from_poses("idle", bones, rig, poses, seconds)


def _crouch(depth: Float32, scale: Float32) -> Pose:
    """Return a crouch: `depth` zero standing, one a deep squat."""
    var pose = Pose()
    pose.lift = Vector3(
        0, -Float32(0.2) * depth * scale, Float32(0.02) * depth * scale
    )
    for thigh in [RIGHT_THIGH, LEFT_THIGH]:  # pragma: no branch
        pose.turn(thigh, -55 * depth)
        pose.turn(Joint(thigh.value + 1), 95 * depth)
        pose.turn(Joint(thigh.value + 2), -35 * depth)
    pose.turn(SPINE, 18 * depth)
    pose.turn(CHEST, 8 * depth)
    pose.turn(NECK, -14 * depth)
    return pose^


def jump_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a standing jump, 1.4 s, which plays once.

    The jumper crouches with the arms swung back, springs up with the
    arms thrown forward and up, tucks the legs at the top, and lands on
    bent knees before standing again.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"jump"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(1.4)
    var scale = rig.stature / Float32(1.8288)
    # The key poses and when each is reached, as a fraction of the clip.
    var keys = List[Pose]()
    var at = List[Float32]()
    keys.append(Pose())
    at.append(0)
    var low = _crouch(0.8, scale)
    for arm in [RIGHT_UPPER_ARM, LEFT_UPPER_ARM]:  # pragma: no branch
        low.turn(arm, 45)
    keys.append(low^)
    at.append(0.28)
    var spring = Pose()
    spring.lift = Vector3(0, Float32(0.08) * scale, 0)
    for foot in [RIGHT_FOOT, LEFT_FOOT]:  # pragma: no branch
        spring.turn(foot, 35)
    for toes in [RIGHT_TOES, LEFT_TOES]:  # pragma: no branch
        spring.turn(toes, -20)
    for arm in [RIGHT_UPPER_ARM, LEFT_UPPER_ARM]:  # pragma: no branch
        spring.turn(arm, -150)
    keys.append(spring^)
    at.append(0.4)
    var tuck = Pose()
    tuck.lift = Vector3(0, Float32(0.42) * scale, 0)
    for thigh in [RIGHT_THIGH, LEFT_THIGH]:  # pragma: no branch
        tuck.turn(thigh, -50)
        tuck.turn(Joint(thigh.value + 1), 80)
        tuck.turn(Joint(thigh.value + 2), 15)
    for arm in [RIGHT_UPPER_ARM, LEFT_UPPER_ARM]:  # pragma: no branch
        tuck.turn(arm, -100)
    tuck.turn(RIGHT_FOREARM, -40)
    tuck.turn(LEFT_FOREARM, -40)
    keys.append(tuck^)
    at.append(0.58)
    var reach = Pose()
    reach.lift = Vector3(0, Float32(0.06) * scale, 0)
    for foot in [RIGHT_FOOT, LEFT_FOOT]:  # pragma: no branch
        reach.turn(foot, 20)
    for arm in [RIGHT_UPPER_ARM, LEFT_UPPER_ARM]:  # pragma: no branch
        reach.turn(arm, -60)
    keys.append(reach^)
    at.append(0.72)
    var land = _crouch(0.55, scale)
    for arm in [RIGHT_UPPER_ARM, LEFT_UPPER_ARM]:  # pragma: no branch
        land.turn(arm, -35)
    keys.append(land^)
    at.append(0.82)
    keys.append(Pose())
    at.append(1.0)
    var poses = List[Pose]()
    var count = _sampled(seconds)
    var span = 0
    for k in range(count):  # pragma: no branch
        var t = Float32(k) / Float32(count - 1)
        while span < len(at) - 2 and t > at[span + 1]:
            span += 1
        var u = (t - at[span]) / (at[span + 1] - at[span])
        u = min(Float32(1), max(Float32(0), u))
        # Eased, so each key pose is held for a moment.
        u = u * u * (3 - 2 * u)
        poses.append(keys[span].blend(keys[span + 1], u))
    return clip_from_poses("jump", bones, rig, poses, seconds)


def wave_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a wave of the right hand, 2 s, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"wave"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(2.0)
    var poses = List[Pose]()
    var count = _sampled(seconds)
    for k in range(count):  # pragma: no branch
        var phase = Float32(k) / Float32(count - 1)
        var pose = Pose()
        # Three waves a loop, the arm raised out to the side and the
        # forearm upright.
        var wag = sin(Float32(6 * pi) * phase)
        pose.turn(RIGHT_UPPER_ARM, -15, 0, 95)
        pose.turn(RIGHT_FOREARM, 0, 0, 55 + 22 * wag)
        pose.turn(RIGHT_HAND, 0, 0, 10 * wag)
        pose.turn(LEFT_UPPER_ARM, 0, 0, 4)
        pose.turn(LEFT_FOREARM, -10)
        pose.turn(HEAD, 0, 8, -3)
        pose.turn(SPINE, 0, 0, -2)
        poses.append(pose^)
    return clip_from_poses("wave", bones, rig, poses, seconds)
