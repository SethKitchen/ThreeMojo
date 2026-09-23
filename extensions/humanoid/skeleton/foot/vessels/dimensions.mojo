# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named arteries and veins of one foot, as implicit tubes.

The arteries are the dorsalis pedis, the arcuate, the posterior tibial,
the medial and lateral plantar arteries and the plantar arch. The veins
are the dorsal venous arch and the great and small saphenous veins at
the ankle. Physical radii are authored stature ratios in the range of
adult ankle calibers. They are not a cited table cell.

Physical radii drive distance and mass. Geometry applies a separate
diagrammatic minimum radius so the current isosurface can show them.
Superficial veins sit on the dorsum and in front of or behind the
malleoli. Deep arteries do not define the foot's bulk.

The solids live in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_dimensions(Length(6.0, FOOT), MALE)
    var d = vessel_distance(dims, DORSALIS_PEDIS_ARTERY, Vector3(0, 0, 0.05))
"""

from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    field_gradient,
    mix_point,
)
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    medial_axis,
)
from extensions.humanoid.skeleton.foot.chain import (
    TubeSet,
    enlarge_tube_set,
    one_tube,
    tube_set_bounds,
    tube_set_distance,
)
from math.vector3 import Vector3


@fieldwise_init
struct FootVessel(Equatable, ImplicitlyCopyable, Writable):
    """Which named artery or vein of the foot a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named vessels is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named foot vessel."""
        if self.value < 0:
            return False
        return self.value <= SMALL_SAPHENOUS_VEIN.value


comptime DORSALIS_PEDIS_ARTERY = FootVessel(0)
comptime ARCUATE_ARTERY = FootVessel(1)
comptime POSTERIOR_TIBIAL_ARTERY = FootVessel(2)
comptime MEDIAL_PLANTAR_ARTERY = FootVessel(3)
comptime LATERAL_PLANTAR_ARTERY = FootVessel(4)
comptime PLANTAR_ARCH = FootVessel(5)
comptime DORSAL_VENOUS_ARCH = FootVessel(6)
comptime GREAT_SAPHENOUS_VEIN = FootVessel(7)
comptime SMALL_SAPHENOUS_VEIN = FootVessel(8)


struct FootVesselField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one named foot vessel."""

    var tubes: TubeSet
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FootDimensions, part: FootVessel) raises:
        """Build one vessel from landmarks that `validate` accepts.

        Args:
            dimensions: Foot landmarks.
            part: A named vessel.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A foot vessel must be a named artery or vein")
        self.tubes = _tubes(dimensions, part)
        var S = dimensions.stature.value
        self.k = 0.00035 * S
        self.epsilon = 0.00020 * S
        var box = tube_set_bounds(self.tubes, 0.003)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the vessel, in meters.

        Negative is inside. Zero is the surface.
        """
        return tube_set_distance(self.tubes, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def display_vessel_field(
    dimensions: FootDimensions, part: FootVessel
) raises -> FootVesselField:
    """Return a vessel with a diagrammatic minimum mesh radius.

    Args:
        dimensions: Foot landmarks.
        part: A named vessel.

    Returns:
        The same centerline with radii held up for meshing.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    var field = FootVesselField(dimensions, part)
    var least = 0.0016 * dimensions.stature.value
    field.tubes = enlarge_tube_set(field.tubes, least)
    field.k = 0.0008 * dimensions.stature.value
    field.epsilon = 0.0004 * dimensions.stature.value
    var box = tube_set_bounds(field.tubes, 0.004)
    field.low = box.low
    field.high = box.high
    return field


def vessel_distance(
    dimensions: FootDimensions, part: FootVessel, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside. This is the physical radius, not the mesh radius.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which vessel to sample.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return FootVesselField(dimensions, part).distance(point)


def is_artery(part: FootVessel) raises -> Bool:
    """Return True if `part` is an artery.

    Args:
        part: A named vessel.

    Returns:
        True for the six named arteries.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A foot vessel must be a named artery or vein")
    return part.value <= PLANTAR_ARCH.value


def vessel_part_label(part: FootVessel) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A vessel, named or not.

    Returns:
        A short American English label, or `"foot vessel"` when `part`
        is not named.
    """
    if part == DORSALIS_PEDIS_ARTERY:
        return "dorsalis pedis artery"
    if part == ARCUATE_ARTERY:
        return "arcuate artery"
    if part == POSTERIOR_TIBIAL_ARTERY:
        return "posterior tibial artery"
    if part == MEDIAL_PLANTAR_ARTERY:
        return "medial plantar artery"
    if part == LATERAL_PLANTAR_ARTERY:
        return "lateral plantar artery"
    if part == PLANTAR_ARCH:
        return "plantar arch"
    if part == DORSAL_VENOUS_ARCH:
        return "dorsal venous arch"
    if part == GREAT_SAPHENOUS_VEIN:
        return "great saphenous vein"
    if part == SMALL_SAPHENOUS_VEIN:
        return "small saphenous vein"
    return "foot vessel"


def named_foot_vessels() -> List[FootVessel]:
    """Return every named foot vessel in a stable order.

    Returns:
        Six arteries, then three veins.
    """
    var parts = List[FootVessel]()
    parts.append(DORSALIS_PEDIS_ARTERY)
    parts.append(ARCUATE_ARTERY)
    parts.append(POSTERIOR_TIBIAL_ARTERY)
    parts.append(MEDIAL_PLANTAR_ARTERY)
    parts.append(LATERAL_PLANTAR_ARTERY)
    parts.append(PLANTAR_ARCH)
    parts.append(DORSAL_VENOUS_ARCH)
    parts.append(GREAT_SAPHENOUS_VEIN)
    parts.append(SMALL_SAPHENOUS_VEIN)
    return parts^


def _tubes(dimensions: FootDimensions, part: FootVessel) -> TubeSet:
    """Return the physical centerline of one vessel."""
    var S = dimensions.stature.value
    var med = medial_axis(dimensions)
    var lateral = med * Float32(-1)
    if part == DORSALIS_PEDIS_ARTERY:
        return one_tube(
            _via(
                Vector3(0, Float32(-0.002) * S, 0.012 * S),
                dimensions.intermediate_cuneiform + Vector3(0, 0.008 * S, 0),
                mix_point(dimensions.mt1_head, dimensions.mt2_head, 0.45)
                + Vector3(0, 0.008 * S, 0),
                0.00062 * S,
            )
        )
    if part == ARCUATE_ARTERY:
        return one_tube(
            _line(
                dimensions.intermediate_cuneiform + Vector3(0, 0.008 * S, 0),
                dimensions.mt5_base + Vector3(0, 0.006 * S, 0),
                0.00040 * S,
            )
        )
    if part == POSTERIOR_TIBIAL_ARTERY:
        return one_tube(
            _line(
                dimensions.medial_malleolus
                + Vector3(0, 0.016 * S, Float32(-0.006) * S),
                dimensions.medial_malleolus
                + Vector3(0, Float32(-0.014) * S, Float32(-0.004) * S),
                0.00078 * S,
            )
        )
    if part == MEDIAL_PLANTAR_ARTERY:
        return one_tube(
            _via(
                dimensions.medial_malleolus
                + Vector3(0, Float32(-0.014) * S, Float32(-0.004) * S),
                dimensions.navicular_tuberosity
                + Vector3(0, Float32(-0.006) * S, 0),
                dimensions.mt1_head + Vector3(0, Float32(-0.004) * S, 0),
                0.00048 * S,
            )
        )
    if part == LATERAL_PLANTAR_ARTERY:
        return one_tube(
            _via(
                dimensions.medial_malleolus
                + Vector3(0, Float32(-0.014) * S, Float32(-0.004) * S),
                dimensions.cuboid + Vector3(0, Float32(-0.008) * S, 0),
                dimensions.mt5_base + Vector3(0, Float32(-0.004) * S, 0),
                0.00058 * S,
            )
        )
    if part == PLANTAR_ARCH:
        return one_tube(
            _line(
                dimensions.mt5_base
                + Vector3(0, Float32(-0.005) * S, 0.010 * S),
                mix_point(dimensions.mt1_base, dimensions.mt2_base, 0.5)
                + Vector3(0, Float32(-0.004) * S, 0),
                0.00042 * S,
            )
        )
    if part == DORSAL_VENOUS_ARCH:
        return one_tube(
            _line(
                dimensions.mt5_head + Vector3(0, 0.012 * S, 0),
                dimensions.mt1_head + Vector3(0, 0.012 * S, 0),
                0.00090 * S,
            )
        )
    if part == GREAT_SAPHENOUS_VEIN:
        var front = (
            dimensions.medial_malleolus
            + med * (0.006 * S)
            + Vector3(0, 0.004 * S, 0.010 * S)
        )
        return one_tube(
            _via(
                dimensions.mt1_head
                + med * (0.008 * S)
                + Vector3(0, 0.012 * S, 0),
                front,
                front + Vector3(0, 0.030 * S, 0.004 * S),
                0.00085 * S,
            )
        )
    var behind = (
        dimensions.lateral_malleolus
        + lateral * (0.004 * S)
        + Vector3(0, 0.002 * S, Float32(-0.008) * S)
    )
    return one_tube(
        _via(
            dimensions.mt5_head
            + lateral * (0.006 * S)
            + Vector3(0, 0.010 * S, 0),
            behind,
            behind + Vector3(0, 0.028 * S, Float32(-0.004) * S),
            0.00070 * S,
        )
    )


def _line(a: Vector3, b: Vector3, radius: Float32) -> TubeChain:
    """Return five stations on a straight vessel."""
    return TubeChain(
        a,
        mix_point(a, b, 0.25),
        mix_point(a, b, 0.50),
        mix_point(a, b, 0.75),
        b,
        radius,
        radius,
        radius,
        radius,
        radius,
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
        radius,
        radius,
    )
