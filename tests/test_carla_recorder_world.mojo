# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's recorder on a world, and its replayer back into one.

The world stands on `assets/carla/town.xodr`: the spectator is actor 1,
the traffic light actor 2 and the four signs actors 3 to 6, so the first
actor a test spawns is actor 7. The expected numbers come from outside
this port:

- The units by hand: a location in meters is written times 100 in
  centimeters, a walker's speed in m/s times 100 in cm/s, a rotation as
  roll, pitch and yaw.
- The replay's times from CARLA's `CarlaReplayer.cpp`, worked by hand:
  the replay at time t sits in the frame k with t(k) <= t < t(k) + d(k),
  and places each actor between its poses in frames k - 1 and k at the
  fraction (t - t(k)) / d(k). So after replay tick j, at time j dt, an
  actor has its pose of frame j: the pose it had after the recording's
  tick j.
- The midpoint of two poses by hand: the middle of the two locations,
  and each angle halfway the shorter way round: 172 and -168 degrees
  meet at 182, which is -178.
- CARLA's text for the replay, from `CarlaReplayer.cpp`'s stream: the
  times as `%g`, the time factor with one digit.
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    NO_ACTOR,
    OTHER_ACTOR,
    RED,
    SENSOR_ACTOR,
    TRAFFIC_LIGHT_ACTOR,
    VEHICLE_ACTOR,
    WALKER_ACTOR,
    YELLOW,
)
from extensions.carla.blueprint import ATTRIBUTE_STRING, ActorAttributeValue
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.physics.vehicle_control import Gear, VehicleControl
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.recorder import (
    Recorder,
    now_seconds,
    recorder_rotation,
    weather_record,
)
from extensions.carla.recorder_packets import (
    LIGHT_GROUP_STREET,
    LogReader,
    LogVector,
    NOT_AN_ACTOR,
    PACKET_ANIM_VEHICLE,
    PACKET_ANIM_WALKER,
    PACKET_BOUNDING_BOX,
    PACKET_COLLISION,
    PACKET_EVENT_ADD,
    PACKET_EVENT_DEL,
    PACKET_EVENT_PARENT,
    PACKET_FRAME_START,
    PACKET_KINEMATICS,
    PACKET_PHYSICS_CONTROL,
    PACKET_POSITION,
    PACKET_STATE,
    PACKET_TRAFFIC_LIGHT_TIME,
    PACKET_TRIGGER_VOLUME,
    PACKET_VEHICLE_DOOR,
    PACKET_VEHICLE_LIGHT,
    PACKET_WALKER_BONES,
    PACKET_WEATHER,
    RecordedAnimBiker,
    RecordedAnimVehicle,
    RecordedAnimWalker,
    RecordedAnimWheels,
    RecordedAttribute,
    RecordedBone,
    RecordedBoundingBox,
    RecordedCollision,
    RecordedDescription,
    RecordedDoorVehicle,
    RecordedEventAdd,
    RecordedEventDel,
    RecordedEventParent,
    RecordedKinematics,
    RecordedLightScene,
    RecordedLightVehicle,
    RecordedPosition,
    RecordedTrafficLight,
    RecordedTrafficLightTime,
    RecordedWalkerBones,
    RecordedWeather,
    RecordedWheel,
    RecorderInfo,
    SceneLightId,
)
from extensions.carla.recorder_physics import RecordedPhysicsControl
from extensions.carla.replayer import Replayer
from extensions.carla.replayer_helper import (
    IGNORED,
    NOT_CREATED,
    find_traffic_sign_at,
    interpolated_transform,
    lerp_angle,
    process_door_vehicle,
    process_event_add,
    process_event_parent,
    process_position,
    process_state_traffic_light,
    set_camera_position,
)
from extensions.carla.recorder_packets import (
    PACKET_SCENE_LIGHT,
    write_packet,
)
from extensions.carla.road_info import SignalId
from extensions.carla.traffic_sign import TriggerBox
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.vehicle import (
    DOOR_FRONT_LEFT,
    DOOR_REAR_RIGHT,
    LIGHT_BRAKE,
    LIGHT_LOW_BEAM,
    VehicleDoor,
    VehicleWheelLocation,
)
from extensions.carla.walker import BoneTransformDataIn, WalkerBoneControlIn
from extensions.carla.weather import WeatherParameters, weather_preset
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from math.vector4 import Vector4
from test_scratch import temporary_path
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
    METER,
    SECOND,
    Angle,
    Duration,
    Length,
    Velocity,
)


def _world() raises -> World:
    var world = World(load_opendrive_file("assets/carla/town.xodr"))
    var settings = EpisodeSettings()
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    return world^


def _pose(
    x: Float32, y: Float32, z: Float32, yaw: Float32, pitch: Float32 = 0
) -> CarlaTransform:
    return CarlaTransform(
        Length(x, METER),
        Length(y, METER),
        Length(z, METER),
        CarlaRotation(
            Angle(pitch, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)
        ),
    )


def _spawn(
    mut world: World,
    id: String,
    t: CarlaTransform,
    parent: ActorId = NO_ACTOR,
) raises -> ActorId:
    return world.spawn_actor(world.blueprints.at(id), t, parent)


def _hero(mut world: World, t: CarlaTransform) raises -> ActorId:
    var bp = world.blueprints.at("vehicle.lincoln.mkz")
    bp.set_attribute("role_name", "hero")
    return world.spawn_actor(bp, t)


def _near(a: Float32, b: Float32, tol: Float64 = 1e-3) raises:
    assert_almost_equal(Float64(a), Float64(b), atol=tol)


def _near_pose(
    a: CarlaTransform, b: CarlaTransform, tol: Float64 = 1e-3
) raises:
    _near(a.location.x, b.location.x, tol)
    _near(a.location.y, b.location.y, tol)
    _near(a.location.z, b.location.z, tol)
    var ra = recorder_rotation(a.rotation)
    var rb = recorder_rotation(b.rotation)
    _near(ra.pitch, rb.pitch, tol)
    _near(ra.yaw, rb.yaw, tol)
    _near(ra.roll, rb.roll, tol)


@fieldwise_init
struct _Packet(ImplicitlyCopyable):
    var frame: Int
    var id: Int
    var start: Int


def _packets(bytes: List[UInt8]) -> List[_Packet]:
    """Walk a recording: each packet's frame, id and body offset."""
    var r = LogReader(bytes.copy())
    _ = RecorderInfo.read(r)
    var out = List[_Packet]()
    var frame = 0
    while True:
        var id = r.u8()
        var size = r.u32()
        if r.failed:
            break
        if id == PACKET_FRAME_START.value:
            frame += 1
        out.append(_Packet(frame, id, r.pos))
        r.skip(size)
    return out^


def _reader_at(bytes: List[UInt8], p: _Packet) -> LogReader:
    var r = LogReader(bytes.copy())
    r.seek(p.start)
    return r^


def _find(packets: List[_Packet], frame: Int, id: Int) raises -> _Packet:
    for p in packets:
        if p.frame == frame and p.id == id:
            return p
    raise Error("no packet " + String(id) + " in frame " + String(frame))


def _has(packets: List[_Packet], frame: Int, id: Int) -> Bool:
    for p in packets:
        if p.frame == frame and p.id == id:
            return True
    return False


