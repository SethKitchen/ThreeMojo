# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.plan`.

The references are the formulas of plane geometry: the area of a circle and
of an ellipse, the volume of a hollow cylinder, the corners of a turned
rectangle, and the radius of a circle through three points of an arch.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.castle.kinds import (
    CONE,
    GABLE,
    PARAPET,
    ROUND,
    RoofForm,
    SQUARE,
    TowerShape,
)
from extensions.castle.plan import (
    Block,
    Bridge,
    CastlePlan,
    Moat,
    PlanPoint,
    Tower,
    wijnendale,
)
from std.math import cos, nan, pi, sin
from units.si import DEGREE, METER, Angle64, Length64


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _at(x: Float64, y: Float64) -> PlanPoint:
    return PlanPoint(_m(x), _m(y))


def _round_tower() -> Tower:
    return Tower(
        "tower", ROUND, _at(0, 0), _m(3.0), _m(1.0), _m(10.0), CONE, _m(5.0)
    )


def _block() -> Block:
    return Block(
        "range",
        _at(0, 0),
        _m(20.0),
        _m(8.0),
        Angle64(0.0),
        _m(1.0),
        _m(9.0),
        GABLE,
        _m(4.0),
    )


def _moat() -> Moat:
    return Moat(
        _at(0, 0), _m(20), _m(10), _at(0, 0), _m(12), _m(5), _m(1.5), _m(2.0)
    )


def _bridge() -> Bridge:
    return Bridge(
        _at(0, 0),
        Angle64(0.0),
        3,
        _m(5.0),
        _m(1.4),
        _m(1.4),
        _m(0.4),
        _m(4.2),
        _m(0.5),
        _m(0.1),
        _m(0.9),
    )


def test_wijnendale_plan_is_sound() raises:
    var plan = wijnendale()
    plan.check()
    assert_equal(plan.name, "Wijnendale Castle")
    assert_equal(len(plan.towers), 10)
    assert_equal(len(plan.blocks), 3)
    # 51 deg 4' 44" N and 3 deg 3' 34" E, as the castle's article gives them.
    assert_almost_equal(plan.latitude.value / pi * 180.0, 51.078889, atol=1e-5)
    assert_almost_equal(plan.longitude.value / pi * 180.0, 3.059444, atol=1e-5)
    assert_equal(plan.towers[0].name, "keep")
    assert_equal(plan.blocks[2].name, "gatehouse")
    # The plan takes the gatehouse as square.
    assert_almost_equal(plan.blocks[2].length.value, plan.blocks[2].width.value)


def test_tallest_part_is_the_keep() raises:
    var plan = wijnendale()
    assert_almost_equal(plan.tallest().value, 28.0)
    # A taller block takes over.
    plan.blocks[0].height = _m(30.0)
    assert_almost_equal(plan.tallest().value, 37.0)


def test_a_plan_without_parts_has_no_height_or_area() raises:
    var plan = wijnendale()
    plan.towers = List[Tower]()
    plan.blocks = List[Block]()
    assert_almost_equal(plan.tallest().value, 0.0)
    assert_almost_equal(plan.masonry_footprint().value, 0.0)
    # Without blocks only the towers count.
    var towers_only = wijnendale()
    towers_only.blocks = List[Block]()
    towers_only.check()
    assert_almost_equal(towers_only.tallest().value, 28.0)
    assert_true(towers_only.masonry_footprint().value > 0.0)
    # Without towers only the blocks count.
    var blocks_only = wijnendale()
    blocks_only.towers = List[Tower]()
    assert_almost_equal(blocks_only.tallest().value, 19.0)


def test_masonry_footprint_sums_the_parts() raises:
    var plan = wijnendale()
    var expected = 0.0
    for i in range(len(plan.towers)):
        expected += plan.towers[i].footprint().value
    for i in range(len(plan.blocks)):
        expected += plan.blocks[i].footprint().value
    assert_almost_equal(plan.masonry_footprint().value, expected)


