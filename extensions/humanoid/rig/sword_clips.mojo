# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sword clips for a game humanoid: a ready stance, cuts, specials, a dodge,
a guard, and the reels and the fall of a fighter who is hit.

The sword is in the hand on minus x: `LEFT_HAND` by the rig's names. The
rig faces plus z and calls the side on plus x its right, so a camera
behind it sees minus x on its own right: a player sees the sword in the
right hand. Each pose is written for a sword arm on plus x, and
`mirrored` turns it over to minus x.

Each clip is worked out from key poses, as `jump_clip` is: each key pose
is held for a moment and eased into the next. Each clip that plays once
lasts as long as its move does in the middle stance, so it plays at its
own rate there. In the table, the right and the left are the sword arm's
side and the other side:

| Clip | Seconds | What it shows |
|---|---|---|
| `ready_clip` | 2.0, loops | Knees bent, the right foot forward, the sword before the body, point up |
| `light_one_clip` | 0.5 | A cut from the right across to the left |
| `light_two_clip` | 0.5 | A backhand cut from the left back to the right |
| `light_three_clip` | 0.77 | A step and a cut down from over the head |
| `heavy_clip` | 1.09 | A long wind-up high on the right, and a lunge that cuts down to the left |
| `rising_edge_clip` | 0.81 | A crouch with the sword low on the left, and a cut up that rises onto the toes |
| `whirlwind_clip` | 1.06 | The sword arm out, and a whole turn of the body |
| `ground_wave_clip` | 0.65 | A crouch with the sword low behind, and a cut along the ground and up |
| `ultimate_clip` | 2.1 | The sword raised to the sky, two whole turns of the body with the sword arm out, and a cut down |
| `cast_clip` | 0.8 | The sword raised, and pointed at the foe with the free hand beside it |
| `plunge_clip` | 0.75 | The sword raised over the head, and a cut down to the ground in a deep crouch |
| `throw_clip` | 1.0 | The free arm drawn back over the shoulder, and flung forward to throw a knife |
| `pierce_clip` | 1.44 | A long coil with the sword drawn back at the hip, and a lunge that thrusts it straight ahead |
| `dodge_clip` | 0.48 | A low, quick crouch with the sword held in |
| `guard_clip` | 1.0, loops | The blade upright before the face, the knees bent |
| `flinch_clip` | 0.4 | The head and the chest thrown back |
| `stagger_clip` | 1.6 | Bent over, the sword low, swaying for breath |
| `fall_clip` | 2.0 | The knees give, and the body falls on its back |

This is not a three.js port. See Extensions.
"""

from animation.animation_clip import AnimationClip
from core.object3d import NodeId
from extensions.humanoid.rig.clips import Pose, clip_from_poses
from extensions.humanoid.rig.joints import (
    JOINT_COUNT,
    CHEST,
    HEAD,
    HIPS,
    LEFT_FOOT,
    LEFT_FOREARM,
    LEFT_HAND,
    LEFT_SHIN,
    LEFT_THIGH,
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
)
from math.smoothstep import hermite_fade
from math.utils import clamp
from math.vector3 import Vector3
from std.math import sin, pi

comptime SAMPLES = 30
"""How many poses a clip samples a second."""
comptime WHIRLWIND_SECONDS = Float32(1.06)
"""How long the whirlwind's clip lasts, in seconds."""
comptime WHIRLWIND_BEGIN = Float32(0.18)
"""When the whirlwind's spin begins, in seconds."""
comptime WHIRLWIND_END = Float32(0.66)
"""When the whirlwind's spin ends, in seconds."""
comptime ULTIMATE_SECONDS = Float32(2.1)
"""How long the ultimate lasts, in seconds."""
comptime ULTIMATE_BEGIN = Float32(0.5)
"""When the ultimate's spins begin, in seconds."""
comptime ULTIMATE_END = Float32(1.5)
"""When the ultimate's spins end, in seconds."""


@fieldwise_init
struct Grip(ImplicitlyCopyable):
    """How the sword arm is held, in degrees: the shoulder's flexion,
    twist and lean, the elbow's flexion, and the wrist's flexion and roll.

    A fist that holds a sword points it the way the thumb points: forward
    from an arm that hangs. The wrist's flexion turns the blade toward the
    line of the forearm, and its roll turns the blade about that line.
    """

    var flex: Float32
    var twist: Float32
    var lean: Float32
    var elbow: Float32
    var wrist: Float32
    var roll: Float32


