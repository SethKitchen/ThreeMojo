# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Traffic graph walks terminate without an arbitrary waypoint limit."""

from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road_info import RoadId, LaneId
from extensions.carla.transform import CarlaRotation
from units.si import Angle, DEGREE
from extensions.carla.traffic_manager_localization import (
    LocalizationStage,
    _branch_end,
    _buffer_places,
    _closest_branch,
)
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    ROAD_OPTION_LANE_FOLLOW,
    ROAD_OPTION_LEFT,
    ROAD_OPTION_RIGHT,
    ROAD_OPTION_STRAIGHT,
    ROAD_OPTION_VOID,
    SimpleWaypointIndex,
)
from extensions.carla.traffic_manager_random import RandomGenerator
from extensions.carla.traffic_manager_shared import TrafficManagerShared
from extensions.carla.traffic_manager_state import push_waypoint
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from test_carla_traffic_manager import straight_town
from test_carla_traffic_manager_stages import (
    Waypoint_at,
    _indices,
    _line,
    _localize,
    _put,
    _same,
    _vehicles,
)


def _link(mut shared: TrafficManagerShared, source: Int, target: Int):
    shared.local_map.waypoints[source].next_waypoints = [
        SimpleWaypointIndex(target)
    ]


def _seed(
    mut shared: TrafficManagerShared, nodes: List[Int]
) raises -> List[SimpleWaypointIndex]:
    var buffer = List[SimpleWaypointIndex]()
    for node in nodes:
        push_waypoint(
            ActorId(1),
            shared.track_traffic,
            buffer,
            shared.local_map,
            SimpleWaypointIndex(node),
        )
    return buffer^


def _assert_owners(shared: TrafficManagerShared, nodes: List[Int]) raises:
    for i in range(shared.local_map.size()):
        var owners = shared.track_traffic.get_passing_vehicles(
            shared.local_map.waypoints[i].id
        )
        if i in nodes:
            assert_equal(len(owners), 1)
            assert_true(owners[0] == ActorId(1))
        else:
            assert_equal(len(owners), 0)


def test_empty_buffer_has_no_visited_places() raises:
    var map = InMemoryMap()
    var places = _buffer_places(map, List[SimpleWaypointIndex]())
    assert_equal(len(places), 0)


def test_random_internal_start_and_self_cycles_stay_bounded() raises:
    var map = load_opendrive(straight_town())
    for back in [0, 1, 2]:
        var shared = _line(map, [(10.0, False), (12.0, False), (14.0, False)])
        _link(shared, 2, back)
        var stage = LocalizationStage()
        _put(shared, 1, 8, 1.75, 0, 0)
        _vehicles(shared, [1])
        for _ in range(20):
            _localize(stage, shared)
            _same(_indices(shared, 1), [0, 1, 2])
            _assert_owners(shared, [0, 1, 2])
        assert_equal(len(shared.marked_for_removal), 0)
        var expected = RandomGenerator(42)
        assert_equal(shared.random_device.next(), expected.next())


def test_cycle_trimming_keeps_passing_vehicle_ownership() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (12.0, False), (14.0, False)])
    _link(shared, 2, 1)
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _put(shared, 1, 11, 1.75, 0, 0)
    _localize(stage, shared)
    _same(_indices(shared, 1), [1, 2])
    _assert_owners(shared, [1, 2])


def test_distinct_indices_for_the_same_place_do_not_duplicate_ownership() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (12.0, False), (14.0, False)])
    var alias = shared.local_map.add_waypoint(map, Waypoint_at(1, -1, 12.0))
    _link(shared, 2, alias.value)
    var buffer = _seed(shared, [0])
    var stage = LocalizationStage()
    stage._extend_randomly(ActorId(1), 225.0, shared, buffer)
    assert_equal(len(buffer), 3)
    assert_equal(buffer[2].value, 2)
    _assert_owners(shared, [0, 1, 2, 3])


def test_fork_choices_and_random_draw_order_are_unchanged() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map,
        [
            (10.0, False),
            (12.0, False),
            (14.0, False),
            (13.0, False),
            (40.0, False),
        ],
    )
    shared.local_map.waypoints[0].next_waypoints = [
        SimpleWaypointIndex(1),
        SimpleWaypointIndex(3),
    ]
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _same(_indices(shared, 1), [0, 3, 4])
    var expected = RandomGenerator(42)
    _ = expected.next()
    assert_equal(shared.random_device.next(), expected.next())


