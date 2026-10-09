# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA world: traffic lights, stop, yield and speed-limit signs.

The test town is a cross. Road 1 runs east into junction 100 at x = 50,
road 10 goes on to road 2, and road 3 comes north into the junction
along x = 55 and goes on to road 4 through road 12. In CARLA's frame y
is the OpenDRIVE y negated, so road 3's right lane runs along
x = 56.75 toward minus y. Junction roads 13 and 15 stand far away and
hang off road 1 and road 13; road 14 turns from road 3 to road 2. Road
16, in junction 200, hangs off road 4.

Lights 2001, 2005, 2006 and 2008 belong to controller 1 and light 2002
to controller 2, both in junction 100. Light 2007 belongs to controller
4 in junction 200. Light 2004 is held by controller 3, which no junction
names, light 2003 by no controller, and light 2009, on a junction road,
by none, so it is not placed. Stop sign 3001 stands on junction road
12, stop sign 3006 on road 13, yield sign 3002 on road 4, and 60 and
50 km/h signs 3003 and 3007 on roads 2 and 13. Sign 3004 is painted on
the road and 3005 has a speed CARLA has no sign for. Lights 2008 and
signs 3006 and 3007 face lanes their roads do not have, so they get no
box.

The expected numbers come from outside this port:

- The poses of the lights, the signs and their boxes are worked by hand
  from the file: the signal's s and t, 3 m against the lane for a light
  box, 1.5 m by half a lane for its size.
- The stages of the lights and the give-way checks of the stop sign come
  from Python models of CARLA's `TrafficLightController.cpp`,
  `TrafficLightGroup.cpp` and `StopSignComponent.cpp`, run with the same
  0.25 s step.
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    NO_ACTOR,
    OFF,
    RED,
    TrafficLightState,
    UNKNOWN,
    YELLOW,
)
from extensions.carla.map import Waypoint
from extensions.carla.opendrive import load_opendrive
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.road_info import JuncId, LaneId, RoadId, SignalId
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.traffic_light import (
    TrafficLight,
    TrafficLightController,
    TrafficLightManager,
    TrafficLightStage,
    affected_lane_waypoints,
    default_stages,
    light_transform,
    stop_waypoints,
)
from extensions.carla.traffic_sign import (
    SPEED_LIMIT_SIGN,
    STOP_SIGN,
    SignKind,
    TrafficSign,
    TriggerBox,
    YIELD_SIGN,
    give_way_boxes,
    sign_kind_of,
    sign_type_id,
    signal_references,
    speed_limit_boxes,
    traffic_light_boxes,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from std.math import inf, nan
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
    Length64,
    Velocity,
)

comptime SPECTATOR = ActorId(1)
comptime L2001 = ActorId(2)
comptime L2005 = ActorId(3)
comptime L2006 = ActorId(4)
comptime L2008 = ActorId(5)
comptime L2002 = ActorId(6)
comptime L2004 = ActorId(7)
comptime L2007 = ActorId(8)
comptime L2003 = ActorId(9)
comptime STOP = ActorId(10)
comptime YIELD = ActorId(11)
comptime LIMIT = ActorId(12)
comptime FAR_STOP = ActorId(13)
comptime FAR_LIMIT = ActorId(14)


def _town() -> String:
    """The cross town: see the module docstring."""
    return """<?xml version="1.0" encoding="UTF-8"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="cross" version="1.0"/>
  <road name="west" length="50" id="1" junction="-1">
    <link><successor elementType="junction" elementId="100"/></link>
    <type s="0" type="town"><speed max="50" unit="km/h"/></type>
    <planView><geometry s="0" x="0" y="0" hdg="0" length="50"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left>
        <lane id="2" type="sidewalk"><width sOffset="0" a="2" b="0" c="0" d="0"/><height sOffset="0" inner="0.15" outer="0.15"/></lane>
        <lane id="1" type="driving"><link><predecessor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
      </left>
      <center><lane id="0" type="none"/></center>
      <right>
        <lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
        <lane id="-2" type="sidewalk"><width sOffset="0" a="2" b="0" c="0" d="0"/><height sOffset="0" inner="0.15" outer="0.15"/></lane>
      </right>
    </laneSection></lanes>
    <signals>
      <signal s="45" t="-5" id="2001" name="light" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-2" toLane="-1"/>
      </signal>
    </signals>
  </road>
  <road name="east" length="50" id="2" junction="-1">
    <link><predecessor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="60" y="0" hdg="0" length="50"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><successor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="20" t="-5" id="2003" name="lonely" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="1" toLane="-3"/>
      </signal>
      <signal s="30" t="-5" id="3003" name="limit" dynamic="no" orientation="+" zOffset="2" country="DE" type="274" subtype="60" value="60" unit="km/h" height="1" width="1" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
      <signal s="40" t="-5" id="3005" name="odd limit" dynamic="no" orientation="+" zOffset="2" country="DE" type="274" subtype="35" value="35" unit="km/h" height="1" width="1" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
    </signals>
  </road>
  <road name="south" length="40" id="3" junction="-1">
    <link><successor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="55" y="-50" hdg="1.5707963267948966" length="40"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><predecessor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="35" t="-5" id="2002" name="light" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="1"/>
      </signal>
    </signals>
  </road>
  <road name="north" length="40" id="4" junction="-1">
    <link><predecessor elementType="junction" elementId="100"/><successor elementType="junction" elementId="200"/></link>
    <planView><geometry s="0" x="55" y="10" hdg="1.5707963267948966" length="40"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><successor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="10" t="-5" id="3002" name="yield" dynamic="no" orientation="+" zOffset="2" country="OpenDRIVE" type="205" subtype="" value="0" height="1" width="1" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
      <signal s="30" t="-5" id="2004" name="orphan" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
      <signal s="20" t="-1.75" id="3004" name="Stencil_STOP" dynamic="no" orientation="+" zOffset="0" country="OpenDRIVE" type="206" subtype="" value="0" height="0" width="3" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
    </signals>
  </road>
  <road name="through" length="10" id="10" junction="100">
    <link>
      <predecessor elementType="road" elementId="1" contactPoint="end"/>
      <successor elementType="road" elementId="2" contactPoint="start"/>
    </link>
    <planView><geometry s="0" x="50" y="0" hdg="0" length="10"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><successor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="5" t="-5" id="2009" name="unheld" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
      <signalReference s="2" t="-5" id="2001" orientation="+">
        <validity fromLane="-1" toLane="-1"/>
      </signalReference>
    </signals>
  </road>
  <road name="across" length="20" id="12" junction="100">
    <link>
      <predecessor elementType="road" elementId="3" contactPoint="end"/>
      <successor elementType="road" elementId="4" contactPoint="start"/>
    </link>
    <planView><geometry s="0" x="55" y="-10" hdg="1.5707963267948966" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><predecessor id="1"/><successor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="1" t="-8" id="3001" name="stop" dynamic="no" orientation="+" zOffset="2" country="OpenDRIVE" type="206" subtype="" value="0" height="1" width="1" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
    </signals>
  </road>
  <road name="far" length="10" id="13" junction="100">
    <link><predecessor elementType="road" elementId="1" contactPoint="end"/><successor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="200" y="200" hdg="0" length="10"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="2" t="-5" id="2005" name="far light" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
      <signal s="5" t="-5" id="3006" name="far stop" dynamic="no" orientation="+" zOffset="2" country="OpenDRIVE" type="206" subtype="" value="0" height="1" width="1" hOffset="0" pitch="0" roll="0"/>
      <signal s="7" t="-5" id="3007" name="far limit" dynamic="no" orientation="+" zOffset="2" country="DE" type="274" subtype="50" value="50" unit="km/h" height="1" width="1" hOffset="0" pitch="0" roll="0"/>
    </signals>
  </road>
  <road name="diagonal" length="14.142135623730951" id="14" junction="100">
    <link>
      <predecessor elementType="road" elementId="3" contactPoint="end"/>
      <successor elementType="road" elementId="2" contactPoint="start"/>
    </link>
    <planView><geometry s="0" x="55" y="-10" hdg="0.7853981633974483" length="14.142135623730951"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="farther" length="10" id="15" junction="100">
    <link><predecessor elementType="road" elementId="13" contactPoint="end"/></link>
    <planView><geometry s="0" x="300" y="300" hdg="0" length="10"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="2" t="-5" id="2006" name="chained light" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
      <signal s="5" t="-5" id="2008" name="leftless light" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0"/>
    </signals>
  </road>
  <road name="beyond" length="10" id="16" junction="200">
    <link><predecessor elementType="road" elementId="4" contactPoint="end"/></link>
    <planView><geometry s="0" x="400" y="400" hdg="0" length="10"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="5" t="-5" id="2007" name="second junction" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
    </signals>
  </road>
  <junction id="100" name="cross">
    <connection id="0" incomingRoad="1" connectingRoad="10" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <connection id="1" incomingRoad="2" connectingRoad="10" contactPoint="end"><laneLink from="1" to="1"/></connection>
    <connection id="2" incomingRoad="3" connectingRoad="12" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <connection id="3" incomingRoad="4" connectingRoad="12" contactPoint="end"><laneLink from="1" to="1"/></connection>
    <connection id="4" incomingRoad="1" connectingRoad="13" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <connection id="5" incomingRoad="3" connectingRoad="14" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <connection id="6" incomingRoad="13" connectingRoad="15" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <controller id="1" type="0"/>
    <controller id="2" type="0"/>
  </junction>
  <junction id="200" name="second">
    <connection id="0" incomingRoad="4" connectingRoad="16" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <controller id="4" type="0"/>
    <controller id="5" type="0"/>
  </junction>
  <controller id="1" name="west" sequence="0"><control signalId="2001" type="0"/><control signalId="2005" type="0"/><control signalId="2006" type="0"/><control signalId="2008" type="0"/></controller>
  <controller id="2" name="south" sequence="1"><control signalId="2002" type="0"/></controller>
  <controller id="3" name="nowhere" sequence="2"><control signalId="9999" type="0"/><control signalId="3001" type="0"/><control signalId="2004" type="0"/><control signalId="2001" type="0"/></controller>
  <controller id="4" name="second" sequence="0"><control signalId="2007" type="0"/><control signalId="3002" type="0"/></controller>
  <controller id="5" name="empty" sequence="1"/>
</OpenDRIVE>
"""


