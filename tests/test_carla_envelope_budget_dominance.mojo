# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Original entry refusal and count-union debit remain the budget authority."""
from extensions.carla.curve_bounds import _try_lane_envelope_capture
from extensions.carla.spiral_domain_proof import _SpiralRootCapture
from std.testing import TestSuite, assert_equal, assert_false
from tests.test_carla_spiral_envelope_capture import _eligible_road


def test_invalid_budget_states_leave_counters_and_capture_unchanged() raises:
    var road = _eligible_road()
    for state in [(-1, 2048), (10, 9), (0, -1)]:
        var spent = state[0]
        var capture = _SpiralRootCapture()
        assert_false(
            Bool(
                _try_lane_envelope_capture(
                    road, 0, 0, 0.1, 0.2, capture, spent, state[1]
                )
            )
        )
        assert_equal(spent, state[0])
        assert_equal(capture.record_at, -1)


def test_exact_one_and_two_branch_admission_keeps_full_debit() raises:
    var road = _eligible_road()
    road.info.geometries[0].geometry.curvature_end = 0.0
    for branches in [1, 2]:
        var low = 0.1 if branches == 1 else 0.99
        var high = 0.2 if branches == 1 else 1.01
        var work = 1024 * branches
        for delta in [-1, 0, 1]:
            var spent = 17
            var capture = _SpiralRootCapture()
            var result = _try_lane_envelope_capture(
                road, 0, 0, low, high, capture, spent, 17 + work + delta
            )
            assert_equal(Bool(result), delta >= 0)
            assert_equal(spent, 17 + work if delta >= 0 else 17)
            assert_equal(capture.record_at, 0 if delta >= 0 else -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
