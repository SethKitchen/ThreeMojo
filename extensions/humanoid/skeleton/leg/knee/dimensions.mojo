# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Size of the knee soft tissues, and the implicit solids that have that size.

Articular cartilage thickness at the six-foot male template uses Shepherd
and Seedhom 1999 as named adult means: 2.2 mm on the femoral condyles,
2.5 mm on the tibial plateau, 3.3 mm on the patella. Other statures scale
those thicknesses in proportion to stature. That scale is an authored
template rule. It is not a cited stature regression.

Meniscus size and collateral size are authored sex-specific ratios of
stature. They are template parameters. They are not a cited osteometric
table.

The solids live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior. A
right knee uses that frame. A left knee uses the same rule after the
bones flip x.

`KneeDimensions` is fieldwise-constructible. Editing a measurement does
not rebuild landmarks. Call `knee_dimensions` to resolve a template.
Call `validate` at every public consumer of an edited copy.
"""

from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    check_spec,
    empty_bounds,
    field_gradient,
    finite_point,
    positive_length,
    sd_ellipsoid,
    sd_segment,
    smin,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurDimensions,
    femur_dimensions,
)
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    FibulaDimensions,
    fibula_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaDimensions,
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaDimensions,
    tibia_dimensions,
)
from math.vector3 import Vector3
from std.math import cos, max, pi, sin
from units.si import Length


@fieldwise_init
struct KneePart(Equatable, ImplicitlyCopyable, Writable):
    """Which knee soft-tissue solid a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the five named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named knee part."""
        if self == ARTICULAR_CARTILAGE:
            return True
        if self == MEDIAL_MENISCUS:
            return True
        if self == LATERAL_MENISCUS:
            return True
        if self == MEDIAL_COLLATERAL:
            return True
        return self == LATERAL_COLLATERAL


# Hyaline cartilage on the femoral condyles, the trochlea, the plateau
# and the posterior patella.
comptime ARTICULAR_CARTILAGE = KneePart(0)
# C-shaped medial meniscus on the tibial plateau.
comptime MEDIAL_MENISCUS = KneePart(1)
# More circular lateral meniscus on the tibial plateau.
comptime LATERAL_MENISCUS = KneePart(2)
# Medial collateral ligament, femur to tibia.
comptime MEDIAL_COLLATERAL = KneePart(3)
# Lateral collateral ligament, femur to fibular head.
comptime LATERAL_COLLATERAL = KneePart(4)

# Shepherd and Seedhom 1999 means as ratios of stature, 6 ft male.
comptime MALE_FEM_CART = Float32(0.001203)
comptime MALE_TIB_CART = Float32(0.001367)
comptime MALE_PAT_CART = Float32(0.001805)
comptime MALE_MED_AP = Float32(0.0230)
comptime MALE_MED_RAD = Float32(0.0066)
comptime MALE_MED_H = Float32(0.0038)
comptime MALE_LAT_AP = Float32(0.0195)
comptime MALE_LAT_RAD = Float32(0.0062)
comptime MALE_LAT_H = Float32(0.0036)
comptime MALE_MCL_R = Float32(0.00315)
comptime MALE_LCL_R = Float32(0.00255)

comptime FEMALE_FEM_CART = Float32(0.001150)
comptime FEMALE_TIB_CART = Float32(0.001300)
comptime FEMALE_PAT_CART = Float32(0.001720)
comptime FEMALE_MED_AP = Float32(0.0218)
comptime FEMALE_MED_RAD = Float32(0.0062)
comptime FEMALE_MED_H = Float32(0.0036)
comptime FEMALE_LAT_AP = Float32(0.0185)
comptime FEMALE_LAT_RAD = Float32(0.0058)
comptime FEMALE_LAT_H = Float32(0.0034)
comptime FEMALE_MCL_R = Float32(0.00290)
comptime FEMALE_LCL_R = Float32(0.00235)


@fieldwise_init
struct KneeDimensions(ImplicitlyCopyable):
    """Measured size of the knee tissues, in the leg frame.

    Positions are in meters. Lengths carry units. Landmarks come from
    `knee_dimensions`. Editing a length does not move them.
    """

    var stature: Length
    var sex: Sex
    var side: BodySide
    var femoral_thickness: Length
    var tibial_thickness: Length
    var patellar_thickness: Length
    var medial_meniscus_ap: Length
    var medial_meniscus_radial: Length
    var medial_meniscus_height: Length
    var lateral_meniscus_ap: Length
    var lateral_meniscus_radial: Length
    var lateral_meniscus_height: Length
    var mcl_length: Length
    var mcl_radius: Length
    var lcl_length: Length
    var lcl_radius: Length
    var femoral_width: Length
    var tibial_width: Length
    var tibial_ap: Length
    var patella_height: Length
    var patella_width: Length
    var femoral_medial_cartilage: Vector3
    var femoral_lateral_cartilage: Vector3
    var trochlear_cartilage: Vector3
    var tibial_medial_cartilage: Vector3
    var tibial_lateral_cartilage: Vector3
    var patellar_cartilage: Vector3
    var medial_meniscus_center: Vector3
    var lateral_meniscus_center: Vector3
    var mcl_femur: Vector3
    var mcl_tibia: Vector3
    var lcl_femur: Vector3
    var lcl_fibula: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex or side is not valid, if a required length is
                not finite or not positive, or if a landmark is not finite.
        """
        check_spec(self.stature, self.sex, self.side, "knee")
        positive_length(self.femoral_thickness, "femoral thickness", "knee")
        positive_length(self.tibial_thickness, "tibial thickness", "knee")
        positive_length(self.patellar_thickness, "patellar thickness", "knee")
        positive_length(self.medial_meniscus_ap, "medial meniscus AP", "knee")
        positive_length(
            self.medial_meniscus_radial, "medial meniscus radial", "knee"
        )
        positive_length(
            self.medial_meniscus_height, "medial meniscus height", "knee"
        )
        positive_length(self.lateral_meniscus_ap, "lateral meniscus AP", "knee")
        positive_length(
            self.lateral_meniscus_radial, "lateral meniscus radial", "knee"
        )
        positive_length(
            self.lateral_meniscus_height, "lateral meniscus height", "knee"
        )
        positive_length(self.mcl_length, "MCL length", "knee")
        positive_length(self.mcl_radius, "MCL radius", "knee")
        positive_length(self.lcl_length, "LCL length", "knee")
        positive_length(self.lcl_radius, "LCL radius", "knee")
        positive_length(self.femoral_width, "femoral width", "knee")
        positive_length(self.tibial_width, "tibial width", "knee")
        positive_length(self.tibial_ap, "tibial AP", "knee")
        positive_length(self.patella_height, "patella height", "knee")
        positive_length(self.patella_width, "patella width", "knee")
        finite_point(
            self.femoral_medial_cartilage, "femoral medial cartilage", "knee"
        )
        finite_point(
            self.femoral_lateral_cartilage, "femoral lateral cartilage", "knee"
        )
        finite_point(self.trochlear_cartilage, "trochlear cartilage", "knee")
        finite_point(
            self.tibial_medial_cartilage, "tibial medial cartilage", "knee"
        )
        finite_point(
            self.tibial_lateral_cartilage, "tibial lateral cartilage", "knee"
        )
        finite_point(self.patellar_cartilage, "patellar cartilage", "knee")
        finite_point(
            self.medial_meniscus_center, "medial meniscus center", "knee"
        )
        finite_point(
            self.lateral_meniscus_center, "lateral meniscus center", "knee"
        )
        finite_point(self.mcl_femur, "MCL femoral attachment", "knee")
        finite_point(self.mcl_tibia, "MCL tibial attachment", "knee")
        finite_point(self.lcl_femur, "LCL femoral attachment", "knee")
        finite_point(self.lcl_fibula, "LCL fibular attachment", "knee")


