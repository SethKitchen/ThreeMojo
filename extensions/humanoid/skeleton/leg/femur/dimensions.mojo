# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Osteometric size of a femur, and the implicit solid that has that size.

Length comes from Trotter and Gleser 1952. That paper predicts stature
from maximum femoral length. This template inverts the published line so
a chosen stature picks a bone length. The inverse of a stature-from-bone
regression is not the regression of bone length on stature. It is a
modeling choice for a named adult template, not a uniquely determined
measurement for a person of that height.

The male line is `stature_cm = 2.38 * femur_cm + 61.41`. The female line
is `stature_cm = 2.47 * femur_cm + 54.10`. Those are the American White
adult formulae from 1952. Forensic software uses them when no population
is named. Other populations and later samples use different coefficients.
A six foot male therefore gets a femur of 51.04 cm on this template.

Every other linear measure is a sex-specific ratio of that length. The
ratios are authored template parameters. They are not a cited osteometric
table. Neck-shaft angle, anteversion and the bicondylar angle are authored
adult means for the two templates. Thickness scales with the bone, not
with stature on its own.

The solid is a smooth union of anatomical parts: a bowed tapered shaft
with an elliptical cross-section, a neck, a spherical head, both
trochanters, both condyles, a patellar surface, a linea aspera, and a
notch cut between the condyles. The mesh builder in `geometry` takes the
zero set of that field.

The bone's own frame is osteological. Plus y is proximal, plus x is
lateral, plus z is anterior, the origin is mid-shaft. A right femur uses
that frame. A left femur is the same points with x flipped.

