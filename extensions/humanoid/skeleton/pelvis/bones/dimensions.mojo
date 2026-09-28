# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The four bones of the pelvis, as implicit solids.

The pelvis is the two hip bones, the sacrum and the coccyx. Each hip
bone is the fused ilium, ischium and pubis.

The hip joint centers come from Harrington and colleagues 2007. That
paper predicts them from the pelvic width between the anterior superior
iliac spines. Here a sex-specific ratio of stature picks that width,
and the regression places the joint centers. Every other landmark is
an authored ratio of stature. The ratios are template parameters. They
are not a cited osteometric table. The female template is wider,
shorter and has a wider pubic arch.

The frame origin is the midpoint of the two hip joint centers. Plus y
is proximal. Plus x is body-right. Plus z is anterior. The landmarks
are those of the right side. A left part mirrors them on x. The
sacrum and the coccyx lie on the midline.

Each hip bone is a smooth union of the iliac wing, the crest, the
columns and rami, and a cup around the femoral head. The wing is a fan
of thin plates. The socket, the sacroiliac joint and the pubic
symphysis keep a joint space. The sacrum is a curved wedge of five
elliptical stations. The coccyx is a short tapered chain.

`PelvisDimensions` is fieldwise-constructible. Editing a measurement
does not rebuild landmarks. Call `pelvis_dimensions` to resolve a
template. Call `validate` at every public consumer of an edited copy.

    var dims = pelvis_dimensions(Length(6.0, FOOT), MALE)
    var d = pelvis_bone_distance(dims, SACRUM, dims.promontory)