def twin_joint(joint: Int) -> Int:
    """Return the joint that mirrors a joint across the body's middle.

    Args:
        joint: A joint's place in the rig's order.

    Returns:
        The same joint on the other side for an arm's or a leg's joint,
        and the joint itself for the hips, the spine, the neck and the
        head.
    """
    if joint >= RIGHT_UPPER_ARM.value and joint <= RIGHT_HAND.value:
        return joint + 3
    if joint >= LEFT_UPPER_ARM.value and joint <= LEFT_HAND.value:
        return joint - 3
    if joint >= RIGHT_THIGH.value and joint <= RIGHT_TOES.value:
        return joint + 4
    if joint >= LEFT_THIGH.value:
        return joint - 4
    return joint


def mirrored(pose: Pose) -> Pose:
    """Return a pose mirrored across the body's middle.

    Args:
        pose: The pose.

    Returns:
        Each joint's turn given to its twin, with its twist and its lean
        turned the other way, and the hips moved the other way along x.
    """
    var out = Pose()
    for joint in range(JOINT_COUNT):  # pragma: no branch
        var a = pose.angles[joint]
        out.angles[twin_joint(joint)] = Vector3(a.x, -a.y, -a.z)
    out.lift = Vector3(-pose.lift.x, pose.lift.y, pose.lift.z)
    return out^


def _clip(
    name: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    poses: List[Pose],
    seconds: Float32,
) raises -> AnimationClip:
    """Return a clip of poses written for a sword arm on plus x, mirrored
    so the sword arm is on minus x."""
    var turned = List[Pose](capacity=len(poses))
    for pose in poses:  # pragma: no branch
        turned.append(mirrored(pose))
    return clip_from_poses(name, bones, rig, turned, seconds)


def _arm(mut pose: Pose, grip: Grip):
    """Turn the sword arm to a grip."""
    pose.turn(RIGHT_UPPER_ARM, grip.flex, grip.twist, grip.lean)
    pose.turn(RIGHT_FOREARM, grip.elbow)
    pose.turn(RIGHT_HAND, grip.wrist, grip.roll)


def _body(
    mut pose: Pose,
    hips: Float32,
    spine: Vector3,
    chest: Vector3,
):
    """Turn the trunk: the hips' twist, and the spine's and the chest's
    flexion, twist and lean."""
    pose.turn(HIPS, 0, hips)
    pose.turn(SPINE, spine.x, spine.y, spine.z)
    pose.turn(CHEST, chest.x, chest.y, chest.z)


def _legs(
    mut pose: Pose,
    front: Float32,
    back: Float32,
    bend: Float32,
    scale: Float32,
):
    """Set the legs: the right thigh `front` degrees forward, the left
    `back` degrees back, both knees bent by `bend` from zero to one, and
    the feet a little apart."""
    pose.turn(RIGHT_THIGH, -front - 40 * bend, 0, 5)
    pose.turn(LEFT_THIGH, back - 40 * bend, 0, -5)
    pose.turn(RIGHT_SHIN, 70 * bend)
    pose.turn(LEFT_SHIN, 70 * bend)
    pose.turn(RIGHT_FOOT, -30 * bend + front * 0.3)
    pose.turn(LEFT_FOOT, -30 * bend - back * 0.3)
    pose.lift = pose.lift + Vector3(0, -Float32(0.11) * bend * scale, 0)


def _free_hand(mut pose: Pose, flex: Float32, lean: Float32, elbow: Float32):
    """Turn the arm without the sword."""
    pose.turn(LEFT_UPPER_ARM, flex, 0, lean)
    pose.turn(LEFT_FOREARM, elbow)


def _ready(scale: Float32) -> Pose:
    """Return the ready stance: knees bent, the sword side forward, the
    sword before the body, point up and forward."""
    var pose = Pose()
    _legs(pose, 18, 8, 0.35, scale)
    _body(pose, -20, Vector3(6, 6, 0), Vector3(2, 8, 0))
    pose.turn(HEAD, -4, 8)
    _arm(pose, Grip(-38, -9, 17, -51, 34, 7))
    # The free hand rides before the chest.
    _free_hand(pose, -25, -12, -95)
    return pose^