def _edge() -> String:
    """The edge town: see `test_edge_town_check_boxes`."""
    return """<?xml version="1.0" encoding="UTF-8"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="edge" version="1.0"/>
  <road name="approach" length="20" id="30" junction="-1">
    <link><successor elementType="junction" elementId="300"/></link>
    <planView><geometry s="0" x="0" y="-30" hdg="1.5707963267948966" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="stopper" length="20" id="31" junction="300">
    <link><predecessor elementType="road" elementId="30" contactPoint="end"/></link>
    <planView><geometry s="0" x="0" y="-10" hdg="1.5707963267948966" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="1" t="-5" id="3101" name="stop" dynamic="no" orientation="+" zOffset="2" country="OpenDRIVE" type="206" subtype="" value="0" height="1" width="1" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
    </signals>
  </road>
  <road name="walk" length="20" id="32" junction="300">
    <planView><geometry s="0" x="-10" y="0" hdg="0" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="sidewalk"><width sOffset="0" a="2" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="fed" length="20" id="33" junction="300">
    <link><predecessor elementType="road" elementId="34" contactPoint="end"/></link>
    <planView><geometry s="0" x="-10" y="5" hdg="0" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="feeder" length="5" id="34" junction="-1">
    <link><successor elementType="junction" elementId="300"/></link>
    <planView><geometry s="0" x="-15" y="5" hdg="0" length="5"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="lonely" length="20" id="35" junction="300">
    <link><successor elementType="road" elementId="36" contactPoint="start"/></link>
    <planView><geometry s="0" x="-10" y="-5" hdg="0" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="beyond" length="10" id="36" junction="-1">
    <link><predecessor elementType="road" elementId="35" contactPoint="end"/></link>
    <planView><geometry s="0" x="10" y="-5" hdg="0" length="10"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <junction id="300" name="edge">
    <connection id="0" incomingRoad="30" connectingRoad="31" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <connection id="1" incomingRoad="34" connectingRoad="33" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
  </junction>
</OpenDRIVE>
"""


def _world() raises -> World:
    var world = World(load_opendrive(_town()))
    var settings = EpisodeSettings()
    settings.fixed_delta_seconds = Duration(0.25, SECOND)
    _ = world.apply_settings(settings)
    return world^


def _pose(x: Float32, y: Float32, z: Float32, yaw: Float32) -> CarlaTransform:
    return CarlaTransform(
        Length(x, METER),
        Length(y, METER),
        Length(z, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)),
    )


def _near(
    v: Vector3, x: Float32, y: Float32, z: Float32, msg: String = ""
) raises:
    assert_almost_equal(v.x, x, atol=1e-3, msg=msg)
    assert_almost_equal(v.y, y, atol=1e-3, msg=msg)
    assert_almost_equal(v.z, z, atol=1e-3, msg=msg)


def _yaw(r: CarlaRotation, yaw: Float32, msg: String = "") raises:
    """Compare where plus x points, so that 180 and -180 agree."""
    var want = CarlaRotation(
        Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)
    )
    _near(
        r.forward_vector(),
        want.forward_vector().x,
        want.forward_vector().y,
        0,
        msg,
    )


def _box(b: TriggerBox, x: Float32, y: Float32, yaw: Float32) raises:
    _near(b.transform.location, x, y, 0)
    _yaw(b.transform.rotation, yaw)


def _car(mut world: World, t: CarlaTransform) raises -> ActorId:
    var bp = world.blueprints.at("vehicle.lincoln.mkz")
    return world.spawn_actor(bp, t)


def _state(world: World, id: ActorId) raises -> Int:
    return world.get_traffic_light_state_of(id).value


