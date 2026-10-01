# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named nerves of the pelvis, as implicit tubes in the pelvis frame.

The set is the lumbosacral trunk, the sacral plexus and the sciatic
nerve's pelvic course, the femoral, obturator, superior and inferior
gluteal and pudendal nerves, and the lateral femoral cutaneous nerve.
The lumbar roots are not modeled; each lumbar nerve starts beside the
spine where the psoas would release it. The sciatic and femoral nerves
end where the leg's begin.

Every nerve is paired, authored on the right and mirrored on x for the
left. Physical radii drive distance and mass. Geometry applies a
separate diagrammatic minimum radius.

    var dims = pelvis_muscle_dimensions(person)
    var d = pelvis_nerve_distance(dims, PUDENDAL_NERVE, RIGHT, p)
"""

from extensions.humanoid.side import LEFT, BodySide
from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    field_gradient,
    flip_x,
    mix_point,
    tube_chain_bounds,
    tube_chain_distance,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    pelvis_frame,
    sacral_front,
    sided_bounds,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
)
from math.vector3 import Vector3
from std.math import max


@fieldwise_init
struct PelvisNerve(Equatable, ImplicitlyCopyable, Writable):
    """Which named pelvic nerve a caller asks for.

    The type stops a bare integer at compile time. A value that is not
    one of the named nerves is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named nerve."""
        if self.value < 0:
            return False
        return self.value <= LATERAL_FEMORAL_CUTANEOUS_NERVE.value


comptime LUMBOSACRAL_TRUNK = PelvisNerve(0)
# The sacral plexus on the piriformis, and the sciatic nerve out through
# the greater sciatic foramen to the thigh.
comptime SACRAL_PLEXUS = PelvisNerve(1)
comptime PELVIC_FEMORAL_NERVE = PelvisNerve(2)
comptime OBTURATOR_NERVE = PelvisNerve(3)
comptime SUPERIOR_GLUTEAL_NERVE = PelvisNerve(4)
comptime INFERIOR_GLUTEAL_NERVE = PelvisNerve(5)
comptime PUDENDAL_NERVE = PelvisNerve(6)
comptime LATERAL_FEMORAL_CUTANEOUS_NERVE = PelvisNerve(7)


struct PelvisNerveField(DistanceField, ImplicitlyCopyable):
    """The implicit solid for one pelvic nerve on one side."""

    var chain: TubeChain
    var mirror: Bool
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        dimensions: PelvisMuscleDimensions,
        part: PelvisNerve,
        side: BodySide,
    ) raises:
        """Build one nerve from landmarks that `validate` accepts.

        Args:
            dimensions: Landmarks shared with the muscles.
            part: A named nerve.
            side: `RIGHT` or `LEFT`.

        Raises:
            Error: If `dimensions.validate` refuses the copy, if `part`
                is not named, or if `side` is not valid.
        """
        dimensions.validate()
        if not part.is_valid():
            raise Error("A pelvic nerve must be a named nerve")
        if not side.is_valid():
            raise Error("A pelvis side must be RIGHT or LEFT")
        self.chain = _chain(dimensions, part)
        self.mirror = side == LEFT
        self.k = Float32(0.00025)
        self.epsilon = Float32(0.00015)
        var box = tube_chain_bounds(self.chain, Float32(0.003) + self.chain.r0)
        var placed = sided_bounds(box.low, box.high, side)
        self.low = placed.low
        self.high = placed.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the nerve, in meters.

        Negative is inside. Zero is the surface.
        """
        if self.mirror:
            return tube_chain_distance(self.chain, flip_x(point), self.k)
        return tube_chain_distance(self.chain, point, self.k)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)

    def widened(self, least: Float32) -> PelvisNerveField:
        """Return a copy whose radii are at least `least`, for display.

        Args:
            least: The smallest radius a mesh shows, in meters.

        Returns:
            A wider copy with a larger blend and box.
        """
        var field = self
        field.chain.r0 = max(field.chain.r0, least)
        field.chain.r1 = max(field.chain.r1, least)
        field.chain.r2 = max(field.chain.r2, least)
        field.chain.r3 = max(field.chain.r3, least)
        field.chain.r4 = max(field.chain.r4, least)
        field.k = Float32(0.4) * least
        field.epsilon = Float32(0.25) * least
        field.low = field.low - Vector3(least, least, least)
        field.high = field.high + Vector3(least, least, least)
        return field


