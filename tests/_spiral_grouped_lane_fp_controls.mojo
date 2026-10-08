# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Checks called inside the maintained saved/restored hostile CPU-mode suite."""

from extensions.carla.curve_bounds import _lane_jet_model_proof
from extensions.carla.spiral_domain_proof import (
    _SpiralDomainProof,
    _SpiralRootCapture,
)
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.testing import assert_equal, assert_false


def _assert_grouped_lane_refuses_hostile_state(
    road: Road,
    proof: _SpiralDomainProof,
) raises:
    var nodes = 7
    var terms = 11
    assert_false(
        Bool(
            _try_grouped_lane_jet(
                road, 0, 0, 0.4, 0.7, nodes, terms, 100, 10000
            )
        )
    )
    assert_equal(nodes, 7)
    assert_equal(terms, 11)
    var captured = _SpiralRootCapture()
    var point = _lane_jet_model_proof[False](
        road,
        0,
        0,
        0.4,
        0.7,
        Vector3(0, 0, 0),
        proof,
        0.4,
        0.7,
        captured,
        require_reuse=True,
    )
    assert_false(point[0].rounded_value().is_finite())
    assert_equal(captured.record_at, -1)