# --- placing the signals ------------------------------------------------------


def test_signals_become_actors() raises:
    var world = _world()
    assert_equal(len(world.get_actors()), 14)
    var types: List[String] = ["spectator"]
    for _ in range(8):
        types.append("traffic.traffic_light")
    types.extend(
        [
            "traffic.stop",
            "traffic.yield",
            "traffic.speed_limit.60",
            "traffic.stop",
            "traffic.speed_limit.50",
        ]
    )
    for i in range(14):
        assert_equal(world.actor(ActorId(i + 1)).type_id, types[i])
    var ids: List[String] = [
        "2001",
        "2005",
        "2006",
        "2008",
        "2002",
        "2004",
        "2007",
        "2003",
        "3001",
        "3002",
        "3003",
        "3006",
        "3007",
    ]
    for i in range(13):
        assert_equal(world.get_opendrive_id(ActorId(i + 2)).value, ids[i])
    assert_equal(len(world.filter_actors("traffic.*")), 13)
    assert_equal(len(world.filter_actors("*stop")), 2)
    assert_equal(world.get_spectator(), SPECTATOR)
    assert_equal(world.actor(L2001).semantic_tags[0].value, 7)
    assert_equal(world.actor(STOP).semantic_tags[0].value, 8)
    with assert_raises(contains="not a traffic sign"):
        _ = world.get_opendrive_id(SPECTATOR)


def test_light_poses_and_boxes() raises:
    var world = _world()
    # The signal's pose, 0.25 m forward for a light, turned a quarter.
    _near(world.get_transform(L2001).location, 45.25, 5, 3)
    _yaw(world.get_transform(L2001).rotation, 90)
    _near(world.get_transform(L2005).location, 202.25, -195, 3)
    _near(world.get_transform(L2006).location, 302.25, -295, 3)
    _near(world.get_transform(L2008).location, 305.25, -295, 3)
    _near(world.get_transform(L2007).location, 405.25, -395, 3)
    _near(world.get_transform(L2002).location, 60, 14.75, 3)
    _yaw(world.get_transform(L2002).rotation, 0)
    _near(world.get_transform(L2004).location, 60, -40.25, 3)
    _near(world.get_transform(L2003).location, 80.25, 5, 3)
    ref lights = world.traffic_lights.lights
    # 3 m before s = 45 on road 1's right lane; lane -2 is a sidewalk. The
    # reference on road 10 has two predecessors, both road 1, as CARLA
    # counts them, so its box stays, at s = 2 - 3 clamped to the start.
    assert_equal(len(lights[0].boxes), 2)
    _box(lights[0].boxes[0], 42, 1.75, 0)
    _near(lights[0].boxes[0].extent, 1.5, 0.875, 1)
    _box(lights[0].boxes[1], 50, 1.75, 0)
    # Road 13 has one predecessor, road 1, outside the junction: the box
    # moves there, 3 m before its end.
    _box(lights[1].boxes[0], 47, 1.75, 0)
    # Road 15's one predecessor is road 13, a junction road: no move, and
    # s = 2 - 3 clamps to the section's start.
    _box(lights[2].boxes[0], 300, -298.25, 0)
    # Road 15 has no left lane for a "+" signal with no validity.
    assert_equal(len(lights[3].boxes), 0)
    # Lanes -1 and 1 of road 3; lane 1 runs against s, so its box is 3 m
    # further along s.
    assert_equal(len(lights[4].boxes), 2)
    _box(lights[4].boxes[0], 56.75, 18, -90)
    _box(lights[4].boxes[1], 53.25, 12, 90)
    _box(lights[5].boxes[0], 56.75, -37, -90)
    # Road 16's one predecessor is road 4: 3 m before its end.
    _box(lights[6].boxes[0], 56.75, -47, -90)
    # Lanes 1 to -3 of road 2: lane 0 is skipped, and -2 and -3 do not
    # exist.
    assert_equal(len(lights[7].boxes), 2)
    _box(lights[7].boxes[0], 83, -1.75, 180)
    _box(lights[7].boxes[1], 77, 1.75, 0)


def test_sign_poses_and_boxes() raises:
    var world = _world()
    _near(world.get_transform(STOP).location, 63, 9, 2)
    _yaw(world.get_transform(STOP).rotation, 0)
    _near(world.get_transform(FAR_STOP).location, 205, -195, 2)
    ref stop = world.signs[0]
    assert_equal(stop.kind.value, STOP_SIGN.value)
    # Road 12's lane has two predecessors, as CARLA counts them, so the
    # box stays on road 12, at s = 1 - 3 clamped to the start.
    assert_equal(len(stop.effect_boxes), 1)
    _box(stop.effect_boxes[0], 56.75, 10, -90)
    # Road 10 crosses road 12. Its right lane: boxes every 3.15 m from its
    # start, then one pair at x = 46.85 on road 1. Its 50 km/h limit is
    # 13.888... m/s: the 1.575 m half-box costs 0.1134 s, so there is no
    # second predecessor step within 0.1 s. Its left lane: from x = 60
    # back to 50.55, then three pairs along road 2 at the 40 m/s fallback.
    # Road 14 comes from road 3 as road 12 does, and gets none.
    var xs: List[Float32] = [
        50,
        53.15,
        56.3,
        59.45,
        46.85,
        46.85,
        60,
        56.85,
        53.7,
        50.55,
        63.15,
        63.15,
        66.3,
        66.3,
        69.45,
        69.45,
    ]
    assert_equal(len(stop.check_boxes), len(xs))
    for i in range(len(xs)):
        var y = Float32(1.75) if i < 6 else Float32(-1.75)
        _box(
            stop.check_boxes[i],
            xs[i],
            y,
            Float32(0) if i < 6 else Float32(180),
        )
        _near(stop.check_boxes[i].extent, 1.575, 1.575, 1.575)
    ref yield_sign = world.signs[1]
    assert_equal(yield_sign.kind.value, YIELD_SIGN.value)
    _box(yield_sign.effect_boxes[0], 56.75, -17, -90)
    assert_equal(len(yield_sign.check_boxes), 0)
    ref limit = world.signs[2]
    assert_equal(limit.kind.value, SPEED_LIMIT_SIGN.value)
    assert_almost_equal(limit.speed_limit.to(KILOMETER_PER_HOUR), 60, atol=1e-4)
    # A cube 0.7 of a lane wide, its half size before s = 30.
    _box(limit.effect_boxes[0], 88.775, 1.75, 0)
    _near(limit.effect_boxes[0].extent, 1.225, 1.225, 1.225)
    # Road 13 has no left lane for the far signs, and no crossing road.
    assert_equal(len(world.signs[3].effect_boxes), 0)
    assert_equal(len(world.signs[3].check_boxes), 0)
    assert_equal(len(world.signs[4].effect_boxes), 0)
    _near(world.get_transform(FAR_LIMIT).location, 207, -195, 2)


