# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Direct private-API rejection domains, not canonical caller reachability.

Normal controls retain the original distance/count producers. Rejection cases
intentionally supply unsupported typed inputs to boundaries that validate them.
"""
from extensions.carla.curve_bounds import _geometry_distance, _spiral_counts
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, with_spiral
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope,
)
from extensions.carla.spiral_roundoff_proof import _try_spiral_roundoff_envelope
from extensions.carla.spiral_moment_proof import (
    _try_spiral_moment_expansion as _dynamic_expansion,
)
from extensions.carla.spiral_moment_table import (
    _try_spiral_moment_expansion as _table_expansion,
)
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_true
from tests.test_spiral_moment_guards import _proof as _dynamic_proof
from tests.test_spiral_moment_table_guards import _proof as _table_proof
from tests._spiral_domain_controls import _geometry, _road, _capture


def test_fixed_count_helpers_refuse_large_finite_and_overflowing_phase() raises:
    for variant in range(3):
        var length = 20.0 if variant < 2 else 1e308
        var curvature = (
            0.001 if variant == 0 else 1e10 if variant == 1 else 1e308
        )
        var geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, length), 0.0, curvature
        )
        var station = 2.125 if variant < 2 else 1e200
        var high = 2.25 if variant < 2 else 1.01e200
        var d = _geometry_distance(geometry, _Jet.variable(station, high))
        assert_true(d.rounded_value().is_finite())
        assert_true(d.rounded_value().low > 0.0)
        assert_true(d.rounded_value().high < geometry.length)
        var counts = _spiral_counts(geometry, d)
        if variant == 0:
            assert_equal(counts[0], 4)
            assert_equal(counts[1], 4)
        else:
            # Deliberately unsupported count/domain association: these direct
            # calls must refuse, not stand in for an ordinary query path.
            assert_true(counts[0] != 4 or counts[1] != 4)
        assert_equal(
            Bool(_try_spiral_grouped_roundoff_envelope(geometry, d, 4)),
            variant == 0,
        )
        assert_equal(
            Bool(_try_spiral_roundoff_envelope(geometry, d, 4)), variant == 0
        )


def test_matching_payload_counts_do_not_validate_corrupted_distance() raises:
    var geometry = _geometry()
    var road = _road(geometry.copy())
    var captured = _capture(road, 2.125, 2.25)
    assert_equal(captured.first_count, 4)
    assert_equal(captured.last_count, 4)
    var dynamic = _dynamic_proof(4)
    var table = _table_proof(4)
    for malformed in [False, True]:
        var d = captured.d
        if malformed:
            d.value = _Interval.whole()
            var actual_counts = _spiral_counts(geometry, d)
            assert_equal(actual_counts[0], -1)
            assert_equal(actual_counts[1], -1)
        # Matching count metadata alone must not bless a corrupted Jet.
        assert_equal(
            Bool(
                _dynamic_expansion(
                    dynamic, geometry, d, (4, 4), Vector3(0, 0, 0)
                )
            ),
            not malformed,
        )
        assert_equal(
            Bool(
                _table_expansion(table, geometry, d, (4, 4), Vector3(0, 0, 0))
            ),
            not malformed,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
