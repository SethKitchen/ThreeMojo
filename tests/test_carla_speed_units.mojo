# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""OpenDRIVE speed units, source payloads and distinct nonnumeric states."""

from extensions.carla.map import Waypoint
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road_info import (
    RoadInfoSpeed,
    RoadId,
    LaneId,
    SectionId,
    SignalId,
)
from extensions.carla.speed_limits import (
    SpeedLimitKind,
    NUMERIC_SPEED_LIMIT,
    NO_SPEED_LIMIT,
    UNDEFINED_SPEED_LIMIT,
    UNSPECIFIED_SPEED_LIMIT,
    opendrive_speed,
    simulation_speed,
    read_speed_number,
)
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from units.si import Velocity64


def speed_town(
    road_speed: String, lane_speed: String = "", signal: String = ""
) -> String:
    """Build a fixed small road with only its speed metadata varied.

    Args:
        road_speed: A complete road speed element, or empty.
        lane_speed: A complete lane speed element, or empty.
        signal: A complete signal element, or empty.

    Returns:
        OpenDRIVE with unchanged geometry and lane identities.
    """
    return (
        "<OpenDRIVE><road id='1' length='40' junction='-1'><type s='0' type='town'>"
        + road_speed
        + "</type><planView><geometry s='0' x='0' y='0' hdg='0' length='40'><line/></geometry></planView>"
        + "<lanes><laneSection s='0'><center><lane id='0' type='none'/></center><right><lane id='-1' type='driving'>"
        + "<width sOffset='0' a='3.5' b='0' c='0' d='0'/>"
        + lane_speed
        + "</lane></right></laneSection></lanes><signals>"
        + signal
        + "</signals></road></OpenDRIVE>"
    )


def speed_signal(value: String, unit: String) -> String:
    """Return speed-sign XML with stable placement and model subtype.

    Args:
        value: The value attribute text, or empty to omit it.
        unit: The complete unit attribute, or empty to omit it.

    Returns:
        One recognized speed signal at station 20.
    """
    var attribute = " value='" + value + "'" if value != "" else ""
    return (
        "<signal id='7' s='20' t='-5' type='274' subtype='40' name='limit' orientation='+' zOffset='2'"
        + attribute
        + unit
        + "><validity fromLane='-1' toLane='-1'/></signal>"
    )


def test_speed_equivalent_units_and_float64_precision() raises:
    # 45 international mph = 72.42048 km/h = 20.1168 m/s, exactly in decimals.
    var mph = opendrive_speed(45, "mph")
    var kmh = opendrive_speed(72.42048, "km/h")
    var si = opendrive_speed(20.1168, "m/s")
    assert_almost_equal(mph.value, Float64(20.1168), atol=1e-12)
    assert_almost_equal(kmh.value, si.value, atol=1e-12)
    assert_equal(simulation_speed(mph).value, simulation_speed(si).value)
    assert_equal(simulation_speed(kmh).value, simulation_speed(si).value)
    var precise = bitcast[DType.float64](UInt64(0x3FF0000000000001))
    assert_equal(
        bitcast[DType.uint64](opendrive_speed(precise, "m/s").value),
        UInt64(0x3FF0000000000001),
    )
    assert_equal(opendrive_speed(10, "", True).value, Float64(10))


