# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's recorder file and its three queries, byte for byte.

The expected bytes and texts come from outside this port. `ref.cpp`, a
C++ program outside the repository, holds CARLA's packet writers, its
frame writer and its three query functions, copied from CARLA's
simulator plugin with the standard library's string and a struct of
three doubles in place of the engine's types. It is built with GCC on
x86-64 Linux and run with `TZ=UTC`. It writes three hand-made
recordings and prints each query:

- `full`: three frames with every packet, additional data included.
- `collisions`: seven frames of collisions between vehicles, a hero, a
  walker, a light, a sign, a sensor and something that is not an actor.
- `blocked`: eleven frames of actors that stop and move.

This suite builds the same recordings with the port and compares the
bytes: the whole `full` file, and the length and FNV-1a hash of the
other two. It compares every query's text in full. The number formats
are checked against Python's `%g` and `%.*f`, which round as the GNU C
library does, and the dates against Python's `time.strftime` in UTC.
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    OTHER_ACTOR,
    RED,
    SENSOR_ACTOR,
    TRAFFIC_LIGHT_ACTOR,
    TRAFFIC_SIGN_ACTOR,
    VEHICLE_ACTOR,
    WALKER_ACTOR,
    YELLOW,
    ActorKind,
    TrafficLightState,
)
from extensions.carla.blueprint import (
    ATTRIBUTE_FLOAT,
    ATTRIBUTE_RGB_COLOR,
    ATTRIBUTE_STRING,
    ActorAttributeType,
)
from extensions.carla.physics.vehicle_control import Gear
from extensions.carla.physics.vehicle_physics import (
    AxleType,
    DifferentialType,
    SweepShape,
    SweepType,
    TorqueCombineMethod,
    VehiclePhysicsControl,
    WheelPhysicsControl,
)
from extensions.carla.recorder import Recorder
from extensions.carla.recorder_format import (
    c_date,
    c_fixed,
    c_general,
    pad_left,
    pad_right,
)
from extensions.carla.recorder_packets import (
    LIGHT_GROUP_STREET,
    LogReader,
    LogVector,
    NOT_AN_ACTOR,
    PACKET_EVENT_ADD,
    PACKET_FRAME_START,
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
    RecorderPacketId,
    SceneLightGroup,
    SceneLightId,
    PACKET_VEHICLE_DOOR,
    collisions_packet,
    events_add_packet,
    events_del_packet,
    frame_counter_packet,
    positions_packet,
    time_packet,
    walker_bones_packet,
    write_packet,
    write_string,
)
from extensions.carla.recorder_physics import (
    RecordedPhysicsControl,
    RecordedWheelPhysics,
    physics_control_text,
)
from extensions.carla.recorder_query import (
    CATEGORY_ANY,
    CATEGORY_HERO,
    CATEGORY_OTHER,
    CATEGORY_TRAFFIC_LIGHT,
    CATEGORY_VEHICLE,
    CATEGORY_WALKER,
    CollisionCategory,
    light_names,
    query_blocked,
    query_collisions,
    query_info,
    recorder_file_path,
    show_recorder_actors_blocked,
    show_recorder_collisions,
    show_recorder_file_info,
)
from extensions.carla.sensor_data import ByteWriter
from extensions.carla.vehicle import (
    DOOR_ALL,
    DOOR_FRONT_LEFT,
    LIGHT_BRAKE,
    LIGHT_FOG,
    LIGHT_INTERIOR,
    LIGHT_POSITION,
    VehicleDoor,
    VehicleLightState,
    VehicleWheelLocation,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.memory import bitcast
from std.os import makedirs
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import CENTIMETER, METER, SECOND, Duration, Length

# The recordings' date: 2026-09-21 14:13:20 UTC.
comptime DATE = 1790000000


# --- number and date formats -------------------------------------------------------


def test_general_numbers_match_printf_g() raises:
    # Python's '%g' % x for each input.
    assert_equal(c_general(0.0), "0")
    assert_equal(c_general(-0.0), "-0")
    assert_equal(c_general(1.0), "1")
    assert_equal(c_general(0.5), "0.5")
    assert_equal(c_general(1234.5678), "1234.57")
    # A tie at the sixth digit goes to the even digit.
    assert_equal(c_general(1234565.0), "1.23456e+06")
    assert_equal(c_general(999999.5), "1e+06")
    assert_equal(c_general(0.0001), "0.0001")
    assert_equal(c_general(0.00001234567), "1.23457e-05")
    assert_equal(c_general(1e-300), "1e-300")
    assert_equal(c_general(5e-324), "4.94066e-324")
    assert_equal(c_general(1.7976931348623157e308), "1.79769e+308")
    assert_equal(c_general(-2.5), "-2.5")
    assert_equal(c_general(123456.0), "123456")
    assert_equal(c_general(1234567.0), "1.23457e+06")
    assert_equal(c_general(0.1), "0.1")
    assert_equal(c_general(100000.0), "100000")
    assert_equal(c_general(0.15), "0.15")
    assert_equal(c_general(Float64(Float32(0.3))), "0.3")
    assert_equal(c_general(1e21), "1e+21")
    assert_equal(c_general(Float64(Float32(9.9999995e-5))), "0.0001")
    # glibc's text for the numbers that are not finite.
    var inf = Float64(1) / Float64(0)
    assert_equal(c_general(inf), "inf")
    assert_equal(c_general(-inf), "-inf")
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    var minus_nan = bitcast[DType.float64](UInt64(0xFFF8000000000000))
    assert_equal(c_general(nan), "nan")
    assert_equal(c_general(minus_nan), "-nan")


def test_fixed_numbers_match_printf_f() raises:
    # Python's '%.*f' % (p, x) for each input.
    assert_equal(c_fixed(2.5, 0), "2")
    assert_equal(c_fixed(3.5, 0), "4")
    assert_equal(c_fixed(-0.4, 0), "-0")
    assert_equal(c_fixed(0.5, 0), "0")
    assert_equal(c_fixed(1.5, 1), "1.5")
    assert_equal(c_fixed(0.05, 1), "0.1")
    assert_equal(c_fixed(1.0, 1), "1.0")
    assert_equal(c_fixed(1234.5678, 6), "1234.567800")
    assert_equal(c_fixed(-80.0, 6), "-80.000000")
    assert_equal(c_fixed(0.125, 2), "0.12")
    assert_equal(c_fixed(1e22, 0), "10000000000000000000000")
    assert_equal(c_fixed(5e-324, 6), "0.000000")
    assert_equal(c_fixed(0.6, 0), "1")
    assert_equal(c_fixed(0.96, 1), "1.0")
    assert_equal(c_fixed(9.995, 2), "9.99")
    assert_equal(c_fixed(99.5, 0), "100")
    assert_equal(c_fixed(0.0, 3), "0.000")
    assert_equal(c_fixed(0.001, 3), "0.001")
    var inf = Float64(1) / Float64(0)
    assert_equal(c_fixed(-inf, 0), "-inf")
    with assert_raises():
        _ = c_fixed(1, -1)
    with assert_raises():
        _ = c_fixed(1, 61)


def test_padding_and_dates() raises:
    assert_equal(pad_right("Id", 6), "    Id")
    assert_equal(pad_left("Id", 6), "Id    ")
    assert_equal(pad_right("toolong", 3), "toolong")
    assert_equal(pad_left("toolong", 3), "toolong")
    # Python's time.strftime('%m/%d/%y %H:%M:%S', time.gmtime(t)).
    assert_equal(c_date(0), "01/01/70 00:00:00")
    assert_equal(c_date(1790000000), "09/21/26 14:13:20")
    assert_equal(c_date(1790046861), "09/22/26 03:14:21")
    assert_equal(c_date(951782400), "02/29/00 00:00:00")
    assert_equal(c_date(4102444799), "12/31/99 23:59:59")
    assert_equal(c_date(-1), "12/31/69 23:59:59")


# --- building the reference recordings ---------------------------------------------


def _add(
    id: Int,
    kind: ActorKind,
    location: LogVector,
    rotation: LogVector,
    uid: Int,
    blueprint: String,
    var attributes: List[RecordedAttribute] = List[RecordedAttribute](),
) -> RecordedEventAdd:
    return RecordedEventAdd(
        ActorId(id),
        kind,
        location,
        rotation,
        RecordedDescription(uid, blueprint, attributes^),
    )


def _pos(id: Int, location: LogVector, rotation: LogVector) -> RecordedPosition:
    return RecordedPosition(ActorId(id), location, rotation)


def _zero() -> LogVector:
    return LogVector(0, 0, 0)


def _carla_wheel() -> RecordedWheelPhysics:
    """CARLA's default `rpc::WheelPhysicsControl`, in its own units."""
    return RecordedWheelPhysics(
        AxleType(0),
        Vector3(0, 0, 0),
        30,
        30,
        30,
        1000,
        3,
        1,
        20,
        20,
        70,
        True,
        True,
        True,
        True,
        False,
        False,
        30,
        TorqueCombineMethod(0),
        Vector3(0, 0, -1),
        Vector3(0, 0, 0),
        10,
        10,
        0.5,
        0.5,
        250,
        50,
        0,
        0.15,
        SweepShape(0),
        SweepType(0),
        1500,
        3000,
        -1,
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
    )


def _carla_physics(id: Int) -> RecordedPhysicsControl:
    """CARLA's default `rpc::VehiclePhysicsControl`, with no wheel."""
    return RecordedPhysicsControl(
        ActorId(id),
        300,
        5000,
        1,
        1,
        1,
        600,
        DifferentialType(0),
        0.5,
        True,
        0.5,
        4,
        4500,
        2000,
        0.9,
        1000,
        0.3,
        Vector3(0, 0, 0),
        180,
        140,
        0.3,
        0,
        Vector3(1, 1, 1),
        10,
        0.866,
        False,
        [Vector2(0, 500), Vector2(5000, 500)],
        [2.85, 2.02, 1.35, 1.0, 2.85, 2.02, 1.35, 1.0],
        [2.86, 2.86],
        [Vector2(0, 1), Vector2(10, 0.5)],
        List[RecordedWheelPhysics](),
    )


def _full_log() raises -> List[UInt8]:
    """The `full` recording of the reference program."""
    var r = Recorder()
    _ = r.begin("", "Town10HD_Opt", True, DATE)
    # Frame 1.
    r.events_add.append(_add(1, OTHER_ACTOR, _zero(), _zero(), 0, "spectator"))
    r.events_add.append(
        _add(
            2,
            VEHICLE_ACTOR,
            LogVector(1250.5, -300.25, 10),
            LogVector(0.5, -1.25, 90),
            17,
            "vehicle.tesla.model3",
            [
                RecordedAttribute(ATTRIBUTE_RGB_COLOR, "color", "255,0,0"),
                RecordedAttribute(ATTRIBUTE_STRING, "role_name", "hero"),
            ],
        )
    )
    r.events_add.append(
        _add(
            3,
            WALKER_ACTOR,
            LogVector(500, 200, 100),
            LogVector(0, 0, -45),
            40,
            "walker.pedestrian.0001",
            [RecordedAttribute(ATTRIBUTE_FLOAT, "speed", "1.4")],
        )
    )
    r.events_add.append(
        _add(
            4,
            TRAFFIC_LIGHT_ACTOR,
            LogVector(1000, 1000, 0),
            LogVector(0, 0, 180),
            90,
            "traffic.traffic_light",
        )
    )
    r.events_add.append(
        _add(
            5,
            SENSOR_ACTOR,
            LogVector(150, 0, 240),
            LogVector(0, -15, 0),
            60,
            "sensor.other.collision",
        )
    )
    r.events_parent.append(RecordedEventParent(ActorId(5), ActorId(2)))
    r.positions = [
        _pos(1, _zero(), _zero()),
        _pos(2, LogVector(1250.5, -300.25, 10), LogVector(0.5, -1.25, 90)),
        _pos(3, LogVector(500, 200, 100), LogVector(0, 0, -45)),
    ]
    r.states.append(RecordedTrafficLight(ActorId(4), False, 1.5, GREEN))
    r.vehicles.append(
        RecordedAnimVehicle(ActorId(2), 0.25, 0.75, 0, False, Gear(1))
    )
    r.walkers.append(RecordedAnimWalker(ActorId(3), 140))
    r.light_vehicles.append(
        RecordedLightVehicle(
            ActorId(2), LIGHT_POSITION | LIGHT_BRAKE | LIGHT_INTERIOR
        )
    )
    r.add_light_scene(
        RecordedLightScene(
            SceneLightId(7),
            1000,
            Vector4(1, 0.5, 0.25, 1),
            True,
            LIGHT_GROUP_STREET,
        )
    )
    r.add_anim_wheels(
        RecordedAnimWheels(
            ActorId(2),
            [
                RecordedWheel(VehicleWheelLocation(0), 10, 45),
                RecordedWheel(VehicleWheelLocation(1), -10, 90.5),
            ],
        )
    )
    r.add_anim_biker(RecordedAnimBiker(ActorId(2), 3.5, 0.5))
    r.weathers.append(
        RecordedWeather(
            10, 0, 0, 5, 45, 30, 0, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0
        )
    )
    r.kinematics.append(
        RecordedKinematics(ActorId(2), LogVector(1, 2, 3), LogVector(0, 0, 45))
    )
    r.bounding_boxes.append(
        RecordedBoundingBox(
            ActorId(2), LogVector(0, 0, 75), LogVector(240, 100, 75)
        )
    )
    r.bounding_boxes.append(
        RecordedBoundingBox(ActorId(3), _zero(), LogVector(25, 25, 90))
    )
    r.trigger_volumes.append(
        RecordedBoundingBox(
            ActorId(4), LogVector(1050, 1000, 100), LogVector(150, 87.5, 100)
        )
    )
    var p = _carla_physics(2)
    p.differential_type = DifferentialType(3)
    p.mass = 1845.5
    p.center_of_mass = Vector3(10, 0, -25)
    p.torque_curve = [
        Vector2(0, 400),
        Vector2(1890.76, 500),
        Vector2(5729.58, 400),
    ]
    var front = _carla_wheel()
    front.axle_type = AxleType(1)
    front.offset = Vector3(135, -80, 30)
    front.max_steer_angle = 69.5
    front.wheel_index = 0
    front.abs_enabled = True
    var rear = _carla_wheel()
    rear.axle_type = AxleType(2)
    rear.offset = Vector3(-135, -80, 30)
    rear.affected_by_steering = False
    rear.wheel_index = 1
    rear.sweep_type = SweepType(1)
    rear.location = Vector3(1.5, 2.25, -3)
    rear.suspension_smoothing = 3
    p.wheels.append(front^)
    p.wheels.append(rear^)
    r.physics_controls.append(p^)
    r.traffic_light_times.append(RecordedTrafficLightTime(ActorId(4), 10, 3, 2))
    r.walker_bones.append(
        RecordedWalkerBones(
            ActorId(3),
            [
                RecordedBone("crl_root", _zero(), _zero()),
                RecordedBone(
                    "crl_hips__C",
                    LogVector(0, 1.5, 95.25),
                    LogVector(-90, 0, 90),
                ),
            ],
        )
    )
    r.write_frame(0.05, 0.0, 0.001234)
    # Frame 2.
    r.collisions.append(
        RecordedCollision(0, ActorId(2), NOT_AN_ACTOR, True, False)
    )
    r.doors.append(RecordedDoorVehicle(ActorId(2), DOOR_FRONT_LEFT, True))
    r.doors.append(RecordedDoorVehicle(ActorId(2), DOOR_ALL, False))
    r.positions = [
        _pos(1, _zero(), _zero()),
        _pos(2, LogVector(1300.5, -300.25, 10), LogVector(0.5, -1.25, 95)),
        _pos(3, LogVector(510, 200, 100), LogVector(0, 0, -45)),
    ]
    r.states.append(RecordedTrafficLight(ActorId(4), True, 1.55, YELLOW))
    r.vehicles.append(
        RecordedAnimVehicle(ActorId(2), -0.125, 0.5, 0.25, True, Gear(-1))
    )
    r.walkers.append(RecordedAnimWalker(ActorId(3), 0))
    r.light_vehicles.append(
        RecordedLightVehicle(ActorId(2), VehicleLightState(0))
    )
    r.kinematics.append(
        RecordedKinematics(ActorId(2), LogVector(10, 0, 0), _zero())
    )
    r.write_frame(0.05, 0.05, 0.5)
    # Frame 3.
    r.events_del.append(RecordedEventDel(ActorId(3)))
    r.collisions.append(
        RecordedCollision(1, ActorId(2), ActorId(4), True, False)
    )
    r.positions = [
        _pos(1, _zero(), _zero()),
        _pos(2, LogVector(1350.5, -300.25, 10), LogVector(0.5, -1.25, 100)),
    ]
    r.states.append(RecordedTrafficLight(ActorId(4), True, 1.6, RED))
    r.vehicles.append(RecordedAnimVehicle(ActorId(2), 0, 1, 0, False, Gear(2)))
    r.light_vehicles.append(
        RecordedLightVehicle(ActorId(2), VehicleLightState(0xFFFFFFFF))
    )
    r.weathers.append(
        RecordedWeather(
            80, 60, 40, 30, 300, -10.5, 20, 2.5, 0.2, 55, 0.5, 0.1, 0.2, 1234567
        )
    )
    r.write_frame(0.1, 0.1, 1e-7)
    return r.bytes()


def _collisions_log() raises -> List[UInt8]:
    """The `collisions` recording of the reference program."""
    var r = Recorder()
    _ = r.begin("", "Town01", False, DATE + 3600 * 13 + 61)
    var hero: List[RecordedAttribute] = [
        RecordedAttribute(ATTRIBUTE_STRING, "role_name", "hero")
    ]
    r.events_add = [
        _add(
            2, VEHICLE_ACTOR, _zero(), _zero(), 1, "vehicle.lincoln.mkz", hero^
        ),
        _add(3, WALKER_ACTOR, _zero(), _zero(), 2, "walker.pedestrian.0002"),
        _add(6, VEHICLE_ACTOR, _zero(), _zero(), 3, "vehicle.audi.tt"),
        _add(
            4, TRAFFIC_LIGHT_ACTOR, _zero(), _zero(), 4, "traffic.traffic_light"
        ),
        _add(8, TRAFFIC_SIGN_ACTOR, _zero(), _zero(), 5, "traffic.stop"),
        _add(9, SENSOR_ACTOR, _zero(), _zero(), 6, "sensor.other.collision"),
    ]
    r.write_frame(0, 0, 0)
    var deltas: List[Float64] = [2.5, 1.0, 0.25, 0.25, 0.5, 1.0]
    var none = NOT_AN_ACTOR
    var frames: List[List[RecordedCollision]] = [
        [RecordedCollision(0, ActorId(2), ActorId(6), True, False)],
        [
            RecordedCollision(1, ActorId(2), ActorId(6), True, False),
            RecordedCollision(2, ActorId(3), none, False, False),
        ],
        [
            RecordedCollision(3, ActorId(6), ActorId(2), False, True),
            RecordedCollision(4, ActorId(4), ActorId(3), False, False),
        ],
        [
            RecordedCollision(5, ActorId(2), ActorId(6), True, False),
            RecordedCollision(6, ActorId(9), ActorId(8), False, False),
        ],
        [
            RecordedCollision(7, none, ActorId(2), False, True),
            RecordedCollision(8, ActorId(8), ActorId(9), False, False),
        ],
        List[RecordedCollision](),
    ]
    for k in range(6):
        r.collisions = frames[k].copy()
        if k == 2:
            r.events_del.append(RecordedEventDel(ActorId(3)))
        r.write_frame(deltas[k], 0, 0)
    return r.bytes()


def _blocked_log() raises -> List[UInt8]:
    """The `blocked` recording of the reference program."""
    var r = Recorder()
    _ = r.begin("", "Town02", False, DATE)
    r.events_add = [
        _add(2, VEHICLE_ACTOR, _zero(), _zero(), 1, "vehicle.lincoln.mkz"),
        _add(3, WALKER_ACTOR, _zero(), _zero(), 2, "walker.pedestrian.0002"),
        _add(6, VEHICLE_ACTOR, _zero(), _zero(), 3, "vehicle.audi.tt"),
    ]
    r.positions = [
        _pos(2, LogVector(1000, 0, 0), _zero()),
        _pos(3, LogVector(0, 500, 0), _zero()),
        _pos(6, LogVector(3, 4, 0), _zero()),
        _pos(7, _zero(), _zero()),
    ]
    r.write_frame(0, 0, 0)
    for k in range(1, 11):
        var x2 = 1100.0 if k < 8 else 1100.0 + 50.0 * Float64(k - 7)
        var y3 = 500.0 + 4.0 * Float64(k)
        var x6 = 3.0 if k < 5 else 800.0
        r.positions = [
            _pos(2, LogVector(x2, 0, 0), _zero()),
            _pos(3, LogVector(0, y3, 0), _zero()),
            _pos(6, LogVector(x6, 4, 0), _zero()),
            _pos(7, _zero(), _zero()),
        ]
        if k == 6:
            r.events_del.append(RecordedEventDel(ActorId(3)))
        r.write_frame(12.5, 0, 0)
    return r.bytes()


def _hex(bytes: List[UInt8]) -> String:
    var digits = "0123456789abcdef"
    var out = String()
    for b in bytes:
        out += chr(Int(digits.as_bytes()[Int(b >> 4)]))
        out += chr(Int(digits.as_bytes()[Int(b & 15)]))
    return out


def _fnv(bytes: List[UInt8]) -> UInt64:
    var h = UInt64(0xCBF29CE484222325)
    for b in bytes:
        h ^= UInt64(b)
        h *= UInt64(0x100000001B3)
    return h


# --- the file bytes -------------------------------------------------------------


def test_full_recording_is_carlas_bytes() raises:
    var bytes = _full_log()
    assert_equal(len(bytes), 2822)
    assert_equal(_hex(bytes), _full_log_hex())


def test_collision_and_blocked_recordings_are_carlas_bytes() raises:
    var c = _collisions_log()
    assert_equal(len(c), _COLLISIONS_LOG_SIZE)
    assert_equal(_fnv(c), _COLLISIONS_LOG_FNV)
    var b = _blocked_log()
    assert_equal(len(b), _BLOCKED_LOG_SIZE)
    assert_equal(_fnv(b), _BLOCKED_LOG_FNV)


def test_header_and_frame_layout_by_hand() raises:
    # Worked by hand from CarlaRecorderInfo.h and CarlaRecorderFrames.cpp.
    var r = Recorder()
    _ = r.begin("", "M", False, 258)
    var head = r.bytes()
    # Version 1, "CARLA_RECORDER" (14 bytes), the date 258, "M".
    assert_equal(len(head), 2 + 2 + 14 + 8 + 2 + 1)
    assert_equal(Int(head[0]), 1)
    assert_equal(Int(head[2]), 14)
    assert_equal(Int(head[18]), 2)
    assert_equal(Int(head[19]), 1)
    r.write_frame(0.25, 0, 0)
    r.write_frame(0.25, 0, 0)
    var reader = LogReader(r.bytes())
    reader.skip(len(head))
    # Frame 1: id 0, size 24, frame 1, duration 0.25 written back, time 0.
    assert_equal(reader.u8(), 0)
    assert_equal(reader.u32(), 24)
    assert_equal(Int(reader.u64()), 1)
    assert_equal(reader.f64(), 0.25)
    assert_equal(reader.f64(), 0.0)
    # The last frame keeps the duration -1.
    var all = r.bytes()
    var tail = LogReader(all^)
    tail.seek(len(head) + 5 + 24)
    while tail.u8() != 0:
        tail.skip(tail.u32())
    _ = tail.u32()
    assert_equal(Int(tail.u64()), 2)
    assert_equal(tail.f64(), -1.0)
    assert_equal(tail.f64(), 0.25)


# --- the queries ------------------------------------------------------------------


def test_file_info_query() raises:
    assert_equal(query_info(_full_log(), False), _full_info())
    assert_equal(query_info(_collisions_log(), False), _collisions_info())


def test_file_info_query_shows_all() raises:
    assert_equal(query_info(_full_log(), True), _full_all())


def test_collision_query_filters() raises:
    var log = _collisions_log()
    assert_equal(
        query_collisions(log.copy(), CATEGORY_ANY, CATEGORY_ANY),
        _collisions_aa(),
    )
    assert_equal(
        query_collisions(log.copy(), CATEGORY_VEHICLE, CATEGORY_VEHICLE),
        _collisions_vv(),
    )
    assert_equal(
        query_collisions(log.copy(), CATEGORY_HERO, CATEGORY_ANY),
        _collisions_ha(),
    )
    assert_equal(
        query_collisions(log.copy(), CATEGORY_VEHICLE, CATEGORY_OTHER),
        _collisions_vo(),
    )
    assert_equal(
        query_collisions(log.copy(), CATEGORY_WALKER, CATEGORY_OTHER),
        _collisions_wo(),
    )
    assert_equal(
        query_collisions(log.copy(), CATEGORY_OTHER, CATEGORY_HERO),
        _collisions_oh(),
    )
    assert_equal(
        query_collisions(log.copy(), CATEGORY_TRAFFIC_LIGHT, CATEGORY_WALKER),
        _collisions_tw(),
    )
    assert_equal(
        query_collisions(log.copy(), CATEGORY_ANY, CATEGORY_HERO),
        _collisions_ah(),
    )
    with assert_raises():
        _ = query_collisions(log.copy(), CollisionCategory(120), CATEGORY_ANY)
    with assert_raises():
        _ = query_collisions(log.copy(), CATEGORY_ANY, CollisionCategory(0))


def test_blocked_query() raises:
    var log = _blocked_log()
    assert_equal(query_blocked(log.copy()), _blocked_default())
    assert_equal(
        query_blocked(log.copy(), Duration(20, SECOND), Length(3, CENTIMETER)),
        _blocked_short(),
    )
    assert_equal(
        query_blocked(log.copy(), Duration(1000, SECOND), Length(0.1, METER)),
        _blocked_none(),
    )


def test_a_file_that_is_not_a_recording() raises:
    var w = ByteWriter()
    w.u16(1)
    write_string(w, "NOT_CARLA")
    w.i64(DATE)
    write_string(w, "x")
    var bytes = w^.finish()
    var expected = "File is not a CARLA recorder\n"
    assert_equal(query_info(bytes.copy()), expected)
    assert_equal(query_collisions(bytes.copy()), expected)
    assert_equal(query_blocked(bytes.copy()), expected)


def test_the_file_forms_of_the_queries() raises:
    var dir = "/tmp/threemojo_recorder_queries/"
    makedirs(dir, exist_ok=True)
    Path(dir + "full.log").write_bytes(_full_log())
    Path(dir + "collisions.log").write_bytes(_collisions_log())
    Path(dir + "blocked.log").write_bytes(_blocked_log())
    assert_equal(show_recorder_file_info("full.log", False, dir), _full_info())
    assert_equal(
        show_recorder_collisions(
            dir + "collisions.log", CATEGORY_ANY, CATEGORY_ANY
        ),
        _collisions_aa(),
    )
    assert_equal(
        show_recorder_actors_blocked(
            "blocked.log", Duration(30, SECOND), Length(10, CENTIMETER), dir
        ),
        _blocked_default(),
    )
    var missing = "File /nonexistent/x.log not found on server\n"
    assert_equal(show_recorder_file_info("/nonexistent/x.log"), missing)
    assert_equal(
        show_recorder_collisions(
            "/nonexistent/x.log", CATEGORY_ANY, CATEGORY_ANY
        ),
        missing,
    )
    assert_equal(show_recorder_actors_blocked("/nonexistent/x.log"), missing)
    assert_equal(recorder_file_path("a.log", "/saved/"), "/saved/a.log")
    assert_equal(recorder_file_path("C:a.log", "/saved/"), "C:a.log")
    assert_equal(recorder_file_path("d\\a.log", "/saved/"), "d\\a.log")


def _cut(var bytes: List[UInt8], count: Int) -> List[UInt8]:
    for _ in range(count):
        _ = bytes.pop()
    return bytes^


def test_a_log_cut_short() raises:
    # With no last FrameEnd, the loop ends at the last packet read.
    var text = query_info(_cut(_full_log(), 5), True)
    assert_true(
        text.endswith(
            " Walkers Bones: 0\n\nFrames: 3\nDuration: 0.15 seconds\n"
        )
    )
    # A FrameEnd whose size is cut: its id is read, and ends the frame.
    var partial = query_info(_cut(_full_log(), 3), True)
    assert_true(
        partial.endswith(
            " Walkers Bones: 0\n\n\nFrames: 3\nDuration: 0.15 seconds\n"
        )
    )
    var collisions = query_collisions(_cut(_collisions_log(), 5))
    assert_true(collisions.endswith("Frames: 7\nDuration: 6 seconds\n"))
    var blocked = query_blocked(_cut(_blocked_log(), 5))
    assert_true(blocked.endswith("Frames: 11\nDuration: 125 seconds\n"))


def _edge_log() raises -> List[UInt8]:
    """The `edge` recording: empty packets, every door and repeats."""
    var r = Recorder()
    _ = r.begin("", "M", True, DATE)
    r.frames.set_frame(0)
    r.frames.write_start(r.out)
    events_add_packet(
        r.out,
        [
            _add(2, VEHICLE_ACTOR, _zero(), _zero(), 1, "vehicle.a"),
            _add(3, WALKER_ACTOR, _zero(), _zero(), 2, "walker.b"),
        ],
    )
    events_del_packet(
        r.out, [RecordedEventDel(ActorId(5)), RecordedEventDel(ActorId(6))]
    )
    collisions_packet(
        r.out,
        [
            RecordedCollision(0, ActorId(2), ActorId(7), False, False),
            RecordedCollision(1, ActorId(2), ActorId(7), False, False),
        ],
    )
    for id in [11, 12, 17, 15, 16, 24]:
        write_packet(r.out, RecorderPacketId(id), [UInt8(0), UInt8(0)])
    # Door 9 has no name: the writer refuses it, so it is written by hand.
    var doors = ByteWriter()
    doors.u16(8)
    for k in [0, 1, 2, 3, 4, 5, 6, 9]:
        doors.u32(2)
        doors.u8(UInt8(k))
        doors.u8(1)
    write_packet(r.out, PACKET_VEHICLE_DOOR, doors^.finish())
    positions_packet(r.out, List[RecordedPosition]())
    walker_bones_packet(
        r.out, [RecordedWalkerBones(ActorId(3), List[RecordedBone]())]
    )
    r.frames.write_end(r.out)
    return r.bytes()


def _bare_log() raises -> List[UInt8]:
    var r = Recorder()
    _ = r.begin("", "M", False, DATE)
    r.write_frame(0, 0, 0)
    return r.bytes()


def test_empty_packets_every_door_and_repeats() raises:
    var edge = _edge_log()
    assert_equal(len(edge), _EDGE_LOG_SIZE)
    assert_equal(_fnv(edge), _EDGE_LOG_FNV)
    assert_equal(query_info(edge.copy(), True), _edge_all())
    assert_equal(query_info(edge.copy(), False), _edge_info())
    assert_equal(query_collisions(edge.copy()), _edge_coll())
    assert_equal(query_blocked(edge.copy()), _edge_blocked())
    assert_equal(query_blocked(_bare_log()), _bare_blocked())


def test_light_names_in_carlas_order() raises:
    assert_equal(light_names(VehicleLightState(0)), "None")
    # The interior light comes before the fog lights.
    assert_equal(light_names(LIGHT_FOG | LIGHT_INTERIOR), "Interior Fog")


# --- reading back ------------------------------------------------------------------


def test_every_record_reads_back() raises:
    # The file is walked packet by packet: each record reads back to what
    # was written, and the reader lands on each packet's end.
    var bytes = _full_log()
    var r = LogReader(bytes^)
    _ = r.u16()
    assert_equal(r.string(), "CARLA_RECORDER")
    assert_equal(r.i64(), DATE)
    assert_equal(r.string(), "Town10HD_Opt")
    var ids = List[Int]()
    while True:
        var id = r.u8()
        var size = r.u32()
        if r.failed:
            break
        ids.append(id)
        r.skip(size)
    # Frame 1 holds every packet; the order is CARLA's.
    var first: List[Int] = [
        0,
        20,
        2,
        3,
        4,
        5,
        23,
        6,
        7,
        8,
        9,
        10,
        11,
        21,
        22,
        24,
        12,
        13,
        17,
        14,
        15,
        16,
        19,
        1,
    ]
    for i in range(len(first)):
        assert_equal(ids[i], first[i])
    assert_equal(ids[len(ids) - 1], 1)


def test_records_round_trip() raises:
    var w = ByteWriter()
    var add = _add(
        9,
        VEHICLE_ACTOR,
        LogVector(1, -2, 3.5),
        LogVector(4, 5, 6),
        12,
        "vehicle.x",
        [RecordedAttribute(ATTRIBUTE_STRING, "role_name", "hero")],
    )
    add.write(w)
    RecordedEventDel(ActorId(9)).write(w)
    RecordedEventParent(ActorId(9), ActorId(1)).write(w)
    RecordedCollision(3, ActorId(9), NOT_AN_ACTOR, True, False).write(w)
    RecordedTrafficLight(ActorId(4), True, 2.5, YELLOW).write(w)
    RecordedAnimVehicle(ActorId(9), 0.5, 0.25, 0.125, True, Gear(-1)).write(w)
    RecordedAnimWheels(
        ActorId(9), [RecordedWheel(VehicleWheelLocation(3), 1.5, 2.5)]
    ).write(w)
    RecordedAnimWalker(ActorId(9), 150).write(w)
    RecordedAnimBiker(ActorId(9), 4, 0.75).write(w)
    RecordedLightScene(
        SceneLightId(-5), 2, Vector4(0.5, 0.25, 1, 1), False, SceneLightGroup(4)
    ).write(w)
    RecordedDoorVehicle(ActorId(9), DOOR_ALL, True).write(w)
    var physics = _carla_physics(9)
    physics.wheels.append(_carla_wheel())
    physics.write(w)
    var r = LogReader(w^.finish())
    var a = RecordedEventAdd.read(r)
    assert_equal(a.database_id.value, 9)
    assert_true(a.type == VEHICLE_ACTOR)
    assert_equal(a.location.z, 3.5)
    assert_equal(a.description.uid, 12)
    assert_equal(a.description.attributes[0].value, "hero")
    assert_equal(RecordedEventDel.read(r).database_id.value, 9)
    assert_equal(RecordedEventParent.read(r).database_id_parent.value, 1)
    var c = RecordedCollision.read(r)
    assert_true(c.database_id2 == NOT_AN_ACTOR and c.is_actor1_hero)
    var s = RecordedTrafficLight.read(r)
    assert_true(s.state == YELLOW and s.is_frozen)
    assert_equal(s.elapsed_time, 2.5)
    var v = RecordedAnimVehicle.read(r)
    assert_equal(v.gear.value, -1)
    assert_true(v.handbrake)
    var wheels = RecordedAnimWheels.read(r)
    assert_equal(wheels.wheels[0].tire_rotation, 2.5)
    assert_equal(RecordedAnimWalker.read(r).speed, 150)
    assert_equal(RecordedAnimBiker.read(r).engine_rotation, 0.75)
    var light = RecordedLightScene.read(r)
    assert_equal(light.light_id.value, -5)
    assert_true(light.type == SceneLightGroup(4))
    assert_false(light.on)
    var door = RecordedDoorVehicle.read(r)
    assert_true(door.doors == DOOR_ALL and door.is_open)
    var p = RecordedPhysicsControl.read(r)
    assert_equal(len(p.wheels), 1)
    assert_equal(p.wheels[0].wheel_index, -1)
    assert_equal(p.wheels[0].suspension_axis.z, -1)
    assert_equal(len(p.forward_gear_ratios), 8)
    assert_false(r.failed)
    # One more read runs past the end.
    _ = r.u8()
    assert_true(r.failed)
    assert_equal(r.string(), "")


def test_log_vectors_convert_units() raises:
    var v = LogVector.from_meters(Vector3(1.5, -2, 0.25))
    assert_equal(v.x, 150)
    assert_equal(v.y, -200)
    assert_equal(v.z, 25)
    var back = v.to_meters()
    assert_equal(back.x, 1.5)
    var r = LogVector(10, 20, 30).to_rotation()
    # The file's x, y and z are the roll, pitch and yaw.
    assert_almost_equal(r.roll, 10, atol=1e-5)
    assert_almost_equal(r.pitch, 20, atol=1e-5)
    assert_almost_equal(r.yaw, 30, atol=1e-5)
    var e = LogVector.from_rotation(r)
    assert_almost_equal(e.x, 10, atol=1e-5)
    assert_almost_equal(e.y, 20, atol=1e-5)
    assert_equal(LogVector.from_vector(Vector3(1, 2, 3)).to_vector().z, 3)
    assert_equal(LogVector(0, 3, 4).distance(_zero()), 5)


# --- refusals --------------------------------------------------------------------


def test_records_refuse_values_that_are_not_valid() raises:
    var w = ByteWriter()
    with assert_raises():
        write_packet(w, RecorderPacketId(25), List[UInt8]())
    with assert_raises():
        RecordedEventDel(ActorId(-1)).write(w)
    with assert_raises():
        RecordedEventParent(ActorId(1), ActorId(1 << 33)).write(w)
    with assert_raises():
        _add(1, ActorKind(6), _zero(), _zero(), 0, "x").write(w)
    with assert_raises():
        _add(
            1,
            OTHER_ACTOR,
            _zero(),
            _zero(),
            0,
            "x",
            [RecordedAttribute(ActorAttributeType(6), "a", "b")],
        ).write(w)
    with assert_raises():
        RecordedTrafficLight(ActorId(1), False, 0, TrafficLightState(5)).write(
            w
        )
    with assert_raises():
        RecordedLightVehicle(ActorId(1), VehicleLightState(-1)).write(w)
    with assert_raises():
        RecordedLightScene(
            SceneLightId(1 << 40),
            0,
            Vector4(0, 0, 0, 0),
            True,
            SceneLightGroup(0),
        ).write(w)
    with assert_raises():
        RecordedLightScene(
            SceneLightId(0), 0, Vector4(0, 0, 0, 0), True, SceneLightGroup(5)
        ).write(w)
    with assert_raises():
        RecordedDoorVehicle(ActorId(1), VehicleDoor(7), True).write(w)
    with assert_raises():
        RecordedAnimWheels(
            ActorId(1), [RecordedWheel(VehicleWheelLocation(4), 0, 0)]
        ).write(w)
    var p = _carla_physics(1)
    p.differential_type = DifferentialType(4)
    with assert_raises():
        p.write(w)
    var q = _carla_physics(-1)
    with assert_raises():
        q.write(w)
    var bad_wheel = _carla_wheel()
    bad_wheel.sweep_shape = SweepShape(3)
    with assert_raises():
        bad_wheel.write(w)


def test_physics_control_with_empty_lists() raises:
    # CARLA's default setup has no wheels; with empty curves and gears the
    # text has only the headings.
    var p = RecordedPhysicsControl.from_control(
        ActorId(4), VehiclePhysicsControl()
    )
    assert_equal(len(p.wheels), 0)
    assert_almost_equal(p.max_rpm, 5000, atol=1e-2)
    assert_almost_equal(p.chassis_width, 180, atol=1e-3)
    p.torque_curve = List[Vector2]()
    p.steering_curve = List[Vector2]()
    p.forward_gear_ratios = List[Float32]()
    p.reverse_gear_ratios = List[Float32]()
    var w = ByteWriter()
    p.write(w)
    var r = LogReader(w^.finish())
    var back = RecordedPhysicsControl.read(r)
    assert_equal(len(back.torque_curve), 0)
    assert_equal(len(back.reverse_gear_ratios), 0)
    assert_equal(len(back.wheels), 0)
    var text = physics_control_text(back)
    assert_true(
        text.endswith(
            "   torque_curve =\n   steering_curve =\n   forward_gear_ratios:\n"
            + "   reverse_gear_ratios:\n   wheels:\n"
        )
    )
    # A wheel's setup in CARLA's units: the default wheel.
    var control = VehiclePhysicsControl()
    control.wheels.append(WheelPhysicsControl())
    var one = RecordedPhysicsControl.from_control(ActorId(4), control)
    assert_almost_equal(one.wheels[0].wheel_radius, 30, atol=1e-3)
    assert_almost_equal(one.wheels[0].slip_threshold, 20, atol=1e-3)
    assert_almost_equal(one.wheels[0].spring_rate, 250, atol=1e-2)
    assert_almost_equal(one.wheels[0].max_steer_angle, 70, atol=1e-3)
    assert_equal(one.wheels[0].wheel_index, 0)
    # Empty wheel animation reads back empty.
    var a = ByteWriter()
    RecordedAnimWheels(ActorId(1), List[RecordedWheel]()).write(a)
    var ar = LogReader(a^.finish())
    assert_equal(len(RecordedAnimWheels.read(ar).wheels), 0)


def _bytes_of(var w: ByteWriter) -> List[UInt8]:
    return w^.finish()


def test_reading_values_that_are_not_valid_raises() raises:
    # An EventAdd with the kind 6.
    var a = ByteWriter()
    a.u32(1)
    a.u8(6)
    with assert_raises():
        var r = LogReader(_bytes_of(a^))
        _ = RecordedEventAdd.read(r)
    # An attribute of type 6.
    var b = ByteWriter()
    _add(1, OTHER_ACTOR, _zero(), _zero(), 0, "x").write(b)
    var bytes = _bytes_of(b^)
    # The attribute count is the last two bytes: make it one, then add a
    # bad attribute.
    bytes[len(bytes) - 2] = 1
    bytes.append(6)
    with assert_raises():
        var r = LogReader(bytes^)
        _ = RecordedEventAdd.read(r)
    var c = ByteWriter()
    c.u32(1)
    c.u8(0)
    c.f32(0)
    c.u8(9)
    with assert_raises():
        var r = LogReader(_bytes_of(c^))
        _ = RecordedTrafficLight.read(r)
    var d = ByteWriter()
    d.u32(1)
    d.u32(1)
    d.u8(7)
    with assert_raises():
        var r = LogReader(_bytes_of(d^))
        _ = RecordedAnimWheels.read(r)
    var e = ByteWriter()
    e.u32(1)
    for _ in range(5):
        e.f32(0)
    e.u8(1)
    e.u8(9)
    with assert_raises():
        var r = LogReader(_bytes_of(e^))
        _ = RecordedLightScene.read(r)
    var f = ByteWriter()
    f.u32(1)
    for _ in range(6):
        f.f32(0)
    f.u8(9)
    with assert_raises():
        var r = LogReader(_bytes_of(f^))
        _ = RecordedPhysicsControl.read(r)
    var g = ByteWriter()
    g.u8(7)
    g.zeros(207)
    with assert_raises():
        var r = LogReader(_bytes_of(g^))
        _ = RecordedWheelPhysics.read(r)


def test_ids_and_kinds_check_their_range() raises:
    assert_true(RecorderPacketId(0).is_valid())
    assert_true(RecorderPacketId(24).is_valid())
    assert_false(RecorderPacketId(-1).is_valid())
    assert_false(RecorderPacketId(25).is_valid())
    assert_true(SceneLightId(-2147483648).is_valid())
    assert_false(SceneLightId(-2147483649).is_valid())
    assert_false(SceneLightId(2147483648).is_valid())
    assert_false(SceneLightGroup(-1).is_valid())
    assert_true(CATEGORY_ANY.is_valid())
    assert_true(CATEGORY_TRAFFIC_LIGHT.is_valid())
    assert_false(CollisionCategory(98).is_valid())


def test_packets_carla_does_not_read_are_skipped() raises:
    # A FrameCounter and a platform time the queries skip.
    var r = Recorder()
    _ = r.begin("", "M", False, 0)
    frame_counter_packet(r.out, 7)
    r.write_frame(0, 0, 0)
    var text = query_info(r.bytes(), True)
    assert_true("Frames: 1" in text)


# --- the reference program's output ------------------------------------------------


def _full_log_hex() -> String:
    var s = String()
    s += "01000e004341524c415f5245434f52444552803bb16a000000000c00546f776e"
    s += "313048445f4f7074001800000001000000000000009a9999999999a93f000000"
    s += "00000000001408000000000000000000000002c1010000050001000000000000"
    s += "0000000000000000000000000000000000000000000000000000000000000000"
    s += "0000000000000000000000000000000000000900737065637461746f72000002"
    s += "0000000100000000008a93400000000000c472c0000000000000244000000000"
    s += "0000e03f000000000000f4bf000000000080564011000000140076656869636c"
    s += "652e7465736c612e6d6f64656c330200040500636f6c6f7207003235352c302c"
    s += "30030900726f6c655f6e616d6504006865726f03000000020000000000407f40"
    s += "0000000000006940000000000000594000000000000000000000000000000000"
    s += "00000000008046c028000000160077616c6b65722e7065646573747269616e2e"
    s += "30303031010002050073706565640300312e3404000000030000000000408f40"
    s += "0000000000408f40000000000000000000000000000000000000000000000000"
    s += "00000000008066405a0000001500747261666669632e747261666669635f6c69"
    s += "676874000005000000050000000000c062400000000000000000000000000000"
    s += "6e4000000000000000000000000000002ec000000000000000003c0000001600"
    s += "73656e736f722e6f746865722e636f6c6c6973696f6e00000302000000000004"
    s += "0a000000010005000000020000000502000000000017020000000000069e0000"
    s += "0003000100000000000000000000000000000000000000000000000000000000"
    s += "0000000000000000000000000000000000000000000000020000000000000000"
    s += "8a93400000000000c472c00000000000002440000000000000e03f0000000000"
    s += "00f4bf0000000000805640030000000000000000407f40000000000000694000"
    s += "000000000059400000000000000000000000000000000000000000008046c007"
    s += "0c000000010004000000000000c03f0208170000000100020000000000803e00"
    s += "00403f000000000001000000090a00000001000300000000000c430a0a000000"
    s += "010002000000090100000b1c00000001000700000000007a440000803f000000"
    s += "3f0000803e0000803f0102151c00000001000200000002000000000000204100"
    s += "00344201000020c10000b542160e000000010002000000000060400000003f18"
    s += "3a00000001000000204100000000000000000000a040000034420000f0410000"
    s += "00000000403fcdcccc3d000000000000803f8fc2f53cde93073d000000000c36"
    s += "000000010002000000000000000000f03f000000000000004000000000000008"
    s += "400000000000000000000000000000000000000000008046400d6a0000000200"
    s += "02000000000000000000000000000000000000000000000000c0524000000000"
    s += "00006e4000000000000059400000000000c05240030000000000000000000000"
    s += "0000000000000000000000000000000000000000000039400000000000003940"
    s += "0000000000805640113600000001000400000000000000006890400000000000"
    s += "408f4000000000000059400000000000c062400000000000e055400000000000"
    s += "0059400e08000000c53c2b69c537543f0f750200000100020000000000964300"
    s += "409c450000803f0000803f0000803f00001644030000003f010000003f000080"
    s += "4000a08c450000fa446666663f00b0e6449a99993e00002041000000000000c8"
    s += "c10000344300000c439a99993e000000000000803f0000803f0000803f000020"
    s += "412db25d3f0003000000000000000000c8435258ec440000fa43a40cb3450000"
    s += "c8430800000066663640ae470140cdccac3f0000803f66663640ae470140cdcc"
    s += "ac3f0000803f020000003d0a37403d0a374002000000000000000000803f0000"
    s += "20410000003f0200000001000000000007430000a0c20000f0410000f0410000"
    s += "f0410000f04100007a44000040400000803f0000a0410000a04100008b420101"
    s += "0101010000000000f04100000000000000000000000000000000000000000000"
    s += "000000000000000000000000000000000000000080bf00000000000000000000"
    s += "000000002041000020410000003f0000003f00007a4300004842000000009a99"
    s += "193e000000000080bb4400803b45000000000000000000000000000000000000"
    s += "0000000000000000000000000000000000000000000000000000020000000000"
    s += "07c30000a0c20000f0410000f0410000f0410000f04100007a44000040400000"
    s += "803f0000a0410000a04100008c4200010101000000000000f041000000000000"
    s += "0000000000000000000000000000000000000000000000000000000000000000"
    s += "0000000080bf00000000000000000000000000002041000020410000003f0000"
    s += "003f00007a4300004842030000009a99193e000100000080bb4400803b450100"
    s += "00000000c03f00001040000040c0000000000000000000000000000000000000"
    s += "0000000000000000000010120000000100040000000000204100004040000000"
    s += "40137f0000000100030000000200080063726c5f726f6f740000000000000000"
    s += "0000000000000000000000000000000000000000000000000000000000000000"
    s += "00000000000000000b0063726c5f686970735f5f430000000000000000000000"
    s += "000000f83f0000000000d0574000000000008056c00000000000000000000000"
    s += "00008056400100000000001800000002000000000000009a9999999999b93f9a"
    s += "9999999999a93f14080000009a9999999999a93f020200000000000302000000"
    s += "000004020000000000051000000001000000000002000000ffffffff0100170e"
    s += "0000000200020000000001020000000600069e00000003000100000000000000"
    s += "0000000000000000000000000000000000000000000000000000000000000000"
    s += "0000000000000000000000000200000000000000005294400000000000c472c0"
    s += "0000000000002440000000000000e03f000000000000f4bf0000000000c05740"
    s += "030000000000000000e07f400000000000006940000000000000594000000000"
    s += "00000000000000000000000000000000008046c0070c00000001000400000001"
    s += "6666c63f010817000000010002000000000000be0000003f0000803e01ffffff"
    s += "ff090a000000010003000000000000000a0a0000000100020000000000000015"
    s += "020000000000160200000000000c360000000100020000000000000000002440"
    s += "0000000000000000000000000000000000000000000000000000000000000000"
    s += "00000000000000000d0200000000000e08000000000000000000e03f13020000"
    s += "000000010000000000180000000300000000000000000000000000f0bf343333"
    s += "333333c33f14080000009a9999999999b93f0202000000000003060000000100"
    s += "0300000004020000000000051000000001000100000002000000040000000100"
    s += "17020000000000066a0000000200010000000000000000000000000000000000"
    s += "0000000000000000000000000000000000000000000000000000000000000000"
    s += "00000200000000000000001a95400000000000c472c000000000000024400000"
    s += "00000000e03f000000000000f4bf0000000000005940070c0000000100040000"
    s += "0001cdcccc3f000817000000010002000000000000000000803f000000000002"
    s += "000000090200000000000a0a000000010002000000ffffffff15020000000000"
    s += "16020000000000183a00000001000000a04200007042000020420000f0410000"
    s += "9643000028c10000a04100002040cdcc4c3e00005c420000003fcdcccc3dcdcc"
    s += "4c3e38b496490d0200000000000e0800000048afbc9af2d77a3e130200000000"
    s += "000100000000"
    return s^


comptime _COLLISIONS_LOG_SIZE = 1576
comptime _COLLISIONS_LOG_FNV = UInt64(3513976682833853258)


comptime _BLOCKED_LOG_SIZE = 4006
comptime _BLOCKED_LOG_FNV = UInt64(10558736197089975754)


comptime _EDGE_LOG_SIZE = 376
comptime _EDGE_LOG_FNV = UInt64(8286009960029213708)


def _edge_all() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: M\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "Frame 1 at 0 seconds\n"
    s += " Create 2: vehicle.a (1) at (0, 0, 0)\n"
    s += " Create 3: walker.b (2) at (0, 0, 0)\n"
    s += " Destroy 5\n"
    s += " Destroy 6\n"
    s += " Collision id 0 between 2 with 7\n"
    s += " Collision id 1 between 2 with 7\n"
    s += " Scene light changes: 0\n"
    s += " Dynamic actors: 0\n"
    s += " Actor trigger volumes: 0\n"
    s += " Physics Control events: 0\n"
    s += " Traffic Light time events: 0\n"
    s += " Weathers: 0\n"
    s += " Vehicle door animations: 8\n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Front Left \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Front Right \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Rear Left \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Rear Right \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Hood \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Trunk \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  All \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Positions: 0\n"
    s += " Walkers Bones: 1\n"
    s += "  Id: 3\n"
    s += "\n"
    s += "\n"
    s += "\n"
    s += "Frames: 1\n"
    s += "Duration: 0 seconds\n"
    return s^


def _edge_info() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: M\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "Frame 1 at 0 seconds\n"
    s += " Create 2: vehicle.a (1) at (0, 0, 0)\n"
    s += " Create 3: walker.b (2) at (0, 0, 0)\n"
    s += " Destroy 5\n"
    s += " Destroy 6\n"
    s += " Collision id 0 between 2 with 7\n"
    s += " Collision id 1 between 2 with 7\n"
    s += " Weathers: 0\n"
    s += "\n"
    s += "\n"
    s += "\n"
    s += "Frames: 1\n"
    s += "Duration: 0 seconds\n"
    return s^


def _edge_coll() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: M\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       0   v o       2 vehicle.a                                7     "
    )
    s += "                               \n"
    s += (
        "       0   v o       2 vehicle.a                                7     "
    )
    s += "                               \n"
    s += "\n"
    s += "Frames: 1\n"
    s += "Duration: 0 seconds\n"
    return s^


