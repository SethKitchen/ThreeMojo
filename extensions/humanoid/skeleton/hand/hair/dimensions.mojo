# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named hair groups of one hand, as short implicit shafts.

Fine hair grows on the back of the hand and on the back of each
finger's proximal phalanx; the palm and the pads have none. Each root
sits where a ray out of the back of the hand leaves the hand's skin,
and each shaft lies toward the fingertips with a small outward tilt.
Physical shaft radii are authored template values. The mesh uses a
separate diagrammatic radius; see
`extensions.humanoid.skeleton.hand.hair.geometry`.

    var dims = arm_muscle_dimensions(person)
    var d = hand_hair_distance(dims, FINGER_HAIR, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.hair.dimensions import (
    shaft,
    surface_root,
)
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    INDEX,
    LITTLE,
    Finger,
    finger_joints,
)
from extensions.humanoid.skeleton.hand.skin.dimensions import HandSkinField
from extensions.humanoid.skeleton.torso.sweep import Dome, Sweep, SweepField
from math.vector3 import Vector3


@fieldwise_init
struct HandHair(Equatable, ImplicitlyCopyable, Writable):
    """Which named hair group of the hand a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named groups is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named hair group."""
        if self.value < 0:
            return False
        return self.value <= FINGER_HAIR.value


comptime HAND_HAIR = HandHair(0)
comptime FINGER_HAIR = HandHair(1)


def hand_hair_label(part: HandHair) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hair group, named or not.

    Returns:
        `"hand hair"` or `"finger hair"`, or `"hand hair group"` when
        `part` is not named.
    """
    if part == HAND_HAIR:
        return "hand hair"
    if part == FINGER_HAIR:
        return "finger hair"
    return "hand hair group"


def named_hand_hair() -> List[HandHair]:
    """Return every named hand hair group in a stable order.

    Returns:
        The back of the hand's hair, then the fingers'.
    """
    var parts = List[HandHair]()
    for index in range(FINGER_HAIR.value + 1):
        parts.append(HandHair(index))
    return parts^


def hand_hair_field(
    dimensions: ArmMuscleDimensions, part: HandHair, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one hand hair group.

    Args:
        dimensions: Landmarks shared with the muscles.
        part: A named hair group.
        side: `RIGHT` or `LEFT`.

    Returns:
        The group's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A hand hair part must be a named hair group")
    if not side.is_valid():
        raise Error("A hand side must be RIGHT or LEFT")
    var arm = dimensions.arm.copy()
    var f = arm.frame
    var skin = HandSkinField(dimensions, RIGHT)
    var back = f.hand_direction(0, 0, -1)
    var down = f.hand_direction(0, -1, 0)
    var reach = f.cm(4.0)
    var sweeps = List[Sweep]()
    if part == HAND_HAIR:
        for k in range(6):
            var x = Float32(2.0) - Float32(0.8) * Float32(k)
            var y = Float32(-4.0) - Float32(0.6) * Float32(k % 3)
            var root = surface_root(skin, f.hand(x, y, 0.3), back, reach)
            sweeps.append(shaft(root, back, down, 0.005, 0.00001))
    else:
        for k in range(INDEX.value, LITTLE.value + 1):
            var joints = finger_joints(arm, Finger(k))
            var middle = (joints[1] + joints[2]) * Float32(0.5)
            var root = surface_root(skin, middle, back, reach)
            sweeps.append(shaft(root, back, down, 0.004, 0.000008))
    var r = sweeps[0].stations[0].ml
    return SweepField(sweeps^, List[Dome](), side, 0.5 * r, 0.5 * r, 0.003)


def hand_hair_distance(
    dimensions: ArmMuscleDimensions,
    part: HandHair,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which group to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return hand_hair_field(dimensions, part, side).distance(point)
