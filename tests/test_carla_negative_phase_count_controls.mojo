# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Canonical-count controls for a finite negative quadrant transition."""
from extensions.carla.curve_bounds import _geometry_distance, _spiral_counts
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, with_spiral
from extensions.carla.spiral_roundoff_proof import _try_spiral_roundoff_envelope
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope,
)
from tests._spiral_domain_controls import _road
from tests.test_carla_junction_arithmetic_states import _valid
from std.testing import TestSuite, assert_equal, assert_true


def test_negative_quadrant_transition_uses_actual_count_union() raises:
    for curvature in [-0.001, -4.0]:
        var geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 20.0), 0.0, curvature
        )
        var road = _road(geometry.copy())
        _valid(road)
        var d = _geometry_distance(geometry, _Jet.variable(4.0, 4.01))
        var counts = _spiral_counts(geometry, d)
        assert_true(counts[0] >= 1)
        assert_true(counts[1] <= 64)
        assert_true(counts[0] <= counts[1])
        for pieces in range(counts[0], counts[1] + 1):
            assert_equal(
                Bool(_try_spiral_roundoff_envelope(geometry, d, pieces)),
                curvature == -0.001,
            )
            assert_equal(
                Bool(
                    _try_spiral_grouped_roundoff_envelope(geometry, d, pieces)
                ),
                curvature == -0.001,
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
