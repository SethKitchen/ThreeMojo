# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Joint tissues and ligaments of the wrist, the hand and the fingers.

The set is the flexor retinaculum over the carpal tunnel, the extensor
retinaculum across the back of the wrist, the palmar aponeurosis
fanning from the wrist to the fingers, the collateral ligaments on
either side of each knuckle and finger joint, the volar plate in front
of each of those joints, the articular cartilage in the radiocarpal
joint and in each joint of the digits, and the triangular
fibrocartilage between the ulna's head and the carpus.

The digits' parts follow each digit's joint chain from
`finger_joints`. Their meshes widen the thinnest radii; see
`extensions.humanoid.skeleton.hand.ligaments.geometry`. Radii are
authored in template centimeters. They are not a cited width table.

    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var d = hand_ligament_distance(dims, FLEXOR_RETINACULUM, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmDimensions
from extensions.humanoid.skeleton.arm.ligaments.dimensions import joint_pad
from extensions.humanoid.skeleton.field import cross
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    INDEX,
    LITTLE,
    THUMB,
    Finger,
    finger_joints,
    finger_scale,
    named_fingers,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftTissue,
    cartilage_tissue,
    ligament_tissue,
    meniscus_tissue,
)
from extensions.humanoid.skeleton.torso.sweep import Dome, Sweep, SweepField
from math.vector3 import Vector3


@fieldwise_init
struct HandLigament(Equatable, ImplicitlyCopyable, Writable):
    """Which joint tissue or ligament of the hand a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named part."""
        if self.value < 0:
            return False
        return self.value <= TRIANGULAR_FIBROCARTILAGE.value


comptime FLEXOR_RETINACULUM = HandLigament(0)
comptime EXTENSOR_RETINACULUM = HandLigament(1)
comptime PALMAR_APONEUROSIS = HandLigament(2)
# Both collateral ligaments of every knuckle and finger joint.
comptime COLLATERAL_LIGAMENTS = HandLigament(3)
comptime VOLAR_PLATES = HandLigament(4)
# The radiocarpal joint's and the digits' joints' cartilage.
comptime JOINT_CARTILAGE = HandLigament(5)
comptime TRIANGULAR_FIBROCARTILAGE = HandLigament(6)


def hand_ligament_label(part: HandLigament) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hand part, named or not.

    Returns:
        A short American English label, or `"hand ligament"` when
        `part` is not named.
    """
    if not part.is_valid():
        return "hand ligament"
    var names = List[String]()
    names.append("flexor retinaculum")
    names.append("extensor retinaculum")
    names.append("palmar aponeurosis")
    names.append("collateral ligaments")
    names.append("volar plates")
    names.append("joint cartilage")
    names.append("triangular fibrocartilage")
    return names[part.value]


def named_hand_ligaments() -> List[HandLigament]:
    """Return every named hand joint tissue and ligament.

    Returns:
        The retinacula, the aponeurosis, the digits' parts and the
        triangular fibrocartilage.
    """
    var parts = List[HandLigament]()
    for index in range(
        TRIANGULAR_FIBROCARTILAGE.value + 1
    ):  # pragma: no branch
        parts.append(HandLigament(index))
    return parts^


def hand_ligament_tissue(part: HandLigament) raises -> SoftTissue:
    """Return the tissue `part` is made of.

    Args:
        part: A named part.

    Returns:
        Fibrocartilage for the triangular fibrocartilage, hyaline
        cartilage for the joint cartilage, and ligament for the rest.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A hand ligament must be a named part")
    if part == TRIANGULAR_FIBROCARTILAGE:
        return meniscus_tissue()
    if part == JOINT_CARTILAGE:
        return cartilage_tissue()
    return ligament_tissue()


def palmar_direction(dimensions: ArmDimensions, finger: Finger) -> Vector3:
    """Return which way the front of one right digit faces.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        finger: A digit. The thumb turns its front toward the fingers.

    Returns:
        A unit direction in the pelvis frame.
    """
    var f = dimensions.frame
    if finger == THUMB:
        return f.hand_direction(-0.6, 0, 0.8)
    return f.hand_direction(0, 0, 1)


