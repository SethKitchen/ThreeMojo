# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA agents: the helpers, the PID controllers and the planners.

The expected numbers come from outside this port:

- Hand math for the helpers of `misc.py` and the behavior types.
- CARLA's own Python agents, `controller.py`, `local_planner.py`,
  `global_route_planner.py` and `basic_agent.py`, run in a scratch
  directory against a mock `carla` module. The mock holds the lanes of
  `assets/carla/town.xodr` and of the two-lane road below, worked out by
  hand: straight lanes 3.5 m wide and road 11's arc of radius 20 m. The
  random choice uses the same minimal-standard generator as this port.
- Endpoint fixtures include all dead-end topology lanes. Their node ids,
  lane-change edges and turn decisions correct the inherited narrowing
  bug; these expectations deliberately differ from pinned CARLA.
- The route strings list each plan item as road, section, lane, s
  rounded to a millimeter, and road option.
"""

from extensions.carla.actor import ActorId
from extensions.carla.agents_controller import (
    PIDGains,
    PIDLateralController,
    PIDLongitudinalController,
    VehiclePIDController,
)
from extensions.carla.agents_local_planner import (
    LocalPlanner,
    LocalPlannerOptions,
    PlanItem,
    compute_connection,
    plan_item,
    retrieve_options,
)
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
    OPTION_VOID,
    RoadOption,
    behavior_parameters,
    compute_distance,
    compute_magnitude_angle,
    distance_vehicle,
    from_kmh,
    get_speed,
    get_trafficlight_trigger_location,
    is_within_distance,
    kmh,
    positive,
    speed_of,
    trafficlight_trigger_location,
    vector,
    _acos_degrees,
)
from extensions.carla.agents_route import (
    GlobalRoutePlanner,
    RouteNodeId,
    round_half_even,
    turn_option,
)
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.road_info import LaneId, RoadId, SectionId
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from std.math import floor, isnan
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
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
    Velocity,
)


# --- fixtures -----------------------------------------------------------------------

# A straight one-way road in two pieces of 50 m. Lanes -1 and -2 drive
# east. Lane -1's outer mark is broken and lets a car cross both ways;
# lane -2's is solid; the center line forbids a change.
comptime TWO_LANE = """<?xml version="1.0"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="two lanes"/>
  <road name="a" length="50" id="1" junction="-1">
    <link><successor elementType="road" elementId="2" contactPoint="start"/></link>
    <planView><geometry s="0" x="0" y="0" hdg="0" length="50"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"><roadMark sOffset="0" type="solid" color="yellow" width="0.15" laneChange="none"/></lane></center>
      <right>
        <lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="both"/></lane>
        <lane id="-2" type="driving"><link><successor id="-2"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" color="white" width="0.15" laneChange="none"/></lane>
        <lane id="-3" type="sidewalk"><link><successor id="-3"/></link><width sOffset="0" a="2" b="0" c="0" d="0"/></lane>
      </right>
    </laneSection></lanes>
  </road>
  <road name="b" length="50" id="2" junction="-1">
    <link><predecessor elementType="road" elementId="1" contactPoint="end"/></link>
    <planView><geometry s="0" x="50" y="0" hdg="0" length="50"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"><roadMark sOffset="0" type="solid" color="yellow" width="0.15" laneChange="none"/></lane></center>
      <right>
        <lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="both"/></lane>
        <lane id="-2" type="driving"><link><predecessor id="-2"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" color="white" width="0.15" laneChange="none"/></lane>
        <lane id="-3" type="sidewalk"><link><predecessor id="-3"/></link><width sOffset="0" a="2" b="0" c="0" d="0"/></lane>
      </right>
    </laneSection></lanes>
  </road>
</OpenDRIVE>
"""


# Odd corners for the route planner. Road 1 has four lanes east; lanes -1
# to -3 go on through junction 100, lane -4 ends. From lane -1 the
# junction leads straight on road 10 to road 2, a stub of 1 m; to road
# 11, which lies far away at x = 200; and right on road 13, an arc of
# radius 5 m, then road 14 inside the junction, onto road 3 going south.
# Roads 20, 21 and 22 (3, 1 and 2 m) and roads 6 and 7 (0.5 m each) are
# short pieces in a row.
comptime ODD = """<?xml version="1.0"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="odd"/>
  <road name="entry" length="20" id="1" junction="-1">
    <link><successor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="0" y="0" hdg="0" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="both"/></lane></center>
      <right>
        <lane id="-1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="both"/></lane>
        <lane id="-2" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="both"/></lane>
        <lane id="-3" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" color="white" width="0.15" laneChange="both"/></lane>
        <lane id="-4" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" color="white" width="0.15" laneChange="none"/></lane>
      </right>
    </laneSection></lanes>
  </road>
  <road name="through" length="12" id="10" junction="100">
    <link><predecessor elementType="road" elementId="1" contactPoint="end"/><successor elementType="road" elementId="2" contactPoint="start"/></link>
    <planView><geometry s="0" x="20" y="0" hdg="0" length="12"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right>
        <lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
        <lane id="-2" type="driving"><link><predecessor id="-2"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
        <lane id="-3" type="driving"><link><predecessor id="-3"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
      </right>
    </laneSection></lanes>
  </road>
  <road name="far" length="5" id="11" junction="100">
    <link><predecessor elementType="road" elementId="1" contactPoint="end"/></link>
    <planView><geometry s="0" x="200" y="0" hdg="0" length="5"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="bend" length="7.853981633974483" id="13" junction="100">
    <link><predecessor elementType="road" elementId="1" contactPoint="end"/><successor elementType="road" elementId="14" contactPoint="start"/></link>
    <planView><geometry s="0" x="20" y="0" hdg="0" length="7.853981633974483"><arc curvature="-0.2"/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="bend2" length="5" id="14" junction="100">
    <link><predecessor elementType="road" elementId="13" contactPoint="end"/><successor elementType="road" elementId="3" contactPoint="start"/></link>
    <planView><geometry s="0" x="25" y="-5" hdg="-1.5707963267948966" length="5"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="south" length="20" id="3" junction="-1">
    <link><predecessor elementType="road" elementId="14" contactPoint="end"/></link>
    <planView><geometry s="0" x="25" y="-10" hdg="-1.5707963267948966" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="stub" length="1" id="2" junction="-1">
    <link><predecessor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="32" y="0" hdg="0" length="1"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="three" length="3" id="20" junction="-1">
    <link><successor elementType="road" elementId="21" contactPoint="start"/></link>
    <planView><geometry s="0" x="0" y="100" hdg="0" length="3"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="one" length="1" id="21" junction="-1">
    <link><predecessor elementType="road" elementId="20" contactPoint="end"/><successor elementType="road" elementId="22" contactPoint="start"/></link>
    <planView><geometry s="0" x="3" y="100" hdg="0" length="1"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="last" length="2" id="22" junction="-1">
    <link><predecessor elementType="road" elementId="21" contactPoint="end"/></link>
    <planView><geometry s="0" x="4" y="100" hdg="0" length="2"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="x" length="0.5" id="6" junction="-1">
    <link><successor elementType="road" elementId="7" contactPoint="start"/></link>
    <planView><geometry s="0" x="0" y="50" hdg="0" length="0.5"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="y" length="0.5" id="7" junction="-1">
    <link><predecessor elementType="road" elementId="6" contactPoint="end"/></link>
    <planView><geometry s="0" x="0.5" y="50" hdg="0" length="0.5"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <junction id="100" name="odd">
    <connection id="0" incomingRoad="1" connectingRoad="10" contactPoint="start">
      <laneLink from="-1" to="-1"/>
      <laneLink from="-2" to="-2"/>
      <laneLink from="-3" to="-3"/>
    </connection>
    <connection id="1" incomingRoad="1" connectingRoad="11" contactPoint="start">
      <laneLink from="-1" to="-1"/>
    </connection>
    <connection id="2" incomingRoad="1" connectingRoad="13" contactPoint="start">
      <laneLink from="-1" to="-1"/>
    </connection>
  </junction>
