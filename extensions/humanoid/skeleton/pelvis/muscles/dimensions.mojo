# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named muscles of the pelvis, as implicit solids in the pelvis frame.

The set is the iliopsoas, the deep lateral rotators of the hip, the
gluteus minimus, the pelvic floor, and the lowest part of the trunk
wall that rises from the crest. The gluteus maximus and medius, the
tensor and the thigh muscles belong to the leg. The trunk is not
modeled yet, so the trunk-wall muscles end a short way above the
crest.

Every muscle is paired. Each is authored on the right side; a left
muscle mirrors it on x. A muscle is one to three chains of five
elliptical stations. Radii are authored in centimeters on the six-foot
male template, scaled by stature and by athleticism. They are template
parameters. They are not a cited cross-section table.

The solids live in the pelvis frame. The origin is the midpoint of the
two hip joint centers. Plus y is proximal. Plus x is body-right. Plus z
is anterior.

`PelvisMuscleDimensions` also carries the femur's landmarks in this
frame, and the points where the leg's vessels and nerves begin. The
pelvic vessels, nerves and lymphatics run on to those points.

    var dims = pelvis_muscle_dimensions(person)
    var d = pelvis_muscle_distance(dims, PIRIFORMIS, RIGHT, dims.gt)
"""

from extensions.humanoid.athleticism import Athleticism, radius_scale
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    empty_bounds,
    field_gradient,
    finite_point,
    flip_x,
    mix_point,
    sd_ellipse_segment,
    smin,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import femur_dimensions
from extensions.humanoid.skeleton.leg.lymph.dimensions import (
    INGUINAL_NODES,
    LymphField,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.nerves.dimensions import (
    FEMORAL_NERVE,
    SCIATIC_NERVE,
    NerveField,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    FEMORAL_ARTERY,
    FEMORAL_VEIN,
    VesselField,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    TEMPLATE_CM,
    PelvisDimensions,
    pelvis_dimensions,
    pelvis_frame,
    sacral_front,
    sided_bounds,
)
from math.vector3 import Vector3
from std.math import isfinite, pi, sqrt


@fieldwise_init
struct PelvisMuscle(Equatable, ImplicitlyCopyable, Writable):
    """Which named pelvic muscle a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named muscles is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named pelvic muscle."""
        if self.value < 0:
            return False
        return self.value <= ERECTOR_SPINAE.value


comptime ILIACUS = PelvisMuscle(0)
comptime PSOAS_MAJOR = PelvisMuscle(1)
comptime PIRIFORMIS = PelvisMuscle(2)
comptime OBTURATOR_INTERNUS = PelvisMuscle(3)
# The superior and inferior gemelli, which run beside the obturator
# internus tendon.
comptime GEMELLI = PelvisMuscle(4)
comptime QUADRATUS_FEMORIS = PelvisMuscle(5)
comptime OBTURATOR_EXTERNUS = PelvisMuscle(6)
comptime GLUTEUS_MINIMUS = PelvisMuscle(7)
comptime LEVATOR_ANI = PelvisMuscle(8)
comptime COCCYGEUS = PelvisMuscle(9)
comptime RECTUS_ABDOMINIS = PelvisMuscle(10)
# The lateral abdominal wall above the crest: the external and internal
# obliques and the transversus, drawn as one layer.
comptime EXTERNAL_OBLIQUE = PelvisMuscle(11)
comptime QUADRATUS_LUMBORUM = PelvisMuscle(12)
# The erector spinae and the multifidus over the sacrum.
comptime ERECTOR_SPINAE = PelvisMuscle(13)


@fieldwise_init
struct Radii(ImplicitlyCopyable):
    """Five radii of one chain, in template centimeters."""

    var r0: Float32
    var r1: Float32
    var r2: Float32
    var r3: Float32
    var r4: Float32


@fieldwise_init
struct PelvisChain(ImplicitlyCopyable):
    """Five tapered elliptical stations of one muscle, in meters.

    `ml` is the radius along x after the tangent is projected out.
    `ap` is the radius along the axis across both.
    """

    var p0: Vector3
    var p1: Vector3
    var p2: Vector3
    var p3: Vector3
    var p4: Vector3
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


@fieldwise_init
struct PelvisChainSet(ImplicitlyCopyable):
    """One to three chains of one solid."""

    var count: Int
    var c0: PelvisChain
    var c1: PelvisChain
    var c2: PelvisChain


@fieldwise_init
struct PelvisMuscleDimensions(ImplicitlyCopyable):
    """Pelvis landmarks, femur landmarks, leg junctions and the scale.

    Every point is in the pelvis frame, on the right side, in meters.
    """

    var pelvis: PelvisDimensions
    var athleticism: Athleticism
    var scale: Float32
    var k: Float32
    var epsilon: Float32
    var gt: Vector3
    var lt: Vector3
    var neck: Vector3
    # The trochanteric fossa, where the deep rotators insert.
    var fossa: Vector3
    # Where the leg's femoral artery, femoral vein, femoral nerve and
    # sciatic nerve begin, and its highest inguinal node.
    var femoral_artery: Vector3
    var femoral_vein: Vector3
    var femoral_nerve: Vector3
    var sciatic_nerve: Vector3
    var inguinal: Vector3
    # The right leg frame's origin in the pelvis frame.
    var leg_origin: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If the pelvis fails `validate`, if athleticism is not
                named, if scale, blend radius or gradient step is not
                positive, or if a landmark is not finite.
        """
        self.pelvis.validate()
        if not self.athleticism.is_valid():
            raise Error("A pelvic muscle needs a toned or untoned athleticism")
        if not isfinite(self.scale) or self.scale <= 0:
            raise Error("A pelvic muscle radius scale must be positive")
        if not isfinite(self.k) or self.k <= 0:
            raise Error("A pelvic muscle blend radius must be positive")
        if not isfinite(self.epsilon) or self.epsilon <= 0:
            raise Error("A pelvic muscle gradient step must be positive")
        finite_point(self.gt, "greater trochanter", "pelvic muscle")
        finite_point(self.lt, "lesser trochanter", "pelvic muscle")
        finite_point(self.neck, "femoral neck", "pelvic muscle")
        finite_point(self.fossa, "trochanteric fossa", "pelvic muscle")
        finite_point(self.femoral_artery, "femoral artery", "pelvic muscle")
        finite_point(self.femoral_vein, "femoral vein", "pelvic muscle")
        finite_point(self.femoral_nerve, "femoral nerve", "pelvic muscle")
        finite_point(self.sciatic_nerve, "sciatic nerve", "pelvic muscle")
        finite_point(self.inguinal, "inguinal node", "pelvic muscle")
        finite_point(self.leg_origin, "leg origin", "pelvic muscle")

    def leg_origin_at(self, side: BodySide) raises -> Vector3:
        """Return one leg frame's origin in the pelvis frame.

        Args:
            side: `RIGHT` or `LEFT`.

        Returns:
            Where that leg's knee origin sits, so its femoral head meets
            the socket.

        Raises:
            Error: If `side` is not valid.
        """
        if not side.is_valid():
            raise Error("A pelvis side must be RIGHT or LEFT")
        if side == LEFT:
            return flip_x(self.leg_origin)
        return self.leg_origin


