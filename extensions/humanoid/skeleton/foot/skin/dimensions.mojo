# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope derived from the modeled anatomy of one foot.

Six sections run from the heel to the metatarsal heads. Five toe
sections continue to the tips. Each section is fitted to the bones,
ligaments, muscles, vessels, lymphatic trunks and nerves. A separate
shell is the dermis for occupancy and mass.

Superficial veins use their physical radii. Diagrammatic display
radii are not part of this fit. Deep vessels do not set the outer
bulk when they lie inside the other solids.

The solid lives in the foot frame. The origin is the tibial plafond.
Plus y is proximal. Plus x is body-right. Plus z is anterior.

    var dims = foot_muscle_dimensions(person)
    var d = skin_distance(dims, Vector3(0, 0, 0))
"""

from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    TubeChain,
    empty_bounds,
    field_gradient,
    mix_point,
    sd_ellipse_segment,
    smin,
)
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootBoneField,
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
from math.vector3 import Vector3
from std.math import max, min


@fieldwise_init
struct _Section(ImplicitlyCopyable):
    """One fitted cross-section of the foot."""

    var center: Vector3
    var ml: Float32
    var ap: Float32


@fieldwise_init
struct _Env(ImplicitlyCopyable):
    """One anatomical sample used to fit the skin."""

    var center: Vector3
    var ml: Float32
    var ap: Float32


struct SkinField(DistanceField, ImplicitlyCopyable):
    """The outer skin surface around the modeled foot anatomy."""

    var s0: _Section
    var s1: _Section
    var s2: _Section
    var s3: _Section
    var s4: _Section
    var s5: _Section
    var h0: _Section
    var h1: _Section
    var u0: _Section
    var u1: _Section
    var v0: _Section
    var v1: _Section
    var w0: _Section
    var w1: _Section
    var x0: _Section
    var x1: _Section
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
        var sole = List[_Env]()
        var toes = List[_Env]()
        _collect(sole, toes, dimensions)
        var foot = dimensions.foot
        var S = foot.stature.value
        # Wide enough that both neighboring sections see each station.
        var slab = 0.25 * foot.length.value
        var cover = 0.0032 * S + Float32(0.0018)
        var heel_z = foot.heel.z
        self.s0 = _fit(
            sole, Vector3(foot.heel.x, foot.heel.y, heel_z), slab, cover
        )
        self.s1 = _fit(
            sole,
            Vector3(0, Float32(-0.030) * S, heel_z + 0.20 * foot.length.value),
            slab,
            cover,
        )
        self.s2 = _fit(sole, Vector3(0, Float32(-0.020) * S, 0), slab, cover)
        self.s3 = _fit(sole, foot.navicular, slab, cover)
        self.s4 = _fit(
            sole, mix_point(foot.mt2_base, foot.mt2_head, 0.45), slab, cover
        )
        self.s5 = _fit(sole, foot.mt2_head, slab, cover)
        var z_slab = 0.24 * foot.length.value
        var x_slab = 0.22 * foot.width.value
        self.h0 = _fit_toe(toes, foot.mt1_head, z_slab, x_slab, cover)
        self.h1 = _fit_toe(toes, foot.hallux_tip, z_slab, x_slab, cover)
        self.u0 = _fit_toe(toes, foot.mt2_head, z_slab, x_slab, cover)
        self.u1 = _fit_toe(toes, foot.toe2_tip, z_slab, x_slab, cover)
        self.v0 = _fit_toe(toes, foot.mt3_head, z_slab, x_slab, cover)
        self.v1 = _fit_toe(toes, foot.toe3_tip, z_slab, x_slab, cover)
        self.w0 = _fit_toe(toes, foot.mt4_head, z_slab, x_slab, cover)
        self.w1 = _fit_toe(toes, foot.toe4_tip, z_slab, x_slab, cover)
        self.x0 = _fit_toe(toes, foot.mt5_head, z_slab, x_slab, cover)
        self.x1 = _fit_toe(toes, foot.toe5_tip, z_slab, x_slab, cover)
        self.blend = 0.0045 * S
        self.dermis = 0.0015 * S
        self.epsilon = 0.0008 * S
        var box = empty_bounds()
        _include(box, self.s0)
        _include(box, self.s1)
        _include(box, self.s2)
        _include(box, self.s3)
        _include(box, self.s4)
        _include(box, self.s5)
        _include(box, self.h0)
        _include(box, self.h1)
        _include(box, self.u0)
        _include(box, self.u1)
        _include(box, self.v0)
        _include(box, self.v1)
        _include(box, self.w0)
        _include(box, self.w1)
        _include(box, self.x0)
        _include(box, self.x1)
        var padded = box.padded(0.004)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the anatomy-derived outer surface.

        Negative is inside. Zero is the surface.
        """
        var axis = Vector3(1, 0, 0)
        var d = _span(point, self.s0, self.s1, axis)
        d = smin(d, _span(point, self.s1, self.s2, axis), self.blend)
        d = smin(d, _span(point, self.s2, self.s3, axis), self.blend)
        d = smin(d, _span(point, self.s3, self.s4, axis), self.blend)
        d = smin(d, _span(point, self.s4, self.s5, axis), self.blend)
        d = smin(d, _span(point, self.h0, self.h1, axis), self.blend)
        d = smin(d, _span(point, self.u0, self.u1, axis), self.blend)
        d = smin(d, _span(point, self.v0, self.v1, axis), self.blend)
        d = smin(d, _span(point, self.w0, self.w1, axis), self.blend)
        return smin(d, _span(point, self.x0, self.x1, axis), self.blend)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct SkinLayerField(DistanceField, ImplicitlyCopyable):
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


