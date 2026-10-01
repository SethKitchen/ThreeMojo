# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The joints a game humanoid bends at, placed on one person's anatomy.

Nineteen joints make a skeleton for animation: the hips, two joints of
the spine, the neck and the head; each arm's shoulder, elbow and wrist;
each leg's hip, knee, ankle and the ball of the foot. Each joint is a
bone that turns the skin beyond it.

The joints stand where the anatomy puts them, in the pelvis frame:

- The hips are the frame's origin, between the two hip joints.
- The neck is the seventh cervical vertebra and the head the first, the
  atlas, where the skull nods.
- A shoulder, an elbow and a wrist are the arm frame's own.
- A hip is the femoral head, a knee the leg frame's origin at the joint
  line, an ankle the tibial plafond.
- The spine's two joints lie a third and two thirds of the way from the
  hips to the neck.

Where no bone of the anatomy marks a joint, the skin does: the ball of
the foot lies seven tenths of the way from the ankle to the toes' tip,
just above the sole.

This is not a three.js port. See Extensions.

    var rig = humanoid_rig(spec, skin)
    var knee = rig.at(RIGHT_SHIN)
"""

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.arm.frame import arm_muscle_dimensions
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3


@fieldwise_init
struct Joint(Equatable, ImplicitlyCopyable, Writable):
    """One joint of a game humanoid's skeleton.

    The type stops a bare integer at compile time. A value that is not a
    named joint is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named joint."""
        return self.value >= 0 and self.value < JOINT_COUNT

    def side(self) -> Int:
        """Return plus one for a joint of the right side, minus one for
        the left, and zero for one on the midline."""
        if self.value >= RIGHT_UPPER_ARM.value and (
            self.value <= RIGHT_HAND.value
        ):
            return 1
        if self.value >= LEFT_UPPER_ARM.value and self.value <= LEFT_HAND.value:
            return -1
        if self.value >= RIGHT_THIGH.value and self.value <= RIGHT_TOES.value:
            return 1
        if self.value >= LEFT_THIGH.value and self.value <= LEFT_TOES.value:
            return -1
        return 0


comptime HIPS = Joint(0)
comptime SPINE = Joint(1)
comptime CHEST = Joint(2)
comptime NECK = Joint(3)
comptime HEAD = Joint(4)
comptime RIGHT_UPPER_ARM = Joint(5)
comptime RIGHT_FOREARM = Joint(6)
comptime RIGHT_HAND = Joint(7)
comptime LEFT_UPPER_ARM = Joint(8)
comptime LEFT_FOREARM = Joint(9)
comptime LEFT_HAND = Joint(10)
comptime RIGHT_THIGH = Joint(11)
comptime RIGHT_SHIN = Joint(12)
comptime RIGHT_FOOT = Joint(13)
comptime RIGHT_TOES = Joint(14)
comptime LEFT_THIGH = Joint(15)
comptime LEFT_SHIN = Joint(16)
comptime LEFT_FOOT = Joint(17)
comptime LEFT_TOES = Joint(18)
comptime JOINT_COUNT = 19
# The ball of the foot: how far from the ankle toward the toes' tip, and
# how far above the sole, in template centimeters.
comptime BALL_ALONG = Float32(0.7)
comptime BALL_RISE = Float32(2.0)
# How far from the wrist a fingertip is sought, in template centimeters.
comptime HAND_REACH = Float32(24.0)


def joint_label(joint: Joint) -> String:
    """Return the name of `joint`, as a glTF node or a bone is named.

    Args:
        joint: A joint, named or not.

    Returns:
        Its name, as `"hips"` or `"rightShin"`, or `"joint"` when it is not
        named.
    """
    var names: List[String] = [
        "hips",
        "spine",
        "chest",
        "neck",
        "head",
        "rightUpperArm",
        "rightForearm",
        "rightHand",
        "leftUpperArm",
        "leftForearm",
        "leftHand",
        "rightThigh",
        "rightShin",
        "rightFoot",
        "rightToes",
        "leftThigh",
        "leftShin",
        "leftFoot",
        "leftToes",
    ]
    if not joint.is_valid():
        return "joint"
    return names[joint.value]


def named_joints() -> List[Joint]:
    """Return every joint, each after its parent.

    Returns:
        `HIPS` through `LEFT_TOES`.
    """
    var all = List[Joint]()
    for value in range(JOINT_COUNT):  # pragma: no branch
        all.append(Joint(value))
    return all^


def joint_parent(joint: Joint) raises -> Joint:
    """Return the joint `joint` hangs from.

    Args:
        joint: A named joint.

    Returns:
        Its parent. `HIPS`, the root, is its own.

    Raises:
        Error: If `joint` is not named.
    """
    if not joint.is_valid():
        raise Error("A joint must be a named joint")
    var parents: List[Int] = [
        0,
        0,
        1,
        2,
        3,
        2,
        5,
        6,
        2,
        8,
        9,
        0,
        11,
        12,
        13,
        0,
        15,
        16,
        17,
    ]
    return Joint(parents[joint.value])


struct HumanoidRig(Copyable, Movable):
    """Where each joint of one person stands at rest, and where the
    bone that turns from it ends, in the pelvis frame, in meters."""

    var joints: List[Vector3]
    var ends: List[Vector3]
    # How tall the person stands, in meters.
    var stature: Float32

    def __init__(
        out self,
        var joints: List[Vector3],
        var ends: List[Vector3],
        stature: Float32,
    ) raises:
        """Hold a rig.

        Args:
            joints: One rest place per joint, in the order of the joints.
            ends: Where each joint's bone ends.
            stature: Standing height, in meters.

        Raises:
            Error: If either list is not one point per joint.
        """
        if len(joints) != JOINT_COUNT or len(ends) != JOINT_COUNT:
            raise Error("A rig needs one place per joint")
        self.joints = joints^
        self.ends = ends^
        self.stature = stature

    def at(self, joint: Joint) raises -> Vector3:
        """Return where a joint stands at rest.

        Args:
            joint: A named joint.

        Returns:
            Its place in the pelvis frame, in meters.

        Raises:
            Error: If `joint` is not named.
        """
        if not joint.is_valid():
            raise Error("A joint must be a named joint")
        return self.joints[joint.value]

    def local(self, joint: Joint) raises -> Vector3:
        """Return where a joint stands from its parent, at rest: the
        position its bone takes in the scene.

        Args:
            joint: A named joint.

        Returns:
            The offset, in meters. The hips' is their place.

        Raises:
            Error: If `joint` is not named.
        """
        if joint == HIPS:
            return self.at(HIPS)
        return self.at(joint) - self.at(joint_parent(joint))


def _mirrored(p: Vector3, sign: Float32) -> Vector3:
    """Return a right-side point, or its mirror on the left for a
    negative `sign`."""
    return Vector3(p.x * sign, p.y, p.z)


def _fingertip(
    points: List[Vector3], wrist: Vector3, sign: Float32, hand: Float32
) -> Vector3:
    """Return the fingertip: the point of the skin farthest from the
    wrist on one side of the midline, plus x for a positive `sign`, that
    lies below the wrist and within a hand's length of it."""
    var best = wrist
    var reach = Float32(-1)
    for p in points:  # pragma: no branch
        if p.x * sign <= 0 or p.y > wrist.y:
            continue
        var d = (p - wrist).length()
        if d > hand:
            continue
        if d > reach:
            reach = d
            best = p
    return best


