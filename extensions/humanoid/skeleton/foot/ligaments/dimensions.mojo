# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named ligaments of one ankle and foot, as implicit solids.

The set is the lateral collateral trio, the deltoid, the spring
ligament, the long and short plantar ligaments, the bifurcate
ligament, the talocalcaneal interosseous ligament and the Lisfranc
ligament. Radii are authored round sections of stature. They are not
a cited width table. A flat band is drawn as a round section.

The solids live in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_dimensions(Length(6.0, FOOT), MALE)
    var d = ligament_distance(dims, ANTERIOR_TALOFIBULAR, dims.talar_head)
"""

from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    mix_point,
)
from extensions.humanoid.skeleton.foot.bones.dimensions import FootDimensions
from extensions.humanoid.skeleton.foot.chain import (
    SegmentSet,
    one_segment,
    segment_bounds,
    segment_distance,
    three_segments,
    two_segments,
)
from math.vector3 import Vector3


@fieldwise_init
struct FootLigament(Equatable, ImplicitlyCopyable, Writable):
    """Which named ankle or foot ligament a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named ligaments is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named ligament."""
        if self.value < 0:
            return False
        return self.value <= LISFRANC.value


comptime ANTERIOR_TALOFIBULAR = FootLigament(0)
comptime CALCANEOFIBULAR = FootLigament(1)
comptime POSTERIOR_TALOFIBULAR = FootLigament(2)
comptime DELTOID = FootLigament(3)
comptime SPRING_LIGAMENT = FootLigament(4)
comptime LONG_PLANTAR = FootLigament(5)
comptime SHORT_PLANTAR = FootLigament(6)
comptime BIFURCATE = FootLigament(7)
comptime TALOCALCANEAL_INTEROSSEOUS = FootLigament(8)
comptime LISFRANC = FootLigament(9)


struct FootLigamentField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one named ligament."""

    var segments: SegmentSet
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: FootDimensions, part: FootLigament
    ) raises:
        """Build one ligament from landmarks that `validate` accepts.

        Args:
            dimensions: Foot landmarks.
            part: A named ligament.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A foot ligament must be a named ligament")
        self.segments = _segments(dimensions, part)
        var S = dimensions.stature.value
        self.k = 0.0008 * S
        self.epsilon = 0.0004 * S
        var box = segment_bounds(self.segments, 0.003 + 0.002 * S)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the ligament, in meters.

        Negative is inside. Zero is the surface.
        """
        return segment_distance(self.segments, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def ligament_distance(
    dimensions: FootDimensions, part: FootLigament, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which ligament to sample.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return FootLigamentField(dimensions, part).distance(point)


def ligament_part_label(part: FootLigament) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A ligament, named or not.

    Returns:
        A short American English label, or `"ligament"` when `part`
        is not named.
    """
    if part == ANTERIOR_TALOFIBULAR:
        return "anterior talofibular ligament"
    if part == CALCANEOFIBULAR:
        return "calcaneofibular ligament"
    if part == POSTERIOR_TALOFIBULAR:
        return "posterior talofibular ligament"
    if part == DELTOID:
        return "deltoid ligament"
    if part == SPRING_LIGAMENT:
        return "spring ligament"
    if part == LONG_PLANTAR:
        return "long plantar ligament"
    if part == SHORT_PLANTAR:
        return "short plantar ligament"
    if part == BIFURCATE:
        return "bifurcate ligament"
    if part == TALOCALCANEAL_INTEROSSEOUS:
        return "talocalcaneal interosseous ligament"
    if part == LISFRANC:
        return "Lisfranc ligament"
    return "ligament"


def named_foot_ligaments() -> List[FootLigament]:
    """Return every named foot ligament in a stable order.

    Returns:
        The lateral trio, the deltoid, and the plantar and midfoot bands.
    """
    var parts = List[FootLigament]()
    parts.append(ANTERIOR_TALOFIBULAR)
    parts.append(CALCANEOFIBULAR)
    parts.append(POSTERIOR_TALOFIBULAR)
    parts.append(DELTOID)
    parts.append(SPRING_LIGAMENT)
    parts.append(LONG_PLANTAR)
    parts.append(SHORT_PLANTAR)
    parts.append(BIFURCATE)
    parts.append(TALOCALCANEAL_INTEROSSEOUS)
    parts.append(LISFRANC)
    return parts^


def _segments(dimensions: FootDimensions, part: FootLigament) -> SegmentSet:
    """Return the bands of one named ligament."""
    var S = dimensions.stature.value
    var plantar = Vector3(0, Float32(-0.005) * S, 0)
    var neck = mix_point(dimensions.talar_body, dimensions.talar_head, 0.65)
    if part == ANTERIOR_TALOFIBULAR:
        return one_segment(
            dimensions.lateral_malleolus, neck, 0.0017 * S, 0.0015 * S
        )
    if part == CALCANEOFIBULAR:
        return one_segment(
            dimensions.lateral_malleolus,
            dimensions.calcaneal_lateral,
            0.0016 * S,
            0.0014 * S,
        )
    if part == POSTERIOR_TALOFIBULAR:
        return one_segment(
            dimensions.lateral_malleolus,
            dimensions.talar_posterior,
            0.0018 * S,
            0.0016 * S,
        )
    if part == DELTOID:
        return three_segments(
            dimensions.medial_malleolus,
            dimensions.navicular_tuberosity,
            0.0020 * S,
            0.0016 * S,
            dimensions.medial_malleolus,
            dimensions.sustentaculum,
            0.0022 * S,
            0.0018 * S,
            dimensions.medial_malleolus,
            dimensions.talar_body,
            0.0018 * S,
            0.0016 * S,
        )
    if part == SPRING_LIGAMENT:
        return one_segment(
            dimensions.sustentaculum + plantar,
            dimensions.navicular + plantar,
            0.0018 * S,
            0.0016 * S,
        )
    if part == LONG_PLANTAR:
        return two_segments(
            dimensions.heel + plantar,
            dimensions.cuboid + plantar,
            0.0024 * S,
            0.0020 * S,
            dimensions.cuboid + plantar,
            dimensions.mt3_base + plantar,
            0.0018 * S,
            0.0014 * S,
        )
    if part == SHORT_PLANTAR:
        return one_segment(
            dimensions.calcaneal_anterior + plantar,
            dimensions.cuboid + plantar,
            0.0017 * S,
            0.0015 * S,
        )
    if part == BIFURCATE:
        return two_segments(
            dimensions.calcaneal_anterior,
            dimensions.navicular,
            0.0013 * S,
            0.0011 * S,
            dimensions.calcaneal_anterior,
            dimensions.cuboid,
            0.0013 * S,
            0.0011 * S,
        )
    if part == TALOCALCANEAL_INTEROSSEOUS:
        return one_segment(
            dimensions.talar_body,
            dimensions.sustentaculum,
            0.0016 * S,
            0.0014 * S,
        )
    return two_segments(
        dimensions.medial_cuneiform,
        dimensions.mt2_base,
        0.0015 * S,
        0.0013 * S,
        dimensions.lateral_cuneiform,
        dimensions.mt3_base,
        0.0013 * S,
        0.0011 * S,
    )