def _collect(
    mut sole: List[_Env], mut toes: List[_Env], dimensions: FootMuscleDimensions
) raises:
    """Append every modeled station to the sole list, the toe list, or both."""
    var split_z = dimensions.foot.mt2_head.z
    var bones = named_foot_bones()
    for index in range(len(bones)):  # pragma: no branch
        var field = FootBoneField(dimensions.foot, bones[index])
        _append_segments(sole, toes, field.segments, split_z)
    var ligaments = named_foot_ligaments()
    for index in range(len(ligaments)):  # pragma: no branch
        var field = FootLigamentField(dimensions.foot, ligaments[index])
        _append_segments(sole, toes, field.segments, split_z)
    var muscles = named_foot_muscles()
    for index in range(len(muscles)):  # pragma: no branch
        var field = FootMuscleField(dimensions, muscles[index])
        _append_tubes(sole, toes, field.tubes, split_z)
    var vessels = named_foot_vessels()
    for index in range(len(vessels)):  # pragma: no branch
        var field = FootVesselField(dimensions.foot, vessels[index])
        _append_tubes(sole, toes, field.tubes, split_z)
    var lymph = named_foot_lymph()
    for index in range(len(lymph)):  # pragma: no branch
        var field = FootLymphField(dimensions.foot, lymph[index])
        _append_tubes(sole, toes, field.tubes, split_z)
    var nerves = named_foot_nerves()
    for index in range(len(nerves)):  # pragma: no branch
        var field = FootNerveField(dimensions.foot, nerves[index])
        _append_tubes(sole, toes, field.tubes, split_z)


def _append_segments(
    mut sole: List[_Env],
    mut toes: List[_Env],
    segs: SegmentSet,
    split_z: Float32,
):
    """Append the stations of one segment set."""
    _station(sole, toes, segs.a0, segs.ra0, split_z)
    _station(sole, toes, segs.b0, segs.rb0, split_z)
    _station(
        sole,
        toes,
        mix_point(segs.a0, segs.b0, 0.5),
        Float32(0.5) * (segs.ra0 + segs.rb0),
        split_z,
    )
    if segs.count >= 2:
        _station(sole, toes, segs.a1, segs.ra1, split_z)
        _station(sole, toes, segs.b1, segs.rb1, split_z)
        _station(
            sole,
            toes,
            mix_point(segs.a1, segs.b1, 0.5),
            Float32(0.5) * (segs.ra1 + segs.rb1),
            split_z,
        )
    if segs.count >= 3:
        _station(sole, toes, segs.a2, segs.ra2, split_z)
        _station(sole, toes, segs.b2, segs.rb2, split_z)
        _station(
            sole,
            toes,
            mix_point(segs.a2, segs.b2, 0.5),
            Float32(0.5) * (segs.ra2 + segs.rb2),
            split_z,
        )


