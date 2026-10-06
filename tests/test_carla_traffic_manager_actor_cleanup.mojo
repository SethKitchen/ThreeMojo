# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Actor lifetime cleanup without changing temporary autopilot preferences."""

from extensions.carla.actor import ActorId, NO_ACTOR
from extensions.carla.traffic_manager import (
    is_physics_enabled,
    set_simulate_physics,
)
from extensions.carla.traffic_manager_map import ROAD_OPTION_LEFT
from extensions.carla.traffic_manager_parameters import Parameters
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from test_carla_traffic_manager import straight_town
from test_carla_traffic_manager_world import _manager, _spawn, _world
from units.si import Duration, Length, MILLISECOND, Velocity


def _configure(
    mut p: Parameters, actor: ActorId, other: ActorId, exact: Bool
) raises:
    if exact:
        p.set_desired_speed(actor, Velocity(3))
    else:
        p.set_percentage_speed_difference(actor, 23)
    p.set_lane_offset(actor, Length(1))
    p.set_large_vehicle_wide_turn(actor, False)
    p.set_collision_detection(actor, other, False)
    p.set_distance_to_leading_vehicle(actor, Length(7))
    p.set_force_lane_change(actor, True)
    p.set_auto_lane_change(actor, False)
    p.set_percentage_running_light(actor, 11)
    p.set_percentage_running_sign(actor, 12)
    p.set_percentage_ignore_walkers(actor, 13)
    p.set_percentage_ignore_vehicles(actor, 14)
    p.set_keep_slow_lane_percentage(actor, 15)
    p.set_random_left_lane_change_percentage(actor, 16)
    p.set_random_right_lane_change_percentage(actor, 17)
    p.set_update_vehicle_lights(actor, True)
    p.set_custom_path(actor, [Vector3(1, 2, 3)], True)
    p.set_imported_route(actor, [ROAD_OPTION_LEFT], True)


def _assert_absent(p: Parameters, actor: ActorId) raises:
    assert_false(actor.value in p._percentage_difference)
    assert_false(actor.value in p._lane_offset)
    assert_false(actor.value in p._exact_desired_speed)
    assert_false(actor.value in p._large_vehicle_wide_turn)
    assert_false(actor.value in p._ignore_collision)
    assert_false(actor.value in p._distance_to_leading_vehicle)
    assert_false(actor.value in p._force_lane_change)
    assert_false(actor.value in p._auto_lane_change)
    assert_false(actor.value in p._perc_run_traffic_light)
    assert_false(actor.value in p._perc_run_traffic_sign)
    assert_false(actor.value in p._perc_ignore_walkers)
    assert_false(actor.value in p._perc_ignore_vehicles)
    assert_false(actor.value in p._perc_keep_slow_lane)
    assert_false(actor.value in p._perc_random_left)
    assert_false(actor.value in p._perc_random_right)
    assert_false(actor.value in p._auto_update_vehicle_lights)
    assert_false(actor.value in p._upload_path)
    assert_false(actor.value in p._custom_path)
    assert_false(actor.value in p._upload_route)
    assert_false(actor.value in p._custom_route)


def _set_globals(mut p: Parameters):
    p.set_global_percentage_speed_difference(17)
    p.set_global_lane_offset(Length(0.5))
    p.set_global_large_vehicle_wide_turn(False)
    p.set_global_distance_to_leading_vehicle(Length(9))
    p.set_synchronous_mode(True)
    p.set_synchronous_mode_time_out(Duration(27, MILLISECOND))
    p.set_hybrid_physics_mode(True)
    p.set_hybrid_physics_radius(Length(73))
    p.set_respawn_dormant_vehicles(True)
    p.set_max_boundaries(Length(21), Length(1800))
    p.set_boundaries_respawn_dormant_vehicles(Length(101), Length(900))
    p.set_osm_mode(False)