struct PelvisMuscleField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one pelvic muscle on one side."""

    var chains: PelvisChainSet
    var mirror: Bool
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        dimensions: PelvisMuscleDimensions,
        part: PelvisMuscle,
        side: BodySide,
    ) raises:
        """Build one muscle from dimensions that `validate` accepts.

        Args:
            dimensions: Landmarks and the belly scale.
            part: A named muscle.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If `dimensions.validate` refuses the copy, if `part`
                is not named, or if `side` is not valid.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A pelvic muscle must be a named muscle")
        if not side.is_valid():
            raise Error("A pelvis side must be RIGHT or LEFT")
        self.chains = _chains(dimensions, part)
        self.mirror = side == LEFT
        self.k = dimensions.k
        self.epsilon = dimensions.epsilon
        var box = chain_set_bounds(self.chains, 0.004)
        var placed = sided_bounds(box.low, box.high, side)
        self.low = placed.low
        self.high = placed.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the muscle, in meters.

        Negative is inside. Zero is the surface.
        """
        var local = point
        if self.mirror:
            local = flip_x(point)
        return chain_set_distance(self.chains, local, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def pelvis_muscle_dimensions(
    spec: HumanoidSpec,
) raises -> PelvisMuscleDimensions:
    """Return pelvic muscle landmarks sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.

    Returns:
        Pelvis and femur landmarks, the leg junctions and the radius
        scale, in the pelvis frame.

    Raises:
        Error: If `spec` is refused, or athleticism is not named.
    """
    if not spec.athleticism.is_valid():
        raise Error("A pelvic muscle needs a toned or untoned athleticism")
    var pelvis = pelvis_dimensions(spec.stature, spec.sex)
    var femur = femur_dimensions(spec.stature, spec.sex, RIGHT)
    var S = spec.stature.value
    var head = femur.head_center
    var gt = pelvis.hip + (femur.greater_trochanter - head)
    var leg = muscle_dimensions(spec, RIGHT)
    # The right leg frame sits where its femoral head meets the socket.
    var origin = pelvis.hip - leg.hip
    return PelvisMuscleDimensions(
        pelvis,
        spec.athleticism,
        radius_scale(spec.athleticism),
        0.0030 * S,
        0.0008 * S,
        gt,
        pelvis.hip + (femur.lesser_trochanter - head),
        pelvis.hip + (femur.neck_base - head),
        gt + Vector3(-0.0090 * S, -0.0010 * S, -0.0033 * S),
        origin + VesselField(leg, FEMORAL_ARTERY).chain.p0,
        origin + VesselField(leg, FEMORAL_VEIN).chain.p0,
        origin + NerveField(leg, FEMORAL_NERVE).chain.p0,
        origin + NerveField(leg, SCIATIC_NERVE).chain.p0,
        origin + LymphField(leg, INGUINAL_NODES).c0,
        origin,
    )


def pelvis_muscle_distance(
    dimensions: PelvisMuscleDimensions,
    part: PelvisMuscle,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which muscle to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return PelvisMuscleField(dimensions, part, side).distance(point)


def pelvis_muscle_label(part: PelvisMuscle) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A pelvic muscle, named or not.

    Returns:
        A short American English label, or `"pelvic muscle"` when
        `part` is not named.
    """
    if part == ILIACUS:
        return "iliacus"
    if part == PSOAS_MAJOR:
        return "psoas major"
    if part == PIRIFORMIS:
        return "piriformis"
    if part == OBTURATOR_INTERNUS:
        return "obturator internus"
    if part == GEMELLI:
        return "gemelli"
    if part == QUADRATUS_FEMORIS:
        return "quadratus femoris"
    if part == OBTURATOR_EXTERNUS:
        return "obturator externus"
    if part == GLUTEUS_MINIMUS:
        return "gluteus minimus"
    if part == LEVATOR_ANI:
        return "levator ani"
    if part == COCCYGEUS:
        return "coccygeus"
    if part == RECTUS_ABDOMINIS:
        return "rectus abdominis"
    if part == EXTERNAL_OBLIQUE:
        return "abdominal wall"
    if part == QUADRATUS_LUMBORUM:
        return "quadratus lumborum"
    if part == ERECTOR_SPINAE:
        return "erector spinae"
    return "pelvic muscle"


