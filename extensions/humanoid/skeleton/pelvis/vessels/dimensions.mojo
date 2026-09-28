# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named arteries and veins of the pelvis, as implicit tubes.

The centerlines follow the lowest abdominal aorta to its bifurcation,
the common, external and internal iliac arteries, the gluteal,
internal pudendal and obturator branches, and the median sacral
artery. The veins are the inferior vena cava and the common, external
and internal iliac veins. Each external iliac vessel ends where the
leg's femoral vessel begins.

The aorta, the inferior vena cava and the median sacral artery are
unpaired: the aorta lies a little left of the midline and the vena
cava right of it. Every other vessel is paired, authored on the right
and mirrored on x for the left. The left common iliac vein crosses the
midline to the vena cava.

Physical radii drive distance and mass. Geometry applies a separate
diagrammatic minimum radius so the current isosurface can show them.

    var dims = pelvis_muscle_dimensions(person)
    var d = pelvis_vessel_distance(dims, EXTERNAL_ILIAC_ARTERY, RIGHT, p)
"""

from extensions.humanoid.side import LEFT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    field_gradient,
    flip_x,
    mix_point,
    tube_chain_bounds,
    tube_chain_distance,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    PelvisDimensions,
    pelvis_frame,
    sacral_back,
    sacral_front,
    sided_bounds,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
)
from math.vector3 import Vector3
from std.math import max


@fieldwise_init
struct PelvisVessel(Equatable, ImplicitlyCopyable, Writable):
    """Which named pelvic artery or vein a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named vessels is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named vessel."""
        if self.value < 0:
            return False
        return self.value <= INTERNAL_ILIAC_VEIN.value


comptime ABDOMINAL_AORTA = PelvisVessel(0)
comptime COMMON_ILIAC_ARTERY = PelvisVessel(1)
comptime EXTERNAL_ILIAC_ARTERY = PelvisVessel(2)
comptime INTERNAL_ILIAC_ARTERY = PelvisVessel(3)
comptime SUPERIOR_GLUTEAL_ARTERY = PelvisVessel(4)
comptime INFERIOR_GLUTEAL_ARTERY = PelvisVessel(5)
comptime INTERNAL_PUDENDAL_ARTERY = PelvisVessel(6)
comptime OBTURATOR_ARTERY = PelvisVessel(7)
comptime MEDIAN_SACRAL_ARTERY = PelvisVessel(8)
comptime INFERIOR_VENA_CAVA = PelvisVessel(9)
comptime COMMON_ILIAC_VEIN = PelvisVessel(10)
comptime EXTERNAL_ILIAC_VEIN = PelvisVessel(11)
comptime INTERNAL_ILIAC_VEIN = PelvisVessel(12)


struct PelvisVesselField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one pelvic vessel on one side."""

    var chain: TubeChain
    var mirror: Bool
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        dimensions: PelvisMuscleDimensions,
        part: PelvisVessel,
        side: BodySide,
    ) raises:
        """Build one vessel from landmarks that `validate` accepts.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named vessel.
            side: `RIGHT` or `LEFT`. An unpaired vessel ignores it.

        Raises:
            Error: If `dimensions.validate` refuses the copy, if `part`
                is not named, or if `side` is not valid.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A pelvic vessel must be a named artery or vein")
        if not side.is_valid():
            raise Error("A pelvis side must be RIGHT or LEFT")
        self.chain = _chain(dimensions, part, side)
        self.mirror = side == LEFT and not _unpaired(part)
        self.k = Float32(0.00025)
        self.epsilon = Float32(0.00015)
        var box = tube_chain_bounds(self.chain, Float32(0.003) + self.chain.r0)
        if self.mirror:
            box = sided_bounds(box.low, box.high, side)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the vessel, in meters.

        Negative is inside. Zero is the surface.
        """
        if self.mirror:
            return tube_chain_distance(self.chain, flip_x(point), self.k)
        return tube_chain_distance(self.chain, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)

    def widened(self, least: Float32) -> PelvisVesselField:
        """Return a copy whose radii are at least `least`, for display.

        Args:
            least: The smallest radius a mesh shows, in meters.

        Returns:
            A wider copy with a larger blend and box.
        """
        var field = self
        field.chain.r0 = max(field.chain.r0, least)
        field.chain.r1 = max(field.chain.r1, least)
        field.chain.r2 = max(field.chain.r2, least)
        field.chain.r3 = max(field.chain.r3, least)
        field.chain.r4 = max(field.chain.r4, least)
        field.k = Float32(0.4) * least
        field.epsilon = Float32(0.25) * least
        field.low = field.low - Vector3(least, least, least)
        field.high = field.high + Vector3(least, least, least)
        return field