def humanoid_rig(
    spec: HumanoidSpec,
    skin: BufferGeometry,
) raises -> HumanoidRig:
    """Place the joints on one person.

    Args:
        spec: Standing height, osteological sex, athleticism and genome.
        skin: The person's skin in the pelvis frame, hands and feet
            included: it marks the crown, the fingertips and the toes.

    Returns:
        The rig.

    Raises:
        Error: If `spec` is refused, or the skin has no positions.
    """
    var pelvis = assemble_pelvis(spec)
    var arms = arm_muscle_dimensions(spec)
    var head = head_muscle_dimensions(spec).head.copy()
    # One template centimeter on this person, in meters.
    var cm = Float32(spec.stature.value) / Float32(182.88)
    ref placed = skin.attribute_view(String(POSITION))
    var points = List[Vector3](capacity=placed.count())
    var crown = Float32(-1e9)
    var sole = Float32(1e9)
    for v in range(placed.count()):  # pragma: no branch
        var p = placed.vector3(v)
        points.append(p)
        crown = max(crown, p.y)
        sole = min(sole, p.y)
    var joints = List[Vector3](length=JOINT_COUNT, fill=Vector3(0, 0, 0))
    var ends = List[Vector3](length=JOINT_COUNT, fill=Vector3(0, 0, 0))
    var neck = head.centers[6]
    var atlas = head.centers[0]
    var hips = Vector3(0, 0, neck.z)
    joints[HIPS.value] = hips
    joints[SPINE.value] = hips + (neck - hips) * Float32(1.0 / 3.0)
    joints[CHEST.value] = hips + (neck - hips) * Float32(2.0 / 3.0)
    joints[NECK.value] = neck
    joints[HEAD.value] = atlas
    ends[HIPS.value] = joints[SPINE.value]
    ends[SPINE.value] = joints[CHEST.value]
    ends[CHEST.value] = neck
    ends[NECK.value] = atlas
    ends[HEAD.value] = Vector3(atlas.x, crown, atlas.z)
    var frame = arms.arm.frame
    for s in range(2):  # pragma: no branch
        var side = RIGHT if s == 0 else LEFT
        var sign = Float32(1) if s == 0 else Float32(-1)
        var upper = RIGHT_UPPER_ARM.value if s == 0 else LEFT_UPPER_ARM.value
        var shoulder = _mirrored(frame.shoulder, sign)
        var elbow = _mirrored(frame.elbow, sign)
        var wrist = _mirrored(frame.wrist, sign)
        joints[upper] = shoulder
        joints[upper + 1] = elbow
        joints[upper + 2] = wrist
        ends[upper] = elbow
        ends[upper + 1] = wrist
        ends[upper + 2] = _fingertip(points, wrist, sign, HAND_REACH * cm)
        var thigh = RIGHT_THIGH.value if s == 0 else LEFT_THIGH.value
        var knee = pelvis.leg_origin(side)
        var ankle = knee + assemble_leg(spec, side).ankle_center()
        # The toes' tip: the skin's farthest forward on this side, low.
        var tip = ankle
        for p in points:  # pragma: no branch
            if p.x * sign > 0 and p.y < ankle.y and p.z > tip.z:
                tip = p
        var ball = Vector3(
            ankle.x + (tip.x - ankle.x) * BALL_ALONG,
            sole + BALL_RISE * cm,
            ankle.z + (tip.z - ankle.z) * BALL_ALONG,
        )
        joints[thigh] = pelvis.hip_center(side)
        joints[thigh + 1] = knee
        joints[thigh + 2] = ankle
        joints[thigh + 3] = ball
        ends[thigh] = knee
        ends[thigh + 1] = ankle
        ends[thigh + 2] = ball
        ends[thigh + 3] = Vector3(tip.x, sole + BALL_RISE * cm, tip.z)
    return HumanoidRig(joints^, ends^, Float32(spec.stature.value))