# --- recording ----------------------------------------------------------------------


def test_record_and_replay_world_with_utf8_signal_ids() raises:
    var world = _world()
    var light_id = String("a") * 31 + "é"
    var sign_id = String("b") * 29 + "😀"
    world.traffic_lights.lights[0].sign_id = SignalId(light_id)
    world.signs[0].sign_id = SignalId(sign_id)
    var recorder = Recorder()
    _ = recorder.start(world, "", "Town", False, 0)
    for frame in range(1, 4):
        assert_equal(recorder.tick(world), frame)
        var snapshot = world.get_snapshot()
        assert_equal(
            snapshot.find(ActorId(2)).value().traffic_light.value().sign_id,
            String("a") * 31,
        )
        assert_equal(
            snapshot.find(ActorId(3)).value().sign_id, String("b") * 29
        )
    recorder.stop()
    var bytes = recorder.bytes()
    var packets = _packets(bytes)
    # The recorder stores actor ids and light states, not snapshot sign
    # strings. Its tick must still finish, and the packets must be readable.
    for frame in range(1, 4):
        var state = _reader_at(bytes, _find(packets, frame, PACKET_STATE.value))
        assert_equal(state.u16(), 1)
        var light = RecordedTrafficLight.read(state)
        assert_equal(light.database_id.value, 2)
        assert_true(light.state == world.get_traffic_light_state_of(ActorId(2)))
        assert_false(state.failed)
    var replay_world = _world()
    replay_world.traffic_lights.lights[0].sign_id = SignalId(light_id)
    replay_world.signs[0].sign_id = SignalId(sign_id)
    var replay = Replayer()
    _ = replay.replay_bytes(replay_world, bytes.copy(), "mem")
    assert_equal(replay.mapped(ActorId(2)).value, 2)
    assert_equal(replay.mapped(ActorId(3)).value, 3)
    _ = replay.step(replay_world)
    assert_equal(replay_world.get_opendrive_id(ActorId(2)).value, light_id)
    assert_equal(replay_world.get_opendrive_id(ActorId(3)).value, sign_id)
    assert_equal(
        replay_world.get_snapshot().find(ActorId(3)).value().sign_id,
        String("b") * 29,
    )


def test_the_first_frame_holds_the_worlds_actors() raises:
    var world = _world()
    var car = _hero(world, _pose(10, 1.75, 0.5, 30))
    var r = Recorder()
    assert_false(r.is_enabled())
    _ = r.start(world, "", "Town", False, 1234)
    assert_true(r.is_enabled())
    _ = r.tick(world)
    var bytes = r.bytes()
    var info = LogReader(bytes.copy())
    var head = RecorderInfo.read(info)
    assert_equal(head.version, 1)
    assert_equal(head.magic, "CARLA_RECORDER")
    assert_equal(head.date, 1234)
    assert_equal(head.map_file, "Town")
    var packets = _packets(bytes)
    var reader = _reader_at(bytes, _find(packets, 1, PACKET_EVENT_ADD.value))
    assert_equal(reader.u16(), 7)
    var kinds = List[Int]()
    var names = List[String]()
    for _ in range(7):
        var e = RecordedEventAdd.read(reader)
        kinds.append(e.type.value)
        names.append(e.description.id)
        if e.database_id == car:
            # Where the car was when the recording started, in cm.
            assert_almost_equal(e.location.x, 1000, atol=1e-3)
            assert_almost_equal(e.location.y, 175, atol=1e-3)
            assert_almost_equal(e.rotation.z, 30, atol=1e-3)
            var hero = False
            for a in e.description.attributes:
                if a.id == "role_name" and a.value == "hero":
                    hero = True
            assert_true(hero)
            assert_true(e.description.uid > 0)
    assert_equal(names[0], "spectator")
    assert_equal(kinds[0], OTHER_ACTOR.value)
    assert_equal(names[1], "traffic.traffic_light")
    assert_equal(kinds[1], TRAFFIC_LIGHT_ACTOR.value)
    assert_equal(kinds[6], VEHICLE_ACTOR.value)
    # The spectator and the car have poses; the light has a state.
    var pos = _reader_at(bytes, _find(packets, 1, PACKET_POSITION.value))
    assert_equal(pos.u16(), 2)
    var spectator = RecordedPosition.read(pos)
    assert_equal(spectator.database_id.value, 1)
    var p = RecordedPosition.read(pos)
    var now = world.get_transform(car)
    assert_almost_equal(p.location.x, Float64(now.location.x) * 100, atol=1e-3)
    assert_almost_equal(p.location.z, Float64(now.location.z) * 100, atol=1e-3)
    var state = _reader_at(bytes, _find(packets, 1, PACKET_STATE.value))
    assert_equal(state.u16(), 1)
    var light = RecordedTrafficLight.read(state)
    assert_equal(light.database_id.value, 2)
    assert_true(light.state == world.get_traffic_light_state_of(ActorId(2)))
    assert_false(light.is_frozen)
    # The first frame has the weather; no additional data is written.
    assert_true(_has(packets, 1, PACKET_WEATHER.value))
    assert_false(_has(packets, 1, PACKET_KINEMATICS.value))
    assert_false(_has(packets, 1, PACKET_BOUNDING_BOX.value))
    r.stop()
    assert_false(r.is_enabled())


