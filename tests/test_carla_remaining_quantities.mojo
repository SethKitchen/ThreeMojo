# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Remaining typed serializers, replay controls, and physical return values."""

from core.assets import Assets
from core.scene import Scene
from extensions.carla.town import Town, TownSettings
from extensions.carla.weather import WeatherParameters
from extensions.carla.vehicle import LIGHTS_NONE, LIGHT_POSITION
from extensions.carla.actor import ActorId
from extensions.carla.geometry import (
    LINE,
    ARC_LENGTH,
    NORMALIZED,
    NormalizedCubic,
    RoadGeometry,
    RoadGeometryKind,
    with_poly3,
    with_poly3_si,
    poly3,
    poly3_from_coefficients,
    param_poly3_from_coefficients,
    with_param_poly3,
    with_param_poly3_normalized,
    with_param_poly3_from_coefficients,
    param_poly3,
    param_poly3_normalized,
)
from extensions.carla.map_builder import MapBuilder
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.blueprint import (
    PedestrianParameters,
    GENDER_OTHER,
    AGE_ADULT,
)
from extensions.carla.cameras import DVSEvent
from extensions.carla.map import (
    Waypoint,
    segment_distance_2d,
    segment_distance_2d_meters,
)
from extensions.carla.radar import RadarDetection
from extensions.carla.recorder import Recorder
from extensions.carla.recorder_packets import (
    RecorderFrames,
    time_packet,
    time_packet_seconds,
    PACKET_VISUAL_TIME,
)
from extensions.carla.render_actors import loft, loft_meters
from extensions.carla.render_light import (
    fog_density_at,
    fog_density_at_per_meter,
)
from extensions.carla.render_weather import HeightFog
from extensions.carla.replayer_helper import (
    lerp_angle,
    lerp_angle_degrees,
    set_walker_speed,
    set_walker_speed_centimeters_per_second,
)
from extensions.carla.road_info import RoadId, SectionId, LaneId, NO_JUNCTION
from extensions.carla.sensor_data import (
    ByteWriter,
    RGB_CAMERA,
    sensor_header,
    sensor_header_seconds,
    image_data,
    image_data_carla,
    optical_flow_data,
    optical_flow_data_degrees,
    dvs_data,
    dvs_data_degrees,
    radar_data,
)
from extensions.carla.opendrive import load_opendrive
from extensions.carla.traffic_manager_collision import (
    CollisionStage,
    CollisionLock,
    GeometryComparison,
    polygon_distance,
    polygon_distance_meters,
)
from extensions.carla.traffic_manager_planning import (
    MotionPlanStage,
    VehicleLightStage,
)
from extensions.carla.traffic_manager_shared import CollisionHazardData
from tests.test_carla_traffic_manager import straight_town
from tests.test_carla_traffic_manager_stages import _setup_follow
from extensions.carla.traffic_manager_map import (
    SimpleWaypoint,
    WaypointId,
    SimpleWaypointIndex,
    distance_squared,
    distance_squared_square_meters,
)
from math.vector3 import Vector3
from render.framebuffer import Framebuffer, Color
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from tests.test_carla_world import _world, _pose, _spawn
from units.si import (
    Duration64,
    Angle,
    Angle64,
    Length,
    Length64,
    Area,
    Velocity,
    InverseLength,
    InverseLength64,
    InverseArea64,
    DEGREE,
    RADIAN,
)


def _max_finite32() -> Float32:
    # Exact largest finite binary32, independent of SDK MAX semantics.
    return bitcast[DType.float32](UInt32(0x7F7FFFFF))


def _max_finite64() -> Float64:
    # Exact largest finite binary64, independent of SDK MAX semantics.
    return bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))


def _bad_nonnegative() -> List[Float64]:
    return [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        -1.0,
        -bitcast[DType.float64](UInt64(1)),
    ]


def _same_bytes(one: List[UInt8], two: List[UInt8]) raises:
    assert_equal(len(one), len(two))
    for i in range(len(one)):
        assert_equal(one[i], two[i])


def _u64(bytes: List[UInt8], offset: Int) -> UInt64:
    var value = UInt64(0)
    for i in range(8):
        value |= UInt64(bytes[offset + i]) << UInt64(8 * i)
    return value


def _u32(bytes: List[UInt8], offset: Int) -> UInt32:
    var value = UInt32(0)
    for i in range(4):
        value |= UInt32(bytes[offset + i]) << UInt32(8 * i)
    return value


def _time_words() -> List[UInt64]:
    return [
        UInt64(0),
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x3FF0000000000001),
        UInt64(0x419D6F3454000043),
        UInt64(0x4270000000000200),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]


def test_sensor_header_retains_float64_time_bits_and_exact_wire_layout() raises:
    for word in _time_words():
        var time = bitcast[DType.float64](word)
        var typed = sensor_header(
            RGB_CAMERA, 42, Duration64(time), _pose(1, 2, 3, 0)
        )
        var raw = sensor_header_seconds(RGB_CAMERA, 42, time, _pose(1, 2, 3, 0))
        _same_bytes(typed, raw)
        assert_equal(len(typed), 48)
        assert_equal(_u64(typed, 0), UInt64(RGB_CAMERA.value))
        assert_equal(_u64(typed, 8), UInt64(42))
        assert_equal(_u64(typed, 16), word)
        assert_equal(_u32(typed, 24), UInt32(0x3F800000))
        assert_equal(_u32(typed, 28), UInt32(0x40000000))
        assert_equal(_u32(typed, 32), UInt32(0x40400000))
    for bad in _bad_nonnegative():
        with assert_raises():
            _ = sensor_header(RGB_CAMERA, 1, Duration64(bad), _pose(0, 0, 0, 0))
        with assert_raises():
            _ = sensor_header_seconds(RGB_CAMERA, 1, bad, _pose(0, 0, 0, 0))


def test_recorder_frame_time_bits_and_tiny_delta_at_large_elapsed_time() raises:
    for word in _time_words():
        var delta = bitcast[DType.float64](word)
        var typed = RecorderFrames()
        var raw = RecorderFrames()
        typed.set_frame(Duration64(0))
        raw.set_frame_seconds(0)
        typed.set_frame(Duration64(delta))
        raw.set_frame_seconds(delta)
        assert_equal(typed.frame.id, raw.frame.id)
        assert_equal(bitcast[DType.uint64](typed.frame.duration_this), word)
        assert_equal(bitcast[DType.uint64](raw.frame.duration_this), word)
        assert_equal(typed.frame.elapsed, raw.frame.elapsed)
        var typed_bytes = ByteWriter()
        var raw_bytes = ByteWriter()
        typed.write_start(typed_bytes)
        raw.write_start(raw_bytes)
        _same_bytes(typed_bytes.bytes, raw_bytes.bytes)
    var frames = RecorderFrames()
    frames.set_frame(Duration64(0))
    var start = 123456789.000001
    frames.set_frame(Duration64(start))
    frames.set_frame(Duration64(1e-6))
    assert_equal(frames.frame.elapsed - start, (start + 1e-6) - start)
    assert_true(frames.frame.elapsed > start)
    assert_equal(Float32(start + 1e-6), Float32(start))
    assert_equal(frames.frame.duration_this, 1e-6)