`FemurDimensions` is fieldwise-constructible. Editing a measurement does
not rebuild landmarks. Call `femur_dimensions` to resolve a template.
Call `validate` at every public consumer of an edited copy.
"""

from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    acute_angle,
    bowed_station,
    check_spec,
    clamp_unit,
    empty_bounds,
    field_gradient,
    finite_angle,
    finite_point,
    flip_x,
    non_negative_length,
    open_angle,
    positive_length,
    sd_ellipse_segment,
    sd_ellipsoid,
    sd_segment,
    sd_sphere,
    smax,
    smin,
)
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import acos, cos, max, min, sin
from units.si import (
    Angle,
    CENTIMETER,
    DEGREE,
    Length,
    RADIAN,
)

# Mediolateral hint for an unrotated shaft ellipse.
comptime SHAFT_ML = Vector3(1, 0, 0)

# Trotter M, Gleser GC. Am J Phys Anthropol. 1952. Table 13, American
# White adults, maximum femoral length in centimeters.
comptime MALE_SLOPE = Float32(2.38)
comptime MALE_INTERCEPT_CM = Float32(61.41)
comptime FEMALE_SLOPE = Float32(2.47)
comptime FEMALE_INTERCEPT_CM = Float32(54.10)

# Authored ratios of maximum femoral length, adult male template.
comptime MALE_HEAD = Float32(0.1030)
comptime MALE_NECK = Float32(0.1073)
comptime MALE_BICONDYLAR = Float32(0.1803)
comptime MALE_SHAFT_AP = Float32(0.0631)
comptime MALE_SHAFT_ML = Float32(0.0579)
comptime MALE_GT = Float32(0.0687)
comptime MALE_LT = Float32(0.0386)
comptime MALE_BOW = Float32(0.0129)
# Authored neck-shaft (CCD) angle, anteversion and femoral obliquity.
comptime MALE_CCD_DEG = Float32(126.0)
comptime MALE_ANTEVERSION_DEG = Float32(12.0)
comptime MALE_OBLIQUITY_DEG = Float32(9.0)

# Authored adult female template ratios.
comptime FEMALE_HEAD = Float32(0.0977)
comptime FEMALE_NECK = Float32(0.1065)
comptime FEMALE_BICONDYLAR = Float32(0.1736)
comptime FEMALE_SHAFT_AP = Float32(0.0602)
comptime FEMALE_SHAFT_ML = Float32(0.0567)
comptime FEMALE_GT = Float32(0.0648)
comptime FEMALE_LT = Float32(0.0370)
comptime FEMALE_BOW = Float32(0.0120)
comptime FEMALE_CCD_DEG = Float32(128.0)
comptime FEMALE_ANTEVERSION_DEG = Float32(14.0)
comptime FEMALE_OBLIQUITY_DEG = Float32(11.0)


@fieldwise_init
struct FemurDimensions(ImplicitlyCopyable):
    """Measured size of one femur, and the landmarks a skeleton will bind.

    Positions are in meters in the bone's frame, as a `Vector3` always is.
    Lengths and angles carry units. Landmarks come from `femur_dimensions`.
    Editing a length does not move them.
    """

    var stature: Length
    var sex: Sex
    var side: BodySide
    var length: Length
    var head_diameter: Length
    var neck_length: Length
    var neck_shaft_angle: Angle
    var anteversion: Angle
    var bicondylar_width: Length
    var midshaft_ap: Length
    var midshaft_ml: Length
    var greater_trochanter_offset: Length
    var lesser_trochanter_offset: Length
    var anterior_bow: Length
    var bicondylar_angle: Angle
    var head_center: Vector3
    var neck_base: Vector3
    var greater_trochanter: Vector3
    var lesser_trochanter: Vector3
    var medial_condyle: Vector3
    var lateral_condyle: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or side is not valid, if a required length is
                not finite or not positive, if bow is negative, if an
                angle is not finite, if the neck-shaft angle is not
                between 0 and 180 degrees, or if a landmark is not finite.
        """
        check_spec(self.stature, self.sex, self.side, "femur")
        positive_length(self.length, "length", "femur")
        positive_length(self.head_diameter, "head diameter", "femur")
        positive_length(self.neck_length, "neck length", "femur")
        positive_length(self.bicondylar_width, "bicondylar width", "femur")
        positive_length(self.midshaft_ap, "midshaft AP diameter", "femur")
        positive_length(self.midshaft_ml, "midshaft ML diameter", "femur")
        positive_length(
            self.greater_trochanter_offset, "greater trochanter", "femur"
        )
        positive_length(
            self.lesser_trochanter_offset, "lesser trochanter", "femur"
        )
        non_negative_length(self.anterior_bow, "anterior bow", "femur")
        open_angle(self.neck_shaft_angle, "neck-shaft angle", "femur")
        finite_angle(self.anteversion, "anteversion", "femur")
        acute_angle(self.bicondylar_angle, "bicondylar angle", "femur")
        finite_point(self.head_center, "head center", "femur")
        finite_point(self.neck_base, "neck base", "femur")
        finite_point(self.greater_trochanter, "greater trochanter", "femur")
        finite_point(self.lesser_trochanter, "lesser trochanter", "femur")
        finite_point(self.medial_condyle, "medial condyle", "femur")
        finite_point(self.lateral_condyle, "lateral condyle", "femur")


