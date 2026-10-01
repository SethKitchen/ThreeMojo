# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA walker navigation on real maps and in a world.

The maps are `assets/carla/town.xodr` and a straight road of 200 m below.
In both, the driving lanes are 3.5 m wide on each side of the center line
and the sidewalks 2 m wide beyond them, raised by the port's curb height
of 0.1524 m. The expected crosswalk outlines, paths and sides are worked
by hand from the files: a crosswalk at s along a road running east is
the rectangle from s - 1.5 to s + 1.5 and from -6 to 6 m across, since
CARLA widens a crosswalk by 1 m at each end.
"""

from extensions.carla.actor import ActorId, GREEN, RED, TrafficLightState
from extensions.carla.map import Map
from extensions.carla.navigation_mesh import (
    _stations,
    AREA_CROSSWALK,
    AREA_ROAD,
    AREA_SIDEWALK,
    NavMesh,
    NavPolygonId,
    build_navigation_mesh,
    crosswalk_outlines,
    walker_filter,
)
from extensions.carla.navigation_walkers import (
    WalkerAIController,
    WalkerHandle,
    WalkerNavigation,
)
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length, Velocity

# A straight road of 200 m: one lane each way, a sidewalk each side, and
# one crosswalk at s = 20 with an outline of 10 by 3 m.
comptime LONG_ROAD = """<?xml version="1.0"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="long road"/>
  <road name="long" length="200" id="1" junction="-1">
    <planView><geometry s="0" x="0" y="0" hdg="0" length="200"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left>
        <lane id="2" type="sidewalk"><width sOffset="0" a="2" b="0" c="0" d="0"/></lane>
        <lane id="1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
      </left>
      <center><lane id="0" type="none"/></center>
      <right>
        <lane id="-1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
        <lane id="-2" type="sidewalk"><width sOffset="0" a="2" b="0" c="0" d="0"/></lane>
      </right>
    </laneSection></lanes>
    <objects>
      <object type="crosswalk" id="1" name="cw" s="20" t="0" zOffset="0" hdg="1.5707963267948966" pitch="0" roll="0" orientation="none" length="10" width="3">
        <outline>
          <cornerLocal u="-5" v="-1.5" z="0"/>
          <cornerLocal u="5" v="-1.5" z="0"/>
          <cornerLocal u="5" v="1.5" z="0"/>
          <cornerLocal u="-5" v="1.5" z="0"/>
          <cornerLocal u="-5" v="-1.5" z="0"/>
        </outline>
      </object>
    </objects>
  </road>
</OpenDRIVE>
"""

# A road with an outline that does not close, a sidewalk of no width, and
# a traffic light whose validity names a lane the road does not have.
comptime ODD_WALK = """<?xml version="1.0"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="odd walk"/>
  <road name="odd" length="40" id="1" junction="-1">
    <planView><geometry s="0" x="0" y="0" hdg="0" length="40"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left>
        <lane id="2" type="sidewalk"><width sOffset="0" a="0" b="0" c="0" d="0"/></lane>
        <lane id="1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
      </left>
      <center><lane id="0" type="none"/></center>
      <right>
        <lane id="-1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>
        <lane id="-2" type="sidewalk"><width sOffset="0" a="2" b="0" c="0" d="0"/></lane>
      </right>
    </laneSection></lanes>
    <objects>
      <object type="crosswalk" id="1" name="cw" s="20" t="0" zOffset="0" hdg="1.5707963267948966" pitch="0" roll="0" orientation="none" length="10" width="3">
        <outline>
          <cornerLocal u="-5" v="-1.5" z="0"/>
          <cornerLocal u="5" v="-1.5" z="0"/>
          <cornerLocal u="5" v="1.5" z="0"/>
          <cornerLocal u="-5" v="1.5" z="0"/>
        </outline>
      </object>
    </objects>
    <signals>
      <signal s="30" t="-6" id="1" name="light" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-5" toLane="-5"/>
      </signal>
    </signals>
  </road>