def test_recorder_frame_bad_time_and_elapsed_overflow_are_atomic() raises:
    var frames = RecorderFrames()
    frames.set_frame(Duration64(0))
    frames.set_frame(Duration64(2))
    for bad in _bad_nonnegative():
        with assert_raises():
            frames.set_frame(Duration64(bad))
        with assert_raises():
            frames.set_frame_seconds(bad)
        assert_equal(frames.frame.id, 2)
        assert_equal(frames.frame.duration_this, 2)
        assert_equal(frames.frame.elapsed, 2)
        assert_equal(frames.offset_previous_frame, 0)
    frames.frame.elapsed = _max_finite64()
    with assert_raises():
        frames.set_frame(Duration64(_max_finite64()))
    assert_equal(frames.frame.id, 2)
    assert_equal(frames.frame.elapsed, _max_finite64())
    assert_equal(frames.frame.duration_this, 2)


def test_recorder_typed_frames_match_raw_bytes_and_patch_tiny_durations() raises:
    var typed = Recorder()
    var raw = Recorder()
    _ = typed.begin_unix_seconds("", "quantity", True, 1790000000)
    _ = raw.begin_unix_seconds("", "quantity", True, 1790000000)
    typed.write_frame(Duration64(0), Duration64(0), Duration64(0))
    raw.write_frame_seconds(0, 0, 0)
    var offset = typed.frames.offset_previous_frame
    var second_start = len(typed.out.bytes)
    var delta = bitcast[DType.float64](UInt64(1))
    var precise = bitcast[DType.float64](UInt64(0x419D6F3454000043))
    typed.write_frame(
        Duration64(delta), Duration64(precise), Duration64(precise)
    )
    raw.write_frame_seconds(delta, precise, precise)
    _same_bytes(typed.bytes(), raw.bytes())
    assert_equal(_u64(typed.bytes(), offset), UInt64(1))
    assert_equal(typed.frames.frame.elapsed, delta)
    assert_equal(typed.frames.frame.id, 2)
    var bytes = typed.bytes()
    var position = second_start
    var exact_times = 0
    while position < len(bytes):
        var kind = Int(bytes[position])
        var size = Int(_u32(bytes, position + 1))
        # Recorder packet 14 is platform time; packet 20 is visual time.
        if kind == 14 or kind == 20:
            assert_equal(size, 8)
            assert_equal(_u64(bytes, position + 5), UInt64(0x419D6F3454000043))
            exact_times += 1
        position += 5 + size
    assert_equal(exact_times, 2)


def test_recorder_rejects_each_time_before_bytes_or_frame_state_change() raises:
    var recorder = Recorder()
    _ = recorder.begin_unix_seconds("", "quantity", True, 1790000000)
    recorder.write_frame(Duration64(0), Duration64(0), Duration64(0))
    var before = recorder.bytes()
    var offset = recorder.frames.offset_previous_frame
    for bad in _bad_nonnegative():
        for field in range(3):
            var times = List[Float64](length=3, fill=0.25)
            times[field] = bad
            with assert_raises():
                recorder.write_frame(
                    Duration64(times[0]),
                    Duration64(times[1]),
                    Duration64(times[2]),
                )
            with assert_raises():
                recorder.write_frame_seconds(times[0], times[1], times[2])
            _same_bytes(recorder.bytes(), before)
            assert_equal(recorder.frames.frame.id, 1)
            assert_equal(recorder.frames.frame.elapsed, 0)
            assert_equal(recorder.frames.frame.duration_this, 0)
            assert_equal(recorder.frames.offset_previous_frame, offset)


def test_image_and_event_angle_adapters_preserve_source_bytes() raises:
    var frame = Framebuffer(2, 1, Color(0, 0, 0))
    frame.set_pixel(0, 0, Color(1, 2, 3, 4))
    frame.set_pixel(1, 0, Color(5, 6, 7, 8))
    var pinhole = image_data(frame, Angle(90, DEGREE))
    _same_bytes(pinhole, image_data_carla(frame, 90))
    assert_equal(_u32(pinhole, 0), UInt32(2))
    assert_equal(_u32(pinhole, 4), UInt32(1))
    assert_equal(_u32(pinhole, 8), UInt32(0x42B40000))
    assert_equal(_u32(pinhole, 12), UInt32(0x04010203))
    assert_equal(_u32(pinhole, 16), UInt32(0x08050607))
    var radians = bitcast[DType.float32](UInt32(0x3FC00001))
    var wide = image_data(frame, Angle(radians, RADIAN), True)
    _same_bytes(wide, image_data_carla(frame, radians))
    assert_equal(_u32(wide, 8), UInt32(0x3FC00001))
    var flow = optical_flow_data(1, 1, Angle(90, DEGREE), [0.5, -0.25])
    _same_bytes(flow, optical_flow_data_degrees(1, 1, 90, [0.5, -0.25]))
    assert_equal(_u32(flow, 12), UInt32(0x3F000000))
    assert_equal(_u32(flow, 16), UInt32(0xBE800000))
    var events = List[DVSEvent]()
    events.append(DVSEvent(1, 0, 123456789, True))
    var dvs = dvs_data(2, 1, Angle(90, DEGREE), events)
    _same_bytes(dvs, dvs_data_degrees(2, 1, 90, events))
    assert_equal(_u64(dvs, 16), UInt64(123456789))
    assert_equal(dvs[24], UInt8(1))