def test_round_tower_quantities() raises:
    var t = _round_tower()
    t.check()
    assert_almost_equal(t.apex().value, 15.0)
    assert_almost_equal(t.footprint().value, pi * 9.0)
    assert_almost_equal(t.core_radius().value, 2.0)
    # A hollow cylinder: pi (R^2 - r^2) h.
    assert_almost_equal(t.shaft_volume().value, pi * (9.0 - 4.0) * 10.0)


def test_parapet_tower_apex_is_the_shaft_height() raises:
    var t = _round_tower()
    t.roof = PARAPET
    t.roof_rise = _m(0.0)
    t.check()
    assert_almost_equal(t.apex().value, 10.0)


def test_square_tower_quantities() raises:
    var t = _round_tower()
    t.shape = SQUARE
    t.radius = _m(2.0)
    t.wall = _m(0.5)
    t.check()
    assert_almost_equal(t.footprint().value, 16.0)
    # Outer side 4 and inner side 3: (16 - 9) x 10.
    assert_almost_equal(t.shaft_volume().value, 70.0)


def test_tower_refuses_what_cannot_stand() raises:
    var t = _round_tower()
    t.shape = TowerShape(3)
    with assert_raises(contains="A tower shape is not valid"):
        t.check()
    t = _round_tower()
    t.roof = RoofForm(7)
    with assert_raises(contains="A roof form is not valid"):
        t.check()
    t = _round_tower()
    t.center = PlanPoint(_m(nan[DType.float64]()), _m(0))
    with assert_raises(contains="A tower must have a position"):
        t.check()
    t = _round_tower()
    t.center = PlanPoint(_m(0), _m(nan[DType.float64]()))
    with assert_raises(contains="A tower must have a position"):
        t.check()
    t = _round_tower()
    t.radius = _m(0.0)
    with assert_raises(contains="A tower radius must be positive"):
        t.check()
    t = _round_tower()
    t.wall = _m(-1.0)
    with assert_raises(contains="A tower wall must be positive"):
        t.check()
    t = _round_tower()
    t.height = _m(0.0)
    with assert_raises(contains="A tower height must be positive"):
        t.check()
    t = _round_tower()
    t.roof = GABLE
    with assert_raises(contains="a cone or a parapet, not a gable"):
        t.check()
    t = _round_tower()
    t.roof_rise = _m(0.0)
    with assert_raises(contains="A cone must have a rise"):
        t.check()
    t = _round_tower()
    t.wall = _m(3.0)
    with assert_raises(contains="thinner than its radius"):
        t.check()


def test_block_quantities() raises:
    var b = _block()
    b.check()
    assert_almost_equal(b.apex().value, 13.0)
    assert_almost_equal(b.footprint().value, 160.0)
    var low = b.corner(-1.0, -1.0)
    assert_almost_equal(low.x.value, -10.0)
    assert_almost_equal(low.y.value, -4.0)
    var high = b.corner(1.0, 1.0)
    assert_almost_equal(high.x.value, 10.0)
    assert_almost_equal(high.y.value, 4.0)
    b.roof = PARAPET
    b.roof_rise = _m(0.0)
    b.check()
    assert_almost_equal(b.apex().value, 9.0)


def test_block_corner_turns_with_the_heading() raises:
    var b = _block()
    b.center = _at(5.0, 7.0)
    b.heading = Angle64(90.0, DEGREE)
    # The length now runs north, so the far end is 10 m north of the center.
    var end = b.corner(1.0, 0.0)
    assert_almost_equal(end.x.value, 5.0, atol=1e-6)
    assert_almost_equal(end.y.value, 17.0, atol=1e-6)
    # The width runs west from the heading, to the left of the direction.
    var side = b.corner(0.0, 1.0)
    assert_almost_equal(side.x.value, 1.0, atol=1e-6)
    assert_almost_equal(side.y.value, 7.0, atol=1e-6)


