# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The standalone grouped proof must decline finite-input accumulation overflow."""
from extensions.carla.curve_bounds import _geometry_distance, _spiral_counts
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, with_spiral
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_grouped_accumulation_overflow_is_a_conservative_direct_refusal() raises:
    for unsupported in [False, True]:
        var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
        var station = bitcast[DType.float64](
            UInt64(0x7FEFFFFFFFFFFFFE)
        ) if unsupported else 2.125
        var length = maximum if unsupported else 20.0
        var geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, length), 0.0, 0.0
        )
        var d = _geometry_distance(geometry, _Jet.variable(station, station))
        assert_true(d.rounded_value().is_finite())
        assert_true(d.rounded_value().low > 0.0)
        assert_true(d.rounded_value().high < geometry.length)
        var counts = _spiral_counts(geometry, d)
        if not unsupported:
            assert_equal(counts[0], 4)
            assert_equal(counts[1], 4)
        else:
            # This is an explicit standalone fixed-count rejection, not a
            # count/domain association emitted by canonical construction.
            assert_equal(counts[0], -1)
            assert_equal(counts[1], -1)
        var result = _try_spiral_grouped_roundoff_envelope(
            geometry, d, 1 if unsupported else 4
        )
        assert_equal(Bool(result), not unsupported)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
