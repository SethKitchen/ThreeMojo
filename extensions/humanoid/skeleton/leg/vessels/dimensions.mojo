# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named arteries and veins of one leg, as implicit tubes in the leg frame.

The centerlines preserve the femoral-popliteal-tibial arterial tree,
the fibular branch, both deep veins and both saphenous junctions.
Physical radii drive distance and mass. Geometry applies a separate
diagrammatic minimum radius so the current isosurface can show them.

The solids live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var dims = muscle_dimensions(person)
    var d = vessel_distance(dims, FEMORAL_ARTERY, Vector3(0, 0.2, 0.02))
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
struct VesselPart(Equatable, ImplicitlyCopyable, Writable):
    """Which named artery or vein a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary that
    reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named vessel."""
        if self.value < 0:
            return False
        return self.value <= SMALL_SAPHENOUS_VEIN.value


comptime FEMORAL_ARTERY = VesselPart(0)
comptime POPLITEAL_ARTERY = VesselPart(1)
comptime ANTERIOR_TIBIAL_ARTERY = VesselPart(2)
comptime TIBIOPERONEAL_TRUNK = VesselPart(3)
comptime POSTERIOR_TIBIAL_ARTERY = VesselPart(4)
comptime FIBULAR_ARTERY = VesselPart(5)
# Compatibility name for the fibular artery.
comptime PERONEAL_ARTERY = FIBULAR_ARTERY
comptime FEMORAL_VEIN = VesselPart(6)
comptime POPLITEAL_VEIN = VesselPart(7)
comptime GREAT_SAPHENOUS_VEIN = VesselPart(8)
comptime SMALL_SAPHENOUS_VEIN = VesselPart(9)


struct VesselField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `VesselPart`."""

    var chain: TubeChain
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: MuscleDimensions, part: VesselPart
    ) raises:
        """Build one vessel from muscle landmarks that `validate` accepts.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named vessel.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A vessel part must be a named artery or vein")
        var S = dimensions.stature.value
        var chain: TubeChain
        if part == FEMORAL_ARTERY:
            chain = _femoral_artery(dimensions, S)
        elif part == POPLITEAL_ARTERY:
            chain = _popliteal_artery(dimensions, S)
        elif part == ANTERIOR_TIBIAL_ARTERY:
            chain = _anterior_tibial_artery(dimensions, S)
        elif part == TIBIOPERONEAL_TRUNK:
            chain = _tibioperoneal_trunk(dimensions, S)
        elif part == POSTERIOR_TIBIAL_ARTERY:
            chain = _posterior_tibial_artery(dimensions, S)
        elif part == FIBULAR_ARTERY:
            chain = _peroneal_artery(dimensions, S)
        elif part == FEMORAL_VEIN:
            chain = _femoral_vein(dimensions, S)
        elif part == POPLITEAL_VEIN:
            chain = _popliteal_vein(dimensions, S)
        elif part == GREAT_SAPHENOUS_VEIN:
            chain = _great_saphenous(dimensions, S)
        else:
            chain = _small_saphenous(dimensions, S)
        self.chain = chain
        self.k = Float32(0.00025)
        self.epsilon = Float32(0.00015)
        var box = tube_chain_bounds(chain, Float32(0.003) + chain.r0)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the vessel, in meters.

        Negative is inside. Zero is the surface.
        """
        return tube_chain_distance(self.chain, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def _display_vessel_field(
    dimensions: MuscleDimensions, part: VesselPart
) raises -> VesselField:
    """Return a vessel with a diagrammatic minimum mesh radius."""
    var field = VesselField(dimensions, part)
    var least = 0.0018 * dimensions.stature.value
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


def vessel_distance(
    dimensions: MuscleDimensions, part: VesselPart, point: Vector3
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
    return VesselField(dimensions, part).distance(point)


def vessel_part_label(part: VesselPart) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A vessel part.

    Returns:
        A short English name, or `"vessel"` when `part` is not named.
    """
    if part == FEMORAL_ARTERY:
        return "femoral artery"
    if part == POPLITEAL_ARTERY:
        return "popliteal artery"
    if part == ANTERIOR_TIBIAL_ARTERY:
        return "anterior tibial artery"
    if part == TIBIOPERONEAL_TRUNK:
        return "tibioperoneal trunk"
    if part == POSTERIOR_TIBIAL_ARTERY:
        return "posterior tibial artery"
    if part == FIBULAR_ARTERY:
        return "fibular artery"
    if part == FEMORAL_VEIN:
        return "femoral vein"
    if part == POPLITEAL_VEIN:
        return "popliteal vein"
    if part == GREAT_SAPHENOUS_VEIN:
        return "great saphenous vein"
    if part == SMALL_SAPHENOUS_VEIN:
        return "small saphenous vein"
    return "vessel"