def _assert_globals(p: Parameters) raises:
    assert_equal(p._global_percentage_difference, 17.0)
    assert_equal(p._global_lane_offset.value, 0.5)
    assert_false(p._global_large_vehicle_wide_turn)
    assert_equal(p._distance_margin.value, 9.0)
    assert_true(p.get_synchronous_mode())
    assert_equal(p.get_synchronous_mode_time_out().to(MILLISECOND), 27.0)
    assert_true(p.get_hybrid_physics_mode())
    assert_equal(p.get_hybrid_physics_radius().value, 73.0)
    assert_true(p.get_respawn_dormant_vehicles())
    assert_equal(p._min_lower_bound.value, 21.0)
    assert_equal(p._max_upper_bound.value, 1800.0)
    assert_equal(p.get_lower_boundary_respawn_dormant_vehicles().value, 101.0)
    assert_equal(p.get_upper_boundary_respawn_dormant_vehicles().value, 900.0)
    assert_false(p.get_osm_mode())


def test_parameters_remove_owner_and_inbound_references() raises:
    var p = Parameters()
    _set_globals(p)
    var gone = ActorId(2)
    var survivor = ActorId(3)
    var other = ActorId(4)
    _configure(p, gone, survivor, False)
    _configure(p, survivor, gone, True)
    p.set_collision_detection(survivor, other, False)
    p.set_collision_detection(other, gone, False)
    assert_equal(len(p.configured_actor_ids()), 3)
    p.remove_actor(gone)
    _assert_absent(p, gone)
    assert_true(p.get_collision_detection(survivor, gone))
    assert_false(p.get_collision_detection(survivor, other))
    assert_false(other.value in p._ignore_collision)
    assert_true(p.has_desired_speed(survivor))
    assert_equal(p.get_lane_offset(survivor).value, 1.0)
    assert_equal(len(p.get_custom_path(survivor)), 1)
    assert_equal(len(p.get_imported_route(survivor)), 1)
    # Check every survivor-owned map, including pending one-shot commands.
    assert_false(survivor.value in p._percentage_difference)
    assert_equal(p._exact_desired_speed[survivor.value].value, 3.0)
    assert_false(p._large_vehicle_wide_turn[survivor.value])
    assert_equal(len(p._ignore_collision[survivor.value]), 1)
    assert_equal(p._ignore_collision[survivor.value][0], other.value)
    assert_equal(p._distance_to_leading_vehicle[survivor.value].value, 7.0)
    assert_true(p._force_lane_change[survivor.value].change_lane)
    assert_true(p._force_lane_change[survivor.value].direction)
    assert_false(p._auto_lane_change[survivor.value])
    assert_equal(p._perc_run_traffic_light[survivor.value], 11.0)
    assert_equal(p._perc_run_traffic_sign[survivor.value], 12.0)
    assert_equal(p._perc_ignore_walkers[survivor.value], 13.0)
    assert_equal(p._perc_ignore_vehicles[survivor.value], 14.0)
    assert_equal(p._perc_keep_slow_lane[survivor.value], 15.0)
    assert_equal(p._perc_random_left[survivor.value], 16.0)
    assert_equal(p._perc_random_right[survivor.value], 17.0)
    assert_true(p._auto_update_vehicle_lights[survivor.value])
    assert_true(p._upload_path[survivor.value])
    assert_true(p._custom_path[survivor.value][0] == Vector3(1, 2, 3))
    assert_true(p._upload_route[survivor.value])
    assert_true(p._custom_route[survivor.value][0] == ROAD_OPTION_LEFT)
    # The alternative speed map also survives another actor's removal.
    p.set_percentage_speed_difference(survivor, 23)
    p.remove_actor(gone)
    assert_equal(p._percentage_difference[survivor.value], 23.0)
    assert_false(p.has_desired_speed(survivor))
    assert_equal(len(p.configured_actor_ids()), 2)
    _assert_globals(p)
    # Repeated removal and absent valid ids are harmless.
    p.remove_actor(gone)
    p.remove_actor(ActorId(99))
    p.remove_actor(survivor)
    _assert_absent(p, survivor)
    assert_equal(len(p.configured_actor_ids()), 0)
    with assert_raises(contains="not valid"):
        p.remove_actor(ActorId(-1))


