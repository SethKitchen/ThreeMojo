# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named muscles and long tendons of the hand and the fingers.

The set is the hand's own muscles: the thenar group at the base of the
thumb, the hypothenar group at the base of the little finger, the
lumbricals, and the dorsal and palmar interossei between the
metacarpals. It also holds the long tendons the forearm sends to the
digits: the flexor tendons along the front of each finger, the flexor
pollicis longus along the thumb, and the extensor tendons along the
back.

A muscle is authored as station paths in the hand's frame; see
`extensions.humanoid.skeleton.arm.frame`. A tendon follows its digit's
joint chain from `finger_joints`, a little in front of or behind the
bones. Belly radii scale with athleticism; tendon radii do not. The
values are template parameters. They are not a cited cross-section
table.

    var dims = arm_muscle_dimensions(person)
    var d = hand_muscle_distance(dims, ADDUCTOR_POLLICIS, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmDimensions,
    ArmMuscleDimensions,
)
from extensions.humanoid.skeleton.arm.muscles.dimensions import paths_field
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    INDEX,
    LITTLE,
    THUMB,
    Finger,
    finger_joints,
    finger_scale,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
)
from math.vector3 import Vector3


@fieldwise_init
struct HandMuscle(Equatable, ImplicitlyCopyable, Writable):
    """Which named muscle or tendon group of the hand a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named hand muscle or tendon group."""
        if self.value < 0:
            return False
        return self.value <= THUMB_EXTENSOR_TENDONS.value


comptime ABDUCTOR_POLLICIS_BREVIS = HandMuscle(0)
comptime FLEXOR_POLLICIS_BREVIS = HandMuscle(1)
comptime OPPONENS_POLLICIS = HandMuscle(2)
comptime ADDUCTOR_POLLICIS = HandMuscle(3)
comptime ABDUCTOR_DIGITI_MINIMI = HandMuscle(4)
comptime FLEXOR_DIGITI_MINIMI = HandMuscle(5)
comptime OPPONENS_DIGITI_MINIMI = HandMuscle(6)
# The four lumbricals, drawn as one part.
comptime LUMBRICALS = HandMuscle(7)
# The four dorsal interossei, drawn as one part.
comptime DORSAL_INTEROSSEI = HandMuscle(8)
# The three palmar interossei, drawn as one part.
comptime PALMAR_INTEROSSEI = HandMuscle(9)
# The superficial and deep flexor tendons of the four fingers.
comptime FLEXOR_TENDONS = HandMuscle(10)
comptime FLEXOR_POLLICIS_LONGUS_TENDON = HandMuscle(11)
# The extensor tendons of the four fingers, with the extensor indicis
# and the extensor digiti minimi.
comptime EXTENSOR_TENDONS = HandMuscle(12)
# The long and short extensor tendons of the thumb.
comptime THUMB_EXTENSOR_TENDONS = HandMuscle(13)


def hand_muscle_label(part: HandMuscle) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hand muscle, named or not.

    Returns:
        A short American English label, or `"hand muscle"` when `part`
        is not named.
    """
    if not part.is_valid():
        return "hand muscle"
    var names = List[String]()
    names.append("abductor pollicis brevis")
    names.append("flexor pollicis brevis")
    names.append("opponens pollicis")
    names.append("adductor pollicis")
    names.append("abductor digiti minimi")
    names.append("flexor digiti minimi")
    names.append("opponens digiti minimi")
    names.append("lumbricals")
    names.append("dorsal interossei")
    names.append("palmar interossei")
    names.append("flexor tendons")
    names.append("flexor pollicis longus tendon")
    names.append("extensor tendons")
    names.append("thumb extensor tendons")
    return names[part.value]


def named_hand_muscles() -> List[HandMuscle]:
    """Return every named hand muscle and tendon group in a stable order.

    Returns:
        The thenar and hypothenar groups, the lumbricals, the
        interossei, then the long tendons.
    """
    var parts = List[HandMuscle]()
    for index in range(THUMB_EXTENSOR_TENDONS.value + 1):
        parts.append(HandMuscle(index))
    return parts^


def is_hand_tendon(part: HandMuscle) raises -> Bool:
    """Return True if `part` is a group of long tendons.

    Args:
        part: A named part.

    Returns:
        True for the four tendon groups, False for the hand's own
        muscles.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A hand muscle must be a named muscle or tendon group")
    return part.value >= FLEXOR_TENDONS.value


