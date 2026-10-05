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

from extensions.anatomy.locomotion import (
    WALK_FROUDE,
    stride_frequency,
    stride_length,
)
from extensions.animals.rig import Pose, Rig
from extensions.sdf.vector import (
    V3,
    smoothstep,
    length,
)
from std.math import atan2, acos, cos, floor, isfinite, pi, sin, sqrt
from units.si import METER, SECOND, Duration, Length

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
) raises -> Tuple[Float64, Float64]:
    """Return the turns about +x that bring a two-bone chain to a target.

    The chain bends the way it bends in bind pose. A target out of reach
    straightens the chain toward it. The returned turns reach the nearest
    point in the chain's reachable annulus.

    Args:
        root: The chain's root joint, in bind pose.
        mid: Its middle joint, in bind pose.
        end: Its end joint, in bind pose.
        target: Where the end joint must go.

    Returns:
        The upper bone's turn, and the lower bone's turn relative to the
        upper, in radians.

    Raises:
        Error: If a point is not finite, a link has no length in the
            y-z plane, or the solution is outside the numeric range.
    """
    for p in [root, mid, end, target]:  # pragma: no branch
        if not (isfinite(p.x) and isfinite(p.y) and isfinite(p.z)):
            raise Error("A leg point must be finite")
    var a = mid - root
    var b = end - mid
    var la = length(V3(0.0, a.y, a.z))
    var lb = length(V3(0.0, b.y, b.z))
    if not (la > 0.0 and lb > 0.0 and isfinite(la + lb)):
        raise Error("A leg link must have finite positive planar length")
    var t = target - root
    var distance = length(V3(0.0, t.y, t.z))
    if not isfinite(distance):
        raise Error("A leg target displacement must be finite")
    var reach = max(abs(la - lb), min(distance, la + lb))
    # Equal links can fold exactly onto their root. A small relative
    # radius selects a stable fold direction without dividing by zero.
    reach = max(reach, (la + lb) * 1e-12)
    var direction = V3(0.0, -1.0, 0.0)
    if distance > 0.0:
        direction = V3(0.0, t.y / distance, t.z / distance)
    var projected = root + direction * reach
    # The bind bend: which side of the root-to-end line the middle lies.
    var e = end - root
    var scale = max(la, max(lb, reach))
    var bend_cross = (e.y / scale) * (a.z / scale) - (e.z / scale) * (
        a.y / scale
    )
    var bend = -1.0 if bend_cross >= 0.0 else 1.0
    var na = la / scale
    var nb = lb / scale
    var nr = reach / scale
    var denominator = 2.0 * na * nr
    if not denominator > 0.0:
        raise Error("A leg length ratio is outside the supported numeric range")
    var cos_root = (na * na + nr * nr - nb * nb) / denominator
    var at_root = acos(max(-1.0, min(1.0, cos_root)))
    var upper = _angle(direction) - bend * at_root
    var upper_dir = V3(0.0, cos(upper), sin(upper))
    var new_mid = root + upper_dir * la
    var lower_dir = projected - new_mid
    # The solution keeps the root's x, which was checked finite above.
    for p in [projected, new_mid, lower_dir]:  # pragma: no branch
        if not (isfinite(p.y) and isfinite(p.z)):
            raise Error("A leg solution must fit finite coordinates")
    var lower = _angle(lower_dir)
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
    # The root bob moves the entire chain. Remove it from the local
    # target so the planted foot keeps its bind height in world space.
    var turns = solve_two_bone(r, m, e, e + offset - pose.root.t)
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


def _reach_along(span: Float64, perpendicular: Float64) -> Float64:
    # sqrt(span^2 - perpendicular^2), without squaring a world length.
    var ratio = perpendicular / span
    return span * sqrt(max(0.0, (1.0 - ratio) * (1.0 + ratio)))


