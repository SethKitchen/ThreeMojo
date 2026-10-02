# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Failed public spawns must preserve registries and the next usable ids."""

from extensions.carla.actor import ActorId, AttachmentType, NO_ACTOR, RIGID
from extensions.carla.blueprint import ATTRIBUTE_STRING, ActorBlueprint
from extensions.carla.sensor_manager import SensorManager
from extensions.carla.world import World
from extensions.carla.transform import CarlaTransform
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_world import _world, _pose, _car, _spawn


def _counts(world: World) -> List[Int]:
    return [
        len(world.actors),
        len(world.vehicles),
        len(world.walkers),
        world.physics.world.body_count(),
        len(world.physics.vehicles),
        len(world.physics.walkers),
        len(world.physics.world._order),
        len(world.physics.world._triangles),
        len(world.physics.world._triangle_body),
        len(world.physics.world.events),
        world.physics.world.contact_count,
        len(world.physics.events),
        len(world._overlaps),
        world.frame,
        world.snapshot.size(),
    ]


def _check_counts(world: World, before: List[Int]) raises:
    var after = _counts(world)
    assert_equal(len(after), len(before))
    for i in range(len(before)):
        assert_equal(after[i], before[i], "spawn state counter " + String(i))


def _check_failure(
    mut world: World,
    blueprint: ActorBlueprint,
    pose: CarlaTransform,
    error: String,
    parent: ActorId = NO_ACTOR,
    attachment: AttachmentType = RIGID,
) raises:
    var counts = _counts(world)
    var actors = world.actors.copy()
    var bodies = world.physics.world.bodies.copy()
    var order = world.physics.world._order.copy()
    var elapsed = world.elapsed_seconds
    var delta = world.delta_seconds
    with assert_raises(contains=error):
        _ = world.spawn_actor(blueprint, pose, parent, attachment)
    _check_counts(world, counts)
    assert_false(
        Bool(world.try_spawn_actor(blueprint, pose, parent, attachment))
    )
    _check_counts(world, counts)
    assert_equal(world.elapsed_seconds, elapsed)
    assert_equal(world.delta_seconds, delta)
    for i in range(len(actors)):
        ref before = actors[i]
        ref after = world.actors[i]
        assert_equal(after.id, before.id)
        assert_equal(after.type_id, before.type_id)
        assert_equal(after.state, before.state)
        assert_equal(after.kind, before.kind)
        assert_equal(after.handle, before.handle)
        assert_equal(after.body, before.body)
        assert_equal(after.parent, before.parent)
        assert_equal(after.attachment, before.attachment)
        assert_true(
            after.local_transform.location == before.local_transform.location
        )
        assert_true(
            after.local_transform.rotation == before.local_transform.rotation
        )
        assert_true(after.last_velocity == before.last_velocity)
    for i in range(len(bodies)):
        assert_true(
            world.physics.world.bodies[i].position == bodies[i].position
        )
        assert_true(
            world.physics.world.bodies[i].linear_velocity
            == bodies[i].linear_velocity
        )
        assert_equal(world.physics.world.bodies[i].collides, bodies[i].collides)
    for i in range(len(order)):
        assert_equal(world.physics.world._order[i], order[i])
    assert_false(world.is_alive(ActorId(len(actors) + 1)))
    assert_false(world.destroy_actor(ActorId(len(actors) + 1)))


def _attribute_index(blueprint: ActorBlueprint, id: String) raises -> Int:
    for i in range(len(blueprint.attributes)):
        if blueprint.attributes[i].id == id:
            return i
    raise Error("Missing test attribute: " + id)


def _populated_world() raises -> World:
    var world = _world()
    _ = _car(world, _pose(10, 1.75, 4, 0))
    _ = _spawn(world, "walker.pedestrian.0015", _pose(10, 4.5, 4, 0))
    _ = _spawn(world, "sensor.other.imu", _pose(10, 1.75, 6, 0))
    _ = world.tick()
    return world^


