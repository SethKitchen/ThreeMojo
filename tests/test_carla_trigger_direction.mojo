# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Trigger offsets follow lane travel, not lane sign (issue #486).

The independent reference is a straight, level OpenDRIVE road: x = s,
y = -1.75 * lane, and upstream is minus the travel direction. Lane 1
travels with s under LHT; lane -1 travels with s under RHT. Explicit
expected positions cover both sides of the section boundary at s = 60.
The world tests drive the actual cached trigger boxes through tick.
"""

from extensions.carla.actor import ActorId, GREEN, RED
from extensions.carla.map import Map
from extensions.carla.opendrive import load_opendrive
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.road_info import LaneId, RoadId, SignalId
from extensions.carla.traffic_sign import (
    TriggerBox,
    _shifted,
    give_way_boxes,
    speed_limit_boxes,
    traffic_light_boxes,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import EpisodeSettings, World
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length


def _section(s: Int) -> String:
    return (
        '<laneSection s="'
        + String(s)
        + '"><left><lane id="1" type="driving">'
        + '<link><predecessor id="1"/><successor id="1"/></link>'
        + '<width sOffset="0" a="3.5" b="0" c="0" d="0"/>'
        + '</lane></left><center><lane id="0" type="none"/></center>'
        + '<right><lane id="-1" type="driving">'
        + '<link><predecessor id="-1"/><successor id="-1"/></link>'
        + '<width sOffset="0" a="3.5" b="0" c="0" d="0"/>'
        + '</lane></right></laneSection>'
    )


def _signal(lane: Int, s: Int, type: String) -> String:
    return (
        '<signals><signal s="'
        + String(s)
        + '" t="-5" id="10" name="test" dynamic="yes" orientation="+" '
        + 'zOffset="2" country="OpenDRIVE" type="'
        + type
        + '" subtype="60" value="60" unit="km/h">'
        + '<validity fromLane="'
        + String(lane)
        + '" toLane="'
        + String(lane)
        + '"/></signal></signals>'
    )


def _road_map(
    rule: String, lane: Int, s: Int, type: String = "1000001"
) raises -> Map:
    return load_opendrive(
        '<OpenDRIVE><header revMajor="1" revMinor="4"/>'
        + '<road name="straight" length="120" id="1" junction="-1" rule="'
        + rule
        + '"><planView><geometry s="0" x="0" y="0" hdg="0" length="120">'
        + '<line/></geometry></planView><lanes>'
        + _section(0)
        + _section(60)
        + '</lanes>'
        + _signal(lane, s, type)
        + '</road></OpenDRIVE>'
    )


def _box_at(box: TriggerBox, lane: Int, x: Float64, forward: Float32) raises:
    assert_almost_equal(box.transform.location.x, Float32(x), atol=1e-4)
    assert_almost_equal(
        box.transform.location.y, -1.75 * Float32(lane), atol=1e-4
    )
    assert_almost_equal(box.transform.location.z, 0, atol=1e-4)
    assert_almost_equal(
        box.transform.rotation.forward_vector().x, forward, atol=1e-4
    )


def _offset_cases(rule: String, lane: Int, with_s: Bool) raises:
    # These numbers do not call the implementation to derive direction.
    var positions: List[Int] = [1, 50, 59, 60, 61, 90, 119]
    var against_positive: List[Float64] = [
        0.00001, 47, 56, 60.00001, 60.00001, 87, 116
    ]
    var against_negative: List[Float64] = [
        4, 53, 59.99999, 63, 64, 93, 119.99999
    ]
    for i in range(len(positions)):
        var s = positions[i]
        var map = _road_map(rule, lane, s)
        var w = map.waypoint_xodr(
            RoadId(1), LaneId(lane), Length(Float32(s), METER)
        ).value()
        assert_equal(map.is_positive_direction(w), with_s)
        var want = against_positive[i] if with_s else against_negative[i]
        var shifted = _shifted(map, w, 3.0)
        assert_almost_equal(shifted.s, want, atol=1e-10)
        assert_equal(shifted.road_id, w.road_id)
        assert_equal(shifted.section_id, w.section_id)
        assert_equal(shifted.lane_id, w.lane_id)
        var forward = Float32(1) if with_s else Float32(-1)
        var lights = traffic_light_boxes(map, SignalId("10"))
        var signs = give_way_boxes(map, SignalId("10"))
        assert_equal(len(lights), 1)
        assert_equal(len(signs.effect), 1)
        _box_at(lights[0], lane, want, forward)
        _box_at(signs.effect[0], lane, want, forward)
        var low = Float64(0.00001) if s < 60 else Float64(60.00001)
        var high = Float64(59.99999) if s < 60 else Float64(119.99999)
        var limit_x = Float64(s) - 1.225 if with_s else Float64(s) + 1.225
        var limits = speed_limit_boxes(map, SignalId("10"))
        assert_equal(len(limits), 1)
        _box_at(limits[0], lane, min(max(limit_x, low), high), forward)


def test_rht_negative_lane_offsets_and_section_clamps() raises:
    _offset_cases("RHT", -1, True)


def test_rht_positive_lane_offsets_and_section_clamps() raises:
    _offset_cases("RHT", 1, False)


def test_lht_positive_lane_offsets_and_section_clamps() raises:
    _offset_cases("LHT", 1, True)


def test_lht_negative_lane_offsets_and_section_clamps() raises:
    _offset_cases("LHT", -1, False)


def _pose(s: Float32, lane: Int, with_s: Bool) -> CarlaTransform:
    var yaw = Float32(0) if with_s else Float32(180)
    return CarlaTransform(
        Length(s, METER),
        Length(-1.75 * Float32(lane), METER),
        Length(0.05, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)),
    )


def _world_entries(rule: String, lane: Int, with_s: Bool) raises:
    var types: List[String] = ["1000001", "206", "205", "274"]
    for kind in range(len(types)):
        var world = World(_road_map(rule, lane, 50, types[kind]))
        var settings = EpisodeSettings()
        settings.fixed_delta_seconds = Duration(0.05, SECOND)
        _ = world.apply_settings(settings)
        var distance = Float32(1.225) if kind == 3 else Float32(3)
        var x = 50 - distance if with_s else 50 + distance
        var forward = Float32(1) if with_s else Float32(-1)
        if kind == 0:
            assert_equal(len(world.traffic_lights.lights), 1)
            _box_at(world.traffic_lights.lights[0].boxes[0], lane, Float64(x), forward)
            world.freeze_all_traffic_lights(True)
            world.set_traffic_light_state(ActorId(2), RED)
        else:
            assert_equal(len(world.signs), 1)
            _box_at(world.signs[0].effect_boxes[0], lane, Float64(x), forward)
        var blueprint = world.blueprints.at("vehicle.lincoln.mkz")
        var car = world.spawn_actor(
            blueprint,
            _pose(x - 10 * forward, lane, with_s),
        )
        _ = world.tick()
        if kind == 0:
            assert_false(world.is_at_traffic_light(car))
        elif kind != 3:
            assert_equal(len(world.signs[0].vehicles_in_effect), 0)
        else:
            assert_almost_equal(
                world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 30, atol=1e-4
            )
        world.set_transform(car, _pose(x, lane, with_s))
        _ = world.tick()
        if kind == 0:
            assert_true(world.is_at_traffic_light(car))
            assert_equal(world.get_traffic_light(car).value(), ActorId(2))
            assert_equal(world.get_traffic_light_state(car).value, RED.value)
            assert_equal(len(world.traffic_lights.lights[0].vehicles), 1)
        elif kind != 3:
            assert_equal(len(world.signs[0].vehicles_in_effect), 1)
            assert_equal(world.signs[0].vehicles_in_effect[0], car)
            var state = RED if kind == 1 else GREEN
            assert_equal(world.get_traffic_light_state(car).value, state.value)
        else:
            assert_almost_equal(
                world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 60, atol=1e-4
            )
        world.set_transform(car, _pose(x + 10 * forward, lane, with_s))
        _ = world.tick()
        if kind == 0:
            assert_false(world.is_at_traffic_light(car))
            assert_false(Bool(world.get_traffic_light(car)))
            assert_equal(world.get_traffic_light_state(car).value, GREEN.value)
            assert_equal(len(world.traffic_lights.lights[0].vehicles), 0)
        elif kind != 3:
            assert_equal(len(world.signs[0].vehicles_in_effect), 0)
        else:
            assert_almost_equal(
                world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 60, atol=1e-4
            )


def test_world_rht_negative_lane_entry_and_exit() raises:
    _world_entries("RHT", -1, True)


def test_world_rht_positive_lane_entry_and_exit() raises:
    _world_entries("RHT", 1, False)


def test_world_lht_positive_lane_entry_and_exit() raises:
    _world_entries("LHT", 1, True)


def test_world_lht_negative_lane_entry_and_exit() raises:
    _world_entries("LHT", -1, False)


def test_junction_offset_uses_resolved_predecessor_lane() raises:
    # LHT lane 1 receives traffic from RHT lane -1. The trigger belongs
    # to that predecessor, at its end minus 3 m: x = 57, not x = 60.
    var map = load_opendrive(
        '<OpenDRIVE><header revMajor="1" revMinor="4"/>'
        + '<road id="1" length="60" junction="-1" rule="RHT">'
        + '<link><successor elementType="road" elementId="2" contactPoint="start"/></link>'
        + '<planView><geometry s="0" x="0" y="0" hdg="0" length="60">'
        + '<line/></geometry></planView><lanes>'
        + '<laneSection s="0"><center><lane id="0" type="none"/></center>'
        + '<right><lane id="-1" type="driving"><link><successor id="1"/></link>'
        + '<width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>'
        + '</right></laneSection></lanes></road>'
        + '<road id="2" length="20" junction="100" rule="LHT">'
        + '<link><predecessor elementType="road" elementId="1" contactPoint="end"/></link>'
        + '<planView><geometry s="0" x="60" y="-3.5" hdg="0" length="20">'
        + '<line/></geometry></planView><lanes><laneSection s="0"><left>'
        + '<lane id="1" type="driving"><link><predecessor id="-1"/></link>'
        + '<width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>'
        + '</left><center><lane id="0" type="none"/></center></laneSection></lanes>'
        + _signal(1, 5, "206")
        + '</road><junction id="100" name="test"/></OpenDRIVE>'
    )
    var w = map.waypoint_xodr(RoadId(2), LaneId(1), Length(5, METER)).value()
    var before = map.predecessors(w)
    assert_equal(len(before), 1)
    assert_equal(before[0].road_id, RoadId(1))
    assert_equal(before[0].lane_id, LaneId(-1))
    var lights = traffic_light_boxes(map, SignalId("10"))
    var signs = give_way_boxes(map, SignalId("10"))
    assert_equal(len(lights), 1)
    assert_equal(len(signs.effect), 1)
    _box_at(lights[0], -1, 57, 1)
    _box_at(signs.effect[0], -1, 57, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