"""

from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    check_spec,
    empty_bounds,
    field_gradient,
    finite_point,
    flip_x,
    mix_point,
    positive_length,
    sd_ellipse_segment,
    sd_ellipsoid,
    sd_segment,
    smax,
    smin,
    ud_triangle,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import femur_dimensions
from math.vector3 import Vector3
from std.math import cos, max, min, sin
from units.si import DEGREE, Angle, Length

# Width between the anterior superior iliac spines, as a ratio of
# stature. Authored adult template values.
comptime MALE_ASIS_WIDTH = Float32(0.131)
comptime FEMALE_ASIS_WIDTH = Float32(0.146)

# Harrington JR, Lenhoff MW, Oeffinger DJ. J Biomech. 2007. The hip
# joint center from the pelvic width PW: lateral 0.33 PW + 7.3 mm,
# inferior 0.30 PW + 10.9 mm, and posterior 0.24 PD + 9.9 mm of the
# anterior superior iliac spine. PD is the pelvic depth.
comptime HJC_LATERAL = Float32(0.33)
comptime HJC_LATERAL_M = Float32(0.0073)
comptime HJC_INFERIOR = Float32(0.30)
comptime HJC_INFERIOR_M = Float32(0.0109)
comptime HJC_POSTERIOR = Float32(0.24)
comptime HJC_POSTERIOR_M = Float32(0.0099)
# Pelvic depth, spine to spine front to back, as a ratio of stature.
comptime PELVIC_DEPTH = Float32(0.085)

# The socket's opening: inclination from vertical, and anteversion.
comptime MALE_INCLINATION_DEG = Float32(45.0)
comptime MALE_ANTEVERSION_DEG = Float32(17.0)
comptime FEMALE_INCLINATION_DEG = Float32(47.0)
comptime FEMALE_ANTEVERSION_DEG = Float32(20.0)

# The female template against the male one: wider, shorter, the same
# depth, and a pubic arch wider again.
comptime FEMALE_BREADTH = Float32(1.08)
comptime FEMALE_HEIGHT = Float32(0.94)
comptime FEMALE_ARCH = Float32(1.07)

# How deep the sacrum's front bows behind the line from promontory to
# apex, as a ratio of stature.
comptime MALE_SACRAL_BOW = Float32(0.0077)
comptime FEMALE_SACRAL_BOW = Float32(0.0058)

# Joint spaces, as ratios of stature: the socket around the femoral
# head, the sacroiliac joint, and half the pubic symphysis.
comptime SOCKET_SPACE = Float32(0.0019)
comptime SACROILIAC_SPACE = Float32(0.0012)
comptime SYMPHYSIS_SPACE = Float32(0.0014)

# One centimeter on the six-foot male template, as a ratio of stature.
# Soft tissue is authored in these centimeters and scales with stature.
comptime TEMPLATE_CM = Float32(1.0 / 182.88)

# Blades of the iliac wing's fan between two rim landmarks.
comptime WING_STEPS = 4

# Cortical shells, as ratios of stature.
comptime HIP_SHELL = Float32(0.0010)
comptime SACRAL_SHELL = Float32(0.0008)
comptime COCCYGEAL_SHELL = Float32(0.0006)


@fieldwise_init
struct PelvisBone(Equatable, ImplicitlyCopyable, Writable):
    """Which of the four pelvic bones a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named bones is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named pelvic bone."""
        if self.value < 0:
            return False
        return self.value <= COCCYX.value


comptime RIGHT_HIP_BONE = PelvisBone(0)
comptime LEFT_HIP_BONE = PelvisBone(1)
comptime SACRUM = PelvisBone(2)
comptime COCCYX = PelvisBone(3)


@fieldwise_init
struct PelvisDimensions(ImplicitlyCopyable):
    """Size and landmarks of one pelvis in the pelvis frame.

    Positions are in meters. Lengths carry units. The landmarks are
    those of the right hip bone; the midline ones have x near zero.
    Landmarks come from `pelvis_dimensions`. Editing a length does not
    move them.
    """

    var stature: Length
    var sex: Sex
    # Between the anterior superior iliac spines.
    var breadth: Length
    # Between the two hip joint centers.
    var hip_span: Length
    # From the top of the crest to the bottom of the ischial tuberosity.
    var height: Length
    # The femoral head's radius, which the socket holds.
    var head_radius: Length
    # Unit vector out of the right socket's opening.
    var socket_axis: Vector3
    var sacral_bow: Float32
    var hip: Vector3
    var asis: Vector3
    var aiis: Vector3
    var crest_front: Vector3
    var tubercle: Vector3
    var crest_top: Vector3
    var crest_back: Vector3
    var psis: Vector3
    var piis: Vector3
    var auricular: Vector3
    var notch: Vector3
    var hub: Vector3
    var spine: Vector3
    var ischium: Vector3
    var tuberosity: Vector3
    var eminence: Vector3
    var pectineal: Vector3
    var pubic_tubercle: Vector3
    var symphysis_top: Vector3
    var symphysis_bottom: Vector3
    var ramus: Vector3
    var obturator: Vector3
    var promontory: Vector3
    var sacral_apex: Vector3
    var coccyx_tip: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex is not valid, if stature is outside the
                software range, if a length is not finite or not
                positive, if the socket axis is not a unit vector, or
                if a landmark is not finite.
        """
        check_spec(self.stature, self.sex, RIGHT, "pelvis")
        positive_length(self.breadth, "breadth", "pelvis")
        positive_length(self.hip_span, "hip span", "pelvis")
        positive_length(self.height, "height", "pelvis")
        positive_length(self.head_radius, "femoral head radius", "pelvis")
        finite_point(self.socket_axis, "socket axis", "pelvis")
        var norm = self.socket_axis.length()
        if norm < 0.99 or norm > 1.01:
            raise Error("A pelvis socket axis must be a unit vector")
        if not self.sacral_bow >= 0:
            raise Error("A pelvis sacral bow must not be negative")
        finite_point(self.hip, "hip", "pelvis")
        finite_point(self.asis, "ASIS", "pelvis")
        finite_point(self.aiis, "AIIS", "pelvis")
        finite_point(self.crest_front, "front of the crest", "pelvis")
        finite_point(self.tubercle, "iliac tubercle", "pelvis")
        finite_point(self.crest_top, "top of the crest", "pelvis")
        finite_point(self.crest_back, "back of the crest", "pelvis")
        finite_point(self.psis, "PSIS", "pelvis")
        finite_point(self.piis, "PIIS", "pelvis")
        finite_point(self.auricular, "auricular surface", "pelvis")
        finite_point(self.notch, "greater sciatic notch", "pelvis")
        finite_point(self.hub, "supra-acetabular hub", "pelvis")
        finite_point(self.spine, "ischial spine", "pelvis")
        finite_point(self.ischium, "ischial body", "pelvis")
        finite_point(self.tuberosity, "ischial tuberosity", "pelvis")
        finite_point(self.eminence, "iliopubic eminence", "pelvis")
        finite_point(self.pectineal, "pectineal line", "pelvis")
        finite_point(self.pubic_tubercle, "pubic tubercle", "pelvis")
        finite_point(self.symphysis_top, "top of the symphysis", "pelvis")
        finite_point(self.symphysis_bottom, "bottom of the symphysis", "pelvis")
        finite_point(self.ramus, "ischiopubic ramus", "pelvis")
        finite_point(self.obturator, "obturator foramen", "pelvis")
        finite_point(self.promontory, "sacral promontory", "pelvis")
        finite_point(self.sacral_apex, "sacral apex", "pelvis")
        finite_point(self.coccyx_tip, "coccyx tip", "pelvis")

    def hip_center(self, side: BodySide) raises -> Vector3:
        """Return one hip joint center in the pelvis frame.

        Args:
            side: `RIGHT` or `LEFT`.

        Returns:
            The center of that femoral head, in meters.

        Raises:
            Error: If `side` is not valid.
        """
        return sided(self.hip, side)


