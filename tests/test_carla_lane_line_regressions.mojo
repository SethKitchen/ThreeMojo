# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Focused LINE controls for lane-center stationary-point refinement.

These six controls supplement the general-curve tests. They do not constitute
the full lane-geometry regression suite.
"""

from extensions.carla.map import (
    Controller,
    Junction,
    Map,
    Signal,
    _distance_is_convex,
    _polynomial_candidates,
)
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road_info import (
    LaneId,
    SectionId,
    RoadInfoElevation,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
)
from extensions.carla.polynomial import CubicPolynomial
from math.vector3 import Vector3
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def _map(
    offset: String = 'a="0" b="0" c="0" d="0"',
    width: String = 'a="3.5" b="0" c="0" d="0"',
    geometry: String = "<line/>",
    rht: Bool = True,
    grade: Float64 = 0.0,
    second: Bool = False,
    outer: Bool = False,
    length: Float64 = 100.0,
) raises -> Map:
    var text = String(
        '<OpenDRIVE><road id="1" length="',
        length,
        '" junction="-1" rule="',
        "RHT" if rht else "LHT",
        '"><planView><geometry s="0" x="0" y="0" hdg="0" length="',
        length,
        '">',
        geometry,
        '</geometry></planView><elevationProfile><elevation s="0" a="0" b="',
        grade,
        '" c="0" d="0"/></elevationProfile><lanes><laneOffset s="0" ',
        offset,
        "/>",
    )
    var count = 2 if second else 1
    for section in range(count):
        text += String('<laneSection s="', section * 50, '">')
        for side in ["left", "right"]:
            var sign = 1 if side == "left" else -1
            text += String("<", side, ">")
            var lanes = 2 if outer else 1
            for index in range(1, lanes + 1):
                text += String(
                    '<lane id="',
                    sign * index,
                    '" type="driving"><width sOffset="0" ',
                    width,
                    "/></lane>",
                )
            text += String("</", side, ">")
        text += '<center><lane id="0" type="none"/></center></laneSection>'
    return load_opendrive(text + "</lanes></road></OpenDRIVE>")


def _query(
    map: Map,
    lane: Int,
    s: Float64,
    x: Float64,
    y: Float64,
    z: Float64 = 0.0,
    section: Int = 0,
) raises:
    # These positions come from the closed-form curve, not compute_transform.
    var point = Vector3(Float32(x), Float32(y), Float32(z))
    var nearest = map.certified_closest_waypoint_on_road(point)
    assert_true(Bool(nearest))
    assert_equal(nearest.value().lane_id, LaneId(lane))
    assert_equal(nearest.value().section_id, SectionId(section))
    assert_almost_equal(nearest.value().s, s, atol=2e-4)
    var under = map.certified_waypoint(point)
    assert_true(Bool(under))
    assert_equal(under.value().lane_id, LaneId(lane))


def test_narrow_nonconvex_cubic_checks_every_stationary_basin() raises:
    # Exact serialized coefficients and Float32 query bits are retained in
    # the independent rational-polynomial oracle. Golden40 chose s=0.0004397
    # instead of the global minimum at 0.000900000002294056, and missed the
    # 0.2 mm lane. Its continuous maximum chord error is below 1 mm.
    var map = load_opendrive(
        '<OpenDRIVE><road id="1" length="0.001001" junction="-1" rule="RHT">'
        '<planView><geometry s="0" x="0" y="0" hdg="0" length="0.001001">'
        '<line/></geometry></planView><lanes><laneOffset s="0" a="0.00039575"'
        ' b="-6.7925" c="18200" d="-13000000"/><laneSection s="0">'
        '<center><lane id="0" type="none"/></center><right><lane id="-1"'
        ' type="driving"><width sOffset="0" a="0.0002" b="0" c="0" d="0"/>'
        "</lane></right></laneSection></lanes></road></OpenDRIVE>"
    )
    var point = Vector3(Float32(0.0009), Float32(0.0005525), 0)
    var nearest = map.certified_closest_waypoint_on_road(point).value()
    assert_equal(nearest.lane_id, LaneId(-1))
    assert_almost_equal(nearest.s, 0.000900000002294056, atol=2e-4)
    assert_true(Bool(map.certified_waypoint(point)))
    assert_true(
        map.roads[0]._lane_distance_squared(0, 0, nearest.s, point) < 1e-20
    )


def test_polynomial_partition_retains_repeated_roots_and_endpoints() raises:
    # (t - 1/2)^5: the stationary root has multiplicity five, so a residual
    # threshold or strict sign change at derivative partition ends can miss it.
    var repeated: List[Float64] = [-0.03125, 0.3125, -1.25, 2.5, -2.5, 1.0]
    var candidates = _polynomial_candidates(repeated)
    var distance = 1.0
    for t in candidates:
        distance = min(distance, abs(t - 0.5))
    assert_almost_equal(distance, 0.0, atol=1e-15)
    assert_equal(candidates[0], 0.0)
    assert_equal(candidates[len(candidates) - 1], 1.0)
    # Ascending, descending and identically zero polynomials.
    for sign in [-1.0, 1.0]:
        var linear = _polynomial_candidates([-0.3 * sign, sign])
        assert_almost_equal(linear[1], 0.3, atol=1e-15)
    var zero = _polynomial_candidates([0.0, 0.0, 0.0])
    assert_equal(len(zero), 2)
    assert_true(_distance_is_convex([0, 1, 0, 0, 0, 0]))
    assert_false(_distance_is_convex([0, -1, 0, 0, 0, 0]))


def test_five_stationary_roots_and_interior_flat_minimum() raises:
    # C=(0.0008t, 0.019(t-.2)(t-.5)(t-.8)), query=(0.0004,0).
    # Differentiated distance has five roots: 0.2214685, 0.2940383,
    # 0.5, 0.7059617, 0.7785315. The middle root is the global minimum.
    var five = _polynomial_candidates(
        [
            -0.0000193808,
            0.0002445316,
            -0.00115881,
            0.00257754,
            -0.0027075,
            0.001083,
        ]
    )
    for expected in [
        0.221468515652635,
        0.294038323401528,
        0.5,
        0.705961676598472,
        0.778531484347365,
    ]:
        var difference = 1.0
        for t in five:
            difference = min(difference, abs(t - expected))
        assert_true(difference < 1e-10)
    var map = _map(
        'a="0.00162" b="-15.675" c="44531.25" d="-37109375"',
        width='a="0.0002" b="0" c="0" d="0"',
        length=0.000801,
    )
    _query(map, -1, 0.0004, 0.0004, 0)
    # C=(u,0.5u^2), P=(0,1), u=t-0.5 gives D=1+0.25u^4.
    # Its stationary root is repeated and lies inside the search interval.
    var flat = _polynomial_candidates([-0.125, 0.75, -1.5, 1.0])
    var closest = 1.0
    for t in flat:
        closest = min(closest, abs(t - 0.5))
    assert_almost_equal(closest, 0.0, atol=1e-15)


def test_cubic_certification_requires_one_unclamped_record_interval() raises:
    var map = _map()
    var point = Vector3(25, 1.75, 0)
    ref road = map.roads[0]
    assert_equal(len(road._lane_distance_derivative(0, 0, 1, 1, point)), 0)
    assert_equal(len(road._lane_distance_derivative(0, 0, -2, -1, point)), 0)
    assert_equal(len(road._lane_distance_derivative(0, 0, 0, 101, point)), 0)
    var shifted = road.info.geometries[0].copy()
    shifted.s = 50
    road.info.geometries.append(shifted^)
    assert_equal(len(road._lane_distance_derivative(0, 0, 0, 75, point)), 0)
    _ = road.info.geometries.pop()
    road.info.elevations.append(
        RoadInfoElevation(50, CubicPolynomial.constant(0))
    )
    assert_equal(len(road._lane_distance_derivative(0, 0, 0, 75, point)), 0)
    _ = road.info.elevations.pop()
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(50, CubicPolynomial.constant(0))
    )
    assert_equal(len(road._lane_distance_derivative(0, 0, 0, 75, point)), 0)
    _ = road.info.lane_offsets.pop()
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(50, CubicPolynomial.constant(3.5))
    )
    assert_equal(len(road._lane_distance_derivative(0, 0, 0, 75, point)), 0)
    var overflow = road.copy()
    overflow.info.lane_offsets[0].polynomial.d = 1e308
    assert_equal(len(overflow._lane_distance_derivative(0, 0, 0, 25, point)), 0)
    var center = road.sections[0].lane_index(LaneId(0))
    assert_equal(
        len(road._lane_distance_derivative(0, center, 0, 75, point)), 6
    )


def test_nonconvex_elevation_and_rotated_left_and_right_centers() raises:
    for rht in [True, False]:
        for id in [-1, 1]:
            var side = "right" if id < 0 else "left"
            var parsed = load_opendrive(
                String(
                    (
                        '<OpenDRIVE><road id="1" length="0.001001"'
                        ' junction="-1" rule="'
                    ),
                    "RHT" if rht else "LHT",
                    (
                        '"><planView><geometry s="0" x="0" y="0" hdg="0"'
                        ' length="0.001001"><line/></geometry></planView><elevationProfile><elevation'
                        ' s="0" a="-0.00029575" b="6.7925" c="-18200"'
                        ' d="13000000"/></elevationProfile><lanes><laneOffset'
                        ' s="0" a="'
                    ),
                    -Float64(id) * 0.0001,
                    (
                        '" b="0" c="0" d="0"/><laneSection s="0"><center><lane'
                        ' id="0" type="none"/></center><'
                    ),
                    side,
                    '><lane id="',
                    id,
                    (
                        '" type="driving"><width sOffset="0" a="0.0002" b="0"'
                        ' c="0" d="0"/></lane></'
                    ),
                    side,
                    "></laneSection></lanes></road></OpenDRIVE>",
                )
            )
            var roads = parsed.roads.copy()
            roads[0].info.geometries[0].geometry.heading = 0.7
            var map = Map(
                roads^, List[Junction](), List[Signal](), List[Controller]()
            )
            var point = Vector3(
                Float32(0.0009 * cos(0.7)),
                Float32(-0.0009 * sin(0.7)),
                Float32(0.0005525),
            )
            var nearest = map.certified_closest_waypoint_on_road(point).value()
            assert_equal(nearest.lane_id, LaneId(id))
            assert_almost_equal(nearest.s, 0.0009, atol=2e-4)
            assert_true(Bool(map.certified_waypoint(point)))
            assert_true(
                map.compute_transform(nearest).location.distance_to(point)
                < 1e-9
            )


def test_line_polynomial_translation_and_far_query_scale() raises:
    var parsed = _map('a="0" b="0" c="0.000001" d="0"', length=1.0)
    var roads = parsed.roads.copy()
    var base = 1000000000.0
    roads[0].length = base + 1.0
    roads[0].sections[0].s = base
    roads[0].info.geometries[0].s = base
    roads[0].info.geometries[0].geometry.s = base
    # Keep the target lane center affine, while the other lane's quadratic
    # width ensures that the section-wide affine shortcut cannot mask this.
    roads[0].info.lane_offsets[0].polynomial = CubicPolynomial.constant(0.0)
    roads[0].sections[0].lanes[2].info.widths[0].polynomial.c = 0.000001
    for i in range(len(roads[0].sections[0].lanes)):
        roads[0].sections[0].lanes[i].distance = base
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var point = Vector3(0.6, 1.75, 0)
    var nearest = map.certified_closest_waypoint_on_road(point).value()
    assert_true(abs(nearest.s - (base + Float64(point.x))) <= 0.00000012)
    var derivative = map.roads[0]._lane_distance_derivative(
        0, 0, base, base + 1.0, Vector3(1e20, 1e20, 1e20)
    )
    assert_equal(len(derivative), 6)
    assert_true(derivative[0] < 0.0)
    var candidates = _polynomial_candidates(derivative)
    assert_equal(candidates[0], 0.0)
    assert_equal(candidates[len(candidates) - 1], 1.0)
    # A far query on a cubic interval keeps a finite normalized polynomial.
    var curved = _map('a="0" b="0" c="0.01" d="0.001"')
    var far = curved.roads[0]._lane_distance_derivative(
        0, 0, 0, 1, Vector3(1e20, 1e20, 1e20)
    )
    assert_equal(len(far), 6)
    assert_true(far[0] < 0.0)
    assert_true(len(_polynomial_candidates(far)) >= 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
