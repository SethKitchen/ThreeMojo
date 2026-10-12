# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Actor-id input boundaries preserve state when an id cannot fit UInt32.

The independent range oracle is CARLA's unsigned 32-bit ActorId: zero and
4294967295 fit; -1 and 4294967296 do not. Zero keeps its no-actor meaning.
"""

from extensions.carla.actor import ActorId, GREEN, NO_ACTOR
from extensions.carla.opendrive import load_opendrive
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.road_info import JuncId
from extensions.carla.traffic_manager import (
    ActorSet,
    apply_batch,
    is_physics_enabled,
    set_simulate_physics,
)
from extensions.carla.traffic_manager_collision import (
    CollisionStage,
    GeometryComparison,
)
from extensions.carla.traffic_manager_localization import LocalizationStage
from extensions.carla.traffic_manager_map import (
    ROAD_OPTION_LEFT,
    ROAD_OPTION_VOID,
    SimpleWaypointIndex,
    WaypointId,
)
from extensions.carla.traffic_manager_parameters import (
    Parameters,
    ChangeLaneInfo,
)
from extensions.carla.traffic_manager_planning import (
    MotionPlanStage,
    TrafficLightStage,
    VehicleLightStage,
)
from extensions.carla.traffic_manager_shared import (
    CommandKind,
    TrafficCommand,
    CollisionHazardData,
    apply_transform,
    apply_vehicle_control,
    no_command,
    set_vehicle_light_state,
)
from extensions.carla.traffic_manager_state import (
    SimulationState,
    TrackTraffic,
    TrafficLightInfo,
    push_waypoint,
    pop_waypoint,
)
from extensions.carla.vehicle import LIGHTS_NONE
from extensions.carla.weather import WeatherParameters
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from test_carla_traffic_manager import _kinematic, _attributes, straight_town
from test_carla_traffic_manager_planning import _at, _put, _shared, _vehicles
from test_carla_traffic_manager_world import _manager, _spawn, _world
from units.si import Length, Velocity


def test_parameter_read_boundaries() raises:
    var p = Parameters()
    p.set_desired_speed(ActorId(7), Velocity(3))
    p.set_force_lane_change(ActorId(7), True)
    for bad in [ActorId(-1), ActorId(4294967296)]:
        with assert_raises(contains="not valid"):
            _ = p.has_desired_speed(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_lane_offset(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_large_vehicle_wide_turn(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_force_lane_change(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_keep_slow_lane_percentage(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_random_left_lane_change_percentage(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_random_right_lane_change_percentage(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_auto_lane_change(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_distance_to_leading_vehicle(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_percentage_running_sign(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_percentage_running_light(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_percentage_ignore_vehicles(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_percentage_ignore_walkers(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_update_vehicle_lights(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_upload_path(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_custom_path(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_upload_route(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_imported_route(bad)
        with assert_raises(contains="not valid"):
            _ = p.get_collision_detection(bad, ActorId(7))
        with assert_raises(contains="not valid"):
            _ = p.get_collision_detection(ActorId(99), bad)
        with assert_raises(contains="not valid"):
            _ = p.get_collision_detection(bad, bad)
        with assert_raises(contains="not valid"):
            _ = p.get_vehicle_target_velocity(bad, Velocity(10))
        # A pending command cannot be consumed through an invalid id.
        p._force_lane_change[bad.value] = ChangeLaneInfo(True, False)
        with assert_raises(contains="not valid"):
            _ = p.get_force_lane_change(bad)
        assert_true(p._force_lane_change[bad.value].change_lane)
        assert_true(p.has_desired_speed(ActorId(7)))
    assert_true(p.get_force_lane_change(ActorId(7)).direction)
    for actor in [NO_ACTOR, ActorId(4294967295), ActorId(99)]:
        assert_false(p.has_desired_speed(actor))
        assert_equal(
            p.get_vehicle_target_velocity(actor, Velocity(10)).value, 10.0
        )
        assert_equal(p.get_lane_offset(actor).value, 0.0)
        assert_true(p.get_large_vehicle_wide_turn(actor))
        assert_true(p.get_collision_detection(actor, actor))
        assert_false(p.get_force_lane_change(actor).change_lane)
        assert_equal(p.get_keep_slow_lane_percentage(actor), -1.0)
        assert_equal(p.get_random_left_lane_change_percentage(actor), -1.0)
        assert_equal(p.get_random_right_lane_change_percentage(actor), -1.0)
        assert_true(p.get_auto_lane_change(actor))
        assert_equal(p.get_distance_to_leading_vehicle(actor).value, 2.0)
        assert_equal(p.get_percentage_running_sign(actor), 0.0)
        assert_equal(p.get_percentage_running_light(actor), 0.0)
        assert_equal(p.get_percentage_ignore_vehicles(actor), 0.0)
        assert_equal(p.get_percentage_ignore_walkers(actor), 0.0)
        assert_false(p.get_update_vehicle_lights(actor))
        assert_false(p.get_upload_path(actor))
        assert_equal(len(p.get_custom_path(actor)), 0)
        assert_false(p.get_upload_route(actor))
        assert_equal(len(p.get_imported_route(actor)), 0)
        p.set_desired_speed(actor, Velocity(4))
        assert_equal(
            p.get_vehicle_target_velocity(actor, Velocity(10)).value, 4.0
        )


def test_parameter_write_boundaries() raises:
    var p = Parameters()
    p.set_desired_speed(ActorId(7), Velocity(3))
    for bad in [ActorId(-1), ActorId(4294967296)]:
        with assert_raises(contains="not valid"):
            p.remove_actor(bad)
        with assert_raises(contains="not valid"):
            p.set_percentage_speed_difference(bad, 5)
        with assert_raises(contains="not valid"):
            p.set_lane_offset(bad, Length(1))
        with assert_raises(contains="not valid"):
            p.set_desired_speed(bad, Velocity(2))
        with assert_raises(contains="not valid"):
            p.set_large_vehicle_wide_turn(bad, True)
        with assert_raises(contains="not valid"):
            p.set_force_lane_change(bad, True)
        with assert_raises(contains="not valid"):
            p.set_keep_slow_lane_percentage(bad, 2)
        with assert_raises(contains="not valid"):
            p.set_random_left_lane_change_percentage(bad, 2)
        with assert_raises(contains="not valid"):
            p.set_random_right_lane_change_percentage(bad, 2)
        with assert_raises(contains="not valid"):
            p.set_update_vehicle_lights(bad, True)
        with assert_raises(contains="not valid"):
            p.set_auto_lane_change(bad, True)
        with assert_raises(contains="not valid"):
            p.set_distance_to_leading_vehicle(bad, Length(1))
        with assert_raises(contains="not valid"):
            p.set_percentage_running_light(bad, 2)
        with assert_raises(contains="not valid"):
            p.set_percentage_running_sign(bad, 2)
        with assert_raises(contains="not valid"):
            p.set_percentage_ignore_vehicles(bad, 2)
        with assert_raises(contains="not valid"):
            p.set_percentage_ignore_walkers(bad, 2)
        with assert_raises(contains="not valid"):
            p.set_custom_path(bad, [Vector3(0, 0, 0)], True)
        with assert_raises(contains="not valid"):
            p.remove_upload_path(bad, True)
        with assert_raises(contains="not valid"):
            p.update_upload_path(bad, [Vector3(0, 0, 0)])
        with assert_raises(contains="not valid"):
            p.set_imported_route(bad, [ROAD_OPTION_LEFT], True)
        with assert_raises(contains="not valid"):
            p.remove_imported_route(bad, True)
        with assert_raises(contains="not valid"):
            p.update_imported_route(bad, [ROAD_OPTION_LEFT])
        with assert_raises(contains="not valid"):
            p.set_collision_detection(bad, ActorId(7), True)
        with assert_raises(contains="not valid"):
            p.set_collision_detection(ActorId(7), bad, False)
        assert_equal(len(p.configured_actor_ids()), 1)
        assert_equal(
            p.get_vehicle_target_velocity(ActorId(7), Velocity(10)).value, 3.0
        )


def test_manager_parameter_forwarding_boundaries() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    tm.set_desired_speed(ActorId(7), Velocity(3))
    for bad in [ActorId(-1), ActorId(4294967296)]:
        with assert_raises(contains="not valid"):
            tm.set_percentage_speed_difference(bad, 5)
        with assert_raises(contains="not valid"):
            tm.set_lane_offset(bad, Length(1))
        with assert_raises(contains="not valid"):
            tm.set_desired_speed(bad, Velocity(2))
        with assert_raises(contains="not valid"):
            tm.set_large_vehicle_wide_turn(bad, True)
        with assert_raises(contains="not valid"):
            tm.set_force_lane_change(bad, True)
        with assert_raises(contains="not valid"):
            tm.set_keep_slow_lane_percentage(bad, 2)
        with assert_raises(contains="not valid"):
            tm.set_random_left_lane_change_percentage(bad, 2)
        with assert_raises(contains="not valid"):
            tm.set_random_right_lane_change_percentage(bad, 2)
        with assert_raises(contains="not valid"):
            tm.set_update_vehicle_lights(bad, True)
        with assert_raises(contains="not valid"):
            tm.set_auto_lane_change(bad, True)
        with assert_raises(contains="not valid"):
            tm.set_distance_to_leading_vehicle(bad, Length(1))
        with assert_raises(contains="not valid"):
            tm.set_percentage_running_light(bad, 2)
        with assert_raises(contains="not valid"):
            tm.set_percentage_running_sign(bad, 2)
        with assert_raises(contains="not valid"):
            tm.set_percentage_ignore_vehicles(bad, 2)
        with assert_raises(contains="not valid"):
            tm.set_percentage_ignore_walkers(bad, 2)
        with assert_raises(contains="not valid"):
            tm.set_custom_path(bad, [Vector3(0, 0, 0)], True)
        with assert_raises(contains="not valid"):
            tm.remove_upload_path(bad, True)
        with assert_raises(contains="not valid"):
            tm.update_upload_path(bad, [Vector3(0, 0, 0)])
        with assert_raises(contains="not valid"):
            tm.set_imported_route(bad, [ROAD_OPTION_LEFT], True)
        with assert_raises(contains="not valid"):
            tm.remove_imported_route(bad, True)
        with assert_raises(contains="not valid"):
            tm.update_imported_route(bad, [ROAD_OPTION_LEFT])
        with assert_raises(contains="not valid"):
            tm.set_collision_detection(bad, ActorId(7), True)
        with assert_raises(contains="not valid"):
            tm.set_collision_detection(ActorId(7), bad, False)
        assert_equal(len(tm.parameters().configured_actor_ids()), 1)
        assert_equal(
            tm.parameters()
            .get_vehicle_target_velocity(ActorId(7), Velocity(10))
            .value,
            3.0,
        )


def test_state_and_waypoint_boundaries() raises:
    var map = load_opendrive(straight_town())
    var shared = _shared(map)
    var light = TrafficLightInfo(GREEN, False)
    var buffer = List[SimpleWaypointIndex]()
    var node = SimpleWaypointIndex(0)
    var waypoint = shared.local_map.at(node).id
    for actor in [NO_ACTOR, ActorId(4294967295)]:
        assert_false(shared.simulation_state.contains_actor(actor))
        shared.simulation_state.add_actor(
            actor, _kinematic(1, 2), _attributes(), light
        )
        assert_equal(shared.simulation_state.get_location(actor).x, 1.0)
        push_waypoint(
            actor, shared.track_traffic, buffer, shared.local_map, node
        )
        assert_equal(len(buffer), 1)
        pop_waypoint(actor, shared.track_traffic, buffer, shared.local_map)
        assert_equal(len(buffer), 0)
        shared.simulation_state.remove_actor(actor)
        shared.simulation_state.remove_actor(actor)
        assert_false(shared.simulation_state.contains_actor(actor))
        with assert_raises(contains="does not track"):
            _ = shared.simulation_state.get_location(actor)
        assert_equal(
            len(shared.track_traffic.get_overlapping_vehicles(actor)), 0
        )
        assert_equal(len(shared.buffer(actor)), 0)
    var good = ActorId(7)
    shared.simulation_state.add_actor(
        good, _kinematic(1, 2), _attributes(), light
    )
    push_waypoint(good, shared.track_traffic, buffer, shared.local_map, node)
    for bad in [ActorId(-1), ActorId(4294967296)]:
        with assert_raises(contains="not valid"):
            _ = shared.buffer(bad)
        with assert_raises(contains="not valid"):
            shared.simulation_state.add_actor(
                bad, _kinematic(3, 4), _attributes(), light
            )
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.contains_actor(bad)
        with assert_raises(contains="not valid"):
            shared.simulation_state.remove_actor(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_kinematic_state(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_location(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_hybrid_end_location(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_rotation(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_heading(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_velocity(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_speed_limit(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.is_physics_enabled(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.is_dormant(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_tls(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_type(bad)
        with assert_raises(contains="not valid"):
            _ = shared.simulation_state.get_dimensions(bad)
        with assert_raises(contains="not valid"):
            shared.simulation_state.update_kinematic_state(
                bad, _kinematic(3, 4)
            )
        with assert_raises(contains="not valid"):
            shared.simulation_state.update_kinematic_hybrid_end_location(
                bad, Vector3(3, 4, 5)
            )
        with assert_raises(contains="not valid"):
            shared.simulation_state.update_traffic_light_state(bad, light)
        with assert_raises(contains="not valid"):
            shared.track_traffic.update_passing_vehicle(waypoint, bad)
        with assert_raises(contains="not valid"):
            shared.track_traffic.remove_passing_vehicle(waypoint, bad)
        with assert_raises(contains="not valid"):
            shared.track_traffic.update_grid_position(
                bad, buffer, shared.local_map
            )
        with assert_raises(contains="not valid"):
            shared.track_traffic.update_unregistered_grid_position(
                bad, buffer, shared.local_map
            )
        with assert_raises(contains="not valid"):
            _ = shared.track_traffic.get_overlapping_vehicles(bad)
        with assert_raises(contains="not valid"):
            shared.track_traffic.add_taken_grid(JuncId(1), bad)
        with assert_raises(contains="not valid"):
            shared.track_traffic.delete_actor(bad)
        with assert_raises(contains="not valid"):
            push_waypoint(
                bad, shared.track_traffic, buffer, shared.local_map, node
            )
        with assert_raises(contains="not valid"):
            pop_waypoint(bad, shared.track_traffic, buffer, shared.local_map)
        with assert_raises(contains="not valid"):
            pop_waypoint(
                bad, shared.track_traffic, buffer, shared.local_map, False
            )
        assert_equal(len(buffer), 1)
        assert_equal(buffer[0].value, node.value)
        assert_equal(
            shared.track_traffic.get_passing_vehicles(waypoint)[0].value, 7
        )
        assert_equal(len(shared.simulation_state._actors), 1)
        assert_equal(shared.simulation_state.get_location(good).x, 1.0)


def test_actor_sets_and_manager_bulk_refusal() raises:
    var world = _world(straight_town())
    var car = _spawn(world, 20, 1.75)
    var tm = _manager(world)
    var set = ActorSet()
    set.insert([NO_ACTOR, ActorId(4294967295)])
    assert_true(set.contains(NO_ACTOR))
    assert_true(set.contains(ActorId(4294967295)))
    for bad in [ActorId(-1), ActorId(4294967296)]:
        var generation = tm.registered_vehicles.state
        with assert_raises(contains="not valid"):
            set.insert([ActorId(7), bad])
        assert_equal(set.state, 1)
        assert_equal(set.size(), 2)
        with assert_raises(contains="not valid"):
            set.remove([NO_ACTOR, bad])
        assert_equal(set.state, 1)
        assert_equal(set.size(), 2)
        with assert_raises(contains="not valid"):
            _ = set.contains(bad)
        with assert_raises(contains="not valid"):
            set.destroy(bad, world)
        with assert_raises(contains="not valid"):
            tm.register_vehicles(world, [car, bad])
        assert_equal(tm.registered_vehicles.size(), 0)
        assert_equal(tm.registered_vehicles.state, generation)
        tm.register_vehicles(world, [car])
        with assert_raises(contains="not valid"):
            tm.unregister_vehicles([car, bad])
        assert_true(tm.registered_vehicles.contains(car))
        with assert_raises(contains="not valid"):
            _ = tm.get_next_action(bad)
        with assert_raises(contains="not valid"):
            _ = tm.get_action_buffer(bad)
        with assert_raises(contains="not valid"):
            _ = tm.check_all_frozen(world, [bad])
        with assert_raises(contains="names no actor"):
            _ = is_physics_enabled(world, bad)
        with assert_raises(contains="names no actor"):
            set_simulate_physics(world, bad, False)
        with assert_raises(contains="names no actor"):
            tm.alsm.add_actor(world, bad, tm.shared)
        tm.unregister_vehicles([car])
    with assert_raises(contains="names no actor"):
        tm.register_vehicles(world, [car, ActorId(4294967295)])
    assert_equal(tm.registered_vehicles.size(), 0)
    assert_equal(tm.registered_vehicles.state, 4)
    for actor in [NO_ACTOR, ActorId(4294967295)]:
        assert_true(tm.get_next_action(actor).road_option == ROAD_OPTION_VOID)
        assert_equal(len(tm.get_action_buffer(actor)), 0)
        tm.unregister_vehicles([actor])
        assert_false(tm.alsm.is_vehicle_stuck(actor, tm.shared))
    set.remove([NO_ACTOR, ActorId(4294967295)])
    assert_equal(set.size(), 0)


def test_stage_boundaries_and_cache_bypass() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    _put(tm.shared, 0, 0, 0, 0, 0)
    var now = _at(0)
    var node = SimpleWaypointIndex(0)
    for bad in [ActorId(-1), ActorId(4294967296)]:
        tm.collision_stage.clear_cycle_cache()
        tm.collision_stage.geodesic_boundary_map[bad.value] = [Vector3(0, 0, 0)]
        var pair_key = (min(bad.value, 0) << 32) | max(bad.value, 0)
        tm.collision_stage.geometry_cache[pair_key] = GeometryComparison(
            1, 2, 3, 4
        )
        with assert_raises(contains="not valid"):
            _ = tm.collision_stage.get_bounding_box_extension_meters(
                bad, tm.shared
            )
        with assert_raises(contains="not valid"):
            _ = tm.collision_stage.get_boundary(bad, tm.shared)
        with assert_raises(contains="not valid"):
            _ = tm.collision_stage.get_geodesic_boundary(bad, tm.shared)
        with assert_raises(contains="not valid"):
            _ = tm.collision_stage.get_geometry_between_actors(
                bad, NO_ACTOR, tm.shared
            )
        with assert_raises(contains="not valid"):
            _ = tm.collision_stage.get_geometry_between_actors(
                NO_ACTOR, bad, tm.shared
            )
        with assert_raises(contains="not valid"):
            _ = tm.collision_stage.negotiate_collision_meters(
                bad, NO_ACTOR, 0, tm.shared
            )
        with assert_raises(contains="not valid"):
            _ = tm.collision_stage.negotiate_collision_meters(
                NO_ACTOR, bad, 0, tm.shared
            )
        with assert_raises(contains="not valid"):
            tm.collision_stage.remove_actor(bad)
        assert_equal(len(tm.collision_stage.geometry_cache), 1)
        assert_true(bad.value in tm.collision_stage.geodesic_boundary_map)
        with assert_raises(contains="not valid"):
            tm.localization_stage.remove_actor(bad)
        with assert_raises(contains="not valid"):
            _ = tm.localization_stage.compute_next_action(bad, tm.shared)
        with assert_raises(contains="not valid"):
            _ = tm.localization_stage.compute_action_buffer(bad, tm.shared)
        with assert_raises(contains="not valid"):
            tm.traffic_light_stage.add_actor_to_non_signalised_junction(bad, 5)
        with assert_raises(contains="not valid"):
            _ = tm.traffic_light_stage.handle_non_signalised_junction(
                bad, 5, now, tm.shared
            )
        with assert_raises(contains="not valid"):
            _ = tm.traffic_light_stage.get_affected_junction_id(bad, tm.shared)
        with assert_raises(contains="not valid"):
            tm.traffic_light_stage.remove_actor(bad)
        assert_equal(len(tm.traffic_light_stage.entering_vehicles_map), 0)
        with assert_raises(contains="not valid"):
            _ = tm.motion_plan_stage.calculate_base_offset_meters(
                bad, [node], False, 0, tm.shared
            )
        with assert_raises(contains="not valid"):
            _ = tm.motion_plan_stage.is_wide_turn_side_occupied(
                bad, Vector3(1, 0, 0), Length(1), tm.shared
            )
        with assert_raises(contains="not valid"):
            _ = tm.motion_plan_stage.get_landmark_target_velocity_meters_per_second(
                node, Vector3(0, 0, 0), bad, 0, tm.shared, world.map
            )
        with assert_raises(contains="not valid"):
            tm.motion_plan_stage.remove_actor(bad)
        for hazard in [False, True]:
            with assert_raises(contains="not valid"):
                _ = tm.motion_plan_stage.collision_handling_meters_per_second(
                    CollisionHazardData(Length(0), bad, hazard),
                    True,
                    Vector3(0, 0, 0),
                    Vector3(1, 0, 0),
                    10,
                    tm.shared,
                )
        with assert_raises(contains="not valid"):
            _ = tm.alsm.is_vehicle_stuck(bad, tm.shared)
        tm.alsm.has_physics_enabled[bad.value] = True
        with assert_raises(contains="not valid"):
            tm.alsm.remove_actor(
                bad,
                True,
                tm.registered_vehicles,
                tm.shared,
                tm.localization_stage,
                tm.collision_stage,
                tm.traffic_light_stage,
                tm.motion_plan_stage,
            )
        assert_true(tm.alsm.has_physics_enabled[bad.value])
        tm.shared.marked_for_removal = [NO_ACTOR, bad]
        with assert_raises(contains="not valid"):
            tm.alsm.update(
                world,
                tm.registered_vehicles,
                tm.shared,
                tm.localization_stage,
                tm.collision_stage,
                tm.traffic_light_stage,
                tm.motion_plan_stage,
            )
        assert_equal(len(tm.shared.marked_for_removal), 2)
        tm.shared.marked_for_removal = List[ActorId]()
        tm.shared.vehicle_id_list = [bad]
        tm.shared.reset_frames()
        with assert_raises(contains="not valid"):
            tm.localization_stage.update(0, tm.shared)
        with assert_raises(contains="not valid"):
            tm.collision_stage.update(0, tm.shared)
        with assert_raises(contains="not valid"):
            tm.traffic_light_stage.update(0, tm.shared, now)
        with assert_raises(contains="not valid"):
            tm.motion_plan_stage.update(0, tm.shared, world.map, now)
        with assert_raises(contains="not valid"):
            tm.vehicle_light_stage.update(0, tm.shared)
    for actor in [NO_ACTOR, ActorId(4294967295)]:
        tm.localization_stage.remove_actor(actor)
        tm.collision_stage.remove_actor(actor)
        tm.traffic_light_stage.add_actor_to_non_signalised_junction(actor, 5)
        tm.traffic_light_stage.remove_actor(actor)
        tm.motion_plan_stage.remove_actor(actor)
        assert_equal(
            tm.motion_plan_stage.calculate_base_offset_meters(
                actor, [node], False, 0, tm.shared
            ),
            0.0,
        )
        assert_false(
            tm.motion_plan_stage.is_wide_turn_side_occupied(
                actor, Vector3(1, 0, 0), Length(1), tm.shared
            )
        )


def test_motion_frame_refusal_precedes_respawn() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    _put(tm.shared, 7, 0, 0, 0, 0, dormant=True)
    _vehicles(tm.shared, [7])
    tm.shared.buffer_map[7] = [SimpleWaypointIndex(0)]
    tm.shared.track_traffic.set_hero_location(Vector3(1, 1, 0))
    tm.set_respawn_dormant_vehicles(True)
    for bad in [ActorId(-1), ActorId(4294967296)]:
        tm.shared.collision_frame[0] = CollisionHazardData(
            Length(0), bad, False
        )
        with assert_raises(contains="not valid"):
            tm.motion_plan_stage.update(0, tm.shared, world.map, _at(1))
        assert_equal(len(tm.motion_plan_stage.teleportation_instance), 0)
        assert_equal(tm.shared.control_frame[0].kind.value, 0)
        assert_equal(tm.shared.simulation_state.get_location(ActorId(7)).x, 0.0)


def test_command_and_light_record_boundaries() raises:
    var world = _world(straight_town())
    var car = _spawn(world, 20, 1.75)
    var before = world.get_transform(car)
    var after = before
    after.location.x += 10
    var lights = VehicleLightStage()
    lights.update_world_info(
        [(NO_ACTOR, LIGHTS_NONE), (ActorId(4294967295), LIGHTS_NONE)],
        WeatherParameters(),
    )
    for bad in [ActorId(-1), ActorId(4294967296)]:
        with assert_raises(contains="not valid"):
            _ = apply_vehicle_control(bad, VehicleControl())
        with assert_raises(contains="not valid"):
            _ = apply_transform(bad, before)
        with assert_raises(contains="not valid"):
            _ = set_vehicle_light_state(bad, LIGHTS_NONE)
        var invalid = no_command()
        invalid.actor = bad
        with assert_raises(contains="not valid"):
            apply_batch(world, [apply_transform(car, after), invalid])
        assert_equal(world.get_location(car).x, before.location.x)
        with assert_raises(contains="not valid"):
            lights.update_world_info(
                [(car, LIGHTS_NONE), (bad, LIGHTS_NONE)],
                WeatherParameters(),
                False,
            )
        assert_equal(len(lights.all_light_states), 2)
        assert_equal(lights.all_light_states[0][0].value, 0)
        assert_true(lights.is_weather_enabled)
    for actor in [NO_ACTOR, ActorId(4294967295)]:
        assert_equal(
            apply_vehicle_control(actor, VehicleControl()).actor.value,
            actor.value,
        )
        assert_equal(apply_transform(actor, before).actor.value, actor.value)
        assert_equal(
            set_vehicle_light_state(actor, LIGHTS_NONE).actor.value, actor.value
        )
    var invalid_kind = no_command()
    invalid_kind.kind = CommandKind(-1)
    with assert_raises(contains="kind is not valid"):
        apply_batch(world, [apply_transform(car, after), invalid_kind])
    assert_equal(world.get_location(car).x, before.location.x)
    apply_batch(world, List[TrafficCommand]())
    apply_batch(world, [no_command()])


def main() raises:
    var suite = TestSuite.discover_tests[__functions_in_module()]()
    suite^.run()