@fieldwise_init
struct _Capsule(ImplicitlyCopyable):
    """One tapered capsule of a hip bone."""

    var a: Vector3
    var b: Vector3
    var ra: Float32
    var rb: Float32


@fieldwise_init
struct _Plate(ImplicitlyCopyable):
    """One thin triangular plate of the iliac wing."""

    var a: Vector3
    var b: Vector3
    var c: Vector3


struct SacrumShape(ImplicitlyCopyable):
    """The sacrum's five elliptical stations and its median crest."""

    var c0: Vector3
    var c1: Vector3
    var c2: Vector3
    var c3: Vector3
    var c4: Vector3
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
    var crest_a: Vector3
    var crest_b: Vector3
    var crest_r: Float32
    var k: Float32

    def __init__(out self, dimensions: PelvisDimensions):
        """Lay the sacrum along its curve from promontory to apex.

        Args:
            dimensions: Landmarks from `pelvis_dimensions`.
        """
        var S = dimensions.stature.value
        var wide = Float32(1)
        if dimensions.sex != MALE:
            wide = FEMALE_BREADTH
        var front = dimensions.promontory
        var apex = dimensions.sacral_apex
        var run = apex - front
        run.normalize()
        # Behind the front of the sacrum, and a little up.
        var back = Vector3(0, -run.z, run.y)
        var bow = dimensions.sacral_bow
        var deep0 = 0.0300 * S
        var deep1 = 0.0210 * S
        var deep2 = 0.0150 * S
        var deep3 = 0.0100 * S
        var deep4 = 0.0065 * S
        self.c0 = _sacral_station(front, apex, back, bow, 0.00, deep0)
        self.c1 = _sacral_station(front, apex, back, bow, 0.25, deep1)
        self.c2 = _sacral_station(front, apex, back, bow, 0.50, deep2)
        self.c3 = _sacral_station(front, apex, back, bow, 0.75, deep3)
        self.c4 = _sacral_station(front, apex, back, bow, 1.00, deep4)
        self.ml0 = 0.0290 * S * wide
        self.ml1 = 0.0255 * S * wide
        self.ml2 = 0.0195 * S * wide
        self.ml3 = 0.0125 * S * wide
        self.ml4 = 0.0055 * S * wide
        self.ap0 = 0.5 * deep0
        self.ap1 = 0.5 * deep1
        self.ap2 = 0.5 * deep2
        self.ap3 = 0.5 * deep3
        self.ap4 = 0.5 * deep4
        self.crest_a = self.c0 + back * (0.5 * deep0)
        self.crest_b = self.c3 + back * (0.5 * deep3)
        self.crest_r = 0.0026 * S
        self.k = 0.0030 * S

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the sacrum, in meters.

        Negative is inside. Zero is the surface.
        """
        var ml = Vector3(1, 0, 0)
        var d = sd_ellipse_segment(
            point, self.c0, self.c1, self.ml0, self.ap0, self.ml1, self.ap1, ml
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.c1,
                self.c2,
                self.ml1,
                self.ap1,
                self.ml2,
                self.ap2,
                ml,
            ),
            self.k,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.c2,
                self.c3,
                self.ml2,
                self.ap2,
                self.ml3,
                self.ap3,
                ml,
            ),
            self.k,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.c3,
                self.c4,
                self.ml3,
                self.ap3,
                self.ml4,
                self.ap4,
                ml,
            ),
            self.k,
        )
        return smin(
            d,
            sd_segment(
                point, self.crest_a, self.crest_b, self.crest_r, self.crest_r
            ),
            self.k,
        )

    def bounds(self, pad: Float32) -> Bounds:
        """Return a padded box that holds the sacrum.

        Args:
            pad: Extra margin, in meters.

        Returns:
            An axis-aligned box.
        """
        var box = empty_bounds()
        box.include_ellipsoid(self.c0, Vector3(self.ml0, self.ap0, self.ap0))
        box.include_ellipsoid(self.c1, Vector3(self.ml1, self.ap1, self.ap1))
        box.include_ellipsoid(self.c2, Vector3(self.ml2, self.ap2, self.ap2))
        box.include_ellipsoid(self.c3, Vector3(self.ml3, self.ap3, self.ap3))
        box.include_ellipsoid(self.c4, Vector3(self.ml4, self.ap4, self.ap4))
        box.include_sphere(self.crest_a, self.crest_r)
        box.include_sphere(self.crest_b, self.crest_r)
        return box.padded(pad)


struct HipBoneShape(Copyable, Movable):
    """The right hip bone: plates, capsules, a tuberosity and a cup."""

    var plates: List[_Plate]
    var capsules: List[_Capsule]
    var hub: Vector3
    var thin: Float32
    var thick: Float32
    var reach: Float32
    var tuberosity: Vector3
    var tuberosity_r: Vector3
    var hip: Vector3
    var axis: Vector3
    var cup: Float32
    var socket: Float32
    var sacrum: SacrumShape
    var sacral_gap: Float32
    var midline: Float32
    var k: Float32

    def __init__(out self, dimensions: PelvisDimensions):
        """Build the right hip bone from its landmarks.

        Args:
            dimensions: Landmarks from `pelvis_dimensions`.
        """
        var S = dimensions.stature.value
        var d = dimensions
        self.plates = List[_Plate]()
        # The iliac wing: a fan from above the socket to the rim, which
        # runs from the anterior inferior spine over the crest and down
        # to the sciatic notch. A spline through the rim gives the fan
        # enough blades that it reads as one curved sheet.
        var rim = List[Vector3]()
        rim.append(d.aiis)
        rim.append(d.asis)
        rim.append(d.crest_front)
        rim.append(d.tubercle)
        rim.append(d.crest_top)
        rim.append(d.crest_back)
        rim.append(d.psis)
        rim.append(d.piis)
        rim.append(d.auricular)
        rim.append(d.notch)
        var last = len(rim) - 1
        var previous = rim[0]
        for span in range(last):
            var before = rim[max(span - 1, 0)]
            var after = rim[min(span + 2, last)]
            for step in range(1, WING_STEPS + 1):
                var t = Float32(step) / Float32(WING_STEPS)
                var here = _spline(before, rim[span], rim[span + 1], after, t)
                self.plates.append(_Plate(d.hub, previous, here))
                previous = here
        # The walls of the socket's two columns.
        self.plates.append(_Plate(d.hub, d.notch, d.ischium))
        self.plates.append(_Plate(d.hub, d.eminence, d.aiis))
        self.plates.append(_Plate(d.hub, d.eminence, d.ischium))
        self.capsules = List[_Capsule]()
        # The iliac crest, thickest at the tubercle.
        self.capsules.append(
            _Capsule(d.asis, d.crest_front, 0.0036 * S, 0.0040 * S)
        )
        self.capsules.append(
            _Capsule(d.crest_front, d.tubercle, 0.0040 * S, 0.0048 * S)
        )
        self.capsules.append(
            _Capsule(d.tubercle, d.crest_top, 0.0048 * S, 0.0042 * S)
        )
        self.capsules.append(
            _Capsule(d.crest_top, d.crest_back, 0.0042 * S, 0.0040 * S)
        )
        self.capsules.append(
            _Capsule(d.crest_back, d.psis, 0.0040 * S, 0.0045 * S)
        )
        # The thick posterior ilium, and the rim of the sciatic notch.
        self.capsules.append(_Capsule(d.psis, d.piis, 0.0060 * S, 0.0070 * S))
        self.capsules.append(
            _Capsule(d.piis, d.auricular, 0.0070 * S, 0.0080 * S)
        )
        self.capsules.append(
            _Capsule(d.auricular, d.notch, 0.0075 * S, 0.0065 * S)
        )
        self.capsules.append(
            _Capsule(d.notch, d.ischium, 0.0065 * S, 0.0075 * S)
        )
        # The anterior border, and the arcuate line of the pelvic brim.
        self.capsules.append(_Capsule(d.asis, d.aiis, 0.0036 * S, 0.0042 * S))
        self.capsules.append(_Capsule(d.aiis, d.hub, 0.0042 * S, 0.0070 * S))
        self.capsules.append(
            _Capsule(d.auricular, d.eminence, 0.0050 * S, 0.0050 * S)
        )
        # The ischium: its body, its spine, and the ramus to the pubis.
        self.capsules.append(
            _Capsule(d.ischium, d.tuberosity, 0.0085 * S, 0.0085 * S)
        )
        self.capsules.append(
            _Capsule(
                mix_point(d.ischium, d.tuberosity, 0.2),
                d.spine,
                0.0045 * S,
                0.0018 * S,
            )
        )
        self.capsules.append(
            _Capsule(d.tuberosity, d.ramus, 0.0075 * S, 0.0052 * S)
        )
        # The pubis: the superior ramus, the body at the symphysis, and
        # the inferior ramus. Together with the ischium they ring the
        # obturator foramen.
        var body_top = _pubic_body(d.symphysis_top, S)
        var body_bottom = _pubic_body(d.symphysis_bottom, S)
        self.capsules.append(
            _Capsule(d.eminence, d.pectineal, 0.0068 * S, 0.0060 * S)
        )
        self.capsules.append(
            _Capsule(d.pectineal, body_top, 0.0060 * S, 0.0066 * S)
        )
        self.capsules.append(
            _Capsule(body_top, body_bottom, 0.0070 * S, 0.0066 * S)
        )
        self.capsules.append(
            _Capsule(body_bottom, d.ramus, 0.0052 * S, 0.0052 * S)
        )
        self.capsules.append(
            _Capsule(d.pubic_tubercle, body_top, 0.0030 * S, 0.0040 * S)
        )
        self.hub = d.hub
        self.thin = 0.0017 * S
        self.thick = 0.0058 * S
        self.reach = 0.0300 * S
        self.tuberosity = d.tuberosity
        self.tuberosity_r = Vector3(0.0085 * S, 0.0130 * S, 0.0095 * S)
        self.hip = d.hip
        self.axis = d.socket_axis
        self.socket = d.head_radius.value + SOCKET_SPACE * S
        self.cup = self.socket + 0.0032 * S
        self.sacrum = SacrumShape(d)
        self.sacral_gap = SACROILIAC_SPACE * S
        self.midline = SYMPHYSIS_SPACE * S
        self.k = 0.0028 * S

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the right hip bone.

        Negative is inside. Zero is the surface.
        """
        var d = sd_ellipsoid(point, self.tuberosity, self.tuberosity_r)
        # The wing thins away from the socket.
        var near = max(
            Float32(0),
            Float32(1) - (point - self.hub).length() / self.reach,
        )
        var half = self.thin + (self.thick - self.thin) * near
        # The plates meet edge to edge, so they join with a hard minimum:
        # one sheet, with no ridge where two plates meet.
        var sheet = Float32(1.0e9)
        for index in range(len(self.plates)):
            var plate = self.plates[index]
            sheet = min(sheet, ud_triangle(point, plate.a, plate.b, plate.c))
        d = smin(d, sheet - half, self.k)
        for index in range(len(self.capsules)):
            var capsule = self.capsules[index]
            d = smin(
                d,
                sd_segment(point, capsule.a, capsule.b, capsule.ra, capsule.rb),
                self.k,
            )
        # The cup: a ball cut flat where the socket opens.
        var offset = point - self.hip
        var cup = smax(
            offset.length() - self.cup, offset.dot(self.axis), 2 * self.k
        )
        d = smin(d, cup, self.k)
        # The socket, the sacroiliac joint and the symphysis stay open.
        d = max(d, self.socket - offset.length())
        d = max(d, self.sacral_gap - self.sacrum.distance(point))
        return max(d, self.midline - point.x)

    def bounds(self, pad: Float32) -> Bounds:
        """Return a padded box that holds the right hip bone.

        Args:
            pad: Extra margin, in meters.

        Returns:
            An axis-aligned box.
        """
        var box = empty_bounds()
        for index in range(len(self.plates)):
            var plate = self.plates[index]
            box.include_sphere(plate.a, self.thick)
            box.include_sphere(plate.b, self.thick)
            box.include_sphere(plate.c, self.thick)
        for index in range(len(self.capsules)):
            var capsule = self.capsules[index]
            box.include_sphere(capsule.a, capsule.ra)
            box.include_sphere(capsule.b, capsule.rb)
        box.include_ellipsoid(self.tuberosity, self.tuberosity_r)
        box.include_sphere(self.hip, self.cup)
        return box.padded(pad)