def _edge_blocked() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: M\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "    Time     Id Actor                                 Duration\n"
    s += "\n"
    s += "Frames: 1\n"
    s += "Duration: 0 seconds\n"
    return s^


def _bare_blocked() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: M\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "    Time     Id Actor                                 Duration\n"
    s += "\n"
    s += "Frames: 1\n"
    s += "Duration: 0 seconds\n"
    return s^


def _full_info() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town10HD_Opt\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "Frame 1 at 0 seconds\n"
    s += " Create 1: spectator (0) at (0, 0, 0)\n"
    s += " Create 2: vehicle.tesla.model3 (1) at (1250.5, -300.25, 10)\n"
    s += "  color = 255,0,0\n"
    s += "  role_name = hero\n"
    s += " Create 3: walker.pedestrian.0001 (2) at (500, 200, 100)\n"
    s += "  speed = 1.4\n"
    s += " Create 4: traffic.traffic_light (3) at (1000, 1000, 0)\n"
    s += " Create 5: sensor.other.collision (5) at (150, 0, 240)\n"
    s += " Parenting 5 with 2 (parent)\n"
    s += " Weathers: 1\n"
    s += (
        "  Cloudiness: 10 Precipitation: 0 PrecipitationDeposits: 0 WindIntensi"
    )
    s += (
        "ty: 5 SunAzimuthAngle: 45 SunAltitudeAngle: 30 FogDensity: 0 FogDistan"
    )
    s += (
        "ce: 0.75 FogFalloff: 0.1 Wetness: 0 ScatteringIntensity: 1 MieScatteri"
    )
    s += "ngScale: 0.03 RayleighScatteringScale: 0.0331 DustStorm: 0\n"
    s += "\n"
    s += "Frame 2 at 0.05 seconds\n"
    s += " Collision id 0 between 2 (hero)  with 4294967295\n"
    s += "\n"
    s += "Frame 3 at 0.15 seconds\n"
    s += " Destroy 3\n"
    s += " Collision id 1 between 2 (hero)  with 4\n"
    s += " Weathers: 1\n"
    s += (
        "  Cloudiness: 80 Precipitation: 60 PrecipitationDeposits: 40 WindInten"
    )
    s += (
        "sity: 30 SunAzimuthAngle: 300 SunAltitudeAngle: -10.5 FogDensity: 20 F"
    )
    s += (
        "ogDistance: 2.5 FogFalloff: 0.2 Wetness: 55 ScatteringIntensity: 0.5 M"
    )
    s += (
        "ieScatteringScale: 0.1 RayleighScatteringScale: 0.2 DustStorm: 1.23457"
    )
    s += "e+06\n"
    s += "\n"
    s += "\n"
    s += "\n"
    s += "Frames: 3\n"
    s += "Duration: 0.15 seconds\n"
    return s^


