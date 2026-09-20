# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named skeletal muscles of one leg, as implicit solids in the leg frame.

The labeled set follows a standard anterior, lateral and posterior
dissection of the left lower limb. Attachment points are authored from
the stature-scaled bone landmarks. Belly radii are authored ratios of
stature, then scaled by athleticism. They are template parameters. They
are not a cited CSA table.

The solids live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var dims = muscle_dimensions(person)
    var d = muscle_distance(dims, RECTUS_FEMORIS, Vector3(0, 0.2, 0.05))

`MuscleDimensions` is fieldwise-constructible. Editing a landmark does
not rebuild the others. Call `muscle_dimensions` to resolve a template.
Call `validate` at every public consumer of an edited copy.
"""

from extensions.humanoid.athleticism import TONED, Athleticism, radius_scale
from extensions.humanoid.sex import Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import (
    DistanceField,
    check_spec,
    empty_bounds,
    field_gradient,
    finite_point,
    sd_ellipse_segment,
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
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    femur_origin,
    fibula_origin,
    knee_dimensions_from_bones,
    patella_origin,
    tibia_origin,
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
from units.si import Length


@fieldwise_init
struct MusclePart(Equatable, ImplicitlyCopyable, Writable):
    """Which named muscle, tract or tendon a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary that
    reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named muscle part."""
        if self.value < 0:
            return False
        return self.value <= TIBIALIS_POSTERIOR.value


comptime GLUTEUS_MAXIMUS = MusclePart(0)
comptime GLUTEUS_MEDIUS = MusclePart(1)
comptime TENSOR_FASCIAE_LATAE = MusclePart(2)
comptime ILIOTIBIAL_TRACT = MusclePart(3)
comptime SARTORIUS = MusclePart(4)
comptime RECTUS_FEMORIS = MusclePart(5)
comptime VASTUS_LATERALIS = MusclePart(6)
comptime VASTUS_MEDIALIS = MusclePart(7)
comptime PECTINEUS = MusclePart(8)
comptime ADDUCTOR_LONGUS = MusclePart(9)
comptime GRACILIS = MusclePart(10)
comptime BICEPS_FEMORIS = MusclePart(11)
comptime SEMITENDINOSUS = MusclePart(12)
comptime SEMIMEMBRANOSUS = MusclePart(13)
comptime GASTROCNEMIUS = MusclePart(14)
comptime SOLEUS = MusclePart(15)
comptime TIBIALIS_ANTERIOR = MusclePart(16)
comptime EXTENSOR_DIGITORUM_LONGUS = MusclePart(17)
comptime PERONEUS_LONGUS = MusclePart(18)
comptime PERONEUS_BREVIS = MusclePart(19)
comptime ACHILLES_TENDON = MusclePart(20)
comptime PATELLAR_TENDON = MusclePart(21)
comptime VASTUS_INTERMEDIUS = MusclePart(22)
comptime ADDUCTOR_MAGNUS = MusclePart(23)
comptime TIBIALIS_POSTERIOR = MusclePart(24)


@fieldwise_init
struct MuscleChain(ImplicitlyCopyable):
    """Five tapered elliptical stations of one muscle solid."""

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
    var a0: Float32
    var a1: Float32
    var a2: Float32
    var a3: Float32
    var a4: Float32


@fieldwise_init
struct MuscleDimensions(ImplicitlyCopyable):
    """Landmarks and radius scale for the named muscles of one leg."""

    var stature: Length
    var sex: Sex
    var side: BodySide
    var athleticism: Athleticism
    var scale: Float32
    var k: Float32
    var epsilon: Float32
    var hip: Vector3
    var gt: Vector3
    var lt: Vector3
    var asis: Vector3
    var aiis: Vector3
    var iliac: Vector3
    var ischial: Vector3
    var pubis: Vector3
    var med_condyle: Vector3
    var lat_condyle: Vector3
    var femur_mid: Vector3
    var tib_med: Vector3
    var tib_lat: Vector3
    var tuberosity: Vector3
    var gerdy: Vector3
    var pes: Vector3
    var fib_head: Vector3
    var plafond: Vector3
    var med_mal: Vector3
    var lat_mal: Vector3
    var heel: Vector3
    var tibia_mid: Vector3
    var fibula_mid: Vector3
    var patella: Vector3

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If sex, side or athleticism is not valid, if stature
                is outside the software range, if scale or blend radius
                is not positive, or if a landmark is not finite.
        """
        check_spec(self.stature, self.sex, self.side, "muscle")
        if not self.athleticism.is_valid():
            raise Error("A muscle needs a toned or untoned athleticism")
        if self.scale <= 0:
            raise Error("A muscle radius scale must be positive")
        if self.k <= 0:
            raise Error("A muscle blend radius must be positive")
        if self.epsilon <= 0:
            raise Error("A muscle gradient step must be positive")
        finite_point(self.hip, "hip", "muscle")
        finite_point(self.gt, "greater trochanter", "muscle")
        finite_point(self.lt, "lesser trochanter", "muscle")
        finite_point(self.asis, "ASIS", "muscle")
        finite_point(self.aiis, "AIIS", "muscle")
        finite_point(self.iliac, "iliac crest", "muscle")
        finite_point(self.ischial, "ischial tuberosity", "muscle")
        finite_point(self.pubis, "pubis", "muscle")
        finite_point(self.med_condyle, "medial condyle", "muscle")
        finite_point(self.lat_condyle, "lateral condyle", "muscle")
        finite_point(self.femur_mid, "femur midshaft", "muscle")
        finite_point(self.tib_med, "tibial medial condyle", "muscle")
        finite_point(self.tib_lat, "tibial lateral condyle", "muscle")
        finite_point(self.tuberosity, "tibial tuberosity", "muscle")
        finite_point(self.gerdy, "Gerdy tubercle", "muscle")
        finite_point(self.pes, "pes anserinus", "muscle")
        finite_point(self.fib_head, "fibular head", "muscle")
        finite_point(self.plafond, "plafond", "muscle")
        finite_point(self.med_mal, "medial malleolus", "muscle")
        finite_point(self.lat_mal, "lateral malleolus", "muscle")
        finite_point(self.heel, "heel", "muscle")
        finite_point(self.tibia_mid, "tibia midshaft", "muscle")
        finite_point(self.fibula_mid, "fibula midshaft", "muscle")
        finite_point(self.patella, "patella", "muscle")


