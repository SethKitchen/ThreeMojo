# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Native controls for complete stored-graph scalar-error envelopes."""

from extensions.carla.curve_bounds import _geometry_distance, _spiral_counts
from extensions.carla.curve_interval import _Interval, _Jet, _ValueJet
from extensions.carla.geometry import LINE
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from extensions.carla.spiral_domain_proof import (
    _SpiralDomainProof,
    _spiral_proof_branch,
)
from extensions.carla.spiral_roundoff_proof import (
    _try_spiral_roundoff_envelope,
    _sequential_sum_error,
)
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._spiral_domain_controls import _geometry


def _check_counts(begin: Int, end: Int) raises:
    for pieces in range(begin, end):
        var station = Float64(pieces) - 1.5
        for curvature in [-0.001, 0.001]:
            for origin in [0.0, 1000000.0, -1000000.0, 1e20, -1e20]:
                var geometry = _geometry()
                geometry.length = 100.0
                geometry.curvature_end = curvature
                geometry.x = origin
                geometry.y = -origin
                var d = _geometry_distance(
                    geometry, _Jet.variable(station - 0.01, station + 0.01)
                )
                var counts = _spiral_counts(geometry, d)
                assert_equal(counts[0], pieces)
                assert_equal(counts[1], pieces)
                var errors = _try_spiral_roundoff_envelope(
                    geometry, d, pieces
                ).value()
                assert_true(errors[0] >= 0.0 and isfinite(errors[0]))
                assert_true(errors[1] >= 0.0 and isfinite(errors[1]))
                var proof = _SpiralDomainProof(
                    0,
                    0,
                    d.rounded_value(),
                    pieces,
                    pieces,
                    errors[0],
                    errors[1],
                    errors[0],
                    errors[1],
                )
                var whole = _spiral_proof_branch(proof, geometry, d, pieces)
                for step in range(7):
                    var sample = station - 0.01 + 0.02 * Float64(step) / 6.0
                    var point_d = _geometry_distance(
                        geometry, _Jet.variable(sample, sample)
                    )
                    var point = _spiral_proof_branch(
                        proof, geometry, point_d, pieces
                    )
                    var scalar = _lane_geometry_pos_at(geometry, sample)
                    assert_true(whole[0].rounded_value().contains(scalar.x))
                    assert_true(whole[1].rounded_value().contains(scalar.y))
                    assert_true(point[0].rounded_value().contains(scalar.x))
                    assert_true(point[1].rounded_value().contains(scalar.y))


def test_original_scalar_enclosure_counts_2_through_17() raises:
    _check_counts(2, 18)


def test_original_scalar_enclosure_counts_18_through_33() raises:
    _check_counts(18, 34)


def test_original_scalar_enclosure_counts_34_through_49() raises:
    _check_counts(34, 50)


def test_original_scalar_enclosure_counts_50_through_64() raises:
    _check_counts(50, 65)


def test_unsupported_geometry_phase_clamp_count_and_range_refuse() raises:
    var geometry = _geometry()
    var d = _Jet.variable(0.1, 0.2)
    for pieces in [0, 65]:
        assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, pieces)))
    geometry.heading = 0.1
    assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, 2)))
    geometry.heading = 0.0
    geometry.curvature_start = 0.1
    assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, 2)))
    geometry.curvature_start = 0.0
    geometry.length = 0.0
    assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, 2)))
    geometry.length = 20.0
    geometry.x = inf[DType.float64]()
    assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, 2)))
    geometry.x = 0.0
    assert_false(
        Bool(_try_spiral_roundoff_envelope(geometry, _Jet.variable(0, 0.2), 2))
    )
    assert_false(
        Bool(_try_spiral_roundoff_envelope(geometry, _Jet.variable(19, 20), 2))
    )
    geometry.curvature_end = 200.0
    assert_false(
        Bool(_try_spiral_roundoff_envelope(geometry, _Jet.variable(5, 6), 7))
    )
    geometry.kind = LINE
    assert_false(Bool(_try_spiral_roundoff_envelope(geometry, d, 2)))


def test_sequential_sum_envelope_handles_subnormal_and_overflow_edges() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    var value = _ValueJet(
        _Interval(-tiny, tiny), _Interval.whole(), _Interval.whole(), tiny
    )
    var error = _sequential_sum_error(value, 320, 0.0)
    assert_true(isfinite(error))
    assert_true(error >= 320.0 * tiny)
    var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    value = _ValueJet(
        _Interval(-largest, largest), _Interval.whole(), _Interval.whole(), 0.0
    )
    assert_false(isfinite(_sequential_sum_error(value, 320, 0.0)))
    for count in [0, 321]:
        assert_false(
            isfinite(_sequential_sum_error(_ValueJet.constant(1.0), count, 0.0))
        )
    assert_false(
        isfinite(
            _sequential_sum_error(
                _ValueJet.constant(1.0), 5, inf[DType.float64]()
            )
        )
    )
    value.error = -1.0
    assert_false(isfinite(_sequential_sum_error(value, 5, 0.0)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
