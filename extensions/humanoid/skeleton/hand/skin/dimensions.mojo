# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope derived from the modeled anatomy of the hand.

The palm and each digit fit their own loft; see
`extensions.humanoid.skeleton.loft`. The palm's sections run from a
few centimeters above the wrist, where they overlap the arm's skin,
down to the knuckles. They slice the carpals, the metacarpals and the
hand's own muscles, the thumb's metacarpal and its ball of muscle
included, and the lower radius, ulna and forearm tendons, so the
palm's skin meets the forearm's at the same girth. Each
digit's sections run from its knuckle to a little past its fingertip
and slice its phalanges. Every section is closed as a convex hull and
pushed out by its cover. The palm's pad thins over its last sections,
so its cut at the knuckles tucks inside the fingers' bases.

A smooth union joins the palm and the five digits, so the web between
two fingers rises only where the fingers meet the palm. A separate
shell represents the dermis for occupancy and mass.

    var dims = arm_muscle_dimensions(person)
    var d = HandSkinField(dims, RIGHT).distance(p)
"""

from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.arm.bones.dimensions import (
    RADIUS,
    ULNA,
    arm_bone_field,
)
from extensions.humanoid.skeleton.arm.frame import ArmMuscleDimensions
from extensions.humanoid.skeleton.arm.muscles.dimensions import (
    PRONATOR_TERES,
    arm_muscle_field,
    named_arm_muscles,
)
from extensions.humanoid.skeleton.arm.skin.dimensions import (
    LIMB_DERMIS,
    append_stations,
)
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    flip_x,
    smin,
)
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    INDEX,
    PROXIMAL_PHALANX_1,
    THUMB,
    HandBone,
    finger_bones,
    finger_joints,
    finger_scale,
    hand_bone_field,
    named_fingers,
)
from extensions.humanoid.skeleton.hand.muscles.dimensions import (
    hand_muscle_field,
    is_hand_tendon,
    named_hand_muscles,
)
from extensions.humanoid.skeleton.loft import (
    AXIS_Y,
    Loft,
    LoftSample,
    fit_loft,
    loft_distance,
)
from math.vector3 import Vector3
from std.math import max, min

# Sections of the palm and of each digit.
comptime PALM_SECTIONS = 18
comptime DIGIT_SECTIONS = 14
# Soft tissue over the palm's hull and over a finger's bones, in
# template cm: the palm's pad and the finger's pulp and skin.
comptime PALM_COVER = Float32(0.45)
# Sections over which the palm's pad thins toward the knuckles.
comptime PALM_TAPER = 4
comptime DIGIT_COVER = Float32(0.5)


struct HandSkinField(Copyable, DistanceField, Movable):
    """The outer skin surface around one hand's modeled anatomy."""

    var mirror: Bool
    var dermis: Float32
    # The palm's loft first, then the thumb's and each finger's.
    var lofts: List[Loft]
    var blend: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: ArmMuscleDimensions, side: BodySide
    ) raises:
        """Build skin around the hand's actual modeled structures.

        Args:
            dimensions: Arm landmarks and the muscles' radius scale.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If `side` is not valid, or any underlying anatomical
                field refuses its inputs.
        """
        dimensions.validate()
        if not side.is_valid():
            raise Error("A hand side must be RIGHT or LEFT")
        var arm = dimensions.arm.copy()
        var f = arm.frame
        self.mirror = side == LEFT
        self.dermis = LIMB_DERMIS
        self.epsilon = f.cm(0.08)
        self.blend = f.cm(0.5)
        self.lofts = List[Loft]()
        var anywhere = Float32(-1.0e9)
        # The palm: the carpals, the metacarpals and the hand's muscles.
        var palm = List[LoftSample]()
        for index in range(PROXIMAL_PHALANX_1.value):  # pragma: no branch
            append_stations(
                palm, hand_bone_field(arm, HandBone(index), RIGHT), anywhere
            )
        var muscles = named_hand_muscles()
        for index in range(len(muscles)):  # pragma: no branch
            if is_hand_tendon(muscles[index]):
                continue
            append_stations(
                palm,
                hand_muscle_field(dimensions, muscles[index], RIGHT),
                anywhere,
            )
        append_stations(palm, arm_bone_field(arm, RADIUS, RIGHT), anywhere)
        append_stations(palm, arm_bone_field(arm, ULNA, RIGHT), anywhere)
        var forearm = named_arm_muscles()
        for index in range(
            PRONATOR_TERES.value, len(forearm)
        ):  # pragma: no branch
            append_stations(
                palm,
                arm_muscle_field(dimensions, forearm[index], RIGHT),
                anywhere,
            )
        # A little above the lowest knuckle, so the palm's cut lies inside
        # the fingers' skins.
        var knuckle = finger_joints(arm, INDEX)[1]
        var palm_bottom = knuckle.y + f.cm(0.4)
        var palm_top = f.wrist.y + f.cm(3.0)
        self.lofts.append(
            fit_loft(
                palm,
                AXIS_Y,
                palm_bottom,
                palm_top,
                PALM_SECTIONS,
                _palm_covers(f.cm(PALM_COVER), self.dermis),
                2,
            )
        )
        # Each digit: its phalanges, from its knuckle past its tip.
        var digits = named_fingers()
        for d in range(len(digits)):  # pragma: no branch
            var finger = digits[d]
            var bones = finger_bones(finger)
            var samples = List[LoftSample]()
            for b in range(1, len(bones)):  # pragma: no branch
                append_stations(
                    samples, hand_bone_field(arm, bones[b], RIGHT), anywhere
                )
            var joints = finger_joints(arm, finger)
            var s = finger_scale(finger)
            var tip = joints[len(joints) - 1]
            var reach = f.cm(0.6)
            if finger == THUMB:
                reach = f.cm(1.0)
            self.lofts.append(
                fit_loft(
                    samples,
                    AXIS_Y,
                    tip.y - f.cm(0.35),
                    joints[1].y + reach,
                    DIGIT_SECTIONS,
                    _covers(
                        DIGIT_SECTIONS, f.cm(DIGIT_COVER * s) + self.dermis
                    ),
                    1,
                )
            )
        var low = self.lofts[0].low
        var high = self.lofts[0].high
        for index in range(1, len(self.lofts)):  # pragma: no branch
            low = Vector3(
                min(low.x, self.lofts[index].low.x),
                min(low.y, self.lofts[index].low.y),
                min(low.z, self.lofts[index].low.z),
            )
            high = Vector3(
                max(high.x, self.lofts[index].high.x),
                max(high.y, self.lofts[index].high.y),
                max(high.z, self.lofts[index].high.z),
            )
        self.low = low
        self.high = high
        if self.mirror:
            self.low = Vector3(-high.x, low.y, low.z)
            self.high = Vector3(-low.x, high.y, high.z)

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the anatomy-derived outer surface.

        Negative is inside. Zero is the surface.
        """
        var p = point
        if self.mirror:
            p = flip_x(point)
        var d = loft_distance(self.lofts[0], p)
        for index in range(1, len(self.lofts)):  # pragma: no branch
            d = smin(d, loft_distance(self.lofts[index], p), self.blend)
        return d

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct HandSkinLayerField(Copyable, DistanceField, Movable):
    """The dermal shell immediately inside a `HandSkinField`."""

    var outer: HandSkinField
    var thickness: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: ArmMuscleDimensions, side: BodySide
    ) raises:
        """Build the dermal shell around the hand's anatomy.

        Args:
            dimensions: Arm landmarks and the muscles' radius scale.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If the outer field refuses its inputs.
        """
        self.outer = HandSkinField(dimensions, side)
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


def _palm_covers(cover: Float32, dermis: Float32) -> List[Float32]:
    """Return the palm's covers, thinning over its last sections.

    At the knuckles the palm's cut must tuck inside the fingers' bases,
    so the pad thins to a quarter of `cover` there.
    """
    var out = List[Float32]()
    for section in range(PALM_SECTIONS):  # pragma: no branch
        var t = min(Float32(section) / Float32(PALM_TAPER), 1)
        out.append(dermis + cover * (0.25 + 0.75 * t))
    return out^


def _covers(count: Int, cover: Float32) -> List[Float32]:
    """Return one equal cover per section."""
    var out = List[Float32]()
    for _ in range(count):  # pragma: no branch
        out.append(cover)
    return out^