def test_unreachable_imported_path_stays_pending_on_repeated_updates() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map, [(10.0, False), (12.0, False), (14.0, False), (100.0, False)]
    )
    _link(shared, 2, 1)
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    shared.parameters.set_custom_path(ActorId(1), [Vector3(100, 1.75, 0)], True)
    for _ in range(20):
        _localize(stage, shared)
        _same(_indices(shared, 1), [0, 1, 2])
        var remaining = shared.parameters.get_custom_path(ActorId(1))
        assert_equal(len(remaining), 1)
        assert_true(remaining[0] == Vector3(100, 1.75, 0))
        _assert_owners(shared, [0, 1, 2])
    assert_false(shared.parameters.get_upload_path(ActorId(1)))


def test_imported_route_keeps_unreached_options_on_a_cycle() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (12.0, False), (14.0, False)])
    _link(shared, 2, 1)
    for i in range(3):
        shared.local_map.waypoints[i].road_option = ROAD_OPTION_LANE_FOLLOW
    shared.local_map.waypoints[1].road_option = ROAD_OPTION_RIGHT
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    shared.parameters.set_imported_route(
        ActorId(1), [ROAD_OPTION_RIGHT, ROAD_OPTION_LEFT], True
    )
    for _ in range(20):
        _localize(stage, shared)
        _same(_indices(shared, 1), [0, 1, 2])
        var remaining = shared.parameters.get_imported_route(ActorId(1))
        assert_equal(len(remaining), 1)
        assert_true(remaining[0] == ROAD_OPTION_LEFT)
        _assert_owners(shared, [0, 1, 2])
    assert_false(shared.parameters.get_upload_route(ActorId(1)))


def test_imported_path_consumes_only_points_reached_before_a_cycle() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map, [(10.0, False), (12.0, False), (14.0, False), (100.0, False)]
    )
    _link(shared, 2, 1)
    var buffer = _seed(shared, [0])
    var stage = LocalizationStage()
    var path: List[Vector3] = [Vector3(12, 1.75, 0), Vector3(100, 1.75, 0)]
    stage._import_path(path^, buffer, ActorId(1), 225.0, shared)
    assert_equal(len(buffer), 3)
    var remaining = shared.parameters.get_custom_path(ActorId(1))
    assert_equal(len(remaining), 1)
    assert_true(remaining[0] == Vector3(100, 1.75, 0))


def test_imported_point_already_in_buffer_is_consumed() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (12.0, False)])
    var buffer = _seed(shared, [0])
    var stage = LocalizationStage()
    stage._import_path(
        [Vector3(10, 1.75, 0)], buffer, ActorId(1), 225.0, shared
    )
    assert_equal(len(buffer), 1)
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 0)
    _assert_owners(shared, [0])


def test_repeated_imported_points_make_progress_without_duplicate_nodes() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (12.0, False)])
    var buffer = _seed(shared, [0])
    var stage = LocalizationStage()
    stage._import_path(
        [Vector3(10, 1.75, 0), Vector3(10, 1.75, 0), Vector3(12, 1.75, 0)],
        buffer,
        ActorId(1),
        225.0,
        shared,
    )
    assert_equal(len(buffer), 2)
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 0)
    _assert_owners(shared, [0, 1])


def test_imported_self_loop_target_is_appended_once() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (12.0, False)])
    _link(shared, 1, 1)
    var buffer = _seed(shared, [0])
    var stage = LocalizationStage()
    stage._import_path(
        [Vector3(12, 1.75, 0)], buffer, ActorId(1), 225.0, shared
    )
    assert_equal(len(buffer), 2)
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 0)
    _assert_owners(shared, [0, 1])


def test_imported_alias_target_is_appended_once() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (12.0, False), (12.0, False)])
    _link(shared, 0, 2)
    _link(shared, 2, 1)
    var buffer = _seed(shared, [0])
    var stage = LocalizationStage()
    stage._import_path(
        [Vector3(12, 1.75, 0)], buffer, ActorId(1), 225.0, shared
    )
    assert_equal(len(buffer), 2)
    assert_equal(buffer[1].value, 1)
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 0)
    _assert_owners(shared, [0, 1, 2])


