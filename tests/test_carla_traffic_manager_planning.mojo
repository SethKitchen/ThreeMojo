# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's traffic manager: the traffic-light, motion and light stages.

The stages run on hand-made states, with no physics. The expected values
are worked by hand from CARLA's C++ and constants, or come from
`tm_model.py`, a Python model outside the repository:

- The follow rule: a target of the other's speed beyond 2 s plus 2 m of
  gap, at least 12 km/h closer in, a full stop within 0.2 m, and a fall
  of at most 8 % of the speed a step.
- The landmark speeds: a linear rise from the sign's speed at the sign
  to the target speed 3.5 s away; for example 15 km/h at a light 15 m
  from a car aiming at 30 km/h gives 6.3095 m/s.
- The curve speed through road 11's turn: the circle through the path
  is 10.35 m, so sqrt(10.35 0.6 9.81) = 7.8057 m/s.
- The wide-turn offset of an 11 m bus: 0.25 (11 - 6) = 1.25 m, shaped by
  the cosine profile at the share of the junction left.
- The PID: a speed error of 1 gives 12 + 0.0025 + 0.4, a full throttle,
  and a heading error of atan2(1, 3) / 180 = 0.10242 a steer capped at
  0.15.
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    NO_ACTOR,
    OFF,
    RED,
    YELLOW,
)
from extensions.carla.map import Map
from extensions.carla.opendrive import load_opendrive
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.road_info import JuncId
from extensions.carla.traffic_manager_localization import LocalizationStage
from extensions.carla.traffic_manager_pid import PIDParameters
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    NO_SIMPLE_WAYPOINT,
    ROAD_OPTION_LANE_FOLLOW,
    ROAD_OPTION_LEFT,
    SimpleWaypointIndex,
)
from extensions.carla.traffic_manager_planning import (
    MotionPlanStage,
    TrafficLightStage,
    VehicleLightStage,
)
from extensions.carla.traffic_manager_shared import (
    APPLY_TRANSFORM,
    APPLY_VEHICLE_CONTROL,
    CollisionHazardData,
    LargeVehicle,
    LocalizationData,
    NO_COMMAND,
    SET_VEHICLE_LIGHT_STATE,
    TrafficCommand,
    TrafficManagerShared,
    apply_vehicle_control,
    no_localization,
)
from extensions.carla.traffic_manager_state import (
    FLOAT_MAX,
    KinematicState,
    StaticAttributes,
    TRAFFIC_VEHICLE,
    TrafficLightInfo,
)
from extensions.carla.transform import CarlaRotation
from extensions.carla.vehicle import (
    LIGHT_BRAKE,
    LIGHT_FOG,
    LIGHT_LEFT_BLINKER,
    LIGHT_LOW_BEAM,
    LIGHT_POSITION,
    LIGHT_RIGHT_BLINKER,
    LIGHTS_NONE,
    VehicleLightState,
)
from extensions.carla.weather import WeatherParameters
from extensions.carla.world_snapshot import Timestamp
from math.vector3 import Vector3
from std.math import isinf
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


def _shared(map: Map, seed: UInt64 = 42) raises -> TrafficManagerShared:
    var local = InMemoryMap()
    local.set_up(map)
    return TrafficManagerShared(local^, seed)


def _put(
    mut shared: TrafficManagerShared,
    id: Int,
    x: Float32,
    y: Float32,
    yaw: Float32,
    speed: Float32,
    light: TrafficLightInfo = TrafficLightInfo(GREEN, False),
    physics: Bool = True,
    dormant: Bool = False,
    half_length: Float32 = 2.4,
    limit_kmh: Float32 = 30,
) raises:
    var rotation = CarlaRotation(
        Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)
    )
    var state = KinematicState(
        Vector3(x, y, 0),
        rotation,
        rotation.forward_vector() * speed,
        Velocity(limit_kmh, KILOMETER_PER_HOUR),
        physics,
        dormant,
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
            StaticAttributes(
                TRAFFIC_VEHICLE, Length(half_length), Length(1.0), Length(0.75)
            ),
            light,
        )


def _vehicles(mut shared: TrafficManagerShared, ids: List[Int]):
    shared.vehicle_id_list = List[ActorId]()
    for id in ids:
        shared.vehicle_id_list.append(ActorId(id))
    shared.reset_frames()


def _localize(mut shared: TrafficManagerShared, times: Int = 2) raises:
    var stage = LocalizationStage()
    for _ in range(times):
        for i in range(len(shared.vehicle_id_list)):
            stage.update(i, shared)


def _at(seconds: Float64) -> Timestamp:
    return Timestamp(Int(seconds * 20), seconds, 0.05, 0)


# --- traffic lights and signs ---------------------------------------------------------