def is_artery(part: VesselPart) raises -> Bool:
    """Return True if `part` is an artery rather than a vein.

    Args:
        part: A named vessel.

    Returns:
        True for the five named arteries.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A vessel part must be a named artery or vein")
    return part.value <= FIBULAR_ARTERY.value


def named_vessel_parts() -> List[VesselPart]:
    """Return every named vessel in a stable order.

    Returns:
        Six arterial segments and four veins.
    """
    var parts = List[VesselPart]()
    parts.append(FEMORAL_ARTERY)
    parts.append(POPLITEAL_ARTERY)
    parts.append(ANTERIOR_TIBIAL_ARTERY)
    parts.append(TIBIOPERONEAL_TRUNK)
    parts.append(POSTERIOR_TIBIAL_ARTERY)
    parts.append(FIBULAR_ARTERY)
    parts.append(FEMORAL_VEIN)
    parts.append(POPLITEAL_VEIN)
    parts.append(GREAT_SAPHENOUS_VEIN)
    parts.append(SMALL_SAPHENOUS_VEIN)
    return parts^


def _lat(dimensions: MuscleDimensions) -> Float32:
    """Return +1 on a right leg and -1 on a left leg."""
    if dimensions.side == LEFT:
        return Float32(-1)
    return Float32(1)


def _femoral_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _groin_artery(d, S)
    var p1 = mix_point(d.hip, d.femur_mid, 0.28) + Vector3(
        -lat * 0.020 * S, 0, 0.014 * S
    )
    var p2 = d.femur_mid + Vector3(-lat * 0.022 * S, 0, 0.008 * S)
    var p3 = mix_point(d.femur_mid, d.med_condyle, 0.64) + Vector3(
        -lat * 0.018 * S, 0, -0.006 * S
    )
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        _adductor_hiatus(d, S),
        0.0045,
        0.0043,
        0.0041,
        0.0038,
        0.0035,
    )


def _popliteal_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    var tibia = mix_point(d.tib_med, d.tib_lat, 0.50)
    return TubeChain(
        _adductor_hiatus(d, S),
        knee + Vector3(0, 0.026 * S, -0.025 * S),
        knee + Vector3(0, 0, -0.030 * S),
        tibia + Vector3(0, -0.024 * S, -0.026 * S),
        _tibial_branch(d, S),
        0.0035,
        0.0034,
        0.0033,
        0.0030,
        0.0028,
    )


def _anterior_tibial_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _tibial_branch(d, S)
    var p1 = mix_point(d.tib_lat, d.fib_head, 0.48) + Vector3(
        -lat * 0.004 * S, -0.038 * S, 0.004 * S
    )
    var p2 = mix_point(d.tib_lat, d.plafond, 0.45) + Vector3(
        lat * 0.003 * S, 0, 0.014 * S
    )
    var p3 = mix_point(d.tibia_mid, d.plafond, 0.68) + Vector3(
        lat * 0.004 * S, 0, 0.015 * S
    )
    var p4 = d.plafond + Vector3(lat * 0.005 * S, 0, 0.014 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0015,
        0.0014,
        0.0013,
        0.0012,
        0.0011,
    )


def _tibioperoneal_trunk(d: MuscleDimensions, S: Float32) -> TubeChain:
    var p0 = _tibial_branch(d, S)
    var p4 = _fibular_branch(d, S)
    return TubeChain(
        p0,
        mix_point(p0, p4, 0.25),
        mix_point(p0, p4, 0.50),
        mix_point(p0, p4, 0.75),
        p4,
        0.0016,
        0.00155,
        0.0015,
        0.00145,
        0.0014,
    )


def _posterior_tibial_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _fibular_branch(d, S)
    var p1 = mix_point(
        p0,
        d.tibia_mid + Vector3(-lat * 0.006 * S, 0, -0.018 * S),
        0.28,
    )
    var p2 = d.tibia_mid + Vector3(-lat * 0.006 * S, 0, -0.018 * S)
    var p3 = mix_point(d.tibia_mid, d.med_mal, 0.72) + Vector3(
        -lat * 0.008 * S, 0, -0.014 * S
    )
    var p4 = d.med_mal + Vector3(-lat * 0.004 * S, 0.006 * S, -0.010 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0015,
        0.0014,
        0.00105,
        0.0010,
        0.0009,
    )


def _peroneal_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _fibular_branch(d, S)
    var p1 = mix_point(d.fib_head, d.fibula_mid, 0.32) + Vector3(
        -lat * 0.004 * S, 0, -0.014 * S
    )
    var p2 = d.fibula_mid + Vector3(-lat * 0.004 * S, 0, -0.012 * S)
    var p3 = mix_point(d.fibula_mid, d.lat_mal, 0.72) + Vector3(
        -lat * 0.003 * S, 0, -0.010 * S
    )
    var p4 = d.lat_mal + Vector3(-lat * 0.002 * S, 0.012 * S, -0.008 * S)
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        p4,
        0.0011,
        0.00105,
        0.0010,
        0.0009,
        0.0008,
    )


def _femoral_vein(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = _vein_hiatus(d, S)
    var p1 = mix_point(d.med_condyle, d.femur_mid, 0.58) + Vector3(
        -lat * 0.023 * S, 0, -0.004 * S
    )
    var p2 = d.femur_mid + Vector3(-lat * 0.027 * S, 0, 0.004 * S)
    var p3 = mix_point(d.femur_mid, d.hip, 0.70) + Vector3(
        -lat * 0.027 * S, 0, 0.010 * S
    )
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        _groin_vein(d, S),
        0.0040,
        0.0042,
        0.0045,
        0.0048,
        0.0050,
    )


def _popliteal_vein(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    var tibia = mix_point(d.tib_med, d.tib_lat, 0.50)
    return TubeChain(
        _venous_branch(d, S) + Vector3(-lat * 0.004 * S, 0, 0),
        tibia + Vector3(-lat * 0.003 * S, -0.022 * S, -0.034 * S),
        _popliteal_vein_knee(d, S),
        knee + Vector3(lat * 0.003 * S, 0.028 * S, -0.036 * S),
        _vein_hiatus(d, S),
        0.0035,
        0.0036,
        0.0038,
        0.0039,
        0.0040,
    )


def _great_saphenous(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = d.med_mal + Vector3(-lat * 0.010 * S, 0, 0.008 * S)
    var p1 = mix_point(d.med_mal, d.tibia_mid, 0.58) + Vector3(
        -lat * 0.020 * S, 0, 0.004 * S
    )
    var p2 = d.med_condyle + Vector3(-lat * 0.026 * S, 0, -0.010 * S)
    var p3 = mix_point(d.med_condyle, d.hip, 0.62) + Vector3(
        -lat * 0.034 * S, 0, 0.006 * S
    )
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        _groin_vein(d, S),
        0.0020,
        0.0021,
        0.0022,
        0.0023,
        0.0025,
    )


def _small_saphenous(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var p0 = d.lat_mal + Vector3(lat * 0.006 * S, 0, -0.010 * S)
    var p1 = mix_point(d.lat_mal, d.tibia_mid, 0.45) + Vector3(
        lat * 0.004 * S, 0, -0.026 * S
    )
    var p2 = d.tibia_mid + Vector3(0, 0, -0.032 * S)
    var p3 = mix_point(d.tibia_mid, d.lat_condyle, 0.70) + Vector3(
        0, 0, -0.034 * S
    )
    return TubeChain(
        p0,
        p1,
        p2,
        p3,
        _saphenopopliteal_junction(d, S),
        0.0014,
        0.0015,
        0.0016,
        0.0017,
        0.0018,
    )


def _groin_artery(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the femoral artery below the inguinal ligament."""
    var lat = _lat(d)
    return d.hip + Vector3(-lat * 0.018 * S, -0.024 * S, 0.016 * S)


