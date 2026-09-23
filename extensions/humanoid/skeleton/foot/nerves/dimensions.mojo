# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named nerves of one foot, as implicit tubes.

The set is the tibial nerve in the tarsal tunnel, the medial and
lateral plantar nerves, the deep and superficial fibular nerves, and
the sural and saphenous nerves. `FIBULAR` is the canonical name.
`PERONEAL` is an alias. Radii are authored stature ratios. They are
not a cited caliber table.

Physical radii drive distance and mass. Geometry applies a separate
diagrammatic minimum radius. Display radius does not change mass.

The solids live in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_dimensions(Length(6.0, FOOT), MALE)
    var d = nerve_distance(dims, MEDIAL_PLANTAR_NERVE, dims.navicular)
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
    two_tubes,
)
from math.vector3 import Vector3


@fieldwise_init
struct FootNerve(Equatable, ImplicitlyCopyable, Writable):
    """Which named nerve of the foot a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named nerves is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named foot nerve."""
        if self.value < 0:
            return False
        return self.value <= SAPHENOUS_NERVE.value


comptime TIBIAL_NERVE = FootNerve(0)
comptime MEDIAL_PLANTAR_NERVE = FootNerve(1)
comptime LATERAL_PLANTAR_NERVE = FootNerve(2)
comptime DEEP_FIBULAR_NERVE = FootNerve(3)
comptime SUPERFICIAL_FIBULAR_NERVE = FootNerve(4)
comptime SURAL_NERVE = FootNerve(5)
comptime SAPHENOUS_NERVE = FootNerve(6)
# Compatibility names for the fibular nerves.
comptime DEEP_PERONEAL_NERVE = DEEP_FIBULAR_NERVE
comptime SUPERFICIAL_PERONEAL_NERVE = SUPERFICIAL_FIBULAR_NERVE


struct FootNerveField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one named foot nerve."""

    var tubes: TubeSet
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FootDimensions, part: FootNerve) raises:
        """Build one nerve from landmarks that `validate` accepts.

        Args:
            dimensions: Foot landmarks.
            part: A named nerve.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A foot nerve must be a named nerve")
        self.tubes = _tubes(dimensions, part)
        var S = dimensions.stature.value
        self.k = 0.00030 * S
        self.epsilon = 0.00018 * S
        var box = tube_set_bounds(self.tubes, 0.003)
        self.low = box.low
        self.high = box.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the nerve, in meters.

        Negative is inside. Zero is the surface.
        """
        return tube_set_distance(self.tubes, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def display_nerve_field(
    dimensions: FootDimensions, part: FootNerve
) raises -> FootNerveField:
    """Return a nerve with a diagrammatic minimum mesh radius.

    Args:
        dimensions: Foot landmarks.
        part: A named nerve.

    Returns:
        The same centerline with radii held up for meshing.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    var field = FootNerveField(dimensions, part)
    var least = 0.0015 * dimensions.stature.value
    field.tubes = enlarge_tube_set(field.tubes, least)
    field.k = 0.0008 * dimensions.stature.value
    var box = tube_set_bounds(field.tubes, 0.004)
    field.low = box.low
    field.high = box.high
    return field


