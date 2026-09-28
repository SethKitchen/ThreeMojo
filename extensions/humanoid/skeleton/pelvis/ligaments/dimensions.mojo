# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named ligaments and joint tissues of the pelvis, as implicit solids.

The set is the sacroiliac, sacrotuberous, sacrospinous and iliolumbar
ligaments, the inguinal ligament, the three ligaments of the hip
capsule, and the joint tissues: the acetabular labrum, the acetabular
cartilage and the interpubic disc. Radii are authored in centimeters
on the six-foot male template. They are not a cited width table. A
flat band is drawn as a round section.

Every part but the interpubic disc is paired, authored on the right
and mirrored on x for the left. The disc lies on the midline and is
the same on either side.

The solids live in the pelvis frame. The origin is the midpoint of the
two hip joint centers. Plus y is proximal. Plus x is body-right. Plus z
is anterior.

    var dims = pelvis_muscle_dimensions(person)
    var d = pelvis_ligament_distance(dims, INGUINAL, RIGHT, dims.gt)
"""

from extensions.humanoid.side import LEFT, BodySide
from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    empty_bounds,
    field_gradient,
    flip_x,
    mix_point,
    sd_ellipse_segment,
    smax,
)
from extensions.humanoid.skeleton.foot.chain import (
    SegmentSet,
    one_segment,
    segment_bounds,
    segment_distance,
    segment_volume,
    three_segments,
    two_segments,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    SOCKET_SPACE,
    TEMPLATE_CM,
    pelvis_frame,
    sacral_front,
    sided_bounds,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftTissue,
    cartilage_tissue,
    ligament_tissue,
    meniscus_tissue,
)
from math.vector3 import Vector3
from std.math import cos, max, pi, sqrt

# The bare acetabular fossa: no cartilage within this angle of the
# socket's pole.
comptime FOSSA_DEG = Float32(38.0)


@fieldwise_init
struct PelvisLigament(Equatable, ImplicitlyCopyable, Writable):
    """Which named pelvic ligament or joint tissue a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named ligament or joint tissue."""
        if self.value < 0:
            return False
        return self.value <= INTERPUBIC_DISC.value


comptime ANTERIOR_SACROILIAC = PelvisLigament(0)
comptime POSTERIOR_SACROILIAC = PelvisLigament(1)
comptime SACROTUBEROUS = PelvisLigament(2)
comptime SACROSPINOUS = PelvisLigament(3)
comptime ILIOLUMBAR = PelvisLigament(4)
comptime INGUINAL = PelvisLigament(5)
comptime ILIOFEMORAL = PelvisLigament(6)
comptime PUBOFEMORAL = PelvisLigament(7)
comptime ISCHIOFEMORAL = PelvisLigament(8)
# The fibrocartilage ring on the socket's rim.
comptime ACETABULAR_LABRUM = PelvisLigament(9)
# The horseshoe of hyaline cartilage lining the socket.
comptime ACETABULAR_CARTILAGE = PelvisLigament(10)
# The fibrocartilage disc of the pubic symphysis, on the midline.
comptime INTERPUBIC_DISC = PelvisLigament(11)


struct PelvisLigamentField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one pelvic ligament or joint tissue."""

    var part: PelvisLigament
    var segments: SegmentSet
    var hip: Vector3
    var axis: Vector3
    # The labrum: a ring of this radius and this tube radius.
    var ring: Float32
    var tube: Float32
    # The cartilage: a shell between these two radii.
    var inner: Float32
    var outer: Float32
    var fossa: Float32
    # The disc: an elliptical segment.
    var disc_a: Vector3
    var disc_b: Vector3
    var disc_ml: Float32
    var disc_ap: Float32
    var mirror: Bool
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        dimensions: PelvisMuscleDimensions,
        part: PelvisLigament,
        side: BodySide,
    ) raises:
        """Build one part from landmarks that `validate` accepts.

        Args:
            dimensions: Pelvis and femur landmarks.
            part: A named ligament or joint tissue.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If `dimensions.validate` refuses the copy, if `part`
                is not named, or if `side` is not valid.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A pelvic ligament must be a named ligament")
        if not side.is_valid():
            raise Error("A pelvis side must be RIGHT or LEFT")
        var p = dimensions.pelvis
        var S = p.stature.value
        self.part = part
        self.segments = _segments(dimensions, part)
        self.hip = p.hip
        self.axis = p.socket_axis
        var head = p.head_radius.value
        var socket = head + SOCKET_SPACE * S
        self.inner = head + 0.0004 * S
        self.outer = socket
        self.fossa = cos(FOSSA_DEG * pi / 180)
        # The labrum rides the rim between the socket and the cup's edge.
        self.ring = socket + 0.0012 * S
        self.tube = 0.0018 * S
        var top = p.symphysis_top
        var bottom = p.symphysis_bottom
        self.disc_a = mix_point(top, bottom, 0.08)
        self.disc_b = mix_point(top, bottom, 0.92)
        self.disc_ml = 0.0017 * S
        self.disc_ap = 0.0048 * S
        self.mirror = side == LEFT
        self.k = 0.0008 * S
        self.epsilon = 0.0003 * S
        var box: Bounds
        if part == ACETABULAR_LABRUM or part == ACETABULAR_CARTILAGE:
            box = empty_bounds()
            box.include_sphere(self.hip, self.ring + self.tube)
            box = box.padded(0.003)
        elif part == INTERPUBIC_DISC:
            box = empty_bounds()
            box.include_sphere(self.disc_a, self.disc_ap)
            box.include_sphere(self.disc_b, self.disc_ap)
            box = box.padded(0.003)
        else:
            box = segment_bounds(self.segments, 0.003 + 0.002 * S)
        var placed = sided_bounds(box.low, box.high, side)
        self.low = placed.low
        self.high = placed.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the part, in meters.

        Negative is inside. Zero is the surface.
        """
        var local = point
        if self.mirror:
            local = flip_x(point)
        if self.part == ACETABULAR_LABRUM:
            var offset = local - self.hip
            var height = offset.dot(self.axis)
            var flat = offset - self.axis * height
            var radial = flat.length() - self.ring
            return sqrt(radial * radial + height * height) - self.tube
        if self.part == ACETABULAR_CARTILAGE:
            var offset = local - self.hip
            var reach = offset.length()
            var middle = Float32(0.5) * (self.inner + self.outer)
            var half = Float32(0.5) * (self.outer - self.inner)
            var d = abs_gap(reach - middle) - half
            # Only inside the cup, and not over the bare fossa.
            d = smax(d, offset.dot(self.axis), self.k)
            return max(d, -offset.dot(self.axis) - self.fossa * reach)
        if self.part == INTERPUBIC_DISC:
            return sd_ellipse_segment(
                point,
                self.disc_a,
                self.disc_b,
                self.disc_ml,
                self.disc_ap,
                self.disc_ml,
                self.disc_ap,
                Vector3(1, 0, 0),
            )
        return segment_distance(self.segments, local, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)

    def volume(self) -> Float32:
        """Return the part's analytic volume, in cubic meters.

        A band is its frusta. The labrum is a torus. The cartilage is
        the shell's zone outside the fossa. The disc is an elliptical
        cylinder with rounded ends.
        """
        if self.part == ACETABULAR_LABRUM:
            return Float32(2) * pi * pi * self.ring * self.tube * self.tube
        if self.part == ACETABULAR_CARTILAGE:
            var cubes = (
                self.outer * self.outer * self.outer
                - self.inner * self.inner * self.inner
            )
            return Float32(2.0 / 3.0) * pi * cubes * self.fossa
        if self.part == INTERPUBIC_DISC:
            var area = pi * self.disc_ml * self.disc_ap
            var length = (self.disc_b - self.disc_a).length()
            var ends = (
                Float32(4.0 / 3.0)
                * pi
                * self.disc_ml
                * self.disc_ap
                * sqrt(self.disc_ml * self.disc_ap)
            )
            return area * length + ends
        return segment_volume(self.segments)