struct CartilageField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for articular cartilage of one knee."""

    var fem_med: Vector3
    var fem_med_r: Vector3
    var fem_lat: Vector3
    var fem_lat_r: Vector3
    var troch: Vector3
    var troch_r: Vector3
    var tib_med: Vector3
    var tib_med_r: Vector3
    var tib_lat: Vector3
    var tib_lat_r: Vector3
    var pat: Vector3
    var pat_r: Vector3
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: KneeDimensions) raises:
        """Build the cartilage solid from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var t_f = dimensions.femoral_thickness.value
        var t_t = dimensions.tibial_thickness.value
        var t_p = dimensions.patellar_thickness.value
        var W = dimensions.femoral_width.value
        var tw = dimensions.tibial_width.value
        var ap = dimensions.tibial_ap.value
        var ph = dimensions.patella_height.value
        var pw = dimensions.patella_width.value
        var condyle_ry = 0.39 * W
        var condyle_rz = 0.36 * W
        var condyle_rx = 0.28 * W
        self.fem_med = dimensions.femoral_medial_cartilage
        self.fem_med_r = Vector3(
            condyle_rx * 0.82, t_f * 0.75, condyle_rz * 0.62
        )
        self.fem_lat = dimensions.femoral_lateral_cartilage
        self.fem_lat_r = Vector3(
            condyle_rx * 0.78, t_f * 0.75, condyle_rz * 0.58
        )
        self.troch = dimensions.trochlear_cartilage
        self.troch_r = Vector3(0.24 * W, 0.24 * condyle_ry, t_f * 0.70)
        self.tib_med = dimensions.tibial_medial_cartilage
        self.tib_med_r = Vector3(0.20 * tw, t_t * 0.75, 0.30 * ap)
        self.tib_lat = dimensions.tibial_lateral_cartilage
        self.tib_lat_r = Vector3(0.19 * tw, t_t * 0.75, 0.28 * ap)
        self.pat = dimensions.patellar_cartilage
        self.pat_r = Vector3(0.36 * pw, 0.30 * ph, t_p * 0.65)
        self.k = 0.20 * t_f
        self.epsilon = 0.12 * t_f
        var box = empty_bounds()
        box.include_ellipsoid(self.fem_med, self.fem_med_r)
        box.include_ellipsoid(self.fem_lat, self.fem_lat_r)
        box.include_ellipsoid(self.troch, self.troch_r)
        box.include_ellipsoid(self.tib_med, self.tib_med_r)
        box.include_ellipsoid(self.tib_lat, self.tib_lat_r)
        box.include_ellipsoid(self.pat, self.pat_r)
        var padded = box.padded(0.004 + t_p)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the cartilage, in meters.

        Negative is inside. Zero is the surface.
        """
        var d = sd_ellipsoid(point, self.fem_med, self.fem_med_r)
        d = smin(d, sd_ellipsoid(point, self.fem_lat, self.fem_lat_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.troch, self.troch_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.tib_med, self.tib_med_r), self.k)
        d = smin(d, sd_ellipsoid(point, self.tib_lat, self.tib_lat_r), self.k)
        return smin(d, sd_ellipsoid(point, self.pat, self.pat_r), self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct MeniscusField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one meniscus."""

    var p0: Vector3
    var p1: Vector3
    var p2: Vector3
    var p3: Vector3
    var p4: Vector3
    var r0: Float32
    var r1: Float32
    var r2: Float32
    var r3: Float32
    var r4: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: KneeDimensions, part: KneePart) raises:
        """Build one meniscus from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks.
            part: `MEDIAL_MENISCUS` or `LATERAL_MENISCUS`.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not a meniscus.
        """
        dimensions.validate()
        if part != MEDIAL_MENISCUS:
            if part != LATERAL_MENISCUS:
                raise Error("A meniscus field needs a medial or lateral part")
        var medial = part == MEDIAL_MENISCUS
        var ap: Float32
        var height: Float32
        var radial: Float32
        var center: Vector3
        if medial:
            ap = dimensions.medial_meniscus_ap.value
            height = dimensions.medial_meniscus_height.value
            radial = dimensions.medial_meniscus_radial.value
            center = dimensions.medial_meniscus_center
        else:
            ap = dimensions.lateral_meniscus_ap.value
            height = dimensions.lateral_meniscus_height.value
            radial = dimensions.lateral_meniscus_radial.value
            center = dimensions.lateral_meniscus_center
        var tube = 0.42 * height + 0.16 * radial
        var rz = 0.5 * ap - tube
        if rz < tube:
            rz = tube
        var rx = 0.72 * rz
        var d2r = pi / Float32(180)
        if medial:
            self.p0 = _arc(center, rx, rz, Float32(50) * d2r)
            self.p1 = _arc(center, rx, rz, Float32(110) * d2r)
            self.p2 = _arc(center, rx, rz, Float32(180) * d2r)
            self.p3 = _arc(center, rx, rz, Float32(250) * d2r)
            self.p4 = _arc(center, rx, rz, Float32(310) * d2r)
            self.r0 = 0.86 * tube
            self.r1 = 0.96 * tube
            self.r2 = 1.05 * tube
            self.r3 = 1.22 * tube
            self.r4 = 1.02 * tube
        else:
            self.p0 = _arc(center, rx, rz, Float32(220) * d2r)
            self.p1 = _arc(center, rx, rz, Float32(270) * d2r)
            self.p2 = _arc(center, rx, rz, Float32(0) * d2r)
            self.p3 = _arc(center, rx, rz, Float32(90) * d2r)
            self.p4 = _arc(center, rx, rz, Float32(140) * d2r)
            self.r0 = 0.95 * tube
            self.r1 = 1.12 * tube
            self.r2 = 1.00 * tube
            self.r3 = 0.92 * tube
            self.r4 = 0.98 * tube
        self.k = 0.55 * tube
        self.epsilon = 0.18 * tube
        var box = empty_bounds()
        box.include_sphere(self.p0, self.r0)
        box.include_sphere(self.p1, self.r1)
        box.include_sphere(self.p2, self.r2)
        box.include_sphere(self.p3, self.r3)
        box.include_sphere(self.p4, self.r4)
        var padded = box.padded(0.003 + tube)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the meniscus, in meters.

        Negative is inside. Zero is the surface.
        """
        var d = sd_segment(point, self.p0, self.p1, self.r0, self.r1)
        d = smin(
            d, sd_segment(point, self.p1, self.p2, self.r1, self.r2), self.k
        )
        d = smin(
            d, sd_segment(point, self.p2, self.p3, self.r2, self.r3), self.k
        )
        return smin(
            d, sd_segment(point, self.p3, self.p4, self.r3, self.r4), self.k
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct CollateralField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one collateral ligament."""

    var a: Vector3
    var b: Vector3
    var ra: Float32
    var rb: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: KneeDimensions, part: KneePart) raises:
        """Build one collateral from dimensions that `validate` accepts.

        Args:
            dimensions: Size and landmarks.
            part: `MEDIAL_COLLATERAL` or `LATERAL_COLLATERAL`.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not a collateral.
        """
        dimensions.validate()
        if part != MEDIAL_COLLATERAL:
            if part != LATERAL_COLLATERAL:
                raise Error("A collateral field needs a medial or lateral part")
        if part == MEDIAL_COLLATERAL:
            self.a = dimensions.mcl_femur
            self.b = dimensions.mcl_tibia
            self.ra = 1.18 * dimensions.mcl_radius.value
            self.rb = dimensions.mcl_radius.value
        else:
            self.a = dimensions.lcl_femur
            self.b = dimensions.lcl_fibula
            self.ra = 1.10 * dimensions.lcl_radius.value
            self.rb = dimensions.lcl_radius.value
        var rad = max(self.ra, self.rb)
        self.k = 0.40 * rad
        self.epsilon = 0.18 * rad
        var box = empty_bounds()
        box.include_sphere(self.a, self.ra)
        box.include_sphere(self.b, self.rb)
        var padded = box.padded(0.004 + rad)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the ligament, in meters.

        Negative is inside. Zero is the surface.
        """
        return sd_segment(point, self.a, self.b, self.ra, self.rb)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def knee_dimensions(
    stature: Length, sex: Sex, side: BodySide = RIGHT
) raises -> KneeDimensions:
    """Return the size of the knee tissues for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.
        side: `RIGHT` or `LEFT`. A right knee is the default.

    Returns:
        Lengths and landmark positions in the leg frame.

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the software range.
    """
    check_spec(stature, sex, side, "knee")
    var femur = femur_dimensions(stature, sex, side)
    var tibia = tibia_dimensions(stature, sex, side)
    var fibula = fibula_dimensions(stature, sex, side)
    var patella = patella_dimensions(stature, sex, side)
    return knee_dimensions_from_bones(femur, tibia, fibula, patella)


def knee_dimensions_from_bones(
    femur: FemurDimensions,
    tibia: TibiaDimensions,
    fibula: FibulaDimensions,
    patella: PatellaDimensions,
) raises -> KneeDimensions:
    """Return knee tissues placed against already-sized leg bones.

    Args:
        femur: A femur already sized from stature and sex.
        tibia: A tibia from the same spec.
        fibula: A fibula from the same spec.
        patella: A patella from the same spec.

    Returns:
        Lengths and landmark positions in the leg frame.

    Raises:
        Error: If any bone fails `validate`.
    """
    femur.validate()
    tibia.validate()
    fibula.validate()
    patella.validate()
    var stature = femur.stature
    var sex = femur.sex
    var side = femur.side
    var fem_ratio: Float32
    var tib_ratio: Float32
    var pat_ratio: Float32
    var med_ap: Float32
    var med_rad: Float32
    var med_h: Float32
    var lat_ap: Float32
    var lat_rad: Float32
    var lat_h: Float32
    var mcl_r: Float32
    var lcl_r: Float32
    if sex == MALE:
        fem_ratio = MALE_FEM_CART
        tib_ratio = MALE_TIB_CART
        pat_ratio = MALE_PAT_CART
        med_ap = MALE_MED_AP
        med_rad = MALE_MED_RAD
        med_h = MALE_MED_H
        lat_ap = MALE_LAT_AP
        lat_rad = MALE_LAT_RAD
        lat_h = MALE_LAT_H
        mcl_r = MALE_MCL_R
        lcl_r = MALE_LCL_R
    else:
        fem_ratio = FEMALE_FEM_CART
        tib_ratio = FEMALE_TIB_CART
        pat_ratio = FEMALE_PAT_CART
        med_ap = FEMALE_MED_AP
        med_rad = FEMALE_MED_RAD
        med_h = FEMALE_MED_H
        lat_ap = FEMALE_LAT_AP
        lat_rad = FEMALE_LAT_RAD
        lat_h = FEMALE_LAT_H
        mcl_r = FEMALE_MCL_R
        lcl_r = FEMALE_LCL_R
    var t_f = Length(fem_ratio * stature.value)
    var t_t = Length(tib_ratio * stature.value)
    var t_p = Length(pat_ratio * stature.value)
    var f_origin = femur_origin(femur, t_f)
    var t_origin = tibia_origin(tibia, t_t)
    var fi_origin = fibula_origin(tibia, t_origin, fibula)
    var p_origin = patella_origin(femur, f_origin, patella, t_p)
    var W = femur.bicondylar_width.value
    var tw = tibia.proximal_width.value
    var condyle_ry = 0.39 * W
    var condyle_rz = 0.36 * W
    var fem_med = f_origin + femur.medial_condyle
    var fem_lat = f_origin + femur.lateral_condyle
    var tib_med = t_origin + tibia.medial_condyle
    var tib_lat = t_origin + tibia.lateral_condyle
    var troch_local = _trochlea_local(femur)
    var troch_world = f_origin + troch_local
    var fem_med_c = Vector3(
        fem_med.x,
        fem_med.y - 1.04 * condyle_ry + t_f.value * 0.35,
        fem_med.z,
    )
    var fem_lat_c = Vector3(
        fem_lat.x,
        fem_lat.y - condyle_ry + t_f.value * 0.35,
        fem_lat.z,
    )
    var troch_c = Vector3(
        troch_world.x,
        troch_world.y,
        troch_world.z + 0.24 * condyle_rz + t_f.value * 0.35,
    )
    var tib_med_c = Vector3(
        tib_med.x,
        tib_med.y + 0.085 * tw + t_t.value * 0.35,
        tib_med.z,
    )
    var tib_lat_c = Vector3(
        tib_lat.x,
        tib_lat.y + 0.080 * tw + t_t.value * 0.35,
        tib_lat.z,
    )
    var T = patella.thickness.value
    var pat_c = Vector3(
        p_origin.x,
        p_origin.y,
        p_origin.z - Float32(0.38) * T - t_p.value * 0.25,
    )
    var med_men = Vector3(tib_med.x, 0, tib_med.z)
    var lat_men = Vector3(tib_lat.x, 0, tib_lat.z)
    var lat_sign = Float32(1)
    if side == LEFT:
        lat_sign = Float32(-1)
    var mcl_a = Vector3(
        fem_med.x - lat_sign * 0.16 * W,
        t_f.value + 0.024,
        fem_med.z + 0.006,
    )
    var mcl_b = Vector3(
        tib_med.x - lat_sign * 0.12 * W,
        -0.052,
        tib_med.z + 0.004,
    )
    var lcl_a = Vector3(
        fem_lat.x + lat_sign * 0.14 * W,
        t_f.value + 0.022,
        fem_lat.z + 0.002,
    )
    var lcl_b = fi_origin + fibula.head_center
    var mcl_len = (mcl_b - mcl_a).length()
    var lcl_len = (lcl_b - lcl_a).length()
    return KneeDimensions(
        stature,
        sex,
        side,
        t_f,
        t_t,
        t_p,
        Length(med_ap * stature.value),
        Length(med_rad * stature.value),
        Length(med_h * stature.value),
        Length(lat_ap * stature.value),
        Length(lat_rad * stature.value),
        Length(lat_h * stature.value),
        Length(mcl_len),
        Length(mcl_r * stature.value),
        Length(lcl_len),
        Length(lcl_r * stature.value),
        femur.bicondylar_width,
        tibia.proximal_width,
        tibia.proximal_ap,
        patella.height,
        patella.width,
        fem_med_c,
        fem_lat_c,
        troch_c,
        tib_med_c,
        tib_lat_c,
        pat_c,
        med_men,
        lat_men,
        mcl_a,
        mcl_b,
        lcl_a,
        lcl_b,
    )


def femur_origin(femur: FemurDimensions, cartilage: Length) raises -> Vector3:
    """Return the femur-frame origin in the leg frame.

    The distal condyle surface sits at plus `cartilage` on y.

    Args:
        femur: A femur already sized from stature and sex.
        cartilage: Femoral articular thickness.

    Returns:
        The bone origin in the leg frame, in meters.

    Raises:
        Error: If `femur.validate` refuses the copy, or `cartilage` is
            not finite or not positive.
    """
    femur.validate()
    positive_length(cartilage, "femoral thickness", "knee")
    var mid = _mid(femur.medial_condyle, femur.lateral_condyle)
    var distal_y = -0.5 * femur.length.value
    return Vector3(-mid.x, cartilage.value - distal_y, -mid.z)


def tibia_origin(tibia: TibiaDimensions, cartilage: Length) raises -> Vector3:
    """Return the tibia-frame origin in the leg frame.

    The eminence sits at minus `cartilage` on y.

    Args:
        tibia: A tibia already sized from stature and sex.
        cartilage: Tibial articular thickness.

    Returns:
        The bone origin in the leg frame, in meters.

    Raises:
        Error: If `tibia.validate` refuses the copy, or `cartilage` is
            not finite or not positive.
    """
    tibia.validate()
    positive_length(cartilage, "tibial thickness", "knee")
    var mid = _mid(tibia.medial_condyle, tibia.lateral_condyle)
    return Vector3(-mid.x, -cartilage.value - tibia.eminence.y, -mid.z)


def fibula_origin(
    tibia: TibiaDimensions,
    tibia_origin_point: Vector3,
    fibula: FibulaDimensions,
) raises -> Vector3:
    """Return the fibula-frame origin in the leg frame.

    The head sits just lateral and slightly distal of the tibial
    lateral condyle.

    Args:
        tibia: A tibia already sized from stature and sex.
        tibia_origin_point: Tibia origin in the leg frame.
        fibula: A fibula from the same spec.

    Returns:
        The bone origin in the leg frame, in meters.

    Raises:
        Error: If a bone fails `validate`.
    """
    tibia.validate()
    fibula.validate()
    finite_point(tibia_origin_point, "tibia origin", "knee")
    var lat = tibia_origin_point + tibia.lateral_condyle
    var head_r = fibula.head_diameter.value * 0.5
    var lat_sign = Float32(1)
    if fibula.side == LEFT:
        lat_sign = Float32(-1)
    var target = Vector3(
        lat.x + lat_sign * (head_r * 1.12 + Float32(0.003)),
        lat.y - Float32(0.010),
        lat.z - Float32(0.006),
    )
    return target - fibula.head_center


def patella_origin(
    femur: FemurDimensions,
    femur_origin_point: Vector3,
    patella: PatellaDimensions,
    cartilage: Length,
) raises -> Vector3:
    """Return the patella-frame origin in the leg frame.

    The posterior face sits just anterior of the trochlea plus the
    patellar cartilage thickness.

    Args:
        femur: A femur already sized from stature and sex.
        femur_origin_point: Femur origin in the leg frame.
        patella: A patella from the same spec.
        cartilage: Patellar articular thickness.

    Returns:
        The bone origin in the leg frame, in meters.

    Raises:
        Error: If a bone fails `validate`, a point is not finite, or
            `cartilage` is not finite or not positive.
    """
    femur.validate()
    patella.validate()
    finite_point(femur_origin_point, "femur origin", "knee")
    positive_length(cartilage, "patellar thickness", "knee")
    var troch = _trochlea_local(femur)
    var W = femur.bicondylar_width.value
    var condyle_rz = 0.36 * W
    var anterior = (
        femur_origin_point.z + troch.z + 0.24 * condyle_rz + cartilage.value
    )
    var T = patella.thickness.value
    var posterior_local = Float32(-0.40) * T
    return Vector3(
        femur_origin_point.x + troch.x,
        femur_origin_point.y + troch.y,
        anterior - posterior_local,
    )


def knee_distance(
    dimensions: KneeDimensions, part: KneePart, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside. The surface the mesher takes is the zero set.

    Args:
        dimensions: Knee tissues already sized from stature and sex.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not a named knee part.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A knee part must be cartilage, a meniscus or a collateral")
    if part == ARTICULAR_CARTILAGE:
        return CartilageField(dimensions).distance(point)
    if part == MEDIAL_MENISCUS:
        return MeniscusField(dimensions, part).distance(point)
    if part == LATERAL_MENISCUS:
        return MeniscusField(dimensions, part).distance(point)
    return CollateralField(dimensions, part).distance(point)


def knee_part_label(part: KneePart) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A knee part, named or not.

    Returns:
        A short American English label.
    """
    if part == ARTICULAR_CARTILAGE:
        return "articular cartilage"
    if part == MEDIAL_MENISCUS:
        return "medial meniscus"
    if part == LATERAL_MENISCUS:
        return "lateral meniscus"
    if part == MEDIAL_COLLATERAL:
        return "medial collateral"
    if part == LATERAL_COLLATERAL:
        return "lateral collateral"
    return "knee"


def _mid(a: Vector3, b: Vector3) -> Vector3:
    """Return the midpoint of `a` and `b`."""
    return Vector3(0.5 * (a.x + b.x), 0.5 * (a.y + b.y), 0.5 * (a.z + b.z))


def _trochlea_local(femur: FemurDimensions) -> Vector3:
    """Return the trochlear-groove center in the femur frame."""
    var W = femur.bicondylar_width.value
    var condyle_ry = 0.39 * W
    var condyle_rz = 0.36 * W
    return Vector3(
        0.5 * (femur.medial_condyle.x + femur.lateral_condyle.x),
        0.5 * (femur.medial_condyle.y + femur.lateral_condyle.y)
        + 0.12 * condyle_ry,
        0.5 * (femur.medial_condyle.z + femur.lateral_condyle.z)
        + 0.58 * condyle_rz,
    )


def _arc(center: Vector3, rx: Float32, rz: Float32, theta: Float32) -> Vector3:
    """Return an xz ellipse point at `theta` radians from plus x."""
    return Vector3(
        center.x + rx * cos(theta),
        center.y,
        center.z + rz * sin(theta),
    )
