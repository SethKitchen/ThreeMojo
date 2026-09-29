# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bones of the wrist, the hand and the fingers, as implicit solids.

The set is the eight carpals in two rows, the five metacarpals and the
fourteen phalanges: a proximal and a distal phalanx in the thumb, and a
proximal, a middle and a distal phalanx in each finger. The hand hangs
from the radiocarpal joint in the anatomical position: the palm faces
forward and the fingers point down, a little apart. The thumb stands
forward of the palm and out to the side.

Each finger is a chain of joint centers; see `finger_joints`. A bone
spans two joints of its chain and stops short of each, which leaves the
joint space. The middle finger reaches about 20 cm below the wrist on
the six-foot template. The values are template parameters. They are
not a cited osteometric table.

    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var d = hand_bone_distance(dims, CAPITATE, RIGHT, dims.frame.wrist)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmDimensions, ArmFrame
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
)
from math.vector3 import Vector3

# Cortical shell, as a ratio of stature.
comptime HAND_SHELL = Float32(0.0006)
# The gap each bone leaves at a joint, in template cm.
comptime JOINT_GAP = Float32(0.08)


@fieldwise_init
struct HandBone(Equatable, ImplicitlyCopyable, Writable):
    """Which bone of the wrist, the hand or the fingers a caller asks
    for.

    The carpals come first, then the metacarpals, then the proximal,
    middle and distal phalanges, each run from the thumb out. The type
    stops a bare integer at compile time. A value that is not one of the
    named bones is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named hand bone."""
        if self.value < 0:
            return False
        return self.value <= DISTAL_PHALANX_5.value


comptime SCAPHOID = HandBone(0)
comptime LUNATE = HandBone(1)
comptime TRIQUETRUM = HandBone(2)
comptime PISIFORM = HandBone(3)
comptime TRAPEZIUM = HandBone(4)
comptime TRAPEZOID = HandBone(5)
comptime CAPITATE = HandBone(6)
comptime HAMATE = HandBone(7)
comptime METACARPAL_1 = HandBone(8)
comptime METACARPAL_2 = HandBone(9)
comptime METACARPAL_3 = HandBone(10)
comptime METACARPAL_4 = HandBone(11)
comptime METACARPAL_5 = HandBone(12)
comptime PROXIMAL_PHALANX_1 = HandBone(13)
comptime PROXIMAL_PHALANX_2 = HandBone(14)
comptime PROXIMAL_PHALANX_3 = HandBone(15)
comptime PROXIMAL_PHALANX_4 = HandBone(16)
comptime PROXIMAL_PHALANX_5 = HandBone(17)
# The thumb has no middle phalanx.
comptime MIDDLE_PHALANX_2 = HandBone(18)
comptime MIDDLE_PHALANX_3 = HandBone(19)
comptime MIDDLE_PHALANX_4 = HandBone(20)
comptime MIDDLE_PHALANX_5 = HandBone(21)
comptime DISTAL_PHALANX_1 = HandBone(22)
comptime DISTAL_PHALANX_2 = HandBone(23)
comptime DISTAL_PHALANX_3 = HandBone(24)
comptime DISTAL_PHALANX_4 = HandBone(25)
comptime DISTAL_PHALANX_5 = HandBone(26)


@fieldwise_init
struct Finger(Equatable, ImplicitlyCopyable, Writable):
    """Which digit of the hand a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the five digits is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the five digits."""
        if self.value < 0:
            return False
        return self.value <= LITTLE.value


comptime THUMB = Finger(0)
comptime INDEX = Finger(1)
comptime MIDDLE = Finger(2)
comptime RING = Finger(3)
comptime LITTLE = Finger(4)


def finger_label(finger: Finger) -> String:
    """Return the error-text name of `finger`.

    Args:
        finger: A digit, named or not.

    Returns:
        `"thumb"`, `"index finger"`, `"middle finger"`, `"ring finger"`
        or `"little finger"`, or `"finger"` when it is not named.
    """
    if finger == THUMB:
        return "thumb"
    if finger == INDEX:
        return "index finger"
    if finger == MIDDLE:
        return "middle finger"
    if finger == RING:
        return "ring finger"
    if finger == LITTLE:
        return "little finger"
    return "finger"


def named_fingers() -> List[Finger]:
    """Return the five digits, thumb first.

    Returns:
        The thumb, then the index, middle, ring and little fingers.
    """
    var out = List[Finger]()
    for index in range(LITTLE.value + 1):  # pragma: no branch
        out.append(Finger(index))
    return out^