def _keyed(
    name: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    keys: List[Pose],
    at: List[Float32],
    seconds: Float32,
) raises -> AnimationClip:
    """Return a clip that eases through key poses, each reached at its
    share of `seconds`."""
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    var span = 0
    for k in range(count):  # pragma: no branch
        var t = Float32(k) / Float32(count - 1)
        while span < len(at) - 2 and t > at[span + 1]:
            span += 1
        var u = clamp((t - at[span]) / (at[span + 1] - at[span]), 0, 1)
        poses.append(keys[span].blend(keys[span + 1], hermite_fade(u)))
    return _clip(name, bones, rig, poses, seconds)


def _scale(rig: HumanoidRig) -> Float32:
    """Return the rig's height over six feet."""
    return rig.stature / Float32(1.8288)


def ready_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return the ready stance, two seconds of slow breathing, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"ready"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(2.0)
    var scale = _scale(rig)
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    for k in range(count):  # pragma: no branch
        var phase = Float32(k) / Float32(count - 1)
        var breath = sin(Float32(2 * pi) * phase)
        var pose = _ready(scale)
        pose.lift = pose.lift + Vector3(0, Float32(0.006) * breath * scale, 0)
        pose.turn(CHEST, -1.5 * breath)
        pose.turn(RIGHT_FOREARM, 3 * breath)
        pose.turn(HEAD, 0, 3 * sin(Float32(2 * pi) * phase + 1))
        poses.append(pose^)
    return _clip("ready", bones, rig, poses, seconds)


def _cut(
    name: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    var keys: List[Pose],
    var at: List[Float32],
    seconds: Float32,
) raises -> AnimationClip:
    """Return a cut: from the ready stance through its key poses, and back
    to the ready stance at its end."""
    var scale = _scale(rig)
    keys.insert(0, _ready(scale))
    keys.append(_ready(scale))
    at.insert(0, 0)
    at.append(1)
    return _keyed(name, bones, rig, keys, at, seconds)


def light_one_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the first light attack: a cut from the sword's side across
    to the other side, 0.5 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"light_one"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var wind = Pose()
    _legs(wind, 15, 10, 0.4, scale)
    _body(wind, -5, Vector3(0, 0, 0), Vector3(0, 30, 0))
    wind.turn(HEAD, 0, -20)
    _arm(wind, Grip(-102, 30, 64, -7, 61, 44))
    _free_hand(wind, -20, -15, -80)
    var middle = Pose()
    _legs(middle, 22, 10, 0.45, scale)
    _body(middle, -18, Vector3(4, 0, 0), Vector3(1, 0, 0))
    middle.turn(HEAD, 0, 10)
    _arm(middle, Grip(-86, -2, 31, 0, 74, 38))
    _free_hand(middle, 0, -20, -60)
    var cut = Pose()
    _legs(cut, 28, 10, 0.45, scale)
    _body(cut, -30, Vector3(8, -10, 0), Vector3(2, -25, 0))
    cut.turn(HEAD, 0, 40)
    _arm(cut, Grip(-89, -10, 26, 0, 72, -10))
    _free_hand(cut, 20, -25, -40)
    var keys: List[Pose] = [wind^, middle^, cut^]
    var at: List[Float32] = [0.24, 0.36, 0.5]
    return _cut("light_one", bones, rig, keys^, at^, 0.5)


def light_two_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the second light attack: a backhand cut back across to the
    sword's side, 0.5 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"light_two"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var wind = Pose()
    _legs(wind, 26, 10, 0.45, scale)
    _body(wind, -30, Vector3(8, -10, 0), Vector3(2, -30, 0))
    wind.turn(HEAD, 0, 40)
    _arm(wind, Grip(-27, -54, 88, -47, 36, -9))
    _free_hand(wind, 20, -25, -40)
    var middle = Pose()
    _legs(middle, 24, 10, 0.42, scale)
    _body(middle, -18, Vector3(7, 0, 0), Vector3(1, 0, 0))
    middle.turn(HEAD, 0, 15)
    _arm(middle, Grip(-34, -68, 91, 0, 69, -2))
    _free_hand(middle, -5, -20, -70)
    var cut = Pose()
    _legs(cut, 20, 12, 0.4, scale)
    _body(cut, -5, Vector3(6, 5, 0), Vector3(0, 30, 0))
    cut.turn(HEAD, 0, -15)
    _arm(cut, Grip(-122, -49, 91, -4, 55, 49))
    _free_hand(cut, -30, -20, -90)
    var keys: List[Pose] = [wind^, middle^, cut^]
    var at: List[Float32] = [0.2, 0.32, 0.46]
    return _cut("light_two", bones, rig, keys^, at^, 0.5)