def test_sensor_field_of_view_refuses_bad_angles_at_both_adapters() raises:
    var frame = Framebuffer(1, 1, Color(0, 0, 0))
    for bad64 in _bad_nonnegative():
        var bad = Float32(bad64)
        # A Float64 minimum subnormal rounds to zero in the Float32 API.
        if bad == 0:
            continue
        with assert_raises():
            _ = image_data(frame, Angle(bad))
        with assert_raises():
            _ = image_data(frame, Angle(bad), True)
        with assert_raises():
            _ = image_data_carla(frame, bad)
        with assert_raises():
            _ = optical_flow_data(1, 1, Angle(bad), [0.0, 0.0])
        with assert_raises():
            _ = optical_flow_data_degrees(1, 1, bad, [0.0, 0.0])
        with assert_raises():
            _ = dvs_data(1, 1, Angle(bad), List[DVSEvent]())
        with assert_raises():
            _ = dvs_data_degrees(1, 1, bad, List[DVSEvent]())
    with assert_raises():
        _ = image_data(frame, Angle(-bitcast[DType.float32](UInt32(1))), True)


def test_replay_angle_quantities_use_short_turn_and_checked_fraction() raises:
    comptime TO_RADIANS = 0.017453292519943295
    var forward = lerp_angle(
        Angle64(170.0 * TO_RADIANS), Angle64(-170.0 * TO_RADIANS), 0.5
    )
    var backward = lerp_angle(
        Angle64(-170.0 * TO_RADIANS), Angle64(170.0 * TO_RADIANS), 0.5
    )
    assert_true(abs(forward.value - 3.141592653589793) < 1e-14)
    assert_true(abs(backward.value + 3.141592653589793) < 1e-14)
    assert_equal(lerp_angle_degrees(170, -170, 0.5), 180)
    assert_equal(lerp_angle_degrees(-170, 170, 0.5), -180)
    assert_equal(lerp_angle_degrees(10, 50, 0), 10)
    assert_equal(lerp_angle_degrees(10, 50, 1), 50)
    var fractions = _bad_nonnegative()
    fractions.append(1.0000000000000002)
    for bad in fractions:
        with assert_raises():
            _ = lerp_angle(Angle64(0), Angle64(1), bad)
        with assert_raises():
            _ = lerp_angle_degrees(0, 1, bad)
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        with assert_raises():
            _ = lerp_angle(Angle64(bad), Angle64(0), 0.5)
        with assert_raises():
            _ = lerp_angle(Angle64(0), Angle64(bad), 0.5)
        with assert_raises():
            _ = lerp_angle_degrees(bad, 0, 0.5)
        with assert_raises():
            _ = lerp_angle_degrees(0, bad, 0.5)
    with assert_raises():
        _ = lerp_angle_degrees(-_max_finite64(), _max_finite64(), 0.5)
    with assert_raises():
        _ = lerp_angle(Angle64(_max_finite64()), Angle64(0), 0.5)


def test_walker_speed_quantity_and_explicit_centimeter_adapter_are_atomic() raises:
    var world = _world()
    var walker = _spawn(world, "walker.pedestrian.0015", _pose(50, -4, 1.2, 0))
    set_walker_speed(world, walker, Velocity(2.5))
    var typed = world.get_walker_control(walker)
    assert_equal(typed.speed.value, 2.5)
    set_walker_speed_centimeters_per_second(world, walker, 250)
    var raw = world.get_walker_control(walker)
    assert_equal(raw.speed.value, typed.speed.value)
    assert_equal(raw.direction.x, typed.direction.x)
    assert_equal(raw.direction.y, typed.direction.y)
    assert_equal(raw.direction.z, typed.direction.z)
    assert_equal(raw.jump, typed.jump)
    for bad64 in _bad_nonnegative():
        var bad = Float32(bad64)
        if bad == 0:
            continue
        with assert_raises():
            set_walker_speed(world, walker, Velocity(bad))
        with assert_raises():
            set_walker_speed_centimeters_per_second(world, walker, bad)
        assert_equal(world.get_walker_control(walker).speed.value, 2.5)
    set_walker_speed(world, walker, Velocity(0))
    assert_equal(world.get_walker_control(walker).speed.value, 0)
    set_walker_speed(world, ActorId(999999), Velocity(1))
    assert_equal(world.get_walker_control(walker).speed.value, 0)


def test_physical_distance_outputs_have_units_and_keep_raw_arithmetic() raises:
    var a = Vector3(0, 0, 100)
    var b = Vector3(4, 0, -100)
    var c = Vector3(0, 3, 50)
    var d = Vector3(4, 3, -50)
    var gap: Length64 = segment_distance_2d(a, b, c, d)
    assert_equal(gap.value, 3)
    assert_equal(gap.value, segment_distance_2d_meters(a, b, c, d))
    assert_equal(
        segment_distance_2d(
            a, Vector3(4, 4, 0), Vector3(0, 4, 0), Vector3(4, 0, 0)
        ).value,
        0,
    )
    var squared: Area = distance_squared(Vector3(1, 2, 3), Vector3(4, 6, 3))
    assert_equal(squared.value, 25)
    assert_equal(
        squared.value,
        distance_squared_square_meters(Vector3(1, 2, 3), Vector3(4, 6, 3)),
    )
    var world = _world()
    var waypoint = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(1))
    var node = SimpleWaypoint(world.map, waypoint, WaypointId(1))
    var target = node.location() + Vector3(3, 4, 0)
    var distance: Length = node.distance(target)
    var distance2: Area = node.distance_squared(target)
    assert_equal(distance.value, 5)
    assert_equal(distance2.value, 25)
    assert_equal(distance.value, node.distance_meters(target))
    assert_equal(distance2.value, node.distance_squared_square_meters(target))


def test_fog_extinction_has_inverse_length_and_matches_explicit_adapter() raises:
    var fog = HeightFog(
        InverseLength(0.125),
        Length(0),
        InverseLength(0),
        1,
        InverseLength(0.25),
    )
    var extinction: InverseLength = fog_density_at(fog, Length(20))
    assert_equal(extinction.value, 0.375)
    assert_equal(extinction.value, fog_density_at_per_meter(fog, Length(20)))


