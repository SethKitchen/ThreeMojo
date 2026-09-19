# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Osteometric size of a fibula, and the implicit solid that has that size.

Length comes from Trotter and Gleser 1952. That paper predicts stature
from fibular length. This template inverts the published line so a chosen
stature picks a bone length. The inverse of a stature-from-bone
regression is not the regression of bone length on stature. It is a
modeling choice for a named adult template.

The male line is `stature_cm = 2.68 * fibula_cm + 71.78`. The female line
is `stature_cm = 2.93 * fibula_cm + 59.61`. Those are the American White
adult formulae from 1952.

Every other linear measure is a sex-specific ratio of that length. The
ratios are authored template parameters. They are not a cited osteometric
table.

The solid is a smooth union of a thin elliptical shaft, a proximal head
and styloid, and a distal lateral malleolus.

The bone's own frame is osteological. Plus y is proximal, plus x is
lateral, plus z is anterior, the origin is mid-shaft. A right fibula uses
that frame. A left fibula is the same points with x flipped.

`FibulaDimensions` is fieldwise-constructible. Editing a measurement does
not rebuild landmarks. Call `fibula_dimensions` to resolve a template.
Call `validate` at every public consumer of an edited copy.
"""

from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
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
    smin,
)
from math.vector3 import Vector3
from std.math import max
from units.si import CENTIMETER, Length

comptime MALE_SLOPE = Float32(2.68)
comptime MALE_INTERCEPT_CM = Float32(71.78)
comptime FEMALE_SLOPE = Float32(2.93)
comptime FEMALE_INTERCEPT_CM = Float32(59.61)

comptime MALE_HEAD = Float32(0.062)
comptime MALE_SHAFT_AP = Float32(0.028)
comptime MALE_SHAFT_ML = Float32(0.024)
comptime MALE_MAL_AP = Float32(0.055)
comptime MALE_MAL_ML = Float32(0.040)
comptime MALE_MAL_H = Float32(0.072)
comptime MALE_STYLOID = Float32(0.022)
comptime MALE_BOW = Float32(0.012)

comptime FEMALE_HEAD = Float32(0.058)
comptime FEMALE_SHAFT_AP = Float32(0.026)
comptime FEMALE_SHAFT_ML = Float32(0.022)
comptime FEMALE_MAL_AP = Float32(0.052)
comptime FEMALE_MAL_ML = Float32(0.038)
comptime FEMALE_MAL_H = Float32(0.068)
comptime FEMALE_STYLOID = Float32(0.020)
comptime FEMALE_BOW = Float32(0.011)

comptime SHAFT_ML = Vector3(1, 0, 0)


@fieldwise_init
struct FibulaDimensions(ImplicitlyCopyable):
    """Measured size of one fibula, and the landmarks a skeleton will bind.

    Positions are in meters in the bone's frame. Landmarks come from
    `fibula_dimensions`. Editing a length does not move them.
    """

    var stature: Length
    var sex: Sex
    var side: BodySide
    var length: Length
    var head_diameter: Length
    var midshaft_ap: Length
    var midshaft_ml: Length
    var malleolus_ap: Length
    var malleolus_ml: Length
    var malleolus_height: Length
    var styloid_length: Length
    var lateral_bow: Length
    var head_center: Vector3
    var styloid: Vector3
    var lateral_malleolus: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or side is not valid, if a required length is
                not finite or not positive, if bow is negative, or if a
                landmark is not finite.
        """
        check_spec(self.stature, self.sex, self.side, "fibula")
        positive_length(self.length, "length", "fibula")
        positive_length(self.head_diameter, "head diameter", "fibula")
        positive_length(self.midshaft_ap, "midshaft AP diameter", "fibula")
        positive_length(self.midshaft_ml, "midshaft ML diameter", "fibula")
        positive_length(self.malleolus_ap, "malleolus AP", "fibula")
        positive_length(self.malleolus_ml, "malleolus ML", "fibula")
        positive_length(self.malleolus_height, "malleolus height", "fibula")
        positive_length(self.styloid_length, "styloid", "fibula")
        non_negative_length(self.lateral_bow, "lateral bow", "fibula")
        finite_point(self.head_center, "head center", "fibula")
        finite_point(self.styloid, "styloid", "fibula")
        finite_point(self.lateral_malleolus, "lateral malleolus", "fibula")


