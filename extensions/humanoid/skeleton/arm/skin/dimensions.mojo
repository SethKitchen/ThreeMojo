# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope derived from the modeled anatomy of the arm.

Transverse sections run from just below the wrist to the top of the
deltoid. Each
one slices the humerus, the radius, the ulna and the arm's muscles,
closes the outline as a convex hull, and adds the subcutaneous fat and
the dermis. See `extensions.humanoid.skeleton.loft`. The fat is thicker
over the upper arm than over the forearm. A separate shell represents
the dermis for occupancy and mass.

The muscles that lie on the scapula, and whatever lies more than
`ARM_REACH` in from the shoulder joint's center, are the torso's skin's
to cover. The arm's skin ends in a cut a centimeter below the wrist,
inside the hand's skin, which reaches up over the lower forearm. See `extensions.humanoid.skeleton.hand.skin`.

    var dims = arm_muscle_dimensions(person)
    var d = ArmSkinField(dims, RIGHT).distance(p)
"""

from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.arm.bones.dimensions import (
    arm_bone_field,
    named_arm_bones,
)
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.muscles.dimensions import (
    INFRASPINATUS,
    SUBSCAPULARIS,
    SUPRASPINATUS,
    TERES_MAJOR,
    TERES_MINOR,
    ArmMuscle,
    arm_muscle_field,
    named_arm_muscles,
)
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    flip_x,
    mix_point,
)
from extensions.humanoid.skeleton.loft import (
    AXIS_Y,
    Loft,
    LoftSample,
    fit_loft,
    loft_distance,
)
from extensions.humanoid.skeleton.torso.sweep import SweepField
from math.vector3 import Vector3
from std.math import max, min

# Sections from the wrist to the top of the deltoid: about fifteen
# millimeters apart on a six-foot arm.
comptime ARM_SKIN_SECTIONS = 44
# How far in from the shoulder joint's center the arm's skin reaches,
# in template cm.
comptime ARM_REACH = Float32(4.0)
# Subcutaneous fat over the upper arm and over the forearm, in meters.
# Authored adult template values.
comptime MALE_UPPER_FAT = Float32(0.0060)
comptime MALE_FORE_FAT = Float32(0.0040)
comptime FEMALE_UPPER_FAT = Float32(0.0120)
comptime FEMALE_FORE_FAT = Float32(0.0070)
comptime LIMB_DERMIS = Float32(0.0015)


def arm_fat(sex: Sex, upper: Bool) -> Float32:
    """Return the subcutaneous fat over the arm, in meters.

    Args:
        sex: `MALE` or `FEMALE`. Any other value gets the female cover.
        upper: True for the upper arm, False for the forearm.

    Returns:
        The authored template thickness.
    """
    if sex == MALE:
        if upper:
            return MALE_UPPER_FAT
        return MALE_FORE_FAT
    if upper:
        return FEMALE_UPPER_FAT
    return FEMALE_FORE_FAT


def lies_on_scapula(part: ArmMuscle) -> Bool:
    """Return True if `part` lies on the scapula, under the torso's skin.

    Args:
        part: An arm muscle.

    Returns:
        True for the rotator cuff and the teres major.
    """
    return (
        part == SUPRASPINATUS
        or part == INFRASPINATUS
        or part == TERES_MINOR
        or part == SUBSCAPULARIS
        or part == TERES_MAJOR
    )


struct ArmSkinField(Copyable, DistanceField, Movable):
    """The outer skin surface around one arm's modeled anatomy."""

    var mirror: Bool
    var dermis: Float32
    var loft: Loft
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: ArmMuscleDimensions, side: BodySide
    ) raises:
        """Build skin around the arm's actual modeled structures.

        Args:
            dimensions: Arm landmarks and the muscles' radius scale.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If `side` is not valid, or any underlying anatomical
                field refuses its inputs.
        """
        dimensions.validate()
        if not side.is_valid():
            raise Error("An arm side must be RIGHT or LEFT")
        var arm = dimensions.arm.copy()
        var f = arm.frame
        self.mirror = side == LEFT
        self.dermis = LIMB_DERMIS
        self.epsilon = f.cm(0.15)
        var inner = f.shoulder.x - f.cm(ARM_REACH)
        var points = List[LoftSample]()
        var bones = named_arm_bones()
        for index in range(len(bones)):  # pragma: no branch
            append_stations(
                points, arm_bone_field(arm, bones[index], RIGHT), inner
            )
        var muscles = named_arm_muscles()
        for index in range(len(muscles)):  # pragma: no branch
            if lies_on_scapula(muscles[index]):
                continue
            append_stations(
                points,
                arm_muscle_field(dimensions, muscles[index], RIGHT),
                inner,
            )
        var bottom = f.wrist.y - f.cm(1.0)
        var top = f.shoulder.y + f.cm(3.6)
        var upper = arm_fat(arm.sex, True) + self.dermis
        var fore = arm_fat(arm.sex, False) + self.dermis
        var covers = List[Float32]()
        var spacing = (top - bottom) / Float32(ARM_SKIN_SECTIONS - 1)
        for section in range(ARM_SKIN_SECTIONS):  # pragma: no branch
            var y = bottom + spacing * Float32(section)
            var t = min(max((y - f.elbow.y) / f.cm(6.0) + 0.5, 0), 1)
            covers.append(fore + (upper - fore) * t)
        self.loft = fit_loft(
            points, AXIS_Y, bottom, top, ARM_SKIN_SECTIONS, covers, 2
        )
        self.low = self.loft.low
        self.high = self.loft.high
        if self.mirror:
            self.low = Vector3(
                -self.loft.high.x, self.loft.low.y, self.loft.low.z
            )
            self.high = Vector3(
                -self.loft.low.x, self.loft.high.y, self.loft.high.z
            )

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the anatomy-derived outer surface.

        Negative is inside. Zero is the surface.
        """
        if self.mirror:
            return loft_distance(self.loft, flip_x(point))
        return loft_distance(self.loft, point)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct ArmSkinLayerField(Copyable, DistanceField, Movable):
    """The dermal shell immediately inside an `ArmSkinField`."""

    var outer: ArmSkinField
    var thickness: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: ArmMuscleDimensions, side: BodySide
    ) raises:
        """Build the dermal shell around the arm's anatomy.

        Args:
            dimensions: Arm landmarks and the muscles' radius scale.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If the outer field refuses its inputs.
        """
        self.outer = ArmSkinField(dimensions, side)
        self.thickness = self.outer.dermis
        self.low = self.outer.low
        self.high = self.outer.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the dermal shell, in meters.

        Negative is inside the dermis. Deep anatomy and exterior space
        are both outside this shell.
        """
        var d = self.outer.distance(point)
        return max(d, -d - self.thickness)


