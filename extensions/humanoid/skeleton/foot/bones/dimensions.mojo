# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The twenty-six bones of one foot, as implicit solids.

The foot has no Trotter and Gleser line. Length, breadth and ankle
height are authored sex-specific ratios of stature. They are template
parameters. They are not a cited osteometric table.

The frame origin is the tibial plafond. Plus y is proximal. Plus x is
body-right. Plus z is anterior. The posterior calcaneus meets the leg's
Achilles insertion. The malleoli are the tibia and fibula landmarks,
moved into this frame. A right foot uses that frame. A left foot flips
the authored landmarks on x. The malleoli are already sided.

Each bone is one or two tapered segments. Tarsals, metatarsals and
phalanges share a thin cortical shell over trabecular bone. A medullary
canal is not cut. That is an authored simplification for these short
bones.

`FootDimensions` is fieldwise-constructible. Editing a measurement
does not rebuild landmarks. Call `foot_dimensions` to resolve a
template. Call `validate` at every public consumer of an edited copy.

    var dims = foot_dimensions(Length(6.0, FOOT), MALE)
    var d = bone_distance(dims, CALCANEUS, dims.heel)
"""

from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    check_spec,
    field_gradient,
    finite_point,
    flip_x,
    positive_length,
)
from extensions.humanoid.skeleton.foot.chain import (
    SegmentSet,
    one_segment,
    segment_bounds,
    segment_distance,
    two_segments,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import femur_dimensions
from extensions.humanoid.skeleton.leg.fibula.dimensions import fibula_dimensions
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    fibula_origin,
    knee_dimensions_from_bones,
    tibia_origin,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import tibia_dimensions
from math.vector3 import Vector3
from std.math import min
from units.si import Length

# Authored ratios of stature. Not a cited regression.
comptime MALE_FOOT_LENGTH = Float32(0.152)
comptime MALE_FOOT_BREADTH = Float32(0.058)
comptime MALE_ANKLE_HEIGHT = Float32(0.048)
comptime FEMALE_FOOT_LENGTH = Float32(0.146)
comptime FEMALE_FOOT_BREADTH = Float32(0.054)
comptime FEMALE_ANKLE_HEIGHT = Float32(0.046)

# Cortical shell as a fraction of the smaller end radius.
comptime SHELL_FRACTION = Float32(0.38)


@fieldwise_init
struct FootBone(Equatable, ImplicitlyCopyable, Writable):
    """Which of the twenty-six bones a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named bones is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named foot bone."""
        if self.value < 0:
            return False
        return self.value <= TOE5_DISTAL.value


comptime TALUS = FootBone(0)
comptime CALCANEUS = FootBone(1)
comptime NAVICULAR = FootBone(2)
comptime CUBOID = FootBone(3)
comptime MEDIAL_CUNEIFORM = FootBone(4)
comptime INTERMEDIATE_CUNEIFORM = FootBone(5)
comptime LATERAL_CUNEIFORM = FootBone(6)
comptime METATARSAL_1 = FootBone(7)
comptime METATARSAL_2 = FootBone(8)
comptime METATARSAL_3 = FootBone(9)
comptime METATARSAL_4 = FootBone(10)
comptime METATARSAL_5 = FootBone(11)
comptime HALLUX_PROXIMAL = FootBone(12)
comptime HALLUX_DISTAL = FootBone(13)
comptime TOE2_PROXIMAL = FootBone(14)
comptime TOE2_MIDDLE = FootBone(15)
comptime TOE2_DISTAL = FootBone(16)
comptime TOE3_PROXIMAL = FootBone(17)
comptime TOE3_MIDDLE = FootBone(18)
comptime TOE3_DISTAL = FootBone(19)
comptime TOE4_PROXIMAL = FootBone(20)
comptime TOE4_MIDDLE = FootBone(21)
comptime TOE4_DISTAL = FootBone(22)
comptime TOE5_PROXIMAL = FootBone(23)
comptime TOE5_MIDDLE = FootBone(24)
comptime TOE5_DISTAL = FootBone(25)


@fieldwise_init
struct FootDimensions(ImplicitlyCopyable):
    """Landmarks of one foot in the plafond frame.

    Positions are in meters. Lengths carry units. Landmarks come from
    `foot_dimensions`. Editing a length does not move them.
    """

    var stature: Length
    var sex: Sex
    var side: BodySide
    var length: Length
    var width: Length
    var height: Length
    var heel: Vector3
    var sustentaculum: Vector3
    var calcaneal_anterior: Vector3
    var calcaneal_lateral: Vector3
    var talar_posterior: Vector3
    var talar_body: Vector3
    var talar_head: Vector3
    var talar_lateral: Vector3
    var navicular: Vector3
    var navicular_tuberosity: Vector3
    var navicular_lateral: Vector3
    var cuboid: Vector3
    var medial_cuneiform: Vector3
    var intermediate_cuneiform: Vector3
    var lateral_cuneiform: Vector3
    var mt1_base: Vector3
    var mt1_head: Vector3
    var mt2_base: Vector3
    var mt2_head: Vector3
    var mt3_base: Vector3
    var mt3_head: Vector3
    var mt4_base: Vector3
    var mt4_head: Vector3
    var mt5_base: Vector3
    var mt5_head: Vector3
    var mt5_tuberosity: Vector3
    var hallux_ip: Vector3
    var hallux_tip: Vector3
    var toe2_pip: Vector3
    var toe2_dip: Vector3
    var toe2_tip: Vector3
    var toe3_pip: Vector3
    var toe3_dip: Vector3
    var toe3_tip: Vector3
    var toe4_pip: Vector3
    var toe4_dip: Vector3
    var toe4_tip: Vector3
    var toe5_pip: Vector3
    var toe5_dip: Vector3
    var toe5_tip: Vector3
    var medial_malleolus: Vector3
    var lateral_malleolus: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or side is not valid, if a required length is
                not finite or not positive, or if a landmark is not finite.
        """
        check_spec(self.stature, self.sex, self.side, "foot")
        positive_length(self.length, "length", "foot")
        positive_length(self.width, "breadth", "foot")
        positive_length(self.height, "ankle height", "foot")
        finite_point(self.heel, "heel", "foot")
        finite_point(self.sustentaculum, "sustentaculum", "foot")
        finite_point(self.calcaneal_anterior, "calcaneal anterior", "foot")
        finite_point(self.calcaneal_lateral, "calcaneal lateral", "foot")
        finite_point(self.talar_posterior, "talar posterior", "foot")
        finite_point(self.talar_body, "talar body", "foot")
        finite_point(self.talar_head, "talar head", "foot")
        finite_point(self.talar_lateral, "talar lateral", "foot")
        finite_point(self.navicular, "navicular", "foot")
        finite_point(self.navicular_tuberosity, "navicular tuberosity", "foot")
        finite_point(self.navicular_lateral, "navicular lateral", "foot")
        finite_point(self.cuboid, "cuboid", "foot")
        finite_point(self.medial_cuneiform, "medial cuneiform", "foot")
        finite_point(
            self.intermediate_cuneiform, "intermediate cuneiform", "foot"
        )
        finite_point(self.lateral_cuneiform, "lateral cuneiform", "foot")
        finite_point(self.mt1_base, "first metatarsal base", "foot")
        finite_point(self.mt1_head, "first metatarsal head", "foot")
        finite_point(self.mt2_base, "second metatarsal base", "foot")
        finite_point(self.mt2_head, "second metatarsal head", "foot")
        finite_point(self.mt3_base, "third metatarsal base", "foot")
        finite_point(self.mt3_head, "third metatarsal head", "foot")
        finite_point(self.mt4_base, "fourth metatarsal base", "foot")
        finite_point(self.mt4_head, "fourth metatarsal head", "foot")
        finite_point(self.mt5_base, "fifth metatarsal base", "foot")
        finite_point(self.mt5_head, "fifth metatarsal head", "foot")
        finite_point(self.mt5_tuberosity, "fifth metatarsal tuberosity", "foot")
        finite_point(self.hallux_ip, "hallux interphalangeal joint", "foot")
        finite_point(self.hallux_tip, "hallux tip", "foot")
        finite_point(self.toe2_pip, "second toe proximal joint", "foot")
        finite_point(self.toe2_dip, "second toe distal joint", "foot")
        finite_point(self.toe2_tip, "second toe tip", "foot")
        finite_point(self.toe3_pip, "third toe proximal joint", "foot")
        finite_point(self.toe3_dip, "third toe distal joint", "foot")
        finite_point(self.toe3_tip, "third toe tip", "foot")
        finite_point(self.toe4_pip, "fourth toe proximal joint", "foot")
        finite_point(self.toe4_dip, "fourth toe distal joint", "foot")
        finite_point(self.toe4_tip, "fourth toe tip", "foot")
        finite_point(self.toe5_pip, "fifth toe proximal joint", "foot")
        finite_point(self.toe5_dip, "fifth toe distal joint", "foot")
        finite_point(self.toe5_tip, "fifth toe tip", "foot")
        finite_point(self.medial_malleolus, "medial malleolus", "foot")
        finite_point(self.lateral_malleolus, "lateral malleolus", "foot")