def test_stop_anticipation_uses_physical_speed_units() raises:
    # Independent time calculation: 0.9 * 3.5 / 2 = 1.575 m per debit.
    # At 50 km/h one debit exceeds 0.1 s. At 50 m/s three fit and the
    # fourth does not. The algorithm emits a box before its time debit.
    var kmh_time = Float64(1.575) / (Float64(50) / Float64(3.6))
    var si_time = Float64(1.575) / Float64(50)
    assert_almost_equal(kmh_time, Float64(0.1134), atol=1e-12)
    assert_true(kmh_time > Float64(0.1))
    assert_almost_equal(si_time, Float64(0.0315), atol=1e-12)
    assert_true(3 * si_time < Float64(0.1))
    assert_true(4 * si_time > Float64(0.1))
    var speeds: List[String] = [
        'max="50" unit="km/h"',
        'max="13.888888888888889" unit="m/s"',
        'max="50" unit="m/s"',
    ]
    var steps: List[Int] = [1, 1, 4]
    for variant in range(len(speeds)):
        var map = load_opendrive(
            _town().replace('max="50" unit="km/h"', speeds[variant])
        )
        var boxes = give_way_boxes(map, SignalId("3001"))
        var right = 4 + 2 * steps[variant]
        assert_equal(len(boxes.check), right + 10)
        # Four boxes on each junction lane; each predecessor occurs twice.
        for i in range(4):
            _box(boxes.check[i], 50 + 3.15 * Float32(i), 1.75, 0)
            _box(boxes.check[right + i], 60 - 3.15 * Float32(i), -1.75, 180)
        for step in range(steps[variant]):
            for duplicate in range(2):
                _box(
                    boxes.check[4 + 2 * step + duplicate],
                    50 - 3.15 * Float32(step + 1),
                    1.75,
                    0,
                )
        # Road 2 has no numeric limit. The unchanged 40 m/s fallback
        # permits three predecessor boxes on each of its two paths.
        for step in range(3):
            for duplicate in range(2):
                _box(
                    boxes.check[right + 4 + 2 * step + duplicate],
                    60 + 3.15 * Float32(step + 1),
                    -1.75,
                    180,
                )
        for box in boxes.check:
            _near(box.extent, 1.575, 1.575, 1.575)


def test_groups_and_first_states() raises:
    var world = _world()
    ref m = world.traffic_lights
    assert_equal(len(m.groups), 4)
    assert_equal(m.groups[0].junction_id, 100)
    assert_equal(m.groups[1].junction_id, -2)
    assert_equal(m.groups[2].junction_id, 200)
    assert_equal(m.groups[3].junction_id, -3)
    assert_equal(m.controllers[0].id, "1")
    assert_equal(len(m.controllers[0].lights), 4)
    assert_equal(m.controllers[1].id, "2")
    assert_equal(m.controllers[2].id, "-1")
    assert_equal(m.controllers[3].id, "4")
    assert_equal(m.controllers[4].id, "-2")
    # A group's first controller is green and the others red.
    assert_equal(_state(world, L2001), GREEN.value)
    assert_equal(_state(world, L2005), GREEN.value)
    assert_equal(_state(world, L2006), GREEN.value)
    assert_equal(_state(world, L2008), GREEN.value)
    assert_equal(_state(world, L2007), GREEN.value)
    assert_equal(_state(world, L2002), RED.value)
    assert_equal(_state(world, L2004), GREEN.value)
    assert_equal(_state(world, L2003), GREEN.value)
    assert_equal(world.get_light_time(L2001, GREEN).value, 10)
    assert_equal(world.get_light_time(L2001, YELLOW).value, 3)
    assert_equal(world.get_light_time(L2001, RED).value, 2)
    # A light with no junction's controller waits 10 s at red.
    assert_equal(world.get_light_time(L2004, RED).value, 10)
    var group = world.get_group_traffic_lights(L2002)
    assert_equal(len(group), 5)
    assert_equal(group[0], L2001)
    assert_equal(group[3], L2008)
    assert_equal(group[4], L2002)
    assert_equal(len(world.get_group_traffic_lights(L2003)), 1)
    var junction = world.get_traffic_lights_in_junction(JuncId(100))
    assert_equal(len(junction), 5)
    assert_equal(junction[1], L2005)
    # Controller 4 also holds yield sign 3002, which is no light, and
    # controller 5 holds nothing.
    var second = world.get_traffic_lights_in_junction(JuncId(200))
    assert_equal(len(second), 1)
    assert_equal(second[0], L2007)
    assert_equal(world.get_pole_index(L2001), 0)


def test_cycle_matches_carla() raises:
    var world = _world()
    # (tick, light, new state), from the Python model.
    # Lights 2001, 2002, 2004, 2007 and 2003. Light 2007 is alone in its
    # group, so it goes green again as its red ends.
    var changes: List[Tuple[Int, Int, Int]] = [
        (41, 2, YELLOW.value),
        (41, 7, YELLOW.value),
        (41, 8, YELLOW.value),
        (41, 9, YELLOW.value),
        (54, 2, RED.value),
        (54, 7, RED.value),
        (54, 8, RED.value),
        (54, 9, RED.value),
        (63, 6, GREEN.value),
        (63, 8, GREEN.value),
        (95, 7, GREEN.value),
        (95, 9, GREEN.value),
        (104, 6, YELLOW.value),
        (104, 8, YELLOW.value),
        (117, 6, RED.value),
        (117, 8, RED.value),
        (126, 2, GREEN.value),
        (126, 8, GREEN.value),
        (136, 7, YELLOW.value),
        (136, 9, YELLOW.value),
    ]
    var watch: List[Int] = [2, 6, 7, 8, 9]
    var last: List[Int] = [
        GREEN.value,
        RED.value,
        GREEN.value,
        GREEN.value,
        GREEN.value,
    ]
    var seen = List[Tuple[Int, Int, Int]]()
    for tick in range(1, 141):
        assert_equal(world.tick(), tick)
        for k in range(5):
            var now = _state(world, ActorId(watch[k]))
            if now != last[k]:
                seen.append((tick, watch[k], now))
                last[k] = now
        if tick == 10:
            var data = world.get_snapshot().find(L2001).value().traffic_light
            var d = data.value()
            assert_equal(d.sign_id, "2001")
            assert_equal(d.green_time.value, 10)
            assert_equal(d.yellow_time.value, 3)
            assert_equal(d.red_time.value, 2)
            assert_equal(d.elapsed_time.value, 2.5)
            assert_equal(d.state.value, GREEN.value)
            assert_false(d.time_is_frozen)
            assert_equal(d.pole_index, 0)
            assert_equal(world.get_elapsed_time(L2001).value, 2.5)
    assert_equal(len(seen), len(changes))
    for i in range(len(changes)):
        assert_equal(seen[i][0], changes[i][0], String(i))
        assert_equal(seen[i][1], changes[i][1], String(i))
        assert_equal(seen[i][2], changes[i][2], String(i))


