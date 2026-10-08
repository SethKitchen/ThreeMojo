# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Unsupported interval ordering must be rejected using actual derived counts."""
from extensions.carla.curve_bounds import (
    _geometry_distance,
    _spiral_counts,
    _try_lane_envelope_capture,
)
from extensions.carla.curve_interval import _Jet
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.spiral_domain_proof import _SpiralRootCapture
from std.testing import TestSuite, assert_equal
from tests._spiral_domain_controls import _geometry, _road
from tests.test_carla_junction_arithmetic_states import _valid


def test_reversed_interval_counts_refuse_without_spending_optional_terms() raises:
    var geometry = _geometry()
    geometry.curvature_end = 0.0
    var road = _road(geometry.copy())
    _valid(road)
    for reversed_interval in [False, True]:
        var low = 2.25 if reversed_interval else 1.25
        var high = 1.25 if reversed_interval else 1.5
        var d = _geometry_distance(geometry, _Jet.variable(low, high))
        var counts = _spiral_counts(geometry, d)
        assert_equal(counts[0], 4 if reversed_interval else 3)
        assert_equal(counts[1], 3)
        var nodes = 7
        var terms = 17
        var grouped = _try_grouped_lane_jet(
            road, 0, 0, low, high, nodes, terms, 100, 10000
        )
        assert_equal(Bool(grouped), not reversed_interval)
        # The generic node reservation precedes interval/count validation.
        assert_equal(nodes, 8)
        assert_equal(terms, 17 if reversed_interval else 26)
        var capture = _SpiralRootCapture()
        terms = 17
        var envelope = _try_lane_envelope_capture(
            road, 0, 0, low, high, capture, terms, 10000
        )
        assert_equal(Bool(envelope), not reversed_interval)
        assert_equal(terms, 17 if reversed_interval else 1041)
        assert_equal(capture.record_at, -1 if reversed_interval else 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