def _full_all() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town10HD_Opt\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "Frame 1 at 0 seconds\n"
    s += " Create 1: spectator (0) at (0, 0, 0)\n"
    s += " Create 2: vehicle.tesla.model3 (1) at (1250.5, -300.25, 10)\n"
    s += "  color = 255,0,0\n"
    s += "  role_name = hero\n"
    s += " Create 3: walker.pedestrian.0001 (2) at (500, 200, 100)\n"
    s += "  speed = 1.4\n"
    s += " Create 4: traffic.traffic_light (3) at (1000, 1000, 0)\n"
    s += " Create 5: sensor.other.collision (5) at (150, 0, 240)\n"
    s += " Parenting 5 with 2 (parent)\n"
    s += " Vehicle door animations: 0\n"
    s += " Positions: 3\n"
    s += "  Id: 1 Location: (0, 0, 0) Rotation: (0, 0, 0)\n"
    s += "  Id: 2 Location: (1250.5, -300.25, 10) Rotation: (0.5, -1.25, 90)\n"
    s += "  Id: 3 Location: (500, 200, 100) Rotation: (0, 0, -45)\n"
    s += " State traffic lights: 1\n"
    s += "  Id: 4 state: 2 frozen: 0 elapsedTime: 1.5\n"
    s += " Vehicle animations: 1\n"
    s += "  Id: 2 Steering: 0.25 Throttle: 0.75 Brake: 0 Handbrake: 0 Gear: 1\n"
    s += " Walker animations: 1\n"
    s += "  Id: 3 speed: 140\n"
    s += " Vehicle light animations: 1\n"
    s += "  Id: 2 Position Brake Interior\n"
    s += " Scene light changes: 1\n"
    s += "  Id: 7 enabled: True intensity: 1000 RGB_color: (1, 0.5, 0.25)\n"
    s += " Weathers: 1\n"
    s += (
        "  Cloudiness: 10 Precipitation: 0 PrecipitationDeposits: 0 WindIntensi"
    )
    s += (
        "ty: 5 SunAzimuthAngle: 45 SunAltitudeAngle: 30 FogDensity: 0 FogDistan"
    )
    s += (
        "ce: 0.75 FogFalloff: 0.1 Wetness: 0 ScatteringIntensity: 1 MieScatteri"
    )
    s += "ngScale: 0.03 RayleighScatteringScale: 0.0331 DustStorm: 0\n"
    s += " Dynamic actors: 1\n"
    s += "  Id: 2 linear_velocity: (1, 2, 3) angular_velocity: (0, 0, 45)\n"
    s += " Actor bounding boxes: 2\n"
    s += "  Id: 2 origin: (0, 0, 75) extension: (240, 100, 75)\n"
    s += "  Id: 3 origin: (0, 0, 0) extension: (25, 25, 90)\n"
    s += " Actor trigger volumes: 1\n"
    s += "  Id: 4 origin: (1050, 1000, 100) extension: (150, 87.5, 100)\n"
    s += " Current platform time: 0.001234\n"
    s += " Physics Control events: 1\n"
    s += "  Id: 2\n"
    s += "   max_torque = 300\n"
    s += "   max_rpm = 5000\n"
    s += "   MOI = 1\n"
    s += "   rev_down_rate = 600\n"
    s += "   differential_type = \x03\n"
    s += "   front_rear_split = 0.5\n"
    s += "   use_gear_auto_box = true\n"
    s += "   gear_change_time = 0.5\n"
    s += "   final_ratio = 4\n"
    s += "   change_up_rpm = 4500\n"
    s += "   change_down_rpm = 2000\n"
    s += "   transmission_efficiency = 0.9\n"
    s += "   mass = 1845.5\n"
    s += "   drag_coefficient = 0.3\n"
    s += "   center_of_mass = (10, 0, -25)\n"
    s += "   torque_curve = (0, 400) (1890.76, 500) (5729.58, 400)\n"
    s += "   steering_curve = (0, 1) (10, 0.5)\n"
    s += "   forward_gear_ratios:\n"
    s += "    gear 0: ratio 2.85\n"
    s += "    gear 1: ratio 2.02\n"
    s += "    gear 2: ratio 1.35\n"
    s += "    gear 3: ratio 1\n"
    s += "    gear 4: ratio 2.85\n"
    s += "    gear 5: ratio 2.02\n"
    s += "    gear 6: ratio 1.35\n"
    s += "    gear 7: ratio 1\n"
    s += "   reverse_gear_ratios:\n"
    s += "    gear 0: ratio 2.86\n"
    s += "    gear 1: ratio 2.86\n"
    s += "   wheels:\n"
    s += "wheel #0:\n"
    s += (
        " axle_type: \x01 offset: (135.000000, -80.000000, 30.000000) wheel_rad"
    )
    s += (
        "ius: 30 wheel_width: 30 wheel_mass: 30 cornering_stiffness: 1000 frict"
    )
    s += (
        "ion_force_multiplier: 3 side_slip_modifier: 1 slip_threshold: 20 skid_"
    )
    s += (
        "threshold: 20 max_steer_angle: 69.5 affected_by_steering: 1 affected_b"
    )
    s += (
        "y_brake: 1 affected_by_handbrake: 1 affected_by_engine: 1 abs_enabled:"
    )
    s += (
        " 1 traction_control_enabled: 0 max_wheelspin_rotation: 30 external_tor"
    )
    s += (
        "que_combine_method: \x00 lateral_slip_graph: [] suspension_axis: (0.00"
    )
    s += (
        "0000, 0.000000, -1.000000) suspension_force_offset: (0.000000, 0.00000"
    )
    s += (
        "0, 0.000000) suspension_max_raise: 10 suspension_max_drop: 10 suspensi"
    )
    s += (
        "on_damping_ratio: 0.5 wheel_load_ratio: 0.5 spring_rate: 250 spring_pr"
    )
    s += "eload: 50 suspension_smoothing: 0 rollbar_scaling: 0.15 sweep_shape: "
    s += (
        "\x00 sweep_type: \x00 max_brake_torque: 1500 max_hand_brake_torque: 30"
    )
    s += (
        "00 wheel_index: 0 location: (0.000000, 0.000000, 0.000000) old_locatio"
    )
    s += (
        "n: (0.000000, 0.000000, 0.000000) velocity: (0.000000, 0.000000, 0.000"
    )
    s += "000)\n"
    s += "wheel #1:\n"
    s += (
        " axle_type: \x02 offset: (-135.000000, -80.000000, 30.000000) wheel_ra"
    )
    s += (
        "dius: 30 wheel_width: 30 wheel_mass: 30 cornering_stiffness: 1000 fric"
    )
    s += (
        "tion_force_multiplier: 3 side_slip_modifier: 1 slip_threshold: 20 skid"
    )
    s += (
        "_threshold: 20 max_steer_angle: 70 affected_by_steering: 0 affected_by"
    )
    s += (
        "_brake: 1 affected_by_handbrake: 1 affected_by_engine: 1 abs_enabled: "
    )
    s += (
        "0 traction_control_enabled: 0 max_wheelspin_rotation: 30 external_torq"
    )
    s += (
        "ue_combine_method: \x00 lateral_slip_graph: [] suspension_axis: (0.000"
    )
    s += (
        "000, 0.000000, -1.000000) suspension_force_offset: (0.000000, 0.000000"
    )
    s += (
        ", 0.000000) suspension_max_raise: 10 suspension_max_drop: 10 suspensio"
    )
    s += (
        "n_damping_ratio: 0.5 wheel_load_ratio: 0.5 spring_rate: 250 spring_pre"
    )
    s += "load: 50 suspension_smoothing: 3 rollbar_scaling: 0.15 sweep_shape: "
    s += (
        "\x00 sweep_type: \x01 max_brake_torque: 1500 max_hand_brake_torque: 30"
    )
    s += (
        "00 wheel_index: 1 location: (1.500000, 2.250000, -3.000000) old_locati"
    )
    s += (
        "on: (0.000000, 0.000000, 0.000000) velocity: (0.000000, 0.000000, 0.00"
    )
    s += "0000)\n"
    s += " Traffic Light time events: 1\n"
    s += "  Id: 4 green_time: 10 yellow_time: 3 red_time: 2\n"
    s += " Walkers Bones: 1\n"
    s += "  Id: 3\n"
    s += '     Bone: "crl_root" relative: Loc(0, 0, 0) Rot(0, 0, 0)\n'
    s += '     Bone: "crl_hips__C" relative: Loc(0, 1.5, 95.25) Rot(-90, 0, 90'
    s += ")\n"
    s += "\n"
    s += "Frame 2 at 0.05 seconds\n"
    s += " Collision id 0 between 2 (hero)  with 4294967295\n"
    s += " Vehicle door animations: 2\n"
    s += "  Id: 2\n"
    s += "  Doors opened:  Front Left \n"
    s += "  Id: 2\n"
    s += "  Doors opened:  All \n"
    s += " Positions: 3\n"
    s += "  Id: 1 Location: (0, 0, 0) Rotation: (0, 0, 0)\n"
    s += "  Id: 2 Location: (1300.5, -300.25, 10) Rotation: (0.5, -1.25, 95)\n"
    s += "  Id: 3 Location: (510, 200, 100) Rotation: (0, 0, -45)\n"
    s += " State traffic lights: 1\n"
    s += "  Id: 4 state: 1 frozen: 1 elapsedTime: 1.55\n"
    s += " Vehicle animations: 1\n"
    s += (
        "  Id: 2 Steering: -0.125 Throttle: 0.5 Brake: 0.25 Handbrake: 1 Gear: "
    )
    s += "-1\n"
    s += " Walker animations: 1\n"
    s += "  Id: 3 speed: 0\n"
    s += " Vehicle light animations: 1\n"
    s += "  Id: 2 None\n"
    s += " Dynamic actors: 1\n"
    s += "  Id: 2 linear_velocity: (10, 0, 0) angular_velocity: (0, 0, 0)\n"
    s += " Actor bounding boxes: 0\n"
    s += " Current platform time: 0.5\n"
    s += " Walkers Bones: 0\n"
    s += "\n"
    s += "Frame 3 at 0.15 seconds\n"
    s += " Destroy 3\n"
    s += " Collision id 1 between 2 (hero)  with 4\n"
    s += " Vehicle door animations: 0\n"
    s += " Positions: 2\n"
    s += "  Id: 1 Location: (0, 0, 0) Rotation: (0, 0, 0)\n"
    s += "  Id: 2 Location: (1350.5, -300.25, 10) Rotation: (0.5, -1.25, 100)\n"
    s += " State traffic lights: 1\n"
    s += "  Id: 4 state: 0 frozen: 1 elapsedTime: 1.6\n"
    s += " Vehicle animations: 1\n"
    s += "  Id: 2 Steering: 0 Throttle: 1 Brake: 0 Handbrake: 0 Gear: 2\n"
    s += " Walker animations: 0\n"
    s += " Vehicle light animations: 1\n"
    s += (
        "  Id: 2 Position LowBeam HighBeam Brake RightBlinker LeftBlinker Rever"
    )
    s += "se Interior Fog Special1 Special2\n"
    s += " Weathers: 1\n"
    s += (
        "  Cloudiness: 80 Precipitation: 60 PrecipitationDeposits: 40 WindInten"
    )
    s += (
        "sity: 30 SunAzimuthAngle: 300 SunAltitudeAngle: -10.5 FogDensity: 20 F"
    )
    s += (
        "ogDistance: 2.5 FogFalloff: 0.2 Wetness: 55 ScatteringIntensity: 0.5 M"
    )
    s += (
        "ieScatteringScale: 0.1 RayleighScatteringScale: 0.2 DustStorm: 1.23457"
    )
    s += "e+06\n"
    s += " Actor bounding boxes: 0\n"
    s += " Current platform time: 1e-07\n"
    s += " Walkers Bones: 0\n"
    s += "\n"
    s += "\n"
    s += "\n"
    s += "Frames: 3\n"
    s += "Duration: 0.15 seconds\n"
    return s^