struct MuscleField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `MusclePart`."""

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
    var a0: Float32
    var a1: Float32
    var a2: Float32
    var a3: Float32
    var a4: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: MuscleDimensions, part: MusclePart
    ) raises:
        """Build one muscle from dimensions that `validate` accepts.

        Args:
            dimensions: Landmarks and radius scale.
            part: A named muscle part.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A muscle part must be a named muscle, tract or tendon")
        var S = dimensions.stature.value
        var scale = dimensions.scale
        var chain: MuscleChain
        if part == GLUTEUS_MAXIMUS:
            chain = _glute_max(dimensions, S, scale)
        elif part == GLUTEUS_MEDIUS:
            chain = _glute_med(dimensions, S, scale)
        elif part == TENSOR_FASCIAE_LATAE:
            chain = _tfl(dimensions, S, scale)
        elif part == ILIOTIBIAL_TRACT:
            chain = _it_band(dimensions, S, scale)
        elif part == SARTORIUS:
            chain = _sartorius(dimensions, S, scale)
        elif part == RECTUS_FEMORIS:
            chain = _rectus(dimensions, S, scale)
        elif part == VASTUS_LATERALIS:
            chain = _vastus_lat(dimensions, S, scale)
        elif part == VASTUS_MEDIALIS:
            chain = _vastus_med(dimensions, S, scale)
        elif part == VASTUS_INTERMEDIUS:
            chain = _vastus_intermedius(dimensions, S, scale)
        elif part == PECTINEUS:
            chain = _pectineus(dimensions, S, scale)
        elif part == ADDUCTOR_LONGUS:
            chain = _adductor(dimensions, S, scale)
        elif part == GRACILIS:
            chain = _gracilis(dimensions, S, scale)
        elif part == BICEPS_FEMORIS:
            chain = _biceps(dimensions, S, scale)
        elif part == SEMITENDINOSUS:
            chain = _semitend(dimensions, S, scale)
        elif part == SEMIMEMBRANOSUS:
            chain = _semimemb(dimensions, S, scale)
        elif part == GASTROCNEMIUS:
            chain = _gastroc(dimensions, S, scale)
        elif part == SOLEUS:
            chain = _soleus(dimensions, S, scale)
        elif part == TIBIALIS_ANTERIOR:
            chain = _tib_ant(dimensions, S, scale)
        elif part == TIBIALIS_POSTERIOR:
            chain = _tib_post(dimensions, S, scale)
        elif part == EXTENSOR_DIGITORUM_LONGUS:
            chain = _edl(dimensions, S, scale)
        elif part == PERONEUS_LONGUS:
            chain = _per_long(dimensions, S, scale)
        elif part == PERONEUS_BREVIS:
            chain = _per_brev(dimensions, S, scale)
        elif part == ACHILLES_TENDON:
            chain = _achilles(dimensions, S, scale)
        elif part == PATELLAR_TENDON:
            chain = _patellar(dimensions, S, scale)
        else:
            chain = _adductor_magnus(dimensions, S, scale)
        self.p0 = chain.p0
        self.p1 = chain.p1
        self.p2 = chain.p2
        self.p3 = chain.p3
        self.p4 = chain.p4
        self.r0 = chain.r0
        self.r1 = chain.r1
        self.r2 = chain.r2
        self.r3 = chain.r3
        self.r4 = chain.r4
        self.a0 = chain.a0
        self.a1 = chain.a1
        self.a2 = chain.a2
        self.a3 = chain.a3
        self.a4 = chain.a4
        self.k = dimensions.k
        self.epsilon = dimensions.epsilon
        var box = empty_bounds()
        box.include_sphere(self.p0, self.r0)
        box.include_sphere(self.p1, self.r1)
        box.include_sphere(self.p2, self.r2)
        box.include_sphere(self.p3, self.r3)
        box.include_sphere(self.p4, self.r4)
        var padded = box.padded(0.006 + self.r2)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the muscle, in meters.

        Negative is inside. Zero is the surface.
        """
        var ml = Vector3(1, 0, 0)
        var d = sd_ellipse_segment(
            point, self.p0, self.p1, self.r0, self.a0, self.r1, self.a1, ml
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point, self.p1, self.p2, self.r1, self.a1, self.r2, self.a2, ml
            ),
            self.k,
        )
        d = smin(
            d,
            sd_ellipse_segment(
                point, self.p2, self.p3, self.r2, self.a2, self.r3, self.a3, ml
            ),
            self.k,
        )
        return smin(
            d,
            sd_ellipse_segment(
                point, self.p3, self.p4, self.r3, self.a3, self.r4, self.a4, ml
            ),
            self.k,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def muscle_dimensions(
    spec: HumanoidSpec, side: BodySide = RIGHT
) raises -> MuscleDimensions:
    """Return muscle landmarks sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right leg is the default.

    Returns:
        Landmarks in the leg frame and the athleticism radius scale.

    Raises:
        Error: If `spec` or `side` is refused.
    """
    var femur = femur_dimensions(spec.stature, spec.sex, side)
    var tibia = tibia_dimensions(spec.stature, spec.sex, side)
    var fibula = fibula_dimensions(spec.stature, spec.sex, side)
    var patella = patella_dimensions(spec.stature, spec.sex, side)
    var knee = knee_dimensions_from_bones(femur, tibia, fibula, patella)
    var f_origin = femur_origin(femur, knee.femoral_thickness)
    var t_origin = tibia_origin(tibia, knee.tibial_thickness)
    var fi_origin = fibula_origin(tibia, t_origin, fibula)
    var p_origin = patella_origin(
        femur, f_origin, patella, knee.patellar_thickness
    )
    return muscle_dimensions_from_bones(
        spec.athleticism,
        femur,
        tibia,
        fibula,
        patella,
        f_origin,
        t_origin,
        fi_origin,
        p_origin,
    )


def muscle_dimensions_from_bones(
    athleticism: Athleticism,
    femur: FemurDimensions,
    tibia: TibiaDimensions,
    fibula: FibulaDimensions,
    patella: PatellaDimensions,
    femur_origin_point: Vector3,
    tibia_origin_point: Vector3,
    fibula_origin_point: Vector3,
    patella_origin_point: Vector3,
) raises -> MuscleDimensions:
    """Return muscle landmarks from already-sized bones.

    Args:
        athleticism: `UNTONED` or `TONED`.
        femur: A femur already sized from stature and sex.
        tibia: A tibia from the same spec.
        fibula: A fibula from the same spec.
        patella: A patella from the same spec.
        femur_origin_point: Femur origin in the leg frame.
        tibia_origin_point: Tibia origin in the leg frame.
        fibula_origin_point: Fibula origin in the leg frame.
        patella_origin_point: Patella origin in the leg frame.

    Returns:
        Landmarks in the leg frame and the athleticism radius scale.

    Raises:
        Error: If a bone fails `validate`, or `athleticism` is not named.
    """
    femur.validate()
    tibia.validate()
    fibula.validate()
    patella.validate()
    var scale = radius_scale(athleticism)
    var S = femur.stature.value
    var lat = Float32(1)
    if femur.side == LEFT:
        lat = Float32(-1)
    var hip = femur_origin_point + femur.head_center
    var gt = femur_origin_point + femur.greater_trochanter
    var lt = femur_origin_point + femur.lesser_trochanter
    var med_c = femur_origin_point + femur.medial_condyle
    var lat_c = femur_origin_point + femur.lateral_condyle
    var tib_med = tibia_origin_point + tibia.medial_condyle
    var tib_lat = tibia_origin_point + tibia.lateral_condyle
    var tuber = tibia_origin_point + tibia.tuberosity
    var plafond = tibia_origin_point + tibia.plafond
    var med_mal = tibia_origin_point + tibia.medial_malleolus
    var fib_head = fibula_origin_point + fibula.head_center
    var lat_mal = fibula_origin_point + fibula.lateral_malleolus
    var k = 0.016 * S
    if athleticism == TONED:
        k = 0.013 * S
    return MuscleDimensions(
        femur.stature,
        femur.sex,
        femur.side,
        athleticism,
        scale,
        k,
        0.0018 * S,
        hip,
        gt,
        lt,
        hip + Vector3(lat * 0.052 * S, 0.032 * S, 0.028 * S),
        hip + Vector3(lat * 0.032 * S, 0.012 * S, 0.034 * S),
        hip + Vector3(lat * 0.048 * S, 0.058 * S, -0.004 * S),
        hip + Vector3(-lat * 0.022 * S, -0.052 * S, -0.048 * S),
        hip + Vector3(-lat * 0.038 * S, -0.048 * S, 0.018 * S),
        med_c,
        lat_c,
        femur_origin_point,
        tib_med,
        tib_lat,
        tuber,
        tib_lat + Vector3(lat * 0.010 * S, -0.022 * S, 0.026 * S),
        tib_med + Vector3(-lat * 0.010 * S, -0.032 * S, 0.024 * S),
        fib_head,
        plafond,
        med_mal,
        lat_mal,
        plafond + Vector3(0, -0.042 * S, -0.052 * S),
        tibia_origin_point,
        fibula_origin_point,
        patella_origin_point,
    )


def muscle_distance(
    dimensions: MuscleDimensions, part: MusclePart, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Muscles already sized from stature, sex and athleticism.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return MuscleField(dimensions, part).distance(point)


def muscle_part_label(part: MusclePart) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A muscle part, named or not.

    Returns:
        A short American English label.
    """
    if part == GLUTEUS_MAXIMUS:
        return "gluteus maximus"
    if part == GLUTEUS_MEDIUS:
        return "gluteus medius"
    if part == TENSOR_FASCIAE_LATAE:
        return "tensor fasciae latae"
    if part == ILIOTIBIAL_TRACT:
        return "iliotibial tract"
    if part == SARTORIUS:
        return "sartorius"
    if part == RECTUS_FEMORIS:
        return "rectus femoris"
    if part == VASTUS_LATERALIS:
        return "vastus lateralis"
    if part == VASTUS_MEDIALIS:
        return "vastus medialis"
    if part == VASTUS_INTERMEDIUS:
        return "vastus intermedius"
    if part == PECTINEUS:
        return "pectineus"
    if part == ADDUCTOR_LONGUS:
        return "adductor longus"
    if part == ADDUCTOR_MAGNUS:
        return "adductor magnus"
    if part == GRACILIS:
        return "gracilis"
    if part == BICEPS_FEMORIS:
        return "biceps femoris"
    if part == SEMITENDINOSUS:
        return "semitendinosus"
    if part == SEMIMEMBRANOSUS:
        return "semimembranosus"
    if part == GASTROCNEMIUS:
        return "gastrocnemius"
    if part == SOLEUS:
        return "soleus"
    if part == TIBIALIS_ANTERIOR:
        return "tibialis anterior"
    if part == TIBIALIS_POSTERIOR:
        return "tibialis posterior"
    if part == EXTENSOR_DIGITORUM_LONGUS:
        return "extensor digitorum longus"
    if part == PERONEUS_LONGUS:
        return "peroneus longus"
    if part == PERONEUS_BREVIS:
        return "peroneus brevis"
    if part == ACHILLES_TENDON:
        return "Achilles tendon"
    if part == PATELLAR_TENDON:
        return "patellar tendon"
    return "muscle"


