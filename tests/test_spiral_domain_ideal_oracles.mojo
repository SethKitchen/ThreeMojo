# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent exact stored-polynomial controls for retained root errors.

The first 96 value/first/second brackets are unchanged from the qualified
zero-translation exact-rational oracle fixtures. Their generator distributed
the literal GL/trig polynomial independently of the moment table. Root and
child enclosures must both contain each bracket. Canonical rounded centers
are checked separately; no ideal sine or fitted scalar replaces them.
A final nonzero-record-station control reuses the six exact count-3 brackets
with the original station-subtraction graph. No duration, workload, search cap,
or tolerance is changed by this new suite.
"""

from extensions.carla.curve_bounds import (
    _geometry_distance, _spiral_counts, _reference_jet, _lane_jet_with_proof,
)
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import RoadGeometry, _GL_NODES
from extensions.carla.curve_trig import _INV_HALF_PI, _PHASE_LIMIT
from extensions.carla.spiral_domain_proof import (
    _spiral_proof_matches, _spiral_proof_branch,
)
from math.vector3 import Vector3
from std.math import floor, isfinite
from std.testing import TestSuite, assert_true, assert_equal
from tests._spiral_domain_controls import (
    _f64, _encloses, _jet_bits, _bits, _geometry, _road, _proof,
    _canonical_contains,
)

def _each_original_node_quadrant_zero(geometry: RoadGeometry, d: _Jet, pieces: Int) raises:
    # Independent enumeration of the original rounded operation graph.
    # The proof's constant-time envelope is not reused to establish this fact.
    var nodes = materialize[_GL_NODES]()
    var rate = _Jet.constant((geometry.curvature_end - geometry.curvature_start) / geometry.length)
    var step = d / _Jet.constant(Float64(pieces))
    for piece in range(pieces):
        var start = step * _Jet.constant(Float64(piece))
        for i in range(5):
            var t = start + step * _Jet.constant(0.5) * _Jet.constant(1.0 + nodes[i])
            var theta = _Jet.constant(geometry.heading) + t * (
                _Jet.constant(geometry.curvature_start) + _Jet.constant(0.5) * rate * t
            )
            var phase = theta.rounded_value()
            assert_true(phase.is_finite())
            assert_true(phase.magnitude() <= _PHASE_LIMIT)
            var selection = (theta * _Jet.constant(_INV_HALF_PI) + _Jet.constant(0.5)).rounded_value()
            assert_equal(floor(selection.low), 0.0)
            assert_equal(floor(selection.high), 0.0)

def test_root_error_ideal_hot2_before() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x3FFFFFFFEBFA8A91))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 4)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FFFFFFAADCD9E8E), UInt64(0x3FFFFFFAADCD9E8F))
    _encloses(candidate[0].value, UInt64(0x3FFFFFFAADCD9E8E), UInt64(0x3FFFFFFAADCD9E8F))
    _encloses(root[0].value, UInt64(0x3FFFFFFAADCD9E8E), UInt64(0x3FFFFFFAADCD9E8F))
    _encloses(original[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(candidate[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(root[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(original[0].second, UInt64(0xBEFA36DB9163AEE7), UInt64(0xBEFA36DB9163AEE6))
    _encloses(candidate[0].second, UInt64(0xBEFA36DB9163AEE7), UInt64(0xBEFA36DB9163AEE6))
    _encloses(root[0].second, UInt64(0xBEFA36DB9163AEE7), UInt64(0xBEFA36DB9163AEE6))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(candidate[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(root[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(original[1].first, UInt64(0x3F747ADB9666283C), UInt64(0x3F747ADB9666283D))
    _encloses(candidate[1].first, UInt64(0x3F747ADB9666283C), UInt64(0x3F747ADB9666283D))
    _encloses(root[1].first, UInt64(0x3F747ADB9666283C), UInt64(0x3F747ADB9666283D))
    _encloses(original[1].second, UInt64(0x3F747AD073E8A781), UInt64(0x3F747AD073E8A782))
    _encloses(candidate[1].second, UInt64(0x3F747AD073E8A781), UInt64(0x3F747AD073E8A782))
    _encloses(root[1].second, UInt64(0x3F747AD073E8A781), UInt64(0x3F747AD073E8A782))


def test_root_error_ideal_hot2_exact() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x3FFFFFFFEBFA8A92))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 4)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FFFFFFAADCD9E8F), UInt64(0x3FFFFFFAADCD9E90))
    _encloses(candidate[0].value, UInt64(0x3FFFFFFAADCD9E8F), UInt64(0x3FFFFFFAADCD9E90))
    _encloses(root[0].value, UInt64(0x3FFFFFFAADCD9E8F), UInt64(0x3FFFFFFAADCD9E90))
    _encloses(original[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(candidate[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(root[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(original[0].second, UInt64(0xBEFA36DB9163AEE9), UInt64(0xBEFA36DB9163AEE8))
    _encloses(candidate[0].second, UInt64(0xBEFA36DB9163AEE9), UInt64(0xBEFA36DB9163AEE8))
    _encloses(root[0].second, UInt64(0xBEFA36DB9163AEE9), UInt64(0xBEFA36DB9163AEE8))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(candidate[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(root[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(original[1].first, UInt64(0x3F747ADB9666283D), UInt64(0x3F747ADB9666283E))
    _encloses(candidate[1].first, UInt64(0x3F747ADB9666283D), UInt64(0x3F747ADB9666283E))
    _encloses(root[1].first, UInt64(0x3F747ADB9666283D), UInt64(0x3F747ADB9666283E))
    _encloses(original[1].second, UInt64(0x3F747AD073E8A781), UInt64(0x3F747AD073E8A782))
    _encloses(candidate[1].second, UInt64(0x3F747AD073E8A781), UInt64(0x3F747AD073E8A782))
    _encloses(root[1].second, UInt64(0x3F747AD073E8A781), UInt64(0x3F747AD073E8A782))


def test_root_error_ideal_hot2_after() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x3FFFFFFFEBFA8A93))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 4)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FFFFFFAADCD9E90), UInt64(0x3FFFFFFAADCD9E91))
    _encloses(candidate[0].value, UInt64(0x3FFFFFFAADCD9E90), UInt64(0x3FFFFFFAADCD9E91))
    _encloses(root[0].value, UInt64(0x3FFFFFFAADCD9E90), UInt64(0x3FFFFFFAADCD9E91))
    _encloses(original[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(candidate[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(root[0].first, UInt64(0x3FEFFFE5C920EAC1), UInt64(0x3FEFFFE5C920EAC2))
    _encloses(original[0].second, UInt64(0xBEFA36DB9163AEEC), UInt64(0xBEFA36DB9163AEEB))
    _encloses(candidate[0].second, UInt64(0xBEFA36DB9163AEEC), UInt64(0xBEFA36DB9163AEEB))
    _encloses(root[0].second, UInt64(0xBEFA36DB9163AEEC), UInt64(0xBEFA36DB9163AEEB))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(candidate[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(root[1].value, UInt64(0x405900369CFC9F20), UInt64(0x405900369CFC9F21))
    _encloses(original[1].first, UInt64(0x3F747ADB9666283F), UInt64(0x3F747ADB96662840))
    _encloses(candidate[1].first, UInt64(0x3F747ADB9666283F), UInt64(0x3F747ADB96662840))
    _encloses(root[1].first, UInt64(0x3F747ADB9666283F), UInt64(0x3F747ADB96662840))
    _encloses(original[1].second, UInt64(0x3F747AD073E8A782), UInt64(0x3F747AD073E8A783))
    _encloses(candidate[1].second, UInt64(0x3F747AD073E8A782), UInt64(0x3F747AD073E8A783))
    _encloses(root[1].second, UInt64(0x3F747AD073E8A782), UInt64(0x3F747AD073E8A783))


def test_root_error_ideal_hot5_before() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x4014000006279A30))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 7)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x4013FF8007A2156F), UInt64(0x4013FF8007A21570))
    _encloses(candidate[0].value, UInt64(0x4013FF8007A2156F), UInt64(0x4013FF8007A21570))
    _encloses(root[0].value, UInt64(0x4013FF8007A2156F), UInt64(0x4013FF8007A21570))
    _encloses(original[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(candidate[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(root[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(original[0].second, UInt64(0xBF399888A392577B), UInt64(0xBF399888A392577A))
    _encloses(candidate[0].second, UInt64(0xBF399888A392577B), UInt64(0xBF399888A392577A))
    _encloses(root[0].second, UInt64(0xBF399888A392577B), UInt64(0xBF399888A392577A))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(candidate[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(root[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(original[1].first, UInt64(0x3F9FFEAAC29E5FA8), UInt64(0x3F9FFEAAC29E5FA9))
    _encloses(candidate[1].first, UInt64(0x3F9FFEAAC29E5FA8), UInt64(0x3F9FFEAAC29E5FA9))
    _encloses(root[1].first, UInt64(0x3F9FFEAAC29E5FA8), UInt64(0x3F9FFEAAC29E5FA9))
    _encloses(original[1].second, UInt64(0x3F8996667F532C1F), UInt64(0x3F8996667F532C20))
    _encloses(candidate[1].second, UInt64(0x3F8996667F532C1F), UInt64(0x3F8996667F532C20))
    _encloses(root[1].second, UInt64(0x3F8996667F532C1F), UInt64(0x3F8996667F532C20))


def test_root_error_ideal_hot5_exact() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x4014000006279A31))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 7)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x4013FF8007A21570), UInt64(0x4013FF8007A21571))
    _encloses(candidate[0].value, UInt64(0x4013FF8007A21570), UInt64(0x4013FF8007A21571))
    _encloses(root[0].value, UInt64(0x4013FF8007A21570), UInt64(0x4013FF8007A21571))
    _encloses(original[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(candidate[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(root[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(original[0].second, UInt64(0xBF399888A392577E), UInt64(0xBF399888A392577D))
    _encloses(candidate[0].second, UInt64(0xBF399888A392577E), UInt64(0xBF399888A392577D))
    _encloses(root[0].second, UInt64(0xBF399888A392577E), UInt64(0xBF399888A392577D))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(candidate[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(root[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(original[1].first, UInt64(0x3F9FFEAAC29E5FAB), UInt64(0x3F9FFEAAC29E5FAC))
    _encloses(candidate[1].first, UInt64(0x3F9FFEAAC29E5FAB), UInt64(0x3F9FFEAAC29E5FAC))
    _encloses(root[1].first, UInt64(0x3F9FFEAAC29E5FAB), UInt64(0x3F9FFEAAC29E5FAC))
    _encloses(original[1].second, UInt64(0x3F8996667F532C20), UInt64(0x3F8996667F532C21))
    _encloses(candidate[1].second, UInt64(0x3F8996667F532C20), UInt64(0x3F8996667F532C21))
    _encloses(root[1].second, UInt64(0x3F8996667F532C20), UInt64(0x3F8996667F532C21))


def test_root_error_ideal_hot5_after() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x4014000006279A32))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 7)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x4013FF8007A21571), UInt64(0x4013FF8007A21572))
    _encloses(candidate[0].value, UInt64(0x4013FF8007A21571), UInt64(0x4013FF8007A21572))
    _encloses(root[0].value, UInt64(0x4013FF8007A21571), UInt64(0x4013FF8007A21572))
    _encloses(original[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(candidate[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(root[0].first, UInt64(0x3FEFFC0015503B8C), UInt64(0x3FEFFC0015503B8D))
    _encloses(original[0].second, UInt64(0xBF399888A3925782), UInt64(0xBF399888A3925781))
    _encloses(candidate[0].second, UInt64(0xBF399888A3925782), UInt64(0xBF399888A3925781))
    _encloses(root[0].second, UInt64(0xBF399888A3925782), UInt64(0xBF399888A3925781))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(candidate[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(root[1].value, UInt64(0x40590355461B9439), UInt64(0x40590355461B943A))
    _encloses(original[1].first, UInt64(0x3F9FFEAAC29E5FAE), UInt64(0x3F9FFEAAC29E5FAF))
    _encloses(candidate[1].first, UInt64(0x3F9FFEAAC29E5FAE), UInt64(0x3F9FFEAAC29E5FAF))
    _encloses(root[1].first, UInt64(0x3F9FFEAAC29E5FAE), UInt64(0x3F9FFEAAC29E5FAF))
    _encloses(original[1].second, UInt64(0x3F8996667F532C22), UInt64(0x3F8996667F532C23))
    _encloses(candidate[1].second, UInt64(0x3F8996667F532C22), UInt64(0x3F8996667F532C23))
    _encloses(root[1].second, UInt64(0x3F8996667F532C22), UInt64(0x3F8996667F532C23))


def test_root_error_ideal_eighth() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x3FC0000000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 2)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FBFFFFFFFFAC1D3), UInt64(0x3FBFFFFFFFFAC1D4))
    _encloses(candidate[0].value, UInt64(0x3FBFFFFFFFFAC1D3), UInt64(0x3FBFFFFFFFFAC1D4))
    _encloses(root[0].value, UInt64(0x3FBFFFFFFFFAC1D3), UInt64(0x3FBFFFFFFFFAC1D4))
    _encloses(original[0].first, UInt64(0x3FEFFFFFFFE5C91D), UInt64(0x3FEFFFFFFFE5C91E))
    _encloses(candidate[0].first, UInt64(0x3FEFFFFFFFE5C91D), UInt64(0x3FEFFFFFFFE5C91E))
    _encloses(root[0].first, UInt64(0x3FEFFFFFFFE5C91D), UInt64(0x3FEFFFFFFFE5C91E))
    _encloses(original[0].second, UInt64(0xBE3A36E2EB151AA9), UInt64(0xBE3A36E2EB151AA8))
    _encloses(candidate[0].second, UInt64(0xBE3A36E2EB151AA9), UInt64(0xBE3A36E2EB151AA8))
    _encloses(root[0].second, UInt64(0xBE3A36E2EB151AA9), UInt64(0xBE3A36E2EB151AA8))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x405900000369D036), UInt64(0x405900000369D037))
    _encloses(candidate[1].value, UInt64(0x405900000369D036), UInt64(0x405900000369D037))
    _encloses(root[1].value, UInt64(0x405900000369D036), UInt64(0x405900000369D037))
    _encloses(original[1].first, UInt64(0x3EF47AE147A87CD3), UInt64(0x3EF47AE147A87CD4))
    _encloses(candidate[1].first, UInt64(0x3EF47AE147A87CD3), UInt64(0x3EF47AE147A87CD4))
    _encloses(root[1].first, UInt64(0x3EF47AE147A87CD3), UInt64(0x3EF47AE147A87CD4))
    _encloses(original[1].second, UInt64(0x3F347AE1479D4D83), UInt64(0x3F347AE1479D4D84))
    _encloses(candidate[1].second, UInt64(0x3F347AE1479D4D83), UInt64(0x3F347AE1479D4D84))
    _encloses(root[1].second, UInt64(0x3F347AE1479D4D83), UInt64(0x3F347AE1479D4D84))


def test_root_error_ideal_half() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x3FE0000000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 2)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FDFFFFFFAC1D29E), UInt64(0x3FDFFFFFFAC1D29F))
    _encloses(candidate[0].value, UInt64(0x3FDFFFFFFAC1D29E), UInt64(0x3FDFFFFFFAC1D29F))
    _encloses(root[0].value, UInt64(0x3FDFFFFFFAC1D29E), UInt64(0x3FDFFFFFFAC1D29F))
    _encloses(original[0].first, UInt64(0x3FEFFFFFE5C91D19), UInt64(0x3FEFFFFFE5C91D1A))
    _encloses(candidate[0].first, UInt64(0x3FEFFFFFE5C91D19), UInt64(0x3FEFFFFFE5C91D1A))
    _encloses(root[0].first, UInt64(0x3FEFFFFFE5C91D19), UInt64(0x3FEFFFFFE5C91D1A))
    _encloses(original[0].second, UInt64(0xBE9A36E2E3F3BE38), UInt64(0xBE9A36E2E3F3BE37))
    _encloses(candidate[0].second, UInt64(0xBE9A36E2E3F3BE38), UInt64(0xBE9A36E2E3F3BE37))
    _encloses(root[0].second, UInt64(0xBE9A36E2E3F3BE38), UInt64(0xBE9A36E2E3F3BE37))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x40590000DA740D8D), UInt64(0x40590000DA740D8E))
    _encloses(candidate[1].value, UInt64(0x40590000DA740D8D), UInt64(0x40590000DA740D8E))
    _encloses(root[1].value, UInt64(0x40590000DA740D8D), UInt64(0x40590000DA740D8E))
    _encloses(original[1].first, UInt64(0x3F347AE142166C9B), UInt64(0x3F347AE142166C9C))
    _encloses(candidate[1].first, UInt64(0x3F347AE142166C9B), UInt64(0x3F347AE142166C9C))
    _encloses(root[1].first, UInt64(0x3F347AE142166C9B), UInt64(0x3F347AE142166C9C))
    _encloses(original[1].second, UInt64(0x3F547AE136E71CDC), UInt64(0x3F547AE136E71CDD))
    _encloses(candidate[1].second, UInt64(0x3F547AE136E71CDC), UInt64(0x3F547AE136E71CDD))
    _encloses(root[1].second, UInt64(0x3F547AE136E71CDC), UInt64(0x3F547AE136E71CDD))


def test_root_error_ideal_nine_eighth() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x4022400000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 11)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x40223AF0FADB699B), UInt64(0x40223AF0FADB699C))
    _encloses(candidate[0].value, UInt64(0x40223AF0FADB699B), UInt64(0x40223AF0FADB699C))
    _encloses(root[0].value, UInt64(0x40223AF0FADB699B), UInt64(0x40223AF0FADB699C))
    _encloses(original[0].first, UInt64(0x3FEFD3AAF45E9305), UInt64(0x3FEFD3AAF45E9306))
    _encloses(candidate[0].first, UInt64(0x3FEFD3AAF45E9305), UInt64(0x3FEFD3AAF45E9306))
    _encloses(root[0].first, UInt64(0x3FEFD3AAF45E9305), UInt64(0x3FEFD3AAF45E9306))
    _encloses(original[0].second, UInt64(0xBF636A6E9C4D8AD2), UInt64(0xBF636A6E9C4D8AD1))
    _encloses(candidate[0].second, UInt64(0xBF636A6E9C4D8AD2), UInt64(0xBF636A6E9C4D8AD1))
    _encloses(root[0].second, UInt64(0xBF636A6E9C4D8AD2), UInt64(0xBF636A6E9C4D8AD1))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x4059143EE192D7BA), UInt64(0x4059143EE192D7BB))
    _encloses(candidate[1].value, UInt64(0x4059143EE192D7BA), UInt64(0x4059143EE192D7BB))
    _encloses(root[1].value, UInt64(0x4059143EE192D7BA), UInt64(0x4059143EE192D7BB))
    _encloses(original[1].first, UInt64(0x3FBA98CFA182C52D), UInt64(0x3FBA98CFA182C52E))
    _encloses(candidate[1].first, UInt64(0x3FBA98CFA182C52D), UInt64(0x3FBA98CFA182C52E))
    _encloses(root[1].first, UInt64(0x3FBA98CFA182C52D), UInt64(0x3FBA98CFA182C52E))
    _encloses(original[1].second, UInt64(0x3F973BCC282651B9), UInt64(0x3F973BCC282651BA))
    _encloses(candidate[1].second, UInt64(0x3F973BCC282651B9), UInt64(0x3F973BCC282651BA))
    _encloses(root[1].second, UInt64(0x3F973BCC282651B9), UInt64(0x3F973BCC282651BA))


def test_root_error_ideal_nineteen_hot() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x4033000000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 21)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x40329DE2A7713F18), UInt64(0x40329DE2A7713F19))
    _encloses(candidate[0].value, UInt64(0x40329DE2A7713F18), UInt64(0x40329DE2A7713F19))
    _encloses(root[0].value, UInt64(0x40329DE2A7713F18), UInt64(0x40329DE2A7713F19))
    _encloses(original[0].first, UInt64(0x3FECCC00BB053134), UInt64(0x3FECCC00BB053135))
    _encloses(candidate[0].first, UInt64(0x3FECCC00BB053134), UInt64(0x3FECCC00BB053135))
    _encloses(root[0].first, UInt64(0x3FECCC00BB053134), UInt64(0x3FECCC00BB053135))
    _encloses(original[0].second, UInt64(0xBF953621DD1FB526), UInt64(0xBF953621DD1FB525))
    _encloses(candidate[0].second, UInt64(0xBF953621DD1FB526), UInt64(0xBF953621DD1FB525))
    _encloses(root[0].second, UInt64(0xBF953621DD1FB526), UInt64(0xBF953621DD1FB525))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x4059B4437558F7F4), UInt64(0x4059B4437558F7F5))
    _encloses(candidate[1].value, UInt64(0x4059B4437558F7F4), UInt64(0x4059B4437558F7F5))
    _encloses(root[1].value, UInt64(0x4059B4437558F7F4), UInt64(0x4059B4437558F7F5))
    _encloses(original[1].first, UInt64(0x3FDBE8E9306D16C5), UInt64(0x3FDBE8E9306D16C6))
    _encloses(candidate[1].first, UInt64(0x3FDBE8E9306D16C5), UInt64(0x3FDBE8E9306D16C6))
    _encloses(root[1].first, UInt64(0x3FDBE8E9306D16C5), UInt64(0x3FDBE8E9306D16C6))
    _encloses(original[1].second, UInt64(0x3FA5E2B8E00E2FA2), UInt64(0x3FA5E2B8E00E2FA3))
    _encloses(candidate[1].second, UInt64(0x3FA5E2B8E00E2FA2), UInt64(0x3FA5E2B8E00E2FA3))
    _encloses(root[1].second, UInt64(0x3FA5E2B8E00E2FA2), UInt64(0x3FA5E2B8E00E2FA3))


def test_root_error_ideal_count3() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x3FF2000000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 3)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FF1FFFFB46AD370), UInt64(0x3FF1FFFFB46AD371))
    _encloses(candidate[0].value, UInt64(0x3FF1FFFFB46AD370), UInt64(0x3FF1FFFFB46AD371))
    _encloses(root[0].value, UInt64(0x3FF1FFFFB46AD370), UInt64(0x3FF1FFFFB46AD371))
    _encloses(original[0].first, UInt64(0x3FEFFFFD60275B84), UInt64(0x3FEFFFFD60275B85))
    _encloses(candidate[0].first, UInt64(0x3FEFFFFD60275B84), UInt64(0x3FEFFFFD60275B85))
    _encloses(root[0].first, UInt64(0x3FEFFFFD60275B84), UInt64(0x3FEFFFFD60275B85))
    _encloses(original[0].second, UInt64(0xBED2A99289457F77), UInt64(0xBED2A99289457F76))
    _encloses(candidate[0].second, UInt64(0xBED2A99289457F77), UInt64(0xBED2A99289457F76))
    _encloses(root[0].second, UInt64(0xBED2A99289457F77), UInt64(0xBED2A99289457F76))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x40590009B851CE5D), UInt64(0x40590009B851CE5E))
    _encloses(candidate[1].value, UInt64(0x40590009B851CE5D), UInt64(0x40590009B851CE5E))
    _encloses(root[1].value, UInt64(0x40590009B851CE5D), UInt64(0x40590009B851CE5E))
    _encloses(original[1].first, UInt64(0x3F59EB8469524D7A), UInt64(0x3F59EB8469524D7B))
    _encloses(candidate[1].first, UInt64(0x3F59EB8469524D7A), UInt64(0x3F59EB8469524D7B))
    _encloses(root[1].first, UInt64(0x3F59EB8469524D7A), UInt64(0x3F59EB8469524D7B))
    _encloses(original[1].second, UInt64(0x3F670A3B8CE9232B), UInt64(0x3F670A3B8CE9232C))
    _encloses(candidate[1].second, UInt64(0x3F670A3B8CE9232B), UInt64(0x3F670A3B8CE9232C))
    _encloses(root[1].second, UInt64(0x3F670A3B8CE9232B), UInt64(0x3F670A3B8CE9232C))


def test_root_error_ideal_count6() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x4010800000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 6)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x40107FCF14EFC040), UInt64(0x40107FCF14EFC041))
    _encloses(candidate[0].value, UInt64(0x40107FCF14EFC040), UInt64(0x40107FCF14EFC041))
    _encloses(root[0].value, UInt64(0x40107FCF14EFC040), UInt64(0x40107FCF14EFC041))
    _encloses(original[0].first, UInt64(0x3FEFFE25A64486F1), UInt64(0x3FEFFE25A64486F2))
    _encloses(candidate[0].first, UInt64(0x3FEFFE25A64486F1), UInt64(0x3FEFFE25A64486F2))
    _encloses(root[0].first, UInt64(0x3FEFFE25A64486F1), UInt64(0x3FEFFE25A64486F2))
    _encloses(original[0].second, UInt64(0xBF2CBF57BA32BDDD), UInt64(0xBF2CBF57BA32BDDC))
    _encloses(candidate[0].second, UInt64(0xBF2CBF57BA32BDDD), UInt64(0xBF2CBF57BA32BDDC))
    _encloses(root[0].second, UInt64(0xBF2CBF57BA32BDDD), UInt64(0xBF2CBF57BA32BDDC))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x405901DF24FF0CBD), UInt64(0x405901DF24FF0CBE))
    _encloses(candidate[1].value, UInt64(0x405901DF24FF0CBD), UInt64(0x405901DF24FF0CBE))
    _encloses(root[1].value, UInt64(0x405901DF24FF0CBD), UInt64(0x405901DF24FF0CBE))
    _encloses(original[1].first, UInt64(0x3F95C74275C95988), UInt64(0x3F95C74275C95989))
    _encloses(candidate[1].first, UInt64(0x3F95C74275C95988), UInt64(0x3F95C74275C95989))
    _encloses(root[1].first, UInt64(0x3F95C74275C95988), UInt64(0x3F95C74275C95989))
    _encloses(original[1].second, UInt64(0x3F851D7F3FA81B9F), UInt64(0x3F851D7F3FA81BA0))
    _encloses(candidate[1].second, UInt64(0x3F851D7F3FA81B9F), UInt64(0x3F851D7F3FA81BA0))
    _encloses(root[1].second, UInt64(0x3F851D7F3FA81B9F), UInt64(0x3F851D7F3FA81BA0))


def test_root_error_ideal_count22_eligible() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4040000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var station = _f64(UInt64(0x4034400000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 22)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x40340B0C4FB50BDF), UInt64(0x40340B0C4FB50BE0))
    _encloses(candidate[0].value, UInt64(0x40340B0C4FB50BDF), UInt64(0x40340B0C4FB50BE0))
    _encloses(root[0].value, UInt64(0x40340B0C4FB50BDF), UInt64(0x40340B0C4FB50BE0))
    _encloses(original[0].first, UInt64(0x3FEE5F3475A85DBE), UInt64(0x3FEE5F3475A85DBF))
    _encloses(candidate[0].first, UInt64(0x3FEE5F3475A85DBE), UInt64(0x3FEE5F3475A85DBF))
    _encloses(root[0].first, UInt64(0x3FEE5F3475A85DBE), UInt64(0x3FEE5F3475A85DBF))
    _encloses(original[0].second, UInt64(0xBF8467F89C707FE1), UInt64(0xBF8467F89C707FE0))
    _encloses(candidate[0].second, UInt64(0xBF8467F89C707FE1), UInt64(0xBF8467F89C707FE0))
    _encloses(root[0].second, UInt64(0xBF8467F89C707FE1), UInt64(0xBF8467F89C707FE0))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x4059896285342739), UInt64(0x405989628534273A))
    _encloses(candidate[1].value, UInt64(0x4059896285342739), UInt64(0x405989628534273A))
    _encloses(root[1].value, UInt64(0x4059896285342739), UInt64(0x405989628534273A))
    _encloses(original[1].first, UInt64(0x3FD4277A4855D3A1), UInt64(0x3FD4277A4855D3A2))
    _encloses(candidate[1].first, UInt64(0x3FD4277A4855D3A1), UInt64(0x3FD4277A4855D3A2))
    _encloses(root[1].first, UInt64(0x3FD4277A4855D3A1), UInt64(0x3FD4277A4855D3A2))
    _encloses(original[1].second, UInt64(0x3F9EC0651D874551), UInt64(0x3F9EC0651D874552))
    _encloses(candidate[1].second, UInt64(0x3F9EC0651D874551), UInt64(0x3F9EC0651D874552))
    _encloses(root[1].second, UInt64(0x3F9EC0651D874551), UInt64(0x3F9EC0651D874552))


def test_root_error_ideal_count64() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4060000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3F50624DD2F1A9FC))
    var station = _f64(UInt64(0x404F400000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 64)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x404F3FD05119AF50), UInt64(0x404F3FD05119AF51))
    _encloses(candidate[0].value, UInt64(0x404F3FD05119AF50), UInt64(0x404F3FD05119AF51))
    _encloses(root[0].value, UInt64(0x404F3FD05119AF50), UInt64(0x404F3FD05119AF51))
    _encloses(original[0].first, UInt64(0x3FEFFF0BDD36703E), UInt64(0x3FEFFF0BDD36703F))
    _encloses(candidate[0].first, UInt64(0x3FEFFF0BDD36703E), UInt64(0x3FEFFF0BDD36703F))
    _encloses(root[0].first, UInt64(0x3FEFFF0BDD36703E), UInt64(0x3FEFFF0BDD36703F))
    _encloses(original[0].second, UInt64(0xBEDF3FB0872F4CA1), UInt64(0xBEDF3FB0872F4CA0))
    _encloses(candidate[0].second, UInt64(0xBEDF3FB0872F4CA1), UInt64(0xBEDF3FB0872F4CA0))
    _encloses(root[0].second, UInt64(0xBEDF3FB0872F4CA1), UInt64(0xBEDF3FB0872F4CA0))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x405914583F28BE17), UInt64(0x405914583F28BE18))
    _encloses(candidate[1].value, UInt64(0x405914583F28BE17), UInt64(0x405914583F28BE18))
    _encloses(root[1].value, UInt64(0x405914583F28BE17), UInt64(0x405914583F28BE18))
    _encloses(original[1].first, UInt64(0x3F8F3FB0872F4CA0), UInt64(0x3F8F3FB0872F4CA1))
    _encloses(candidate[1].first, UInt64(0x3F8F3FB0872F4CA0), UInt64(0x3F8F3FB0872F4CA1))
    _encloses(root[1].first, UInt64(0x3F8F3FB0872F4CA0), UInt64(0x3F8F3FB0872F4CA1))
    _encloses(original[1].second, UInt64(0x3F3FFF0BDD36703F), UInt64(0x3F3FFF0BDD367040))
    _encloses(candidate[1].second, UInt64(0x3F3FFF0BDD36703F), UInt64(0x3F3FFF0BDD367040))
    _encloses(root[1].second, UInt64(0x3F3FFF0BDD36703F), UInt64(0x3F3FFF0BDD367040))


def test_root_error_ideal_negative_curvature() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0xBFA999999999999A))
    var station = _f64(UInt64(0x4014800000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 7)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x40147F6F2FDDA528), UInt64(0x40147F6F2FDDA529))
    _encloses(candidate[0].value, UInt64(0x40147F6F2FDDA528), UInt64(0x40147F6F2FDDA529))
    _encloses(root[0].value, UInt64(0x40147F6F2FDDA528), UInt64(0x40147F6F2FDDA529))
    _encloses(original[0].first, UInt64(0x3FEFFB95CC10B4F6), UInt64(0x3FEFFB95CC10B4F7))
    _encloses(candidate[0].first, UInt64(0x3FEFFB95CC10B4F6), UInt64(0x3FEFFB95CC10B4F7))
    _encloses(root[0].first, UInt64(0x3FEFFB95CC10B4F6), UInt64(0x3FEFFB95CC10B4F7))
    _encloses(original[0].second, UInt64(0xBF3B903E16E56176), UInt64(0xBF3B903E16E56175))
    _encloses(candidate[0].second, UInt64(0xBF3B903E16E56176), UInt64(0xBF3B903E16E56175))
    _encloses(root[0].second, UInt64(0xBF3B903E16E56176), UInt64(0xBF3B903E16E56175))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x4058FC691FC419CF), UInt64(0x4058FC691FC419D0))
    _encloses(candidate[1].value, UInt64(0x4058FC691FC419CF), UInt64(0x4058FC691FC419D0))
    _encloses(root[1].value, UInt64(0x4058FC691FC419CF), UInt64(0x4058FC691FC419D0))
    _encloses(original[1].first, UInt64(0xBFA0CE963FE9865B), UInt64(0xBFA0CE963FE9865A))
    _encloses(candidate[1].first, UInt64(0xBFA0CE963FE9865B), UInt64(0xBFA0CE963FE9865A))
    _encloses(root[1].first, UInt64(0xBFA0CE963FE9865B), UInt64(0xBFA0CE963FE9865A))
    _encloses(original[1].second, UInt64(0xBF8A39D1DFA74CB6), UInt64(0xBF8A39D1DFA74CB5))
    _encloses(candidate[1].second, UInt64(0xBF8A39D1DFA74CB6), UInt64(0xBF8A39D1DFA74CB5))
    _encloses(root[1].second, UInt64(0xBF8A39D1DFA74CB6), UInt64(0xBF8A39D1DFA74CB5))


def test_root_error_ideal_zero_rate() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x0000000000000000))
    var station = _f64(UInt64(0x3FF2000000000000))
    var distance = _Jet.variable(station, station)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 3)
    var road = _road(geometry.copy())
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FF2000000000000), UInt64(0x3FF2000000000001))
    _encloses(candidate[0].value, UInt64(0x3FF2000000000000), UInt64(0x3FF2000000000001))
    _encloses(root[0].value, UInt64(0x3FF2000000000000), UInt64(0x3FF2000000000001))
    _encloses(original[0].first, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(candidate[0].first, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(root[0].first, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(original[0].second, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    _encloses(candidate[0].second, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    _encloses(root[0].second, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x4059000000000000), UInt64(0x4059000000000000))
    _encloses(candidate[1].value, UInt64(0x4059000000000000), UInt64(0x4059000000000000))
    _encloses(root[1].value, UInt64(0x4059000000000000), UInt64(0x4059000000000000))
    _encloses(original[1].first, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    _encloses(candidate[1].first, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    _encloses(root[1].first, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    _encloses(original[1].second, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    _encloses(candidate[1].second, UInt64(0x8000000000000000), UInt64(0x0000000000000000))
    _encloses(root[1].second, UInt64(0x8000000000000000), UInt64(0x0000000000000000))


def test_root_error_ideal_nonzero_record_station() raises:
    var geometry = _geometry()
    geometry.length = _f64(UInt64(0x4034000000000000))
    geometry.x = _f64(UInt64(0x0000000000000000))
    geometry.y = _f64(UInt64(0x4059000000000000))
    geometry.curvature_end = _f64(UInt64(0x3FA999999999999A))
    var local_station = _f64(UInt64(0x3FF2000000000000))
    var record_s = Float64(128.0)
    var station = record_s + local_station
    geometry.s = record_s
    var distance = _Jet.variable(station, station) - _Jet.constant(record_s)
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], counts[1])
    assert_equal(counts[0], 3)
    var road = _road(geometry.copy(), record_s)
    var root_low = station - 0.03125
    var root_high = station + 0.03125
    var proof = _proof(road, root_low, root_high)
    var translation = Vector3(Float32(_f64(UInt64(0x0000000000000000))), Float32(_f64(UInt64(0x0000000000000000))), 0.0)
    var original = _reference_jet(geometry, distance, translation)
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, station, station, root_low, root_high, d, counts,
    ))
    var candidate = _spiral_proof_branch(proof, geometry, d, counts[0])
    var root_d = _geometry_distance(geometry, _Jet.variable(root_low, root_high) - _Jet.constant(record_s))
    assert_true(_spiral_proof_matches(
        proof, geometry, 0, root_low, root_high, root_low, root_high,
        root_d, _spiral_counts(geometry, root_d),
    ))
    var root = _spiral_proof_branch(proof, geometry, root_d, counts[0])
    var lane = _lane_jet_with_proof(
        road, 0, 0, station, station, root_low, root_high, proof,
    )
    _canonical_contains(road, 0, lane, station)
    var canonical = geometry.pos_at(local_station)
    assert_true(candidate[0].rounded_value().contains(canonical.x))
    assert_true(candidate[1].rounded_value().contains(canonical.y))
    _jet_bits(original[2], candidate[2])
    _each_original_node_quadrant_zero(geometry, root_d, counts[0])
    assert_true(isfinite(original[0].error))
    assert_true(isfinite(candidate[0].error))
    assert_true(candidate[0].rounded_value().is_finite())
    _bits(candidate[0].error, proof.last_x_error if counts[0] == proof.last_count else proof.first_x_error)
    _encloses(original[0].value, UInt64(0x3FF1FFFFB46AD370), UInt64(0x3FF1FFFFB46AD371))
    _encloses(candidate[0].value, UInt64(0x3FF1FFFFB46AD370), UInt64(0x3FF1FFFFB46AD371))
    _encloses(root[0].value, UInt64(0x3FF1FFFFB46AD370), UInt64(0x3FF1FFFFB46AD371))
    _encloses(original[0].first, UInt64(0x3FEFFFFD60275B84), UInt64(0x3FEFFFFD60275B85))
    _encloses(candidate[0].first, UInt64(0x3FEFFFFD60275B84), UInt64(0x3FEFFFFD60275B85))
    _encloses(root[0].first, UInt64(0x3FEFFFFD60275B84), UInt64(0x3FEFFFFD60275B85))
    _encloses(original[0].second, UInt64(0xBED2A99289457F77), UInt64(0xBED2A99289457F76))
    _encloses(candidate[0].second, UInt64(0xBED2A99289457F77), UInt64(0xBED2A99289457F76))
    _encloses(root[0].second, UInt64(0xBED2A99289457F77), UInt64(0xBED2A99289457F76))
    assert_true(isfinite(original[1].error))
    assert_true(isfinite(candidate[1].error))
    assert_true(candidate[1].rounded_value().is_finite())
    _bits(candidate[1].error, proof.last_y_error if counts[0] == proof.last_count else proof.first_y_error)
    _encloses(original[1].value, UInt64(0x40590009B851CE5D), UInt64(0x40590009B851CE5E))
    _encloses(candidate[1].value, UInt64(0x40590009B851CE5D), UInt64(0x40590009B851CE5E))
    _encloses(root[1].value, UInt64(0x40590009B851CE5D), UInt64(0x40590009B851CE5E))
    _encloses(original[1].first, UInt64(0x3F59EB8469524D7A), UInt64(0x3F59EB8469524D7B))
    _encloses(candidate[1].first, UInt64(0x3F59EB8469524D7A), UInt64(0x3F59EB8469524D7B))
    _encloses(root[1].first, UInt64(0x3F59EB8469524D7A), UInt64(0x3F59EB8469524D7B))
    _encloses(original[1].second, UInt64(0x3F670A3B8CE9232B), UInt64(0x3F670A3B8CE9232C))
    _encloses(candidate[1].second, UInt64(0x3F670A3B8CE9232B), UInt64(0x3F670A3B8CE9232C))
    _encloses(root[1].second, UInt64(0x3F670A3B8CE9232B), UInt64(0x3F670A3B8CE9232C))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