struct FootBoneField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one named foot bone."""

    var segments: SegmentSet
    var k: Float32
    var epsilon: Float32
    var shell: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FootDimensions, part: FootBone) raises:
        """Build one bone from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks.
            part: A named bone.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A foot bone must be one of the twenty-six bones")
        self.segments = _segments(dimensions, part)
        var ends = min(self.segments.ra0, self.segments.rb0)
        self.shell = SHELL_FRACTION * ends
        self.k = Float32(0.35) * self.shell
        self.epsilon = Float32(0.25) * self.shell
        var box = segment_bounds(self.segments, Float32(0.004) + self.shell)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the bone, in meters.

        Negative is inside. Zero is the surface.
        """
        return segment_distance(self.segments, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def foot_dimensions(
    stature: Length, sex: Sex, side: BodySide = RIGHT
) raises -> FootDimensions:
    """Return the landmarks of a foot for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Lengths and landmark positions in the plafond frame.

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the software range.
    """
    check_spec(stature, sex, side, "foot")
    var length_ratio = FEMALE_FOOT_LENGTH
    var breadth_ratio = FEMALE_FOOT_BREADTH
    var height_ratio = FEMALE_ANKLE_HEIGHT
    if sex == MALE:
        length_ratio = MALE_FOOT_LENGTH
        breadth_ratio = MALE_FOOT_BREADTH
        height_ratio = MALE_ANKLE_HEIGHT
    var S = stature.value
    var L = length_ratio * S
    var W = breadth_ratio * S
    var H = height_ratio * S
    var heel = Vector3(0, Float32(-0.042) * S, Float32(-0.052) * S)
    var z0 = heel.z
    var dims = FootDimensions(
        stature,
        sex,
        side,
        Length(L),
        Length(W),
        Length(H),
        heel,
        _place(
            Vector3(Float32(-0.20) * W, Float32(-0.034) * S, z0 + 0.16 * L),
            side,
        ),
        _place(Vector3(0.06 * W, Float32(-0.036) * S, z0 + 0.30 * L), side),
        _place(Vector3(0.22 * W, Float32(-0.038) * S, z0 + 0.18 * L), side),
        _place(Vector3(0.02 * W, Float32(-0.020) * S, z0 + 0.14 * L), side),
        _place(Vector3(0, Float32(-0.008) * S, z0 + 0.22 * L), side),
        _place(
            Vector3(Float32(-0.08) * W, Float32(-0.018) * S, z0 + 0.36 * L),
            side,
        ),
        _place(Vector3(0.20 * W, Float32(-0.016) * S, z0 + 0.20 * L), side),
        _place(
            Vector3(Float32(-0.12) * W, Float32(-0.024) * S, z0 + 0.42 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.30) * W, Float32(-0.028) * S, z0 + 0.40 * L),
            side,
        ),
        _place(Vector3(0.02 * W, Float32(-0.026) * S, z0 + 0.43 * L), side),
        _place(Vector3(0.24 * W, Float32(-0.038) * S, z0 + 0.34 * L), side),
        _place(
            Vector3(Float32(-0.24) * W, Float32(-0.028) * S, z0 + 0.50 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.06) * W, Float32(-0.026) * S, z0 + 0.50 * L),
            side,
        ),
        _place(Vector3(0.08 * W, Float32(-0.030) * S, z0 + 0.48 * L), side),
        _place(
            Vector3(Float32(-0.26) * W, Float32(-0.032) * S, z0 + 0.54 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.40) * W, Float32(-0.040) * S, z0 + 0.76 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.06) * W, Float32(-0.030) * S, z0 + 0.50 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.08) * W, Float32(-0.038) * S, z0 + 0.80 * L),
            side,
        ),
        _place(Vector3(0.08 * W, Float32(-0.032) * S, z0 + 0.52 * L), side),
        _place(Vector3(0.08 * W, Float32(-0.040) * S, z0 + 0.76 * L), side),
        _place(Vector3(0.20 * W, Float32(-0.036) * S, z0 + 0.46 * L), side),
        _place(Vector3(0.24 * W, Float32(-0.042) * S, z0 + 0.72 * L), side),
        _place(Vector3(0.34 * W, Float32(-0.040) * S, z0 + 0.42 * L), side),
        _place(Vector3(0.42 * W, Float32(-0.044) * S, z0 + 0.68 * L), side),
        _place(Vector3(0.40 * W, Float32(-0.042) * S, z0 + 0.34 * L), side),
        _place(
            Vector3(Float32(-0.42) * W, Float32(-0.041) * S, z0 + 0.88 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.42) * W, Float32(-0.042) * S, z0 + 0.96 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.08) * W, Float32(-0.040) * S, z0 + 0.88 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.08) * W, Float32(-0.041) * S, z0 + 0.94 * L),
            side,
        ),
        _place(
            Vector3(Float32(-0.08) * W, Float32(-0.042) * S, z0 + 1.00 * L),
            side,
        ),
        _place(Vector3(0.08 * W, Float32(-0.041) * S, z0 + 0.84 * L), side),
        _place(Vector3(0.08 * W, Float32(-0.042) * S, z0 + 0.90 * L), side),
        _place(Vector3(0.08 * W, Float32(-0.043) * S, z0 + 0.95 * L), side),
        _place(Vector3(0.24 * W, Float32(-0.043) * S, z0 + 0.80 * L), side),
        _place(Vector3(0.25 * W, Float32(-0.044) * S, z0 + 0.86 * L), side),
        _place(Vector3(0.26 * W, Float32(-0.044) * S, z0 + 0.90 * L), side),
        _place(Vector3(0.42 * W, Float32(-0.045) * S, z0 + 0.74 * L), side),
        _place(Vector3(0.43 * W, Float32(-0.045) * S, z0 + 0.79 * L), side),
        _place(Vector3(0.44 * W, Float32(-0.046) * S, z0 + 0.84 * L), side),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
    )
    var malleoli = _malleoli(stature, sex, side)
    dims.medial_malleolus = malleoli[0]
    dims.lateral_malleolus = malleoli[1]
    return dims


def medial_axis(dimensions: FootDimensions) -> Vector3:
    """Return a unit vector from the lateral malleolus toward the medial.

    Args:
        dimensions: Landmarks from `foot_dimensions`.

    Returns:
        A unit vector in the foot frame. A zero span stays zero.
    """
    var axis = dimensions.medial_malleolus - dimensions.lateral_malleolus
    axis.normalize()
    return axis


def bone_distance(
    dimensions: FootDimensions, part: FootBone, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which bone to sample.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return FootBoneField(dimensions, part).distance(point)


def bone_part_label(part: FootBone) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A foot bone, named or not.

    Returns:
        A short American English label, or `"foot bone"` when `part`
        is not named.
    """
    if part == TALUS:
        return "talus"
    if part == CALCANEUS:
        return "calcaneus"
    if part == NAVICULAR:
        return "navicular"
    if part == CUBOID:
        return "cuboid"
    if part == MEDIAL_CUNEIFORM:
        return "medial cuneiform"
    if part == INTERMEDIATE_CUNEIFORM:
        return "intermediate cuneiform"
    if part == LATERAL_CUNEIFORM:
        return "lateral cuneiform"
    if part == METATARSAL_1:
        return "first metatarsal"
    if part == METATARSAL_2:
        return "second metatarsal"
    if part == METATARSAL_3:
        return "third metatarsal"
    if part == METATARSAL_4:
        return "fourth metatarsal"
    if part == METATARSAL_5:
        return "fifth metatarsal"
    if part == HALLUX_PROXIMAL:
        return "hallux proximal phalanx"
    if part == HALLUX_DISTAL:
        return "hallux distal phalanx"
    if part == TOE2_PROXIMAL:
        return "second toe proximal phalanx"
    if part == TOE2_MIDDLE:
        return "second toe middle phalanx"
    if part == TOE2_DISTAL:
        return "second toe distal phalanx"
    if part == TOE3_PROXIMAL:
        return "third toe proximal phalanx"
    if part == TOE3_MIDDLE:
        return "third toe middle phalanx"
    if part == TOE3_DISTAL:
        return "third toe distal phalanx"
    if part == TOE4_PROXIMAL:
        return "fourth toe proximal phalanx"
    if part == TOE4_MIDDLE:
        return "fourth toe middle phalanx"
    if part == TOE4_DISTAL:
        return "fourth toe distal phalanx"
    if part == TOE5_PROXIMAL:
        return "fifth toe proximal phalanx"
    if part == TOE5_MIDDLE:
        return "fifth toe middle phalanx"
    if part == TOE5_DISTAL:
        return "fifth toe distal phalanx"
    return "foot bone"


