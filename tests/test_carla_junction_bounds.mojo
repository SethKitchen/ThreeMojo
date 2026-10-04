# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent geometric controls for direction-independent junction bounds."""

from extensions.carla.junction_bounds import (
    _lane_section_box,
    _polynomial_bounds,
)
from extensions.carla.map import Map, Waypoint
from extensions.carla.map_builder import MapBuilder, junction_box
from extensions.carla.mesh_factory import junctions_bounding_boxes
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import (
    ConId,
    JuncId,
    LANE_ANY,
    LANE_DRIVING,
    LaneId,
    RoadId,
    SectionId,
)
from extensions.carla.traffic_sign import TriggerBox, _check_boxes
from math.bounds import Box3
from math.vector3 import Vector3
from std.math import cos, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime PI = 3.14159265358979323846


def _road(
    mut b: MapBuilder, id: Int, length: Float64, sign: Int, rht: Bool = True
) raises -> Int:
    var r = b.add_road(
        RoadId(id), "bounds", length, JuncId(7), RoadId(0), RoadId(0), rht
    )
    var sec = b.add_road_section(r, SectionId(0), 0.0)
    _ = b.add_road_section_lane(
        r, sec, LaneId(sign), LANE_DRIVING, False, LaneId(0), LaneId(0)
    )
    b.create_lane_width(
        b.lane(RoadId(id), LaneId(sign), 0.0), 0.0, 3.5, 0, 0, 0
    )
    b.create_section_offset(r, 0.0, 0, 0, 0, 0)
    b.add_road_elevation_profile(r, 0.0, 0, 0, 0, 0)
    return r


def _connect(mut b: MapBuilder, ids: List[Int]) raises:
    b.add_junction(JuncId(7), "bounds")
    for i in range(len(ids)):
        b.add_connection(JuncId(7), ConId(i), RoadId(0), RoadId(ids[i]))


def _contains(box: Box3, x: Float64, y: Float64, z: Float64 = 0.0) raises:
    assert_true(box.contains_point(Vector3(Float32(x), Float32(y), Float32(z))))


def _dense_points(map: Map) raises:
    var box = map.junction(JuncId(7)).bounding_box
    for pair in map.junction_waypoints(JuncId(7), LANE_ANY):
        ref road = map.road(pair[0].road_id)
        var sec = road.section_index(pair[0].section_id)
        var a = road.sections[sec].s
        var length = road.section_length(sec)
        for i in range(258):
            var w = pair[0]
            # Prime denominator and noncentral offset do not reuse the
            # production subdivision grid or just its midpoint.
            w.s = a + length * min(1.0, (Float64(i) + 0.317) / 257.0)
            assert_true(box.contains_point(map.compute_transform(w).location))
        var w = pair[0]
        w.s = a
        assert_true(box.contains_point(map.compute_transform(w).location))
        w.s = a + length
        assert_true(box.contains_point(map.compute_transform(w).location))


def test_semicircle_all_lane_signs_and_traffic_rules() raises:
    for rht in [True, False]:
        for sign in [-1, 1]:
            var b = MapBuilder()
            var r = _road(b, 1, 100.0, sign, rht)
            b.add_road_geometry_arc(r, 0, 0, 0, 0, 100, PI / 100.0)
            _connect(b, [1])
            var map = b.build()
            var pair = map.junction_waypoints(JuncId(7), LANE_ANY)[0]
            assert_equal(pair[0].s < pair[1].s, (sign < 0) == rht)
            var box = map.junction(JuncId(7)).bounding_box
            var radius = 100.0 / PI
            var lane_radius = radius - Float64(sign) * 1.75
            # Circle equations, independent of RoadGeometry and lane_transform.
            for i in range(401):
                var angle = PI * Float64(i) / 400.0
                _contains(
                    box,
                    lane_radius * sin(angle),
                    -radius + lane_radius * cos(angle),
                )
            assert_almost_equal(Float64(box.max.x), lane_radius, atol=1e-4)
            assert_almost_equal(
                Float64(box.min.y), -radius - lane_radius, atol=1e-4
            )
            assert_almost_equal(
                Float64(box.max.y), -radius + lane_radius, atol=1e-4
            )
            _dense_points(map)
            var again = junction_box(map, JuncId(7))
            assert_true(box.min == again.min)
            assert_true(box.max == again.max)


