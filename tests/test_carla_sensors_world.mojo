# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's sensors in a world: rays against its colliders, collisions,
lane invasions, obstacles, the V2X channel and the sensor manager.

The world stands on `assets/carla/town.xodr`. Road 1 runs east from the
origin: in CARLA's frame its right driving lane covers y from 0 to 3.5 m
and its left lane y from -3.5 to 0, with a solid yellow center mark, and a
2 m sidewalk 0.15 m high lies on each side. A car's box is 4.8 m long,
2 m wide and 1.5 m high, standing on its origin. The expected numbers are
worked by hand from that geometry, or come from the C++ and Python models
named in `test_carla_sensors.mojo`.
"""

from extensions.carla.actor import (
    ActorId,
    NO_ACTOR,
)
from extensions.carla.blueprint import ActorBlueprint

from extensions.carla.collision import (
    CollisionMeasurement,
    CollisionSensor,
)
from extensions.carla.lane_invasion import (
    LaneInvasionSensor,
    box_corners,
)
from extensions.carla.obstacle import (
    ObstacleDescription,
    detect_obstacle,
    sweep_sphere,
)
from extensions.carla.opendrive import (
    load_opendrive,
    load_opendrive_file,
)
from extensions.carla.physics.body import (
    BodyId,
    DYNAMIC,
    RigidBody,
    STATIC,
)
from extensions.carla.physics.shape import Shape
from extensions.carla.road_info import (
    MARKING_YELLOW,
    SOLID,
)
from extensions.carla.sensor import (
    CAR,
    PEDESTRIAN,
    ROAD,
    SIDEWALK,
    SemanticTag,
    UNLABELED,
)
from extensions.carla.sensor_data import (
    ByteWriter,
    collision_data,
    obstacle_data,
    pack_actor,
)
from extensions.carla.sensor_manager import (
    SensorMeasurement,
    COLLISION,
    CUSTOM_V2X,
    DEPTH_SENSOR,
    DVS_SENSOR,
    GNSS,
    IMU_KIND,
    LANE_INVASION,
    OBSTACLE,
    RADAR,
    SensorKind,
    SensorManager,
    V2X,
    sensor_kind_of,
    sensor_type_of,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.sensor_rays import (
    WorldRays,
    surface_tag_of_body,
)
from extensions.carla.transform import (
    CarlaRotation,
    CarlaTransform,
)
from extensions.carla.v2x import (
    CONTAINER_NOTHING,
    CONTAINER_RSU,
    CONTAINER_VEHICLE,
    CaService,
    CamNoise,
    HIGHWAY,
    LOS,
    NLOS_BUILDING,
    NLOS_VEHICLE,
    PathLossModel,
    PropagationParams,
    STATION_PASSENGER_CAR,
    STATION_PEDESTRIAN,
    STATION_ROAD_SIDE_UNIT,
    WINNER,
    path_state,
    simulate_channel,
)
from extensions.carla.vehicle import (
    LIGHT_FOG,
    LIGHT_LOW_BEAM,
)
from extensions.carla.world import (
    EpisodeSettings,
    World,
)
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Duration64,
    DEGREE,
    KILOGRAM,
    METER,
    SECOND,
    Angle,
    Duration,
    Length,
    Mass,
)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _pose(
    x: Float32, y: Float32, z: Float32, yaw: Float32 = 0, pitch: Float32 = 0
) -> CarlaTransform:
    return CarlaTransform(
        _m(x),
        _m(y),
        _m(z),
        CarlaRotation(
            Angle(pitch, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)
        ),
    )


def _near(
    a: Vector3, x: Float32, y: Float32, z: Float32, tol: Float64 = 1e-4
) raises:
    assert_almost_equal(a.x, x, atol=tol)
    assert_almost_equal(a.y, y, atol=tol)
    assert_almost_equal(a.z, z, atol=tol)


def _world() raises -> World:
    var world = World(load_opendrive_file("assets/carla/town.xodr"))
    var settings = EpisodeSettings()
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    return world^


def _car(
    mut world: World, x: Float32, y: Float32, z: Float32 = 0
) raises -> ActorId:
    return world.spawn_actor(
        world.blueprints.at("vehicle.lincoln.mkz"), _pose(x, y, z)
    )


def _wreck(mut world: World) raises:
    # A destroyed car: the loops over the actors pass over it.
    var gone = _car(world, 55, -30)
    _ = world.destroy_actor(gone)


def _sensor(
    mut world: World,
    id: String,
    t: CarlaTransform,
    parent: ActorId = NO_ACTOR,
) raises -> ActorId:
    return world.spawn_actor(world.blueprints.at(id), t, parent)


def _hex(bytes: List[UInt8]) -> String:
    comptime digits = "0123456789abcdef"
    var out = String()
    for b in bytes:
        out += digits[byte=Int(b >> 4)]
        out += digits[byte=Int(b & 15)]
    return out^


# --- rays ------------------------------------------------------------------------


def test_world_rays_name_what_they_meet() raises:
    var world = _world()
    _wreck(world)
    var car = _car(world, 20, 1.75)
    world.set_target_velocity(car, Vector3(3, 0, 0))
    var rays = WorldRays(Pointer(to=world))
    # Down onto the right lane, 5 m below.
    var road = rays.cast_ray(Vector3(10, 1.75, 5), Vector3(0, 0, -2), _m(100))
    assert_true(road.hit)
    assert_almost_equal(road.distance.value, 5, atol=1e-4)
    _near(road.point, 10, 1.75, 0)
    _near(road.normal, 0, 0, 1)
    assert_equal(road.actor, NO_ACTOR)
    assert_equal(road.tag, ROAD)
    # The second hit on that surface reads its tag from the cache.
    var again = rays.cast_ray(Vector3(11, 1.75, 5), Vector3(0, 0, -1), _m(100))
    assert_equal(again.tag, ROAD)
    # Along the lane to the car's back, 2.4 m before its center.
    var back = rays.cast_ray(Vector3(10, 1.75, 0.75), Vector3(1, 0, 0), _m(100))
    assert_almost_equal(back.distance.value, 7.6, atol=1e-3)
    assert_equal(back.actor, car)
    assert_equal(back.tag, CAR)
    _near(back.normal, -1, 0, 0)
    _near(back.actor_velocity, 3, 0, 0)
    _near(back.point_velocity, 3, 0, 0)
    assert_false(
        rays.cast_ray(Vector3(10, 1.75, 5), Vector3(0, 0, 1), _m(100)).hit
    )
    with assert_raises(contains="needs a direction"):
        _ = rays.cast_ray(Vector3(10, 1.75, 5), Vector3(0, 0, 0), _m(100))
    var body = world.actor(car).body
    assert_equal(rays.actor_of_body(body), car)
    assert_equal(rays.actor_of_body(BodyId(0)), NO_ACTOR)


def test_an_actor_without_tags() raises:
    var world = _world()
    var car = _car(world, 20, 1.75)
    world.actors[car.value - 1].semantic_tags = List[SemanticTag]()
    var rays = WorldRays(Pointer(to=world))
    var back = rays.cast_ray(Vector3(10, 1.75, 0.75), Vector3(1, 0, 0), _m(100))
    assert_equal(back.tag, UNLABELED)
    assert_equal(surface_tag_of_body(world, world.actor(car).body), UNLABELED)


def test_surface_tags_of_bodies() raises:
    var world = _world()
    _wreck(world)
    var car = _car(world, 20, 1.75)
    var road = (
        world.physics.raycast(Vector3(10, 1.75, 5), Vector3(0, 0, -1), _m(10))
        .value()
        .body
    )
    assert_equal(surface_tag_of_body(world, road), ROAD)
    var walk = (
        world.physics.raycast(Vector3(10, 4.5, 5), Vector3(0, 0, -1), _m(10))
        .value()
        .body
    )
    assert_equal(surface_tag_of_body(world, walk), SIDEWALK)
    assert_equal(surface_tag_of_body(world, world.actor(car).body), CAR)
    var ball = world.physics.add_body(
        RigidBody(
            STATIC,
            Shape.sphere(_m(1)),
            Mass(0, KILOGRAM),
            Vector3(0, 0, 50),
            Quaternion.identity(),
        )
    )
    assert_equal(surface_tag_of_body(world, ball), UNLABELED)
    world.physics.world.bodies[road.value].collides = False
    with assert_raises(contains="found no surface"):
        _ = surface_tag_of_body(world, road)
    with assert_raises():
        _ = surface_tag_of_body(world, BodyId(100000))


# --- collisions ----------------------------------------------------------------


def test_collision_with_another_car() raises:
    var world = _world()
    _wreck(world)
    var a = _car(world, 10, 1.75, 0.5)
    var b = _car(world, 16, 1.75, 0.5)
    var sensor = CollisionSensor()
    var hits = List[CollisionMeasurement]()
    for _ in range(40):
        world.set_target_velocity(a, Vector3(10, 0, 0))
        _ = world.tick()
        var found = sensor.collect(world, a)
        # One measurement a pair a frame, however many substeps pushed.
        var others = List[Int]()
        for h in found:
            assert_false(h.other_actor.value in others)
            others.append(h.other_actor.value)
        hits.extend(found^)
        if len(hits) > 0:
            break
    assert_true(len(hits) > 0)
    assert_equal(hits[0].actor, a)
    assert_equal(hits[0].other_actor, b)
    assert_equal(hits[0].other_tag, CAR)
    # The car ahead pushes the one behind back.
    assert_true(hits[0].normal_impulse.x < 0)
    # Asked again in the same frame, the pair is already reported.
    assert_equal(len(sensor.collect(world, a)), 0)


def test_collision_with_the_road() raises:
    var world = _world()
    # A car nearly upside down, dropped: its roof lands on the road.
    var car = world.spawn_actor(
        world.blueprints.at("vehicle.lincoln.mkz"),
        CarlaTransform(
            _m(10),
            _m(1.75),
            _m(2.5),
            CarlaRotation(
                Angle(0, DEGREE), Angle(0, DEGREE), Angle(170, DEGREE)
            ),
        ),
    )
    var sensor = CollisionSensor()
    var hits = List[CollisionMeasurement]()
    for _ in range(40):
        _ = world.tick()
        hits.extend(sensor.collect(world, car))
        if len(hits) > 0:
            break
    assert_true(len(hits) > 0)
    assert_equal(hits[0].other_actor, NO_ACTOR)
    assert_equal(hits[0].other_tag, ROAD)
    # The road pushes the car up.
    assert_true(hits[0].normal_impulse.z > 0)
    var bytes = collision_data(world, hits[0])
    # The map surface is `static.road` with a zero box and tag 1.
    var surface = "9600009300ab7374617469632e726f6164909393ca00000000ca00000000ca0000000093ca00000000ca00000000ca0000000093ca00000000ca00000000ca00000000c40101c400"
    assert_true(surface in _hex(bytes))
    assert_true(_hex(bytes).startswith("9396"))
    # A parent without a body has no hits.
    var empty = _sensor(world, "util.actor.empty", _pose(0, 0, 0))
    assert_equal(len(sensor.collect(world, empty)), 0)


# --- lane invasion ----------------------------------------------------------------


def test_lane_invasion_crosses_the_center_mark() raises:
    var world = _world()
    var car = _car(world, 10, 1.75)
    var box = world.get_bounding_box(car)
    var corners = box_corners(_pose(10, 1.75, 0, 90), box)
    # Turned by 90 degrees, the front right corner is at (10 - 1, 1.75 + 2.4).
    _near(corners[0], 9, 4.15, 0.75)
    _near(corners[3], 11, -0.65, 0.75)
    var sensor = LaneInvasionSensor(box)
    assert_false(
        Bool(sensor.tick(world.map, 1, Duration64(0.05), _pose(10, 1.75, 0)))
    )
    # Standing still is no move.
    assert_false(
        Bool(sensor.tick(world.map, 2, Duration64(0.1), _pose(10, 1.75, 0)))
    )
    # Along the lane: no mark crossed.
    assert_false(
        Bool(sensor.tick(world.map, 3, Duration64(0.15), _pose(10.5, 1.75, 0)))
    )
    # A frame that is not newer is skipped.
    assert_false(
        Bool(sensor.tick(world.map, 3, Duration64(0.15), _pose(11, 1.75, 0)))
    )
    # To y = -0.5: the left corners go from 0.75 to -1.5 and cross the
    # center; the right ones stay in the lane.
    var event = sensor.tick(world.map, 4, Duration64(0.2), _pose(11.5, -0.5, 0))
    assert_true(Bool(event))
    var e = event.value().copy()
    assert_equal(e.frame, 4)
    assert_equal(e.timestamp, 0.2)
    assert_equal(len(e.crossed_lane_markings), 2)
    assert_equal(e.crossed_lane_markings[0].type, SOLID)
    assert_equal(e.crossed_lane_markings[0].color, MARKING_YELLOW)
    _near(e.transform.location, 11.5, -0.5, 0)


def _refuse_lane(mut sensor: LaneInvasionSensor, world: World) raises:
    # A refused time is checked before the corners or frame change.
    for bad in [inf[DType.float64](), nan[DType.float64](), -0.5]:
        with assert_raises(contains="lane invasion time"):
            _ = sensor.tick(world.map, 9, Duration64(bad), _pose(11.5, -0.5, 0))


def test_lane_invasion_time_keeps_float64_and_is_checked() raises:
    var world = _world()
    var car = _car(world, 10, 1.75)
    var box = world.get_bounding_box(car)
    var control = LaneInvasionSensor(box)
    var refused = LaneInvasionSensor(box)
    # Before the first snapshot and after it, refusals change nothing.
    _refuse_lane(refused, world)
    assert_false(refused.has_corners)
    var start = 123456789.000001
    _ = control.tick(world.map, 1, Duration64(start), _pose(10, 1.75, 0))
    _ = refused.tick(world.map, 1, Duration64(start), _pose(10, 1.75, 0))
    _refuse_lane(refused, world)
    assert_equal(refused.frame, control.frame)
    var expected = control.tick(
        world.map, 2, Duration64(start + 1.0e-6), _pose(11.5, -0.5, 0)
    )
    var event = refused.tick(
        world.map, 2, Duration64(start + 1.0e-6), _pose(11.5, -0.5, 0)
    )
    # The event keeps the time's Float64 digits.
    assert_equal(event.value().timestamp, start + 1.0e-6)
    assert_equal(event.value().timestamp, expected.value().timestamp)
    assert_equal(
        len(event.value().crossed_lane_markings),
        len(expected.value().crossed_lane_markings),
    )


# --- obstacles ----------------------------------------------------------------------


def test_obstacle_ahead() raises:
    var world = _world()
    _wreck(world)
    var a = _car(world, 10, 1.75)
    var b = _car(world, 18, 1.75)
    var sensor = _sensor(world, "sensor.other.obstacle", _pose(2.5, 0, 0.75), a)
    var d = ObstacleDescription.from_attributes(world.actor(sensor).attributes)
    assert_equal(d.distance.value, 5)
    assert_equal(d.hit_radius.value, 0.5)
    assert_false(d.only_dynamics)
    assert_false(d.debug_linetrace)
    # From x = 12.5 to the back of the car ahead, 15.6, less the radius.
    var found = detect_obstacle(world, sensor, d).value()
    assert_equal(found.actor, sensor)
    assert_equal(found.other_actor, b)
    assert_equal(found.other_tag, CAR)
    assert_almost_equal(found.distance.value, 2.6, atol=2e-3)
    var bytes = _hex(obstacle_data(world, found))
    assert_true(bytes.startswith("9396"))
    assert_true(bytes.endswith(_big_float(found.distance.value)))


def _big_float(value: Float32) -> String:
    # A MessagePack float 32: 0xca, then the bits big-endian.
    var bits = Int(bitcast[DType.uint32](value))
    comptime digits = "0123456789abcdef"
    var out = String("ca")
    for shift in [28, 24, 20, 16, 12, 8, 4, 0]:
        out += digits[byte=(bits >> shift) & 15]
    return out^


def test_obstacle_below_and_only_dynamics() raises:
    var world = _world()
    _ = _car(world, 60, 30)
    # Pitch 90 looks down in this port's frame.
    var down = _sensor(
        world, "sensor.other.obstacle", _pose(30, 1.75, 2, 0, 90)
    )
    var d = ObstacleDescription()
    var found = detect_obstacle(world, down, d).value()
    assert_equal(found.other_actor, NO_ACTOR)
    assert_equal(found.other_tag, ROAD)
    assert_almost_equal(found.distance.value, 1.5, atol=2e-3)
    d.only_dynamics = True
    assert_false(Bool(detect_obstacle(world, down, d)))
    # The car itself as the detector: its own body is passed through,
    # and the sphere at its origin already touches the road.
    var own = _car(world, 40, 1.75)
    d.only_dynamics = False
    var at_own = detect_obstacle(world, own, d).value()
    assert_equal(at_own.other_actor, NO_ACTOR)
    assert_equal(at_own.distance.value, 0)
    # A detector on a parent without a body.
    var empty = _sensor(world, "util.actor.empty", _pose(50, 1.75, 2))
    var on_empty = _sensor(
        world, "sensor.other.obstacle", _pose(0, 0, 0, 0, 90), empty
    )
    assert_almost_equal(
        detect_obstacle(world, on_empty, d).value().distance.value,
        1.5,
        atol=2e-3,
    )


def test_sphere_sweeps() raises:
    var world = _world()
    var none = List[BodyId]()
    # No moving body at all.
    assert_false(
        Bool(
            sweep_sphere(
                world,
                Vector3(10, 1.75, 2),
                Vector3(1, 0, 0),
                _m(5),
                _m(0.5),
                none,
                True,
            )
        )
    )
    # High above the map every road triangle is culled.
    assert_false(
        Bool(
            sweep_sphere(
                world,
                Vector3(10, 1.75, 100),
                Vector3(1, 0, 0),
                _m(5),
                _m(0.5),
                none,
                False,
            )
        )
    )
    # A map with no surface has nothing to meet.
    var bare = World(load_opendrive("<OpenDRIVE></OpenDRIVE>"))
    assert_false(
        Bool(
            sweep_sphere(
                bare,
                Vector3(0, 0, 0),
                Vector3(1, 0, 0),
                _m(5),
                _m(0.5),
                none,
                False,
            )
        )
    )
    var ball = world.physics.add_body(
        RigidBody(
            STATIC,
            Shape.sphere(_m(1)),
            Mass(0, KILOGRAM),
            Vector3(50, 1.75, 3),
            Quaternion.identity(),
        )
    )
    # A body that does not collide is passed through.
    var ghost = world.physics.add_body(
        RigidBody(
            STATIC,
            Shape.sphere(_m(1)),
            Mass(0, KILOGRAM),
            Vector3(47, 1.75, 3),
            Quaternion.identity(),
        )
    )
    world.physics.world.bodies[ghost.value].collides = False
    # Along a flat top 1 mm above it: the steps are 1 mm, and 512 of them
    # end the sweep short of its 5 m.
    _ = world.physics.add_body(
        RigidBody(
            STATIC,
            Shape.box(_m(10), _m(10), _m(1)),
            Mass(0, KILOGRAM),
            Vector3(100, 100, 0),
            Quaternion.identity(),
        )
    )
    assert_false(
        Bool(
            sweep_sphere(
                world,
                Vector3(95, 100, 1.501),
                Vector3(1, 0, 0),
                _m(5),
                _m(0.5),
                none,
                False,
            )
        )
    )
    var hit = sweep_sphere(
        world,
        Vector3(45, 1.75, 3),
        Vector3(2, 0, 0),
        _m(10),
        _m(0.5),
        none,
        False,
    ).value()
    assert_equal(hit.body, ball)
    assert_almost_equal(hit.distance.value, 3.5, atol=2e-3)
    # A capsule standing up, and one with no segment.
    var pole = world.physics.add_body(
        RigidBody(
            DYNAMIC,
            Shape.capsule(_m(0.25), _m(1)),
            Mass(10, KILOGRAM),
            Vector3(40, -20, 3),
            Quaternion.identity(),
        )
    )
    var at_pole = sweep_sphere(
        world,
        Vector3(35, -20, 3.5),
        Vector3(1, 0, 0),
        _m(10),
        _m(0.5),
        none,
        True,
    ).value()
    assert_equal(at_pole.body, pole)
    assert_almost_equal(at_pole.distance.value, 4.25, atol=2e-3)
    var bead = world.physics.add_body(
        RigidBody(
            DYNAMIC,
            Shape.capsule(_m(0.25), _m(0)),
            Mass(10, KILOGRAM),
            Vector3(40, -30, 3),
            Quaternion.identity(),
        )
    )
    var at_bead = sweep_sphere(
        world,
        Vector3(35, -30, 3),
        Vector3(1, 0, 0),
        _m(10),
        _m(0.5),
        none,
        True,
    ).value()
    assert_equal(at_bead.body, bead)
    assert_almost_equal(at_bead.distance.value, 4.25, atol=2e-3)
    # Starting in contact touches at once.
    var inside = sweep_sphere(
        world,
        Vector3(50, 1.75, 3),
        Vector3(1, 0, 0),
        _m(10),
        _m(0.5),
        none,
        False,
    ).value()
    assert_equal(inside.distance.value, 0)
    with assert_raises(contains="needs a direction"):
        _ = sweep_sphere(
            world, Vector3(0, 0, 0), Vector3(0, 0, 0), _m(1), _m(1), none, False
        )
    with assert_raises(contains="cannot be negative"):
        _ = sweep_sphere(
            world,
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            _m(1),
            _m(-1),
            none,
            False,
        )
    with assert_raises(contains="cannot be negative"):
        _ = sweep_sphere(
            world,
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            _m(-1),
            _m(1),
            none,
            False,
        )


# --- the V2X channel ---------------------------------------------------------------


def test_path_states() raises:
    var world = _world()
    _wreck(world)
    var r = _sensor(world, "sensor.other.v2x", _pose(10, 1.75, 1))
    var s = _sensor(world, "sensor.other.v2x", _pose(30, 1.75, 1))
    var clear = path_state(world, r, s, 1)
    assert_equal(clear[0], LOS)
    assert_equal(len(clear[1]), 0)
    # A car between them at 1 m is in the way. Its edge is its roof, 1.5 m
    # up, plus 2 cm, over the lower antenna at 1 m.
    var car = _car(world, 20, 1.75)
    var blocked = path_state(world, r, s, 1)
    assert_equal(blocked[0], NLOS_VEHICLE)
    assert_equal(len(blocked[1]), 1)
    _near(blocked[1][0], 20, 1.75, 0.52)
    # Above the car the line is clear again.
    var high_r = _sensor(world, "sensor.other.v2x", _pose(10, 1.75, 2))
    var high_s = _sensor(world, "sensor.other.v2x", _pose(30, 1.75, 2))
    assert_equal(path_state(world, high_r, high_s, 2)[0], LOS)
    # A building between them ends the search.
    _ = world.physics.add_body(
        RigidBody(
            STATIC,
            Shape.box(_m(1), _m(1), _m(5)),
            Mass(0, KILOGRAM),
            Vector3(25, 1.75, 0),
            Quaternion.identity(),
        )
    )
    var walled = path_state(world, r, s, 1)
    assert_equal(walled[0], NLOS_BUILDING)
    assert_equal(len(walled[1]), 1)
    # A walker in the way counts as a building, as CARLA's check for a
    # vehicle has it.
    var low_r = _sensor(world, "sensor.other.v2x", _pose(40, -20, 1))
    var low_s = _sensor(world, "sensor.other.v2x", _pose(60, -20, 1))
    _ = world.spawn_actor(
        world.blueprints.at("walker.pedestrian.0020"), _pose(50, -20, 1)
    )
    assert_equal(path_state(world, low_r, low_s, 1)[0], NLOS_BUILDING)
    # Two sensors at one place see each other.
    var twin = _sensor(world, "sensor.other.v2x", _pose(10, 1.75, 1))
    assert_equal(path_state(world, r, twin, 1)[0], LOS)
    _ = car


def test_antennas_on_their_own_cars() raises:
    var world = _world()
    var a = _car(world, 10, 1.75)
    var b = _car(world, 30, 1.75)
    # Both antennas sit inside their cars' boxes; the line passes through
    # the two parents.
    var r = _sensor(world, "sensor.other.v2x", _pose(0, 0, 1), a)
    var s = _sensor(world, "sensor.other.v2x", _pose(0, 0, 1), b)
    assert_equal(path_state(world, r, s, 1)[0], LOS)


def test_channel_hears_a_sender() raises:
    var world = _world()
    var r = _sensor(world, "sensor.other.v2x", _pose(10, 1.75, 2))
    var s = _sensor(world, "sensor.other.v2x", _pose(30, 1.75, 2))
    var params = PropagationParams()
    params.model = WINNER
    params.scenario = HIGHWAY
    var model = PathLossModel(params)
    var rng = SensorRandom(9)
    # WINNER+ on a highway at 20 m, 73.8376 dB, and a fading of -1.1874.
    var heard = simulate_channel(world, model, r, [s], [21.5], rng)
    assert_equal(len(heard), 1)
    assert_equal(heard[0].sender, s)
    assert_almost_equal(
        heard[0].power, 21.5 + 10 - (73.8376389 - 1.18739259), atol=1e-3
    )
    # Beyond the filter distance, or below the sensitivity, nothing.
    params.filter_distance = _m(10)
    assert_equal(
        len(
            simulate_channel(world, PathLossModel(params), r, [s], [21.5], rng)
        ),
        0,
    )
    params = PropagationParams()
    params.model = WINNER
    params.receiver_sensitivity = 100
    assert_equal(
        len(
            simulate_channel(world, PathLossModel(params), r, [s], [21.5], rng)
        ),
        0,
    )
    _ = world.destroy_actor(s)
    assert_equal(len(simulate_channel(world, model, r, [s], [21.5], rng)), 0)
    assert_equal(
        len(
            simulate_channel(
                world, model, r, List[ActorId](), List[Float32](), rng
            )
        ),
        0,
    )
    with assert_raises(contains="one power a sender"):
        _ = simulate_channel(world, model, r, [s], List[Float32](), rng)


def test_ca_service_of_a_vehicle() raises:
    var world = _world()
    var car = _car(world, 10, 1.75)
    world.set_light_state(car, LIGHT_LOW_BEAM | LIGHT_FOG)
    var cam = CaService(world, car, 0.1, 1.0, False, CamNoise(), 1000)
    assert_equal(cam.station_type, STATION_PASSENGER_CAR)
    var rng = SensorRandom(0)
    var projection = world.map.geo_projection.copy()
    var tick = Duration(0.05, SECOND)
    # The first CAM: the car is more than 4 m from the zero position.
    var first = cam.trigger(world, projection, tick, rng).value()
    assert_equal(first.header.protocol_version, 2)
    assert_equal(first.header.message_id.value, 2)
    assert_equal(first.header.station_id, car.value)
    assert_equal(first.generation_delta_time, 1000)
    assert_equal(first.station_type, STATION_PASSENGER_CAR)
    ref high = first.high_frequency
    assert_equal(high.present, CONTAINER_VEHICLE)
    # East is 90 degrees from north: 900 tenths.
    assert_equal(high.heading, 900)
    assert_equal(high.speed, 0)
    assert_equal(high.drive_direction, 0)
    # CARLA's units: 4.8 m is 480 cm, times ten.
    assert_equal(high.vehicle_length, 4800)
    assert_equal(high.vehicle_width, 2000)
    assert_equal(high.longitudinal_acceleration, 0)
    # Gravity alone: 9.81 m/s^2 is 98 tenths.
    assert_equal(high.vertical_acceleration, 98)
    assert_equal(high.yaw_rate, 0)
    assert_equal(first.low_frequency.present, CONTAINER_VEHICLE)
    # Low beam is ETSI bit 0 and fog bit 6, the most significant first.
    assert_equal(Int(first.low_frequency.exterior_lights), 0x82)
    var geo = projection.transform_to_geo_location(world.get_location(car))
    assert_equal(
        first.reference_position.latitude,
        Int(round(geo.latitude_degrees * 1e6)) * 10,
    )
    # No time has passed: nothing to send.
    assert_false(Bool(cam.trigger(world, projection, tick, rng)))
    # Standing still, a CAM after `gen_cam`, the whole second.
    world.elapsed_seconds = 0.5
    assert_false(Bool(cam.trigger(world, projection, tick, rng)))
    world.elapsed_seconds = 1.0
    var slow = cam.trigger(world, projection, tick, rng).value()
    # The low-frequency container comes every 0.5 s at most.
    assert_equal(slow.low_frequency.present, CONTAINER_VEHICLE)
    world.elapsed_seconds = 2.0
    _ = cam.trigger(world, projection, tick, rng).value()
    world.elapsed_seconds = 3.0
    _ = cam.trigger(world, projection, tick, rng).value()
    assert_equal(cam.low_dynamics_counter, 3)
    # Backing up at 1 m/s: a speed change, and the speed reads zero.
    world.set_target_velocity(car, Vector3(-1, 0, 0))
    world.set_target_angular_velocity(car, Vector3(0, 0, 2000))
    world.elapsed_seconds = 3.2
    var moving = cam.trigger(world, projection, tick, rng).value()
    assert_equal(moving.high_frequency.drive_direction, 1)
    assert_equal(moving.high_frequency.speed, 0)
    # 2000 degrees a second is past ETSI's range.
    assert_equal(moving.high_frequency.yaw_rate, 32767)
    assert_equal(cam.low_dynamics_counter, 0)
    # A jump of 100 m in 0.2 s is past the acceleration's range, and the
    # position change sends at once.
    world.set_location(car, Vector3(110, 1.75, 0))
    world.elapsed_seconds = 3.4
    var jump = cam.trigger(
        world, projection, Duration(0.2, SECOND), rng
    ).value()
    assert_equal(jump.high_frequency.longitudinal_acceleration, 161)
    # Turning the other way as fast is past the range too.
    world.set_target_angular_velocity(car, Vector3(0, 0, -2000))
    world.set_location(car, Vector3(10, 1.75, 0))
    world.elapsed_seconds = 3.52
    var back = cam.trigger(world, projection, tick, rng).value()
    assert_equal(back.high_frequency.yaw_rate, 32767)
    # A turn of more than 4 degrees sends too.
    world.set_transform(car, _pose(10, 1.75, 0, 30))
    world.elapsed_seconds = 3.7
    assert_true(Bool(cam.trigger(world, projection, tick, rng)))


def test_ca_service_fixed_rate_and_roadside_units() raises:
    var world = _world()
    var car = _car(world, 10, 1.75)
    var fixed = CaService(world, car, 0.1, 1.0, True, CamNoise(), 0)
    var rng = SensorRandom(0)
    var projection = world.map.geo_projection.copy()
    var tick = Duration(0.05, SECOND)
    assert_true(Bool(fixed.trigger(world, projection, tick, rng)))
    world.elapsed_seconds = 0.1
    assert_true(Bool(fixed.trigger(world, projection, tick, rng)))
    # A sensor with no parent is a roadside unit: a CAM every 0.5 s.
    var rsu_sensor = _sensor(world, "sensor.other.v2x", _pose(0, 0, 0))
    world.elapsed_seconds = 0
    var rsu = CaService(world, rsu_sensor, 0.1, 1.0, False, CamNoise(), 0)
    assert_equal(rsu.station_type, STATION_ROAD_SIDE_UNIT)
    var cam = rsu.trigger(world, projection, tick, rng).value()
    assert_equal(cam.high_frequency.present, CONTAINER_RSU)
    assert_equal(cam.high_frequency.protected_zone_count, 16)
    assert_equal(cam.low_frequency.present, CONTAINER_NOTHING)
    # The town's projection puts the origin at 49 N, 8 E.
    assert_equal(cam.reference_position.latitude, 490000000)
    assert_equal(cam.reference_position.longitude, 80000000)
    world.elapsed_seconds = 0.25
    assert_false(Bool(rsu.trigger(world, projection, tick, rng)))
    world.elapsed_seconds = 0.5
    assert_true(Bool(rsu.trigger(world, projection, tick, rng)))
    # A vehicle tagged as a pedestrian sends no container.
    world.actors[car.value - 1].semantic_tags = [PEDESTRIAN]
    var walker_like = CaService(world, car, 0.1, 1.0, True, CamNoise(), 0)
    assert_equal(walker_like.station_type, STATION_PEDESTRIAN)
    world.elapsed_seconds = 2
    var bare = walker_like.trigger(world, projection, tick, rng).value()
    assert_equal(bare.high_frequency.present, CONTAINER_NOTHING)
    # A vehicle with no tags at all is an unknown station.
    world.actors[car.value - 1].semantic_tags = List[SemanticTag]()
    var unknown = CaService(world, car, 0.1, 1.0, True, CamNoise(), 0)
    assert_equal(unknown.station_type.value, 0)
    world.elapsed_seconds = 3
    var unidentified = unknown.trigger(world, projection, tick, rng).value()
    assert_equal(unidentified.high_frequency.present, CONTAINER_NOTHING)
    assert_equal(unidentified.low_frequency.present, CONTAINER_NOTHING)
    var noise = CamNoise.from_attributes(
        world.blueprints.at("sensor.other.v2x").description()
    )
    assert_equal(noise.velocity_stddev, 0)


def test_actor_records_in_events() raises:
    var world = _world()
    var car = _car(world, 10, 1.75)
    var w = ByteWriter()
    pack_actor(w, world, car, ROAD)
    var text = _hex(w^.finish())
    # [id, parent 0, [uid, "vehicle.lincoln.mkz", ...], ...].
    assert_true(text.startswith("96" + _hex([UInt8(car.value)]) + "0093"))
    assert_true("b376656869636c652e6c696e636f6c6e2e6d6b7a" in text)
    # The car's tag, 14, and the empty stream token end it.
    assert_true(text.endswith("c4010ec400"))
    # An actor that is not in the library has uid zero.
    var spectator = ByteWriter()
    pack_actor(spectator, world, world.get_spectator(), ROAD)
    assert_true(_hex(spectator^.finish()).startswith("96010093" + "00"))


# --- the sensor manager -------------------------------------------------------------


def _small(world: World, id: String) raises -> ActorBlueprint:
    # A blueprint with a tiny image and few rays, for a quick tick.
    var bp = world.blueprints.at(id)
    for i in range(len(bp.attributes)):
        ref a = bp.attributes[i]
        if a.id == "image_size_x":
            a.value = "4"
        elif a.id == "image_size_y":
            a.value = "2"
        elif a.id == "points_per_second":
            a.value = "400"
        elif a.id == "channels":
            a.value = "2"
        elif a.id == "horizontal_resolution":
            a.value = "60"
    return bp^


def _count(ms: List[SensorMeasurement], kind: SensorKind) -> Int:
    var n = 0
    for m in ms:
        if m.kind == kind:
            n += 1
    return n


def test_sensor_kinds() raises:
    assert_equal(sensor_kind_of("sensor.other.imu").value(), IMU_KIND)
    assert_equal(sensor_kind_of("sensor.camera.depth").value(), DEPTH_SENSOR)
    assert_false(Bool(sensor_kind_of("sensor.other.rss")))
    assert_equal(sensor_type_of(IMU_KIND).value, 5)
    assert_equal(sensor_type_of(COLLISION).value, 0)
    assert_equal(sensor_type_of(CUSTOM_V2X).value, 25)
    assert_false(SensorKind(22).is_valid())
    assert_false(SensorKind(-1).is_valid())
    with assert_raises(contains="22 sensors"):
        _ = sensor_type_of(SensorKind(22))


def test_every_sensor_measures() raises:
    var world = _world()
    var car = _car(world, 10, 1.75, 0.5)
    var manager = SensorManager()
    var mount = _pose(0, 0, 2.5)
    var ids = List[String]()
    for b in world.blueprints.blueprints:
        if sensor_kind_of(b.id):
            ids.append(b.id)
    assert_equal(len(ids), 22)
    for id in ids:
        _ = manager.spawn_sensor(world, _small(world, id), mount, car)
    assert_equal(len(manager.slots), 22)
    var first = manager.tick(world)
    # Everything but the DVS (no events on its first frame), the lane
    # invasion (no move yet), the collision (no hit) and the obstacle
    # (nothing ahead) measures; the two V2X sensors have no one to hear.
    assert_equal(len(first), 16)
    for m in first:
        assert_equal(len(m.header), 48)
        assert_equal(Int(m.header[0]), sensor_type_of(m.kind).value)
        assert_equal(Int(m.header[8]), world.frame)
    var depth = first[0].copy()
    assert_equal(depth.kind, DEPTH_SENSOR)
    assert_equal(depth.width, 4)
    assert_equal(depth.image().height, 2)
    # 12 bytes of image header, then 4 a pixel.
    assert_equal(len(depth.raw_data), 12 + 4 * 4 * 2)
    assert_equal(_count(first, IMU_KIND), 1)
    assert_equal(_count(first, GNSS), 1)
    assert_equal(_count(first, RADAR), 1)
    with assert_raises(contains="no image"):
        _ = first[len(first) - 1].image()


def test_sensor_tick_and_errors() raises:
    var world = _world()
    var car = _car(world, 10, 1.75, 0.5)
    var manager = SensorManager()
    var bp = world.blueprints.at("sensor.other.imu")
    for i in range(len(bp.attributes)):
        if bp.attributes[i].id == "sensor_tick":
            bp.attributes[i].value = "0.1"
    var imu = manager.spawn_sensor(world, bp, _pose(0, 0, 1), car)
    assert_true(manager.is_listening(imu))
    # Due every second tick of 0.05 s.
    assert_equal(len(manager.tick(world)), 0)
    var second = manager.tick(world)
    assert_equal(len(second), 1)
    assert_true(Bool(second[0].imu))
    assert_equal(len(manager.tick(world)), 0)
    with assert_raises(contains="already listened"):
        manager.listen(world, imu)
    with assert_raises(contains="not a sensor"):
        manager.listen(world, car)
    with assert_raises(contains="must be on a vehicle"):
        _ = manager.spawn_sensor(
            world,
            world.blueprints.at("sensor.other.lane_invasion"),
            _pose(0, 0, 0),
        )
    with assert_raises(contains="custom V2X sensor can send"):
        manager.send(world, imu, [1])
    manager.stop(imu)
    assert_false(manager.is_listening(imu))
    manager.stop(imu)
    var still = World(load_opendrive_file("assets/carla/town.xodr"))
    with assert_raises(contains="fixed_delta_seconds"):
        _ = manager.tick(still)


def test_lidar_sends_its_last_measurement_again() raises:
    var world = _world()
    var manager = SensorManager()
    var lidar = manager.spawn_sensor(
        world, _small(world, "sensor.lidar.ray_cast"), _pose(10, 1.75, 2)
    )
    var semantic = manager.spawn_sensor(
        world,
        _small(world, "sensor.lidar.ray_cast_semantic"),
        _pose(10, 1.75, 2),
    )
    var first = manager.tick(world)
    assert_equal(len(first), 2)
    # No ray to fire this tick: the last measurement again.
    manager.slots[0].lidar.points_per_second = 1
    manager.slots[1].lidar.points_per_second = 1
    var again = manager.tick(world)
    assert_equal(len(again), 2)
    assert_equal(len(again[0].raw_data), len(first[0].raw_data))
    # Before any measurement, nothing to send.
    var fresh = SensorManager()
    var quiet = _small(world, "sensor.lidar.ray_cast")
    for i in range(len(quiet.attributes)):
        if quiet.attributes[i].id == "points_per_second":
            quiet.attributes[i].value = "1"
    _ = fresh.spawn_sensor(world, quiet, _pose(10, 1.75, 2))
    var quiet_semantic = _small(world, "sensor.lidar.ray_cast_semantic")
    for i in range(len(quiet_semantic.attributes)):
        if quiet_semantic.attributes[i].id == "points_per_second":
            quiet_semantic.attributes[i].value = "1"
    _ = fresh.spawn_sensor(world, quiet_semantic, _pose(10, 1.75, 2))
    assert_equal(len(fresh.tick(world)), 0)
    _ = lidar
    _ = semantic


def test_event_camera_and_lane_invasion_follow_the_car() raises:
    var world = _world()
    var car = _car(world, 10, 1.75, 0.5)
    var ahead = _car(world, 16, 1.75, 0.5)
    var manager = SensorManager()
    # Four rows at 90 degrees, from just ahead of the bumper: the third
    # looks down a quarter, onto the back of the car ahead, 1.1 m away.
    # The physics tier's collider of a car is 0.3 m over its origin.
    var dvs = _small(world, "sensor.camera.dvs")
    for i in range(len(dvs.attributes)):
        if dvs.attributes[i].id == "image_size_y":
            dvs.attributes[i].value = "4"
    _ = manager.spawn_sensor(world, dvs, _pose(2.5, 0, 1), car)
    _ = manager.spawn_sensor(
        world,
        world.blueprints.at("sensor.other.lane_invasion"),
        _pose(0, 0, 0),
        car,
    )
    assert_equal(len(manager.tick(world)), 0)
    # The car ahead leaves the camera's view, and the car crosses the
    # center line with its left corners.
    world.set_location(ahead, Vector3(50, 40, 0.5))
    world.set_location(car, Vector3(14, -0.5, 0.5))
    var moved = manager.tick(world)
    assert_equal(_count(moved, LANE_INVASION), 1)
    assert_equal(_count(moved, DVS_SENSOR), 1)
    for m in moved:
        if m.kind == LANE_INVASION:
            assert_true(len(m.lane_invasion.value().crossed_lane_markings) > 0)
        else:
            assert_true(len(m.events) > 0)
            assert_equal(len(m.raw_data), 12 + 13 * len(m.events))


def test_collision_and_obstacle_through_the_manager() raises:
    var world = _world()
    var a = _car(world, 10, 1.75, 0.5)
    _ = _car(world, 16, 1.75, 0.5)
    var manager = SensorManager()
    _ = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.collision"), _pose(0, 0, 0), a
    )
    _ = manager.spawn_sensor(
        world,
        world.blueprints.at("sensor.other.obstacle"),
        _pose(2.5, 0, 0.75),
        a,
    )
    # A collision sensor with no parent hears nothing.
    _ = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.collision"), _pose(0, 0, 0)
    )
    var collided = 0
    var detected = 0
    for _ in range(40):
        world.set_target_velocity(a, Vector3(10, 0, 0))
        var ms = manager.tick(world)
        collided += _count(ms, COLLISION)
        detected += _count(ms, OBSTACLE)
        if collided > 0:
            break
    assert_true(collided > 0)
    assert_true(detected > 0)


def test_v2x_through_the_manager() raises:
    var world = _world()
    var a = _car(world, 10, 1.75, 0.5)
    var b = _car(world, 30, 1.75, 0.5)
    var manager = SensorManager()
    _ = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.v2x"), _pose(0, 0, 2), a
    )
    _ = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.v2x"), _pose(0, 0, 2), b
    )
    var sender = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.v2x_custom"), _pose(0, 0, 2), a
    )
    var listener = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.v2x_custom"), _pose(0, 0, 2), b
    )
    var elsewhere = world.blueprints.at("sensor.other.v2x_custom")
    for i in range(len(elsewhere.attributes)):
        if elsewhere.attributes[i].id == "channel_id":
            elsewhere.attributes[i].value = "Other"
    _ = manager.spawn_sensor(world, elsewhere, _pose(0, 0, 2), b)
    var unparented = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.v2x_custom"), _pose(0, 0, 2)
    )
    manager.send(world, sender, [1, 2, 3])
    manager.send(world, unparented, [4])
    var ms = manager.tick(world)
    # Each car hears the other's CAM: WINNER+ on a highway at 20 m, and
    # a fading draw after the nine draws of its own CAM.
    assert_equal(_count(ms, V2X), 2)
    for m in ms:
        if m.kind == V2X:
            assert_equal(len(m.cams), 1)
            assert_almost_equal(
                m.cams[0].power, 31.5 - (73.8376389 - 0.904645443), atol=2e-2
            )
            # One `CAMData` record of 3168 bytes.
            assert_equal(len(m.raw_data), 3168)
    # Both custom listeners on the default channel hear both messages;
    # the one on another channel hears nothing.
    assert_equal(_count(ms, CUSTOM_V2X), 3)
    for m in ms:
        if m.kind == CUSTOM_V2X and m.sensor == listener:
            assert_equal(len(m.custom), 2)
            assert_equal(len(m.custom[0].message.data), 3)
            # Two `CustomV2XData` records of 136 bytes.
            assert_equal(len(m.raw_data), 2 * 136)
            assert_equal(m.custom[0].message.header.station_id, a.value)
            assert_equal(m.custom[1].message.header.station_id, 0)
    # The next tick has nothing new to say.
    assert_equal(_count(manager.tick(world), CUSTOM_V2X), 0)


def test_v2x_mixed_rates_deliver_each_transmission_once() raises:
    var world = _world()
    var a = _car(world, 10, 1.75, 0.5)
    var b = _car(world, 30, 1.75, 0.5)
    var manager = SensorManager()
    var bp = world.blueprints.at("sensor.other.v2x_custom")
    bp.set_attribute("sensor_tick", "0.1")
    var sender = manager.spawn_sensor(world, bp, _pose(0, 0, 2), a)
    var listener = manager.spawn_sensor(
        world,
        world.blueprints.at("sensor.other.v2x_custom"),
        _pose(0, 0, 2),
        b,
    )
    var cam = world.blueprints.at("sensor.other.v2x")
    cam.set_attribute("sensor_tick", "0.1")
    _ = manager.spawn_sensor(world, cam, _pose(0, 0, 2), a)
    var cam_listener = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.v2x"), _pose(0, 0, 2), b
    )
    manager.send(world, sender, [1, 2, 3])
    for frame in range(1, 5):
        var messages = 0
        var cams = 0
        for m in manager.tick(world):
            if m.kind == CUSTOM_V2X and m.sensor == listener:
                messages += len(m.custom)
            if m.kind == V2X and m.sensor == cam_listener:
                cams += len(m.cams)
        assert_equal(messages, 1 if frame == 2 else 0, String(frame))
        if frame == 2:
            assert_equal(cams, 1)
        if frame == 1 or frame == 3:
            assert_equal(cams, 0)


def test_manager_edges() raises:
    var world = _world()
    var manager = SensorManager()
    # No sensors: the world still ticks.
    assert_equal(len(manager.tick(world)), 0)
    assert_equal(world.frame, 1)
    var car = _car(world, 10, 1.75, 0.5)
    with assert_raises(contains="custom V2X sensor can send"):
        manager.send(world, car, [1])
    # An IMU with no parent, and one on a parent without a body.
    _ = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.imu"), _pose(0, 0, 1)
    )
    var empty = _sensor(world, "util.actor.empty", _pose(0, 0, 0))
    _ = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.imu"), _pose(0, 0, 1), empty
    )
    var readings = manager.tick(world)
    assert_equal(len(readings), 2)
    # The second reading still has the zero location before the first:
    # through 0, 1 and 1 m, (1 - 2 + 0) / 0.05^2 = -400, plus gravity.
    readings = manager.tick(world)
    assert_almost_equal(
        readings[0].imu.value().accelerometer.z, -400 + 9.81, atol=1e-2
    )
    # Standing still, gravity alone, 9.81 m/s^2 up.
    readings = manager.tick(world)
    assert_almost_equal(
        readings[0].imu.value().accelerometer.z, 9.81, atol=1e-3
    )
    assert_equal(readings[1].imu.value().gyroscope.z, 0)


def test_v2x_alone_far_and_out_of_order() raises:
    var world = _world()
    var manager = SensorManager()
    # A single V2X sensor has no one to hear.
    var alone = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.v2x"), _pose(10, 1.75, 2)
    )
    assert_equal(_count(manager.tick(world), V2X), 0)
    manager.stop(alone)
    # Two spawned first and listened to in the other order; a filter of
    # 1 m keeps them from hearing each other.
    var bp = world.blueprints.at("sensor.other.v2x")
    for i in range(len(bp.attributes)):
        if bp.attributes[i].id == "filter_distance":
            bp.attributes[i].value = "1"
    var first = world.spawn_actor(bp, _pose(10, 1.75, 2))
    var second = world.spawn_actor(bp, _pose(30, 1.75, 2))
    manager.listen(world, second)
    manager.listen(world, first)
    assert_equal(_count(manager.tick(world), V2X), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