def is_tendon(part: MusclePart) raises -> Bool:
    """Return True if `part` is fascia or tendon rather than a belly.

    Args:
        part: A named muscle part.

    Returns:
        True for the iliotibial tract, Achilles tendon or patellar tendon.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A muscle part must be a named muscle, tract or tendon")
    if part == ILIOTIBIAL_TRACT:
        return True
    if part == ACHILLES_TENDON:
        return True
    return part == PATELLAR_TENDON


def named_muscle_parts() -> List[MusclePart]:
    """Return every named muscle part in a stable order.

    Returns:
        The labeled set, three deep muscles and the patellar tendon.
    """
    var parts = List[MusclePart]()
    parts.append(GLUTEUS_MAXIMUS)
    parts.append(GLUTEUS_MEDIUS)
    parts.append(TENSOR_FASCIAE_LATAE)
    parts.append(ILIOTIBIAL_TRACT)
    parts.append(SARTORIUS)
    parts.append(RECTUS_FEMORIS)
    parts.append(VASTUS_LATERALIS)
    parts.append(VASTUS_MEDIALIS)
    parts.append(VASTUS_INTERMEDIUS)
    parts.append(PECTINEUS)
    parts.append(ADDUCTOR_LONGUS)
    parts.append(ADDUCTOR_MAGNUS)
    parts.append(GRACILIS)
    parts.append(BICEPS_FEMORIS)
    parts.append(SEMITENDINOSUS)
    parts.append(SEMIMEMBRANOSUS)
    parts.append(GASTROCNEMIUS)
    parts.append(SOLEUS)
    parts.append(TIBIALIS_ANTERIOR)
    parts.append(TIBIALIS_POSTERIOR)
    parts.append(EXTENSOR_DIGITORUM_LONGUS)
    parts.append(PERONEUS_LONGUS)
    parts.append(PERONEUS_BREVIS)
    parts.append(ACHILLES_TENDON)
    parts.append(PATELLAR_TENDON)
    return parts^


def _at(a: Vector3, b: Vector3, t: Float32) -> Vector3:
    """Return the point `t` of the way from `a` to `b`."""
    return Vector3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
    )


def _r(stature: Float32, scale: Float32, ratio: Float32) -> Float32:
    """Return a belly radius from a stature ratio and athleticism scale."""
    return ratio * stature * scale


def _fusiform(
    origin: Vector3,
    insertion: Vector3,
    belly_off: Vector3,
    r_end: Float32,
    r_belly: Float32,
    depth: Float32 = 0.78,
) -> MuscleChain:
    """Return a tapered elliptical belly from origin to insertion."""
    var belly = _at(origin, insertion, 0.46) + belly_off
    var r0 = 0.72 * r_end
    var r1 = 0.90 * r_belly
    var r3 = 0.82 * r_belly
    var r4 = 0.42 * r_end
    return MuscleChain(
        origin,
        _at(origin, belly, 0.50),
        belly,
        _at(belly, insertion, 0.50),
        insertion,
        r0,
        r1,
        r_belly,
        r3,
        r4,
        r0 * depth,
        r1 * depth,
        r_belly * depth,
        r3 * depth,
        r4 * depth,
    )


def _strap(
    origin: Vector3,
    insertion: Vector3,
    belly_off: Vector3,
    width: Float32,
    depth: Float32,
) -> MuscleChain:
    """Return a long flat strap with tapered attachment ends."""
    var belly = _at(origin, insertion, 0.48) + belly_off
    var r0 = 0.65 * width
    var r1 = 0.94 * width
    var r3 = 0.88 * width
    var r4 = 0.55 * width
    return MuscleChain(
        origin,
        _at(origin, belly, 0.52),
        belly,
        _at(belly, insertion, 0.54),
        insertion,
        r0,
        r1,
        width,
        r3,
        r4,
        r0 * depth,
        r1 * depth,
        width * depth,
        r3 * depth,
        r4 * depth,
    )


def _glute_max(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.028)
    var origin = _at(d.iliac, d.ischial, 0.45) + Vector3(
        0, 0.002 * S, -0.010 * S
    )
    var insertion = _at(d.gt, d.femur_mid, 0.30) + Vector3(0, 0, -0.014 * S)
    var belly = d.hip + Vector3(0, -0.034 * S, -0.030 * S)
    var r0 = 0.55 * rb
    var r1 = 0.88 * rb
    var r2 = rb
    var r3 = 0.90 * rb
    var r4 = 0.48 * rb
    return MuscleChain(
        origin,
        _at(origin, belly, 0.50),
        belly,
        _at(belly, insertion, 0.50),
        insertion,
        r0,
        r1,
        r2,
        r3,
        r4,
        0.64 * r0,
        0.70 * r1,
        0.72 * r2,
        0.70 * r3,
        0.62 * r4,
    )


def _glute_med(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.016)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var origin = _at(d.iliac, d.gt, 0.38)
    return _fusiform(
        origin,
        d.gt,
        Vector3(lat * 0.008 * S, 0, 0.004 * S),
        0.80 * rb,
        rb,
        0.68,
    )


def _tfl(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.012)
    var insertion = _at(d.gt, d.gerdy, 0.18)
    return _fusiform(
        d.asis, insertion, Vector3(0, 0, 0.010 * S), 0.58 * rb, rb, 0.70
    )


def _it_band(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, Float32(1), 0.0065)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    return _strap(
        d.gt,
        d.gerdy,
        Vector3(lat * 0.006 * S, 0, 0.003 * S),
        rb,
        0.28,
    )


def _sartorius(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0085)
    return _strap(d.asis, d.pes, Vector3(0, 0, 0.025 * S), rb, 0.55)


def _rectus(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.021)
    return _fusiform(
        d.aiis, d.patella, Vector3(0, 0, 0.026 * S), 0.55 * rb, rb, 0.78
    )


def _vastus_lat(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.028)
    var origin = _at(d.gt, d.femur_mid, 0.18)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var insertion = d.patella + Vector3(lat * 0.006 * S, 0.004 * S, 0)
    return _fusiform(
        origin,
        insertion,
        Vector3(lat * 0.025 * S, 0, 0.010 * S),
        0.58 * rb,
        rb,
        0.78,
    )


def _vastus_med(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.022)
    var origin = _at(d.lt, d.med_condyle, 0.22)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var insertion = d.patella + Vector3(-lat * 0.005 * S, 0.002 * S, 0)
    return _fusiform(
        origin,
        insertion,
        Vector3(-lat * 0.023 * S, -0.012 * S, 0.012 * S),
        0.55 * rb,
        rb,
        0.78,
    )


def _vastus_intermedius(
    d: MuscleDimensions, S: Float32, scale: Float32
) -> MuscleChain:
    """Return the deep quadriceps belly that packs around the femur."""
    var rb = _r(S, scale, 0.027)
    var origin = _at(d.aiis, d.femur_mid, 0.30)
    return _fusiform(
        origin,
        d.patella,
        Vector3(0, 0, 0.008 * S),
        0.58 * rb,
        rb,
        0.82,
    )


def _pectineus(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.012)
    return _fusiform(
        d.pubis, d.lt, Vector3(0, 0, 0.008 * S), 0.62 * rb, rb, 0.72
    )


def _adductor(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.021)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var insertion = d.femur_mid + Vector3(-lat * 0.016 * S, 0, -0.008 * S)
    return _fusiform(
        d.pubis,
        insertion,
        Vector3(-lat * 0.014 * S, 0, 0.003 * S),
        0.58 * rb,
        rb,
        0.75,
    )


def _adductor_magnus(
    d: MuscleDimensions, S: Float32, scale: Float32
) -> MuscleChain:
    """Return the broad deep adductor that closes the medial thigh."""
    var rb = _r(S, scale, 0.029)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var origin = _at(d.pubis, d.ischial, 0.56)
    var insertion = d.med_condyle + Vector3(-lat * 0.006 * S, 0.018 * S, 0)
    return _fusiform(
        origin,
        insertion,
        Vector3(-lat * 0.011 * S, 0, -0.010 * S),
        0.62 * rb,
        rb,
        0.88,
    )


def _gracilis(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.008)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    return _strap(
        d.pubis,
        d.pes,
        Vector3(-lat * 0.018 * S, 0, 0.006 * S),
        rb,
        0.55,
    )


def _biceps(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.019)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    return _fusiform(
        d.ischial,
        d.fib_head,
        Vector3(lat * 0.016 * S, 0, -0.024 * S),
        0.55 * rb,
        rb,
        0.78,
    )


def _semitend(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.015)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    return _fusiform(
        d.ischial,
        d.pes,
        Vector3(-lat * 0.010 * S, 0, -0.023 * S),
        0.52 * rb,
        rb,
        0.76,
    )


def _semimemb(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.017)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var insertion = d.tib_med + Vector3(0, 0, -0.016 * S)
    return _fusiform(
        d.ischial,
        insertion,
        Vector3(-lat * 0.008 * S, 0, -0.022 * S),
        0.55 * rb,
        rb,
        0.78,
    )


def _gastroc(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.021)
    var med = d.med_condyle + Vector3(0, -0.008 * S, -0.016 * S)
    var latc = d.lat_condyle + Vector3(0, -0.008 * S, -0.016 * S)
    var merge = _at(d.med_condyle, d.heel, 0.50) + Vector3(0, 0, -0.026 * S)
    var r0 = 0.36 * rb
    var r1 = rb
    var r2 = 0.42 * rb
    var r3 = 0.94 * rb
    var r4 = 0.34 * rb
    return MuscleChain(
        med,
        _at(med, merge, 0.44),
        merge,
        _at(latc, merge, 0.44),
        latc,
        r0,
        r1,
        r2,
        r3,
        r4,
        0.84 * r0,
        0.88 * r1,
        0.78 * r2,
        0.88 * r3,
        0.84 * r4,
    )


def _soleus(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.016)
    var origin = _at(d.fib_head, d.tibia_mid, 0.40) + Vector3(0, 0, -0.016 * S)
    var insertion = _at(d.med_condyle, d.heel, 0.56) + Vector3(0, 0, -0.028 * S)
    return _fusiform(
        origin, insertion, Vector3(0, 0, -0.020 * S), 0.58 * rb, rb, 0.84
    )


def _tib_ant(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.011)
    var origin = d.tib_lat + Vector3(0, -0.035 * S, 0.014 * S)
    var insertion = d.med_mal + Vector3(0, 0.010 * S, 0.016 * S)
    return _fusiform(
        origin, insertion, Vector3(0, 0, 0.012 * S), 0.52 * rb, rb, 0.70
    )


def _tib_post(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    """Return the deep posterior belly between the tibia and fibula."""
    var rb = _r(S, scale, 0.012)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var origin = _at(d.tib_med, d.fib_head, 0.48) + Vector3(
        -lat * 0.004 * S, -0.030 * S, -0.008 * S
    )
    var insertion = d.med_mal + Vector3(0, 0.018 * S, -0.004 * S)
    return _fusiform(
        origin,
        insertion,
        Vector3(-lat * 0.004 * S, 0, -0.012 * S),
        0.55 * rb,
        rb,
        0.80,
    )


def _edl(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.009)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var origin = d.fib_head + Vector3(0, -0.018 * S, 0.012 * S)
    var insertion = d.plafond + Vector3(lat * 0.012 * S, 0, 0.018 * S)
    return _fusiform(
        origin, insertion, Vector3(0, 0, 0.010 * S), 0.52 * rb, rb, 0.68
    )


def _per_long(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.010)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    return _fusiform(
        d.fib_head,
        d.lat_mal,
        Vector3(lat * 0.013 * S, 0, 0.004 * S),
        0.55 * rb,
        rb,
        0.72,
    )


def _per_brev(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.008)
    var origin = _at(d.fibula_mid, d.lat_mal, 0.22)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    return _fusiform(
        origin,
        d.lat_mal,
        Vector3(lat * 0.010 * S, 0, 0.002 * S),
        0.58 * rb,
        rb,
        0.70,
    )


def _achilles(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, Float32(1), 0.007)
    var origin = _at(d.med_condyle, d.heel, 0.56) + Vector3(0, 0, -0.028 * S)
    return _strap(origin, d.heel, Vector3(0, 0, -0.006 * S), rb, 0.48)


def _patellar(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    """Return the flat tendon from the patella to the tibial tuberosity."""
    var width = _r(S, Float32(1), 0.0065)
    var origin = d.patella + Vector3(0, -0.006 * S, 0)
    var insertion = d.tuberosity + Vector3(0, 0.003 * S, 0.004 * S)
    return _strap(origin, insertion, Vector3(0, 0, 0.002 * S), width, 0.38)