def test_events_are_found_by_comparing_frames() raises:
    var world = _world()
    var r = Recorder()
    _ = r.start(world, "", "Town", False, 0)
    _ = r.tick(world)
    var car = _spawn(world, "vehicle.lincoln.mkz", _pose(20, 1.75, 0.5, 0))
    var walker = _spawn(world, "walker.pedestrian.0015", _pose(40, -4, 1.2, 90))
    var sensor = _spawn(world, "sensor.other.collision", _pose(1, 0, 2, 0), car)
    world.apply_walker_control(
        walker, WalkerControl(Vector3(0, 1, 0), Velocity(1.5), False)
    )
    var control = VehicleControl()
    control.throttle = 0.5
    control.steer = -0.25
    control.gear = Gear(2)
    world.apply_control(car, control)
    world.set_light_state(car, LIGHT_LOW_BEAM | LIGHT_BRAKE)
    _ = r.tick(world)
    world.open_door(car, DOOR_REAR_RIGHT)
    world.set_weather(weather_preset("HardRainNoon"))
    _ = world.destroy_actor(walker)
    _ = r.tick(world)
    # A tick with no change writes no weather and no events.
    _ = r.tick(world)
    var bytes = r.bytes()
    var packets = _packets(bytes)
    # Frame 2: the car, the walker and the sensor appear, at the poses
    # they were spawned with; the sensor's is in the car's frame.
    var add = _reader_at(bytes, _find(packets, 2, PACKET_EVENT_ADD.value))
    assert_equal(add.u16(), 3)
    var e1 = RecordedEventAdd.read(add)
    assert_true(e1.database_id == car and e1.type == VEHICLE_ACTOR)
    assert_almost_equal(e1.location.x, 2000, atol=1e-3)
    var e2 = RecordedEventAdd.read(add)
    assert_true(e2.type == WALKER_ACTOR)
    assert_almost_equal(e2.rotation.z, 90, atol=1e-3)
    var e3 = RecordedEventAdd.read(add)
    assert_true(e3.database_id == sensor and e3.type == SENSOR_ACTOR)
    assert_almost_equal(e3.location.x, 100, atol=1e-3)
    assert_almost_equal(e3.location.z, 200, atol=1e-3)
    var parent = _reader_at(bytes, _find(packets, 2, PACKET_EVENT_PARENT.value))
    assert_equal(parent.u16(), 1)
    var link = RecordedEventParent.read(parent)
    assert_true(link.database_id == sensor and link.database_id_parent == car)
    # The car's control and lights, and the walker's speed in cm/s.
    var anim = _reader_at(bytes, _find(packets, 2, PACKET_ANIM_VEHICLE.value))
    assert_equal(anim.u16(), 1)
    var v = RecordedAnimVehicle.read(anim)
    assert_equal(v.throttle, 0.5)
    assert_equal(v.steering, -0.25)
    # The gear is the gearbox's, which the automatic box chose.
    assert_false(v.handbrake)
    var lights = _reader_at(
        bytes, _find(packets, 2, PACKET_VEHICLE_LIGHT.value)
    )
    assert_equal(lights.u16(), 1)
    assert_true(
        RecordedLightVehicle.read(lights).state
        == (LIGHT_LOW_BEAM | LIGHT_BRAKE)
    )
    var walk = _reader_at(bytes, _find(packets, 2, PACKET_ANIM_WALKER.value))
    assert_equal(walk.u16(), 1)
    assert_almost_equal(RecordedAnimWalker.read(walk).speed, 150, atol=1e-3)
    # Frame 3: the door, the weather and the removal.
    var door = _reader_at(bytes, _find(packets, 3, PACKET_VEHICLE_DOOR.value))
    assert_equal(door.u16(), 1)
    var d = RecordedDoorVehicle.read(door)
    assert_true(d.doors == DOOR_REAR_RIGHT and d.is_open)
    var weather = _reader_at(bytes, _find(packets, 3, PACKET_WEATHER.value))
    assert_equal(weather.u16(), 1)
    var w = RecordedWeather.read(weather)
    var hard = weather_preset("HardRainNoon")
    assert_equal(w.precipitation, hard.precipitation)
    assert_almost_equal(
        w.sun_altitude_angle, hard.sun_altitude_angle.to(DEGREE), atol=1e-4
    )
    var gone = _reader_at(bytes, _find(packets, 3, PACKET_EVENT_DEL.value))
    assert_equal(gone.u16(), 1)
    assert_true(RecordedEventDel.read(gone).database_id == walker)
    # Frame 4: nothing new.
    var quiet = _reader_at(bytes, _find(packets, 4, PACKET_EVENT_ADD.value))
    assert_equal(quiet.u16(), 0)
    assert_false(_has(packets, 4, PACKET_WEATHER.value))


def test_additional_data() raises:
    var world = _world()
    var walker = _spawn(world, "walker.pedestrian.0015", _pose(40, -4, 1.2, 0))
    world.set_bones_transform(
        walker,
        WalkerBoneControlIn(
            [BoneTransformDataIn("crl_hips__C", _pose(0, 0, 0.95, 10))]
        ),
    )
    var r = Recorder()
    _ = r.start(world, "", "Town", True, 0)
    var car = _spawn(world, "vehicle.lincoln.mkz", _pose(20, 1.75, 0.5, 0))
    world.set_target_velocity(car, Vector3(3, 0, 0))
    _ = r.tick(world)
    r.add_physics_control(world, car)
    r.add_traffic_light_time(world, ActorId(2))
    _ = r.tick(world)
    var bytes = r.bytes()
    var packets = _packets(bytes)
    var kin = _reader_at(bytes, _find(packets, 1, PACKET_KINEMATICS.value))
    assert_equal(kin.u16(), 2)
    var k1 = RecordedKinematics.read(kin)
    assert_true(k1.database_id == walker)
    var k2 = RecordedKinematics.read(kin)
    var velocity = world.get_velocity(car)
    assert_true(k2.database_id == car)
    assert_true(abs(k2.linear_velocity.x) > 0)
    _ = velocity
    var boxes = _reader_at(bytes, _find(packets, 1, PACKET_BOUNDING_BOX.value))
    # The spectator, the walker and the car: lights and signs have trigger
    # volumes instead.
    assert_equal(boxes.u16(), 3)
    _ = RecordedBoundingBox.read(boxes)
    _ = RecordedBoundingBox.read(boxes)
    var box = RecordedBoundingBox.read(boxes)
    # The car's box: 4.8 m long, 2 m wide, 1.5 m high, in cm.
    assert_almost_equal(box.extension.x, 240, atol=1e-3)
    assert_almost_equal(box.extension.z, 75, atol=1e-3)
    var triggers = _reader_at(
        bytes, _find(packets, 1, PACKET_TRIGGER_VOLUME.value)
    )
    assert_equal(triggers.u16(), 5)
    var times = _reader_at(
        bytes, _find(packets, 1, PACKET_TRAFFIC_LIGHT_TIME.value)
    )
    assert_equal(times.u16(), 1)
    var t = RecordedTrafficLightTime.read(times)
    assert_equal(t.green_time, 10)
    assert_equal(t.yellow_time, 3)
    assert_equal(t.red_time, 2)
    var physics = _reader_at(
        bytes, _find(packets, 1, PACKET_PHYSICS_CONTROL.value)
    )
    assert_equal(physics.u16(), 1)
    var p = RecordedPhysicsControl.read(physics)
    assert_true(p.database_id == car)
    assert_equal(len(p.wheels), 4)
    assert_almost_equal(p.wheels[0].wheel_radius, 30, atol=1e-3)
    assert_almost_equal(p.wheels[0].slip_threshold, 20, atol=1e-3)
    assert_almost_equal(p.chassis_width, 180, atol=1e-3)
    var bones = _reader_at(bytes, _find(packets, 1, PACKET_WALKER_BONES.value))
    assert_equal(bones.u16(), 1)
    var b = RecordedWalkerBones.read(bones)
    assert_equal(b.bones[0].name, "crl_hips__C")
    assert_almost_equal(b.bones[0].location.z, 95, atol=1e-3)
    assert_almost_equal(b.bones[0].rotation.z, 10, atol=1e-3)
    # The later calls land in frame 2.
    assert_true(_has(packets, 2, PACKET_PHYSICS_CONTROL.value))
    assert_true(_has(packets, 2, PACKET_TRAFFIC_LIGHT_TIME.value))


def test_collision_sensor_hits_are_recorded() raises:
    var world = _world()
    var car = _hero(world, _pose(20, 1.75, 0.6, 0))
    var other = _spawn(world, "vehicle.mini.cooper", _pose(26, 1.75, 0.6, 0))
    _ = _spawn(world, "sensor.other.collision", _pose(0, 0, 0, 0), car)
    # A sensor with no parent hears nothing.
    _ = _spawn(world, "sensor.other.collision", _pose(0, 0, 0, 0))
    var r = Recorder()
    _ = r.start(world, "", "Town", False, 0)
    world.set_target_velocity(car, Vector3(15, 0, 0))
    var hit = False
    for _ in range(20):
        _ = r.tick(world)
        world.set_target_velocity(car, Vector3(15, 0, 0))
    var bytes = r.bytes()
    for p in _packets(bytes):
        if p.id != PACKET_COLLISION.value:
            continue
        var c = _reader_at(bytes, p)
        var n = c.u16()
        for _ in range(n):
            var rec = RecordedCollision.read(c)
            if rec.database_id2 == other:
                assert_true(rec.database_id1 == car)
                assert_true(rec.is_actor1_hero)
                assert_false(rec.is_actor2_hero)
                hit = True
    assert_true(hit)


