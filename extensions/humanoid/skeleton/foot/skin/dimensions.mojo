# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope derived from the modeled anatomy of one foot.

One loft runs from behind the heel to the toe webs. Five more run
along the toes, one each. Every section slices the bones, ligaments,
muscles, vessels, lymphatic trunks and nerves, closes the outline as a
convex hull, and adds the soft tissue that covers it. See
`extensions.humanoid.skeleton.loft`. A separate shell is the dermis for
occupancy and mass.

The sole is not a hull of the bones alone. Pads under the heel, the
lateral column, the metatarsal heads and the toe pulps carry the skin
to the ground, and the medial arch stays clear of it.

The solid lives in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_muscle_dimensions(person)
    var d = skin_distance(dims, Vector3(0, 0, 0))
"""

from extensions.humanoid.skeleton.field import (
    DistanceField,
    TubeChain,
    field_gradient,
    smin,
)
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    HEEL_SKIN,
    FootBoneField,
    FootDimensions,
    named_foot_bones,
)
from extensions.humanoid.skeleton.foot.chain import SegmentSet, TubeSet
from extensions.humanoid.skeleton.foot.ligaments.dimensions import (
    FootLigamentField,
    named_foot_ligaments,
)
from extensions.humanoid.skeleton.foot.lymph.dimensions import (
    FootLymphField,
    named_foot_lymph,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscleDimensions,
    FootMuscleField,
    named_foot_muscles,
)
from extensions.humanoid.skeleton.foot.nerves.dimensions import (
    FootNerveField,
    named_foot_nerves,
)
from extensions.humanoid.skeleton.foot.vessels.dimensions import (
    FootVesselField,
    named_foot_vessels,
)
from extensions.humanoid.skeleton.loft import (
    AXIS_Z,
    Loft,
    LoftSample,
    fit_loft,
    loft_distance,
)
from math.vector3 import Vector3
from std.math import abs, max, min

# Sections of the loft from the heel to the toe webs.
comptime FOOT_SECTIONS = 34
# Sections of one toe's loft.
comptime TOE_SECTIONS = 12
# Passes that fill one-section dips along a loft. See `fit_loft`.
comptime FILL_PASSES = 3
# Where the toe webs end, as a fraction of foot length forward of the
# heel's skin. The lofts of the toes carry on from there.
comptime WEB_REACH = Float32(0.80)


struct SkinField(Copyable, DistanceField, Movable):
    """The outer skin surface around the modeled foot anatomy."""

    var foot: Loft
    var hallux: Loft
    var toe2: Loft
    var toe3: Loft
    var toe4: Loft
    var toe5: Loft
    var blend: Float32
    var dermis: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FootMuscleDimensions) raises:
        """Fit the envelope around every modeled foot solid.

        Args:
            dimensions: Landmarks and the muscle scale.

        Raises:
            Error: If `dimensions.validate` refuses the copy.
        """
        dimensions.validate()
        var foot = dimensions.foot
        var S = foot.stature.value
        var L = foot.length.value
        # Soft tissue over the dorsum and the sides, and over the toes.
        var cover = Float32(0.0028) * S
        var toe_cover = Float32(0.0022) * S
        var samples = List[LoftSample]()
        _collect(samples, dimensions)
        _pads(samples, foot, cover, toe_cover)
        var heel_skin = -HEEL_SKIN * L
        var web = (WEB_REACH - HEEL_SKIN) * L
        # The first section stands behind the heel, where nothing is,
        # so the heel rounds off to its cover.
        var start = heel_skin - Float32(0.004) * S
        self.foot = fit_loft(
            samples,
            AXIS_Z,
            start,
            web,
            FOOT_SECTIONS,
            List[Float32](length=FOOT_SECTIONS, fill=cover),
            FILL_PASSES,
        )
        self.hallux = _toe(
            samples, foot.mt1_head, foot.hallux_tip, foot, toe_cover
        )
        self.toe2 = _toe(samples, foot.mt2_head, foot.toe2_tip, foot, toe_cover)
        self.toe3 = _toe(samples, foot.mt3_head, foot.toe3_tip, foot, toe_cover)
        self.toe4 = _toe(samples, foot.mt4_head, foot.toe4_tip, foot, toe_cover)
        self.toe5 = _toe(samples, foot.mt5_head, foot.toe5_tip, foot, toe_cover)
        self.blend = Float32(0.0015) * S
        self.dermis = Float32(0.0015) * S
        self.epsilon = Float32(0.0008) * S
        var low = self.foot.low
        var high = self.foot.high
        _grow(low, high, self.hallux)
        _grow(low, high, self.toe2)
        _grow(low, high, self.toe3)
        _grow(low, high, self.toe4)
        _grow(low, high, self.toe5)
        self.low = low
        self.high = high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the anatomy-derived outer surface.

        Negative is inside. Zero is the surface.
        """
        var d = loft_distance(self.foot, point)
        d = smin(d, loft_distance(self.hallux, point), self.blend)
        d = smin(d, loft_distance(self.toe2, point), self.blend)
        d = smin(d, loft_distance(self.toe3, point), self.blend)
        d = smin(d, loft_distance(self.toe4, point), self.blend)
        return smin(d, loft_distance(self.toe5, point), self.blend)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct SkinLayerField(Copyable, DistanceField, Movable):
    """The dermal shell immediately inside a `SkinField`."""

    var outer: SkinField
    var thickness: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: FootMuscleDimensions) raises:
        """Build the dermal shell around the modeled anatomy.

        Args:
            dimensions: Landmarks and the muscle scale.

        Raises:
            Error: If the outer field refuses an anatomical input.
        """
        self.outer = SkinField(dimensions)
        self.thickness = self.outer.dermis
        self.low = self.outer.low
        self.high = self.outer.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the dermal shell, in meters.

        Negative is inside the dermis. Deep anatomy and exterior space
        are both outside this shell.
        """
        var d = self.outer.distance(point)
        return max(d, -d - self.thickness)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the dermal shell at `point`."""
        return field_gradient(self, point, self.outer.epsilon)