def test_red_and_yellow_lights_stop() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = TrafficLightStage()
    _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(RED, True))
    _vehicles(shared, [1])
    _localize(shared)
    stage.update(0, shared, _at(1))
    assert_true(shared.tl_frame[0])
    for state in [GREEN, OFF]:
        _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(state, False))
        _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(state, True))
        stage.update(0, shared, _at(1))
        assert_false(shared.tl_frame[0])
    _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(YELLOW, False))
    _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(YELLOW, True))
    stage.update(0, shared, _at(1))
    assert_true(shared.tl_frame[0])
    # Always running lights: no stop, and no stop sign either.
    shared.parameters.set_percentage_running_light(ActorId(1), 100)
    stage.update(0, shared, _at(1))
    assert_false(shared.tl_frame[0])
    # A dormant vehicle is never stopped.
    _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(RED, True), True, True)
    shared.parameters.set_percentage_running_light(ActorId(1), 0)
    stage.update(0, shared, _at(1))
    assert_false(shared.tl_frame[0])
    with assert_raises(contains="out of range"):
        stage.update(2, shared, _at(1))


def test_stop_sign_queue() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = TrafficLightStage()
    # Told red with no light, 5 m before junction 100: it queues.
    _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(RED, False))
    _vehicles(shared, [1])
    _localize(shared)
    stage.update(0, shared, _at(1))
    assert_true(shared.tl_frame[0])
    assert_equal(stage.vehicle_last_junction[1], 100)
    # Still moving: it waits for a full stop.
    stage.update(0, shared, _at(1.5))
    assert_true(shared.tl_frame[0])
    assert_false(1 in stage.vehicle_stop_time)
    # Stopped at 2 s; held for 2 s, then free.
    _put(shared, 1, 92, 1.75, 0, 0, TrafficLightInfo(GREEN, False))
    stage.update(0, shared, _at(2))
    assert_true(shared.tl_frame[0])
    stage.update(0, shared, _at(3.5))
    assert_true(shared.tl_frame[0])
    stage.update(0, shared, _at(4.25))
    assert_false(shared.tl_frame[0])
    # A second vehicle queues behind it and waits even when stopped.
    _put(shared, 2, 92, -1.75, 0, 0, TrafficLightInfo(RED, False))
    shared.buffer_map[2] = shared.buffer(ActorId(1))
    _vehicles(shared, [1, 2])
    stage.update(1, shared, _at(4.5))
    stage.update(1, shared, _at(5))
    stage.update(1, shared, _at(9))
    assert_true(shared.tl_frame[1])
    # A red light while queued takes it out of the queue and stops it.
    _put(shared, 2, 92, -1.75, 0, 0, TrafficLightInfo(RED, True))
    stage.update(1, shared, _at(9.5))
    assert_true(shared.tl_frame[1])
    assert_false(2 in stage.vehicle_last_junction)
    # Always running signs: no queue.
    _put(shared, 3, 92, -1.75, 0, 0, TrafficLightInfo(RED, False))
    shared.buffer_map[3] = shared.buffer(ActorId(1))
    _vehicles(shared, [1, 2, 3])
    shared.parameters.set_percentage_running_sign(ActorId(3), 100)
    stage.update(2, shared, _at(10))
    assert_false(shared.tl_frame[2])
    # Green with no junction ahead: nothing.
    _put(shared, 3, 20, 1.75, 0, 0, TrafficLightInfo(RED, False))
    shared.buffer_map[3] = [SimpleWaypointIndex(4), SimpleWaypointIndex(5)]
    shared.parameters.set_percentage_running_sign(ActorId(3), 0)
    stage.update(2, shared, _at(10))
    assert_false(shared.tl_frame[2])
    _put(shared, 3, 92, 1.75, 0, 0, TrafficLightInfo(GREEN, False))
    shared.buffer_map[3] = shared.buffer(ActorId(1))
    stage.update(2, shared, _at(10))
    assert_false(shared.tl_frame[2])
    # The first vehicle leaves the junction: out of the queue.
    shared.buffer_map[1] = [SimpleWaypointIndex(81), SimpleWaypointIndex(82)]
    stage.update(0, shared, _at(11))
    assert_false(shared.tl_frame[0])
    assert_false(1 in stage.vehicle_last_junction)
    stage.remove_actor(ActorId(1))
    stage.reset()
    assert_equal(len(stage.entering_vehicles_map), 0)


