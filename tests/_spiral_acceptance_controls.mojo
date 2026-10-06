# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""New source-only fixtures for admitted SPIRAL acceptance-path controls.

Zero curvature does not select the LINE-only exact solver. Stored s=0.5 has
count 2 and an exact power-of-two quadrature step. The independent Fraction
record in this artifact proves its canonical point exactly, without an ideal
sine approximation or a tolerance-close equality assertion.
"""

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _lane_jet,
    _lane_jet_with_proof,
    _reference_work,
    _spiral_counts,
)
from extensions.carla.curve_interval import _Interval, _Jet, _next_up
from extensions.carla.geometry import RoadGeometry, SPIRAL
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _ClosedInterval,
    _checked_center,
    _chord_certificate_capture,
)
from extensions.carla.lane_distance import _normalized_square
from extensions.carla.map import Map, Controller, Junction, Signal
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    RoadId,
    LaneId,
    SectionId,
    NO_JUNCTION,
    LANE_DRIVING,
    RoadInfoGeometry,
    RoadInfoLaneWidth,
    RoadInfoLaneOffset,
    RoadInfoElevation,
    info_index,
)
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _SpiralDomainProof,
    _try_pack_spiral_proof,
    _spiral_proof_matches,
    _spiral_proof_branch,
    _find_spiral_proof,
)
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import assert_equal, assert_true, assert_false
from tests._spiral_domain_controls import _bits, _jet_bits


def _acceptance_road(
    id: Int = 1,
    y: Float64 = 0.0,
    varying_width: Bool = False,
) raises -> Road:
    var road = Road(
        RoadId(id),
        "admitted SPIRAL acceptance",
        1.0,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    var width = CubicPolynomial.constant(2.0)
    var offset = CubicPolynomial.constant(1.0)
    if varying_width:
        # Identical stored polynomial records are intentional index cuts.
        # Width/2 equals offset by exact binary scaling. A nonzero b keeps
        # the existing projected-seed heuristic off; no policy is changed.
        width = CubicPolynomial(2.0, 0.125, 0.0, 0.0, 0.0)
        offset = CubicPolynomial(1.0, 0.0625, 0.0, 0.0, 0.0)
    for station in [0.0, 0.375, 0.75]:
        road.sections[0].lanes[0].info.widths.append(
            RoadInfoLaneWidth(station, width)
        )
    road.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(SPIRAL, 0.0, 0.0, y, 0.0, 4.0))
    )
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, offset))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    return road^


def _acceptance_map(second_y: Float64 = 0.0) raises -> Map:
    var roads = List[Road]()
    roads.append(_acceptance_road(1, 0.0, True))
    roads.append(_acceptance_road(2, second_y, True))
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def _narrow_high() -> Float64:
    return _next_up(_next_up(Float64(0.5)))


def _capture_acceptance_proof(
    road: Road,
    low: Float64,
    high: Float64,
) raises -> _SpiralDomainProof:
    var terms = 0
    var first = _checked_center(road, 0, 0, low, terms, 2000000)
    var last = _checked_center(road, 0, 0, high, terms, 2000000)
    var captured = _SpiralRootCapture()
    var chord = _chord_certificate_capture(
        road,
        0,
        0,
        low,
        high,
        Vector3(Float32(first[0]), Float32(first[1]), Float32(first[2])),
        Vector3(Float32(last[0]), Float32(last[1]), Float32(last[2])),
        captured,
    )
    var construction = chord[2]
    var units = 0
    var found = _try_pack_spiral_proof(
        road,
        low,
        high,
        0,
        captured,
        0,
        construction,
        units,
    )
    assert_true(Bool(found))
    assert_equal(found.value().first_count, 2)
    assert_equal(found.value().last_count, 2)
    return found.value()


def _assert_acceptance_hit(
    road: Road,
    low: Float64,
    high: Float64,
    proof: _SpiralDomainProof,
) raises:
    var at = info_index(road.info.geometries, low)
    assert_equal(at, info_index(road.info.geometries, high))
    ref record = road.info.geometries[at]
    var d = _geometry_distance(
        record.geometry, _Jet.variable(low, high) - _Jet.constant(record.s)
    )
    var counts = _spiral_counts(record.geometry, d)
    assert_equal(counts[0], 2)
    assert_equal(counts[1], 2)
    assert_equal(_reference_work(road, low, high), 10)
    assert_true(
        _spiral_proof_matches(
            proof,
            record.geometry,
            at,
            low,
            high,
            low,
            high,
            d,
            counts,
        )
    )
    var reference = _spiral_proof_branch(proof, record.geometry, d, 2)
    var actual = _lane_jet_with_proof(road, 0, 0, low, high, low, high, proof)
    # Heading is exactly zero. Multiplication by its zero sine leaves the
    # entire X jet unchanged even for the varying-width fixture. Equality
    # with the moment branch checks the actual branch result, not just the
    # existence of an Optional record. Generic first bounds are wider.
    _jet_bits(actual[0], reference[0])
    var generic = _lane_jet(road, 0, 0, low, high)
    assert_true(
        bitcast[DType.uint64](actual[0].first.low)
        != bitcast[DType.uint64](generic[0].first.low)
        or bitcast[DType.uint64](actual[0].first.high)
        != bitcast[DType.uint64](generic[0].first.high)
    )


def _initial_acceptance_certificate(
    road: Road,
    location: Vector3,
) raises -> _LaneCertificate:
    var terms = 0
    var point = _checked_center(road, 0, 0, 0.5, terms, 2000000)
    _bits(point[0], 0.5)
    assert_equal(point[1], 0.0)
    assert_equal(point[2], 0.0)
    assert_equal(terms, 10)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var upper = _normalized_square[3](point, query, 1.0).high
    # This is a complete initial cover of the declared three-value domain.
    # No hard exclusion is invented and no pre-existing depth is reset.
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(0.5, _narrow_high(), 0, 0.0, 1.0)
    ]
    return _LaneCertificate(
        0.5,
        point^,
        1.0,
        0.0,
        upper,
        False,
        cells^,
        0,
        terms,
    )


def _map_proof_segment(map: Map, road_id: RoadId) raises -> Int:
    for index in range(map.segment_count()):
        var segment = map.segment(index)
        if segment[2].road_id != road_id:
            continue
        var low = min(segment[2].s, segment[3].s)
        var high = max(segment[2].s, segment[3].s)
        if low < 0.5 and high > 0.5:
            var found = _find_spiral_proof(map._spiral_proofs, index)
            assert_true(Bool(found))
            assert_equal(found.value().segment_index, index)
            return index
    raise Error("Missing admitted SPIRAL interior segment")