def test_collisions_keep_one_record_a_pair() raises:
    var world = _world()
    var car = _hero(world, _pose(20, 1.75, 0.6, 0))
    var r = Recorder()
    r.add_collision(world, car, NO_ACTOR)
    assert_equal(len(r.collisions), 0)
    _ = r.start(world, "", "Town", False, 0)
    r.add_collision(world, car, NO_ACTOR)
    r.add_collision(world, car, NO_ACTOR)
    r.add_collision(world, NO_ACTOR, car)
    r.add_collision(world, car, ActorId(2))
    assert_equal(len(r.collisions), 3)
    # The second hit of the pair took id 1.
    assert_equal(r.collisions[1].id, 2)
    assert_true(r.collisions[0].database_id2 == NOT_AN_ACTOR)
    assert_true(r.collisions[1].is_actor2_hero)
    with assert_raises():
        r.add_collision(world, ActorId(99), NO_ACTOR)


def test_recorder_calls_do_nothing_when_off() raises:
    var world = _world()
    var r = Recorder()
    r.record(world)
    r.add_light_scene(
        RecordedLightScene(
            SceneLightId(1), 1, Vector4(1, 1, 1, 1), True, LIGHT_GROUP_STREET
        )
    )
    r.add_anim_biker(RecordedAnimBiker(ActorId(1), 1, 1))
    r.add_anim_wheels(RecordedAnimWheels(ActorId(1), List[RecordedWheel]()))
    r.add_physics_control(world, ActorId(1))
    r.add_traffic_light_time(world, ActorId(2))
    assert_equal(len(r.bytes()), 0)
    assert_equal(len(r.light_scenes), 0)
    assert_equal(len(r.bikers), 0)
    assert_equal(len(r.wheels), 0)
    # Without additional data the setups are not kept.
    _ = r.start(world, "", "Town", False)
    r.add_physics_control(world, ActorId(1))
    assert_equal(len(r.physics_controls), 0)
    # The date defaults to now.
    var reader = LogReader(r.bytes())
    assert_true(RecorderInfo.read(reader).date >= now_seconds() - 60)


def test_stop_writes_the_file() raises:
    var world = _world()
    var r = Recorder()
    var path = r.start(
        world, "recorder_test.log", "Town", False, 0, temporary_path("")
    )
    assert_equal(path, temporary_path("recorder_test.log"))
    _ = r.tick(world)
    var bytes = r.bytes()
    r.stop()
    var written = Path(path).read_bytes()
    assert_equal(len(written), len(bytes))
    # A second start stops the first and starts again.
    _ = r.start(world, temporary_path("recorder_test2.log"), "Town", False, 0)
    _ = r.start(world, "", "Town", False, 0)
    assert_true(Path(temporary_path("recorder_test2.log")).exists())
    r.stop()


def test_rotations_are_recorded_as_carla_stores_them() raises:
    var r = recorder_rotation(
        CarlaRotation(
            Angle(10, DEGREE), Angle(270, DEGREE), Angle(-190, DEGREE)
        )
    )
    assert_almost_equal(r.pitch, 10, atol=1e-4)
    assert_almost_equal(r.yaw, -90, atol=1e-4)
    assert_almost_equal(r.roll, 170, atol=1e-4)
    # A pitch past a quarter turn is the same turn with the yaw and roll
    # turned half way round: pitch 120 is pitch 60, yaw +180, roll +180.
    var over = recorder_rotation(
        CarlaRotation(Angle(120, DEGREE), Angle(10, DEGREE), Angle(0, DEGREE))
    )
    assert_almost_equal(over.pitch, 60, atol=1e-3)
    assert_almost_equal(over.yaw, -170, atol=1e-3)
    assert_almost_equal(abs(over.roll), 180, atol=1e-3)
    var under = recorder_rotation(
        CarlaRotation(Angle(-120, DEGREE), Angle(10, DEGREE), Angle(0, DEGREE))
    )
    assert_almost_equal(under.pitch, -60, atol=1e-3)


def test_weather_record_units() raises:
    var w = weather_record(weather_preset("ClearSunset"))
    var preset = weather_preset("ClearSunset")
    assert_almost_equal(
        w.sun_altitude_angle, preset.sun_altitude_angle.to(DEGREE), atol=1e-4
    )
    assert_almost_equal(
        w.fog_distance, preset.fog_distance.to(METER), atol=1e-4
    )


# --- replaying ----------------------------------------------------------------------


struct _Recording(Movable):
    var bytes: List[UInt8]
    var car: List[CarlaTransform]
    var prop: List[CarlaTransform]

    def __init__(out self):
        self.bytes = List[UInt8]()
        self.car = List[CarlaTransform]()
        self.prop = List[CarlaTransform]()


def _prop_pose(k: Int) -> CarlaTransform:
    # Yaw 166 + 8k degrees: it passes 180 between frames 2 and 3.
    return _pose(5 + Float32(k), 5, 1, 166 + 8 * Float32(k))


def _record(frames: Int) raises -> _Recording:
    """A car rolling forward and a prop moved each tick; ids 7 and 8."""
    var world = _world()
    var car = _spawn(world, "vehicle.lincoln.mkz", _pose(20, 1.75, 0.5, 0))
    var prop = _spawn(world, "util.actor.empty", _prop_pose(0))
    world.set_target_velocity(car, Vector3(5, 0, 0))
    var r = Recorder()
    _ = r.start(world, "", "Town", False, 0)
    var out = _Recording()
    for k in range(frames):
        world.set_transform(prop, _prop_pose(k))
        _ = r.tick(world)
        out.car.append(world.get_transform(car))
        out.prop.append(world.get_transform(prop))
    r.stop()
    out.bytes = r.bytes()
    return out^


def test_replay_reproduces_the_recorded_poses() raises:
    var rec = _record(6)
    var world = _world()
    var replay = Replayer()
    var text = replay.replay_bytes(world, rec.bytes.copy(), "mem")
    assert_equal(
        text,
        "Replaying File: mem\nTotal time recorded: 0.25\n"
        + "Replaying from 0 s - 0.25 s (0.25 s) at 1.0x\n"
        + "Ignoring Spectator camera\n",
    )
    assert_true(replay.is_enabled())
    # The car and the prop are made again, as actors 7 and 8.
    assert_equal(len(world.actors), 8)
    assert_equal(world.actor(ActorId(7)).type_id, "vehicle.lincoln.mkz")
    assert_true(replay.mapped(ActorId(7)) == ActorId(7))
    for j in range(1, 5):
        _ = replay.step(world)
        _near_pose(world.get_transform(ActorId(7)), rec.car[j - 1])
        _near_pose(world.get_transform(ActorId(8)), rec.prop[j - 1])
    # At the last frame's time the replay stops and keeps its actors.
    _ = replay.step(world)
    assert_false(replay.is_enabled())
    assert_true(world.is_alive(ActorId(7)))