def test_affected_junction() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = TrafficLightStage()
    _put(shared, 1, 0, 0, 0, 0)
    # Nodes: 19 is road 1's last, 128 the turn's first, 146 its last, 80
    # road 3's first.
    var before: List[SimpleWaypointIndex] = [
        SimpleWaypointIndex(19),
        SimpleWaypointIndex(128),
    ]
    var inside: List[SimpleWaypointIndex] = [
        SimpleWaypointIndex(146),
        SimpleWaypointIndex(80),
        SimpleWaypointIndex(81),
    ]
    var after: List[SimpleWaypointIndex] = [
        SimpleWaypointIndex(80),
        SimpleWaypointIndex(81),
    ]
    shared.buffer_map[1] = before.copy()
    assert_equal(stage.get_affected_junction_id(ActorId(1), shared), 100)
    shared.buffer_map[1] = after.copy()
    assert_equal(stage.get_affected_junction_id(ActorId(1), shared), -1)
    # Queued at 100: the node ahead in 100 is kept.
    stage.vehicle_last_junction[1] = 100
    shared.buffer_map[1] = before.copy()
    assert_equal(stage.get_affected_junction_id(ActorId(1), shared), 100)
    # Still in the junction, the node 5 m on out of it.
    shared.buffer_map[1] = inside.copy()
    assert_equal(stage.get_affected_junction_id(ActorId(1), shared), 100)
    # Out of it.
    shared.buffer_map[1] = after.copy()
    assert_equal(stage.get_affected_junction_id(ActorId(1), shared), -1)
    # Queued at another junction: the one ahead.
    stage.vehicle_last_junction[1] = 7
    shared.buffer_map[1] = before.copy()
    assert_equal(stage.get_affected_junction_id(ActorId(1), shared), 100)
    with assert_raises(contains="no path"):
        _ = stage.get_affected_junction_id(ActorId(9), shared)
    with assert_raises(contains="no queue"):
        _ = stage.handle_non_signalised_junction(ActorId(1), 55, _at(0), shared)


def test_requeue_at_another_junction() raises:
    var stage = TrafficLightStage()
    stage.add_actor_to_non_signalised_junction(ActorId(1), 100)
    stage.vehicle_stop_time[1] = 1.0
    stage.add_actor_to_non_signalised_junction(ActorId(1), 100)
    assert_equal(len(stage.entering_vehicles_map[100]), 1)
    stage.add_actor_to_non_signalised_junction(ActorId(1), 200)
    assert_equal(len(stage.entering_vehicles_map[100]), 0)
    assert_equal(stage.vehicle_last_junction[1], 200)
    assert_false(1 in stage.vehicle_stop_time)


# --- motion planning ------------------------------------------------------------------


def _hazard(margin: Float32) -> CollisionHazardData:
    return CollisionHazardData(Length(margin), ActorId(2), True)


def test_collision_handling_follow_rule() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    _put(shared, 2, 0, 0, 0, 5)
    var v = Vector3(10, 0, 0)
    var east = Vector3(1, 0, 0)
    # 30 m of room, more than 2 s 10 m/s + 2 m: the other's 5 m/s, held
    # to a fall of 8 % of 10 m/s.
    var far = stage.collision_handling(_hazard(30), False, v, east, 12, shared)
    assert_false(far[0])
    _near(far[1], 9.2)
    # 10 m: at least 12 km/h, the other's 5 m/s; the same fall.
    var mid = stage.collision_handling(_hazard(10), False, v, east, 12, shared)
    assert_false(mid[0])
    _near(mid[1], 9.2)
    # Within 0.2 m: a full stop.
    assert_true(
        stage.collision_handling(_hazard(0.1), False, v, east, 12, shared)[0]
    )
    # Closing on nothing: no relative speed, but still inside 0.2 m.
    _put(shared, 2, 0, 0, 0, 10)
    var same = stage.collision_handling(
        _hazard(0.1), False, v, east, 12, shared
    )
    assert_true(same[0])
    var clear = stage.collision_handling(_hazard(5), False, v, east, 12, shared)
    assert_false(clear[0])
    _near(clear[1], 12)
    # A light already stops the vehicle: the hazard is ignored.
    var light = stage.collision_handling(
        _hazard(0.1), True, v, east, 12, shared
    )
    assert_false(light[0])
    _near(light[1], 12)
    # A target below the fall's floor stays the target.
    var low = stage.collision_handling(
        CollisionHazardData(Length(0), NO_ACTOR, False),
        False,
        v,
        east,
        5,
        shared,
    )
    _near(low[1], 5)
    # Slow and close: 12 km/h, and no fall to cap it.
    _put(shared, 2, 0, 0, 0, 0)
    var slow = stage.collision_handling(
        _hazard(1), False, Vector3(1, 0, 0), east, 12, shared
    )
    _near(slow[1], 3.3333333)


