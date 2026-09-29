# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named lymphatics of the hand and the fingers.

A fine plexus under the palm's skin drains around the sides of the
hand to its back. On the back, a collecting vessel from each digit
runs up between the knuckles toward the wrist, where the arm's
collecting vessels take them over; see
`extensions.humanoid.skeleton.arm.lymph`.

The digits' vessels follow each digit's joint chain from
`finger_joints`. Radii are authored template values. They are not a
cited count or size table. Geometry applies a separate diagrammatic
minimum radius.

    var dims = arm_muscle_dimensions(person)
    var d = hand_lymph_distance(dims, PALMAR_PLEXUS, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.muscles.dimensions import paths_field
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
struct HandLymph(Equatable, ImplicitlyCopyable, Writable):
    """Which named lymphatic of the hand a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named lymphatic."""
        if self.value < 0:
            return False
        return self.value <= DORSAL_LYMPHATICS.value


comptime PALMAR_PLEXUS = HandLymph(0)
# One collecting vessel from each digit, up the back of the hand.
comptime DORSAL_LYMPHATICS = HandLymph(1)


def hand_lymph_label(part: HandLymph) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hand lymphatic, named or not.

    Returns:
        A short American English label, or `"hand lymph"` when `part`
        is not named.
    """
    if part == PALMAR_PLEXUS:
        return "palmar plexus"
    if part == DORSAL_LYMPHATICS:
        return "dorsal lymphatics"
    return "hand lymph"


def named_hand_lymph() -> List[HandLymph]:
    """Return every named hand lymphatic in a stable order.

    Returns:
        The palmar plexus, then the dorsal lymphatics.
    """
    var parts = List[HandLymph]()
    for index in range(DORSAL_LYMPHATICS.value + 1):
        parts.append(HandLymph(index))
    return parts^


def hand_lymph_field(
    dimensions: ArmMuscleDimensions, part: HandLymph, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one hand lymphatic.

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
    if not part.is_valid():
        raise Error("A hand lymphatic must be a named part")
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var arm = dimensions.arm.copy()
    var f = arm.frame
    if part == DORSAL_LYMPHATICS:
        var sweeps = List[Sweep]()
        var digits = named_fingers()
        for index in range(len(digits)):
            var joints = finger_joints(arm, digits[index])
            var s = finger_scale(digits[index])
            var back = palmar_direction(arm, digits[index]) * -1
            var run = Sweep(Vector3(1, 0, 0))
            run.round(joints[2] + back * f.cm(0.7 * s), f.cm(0.05))
            run.round(joints[1] + back * f.cm(0.95 * s), f.cm(0.06))
            run.round(joints[0] + back * f.cm(1.1), f.cm(0.07))
            run.round(f.hand(0.4, -0.6, -1.4), f.cm(0.08))
            sweeps.append(run^)
        return SweepField(
            sweeps^, List[Dome](), side, f.cm(0.03), f.cm(0.01), f.cm(0.2)
        )
    var paths = List[List[Float32]]()
    # fmt: off
    paths.append(floats(
        1, 0, 0,
        3, 2.2, -8.8, 1.6, 0.05, 0.05, 0,
        3, 0.4, -9.0, 1.6, 0.05, 0.05, 0,
        3, -1.6, -8.6, 1.4, 0.05, 0.05, 0,
        3, -3.0, -6.5, 0.9, 0.05, 0.05, 0,
        3, -3.2, -3.0, 0.2, 0.06, 0.06, 0,
    ))
    paths.append(floats(
        1, 0, 0,
        3, 0.4, -9.0, 1.6, 0.05, 0.05, 0,
        3, 0.6, -5.5, 1.8, 0.05, 0.05, 0,
        3, 2.8, -3.6, 1.5, 0.05, 0.05, 0,
        3, 3.4, -1.8, 0.4, 0.06, 0.06, 0,
    ))
    # fmt: on
    return paths_field(arm, paths, 1, side, 0.03)


def hand_lymph_distance(
    dimensions: ArmMuscleDimensions,
    part: HandLymph,
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
    return hand_lymph_field(dimensions, part, side).distance(point)