def light_three_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the third light attack: a step and a cut down from over the
    head, 0.77 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"light_three"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var raised = Pose()
    _legs(raised, 10, 5, 0.2, scale)
    raised.lift = raised.lift + Vector3(0, Float32(0.02) * scale, 0)
    _body(raised, -10, Vector3(-8, 0, 0), Vector3(-6, 5, 0))
    raised.turn(HEAD, -6, 5)
    _arm(raised, Grip(-165, 2, 8, -65, 27, 7))
    _free_hand(raised, -60, -20, -60)
    var middle = Pose()
    _legs(middle, 25, 10, 0.4, scale)
    _body(middle, -12, Vector3(8, 0, 0), Vector3(4, 0, 0))
    _arm(middle, Grip(-128, 9, 8, 0, 75, -6))
    _free_hand(middle, -20, -20, -45)
    var down = Pose()
    _legs(down, 40, 15, 0.6, scale)
    down.lift = down.lift + Vector3(0, 0, Float32(0.08) * scale)
    _body(down, -12, Vector3(18, 0, 0), Vector3(10, 0, 0))
    down.turn(NECK, -15)
    down.turn(HEAD, -10)
    _arm(down, Grip(-87, 8, 7, -6, 78, -10))
    _free_hand(down, 25, -20, -30)
    var keys: List[Pose] = [raised^, middle^, down^]
    var at: List[Float32] = [0.24, 0.33, 0.44]
    return _cut("light_three", bones, rig, keys^, at^, 0.77)


def heavy_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return the heavy attack: a long wind-up high on the sword's side,
    and a lunge that cuts down across to the other side, 1.09 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"heavy"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var wind = Pose()
    _legs(wind, 5, 15, 0.45, scale)
    _body(wind, 15, Vector3(-6, 10, 0), Vector3(-4, 25, 0))
    wind.turn(HEAD, 0, -35)
    _arm(wind, Grip(-157, -20, 41, -21, 20, 63))
    _free_hand(wind, -70, -10, -30)
    var middle = Pose()
    _legs(middle, 30, 20, 0.55, scale)
    _body(middle, -5, Vector3(10, 0, 0), Vector3(4, 0, 0))
    _arm(middle, Grip(-139, -30, 40, 0, 90, 42))
    _free_hand(middle, -20, -20, -40)
    var cut = Pose()
    _legs(cut, 45, 25, 0.7, scale)
    cut.lift = cut.lift + Vector3(0, 0, Float32(0.12) * scale)
    _body(cut, -25, Vector3(22, -15, 0), Vector3(10, -25, 0))
    cut.turn(NECK, -15)
    cut.turn(HEAD, -10, 35)
    _arm(cut, Grip(-88, -28, 42, -4, 90, 28))
    _free_hand(cut, 35, -30, -20)
    var hold = cut.copy()
    var keys: List[Pose] = [wind^, middle^, cut^, hold^]
    var at: List[Float32] = [0.34, 0.43, 0.52, 0.64]
    return _cut("heavy", bones, rig, keys^, at^, 1.09)