def test_turn_and_landmark_speeds() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    # A straight path has no finite circle: no limit.
    var straight: List[SimpleWaypointIndex] = [
        SimpleWaypointIndex(60),
        SimpleWaypointIndex(61),
        SimpleWaypointIndex(62),
    ]
    var straight_speed = stage.get_turn_target_velocity(straight, 8, shared)
    assert_false(isinf(straight_speed))
    assert_true(straight_speed > 1e19)
    assert_equal(min(Float32(8), straight_speed), 8.0)
    assert_equal(
        stage.get_turn_target_velocity(
            [SimpleWaypointIndex(60), SimpleWaypointIndex(61)], 8, shared
        ),
        8.0,
    )
    # The 60 km/h sign 10 m ahead of a car aiming at 25 m/s: 17.619.
    _put(shared, 1, 140, 1.75, 0, 0)
    _near(
        stage.get_landmark_target_velocity(
            SimpleWaypointIndex(88),
            Vector3(140, 1.75, 0),
            ActorId(1),
            25,
            shared,
            map,
        ),
        17.619048,
    )
    # Aiming at 10 m/s, under the sign's speed: no change.
    _near(
        stage.get_landmark_target_velocity(
            SimpleWaypointIndex(88),
            Vector3(140, 1.75, 0),
            ActorId(1),
            10,
            shared,
            map,
        ),
        10.0,
    )
    # With a desired speed, CARLA compares 36 (km/h) with 10 (m/s).
    shared.parameters.set_desired_speed(ActorId(1), Velocity(10.0))
    _near(
        stage.get_landmark_target_velocity(
            SimpleWaypointIndex(88),
            Vector3(140, 1.75, 0),
            ActorId(1),
            10,
            shared,
            map,
        ),
        10.0,
    )
    # No landmark ahead of lane -2.
    assert_equal(
        stage.get_landmark_target_velocity(
            SimpleWaypointIndex(28),
            Vector3(140, 5.25, 0),
            ActorId(1),
            10,
            shared,
            map,
        ),
        FLOAT_MAX,
    )
    # The node is near the sign, the vehicle far behind it: out of reach.
    assert_equal(
        stage.get_landmark_target_velocity(
            SimpleWaypointIndex(88),
            Vector3(100, 1.75, 0),
            ActorId(1),
            3,
            shared,
            map,
        ),
        FLOAT_MAX,
    )


def test_light_stop_and_other_sign_speeds() raises:
    var v = Float32(30) / Float32(3.6)
    var kinds = ["1000001", "206", "205", "101"]
    var speeds: List[Float32] = [6.3095238, 5.6349206, 5.6349206, FLOAT_MAX]
    for k in range(4):
        var map = load_opendrive(
            junction_town().replace('type="1000001"', 'type="' + kinds[k] + '"')
        )
        var shared = _shared(map)
        var stage = MotionPlanStage()
        _put(shared, 1, 80, 1.75, 0, 0)
        # From road 1's node at x = 80, the light 15 m on.
        _near(
            stage.get_landmark_target_velocity(
                SimpleWaypointIndex(16),
                Vector3(80, 1.75, 0),
                ActorId(1),
                v,
                shared,
                map,
            ),
            speeds[k],
            1e-3,
        )


def test_safe_after_junction() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    var end = SimpleWaypointIndex(80)
    var safe = SimpleWaypointIndex(81)
    var entrance = LocalizationData(end, safe, True)
    assert_true(stage.safe_after_junction(entrance, False, False, shared))
    # A stopped vehicle in the space after the junction, passing the safe
    # point but not the junction's end.
    _put(shared, 2, 108.25, 12.5, 90, 0)
    shared.track_traffic.update_passing_vehicle(
        shared.local_map.at(safe).id, ActorId(2)
    )
    assert_false(stage.safe_after_junction(entrance, False, False, shared))
    # It moves: fine.
    _put(shared, 2, 108.25, 12.5, 90, 3)
    assert_true(stage.safe_after_junction(entrance, False, False, shared))
    # Far from the space's middle: fine.
    _put(shared, 2, 108.25, 40, 90, 0)
    assert_true(stage.safe_after_junction(entrance, False, False, shared))
    # Passing the junction's end too: it is not counted.
    _put(shared, 2, 108.25, 12.5, 90, 0)
    shared.track_traffic.update_passing_vehicle(
        shared.local_map.at(end).id, ActorId(2)
    )
    assert_true(stage.safe_after_junction(entrance, False, False, shared))
    # The other reasons not to look.
    assert_true(stage.safe_after_junction(entrance, True, False, shared))
    assert_true(stage.safe_after_junction(entrance, False, True, shared))
    assert_true(
        stage.safe_after_junction(no_localization(), False, False, shared)
    )
    assert_true(
        stage.safe_after_junction(
            LocalizationData(NO_SIMPLE_WAYPOINT, safe, True),
            False,
            False,
            shared,
        )
    )
    assert_true(
        stage.safe_after_junction(
            LocalizationData(end, NO_SIMPLE_WAYPOINT, True),
            False,
            False,
            shared,
        )
    )
    # A space shorter than 2 m.
    assert_true(
        stage.safe_after_junction(
            LocalizationData(end, end, True), False, False, shared
        )
    )