</OpenDRIVE>
"""


def _town() raises -> Map:
    return load_opendrive_file("assets/carla/town.xodr")


def _world(var map: Map) raises -> World:
    var world = World(map^)
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


def _car(mut world: World, x: Float32, y: Float32) raises -> ActorId:
    var bp = world.blueprints.at("vehicle.lincoln.mkz")
    return world.spawn_actor(bp, _pose(x, y, 0.3, 0))


def _s(s: Float64) -> String:
    # Python's "%g" of `round(s, 3)` for the values these plans hold.
    var r = floor(s * 1000.0 + 0.5) / 1000.0
    if r == floor(r):
        return String(Int(r))
    return String(r)


def _route(plan: List[PlanItem]) -> String:
    var out = String()
    for i in range(len(plan)):
        if i > 0:
            out += ";"
        ref w = plan[i].waypoint
        out += String(
            w.road_id.value,
            ",",
            w.section_id.value,
            ",",
            w.lane_id.value,
            ",",
            _s(w.s),
            ",",
            plan[i].road_option.value,
        )
    return out


def _short(plan: List[PlanItem]) -> String:
    # The same without the section, for the two-lane road.
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


# --- types ----------------------------------------------------------------------------


def test_road_options_are_carlas() raises:
    assert_equal(OPTION_VOID.value, -1)
    assert_equal(OPTION_LEFT.value, 1)
    assert_equal(OPTION_RIGHT.value, 2)
    assert_equal(OPTION_STRAIGHT.value, 3)
    assert_equal(OPTION_LANE_FOLLOW.value, 4)
    assert_equal(OPTION_CHANGE_LANE_LEFT.value, 5)
    assert_equal(OPTION_CHANGE_LANE_RIGHT.value, 6)
    assert_true(OPTION_VOID.is_valid())
    assert_true(OPTION_CHANGE_LANE_RIGHT.is_valid())
    assert_false(RoadOption(0).is_valid())
    assert_false(RoadOption(7).is_valid())
    assert_false(RoadOption(-2).is_valid())
    assert_true(RouteNodeId(-2147483648).is_valid())
    assert_true(RouteNodeId(2147483647).is_valid())
    assert_false(RouteNodeId(-2147483649).is_valid())
    assert_false(RouteNodeId(2147483648).is_valid())


def test_behavior_types_are_carlas() raises:
    var c = behavior_parameters(CAUTIOUS)
    assert_almost_equal(kmh(c.max_speed), 40, atol=1e-4)
    assert_almost_equal(kmh(c.speed_lim_dist), 6, atol=1e-4)
    assert_almost_equal(kmh(c.speed_decrease), 12, atol=1e-4)
    assert_equal(c.safety_time.value, 3)
    assert_equal(c.min_proximity_threshold.value, 12)
    assert_equal(c.braking_distance.value, 6)
    assert_equal(c.tailgate_counter, 0)
    var n = behavior_parameters(NORMAL)
    assert_almost_equal(kmh(n.max_speed), 50, atol=1e-4)
    assert_almost_equal(kmh(n.speed_lim_dist), 3, atol=1e-4)
    assert_almost_equal(kmh(n.speed_decrease), 10, atol=1e-4)
    assert_equal(n.min_proximity_threshold.value, 10)
    assert_equal(n.braking_distance.value, 5)
    assert_equal(n.tailgate_counter, 0)
    var a = behavior_parameters(AGGRESSIVE)
    assert_almost_equal(kmh(a.max_speed), 70, atol=1e-4)
    assert_almost_equal(kmh(a.speed_lim_dist), 1, atol=1e-4)
    assert_almost_equal(kmh(a.speed_decrease), 8, atol=1e-4)
    assert_equal(a.min_proximity_threshold.value, 8)
    assert_equal(a.braking_distance.value, 4)
    assert_equal(a.tailgate_counter, -1)
    assert_false(BehaviorType(3).is_valid())
    assert_false(BehaviorType(-1).is_valid())
    with assert_raises(contains="Behavior type is not valid"):
        _ = behavior_parameters(BehaviorType(3))


# --- misc.py --------------------------------------------------------------------------


def test_speeds() raises:
    # |(3, 4, 12)| = 13 m/s = 46.8 km/h.
    assert_almost_equal(speed_of(Vector3(3, 4, 12)).value, 13, atol=1e-5)
    assert_almost_equal(kmh(speed_of(Vector3(3, 4, 12))), 46.8, atol=1e-4)
    assert_almost_equal(from_kmh(36).value, 10, atol=1e-5)
    assert_almost_equal(positive(from_kmh(5)).value, from_kmh(5).value)
    assert_equal(positive(from_kmh(-5)).value, 0)
    assert_equal(positive(Velocity(0)).value, 0)


def test_is_within_distance() raises:
    var ref_pose = _pose(0, 0, 0, 0)
    # A target 0.0005 m away is always within.
    assert_true(
        is_within_distance(_pose(0.0005, 0, 0, 0), ref_pose, Length(1, METER))
    )
    # (3, 4) is 5 m away.
    assert_false(
        is_within_distance(_pose(3, 4, 0, 0), ref_pose, Length(4.9, METER))
    )
    assert_true(
        is_within_distance(_pose(3, 4, 0, 0), ref_pose, Length(5.1, METER))
    )
    # atan(4/3) = 53.13 degrees from the heading.
    var inside = (Angle(50, DEGREE), Angle(60, DEGREE))
    var outside = (Angle(0, DEGREE), Angle(50, DEGREE))
    assert_true(
        is_within_distance(
            _pose(3, 4, 0, 0), ref_pose, Length(10, METER), inside
        )
    )
    assert_false(
        is_within_distance(
            _pose(3, 4, 0, 0), ref_pose, Length(10, METER), outside
        )
    )
    # Behind: 180 - 53.13 = 126.87 degrees.
    assert_false(
        is_within_distance(
            _pose(-3, 4, 0, 0),
            ref_pose,
            Length(10, METER),
            (Angle(0, DEGREE), Angle(90, DEGREE)),
        )
    )
    # Heading 90 degrees faces +y, so (0, 5) is dead ahead.
    assert_true(
        is_within_distance(
            _pose(0, 5, 0, 0),
            _pose(0, 0, 0, 90),
            Length(10, METER),
            (Angle(-1, DEGREE), Angle(1, DEGREE)),
        )
    )


def test_magnitude_angle_and_distances() raises:
    var m = compute_magnitude_angle(
        Vector3(3, 4, 7), Vector3(0, 0, 0), Angle(0, DEGREE)
    )
    assert_almost_equal(m[0].value, 5, atol=1e-6)
    assert_almost_equal(m[1].to(DEGREE), 53.130102354, atol=1e-4)
    var back = compute_magnitude_angle(
        Vector3(-1, 0, 0), Vector3(0, 0, 0), Angle(0, DEGREE)
    )
    assert_almost_equal(back[1].to(DEGREE), 180, atol=1e-4)
    var same = compute_magnitude_angle(
        Vector3(1, 1, 0), Vector3(1, 1, 0), Angle(0, DEGREE)
    )
    assert_equal(same[0].value, 0)
    assert_true(isnan(same[1].value))
    assert_almost_equal(
        distance_vehicle(_pose(3, 4, 9, 0), _pose(0, 0, 0, 0)).value,
        5,
        atol=1e-6,
    )
    # |(2, 3, 6)| = 7.
    var u = vector(Vector3(1, 1, 1), Vector3(3, 4, 7))
    assert_almost_equal(u.x, 2.0 / 7.0, atol=1e-6)
    assert_almost_equal(u.y, 3.0 / 7.0, atol=1e-6)
    assert_almost_equal(u.z, 6.0 / 7.0, atol=1e-6)
    var zero = vector(Vector3(1, 1, 1), Vector3(1, 1, 1))
    assert_equal(zero.x, 0)
    assert_almost_equal(
        compute_distance(Vector3(1, 1, 1), Vector3(3, 4, 7)).value,
        7,
        atol=1e-6,
    )


def test_trigger_location() raises:
    # The box's center, (2, 1, 0.5) in the light's frame, turned by 90
    # degrees of yaw and moved to (10, 20, 3): (9, 22, 3.5).
    var box = BoundingBox(Vector3(2, 1, 0.5), Vector3(1.5, 1.75, 1))
    var at = trafficlight_trigger_location(_pose(10, 20, 3, 90), box)
    assert_almost_equal(at.x, 9, atol=1e-5)
    assert_almost_equal(at.y, 22, atol=1e-5)
    assert_almost_equal(at.z, 3.5, atol=1e-5)


# --- PID -----------------------------------------------------------------------------


def test_longitudinal_pid() raises:
    var pid = PIDLongitudinalController(
        PIDGains(1.5, 0.05, 0.2, Duration(0.05, SECOND))
    )
    var speeds = [19.0, 19.5, 19.8, 20.2, 20.1, 20, 19.9, 20, 20, 20, 20.05, 20]
    var expected = [
        1.0,
        -1.0,
        -0.8957522864341689,
        -1.0,
        0.25349761629105855,
        0.4035064873695384,
        0.5537490496635409,
        -0.3962473244667014,
        0.0037511515617381177,
        0.003751153469086752,
        -0.2738822417259323,
        0.1998822546005345,
    ]
    for i in range(len(speeds)):
        var out = pid.run_step(from_kmh(20), from_kmh(speeds[i]))
        assert_almost_equal(out, expected[i], atol=1e-4)
    pid.change_parameters(PIDGains(1, 0, 0, Duration(0.03, SECOND)))
    assert_almost_equal(
        pid.run_step(from_kmh(20), from_kmh(19.5)), 0.5, atol=1e-4
    )
    # CARLA's defaults: K_P 1, dt 0.03 s.
    var plain = PIDLongitudinalController()
    assert_equal(plain.gains.k_p, 1)
    assert_almost_equal(plain.gains.dt.value, 0.03, atol=1e-7)


def test_lateral_pid() raises:
    var pid = PIDLateralController(
        Length(0, METER), PIDGains(1.95, 0.05, 0.2, Duration(0.05, SECOND))
    )
    var ys = [0.3, 0.35, 0.2, -0.1, 0.0, 0.05, 0.1, 0.1, 0.1, 0.1, 0.1]
    var expected = [
        0.058482461793403016,
        0.088363441106691,
        -0.02074629887366674,
        -0.1392999187771138,
        0.04018610332193427,
        0.02994968840576414,
        0.039723119080665996,
        0.019749284539029226,
        0.01977428370611838,
        0.019799282873207532,
        0.019749304525176935,
    ]
    var car = _pose(0, 0, 0, 0)
    for i in range(len(ys)):
        var out = pid.run_step(_pose(10, Float32(ys[i]), 0, 0), car)
        assert_almost_equal(out, expected[i], atol=1e-5)
    # Behind and to the right: clamped to 1. On the car: an error of 1.
    assert_almost_equal(pid.run_step(_pose(-3, 2, 0, 0), car), 1.0, atol=1e-9)
    assert_almost_equal(pid.run_step(_pose(0, 0, 0, 0), car), -1.0, atol=1e-9)
    pid.change_parameters(PIDGains(1, 0, 0, Duration(0.03, SECOND)))
    assert_equal(pid.gains.k_p, 1)


def test_lateral_offset() raises:
    # A waypoint facing +y moves 1 m along its right vector, (-1, 0):
    # (9, 0) is dead ahead. Facing +x it moves to (10, 1): atan(0.1).
    var pid = PIDLateralController(Length(1, METER))
    var car = _pose(0, 0, 0, 0)
    assert_almost_equal(pid.run_step(_pose(10, 0, 0, 90), car), 0, atol=1e-6)
    assert_almost_equal(
        pid.run_step(_pose(10, 0, 0, 0), car), 0.09966865249116186, atol=1e-6
    )
    pid.set_offset(Length(0, METER))
    assert_equal(pid.offset.value, 0)


def test_vehicle_pid() raises:
    var lateral = PIDGains(1.95, 0.05, 0.2, Duration(0.05, SECOND))
    var longitudinal = PIDGains(1.5, 0.05, 0.2, Duration(0.05, SECOND))
    var pid = VehiclePIDController(lateral, longitudinal)
    var car = _pose(0, 0, 0, 0)
    var speeds = [0.0, 10.0, 30.0, 30.0, 20.0]
    var ys = [3.0, 3.0, -3.0, -3.0, 0.0]
    var throttle = [0.75, 0.0, 0.0, 0.0, 0.75]
    var brake = [0.0, 0.3, 0.3, 0.3, 0.0]
    var steer = [0.1, 0.2, 0.1, 0.0, 0.1]
    for i in range(5):
        var c = pid.run_step(
            from_kmh(20),
            _pose(10, Float32(ys[i]), 0, 0),
            car,
            from_kmh(speeds[i]),
        )
        assert_almost_equal(Float64(c.throttle), throttle[i], atol=1e-6)
        assert_almost_equal(Float64(c.brake), brake[i], atol=1e-6)
        assert_almost_equal(Float64(c.steer), steer[i], atol=1e-6)
        assert_false(c.hand_brake)
        assert_false(c.manual_gear_shift)
    # The steering stops at `max_steering` on each side.
    var tight = VehiclePIDController(
        lateral, longitudinal, Length(0, METER), 0.75, 0.3, 0.05, 0.0
    )
    var right = tight.run_step(
        from_kmh(20), _pose(1, 5, 0, 0), car, from_kmh(20)
    )
    assert_almost_equal(right.steer, 0.05, atol=1e-7)
    var left = tight.run_step(
        from_kmh(20), _pose(1, -5, 0, 0), car, from_kmh(20)
    )
    assert_almost_equal(left.steer, -0.05, atol=1e-7)
    tight.change_longitudinal_pid(PIDGains(2, 0, 0, Duration(0.05, SECOND)))
    tight.change_lateral_pid(PIDGains(3, 0, 0, Duration(0.05, SECOND)))
    tight.set_offset(Length(0.5, METER))
    assert_equal(tight.longitudinal.gains.k_p, 2)
    assert_equal(tight.lateral.gains.k_p, 3)
    assert_equal(tight.lateral.offset.value, 0.5)


# --- local planner --------------------------------------------------------------------


def test_compute_connection() raises:
    # (yaw now, yaw next) -> CARLA's `_compute_connection`.
    var now = [0.0, 0.0, 0.0, 350.0, -170.0, 90.0, 0.0]
    var next = [10.0, 80.0, 280.0, 10.0, 175.0, 200.0, 150.0]
    var expected = [3, 2, 1, 3, 3, 1, 3]
    for i in range(len(now)):
        var got = compute_connection(
            _pose(0, 0, 0, Float32(now[i])), _pose(0, 0, 0, Float32(next[i]))
        )
        assert_equal(got.value, expected[i])


def test_plan_item_checks_its_option() raises:
    var map = _town()
    var w = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 10.0)
    var item = plan_item(map, w, OPTION_STRAIGHT)
    assert_almost_equal(item.transform.location.x, 10, atol=1e-5)
    with assert_raises(contains="Road option is not valid"):
        _ = plan_item(map, w, RoadOption(9))


def test_retrieve_options_at_the_fork() raises:
    # Three metres into road 11 the arc has turned 3.9 / 20 rad = 11
    # degrees: CARLA calls every branch straight.
    var map = _town()
    var last = Waypoint(RoadId(1), SectionId(1), LaneId(-1), 58.9)
    var nexts = map.next(last, 2.0)
    assert_equal(len(nexts), 3)
    var options = retrieve_options(map, nexts, last)
    for o in options:
        assert_equal(o.value, OPTION_STRAIGHT.value)
    # A lane that ends gives no waypoint 3 m on.
    var dead = List[Waypoint]()
    dead.append(Waypoint(RoadId(2), SectionId(0), LaneId(-1), 38.5))
    with assert_raises(contains="No waypoint lies 3 m past"):
        _ = retrieve_options(map, dead, last)


def test_local_planner_first_step() raises:
    # CARLA's Python planner, from rest at (5.3, 1.75): it plans 60
    # waypoints to the end of road 2, drops the two within 3 m, and
    # steers for s = 9.3 at full throttle, 0.75.
    var world = _world(_town())
    var car = _car(world, 5.3, 1.75)
    var planner = LocalPlanner(world, car)
    assert_equal(len(planner.queue), 1)
    assert_almost_equal(planner.queue[0].waypoint.s, 5.3, atol=1e-5)
    var c = planner.run_step(world)
    assert_equal(len(planner.queue), 61)
    assert_almost_equal(planner.target.waypoint.s, 9.3, atol=1e-5)
    assert_equal(planner.target.road_option.value, OPTION_LANE_FOLLOW.value)
    assert_almost_equal(c.throttle, 0.75, atol=1e-6)
    assert_almost_equal(c.steer, 0, atol=1e-6)
    assert_equal(c.brake, 0)
    assert_almost_equal(planner.min_distance.value, 3, atol=1e-6)
    var forks = 0
    for item in planner.queue:
        if item.road_option.value != OPTION_LANE_FOLLOW.value:
            forks += 1
            assert_equal(item.waypoint.road_id.value, 10)
            assert_almost_equal(item.waypoint.s, 1.3, atol=1e-4)
    assert_equal(forks, 1)
    var last = planner.queue[len(planner.queue) - 1].waypoint
    assert_equal(last.road_id.value, 2)
    assert_almost_equal(last.s, 39.3, atol=1e-4)
    var ahead = planner.get_incoming_waypoint_and_direction()
    assert_almost_equal(ahead.value().waypoint.s, 15.3, atol=1e-4)
    var far = planner.get_incoming_waypoint_and_direction(100)
    assert_almost_equal(far.value().waypoint.s, 39.3, atol=1e-4)
    assert_equal(len(planner.get_plan()), 61)
    assert_false(planner.done())


def test_local_planner_reach_grows_with_speed() raises:
    # At 10 m/s the reach is 3 + 0.5 * 10 = 8 m: the target is s = 13.3.
    # The speed error is 20 - 36 km/h, so the planner brakes at 0.3.
    var world = _world(_town())
    var car = _car(world, 5.3, 1.75)
    world.set_target_velocity(car, Vector3(10, 0, 0))
    var planner = LocalPlanner(world, car)
    var c = planner.run_step(world)
    assert_equal(len(planner.queue), 59)
    assert_almost_equal(planner.target.waypoint.s, 13.3, atol=1e-5)
    assert_almost_equal(planner.min_distance.value, 8, atol=1e-5)
    assert_equal(c.throttle, 0)
    assert_almost_equal(c.brake, 0.3, atol=1e-6)


def test_local_planner_end_of_the_road() raises:
    # At s = 35.3 on road 2 the lane ends 4.7 m on: two more waypoints.
    # The last one stays until the car is within 1 m of it.
    var world = _world(_town())
    var car = _car(world, 125.3, 1.75)
    var options = LocalPlannerOptions()
    options.follow_speed_limits = True
    var planner = LocalPlanner(world, car, options)
    _ = planner.run_step(world)
    assert_equal(len(planner.queue), 1)
    assert_almost_equal(planner.target.waypoint.s, 39.3, atol=1e-4)
    # The speed limit before any sign is 30 km/h.
    assert_almost_equal(kmh(planner.target_speed), 30, atol=1e-3)
    planner.follow_speed_limits(False)
    planner.set_speed(from_kmh(15))
    assert_almost_equal(kmh(planner.target_speed), 15, atol=1e-4)
    world.set_location(car, Vector3(129.0, 1.75, 0.3))
    var stop = planner.run_step(world)
    assert_true(planner.done())
    assert_equal(stop.brake, 1)
    assert_equal(stop.throttle, 0)
    assert_false(Bool(planner.get_incoming_waypoint_and_direction()))
    # Automatic generation remains enabled, but exhaustion is stable.
    assert_false(planner.stop_waypoint_creation)
    for _ in range(3):
        stop = planner.run_step(world)
        assert_equal(stop.brake, 1)
        assert_equal(stop.throttle, 0)
        assert_true(planner.done())
    planner.compute_next_waypoints(world.map, 5)
    assert_true(planner.done())
    # A planner with no waypoint creation keeps an empty queue.
    planner.set_offset(Length(0.5, METER))
    assert_equal(planner.controller.lateral.offset.value, 0.5)


def test_local_planner_global_plan() raises:
    var world = _world(_town())
    var car = _car(world, 5.3, 1.75)
    var planner = LocalPlanner(world, car)
    var plan = List[PlanItem]()
    for s in [20.0, 22.0, 24.0]:
        plan.append(
            plan_item(
                world.map,
                Waypoint(RoadId(1), SectionId(0), LaneId(-1), s),
                OPTION_LANE_FOLLOW,
            )
        )
    planner.set_global_plan(plan)
    assert_equal(len(planner.queue), 3)
    assert_true(planner.stop_waypoint_creation)
    planner.set_global_plan(plan, False, False)
    assert_equal(len(planner.queue), 6)
    assert_false(planner.stop_waypoint_creation)
    # A plan longer than the queue's limit raises the limit.
    planner.max_queue_length = 7
    planner.set_global_plan(plan, True, False)
    assert_equal(planner.max_queue_length, 9)
    assert_equal(len(planner.queue), 9)
    # With creation stopped, a step does not add waypoints.
    _ = planner.run_step(world)
    assert_equal(len(planner.queue), 9)
    # A full queue takes no more.
    planner.compute_next_waypoints(world.map, 5)
    assert_equal(len(planner.queue), 9)


def test_local_planner_needs_a_vehicle_on_a_road() raises:
    var world = _world(load_opendrive("<OpenDRIVE/>"))
    var bp = world.blueprints.at("vehicle.lincoln.mkz")
    var car = world.spawn_actor(bp, _pose(0, 0, 0.3, 0))
    with assert_raises(contains="not on a driving lane"):
        _ = LocalPlanner(world, car)


# --- global route planner --------------------------------------------------------------


comptime _RIGHT_TURN = "1,0,-1,6,4;1,0,-1,8,4;1,0,-1,10,4;1,0,-1,12,4;1,0,-1,14,4;1,0,-1,16,4;1,0,-1,18,4;1,0,-1,20,4;1,0,-1,22,4;1,0,-1,24,4;1,0,-1,26,4;1,1,-1,30,4;1,1,-1,30,4;1,1,-1,32,4;1,1,-1,34,4;1,1,-1,36,4;1,1,-1,38,4;1,1,-1,40,4;1,1,-1,42,4;1,1,-1,44,4;1,1,-1,46,4;1,1,-1,48,4;1,1,-1,50,4;1,1,-1,52,4;1,1,-1,54,4;1,1,-1,56,4;1,1,-1,58,4;10,0,-1,0,4;11,0,-1,0,2;11,0,-1,2,2;11,0,-1,4,2;11,0,-1,6,2;11,0,-1,8,2;11,0,-1,10,2;11,0,-1,12,2;11,0,-1,14,2;11,0,-1,16,2;11,0,-1,18,2;11,0,-1,20,2;11,0,-1,22,2;11,0,-1,24,2;11,0,-1,26,2;11,0,-1,28,2;3,0,-1,0,2;3,0,-1,0,4;3,0,-1,2,4;3,0,-1,4,4;3,0,-1,6,4;3,0,-1,8,4;3,0,-1,10,4;3,0,-1,12,4"

comptime _STRAIGHT = "1,0,-1,6,4;1,0,-1,8,4;1,0,-1,10,4;1,0,-1,12,4;1,0,-1,14,4;1,0,-1,16,4;1,0,-1,18,4;1,0,-1,20,4;1,0,-1,22,4;1,0,-1,24,4;1,0,-1,26,4;1,1,-1,30,4;1,1,-1,30,4;1,1,-1,32,4;1,1,-1,34,4;1,1,-1,36,4;1,1,-1,38,4;1,1,-1,40,4;1,1,-1,42,4;1,1,-1,44,4;1,1,-1,46,4;1,1,-1,48,4;1,1,-1,50,4;1,1,-1,52,4;1,1,-1,54,4;1,1,-1,56,4;1,1,-1,58,4;10,0,-1,0,4;10,0,-1,0,3;10,0,-1,2,3;10,0,-1,4,3;10,0,-1,6,3;10,0,-1,8,3;10,0,-1,10,3;10,0,-1,12,3;10,0,-1,14,3;10,0,-1,16,3;10,0,-1,18,3;10,0,-1,20,3;10,0,-1,22,3;10,0,-1,24,3;10,0,-1,26,3;2,0,-1,0,3;2,0,-1,0,4;2,0,-1,2,4;2,0,-1,4,4;2,0,-1,6,4;2,0,-1,8,4;2,0,-1,10,4;2,0,-1,12,4;2,0,-1,14,4;2,0,-1,16,4;2,0,-1,18,4"

comptime _WEST = "2,0,1,30,4;2,0,1,28,4;2,0,1,26,4;2,0,1,24,4;2,0,1,22,4;2,0,1,20,4;2,0,1,18,4;2,0,1,16,4;2,0,1,14,4;2,0,1,12,4;2,0,1,10,4;2,0,1,8,4;2,0,1,6,4;2,0,1,4,4;10,0,1,30,4;10,0,1,30,3;10,0,1,28,3;10,0,1,26,3;10,0,1,24,3;10,0,1,22,3;10,0,1,20,3;10,0,1,18,3;10,0,1,16,3;10,0,1,14,3;10,0,1,12,3;10,0,1,10,3;10,0,1,8,3;10,0,1,6,3;10,0,1,4,3;1,1,1,60,3;1,1,1,60,4;1,1,1,58,4;1,1,1,56,4;1,1,1,54,4;1,1,1,52,4;1,1,1,50,4;1,1,1,48,4;1,1,1,46,4;1,1,1,44,4;1,1,1,42,4;1,1,1,40,4;1,1,1,38,4;1,1,1,36,4;1,1,1,34,4;1,0,1,30,4;1,0,1,30,4;1,0,1,28,4;1,0,1,26,4;1,0,1,24,4;1,0,1,22,4;1,0,1,20,4;1,0,1,18,4;1,0,1,16,4;1,0,1,14,4"

comptime _SHORT = "1,0,-1,20,4;1,0,-1,22,4;1,0,-1,24,4;1,0,-1,26,4;1,1,-1,30,4;1,1,-1,30,4;1,1,-1,32,4;1,1,-1,34,4;1,1,-1,36,4;1,1,-1,38,4"


def test_round_half_even() raises:
    assert_equal(round_half_even(2.5), 2)
    assert_equal(round_half_even(3.5), 4)
    assert_equal(round_half_even(-2.5), -2)
    assert_equal(round_half_even(1.75), 2)
    assert_equal(round_half_even(-0.4), 0)
    assert_equal(round_half_even(0.49), 0)


def test_route_on_the_town() raises:
    var map = _town()
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    var right = grp.trace_route(
        map, Vector3(5.3, 1.75, 0), Vector3(78.25, 35.3, 0)
    )
    assert_equal(_route(right), _RIGHT_TURN)
    var straight = grp.trace_route(
        map, Vector3(5.3, 1.75, 0), Vector3(110.3, 1.75, 0)
    )
    assert_equal(_route(straight), _STRAIGHT)
    var west = grp.trace_route(
        map, Vector3(120.3, -1.75, 0), Vector3(10.3, -1.75, 0)
    )
    assert_equal(_route(west), _WEST)
    var short = grp.trace_route(
        map, Vector3(20.3, 1.75, 0), Vector3(40.3, 1.75, 0)
    )
    assert_equal(_route(short), _SHORT)
    # Road 3 ends the network: nothing leads back.
    var none = grp.trace_route(
        map, Vector3(78.25, 30.3, 0), Vector3(10.3, 1.75, 0)
    )
    assert_equal(len(none), 0)


def test_route_nodes_on_the_town() raises:
    # Retained road 3 topology gives a regular rounded terminal node,
    # instead of an unrounded loose end recovered from lane samples.
    # Road 3/-1 ends at CARLA (78.25, 50): rounding gives (78, 50).
    var map = _town()
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    var nodes = grp.path_search(
        map, Vector3(5.3, 1.75, 0), Vector3(78.25, 35.3, 0)
    )
    var xs = [0.0, 30.0, 60.0, 78.0, 78.0]
    var ys = [2.0, 2.0, 2.0, 20.0, 50.0]
    assert_equal(len(nodes), 5)
    for i in range(5):
        var v = grp.vertex(nodes[i])
        assert_almost_equal(Float64(v.x), xs[i], atol=1e-4)
        assert_almost_equal(Float64(v.y), ys[i], atol=1e-4)
    assert_true(nodes[4].value >= 0)
    # The piece of road 1 before the junction: 14 samples, s = 32 to 58.
    var edge = grp.edge(nodes[1], nodes[2])
    assert_equal(edge.length, 15)
    assert_true(edge.type == OPTION_LANE_FOLLOW)
    assert_false(edge.intersection)
    assert_true(grp.edge(nodes[2], nodes[3]).intersection)
    var successors = grp.successors(nodes[2])
    assert_equal(len(successors), 2)
    assert_true(grp.node_count() > 0)
    assert_true(grp.edge_count() > 0)
    var here = grp.localize(map, Vector3(5.3, 1.75, 0)).value()
    assert_equal(here[0].value, nodes[0].value)
    assert_equal(here[1].value, nodes[1].value)
    with assert_raises(contains="no such node"):
        _ = grp.vertex(RouteNodeId(-50))
    with assert_raises(contains="Route node id is not valid"):
        _ = grp.vertex(RouteNodeId(1 << 40))
    with assert_raises(contains="no such edge"):
        _ = grp.edge(nodes[0], nodes[4])
    with assert_raises(contains="no such edge"):
        _ = grp.edge(RouteNodeId(-50), nodes[4])
    with assert_raises(contains="Route node id is not valid"):
        _ = grp.edge(RouteNodeId(1 << 40), nodes[4])


def test_turn_decisions() raises:
    var map = _town()
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    var nodes = grp.path_search(
        map, Vector3(5.3, 1.75, 0), Vector3(78.25, 35.3, 0)
    )
    assert_equal(grp.turn_decision(0, nodes).value, OPTION_LANE_FOLLOW.value)
    assert_equal(grp.turn_decision(1, nodes).value, OPTION_LANE_FOLLOW.value)
    assert_equal(grp.turn_decision(2, nodes).value, OPTION_RIGHT.value)
    assert_equal(grp.turn_decision(3, nodes).value, OPTION_LANE_FOLLOW.value)
    # A threshold past the 90-degree turn calls it straight.
    assert_equal(
        grp.turn_decision(2, nodes, Angle(95, DEGREE)).value,
        OPTION_STRAIGHT.value,
    )
    with assert_raises(contains="no step at that index"):
        _ = grp.turn_decision(4, nodes)
    with assert_raises(contains="no step at that index"):
        _ = grp.turn_decision(-1, nodes)


def test_route_planner_checks_its_resolution() raises:
    with assert_raises(contains="more than zero"):
        _ = GlobalRoutePlanner(_town(), Length(0, METER))


def test_route_on_an_empty_map() raises:
    var map = load_opendrive("<OpenDRIVE/>")
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    assert_equal(grp.node_count(), 0)
    assert_false(Bool(grp.localize(map, Vector3(0, 0, 0))))
    assert_equal(
        len(grp.trace_route(map, Vector3(0, 0, 0), Vector3(1, 0, 0))), 0
    )


# --- lane changes --------------------------------------------------------------------


comptime _CHANGE_RIGHT = "1,-1,5.3,6;1,-2,16,6;1,-2,16,4;1,-2,18,4;1,-2,20,4;1,-2,22,4;1,-2,24,4;1,-2,26,4;1,-2,28,4;1,-2,30,4;1,-2,32,4;1,-2,34,4;1,-2,36,4;1,-2,38,4;1,-2,40,4;1,-2,42,4;1,-2,44,4;1,-2,46,4;2,-2,0,4;2,-2,0,4;2,-2,2,4;2,-2,4,4;2,-2,6,4;2,-2,8,4;2,-2,10,4;2,-2,12,4;2,-2,14,4;2,-2,16,4;2,-2,18,4;2,-2,20,4;2,-2,22,4;2,-2,24,4;2,-2,26,4;2,-2,28,4"

comptime _CHANGE_LEFT = "1,-2,5.3,5;1,-1,16,5;1,-1,16,4;1,-1,18,4;1,-1,20,4;1,-1,22,4;1,-1,24,4;1,-1,26,4;1,-1,28,4;1,-1,30,4;1,-1,32,4;1,-1,34,4;1,-1,36,4;1,-1,38,4;1,-1,40,4;1,-1,42,4;1,-1,44,4;1,-1,46,4;2,-1,0,4;2,-1,0,4;2,-1,2,4;2,-1,4,4;2,-1,6,4;2,-1,8,4;2,-1,10,4;2,-1,12,4;2,-1,14,4;2,-1,16,4;2,-1,18,4;2,-1,20,4;2,-1,22,4;2,-1,24,4;2,-1,26,4;2,-1,28,4"


def test_lane_change_edges() raises:
    # Lane -1 may cross right to lane -2 and lane -2 left to lane -1: one
    # edge of weight zero each way, between the pieces' entries.
    var map = load_opendrive(TWO_LANE)
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    var a = grp.localize(map, Vector3(5.3, 1.75, 0)).value()[0]
    var b = grp.localize(map, Vector3(5.3, 5.25, 0)).value()[0]
    var right = grp.edge(a, b)
    assert_equal(right.type.value, OPTION_CHANGE_LANE_RIGHT.value)
    assert_equal(right.length, 0)
    assert_equal(len(right.path), 0)
    assert_equal(right.change_waypoint.value().lane_id.value, -2)
    var left = grp.edge(b, a)
    assert_equal(left.type.value, OPTION_CHANGE_LANE_LEFT.value)
    # Four lane-follow pieces plus two lane-change edges per road.
    # Retained road 2/-1 and 2/-2 now supply its broken-mark crossings.
    assert_equal(grp.edge_count(), 8)
    var a2 = grp.localize(map, Vector3(60, 1.75, 0)).value()[0]
    var b2 = grp.localize(map, Vector3(60, 5.25, 0)).value()[0]
    assert_equal(grp.edge(a2, b2).type.value, OPTION_CHANGE_LANE_RIGHT.value)
    assert_equal(grp.edge(b2, a2).type.value, OPTION_CHANGE_LANE_LEFT.value)
    # Twenty-three samples at s=2,4,...,46 give each forward edge
    # weight 24. An early change costs 0+24; a late change costs 24+0.
    # Both are minimum routes. The zero-cost neighbor is expanded first
    # and reaches the destination entry before the equal-cost alternative.
    # Strict relaxation retains that first predecessor.
    assert_equal(grp.edge(a, a2).length, 24)
    assert_equal(grp.edge(b, b2).length, 24)
    var right_nodes = grp.path_search(
        map, Vector3(5.3, 1.75, 0), Vector3(80.3, 5.25, 0)
    )
    assert_equal(len(right_nodes), 4)
    assert_equal(right_nodes[0], a)
    assert_equal(right_nodes[1], b)
    assert_equal(right_nodes[2], b2)
    var left_nodes = grp.path_search(
        map, Vector3(5.3, 5.25, 0), Vector3(80.3, 1.75, 0)
    )
    assert_equal(len(left_nodes), 4)
    assert_equal(left_nodes[0], b)
    assert_equal(left_nodes[1], a)
    assert_equal(left_nodes[2], a2)
    # This deliberately differs from CARLA's Euclidean search, which
    # deferred the equally costly lane change. Projected origin s=5.3
    # has nearest sample s=6; the five-sample hop ends at s=16 on road 1.
    # The trace follows road 1 to its exit, then road 2 from s=0 to s=28.
    # The piece boundary appears twice, once as exit and once as entry.
    var to_right = grp.trace_route(
        map, Vector3(5.3, 1.75, 0), Vector3(80.3, 5.25, 0)
    )
    assert_equal(_short(to_right), _CHANGE_RIGHT)
    var to_left = grp.trace_route(
        map, Vector3(5.3, 5.25, 0), Vector3(80.3, 1.75, 0)
    )
    assert_equal(_short(to_left), _CHANGE_LEFT)


# --- odd corners -----------------------------------------------------------------------


comptime _ODD_STUB = "1,0,-1,6,4;1,0,-1,8,4;1,0,-1,10,4;1,0,-1,12,4;1,0,-1,14,4;1,0,-1,16,4;13,0,-1,0,4;10,0,-1,0,3;10,0,-1,2,3;10,0,-1,4,3;10,0,-1,6,3;10,0,-1,8,3;2,0,-1,0,3"

comptime _ODD_RIGHT = "1,0,-1,6,4;1,0,-1,8,4;1,0,-1,10,4;1,0,-1,12,4;1,0,-1,14,4;1,0,-1,16,4;13,0,-1,0,4;13,0,-1,0,2;13,0,-1,2,2;13,0,-1,4,2;14,0,-1,0,2;14,0,-1,0,2;14,0,-1,2,2;3,0,-1,0,2;3,0,-1,0,4;3,0,-1,2,4;3,0,-1,4,4;3,0,-1,6,4;3,0,-1,8,4"

comptime _ODD_FAR = "1,0,-1,6,4;1,0,-1,8,4;1,0,-1,10,4;1,0,-1,12,4;1,0,-1,14,4;1,0,-1,16,4;1,0,-1,18,4;10,0,-1,0,4;10,0,-1,2,4;10,0,-1,4,4;10,0,-1,6,4;10,0,-1,8,4;10,0,-1,10,4;2,0,-1,0,4;11,0,-1,0,4;11,0,-1,0,3"


def test_odd_routes() raises:
    # To the stub: straight through road 10. The stub's lane piece has no
    # sample, so its loose end has no edge: the last step is skipped.
    var map = load_opendrive(ODD)
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    assert_equal(
        _route(
            grp.trace_route(map, Vector3(5.3, 1.75, 0), Vector3(32.5, 1.75, 0))
        ),
        _ODD_STUB,
    )
    # The planner keeps its last decision and the end of the last
    # junction between calls, as CARLA's does: a second route through
    # the same junction entry keeps the stale lane follow.
    var stale = grp.trace_route(
        map, Vector3(5.3, 1.75, 0), Vector3(23.25, 20.3, 0)
    )
    assert_equal(stale[7].road_option.value, OPTION_LANE_FOLLOW.value)
    # A fresh planner turns right onto the arc; road 14 is in the
    # junction too, so it keeps the decision; road 3 follows its lane.
    var fresh = GlobalRoutePlanner(map, Length(2, METER))
    assert_equal(
        _route(
            fresh.trace_route(
                map, Vector3(5.3, 1.75, 0), Vector3(23.25, 20.3, 0)
            )
        ),
        _ODD_RIGHT,
    )
    # Road 11 is linked but far away. Its lane piece's samples follow the
    # first way on, road 10, to the stub's dead end. Retained road 11/-1
    # has an east-facing exit vector, so the final junction decision is
    # straight (3), not the vector-less loose end's lane follow (4).
    var far = GlobalRoutePlanner(map, Length(2, METER))
    var far_nodes = far.localize(map, Vector3(202.3, 1.75, 0)).value()
    var far_edge = far.edge(far_nodes[0], far_nodes[1])
    assert_equal(far_edge.entry_waypoint.road_id, RoadId(11))
    assert_equal(far_edge.exit_waypoint.road_id, RoadId(11))
    assert_true(Bool(far_edge.exit_vector))
    assert_almost_equal(far_edge.exit_vector.value().x, 1.0, atol=1e-5)
    assert_almost_equal(far_edge.exit_vector.value().y, 0.0, atol=1e-5)
    assert_equal(
        _route(
            far.trace_route(map, Vector3(5.3, 1.75, 0), Vector3(202.3, 1.75, 0))
        ),
        _ODD_FAR,
    )
    # Road 20 is 3 m long: its piece has no sample between its ends.
    assert_equal(
        _route(
            far.trace_route(
                map, Vector3(0.5, -98.25, 0), Vector3(3.5, -98.25, 0)
            )
        ),
        "20,0,-1,0,4;21,0,-1,0,4;21,0,-1,0,4",
    )


def test_odd_graph() raises:
    var map = load_opendrive(ODD)
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    # Lanes -1 to -3 change into each other; lane -1 has no lane to its
    # left. Retained lane -4 adds a right-change edge from lane -3.
    var l1 = grp.localize(map, Vector3(5.3, 1.75, 0)).value()[0]
    var l2 = grp.localize(map, Vector3(5.3, 5.25, 0)).value()[0]
    var l3 = grp.localize(map, Vector3(5.3, 8.75, 0)).value()[0]
    assert_equal(grp.edge(l1, l2).type.value, OPTION_CHANGE_LANE_RIGHT.value)
    assert_equal(grp.edge(l2, l1).type.value, OPTION_CHANGE_LANE_LEFT.value)
    assert_equal(grp.edge(l2, l3).type.value, OPTION_CHANGE_LANE_RIGHT.value)
    assert_equal(grp.edge(l3, l2).type.value, OPTION_CHANGE_LANE_LEFT.value)
    var l4 = grp.localize(map, Vector3(5.3, 12.25, 0)).value()[0]
    assert_equal(grp.edge(l3, l4).type.value, OPTION_CHANGE_LANE_RIGHT.value)
    assert_equal(grp.edge(l4, l3).type.value, OPTION_CHANGE_LANE_LEFT.value)
    assert_equal(len(grp.successors(l3)), 3)
    # Roads 6 and 7 are shorter than one step together: no lane piece.
    assert_false(Bool(grp.localize(map, Vector3(0.2, -48.25, 0))))
    # A terminal lane endpoint has no edge out.
    var nodes = grp.path_search(
        map, Vector3(5.3, 1.75, 0), Vector3(23.25, 20.3, 0)
    )
    assert_equal(len(grp.successors(nodes[4])), 0)


def test_route_within_one_piece() raises:
    # Both ends on road 1's first piece: from the sample nearest s = 10.3
    # to the first within 4 m of s = 20.3.
    var map = _town()
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    var plan = grp.trace_route(
        map, Vector3(10.3, 1.75, 0), Vector3(20.3, 1.75, 0)
    )
    assert_equal(
        _route(plan),
        "1,0,-1,10,4;1,0,-1,12,4;1,0,-1,14,4;1,0,-1,16,4;1,0,-1,18,4",
    )
    assert_equal(
        grp._find_closest_in_list(map, plan[0].waypoint, List[Waypoint]()),
        -1,
    )


def _graph() raises -> GlobalRoutePlanner:
    # An empty planner to hold a hand-made graph.
    return GlobalRoutePlanner(load_opendrive("<OpenDRIVE/>"), Length(2, METER))


def _node(mut grp: GlobalRoutePlanner, x: Float64, y: Float64) -> Int:
    return grp._node_of(String(x, ",", y), SIMD[DType.float64, 4](x, y, 0, 0))


def _link(mut grp: GlobalRoutePlanner, a: Int, b: Int, length: Int) raises:
    var w = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 0.0)
    var e = grp._add_edge(a, b, w, w)
    grp._edges[e].length = length


def _linear_route(
    grp: GlobalRoutePlanner, source: Int, target: Int
) raises -> List[RouteNodeId]:
    """A linear-selection uniform-cost search for heap parity checks."""
    # This oracle checks heap ordering, not shortest-path correctness.
    # The independent all-pairs oracle lives in test_carla_route_search.
    var out = List[RouteNodeId]()
    var open = List[Tuple[Int64, Int]]()
    var g = Dict[Int, Int64]()
    var came_from = Dict[Int, Int]()
    var closed = Dict[Int, Bool]()
    g[source] = 0
    open.append((Int64(0), source))
    while len(open) > 0:
        var best = 0
        for i in range(1, len(open)):
            if open[i][0] < open[best][0] or (
                open[i][0] == open[best][0] and open[i][1] < open[best][1]
            ):
                best = i
        var current = open.pop(best)[1]
        if current == target:
            var nodes = List[Int]()
            nodes.append(current)
            var n = current
            while n != source:
                n = came_from[n]
                nodes.append(n)
            # The list holds the target at least.
            for i in range(len(nodes) - 1, -1, -1):  # pragma: no branch
                out.append(RouteNodeId(nodes[i]))
            return out^
        if current in closed:
            continue
        closed[current] = True
        var g_current = g[current]
        for e in grp._nodes[grp._node_index[current]].out_edges:
            var neighbor = grp._edges[e].target.value
            var tentative = g_current + Int64(grp._edges[e].length)
            var known = g.get(neighbor)
            if not Bool(known) or tentative < known.value():
                g[neighbor] = tentative
                came_from[neighbor] = current
                open.append((tentative, neighbor))
    return out^


def test_heap_routes_match_linear_search_on_generated_graphs() raises:
    for seed in range(8):
        var grp = _graph()
        for i in range(32):
            _ = _node(grp, Float64(i) * 0.001, 0)
        for a in range(32):
            for b in range(32):
                if a == b or (b == 31 and seed % 4 == 0):
                    continue
                if (a * 7 + b * 13 + seed) % 11 < 2:
                    _link(grp, a, b, 1 + (a * 3 + b + seed) % 9)
        for start in range(4):
            var want = _linear_route(grp, start, 31)
            var got = grp._search(start, 31)
            assert_equal(len(got), len(want))
            for i in range(len(want)):
                assert_equal(got[i].value, want[i].value)


def test_search_ties_and_stale_entries() raises:
    # Ties: nodes 1 and 2 both cost 1 from the source. The lower id, 1,
    # comes out first, though it was pushed second.
    var grp = _graph()
    var s = _node(grp, 0, 0)
    var b = _node(grp, 3, 4)
    var a = _node(grp, 4, 3)
    var goal = _node(grp, 8, 8)
    _link(grp, s, a, 1)
    _link(grp, s, b, 1)
    _link(grp, b, goal, 1)
    _link(grp, a, goal, 1)
    var route = grp._search(s, goal)
    assert_equal(len(route), 3)
    assert_equal(route[1].value, b)
    # A stale entry: node y is pushed at 5, then at 2 through x; the old
    # entry comes out after y is closed and is skipped. A worse way to x
    # through y changes nothing.
    var h = _graph()
    var p = _node(h, 0, 0)
    var x = _node(h, 0, 0.1)
    var y = _node(h, 0, 0.2)
    var z = _node(h, 0, 0.3)
    _link(h, p, x, 1)
    _link(h, p, y, 5)
    _link(h, x, y, 1)
    _link(h, y, x, 1)
    _link(h, y, z, 10)
    var r = h._search(p, z)
    assert_equal(len(r), 4)
    assert_equal(r[2].value, y)
    # No way to the goal: nothing.
    assert_equal(len(h._search(z, p)), 0)
    # A second edge between the same nodes updates the first.
    _link(h, p, x, 3)
    assert_equal(h.edge(RouteNodeId(p), RouteNodeId(x)).length, 3)


def test_turn_options() raises:
    # Right of every other way, left of every one, straight within the
    # threshold, and the sign of the cross product in between.
    var none = List[Float64]()
    var rad = Angle(1.5, RADIAN)
    assert_equal(turn_option(Angle(0.5, RADIAN), 1, none).value, 3)
    assert_equal(turn_option(rad, 1, none).value, OPTION_RIGHT.value)
    assert_equal(turn_option(rad, -1, none).value, OPTION_LEFT.value)
    var both: List[Float64] = [-0.5, 0.5]
    assert_equal(turn_option(rad, 0.8, both).value, OPTION_RIGHT.value)
    assert_equal(turn_option(rad, -0.8, both).value, OPTION_LEFT.value)
    assert_equal(turn_option(rad, 0.2, both).value, OPTION_RIGHT.value)
    assert_equal(turn_option(rad, -0.2, both).value, OPTION_LEFT.value)
    assert_equal(turn_option(rad, 0, both).value, OPTION_VOID.value)


def test_local_planner_takes_a_random_fork() raises:
    # At the end of road 1 the ways on are straight, straight and, 3 m
    # into the arc of radius 5, 49 degrees right. The draw 0.899 of seed
    # 40000 picks the third option: the first with that option.
    var world = _world(load_opendrive(ODD))
    var car = _car(world, 5.3, 1.75)
    var planner = LocalPlanner(world, car, LocalPlannerOptions(), 40000)
    _ = planner.run_step(world)
    var turned = 0
    for item in planner.queue:
        if item.road_option.value == OPTION_RIGHT.value:
            turned += 1
            assert_equal(item.waypoint.road_id.value, 13)
    assert_equal(turned, 1)
    assert_equal(
        len(
            retrieve_options(
                world.map, List[Waypoint](), planner.queue[0].waypoint
            )
        ),
        0,
    )


def test_lane_change_onto_an_empty_piece() raises:
    # With the target piece's samples removed, the plan steps to its exit.
    var map = load_opendrive(TWO_LANE)
    var grp = GlobalRoutePlanner(map, Length(2, METER))
    var b = grp.localize(map, Vector3(5.3, 5.25, 0)).value()
    grp._edges[grp._edge_index(b[0].value, b[1].value)].path.clear()
    var plan = grp.trace_route(
        map, Vector3(5.3, 1.75, 0), Vector3(40.3, 5.25, 0)
    )
    assert_equal(plan[1].waypoint.road_id.value, 2)
    assert_equal(plan[1].waypoint.lane_id.value, -2)


def test_misc_speed_and_arc_cosine() raises:
    var world = _world(_town())
    var car = _car(world, 5.3, 1.75)
    world.set_target_velocity(car, Vector3(3, 4, 0))
    assert_almost_equal(get_speed(world, car).value, 5, atol=1e-5)
    assert_almost_equal(_acos_degrees(1.5), 0, atol=1e-12)
    assert_almost_equal(_acos_degrees(-1.5), 180, atol=1e-9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