def test_loft_typed_lists_match_explicit_meter_geometry() raises:
    var typed = loft(
        [Length(0), Length(2)],
        [Length(1), Length(1)],
        [Length(0), Length(0)],
        [Length(1), Length(1)],
        0.25,
        8,
    )
    var raw = loft_meters(
        [0.0, 2.0], [1.0, 1.0], [0.0, 0.0], [1.0, 1.0], 0.25, 8
    )
    assert_equal(typed.vertex_count(), raw.vertex_count())
    assert_equal(typed.triangle_count(), raw.triangle_count())
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises():
            _ = loft(
                [Length(0), Length(bad)],
                [Length(1), Length(1)],
                [Length(0), Length(0)],
                [Length(1), Length(1)],
                0.25,
                8,
            )
        with assert_raises():
            _ = loft(
                [Length(0), Length(2)],
                [Length(1), Length(bad)],
                [Length(0), Length(0)],
                [Length(1), Length(1)],
                0.25,
                8,
            )
        with assert_raises():
            _ = loft(
                [Length(0), Length(2)],
                [Length(1), Length(1)],
                [Length(0), Length(bad)],
                [Length(1), Length(1)],
                0.25,
                8,
            )
        with assert_raises():
            _ = loft(
                [Length(0), Length(2)],
                [Length(1), Length(1)],
                [Length(0), Length(0)],
                [Length(1), Length(bad)],
                0.25,
                8,
            )
    with assert_raises():
        _ = loft([Length(0)], [Length(1)], [Length(0)], [Length(1)], 0.25, 8)
    with assert_raises():
        _ = loft(
            [Length(0), Length(2)],
            [Length(1)],
            [Length(0), Length(0)],
            [Length(1), Length(1)],
            0.25,
            8,
        )
    with assert_raises():
        _ = loft(
            [Length(0), Length(2)],
            [Length(1), Length(1)],
            [Length(0), Length(0)],
            [Length(1), Length(1)],
            0.25,
            3,
        )


def test_radar_velocity_constructor_view_and_wire_bytes_keep_float32_bits() raises:
    for word in [
        UInt32(0x80000000),
        UInt32(1),
        UInt32(0x3F800001),
        UInt32(0x7F7FFFFF),
        UInt32(0xBFC00000),
    ]:
        var speed = bitcast[DType.float32](word)
        var typed = RadarDetection(
            Velocity(speed), Angle(0.25), Angle(-0.125), Length(12.5)
        )
        var raw = RadarDetection.from_si(
            speed, Angle(0.25), Angle(-0.125), Length(12.5)
        )
        assert_equal(bitcast[DType.uint32](typed.velocity), word)
        assert_equal(
            bitcast[DType.uint32](typed.velocity_quantity().value), word
        )
        _same_bytes(radar_data([typed]), radar_data([raw]))
        assert_equal(_u32(radar_data([typed]), 0), word)
        assert_equal(_u32(radar_data([typed]), 4), UInt32(0x3E800000))
        assert_equal(_u32(radar_data([typed]), 8), UInt32(0xBE000000))
        assert_equal(_u32(radar_data([typed]), 12), UInt32(0x41480000))
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises():
            _ = RadarDetection(Velocity(bad), Angle(0), Angle(0), Length(1))
        with assert_raises():
            _ = RadarDetection.from_si(bad, Angle(0), Angle(0), Length(1))
        var record = RadarDetection(Velocity(0), Angle(0), Angle(0), Length(1))
        record.velocity = bad
        with assert_raises():
            _ = record.velocity_quantity()


def test_pedestrian_speed_list_constructor_views_and_raw_records() raises:
    var precise = bitcast[DType.float32](UInt32(0x3F800001))
    var typed = PedestrianParameters(
        "0015",
        GENDER_OTHER,
        AGE_ADULT,
        1,
        [Velocity(0), Velocity(precise), Velocity(3)],
    )
    var raw = PedestrianParameters.from_meters_per_second(
        "0015", GENDER_OTHER, AGE_ADULT, 1, [0.0, precise, 3.0]
    )
    var views = typed.speeds_quantity()
    assert_equal(len(views), 3)
    for i in range(3):
        assert_equal(
            bitcast[DType.uint32](typed.speeds[i]),
            bitcast[DType.uint32](raw.speeds[i]),
        )
        assert_equal(
            bitcast[DType.uint32](views[i].value),
            bitcast[DType.uint32](raw.speeds[i]),
        )
    assert_equal(bitcast[DType.uint32](typed.speeds[1]), UInt32(0x3F800001))
    assert_equal(
        len(
            PedestrianParameters(
                "empty", GENDER_OTHER, AGE_ADULT, 1, List[Velocity]()
            ).speeds_quantity()
        ),
        0,
    )
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        Float32(-1),
    ]:
        with assert_raises():
            _ = PedestrianParameters(
                "0015", GENDER_OTHER, AGE_ADULT, 1, [Velocity(0), Velocity(bad)]
            )
        with assert_raises():
            _ = PedestrianParameters.from_meters_per_second(
                "0015", GENDER_OTHER, AGE_ADULT, 1, [Float32(0), bad]
            )
        typed.speeds[1] = bad
        with assert_raises():
            _ = typed.speeds_quantity()
        typed.speeds[1] = precise


def test_distance_boundaries_refuse_nonfinite_coordinates_and_overflow() raises:
    var zero = Vector3(0, 0, 0)
    var other = Vector3(1, 1, 1)
    var world = _world()
    var waypoint = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(1))
    var node = SimpleWaypoint(world.map, waypoint, WaypointId(1))
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for axis in range(3):
            var point = Vector3(0, 0, 0)
            if axis == 0:
                point.x = bad
            elif axis == 1:
                point.y = bad
            else:
                point.z = bad
            with assert_raises():
                _ = distance_squared(point, zero)
            with assert_raises():
                _ = distance_squared(zero, point)
            with assert_raises():
                _ = node.distance(point)
            with assert_raises():
                _ = node.distance_squared(point)
            if axis < 2:
                with assert_raises():
                    _ = segment_distance_2d(point, other, zero, other)
                with assert_raises():
                    _ = segment_distance_2d(zero, point, zero, other)
                with assert_raises():
                    _ = segment_distance_2d(zero, other, point, other)
                with assert_raises():
                    _ = segment_distance_2d(zero, other, zero, point)
            else:
                # This operation is explicitly planar; z never enters it.
                assert_equal(
                    segment_distance_2d(point, other, zero, other).value, 0
                )
    with assert_raises():
        _ = distance_squared(zero, Vector3(_max_finite32(), 0, 0))
    with assert_raises():
        _ = node.distance_squared(Vector3(_max_finite32(), 0, 0))
    node.transform.location.x = _max_finite32()
    with assert_raises():
        _ = node.distance(Vector3(-_max_finite32(), 0, 0))


def test_fog_rejects_bad_parameters_and_nonfinite_result() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        Float32(-1),
    ]:
        var fog = HeightFog(
            InverseLength(0.125),
            Length(0),
            InverseLength(0),
            1,
            InverseLength(0.25),
        )
        fog.density = InverseLength(bad)
        with assert_raises():
            _ = fog_density_at(fog, Length(0))
        fog.density = InverseLength(0.125)
        fog.falloff = InverseLength(bad)
        with assert_raises():
            _ = fog_density_at(fog, Length(0))
        fog.falloff = InverseLength(0)
        fog.haze = InverseLength(bad)
        with assert_raises():
            _ = fog_density_at(fog, Length(0))
    var fog = HeightFog(
        InverseLength(1), Length(0), InverseLength(1), 1, InverseLength(0)
    )
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises():
            _ = fog_density_at(fog, Length(bad))
        with assert_raises():
            _ = fog_density_at_per_meter(fog, Length(bad))
    with assert_raises():
        _ = fog_density_at(fog, Length(-_max_finite32()))


