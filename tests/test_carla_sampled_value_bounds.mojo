# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact value/error and four-cell equivalence after derivative elision."""

from extensions.carla.curve_bounds import _lane_jet, _sample_jet
from extensions.carla.curve_interval import _Jet, _ValueJet
from extensions.carla.geometry import POLY3, PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_value_bounds import (
    _sampled_lane_value_bound,
    _sample_value,
)
from extensions.carla.lane_box_cover import (
    _sampled_lane_box_cover,
    _sampled_lane_box_cover_fast,
)
from extensions.carla.lane_refinement import _midpoint
from extensions.carla.opendrive import load_opendrive_file
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests.test_carla_sampled_box_cover import _boxes
from tests.test_carla_scaled_lane_refinement import _scaled_road


def _equal_value(full: _Jet, value: _ValueJet) raises:
    assert_equal(
        bitcast[DType.uint64](full.value.low),
        bitcast[DType.uint64](value.value.low),
    )
    assert_equal(
        bitcast[DType.uint64](full.value.high),
        bitcast[DType.uint64](value.value.high),
    )
    assert_equal(
        bitcast[DType.uint64](full.error), bitcast[DType.uint64](value.error)
    )
    assert_equal(
        bitcast[DType.uint64](full.rounded_value().low),
        bitcast[DType.uint64](value.rounded_value().low),
    )
    assert_equal(
        bitcast[DType.uint64](full.rounded_value().high),
        bitcast[DType.uint64](value.rounded_value().high),
    )
    assert_false(value.first.is_finite())
    assert_false(value.second.is_finite())


def test_every_town_sampled_cover_and_error_word_matches_full_jet() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var covers = 0
    for segment in map._segments:
        if segment.cover_index < 0:
            continue
        var at = map._locate(segment.first)
        ref road = map.roads[at[0]]
        var lo = min(segment.first.s, segment.second.s)
        var hi = max(segment.first.s, segment.second.s)
        var mid = _midpoint(lo, hi)
        var edges: Array[Float64, 5] = [
            lo,
            _midpoint(lo, mid),
            mid,
            _midpoint(mid, hi),
            hi,
        ]
        var old_terms = 0
        var new_terms = 0
        var before = _sampled_lane_box_cover(
            road, at[1], at[2], lo, hi, old_terms
        ).value()
        var after = _sampled_lane_box_cover_fast(
            road, at[1], at[2], lo, hi, new_terms
        ).value()
        assert_equal(old_terms, new_terms)
        assert_equal(old_terms, 4)
        var old_boxes = _boxes(before)
        var new_boxes = _boxes(after)
        for cell in range(4):
            var full = _lane_jet(
                road, at[1], at[2], edges[cell], edges[cell + 1]
            )
            var value = _sampled_lane_value_bound(
                road, at[1], at[2], edges[cell], edges[cell + 1]
            )
            _equal_value(full[0], value[0])
            assert_equal(
                bitcast[DType.uint64](old_boxes[cell][0].low),
                bitcast[DType.uint64](new_boxes[cell][0].low),
            )
            assert_equal(
                bitcast[DType.uint64](old_boxes[cell][0].high),
                bitcast[DType.uint64](new_boxes[cell][0].high),
            )
            _equal_value(full[1], value[1])
            assert_equal(
                bitcast[DType.uint64](old_boxes[cell][1].low),
                bitcast[DType.uint64](new_boxes[cell][1].low),
            )
            assert_equal(
                bitcast[DType.uint64](old_boxes[cell][1].high),
                bitcast[DType.uint64](new_boxes[cell][1].high),
            )
            _equal_value(full[2], value[2])
            assert_equal(
                bitcast[DType.uint64](old_boxes[cell][2].low),
                bitcast[DType.uint64](new_boxes[cell][2].low),
            )
            assert_equal(
                bitcast[DType.uint64](old_boxes[cell][2].high),
                bitcast[DType.uint64](new_boxes[cell][2].high),
            )
        covers += 1
    assert_equal(covers, 485)


def test_sampled_value_keeps_scale_signed_zero_and_branch_bounds() raises:
    for scale in [Float64(1e-200), Float64(1.0), Float64(1e200)]:
        var road = _scaled_road(scale)
        for kind in [POLY3, PARAM_POLY3]:
            road.info.geometries[0].geometry.kind = kind
            for i in range(4):
                var lo = Float64(i) * 0.25
                var hi = lo + 0.25
                var full = _lane_jet(road, 0, 0, lo, hi)
                var value = _sampled_lane_value_bound(road, 0, 0, lo, hi)
                _equal_value(full[0], value[0])
                _equal_value(full[1], value[1])
                _equal_value(full[2], value[2])
    for horizontal in [-1.0, 0.0, 1.0]:
        for vertical in [-2.0, -0.0, 0.0, 2.0]:
            var geometry = RoadGeometry(PARAM_POLY3, 0, 1e6, -1e6, 0.3, 1)
            geometry.samples.append(_Sample(0, 0, 0, horizontal, vertical))
            geometry.samples.append(_Sample(1, 1, 1, -horizontal, -vertical))
            for i in range(4):
                var lo = Float64(i) * 0.25
                var hi = lo + 0.25
                var full = _sample_jet(
                    geometry, _Jet.variable(lo, hi), 0, Vector3(0, 0, 0)
                )
                var value = _sample_value(
                    geometry, _ValueJet.variable(lo, hi), 0, Vector3(0, 0, 0)
                )
                _equal_value(full[0], value[0])

                _equal_value(full[1], value[1])

                _equal_value(full[2], value[2])


def test_value_cover_preserves_optional_budget_and_failure() raises:
    var road = _scaled_road(1.0)
    for cap in range(5):
        var old_terms = 0
        var new_terms = 0
        var before = _sampled_lane_box_cover(road, 0, 0, 0, 1, old_terms, cap)
        var after = _sampled_lane_box_cover_fast(
            road, 0, 0, 0, 1, new_terms, cap
        )
        assert_equal(Bool(before), Bool(after))
        assert_equal(old_terms, new_terms)
        assert_equal(new_terms, cap)
    _ = road.sections[0].lanes[0].info.widths.pop()
    var old_terms = 0
    var new_terms = 0
    assert_false(Bool(_sampled_lane_box_cover(road, 0, 0, 0, 1, old_terms)))
    assert_false(
        Bool(_sampled_lane_box_cover_fast(road, 0, 0, 0, 1, new_terms))
    )
    assert_equal(old_terms, 1)
    assert_equal(new_terms, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