def named_pelvis_muscles() -> List[PelvisMuscle]:
    """Return every named pelvic muscle in a stable order.

    Returns:
        The iliopsoas, the deep hip muscles, the pelvic floor and the
        trunk wall. Fourteen muscles, each paired.
    """
    var parts = List[PelvisMuscle]()
    parts.append(ILIACUS)
    parts.append(PSOAS_MAJOR)
    parts.append(PIRIFORMIS)
    parts.append(OBTURATOR_INTERNUS)
    parts.append(GEMELLI)
    parts.append(QUADRATUS_FEMORIS)
    parts.append(OBTURATOR_EXTERNUS)
    parts.append(GLUTEUS_MINIMUS)
    parts.append(LEVATOR_ANI)
    parts.append(COCCYGEUS)
    parts.append(RECTUS_ABDOMINIS)
    parts.append(EXTERNAL_OBLIQUE)
    parts.append(QUADRATUS_LUMBORUM)
    parts.append(ERECTOR_SPINAE)
    return parts^


def chain_distance(chain: PelvisChain, point: Vector3, k: Float32) -> Float32:
    """Return how far `point` lies outside one elliptical chain.

    Args:
        chain: Five stations.
        point: A point in the same frame, in meters.
        k: Smooth-union radius, in meters.

    Returns:
        The signed distance, in meters.
    """
    var ml = Vector3(1, 0, 0)
    var c = chain
    var d = sd_ellipse_segment(
        point, c.p0, c.p1, c.ml0, c.ap0, c.ml1, c.ap1, ml
    )
    d = smin(
        d,
        sd_ellipse_segment(point, c.p1, c.p2, c.ml1, c.ap1, c.ml2, c.ap2, ml),
        k,
    )
    d = smin(
        d,
        sd_ellipse_segment(point, c.p2, c.p3, c.ml2, c.ap2, c.ml3, c.ap3, ml),
        k,
    )
    return smin(
        d,
        sd_ellipse_segment(point, c.p3, c.p4, c.ml3, c.ap3, c.ml4, c.ap4, ml),
        k,
    )