def test_block_refuses_what_cannot_stand() raises:
    var b = _block()
    b.roof = RoofForm(4)
    with assert_raises(contains="A roof form is not valid"):
        b.check()
    b = _block()
    b.center = PlanPoint(_m(nan[DType.float64]()), _m(0))
    with assert_raises(contains="A block must have a position"):
        b.check()
    b = _block()
    b.center = PlanPoint(_m(0), _m(nan[DType.float64]()))
    with assert_raises(contains="A block must have a position"):
        b.check()
    b = _block()
    b.heading = Angle64(nan[DType.float64]())
    with assert_raises(contains="A block must have a heading"):
        b.check()
    b = _block()
    b.length = _m(0.0)
    with assert_raises(contains="A block length must be positive"):
        b.check()
    b = _block()
    b.width = _m(0.0)
    with assert_raises(contains="A block width must be positive"):
        b.check()
    b = _block()
    b.wall = _m(0.0)
    with assert_raises(contains="A block wall must be positive"):
        b.check()
    b = _block()
    b.height = _m(0.0)
    with assert_raises(contains="A block height must be positive"):
        b.check()
    b = _block()
    b.roof = CONE
    with assert_raises(contains="a gable or a parapet, not a cone"):
        b.check()
    b = _block()
    b.roof_rise = _m(0.0)
    with assert_raises(contains="A gable must have a rise"):
        b.check()
    b = _block()
    b.wall = _m(4.0)
    with assert_raises(contains="thinner than half its width"):
        b.check()


def test_moat_quantities() raises:
    var m = _moat()
    m.check()
    assert_true(m.island_inside())
    # An ellipse has area pi a b.
    assert_almost_equal(
        m.water_area().value, pi * (20.0 * 10.0 - 12.0 * 5.0), atol=1e-9
    )
    assert_almost_equal(m.volume().value, m.water_area().value * 1.5)


def test_moat_refuses_what_is_not_a_ring() raises:
    var m = _moat()
    m.center = PlanPoint(_m(nan[DType.float64]()), _m(0))
    with assert_raises(contains="A moat must have a center"):
        m.check()
    m = _moat()
    m.center = PlanPoint(_m(0), _m(nan[DType.float64]()))
    with assert_raises(contains="A moat must have a center"):
        m.check()
    m = _moat()
    m.island_center = PlanPoint(_m(nan[DType.float64]()), _m(0))
    with assert_raises(contains="An island must have a center"):
        m.check()
    m = _moat()
    m.island_center = PlanPoint(_m(0), _m(nan[DType.float64]()))
    with assert_raises(contains="An island must have a center"):
        m.check()
    m = _moat()
    m.semi_x = _m(0.0)
    with assert_raises(contains="A moat semi-axis must be positive"):
        m.check()
    m = _moat()
    m.semi_y = _m(0.0)
    with assert_raises(contains="A moat semi-axis must be positive"):
        m.check()
    m = _moat()
    m.island_semi_x = _m(0.0)
    with assert_raises(contains="An island semi-axis must be positive"):
        m.check()
    m = _moat()
    m.island_semi_y = _m(0.0)
    with assert_raises(contains="An island semi-axis must be positive"):
        m.check()
    m = _moat()
    m.depth = _m(0.0)
    with assert_raises(contains="A moat depth must be positive"):
        m.check()
    m = _moat()
    m.freeboard = _m(0.0)
    with assert_raises(contains="A moat freeboard must be positive"):
        m.check()
    m = _moat()
    m.island_semi_x = _m(25.0)
    assert_false(m.island_inside())
    with assert_raises(contains="The island must lie inside the moat"):
        m.check()


def test_bridge_quantities() raises:
    var b = _bridge()
    b.check()
    # Three spans of 5 m and four piers of 1.4 m.
    assert_almost_equal(b.length().value, 20.6)
    # (s^2/4 + f^2) / (2 f) for s = 5 and f = 1.4.
    assert_almost_equal(b.intrados_radius().value, (6.25 + 1.96) / 2.8)
    assert_almost_equal(b.deck_height().value, 2.4)
    # A circle of that radius through the springings has the stated rise.
    var r = b.intrados_radius().value
    assert_almost_equal(r - (r * r - 6.25) ** 0.5, 1.4, atol=1e-9)


