# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named arteries and veins of the arm, as implicit tubes.

The axillary artery continues the torso's subclavian artery through
the armpit. It becomes the brachial artery, which runs down the inside
of the arm to the front of the elbow and divides into the radial and
the ulnar arteries. The radial artery runs down the lateral forearm to
the wrist and turns onto the back of the hand; the ulnar artery runs
down the medial forearm to the palm. The hand's arches take both over;
see `extensions.humanoid.skeleton.hand.vessels`.

The deep veins follow the arteries: two brachial veins beside the
artery, and the axillary vein, which becomes the torso's subclavian
vein. The superficial veins lie under the skin: the cephalic vein up
the lateral side to the groove between the deltoid and the pectoralis
major, the basilic vein up the medial side, and the median cubital
vein across the front of the elbow between them.

Physical radii drive distance and mass. Geometry applies a separate
diagrammatic minimum radius. The values are template parameters. They
are not a cited caliber table.

    var dims = arm_muscle_dimensions(person)
    var d = arm_vessel_distance(dims, BRACHIAL_ARTERY, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.muscles.dimensions import paths_field
from extensions.humanoid.skeleton.torso.sweep import SweepField, floats
from math.vector3 import Vector3


@fieldwise_init
struct ArmVessel(Equatable, ImplicitlyCopyable, Writable):
    """Which named artery or vein of the arm a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named vessels is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named vessel."""
        if self.value < 0:
            return False
        return self.value <= MEDIAN_CUBITAL_VEIN.value


comptime AXILLARY_ARTERY = ArmVessel(0)
comptime BRACHIAL_ARTERY = ArmVessel(1)
comptime RADIAL_ARTERY = ArmVessel(2)
comptime ULNAR_ARTERY = ArmVessel(3)
comptime AXILLARY_VEIN = ArmVessel(4)
# The two venae comitantes beside the brachial artery.
comptime BRACHIAL_VEINS = ArmVessel(5)
comptime CEPHALIC_VEIN = ArmVessel(6)
comptime BASILIC_VEIN = ArmVessel(7)
comptime MEDIAN_CUBITAL_VEIN = ArmVessel(8)


def is_arm_artery(part: ArmVessel) raises -> Bool:
    """Return True if `part` is an artery.

    Args:
        part: A named vessel.

    Returns:
        True for the four arteries.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("An arm vessel must be a named artery or vein")
    return part.value <= ULNAR_ARTERY.value


def arm_vessel_label(part: ArmVessel) -> String:
    """Return the error-text name of `part`.

    Args:
        part: An arm vessel, named or not.

    Returns:
        A short American English label, or `"arm vessel"` when `part`
        is not named.
    """
    if not part.is_valid():
        return "arm vessel"
    var names = List[String]()
    names.append("axillary artery")
    names.append("brachial artery")
    names.append("radial artery")
    names.append("ulnar artery")
    names.append("axillary vein")
    names.append("brachial veins")
    names.append("cephalic vein")
    names.append("basilic vein")
    names.append("median cubital vein")
    return names[part.value]


def named_arm_vessels() -> List[ArmVessel]:
    """Return every named arm vessel in a stable order.

    Returns:
        The four arteries, then the five veins.
    """
    var parts = List[ArmVessel]()
    for index in range(MEDIAN_CUBITAL_VEIN.value + 1):
        parts.append(ArmVessel(index))
    return parts^


def arm_vessel_paths(part: ArmVessel) raises -> List[List[Float32]]:
    """Return the authored runs of one vessel.

    The layout is `arm_muscle_paths`'s. No station grows with
    athleticism.

    Args:
        part: A named vessel.

    Returns:
        One list per run.

    Raises:
        Error: If `part` is not named.
    """
    _ = is_arm_artery(part)
    var paths = List[List[Float32]]()
    # fmt: off
    if part == AXILLARY_ARTERY:
        paths.append(floats(
            1, 0, 0,
            0, 12.5, 47.6, 0.5, 0.42, 0.42, 0,
            0, 14.4, 45.6, 0.2, 0.4, 0.4, 0,
            1, -3.4, -1.5, 1.4, 0.4, 0.4, 0,
            1, -2.2, -6.5, 0.9, 0.36, 0.36, 0,
        ))
    elif part == BRACHIAL_ARTERY:
        paths.append(floats(
            1, 0, 0,
            1, -2.2, -6.5, 0.9, 0.34, 0.34, 0,
            1, -1.8, -15.0, 1.2, 0.33, 0.33, 0,
            1, -0.9, -25.0, 1.9, 0.31, 0.31, 0,
            1, -0.2, -31.0, 2.4, 0.3, 0.3, 0,
            2, 0.2, -2.5, 1.6, 0.28, 0.28, 0,
        ))
    elif part == RADIAL_ARTERY:
        paths.append(floats(
            1, 0, 0,
            2, 0.2, -2.5, 1.6, 0.22, 0.22, 0,
            2, 1.2, -8.0, 2.1, 0.21, 0.21, 0,
            2, 2.0, -16.0, 2.3, 0.2, 0.2, 0,
            2, 2.2, -24.0, 2.1, 0.19, 0.19, 0,
            2, 2.4, -27.5, 1.9, 0.18, 0.18, 0,
            3, 2.9, -1.2, 0.6, 0.17, 0.17, 0,
            3, 2.6, -2.0, 0.4, 0.16, 0.16, 0,
        ))
    elif part == ULNAR_ARTERY:
        paths.append(floats(
            1, 0, 0,
            2, 0.2, -2.5, 1.6, 0.24, 0.24, 0,
            2, -1.2, -7.0, 1.5, 0.23, 0.23, 0,
            2, -2.1, -15.0, 1.6, 0.22, 0.22, 0,
            2, -2.2, -24.0, 1.6, 0.21, 0.21, 0,
            2, -1.7, -28.0, 1.7, 0.2, 0.2, 0,
            3, -1.2, -2.4, 1.6, 0.19, 0.19, 0,
        ))
    elif part == AXILLARY_VEIN:
        paths.append(floats(
            1, 0, 0,
            1, -3.8, -6.3, 0.4, 0.5, 0.5, 0,
            1, -3.9, -2.8, 1.2, 0.55, 0.55, 0,
            0, 14.2, 45.2, 1.3, 0.55, 0.55, 0,
            0, 12.5, 47.0, 1.4, 0.55, 0.55, 0,
        ))
    elif part == BRACHIAL_VEINS:
        paths.append(floats(
            1, 0, 0,
            1, -2.7, -6.6, 0.8, 0.2, 0.2, 0,
            1, -2.3, -15.0, 1.1, 0.2, 0.2, 0,
            1, -1.4, -25.0, 1.8, 0.19, 0.19, 0,
            1, -0.7, -31.0, 2.3, 0.18, 0.18, 0,
            2, -0.2, -2.6, 1.5, 0.17, 0.17, 0,
        ))
        paths.append(floats(
            1, 0, 0,
            1, -1.7, -6.8, 1.3, 0.2, 0.2, 0,
            1, -1.3, -15.0, 1.6, 0.2, 0.2, 0,
            1, -0.4, -25.0, 2.3, 0.19, 0.19, 0,
            1, 0.3, -31.0, 2.7, 0.18, 0.18, 0,
            2, 0.6, -2.6, 1.8, 0.17, 0.17, 0,
        ))
    elif part == CEPHALIC_VEIN:
        # From the back of the hand's thumb side, up the lateral forearm
        # and arm, through the groove between the deltoid and the
        # pectoralis major, to the axillary vein.
        paths.append(floats(
            1, 0, 0,
            3, 2.6, -3.5, -0.6, 0.2, 0.2, 0,
            3, 3.4, -0.5, -0.1, 0.22, 0.22, 0,
            2, 3.8, -25.0, 0.4, 0.23, 0.23, 0,
            2, 4.3, -16.0, 1.2, 0.24, 0.24, 0,
            2, 4.4, -6.0, 2.4, 0.25, 0.25, 0,
            1, 2.9, -29.0, 3.2, 0.26, 0.26, 0,
            1, 2.4, -18.0, 4.4, 0.26, 0.26, 0,
            1, 2.6, -8.0, 4.4, 0.27, 0.27, 0,
            0, 15.4, 45.4, 4.0, 0.28, 0.28, 0,
            0, 15.2, 48.2, 2.8, 0.28, 0.28, 0,
            0, 13.2, 47.4, 1.6, 0.3, 0.3, 0,
        ))
    elif part == BASILIC_VEIN:
        paths.append(floats(
            1, 0, 0,
            3, -2.6, -3.6, -0.5, 0.2, 0.2, 0,
            3, -3.1, -0.6, -0.2, 0.22, 0.22, 0,
            2, -3.4, -25.0, -0.2, 0.24, 0.24, 0,
            2, -3.9, -15.0, 0.6, 0.26, 0.26, 0,
            2, -3.7, -5.0, 1.8, 0.27, 0.27, 0,
            1, -3.6, -30.0, 1.6, 0.28, 0.28, 0,
            1, -3.3, -20.0, 1.8, 0.29, 0.29, 0,
            1, -3.3, -12.0, 1.3, 0.3, 0.3, 0,
            1, -3.6, -7.0, 0.7, 0.32, 0.32, 0,
            1, -3.8, -6.3, 0.4, 0.35, 0.35, 0,
        ))
    else:
        paths.append(floats(
            1, 0, 0,
            2, 4.2, -2.5, 2.7, 0.2, 0.2, 0,
            2, 0.8, 0.4, 3.7, 0.22, 0.22, 0,
            1, -3.0, -30.5, 2.4, 0.22, 0.22, 0,
        ))
    # fmt: on
    return paths^


def arm_vessel_field(
    dimensions: ArmMuscleDimensions, part: ArmVessel, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one arm vessel.

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
    var paths = arm_vessel_paths(part)
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    return paths_field(dimensions.arm, paths, 1, side, 0.05)


def arm_vessel_distance(
    dimensions: ArmMuscleDimensions,
    part: ArmVessel,
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
    return arm_vessel_field(dimensions, part, side).distance(point)