def _muscle_paths(part: HandMuscle) -> List[List[Float32]]:
    """Return the authored station paths of one of the hand's muscles.

    The layout is `arm_muscle_paths`'s, every station in the hand's
    frame.
    """
    var paths = List[List[Float32]]()
    # fmt: off
    if part == ABDUCTOR_POLLICIS_BREVIS:
        paths.append(floats(
            1, 0, 0,
            3, 1.9, -1.4, 1.6, 0.5, 0.5, 1,
            3, 3.0, -4.2, 2.6, 0.8, 0.6, 1,
            3, 3.9, -7.2, 3.3, 0.35, 0.3, 0,
        ))
    elif part == FLEXOR_POLLICIS_BREVIS:
        paths.append(floats(
            1, 0, 0,
            3, 1.2, -2.4, 1.7, 0.45, 0.45, 1,
            3, 2.3, -4.8, 2.5, 0.7, 0.6, 1,
            3, 3.3, -7.2, 3.3, 0.3, 0.3, 0,
        ))
    elif part == OPPONENS_POLLICIS:
        paths.append(floats(
            1, 0, 0,
            3, 1.9, -2.8, 1.5, 0.45, 0.45, 1,
            3, 2.9, -4.8, 2.2, 0.6, 0.5, 1,
            3, 3.6, -6.4, 2.4, 0.4, 0.35, 1,
        ))
    elif part == ADDUCTOR_POLLICIS:
        # The transverse head from the third metacarpal and the oblique
        # head from the capitate, to the base of the thumb.
        paths.append(floats(
            0, 0, 1,
            3, 0.0, -8.5, 0.95, 0.4, 1.0, 1,
            3, 1.8, -7.8, 1.9, 0.5, 0.9, 1,
            3, 3.0, -7.3, 2.9, 0.3, 0.4, 0,
        ))
        paths.append(floats(
            0, 0, 1,
            3, 0.3, -3.9, 1.1, 0.4, 0.8, 1,
            3, 1.6, -5.8, 1.8, 0.5, 0.9, 1,
            3, 3.0, -7.3, 2.9, 0.3, 0.4, 0,
        ))
    elif part == ABDUCTOR_DIGITI_MINIMI:
        paths.append(floats(
            1, 0, 0,
            3, -1.6, -1.8, 1.0, 0.45, 0.45, 1,
            3, -2.9, -5.0, 0.5, 0.7, 0.6, 1,
            3, -3.2, -8.8, 0.3, 0.3, 0.3, 0,
        ))
    elif part == FLEXOR_DIGITI_MINIMI:
        paths.append(floats(
            1, 0, 0,
            3, -1.5, -3.3, 1.3, 0.35, 0.35, 1,
            3, -2.3, -5.8, 1.2, 0.55, 0.5, 1,
            3, -2.8, -8.8, 0.9, 0.25, 0.25, 0,
        ))
    elif part == OPPONENS_DIGITI_MINIMI:
        paths.append(floats(
            1, 0, 0,
            3, -1.5, -3.3, 1.0, 0.35, 0.35, 1,
            3, -2.4, -6.2, 0.8, 0.5, 0.45, 1,
            3, -2.8, -8.0, 0.6, 0.35, 0.3, 1,
        ))
    elif part == DORSAL_INTEROSSEI:
        # The first, between the thumb and the index, is the largest.
        paths.append(floats(
            1, 0, 0,
            3, 2.1, -4.4, 0.6, 0.5, 0.5, 1,
            3, 2.2, -6.6, 0.9, 0.8, 0.7, 1,
            3, 1.9, -10.6, 0.4, 0.25, 0.25, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, 0.55, -5.0, 0.0, 0.3, 0.4, 1,
            3, 0.55, -7.8, 0.0, 0.35, 0.45, 1,
            3, 0.5, -10.8, -0.1, 0.18, 0.18, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, -0.6, -4.9, 0.0, 0.3, 0.4, 1,
            3, -0.65, -7.6, 0.0, 0.35, 0.45, 1,
            3, -0.8, -10.3, -0.1, 0.18, 0.18, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, -1.7, -4.7, 0.0, 0.3, 0.4, 1,
            3, -1.95, -7.2, 0.0, 0.35, 0.45, 1,
            3, -2.2, -9.7, -0.1, 0.18, 0.18, 0,
        ))
    else:
        # The palmar interossei, in front of the dorsal ones.
        paths.append(floats(
            1, 0, 0,
            3, 0.6, -5.2, 0.7, 0.28, 0.32, 1,
            3, 0.6, -7.8, 0.75, 0.3, 0.35, 1,
            3, 0.7, -10.6, 0.5, 0.15, 0.15, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, -0.6, -5.1, 0.7, 0.28, 0.32, 1,
            3, -0.75, -7.6, 0.75, 0.3, 0.35, 1,
            3, -0.95, -10.2, 0.5, 0.15, 0.15, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, -1.7, -4.9, 0.6, 0.28, 0.32, 1,
            3, -2.0, -7.2, 0.65, 0.3, 0.35, 1,
            3, -2.3, -9.5, 0.4, 0.15, 0.15, 0,
        ))
    # fmt: on
    return paths^