def test_imported_path_cannot_revisit_a_predecessor_of_its_target() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map, [(10.0, False), (20.0, False), (22.0, False), (24.0, False)]
    )
    _link(shared, 2, 1)
    _link(shared, 1, 3)
    var buffer = _seed(shared, [0, 1, 2])
    var stage = LocalizationStage()
    stage._import_path(
        [Vector3(24, 1.75, 0)], buffer, ActorId(1), 225.0, shared
    )
    assert_equal(len(buffer), 3)
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 1)
    _assert_owners(shared, [0, 1, 2])


def test_junction_cycle_has_no_end_or_safe_point() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map, [(10.0, False), (15.0, True), (20.0, True), (22.0, True)]
    )
    _link(shared, 3, 2)
    var buffer = _seed(shared, [0, 1])
    var stage = LocalizationStage()
    stage._extend_and_find_safe_space(ActorId(1), True, shared, buffer)
    assert_equal(len(buffer), 4)
    var points = stage.vehicles_at_junction_entrance[1]
    assert_false(points[0].is_some())
    assert_false(points[1].is_some())
    stage._extend_and_find_safe_space(ActorId(1), True, shared, buffer)
    assert_equal(len(buffer), 4)
    _assert_owners(shared, [0, 1, 2, 3])


def test_repeated_actor_updates_in_a_cyclic_junction() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (15.0, True), (20.0, True)])
    _link(shared, 2, 1)
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    for _ in range(20):
        _localize(stage, shared)
        _same(_indices(shared, 1), [0, 1, 2])
        assert_true(shared.localization_frame[0].is_at_junction_entrance)
        assert_false(shared.localization_frame[0].junction_end_point.is_some())
        assert_false(shared.localization_frame[0].safe_point.is_some())
        _assert_owners(shared, [0, 1, 2])


def test_later_fork_exit_refreshes_an_incomplete_safe_point() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map,
        [
            (10.0, False),
            (15.0, True),
            (20.0, True),
            (25.0, False),
            (30.0, False),
        ],
    )
    shared.local_map.waypoints[2].next_waypoints = [
        SimpleWaypointIndex(1),
        SimpleWaypointIndex(3),
    ]
    shared.buffer_map[1] = _seed(shared, [0, 1, 2])
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    # Seed 42 draws 79.654, 18.343, 77.969. Start with the second
    # draw, which selects the cycle. The next update selects the exit.
    _ = shared.random_device.next()
    _localize(stage, shared)
    _same(_indices(shared, 1), [0, 1, 2])
    assert_false(shared.localization_frame[0].junction_end_point.is_some())
    assert_false(shared.localization_frame[0].safe_point.is_some())
    _localize(stage, shared)
    _same(_indices(shared, 1), [0, 1, 2, 3, 4])
    assert_equal(shared.localization_frame[0].junction_end_point.value, 3)
    assert_equal(shared.localization_frame[0].safe_point.value, 4)
    _assert_owners(shared, [0, 1, 2, 3, 4])


def test_cycle_after_junction_keeps_end_without_inventing_safe_point() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map,
        [
            (10.0, False),
            (15.0, True),
            (25.0, False),
            (27.0, False),
            (28.0, False),
        ],
    )
    _link(shared, 4, 3)
    var buffer = _seed(shared, [0, 1])
    var stage = LocalizationStage()
    stage._extend_and_find_safe_space(ActorId(1), True, shared, buffer)
    assert_equal(len(buffer), 5)
    var points = stage.vehicles_at_junction_entrance[1]
    assert_equal(points[0].value, 2)
    assert_false(points[1].is_some())
    _assert_owners(shared, [0, 1, 2, 3, 4])


def test_forced_lane_change_stops_at_a_short_cycle() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (11.0, False), (12.0, False)])
    _link(shared, 2, 1)
    shared.local_map.waypoints[0].next_right_waypoint = SimpleWaypointIndex(1)
    var stage = LocalizationStage()
    var selected = stage._assign_lane_change(
        ActorId(1),
        Vector3(8, 1.75, 0),
        0.0,
        True,
        True,
        shared,
        [SimpleWaypointIndex(0)],
    )
    assert_equal(selected.value, 2)