def test_replay_interpolates_between_frames() raises:
    var rec = _record(6)
    var world = _world()
    var replay = Replayer()
    # Half a frame in: every tick sits halfway through a frame.
    _ = replay.replay_bytes(
        world, rec.bytes.copy(), "mem", Duration(0.025, SECOND)
    )
    # Halfway between yaw 166 + 8(j - 1) and 166 + 8j: 170, 178 and 186,
    # which is -174. From 174 to -178 the yaw passes 180, not 0.
    var yaws: List[Float32] = [170, 178, -174]
    for j in range(1, 4):
        _ = replay.step(world)
        var a = rec.prop[j - 1]
        var b = rec.prop[j]
        var got = world.get_transform(ActorId(8))
        _near(got.location.x, (a.location.x + b.location.x) / 2)
        _near(recorder_rotation(got.rotation).yaw, yaws[j - 1])
        var car = world.get_transform(ActorId(7))
        _near(
            car.location.x,
            (rec.car[j - 1].location.x + rec.car[j].location.x) / 2,
        )


def test_a_fast_replay_takes_the_earlier_pose() raises:
    var rec = _record(8)
    var world = _world()
    var replay = Replayer()
    replay.set_time_factor(2)
    var text = replay.replay_bytes(
        world, rec.bytes.copy(), "mem", Duration(0.025, SECOND)
    )
    assert_true("at 2.0x" in text)
    _ = replay.step(world)
    # Time 0.125 is in frame 3. The replay passed over frame 2 without
    # reading its poses, so the pose is that of frame 1, the last frame
    # read, with no interpolation.
    _near_pose(world.get_transform(ActorId(8)), rec.prop[0])


def test_start_time_and_duration() raises:
    var rec = _record(6)
    var world = _world()
    var replay = Replayer()
    replay.set_ignore_spectator(False)
    replay.set_ignore_hero(True)
    var text = replay.replay_bytes(
        world,
        rec.bytes.copy(),
        "mem",
        Duration(-0.1, SECOND),
        Duration(0.05, SECOND),
    )
    assert_equal(
        text,
        "Replaying File: mem\nTotal time recorded: 0.25\n"
        + "Replaying from 0.15 s - 0.2 s (0.25 s) at 1.0x\n"
        + "Ignoring Hero vehicle\n",
    )
    # A start further back than the recording starts at zero.
    var again = replay.replay_bytes(
        world, rec.bytes.copy(), "mem", Duration(-10, SECOND)
    )
    assert_true("Replaying from 0 s - 0.25 s" in again)


def test_replay_file_and_a_missing_file() raises:
    var rec = _record(3)
    Path(temporary_path("replay_test.log")).write_bytes(rec.bytes)
    var world = _world()
    var replay = Replayer()
    var text = replay.replay_file(
        world, "replay_test.log", saved_dir=temporary_path("")
    )
    assert_true(
        text.startswith(
            "Replaying File: " + temporary_path("replay_test.log") + "\n"
        )
    )
    assert_true(replay.is_enabled())
    var missing = replay.replay_file(world, "/nonexistent/x.log")
    assert_equal(
        missing,
        "Replaying File: /nonexistent/x.log\n"
        + "File /nonexistent/x.log not found on server\n",
    )
    assert_false(replay.is_enabled())
    # A missing file with no replay running.
    _ = replay.replay_file(world, "/nonexistent/x.log")


def test_follow_an_actor() raises:
    var rec = _record(6)
    var world = _world()
    var replay = Replayer()
    var offset = _pose(-6, 0, 3, 0, -10)
    _ = replay.replay_bytes(
        world,
        rec.bytes.copy(),
        "mem",
        follow_id=ActorId(7),
        follow_offset=offset,
    )
    _ = replay.step(world)
    var car = world.get_transform(ActorId(7))
    var spectator = world.get_transform(world.get_spectator())
    # Behind the car by 6 m and 3 m up, pitched down 10 degrees.
    _near(spectator.location.x, car.location.x - 6, 1e-2)
    _near(spectator.location.z, car.location.z + 3, 1e-2)
    _near(recorder_rotation(spectator.rotation).pitch, -10, 1e-2)


def test_heroes_and_the_spectator() raises:
    var world = _world()
    var hero = _hero(world, _pose(20, 1.75, 0.5, 0))
    var other = _spawn(world, "vehicle.mini.cooper", _pose(40, 1.75, 0.5, 0))
    var r = Recorder()
    _ = r.start(world, "", "Town", False, 0)
    world.set_transform(world.get_spectator(), _pose(1, 2, 30, 0))
    for _ in range(4):
        _ = r.tick(world)
    var bytes = r.bytes()
    _ = hero
    _ = other
    # Ignoring the hero: it is not made, and the other car is actor 7.
    var w1 = _world()
    var replay = Replayer()
    replay.set_ignore_hero(True)
    _ = replay.replay_bytes(w1, bytes.copy(), "mem")
    assert_equal(len(w1.actors), 7)
    assert_equal(w1.actor(ActorId(7)).type_id, "vehicle.mini.cooper")
    assert_true(replay.mapped(ActorId(7)) == NO_ACTOR)
    _ = replay.step(w1)
    # Not ignoring the spectator: the world's spectator takes its poses.
    var w2 = _world()
    var second = Replayer()
    second.set_ignore_spectator(False)
    _ = second.replay_bytes(w2, bytes.copy(), "mem")
    _ = second.step(w2)
    _near(w2.get_transform(ActorId(1)).location.z, 30)


