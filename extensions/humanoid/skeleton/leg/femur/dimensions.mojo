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
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import acos, cos, isfinite, max, min, pi, sin, sqrt
from units.si import (
    Angle,
    CENTIMETER,
    DEGREE,
    Length,
    METER,
    RADIAN,
)

# Software range for a stature argument. This is not the calibration
# range of the 1952 sample.
comptime MIN_STATURE = Length(1.2, METER)
comptime MAX_STATURE = Length(2.5, METER)

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
        _check_spec(self.stature, self.sex, self.side)
        _positive_length(self.length, "length")
        _positive_length(self.head_diameter, "head diameter")
        _positive_length(self.neck_length, "neck length")
        _positive_length(self.bicondylar_width, "bicondylar width")
        _positive_length(self.midshaft_ap, "midshaft AP diameter")
        _positive_length(self.midshaft_ml, "midshaft ML diameter")
        _positive_length(self.greater_trochanter_offset, "greater trochanter")
        _positive_length(self.lesser_trochanter_offset, "lesser trochanter")
        _non_negative_length(self.anterior_bow, "anterior bow")
        _open_angle(self.neck_shaft_angle, "neck-shaft angle")
        _finite_angle(self.anteversion, "anteversion")
        _acute_angle(self.bicondylar_angle, "bicondylar angle")
        _finite_point(self.head_center, "head center")
        _finite_point(self.neck_base, "neck base")
        _finite_point(self.greater_trochanter, "greater trochanter")
        _finite_point(self.lesser_trochanter, "lesser trochanter")
        _finite_point(self.medial_condyle, "medial condyle")
        _finite_point(self.lateral_condyle, "lateral condyle")