def test_multiple_connections_unlinked_sections_and_duplicate_roads() raises:
    var b = MapBuilder()
    var r = _road(b, 1, 100.0, 1)
    var sec = b.add_road_section(r, SectionId(4), 39.125)
    _ = b.add_road_section_lane(
        r, sec, LaneId(-2), LANE_DRIVING, False, LaneId(0), LaneId(0)
    )
    b.create_lane_width(
        b.lane(RoadId(1), LaneId(-2), 39.125), 39.125, 8, 0, 0, 0
    )
    b.add_road_geometry_arc(r, 0, 0, 0, 0, 100, PI / 100.0)
    var other = _road(b, 2, 13, -1, False)
    b.add_road_geometry_line(other, 0, 120, 17, 0, 13)
    _connect(b, [2, 1, 1])
    var map = b.build()
    assert_equal(len(map.junction_waypoints(JuncId(7), LANE_ANY)), 5)
    _dense_points(map)
    var box = map.junction(JuncId(7)).bounding_box
    _contains(box, 133, -15.25)
    _contains(box, 100.0 / PI + 4, -100.0 / PI)
    _ = map.junctions[0].connections.pop()
    var single = junction_box(map, JuncId(7))
    assert_true(box.min == single.min)
    assert_true(box.max == single.max)


def test_cubic_profiles_and_inner_lane_records() raises:
    var b = MapBuilder()
    var r = _road(b, 1, 10, 1)
    _ = b.add_road_section_lane(
        r, 0, LaneId(2), LANE_DRIVING, False, LaneId(0), LaneId(0)
    )
    b.create_lane_width(b.lane(RoadId(1), LaneId(2), 0), 0, 2, 0, 0, 0)
    # The outer center's offset is -(inner width + 1) - road offset.
    # A narrow record away from deciles has an interior maximum at ds=0.125.
    b.create_lane_width(
        b.lane(RoadId(1), LaneId(1), 0), 4.03125, 3.5, 160, -640, 0
    )
    b.create_lane_width(b.lane(RoadId(1), LaneId(1), 0), 4.28125, 3.5, 0, 0, 0)
    b.create_section_offset(r, 4.03125, 0, 80, -320, 0)
    b.create_section_offset(r, 4.28125, 0, 0, 0, 0)
    b.add_road_elevation_profile(r, 4.03125, 0, 48, -192, 0)
    b.add_road_elevation_profile(r, 4.28125, 0, 0, 0, 0)
    b.add_road_geometry_line(r, 0, 0, 0, 0, 10)
    _connect(b, [1])
    var map = b.build()
    var box = map.junction(JuncId(7)).bounding_box
    _contains(box, 4.15625, -19.5, 3.0)
    assert_true(box.min.y >= -19.511)
    assert_true(box.max.z <= 3.011)
    _dense_points(map)
    # Independent Bernstein control: 4s(1-s) reaches 1 at 1/2.
    var bounds = _polynomial_bounds(CubicPolynomial(0, 4, -4, 0, 0), 0, 1)
    assert_true(bounds[0] >= 1)
    assert_almost_equal(bounds[1], 4.0, atol=1e-12)
    assert_almost_equal(bounds[2], 8.0, atol=1e-12)


def test_record_jumps_and_clamped_geometry_tail() raises:
    var b = MapBuilder()
    var r = _road(b, 1, 20, 1)
    b.add_road_geometry_line(r, 0, 0, 0, 0, 5)
    b.add_road_geometry_line(r, 7.03125, 100, 40, 0, 12.96875)
    b.create_section_offset(r, 3.125, 20, 0, 0, 0)
    b.create_section_offset(r, 7.03125, -30, 0, 0, 0)
    b.add_road_elevation_profile(r, 7.03125, -12, 0, 0, 0)
    _connect(b, [1])
    var map = b.build()
    var box = map.junction(JuncId(7)).bounding_box
    _contains(box, 5, -21.75)
    _contains(box, 100, -11.75, -12)
    _dense_points(map)


