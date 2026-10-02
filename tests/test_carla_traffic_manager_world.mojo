# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's traffic manager driving a world's vehicles through physics.

The world steps at 0.05 s. The expected behavior is worked by hand from
CARLA's rules, with a tolerance for the physics:

- The target speed is the limit, 30 km/h before any sign, times one
  minus the speed difference over 100, or the desired speed.
- A follower stops when its room, the gap between the boxes less the
  distance to keep, falls under 0.2 m, after closing in at 12 km/h; it
  brakes fully from there, so the gap ends a little under the distance
  plus 0.2 m.
- A light's box is 3 m long, 3 m before the light at s = 95: from x =
  90.5 to 93.5. A car stops once its front, 2.4 m ahead of its center,
  is in the box.
- Without physics (hybrid mode), a car at the target speed moves 8.333
  m/s times 0.05 s each step, exactly.
- A dormant car comes back on the first node of lane -2 strictly
  between 20 m and 45 m of the hero along x: x = 110, 0.5 m up.
"""

from extensions.carla.actor import (
    ACTOR_DORMANT,
    ActorId,
    GREEN,
    NO_ACTOR,
    RED,
)
from extensions.carla.opendrive import load_opendrive
from extensions.carla.physics.body import DYNAMIC, KINEMATIC
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.traffic_manager import (
    ALSM,
    ActorSet,
    TrafficManagerLocal,
    apply_batch,
    is_physics_enabled,
    set_simulate_physics,
)
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    ROAD_OPTION_LANE_FOLLOW,
    ROAD_OPTION_RIGHT,
    ROAD_OPTION_VOID,
    SimpleWaypointIndex,
)
from extensions.carla.traffic_manager_shared import (
    CommandKind,
    TrafficCommand,
    apply_transform,
    apply_vehicle_control,
    no_command,
    set_vehicle_light_state,
)
from extensions.carla.traffic_manager_state import (
    TRAFFIC_PEDESTRIAN,
    TRAFFIC_VEHICLE,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.vehicle import LIGHT_LOW_BEAM, LIGHT_POSITION
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from test_carla_traffic_manager import junction_town, straight_town
from units.si import (
    Angle,
    DEGREE,
    Duration,
    Length,
    MILLISECOND,
    SECOND,
    Velocity,
)


def _world(text: String) raises -> World:
    var world = World(load_opendrive(text))
    var settings = EpisodeSettings()
    settings.synchronous_mode = True
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    return world^


def _spawn(
    mut world: World,
    x: Float32,
    y: Float32,
    role: String = "",
    blueprint: String = "vehicle.lincoln.mkz",
    yaw: Float32 = 0,
) raises -> ActorId:
    var bp = world.get_blueprint_library().at(blueprint)
    if role != "":
        bp.set_attribute("role_name", role)
    return world.spawn_actor(
        bp,
        CarlaTransform(
            Length(x),
            Length(y),
            Length(0.3),
            CarlaRotation(
                Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)
            ),
        ),
    )


def _manager(world: World) raises -> TrafficManagerLocal:
    var tm = TrafficManagerLocal(world, seed=UInt64(42))
    tm.set_synchronous_mode(True)
    return tm^


def _run(mut tm: TrafficManagerLocal, mut world: World, ticks: Int) raises:
    for _ in range(ticks):
        _ = tm.tick(world)


def _speed(world: World, car: ActorId) raises -> Float32:
    return world.get_velocity(car).length()


def test_speed_targets() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var plain = _spawn(world, 20, 1.75)
    var fast = _spawn(world, 20, 5.25)
    var slow = _spawn(world, 250, -1.75, "", "vehicle.lincoln.mkz", 180)
    tm.register_vehicles(world, [plain, fast, slow])
    # 30 km/h; 30 % faster (39 km/h); a desired 5 m/s.
    tm.set_percentage_speed_difference(fast, -30)
    tm.set_desired_speed(slow, Velocity(5.0))
    _run(tm, world, 160)
    assert_almost_equal(_speed(world, plain), 8.333333, atol=0.05)
    assert_almost_equal(_speed(world, fast), 10.833333, atol=0.05)
    assert_almost_equal(_speed(world, slow), 5.0, atol=0.05)
    # Each keeps its lane.
    assert_almost_equal(world.get_location(plain).y, 1.75, atol=0.05)
    assert_almost_equal(world.get_location(slow).y, -1.75, atol=0.05)


def test_following_at_the_set_distance() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    var lead = _spawn(world, 60, 1.75)
    tm.register_vehicles(world, [car])
    tm.set_distance_to_leading_vehicle(car, Length(5))
    tm.set_auto_lane_change(car, False)
    _run(tm, world, 300)
    var gap = world.get_location(lead).x - world.get_location(car).x - 4.8
    assert_true(gap > 4.2 and gap < 5.2)
    assert_true(_speed(world, car) < 0.01)
    # Ignoring every vehicle, it drives into the lead.
    tm.set_percentage_ignore_vehicles(car, 100)
    _run(tm, world, 100)
    var closer = world.get_location(lead).x - world.get_location(car).x - 4.8
    assert_true(closer < 1.0)


def test_following_a_slower_vehicle() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    var front = _spawn(world, 45, 1.75)
    tm.register_vehicles(world, [car, front])
    tm.set_desired_speed(front, Velocity(3.0))
    tm.set_auto_lane_change(car, False)
    var initial_gap = (
        world.get_location(front).x - world.get_location(car).x - 4.8
    )
    var least = Float32(100)
    var halfway = Float32(0)
    var front_halfway = Float32(0)
    for k in range(400):
        _ = tm.tick(world)
        least = min(
            least, world.get_location(front).x - world.get_location(car).x - 4.8
        )
        if k == 199:
            halfway = world.get_location(car).x
            front_halfway = world.get_location(front).x
    # Never closer than the 2 m gap, less the 0.2 m braking margin and a
    # little braking. Both controllers change speed during the run. Compare
    # progress over the same last 10 s using the world's positions, rather
    # than assuming the front car travels at its exact commanded speed.
    assert_true(least > 1.0)
    var final_gap = (
        world.get_location(front).x - world.get_location(car).x - 4.8
    )
    assert_true(final_gap < initial_gap)
    var front_average = (world.get_location(front).x - front_halfway) / 10
    assert_almost_equal(front_average, 3.0, atol=0.25)
    assert_almost_equal(
        (world.get_location(car).x - halfway) / 10, front_average, atol=0.25
    )


def test_stops_at_a_red_light() raises:
    var world = _world(junction_town())
    var tm = _manager(world)
    var lights = world.filter_actors("traffic.traffic_light")
    assert_equal(len(lights), 1)
    world.set_traffic_light_state(lights[0], RED)
    world.freeze_all_traffic_lights(True)
    var car = _spawn(world, 40, 1.75)
    tm.register_vehicles(world, [car])
    _run(tm, world, 300)
    var x = world.get_location(car).x
    assert_true(x > 88.1 and x < 91.1)
    assert_true(_speed(world, car) < 0.01)
    assert_true(world.is_at_traffic_light(car))
    assert_true(tm.check_all_frozen(world, lights))
    assert_true(tm.check_all_frozen(world, List[ActorId]()))
    world.set_traffic_light_state(lights[0], GREEN)
    assert_false(tm.check_all_frozen(world, lights))
    world.freeze_all_traffic_lights(False)
    world.set_traffic_light_state(lights[0], RED)
    assert_false(tm.check_all_frozen(world, lights))
    world.set_traffic_light_state(lights[0], GREEN)
    world.freeze_all_traffic_lights(True)
    _run(tm, world, 100)
    assert_true(world.get_location(car).x > 100)


def test_stops_at_a_stop_sign() raises:
    var world = _world(junction_town().replace('type="1000001"', 'type="206"'))
    var tm = _manager(world)
    var car = _spawn(world, 40, 1.75)
    tm.register_vehicles(world, [car])
    var stopped_at = -1
    var stopped_x = Float32(0)
    var held = 0
    for k in range(400):
        _ = tm.tick(world)
        if tm.shared.tl_frame[0]:
            held += 1
        if stopped_at < 0 and _speed(world, car) < 0.001:
            stopped_at = k
            stopped_x = world.get_location(car).x
    # It stopped before the junction, was held at least 2 s (40 steps),
    # and went on through it.
    assert_true(stopped_at > 0)
    assert_true(stopped_x > 88.1 and stopped_x < 97.6)
    assert_true(held >= 40)
    assert_true(
        world.get_location(car).x > 100 or world.get_location(car).y > 5
    )


def test_forced_and_random_lane_changes() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var forced = _spawn(world, 20, 1.75)
    # Apart, so that the two changes do not meet.
    var random = _spawn(world, 100, 5.25)
    tm.register_vehicles(world, [forced, random])
    _run(tm, world, 60)
    tm.set_force_lane_change(forced, True)
    tm.set_random_left_lane_change_percentage(random, 100)
    _run(tm, world, 100)
    assert_almost_equal(world.get_location(forced).y, 5.25, atol=0.3)
    assert_almost_equal(world.get_location(random).y, 1.75, atol=0.3)


def test_hybrid_mode_teleports_far_vehicles() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var hero = _spawn(world, 250, 5.25, "hero")
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    tm.set_hybrid_physics_mode(True)
    tm.set_hybrid_physics_radius(Length(50))
    # After the first step, physics no longer moves it. Each teleport
    # heads for the next waypoint in 3D, so the car first sinks from its
    # spawn height to the road; after 15 steps it is on the road.
    _run(tm, world, 15)
    assert_almost_equal(world.get_location(car).z, 0.0, atol=1e-3)
    var start = world.get_location(car)
    _run(tm, world, 20)
    assert_false(is_physics_enabled(world, car))
    var body = world.actor(car).body.value
    assert_true(world.physics.world.bodies[body].kind == KINEMATIC)
    # 20 steps of 8.333 m/s times 0.05 s.
    assert_almost_equal(
        world.get_location(car).x,
        start.x + 20 * Float32(30.0 / 3.6 * 0.05),
        atol=1e-3,
    )
    assert_almost_equal(world.get_location(car).y, 1.75, atol=1e-4)
    # The hero comes near: physics again, at the speed it was moving.
    var near = world.get_location(car)
    world.set_location(hero, Vector3(near.x + 10, 5.25, near.z))
    _run(tm, world, 20)
    assert_true(is_physics_enabled(world, car))
    assert_almost_equal(_speed(world, car), 8.333333, atol=0.3)


def test_dormant_vehicle_respawns_near_the_hero() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var hero = _spawn(world, 150, 1.75, "hero")
    var car = _spawn(world, 60, 1.75)
    tm.register_vehicles(world, [car])
    tm.set_respawn_dormant_vehicles(True)
    tm.set_boundaries_respawn_dormant_vehicles(Length(20), Length(20))
    _run(tm, world, 2)
    world.actors[car.value - 1].state = ACTOR_DORMANT
    _ = tm.tick(world)
    var at = world.get_location(car)
    assert_almost_equal(at.x, 110, atol=1e-4)
    assert_almost_equal(at.y, 5.25, atol=1e-4)
    assert_almost_equal(at.z, 0.5, atol=1e-4)
    _ = hero


def test_stuck_vehicle_is_destroyed() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    # A desired speed of zero: CARLA's controller gives a NaN brake, sent
    # as zero, and the car stays.
    tm.set_desired_speed(car, Velocity(0))
    # 2 s for the car to settle on its wheels: a vertical speed over
    # 0.8 m/s also counts as moving.
    _run(tm, world, 40)
    # Idle since long ago, but the last removal was less than 10 s ago.
    var now = tm.alsm.current_time
    tm.alsm.idle_time[car.value] = now - 200.0
    tm.alsm.elapsed_last_actor_destruction = now - 9.0
    _run(tm, world, 1)
    assert_true(world.is_alive(car))
    tm.alsm.elapsed_last_actor_destruction = now - 20.0
    _run(tm, world, 1)
    assert_false(world.is_alive(car))
    assert_equal(len(tm.get_registered_vehicles_ids()), 0)


def test_dead_end_in_osm_mode() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    # 10 m from the lane's end: the first step's path meets it.
    var car = _spawn(world, 285, 1.75)
    tm.register_vehicles(world, [car])
    _run(tm, world, 2)
    assert_false(world.is_alive(car))


def test_unregistered_actors_and_heroes() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    var parked = _spawn(world, 100, 5.25)
    var walker = _spawn(world, 60, 8.5, "", "walker.pedestrian.0015")
    var hero = _spawn(world, 200, 5.25, "hero")
    tm.register_vehicles(world, [car, hero])
    _run(tm, world, 2)
    ref state = tm.shared.simulation_state
    assert_true(state.get_type(parked) == TRAFFIC_VEHICLE)
    assert_true(state.get_type(walker) == TRAFFIC_PEDESTRIAN)
    assert_true(hero.value in tm.alsm.hero_actors)
    _ = world.destroy_actor(parked)
    _ = world.destroy_actor(hero)
    _run(tm, world, 1)
    assert_false(tm.shared.simulation_state.contains_actor(parked))
    assert_false(hero.value in tm.alsm.hero_actors)
    assert_equal(len(tm.get_registered_vehicles_ids()), 1)
    # A registered hero in hybrid mode keeps its physics.
    var hero2 = _spawn(world, 250, -1.75, "hero")
    tm.register_vehicles(world, [hero2])
    tm.set_hybrid_physics_mode(True)
    tm.set_respawn_dormant_vehicles(True)
    _run(tm, world, 2)
    assert_true(is_physics_enabled(world, hero2))
    assert_false(is_physics_enabled(world, car))


def test_vehicle_lights_follow_the_night() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    tm.set_update_vehicle_lights(car, True)
    _run(tm, world, 2)
    assert_true(world.get_light_state(car).has(LIGHT_POSITION | LIGHT_LOW_BEAM))


def test_asynchronous_steps_and_life_cycle() raises:
    var world = _world(straight_town())
    var tm = TrafficManagerLocal(world, 20.0, UInt64(3))
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    # Asynchronous: a world tick does not step it.
    _ = tm.tick(world)
    assert_equal(len(tm.shared.vehicle_id_list), 0)
    tm.step(world)
    assert_equal(len(tm.shared.vehicle_id_list), 1)
    # The same frame again does nothing.
    tm.shared.vehicle_id_list = List[ActorId]()
    tm.step(world)
    assert_equal(len(tm.shared.vehicle_id_list), 0)
    _ = world.tick()
    tm.step(world)
    assert_equal(len(tm.shared.vehicle_id_list), 1)
    var action = tm.get_next_action(car)
    assert_true(action.road_option == ROAD_OPTION_LANE_FOLLOW)
    assert_equal(len(tm.get_action_buffer(car)), 1)
    tm.unregister_vehicles([car])
    assert_equal(len(tm.get_registered_vehicles_ids()), 0)
    assert_true(tm.get_next_action(car).road_option == ROAD_OPTION_VOID)
    tm.register_vehicles(world, [car])
    tm.stop()
    assert_equal(len(tm.get_registered_vehicles_ids()), 0)
    tm.release()
    assert_equal(tm.shared.local_map.size(), 0)
    tm.reset(world)
    assert_equal(tm.shared.local_map.size(), 180)
    tm.set_random_device_seed(9, world)
    assert_equal(tm.seed, 9)


def test_reset_clears_previous_episode_actor_and_junction_state() raises:
    var old_world = _world(straight_town())
    var hero = _spawn(old_world, 20, 1.75, "hero")
    var tm = _manager(old_world)
    tm.register_vehicles(old_world, [hero])
    tm.step(old_world)
    assert_equal(len(tm.alsm.hero_actors), 1)
    # These are indices into the old map and must not survive any reset.
    tm.localization_stage.vehicles_at_junction_entrance[hero.value] = (
        SimpleWaypointIndex(9999),
        SimpleWaypointIndex(10000),
    )
    tm.alsm.has_physics_enabled[hero.value] = False
    tm.shared.track_traffic.set_hero_location(Vector3(20, 1.75, 0.3))
    var new_world = _world(straight_town())
    tm.reset(new_world)
    assert_equal(len(tm.alsm.hero_actors), 0)
    assert_equal(len(tm.alsm.idle_time), 0)
    assert_equal(len(tm.alsm.has_physics_enabled), 0)
    assert_equal(len(tm.localization_stage.vehicles_at_junction_entrance), 0)
    assert_true(tm.shared.track_traffic.get_hero_location() == Vector3(0, 0, 0))
    # No stale hero lookup, even though the new episode has no vehicles.
    tm.step(new_world)
    # Reused IDs get a fresh physics decision rather than a cached one.
    var car = _spawn(new_world, 20, 1.75)
    assert_equal(car, hero)
    tm.register_vehicles(new_world, [car])
    tm.set_hybrid_physics_mode(True)
    tm.step(new_world)
    assert_false(is_physics_enabled(new_world, car))
    tm.localization_stage.vehicles_at_junction_entrance[car.value] = (
        SimpleWaypointIndex(9999),
        SimpleWaypointIndex(10000),
    )
    tm.unregister_vehicles([car])
    assert_equal(len(tm.localization_stage.vehicles_at_junction_entrance), 0)
    tm.alsm.has_physics_enabled[car.value] = False
    tm.alsm.reset(new_world)
    assert_equal(len(tm.alsm.has_physics_enabled), 0)


def test_manager_from_a_cache_and_a_large_vehicle() raises:
    var world = _world(straight_town())
    var local = InMemoryMap()
    local.set_up(world.map)
    var tm = TrafficManagerLocal(world, cache=local.save())
    assert_equal(tm.shared.local_map.size(), 180)
    var empty = TrafficManagerLocal(world, cache=List[UInt8]())
    assert_equal(empty.shared.local_map.size(), 180)
    var clock = TrafficManagerLocal(world)
    _ = clock.seed
    var bus = _spawn(world, 20, 1.75, "", "vehicle.fuso.mitsubishi")
    var truck = _spawn(world, 60, 1.75, "", "vehicle.carlacola.actors")
    var car = _spawn(world, 100, 1.75)
    tm.register_vehicles(world, [bus, truck, car])
    assert_true(bus.value in tm.shared.large_vehicles)
    assert_true(truck.value in tm.shared.large_vehicles)
    assert_false(car.value in tm.shared.large_vehicles)
    var spectator = world.get_spectator()
    tm.register_vehicles(world, [spectator])
    assert_false(spectator.value in tm.shared.large_vehicles)


def test_settings_pass_through() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var a = ActorId(50)
    var b = ActorId(51)
    tm.set_synchronous_mode_time_out(Duration(20, MILLISECOND))
    tm.set_global_percentage_speed_difference(10)
    tm.set_lane_offset(a, Length(0.5))
    tm.set_global_lane_offset(Length(0.25))
    tm.set_large_vehicle_wide_turn(a, False)
    tm.set_global_large_vehicle_wide_turn(False)
    tm.set_collision_detection(a, b, False)
    tm.set_auto_lane_change(a, False)
    tm.set_distance_to_leading_vehicle(a, Length(3))
    tm.set_global_distance_to_leading_vehicle(Length(4))
    tm.set_percentage_ignore_walkers(a, 10)
    tm.set_percentage_ignore_vehicles(a, 20)
    tm.set_percentage_running_light(a, 30)
    tm.set_percentage_running_sign(a, 40)
    tm.set_keep_slow_lane_percentage(a, 50)
    tm.set_random_left_lane_change_percentage(a, 60)
    tm.set_random_right_lane_change_percentage(a, 70)
    tm.set_osm_mode(False)
    tm.set_custom_path(a, [Vector3(1, 2, 3)], True)
    tm.update_upload_path(a, [Vector3(1, 2, 3), Vector3(4, 5, 6)])
    tm.remove_upload_path(a, False)
    tm.set_imported_route(a, [ROAD_OPTION_RIGHT], True)
    tm.update_imported_route(a, [ROAD_OPTION_RIGHT, ROAD_OPTION_RIGHT])
    tm.remove_imported_route(a, False)
    tm.set_max_boundaries(Length(5), Length(500))
    tm.set_boundaries_respawn_dormant_vehicles(Length(1), Length(900))
    ref p = tm.parameters()
    assert_almost_equal(p.get_synchronous_mode_time_out().value, 0.02)
    _ = p.get_vehicle_target_velocity(b, Velocity(10))
    assert_equal(p.get_lane_offset(a).value, 0.5)
    assert_equal(p.get_lane_offset(b).value, 0.25)
    assert_false(p.get_large_vehicle_wide_turn(b))
    assert_false(p.get_collision_detection(a, b))
    assert_false(p.get_auto_lane_change(a))
    assert_equal(p.get_distance_to_leading_vehicle(a).value, 3.0)
    assert_equal(p.get_distance_to_leading_vehicle(b).value, 4.0)
    assert_equal(p.get_percentage_ignore_walkers(a), 10.0)
    assert_equal(p.get_percentage_ignore_vehicles(a), 20.0)
    assert_equal(p.get_percentage_running_light(a), 30.0)
    assert_equal(p.get_percentage_running_sign(a), 40.0)
    assert_equal(p.get_keep_slow_lane_percentage(a), 50.0)
    assert_equal(p.get_random_left_lane_change_percentage(a), 60.0)
    assert_equal(p.get_random_right_lane_change_percentage(a), 70.0)
    assert_false(p.get_osm_mode())
    assert_equal(len(p.get_custom_path(a)), 2)
    assert_false(p.get_upload_path(a))
    assert_equal(len(p.get_imported_route(a)), 2)
    assert_false(p.get_upload_route(a))
    assert_equal(p.get_lower_boundary_respawn_dormant_vehicles().value, 5.0)
    assert_equal(p.get_upper_boundary_respawn_dormant_vehicles().value, 500.0)


def test_actor_set() raises:
    var world = _world(straight_town())
    var set = ActorSet()
    set.insert([ActorId(5), ActorId(2), ActorId(5)])
    assert_equal(set.size(), 2)
    assert_equal(set.state, 1)
    assert_equal(set.get_id_list()[0].value, 2)
    set.remove([ActorId(9)])
    assert_equal(set.state, 2)
    set.destroy(ActorId(9), world)
    assert_equal(set.state, 2)
    assert_true(set.contains(ActorId(5)))
    # Empty lists still count as a change.
    set.insert(List[ActorId]())
    assert_equal(set.state, 3)
    set.remove(List[ActorId]())
    assert_equal(set.state, 4)
    set.clear()
    assert_equal(set.size(), 0)
    with assert_raises(contains="not valid"):
        set.insert([ActorId(-1)])


def test_commands_reach_the_world() raises:
    var world = _world(straight_town())
    var car = _spawn(world, 20, 1.75)
    var control = VehicleControl()
    control.throttle = nan[DType.float32]()
    control.brake = nan[DType.float32]()
    var moved = CarlaTransform(
        Length(30),
        Length(1.75),
        Length(0.3),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )
    var lights = LIGHT_POSITION
    apply_batch(
        world,
        [
            no_command(),
            apply_vehicle_control(car, control),
            apply_transform(car, moved),
            set_vehicle_light_state(car, lights),
        ],
    )
    assert_equal(world.get_control(car).throttle, 0.0)
    assert_equal(world.get_control(car).brake, 0.0)
    assert_equal(world.get_location(car).x, 30.0)
    assert_true(world.get_light_state(car) == lights)
    # A teleport of a car without physics also stops its body.
    set_simulate_physics(world, car, False)
    world.set_target_velocity(car, Vector3(3, 0, 0))
    apply_batch(world, [apply_transform(car, moved)])
    assert_equal(world.get_velocity(car).x, 0.0)
    set_simulate_physics(world, car, True)
    assert_true(is_physics_enabled(world, car))
    # The spectator has no body.
    set_simulate_physics(world, world.get_spectator(), False)
    assert_false(is_physics_enabled(world, world.get_spectator()))
    # A command of no known kind is refused.
    var bad = no_command()
    bad.kind = CommandKind(4)
    with assert_raises(contains="kind is not valid"):
        apply_batch(world, [bad])


def test_alsm_stuck_rules() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    _ = tm.tick(world)
    ref alsm = tm.alsm
    alsm.current_time = 100.0
    alsm.idle_time[car.value] = 0.0
    # Idle 100 s away from a red light: stuck; at a red light: not yet.
    assert_true(alsm.is_vehicle_stuck(car, tm.shared))
    var light = tm.shared.simulation_state.get_tls(car)
    light.tl_state = RED
    light.at_traffic_light = False
    tm.shared.simulation_state.update_traffic_light_state(car, light)
    assert_false(alsm.is_vehicle_stuck(car, tm.shared))
    alsm.current_time = 181.0
    assert_true(alsm.is_vehicle_stuck(car, tm.shared))
    assert_false(alsm.is_vehicle_stuck(ActorId(77), tm.shared))
    alsm.reset(world)
    assert_equal(len(alsm.idle_time), 0)
    var fresh = ALSM()
    assert_equal(fresh.elapsed_last_actor_destruction, 0.0)


def test_alsm_life_cycle_edges() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    # No registered vehicles: a tick notes the others only. The
    # spectator is neither a vehicle nor a walker, so it has no state.
    _ = tm.tick(world)
    assert_equal(len(tm.shared.vehicle_id_list), 0)
    var spectator = world.get_spectator()
    assert_true(spectator.value in tm.alsm.unregistered_actors)
    assert_false(tm.shared.simulation_state.contains_actor(spectator))
    tm.register_vehicles(world, List[ActorId]())
    tm.unregister_vehicles(List[ActorId]())
    # A car seen unregistered, then registered: it leaves the
    # unregistered list.
    var car = _spawn(world, 20, 1.75)
    _ = tm.tick(world)
    assert_true(car.value in tm.alsm.unregistered_actors)
    tm.register_vehicles(world, [car])
    # Respawn on with no hero: the hero's place is the origin. Open Street
    # Map mode off.
    tm.set_respawn_dormant_vehicles(True)
    tm.set_osm_mode(False)
    tm.shared.track_traffic.set_hero_location(Vector3(5, 5, 5))
    _ = tm.tick(world)
    assert_false(car.value in tm.alsm.unregistered_actors)
    assert_true(tm.shared.track_traffic.get_hero_location() == Vector3(0, 0, 0))
    assert_equal(len(tm.shared.vehicle_id_list), 1)
    # A car registered and taken back before any step: nothing to forget.
    var other = _spawn(world, 100, 1.75)
    tm.register_vehicles(world, [other])
    tm.unregister_vehicles([other])
    assert_equal(len(tm.get_registered_vehicles_ids()), 1)
    # The registered car destroyed in the world, with no hero: forgotten.
    _ = world.destroy_actor(car)
    _ = tm.tick(world)
    assert_equal(len(tm.get_registered_vehicles_ids()), 0)
    assert_false(tm.shared.simulation_state.contains_actor(car))


def test_a_step_at_time_zero() raises:
    # Before the first tick the time is zero: no idle time is noted.
    var world = _world(straight_town())
    var tm = _manager(world)
    var car = _spawn(world, 20, 1.75)
    tm.register_vehicles(world, [car])
    tm.step(world)
    assert_equal(tm.alsm.current_time, 0.0)
    assert_false(car.value in tm.alsm.idle_time)
    _ = tm.tick(world)
    assert_true(car.value in tm.alsm.idle_time)


def test_the_longest_idle_vehicle_goes_first() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var first = _spawn(world, 20, 1.75)
    var second = _spawn(world, 60, 1.75)
    tm.register_vehicles(world, [first, second])
    tm.set_desired_speed(first, Velocity(0))
    tm.set_desired_speed(second, Velocity(0))
    _run(tm, world, 40)
    # Both stuck, the second idle longer: it goes, the first stays, since
    # one goes each 10 s at most.
    var now = tm.alsm.current_time
    tm.alsm.idle_time[first.value] = now - 100.0
    tm.alsm.idle_time[second.value] = now - 150.0
    tm.alsm.elapsed_last_actor_destruction = now - 20.0
    _run(tm, world, 1)
    assert_true(world.is_alive(first))
    assert_false(world.is_alive(second))


def test_physics_toggle_stops_and_restores_effective_mass() raises:
    var world = _world(straight_town())
    var car = _spawn(world, 20, 1.75)
    var id = world.actor(car).body.value
    var mass = world.physics.world.bodies[id].mass
    var tensor = world.physics.world.bodies[id].inverse_inertia
    world.set_target_velocity(car, Vector3(3, 0, 0))
    set_simulate_physics(world, car, False)
    assert_equal(world.get_velocity(car).length_sq(), 0)
    assert_equal(world.physics.world.bodies[id].inverse_mass, 0)
    world.add_impulse(car, Vector3(mass, 0, 0))
    assert_equal(world.get_velocity(car).length_sq(), 0)
    set_simulate_physics(world, car, False)
    set_simulate_physics(world, car, True)
    assert_equal(world.physics.world.bodies[id].mass, mass)
    for i in range(9):
        assert_equal(
            world.physics.world.bodies[id].inverse_inertia.elements[i],
            tensor.elements[i],
        )
    world.add_impulse(car, Vector3(mass, 0, 0))
    assert_almost_equal(world.get_velocity(car).x, 1, atol=1e-6)


def test_unregister_a_large_vehicle() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    var bus = _spawn(world, 20, 1.75, "", "vehicle.fuso.mitsubishi")
    tm.register_vehicles(world, [bus])
    assert_true(bus.value in tm.shared.large_vehicles)
    tm.unregister_vehicles([bus])
    assert_false(bus.value in tm.shared.large_vehicles)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