def named_foot_bones() -> List[FootBone]:
    """Return every named foot bone in anatomical order.

    Returns:
        Talus through the fifth distal phalanx. Twenty-six bones.
    """
    var parts = List[FootBone]()
    parts.append(TALUS)
    parts.append(CALCANEUS)
    parts.append(NAVICULAR)
    parts.append(CUBOID)
    parts.append(MEDIAL_CUNEIFORM)
    parts.append(INTERMEDIATE_CUNEIFORM)
    parts.append(LATERAL_CUNEIFORM)
    parts.append(METATARSAL_1)
    parts.append(METATARSAL_2)
    parts.append(METATARSAL_3)
    parts.append(METATARSAL_4)
    parts.append(METATARSAL_5)
    parts.append(HALLUX_PROXIMAL)
    parts.append(HALLUX_DISTAL)
    parts.append(TOE2_PROXIMAL)
    parts.append(TOE2_MIDDLE)
    parts.append(TOE2_DISTAL)
    parts.append(TOE3_PROXIMAL)
    parts.append(TOE3_MIDDLE)
    parts.append(TOE3_DISTAL)
    parts.append(TOE4_PROXIMAL)
    parts.append(TOE4_MIDDLE)
    parts.append(TOE4_DISTAL)
    parts.append(TOE5_PROXIMAL)
    parts.append(TOE5_MIDDLE)
    parts.append(TOE5_DISTAL)
    return parts^