def abs_gap(value: Float32) -> Float32:
    """Return `value` without its sign.

    Args:
        value: A signed length.

    Returns:
        Its magnitude.
    """
    if value < 0:
        return -value
    return value


def pelvis_ligament_distance(
    dimensions: PelvisMuscleDimensions,
    part: PelvisLigament,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return PelvisLigamentField(dimensions, part, side).distance(point)


def pelvis_ligament_label(part: PelvisLigament) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A ligament or joint tissue, named or not.

    Returns:
        A short American English label, or `"pelvic ligament"` when
        `part` is not named.
    """
    if part == ANTERIOR_SACROILIAC:
        return "anterior sacroiliac ligament"
    if part == POSTERIOR_SACROILIAC:
        return "posterior sacroiliac ligament"
    if part == SACROTUBEROUS:
        return "sacrotuberous ligament"
    if part == SACROSPINOUS:
        return "sacrospinous ligament"
    if part == ILIOLUMBAR:
        return "iliolumbar ligament"
    if part == INGUINAL:
        return "inguinal ligament"
    if part == ILIOFEMORAL:
        return "iliofemoral ligament"
    if part == PUBOFEMORAL:
        return "pubofemoral ligament"
    if part == ISCHIOFEMORAL:
        return "ischiofemoral ligament"
    if part == ACETABULAR_LABRUM:
        return "acetabular labrum"
    if part == ACETABULAR_CARTILAGE:
        return "acetabular cartilage"
    if part == INTERPUBIC_DISC:
        return "interpubic disc"
    return "pelvic ligament"


def is_midline(part: PelvisLigament) raises -> Bool:
    """Return True if `part` lies on the midline and is not paired.

    Args:
        part: A named ligament or joint tissue.

    Returns:
        True for the interpubic disc.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A pelvic ligament must be a named ligament")
    return part == INTERPUBIC_DISC


def pelvis_ligament_tissue(part: PelvisLigament) raises -> SoftTissue:
    """Return the tissue `part` is made of.

    Args:
        part: A named ligament or joint tissue.

    Returns:
        Hyaline cartilage for the acetabular cartilage, fibrocartilage
        for the labrum and the disc, and ligament for the bands.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A pelvic ligament must be a named ligament")
    if part == ACETABULAR_CARTILAGE:
        return cartilage_tissue()
    if part == ACETABULAR_LABRUM or part == INTERPUBIC_DISC:
        return meniscus_tissue()
    return ligament_tissue()


def named_pelvis_ligaments() -> List[PelvisLigament]:
    """Return every named pelvic ligament and joint tissue.

    Returns:
        The nine bands, then the labrum, the cartilage and the disc.
    """
    var parts = List[PelvisLigament]()
    parts.append(ANTERIOR_SACROILIAC)
    parts.append(POSTERIOR_SACROILIAC)
    parts.append(SACROTUBEROUS)
    parts.append(SACROSPINOUS)
    parts.append(ILIOLUMBAR)
    parts.append(INGUINAL)
    parts.append(ILIOFEMORAL)
    parts.append(PUBOFEMORAL)
    parts.append(ISCHIOFEMORAL)
    parts.append(ACETABULAR_LABRUM)
    parts.append(ACETABULAR_CARTILAGE)
    parts.append(INTERPUBIC_DISC)
    return parts^


def _segments(
    dimensions: PelvisMuscleDimensions, part: PelvisLigament
) -> SegmentSet:
    """Return the bands of one named ligament, on the right side."""
    var p = dimensions.pelvis
    var f = pelvis_frame(p)
    var unit = TEMPLATE_CM * p.stature.value
    if part == ANTERIOR_SACROILIAC:
        # Across the front of the joint, in an upper and a lower band.
        var a = p.auricular
        return two_segments(
            a + f.template(-1.3, 0.1, 4.1),
            a + f.template(0.8, -0.5, 3.4),
            0.40 * unit,
            0.40 * unit,
            a + f.template(-1.4, -2.2, 3.1),
            a + f.template(0.6, -2.3, 2.4),
            0.40 * unit,
            0.40 * unit,
        )
    if part == POSTERIOR_SACROILIAC:
        # From the posterior spines to the sacral tubercles; the deeper
        # band is the interosseous ligament.
        return two_segments(
            p.psis,
            p.psis + f.template(-2.6, -4.3, 1.8),
            0.55 * unit,
            0.45 * unit,
            p.piis,
            p.piis + f.template(-3.0, -2.4, 2.2),
            0.55 * unit,
            0.45 * unit,
        )
    if part == SACROTUBEROUS:
        var upper = p.psis + f.template(-0.6, -3.0, 0.6)
        var border = sacral_front(p, 0.75) + f.template(2.7, 0, -1.8)
        var lower = p.tuberosity + f.template(-0.8, 0.6, -0.6)
        return two_segments(
            upper,
            border,
            0.65 * unit,
            0.55 * unit,
            border,
            lower,
            0.55 * unit,
            0.50 * unit,
        )
    if part == SACROSPINOUS:
        return one_segment(
            p.spine,
            sacral_front(p, 0.95) + f.template(1.4, 0, -0.55),
            0.45 * unit,
            0.55 * unit,
        )
    if part == ILIOLUMBAR:
        # To the fifth lumbar transverse process, which is not modeled.
        return one_segment(
            p.crest_back + f.template(-1.0, -0.55, 0.7),
            p.promontory + f.template(3.5, 3.3, -2.4),
            0.45 * unit,
            0.40 * unit,
        )
    if part == INGUINAL:
        # From the anterior superior spine to the pubic tubercle, sagging
        # a little forward and down.
        var middle = mix_point(p.asis, p.pubic_tubercle, 0.5) + f.template(
            0, -0.55, 0.75
        )
        return two_segments(
            p.asis,
            middle,
            0.33 * unit,
            0.33 * unit,
            middle,
            p.pubic_tubercle,
            0.33 * unit,
            0.33 * unit,
        )
    if part == ILIOFEMORAL:
        # The Y ligament: from below the anterior inferior spine to the
        # intertrochanteric line, in two limbs over the front of the
        # capsule.
        var start = p.aiis + f.template(0, -1.1, -0.4)
        var upper = dimensions.gt + f.template(-1.5, -0.4, 2.7)
        var lower = dimensions.lt + f.template(0.7, -0.4, 3.1)
        var bulge = f.template(0, 0, 0.7)
        return three_segments(
            start,
            mix_point(start, upper, 0.5) + bulge,
            0.65 * unit,
            0.60 * unit,
            mix_point(start, upper, 0.5) + bulge,
            upper,
            0.60 * unit,
            0.55 * unit,
            start,
            lower,
            0.60 * unit,
            0.55 * unit,
        )
    if part == PUBOFEMORAL:
        return one_segment(
            mix_point(p.eminence, p.pectineal, 0.4) + f.template(0, -0.7, 0),
            dimensions.lt + f.template(0.2, 0.7, 2.2),
            0.45 * unit,
            0.40 * unit,
        )
    # Ischiofemoral: from behind the socket over the back of the neck.
    return one_segment(
        p.ischium + f.template(0.7, -0.2, -1.1),
        dimensions.gt + f.template(-1.3, 0.2, -0.7),
        0.45 * unit,
        0.40 * unit,
    )
