# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named nerves of the hand and the fingers.

The median nerve leaves the carpal tunnel, sends its recurrent branch
into the thenar muscles, and fans into the common palmar digital nerves
of the thumb side. The ulnar nerve leaves Guyon's canal in a
superficial branch to the little finger's side and a deep branch
across the palm with the deep arch. The radial nerve's superficial
branch crosses the back of the wrist to the thumb's side of the back of
the hand. A proper palmar digital nerve runs along either side of each
digit, a little in front of its artery.

The digits' nerves follow each digit's joint chain from
`finger_joints`. Physical radii drive distance and mass. Geometry
applies a separate diagrammatic minimum radius. The values are
template parameters. They are not a cited caliber table.

    var dims = arm_muscle_dimensions(person)
    var d = hand_nerve_distance(dims, MEDIAN_BRANCHES, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
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
struct HandNerve(Equatable, ImplicitlyCopyable, Writable):
    """Which named nerve of the hand a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named nerves is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named nerve."""
        if self.value < 0:
            return False
        return self.value <= DIGITAL_NERVES.value


# The recurrent branch and the common palmar digital nerves.
comptime MEDIAN_BRANCHES = HandNerve(0)
# The superficial and the deep branch.
comptime ULNAR_BRANCHES = HandNerve(1)
comptime SUPERFICIAL_RADIAL_NERVE = HandNerve(2)
# Both proper palmar digital nerves of every digit.
comptime DIGITAL_NERVES = HandNerve(3)


def hand_nerve_label(part: HandNerve) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hand nerve, named or not.

    Returns:
        A short American English label, or `"hand nerve"` when `part`
        is not named.
    """
    if not part.is_valid():
        return "hand nerve"
    var names = List[String]()
    names.append("median branches")
    names.append("ulnar branches")
    names.append("superficial radial nerve")
    names.append("digital nerves")
    return names[part.value]


def named_hand_nerves() -> List[HandNerve]:
    """Return every named hand nerve in a stable order.

    Returns:
        The median, ulnar and radial branches, then the digital nerves.
    """
    var parts = List[HandNerve]()
    for index in range(DIGITAL_NERVES.value + 1):
        parts.append(HandNerve(index))
    return parts^


def hand_nerve_field(
    dimensions: ArmMuscleDimensions, part: HandNerve, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one hand nerve.

    Args:
        dimensions: Landmarks shared with the muscles.
        part: A named nerve.
        side: `RIGHT` or `LEFT`.

    Returns:
        The nerve's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A hand nerve must be a named nerve")
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var arm = dimensions.arm.copy()
    var f = arm.frame
    if part == DIGITAL_NERVES:
        var sweeps = List[Sweep]()
        var digits = named_fingers()
        for index in range(len(digits)):
            var joints = finger_joints(arm, digits[index])
            var s = finger_scale(digits[index])
            var front = palmar_direction(arm, digits[index])
            var last = len(joints) - 1
            var along = joints[last] - joints[1]
            along.normalize()
            var aside = cross(along, front)
            aside.normalize()
            for k in range(2):
                var sign = Float32(1)
                if k == 1:
                    sign = Float32(-1)
                var run = Sweep(Vector3(1, 0, 0))
                for j in range(1, last):
                    var r = f.cm((0.45 - 0.05 * Float32(j)) * s)
                    run.round(
                        joints[j] + aside * (sign * r) + front * f.cm(0.45),
                        f.cm(0.07),
                    )
                run.round(
                    joints[last]
                    - along * f.cm(0.4)
                    + aside * (sign * f.cm(0.25))
                    + front * f.cm(0.3),
                    f.cm(0.05),
                )
                sweeps.append(run^)
        return SweepField(
            sweeps^, List[Dome](), side, f.cm(0.03), f.cm(0.01), f.cm(0.2)
        )
    var paths = List[List[Float32]]()
    # fmt: off
    if part == MEDIAN_BRANCHES:
        paths.append(floats(
            1, 0, 0,
            3, 0.8, -3.2, 1.5, 0.1, 0.1, 0,
            3, 1.8, -3.6, 2.1, 0.08, 0.08, 0,
            3, 2.4, -4.2, 2.3, 0.06, 0.06, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, 0.6, -2.0, 1.2, 0.16, 0.16, 0,
            3, 0.6, -2.8, 1.3, 0.14, 0.14, 0,
            3, 1.8, -5.0, 1.9, 0.1, 0.1, 0,
            3, 2.6, -6.2, 2.4, 0.08, 0.08, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, 0.6, -2.8, 1.3, 0.12, 0.12, 0,
            3, 1.1, -5.5, 1.4, 0.1, 0.1, 0,
            3, 1.3, -7.0, 1.4, 0.08, 0.08, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, 0.6, -2.8, 1.3, 0.12, 0.12, 0,
            3, 0.4, -5.6, 1.4, 0.1, 0.1, 0,
            3, 0.4, -7.2, 1.4, 0.08, 0.08, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, 0.6, -2.8, 1.3, 0.1, 0.1, 0,
            3, -0.2, -5.5, 1.4, 0.09, 0.09, 0,
            3, -0.6, -7.0, 1.4, 0.07, 0.07, 0,
        ))
    elif part == ULNAR_BRANCHES:
        paths.append(floats(
            1, 0, 0,
            3, -1.3, -2.2, 1.3, 0.15, 0.15, 0,
            3, -1.4, -4.6, 1.4, 0.11, 0.11, 0,
            3, -1.6, -6.8, 1.4, 0.08, 0.08, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, -1.4, -4.6, 1.4, 0.09, 0.09, 0,
            3, -0.9, -7.0, 1.4, 0.07, 0.07, 0,
        ))
        # The deep branch, across the palm with the deep arch.
        paths.append(floats(
            1, 0, 0,
            3, -1.4, -3.0, 1.0, 0.12, 0.12, 0,
            3, -0.8, -4.7, 0.85, 0.1, 0.1, 0,
            3, 0.4, -4.9, 0.8, 0.09, 0.09, 0,
            3, 1.6, -4.9, 0.8, 0.08, 0.08, 0,
        ))
    else:
        paths.append(floats(
            1, 0, 0,
            2, 3.3, -26.0, 0.6, 0.11, 0.11, 0,
            3, 2.7, -2.4, -0.3, 0.1, 0.1, 0,
            3, 2.4, -5.0, -0.7, 0.08, 0.08, 0,
            3, 1.6, -7.2, -0.8, 0.06, 0.06, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            3, 2.7, -2.4, -0.3, 0.08, 0.08, 0,
            3, 3.3, -4.5, 0.4, 0.07, 0.07, 0,
            3, 3.9, -6.6, 1.5, 0.06, 0.06, 0,
        ))
    # fmt: on
    return paths_field(arm, paths, 1, side, 0.04)


def hand_nerve_distance(
    dimensions: ArmMuscleDimensions,
    part: HandNerve,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which nerve to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return hand_nerve_field(dimensions, part, side).distance(point)