struct FemurField(ImplicitlyCopyable):
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
    var lt: Vector3
    var lt_r: Vector3
    var medial: Vector3
    var medial_r: Vector3
    var lateral: Vector3
    var lateral_r: Vector3
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
        var condyle_ry = 0.39 * W
        var condyle_rz = 0.36 * W
        var condyle_rx = 0.28 * W
        self.head_center = dimensions.head_center
        self.head_r = head_r
        self.neck_base = dimensions.neck_base
        self.neck_r = 0.58 * head_r
        self.gt = dimensions.greater_trochanter
        self.gt_r = Vector3(0.62 * gt_off, 0.95 * head_r, 0.55 * gt_off)
        self.lt = dimensions.lesser_trochanter
        self.lt_r = Vector3(0.55 * lt_off, 0.62 * lt_off, 0.50 * lt_off)
        self.medial = dimensions.medial_condyle
        self.medial_r = Vector3(
            condyle_rx * 1.06, condyle_ry * 1.04, condyle_rz * 1.04
        )
        self.lateral = dimensions.lateral_condyle
        self.lateral_r = Vector3(condyle_rx, condyle_ry, condyle_rz)
        var y0 = 0.5 * (self.medial.y + self.lateral.y) + 0.085 * L
        var y4 = self.neck_base.y
        var x0 = 0.5 * (self.medial.x + self.lateral.x)
        var x4 = self.neck_base.x
        self.s0 = _station(0.0, x0, x4, y0, y4, bow)
        self.s1 = _station(0.25, x0, x4, y0, y4, bow)
        self.s2 = _station(0.5, x0, x4, y0, y4, bow)
        self.s3 = _station(0.75, x0, x4, y0, y4, bow)
        self.s4 = _station(1.0, x0, x4, y0, y4, bow)
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
            self.medial.y + 0.18 * condyle_ry,
            self.medial.z - 0.72 * condyle_rz,
        )
        self.notch_b = Vector3(
            self.lateral.x * 0.55,
            self.lateral.y + 0.18 * condyle_ry,
            self.lateral.z - 0.72 * condyle_rz,
        )
        self.notch_r = 0.22 * W
        self.patella = Vector3(
            0.5 * (self.medial.x + self.lateral.x),
            0.5 * (self.medial.y + self.lateral.y) + 0.12 * condyle_ry,
            0.5 * (self.medial.z + self.lateral.z) + 0.58 * condyle_rz,
        )
        self.patella_r = Vector3(0.30 * W, 0.38 * condyle_ry, 0.24 * condyle_rz)
        self.k = 0.016 * L
        self.k_notch = 0.007 * L
        self.epsilon = 0.0015 * L
        var rad0 = max(self.ml0, self.ap0)
        var rad4 = max(self.ml4, self.ap4)
        var lo_x = self.head_center.x - self.head_r
        var lo_y = self.head_center.y - self.head_r
        var lo_z = self.head_center.z - self.head_r
        var hi_x = self.head_center.x + self.head_r
        var hi_y = self.head_center.y + self.head_r
        var hi_z = self.head_center.z + self.head_r
        lo_x = min(lo_x, self.gt.x - self.gt_r.x)
        lo_y = min(lo_y, self.gt.y - self.gt_r.y)
        lo_z = min(lo_z, self.gt.z - self.gt_r.z)
        hi_x = max(hi_x, self.gt.x + self.gt_r.x)
        hi_y = max(hi_y, self.gt.y + self.gt_r.y)
        hi_z = max(hi_z, self.gt.z + self.gt_r.z)
        lo_x = min(lo_x, self.lt.x - self.lt_r.x)
        lo_y = min(lo_y, self.lt.y - self.lt_r.y)
        lo_z = min(lo_z, self.lt.z - self.lt_r.z)
        hi_x = max(hi_x, self.lt.x + self.lt_r.x)
        hi_y = max(hi_y, self.lt.y + self.lt_r.y)
        hi_z = max(hi_z, self.lt.z + self.lt_r.z)
        lo_x = min(lo_x, self.medial.x - self.medial_r.x)
        lo_y = min(lo_y, self.medial.y - self.medial_r.y)
        lo_z = min(lo_z, self.medial.z - self.medial_r.z)
        hi_x = max(hi_x, self.medial.x + self.medial_r.x)
        hi_y = max(hi_y, self.medial.y + self.medial_r.y)
        hi_z = max(hi_z, self.medial.z + self.medial_r.z)
        lo_x = min(lo_x, self.lateral.x - self.lateral_r.x)
        lo_y = min(lo_y, self.lateral.y - self.lateral_r.y)
        lo_z = min(lo_z, self.lateral.z - self.lateral_r.z)
        hi_x = max(hi_x, self.lateral.x + self.lateral_r.x)
        hi_y = max(hi_y, self.lateral.y + self.lateral_r.y)
        hi_z = max(hi_z, self.lateral.z + self.lateral_r.z)
        lo_x = min(lo_x, self.s0.x - rad0)
        lo_y = min(lo_y, self.s0.y - rad0)
        lo_z = min(lo_z, self.s0.z - rad0)
        hi_x = max(hi_x, self.s0.x + rad0)
        hi_y = max(hi_y, self.s0.y + rad0)
        hi_z = max(hi_z, self.s0.z + rad0)
        lo_x = min(lo_x, self.s4.x - rad4)
        lo_y = min(lo_y, self.s4.y - rad4)
        lo_z = min(lo_z, self.s4.z - rad4)
        hi_x = max(hi_x, self.s4.x + rad4)
        hi_y = max(hi_y, self.s4.y + rad4)
        hi_z = max(hi_z, self.s4.z + rad4)
        var pad = 0.022 * L + Float32(0.004)
        self.low = Vector3(lo_x - pad, lo_y - pad, lo_z - pad)
        self.high = Vector3(hi_x + pad, hi_y + pad, hi_z + pad)

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the femur, in meters.

        Negative is inside. Zero is the surface.
        """
        var d = _sd_ellipse_segment(
            point, self.s0, self.s1, self.ml0, self.ap0, self.ml1, self.ap1
        )
        d = _smin(
            d,
            _sd_ellipse_segment(
                point, self.s1, self.s2, self.ml1, self.ap1, self.ml2, self.ap2
            ),
            self.k,
        )
        d = _smin(
            d,
            _sd_ellipse_segment(
                point, self.s2, self.s3, self.ml2, self.ap2, self.ml3, self.ap3
            ),
            self.k,
        )
        d = _smin(
            d,
            _sd_ellipse_segment(
                point, self.s3, self.s4, self.ml3, self.ap3, self.ml4, self.ap4
            ),
            self.k,
        )
        d = _smin(
            d,
            _sd_segment(
                point,
                self.neck_base,
                self.head_center,
                self.neck_r,
                self.head_r * 0.55,
            ),
            self.k,
        )
        d = _smin(d, _sd_sphere(point, self.head_center, self.head_r), self.k)
        d = _smin(d, _sd_ellipsoid(point, self.gt, self.gt_r), self.k)
        d = _smin(d, _sd_ellipsoid(point, self.lt, self.lt_r), self.k)
        d = _smin(d, _sd_ellipsoid(point, self.medial, self.medial_r), self.k)
        d = _smin(d, _sd_ellipsoid(point, self.lateral, self.lateral_r), self.k)
        d = _smin(d, _sd_ellipsoid(point, self.patella, self.patella_r), self.k)
        d = _smin(
            d,
            _sd_segment(
                point, self.linea_a, self.linea_b, self.linea_r, self.linea_r
            ),
            self.k,
        )
        var notch = _sd_segment(
            point, self.notch_a, self.notch_b, self.notch_r, self.notch_r
        )
        return _smax(d, -notch, self.k_notch)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        var e = self.epsilon
        var dx = self.distance(
            Vector3(point.x + e, point.y, point.z)
        ) - self.distance(Vector3(point.x - e, point.y, point.z))
        var dy = self.distance(
            Vector3(point.x, point.y + e, point.z)
        ) - self.distance(Vector3(point.x, point.y - e, point.z))
        var dz = self.distance(
            Vector3(point.x, point.y, point.z + e)
        ) - self.distance(Vector3(point.x, point.y, point.z - e))
        var normal = Vector3(dx, dy, dz)
        normal.normalize()
        return normal


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
    _check_spec(stature, sex, side)

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
    var condyle_ry = 0.39 * width
    var condyle_rz = 0.36 * width
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
        neck_base.x + gt_off,
        head_center.y - 0.22 * head_r,
        neck_base.z - 0.28 * gt_off,
    )
    var lt = Vector3(
        neck_base.x - 0.42 * lt_off,
        neck_base.y - 0.065 * L,
        neck_base.z - lt_off,
    )
    if side == LEFT:
        head_center = _flip_x(head_center)
        neck_base = _flip_x(neck_base)
        gt = _flip_x(gt)
        lt = _flip_x(lt)
        medial = _flip_x(medial)
        lateral = _flip_x(lateral)

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
    return Angle(acos(_clamp_unit(neck.dot(shaft))), RADIAN)


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


def _check_spec(stature: Length, sex: Sex, side: BodySide) raises:
    """Refuse a spec the femur templates cannot use."""
    if not sex.is_valid():
        raise Error("A femur needs a male or female template")
    if not side.is_valid():
        raise Error("A femur needs a left or right side")
    if not isfinite(stature.value):
        raise Error("A femur's stature must be finite")
    if stature < MIN_STATURE:
        raise Error("A femur's stature must be at least 1.2 meters")
    if stature > MAX_STATURE:
        raise Error("A femur's stature cannot exceed 2.5 meters")


def _positive_length(value: Length, name: String) raises:
    """Refuse a length that is not finite or not positive."""
    if not isfinite(value.value):
        raise Error("A femur " + name + " must be finite")
    if value.value <= 0:
        raise Error("A femur " + name + " must be positive")


def _non_negative_length(value: Length, name: String) raises:
    """Refuse a length that is not finite or is negative."""
    if not isfinite(value.value):
        raise Error("A femur " + name + " must be finite")
    if value.value < 0:
        raise Error("A femur " + name + " cannot be negative")


def _finite_angle(value: Angle, name: String) raises:
    """Refuse an angle that is not finite."""
    if not isfinite(value.value):
        raise Error("A femur " + name + " must be finite")


def _open_angle(value: Angle, name: String) raises:
    """Refuse an angle that is not finite or not strictly between 0 and pi."""
    _finite_angle(value, name)
    if value.value <= 0:
        raise Error("A femur " + name + " must be positive")
    if value.value >= pi:
        raise Error("A femur " + name + " must be less than 180 degrees")


def _acute_angle(value: Angle, name: String) raises:
    """Refuse an angle that is not finite, negative, or 90 degrees or more."""
    _finite_angle(value, name)
    if value.value < 0:
        raise Error("A femur " + name + " cannot be negative")
    if value.value >= pi * Float32(0.5):
        raise Error("A femur " + name + " must be less than 90 degrees")


def _finite_point(point: Vector3, name: String) raises:
    """Refuse a landmark with a non-finite coordinate."""
    if not isfinite(point.x):
        raise Error("A femur " + name + " must be finite")
    if not isfinite(point.y):
        raise Error("A femur " + name + " must be finite")
    if not isfinite(point.z):
        raise Error("A femur " + name + " must be finite")


def _clamp_unit(value: Float32) -> Float32:
    """Return `value` held to minus one through one, for `acos`."""
    if value < -1:
        return -1
    if value > 1:
        return 1
    return value


def _flip_x(point: Vector3) -> Vector3:
    """Return `point` mirrored across the midline of the bone."""
    return Vector3(-point.x, point.y, point.z)


def _station(
    t: Float32, x0: Float32, x4: Float32, y0: Float32, y4: Float32, bow: Float32
) -> Vector3:
    """Return a shaft centerline point at fraction `t` from distal to proximal.
    """
    return Vector3(
        x0 + t * (x4 - x0),
        y0 + t * (y4 - y0),
        4 * bow * t * (1 - t),
    )


def _abs(value: Float32) -> Float32:
    """Return `value` without its sign."""
    if value < 0:
        return -value
    return value


def _smin(a: Float32, b: Float32, k: Float32) -> Float32:
    """Return a smooth minimum of `a` and `b` with blend radius `k`."""
    var h = k - _abs(a - b)
    if h < 0:
        h = 0
    return min(a, b) - h * h * Float32(0.25) / k


def _smax(a: Float32, b: Float32, k: Float32) -> Float32:
    """Return a smooth maximum of `a` and `b` with blend radius `k`."""
    return -_smin(-a, -b, k)


def _sd_sphere(point: Vector3, center: Vector3, radius: Float32) -> Float32:
    """Return the signed distance to a sphere."""
    return (point - center).length() - radius


def _sd_segment(
    point: Vector3, a: Vector3, b: Vector3, radius_a: Float32, radius_b: Float32
) -> Float32:
    """Return the signed distance to a tapered capsule from `a` to `b`."""
    var along = b - a
    var from_a = point - a
    var span = along.dot(along)
    var t = Float32(0)
    if span > 0:
        t = from_a.dot(along) / span
        if t < 0:
            t = 0
        if t > 1:
            t = 1
    var radius = radius_a + (radius_b - radius_a) * t
    return (from_a - along * t).length() - radius


def _reject(vector: Vector3, unit: Vector3) -> Vector3:
    """Return the part of `vector` perpendicular to unit `unit`."""
    var d = vector.dot(unit)
    return Vector3(
        vector.x - unit.x * d, vector.y - unit.y * d, vector.z - unit.z * d
    )


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of `a` and `b` without mutating them."""
    var out = a
    out.cross(b)
    return out


