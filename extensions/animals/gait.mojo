# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A walk cycle for four-legged animals.

procedural-animals drives its quadrupeds with a full gait engine. This
is the lateral-sequence walk of its motion data, as one pose per phase:
each foot is planted for 70 % of the stride and swings forward, lifted,
for the rest. The feet follow their paths by two-bone inverse
kinematics in the leg's plane, so a planted foot stays on the ground.
The lower foot keeps its bind attitude, the back bobs twice a stride and
the tail swings.

A pose turns bones, and the sculpt is meshed again in it, so the joints
keep their shape however far they bend.
"""

from extensions.anatomy.locomotion import WALK_FROUDE, stride_length
from extensions.animals.rig import Pose, Rig
from extensions.sdf.vector import (
    V3,
    smoothstep,
)
from std.math import atan2, acos, cos, pi, sin, sqrt
from units.si import METER, Length

# Each foot's phase offset in the lateral-sequence walk: left fore, right
# fore, left hind, right hind, as procedural-animals' wolf walk.
comptime WALK_FL = 0.25
comptime WALK_FR = 0.75
comptime WALK_HL = 0.0
comptime WALK_HR = 0.5
# The share of the stride a foot is on the ground.
comptime DUTY = 0.7


def is_quadruped(rig: Rig) -> Bool:
    """Return True if a rig has the standard quadruped legs.

    Args:
        rig: The rig.

    Returns:
        Whether it has both shoulders, both hips and a neck.
    """
    var count = 0
    for name in [
        String("shoulderL"),
        "shoulderR",
        "hipL",
        "hipR",
        "wristL",
        "hockL",
    ]:  # pragma: no branch
        count += Int(rig.find_joint(name) >= 0)
    return count == 6


def foot_offset(phase: Float64, stride: Float64, lift: Float64) -> V3:
    """Return where a foot is, from its bind place, at one phase.

    Args:
        phase: The foot's own phase in `[0, 1)`: zero is touch-down.
        stride: How far the foot travels in one stride, in meters.
        lift: How high it lifts in the swing, in meters.

    Returns:
        The offset: forward along z, up along y.
    """
    var stance = phase < DUTY
    var s = phase / DUTY
    var w = (phase - DUTY) / (1.0 - DUTY)
    # Planted, the foot moves back at a steady pace. In the swing it eases
    # forward and lifts in a smooth arch.
    var ease = smoothstep(0.0, 1.0, w)
    var z = stride * (0.5 - s) if stance else stride * (ease - 0.5)
    var y = 0.0 if stance else lift * sin(pi * w)
    return V3(0.0, y, z)


def _angle(v: V3) -> Float64:
    # The angle of a vector about +x, in the y-z plane.
    return atan2(v.z, v.y)


def solve_two_bone(
    root: V3, mid: V3, end: V3, target: V3
) -> Tuple[Float64, Float64]:
    """Return the turns about +x that bring a two-bone chain to a target.

    The chain bends the way it bends in bind pose. A target out of reach
    straightens the chain toward it.

    Args:
        root: The chain's root joint, in bind pose.
        mid: Its middle joint, in bind pose.
        end: Its end joint, in bind pose.
        target: Where the end joint must go.

    Returns:
        The upper bone's turn, and the lower bone's turn relative to the
        upper, in radians.
    """
    var a = mid - root
    var b = end - mid
    var la = sqrt(a.y * a.y + a.z * a.z)
    var lb = sqrt(b.y * b.y + b.z * b.z)
    var t = target - root
    var reach = min(sqrt(t.y * t.y + t.z * t.z), (la + lb) * 0.9999)
    reach = max(reach, abs(la - lb) * 1.0001 + 1e-9)
    # The bind bend: which side of the root-to-end line the middle lies.
    var e = end - root
    var bend = -1.0 if (e.y * a.z - e.z * a.y) >= 0.0 else 1.0
    var cos_root = (la * la + reach * reach - lb * lb) / (2.0 * la * reach)
    var at_root = acos(max(-1.0, min(1.0, cos_root)))
    var upper = _angle(t) - bend * at_root
    var upper_dir = V3(0.0, cos(upper), sin(upper))
    var new_mid = root + upper_dir * la
    var lower = _angle(target - new_mid)
    var turn_upper = upper - _angle(a)
    var turn_lower = lower - _angle(b) - turn_upper
    return (turn_upper, turn_lower)


def _leg(
    mut pose: Pose,
    rig: Rig,
    side: String,
    front: Bool,
    phase: Float64,
    stride: Float64,
    lift: Float64,
) raises:
    var root = String("shoulder") if front else String("hip")
    var mid = String("elbow") if front else String("knee")
    var end = String("wrist") if front else String("hock")
    var upper = String("humerus") if front else String("femur")
    var lower = String("radius") if front else String("tibia")
    var foot = String("metacarpus") if front else String("metatarsus")
    var r = rig.j(root + side)
    var m = rig.j(mid + side)
    var e = rig.j(end + side)
    var offset = foot_offset(phase, stride, lift)
    var turns = solve_two_bone(r, m, e, e + offset)
    var x = V3(1.0, 0.0, 0.0)
    pose.turn(rig, upper + side, x, turns[0])
    pose.turn(rig, lower + side, x, turns[1])
    # The lower foot keeps its bind attitude, and curls as it lifts.
    var curl = 0.6 * sin(pi * max(0.0, (phase - DUTY) / (1.0 - DUTY)))
    pose.turn(
        rig,
        foot + side,
        x,
        -turns[0] - turns[1] + curl * (1.0 if front else -1.0) * 0.5,
    )


def walk_pose(
    rig: Rig, phase: Float64, froude: Float64 = WALK_FROUDE
) raises -> Pose:
    """Return the walk at one phase of the stride.

    The stride is the one dynamic similarity gives the hip height at
    the Froude number: `2.3 Fr^0.3 h`. Each foot is planted for `DUTY`
    of it, so it sweeps back that share of the stride under the body.
    See `extensions/anatomy/locomotion.mojo`. A rig without the standard
    quadruped legs gets its bind pose.

    Args:
        rig: The animal's rig, in meters.
        phase: How far through the stride, in `[0, 1)`. It wraps.
        froude: The walk's Froude number. 0.25 is a comfortable walk.

    Returns:
        The pose.

    Raises:
        Error: If the rig has quadruped legs but lacks a bone they need,
            or the Froude number is not positive.
    """
    var pose = Pose(len(rig.bones))
    if not is_quadruped(rig):
        return pose^
    var p = (
        phase - Float64(Int(phase)) if phase
        >= 0.0 else phase - Float64(Int(phase)) + 1.0
    )
    var hip = rig.j("hipL").y
    var cycle = stride_length(froude, Length(Float32(hip), METER))
    var stride = DUTY * Float64(cycle.to(METER))
    var lift = 0.11 * hip
    _leg(pose, rig, "L", True, _wrap(p + WALK_FL), stride, lift)
    _leg(pose, rig, "R", True, _wrap(p + WALK_FR), stride, lift)
    _leg(pose, rig, "L", False, _wrap(p + WALK_HL), stride, lift)
    _leg(pose, rig, "R", False, _wrap(p + WALK_HR), stride, lift)
    # The back bobs twice a stride, lowest as each hind foot takes the
    # weight, and the tail swings once.
    var bob = 0.012 * hip * cos(4.0 * pi * p)
    pose.root.t = V3(0.0, bob, 0.0)
    pose.turn(rig, "neck2", V3(1.0, 0.0, 0.0), 0.04 * sin(4.0 * pi * p))
    for i in range(len(rig.bones)):  # pragma: no branch
        var name = rig.bones[i].name
        if name.startswith("tail"):
            pose.turn(rig, name, V3(0.0, 1.0, 0.0), 0.06 * sin(2.0 * pi * p))
    return pose^


def _wrap(x: Float64) -> Float64:
    return x - Float64(Int(x))


def spine_count(rig: Rig) -> Int:
    """Return how many bones the rig's `spine0`, `spine1`, ... chain has.

    Args:
        rig: The rig.

    Returns:
        The length of the chain. Zero for a rig without one.
    """
    var n = 0
    for i in range(len(rig.bones)):
        n += Int(rig.bones[i].name == "spine" + String(n))
    return n


def undulate_pose(
    rig: Rig, phase: Float64, waves: Float64 = 1.5
) raises -> Pose:
    """Return a lateral undulation at one phase: a snake's slither, or a
    fish's swim.

    A sine wave travels down the `spine` chain, from head to tail. Each
    bone turns about the vertical by the wave's curvature there, so the
    body bends into S curves. The wave grows toward the tail, as an eel's
    and a trout's do. A rig without a spine chain gets its bind pose.

    Args:
        rig: The animal's rig.
        phase: How far through the cycle, in `[0, 1)`. It wraps.
        waves: How many whole waves the body holds.

    Returns:
        The pose.

    Raises:
        Error: If the rig lacks a bone of its own chain.
    """
    var pose = Pose(len(rig.bones))
    var n = spine_count(rig)
    var up = V3(0.0, 1.0, 0.0)
    for i in range(n):
        var t = Float64(i) / Float64(n)
        var bend = 2.0 * pi * waves / Float64(n)
        var angle = (
            bend * (0.35 + 0.65 * t) * cos(2.0 * pi * (waves * t - phase))
        )
        pose.turn(rig, "spine" + String(i), up, angle)
    return pose^
