# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named hair groups of one arm, as short implicit shafts.

Upper-arm roots span the shoulder to the elbow; forearm roots span the
elbow to the wrist, most of them on the back and the thumb side, where
the forearm's hair grows thickest. Each root sits where an outward ray
leaves the arm's skin, and each shaft lies down the arm with a small
outward tilt. Eight representative shafts stand for each group.
Physical shaft radii are authored template values. The mesh uses a
separate diagrammatic radius; see
`extensions.humanoid.skeleton.arm.hair.geometry`.

    var dims = arm_muscle_dimensions(person)
    var d = arm_hair_distance(dims, FOREARM_HAIR, RIGHT, p)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.skin.dimensions import ArmSkinField
from extensions.humanoid.skeleton.field import DistanceField, mix_point
from extensions.humanoid.skeleton.torso.sweep import Dome, Sweep, SweepField
from math.vector3 import Vector3

# Representative shafts per group.
comptime SHAFTS = 8


@fieldwise_init
struct ArmHair(Equatable, ImplicitlyCopyable, Writable):
    """Which named hair group of the arm a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named groups is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named hair group."""
        if self.value < 0:
            return False
        return self.value <= FOREARM_HAIR.value


comptime UPPER_ARM_HAIR = ArmHair(0)
comptime FOREARM_HAIR = ArmHair(1)


def arm_hair_label(part: ArmHair) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A hair group, named or not.

    Returns:
        `"upper arm hair"` or `"forearm hair"`, or `"arm hair"` when
        `part` is not named.
    """
    if part == UPPER_ARM_HAIR:
        return "upper arm hair"
    if part == FOREARM_HAIR:
        return "forearm hair"
    return "arm hair"


def named_arm_hair() -> List[ArmHair]:
    """Return every named arm hair group in a stable order.

    Returns:
        The upper arm's hair, then the forearm's.
    """
    var parts = List[ArmHair]()
    for index in range(FOREARM_HAIR.value + 1):  # pragma: no branch
        parts.append(ArmHair(index))
    return parts^


def surface_root[
    F: DistanceField
](skin: F, inside: Vector3, outward: Vector3, reach: Float32) -> Vector3:
    """Return where a ray from inside a skin leaves it.

    Args:
        skin: A skin field.
        inside: A point inside the skin, in meters.
        outward: The ray's direction.
        reach: How far the ray may run, in meters.

    Returns:
        The exit point, within a micrometer or so.
    """
    var direction = outward
    direction.normalize()
    var low = inside
    var high = inside + direction * reach
    for _ in range(18):  # pragma: no branch
        var middle = (low + high) * Float32(0.5)
        if skin.distance(middle) < 0:
            low = middle
        else:
            high = middle
    return high


def shaft(
    root: Vector3,
    outward: Vector3,
    down: Vector3,
    length: Float32,
    radius: Float32,
) -> Sweep:
    """Return one hair shaft lying down a limb with a small outward tilt.

    Args:
        root: Where it leaves the skin, in meters.
        outward: The skin's outward direction there.
        down: The unit direction down the limb.
        length: The shaft's length, in meters.
        radius: The shaft's radius, in meters.

    Returns:
        The shaft's sweep.
    """
    var away = outward
    away.normalize()
    var lie = down * Float32(0.94) + away * Float32(0.2)
    lie.normalize()
    var hair = Sweep(Vector3(1, 0, 0))
    hair.round(root, radius)
    hair.round(root + lie * length, radius)
    return hair^


def arm_hair_field(
    dimensions: ArmMuscleDimensions, part: ArmHair, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one arm hair group.

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
        raise Error("An arm hair part must be a named hair group")
    if not side.is_valid():
        raise Error("An arm side must be RIGHT or LEFT")
    var f = dimensions.arm.frame
    var skin = ArmSkinField(dimensions, RIGHT)
    var S = dimensions.arm.stature.value
    var a = f.shoulder
    var b = f.elbow
    var radius = Float32(0.000012)
    var length = Float32(0.008)
    # Where around the limb each shaft grows: lateral is plus x,
    # anterior plus z.
    var around = List[Vector3]()
    around.append(Vector3(1, 0, 0))
    around.append(Vector3(0.7, 0, -0.7))
    around.append(Vector3(0, 0, -1))
    around.append(Vector3(0.7, 0, 0.7))
    around.append(Vector3(0, 0, 1))
    around.append(Vector3(-0.6, 0, -0.8))
    around.append(Vector3(1, 0, -0.3))
    around.append(Vector3(0.3, 0, -1))
    if part == FOREARM_HAIR:
        a = f.elbow
        b = f.wrist
        radius = Float32(0.000016)
        length = Float32(0.011)
    var down = b - a
    down.normalize()
    var sweeps = List[Sweep]()
    for k in range(SHAFTS):  # pragma: no branch
        var t = Float32(0.15) + Float32(0.7) * Float32(k) / Float32(SHAFTS - 1)
        var root = surface_root(skin, mix_point(a, b, t), around[k], 0.12 * S)
        sweeps.append(shaft(root, around[k], down, length, radius))
    return SweepField(
        sweeps^, List[Dome](), side, 0.5 * radius, 0.5 * radius, 0.003
    )


def arm_hair_distance(
    dimensions: ArmMuscleDimensions,
    part: ArmHair,
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
    return arm_hair_field(dimensions, part, side).distance(point)
