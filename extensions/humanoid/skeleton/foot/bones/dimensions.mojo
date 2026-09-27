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
    mix_point,
    positive_length,
)
from extensions.humanoid.skeleton.foot.chain import (
    SegmentSet,
    segment_bounds,
    segment_distance,
    three_segments,
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
from std.math import max, min
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

# Where the heel's skin lies behind the tibial plafond, as a fraction of
# foot length. The malleoli stand about a quarter of the way along a
# standing foot.
comptime HEEL_SKIN = Float32(0.245)
# Distances along the foot from the heel's skin, as fractions of foot
# length: the calcaneal tuberosity's center and the second toe's bony
# tip. Authored template proportions, not a cited table.
comptime HEEL_REACH = Float32(0.085)
comptime TOE2_REACH = Float32(0.960)


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
    # Each landmark is authored as a fraction of foot length forward of
    # the heel's skin, of foot breadth lateral of the midline, and of
    # ankle height above the ground. The plafond is the origin, so the
    # ground lies at minus the ankle height.
    var frame = _FootFrame(L, W, H, side)
    var dims = FootDimensions(
        stature,
        sex,
        side,
        Length(L),
        Length(W),
        Length(H),
        # Heel: the calcaneal tuberosity, on the midline above its pad.
        frame.at(HEEL_REACH, 0.00, 0.34),
        frame.at(0.25, -0.20, 0.56),  # sustentaculum tali
        frame.at(0.37, 0.12, 0.36),  # calcaneal anterior process
        frame.at(0.20, 0.17, 0.40),  # calcaneal lateral wall
        frame.at(0.17, 0.02, 0.64),  # talar posterior process
        frame.at(0.25, 0.00, 0.80),  # talar body under the plafond
        frame.at(0.39, -0.08, 0.63),  # talar head
        frame.at(0.25, 0.13, 0.72),  # talar lateral process
        frame.at(0.445, -0.10, 0.57),  # navicular
        frame.at(0.43, -0.27, 0.48),  # navicular tuberosity
        frame.at(0.455, 0.05, 0.58),  # navicular lateral pole
        frame.at(0.44, 0.21, 0.36),  # cuboid
        frame.at(0.525, -0.19, 0.45),  # medial cuneiform
        frame.at(0.53, -0.05, 0.55),  # intermediate cuneiform
        frame.at(0.52, 0.08, 0.49),  # lateral cuneiform
        frame.at(0.585, -0.21, 0.39),  # first metatarsal base
        frame.at(0.745, -0.30, 0.16),  # first metatarsal head
        frame.at(0.575, -0.06, 0.47),  # second metatarsal base
        frame.at(0.775, -0.12, 0.14),  # second metatarsal head
        frame.at(0.575, 0.05, 0.43),  # third metatarsal base
        frame.at(0.760, 0.03, 0.13),  # third metatarsal head
        frame.at(0.560, 0.15, 0.35),  # fourth metatarsal base
        frame.at(0.725, 0.17, 0.13),  # fourth metatarsal head
        frame.at(0.540, 0.26, 0.26),  # fifth metatarsal base
        frame.at(0.680, 0.31, 0.13),  # fifth metatarsal head
        frame.at(0.515, 0.34, 0.20),  # fifth metatarsal tuberosity
        frame.at(0.875, -0.32, 0.16),  # hallux interphalangeal joint
        frame.at(0.975, -0.33, 0.11),  # hallux tip
        frame.at(0.860, -0.13, 0.21),  # second toe PIP
        frame.at(0.915, -0.13, 0.15),  # second toe DIP
        frame.at(TOE2_REACH, -0.13, 0.10),  # second toe tip
        frame.at(0.835, 0.03, 0.20),  # third toe PIP
        frame.at(0.885, 0.03, 0.14),  # third toe DIP
        frame.at(0.925, 0.035, 0.10),  # third toe tip
        frame.at(0.795, 0.18, 0.19),  # fourth toe PIP
        frame.at(0.840, 0.185, 0.14),  # fourth toe DIP
        frame.at(0.880, 0.19, 0.10),  # fourth toe tip
        frame.at(0.745, 0.32, 0.18),  # fifth toe PIP
        frame.at(0.785, 0.33, 0.14),  # fifth toe DIP
        frame.at(0.820, 0.34, 0.10),  # fifth toe tip
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


@fieldwise_init
struct _FootFrame(ImplicitlyCopyable):
    """Turns authored fractions into points in the plafond frame."""

    var length: Float32
    var breadth: Float32
    var height: Float32
    var side: BodySide

    def at(self, along: Float32, lateral: Float32, up: Float32) -> Vector3:
        """Return one landmark.

        Args:
            along: Fraction of foot length forward of the heel's skin.
            lateral: Fraction of foot breadth lateral of the midline.
            up: Fraction of ankle height above the ground.

        Returns:
            The point, mirrored for a left foot.
        """
        return _place(
            Vector3(
                lateral * self.breadth,
                (up - 1) * self.height,
                (along - HEEL_SKIN) * self.length,
            ),
            self.side,
        )


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
    """Return the tapered segments of one named bone.

    A long bone has a base, a shaft and a head, and stops short of the
    next bone by a joint space. A tarsal is a block of two or three
    rounded masses. Radii are authored fractions of foot breadth.
    """
    var W = dimensions.width.value
    var d = dimensions
    if part == TALUS:
        # Body under the plafond, neck, and head at the navicular.
        return three_segments(
            d.talar_posterior,
            d.talar_body,
            0.10 * W,
            0.15 * W,
            d.talar_body,
            d.talar_head,
            0.15 * W,
            0.12 * W,
            d.talar_body,
            d.talar_lateral,
            0.13 * W,
            0.08 * W,
        )
    if part == CALCANEUS:
        # Tuberosity, body and anterior process, with the shelf that
        # holds the talus on the medial side.
        return three_segments(
            d.heel,
            d.calcaneal_lateral,
            0.17 * W,
            0.16 * W,
            d.calcaneal_lateral,
            d.calcaneal_anterior,
            0.16 * W,
            0.12 * W,
            d.calcaneal_lateral,
            d.sustentaculum,
            0.12 * W,
            0.09 * W,
        )
    if part == NAVICULAR:
        return two_segments(
            d.navicular_tuberosity,
            d.navicular,
            0.09 * W,
            0.11 * W,
            d.navicular,
            d.navicular_lateral,
            0.11 * W,
            0.08 * W,
        )
    if part == CUBOID:
        return _block(d.cuboid, dimensions.length.value, 0.12 * W, 0.11 * W)
    if part == MEDIAL_CUNEIFORM:
        return _block(
            d.medial_cuneiform, dimensions.length.value, 0.10 * W, 0.10 * W
        )
    if part == INTERMEDIATE_CUNEIFORM:
        return _block(
            d.intermediate_cuneiform,
            dimensions.length.value,
            0.075 * W,
            0.07 * W,
        )
    if part == LATERAL_CUNEIFORM:
        return _block(
            d.lateral_cuneiform, dimensions.length.value, 0.085 * W, 0.08 * W
        )
    if part == METATARSAL_1:
        return _long_bone(
            d.mt1_base, d.mt1_head, 0.12 * W, 0.065 * W, 0.105 * W
        )
    if part == METATARSAL_2:
        return _long_bone(
            d.mt2_base, d.mt2_head, 0.075 * W, 0.042 * W, 0.066 * W
        )
    if part == METATARSAL_3:
        return _long_bone(
            d.mt3_base, d.mt3_head, 0.072 * W, 0.040 * W, 0.063 * W
        )
    if part == METATARSAL_4:
        return _long_bone(
            d.mt4_base, d.mt4_head, 0.070 * W, 0.040 * W, 0.060 * W
        )
    if part == METATARSAL_5:
        return _long_bone(
            d.mt5_tuberosity, d.mt5_head, 0.085 * W, 0.042 * W, 0.058 * W
        )
    if part == HALLUX_PROXIMAL:
        return _phalanx(
            d.mt1_head, 0.105 * W, d.hallux_ip, 0.085 * W, 0.058 * W
        )
    if part == HALLUX_DISTAL:
        return _phalanx(
            d.hallux_ip, 0.068 * W, d.hallux_tip, 0.066 * W, 0.050 * W
        )
    if part == TOE2_PROXIMAL:
        return _phalanx(d.mt2_head, 0.066 * W, d.toe2_pip, 0.052 * W, 0.036 * W)
    if part == TOE2_MIDDLE:
        return _phalanx(d.toe2_pip, 0.040 * W, d.toe2_dip, 0.042 * W, 0.032 * W)
    if part == TOE2_DISTAL:
        return _phalanx(d.toe2_dip, 0.034 * W, d.toe2_tip, 0.038 * W, 0.030 * W)
    if part == TOE3_PROXIMAL:
        return _phalanx(d.mt3_head, 0.063 * W, d.toe3_pip, 0.050 * W, 0.034 * W)
    if part == TOE3_MIDDLE:
        return _phalanx(d.toe3_pip, 0.038 * W, d.toe3_dip, 0.040 * W, 0.030 * W)
    if part == TOE3_DISTAL:
        return _phalanx(d.toe3_dip, 0.032 * W, d.toe3_tip, 0.036 * W, 0.028 * W)
    if part == TOE4_PROXIMAL:
        return _phalanx(d.mt4_head, 0.060 * W, d.toe4_pip, 0.048 * W, 0.032 * W)
    if part == TOE4_MIDDLE:
        return _phalanx(d.toe4_pip, 0.036 * W, d.toe4_dip, 0.038 * W, 0.028 * W)
    if part == TOE4_DISTAL:
        return _phalanx(d.toe4_dip, 0.030 * W, d.toe4_tip, 0.034 * W, 0.026 * W)
    if part == TOE5_PROXIMAL:
        return _phalanx(d.mt5_head, 0.058 * W, d.toe5_pip, 0.046 * W, 0.031 * W)
    if part == TOE5_MIDDLE:
        return _phalanx(d.toe5_pip, 0.034 * W, d.toe5_dip, 0.036 * W, 0.027 * W)
    return _phalanx(d.toe5_dip, 0.029 * W, d.toe5_tip, 0.032 * W, 0.025 * W)


def _long_bone(
    base: Vector3,
    head: Vector3,
    r_base: Float32,
    r_shaft: Float32,
    r_head: Float32,
) -> SegmentSet:
    """Return a metatarsal: a broad base, a narrow shaft and a round head."""
    var neck = mix_point(base, head, 0.80)
    var waist = mix_point(base, head, 0.22)
    return three_segments(
        base,
        waist,
        r_base,
        r_shaft,
        waist,
        neck,
        r_shaft,
        Float32(0.9) * r_shaft,
        neck,
        head,
        Float32(0.9) * r_shaft,
        r_head,
    )


def _phalanx(
    joint: Vector3,
    joint_radius: Float32,
    end: Vector3,
    r_base: Float32,
    r_shaft: Float32,
) -> SegmentSet:
    """Return a phalanx that starts a joint space past `joint`.

    `joint` is the center of the head before it. The base begins past
    that head's surface, so the joint keeps its cartilage space.
    """
    var run = end - joint
    var reach = run.length()
    var direction = run * (1 / max(reach, Float32(1.0e-6)))
    var base = joint + direction * (joint_radius + Float32(0.6) * r_base)
    var waist = mix_point(base, end, 0.55)
    return two_segments(
        base,
        waist,
        r_base,
        r_shaft,
        waist,
        end,
        r_shaft,
        Float32(0.95) * r_base,
    )


def _block(
    center: Vector3, length: Float32, ra: Float32, rb: Float32
) -> SegmentSet:
    """Return a short tarsal block through `center`."""
    var half = 0.020 * length
    return two_segments(
        center + Vector3(0, 0.25 * ra, -half),
        center + Vector3(0, 0.25 * ra, half),
        ra,
        rb,
        center + Vector3(0, -0.25 * ra, -half),
        center + Vector3(0, -0.25 * ra, half),
        ra,
        rb,
    )