def chain_set_distance(
    set: PelvisChainSet, point: Vector3, k: Float32
) -> Float32:
    """Return how far `point` lies outside a chain set.

    Args:
        set: One to three chains.
        point: A point in the same frame, in meters.
        k: Smooth-union radius, in meters.

    Returns:
        The signed distance, in meters.
    """
    var d = chain_distance(set.c0, point, k)
    if set.count < 2:
        return d
    d = smin(d, chain_distance(set.c1, point, k), k)
    if set.count < 3:
        return d
    return smin(d, chain_distance(set.c2, point, k), k)


def chain_set_bounds(set: PelvisChainSet, pad: Float32) -> Bounds:
    """Return a padded box that holds a chain set.

    Args:
        set: One to three chains.
        pad: Extra margin, in meters.

    Returns:
        An axis-aligned box around the used chains.
    """
    var box = empty_bounds()
    _include_chain(box, set.c0)
    if set.count >= 2:
        _include_chain(box, set.c1)
    if set.count >= 3:
        _include_chain(box, set.c2)
    return box.padded(pad)


def chain_set_volume(set: PelvisChainSet) -> Float32:
    """Return the analytic volume of a chain set.

    Each segment is an elliptical frustum. Each chain's two ends are
    capped by half ellipsoids. Overlapping chains count twice; that is
    an authored envelope, not a dissected volume.

    Args:
        set: One to three chains.

    Returns:
        Approximate envelope volume, in cubic meters.
    """
    var volume = _chain_volume(set.c0)
    if set.count >= 2:
        volume += _chain_volume(set.c1)
    if set.count >= 3:
        volume += _chain_volume(set.c2)
    return volume


def round_chain(
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    p4: Vector3,
    radii: Radii,
    unit: Float32,
) -> PelvisChain:
    """Return a chain with round stations.

    Args:
        p0: First station, in meters.
        p1: Second station.
        p2: Third station.
        p3: Fourth station.
        p4: Fifth station.
        radii: Radii in template centimeters.
        unit: Meters per template centimeter.

    Returns:
        The chain.
    """
    return flat_chain(p0, p1, p2, p3, p4, radii, radii, unit)


def flat_chain(
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    p4: Vector3,
    ml: Radii,
    ap: Radii,
    unit: Float32,
) -> PelvisChain:
    """Return a chain with elliptical stations.

    Args:
        p0: First station, in meters.
        p1: Second station.
        p2: Third station.
        p3: Fourth station.
        p4: Fifth station.
        ml: Radii along x, in template centimeters.
        ap: Radii across, in template centimeters.
        unit: Meters per template centimeter.

    Returns:
        The chain.
    """
    return PelvisChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        ml.r0 * unit,
        ml.r1 * unit,
        ml.r2 * unit,
        ml.r3 * unit,
        ml.r4 * unit,
        ap.r0 * unit,
        ap.r1 * unit,
        ap.r2 * unit,
        ap.r3 * unit,
        ap.r4 * unit,
    )


def _include_chain(mut box: Bounds, c: PelvisChain):
    """Grow `box` to hold every station of one chain."""
    box.include_sphere(c.p0, max_f(c.ml0, c.ap0))
    box.include_sphere(c.p1, max_f(c.ml1, c.ap1))
    box.include_sphere(c.p2, max_f(c.ml2, c.ap2))
    box.include_sphere(c.p3, max_f(c.ml3, c.ap3))
    box.include_sphere(c.p4, max_f(c.ml4, c.ap4))