def test_bridge_point_turns_with_the_heading() raises:
    var b = _bridge()
    b.start = _at(10.0, 4.0)
    b.heading = Angle64(90.0, DEGREE)
    var p = b.point(_m(6.0), _m(1.0))
    assert_almost_equal(p.x.value, 9.0, atol=1e-6)
    assert_almost_equal(p.y.value, 10.0, atol=1e-6)


def test_bridge_refuses_what_cannot_stand() raises:
    var b = _bridge()
    b.start = PlanPoint(_m(nan[DType.float64]()), _m(0))
    with assert_raises(contains="A bridge must have a start"):
        b.check()
    b = _bridge()
    b.start = PlanPoint(_m(0), _m(nan[DType.float64]()))
    with assert_raises(contains="A bridge must have a start"):
        b.check()
    b = _bridge()
    b.heading = Angle64(nan[DType.float64]())
    with assert_raises(contains="A bridge must have a heading"):
        b.check()
    b = _bridge()
    b.spans = 0
    with assert_raises(contains="at least one span"):
        b.check()
    b = _bridge()
    b.span = _m(0.0)
    with assert_raises(contains="A bridge span must be positive"):
        b.check()
    b = _bridge()
    b.pier = _m(0.0)
    with assert_raises(contains="A bridge pier must be positive"):
        b.check()
    b = _bridge()
    b.rise = _m(0.0)
    with assert_raises(contains="A bridge rise must be positive"):
        b.check()
    b = _bridge()
    b.ring = _m(0.0)
    with assert_raises(contains="A bridge ring must be positive"):
        b.check()
    b = _bridge()
    b.width = _m(0.0)
    with assert_raises(contains="A bridge width must be positive"):
        b.check()
    b = _bridge()
    b.fill = _m(0.0)
    with assert_raises(contains="A bridge fill must be positive"):
        b.check()
    b = _bridge()
    b.springing = _m(0.0)
    with assert_raises(contains="A bridge springing must be positive"):
        b.check()
    b = _bridge()
    b.parapet = _m(0.0)
    with assert_raises(contains="A bridge parapet must be positive"):
        b.check()
    b = _bridge()
    b.rise = _m(2.6)
    with assert_raises(contains="cannot rise more than half its span"):
        b.check()


def test_plan_refuses_what_cannot_stand() raises:
    var plan = wijnendale()
    plan.latitude = Angle64(100.0, DEGREE)
    with assert_raises(contains="A latitude must be from -90 to 90"):
        plan.check()
    plan = wijnendale()
    plan.longitude = Angle64(200.0, DEGREE)
    with assert_raises(contains="A longitude must be from -180 to 180"):
        plan.check()
    plan = wijnendale()
    plan.towers = List[Tower]()
    with assert_raises(contains="A castle must have a tower"):
        plan.check()
    plan = wijnendale()
    plan.towers[0].center = _at(200.0, 0.0)
    with assert_raises(contains="A tower must stand on the island"):
        plan.check()
    plan = wijnendale()
    plan.towers[1].radius = _m(0.0)
    with assert_raises(contains="A tower radius must be positive"):
        plan.check()
    plan = wijnendale()
    plan.blocks[0].length = _m(0.0)
    with assert_raises(contains="A block length must be positive"):
        plan.check()
    plan = wijnendale()
    plan.moat.depth = _m(0.0)
    with assert_raises(contains="A moat depth must be positive"):
        plan.check()
    plan = wijnendale()
    plan.bridge.spans = 0
    with assert_raises(contains="at least one span"):
        plan.check()


def test_on_island_uses_the_circle() raises:
    var plan = wijnendale()
    assert_true(plan.on_island(_at(4.0, -3.0)))
    assert_false(plan.on_island(_at(4.0, 40.0)))
    # Just inside and just outside the east end of the round island.
    assert_true(plan.on_island(_at(36.9, -3.0)))
    assert_false(plan.on_island(_at(37.1, -3.0)))


def test_the_moat_is_round() raises:
    var moat = wijnendale().moat.copy()
    assert_almost_equal(moat.semi_x.value, moat.semi_y.value)
    assert_almost_equal(moat.island_semi_x.value, moat.island_semi_y.value)
    assert_almost_equal(moat.water_area().value, pi * (46.0**2 - 33.0**2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