struct PelvisBoneField(Copyable, DistanceField, Movable):
    """The implicit solid for one named pelvic bone."""

    var part: PelvisBone
    var hip_bone: HipBoneShape
    var sacrum: SacrumShape
    var coccyx0: Vector3
    var coccyx1: Vector3
    var coccyx2: Vector3
    var coccyx3: Vector3
    var coccyx_ml: Float32
    var coccyx_ap: Float32
    var mirror: Bool
    var shell: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: PelvisDimensions, part: PelvisBone
    ) raises:
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
            raise Error("A pelvic bone must be one of the four bones")
        var S = dimensions.stature.value
        self.part = part
        self.hip_bone = HipBoneShape(dimensions)
        self.sacrum = SacrumShape(dimensions)
        # The coccyx starts a joint space below the sacral apex and
        # curls forward to its tip.
        var tip = dimensions.coccyx_tip
        var apex = dimensions.sacral_apex
        self.coccyx0 = mix_point(apex, tip, 0.12) + Vector3(0, 0, -0.002 * S)
        self.coccyx1 = mix_point(apex, tip, 0.42) + Vector3(0, 0, -0.004 * S)
        self.coccyx2 = mix_point(apex, tip, 0.72) + Vector3(0, 0, -0.002 * S)
        self.coccyx3 = tip
        self.coccyx_ml = 0.0060 * S
        self.coccyx_ap = 0.0034 * S
        self.mirror = part == LEFT_HIP_BONE
        self.k = 0.0020 * S
        self.epsilon = 0.0004 * S
        var box: Bounds
        if part == SACRUM:
            self.shell = SACRAL_SHELL * S
            box = self.sacrum.bounds(0.004)
        elif part == COCCYX:
            self.shell = COCCYGEAL_SHELL * S
            box = empty_bounds()
            box.include_sphere(self.coccyx0, self.coccyx_ml)
            box.include_sphere(self.coccyx1, self.coccyx_ml)
            box.include_sphere(self.coccyx2, self.coccyx_ml)
            box.include_sphere(self.coccyx3, self.coccyx_ml)
            box = box.padded(0.004)
        else:
            self.shell = HIP_SHELL * S
            box = self.hip_bone.bounds(0.004)
            if self.mirror:
                box = Bounds(
                    Vector3(-box.high.x, box.low.y, box.low.z),
                    Vector3(-box.low.x, box.high.y, box.high.z),
                )
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the bone, in meters.

        Negative is inside. Zero is the surface.
        """
        if self.part == SACRUM:
            return self.sacrum.distance(point)
        if self.part == COCCYX:
            return self._coccyx(point)
        if self.mirror:
            return self.hip_bone.distance(flip_x(point))
        return self.hip_bone.distance(point)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)

    def _coccyx(self, point: Vector3) -> Float32:
        """Return the distance to the coccyx's tapered chain."""
        var ml = Vector3(1, 0, 0)
        var d = sd_ellipse_segment(
            point,
            self.coccyx0,
            self.coccyx1,
            self.coccyx_ml,
            self.coccyx_ap,
            0.80 * self.coccyx_ml,
            0.85 * self.coccyx_ap,
            ml,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point,
                self.coccyx1,
                self.coccyx2,
                0.80 * self.coccyx_ml,
                0.85 * self.coccyx_ap,
                0.60 * self.coccyx_ml,
                0.70 * self.coccyx_ap,
                ml,
            ),
            self.k,
        )
        return smin(
            d,
            sd_ellipse_segment(
                point,
                self.coccyx2,
                self.coccyx3,
                0.60 * self.coccyx_ml,
                0.70 * self.coccyx_ap,
                0.40 * self.coccyx_ml,
                0.50 * self.coccyx_ap,
                ml,
            ),
            self.k,
        )