def test_loft_refuses_negative_width_inverted_heights_and_bad_taper() raises:
    for taper in [
        Float32(-1),
        Float32(1.0000001192092896),
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        with assert_raises():
            _ = loft(
                [Length(0), Length(2)],
                [Length(1), Length(1)],
                [Length(0), Length(0)],
                [Length(1), Length(1)],
                taper,
                8,
            )
    with assert_raises():
        _ = loft(
            [Length(0), Length(2)],
            [Length(1), Length(-1)],
            [Length(0), Length(0)],
            [Length(1), Length(1)],
            0,
            8,
        )
    with assert_raises():
        _ = loft_meters([0.0, 2.0], [1.0, 1.0], [0.0, 2.0], [1.0, 1.0], 0, 8)


def test_radar_rejects_nonfinite_angles_and_invalid_range() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises():
            _ = RadarDetection(Velocity(0), Angle(bad), Angle(0), Length(1))
        with assert_raises():
            _ = RadarDetection(Velocity(0), Angle(0), Angle(bad), Length(1))
        with assert_raises():
            _ = RadarDetection(Velocity(0), Angle(0), Angle(0), Length(bad))
    with assert_raises():
        _ = RadarDetection(
            Velocity(0),
            Angle(0),
            Angle(0),
            Length(-bitcast[DType.float32](UInt32(1))),
        )


def test_normalized_cubic_coefficients_are_lengths_and_derivative_is_length() raises:
    var p = NormalizedCubic(Length64(1), Length64(2), Length64(3), Length64(4))
    var raw = NormalizedCubic.from_meters(1, 2, 3, 4)
    var value: Length64 = p.evaluate(0.5)
    var tangent: Length64 = p.tangent(0.5)
    # a + bp + cp^2 + dp^3 and b + 2cp + 3dp^2, independently at p=1/2.
    assert_equal(value.value, 3.25)
    assert_equal(tangent.value, 8.0)
    assert_equal(value.value, raw.evaluate(0.5).value)
    assert_equal(tangent.value, raw.tangent(0.5).value)
    assert_equal(p.evaluate(0).value, 1)
    assert_equal(p.evaluate(1).value, 10)
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x3FF0000000000001),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var coefficient = bitcast[DType.float64](word)
        var fields = NormalizedCubic(
            Length64(coefficient),
            Length64(coefficient),
            Length64(coefficient),
            Length64(coefficient),
        )
        assert_equal(bitcast[DType.uint64](fields.a.value), word)
        assert_equal(bitcast[DType.uint64](fields.b.value), word)
        assert_equal(bitcast[DType.uint64](fields.c.value), word)
        assert_equal(bitcast[DType.uint64](fields.d.value), word)
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        for field in range(4):
            var values = List[Float64](length=4, fill=0.0)
            values[field] = bad
            with assert_raises():
                _ = NormalizedCubic(
                    Length64(values[0]),
                    Length64(values[1]),
                    Length64(values[2]),
                    Length64(values[3]),
                )
            with assert_raises():
                _ = NormalizedCubic.from_meters(
                    values[0], values[1], values[2], values[3]
                )
        with assert_raises():
            _ = p.evaluate(bad)
        with assert_raises():
            _ = p.tangent(bad)


def _param_base() raises -> RoadGeometry:
    return RoadGeometry(
        LINE, Length64(0), Length64(1), Length64(2), Angle64(0), Length64(10)
    )


def test_parametric_arc_and_normalized_factories_have_distinct_typed_coefficients() raises:
    var arc_u = CubicPolynomial(
        Length64(0), 1, InverseLength64(0), InverseArea64(0), Length64(0)
    )
    var arc_v = CubicPolynomial.constant(Length64(0))
    var norm_u = NormalizedCubic(
        Length64(0), Length64(10), Length64(0), Length64(0)
    )
    var norm_v = NormalizedCubic.from_meters(0, 0, 0, 0)
    var arc = with_param_poly3(_param_base(), arc_u, arc_v)
    var normalized = with_param_poly3_normalized(_param_base(), norm_u, norm_v)
    var raw_normalized = with_param_poly3_from_coefficients(
        _param_base(),
        CubicPolynomial.from_coefficients(0, 10, 0, 0, 0),
        arc_v,
        NORMALIZED,
    )
    assert_equal(len(normalized.samples), len(raw_normalized.samples))
    for i in range(len(normalized.samples)):
        assert_equal(normalized.samples[i].s, raw_normalized.samples[i].s)
        assert_equal(normalized.samples[i].u, raw_normalized.samples[i].u)
        assert_equal(normalized.samples[i].v, raw_normalized.samples[i].v)
        assert_equal(normalized.samples[i].tu, raw_normalized.samples[i].tu)
        assert_equal(normalized.samples[i].tv, raw_normalized.samples[i].tv)
    for station in [0.0, 2.5, 5.0, 10.0]:
        var a = arc.pos_at(Length64(station))
        var n = normalized.pos_at(Length64(station))
        assert_true(abs(a.x - n.x) <= 1e-12)
        assert_true(abs(a.y - n.y) <= 1e-12)
    var arc_factory = param_poly3(
        Length64(0),
        Length64(1),
        Length64(2),
        Angle64(0),
        Length64(10),
        arc_u,
        arc_v,
    )
    var normalized_factory = param_poly3_normalized(
        Length64(0),
        Length64(1),
        Length64(2),
        Angle64(0),
        Length64(10),
        norm_u,
        norm_v,
    )
    assert_equal(arc_factory.pos_at(Length64(5)).x, 6)
    assert_true(abs(normalized_factory.pos_at(Length64(5)).x - 6) <= 1e-12)