def test_freeze_and_times() raises:
    var world = _world()
    world.freeze(L2003, True)
    assert_true(world.is_frozen(L2001))
    assert_true(world.traffic_lights.frozen)
    for _ in range(50):
        _ = world.tick()
    assert_equal(world.get_elapsed_time(L2001).value, 0)
    assert_equal(_state(world, L2001), GREEN.value)
    assert_true(
        world.get_snapshot()
        .find(L2002)
        .value()
        .traffic_light.value()
        .time_is_frozen
    )
    world.freeze_all_traffic_lights(False)
    assert_false(world.is_frozen(L2004))
    # Controller 1 holds 2001, 2005 and 2006.
    world.set_light_time(L2005, GREEN, Duration(5, SECOND))
    assert_equal(world.get_light_time(L2001, GREEN).value, 5)
    world.reset_group(L2002)
    for tick in range(1, 22):
        _ = world.tick()
        var want = GREEN.value if tick < 21 else YELLOW.value
        assert_equal(_state(world, L2006), want, String(tick))


def test_set_state_and_reset() raises:
    var world = _world()
    world.set_traffic_light_state(L2002, GREEN)
    assert_equal(_state(world, L2002), GREEN.value)
    # The controller does not know; its cycle sets the light again.
    assert_equal(world.traffic_lights.controllers[1].current_stage, 2)
    world.set_traffic_light_state(L2001, OFF)
    world.reset_all_traffic_lights()
    assert_equal(_state(world, L2001), GREEN.value)
    assert_equal(_state(world, L2002), RED.value)
    with assert_raises(contains="state is not valid"):
        world.set_traffic_light_state(L2001, TrafficLightState(5))
    with assert_raises(contains="not a traffic light"):
        world.set_traffic_light_state(STOP, RED)
    assert_true(UNKNOWN.is_valid())
    assert_false(TrafficLightState(-1).is_valid())


def test_trigger_volumes() raises:
    var world = _world()
    # The box at (42, 1.75, 0) seen from the light at (45.25, 5, 3), which
    # faces plus y: back 3.25, right 3.25 (toward minus x), down 3.
    var tv = world.get_trigger_volume(L2001)
    _near(tv.location, -3.25, 3.25, -3)
    _near(tv.extent, 1.5, 0.875, 1)
    _yaw(tv.rotation, -90)
    # Light 2003's first box is lane 1's, at (83, -1.75), facing minus x.
    var tv3 = world.get_trigger_volume(L2003)
    _near(tv3.location, -6.75, -2.75, -3)
    _yaw(tv3.rotation, 90)
    # The speed box at (88.775, 1.75, 0) from the sign at (90, 5, 2).
    var limit = world.get_trigger_volume(LIMIT)
    _near(limit.location, -3.25, 1.225, -2)
    _yaw(limit.rotation, -90)
    # The stop box at (56.75, 10, 0) from the sign at (63, 9, 2), both
    # without a turn but the box's -90.
    var stop = world.get_trigger_volume(STOP)
    _near(stop.location, -6.25, 1, -2)
    _yaw(stop.rotation, -90)
    # Light 2008 and the far stop have no box.
    _near(world.get_trigger_volume(L2008).extent, 0, 0, 0)
    _near(world.get_trigger_volume(FAR_STOP).extent, 0, 0, 0)


def test_stop_and_affected_waypoints() raises:
    var world = _world()
    # Across the box at x = 42: y = 0.4, 1.4 and 2.4, all road 1's lane -1.
    var stops = world.get_stop_waypoints(L2001)
    assert_equal(len(stops), 1)
    assert_equal(stops[0].road_id.value, 1)
    assert_equal(stops[0].lane_id.value, -1)
    var across = world.get_stop_waypoints(L2003)
    assert_equal(len(across), 1)
    assert_equal(across[0].road_id.value, 2)
    assert_equal(across[0].lane_id.value, 1)
    # Lanes -2 and -1 at s = 45 on road 1, and lane -1 at s = 2 on road
    # 10, where a reference to the light stands.
    var one = world.get_affected_lane_waypoints(L2001)
    assert_equal(len(one), 3)
    assert_equal(one[0].lane_id.value, -2)
    assert_equal(one[1].lane_id.value, -1)
    assert_equal(one[1].s, 45)
    assert_equal(one[2].road_id.value, 10)
    assert_equal(len(world.get_affected_lane_waypoints(L2008)), 0)
    # From lane -1 up to lane 1: lane 0 is skipped.
    var up = world.get_affected_lane_waypoints(L2002)
    assert_equal(len(up), 2)
    assert_equal(up[0].lane_id.value, -1)
    assert_equal(up[1].lane_id.value, 1)
    # From lane 1 down to -3: road 2 has no lane -2 or -3.
    var down = world.get_affected_lane_waypoints(L2003)
    assert_equal(len(down), 2)
    assert_equal(down[0].lane_id.value, 1)
    assert_equal(down[1].lane_id.value, -1)
    assert_equal(down[1].s, 20)


def test_landmark_queries() raises:
    var world = _world()
    var start = world.map.waypoint_xodr(
        RoadId(1), LaneId(-1), Length(10, METER)
    ).value()
    var ahead = world.get_traffic_lights_from_waypoint(start, Length64(38))
    assert_equal(len(ahead), 1)
    assert_equal(ahead[0], L2001)
    # Further on: the reference to 2001 on road 10, light 2009, which is
    # not placed, and 2005 on road 13.
    var further = world.get_traffic_lights_from_waypoint(start, Length64(46))
    assert_equal(len(further), 2)
    assert_equal(further[0], L2001)
    assert_equal(further[1], L2005)
    var end = world.map.waypoint_xodr(
        RoadId(2), LaneId(1), Length(49, METER)
    ).value()
    assert_equal(
        len(world.get_traffic_lights_from_waypoint(end, Length64(5))), 0
    )
    for bad in [inf[DType.float64](), nan[DType.float64](), -1.0]:
        with assert_raises(contains="light search distance"):
            _ = world.get_traffic_lights_from_waypoint(start, Length64(bad))
    var east = world.map.waypoint_xodr(
        RoadId(2), LaneId(-1), Length(0, METER)
    ).value()
    # Ahead on road 2 are the 60 km/h sign and light 2003. The light's
    # validity runs from lane 1 down to -3, and CARLA's search takes a
    # validity from its low lane to its high one, so it misses the light.
    assert_equal(
        len(world.get_traffic_lights_from_waypoint(east, Length64(35))), 0
    )
    var light = world.map.landmarks_from_id(SignalId("2001"))[0].copy()
    var stop = world.map.landmarks_from_id(SignalId("3001"))[0].copy()
    var paint = world.map.landmarks_from_id(SignalId("3004"))[0].copy()
    assert_equal(world.get_traffic_light(light).value(), L2001)
    assert_false(Bool(world.get_traffic_light(stop)))
    assert_equal(world.get_traffic_sign(stop).value(), STOP)
    # CARLA's `*traffic.*` also takes the lights.
    assert_equal(world.get_traffic_sign(light).value(), L2001)
    assert_false(Bool(world.get_traffic_sign(paint)))
    var far = world.map.landmarks_from_id(SignalId("3006"))[0].copy()
    assert_equal(world.get_traffic_sign(far).value(), FAR_STOP)
    assert_false(Bool(world.get_traffic_light_from_opendrive(SignalId("9999"))))