def _sd_ellipse_segment(
    point: Vector3,
    a: Vector3,
    b: Vector3,
    ml_a: Float32,
    ap_a: Float32,
    ml_b: Float32,
    ap_b: Float32,
) -> Float32:
    """Return an approximate signed distance to a tapered elliptical capsule.

    Mediolateral radius is along bone x after projecting out the tangent.
    Anteroposterior radius is along the remaining anterior axis. The two
    diameters are independent.
    """
    var along = b - a
    var from_a = point - a
    var span = along.dot(along)
    var t = Float32(0)
    if span > 0:
        t = from_a.dot(along) / span
        if t < 0:
            t = 0
        if t > 1:
            t = 1
    var ml_r = ml_a + (ml_b - ml_a) * t
    var ap_r = ap_a + (ap_b - ap_a) * t
    var center = Vector3(
        a.x + along.x * t, a.y + along.y * t, a.z + along.z * t
    )
    var offset = point - center
    var tangent = Vector3(0, 1, 0)
    if span > 0:
        var inv = Float32(1) / sqrt(span)
        tangent = Vector3(along.x * inv, along.y * inv, along.z * inv)
    var ml_axis = _reject(Vector3(1, 0, 0), tangent)
    if ml_axis.length() < Float32(0.000001):
        ml_axis = _reject(Vector3(0, 0, 1), tangent)
    ml_axis.normalize()
    var ap_axis = _cross(tangent, ml_axis)
    ap_axis.normalize()
    var u = offset.dot(ml_axis)
    var v = offset.dot(ap_axis)
    var w = offset.dot(tangent)
    var px = u / ml_r
    var pz = v / ap_r
    var pr = sqrt(ml_r * ap_r)
    var py = w / pr
    var k0 = sqrt(px * px + py * py + pz * pz)
    var qx = px / ml_r
    var qy = py / pr
    var qz = pz / ap_r
    var k1 = sqrt(qx * qx + qy * qy + qz * qz)
    if k1 == 0:
        return -min(ml_r, ap_r)
    return k0 * (k0 - 1) / k1


def _sd_ellipsoid(point: Vector3, center: Vector3, radii: Vector3) -> Float32:
    """Return an approximate signed distance to an ellipsoid."""
    var px = (point.x - center.x) / radii.x
    var py = (point.y - center.y) / radii.y
    var pz = (point.z - center.z) / radii.z
    var k0 = sqrt(px * px + py * py + pz * pz)
    var qx = px / radii.x
    var qy = py / radii.y
    var qz = pz / radii.z
    var k1 = sqrt(qx * qx + qy * qy + qz * qz)
    if k1 == 0:
        return -min(radii.x, min(radii.y, radii.z))
    return k0 * (k0 - 1) / k1