def test_wide_turn_offset() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    # The path of the turn: road 1's last node, the turn's 19, road 3's two.
    var path = List[SimpleWaypointIndex]()
    path.append(SimpleWaypointIndex(19))
    for i in range(128, 147):
        path.append(SimpleWaypointIndex(i))
    path.append(SimpleWaypointIndex(80))
    path.append(SimpleWaypointIndex(81))
    # An 11 m bus: offset 1.25 m.
    _put(shared, 1, 100, 1.75, 0, 3, half_length=5.5)
    var bus = ActorId(1)
    # Not large yet.
    assert_equal(stage.calculate_base_offset(bus, path, True, 1, shared), 0.0)
    shared.large_vehicles[1] = LargeVehicle(Length(17.955367), True)
    assert_equal(stage.calculate_base_offset(bus, path, False, 1, shared), 0.0)
    # 72 % of the junction left: -1.2342, a swing out to the left.
    _near(
        stage.calculate_base_offset(bus, path, True, 1, shared),
        -1.2341793,
        1e-3,
    )
    _near(
        stage.calculate_base_offset(bus, path, True, 10, shared),
        0.2570375,
        1e-3,
    )
    shared.large_vehicles[1] = LargeVehicle(Length(17.955367), False)
    _near(
        stage.calculate_base_offset(bus, path, True, 16, shared),
        -0.1519261,
        1e-3,
    )
    shared.large_vehicles[1] = LargeVehicle(Length(0), False)
    assert_equal(stage.calculate_base_offset(bus, path, True, 1, shared), 0.0)
    shared.large_vehicles[1] = LargeVehicle(Length(17.955367), True)
    shared.parameters.set_large_vehicle_wide_turn(bus, False)
    assert_equal(stage.calculate_base_offset(bus, path, True, 1, shared), 0.0)


def test_wide_turn_side() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    _put(shared, 1, 50, 1.75, 0, 3)
    var right = Vector3(0, 1, 0)
    assert_false(
        stage.is_wide_turn_side_occupied(ActorId(1), right, Length(1), shared)
    )
    _put(shared, 2, 50, 4.5, 0, 0)
    _vehicles(shared, [1, 2])
    _localize(shared)
    # Vehicle 2's path shares no grid with 1's: they are on other lanes.
    shared.track_traffic.update_unregistered_grid_position(
        ActorId(2), [SimpleWaypointIndex(70)], shared.local_map
    )
    assert_true(
        stage.is_wide_turn_side_occupied(ActorId(1), right, Length(1), shared)
    )
    assert_false(
        stage.is_wide_turn_side_occupied(
            ActorId(1), right * -1.0, Length(1), shared
        )
    )