struct FibulaField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `FibulaDimensions`."""

    var head: Vector3
    var head_r: Float32
    var styloid: Vector3
    var styloid_r: Vector3
    var malleolus: Vector3
    var malleolus_r: Vector3
    var neck_a: Vector3
    var neck_b: Vector3
    var neck_ra: Float32
    var neck_rb: Float32
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
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FibulaDimensions) raises:
        """Build the solid from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var L = dimensions.length.value
        var head_r = dimensions.head_diameter.value * 0.5
        var ml_mid = dimensions.midshaft_ml.value * 0.5
        var ap_mid = dimensions.midshaft_ap.value * 0.5
        var bow = dimensions.lateral_bow.value
        self.head = dimensions.head_center
        self.head_r = head_r
        self.styloid = dimensions.styloid
        self.styloid_r = Vector3(
            0.35 * dimensions.styloid_length.value,
            0.55 * dimensions.styloid_length.value,
            0.32 * dimensions.styloid_length.value,
        )
        self.malleolus = dimensions.lateral_malleolus
        self.malleolus_r = Vector3(
            dimensions.malleolus_ml.value * 0.5,
            dimensions.malleolus_height.value * 0.5,
            dimensions.malleolus_ap.value * 0.5,
        )
        self.neck_a = Vector3(self.head.x, self.head.y - 0.7 * head_r, self.head.z)
        self.neck_b = Vector3(self.head.x, self.head.y - 2.2 * head_r, self.head.z)
        self.neck_ra = 0.55 * head_r
        self.neck_rb = 1.15 * ml_mid
        var distal = Vector3(
            self.malleolus.x - 0.15 * bow,
            self.malleolus.y + 0.45 * dimensions.malleolus_height.value,
            self.malleolus.z,
        )
        var proximal = Vector3(self.head.x, self.head.y - 1.6 * head_r, self.head.z)
        var bow_off = Vector3(bow, 0, 0)
        self.s0 = bowed_station(0.0, distal, proximal, bow_off)
        self.s1 = bowed_station(0.25, distal, proximal, bow_off)
        self.s2 = bowed_station(0.5, distal, proximal, bow_off)
        self.s3 = bowed_station(0.75, distal, proximal, bow_off)
        self.s4 = bowed_station(1.0, distal, proximal, bow_off)
        self.ml0 = 0.70 * self.malleolus_r.x
        self.ml1 = 1.10 * ml_mid
        self.ml2 = ml_mid
        self.ml3 = 1.08 * ml_mid
        self.ml4 = 0.90 * self.neck_rb
        self.ap0 = 0.65 * self.malleolus_r.z
        self.ap1 = 1.10 * ap_mid
        self.ap2 = ap_mid
        self.ap3 = 1.08 * ap_mid
        self.ap4 = 0.95 * ap_mid
        self.r2 = 0.5 * (ml_mid + ap_mid)
        self.k = 0.012 * L
        self.epsilon = 0.0015 * L
        var box = empty_bounds()
        box.include_sphere(self.head, self.head_r)
        box.include_ellipsoid(self.styloid, self.styloid_r)
        box.include_ellipsoid(self.malleolus, self.malleolus_r)
        box.include_sphere(self.s0, max(self.ml0, self.ap0))
        box.include_sphere(self.s4, max(self.ml4, self.ap4))
        var padded = box.padded(0.018 * L + Float32(0.003))
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the fibula, in meters.

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
            SHAFT_ML,
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
                SHAFT_ML,
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
                SHAFT_ML,
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
                SHAFT_ML,
            ),
            self.k,
        )
        d = smin(d, sd_sphere(point, self.head, self.head_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.styloid, self.styloid_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.malleolus, self.malleolus_r), self.k)
        return smin(
            d,
            sd_segment(
                point, self.neck_a, self.neck_b, self.neck_ra, self.neck_rb
            ),
            self.k,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def fibula_dimensions(
    stature: Length, sex: Sex, side: BodySide = RIGHT
) raises -> FibulaDimensions:
    """Return the osteometric size of a fibula for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        side: `RIGHT` or `LEFT`. A right fibula is the default.

    Returns:
        Lengths and landmark positions in the bone's frame.

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the software range.
    """
    check_spec(stature, sex, side, "fibula")

    var stature_cm = stature.to(CENTIMETER)
    var bone_cm: Float32
    var head_ratio: Float32
    var ap_ratio: Float32
    var ml_ratio: Float32
    var mal_ap: Float32
    var mal_ml: Float32
    var mal_h: Float32
    var styloid_ratio: Float32
    var bow_ratio: Float32
    if sex == MALE:
        bone_cm = (stature_cm - MALE_INTERCEPT_CM) / MALE_SLOPE
        head_ratio = MALE_HEAD
        ap_ratio = MALE_SHAFT_AP
        ml_ratio = MALE_SHAFT_ML
        mal_ap = MALE_MAL_AP
        mal_ml = MALE_MAL_ML
        mal_h = MALE_MAL_H
        styloid_ratio = MALE_STYLOID
        bow_ratio = MALE_BOW
    else:
        bone_cm = (stature_cm - FEMALE_INTERCEPT_CM) / FEMALE_SLOPE
        head_ratio = FEMALE_HEAD
        ap_ratio = FEMALE_SHAFT_AP
        ml_ratio = FEMALE_SHAFT_ML
        mal_ap = FEMALE_MAL_AP
        mal_ml = FEMALE_MAL_ML
        mal_h = FEMALE_MAL_H
        styloid_ratio = FEMALE_STYLOID
        bow_ratio = FEMALE_BOW

    var bone = Length(bone_cm, CENTIMETER)
    var L = bone.value
    var head_d = head_ratio * L
    var head_r = head_d * 0.5
    var styloid_len = styloid_ratio * L
    var bow = bow_ratio * L
    var mal_h_len = mal_h * L
    var head = Vector3(0.02 * L, 0.5 * L - head_r, -0.01 * L)
    var styloid = Vector3(
        head.x + 0.35 * styloid_len,
        head.y + 0.55 * styloid_len,
        head.z - 0.40 * styloid_len,
    )
    var malleolus = Vector3(
        0.04 * L + 0.20 * bow, -0.5 * L + 0.35 * mal_h_len, -0.015 * L
    )
    if side == LEFT:
        head = flip_x(head)
        styloid = flip_x(styloid)
        malleolus = flip_x(malleolus)

    return FibulaDimensions(
        stature,
        sex,
        side,
        bone,
        Length(head_d),
        Length(ap_ratio * L),
        Length(ml_ratio * L),
        Length(mal_ap * L),
        Length(mal_ml * L),
        Length(mal_h_len),
        Length(styloid_len),
        Length(bow),
        head,
        styloid,
        malleolus,
    )


def fibula_distance(
    dimensions: FibulaDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the fibula, in meters.

    Negative is inside. The surface `fibula` meshes is the zero set.

    Args:
        dimensions: A fibula already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return FibulaField(dimensions).distance(point)