def _groin_vein(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the femoral vein medial to the artery in the groin."""
    var lat = _lat(d)
    return _groin_artery(d, S) + Vector3(-lat * 0.009 * S, 0, -0.002 * S)


def _adductor_hiatus(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the artery at the posterior opening of adductor magnus."""
    var lat = _lat(d)
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    return knee + Vector3(-lat * 0.008 * S, 0.055 * S, -0.026 * S)


def _vein_hiatus(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the vein beside the artery at the adductor hiatus."""
    var lat = _lat(d)
    return _adductor_hiatus(d, S) + Vector3(-lat * 0.006 * S, 0, -0.004 * S)


def _tibial_branch(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the popliteal arterial bifurcation below the popliteus."""
    var tibia = mix_point(d.tib_med, d.tib_lat, 0.50)
    return tibia + Vector3(0, -0.038 * S, -0.022 * S)


def _fibular_branch(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the fibular arterial branch from the tibioperoneal path."""
    var lat = _lat(d)
    return _tibial_branch(d, S) + Vector3(
        lat * 0.004 * S, -0.0175 * S, -0.004 * S
    )


def _venous_branch(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the deep-vein confluence below the popliteal fossa."""
    return _tibial_branch(d, S) + Vector3(0, 0, -0.006 * S)


def _popliteal_vein_knee(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the popliteal vein superficial to the popliteal artery."""
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    return knee + Vector3(0, 0, -0.040 * S)


def _saphenopopliteal_junction(d: MuscleDimensions, S: Float32) -> Vector3:
    """Return the common small-saphenous junction above the knee."""
    var knee = mix_point(d.med_condyle, d.lat_condyle, 0.50)
    var lat = _lat(d)
    return knee + Vector3(lat * 0.003 * S, 0.028 * S, -0.036 * S)