def _collisions_info() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += "Frame 1 at 0 seconds\n"
    s += " Create 2: vehicle.lincoln.mkz (1) at (0, 0, 0)\n"
    s += "  role_name = hero\n"
    s += " Create 3: walker.pedestrian.0002 (2) at (0, 0, 0)\n"
    s += " Create 6: vehicle.audi.tt (1) at (0, 0, 0)\n"
    s += " Create 4: traffic.traffic_light (3) at (0, 0, 0)\n"
    s += " Create 8: traffic.stop (4) at (0, 0, 0)\n"
    s += " Create 9: sensor.other.collision (5) at (0, 0, 0)\n"
    s += "\n"
    s += "Frame 2 at 2.5 seconds\n"
    s += " Collision id 0 between 2 (hero)  with 6\n"
    s += "\n"
    s += "Frame 3 at 3.5 seconds\n"
    s += " Collision id 1 between 2 (hero)  with 6\n"
    s += " Collision id 2 between 3 with 4294967295\n"
    s += "\n"
    s += "Frame 4 at 3.75 seconds\n"
    s += " Destroy 3\n"
    s += " Collision id 3 between 6 with 2 (hero) \n"
    s += " Collision id 4 between 4 with 3\n"
    s += "\n"
    s += "Frame 5 at 4 seconds\n"
    s += " Collision id 5 between 2 (hero)  with 6\n"
    s += " Collision id 6 between 9 with 8\n"
    s += "\n"
    s += "Frame 6 at 4.5 seconds\n"
    s += " Collision id 7 between 4294967295 with 2 (hero) \n"
    s += " Collision id 8 between 8 with 9\n"
    s += "\n"
    s += "\n"
    s += "\n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 5.5 seconds\n"
    return s^


