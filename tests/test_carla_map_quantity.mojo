# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Float64 quantity boundaries, raw adapters, and transactional map assembly."""

from extensions.carla.geometry import (
    LINE,
    ARC,
    SPIRAL,
    POLY3,
    PARAM_POLY3,
    NORMALIZED,
    ARC_LENGTH,
    DirectedPoint,
    RoadGeometry,
    RoadGeometryKind,
    with_arc,
    with_spiral,
    with_poly3,
    with_arc_si,
    with_spiral_si,
    with_poly3_si,
    with_param_poly3,
)
from extensions.carla.map import (
    Map,
    Waypoint,
    Signal,
    SignalSearchData,
    Landmark,
    RoadObject,
    EPSILON,
)
from extensions.carla.map_builder import MapBuilder
from extensions.carla.agents_misc import from_kmh, from_kmh_float32
from extensions.carla.opendrive import load_opendrive
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road, Lane, LaneSection
from extensions.carla.road_info import (
    RoadId,
    SectionId,
    LaneId,
    SignalId,
    NO_JUNCTION,
    LANE_DRIVING,
    MARK_CHANGE_BOTH,
    CHANGE_BOTH,
    SOLID,
    MARKING_WHITE,
    MarkLaneChange,
    CrosswalkPoint,
    LaneMarking,
    LaneValidity,
    RoadInfoGeometry,
    RoadInfoElevation,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    RoadInfoLaneBorder,
    RoadInfoLaneHeight,
    RoadInfoLaneMaterial,
    RoadInfoLaneVisibility,
    RoadInfoLaneAccess,
    RoadInfoLaneRule,
    RoadInfoSpeed,
    RoadInfoMarkTypeLine,
    RoadInfoMarkRecord,
    RoadInfoCrosswalk,
    RoadInfoSignal,
    info_at,
    info_index,
    infos_in_range,
    info_at_meters,
    info_index_meters,
    infos_in_range_meters,
)
from extensions.carla.render_actors import (
    body_style_of,
    body_style_of_si,
    body_geometry,
    body_geometry_si,
    cabin_geometry,
    cabin_geometry_si,
    wheel_inset,
    wheel_inset_si,
    stride,
    stride_si,
    SEDAN,
)
from extensions.carla.mesh_factory import MeshFactory
from extensions.carla.math import distance_squared_2d, distance_squared_2d_si
from extensions.carla.navigation_mesh import NavPolygon, AREA_SIDEWALK
from extensions.carla.town import roadside, roadside_si
from extensions.carla.physics.vehicle_control import PID
from extensions.carla.traffic_sign import TrafficSign, STOP_SIGN
from extensions.carla.transform import CarlaTransform, CarlaRotation
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from units.si import (
    Length,
    Length64,
    Angle64,
    InverseLength64,
    InverseArea64,
    Velocity64,
    METER,
    KILOMETER,
    DEGREE,
    Duration,
    Velocity,
    Area,
    Angle,
)


def _max_finite32() -> Float32:
    # Exact largest finite binary32, independent of SDK MAX semantics.
    return bitcast[DType.float32](UInt32(0x7F7FFFFF))


def _max_finite64() -> Float64:
    # Exact largest finite binary64, independent of SDK MAX semantics.
    return bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))


def _bad_values() -> List[Float64]:
    return [nan[DType.float64](), inf[DType.float64](), -inf[DType.float64]()]


def _word(value: Float64) -> UInt64:
    return bitcast[DType.uint64](value)


def _same_vector(one: Vector3, two: Vector3) raises:
    assert_equal(one.x, two.x)
    assert_equal(one.y, two.y)
    assert_equal(one.z, two.z)


def _precise() -> Float64:
    # The low binary64 bit is lost by any intermediate Float32 conversion.
    return bitcast[DType.float64](UInt64(0x3FF0000000000001))


def _reference() raises -> RoadInfoSignal:
    return RoadInfoSignal(
        SignalId("typed"),
        RoadId(1),
        Length64(0),
        Length64(0),
        "none",
        List[LaneValidity](),
    )


def _waypoint(s: Float64 = 0.0) raises -> Waypoint:
    return Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(s))