def test_vehicle_boolean_failures_leave_no_actor_or_body() raises:
    # Both reads used to happen after the actor and physics were published.
    for field in ["has_dynamic_doors", "sticky_control"]:
        for invalid in range(3):
            var world = _populated_world()
            var bp = world.blueprints.at("vehicle.lincoln.mkz")
            var i = _attribute_index(bp, field)
            var error = field
            if invalid == 0:
                bp.attributes[i].value = "yes"
            elif invalid == 1:
                bp.attributes[i].type = ATTRIBUTE_STRING
            else:
                _ = bp.attributes.pop(i)
            var next_id = len(world.actors) + 1
            var next_body = world.physics.world.body_count()
            var next_vehicle = len(world.physics.vehicles)
            var pose = _pose(30, 1.75, 4, 0)
            _check_failure(world, bp, pose, error)
            assert_equal(len(world.filter_actors("vehicle.*")), 1)
            assert_equal(len(world.filter_actors("walker.*")), 1)
            assert_equal(len(world.filter_actors("sensor.*")), 1)
            # The same position and all next ids are still available.
            var car = _car(world, pose)
            assert_equal(car.value, next_id)
            assert_equal(world.actor(car).body.value, next_body)
            assert_equal(
                world.vehicles[world.actor(car).handle].physics.value,
                next_vehicle,
            )
            assert_equal(len(world.get_vehicles_light_states()), 2)
            _ = world.tick()
            assert_true(world.get_snapshot().contains(car))
            assert_true(world.destroy_actor(car))
            _ = world.tick()
            assert_false(world.get_snapshot().contains(car))


def test_missing_vehicle_base_type_is_atomic() raises:
    var world = _populated_world()
    var bp = world.blueprints.at("vehicle.lincoln.mkz")
    _ = bp.attributes.pop(_attribute_index(bp, "base_type"))
    var next_id = len(world.actors) + 1
    _check_failure(world, bp, _pose(30, 1.75, 4, 0), "base_type")
    assert_equal(_car(world, _pose(30, 1.75, 4, 0)).value, next_id)


def test_sensor_attachment_failures_preserve_existing_actors() raises:
    var world = _populated_world()
    var bp = world.blueprints.at("sensor.camera.rgb")
    var pose = _pose(1, 0, 2, 0)
    var next_id = len(world.actors) + 1
    _check_failure(
        world, bp, pose, "Attachment type", ActorId(7), AttachmentType(3)
    )
    _check_failure(world, bp, pose, "names no actor", ActorId(999))
    var dead = _spawn(world, "util.actor.empty", _pose(0, 0, 0, 0))
    assert_true(world.destroy_actor(dead))
    _check_failure(world, bp, pose, "destroyed", dead)
    var camera = world.spawn_actor(bp, pose, ActorId(7))
    assert_equal(camera.value, next_id + 1)
    assert_equal(world.actor(camera).parent, ActorId(7))
    _ = world.tick()
    assert_true(world.get_snapshot().contains(camera))
    assert_true(world.destroy_actor(camera))


def test_collision_and_physical_parent_failures_keep_walker_ids() raises:
    var world = _populated_world()
    var walker = world.blueprints.at("walker.pedestrian.0015")
    var vehicle = world.blueprints.at("vehicle.lincoln.mkz")
    _check_failure(world, vehicle, world.get_transform(ActorId(7)), "collision")
    _check_failure(world, walker, world.get_transform(ActorId(8)), "collision")
    var pose = _pose(30, 4.5, 4, 25)
    _check_failure(world, walker, pose, "cannot have a parent", ActorId(7))
    _check_failure(world, vehicle, pose, "cannot have a parent", ActorId(7))
    var next_id = len(world.actors) + 1
    var next_body = world.physics.world.body_count()
    var next_walker = len(world.physics.walkers)
    var id = world.spawn_actor(walker, pose)
    assert_equal(id.value, next_id)
    assert_equal(world.actor(id).body.value, next_body)
    assert_equal(
        world.walkers[world.actor(id).handle].physics.value, next_walker
    )
    _ = world.tick()
    assert_true(world.get_snapshot().contains(id))
    assert_true(world.destroy_actor(id))
    _ = world.tick()