def hand_bone_label(part: HandBone) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hand bone, named or not.

    Returns:
        A carpal's name, or a label such as `"metacarpal 3"` or
        `"distal phalanx 1"`, or `"hand bone"` when `part` is not named.
    """
    if not part.is_valid():
        return "hand bone"
    var carpals = List[String]()
    carpals.append("scaphoid")
    carpals.append("lunate")
    carpals.append("triquetrum")
    carpals.append("pisiform")
    carpals.append("trapezium")
    carpals.append("trapezoid")
    carpals.append("capitate")
    carpals.append("hamate")
    if part.value < METACARPAL_1.value:
        return carpals[part.value]
    if part.value < PROXIMAL_PHALANX_1.value:
        return "metacarpal " + String(part.value - METACARPAL_1.value + 1)
    if part.value < MIDDLE_PHALANX_2.value:
        return "proximal phalanx " + String(
            part.value - PROXIMAL_PHALANX_1.value + 1
        )
    if part.value < DISTAL_PHALANX_1.value:
        return "middle phalanx " + String(
            part.value - MIDDLE_PHALANX_2.value + 2
        )
    return "distal phalanx " + String(part.value - DISTAL_PHALANX_1.value + 1)


def named_hand_bones() -> List[HandBone]:
    """Return every named hand bone in a stable order.

    Returns:
        The carpals, the metacarpals, then the phalanges.
    """
    var parts = List[HandBone]()
    for index in range(DISTAL_PHALANX_5.value + 1):  # pragma: no branch
        parts.append(HandBone(index))
    return parts^


def finger_bones(finger: Finger) raises -> List[HandBone]:
    """Return the bones of one digit, from the wrist out.

    Args:
        finger: A named digit.

    Returns:
        The metacarpal and the phalanges: three bones in the thumb and
        four in a finger.

    Raises:
        Error: If `finger` is not named.
    """
    if not finger.is_valid():
        raise Error("A finger must be the thumb or a named finger")
    var k = finger.value
    var out = List[HandBone]()
    out.append(HandBone(METACARPAL_1.value + k))
    out.append(HandBone(PROXIMAL_PHALANX_1.value + k))
    if finger != THUMB:
        out.append(HandBone(MIDDLE_PHALANX_2.value + k - 1))
    out.append(HandBone(DISTAL_PHALANX_1.value + k))
    return out^


def _digit_table(finger: Finger) -> List[Float32]:
    """Return one digit's authored values in template cm.

    The base of the metacarpal, the direction of the digit, the lengths
    of the metacarpal and the three phalanges, and the radius scale.
    """
    # fmt: off
    if finger == THUMB:
        return floats(2.5, -3.2, 1.0, 0.25, -0.85, 0.45, 4.3, 3.0, 0, 2.3, 1.15)
    if finger == INDEX:
        return floats(1.05, -4.1, 0.3, 0.06, -1, 0.03, 6.5, 4.1, 2.4, 1.7, 1.0)
    if finger == MIDDLE:
        return floats(0.0, -4.2, 0.3, 0.0, -1, 0.03, 6.2, 4.5, 2.7, 1.9, 1.02)
    if finger == RING:
        return floats(-1.15, -4.0, 0.2, -0.06, -1, 0.03, 5.5, 4.2, 2.6, 1.8, 0.97)
    return floats(-2.1, -3.8, 0.1, -0.13, -1, 0.03, 5.0, 3.4, 1.9, 1.6, 0.88)
    # fmt: on


def finger_joints(
    dimensions: ArmDimensions, finger: Finger
) raises -> List[Vector3]:
    """Return the joint centers of one right digit, from the wrist out.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        finger: A named digit.

    Returns:
        The carpometacarpal joint, the knuckle, one interphalangeal
        joint in the thumb or two in a finger, and the tip of the
        distal phalanx, in meters.

    Raises:
        Error: If `finger` is not named.
    """
    if not finger.is_valid():
        raise Error("A finger must be the thumb or a named finger")
    var f = dimensions.frame
    var row = _digit_table(finger)
    var d = Vector3(row[3], row[4], row[5])
    d.normalize()
    var p = Vector3(row[0], row[1], row[2])
    var out = List[Vector3]()
    out.append(f.hand(p.x, p.y, p.z))
    for k in range(4):  # pragma: no branch
        var length = row[6 + k]
        if length == 0:
            continue
        p = p + d * length
        out.append(f.hand(p.x, p.y, p.z))
    return out^


def finger_scale(finger: Finger) raises -> Float32:
    """Return how much thicker one digit's bones are than a finger's.

    Args:
        finger: A named digit.

    Returns:
        A ratio near one: above it for the thumb, below it for the
        little finger.

    Raises:
        Error: If `finger` is not named.
    """
    if not finger.is_valid():
        raise Error("A finger must be the thumb or a named finger")
    return _digit_table(finger)[10]


def hand_bone_field(
    dimensions: ArmDimensions, part: HandBone, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one hand bone.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: A named bone.
        side: `RIGHT` or `LEFT`.

    Returns:
        The bone's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A hand bone must be a named carpal, metacarpal or phalanx")
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var f = dimensions.frame
    var sweeps = List[Sweep]()
    if part.value < METACARPAL_1.value:
        _carpal(sweeps, f, part)
    else:
        _long_bone(sweeps, dimensions, part)
    return SweepField(
        sweeps^, List[Dome](), side, f.cm(0.12), f.cm(0.02), 0.003
    )


def hand_bone_distance(
    dimensions: ArmDimensions, part: HandBone, side: BodySide, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: Which bone to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return hand_bone_field(dimensions, part, side).distance(point)


def bone_finger(part: HandBone) raises -> Finger:
    """Return the digit a metacarpal or a phalanx belongs to.

    Args:
        part: A named metacarpal or phalanx.

    Returns:
        Its digit.

    Raises:
        Error: If `part` is not named, or is a carpal.
    """
    if not part.is_valid() or part.value < METACARPAL_1.value:
        raise Error("Only a metacarpal or a phalanx belongs to a finger")
    if part.value < PROXIMAL_PHALANX_1.value:
        return Finger(part.value - METACARPAL_1.value)
    if part.value < MIDDLE_PHALANX_2.value:
        return Finger(part.value - PROXIMAL_PHALANX_1.value)
    if part.value < DISTAL_PHALANX_1.value:
        return Finger(part.value - MIDDLE_PHALANX_2.value + 1)
    return Finger(part.value - DISTAL_PHALANX_1.value)


def _carpal(mut sweeps: List[Sweep], f: ArmFrame, part: HandBone):
    """Append one carpal: a knob, or two for the longer ones."""
    # Each row: two station centers and their radii, in template cm.
    var row: List[Float32]
    if part == SCAPHOID:
        row = floats(1.9, -0.7, 0.3, 0.7, 1.3, -1.6, 0.5, 0.62)
    elif part == LUNATE:
        row = floats(0.2, -0.8, 0.2, 0.78, 0.2, -1.0, 0.2, 0.78)
    elif part == TRIQUETRUM:
        row = floats(-1.2, -1.0, -0.1, 0.66, -1.4, -1.3, -0.1, 0.62)
    elif part == PISIFORM:
        row = floats(-1.5, -1.3, 0.85, 0.48, -1.5, -1.4, 0.95, 0.46)
    elif part == TRAPEZIUM:
        row = floats(1.9, -2.5, 0.6, 0.7, 2.2, -3.0, 0.85, 0.66)
    elif part == TRAPEZOID:
        row = floats(0.95, -2.6, 0.35, 0.6, 0.95, -3.1, 0.35, 0.58)
    elif part == CAPITATE:
        row = floats(0.0, -2.2, 0.25, 0.72, 0.0, -3.3, 0.25, 0.7)
    else:
        row = floats(-1.3, -2.3, 0.1, 0.68, -1.4, -3.2, 0.1, 0.68)
    var bone = Sweep(Vector3(1, 0, 0))
    bone.round(f.hand(row[0], row[1], row[2]), f.cm(row[3]))
    bone.round(f.hand(row[4], row[5], row[6]), f.cm(row[7]))
    sweeps.append(bone^)
    if part == HAMATE:
        # The hook of the hamate, forward into the palm.
        var hook = Sweep(Vector3(1, 0, 0))
        hook.round(f.hand(-1.5, -2.9, 0.6), f.cm(0.35))
        hook.round(f.hand(-1.6, -3.1, 1.1), f.cm(0.3))
        sweeps.append(hook^)


def _long_bone(
    mut sweeps: List[Sweep], dimensions: ArmDimensions, part: HandBone
) raises:
    """Append one metacarpal or phalanx between two joints of its digit."""
    var f = dimensions.frame
    var finger = bone_finger(part)
    var joints = finger_joints(dimensions, finger)
    var bones = finger_bones(finger)
    var at = 0
    for index in range(len(bones)):  # pragma: no branch
        if bones[index] == part:
            at = index
    var a = joints[at]
    var b = joints[at + 1]
    var d = b - a
    d.normalize()
    var s = finger_scale(finger)
    # Base, shaft and head radii in template cm by kind of bone.
    var radii: List[Float32]
    if part.value < PROXIMAL_PHALANX_1.value:
        radii = floats(0.6, 0.42, 0.52)
    elif part.value < MIDDLE_PHALANX_2.value:
        radii = floats(0.52, 0.37, 0.42)
    elif part.value < DISTAL_PHALANX_1.value:
        radii = floats(0.42, 0.32, 0.35)
    else:
        radii = floats(0.36, 0.25, 0.3)
    var base = f.cm(radii[0] * s)
    var shaft = f.cm(radii[1] * s)
    var head = f.cm(radii[2] * s)
    var gap = f.cm(JOINT_GAP)
    var bone = Sweep(Vector3(1, 0, 0))
    bone.round(a + d * (base + gap), base)
    bone.round(a + (b - a) * 0.5, shaft)
    var end = b - d * (head + gap)
    if part.value >= DISTAL_PHALANX_1.value:
        end = b - d * head
    bone.round(end, head)
    sweeps.append(bone^)