def _log_for_replay(world: World) raises -> List[UInt8]:
    """A hand-made recording with every packet the replayer reads."""
    var light = LogVector.from_meters(world.get_location(ActorId(2)))
    var r = Recorder()
    # With additional data, so the walker's bones are written.
    _ = r.begin("", "Town", True, 0)
    var hero: List[RecordedAttribute] = [
        RecordedAttribute(ATTRIBUTE_STRING, "role_name", "hero"),
        RecordedAttribute(ATTRIBUTE_STRING, "color", "not a color"),
        RecordedAttribute(ATTRIBUTE_STRING, "no_such_attribute", "1"),
        RecordedAttribute(ATTRIBUTE_STRING, "base_type", "truck"),
    ]
    r.events_add = [
        RecordedEventAdd(
            ActorId(10),
            VEHICLE_ACTOR,
            LogVector(2000, 175, 50),
            LogVector(0, 0, 0),
            RecordedDescription(1, "vehicle.lincoln.mkz", hero^),
        ),
        RecordedEventAdd(
            ActorId(11),
            WALKER_ACTOR,
            LogVector(4000, -400, 120),
            LogVector(0, 0, 90),
            RecordedDescription(
                2, "walker.pedestrian.0015", List[RecordedAttribute]()
            ),
        ),
        RecordedEventAdd(
            ActorId(20),
            TRAFFIC_LIGHT_ACTOR,
            light,
            LogVector(0, 0, 0),
            RecordedDescription(
                3, "traffic.traffic_light", List[RecordedAttribute]()
            ),
        ),
        RecordedEventAdd(
            ActorId(21),
            TRAFFIC_LIGHT_ACTOR,
            LogVector(-999, -999, -999),
            LogVector(0, 0, 0),
            RecordedDescription(
                3, "traffic.traffic_light", List[RecordedAttribute]()
            ),
        ),
        RecordedEventAdd(
            ActorId(12),
            SENSOR_ACTOR,
            LogVector(100, 0, 200),
            LogVector(0, 0, 0),
            RecordedDescription(
                4, "sensor.other.collision", List[RecordedAttribute]()
            ),
        ),
        RecordedEventAdd(
            ActorId(13),
            OTHER_ACTOR,
            LogVector(0, 0, 0),
            LogVector(0, 0, 0),
            RecordedDescription(
                5, "no.such.blueprint", List[RecordedAttribute]()
            ),
        ),
    ]
    r.events_parent = [
        RecordedEventParent(ActorId(12), ActorId(10)),
        RecordedEventParent(ActorId(11), ActorId(10)),
        RecordedEventParent(ActorId(13), ActorId(10)),
    ]
    r.weathers.append(weather_record(weather_preset("WetCloudySunset")))
    r.positions = [
        RecordedPosition(
            ActorId(10), LogVector(2000, 175, 50), LogVector(0, 0, 0)
        ),
        RecordedPosition(
            ActorId(11), LogVector(4000, -400, 120), LogVector(0, 0, 90)
        ),
    ]
    r.write_frame(0, 0, 0)
    r.states.append(RecordedTrafficLight(ActorId(20), True, 1.25, YELLOW))
    r.states.append(RecordedTrafficLight(ActorId(10), False, 0, RED))
    r.vehicles.append(
        RecordedAnimVehicle(ActorId(10), 0.5, 0.25, 0.75, True, Gear(-1))
    )
    r.walkers.append(RecordedAnimWalker(ActorId(11), 150))
    r.walkers.append(RecordedAnimWalker(ActorId(10), 150))
    r.light_vehicles.append(RecordedLightVehicle(ActorId(10), LIGHT_BRAKE))
    r.doors.append(RecordedDoorVehicle(ActorId(10), DOOR_FRONT_LEFT, True))
    r.light_scenes.append(
        RecordedLightScene(
            SceneLightId(5),
            800,
            Vector4(1, 0.5, 0, 1),
            True,
            LIGHT_GROUP_STREET,
        )
    )
    r.bikers.append(RecordedAnimBiker(ActorId(10), 2, 0.5))
    r.wheels.append(
        RecordedAnimWheels(
            ActorId(10), [RecordedWheel(VehicleWheelLocation(0), 5, 45)]
        )
    )
    r.walker_bones.append(
        RecordedWalkerBones(
            ActorId(11),
            [
                RecordedBone(
                    "crl_hips__C", LogVector(0, 0, 95), LogVector(0, 0, 10)
                )
            ],
        )
    )
    r.walker_bones.append(
        RecordedWalkerBones(ActorId(10), List[RecordedBone]())
    )
    r.walker_bones.append(
        RecordedWalkerBones(ActorId(11), List[RecordedBone]())
    )
    r.positions = [
        RecordedPosition(
            ActorId(10), LogVector(2100, 175, 50), LogVector(0, 0, 0)
        ),
        RecordedPosition(
            ActorId(11), LogVector(4000, -300, 120), LogVector(0, 0, 90)
        ),
    ]
    r.write_frame(0.05, 0.05, 0)
    r.events_del.append(RecordedEventDel(ActorId(11)))
    # An actor that was never made is removed too: nothing happens.
    r.events_del.append(RecordedEventDel(ActorId(21)))
    # A prop appears: it has no pose in the frame before.
    r.events_add.append(
        RecordedEventAdd(
            ActorId(14),
            OTHER_ACTOR,
            LogVector(500, 500, 100),
            LogVector(0, 0, 0),
            RecordedDescription(
                6, "util.actor.empty", List[RecordedAttribute]()
            ),
        )
    )
    r.doors.append(RecordedDoorVehicle(ActorId(10), DOOR_FRONT_LEFT, False))
    r.weathers.append(weather_record(weather_preset("ClearNoon")))
    r.positions = [
        RecordedPosition(
            ActorId(10), LogVector(2200, 175, 50), LogVector(0, 0, 0)
        ),
    ]
    r.write_frame(0.05, 0.1, 0)
    r.positions = [
        RecordedPosition(
            ActorId(10), LogVector(2300, 175, 50), LogVector(0, 0, 0)
        ),
    ]
    r.write_frame(0.05, 0.15, 0)
    return r.bytes()


def test_replay_sets_what_each_packet_holds() raises:
    var world = _world()
    var bytes = _log_for_replay(world)
    var replay = Replayer()
    _ = replay.replay_bytes(
        world, bytes^, "mem", replay_sensors=True, replay_weather=True
    )
    # The car, the walker and the sensor are made; the light is found at
    # its place, and the light with no match and the unknown blueprint are
    # not made.
    var car = replay.mapped(ActorId(10))
    var walker = replay.mapped(ActorId(11))
    var sensor = replay.mapped(ActorId(12))
    assert_true(car == ActorId(7))
    assert_true(walker == ActorId(8))
    assert_true(sensor == ActorId(9))
    assert_true(replay.mapped(ActorId(20)) == ActorId(2))
    assert_true(replay.mapped(ActorId(21)) == NO_ACTOR)
    assert_true(replay.mapped(ActorId(13)) == NO_ACTOR)
    # A refused color and an unknown attribute keep the blueprint's; the
    # role name is set. A fixed attribute is not changed.
    assert_equal(world.actor(car).role_name(), "hero")
    assert_equal(world.actor(car).attribute("base_type").value().value, "car")
    # The sensor rides on the car, 1 m ahead and 2 m up; the walker cannot.
    assert_true(world.actor(sensor).parent == car)
    assert_true(world.actor(walker).parent == NO_ACTOR)
    assert_equal(world.get_weather(), weather_preset("WetCloudySunset"))
    _ = replay.step(world)
    # Frame 2's records.
    assert_true(world.get_traffic_light_state_of(ActorId(2)) == YELLOW)
    assert_true(world.is_frozen(ActorId(2)))
    assert_almost_equal(
        world.get_elapsed_time(ActorId(2)).to(SECOND), 1.25, atol=1e-6
    )
    var control = world.get_control(car)
    assert_equal(control.steer, 0.5)
    assert_equal(control.brake, 0.75)
    assert_true(control.hand_brake and control.reverse)
    assert_equal(control.gear.value, -1)
    assert_true(world.get_light_state(car) == LIGHT_BRAKE)
    assert_true(world.is_door_open(car, DOOR_FRONT_LEFT))
    _near(world.get_walker_control(walker).speed.value, 1.5)
    var bones = world.get_bones_transform(walker)
    assert_equal(bones.bone_transforms[0].bone_name, "crl_hips__C")
    _near(bones.bone_transforms[0].relative.location.z, 0.95)
    assert_equal(replay.scene_lights[5].intensity, 800)
    assert_equal(replay.bikers[7].forward_speed, 2)
    assert_equal(replay.wheels[7].wheels[0].tire_rotation, 45)
    assert_equal(replay.visual_time, 0.05)
    # The first frame's poses: there was no frame before them.
    _near(world.get_location(car).x, 20)
    _ = replay.step(world)
    # Frame 3: the walker goes, the door shuts, the weather changes.
    assert_false(world.is_alive(walker))
    assert_false(world.is_door_open(car, DOOR_FRONT_LEFT))
    assert_equal(world.get_weather(), weather_preset("ClearNoon"))
    _near(world.get_location(car).x, 21)
    # Stopping hands the car back: gravity, rest and first gear.
    replay.stop(world, True)
    assert_false(replay.is_enabled())
    assert_equal(world.get_control(car).gear.value, 1)
    # A second stop does nothing.
    replay.stop(world)


