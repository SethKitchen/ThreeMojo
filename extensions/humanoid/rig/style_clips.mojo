# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clips of the other fighting styles for a game humanoid: fists and feet,
a mage's staff, and a bow.

The clips are written as the sword clips are: for the weapon arm on plus
x, and turned over by `mirrored`. See
`extensions.humanoid.rig.sword_clips`. The weapon arm is the hand a player
sees on the right. A staff is held in it. A bow is held in the other hand,
and the weapon arm draws the string. Each clip that plays once lasts as
long as the sword's move of the same button does, so a style's pace plays
it faster or slower.

| Clip | Seconds | What it shows |
|---|---|---|
| `fists_ready_clip` | 2.0, loops | The other foot forward, the fists up by the chin |
| `fists_guard_clip` | 1.0, loops | The forearms up before the face |
| `jab_clip` | 0.5 | The lead fist snapped straight out |
| `cross_clip` | 0.5 | The rear fist driven straight out, the hips turning |
| `kick_clip` | 0.77 | The rear leg chambered and kicked in an arc at the ribs |
| `haymaker_clip` | 1.09 | The rear fist cocked back, and swung over and down |
| `uppercut_clip` | 0.81 | A crouch, and the rear fist driven up as the body rises |
| `spin_kick_clip` | 1.06 | A whole turn of the body with the rear leg out |
| `ground_punch_clip` | 0.65 | The rear fist raised, and driven down to the ground |
| `staff_ready_clip` | 2.0, loops | The staff upright at the side |
| `staff_bolt_clip` | 0.52 | The staff pointed at the foe, the free palm out |
| `staff_blast_clip` | 1.05 | The staff drawn back, and thrust out with both hands |
| `nova_clip` | 0.87 | The staff raised high, and driven into the ground |
| `mend_clip` | 1.1 | The staff raised high and held, the face lifted |
| `bow_ready_clip` | 2.0, loops | Side on, the bow low in the other hand |
| `quick_shot_clip` | 0.42 | A short draw to the chin, and a loose |
| `aimed_shot_clip` | 0.98 | A long draw to the ear, held, and a loose |
| `volley_clip` | 0.8 | The bow canted, drawn, and loosed in a sweep |
| `leap_shot_clip` | 0.7 | A crouch, the legs tucked in the air, and a loose |
| `rain_clip` | 0.9 | The bow raised high, drawn, and loosed at the sky |