def test_directed_point_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = DirectedPoint(
        Length64(q), Length64(q), Length64(q), Angle64(q), 0.0
    )
    var raw = DirectedPoint.from_si(q, q, q, q, 0.0)
    assert_equal(_word(typed.x), _word(q))
    assert_equal(_word(raw.x), _word(q))
    assert_equal(_word(typed.x_quantity().value), _word(q))
    assert_equal(_word(typed.y), _word(q))
    assert_equal(_word(raw.y), _word(q))
    assert_equal(_word(typed.y_quantity().value), _word(q))
    assert_equal(_word(typed.z), _word(q))
    assert_equal(_word(raw.z), _word(q))
    assert_equal(_word(typed.z_quantity().value), _word(q))
    assert_equal(_word(typed.tangent), _word(q))
    assert_equal(_word(raw.tangent), _word(q))
    assert_equal(_word(typed.tangent_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.x = value
        assert_equal(_word(typed.x_quantity().value), word)
        typed.x = q
        typed.y = value
        assert_equal(_word(typed.y_quantity().value), word)
        typed.y = q
        typed.z = value
        assert_equal(_word(typed.z_quantity().value), word)
        typed.z = q
        typed.tangent = value
        assert_equal(_word(typed.tangent_quantity().value), word)
        typed.tangent = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = DirectedPoint(
                Length64(bad), Length64(q), Length64(q), Angle64(q), 0.0
            )
        with assert_raises(contains="finite"):
            _ = DirectedPoint.from_si(bad, q, q, q, 0.0)
        typed.x = bad
        with assert_raises(contains="finite"):
            _ = typed.x_quantity()
        typed.x = q
        with assert_raises(contains="finite"):
            _ = DirectedPoint(
                Length64(q), Length64(bad), Length64(q), Angle64(q), 0.0
            )
        with assert_raises(contains="finite"):
            _ = DirectedPoint.from_si(q, bad, q, q, 0.0)
        typed.y = bad
        with assert_raises(contains="finite"):
            _ = typed.y_quantity()
        typed.y = q
        with assert_raises(contains="finite"):
            _ = DirectedPoint(
                Length64(q), Length64(q), Length64(bad), Angle64(q), 0.0
            )
        with assert_raises(contains="finite"):
            _ = DirectedPoint.from_si(q, q, bad, q, 0.0)
        typed.z = bad
        with assert_raises(contains="finite"):
            _ = typed.z_quantity()
        typed.z = q
        with assert_raises(contains="finite"):
            _ = DirectedPoint(
                Length64(q), Length64(q), Length64(q), Angle64(bad), 0.0
            )
        with assert_raises(contains="finite"):
            _ = DirectedPoint.from_si(q, q, q, bad, 0.0)
        typed.tangent = bad
        with assert_raises(contains="finite"):
            _ = typed.tangent_quantity()
        typed.tangent = q


def test_lane_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = Lane(LaneId(-1), SectionId(0), Length64(q))
    var raw = Lane.from_si(LaneId(-1), SectionId(0), q)
    assert_equal(_word(typed.distance), _word(q))
    assert_equal(_word(raw.distance), _word(q))
    assert_equal(_word(typed.distance_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.distance = value
        assert_equal(_word(typed.distance_quantity().value), word)
        typed.distance = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = Lane(LaneId(-1), SectionId(0), Length64(bad))
        with assert_raises(contains="finite"):
            _ = Lane.from_si(LaneId(-1), SectionId(0), bad)
        typed.distance = bad
        with assert_raises(contains="finite"):
            _ = typed.distance_quantity()
        typed.distance = q


def test_lane_section_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = LaneSection(SectionId(0), Length64(q))
    var raw = LaneSection.from_si(SectionId(0), q)
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = LaneSection(SectionId(0), Length64(bad))
        with assert_raises(contains="finite"):
            _ = LaneSection.from_si(SectionId(0), bad)
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = Road(
        RoadId(1), "typed", Length64(q), NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    var raw = Road.from_si(
        RoadId(1), "typed", q, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    assert_equal(_word(typed.length), _word(q))
    assert_equal(_word(raw.length), _word(q))
    assert_equal(_word(typed.length_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.length = value
        assert_equal(_word(typed.length_quantity().value), word)
        typed.length = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = Road(
                RoadId(1),
                "typed",
                Length64(bad),
                NO_JUNCTION,
                RoadId(0),
                RoadId(0),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Road.from_si(
                RoadId(1), "typed", bad, NO_JUNCTION, RoadId(0), RoadId(0), True
            )
        typed.length = bad
        with assert_raises(contains="finite"):
            _ = typed.length_quantity()
        typed.length = q


def test_waypoint_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(q))
    var raw = Waypoint.from_si(RoadId(1), SectionId(0), LaneId(-1), q)
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(bad))
        with assert_raises(contains="finite"):
            _ = Waypoint.from_si(RoadId(1), SectionId(0), LaneId(-1), bad)
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_signal_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = Signal(
        RoadId(1),
        SignalId("typed"),
        Length64(q),
        Length64(q),
        "typed",
        "typed",
        "none",
        Length64(q),
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        Length64(q),
        Length64(q),
        "typed",
        Angle64(q),
        Angle64(q),
        Angle64(q),
        True,
    )
    var raw = Signal.from_si(
        RoadId(1),
        SignalId("typed"),
        q,
        q,
        "typed",
        "typed",
        "none",
        q,
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        q,
        q,
        "typed",
        q,
        q,
        q,
        True,
    )
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    assert_equal(_word(typed.t), _word(q))
    assert_equal(_word(raw.t), _word(q))
    assert_equal(_word(typed.t_quantity().value), _word(q))
    assert_equal(_word(typed.z_offset), _word(q))
    assert_equal(_word(raw.z_offset), _word(q))
    assert_equal(_word(typed.z_offset_quantity().value), _word(q))
    assert_equal(_word(typed.height), _word(q))
    assert_equal(_word(raw.height), _word(q))
    assert_equal(_word(typed.height_quantity().value), _word(q))
    assert_equal(_word(typed.width), _word(q))
    assert_equal(_word(raw.width), _word(q))
    assert_equal(_word(typed.width_quantity().value), _word(q))
    assert_equal(_word(typed.h_offset), _word(q))
    assert_equal(_word(raw.h_offset), _word(q))
    assert_equal(_word(typed.h_offset_quantity().value), _word(q))
    assert_equal(_word(typed.pitch), _word(q))
    assert_equal(_word(raw.pitch), _word(q))
    assert_equal(_word(typed.pitch_quantity().value), _word(q))
    assert_equal(_word(typed.roll), _word(q))
    assert_equal(_word(raw.roll), _word(q))
    assert_equal(_word(typed.roll_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
        typed.t = value
        assert_equal(_word(typed.t_quantity().value), word)
        typed.t = q
        typed.z_offset = value
        assert_equal(_word(typed.z_offset_quantity().value), word)
        typed.z_offset = q
        typed.height = value
        assert_equal(_word(typed.height_quantity().value), word)
        typed.height = q
        typed.width = value
        assert_equal(_word(typed.width_quantity().value), word)
        typed.width = q
        typed.h_offset = value
        assert_equal(_word(typed.h_offset_quantity().value), word)
        typed.h_offset = q
        typed.pitch = value
        assert_equal(_word(typed.pitch_quantity().value), word)
        typed.pitch = q
        typed.roll = value
        assert_equal(_word(typed.roll_quantity().value), word)
        typed.roll = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(bad),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                bad,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                q,
                "typed",
                q,
                q,
                q,
                True,
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(bad),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                bad,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                q,
                "typed",
                q,
                q,
                q,
                True,
            )
        typed.t = bad
        with assert_raises(contains="finite"):
            _ = typed.t_quantity()
        typed.t = q
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(bad),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                bad,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                q,
                "typed",
                q,
                q,
                q,
                True,
            )
        typed.z_offset = bad
        with assert_raises(contains="finite"):
            _ = typed.z_offset_quantity()
        typed.z_offset = q
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(bad),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                bad,
                q,
                "typed",
                q,
                q,
                q,
                True,
            )
        typed.height = bad
        with assert_raises(contains="finite"):
            _ = typed.height_quantity()
        typed.height = q
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(bad),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                bad,
                "typed",
                q,
                q,
                q,
                True,
            )
        typed.width = bad
        with assert_raises(contains="finite"):
            _ = typed.width_quantity()
        typed.width = q
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(q),
                "typed",
                Angle64(bad),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                q,
                "typed",
                bad,
                q,
                q,
                True,
            )
        typed.h_offset = bad
        with assert_raises(contains="finite"):
            _ = typed.h_offset_quantity()
        typed.h_offset = q
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(bad),
                Angle64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                q,
                "typed",
                q,
                bad,
                q,
                True,
            )
        typed.pitch = bad
        with assert_raises(contains="finite"):
            _ = typed.pitch_quantity()
        typed.pitch = q
        with assert_raises(contains="finite"):
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(bad),
                True,
            )
        with assert_raises(contains="finite"):
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                q,
                "typed",
                q,
                q,
                bad,
                True,
            )
        typed.roll = bad
        with assert_raises(contains="finite"):
            _ = typed.roll_quantity()
        typed.roll = q


def test_signal_search_data_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = SignalSearchData(_reference(), _waypoint(), Length64(q))
    var raw = SignalSearchData.from_si(_reference(), _waypoint(), q)
    assert_equal(_word(typed.accumulated_s), _word(q))
    assert_equal(_word(raw.accumulated_s), _word(q))
    assert_equal(_word(typed.accumulated_s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.accumulated_s = value
        assert_equal(_word(typed.accumulated_s_quantity().value), word)
        typed.accumulated_s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = SignalSearchData(_reference(), _waypoint(), Length64(bad))
        with assert_raises(contains="finite"):
            _ = SignalSearchData.from_si(_reference(), _waypoint(), bad)
        typed.accumulated_s = bad
        with assert_raises(contains="finite"):
            _ = typed.accumulated_s_quantity()
        typed.accumulated_s = q


def test_landmark_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = Landmark(_waypoint(), _reference(), Length64(q))
    var raw = Landmark.from_si(_waypoint(), _reference(), q)
    assert_equal(_word(typed.distance), _word(q))
    assert_equal(_word(raw.distance), _word(q))
    assert_equal(_word(typed.distance_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.distance = value
        assert_equal(_word(typed.distance_quantity().value), word)
        typed.distance = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = Landmark(_waypoint(), _reference(), Length64(bad))
        with assert_raises(contains="finite"):
            _ = Landmark.from_si(_waypoint(), _reference(), bad)
        typed.distance = bad
        with assert_raises(contains="finite"):
            _ = typed.distance_quantity()
        typed.distance = q


def test_road_info_geometry_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoGeometry(
        Length64(q),
        RoadGeometry(
            LINE,
            Length64(0),
            Length64(0),
            Length64(0),
            Angle64(0),
            Length64(10),
        ),
    )
    var raw = RoadInfoGeometry.from_si(
        q,
        RoadGeometry(
            LINE,
            Length64(0),
            Length64(0),
            Length64(0),
            Angle64(0),
            Length64(10),
        ),
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoGeometry(
                Length64(bad),
                RoadGeometry(
                    LINE,
                    Length64(0),
                    Length64(0),
                    Length64(0),
                    Angle64(0),
                    Length64(10),
                ),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoGeometry.from_si(
                bad,
                RoadGeometry(
                    LINE,
                    Length64(0),
                    Length64(0),
                    Length64(0),
                    Angle64(0),
                    Length64(10),
                ),
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_elevation_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoElevation(
        Length64(q), CubicPolynomial.constant(Length64(3.5))
    )
    var raw = RoadInfoElevation.from_si(
        q, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoElevation(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoElevation.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_lane_offset_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneOffset(
        Length64(q), CubicPolynomial.constant(Length64(3.5))
    )
    var raw = RoadInfoLaneOffset.from_si(
        q, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneOffset(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneOffset.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_lane_width_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneWidth(
        Length64(q), CubicPolynomial.constant(Length64(3.5))
    )
    var raw = RoadInfoLaneWidth.from_si(
        q, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneWidth(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneWidth.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_lane_border_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneBorder(
        Length64(q), CubicPolynomial.constant(Length64(3.5))
    )
    var raw = RoadInfoLaneBorder.from_si(
        q, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneBorder(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneBorder.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_lane_height_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneHeight(Length64(q), Length64(q), Length64(q))
    var raw = RoadInfoLaneHeight.from_si(q, q, q)
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    assert_equal(_word(typed.inner), _word(q))
    assert_equal(_word(raw.inner), _word(q))
    assert_equal(_word(typed.inner_quantity().value), _word(q))
    assert_equal(_word(typed.outer), _word(q))
    assert_equal(_word(raw.outer), _word(q))
    assert_equal(_word(typed.outer_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
        typed.inner = value
        assert_equal(_word(typed.inner_quantity().value), word)
        typed.inner = q
        typed.outer = value
        assert_equal(_word(typed.outer_quantity().value), word)
        typed.outer = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneHeight(Length64(bad), Length64(q), Length64(q))
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneHeight.from_si(bad, q, q)
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneHeight(Length64(q), Length64(bad), Length64(q))
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneHeight.from_si(q, bad, q)
        typed.inner = bad
        with assert_raises(contains="finite"):
            _ = typed.inner_quantity()
        typed.inner = q
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneHeight(Length64(q), Length64(q), Length64(bad))
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneHeight.from_si(q, q, bad)
        typed.outer = bad
        with assert_raises(contains="finite"):
            _ = typed.outer_quantity()
        typed.outer = q


def test_road_info_lane_material_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneMaterial(Length64(q), "typed", 0.0, 0.0)
    var raw = RoadInfoLaneMaterial.from_si(q, "typed", 0.0, 0.0)
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneMaterial(Length64(bad), "typed", 0.0, 0.0)
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneMaterial.from_si(bad, "typed", 0.0, 0.0)
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_lane_visibility_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneVisibility(
        Length64(q), Length64(q), Length64(q), Length64(q), Length64(q)
    )
    var raw = RoadInfoLaneVisibility.from_si(q, q, q, q, q)
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    assert_equal(_word(typed.forward), _word(q))
    assert_equal(_word(raw.forward), _word(q))
    assert_equal(_word(typed.forward_quantity().value), _word(q))
    assert_equal(_word(typed.back), _word(q))
    assert_equal(_word(raw.back), _word(q))
    assert_equal(_word(typed.back_quantity().value), _word(q))
    assert_equal(_word(typed.left), _word(q))
    assert_equal(_word(raw.left), _word(q))
    assert_equal(_word(typed.left_quantity().value), _word(q))
    assert_equal(_word(typed.right), _word(q))
    assert_equal(_word(raw.right), _word(q))
    assert_equal(_word(typed.right_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
        typed.forward = value
        assert_equal(_word(typed.forward_quantity().value), word)
        typed.forward = q
        typed.back = value
        assert_equal(_word(typed.back_quantity().value), word)
        typed.back = q
        typed.left = value
        assert_equal(_word(typed.left_quantity().value), word)
        typed.left = q
        typed.right = value
        assert_equal(_word(typed.right_quantity().value), word)
        typed.right = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility(
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility.from_si(bad, q, q, q, q)
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility.from_si(q, bad, q, q, q)
        typed.forward = bad
        with assert_raises(contains="finite"):
            _ = typed.forward_quantity()
        typed.forward = q
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(q),
                Length64(bad),
                Length64(q),
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility.from_si(q, q, bad, q, q)
        typed.back = bad
        with assert_raises(contains="finite"):
            _ = typed.back_quantity()
        typed.back = q
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility.from_si(q, q, q, bad, q)
        typed.left = bad
        with assert_raises(contains="finite"):
            _ = typed.left_quantity()
        typed.left = q
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneVisibility.from_si(q, q, q, q, bad)
        typed.right = bad
        with assert_raises(contains="finite"):
            _ = typed.right_quantity()
        typed.right = q


def test_road_info_lane_access_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneAccess(Length64(q), "typed")
    var raw = RoadInfoLaneAccess.from_si(q, "typed")
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneAccess(Length64(bad), "typed")
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneAccess.from_si(bad, "typed")
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_lane_rule_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoLaneRule(Length64(q), "typed")
    var raw = RoadInfoLaneRule.from_si(q, "typed")
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneRule(Length64(bad), "typed")
        with assert_raises(contains="finite"):
            _ = RoadInfoLaneRule.from_si(bad, "typed")
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_speed_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoSpeed(Length64(q), Velocity64(5.0), "solid")
    var raw = RoadInfoSpeed.from_si(q, 5.0, "solid", "m/s")
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoSpeed(Length64(bad), Velocity64(5.0), "solid")
        with assert_raises(contains="finite"):
            _ = RoadInfoSpeed.from_si(bad, 5.0, "solid", "m/s")
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_mark_type_line_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoMarkTypeLine(
        Length64(q),
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        "typed",
        Length64(q),
    )
    var raw = RoadInfoMarkTypeLine.from_si(q, 0, q, q, q, "typed", q)
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    assert_equal(_word(typed.length), _word(q))
    assert_equal(_word(raw.length), _word(q))
    assert_equal(_word(typed.length_quantity().value), _word(q))
    assert_equal(_word(typed.space), _word(q))
    assert_equal(_word(raw.space), _word(q))
    assert_equal(_word(typed.space_quantity().value), _word(q))
    assert_equal(_word(typed.t_offset), _word(q))
    assert_equal(_word(raw.t_offset), _word(q))
    assert_equal(_word(typed.t_offset_quantity().value), _word(q))
    assert_equal(_word(typed.width), _word(q))
    assert_equal(_word(raw.width), _word(q))
    assert_equal(_word(typed.width_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
        typed.length = value
        assert_equal(_word(typed.length_quantity().value), word)
        typed.length = q
        typed.space = value
        assert_equal(_word(typed.space_quantity().value), word)
        typed.space = q
        typed.t_offset = value
        assert_equal(_word(typed.t_offset_quantity().value), word)
        typed.t_offset = q
        typed.width = value
        assert_equal(_word(typed.width_quantity().value), word)
        typed.width = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine(
                Length64(bad),
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                "typed",
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine.from_si(bad, 0, q, q, q, "typed", q)
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine(
                Length64(q),
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                "typed",
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine.from_si(q, 0, bad, q, q, "typed", q)
        typed.length = bad
        with assert_raises(contains="finite"):
            _ = typed.length_quantity()
        typed.length = q
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine(
                Length64(q),
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                "typed",
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine.from_si(q, 0, q, bad, q, "typed", q)
        typed.space = bad
        with assert_raises(contains="finite"):
            _ = typed.space_quantity()
        typed.space = q
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine(
                Length64(q),
                0,
                Length64(q),
                Length64(q),
                Length64(bad),
                "typed",
                Length64(q),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine.from_si(q, 0, q, q, bad, "typed", q)
        typed.t_offset = bad
        with assert_raises(contains="finite"):
            _ = typed.t_offset_quantity()
        typed.t_offset = q
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine(
                Length64(q),
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                "typed",
                Length64(bad),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkTypeLine.from_si(q, 0, q, q, q, "typed", bad)
        typed.width = bad
        with assert_raises(contains="finite"):
            _ = typed.width_quantity()
        typed.width = q


def test_road_info_mark_record_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoMarkRecord(Length64(q), 0)
    var raw = RoadInfoMarkRecord.from_si(q, 0)
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord(Length64(bad), 0)
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord.from_si(bad, 0)
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q


def test_road_info_mark_record_full_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoMarkRecord(
        Length64(q),
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        Length64(q),
        MARK_CHANGE_BOTH,
        Length64(q),
        "typed",
        Length64(q),
        True,
    )
    var raw = RoadInfoMarkRecord.from_si(
        q,
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        q,
        MARK_CHANGE_BOTH,
        q,
        "typed",
        q,
        True,
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    assert_equal(_word(typed.width), _word(q))
    assert_equal(_word(raw.width), _word(q))
    assert_equal(_word(typed.width_quantity().value), _word(q))
    assert_equal(_word(typed.height), _word(q))
    assert_equal(_word(raw.height), _word(q))
    assert_equal(_word(typed.height_quantity().value), _word(q))
    assert_equal(_word(typed.type_width), _word(q))
    assert_equal(_word(raw.type_width), _word(q))
    assert_equal(_word(typed.type_width_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
        typed.width = value
        assert_equal(_word(typed.width_quantity().value), word)
        typed.width = q
        typed.height = value
        assert_equal(_word(typed.height_quantity().value), word)
        typed.height = q
        typed.type_width = value
        assert_equal(_word(typed.type_width_quantity().value), word)
        typed.type_width = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord(
                Length64(bad),
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                Length64(q),
                MARK_CHANGE_BOTH,
                Length64(q),
                "typed",
                Length64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord.from_si(
                bad,
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                q,
                MARK_CHANGE_BOTH,
                q,
                "typed",
                q,
                True,
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord(
                Length64(q),
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                Length64(bad),
                MARK_CHANGE_BOTH,
                Length64(q),
                "typed",
                Length64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord.from_si(
                q,
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                bad,
                MARK_CHANGE_BOTH,
                q,
                "typed",
                q,
                True,
            )
        typed.width = bad
        with assert_raises(contains="finite"):
            _ = typed.width_quantity()
        typed.width = q
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord(
                Length64(q),
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                Length64(q),
                MARK_CHANGE_BOTH,
                Length64(bad),
                "typed",
                Length64(q),
                True,
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord.from_si(
                q,
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                q,
                MARK_CHANGE_BOTH,
                bad,
                "typed",
                q,
                True,
            )
        typed.height = bad
        with assert_raises(contains="finite"):
            _ = typed.height_quantity()
        typed.height = q
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord(
                Length64(q),
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                Length64(q),
                MARK_CHANGE_BOTH,
                Length64(q),
                "typed",
                Length64(bad),
                True,
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoMarkRecord.from_si(
                q,
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                q,
                MARK_CHANGE_BOTH,
                q,
                "typed",
                bad,
                True,
            )
        typed.type_width = bad
        with assert_raises(contains="finite"):
            _ = typed.type_width_quantity()
        typed.type_width = q


def test_crosswalk_point_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = CrosswalkPoint(Length64(q), Length64(q), Length64(q))
    var raw = CrosswalkPoint.from_si(q, q, q)
    assert_equal(_word(typed.u), _word(q))
    assert_equal(_word(raw.u), _word(q))
    assert_equal(_word(typed.u_quantity().value), _word(q))
    assert_equal(_word(typed.v), _word(q))
    assert_equal(_word(raw.v), _word(q))
    assert_equal(_word(typed.v_quantity().value), _word(q))
    assert_equal(_word(typed.z), _word(q))
    assert_equal(_word(raw.z), _word(q))
    assert_equal(_word(typed.z_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.u = value
        assert_equal(_word(typed.u_quantity().value), word)
        typed.u = q
        typed.v = value
        assert_equal(_word(typed.v_quantity().value), word)
        typed.v = q
        typed.z = value
        assert_equal(_word(typed.z_quantity().value), word)
        typed.z = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = CrosswalkPoint(Length64(bad), Length64(q), Length64(q))
        with assert_raises(contains="finite"):
            _ = CrosswalkPoint.from_si(bad, q, q)
        typed.u = bad
        with assert_raises(contains="finite"):
            _ = typed.u_quantity()
        typed.u = q
        with assert_raises(contains="finite"):
            _ = CrosswalkPoint(Length64(q), Length64(bad), Length64(q))
        with assert_raises(contains="finite"):
            _ = CrosswalkPoint.from_si(q, bad, q)
        typed.v = bad
        with assert_raises(contains="finite"):
            _ = typed.v_quantity()
        typed.v = q
        with assert_raises(contains="finite"):
            _ = CrosswalkPoint(Length64(q), Length64(q), Length64(bad))
        with assert_raises(contains="finite"):
            _ = CrosswalkPoint.from_si(q, q, bad)
        typed.z = bad
        with assert_raises(contains="finite"):
            _ = typed.z_quantity()
        typed.z = q


def test_road_info_crosswalk_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoCrosswalk(
        Length64(q),
        "typed",
        Length64(q),
        Length64(q),
        Angle64(q),
        Angle64(q),
        Angle64(q),
        "none",
        Length64(q),
        Length64(q),
        List[CrosswalkPoint](),
    )
    var raw = RoadInfoCrosswalk.from_si(
        q, "typed", q, q, q, q, q, "none", q, q, List[CrosswalkPoint]()
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    assert_equal(_word(typed.t), _word(q))
    assert_equal(_word(raw.t), _word(q))
    assert_equal(_word(typed.t_quantity().value), _word(q))
    assert_equal(_word(typed.z_offset), _word(q))
    assert_equal(_word(raw.z_offset), _word(q))
    assert_equal(_word(typed.z_offset_quantity().value), _word(q))
    assert_equal(_word(typed.heading), _word(q))
    assert_equal(_word(raw.heading), _word(q))
    assert_equal(_word(typed.heading_quantity().value), _word(q))
    assert_equal(_word(typed.pitch), _word(q))
    assert_equal(_word(raw.pitch), _word(q))
    assert_equal(_word(typed.pitch_quantity().value), _word(q))
    assert_equal(_word(typed.roll), _word(q))
    assert_equal(_word(raw.roll), _word(q))
    assert_equal(_word(typed.roll_quantity().value), _word(q))
    assert_equal(_word(typed.width), _word(q))
    assert_equal(_word(raw.width), _word(q))
    assert_equal(_word(typed.width_quantity().value), _word(q))
    assert_equal(_word(typed.length), _word(q))
    assert_equal(_word(raw.length), _word(q))
    assert_equal(_word(typed.length_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
        typed.t = value
        assert_equal(_word(typed.t_quantity().value), word)
        typed.t = q
        typed.z_offset = value
        assert_equal(_word(typed.z_offset_quantity().value), word)
        typed.z_offset = q
        typed.heading = value
        assert_equal(_word(typed.heading_quantity().value), word)
        typed.heading = q
        typed.pitch = value
        assert_equal(_word(typed.pitch_quantity().value), word)
        typed.pitch = q
        typed.roll = value
        assert_equal(_word(typed.roll_quantity().value), word)
        typed.roll = q
        typed.width = value
        assert_equal(_word(typed.width_quantity().value), word)
        typed.width = q
        typed.length = value
        assert_equal(_word(typed.length_quantity().value), word)
        typed.length = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(bad),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                bad,
                "typed",
                q,
                q,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(bad),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                bad,
                q,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        typed.t = bad
        with assert_raises(contains="finite"):
            _ = typed.t_quantity()
        typed.t = q
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(bad),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                bad,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        typed.z_offset = bad
        with assert_raises(contains="finite"):
            _ = typed.z_offset_quantity()
        typed.z_offset = q
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(bad),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                q,
                bad,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        typed.heading = bad
        with assert_raises(contains="finite"):
            _ = typed.heading_quantity()
        typed.heading = q
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(bad),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                q,
                q,
                bad,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        typed.pitch = bad
        with assert_raises(contains="finite"):
            _ = typed.pitch_quantity()
        typed.pitch = q
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(bad),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                q,
                q,
                q,
                bad,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        typed.roll = bad
        with assert_raises(contains="finite"):
            _ = typed.roll_quantity()
        typed.roll = q
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(bad),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                q,
                q,
                q,
                q,
                "none",
                bad,
                q,
                List[CrosswalkPoint](),
            )
        typed.width = bad
        with assert_raises(contains="finite"):
            _ = typed.width_quantity()
        typed.width = q
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(bad),
                List[CrosswalkPoint](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                q,
                q,
                q,
                q,
                "none",
                q,
                bad,
                List[CrosswalkPoint](),
            )
        typed.length = bad
        with assert_raises(contains="finite"):
            _ = typed.length_quantity()
        typed.length = q


def test_road_info_signal_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = RoadInfoSignal(
        SignalId("typed"),
        RoadId(1),
        Length64(q),
        Length64(q),
        "none",
        List[LaneValidity](),
    )
    var raw = RoadInfoSignal.from_si(
        SignalId("typed"), RoadId(1), q, q, "none", List[LaneValidity]()
    )
    assert_equal(_word(typed.distance().value), _word(q))
    assert_equal(_word(typed.distance_meters()), _word(q))
    assert_equal(_word(typed.s), _word(q))
    assert_equal(_word(raw.s), _word(q))
    assert_equal(_word(typed.s_quantity().value), _word(q))
    assert_equal(_word(typed.t), _word(q))
    assert_equal(_word(raw.t), _word(q))
    assert_equal(_word(typed.t_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.s = value
        assert_equal(_word(typed.s_quantity().value), word)
        typed.s = q
        typed.t = value
        assert_equal(_word(typed.t_quantity().value), word)
        typed.t = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = RoadInfoSignal(
                SignalId("typed"),
                RoadId(1),
                Length64(bad),
                Length64(q),
                "none",
                List[LaneValidity](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoSignal.from_si(
                SignalId("typed"),
                RoadId(1),
                bad,
                q,
                "none",
                List[LaneValidity](),
            )
        typed.s = bad
        with assert_raises(contains="finite"):
            _ = typed.distance()
        with assert_raises(contains="finite"):
            _ = typed.s_quantity()
        typed.s = q
        with assert_raises(contains="finite"):
            _ = RoadInfoSignal(
                SignalId("typed"),
                RoadId(1),
                Length64(q),
                Length64(bad),
                "none",
                List[LaneValidity](),
            )
        with assert_raises(contains="finite"):
            _ = RoadInfoSignal.from_si(
                SignalId("typed"),
                RoadId(1),
                q,
                bad,
                "none",
                List[LaneValidity](),
            )
        typed.t = bad
        with assert_raises(contains="finite"):
            _ = typed.t_quantity()
        typed.t = q


def test_lane_marking_typed_raw_and_checked_views() raises:
    var q = _precise()
    var typed = LaneMarking(SOLID, MARKING_WHITE, CHANGE_BOTH, Length64(q))
    var raw = LaneMarking.from_si(SOLID, MARKING_WHITE, CHANGE_BOTH, q)
    assert_equal(_word(typed.width), _word(q))
    assert_equal(_word(raw.width), _word(q))
    assert_equal(_word(typed.width_quantity().value), _word(q))
    # Raw compatibility views retain finite values without evaluating them.
    for word in [
        UInt64(0x8000000000000000),
        UInt64(1),
        UInt64(0x7FEFFFFFFFFFFFFF),
    ]:
        var value = bitcast[DType.float64](word)
        typed.width = value
        assert_equal(_word(typed.width_quantity().value), word)
        typed.width = q
    for bad in _bad_values():
        with assert_raises(contains="finite"):
            _ = LaneMarking(SOLID, MARKING_WHITE, CHANGE_BOTH, Length64(bad))
        with assert_raises(contains="finite"):
            _ = LaneMarking.from_si(SOLID, MARKING_WHITE, CHANGE_BOTH, bad)
        typed.width = bad
        with assert_raises(contains="finite"):
            _ = typed.width_quantity()
        typed.width = q


def test_road_object_raw_fields_have_checked_typed_views() raises:
    var raw = RoadObject()
    var q = _precise()
    assert_equal(raw.s_quantity().value, 0.0)
    raw.s = q
    assert_equal(_word(raw.s_quantity().value), _word(q))
    assert_equal(raw.t_quantity().value, 0.0)
    raw.t = q
    assert_equal(_word(raw.t_quantity().value), _word(q))
    assert_equal(raw.z_offset_quantity().value, 0.0)
    raw.z_offset = q
    assert_equal(_word(raw.z_offset_quantity().value), _word(q))
    assert_equal(raw.valid_length_quantity().value, 0.0)
    raw.valid_length = q
    assert_equal(_word(raw.valid_length_quantity().value), _word(q))
    assert_equal(raw.length_quantity().value, 0.0)
    raw.length = q
    assert_equal(_word(raw.length_quantity().value), _word(q))
    assert_equal(raw.width_quantity().value, 0.0)
    raw.width = q
    assert_equal(_word(raw.width_quantity().value), _word(q))
    assert_equal(raw.heading_quantity().value, 0.0)
    raw.heading = q
    assert_equal(_word(raw.heading_quantity().value), _word(q))
    assert_equal(raw.pitch_quantity().value, 0.0)
    raw.pitch = q
    assert_equal(_word(raw.pitch_quantity().value), _word(q))
    assert_equal(raw.roll_quantity().value, 0.0)
    raw.roll = q
    assert_equal(_word(raw.roll_quantity().value), _word(q))
    for bad in _bad_values():
        raw.s = bad
        with assert_raises(contains="finite"):
            _ = raw.s_quantity()
        raw.s = q
        raw.t = bad
        with assert_raises(contains="finite"):
            _ = raw.t_quantity()
        raw.t = q
        raw.z_offset = bad
        with assert_raises(contains="finite"):
            _ = raw.z_offset_quantity()
        raw.z_offset = q
        raw.valid_length = bad
        with assert_raises(contains="finite"):
            _ = raw.valid_length_quantity()
        raw.valid_length = q
        raw.length = bad
        with assert_raises(contains="finite"):
            _ = raw.length_quantity()
        raw.length = q
        raw.width = bad
        with assert_raises(contains="finite"):
            _ = raw.width_quantity()
        raw.width = q
        raw.heading = bad
        with assert_raises(contains="finite"):
            _ = raw.heading_quantity()
        raw.heading = q
        raw.pitch = bad
        with assert_raises(contains="finite"):
            _ = raw.pitch_quantity()
        raw.pitch = q
        raw.roll = bad
        with assert_raises(contains="finite"):
            _ = raw.roll_quantity()
        raw.roll = q


def _builder() raises -> MapBuilder:
    var b = MapBuilder()
    var road = b.add_road(
        RoadId(1),
        "typed",
        Length64(10),
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    var section = b.add_road_section(road, SectionId(0), Length64(0))
    _ = b.add_road_section_lane(
        road,
        section,
        LaneId(-1),
        LANE_DRIVING,
        False,
        LaneId(0),
        LaneId(0),
    )
    var lane = b.lane(RoadId(1), LaneId(-1), Length64(0))
    b.create_lane_width(
        lane,
        Length64(0),
        Length64(3.5),
        0,
        InverseLength64(0),
        InverseArea64(0),
    )
    b.create_section_offset(
        road, Length64(0), Length64(0), 0, InverseLength64(0), InverseArea64(0)
    )
    b.add_road_elevation_profile(
        road, Length64(0), Length64(0), 0, InverseLength64(0), InverseArea64(0)
    )
    b.add_road_geometry_line(
        road, Length64(0), Length64(0), Length64(0), Angle64(0), Length64(10)
    )
    b.create_road_mark(
        lane,
        0,
        Length64(0),
        "solid",
        "standard",
        "white",
        "paint",
        Length64(0.15),
        "both",
        Length64(0),
        "",
        Length64(0.15),
        True,
    )
    _ = b.add_signal(
        road,
        SignalId("typed"),
        Length64(2),
        Length64(3),
        "typed",
        "no",
        "none",
        Length64(0),
        "",
        "stop",
        "",
        0,
        "",
        Length64(1),
        Length64(1),
        "",
        Angle64(0),
        Angle64(0),
        Angle64(0),
    )
    return b^


def _builder_state(b: MapBuilder) -> String:
    # Capture counts plus overwrite targets, so a rejected replacement,
    # appended record, or partial signal-position update is observable.
    var result = String(len(b.roads)) + ":" + String(len(b.signals))
    for road in b.roads:
        result += ":" + road.name + ":" + String(_word(road.length))
        result += ":" + String(len(road.sections))
        result += ":" + String(len(road.info.geometries))
        result += ":" + String(len(road.info.elevations))
        result += ":" + String(len(road.info.lane_offsets))
        result += ":" + String(len(road.info.speeds))
        result += ":" + String(len(road.info.crosswalks))
        result += ":" + String(len(road.info.signals))
        for section in road.sections:
            result += ":" + String(_word(section.s))
            for lane in section.lanes:
                result += ":" + String(len(lane.info.widths))
                result += ":" + String(len(lane.info.borders))
                result += ":" + String(len(lane.info.heights))
                result += ":" + String(len(lane.info.materials))
                result += ":" + String(len(lane.info.rules))
                result += ":" + String(len(lane.info.visibilities))
                result += ":" + String(len(lane.info.accesses))
                result += ":" + String(len(lane.info.speeds))
                result += ":" + String(len(lane.info.marks))
                for mark in lane.info.marks:
                    result += ":" + String(len(mark.lines))
    for signal in b.signals:
        result += (
            ":" + signal.name + ":" + String(signal.using_inertial_position)
        )
        result += ":" + String(_word(signal.s)) + ":" + String(_word(signal.t))
        result += ":" + String(_word(signal.z_offset))
        result += ":" + String(_word(signal.h_offset))
        result += ":" + String(_word(signal.pitch))
        result += ":" + String(_word(signal.roll))
        result += ":" + String(signal.transform.location.x)
        result += ":" + String(signal.transform.location.y)
        result += ":" + String(signal.transform.location.z)
        result += ":" + String(signal.transform.rotation.yaw)
        result += ":" + String(signal.transform.rotation.pitch)
        result += ":" + String(signal.transform.rotation.roll)
    return result


def test_builder_add_road_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    _ = b.add_road(
        RoadId(1), "new", Length64(q), NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = raw.add_road_si(
        RoadId(1), "new", q, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_rejects_before_mutation() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            _ = b.add_road(
                RoadId(1),
                "new",
                Length64(bad),
                NO_JUNCTION,
                RoadId(0),
                RoadId(0),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_road_si(
                RoadId(1), "new", bad, NO_JUNCTION, RoadId(0), RoadId(0), True
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_road_section_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    _ = b.add_road_section(0, SectionId(1), Length64(q))
    _ = raw.add_road_section_si(0, SectionId(1), q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_section_rejects_before_mutation() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            _ = b.add_road_section(0, SectionId(1), Length64(bad))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_road_section_si(0, SectionId(1), bad)
        assert_equal(_builder_state(b), before)


def test_builder_lane_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    _ = b.lane(RoadId(1), LaneId(-1), Length64(q))
    _ = raw.lane_si(RoadId(1), LaneId(-1), q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_lane_rejects_before_mutation() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            _ = b.lane(RoadId(1), LaneId(-1), Length64(bad))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.lane_si(RoadId(1), LaneId(-1), bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_width_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_width(
        (0, 0, 0),
        Length64(q),
        Length64(q),
        0.0,
        InverseLength64(q),
        InverseArea64(q),
    )
    raw.create_lane_width_si((0, 0, 0), q, q, 0.0, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_width_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_width(
                (0, 0, 0),
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width_si((0, 0, 0), bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width(
                (0, 0, 0),
                Length64(q),
                Length64(bad),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width_si((0, 0, 0), q, bad, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width(
                (0, 0, 0),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(bad),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width_si((0, 0, 0), q, q, 0.0, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width(
                (0, 0, 0),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width_si((0, 0, 0), q, q, 0.0, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_border_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_border(
        (0, 0, 0),
        Length64(q),
        Length64(q),
        0.0,
        InverseLength64(q),
        InverseArea64(q),
    )
    raw.create_lane_border_si((0, 0, 0), q, q, 0.0, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_border_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_border(
                (0, 0, 0),
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border_si((0, 0, 0), bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border(
                (0, 0, 0),
                Length64(q),
                Length64(bad),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border_si((0, 0, 0), q, bad, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border(
                (0, 0, 0),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(bad),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border_si((0, 0, 0), q, q, 0.0, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border(
                (0, 0, 0),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border_si((0, 0, 0), q, q, 0.0, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_height_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_height((0, 0, 0), Length64(q), Length64(q), Length64(q))
    raw.create_lane_height_si((0, 0, 0), q, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_height_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_height(
                (0, 0, 0), Length64(bad), Length64(q), Length64(q)
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_height_si((0, 0, 0), bad, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_height(
                (0, 0, 0), Length64(q), Length64(bad), Length64(q)
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_height_si((0, 0, 0), q, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_height(
                (0, 0, 0), Length64(q), Length64(q), Length64(bad)
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_height_si((0, 0, 0), q, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_material_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_material((0, 0, 0), Length64(q), "", 0.0, 0.0)
    raw.create_lane_material_si((0, 0, 0), q, "", 0.0, 0.0)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_material_rejects_before_mutation() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_material((0, 0, 0), Length64(bad), "", 0.0, 0.0)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_material_si((0, 0, 0), bad, "", 0.0, 0.0)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_rule_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_rule((0, 0, 0), Length64(q), "")
    raw.create_lane_rule_si((0, 0, 0), q, "")
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_rule_rejects_before_mutation() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_rule((0, 0, 0), Length64(bad), "")
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_rule_si((0, 0, 0), bad, "")
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_visibility_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_visibility(
        (0, 0, 0),
        Length64(q),
        Length64(q),
        Length64(q),
        Length64(q),
        Length64(q),
    )
    raw.create_lane_visibility_si((0, 0, 0), q, q, q, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_visibility_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_visibility(
                (0, 0, 0),
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility_si((0, 0, 0), bad, q, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility(
                (0, 0, 0),
                Length64(q),
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility_si((0, 0, 0), q, bad, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility(
                (0, 0, 0),
                Length64(q),
                Length64(q),
                Length64(bad),
                Length64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility_si((0, 0, 0), q, q, bad, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility(
                (0, 0, 0),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility_si((0, 0, 0), q, q, q, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility(
                (0, 0, 0),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility_si((0, 0, 0), q, q, q, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_access_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_access((0, 0, 0), Length64(q), "")
    raw.create_lane_access_si((0, 0, 0), q, "")
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_access_rejects_before_mutation() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_access((0, 0, 0), Length64(bad), "")
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_access_si((0, 0, 0), bad, "")
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_speed_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_lane_speed((0, 0, 0), Length64(q), Velocity64(q))
    raw.create_lane_speed_opendrive((0, 0, 0), q, q, "m/s")
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_lane_speed_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_lane_speed((0, 0, 0), Length64(bad), Velocity64(q))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_speed_opendrive((0, 0, 0), bad, q, "m/s")
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_speed((0, 0, 0), Length64(q), Velocity64(bad))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_speed_opendrive((0, 0, 0), q, bad, "m/s")
        assert_equal(_builder_state(b), before)


def test_builder_create_road_mark_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_road_mark(
        (0, 0, 0),
        0,
        Length64(q),
        "solid",
        "",
        "white",
        "",
        Length64(q),
        "both",
        Length64(q),
        "",
        Length64(q),
        True,
    )
    raw.create_road_mark_si(
        (0, 0, 0), 0, q, "solid", "", "white", "", q, "both", q, "", q, True
    )
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_road_mark_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_road_mark(
                (0, 0, 0),
                0,
                Length64(bad),
                "solid",
                "",
                "white",
                "",
                Length64(q),
                "both",
                Length64(q),
                "",
                Length64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_si(
                (0, 0, 0),
                0,
                bad,
                "solid",
                "",
                "white",
                "",
                q,
                "both",
                q,
                "",
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark(
                (0, 0, 0),
                0,
                Length64(q),
                "solid",
                "",
                "white",
                "",
                Length64(bad),
                "both",
                Length64(q),
                "",
                Length64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_si(
                (0, 0, 0),
                0,
                q,
                "solid",
                "",
                "white",
                "",
                bad,
                "both",
                q,
                "",
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark(
                (0, 0, 0),
                0,
                Length64(q),
                "solid",
                "",
                "white",
                "",
                Length64(q),
                "both",
                Length64(bad),
                "",
                Length64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_si(
                (0, 0, 0),
                0,
                q,
                "solid",
                "",
                "white",
                "",
                q,
                "both",
                bad,
                "",
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark(
                (0, 0, 0),
                0,
                Length64(q),
                "solid",
                "",
                "white",
                "",
                Length64(q),
                "both",
                Length64(q),
                "",
                Length64(bad),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_si(
                (0, 0, 0),
                0,
                q,
                "solid",
                "",
                "white",
                "",
                q,
                "both",
                q,
                "",
                bad,
                True,
            )
        assert_equal(_builder_state(b), before)


def test_builder_create_road_mark_type_line_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_road_mark_type_line(
        (0, 0, 0),
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        Length64(q),
        "",
        Length64(q),
    )
    raw.create_road_mark_type_line_si((0, 0, 0), 0, q, q, q, q, "", q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_road_mark_type_line_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_road_mark_type_line(
                (0, 0, 0),
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
                "",
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line_si((0, 0, 0), 0, bad, q, q, q, "", q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line(
                (0, 0, 0),
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                Length64(q),
                "",
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line_si((0, 0, 0), 0, q, bad, q, q, "", q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line(
                (0, 0, 0),
                0,
                Length64(q),
                Length64(q),
                Length64(bad),
                Length64(q),
                "",
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line_si((0, 0, 0), 0, q, q, bad, q, "", q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line(
                (0, 0, 0),
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
                "",
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line_si((0, 0, 0), 0, q, q, q, bad, "", q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line(
                (0, 0, 0),
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
                "",
                Length64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line_si((0, 0, 0), 0, q, q, q, q, "", bad)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_elevation_profile_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_road_elevation_profile(
        0, Length64(q), Length64(q), 0.0, InverseLength64(q), InverseArea64(q)
    )
    raw.add_road_elevation_profile_si(0, q, q, 0.0, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_elevation_profile_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_road_elevation_profile(
                0,
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile_si(0, bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile(
                0,
                Length64(q),
                Length64(bad),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile_si(0, q, bad, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile(
                0,
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(bad),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile_si(0, q, q, 0.0, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile(
                0,
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile_si(0, q, q, 0.0, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_section_offset_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_section_offset(
        0, Length64(q), Length64(q), 0.0, InverseLength64(q), InverseArea64(q)
    )
    raw.create_section_offset_si(0, q, q, 0.0, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_section_offset_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_section_offset(
                0,
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset_si(0, bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset(
                0,
                Length64(q),
                Length64(bad),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset_si(0, q, bad, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset(
                0,
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(bad),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset_si(0, q, q, 0.0, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset(
                0,
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset_si(0, q, q, 0.0, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_road_speed_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.create_road_speed(0, Length64(q), "solid", Velocity64(q))
    raw.create_road_speed_opendrive(0, q, "solid", q, "m/s")
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_create_road_speed_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.create_road_speed(0, Length64(bad), "solid", Velocity64(q))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_speed_opendrive(0, bad, "solid", q, "m/s")
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_speed(0, Length64(q), "solid", Velocity64(bad))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_speed_opendrive(0, q, "solid", bad, "m/s")
        assert_equal(_builder_state(b), before)


def test_builder_add_road_object_crosswalk_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_road_object_crosswalk(
        0,
        "new",
        Length64(q),
        Length64(q),
        Length64(q),
        Angle64(q),
        Angle64(q),
        Angle64(q),
        "none",
        Length64(q),
        Length64(q),
        List[CrosswalkPoint](),
    )
    raw.add_road_object_crosswalk_si(
        0, "new", q, q, q, q, q, q, "none", q, q, List[CrosswalkPoint]()
    )
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_object_crosswalk_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                bad,
                q,
                q,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                q,
                bad,
                q,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                q,
                q,
                bad,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                q,
                q,
                q,
                bad,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(bad),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                q,
                q,
                q,
                q,
                bad,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(bad),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                q,
                q,
                q,
                q,
                q,
                bad,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(bad),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                q,
                q,
                q,
                q,
                q,
                q,
                "none",
                bad,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(bad),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                q,
                q,
                q,
                q,
                q,
                q,
                "none",
                q,
                bad,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_line_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_road_geometry_line(
        0, Length64(q), Length64(q), Length64(q), Angle64(q), Length64(q)
    )
    raw.add_road_geometry_line_si(0, q, q, q, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_geometry_line_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_road_geometry_line(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line_si(0, bad, q, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line(
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line_si(0, q, bad, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line(
                0,
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line_si(0, q, q, bad, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line_si(0, q, q, q, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line_si(0, q, q, q, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_arc_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_road_geometry_arc(
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        Angle64(q),
        Length64(q),
        InverseLength64(q),
    )
    raw.add_road_geometry_arc_si(0, q, q, q, q, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_geometry_arc_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, bad, q, q, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, q, bad, q, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, q, q, bad, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Length64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, q, q, q, bad, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, q, q, q, q, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, q, q, q, q, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_spiral_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_road_geometry_spiral(
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        Angle64(q),
        Length64(q),
        InverseLength64(q),
        InverseLength64(q),
    )
    raw.add_road_geometry_spiral_si(0, q, q, q, q, q, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_geometry_spiral_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, bad, q, q, q, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, q, bad, q, q, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, q, q, bad, q, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Length64(q),
                InverseLength64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, q, q, q, bad, q, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                InverseLength64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, q, q, q, q, bad, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(bad),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, q, q, q, q, q, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
                InverseLength64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, q, q, q, q, q, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_poly3_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_road_geometry_poly3(
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        Angle64(q),
        Length64(q),
        Length64(q),
        0.0,
        InverseLength64(q),
        InverseArea64(q),
    )
    raw.add_road_geometry_poly3_si(0, q, q, q, q, q, q, 0.0, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_geometry_poly3_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, bad, q, q, q, q, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, bad, q, q, q, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, q, bad, q, q, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, q, q, bad, q, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, q, q, q, bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                Length64(bad),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, q, q, q, q, bad, 0.0, q, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(bad),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, q, q, q, q, q, 0.0, bad, q)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, q, q, q, q, q, 0.0, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_param_poly3_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_road_geometry_param_poly3(
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        Angle64(q),
        Length64(q),
        CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
        CubicPolynomial.constant(Length64(0)),
    )
    raw.add_road_geometry_param_poly3_si(
        0,
        q,
        q,
        q,
        q,
        q,
        CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
        CubicPolynomial.constant(Length64(0)),
        "arcLength",
    )
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_road_geometry_param_poly3_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_road_geometry_param_poly3(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3_si(
                0,
                bad,
                q,
                q,
                q,
                q,
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
                "arcLength",
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3(
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Length64(q),
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3_si(
                0,
                q,
                bad,
                q,
                q,
                q,
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
                "arcLength",
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Length64(q),
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3_si(
                0,
                q,
                q,
                bad,
                q,
                q,
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
                "arcLength",
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Length64(q),
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3_si(
                0,
                q,
                q,
                q,
                bad,
                q,
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
                "arcLength",
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3_si(
                0,
                q,
                q,
                q,
                q,
                bad,
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
                "arcLength",
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_signal_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    _ = b.add_signal(
        0,
        SignalId("typed"),
        Length64(q),
        Length64(q),
        "new",
        "no",
        "none",
        Length64(q),
        "",
        "solid",
        "",
        0.0,
        "",
        Length64(q),
        Length64(q),
        "",
        Angle64(q),
        Angle64(q),
        Angle64(q),
        True,
    )
    _ = raw.add_signal_si(
        0,
        SignalId("typed"),
        q,
        q,
        "new",
        "no",
        "none",
        q,
        "",
        "solid",
        "",
        0.0,
        "",
        q,
        q,
        "",
        q,
        q,
        q,
        True,
    )
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_signal_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(bad),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(q),
                "",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                bad,
                q,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                q,
                "",
                q,
                q,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(q),
                Length64(bad),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(q),
                "",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                q,
                bad,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                q,
                "",
                q,
                q,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(bad),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(q),
                "",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                q,
                q,
                "new",
                "no",
                "none",
                bad,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                q,
                "",
                q,
                q,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(bad),
                Length64(q),
                "",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                q,
                q,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                bad,
                q,
                "",
                q,
                q,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(bad),
                "",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                q,
                q,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                bad,
                "",
                q,
                q,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(q),
                "",
                Angle64(bad),
                Angle64(q),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                q,
                q,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                q,
                "",
                bad,
                q,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(q),
                "",
                Angle64(q),
                Angle64(bad),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                q,
                q,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                q,
                "",
                q,
                bad,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(q),
                "",
                Angle64(q),
                Angle64(q),
                Angle64(bad),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                q,
                q,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                q,
                "",
                q,
                q,
                bad,
                True,
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_signal_position_inertial_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_signal_position_inertial(
        SignalId("typed"),
        Length64(q),
        Length64(q),
        Length64(q),
        Angle64(q),
        Angle64(q),
        Angle64(q),
    )
    raw.add_signal_position_inertial_si(SignalId("typed"), q, q, q, q, q, q)
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_signal_position_inertial_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_signal_position_inertial(
                SignalId("typed"),
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial_si(
                SignalId("typed"), bad, q, q, q, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial(
                SignalId("typed"),
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial_si(
                SignalId("typed"), q, bad, q, q, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial(
                SignalId("typed"),
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial_si(
                SignalId("typed"), q, q, bad, q, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial(
                SignalId("typed"),
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial_si(
                SignalId("typed"), q, q, q, bad, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial(
                SignalId("typed"),
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(bad),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial_si(
                SignalId("typed"), q, q, q, q, bad, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial(
                SignalId("typed"),
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_inertial_si(
                SignalId("typed"), q, q, q, q, q, bad
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_signal_position_road_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    b.add_signal_position_road(
        SignalId("typed"),
        RoadId(1),
        Length64(q),
        Length64(q),
        Length64(q),
        Angle64(q),
        Angle64(q),
        Angle64(q),
    )
    raw.add_signal_position_road_si(
        SignalId("typed"), RoadId(1), q, q, q, q, q, q
    )
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_signal_position_road_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            b.add_signal_position_road(
                SignalId("typed"),
                RoadId(1),
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road_si(
                SignalId("typed"), RoadId(1), bad, q, q, q, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road(
                SignalId("typed"),
                RoadId(1),
                Length64(q),
                Length64(bad),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road_si(
                SignalId("typed"), RoadId(1), q, bad, q, q, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road(
                SignalId("typed"),
                RoadId(1),
                Length64(q),
                Length64(q),
                Length64(bad),
                Angle64(q),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road_si(
                SignalId("typed"), RoadId(1), q, q, bad, q, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road(
                SignalId("typed"),
                RoadId(1),
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(bad),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road_si(
                SignalId("typed"), RoadId(1), q, q, q, bad, q, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road(
                SignalId("typed"),
                RoadId(1),
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(bad),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road_si(
                SignalId("typed"), RoadId(1), q, q, q, q, bad, q
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road(
                SignalId("typed"),
                RoadId(1),
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road_si(
                SignalId("typed"), RoadId(1), q, q, q, q, q, bad
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_signal_reference_typed_and_raw_adapters() raises:
    var q = _precise()
    var b = _builder()
    var raw = _builder()
    _ = b.add_signal_reference(
        0, SignalId("typed"), Length64(q), Length64(q), "none"
    )
    _ = raw.add_signal_reference_si(0, SignalId("typed"), q, q, "none")
    assert_equal(_builder_state(b), _builder_state(raw))


def test_builder_add_signal_reference_rejects_before_mutation() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in _bad_values():
        with assert_raises():
            _ = b.add_signal_reference(
                0, SignalId("typed"), Length64(bad), Length64(q), "none"
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_reference_si(0, SignalId("typed"), bad, q, "none")
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_reference(
                0, SignalId("typed"), Length64(q), Length64(bad), "none"
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_reference_si(0, SignalId("typed"), q, bad, "none")
        assert_equal(_builder_state(b), before)


def test_builder_add_road_rejects_invalid_domain() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1)), 0.0]:
        with assert_raises():
            _ = b.add_road(
                RoadId(1),
                "new",
                Length64(bad),
                NO_JUNCTION,
                RoadId(0),
                RoadId(0),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_road_si(
                RoadId(1), "new", bad, NO_JUNCTION, RoadId(0), RoadId(0), True
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_road_section_rejects_invalid_domain() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = b.add_road_section(0, SectionId(1), Length64(bad))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_road_section_si(0, SectionId(1), bad)
        assert_equal(_builder_state(b), before)


def test_builder_lane_rejects_invalid_domain() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = b.lane(RoadId(1), LaneId(-1), Length64(bad))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.lane_si(RoadId(1), LaneId(-1), bad)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_width_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_width(
                (0, 0, 0),
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_width_si((0, 0, 0), bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_border_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_border(
                (0, 0, 0),
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_border_si((0, 0, 0), bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_height_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_height(
                (0, 0, 0), Length64(bad), Length64(q), Length64(q)
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_height_si((0, 0, 0), bad, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_material_rejects_invalid_domain() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_material((0, 0, 0), Length64(bad), "", 0.0, 0.0)
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_material_si((0, 0, 0), bad, "", 0.0, 0.0)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_rule_rejects_invalid_domain() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_rule((0, 0, 0), Length64(bad), "")
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_rule_si((0, 0, 0), bad, "")
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_visibility_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_visibility(
                (0, 0, 0),
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_visibility_si((0, 0, 0), bad, q, q, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_access_rejects_invalid_domain() raises:
    _ = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_access((0, 0, 0), Length64(bad), "")
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_access_si((0, 0, 0), bad, "")
        assert_equal(_builder_state(b), before)


def test_builder_create_lane_speed_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_lane_speed((0, 0, 0), Length64(bad), Velocity64(q))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_lane_speed_opendrive((0, 0, 0), bad, q, "m/s")
        assert_equal(_builder_state(b), before)


def test_builder_create_road_mark_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_road_mark(
                (0, 0, 0),
                0,
                Length64(bad),
                "solid",
                "",
                "white",
                "",
                Length64(q),
                "both",
                Length64(q),
                "",
                Length64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_si(
                (0, 0, 0),
                0,
                bad,
                "solid",
                "",
                "white",
                "",
                q,
                "both",
                q,
                "",
                q,
                True,
            )
        assert_equal(_builder_state(b), before)


def test_builder_create_road_mark_type_line_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_road_mark_type_line(
                (0, 0, 0),
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
                "",
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_mark_type_line_si((0, 0, 0), 0, q, q, q, bad, "", q)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_elevation_profile_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_road_elevation_profile(
                0,
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_elevation_profile_si(0, bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_create_section_offset_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_section_offset(
                0,
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_section_offset_si(0, bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_create_road_speed_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.create_road_speed(0, Length64(bad), "solid", Velocity64(q))
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.create_road_speed_opendrive(0, bad, "solid", q, "m/s")
        assert_equal(_builder_state(b), before)


def test_builder_add_road_object_crosswalk_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_road_object_crosswalk(
                0,
                "new",
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_object_crosswalk_si(
                0,
                "new",
                bad,
                q,
                q,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_line_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_road_geometry_line(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line_si(0, bad, q, q, q, q)
        assert_equal(_builder_state(b), before)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1)), 0.0]:
        with assert_raises():
            b.add_road_geometry_line(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_line_si(0, q, q, q, q, bad)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_arc_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, bad, q, q, q, q, q)
        assert_equal(_builder_state(b), before)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1)), 0.0]:
        with assert_raises():
            b.add_road_geometry_arc(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_arc_si(0, q, q, q, q, bad, q)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_spiral_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                InverseLength64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, bad, q, q, q, q, q, q)
        assert_equal(_builder_state(b), before)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1)), 0.0]:
        with assert_raises():
            b.add_road_geometry_spiral(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                InverseLength64(q),
                InverseLength64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_spiral_si(0, q, q, q, q, bad, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_poly3_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, bad, q, q, q, q, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1)), 0.0]:
        with assert_raises():
            b.add_road_geometry_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                Length64(q),
                0.0,
                InverseLength64(q),
                InverseArea64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_poly3_si(0, q, q, q, q, bad, q, 0.0, q, q)
        assert_equal(_builder_state(b), before)


def test_builder_add_road_geometry_param_poly3_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_road_geometry_param_poly3(
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(q),
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3_si(
                0,
                bad,
                q,
                q,
                q,
                q,
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
                "arcLength",
            )
        assert_equal(_builder_state(b), before)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1)), 0.0]:
        with assert_raises():
            b.add_road_geometry_param_poly3(
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                Angle64(q),
                Length64(bad),
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_road_geometry_param_poly3_si(
                0,
                q,
                q,
                q,
                q,
                bad,
                CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
                CubicPolynomial.constant(Length64(0)),
                "arcLength",
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_signal_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = b.add_signal(
                0,
                SignalId("typed"),
                Length64(bad),
                Length64(q),
                "new",
                "no",
                "none",
                Length64(q),
                "",
                "solid",
                "",
                0.0,
                "",
                Length64(q),
                Length64(q),
                "",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_si(
                0,
                SignalId("typed"),
                bad,
                q,
                "new",
                "no",
                "none",
                q,
                "",
                "solid",
                "",
                0.0,
                "",
                q,
                q,
                "",
                q,
                q,
                q,
                True,
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_signal_position_road_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            b.add_signal_position_road(
                SignalId("typed"),
                RoadId(1),
                Length64(bad),
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            b.add_signal_position_road_si(
                SignalId("typed"), RoadId(1), bad, q, q, q, q, q
            )
        assert_equal(_builder_state(b), before)


def test_builder_add_signal_reference_rejects_invalid_domain() raises:
    var q = _precise()
    var b = _builder()
    var before = _builder_state(b)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = b.add_signal_reference(
                0, SignalId("typed"), Length64(bad), Length64(q), "none"
            )
        assert_equal(_builder_state(b), before)
        with assert_raises():
            _ = b.add_signal_reference_si(0, SignalId("typed"), bad, q, "none")
        assert_equal(_builder_state(b), before)


def _same_stations(typed: List[Waypoint], raw: List[Waypoint]) raises:
    assert_equal(len(typed), len(raw))
    for i in range(len(typed)):
        assert_equal(typed[i].road_id, raw[i].road_id)
        assert_equal(typed[i].section_id, raw[i].section_id)
        assert_equal(typed[i].lane_id, raw[i].lane_id)
        assert_equal(_word(typed[i].s), _word(raw[i].s))


def test_map_typed_walk_sampling_signal_and_landmark_wrappers() raises:
    var builder = _builder()
    var map = builder.build()
    var start = _waypoint(1.0)
    var step = _precise()
    _same_stations(
        map.next(start, Length64(step)), map.next_meters(start, step)
    )
    _same_stations(
        map.previous(start, Length64(0.5)), map.previous_meters(start, 0.5)
    )
    _same_stations(
        map.generate_waypoints(Length64(3)), map.generate_waypoints_meters(3)
    )
    _same_stations(
        map.next_until_lane_end(start, Length64(3)),
        map.next_until_lane_end_meters(start, 3),
    )
    _same_stations(
        map.previous_until_lane_start(_waypoint(9), Length64(3)),
        map.previous_until_lane_start_meters(_waypoint(9), 3),
    )
    assert_equal(
        _word(map.lane_width(start).value), _word(map.lane_width_meters(start))
    )
    assert_equal(map.lane_width_float32(start).value, 3.5)
    var signals = map.signals_in_distance(start, Length64(2))
    var signals_raw = map.signals_in_distance_meters(start, 2)
    assert_equal(len(signals), 1)
    assert_equal(len(signals_raw), 1)
    assert_equal(signals[0].accumulated_s_quantity().value, 1.0)
    assert_equal(
        _word(signals[0].accumulated_s), _word(signals_raw[0].accumulated_s)
    )
    var landmarks = map.landmarks_in_distance(start, Length64(2))
    var landmarks_raw = map.landmarks_in_distance_meters(start, 2)
    assert_equal(len(landmarks), 1)
    assert_equal(len(landmarks_raw), 1)
    assert_equal(landmarks[0].distance_quantity().value, 1.0)
    assert_equal(_word(landmarks[0].distance), _word(landmarks_raw[0].distance))
    assert_equal(
        len(map.landmarks_of_type_in_distance(start, Length64(2), "stop")), 1
    )
    assert_equal(
        len(map.landmarks_of_type_in_distance_meters(start, 2, "stop")), 1
    )
    assert_equal(len(map.signals_in_distance(start, Length64(0))), 0)
    assert_equal(len(map.landmarks_in_distance(start, Length64(0))), 0)
    assert_equal(
        len(map.landmarks_of_type_in_distance(start, Length64(0), "stop")), 0
    )


def test_map_rejects_nonfinite_and_invalid_distance_domains() raises:
    var builder = _builder()
    var map = builder.build()
    var start = _waypoint(1)
    var bad_values = _bad_values()
    bad_values.append(-1)
    for bad in bad_values:
        with assert_raises():
            _ = map.next(start, Length64(bad))
        with assert_raises():
            _ = map.next_meters(start, bad)
        with assert_raises():
            _ = map.previous(start, Length64(bad))
        with assert_raises():
            _ = map.previous_meters(start, bad)
        with assert_raises():
            _ = map.generate_waypoints(Length64(bad))
        with assert_raises():
            _ = map.generate_waypoints_meters(bad)
        with assert_raises():
            _ = map.next_until_lane_end(start, Length64(bad))
        with assert_raises():
            _ = map.next_until_lane_end_meters(start, bad)
        with assert_raises():
            _ = map.previous_until_lane_start(start, Length64(bad))
        with assert_raises():
            _ = map.previous_until_lane_start_meters(start, bad)
        with assert_raises():
            _ = map.signals_in_distance(start, Length64(bad))
        with assert_raises():
            _ = map.signals_in_distance_meters(start, bad)
        with assert_raises():
            _ = map.landmarks_in_distance(start, Length64(bad))
        with assert_raises():
            _ = map.landmarks_in_distance_meters(start, bad)
        with assert_raises():
            _ = map.landmarks_of_type_in_distance(start, Length64(bad), "stop")
        with assert_raises():
            _ = map.landmarks_of_type_in_distance_meters(start, bad, "stop")
    with assert_raises():
        _ = map.next(start, Length64(0))
    with assert_raises():
        _ = map.previous(start, Length64(0))
    with assert_raises():
        _ = map.generate_waypoints(Length64(0))
    # The smallest spacing fails immediately when adding it cannot advance.
    var eta = bitcast[DType.float64](UInt64(1))
    with assert_raises(contains="advance"):
        _ = map.generate_waypoints(Length64(eta))
    with assert_raises():
        _ = map.next_until_lane_end(start, Length64(eta))
    with assert_raises():
        _ = map.previous_until_lane_start(start, Length64(eta))
    assert_equal(_word(map.next(start, Length64(eta))[0].s), _word(start.s))
    assert_equal(_word(map.previous(start, Length64(eta))[0].s), _word(start.s))


def test_map_low_bits_large_steps_and_adjacent_endpoints() raises:
    var builder = _builder()
    var map = builder.build()
    var precise = _precise()
    var step = map.next(_waypoint(0), Length64(precise))[0]
    assert_equal(_word(step.s), _word(precise - EPSILON))
    var next_ten = bitcast[DType.float64](_word(10.0) + UInt64(1))
    var before_ten = bitcast[DType.float64](_word(10.0) - UInt64(1))
    _same_stations(
        map.next(_waypoint(9), Length64(before_ten - 9)),
        map.next_meters(_waypoint(9), before_ten - 9),
    )
    _same_stations(
        map.next(_waypoint(9), Length64(next_ten - 9)),
        map.next_meters(_waypoint(9), next_ten - 9),
    )
    assert_equal(len(map.next(_waypoint(1), Length64(1e300))), 0)
    assert_equal(len(map.previous(_waypoint(1), Length64(1e300))), 0)
    var large = bitcast[DType.float64](UInt64(0x4160000000000001))
    var waypoint = _waypoint(large)
    assert_equal(_word(waypoint.s_quantity().value), _word(large))
    assert_true(Float64(Float32(waypoint.s)) != waypoint.s)


def test_road_public_quantity_wrappers_and_raw_parity() raises:
    var builder = _builder()
    ref road = builder.roads[0]
    var q = _precise()
    assert_equal(_word(road.length_quantity().value), _word(road.length))
    assert_equal(road.section_length(0).value, road.section_length_meters(0))
    assert_equal(road.lane_length(0).value, road.lane_length_meters(0))
    assert_equal(
        road.upper_bound(Length64(q)).value, road.upper_bound_meters(q)
    )
    assert_equal(
        road.sections_at(Length64(q))[0], road.sections_at_meters(q)[0]
    )
    assert_equal(
        road.lane_by_distance(Length64(q), LaneId(-1)),
        road.lane_by_distance_meters(q, LaneId(-1)),
    )
    assert_equal(
        road.lanes_by_distance(Length64(q))[0],
        road.lanes_by_distance_meters(q)[0],
    )
    assert_equal(road.lanes_at(Length64(q))[0], road.lanes_at_meters(q)[0])
    assert_false(Bool(road.next_lane(Length64(q), LaneId(-1))))
    assert_false(Bool(road.prev_lane(Length64(0), LaneId(-1))))
    assert_equal(
        road.elevation_on(Length64(q)).a, road.elevation_on_meters(q).a
    )
    assert_equal(_word(road.directed_point(Length64(q)).x), _word(q))
    assert_equal(
        _word(road.directed_point_no_lane_offset(Length64(q)).x), _word(q)
    )
    assert_equal(
        road.lane_width(0, 0, Length64(q)).value,
        road.lane_width_meters(0, 0, q),
    )
    _same_vector(
        road.lane_transform(0, 0, Length64(q)).location,
        road.lane_transform_meters(0, 0, q).location,
    )
    _same_vector(
        road.lane_corners(0, 0, Length64(q))[0],
        road.lane_corners_meters(0, 0, q)[0],
    )
    assert_equal(
        road.lane_edge_offsets(0, 0, Length64(q))[0].value,
        road.lane_edge_offsets_meters(0, 0, q)[0],
    )
    var nearest = road.nearest_point(Vector3(2, 3, 0))
    var nearest_raw = road.nearest_point_meters(Vector3(2, 3, 0))
    assert_equal(nearest[0].value, nearest_raw[0])
    assert_equal(nearest[1].value, nearest_raw[1])
    var lane = road.nearest_lane(Length64(2), Vector3(2, -1.75, 0))
    var lane_raw = road.nearest_lane_meters(2, Vector3(2, -1.75, 0))
    assert_equal(Bool(lane[0]), Bool(lane_raw[0]))
    assert_equal(lane[0].value().lane_id, lane_raw[0].value().lane_id)
    assert_equal(lane[1].value, lane_raw[1])
    var added = road.add_section(SectionId(1), Length64(q))
    assert_equal(_word(road.sections[added].s_quantity().value), _word(q))
    _ = road.add_section_meters(SectionId(2), 5)
    assert_equal(road.sections[road.section_index(SectionId(2))].s, 5)


def test_road_queries_reject_nonfinite_stations_without_mutation() raises:
    var builder = _builder()
    ref road = builder.roads[0]
    for bad in _bad_values():
        with assert_raises():
            _ = road.add_section(SectionId(9), Length64(bad))
        with assert_raises():
            _ = road.add_section_meters(SectionId(9), bad)
        assert_equal(len(road.sections), 1)
        with assert_raises():
            _ = road.upper_bound(Length64(bad))
        with assert_raises():
            _ = road.sections_at(Length64(bad))
        with assert_raises():
            _ = road.lane_by_distance(Length64(bad), LaneId(-1))
        with assert_raises():
            _ = road.lanes_by_distance(Length64(bad))
        with assert_raises():
            _ = road.lanes_at(Length64(bad))
        with assert_raises():
            _ = road.next_lane(Length64(bad), LaneId(-1))
        with assert_raises():
            _ = road.prev_lane(Length64(bad), LaneId(-1))
        with assert_raises():
            _ = road.elevation_on(Length64(bad))
        with assert_raises():
            _ = road.directed_point(Length64(bad))
        with assert_raises():
            _ = road.directed_point_no_lane_offset(Length64(bad))
        with assert_raises():
            _ = road.nearest_lane(Length64(bad), Vector3(0, 0, 0))
        with assert_raises():
            _ = road.lane_width(0, 0, Length64(bad))
        with assert_raises():
            _ = road.lane_transform(0, 0, Length64(bad))
        with assert_raises():
            _ = road.lane_corners(0, 0, Length64(bad))
        with assert_raises():
            _ = road.lane_edge_offsets(0, 0, Length64(bad))


def test_record_search_preserves_adjacent_float64_stations() raises:
    var q = _precise()
    var records = List[RoadInfoLaneRule]()
    records.append(RoadInfoLaneRule(Length64(1), "first"))
    records.append(RoadInfoLaneRule(Length64(q), "second"))
    assert_equal(info_index(records, Length64(1)), 0)
    assert_equal(info_index(records, Length64(q)), 1)
    assert_equal(info_index_meters(records, q), 1)
    assert_equal(info_at(records, Length64(q)).value().value, "second")
    assert_equal(info_at_meters(records, q).value().value, "second")
    assert_equal(_word(records[1].distance().value), _word(q))
    assert_equal(_word(records[1].distance_meters()), _word(q))
    var forward = infos_in_range(records, Length64(1), Length64(q))
    var backward = infos_in_range(records, Length64(q), Length64(1))
    assert_equal(len(forward), 2)
    assert_equal(forward[0].value, "first")
    assert_equal(backward[0].value, "second")
    assert_equal(len(infos_in_range_meters(records, 1, q)), 2)
    for bad in _bad_values():
        with assert_raises():
            _ = info_index(records, Length64(bad))
        with assert_raises():
            _ = info_index_meters(records, bad)
        with assert_raises():
            _ = info_at(records, Length64(bad))
        with assert_raises():
            _ = info_at_meters(records, bad)
        with assert_raises():
            _ = infos_in_range(records, Length64(bad), Length64(q))
        with assert_raises():
            _ = infos_in_range(records, Length64(1), Length64(bad))
        with assert_raises():
            _ = infos_in_range_meters(records, bad, q)
        with assert_raises():
            _ = infos_in_range_meters(records, 1, bad)
        records[0].s = bad
        with assert_raises():
            _ = records[0].distance()
        records[0].s = 1


def test_geometry_typed_float64_factories_and_views() raises:
    var q = _precise()
    var base = RoadGeometry(
        LINE, Length64(q), Length64(q), Length64(q), Angle64(q), Length64(q)
    )
    var raw = RoadGeometry.from_meters(LINE, q, q, q, q, q)
    assert_equal(_word(base.s_quantity().value), _word(q))
    assert_equal(_word(base.x_quantity().value), _word(q))
    assert_equal(_word(base.y_quantity().value), _word(q))
    assert_equal(_word(base.heading_quantity().value), _word(q))
    assert_equal(_word(base.length_quantity().value), _word(q))
    assert_equal(_word(base.end_s().value), _word(raw.end_s_meters()))
    assert_equal(
        _word(base.pos_at(Length64(0.5)).x), _word(raw.pos_at_meters(0.5).x)
    )
    var arc = with_arc(base.copy(), InverseLength64(q))
    var arc_raw = with_arc_si(base.copy(), q)
    assert_equal(_word(arc.curvature_start_quantity().value), _word(q))
    assert_equal(_word(arc.curvature_end_quantity().value), _word(q))
    assert_equal(arc.kind, arc_raw.kind)
    var spiral = with_spiral(
        base.copy(), InverseLength64(q), InverseLength64(0)
    )
    var spiral_raw = with_spiral_si(base.copy(), q, 0)
    assert_equal(
        _word(spiral.curvature_start), _word(spiral_raw.curvature_start)
    )
    var polynomial = with_poly3(
        base.copy(), Length64(q), 0, InverseLength64(0), InverseArea64(0)
    )
    var polynomial_raw = with_poly3_si(base.copy(), q, 0, 0, 0)
    assert_equal(
        _word(polynomial.u_coefficients()[0]),
        _word(polynomial_raw.u_coefficients()[0]),
    )
    assert_equal(_word(polynomial.u_coefficients()[0]), _word(q))
    var parametric = with_param_poly3(
        base.copy(),
        CubicPolynomial.from_coefficients(0, 1, 0, 0, 0),
        CubicPolynomial.constant(Length64(0)),
    )
    assert_equal(parametric.kind, PARAM_POLY3)
    var point = DirectedPoint(Length64(q), Length64(0), Length64(0), Angle64(q))
    assert_equal(_word(point.heading().value), _word(q))
    var kilometers = RoadGeometry(
        LINE,
        Length64(1, KILOMETER),
        Length64(2, KILOMETER),
        Length64(0),
        Angle64(0, DEGREE),
        Length64(3, KILOMETER),
    )
    assert_equal(kilometers.s, 1000)
    assert_equal(kilometers.x, 2000)
    assert_equal(kilometers.end_s().value, 4000)


def test_geometry_checks_dimensions_before_publishing_records() raises:
    for bad in _bad_values():
        with assert_raises():
            _ = RoadGeometry(
                LINE,
                Length64(bad),
                Length64(0),
                Length64(0),
                Angle64(0),
                Length64(10),
            )
        with assert_raises():
            _ = RoadGeometry(
                LINE,
                Length64(0),
                Length64(bad),
                Length64(0),
                Angle64(0),
                Length64(10),
            )
        with assert_raises():
            _ = RoadGeometry(
                LINE,
                Length64(0),
                Length64(0),
                Length64(bad),
                Angle64(0),
                Length64(10),
            )
        with assert_raises():
            _ = RoadGeometry(
                LINE,
                Length64(0),
                Length64(0),
                Length64(0),
                Angle64(bad),
                Length64(10),
            )
        with assert_raises():
            _ = RoadGeometry(
                LINE,
                Length64(0),
                Length64(0),
                Length64(0),
                Angle64(0),
                Length64(bad),
            )
        var base = RoadGeometry(
            LINE,
            Length64(0),
            Length64(0),
            Length64(0),
            Angle64(0),
            Length64(10),
        )
        with assert_raises():
            _ = base.pos_at(Length64(bad))
        with assert_raises():
            _ = with_arc(base.copy(), InverseLength64(bad))
        with assert_raises():
            _ = with_spiral(
                base.copy(), InverseLength64(bad), InverseLength64(0)
            )
        with assert_raises():
            _ = with_spiral(
                base.copy(), InverseLength64(0), InverseLength64(bad)
            )
        with assert_raises():
            _ = with_poly3(
                base.copy(),
                Length64(bad),
                0,
                InverseLength64(0),
                InverseArea64(0),
            )
        with assert_raises():
            _ = with_poly3(
                base.copy(),
                Length64(0),
                0,
                InverseLength64(bad),
                InverseArea64(0),
            )
        with assert_raises():
            _ = with_poly3(
                base.copy(),
                Length64(0),
                0,
                InverseLength64(0),
                InverseArea64(bad),
            )
    with assert_raises():
        _ = RoadGeometry(
            LINE,
            Length64(-1),
            Length64(0),
            Length64(0),
            Angle64(0),
            Length64(1),
        )
    for length in [0.0, -1.0]:
        with assert_raises():
            _ = RoadGeometry(
                LINE,
                Length64(0),
                Length64(0),
                Length64(0),
                Angle64(0),
                Length64(length),
            )


def test_geometry_raw_field_views_reject_mutated_nonfinite_values() raises:
    var base = RoadGeometry(
        LINE, Length64(0), Length64(0), Length64(0), Angle64(0), Length64(10)
    )
    for bad in _bad_values():
        base.s = bad
        with assert_raises():
            _ = base.s_quantity()
        base.s = 0
        base.x = bad
        with assert_raises():
            _ = base.x_quantity()
        base.x = 0
        base.y = bad
        with assert_raises():
            _ = base.y_quantity()
        base.y = 0
        base.heading = bad
        with assert_raises():
            _ = base.heading_quantity()
        base.heading = 0
        base.length = bad
        with assert_raises():
            _ = base.length_quantity()
        base.length = 10
        base.curvature_start = bad
        with assert_raises():
            _ = base.curvature_start_quantity()
        base.curvature_start = 0
        base.curvature_end = bad
        with assert_raises():
            _ = base.curvature_end_quantity()
        base.curvature_end = 0


def _xml(
    length: Float64, coordinate: Float64, width: Float64, elevation: Float64
) -> String:
    # Reconstruct explicit source-unit fields, not a display-only rounded pose.
    return (
        '<OpenDRIVE><road id="1" name="quantity" length="'
        + String(length)
        + '" junction="-1"><planView><geometry s="0" x="'
        + String(coordinate)
        + '" y="0" hdg="0" length="'
        + String(length)
        + '"><line/></geometry></planView><elevationProfile><elevation'
        ' s="0" a="'
        + String(elevation)
        + '" b="0" c="0" d="0"/></elevationProfile><lanes><laneOffset s="0"'
        ' a="0" b="0" c="0" d="0"/><laneSection s="0"><center><lane id="0"'
        ' type="none"/></center><right><lane id="-1" type="driving"><width'
        ' sOffset="0" a="'
        + String(width)
        + '" b="0" c="0"'
        ' d="0"/></lane></right></laneSection></lanes></road></OpenDRIVE>'
    )


def test_opendrive_round_trip_retains_wide_fields_and_location_narrowing() raises:
    var length = bitcast[DType.float64](UInt64(0x4024000000000001))
    var coordinate = _precise()
    var width = bitcast[DType.float64](UInt64(0x400C000000000001))
    var map = load_opendrive(_xml(length, coordinate, width, coordinate))
    ref road = map.road(RoadId(1))
    # The baseline MapBuilder stores its start Location through Float32.
    # The independent expected conversion preserves that deliberate layout,
    # while road stations, widths and elevation coefficients stay Float64.
    var location = Float64(Float32(coordinate))
    assert_equal(_word(road.length_quantity().value), _word(length))
    assert_equal(
        _word(road.info.geometries[0].geometry.x_quantity().value),
        _word(location),
    )
    assert_equal(
        _word(road.info.elevations[0].polynomial.a_quantity().value),
        _word(coordinate),
    )
    var waypoint = _waypoint(1)
    assert_equal(_word(map.lane_width(waypoint).value), _word(width))
    var again = load_opendrive(
        _xml(
            road.length_quantity().value,
            road.info.geometries[0].geometry.x_quantity().value,
            map.lane_width(waypoint).value,
            road.info.elevations[0].polynomial.a_quantity().value,
        )
    )
    assert_equal(_word(again.road(RoadId(1)).length), _word(length))
    assert_equal(_word(again.lane_width(waypoint).value), _word(width))
    assert_equal(
        _word(again.road(RoadId(1)).info.geometries[0].geometry.x),
        _word(location),
    )
    assert_equal(
        _word(again.road(RoadId(1)).info.elevations[0].polynomial.a),
        _word(coordinate),
    )


def test_float32_render_quantities_keep_legacy_layout_and_refuse_nonfinite() raises:
    var q = bitcast[DType.float32](UInt32(0x40800001))
    assert_equal(
        body_style_of("vehicle.test", Length(q)),
        body_style_of_si("vehicle.test", q),
    )
    assert_equal(wheel_inset(Length(q)).value, wheel_inset_si(q))
    assert_equal(stride(Velocity(q)).value, stride_si(q).value)
    var body = body_geometry(Length(q), Length(2), Length(1.5), SEDAN)
    var body_raw = body_geometry_si(q, 2, 1.5, SEDAN)
    assert_equal(body.vertex_count(), body_raw.vertex_count())
    assert_equal(body.triangle_count(), body_raw.triangle_count())
    var cabin = cabin_geometry(Length(q), Length(2), Length(1.5), SEDAN)
    var cabin_raw = cabin_geometry_si(q, 2, 1.5, SEDAN)
    assert_equal(cabin.vertex_count(), cabin_raw.vertex_count())
    assert_equal(cabin.triangle_count(), cabin_raw.triangle_count())
    for bad64 in _bad_values():
        var bad = Float32(bad64)
        with assert_raises():
            _ = body_style_of("vehicle.test", Length(bad))
        with assert_raises():
            _ = wheel_inset(Length(bad))
        with assert_raises():
            _ = stride(Velocity(bad))
        with assert_raises():
            _ = body_geometry(Length(bad), Length(2), Length(1.5), SEDAN)
        with assert_raises():
            _ = body_geometry(Length(4), Length(bad), Length(1.5), SEDAN)
        with assert_raises():
            _ = body_geometry(Length(4), Length(2), Length(bad), SEDAN)
        with assert_raises():
            _ = cabin_geometry(Length(bad), Length(2), Length(1.5), SEDAN)
        with assert_raises():
            _ = cabin_geometry(Length(4), Length(bad), Length(1.5), SEDAN)
        with assert_raises():
            _ = cabin_geometry(Length(4), Length(2), Length(bad), SEDAN)


def test_map_mesh_and_roadside_quantity_wrappers() raises:
    var builder = _builder()
    ref road = builder.roads[0]
    var factory = MeshFactory()
    assert_equal(
        factory.generate_lane(
            road, 0, 0, Length64(1), Length64(4)
        ).vertex_count(),
        factory.generate_lane_si(road, 0, 0, 1, 4).vertex_count(),
    )
    assert_equal(
        factory.generate_tesselated(
            road, 0, 0, Length64(1), Length64(4)
        ).vertex_count(),
        factory.generate_tesselated_si(road, 0, 0, 1, 4).vertex_count(),
    )
    assert_equal(
        factory.generate_sidewalk(
            road, 0, 0, Length64(1), Length64(4)
        ).vertex_count(),
        factory.generate_sidewalk_si(road, 0, 0, 1, 4).vertex_count(),
    )
    assert_equal(
        factory.generate_right_wall(
            road, 0, 0, Length64(1), Length64(4)
        ).vertex_count(),
        factory.generate_right_wall_si(road, 0, 0, 1, 4).vertex_count(),
    )
    assert_equal(
        factory.generate_left_wall(
            road, 0, 0, Length64(1), Length64(4)
        ).vertex_count(),
        factory.generate_left_wall_si(road, 0, 0, 1, 4).vertex_count(),
    )
    var edges = factory.compute_edges_for_lanemark(
        road, 0, 0, Length64(2), Length64(0.15), Length(0)
    )
    var raw_edges = factory.compute_edges_for_lanemark_si(
        road, 0, 0, 2, 0.15, 0
    )
    _same_vector(edges[0], raw_edges[0])
    _same_vector(edges[1], raw_edges[1])
    var side = roadside(road, Length64(2), True)
    var raw_side = roadside_si(road, 2, True)
    assert_equal(Bool(side), Bool(raw_side))
    _same_vector(side.value()[0], raw_side.value()[0])
    for bad in _bad_values():
        with assert_raises():
            _ = factory.generate_lane(road, 0, 0, Length64(bad), Length64(4))
        with assert_raises():
            _ = factory.generate_lane(road, 0, 0, Length64(1), Length64(bad))
        with assert_raises():
            _ = factory.generate_tesselated(
                road, 0, 0, Length64(bad), Length64(4)
            )
        with assert_raises():
            _ = factory.generate_sidewalk(
                road, 0, 0, Length64(bad), Length64(4)
            )
        with assert_raises():
            _ = factory.generate_right_wall(
                road, 0, 0, Length64(bad), Length64(4)
            )
        with assert_raises():
            _ = factory.generate_left_wall(
                road, 0, 0, Length64(bad), Length64(4)
            )
        with assert_raises():
            _ = factory.compute_edges_for_lanemark(
                road, 0, 0, Length64(bad), Length64(0.15), Length(0)
            )
        with assert_raises():
            _ = factory.compute_edges_for_lanemark(
                road, 0, 0, Length64(2), Length64(bad), Length(0)
            )
        with assert_raises():
            _ = factory.compute_edges_for_lanemark(
                road, 0, 0, Length64(2), Length64(0.15), Length(Float32(bad))
            )
        with assert_raises():
            _ = roadside(road, Length64(bad), True)


def test_area_and_navigation_height_return_quantities() raises:
    var distance: Area = distance_squared_2d(
        Vector3(1, 2, 999), Vector3(4, 6, -999)
    )
    assert_equal(distance.value, 25)
    assert_equal(
        distance.value,
        distance_squared_2d_si(Vector3(1, 2, 999), Vector3(4, 6, -999)),
    )
    var polygon = NavPolygon(
        [Vector3(0, 0, 3), Vector3(4, 0, 3), Vector3(0, 4, 3)], AREA_SIDEWALK
    )
    var height: Length = polygon.height_at(Vector3(1, 1, 999))
    assert_equal(height.value, 3)
    assert_equal(height.value, polygon.height_at_si(Vector3(1, 1, 999)))


def test_pid_and_sign_duration_adapters_reject_before_state_changes() raises:
    var pid = PID(0.5, 0.25, 0.125)
    var raw = pid
    assert_equal(pid.run(0.5, Duration(0.25)), raw.run_seconds(0.5, 0.25))
    assert_equal(pid.integral, raw.integral)
    assert_equal(pid.last_input, raw.last_input)
    var sign = TrafficSign(
        SignalId("typed"),
        STOP_SIGN,
        CarlaTransform(
            Length(0),
            Length(0),
            Length(0),
            CarlaRotation(Angle(0), Angle(0), Angle(0)),
        ),
        Velocity(0),
    )
    sign.timers.append(2)
    var sign_raw = sign.copy()
    _ = sign.tick_timers(Duration(0.25))
    _ = sign_raw.tick_timers_seconds(0.25)
    assert_equal(sign.timers[0], 1.75)
    assert_equal(sign.timers[0], sign_raw.timers[0])
    var bad_values = _bad_values()
    bad_values.append(-1)
    for bad64 in bad_values:
        var bad = Float32(bad64)
        var integral = pid.integral
        var last = pid.last_input
        with assert_raises():
            _ = pid.run(0.75, Duration(bad))
        assert_equal(pid.integral, integral)
        assert_equal(pid.last_input, last)
        with assert_raises():
            _ = sign.tick_timers(Duration(bad))
        assert_equal(len(sign.timers), 1)
        assert_equal(sign.timers[0], 1.75)
    with assert_raises():
        _ = pid.run(0.75, Duration(0))
    _ = sign.tick_timers(Duration(0))
    assert_equal(sign.timers[0], 1.75)


def test_road_length_domain_and_wide_waypoint_lookup() raises:
    for bad in [0.0, -1.0]:
        with assert_raises():
            _ = Road(
                RoadId(1),
                "road",
                Length64(bad),
                NO_JUNCTION,
                RoadId(0),
                RoadId(0),
                True,
            )
        with assert_raises():
            _ = Road.from_si(
                RoadId(1), "road", bad, NO_JUNCTION, RoadId(0), RoadId(0), True
            )
    var builder = _builder()
    var map = builder.build()
    var q = _precise()
    var waypoint = map.waypoint_xodr(RoadId(1), LaneId(-1), Length64(q)).value()
    assert_equal(_word(waypoint.s), _word(q))
    assert_equal(
        map.waypoint_xodr_float32(RoadId(1), LaneId(-1), Length(1)).value().s, 1
    )


def test_directed_point_lateral_offset_and_legacy_distance_are_checked() raises:
    var point = DirectedPoint(Length64(2), Length64(3), Length64(4), Angle64(0))
    point.apply_lateral_offset(Length(0.5))
    assert_equal(point.x, 2)
    assert_equal(point.y, 2.5)
    var geometry = RoadGeometry(
        LINE, Length64(0), Length64(0), Length64(0), Angle64(0), Length64(10)
    )
    assert_equal(geometry.pos_from_dist(Length(2)).x, 2)
    for bad64 in _bad_values():
        with assert_raises():
            point.apply_lateral_offset(Length(Float32(bad64)))
        assert_equal(point.x, 2)
        assert_equal(point.y, 2.5)
        with assert_raises():
            _ = geometry.pos_from_dist(Length(Float32(bad64)))
        with assert_raises():
            _ = DirectedPoint(
                Length64(0), Length64(0), Length64(0), Angle64(0), bad64
            )
        with assert_raises():
            _ = DirectedPoint.from_si(0, 0, 0, 0, bad64)


def test_builder_nonfinite_profile_slopes_fail_before_append() raises:
    var builder = _builder()
    var before = _builder_state(builder)
    for bad in _bad_values():
        with assert_raises():
            builder.create_lane_width(
                (0, 0, 0),
                Length64(1),
                Length64(3.5),
                bad,
                InverseLength64(0),
                InverseArea64(0),
            )
        with assert_raises():
            builder.create_lane_border(
                (0, 0, 0),
                Length64(1),
                Length64(3.5),
                bad,
                InverseLength64(0),
                InverseArea64(0),
            )
        with assert_raises():
            builder.create_section_offset(
                0,
                Length64(1),
                Length64(0),
                bad,
                InverseLength64(0),
                InverseArea64(0),
            )
        with assert_raises():
            builder.add_road_elevation_profile(
                0,
                Length64(1),
                Length64(0),
                bad,
                InverseLength64(0),
                InverseArea64(0),
            )
        with assert_raises():
            builder.add_road_geometry_poly3(
                0,
                Length64(1),
                Length64(0),
                Length64(0),
                Angle64(0),
                Length64(1),
                Length64(0),
                bad,
                InverseLength64(0),
                InverseArea64(0),
            )
        assert_equal(_builder_state(builder), before)


def test_kmh_adapter_preserves_wide_speeds_and_round_trip() raises:
    var speed: Velocity64 = from_kmh(1e40)
    assert_true(speed.value > 1e39)
    var source = speed.value * Float64(3.6)
    assert_true(abs(source - 1e40) <= 1e40 * 2.220446049250313e-16)
    assert_equal(from_kmh(36).value, 10)
    assert_equal(from_kmh_float32(36).value, 10)
    with assert_raises():
        _ = from_kmh_float32(1e40)
    for bad in _bad_values():
        with assert_raises():
            _ = from_kmh(bad)
        with assert_raises():
            _ = from_kmh_float32(bad)


def test_signal_inertial_narrowing_failure_preserves_flag_and_transform() raises:
    var builder = _builder()
    # Check both first placement and replacement of a nontrivial placement.
    for already_placed in range(2):
        if already_placed == 1:
            builder.add_signal_position_inertial_si(
                SignalId("typed"), 1, 2, 3, 0.25, 0.5, 0.75
            )
        var before = _builder_state(builder)
        for field in range(6):
            for bad in [1e100, -1e100]:
                var values: List[Float64] = [1, 2, 3, 0.25, 0.5, 0.75]
                values[field] = bad
                with assert_raises():
                    builder.add_signal_position_inertial_si(
                        SignalId("typed"),
                        values[0],
                        values[1],
                        values[2],
                        values[3],
                        values[4],
                        values[5],
                    )
                assert_equal(_builder_state(builder), before)
                with assert_raises():
                    builder.add_signal_position_inertial(
                        SignalId("typed"),
                        Length64(values[0]),
                        Length64(values[1]),
                        Length64(values[2]),
                        Angle64(values[3]),
                        Angle64(values[4]),
                        Angle64(values[5]),
                    )
                assert_equal(_builder_state(builder), before)


def test_negative_lane_section_stations_refuse_before_append() raises:
    var builder = _builder()
    var road = builder.roads[0].copy()
    var count = len(road.sections)
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = LaneSection(SectionId(1), Length64(bad))
        with assert_raises():
            _ = LaneSection.from_si(SectionId(1), bad)
        with assert_raises():
            _ = road.add_section(SectionId(1), Length64(bad))
        with assert_raises():
            _ = road.add_section_meters(SectionId(1), bad)
        assert_equal(len(road.sections), count)
        assert_equal(road.sections[0].s, 0)


def test_lane_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = Lane(LaneId(-1), SectionId(0), Length64(bad))
        with assert_raises():
            _ = Lane.from_si(LaneId(-1), SectionId(0), bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_distance = Lane(LaneId(-1), SectionId(0), Length64(bad))
    var raw_zero_distance = Lane.from_si(LaneId(-1), SectionId(0), bad)
    assert_equal(_word(zero_distance.distance), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_distance.distance), UInt64(0x8000000000000000))


def test_lane_section_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = LaneSection(SectionId(0), Length64(bad))
        with assert_raises():
            _ = LaneSection.from_si(SectionId(0), bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = LaneSection(SectionId(0), Length64(bad))
    var raw_zero_s = LaneSection.from_si(SectionId(0), bad)
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_waypoint_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(bad))
        with assert_raises():
            _ = Waypoint.from_si(RoadId(1), SectionId(0), LaneId(-1), bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(bad))
    var raw_zero_s = Waypoint.from_si(RoadId(1), SectionId(0), LaneId(-1), bad)
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_signal_nonnegative_domains() raises:
    var q = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(bad),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises():
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                bad,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                q,
                "typed",
                q,
                q,
                q,
                True,
            )
        with assert_raises():
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(bad),
                Length64(q),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises():
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                bad,
                q,
                "typed",
                q,
                q,
                q,
                True,
            )
        with assert_raises():
            _ = Signal(
                RoadId(1),
                SignalId("typed"),
                Length64(q),
                Length64(q),
                "typed",
                "typed",
                "none",
                Length64(q),
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                Length64(q),
                Length64(bad),
                "typed",
                Angle64(q),
                Angle64(q),
                Angle64(q),
                True,
            )
        with assert_raises():
            _ = Signal.from_si(
                RoadId(1),
                SignalId("typed"),
                q,
                q,
                "typed",
                "typed",
                "none",
                q,
                "typed",
                "solid",
                "typed",
                0.0,
                "m/s",
                q,
                bad,
                "typed",
                q,
                q,
                q,
                True,
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = Signal(
        RoadId(1),
        SignalId("typed"),
        Length64(bad),
        Length64(q),
        "typed",
        "typed",
        "none",
        Length64(q),
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        Length64(q),
        Length64(q),
        "typed",
        Angle64(q),
        Angle64(q),
        Angle64(q),
        True,
    )
    var raw_zero_s = Signal.from_si(
        RoadId(1),
        SignalId("typed"),
        bad,
        q,
        "typed",
        "typed",
        "none",
        q,
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        q,
        q,
        "typed",
        q,
        q,
        q,
        True,
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))
    var zero_height = Signal(
        RoadId(1),
        SignalId("typed"),
        Length64(q),
        Length64(q),
        "typed",
        "typed",
        "none",
        Length64(q),
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        Length64(bad),
        Length64(q),
        "typed",
        Angle64(q),
        Angle64(q),
        Angle64(q),
        True,
    )
    var raw_zero_height = Signal.from_si(
        RoadId(1),
        SignalId("typed"),
        q,
        q,
        "typed",
        "typed",
        "none",
        q,
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        bad,
        q,
        "typed",
        q,
        q,
        q,
        True,
    )
    assert_equal(_word(zero_height.height), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_height.height), UInt64(0x8000000000000000))
    var zero_width = Signal(
        RoadId(1),
        SignalId("typed"),
        Length64(q),
        Length64(q),
        "typed",
        "typed",
        "none",
        Length64(q),
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        Length64(q),
        Length64(bad),
        "typed",
        Angle64(q),
        Angle64(q),
        Angle64(q),
        True,
    )
    var raw_zero_width = Signal.from_si(
        RoadId(1),
        SignalId("typed"),
        q,
        q,
        "typed",
        "typed",
        "none",
        q,
        "typed",
        "solid",
        "typed",
        0.0,
        "m/s",
        q,
        bad,
        "typed",
        q,
        q,
        q,
        True,
    )
    assert_equal(_word(zero_width.width), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_width.width), UInt64(0x8000000000000000))


def test_signal_search_data_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = SignalSearchData(_reference(), _waypoint(), Length64(bad))
        with assert_raises():
            _ = SignalSearchData.from_si(_reference(), _waypoint(), bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_accumulated_s = SignalSearchData(
        _reference(), _waypoint(), Length64(bad)
    )
    var raw_zero_accumulated_s = SignalSearchData.from_si(
        _reference(), _waypoint(), bad
    )
    assert_equal(
        _word(zero_accumulated_s.accumulated_s), UInt64(0x8000000000000000)
    )
    assert_equal(
        _word(raw_zero_accumulated_s.accumulated_s), UInt64(0x8000000000000000)
    )


def test_landmark_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = Landmark(_waypoint(), _reference(), Length64(bad))
        with assert_raises():
            _ = Landmark.from_si(_waypoint(), _reference(), bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_distance = Landmark(_waypoint(), _reference(), Length64(bad))
    var raw_zero_distance = Landmark.from_si(_waypoint(), _reference(), bad)
    assert_equal(_word(zero_distance.distance), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_distance.distance), UInt64(0x8000000000000000))


def test_road_info_geometry_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoGeometry(
                Length64(bad),
                RoadGeometry(
                    LINE,
                    Length64(0),
                    Length64(0),
                    Length64(0),
                    Angle64(0),
                    Length64(10),
                ),
            )
        with assert_raises():
            _ = RoadInfoGeometry.from_si(
                bad,
                RoadGeometry(
                    LINE,
                    Length64(0),
                    Length64(0),
                    Length64(0),
                    Angle64(0),
                    Length64(10),
                ),
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoGeometry(
        Length64(bad),
        RoadGeometry(
            LINE,
            Length64(0),
            Length64(0),
            Length64(0),
            Angle64(0),
            Length64(10),
        ),
    )
    var raw_zero_s = RoadInfoGeometry.from_si(
        bad,
        RoadGeometry(
            LINE,
            Length64(0),
            Length64(0),
            Length64(0),
            Angle64(0),
            Length64(10),
        ),
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_elevation_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoElevation(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises():
            _ = RoadInfoElevation.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoElevation(
        Length64(bad), CubicPolynomial.constant(Length64(3.5))
    )
    var raw_zero_s = RoadInfoElevation.from_si(
        bad, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_lane_offset_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneOffset(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises():
            _ = RoadInfoLaneOffset.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneOffset(
        Length64(bad), CubicPolynomial.constant(Length64(3.5))
    )
    var raw_zero_s = RoadInfoLaneOffset.from_si(
        bad, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_lane_width_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneWidth(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises():
            _ = RoadInfoLaneWidth.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneWidth(
        Length64(bad), CubicPolynomial.constant(Length64(3.5))
    )
    var raw_zero_s = RoadInfoLaneWidth.from_si(
        bad, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_lane_border_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneBorder(
                Length64(bad), CubicPolynomial.constant(Length64(3.5))
            )
        with assert_raises():
            _ = RoadInfoLaneBorder.from_si(
                bad, CubicPolynomial.constant(Length64(3.5))
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneBorder(
        Length64(bad), CubicPolynomial.constant(Length64(3.5))
    )
    var raw_zero_s = RoadInfoLaneBorder.from_si(
        bad, CubicPolynomial.constant(Length64(3.5))
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_lane_height_nonnegative_domains() raises:
    var q = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneHeight(Length64(bad), Length64(q), Length64(q))
        with assert_raises():
            _ = RoadInfoLaneHeight.from_si(bad, q, q)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneHeight(Length64(bad), Length64(q), Length64(q))
    var raw_zero_s = RoadInfoLaneHeight.from_si(bad, q, q)
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_lane_material_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneMaterial(Length64(bad), "typed", 0.0, 0.0)
        with assert_raises():
            _ = RoadInfoLaneMaterial.from_si(bad, "typed", 0.0, 0.0)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneMaterial(Length64(bad), "typed", 0.0, 0.0)
    var raw_zero_s = RoadInfoLaneMaterial.from_si(bad, "typed", 0.0, 0.0)
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_lane_visibility_nonnegative_domains() raises:
    var q = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneVisibility(
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
            )
        with assert_raises():
            _ = RoadInfoLaneVisibility.from_si(bad, q, q, q, q)
        with assert_raises():
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(bad),
                Length64(q),
                Length64(q),
                Length64(q),
            )
        with assert_raises():
            _ = RoadInfoLaneVisibility.from_si(q, bad, q, q, q)
        with assert_raises():
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(q),
                Length64(bad),
                Length64(q),
                Length64(q),
            )
        with assert_raises():
            _ = RoadInfoLaneVisibility.from_si(q, q, bad, q, q)
        with assert_raises():
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
                Length64(q),
            )
        with assert_raises():
            _ = RoadInfoLaneVisibility.from_si(q, q, q, bad, q)
        with assert_raises():
            _ = RoadInfoLaneVisibility(
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(q),
                Length64(bad),
            )
        with assert_raises():
            _ = RoadInfoLaneVisibility.from_si(q, q, q, q, bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneVisibility(
        Length64(bad), Length64(q), Length64(q), Length64(q), Length64(q)
    )
    var raw_zero_s = RoadInfoLaneVisibility.from_si(bad, q, q, q, q)
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))
    var zero_forward = RoadInfoLaneVisibility(
        Length64(q), Length64(bad), Length64(q), Length64(q), Length64(q)
    )
    var raw_zero_forward = RoadInfoLaneVisibility.from_si(q, bad, q, q, q)
    assert_equal(_word(zero_forward.forward), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_forward.forward), UInt64(0x8000000000000000))
    var zero_back = RoadInfoLaneVisibility(
        Length64(q), Length64(q), Length64(bad), Length64(q), Length64(q)
    )
    var raw_zero_back = RoadInfoLaneVisibility.from_si(q, q, bad, q, q)
    assert_equal(_word(zero_back.back), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_back.back), UInt64(0x8000000000000000))
    var zero_left = RoadInfoLaneVisibility(
        Length64(q), Length64(q), Length64(q), Length64(bad), Length64(q)
    )
    var raw_zero_left = RoadInfoLaneVisibility.from_si(q, q, q, bad, q)
    assert_equal(_word(zero_left.left), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_left.left), UInt64(0x8000000000000000))
    var zero_right = RoadInfoLaneVisibility(
        Length64(q), Length64(q), Length64(q), Length64(q), Length64(bad)
    )
    var raw_zero_right = RoadInfoLaneVisibility.from_si(q, q, q, q, bad)
    assert_equal(_word(zero_right.right), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_right.right), UInt64(0x8000000000000000))


def test_road_info_lane_access_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneAccess(Length64(bad), "typed")
        with assert_raises():
            _ = RoadInfoLaneAccess.from_si(bad, "typed")
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneAccess(Length64(bad), "typed")
    var raw_zero_s = RoadInfoLaneAccess.from_si(bad, "typed")
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_lane_rule_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoLaneRule(Length64(bad), "typed")
        with assert_raises():
            _ = RoadInfoLaneRule.from_si(bad, "typed")
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoLaneRule(Length64(bad), "typed")
    var raw_zero_s = RoadInfoLaneRule.from_si(bad, "typed")
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_speed_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoSpeed(Length64(bad), Velocity64(5.0), "solid")
        with assert_raises():
            _ = RoadInfoSpeed.from_si(bad, 5.0, "solid", "m/s")
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoSpeed(Length64(bad), Velocity64(5.0), "solid")
    var raw_zero_s = RoadInfoSpeed.from_si(bad, 5.0, "solid", "m/s")
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_mark_type_line_nonnegative_domains() raises:
    var q = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoMarkTypeLine(
                Length64(bad),
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                "typed",
                Length64(q),
            )
        with assert_raises():
            _ = RoadInfoMarkTypeLine.from_si(bad, 0, q, q, q, "typed", q)
        with assert_raises():
            _ = RoadInfoMarkTypeLine(
                Length64(q),
                0,
                Length64(bad),
                Length64(q),
                Length64(q),
                "typed",
                Length64(q),
            )
        with assert_raises():
            _ = RoadInfoMarkTypeLine.from_si(q, 0, bad, q, q, "typed", q)
        with assert_raises():
            _ = RoadInfoMarkTypeLine(
                Length64(q),
                0,
                Length64(q),
                Length64(bad),
                Length64(q),
                "typed",
                Length64(q),
            )
        with assert_raises():
            _ = RoadInfoMarkTypeLine.from_si(q, 0, q, bad, q, "typed", q)
        with assert_raises():
            _ = RoadInfoMarkTypeLine(
                Length64(q),
                0,
                Length64(q),
                Length64(q),
                Length64(q),
                "typed",
                Length64(bad),
            )
        with assert_raises():
            _ = RoadInfoMarkTypeLine.from_si(q, 0, q, q, q, "typed", bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoMarkTypeLine(
        Length64(bad),
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        "typed",
        Length64(q),
    )
    var raw_zero_s = RoadInfoMarkTypeLine.from_si(bad, 0, q, q, q, "typed", q)
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))
    var zero_length = RoadInfoMarkTypeLine(
        Length64(q),
        0,
        Length64(bad),
        Length64(q),
        Length64(q),
        "typed",
        Length64(q),
    )
    var raw_zero_length = RoadInfoMarkTypeLine.from_si(
        q, 0, bad, q, q, "typed", q
    )
    assert_equal(_word(zero_length.length), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_length.length), UInt64(0x8000000000000000))
    var zero_space = RoadInfoMarkTypeLine(
        Length64(q),
        0,
        Length64(q),
        Length64(bad),
        Length64(q),
        "typed",
        Length64(q),
    )
    var raw_zero_space = RoadInfoMarkTypeLine.from_si(
        q, 0, q, bad, q, "typed", q
    )
    assert_equal(_word(zero_space.space), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_space.space), UInt64(0x8000000000000000))
    var zero_width = RoadInfoMarkTypeLine(
        Length64(q),
        0,
        Length64(q),
        Length64(q),
        Length64(q),
        "typed",
        Length64(bad),
    )
    var raw_zero_width = RoadInfoMarkTypeLine.from_si(
        q, 0, q, q, q, "typed", bad
    )
    assert_equal(_word(zero_width.width), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_width.width), UInt64(0x8000000000000000))


def test_road_info_mark_record_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoMarkRecord(Length64(bad), 0)
        with assert_raises():
            _ = RoadInfoMarkRecord.from_si(bad, 0)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoMarkRecord(Length64(bad), 0)
    var raw_zero_s = RoadInfoMarkRecord.from_si(bad, 0)
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_road_info_mark_record_full_nonnegative_domains() raises:
    var q = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoMarkRecord(
                Length64(bad),
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                Length64(q),
                MARK_CHANGE_BOTH,
                Length64(q),
                "typed",
                Length64(q),
                True,
            )
        with assert_raises():
            _ = RoadInfoMarkRecord.from_si(
                bad,
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                q,
                MARK_CHANGE_BOTH,
                q,
                "typed",
                q,
                True,
            )
        with assert_raises():
            _ = RoadInfoMarkRecord(
                Length64(q),
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                Length64(bad),
                MARK_CHANGE_BOTH,
                Length64(q),
                "typed",
                Length64(q),
                True,
            )
        with assert_raises():
            _ = RoadInfoMarkRecord.from_si(
                q,
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                bad,
                MARK_CHANGE_BOTH,
                q,
                "typed",
                q,
                True,
            )
        with assert_raises():
            _ = RoadInfoMarkRecord(
                Length64(q),
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                Length64(q),
                MARK_CHANGE_BOTH,
                Length64(q),
                "typed",
                Length64(bad),
                True,
            )
        with assert_raises():
            _ = RoadInfoMarkRecord.from_si(
                q,
                0,
                "solid",
                "typed",
                "typed",
                "typed",
                q,
                MARK_CHANGE_BOTH,
                q,
                "typed",
                bad,
                True,
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoMarkRecord(
        Length64(bad),
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        Length64(q),
        MARK_CHANGE_BOTH,
        Length64(q),
        "typed",
        Length64(q),
        True,
    )
    var raw_zero_s = RoadInfoMarkRecord.from_si(
        bad,
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        q,
        MARK_CHANGE_BOTH,
        q,
        "typed",
        q,
        True,
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))
    var zero_width = RoadInfoMarkRecord(
        Length64(q),
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        Length64(bad),
        MARK_CHANGE_BOTH,
        Length64(q),
        "typed",
        Length64(q),
        True,
    )
    var raw_zero_width = RoadInfoMarkRecord.from_si(
        q,
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        bad,
        MARK_CHANGE_BOTH,
        q,
        "typed",
        q,
        True,
    )
    assert_equal(_word(zero_width.width), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_width.width), UInt64(0x8000000000000000))
    var zero_type_width = RoadInfoMarkRecord(
        Length64(q),
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        Length64(q),
        MARK_CHANGE_BOTH,
        Length64(q),
        "typed",
        Length64(bad),
        True,
    )
    var raw_zero_type_width = RoadInfoMarkRecord.from_si(
        q,
        0,
        "solid",
        "typed",
        "typed",
        "typed",
        q,
        MARK_CHANGE_BOTH,
        q,
        "typed",
        bad,
        True,
    )
    assert_equal(_word(zero_type_width.type_width), UInt64(0x8000000000000000))
    assert_equal(
        _word(raw_zero_type_width.type_width), UInt64(0x8000000000000000)
    )


def test_road_info_crosswalk_nonnegative_domains() raises:
    var q = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoCrosswalk(
                Length64(bad),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises():
            _ = RoadInfoCrosswalk.from_si(
                bad,
                "typed",
                q,
                q,
                q,
                q,
                q,
                "none",
                q,
                q,
                List[CrosswalkPoint](),
            )
        with assert_raises():
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(bad),
                Length64(q),
                List[CrosswalkPoint](),
            )
        with assert_raises():
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                q,
                q,
                q,
                q,
                "none",
                bad,
                q,
                List[CrosswalkPoint](),
            )
        with assert_raises():
            _ = RoadInfoCrosswalk(
                Length64(q),
                "typed",
                Length64(q),
                Length64(q),
                Angle64(q),
                Angle64(q),
                Angle64(q),
                "none",
                Length64(q),
                Length64(bad),
                List[CrosswalkPoint](),
            )
        with assert_raises():
            _ = RoadInfoCrosswalk.from_si(
                q,
                "typed",
                q,
                q,
                q,
                q,
                q,
                "none",
                q,
                bad,
                List[CrosswalkPoint](),
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoCrosswalk(
        Length64(bad),
        "typed",
        Length64(q),
        Length64(q),
        Angle64(q),
        Angle64(q),
        Angle64(q),
        "none",
        Length64(q),
        Length64(q),
        List[CrosswalkPoint](),
    )
    var raw_zero_s = RoadInfoCrosswalk.from_si(
        bad, "typed", q, q, q, q, q, "none", q, q, List[CrosswalkPoint]()
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))
    var zero_width = RoadInfoCrosswalk(
        Length64(q),
        "typed",
        Length64(q),
        Length64(q),
        Angle64(q),
        Angle64(q),
        Angle64(q),
        "none",
        Length64(bad),
        Length64(q),
        List[CrosswalkPoint](),
    )
    var raw_zero_width = RoadInfoCrosswalk.from_si(
        q, "typed", q, q, q, q, q, "none", bad, q, List[CrosswalkPoint]()
    )
    assert_equal(_word(zero_width.width), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_width.width), UInt64(0x8000000000000000))
    var zero_length = RoadInfoCrosswalk(
        Length64(q),
        "typed",
        Length64(q),
        Length64(q),
        Angle64(q),
        Angle64(q),
        Angle64(q),
        "none",
        Length64(q),
        Length64(bad),
        List[CrosswalkPoint](),
    )
    var raw_zero_length = RoadInfoCrosswalk.from_si(
        q, "typed", q, q, q, q, q, "none", q, bad, List[CrosswalkPoint]()
    )
    assert_equal(_word(zero_length.length), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_length.length), UInt64(0x8000000000000000))


def test_road_info_signal_nonnegative_domains() raises:
    var q = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = RoadInfoSignal(
                SignalId("typed"),
                RoadId(1),
                Length64(bad),
                Length64(q),
                "none",
                List[LaneValidity](),
            )
        with assert_raises():
            _ = RoadInfoSignal.from_si(
                SignalId("typed"),
                RoadId(1),
                bad,
                q,
                "none",
                List[LaneValidity](),
            )
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_s = RoadInfoSignal(
        SignalId("typed"),
        RoadId(1),
        Length64(bad),
        Length64(q),
        "none",
        List[LaneValidity](),
    )
    var raw_zero_s = RoadInfoSignal.from_si(
        SignalId("typed"), RoadId(1), bad, q, "none", List[LaneValidity]()
    )
    assert_equal(_word(zero_s.s), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_s.s), UInt64(0x8000000000000000))


def test_lane_marking_nonnegative_domains() raises:
    _ = _precise()
    for bad in [-1.0, -bitcast[DType.float64](UInt64(1))]:
        with assert_raises():
            _ = LaneMarking(SOLID, MARKING_WHITE, CHANGE_BOTH, Length64(bad))
        with assert_raises():
            _ = LaneMarking.from_si(SOLID, MARKING_WHITE, CHANGE_BOTH, bad)
    # Zero, including its negative representation, is inside the domain.
    var bad = bitcast[DType.float64](UInt64(0x8000000000000000))
    var zero_width = LaneMarking(
        SOLID, MARKING_WHITE, CHANGE_BOTH, Length64(bad)
    )
    var raw_zero_width = LaneMarking.from_si(
        SOLID, MARKING_WHITE, CHANGE_BOTH, bad
    )
    assert_equal(_word(zero_width.width), UInt64(0x8000000000000000))
    assert_equal(_word(raw_zero_width.width), UInt64(0x8000000000000000))


def _road_info_polynomial_refused(polynomial: CubicPolynomial) raises:
    with assert_raises():
        _ = RoadInfoElevation(Length64(0), polynomial)
    with assert_raises():
        _ = RoadInfoElevation.from_si(0, polynomial)
    with assert_raises():
        _ = RoadInfoLaneOffset(Length64(0), polynomial)
    with assert_raises():
        _ = RoadInfoLaneOffset.from_si(0, polynomial)
    with assert_raises():
        _ = RoadInfoLaneWidth(Length64(0), polynomial)
    with assert_raises():
        _ = RoadInfoLaneWidth.from_si(0, polynomial)
    with assert_raises():
        _ = RoadInfoLaneBorder(Length64(0), polynomial)
    with assert_raises():
        _ = RoadInfoLaneBorder.from_si(0, polynomial)


def test_road_info_consumers_validate_mutated_nested_polynomials() raises:
    for bad in _bad_values():
        var polynomial = CubicPolynomial.from_coefficients(1, 2, 3, 4, 0)
        polynomial.a = bad
        _road_info_polynomial_refused(polynomial)
        polynomial = CubicPolynomial.from_coefficients(1, 2, 3, 4, 0)
        polynomial.b = bad
        _road_info_polynomial_refused(polynomial)
        polynomial = CubicPolynomial.from_coefficients(1, 2, 3, 4, 0)
        polynomial.c = bad
        _road_info_polynomial_refused(polynomial)
        polynomial = CubicPolynomial.from_coefficients(1, 2, 3, 4, 0)
        polynomial.d = bad
        _road_info_polynomial_refused(polynomial)
        polynomial = CubicPolynomial.from_coefficients(1, 2, 3, 4, 0)
        polynomial.s = bad
        _road_info_polynomial_refused(polynomial)


def _road_info_geometry_refused(base: RoadGeometry) raises:
    with assert_raises():
        _ = RoadInfoGeometry(Length64(0), base)
    with assert_raises():
        _ = RoadInfoGeometry.from_si(0, base)


def test_road_info_geometry_checks_mutable_common_record() raises:
    for bad in _bad_values():
        var base = RoadGeometry(
            LINE,
            Length64(0),
            Length64(1),
            Length64(2),
            Angle64(0),
            Length64(10),
        )
        base.s = bad
        _road_info_geometry_refused(base)
        base.s = 0
        base.x = bad
        _road_info_geometry_refused(base)
        base.x = 1
        base.y = bad
        _road_info_geometry_refused(base)
        base.y = 2
        base.heading = bad
        _road_info_geometry_refused(base)
        base.heading = 0
        base.length = bad
        _road_info_geometry_refused(base)
    var base = RoadGeometry(
        LINE, Length64(0), Length64(1), Length64(2), Angle64(0), Length64(10)
    )
    base.s = -1
    _road_info_geometry_refused(base)
    base.s = 0
    base.length = 0
    _road_info_geometry_refused(base)
    base.length = -1
    _road_info_geometry_refused(base)
    base.s = _max_finite64()
    base.length = _max_finite64()
    _road_info_geometry_refused(base)
    base.s = 0
    base.length = 10
    base.kind = RoadGeometryKind(99)
    _road_info_geometry_refused(base)


def test_crosswalk_and_lane_marking_validate_nested_mutable_fields() raises:
    for bad in _bad_values():
        for field in range(3):
            var point = CrosswalkPoint(Length64(1), Length64(2), Length64(3))
            if field == 0:
                point.u = bad
            elif field == 1:
                point.v = bad
            else:
                point.z = bad
            with assert_raises():
                _ = RoadInfoCrosswalk(
                    Length64(0),
                    "test",
                    Length64(0),
                    Length64(0),
                    Angle64(0),
                    Angle64(0),
                    Angle64(0),
                    "none",
                    Length64(2),
                    Length64(3),
                    [point],
                )
            with assert_raises():
                _ = RoadInfoCrosswalk.from_si(
                    0, "test", 0, 0, 0, 0, 0, "none", 2, 3, [point]
                )
    var invalid_widths = _bad_values()
    invalid_widths.append(-1)
    invalid_widths.append(-bitcast[DType.float64](UInt64(1)))
    for width in invalid_widths:
        var info = RoadInfoMarkRecord(Length64(0), 0)
        info.width = width
        with assert_raises():
            _ = LaneMarking(info)
        with assert_raises():
            _ = LaneMarking.from_si(info)
    var info = RoadInfoMarkRecord(Length64(0), 0)
    info.lane_change = MarkLaneChange(99)
    with assert_raises():
        _ = LaneMarking(info)
    with assert_raises():
        _ = LaneMarking.from_si(info)


def test_area_and_navigation_height_refuse_nonfinite_and_overflow_results() raises:
    var a = Vector3(_max_finite32(), 0, 0)
    var b = Vector3(-_max_finite32(), 0, 0)
    with assert_raises():
        _ = distance_squared_2d(a, b)
    with assert_raises():
        _ = distance_squared_2d_si(a, b)
    for bad64 in _bad_values():
        var bad = Float32(bad64)
        var polygon = NavPolygon(
            [Vector3(0, 0, 3), Vector3(4, 0, 3), Vector3(0, 4, 3)],
            AREA_SIDEWALK,
        )
        for point in [
            Vector3(bad, 1, 0),
            Vector3(1, bad, 0),
            Vector3(1, 1, bad),
        ]:
            with assert_raises():
                _ = polygon.height_at(point)
            with assert_raises():
                _ = polygon.height_at_si(point)
        for vertex in [
            Vector3(bad, 0, 3),
            Vector3(0, bad, 3),
            Vector3(0, 0, bad),
        ]:
            polygon.vertices[0] = vertex
            with assert_raises():
                _ = polygon.height_at(Vector3(1, 1, 0))
            with assert_raises():
                _ = polygon.height_at_si(Vector3(1, 1, 0))
    var polygon = NavPolygon(
        [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)], AREA_SIDEWALK
    )
    polygon.vertices[0] = Vector3(0, 0, _max_finite32())
    polygon.vertices[1] = Vector3(1, 0, -_max_finite32())
    with assert_raises():
        _ = polygon.height_at(Vector3(4, 0, 0))
    with assert_raises():
        _ = polygon.height_at_si(Vector3(4, 0, 0))
    polygon.vertices.clear()
    with assert_raises():
        _ = polygon.height_at(Vector3(0, 0, 0))
    with assert_raises():
        _ = polygon.height_at_si(Vector3(0, 0, 0))


def test_mesh_sampling_refuses_unrepresentable_station_progress() raises:
    var builder = _builder()
    var road = builder.roads[0].copy()
    # Force the curved _stations route as well as the always-sampled rows route.
    road.sections[0].lanes[0].info.widths[0].polynomial.c = 1
    var factory = MeshFactory()
    var start = Float64(1e20)
    var end = bitcast[DType.float64](_word(start) + UInt64(1))
    assert_true(end > start)
    assert_equal(start + 2, start)
    with assert_raises():
        _ = factory.generate_lane(road, 0, 0, Length64(start), Length64(end))
    with assert_raises():
        _ = factory.generate_lane_si(road, 0, 0, start, end)
    with assert_raises():
        _ = factory.generate_tesselated(
            road, 0, 0, Length64(start), Length64(end)
        )
    with assert_raises():
        _ = factory.generate_tesselated_si(road, 0, 0, start, end)
    var invalid = _bad_values()
    invalid.append(0)
    invalid.append(-1)
    for bad in invalid:
        factory.road_param.resolution = Length(Float32(bad))
        with assert_raises():
            _ = factory.generate_lane(road, 0, 0, Length64(0), Length64(4))
        with assert_raises():
            _ = factory.generate_tesselated_si(road, 0, 0, 0, 4)
    factory.road_param.resolution = Length(2)
    for bad in [inf[DType.float32](), nan[DType.float32](), _max_finite32()]:
        factory.road_param.vertex_width_resolution = bad
        with assert_raises():
            _ = factory.generate_tesselated(
                road, 0, 0, Length64(0), Length64(4)
            )


def test_lane_width_offsets_and_elevation_check_narrowed_results() raises:
    var builder = _builder()
    var map = builder.build()
    map.roads[0].sections[0].lanes[0].info.widths[0].polynomial.a = 1e100
    assert_equal(map.lane_width(_waypoint()).value, Float64(1e100))
    assert_equal(map.lane_width_meters(_waypoint()), Float64(1e100))
    with assert_raises():
        _ = map.lane_width_float32(_waypoint())
    with assert_raises():
        _ = map.roads[0].lane_edge_offsets(0, 0, Length64(0))
    with assert_raises():
        _ = map.roads[0].lane_edge_offsets_meters(0, 0, 0)
    map.roads[0].sections[0].lanes[0].info.widths[0].polynomial.a = 3.5
    map.roads[0].info.lane_offsets[0].polynomial.a = 1e100
    with assert_raises():
        _ = map.roads[0].directed_point(Length64(1))
    with assert_raises():
        _ = map.roads[0].directed_point_meters(1)
    map.roads[0].info.lane_offsets[0].polynomial.a = 0
    map.roads[0].info.elevations[0].polynomial.a = 1e100
    with assert_raises():
        _ = map.roads[0].directed_point(Length64(1))
    with assert_raises():
        _ = map.roads[0].directed_point_meters(1)
    with assert_raises():
        _ = map.roads[0].directed_point_no_lane_offset(Length64(1))
    with assert_raises():
        _ = map.roads[0].directed_point_no_lane_offset_meters(1)
    # The local value cancels exactly, while the derivative overflows.
    map.roads[0].info.elevations[
        0
    ].polynomial = CubicPolynomial.from_coefficients(
        -_max_finite64(), 0, _max_finite64(), 0, 0
    )
    with assert_raises():
        _ = map.roads[0].directed_point(Length64(1))
    with assert_raises():
        _ = map.roads[0].directed_point_no_lane_offset_meters(1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def test_degenerate_mutated_navigation_polygon_refuses_height() raises:
    var polygon = NavPolygon(
        [Vector3(0, 0, 3), Vector3(4, 0, 3), Vector3(0, 4, 3)], AREA_SIDEWALK
    )
    polygon.vertices[2] = Vector3(2, 0, 3)
    with assert_raises():
        _ = polygon.height_at(Vector3(1, 0, 0))
    with assert_raises():
        _ = polygon.height_at_si(Vector3(1, 0, 0))


def test_geometry_mutable_station_length_views_enforce_domains() raises:
    var geometry = RoadGeometry(
        LINE, Length64(0), Length64(0), Length64(0), Angle64(0), Length64(10)
    )
    geometry.s = -1
    with assert_raises():
        _ = geometry.s_quantity()
    with assert_raises():
        _ = geometry.end_s_meters()
    geometry.s = 0
    for length in [Float64(0), Float64(-1)]:
        geometry.length = length
        with assert_raises():
            _ = geometry.length_quantity()
        with assert_raises():
            _ = geometry.end_s()


def test_nearest_point_revalidates_mutable_geometry_records() raises:
    var builder = _builder()
    var road = builder.roads[0].copy()
    road.info.geometries[0].geometry.kind = RoadGeometryKind(99)
    with assert_raises():
        _ = road.nearest_point(Vector3(0, 0, 0))
    with assert_raises():
        _ = road.nearest_point_meters(Vector3(0, 0, 0))
    road.info.geometries[0].geometry.kind = LINE
    road.info.geometries[0].s = -1
    with assert_raises():
        _ = road.nearest_point(Vector3(0, 0, 0))


def test_geometry_endpoint_overflow_refuses_before_builder_append() raises:
    with assert_raises():
        _ = RoadGeometry.from_meters(LINE, 1e308, 0, 0, 0, 1e308)
    var builder = _builder()
    var before = _builder_state(builder)
    with assert_raises():
        builder.add_road_geometry_line_si(0, 1e308, 0, 0, 0, 1e308)
    assert_equal(_builder_state(builder), before)