def test_stopping_runs_the_rest_of_the_events() raises:
    var world = _world()
    var bytes = _log_for_replay(world)
    var replay = Replayer()
    _ = replay.replay_bytes(world, bytes^, "mem")
    var walker = replay.mapped(ActorId(11))
    assert_true(world.is_alive(walker))
    # The sensor was not replayed, nor the weather.
    assert_true(replay.mapped(ActorId(12)) == NO_ACTOR)
    assert_equal(world.get_weather(), WeatherParameters())
    replay.stop(world)
    assert_false(world.is_alive(walker))


def test_ignore_hero_leaves_the_hero_alone() raises:
    var world = _world()
    var bytes = _log_for_replay(world)
    var replay = Replayer()
    replay.set_ignore_hero(True)
    _ = replay.replay_bytes(world, bytes^, "mem")
    # The hero is not made; the walker is actor 7.
    assert_true(replay.mapped(ActorId(10)) == NO_ACTOR)
    assert_true(replay.mapped(ActorId(11)) == ActorId(7))
    _ = replay.step(world)
    replay.stop(world, True)


def test_a_replay_started_while_one_runs_stops_it() raises:
    var world = _world()
    var bytes = _log_for_replay(world)
    var replay = Replayer()
    _ = replay.replay_bytes(world, bytes.copy(), "mem")
    _ = replay.replay_bytes(world, bytes^, "mem")
    assert_true(replay.is_enabled())
    # A tick of the replay alone, without the world's.
    replay.tick(world, Duration(0.05, SECOND))
    replay.set_time_factor(1)


def test_a_log_cut_short_replays_to_its_end() raises:
    var world = _world()
    var bytes = _log_for_replay(world)
    # Drop the last FrameEnd: the last frame ends at its last packet.
    for _ in range(5):
        _ = bytes.pop()
    var replay = Replayer()
    var text = replay.replay_bytes(world, bytes^, "mem")
    assert_true("Total time recorded: 0.15" in text)
    for _ in range(5):
        _ = replay.step(world)
    assert_false(replay.is_enabled())


# --- the helper ---------------------------------------------------------------------


def test_helper_edges() raises:
    var world = _world()
    var car = _spawn(world, "vehicle.lincoln.mkz", _pose(20, 1.75, 0.5, 0))
    var prop = _spawn(world, "util.actor.empty", _pose(1, 1, 1, 0))
    var walker = _spawn(world, "walker.pedestrian.0015", _pose(40, -4, 1.2, 0))
    # A light by its place, cut to whole centimeters.
    var at = LogVector.from_meters(world.get_location(ActorId(3)))
    var nudged = LogVector(at.x + 0.25, at.y, at.z)
    assert_true(find_traffic_sign_at(world, nudged) == ActorId(3))
    assert_true(find_traffic_sign_at(world, LogVector(1, 2, 3)) == NO_ACTOR)
    assert_true(
        find_traffic_sign_at(world, LogVector(at.x, at.y + 10000, at.z))
        == NO_ACTOR
    )
    assert_true(
        find_traffic_sign_at(world, LogVector(at.x, at.y, at.z + 10000))
        == NO_ACTOR
    )
    process_door_vehicle(world, RecordedDoorVehicle(car, VehicleDoor(99), True))
    assert_false(world.is_door_open(car, DOOR_FRONT_LEFT))
    # Parents: a dead child or parent, or a vehicle child, is refused.
    assert_false(process_event_parent(world, ActorId(99), car))
    assert_false(process_event_parent(world, prop, ActorId(99)))
    assert_false(process_event_parent(world, car, prop))
    assert_true(process_event_parent(world, prop, car))
    # A pose for an actor that is not alive.
    var p = RecordedPosition(
        ActorId(99), LogVector(0, 0, 0), LogVector(0, 0, 0)
    )
    assert_false(process_position(world, p, p, 0))
    # A light state for an actor that is not a light, or not alive.
    assert_false(
        process_state_traffic_light(
            world, RecordedTrafficLight(car, False, 0, RED)
        )
    )
    assert_false(
        process_state_traffic_light(
            world, RecordedTrafficLight(ActorId(99), False, 0, RED)
        )
    )
    # The camera follows only a living actor.
    assert_false(set_camera_position(world, ActorId(99), _pose(0, 0, 0, 0)))
    # An ignored hero keeps its gravity.
    var hero: List[RecordedAttribute] = [
        RecordedAttribute(ATTRIBUTE_STRING, "role_name", "hero")
    ]
    var ignored = process_event_add(
        world,
        LogVector(9000, 175, 50),
        LogVector(0, 0, 0),
        RecordedDescription(1, "vehicle.lincoln.mkz", hero^),
        True,
        True,
        False,
    )
    assert_equal(ignored[0], IGNORED)
    # A walker whose place is taken is not made.
    var blocked = process_event_add(
        world,
        LogVector.from_meters(world.get_location(walker)),
        LogVector(0, 0, 0),
        RecordedDescription(
            2, "walker.pedestrian.0015", List[RecordedAttribute]()
        ),
        False,
        True,
        False,
    )
    _ = blocked
    # The spectator is not a blueprint.
    var spectator = process_event_add(
        world,
        LogVector(0, 0, 0),
        LogVector(0, 0, 0),
        RecordedDescription(0, "spectator", List[RecordedAttribute]()),
        False,
        False,
        False,
    )
    assert_equal(spectator[0], NOT_CREATED)


def test_angles_move_the_shorter_way() raises:
    assert_almost_equal(lerp_angle(170, -170, 0.5), 180, atol=1e-9)
    assert_almost_equal(lerp_angle(-170, 170, 0.5), -180, atol=1e-9)
    assert_almost_equal(lerp_angle(10, 50, 0.25), 20, atol=1e-9)
    # A turn of more than a whole turn is wrapped first.
    assert_almost_equal(lerp_angle(0, 370, 0.5), 5, atol=1e-9)
    assert_almost_equal(lerp_angle(0, -540, 1), 180, atol=1e-9)
    var a = RecordedPosition(
        ActorId(1), LogVector(0, 0, 0), LogVector(0, 0, 10)
    )
    var b = RecordedPosition(
        ActorId(1), LogVector(100, 0, 0), LogVector(0, 0, 30)
    )
    var mid = interpolated_transform(a, b, 0.5)
    _near(mid.location.x, 0.5)
    _near(mid.rotation.yaw, 20)
    var first = interpolated_transform(a, b, 0)
    _near(first.location.x, 0)