def rising_edge_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the rising edge: a crouch with the sword low on the other
    side, and a cut up that rises onto the toes, 0.81 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"rising_edge"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var low = Pose()
    _legs(low, 25, 15, 0.9, scale)
    _body(low, -25, Vector3(20, -10, 0), Vector3(8, -20, 0))
    low.turn(HEAD, -15, 30)
    _arm(low, Grip(-61, -9, 22, -12, 80, 13))
    _free_hand(low, 20, -30, -50)
    var middle = Pose()
    _legs(middle, 18, 12, 0.45, scale)
    _body(middle, -10, Vector3(5, 0, 0), Vector3(0, 0, 0))
    _arm(middle, Grip(-93, -10, 21, -3, 60, 10))
    _free_hand(middle, 0, -40, -35)
    var high = Pose()
    _legs(high, 10, 10, 0, scale)
    high.lift = high.lift + Vector3(0, Float32(0.12) * scale, 0)
    for foot in [RIGHT_FOOT, LEFT_FOOT]:  # pragma: no branch
        high.turn(foot, 25)
    _body(high, 5, Vector3(-10, 10, 0), Vector3(-8, 10, 0))
    high.turn(HEAD, 15, -5)
    _arm(high, Grip(-146, -3, 10, 0, 61, 2))
    _free_hand(high, -10, -50, -20)
    var keys: List[Pose] = [low^, middle^, high^]
    var at: List[Float32] = [0.18, 0.3, 0.46]
    return _cut("rising_edge", bones, rig, keys^, at^, 0.81)


def whirlwind_twist(share: Float32) -> Float32:
    """Return how far the whirlwind turns the hips about plus y, as its
    poses are written, before `mirrored` turns them the other way.

    Args:
        share: How far through the clip, from 0 to 1.

    Returns:
        The twist, in degrees: 40 wound back by `WHIRLWIND_BEGIN`, then a
        turn of 400 the other way by `WHIRLWIND_END`, ending a whole turn
        round.
    """
    var begin = WHIRLWIND_BEGIN / WHIRLWIND_SECONDS
    var end = WHIRLWIND_END / WHIRLWIND_SECONDS
    var wind = hermite_fade(clamp(share / begin, 0, 1))
    var spin = hermite_fade(clamp((share - begin) / (end - begin), 0, 1))
    return 40 * wind - 400 * spin


def whirlwind_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the whirlwind: the sword arm out, and a whole turn of the body,
    1.06 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"whirlwind"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = WHIRLWIND_SECONDS
    var scale = _scale(rig)
    # The body winds and unwinds before and after the spin: see
    # `whirlwind_twist`.
    var begin = WHIRLWIND_BEGIN / seconds
    var end = WHIRLWIND_END / seconds
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    for k in range(count):  # pragma: no branch
        var t = Float32(k) / Float32(count - 1)
        var out = clamp(t / begin, 0, 1)
        var back = clamp((t - end) / (1 - end), 0, 1)
        var share = hermite_fade(out) * (1 - hermite_fade(back))
        var pose = _ready(scale).blend(Pose(), share)
        _legs(pose, 0, 0, 0.55 * share, scale)
        pose.turn(HIPS, 0, whirlwind_twist(t))
        pose.turn(SPINE, 8 * share)
        _arm(
            pose,
            Grip(-10 * share, 0, 85 * share, -10 * share, 70 * share, 0),
        )
        pose.turn(LEFT_UPPER_ARM, 0, 0, -60 * share)
        poses.append(pose^)
    return _clip("whirlwind", bones, rig, poses, seconds)


def ground_wave_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the ground wave: a crouch with the sword low behind on its
    side, and a cut along the ground and up, 0.65 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"ground_wave"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var low = Pose()
    _legs(low, 30, 15, 0.8, scale)
    _body(low, -10, Vector3(25, 0, 0), Vector3(10, 0, 0))
    low.turn(HEAD, -15)
    _arm(low, Grip(23, -82, 12, 0, 54, -56))
    _free_hand(low, -30, -20, -60)
    var along = Pose()
    _legs(along, 35, 15, 0.7, scale)
    _body(along, -15, Vector3(8, 0, 0), Vector3(2, 0, 0))
    _arm(along, Grip(16, -69, 90, 0, 86, -35))
    _free_hand(along, 10, -30, -40)
    var up = Pose()
    _legs(up, 30, 15, 0.5, scale)
    _body(up, -18, Vector3(4, 0, 0), Vector3(0, 0, 0))
    _arm(up, Grip(-26, -67, 110, 0, 65, 23))
    _free_hand(up, 20, -30, -30)
    var keys: List[Pose] = [low^, along^, up^]
    var at: List[Float32] = [0.28, 0.38, 0.48]
    return _cut("ground_wave", bones, rig, keys^, at^, 0.65)


