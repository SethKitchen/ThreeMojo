# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Lymphatic trunks of one foot, as implicit tubes.

The foot drains through dorsal and plantar collectors and through
medial and lateral trunks that follow the saphenous veins. Named nodes
stay in the leg, at the popliteal fossa and the inguinal region. Trunk
radii are an authored stature ratio. They are not a cited caliber table.

Physical radii drive distance and mass. Geometry applies a separate
diagrammatic minimum radius. Display radius does not change mass.

The solids live in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_dimensions(Length(6.0, FOOT), MALE)
    var d = lymph_distance(dims, DORSAL_LYMPHATICS, dims.mt2_head)
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
struct FootLymph(Equatable, ImplicitlyCopyable, Writable):
    """Which named lymphatic trunk of the foot a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named trunks is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named lymphatic trunk."""
        if self.value < 0:
            return False
        return self.value <= LATERAL_COLLECTORS.value


comptime DORSAL_LYMPHATICS = FootLymph(0)
comptime PLANTAR_LYMPHATICS = FootLymph(1)
comptime MEDIAL_COLLECTORS = FootLymph(2)
comptime LATERAL_COLLECTORS = FootLymph(3)


struct FootLymphField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one lymphatic trunk."""

    var tubes: TubeSet
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FootDimensions, part: FootLymph) raises:
        """Build one trunk from landmarks that `validate` accepts.

        Args:
            dimensions: Foot landmarks.
            part: A named trunk.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A foot lymph part must be a named trunk")
        self.tubes = _tubes(dimensions, part)
        var S = dimensions.stature.value
        self.k = 0.00025 * S
        self.epsilon = 0.00015 * S
        var box = tube_set_bounds(self.tubes, 0.003)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the trunk, in meters.

        Negative is inside. Zero is the surface.
        """
        return tube_set_distance(self.tubes, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def display_lymph_field(
    dimensions: FootDimensions, part: FootLymph
) raises -> FootLymphField:
    """Return a trunk with a diagrammatic minimum mesh radius.

    Args:
        dimensions: Foot landmarks.
        part: A named trunk.

    Returns:
        The same centerline with radii held up for meshing.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    var field = FootLymphField(dimensions, part)
    var least = 0.0014 * dimensions.stature.value
    field.tubes = enlarge_tube_set(field.tubes, least)
    field.k = 0.0007 * dimensions.stature.value
    var box = tube_set_bounds(field.tubes, 0.004)
    field.low = box.low
    field.high = box.high
    return field


def lymph_distance(
    dimensions: FootDimensions, part: FootLymph, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which trunk to sample.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return FootLymphField(dimensions, part).distance(point)


def lymph_part_label(part: FootLymph) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A lymphatic trunk, named or not.

    Returns:
        A short American English label, or `"foot lymph"` when `part`
        is not named.
    """
    if part == DORSAL_LYMPHATICS:
        return "dorsal lymphatics"
    if part == PLANTAR_LYMPHATICS:
        return "plantar lymphatics"
    if part == MEDIAL_COLLECTORS:
        return "medial collectors"
    if part == LATERAL_COLLECTORS:
        return "lateral collectors"
    return "foot lymph"


def named_foot_lymph() -> List[FootLymph]:
    """Return every named foot lymphatic trunk.

    Returns:
        Dorsal, plantar, medial and lateral collectors.
    """
    var parts = List[FootLymph]()
    parts.append(DORSAL_LYMPHATICS)
    parts.append(PLANTAR_LYMPHATICS)
    parts.append(MEDIAL_COLLECTORS)
    parts.append(LATERAL_COLLECTORS)
    return parts^


def _tubes(dimensions: FootDimensions, part: FootLymph) -> TubeSet:
    """Return the physical centerline of one trunk."""
    var S = dimensions.stature.value
    var radius = 0.00022 * S
    var med = medial_axis(dimensions)
    var lateral = med * Float32(-1)
    if part == DORSAL_LYMPHATICS:
        return one_tube(
            _line(
                dimensions.mt5_head + Vector3(0, 0.011 * S, 0),
                dimensions.mt1_head + Vector3(0, 0.011 * S, 0),
                radius,
            )
        )
    if part == PLANTAR_LYMPHATICS:
        return one_tube(
            _line(
                dimensions.heel + Vector3(0, Float32(-0.008) * S, 0.012 * S),
                dimensions.mt3_head + Vector3(0, Float32(-0.006) * S, 0),
                radius,
            )
        )
    if part == MEDIAL_COLLECTORS:
        var front = (
            dimensions.medial_malleolus
            + med * (0.005 * S)
            + Vector3(0, 0.006 * S, 0.008 * S)
        )
        return one_tube(
            _via(
                dimensions.navicular_tuberosity + Vector3(0, 0.006 * S, 0),
                front,
                front + Vector3(0, 0.028 * S, 0.002 * S),
                radius,
            )
        )
    var behind = (
        dimensions.lateral_malleolus
        + lateral * (0.004 * S)
        + Vector3(0, 0.004 * S, Float32(-0.006) * S)
    )
    return one_tube(
        _via(
            dimensions.mt5_head + Vector3(0, 0.008 * S, 0),
            behind,
            behind + Vector3(0, 0.026 * S, Float32(-0.002) * S),
            radius,
        )
    )


def _line(a: Vector3, b: Vector3, radius: Float32) -> TubeChain:
    """Return five stations on a straight trunk."""
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
