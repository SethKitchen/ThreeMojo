# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named lymph node groups and the iliac lymphatic trunk of the pelvis.

Four node groups follow the vessels: the external iliac nodes, the
internal iliac nodes, the common iliac nodes and the sacral nodes. Five
representative nodes stand for each group. The iliac lymphatic trunk
runs from the leg's highest inguinal node along the iliac vessels to
the lumbar nodes beside the aorta. Radii are authored ratios of
stature. They are not a cited count or size table.

Every part is paired, authored on the right and mirrored on x for the
left.

    var dims = pelvis_muscle_dimensions(person)
    var d = pelvis_lymph_distance(dims, SACRAL_NODES, RIGHT, p)
"""

from extensions.humanoid.side import LEFT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    empty_bounds,
    field_gradient,
    flip_x,
    mix_point,
    sd_sphere,
    tube_chain_bounds,
    tube_chain_distance,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    pelvis_frame,
    sacral_back,
    sacral_front,
    sided_bounds,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
)
from extensions.humanoid.skeleton.pelvis.vessels.dimensions import (
    vessel_landmarks,
)
from math.vector3 import Vector3
from std.math import max, min, pi


@fieldwise_init
struct PelvisLymph(Equatable, ImplicitlyCopyable, Writable):
    """Which named pelvic node group or trunk a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named parts is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named node group or trunk."""
        if self.value < 0:
            return False
        return self.value <= ILIAC_LYMPHATICS.value


comptime EXTERNAL_ILIAC_NODES = PelvisLymph(0)
comptime INTERNAL_ILIAC_NODES = PelvisLymph(1)
comptime COMMON_ILIAC_NODES = PelvisLymph(2)
comptime SACRAL_NODES = PelvisLymph(3)
comptime ILIAC_LYMPHATICS = PelvisLymph(4)


struct PelvisLymphField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one pelvic node group or trunk."""

    var nodes: Bool
    var chain: TubeChain
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
    var mirror: Bool
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        dimensions: PelvisMuscleDimensions,
        part: PelvisLymph,
        side: BodySide,
    ) raises:
        """Build one lymph solid from landmarks that `validate` accepts.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named node group or trunk.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If `dimensions.validate` refuses the copy, if `part`
                is not named, or if `side` is not valid.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A pelvic lymph part must be a named group or trunk")
        if not side.is_valid():
            raise Error("A pelvis side must be RIGHT or LEFT")
        var p = dimensions.pelvis
        var f = pelvis_frame(p)
        var S = p.stature.value
        var at = vessel_landmarks(p)
        self.mirror = side == LEFT
        self.k = 0.0004 * S
        self.epsilon = 0.0003 * S
        self.nodes = part != ILIAC_LYMPHATICS
        self.chain = TubeChain(
            dimensions.inguinal,
            at.inguinal + f.template(-1.4, 0, 0),
            mix_point(at.division, at.inguinal, 0.45)
            + f.template(-1.1, 0, 0.4),
            at.division + f.template(-0.8, 0.4, 0.6),
            at.bifurcation + f.template(1.4, 1.5, -0.4),
            0.0006 * S,
            0.0006 * S,
            0.0006 * S,
            0.0006 * S,
            0.0006 * S,
        )
        var d = at.division
        if part == EXTERNAL_ILIAC_NODES:
            var beside = f.template(-0.9, 0, 0.3)
            self.c0 = mix_point(d, at.inguinal, 0.2) + beside
            self.c1 = mix_point(d, at.inguinal, 0.4) + beside
            self.c2 = mix_point(d, at.inguinal, 0.6) + beside
            self.c3 = mix_point(d, at.inguinal, 0.8) + beside
            self.c4 = at.inguinal + f.template(-1.6, -0.4, 0)
            self.n0 = 0.0030 * S
            self.n1 = 0.0028 * S
            self.n2 = 0.0030 * S
            self.n3 = 0.0027 * S
            self.n4 = 0.0032 * S
        elif part == INTERNAL_ILIAC_NODES:
            self.c0 = d + f.template(-0.3, -1.6, -1.8)
            self.c1 = d + f.template(0.1, -3.2, -3.6)
            self.c2 = d + f.template(1.6, -4.6, -3.2)
            self.c3 = d + f.template(1.7, -6.4, -2.6)
            self.c4 = d + f.template(0.2, -5.4, -4.6)
            self.n0 = 0.0027 * S
            self.n1 = 0.0025 * S
            self.n2 = 0.0026 * S
            self.n3 = 0.0024 * S
            self.n4 = 0.0023 * S
        elif part == COMMON_ILIAC_NODES:
            var beside = f.template(0.7, 0, -0.3)
            var b = at.bifurcation
            self.c0 = mix_point(b, d, 0.15) + beside
            self.c1 = mix_point(b, d, 0.35) + beside
            self.c2 = mix_point(b, d, 0.55) + beside
            self.c3 = mix_point(b, d, 0.75) + beside
            self.c4 = mix_point(b, d, 0.95) + beside
            self.n0 = 0.0028 * S
            self.n1 = 0.0027 * S
            self.n2 = 0.0028 * S
            self.n3 = 0.0026 * S
            self.n4 = 0.0027 * S
        else:
            # Sacral nodes: on the front of the sacrum, beside the
            # median sacral artery.
            var ahead = sacral_back(p) * (-0.0040 * S) + f.template(1.1, 0, 0)
            self.c0 = sacral_front(p, 0.15) + ahead
            self.c1 = sacral_front(p, 0.30) + ahead
            self.c2 = sacral_front(p, 0.45) + ahead
            self.c3 = sacral_front(p, 0.60) + ahead
            self.c4 = sacral_front(p, 0.75) + ahead
            self.n0 = 0.0022 * S
            self.n1 = 0.0021 * S
            self.n2 = 0.0022 * S
            self.n3 = 0.0020 * S
            self.n4 = 0.0019 * S
        var box = tube_chain_bounds(self.chain, 0.004)
        if self.nodes:
            box = empty_bounds()
            box.include_sphere(self.c0, self.n0)
            box.include_sphere(self.c1, self.n1)
            box.include_sphere(self.c2, self.n2)
            box.include_sphere(self.c3, self.n3)
            box.include_sphere(self.c4, self.n4)
            box = box.padded(0.004)
        var placed = sided_bounds(box.low, box.high, side)
        self.low = placed.low
        self.high = placed.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the lymph solid, in meters.

        Negative is inside. Zero is the surface.
        """
        var local = point
        if self.mirror:
            local = flip_x(point)
        if not self.nodes:
            return tube_chain_distance(self.chain, local, self.k)
        var d = sd_sphere(local, self.c0, self.n0)
        d = min(d, sd_sphere(local, self.c1, self.n1))
        d = min(d, sd_sphere(local, self.c2, self.n2))
        d = min(d, sd_sphere(local, self.c3, self.n3))
        return min(d, sd_sphere(local, self.c4, self.n4))

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)

    def volume(self) -> Float32:
        """Return the analytic volume of the nodes or the trunk.

        Returns:
            Cubic meters.
        """
        if not self.nodes:
            var c = self.chain
            var length = (c.p1 - c.p0).length() + (c.p2 - c.p1).length()
            length += (c.p3 - c.p2).length() + (c.p4 - c.p3).length()
            return pi * c.r0 * c.r0 * length
        var cubes = (
            self.n0 * self.n0 * self.n0
            + self.n1 * self.n1 * self.n1
            + self.n2 * self.n2 * self.n2
            + self.n3 * self.n3 * self.n3
            + self.n4 * self.n4 * self.n4
        )
        return Float32(4.0 / 3.0) * pi * cubes

    def widened(self, least: Float32) -> PelvisLymphField:
        """Return a copy whose trunk is at least `least` thick, for display.

        Args:
            least: The smallest radius a mesh shows, in meters.

        Returns:
            A wider copy. Nodes are already large enough to show.
        """
        var field = self
        field.chain.r0 = max(field.chain.r0, least)
        field.chain.r1 = max(field.chain.r1, least)
        field.chain.r2 = max(field.chain.r2, least)
        field.chain.r3 = max(field.chain.r3, least)
        field.chain.r4 = max(field.chain.r4, least)
        field.k = max(field.k, Float32(0.4) * least)
        field.low = field.low - Vector3(least, least, least)
        field.high = field.high + Vector3(least, least, least)
        return field


def pelvis_lymph_distance(
    dimensions: PelvisMuscleDimensions,
    part: PelvisLymph,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which lymph solid to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return PelvisLymphField(dimensions, part, side).distance(point)


def pelvis_lymph_label(part: PelvisLymph) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A pelvic lymph part, named or not.

    Returns:
        A short American English label, or `"pelvic lymph"` when `part`
        is not named.
    """
    if part == EXTERNAL_ILIAC_NODES:
        return "external iliac nodes"
    if part == INTERNAL_ILIAC_NODES:
        return "internal iliac nodes"
    if part == COMMON_ILIAC_NODES:
        return "common iliac nodes"
    if part == SACRAL_NODES:
        return "sacral nodes"
    if part == ILIAC_LYMPHATICS:
        return "iliac lymphatics"
    return "pelvic lymph"


def named_pelvis_lymph() -> List[PelvisLymph]:
    """Return every named pelvic node group and trunk.

    Returns:
        Four node groups, then the iliac trunk.
    """
    var parts = List[PelvisLymph]()
    for index in range(ILIAC_LYMPHATICS.value + 1):  # pragma: no branch
        parts.append(PelvisLymph(index))
    return parts^
