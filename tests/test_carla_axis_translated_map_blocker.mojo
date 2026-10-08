# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Explicit construction refusal for unrepresentable road-s subdivision.

The original five-ULP Map input cannot meet the parameter-matched target.
The line and direct-Road stored-point minima remain representable.
"""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_refinement import _axis_lane_minimum
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.opendrive import load_opendrive
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import LaneId
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _flat_map(
    length: Float64 = 1.0,
    origin: Float64 = 0.0,
    record_s: Float64 = 0.0,
    reverse: Bool = False,
    quadratic_width: Bool = False,
) raises -> Map:
    var side = "left" if reverse else "right"
    var id = 1 if reverse else -1
    var parsed = load_opendrive(
        String(
            (
                '<OpenDRIVE><road id="1" length="1" junction="-1" rule="RHT">'
                '<planView><geometry s="0" x="0" y="0" hdg="0" length="1">'
                '<line/></geometry></planView><lanes><laneOffset s="0" a="0"'
                ' b="0" c="0" d="0"/><laneSection s="0">'
                '<center><lane id="0" type="none"/></center><'
            ),
            side,
            '><lane id="',
            id,
            (
                '" type="driving"><width sOffset="0" a="0.0002" b="0" c="0"'
                ' d="0"/></lane></'
            ),
            side,
            "></laneSection></lanes></road></OpenDRIVE>",
        )
    )
    var roads = parsed.roads.copy()
    roads[0].length = record_s + length
    roads[0].sections[0].s = record_s
    roads[0].info.geometries[0].s = record_s
    roads[0].info.geometries[0].geometry.s = record_s
    roads[0].info.geometries[0].geometry.length = length
    roads[0].info.geometries[0].geometry.x = origin
    var lane = roads[0].sections[0].lane_index(LaneId(id))
    roads[0].sections[0].lanes[lane].distance = record_s
    roads[0].sections[0].lanes[lane].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(0.0002)
    if quadratic_width:
        roads[0].sections[0].lanes[lane].info.widths[0].polynomial.c = 1e-40
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def test_translated_parameter_grid_rejects_unrepresentable_subdivision() raises:
    # Preserve the original five-ULP Map input. No contiguous partition
    # can meet the unchanged one-millimeter parameter-matched chord target.
    # The exact bracket and tie successes remain in the direct-Road suite.
    var base = Float64(1e20)
    with assert_raises(contains="Float64 road-s resolution"):
        _ = _flat_map(length=81920.0, record_s=base)


def test_translated_fixture_preserves_exact_input_bits() raises:
    var base = Float64(1e20)
    assert_equal(bitcast[DType.uint64](base), UInt64(0x4415AF1D78B58C40))
    assert_equal(
        bitcast[DType.uint64](base + 81920.0), UInt64(0x4415AF1D78B58C45)
    )
    assert_equal(base + 16384.0 - base, 16384.0)
    assert_equal(base + 8192.0, base)


def test_reverse_translated_map_rejects_unrepresentable_subdivision() raises:
    with assert_raises(contains="Float64 road-s resolution"):
        _ = _flat_map(length=81920.0, record_s=1e20, reverse=True)


def test_adjacent_parameters_reject_both_midpoint_rounding_directions() raises:
    # Even and odd endpoint bits make the midpoint select opposite ends.
    for shift in [0.0, 16384.0]:
        for reverse in [False, True]:
            with assert_raises(contains="Float64 road-s resolution"):
                _ = _flat_map(
                    length=16384.0,
                    record_s=Float64(1e20) + shift,
                    reverse=reverse,
                )


def test_aligned_translated_map_keeps_representable_queries() raises:
    # A coarse ULP alone is not a reason to reject an input.
    # Four ULPs have exact quarter points and meet the existing target.
    var base = Float64(1e20)
    var map = _flat_map(length=65536.0, record_s=base)
    assert_equal(map.segment_count(), 1)
    assert_equal(
        map.certified_closest_waypoint_on_road(Vector3(10000, 0.0001, 0))
        .value()
        .s,
        base + 16384.0,
    )
    assert_equal(
        map.certified_closest_waypoint_on_road(Vector3(8192, 0.0001, 0))
        .value()
        .s,
        base,
    )


def test_passing_singleton_does_not_require_an_interior_midpoint() raises:
    var map = _flat_map(length=65536.0, record_s=1e20)
    var first = map.segment(0)[2]
    var transform = map.compute_transform(first)
    # The existing target passes, including at the existing depth cap.
    map._subdivide_segment(transform, transform, first, first, 24)
    assert_equal(map.segment_count(), 2)


def test_advancing_midpoint_keeps_the_existing_depth_limit() raises:
    var base = Float64(1e20)
    var map = _flat_map(length=65536.0, record_s=base)
    var first = map.segment(0)[2]
    var second = first
    second.s = base + 49152.0
    var start = map.compute_transform(first)
    var end = map.compute_transform(second)
    # Three ULPs fail the target but still have an interior midpoint.
    with assert_raises(contains="spatial subdivision limit"):
        map._subdivide_segment(start, end, first, second, 24)
    assert_equal(map.segment_count(), 1)


def test_non_affine_translated_sampling_requires_directed_progress() raises:
    # The exact section endpoints remain B and B + 81920. A nonzero
    # quadratic width takes the non-affine path. Its positive 1 m step
    # rounds to the unchanged s in both lane directions.
    for reverse in [False, True]:
        with assert_raises(contains="Lane index sampling cannot advance"):
            _ = _flat_map(
                length=81920.0,
                record_s=1e20,
                reverse=reverse,
                quadratic_width=True,
            )


def test_terminal_non_affine_sampling_keeps_zero_span_entry() raises:
    # This positive section reaches the existing terminal branch before
    # a 1 m step is requested. Its zero-span index entry remains valid.
    for reverse in [False, True]:
        var map = _flat_map(
            length=0.000001,
            reverse=reverse,
            quadratic_width=True,
        )
        assert_equal(map.segment_count(), 1)
        var segment = map.segment(0)
        assert_equal(segment[2].s, segment[3].s)


def test_ordinary_non_affine_sampling_still_advances() raises:
    for reverse in [False, True]:
        var map = _flat_map(length=3.0, reverse=reverse, quadratic_width=True)
        assert_equal(map.segment_count(), 1)
        var segment = map.segment(0)
        assert_true(segment[2].s != segment[3].s)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
