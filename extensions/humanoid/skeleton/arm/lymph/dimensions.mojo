# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named lymphatics of the arm, as implicit solids.

The superficial collecting vessels of the arm run in two bundles. The
medial bundle follows the basilic vein up the forearm to the cubital
nodes above the medial epicondyle, and on to the torso's axillary
nodes. The lateral bundle follows the cephalic vein up to the
deltopectoral nodes in the groove between the deltoid and the
pectoralis major. Two representative nodes stand for each group.

Radii are authored template values. They are not a cited count or size
table. Geometry applies a separate diagrammatic minimum radius.

    var dims = arm_muscle_dimensions(person)
    var d = arm_lymph_distance(dims, CUBITAL_NODES, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.muscles.dimensions import paths_field
from extensions.humanoid.skeleton.torso.sweep import SweepField, floats
from math.vector3 import Vector3


@fieldwise_init
struct ArmLymph(Equatable, ImplicitlyCopyable, Writable):
    """Which named lymphatic of the arm a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named lymphatic."""
        if self.value < 0:
            return False
        return self.value <= LATERAL_LYMPHATICS.value


comptime CUBITAL_NODES = ArmLymph(0)
comptime DELTOPECTORAL_NODES = ArmLymph(1)
# The collecting vessels beside the basilic vein.
comptime MEDIAL_LYMPHATICS = ArmLymph(2)
# The collecting vessels beside the cephalic vein.
comptime LATERAL_LYMPHATICS = ArmLymph(3)


def arm_lymph_label(part: ArmLymph) -> String:
    """Return the error-text name of `part`.

    Args:
        part: An arm lymphatic, named or not.

    Returns:
        A short American English label, or `"arm lymph"` when `part` is
        not named.
    """
    if not part.is_valid():
        return "arm lymph"
    var names = List[String]()
    names.append("cubital nodes")
    names.append("deltopectoral nodes")
    names.append("medial lymphatics")
    names.append("lateral lymphatics")
    return names[part.value]


def named_arm_lymph() -> List[ArmLymph]:
    """Return every named arm lymphatic in a stable order.

    Returns:
        The two node groups, then the two bundles.
    """
    var parts = List[ArmLymph]()
    for index in range(LATERAL_LYMPHATICS.value + 1):  # pragma: no branch
        parts.append(ArmLymph(index))
    return parts^


def arm_lymph_paths(part: ArmLymph) raises -> List[List[Float32]]:
    """Return the authored nodes or runs of one lymphatic.

    The layout is `arm_muscle_paths`'s. A node is a run of one station.
    No station grows with athleticism.

    Args:
        part: A named lymphatic.

    Returns:
        One list per node or run.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("An arm lymphatic must be a named part")
    var paths = List[List[Float32]]()
    # fmt: off
    if part == CUBITAL_NODES:
        paths.append(floats(1, 0, 0, 1, -3.9, -28.5, 1.3, 0.35, 0.3, 0))
        paths.append(floats(1, 0, 0, 1, -3.9, -26.8, 1.1, 0.3, 0.26, 0))
    elif part == DELTOPECTORAL_NODES:
        paths.append(floats(1, 0, 0, 0, 15.6, 46.4, 4.2, 0.3, 0.26, 0))
        paths.append(floats(1, 0, 0, 0, 15.2, 47.6, 3.6, 0.26, 0.22, 0))
    elif part == MEDIAL_LYMPHATICS:
        for k in range(2):  # pragma: no branch
            var o = Float32(0.4) * Float32(k) - Float32(0.2)
            paths.append(floats(
                1, 0, 0,
                3, -2.4 + o, -3.2, -0.3, 0.07, 0.07, 0,
                2, -3.2 + o, -24.0, 0.2, 0.07, 0.07, 0,
                2, -3.6 + o, -14.0, 1.0, 0.07, 0.07, 0,
                2, -3.4 + o, -4.0, 2.1, 0.07, 0.07, 0,
                1, -3.9, -28.5 + o, 1.3, 0.07, 0.07, 0,
                1, -3.4 + o, -18.0, 1.6, 0.08, 0.08, 0,
                1, -3.6 + o, -8.0, 0.9, 0.08, 0.08, 0,
                0, 15.0, 42.5, -1.0, 0.08, 0.08, 0,
            ))
    else:
        for k in range(2):  # pragma: no branch
            var o = Float32(0.4) * Float32(k) - Float32(0.2)
            paths.append(floats(
                1, 0, 0,
                3, 2.4 + o, -3.4, -0.4, 0.07, 0.07, 0,
                2, 3.6 + o, -24.0, 0.8, 0.07, 0.07, 0,
                2, 4.0 + o, -14.0, 1.6, 0.07, 0.07, 0,
                2, 4.1 + o, -5.0, 2.7, 0.07, 0.07, 0,
                1, 2.7 + o, -24.0, 3.8, 0.07, 0.07, 0,
                1, 2.8 + o, -12.0, 4.6, 0.08, 0.08, 0,
                0, 15.6, 46.4, 4.2, 0.08, 0.08, 0,
            ))
    # fmt: on
    return paths^


def arm_lymph_field(
    dimensions: ArmMuscleDimensions, part: ArmLymph, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one arm lymphatic.

    Args:
        dimensions: Landmarks shared with the muscles.
        part: A named lymphatic.
        side: `RIGHT` or `LEFT`.

    Returns:
        The part's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    var paths = arm_lymph_paths(part)
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    return paths_field(dimensions.arm, paths, 1, side, 0.03)


def arm_lymph_distance(
    dimensions: ArmMuscleDimensions,
    part: ArmLymph,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which lymphatic to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return arm_lymph_field(dimensions, part, side).distance(point)
