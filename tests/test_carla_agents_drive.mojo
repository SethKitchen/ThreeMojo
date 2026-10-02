# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA agents in a world: routes driven, hazards seen, behavior types.

The worlds stand on `assets/carla/town.xodr` and on a straight two-lane
road of 100 m. The cars are CARLA's `vehicle.lincoln.mkz`, 4.8 m long
and 2 m wide in this port. The expected numbers come from outside:

- Hand math for the detection ranges, the speed caps of the behavior
  types and the times to collision.
- CARLA's Python `basic_agent.py`, run against a mock `carla` module
  with the two-lane road worked out by hand, for the lane-change plans.
- Physics gives the rest only as bounds: a car that stops, stops before
  the light or the car ahead, and keeps its lane.
"""

from extensions.carla.actor import ActorId, GREEN, RED, YELLOW
from extensions.carla.agents import (
    BasicAgent,
    BasicAgentOptions,
    point_in_polygon,
    polygons_intersect,
)
from extensions.carla.agents_behavior import (
    BehaviorAgent,
    ConstantVelocityAgent,
)
from extensions.carla.agents_local_planner import PlanItem, plan_item
from extensions.carla.agents_misc import (
    AGGRESSIVE,
    BehaviorType,
    CAUTIOUS,
    NORMAL,
    OPTION_CHANGE_LANE_LEFT,
    OPTION_CHANGE_LANE_RIGHT,
    OPTION_LANE_FOLLOW,
    OPTION_LEFT,
    OPTION_RIGHT,
    OPTION_STRAIGHT,
    RoadOption,
    from_kmh,
    kmh,
    speed_of,
)
from extensions.carla.agents_route import GlobalRoutePlanner
from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.road_info import LaneId, RoadId, SectionId
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from std.math import floor
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length, Velocity

# The two-lane road of `test_carla_agents.mojo`. `{CHANGE}` is lane -1's
# outer mark: "both" lets a car cross either way; "decrease" only from
# lane -2 to the left. `{CENTER}` is the center line's.
comptime TWO_LANE = """<?xml version="1.0"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="two lanes"/>
  <road name="a" length="50" id="1" junction="-1">
    <link><successor elementType="road" elementId="2" contactPoint="start"/></link>
    <planView><geometry s="0" x="0" y="0" hdg="0" length="50"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"><roadMark sOffset="0" type="solid" color="yellow" width="0.15" laneChange="{CENTER}"/></lane></center>
      <right>
        <lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="{CHANGE}"/></lane>
        <lane id="-2" type="driving"><link><successor id="-2"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" color="white" width="0.15" laneChange="none"/></lane>
        <lane id="-3" type="sidewalk"><link><successor id="-3"/></link><width sOffset="0" a="2" b="0" c="0" d="0"/></lane>
      </right>
    </laneSection></lanes>
  </road>
  <road name="b" length="50" id="2" junction="-1">
    <link><predecessor elementType="road" elementId="1" contactPoint="end"/></link>
    <planView><geometry s="0" x="50" y="0" hdg="0" length="50"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"><roadMark sOffset="0" type="solid" color="yellow" width="0.15" laneChange="{CENTER}"/></lane></center>
      <right>
        <lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="{CHANGE}"/></lane>
        <lane id="-2" type="driving"><link><predecessor id="-2"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" color="white" width="0.15" laneChange="none"/></lane>
        <lane id="-3" type="sidewalk"><link><predecessor id="-3"/></link><width sOffset="0" a="2" b="0" c="0" d="0"/></lane>
      </right>
    </laneSection></lanes>
  </road>