def test_normalized_builder_profile_and_base_fields_validate_before_append() raises:
    var builder = MapBuilder()
    var road = builder.add_road(
        RoadId(1),
        "normalized",
        Length64(10),
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    var u = NormalizedCubic.from_meters(0, 10, 0, 0)
    var v = NormalizedCubic.from_meters(0, 0, 0, 0)
    builder.add_road_geometry_param_poly3_normalized(
        road,
        Length64(0),
        Length64(1),
        Length64(2),
        Angle64(0),
        Length64(10),
        u,
        v,
    )
    assert_equal(len(builder.roads[0].info.geometries), 1)
    assert_true(
        abs(
            builder.roads[0].info.geometries[0].geometry.pos_at(Length64(5)).x
            - 6
        )
        <= 1e-12
    )
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        with assert_raises():
            builder.add_road_geometry_param_poly3_normalized(
                road,
                Length64(bad),
                Length64(1),
                Length64(2),
                Angle64(0),
                Length64(10),
                u,
                v,
            )
        with assert_raises():
            builder.add_road_geometry_param_poly3_normalized(
                road,
                Length64(0),
                Length64(bad),
                Length64(2),
                Angle64(0),
                Length64(10),
                u,
                v,
            )
        with assert_raises():
            builder.add_road_geometry_param_poly3_normalized(
                road,
                Length64(0),
                Length64(1),
                Length64(bad),
                Angle64(0),
                Length64(10),
                u,
                v,
            )
        with assert_raises():
            builder.add_road_geometry_param_poly3_normalized(
                road,
                Length64(0),
                Length64(1),
                Length64(2),
                Angle64(bad),
                Length64(10),
                u,
                v,
            )
        with assert_raises():
            builder.add_road_geometry_param_poly3_normalized(
                road,
                Length64(0),
                Length64(1),
                Length64(2),
                Angle64(0),
                Length64(bad),
                u,
                v,
            )
        var mutated = u
        mutated.b = Length64(bad)
        with assert_raises():
            builder.add_road_geometry_param_poly3_normalized(
                road,
                Length64(0),
                Length64(1),
                Length64(2),
                Angle64(0),
                Length64(10),
                mutated,
                v,
            )
        assert_equal(len(builder.roads[0].info.geometries), 1)


def test_normalized_parameter_domain_and_mutated_coefficients_are_checked() raises:
    var p = NormalizedCubic.from_meters(1, 2, 3, 4)
    for parameter in [
        -bitcast[DType.float64](UInt64(1)),
        -1.0,
        1.0000000000000002,
    ]:
        with assert_raises():
            _ = p.evaluate(parameter)
        with assert_raises():
            _ = p.tangent(parameter)
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        var p = NormalizedCubic.from_meters(1, 2, 3, 4)
        p.a = Length64(bad)
        with assert_raises():
            _ = p.evaluate(0.5)
        p = NormalizedCubic.from_meters(1, 2, 3, 4)
        p.b = Length64(bad)
        with assert_raises():
            _ = p.tangent(0.5)
        p = NormalizedCubic.from_meters(1, 2, 3, 4)
        p.c = Length64(bad)
        with assert_raises():
            _ = p.evaluate(0.5)
        p = NormalizedCubic.from_meters(1, 2, 3, 4)
        p.d = Length64(bad)
        with assert_raises():
            _ = p.tangent(0.5)
    var huge = NormalizedCubic.from_meters(
        _max_finite64(), _max_finite64(), 0, 0
    )
    with assert_raises():
        _ = huge.evaluate(1)


def test_time_packet_bytes_preserve_bits_and_bad_values_are_atomic() raises:
    for word in _time_words():
        var time = bitcast[DType.float64](word)
        var typed = ByteWriter()
        var raw = ByteWriter()
        time_packet(typed, PACKET_VISUAL_TIME, Duration64(time))
        time_packet_seconds(raw, PACKET_VISUAL_TIME, time)
        _same_bytes(typed.bytes, raw.bytes)
        assert_equal(len(typed.bytes), 13)
        assert_equal(_u64(typed.bytes, 5), word)
    var writer = ByteWriter()
    writer.u8(UInt8(19))
    for bad in _bad_nonnegative():
        with assert_raises():
            time_packet(writer, PACKET_VISUAL_TIME, Duration64(bad))
        with assert_raises():
            time_packet_seconds(writer, PACKET_VISUAL_TIME, bad)
        assert_equal(len(writer.bytes), 1)
        assert_equal(writer.bytes[0], UInt8(19))


def test_polygon_distance_uses_absence_for_empty_polygon() raises:
    var one: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        Vector3(2, 2, 0),
        Vector3(0, 2, 0),
    ]
    var two: List[Vector3] = [
        Vector3(5, 0, 0),
        Vector3(7, 0, 0),
        Vector3(7, 2, 0),
        Vector3(5, 2, 0),
    ]
    var separation: Optional[Length64] = polygon_distance(one, two)
    assert_true(Bool(separation))
    assert_equal(separation.value().value, 3)
    assert_equal(separation.value().value, polygon_distance_meters(one, two))
    assert_equal(polygon_distance(one, one).value().value, 0)
    assert_false(Bool(polygon_distance(List[Vector3](), one)))
    assert_false(Bool(polygon_distance(one, List[Vector3]())))
    assert_false(Bool(polygon_distance(List[Vector3](), List[Vector3]())))
    assert_equal(
        polygon_distance_meters(List[Vector3](), one), inf[DType.float64]()
    )
    assert_equal(
        polygon_distance_meters(one, List[Vector3]()), inf[DType.float64]()
    )
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        var invalid = one.copy()
        invalid[0].x = bad
        with assert_raises():
            _ = polygon_distance(invalid, two)
        with assert_raises():
            _ = polygon_distance(two, invalid)
        invalid = one.copy()
        invalid[0].y = bad
        with assert_raises():
            _ = polygon_distance(invalid, two)