def hand_ligament_field(
    dimensions: ArmDimensions, part: HandLigament, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one hand joint tissue or ligament.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: A named part.
        side: `RIGHT` or `LEFT`.

    Returns:
        The part's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    _ = hand_ligament_tissue(part)
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var f = dimensions.frame
    var up = f.hand_direction(0, 1, 0)
    var palm = f.hand_direction(0, 0, 1)
    var sweeps = List[Sweep]()
    if part == FLEXOR_RETINACULUM:
        # A band arching over the carpal tunnel, tall along the hand and
        # thin front to back.
        var band = Sweep(up)
        band.add(f.hand(2.1, -2.4, 1.5), f.cm(1.1), f.cm(0.16))
        band.add(f.hand(0.2, -2.4, 1.95), f.cm(1.2), f.cm(0.16))
        band.add(f.hand(-1.6, -2.4, 1.6), f.cm(1.1), f.cm(0.16))
        sweeps.append(band^)
    elif part == EXTENSOR_RETINACULUM:
        var band = Sweep(up)
        band.add(f.hand(2.8, 1.2, -0.3), f.cm(0.9), f.cm(0.14))
        band.add(f.hand(0.6, 1.2, -1.75), f.cm(1.0), f.cm(0.14))
        band.add(f.hand(-2.4, 1.2, -0.9), f.cm(0.9), f.cm(0.14))
        sweeps.append(band^)
    elif part == PALMAR_APONEUROSIS:
        var apex = f.hand(0.0, -2.5, 1.9)
        for k in range(INDEX.value, LITTLE.value + 1):  # pragma: no branch
            var joints = finger_joints(dimensions, Finger(k))
            var reach = joints[1] - joints[0]
            var band = Sweep(palm)
            band.add(apex, f.cm(0.1), f.cm(0.5))
            band.add(
                joints[0] + reach * 0.9 + palm * f.cm(1.05),
                f.cm(0.1),
                f.cm(0.35),
            )
            sweeps.append(band^)
    elif part == TRIANGULAR_FIBROCARTILAGE:
        sweeps.append(
            joint_pad(f.hand(-1.8, 0.5, -0.3), up, f.cm(0.15), f.cm(0.75))
        )
    elif part == JOINT_CARTILAGE:
        # The radiocarpal joint's face, then a pad in each gap of each
        # digit's chain.
        var down = up * -1
        sweeps.append(
            joint_pad(f.hand(0.8, 0.05, 0.45), down, f.cm(0.1), f.cm(1.6))
        )
        var digits = named_fingers()
        for index in range(len(digits)):  # pragma: no branch
            var joints = finger_joints(dimensions, digits[index])
            var s = finger_scale(digits[index])
            for j in range(1, len(joints) - 1):  # pragma: no branch
                var along = joints[j + 1] - joints[j]
                along.normalize()
                sweeps.append(
                    joint_pad(joints[j], along, f.cm(0.05), f.cm(0.42 * s))
                )
    else:
        var digits = named_fingers()
        for index in range(len(digits)):  # pragma: no branch
            _digit_joints(sweeps, dimensions, digits[index], part)
    return SweepField(
        sweeps^, List[Dome](), side, f.cm(0.08), f.cm(0.02), f.cm(0.3)
    )


def _digit_joints(
    mut sweeps: List[Sweep],
    dimensions: ArmDimensions,
    finger: Finger,
    part: HandLigament,
) raises:
    """Append one digit's collateral ligaments or volar plates."""
    var f = dimensions.frame
    var joints = finger_joints(dimensions, finger)
    var s = finger_scale(finger)
    var front = palmar_direction(dimensions, finger)
    for j in range(1, len(joints) - 1):  # pragma: no branch
        var along = joints[j + 1] - joints[j - 1]
        along.normalize()
        # The joint narrows out toward the fingertip.
        var r = f.cm((0.5 - 0.05 * Float32(j)) * s)
        if part == VOLAR_PLATES:
            sweeps.append(
                joint_pad(
                    joints[j] + front * (r + f.cm(0.08)),
                    front,
                    f.cm(0.08),
                    f.cm(0.4 * s),
                )
            )
            continue
        var aside = cross(along, front)
        aside.normalize()
        for k in range(2):  # pragma: no branch
            var sign = Float32(1)
            if k == 1:
                sign = Float32(-1)
            var offset = aside * (sign * (r + f.cm(0.05)))
            var band = Sweep(Vector3(1, 0, 0))
            band.round(joints[j] - along * f.cm(0.45) + offset, f.cm(0.12))
            band.round(joints[j] + along * f.cm(0.45) + offset, f.cm(0.12))
            sweeps.append(band^)


def hand_ligament_distance(
    dimensions: ArmDimensions,
    part: HandLigament,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return hand_ligament_field(dimensions, part, side).distance(point)