</OpenDRIVE>
"""


def _two_lane(change: String = "both", center: String = "none") raises -> Map:
    return load_opendrive(
        String(TWO_LANE).replace("{CHANGE}", change).replace("{CENTER}", center)
    )


def _world(var map: Map) raises -> World:
    var world = World(map^)
    var settings = EpisodeSettings()
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    return world^


def _town() raises -> World:
    return _world(load_opendrive_file("assets/carla/town.xodr"))


def _pose(x: Float32, y: Float32, z: Float32, yaw: Float32) -> CarlaTransform:
    return CarlaTransform(
        Length(x, METER),
        Length(y, METER),
        Length(z, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)),
    )


def _car(
    mut world: World, x: Float32, y: Float32, yaw: Float32 = 0
) raises -> ActorId:
    var bp = world.blueprints.at("vehicle.lincoln.mkz")
    return world.spawn_actor(bp, _pose(x, y, 0.3, yaw))


def _walker(mut world: World, x: Float32, y: Float32) raises -> ActorId:
    var bp = world.blueprints.at("walker.pedestrian.0020")
    return world.spawn_actor(bp, _pose(x, y, 1.0, 0))


def _speed(world: World, car: ActorId) raises -> Float64:
    return kmh(speed_of(world.get_velocity(car)))


def _s(s: Float64) -> String:
    var r = floor(s * 1000.0 + 0.5) / 1000.0
    if r == floor(r):
        return String(Int(r))
    return String(r)


def _short(plan: List[PlanItem]) -> String:
    var out = String()
    for i in range(len(plan)):
        if i > 0:
            out += ";"
        ref w = plan[i].waypoint
        out += String(
            w.road_id.value,
            ",",
            w.lane_id.value,
            ",",
            _s(w.s),
            ",",
            plan[i].road_option.value,
        )
    return out


def _ids(a: ActorId) -> List[ActorId]:
    var out = List[ActorId]()
    out.append(a)
    return out^


def _ids(a: ActorId, b: ActorId) -> List[ActorId]:
    var out = _ids(a)
    out.append(b)
    return out^


def _lights_red(mut world: World) raises -> ActorId:
    var light = world.filter_actors("*traffic_light*")[0]
    world.freeze(light, False)
    world.set_traffic_light_state(light, RED)
    world.freeze(light, True)
    return light


# --- geometry ------------------------------------------------------------------------


def test_even_odd_polygons() raises:
    var square: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        Vector3(2, 2, 0),
        Vector3(0, 2, 0),
    ]
    assert_true(point_in_polygon(Vector3(1, 1, 5), square))
    assert_false(point_in_polygon(Vector3(3, 1, 0), square))
    # A bow tie, as CARLA's route ring: the middle row is outside.
    var bow: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, 2, 0),
        Vector3(2, 0, 0),
        Vector3(2, 2, 0),
    ]
    assert_true(point_in_polygon(Vector3(0.2, 1, 0), bow))
    assert_false(point_in_polygon(Vector3(1, 0.2, 0), bow))
    var far: List[Vector3] = [
        Vector3(5, 5, 0),
        Vector3(6, 5, 0),
        Vector3(6, 6, 0),
    ]
    assert_false(polygons_intersect(square, far))
    # One inside the other: no edge crosses.
    var small: List[Vector3] = [
        Vector3(0.5, 0.5, 0),
        Vector3(1, 0.5, 0),
        Vector3(1, 1, 0),
    ]
    assert_true(polygons_intersect(square, small))
    assert_true(polygons_intersect(small, square))
    # Crossing edges.
    var across: List[Vector3] = [
        Vector3(1, -1, 0),
        Vector3(1.5, -1, 0),
        Vector3(1, 3, 0),
    ]
    assert_true(polygons_intersect(square, across))
    # Touching at a corner, and along an edge's line past its end.
    var corner: List[Vector3] = [
        Vector3(2, 2, 0),
        Vector3(3, 2, 0),
        Vector3(3, 3, 0),
    ]
    assert_true(polygons_intersect(square, corner))
    var line: List[Vector3] = [
        Vector3(3, 0, 0),
        Vector3(4, 0, 0),
        Vector3(4, -1, 0),
    ]
    assert_false(polygons_intersect(square, line))
    var t1: List[Vector3] = [
        Vector3(1, 2, 0),
        Vector3(1, 3, 0),
        Vector3(0.5, 3, 0),
    ]
    assert_true(polygons_intersect(square, t1))
    var t2: List[Vector3] = [
        Vector3(1, 3, 0),
        Vector3(1, 2, 0),
        Vector3(0.5, 3, 0),
    ]
    assert_true(polygons_intersect(square, t2))
    var t3: List[Vector3] = [
        Vector3(-1, 2, 0),
        Vector3(-1, 3, 0),
        Vector3(0, 2, 0),
    ]
    assert_true(polygons_intersect(t3, square))
    var t4: List[Vector3] = [
        Vector3(0, 2, 0),
        Vector3(-1, 3, 0),
        Vector3(-1, 2, 0),
    ]
    assert_true(polygons_intersect(t4, square))


# --- basic agent ----------------------------------------------------------------------


def test_basic_agent_reaches_its_destination() raises:
    # Road 1 east, straight through the junction on road 10, onto road 2.
    # The plan ends 4 m short of (110.3, 1.75); the last item needs the
    # car within 1 m.
    var world = _town()
    var car = _car(world, 5.3, 1.75)
    var agent = BasicAgent(world, car)
    agent.ignore_traffic_lights()
    agent.set_destination(world, Vector3(110.3, 1.75, 0))
    var worst = Float32(0)
    var ticks = 0
    while not agent.done() and ticks < 800:
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
        worst = max(worst, abs(world.get_location(car).y - 1.75))
        ticks += 1
    assert_true(agent.done())
    var at = world.get_location(car)
    assert_true(at.x > 104 and at.x < 110)
    assert_true(worst < 0.5)
    # Done: the planner brakes fully.
    assert_equal(agent.run_step(world).brake, 1)


def test_basic_agent_stops_for_a_red_light() raises:
    var world = _town()
    var light = _lights_red(world)
    var car = _car(world, 5.3, 1.75)
    var agent = BasicAgent(world, car)
    agent.set_destination(world, Vector3(110.3, 1.75, 0))
    for _ in range(300):
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
    var trigger = agent.lights_map[light.value]
    var at = world.get_location(car)
    assert_true(_speed(world, car) < 0.1)
    # The car stops ahead of the trigger waypoint, within the 5 m base
    # threshold plus one second at 25 km/h.
    assert_true(at.x < trigger.transform.location.x)
    assert_true(at.x > trigger.transform.location.x - 12)
    assert_equal(agent.last_traffic_light.value(), light)
    var found = agent.affected_by_traffic_light(world)
    assert_true(found.traffic_light_was_found)
    assert_equal(found.traffic_light.value(), light)
    # Green: the agent forgets the light and drives on.
    world.freeze(light, False)
    world.set_traffic_light_state(light, GREEN)
    world.freeze(light, True)
    for _ in range(100):
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
    assert_false(Bool(agent.last_traffic_light))
    assert_true(world.get_location(car).x > trigger.transform.location.x)
    # Ignored lights are never found.
    _ = _lights_red(world)
    agent.ignore_traffic_lights()
    assert_false(agent.affected_by_traffic_light(world).traffic_light_was_found)


def test_red_light_checks() raises:
    # The car stands 10 m before the trigger waypoint on its lane.
    var world = _town()
    var light = _lights_red(world)
    var probe = _car(world, 5.3, 1.75)
    var agent = BasicAgent(world, probe)
    var found = agent.affected_by_traffic_light(world, List[ActorId]())
    assert_false(found.traffic_light_was_found)
    var trigger = agent.lights_map[light.value].transform.location
    world.set_location(probe, Vector3(trigger.x - 10, 1.75, 0.3))
    # The 5 m base threshold is too short; 12 m reaches.
    assert_false(
        agent.affected_by_traffic_light(
            world, None, Length(0, METER)
        ).traffic_light_was_found
    )
    assert_true(
        agent.affected_by_traffic_light(
            world, _ids(light), Length(12, METER)
        ).traffic_light_was_found
    )
    # A kept light that stays red is kept.
    assert_true(agent.affected_by_traffic_light(world).traffic_light_was_found)
    # A car on the other lane faces the other way; a car past the trigger
    # has it behind.
    world.freeze(light, False)
    world.set_traffic_light_state(light, YELLOW)
    world.freeze(light, True)
    assert_false(
        agent.affected_by_traffic_light(
            world, None, Length(12, METER)
        ).traffic_light_was_found
    )
    _ = _lights_red(world)
    world.set_transform(probe, _pose(trigger.x - 10, -1.75, 0.3, 180))
    assert_false(
        agent.affected_by_traffic_light(
            world, None, Length(12, METER)
        ).traffic_light_was_found
    )
    world.set_transform(probe, _pose(trigger.x + 3, 2.05, 0.3, 0))
    assert_false(
        agent.affected_by_traffic_light(
            world, None, Length(12, METER)
        ).traffic_light_was_found
    )
    # A car on road 3 is on another road.
    world.set_transform(probe, _pose(78.25, 25, 0.3, 90))
    assert_false(
        agent.affected_by_traffic_light(
            world, None, Length(100, METER)
        ).traffic_light_was_found
    )


def test_basic_agent_stops_behind_a_car() raises:
    var world = _town()
    var lead = _car(world, 40, 1.85)
    var car = _car(world, 5.3, 1.75)
    var agent = BasicAgent(world, car)
    agent.ignore_traffic_lights()
    agent.set_destination(world, Vector3(110.3, 1.75, 0))
    for _ in range(300):
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
    var at = world.get_location(car).x
    var lead_at = world.get_location(lead).x
    assert_true(_speed(world, car) < 0.1)
    # No contact: 2.4 m of box ahead of the car, 2.4 m behind the lead.
    assert_true(at + 2.4 < lead_at - 2.4)
    # The gap is below the 5 m base threshold plus the braking distance.
    assert_true(lead_at - 2.4 - (at + 2.4) < 12)
    var found = agent.vehicle_obstacle_detected(world)
    assert_true(found.obstacle_was_found)
    assert_equal(found.obstacle.value(), lead)
    assert_almost_equal(
        Float64(found.distance.value), Float64(lead_at - at), atol=0.05
    )
    agent.ignore_vehicles()
    assert_false(agent.vehicle_obstacle_detected(world).obstacle_was_found)
    agent.ignore_vehicles(False)
    # An empty list, a car out of reach, and the agent itself.
    assert_false(
        agent.vehicle_obstacle_detected(
            world, List[ActorId]()
        ).obstacle_was_found
    )
    assert_false(
        agent.vehicle_obstacle_detected(
            world, _ids(car, lead), Length(1, METER)
        ).obstacle_was_found
    )
    # The emergency stop keeps the steering.
    var c = VehicleControl()
    c.throttle = 0.5
    c.steer = 0.2
    c.hand_brake = True
    var stop = agent.add_emergency_stop(c)
    assert_equal(stop.throttle, 0)
    assert_almost_equal(stop.brake, 0.6, atol=1e-7)
    assert_almost_equal(stop.steer, 0.2, atol=1e-7)
    assert_false(stop.hand_brake)


def test_vehicle_checks_on_other_lanes() raises:
    # The car is at x = 10 on lane -1 of the two-lane road, planning ahead.
    var world = _world(_two_lane())
    var car = _car(world, 10.3, 1.75)
    var right = _car(world, 18.3, 5.25)
    var agent = BasicAgent(world, car)
    _ = agent.local_planner.run_step(world)
    # Lane -2 is lane -1 plus... a lane offset of 1 turns into -1 on a
    # lane with a minus id: the check looks at lane -1 + (-1) = -2.
    var own = agent.vehicle_obstacle_detected(
        world, _ids(right), Length(20, METER)
    )
    assert_false(own.obstacle_was_found)
    var beside = agent.vehicle_obstacle_detected(
        world,
        _ids(right),
        Length(20, METER),
        Angle(90, DEGREE),
        Angle(0, DEGREE),
        1,
    )
    assert_true(beside.obstacle_was_found)
    # Behind, the car on lane -1 is at 180 degrees less 1.
    var behind = _car(world, 0.3, 1.9)
    var back = agent.vehicle_obstacle_detected(
        world,
        _ids(behind),
        Length(20, METER),
        Angle(180, DEGREE),
        Angle(160, DEGREE),
    )
    assert_true(back.obstacle_was_found)
    # With the plan empty there is no incoming waypoint to try.
    agent.local_planner.queue.clear()
    var none = agent.vehicle_obstacle_detected(
        world, _ids(right), Length(20, METER)
    )
    assert_false(none.obstacle_was_found)


def test_route_polygon_check() raises:
    # With `use_bbs_detection` the car checks boxes against its route.
    var world = _world(_two_lane())
    var car = _car(world, 10.3, 1.75)
    var ahead = _car(world, 20.3, 2.75)
    var side = _car(world, 20.3, 5.75)
    var options = BasicAgentOptions()
    options.use_bbs_detection = True
    var agent = BasicAgent(world, car, from_kmh(20), options)
    _ = agent.local_planner.run_step(world)
    var found = agent.vehicle_obstacle_detected(
        world, _ids(ahead, side), Length(15, METER)
    )
    assert_true(found.obstacle_was_found)
    assert_equal(found.obstacle.value(), ahead)
    assert_false(
        agent.vehicle_obstacle_detected(
            world, _ids(side), Length(15, METER)
        ).obstacle_was_found
    )
    # A reach shorter than the first plan item gives two points: no
    # polygon, so the lane check runs and finds the car on lane -1.
    assert_true(
        agent.vehicle_obstacle_detected(
            world, _ids(ahead), Length(1.5, METER)
        ).obstacle_was_found
        == False
    )
    # An offset past half the lane turns the box check on by itself.
    var wide = BasicAgentOptions()
    wide.offset = Length(1, METER)
    var shifted = BasicAgent(world, car, from_kmh(20), wide)
    _ = shifted.local_planner.run_step(world)
    assert_true(
        shifted.vehicle_obstacle_detected(
            world, _ids(ahead), Length(15, METER)
        ).obstacle_was_found
    )


def test_junction_uses_boxes() raises:
    # Inside junction 100 the agent checks boxes against its route.
    var world = _town()
    var car = _car(world, 62.3, 1.75)
    var other = _car(world, 72.3, 3.5)
    var agent = BasicAgent(world, car)
    agent.set_destination(world, Vector3(110.3, 1.75, 0))
    var found = agent.vehicle_obstacle_detected(
        world, _ids(other), Length(15, METER)
    )
    assert_true(found.obstacle_was_found)


# --- plans ---------------------------------------------------------------------------

comptime _LC_RIGHT = "1,-1,5.3,4;1,-1,7.3,4;1,-1,9.3,4;1,-1,11.3,4;1,-1,13.3,4;1,-1,15.3,4;1,-2,40.3,6;1,-2,42.3,4;1,-2,44.3,4;1,-2,46.3,4;1,-2,48.3,4;2,-2,0.3,4;2,-2,2.3,4;2,-2,4.3,4;2,-2,6.3,4;2,-2,8.3,4;2,-2,10.3,4;2,-2,12.3,4;2,-2,14.3,4;2,-2,16.3,4"

comptime _LC_LEFT = "1,-2,30.3,4;1,-2,34.8,4;1,-1,39.8,5;1,-1,44.3,4"


def test_lane_change_paths() raises:
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var agent = BasicAgent(world, car)
    var w = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 5.3)
    var right = agent.generate_lane_change_path(
        world.map, w, OPTION_CHANGE_LANE_RIGHT
    )
    assert_equal(_short(right), _LC_RIGHT)
    # Lane -1 lets a car cross only to the right.
    var left = agent.generate_lane_change_path(
        world.map, w, OPTION_CHANGE_LANE_LEFT
    )
    assert_equal(len(left), 0)
    # Unchecked, there is no lane to the left of lane -1.
    var unchecked = agent.generate_lane_change_path(
        world.map,
        w,
        OPTION_CHANGE_LANE_LEFT,
        Length(10, METER),
        Length(25, METER),
        Length(25, METER),
        False,
    )
    assert_equal(len(unchecked), 0)
    var w2 = Waypoint(RoadId(1), SectionId(0), LaneId(-2), 30.3)
    var back = agent.generate_lane_change_path(
        world.map,
        w2,
        OPTION_CHANGE_LANE_LEFT,
        Length(0, METER),
        Length(0, METER),
        Length(5, METER),
        True,
        1,
        Length(4.5, METER),
    )
    assert_equal(_short(back), _LC_LEFT)
    var wrong = agent.generate_lane_change_path(
        world.map,
        w2,
        OPTION_STRAIGHT,
        Length(0, METER),
        Length(0, METER),
        Length(5, METER),
        True,
        1,
        Length(4.5, METER),
    )
    assert_equal(len(wrong), 0)
    with assert_raises(contains="Road option is not valid"):
        _ = agent.generate_lane_change_path(world.map, w2, RoadOption(0))
    # Near the end of the road, the first stretch runs out.
    var w3 = Waypoint(RoadId(2), SectionId(0), LaneId(-1), 40.3)
    assert_equal(
        len(
            agent.generate_lane_change_path(
                world.map, w3, OPTION_CHANGE_LANE_RIGHT
            )
        ),
        0,
    )
    # The change itself runs out, and the last stretch runs out.
    var w4 = Waypoint(RoadId(2), SectionId(0), LaneId(-1), 30.3)
    assert_equal(
        len(
            agent.generate_lane_change_path(
                world.map,
                w4,
                OPTION_CHANGE_LANE_RIGHT,
                Length(1, METER),
                Length(1, METER),
                Length(25, METER),
            )
        ),
        0,
    )
    assert_equal(
        len(
            agent.generate_lane_change_path(
                world.map,
                w4,
                OPTION_CHANGE_LANE_RIGHT,
                Length(1, METER),
                Length(25, METER),
                Length(5, METER),
            )
        ),
        0,
    )


def test_basic_agent_changes_lane() raises:
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    world.set_target_velocity(car, Vector3(5, 0, 0))
    var agent = BasicAgent(world, car)
    agent.lane_change(
        world,
        OPTION_CHANGE_LANE_RIGHT,
        Duration(1, SECOND),
        Duration(4, SECOND),
        Duration(3, SECOND),
    )
    assert_true(len(agent.local_planner.queue) > 3)
    var ticks = 0
    while not agent.done() and ticks < 600:
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
        ticks += 1
    assert_true(agent.done())
    assert_almost_equal(world.get_location(car).y, 5.25, atol=0.5)


def test_destinations_and_settings() raises:
    var world = _town()
    var car = _car(world, 5.3, 1.75)
    var planner = GlobalRoutePlanner(world.map, Length(2, METER))
    var agent = BasicAgent(world, car, planner^, from_kmh(30))
    assert_almost_equal(kmh(agent.local_planner.target_speed), 30, atol=1e-4)
    agent.set_target_speed(from_kmh(25))
    assert_almost_equal(kmh(agent.target_speed), 25, atol=1e-4)
    assert_almost_equal(kmh(agent.local_planner.target_speed), 25, atol=1e-4)
    agent.follow_speed_limits()
    assert_true(agent.local_planner.follow_limits)
    agent.set_offset(Length(0.5, METER))
    assert_equal(agent.local_planner.controller.lateral.offset.value, 0.5)
    agent.ignore_stop_signs()
    assert_true(agent.ignore_signs)
    # From the planner's target waypoint (the car's own, s = 5.3).
    agent.set_destination(world, Vector3(40.3, 1.75, 0))
    var first = agent.local_planner.queue[0].waypoint
    assert_almost_equal(first.s, 6, atol=1e-6)
    var count = len(agent.local_planner.queue)
    # Appended from the end of the plan: a second stretch.
    agent.set_destination(world, Vector3(110.3, 1.75, 0), None, False)
    assert_true(len(agent.local_planner.queue) > count)
    # From a given start.
    agent.set_destination(
        world, Vector3(110.3, 1.75, 0), Vector3(20.3, 1.75, 0), True
    )
    assert_almost_equal(agent.local_planner.queue[0].waypoint.s, 20, atol=1e-6)
    # Appended to an empty plan: from the car.
    agent.local_planner.queue.clear()
    agent.set_destination(world, Vector3(40.3, 1.75, 0), None, False)
    assert_almost_equal(agent.local_planner.queue[0].waypoint.s, 6, atol=1e-6)
    var plan = agent.trace_route(
        world.map,
        Waypoint(RoadId(1), SectionId(0), LaneId(-1), 20.3),
        Waypoint(RoadId(1), SectionId(1), LaneId(-1), 40.3),
    )
    assert_equal(len(plan), 10)
    agent.set_global_plan(plan)
    assert_equal(len(agent.local_planner.queue), 10)


# --- behavior agent -------------------------------------------------------------------


def _cruise(kind: BehaviorType) raises -> Tuple[Float64, Float64]:
    # 12 s from rest on lane -1 of the two-lane road; the speed limit is
    # 30 km/h before any sign.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var agent = BehaviorAgent(world, car, kind)
    agent.agent.set_destination(world, Vector3(95.3, 1.75, 0))
    var total = 0.0
    for i in range(240):
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
        if i >= 160:
            total += _speed(world, car)
    return (kmh(agent.agent.local_planner.target_speed), total / 80.0)


def test_behavior_types_drive_at_their_speeds() raises:
    # min(max_speed, 30 - speed_lim_dist): 24, 27 and 29 km/h.
    var cautious = _cruise(CAUTIOUS)
    var normal = _cruise(NORMAL)
    var aggressive = _cruise(AGGRESSIVE)
    assert_almost_equal(cautious[0], 24, atol=1e-3)
    assert_almost_equal(normal[0], 27, atol=1e-3)
    assert_almost_equal(aggressive[0], 29, atol=1e-3)
    assert_true(cautious[1] < normal[1])
    assert_true(normal[1] < aggressive[1])
    assert_true(cautious[1] > 18)


def test_behavior_agent_slows_for_a_turn() raises:
    # Up to the junction the plan turns right: the limit less 5 km/h.
    var world = _town()
    var car = _car(world, 40.3, 1.75)
    var agent = BehaviorAgent(world, car)
    agent.agent.ignore_traffic_lights()
    agent.agent.set_destination(world, Vector3(78.25, 40.3, 0))
    _ = agent.run_step(world)
    assert_equal(agent.look_ahead_steps, 3)
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 27, atol=1e-3
    )
    # Three plan items ahead of the car, the plan turns right into the
    # junction.
    var ticks = 0
    while agent.incoming_direction != OPTION_RIGHT and ticks < 200:
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
        ticks += 1
    assert_equal(agent.incoming_direction.value, OPTION_RIGHT.value)
    assert_true(world.get_location(car).x < 60)
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 25, atol=1e-3
    )
    for index in range(len(agent.agent.local_planner.queue)):
        agent.agent.local_planner.queue[index].road_option = OPTION_LEFT
    _ = agent.run_step(world)
    assert_equal(agent.incoming_direction.value, OPTION_LEFT.value)
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 25, atol=1e-3
    )


def test_behavior_agent_red_light_and_walkers() raises:
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var walker = _walker(world, 11.3, 1.95)
    var agent = BehaviorAgent(world, car)
    # The walker's box and the car's are 0.25 m and 2.4 m about their
    # centers, 6 m apart: a gap of about 3.4 m, under the 5 m of `NORMAL`.
    # The walker stands 0.2 m off the car's line: CARLA's angle range is
    # open, so a target at exactly 0 degrees is not seen.
    var stop = agent.run_step(world)
    assert_equal(stop.throttle, 0)
    assert_almost_equal(stop.brake, 0.6, atol=1e-7)
    assert_equal(stop.steer, 0)
    var seen = agent.pedestrian_avoid_manager(
        world, world.map.closest_waypoint_on_road(Vector3(5.3, 1.75, 0)).value()
    )
    assert_equal(seen.obstacle.value(), walker)
    # Far away the walker is not seen.
    world.set_location(walker, Vector3(30.3, 1.95, 1.0))
    var go = agent.run_step(world)
    assert_true(go.throttle > 0)
    # 8 m ahead: seen, but the gap of about 5.4 m is not under 5 m.
    world.set_location(walker, Vector3(13.3, 1.95, 1.0))
    var on = agent.run_step(world)
    assert_true(on.throttle > 0)


def test_behavior_agent_lane_change_directions() raises:
    # While the plan changes lanes, the checks look at the lane beside.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var beside = _car(world, 12.3, 5.25)
    var walker = _walker(world, 9.3, 5.25)
    var agent = BehaviorAgent(world, car)
    var w = world.map.closest_waypoint_on_road(Vector3(5.3, 1.75, 0)).value()
    agent.speed_limit = from_kmh(30)
    agent.direction = OPTION_CHANGE_LANE_RIGHT
    assert_equal(
        agent.collision_and_car_avoid_manager(world, w).obstacle.value(),
        beside,
    )
    assert_equal(
        agent.pedestrian_avoid_manager(world, w).obstacle.value(), walker
    )
    agent.direction = OPTION_CHANGE_LANE_LEFT
    assert_false(
        agent.collision_and_car_avoid_manager(world, w).obstacle_was_found
    )
    assert_false(agent.pedestrian_avoid_manager(world, w).obstacle_was_found)


def test_car_following() raises:
    # The car drives at 36 km/h behind one at 18 km/h: a closing speed of
    # 5 m/s. Gaps of 10, 20 and 40 m give times of 2, 4 and 8 s against
    # the safety time of 3 s.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var lead = _car(world, 30.3, 1.85)
    world.set_target_velocity(car, Vector3(10, 0, 0))
    world.set_target_velocity(lead, Vector3(5, 0, 0))
    var agent = BehaviorAgent(world, car)
    agent.update_information(world)
    _ = agent.car_following_manager(world, lead, Length(10, METER))
    # min(18 - 10, 50, 30 - 3) = 8.
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 8, atol=1e-3
    )
    _ = agent.car_following_manager(world, lead, Length(20, METER))
    # min(max(5, 18), 50, 27) = 18.
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 18, atol=1e-3
    )
    _ = agent.car_following_manager(world, lead, Length(40, METER))
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 27, atol=1e-3
    )
    # The range, max(10 m, 30 / 3), holds between the centers, so a car
    # ahead is seen only with a gap under 10 - 4.8 = 5.2 m. At 9.9 m
    # between the centers the gap is 5.1 m, over the braking distance:
    # 1.02 s to a collision, so `run_step` slows to 18 - 10 = 8 km/h.
    world.set_location(lead, Vector3(15.2, 1.85, 0.3))
    _ = agent.run_step(world)
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 8, atol=0.1
    )
    # Close behind: an emergency stop.
    world.set_location(lead, Vector3(12.3, 1.85, 0.3))
    var stop = agent.run_step(world)
    assert_almost_equal(stop.brake, 0.6, atol=1e-7)
    # A red light: an emergency stop too.
    var town = _town()
    _ = _lights_red(town)
    # The trigger waypoint is at s = 52 on lane -1: 3.7 m ahead, within
    # the 5 m threshold.
    var town_car = _car(town, 48.3, 1.95)
    var town_agent = BehaviorAgent(town, town_car)
    assert_almost_equal(town_agent.run_step(town).brake, 0.6, atol=1e-7)


def test_tailgating_moves_right() raises:
    # A car at 18 km/h on lane -1, a faster one 6 m behind: the agent
    # moves to lane -2, which the broken mark allows.
    var world = _world(_two_lane())
    var car = _car(world, 20.3, 1.75)
    var behind = _car(world, 12.3, 2.05)
    world.set_target_velocity(car, Vector3(5, 0, 0))
    world.set_target_velocity(behind, Vector3(8, 0, 0))
    var agent = BehaviorAgent(world, car)
    agent.update_information(world)
    var w = world.map.closest_waypoint_on_road(Vector3(20.3, 1.75, 0)).value()
    _ = agent.collision_and_car_avoid_manager(world, w)
    assert_equal(agent.behavior.tailgate_counter, 200)
    assert_equal(agent.agent.local_planner.queue[0].waypoint.lane_id.value, -2)
    # The counter runs down one a step.
    _ = agent.run_step(world)
    assert_equal(agent.behavior.tailgate_counter, 199)


def test_tailgating_needs_a_free_lane() raises:
    var world = _world(_two_lane())
    var car = _car(world, 20.3, 1.75)
    var behind = _car(world, 12.3, 2.05)
    var blocker = _car(world, 25.3, 5.25)
    world.set_target_velocity(car, Vector3(5, 0, 0))
    world.set_target_velocity(behind, Vector3(8, 0, 0))
    var agent = BehaviorAgent(world, car)
    agent.update_information(world)
    var w = world.map.closest_waypoint_on_road(Vector3(20.3, 1.75, 0)).value()
    _ = agent.collision_and_car_avoid_manager(world, w)
    assert_equal(agent.behavior.tailgate_counter, 0)
    # A slower car behind is no reason to move.
    world.set_location(blocker, Vector3(80, 5.25, 0.3))
    world.set_target_velocity(behind, Vector3(2, 0, 0))
    _ = agent.collision_and_car_avoid_manager(world, w)
    assert_equal(agent.behavior.tailgate_counter, 0)


def test_tailgating_moves_left_only_on_a_left_mark() raises:
    # On lane -2 the left mark is lane -1's. "both" is not enough: CARLA
    # asks for exactly "Left". "decrease" gives it, and forbids the way
    # back to the right.
    for change in ["both", "decrease"]:
        var world = _world(_two_lane(change))
        var car = _car(world, 20.3, 5.25)
        var behind = _car(world, 12.3, 5.55)
        world.set_target_velocity(car, Vector3(5, 0, 0))
        world.set_target_velocity(behind, Vector3(8, 0, 0))
        var agent = BehaviorAgent(world, car)
        agent.update_information(world)
        var w = world.map.closest_waypoint_on_road(
            Vector3(20.3, 5.25, 0)
        ).value()
        _ = agent.collision_and_car_avoid_manager(world, w)
        if change == "both":
            assert_equal(agent.behavior.tailgate_counter, 0)
        else:
            # The move is made, but the route from lane -1 back to the
            # target on lane -2 needs a change to the right, which
            # "decrease" forbids: the plan is empty.
            assert_equal(agent.behavior.tailgate_counter, 200)
            assert_equal(len(agent.agent.local_planner.queue), 0)


def test_behavior_agent_checks_its_type() raises:
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    with assert_raises(contains="Behavior type is not valid"):
        _ = BehaviorAgent(world, car, BehaviorType(7))
    var agent = BehaviorAgent(world, car, AGGRESSIVE)
    assert_equal(agent.behavior.tailgate_counter, -1)
    assert_equal(agent.agent.sampling_resolution.value, 4.5)
    # With nothing left to plan, no incoming waypoint and a full stop.
    agent.agent.local_planner.queue.clear()
    agent.agent.local_planner.stop_waypoint_creation = True
    var stop = agent.run_step(world)
    assert_false(Bool(agent.incoming_waypoint))
    assert_equal(stop.brake, 1)


# --- constant velocity agent -----------------------------------------------------------


def test_constant_velocity_agent_holds_its_speed() raises:
    # The world sets the held velocity before each physics step; the
    # step's drag and rolling resistance take a little off by its end.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var agent = ConstantVelocityAgent(world, car, from_kmh(36))
    for _ in range(40):
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
    assert_almost_equal(_speed(world, car), 36, atol=2)
    agent.set_target_speed(from_kmh(18))
    for _ in range(10):
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
    assert_almost_equal(_speed(world, car), 18, atol=2)


def test_constant_velocity_agent_matches_a_car_ahead() raises:
    # A still car ahead has no speed along the agent's heading: the
    # agent holds zero. The range, 5 m plus the speed times 1 s, holds
    # between the centers. Standing still, the agent sees only 5 m and
    # holds its speed again for one step: it creeps up in steps of half a
    # meter, and at last touches the car, which stops the mode.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    _ = _car(world, 25.3, 1.85)
    var agent = ConstantVelocityAgent(world, car, from_kmh(36))
    var held = 0
    for _ in range(80):
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
        if _speed(world, car) < 2:
            held += 1
    assert_true(held > 10)
    assert_false(agent.is_constant_velocity_active)
    # A red light holds zero as well.
    var town = _town()
    _ = _lights_red(town)
    var town_car = _car(town, 45.3, 1.75)
    var town_agent = ConstantVelocityAgent(town, town_car, from_kmh(36))
    for _ in range(40):
        town.apply_control(town_car, town_agent.run_step(town))
        _ = town.tick()
    # The trigger waypoint is at s = 52: 6.7 m ahead, seen once the range
    # grows past it at speed. The light is kept while it is red.
    assert_true(_speed(town, town_car) < 2)
    assert_true(town.get_location(town_car).x < 52)
    assert_true(Bool(town_agent.agent.last_traffic_light))


def test_constant_velocity_agent_stops_on_a_collision() raises:
    # With other cars ignored, the agent runs into one and stops holding
    # its speed. It starts again after the restart time.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    _ = _car(world, 20.3, 1.75)
    var options = BasicAgentOptions()
    options.ignore_vehicles = True
    var agent = ConstantVelocityAgent(
        world, car, from_kmh(36), options, Duration(1, SECOND)
    )
    var ticks = 0
    while agent.is_constant_velocity_active and ticks < 100:
        world.apply_control(car, agent.run_step(world))
        _ = world.tick()
        ticks += 1
    assert_false(agent.is_constant_velocity_active)
    var stopped = agent.constant_velocity_stop_time.value().value
    assert_true(stopped > 0)
    # While stopped the agent gives an empty control.
    var idle = agent.run_step(world)
    assert_equal(idle.throttle, 0)
    assert_equal(idle.brake, 0)
    for _ in range(25):
        _ = world.tick()
    _ = agent.run_step(world)
    assert_true(agent.is_constant_velocity_active)


def test_constant_velocity_agent_basic_fallback() raises:
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var agent = ConstantVelocityAgent(
        world,
        car,
        from_kmh(36),
        BasicAgentOptions(),
        Duration(100, SECOND),
        True,
    )
    agent.stop_constant_velocity(world)
    var c = agent.run_step(world)
    assert_almost_equal(c.throttle, 0.75, atol=1e-6)
    assert_false(agent.is_constant_velocity_active)
    agent.restart_constant_velocity(world)
    assert_true(agent.is_constant_velocity_active)


# --- corners ------------------------------------------------------------------------------


def test_empty_rings() raises:
    var square: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        Vector3(2, 2, 0),
    ]
    assert_false(point_in_polygon(Vector3(1, 1, 0), List[Vector3]()))
    assert_false(polygons_intersect(square, List[Vector3]()))
    assert_false(polygons_intersect(List[Vector3](), square))


def test_obstacle_check_corners() raises:
    var world = _world(_two_lane())
    var car = _car(world, 45.3, 1.75)
    var ahead = _car(world, 53.3, 1.85)
    var agent = BasicAgent(world, car)
    _ = agent.local_planner.run_step(world)
    # A zero range means the 5 m base threshold: the car ahead, 8 m off,
    # is out of it.
    assert_false(
        agent.vehicle_obstacle_detected(
            world, _ids(ahead), Length(0, METER)
        ).obstacle_was_found
    )
    # The car ahead is on road 2, the car on road 1: it counts through the
    # plan's waypoint three steps on, on road 2.
    assert_true(
        agent.vehicle_obstacle_detected(
            world, _ids(ahead), Length(20, METER)
        ).obstacle_was_found
    )
    # A lane change of zero lanes drives on in the lane.
    var w = world.map.closest_waypoint_on_road(Vector3(5.3, 1.75, 0)).value()
    var none = agent.generate_lane_change_path(
        world.map,
        w,
        OPTION_CHANGE_LANE_RIGHT,
        Length(4, METER),
        Length(4, METER),
        Length(4, METER),
        True,
        0,
    )
    for item in none:
        assert_equal(item.waypoint.lane_id.value, -1)
    # Right of lane -2 is the sidewalk: no change.
    var w2 = world.map.closest_waypoint_on_road(Vector3(5.3, 5.25, 0)).value()
    assert_equal(
        len(
            agent.generate_lane_change_path(
                world.map,
                w2,
                OPTION_CHANGE_LANE_RIGHT,
                Length(4, METER),
                Length(4, METER),
                Length(4, METER),
                False,
            )
        ),
        0,
    )
    # With the box check on and nothing planned, the lane check runs.
    var options = BasicAgentOptions()
    options.use_bbs_detection = True
    var boxes = BasicAgent(world, car, from_kmh(20), options)
    boxes.local_planner.queue.clear()
    assert_false(
        boxes.vehicle_obstacle_detected(
            world, _ids(ahead), Length(20, METER)
        ).obstacle_was_found
    )


def test_obstacle_check_on_a_left_lane() raises:
    # Lane 1 of the town runs west. An offset of 1 stays 1 on a lane with
    # a plus id: lane 1 + 1 = 2, a sidewalk.
    var world = _town()
    var car = _car(world, 20.3, -1.75, 180)
    var other = _car(world, 12.3, -1.85, 180)
    var agent = BasicAgent(world, car)
    var own = agent.vehicle_obstacle_detected(
        world, _ids(other), Length(20, METER)
    )
    assert_true(own.obstacle_was_found)
    var beside = agent.vehicle_obstacle_detected(
        world,
        _ids(other),
        Length(20, METER),
        Angle(90, DEGREE),
        Angle(0, DEGREE),
        1,
    )
    assert_false(beside.obstacle_was_found)


def _tailgate(mut world: World, x: Float32, y: Float32) raises -> Int:
    # A car at 18 km/h, a faster one 8 m behind: the counter after the
    # check, 200 when the agent moved.
    var car = _car(world, x, y)
    var behind = _car(world, x - 8, y + 0.3)
    world.set_target_velocity(car, Vector3(5, 0, 0))
    world.set_target_velocity(behind, Vector3(8, 0, 0))
    var agent = BehaviorAgent(world, car)
    agent.update_information(world)
    var w = world.map.closest_waypoint_on_road(Vector3(x, y, 0)).value()
    _ = agent.collision_and_car_avoid_manager(world, w)
    return agent.behavior.tailgate_counter


def test_tailgating_corners() raises:
    # Road 2 of the town has no marks: no change either way.
    var town = _town()
    assert_equal(_tailgate(town, 110.3, 1.75), 0)
    # Road 1's first section: the right mark allows, but right is the
    # sidewalk; the center line forbids the left.
    var town2 = _town()
    assert_equal(_tailgate(town2, 20.3, 1.75), 0)
    # A center line that allows the left, with no lane beyond it.
    var world = _world(_two_lane("none", "decrease"))
    assert_equal(_tailgate(world, 20.3, 1.75), 0)


def test_following_a_car_behind_the_front() raises:
    # A gap below zero gives no time to a collision: the plain cap.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    var lead = _car(world, 30.3, 1.85)
    var agent = BehaviorAgent(world, car)
    agent.update_information(world)
    _ = agent.car_following_manager(world, lead, Length(-1, METER))
    assert_almost_equal(
        kmh(agent.agent.local_planner.target_speed), 27, atol=1e-3
    )


def test_constant_velocity_agent_standing_still() raises:
    # A car 4.9 m ahead, center to center, is within the 5 m range of a
    # still agent; the agent's speed of zero holds zero.
    var world = _world(_two_lane())
    var car = _car(world, 5.3, 1.75)
    _ = _car(world, 10.2, 1.85)
    var agent = ConstantVelocityAgent(world, car, from_kmh(36))
    _ = agent.run_step(world)
    _ = world.tick()
    assert_true(_speed(world, car) < 2)


def test_two_sided_marking_allows_lane_change() raises:
    var world = _world(_two_lane("both", "both"))
    var car = _car(world, 5.3, 1.75)
    var agent = BasicAgent(world, car)
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 5.3)
    var path = agent.generate_lane_change_path(
        world.map, start, OPTION_CHANGE_LANE_RIGHT
    )
    assert_equal(_short(path), _LC_RIGHT)


def test_approaching_car_detects_a_target_inside_junction() raises:
    var world = _town()
    var car = _car(world, 55.3, 1.75)
    var target = _car(world, 62.3, 1.75)
    var agent = BasicAgent(world, car)
    agent.set_destination(world, Vector3(110.3, 1.75, 0))
    assert_true(
        agent.vehicle_obstacle_detected(
            world, _ids(target), Length(15, METER)
        ).obstacle_was_found
    )


def test_tailgating_right_only_mark_needs_a_driving_neighbor() raises:
    var allowed = _world(_two_lane("increase"))
    assert_equal(_tailgate(allowed, 20.3, 1.75), 200)
    var text = (
        String(TWO_LANE)
        .replace("{CHANGE}", "increase")
        .replace("{CENTER}", "none")
    )
    text = text.replace(
        '<lane id="-2" type="driving">', '<lane id="-2" type="sidewalk">'
    )
    var sidewalk = _world(load_opendrive(text))
    assert_equal(_tailgate(sidewalk, 20.3, 1.75), 0)


def test_turning_or_junction_agent_does_not_start_tailgating() raises:
    var world = _world(_two_lane())
    var car = _car(world, 20.3, 1.75)
    var agent = BehaviorAgent(world, car)
    var waypoint = world.map.closest_waypoint_on_road(
        Vector3(20.3, 1.75, 0)
    ).value()
    agent.direction = OPTION_LEFT
    assert_false(
        agent.collision_and_car_avoid_manager(
            world, waypoint
        ).obstacle_was_found
    )
    assert_equal(agent.behavior.tailgate_counter, 0)
    var junction = _town()
    var inside = _car(junction, 65.3, 1.75)
    var crossing = BehaviorAgent(junction, inside)
    crossing.direction = OPTION_LANE_FOLLOW
    var at = junction.map.closest_waypoint_on_road(
        Vector3(65.3, 1.75, 0)
    ).value()
    assert_false(
        crossing.collision_and_car_avoid_manager(
            junction, at
        ).obstacle_was_found
    )
    assert_equal(crossing.behavior.tailgate_counter, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