def append_stations(
    mut points: List[LoftSample], field: SweepField, inner: Float32
):
    """Append a right-side field's stations as loft samples.

    A station nearer the midline than `inner` is left out. A station
    joins the one before it; the midpoint between them stands between.
    A sweep's radius along its hint becomes the loft's radius along x
    or z, whichever the hint runs nearer; a hint along y leaves the
    radius across for both.

    Args:
        points: The samples to extend.
        field: A field authored on the right. Its mirror flag is not
            read.
        inner: The least x a station may have, in meters.
    """
    for s in range(len(field.sweeps)):  # pragma: no branch
        var sweep = field.sweeps[s].copy()
        var h = sweep.hint
        var along_z = abs(h.z) > abs(h.x) and abs(h.z) >= abs(h.y)
        var along_y = abs(h.y) > abs(h.x) and abs(h.y) > abs(h.z)
        var first = len(points)
        var last_kept = -1
        for index in range(len(sweep.stations)):  # pragma: no branch
            var station = sweep.stations[index]
            if station.p.x < inner:
                continue
            var ml = station.ml
            var ap = station.ap
            if along_z:
                ml = station.ap
                ap = station.ml
            elif along_y:
                ml = station.ap
            if len(sweep.stations) < 2:
                points.append(LoftSample(station.p, ml, ap, ap, False))
                continue
            var joined = index > 0 and last_kept == index - 1
            if joined:
                var before = points[len(points) - 1]
                points.append(
                    LoftSample(
                        mix_point(before.center, station.p, 0.5),
                        0.5 * (before.ml + ml),
                        0.5 * (before.ap + ap),
                        0,
                        True,
                    )
                )
            points.append(LoftSample(station.p, ml, ap, 0, joined))
            last_kept = index
        if len(points) > first:
            points[first].joins = False
