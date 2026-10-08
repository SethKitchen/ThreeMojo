# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The grouped proof refuses an overflowing finite raw error allowance."""
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope,
)
from std.math import isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true
from tests._spiral_domain_controls import _geometry, _road, _capture


def test_finite_raw_error_can_make_the_rounded_domain_nonfinite() raises:
    var road = _road(_geometry())
    var captured = _capture(road, 2.125, 2.25)
    assert_equal(captured.first_count, 4)
    assert_equal(captured.last_count, 4)
    for unsupported in [False, True]:
        var d = captured.d
        if unsupported:
            # A typed unsupported allowance at this direct validation boundary,
            # not a claim that canonical distance construction returns it.
            d.error = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
        assert_true(d.value.is_finite())
        assert_true(isfinite(d.error))
        assert_true(d.error >= 0.0)
        assert_equal(d.rounded_value().is_finite(), not unsupported)
        assert_equal(
            Bool(
                _try_spiral_grouped_roundoff_envelope(
                    road.info.geometries[0].geometry, d, captured.first_count
                )
            ),
            not unsupported,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
