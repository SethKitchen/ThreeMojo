# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Real producers reach the lane-distance axis and stored-blend loops."""
from extensions.carla.lane_distance import _refinement_square
from extensions.carla.curve_interval import _Jet, _stored_blend_error
from std.math import isfinite
from std.testing import TestSuite, assert_true


def test_all_admitted_axis_instantiations_and_four_float_blend() raises:
    var point: Array[Float64, 3] = [1.0, 2.0, 3.0]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    assert_true(_refinement_square[1](point, query, 1.0).contains(1.0))
    assert_true(_refinement_square[2](point, query, 1.0).contains(5.0))
    assert_true(_refinement_square[3](point, query, 1.0).contains(14.0))
    var error = _stored_blend_error(_Jet.constant(0.5), 1.0, 2.0)
    assert_true(isfinite(error) and error >= 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