def max_f(a: Float32, b: Float32) -> Float32:
    """Return the larger of two radii.

    Args:
        a: A radius.
        b: Another radius.

    Returns:
        The larger one.
    """
    if a > b:
        return a
    return b


def _chain_volume(c: PelvisChain) -> Float32:
    """Return one chain's frusta and end caps."""
    var volume = _frustum(c.p0, c.p1, c.ml0 * c.ap0, c.ml1 * c.ap1)
    volume += _frustum(c.p1, c.p2, c.ml1 * c.ap1, c.ml2 * c.ap2)
    volume += _frustum(c.p2, c.p3, c.ml2 * c.ap2, c.ml3 * c.ap3)
    volume += _frustum(c.p3, c.p4, c.ml3 * c.ap3, c.ml4 * c.ap4)
    var first = c.ml0 * c.ap0
    var last = c.ml4 * c.ap4
    volume += (
        Float32(2.0 / 3.0) * pi * (first * sqrt(first) + last * sqrt(last))
    )
    return volume


def _frustum(
    a: Vector3, b: Vector3, area_a: Float32, area_b: Float32
) -> Float32:
    """Return the volume of one elliptical frustum.

    The areas are the products of the two radii at each end.
    """
    var length = (b - a).length()
    return pi * length * (area_a + area_b + sqrt(area_a * area_b)) / Float32(3)


def _one(chain: PelvisChain) -> PelvisChainSet:
    """Return a set of one chain."""
    return PelvisChainSet(1, chain, chain, chain)


def _two(first: PelvisChain, second: PelvisChain) -> PelvisChainSet:
    """Return a set of two chains."""
    return PelvisChainSet(2, first, second, first)


def _three(
    first: PelvisChain, second: PelvisChain, third: PelvisChain
) -> PelvisChainSet:
    """Return a set of three chains."""
    return PelvisChainSet(3, first, second, third)


