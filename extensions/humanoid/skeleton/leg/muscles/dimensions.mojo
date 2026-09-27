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
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    foot_dimensions,
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
from std.math import sqrt
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


# Room for six shifts of every named part.
comptime BELLY_SLOTS = 512
# The most a belly spreads around its bone, as a factor of its width.
comptime SPREAD_LIMIT = Float32(1.6)
# How far two bellies, or a belly and a bone, may press into each other
# when they pack, as a share of their reach. Muscle is soft.
comptime PACK_OVERLAP = Float32(0.15)


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
    # How each belly station moves and spreads when the bellies pack
    # around the bones. Four numbers a station, for stations one, two
    # and three, at `part.value * 12 + station * 4`: the move in x and
    # in z, then the x radius and the z radius each as a factor less
    # one. Zero until `muscle_dimensions` packs them. See `_pack`.
    var bellies: SIMD[DType.float32, BELLY_SLOTS]

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
        var chain = _raw_chain(dimensions, part)
        var at = part.value * 12
        var packed = dimensions.bellies
        chain.p1 = chain.p1 + Vector3(packed[at], 0, packed[at + 1])
        chain.r1 = chain.r1 * (1 + packed[at + 2])
        chain.a1 = chain.a1 * (1 + packed[at + 3])
        chain.p2 = chain.p2 + Vector3(packed[at + 4], 0, packed[at + 5])
        chain.r2 = chain.r2 * (1 + packed[at + 6])
        chain.a2 = chain.a2 * (1 + packed[at + 7])
        chain.p3 = chain.p3 + Vector3(packed[at + 8], 0, packed[at + 9])
        chain.r3 = chain.r3 * (1 + packed[at + 10])
        chain.a3 = chain.a3 * (1 + packed[at + 11])
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


def _raw_chain(dimensions: MuscleDimensions, part: MusclePart) -> MuscleChain:
    """Return one part's stations as authored, before the bellies pack."""
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
    return chain


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
    var k = 0.0050 * S
    if athleticism == TONED:
        k = 0.0042 * S
    var dims = MuscleDimensions(
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
        hip + Vector3(lat * 0.045 * S, 0.016 * S, 0.024 * S),
        hip + Vector3(lat * 0.030 * S, 0.006 * S, 0.030 * S),
        hip + Vector3(lat * 0.046 * S, 0.045 * S, -0.004 * S),
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
        # The calcaneal tuberosity, where the foot places it.
        plafond + foot_dimensions(femur.stature, femur.sex, femur.side).heel,
        tibia_origin_point,
        fibula_origin_point,
        patella_origin_point,
        SIMD[DType.float32, BELLY_SLOTS](0),
    )
    dims.bellies = _pack(dims)
    return dims


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


@fieldwise_init
struct _Station(ImplicitlyCopyable):
    """One belly station while the bellies pack."""

    var slot: Int
    var center: Vector3
    var ml: Float32
    var ap: Float32
    var reach: Float32


