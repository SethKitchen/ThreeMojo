# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Osteometric size of a femur, and the implicit solid that has that size.

Length comes from Trotter and Gleser 1952, inverted: stature from maximum
femoral length, solved for the bone. The male line is
`stature_cm = 2.38 * femur_cm + 61.41`. The female line is
`stature_cm = 2.47 * femur_cm + 54.10`. Those are the American White adult
formulae, which forensic software uses when no population is named. A six
foot male therefore gets a femur of 51.04 cm, not a naive 26.7 percent of
stature.

Every other linear measure is a sex-specific ratio of that length, taken
from standard adult osteometry: femoral head diameter, biomechanical neck
length, midshaft diameters, bicondylar breadth, trochanter offsets and the
anterior bow. Neck-shaft angle, anteversion and the bicondylar angle are
the usual adult means, a few degrees different by sex. Thickness therefore
scales with the bone, not with stature on its own, which is what
"proportionally" means here.

The solid is a smooth union of anatomical parts: a bowed tapered shaft, a
neck, a spherical head, both trochanters, both condyles, a patellar
surface, a linea aspera, and a notch cut between the condyles. The mesh
builder in `geometry` takes the zero set of that field.

The bone's own frame is osteological. Plus y is proximal, plus x is
lateral, plus z is anterior, the origin is mid-shaft. A right femur uses
that frame. A left femur is the same points with x flipped.
"""

from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import cos, isfinite, max, min, sin, sqrt
from units.si import (
    Angle,
    CENTIMETER,
    DEGREE,
    Length,
    METER,
    RADIAN,
)

# Adult range the Trotter and Gleser lines were built for. A stature
# outside it is refused rather than extrapolated.
comptime MIN_STATURE = Length(1.2, METER)
comptime MAX_STATURE = Length(2.5, METER)

# Trotter M, Gleser GC. Am J Phys Anthropol. 1952. Table 13, American
# White adults, maximum femoral length in centimeters.
comptime MALE_SLOPE = Float32(2.38)
comptime MALE_INTERCEPT_CM = Float32(61.41)
comptime FEMALE_SLOPE = Float32(2.47)
comptime FEMALE_INTERCEPT_CM = Float32(54.10)

# Ratios of maximum femoral length, adult male. Head diameter, bicondylar
# breadth and midshaft diameters follow common osteometric means around a
# 466 mm femur; neck length is the biomechanical length from the shaft
# axis to the head center; trochanter offsets and bow are the same scale.
comptime MALE_HEAD = Float32(0.1030)
comptime MALE_NECK = Float32(0.1073)
comptime MALE_BICONDYLAR = Float32(0.1803)
comptime MALE_SHAFT_AP = Float32(0.0631)
comptime MALE_SHAFT_ML = Float32(0.0579)
comptime MALE_GT = Float32(0.0687)
comptime MALE_LT = Float32(0.0386)
comptime MALE_BOW = Float32(0.0129)
# Neck-shaft (CCD) angle, anteversion and femoral obliquity, in degrees.
comptime MALE_CCD_DEG = Float32(126.0)
comptime MALE_ANTEVERSION_DEG = Float32(12.0)
comptime MALE_OBLIQUITY_DEG = Float32(9.0)

# The matching adult female ratios, around a 432 mm femur. The head and
# the condyles are relatively smaller; the neck-shaft and bicondylar
# angles are a little more open, as in the orthopedic means.
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
    Lengths and angles carry units.
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


struct FemurField(ImplicitlyCopyable):
    """The implicit solid for one `FemurDimensions`.

    `distance` is in meters, negative inside the bone. `geometry` meshes
    the zero set.
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
    var r0: Float32
    var r1: Float32
    var r2: Float32
    var r3: Float32
    var r4: Float32
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

    def __init__(out self, dimensions: FemurDimensions):
        """Build the solid from already-checked dimensions."""
        var L = dimensions.length.value
        var head_r = dimensions.head_diameter.value * 0.5
        var W = dimensions.bicondylar_width.value
        var bow = dimensions.anterior_bow.value
        var gt_off = dimensions.greater_trochanter_offset.value
        var lt_off = dimensions.lesser_trochanter_offset.value
        var r_mid = 0.25 * (
            dimensions.midshaft_ap.value + dimensions.midshaft_ml.value
        )
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
        self.r0 = 1.35 * r_mid
        self.r1 = 1.10 * r_mid
        self.r2 = r_mid
        self.r3 = 1.12 * r_mid
        self.r4 = 1.28 * r_mid
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
        lo_x = min(lo_x, self.s0.x - self.r0)
        lo_y = min(lo_y, self.s0.y - self.r0)
        lo_z = min(lo_z, self.s0.z - self.r0)
        hi_x = max(hi_x, self.s0.x + self.r0)
        hi_y = max(hi_y, self.s0.y + self.r0)
        hi_z = max(hi_z, self.s0.z + self.r0)
        lo_x = min(lo_x, self.s4.x - self.r4)
        lo_y = min(lo_y, self.s4.y - self.r4)
        lo_z = min(lo_z, self.s4.z - self.r4)
        hi_x = max(hi_x, self.s4.x + self.r4)
        hi_y = max(hi_y, self.s4.y + self.r4)
        hi_z = max(hi_z, self.s4.z + self.r4)
        var pad = 0.022 * L + Float32(0.004)
        self.low = Vector3(lo_x - pad, lo_y - pad, lo_z - pad)
        self.high = Vector3(hi_x + pad, hi_y + pad, hi_z + pad)

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the femur, in meters.

        Negative is inside. Zero is the surface.
        """
        var d = _sd_segment(point, self.s0, self.s1, self.r0, self.r1)
        d = _smin(
            d, _sd_segment(point, self.s1, self.s2, self.r1, self.r2), self.k
        )
        d = _smin(
            d, _sd_segment(point, self.s2, self.s3, self.r2, self.r3), self.k
        )
        d = _smin(
            d, _sd_segment(point, self.s3, self.s4, self.r3, self.r4), self.k
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

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the adult range.
    """
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
    var inclination = Angle(180.0, DEGREE) - ccd
    var neck_dir = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), inclination
    ).rotate(Vector3(0, 1, 0))
    neck_dir = Quaternion.from_axis_angle(Vector3(0, 1, 0), ante).rotate(
        neck_dir
    )
    neck_dir.normalize()
    var head_center = Vector3(0, 0.5 * L - head_r, 0)
    var neck_base = Vector3(
        head_center.x - neck_dir.x * neck_len,
        head_center.y - neck_dir.y * neck_len,
        head_center.z - neck_dir.z * neck_len,
    )
    # The shaft sits more lateral than the knee, by the bicondylar angle.
    # Shift the proximal cluster so the condyles stay on x of zero and the
    # neck base is the tilted shaft's top.
    var y_distal = -0.5 * L + 2.15 * condyle_ry
    var rise = neck_base.y - y_distal
    var tilt = sin(obliq.value) / cos(obliq.value)
    var proximal_x = tilt * rise
    var shift = proximal_x - neck_base.x
    head_center = Vector3(head_center.x + shift, head_center.y, head_center.z)
    neck_base = Vector3(neck_base.x + shift, neck_base.y, neck_base.z)
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
    var medial = Vector3(
        -0.26 * width, -0.5 * L + condyle_ry * 1.04, 0.08 * condyle_rz
    )
    var lateral = Vector3(
        0.24 * width, -0.5 * L + condyle_ry, 0.04 * condyle_rz
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


def femur_distance(dimensions: FemurDimensions, point: Vector3) -> Float32:
    """Return how far `point` lies outside the femur, in meters.

    Negative is inside. The surface `femur` meshes is the zero set.

    Args:
        dimensions: A femur already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        The signed distance, in meters.
    """
    var field = FemurField(dimensions)
    return field.distance(point)


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