def nerve_distance(
    dimensions: FootDimensions, part: FootNerve, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which nerve to sample.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return FootNerveField(dimensions, part).distance(point)


def nerve_part_label(part: FootNerve) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A nerve, named or not.

    Returns:
        A short American English label, or `"foot nerve"` when `part`
        is not named.
    """
    if part == TIBIAL_NERVE:
        return "tibial nerve"
    if part == MEDIAL_PLANTAR_NERVE:
        return "medial plantar nerve"
    if part == LATERAL_PLANTAR_NERVE:
        return "lateral plantar nerve"
    if part == DEEP_FIBULAR_NERVE:
        return "deep fibular nerve"
    if part == SUPERFICIAL_FIBULAR_NERVE:
        return "superficial fibular nerve"
    if part == SURAL_NERVE:
        return "sural nerve"
    if part == SAPHENOUS_NERVE:
        return "saphenous nerve"
    return "foot nerve"


def named_foot_nerves() -> List[FootNerve]:
    """Return every named foot nerve in a stable order.

    Returns:
        Tibial, plantar, fibular, sural and saphenous nerves.
    """
    var parts = List[FootNerve]()
    parts.append(TIBIAL_NERVE)
    parts.append(MEDIAL_PLANTAR_NERVE)
    parts.append(LATERAL_PLANTAR_NERVE)
    parts.append(DEEP_FIBULAR_NERVE)
    parts.append(SUPERFICIAL_FIBULAR_NERVE)
    parts.append(SURAL_NERVE)
    parts.append(SAPHENOUS_NERVE)
    return parts^


def _tubes(dimensions: FootDimensions, part: FootNerve) -> TubeSet:
    """Return the physical centerline of one nerve."""
    var S = dimensions.stature.value
    var med = medial_axis(dimensions)
    var lateral = med * Float32(-1)
    if part == TIBIAL_NERVE:
        return one_tube(
            _line(
                dimensions.medial_malleolus
                + Vector3(0, 0.018 * S, Float32(-0.010) * S),
                dimensions.medial_malleolus
                + Vector3(0, Float32(-0.012) * S, Float32(-0.006) * S),
                0.00105 * S,
            )
        )
    if part == MEDIAL_PLANTAR_NERVE:
        return one_tube(
            _via(
                dimensions.medial_malleolus
                + Vector3(0, Float32(-0.012) * S, Float32(-0.006) * S),
                dimensions.navicular + Vector3(0, Float32(-0.007) * S, 0),
                dimensions.mt1_head + Vector3(0, Float32(-0.003) * S, 0),
                0.00070 * S,
            )
        )
    if part == LATERAL_PLANTAR_NERVE:
        return one_tube(
            _via(
                dimensions.medial_malleolus
                + Vector3(0, Float32(-0.012) * S, Float32(-0.006) * S),
                dimensions.cuboid + Vector3(0, Float32(-0.007) * S, 0),
                dimensions.mt5_base + Vector3(0, Float32(-0.003) * S, 0),
                0.00065 * S,
            )
        )
    if part == DEEP_FIBULAR_NERVE:
        return one_tube(
            _via(
                Vector3(0, 0, 0.014 * S) + lateral * (0.003 * S),
                dimensions.intermediate_cuneiform + Vector3(0, 0.007 * S, 0),
                mix_point(dimensions.mt1_head, dimensions.mt2_head, 0.5)
                + Vector3(0, 0.007 * S, 0),
                0.00055 * S,
            )
        )
    if part == SUPERFICIAL_FIBULAR_NERVE:
        var start = Vector3(0, 0.006 * S, 0.020 * S) + lateral * (0.012 * S)
        var radius = 0.00050 * S
        return two_tubes(
            _via(
                start,
                dimensions.mt2_head + Vector3(0, 0.010 * S, 0),
                dimensions.toe2_pip + Vector3(0, 0.006 * S, 0),
                radius,
            ),
            _via(
                start,
                dimensions.mt4_head + Vector3(0, 0.009 * S, 0),
                dimensions.toe4_pip + Vector3(0, 0.005 * S, 0),
                radius,
            ),
        )
    if part == SURAL_NERVE:
        var behind = dimensions.lateral_malleolus + Vector3(
            0, 0.004 * S, Float32(-0.008) * S
        )
        return one_tube(
            _via(
                behind + Vector3(0, 0.020 * S, 0),
                behind,
                dimensions.toe5_pip + Vector3(0, 0.006 * S, 0),
                0.00048 * S,
            )
        )
    var front = (
        dimensions.medial_malleolus
        + med * (0.006 * S)
        + Vector3(0, 0.006 * S, 0.008 * S)
    )
    return one_tube(
        _via(
            front + Vector3(0, 0.024 * S, 0),
            front,
            dimensions.medial_cuneiform + Vector3(0, 0.006 * S, 0),
            0.00045 * S,
        )
    )


def _line(a: Vector3, b: Vector3, radius: Float32) -> TubeChain:
    """Return five stations on a straight nerve."""
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
