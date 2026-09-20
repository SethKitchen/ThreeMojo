# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named peripheral nerves of one leg, as implicit tubes in the leg frame.

The labeled set is the femoral, sciatic, tibial, common fibular,
saphenous and sural nerves. Centerlines preserve the sciatic
bifurcation and the femoral-to-saphenous branch. Physical radii drive
distance and mass. Geometry applies a separate display minimum.

The solids live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = muscle_dimensions(person)
    var d = nerve_distance(dims, SCIATIC_NERVE, Vector3(0, 0.2, -0.04))
"""

from extensions.humanoid.side import LEFT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    field_gradient,
    mix_point,
    tube_chain_bounds,
    tube_chain_distance,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleDimensions
from math.vector3 import Vector3
from std.math import max


@fieldwise_init
struct NervePart(Equatable, ImplicitlyCopyable, Writable):
    """Which named nerve a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary that
    reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named nerve."""
        if self.value < 0:
            return False
        return self.value <= SURAL_NERVE.value


comptime FEMORAL_NERVE = NervePart(0)
comptime SCIATIC_NERVE = NervePart(1)
comptime TIBIAL_NERVE = NervePart(2)
comptime COMMON_FIBULAR_NERVE = NervePart(3)
# Compatibility name for the common fibular nerve.
comptime COMMON_PERONEAL_NERVE = COMMON_FIBULAR_NERVE
comptime SAPHENOUS_NERVE = NervePart(4)
comptime SURAL_NERVE = NervePart(5)


struct NerveField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `NervePart`."""

    var chain: TubeChain
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: MuscleDimensions, part: NervePart
    ) raises:
        """Build one nerve from muscle landmarks that `validate` accepts.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named nerve.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A nerve part must be a named peripheral nerve")
        var S = dimensions.stature.value
        var chain: TubeChain
        if part == FEMORAL_NERVE:
            chain = _femoral_nerve(dimensions, S)
        elif part == SCIATIC_NERVE:
            chain = _sciatic_nerve(dimensions, S)
        elif part == TIBIAL_NERVE:
            chain = _tibial_nerve(dimensions, S)
        elif part == COMMON_FIBULAR_NERVE:
            chain = _common_peroneal(dimensions, S)
        elif part == SAPHENOUS_NERVE:
            chain = _saphenous_nerve(dimensions, S)
        else:
            chain = _sural_nerve(dimensions, S)
        self.chain = chain
        self.k = Float32(0.00020)
        self.epsilon = Float32(0.00015)
        var box = tube_chain_bounds(chain, Float32(0.003) + chain.r0)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the nerve, in meters.

        Negative is inside. Zero is the surface.
        """
        return tube_chain_distance(self.chain, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def _display_nerve_field(
    dimensions: MuscleDimensions, part: NervePart
) raises -> NerveField:
    """Return a nerve with a diagrammatic minimum mesh radius."""
    var field = NerveField(dimensions, part)
    var least = 0.0015 * dimensions.stature.value
    field.chain.r0 = max(field.chain.r0, least)
    field.chain.r1 = max(field.chain.r1, least)
    field.chain.r2 = max(field.chain.r2, least)
    field.chain.r3 = max(field.chain.r3, least)
    field.chain.r4 = max(field.chain.r4, least)
    field.k = 0.0008 * dimensions.stature.value
    field.epsilon = Float32(0.25) * least
    var box = tube_chain_bounds(field.chain, 0.008 + field.chain.r2)
    field.low = box.low
    field.high = box.high
    return field


def nerve_distance(
    dimensions: MuscleDimensions, part: NervePart, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return NerveField(dimensions, part).distance(point)


def nerve_part_label(part: NervePart) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A nerve part.

    Returns:
        A short English name, or `"nerve"` when `part` is not named.
    """
    if part == FEMORAL_NERVE:
        return "femoral nerve"
    if part == SCIATIC_NERVE:
        return "sciatic nerve"
    if part == TIBIAL_NERVE:
        return "tibial nerve"
    if part == COMMON_FIBULAR_NERVE:
        return "common fibular nerve"
    if part == SAPHENOUS_NERVE:
        return "saphenous nerve"
    if part == SURAL_NERVE:
        return "sural nerve"
    return "nerve"


def named_nerve_parts() -> List[NervePart]:
    """Return every named nerve in a stable order.

    Returns:
        The six labeled trunks.
    """
    var parts = List[NervePart]()
    parts.append(FEMORAL_NERVE)
    parts.append(SCIATIC_NERVE)
    parts.append(TIBIAL_NERVE)
    parts.append(COMMON_FIBULAR_NERVE)
    parts.append(SAPHENOUS_NERVE)
    parts.append(SURAL_NERVE)
    return parts^


def _lat(d: MuscleDimensions) -> Float32:
    """Return +1 on a right leg and -1 on a left leg."""
    if d.side == LEFT:
        return Float32(-1)
    return Float32(1)


def _femoral_nerve(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = d.hip + Vector3(lat * 0.004 * S, -0.016 * S, 0.020 * S)
    var p1 = mix_point(d.hip, d.femur_mid, 0.14) + Vector3(
        lat * 0.010 * S, 0, 0.020 * S
    )
    var p2 = mix_point(d.hip, d.femur_mid, 0.24) + Vector3(
        lat * 0.012 * S, 0, 0.018 * S
    )
    var p3 = _saphenous_origin(d, S)
    var p4 = mix_point(d.hip, d.femur_mid, 0.42) + Vector3(
        lat * 0.014 * S, 0, 0.014 * S
    )
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0031,
        0.0030,
        0.0029,
        0.0027,
        0.0025,
    )


def _sciatic_nerve(d: MuscleDimensions, S: Float32) -> TubeChain:
    var p0 = mix_point(d.ischial, d.gt, 0.50) + Vector3(
        0, -0.004 * S, -0.020 * S
    )
    var p1 = mix_point(p0, d.femur_mid, 0.34) + Vector3(0, 0, -0.026 * S)
    var p2 = d.femur_mid + Vector3(0, 0, -0.034 * S)
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    var p3 = mix_point(d.femur_mid, knee, 0.70) + Vector3(0, 0, -0.032 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        _sciatic_split(d, S),
        0.0065,
        0.0058,
        0.0050,
        0.0045,
        0.0041,
    )


def _tibial_nerve(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _sciatic_split(d, S)
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    var p1 = knee + Vector3(0, 0, -0.050 * S)
    var p2 = d.tibia_mid + Vector3(-lat * 0.004 * S, 0, -0.026 * S)
    var p3 = mix_point(d.tibia_mid, d.med_mal, 0.72) + Vector3(
        -lat * 0.006 * S, 0, -0.018 * S
    )
    var p4 = d.med_mal + Vector3(-lat * 0.004 * S, 0.006 * S, -0.012 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0029,
        0.0029,
        0.0025,
        0.0022,
        0.0020,
    )


def _common_peroneal(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _sciatic_split(d, S)
    var p1 = mix_point(d.lat_condyle, d.fib_head, 0.18) + Vector3(
        lat * 0.008 * S, 0.018 * S, -0.024 * S
    )
    var p2 = d.lat_condyle + Vector3(lat * 0.008 * S, 0, -0.024 * S)
    var p3 = d.fib_head + Vector3(lat * 0.006 * S, 0, -0.010 * S)
    var p4 = d.fib_head + Vector3(lat * 0.014 * S, -0.018 * S, 0.004 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0018,
        0.0017,
        0.0016,
        0.0016,
        0.0015,
    )


def _saphenous_nerve(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _saphenous_origin(d, S)
    var p1 = mix_point(d.femur_mid, d.med_condyle, 0.58) + Vector3(
        -lat * 0.020 * S, 0, 0.008 * S
    )
    var p2 = d.med_condyle + Vector3(-lat * 0.020 * S, 0, 0.004 * S)
    var p3 = mix_point(d.tibia_mid, d.med_mal, 0.42) + Vector3(
        -lat * 0.018 * S, 0, 0.004 * S
    )
    var p4 = d.med_mal + Vector3(-lat * 0.008 * S, 0.010 * S, 0.006 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0011,
        0.0010,
        0.0009,
        0.0008,
        0.0007,
    )


def _sural_nerve(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = mix_point(d.tibia_mid, d.lat_mal, 0.20) + Vector3(0, 0, -0.028 * S)
    var p1 = mix_point(d.tibia_mid, d.lat_mal, 0.38) + Vector3(
        lat * 0.003 * S, 0, -0.026 * S
    )
    var p2 = mix_point(d.tibia_mid, d.lat_mal, 0.56) + Vector3(
        lat * 0.005 * S, 0, -0.022 * S
    )
    var p3 = mix_point(d.tibia_mid, d.lat_mal, 0.76) + Vector3(
        lat * 0.007 * S, 0, -0.018 * S
    )
    var p4 = d.lat_mal + Vector3(lat * 0.006 * S, 0.006 * S, -0.014 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0009,
        0.0009,
        0.00085,
        0.0008,
        0.0007,
    )


def _sciatic_split(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the usual sciatic division at the popliteal-fossa apex."""
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    return knee + Vector3(0, 0.060 * S, -0.032 * S)


def _saphenous_origin(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the saphenous branch of the femoral nerve in the thigh."""
    var lat = _lat(d)
    return mix_point(d.hip, d.femur_mid, 0.34) + Vector3(
        -lat * 0.004 * S, 0, 0.016 * S
    )