This is not a three.js port. See Extensions.
"""

from animation.animation_clip import AnimationClip
from core.object3d import NodeId
from extensions.humanoid.rig.clips import Pose
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_FOOT,
    LEFT_HAND,
    LEFT_SHIN,
    LEFT_THIGH,
    NECK,
    RIGHT_FOOT,
    RIGHT_HAND,
    RIGHT_SHIN,
    RIGHT_THIGH,
    SPINE,
    HumanoidRig,
)
from extensions.humanoid.rig.sword_clips import (
    SAMPLES,
    WHIRLWIND_SECONDS,
    Grip,
    keyed_clip,
    mirrored_clip,
    rig_scale,
    set_arm,
    set_body,
    set_free_hand,
    set_legs,
    whirlwind_twist,
)
from math.smoothstep import hermite_fade
from math.utils import clamp
from math.vector3 import Vector3
from std.math import pi, sin


def _round(
    name: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    rest: Pose,
    var keys: List[Pose],
    var at: List[Float32],
    seconds: Float32,
) raises -> AnimationClip:
    """Return a clip from a resting pose, through its key poses, and back
    to the resting pose at its end."""
    keys.insert(0, rest.copy())
    keys.append(rest.copy())
    at.insert(0, 0)
    at.append(1)
    return keyed_clip(name, bones, rig, keys, at, seconds)


def _breathing(
    name: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    rest: Pose,
    seconds: Float32,
) raises -> AnimationClip:
    """Return a loop of a resting pose that breathes."""
    var scale = rig_scale(rig)
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    for k in range(count):  # pragma: no branch
        var phase = Float32(k) / Float32(count - 1)
        var breath = sin(Float32(2 * pi) * phase)
        var pose = rest.copy()
        pose.lift = pose.lift + Vector3(0, Float32(0.006) * breath * scale, 0)
        pose.turn(CHEST, -1.5 * breath)
        pose.turn(HEAD, 0, 2 * sin(Float32(2 * pi) * phase + 1))
        poses.append(pose^)
    return mirrored_clip(name, bones, rig, poses, seconds)


def fists_pose(scale: Float32) -> Pose:
    """Return a fighter's stance with bare fists: the other foot forward,
    the knees bent, the fists up by the chin.

    Args:
        scale: The rig's height over six feet.

    Returns:
        The pose.
    """
    var pose = Pose()
    set_legs(pose, -8, -16, 0.38, scale)
    set_body(pose, 22, Vector3(8, -8, 0), Vector3(4, -10, 0))
    pose.turn(NECK, 6)
    pose.turn(HEAD, 6, -14)
    set_arm(pose, Grip(-42, 0, 28, -122, 15, 0))
    set_free_hand(pose, -62, -12, -108)
    return pose^


def fists_ready_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the stance with bare fists, two seconds of breathing, which
    loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"fists_ready"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    return _breathing(
        "fists_ready", bones, rig, fists_pose(rig_scale(rig)), 2.0
    )


def fists_guard_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the guard with bare fists: the forearms up before the face,
    one second of breathing, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"fists_guard"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var pose = Pose()
    set_legs(pose, -6, -12, 0.5, scale)
    set_body(pose, 15, Vector3(14, -4, 0), Vector3(8, -6, 0))
    pose.turn(NECK, 12)
    pose.turn(HEAD, 8)
    set_arm(pose, Grip(-75, 0, 38, -135, 5, 0))
    set_free_hand(pose, -75, -30, -135)
    return _breathing("fists_guard", bones, rig, pose, 1.0)


def jab_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a jab: the lead fist snapped straight out, 0.5 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"jab"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = fists_pose(scale)
    var load = rest.copy()
    set_body(load, 28, Vector3(8, -10, 0), Vector3(4, -14, 0))
    var out = rest.copy()
    set_legs(out, -6, -24, 0.42, scale)
    out.lift = out.lift + Vector3(0, 0, Float32(0.06) * scale)
    set_body(out, 32, Vector3(10, -12, 0), Vector3(6, -18, 0))
    set_free_hand(out, -88, -4, -6)
    var hold = out.copy()
    var keys: List[Pose] = [load^, out^, hold^]
    var at: List[Float32] = [0.18, 0.38, 0.5]
    return _round("jab", bones, rig, rest, keys^, at^, 0.5)


def cross_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a cross: the rear fist driven straight out as the hips turn,
    0.5 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"cross"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = fists_pose(scale)
    var load = rest.copy()
    set_body(load, 30, Vector3(8, -12, 0), Vector3(4, -16, 0))
    var out = rest.copy()
    set_legs(out, -2, -22, 0.42, scale)
    out.lift = out.lift + Vector3(0, 0, Float32(0.07) * scale)
    set_body(out, -18, Vector3(10, 12, 0), Vector3(6, 18, 0))
    out.turn(HEAD, 6, 6)
    set_arm(out, Grip(-88, 0, 6, -6, 0, 0))
    set_free_hand(out, -55, -16, -122)
    # The rear heel lifts as the hips turn.
    out.turn(RIGHT_FOOT, 25)
    var hold = out.copy()
    var keys: List[Pose] = [load^, out^, hold^]
    var at: List[Float32] = [0.16, 0.36, 0.48]
    return _round("cross", bones, rig, rest, keys^, at^, 0.5)


def kick_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a roundhouse kick: the rear leg chambered, and kicked in an arc
    at the ribs, 0.77 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"kick"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = fists_pose(scale)
    var chamber = rest.copy()
    set_body(chamber, -10, Vector3(-4, 10, 0), Vector3(-2, 10, 0))
    chamber.turn(RIGHT_THIGH, -80, 0, 35)
    chamber.turn(RIGHT_SHIN, 105)
    chamber.turn(RIGHT_FOOT, 30)
    chamber.turn(LEFT_THIGH, -12)
    chamber.turn(LEFT_SHIN, 18)
    var out = chamber.copy()
    set_body(out, -45, Vector3(-14, 18, -8), Vector3(-6, 12, 0))
    out.turn(RIGHT_THIGH, -75, 0, 55)
    out.turn(RIGHT_SHIN, 8)
    out.turn(RIGHT_FOOT, 35)
    out.turn(HEAD, 6, 30)
    var back = chamber.copy()
    var keys: List[Pose] = [chamber^, out^, back^]
    var at: List[Float32] = [0.22, 0.38, 0.56]
    return _round("kick", bones, rig, rest, keys^, at^, 0.77)


def haymaker_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a haymaker: the rear fist cocked back, and swung over and
    down as the body lunges, 1.09 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"haymaker"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = fists_pose(scale)
    var cock = rest.copy()
    set_legs(cock, -14, -10, 0.5, scale)
    set_body(cock, 40, Vector3(-2, -20, 0), Vector3(-4, -25, 0))
    set_arm(cock, Grip(-60, 45, 80, -110, 10, 0))
    var swing = rest.copy()
    set_legs(swing, 10, -30, 0.62, scale)
    swing.lift = swing.lift + Vector3(0, 0, Float32(0.14) * scale)
    set_body(swing, -35, Vector3(22, 18, 0), Vector3(10, 24, 0))
    swing.turn(HEAD, 10, 10)
    set_arm(swing, Grip(-100, -15, 22, -18, 10, 0))
    set_free_hand(swing, -30, -20, -110)
    var hold = swing.copy()
    var keys: List[Pose] = [cock^, swing^, hold^]
    var at: List[Float32] = [0.34, 0.5, 0.64]
    return _round("haymaker", bones, rig, rest, keys^, at^, 1.09)


def uppercut_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return an uppercut: a crouch, and the rear fist driven up as the body
    rises onto its toes, 0.81 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"uppercut"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = fists_pose(scale)
    var dip = rest.copy()
    set_legs(dip, -10, -18, 0.78, scale)
    set_body(dip, 25, Vector3(24, -10, 0), Vector3(12, -12, 0))
    set_arm(dip, Grip(-15, 0, 15, -95, 10, 0))
    var rise = rest.copy()
    set_legs(rise, -4, -10, 0.05, scale)
    rise.lift = rise.lift + Vector3(0, Float32(0.06) * scale, 0)
    rise.turn(RIGHT_FOOT, 30)
    rise.turn(LEFT_FOOT, 20)
    set_body(rise, -20, Vector3(-12, 12, 0), Vector3(-8, 15, 0))
    rise.turn(HEAD, -15)
    set_arm(rise, Grip(-150, 0, 12, -55, 5, 0))
    var hold = rise.copy()
    var keys: List[Pose] = [dip^, rise^, hold^]
    var at: List[Float32] = [0.22, 0.42, 0.56]
    return _round("uppercut", bones, rig, rest, keys^, at^, 0.81)


def spin_kick_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a spinning heel kick: a whole turn of the body with the rear
    leg out, 1.06 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"spin_kick"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var seconds = WHIRLWIND_SECONDS
    var scale = rig_scale(rig)
    var poses = List[Pose]()
    var count = Int(seconds * SAMPLES) + 1
    for k in range(count):  # pragma: no branch
        var t = Float32(k) / Float32(count - 1)
        var rise = hermite_fade(clamp(t / 0.17, 0, 1))
        var back = hermite_fade(clamp((t - 0.62) / 0.38, 0, 1))
        var share = rise * (1 - back)
        var pose = fists_pose(scale).blend(Pose(), share * 0.5)
        pose.turn(HIPS, 0, whirlwind_twist(t))
        pose.turn(SPINE, -10 * share, 0, -12 * share)
        pose.turn(RIGHT_THIGH, -15 * share, 0, 75 * share)
        pose.turn(RIGHT_SHIN, 10 * share)
        pose.turn(RIGHT_FOOT, 30 * share)
        pose.turn(LEFT_THIGH, -20 * share)
        pose.turn(LEFT_SHIN, 30 * share)
        poses.append(pose^)
    return mirrored_clip("spin_kick", bones, rig, poses, seconds)


def ground_punch_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a ground punch: the rear fist raised, and driven down to the
    ground in a deep crouch, 0.65 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"ground_punch"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = fists_pose(scale)
    var raise_up = rest.copy()
    set_legs(raise_up, -6, -12, 0.3, scale)
    set_body(raise_up, 10, Vector3(-10, 0, 0), Vector3(-6, 0, 0))
    raise_up.turn(HEAD, -8)
    set_arm(raise_up, Grip(-165, 0, 10, -40, 0, 0))
    var slam = rest.copy()
    set_legs(slam, 20, -40, 0.95, scale)
    slam.lift = slam.lift + Vector3(0, -Float32(0.05) * scale, 0)
    set_body(slam, 0, Vector3(40, 0, 0), Vector3(25, 0, 0))
    slam.turn(NECK, -20)
    set_arm(slam, Grip(-55, 0, 10, -4, 0, 0))
    set_free_hand(slam, -20, -30, -90)
    var hold = slam.copy()
    var keys: List[Pose] = [raise_up^, slam^, hold^]
    var at: List[Float32] = [0.24, 0.42, 0.62]
    return _round("ground_punch", bones, rig, rest, keys^, at^, 0.65)


def staff_pose(scale: Float32) -> Pose:
    """Return a mage's stance: the staff upright at the weapon side, the
    other hand open before the body.

    Args:
        scale: The rig's height over six feet.

    Returns:
        The pose.
    """
    var pose = Pose()
    set_legs(pose, 10, 6, 0.22, scale)
    set_body(pose, -8, Vector3(3, 4, 0), Vector3(1, 4, 0))
    pose.turn(HEAD, -2, 6)
    set_arm(pose, Grip(-12, 0, 14, -82, 0, 0))
    set_free_hand(pose, -28, -10, -62)
    return pose^


def staff_ready_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the mage's stance, two seconds of breathing, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"staff_ready"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    return _breathing(
        "staff_ready", bones, rig, staff_pose(rig_scale(rig)), 2.0
    )


def staff_bolt_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a spell bolt: the staff pointed at the foe, the free palm
    out beside it, 0.52 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"staff_bolt"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = staff_pose(scale)
    var lift = rest.copy()
    set_arm(lift, Grip(-35, 5, 22, -95, 20, 0))
    set_free_hand(lift, -35, -10, -70)
    var point = rest.copy()
    set_legs(point, 22, 10, 0.32, scale)
    set_body(point, -18, Vector3(6, -6, 0), Vector3(3, -8, 0))
    point.turn(HEAD, 0, 16)
    set_arm(point, Grip(-94, -2, 40, -3, 77, 3))
    set_free_hand(point, -85, -14, -12)
    point.turn(LEFT_HAND, -60)
    var hold = point.copy()
    var keys: List[Pose] = [lift^, point^, hold^]
    var at: List[Float32] = [0.2, 0.42, 0.56]
    return _round("staff_bolt", bones, rig, rest, keys^, at^, 0.52)


def staff_blast_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a spell blast: the staff drawn back, and thrust out with both
    hands as the body lunges, 1.05 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"staff_blast"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = staff_pose(scale)
    var gather = rest.copy()
    set_legs(gather, 6, 18, 0.45, scale)
    set_body(gather, 28, Vector3(-6, 14, 0), Vector3(-4, 18, 0))
    set_arm(gather, Grip(-25, 25, 35, -115, 40, 0))
    set_free_hand(gather, -40, -20, -100)
    var thrust = rest.copy()
    set_legs(thrust, 34, 14, 0.55, scale)
    thrust.lift = thrust.lift + Vector3(0, 0, Float32(0.12) * scale)
    set_body(thrust, -20, Vector3(14, -8, 0), Vector3(8, -10, 0))
    thrust.turn(HEAD, -4, 10)
    set_arm(thrust, Grip(-92, 0, 30, -6, 80, 0))
    set_free_hand(thrust, -90, -6, -6)
    thrust.turn(LEFT_HAND, -60)
    var hold = thrust.copy()
    var keys: List[Pose] = [gather^, thrust^, hold^]
    var at: List[Float32] = [0.42, 0.56, 0.7]
    return _round("staff_blast", bones, rig, rest, keys^, at^, 1.05)


def nova_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a nova: the staff raised high, and driven down into the ground
    in a crouch, 0.87 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"nova"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = staff_pose(scale)
    var high = rest.copy()
    set_legs(high, 8, 6, 0.1, scale)
    set_body(high, 0, Vector3(-10, 0, 0), Vector3(-8, 0, 0))
    high.turn(HEAD, -15)
    set_arm(high, Grip(-168, 0, 6, -12, 0, 0))
    set_free_hand(high, -150, -25, -20)
    var down = rest.copy()
    set_legs(down, 18, 18, 0.78, scale)
    set_body(down, 0, Vector3(28, 0, 0), Vector3(16, 0, 0))
    down.turn(NECK, -10)
    set_arm(down, Grip(-58, 0, 22, -22, -18, 0))
    set_free_hand(down, -20, -45, -40)
    var hold = down.copy()
    var keys: List[Pose] = [high^, down^, hold^]
    var at: List[Float32] = [0.3, 0.44, 0.62]
    return _round("nova", bones, rig, rest, keys^, at^, 0.87)


def mend_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a mend: the staff raised high and held, the free hand open,
    the face lifted, 1.1 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"mend"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = staff_pose(scale)
    var up = rest.copy()
    set_legs(up, 8, 4, 0.12, scale)
    set_body(up, 0, Vector3(-8, 0, 0), Vector3(-10, 0, 0))
    up.turn(NECK, -10)
    up.turn(HEAD, -20)
    set_arm(up, Grip(-162, 0, 12, -15, 0, 0))
    set_free_hand(up, -120, -35, -25)
    var hold = up.copy()
    var keys: List[Pose] = [up^, hold^]
    var at: List[Float32] = [0.32, 0.74]
    return _round("mend", bones, rig, rest, keys^, at^, 1.1)


def bow_pose(scale: Float32) -> Pose:
    """Return an archer's stance: side on, the bow low in the other hand.

    Args:
        scale: The rig's height over six feet.

    Returns:
        The pose.
    """
    var pose = Pose()
    set_legs(pose, -6, -10, 0.25, scale)
    set_body(pose, 35, Vector3(3, -10, 0), Vector3(1, -12, 0))
    pose.turn(HEAD, -2, -30)
    set_arm(pose, Grip(-20, 0, 12, -40, 0, 0))
    set_free_hand(pose, -35, -10, -25)
    return pose^


def _drawn(scale: Float32, rise: Float32, depth: Float32) -> Pose:
    """Return a full draw: side on, the bow arm out at `rise` degrees over
    the level, the string drawn back by `depth` from zero to one."""
    var pose = bow_pose(scale)
    set_legs(pose, -8, -14, 0.3, scale)
    set_body(pose, 55, Vector3(0, -18, 0), Vector3(-2, -20, 0))
    pose.turn(HEAD, -rise * 0.5, -55)
    set_free_hand(pose, -88 - rise, -15, -4)
    set_arm(pose, Grip(-88 - rise, 20, 70 * depth, -150 * depth, 0, 0))
    return pose^


def bow_ready_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return the archer's stance, two seconds of breathing, which loops.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"bow_ready"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    return _breathing("bow_ready", bones, rig, bow_pose(rig_scale(rig)), 2.0)


def quick_shot_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a quick shot: a short draw to the chin, and a loose, 0.42
    seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"quick_shot"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = bow_pose(scale)
    var draw = _drawn(scale, 0, 0.85)
    var loose = _drawn(scale, 2, 1)
    set_arm(loose, Grip(-92, 30, 80, -120, 0, 0))
    var keys: List[Pose] = [draw^, loose^]
    var at: List[Float32] = [0.36, 0.56]
    return _round("quick_shot", bones, rig, rest, keys^, at^, 0.42)


def aimed_shot_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return an aimed shot: a long draw to the ear, held, and a loose, 0.98
    seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"aimed_shot"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = bow_pose(scale)
    var draw = _drawn(scale, 0, 1)
    var held = draw.copy()
    var loose = _drawn(scale, 2, 1)
    set_arm(loose, Grip(-95, 35, 85, -110, 0, 0))
    var keys: List[Pose] = [draw^, held^, loose^]
    var at: List[Float32] = [0.36, 0.64, 0.74]
    return _round("aimed_shot", bones, rig, rest, keys^, at^, 0.98)


def volley_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a volley: the bow canted, drawn, and loosed in a sweep, 0.8
    seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"volley"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = bow_pose(scale)
    var draw = _drawn(scale, 6, 1)
    draw.turn(SPINE, 0, 0, -10)
    draw.turn(RIGHT_HAND, 0, 40)
    var sweep = _drawn(scale, 6, 1)
    set_body(sweep, 25, Vector3(0, -6, 0), Vector3(0, -8, 0))
    set_arm(sweep, Grip(-95, 30, 80, -115, 0, 0))
    var keys: List[Pose] = [draw^, sweep^]
    var at: List[Float32] = [0.38, 0.6]
    return _round("volley", bones, rig, rest, keys^, at^, 0.8)


def leap_shot_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a leap shot: a crouch, the legs tucked in the air, and a
    loose at the top, 0.7 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"leap_shot"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = bow_pose(scale)
    var crouch = rest.copy()
    set_legs(crouch, 20, 20, 0.85, scale)
    set_body(crouch, 30, Vector3(25, -8, 0), Vector3(10, -10, 0))
    var tuck = _drawn(scale, -10, 1)
    tuck.turn(RIGHT_THIGH, -70)
    tuck.turn(RIGHT_SHIN, 110)
    tuck.turn(LEFT_THIGH, -50)
    tuck.turn(LEFT_SHIN, 100)
    tuck.lift = tuck.lift + Vector3(0, Float32(0.15) * scale, 0)
    var loose = tuck.copy()
    set_arm(loose, Grip(-80, 30, 80, -115, 0, 0))
    var keys: List[Pose] = [crouch^, tuck^, loose^]
    var at: List[Float32] = [0.14, 0.4, 0.52]
    return _round("leap_shot", bones, rig, rest, keys^, at^, 0.7)


def rain_clip(bones: List[NodeId], rig: HumanoidRig) raises -> AnimationClip:
    """Return a rain of arrows: the bow raised high, drawn, and loosed at
    the sky, 0.9 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"rain"`.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var rest = bow_pose(scale)
    var draw = _drawn(scale, 55, 1)
    draw.turn(SPINE, -12)
    draw.turn(HEAD, -30, -40)
    var loose = draw.copy()
    set_arm(loose, Grip(-140, 30, 70, -110, 0, 0))
    var keys: List[Pose] = [draw^, loose^]
    var at: List[Float32] = [0.42, 0.6]
    return _round("rain", bones, rig, rest, keys^, at^, 0.9)