def test_clear_actor_settings_keeps_every_global_setting() raises:
    var p = Parameters()
    _set_globals(p)
    _configure(p, ActorId(2), ActorId(3), False)
    _configure(p, ActorId(3), ActorId(2), True)
    p.clear_actor_settings()
    _assert_absent(p, ActorId(2))
    _assert_absent(p, ActorId(3))
    assert_equal(len(p.configured_actor_ids()), 0)
    _assert_globals(p)
    p.clear_actor_settings()
    _assert_globals(p)


def test_unregister_refreshes_physics_and_preserves_preferences() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    tm.set_desired_speed(car, Velocity(3))
    tm.set_lane_offset(car, Length(0.1))
    tm.set_auto_lane_change(car, False)
    tm.step(world)
    assert_true(tm.alsm.has_physics_enabled[car.value])
    tm.unregister_vehicles([car])
    assert_false(car.value in tm.alsm.has_physics_enabled)
    assert_true(tm.shared.parameters.has_desired_speed(car))
    assert_equal(tm.shared.parameters.get_lane_offset(car).value, 0.1)
    assert_false(tm.shared.parameters.get_auto_lane_change(car))
    set_simulate_physics(world, car, False)
    tm.register_vehicles(world, [car])
    tm.step(world)
    assert_true(is_physics_enabled(world, car))
    assert_true(tm.alsm.has_physics_enabled[car.value])
    assert_true(tm.shared.parameters.has_desired_speed(car))
    # A second unregister has no runtime cache entry to remove.
    tm.unregister_vehicles([car])
    tm.unregister_vehicles([car])
    tm.stop()
    assert_true(tm.shared.parameters.has_desired_speed(car))
    tm.release()
    assert_true(tm.shared.parameters.has_desired_speed(car))


def test_destroyed_settings_are_pruned_without_runtime_membership() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var gone = _spawn(world, 20, 1.75)
    var survivor = _spawn(world, 60, 1.75)
    tm.set_desired_speed(gone, Velocity(3))
    tm.set_lane_offset(survivor, Length(0.25))
    tm.set_collision_detection(survivor, gone, False)
    tm.register_vehicles(world, [gone])
    tm.step(world)
    tm.unregister_vehicles([gone])
    assert_true(world.destroy_actor(gone))
    assert_false(world.destroy_actor(gone))
    tm.step(world)
    _assert_absent(tm.shared.parameters, gone)
    assert_true(tm.shared.parameters.get_collision_detection(survivor, gone))
    assert_equal(tm.shared.parameters.get_lane_offset(survivor).value, 0.25)
    with assert_raises(contains="destroyed"):
        _ = world.actor(gone)
    # This actor is destroyed before the TM ever observes it, and appears
    # only as another actor's collision-ignore target.
    var unseen = _spawn(world, 20, 1.75)
    assert_true(unseen != gone)
    tm.set_collision_detection(survivor, unseen, False)
    assert_true(world.destroy_actor(unseen))
    tm.step(world)
    assert_true(tm.shared.parameters.get_collision_detection(survivor, unseen))
    assert_equal(len(tm.shared.parameters.configured_actor_ids()), 1)


def test_future_actor_settings_survive_until_permanent_destruction() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var future = ActorId(len(world.actors) + 1)
    tm.set_lane_offset(future, Length(0.25))
    tm.set_lane_offset(NO_ACTOR, Length(0.5))
    # Defensive boundary: malformed raw storage must not index the world.
    tm.shared.parameters._lane_offset[-1] = Length(1)
    tm.step(world)
    assert_equal(tm.shared.parameters.get_lane_offset(future).value, 0.25)
    assert_equal(tm.shared.parameters.get_lane_offset(NO_ACTOR).value, 0.5)
    var car = _spawn(world, 20, 1.75)
    assert_equal(car, future)
    tm.step(world)
    assert_equal(tm.shared.parameters.get_lane_offset(car).value, 0.25)
    assert_true(world.destroy_actor(car))
    tm.step(world)
    _assert_absent(tm.shared.parameters, car)


