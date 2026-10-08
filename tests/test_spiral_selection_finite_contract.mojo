# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Preserve complete predecessor results at supported and malformed boundaries."""
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, with_spiral
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope as _grouped,
)
from extensions.carla.spiral_roundoff_proof import (
    _try_spiral_roundoff_envelope as _roundoff,
)
from tests._reference_grouped_selection import (
    _try_spiral_grouped_roundoff_envelope as _old_grouped,
)
from tests._reference_roundoff_selection import (
    _try_spiral_roundoff_envelope as _old_roundoff,
)
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true, assert_false


def _same(
    one: Optional[Tuple[Float64, Float64]],
    two: Optional[Tuple[Float64, Float64]],
) raises:
    assert_equal(Bool(one), Bool(two))
    if one:
        assert_equal(
            bitcast[DType.uint64](one.value()[0]),
            bitcast[DType.uint64](two.value()[0]),
        )
        assert_equal(
            bitcast[DType.uint64](one.value()[1]),
            bitcast[DType.uint64](two.value()[1]),
        )


def test_normal_and_reversed_inputs_preserve_all_returned_bits() raises:
    for curvature in [-4.0, 0.0, 0.05, 1e10]:
        var geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 20.0), 0.0, curvature
        )
        for fault in range(9):
            var d = _Jet.variable(2.125, 2.25)
            if fault == 1:
                d.value = _Interval(2.25, 1.25)
            elif fault == 2:
                d.error = 1e-15
            elif fault == 3:
                d = _Jet.variable(1e-200, 2e-200)
            elif fault == 4:
                d = _Jet.variable(0.0, 0.25)
            elif fault == 5:
                d.value = _Interval.whole()
            elif fault == 6:
                d.value = _Interval(inf[DType.float64](), -inf[DType.float64]())
                d.error = 1.0
            elif fault == 7:
                d.error = -1e-6
            elif fault == 8:
                d.error = -inf[DType.float64]()
            for count in [1, 4, 64]:
                _same(
                    _grouped(geometry, d, count),
                    _old_grouped(geometry, d, count),
                )
                _same(
                    _roundoff(geometry, d, count),
                    _old_roundoff(geometry, d, count),
                )


def test_finite_overflow_domains_keep_complete_predecessor_refusals() raises:
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    for rate in [0.0, 1.0]:
        var geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, maximum),
            0.0,
            maximum * rate,
        )
        for station in [
            1e200,
            bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFE)),
        ]:
            var d = _Jet.variable(station, station)
            for count in [1, 4, 64]:
                _same(
                    _grouped(geometry, d, count),
                    _old_grouped(geometry, d, count),
                )
                _same(
                    _roundoff(geometry, d, count),
                    _old_roundoff(geometry, d, count),
                )


def test_ordering_boundary_distinction_and_canonical_positive_control() raises:
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 20.0), 0.0, 0.0
    )
    var normal = _Jet.variable(2.125, 2.25)
    assert_true(Bool(_grouped(geometry, normal, 4)))
    assert_true(Bool(_roundoff(geometry, normal, 4)))
    var reversed = _Jet.variable(2.25, 1.25)
    assert_false(Bool(_grouped(geometry, reversed, 4)))
    assert_true(Bool(_roundoff(geometry, reversed, 4)))
    _same(
        _roundoff(geometry, reversed, 4), _old_roundoff(geometry, reversed, 4)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