def test_collision_and_motion_plan_results_carry_physical_quantities() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var collision = CollisionStage()
    collision.collision_locks[1] = CollisionLock(9, 9, ActorId(2))
    collision.geometry_cache[(1 << 32) | 2] = GeometryComparison(3, 2, 0, 1)
    var yield_result: Tuple[
        Bool, Optional[Length]
    ] = collision.negotiate_collision(ActorId(1), ActorId(2), 0, shared)
    assert_true(yield_result[0])
    assert_true(Bool(yield_result[1]))
    assert_equal(yield_result[1].value().value, 1)
    var extension: Length = collision.get_bounding_box_extension(
        ActorId(1), shared
    )
    assert_equal(
        extension.value,
        collision.get_bounding_box_extension_meters(ActorId(1), shared),
    )
    var clear = CollisionStage()
    var absent = clear.negotiate_collision(ActorId(2), ActorId(1), 0, shared)
    assert_false(absent[0])
    assert_false(Bool(absent[1]))
    var absent_raw = clear.negotiate_collision_meters(
        ActorId(2), ActorId(1), 0, shared
    )
    assert_false(absent_raw[0])
    assert_equal(absent_raw[1], inf[DType.float32]())
    var plan = MotionPlanStage()
    var path: List[SimpleWaypointIndex] = [
        SimpleWaypointIndex(60),
        SimpleWaypointIndex(61),
    ]
    var offset: Length = plan.calculate_base_offset(
        ActorId(1), path, False, 1, shared
    )
    assert_equal(
        offset.value,
        plan.calculate_base_offset_meters(ActorId(1), path, False, 1, shared),
    )
    var hazard = CollisionHazardData(Length(30), ActorId(2), True)
    var target: Tuple[Bool, Velocity] = plan.collision_handling(
        hazard, False, Vector3(10, 0, 0), Vector3(1, 0, 0), Velocity(12), shared
    )
    var target_raw = plan.collision_handling_meters_per_second(
        hazard, False, Vector3(10, 0, 0), Vector3(1, 0, 0), 12, shared
    )
    assert_equal(target[0], target_raw[0])
    assert_equal(target[1].value, target_raw[1])
    var turn: Velocity = plan.get_turn_target_velocity(
        path, Velocity(8), shared
    )
    assert_equal(turn.value, 8)
    assert_equal(
        turn.value,
        plan.get_turn_target_velocity_meters_per_second(path, 8, shared),
    )
    var landmark: Velocity = plan.get_landmark_target_velocity(
        path[0], Vector3(50, 1.75, 0), ActorId(1), Velocity(8), shared, map
    )
    assert_equal(
        landmark.value,
        plan.get_landmark_target_velocity_meters_per_second(
            path[0], Vector3(50, 1.75, 0), ActorId(1), 8, shared, map
        ),
    )
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        Float32(-1),
    ]:
        with assert_raises():
            _ = plan.collision_handling(
                hazard,
                False,
                Vector3(10, 0, 0),
                Vector3(1, 0, 0),
                Velocity(bad),
                shared,
            )
        with assert_raises():
            _ = plan.get_turn_target_velocity(path, Velocity(bad), shared)
        with assert_raises():
            _ = plan.get_landmark_target_velocity(
                path[0],
                Vector3(50, 1.75, 0),
                ActorId(1),
                Velocity(bad),
                shared,
                map,
            )


def test_sampled_geometry_budgets_reject_before_work_and_count_appends() raises:
    var u = CubicPolynomial.from_coefficients(0, 1, 0, 0, 0)
    var zero = CubicPolynomial.constant(Length64(0))
    var nu = NormalizedCubic.from_meters(0, 10, 0, 0)
    var nz = NormalizedCubic.from_meters(0, 0, 0, 0)
    for budget in [-1, 0, 1]:
        with assert_raises():
            _ = with_poly3(
                _param_base(),
                Length64(0),
                0,
                InverseLength64(0),
                InverseArea64(0),
                max_samples=budget,
            )
        with assert_raises():
            _ = with_poly3_si(_param_base(), 0, 0, 0, 0, max_samples=budget)
        with assert_raises():
            _ = with_param_poly3(_param_base(), u, zero, max_samples=budget)
        with assert_raises():
            _ = with_param_poly3_normalized(
                _param_base(), nu, nz, max_samples=budget
            )
        with assert_raises():
            _ = with_param_poly3_from_coefficients(
                _param_base(), u, zero, ARC_LENGTH, max_samples=budget
            )
        with assert_raises():
            _ = poly3(
                Length64(0),
                Length64(1),
                Length64(2),
                Angle64(0),
                Length64(10),
                Length64(0),
                0,
                InverseLength64(0),
                InverseArea64(0),
                max_samples=budget,
            )
        with assert_raises():
            _ = poly3_from_coefficients(
                Length(0),
                Length(1),
                Length(2),
                Angle(0),
                Length(10),
                0,
                0,
                0,
                0,
                max_samples=budget,
            )
        with assert_raises():
            _ = param_poly3(
                Length64(0),
                Length64(1),
                Length64(2),
                Angle64(0),
                Length64(10),
                u,
                zero,
                max_samples=budget,
            )
        with assert_raises():
            _ = param_poly3_normalized(
                Length64(0),
                Length64(1),
                Length64(2),
                Angle64(0),
                Length64(10),
                nu,
                nz,
                max_samples=budget,
            )
        with assert_raises():
            _ = param_poly3_from_coefficients(
                Length(0),
                Length(1),
                Length(2),
                Angle(0),
                Length(10),
                u,
                zero,
                ARC_LENGTH,
                max_samples=budget,
            )
    var polynomial = with_poly3_si(_param_base(), 0, 0, 0, 0)
    var polynomial_count = len(polynomial.samples)
    var exact_poly = with_poly3_si(
        _param_base(), 0, 0, 0, 0, max_samples=polynomial_count
    )
    assert_equal(len(exact_poly.samples), polynomial_count)
    with assert_raises():
        _ = with_poly3_si(
            _param_base(), 0, 0, 0, 0, max_samples=polynomial_count - 1
        )
    var arc = with_param_poly3(_param_base(), u, zero)
    var exact_arc = with_param_poly3(
        _param_base(), u, zero, max_samples=len(arc.samples)
    )
    assert_equal(len(exact_arc.samples), len(arc.samples))
    with assert_raises():
        _ = with_param_poly3(
            _param_base(), u, zero, max_samples=len(arc.samples) - 1
        )
    var normalized = with_param_poly3_normalized(_param_base(), nu, nz)
    var exact_normalized = with_param_poly3_normalized(
        _param_base(), nu, nz, max_samples=len(normalized.samples)
    )
    assert_equal(len(exact_normalized.samples), len(normalized.samples))
    with assert_raises():
        _ = with_param_poly3_normalized(
            _param_base(), nu, nz, max_samples=len(normalized.samples) - 1
        )


def _sampled_base_refused(base: RoadGeometry) raises:
    var u = CubicPolynomial.from_coefficients(0, 1, 0, 0, 0)
    var zero = CubicPolynomial.constant(Length64(0))
    with assert_raises():
        _ = with_poly3(
            base.copy(),
            Length64(0),
            0,
            InverseLength64(0),
            InverseArea64(0),
            max_samples=64,
        )
    with assert_raises():
        _ = with_poly3_si(base.copy(), 0, 0, 0, 0, max_samples=64)
    with assert_raises():
        _ = with_param_poly3(base.copy(), u, zero, max_samples=64)
    with assert_raises():
        _ = with_param_poly3_from_coefficients(
            base.copy(), u, zero, ARC_LENGTH, max_samples=64
        )
    with assert_raises():
        _ = with_param_poly3_normalized(
            base.copy(),
            NormalizedCubic.from_meters(0, 10, 0, 0),
            NormalizedCubic.from_meters(0, 0, 0, 0),
            max_samples=64,
        )