def pelvis_dimensions(stature: Length, sex: Sex) raises -> PelvisDimensions:
    """Return the landmarks of a pelvis for an adult humanoid.

    Args:
        stature: Standing height. Must lie in 1.2 m through 2.5 m.
        sex: `MALE` or `FEMALE`.

    Returns:
        Lengths and landmark positions in the pelvis frame.

    Raises:
        Error: If `sex` is not valid, or stature is not finite or is
            outside the software range.
    """
    check_spec(stature, sex, RIGHT, "pelvis")
    var S = stature.value
    var width_ratio = FEMALE_ASIS_WIDTH
    var wide = FEMALE_BREADTH
    var tall = FEMALE_HEIGHT
    var arch = FEMALE_ARCH
    var inclination = Angle(FEMALE_INCLINATION_DEG, DEGREE)
    var anteversion = Angle(FEMALE_ANTEVERSION_DEG, DEGREE)
    var bow = FEMALE_SACRAL_BOW
    if sex == MALE:
        width_ratio = MALE_ASIS_WIDTH
        wide = Float32(1)
        tall = Float32(1)
        arch = Float32(1)
        inclination = Angle(MALE_INCLINATION_DEG, DEGREE)
        anteversion = Angle(MALE_ANTEVERSION_DEG, DEGREE)
        bow = MALE_SACRAL_BOW
    # The joint centers from the spines, then every landmark from the
    # joint center's height and depth.
    var width = width_ratio * S
    var depth = PELVIC_DEPTH * S
    var half = HJC_LATERAL * width + HJC_LATERAL_M * (S / Float32(1.75))
    var below = HJC_INFERIOR * width + HJC_INFERIOR_M * (S / Float32(1.75))
    var behind = HJC_POSTERIOR * depth + HJC_POSTERIOR_M * (S / Float32(1.75))
    var frame = PelvisFrame(S, wide, tall, arch)
    var femur = femur_dimensions(stature, sex, RIGHT)
    var head = femur.head_diameter.value * Float32(0.5)
    var tilt = sin(inclination.value)
    var axis = Vector3(
        tilt * cos(anteversion.value),
        -cos(inclination.value),
        tilt * sin(anteversion.value),
    )
    var tuberosity = frame.arched(0.0350, -0.0383, -0.0219)
    var crest_top = frame.at(0.0689, 0.0766, -0.0180)
    var dims = PelvisDimensions(
        stature,
        sex,
        Length(width),
        Length(2 * half),
        Length(crest_top.y - tuberosity.y + 0.0120 * S * tall),
        Length(head),
        axis,
        bow * S,
        Vector3(half, 0, 0),
        Vector3(0.5 * width, below, behind),
        frame.at(0.0563, 0.0208, 0.0219),  # AIIS
        frame.at(0.0733, 0.0601, 0.0142),  # front of the crest
        frame.at(0.0766, 0.0684, 0.0027),  # iliac tubercle
        crest_top,
        frame.at(0.0514, 0.0711, -0.0416),  # back of the crest
        frame.at(0.0262, 0.0563, -0.0563),  # PSIS
        frame.at(0.0306, 0.0361, -0.0547),  # PIIS
        frame.at(0.0284, 0.0339, -0.0405),  # auricular surface
        frame.at(0.0416, 0.0142, -0.0273),  # greater sciatic notch
        frame.at(0.0487, 0.0197, -0.0033),  # above the socket
        frame.arched(0.0290, -0.0126, -0.0306),  # ischial spine
        frame.at(0.0377, -0.0109, -0.0126),  # ischial body
        tuberosity,
        frame.at(0.0437, 0.0082, 0.0164),  # iliopubic eminence
        frame.at(0.0273, -0.0055, 0.0252),  # pectineal line
        frame.at(0.0142, -0.0175, 0.0317),  # pubic tubercle
        frame.midline(-0.0153, 0.0284),  # top of the symphysis
        frame.midline(-0.0383, 0.0208),  # bottom of the symphysis
        frame.arched(0.0252, -0.0448, 0.0022),  # ischiopubic ramus
        frame.at(0.0306, -0.0262, 0.0098),  # obturator foramen
        frame.midline(0.0339, -0.0060),  # sacral promontory
        frame.midline(-0.0082, -0.0410),  # sacral apex
        frame.midline(-0.0252, -0.0328),  # coccyx tip
    )
    # The spines were placed from Harrington's regression. Shift the
    # authored landmarks so the joint center sits where it predicts.
    var authored_hip = frame.at(0.0472, 0, 0)
    var shift = Vector3(dims.hip.x - authored_hip.x, 0, 0)
    _shift_lateral(dims, shift)
    return dims


