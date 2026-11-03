# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the plan of a castle: the geometry of points and polygons, each
part, and the checks that refuse what cannot stand.

The geometry is worked by hand. A mitered band along (0, 0), (10, 0), (10, 10)
of width 2 has the left corners (0, 1), (9, 1) and (9, 10), and the right
corners (0, -1), (11, -1) and (11, 10). A block of 4 by 2 at heading 90
degrees is 2 wide and 4 high.
"""

from extensions.castle.kinds import (
    CONE,
    ESTIMATED,
    FLAT,
    GABLE,
    MEASURED,
    Provenance,
    RoofKind,
    SURVEYED,
)
from extensions.castle.plan import (
    Bridge,
    CastlePlan,
    Gate,
    Moat,
    Point,
    QuayWall,
    Tower,
    Wing,
    check_polygon,
    convex_hull,
    distance_to_outline,
    offset_outline,
    point,
    points,
    polygon_area,
    polygon_contains,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle64, DEGREE64, Length64


def square(side: Float64) raises -> List[Point]:
    return points([0.0, 0.0, side, 0.0, side, side, 0.0, side])


def tower() -> Tower:
    return Tower(
        "Tower",
        point(0, 0),
        Length64(2.0),
        Length64(0.0),
        Length64(10.0),
        CONE,
        Length64(4.0),
        MEASURED,
    )


def wing() raises -> Wing:
    return Wing(
        "Wing",
        points([0.0, 0.0, 10.0, 0.0]),
        Length64(4.0),
        Length64(0.0),
        Length64(5.0),
        Length64(8.0),
        MEASURED,
    )


def gate() -> Gate:
    return Gate(
        "Gate",
        point(0, 0),
        Length64(4.0),
        Length64(2.0),
        Angle64(0.0),
        Length64(0.0),
        Length64(9.0),
        Length64(1.0),
        MEASURED,
    )


def quay() raises -> QuayWall:
    return QuayWall(
        "Quay",
        points([0.0, 0.0, 5.0, 0.0]),
        Length64(1.0),
        Length64(-1.5),
        Length64(4.0),
        ESTIMATED,
    )


def moat() raises -> Moat:
    return Moat(
        "Moat",
        points([-20.0, -20.0, 20.0, -20.0, 20.0, 20.0, -20.0, 20.0]),
        Length64(0.0),
        Length64(1.5),
        SURVEYED,
    )


def bridge() -> Bridge:
    return Bridge(
        "Bridge",
        point(5, 0),
        Angle64(0.0),
        3,
        Length64(7.0),
        Length64(9.0),
        Length64(2.0),
        Length64(3.2),
        Length64(0.6),
        ESTIMATED,
    )


def small_plan() raises -> CastlePlan:
    # A wing from 0 to 10 and 4 wide, and the surveyed building the same.
    # The tower and the gate are far from it.
    var far_tower = tower()
    far_tower.center = point(100, 100)
    var far_gate = gate()
    far_gate.center = point(100, 100)
    var towers = List[Tower]()
    towers.append(far_tower^)
    var wings = List[Wing]()
    wings.append(wing())
    return CastlePlan(
        "Plan",
        Length64(3.5),
        Length64(2.0),
        points([0.0, -2.0, 10.0, -2.0, 10.0, 2.0, 0.0, 2.0]),
        towers^,
        wings^,
        far_gate^,
        quay(),
        moat(),
        bridge(),
    )


def test_points_come_from_pairs_of_meters() raises:
    var pair = points([1.0, 2.0, 3.0, 4.0])
    assert_equal(len(pair), 2)
    assert_equal(pair[1].x.value, 3.0)
    assert_equal(pair[1].y.value, 4.0)
    assert_equal(len(points(List[Float64]())), 0)
    with assert_raises(contains="east and a north"):
        _ = points([1.0, 2.0, 3.0])
    with assert_raises(contains="finite"):
        _ = points([nan[DType.float64](), 2.0])
    with assert_raises(contains="finite"):
        _ = points([1.0, inf[DType.float64]()])


def test_the_area_of_a_polygon_ignores_the_winding() raises:
    assert_almost_equal(polygon_area(square(2.0)).value, 4.0, atol=1e-12)
    var reversed = points([0.0, 2.0, 2.0, 2.0, 2.0, 0.0, 0.0, 0.0])
    assert_almost_equal(polygon_area(reversed).value, 4.0, atol=1e-12)
    with assert_raises(contains="three points"):
        _ = polygon_area(points([0.0, 0.0, 1.0, 1.0]))


def test_a_polygon_holds_the_points_inside_it() raises:
    var l_shape = points(
        [0.0, 0.0, 4.0, 0.0, 4.0, 2.0, 2.0, 2.0, 2.0, 4.0, 0.0, 4.0]
    )
    assert_true(polygon_contains(l_shape, point(1, 1)))
    assert_true(polygon_contains(l_shape, point(3, 1)))
    assert_true(polygon_contains(l_shape, point(1, 3)))
    assert_false(polygon_contains(l_shape, point(3, 3)))
    assert_false(polygon_contains(l_shape, point(-1, 1)))
    assert_false(polygon_contains(l_shape, point(5, 1)))
    assert_false(polygon_contains(l_shape, point(1, 5)))
    assert_false(
        polygon_contains(points([0.0, 0.0, 1.0, 1.0]), point(0.5, 0.5))
    )


def test_a_polygon_must_have_an_area() raises:
    check_polygon(square(1.0))
    with assert_raises(contains="three points"):
        check_polygon(points([0.0, 0.0, 1.0, 1.0]))
    var outline = square(1.0)
    outline[1].x = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        check_polygon(outline)
    outline = square(1.0)
    outline[2].y = Length64(inf[DType.float64]())
    with assert_raises(contains="finite"):
        check_polygon(outline)
    with assert_raises(contains="area"):
        check_polygon(points([0.0, 0.0, 1.0, 0.0, 2.0, 0.0]))


def test_the_hull_wraps_the_outermost_points() raises:
    # A square, with a point inside it and a point on an edge.
    var cloud = points(
        [2.0, 2.0, 0.0, 0.0, 1.0, 1.0, 2.0, 0.0, 1.0, 0.0, 0.0, 2.0]
    )
    var hull = convex_hull(cloud)
    assert_equal(len(hull), 4)
    assert_almost_equal(polygon_area(hull).value, 4.0, atol=1e-12)
    # It runs counterclockwise from the lowest point to the west.
    assert_equal(hull[0].x.value, 0.0)
    assert_equal(hull[0].y.value, 0.0)
    assert_equal(hull[1].x.value, 2.0)
    assert_equal(hull[1].y.value, 0.0)
    assert_equal(hull[2].x.value, 2.0)
    assert_equal(hull[2].y.value, 2.0)
    assert_equal(hull[3].x.value, 0.0)
    assert_equal(hull[3].y.value, 2.0)
    # The hull of a C is the oval that holds it.
    var c_shape = points(
        [
            0.0,
            0.0,
            4.0,
            0.0,
            4.0,
            1.0,
            1.0,
            1.0,
            1.0,
            3.0,
            4.0,
            3.0,
            4.0,
            4.0,
            0.0,
            4.0,
        ]
    )
    assert_almost_equal(
        polygon_area(convex_hull(c_shape)).value, 16.0, atol=1e-12
    )
    with assert_raises(contains="three points"):
        _ = convex_hull(points([0.0, 0.0, 1.0, 1.0]))
    with assert_raises(contains="on one line"):
        _ = convex_hull(points([0.0, 0.0, 1.0, 1.0, 2.0, 2.0]))


def test_the_distance_to_a_polygon_is_to_its_nearest_edge() raises:
    var unit = square(1.0)
    assert_almost_equal(
        distance_to_outline(unit, point(0.5, 0.5)).value, 0.5, atol=1e-12
    )
    assert_almost_equal(
        distance_to_outline(unit, point(3.0, 0.5)).value, 2.0, atol=1e-12
    )
    assert_almost_equal(
        distance_to_outline(unit, point(2.0, 2.0)).value,
        1.4142135623730951,
        atol=1e-12,
    )
    assert_almost_equal(
        distance_to_outline(unit, point(1.0, 0.5)).value, 0.0, atol=1e-12
    )
    # An edge of no length does not divide by zero.
    var doubled = points([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0])
    assert_almost_equal(
        distance_to_outline(doubled, point(-1.0, 0.0)).value, 1.0, atol=1e-12
    )
    with assert_raises(contains="three points"):
        _ = distance_to_outline(points([0.0, 0.0, 1.0, 1.0]), point(0, 0))


def test_a_band_along_a_straight_axis_is_a_rectangle() raises:
    var outline = offset_outline(points([0.0, 0.0, 10.0, 0.0]), Length64(4.0))
    assert_equal(len(outline), 4)
    assert_almost_equal(outline[0].x.value, 0.0, atol=1e-12)
    assert_almost_equal(outline[0].y.value, 2.0, atol=1e-12)
    assert_almost_equal(outline[1].x.value, 10.0, atol=1e-12)
    assert_almost_equal(outline[1].y.value, 2.0, atol=1e-12)
    assert_almost_equal(outline[2].y.value, -2.0, atol=1e-12)
    assert_almost_equal(outline[3].x.value, 0.0, atol=1e-12)
    assert_almost_equal(polygon_area(outline).value, 40.0, atol=1e-9)


def test_a_band_miters_its_corners() raises:
    var outline = offset_outline(
        points([0.0, 0.0, 10.0, 0.0, 10.0, 10.0]), Length64(2.0)
    )
    assert_equal(len(outline), 6)
    var left = [0.0, 1.0, 9.0, 1.0, 9.0, 10.0]
    var right = [11.0, 10.0, 11.0, -1.0, 0.0, -1.0]
    for at in range(3):
        assert_almost_equal(outline[at].x.value, left[2 * at], atol=1e-12)
        assert_almost_equal(outline[at].y.value, left[2 * at + 1], atol=1e-12)
        assert_almost_equal(outline[3 + at].x.value, right[2 * at], atol=1e-12)
        assert_almost_equal(
            outline[3 + at].y.value, right[2 * at + 1], atol=1e-12
        )
    # A mitered band has the area of its axis times its width.
    assert_almost_equal(polygon_area(outline).value, 40.0, atol=1e-9)


def test_a_band_that_cannot_be_laid_out_is_refused() raises:
    with assert_raises(contains="two points"):
        _ = offset_outline(points([0.0, 0.0]), Length64(1.0))
    with assert_raises(contains="width"):
        _ = offset_outline(points([0.0, 0.0, 1.0, 0.0]), Length64(0.0))
    with assert_raises(contains="width"):
        _ = offset_outline(
            points([0.0, 0.0, 1.0, 0.0]), Length64(nan[DType.float64]())
        )
    var axis = points([0.0, 0.0, 1.0, 0.0])
    axis[0].x = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        _ = offset_outline(axis, Length64(1.0))
    axis = points([0.0, 0.0, 1.0, 0.0])
    axis[0].y = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        _ = offset_outline(axis, Length64(1.0))
    axis = points([0.0, 0.0, 1.0, 0.0])
    axis[1].x = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        _ = offset_outline(axis, Length64(1.0))
    axis = points([0.0, 0.0, 1.0, 0.0])
    axis[1].y = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        _ = offset_outline(axis, Length64(1.0))
    with assert_raises(contains="length"):
        _ = offset_outline(points([0.0, 0.0, 0.0, 0.0]), Length64(1.0))
    with assert_raises(contains="too sharp"):
        _ = offset_outline(
            points([0.0, 0.0, 10.0, 0.0, 0.0, 0.1]), Length64(1.0)
        )


def test_a_tower_stands_or_is_refused() raises:
    var round = tower()
    round.check()
    assert_equal(round.top().value, 14.0)
    assert_true(round.contains(point(1.9, 0)))
    assert_true(round.contains(point(2.0, 0)))
    assert_false(round.contains(point(2.1, 0)))
    var flat = tower()
    flat.roof = FLAT
    flat.roof_height = Length64(0.0)
    flat.check()
    var bad = tower()
    bad.center = point(nan[DType.float64](), 0)
    with assert_raises(contains="center"):
        bad.check()
    bad = tower()
    bad.center = point(0, inf[DType.float64]())
    with assert_raises(contains="center"):
        bad.check()
    bad = tower()
    bad.radius = Length64(0.0)
    with assert_raises(contains="radius"):
        bad.check()
    bad.radius = Length64(nan[DType.float64]())
    with assert_raises(contains="radius"):
        bad.check()
    bad = tower()
    bad.base = Length64(nan[DType.float64]())
    with assert_raises(contains="base"):
        bad.check()
    bad = tower()
    bad.wall_height = Length64(0.0)
    with assert_raises(contains="wall"):
        bad.check()
    bad.wall_height = Length64(nan[DType.float64]())
    with assert_raises(contains="wall"):
        bad.check()
    bad = tower()
    bad.roof = GABLE
    with assert_raises(contains="cone or a flat"):
        bad.check()
    bad = tower()
    bad.roof_height = Length64(-1.0)
    with assert_raises(contains="roof height"):
        bad.check()
    bad.roof_height = Length64(nan[DType.float64]())
    with assert_raises(contains="roof height"):
        bad.check()
    bad = tower()
    bad.roof_height = Length64(0.0)
    with assert_raises(contains="cone roof"):
        bad.check()
    bad = tower()
    bad.provenance = Provenance(7)
    with assert_raises(contains="provenance"):
        bad.check()
    bad = tower()
    bad.roof = RoofKind(9)
    with assert_raises(contains="cone or a flat"):
        bad.check()


def test_a_wing_stands_or_is_refused() raises:
    var gable = wing()
    gable.check()
    assert_almost_equal(gable.roof_rise().value, 3.0, atol=1e-12)
    assert_equal(len(gable.outline()), 4)
    var bad = wing()
    bad.axis = points([0.0, 0.0])
    with assert_raises(contains="two points"):
        bad.check()
    with assert_raises(contains="two points"):
        _ = bad.outline()
    bad = wing()
    bad.base = Length64(nan[DType.float64]())
    with assert_raises(contains="base"):
        bad.check()
    bad = wing()
    bad.eave_height = Length64(0.0)
    with assert_raises(contains="eaves"):
        bad.check()
    bad.eave_height = Length64(nan[DType.float64]())
    with assert_raises(contains="eaves"):
        bad.check()
    bad = wing()
    bad.ridge_height = Length64(5.0)
    with assert_raises(contains="ridge"):
        bad.check()
    bad.ridge_height = Length64(nan[DType.float64]())
    with assert_raises(contains="ridge"):
        bad.check()
    bad = wing()
    bad.provenance = Provenance(-1)
    with assert_raises(contains="provenance"):
        bad.check()


def test_a_gate_is_a_rectangle_at_its_heading() raises:
    var block = gate()
    block.check()
    var corners = block.outline()
    var expected = [-2.0, -1.0, 2.0, -1.0, 2.0, 1.0, -2.0, 1.0]
    for at in range(4):
        assert_almost_equal(corners[at].x.value, expected[2 * at], atol=1e-12)
        assert_almost_equal(
            corners[at].y.value, expected[2 * at + 1], atol=1e-12
        )
    block.heading = Angle64(90.0, DEGREE64)
    corners = block.outline()
    assert_almost_equal(corners[0].x.value, 1.0, atol=1e-9)
    assert_almost_equal(corners[0].y.value, -2.0, atol=1e-9)
    assert_almost_equal(polygon_area(corners).value, 8.0, atol=1e-9)
    var bad = gate()
    bad.center = point(nan[DType.float64](), 0)
    with assert_raises(contains="center"):
        bad.check()
    bad = gate()
    bad.center = point(0, nan[DType.float64]())
    with assert_raises(contains="center"):
        bad.check()
    bad = gate()
    bad.length = Length64(0.0)
    with assert_raises(contains="length"):
        bad.check()
    bad.length = Length64(nan[DType.float64]())
    with assert_raises(contains="length"):
        bad.check()
    bad = gate()
    bad.width = Length64(-1.0)
    with assert_raises(contains="width"):
        bad.check()
    bad.width = Length64(nan[DType.float64]())
    with assert_raises(contains="width"):
        bad.check()
    bad = gate()
    bad.heading = Angle64(nan[DType.float64]())
    with assert_raises(contains="heading"):
        bad.check()
    bad = gate()
    bad.base = Length64(inf[DType.float64]())
    with assert_raises(contains="base"):
        bad.check()
    bad = gate()
    bad.height = Length64(0.0)
    with assert_raises(contains="height"):
        bad.check()
    bad.height = Length64(nan[DType.float64]())
    with assert_raises(contains="height"):
        bad.check()
    bad = gate()
    bad.parapet = Length64(-0.1)
    with assert_raises(contains="parapet"):
        bad.check()
    bad.parapet = Length64(nan[DType.float64]())
    with assert_raises(contains="parapet"):
        bad.check()
    bad = gate()
    bad.provenance = Provenance(4)
    with assert_raises(contains="provenance"):
        bad.check()


def test_a_quay_wall_stands_or_is_refused() raises:
    var wall = quay()
    wall.check()
    assert_almost_equal(wall.height().value, 5.5, atol=1e-12)
    var bad = quay()
    bad.axis = points([0.0, 0.0])
    with assert_raises(contains="two points"):
        bad.check()
    bad = quay()
    bad.foot = Length64(nan[DType.float64]())
    with assert_raises(contains="foot and top"):
        bad.check()
    bad = quay()
    bad.top = Length64(inf[DType.float64]())
    with assert_raises(contains="foot and top"):
        bad.check()
    bad = quay()
    bad.top = Length64(-2.0)
    with assert_raises(contains="above its foot"):
        bad.check()
    bad = quay()
    bad.provenance = Provenance(4)
    with assert_raises(contains="provenance"):
        bad.check()


def test_a_moat_holds_water_or_is_refused() raises:
    var water = moat()
    water.check()
    assert_almost_equal(water.area().value, 1600.0, atol=1e-9)
    assert_almost_equal(water.bed().value, -1.5, atol=1e-12)
    var bad = moat()
    bad.outline = points([0.0, 0.0, 1.0, 1.0])
    with assert_raises(contains="three points"):
        bad.check()
    with assert_raises(contains="three points"):
        _ = bad.area()
    bad = moat()
    bad.water_level = Length64(nan[DType.float64]())
    with assert_raises(contains="water level"):
        bad.check()
    bad = moat()
    bad.depth = Length64(0.0)
    with assert_raises(contains="depth"):
        bad.check()
    bad.depth = Length64(nan[DType.float64]())
    with assert_raises(contains="depth"):
        bad.check()
    bad = moat()
    bad.provenance = Provenance(4)
    with assert_raises(contains="provenance"):
        bad.check()


def test_a_bridge_spans_or_is_refused() raises:
    var arches = bridge()
    arches.check()
    assert_almost_equal(arches.clear_span().value, 5.0, atol=1e-12)
    assert_almost_equal(arches.length().value, 21.0, atol=1e-12)
    assert_almost_equal(arches.rise().value, 2.5, atol=1e-12)
    var bad = bridge()
    bad.start = point(nan[DType.float64](), 0)
    with assert_raises(contains="start"):
        bad.check()
    bad = bridge()
    bad.start = point(0, nan[DType.float64]())
    with assert_raises(contains="start"):
        bad.check()
    bad = bridge()
    bad.heading = Angle64(nan[DType.float64]())
    with assert_raises(contains="heading"):
        bad.check()
    bad = bridge()
    bad.spans = 0
    with assert_raises(contains="span"):
        bad.check()
    bad = bridge()
    bad.pitch = Length64(0.0)
    with assert_raises(contains="pitch"):
        bad.check()
    bad.pitch = Length64(nan[DType.float64]())
    with assert_raises(contains="pitch"):
        bad.check()
    bad = bridge()
    bad.width = Length64(0.0)
    with assert_raises(contains="width"):
        bad.check()
    bad.width = Length64(nan[DType.float64]())
    with assert_raises(contains="width"):
        bad.check()
    bad = bridge()
    bad.pier = Length64(0.0)
    with assert_raises(contains="pier must be positive"):
        bad.check()
    bad.pier = Length64(nan[DType.float64]())
    with assert_raises(contains="pier must be positive"):
        bad.check()
    bad = bridge()
    bad.pier = Length64(7.0)
    with assert_raises(contains="thinner than its pitch"):
        bad.check()
    bad = bridge()
    bad.deck = Length64(nan[DType.float64]())
    with assert_raises(contains="deck"):
        bad.check()
    bad = bridge()
    bad.ring = Length64(0.0)
    with assert_raises(contains="ring must be positive"):
        bad.check()
    bad.ring = Length64(nan[DType.float64]())
    with assert_raises(contains="ring must be positive"):
        bad.check()
    bad = bridge()
    bad.ring = Length64(2.5)
    with assert_raises(contains="half its span"):
        bad.check()
    bad = bridge()
    bad.provenance = Provenance(4)
    with assert_raises(contains="provenance"):
        bad.check()


def test_a_plan_of_matching_parts_is_consistent() raises:
    var plan = small_plan()
    plan.check()
    assert_almost_equal(plan.footprint_area().value, 40.0, atol=1e-9)


def test_a_plan_that_is_not_consistent_is_refused() raises:
    var bad = small_plan()
    bad.island_level = Length64(nan[DType.float64]())
    with assert_raises(contains="levels"):
        bad.check()
    bad = small_plan()
    bad.ground_level = Length64(inf[DType.float64]())
    with assert_raises(contains="levels"):
        bad.check()
    bad = small_plan()
    bad.surveyed_footprint = points([0.0, 0.0, 1.0, 1.0])
    with assert_raises(contains="three points"):
        bad.check()
    bad = small_plan()
    bad.towers = List[Tower]()
    with assert_raises(contains="needs a tower"):
        bad.check()
    bad = small_plan()
    bad.wings = List[Wing]()
    with assert_raises(contains="needs a wing"):
        bad.check()
    bad = small_plan()
    bad.towers[0].radius = Length64(0.0)
    with assert_raises(contains="radius"):
        bad.check()
    bad = small_plan()
    bad.wings[0].width = Length64(0.0)
    with assert_raises(contains="width"):
        bad.check()
    bad = small_plan()
    bad.gate.length = Length64(0.0)
    with assert_raises(contains="gate"):
        bad.check()
    bad = small_plan()
    bad.quay.thickness = Length64(0.0)
    with assert_raises(contains="width"):
        bad.check()
    bad = small_plan()
    bad.moat.depth = Length64(0.0)
    with assert_raises(contains="depth"):
        bad.check()
    bad = small_plan()
    bad.bridge.spans = 0
    with assert_raises(contains="span"):
        bad.check()
    bad = small_plan()
    bad.island_level = Length64(-1.0)
    with assert_raises(contains="island"):
        bad.check()
    bad = small_plan()
    bad.bridge.deck = Length64(-1.0)
    with assert_raises(contains="deck"):
        bad.check()


def test_the_overlap_is_one_for_a_match_and_less_for_a_miss() raises:
    var plan = small_plan()
    assert_almost_equal(plan.footprint_overlap(Length64(0.1)), 1.0, atol=1e-12)
    # A surveyed building twice as long as the wing: half of it is built.
    plan.surveyed_footprint = points(
        [0.0, -2.0, 20.0, -2.0, 20.0, 2.0, 0.0, 2.0]
    )
    assert_almost_equal(plan.footprint_overlap(Length64(0.1)), 0.5, atol=1e-6)
    # A tower of radius 1 in a surveyed square of side 2: pi over 4 is built.
    var round = small_plan()
    round.towers[0].center = point(5, 50)
    round.towers[0].radius = Length64(1.0)
    round.surveyed_footprint = points(
        [4.0, 49.0, 6.0, 49.0, 6.0, 51.0, 4.0, 51.0]
    )
    assert_almost_equal(
        round.footprint_overlap(Length64(0.02)), 0.7853981634, atol=2e-3
    )
    # A gate on the surveyed outline.
    var block = small_plan()
    block.gate.center = point(5, 0)
    block.gate.length = Length64(10.0)
    block.gate.width = Length64(4.0)
    assert_almost_equal(block.footprint_overlap(Length64(0.1)), 1.0, atol=1e-12)


def test_the_overlap_refuses_what_it_cannot_measure() raises:
    var plan = small_plan()
    with assert_raises(contains="step"):
        _ = plan.footprint_overlap(Length64(0.0))
    with assert_raises(contains="step"):
        _ = plan.footprint_overlap(Length64(nan[DType.float64]()))
    var bad_wing = small_plan()
    bad_wing.wings[0].axis = points([0.0, 0.0])
    with assert_raises(contains="two points"):
        _ = bad_wing.footprint_overlap(Length64(0.5))
    # A surveyed outline smaller than the step, with nothing built near it.
    var tiny = small_plan()
    tiny.surveyed_footprint = points(
        [50.0, 50.0, 50.001, 50.0, 50.001, 50.001, 50.0, 50.001]
    )
    tiny.wings[0].axis = points([0.0, 0.0, 10.0, 0.0])
    with assert_raises(contains="Nothing is built"):
        _ = tiny.footprint_overlap(Length64(1.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