def pelvis_nerve_distance(
    dimensions: PelvisMuscleDimensions,
    part: PelvisNerve,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which nerve to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return PelvisNerveField(dimensions, part, side).distance(point)


def pelvis_nerve_label(part: PelvisNerve) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A pelvic nerve, named or not.

    Returns:
        A short American English label, or `"pelvic nerve"` when `part`
        is not named.
    """
    if part == LUMBOSACRAL_TRUNK:
        return "lumbosacral trunk"
    if part == SACRAL_PLEXUS:
        return "sacral plexus"
    if part == PELVIC_FEMORAL_NERVE:
        return "femoral nerve"
    if part == OBTURATOR_NERVE:
        return "obturator nerve"
    if part == SUPERIOR_GLUTEAL_NERVE:
        return "superior gluteal nerve"
    if part == INFERIOR_GLUTEAL_NERVE:
        return "inferior gluteal nerve"
    if part == PUDENDAL_NERVE:
        return "pudendal nerve"
    if part == LATERAL_FEMORAL_CUTANEOUS_NERVE:
        return "lateral femoral cutaneous nerve"
    return "pelvic nerve"


def named_pelvis_nerves() -> List[PelvisNerve]:
    """Return every named pelvic nerve in a stable order.

    Returns:
        The trunk and plexus, then the six named branches.
    """
    var parts = List[PelvisNerve]()
    for index in range(
        LATERAL_FEMORAL_CUTANEOUS_NERVE.value + 1
    ):  # pragma: no branch
        parts.append(PelvisNerve(index))
    return parts^


def _chain(d: PelvisMuscleDimensions, part: PelvisNerve) -> TubeChain:
    """Return one nerve's centerline and radii, on the right side."""
    var p = d.pelvis
    var f = pelvis_frame(p)
    var S = p.stature.value
    # The sacral plexus lies on the front of the piriformis.
    var plexus = sacral_front(p, 0.4) + f.template(3.3, 0, -0.4)
    # Behind the middle of the inguinal ligament.
    var inguinal = mix_point(p.asis, p.symphysis_top, 0.5) + f.template(
        0, -0.35, -0.9
    )
    if part == LUMBOSACRAL_TRUNK:
        var top = p.promontory + f.template(3.1, 4.4, -2.0)
        var ala = p.auricular + f.template(-1.8, -0.9, 2.6)
        return TubeChain(
            top,
            mix_point(top, ala, 0.5),
            ala,
            mix_point(ala, plexus, 0.5),
            plexus,
            0.0022 * S,
            0.0022 * S,
            0.0022 * S,
            0.0023 * S,
            0.0024 * S,
        )
    if part == SACRAL_PLEXUS:
        # Out below the piriformis, behind the hip, to the thigh.
        var out = p.notch + f.template(-1.1, -2.2, -2.7)
        return TubeChain(
            plexus,
            mix_point(plexus, out, 0.5),
            out,
            f.template(9.2, -3.5, -7.3),
            d.sciatic_nerve,
            0.0030 * S,
            0.0033 * S,
            0.0034 * S,
            0.0035 * S,
            0.0035 * S,
        )
    if part == PELVIC_FEMORAL_NERVE:
        # Down the groove between the psoas and the iliacus, and under
        # the inguinal ligament beside the femoral artery.
        return TubeChain(
            p.promontory + f.template(4.9, 7.3, 1.1),
            f.template(6.4, 9.0, 0.6),
            f.template(7.6, 6.0, 1.8),
            inguinal + f.template(1.5, -0.2, -0.15),
            d.femoral_nerve,
            0.0020 * S,
            0.0021 * S,
            0.0022 * S,
            0.0022 * S,
            0.0022 * S,
        )
    if part == OBTURATOR_NERVE:
        # Along the side wall and out through the obturator canal.
        return TubeChain(
            p.promontory + f.template(3.1, 5.5, 0.2),
            p.auricular + f.template(-0.4, -1.2, 6.0),
            f.template(5.3, 1.5, -0.2),
            p.obturator + f.template(0.7, 2.75, 0.4),
            p.obturator + f.template(1.6, 1.2, 1.6),
            0.0014 * S,
            0.0014 * S,
            0.0014 * S,
            0.0013 * S,
            0.0012 * S,
        )
    if part == SUPERIOR_GLUTEAL_NERVE:
        # Above the piriformis, then between the gluteus medius and
        # minimus.
        return TubeChain(
            plexus + f.template(0.3, 1.0, -0.3),
            p.notch + f.template(-0.6, 0.6, -1.8),
            p.notch + f.template(0.4, 1.3, -2.9),
            f.template(10.0, 5.5, -6.0),
            f.template(11.5, 6.0, -3.5),
            0.0011 * S,
            0.0011 * S,
            0.0011 * S,
            0.0010 * S,
            0.0009 * S,
        )
    if part == INFERIOR_GLUTEAL_NERVE:
        # Below the piriformis into the gluteus maximus.
        return TubeChain(
            plexus + f.template(0.5, -1.0, -0.6),
            p.notch + f.template(-1.4, -2.0, -2.9),
            p.notch + f.template(0.4, -4.0, -4.5),
            f.template(8.6, -2.2, -9.6),
            f.template(9.4, -3.2, -10.4),
            0.0011 * S,
            0.0011 * S,
            0.0011 * S,
            0.0010 * S,
            0.0009 * S,
        )
    if part == PUDENDAL_NERVE:
        # Around the sacrospinous ligament and forward in the pudendal
        # canal to the perineum.
        return TubeChain(
            plexus + f.template(0.2, -1.4, -0.4),
            p.spine + f.template(-0.1, -0.3, -1.3),
            mix_point(p.tuberosity, p.ramus, 0.4) + f.template(-1.6, 0.9, 0.2),
            p.symphysis_bottom + f.template(2.8, -0.3, -1.6),
            p.symphysis_bottom + f.template(1.8, -0.8, -0.4),
            0.0012 * S,
            0.0012 * S,
            0.0011 * S,
            0.0010 * S,
            0.0009 * S,
        )
    # The lateral femoral cutaneous nerve crosses the iliacus and leaves
    # under the inguinal ligament beside the anterior superior spine.
    return TubeChain(
        p.promontory + f.template(4.4, 6.9, -0.9),
        p.hub + f.template(0.7, 5.0, 1.9),
        p.asis + f.template(-1.1, -0.7, 0),
        p.asis + f.template(-0.8, -2.6, 0.4),
        p.asis + f.template(-0.55, -4.6, 0.7),
        0.0009 * S,
        0.0009 * S,
        0.0009 * S,
        0.0009 * S,
        0.0008 * S,
    )