def test_landmark_query_skips_a_destroyed_actor() raises:
    var world = _world()
    var car = _car(world, _pose(20, 1.75, 0.05, 0))
    assert_true(world.destroy_actor(car))
    assert_false(world.is_alive(car))
    # A painted marking has no traffic actor. Lookup must reach the end
    # of the registry, including the dead vehicle, without reading its signal id.
    var paint = world.map.landmarks_from_id(SignalId("3004"))[0].copy()
    assert_false(Bool(world.get_traffic_sign(paint)))


# --- vehicles in the boxes -----------------------------------------------------


def test_vehicle_at_a_light() raises:
    var world = _world()
    var car = _car(world, _pose(42, 1.75, 0.05, 0))
    assert_false(world.is_at_traffic_light(car))
    _ = world.tick()
    assert_true(world.is_at_traffic_light(car))
    assert_equal(world.get_traffic_light(car).value(), L2001)
    assert_equal(world.get_traffic_light_state(car).value, GREEN.value)
    var data = world.get_snapshot().find(car).value().vehicle.value()
    assert_true(data.has_traffic_light)
    assert_equal(data.traffic_light_id, L2001)
    # The light tells the vehicle at once.
    world.set_traffic_light_state(L2001, RED)
    assert_equal(world.get_traffic_light_state(car).value, RED.value)
    world.set_transform(car, _pose(100, 1.75, 0.05, 0))
    _ = world.tick()
    assert_false(world.is_at_traffic_light(car))
    assert_false(Bool(world.get_traffic_light(car)))
    assert_equal(world.get_traffic_light_state(car).value, GREEN.value)
    assert_equal(len(world.traffic_lights.lights[0].vehicles), 0)


def test_leaving_one_light_keeps_another_lights_association() raises:
    var world = _world()
    world.freeze_all_traffic_lights(True)
    world.set_traffic_light_state(L2001, RED)
    world.set_traffic_light_state(L2003, YELLOW)
    # The public transform moves 2003's driving-lane box to x=40.
    # Light 2001's box stays at x=42; its other box is farther east.
    world.set_transform(L2003, _pose(43.25, 5, 3, 90))
    var car = _car(world, _pose(41, 1.75, 0.05, 0))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[0].vehicles), 1)
    assert_equal(len(world.traffic_lights.lights[7].vehicles), 1)
    # The later light owns the association after entry into both boxes.
    assert_equal(world.get_traffic_light(car).value(), L2003)
    assert_equal(world.get_traffic_light_state(car).value, YELLOW.value)
    world.set_transform(car, _pose(37, 1.75, 0.05, 0))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[0].vehicles), 0)
    assert_equal(len(world.traffic_lights.lights[7].vehicles), 1)
    assert_equal(world.get_traffic_light(car).value(), L2003)
    assert_equal(world.get_traffic_light_state(car).value, YELLOW.value)
    var data = world.get_snapshot().find(car).value().vehicle.value()
    assert_true(data.has_traffic_light)
    assert_equal(data.traffic_light_id, L2003)
    # A departed light cannot overwrite the remaining light's state.
    world.set_traffic_light_state(L2001, OFF)
    assert_equal(world.get_traffic_light_state(car).value, YELLOW.value)
    world.set_transform(car, _pose(30, 1.75, 0.05, 0))
    _ = world.tick()
    assert_false(world.is_at_traffic_light(car))
    assert_equal(world.get_traffic_light_state(car).value, GREEN.value)


def test_destroyed_vehicle_leaves_its_boxes() raises:
    var world = _world()
    # At x = 50 the car overlaps four corrected stop check boxes: the
    # pair at 46.85 and the junction boxes at 50 and 53.15. It also meets
    # light 2001's junction box, preserving both destruction checks.
    var car = _car(world, _pose(50, 1.75, 0.05, 0))
    var other = _car(world, _pose(88.775, 1.75, 0.05, 0))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[0].vehicles), 1)
    # Light 2005's box at 47 also overlaps this position.
    assert_equal(len(world.traffic_lights.lights[1].vehicles), 1)
    assert_equal(len(world.signs[0].vehicles_to_check), 1)
    assert_equal(world.signs[0].vehicles_to_check[0], car)
    assert_equal(world.signs[0].check_counts[0], 4)
    assert_equal(len(world.signs[0].timers), 0)
    var survivor_body = world.actor(other).body
    var survivor_location = world.get_location(other)
    assert_true(world.destroy_actor(car))
    assert_true(world.is_alive(other))
    assert_equal(world.actor(other).body, survivor_body)
    assert_true(world.get_location(other) == survivor_location)
    assert_equal(len(world.traffic_lights.lights[0].vehicles), 0)
    assert_equal(len(world.traffic_lights.lights[1].vehicles), 0)
    assert_equal(len(world.signs[0].vehicles_to_check), 0)
    assert_equal(len(world.signs[0].timers), 4)
    assert_false(world.destroy_actor(car))
    assert_equal(len(world.signs[0].timers), 4)


def test_speed_limit_box() raises:
    var world = _world()
    var car = _car(world, _pose(100, 1.75, 0.05, 0))
    _ = world.tick()
    assert_almost_equal(
        world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 30, atol=1e-4
    )
    world.set_transform(car, _pose(88.775, 1.75, 0.05, 0))
    _ = world.tick()
    assert_almost_equal(
        world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 60, atol=1e-4
    )
    # A speed limit stays after the box.
    world.set_transform(car, _pose(105, 1.75, 0.05, 0))
    _ = world.tick()
    assert_almost_equal(
        world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 60, atol=1e-4
    )


def test_stop_sign_waits_two_seconds() raises:
    var world = _world()
    var car = _car(world, _pose(56.75, 10.5, 0.05, -90))
    for tick in range(1, 11):
        _ = world.tick()
        var want = RED.value if tick < 9 else GREEN.value
        assert_equal(
            world.get_traffic_light_state(car).value, want, String(tick)
        )
    world.set_transform(car, _pose(56.75, 30, 0.05, -90))
    _ = world.tick()
    assert_equal(len(world.signs[0].vehicles_in_effect), 0)


def test_stop_sign_waits_for_cross_traffic() raises:
    var world = _world()
    # B sits in six check boxes: 63.15, 66.3 and 69.45, each twice.
    var b = _car(world, _pose(66.3, -1.75, 0.05, 180))
    _ = world.tick()
    assert_equal(world.signs[0].check_counts[0], 6)
    var a = _car(world, _pose(56.75, 10.5, 0.05, -90))
    for tick in range(2, 16):
        if tick == 12:
            world.set_transform(b, _pose(100, -1.75, 0.05, 180))
        _ = world.tick()
        var want = RED.value if tick < 14 else GREEN.value
        assert_equal(world.get_traffic_light_state(a).value, want, String(tick))


