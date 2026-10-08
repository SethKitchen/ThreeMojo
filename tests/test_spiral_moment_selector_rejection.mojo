# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""One explicit malformed-input refusal; not a general validation guarantee."""
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, with_spiral
from extensions.carla.spiral_moment_proof import _all_spiral_nodes_quadrant_zero
from std.testing import TestSuite, assert_true, assert_false
from tests._spiral_domain_controls import _geometry


def test_negative_error_selector_overflow_retains_conservative_refusal() raises:
    var normal = _geometry()
    var d = _Jet.variable(2.125, 2.125)
    assert_true(_all_spiral_nodes_quadrant_zero(normal, d, 4))
    var unsupported = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 20.0), -1.0, -1.0
    )
    d.error = -2.125
    # Explicit unsupported direct input. The helper must not claim quadrant
    # zero for this case; other malformed inputs may violate caller contracts
    # without triggering this particular rejection.
    assert_false(_all_spiral_nodes_quadrant_zero(unsupported, d, 4))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