def _check_sensor_failure(
    mut world: World,
    mut manager: SensorManager,
    blueprint: ActorBlueprint,
    error: String,
    parent: ActorId = NO_ACTOR,
) raises:
    var before = _counts(world)
    var slots = len(manager.slots)
    var id = manager.slots[0].id
    var since = manager.slots[0].since
    var due = manager.slots[0].due
    var next_id = len(world.actors) + 1
    with assert_raises(contains=error):
        _ = manager.spawn_sensor(world, blueprint, _pose(0, 0, 2, 0), parent)
    _check_counts(world, before)
    assert_equal(len(manager.slots), slots)
    assert_equal(manager.slots[0].id, id)
    assert_equal(manager.slots[0].since, since)
    assert_equal(manager.slots[0].due, due)
    assert_false(manager.is_listening(ActorId(next_id)))
    assert_false(world.is_alive(ActorId(next_id)))
    assert_false(world.destroy_actor(ActorId(next_id)))
    var sensor = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.imu"), _pose(0, 0, 2, 0)
    )
    assert_equal(sensor.value, next_id)
    assert_true(manager.is_listening(sensor))
    assert_equal(len(manager.tick(world)), slots + 1)
    manager.stop(sensor)
    assert_true(world.destroy_actor(sensor))
    assert_equal(len(manager.tick(world)), slots)


def test_sensor_setup_failures_restore_world_and_manager() raises:
    var world = _populated_world()
    var manager = SensorManager()
    _ = manager.spawn_sensor(
        world,
        world.blueprints.at("sensor.other.imu"),
        _pose(0, 0, 2, 0),
        ActorId(7),
    )
    _ = manager.tick(world)
    var camera = world.blueprints.at("sensor.camera.rgb")
    camera.set_attribute("image_size_x", "0")
    _check_sensor_failure(world, manager, camera, "positive", ActorId(7))
    var lidar = world.blueprints.at("sensor.lidar.ray_cast")
    lidar.set_attribute("channels", "0")
    _check_sensor_failure(world, manager, lidar, "at least one channel")
    var lane = world.blueprints.at("sensor.other.lane_invasion")
    _check_sensor_failure(world, manager, lane, "must be on a vehicle")
    _check_sensor_failure(
        world, manager, lane, "must be on a vehicle", ActorId(8)
    )
    var v2x = world.blueprints.at("sensor.other.v2x")
    v2x.set_attribute("frequency_ghz", "0")
    _check_sensor_failure(world, manager, v2x, "frequency", ActorId(7))
    # Channel validation runs after the initial slot setup.
    v2x = world.blueprints.at("sensor.other.v2x")
    v2x.set_attribute("d_ref", "0")
    _check_sensor_failure(world, manager, v2x, "reference distance")
    var next_id = len(world.actors) + 1
    var valid = world.blueprints.at("sensor.other.v2x")
    var station = manager.spawn_sensor(world, valid, _pose(0, 0, 2, 0))
    assert_equal(station.value, next_id)
    assert_equal(
        manager.slots[len(manager.slots) - 1].ca_service.value().owner, station
    )
    assert_equal(len(manager.slots), 2)
    # The lone V2X station hears no peers; the existing IMU still measures.
    assert_equal(len(manager.tick(world)), 1)


def test_sensor_manager_rejects_non_sensors_before_physics() raises:
    var world = _populated_world()
    var manager = SensorManager()
    _ = manager.spawn_sensor(
        world, world.blueprints.at("sensor.other.imu"), _pose(0, 0, 2, 0)
    )
    for type_id in [
        "vehicle.lincoln.mkz",
        "walker.pedestrian.0015",
        "static.prop.mesh",
        "util.actor.empty",
    ]:
        _check_sensor_failure(
            world, manager, world.blueprints.at(type_id), "not a sensor"
        )
    var foreign = world.blueprints.at("sensor.camera.rgb")
    foreign.id = "sensor.camera.unknown"
    _check_sensor_failure(world, manager, foreign, "not a sensor")
    _check_sensor_failure(
        world,
        manager,
        world.blueprints.at("sensor.other.imu"),
        "names no actor",
        ActorId(999),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
