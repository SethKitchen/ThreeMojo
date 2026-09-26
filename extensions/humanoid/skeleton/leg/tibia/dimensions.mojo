# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Osteometric size of a tibia, and the implicit solid that has that size.

Length comes from Trotter and Gleser 1952. That paper predicts stature
from tibial length. This template inverts the published line so a chosen
stature picks a bone length. The inverse of a stature-from-bone
regression is not the regression of bone length on stature. It is a
modeling choice for a named adult template.

The male line is `stature_cm = 2.52 * tibia_cm + 78.62`. The female line
is `stature_cm = 2.90 * tibia_cm + 61.53`. Those are the American White
adult formulae from 1952. Trotter omitted the medial malleolus from the
length she used in those lines. This template still inverts the published
coefficients. The generated solid includes an authored medial malleolus
beyond that length.

Every other linear measure is a sex-specific ratio of that length. The
ratios are authored template parameters. They are not a cited osteometric
table. Torsion and plateau retroversion are authored adult means.

The solid is a smooth union of a triangular-ish elliptical shaft, both
plateau condyles, an intercondylar eminence, a tibial tuberosity, a
distal plafond, and a medial malleolus. A fibular notch is cut from the
distal lateral face.

The bone's own frame is osteological. Plus y is proximal, plus x is
lateral, plus z is anterior, the origin is mid-shaft. A right tibia uses
that frame. A left tibia is the same points with x flipped.

`TibiaDimensions` is fieldwise-constructible. Editing a measurement does
not rebuild landmarks. Call `tibia_dimensions` to resolve a template.
Call `validate` at every public consumer of an edited copy.
"""

from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    acute_angle,
    bowed_station,
    check_spec,
    empty_bounds,
    field_gradient,
    finite_point,
    flip_x,
    non_negative_length,
    positive_length,
    sd_ellipse_segment,
    sd_ellipsoid,
    sd_segment,
    sd_sphere,
    smax,
    smin,
)
from math.vector3 import Vector3
from std.math import atan2, cos, max, pi, sin
from units.si import (
    Angle,
    CENTIMETER,
    DEGREE,
    Length,
    RADIAN,
)

# Trotter M, Gleser GC. Am J Phys Anthropol. 1952. American White adults.
comptime MALE_SLOPE = Float32(2.52)
comptime MALE_INTERCEPT_CM = Float32(78.62)
comptime FEMALE_SLOPE = Float32(2.90)
comptime FEMALE_INTERCEPT_CM = Float32(61.53)

# Authored ratios of inverted tibial length, adult male template.
comptime MALE_PROX_ML = Float32(0.182)
comptime MALE_PROX_AP = Float32(0.118)
comptime MALE_SHAFT_AP = Float32(0.072)
comptime MALE_SHAFT_ML = Float32(0.054)
comptime MALE_DISTAL_ML = Float32(0.128)
comptime MALE_TUBER = Float32(0.032)
comptime MALE_MALLEOLUS = Float32(0.038)
comptime MALE_BOW = Float32(0.008)
comptime MALE_TORSION_DEG = Float32(23.0)
comptime MALE_RETRO_DEG = Float32(7.0)

# Authored adult female template ratios.
comptime FEMALE_PROX_ML = Float32(0.174)
comptime FEMALE_PROX_AP = Float32(0.112)
comptime FEMALE_SHAFT_AP = Float32(0.068)
comptime FEMALE_SHAFT_ML = Float32(0.052)
comptime FEMALE_DISTAL_ML = Float32(0.122)
comptime FEMALE_TUBER = Float32(0.030)
comptime FEMALE_MALLEOLUS = Float32(0.036)
comptime FEMALE_BOW = Float32(0.007)
comptime FEMALE_TORSION_DEG = Float32(27.0)
comptime FEMALE_RETRO_DEG = Float32(8.0)


@fieldwise_init
struct TibiaDimensions(ImplicitlyCopyable):
    """Measured size of one tibia, and the landmarks a skeleton will bind.

    Positions are in meters in the bone's frame, as a `Vector3` always is.
    Lengths and angles carry units. Landmarks come from `tibia_dimensions`.
    Editing a length does not move them.
    """

    var stature: Length
    var sex: Sex
    var side: BodySide
    var length: Length
    var proximal_width: Length
    var proximal_ap: Length
    var midshaft_ap: Length
    var midshaft_ml: Length
    var distal_width: Length
    var tuberosity_offset: Length
    var malleolus_drop: Length
    var anterior_bow: Length
    var torsion: Angle
    var retroversion: Angle
    var medial_condyle: Vector3
    var lateral_condyle: Vector3
    var eminence: Vector3
    var tuberosity: Vector3
    var plafond: Vector3
    var medial_malleolus: Vector3
    var fibular_notch: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or side is not valid, if a required length is
                not finite or not positive, if bow is negative, if an
                angle is not finite or not acute, or if a landmark is
                not finite.
        """
        check_spec(self.stature, self.sex, self.side, "tibia")
        positive_length(self.length, "length", "tibia")
        positive_length(self.proximal_width, "proximal width", "tibia")
        positive_length(self.proximal_ap, "proximal AP depth", "tibia")
        positive_length(self.midshaft_ap, "midshaft AP diameter", "tibia")
        positive_length(self.midshaft_ml, "midshaft ML diameter", "tibia")
        positive_length(self.distal_width, "distal width", "tibia")
        positive_length(self.tuberosity_offset, "tuberosity", "tibia")
        positive_length(self.malleolus_drop, "malleolus drop", "tibia")
        non_negative_length(self.anterior_bow, "anterior bow", "tibia")
        acute_angle(self.torsion, "torsion", "tibia")
        acute_angle(self.retroversion, "retroversion", "tibia")
        finite_point(self.medial_condyle, "medial condyle", "tibia")
        finite_point(self.lateral_condyle, "lateral condyle", "tibia")
        finite_point(self.eminence, "eminence", "tibia")
        finite_point(self.tuberosity, "tuberosity", "tibia")
        finite_point(self.plafond, "plafond", "tibia")
        finite_point(self.medial_malleolus, "medial malleolus", "tibia")
        finite_point(self.fibular_notch, "fibular notch", "tibia")


