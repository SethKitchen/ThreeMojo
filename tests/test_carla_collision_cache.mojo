# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Collision cache direction and path endpoints, issue #488.

The straight-path oracle uses interval gaps between axis-aligned rectangles,
not the polygon-distance implementation. Turn corners are worked by hand.
"""

from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive
from extensions.carla.traffic_manager_collision import (
    CollisionLock,
    CollisionStage,
    GeometryComparison,
)
from extensions.carla.traffic_manager_map import SimpleWaypointIndex
from extensions.carla.traffic_manager_shared import TrafficManagerShared
from extensions.carla.transform import CarlaRotation
from math.vector3 import Vector3
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from test_carla_traffic_manager import straight_town
from test_carla_traffic_manager_stages import (
    _line,
    _put,
    _setup_follow,
    _shared,
    _vehicles,
)
from units.si import Angle, DEGREE, Length


def _same_geometry(a: GeometryComparison, b: GeometryComparison) raises:
    assert_equal(
        a.reference_vehicle_to_other_geodesic,
        b.reference_vehicle_to_other_geodesic,
    )
    assert_equal(
        a.other_vehicle_to_reference_geodesic,
        b.other_vehicle_to_reference_geodesic,
    )
    assert_equal(a.inter_geodesic_distance, b.inter_geodesic_distance)
    assert_equal(a.inter_bbox_distance, b.inter_bbox_distance)


def _reverse(g: GeometryComparison) -> GeometryComparison:
    return GeometryComparison(
        g.other_vehicle_to_reference_geodesic,
        g.reference_vehicle_to_other_geodesic,
        g.inter_geodesic_distance,
        g.inter_bbox_distance,
    )


def _interval_gap(
    a0: Float32, a1: Float32, b0: Float32, b1: Float32
) -> Float64:
    return max(Float64(b0) - Float64(a1), Float64(a0) - Float64(b1), 0.0)


def _box_gap(x1: Float32, y1: Float32, x2: Float32, y2: Float32) -> Float64:
    var dx = _interval_gap(x1 - 2.4, x1 + 2.4, x2 - 2.4, x2 + 2.4)
    var dy = _interval_gap(y1 - 1.0, y1 + 1.0, y2 - 1.0, y2 + 1.0)
    return sqrt(dx * dx + dy * dy)


def test_cache_is_independent_of_first_and_repeated_query_order() raises:
    var map = load_opendrive(straight_town())
    # The trailing body's front is 52.4; the leading body's rear is 57.6.
    # Their path strips overlap, and the leading body is in the trailing path.
    var gap = _box_gap(50, 1.75, 60, 1.75)
    for physical_order in range(2):
        var x1 = Float32(50 + physical_order * 10)
        var x2 = Float32(60 - physical_order * 10)
        var shared = _setup_follow(map, x1, x2, 5)
        shared.parameters.set_global_distance_to_leading_vehicle(Length(100))
        var expected = GeometryComparison(gap, 0, 0, gap)
        if physical_order == 1:
            expected = _reverse(expected)
        for first_reference in range(1, 3):
            var stage = CollisionStage()
            var first = stage.get_geometry_between_actors(
                ActorId(first_reference), ActorId(3 - first_reference), shared
            )
            var first_expected = expected
            if first_reference == 2:
                first_expected = _reverse(expected)
            _same_geometry(first, first_expected)
            # Storage is canonical even when the larger id made the first query.
            _same_geometry(stage.geometry_cache[(1 << 32) | 2], expected)
            for _ in range(3):
                _same_geometry(
                    stage.get_geometry_between_actors(
                        ActorId(1), ActorId(2), shared
                    ),
                    expected,
                )
                _same_geometry(
                    stage.get_geometry_between_actors(
                        ActorId(1), ActorId(2), shared
                    ),
                    expected,
                )
                _same_geometry(
                    stage.get_geometry_between_actors(
                        ActorId(2), ActorId(1), shared
                    ),
                    _reverse(expected),
                )
                _same_geometry(
                    stage.get_geometry_between_actors(
                        ActorId(2), ActorId(1), shared
                    ),
                    _reverse(expected),
                )
            assert_equal(len(stage.geometry_cache), 1)
            _same_geometry(stage.geometry_cache[(1 << 32) | 2], expected)
            stage.clear_cycle_cache()
            assert_equal(len(stage.geometry_cache), 0)
            assert_equal(len(stage.geodesic_boundary_map), 0)
            _same_geometry(
                stage.get_geometry_between_actors(
                    ActorId(2), ActorId(1), shared
                ),
                _reverse(expected),
            )


def test_equal_distances_signed_positions_and_self_pairs() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    # No paths: all four fields equal the rectangle gap. Negative world
    # coordinates do not change its sign or the meaning of actor order.
    _put(shared, 7, -20, -10, 0, 0)
    _put(shared, 9, -10, -5, 0, 0)
    var gap = _box_gap(-20, -10, -10, -5)
    var expected = GeometryComparison(gap, gap, gap, gap)
    var stage = CollisionStage()
    for _ in range(2):
        _same_geometry(
            stage.get_geometry_between_actors(ActorId(9), ActorId(7), shared),
            expected,
        )
        _same_geometry(
            stage.get_geometry_between_actors(ActorId(7), ActorId(9), shared),
            expected,
        )
        _same_geometry(
            stage.get_geometry_between_actors(ActorId(7), ActorId(7), shared),
            GeometryComparison(0, 0, 0, 0),
        )
    assert_equal(len(stage.geometry_cache), 2)


def _path_shared() raises -> TrafficManagerShared:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map,
        [
            (50.0, False),
            (55.0, False),
            (60.0, False),
            (65.0, False),
            (70.0, False),
            (75.0, False),
        ],
    )
    _put(shared, 1, 50, 1.75, 0, 5)
    _vehicles(shared, [1])
    return shared^


def _path(mut shared: TrafficManagerShared, count: Int):
    var buffer = List[SimpleWaypointIndex]()
    for i in range(count):
        buffer.append(SimpleWaypointIndex(i))
    shared.buffer_map[1] = buffer^


def _ends(boundary: List[Vector3], x: Float32) raises:
    assert_true(boundary[0] == Vector3(x, 0.75, 0))
    assert_true(boundary[len(boundary) - 1] == Vector3(x, 2.75, 0))


def test_geodesic_final_waypoint_for_short_and_long_buffers() raises:
    var shared = _path_shared()
    shared.parameters.set_distance_to_leading_vehicle(ActorId(1), Length(100))
    var stage = CollisionStage()
    for count in range(1, 7):
        _path(shared, count)
        stage.clear_cycle_cache()
        var boundary = stage.get_geodesic_boundary(ActorId(1), shared)
        _ends(boundary, Float32(50 + (count - 1) * 5))
        var again = stage.get_geodesic_boundary(ActorId(1), shared)
        assert_equal(len(boundary), len(again))
        for i in range(len(boundary)):
            assert_true(boundary[i] == again[i])
        # A returned list is a copy, so callers cannot corrupt the cache.
        again[0] = Vector3(-999, -999, 0)
        _ends(
            stage.get_geodesic_boundary(ActorId(1), shared),
            Float32(50 + (count - 1) * 5),
        )


def test_geodesic_horizon_before_at_and_beyond_the_last_waypoint() raises:
    var shared = _path_shared()
    _path(shared, 6)
    _put(shared, 1, 50, 1.75, 0, 0)
    var stage = CollisionStage()
    # The boundary starts at x=55 and stops on the first node strictly
    # beyond the horizon, or on the final node if none is beyond it.
    var lengths: List[Float32] = [2.5, 5, 10, 19, 20, 100]
    var ends: List[Float32] = [60, 65, 70, 75, 75, 75]
    for i in range(len(lengths)):
        shared.parameters.set_distance_to_leading_vehicle(
            ActorId(1), Length(lengths[i])
        )
        stage.clear_cycle_cache()
        var boundary = stage.get_geodesic_boundary(ActorId(1), shared)
        _ends(boundary, ends[i])
        assert_equal(len(boundary), 8)
        assert_true(boundary[1] == Vector3(55, 0.75, 0))
        assert_true(boundary[6] == Vector3(55, 2.75, 0))


def test_geodesic_turn_keeps_the_corner_and_final_waypoint() raises:
    var shared = _path_shared()
    _path(shared, 4)
    shared.parameters.set_distance_to_leading_vehicle(ActorId(1), Length(100))
    shared.local_map.waypoints[2].transform.rotation = CarlaRotation(
        Angle(0), Angle(90, DEGREE), Angle(0)
    )
    shared.local_map.waypoints[3].transform.rotation = CarlaRotation(
        Angle(0), Angle(90, DEGREE), Angle(0)
    )
    shared.local_map.waypoints[3].transform.location = Vector3(60, 6.75, 0)
    var stage = CollisionStage()
    var boundary = stage.get_geodesic_boundary(ActorId(1), shared)
    assert_equal(len(boundary), 10)
    # A width of 1 m on each side of an east-then-north path.
    var indices: List[Int] = [0, 1, 2, 7, 8, 9]
    var expected: List[Vector3] = [
        Vector3(61, 6.75, 0),
        Vector3(61, 1.75, 0),
        Vector3(55, 0.75, 0),
        Vector3(55, 2.75, 0),
        Vector3(59, 1.75, 0),
        Vector3(59, 6.75, 0),
    ]
    for i in range(len(indices)):
        assert_almost_equal(boundary[indices[i]].x, expected[i].x, atol=1e-6)
        assert_almost_equal(boundary[indices[i]].y, expected[i].y, atol=1e-6)
        assert_equal(boundary[indices[i]].z, 0.0)


def test_cache_clear_and_reset_recompute_after_motion() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    _ = stage.get_geometry_between_actors(ActorId(2), ActorId(1), shared)
    for reset in range(2):
        var x = Float32(70 + reset * 10)
        _put(shared, 2, x, 1.75, 0, 0)
        # Match the new pose with a forward path on lane -1 (index 60+x/5).
        var start = 60 + Int(x / 5) + 1
        shared.buffer_map[2] = [
            SimpleWaypointIndex(start),
            SimpleWaypointIndex(start + 1),
            SimpleWaypointIndex(start + 2),
        ]
        stage.collision_locks[1] = CollisionLock(5.0, 5.0, ActorId(2))
        if reset == 0:
            stage.clear_cycle_cache()
            assert_equal(len(stage.collision_locks), 1)
        else:
            stage.reset()
            assert_equal(len(stage.collision_locks), 0)
        assert_equal(len(stage.geometry_cache), 0)
        assert_equal(len(stage.geodesic_boundary_map), 0)
        var fresh = CollisionStage()
        # Compare against a cold stage with exactly the same lock state.
        fresh.collision_locks = stage.collision_locks.copy()
        var expected = fresh.get_geometry_between_actors(
            ActorId(1), ActorId(2), shared
        )
        assert_equal(expected.inter_bbox_distance, _box_gap(50, 1.75, x, 1.75))
        var result = stage.get_geometry_between_actors(
            ActorId(2), ActorId(1), shared
        )
        _same_geometry(result, _reverse(expected))
        _same_geometry(
            stage.get_geometry_between_actors(ActorId(1), ActorId(2), shared),
            expected,
        )


def test_collision_hazards_are_stable_after_either_cache_warmup() raises:
    var map = load_opendrive(straight_town())
    for first_reference in range(1, 3):
        var shared = _setup_follow(map, 50, 60, 5)
        var stage = CollisionStage()
        _ = stage.get_geometry_between_actors(
            ActorId(first_reference), ActorId(3 - first_reference), shared
        )
        for repeat in range(3):
            # Both update orders have identical hazards and available room.
            stage.update(repeat % 2, shared)
            stage.update(1 - repeat % 2, shared)
            assert_true(shared.collision_frame[0].hazard)
            assert_true(shared.collision_frame[0].hazard_actor_id == ActorId(2))
            assert_equal(
                shared.collision_frame[0].available_distance_margin.value,
                Float32(_box_gap(50, 1.75, 60, 1.75) - 2.0),
            )
            assert_false(shared.collision_frame[1].hazard)
            assert_equal(
                stage.collision_locks[1].distance_to_lead_vehicle,
                _box_gap(50, 1.75, 60, 1.75),
            )


def test_collision_hazard_at_final_buffered_waypoint() raises:
    var shared = _path_shared()
    _path(shared, 3)
    _put(shared, 1, 50, 1.75, 0, 10)
    _put(shared, 2, 62, 1.75, 0, 0)
    shared.track_traffic.update_grid_position(
        ActorId(1), shared.buffer_map[1], shared.local_map
    )
    shared.track_traffic.update_unregistered_grid_position(
        ActorId(2), [SimpleWaypointIndex(2)], shared.local_map
    )
    var stage = CollisionStage()
    # The path ends at x=60 and reaches the other's rear at x=59.6.
    # A lagged endpoint at x=55 misses this hazard entirely.
    stage.update(0, shared)
    assert_true(shared.collision_frame[0].hazard)
    assert_true(shared.collision_frame[0].hazard_actor_id == ActorId(2))
    assert_equal(
        shared.collision_frame[0].available_distance_margin.value,
        Float32(_box_gap(50, 1.75, 62, 1.75) - 2.0),
    )


def test_nearby_actor_on_a_separate_path_is_not_a_hazard() raises:
    var shared = _path_shared()
    _path(shared, 6)
    _put(shared, 2, 60, 5.25, 0, 0)
    var stage = CollisionStage()
    stage.collision_locks[1] = CollisionLock(5.0, 5.0, ActorId(2))
    var geometry = stage.get_geometry_between_actors(
        ActorId(1), ActorId(2), shared
    )
    # The strip's upper edge is y=2.75, the other's lower edge y=4.25.
    assert_equal(geometry.inter_geodesic_distance, 1.5)
    var result = stage.negotiate_collision(ActorId(1), ActorId(2), 0, shared)
    assert_false(result[0])
    assert_true(result[1] > 1e30)
    assert_false(1 in stage.collision_locks)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