</OpenDRIVE>
"""

comptime _CURB = Float32(0.1524)


def _world(var map: Map) raises -> World:
    var world = World(map^)
    var settings = EpisodeSettings()
    settings.fixed_delta_seconds = Duration(0.05, SECOND)
    _ = world.apply_settings(settings)
    return world^


def _pose(x: Float32, y: Float32, z: Float32) -> CarlaTransform:
    return CarlaTransform(
        Length(x, METER),
        Length(y, METER),
        Length(z, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )


def _near(p: Vector3, x: Float32, y: Float32, tol: Float64 = 1e-3) raises:
    assert_almost_equal(p.x, x, atol=tol)
    assert_almost_equal(p.y, y, atol=tol)


def _walker_with_controller(
    mut world: World, x: Float32, y: Float32
) raises -> Tuple[ActorId, WalkerAIController]:
    var walker = world.spawn_actor(
        world.blueprints.at("walker.pedestrian.0020"), _pose(x, y, 1.1)
    )
    var controller = world.spawn_actor(
        world.blueprints.at("controller.ai.walker"), _pose(0, 0, 0), walker
    )
    return (walker, WalkerAIController(controller))


def _hold_light(mut world: World, state: TrafficLightState) raises:
    var light = world.filter_actors("*traffic_light*")[0]
    world.freeze(light, False)
    world.set_traffic_light_state(light, state)
    world.freeze(light, True)


# --- meshes ----------------------------------------------------------------------------


def test_town_mesh() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var outlines = crosswalk_outlines(map)
    assert_equal(len(outlines), 2)
    # Road 1's crosswalks at s = 10 and 40.
    _near(outlines[0][0], 8.5, 6)
    _near(outlines[0][2], 11.5, -6)
    _near(outlines[1][0], 38.5, 6)
    var mesh = build_navigation_mesh(map)
    var crosswalks = 0
    for p in mesh.polygons:
        if p.area == AREA_CROSSWALK:
            crosswalks += 1
            var c = p.center
            assert_true(abs(c.y) < 3.5)
            assert_true(
                (c.x > 8.5 and c.x < 11.5) or (c.x > 38.5 and c.x < 41.5)
            )
        elif p.area == AREA_SIDEWALK:
            for v in p.vertices:
                assert_almost_equal(v.z - p.vertices[0].z, 0, atol=1e-5)
            assert_true(p.vertices[0].z > 0.1)
    # Each crosswalk covers road 1's two lanes: two strips a lane.
    assert_true(crosswalks >= 4)
    with assert_raises(contains="more than zero"):
        _ = build_navigation_mesh(map, Length(0, METER))


def test_town_path_takes_the_crosswalk() raises:
    # From the south sidewalk at x = 20 to the north one: the taut path
    # turns at the crosswalk's east corners at the road's edges.
    var map = load_opendrive_file("assets/carla/town.xodr")
    var world = _world(load_opendrive_file("assets/carla/town.xodr"))
    var nav = WalkerNavigation(world)
    var points = (
        nav.nav.get_path(
            Vector3(20, 4.5, _CURB),
            Vector3(20, -4.5, _CURB),
            walker_filter(False),
        )
        .value()
        .copy()
    )
    assert_equal(len(points), 4)
    _near(points[0].location, 20, 4.5)
    assert_equal(points[0].area.value, AREA_SIDEWALK.value)
    _near(points[1].location, 11.5, 3.5)
    assert_equal(points[1].area.value, AREA_CROSSWALK.value)
    _near(points[2].location, 11.5, -3.5)
    assert_equal(points[2].area.value, AREA_SIDEWALK.value)
    _near(points[3].location, 20, -4.5)
    _ = map^


def test_long_road_crossing_factor() raises:
    # From (150, 4.5) to (150, -4.5): across the road costs about 7 m at
    # 10 a meter; around by the crosswalk at s = 20 about 267 m.
    var map = load_opendrive(LONG_ROAD)
    var mesh = build_navigation_mesh(map)
    var from_p = Vector3(150, 4.5, _CURB)
    var to_p = Vector3(150, -4.5, _CURB)
    var anywhere = walker_filter(True)
    var a = mesh.find_nearest_polygon(from_p, anywhere).value()
    var b = mesh.find_nearest_polygon(to_p, anywhere).value()
    var direct = mesh.find_straight_path(
        a[1], b[1], mesh.find_path(a[0], b[0], a[1], b[1], anywhere)
    )
    assert_equal(len(direct), 4)
    assert_equal(direct[1].area.value, AREA_ROAD.value)
    _near(direct[1].location, 150, 3.5)
    _near(direct[2].location, 150, -3.5)
    var only = walker_filter(False)
    var around = mesh.find_straight_path(
        a[1], b[1], mesh.find_path(a[0], b[0], a[1], b[1], only)
    )
    assert_equal(len(around), 4)
    assert_equal(around[1].area.value, AREA_CROSSWALK.value)
    _near(around[1].location, 21.5, 3.5)
    _near(around[2].location, 21.5, -3.5)


# --- AI walkers ------------------------------------------------------------------------


def test_ai_walker_crosses_at_the_crosswalk() raises:
    var world = _world(load_opendrive_file("assets/carla/town.xodr"))
    _hold_light(world, RED)
    var nav = WalkerNavigation(world)
    var pair = _walker_with_controller(world, 20, 4.5)
    var walker = pair[0]
    var controller = pair[1]
    controller.start(world, nav)
    assert_true(controller.go_to_location(world, nav, Vector3(20, -4.5, _CURB)))
    var zero = walker_filter(False)
    var crossed = False
    for _ in range(300):
        _ = world.tick()
        nav.tick(world)
        var at = world.get_location(walker)
        var feet = Vector3(
            at.x, at.y, at.z - world.get_bounding_box(walker).extent.z
        )
        # The feet stand on a polygon that filter 0 allows.
        var on = nav.nav.mesh.find_nearest_polygon(
            feet, zero, Vector3(0.1, 0.1, 0.1)
        )
        assert_true(Bool(on))
        if abs(at.y) < 3.5:
            assert_true(at.x > 8.5 and at.x < 11.5)
        if at.y < -3.5:
            crossed = True
    assert_true(crossed)


def test_ai_walker_waits_for_green() raises:
    # Green lets the cars go: the walker stands at the crosswalk.
    var world = _world(load_opendrive_file("assets/carla/town.xodr"))
    _hold_light(world, GREEN)
    var nav = WalkerNavigation(world)
    var pair = _walker_with_controller(world, 20, 4.5)
    var walker = pair[0]
    pair[1].start(world, nav)
    _ = pair[1].go_to_location(world, nav, Vector3(20, -4.5, _CURB))
    for _ in range(300):
        _ = world.tick()
        nav.tick(world)
    assert_true(world.get_location(walker).y > 3.4)
    assert_equal(nav.manager.walkers[walker.value].state.value, 2)


def test_ai_walker_controls() raises:
    var world = _world(load_opendrive(LONG_ROAD))
    var nav = WalkerNavigation(world)
    nav.set_pedestrians_seed(5)
    nav.set_pedestrians_cross_factor(1.0)
    var pair = _walker_with_controller(world, 150, 4.5)
    var walker = pair[0]
    var controller = pair[1]
    controller.start(world, nav)
    # The walker may cross anywhere: straight over the road.
    _ = controller.go_to_location(world, nav, Vector3(150, -4.5, _CURB))
    assert_equal(
        nav.manager.walkers[walker.value].route[1].area.value, AREA_ROAD.value
    )
    assert_true(controller.set_max_speed(world, nav, Velocity(0.8)))
    for _ in range(40):
        _ = world.tick()
        nav.tick(world)
    var v = world.get_velocity(walker)
    assert_almost_equal(Float64(v.length()), 0.8, atol=0.01)
    assert_almost_equal(
        Float64(world.get_walker_control(walker).speed.value), 0.8, atol=0.01
    )
    var random = controller.get_random_location(nav).value()
    var zero = walker_filter(False)
    var on = nav.nav.mesh.find_nearest_polygon(random, zero).value()
    assert_equal(nav.nav.mesh.area_of(on[0]).value, AREA_SIDEWALK.value)
    # Stopped, it leaves the crowd.
    controller.stop(world, nav)
    assert_equal(len(nav.walkers), 0)
    assert_false(controller.go_to_location(world, nav, Vector3(150, -4.5, 0)))
    assert_false(controller.set_max_speed(world, nav, Velocity(1)))
    # A controller must hang from a walker.
    var loose = world.spawn_actor(
        world.blueprints.at("controller.ai.walker"), _pose(0, 0, 0)
    )
    with assert_raises(contains="not attached to a walker"):
        WalkerAIController(loose).start(world, nav)


def test_walker_navigation_ticks() raises:
    var world = _world(load_opendrive(LONG_ROAD))
    var nav = WalkerNavigation(world)
    # No walkers: nothing to do.
    nav.tick(world)
    var pair = _walker_with_controller(world, 50, 4.5)
    var walker = pair[0]
    pair[1].start(world, nav)
    # The cars are in the crowd.
    _ = world.spawn_actor(
        world.blueprints.at("vehicle.lincoln.mkz"), _pose(60, 1.75, 0.3)
    )
    _ = world.tick()
    nav.tick(world)
    assert_equal(len(nav.nav.mapped_vehicles), 1)
    # A walker that is gone leaves, and its controller goes too.
    _ = world.destroy_actor(walker)
    _ = world.tick()
    nav.tick(world)
    assert_equal(len(nav.walkers), 0)
    assert_false(world.is_alive(pair[1].id))
    # Unregistering an unknown pair does nothing.
    nav.unregister_walker(ActorId(900), ActorId(901))
    nav.register_walker(ActorId(900), ActorId(901))
    assert_equal(len(nav.walkers), 1)
    # A walker gone whose controller is gone too.
    nav.tick(world)
    assert_equal(len(nav.walkers), 0)
    assert_true(
        WalkerHandle(ActorId(1), ActorId(2))
        == WalkerHandle(ActorId(1), ActorId(2))
    )


# --- corners -------------------------------------------------------------------------------


def test_mesh_building_corners() raises:
    # No roads: no polygons. No crosswalk: no outline.
    assert_equal(
        build_navigation_mesh(load_opendrive("<OpenDRIVE/>")).polygon_count(), 0
    )
    var long = load_opendrive(String(LONG_ROAD).replace("crosswalk", "pole"))
    assert_equal(len(crosswalk_outlines(long)), 0)
    var plain = build_navigation_mesh(long)
    for p in plain.polygons:
        assert_true(p.area != AREA_CROSSWALK)
    # An outline that does not repeat its first corner still counts; the
    # sidewalk of no width gives no polygon.
    var odd = load_opendrive(ODD_WALK)
    var outlines = crosswalk_outlines(odd)
    assert_equal(len(outlines), 1)
    assert_equal(len(outlines[0]), 4)
    var mesh = build_navigation_mesh(odd)
    for p in mesh.polygons:
        if p.area == AREA_SIDEWALK:
            assert_true(p.center.y > 0)
    # Cut points within 1 cm of a station merge.
    var stations = _stations(0, 10, 2, [4.005, 4.5, 12])
    assert_equal(len(stations), 7)
    assert_almost_equal(stations[3], 4.5, atol=1e-12)


def test_walker_navigation_corners() raises:
    # The light's validity names no lane: it has no stop waypoint.
    var world = _world(load_opendrive(ODD_WALK))
    assert_equal(len(world.filter_actors("traffic.traffic_light")), 1)
    var nav = WalkerNavigation(world)
    assert_equal(len(nav.manager.traffic_lights), 0)
    # A walker registered but not in the crowd is not moved.
    var pair = _walker_with_controller(world, 10, 4.5)
    nav.register_walker(pair[0], pair[1].id)
    nav.register_walker(ActorId(900), ActorId(901))
    # Unregistering the second of two.
    nav.unregister_walker(ActorId(900), ActorId(901))
    assert_equal(len(nav.walkers), 1)
    var before = world.get_location(pair[0])
    nav.tick(world)
    assert_equal(world.get_location(pair[0]).x, before.x)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