struct TibiaField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `TibiaDimensions`.

    `distance` is in meters, negative inside the bone. The shaft uses
    independent AP and ML radii. Distal cross-sections follow torsion.
    """

    var medial: Vector3
    var medial_r: Vector3
    var lateral: Vector3
    var lateral_r: Vector3
    var plateau: Vector3
    var plateau_r: Vector3
    var eminence: Vector3
    var eminence_r: Float32
    var tuberosity: Vector3
    var tuberosity_r: Vector3
    var plafond: Vector3
    var plafond_r: Vector3
    var malleolus: Vector3
    var malleolus_r: Vector3
    var notch_a: Vector3
    var notch_b: Vector3
    var notch_r: Float32
    var crest_a: Vector3
    var crest_b: Vector3
    var crest_r: Float32
    var s0: Vector3
    var s1: Vector3
    var s2: Vector3
    var s3: Vector3
    var s4: Vector3
    var ml0: Float32
    var ml1: Float32
    var ml2: Float32
    var ml3: Float32
    var ml4: Float32
    var ap0: Float32
    var ap1: Float32
    var ap2: Float32
    var ap3: Float32
    var ap4: Float32
    var r2: Float32
    var torsion: Float32
    var k: Float32
    var k_notch: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: TibiaDimensions) raises:
        """Build the solid from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks. Must already pass `validate`,
                or this constructor runs `validate` itself.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var L = dimensions.length.value
        var W = dimensions.proximal_width.value
        var D = dimensions.distal_width.value
        var bow = dimensions.anterior_bow.value
        var ml_mid = dimensions.midshaft_ml.value * 0.5
        var ap_mid = dimensions.midshaft_ap.value * 0.5
        var r_mid = 0.5 * (ml_mid + ap_mid)
        self.medial = dimensions.medial_condyle
        self.medial_r = Vector3(
            0.24 * W, 0.085 * W, 0.38 * dimensions.proximal_ap.value
        )
        self.lateral = dimensions.lateral_condyle
        self.lateral_r = Vector3(
            0.22 * W, 0.080 * W, 0.36 * dimensions.proximal_ap.value
        )
        self.plateau = Vector3(
            0.5 * (self.medial.x + self.lateral.x),
            0.5 * (self.medial.y + self.lateral.y) - 0.02 * W,
            0.5 * (self.medial.z + self.lateral.z),
        )
        self.plateau_r = Vector3(
            0.44 * W, 0.085 * W, 0.34 * dimensions.proximal_ap.value
        )
        self.eminence = dimensions.eminence
        self.eminence_r = 0.045 * W
        self.tuberosity = dimensions.tuberosity
        self.tuberosity_r = Vector3(
            0.45 * dimensions.tuberosity_offset.value,
            1.10 * dimensions.tuberosity_offset.value,
            0.38 * dimensions.tuberosity_offset.value,
        )
        self.plafond = dimensions.plafond
        self.plafond_r = Vector3(0.38 * D, 0.14 * D, 0.28 * D)
        self.malleolus = dimensions.medial_malleolus
        self.malleolus_r = Vector3(
            0.28 * D, 0.55 * dimensions.malleolus_drop.value, 0.32 * D
        )
        self.notch_a = dimensions.fibular_notch
        self.notch_b = Vector3(
            dimensions.fibular_notch.x,
            dimensions.fibular_notch.y + 0.04 * L,
            dimensions.fibular_notch.z,
        )
        self.notch_r = 0.16 * D
        var distal = Vector3(
            0.5 * (self.plafond.x + self.malleolus.x),
            self.plafond.y + 0.06 * L,
            0.5 * (self.plafond.z + self.malleolus.z),
        )
        var proximal = Vector3(
            0.5 * (self.medial.x + self.lateral.x),
            0.5 * (self.medial.y + self.lateral.y) - 0.06 * L,
            0.5 * (self.medial.z + self.lateral.z),
        )
        var bow_off = Vector3(0, 0, bow)
        self.s0 = bowed_station(0.0, distal, proximal, bow_off)
        self.s1 = bowed_station(0.25, distal, proximal, bow_off)
        self.s2 = bowed_station(0.5, distal, proximal, bow_off)
        self.s3 = bowed_station(0.75, distal, proximal, bow_off)
        self.s4 = bowed_station(1.0, distal, proximal, bow_off)
        self.ml0 = 0.92 * (D * 0.5)
        self.ml1 = 1.15 * ml_mid
        self.ml2 = ml_mid
        self.ml3 = 1.18 * ml_mid
        self.ml4 = 0.70 * (W * 0.5)
        self.ap0 = 0.70 * self.plafond_r.z
        self.ap1 = 1.12 * ap_mid
        self.ap2 = ap_mid
        self.ap3 = 1.15 * ap_mid
        self.ap4 = 0.55 * dimensions.proximal_ap.value
        self.r2 = r_mid
        self.crest_a = Vector3(self.s1.x, self.s1.y, self.s1.z + 0.85 * ap_mid)
        self.crest_b = Vector3(self.s3.x, self.s3.y, self.s3.z + 0.85 * ap_mid)
        self.crest_r = 0.28 * r_mid
        self.torsion = dimensions.torsion.value
        self.k = 0.010 * L
        self.k_notch = 0.006 * L
        self.epsilon = 0.0015 * L
        var box = empty_bounds()
        box.include_ellipsoid(self.medial, self.medial_r)
        box.include_ellipsoid(self.lateral, self.lateral_r)
        box.include_ellipsoid(self.plateau, self.plateau_r)
        box.include_sphere(self.eminence, self.eminence_r)
        box.include_ellipsoid(self.tuberosity, self.tuberosity_r)
        box.include_ellipsoid(self.plafond, self.plafond_r)
        box.include_ellipsoid(self.malleolus, self.malleolus_r)
        box.include_sphere(self.s0, max(self.ml0, self.ap0))
        box.include_sphere(self.s4, max(self.ml4, self.ap4))
        var padded = box.padded(0.020 * L + Float32(0.004))
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the tibia, in meters.

        Negative is inside. Zero is the surface.
        """
        var d = sd_ellipse_segment(
            point,
            self.s0,
            self.s1,
            self.ml0,
            self.ap0,
            self.ml1,
            self.ap1,
            _ml_hint(self.torsion, 0.125),
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.s1,
                self.s2,
                self.ml1,
                self.ap1,
                self.ml2,
                self.ap2,
                _ml_hint(self.torsion, 0.375),
            ),
            self.k,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.s2,
                self.s3,
                self.ml2,
                self.ap2,
                self.ml3,
                self.ap3,
                _ml_hint(self.torsion, 0.625),
            ),
            self.k,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.s3,
                self.s4,
                self.ml3,
                self.ap3,
                self.ml4,
                self.ap4,
                _ml_hint(self.torsion, 0.875),
            ),
            self.k,
        )
        d = smin(d, sd_ellipsoid(point, self.medial, self.medial_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.lateral, self.lateral_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.plateau, self.plateau_r), self.k)
        d = smin(d, sd_sphere(point, self.eminence, self.eminence_r), self.k)
        d = smin(
            d,
            sd_segment(
                point,
                self.s4,
                self.tuberosity,
                0.38 * self.ap4,
                0.55 * self.tuberosity_r.x,
            ),
            self.k,
        )
        d = smin(
            d, sd_ellipsoid(point, self.tuberosity, self.tuberosity_r), self.k
        )
        d = smin(d, sd_ellipsoid(point, self.plafond, self.plafond_r), self.k)
        d = smin(
            d, sd_ellipsoid(point, self.malleolus, self.malleolus_r), self.k
        )
        d = smin(
            d,
            sd_segment(
                point, self.crest_a, self.crest_b, self.crest_r, self.crest_r
            ),
            self.k,
        )
        var notch = sd_segment(
            point, self.notch_a, self.notch_b, self.notch_r, self.notch_r
        )
        return smax(d, -notch, self.k_notch)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def tibia_dimensions(
    stature: Length, sex: Sex, side: BodySide = RIGHT
) raises -> TibiaDimensions:
    """Return the osteometric size of a tibia for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        side: `RIGHT` or `LEFT`. A right tibia is the default.

    Returns:
        Lengths, angles and landmark positions in the bone's frame.
        Distal landmarks include the authored external torsion.

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the software range.
    """
    check_spec(stature, sex, side, "tibia")

    var stature_cm = stature.to(CENTIMETER)
    var bone_cm: Float32
    var prox_ml: Float32
    var prox_ap: Float32
    var ap_ratio: Float32
    var ml_ratio: Float32
    var distal_ratio: Float32
    var tuber_ratio: Float32
    var mal_ratio: Float32
    var bow_ratio: Float32
    var torsion_deg: Float32
    var retro_deg: Float32
    if sex == MALE:
        bone_cm = (stature_cm - MALE_INTERCEPT_CM) / MALE_SLOPE
        prox_ml = MALE_PROX_ML
        prox_ap = MALE_PROX_AP
        ap_ratio = MALE_SHAFT_AP
        ml_ratio = MALE_SHAFT_ML
        distal_ratio = MALE_DISTAL_ML
        tuber_ratio = MALE_TUBER
        mal_ratio = MALE_MALLEOLUS
        bow_ratio = MALE_BOW
        torsion_deg = MALE_TORSION_DEG
        retro_deg = MALE_RETRO_DEG
    else:
        bone_cm = (stature_cm - FEMALE_INTERCEPT_CM) / FEMALE_SLOPE
        prox_ml = FEMALE_PROX_ML
        prox_ap = FEMALE_PROX_AP
        ap_ratio = FEMALE_SHAFT_AP
        ml_ratio = FEMALE_SHAFT_ML
        distal_ratio = FEMALE_DISTAL_ML
        tuber_ratio = FEMALE_TUBER
        mal_ratio = FEMALE_MALLEOLUS
        bow_ratio = FEMALE_BOW
        torsion_deg = FEMALE_TORSION_DEG
        retro_deg = FEMALE_RETRO_DEG

    var bone = Length(bone_cm, CENTIMETER)
    var L = bone.value
    var W = prox_ml * L
    var AP = prox_ap * L
    var D = distal_ratio * L
    var tuber = tuber_ratio * L
    var mal = mal_ratio * L
    var bow = bow_ratio * L
    var torsion = Angle(torsion_deg, DEGREE)
    var retro = Angle(retro_deg, DEGREE)
    var condyle_y = 0.5 * L - 0.08 * AP
    var medial = Vector3(-0.28 * W, condyle_y, 0.04 * AP)
    var lateral = Vector3(0.26 * W, condyle_y - 0.01 * L, -0.02 * AP)
    var eminence = Vector3(0.02 * W, 0.5 * L, 0.02 * AP)
    var tuberosity = Vector3(
        -0.04 * W,
        0.5 * L - 0.12 * L,
        0.34 * AP + 0.55 * tuber,
    )
    var pitch = -retro.value
    medial = _pitch(medial, pitch)
    lateral = _pitch(lateral, pitch)
    eminence = _pitch(eminence, pitch)
    tuberosity = _pitch(tuberosity, pitch)
    var twist = torsion.value
    var mal_y = -0.5 * L - 0.55 * mal
    var notch_y = -0.5 * L + 0.10 * D
    var plafond = _twist(Vector3(0.04 * D, -0.5 * L + 0.08 * D, 0), twist)
    var malleolus = _twist(Vector3(-0.42 * D, mal_y, 0), twist)
    var notch = _twist(Vector3(0.46 * D, notch_y, 0), twist)
    if side == LEFT:
        medial = flip_x(medial)
        lateral = flip_x(lateral)
        eminence = flip_x(eminence)
        tuberosity = flip_x(tuberosity)
        plafond = flip_x(plafond)
        malleolus = flip_x(malleolus)
        notch = flip_x(notch)

    return TibiaDimensions(
        stature,
        sex,
        side,
        bone,
        Length(W),
        Length(AP),
        Length(ap_ratio * L),
        Length(ml_ratio * L),
        Length(D),
        Length(tuber),
        Length(mal),
        Length(bow),
        torsion,
        retro,
        medial,
        lateral,
        eminence,
        tuberosity,
        plafond,
        malleolus,
        notch,
    )


def measured_torsion(dimensions: TibiaDimensions) raises -> Angle:
    """Return the xz angle between proximal and distal mediolateral chords.

    The proximal chord is `lateral_condyle - medial_condyle`. The distal
    chord is `fibular_notch - medial_malleolus`. That is the definition
    `torsion` is constructed to match.

    Args:
        dimensions: A tibia already sized from stature and sex.

    Returns:
        The measured angle, in radians inside the `Angle`.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    dimensions.validate()
    var dist = dimensions.fibular_notch - dimensions.medial_malleolus
    var x = dist.x
    if dimensions.side == LEFT:
        x = -x
    var ang = atan2(dist.z, x)
    if ang < 0:
        ang = -ang
    if ang > pi * Float32(0.5):
        ang = pi - ang
    return Angle(ang, RADIAN)


def tibia_distance(
    dimensions: TibiaDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the tibia, in meters.

    Negative is inside. The surface `tibia` meshes is the zero set.

    Args:
        dimensions: A tibia already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    var field = TibiaField(dimensions)
    return field.distance(point)


def _pitch(point: Vector3, angle: Float32) -> Vector3:
    """Rotate `point` about plus x by `angle` radians."""
    var c = cos(angle)
    var s = sin(angle)
    return Vector3(
        point.x, point.y * c - point.z * s, point.y * s + point.z * c
    )


def _twist(point: Vector3, angle: Float32) -> Vector3:
    """Rotate `point` about plus y by `angle` radians."""
    var c = cos(angle)
    var s = sin(angle)
    return Vector3(
        point.x * c - point.z * s, point.y, point.x * s + point.z * c
    )


def _ml_hint(torsion: Float32, t_from_distal: Float32) -> Vector3:
    """Return the mediolateral axis at a shaft fraction from distal.

    Distal uses the full torsion. Proximal is unrotated bone x.
    """
    var a = torsion * (Float32(1) - t_from_distal)
    return Vector3(cos(a), 0, sin(a))