def _collisions_aa() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       2   v v       2 vehicle.lincoln.mkz                      6 vehi"
    )
    s += "cle.audi.tt                    \n"
    s += (
        "       4   w o       3 walker.pedestrian.0002              4294967295 "
    )
    s += "                                   \n"
    s += (
        "       4   v v       6 vehicle.audi.tt                          2 vehi"
    )
    s += "cle.lincoln.mkz                \n"
    s += (
        "       4   t w       4 traffic.traffic_light                    3 walk"
    )
    s += "er.pedestrian.0002             \n"
    s += (
        "       4   v v       2 vehicle.lincoln.mkz                      6 vehi"
    )
    s += "cle.audi.tt                    \n"
    s += (
        "       4   o h       9                                          8 traf"
    )
    s += "fic.stop                       \n"
    s += (
        "       4   o v  4294967295                                          2 "
    )
    s += "vehicle.lincoln.mkz                \n"
    s += (
        "       4   h o       8 traffic.stop                             9     "
    )
    s += "                               \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 6 seconds\n"
    return s^


def _collisions_vv() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       2   v v       2 vehicle.lincoln.mkz                      6 vehi"
    )
    s += "cle.audi.tt                    \n"
    s += (
        "       4   v v       6 vehicle.audi.tt                          2 vehi"
    )
    s += "cle.lincoln.mkz                \n"
    s += (
        "       4   v v       2 vehicle.lincoln.mkz                      6 vehi"
    )
    s += "cle.audi.tt                    \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 6 seconds\n"
    return s^


