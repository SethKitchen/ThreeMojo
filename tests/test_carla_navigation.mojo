# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA walker navigation: the mesh, the crowd and the walker manager.

Most tests stand on a hand-made street, flat at z = 0:

    y 6..8   N0 x 0..3   | N1 x 3..7          | N2 x 7..10   sidewalk
    y 2..6   R0 x 0..4   | R1 x 4..6 crosswalk | R2 x 6..10  road
    y 0..2   S0 x 0..3   | S1 x 3..7          | S2 x 7..10   sidewalk

The expected paths, costs and speeds are worked by hand from that
drawing, CARLA's constants and the crowd rules of the module docstring.
The count of walkers that may cross roads comes from a Python model of
the seeded minimal-standard generator.
"""

from extensions.carla.actor import ActorId, GREEN, RED, YELLOW
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.navigation import (
    AGENT_HEIGHT,
    EVENT_CONTINUE,
    EVENT_END,
    EVENT_IGNORE,
    EVENT_STOP_AND_CHECK,
    EVENT_TIME_OUT,
    EVENT_WAIT,
    EventResult,
    MAX_AGENTS,
    Navigation,
    VehicleCollisionInfo,
    WALKER_IDLE,
    WALKER_IN_EVENT,
    WALKER_STOP,
    WALKER_WALKING,
    WalkerEventKind,
    WalkerManager,
    WalkerRoutePoint,
    WalkerState,
    WalkerTrafficLight,
    ignore_event,
    route_points,
    stop_and_check_event,
    vehicle_box,
    wait_event,
)
from extensions.carla.navigation_mesh import (
    AREA_BLOCK,
    AREA_CROSSWALK,
    AREA_GRASS,
    AREA_ROAD,
    AREA_SIDEWALK,
    FLAG_ALL,
    FLAG_CROSSWALK,
    FLAG_GRASS,
    FLAG_NONE,
    FLAG_ROAD,
    FLAG_SIDEWALK,
    FLAG_WALKABLE,
    NO_POLYGON,
    NavArea,
    NavFlags,
    NavMesh,
    NavPoint,
    NavPolygon,
    NavPolygonId,
    NavQueryFilter,
    _intersect,
    flags_of,
    sidewalk_filter,
    walker_filter,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.transform import CarlaRotation, CarlaTransform
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


def _rect(x0: Float32, y0: Float32, x1: Float32, y1: Float32) -> List[Vector3]:
    var out = List[Vector3]()
    out.append(Vector3(x0, y0, 0))
    out.append(Vector3(x1, y0, 0))
    out.append(Vector3(x1, y1, 0))
    out.append(Vector3(x0, y1, 0))
    return out^


def _street() raises -> NavMesh:
    # Ids: S0 0, S1 1, S2 2, R0 3, R1 4, R2 5, N0 6, N1 7, N2 8.
    var mesh = NavMesh()
    _ = mesh.add_polygon(_rect(0, 0, 3, 2), AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(3, 0, 7, 2), AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(7, 0, 10, 2), AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(0, 2, 4, 6), AREA_ROAD)
    _ = mesh.add_polygon(_rect(4, 2, 6, 6), AREA_CROSSWALK)
    _ = mesh.add_polygon(_rect(6, 2, 10, 6), AREA_ROAD)
    _ = mesh.add_polygon(_rect(0, 6, 3, 8), AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(3, 6, 7, 8), AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(7, 6, 10, 8), AREA_SIDEWALK)
    mesh.connect()
    return mesh^


def _ids(path: List[NavPolygonId]) -> String:
    var out = String()
    for p in path:
        out += String(p.value, " ")
    return out


def _near(p: Vector3, x: Float32, y: Float32, tol: Float64 = 1e-4) raises:
    assert_almost_equal(p.x, x, atol=tol)
    assert_almost_equal(p.y, y, atol=tol)


def _pose(x: Float32, y: Float32, yaw: Float32) -> CarlaTransform:
    return CarlaTransform(
        Length(x, METER),
        Length(y, METER),
        Length(0, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(yaw, DEGREE), Angle(0, DEGREE)),
    )


# --- kinds -------------------------------------------------------------------------------


def test_kinds_are_carlas() raises:
    assert_equal(AREA_BLOCK.value, 0)
    assert_equal(AREA_SIDEWALK.value, 1)
    assert_equal(AREA_CROSSWALK.value, 2)
    assert_equal(AREA_ROAD.value, 3)
    assert_equal(AREA_GRASS.value, 4)
    assert_false(NavArea(5).is_valid())
    assert_false(NavArea(-1).is_valid())
    assert_equal(FLAG_NONE.value, 1)
    assert_equal(FLAG_SIDEWALK.value, 2)
    assert_equal(FLAG_CROSSWALK.value, 4)
    assert_equal(FLAG_ROAD.value, 8)
    assert_equal(FLAG_GRASS.value, 16)
    assert_equal(FLAG_ALL.value, 0xFFFF)
    assert_equal(FLAG_WALKABLE.value, 30)
    assert_true(FLAG_ALL.is_valid())
    assert_false(NavFlags(0x10000).is_valid())
    assert_false(NavFlags(-1).is_valid())
    assert_equal((FLAG_ROAD | FLAG_GRASS).value, 24)
    assert_equal((FLAG_WALKABLE & FLAG_ROAD).value, 8)
    assert_equal(flags_of(AREA_BLOCK).value, 1)
    assert_equal(flags_of(AREA_SIDEWALK).value, 2)
    assert_equal(flags_of(AREA_GRASS).value, 16)
    with assert_raises(contains="area is not valid"):
        _ = flags_of(NavArea(9))
    assert_true(NO_POLYGON.is_valid())
    assert_false(NavPolygonId(-2).is_valid())
    assert_false(EventResult(3).is_valid())
    assert_false(EventResult(-1).is_valid())
    assert_true(EVENT_TIME_OUT.is_valid())
    assert_false(WalkerEventKind(3).is_valid())
    assert_false(WalkerEventKind(-1).is_valid())
    assert_true(EVENT_STOP_AND_CHECK.is_valid())
    assert_false(WalkerState(4).is_valid())
    assert_false(WalkerState(-1).is_valid())
    assert_true(WALKER_STOP.is_valid())


def test_filters() raises:
    var all = NavQueryFilter()
    assert_true(all.passes(FLAG_ROAD))
    assert_equal(all.area_cost(AREA_ROAD), 1)
    var zero = walker_filter(False)
    assert_true(zero.passes(FLAG_SIDEWALK))
    assert_true(zero.passes(FLAG_CROSSWALK))
    assert_false(zero.passes(FLAG_ROAD))
    assert_false(zero.passes(FLAG_NONE))
    assert_equal(zero.area_cost(AREA_ROAD), 10)
    assert_equal(zero.area_cost(AREA_GRASS), 1)
    var one = walker_filter(True)
    assert_true(one.passes(FLAG_ROAD))
    assert_false(one.passes(FLAG_NONE))
    var side = sidewalk_filter()
    assert_true(side.passes(FLAG_SIDEWALK))
    assert_false(side.passes(FLAG_CROSSWALK))
    var custom = NavQueryFilter(FLAG_ROAD, FLAG_NONE)
    custom.set_area_cost(AREA_ROAD, 2.5)
    assert_equal(custom.area_cost(AREA_ROAD), 2.5)
    with assert_raises(contains="at least 1"):
        custom.set_area_cost(AREA_ROAD, 0.5)
    with assert_raises(contains="area is not valid"):
        custom.set_area_cost(NavArea(7), 2)
    with assert_raises(contains="area is not valid"):
        _ = custom.area_cost(NavArea(7))
    with assert_raises(contains="flags are not valid"):
        _ = NavQueryFilter(NavFlags(-1), FLAG_NONE)
    with assert_raises(contains="flags are not valid"):
        _ = NavQueryFilter(FLAG_ROAD, NavFlags(1 << 20))


# --- polygons ------------------------------------------------------------------------


def test_polygon_basics() raises:
    # Given clockwise, stored counter-clockwise.
    var cw = List[Vector3]()
    cw.append(Vector3(0, 0, 0))
    cw.append(Vector3(0, 2, 2))
    cw.append(Vector3(2, 2, 2))
    cw.append(Vector3(2, 0, 0))
    var p = NavPolygon(cw^, AREA_ROAD)
    assert_equal(p.vertices[1].x, 2)
    assert_equal(p.size, 4)
    _near(p.center, 1, 1)
    assert_true(p.contains(Vector3(1, 1, 0)))
    assert_true(p.contains(Vector3(2, 1, 0)))
    assert_false(p.contains(Vector3(2.01, 1, 0)))
    # The quad slopes up along y: z = y.
    assert_almost_equal(p.height_at(Vector3(0.5, 1.5, 0)), 1.5, atol=1e-6)
    assert_almost_equal(p.height_at(Vector3(1.5, 0.5, 0)), 0.5, atol=1e-6)
    var inside = p.closest_point(Vector3(1, 0.25, 9))
    assert_almost_equal(inside.z, 0.25, atol=1e-6)
    var outside = p.closest_point(Vector3(3, 1, 0))
    _near(outside, 2, 1)
    assert_almost_equal(outside.z, 1, atol=1e-6)
    with assert_raises(contains="three corners"):
        var two = _rect(0, 0, 1, 1)
        _ = two.pop()
        _ = two.pop()
        _ = NavPolygon(two^, AREA_ROAD)
    var flat = List[Vector3]()
    flat.append(Vector3(0, 0, 0))
    flat.append(Vector3(1, 1, 0))
    flat.append(Vector3(2, 2, 0))
    with assert_raises(contains="needs an area"):
        _ = NavPolygon(flat^, AREA_ROAD)
    with assert_raises(contains="area is not valid"):
        _ = NavPolygon(_rect(0, 0, 1, 1), NavArea(8))


def test_portals() raises:
    var mesh = _street()
    assert_equal(mesh.polygon_count(), 9)
    # R0 meets S0 along y = 2 for x 0..3 and S1 for x 3..4.
    var r0 = mesh.polygons[3].copy()
    var found = 0
    for portal in r0.portals:
        if portal.neighbor == 0:
            found += 1
            assert_almost_equal(abs(portal.a.x - portal.b.x), 3, atol=1e-6)
        if portal.neighbor == 1:
            found += 1
            assert_almost_equal(abs(portal.a.x - portal.b.x), 1, atol=1e-6)
    assert_equal(found, 2)
    # R0 has S0, S1, R1, N0 and N1: 5 neighbors. S0 has S1 and R0.
    assert_equal(len(r0.portals), 5)
    assert_equal(len(mesh.polygons[0].portals), 2)
    # A step higher than 0.5 m is no portal; a corner is no portal.
    var steps = NavMesh()
    _ = steps.add_polygon(_rect(0, 0, 1, 1), AREA_SIDEWALK)
    var high = _rect(1, 0, 2, 1)
    for i in range(4):
        high[i].z = 0.6
    _ = steps.add_polygon(high^, AREA_SIDEWALK)
    _ = steps.add_polygon(_rect(2, 1, 3, 2), AREA_SIDEWALK)
    var low = _rect(0, 1, 1, 2)
    for i in range(4):
        low[i].z = 0.4
    _ = steps.add_polygon(low^, AREA_SIDEWALK)
    steps.connect()
    assert_equal(len(steps.polygons[0].portals), 1)
    assert_equal(steps.polygons[0].portals[0].neighbor, 3)
    assert_equal(len(steps.polygons[1].portals), 0)
    assert_equal(len(steps.polygons[2].portals), 0)


def test_polygon_ids_are_checked() raises:
    var mesh = _street()
    assert_equal(mesh.area_of(NavPolygonId(4)).value, AREA_CROSSWALK.value)
    with assert_raises(contains="names no polygon"):
        _ = mesh.area_of(NavPolygonId(9))
    with assert_raises(contains="names no polygon"):
        _ = mesh.area_of(NO_POLYGON)
    with assert_raises(contains="names no polygon"):
        _ = mesh.area_of(NavPolygonId(-3))
    _near(
        mesh.closest_point_on_polygon(NavPolygonId(0), Vector3(1, 5, 0)), 1, 2
    )


def test_nearest_polygon() raises:
    var mesh = _street()
    var zero = walker_filter(False)
    var s1 = mesh.find_nearest_polygon(Vector3(5, 1, 0.9), zero).value()
    assert_equal(s1[0].value, 1)
    _near(s1[1], 5, 1)
    # On the road, filter 0 finds the sidewalk 1 m off; filter 1 the road.
    var off = mesh.find_nearest_polygon(Vector3(1, 3, 0), zero).value()
    assert_equal(off[0].value, 0)
    _near(off[1], 1, 2)
    var on = mesh.find_nearest_polygon(Vector3(1, 3, 0), walker_filter(True))
    assert_equal(on.value()[0].value, 3)
    # Out of the box: too far across, or too high.
    assert_false(Bool(mesh.find_nearest_polygon(Vector3(1, 13, 0), zero)))
    assert_false(Bool(mesh.find_nearest_polygon(Vector3(1, 1, 5), zero)))
    # In the middle of the road, with a box 1 m across: 2 m to either
    # sidewalk.
    assert_false(
        Bool(
            mesh.find_nearest_polygon(Vector3(1, 4, 0), zero, Vector3(1, 1, 4))
        )
    )
    assert_false(
        Bool(
            mesh.find_nearest_polygon(
                Vector3(5, 1, 0), NavQueryFilter(FLAG_GRASS, NavFlags(0))
            )
        )
    )


# --- paths ------------------------------------------------------------------------------


def test_path_uses_the_crosswalk() raises:
    # Filter 0 keeps off the road: S0, S1, the crosswalk, N1, N0.
    var mesh = _street()
    var zero = walker_filter(False)
    var start = Vector3(1, 1, 0)
    var goal = Vector3(1, 7, 0)
    var path = mesh.find_path(
        NavPolygonId(0), NavPolygonId(6), start, goal, zero
    )
    assert_equal(_ids(path), "0 1 4 7 6 ")
    # The taut path turns at the crosswalk's corners (4, 2) and (4, 6).
    var points = mesh.find_straight_path(start, goal, path)
    assert_equal(len(points), 4)
    _near(points[0].location, 1, 1)
    assert_equal(points[0].area.value, AREA_SIDEWALK.value)
    _near(points[1].location, 4, 2)
    assert_equal(points[1].area.value, AREA_CROSSWALK.value)
    _near(points[2].location, 4, 6)
    assert_equal(points[2].area.value, AREA_SIDEWALK.value)
    _near(points[3].location, 1, 7)
    assert_equal(points[3].area.value, AREA_SIDEWALK.value)
    # Limits on the lengths.
    assert_equal(
        len(
            mesh.find_path(
                NavPolygonId(0), NavPolygonId(6), start, goal, zero, 2
            )
        ),
        2,
    )
    assert_equal(len(mesh.find_straight_path(start, goal, path, 2)), 2)


def test_path_across_the_road() raises:
    # With a road cost of 1, the straight way across R0 is cheapest. Its
    # points: the start, the road's edge at y = 2, the far sidewalk at
    # y = 6, and the goal.
    var mesh = _street()
    var cheap = walker_filter(True)
    cheap.set_area_cost(AREA_ROAD, 1)
    var start = Vector3(1, 1, 0)
    var goal = Vector3(1, 7, 0)
    var path = mesh.find_path(
        NavPolygonId(0), NavPolygonId(6), start, goal, cheap
    )
    assert_equal(_ids(path), "0 3 6 ")
    var points = mesh.find_straight_path(start, goal, path)
    assert_equal(len(points), 4)
    _near(points[1].location, 1, 2)
    assert_equal(points[1].area.value, AREA_ROAD.value)
    _near(points[2].location, 1, 6)
    assert_equal(points[2].area.value, AREA_SIDEWALK.value)
    # At a cost of 10 the crosswalk is cheaper: about 12.5 against 42.
    var costly = mesh.find_path(
        NavPolygonId(0), NavPolygonId(6), start, goal, walker_filter(True)
    )
    assert_equal(_ids(costly), "0 1 4 7 6 ")


def test_partial_path() raises:
    # On sidewalks only there is no way across: the path ends at S0, the
    # polygon nearest the goal, and the goal moves to S0's edge.
    var mesh = _street()
    var nav = Navigation(_street())
    var path = mesh.find_path(
        NavPolygonId(0),
        NavPolygonId(6),
        Vector3(1, 1, 0),
        Vector3(1, 7, 0),
        sidewalk_filter(),
    )
    assert_equal(_ids(path), "0 ")
    var points = (
        nav.get_path(Vector3(1, 1, 0), Vector3(1, 7, 0), sidewalk_filter())
        .value()
        .copy()
    )
    assert_equal(len(points), 2)
    _near(points[1].location, 1, 2)
    # The default filter walks everywhere walkable.
    assert_equal(
        len(nav.get_path(Vector3(1, 1, 0), Vector3(1, 7, 0)).value()), 4
    )
    # No polygon near an end: no path.
    assert_false(Bool(nav.get_path(Vector3(1, 1, 0), Vector3(50, 50, 0))))


def test_straight_path_funnel_turns() raises:
    # An L: east along the bottom, then north up the right. The taut
    # path turns at the inner corner (2, 1), on the left, then (with the
    # mirror) at (2, 1) on the right.
    var mesh = NavMesh()
    _ = mesh.add_polygon(_rect(0, 0, 2, 1), AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(2, 0, 3, 1), AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(2, 1, 3, 3), AREA_SIDEWALK)
    mesh.connect()
    var up = mesh.find_straight_path(
        Vector3(0.5, 0.5, 0),
        Vector3(2.5, 2.5, 0),
        [NavPolygonId(0), NavPolygonId(1), NavPolygonId(2)],
    )
    assert_equal(len(up), 3)
    _near(up[1].location, 2, 1)
    var down = mesh.find_straight_path(
        Vector3(2.5, 2.5, 0),
        Vector3(0.5, 0.5, 0),
        [NavPolygonId(2), NavPolygonId(1), NavPolygonId(0)],
    )
    assert_equal(len(down), 3)
    _near(down[1].location, 2, 1)
    # A margin keeps 0.3 m from the corner along each portal.
    var kept = mesh.find_straight_path(
        Vector3(0.5, 0.5, 0),
        Vector3(2.5, 2.5, 0),
        [NavPolygonId(0), NavPolygonId(1), NavPolygonId(2)],
        256,
        Length(0.3, METER),
    )
    _near(kept[1].location, 2, 0.7)
    _near(kept[2].location, 2.3, 1)
    # A narrow portal shrinks to its middle.
    var narrow = mesh.find_straight_path(
        Vector3(0.5, 0.5, 0),
        Vector3(2.5, 2.5, 0),
        [NavPolygonId(0), NavPolygonId(1), NavPolygonId(2)],
        256,
        Length(0.8, METER),
    )
    _near(narrow[1].location, 2, 0.5)
    with assert_raises(contains="needs a polygon path"):
        _ = mesh.find_straight_path(
            Vector3(0, 0, 0), Vector3(1, 1, 0), List[NavPolygonId]()
        )
    with assert_raises(contains="not neighbors"):
        _ = mesh.find_straight_path(
            Vector3(0.5, 0.5, 0),
            Vector3(2.5, 2.5, 0),
            [NavPolygonId(0), NavPolygonId(2)],
        )


def test_intersection_helper() raises:
    # (0, 0)-(2, 2) meets the portal x = 1 at y = 1; a parallel portal
    # gives its middle.
    _near(
        _intersect(
            Vector3(0, 0, 0),
            Vector3(2, 2, 0),
            Vector3(1, 0, 0),
            Vector3(1, 4, 0),
        ),
        1,
        1,
    )
    _near(
        _intersect(
            Vector3(0, 0, 0),
            Vector3(2, 2, 0),
            Vector3(1, 0, 0),
            Vector3(3, 2, 0),
        ),
        2,
        1,
    )


def test_random_points() raises:
    # S1 has 8 square meters of the 40 of sidewalk: about 20% of the
    # points, 200 of 1000 with a spread of about 13.
    var mesh = _street()
    var random = SensorRandom(3)
    var in_s1 = 0
    for _ in range(1000):
        var hit = mesh.find_random_point(sidewalk_filter(), random).value()
        var poly = mesh.polygons[hit[0].value].copy()
        assert_true(poly.area == AREA_SIDEWALK)
        assert_true(poly.contains(hit[1]))
        if hit[0].value == 1:
            in_s1 += 1
    assert_true(in_s1 > 160 and in_s1 < 240)
    assert_false(
        Bool(
            mesh.find_random_point(
                NavQueryFilter(FLAG_GRASS, NavFlags(0)), random
            )
        )
    )


# --- the crowd -----------------------------------------------------------------------------


def test_navigation_needs_a_mesh() raises:
    var nav = Navigation(NavMesh())
    var manager = WalkerManager()
    assert_false(nav.ready)
    assert_false(nav.add_walker(manager, ActorId(5), Vector3(0, 0, 0)))
    var info = VehicleCollisionInfo(
        ActorId(6), _pose(0, 0, 0), BoundingBox(Vector3(1, 1, 1))
    )
    assert_false(nav.add_or_update_vehicle(info))
    assert_false(nav.remove_agent(manager, ActorId(5)))
    assert_false(Bool(nav.get_path(Vector3(0, 0, 0), Vector3(1, 0, 0))))
    assert_false(Bool(nav.get_random_location()))
    assert_false(nav.set_walker_direct_target_index(0, Vector3(0, 0, 0)))
    nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_false(nav.set_walker_max_speed(ActorId(5), Velocity(1)))
    assert_false(Bool(nav.get_walker_position(ActorId(5))))


def test_walker_walks_to_its_target() raises:
    # From (1, 0.5) toward (9, 1.5): straight along the sidewalk, at
    # 1.47 m/s from the first step, since 160 m/s^2 reaches it at once.
    var nav = Navigation(_street())
    var manager = WalkerManager()
    var id = ActorId(10)
    assert_true(nav.add_walker(manager, id, Vector3(1, 0.5, AGENT_HEIGHT / 2)))
    _near(nav.get_walker_position(id).value(), 1, 0.5)
    assert_true(nav.set_walker_direct_target(id, Vector3(9, 1.5, 0)))
    for _ in range(20):
        nav.update_crowd(manager, Duration(0.05, SECOND))
    var at = nav.get_walker_position(id).value()
    # 1.47 m along (8, 1) / |(8, 1)|.
    assert_almost_equal(at.x, 1 + 1.47 * 8 / 8.0622577, atol=1e-3)
    assert_almost_equal(at.y, 0.5 + 1.47 / 8.0622577, atol=1e-3)
    assert_almost_equal(nav.get_walker_speed(id).value, 1.47, atol=1e-4)
    # The yaw turns toward atan(1/8) = 7.125 degrees at 0.98 * 6 per
    # second: 7.125 * 5.88 * 0.05 = 2.0948 degrees after one read.
    var pose = nav.get_walker_transform(id).value()
    assert_almost_equal(pose.rotation.yaw, 2.0948, atol=1e-3)
    # A slower walker.
    assert_true(nav.set_walker_max_speed(id, Velocity(0.5)))
    nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_almost_equal(nav.get_walker_speed(id).value, 0.5, atol=1e-4)
    # It slows within 0.6 m of the goal and stops there.
    assert_true(nav.set_walker_max_speed(id, Velocity(1.47)))
    for _ in range(200):
        nav.update_crowd(manager, Duration(0.05, SECOND))
    _near(nav.get_walker_position(id).value(), 9, 1.5, 1e-2)
    assert_true(nav.get_walker_speed(id).value < 0.05)
    # Paused, it stands.
    nav.pause_agent(id, True)
    assert_true(nav.set_walker_direct_target(id, Vector3(1, 1, 0)))
    nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_equal(nav.get_walker_speed(id).value, 0)
    assert_true(nav.is_walker_alive(id).value())
    assert_false(Bool(nav.is_walker_alive(ActorId(99))))
    # A target far from the mesh is refused.
    assert_false(nav.set_walker_direct_target(id, Vector3(50, 50, 0)))
    assert_false(nav.set_walker_direct_target(ActorId(99), Vector3(1, 1, 0)))
    assert_equal(nav.get_walker_speed(ActorId(99)).value, 0)
    assert_equal(nav.get_walker_velocity(ActorId(99)).x, 0)
    assert_false(Bool(nav.get_walker_transform(ActorId(99))))
    nav.pause_agent(ActorId(99), True)
    assert_false(
        Bool(
            nav.get_agent_route(ActorId(99), Vector3(1, 1, 0), Vector3(2, 1, 0))
        )
    )


def test_walker_is_placed_on_the_mesh() raises:
    var nav = Navigation(_street())
    var manager = WalkerManager()
    # Nothing near: refused.
    assert_false(nav.add_walker(manager, ActorId(1), Vector3(50, 50, 0.9)))
    # The crowd holds 500 agents.
    for i in range(MAX_AGENTS):
        assert_true(nav.add_walker(manager, ActorId(i + 2), Vector3(5, 1, 0.9)))
    assert_false(nav.add_walker(manager, ActorId(1000), Vector3(5, 1, 0.9)))
    var box = VehicleCollisionInfo(
        ActorId(2000), _pose(5, 4, 0), BoundingBox(Vector3(2.4, 1, 0.75))
    )
    assert_false(nav.add_or_update_vehicle(box))
    # A removed agent frees its slot.
    assert_true(nav.remove_agent(manager, ActorId(2)))
    assert_false(nav.remove_agent(manager, ActorId(2)))
    assert_true(nav.add_or_update_vehicle(box))
    assert_equal(nav.mapped_vehicles[2000], 0)


def test_cross_factor_draws() raises:
    # A Python model of the generator: with seed 42, 51 of the first 100
    # draws are at most 0.5; with seed 7, 31 are at most 0.25.
    for trial in range(2):
        var nav = Navigation(_street())
        var manager = WalkerManager()
        nav.set_seed(42 if trial == 0 else 7)
        nav.set_pedestrians_cross_factor(Float32(0.5 if trial == 0 else 0.25))
        var crossing = 0
        for i in range(100):
            _ = nav.add_walker(manager, ActorId(i + 1), Vector3(5, 1, 0.9))
            crossing += nav.agents[i].filter_index
        assert_equal(crossing, 51 if trial == 0 else 31)


def test_walkers_keep_apart() raises:
    # Two idle walkers 0.5 m apart push each other toward the range of
    # 2 (0.3 + 0.3) = 1.2 m. The gap e = 1.2 - d closes as
    # de/dt = -1.47 (e / 1.2)^2: after 7.5 s, e = 0.7 / (1 + 1.47 / 1.44
    # * 0.7 * 7.5) = 0.11, so d is about 1.09. (At 8 s a still walker
    # would get a new route.)
    var nav = Navigation(_street())
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(5, 1, 0.9))
    _ = nav.add_walker(manager, ActorId(2), Vector3(5.5, 1, 0.9))
    for _ in range(150):
        nav.update_crowd(manager, Duration(0.05, SECOND))
    var a = nav.get_walker_position(ActorId(1)).value()
    var b = nav.get_walker_position(ActorId(2)).value()
    var d = a.distance_to(b)
    assert_true(d > 1.05 and d < 1.13)
    assert_true(a.x < 5 and b.x > 5.5)


def test_vehicles_in_the_crowd() raises:
    # A car of half size (2.4, 1) at (5, 4) facing +x: the grown box runs
    # from x = 1.8 to 8.4 and y = 2.2 to 5.8.
    var info = VehicleCollisionInfo(
        ActorId(50), _pose(5, 4, 0), BoundingBox(Vector3(2.4, 1, 0.75))
    )
    var corners = vehicle_box(info)
    _near(corners[0], 1.8, 2.2)
    _near(corners[1], 8.4, 2.2)
    _near(corners[2], 8.4, 5.8)
    _near(corners[3], 1.8, 5.8)
    # Facing +y the front grows toward +y.
    var turned = vehicle_box(
        VehicleCollisionInfo(
            ActorId(50), _pose(0, 0, 90), BoundingBox(Vector3(2.4, 1, 0.75))
        )
    )
    _near(turned[1], 1.8, 3.4)
    var nav = Navigation(_street())
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(5, 1, 0.9))
    assert_true(nav.add_or_update_vehicle(info))
    # 1.2 m to the box's edge, ahead toward the road.
    assert_true(
        nav.has_vehicle_near(ActorId(1), Length(6, METER), Vector3(0, 1, 0))
    )
    assert_false(
        nav.has_vehicle_near(ActorId(1), Length(1, METER), Vector3(0, 1, 0))
    )
    assert_false(
        nav.has_vehicle_near(ActorId(1), Length(6, METER), Vector3(0, -1, 0))
    )
    assert_false(
        nav.has_vehicle_near(ActorId(77), Length(6, METER), Vector3(0, 1, 0))
    )
    # From the vehicle itself: the walker is no vehicle.
    assert_false(
        nav.has_vehicle_near(ActorId(50), Length(6, METER), Vector3(0, 1, 0))
    )
    # A walker inside a box always has it near.
    info.transform = _pose(5, 1, 0)
    assert_true(nav.add_or_update_vehicle(info))
    assert_true(
        nav.has_vehicle_near(ActorId(1), Length(0.1, METER), Vector3(0, -1, 0))
    )
    # The walker keeps clear of a box 0.7 m away: it moves off, to -y.
    info.transform = _pose(5, 3.5, 0)
    var manager2 = WalkerManager()
    var nav2 = Navigation(_street())
    _ = nav2.add_walker(manager2, ActorId(1), Vector3(5, 1, 0.9))
    _ = nav2.add_or_update_vehicle(info)
    for _ in range(20):
        nav2.update_crowd(manager2, Duration(0.05, SECOND))
    assert_true(nav2.get_walker_position(ActorId(1)).value().y < 1)
    # A walker inside a box is pushed out too.
    var nav3 = Navigation(_street())
    var manager3 = WalkerManager()
    _ = nav3.add_walker(manager3, ActorId(1), Vector3(5, 1.9, 0.9))
    info.transform = _pose(5, 3.0, 0)
    _ = nav3.add_or_update_vehicle(info)
    for _ in range(20):
        nav3.update_crowd(manager3, Duration(0.05, SECOND))
    assert_true(nav3.get_walker_position(ActorId(1)).value().y < 1.9)
    # A vehicle no longer listed leaves the crowd.
    assert_true(nav.update_vehicles(manager, List[VehicleCollisionInfo]()))
    assert_equal(len(nav.mapped_vehicles), 0)
    var list = List[VehicleCollisionInfo]()
    list.append(info)
    _ = nav.update_vehicles(manager, list)
    assert_equal(len(nav.mapped_vehicles), 1)
    assert_true(nav.remove_agent(manager, ActorId(50)))


def test_look_at() raises:
    var nav = Navigation(_street())
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(5, 1, 0.9))
    assert_true(nav.set_walker_look_at(ActorId(1), Vector3(5, 101, 0)))
    assert_almost_equal(nav.get_walker_velocity(ActorId(1)).y, 0.01, atol=1e-7)
    var info = VehicleCollisionInfo(
        ActorId(50), _pose(5, 4, 0), BoundingBox(Vector3(2.4, 1, 0.75))
    )
    _ = nav.add_or_update_vehicle(info)
    assert_true(nav.set_walker_look_at(ActorId(50), Vector3(5, 5, 0)))
    assert_false(nav.set_walker_look_at(ActorId(77), Vector3(5, 5, 0)))


def test_stuck_walker_gets_a_new_route() raises:
    # Checks at 4.2 s and 8.4 s: at the first the walker has moved from
    # the origin, at the second it has not moved, so it gets a route.
    var nav = Navigation(_street())
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(1, 1, 0.9))
    for _ in range(14):
        nav.update_crowd(manager, Duration(0.3, SECOND))
    assert_equal(len(manager.walkers[1].route), 0)
    for _ in range(14):
        nav.update_crowd(manager, Duration(0.3, SECOND))
    assert_true(len(manager.walkers[1].route) >= 2)
    # A paused walker is left alone.
    var nav2 = Navigation(_street())
    var manager2 = WalkerManager()
    _ = nav2.add_walker(manager2, ActorId(1), Vector3(1, 1, 0.9))
    nav2.pause_agent(ActorId(1), True)
    for _ in range(28):
        nav2.update_crowd(manager2, Duration(0.3, SECOND))
    assert_equal(len(manager2.walkers[1].route), 0)


# --- the walker manager -------------------------------------------------------------------


def test_route_events() raises:
    # Filter 0 across the street: the crosswalk's first corner stops and
    # checks; the other points go on at once.
    var nav = Navigation(_street())
    var manager = WalkerManager()
    var id = ActorId(1)
    _ = nav.add_walker(manager, id, Vector3(1, 1, 0.9))
    assert_true(nav.set_walker_target(manager, id, Vector3(1, 7, 0)))
    ref info = manager.walkers[1]
    assert_equal(len(info.route), 4)
    assert_equal(info.route[0].event.kind.value, EVENT_IGNORE.value)
    assert_equal(info.route[1].event.kind.value, EVENT_STOP_AND_CHECK.value)
    assert_equal(info.route[1].event.time.value, 60)
    assert_true(info.route[1].event.check_for_traffic_light)
    assert_equal(info.route[2].event.kind.value, EVENT_IGNORE.value)
    assert_equal(info.current_index, 1)
    assert_equal(info.state.value, WALKER_WALKING.value)
    _near(manager.get_walker_next_point(id).value(), 4, 2)
    _near(manager.get_walker_crosswalk_end(id).value(), 4, 6)
    assert_false(Bool(manager.get_walker_next_point(ActorId(9))))
    assert_false(Bool(manager.get_walker_crosswalk_end(ActorId(9))))
    assert_false(nav.set_walker_target(manager, ActorId(9), Vector3(1, 7, 0)))
    # Across the road, only the first road point is kept.
    var cross = Navigation(_street())
    var m2 = WalkerManager()
    cross.set_pedestrians_cross_factor(1.0)
    _ = cross.add_walker(m2, id, Vector3(1, 1, 0.9))
    cross.filters[1].set_area_cost(AREA_ROAD, 1)
    _ = cross.set_walker_target(m2, id, Vector3(1, 7, 0))
    assert_equal(len(m2.walkers[1].route), 4)
    assert_equal(
        m2.walkers[1].route[1].event.kind.value, EVENT_STOP_AND_CHECK.value
    )
    assert_equal(m2.walkers[1].route[1].area.value, AREA_ROAD.value)


def test_walker_crosses_on_red_and_waits_on_green() raises:
    var nav = Navigation(_street())
    var manager = WalkerManager()
    var id = ActorId(1)
    var light = ActorId(7)
    var lights = List[WalkerTrafficLight]()
    lights.append(WalkerTrafficLight(light, Vector3(5, 2, 0), GREEN))
    # A far light that the walker must not read.
    lights.append(WalkerTrafficLight(ActorId(8), Vector3(90, 90, 0), RED))
    manager.set_traffic_lights(lights^)
    _ = nav.add_walker(manager, id, Vector3(1, 1, 0.9))
    _ = nav.set_walker_target(manager, id, Vector3(1, 7, 0))
    # About 3.2 m to the crosswalk's corner: there in about 2.2 s.
    for _ in range(60):
        nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].state.value, WALKER_IN_EVENT.value)
    assert_true(nav.agents[0].paused)
    assert_equal(manager.walkers[1].route[1].event.actor.value(), light)
    # Yellow is still for the cars.
    manager.set_light_state(light, YELLOW)
    nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].state.value, WALKER_IN_EVENT.value)
    # Red: the walker goes on across.
    manager.set_light_state(light, RED)
    nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].current_index, 2)
    var highest = Float32(0)
    for _ in range(200):
        nav.update_crowd(manager, Duration(0.05, SECOND))
        highest = max(highest, nav.get_walker_position(id).value().y)
    assert_true(highest > 6.5)


def test_walker_waits_for_a_vehicle() raises:
    var nav = Navigation(_street())
    var manager = WalkerManager()
    var id = ActorId(1)
    _ = nav.add_walker(manager, id, Vector3(1, 1, 0.9))
    _ = nav.set_walker_target(manager, id, Vector3(1, 7, 0))
    var car = VehicleCollisionInfo(
        ActorId(50), _pose(5, 4.5, 0), BoundingBox(Vector3(2.4, 1, 0.75))
    )
    _ = nav.add_or_update_vehicle(car)
    for _ in range(60):
        nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].state.value, WALKER_IN_EVENT.value)
    assert_equal(manager.walkers[1].current_index, 1)
    # The car leaves: the walker goes.
    _ = nav.remove_agent(manager, ActorId(50))
    nav.update_crowd(manager, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].current_index, 2)


def test_stop_and_check_times_out() raises:
    # After 60 s a walker gives up and takes a random route.
    var nav = Navigation(_street())
    var manager = WalkerManager()
    var id = ActorId(1)
    var lights = List[WalkerTrafficLight]()
    lights.append(WalkerTrafficLight(ActorId(7), Vector3(5, 2, 0), GREEN))
    manager.set_traffic_lights(lights^)
    _ = nav.add_walker(manager, id, Vector3(1, 1, 0.9))
    _ = nav.set_walker_target(manager, id, Vector3(1, 7, 0))
    for _ in range(60):
        nav.update_crowd(manager, Duration(0.05, SECOND))
    var first = manager.walkers[1].to
    for _ in range(61):
        nav.update_crowd(manager, Duration(1, SECOND))
    assert_false(manager.walkers[1].to == first)


def test_events_one_by_one() raises:
    var nav = Navigation(_street())
    var manager = WalkerManager()
    var id = ActorId(1)
    _ = nav.add_walker(manager, id, Vector3(1, 1, 0.9))
    ref info = manager.walkers[1]
    info.route.append(
        WalkerRoutePoint(ignore_event(), Vector3(1, 1, 0), AREA_SIDEWALK)
    )
    info.route.append(
        WalkerRoutePoint(
            wait_event(Duration(0.1, SECOND)), Vector3(1, 1, 0), AREA_SIDEWALK
        )
    )
    info.route.append(
        WalkerRoutePoint(ignore_event(), Vector3(2, 1, 0), AREA_SIDEWALK)
    )
    info.current_index = 1
    info.state = WALKER_IN_EVENT
    # The wait of 0.1 s: continue after 0.05 s, end after 0.1 s.
    _ = manager.update(nav, Duration(0.06, SECOND))
    assert_equal(manager.walkers[1].state.value, WALKER_IN_EVENT.value)
    _ = manager.update(nav, Duration(0.06, SECOND))
    assert_equal(manager.walkers[1].current_index, 2)
    assert_equal(manager.walkers[1].state.value, WALKER_WALKING.value)
    # An ignore event ends at once.
    manager.walkers[1].state = WALKER_IN_EVENT
    manager.walkers[1].current_index = 0
    _ = manager.update(nav, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].current_index, 1)
    # Past the end the walker stops and replans; a stop turns idle.
    manager.walkers[1].current_index = 2
    _ = manager.set_walker_next_point(nav, id)
    assert_true(len(manager.walkers[1].route) >= 2)
    manager.walkers[1].state = WALKER_STOP
    _ = manager.update(nav, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].state.value, WALKER_IDLE.value)
    _ = manager.update(nav, Duration(0.05, SECOND))
    assert_equal(manager.walkers[1].state.value, WALKER_IDLE.value)
    assert_false(manager.set_walker_next_point(nav, ActorId(9)))
    assert_true(manager.set_walker_route(nav, id))
    assert_false(manager.set_walker_route(nav, ActorId(9)))
    assert_true(manager.remove_walker(id))
    assert_false(manager.remove_walker(id))


def test_traffic_light_affecting() raises:
    var manager = WalkerManager()
    assert_false(Bool(manager.get_traffic_light_affecting(Vector3(0, 0, 0))))
    var lights = List[WalkerTrafficLight]()
    lights.append(WalkerTrafficLight(ActorId(7), Vector3(10, 0, 0), RED))
    lights.append(WalkerTrafficLight(ActorId(8), Vector3(3, 4, 0), RED))
    manager.set_traffic_lights(lights^)
    var near = manager.get_traffic_light_affecting(Vector3(0, 0, 0))
    assert_equal(near.value().actor, ActorId(8))
    assert_true(
        Bool(
            manager.get_traffic_light_affecting(
                Vector3(0, 0, 0), Length(5.5, METER)
            )
        )
    )
    assert_false(
        Bool(
            manager.get_traffic_light_affecting(
                Vector3(0, 0, 0), Length(4.5, METER)
            )
        )
    )
    manager.set_light_state(ActorId(8), GREEN)
    assert_equal(manager.traffic_lights[1].state.value, GREEN.value)
    assert_equal(manager.traffic_lights[0].state.value, RED.value)
    # A walker added twice keeps one place in the order.
    _ = manager.add_walker(ActorId(3))
    _ = manager.add_walker(ActorId(3))
    assert_equal(len(manager.order), 1)


def test_no_random_point_no_route() raises:
    # Grass only: no sidewalk for a random point.
    var mesh = NavMesh()
    _ = mesh.add_polygon(_rect(0, 0, 2, 2), AREA_GRASS)
    mesh.connect()
    var nav = Navigation(mesh^)
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(1, 1, 0.9))
    assert_false(Bool(nav.get_random_location()))
    assert_false(manager.set_walker_route(nav, ActorId(1)))
    var location = nav.get_random_location(NavQueryFilter())
    assert_true(Bool(location))


# --- corners -------------------------------------------------------------------------------


def test_mesh_corners() raises:
    var point = NavPoint(Vector3(1, 2, 0), AREA_SIDEWALK)
    assert_true("area=1" in String(point))
    var empty = NavMesh()
    empty.connect()
    assert_equal(empty.polygon_count(), 0)
    var random = SensorRandom(1)
    assert_false(Bool(empty.find_random_point(NavQueryFilter(), random)))
    # A side split in two along one line: two equal parts, one portal.
    var mesh = NavMesh()
    var five = _rect(0, 0, 1, 1)
    five.insert(2, Vector3(1, 0.5, 0))
    _ = mesh.add_polygon(five^, AREA_SIDEWALK)
    _ = mesh.add_polygon(_rect(1, 0, 2, 1), AREA_SIDEWALK)
    # An edge of 1 cm is too short to share.
    var short = List[Vector3]()
    short.append(Vector3(2, 1, 0))
    short.append(Vector3(3, 1, 0))
    short.append(Vector3(3, 1.01, 0))
    short.append(Vector3(2, 2, 0))
    _ = mesh.add_polygon(short^, AREA_SIDEWALK)
    # A ramp that rises 1.2 m at its far corner of the shared edge.
    var ramp = _rect(0, 1, 1, 2)
    ramp[0].z = 1.2
    _ = mesh.add_polygon(ramp^, AREA_SIDEWALK)
    mesh.connect()
    assert_equal(len(mesh.polygons[0].portals), 1)
    assert_equal(mesh.polygons[0].portals[0].neighbor, 1)
    assert_almost_equal(
        mesh.polygons[0]
        .portals[0]
        .a.distance_to(mesh.polygons[0].portals[0].b),
        0.5,
        atol=1e-6,
    )
    for p in mesh.polygons[3].portals:
        assert_true(p.neighbor != 0)
    # An island: the path is the start alone, and nothing to go through.
    var island = NavMesh()
    _ = island.add_polygon(_rect(0, 0, 1, 1), AREA_SIDEWALK)
    _ = island.add_polygon(_rect(5, 0, 6, 1), AREA_SIDEWALK)
    island.connect()
    var alone = island.find_path(
        NavPolygonId(0),
        NavPolygonId(1),
        Vector3(0.5, 0.5, 0),
        Vector3(5.5, 0.5, 0),
        NavQueryFilter(),
    )
    assert_equal(_ids(alone), "0 ")
    with assert_raises(contains="not neighbors"):
        _ = island.find_straight_path(
            Vector3(0.5, 0.5, 0),
            Vector3(5.5, 0.5, 0),
            [NavPolygonId(0), NavPolygonId(1)],
        )


def test_start_on_an_area_border() raises:
    # From (1, 2), on the border of S0 and the road: the start takes the
    # road's area, then the far sidewalk at y = 6, then the goal.
    var mesh = _street()
    var points = mesh.find_straight_path(
        Vector3(1, 2, 0),
        Vector3(1, 7, 0),
        [NavPolygonId(0), NavPolygonId(3), NavPolygonId(6)],
    )
    assert_equal(len(points), 3)
    assert_equal(points[0].area.value, AREA_ROAD.value)
    _near(points[1].location, 1, 6)


def test_route_points() raises:
    # Sidewalk, crosswalk, road, sidewalk: the road point right after the
    # crosswalk is left out. Road then crosswalk: the same.
    var path = List[NavPoint]()
    path.append(NavPoint(Vector3(0, 0, 0), AREA_SIDEWALK))
    path.append(NavPoint(Vector3(1, 0, 0), AREA_CROSSWALK))
    path.append(NavPoint(Vector3(2, 0, 0), AREA_ROAD))
    path.append(NavPoint(Vector3(3, 0, 0), AREA_SIDEWALK))
    path.append(NavPoint(Vector3(4, 0, 0), AREA_ROAD))
    path.append(NavPoint(Vector3(5, 0, 0), AREA_CROSSWALK))
    path.append(NavPoint(Vector3(6, 0, 0), AREA_GRASS))
    var route = route_points(path)
    assert_equal(len(route), 5)
    assert_equal(route[1].event.kind.value, EVENT_STOP_AND_CHECK.value)
    assert_equal(route[2].location.x, 3)
    assert_equal(route[3].event.kind.value, EVENT_STOP_AND_CHECK.value)
    assert_equal(route[3].location.x, 4)
    assert_equal(route[4].area.value, AREA_GRASS.value)
    assert_equal(len(route_points(List[NavPoint]())), 0)


def test_crowd_corners() raises:
    # An island goal: the path ends on the start's island, and the target
    # moves to its edge nearest the goal.
    var island = NavMesh()
    _ = island.add_polygon(_rect(0, 0, 1, 1), AREA_SIDEWALK)
    _ = island.add_polygon(_rect(5, 0, 6, 1), AREA_SIDEWALK)
    island.connect()
    var nav = Navigation(island^)
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(0.5, 0.5, 0.9))
    assert_true(nav.set_walker_direct_target(ActorId(1), Vector3(5.5, 0.5, 0)))
    _near(nav.agents[0].target.value(), 1, 0.5)
    # A walker moved off its corridor plans again.
    var street = Navigation(_street())
    var m2 = WalkerManager()
    _ = street.add_walker(m2, ActorId(1), Vector3(1, 1, 0.9))
    _ = street.set_walker_direct_target(ActorId(1), Vector3(9, 1, 0))
    street.agents[0].position = Vector3(1, 7, 0)
    street.update_crowd(m2, Duration(0.05, SECOND))
    assert_equal(street.agents[0].corridor[0].value, 6)
    # A short step: 160 m/s^2 for 5 ms reaches 0.8 m/s.
    var fresh = Navigation(_street())
    var m3 = WalkerManager()
    _ = fresh.add_walker(m3, ActorId(1), Vector3(1, 1, 0.9))
    _ = fresh.set_walker_direct_target(ActorId(1), Vector3(9, 1, 0))
    fresh.update_crowd(m3, Duration(0.005, SECOND))
    assert_almost_equal(
        fresh.get_walker_speed(ActorId(1)).value, 0.8, atol=1e-5
    )
    # Walkers on one spot do not push; one far away is out of range.
    _ = fresh.add_walker(m3, ActorId(2), Vector3(5, 1, 0.9))
    _ = fresh.add_walker(m3, ActorId(3), Vector3(5, 1, 0.9))
    fresh.update_crowd(m3, Duration(0.05, SECOND))
    _near(fresh.get_walker_position(ActorId(2)).value(), 5, 1)
    _near(fresh.get_walker_position(ActorId(3)).value(), 5, 1)
    # A walker pushed off the mesh in one long step stops: 0.83 m/s for
    # 2 s from y = 0.2 lands 1.45 m past the sidewalk's edge.
    var edge = Navigation(_street())
    var m4 = WalkerManager()
    _ = edge.add_walker(m4, ActorId(1), Vector3(5, 0.2, 0.9))
    _ = edge.add_or_update_vehicle(
        VehicleCollisionInfo(
            ActorId(9), _pose(5, 2.5, 0), BoundingBox(Vector3(2.4, 1, 0.75))
        )
    )
    edge.update_crowd(m4, Duration(2, SECOND))
    assert_equal(edge.get_walker_speed(ActorId(1)).value, 0)
    # A ready crowd with no agent steps.
    var bare = Navigation(_street())
    var m5 = WalkerManager()
    bare.update_crowd(m5, Duration(0.05, SECOND))


def test_unblock_skips() raises:
    # At the 4 s check a removed walker and a vehicle are passed over;
    # on grass there is no random point for a stuck walker.
    var mesh = NavMesh()
    _ = mesh.add_polygon(_rect(0, 0, 4, 4), AREA_GRASS)
    mesh.connect()
    var nav = Navigation(mesh^)
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(1, 1, 0.9))
    _ = nav.add_walker(manager, ActorId(2), Vector3(2, 2, 0.9))
    _ = nav.add_or_update_vehicle(
        VehicleCollisionInfo(
            ActorId(9), _pose(30, 30, 0), BoundingBox(Vector3(2.4, 1, 0.75))
        )
    )
    _ = nav.remove_agent(manager, ActorId(1))
    assert_false(nav.agents[0].active)
    for _ in range(28):
        nav.update_crowd(manager, Duration(0.3, SECOND))
    assert_equal(len(manager.walkers[2].route), 0)
    # An empty crowd passes the 4 s check too.
    var empty_mesh = NavMesh()
    _ = empty_mesh.add_polygon(_rect(0, 0, 4, 4), AREA_GRASS)
    empty_mesh.connect()
    var empty = Navigation(empty_mesh^)
    var nobody = WalkerManager()
    for _ in range(13):
        empty.update_crowd(nobody, Duration(0.3, SECOND))
    assert_true(empty.time_to_unblock > 3.8)
    empty.update_crowd(nobody, Duration(0.3, SECOND))
    assert_equal(empty.time_to_unblock, 0.0)


def test_manager_corners() raises:
    var nav = Navigation(_street())
    var manager = WalkerManager()
    _ = nav.add_walker(manager, ActorId(1), Vector3(1, 1, 0.9))
    _ = nav.add_walker(manager, ActorId(2), Vector3(5, 1, 0.9))
    # The second walker leaves: the first is skipped in the order.
    assert_true(manager.remove_walker(ActorId(2)))
    assert_equal(len(manager.order), 1)
    # No light to set.
    manager.set_light_state(ActorId(7), RED)
    # A goal with no polygon near: no path, an empty route; the walker
    # stops and plans once more to a random point.
    assert_true(
        manager.set_walker_route_to(nav, ActorId(1), Vector3(50, 50, 0))
    )
    assert_true(len(manager.walkers[1].route) >= 2)
    # A walker the manager knows and the crowd does not.
    _ = manager.add_walker(ActorId(5))
    assert_true(manager.set_walker_route_to(nav, ActorId(5), Vector3(1, 1, 0)))
    ref info = manager.walkers[5]
    assert_equal(len(info.route), 0)
    assert_equal(info.state.value, WALKER_STOP.value)
    assert_false(Bool(manager.get_walker_next_point(ActorId(5))))
    assert_false(Bool(manager.get_walker_crosswalk_end(ActorId(5))))
    info.route.append(
        WalkerRoutePoint(ignore_event(), Vector3(1, 1, 0), AREA_SIDEWALK)
    )
    info.route.append(
        WalkerRoutePoint(ignore_event(), Vector3(2, 1, 0), AREA_SIDEWALK)
    )
    info.current_index = 1
    info.state = WALKER_WALKING
    _ = manager.update(nav, Duration(0.05, SECOND))
    assert_equal(manager.walkers[5].state.value, WALKER_WALKING.value)
    # Three lights: the nearest wins over one farther that comes later.
    var lights = List[WalkerTrafficLight]()
    lights.append(WalkerTrafficLight(ActorId(7), Vector3(1, 0, 0), RED))
    lights.append(WalkerTrafficLight(ActorId(8), Vector3(9, 0, 0), RED))
    manager.set_traffic_lights(lights^)
    assert_equal(
        manager.get_traffic_light_affecting(Vector3(0, 0, 0)).value().actor,
        ActorId(7),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