def _append_tubes(
    mut sole: List[_Env], mut toes: List[_Env], tubes: TubeSet, split_z: Float32
):
    """Append the stations of one tube set."""
    _append_chain(sole, toes, tubes.c0, split_z)
    if tubes.count >= 2:
        _append_chain(sole, toes, tubes.c1, split_z)
    if tubes.count >= 3:
        _append_chain(sole, toes, tubes.c2, split_z)
    if tubes.count >= 4:
        _append_chain(sole, toes, tubes.c3, split_z)


def _append_chain(
    mut sole: List[_Env],
    mut toes: List[_Env],
    chain: TubeChain,
    split_z: Float32,
):
    """Append the five stations of one tube."""
    _station(sole, toes, chain.p0, chain.r0, split_z)
    _station(sole, toes, chain.p1, chain.r1, split_z)
    _station(sole, toes, chain.p2, chain.r2, split_z)
    _station(sole, toes, chain.p3, chain.r3, split_z)
    _station(sole, toes, chain.p4, chain.r4, split_z)


def _station(
    mut sole: List[_Env],
    mut toes: List[_Env],
    center: Vector3,
    radius: Float32,
    split_z: Float32,
):
    """File a sample on the sole, the toes, or both."""
    var sample = _Env(center, radius, radius)
    if center.z <= split_z:
        sole.append(sample)
    if center.z >= split_z - Float32(0.02):
        toes.append(sample)


def _fit(
    points: List[_Env], seed: Vector3, slab: Float32, cover: Float32
) -> _Section:
    """Fit one enclosing ellipse to samples near `seed` along z."""
    var least_x = seed.x
    var most_x = seed.x
    var least_y = seed.y
    var most_y = seed.y
    for index in range(len(points)):  # pragma: no branch
        var sample = points[index]
        var dz = sample.center.z - seed.z
        if dz < 0:
            dz = -dz
        if dz <= slab:
            least_x = min(least_x, sample.center.x - sample.ml)
            most_x = max(most_x, sample.center.x + sample.ml)
            least_y = min(least_y, sample.center.y - sample.ap)
            most_y = max(most_y, sample.center.y + sample.ap)
    return _section_from(least_x, most_x, least_y, most_y, seed.z, cover)


def _fit_toe(
    points: List[_Env],
    seed: Vector3,
    z_slab: Float32,
    x_slab: Float32,
    cover: Float32,
) -> _Section:
    """Fit one toe section to samples near `seed` in z and x."""
    var least_x = seed.x
    var most_x = seed.x
    var least_y = seed.y
    var most_y = seed.y
    for index in range(len(points)):  # pragma: no branch
        var sample = points[index]
        var dz = sample.center.z - seed.z
        if dz < 0:
            dz = -dz
        var dx = sample.center.x - seed.x
        if dx < 0:
            dx = -dx
        if dz <= z_slab:
            if dx <= x_slab:
                least_x = min(least_x, sample.center.x - sample.ml)
                most_x = max(most_x, sample.center.x + sample.ml)
                least_y = min(least_y, sample.center.y - sample.ap)
                most_y = max(most_y, sample.center.y + sample.ap)
    return _section_from(least_x, most_x, least_y, most_y, seed.z, cover)


def _section_from(
    least_x: Float32,
    most_x: Float32,
    least_y: Float32,
    most_y: Float32,
    z: Float32,
    cover: Float32,
) -> _Section:
    """Return an ellipse that holds the sampled bounds, plus `cover`."""
    var center = Vector3(
        Float32(0.5) * (least_x + most_x),
        Float32(0.5) * (least_y + most_y),
        z,
    )
    # 0.72 of the full span is more than the half-span, so corners stay inside.
    var ml = Float32(0.72) * (most_x - least_x) + cover
    var ap = Float32(0.72) * (most_y - least_y) + cover
    return _Section(center, ml, ap)


def _include(mut box: Bounds, section: _Section):
    """Grow `box` around one skin section."""
    box.include_ellipsoid(
        section.center, Vector3(section.ml, section.ap, section.ml)
    )


def _span(point: Vector3, a: _Section, b: _Section, axis: Vector3) -> Float32:
    """Return distance to one fitted skin segment."""
    return sd_ellipse_segment(
        point, a.center, b.center, a.ml, a.ap, b.ml, b.ap, axis
    )
