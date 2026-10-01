# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named lymph nodes and trunks of one leg, as implicit solids.

The superficial field has a medial route to inguinal nodes and a
posterolateral route to popliteal nodes. Three deep crural routes
converge on popliteal nodes. One efferent reaches a deep inguinal node.
Physical collector radii drive distance and mass. Geometry enlarges
them only for display.

The solids live in the leg frame. The origin is the tibiofemoral joint
line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = muscle_dimensions(person)
    var d = lymph_distance(dims, INGUINAL_NODES, Vector3(0, 0.3, 0.02))
"""

from extensions.humanoid.side import LEFT
from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    TubeChain,
    empty_bounds,
    field_gradient,
    mix_point,
    sd_sphere,
    smin,
    tube_chain_bounds,
    tube_chain_distance,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleDimensions
from math.vector3 import Vector3
from std.math import max


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
    var two_chains: Bool
    var chain_count: Int
    var chain: TubeChain
    var chain2: TubeChain
    var chain3: TubeChain
    var chain4: TubeChain
    var c0: Vector3
    var c1: Vector3
    var c2: Vector3
    var c3: Vector3
    var c4: Vector3
    var n0: Float32
    var n1: Float32
    var n2: Float32
    var n3: Float32
    var n4: Float32
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
        self.k = Float32(0.00010)
        self.epsilon = Float32(0.00008)
        var dummy = TubeChain(
            dimensions.hip,
            dimensions.hip,
            dimensions.hip,
            dimensions.hip,
            dimensions.hip,
            0.00030,
            0.00030,
            0.00030,
            0.00030,
            0.00030,
        )
        self.chain = dummy
        self.chain2 = dummy
        self.chain3 = dummy
        self.chain4 = dummy
        self.c0 = dimensions.hip
        self.c1 = dimensions.hip
        self.c2 = dimensions.hip
        self.c3 = dimensions.hip
        self.c4 = dimensions.hip
        self.n0 = 0.001 * S
        self.n1 = 0.001 * S
        self.n2 = 0.001 * S
        self.n3 = 0.001 * S
        self.n4 = 0.001 * S
        self.nodes = False
        self.two_chains = False
        self.chain_count = 1
        if part == INGUINAL_NODES:
            self.nodes = True
            self.chain_count = 0
            self.c0 = dimensions.hip + Vector3(
                -lat * 0.018 * S, -0.028 * S, 0.014 * S
            )
            self.c1 = dimensions.hip + Vector3(
                -lat * 0.030 * S, -0.034 * S, 0.010 * S
            )
            self.c2 = dimensions.hip + Vector3(
                -lat * 0.010 * S, -0.038 * S, 0.018 * S
            )
            self.c3 = dimensions.hip + Vector3(
                -lat * 0.038 * S, -0.026 * S, 0.006 * S
            )
            self.c4 = dimensions.hip + Vector3(
                -lat * 0.034 * S, -0.046 * S, 0.008 * S
            )
            self.n0 = 0.0035 * S
            self.n1 = 0.0030 * S
            self.n2 = 0.0027 * S
            self.n3 = 0.0025 * S
            self.n4 = 0.0023 * S
        elif part == POPLITEAL_NODES:
            self.nodes = True
            self.chain_count = 0
            var knee = mix_point(
                dimensions.med_condyle, dimensions.lat_condyle, 0.50
            )
            self.c0 = knee + Vector3(0, 0.014 * S, -0.034 * S)
            self.c1 = knee + Vector3(lat * 0.008 * S, 0.004 * S, -0.032 * S)
            self.c2 = knee + Vector3(-lat * 0.008 * S, -0.004 * S, -0.032 * S)
            self.c3 = knee + Vector3(lat * 0.005 * S, -0.014 * S, -0.030 * S)
            self.c4 = knee + Vector3(-lat * 0.005 * S, -0.022 * S, -0.028 * S)
            self.n0 = 0.0028 * S
            self.n1 = 0.0025 * S
            self.n2 = 0.0024 * S
            self.n3 = 0.0022 * S
            self.n4 = 0.0020 * S
        elif part == SUPERFICIAL_LYMPHATICS:
            self.two_chains = True
            self.chain_count = 2
            self.chain = TubeChain(
                dimensions.med_mal + Vector3(-lat * 0.006 * S, 0, 0.014 * S),
                mix_point(dimensions.med_mal, dimensions.tibia_mid, 0.58)
                + Vector3(-lat * 0.014 * S, 0, 0.010 * S),
                dimensions.med_condyle
                + Vector3(-lat * 0.020 * S, 0, -0.004 * S),
                mix_point(dimensions.med_condyle, dimensions.hip, 0.62)
                + Vector3(-lat * 0.028 * S, 0, 0.012 * S),
                dimensions.hip
                + Vector3(-lat * 0.018 * S, -0.028 * S, 0.014 * S),
                0.00030,
                0.00032,
                0.00035,
                0.00040,
                0.00045,
            )
            var knee = mix_point(
                dimensions.med_condyle, dimensions.lat_condyle, 0.50
            )
            self.chain2 = TubeChain(
                dimensions.lat_mal + Vector3(lat * 0.010 * S, 0, -0.004 * S),
                mix_point(dimensions.lat_mal, dimensions.tibia_mid, 0.45)
                + Vector3(lat * 0.010 * S, 0, -0.014 * S),
                dimensions.tibia_mid + Vector3(lat * 0.006 * S, 0, -0.014 * S),
                mix_point(dimensions.tibia_mid, knee, 0.72)
                + Vector3(lat * 0.006 * S, 0, -0.018 * S),
                knee + Vector3(0, 0.014 * S, -0.034 * S),
                0.00025,
                0.00028,
                0.00030,
                0.00035,
                0.00040,
            )
        else:
            self.two_chains = True
            self.chain_count = 4
            var knee = mix_point(
                dimensions.med_condyle, dimensions.lat_condyle, 0.50
            )
            var popliteal_lateral = knee + Vector3(
                lat * 0.005 * S, -0.014 * S, -0.030 * S
            )
            var popliteal_medial = knee + Vector3(
                -lat * 0.005 * S, -0.022 * S, -0.028 * S
            )
            var deep_inguinal = dimensions.hip + Vector3(
                -lat * 0.034 * S, -0.046 * S, 0.008 * S
            )
            self.chain = TubeChain(
                dimensions.plafond + Vector3(0, 0.018 * S, 0.008 * S),
                dimensions.tibia_mid + Vector3(0, 0, 0.012 * S),
                dimensions.tib_lat + Vector3(0, -0.035 * S, 0.004 * S),
                knee + Vector3(lat * 0.004 * S, -0.020 * S, -0.026 * S),
                popliteal_lateral,
                0.00025,
                0.00028,
                0.00030,
                0.00035,
                0.00040,
            )
            self.chain2 = TubeChain(
                dimensions.med_mal + Vector3(0, 0.010 * S, -0.006 * S),
                dimensions.tibia_mid + Vector3(-lat * 0.004 * S, 0, -0.014 * S),
                dimensions.tib_med + Vector3(0, -0.030 * S, -0.018 * S),
                knee + Vector3(-lat * 0.004 * S, -0.020 * S, -0.026 * S),
                popliteal_medial,
                0.00028,
                0.00030,
                0.00034,
                0.00038,
                0.00042,
            )
            self.chain3 = TubeChain(
                dimensions.lat_mal + Vector3(0, 0.012 * S, -0.006 * S),
                dimensions.fibula_mid
                + Vector3(-lat * 0.002 * S, 0, -0.010 * S),
                dimensions.fib_head + Vector3(0, -0.030 * S, -0.010 * S),
                knee + Vector3(lat * 0.006 * S, -0.018 * S, -0.026 * S),
                popliteal_lateral,
                0.00025,
                0.00028,
                0.00030,
                0.00034,
                0.00040,
            )
            self.chain4 = TubeChain(
                popliteal_medial,
                knee + Vector3(-lat * 0.006 * S, 0.030 * S, -0.026 * S),
                dimensions.femur_mid + Vector3(-lat * 0.022 * S, 0, 0.004 * S),
                mix_point(dimensions.femur_mid, dimensions.hip, 0.70)
                + Vector3(-lat * 0.028 * S, 0, 0.010 * S),
                deep_inguinal,
                0.00040,
                0.00042,
                0.00045,
                0.00048,
                0.00050,
            )
        if self.nodes:
            var box = empty_bounds()
            box.include_sphere(self.c0, self.n0)
            box.include_sphere(self.c1, self.n1)
            box.include_sphere(self.c2, self.n2)
            box.include_sphere(self.c3, self.n3)
            box.include_sphere(self.c4, self.n4)
            var padded = box.padded(0.008 + self.n0)
            self.low = padded.low
            self.high = padded.high
        else:
            var tube = tube_chain_bounds(self.chain, Float32(0.003))
            tube.include_sphere(self.chain2.p0, self.chain2.r0)
            tube.include_sphere(self.chain2.p1, self.chain2.r1)
            tube.include_sphere(self.chain2.p2, self.chain2.r2)
            tube.include_sphere(self.chain2.p3, self.chain2.r3)
            tube.include_sphere(self.chain2.p4, self.chain2.r4)
            if self.chain_count >= 3:
                tube.include_sphere(self.chain3.p0, self.chain3.r0)
                tube.include_sphere(self.chain3.p1, self.chain3.r1)
                tube.include_sphere(self.chain3.p2, self.chain3.r2)
                tube.include_sphere(self.chain3.p3, self.chain3.r3)
                tube.include_sphere(self.chain3.p4, self.chain3.r4)
            if self.chain_count >= 4:
                tube.include_sphere(self.chain4.p0, self.chain4.r0)
                tube.include_sphere(self.chain4.p1, self.chain4.r1)
                tube.include_sphere(self.chain4.p2, self.chain4.r2)
                tube.include_sphere(self.chain4.p3, self.chain4.r3)
                tube.include_sphere(self.chain4.p4, self.chain4.r4)
            self.low = tube.low
            self.high = tube.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the solid, in meters.

        Negative is inside. Zero is the surface.
        """
        if self.nodes:
            var d = sd_sphere(point, self.c0, self.n0)
            d = smin(d, sd_sphere(point, self.c1, self.n1), self.k)
            d = smin(d, sd_sphere(point, self.c2, self.n2), self.k)
            d = smin(d, sd_sphere(point, self.c3, self.n3), self.k)
            return smin(d, sd_sphere(point, self.c4, self.n4), self.k)
        var d = tube_chain_distance(self.chain, point, self.k)
        d = smin(d, tube_chain_distance(self.chain2, point, self.k), self.k)
        if self.chain_count >= 3:
            d = smin(d, tube_chain_distance(self.chain3, point, self.k), self.k)
        if self.chain_count >= 4:
            d = smin(d, tube_chain_distance(self.chain4, point, self.k), self.k)
        return d

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