def ultimate_twist(share: Float32) -> Float32:
    """Return how far the ultimate's spins turn the hips about plus y,
    as its poses are written, before `mirrored` turns them the other way.

    Args:
        share: How far through the clip, from 0 to 1.

    Returns:
        The twist, in degrees: none until `ULTIMATE_BEGIN`, then two whole
        turns by `ULTIMATE_END`.
    """
    var begin = ULTIMATE_BEGIN / ULTIMATE_SECONDS
    var end = ULTIMATE_END / ULTIMATE_SECONDS
    return -720 * hermite_fade(clamp((share - begin) / (end - begin), 0, 1))


def ultimate_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the ultimate: the sword raised to the sky, two whole turns
    of the body with the sword arm out, and a cut down, 2.1 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"ultimate"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = ULTIMATE_SECONDS
    var scale = _scale(rig)
    var sky = Pose()
    _legs(sky, 5, 5, 0.3, scale)
    _body(sky, 0, Vector3(-8, 0, 0), Vector3(-6, 0, 0))
    sky.turn(HEAD, -20)
    _arm(sky, Grip(-144, 1, 2, -9, 80, -4))
    _free_hand(sky, -20, -40, -20)
    var spin = Pose()
    _legs(spin, 0, 0, 0.55, scale)
    spin.turn(SPINE, 8)
    _arm(spin, Grip(-10, 0, 85, -10, 70, 0))
    spin.turn(LEFT_UPPER_ARM, 0, 0, -60)
    var cut = Pose()
    _legs(cut, 45, 25, 0.8, scale)
    _body(cut, -25, Vector3(22, -15, 0), Vector3(10, -25, 0))
    cut.turn(NECK, -15)
    _arm(cut, Grip(-88, -28, 42, -4, 90, 28))
    _free_hand(cut, 35, -30, -20)
    var keys: List[Pose] = [
        _ready(scale),
        sky.copy(),
        sky^,
        spin.copy(),
        spin^,
        cut.copy(),
        cut^,
        _ready(scale),
    ]
    var at: List[Float32] = [0, 0.14, 0.22, 0.28, 0.69, 0.76, 0.84, 1]
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    var span = 0
    for k in range(count):  # pragma: no branch
        var t = Float32(k) / Float32(count - 1)
        while span < len(at) - 2 and t > at[span + 1]:
            span += 1
        var u = clamp((t - at[span]) / (at[span + 1] - at[span]), 0, 1)
        var pose = keys[span].blend(keys[span + 1], hermite_fade(u))
        var hips = pose.angles[HIPS.value]
        pose.turn(HIPS, hips.x, hips.y + ultimate_twist(t), hips.z)
        poses.append(pose^)
    return _clip("ultimate", bones, rig, poses, seconds)


def plunge_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return the plunge: the sword raised over the head, and a cut down to
    the ground in a deep crouch, 0.75 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"plunge"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var raised = Pose()
    _legs(raised, 20, 20, 0.3, scale)
    _body(raised, -10, Vector3(-10, 0, 0), Vector3(-6, 5, 0))
    raised.turn(HEAD, -10, 5)
    _arm(raised, Grip(-165, 2, 8, -65, 27, 7))
    _free_hand(raised, -70, -20, -60)
    var slam = Pose()
    _legs(slam, 40, 30, 0.95, scale)
    _body(slam, -12, Vector3(28, 0, 0), Vector3(14, 0, 0))
    slam.turn(NECK, -20)
    slam.turn(HEAD, -10)
    _arm(slam, Grip(-87, 8, 7, -6, 78, -10))
    _free_hand(slam, 30, -30, -20)
    var hold = slam.copy()
    var keys: List[Pose] = [raised^, slam^, hold^]
    var at: List[Float32] = [0.16, 0.36, 0.6]
    return _cut("plunge", bones, rig, keys^, at^, 0.75)