def test_recording_edges() raises:
    var world = _world()
    # A light with no box has no trigger volume.
    world.traffic_lights.lights[0].boxes = List[TriggerBox]()
    # An attribute with no id is not recorded.
    world.actors[0].attributes.append(
        ActorAttributeValue("", ATTRIBUTE_STRING, "x")
    )
    # A vehicle with no doors, a walker with no bones and a dead actor.
    var truck = _spawn(world, "vehicle.carlacola.actors", _pose(60, 1.75, 1, 0))
    var walker = _spawn(world, "walker.pedestrian.0015", _pose(40, -4, 1.2, 0))
    var gone = _spawn(world, "util.actor.empty", _pose(0, 0, 5, 0))
    _ = world.destroy_actor(gone)
    var car = _spawn(world, "vehicle.lincoln.mkz", _pose(20, 1.75, 0.5, 0))
    var r = Recorder()
    _ = r.start(world, "", "Town", True, 0)
    assert_equal(len(r.trigger_volumes), 4)
    for e in r.events_add:
        if e.database_id.value == 1:
            assert_equal(len(e.description.attributes), 0)
    # A light with no controller, then one whose controller has no group,
    # has no state.
    world.traffic_lights.lights[0].controller = -1
    _ = r.tick(world)
    world.traffic_lights.lights[0].controller = 0
    var group = world.traffic_lights.controllers[0].group
    world.traffic_lights.controllers[0].group = -1
    _ = r.tick(world)
    world.traffic_lights.controllers[0].group = group
    # A vehicle with doors goes.
    _ = world.destroy_actor(car)
    _ = r.tick(world)
    var bytes = r.bytes()
    var packets = _packets(bytes)
    for f in range(1, 3):
        var state = _reader_at(bytes, _find(packets, f, PACKET_STATE.value))
        assert_equal(state.u16(), 0)
    var gone3 = _reader_at(bytes, _find(packets, 3, PACKET_EVENT_DEL.value))
    assert_equal(gone3.u16(), 1)
    assert_true(RecordedEventDel.read(gone3).database_id == car)
    var bones = _reader_at(bytes, _find(packets, 1, PACKET_WALKER_BONES.value))
    assert_equal(bones.u16(), 1)
    assert_equal(len(RecordedWalkerBones.read(bones).bones), 0)
    _ = truck
    _ = walker


def test_a_slow_replay_stays_in_its_frame() raises:
    var rec = _record(4)
    var world = _world()
    var replay = Replayer()
    replay.set_time_factor(0.5)
    _ = replay.replay_bytes(world, rec.bytes.copy(), "mem")
    # Ticks of 0.025 s: every other one stays in the frame it is in, and
    # moves halfway from the frame before.
    _ = replay.step(world)
    _ = replay.step(world)
    _ = replay.step(world)
    # Time 0.075 is halfway through frame 2: between frames 1 and 2.
    _near(
        world.get_location(ActorId(8)).x,
        (rec.prop[0].location.x + rec.prop[1].location.x) / 2,
    )
    replay.stop(world)
    # A stopped replay does not move.
    replay.tick(world, Duration(0.05, SECOND))
    _ = replay.step(world)


def test_ignoring_heroes_part_way() raises:
    var world = _world()
    var bytes = _log_for_replay(world)
    var replay = Replayer()
    _ = replay.replay_bytes(world, bytes^, "mem")
    var car = replay.mapped(ActorId(10))
    var walker = replay.mapped(ActorId(11))
    var before = world.get_control(car)
    # The car is a hero: from now on its records are skipped.
    replay.set_ignore_hero(True)
    _ = replay.step(world)
    assert_equal(world.get_control(car).steer, before.steer)
    assert_true(world.is_alive(walker))
    # Another vehicle, not a hero, gets first gear at the end; the hero
    # does not.
    var other = _spawn(world, "vehicle.mini.cooper", _pose(80, 1.75, 0.5, 0))
    replay.stop(world, True)
    assert_equal(world.get_control(other).gear.value, 1)


def _empty_packets_log() raises -> List[UInt8]:
    var r = Recorder()
    _ = r.begin("", "M", False, 0)
    r.write_frame(0, 0, 0)
    r.frames.set_frame(0.05)
    r.frames.write_start(r.out)
    write_packet(r.out, PACKET_SCENE_LIGHT, [UInt8(0), UInt8(0)])
    write_packet(r.out, PACKET_WEATHER, [UInt8(0), UInt8(0)])
    write_packet(r.out, PACKET_POSITION, [UInt8(0), UInt8(0)])
    r.frames.write_end(r.out)
    r.write_frame(0.05, 0, 0)
    return r.bytes()


def test_a_replay_of_no_actors() raises:
    var world = _world()
    var replay = Replayer()
    _ = replay.replay_bytes(world, _empty_packets_log(), "mem")
    _ = replay.step(world)
    replay.stop(world)
    assert_equal(len(world.actors), 6)


def test_helper_spawn_and_light_edges() raises:
    var world = _world()
    var none: List[RecordedAttribute] = []
    var first = process_event_add(
        world,
        LogVector(9000, 175, 50),
        LogVector(0, 0, 0),
        RecordedDescription(1, "vehicle.lincoln.mkz", none.copy()),
        False,
        True,
        False,
    )
    # A car already 1000 m above the place blocks the way.
    _ = _spawn(world, "vehicle.mini.cooper", _pose(90, 1.75, 1000.5, 0))
    var second = process_event_add(
        world,
        LogVector(9000, 175, 50),
        LogVector(0, 0, 0),
        RecordedDescription(1, "vehicle.lincoln.mkz", none^),
        False,
        True,
        False,
    )
    assert_true(first[1] != NO_ACTOR)
    assert_equal(second[0], NOT_CREATED)
    # A light with no controller takes only its state; one whose
    # controller has no group keeps its freeze.
    world.traffic_lights.lights[0].controller = -1
    assert_true(
        process_state_traffic_light(
            world, RecordedTrafficLight(ActorId(2), True, 3, RED)
        )
    )
    assert_true(world.get_traffic_light_state_of(ActorId(2)) == RED)
    world.traffic_lights.lights[0].controller = 0
    world.traffic_lights.controllers[0].group = -1
    assert_true(
        process_state_traffic_light(
            world, RecordedTrafficLight(ActorId(2), True, 3, GREEN)
        )
    )
    assert_false(world.traffic_lights.groups[0].frozen)


def test_camera_follow_refuses_an_invalid_spectator_registry() raises:
    var world = _world()
    var car = _spawn(world, "vehicle.lincoln.mkz", _pose(20, 1.75, 0.5, 0))
    var spectator = world.get_spectator()
    var before = world.get_transform(spectator)
    assert_false(world.destroy_actor(spectator))
    # This is an invalid-registry boundary, not a normal World lifecycle:
    # the public mutable field no longer names the protected spectator.
    world.spectator = NO_ACTOR
    assert_false(set_camera_position(world, car, _pose(0, 0, 0, 0)))
    assert_true(world.get_transform(spectator).location == before.location)
    world.spectator = spectator
    assert_true(set_camera_position(world, car, _pose(0, 0, 0, 0)))
    assert_true(
        world.get_transform(spectator).location == world.get_location(car)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