def test_speed_domains_and_checked_simulation_narrowing() raises:
    for bad in [Float64(-1), nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises(contains="finite and nonnegative"):
            _ = opendrive_speed(bad, "m/s")
        with assert_raises(contains="finite and nonnegative"):
            _ = simulation_speed(Velocity64(bad))
    for unit in ["", "kmh", "MPH", "miles/h", "m"]:
        with assert_raises(contains="supported unit"):
            _ = opendrive_speed(1, unit)
    for bad in [Float64(1e-100), Float64(1e100)]:
        with assert_raises(contains="Float32 range"):
            _ = simulation_speed(Velocity64(bad))
    with assert_raises(contains="Float64 range"):
        _ = opendrive_speed(bitcast[DType.float64](UInt64(1)), "km/h")
    assert_equal(simulation_speed(Velocity64(0)).value, Float32(0))
    assert_equal(read_speed_number(" 1.25e1 "), Float64(12.5))
    for bad in [
        "",
        "no limit",
        "undefined",
        "-1",
        "nan",
        "inf",
        "12x",
        "1e-1000",
    ]:
        with assert_raises(contains="OpenDRIVE speed"):
            _ = read_speed_number(bad)


def test_road_states_keep_zero_no_limit_undefined_and_missing_distinct() raises:
    var zero = RoadInfoSpeed.from_opendrive(0, "0.000", "Town", "", True)
    assert_equal(zero.kind, NUMERIC_SPEED_LIMIT)
    assert_true(Bool(zero.limit()))
    assert_equal(zero.limit().value().value, Float64(0))
    assert_equal(zero.max_text, "0.000")
    var unlimited = RoadInfoSpeed.from_opendrive(
        0, "no limit", "Town", "mph", True
    )
    var undefined = RoadInfoSpeed.from_opendrive(
        0, "undefined", "Town", "", True
    )
    var absent = RoadInfoSpeed.from_opendrive(0, "", "Town", "", True)
    assert_equal(unlimited.kind, NO_SPEED_LIMIT)
    assert_equal(undefined.kind, UNDEFINED_SPEED_LIMIT)
    assert_equal(absent.kind, UNSPECIFIED_SPEED_LIMIT)
    assert_false(Bool(unlimited.limit()))
    assert_false(Bool(undefined.limit()))
    assert_false(Bool(absent.limit()))
    assert_equal(unlimited.max_text, "no limit")
    assert_equal(unlimited.unit, "mph")
    zero.kind = SpeedLimitKind(99)
    with assert_raises(contains="kind"):
        _ = zero.limit()
    zero.kind = NUMERIC_SPEED_LIMIT
    zero.speed = nan[DType.float64]()
    with assert_raises(contains="finite"):
        _ = zero.limit()


def test_parser_preserves_units_and_lane_over_road_precedence() raises:
    var map = load_opendrive(
        speed_town(
            "<speed max='72.42048' unit='km/h'/>",
            "<speed sOffset='0' max='45' unit='mph'/>",
        )
    )
    ref road = map.road(RoadId(1))
    assert_equal(road.info.speeds[0].speed, Float64(72.42048))
    assert_equal(road.info.speeds[0].unit, "km/h")
    assert_equal(road.info.speeds[0].max_text, "72.42048")
    var waypoint = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 10)
    assert_almost_equal(
        map.speed_limit_at(waypoint).value().value, Float64(20.1168), atol=1e-12
    )
    var fallback = load_opendrive(speed_town("<speed max='12.5'/>"))
    assert_equal(fallback.speed_limit_at(waypoint).value().value, Float64(12.5))
    var lane_default = load_opendrive(
        speed_town(
            "<speed max='90' unit='km/h'/>", "<speed sOffset='0' max='7.5'/>"
        )
    )
    assert_equal(
        lane_default.speed_limit_at(waypoint).value().value, Float64(7.5)
    )
    var stopped = load_opendrive(
        speed_town(
            "<speed max='90' unit='km/h'/>", "<speed sOffset='0' max='0'/>"
        )
    )
    assert_true(Bool(stopped.speed_limit_at(waypoint)))
    assert_equal(stopped.speed_limit_at(waypoint).value().value, Float64(0))


def test_parser_road_keywords_and_invalid_lane_values() raises:
    for token in ["no limit", "undefined"]:
        var map = load_opendrive(speed_town("<speed max='" + token + "'/>"))
        assert_false(Bool(map.roads[0].info.speeds[0].limit()))
        assert_equal(map.roads[0].info.speeds[0].max_text, token)
        with assert_raises(contains="numeric max"):
            _ = load_opendrive(
                speed_town("", "<speed sOffset='0' max='" + token + "'/>")
            )
    var map = load_opendrive(speed_town(""))
    assert_equal(map.roads[0].info.speeds[0].kind, UNSPECIFIED_SPEED_LIMIT)
    for xml in [
        "<speed/>",
        "<speed max='12x'/>",
        "<speed max='-1'/>",
        "<speed max='inf'/>",
        "<speed max='1' unit='kmh'/>",
        "<speed max='1' unit=''/>",
    ]:
        with assert_raises(contains="OpenDRIVE"):
            _ = load_opendrive(speed_town(xml))
    with assert_raises(contains="cannot be empty"):
        _ = load_opendrive(
            speed_town("", "<speed sOffset='0' max='1' unit=''/>")
        )


def test_signal_payload_is_separate_from_validated_speed_access() raises:
    var map = load_opendrive(
        speed_town("", "", speed_signal("45", " unit='mph'"))
    )
    ref signal = map.signal(SignalId("7"))
    assert_equal(signal.value, Float64(45))
    assert_equal(signal.unit, "mph")
    assert_almost_equal(
        signal.speed_limit().value, Float64(20.1168), atol=1e-12
    )
    var missing_unit = load_opendrive(
        speed_town("", "", speed_signal("45", ""))
    )
    assert_equal(missing_unit.signals[0].value, Float64(45))
    with assert_raises(contains="supported unit"):
        _ = missing_unit.signals[0].speed_limit()
    var missing_value = load_opendrive(
        speed_town("", "", speed_signal("", " unit='km/h'"))
    )
    assert_false(missing_value.signals[0].value_present)
    with assert_raises(contains="numeric value"):
        _ = missing_value.signals[0].speed_limit()
    var unrelated = load_opendrive(
        speed_town(
            "",
            "",
            "<signal id='7' s='20' t='-5' type='1000001' value='-1' unit=''/>",
        )
    )
    assert_equal(unrelated.signals[0].value, Float64(-1))
    assert_equal(unrelated.signals[0].unit, "")
    with assert_raises(contains="Only a speed signal"):
        _ = unrelated.signals[0].speed_limit()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