def hand_muscle_field(
    dimensions: ArmMuscleDimensions, part: HandMuscle, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one hand muscle or tendon group.

    Args:
        dimensions: Landmarks and the radius scale.
        part: A named part.
        side: `RIGHT` or `LEFT`.

    Returns:
        The part's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    var tendon = is_hand_tendon(part)
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var arm = dimensions.arm.copy()
    var f = arm.frame
    if part == LUMBRICALS or tendon:
        var sweeps = List[Sweep]()
        if part == LUMBRICALS:
            _lumbricals(sweeps, arm, dimensions.scale)
        elif part == FLEXOR_TENDONS:
            for k in range(INDEX.value, LITTLE.value + 1):
                sweeps.append(_digit_tendon(arm, Finger(k), True))
        elif part == FLEXOR_POLLICIS_LONGUS_TENDON:
            sweeps.append(_digit_tendon(arm, THUMB, True))
        elif part == EXTENSOR_TENDONS:
            for k in range(INDEX.value, LITTLE.value + 1):
                sweeps.append(_digit_tendon(arm, Finger(k), False))
        else:
            sweeps.append(_digit_tendon(arm, THUMB, False))
            # The short extensor, beside the long one, to the base of
            # the thumb's proximal phalanx.
            var short = Sweep(Vector3(1, 0, 0))
            short.round(f.hand(3.2, -2.0, 0.5), f.cm(0.2))
            short.round(f.hand(3.9, -4.6, 1.5), f.cm(0.2))
            short.round(f.hand(4.3, -7.3, 2.8), f.cm(0.18))
            sweeps.append(short^)
        return SweepField(
            sweeps^, List[Dome](), side, f.cm(0.2), f.cm(0.04), f.cm(0.3)
        )
    return paths_field(arm, _muscle_paths(part), dimensions.scale, side, 0.25)


def _lumbricals(
    mut sweeps: List[Sweep], dimensions: ArmDimensions, scale: Float32
) raises:
    """Append the four lumbricals: from the deep flexor tendons in the
    palm to the thumb side of each finger's knuckle."""
    var f = dimensions.frame
    var palm = f.hand_direction(0, 0, 1)
    var lateral = f.hand_direction(1, 0, 0)
    for k in range(INDEX.value, LITTLE.value + 1):
        var joints = finger_joints(dimensions, Finger(k))
        var base = joints[0]
        var knuckle = joints[1]
        var worm = Sweep(Vector3(1, 0, 0))
        var start = base + (knuckle - base) * 0.3 + palm * f.cm(1.0)
        worm.round(start, f.cm(0.25) * scale)
        var side = knuckle + lateral * f.cm(0.5)
        worm.round(side + palm * f.cm(0.5), f.cm(0.3) * scale)
        var along = joints[2] - knuckle
        worm.round(side + along * 0.3, f.cm(0.13))
        sweeps.append(worm^)


def _digit_tendon(
    dimensions: ArmDimensions, finger: Finger, front: Bool
) raises -> Sweep:
    """Return one digit's long tendon, in front of the bones or behind.

    It runs from the wrist along the metacarpal, over each joint, to the
    base of the distal phalanx.
    """
    var f = dimensions.frame
    var joints = finger_joints(dimensions, finger)
    var s = finger_scale(finger)
    # Palmar for a flexor, dorsal for an extensor. The thumb turns its
    # palm toward the fingers, so its palmar side faces in and forward.
    var face = f.hand_direction(0, 0, 1)
    if finger == THUMB:
        face = f.hand_direction(-0.6, 0, 0.8)
    if not front:
        face = face * -1
    var tendon = Sweep(Vector3(1, 0, 0))
    var wrist = f.hand(joints_x(finger) * 0.5, -1.2, 0)
    var r = Float32(0.3)
    if not front:
        r = Float32(0.2)
    tendon.round(wrist + face * f.cm(1.4), f.cm(r))
    var count = len(joints)
    for index in range(1, count - 1):
        # Clear the bone: its radius, and a little more over a joint.
        var clear = f.cm((0.75 - 0.08 * Float32(index)) * s)
        var fade = Float32(1) - Float32(0.18) * Float32(index)
        tendon.round(joints[index] + face * clear, f.cm(r * fade))
    var last = joints[count - 2] + (joints[count - 1] - joints[count - 2]) * 0.3
    tendon.round(last + face * f.cm(0.35 * s), f.cm(r * 0.4))
    return tendon^


def joints_x(finger: Finger) -> Float32:
    """Return how far lateral a digit's tendon enters the hand, in
    template cm.

    Args:
        finger: A digit. Any value past the ring finger reads as the
            little finger.

    Returns:
        The x of its metacarpal's base in the hand's frame.
    """
    if finger == THUMB:
        return 2.5
    if finger == INDEX:
        return 1.05
    if finger.value == 2:
        return 0.0
    if finger.value == 3:
        return -1.15
    return -2.1


def hand_muscle_distance(
    dimensions: ArmMuscleDimensions,
    part: HandMuscle,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return hand_muscle_field(dimensions, part, side).distance(point)
