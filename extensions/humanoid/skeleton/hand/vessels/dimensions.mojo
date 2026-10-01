# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named arteries and veins of the hand and the fingers.

The ulnar artery ends in the superficial palmar arch, under the palmar
aponeurosis. The radial artery crosses the back of the wrist and ends
in the deep palmar arch, on the bases of the metacarpals. A pair of
palmar digital arteries runs along either side of each digit. On the
back of the hand, the dorsal venous network gathers the dorsal digital
veins and drains into the arm's cephalic and basilic veins.

The digits' vessels follow each digit's joint chain from
`finger_joints`. Physical radii drive distance and mass. Geometry
applies a separate diagrammatic minimum radius. The values are
template parameters. They are not a cited caliber table.

    var dims = arm_muscle_dimensions(person)
    var d = hand_vessel_distance(dims, DEEP_PALMAR_ARCH, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmDimensions,
    ArmMuscleDimensions,
)
from extensions.humanoid.skeleton.arm.muscles.dimensions import paths_field
from extensions.humanoid.skeleton.field import cross
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    finger_joints,
    finger_scale,
    named_fingers,
)
from extensions.humanoid.skeleton.hand.ligaments.dimensions import (
    palmar_direction,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
)
from math.vector3 import Vector3


@fieldwise_init
struct HandVessel(Equatable, ImplicitlyCopyable, Writable):
    """Which named artery or vein of the hand a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named vessels is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named vessel."""
        if self.value < 0:
            return False
        return self.value <= DORSAL_DIGITAL_VEINS.value


comptime SUPERFICIAL_PALMAR_ARCH = HandVessel(0)
comptime DEEP_PALMAR_ARCH = HandVessel(1)
# Both palmar digital arteries of every digit.
comptime DIGITAL_ARTERIES = HandVessel(2)
comptime DORSAL_VENOUS_NETWORK = HandVessel(3)
comptime DORSAL_DIGITAL_VEINS = HandVessel(4)


def is_hand_artery(part: HandVessel) raises -> Bool:
    """Return True if `part` is an artery.

    Args:
        part: A named vessel.

    Returns:
        True for the two arches and the digital arteries.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A hand vessel must be a named artery or vein")
    return part.value <= DIGITAL_ARTERIES.value


def hand_vessel_label(part: HandVessel) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hand vessel, named or not.

    Returns:
        A short American English label, or `"hand vessel"` when `part`
        is not named.
    """
    if not part.is_valid():
        return "hand vessel"
    var names = List[String]()
    names.append("superficial palmar arch")
    names.append("deep palmar arch")
    names.append("digital arteries")
    names.append("dorsal venous network")
    names.append("dorsal digital veins")
    return names[part.value]


def named_hand_vessels() -> List[HandVessel]:
    """Return every named hand vessel in a stable order.

    Returns:
        The two arches, the digital arteries, then the veins.
    """
    var parts = List[HandVessel]()
    for index in range(DORSAL_DIGITAL_VEINS.value + 1):  # pragma: no branch
        parts.append(HandVessel(index))
    return parts^


def hand_vessel_field(
    dimensions: ArmMuscleDimensions, part: HandVessel, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one hand vessel.

    Args:
        dimensions: Landmarks shared with the muscles.
        part: A named vessel.
        side: `RIGHT` or `LEFT`.

    Returns:
        The vessel's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    var artery = is_hand_artery(part)
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var arm = dimensions.arm.copy()
    var f = arm.frame
    if part == DIGITAL_ARTERIES or part == DORSAL_DIGITAL_VEINS:
        var sweeps = List[Sweep]()
        var digits = named_fingers()
        for index in range(len(digits)):  # pragma: no branch
            _digit_vessels(sweeps, arm, index, artery)
        return SweepField(
            sweeps^, List[Dome](), side, f.cm(0.03), f.cm(0.01), f.cm(0.2)
        )
    var paths = List[List[Float32]]()
    # fmt: off
    if part == SUPERFICIAL_PALMAR_ARCH:
        paths.append(floats(
            1, 0, 0,
            3, -1.2, -2.4, 1.6, 0.14, 0.14, 0,
            3, -1.4, -4.5, 1.6, 0.14, 0.14, 0,
            3, -0.2, -6.2, 1.55, 0.13, 0.13, 0,
            3, 1.2, -6.0, 1.55, 0.12, 0.12, 0,
            3, 2.2, -4.8, 1.8, 0.1, 0.1, 0,
        ))
    elif part == DEEP_PALMAR_ARCH:
        paths.append(floats(
            1, 0, 0,
            3, 2.6, -2.0, 0.4, 0.14, 0.14, 0,
            3, 1.8, -4.6, 0.6, 0.13, 0.13, 0,
            3, 0.6, -4.8, 1.0, 0.12, 0.12, 0,
            3, -0.8, -4.8, 1.0, 0.11, 0.11, 0,
            3, -1.8, -4.5, 1.0, 0.1, 0.1, 0,
        ))
    else:
        paths.append(floats(
            1, 0, 0,
            3, 2.6, -3.5, -0.6, 0.2, 0.2, 0,
            3, 2.6, -5.5, -0.8, 0.19, 0.19, 0,
            3, 1.4, -7.8, -0.9, 0.18, 0.18, 0,
            3, -0.6, -8.2, -0.85, 0.18, 0.18, 0,
            3, -2.2, -7.0, -0.8, 0.19, 0.19, 0,
            3, -2.6, -3.6, -0.5, 0.2, 0.2, 0,
        ))
    # fmt: on
    return paths_field(arm, paths, 1, side, 0.05)


def _digit_vessels(
    mut sweeps: List[Sweep], dimensions: ArmDimensions, digit: Int, artery: Bool
) raises:
    """Append one digit's two palmar digital arteries, or its dorsal
    digital vein."""
    var f = dimensions.frame
    var digits = named_fingers()
    var finger = digits[digit]
    var joints = finger_joints(dimensions, finger)
    var s = finger_scale(finger)
    var front = palmar_direction(dimensions, finger)
    var along = joints[len(joints) - 1] - joints[1]
    along.normalize()
    var aside = cross(along, front)
    aside.normalize()
    var last = len(joints) - 1
    if not artery:
        # Along the back of the digit, from the knuckle to the last
        # joint.
        var vein = Sweep(Vector3(1, 0, 0))
        var back = front * -1
        for j in range(1, last):  # pragma: no branch
            vein.round(joints[j] + back * f.cm(0.75 * s), f.cm(0.08))
        vein.round(
            joints[last - 1] + along * f.cm(0.6) + back * f.cm(0.6 * s),
            f.cm(0.06),
        )
        sweeps.append(vein^)
        return
    for k in range(2):  # pragma: no branch
        var sign = Float32(1)
        if k == 1:
            sign = Float32(-1)
        var run = Sweep(Vector3(1, 0, 0))
        for j in range(1, last):  # pragma: no branch
            var r = f.cm((0.55 - 0.06 * Float32(j)) * s)
            run.round(
                joints[j] + aside * (sign * r) + front * f.cm(0.3),
                f.cm(0.08 - 0.01 * Float32(j)),
            )
        run.round(
            joints[last]
            - along * f.cm(0.5)
            + aside * (sign * f.cm(0.3))
            + front * f.cm(0.2),
            f.cm(0.05),
        )
        sweeps.append(run^)


def hand_vessel_distance(
    dimensions: ArmMuscleDimensions,
    part: HandVessel,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which vessel to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return hand_vessel_field(dimensions, part, side).distance(point)
