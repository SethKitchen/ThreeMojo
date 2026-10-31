# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clips of a giant's attacks for a game humanoid: a raid boss that swings
a mace with its whole weight.

The clips are written as the sword clips are: for the weapon arm on plus
x, and turned over by `mirrored`. See
`extensions.humanoid.rig.sword_clips`. Each clip lasts as long as the
fighter's move that stands in for the attack, and strikes as that move
does. So a boss that paces the move to its wind-up strikes as its zone
does.

| Clip | Seconds | Its move | What it shows |
|---|---|---|---|
| `giant_cleave_clip` | 1.09 | `HEAVY` | The mace drawn far back, and swept flat across the front |
| `giant_slam_clip` | 0.75 | `PLUNGE` | The mace raised in both hands over the head, and slammed down |
| `giant_stomp_clip` | 0.65 | `GROUND_WAVE` | A knee raised high, and the foot driven down, the arms out |
| `giant_charge_clip` | 1.44 | `PIERCE` | A crouch, the shoulder lowered, and a lunge behind it |
| `giant_call_clip` | 0.8 | `CAST` | The free hand thrust at the sky, the head thrown back |
| `giant_roar_clip` | 1.1 | `MEND` | The arms spread wide, the chest out, the head back |

This is not a three.js port. See Extensions.
"""

from animation.animation_clip import AnimationClip
from core.object3d import NodeId
from extensions.humanoid.rig.clips import Pose
from extensions.humanoid.rig.joints import (
    HEAD,
    LEFT_SHIN,
    LEFT_THIGH,
    NECK,
    RIGHT_FOOT,
    RIGHT_SHIN,
    RIGHT_THIGH,
    HumanoidRig,
)
from extensions.humanoid.rig.sword_clips import (
    Grip,
    keyed_clip,
    ready_pose,
    rig_scale,
    set_arm,
    set_body,
    set_free_hand,
    set_legs,
)
from math.vector3 import Vector3


def _round(
    name: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    var keys: List[Pose],
    var at: List[Float32],
    seconds: Float32,
) raises -> AnimationClip:
    """Return a clip from the ready stance, through its key poses, and back
    to the ready stance at its end."""
    var rest = ready_pose(rig_scale(rig))
    keys.insert(0, rest.copy())
    keys.append(rest^)
    at.insert(0, 0)
    at.append(1)
    return keyed_clip(name, bones, rig, keys, at, seconds)


def giant_cleave_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a giant's cleave: the mace drawn far back on its side, and
    swept flat across the front as the body turns, 1.09 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"giant_cleave"`. It strikes as `HEAVY` does.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var wind = Pose()
    set_legs(wind, 10, 20, 0.5, scale)
    set_body(wind, 35, Vector3(4, 25, 6), Vector3(2, 30, 0))
    wind.turn(HEAD, 0, -30)
    set_arm(wind, Grip(-70, -30, 75, -35, 20, 40))
    set_free_hand(wind, -60, -20, -50)
    var sweep = Pose()
    set_legs(sweep, 30, 25, 0.65, scale)
    set_body(sweep, -10, Vector3(14, -10, 0), Vector3(8, -15, 0))
    set_arm(sweep, Grip(-95, -10, 30, -10, 60, 30))
    set_free_hand(sweep, -40, -40, -30)
    var follow = Pose()
    set_legs(follow, 35, 25, 0.7, scale)
    set_body(follow, -40, Vector3(18, -30, -6), Vector3(10, -35, 0))
    follow.turn(HEAD, -6, 25)
    set_arm(follow, Grip(-80, 20, -30, -20, 60, 20))
    set_free_hand(follow, -10, -50, -20)
    var hold = follow.copy()
    var keys: List[Pose] = [wind^, sweep^, follow^, hold^]
    var at: List[Float32] = [0.3, 0.43, 0.52, 0.66]
    return _round("giant_cleave", bones, rig, keys^, at^, 1.09)


def giant_slam_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a giant's slam: the mace raised in both hands over the head,
    and slammed down to the ground in a deep bend, 0.75 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"giant_slam"`. It strikes as `PLUNGE` does.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var raised = Pose()
    set_legs(raised, 15, 15, 0.25, scale)
    set_body(raised, 0, Vector3(-14, 0, 0), Vector3(-10, 0, 0))
    raised.turn(HEAD, -15)
    set_arm(raised, Grip(-172, 0, 6, -45, 30, 0))
    set_free_hand(raised, -168, -6, -45)
    var slam = Pose()
    set_legs(slam, 35, 25, 0.95, scale)
    set_body(slam, 0, Vector3(38, 0, 0), Vector3(22, 0, 0))
    slam.turn(NECK, -20)
    set_arm(slam, Grip(-75, 0, 10, -6, 70, 0))
    set_free_hand(slam, -70, -8, -10)
    var hold = slam.copy()
    var keys: List[Pose] = [raised^, slam^, hold^]
    var at: List[Float32] = [0.16, 0.3, 0.6]
    return _round("giant_slam", bones, rig, keys^, at^, 0.75)


def giant_stomp_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a giant's stomp: a knee raised high, and the foot driven
    down, the arms thrown out for balance, 0.65 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"giant_stomp"`. It strikes as `GROUND_WAVE` does.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var knee = Pose()
    set_body(knee, 0, Vector3(-8, 0, 6), Vector3(-6, 0, 0))
    knee.turn(RIGHT_THIGH, -95, 0, 10)
    knee.turn(RIGHT_SHIN, 100)
    knee.turn(RIGHT_FOOT, 20)
    knee.turn(LEFT_THIGH, -10)
    knee.turn(LEFT_SHIN, 20)
    set_arm(knee, Grip(-50, 0, 55, -30, 0, 0))
    set_free_hand(knee, -50, -55, -30)
    var stomp = Pose()
    set_legs(stomp, 25, 10, 0.75, scale)
    set_body(stomp, 0, Vector3(20, 0, 0), Vector3(12, 0, 0))
    stomp.turn(NECK, -15)
    set_arm(stomp, Grip(-30, 0, 70, -15, 0, 0))
    set_free_hand(stomp, -30, -70, -15)
    var hold = stomp.copy()
    var keys: List[Pose] = [knee^, stomp^, hold^]
    var at: List[Float32] = [0.24, 0.38, 0.62]
    return _round("giant_stomp", bones, rig, keys^, at^, 0.65)


def giant_charge_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a giant's charge: a crouch with the shoulder lowered, and a
    lunge behind it, 1.44 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"giant_charge"`. It strikes as `PIERCE` does.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var coil = Pose()
    set_legs(coil, 20, 30, 0.85, scale)
    set_body(coil, -25, Vector3(30, -20, 0), Vector3(15, -15, 0))
    coil.turn(HEAD, -25)
    set_arm(coil, Grip(-25, 0, 20, -95, 10, 0))
    set_free_hand(coil, -35, -15, -100)
    var lunge = Pose()
    set_legs(lunge, 55, 40, 0.45, scale)
    lunge.lift = lunge.lift + Vector3(0, 0, Float32(0.3) * scale)
    set_body(lunge, -30, Vector3(28, -25, 0), Vector3(14, -20, 0))
    lunge.turn(HEAD, -30)
    set_arm(lunge, Grip(-20, 0, 25, -100, 10, 0))
    set_free_hand(lunge, -20, -20, -110)
    var hold = lunge.copy()
    var keys: List[Pose] = [coil^, lunge^, hold^]
    var at: List[Float32] = [0.4, 0.53, 0.72]
    return _round("giant_charge", bones, rig, keys^, at^, 1.44)


def giant_call_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a giant's call to the sky, as it brings a boulder down: the
    free hand thrust up, the head thrown back, 0.8 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"giant_call"`. It strikes as `CAST` does.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var gather = Pose()
    set_legs(gather, 10, 10, 0.45, scale)
    set_body(gather, 0, Vector3(14, 0, 0), Vector3(8, 0, 0))
    set_arm(gather, Grip(-20, 0, 15, -40, 0, 0))
    set_free_hand(gather, -30, -10, -120)
    var sky = Pose()
    set_legs(sky, 10, 10, 0.15, scale)
    set_body(sky, 0, Vector3(-16, 0, 0), Vector3(-12, 0, 0))
    sky.turn(NECK, 15)
    sky.turn(HEAD, 25)
    set_arm(sky, Grip(-25, 0, 20, -30, 0, 0))
    set_free_hand(sky, -175, -10, -5)
    var hold = sky.copy()
    var keys: List[Pose] = [gather^, sky^, hold^]
    var at: List[Float32] = [0.3, 0.5, 0.72]
    return _round("giant_call", bones, rig, keys^, at^, 0.8)


def giant_roar_clip(
    bones: List[NodeId], rig: HumanoidRig
) raises -> AnimationClip:
    """Return a giant's roar, as it calls its wolves: the arms spread
    wide, the chest out and the head thrown back, 1.1 seconds.

    Args:
        bones: One node per joint, in the order of the joints.
        rig: The rig the bones were placed from.

    Returns:
        The clip, named `"giant_roar"`. It strikes as `MEND` does.

    Raises:
        Error: If there is not one bone per joint.
    """
    var scale = rig_scale(rig)
    var draw_in = Pose()
    set_legs(draw_in, 10, 10, 0.5, scale)
    set_body(draw_in, 0, Vector3(20, 0, 0), Vector3(12, 0, 0))
    draw_in.turn(HEAD, -10)
    set_arm(draw_in, Grip(-30, 0, 10, -100, 0, 0))
    set_free_hand(draw_in, -30, -10, -100)
    var roar = Pose()
    set_legs(roar, 12, 12, 0.3, scale)
    set_body(roar, 0, Vector3(-18, 0, 0), Vector3(-14, 0, 0))
    roar.turn(NECK, 15)
    roar.turn(HEAD, 25)
    set_arm(roar, Grip(-60, 0, 80, -10, 0, 0))
    set_free_hand(roar, -60, -80, -10)
    var hold = roar.copy()
    var keys: List[Pose] = [draw_in^, roar^, hold^]
    var at: List[Float32] = [0.35, 0.57, 0.8]
    return _round("giant_roar", bones, rig, keys^, at^, 1.1)