def test_motion_plan_drives_with_the_pid() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    _put(shared, 1, 20, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(shared)
    stage.update(0, shared, map, _at(1))
    var command = shared.control_frame[0]
    assert_true(command.kind == APPLY_VEHICLE_CONTROL)
    # A speed error of 1: 12.4025, held at 0.85.
    _near(command.control.throttle, 0.85)
    assert_equal(command.control.brake, 0.0)
    _near(command.control.steer, 0.0)
    # One meter right: the target at (23, 2.75), atan2(1, 3) / 180; the
    # steer rises by at most 0.15.
    shared.parameters.set_lane_offset(ActorId(1), Length(1))
    stage.remove_actor(ActorId(1))
    stage.update(0, shared, map, _at(1.05))
    _near(shared.control_frame[0].control.steer, 0.15)
    # A red light: a full brake.
    shared.tl_frame[0] = True
    stage.update(0, shared, map, _at(1.1))
    assert_equal(shared.control_frame[0].control.throttle, 0.0)
    assert_equal(shared.control_frame[0].control.brake, 1.0)
    stage.reset()
    with assert_raises(contains="out of range"):
        stage.update(4, shared, map, _at(1))
    _vehicles(shared, [5])
    _put(shared, 5, 0, 0, 0, 0)
    with assert_raises(contains="no path"):
        stage.update(0, shared, map, _at(1))


def test_motion_plan_highway_and_heading_wrap() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    # 20 m/s at 90 km/h: the highway gains; the speed error 0.2 gives
    # 20 0.2 + 0.05 0.2 0.05 + 0.01 0.2 20 = 4.0405, held at 0.85.
    _put(shared, 1, 60, 1.75, 0, 20, limit_kmh=90)
    _vehicles(shared, [1])
    _localize(shared)
    stage.update(0, shared, map, _at(1))
    _near(shared.control_frame[0].control.throttle, 0.85)
    # Lane 1 runs west. Facing -170 degrees with the lane's center 0.25 m
    # to the plus-y side, the target is at 175.2 degrees: 345.2 degrees
    # up, which wraps to 14.8 degrees down, a turn to the left.
    var west = _shared(map)
    _put(west, 1, 200, -2.0, -170, 0)
    _vehicles(west, [1])
    _localize(west)
    stage.update(0, west, map, _at(1))
    assert_true(west.control_frame[0].control.steer < 0.0)
    var west2 = _shared(map)
    _put(west2, 1, 200, -1.5, 170, 0)
    _vehicles(west2, [1])
    _localize(west2)
    # A fresh controller: the last one still holds the steer of -0.15.
    var fresh = MotionPlanStage()
    fresh.update(0, west2, map, _at(1))
    assert_true(west2.control_frame[0].control.steer > 0.0)


def test_hybrid_teleport() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    # No physics: moved by 8.333 m/s times 0.05 s toward the first node.
    _put(shared, 1, 20, 1.75, 0, 0, physics=False)
    _vehicles(shared, [1])
    _localize(shared)
    shared.parameters.set_synchronous_mode(True)
    stage.update(0, shared, map, _at(1))
    var command = shared.control_frame[0]
    assert_true(command.kind == APPLY_TRANSFORM)
    _near(command.transform.location.x, 20.416666)
    _near(command.transform.location.y, 1.75)
    _near(
        shared.simulation_state.get_hybrid_end_location(ActorId(1)).x, 20.416666
    )
    # Within one step of the first node: along the node's heading.
    _put(shared, 1, 24.8, 1.75, 0, 0, physics=False)
    stage.update(0, shared, map, _at(1.05))
    _near(shared.control_frame[0].transform.location.x, 25.216666)
    # A stop: it stays.
    shared.tl_frame[0] = True
    stage.update(0, shared, map, _at(1.1))
    _near(shared.control_frame[0].transform.location.x, 24.8)
    shared.tl_frame[0] = False
    # Asynchronous: only once 0.05 s have passed since its first move.
    shared.parameters.set_synchronous_mode(False)
    stage.update(0, shared, map, _at(1.02))
    _near(shared.control_frame[0].transform.location.x, 24.8)
    stage.update(0, shared, map, _at(1.2))
    _near(shared.control_frame[0].transform.location.x, 25.216666)
    # A dormant vehicle with no respawn is treated as one without physics.
    _put(shared, 1, 20, 1.75, 0, 0, dormant=True)
    shared.parameters.set_synchronous_mode(True)
    stage.update(0, shared, map, _at(1.3))
    _near(shared.control_frame[0].transform.location.x, 20.416666)


def test_dormant_respawn() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    _put(shared, 1, 20, 1.75, 0, 0, dormant=True)
    _put(shared, 2, 21, 1.75, 0, 0, dormant=True)
    _vehicles(shared, [1, 2])
    _localize(shared)
    shared.parameters.set_respawn_dormant_vehicles(True)
    shared.parameters.set_synchronous_mode(True)
    shared.parameters.set_max_boundaries(Length(0), Length(2000))
    shared.parameters.set_boundaries_respawn_dormant_vehicles(
        Length(10), Length(10)
    )
    # No hero: no respawn; the vehicle is moved as one without physics.
    stage.update(0, shared, map, _at(1))
    assert_true(shared.control_frame[0].kind == APPLY_TRANSFORM)
    _near(shared.control_frame[0].transform.location.x, 20.416666)
    # A hero at x = 150: the ring from 10 m to 35 m around it. The first
    # node is lane -2 at x = 120, grid 4, free; then x = 125, grid 5.
    shared.track_traffic.set_hero_location(Vector3(150, 1.75, 0))
    stage.update(0, shared, map, _at(1))
    var first = shared.control_frame[0].transform.location
    _near(first.x, 120)
    _near(first.y, 5.25)
    _near(first.z, 0.5)
    _near(shared.simulation_state.get_location(ActorId(1)).x, 120)
    stage.update(1, shared, map, _at(1))
    _near(shared.control_frame[1].transform.location.x, 125)
    # Asynchronous, too soon: it stays where it was put.
    shared.parameters.set_synchronous_mode(False)
    stage.update(1, shared, map, _at(1.01))
    _near(shared.control_frame[1].transform.location.x, 125)
    # Once the asynchronous interval elapses, a new sample is drawn.
    # The candidate grids are already held, so its location stays put.
    var expected_draws = shared.random_device.copy()
    _ = expected_draws.next()
    stage.update(1, shared, map, _at(1.1))
    _near(shared.control_frame[1].transform.location.x, 125)
    assert_equal(shared.random_device.next(), expected_draws.next())
    # Every ring node's grid taken: it stays.
    shared.parameters.set_synchronous_mode(True)
    for g in range(0, 40):
        shared.track_traffic.add_taken_grid(JuncId(g), ActorId(7))
    stage.update(1, shared, map, _at(2))
    _near(shared.control_frame[1].transform.location.x, 125)
    # A ring with no nodes at all.
    shared.track_traffic.set_hero_location(Vector3(1000, 1000, 0))
    stage.update(1, shared, map, _at(3))
    _near(shared.control_frame[1].transform.location.x, 125)


# --- vehicle lights -------------------------------------------------------------------


def _lights(shared: TrafficManagerShared) -> Int:
    var n = len(shared.control_frame)
    if n == len(shared.vehicle_id_list):
        return -1
    return shared.control_frame[n - 1].light_state.value


def test_vehicle_lights() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = VehicleLightStage()
    _put(shared, 1, 92, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(shared)
    # Not switched by the traffic manager: nothing.
    stage.update_world_info([(ActorId(1), LIGHTS_NONE)], WeatherParameters())
    stage.update(0, shared)
    assert_equal(_lights(shared), -1)
    shared.parameters.set_update_vehicle_lights(ActorId(1), True)
    # Night (the sun at 0 degrees), and the right turn ahead.
    stage.update(0, shared)
    assert_equal(
        _lights(shared),
        (LIGHT_POSITION | LIGHT_LOW_BEAM | LIGHT_RIGHT_BLINKER).value,
    )
    # Already on: no command.
    shared.reset_frames()
    stage.update_world_info(
        [
            (ActorId(9), LIGHTS_NONE),
            (ActorId(1), LIGHT_POSITION | LIGHT_LOW_BEAM | LIGHT_RIGHT_BLINKER),
        ],
        WeatherParameters(),
    )
    stage.update(0, shared)
    assert_equal(_lights(shared), -1)
    # Day, fog, a hard brake and an unknown vehicle's lights (all on).
    shared.reset_frames()
    var control = VehicleControl()
    control.brake = 1.0
    shared.control_frame[0] = apply_vehicle_control(ActorId(1), control)
    shared.control_frame.insert(0, apply_vehicle_control(ActorId(9), control))
    var fog = WeatherParameters()
    fog.sun_altitude_angle = Angle(90, DEGREE)
    fog.fog_density = 30
    stage.update_world_info(List[Tuple[ActorId, VehicleLightState]](), fog)
    stage.update(0, shared)
    var lit = _lights(shared)
    assert_true(
        VehicleLightState(lit).has(LIGHT_BRAKE | LIGHT_FOG | LIGHT_POSITION)
    )
    assert_false(VehicleLightState(lit).has(VehicleLightState(1 << 2)))
    # Heavy rain; dawn and dusk.
    for sun_rain in [
        (Float32(90), Float32(90)),
        (Float32(25), Float32(0)),
        (Float32(150), Float32(0)),
        (Float32(170), Float32(0)),
    ]:
        shared.reset_frames()
        var w = WeatherParameters()
        w.sun_altitude_angle = Angle(sun_rain[0], DEGREE)
        w.precipitation = sun_rain[1]
        stage.update_world_info([(ActorId(1), LIGHTS_NONE)], w)
        stage.update(0, shared)
        assert_true(VehicleLightState(_lights(shared)).has(LIGHT_POSITION))
    # No weather: nothing but the blinker.
    shared.reset_frames()
    stage.update_world_info(
        [(ActorId(1), LIGHTS_NONE)], WeatherParameters(), False
    )
    stage.update(0, shared)
    assert_equal(_lights(shared), LIGHT_RIGHT_BLINKER.value)
    # A day with no turn: a left turn marked by hand; a long straight path.
    shared.reset_frames()
    var day = WeatherParameters()
    day.sun_altitude_angle = Angle(90, DEGREE)
    stage.update_world_info([(ActorId(1), LIGHTS_NONE)], day)
    shared.local_map.waypoints[128].road_option = ROAD_OPTION_LEFT
    stage.update(0, shared)
    assert_equal(_lights(shared), LIGHT_LEFT_BLINKER.value)
    shared.reset_frames()
    shared.local_map.waypoints[128].road_option = ROAD_OPTION_LANE_FOLLOW
    stage.update(0, shared)
    assert_equal(_lights(shared), -1)
    shared.reset_frames()
    shared.buffer_map[1] = [
        SimpleWaypointIndex(0),
        SimpleWaypointIndex(3),
        SimpleWaypointIndex(4),
    ]
    stage.update(0, shared)
    assert_equal(_lights(shared), -1)
    with assert_raises(contains="out of range"):
        stage.update(3, shared)
    _vehicles(shared, [4])
    shared.parameters.set_update_vehicle_lights(ActorId(4), True)
    with assert_raises(contains="no path"):
        stage.update(0, shared)


# --- edge cases -------------------------------------------------------------------


def test_negative_indices_are_refused() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    _put(shared, 1, 20, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(shared)
    var lights = TrafficLightStage()
    var motion = MotionPlanStage()
    var lamps = VehicleLightStage()
    with assert_raises(contains="out of range"):
        lights.update(-1, shared, _at(1))
    with assert_raises(contains="out of range"):
        motion.update(-1, shared, map, _at(1))
    with assert_raises(contains="out of range"):
        lamps.update(-1, shared)


def test_queue_edge_cases() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = TrafficLightStage()
    # Queued at junction 7, now 5 m before junction 100: it leaves the
    # queue at 7, and is not stopped this step.
    _put(shared, 1, 92, 1.75, 0, 3, TrafficLightInfo(GREEN, False))
    _vehicles(shared, [1])
    _localize(shared)
    stage.add_actor_to_non_signalised_junction(ActorId(1), 7)
    stage.update(0, shared, _at(1))
    assert_false(shared.tl_frame[0])
    assert_false(1 in stage.vehicle_last_junction)
    assert_equal(len(stage.entering_vehicles_map[7]), 0)
    # Taken out of a queue before it ever stopped.
    stage.add_actor_to_non_signalised_junction(ActorId(2), 100)
    stage.remove_actor(ActorId(2))
    assert_false(2 in stage.vehicle_last_junction)
    assert_equal(len(stage.entering_vehicles_map[100]), 0)


def _bus_on(
    mut shared: TrafficManagerShared, node: Int
) raises -> List[SimpleWaypointIndex]:
    """Put an 11 m bus on a node of the right turn (128 to 146), facing
    along it, with its path from there to road 3."""
    ref w = shared.local_map.at(SimpleWaypointIndex(node))
    var at = w.location()
    _put(shared, 1, at.x, at.y, w.transform.rotation.yaw, 3, half_length=5.5)
    var path = List[SimpleWaypointIndex]()
    for i in range(node, 147):
        path.append(SimpleWaypointIndex(i))
    path.append(SimpleWaypointIndex(80))
    path.append(SimpleWaypointIndex(81))
    shared.buffer_map[1] = path.copy()
    _vehicles(shared, [1])
    return path^


def _steer(mut shared: TrafficManagerShared, map: Map) raises -> Float32:
    # A weak heading loop, 0.1 per half turn, keeps the steer under the
    # 0.15 a step may move, so it follows the target.
    var stage = MotionPlanStage(urban_lateral=PIDParameters(0.1, 0, 0))
    stage.update(0, shared, map, _at(1))
    return shared.control_frame[0].control.steer


def test_wide_turn_moves_the_target() raises:
    var map = load_opendrive(junction_town())
    # Early in the turn the offset is negative, a swing to the left: the
    # target moves left, and the steer is less. Late in it the offset is
    # positive: more steer.
    for c in [(129, Float32(-1)), (137, Float32(1))]:
        var shared = _shared(map)
        _ = _bus_on(shared, c[0])
        var plain = _steer(shared, map)
        shared.large_vehicles[1] = LargeVehicle(Length(17.955367), True)
        var wide = _steer(shared, map)
        assert_true((wide - plain) * c[1] > 0.0)
        # A vehicle on the swing side, sharing the bus's grid: no offset.
        var side = shared.simulation_state.get_heading(ActorId(1))
        var right = Vector3(-side.y, side.x, 0)
        var bus = shared.simulation_state.get_location(ActorId(1))
        var there = bus + right * (1.5 * c[1])
        _put(shared, 2, there.x, there.y, 0, 0)
        shared.track_traffic.update_unregistered_grid_position(
            ActorId(1), [SimpleWaypointIndex(c[0])], shared.local_map
        )
        shared.track_traffic.update_unregistered_grid_position(
            ActorId(2), [SimpleWaypointIndex(c[0])], shared.local_map
        )
        assert_equal(_steer(shared, map), plain)


def test_motion_plan_forgets_a_vehicle() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var stage = MotionPlanStage()
    _put(shared, 1, 20, 1.75, 0, 0, physics=False)
    _vehicles(shared, [1])
    _localize(shared)
    shared.parameters.set_synchronous_mode(True)
    stage.update(0, shared, map, _at(1))
    assert_true(1 in stage.teleportation_instance)
    assert_false(1 in stage.pid_state_map)
    stage.remove_actor(ActorId(1))
    assert_false(1 in stage.teleportation_instance)


def test_vehicle_lights_edge_cases() raises:
    var map = load_opendrive(junction_town())
    var shared = _shared(map)
    var stage = VehicleLightStage()
    _put(shared, 1, 92, 1.75, 0, 0)
    _vehicles(shared, [1])
    _localize(shared)
    shared.parameters.set_update_vehicle_lights(ActorId(1), True)
    stage.update_world_info([(ActorId(1), LIGHTS_NONE)], WeatherParameters())
    # With no other command this step: no brake light, and the night
    # lights and the blinker for the right turn.
    shared.control_frame = List[TrafficCommand]()
    stage.update(0, shared)
    assert_equal(len(shared.control_frame), 1)
    assert_equal(
        shared.control_frame[0].light_state.value,
        (LIGHT_POSITION | LIGHT_LOW_BEAM | LIGHT_RIGHT_BLINKER).value,
    )
    # An empty path is refused.
    shared.buffer_map[1] = List[SimpleWaypointIndex]()
    with assert_raises(contains="no path"):
        stage.update(0, shared)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