def _pack(d: MuscleDimensions) -> SIMD[DType.float32, BELLY_SLOTS]:
    """Return how far each belly station moves to pack around the bones.

    A dissected leg's muscles fill the space around its bones. Authored
    bellies do not: each sits where its own offset puts it, and gaps open
    between them. The nearest stations to the bone go first. Each moves
    straight toward its bone's axis until it would press into a bone or
    a station already placed, at a similar height, by more than
    `PACK_OVERLAP` of their reach. Attachments do not move.
    """
    var shifts = SIMD[DType.float32, BELLY_SLOTS](0)
    var stations = List[_Station]()
    var parts = named_muscle_parts()
    for index in range(len(parts)):
        var part = parts[index]
        if not _packs(part):
            continue
        var chain = _raw_chain(d, part)
        var at = part.value * 12
        stations.append(_Station(at, chain.p1, chain.r1, chain.a1, 0))
        stations.append(_Station(at + 4, chain.p2, chain.r2, chain.a2, 0))
        stations.append(_Station(at + 8, chain.p3, chain.r3, chain.a3, 0))
    for index in range(len(stations)):
        var axis = _nearest_bone(d, stations[index].center)
        stations[index].reach = _flat(stations[index].center - axis).length()
    _sort_by_reach(stations)
    # First every belly packs in as it is.
    var packed = List[_Station]()
    for index in range(len(stations)):
        var station = stations[index]
        station.center = _pull_in(d, station, packed)
        packed.append(station)
    # Then each muscle spreads as far as its tightest station allows, so
    # it widens evenly along its length instead of in ridges.
    var spread = SIMD[DType.float32, BELLY_SLOTS](SPREAD_LIMIT)
    for index in range(len(packed)):
        var others = List[_Station]()
        for other in range(len(packed)):
            if other != index:
                others.append(packed[other])
        var part = packed[index].slot // 12
        spread[part] = min(
            spread[part], _spread_factor(d, packed[index], others)
        )
    # Last, each muscle packs in again at its spread.
    var placed = List[_Station]()
    for index in range(len(stations)):
        var station = stations[index]
        var start = station.center
        var ml = station.ml
        var ap = station.ap
        station = _widened(
            station, spread[station.slot // 12], _widens_z(d, packed[index])
        )
        station.center = _pull_in(d, station, placed)
        var moved = station.center - start
        shifts[station.slot] = moved.x
        shifts[station.slot + 1] = moved.z
        shifts[station.slot + 2] = station.ml / ml - 1
        shifts[station.slot + 3] = station.ap / ap - 1
        placed.append(station)
    return shifts


def _pull_in(
    d: MuscleDimensions, station: _Station, placed: List[_Station]
) -> Vector3:
    """Return how far toward its bone's axis a station can move."""
    var axis = _nearest_bone(d, station.center)
    var inward = _flat(axis - station.center)
    var room = inward.length()
    var toward = inward * (1 / max(room, Float32(1.0e-6)))
    var low = Float32(0)
    var high = room
    for _ in range(10):
        var middle = Float32(0.5) * (low + high)
        if _fits(d, station, station.center + toward * middle, placed):
            low = middle
        else:
            high = middle
    return station.center + toward * low


def _spread_factor(
    d: MuscleDimensions, station: _Station, placed: List[_Station]
) -> Float32:
    """Return how far a station can widen around its bone and still fit.

    A belly that meets no neighbor spreads into a sheet: wider around
    the bone and thinner away from it, with the same cross-sectional
    area, up to `SPREAD_LIMIT`.
    """
    var widen_z = _widens_z(d, station)
    var low = Float32(1)
    var high = SPREAD_LIMIT
    for _ in range(8):
        var middle = Float32(0.5) * (low + high)
        if _fits(d, _widened(station, middle, widen_z), station.center, placed):
            low = middle
        else:
            high = middle
    return low


def _widens_z(d: MuscleDimensions, station: _Station) -> Bool:
    """Return whether a station's z radius runs around its bone.

    A belly beside the bone widens along z; one in front of or behind it
    widens along x.
    """
    var out = _flat(station.center - _nearest_bone(d, station.center))
    return abs(out.x) >= abs(out.z)


def _widened(station: _Station, factor: Float32, widen_z: Bool) -> _Station:
    """Return a station `factor` wider along one axis and thinner along
    the other."""
    var wider = station
    if widen_z:
        wider.ap = station.ap * factor
        wider.ml = station.ml / factor
    else:
        wider.ml = station.ml * factor
        wider.ap = station.ap / factor
    return wider


def _packs(part: MusclePart) -> Bool:
    """Return whether a part's belly packs: every muscle, no tendon."""
    return (
        part != ILIOTIBIAL_TRACT
        and part != ACHILLES_TENDON
        and part != PATELLAR_TENDON
    )


def _fits(
    d: MuscleDimensions,
    station: _Station,
    center: Vector3,
    placed: List[_Station],
) -> Bool:
    """Return whether a station centered at `center` presses too hard."""
    var S = d.stature.value
    var bones = _bones_at(d, center.y)
    for index in range(len(bones)):
        var bone = bones[index]
        var gap = _flat(center - bone)
        var reach = _reach(station.ml, station.ap, gap) + bone.y
        if gap.length() < (1 - PACK_OVERLAP) * reach:
            return False
    for index in range(len(placed)):
        var other = placed[index]
        var rise = abs(other.center.y - center.y)
        if rise < Float32(0.5) * (station.ap + other.ap) + Float32(0.01) * S:
            var gap = _flat(center - other.center)
            var reach = _reach(station.ml, station.ap, gap) + _reach(
                other.ml, other.ap, gap
            )
            if gap.length() < (1 - PACK_OVERLAP) * reach:
                return False
    return True


def _reach(ml: Float32, ap: Float32, toward: Vector3) -> Float32:
    """Return how far an x-z ellipse reaches along `toward`."""
    var length = max(toward.length(), Float32(1.0e-6))
    var ux = toward.x / length
    var uz = toward.z / length
    return sqrt(ml * ml * ux * ux + ap * ap * uz * uz)


def _flat(v: Vector3) -> Vector3:
    """Return `v` with its y set to zero."""
    return Vector3(v.x, 0, v.z)


def _nearest_bone(d: MuscleDimensions, point: Vector3) -> Vector3:
    """Return the shaft axis a belly at `point` packs toward.

    Above the knee, the femur. Below it, whichever of the tibia and the
    fibula is nearer, so a lateral belly settles on the fibula.
    """
    var bones = _bones_at(d, point.y)
    var best = bones[0]
    for index in range(1, len(bones)):
        var bone = bones[index]
        if _flat(point - bone).length() < _flat(point - best).length():
            best = bone
    return Vector3(best.x, point.y, best.z)


def _bones_at(d: MuscleDimensions, y: Float32) -> List[Vector3]:
    """Return the bone shafts at height `y`: x and z, and radius in y."""
    var S = d.stature.value
    var knee = _at(d.med_condyle, d.lat_condyle, 0.5)
    var bones = List[Vector3]()
    if y >= knee.y:
        var femur = _along(d.lt, d.femur_mid, knee, y)
        bones.append(Vector3(femur.x, 0.0080 * S, femur.z))
        return bones^
    var tibia = _along(
        _at(d.tib_med, d.tib_lat, 0.5), d.tibia_mid, d.plafond, y
    )
    var fibula = _along(d.fib_head, d.fibula_mid, d.lat_mal, y)
    bones.append(Vector3(tibia.x, 0.0085 * S, tibia.z))
    bones.append(Vector3(fibula.x, 0.0040 * S, fibula.z))
    return bones^


def _along(
    top: Vector3, middle: Vector3, bottom: Vector3, y: Float32
) -> Vector3:
    """Return the point of a three-point axis at height `y`, held at its
    ends."""
    if y >= middle.y:
        var span = top.y - middle.y
        var t = min(max((top.y - y) / span, Float32(0)), Float32(1))
        return _at(top, middle, t)
    var span = middle.y - bottom.y
    var t = min(max((middle.y - y) / span, Float32(0)), Float32(1))
    return _at(middle, bottom, t)


def _sort_by_reach(mut stations: List[_Station]):
    """Sort stations nearest the bone first; an insertion sort."""
    for index in range(1, len(stations)):
        var held = stations[index]
        var k = index - 1
        while k >= 0 and stations[k].reach > held.reach:
            stations[k + 1] = stations[k]
            k -= 1
        stations[k + 1] = held


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
    var r0 = 0.55 * r_end
    var r1 = 0.76 * r_belly
    var r3 = 0.68 * r_belly
    var r4 = 0.45 * r_end
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
    var r0 = 0.58 * width
    var r1 = 0.88 * width
    var r3 = 0.84 * width
    var r4 = 0.50 * width
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
    var rb = _r(S, scale, 0.0429)
    var origin = _at(d.iliac, d.ischial, 0.45) + Vector3(
        0, 0.002 * S, -0.010 * S
    )
    var insertion = _at(d.gt, d.femur_mid, 0.30) + Vector3(0, 0, -0.014 * S)
    var belly = d.hip + Vector3(0, -0.034 * S, -0.030 * S)
    var r0 = 0.48 * rb
    var r1 = 0.78 * rb
    var r2 = rb
    var r3 = 0.75 * rb
    var r4 = 0.42 * rb
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
        0.62 * r0,
        0.68 * r1,
        0.70 * r2,
        0.68 * r3,
        0.60 * r4,
    )