def test_vehicles_in_two_boxes_of_a_light() raises:
    var world = _world()
    # Light 2002 has boxes at (56.75, 18) and (53.25, 12). One car sits in
    # each, and a third car later sits in both.
    var one = _car(world, _pose(56.75, 18, 0.05, -90))
    var two = _car(world, _pose(53.25, 12, 0.05, 90))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[4].vehicles), 2)
    assert_equal(world.get_traffic_light(two).value(), L2002)
    assert_equal(world.get_traffic_light_state(one).value, RED.value)
    world.set_transform(one, _pose(56.75, 30, 0.05, -90))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[4].vehicles), 1)
    assert_true(world.destroy_actor(two))
    var both = _car(world, _pose(55, 15, 0.05, -90))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[4].vehicles), 2)
    # A repeated update does not duplicate either box's membership.
    world._update_overlaps()
    assert_equal(len(world.traffic_lights.lights[4].vehicles), 2)
    # Leaving just one box must keep the red light's other overlap.
    world.set_transform(both, _pose(55, 18, 0.05, -90))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[4].vehicles), 1)
    assert_true(world.is_at_traffic_light(both))
    assert_equal(world.get_traffic_light(both).value(), L2002)
    assert_equal(world.get_traffic_light_state(both).value, RED.value)
    # Leaving the last box clears the association.
    world.set_transform(both, _pose(55, 40, 0.05, -90))
    _ = world.tick()
    assert_equal(len(world.traffic_lights.lights[4].vehicles), 0)
    assert_false(world.is_at_traffic_light(both))


def test_yield_sign_in_the_world() raises:
    var world = _world()
    var car = _car(world, _pose(56.75, -17, 0.05, -90))
    _ = world.tick()
    assert_equal(len(world.signs[1].vehicles_in_effect), 1)
    assert_equal(world.get_traffic_light_state(car).value, GREEN.value)


def test_moving_a_light_moves_its_boxes() raises:
    var world = _world()
    world.set_transform(L2003, _pose(90.25, 5, 3, 90))
    _box(world.traffic_lights.lights[7].boxes[0], 93, -1.75, 180)
    _box(world.traffic_lights.lights[7].boxes[1], 87, 1.75, 0)
    # A light or a sign with no box moves alone.
    world.set_transform(L2008, _pose(1, 2, 3, 0))
    world.set_transform(FAR_STOP, _pose(1, 2, 3, 0))
    _near(world.get_location(FAR_STOP), 1, 2, 3)
    world.set_transform(LIMIT, _pose(100, 5, 2, 90))
    _box(world.signs[2].effect_boxes[0], 98.775, 1.75, 0)
    world.set_transform(STOP, _pose(64, 9, 2, 0))
    _box(world.signs[0].effect_boxes[0], 57.75, 10, -90)
    _box(world.signs[0].check_boxes[0], 51, 1.75, 0)
    var car = _car(world, _pose(98.775, 1.75, 0.05, 0))
    _ = world.tick()
    assert_almost_equal(
        world.get_speed_limit(car).to(KILOMETER_PER_HOUR), 60, atol=1e-4
    )


# --- the parts on their own ---------------------------------------------------


def test_edge_town_check_boxes() raises:
    # Road 31 in junction 300 carries a stop sign and crosses three roads:
    # road 32, a sidewalk only; road 33, fed by the 5 m road 34; and road
    # 35, which no road feeds and which leads on to road 36. Along x in
    # CARLA's frame they run at y = 1, -3.25 and 6.75.
    var map = load_opendrive(_edge())
    var boxes = give_way_boxes(map, SignalId("3101"))
    # Road 31 has one predecessor, road 30: its box is 3 m before the end.
    assert_equal(len(boxes.effect), 1)
    _box(boxes.effect[0], 1.75, 13, -90)
    var xs: List[Float32] = [
        -10,
        -6.85,
        -3.7,
        -0.55,
        2.6,
        5.75,
        8.9,
        -13.15,
        -10,
        -6.85,
        -3.7,
        -0.55,
        2.6,
        5.75,
        8.9,
    ]
    assert_equal(len(boxes.check), len(xs))
    for i in range(len(xs)):
        var y = Float32(-3.25) if i < 8 else Float32(6.75)
        _box(boxes.check[i], xs[i], y, 0)
    var world = World(map^)
    assert_equal(len(world.get_traffic_lights_in_junction(JuncId(300))), 0)


def test_parts_on_empty_input() raises:
    var empty = load_opendrive("<OpenDRIVE></OpenDRIVE>")
    assert_equal(len(signal_references(empty, SignalId("1"))), 0)
    var map = load_opendrive(_town())
    var nothing = SignalId("nope")
    assert_equal(len(traffic_light_boxes(map, nothing)), 0)
    assert_equal(len(give_way_boxes(map, nothing).effect), 0)
    assert_equal(len(speed_limit_boxes(map, nothing)), 0)
    assert_equal(len(affected_lane_waypoints(map, nothing)), 0)
    var volume = BoundingBox(Vector3(0, 0, 0), Vector3(2, 1, 1))
    assert_equal(len(stop_waypoints(empty, _pose(0, 0, 0, 0), volume)), 0)
    # Controllers with no signal, or with one the map lacks.
    var held = load_opendrive(
        '<OpenDRIVE><controller id="1" name="a" sequence="0"><control'
        ' signalId="9" type="0"/></controller><controller id="2" name="b"'
        ' sequence="0"/></OpenDRIVE>'
    )
    assert_equal(len(TrafficLightManager.from_map(held).lights), 0)
    var m = TrafficLightManager()
    assert_equal(m.find(SignalId("1")), -1)
    m.controllers.append(TrafficLightController("x"))
    m.reset_state(0)
    assert_equal(m.controllers[0].current_stage, 2)
    assert_equal(len(m.notified), 0)


def test_stop_waypoints_across_lanes_and_roads() raises:
    var map = load_opendrive(_town())
    # Across road 1 at x = 20, from y = -2.7 to 2.3: lane 1, then lane -1.
    var volume = BoundingBox(Vector3(0, 0, 0), Vector3(3, 1, 1))
    var across = stop_waypoints(map, _pose(20, 0, 0, 90), volume)
    assert_equal(len(across), 2)
    assert_equal(across[0].lane_id.value, 1)
    assert_equal(across[1].lane_id.value, -1)
    # Along x = 56.75 from y = 7.3 to 10.3: road 12, then road 3.
    var along = stop_waypoints(map, _pose(56.75, 10, 0, 90), volume)
    assert_equal(len(along), 2)
    assert_equal(along[0].road_id.value, 12)
    assert_equal(along[1].road_id.value, 3)