def test_fork_probe_stops_in_each_cyclic_phase() raises:
    var map = load_opendrive(straight_town())
    # Before the junction, inside it, and within 7 m after its start.
    for phase in range(3):
        var shared = _line(
            map, [(10.0, phase == 1), (11.0, phase != 0), (12.0, phase == 1)]
        )
        _link(shared, 2, 2)
        assert_false(
            _branch_end(shared.local_map, SimpleWaypointIndex(0)).is_some()
        )
        assert_equal(
            _closest_branch(
                shared.local_map,
                [SimpleWaypointIndex(0)],
                SimpleWaypointIndex(2),
            ),
            0,
        )


def test_fork_probe_skips_disconnected_and_cyclic_branches() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(
        map,
        [
            (10.0, False),
            (11.0, True),
            (12.0, True),
            (30.0, True),
            (40.0, False),
        ],
    )
    shared.local_map.waypoints[0].next_waypoints = List[SimpleWaypointIndex]()
    _link(shared, 2, 1)
    assert_equal(
        _closest_branch(
            shared.local_map,
            [
                SimpleWaypointIndex(0),
                SimpleWaypointIndex(1),
                SimpleWaypointIndex(3),
            ],
            SimpleWaypointIndex(4),
        ),
        2,
    )
    assert_equal(_branch_end(shared.local_map, SimpleWaypointIndex(3)).value, 4)


def test_cyclic_junction_keeps_existing_road_options() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (15.0, True), (20.0, True)])
    _link(shared, 2, 1)
    shared.local_map.waypoints[1].road_option = ROAD_OPTION_RIGHT
    shared.local_map.waypoints[2].road_option = ROAD_OPTION_LEFT
    shared.local_map._assign_turn(SimpleWaypointIndex(1))
    assert_true(shared.local_map.waypoints[1].road_option == ROAD_OPTION_RIGHT)
    assert_true(shared.local_map.waypoints[2].road_option == ROAD_OPTION_LEFT)
    shared.local_map.waypoints[0].next_waypoints = [
        SimpleWaypointIndex(1),
        SimpleWaypointIndex(2),
    ]
    shared.local_map.set_up_road_option(map)
    assert_true(shared.local_map.waypoints[1].road_option == ROAD_OPTION_RIGHT)
    assert_true(shared.local_map.waypoints[2].road_option == ROAD_OPTION_LEFT)


def test_long_acyclic_path_has_no_fixed_walk_limit() raises:
    var map = load_opendrive(straight_town())
    var local = InMemoryMap()
    # Every point is inside the requested horizon, but the route is finite.
    # More nodes than a small fixed walk budget must all remain reachable.
    for i in range(2048):
        _ = local.add_waypoint(
            map, Waypoint_at(1, -1, 10.0 + Float64(i) / 10.0)
        )
        if i > 0:
            _ = local.set_next_waypoints(
                SimpleWaypointIndex(i - 1), [SimpleWaypointIndex(i)]
            )
    var shared = TrafficManagerShared(local^, 42)
    var buffer = _seed(shared, [0])
    var stage = LocalizationStage()
    stage._extend_randomly(ActorId(1), 1000000.0, shared, buffer)
    assert_equal(len(buffer), 2048)
    assert_equal(buffer[2047].value, 2047)
    assert_equal(len(shared.marked_for_removal), 1)
    # The same finite route also terminates with an unmet imported option.
    shared.parameters.set_imported_route(ActorId(1), [ROAD_OPTION_RIGHT], True)
    stage._import_route(
        [ROAD_OPTION_RIGHT], buffer, ActorId(1), 1000000.0, shared
    )
    assert_equal(len(buffer), 2048)
    assert_equal(buffer[2047].value, 2047)
    assert_equal(len(shared.marked_for_removal), 2)
    assert_equal(len(shared.parameters.get_imported_route(ActorId(1))), 1)


