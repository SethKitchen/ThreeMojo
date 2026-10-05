# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Collision locks leave with their owner or lead, without changing ids.

The direct stage tests use hand-computed path endpoints and a cold-stage
comparison. World tests inspect ALSM before collision updates, so a later
no-candidate update cannot hide missing life-cycle cleanup.
"""

from extensions.carla.actor import ActorId, NO_ACTOR
from extensions.carla.opendrive import load_opendrive
from extensions.carla.traffic_manager import TrafficManagerLocal
from extensions.carla.traffic_manager_collision import (
    CollisionLock,
    CollisionStage,
    GeometryComparison,
)
from extensions.carla.traffic_manager_map import SimpleWaypointIndex
from extensions.carla.traffic_manager_shared import TrafficManagerShared
from extensions.carla.world import World
from math.vector3 import Vector3
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
    _vehicles,
)
from test_carla_traffic_manager_world import _manager, _spawn, _world
from units.si import Length, Velocity


def _same_lock(actual: CollisionLock, expected: CollisionLock) raises:
    assert_equal(
        actual.distance_to_lead_vehicle, expected.distance_to_lead_vehicle
    )
    assert_equal(actual.initial_lock_distance, expected.initial_lock_distance)
    assert_equal(actual.lead_vehicle_id, expected.lead_vehicle_id)


def _empty_caches(stage: CollisionStage) raises:
    assert_equal(len(stage.geodesic_boundary_map), 0)
    assert_equal(len(stage.geometry_cache), 0)


def _same_geometry(
    actual: GeometryComparison, expected: GeometryComparison
) raises:
    assert_almost_equal(
        actual.reference_vehicle_to_other_geodesic,
        expected.reference_vehicle_to_other_geodesic,
        atol=1e-6,
    )
    assert_almost_equal(
        actual.other_vehicle_to_reference_geodesic,
        expected.other_vehicle_to_reference_geodesic,
        atol=1e-6,
    )
    assert_almost_equal(
        actual.inter_geodesic_distance,
        expected.inter_geodesic_distance,
        atol=1e-6,
    )
    assert_almost_equal(
        actual.inter_bbox_distance, expected.inter_bbox_distance, atol=1e-6
    )


def _update_actors(mut tm: TrafficManagerLocal, mut world: World) raises:
    tm.alsm.update(
        world,
        tm.registered_vehicles,
        tm.shared,
        tm.localization_stage,
        tm.collision_stage,
        tm.traffic_light_stage,
        tm.motion_plan_stage,
    )


def test_remove_actor_drops_owned_and_all_inbound_locks() raises:
    var stage = CollisionStage()
    var gone = ActorId(2)
    var survivor = CollisionLock(8.0, 7.0, ActorId(5))
    stage.collision_locks[2] = CollisionLock(4.0, 6.0, ActorId(1))
    stage.collision_locks[1] = CollisionLock(9.0, 10.0, gone)
    stage.collision_locks[3] = CollisionLock(11.0, 12.0, gone)
    stage.collision_locks[4] = survivor
    stage.remove_actor(gone)
    assert_equal(len(stage.collision_locks), 1)
    assert_false(1 in stage.collision_locks)
    assert_false(2 in stage.collision_locks)
    assert_false(3 in stage.collision_locks)
    _same_lock(stage.collision_locks[4], survivor)
    # Removing an absent id and repeating a removal preserve every field.
    stage.remove_actor(ActorId(99))
    stage.remove_actor(gone)
    assert_equal(len(stage.collision_locks), 1)
    _same_lock(stage.collision_locks[4], survivor)
    stage.remove_actor(ActorId(4))
    stage.remove_actor(ActorId(4))
    assert_equal(len(stage.collision_locks), 0)
    _empty_caches(stage)


def test_remove_actor_handles_self_lock_and_cache_only_state() raises:
    var stage = CollisionStage()
    stage.collision_locks[2] = CollisionLock(4.0, 4.0, ActorId(2))
    stage.remove_actor(ActorId(2))
    assert_equal(len(stage.collision_locks), 0)
    # A removed actor need not own a lock for its cached geometry to go.
    stage.geometry_cache[(2 << 32) | 3] = GeometryComparison(1, 2, 3, 4)
    stage.geodesic_boundary_map[2] = [Vector3(1, 2, 3)]
    stage.remove_actor(ActorId(2))
    _empty_caches(stage)
    stage.remove_actor(ActorId(2))
    _empty_caches(stage)


def _path_state() raises -> TrafficManagerShared:
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
    _put(shared, 1, 50, 1.75, 0, 0)
    _put(shared, 2, 70, 1.75, 0, 0)
    _put(shared, 3, 72, 1.75, 0, 0)
    _vehicles(shared, [1])
    var path = List[SimpleWaypointIndex]()
    for i in range(6):
        path.append(SimpleWaypointIndex(i))
    shared.buffer_map[1] = path^
    return shared^


def test_removal_recomputes_survivor_boundary_and_pair_distances() raises:
    var shared = _path_state()
    var stage = CollisionStage()
    var survivor = CollisionLock(8.0, 7.0, ActorId(4))
    stage.collision_locks[1] = CollisionLock(15.0, 15.0, ActorId(2))
    stage.collision_locks[3] = survivor
    # The path starts at x=55. A 19 m lock reaches the final x=75 node;
    # the speed-only 2.5 m horizon stops at x=60 instead.
    var before = stage.get_geodesic_boundary(ActorId(1), shared)
    assert_equal(before[0].x, 75.0)
    var old_pair = stage.get_geometry_between_actors(
        ActorId(1), ActorId(3), shared
    )
    assert_equal(old_pair.other_vehicle_to_reference_geodesic, 0.0)
    _ = stage.get_geometry_between_actors(ActorId(1), ActorId(2), shared)
    stage.remove_actor(ActorId(2))
    _empty_caches(stage)
    _same_lock(stage.collision_locks[3], survivor)
    assert_false(1 in stage.collision_locks)
    assert_equal(stage.get_bounding_box_extension(ActorId(1), shared), 2.5)
    var after = stage.get_geodesic_boundary(ActorId(1), shared)
    assert_equal(after[0].x, 60.0)
    assert_equal(after[len(after) - 1].x, 60.0)
    var actual = stage.get_geometry_between_actors(
        ActorId(1), ActorId(3), shared
    )
    # Actor 3's rear is at x=69.6, beyond the shortened x=60 boundary.
    assert_almost_equal(
        actual.other_vehicle_to_reference_geodesic, 9.6, atol=1e-4
    )
    var fresh = CollisionStage()
    fresh.collision_locks[3] = survivor
    _same_geometry(
        actual,
        fresh.get_geometry_between_actors(ActorId(1), ActorId(3), shared),
    )
    _same_lock(stage.collision_locks[3], survivor)


def test_no_candidate_update_after_removal_keeps_fresh_distance() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    stage.update(0, shared)
    assert_true(shared.collision_frame[0].hazard)
    assert_true(stage.get_bounding_box_extension(ActorId(1), shared) > 9.0)
    stage.clear_cycle_cache()
    # Removing lead 2 must preserve a different survivor's lock on ego 1.
    var inbound = CollisionLock(6.0, 5.0, ActorId(1))
    var survivor = CollisionLock(8.0, 7.0, ActorId(4))
    stage.collision_locks[5] = inbound
    stage.collision_locks[3] = survivor
    _ = stage.get_geometry_between_actors(ActorId(1), ActorId(2), shared)
    var expected_random = shared.random_device.copy()
    stage.remove_actor(ActorId(2))
    shared.track_traffic.delete_actor(ActorId(2))
    shared.simulation_state.remove_actor(ActorId(2))
    assert_false(1 in stage.collision_locks)
    _empty_caches(stage)
    stage.update(0, shared)
    assert_false(1 in stage.collision_locks)
    _same_lock(stage.collision_locks[5], inbound)
    _same_lock(stage.collision_locks[3], survivor)
    assert_false(shared.collision_frame[0].hazard)
    assert_equal(shared.collision_frame[0].hazard_actor_id, NO_ACTOR)
    assert_true(
        shared.collision_frame[0].available_distance_margin.value > 1e30
    )
    assert_almost_equal(
        stage.get_bounding_box_extension(ActorId(1), shared),
        2.5 + 1.8 * 1.8,
        atol=1e-5,
    )
    _empty_caches(stage)
    # A second update cannot resurrect the removed lead or draw randomly.
    stage.update(0, shared)
    assert_equal(len(stage.collision_locks), 2)
    assert_equal(shared.random_device.next(), expected_random.next())


def test_live_unnegotiated_lead_keeps_existing_update_semantics() raises:
    var map = load_opendrive(straight_town())
    for disabled in [False, True]:
        var shared = _setup_follow(map, 50, 60, 5)
        var stage = CollisionStage()
        stage.update(0, shared)
        var held = stage.collision_locks[1]
        if disabled:
            shared.parameters.set_collision_detection(
                ActorId(1), ActorId(2), False
            )
        else:
            shared.track_traffic.delete_actor(ActorId(2))
        # No stage removal occurs: this follow-up intentionally does not
        # change the behavior of a live lead with no enabled candidate.
        var expected_random = shared.random_device.copy()
        stage.update(0, shared)
        _same_lock(stage.collision_locks[1], held)
        assert_false(shared.collision_frame[0].hazard)
        assert_true(shared.simulation_state.contains_actor(ActorId(2)))
        assert_equal(shared.random_device.next(), expected_random.next())


def test_absent_ego_update_after_removal_does_not_restore_owned_lock() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    stage.update(0, shared)
    assert_true(1 in stage.collision_locks)
    stage.remove_actor(ActorId(1))
    shared.track_traffic.delete_actor(ActorId(1))
    shared.simulation_state.remove_actor(ActorId(1))
    stage.update(0, shared)
    assert_false(1 in stage.collision_locks)
    assert_false(shared.collision_frame[0].hazard)
    _empty_caches(stage)


def test_ignored_negotiated_hazard_keeps_lock_and_one_random_draw() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = CollisionStage()
    shared.parameters.set_percentage_ignore_vehicles(ActorId(1), 100)
    var expected_random = shared.random_device.copy()
    _ = expected_random.next()
    stage.update(0, shared)
    assert_false(shared.collision_frame[0].hazard)
    assert_true(1 in stage.collision_locks)
    assert_equal(stage.collision_locks[1].lead_vehicle_id, ActorId(2))
    assert_almost_equal(
        stage.collision_locks[1].distance_to_lead_vehicle, 5.2, atol=1e-4
    )
    assert_true(len(stage.geometry_cache) > 0)
    assert_equal(shared.random_device.next(), expected_random.next())


def test_temporary_unregister_clears_locks_but_keeps_preferences() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var gone = _spawn(world, 20, 1.75)
    var follower = _spawn(world, 60, 1.75)
    var other = _spawn(world, 100, 1.75)
    var other_lead = _spawn(world, 140, 1.75)
    tm.register_vehicles(world, [gone, follower])
    tm.set_desired_speed(gone, Velocity(3))
    tm.set_lane_offset(gone, Length(0.1))
    tm.set_auto_lane_change(gone, False)
    tm.step(world)
    var survivor = CollisionLock(8.0, 7.0, other_lead)
    tm.collision_stage.collision_locks[gone.value] = CollisionLock(4, 4, other)
    tm.collision_stage.collision_locks[follower.value] = CollisionLock(
        9, 9, gone
    )
    tm.collision_stage.collision_locks[other.value] = survivor
    _ = tm.collision_stage.get_geometry_between_actors(
        follower, other, tm.shared
    )
    tm.unregister_vehicles([gone])
    assert_true(world.is_alive(gone))
    assert_false(tm.registered_vehicles.contains(gone))
    assert_false(tm.shared.simulation_state.contains_actor(gone))
    assert_false(gone.value in tm.collision_stage.collision_locks)
    assert_false(follower.value in tm.collision_stage.collision_locks)
    _same_lock(tm.collision_stage.collision_locks[other.value], survivor)
    _empty_caches(tm.collision_stage)
    assert_true(tm.shared.parameters.has_desired_speed(gone))
    assert_equal(tm.shared.parameters.get_lane_offset(gone).value, 0.1)
    assert_false(tm.shared.parameters.get_auto_lane_change(gone))
    tm.unregister_vehicles([gone])
    _same_lock(tm.collision_stage.collision_locks[other.value], survivor)
    tm.register_vehicles(world, [gone])
    tm.step(world)
    assert_true(tm.shared.simulation_state.contains_actor(gone))
    assert_true(tm.shared.parameters.has_desired_speed(gone))
    assert_false(gone.value in tm.collision_stage.collision_locks)


def test_alsm_removes_registered_and_observed_unregistered_dead_leads() raises:
    for registered_lead in [False, True]:
        var world = _world(straight_town())
        var tm = _manager(world)
        var follower = _spawn(world, 20, 1.75)
        var lead = _spawn(world, 26, 1.75)
        var other = _spawn(world, 100, 1.75)
        var other_lead = _spawn(world, 140, 1.75)
        tm.register_vehicles(world, [follower])
        if registered_lead:
            tm.register_vehicles(world, [lead])
        tm.step(world)
        assert_true(follower.value in tm.collision_stage.collision_locks)
        assert_equal(
            tm.collision_stage.collision_locks[follower.value].lead_vehicle_id,
            lead,
        )
        assert_equal(
            lead.value in tm.alsm.unregistered_actors, not registered_lead
        )
        var survivor = CollisionLock(8.0, 7.0, other_lead)
        tm.collision_stage.collision_locks[other.value] = survivor
        _ = tm.collision_stage.get_geometry_between_actors(
            follower, other, tm.shared
        )
        assert_true(world.destroy_actor(lead))
        # Inspect before collision.update can hide a missed ALSM removal.
        _update_actors(tm, world)
        assert_false(follower.value in tm.collision_stage.collision_locks)
        assert_false(tm.shared.simulation_state.contains_actor(lead))
        assert_false(lead.value in tm.alsm.unregistered_actors)
        _same_lock(tm.collision_stage.collision_locks[other.value], survivor)
        _empty_caches(tm.collision_stage)
        _update_actors(tm, world)
        _same_lock(tm.collision_stage.collision_locks[other.value], survivor)
        tm.step(world)
        assert_false(tm.shared.collision_frame[0].hazard)
        assert_true(world.is_alive(follower))


def test_observed_lead_promotion_preserves_locks_and_cycle_caches() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var follower = _spawn(world, 20, 1.75)
    var lead = _spawn(world, 26, 1.75)
    tm.register_vehicles(world, [follower])
    tm.step(world)
    assert_true(follower.value in tm.collision_stage.collision_locks)
    assert_true(lead.value in tm.alsm.unregistered_actors)
    var held = tm.collision_stage.collision_locks[follower.value]
    _ = tm.collision_stage.get_geometry_between_actors(
        follower, lead, tm.shared
    )
    var pair_key = (follower.value << 32) | lead.value
    var geometry = tm.collision_stage.geometry_cache[pair_key]
    var boundary = tm.collision_stage.geodesic_boundary_map[
        follower.value
    ].copy()
    assert_true(len(boundary) > 0)
    tm.register_vehicles(world, [lead])
    _update_actors(tm, world)
    assert_true(world.is_alive(lead))
    assert_true(tm.registered_vehicles.contains(lead))
    assert_true(tm.shared.simulation_state.contains_actor(lead))
    assert_false(lead.value in tm.alsm.unregistered_actors)
    assert_true(follower.value in tm.collision_stage.collision_locks)
    _same_lock(tm.collision_stage.collision_locks[follower.value], held)
    var cached = tm.collision_stage.geometry_cache[pair_key]
    assert_equal(
        cached.reference_vehicle_to_other_geodesic,
        geometry.reference_vehicle_to_other_geodesic,
    )
    assert_equal(
        cached.other_vehicle_to_reference_geodesic,
        geometry.other_vehicle_to_reference_geodesic,
    )
    assert_equal(
        cached.inter_geodesic_distance, geometry.inter_geodesic_distance
    )
    assert_equal(cached.inter_bbox_distance, geometry.inter_bbox_distance)
    var after = tm.collision_stage.geodesic_boundary_map[follower.value].copy()
    assert_equal(len(after), len(boundary))
    for i in range(len(boundary)):
        assert_true(after[i] == boundary[i])
    _update_actors(tm, world)
    _same_lock(tm.collision_stage.collision_locks[follower.value], held)
    tm.step(world)
    assert_equal(
        tm.collision_stage.collision_locks[follower.value].lead_vehicle_id, lead
    )


def test_direct_observed_removal_and_dead_promotion_clear_locks() raises:
    for promoted in [False, True]:
        var world = _world(straight_town())
        var tm = _manager(world)
        var follower = _spawn(world, 20, 1.75)
        var lead = _spawn(world, 26, 1.75)
        tm.register_vehicles(world, [follower])
        tm.step(world)
        assert_true(follower.value in tm.collision_stage.collision_locks)
        assert_true(lead.value in tm.alsm.unregistered_actors)
        _ = tm.collision_stage.get_geometry_between_actors(
            follower, lead, tm.shared
        )
        if promoted:
            tm.register_vehicles(world, [lead])
        assert_true(world.destroy_actor(lead))
        if promoted:
            # It is still in both sets. update() removes dead registered
            # actors before it processes the old unregistered observation.
            _update_actors(tm, world)
            assert_false(tm.registered_vehicles.contains(lead))
        else:
            # The public removal method also retains its standalone cleanup.
            tm.alsm.remove_actor(
                lead,
                False,
                tm.registered_vehicles,
                tm.shared,
                tm.localization_stage,
                tm.collision_stage,
                tm.traffic_light_stage,
                tm.motion_plan_stage,
            )
        assert_false(follower.value in tm.collision_stage.collision_locks)
        assert_false(tm.shared.simulation_state.contains_actor(lead))
        assert_false(lead.value in tm.alsm.unregistered_actors)
        _empty_caches(tm.collision_stage)


def test_cycle_clear_preserves_locks_and_reset_forgets_them() raises:
    var stage = CollisionStage()
    var lock = CollisionLock(8.0, 7.0, ActorId(2))
    stage.collision_locks[1] = lock
    stage.geometry_cache[(1 << 32) | 2] = GeometryComparison(1, 2, 3, 4)
    stage.geodesic_boundary_map[1] = [Vector3(1, 2, 3)]
    stage.clear_cycle_cache()
    _empty_caches(stage)
    _same_lock(stage.collision_locks[1], lock)
    stage.geometry_cache[(1 << 32) | 2] = GeometryComparison(1, 2, 3, 4)
    stage.geodesic_boundary_map[1] = [Vector3(1, 2, 3)]
    stage.reset()
    _empty_caches(stage)
    assert_equal(len(stage.collision_locks), 0)
    stage.reset()
    _empty_caches(stage)
    assert_equal(len(stage.collision_locks), 0)


def test_episode_reset_does_not_reuse_old_lead_distances() raises:
    var old_world = _world(straight_town())
    var tm = _manager(old_world)
    var old_follower = _spawn(old_world, 20, 1.75)
    var old_lead = _spawn(old_world, 26, 1.75)
    tm.register_vehicles(old_world, [old_follower])
    tm.step(old_world)
    assert_true(old_follower.value in tm.collision_stage.collision_locks)
    _ = tm.collision_stage.get_geometry_between_actors(
        old_follower, old_lead, tm.shared
    )
    tm.shared.parameters.set_global_distance_to_leading_vehicle(Length(3))
    var next_world = _world(straight_town())
    var next_follower = _spawn(next_world, 50, 1.75)
    var next_lead = _spawn(next_world, 100, 1.75)
    assert_equal(next_follower, old_follower)
    assert_equal(next_lead, old_lead)
    tm.reset(next_world)
    assert_equal(len(tm.collision_stage.collision_locks), 0)
    _empty_caches(tm.collision_stage)
    assert_equal(
        tm.shared.parameters.get_distance_to_leading_vehicle(
            next_follower
        ).value,
        3.0,
    )
    tm.register_vehicles(next_world, [next_follower])
    tm.step(next_world)
    assert_false(tm.shared.collision_frame[0].hazard)
    assert_false(next_follower.value in tm.collision_stage.collision_locks)
    assert_equal(
        tm.collision_stage.get_bounding_box_extension(next_follower, tm.shared),
        2.5,
    )
    tm.stop()
    tm.stop()
    _empty_caches(tm.collision_stage)
    assert_equal(len(tm.collision_stage.collision_locks), 0)
    tm.release()
    _empty_caches(tm.collision_stage)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