def test_spiral_poly3_and_param_poly3_interiors() raises:
    for kind in range(3):
        var b = MapBuilder()
        var r = _road(b, 1, 30, 1)
        if kind == 0:
            b.add_road_geometry_spiral(r, 0, 0, 0, 0, 30, 0.02, 0.08)
        elif kind == 1:
            b.add_road_geometry_poly3(
                r, 0, 0, 0, 0.2, 30, 0, 0.1, 0.04, -0.0005
            )
        else:
            b.add_road_geometry_param_poly3(
                r,
                0,
                0,
                0,
                0.2,
                30,
                CubicPolynomial(0, 30, 0, 0, 0),
                CubicPolynomial(0, 12, -18, 9, 0),
                "normalized",
            )
        _connect(b, [1])
        var map = b.build()
        _dense_points(map)
        if kind == 0:
            # Composite midpoint integration is independent of the library's
            # five-point Gauss-Legendre implementation. Error is < 1e-5 m here.
            var x = 0.0
            var y = 0.0
            var step = 30.0 / 12000.0
            for i in range(12000):
                var s = (Float64(i) + 0.5) * step
                var heading = 0.02 * s + 0.001 * s * s
                x += cos(heading) * step
                y += sin(heading) * step
                if i % 997 == 996:
                    var at = Float64(i + 1) * step
                    var theta = 0.02 * at + 0.001 * at * at
                    _contains(
                        map.junctions[0].bounding_box,
                        x - 1.75 * sin(theta),
                        -y - 1.75 * cos(theta),
                    )


def test_parametric_tail_and_singular_tangent_fallback() raises:
    var b = MapBuilder()
    var r = _road(b, 1, 20, 1)
    # The sampled path only travels 2 m, so pos_at extrapolates its last
    # segment through the rest of the declared 20 m record.
    b.add_road_geometry_param_poly3(
        r,
        0,
        0,
        0,
        0,
        20,
        CubicPolynomial(0, 2, 0, 0, 0),
        CubicPolynomial(0, 0, 0, 0, 0),
        "normalized",
    )
    _connect(b, [1])
    var map = b.build()
    _dense_points(map)
    _contains(map.junctions[0].bounding_box, 20, -1.75)
    # Keep a valid sampled position table, but make its interpolated tangent
    # reverse at the interior of one interval. The normal flips there.
    var count = len(map.roads[0].info.geometries[0].geometry.samples)
    for i in range(count):
        map.roads[0].info.geometries[0].geometry.samples[i].tu = (
            -1.0 if i == 0 else 1.0
        )
        map.roads[0].info.geometries[0].geometry.samples[i].tv = 0.0
    map.junctions[0].bounding_box = junction_box(map, JuncId(7))
    _dense_points(map)
    _contains(map.junctions[0].bounding_box, 0.0, 1.75)


def test_curved_conflicts_and_consumers() raises:
    var b = MapBuilder()
    for id in [1, 2]:
        var r = _road(b, id, 100, 1)
        b.add_road_geometry_arc(
            r, 0, 0, -20.0 * Float64(id - 1), 0, 100, PI / 100.0
        )
    _connect(b, [1, 2])
    var map = b.build()
    var radius = 100.0 / PI - 1.75
    var crossing = Vector3(
        Float32(sqrt(radius * radius - 100.0)), Float32(-100.0 / PI + 10), 0
    )
    assert_true(map.junctions[0].bounding_box.contains_point(crossing))
    assert_true(map.junctions[0].road_has_conflicts(RoadId(1)))
    assert_equal(map.junctions[0].conflicts_of_road(RoadId(1))[0], RoadId(2))
    var checks = List[TriggerBox]()
    _check_boxes(map, RoadId(1), List[Int](), checks)
    assert_true(len(checks) > 0)
    var boxes = junctions_bounding_boxes(map)
    assert_equal(len(boxes), 1)
    assert_true(boxes[0].contains_point(crossing))
    assert_true(boxes[0].contains_point(map.junctions[0].bounding_box.min))
    assert_true(boxes[0].contains_point(map.junctions[0].bounding_box.max))
    # A control reproduces the old endpoint-only box. The crossing is lost.
    var old = Box3.empty()
    for pair in map.junction_waypoints(JuncId(7), LANE_ANY):
        old.expand_by_point(map.compute_transform(pair[0]).location)
        old.expand_by_point(map.compute_transform(pair[1]).location)
    assert_false(old.contains_point(crossing))
    map.junctions[0].bounding_box = old
    assert_equal(len(map.compute_junction_conflicts(JuncId(7))[0]), 0)