def _chains(d: PelvisMuscleDimensions, part: PelvisMuscle) -> PelvisChainSet:
    """Return the chains of one named muscle, on the right side."""
    var f = pelvis_frame(d.pelvis)
    var S = d.pelvis.stature.value
    # Meters per template centimeter, with the athleticism scale.
    var unit = TEMPLATE_CM * S * d.scale
    var p = d.pelvis
    # Where the iliacus and the psoas meet in front of the hip, and
    # where their tendon turns down toward the lesser trochanter.
    var lacuna = f.template(9.15, 2.15, 4.5)
    var tendon = f.template(10.2, -2.5, 3.6)
    if part == ILIACUS:
        var r_a = Radii(1.1, 1.3, 1.2, 0.9, 0.5)
        var r_b = Radii(1.2, 1.4, 1.2, 0.9, 0.5)
        var r_c = Radii(1.0, 1.2, 1.2, 1.1, 0.9)
        return _three(
            round_chain(
                f.template(10.6, 8.8, 2.1),
                f.template(9.9, 5.5, 3.3),
                lacuna,
                tendon,
                d.lt,
                r_a,
                unit,
            ),
            round_chain(
                f.template(9.9, 10.9, -1.9),
                f.template(9.4, 6.5, 1.3),
                lacuna,
                tendon,
                d.lt,
                r_b,
                unit,
            ),
            round_chain(
                f.template(7.8, 9.7, -4.6),
                f.template(7.9, 6.0, -1.0),
                f.template(8.4, 4.0, 1.8),
                lacuna,
                tendon,
                r_c,
                unit,
            ),
        )
    if part == PSOAS_MAJOR:
        # From beside the lumbar bodies, over the brim, to the tendon.
        return _one(
            round_chain(
                f.template(4.4, 17.0, -1.5),
                f.template(4.8, 10.5, 0.2),
                f.template(6.4, 4.8, 1.8),
                f.template(8.2, 1.6, 4.3),
                tendon,
                Radii(2.0, 2.2, 1.8, 1.3, 0.9),
                unit,
            )
        )
    if part == PIRIFORMIS:
        # From the front of the sacrum, out through the greater sciatic
        # foramen, to the top of the greater trochanter.
        var top = d.gt + f.template(-0.8, 0.9, 0)
        var behind = f.template(9.74, 1.1, -5.3)
        return _one(
            round_chain(
                sacral_front(p, 0.45) + f.template(2.3, 0, 0),
                p.notch + f.template(-1.7, -0.2, -1.6),
                behind,
                mix_point(behind, top, 0.6),
                top,
                Radii(1.0, 1.3, 1.2, 0.8, 0.45),
                unit,
            )
        )
    var turn = f.template(10.4, -2.0, -4.5)
    if part == OBTURATOR_INTERNUS:
        # A fan on the inner face of the obturator membrane. Its tendon
        # turns around the ischium through the lesser sciatic foramen.
        return _one(
            flat_chain(
                p.obturator + f.template(-1.0, 0.4, -0.4),
                mix_point(p.obturator, p.spine, 0.5) + f.template(-1.1, 0, 0),
                mix_point(p.spine, p.tuberosity, 0.45)
                + f.template(-0.2, 0, -1.2),
                turn,
                d.fossa,
                Radii(0.6, 0.7, 0.6, 0.55, 0.4),
                Radii(1.8, 1.6, 0.8, 0.65, 0.4),
                unit,
            )
        )
    if part == GEMELLI:
        var high = turn + f.template(0, 0.7, 0)
        var low = turn + f.template(0, -0.7, 0)
        var superior = p.spine + f.template(0.2, 0, -0.6)
        var inferior = p.tuberosity + f.template(0.2, 2.0, -1.2)
        var r = Radii(0.4, 0.5, 0.5, 0.45, 0.35)
        return _two(
            round_chain(
                superior,
                mix_point(superior, high, 0.5),
                high,
                mix_point(high, d.fossa, 0.5) + f.template(0, 0.5, 0),
                d.fossa,
                r,
                unit,
            ),
            round_chain(
                inferior,
                mix_point(inferior, low, 0.5),
                low,
                mix_point(low, d.fossa, 0.5) + f.template(0, -0.4, 0),
                d.fossa,
                r,
                unit,
            ),
        )
    if part == QUADRATUS_FEMORIS:
        # A flat quadrilateral from the tuberosity to the femur.
        var start = p.tuberosity + f.template(1.2, 0.4, -0.2)
        var end = d.gt + f.template(-2.6, -4.4, -0.8)
        return _one(
            flat_chain(
                start,
                mix_point(start, end, 0.25),
                mix_point(start, end, 0.50),
                mix_point(start, end, 0.75),
                end,
                Radii(0.6, 0.7, 0.75, 0.7, 0.6),
                Radii(1.2, 1.4, 1.5, 1.4, 1.2),
                unit,
            )
        )
    if part == OBTURATOR_EXTERNUS:
        # From the outer face of the membrane, under the femoral neck,
        # to the trochanteric fossa.
        var start = p.obturator + f.template(0.8, 0, 0.6)
        var under = f.template(11.5, -5.8, -2.8)
        return _one(
            round_chain(
                start,
                mix_point(start, under, 0.45) + f.template(0, -0.8, 0),
                under,
                mix_point(under, d.fossa, 0.5) + f.template(0, 0, -0.5),
                d.fossa,
                Radii(1.0, 1.1, 0.9, 0.7, 0.5),
                unit,
            )
        )
    if part == GLUTEUS_MINIMUS:
        # A fan on the outer ilium, deep to the gluteus medius, to the
        # front of the greater trochanter.
        var front = d.gt + f.template(0.2, 0.55, 1.8)
        var over = f.template(11.4, 3.66, -0.55)
        var r = Radii(0.8, 1.0, 1.0, 0.8, 0.45)
        return _three(
            _fan(f.template(12.7, 7.7, 1.0), over, front, r, unit),
            _fan(f.template(13.1, 8.5, -0.3), over, front, r, unit),
            _fan(f.template(11.95, 8.8, -2.45), over, front, r, unit),
        )
    if part == LEVATOR_ANI:
        # A funnel from the pubis and the tendinous arch down and back
        # to the midline behind the anorectal junction and the coccyx.
        var ml = Radii(0.9, 0.9, 0.9, 0.8, 0.6)
        var ap = Radii(0.35, 0.35, 0.35, 0.35, 0.3)
        return _three(
            flat_chain(
                f.template(1.5, -5.5, 3.1),
                f.template(2.0, -6.8, 0.8),
                f.template(1.6, -7.6, -1.4),
                f.template(0.7, -7.3, -3.2),
                f.template(0.3, -6.2, -5.0),
                ml,
                ap,
                unit,
            ),
            flat_chain(
                f.template(2.6, -4.5, 1.2),
                f.template(2.2, -6.3, -0.8),
                f.template(1.5, -6.9, -2.6),
                f.template(0.6, -6.4, -4.2),
                f.template(0.25, -5.4, -5.4),
                ml,
                ap,
                unit,
            ),
            flat_chain(
                f.template(3.7, -3.2, -0.8),
                f.template(2.6, -5.4, -2.2),
                f.template(1.4, -6.3, -3.6),
                f.template(0.5, -5.6, -5.2),
                p.coccyx_tip + f.template(0.2, 0, 0.3),
                ml,
                ap,
                unit,
            ),
        )
    if part == COCCYGEUS:
        return _one(
            flat_chain(
                p.spine + f.template(-0.6, 0, 0.4),
                f.template(3.9, -2.2, -5.8),
                f.template(3.1, -2.1, -6.3),
                f.template(2.3, -1.9, -7.0),
                f.template(1.4, -1.4, -7.6),
                Radii(0.9, 1.0, 1.1, 1.0, 0.9),
                Radii(0.4, 0.4, 0.4, 0.4, 0.4),
                unit,
            )
        )
    if part == RECTUS_ABDOMINIS:
        # A wide flat strap from the pubic crest up the front.
        return _one(
            flat_chain(
                f.template(1.9, -2.8, 6.0),
                f.template(2.6, 1.5, 6.9),
                f.template(3.3, 7.0, 7.2),
                f.template(3.7, 13.0, 7.6),
                f.template(3.8, 18.5, 7.8),
                Radii(0.9, 1.8, 2.8, 3.2, 3.3),
                Radii(0.5, 0.6, 0.6, 0.55, 0.5),
                unit,
            )
        )
    if part == EXTERNAL_OBLIQUE:
        # The flank from the crest up, and the front between the flank
        # and the rectus.
        return _two(
            flat_chain(
                f.template(13.4, 13.0, 1.0),
                f.template(13.2, 14.5, 1.4),
                f.template(12.8, 16.0, 1.8),
                f.template(12.5, 17.3, 2.2),
                f.template(12.4, 18.6, 2.6),
                Radii(0.9, 0.9, 0.9, 0.9, 0.9),
                Radii(4.2, 4.5, 4.7, 4.9, 5.0),
                unit,
            ),
            # Down to the inguinal ligament, as the internal oblique and
            # the transversus reach it.
            round_chain(
                f.template(8.8, 4.2, 5.8),
                f.template(10.2, 8.5, 6.6),
                f.template(10.6, 12.5, 7.1),
                f.template(10.5, 15.6, 7.4),
                f.template(10.2, 18.6, 7.6),
                Radii(1.1, 1.5, 1.6, 1.6, 1.6),
                unit,
            ),
        )
    if part == QUADRATUS_LUMBORUM:
        return _one(
            flat_chain(
                f.template(8.6, 13.3, -6.0),
                f.template(8.0, 14.8, -5.7),
                f.template(7.5, 16.2, -5.4),
                f.template(7.1, 17.5, -5.1),
                f.template(6.8, 18.6, -4.9),
                Radii(1.6, 1.8, 2.0, 2.1, 2.2),
                Radii(0.9, 1.0, 1.0, 1.1, 1.1),
                unit,
            )
        )
    # The erector spinae and multifidus: from the back of the sacrum up
    # beside the spinous processes, forward into the lumbar curve.
    return _one(
        flat_chain(
            f.template(2.0, 2.0, -9.4),
            f.template(2.6, 6.5, -10.0),
            f.template(3.0, 11.0, -9.3),
            f.template(3.5, 15.0, -8.4),
            f.template(3.8, 18.6, -7.8),
            Radii(1.2, 1.8, 2.4, 2.8, 3.0),
            Radii(0.9, 1.8, 2.2, 2.5, 2.6),
            unit,
        )
    )


def _fan(
    start: Vector3, over: Vector3, end: Vector3, radii: Radii, unit: Float32
) -> PelvisChain:
    """Return one ray of a fan from `start`, over `over`, to `end`."""
    return round_chain(
        start,
        mix_point(start, over, 0.5),
        over,
        mix_point(over, end, 0.5),
        end,
        radii,
        unit,
    )
