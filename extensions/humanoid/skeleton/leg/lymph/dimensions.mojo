# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named lymph nodes and trunks of one leg, as implicit solids.

The labeled set is the inguinal nodes, the popliteal nodes, a
superficial trunk beside the great saphenous vein, and a deep trunk
beside the femoral artery. Paths and radii are authored from stature.
They are template parameters.

The solids live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = muscle_dimensions(person)
    var d = lymph_distance(dims, INGUINAL_NODES, Vector3(0, 0.3, 0.02))
"""

from extensions.humanoid.side import LEFT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    empty_bounds,
    field_gradient,
    sd_sphere,
    smin,
    tapered_tube,
    tube_chain_bounds,
    tube_chain_distance,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleDimensions
from math.vector3 import Vector3


@fieldwise_init
struct LymphPart(Equatable, ImplicitlyCopyable, Writable):
    """Which named lymph solid a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary that
    reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named lymph solid."""
        if self.value < 0:
            return False
        return self.value <= DEEP_LYMPHATICS.value


comptime INGUINAL_NODES = LymphPart(0)
comptime POPLITEAL_NODES = LymphPart(1)
comptime SUPERFICIAL_LYMPHATICS = LymphPart(2)
comptime DEEP_LYMPHATICS = LymphPart(3)


struct LymphField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one `LymphPart`."""

    var nodes: Bool
    var chain: TubeChain
    var c0: Vector3
    var c1: Vector3
    var c2: Vector3
    var n0: Float32
    var n1: Float32
    var n2: Float32
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: MuscleDimensions, part: LymphPart
    ) raises:
        """Build one lymph solid from muscle landmarks.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named lymph solid.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `part`
                is not named.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A lymph part must be a named node group or trunk")
        var S = dimensions.stature.value
        var lat = Float32(1)
        if dimensions.side == LEFT:
            lat = Float32(-1)
        self.k = 0.003 * S
        self.epsilon = dimensions.epsilon
        self.chain = tapered_tube(
            dimensions.hip,
            dimensions.plafond,
            Vector3(0, 0, 0),
            0.001 * S,
            0.001 * S,
        )
        self.c0 = dimensions.hip
        self.c1 = dimensions.hip
        self.c2 = dimensions.hip
        self.n0 = 0.001 * S
        self.n1 = 0.001 * S
        self.n2 = 0.001 * S
        self.nodes = False
        if part == INGUINAL_NODES:
            self.nodes = True
            self.c0 = dimensions.hip + Vector3(
                -lat * 0.020 * S, -0.022 * S, 0.012 * S
            )
            self.c1 = dimensions.hip + Vector3(
                -lat * 0.028 * S, -0.030 * S, 0.008 * S
            )
            self.c2 = dimensions.hip + Vector3(
                -lat * 0.016 * S, -0.036 * S, 0.016 * S
            )
            self.n0 = 0.0070 * S
            self.n1 = 0.0058 * S
            self.n2 = 0.0050 * S
        elif part == POPLITEAL_NODES:
            self.nodes = True
            self.c0 = dimensions.med_condyle + Vector3(
                0, -0.006 * S, -0.028 * S
            )
            self.c1 = dimensions.lat_condyle + Vector3(
                0, -0.010 * S, -0.026 * S
            )
            self.c2 = dimensions.med_condyle + Vector3(
                0, -0.018 * S, -0.024 * S
            )
            self.n0 = 0.0054 * S
            self.n1 = 0.0048 * S
            self.n2 = 0.0042 * S
        elif part == SUPERFICIAL_LYMPHATICS:
            var origin = dimensions.med_mal + Vector3(
                -lat * 0.012 * S, 0.010 * S, 0.008 * S
            )
            var insertion = dimensions.hip + Vector3(
                -lat * 0.026 * S, -0.030 * S, 0.014 * S
            )
            self.chain = tapered_tube(
                origin,
                insertion,
                Vector3(-lat * 0.032 * S, 0, 0.012 * S),
                0.0022 * S,
                0.0032 * S,
            )
        else:
            var origin = dimensions.hip + Vector3(
                -lat * 0.016 * S, -0.018 * S, 0.012 * S
            )
            var insertion = dimensions.tib_med + Vector3(
                0, -0.028 * S, -0.020 * S
            )
            self.chain = tapered_tube(
                origin,
                insertion,
                Vector3(-lat * 0.018 * S, 0, -0.008 * S),
                0.0022 * S,
                0.0034 * S,
            )
        if self.nodes:
            var box = empty_bounds()
            box.include_sphere(self.c0, self.n0)
            box.include_sphere(self.c1, self.n1)
            box.include_sphere(self.c2, self.n2)
            var padded = box.padded(0.008 + self.n0)
            self.low = padded.low
            self.high = padded.high
        else:
            var tube = tube_chain_bounds(self.chain, 0.008 + self.chain.r2)
            self.low = tube.low
            self.high = tube.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the solid, in meters.

        Negative is inside. Zero is the surface.
        """
        if self.nodes:
            var d = sd_sphere(point, self.c0, self.n0)
            d = smin(d, sd_sphere(point, self.c1, self.n1), self.k)
            return smin(d, sd_sphere(point, self.c2, self.n2), self.k)
        return tube_chain_distance(self.chain, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def lymph_distance(
    dimensions: MuscleDimensions, part: LymphPart, point: Vector3
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
    return LymphField(dimensions, part).distance(point)


def lymph_part_label(part: LymphPart) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A lymph part.

    Returns:
        A short English name, or `"lymph"` when `part` is not named.
    """
    if part == INGUINAL_NODES:
        return "inguinal nodes"
    if part == POPLITEAL_NODES:
        return "popliteal nodes"
    if part == SUPERFICIAL_LYMPHATICS:
        return "superficial lymphatics"
    if part == DEEP_LYMPHATICS:
        return "deep lymphatics"
    return "lymph"


def is_node_group(part: LymphPart) raises -> Bool:
    """Return True if `part` is a node cluster rather than a trunk.

    Args:
        part: A named lymph solid.

    Returns:
        True for the inguinal and popliteal node groups.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A lymph part must be a named node group or trunk")
    if part == INGUINAL_NODES:
        return True
    return part == POPLITEAL_NODES


def named_lymph_parts() -> List[LymphPart]:
    """Return every named lymph solid in a stable order.

    Returns:
        Two node groups and two trunks.
    """
    var parts = List[LymphPart]()
    parts.append(INGUINAL_NODES)
    parts.append(POPLITEAL_NODES)
    parts.append(SUPERFICIAL_LYMPHATICS)
    parts.append(DEEP_LYMPHATICS)
    return parts^
