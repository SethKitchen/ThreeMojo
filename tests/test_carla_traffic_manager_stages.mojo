# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's traffic manager: the localization and collision stages.

The stages run on hand-made states, with no physics. The expected paths
are worked by hand on the straight town of `test_carla_traffic_manager`:
a node each 5 m, lane -2 first (index x / 5), then lane -1 (60 + x / 5),
then lane 1. The random draws for seed 42 come from `tm_model.py`, a
Python model outside the repository: 79.654, 18.343, 77.969, 59.685.
The turn through the junction town's road 11 is an arc of radius 8.25 m
about (100, 10);
`tm_model.py` gives its nodes, the circle through the path, 10.35 m, and
the junction's length along the path, 17.955 m.
"""

from extensions.carla.actor import ActorId, GREEN, NO_ACTOR, RED
from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import load_opendrive
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.road_info import JuncId, LaneId, RoadId, SectionId
from extensions.carla.traffic_manager_collision import (
    CollisionLock,
    CollisionStage,
    GeometryComparison,
    collision_yields,
    polygon_distance,
)
from extensions.carla.traffic_manager_localization import (
    LocalizationStage,
    first_next,
)
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    NO_SIMPLE_WAYPOINT,
    ROAD_OPTION_CHANGE_LANE_LEFT,
    ROAD_OPTION_CHANGE_LANE_RIGHT,
    ROAD_OPTION_LANE_FOLLOW,
    ROAD_OPTION_LEFT,
    ROAD_OPTION_RIGHT,
    ROAD_OPTION_ROAD_END,
    ROAD_OPTION_STRAIGHT,
    ROAD_OPTION_VOID,
    SimpleWaypointIndex,
)
from extensions.carla.traffic_manager_shared import (
    APPLY_TRANSFORM,
    APPLY_VEHICLE_CONTROL,
    CommandKind,
    LargeVehicle,
    NO_COMMAND,
    SET_VEHICLE_LIGHT_STATE,
    TrafficManagerShared,
    apply_transform,
    no_command,
    no_localization,
)
from extensions.carla.traffic_manager_state import (
    KinematicState,
    StaticAttributes,
    TRAFFIC_ANY,
    TRAFFIC_PEDESTRIAN,
    TRAFFIC_VEHICLE,
    TrafficActorType,
    TrafficLightInfo,
)
from extensions.carla.transform import CarlaRotation
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from test_carla_traffic_manager import junction_town, straight_town
from units.si import Angle, DEGREE, Length, Velocity


def _near(a: Float32, b: Float32, tol: Float64 = 1e-4) raises:
    assert_almost_equal(a, b, atol=tol)


def _shared(
    map: Map, seed: UInt64 = 42, name: String = ""
) raises -> TrafficManagerShared:
    var local = InMemoryMap(name)
    local.set_up(map)
    return TrafficManagerShared(local^, seed)


def _put(
    mut shared: TrafficManagerShared,
    id: Int,
    x: Float32,
    y: Float32,
    yaw: Float32,
    speed: Float32,
    kind: TrafficActorType = TRAFFIC_VEHICLE,
    light: TrafficLightInfo = TrafficLightInfo(GREEN, False),
) raises:
    var rotation = CarlaRotation(
        Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)
    )
    var state = KinematicState(
        Vector3(x, y, 0),
        rotation,
        rotation.forward_vector() * speed,
        Velocity(30, KILOMETER_PER_HOUR),
        True,
        False,
        Vector3(0, 0, 0),
    )
    var actor = ActorId(id)
    if shared.simulation_state.contains_actor(actor):
        shared.simulation_state.update_kinematic_state(actor, state)
        shared.simulation_state.update_traffic_light_state(actor, light)
    else:
        shared.simulation_state.add_actor(
            actor,
            state,
            StaticAttributes(kind, Length(2.4), Length(1.0), Length(0.75)),
            light,
        )


def _vehicles(mut shared: TrafficManagerShared, ids: List[Int]):
    shared.vehicle_id_list = List[ActorId]()
    for id in ids:
        shared.vehicle_id_list.append(ActorId(id))
    shared.reset_frames()


def _localize(
    mut stage: LocalizationStage, mut shared: TrafficManagerShared
) raises:
    for i in range(len(shared.vehicle_id_list)):
        stage.update(i, shared)


def _indices(shared: TrafficManagerShared, id: Int) -> List[Int]:
    var out = List[Int]()
    for w in shared.buffer(ActorId(id)):
        out.append(w.value)
    return out^


def _range(first: Int, last: Int) -> List[Int]:
    var out = List[Int]()
    for i in range(first, last + 1):
        out.append(i)
    return out^


def _same(a: List[Int], b: List[Int]) raises:
    assert_equal(len(a), len(b))
    for i in range(len(a)):
        assert_equal(a[i], b[i])


# --- localization -----------------------------------------------------------------


def test_path_grows_moves_and_trims() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 20, 1.75, 0, 0)
    _vehicles(shared, [1])
    # From the node under the vehicle to 20 m on, past the 15 m horizon.
    _localize(stage, shared)
    _same(_indices(shared, 1), _range(64, 68))
    assert_false(shared.localization_frame[0].is_at_junction_entrance)
    # The node under the vehicle is dropped: it is not ahead.
    _localize(stage, shared)
    _same(_indices(shared, 1), _range(65, 69))
    # 35 m from the path: it starts again at x = 60.
    _put(shared, 1, 60, 1.75, 0, 0)
    _localize(stage, shared)
    _same(_indices(shared, 1), _range(72, 76))
    # 20 m/s is above 60 km/h: a horizon of 80 m, from x = 65 to 150.
    _put(shared, 1, 60, 1.75, 0, 20)
    _localize(stage, shared)
    _same(_indices(shared, 1), _range(73, 90))
    # Stopped again: the path is cut back to 20 m, within twice 15^2.
    _put(shared, 1, 60, 1.75, 0, 0)
    _localize(stage, shared)
    _same(_indices(shared, 1), _range(73, 77))
    # A vehicle past every node of its path starts again.
    _put(shared, 1, 90, 1.75, 180, 0)
    _localize(stage, shared)
    assert_equal(_indices(shared, 1)[0], 78)
    with assert_raises(contains="out of range"):
        stage.update(3, shared)


def test_forced_lane_changes() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 50, 1.75, 0, 10)
    _vehicles(shared, [1])
    # Right from lane -1 at x = 50: lane -2, 15 m on (1.5 s at 10 m/s).
    shared.parameters.set_force_lane_change(ActorId(1), True)
    _localize(stage, shared)
    var path = _indices(shared, 1)
    assert_equal(path[0], 13)
    assert_equal(path[len(path) - 1], 18)
    var action = stage.compute_next_action(ActorId(1), shared)
    assert_true(action.road_option == ROAD_OPTION_CHANGE_LANE_RIGHT)
    assert_equal(action.waypoint.value().s, 65.0)
    var actions = stage.compute_action_buffer(ActorId(1), shared)
    assert_equal(len(actions), 2)
    assert_true(actions[0].road_option == ROAD_OPTION_LANE_FOLLOW)
    assert_true(actions[1].road_option == ROAD_OPTION_CHANGE_LANE_RIGHT)
    # Another vehicle on lane -1 is told left: there is no lane there.
    _put(shared, 2, 150, 1.75, 0, 10)
    _vehicles(shared, [2])
    shared.parameters.set_force_lane_change(ActorId(2), False)
    _localize(stage, shared)
    assert_equal(_indices(shared, 2)[0], 90)
    # Left from lane -2 works.
    _put(shared, 3, 150, 5.25, 0, 10)
    _vehicles(shared, [3])
    shared.parameters.set_force_lane_change(ActorId(3), False)
    _localize(stage, shared)
    assert_equal(_indices(shared, 3)[0], 93)
    var left = stage.compute_next_action(ActorId(3), shared)
    assert_true(left.road_option == ROAD_OPTION_CHANGE_LANE_LEFT)
    # Right from lane -2: none.
    _put(shared, 4, 200, 5.25, 0, 10)
    _vehicles(shared, [4])
    shared.parameters.set_force_lane_change(ActorId(4), True)
    _localize(stage, shared)
    assert_equal(_indices(shared, 4)[0], 40)
    # No path, no action.
    assert_true(
        stage.compute_next_action(ActorId(9), shared).road_option
        == ROAD_OPTION_VOID
    )
    assert_equal(len(stage.compute_action_buffer(ActorId(9), shared)), 0)
    assert_true(
        stage.compute_next_action(ActorId(4), shared).road_option
        == ROAD_OPTION_LANE_FOLLOW
    )
    stage.remove_actor(ActorId(1))
    stage.remove_actor(ActorId(1))
    stage.reset()


def test_a_second_lane_change_waits() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 50, 1.75, 0, 10)
    _vehicles(shared, [1])
    shared.parameters.set_force_lane_change(ActorId(1), True)
    _localize(stage, shared)
    # Back left at once: within (10 v)^2 of the last change, it waits.
    _put(shared, 1, 55, 5.25, 0, 10)
    shared.parameters.set_force_lane_change(ActorId(1), False)
    _localize(stage, shared)
    assert_equal(
        shared.local_map.at(
            shared.buffer(ActorId(1))[0]
        ).waypoint.lane_id.value,
        -2,
    )
    # 105 m on, past (10 v)^2 = 100^2, the last change is done with: left
    # to lane -1, 15 m on from x = 170.
    _put(shared, 1, 170, 5.25, 0, 10)
    shared.parameters.set_force_lane_change(ActorId(1), False)
    _localize(stage, shared)
    assert_equal(_indices(shared, 1)[0], 97)


def test_random_lane_changes_with_seed_42() raises:
    var map = load_opendrive(straight_town())
    # Keep right -1 > 79.65 no; right 50 >= 18.34 yes; left 50 >= 77.97
    # no: right.
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 50, 1.75, 0, 10)
    _vehicles(shared, [1])
    shared.parameters.set_random_left_lane_change_percentage(ActorId(1), 50)
    shared.parameters.set_random_right_lane_change_percentage(ActorId(1), 50)
    _localize(stage, shared)
    assert_equal(_indices(shared, 1)[0], 13)
    # Both win on lane -2: the fourth draw, 59.69, is not below 50, so
    # left.
    var both = _shared(map)
    var stage2 = LocalizationStage()
    _put(both, 1, 50, 5.25, 0, 10)
    _vehicles(both, [1])
    both.parameters.set_random_left_lane_change_percentage(ActorId(1), 100)
    both.parameters.set_random_right_lane_change_percentage(ActorId(1), 100)
    _localize(stage2, both)
    assert_equal(_indices(both, 1)[0], 73)
    # Keep right: 100 > 79.65, a right change on a right-hand road.
    var keep = _shared(map)
    var stage3 = LocalizationStage()
    _put(keep, 1, 50, 1.75, 0, 10)
    _vehicles(keep, [1])
    keep.parameters.set_keep_slow_lane_percentage(ActorId(1), 100)
    _localize(stage3, keep)
    assert_equal(_indices(keep, 1)[0], 13)
    # Only a left change wins: from lane -2 to lane -1.
    var only_left = _shared(map, 7)
    var stage4 = LocalizationStage()
    _put(only_left, 1, 50, 5.25, 0, 10)
    _vehicles(only_left, [1])
    only_left.parameters.set_random_left_lane_change_percentage(ActorId(1), 100)
    _localize(stage4, only_left)
    assert_equal(_indices(only_left, 1)[0], 73)
    # Too slow for a random change.
    var slow = _shared(map)
    var stage5 = LocalizationStage()
    _put(slow, 1, 50, 1.75, 0, 4)
    _vehicles(slow, [1])
    slow.parameters.set_random_right_lane_change_percentage(ActorId(1), 100)
    _localize(stage5, slow)
    assert_equal(_indices(slow, 1)[0], 70)


def test_keep_left_on_a_left_hand_road() raises:
    # On a left-hand road, lanes 1 and 2 run with s; keeping to the slow
    # lane is a left change, from lane 1 to lane 2.
    var text = straight_town().replace(
        'junction="-1">', 'junction="-1" rule="LHT">'
    )
    text = text.replace(
        """<lane id="1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" weight="standard" color="white" width="0.15" laneChange="none"/></lane>""",
        """<lane id="2" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" weight="standard" color="white" width="0.15" laneChange="none"/></lane>
        <lane id="1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" weight="standard" color="white" width="0.15" laneChange="both"/></lane>""",
    )
    var map = load_opendrive(text)
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 50, -1.75, 0, 10)
    _vehicles(shared, [1])
    shared.parameters.set_keep_slow_lane_percentage(ActorId(1), 100)
    _localize(stage, shared)
    ref first = shared.local_map.at(shared.buffer(ActorId(1))[0])
    assert_equal(first.waypoint.lane_id.value, 2)
    _near(first.location().x, 65.0)


def test_auto_lane_change_passes_a_slow_vehicle() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    # The ego at x = 50 on lane -1, 10 m/s; a stopped vehicle at x = 80.
    _put(shared, 1, 50, 1.75, 0, 10)
    _put(shared, 2, 80, 1.75, 0, 0)
    _vehicles(shared, [1, 2])
    _localize(stage, shared)
    # Their paths now share grid 15 (x = 75 to 95 on lane -1).
    _localize(stage, shared)
    # 30 m ahead, the right lane free by the obstacle and beside the ego:
    # right, 15 m on from x = 55.
    assert_equal(_indices(shared, 1)[0], 14)


def test_no_lane_change_near_or_blocked() raises:
    var map = load_opendrive(straight_town())
    # Too close: 15 m.
    var near = _shared(map)
    var stage = LocalizationStage()
    _put(near, 1, 50, 1.75, 0, 10)
    _put(near, 2, 65, 1.75, 0, 0)
    _vehicles(near, [1, 2])
    _localize(stage, near)
    _localize(stage, near)
    assert_equal(_indices(near, 1)[0], 71)
    # The right lane beside the obstacle is taken by a third vehicle.
    var blocked = _shared(map)
    var stage2 = LocalizationStage()
    _put(blocked, 1, 50, 1.75, 0, 10)
    _put(blocked, 2, 80, 1.75, 0, 0)
    _put(blocked, 3, 78, 5.25, 0, 0)
    _vehicles(blocked, [1, 2, 3])
    _localize(stage2, blocked)
    _localize(stage2, blocked)
    assert_equal(_indices(blocked, 1)[0], 71)
    # With auto lane change off, nothing happens.
    var off = _shared(map)
    var stage3 = LocalizationStage()
    _put(off, 1, 50, 1.75, 0, 10)
    _put(off, 2, 80, 1.75, 0, 0)
    _vehicles(off, [1, 2])
    off.parameters.set_auto_lane_change(ActorId(1), False)
    _localize(stage3, off)
    _localize(stage3, off)
    assert_equal(_indices(off, 1)[0], 71)


def test_auto_lane_change_to_the_left() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    # On lane -2: the obstacle's left lane is free.
    _put(shared, 1, 50, 5.25, 0, 10)
    _put(shared, 2, 80, 5.25, 0, 0)
    # A walker on lane 1 and a vehicle far behind do not count.
    _put(shared, 3, 60, -1.75, 180, 0)
    _put(shared, 4, 5, 5.25, 0, 0)
    _vehicles(shared, [1, 2, 3, 4])
    _localize(stage, shared)
    _localize(stage, shared)
    assert_equal(_indices(shared, 1)[0], 74)
    # The left lane beside the ego is taken: no change.
    var taken = _shared(map)
    var stage2 = LocalizationStage()
    _put(taken, 1, 50, 5.25, 0, 10)
    _put(taken, 2, 80, 5.25, 0, 0)
    _put(taken, 3, 53, 1.75, 0, 0)
    _vehicles(taken, [1, 2, 3])
    _localize(stage2, taken)
    _localize(stage2, taken)
    assert_equal(_indices(taken, 1)[0], 11)


def test_dead_ends_are_marked() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 290, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    assert_equal(len(shared.marked_for_removal), 1)
    shared.parameters.set_osm_mode(False)
    _localize(stage, shared)
    assert_equal(len(shared.marked_for_removal), 2)
    # A forced change near the end stops where the lane does.
    _put(shared, 2, 290, 1.75, 0, 10)
    _vehicles(shared, [2])
    shared.parameters.set_force_lane_change(ActorId(2), True)
    _localize(stage, shared)
    assert_equal(_indices(shared, 2)[0], 59)


def test_first_next_at_a_dead_end() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    assert_equal(first_next(shared.local_map, SimpleWaypointIndex(3)).value, 4)
    assert_false(
        first_next(shared.local_map, SimpleWaypointIndex(59)).is_some()
    )


def test_a_loop_stops_the_path() raises:
    var map = load_opendrive(straight_town())
    var local = InMemoryMap()
    var a = local.add_waypoint(map, Waypoint_at(1, -1, 10.0))
    var b = local.add_waypoint(map, Waypoint_at(1, -1, 15.0))
    _ = local.set_next_waypoints(a, [b])
    _ = local.set_next_waypoints(b, [a])
    local.set_up_road_option(map)
    var shared = TrafficManagerShared(local^, 42)
    shared.local_map.set_up_spatial_tree()
    var stage = LocalizationStage()
    _put(shared, 1, 10, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _same(_indices(shared, 1), [0, 1])


def Waypoint_at(road: Int, lane: Int, s: Float64) -> Waypoint:
    return Waypoint(RoadId(road), SectionId(0), LaneId(lane), s)


def test_junction_entrance_and_safe_point() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 92, 1.75, 0, 0)
    _vehicles(shared, [1])
    # The first step only builds the path: node 18 (x = 90) on. The fork
    # draws 79.65: index 2 of three (road 10 twice, road 11): the turn.
    _localize(stage, shared)
    assert_false(shared.localization_frame[0].is_at_junction_entrance)
    var path = _indices(shared, 1)
    assert_equal(path[0], 18)
    assert_equal(path[2], 128)
    assert_equal(path[len(path) - 1], 136)
    # The second step: the node 5 m on is in the junction. The path runs
    # through it to road 3's first node (80), and on to the safe point 5 m
    # past it (81).
    _localize(stage, shared)
    var entrance = shared.localization_frame[0]
    assert_true(entrance.is_at_junction_entrance)
    assert_equal(entrance.junction_end_point.value, 80)
    assert_equal(entrance.safe_point.value, 81)
    var after = _indices(shared, 1)
    assert_equal(after[len(after) - 1], 81)
    # The next move is the right turn.
    var action = stage.compute_next_action(ActorId(1), shared)
    assert_true(action.road_option == ROAD_OPTION_RIGHT)
    var actions = stage.compute_action_buffer(ActorId(1), shared)
    assert_true(actions[1].road_option == ROAD_OPTION_RIGHT)
    assert_true(actions[2].road_option == ROAD_OPTION_LANE_FOLLOW)
    # Past road 1's last node, before the junction's first: the first node
    # is in the junction and the one before it is not, an entrance.
    _put(shared, 1, 97, 1.75, 0, 0)
    _localize(stage, shared)
    assert_true(shared.localization_frame[0].is_at_junction_entrance)
    # Past the junction: no longer.
    _put(shared, 1, 108.25, 12, 90, 0)
    _localize(stage, shared)
    assert_false(shared.localization_frame[0].is_at_junction_entrance)


def test_large_vehicle_measures_its_turn() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    shared.large_vehicles[1] = LargeVehicle(Length(0), False)
    _put(shared, 1, 92, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _localize(stage, shared)
    # The circle through the path is 10.35 m, under 20 m: a turn, right,
    # 17.955 m through the junction.
    var large = shared.large_vehicles[1]
    assert_true(large.turn_right)
    _near(large.junction_length.value, 17.955367, 1e-3)
    # In the junction, then out of it: the length goes back to zero.
    _put(shared, 1, 103.9, 2.9, 30, 0)
    _localize(stage, shared)
    _near(shared.large_vehicles[1].junction_length.value, 17.955367, 1e-3)
    _put(shared, 1, 108.25, 30, 90, 0)
    _localize(stage, shared)
    assert_equal(shared.large_vehicles[1].junction_length.value, 0.0)
    stage.remove_actor(ActorId(1))


def test_large_vehicle_going_straight() raises:
    # The draw picks road 10 for seed 7 (tm_model.py: 22.73, index 0):
    # the path is straight, the circle has no radius, no offset.
    var map = load_opendrive(junction_town())
    var shared = _shared(map, UInt64(7) + (UInt64(1) << 32))
    var stage = LocalizationStage()
    shared.large_vehicles[1] = LargeVehicle(Length(0), False)
    _put(shared, 1, 92, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _localize(stage, shared)
    assert_equal(shared.large_vehicles[1].junction_length.value, 0.0)
    assert_equal(
        shared.local_map.at(
            shared.buffer(ActorId(1))[2]
        ).waypoint.road_id.value,
        10,
    )


def test_town03_roundabout_exception() raises:
    # A junction node 5 m past the origin: an entrance, but not on the
    # map CARLA calls Town03 within 30 m of the origin.
    var map = load_opendrive(straight_town())
    for name in ["", "Carla/Maps/Town03"]:
        var local = InMemoryMap(name)
        var a = local.add_waypoint(map, Waypoint_at(1, -1, 10.0))
        var b = local.add_waypoint(map, Waypoint_at(1, -1, 15.0))
        var c = local.add_waypoint(map, Waypoint_at(1, -1, 25.0))
        var d = local.add_waypoint(map, Waypoint_at(1, -1, 30.0))
        local.waypoints[b.value].is_junction = True
        _ = local.set_next_waypoints(a, [b])
        _ = local.set_next_waypoints(b, [c])
        _ = local.set_next_waypoints(c, [d])
        local.set_up_spatial_tree()
        var shared = TrafficManagerShared(local^, 42)
        var stage = LocalizationStage()
        _put(shared, 1, 9, 1.75, 0, 0)
        _vehicles(shared, [1])
        _localize(stage, shared)
        _localize(stage, shared)
        assert_equal(
            shared.localization_frame[0].is_at_junction_entrance, name == ""
        )


def test_imported_path_across_lanes() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    # 20 m/s: an 80 m horizon. Along lane -1 to x = 75; at x = 80 the
    # first point (lane -2) is 3.5 m away, under sqrt(30): the path steps
    # over to it, then on to the second point.
    _put(shared, 1, 50, 1.75, 0, 20)
    _vehicles(shared, [1])
    shared.parameters.set_custom_path(
        ActorId(1), [Vector3(80, 5.25, 0), Vector3(100, 5.25, 0)], False
    )
    _localize(stage, shared)
    var path = _indices(shared, 1)
    _same(path, [70, 71, 72, 73, 74, 75, 16, 17, 18, 19, 20])
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 0)
    # A path uploaded over the old one, and cut short by the horizon.
    _put(shared, 1, 50, 1.75, 0, 0)
    shared.parameters.set_custom_path(ActorId(1), [Vector3(200, 1.75, 0)], True)
    _localize(stage, shared)
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 1)
    assert_false(shared.parameters.get_upload_path(ActorId(1)))
    # A path to a dead end.
    _put(shared, 1, 285, 1.75, 0, 0)
    # A point back on lane 1: never within reach, so the path runs on to
    # the lane's end.
    shared.parameters.set_custom_path(ActorId(1), [Vector3(0, -1.75, 0)], True)
    _localize(stage, shared)
    assert_equal(len(shared.marked_for_removal), 1)
    shared.parameters.set_osm_mode(False)
    _localize(stage, shared)
    assert_equal(len(shared.marked_for_removal), 2)


def test_imported_path_through_a_fork() raises:
    var map = load_opendrive(junction_town())
    # A point on road 3: the turn's branch ends on road 3.
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 90, 1.75, 0, 20)
    _vehicles(shared, [1])
    shared.parameters.set_custom_path(
        ActorId(1), [Vector3(108.25, 40, 0)], False
    )
    _localize(stage, shared)
    assert_equal(
        shared.local_map.at(
            shared.buffer(ActorId(1))[2]
        ).waypoint.road_id.value,
        11,
    )
    # A point on road 10's lane 1, no branch's end road: the branch whose
    # end is nearest it. Road 2's start, (120, 1.75), is 28 m^2 away;
    # road 3's, (108.25, 10), 198 m^2.
    var near = _shared(map)
    var stage2 = LocalizationStage()
    _put(near, 1, 90, 1.75, 0, 20)
    _vehicles(near, [1])
    near.parameters.set_custom_path(ActorId(1), [Vector3(116, -1.75, 0)], False)
    _localize(stage2, near)
    assert_equal(
        near.local_map.at(near.buffer(ActorId(1))[2]).waypoint.road_id.value, 10
    )


def test_imported_route() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 80, 1.75, 0, 0)
    _vehicles(shared, [1])
    shared.parameters.set_imported_route(ActorId(1), [ROAD_OPTION_RIGHT], True)
    _localize(stage, shared)
    var path = _indices(shared, 1)
    # Along road 1, then the turn's first node, where the route is used up.
    assert_equal(path[len(path) - 1], 128)
    assert_equal(len(shared.parameters.get_imported_route(ActorId(1))), 0)
    # A route option no branch has: the first branch, with a note.
    var other = _shared(map)
    var stage2 = LocalizationStage()
    _put(other, 1, 80, 1.75, 0, 0)
    _vehicles(other, [1])
    other.parameters.set_imported_route(
        ActorId(1), [ROAD_OPTION_LEFT, ROAD_OPTION_RIGHT], False
    )
    _localize(stage2, other)
    assert_equal(len(other.parameters.get_imported_route(ActorId(1))), 2)
    # A route that reaches a dead end.
    var straight = load_opendrive(straight_town())
    var dead = _shared(straight)
    var stage3 = LocalizationStage()
    _put(dead, 1, 290, 1.75, 0, 0)
    _vehicles(dead, [1])
    dead.parameters.set_imported_route(
        ActorId(1), [ROAD_OPTION_STRAIGHT], False
    )
    _localize(stage3, dead)
    assert_equal(len(dead.marked_for_removal), 1)
    dead.parameters.set_osm_mode(False)
    _localize(stage3, dead)
    assert_equal(len(dead.marked_for_removal), 2)


# --- collision ----------------------------------------------------------------------


def test_polygon_distance() raises:
    var a: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        Vector3(2, 2, 0),
        Vector3(0, 2, 0),
    ]
    var far: List[Vector3] = [
        Vector3(5, 0, 0),
        Vector3(7, 0, 0),
        Vector3(7, 2, 0),
        Vector3(5, 2, 0),
    ]
    assert_almost_equal(polygon_distance(a, far), 3.0, atol=1e-9)
    var inside: List[Vector3] = [
        Vector3(0.5, 0.5, 0),
        Vector3(1, 0.5, 0),
        Vector3(1, 1, 0),
    ]
    assert_equal(polygon_distance(a, inside), 0.0)
    assert_equal(polygon_distance(inside, a), 0.0)
    var crossing: List[Vector3] = [
        Vector3(1, 1, 0),
        Vector3(3, 1, 0),
        Vector3(3, 3, 0),
    ]
    assert_equal(polygon_distance(a, crossing), 0.0)
    assert_true(polygon_distance(List[Vector3](), a) > 1e300)


def _setup_follow(
    map: Map, ego_x: Float32, other_x: Float32, ego_speed: Float32
) raises -> TrafficManagerShared:
    var shared = _shared(map)
    _put(shared, 1, ego_x, 1.75, 0, ego_speed)
    _put(shared, 2, other_x, 1.75, 0, 0)
    _vehicles(shared, [1, 2])
    var stage = LocalizationStage()
    _localize(stage, shared)
    _localize(stage, shared)
    return shared^


def test_collision_yields_to_the_vehicle_ahead() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    stage.update(0, shared)
    stage.update(1, shared)
    # The ego's box ends at 52.4 and the other's at 57.6: 5.2 m, less the
    # 2 m gap to keep.
    var hazard = shared.collision_frame[0]
    assert_true(hazard.hazard)
    assert_true(hazard.hazard_actor_id == ActorId(2))
    _near(hazard.available_distance_margin.value, 3.2)
    # The vehicle ahead yields to nothing behind it.
    assert_false(shared.collision_frame[1].hazard)
    # The lock holds the gap.
    assert_true(1 in stage.collision_locks)
    var lock = stage.collision_locks[1]
    assert_almost_equal(lock.distance_to_lead_vehicle, 5.2, atol=1e-4)
    # With the lock: the boundary reaches 5.2 + 4 m.
    _near(stage.get_bounding_box_extension(ActorId(1), shared), 9.2)
    # The same pair again this step reads the cache, swapped: from the
    # other's body (inside the ego's boundary) to the ego's boundary, 0.
    var g = stage.get_geometry_between_actors(ActorId(2), ActorId(1), shared)
    assert_equal(g.reference_vehicle_to_other_geodesic, 0.0)
    assert_almost_equal(g.other_vehicle_to_reference_geodesic, 5.2, atol=1e-4)
    stage.clear_cycle_cache()
    # The next step: the same lead, whose body is inside the ego's
    # boundary, so the lock takes the gap between the boxes.
    stage.update(0, shared)
    assert_almost_equal(
        stage.collision_locks[1].distance_to_lead_vehicle, 5.2, atol=1e-4
    )
    stage.clear_cycle_cache()
    # The other vehicle is put behind the ego: it is negotiated, it is no
    # hazard, and the lock goes.
    _put(shared, 2, 44, 1.75, 0, 0)
    stage.update(0, shared)
    assert_false(shared.collision_frame[0].hazard)
    assert_false(1 in stage.collision_locks)
    stage.remove_actor(ActorId(1))
    stage.reset()
    with assert_raises(contains="out of range"):
        stage.update(5, shared)


def test_collision_ignore_chances() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    shared.parameters.set_percentage_ignore_vehicles(ActorId(1), 100)
    stage.update(0, shared)
    assert_false(shared.collision_frame[0].hazard)
    stage.clear_cycle_cache()
    # A walker ahead instead.
    var walker = _shared(map)
    _put(walker, 1, 50, 1.75, 0, 5)
    _put(walker, 2, 60, 1.75, 0, 0, TRAFFIC_PEDESTRIAN)
    _vehicles(walker, [1])
    var loc = LocalizationStage()
    _localize(loc, walker)
    # The walker's grids, as the life-cycle manager notes them.
    walker.track_traffic.update_unregistered_grid_position(
        ActorId(2), [SimpleWaypointIndex(72)], walker.local_map
    )
    _localize(loc, walker)
    var stage2 = CollisionStage()
    stage2.update(0, walker)
    assert_true(walker.collision_frame[0].hazard)
    stage2.clear_cycle_cache()
    walker.parameters.set_percentage_ignore_walkers(ActorId(1), 100)
    stage2.update(0, walker)
    assert_false(walker.collision_frame[0].hazard)
    stage2.clear_cycle_cache()
    # An actor of no known type is never a hazard.
    var any = _shared(map)
    _put(any, 1, 50, 1.75, 0, 5)
    _put(any, 2, 60, 1.75, 0, 0, TRAFFIC_ANY)
    _vehicles(any, [1])
    var loc3 = LocalizationStage()
    _localize(loc3, any)
    any.track_traffic.update_unregistered_grid_position(
        ActorId(2), [SimpleWaypointIndex(72)], any.local_map
    )
    _localize(loc3, any)
    var stage3 = CollisionStage()
    stage3.update(0, any)
    assert_false(any.collision_frame[0].hazard)
    # Ignoring one vehicle by rule.
    var rule = _setup_follow(map, 50, 60, 5)
    rule.parameters.set_collision_detection(ActorId(1), ActorId(2), False)
    var stage4 = CollisionStage()
    stage4.update(0, rule)
    assert_false(rule.collision_frame[0].hazard)


def test_collision_candidates_by_distance() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    # Two vehicles ahead: the nearer one is the hazard. One high above
    # is not a candidate.
    _put(shared, 1, 50, 1.75, 0, 5)
    _put(shared, 2, 64, 1.75, 0, 0)
    _put(shared, 3, 58, 1.75, 0, 0)
    _vehicles(shared, [1, 2, 3])
    var loc = LocalizationStage()
    _localize(loc, shared)
    _localize(loc, shared)
    var high = shared.simulation_state.get_kinematic_state(ActorId(2))
    var stage = CollisionStage()
    stage.update(0, shared)
    assert_true(shared.collision_frame[0].hazard_actor_id == ActorId(3))
    stage.clear_cycle_cache()
    high.location.z = 10
    shared.simulation_state.update_kinematic_state(ActorId(2), high)
    _put(shared, 3, 150, 1.75, 0, 0)
    stage.update(0, shared)
    assert_false(shared.collision_frame[0].hazard)
    stage.clear_cycle_cache()
    # A large gap to keep widens the search: 2 m (not squared) against
    # the squared radius, as CARLA compares.
    shared.parameters.set_distance_to_leading_vehicle(ActorId(1), Length(900))
    stage.update(0, shared)
    stage.clear_cycle_cache()
    # An untracked vehicle yields to nothing; a tracked one with no path
    # is refused.
    _vehicles(shared, [9])
    stage.update(0, shared)
    assert_false(shared.collision_frame[0].hazard)
    _put(shared, 9, 0, 0, 0, 0)
    with assert_raises(contains="no path"):
        stage.update(0, shared)


def test_collision_in_a_junction_and_at_a_red_light() raises:
    var map = load_opendrive(junction_town())
    # The ego at the junction's entrance, stopped by a red light: no
    # negotiation.
    var shared = _shared(map)
    _put(
        shared, 1, 92, 1.75, 0, 5, TRAFFIC_VEHICLE, TrafficLightInfo(RED, True)
    )
    _put(shared, 2, 100.5, 1.8, 5, 0)
    _vehicles(shared, [1, 2])
    var loc = LocalizationStage()
    _localize(loc, shared)
    _localize(loc, shared)
    var stage = CollisionStage()
    stage.update(0, shared)
    assert_false(shared.collision_frame[0].hazard)
    stage.clear_cycle_cache()
    # Inside the junction, the cross range counts.
    _put(
        shared,
        1,
        100.2,
        1.75,
        0,
        5,
        TRAFFIC_VEHICLE,
        TrafficLightInfo(GREEN, False),
    )
    _put(shared, 2, 104.5, 3.1, 33, 0)
    _localize(loc, shared)
    stage.update(0, shared)
    assert_true(shared.collision_frame[0].hazard)


def test_collision_post_crash_and_side_priority() raises:
    var map = load_opendrive(straight_town())
    # Boxes that touch: the ego yields when the other came from the
    # side it faces.
    var shared = _shared(map)
    _put(shared, 1, 50, 1.75, 0, 5)
    _put(shared, 2, 54, 1.75, 0, 0)
    _vehicles(shared, [1, 2])
    var loc = LocalizationStage()
    _localize(loc, shared)
    _localize(loc, shared)
    var stage = CollisionStage()
    stage.update(0, shared)
    assert_true(shared.collision_frame[0].hazard)
    assert_equal(shared.collision_frame[0].available_distance_margin.value, 0.0)


def _g(
    r2o: Float64, o2r: Float64, geo: Float64, box: Float64
) -> GeometryComparison:
    return GeometryComparison(r2o, o2r, geo, box)


def test_collision_yield_rule() raises:
    # Boundaries apart: never.
    assert_false(collision_yields(_g(1, 0, 0.5, 1), False))
    # The other's body in the ego's path.
    assert_true(collision_yields(_g(1, 0, 0, 1), True))
    # Both paths clear of both bodies: the ego's body is farther from the
    # other's path (3 m against 2 m), so it has the lower priority.
    assert_true(collision_yields(_g(3, 2, 0, 1), True))
    # Equally far: the angle decides.
    assert_true(collision_yields(_g(2, 2, 0, 1), False))
    assert_false(collision_yields(_g(2, 2, 0, 1), True))
    # The ego's body is nearer: it goes.
    assert_false(collision_yields(_g(1, 2, 0, 1), False))
    # The ego's body is in the other's path: the other yields.
    assert_false(collision_yields(_g(0.05, 2, 0, 1), False))
    # After a crash, the angle decides.
    assert_true(collision_yields(_g(0, 0, 0, 0), False))
    assert_false(collision_yields(_g(0, 0, 0, 0), True))


def test_collision_lock_changes_lead() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    stage.update(0, shared)
    stage.clear_cycle_cache()
    # A lock held on another vehicle is replaced.
    stage.collision_locks[1] = CollisionLock(1.0, 1.0, ActorId(7))
    stage.update(0, shared)
    assert_true(stage.collision_locks[1].lead_vehicle_id == ActorId(2))
    stage.clear_cycle_cache()
    # A lock 10 m past its start no longer stretches the boundary.
    stage.collision_locks[1] = CollisionLock(20.0, 1.0, ActorId(2))
    _near(stage.get_bounding_box_extension(ActorId(1), shared), 2.5 + 1.8 * 1.8)
    # The same lead, 15.2 m ahead. The lock stretches the ego's boundary
    # to 15 + 4 m, over the lead's body, so the lock takes the gap between
    # the boxes.
    var far = _setup_follow(map, 50, 70, 5)
    var stage2 = CollisionStage()
    far.parameters.set_distance_to_leading_vehicle(ActorId(1), Length(10))
    stage2.collision_locks[1] = CollisionLock(15.0, 15.0, ActorId(2))
    stage2.update(0, far)
    assert_true(far.collision_frame[0].hazard)
    assert_almost_equal(
        stage2.collision_locks[1].distance_to_lead_vehicle, 15.2, atol=1e-3
    )


# --- edge cases -------------------------------------------------------------------


def _line(
    map: Map, nodes: List[Tuple[Float64, Bool]]
) raises -> TrafficManagerShared:
    """Nodes on the straight town's lane -1 at the given s, in a chain,
    each marked as in a junction or not. The last is a dead end."""
    var local = InMemoryMap()
    var made = List[SimpleWaypointIndex]()
    for node in nodes:
        var w = local.add_waypoint(map, Waypoint_at(1, -1, node[0]))
        local.waypoints[w.value].is_junction = node[1]
        made.append(w)
    for i in range(len(made) - 1):
        _ = local.set_next_waypoints(made[i], [made[i + 1]])
        _ = local.set_previous_waypoints(made[i + 1], [made[i]])
    local.set_up_spatial_tree()
    return TrafficManagerShared(local^, 42)


def _entrance(mut shared: TrafficManagerShared) raises -> LocalizationStage:
    var stage = LocalizationStage()
    _put(shared, 1, 8, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _localize(stage, shared)
    assert_true(shared.localization_frame[0].is_at_junction_entrance)
    return stage^


def test_safe_space_edge_cases() raises:
    var map = load_opendrive(straight_town())
    # A junction 5 m long (s 15 to 20): the safe point, s 25, is found
    # in the path, but the junction is under 8 m, so neither point is
    # kept.
    var short = _line(
        map,
        [
            (10.0, False),
            (15.0, True),
            (20.0, False),
            (25.0, False),
            (30.0, False),
        ],
    )
    _ = _entrance(short)
    assert_false(short.localization_frame[0].junction_end_point.is_some())
    assert_false(short.localization_frame[0].safe_point.is_some())
    # A dead end inside the junction: the walk stops there.
    var inside = _line(map, [(10.0, False), (15.0, True), (20.0, True)])
    _ = _entrance(inside)
    assert_false(inside.localization_frame[0].junction_end_point.is_some())
    _same(_indices(inside, 1), [0, 1, 2])
    assert_equal(len(inside.marked_for_removal), 2)
    # A dead end 2 m past a 10 m junction: its end (s 25) is kept, with
    # no safe point.
    var after = _line(
        map,
        [
            (10.0, False),
            (15.0, True),
            (20.0, True),
            (25.0, False),
            (27.0, False),
        ],
    )
    _ = _entrance(after)
    assert_equal(after.localization_frame[0].junction_end_point.value, 3)
    assert_false(after.localization_frame[0].safe_point.is_some())
    # A junction longer than the path: the walk pushes s 35 (still in the
    # junction) and s 40 (its end), then s 45, 5 m on, the safe point.
    var long = _line(
        map,
        [
            (10.0, False),
            (15.0, True),
            (20.0, True),
            (25.0, True),
            (30.0, True),
            (35.0, True),
            (40.0, False),
            (45.0, False),
            (50.0, False),
        ],
    )
    _ = _entrance(long)
    assert_equal(long.localization_frame[0].junction_end_point.value, 6)
    assert_equal(long.localization_frame[0].safe_point.value, 7)
    _same(_indices(long, 1), _range(0, 7))


def test_facing_away_from_the_path() raises:
    # Heading east from x = 52, the path runs from x = 55. Turned round,
    # every node is behind: all are dropped, and the path starts again at
    # the nearest node, x = 50, on to 20 m past it.
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 52, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _localize(stage, shared)
    assert_equal(_indices(shared, 1)[0], 71)
    _put(shared, 1, 52, 1.75, 180, 0)
    _localize(stage, shared)
    _same(_indices(shared, 1), _range(70, 74))
    with assert_raises(contains="out of range"):
        stage.update(-1, shared)
    # A fresh stage forgets a vehicle it never saw.
    var fresh = LocalizationStage()
    fresh.remove_actor(ActorId(1))
    assert_equal(len(fresh.last_lane_change_swpt), 0)
    # A vehicle second in a list leaves it; the first stays.
    fresh.large_vehicles_at_junction = [5, 1]
    fresh.remove_actor(ActorId(1))
    assert_equal(len(fresh.large_vehicles_at_junction), 1)
    assert_equal(fresh.large_vehicles_at_junction[0], 5)


def test_lane_change_obstacles_far_and_farther() raises:
    # At 20 m/s the ego's path reaches past x = 130. On its lane: vehicle
    # 2 at 60 m, too far to pass (over 50 m); vehicle 3 at 30 m, the
    # obstacle; vehicle 4 at 40 m, farther than 3. The ego changes right,
    # 20 m on from x = 55: lane -2 at x = 75.
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 50, 1.75, 0, 20)
    _put(shared, 2, 110, 1.75, 0, 0)
    _put(shared, 3, 80, 1.75, 0, 0)
    _put(shared, 4, 90, 1.75, 0, 0)
    _vehicles(shared, [1, 2, 3, 4])
    _localize(stage, shared)
    _localize(stage, shared)
    assert_equal(_indices(shared, 1)[0], 15)


def test_large_vehicle_turns_and_starts_inside() raises:
    var map = load_opendrive(junction_town())
    # The turn marked left by hand: the same length, turning left.
    var left = _shared(map)
    for i in range(128, 147):
        left.local_map.waypoints[i].road_option = ROAD_OPTION_LEFT
    var stage = LocalizationStage()
    left.large_vehicles[1] = LargeVehicle(Length(0), True)
    _put(left, 1, 92, 1.75, 0, 0)
    _vehicles(left, [1])
    _localize(stage, left)
    _localize(stage, left)
    assert_false(left.large_vehicles[1].turn_right)
    _near(left.large_vehicles[1].junction_length.value, 17.955367, 1e-3)
    # Marked straight: a curve, but no turn to measure.
    var straight = _shared(map)
    for i in range(128, 147):
        straight.local_map.waypoints[i].road_option = ROAD_OPTION_STRAIGHT
    var stage2 = LocalizationStage()
    straight.large_vehicles[1] = LargeVehicle(Length(0), True)
    _put(straight, 1, 92, 1.75, 0, 0)
    _vehicles(straight, [1])
    _localize(stage2, straight)
    _localize(stage2, straight)
    assert_equal(straight.large_vehicles[1].junction_length.value, 0.0)
    # A bus that starts inside the junction was never at its entrance:
    # nothing is noted.
    var inside = _shared(map)
    var stage3 = LocalizationStage()
    inside.large_vehicles[1] = LargeVehicle(Length(0), False)
    _put(inside, 1, 103.9, 2.9, 30, 0)
    _vehicles(inside, [1])
    _localize(stage3, inside)
    assert_true(
        inside.local_map.at(inside.buffer(ActorId(1))[0]).check_junction()
    )
    assert_equal(len(stage3.large_vehicles_at_junction), 0)
    assert_equal(len(stage3.large_vehicles_at_junction_entrance), 0)
    assert_equal(inside.large_vehicles[1].junction_length.value, 0.0)


def test_route_of_two_options() raises:
    # The right turn is used up at its first node (128), where the path
    # reaches the horizon; lane follow is left for later.
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 80, 1.75, 0, 0)
    _vehicles(shared, [1])
    shared.parameters.set_imported_route(
        ActorId(1), [ROAD_OPTION_RIGHT, ROAD_OPTION_LANE_FOLLOW], True
    )
    _localize(stage, shared)
    var path = _indices(shared, 1)
    assert_equal(path[len(path) - 1], 128)
    var left = shared.parameters.get_imported_route(ActorId(1))
    assert_equal(len(left), 1)
    assert_true(left[0] == ROAD_OPTION_LANE_FOLLOW)


def test_actions_with_a_lane_change_and_a_turn() raises:
    # At (92, 1.75) facing east, the path from x = 95 through the right
    # turn (node 128 at x = 100). A lane change noted by hand.
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = LocalizationStage()
    _put(shared, 1, 92, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _localize(stage, shared)
    # To road 3 at (108.25, 15): 439.6 m^2 away, farther than the turn's
    # 64 m^2, so the turn comes first.
    stage.last_lane_change_swpt[1] = SimpleWaypointIndex(81)
    var action = stage.compute_next_action(ActorId(1), shared)
    assert_true(action.road_option == ROAD_OPTION_RIGHT)
    # To lane 1 at (95, -1.75): 21.25 m^2 away, and to the left of the
    # heading (cross product 3.5), so the lane change comes first.
    var beside = shared.local_map.get_waypoint(Vector3(95, -1.75, 0))
    stage.last_lane_change_swpt[1] = beside
    action = stage.compute_next_action(ActorId(1), shared)
    assert_true(action.road_option == ROAD_OPTION_CHANGE_LANE_LEFT)
    # In the list, it goes before the second move: 12.25 m^2 from the
    # path's first node, nearer than the path's second node, 25 m^2.
    var actions = stage.compute_action_buffer(ActorId(1), shared)
    assert_equal(len(actions), 4)
    assert_true(actions[0].road_option == ROAD_OPTION_LANE_FOLLOW)
    assert_true(actions[1].road_option == ROAD_OPTION_CHANGE_LANE_LEFT)
    assert_true(actions[2].road_option == ROAD_OPTION_RIGHT)
    assert_true(actions[3].road_option == ROAD_OPTION_LANE_FOLLOW)
    # An empty path is refused.
    shared.buffer_map[1] = List[SimpleWaypointIndex]()
    with assert_raises(contains="path is empty"):
        _ = stage.compute_next_action(ActorId(1), shared)
    with assert_raises(contains="path is empty"):
        _ = stage.compute_action_buffer(ActorId(1), shared)


def test_imported_path_through_an_open_fork() raises:
    # A fork at s 10 on lane -1 into two branches that start outside a
    # junction: lane -1 at s 15, then a junction node at s 17, out at s
    # 20 (within 7 m of s 15), then s 25; and lane -2 at s 15, 20 (in a
    # junction) and 25. The first branch ends at s 25 on road 1, the
    # point's road: it is taken, and the path steps from s 20 to the
    # point.
    var map = load_opendrive(straight_town())
    var local = InMemoryMap()
    var f = local.add_waypoint(map, Waypoint_at(1, -1, 10.0))
    var a1 = local.add_waypoint(map, Waypoint_at(1, -1, 15.0))
    var a2 = local.add_waypoint(map, Waypoint_at(1, -1, 17.0))
    var a3 = local.add_waypoint(map, Waypoint_at(1, -1, 20.0))
    var a4 = local.add_waypoint(map, Waypoint_at(1, -1, 25.0))
    var b1 = local.add_waypoint(map, Waypoint_at(1, -2, 15.0))
    var b2 = local.add_waypoint(map, Waypoint_at(1, -2, 20.0))
    var b3 = local.add_waypoint(map, Waypoint_at(1, -2, 25.0))
    local.waypoints[a2.value].is_junction = True
    local.waypoints[b2.value].is_junction = True
    _ = local.set_next_waypoints(f, [a1, b1])
    _ = local.set_next_waypoints(a1, [a2])
    _ = local.set_next_waypoints(a2, [a3])
    _ = local.set_next_waypoints(a3, [a4])
    _ = local.set_next_waypoints(b1, [b2])
    _ = local.set_next_waypoints(b2, [b3])
    local.set_up_spatial_tree()
    var shared = TrafficManagerShared(local^, 42)
    var stage = LocalizationStage()
    _put(shared, 1, 9, 1.75, 0, 0)
    _vehicles(shared, [1])
    shared.parameters.set_custom_path(ActorId(1), [Vector3(25, 1.75, 0)], False)
    _localize(stage, shared)
    _same(
        _indices(shared, 1), [f.value, a1.value, a2.value, a3.value, a4.value]
    )
    assert_equal(len(shared.parameters.get_custom_path(ActorId(1))), 0)


def test_collision_edge_cases() raises:
    var map = load_opendrive(straight_town())
    # Vehicles 2 (8 m ahead) and 3 (14 m ahead): 3 comes after 2 by id
    # and by distance. The nearer, 2, is the hazard.
    var shared = _shared(map)
    _put(shared, 1, 50, 1.75, 0, 5)
    _put(shared, 2, 58, 1.75, 0, 0)
    _put(shared, 3, 64, 1.75, 0, 0)
    _vehicles(shared, [1, 2, 3])
    var loc = LocalizationStage()
    _localize(loc, shared)
    _localize(loc, shared)
    var stage = CollisionStage()
    stage.update(0, shared)
    assert_true(shared.collision_frame[0].hazard_actor_id == ActorId(2))
    # A boundary asked for twice in a step is the same list.
    var first = stage.get_geodesic_boundary(ActorId(1), shared)
    var again = stage.get_geodesic_boundary(ActorId(1), shared)
    assert_equal(len(first), len(again))
    assert_true(first[0] == again[0])
    # Removing the vehicle drops its lock.
    assert_true(1 in stage.collision_locks)
    stage.remove_actor(ActorId(1))
    assert_false(1 in stage.collision_locks)
    stage.clear_cycle_cache()
    # A distance to keep of 2000 m is more than the squared radius,
    # (2.65 5 + 20)^2 = 1105.6: the search reaches 2000 m, and vehicle 2
    # is still the hazard, with no room: 2000 m to keep.
    shared.parameters.set_distance_to_leading_vehicle(ActorId(1), Length(2000))
    stage.update(0, shared)
    assert_true(shared.collision_frame[0].hazard)
    assert_equal(shared.collision_frame[0].available_distance_margin.value, 0.0)
    stage.clear_cycle_cache()
    with assert_raises(contains="out of range"):
        stage.update(-1, shared)
    # A vehicle whose path is on no grid has no candidates.
    var alone = _shared(map)
    _put(alone, 1, 50, 1.75, 0, 5)
    _vehicles(alone, [1])
    alone.buffer_map[1] = [SimpleWaypointIndex(70)]
    var stage2 = CollisionStage()
    stage2.update(0, alone)
    assert_false(alone.collision_frame[0].hazard)
    # Negotiating for a vehicle with no path is refused.
    var bare = _shared(map)
    _put(bare, 1, 50, 1.75, 0, 5)
    _put(bare, 2, 58, 1.75, 0, 0)
    with assert_raises(contains="no path"):
        _ = stage2.negotiate_collision(ActorId(1), ActorId(2), 0, bare)
    # Polygons with no corners on one side are infinitely far apart.
    var square: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        Vector3(2, 2, 0),
    ]
    assert_true(polygon_distance(square, List[Vector3]()) > 1e300)


def test_collision_lock_on_a_clear_path() raises:
    # A cached comparison, with the smaller actor as reference: 3 m from its body to
    # the lead's path, 2 m from the lead's body to its own path, the
    # paths touching and the boxes 1 m apart. Both paths are clear of the
    # other's body; the ego's body is the farther, so it yields. The
    # lock on the same lead takes the 3 m, and the room is 3 - 2 m.
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    stage.collision_locks[1] = CollisionLock(9.0, 9.0, ActorId(2))
    stage.geometry_cache[(1 << 32) | 2] = GeometryComparison(3.0, 2.0, 0.0, 1.0)
    var result = stage.negotiate_collision(ActorId(1), ActorId(2), 0, shared)
    assert_true(result[0])
    _near(result[1], 1.0)
    assert_equal(stage.collision_locks[1].distance_to_lead_vehicle, 3.0)


def test_large_vehicle_with_open_nodes_before_the_turn() raises:
    # The turn's first four nodes (128 to 131) marked as outside the
    # junction. The path from x = 92 takes the turn (seed 42). From 1 m
    # before node 128, the node 5 m on is in the junction: an entrance,
    # with open nodes before the junction starts. The turn is measured
    # from node 131: right, and shorter than the whole 17.955 m.
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    for i in range(128, 132):
        shared.local_map.waypoints[i].is_junction = False
    var stage = LocalizationStage()
    shared.large_vehicles[1] = LargeVehicle(Length(0), False)
    _put(shared, 1, 92, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(stage, shared)
    _put(shared, 1, 99, 1.75, 0, 0)
    _localize(stage, shared)
    assert_true(shared.localization_frame[0].is_at_junction_entrance)
    assert_equal(shared.buffer(ActorId(1))[0].value, 128)
    var large = shared.large_vehicles[1]
    assert_true(large.turn_right)
    assert_true(large.junction_length.value > 0.0)
    assert_true(large.junction_length.value < 17.9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