def sided(point: Vector3, side: BodySide) raises -> Vector3:
    """Return a right-side landmark moved to `side`.

    Args:
        point: A point authored on the right, in the pelvis frame.
        side: `RIGHT` or `LEFT`.

    Returns:
        The point itself on the right, or mirrored on x on the left.

    Raises:
        Error: If `side` is not valid.
    """
    if not side.is_valid():
        raise Error("A pelvis side must be RIGHT or LEFT")
    if side == LEFT:
        return flip_x(point)
    return point


def pelvis_bone_distance(
    dimensions: PelvisDimensions, part: PelvisBone, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `pelvis_dimensions`.
        part: Which bone to sample.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return PelvisBoneField(dimensions, part).distance(point)


def pelvis_bone_label(part: PelvisBone) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A pelvic bone, named or not.

    Returns:
        A short American English label, or `"pelvic bone"` when `part`
        is not named.
    """
    if part == RIGHT_HIP_BONE:
        return "right hip bone"
    if part == LEFT_HIP_BONE:
        return "left hip bone"
    if part == SACRUM:
        return "sacrum"
    if part == COCCYX:
        return "coccyx"
    return "pelvic bone"


def named_pelvis_bones() -> List[PelvisBone]:
    """Return every named pelvic bone in a stable order.

    Returns:
        The right and left hip bones, the sacrum and the coccyx.
    """
    var parts = List[PelvisBone]()
    parts.append(RIGHT_HIP_BONE)
    parts.append(LEFT_HIP_BONE)
    parts.append(SACRUM)
    parts.append(COCCYX)
    return parts^


@fieldwise_init
struct PelvisFrame(ImplicitlyCopyable):
    """Turns authored ratios of stature into points in the pelvis frame.

    Ratios are those of the male template. A female frame widens x,
    shortens y, and widens the pubic arch again.
    """

    var stature: Float32
    var wide: Float32
    var tall: Float32
    var arch: Float32

    def at(self, lateral: Float32, up: Float32, forward: Float32) -> Vector3:
        """Return one right-side landmark.

        Args:
            lateral: Ratio of stature to the right of the midline.
            up: Ratio of stature above the hip joint centers.
            forward: Ratio of stature in front of them.

        Returns:
            The point, widened and shortened for a female template.
        """
        var S = self.stature
        return Vector3(lateral * S * self.wide, up * S * self.tall, forward * S)

    def arched(
        self, lateral: Float32, up: Float32, forward: Float32
    ) -> Vector3:
        """Return a landmark of the pubic arch or the pelvic outlet.

        Args:
            lateral: Ratio of stature to the right of the midline.
            up: Ratio of stature above the hip joint centers.
            forward: Ratio of stature in front of them.

        Returns:
            The point, widened again for a female template.
        """
        var point = self.at(lateral, up, forward)
        point.x = point.x * self.arch
        return point

    def template(
        self, lateral: Float32, up: Float32, forward: Float32
    ) -> Vector3:
        """Return a right-side point authored on the six-foot template.

        Args:
            lateral: Centimeters to the right of the midline.
            up: Centimeters above the hip joint centers.
            forward: Centimeters in front of them.

        Returns:
            The point scaled to this stature and sex, in meters.
        """
        return self.at(
            lateral * TEMPLATE_CM, up * TEMPLATE_CM, forward * TEMPLATE_CM
        )

    def midline(self, up: Float32, forward: Float32) -> Vector3:
        """Return a landmark on the midline.

        Args:
            up: Ratio of stature above the hip joint centers.
            forward: Ratio of stature in front of them.

        Returns:
            The point, with x zero.
        """
        return Vector3(0, up * self.stature * self.tall, forward * self.stature)


def pelvis_frame(dimensions: PelvisDimensions) -> PelvisFrame:
    """Return the frame that authored `dimensions`.

    Args:
        dimensions: Landmarks from `pelvis_dimensions`.

    Returns:
        The stature and the sex's breadth, height and arch factors.
    """
    if dimensions.sex == MALE:
        return PelvisFrame(dimensions.stature.value, 1, 1, 1)
    return PelvisFrame(
        dimensions.stature.value, FEMALE_BREADTH, FEMALE_HEIGHT, FEMALE_ARCH
    )


def sacral_front(dimensions: PelvisDimensions, t: Float32) -> Vector3:
    """Return a point on the front of the sacrum, on the midline.

    Args:
        dimensions: Landmarks from `pelvis_dimensions`.
        t: Zero at the promontory through one at the apex.

    Returns:
        The point on the bowed front surface, in meters.
    """
    var run = dimensions.sacral_apex - dimensions.promontory
    run.normalize()
    var back = Vector3(0, -run.z, run.y)
    var bent = Float32(4) * t * (1 - t) * dimensions.sacral_bow
    return mix_point(dimensions.promontory, dimensions.sacral_apex, t) + (
        back * bent
    )


def sacral_back(dimensions: PelvisDimensions) -> Vector3:
    """Return the unit vector behind the front of the sacrum.

    Args:
        dimensions: Landmarks from `pelvis_dimensions`.

    Returns:
        Perpendicular to the line from promontory to apex, pointing
        back and a little up.
    """
    var run = dimensions.sacral_apex - dimensions.promontory
    run.normalize()
    return Vector3(0, -run.z, run.y)


def sided_bounds(low: Vector3, high: Vector3, side: BodySide) -> Bounds:
    """Return a right-side box moved to `side`.

    Args:
        low: Low corner of a box authored on the right.
        high: High corner of that box.
        side: `RIGHT` or `LEFT`.

    Returns:
        The same box on the right, or mirrored on x on the left.
    """
    if side == LEFT:
        return Bounds(
            Vector3(-high.x, low.y, low.z), Vector3(-low.x, high.y, high.z)
        )
    return Bounds(low, high)


def _shift_lateral(mut dims: PelvisDimensions, shift: Vector3):
    """Move every lateral landmark but the spines by `shift`."""
    dims.aiis = dims.aiis + shift
    dims.crest_front = dims.crest_front + shift
    dims.tubercle = dims.tubercle + shift
    dims.crest_top = dims.crest_top + shift
    dims.hub = dims.hub + shift
    dims.eminence = dims.eminence + shift
    dims.ischium = dims.ischium + shift
    dims.obturator = dims.obturator + shift
    dims.notch = dims.notch + shift


def _spline(
    p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: Float32
) -> Vector3:
    """Return the Catmull-Rom point `t` of the way from `p1` to `p2`."""
    var t2 = t * t
    var t3 = t2 * t
    var w0 = Float32(0.5) * (-t3 + 2 * t2 - t)
    var w1 = Float32(0.5) * (3 * t3 - 5 * t2 + 2)
    var w2 = Float32(0.5) * (-3 * t3 + 4 * t2 + t)
    var w3 = Float32(0.5) * (t3 - t2)
    return p0 * w0 + p1 * w1 + p2 * w2 + p3 * w3


def _sacral_station(
    front: Vector3,
    apex: Vector3,
    back: Vector3,
    bow: Float32,
    t: Float32,
    depth: Float32,
) -> Vector3:
    """Return a station's center: half its depth behind the bowed front."""
    var bent = Float32(4) * t * (1 - t) * bow
    return mix_point(front, apex, t) + back * (bent + Float32(0.5) * depth)


def _pubic_body(edge: Vector3, S: Float32) -> Vector3:
    """Return the center of the pubic body beside a symphysis landmark."""
    return edge + Vector3(0.0072 * S, 0, -0.0010 * S)