def throw_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a thrower's throw: the free arm drawn back over the shoulder,
    and flung forward to throw a knife, the sword held low, 1.0 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"throw"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var wind = Pose()
    _legs(wind, 15, 25, 0.35, scale)
    _body(wind, 25, Vector3(-4, 10, 0), Vector3(-6, 15, 0))
    wind.turn(HEAD, 0, -35)
    _arm(wind, Grip(-42, -7, 17, -21, 42, 8))
    _free_hand(wind, -160, -20, -100)
    var fling = Pose()
    _legs(fling, 35, 15, 0.4, scale)
    _body(fling, -15, Vector3(10, -10, 0), Vector3(6, -15, 0))
    fling.turn(HEAD, 0, 20)
    _arm(fling, Grip(-42, -7, 17, -21, 42, 8))
    _free_hand(fling, -70, -10, -5)
    var hold = fling.copy()
    var keys: List[Pose] = [wind^, fling^, hold^]
    var at: List[Float32] = [0.38, 0.5, 0.62]
    return _cut("throw", bones, rig, keys^, at^, 1.0)


def cast_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a companion's cast: the sword raised, and pointed at the foe
    with the free hand beside it, 0.8 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"cast"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var raised = Pose()
    _legs(raised, 10, 10, 0.3, scale)
    _body(raised, -5, Vector3(-4, 0, 0), Vector3(-4, 0, 0))
    raised.turn(HEAD, -10)
    _arm(raised, Grip(-144, 1, 2, -9, 80, -4))
    _free_hand(raised, -40, -10, -60)
    var point = Pose()
    _legs(point, 25, 15, 0.4, scale)
    _body(point, -20, Vector3(8, -5, 0), Vector3(4, -10, 0))
    point.turn(HEAD, 0, 20)
    _arm(point, Grip(-94, -2, 48, -3, 77, 3))
    _free_hand(point, -80, -20, -10)
    var hold = point.copy()
    var keys: List[Pose] = [raised^, point^, hold^]
    var at: List[Float32] = [0.3, 0.52, 0.66]
    return _cut("cast", bones, rig, keys^, at^, 0.8)


def pierce_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return the piercing attack: a long coil with the sword drawn back at
    the hip, point forward, and a lunge that thrusts it straight ahead,
    1.44 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"pierce"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var coil = Pose()
    _legs(coil, 10, 30, 0.6, scale)
    _body(coil, 20, Vector3(10, 10, 0), Vector3(5, 15, 0))
    coil.turn(HEAD, 0, -40)
    _arm(coil, Grip(17, -31, 30, -97, 56, 7))
    _free_hand(coil, -60, -15, -40)
    # It winds in deeper as the glow grows.
    var deeper = Pose()
    _legs(deeper, 10, 32, 0.7, scale)
    _body(deeper, 25, Vector3(12, 12, 0), Vector3(6, 18, 0))
    deeper.turn(HEAD, 0, -48)
    _arm(deeper, Grip(24, -32, 41, -114, 61, 12))
    _free_hand(deeper, -65, -15, -45)
    var thrust = Pose()
    _legs(thrust, 40, 25, 0.75, scale)
    thrust.lift = thrust.lift + Vector3(0, 0, Float32(0.2) * scale)
    _body(thrust, -25, Vector3(15, -10, 0), Vector3(8, -15, 0))
    thrust.turn(HEAD, -5, 40)
    _arm(thrust, Grip(-94, -2, 48, -3, 77, 3))
    _free_hand(thrust, 30, -25, -20)
    var hold = thrust.copy()
    var keys: List[Pose] = [coil^, deeper^, thrust^, hold^]
    var at: List[Float32] = [0.18, 0.44, 0.56, 0.68]
    return _cut("pierce", bones, rig, keys^, at^, 1.44)


def dodge_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a dodge: a low, quick crouch with the sword held in, 0.48
    seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"dodge"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var low = Pose()
    _legs(low, 30, 30, 0.85, scale)
    _body(low, 0, Vector3(30, 0, 0), Vector3(15, 0, 0))
    low.turn(NECK, -25)
    low.turn(HEAD, -15)
    _arm(low, Grip(-63, -2, 19, -63, 68, 10))
    _free_hand(low, -20, -10, -100)
    var hold = low.copy()
    var keys: List[Pose] = [low^, hold^]
    var at: List[Float32] = [0.2, 0.65]
    return _cut("dodge", bones, rig, keys^, at^, 0.48)