def _glute_med(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    """Return the fan from the outer ilium to the greater trochanter.

    It spreads from under the iliac crest, so it is broad and flat.
    """
    var rb = _r(S, scale, 0.036)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var origin = _at(d.iliac, d.gt, 0.10)
    return _fusiform(
        origin,
        d.gt,
        Vector3(lat * 0.010 * S, 0, 0.004 * S),
        0.80 * rb,
        rb,
        0.45,
    )


def _tfl(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0133)
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
    var rb = _r(S, scale, 0.0105)
    return _strap(d.asis, d.pes, Vector3(0, 0, 0.025 * S), rb, 0.55)


def _rectus(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0159)
    var insertion = d.patella + Vector3(0, 0.012 * S, 0.002 * S)
    return _fusiform(
        d.aiis, insertion, Vector3(0, 0, 0.026 * S), 0.55 * rb, rb, 0.78
    )


def _vastus_lat(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0237)
    var origin = _at(d.gt, d.femur_mid, 0.18)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var insertion = d.patella + Vector3(lat * 0.008 * S, 0.012 * S, 0.002 * S)
    return _fusiform(
        origin,
        insertion,
        Vector3(lat * 0.025 * S, 0, 0.010 * S),
        0.58 * rb,
        rb,
        0.78,
    )


def _vastus_med(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0225)
    var origin = _at(d.lt, d.med_condyle, 0.22)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var insertion = d.patella + Vector3(-lat * 0.007 * S, 0.010 * S, 0.002 * S)
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
    var rb = _r(S, scale, 0.0200)
    var origin = _at(d.aiis, d.femur_mid, 0.30)
    var insertion = d.patella + Vector3(0, 0.012 * S, 0.001 * S)
    return _fusiform(
        origin,
        insertion,
        Vector3(0, 0, 0.008 * S),
        0.58 * rb,
        rb,
        0.82,
    )


def _pectineus(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0142)
    return _fusiform(
        d.pubis, d.lt, Vector3(0, 0, 0.008 * S), 0.62 * rb, rb, 0.72
    )


def _adductor(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0198)
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
    var rb = _r(S, scale, 0.0236)
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
    var rb = _r(S, scale, 0.0096)
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
    var rb = _r(S, scale, 0.0162)
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
    var rb = _r(S, scale, 0.0133)
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
    var rb = _r(S, scale, 0.0159)
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
    var merge = _at(d.med_condyle, d.heel, 0.52) + Vector3(0, 0, -0.026 * S)
    var r0 = 0.30 * rb
    var r1 = 0.95 * rb
    var r2 = 0.38 * rb
    var r3 = 0.88 * rb
    var r4 = 0.28 * rb
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
    """Return the broad flat belly under the gastrocnemius.

    It rises from the soleal line and the fibular head and runs down to
    join the calcaneal tendon a hand's breadth above the heel.
    """
    var rb = _r(S, scale, 0.0322)
    var origin = _at(d.fib_head, d.tibia_mid, 0.22) + Vector3(0, 0, -0.016 * S)
    var insertion = Vector3(
        d.heel.x, d.plafond.y + 0.07 * S, d.heel.z - 0.004 * S
    )
    return _fusiform(
        origin, insertion, Vector3(0, 0, -0.014 * S), 0.58 * rb, rb, 0.55
    )


def _tib_ant(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0136)
    var origin = d.tib_lat + Vector3(0, -0.035 * S, 0.014 * S)
    var insertion = d.med_mal + Vector3(0, 0.010 * S, 0.016 * S)
    return _fusiform(
        origin, insertion, Vector3(0, 0, 0.012 * S), 0.52 * rb, rb, 0.70
    )


def _tib_post(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    """Return the deep posterior belly between the tibia and fibula."""
    var rb = _r(S, scale, 0.0106)
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
    var rb = _r(S, scale, 0.0107)
    var lat = Float32(1)
    if d.side == LEFT:
        lat = Float32(-1)
    var origin = d.fib_head + Vector3(0, -0.018 * S, 0.012 * S)
    var insertion = d.plafond + Vector3(lat * 0.012 * S, 0, 0.018 * S)
    return _fusiform(
        origin, insertion, Vector3(0, 0, 0.010 * S), 0.52 * rb, rb, 0.68
    )


def _per_long(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    var rb = _r(S, scale, 0.0111)
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
    var rb = _r(S, scale, 0.0116)
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
    """Return the calcaneal tendon from the triceps surae to the heel.

    Below the calf it runs nearly vertically, through the same two
    points the foot's copy of the tendon uses: behind the ankle at the
    height where it leaves the leg, and on the upper back of the
    calcaneal tuberosity.
    """
    var width = _r(S, Float32(1), 0.007)
    var depth = Float32(0.48) * width
    var origin = _at(d.med_condyle, d.heel, 0.52) + Vector3(0, 0, -0.026 * S)
    var low = Vector3(d.heel.x, d.plafond.y + 0.04 * S, d.heel.z - 0.007 * S)
    var insertion = d.heel + Vector3(0, 0.004 * S, -0.008 * S)
    return MuscleChain(
        origin,
        _at(origin, low, 0.5),
        low,
        _at(low, insertion, 0.5),
        insertion,
        0.60 * width,
        0.85 * width,
        width,
        0.95 * width,
        0.85 * width,
        0.60 * depth,
        0.85 * depth,
        depth,
        0.95 * depth,
        0.85 * depth,
    )


def _patellar(d: MuscleDimensions, S: Float32, scale: Float32) -> MuscleChain:
    """Return the flat tendon from the patella to the tibial tuberosity."""
    var width = _r(S, Float32(1), 0.0075)
    var origin = d.patella + Vector3(0, -0.012 * S, 0.002 * S)
    var insertion = d.tuberosity + Vector3(0, 0.002 * S, 0.003 * S)
    return _strap(origin, insertion, Vector3(0, 0, 0.002 * S), width, 0.45)
