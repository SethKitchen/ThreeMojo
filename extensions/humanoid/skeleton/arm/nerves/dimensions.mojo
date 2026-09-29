# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named nerves of the arm, as implicit tubes.

The five terminal nerves leave the torso's brachial plexus in the
armpit. The axillary nerve wraps behind the humerus's surgical neck to
the deltoid. The musculocutaneous nerve runs between the biceps and
the brachialis and ends in the skin of the lateral forearm. The radial
nerve spirals behind the humerus, comes forward at the elbow, and
divides into a deep branch behind the forearm and a superficial branch
under the brachioradialis. The median nerve runs beside the brachial
artery to the front of the elbow, down the middle of the forearm and
through the carpal tunnel. The ulnar nerve runs down the inside of the
arm, behind the medial epicondyle, and down the ulnar side of the
forearm to the wrist. The hand's branches take them over; see
`extensions.humanoid.skeleton.hand.nerves`.

Physical radii drive distance and mass. Geometry applies a separate
diagrammatic minimum radius. The values are template parameters. They
are not a cited caliber table.

    var dims = arm_muscle_dimensions(person)
    var d = arm_nerve_distance(dims, MEDIAN_NERVE, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.muscles.dimensions import paths_field
from extensions.humanoid.skeleton.torso.sweep import SweepField, floats
from math.vector3 import Vector3


@fieldwise_init
struct ArmNerve(Equatable, ImplicitlyCopyable, Writable):
    """Which named nerve of the arm a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named nerves is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named nerve."""
        if self.value < 0:
            return False
        return self.value <= ULNAR_NERVE.value


comptime AXILLARY_NERVE = ArmNerve(0)
comptime MUSCULOCUTANEOUS_NERVE = ArmNerve(1)
comptime RADIAL_NERVE = ArmNerve(2)
comptime MEDIAN_NERVE = ArmNerve(3)
comptime ULNAR_NERVE = ArmNerve(4)


def arm_nerve_label(part: ArmNerve) -> String:
    """Return the error-text name of `part`.

    Args:
        part: An arm nerve, named or not.

    Returns:
        A short American English label, or `"arm nerve"` when `part` is
        not named.
    """
    if not part.is_valid():
        return "arm nerve"
    var names = List[String]()
    names.append("axillary nerve")
    names.append("musculocutaneous nerve")
    names.append("radial nerve")
    names.append("median nerve")
    names.append("ulnar nerve")
    return names[part.value]


def named_arm_nerves() -> List[ArmNerve]:
    """Return every named arm nerve in a stable order.

    Returns:
        The axillary, musculocutaneous, radial, median and ulnar nerves.
    """
    var parts = List[ArmNerve]()
    for index in range(ULNAR_NERVE.value + 1):
        parts.append(ArmNerve(index))
    return parts^


def arm_nerve_paths(part: ArmNerve) raises -> List[List[Float32]]:
    """Return the authored runs of one nerve.

    The layout is `arm_muscle_paths`'s. No station grows with
    athleticism.

    Args:
        part: A named nerve.

    Returns:
        One list per run.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("An arm nerve must be a named nerve")
    var paths = List[List[Float32]]()
    # fmt: off
    if part == AXILLARY_NERVE:
        paths.append(floats(
            1, 0, 0,
            0, 14.8, 45.2, -0.1, 0.2, 0.2, 0,
            1, -1.6, -2.8, -1.0, 0.19, 0.19, 0,
            1, 0.8, -4.2, -2.4, 0.18, 0.18, 0,
            1, 2.6, -4.8, -1.0, 0.15, 0.15, 0,
        ))
    elif part == MUSCULOCUTANEOUS_NERVE:
        paths.append(floats(
            1, 0, 0,
            0, 14.8, 45.2, -0.1, 0.17, 0.17, 0,
            1, -1.8, -4.0, 1.8, 0.16, 0.16, 0,
            1, -1.4, -8.0, 1.6, 0.15, 0.15, 0,
            1, 0.3, -16.0, 2.8, 0.14, 0.14, 0,
            1, 1.3, -27.0, 3.0, 0.13, 0.13, 0,
            2, 3.4, -3.0, 2.2, 0.11, 0.11, 0,
            2, 3.9, -12.0, 1.6, 0.1, 0.1, 0,
        ))
    elif part == RADIAL_NERVE:
        paths.append(floats(
            1, 0, 0,
            0, 14.8, 45.2, -0.1, 0.25, 0.25, 0,
            1, -2.6, -6.0, -0.6, 0.25, 0.25, 0,
            1, -0.6, -12.0, -1.6, 0.24, 0.24, 0,
            1, 1.6, -18.0, -1.3, 0.24, 0.24, 0,
            1, 2.2, -24.0, 0.3, 0.23, 0.23, 0,
            1, 1.9, -29.0, 1.4, 0.23, 0.23, 0,
            2, 2.4, -1.5, 1.4, 0.22, 0.22, 0,
        ))
        # The deep branch, around the radius behind the forearm.
        paths.append(floats(
            1, 0, 0,
            2, 2.4, -1.5, 1.4, 0.16, 0.16, 0,
            2, 3.0, -4.5, 0.0, 0.15, 0.15, 0,
            2, 1.8, -10.0, -1.3, 0.13, 0.13, 0,
            2, 0.9, -20.0, -1.2, 0.1, 0.1, 0,
        ))
        # The superficial branch, under the brachioradialis.
        paths.append(floats(
            1, 0, 0,
            2, 2.4, -1.5, 1.4, 0.14, 0.14, 0,
            2, 2.8, -10.0, 1.7, 0.13, 0.13, 0,
            2, 3.0, -22.0, 1.2, 0.12, 0.12, 0,
            2, 3.3, -26.0, 0.6, 0.11, 0.11, 0,
        ))
    elif part == MEDIAN_NERVE:
        paths.append(floats(
            1, 0, 0,
            0, 14.8, 45.2, -0.1, 0.24, 0.24, 0,
            1, -2.6, -5.0, 1.4, 0.24, 0.24, 0,
            1, -1.4, -15.0, 1.5, 0.23, 0.23, 0,
            1, -1.5, -25.0, 2.1, 0.23, 0.23, 0,
            1, -1.0, -31.0, 2.3, 0.22, 0.22, 0,
            2, -0.3, -4.0, 1.9, 0.21, 0.21, 0,
            2, 0.0, -12.0, 1.7, 0.2, 0.2, 0,
            2, 0.5, -24.0, 1.6, 0.19, 0.19, 0,
            2, 0.7, -28.3, 1.6, 0.19, 0.19, 0,
            3, 0.6, -2.0, 1.2, 0.18, 0.18, 0,
        ))
    else:
        paths.append(floats(
            1, 0, 0,
            0, 14.8, 45.2, -0.1, 0.22, 0.22, 0,
            1, -3.0, -5.5, 0.9, 0.22, 0.22, 0,
            1, -2.9, -15.0, 0.6, 0.21, 0.21, 0,
            1, -2.8, -26.0, -0.4, 0.21, 0.21, 0,
            1, -3.4, -31.5, -1.2, 0.2, 0.2, 0,
            2, -2.6, -2.5, -0.2, 0.2, 0.2, 0,
            2, -2.4, -10.0, 0.6, 0.19, 0.19, 0,
            2, -2.2, -24.0, 1.2, 0.18, 0.18, 0,
            2, -1.9, -28.0, 1.4, 0.18, 0.18, 0,
            3, -1.3, -2.2, 1.3, 0.17, 0.17, 0,
        ))
    # fmt: on
    return paths^


def arm_nerve_field(
    dimensions: ArmMuscleDimensions, part: ArmNerve, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one arm nerve.

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
    var paths = arm_nerve_paths(part)
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    return paths_field(dimensions.arm, paths, 1, side, 0.05)


def arm_nerve_distance(
    dimensions: ArmMuscleDimensions,
    part: ArmNerve,
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
    return arm_nerve_field(dimensions, part, side).distance(point)
