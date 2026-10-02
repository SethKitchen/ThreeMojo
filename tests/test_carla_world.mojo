# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA world: the registry, spawning, the tick and the snapshot.

The world stands on `assets/carla/town.xodr`, whose road 1 runs east
from the origin with a 3.5 m driving lane and a 2 m sidewalk 0.15 m high
on each side. The expected numbers come from outside this port:

- CARLA's `EpisodeSettings.h` for the settings' defaults.
- Mechanics by hand: a free fall gains 9.8 m/s per second under the
  physics tier's gravity, an impulse of 1000 N s moves the default
  1000 kg car by 1 m/s, and a pose composes as rotate-then-translate.
- The file's lane widths and sidewalk height for where a ray lands.
- This port's own choices where it makes them: the vehicle boxes, and the
  walker's capsule, 1.8 m tall and 0.5 m wide.
"""

from extensions.carla.actor import (
    ACTOR_ACTIVE,
    ACTOR_DORMANT,
    ACTOR_INVALID,
    ACTOR_PENDING_KILL,
    Actor,
    ActorId,
    ActorKind,
    ActorState,
    AttachmentType,
    GREEN,
    NO_ACTOR,
    OTHER_ACTOR,
    RIGID,
    SENSOR_ACTOR,
    SPRING_ARM,
    SPRING_ARM_GHOST,
    TRAFFIC_SIGN_ACTOR,
    VEHICLE_ACTOR,
    WALKER_ACTOR,
    compose,
    no_rotation,
    relative,
    rotation_matrix,
    rotation_of,
    world_obb,
)
from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.physics.vehicle_control import (
    NO_FAILURE,
    VehicleAckermannControl,
    VehicleControl,
)
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.road_info import SignalId
from extensions.carla.sensor import SemanticTag
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.vehicle import (
    BACK_RIGHT_WHEEL,
    BACK_WHEEL,
    DOOR_ALL,
    DOOR_FRONT_LEFT,
    DOOR_HOOD,
    DOOR_TRUNK,
    FRONT_LEFT_WHEEL,
    LIGHTS_ALL,
    LIGHTS_NONE,
    LIGHT_BRAKE,
    LIGHT_LOW_BEAM,
    LIGHT_POSITION,
    LIGHT_SPECIAL1,
    VehicleDoor,
    VehicleLightState,
    VehicleRecord,
    VehicleWheelLocation,
    default_speed_limit,
    vehicle_bounding_box,
    vehicle_physics_control,
    vehicle_semantic_tag,
)
from extensions.carla.physics.simulation import VehicleId, WalkerId
from extensions.carla.walker import (
    BoneTransformDataIn,
    WalkerBoneControlIn,
    WalkerRecord,
)
from extensions.carla.weather import weather_preset
from extensions.carla.world import (
    EpisodeSettings,
    World,
    cut_sign_id,
    surface_tag,
)
from extensions.carla.world_snapshot import (
    ActorSnapshot,
    Timestamp,
    WorldSnapshot,
)
from math.vector3 import Vector3
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    KILOGRAM,
    Length,
    METER,
    Mass,
    SECOND,
    Angle,
    Duration,
    Velocity,
)


def _world() raises -> World:
    var world = World(load_opendrive_file("assets/carla/town.xodr"))
    var settings = EpisodeSettings()
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    return world^


def _pose(x: Float32, y: Float32, z: Float32, yaw: Float32) -> CarlaTransform:
    return CarlaTransform(
        Length(x, METER),
        Length(y, METER),
        Length(z, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)),
    )


def _near(
    v: Vector3, x: Float32, y: Float32, z: Float32, tol: Float64 = 1e-3
) raises:
    assert_almost_equal(v.x, x, atol=tol)
    assert_almost_equal(v.y, y, atol=tol)
    assert_almost_equal(v.z, z, atol=tol)


def _spawn(mut world: World, id: String, t: CarlaTransform) raises -> ActorId:
    var bp = world.blueprints.at(id)
    return world.spawn_actor(bp, t)


def _car(mut world: World, t: CarlaTransform) raises -> ActorId:
    return _spawn(world, "vehicle.lincoln.mkz", t)


# --- the settings -------------------------------------------------------------


def test_settings_defaults_are_carlas() raises:
    var s = EpisodeSettings()
    assert_false(s.synchronous_mode)
    assert_false(s.no_rendering_mode)
    assert_false(Bool(s.fixed_delta_seconds))
    assert_true(s.substepping)
    assert_almost_equal(s.max_substep_delta_time.value, 0.01, atol=1e-9)
    assert_equal(s.max_substeps, 10)
    assert_equal(s.max_culling_distance.value, 0)
    assert_true(s.deterministic_ragdolls)
    assert_equal(s.tile_stream_distance.value, 3000)
    assert_equal(s.actor_active_distance.value, 2000)
    assert_true(s.spectator_as_ego)
    # A step of zero or less is no step, as CARLA's constructor has it.
    var none = EpisodeSettings(True, False, Duration(0, SECOND))
    assert_false(Bool(none.fixed_delta_seconds))
    assert_true(none.synchronous_mode)
    var fixed = EpisodeSettings(True, True, Duration(0.05, SECOND))
    assert_almost_equal(fixed.fixed_delta_seconds.value().value, 0.05)
    assert_true(fixed.no_rendering_mode)
    s.check()


def test_settings_are_checked() raises:
    var s = EpisodeSettings()
    s.fixed_delta_seconds = Duration(-1, SECOND)
    with assert_raises(contains="fixed_delta_seconds"):
        s.check()
    s = EpisodeSettings()
    s.max_substep_delta_time = Duration(0, SECOND)
    with assert_raises(contains="max_substep_delta_time"):
        s.check()
    s = EpisodeSettings()
    s.max_substeps = 0
    with assert_raises(contains="from 1 to 16"):
        s.check()
    s.max_substeps = 17
    with assert_raises(contains="from 1 to 16"):
        s.check()
    s.max_substeps = 16
    s.check()


def test_substeps() raises:
    var s = EpisodeSettings()
    # 0.05 / 0.01 is 5.000000000000001 in binary: five, not six.
    assert_equal(s.substep_count(Duration(0.05, SECOND)), 5)
    assert_equal(s.substep_count(Duration(0.001, SECOND)), 1)
    assert_equal(s.substep_count(Duration(0.25, SECOND)), 10)
    assert_equal(s.substep_count(Duration(0.035, SECOND)), 4)
    s.substepping = False
    assert_equal(s.substep_count(Duration(0.25, SECOND)), 1)


def test_settings_compare_every_field() raises:
    var base = EpisodeSettings(True, False, Duration(0.05, SECOND))
    assert_true(base == base.copy())
    assert_false(base == EpisodeSettings())
    assert_false(EpisodeSettings() == base)
    assert_true(EpisodeSettings() == EpisodeSettings())
    assert_false(base == EpisodeSettings(True, False, Duration(0.1, SECOND)))
    for i in range(11):
        var s = base.copy()
        if i == 0:
            s.synchronous_mode = False
        elif i == 1:
            s.no_rendering_mode = True
        elif i == 2:
            s.substepping = False
        elif i == 3:
            s.max_substep_delta_time = Duration(0.02, SECOND)
        elif i == 4:
            s.max_substeps = 3
        elif i == 5:
            s.max_culling_distance = Length(5, METER)
        elif i == 6:
            s.deterministic_ragdolls = False
        elif i == 7:
            s.tile_stream_distance = Length(1, METER)
        elif i == 8:
            s.actor_active_distance = Length(1, METER)
        elif i == 9:
            s.spectator_as_ego = False
        else:
            s.fixed_delta_seconds = None
        assert_false(s == base, String(i))
    assert_true(String(base).startswith("WorldSettings(synchronous_mode=True"))
    assert_true("fixed_delta_seconds=None" in String(EpisodeSettings()))


# --- the world ------------------------------------------------------------------


def test_world_on_a_map() raises:
    var world = _world()
    # The spectator, light 1001, and the stop, yield, 30 and 40 signs.
    assert_equal(len(world.get_actors()), 6)
    assert_equal(world.get_spectator(), ActorId(1))
    assert_equal(world.actor(ActorId(1)).type_id, "spectator")
    assert_equal(world.actor(ActorId(1)).role_name(), "")
    assert_equal(world.get_blueprint_library().size(), 75)
    assert_equal(world.get_settings().fixed_delta_seconds.value().value, 0.05)
    assert_equal(world.imu_gravity.value, 9.81)
    world.set_weather(weather_preset("HardRainNoon"))
    assert_equal(world.get_weather().precipitation, 100)
    # A spawn point stands 0.5 m above the start of road 1's right lane.
    var found = False
    for p in world.get_spawn_points():
        var d = p.location - Vector3(0, 1.75, 0.5)
        if d.length() < 1e-3:
            found = True
    assert_true(found)
    # One spawn per topology pair: the old 13 plus retained dead ends
    # on road/lane 2/-1, 3/-1, 5/-1, 6/+1 (LHT), and 7/-1.
    assert_equal(len(world.get_spawn_points()), 18)
    var empty = World(load_opendrive("<OpenDRIVE></OpenDRIVE>"))
    assert_equal(len(empty.get_actors()), 1)
    assert_equal(len(empty.get_spawn_points()), 0)
    assert_false(Bool(empty.ground_projection(Vector3(0, 0, 5))))
    # No road, no light and no sign: a car falls through, and a ray from
    # above meets only the car.
    _ = empty.apply_settings(
        EpisodeSettings(True, False, Duration(0.05, SECOND))
    )
    var car = _car(empty, _pose(0, 0, 20, 0))
    empty.freeze_all_traffic_lights(True)
    empty.reset_all_traffic_lights()
    _ = empty.tick()
    assert_true(empty.get_location(car).z < 20)
    var hit = empty.ground_projection(Vector3(0, 0, 40)).value()
    assert_equal(hit.label.value, 14)


def test_actor_ids_are_checked() raises:
    var world = _world()
    assert_false(world.is_alive(ActorId(0)))
    assert_false(world.is_alive(ActorId(99)))
    assert_false(world.is_alive(ActorId(-1)))
    with assert_raises(contains="names no actor"):
        _ = world.actor(ActorId(0))
    with assert_raises(contains="names no actor"):
        _ = world.get_transform(ActorId(7))
    with assert_raises(contains="names no actor"):
        _ = world.actor(ActorId(-3))
    assert_true(NO_ACTOR.is_valid())
    assert_false(ActorId(4294967296).is_valid())


def test_ground_projection_labels() raises:
    var world = _world()
    var road = world.ground_projection(Vector3(20, 1.75, 5)).value()
    _near(road.location, 20, 1.75, 0)
    assert_equal(road.label.value, 1)
    # The sidewalk's top stands 0.15 m up.
    var walk = world.ground_projection(Vector3(20, 4.5, 5)).value()
    assert_almost_equal(walk.location.z, 0.15, atol=0.01)
    assert_equal(walk.label.value, 2)
    assert_false(Bool(world.ground_projection(Vector3(500, 500, 5))))
    var car = _car(world, _pose(30, 1.75, 0.05, 0))
    var hit = world.project_point(
        Vector3(30, 1.75, 5), Vector3(0, 0, -1)
    ).value()
    assert_equal(hit.label.value, 14)
    assert_true(hit.location.z > 1)
    with assert_raises():
        _ = world.project_point(Vector3(0, 0, 5), Vector3(0, 0, 0))
    assert_equal(surface_tag(0).value, 1)
    assert_equal(surface_tag(2).value, 2)
    assert_equal(surface_tag(3).value, 4)
    assert_equal(surface_tag(6).value, 24)
    assert_true(world.destroy_actor(car))


# --- spawning -------------------------------------------------------------------


def test_spawn_a_vehicle() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 0.05, 0))
    assert_equal(car, ActorId(7))
    var a = world.actor(car)
    assert_equal(a.kind.value, VEHICLE_ACTOR.value)
    assert_equal(a.type_id, "vehicle.lincoln.mkz")
    assert_equal(a.role_name(), "autopilot")
    assert_equal(a.attribute("color").value().value, "255,255,255")
    assert_false(Bool(a.attribute("wings")))
    assert_equal(a.semantic_tags[0].value, 14)
    var box = world.get_bounding_box(car)
    _near(box.extent, 2.4, 1.0, 0.75)
    _near(box.location, 0, 0, 0.75)
    _near(world.get_location(car), 20, 1.75, 0.05)
    var physics = world.get_physics_control(car)
    assert_equal(len(physics.wheels), 4)
    _near(physics.wheels[0].offset, 1.6, -0.85, 0.3)
    _near(physics.wheels[3].offset, -1.6, 0.85, 0.3)
    assert_equal(len(world.filter_actors("vehicle.*")), 1)
    assert_equal(len(world.get_actors()), 7)
    # A second car in the same place meets the first.
    with assert_raises(contains="collision at spawn position"):
        _ = _car(world, _pose(21, 1.75, 0.05, 0))
    var bp = world.blueprints.at("vehicle.lincoln.mkz")
    assert_false(Bool(world.try_spawn_actor(bp, _pose(21, 1.75, 0.05, 0))))
    assert_true(Bool(world.try_spawn_actor(bp, _pose(40, 1.75, 0.05, 0))))


def test_spawn_is_checked() raises:
    var world = _world()
    var library = world.get_blueprint_library()
    var car = _car(world, _pose(20, 1.75, 0.05, 0))
    var foreign = library.at("sensor.camera.rgb")
    foreign.id = "sensor.camera.sonar"
    with assert_raises(contains="not in the library"):
        _ = world.spawn_actor(foreign, _pose(0, 0, 0, 0))
    var camera = library.at("sensor.camera.rgb")
    with assert_raises(contains="Attachment type is not valid"):
        _ = world.spawn_actor(camera, _pose(0, 0, 0, 0), car, AttachmentType(3))
    with assert_raises(contains="names no actor"):
        _ = world.spawn_actor(camera, _pose(0, 0, 0, 0), ActorId(50))
    with assert_raises(contains="cannot have a parent"):
        _ = world.spawn_actor(
            library.at("walker.pedestrian.0015"), _pose(0, 0, 0, 0), car
        )
    world.blueprints.blueprints.append(library.at("sensor.camera.rgb"))
    world.blueprints.blueprints[
        len(world.blueprints.blueprints) - 1
    ].id = "traffic.stop"
    with assert_raises(contains="cannot be spawned: traffic.stop"):
        _ = _spawn(world, "traffic.stop", _pose(0, 0, 0, 0))
    assert_true(RIGID.is_valid())
    assert_true(SPRING_ARM.is_valid())
    assert_true(SPRING_ARM_GHOST.is_valid())
    assert_false(AttachmentType(-1).is_valid())


def test_spawn_other_actors() raises:
    var world = _world()
    var prop = _spawn(world, "static.prop.mesh", _pose(5, 5, 0, 0))
    assert_equal(world.actor(prop).kind.value, OTHER_ACTOR.value)
    assert_equal(world.actor(prop).semantic_tags[0].value, 20)
    var empty = _spawn(world, "util.actor.empty", _pose(0, 0, 0, 0))
    assert_equal(len(world.actor(empty).semantic_tags), 0)
    var ai = _spawn(world, "controller.ai.walker", _pose(0, 0, 0, 0))
    assert_equal(world.actor(ai).kind.value, OTHER_ACTOR.value)
    var lidar = _spawn(world, "sensor.lidar.ray_cast", _pose(1, 2, 3, 0))
    assert_equal(world.actor(lidar).kind.value, SENSOR_ACTOR.value)
    _near(world.get_velocity(lidar), 0, 0, 0)
    _near(world.get_angular_velocity(lidar), 0, 0, 0)
    with assert_raises(contains="no physics body"):
        world.set_target_velocity(lidar, Vector3(1, 0, 0))


def test_attach_a_sensor() raises:
    var world = _world()
    var car = _car(world, _pose(30, 1.75, 0.05, 0))
    var bp = world.blueprints.at("sensor.camera.rgb")
    var camera = world.spawn_actor(bp, _pose(1, 0, 2, 0), car, SPRING_ARM)
    assert_equal(world.actor(camera).parent, car)
    assert_equal(world.actor(camera).attachment.value, SPRING_ARM.value)
    _near(world.get_location(camera), 31, 1.75, 2.05)
    # Turned a quarter to the right, forward is plus y.
    world.set_transform(car, _pose(30, 1.75, 0.05, 90))
    _near(world.get_location(camera), 30, 2.75, 2.05)
    assert_almost_equal(world.get_transform(camera).rotation.yaw, 90, atol=1e-3)
    # Placing the child in the world keeps it on its parent.
    world.set_location(camera, Vector3(30, 1.75, 3.05))
    _near(world.actor(camera).local_transform.location, 0, 0, 3)
    world.set_transform(car, _pose(40, 1.75, 0.05, 90))
    _near(world.get_location(camera), 40, 1.75, 3.05)
    # With the parent gone the child stays where it was.
    assert_true(world.destroy_actor(car))
    assert_equal(world.actor(camera).parent, NO_ACTOR)
    _near(world.get_location(camera), 40, 1.75, 3.05)
    world.set_location(camera, Vector3(1, 2, 3))
    _near(world.get_location(camera), 1, 2, 3)


def test_destroy() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 0.05, 0))
    var body = world.actor(car).body
    assert_true(world.destroy_actor(car))
    assert_false(world.is_alive(car))
    assert_false(world.destroy_actor(car))
    with assert_raises(contains="destroyed"):
        _ = world.get_transform(car)
    assert_equal(len(world.filter_actors("vehicle.*")), 0)
    assert_equal(len(world.get_actors()), 6)
    assert_equal(len(world.get_vehicles_light_states()), 0)
    assert_equal(world.actors[car.value - 1].state.value, ACTOR_INVALID.value)
    # The body waits far below, with no collisions, tick after tick.
    ref parked = world.physics.world.bodies[body.value]
    assert_false(parked.collides)
    _ = world.tick()
    _ = world.tick()
    assert_equal(world.physics.world.bodies[body.value].position.z, -10000)
    assert_false(world.destroy_actor(world.get_spectator()))
    # A light and a sign stay.
    assert_false(world.destroy_actor(ActorId(2)))
    assert_false(world.destroy_actor(ActorId(3)))
    # A spot freed by a destroyed car takes a new one.
    _ = _car(world, _pose(20, 1.75, 0.05, 0))
    var walker = _spawn(world, "walker.pedestrian.0020", _pose(20, 4.5, 1.2, 0))
    assert_true(world.destroy_actor(walker))
    # A sensor has no body to park.
    var lidar = _spawn(world, "sensor.lidar.ray_cast", _pose(0, 0, 2, 0))
    assert_true(world.destroy_actor(lidar))
    _ = world.tick()
    assert_equal(len(world.get_snapshot().actors), 7)


# --- motion -----------------------------------------------------------------------


def test_free_fall_and_acceleration() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 20, 0))
    # Not yet in a snapshot.
    _near(world.get_acceleration(car), 0, 0, 0)
    _ = world.tick()
    # Gravity alone: 0.49 m/s down after 0.05 s, so 9.8 m/s^2.
    _near(world.get_velocity(car), 0, 0, -0.49, 1e-3)
    _near(world.get_acceleration(car), 0, 0, -9.8, 1e-2)
    var snap = world.get_snapshot().find(car).value().copy()
    _near(snap.acceleration, 0, 0, -9.8, 1e-2)
    _near(snap.velocity, 0, 0, -0.49, 1e-3)
    # The spectator has no body.
    _near(world.get_snapshot().find(ActorId(1)).value().acceleration, 0, 0, 0)


def test_body_pushes() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 20, 0))
    world.set_target_velocity(car, Vector3(3, 0, 0))
    _near(world.get_velocity(car), 3, 0, 0)
    # 1000 N s on the default 1000 kg car.
    world.add_impulse(car, Vector3(1000, 0, 0))
    _near(world.get_velocity(car), 4, 0, 0)
    world.set_target_angular_velocity(car, Vector3(0, 0, 90))
    _near(world.get_angular_velocity(car), 0, 0, 90, 1e-3)
    var body = world.actor(car).body.value
    world.add_force(car, Vector3(0, 500, 0))
    _near(world.physics.world.bodies[body].force, 0, 500, 0)
    world.add_torque(car, Vector3(0, 0, 7))
    _near(world.physics.world.bodies[body].torque, 0, 0, 7)
    var spin = (
        world.physics.world.bodies[body]
        .world_inverse_inertia()
        .transform(Vector3(0, 0, 100))
    )
    var before = world.physics.world.bodies[body].angular_velocity
    world.add_angular_impulse(car, Vector3(0, 0, 100))
    _near(
        world.physics.world.bodies[body].angular_velocity,
        before.x + spin.x,
        before.y + spin.y,
        before.z + spin.z,
    )
    world.set_enable_gravity(car, False)
    assert_equal(world.physics.world.bodies[body].gravity_scale, 0)
    world.set_enable_gravity(car, True)
    assert_equal(world.physics.world.bodies[body].gravity_scale, 1)
    world.set_location(car, Vector3(50, 1.75, 20))
    _near(world.get_location(car), 50, 1.75, 20)


# --- vehicles ----------------------------------------------------------------------


def test_vehicle_controls() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 0.05, 0))
    var control = VehicleControl()
    control.throttle = 0.5
    world.apply_control(car, control)
    assert_equal(world.get_control(car).throttle, 0.5)
    var target = VehicleAckermannControl()
    world.apply_ackermann_control(car, target)
    var gains = world.get_ackermann_controller_settings(car)
    gains.speed_kp = 0.7
    world.apply_ackermann_controller_settings(car, gains)
    assert_equal(world.get_ackermann_controller_settings(car).speed_kp, 0.7)
    var physics = world.get_physics_control(car)
    physics.mass = Mass(2000, KILOGRAM)
    world.apply_physics_control(car, physics^)
    assert_equal(world.get_physics_control(car).mass.value, 2000)
    _ = world.tick()
    assert_equal(world.get_failure_state(car).value, NO_FAILURE.value)
    assert_equal(len(world.get_telemetry_data(car).wheels), 4)
    var data = world.get_snapshot().find(car).value().vehicle.value()
    assert_equal(data.control.throttle, world.get_control(car).throttle)
    assert_equal(data.traffic_light_state.value, GREEN.value)
    assert_false(data.has_traffic_light)
    assert_almost_equal(data.speed_limit.to(KILOMETER_PER_HOUR), 30, atol=1e-4)
    assert_equal(world.get_wheel_steer_angle(car, FRONT_LEFT_WHEEL).value, 0)
    assert_equal(world.get_wheel_steer_angle(car, BACK_RIGHT_WHEEL).value, 0)
    with assert_raises(contains="no such wheel"):
        _ = world.get_wheel_steer_angle(car, VehicleWheelLocation(5))
    # A two-wheeler has no wheel 3.
    _ = world.physics.vehicles[0].wheels.pop()
    with assert_raises(contains="no such wheel"):
        _ = world.get_wheel_steer_angle(car, BACK_RIGHT_WHEEL)
    with assert_raises(contains="not a vehicle"):
        world.apply_control(ActorId(1), control)
    with assert_raises(contains="not a walker"):
        world.apply_walker_control(car, WalkerControl())


def test_vehicle_lights_and_doors() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 0.05, 0))
    assert_equal(world.get_light_state(car).value, LIGHTS_NONE.value)
    world.set_light_state(car, LIGHT_POSITION | LIGHT_LOW_BEAM)
    assert_true(world.get_light_state(car).has(LIGHT_LOW_BEAM))
    assert_false(world.get_light_state(car).has(LIGHT_BRAKE))
    with assert_raises(contains="light state is not valid"):
        world.set_light_state(car, VehicleLightState(-1))
    var states = world.get_vehicles_light_states()
    assert_equal(len(states), 1)
    assert_equal(states[0][0], car)
    assert_equal(states[0][1].value, 3)
    world.open_door(car, DOOR_FRONT_LEFT)
    assert_true(world.is_door_open(car, DOOR_FRONT_LEFT))
    assert_false(world.is_door_open(car, DOOR_HOOD))
    world.open_door(car, DOOR_ALL)
    assert_true(world.is_door_open(car, DOOR_TRUNK))
    world.close_door(car, DOOR_ALL)
    assert_false(world.is_door_open(car, DOOR_TRUNK))
    with assert_raises(contains="must name one door"):
        _ = world.is_door_open(car, DOOR_ALL)
    with assert_raises(contains="door is not valid"):
        world.open_door(car, VehicleDoor(7))
    # The Carla Cola truck has no dynamic doors.
    var truck = _spawn(
        world, "vehicle.carlacola.actors", _pose(60, -1.75, 0.05, 180)
    )
    world.open_door(truck, DOOR_FRONT_LEFT)
    world.open_door(truck, DOOR_ALL)
    assert_false(world.is_door_open(truck, DOOR_FRONT_LEFT))
    assert_equal(world.get_bounding_box(truck).extent.x, 4.0)
    assert_equal(world.actor(truck).semantic_tags[0].value, 15)


def test_constant_velocity_and_sticky_control() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 0.05, 90))
    world.enable_constant_velocity(car, Vector3(5, 0, 0))
    _ = world.tick()
    # Forward is plus y at a yaw of 90.
    assert_true(world.get_velocity(car).y > 4)
    world.disable_constant_velocity(car)
    assert_false(Bool(world.vehicles[0].constant_velocity))
    var bp = world.blueprints.at("vehicle.mini.cooper")
    bp.set_attribute("sticky_control", "false")
    var loose = world.spawn_actor(bp, _pose(40, -1.75, 0.05, 180))
    var control = VehicleControl()
    control.throttle = 1
    world.apply_control(loose, control)
    world.apply_control(car, control)
    _ = world.tick()
    assert_equal(world.get_control(loose).throttle, 0)
    assert_equal(world.get_control(car).throttle, 1)
    assert_false(world.is_at_traffic_light(car))
    assert_false(Bool(world.get_traffic_light(car)))
    assert_equal(world.get_traffic_light_state(car).value, GREEN.value)
    assert_almost_equal(
        world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 30, atol=1e-4
    )


# --- walkers ------------------------------------------------------------------------


def test_walker() raises:
    var world = _world()
    var walker = _spawn(
        world, "walker.pedestrian.0020", _pose(20, 4.5, 1.2, 30)
    )
    var a = world.actor(walker)
    assert_equal(a.kind.value, WALKER_ACTOR.value)
    assert_equal(a.semantic_tags[0].value, 12)
    assert_equal(a.role_name(), "pedestrian")
    # The capsule is 1.8 m tall and 0.5 m wide about its middle.
    _near(world.get_bounding_box(walker).extent, 0.25, 0.25, 0.9)
    assert_almost_equal(world.get_transform(walker).rotation.yaw, 30, atol=1e-3)
    with assert_raises(contains="collision at spawn position"):
        _ = _spawn(world, "walker.pedestrian.0021", _pose(20.2, 4.5, 1.2, 0))
    var control = WalkerControl()
    control.direction = Vector3(1, 0, 0)
    control.speed = Velocity(1.4)
    world.apply_walker_control(walker, control)
    assert_equal(world.get_walker_control(walker).speed.value, 1.4)
    for _ in range(40):
        _ = world.tick()
    var at = world.get_location(walker)
    assert_true(at.x > 20.5)
    assert_almost_equal(at.y, 4.5, atol=0.05)
    var snap = world.get_snapshot().find(walker).value().copy()
    assert_equal(snap.walker_control.value().speed.value, 1.4)
    assert_false(Bool(snap.vehicle))


def test_walker_bones() raises:
    var world = _world()
    var walker = _spawn(world, "walker.pedestrian.0020", _pose(20, 4.5, 1.2, 0))
    assert_equal(len(world.get_bones_transform(walker).bone_transforms), 0)
    world.set_bones_transform(
        walker, WalkerBoneControlIn(List[BoneTransformDataIn]())
    )
    var bones = WalkerBoneControlIn(
        [
            BoneTransformDataIn("hand", _pose(0, 0, 1, 0)),
            BoneTransformDataIn("head", _pose(0, 0, 1.7, 0)),
        ]
    )
    world.set_bones_transform(walker, bones)
    world.set_bones_transform(
        walker,
        WalkerBoneControlIn([BoneTransformDataIn("hand", _pose(0.5, 0, 1, 0))]),
    )
    var out = world.get_bones_transform(walker)
    assert_equal(len(out.bone_transforms), 2)
    assert_equal(out.bone_transforms[0].bone_name, "hand")
    _near(out.bone_transforms[0].relative.location, 0.5, 0, 1)
    _near(out.bone_transforms[1].world.location, 20, 4.5, 2.9)
    world.blend_pose(walker, 0.5)
    assert_equal(world.walkers[0].pose_blend, 0.5)
    with assert_raises(contains="zero to one"):
        world.blend_pose(walker, 1.5)
    with assert_raises(contains="zero to one"):
        world.blend_pose(walker, -0.5)


# --- the tick and the snapshot -------------------------------------------------------


def test_tick_and_snapshot() raises:
    var bare = World(load_opendrive_file("assets/carla/town.xodr"))
    with assert_raises(contains="needs fixed_delta_seconds"):
        _ = bare.tick()
    var world = _world()
    var first = world.get_snapshot()
    assert_equal(first.frame(), 0)
    assert_equal(first.size(), 6)
    for i in range(1, 5):
        assert_equal(world.tick(), i)
    var snap = world.get_snapshot()
    assert_equal(snap.frame(), 4)
    assert_equal(snap.id, 1)
    assert_almost_equal(snap.timestamp.elapsed_seconds, 0.2, atol=1e-6)
    assert_almost_equal(snap.timestamp.delta_seconds, 0.05, atol=1e-7)
    assert_almost_equal(snap.timestamp.elapsed().value, 0.2, atol=1e-6)
    assert_almost_equal(snap.timestamp.delta().value, 0.05, atol=1e-7)
    assert_true(snap.timestamp.platform_timestamp > 0)
    assert_true(snap.contains(ActorId(2)))
    assert_false(snap.contains(ActorId(40)))
    assert_false(Bool(snap.find(ActorId(40))))
    assert_true(snap == world.get_snapshot())
    assert_false(snap == first)
    # Light 1001 and the stop sign 1002.
    var light = snap.find(ActorId(2)).value().copy()
    assert_equal(light.traffic_light.value().sign_id, "1001")
    assert_equal(light.actor_state.value, ACTOR_ACTIVE.value)
    assert_equal(snap.find(ActorId(3)).value().sign_id, "1002")
    assert_equal(snap.find(ActorId(1)).value().sign_id, "")
    assert_true(String(snap.timestamp).startswith("Timestamp(frame=4,"))
    assert_equal(
        cut_sign_id("1234567890123456789012345678901234"),
        "12345678901234567890123456789012",
    )


def _check_cut_sign_id(id: String, expected: String) raises:
    var cut = cut_sign_id(id)
    assert_equal(cut, expected)
    assert_true(cut.byte_length() <= 32)
    assert_equal(cut_sign_id(cut), cut)


def test_cut_sign_id_preserves_short_and_exact_utf8() raises:
    _check_cut_sign_id("", "")
    _check_cut_sign_id("short", "short")
    _check_cut_sign_id("é中😀", "é中😀")
    var codepoints: List[String] = ["x", "é", "中", "😀"]
    for codepoint in codepoints:
        var width = codepoint.byte_length()
        for size in range(28, 33):
            var id = String("a") * (size - width) + codepoint
            _check_cut_sign_id(id, id)
        var exact = codepoint * (32 // width)
        _check_cut_sign_id(exact, exact)


def test_cut_sign_id_truncates_only_at_utf8_boundaries() raises:
    # A one-, two-, three- or four-byte codepoint starts on either side
    # of byte 32, including every possible partial-codepoint boundary.
    var codepoints: List[String] = ["x", "é", "中", "😀"]
    for codepoint in codepoints:
        var width = codepoint.byte_length()
        for start in range(28, 34):
            var prefix = String("a") * start
            var id = prefix + codepoint + String("z") * 40
            var expected = String("a") * min(start, 32)
            if start + width <= 32:
                expected += codepoint + String("z") * (32 - start - width)
            _check_cut_sign_id(id, expected)
        # The kept prefix itself can contain multibyte codepoints.
        var repeated = codepoint * 40
        _check_cut_sign_id(repeated, codepoint * (32 // width))
    _check_cut_sign_id(String("a") * 31 + "é", String("a") * 31)
    _check_cut_sign_id(String("a") * 30 + "中", String("a") * 30)
    _check_cut_sign_id(String("a") * 29 + "😀", String("a") * 29)


def test_initial_snapshot_accepts_utf8_light_id() raises:
    var full = String("a") * 31 + "é"
    var xml = Path("assets/carla/town.xodr").read_text()
    xml = xml.replace('"1001"', '"' + full + '"')
    var world = World(load_opendrive(xml))
    var light = world.get_snapshot().find(ActorId(2)).value().copy()
    assert_equal(light.traffic_light.value().sign_id, String("a") * 31)
    assert_equal(world.get_opendrive_id(ActorId(2)).value, full)
    assert_equal(
        world.get_traffic_light_from_opendrive(SignalId(full)).value().value,
        2,
    )


def test_initial_snapshot_accepts_utf8_sign_id() raises:
    var full = String("a") * 29 + "😀"
    var xml = Path("assets/carla/town.xodr").read_text()
    xml = xml.replace('"1002"', '"' + full + '"')
    var world = World(load_opendrive(xml))
    # Signals are ordered by id; replacing an id can change actor numbers.
    var found = False
    for actor in world.actors:
        if actor.kind == TRAFFIC_SIGN_ACTOR:
            if world.get_opendrive_id(actor.id).value == full:
                assert_equal(
                    world.get_snapshot().find(actor.id).value().sign_id,
                    String("a") * 29,
                )
                found = True
    assert_true(found)


def test_tick_snapshot_keeps_utf8_prefix_for_lights_and_signs() raises:
    var world = _world()
    var codepoints: List[String] = ["x", "é", "中", "😀"]
    for codepoint in codepoints:
        var width = codepoint.byte_length()
        for start in range(28, 34):
            var full = String("a") * start + codepoint + "tail"
            var expected = String("a") * min(start, 32)
            if start + width <= 32:
                expected += (
                    codepoint + String("tail")[byte = 0 : 32 - start - width]
                )
            world.traffic_lights.lights[0].sign_id = SignalId(full)
            world.signs[0].sign_id = SignalId(full)
            _ = world.tick()
            var snapshot = world.get_snapshot()
            var light = snapshot.find(ActorId(2)).value().copy()
            var sign = snapshot.find(ActorId(3)).value().copy()
            assert_equal(light.traffic_light.value().sign_id, expected)
            assert_equal(sign.sign_id, expected)
            assert_equal(world.get_opendrive_id(ActorId(2)).value, full)
            assert_equal(world.get_opendrive_id(ActorId(3)).value, full)


# --- the records on their own -----------------------------------------------------


def test_actor_records() raises:
    with assert_raises(contains="id or kind is not valid"):
        _ = Actor(
            ActorId(-1),
            "x",
            OTHER_ACTOR,
            List[ActorAttributeValue](),
            _pose(0, 0, 0, 0),
            BoundingBox(Vector3(0, 0, 0)),
            List[SemanticTag](),
        )
    with assert_raises(contains="id or kind is not valid"):
        _ = Actor(
            ActorId(1),
            "x",
            ActorKind(6),
            List[ActorAttributeValue](),
            _pose(0, 0, 0, 0),
            BoundingBox(Vector3(0, 0, 0)),
            List[SemanticTag](),
        )
    var a = Actor(
        ActorId(1),
        "x",
        OTHER_ACTOR,
        List[ActorAttributeValue](),
        _pose(0, 0, 0, 0),
        BoundingBox(Vector3(0, 0, 0)),
        List[SemanticTag](),
    )
    a.state = ACTOR_DORMANT
    assert_true(a.is_alive())
    a.state = ACTOR_PENDING_KILL
    assert_false(a.is_alive())
    assert_true(ACTOR_PENDING_KILL.is_valid())
    assert_false(ActorState(4).is_valid())
    assert_false(ActorKind(-1).is_valid())


def test_poses_compose() raises:
    # A parent at (10, 0, 0) turned 90 degrees: its forward is plus y.
    var parent = _pose(10, 0, 0, 90)
    var child = compose(parent, _pose(2, 1, 0, 30))
    # Forward 2 goes to plus y, right 1 goes to minus x.
    _near(child.location, 9, 2, 0)
    assert_almost_equal(child.rotation.yaw, 120, atol=1e-3)
    var back = relative(parent, child)
    _near(back.location, 2, 1, 0)
    assert_almost_equal(back.rotation.yaw, 30, atol=1e-3)
    # A pitch and a roll come back out of the matrix.
    var tilted = CarlaRotation(
        Angle(20, DEGREE), Angle(-40, DEGREE), Angle(10, DEGREE)
    )
    var r = rotation_of(rotation_matrix(tilted))
    assert_almost_equal(r.pitch, 20, atol=1e-3)
    assert_almost_equal(r.yaw, -40, atol=1e-3)
    assert_almost_equal(r.roll, 10, atol=1e-3)
    var box = world_obb(parent, BoundingBox(Vector3(1, 0, 0), Vector3(1, 2, 3)))
    _near(box.center, 10, 1, 0)
    assert_equal(no_rotation().yaw, 0)


def test_vehicle_parts() raises:
    var lights = LIGHT_POSITION | LIGHT_SPECIAL1
    assert_equal(lights.value, 0x201)
    assert_equal((lights & LIGHT_SPECIAL1).value, 0x200)
    assert_true(LIGHTS_ALL.has(LIGHT_BRAKE))
    assert_true(LIGHTS_ALL.is_valid())
    assert_false(VehicleLightState(0x100000000).is_valid())
    assert_true(DOOR_ALL.is_valid())
    assert_false(VehicleDoor(-1).is_valid())
    assert_true(BACK_RIGHT_WHEEL.is_valid())
    assert_equal(FRONT_LEFT_WHEEL.value, 0)
    assert_equal(BACK_WHEEL.value, 1)
    assert_false(VehicleWheelLocation(4).is_valid())
    assert_almost_equal(default_speed_limit().value, 30 / 3.6, atol=1e-5)
    _near(vehicle_bounding_box("van").extent, 2.9, 1.1, 1.2)
    _near(vehicle_bounding_box("bus").extent, 5.5, 1.3, 1.6)
    _near(vehicle_bounding_box("bicycle").extent, 2.4, 1.0, 0.75)
    assert_equal(vehicle_semantic_tag("bus").value, 16)
    assert_equal(vehicle_semantic_tag("van").value, 14)
    # A truck's box: wheels 0.8 m in from its 4 m half length.
    var p = vehicle_physics_control(vehicle_bounding_box("truck"))
    _near(p.wheels[1].offset, 3.2, 1.15, 0.3)
    assert_false(p.wheels[2].affected_by_steering)
    assert_true(p.wheels[2].affected_by_handbrake)
    var record = VehicleRecord(VehicleId(0), False, True)
    assert_equal(len(record.doors_open), 0)
    assert_false(record.is_door_open(DOOR_HOOD))
    with assert_raises(contains="must name one door"):
        _ = record.is_door_open(VehicleDoor(9))
    var walker = WalkerRecord(WalkerId(0))
    assert_equal(walker.pose_blend, 0)
    assert_equal(len(walker.bones), 0)
    var stamp = Timestamp(3, 1.5, 0.5, 0)
    assert_true(stamp == Timestamp(3, 0, 0, 1))
    assert_false(stamp == Timestamp(4, 1.5, 0.5, 0))
    var empty = WorldSnapshot(1, stamp)
    assert_equal(empty.size(), 0)
    assert_false(empty.contains(ActorId(1)))
    assert_false(Bool(empty.find(ActorId(1))))
    var one = ActorSnapshot(
        ActorId(1),
        ACTOR_ACTIVE,
        _pose(0, 0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
    )
    empty.actors.append(one^)
    assert_true(empty.contains(ActorId(1)))
    assert_false(empty == WorldSnapshot(2, stamp))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