def test_reset_drops_old_episode_preferences_for_reused_actor_id() raises:
    var old_world = _world(straight_town())
    var old_car = _spawn(old_world, 20, 1.75)
    var tm = _manager(old_world)
    _set_globals(tm.shared.parameters)
    _configure(tm.shared.parameters, old_car, ActorId(999), True)
    var next_world = _world(straight_town())
    var next_car = _spawn(next_world, 20, 1.75)
    assert_equal(next_car, old_car)
    tm.reset(next_world)
    assert_equal(len(tm.shared.parameters.configured_actor_ids()), 0)
    _assert_absent(tm.shared.parameters, next_car)
    _assert_globals(tm.shared.parameters)
    assert_equal(tm.shared.parameters.get_lane_offset(next_car).value, 0.5)
    assert_false(tm.shared.parameters.has_desired_speed(next_car))
    assert_true(
        tm.shared.parameters.get_collision_detection(next_car, ActorId(999))
    )


def test_configured_state_is_bounded_across_spawn_destroy_cycles() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var survivor = _spawn(world, 60, 1.75)
    tm.set_lane_offset(survivor, Length(0.25))
    for _ in range(32):
        var car = _spawn(world, 20, 1.75)
        tm.set_desired_speed(car, Velocity(3))
        tm.set_collision_detection(survivor, car, False)
        assert_true(world.destroy_actor(car))
        tm.step(world)
        assert_equal(len(tm.shared.parameters.configured_actor_ids()), 1)
        assert_equal(len(tm.shared.parameters._exact_desired_speed), 0)
        assert_equal(len(tm.shared.parameters._ignore_collision), 0)
        assert_equal(len(tm.alsm.has_physics_enabled), 0)
        assert_equal(tm.shared.parameters.get_lane_offset(survivor).value, 0.25)


def test_registered_and_osm_destruction_clear_runtime_and_settings() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    tm.set_desired_speed(car, Velocity(3))
    tm.step(world)
    assert_true(car.value in tm.alsm.has_physics_enabled)
    assert_true(world.destroy_actor(car))
    tm.step(world)
    _assert_absent(tm.shared.parameters, car)
    assert_false(car.value in tm.alsm.has_physics_enabled)
    var removed_by_osm = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [removed_by_osm])
    tm.set_desired_speed(removed_by_osm, Velocity(3))
    tm.step(world)
    tm.shared.marked_for_removal.append(removed_by_osm)
    tm.step(world)
    assert_false(world.is_alive(removed_by_osm))
    _assert_absent(tm.shared.parameters, removed_by_osm)
    assert_false(removed_by_osm.value in tm.alsm.has_physics_enabled)


def test_async_cleanup_waits_for_the_next_processed_frame() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    tm.set_synchronous_mode(False)
    var car = _spawn(world, 20, 1.75)
    tm.set_desired_speed(car, Velocity(3))
    _ = world.tick()
    tm.step(world)
    assert_true(world.destroy_actor(car))
    tm.step(world)
    assert_true(tm.shared.parameters.has_desired_speed(car))
    _ = world.tick()
    tm.step(world)
    _assert_absent(tm.shared.parameters, car)


def test_configured_ids_include_an_empty_collision_owner() raises:
    var p = Parameters()
    var owner = ActorId(2)
    var target = ActorId(3)
    p.set_collision_detection(owner, target, False)
    p.set_collision_detection(owner, target, True)
    assert_equal(len(p._ignore_collision[owner.value]), 0)
    var ids = p.configured_actor_ids()
    assert_equal(len(ids), 1)
    assert_equal(ids[0], owner)
    p.remove_actor(ActorId(99))
    assert_equal(len(p.configured_actor_ids()), 1)
    p.remove_actor(owner)
    assert_equal(len(p.configured_actor_ids()), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
