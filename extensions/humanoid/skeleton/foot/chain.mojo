# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tapered segments and tube chains shared by the foot layers.

A bone or ligament is one, two or three tapered segments. A muscle,
vessel, lymphatic trunk or nerve is one to four circular tubes. Mass
uses the analytic frustum of those physical radii. A later display mesh
can enlarge a radius. That enlargement is not this volume.
"""

from extensions.humanoid.skeleton.field import (
    Bounds,
    TubeChain,
    empty_bounds,
    sd_segment,
    smin,
    tube_chain_bounds,
    tube_chain_distance,
    tube_chain_volume,
)
from math.vector3 import Vector3
from std.math import max, min, pi


@fieldwise_init
struct SegmentSet(ImplicitlyCopyable):
    """Up to three tapered circular segments of one foot solid."""

    var count: Int
    var a0: Vector3
    var b0: Vector3
    var ra0: Float32
    var rb0: Float32
    var a1: Vector3
    var b1: Vector3
    var ra1: Float32
    var rb1: Float32
    var a2: Vector3
    var b2: Vector3
    var ra2: Float32
    var rb2: Float32


@fieldwise_init
struct TubeSet(ImplicitlyCopyable):
    """Up to four tapered circular tubes of one foot solid."""

    var count: Int
    var c0: TubeChain
    var c1: TubeChain
    var c2: TubeChain
    var c3: TubeChain


def one_segment(a: Vector3, b: Vector3, ra: Float32, rb: Float32) -> SegmentSet:
    """Return a solid made of one tapered segment.

    Args:
        a: Start point, in meters.
        b: End point, in meters.
        ra: Radius at `a`, in meters.
        rb: Radius at `b`, in meters.

    Returns:
        A one-segment set. Unused slots repeat the same segment.
    """
    return SegmentSet(1, a, b, ra, rb, a, b, ra, rb, a, b, ra, rb)


def two_segments(
    a0: Vector3,
    b0: Vector3,
    ra0: Float32,
    rb0: Float32,
    a1: Vector3,
    b1: Vector3,
    ra1: Float32,
    rb1: Float32,
) -> SegmentSet:
    """Return a solid made of two tapered segments.

    Args:
        a0: Start of the first segment, in meters.
        b0: End of the first segment, in meters.
        ra0: Radius at `a0`, in meters.
        rb0: Radius at `b0`, in meters.
        a1: Start of the second segment, in meters.
        b1: End of the second segment, in meters.
        ra1: Radius at `a1`, in meters.
        rb1: Radius at `b1`, in meters.

    Returns:
        A two-segment set. The unused third slot repeats the first.
    """
    return SegmentSet(2, a0, b0, ra0, rb0, a1, b1, ra1, rb1, a0, b0, ra0, rb0)


def three_segments(
    a0: Vector3,
    b0: Vector3,
    ra0: Float32,
    rb0: Float32,
    a1: Vector3,
    b1: Vector3,
    ra1: Float32,
    rb1: Float32,
    a2: Vector3,
    b2: Vector3,
    ra2: Float32,
    rb2: Float32,
) -> SegmentSet:
    """Return a solid made of three tapered segments.

    Args:
        a0: Start of the first segment, in meters.
        b0: End of the first segment, in meters.
        ra0: Radius at `a0`, in meters.
        rb0: Radius at `b0`, in meters.
        a1: Start of the second segment, in meters.
        b1: End of the second segment, in meters.
        ra1: Radius at `a1`, in meters.
        rb1: Radius at `b1`, in meters.
        a2: Start of the third segment, in meters.
        b2: End of the third segment, in meters.
        ra2: Radius at `a2`, in meters.
        rb2: Radius at `b2`, in meters.

    Returns:
        A three-segment set.
    """
    return SegmentSet(3, a0, b0, ra0, rb0, a1, b1, ra1, rb1, a2, b2, ra2, rb2)


def one_tube(chain: TubeChain) -> TubeSet:
    """Return a solid made of one tube.

    Args:
        chain: Five stations.

    Returns:
        A one-tube set. Unused slots repeat `chain`.
    """
    return TubeSet(1, chain, chain, chain, chain)


def two_tubes(first: TubeChain, second: TubeChain) -> TubeSet:
    """Return a solid made of two tubes.

    Args:
        first: The first tube.
        second: The second tube.

    Returns:
        A two-tube set.
    """
    return TubeSet(2, first, second, first, first)


def three_tubes(
    first: TubeChain, second: TubeChain, third: TubeChain
) -> TubeSet:
    """Return a solid made of three tubes.

    Args:
        first: The first tube.
        second: The second tube.
        third: The third tube.

    Returns:
        A three-tube set.
    """
    return TubeSet(3, first, second, third, first)


def four_tubes(
    first: TubeChain,
    second: TubeChain,
    third: TubeChain,
    fourth: TubeChain,
) -> TubeSet:
    """Return a solid made of four tubes.

    Args:
        first: The first tube.
        second: The second tube.
        third: The third tube.
        fourth: The fourth tube.

    Returns:
        A four-tube set.
    """
    return TubeSet(4, first, second, third, fourth)


def segment_distance(set: SegmentSet, point: Vector3, k: Float32) -> Float32:
    """Return how far `point` lies outside `set`, in meters.

    Negative is inside.

    Args:
        set: One to three segments.
        point: A point in the same frame, in meters.
        k: Smooth-union radius, in meters.

    Returns:
        The signed distance, in meters.
    """
    var d = sd_segment(point, set.a0, set.b0, set.ra0, set.rb0)
    if set.count < 2:
        return d
    d = smin(d, sd_segment(point, set.a1, set.b1, set.ra1, set.rb1), k)
    if set.count < 3:
        return d
    return smin(d, sd_segment(point, set.a2, set.b2, set.ra2, set.rb2), k)


def tube_set_distance(set: TubeSet, point: Vector3, k: Float32) -> Float32:
    """Return how far `point` lies outside `set`, in meters.

    Negative is inside.

    Args:
        set: One to four tubes.
        point: A point in the same frame, in meters.
        k: Smooth-union radius, in meters.

    Returns:
        The signed distance, in meters.
    """
    var d = tube_chain_distance(set.c0, point, k)
    if set.count < 2:
        return d
    d = smin(d, tube_chain_distance(set.c1, point, k), k)
    if set.count < 3:
        return d
    d = smin(d, tube_chain_distance(set.c2, point, k), k)
    if set.count < 4:
        return d
    return smin(d, tube_chain_distance(set.c3, point, k), k)


def segment_bounds(set: SegmentSet, pad: Float32) -> Bounds:
    """Return a padded box that holds `set`.

    Args:
        set: One to three segments.
        pad: Extra margin, in meters.

    Returns:
        An axis-aligned box around the used segments.
    """
    var box = empty_bounds()
    box.include_sphere(set.a0, set.ra0)
    box.include_sphere(set.b0, set.rb0)
    if set.count >= 2:
        box.include_sphere(set.a1, set.ra1)
        box.include_sphere(set.b1, set.rb1)
    if set.count >= 3:
        box.include_sphere(set.a2, set.ra2)
        box.include_sphere(set.b2, set.rb2)
    return box.padded(pad)


def tube_set_bounds(set: TubeSet, pad: Float32) -> Bounds:
    """Return a padded box that holds `set`.

    Args:
        set: One to four tubes.
        pad: Extra margin, in meters.

    Returns:
        An axis-aligned box around the used tubes.
    """
    var box = tube_chain_bounds(set.c0, pad)
    if set.count >= 2:
        box = _union(box, tube_chain_bounds(set.c1, pad))
    if set.count >= 3:
        box = _union(box, tube_chain_bounds(set.c2, pad))
    if set.count >= 4:
        box = _union(box, tube_chain_bounds(set.c3, pad))
    return box


def segment_volume(set: SegmentSet) -> Float32:
    """Return the analytic volume of `set`.

    Each used segment is a conical frustum. Two hemispheres cap the
    first start and the last end. Shared internal ends are not capped
    again.

    Args:
        set: One to three segments.

    Returns:
        Approximate envelope volume, in cubic meters.
    """
    var volume = _frustum(set.a0, set.b0, set.ra0, set.rb0)
    var cap_b = set.rb0
    if set.count >= 2:
        volume += _frustum(set.a1, set.b1, set.ra1, set.rb1)
        cap_b = set.rb1
    if set.count >= 3:
        volume += _frustum(set.a2, set.b2, set.ra2, set.rb2)
        cap_b = set.rb2
    volume += (
        Float32(2.0 / 3.0)
        * pi
        * (set.ra0 * set.ra0 * set.ra0 + cap_b * cap_b * cap_b)
    )
    return volume


def tube_set_volume(set: TubeSet) -> Float32:
    """Return the analytic volume of `set`.

    Each used tube includes its own end caps. Overlapping tubes are
    counted twice. That is an authored envelope, not a dissected volume.

    Args:
        set: One to four tubes.

    Returns:
        Approximate envelope volume, in cubic meters.
    """
    var volume = tube_chain_volume(set.c0)
    if set.count >= 2:
        volume += tube_chain_volume(set.c1)
    if set.count >= 3:
        volume += tube_chain_volume(set.c2)
    if set.count >= 4:
        volume += tube_chain_volume(set.c3)
    return volume


def enlarge_tube_set(set: TubeSet, least: Float32) -> TubeSet:
    """Return `set` with every radius held at least to `least`.

    Args:
        set: Physical tubes.
        least: Diagrammatic minimum radius, in meters.

    Returns:
        A copy whose radii are large enough to mesh.
    """
    return TubeSet(
        set.count,
        _enlarge_chain(set.c0, least),
        _enlarge_chain(set.c1, least),
        _enlarge_chain(set.c2, least),
        _enlarge_chain(set.c3, least),
    )


def _union(a: Bounds, b: Bounds) -> Bounds:
    """Return the box that holds both `a` and `b`."""
    return Bounds(
        Vector3(
            min(a.low.x, b.low.x),
            min(a.low.y, b.low.y),
            min(a.low.z, b.low.z),
        ),
        Vector3(
            max(a.high.x, b.high.x),
            max(a.high.y, b.high.y),
            max(a.high.z, b.high.z),
        ),
    )


def _frustum(a: Vector3, b: Vector3, ra: Float32, rb: Float32) -> Float32:
    """Return the volume of one circular conical frustum."""
    var length = (b - a).length()
    return pi * length * (ra * ra + ra * rb + rb * rb) / Float32(3)


def _enlarge_chain(chain: TubeChain, least: Float32) -> TubeChain:
    """Return `chain` with each radius held at least to `least`."""
    var out = chain
    out.r0 = max(out.r0, least)
    out.r1 = max(out.r1, least)
    out.r2 = max(out.r2, least)
    out.r3 = max(out.r3, least)
    out.r4 = max(out.r4, least)
    return out