struct FemurField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `FemurDimensions`.

    `distance` is in meters, negative inside the bone. `geometry` meshes
    the zero set. The shaft uses independent AP and ML radii.
    """

    var head_center: Vector3
    var head_r: Float32
    var neck_base: Vector3
    var neck_r: Float32
    var gt: Vector3
    var gt_r: Vector3
    var gt_bridge_a: Vector3
    var gt_bridge_b: Vector3
    var gt_bridge_ra: Float32
    var gt_bridge_rb: Float32
    var lt: Vector3
    var lt_r: Vector3
    var medial: Vector3
    var medial_r: Vector3
    var lateral: Vector3
    var lateral_r: Vector3
    var distal_metaphysis: Vector3
    var distal_metaphysis_r: Vector3
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
    var linea_a: Vector3
    var linea_b: Vector3
    var linea_r: Float32
    var notch_a: Vector3
    var notch_b: Vector3
    var notch_r: Float32
    var patella: Vector3
    var patella_r: Vector3
    var k: Float32
    var k_notch: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FemurDimensions) raises:
        """Build the solid from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks. Must already pass `validate`,
                or this constructor runs `validate` itself.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var L = dimensions.length.value
        var head_r = dimensions.head_diameter.value * 0.5
        var W = dimensions.bicondylar_width.value
        var bow = dimensions.anterior_bow.value
        var gt_off = dimensions.greater_trochanter_offset.value
        var lt_off = dimensions.lesser_trochanter_offset.value
        var ml_mid = dimensions.midshaft_ml.value * 0.5
        var ap_mid = dimensions.midshaft_ap.value * 0.5
        var r_mid = 0.5 * (ml_mid + ap_mid)
        var condyle_ry = 0.32 * W
        var condyle_rz = 0.34 * W
        var condyle_rx = 0.25 * W
        self.head_center = dimensions.head_center
        self.head_r = head_r
        self.neck_base = dimensions.neck_base
        self.neck_r = 0.58 * head_r
        self.gt = dimensions.greater_trochanter
        self.gt_r = Vector3(0.42 * gt_off, 0.62 * head_r, 0.34 * gt_off)
        self.gt_bridge_a = self.neck_base
        self.gt_bridge_b = self.gt
        self.gt_bridge_ra = 0.82 * self.neck_r
        self.gt_bridge_rb = 0.70 * min(self.gt_r.x, self.gt_r.z)
        self.lt = dimensions.lesser_trochanter
        self.lt_r = Vector3(0.36 * lt_off, 0.42 * lt_off, 0.32 * lt_off)
        self.medial = dimensions.medial_condyle
        self.medial_r = Vector3(
            condyle_rx * 1.06, condyle_ry * 1.04, condyle_rz * 1.04
        )
        self.lateral = dimensions.lateral_condyle
        self.lateral_r = Vector3(condyle_rx, condyle_ry, condyle_rz)
        self.distal_metaphysis = Vector3(
            0.5 * (self.medial.x + self.lateral.x),
            0.5 * (self.medial.y + self.lateral.y) + 0.65 * condyle_ry,
            0.5 * (self.medial.z + self.lateral.z),
        )
        self.distal_metaphysis_r = Vector3(
            0.36 * W, 0.42 * condyle_ry, 0.42 * condyle_rz
        )
        var y0 = 0.5 * (self.medial.y + self.lateral.y) + 0.085 * L
        var y4 = self.neck_base.y
        var x0 = 0.5 * (self.medial.x + self.lateral.x)
        var x4 = self.neck_base.x
        var distal = Vector3(x0, y0, 0)
        var proximal = Vector3(x4, y4, 0)
        var bow_off = Vector3(0, 0, bow)
        self.s0 = bowed_station(0.0, distal, proximal, bow_off)
        self.s1 = bowed_station(0.25, distal, proximal, bow_off)
        self.s2 = bowed_station(0.5, distal, proximal, bow_off)
        self.s3 = bowed_station(0.75, distal, proximal, bow_off)
        self.s4 = bowed_station(1.0, distal, proximal, bow_off)
        self.ml0 = 1.35 * ml_mid
        self.ml1 = 1.10 * ml_mid
        self.ml2 = ml_mid
        self.ml3 = 1.12 * ml_mid
        self.ml4 = 1.28 * ml_mid
        self.ap0 = 1.35 * ap_mid
        self.ap1 = 1.10 * ap_mid
        self.ap2 = ap_mid
        self.ap3 = 1.12 * ap_mid
        self.ap4 = 1.28 * ap_mid
        self.r2 = r_mid
        var posterior = 0.85 * r_mid + 0.20 * bow
        self.linea_a = Vector3(self.s1.x, self.s1.y, self.s1.z - posterior)
        self.linea_b = Vector3(self.s3.x, self.s3.y, self.s3.z - posterior)
        self.linea_r = 0.32 * r_mid
        self.notch_a = Vector3(
            self.medial.x * 0.55,
            self.medial.y + 0.12 * condyle_ry,
            self.medial.z - 0.88 * condyle_rz,
        )
        self.notch_b = Vector3(
            self.lateral.x * 0.55,
            self.lateral.y + 0.12 * condyle_ry,
            self.lateral.z - 0.88 * condyle_rz,
        )
        self.notch_r = 0.10 * W
        self.patella = Vector3(
            0.5 * (self.medial.x + self.lateral.x),
            0.5 * (self.medial.y + self.lateral.y) + 0.12 * condyle_ry,
            0.5 * (self.medial.z + self.lateral.z) + 0.58 * condyle_rz,
        )
        self.patella_r = Vector3(0.34 * W, 0.55 * condyle_ry, 0.20 * condyle_rz)
        self.k = 0.010 * L
        self.k_notch = 0.004 * L
        self.epsilon = 0.0015 * L
        var rad0 = max(self.ml0, self.ap0)
        var rad4 = max(self.ml4, self.ap4)
        var box = empty_bounds()
        box.include_sphere(self.head_center, self.head_r)
        box.include_ellipsoid(self.gt, self.gt_r)
        box.include_ellipsoid(self.lt, self.lt_r)
        box.include_ellipsoid(self.medial, self.medial_r)
        box.include_ellipsoid(self.lateral, self.lateral_r)
        box.include_ellipsoid(self.distal_metaphysis, self.distal_metaphysis_r)
        box.include_sphere(self.s0, rad0)
        box.include_sphere(self.s4, rad4)
        var pad = 0.022 * L + Float32(0.004)
        var padded = box.padded(pad)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the femur, in meters.

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
        d = smin(
            d,
            sd_segment(
                point,
                self.neck_base,
                self.head_center,
                self.neck_r,
                self.head_r * 0.55,
            ),
            self.k,
        )
        d = smin(d, sd_sphere(point, self.head_center, self.head_r), self.k)
        d = smin(
            d,
            sd_segment(
                point,
                self.gt_bridge_a,
                self.gt_bridge_b,
                self.gt_bridge_ra,
                self.gt_bridge_rb,
            ),
            self.k,
        )
        d = smin(d, sd_ellipsoid(point, self.gt, self.gt_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.lt, self.lt_r), self.k)
        d = smin(
            d,
            sd_ellipsoid(
                point, self.distal_metaphysis, self.distal_metaphysis_r
            ),
            self.k,
        )
        d = smin(d, sd_ellipsoid(point, self.medial, self.medial_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.lateral, self.lateral_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.patella, self.patella_r), self.k)
        d = smin(
            d,
            sd_segment(
                point, self.linea_a, self.linea_b, self.linea_r, self.linea_r
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


def femur_dimensions(
    stature: Length, sex: Sex, side: BodySide = RIGHT
) raises -> FemurDimensions:
    """Return the osteometric size of a femur for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        side: `RIGHT` or `LEFT`. A right femur is the default.

    Returns:
        Lengths, angles and landmark positions in the bone's frame.
        The neck direction is measured from the tilted shaft, not from
        world y.

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the software range.
    """
    check_spec(stature, sex, side, "femur")

    var stature_cm = stature.to(CENTIMETER)
    var femur_cm: Float32
    var head_ratio: Float32
    var neck_ratio: Float32
    var width_ratio: Float32
    var ap_ratio: Float32
    var ml_ratio: Float32
    var gt_ratio: Float32
    var lt_ratio: Float32
    var bow_ratio: Float32
    var ccd_deg: Float32
    var ante_deg: Float32
    var obliq_deg: Float32
    if sex == MALE:
        femur_cm = (stature_cm - MALE_INTERCEPT_CM) / MALE_SLOPE
        head_ratio = MALE_HEAD
        neck_ratio = MALE_NECK
        width_ratio = MALE_BICONDYLAR
        ap_ratio = MALE_SHAFT_AP
        ml_ratio = MALE_SHAFT_ML
        gt_ratio = MALE_GT
        lt_ratio = MALE_LT
        bow_ratio = MALE_BOW
        ccd_deg = MALE_CCD_DEG
        ante_deg = MALE_ANTEVERSION_DEG
        obliq_deg = MALE_OBLIQUITY_DEG
    else:
        femur_cm = (stature_cm - FEMALE_INTERCEPT_CM) / FEMALE_SLOPE
        head_ratio = FEMALE_HEAD
        neck_ratio = FEMALE_NECK
        width_ratio = FEMALE_BICONDYLAR
        ap_ratio = FEMALE_SHAFT_AP
        ml_ratio = FEMALE_SHAFT_ML
        gt_ratio = FEMALE_GT
        lt_ratio = FEMALE_LT
        bow_ratio = FEMALE_BOW
        ccd_deg = FEMALE_CCD_DEG
        ante_deg = FEMALE_ANTEVERSION_DEG
        obliq_deg = FEMALE_OBLIQUITY_DEG

    var bone = Length(femur_cm, CENTIMETER)
    var L = bone.value
    var head_d = head_ratio * L
    var neck_len = neck_ratio * L
    var width = width_ratio * L
    var gt_off = gt_ratio * L
    var lt_off = lt_ratio * L
    var bow = bow_ratio * L
    var ccd = Angle(ccd_deg, DEGREE)
    var ante = Angle(ante_deg, DEGREE)
    var obliq = Angle(obliq_deg, DEGREE)
    var head_r = head_d * 0.5
    var condyle_ry = 0.32 * width
    var condyle_rz = 0.34 * width
    var medial = Vector3(
        -0.26 * width, -0.5 * L + condyle_ry * 1.04, 0.08 * condyle_rz
    )
    var lateral = Vector3(
        0.24 * width, -0.5 * L + condyle_ry, 0.04 * condyle_rz
    )
    var x0 = 0.5 * (medial.x + lateral.x)
    var y0 = 0.5 * (medial.y + lateral.y) + 0.085 * L
    # Shaft first: proximal is more lateral by the bicondylar angle.
    var shaft_up = Vector3(sin(obliq.value), cos(obliq.value), 0)
    var shaft_distal = Vector3(-shaft_up.x, -shaft_up.y, -shaft_up.z)
    var medial_dir = Vector3(-cos(obliq.value), sin(obliq.value), 0)
    var neck = Vector3(
        shaft_distal.x * cos(ccd.value) + medial_dir.x * sin(ccd.value),
        shaft_distal.y * cos(ccd.value) + medial_dir.y * sin(ccd.value),
        shaft_distal.z * cos(ccd.value) + medial_dir.z * sin(ccd.value),
    )
    neck = Quaternion.from_axis_angle(shaft_up, ante).rotate(neck)
    neck.normalize()
    var head_center_y = 0.5 * L - head_r
    var neck_base_y = head_center_y - neck.y * neck_len
    var along = (neck_base_y - y0) / shaft_up.y
    var neck_base = Vector3(x0 + along * shaft_up.x, neck_base_y, 0)
    var head_center = Vector3(
        neck_base.x + neck.x * neck_len,
        neck_base.y + neck.y * neck_len,
        neck_base.z + neck.z * neck_len,
    )
    var gt = Vector3(
        neck_base.x + 0.78 * gt_off,
        head_center.y - 0.70 * head_r,
        neck_base.z - 0.20 * gt_off,
    )
    var lt = Vector3(
        neck_base.x - 0.35 * lt_off,
        neck_base.y - 0.055 * L,
        neck_base.z - 0.75 * lt_off,
    )
    if side == LEFT:
        head_center = flip_x(head_center)
        neck_base = flip_x(neck_base)
        gt = flip_x(gt)
        lt = flip_x(lt)
        medial = flip_x(medial)
        lateral = flip_x(lateral)

    return FemurDimensions(
        stature,
        sex,
        side,
        bone,
        Length(head_d),
        Length(neck_len),
        ccd,
        ante,
        Length(width),
        Length(ap_ratio * L),
        Length(ml_ratio * L),
        Length(gt_off),
        Length(lt_off),
        Length(bow),
        obliq,
        head_center,
        neck_base,
        gt,
        lt,
        medial,
        lateral,
    )


def measured_neck_shaft_angle(dimensions: FemurDimensions) raises -> Angle:
    """Return the angle between the neck axis and the distal shaft chord.

    The neck axis is `head_center - neck_base`. The shaft chord is
    `s0 - s4` in the field built from `dimensions`. That is the same
    definition `neck_shaft_angle` is constructed to match.

    Args:
        dimensions: A femur already sized from stature and sex.

    Returns:
        The measured angle, in radians inside the `Angle`.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    var field = FemurField(dimensions)
    var neck = field.head_center - field.neck_base
    neck.normalize()
    var shaft = field.s0 - field.s4
    shaft.normalize()
    return Angle(acos(clamp_unit(neck.dot(shaft))), RADIAN)


def femur_distance(
    dimensions: FemurDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the femur, in meters.

    Negative is inside. The surface `femur` meshes is the zero set.

    Args:
        dimensions: A femur already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    var field = FemurField(dimensions)
    return field.distance(point)