def _collisions_ha() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       2   v v       2 vehicle.lincoln.mkz                      6 vehi"
    )
    s += "cle.audi.tt                    \n"
    s += (
        "       4   v v       2 vehicle.lincoln.mkz                      6 vehi"
    )
    s += "cle.audi.tt                    \n"
    s += (
        "       4   h o       8 traffic.stop                             9     "
    )
    s += "                               \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 6 seconds\n"
    return s^


def _collisions_vo() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 5.5 seconds\n"
    return s^


def _collisions_wo() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       4   w o       3 walker.pedestrian.0002              4294967295 "
    )
    s += "                                   \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 6 seconds\n"
    return s^


def _collisions_oh() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       4   o h       9                                          8 traf"
    )
    s += "fic.stop                       \n"
    s += (
        "       4   o v  4294967295                                          2 "
    )
    s += "vehicle.lincoln.mkz                \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 6 seconds\n"
    return s^


def _collisions_tw() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       4   t w       4 traffic.traffic_light                    3 walk"
    )
    s += "er.pedestrian.0002             \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 6 seconds\n"
    return s^


def _collisions_ah() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town01\n"
    s += "Date: 09/22/26 03:14:21\n"
    s += "\n"
    s += (
        "    Time  Types     Id Actor 1                                 Id Acto"
    )
    s += "r 2                            \n"
    s += (
        "       4   v v       6 vehicle.audi.tt                          2 vehi"
    )
    s += "cle.lincoln.mkz                \n"
    s += (
        "       4   o h       9                                          8 traf"
    )
    s += "fic.stop                       \n"
    s += (
        "       4   o v  4294967295                                          2 "
    )
    s += "vehicle.lincoln.mkz                \n"
    s += "\n"
    s += "Frames: 7\n"
    s += "Duration: 6 seconds\n"
    return s^


def _blocked_default() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town02\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "    Time     Id Actor                                 Duration\n"
    s += "       0      7                                            124\n"
    s += "      25      2 vehicle.lincoln.mkz                         75\n"
    s += "       0      6 vehicle.audi.tt                             62\n"
    s += "      88      6                                             36\n"
    s += "\n"
    s += "Frames: 11\n"
    s += "Duration: 125 seconds\n"
    return s^


def _blocked_short() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town02\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "    Time     Id Actor                                 Duration\n"
    s += "       0      7                                            124\n"
    s += "      25      2 vehicle.lincoln.mkz                         75\n"
    s += "      12      6 vehicle.audi.tt                             50\n"
    s += "      88      6                                             36\n"
    s += "\n"
    s += "Frames: 11\n"
    s += "Duration: 125 seconds\n"
    return s^


def _blocked_none() -> String:
    var s = String()
    s += "Version: 1\n"
    s += "Map: Town02\n"
    s += "Date: 09/21/26 14:13:20\n"
    s += "\n"
    s += "    Time     Id Actor                                 Duration\n"
    s += "\n"
    s += "Frames: 11\n"
    s += "Duration: 125 seconds\n"
    return s^


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