def test_stop_sign_machine() raises:
    # The Python model: B into a check box, A into the effect box, B
    # out, with 0.25 s ticks; the timers run first in each tick.
    var sign = TrafficSign(
        SignalId("1"), STOP_SIGN, _pose(0, 0, 0, 0), Velocity(0)
    )
    var a = ActorId(1)
    var b = ActorId(2)
    assert_equal(len(sign.begin_check(b)), 0)
    var orders = sign.begin_effect(a)
    assert_equal(len(orders), 1)
    assert_equal(orders[0].state.value, RED.value)
    # Entering twice keeps one entry.
    _ = sign.begin_effect(a)
    assert_equal(len(sign.vehicles_in_effect), 1)
    assert_equal(len(sign.timers), 2)
    sign.end_effect(ActorId(9))
    sign.end_check(ActorId(9))
    assert_equal(len(sign.timers), 3)
    sign.timers = [2.0]
    for _ in range(7):
        assert_equal(len(sign.tick_timers(0.25)), 0)
    # The check at 2 s finds B and waits another second.
    orders = sign.tick_timers(0.25)
    assert_equal(len(orders), 1)
    assert_equal(orders[0].state.value, RED.value)
    assert_equal(sign.timers[0], 1.0)
    sign.end_check(b)
    assert_equal(len(sign.vehicles_to_check), 0)
    _ = sign.tick_timers(0.25)
    orders = sign.tick_timers(0.25)
    assert_equal(len(orders), 1)
    assert_equal(orders[0].vehicle, a)
    assert_equal(orders[0].state.value, GREEN.value)
    sign.end_effect(a)
    assert_equal(len(sign.vehicles_in_effect), 0)


def test_yield_sign_machine() raises:
    var sign = TrafficSign(
        SignalId("1"), YIELD_SIGN, _pose(0, 0, 0, 0), Velocity(0)
    )
    var a = ActorId(1)
    var b = ActorId(2)
    _ = sign.begin_check(b)
    _ = sign.begin_check(b)
    assert_equal(sign.check_counts[0], 2)
    var orders = sign.begin_effect(a)
    assert_equal(orders[0].state.value, RED.value)
    assert_equal(sign.timers[0], 0.5)
    # A vehicle already in the effect box is not checked.
    _ = sign.begin_check(a)
    assert_equal(len(sign.vehicles_to_check), 1)
    sign.end_check(b)
    sign.end_check(b)
    _ = sign.tick_timers(0.25)
    orders = sign.tick_timers(0.25)
    assert_equal(orders[len(orders) - 1].state.value, GREEN.value)
    # A check with no vehicle anywhere gives no order.
    var idle = TrafficSign(
        SignalId("2"), YIELD_SIGN, _pose(0, 0, 0, 0), Velocity(0)
    )
    idle.end_check(ActorId(5))
    assert_equal(len(idle.tick_timers(0.5)), 0)
    # A vehicle in both lists leaves the check list.
    var c = ActorId(3)
    _ = sign.begin_check(c)
    sign.vehicles_in_effect.append(c)
    _ = sign.begin_effect(a)
    assert_equal(len(sign.vehicles_to_check), 0)


def test_sign_kinds_and_ids() raises:
    assert_equal(sign_kind_of("206", "", "stop").value().value, STOP_SIGN.value)
    assert_false(Bool(sign_kind_of("206", "", "Stencil_STOP")))
    assert_equal(sign_kind_of("205", "", "").value().value, YIELD_SIGN.value)
    assert_equal(
        sign_kind_of("274", "120", "").value().value, SPEED_LIMIT_SIGN.value
    )
    assert_false(Bool(sign_kind_of("274", "130", "")))
    assert_false(Bool(sign_kind_of("101", "", "")))
    assert_equal(sign_type_id(STOP_SIGN, ""), "traffic.stop")
    assert_equal(sign_type_id(YIELD_SIGN, ""), "traffic.yield")
    assert_equal(sign_type_id(SPEED_LIMIT_SIGN, "90"), "traffic.speed_limit.90")
    with assert_raises(contains="Sign kind is not valid"):
        _ = sign_type_id(SignKind(3), "")
    assert_false(SignKind(-1).is_valid())
    with assert_raises(contains="Sign id or kind is not valid"):
        _ = TrafficSign(SignalId(""), STOP_SIGN, _pose(0, 0, 0, 0), Velocity(0))
    with assert_raises(contains="Sign id or kind is not valid"):
        _ = TrafficSign(
            SignalId("1"), SignKind(7), _pose(0, 0, 0, 0), Velocity(0)
        )
    var map = load_opendrive(_town())
    with assert_raises(contains="Signal id is not valid"):
        _ = signal_references(map, SignalId(""))
    # Light 2001 on road 1, and its reference on road 10.
    assert_equal(len(signal_references(map, SignalId("2001"))), 2)
    assert_equal(len(traffic_light_boxes(map, SignalId("2001"))), 2)
    assert_equal(len(give_way_boxes(map, SignalId("3002")).effect), 1)
    assert_equal(len(speed_limit_boxes(map, SignalId("3003"))), 1)
    # A reference whose lanes are not driving lanes, or not on the map,
    # gives no box.
    assert_equal(len(speed_limit_boxes(map, SignalId("2003"))), 2)
    assert_equal(len(give_way_boxes(map, SignalId("2003")).effect), 2)


def test_manager_without_a_controller() raises:
    var m = TrafficLightManager()
    m.lights.append(TrafficLight(SignalId("5"), _pose(0, 0, 0, 0)))
    assert_equal(m.time_of(0, GREEN).value, 0)
    assert_equal(m.elapsed_time(0).value, 0)
    assert_equal(m.group_of(0), -1)
    assert_false(m.is_frozen(0))
    assert_equal(len(m.group_lights(0)), 0)
    m.reset_group_of(0)
    assert_equal(m.lights[0].state.value, RED.value)
    assert_equal(m.find(SignalId("5")), 0)
    assert_equal(m.find(SignalId("6")), -1)
    with assert_raises(contains="has no controller"):
        m.set_time_of(0, GREEN, Duration(1, SECOND))
    with assert_raises(contains="out of range"):
        _ = m.time_of(1, GREEN)
    with assert_raises(contains="out of range"):
        m.set_light_state(-1, GREEN)


def test_controller_stages() raises:
    var world = _world()
    ref m = world.traffic_lights
    with assert_raises(contains="at least one stage"):
        m.set_stages(0, List[TrafficLightStage]())
    with assert_raises(contains="state is not valid"):
        m.set_stages(
            0, [TrafficLightStage(Duration(1, SECOND), TrafficLightState(8))]
        )
    m.set_stages(
        0,
        [
            TrafficLightStage(Duration(1, SECOND), GREEN),
            TrafficLightStage(Duration(1, SECOND), RED),
        ],
    )
    # `SetStates` resets to the last stage.
    assert_equal(m.controllers[0].current_stage, 1)
    assert_equal(m.lights[0].state.value, RED.value)
    assert_equal(m.controllers[0].stage_time(YELLOW).value, 0)
    var stages = default_stages()
    assert_equal(len(stages), 3)
    assert_equal(stages[1].time.value, 3)
    # Plus 90 degrees past 180 wraps.
    _yaw(light_transform(_pose(0, 0, 0, 170)).rotation, -100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
