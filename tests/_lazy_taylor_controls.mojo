# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Non-tiny admitted proof fixtures for independent lazy-Taylor controls."""

from extensions.carla.road import Road
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _ClosedInterval,
    _checked_center,
)
from extensions.carla.lane_distance import _refinement_square, _point_gap_scale
from math.vector3 import Vector3
from tests._spiral_acceptance_controls import _acceptance_road


def _diagonal_road(thin_width: Bool = False) raises -> Road:
    var road = _acceptance_road(varying_width=thin_width)
    # X=s and Z=s make the nearest distance require correlated coordinates.
    # Independent coordinate boxes cannot settle an interior off-line query.
    road.info.elevations[0].polynomial = CubicPolynomial(0, 1, 0, 0, 0)
    if thin_width:
        for i in range(len(road.sections[0].lanes[0].info.widths)):
            road.sections[0].lanes[0].info.widths[
                i
            ].polynomial = CubicPolynomial(0.05, 0.01, 0, 0, 0)
        road.info.lane_offsets[0].polynomial = CubicPolynomial(
            0.025, 0.005, 0, 0, 0
        )
    return road^


def _whole_certificate(
    road: Road,
    location: Vector3,
    low: Float64 = 0.4,
    high: Float64 = 0.7,
    seed: Float64 = 0.7,
) raises -> _LaneCertificate:
    var terms = 0
    var point = _checked_center(road, 0, 0, seed, terms, 2000000)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var scale = _point_gap_scale(point, query)
    if scale == 0.0:
        scale = 1.0
    var upper = _refinement_square[3](point, query, scale).high
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(low, high, 0, 0.0, scale)
    ]
    return _LaneCertificate(
        seed, point^, scale, 0.0, upper, False, cells^, 0, terms
    )