def pelvis_vessel_distance(
    dimensions: PelvisMuscleDimensions,
    part: PelvisVessel,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which vessel to sample.
        side: `RIGHT` or `LEFT`. An unpaired vessel ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return PelvisVesselField(dimensions, part, side).distance(point)


def pelvis_vessel_label(part: PelvisVessel) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A pelvic vessel, named or not.

    Returns:
        A short American English label, or `"pelvic vessel"` when
        `part` is not named.
    """
    if part == ABDOMINAL_AORTA:
        return "abdominal aorta"
    if part == COMMON_ILIAC_ARTERY:
        return "common iliac artery"
    if part == EXTERNAL_ILIAC_ARTERY:
        return "external iliac artery"
    if part == INTERNAL_ILIAC_ARTERY:
        return "internal iliac artery"
    if part == SUPERIOR_GLUTEAL_ARTERY:
        return "superior gluteal artery"
    if part == INFERIOR_GLUTEAL_ARTERY:
        return "inferior gluteal artery"
    if part == INTERNAL_PUDENDAL_ARTERY:
        return "internal pudendal artery"
    if part == OBTURATOR_ARTERY:
        return "obturator artery"
    if part == MEDIAN_SACRAL_ARTERY:
        return "median sacral artery"
    if part == INFERIOR_VENA_CAVA:
        return "inferior vena cava"
    if part == COMMON_ILIAC_VEIN:
        return "common iliac vein"
    if part == EXTERNAL_ILIAC_VEIN:
        return "external iliac vein"
    if part == INTERNAL_ILIAC_VEIN:
        return "internal iliac vein"
    return "pelvic vessel"


def is_pelvic_artery(part: PelvisVessel) raises -> Bool:
    """Return True if `part` is an artery.

    Args:
        part: A named vessel.

    Returns:
        True for the aorta and the eight arteries after it.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A pelvic vessel must be a named artery or vein")
    return part.value <= MEDIAN_SACRAL_ARTERY.value


def is_unpaired_vessel(part: PelvisVessel) raises -> Bool:
    """Return True if `part` is a single vessel, not one of a pair.

    Args:
        part: A named vessel.

    Returns:
        True for the aorta, the median sacral artery and the inferior
        vena cava.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A pelvic vessel must be a named artery or vein")
    return _unpaired(part)


def named_pelvis_vessels() -> List[PelvisVessel]:
    """Return every named pelvic vessel in a stable order.

    Returns:
        Nine arteries, then four veins.
    """
    var parts = List[PelvisVessel]()
    for index in range(INTERNAL_ILIAC_VEIN.value + 1):
        parts.append(PelvisVessel(index))
    return parts^


def _unpaired(part: PelvisVessel) -> Bool:
    """Return True for the three midline vessels."""
    if part == ABDOMINAL_AORTA or part == MEDIAN_SACRAL_ARTERY:
        return True
    return part == INFERIOR_VENA_CAVA


@fieldwise_init
struct VesselLandmarks(ImplicitlyCopyable):
    """The branch points the pelvic vessels share, in meters.

    The bifurcation of the aorta, the division of the right common
    iliac artery, the point behind the middle of the inguinal ligament,
    the confluence of the common iliac veins, and the division of the
    right common iliac vein.
    """

    var bifurcation: Vector3
    var division: Vector3
    var inguinal: Vector3
    var confluence: Vector3
    var vein_division: Vector3


def vessel_landmarks(p: PelvisDimensions) -> VesselLandmarks:
    """Return the aortic bifurcation, the iliac divisions and the rest.

    Args:
        p: Landmarks from `pelvis_dimensions`.

    Returns:
        The shared branch points, on the right where they are paired.
    """
    var f = pelvis_frame(p)
    var division = p.promontory + f.template(4.2, 0.8, 1.3)
    return VesselLandmarks(
        p.promontory + f.template(0, 7.0, 3.9),
        division,
        # Behind the middle of the inguinal ligament.
        mix_point(p.asis, p.symphysis_top, 0.5) + f.template(0, -0.35, -0.9),
        # The common iliac veins join right of the midline.
        p.promontory + f.template(1.6, 5.6, 3.0),
        division + f.template(-0.4, -0.55, -1.1),
    )


def _chain(
    d: PelvisMuscleDimensions, part: PelvisVessel, side: BodySide
) -> TubeChain:
    """Return one vessel's centerline and radii.

    A paired vessel is on the right; an unpaired one where it lies.
    """
    var p = d.pelvis
    var f = pelvis_frame(p)
    var S = p.stature.value
    var at = vessel_landmarks(p)
    var branch = at.division + f.template(0.8, -4.2, -4.2)
    var trunk = at.division + f.template(1.0, -6.0, -3.8)
    var tail = at.division + f.template(1.0, -7.4, -3.0)
    if part == ABDOMINAL_AORTA:
        var b = at.bifurcation
        return TubeChain(
            b + f.template(-0.9, 5.1, 0.1),
            b + f.template(-0.7, 3.4, 0.1),
            b + f.template(-0.5, 2.1, 0.05),
            b + f.template(-0.25, 1.0, 0),
            b,
            0.0050 * S,
            0.0050 * S,
            0.0049 * S,
            0.0048 * S,
            0.0047 * S,
        )
    if part == COMMON_ILIAC_ARTERY:
        return _straight(at.bifurcation, at.division, 0.0026 * S, 0.0025 * S)
    if part == EXTERNAL_ILIAC_ARTERY:
        return TubeChain(
            at.division,
            mix_point(at.division, at.inguinal, 0.4) + f.template(0.3, 0, 0.3),
            mix_point(at.division, at.inguinal, 0.75) + f.template(0.1, 0, 0.2),
            at.inguinal,
            d.femoral_artery,
            0.0021 * S,
            0.0021 * S,
            0.0021 * S,
            0.0020 * S,
            0.0020 * S,
        )
    if part == INTERNAL_ILIAC_ARTERY:
        return TubeChain(
            at.division,
            at.division + f.template(0.6, -2.5, -2.5),
            branch,
            trunk,
            tail,
            0.0019 * S,
            0.0018 * S,
            0.0016 * S,
            0.0014 * S,
            0.0012 * S,
        )
    if part == SUPERIOR_GLUTEAL_ARTERY:
        # Out through the greater sciatic foramen above the piriformis.
        return TubeChain(
            branch,
            p.notch + f.template(-0.6, 0.4, -1.5),
            p.notch + f.template(0.2, 1.1, -2.7),
            f.template(9.3, 5.2, -7.3),
            f.template(10.5, 6.5, -7.0),
            0.0013 * S,
            0.0013 * S,
            0.0012 * S,
            0.0011 * S,
            0.0010 * S,
        )
    if part == INFERIOR_GLUTEAL_ARTERY:
        # Out below the piriformis into the gluteus maximus.
        return TubeChain(
            trunk,
            p.notch + f.template(-1.6, -2.1, -2.3),
            p.notch + f.template(0, -3.8, -3.8),
            f.template(8.6, -2.4, -9.1),
            f.template(9.5, -3.5, -9.5),
            0.0011 * S,
            0.0011 * S,
            0.0010 * S,
            0.0009 * S,
            0.0008 * S,
        )
    if part == INTERNAL_PUDENDAL_ARTERY:
        # Around the ischial spine and forward in the pudendal canal.
        var canal = mix_point(p.tuberosity, p.ramus, 0.4) + f.template(
            -1.3, 0.55, 0
        )
        var perineum = p.symphysis_bottom + f.template(2.0, -0.7, -0.7)
        return TubeChain(
            tail,
            p.spine + f.template(0.2, -0.2, -1.1),
            canal,
            mix_point(canal, perineum, 0.5),
            perineum,
            0.0009 * S,
            0.0009 * S,
            0.0008 * S,
            0.0008 * S,
            0.0007 * S,
        )
    if part == OBTURATOR_ARTERY:
        # Along the side wall and out through the obturator canal.
        return TubeChain(
            trunk,
            f.template(5.6, -0.2, -0.4),
            p.obturator + f.template(0.5, 2.6, 0.2),
            p.obturator + f.template(1.3, 1.4, 1.2),
            p.obturator + f.template(1.8, 1.2, 1.8),
            0.0009 * S,
            0.0009 * S,
            0.0008 * S,
            0.0008 * S,
            0.0007 * S,
        )
    if part == MEDIAN_SACRAL_ARTERY:
        var ahead = sacral_back(p) * (-0.0022 * S)
        return TubeChain(
            at.bifurcation + f.template(0, -0.3, -0.5),
            sacral_front(p, 0.0) + ahead,
            sacral_front(p, 0.35) + ahead,
            sacral_front(p, 0.7) + ahead,
            sacral_front(p, 1.0) + ahead,
            0.0006 * S,
            0.0006 * S,
            0.0005 * S,
            0.0005 * S,
            0.0004 * S,
        )
    if part == INFERIOR_VENA_CAVA:
        var c = at.confluence
        return TubeChain(
            c,
            c + f.template(0.3, 1.7, 0.1),
            c + f.template(0.5, 3.4, 0.2),
            c + f.template(0.6, 5.0, 0.3),
            c + f.template(0.6, 6.5, 0.4),
            0.0058 * S,
            0.0059 * S,
            0.0060 * S,
            0.0060 * S,
            0.0060 * S,
        )
    if part == COMMON_ILIAC_VEIN:
        # From the vena cava, behind the artery, to the vein division.
        # The join is right of the midline for either side.
        var join = at.confluence
        if side == LEFT:
            join = flip_x(at.confluence)
        var behind = f.template(0, 0, -0.5)
        return TubeChain(
            join,
            mix_point(join, at.vein_division, 0.3) + behind,
            mix_point(join, at.vein_division, 0.55) + behind,
            mix_point(join, at.vein_division, 0.8) + behind,
            at.vein_division,
            0.0034 * S,
            0.0034 * S,
            0.0034 * S,
            0.0033 * S,
            0.0032 * S,
        )
    if part == EXTERNAL_ILIAC_VEIN:
        var v = at.vein_division
        return TubeChain(
            v,
            mix_point(v, at.inguinal, 0.4) + f.template(-0.6, 0, -0.2),
            mix_point(v, at.inguinal, 0.75) + f.template(-1.0, 0, 0),
            at.inguinal + f.template(-1.2, -0.2, -0.3),
            d.femoral_vein,
            0.0029 * S,
            0.0029 * S,
            0.0029 * S,
            0.0028 * S,
            0.0028 * S,
        )
    var v = at.vein_division
    return TubeChain(
        v,
        v + f.template(0.5, -2.3, -2.9),
        v + f.template(0.9, -4.3, -3.6),
        v + f.template(1.1, -6.2, -3.3),
        v + f.template(1.1, -7.3, -2.6),
        0.0025 * S,
        0.0023 * S,
        0.0021 * S,
        0.0019 * S,
        0.0018 * S,
    )


def _straight(a: Vector3, b: Vector3, ra: Float32, rb: Float32) -> TubeChain:
    """Return a straight tube from `a` to `b`."""
    return TubeChain(
        a,
        mix_point(a, b, 0.25),
        mix_point(a, b, 0.50),
        mix_point(a, b, 0.75),
        b,
        ra,
        ra + (rb - ra) * 0.25,
        ra + (rb - ra) * 0.50,
        ra + (rb - ra) * 0.75,
        rb,
    )