def skin_distance(
    dimensions: FootMuscleDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the skin envelope, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `foot_muscle_dimensions`.
        point: A point in the foot frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return SkinField(dimensions).distance(point)


def _grow(mut low: Vector3, mut high: Vector3, loft: Loft):
    """Grow the box from `low` to `high` around one loft."""
    low = Vector3(
        min(low.x, loft.low.x), min(low.y, loft.low.y), min(low.z, loft.low.z)
    )
    high = Vector3(
        max(high.x, loft.high.x),
        max(high.y, loft.high.y),
        max(high.z, loft.high.z),
    )


def _toe(
    samples: List[LoftSample],
    head: Vector3,
    tip: Vector3,
    foot: FootDimensions,
    cover: Float32,
) raises -> Loft:
    """Return the loft of one toe, from its metatarsal head to past its tip.

    Only the solids in the toe's own lane reach it: a lane half as wide as
    the space between two toes, centered on the line from the head to the
    tip.
    """
    var lane = Float32(0.075) * foot.width.value
    var own = List[LoftSample]()
    var index = 0
    while index < len(samples):
        var sample = samples[index]
        var inside = _in_lane(sample.center, head, tip, lane)
        if inside and sample.center.z > head.z - lane:
            var joins = sample.joins
            # A run that starts outside the lane starts again here.
            if joins and not _kept(own, samples, index):
                joins = False
            own.append(
                LoftSample(
                    sample.center, sample.ml, sample.ap, sample.reach, joins
                )
            )
        index += 1
    var end = tip.z + Float32(0.35) * lane + cover
    return fit_loft(
        own,
        AXIS_Z,
        head.z,
        end,
        TOE_SECTIONS,
        List[Float32](length=TOE_SECTIONS, fill=cover),
        FILL_PASSES,
    )


def _kept(own: List[LoftSample], samples: List[LoftSample], index: Int) -> Bool:
    """Return whether the station before `index` was kept in `own`."""
    if len(own) == 0:
        return False
    var before = samples[index - 1].center
    var last = own[len(own) - 1].center
    return (before - last).length() == 0


def _in_lane(
    point: Vector3, head: Vector3, tip: Vector3, lane: Float32
) -> Bool:
    """Return whether `point` lies within `lane` of the toe's line in x."""
    var run = max(tip.z - head.z, Float32(1.0e-6))
    var t = min(max((point.z - head.z) / run, Float32(0)), Float32(1))
    var x = head.x + (tip.x - head.x) * t
    return abs(point.x - x) <= lane


def _pads(
    mut samples: List[LoftSample],
    foot: FootDimensions,
    cover: Float32,
    toe_cover: Float32,
):
    """Append the pads that carry the sole to the ground.

    Each pad is a small sphere set its radius and the cover above the
    ground, so the skin meets the ground under it. The heel, the lateral
    column, the ball of the foot and each toe pulp bear weight. The
    medial arch does not.
    """
    var S = foot.stature.value
    var ground = -foot.height.value
    var r = Float32(0.003) * S
    var lift = ground + cover + r
    var toe_lift = ground + toe_cover + r
    var W = foot.width.value
    # Plus one on a right foot, minus one on a left.
    var span = foot.lateral_malleolus.x - foot.medial_malleolus.x
    var lateral = span / abs(span)
    # The heel pad: two either side of the midline, under the tuberosity.
    for across in [Float32(-0.14), Float32(0.14)]:  # pragma: no branch
        for along in [Float32(0.0), Float32(0.014)]:  # pragma: no branch
            samples.append(
                LoftSample(
                    Vector3(
                        foot.heel.x + lateral * across * W,
                        lift,
                        foot.heel.z + along * S,
                    ),
                    r,
                    r,
                    r,
                    False,
                )
            )
    # The lateral column, from the heel to the fifth metatarsal head.
    for k in range(1, 5):  # pragma: no branch
        var t = Float32(k) / Float32(5)
        var z = foot.heel.z + (foot.mt5_head.z - foot.heel.z) * t
        var x = lateral * (Float32(0.14) + Float32(0.14) * t) * W
        samples.append(LoftSample(Vector3(x, lift, z), r, r, r, False))
    # The ball of the foot, under every metatarsal head.
    for head in [  # pragma: no branch
        foot.mt1_head,
        foot.mt2_head,
        foot.mt3_head,
        foot.mt4_head,
        foot.mt5_head,
    ]:
        samples.append(
            LoftSample(Vector3(head.x, lift, head.z), r, r, r, False)
        )
    # The toe pulps, just behind each tip.
    for tip in [  # pragma: no branch
        foot.hallux_tip,
        foot.toe2_tip,
        foot.toe3_tip,
        foot.toe4_tip,
        foot.toe5_tip,
    ]:
        samples.append(
            LoftSample(Vector3(tip.x, toe_lift, tip.z - r), r, r, r, False)
        )


def _collect(
    mut samples: List[LoftSample], dimensions: FootMuscleDimensions
) raises:
    """Append the stations of every modeled foot solid."""
    var foot = dimensions.foot
    var bones = named_foot_bones()
    for index in range(len(bones)):  # pragma: no branch
        var field = FootBoneField(foot, bones[index])
        _append_segments(samples, field.segments)
    var ligaments = named_foot_ligaments()
    for index in range(len(ligaments)):  # pragma: no branch
        var field = FootLigamentField(foot, ligaments[index])
        _append_segments(samples, field.segments)
    var muscles = named_foot_muscles()
    for index in range(len(muscles)):  # pragma: no branch
        var field = FootMuscleField(dimensions, muscles[index])
        _append_tubes(samples, field.tubes)
    var vessels = named_foot_vessels()
    for index in range(len(vessels)):  # pragma: no branch
        var field = FootVesselField(foot, vessels[index])
        _append_tubes(samples, field.tubes)
    var lymph = named_foot_lymph()
    for index in range(len(lymph)):  # pragma: no branch
        var field = FootLymphField(foot, lymph[index])
        _append_tubes(samples, field.tubes)
    var nerves = named_foot_nerves()
    for index in range(len(nerves)):  # pragma: no branch
        var field = FootNerveField(foot, nerves[index])
        _append_tubes(samples, field.tubes)
    var S = foot.stature.value
    # The foot of the leg: the distal tibia and fibula as two columns
    # that rise to where the tendons leave the leg. Every section across
    # the ankle then ends at the same height, inside the leg's skin.
    var top = Float32(0.045) * S
    var medial = foot.medial_malleolus
    var lateral = foot.lateral_malleolus
    var tibia = Vector3(Float32(0.7) * medial.x, 0, Float32(0.5) * medial.z)
    samples.append(
        LoftSample(
            tibia + Vector3(0, -0.006 * S, 0), 0.011 * S, 0.011 * S, 0, False
        )
    )
    samples.append(
        LoftSample(tibia + Vector3(0, top, 0), 0.012 * S, 0.012 * S, 0, True)
    )
    samples.append(LoftSample(lateral, 0.006 * S, 0.006 * S, 0, False))
    samples.append(
        LoftSample(
            Vector3(lateral.x, top, lateral.z), 0.005 * S, 0.005 * S, 0, True
        )
    )
    var malleolus = Float32(0.0055) * S
    samples.append(
        LoftSample(foot.medial_malleolus, malleolus, malleolus, 0, False)
    )
    samples.append(
        LoftSample(foot.lateral_malleolus, malleolus, malleolus, 0, False)
    )


def _append_segments(mut samples: List[LoftSample], segs: SegmentSet):
    """Append each tapered segment of a set as a joined pair."""
    _pair(samples, segs.a0, segs.ra0, segs.b0, segs.rb0)
    if segs.count >= 2:
        _pair(samples, segs.a1, segs.ra1, segs.b1, segs.rb1)
    if segs.count >= 3:
        _pair(samples, segs.a2, segs.ra2, segs.b2, segs.rb2)


def _pair(
    mut samples: List[LoftSample],
    a: Vector3,
    ra: Float32,
    b: Vector3,
    rb: Float32,
):
    """Append one round tapered segment."""
    samples.append(LoftSample(a, ra, ra, 0, False))
    samples.append(LoftSample(b, rb, rb, 0, True))


def _append_tubes(mut samples: List[LoftSample], tubes: TubeSet):
    """Append each tube of a set as a run of joined stations."""
    _append_chain(samples, tubes.c0)
    if tubes.count >= 2:
        _append_chain(samples, tubes.c1)
    if tubes.count >= 3:
        _append_chain(samples, tubes.c2)
    if tubes.count >= 4:
        _append_chain(samples, tubes.c3)


def _append_chain(mut samples: List[LoftSample], chain: TubeChain):
    """Append the five stations of one tube."""
    samples.append(LoftSample(chain.p0, chain.r0, chain.r0, 0, False))
    samples.append(LoftSample(chain.p1, chain.r1, chain.r1, 0, True))
    samples.append(LoftSample(chain.p2, chain.r2, chain.r2, 0, True))
    samples.append(LoftSample(chain.p3, chain.r3, chain.r3, 0, True))
    samples.append(LoftSample(chain.p4, chain.r4, chain.r4, 0, True))