def test_lane_change_obstacle_filters_and_near_lane_availability() raises:
    var map = load_opendrive(straight_town())
    # Two same-grid vehicles, with a free lane beside both. Vary just one
    # geometric discriminator or lane-availability fact at a time.
    for scenario in range(8):
        var shared = _line(
            map, [(10.0, False), (40.0, False), (60.0, False), (70.0, False)]
        )
        shared.local_map.waypoints[0].next_right_waypoint = SimpleWaypointIndex(
            2
        )
        shared.local_map.waypoints[1].next_right_waypoint = SimpleWaypointIndex(
            3
        )
        shared.buffer_map[2] = [SimpleWaypointIndex(1)]
        shared.track_traffic.update_grid_position(
            ActorId(1), [SimpleWaypointIndex(0)], shared.local_map
        )
        shared.track_traffic.update_grid_position(
            ActorId(2), [SimpleWaypointIndex(0)], shared.local_map
        )
        if scenario == 1:
            shared.local_map.waypoints[0].is_junction = True
        elif scenario == 2:
            shared.local_map.waypoints[1].waypoint.road_id = RoadId(2)
        elif scenario == 3:
            shared.local_map.waypoints[1].waypoint.lane_id = LaneId(-2)
        elif scenario == 4:
            shared.local_map.waypoints[1].transform.rotation = CarlaRotation(
                Angle(0, DEGREE), Angle(180, DEGREE), Angle(0, DEGREE)
            )
        elif scenario == 5:
            shared.local_map.waypoints[
                0
            ].next_right_waypoint = SimpleWaypointIndex(-1)
        elif scenario == 6:
            shared.track_traffic.update_passing_vehicle(
                shared.local_map.waypoints[2].id, ActorId(3)
            )
        if scenario == 7:
            shared.local_map.waypoints[
                1
            ].next_right_waypoint = SimpleWaypointIndex(-1)
            shared.local_map.waypoints[
                1
            ].next_left_waypoint = SimpleWaypointIndex(3)
        var stage = LocalizationStage()
        var selected = stage._assign_lane_change(
            ActorId(1),
            Vector3(10, 1.75, 0),
            0.0,
            False,
            True,
            shared,
            [SimpleWaypointIndex(0)],
        )
        assert_equal(selected.is_some(), scenario == 0)
        if scenario == 0:
            assert_equal(selected.value, 3)


def test_horizon_trim_keeps_a_far_junction_tail() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (20.0, False), (60.0, True)])
    shared.buffer_map[1] = _seed(shared, [0, 1, 2])
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _same(_indices(shared, 1), [0, 1, 2])


def test_town03_entrance_outside_roundabout_radius_is_kept() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(100.0, False), (105.0, True)])
    shared.local_map.name = "Carla/Maps/Town03"
    var stage = LocalizationStage()
    assert_true(
        stage._at_junction_entrance(
            shared.local_map,
            [SimpleWaypointIndex(0), SimpleWaypointIndex(1)],
            Vector3(100, 1.75, 0),
        )
    )


def test_safe_space_stops_at_nearby_fork_or_next_junction() raises:
    var map = load_opendrive(straight_town())
    for fork in [True, False]:
        var shared = _line(
            map,
            [
                (10.0, False),
                (15.0, True),
                (25.0, False),
                (27.0, not fork),
                (28.0, False),
                (29.0, False),
            ],
        )
        if fork:
            shared.local_map.waypoints[3].next_waypoints = [
                SimpleWaypointIndex(4),
                SimpleWaypointIndex(5),
            ]
        var buffer = _seed(shared, [0, 1])
        var stage = LocalizationStage()
        stage._extend_and_find_safe_space(ActorId(1), True, shared, buffer)
        var points = stage.vehicles_at_junction_entrance[1]
        assert_equal(points[0].value, 2)
        assert_equal(points[1].value, 3)


def test_forced_lane_change_stops_on_junction_destination() raises:
    var map = load_opendrive(straight_town())
    var shared = _line(map, [(10.0, False), (20.0, True), (30.0, False)])
    shared.local_map.waypoints[0].next_right_waypoint = SimpleWaypointIndex(1)
    var stage = LocalizationStage()
    var selected = stage._assign_lane_change(
        ActorId(1),
        Vector3(10, 1.75, 0),
        0.0,
        True,
        True,
        shared,
        [SimpleWaypointIndex(0)],
    )
    assert_equal(selected.value, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