def _walk_parameters(
    rig: Rig, froude: Float64
) raises -> Tuple[Float64, Float64]:
    # Bound one common stance sweep at the highest body position. All
    # four feet then move at one rate, with no clipping partway through
    # stance. The simple two-link rig cannot realize every target stride.
    var hip = rig.j("hipL").y
    var desired = DUTY * Float64(
        stride_length(froude, Length(Float32(hip), METER)).to(METER)
    )
    var bob = 0.012 * hip
    var lengths = List[Float64]()
    var inner = List[Float64]()
    var vertical = List[Float64]()
    var forward = List[Float64]()
    for front in [True, False]:  # pragma: no branch
        for side in [String("L"), String("R")]:  # pragma: no branch
            var r = rig.j(
                (String("shoulder") if front else String("hip")) + side
            )
            var m = rig.j((String("elbow") if front else String("knee")) + side)
            var e = rig.j((String("wrist") if front else String("hock")) + side)
            # Validate even when the final stride is zero.
            _ = solve_two_bone(r, m, e, e)
            var a = m - r
            var b = e - m
            var upper = length(V3(0.0, a.y, a.z))
            var lower = length(V3(0.0, b.y, b.z))
            var span = upper + lower
            var minimum = abs(upper - lower)
            inner.append(minimum)
            var dy = abs(e.y - r.y)
            lengths.append(span)
            vertical.append(dy)
            forward.append(abs(e.z - r.z))
            # Preserve reach at the bind forward offset before reserving
            # any motion for the stride.
            var room = _reach_along(span, forward[len(forward) - 1]) - dy
            bob = min(bob, max(0.0, room) * 0.5)
            if minimum > 0.0:
                var floor = _reach_along(minimum, forward[len(forward) - 1])
                bob = min(bob, max(0.0, dy - floor) * 0.5)
    var sweep = desired
    # Four legs.
    for i in range(len(lengths)):  # pragma: no branch
        var dy = vertical[i] + bob
        var z = _reach_along(lengths[i], dy)
        sweep = min(sweep, max(0.0, 2.0 * (z - forward[i])))
        # Unequal links cannot fold inside their inner radius. Reserve
        # the same clearance when the body reaches its lowest point.
        var low_y = max(0.0, vertical[i] - bob)
        if low_y < inner[i]:
            var nearest_z = _reach_along(inner[i], low_y)
            sweep = min(sweep, max(0.0, 2.0 * (forward[i] - nearest_z)))
    return (sweep, bob)


def walk_stride(rig: Rig, froude: Float64 = WALK_FROUDE) raises -> Length:
    """Return the reachable visual stride of the in-place walk.

    The stance sweep is `DUTY` times this length. It can be smaller than
    the dynamic-similarity reference because the two-link legs have a
    finite reach. This is a kinematic illustration, not a measured gait.

    Args:
        rig: The animal's rig, in meters.
        froude: The positive reference Froude number.

    Returns:
        The visual stride. Zero for a rig without quadruped legs.

    Raises:
        Error: If a quadruped leg is degenerate or a parameter is invalid.
    """
    if not is_quadruped(rig):
        return Length(0.0, METER)
    return Length(Float32(_walk_parameters(rig, froude)[0] / DUTY), METER)


def walk_pose_at(
    rig: Rig, elapsed: Duration, froude: Float64 = WALK_FROUDE
) raises -> Pose:
    """Sample the in-place walk at a physical time.

    Each animal uses its own hip-height reference frequency. The visual
    stride remains limited by the rig's reach; the reference speed is
    not an achieved or validated physical translation speed.

    Args:
        rig: The animal's rig, in meters.
        elapsed: Time from the start of the clip, in seconds.
        froude: The positive reference Froude number.

    Returns:
        The pose at this time. A non-quadruped keeps its bind pose.

    Raises:
        Error: If time is not finite or the walk parameters are invalid.
    """
    var seconds = Float64(elapsed.to(SECOND))
    if not isfinite(seconds):
        raise Error("Walk time must be finite")
    if not is_quadruped(rig):
        return Pose(len(rig.bones))
    var hip = Length(Float32(rig.j("hipL").y), METER)
    var frequency = Float64(stride_frequency(froude, hip).value)
    return walk_pose(rig, seconds * frequency, froude)


def walk_pose(
    rig: Rig, phase: Float64, froude: Float64 = WALK_FROUDE
) raises -> Pose:
    """Return the walk at one phase of the stride.

    The reference stride is `2.3 Fr^0.3 h`. `walk_stride` limits it to
    the common reach of all four legs. Each foot is planted for `DUTY`
    of the cycle. The body bob is compensated in each leg target.
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
            or a leg is degenerate, the phase is not finite, or the
            Froude number is not positive.
    """
    var pose = Pose(len(rig.bones))
    if not is_quadruped(rig):
        return pose^
    if not isfinite(phase):
        raise Error("Walk phase must be finite")
    var p = _wrap(phase)
    var hip = rig.j("hipL").y
    var parameters = _walk_parameters(rig, froude)
    var stride = parameters[0]
    var bob = parameters[1] * cos(4.0 * pi * p)
    pose.root.t = V3(0.0, bob, 0.0)
    var lift = 0.11 * hip
    _leg(pose, rig, "L", True, _wrap(p + WALK_FL), stride, lift)
    _leg(pose, rig, "R", True, _wrap(p + WALK_FR), stride, lift)
    _leg(pose, rig, "L", False, _wrap(p + WALK_HL), stride, lift)
    _leg(pose, rig, "R", False, _wrap(p + WALK_HR), stride, lift)
    # The back bobs twice a stride, lowest as each hind foot takes the
    # weight, and the tail swings once.
    pose.turn(rig, "neck2", V3(1.0, 0.0, 0.0), 0.04 * sin(4.0 * pi * p))
    for i in range(len(rig.bones)):  # pragma: no branch
        var name = rig.bones[i].name
        if name.startswith("tail"):
            pose.turn(rig, name, V3(0.0, 1.0, 0.0), 0.06 * sin(2.0 * pi * p))
    return pose^


def _wrap(x: Float64) -> Float64:
    return x - floor(x)


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
