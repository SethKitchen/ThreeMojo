# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named arteries and veins of one leg, as implicit tubes in the leg frame.

The labeled set follows a standard dissection of the lower-limb vessels.
Paths are authored from the stature-scaled muscle landmarks. Radii are
authored ratios of stature. They are template parameters. They are not
a cited vessel-diameter table.

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
    tapered_tube,
    tube_chain_bounds,
    tube_chain_distance,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleDimensions
from math.vector3 import Vector3


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
comptime POSTERIOR_TIBIAL_ARTERY = VesselPart(3)
comptime PERONEAL_ARTERY = VesselPart(4)
comptime FEMORAL_VEIN = VesselPart(5)
comptime POPLITEAL_VEIN = VesselPart(6)
comptime GREAT_SAPHENOUS_VEIN = VesselPart(7)
comptime SMALL_SAPHENOUS_VEIN = VesselPart(8)


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
        elif part == POSTERIOR_TIBIAL_ARTERY:
            chain = _posterior_tibial_artery(dimensions, S)
        elif part == PERONEAL_ARTERY:
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
        self.k = 0.003 * S
        self.epsilon = dimensions.epsilon
        var box = tube_chain_bounds(chain, 0.008 + chain.r2)
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
    if part == POSTERIOR_TIBIAL_ARTERY:
        return "posterior tibial artery"
    if part == PERONEAL_ARTERY:
        return "peroneal artery"
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
    return part.value <= PERONEAL_ARTERY.value


def named_vessel_parts() -> List[VesselPart]:
    """Return every named vessel in a stable order.

    Returns:
        Five arteries and four veins.
    """
    var parts = List[VesselPart]()
    parts.append(FEMORAL_ARTERY)
    parts.append(POPLITEAL_ARTERY)
    parts.append(ANTERIOR_TIBIAL_ARTERY)
    parts.append(POSTERIOR_TIBIAL_ARTERY)
    parts.append(PERONEAL_ARTERY)
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
    var origin = d.hip + Vector3(-lat * 0.018 * S, -0.018 * S, 0.014 * S)
    var insertion = d.med_condyle + Vector3(
        -lat * 0.010 * S, 0.040 * S, -0.018 * S
    )
    return tapered_tube(
        origin,
        insertion,
        Vector3(-lat * 0.020 * S, 0, 0.004 * S),
        0.0044 * S,
        0.0068 * S,
    )


def _popliteal_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var origin = d.med_condyle + Vector3(0, 0.040 * S, -0.018 * S)
    var insertion = d.tib_med + Vector3(0, -0.030 * S, -0.022 * S)
    return tapered_tube(
        origin, insertion, Vector3(0, 0, -0.024 * S), 0.0038 * S, 0.0060 * S
    )


def _anterior_tibial_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var origin = d.tib_lat + Vector3(0, -0.028 * S, 0.008 * S)
    var insertion = d.plafond + Vector3(lat * 0.006 * S, 0, 0.016 * S)
    return tapered_tube(
        origin, insertion, Vector3(0, 0, 0.014 * S), 0.0028 * S, 0.0042 * S
    )


def _posterior_tibial_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var origin = d.tib_med + Vector3(0, -0.028 * S, -0.018 * S)
    var insertion = d.med_mal + Vector3(0, 0.016 * S, -0.006 * S)
    return tapered_tube(
        origin, insertion, Vector3(0, 0, -0.016 * S), 0.0028 * S, 0.0044 * S
    )


def _peroneal_artery(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var origin = d.fib_head + Vector3(0, -0.020 * S, -0.006 * S)
    var insertion = d.lat_mal + Vector3(0, 0.016 * S, -0.004 * S)
    return tapered_tube(
        origin,
        insertion,
        Vector3(lat * 0.006 * S, 0, -0.004 * S),
        0.0026 * S,
        0.0038 * S,
    )


def _femoral_vein(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var origin = d.hip + Vector3(-lat * 0.022 * S, -0.018 * S, 0.010 * S)
    var insertion = d.med_condyle + Vector3(
        -lat * 0.014 * S, 0.040 * S, -0.016 * S
    )
    return tapered_tube(
        origin,
        insertion,
        Vector3(-lat * 0.024 * S, 0, 0.002 * S),
        0.0048 * S,
        0.0074 * S,
    )


def _popliteal_vein(d: MuscleDimensions, S: Float32) -> TubeChain:
    var origin = d.med_condyle + Vector3(0, 0.040 * S, -0.016 * S)
    var insertion = d.tib_med + Vector3(0, -0.028 * S, -0.020 * S)
    return tapered_tube(
        origin, insertion, Vector3(0, 0, -0.022 * S), 0.0044 * S, 0.0066 * S
    )


def _great_saphenous(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var origin = d.med_mal + Vector3(-lat * 0.010 * S, 0.008 * S, 0.006 * S)
    var insertion = d.hip + Vector3(-lat * 0.024 * S, -0.028 * S, 0.012 * S)
    return tapered_tube(
        origin,
        insertion,
        Vector3(-lat * 0.030 * S, 0, 0.010 * S),
        0.0034 * S,
        0.0048 * S,
    )


def _small_saphenous(d: MuscleDimensions, S: Float32) -> TubeChain:
    var lat = _lat(d)
    var origin = d.lat_mal + Vector3(lat * 0.008 * S, 0.010 * S, -0.006 * S)
    var insertion = d.lat_condyle + Vector3(0, -0.010 * S, -0.024 * S)
    return tapered_tube(
        origin,
        insertion,
        Vector3(lat * 0.012 * S, 0, -0.018 * S),
        0.0028 * S,
        0.0040 * S,
    )
