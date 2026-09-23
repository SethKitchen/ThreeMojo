# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named muscles and tendons of one foot, as implicit tubes.

Extrinsic tendons are the parts of those muscles that enter the foot.
Intrinsic muscles are the plantar layers and the dorsal brevis pair.
Belly radii are authored ratios of stature, then scaled by athleticism.
Tendon radii are not scaled. They are template parameters. They are
not a cited cross-section table. `FIBULARIS_*` is the canonical name.
`PERONEUS_*` is an alias.

The solids live in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_muscle_dimensions(person)
    var d = foot_muscle_distance(dims, ABDUCTOR_HALLUCIS, dims.foot.heel)
"""

from extensions.humanoid.athleticism import Athleticism, radius_scale
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    field_gradient,
    mix_point,
)
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    foot_dimensions,
    medial_axis,
)
from extensions.humanoid.skeleton.foot.chain import (
    TubeSet,
    four_tubes,
    one_tube,
    three_tubes,
    tube_set_bounds,
    tube_set_distance,
    two_tubes,
)
from math.vector3 import Vector3


@fieldwise_init
struct FootMuscle(Equatable, ImplicitlyCopyable, Writable):
    """Which named foot muscle or tendon a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named foot muscle or tendon."""
        if self.value < 0:
            return False
        return self.value <= EXTENSOR_HALLUCIS_BREVIS.value


comptime CALCANEAL_TENDON = FootMuscle(0)
comptime TIBIALIS_ANTERIOR_TENDON = FootMuscle(1)
comptime EXTENSOR_HALLUCIS_LONGUS_TENDON = FootMuscle(2)
comptime EXTENSOR_DIGITORUM_LONGUS_TENDON = FootMuscle(3)
comptime FIBULARIS_LONGUS_TENDON = FootMuscle(4)
comptime FIBULARIS_BREVIS_TENDON = FootMuscle(5)
comptime TIBIALIS_POSTERIOR_TENDON = FootMuscle(6)
comptime FLEXOR_HALLUCIS_LONGUS_TENDON = FootMuscle(7)
comptime FLEXOR_DIGITORUM_LONGUS_TENDON = FootMuscle(8)
comptime ABDUCTOR_HALLUCIS = FootMuscle(9)
comptime FLEXOR_DIGITORUM_BREVIS = FootMuscle(10)
comptime ABDUCTOR_DIGITI_MINIMI = FootMuscle(11)
comptime QUADRATUS_PLANTAE = FootMuscle(12)
comptime LUMBRICALS = FootMuscle(13)
comptime FLEXOR_HALLUCIS_BREVIS = FootMuscle(14)
comptime ADDUCTOR_HALLUCIS = FootMuscle(15)
comptime FLEXOR_DIGITI_MINIMI_BREVIS = FootMuscle(16)
comptime DORSAL_INTEROSSEI = FootMuscle(17)
comptime PLANTAR_INTEROSSEI = FootMuscle(18)
comptime EXTENSOR_DIGITORUM_BREVIS = FootMuscle(19)
comptime EXTENSOR_HALLUCIS_BREVIS = FootMuscle(20)
# Compatibility names for the fibular tendons.
comptime PERONEUS_LONGUS_TENDON = FIBULARIS_LONGUS_TENDON
comptime PERONEUS_BREVIS_TENDON = FIBULARIS_BREVIS_TENDON


@fieldwise_init
struct FootMuscleDimensions(ImplicitlyCopyable):
    """Foot landmarks plus the athleticism scale for muscle bellies."""

    var foot: FootDimensions
    var athleticism: Athleticism
    var scale: Float32
    var k: Float32
    var epsilon: Float32

    def validate(self) raises:
        """Refuse dimensions that a field, mesh or mass cannot consume.

        Raises:
            Error: If the foot fails `validate`, if athleticism is not
                named, or if scale, blend radius or gradient step is
                not positive.
        """
        self.foot.validate()
        if not self.athleticism.is_valid():
            raise Error("A foot muscle needs a toned or untoned athleticism")
        if self.scale <= 0:
            raise Error("A foot muscle radius scale must be positive")
        if self.k <= 0:
            raise Error("A foot muscle blend radius must be positive")
        if self.epsilon <= 0:
            raise Error("A foot muscle gradient step must be positive")


struct FootMuscleField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one named foot muscle or tendon."""

    var tubes: TubeSet
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: FootMuscleDimensions, part: FootMuscle
    ) raises:
        """Build one muscle from dimensions that `validate` accepts.

        Args:
            dimensions: Landmarks and the belly scale.
            part: A named muscle or tendon.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A foot muscle must be a named muscle or tendon")
        self.tubes = _tubes(dimensions, part)
        self.k = dimensions.k
        self.epsilon = dimensions.epsilon
        var box = tube_set_bounds(self.tubes, 0.004)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the solid, in meters.

        Negative is inside. Zero is the surface.
        """
        return tube_set_distance(self.tubes, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def foot_muscle_dimensions(
    spec: HumanoidSpec, side: BodySide = RIGHT
) raises -> FootMuscleDimensions:
    """Return foot landmarks and the belly scale for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Landmarks in the foot frame and the authored radius scale.

    Raises:
        Error: If `spec` or `side` is refused, or athleticism is not
            named.
    """
    if not spec.athleticism.is_valid():
        raise Error("A foot muscle needs a toned or untoned athleticism")
    var foot = foot_dimensions(spec.stature, spec.sex, side)
    var scale = radius_scale(spec.athleticism)
    var S = spec.stature.value
    return FootMuscleDimensions(
        foot, spec.athleticism, scale, 0.0016 * S, 0.0008 * S
    )


def foot_muscle_distance(
    dimensions: FootMuscleDimensions, part: FootMuscle, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `foot_muscle_dimensions`.
        part: Which solid to sample.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return FootMuscleField(dimensions, part).distance(point)


def is_tendon(part: FootMuscle) raises -> Bool:
    """Return True if `part` is an extrinsic tendon.

    Args:
        part: A named muscle or tendon.

    Returns:
        True for the nine tendons that enter the foot.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A foot muscle must be a named muscle or tendon")
    return part.value <= FLEXOR_DIGITORUM_LONGUS_TENDON.value


def foot_muscle_part_label(part: FootMuscle) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A muscle or tendon, named or not.

    Returns:
        A short American English label, or `"foot muscle"` when `part`
        is not named.
    """
    if part == CALCANEAL_TENDON:
        return "calcaneal tendon"
    if part == TIBIALIS_ANTERIOR_TENDON:
        return "tibialis anterior tendon"
    if part == EXTENSOR_HALLUCIS_LONGUS_TENDON:
        return "extensor hallucis longus tendon"
    if part == EXTENSOR_DIGITORUM_LONGUS_TENDON:
        return "extensor digitorum longus tendon"
    if part == FIBULARIS_LONGUS_TENDON:
        return "fibularis longus tendon"
    if part == FIBULARIS_BREVIS_TENDON:
        return "fibularis brevis tendon"
    if part == TIBIALIS_POSTERIOR_TENDON:
        return "tibialis posterior tendon"
    if part == FLEXOR_HALLUCIS_LONGUS_TENDON:
        return "flexor hallucis longus tendon"
    if part == FLEXOR_DIGITORUM_LONGUS_TENDON:
        return "flexor digitorum longus tendon"
    if part == ABDUCTOR_HALLUCIS:
        return "abductor hallucis"
    if part == FLEXOR_DIGITORUM_BREVIS:
        return "flexor digitorum brevis"
    if part == ABDUCTOR_DIGITI_MINIMI:
        return "abductor digiti minimi"
    if part == QUADRATUS_PLANTAE:
        return "quadratus plantae"
    if part == LUMBRICALS:
        return "lumbricals"
    if part == FLEXOR_HALLUCIS_BREVIS:
        return "flexor hallucis brevis"
    if part == ADDUCTOR_HALLUCIS:
        return "adductor hallucis"
    if part == FLEXOR_DIGITI_MINIMI_BREVIS:
        return "flexor digiti minimi brevis"
    if part == DORSAL_INTEROSSEI:
        return "dorsal interossei"
    if part == PLANTAR_INTEROSSEI:
        return "plantar interossei"
    if part == EXTENSOR_DIGITORUM_BREVIS:
        return "extensor digitorum brevis"
    if part == EXTENSOR_HALLUCIS_BREVIS:
        return "extensor hallucis brevis"
    return "foot muscle"


def named_foot_muscles() -> List[FootMuscle]:
    """Return every named foot muscle and tendon in a stable order.

    Returns:
        Nine extrinsic tendons, then the intrinsic muscles.
    """
    var parts = List[FootMuscle]()
    parts.append(CALCANEAL_TENDON)
    parts.append(TIBIALIS_ANTERIOR_TENDON)
    parts.append(EXTENSOR_HALLUCIS_LONGUS_TENDON)
    parts.append(EXTENSOR_DIGITORUM_LONGUS_TENDON)
    parts.append(FIBULARIS_LONGUS_TENDON)
    parts.append(FIBULARIS_BREVIS_TENDON)
    parts.append(TIBIALIS_POSTERIOR_TENDON)
    parts.append(FLEXOR_HALLUCIS_LONGUS_TENDON)
    parts.append(FLEXOR_DIGITORUM_LONGUS_TENDON)
    parts.append(ABDUCTOR_HALLUCIS)
    parts.append(FLEXOR_DIGITORUM_BREVIS)
    parts.append(ABDUCTOR_DIGITI_MINIMI)
    parts.append(QUADRATUS_PLANTAE)
    parts.append(LUMBRICALS)
    parts.append(FLEXOR_HALLUCIS_BREVIS)
    parts.append(ADDUCTOR_HALLUCIS)
    parts.append(FLEXOR_DIGITI_MINIMI_BREVIS)
    parts.append(DORSAL_INTEROSSEI)
    parts.append(PLANTAR_INTEROSSEI)
    parts.append(EXTENSOR_DIGITORUM_BREVIS)
    parts.append(EXTENSOR_HALLUCIS_BREVIS)
    return parts^


def _tubes(dimensions: FootMuscleDimensions, part: FootMuscle) -> TubeSet:
    """Return the tubes of one named muscle or tendon."""
    if part.value <= FLEXOR_DIGITORUM_LONGUS_TENDON.value:
        return _tendon(dimensions, part)
    return _belly_part(dimensions, part)


def _tendon(dimensions: FootMuscleDimensions, part: FootMuscle) -> TubeSet:
    """Return one extrinsic tendon."""
    var foot = dimensions.foot
    var S = foot.stature.value
    var med = medial_axis(foot)
    var lateral = med * Float32(-1)
    var dorsal = Vector3(0, 0.008 * S, 0)
    if part == CALCANEAL_TENDON:
        return one_tube(
            _line(
                Vector3(0, 0.04 * S, Float32(-0.045) * S), foot.heel, 0.0036 * S
            )
        )
    if part == TIBIALIS_ANTERIOR_TENDON:
        var start = Vector3(0, Float32(-0.004) * S, 0.016 * S) + med * (
            0.008 * S
        )
        return one_tube(_line(start, foot.medial_cuneiform, 0.0020 * S))
    if part == EXTENSOR_HALLUCIS_LONGUS_TENDON:
        var start = Vector3(0, Float32(-0.002) * S, 0.018 * S) + med * (
            0.004 * S
        )
        return one_tube(
            _via(start, foot.mt1_head + dorsal, foot.hallux_tip, 0.0015 * S)
        )
    if part == EXTENSOR_DIGITORUM_LONGUS_TENDON:
        var start = Vector3(0, Float32(-0.002) * S, 0.016 * S) + lateral * (
            0.004 * S
        )
        var radius = 0.0013 * S
        return four_tubes(
            _via(start, foot.mt2_head + dorsal, foot.toe2_tip, radius),
            _via(start, foot.mt3_head + dorsal, foot.toe3_tip, radius),
            _via(start, foot.mt4_head + dorsal, foot.toe4_tip, radius),
            _via(start, foot.mt5_head + dorsal, foot.toe5_tip, radius),
        )
    if part == FIBULARIS_LONGUS_TENDON:
        var radius = 0.0018 * S
        return one_tube(
            _stations(
                foot.lateral_malleolus
                + Vector3(0, 0.010 * S, Float32(-0.004) * S),
                foot.lateral_malleolus
                + Vector3(0, Float32(-0.012) * S, -0.004 * S),
                foot.cuboid + Vector3(0, Float32(-0.008) * S, 0),
                mix_point(foot.cuboid, foot.medial_cuneiform, 0.55)
                + Vector3(0, Float32(-0.008) * S, 0),
                foot.medial_cuneiform + Vector3(0, Float32(-0.004) * S, 0),
                radius,
            )
        )
    if part == FIBULARIS_BREVIS_TENDON:
        return one_tube(
            _line(
                foot.lateral_malleolus
                + Vector3(0, 0.006 * S, Float32(-0.002) * S),
                foot.mt5_tuberosity,
                0.0016 * S,
            )
        )
    if part == TIBIALIS_POSTERIOR_TENDON:
        return one_tube(
            _via(
                foot.medial_malleolus
                + Vector3(0, 0.012 * S, Float32(-0.008) * S),
                foot.medial_malleolus
                + Vector3(0, Float32(-0.008) * S, -0.004 * S),
                foot.navicular_tuberosity,
                0.0020 * S,
            )
        )
    if part == FLEXOR_HALLUCIS_LONGUS_TENDON:
        return one_tube(
            _stations(
                foot.medial_malleolus
                + Vector3(0, 0.008 * S, Float32(-0.010) * S),
                foot.sustentaculum + Vector3(0, Float32(-0.004) * S, 0),
                mix_point(foot.sustentaculum, foot.mt1_head, 0.55)
                + Vector3(0, Float32(-0.006) * S, 0),
                foot.hallux_ip + Vector3(0, Float32(-0.004) * S, 0),
                foot.hallux_tip + Vector3(0, Float32(-0.003) * S, 0),
                0.0017 * S,
            )
        )
    var knot = mix_point(foot.sustentaculum, foot.mt3_base, 0.65) + Vector3(
        0, Float32(-0.006) * S, 0
    )
    var start = foot.medial_malleolus + Vector3(
        0, 0.006 * S, Float32(-0.008) * S
    )
    var plantar = Vector3(0, Float32(-0.003) * S, 0)
    var radius = 0.0012 * S
    return four_tubes(
        _via(start, knot, foot.toe2_tip + plantar, radius),
        _via(start, knot, foot.toe3_tip + plantar, radius),
        _via(start, knot, foot.toe4_tip + plantar, radius),
        _via(start, knot, foot.toe5_tip + plantar, radius),
    )


def _belly_part(dimensions: FootMuscleDimensions, part: FootMuscle) -> TubeSet:
    """Return one intrinsic muscle."""
    var foot = dimensions.foot
    var S = foot.stature.value
    var scale = dimensions.scale
    var med = medial_axis(foot)
    var lateral = med * Float32(-1)
    var down = Vector3(0, Float32(-0.004) * S, 0)
    var up = Vector3(0, 0.004 * S, 0)
    if part == ABDUCTOR_HALLUCIS:
        return one_tube(
            _belly(
                foot.heel + med * (0.012 * S),
                foot.hallux_ip,
                med * (0.006 * S) + down,
                0.0065 * S,
                scale,
            )
        )
    if part == FLEXOR_DIGITORUM_BREVIS:
        var origin = foot.heel + Vector3(0, Float32(-0.006) * S, 0.010 * S)
        var radius = 0.0048 * S
        return four_tubes(
            _belly(origin, foot.toe2_pip + down, down, radius, scale),
            _belly(origin, foot.toe3_pip + down, down, radius, scale),
            _belly(origin, foot.toe4_pip + down, down, radius, scale),
            _belly(origin, foot.toe5_pip + down, down, radius, scale),
        )
    if part == ABDUCTOR_DIGITI_MINIMI:
        return one_tube(
            _belly(
                foot.heel + lateral * (0.012 * S),
                foot.toe5_pip,
                lateral * (0.005 * S) + down,
                0.0055 * S,
                scale,
            )
        )
    if part == QUADRATUS_PLANTAE:
        var knot = mix_point(foot.heel, foot.mt3_base, 0.55) + Vector3(
            0, Float32(-0.006) * S, 0
        )
        return two_tubes(
            _belly(
                foot.sustentaculum, knot, med * (0.003 * S), 0.0035 * S, scale
            ),
            _belly(
                foot.calcaneal_lateral,
                knot,
                lateral * (0.003 * S),
                0.0035 * S,
                scale,
            ),
        )
    if part == LUMBRICALS:
        var radius = 0.0018 * S
        return four_tubes(
            _belly(
                foot.mt2_head
                + Vector3(0, Float32(-0.004) * S, Float32(-0.010) * S),
                foot.toe2_pip + up,
                up,
                radius,
                scale,
            ),
            _belly(
                foot.mt3_head
                + Vector3(0, Float32(-0.004) * S, Float32(-0.010) * S),
                foot.toe3_pip + up,
                up,
                radius,
                scale,
            ),
            _belly(
                foot.mt4_head
                + Vector3(0, Float32(-0.004) * S, Float32(-0.008) * S),
                foot.toe4_pip + up,
                up,
                radius,
                scale,
            ),
            _belly(
                foot.mt5_head
                + Vector3(0, Float32(-0.004) * S, Float32(-0.006) * S),
                foot.toe5_pip + up,
                up,
                radius,
                scale,
            ),
        )
    if part == FLEXOR_HALLUCIS_BREVIS:
        return two_tubes(
            _belly(
                foot.medial_cuneiform,
                foot.hallux_ip,
                med * (0.003 * S),
                0.0032 * S,
                scale,
            ),
            _belly(foot.cuboid, foot.hallux_ip, down, 0.0030 * S, scale),
        )
    if part == ADDUCTOR_HALLUCIS:
        return two_tubes(
            _belly(foot.mt3_base, foot.hallux_ip, down, 0.0030 * S, scale),
            _belly(foot.mt5_head, foot.mt1_head, down, 0.0024 * S, scale),
        )
    if part == FLEXOR_DIGITI_MINIMI_BREVIS:
        return one_tube(
            _belly(
                foot.mt5_base,
                foot.toe5_pip,
                lateral * (0.002 * S),
                0.0028 * S,
                scale,
            )
        )
    if part == DORSAL_INTEROSSEI:
        var radius = 0.0022 * S
        return four_tubes(
            _belly(
                mix_point(foot.mt1_base, foot.mt2_base, 0.5),
                foot.toe2_pip,
                up,
                radius,
                scale,
            ),
            _belly(
                mix_point(foot.mt2_base, foot.mt3_base, 0.5),
                foot.toe2_pip,
                up,
                radius,
                scale,
            ),
            _belly(
                mix_point(foot.mt3_base, foot.mt4_base, 0.5),
                foot.toe3_pip,
                up,
                radius,
                scale,
            ),
            _belly(
                mix_point(foot.mt4_base, foot.mt5_base, 0.5),
                foot.toe4_pip,
                up,
                radius,
                scale,
            ),
        )
    if part == PLANTAR_INTEROSSEI:
        var radius = 0.0020 * S
        return three_tubes(
            _belly(foot.mt3_base, foot.toe3_pip, down, radius, scale),
            _belly(foot.mt4_base, foot.toe4_pip, down, radius, scale),
            _belly(foot.mt5_base, foot.toe5_pip, down, radius, scale),
        )
    if part == EXTENSOR_DIGITORUM_BREVIS:
        var origin = foot.calcaneal_lateral + Vector3(0, 0.008 * S, 0.010 * S)
        return three_tubes(
            _belly(origin, foot.toe2_pip + up, up, 0.0030 * S, scale),
            _belly(origin, foot.toe3_pip + up, up, 0.0028 * S, scale),
            _belly(origin, foot.toe4_pip + up, up, 0.0026 * S, scale),
        )
    var origin = foot.calcaneal_lateral + Vector3(0, 0.008 * S, 0.012 * S)
    return one_tube(
        _belly(
            origin,
            foot.hallux_ip + up,
            med * (0.002 * S),
            0.0026 * S,
            scale,
        )
    )


def _line(a: Vector3, b: Vector3, radius: Float32) -> TubeChain:
    """Return five stations on a straight tendon."""
    return TubeChain(
        a,
        mix_point(a, b, 0.25),
        mix_point(a, b, 0.50),
        mix_point(a, b, 0.75),
        b,
        radius,
        radius,
        radius,
        radius * 0.92,
        radius * 0.85,
    )


def _via(a: Vector3, b: Vector3, c: Vector3, radius: Float32) -> TubeChain:
    """Return five stations from `a` to `c` through `b`."""
    return TubeChain(
        a,
        mix_point(a, b, 0.5),
        b,
        mix_point(b, c, 0.5),
        c,
        radius,
        radius,
        radius,
        radius * 0.90,
        radius * 0.80,
    )


def _stations(
    a: Vector3,
    b: Vector3,
    c: Vector3,
    d: Vector3,
    e: Vector3,
    radius: Float32,
) -> TubeChain:
    """Return one tendon through five given stations."""
    return TubeChain(
        a,
        b,
        c,
        d,
        e,
        radius,
        radius,
        radius,
        radius * 0.92,
        radius * 0.85,
    )


def _belly(
    a: Vector3, b: Vector3, bow: Vector3, radius: Float32, scale: Float32
) -> TubeChain:
    """Return a tapered belly from `a` to `b`, bowed by `bow`."""
    var mid = mix_point(a, b, 0.5) + bow
    var rs = radius * scale
    return TubeChain(
        a,
        mix_point(a, mid, 0.5),
        mid,
        mix_point(mid, b, 0.5),
        b,
        rs * 0.50,
        rs * 0.82,
        rs,
        rs * 0.78,
        rs * 0.42,
    )