def test_sampled_geometry_rejects_mutated_common_fields_and_huge_lengths() raises:
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        var base = _param_base()
        base.s = bad
        _sampled_base_refused(base)
        base = _param_base()
        base.x = bad
        _sampled_base_refused(base)
        base = _param_base()
        base.y = bad
        _sampled_base_refused(base)
        base = _param_base()
        base.heading = bad
        _sampled_base_refused(base)
        base = _param_base()
        base.length = bad
        _sampled_base_refused(base)
    var base = _param_base()
    base.kind = RoadGeometryKind(99)
    _sampled_base_refused(base)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        base = _param_base()
        base.s = bad
        _sampled_base_refused(base)
        base = _param_base()
        base.length = bad
        _sampled_base_refused(base)
    base = _param_base()
    base.length = 0
    _sampled_base_refused(base)
    base = _param_base()
    base.length = _max_finite64()
    _sampled_base_refused(base)
    base.s = _max_finite64()
    _sampled_base_refused(base)


def test_sampled_geometry_refuses_overflow_and_unrepresentable_progress() raises:
    var zero = CubicPolynomial.constant(Length64(0))
    with assert_raises():
        _ = with_poly3_si(
            _param_base(), 0, 0, _max_finite64(), 0, max_samples=64
        )
    with assert_raises():
        _ = with_param_poly3(
            _param_base(),
            CubicPolynomial.from_coefficients(0, _max_finite64(), 0, 0, 0),
            zero,
            max_samples=64,
        )
    with assert_raises():
        _ = with_param_poly3_normalized(
            _param_base(),
            NormalizedCubic.from_meters(0, _max_finite64(), 0, 0),
            NormalizedCubic.from_meters(0, 0, 0, 0),
            max_samples=64,
        )
    # An extreme finite origin must not bypass finite sample/progress checks.
    var shifted = CubicPolynomial.from_coefficients(
        0, 1, 0, 0, -_max_finite64()
    )
    with assert_raises():
        _ = with_param_poly3(_param_base(), shifted, zero, max_samples=64)
    # At this magnitude all generated unit-scale coordinate steps disappear.
    with assert_raises():
        _ = with_param_poly3(
            _param_base(),
            CubicPolynomial.from_coefficients(1e100, 1, 0, 0, 0),
            zero,
            max_samples=64,
        )
    with assert_raises():
        _ = with_param_poly3(_param_base(), zero, zero, max_samples=64)
    var tiny = _param_base()
    tiny.length = bitcast[DType.float64](UInt64(1))
    with assert_raises():
        _ = with_param_poly3(
            tiny.copy(),
            CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
            zero,
            max_samples=64,
        )
    with assert_raises():
        _ = with_param_poly3_normalized(
            _param_base(),
            NormalizedCubic.from_meters(
                0, bitcast[DType.float64](UInt64(1)), 0, 0
            ),
            NormalizedCubic.from_meters(0, 0, 0, 0),
            max_samples=64,
        )


def test_world_and_vehicle_light_weather_rejection_is_atomic() raises:
    var world = _world()
    var good = WeatherParameters()
    good.cloudiness = 25
    world.set_weather(good)
    var stage = VehicleLightStage()
    stage.update_world_info([(ActorId(1), LIGHT_POSITION)], good)
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        var weather = good
        weather.fog_distance = Length(bad)
        with assert_raises():
            world.set_weather(weather)
        assert_equal(world.get_weather(), good)
        with assert_raises():
            stage.update_world_info([(ActorId(2), LIGHTS_NONE)], weather)
        assert_equal(stage.weather, good)
        assert_true(stage.is_weather_enabled)
        assert_equal(len(stage.all_light_states), 1)
        assert_equal(stage.all_light_states[0][0], ActorId(1))
        assert_equal(stage.all_light_states[0][1], LIGHT_POSITION)
        # Disabled weather is intentionally ignored, but light states still update.
        stage.update_world_info([(ActorId(2), LIGHTS_NONE)], weather, False)
        assert_false(stage.is_weather_enabled)
        assert_equal(stage.weather, good)
        assert_equal(stage.all_light_states[0][0], ActorId(2))
        assert_equal(stage.all_light_states[0][1], LIGHTS_NONE)
        stage.update_world_info([(ActorId(1), LIGHT_POSITION)], good)


def test_town_refuses_mutated_weather_before_material_or_wetness_changes() raises:
    var world = _world()
    var scene = Scene()
    var assets = Assets()
    var settings = TownSettings()
    settings.texture_size = 2
    settings.buildings = False
    settings.trees = False
    settings.lamps = False
    var town = Town(world.map, scene, assets, settings^)
    var before = assets.materials.get(town.materials.surfaces[0])
    var wetness = town.wet.wetness
    var puddles = town.wet.puddles
    var texture = town.puddle_roughness_id
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        var weather = WeatherParameters()
        weather.wetness = 75
        weather.precipitation_deposits = 75
        weather.sun_altitude_angle = Angle(bad)
        with assert_raises():
            town.set_weather(scene, assets, weather)
        var after = assets.materials.get(town.materials.surfaces[0])
        assert_equal(after.roughness, before.roughness)
        assert_equal(after.color.r, before.color.r)
        assert_equal(after.color.g, before.color.g)
        assert_equal(after.color.b, before.color.b)
        assert_equal(town.wet.wetness, wetness)
        assert_equal(town.wet.puddles, puddles)
        assert_equal(town.puddle_roughness_id, texture)


def test_map_tiny_steps_validate_mutated_waypoint_before_shortcut() raises:
    var world = _world()
    var waypoint = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(1))
    var tiny = bitcast[DType.float64](UInt64(1))
    var next = world.map.next(waypoint, Length64(tiny))
    var previous = world.map.previous(waypoint, Length64(tiny))
    assert_equal(len(next), 1)
    assert_equal(len(previous), 1)
    assert_equal(
        bitcast[DType.uint64](next[0].s), bitcast[DType.uint64](waypoint.s)
    )
    assert_equal(
        bitcast[DType.uint64](previous[0].s), bitcast[DType.uint64](waypoint.s)
    )
    for bad in _bad_nonnegative():
        waypoint.s = bad
        with assert_raises():
            _ = world.map.next(waypoint, Length64(tiny))
        with assert_raises():
            _ = world.map.previous(waypoint, Length64(tiny))
        with assert_raises():
            _ = world.map.next_meters(waypoint, tiny)
        with assert_raises():
            _ = world.map.previous_meters(waypoint, tiny)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