def _display_lymph_field(
    dimensions: MuscleDimensions, part: LymphPart
) raises -> LymphField:
    """Return lymph anatomy with diagrammatic collector radii."""
    var field = LymphField(dimensions, part)
    if not field.nodes:
        var least = 0.0018 * dimensions.stature.value
        field.chain = _display_chain(field.chain, least)
        field.chain2 = _display_chain(field.chain2, least)
        if field.chain_count >= 3:
            field.chain3 = _display_chain(field.chain3, least)
        if field.chain_count >= 4:
            field.chain4 = _display_chain(field.chain4, least)
        field.k = 0.0006 * dimensions.stature.value
        field.epsilon = Float32(0.25) * least
        var box = tube_chain_bounds(field.chain, 0.008 + least)
        _include_chain_bounds(box, field.chain2)
        if field.chain_count >= 3:
            _include_chain_bounds(box, field.chain3)
        if field.chain_count >= 4:
            _include_chain_bounds(box, field.chain4)
        field.low = box.low
        field.high = box.high
    return field


def _display_chain(chain: TubeChain, least: Float32) -> TubeChain:
    """Return `chain` with every radius at least `least`."""
    var out = chain
    out.r0 = max(out.r0, least)
    out.r1 = max(out.r1, least)
    out.r2 = max(out.r2, least)
    out.r3 = max(out.r3, least)
    out.r4 = max(out.r4, least)
    return out


def _include_chain_bounds(mut box: Bounds, chain: TubeChain):
    """Grow `box` to hold `chain`."""
    box.include_sphere(chain.p0, chain.r0)
    box.include_sphere(chain.p1, chain.r1)
    box.include_sphere(chain.p2, chain.r2)
    box.include_sphere(chain.p3, chain.r3)
    box.include_sphere(chain.p4, chain.r4)


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