def _place(point: Vector3, side: BodySide) -> Vector3:
    """Mirror an authored landmark when `side` is left."""
    if side == LEFT:
        return flip_x(point)
    return point


def _malleoli(
    stature: Length, sex: Sex, side: BodySide
) raises -> List[Vector3]:
    """Return the tibial and fibular malleoli in the foot frame."""
    var femur = femur_dimensions(stature, sex, side)
    var tibia = tibia_dimensions(stature, sex, side)
    var fibula = fibula_dimensions(stature, sex, side)
    var patella = patella_dimensions(stature, sex, side)
    var knee = knee_dimensions_from_bones(femur, tibia, fibula, patella)
    var t_origin = tibia_origin(tibia, knee.tibial_thickness)
    var fi_origin = fibula_origin(tibia, t_origin, fibula)
    var ankle = t_origin + tibia.plafond
    var points = List[Vector3]()
    points.append((t_origin + tibia.medial_malleolus) - ankle)
    points.append((fi_origin + fibula.lateral_malleolus) - ankle)
    return points^


def _segments(dimensions: FootDimensions, part: FootBone) -> SegmentSet:
    """Return the tapered segments of one named bone."""
    var L = dimensions.length.value
    var W = dimensions.width.value
    if part == TALUS:
        return two_segments(
            dimensions.talar_posterior,
            dimensions.talar_head,
            0.15 * W,
            0.09 * W,
            dimensions.talar_body,
            dimensions.talar_lateral,
            0.16 * W,
            0.07 * W,
        )
    if part == CALCANEUS:
        return two_segments(
            dimensions.heel,
            dimensions.calcaneal_anterior,
            0.18 * W,
            0.12 * W,
            dimensions.heel,
            dimensions.sustentaculum,
            0.12 * W,
            0.08 * W,
        )
    if part == NAVICULAR:
        return one_segment(
            dimensions.navicular_tuberosity,
            dimensions.navicular_lateral,
            0.08 * W,
            0.09 * W,
        )
    if part == CUBOID:
        return _short(dimensions.cuboid, L, 0.11 * W, 0.10 * W)
    if part == MEDIAL_CUNEIFORM:
        return _short(dimensions.medial_cuneiform, L, 0.075 * W, 0.070 * W)
    if part == INTERMEDIATE_CUNEIFORM:
        return _short(
            dimensions.intermediate_cuneiform, L, 0.060 * W, 0.055 * W
        )
    if part == LATERAL_CUNEIFORM:
        return _short(dimensions.lateral_cuneiform, L, 0.065 * W, 0.060 * W)
    if part == METATARSAL_1:
        return one_segment(
            dimensions.mt1_base, dimensions.mt1_head, 0.075 * W, 0.055 * W
        )
    if part == METATARSAL_2:
        return one_segment(
            dimensions.mt2_base, dimensions.mt2_head, 0.050 * W, 0.038 * W
        )
    if part == METATARSAL_3:
        return one_segment(
            dimensions.mt3_base, dimensions.mt3_head, 0.048 * W, 0.036 * W
        )
    if part == METATARSAL_4:
        return one_segment(
            dimensions.mt4_base, dimensions.mt4_head, 0.046 * W, 0.035 * W
        )
    if part == METATARSAL_5:
        return one_segment(
            dimensions.mt5_tuberosity,
            dimensions.mt5_head,
            0.055 * W,
            0.040 * W,
        )
    if part == HALLUX_PROXIMAL:
        return one_segment(
            dimensions.mt1_head, dimensions.hallux_ip, 0.058 * W, 0.050 * W
        )
    if part == HALLUX_DISTAL:
        return one_segment(
            dimensions.hallux_ip, dimensions.hallux_tip, 0.048 * W, 0.042 * W
        )
    if part == TOE2_PROXIMAL:
        return one_segment(
            dimensions.mt2_head, dimensions.toe2_pip, 0.034 * W, 0.028 * W
        )
    if part == TOE2_MIDDLE:
        return one_segment(
            dimensions.toe2_pip, dimensions.toe2_dip, 0.026 * W, 0.022 * W
        )
    if part == TOE2_DISTAL:
        return one_segment(
            dimensions.toe2_dip, dimensions.toe2_tip, 0.024 * W, 0.020 * W
        )
    if part == TOE3_PROXIMAL:
        return one_segment(
            dimensions.mt3_head, dimensions.toe3_pip, 0.032 * W, 0.026 * W
        )
    if part == TOE3_MIDDLE:
        return one_segment(
            dimensions.toe3_pip, dimensions.toe3_dip, 0.024 * W, 0.020 * W
        )
    if part == TOE3_DISTAL:
        return one_segment(
            dimensions.toe3_dip, dimensions.toe3_tip, 0.022 * W, 0.018 * W
        )
    if part == TOE4_PROXIMAL:
        return one_segment(
            dimensions.mt4_head, dimensions.toe4_pip, 0.030 * W, 0.024 * W
        )
    if part == TOE4_MIDDLE:
        return one_segment(
            dimensions.toe4_pip, dimensions.toe4_dip, 0.022 * W, 0.018 * W
        )
    if part == TOE4_DISTAL:
        return one_segment(
            dimensions.toe4_dip, dimensions.toe4_tip, 0.020 * W, 0.016 * W
        )
    if part == TOE5_PROXIMAL:
        return one_segment(
            dimensions.mt5_head, dimensions.toe5_pip, 0.028 * W, 0.022 * W
        )
    if part == TOE5_MIDDLE:
        return one_segment(
            dimensions.toe5_pip, dimensions.toe5_dip, 0.020 * W, 0.016 * W
        )
    return one_segment(
        dimensions.toe5_dip, dimensions.toe5_tip, 0.018 * W, 0.015 * W
    )


def _short(
    center: Vector3, length: Float32, ra: Float32, rb: Float32
) -> SegmentSet:
    """Return a short proximal-to-distal segment through `center`."""
    var half = 0.018 * length
    return one_segment(
        center + Vector3(0, 0, -half),
        center + Vector3(0, 0, half),
        ra,
        rb,
    )