def test_empty_tiny_zero_sections_and_large_coordinates() raises:
    var empty = MapBuilder()
    _connect(empty, [])
    var map = empty.build()
    var box = junction_box(map, JuncId(7))
    assert_equal(box.min.x, Float32(3.4028234663852886e38))
    assert_equal(box.max.x, -Float32(3.4028234663852886e38))
    for length in [0.0, 1e-12, 100.0]:
        var b = MapBuilder()
        var r = _road(b, 1, max(length, 1e-12), -1)
        b.add_road_geometry_line(r, 0, 1000000, -1000000, 0, max(length, 1e-12))
        # Direct section test avoids asking the unrelated segment index to
        # represent a zero-length domain.
        b.roads[r].length = length
        var result = _lane_section_box(b.roads[r], 0, 0)
        _contains(result, 1000000, 1000001.75)
        _contains(result, 1000000 + length, 1000001.75)


def test_arc_cancellation_and_large_s_polynomial_rounding() raises:
    var b = MapBuilder()
    var r = _road(b, 1, 32.0 * PI, 1)
    b.create_lane_width(b.lane(RoadId(1), LaneId(1), 0), 0, 64, 0, 0, 0)
    b.add_road_geometry_arc(r, 0, 0, 0, 0, 32.0 * PI, 1.0 / 32.0)
    _connect(b, [1])
    var map = b.build()
    _dense_points(map)
    _contains(map.junctions[0].bounding_box, 0, -32)
    var shifted = MapBuilder()
    var sr = _road(shifted, 2, 100001, -1)
    shifted.roads[sr].sections[0].s = 100000
    shifted.add_road_geometry_line(sr, 0, 0, 0, 0, 100001)
    shifted.add_road_elevation_profile(sr, 100000, 0, 0, 0, 1)
    var bounds = _lane_section_box(shifted.roads[sr], 0, 0)
    for i in range(1001):
        var s = 100000.0 + Float64(i) / 1000.0
        assert_true(
            bounds.contains_point(
                shifted.roads[sr].lane_transform(0, 0, s).location
            )
        )
    # This polynomial is intentionally ill-conditioned in global s.
    # The wider numerical envelope must not be mislabeled 1 cm tight.
    assert_true(bounds.min.z < -0.25)
    assert_true(bounds.max.z > 1.25)


def test_excessive_subdivision_uses_complete_envelope() raises:
    var b = MapBuilder()
    var r = _road(b, 1, 1, 1)
    b.add_road_geometry_line(r, 0, 0, 0, 0, 1)
    b.create_section_offset(r, 0, 0, 4e12, -4e12, 0)
    var box = _lane_section_box(b.roads[r], 0, 0)
    for i in range(101):
        var s = Float64(i) / 100.0
        assert_true(
            box.contains_point(b.roads[r].lane_transform(0, 0, s).location)
        )


def test_unresolved_arc_phase_and_invalid_records() raises:
    var b = MapBuilder()
    var r = _road(b, 1, 1024, 1)
    b.add_road_geometry_arc(r, 0, 0, 0, 1e18, 1024, 1.0)
    var box = _lane_section_box(b.roads[r], 0, 0)
    for i in range(513):
        assert_true(
            box.contains_point(
                b.roads[r].lane_transform(0, 0, 2.0 * Float64(i)).location
            )
        )
    b.roads[r].sections[0].s = -1
    with assert_raises():
        _ = _lane_section_box(b.roads[r], 0, 0)
    b.roads[r].sections[0].s = 0
    b.roads[r].sections[0].lanes[0].info.widths.clear()
    with assert_raises():
        _ = _lane_section_box(b.roads[r], 0, 0)
    b.roads[r].info.geometries.clear()
    with assert_raises():
        _ = _lane_section_box(b.roads[r], 0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