def guard_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return the guard: the blade held across before the face and the
    knees bent, one second of breathing, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"guard"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(1.0)
    var scale = _scale(rig)
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    for k in range(count):  # pragma: no branch
        var breath = sin(Float32(2 * pi) * Float32(k) / Float32(count - 1))
        var pose = Pose()
        _legs(pose, 15, 15, 0.5 + 0.03 * breath, scale)
        _body(pose, -10, Vector3(10, 5, 0), Vector3(4, 5, 0))
        pose.turn(NECK, -8)
        _arm(pose, Grip(-56, -40, 64, -96, 41, -48))
        _free_hand(pose, -55, -5, -85)
        pose.turn(LEFT_HAND, 20)
        poses.append(pose^)
    return _clip("guard", bones, rig, poses, seconds)


def flinch_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a flinch: the head and the chest thrown back, 0.4 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"flinch"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    var thrown = Pose()
    _legs(thrown, 0, 20, 0.3, scale)
    thrown.lift = thrown.lift + Vector3(0, 0, -Float32(0.06) * scale)
    _body(thrown, 10, Vector3(-14, 0, 4), Vector3(-10, 0, 0))
    thrown.turn(NECK, -12)
    thrown.turn(HEAD, -15, 0, 6)
    _arm(thrown, Grip(11, 25, 48, -34, 32, -3))
    _free_hand(thrown, -10, -35, -30)
    var keys: List[Pose] = [thrown^]
    var at: List[Float32] = [0.25]
    return _cut("flinch", bones, rig, keys^, at^, 0.4)


def stagger_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a stagger: bent over, the sword low, swaying for breath, 1.6
    seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"stagger"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = Float32(1.6)
    var scale = _scale(rig)
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    for k in range(count):  # pragma: no branch
        var t = Float32(k) / Float32(count - 1)
        # In over the first tenth, and out over the last.
        var share = hermite_fade(clamp(t / 0.1, 0, 1)) * (
            1 - hermite_fade(clamp((t - 0.85) / 0.15, 0, 1))
        )
        var sway = sin(Float32(3 * pi) * t)
        var breath = sin(Float32(8 * pi) * t)
        var bent = Pose()
        _legs(bent, 10, 20, 0.6, scale)
        bent.turn(HIPS, 0, 0, 5 * sway)
        bent.turn(SPINE, 25 + 3 * breath, 0, -4 * sway)
        bent.turn(CHEST, 15 + 2 * breath)
        bent.turn(NECK, -20)
        _arm(bent, Grip(-42, -7, 17, -21, 42, 8))
        _free_hand(bent, -45, -5, -30)
        poses.append(_ready(scale).blend(bent, share))
    return _clip("stagger", bones, rig, poses, seconds)


def fall_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a fall: the knees give, and the body falls on its back, 2
    seconds. It ends lying down.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"fall"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = _scale(rig)
    # The hips rest this far over the soles.
    var hips = -rig.at(RIGHT_TOES).y
    var buckle = Pose()
    _legs(buckle, 10, 10, 0.7, scale)
    buckle.turn(SPINE, -10)
    buckle.turn(HEAD, -20)
    _arm(buckle, Grip(-30, 0, 30, -40, 20, 0))
    _free_hand(buckle, -30, -30, -20)
    var tipping = Pose()
    _legs(tipping, 20, 20, 0.5, scale)
    tipping.lift = Vector3(0, -hips * 0.55, -Float32(0.25) * scale)
    tipping.turn(HIPS, -50)
    tipping.turn(SPINE, -10)
    tipping.turn(HEAD, 20)
    _arm(tipping, Grip(-60, 0, 50, -20, 10, 0))
    _free_hand(tipping, -60, -50, -20)
    var lying = Pose()
    lying.lift = Vector3(0, Float32(0.13) * scale - hips, -Float32(0.4) * scale)
    lying.turn(HIPS, -88)
    lying.turn(RIGHT_THIGH, -20, 0, 10)
    lying.turn(LEFT_THIGH, -5, 0, -8)
    lying.turn(RIGHT_SHIN, 35)
    lying.turn(LEFT_SHIN, 10)
    lying.turn(HEAD, 10, 25)
    _arm(lying, Grip(-20, 0, 60, -15, 80, 0))
    _free_hand(lying, -30, -45, -20)
    var still = lying.copy()
    var keys: List[Pose] = [_ready(scale), buckle^, tipping^, lying^, still^]
    var at: List[Float32] = [0, 0.15, 0.32, 0.45, 1]
    return _keyed("fall", bones, rig, keys, at, 2.0)
