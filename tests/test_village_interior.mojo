# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a character can walk in a house: walls cut at the doors, the
floor and its ceiling, the steps up to the door, the furniture and the
doorways, all read from the house's building model."""

from extensions.building.kinds import DOOR, WALL
from extensions.building.material import brick
from extensions.building.model import Element, Opening
from extensions.vegetation.ground import Ground, Lot
from extensions.village.house import (
    HouseParameters,
    STAIR_GOING,
    front_wall,
    house_lot,
    house_model,
    house_stair,
)
from extensions.village.interior import (
    Doorway,
    HouseInterior,
    MOST_STEPS,
    PLINTH_OVERHANG,
    RAIL_HEIGHT,
    STEP_DEPTH,
    house_interior,
)
from extensions.village.terrain import OPEN_SKY
from extensions.building.ids import ElementId
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER, RADIAN, Angle, Length, Length64


def _flat() raises -> Ground:
    """Return level ground with no pond."""
    return Ground(hill_height=Length(0.0, METER))


def _house(storeys: Int) -> HouseParameters:
    """Return a brick house 7 meters wide and 5.5 deep: a hall and a
    chamber on its ground storey."""
    return HouseParameters(
        "test house", Length(7.0, METER), Length(5.5, METER), storeys, brick()
    )


def test_a_house_has_walls_cut_at_its_doors() raises:
    var house = _house(1)
    var model = house_model(house)
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var inside = house_interior(model, lot, 0, _flat())
    var walls = 0
    var doors = 0
    for e in model.elements:
        if e.kind == WALL:
            walls += 1
    for o in model.openings:
        if o.kind == DOOR:
            doors += 1
    # Each door cuts its wall in two and leaves a span over it.
    assert_equal(len(inside.walls), walls + doors * 2)
    assert_equal(len(inside.doorways), doors)
    # The front door leads out, toward +z, and swings in, toward -z.
    var outside = 0
    for way in inside.doorways:
        if way.outside:
            outside += 1
            assert_almost_equal(way.middle().z, 2.75, atol=1e-4)
            assert_true(way.swing_z < -0.99)
            assert_almost_equal(way.height, 2.1, atol=1e-6)
    assert_equal(outside, 1)
    # The front wall's line holds the pieces beside the front door, the
    # piece over it, and the chamber's front wall.
    var front = List[Int]()
    for k in range(len(inside.walls)):
        ref span = inside.walls[k]
        if abs(span.z0 - 2.75) < 1.0e-4 and abs(span.z1 - 2.75) < 1.0e-4:
            front.append(k)
    assert_true(len(front) >= 3)
    var lintels = 0
    for k in front:
        if inside.walls[k].bottom > 2:
            lintels += 1
            assert_false(inside.walls[k].blocks(0, 1.5))
    assert_equal(lintels, 1)


def test_a_floor_carries_and_its_slab_covers() raises:
    var house = _house(2)
    var model = house_model(house)
    var lot = house_lot(house, 3, -2, Angle(0.4, RADIAN))
    var inside = house_interior(model, lot, 1.5, _flat())
    assert_almost_equal(inside.floor_height, 1.5)
    ref floor = inside.floors[0]
    assert_almost_equal(floor.height, 1.5)
    # The ceiling is the underside of the 20 centimeter slab over it.
    assert_almost_equal(floor.ceiling, 1.5 + 2.8 - 0.2, atol=1e-5)
    assert_almost_equal(floor.area.half_width, 3.5 + PLINTH_OVERHANG, atol=1e-6)
    assert_almost_equal(floor.area.turn, 0.4, atol=1e-6)
    # Each piece stands in the way on its own storey's floor, as high as
    # it is: a piece upstairs passes over the floor below.
    assert_equal(len(inside.furniture), len(model.furnishings))
    var upstairs = 0
    for k in range(len(model.furnishings)):
        ref piece = model.furnishings[k]
        ref span = inside.furniture[k]
        var storey = model.spaces[piece.space.value].storey.value
        var bottom = Float32(1.5 + 2.8 * Float64(storey))
        assert_almost_equal(span.bottom, bottom, atol=1e-5)
        assert_almost_equal(
            span.top - span.bottom, Float32(piece.height.value), atol=1e-5
        )
        upstairs += storey
    assert_true(upstairs > 0)
    assert_true(upstairs < len(model.furnishings))


def test_steps_lead_up_to_a_door_above_the_ground() raises:
    var house = _house(1)
    var model = house_model(house)
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    # A floor a meter over level ground: five steps of a sixth of a meter.
    var high = house_interior(model, lot, 1.0, _flat())
    assert_equal(len(high.floors), 6)
    assert_equal(high.steps, 5)
    var last = Float32(1)
    for k in range(1, 6):
        ref step = high.floors[k]
        assert_true(step.height < last)
        assert_equal(step.ceiling, OPEN_SKY)
        last = step.height
    assert_almost_equal(high.floors[1].height, 1 - Float32(1) / 6, atol=1e-5)
    # The first step is just past the plinth.
    assert_almost_equal(
        high.floors[1].area.z,
        2.75 + PLINTH_OVERHANG + STEP_DEPTH / 2,
        atol=1e-4,
    )
    # A floor three meters up has the most steps.
    var tall = house_interior(model, lot, 3.0, _flat())
    assert_equal(len(tall.floors), 1 + MOST_STEPS)
    # A floor a little over the ground has one step, and one at it none.
    var low = house_interior(model, lot, 0.15, _flat())
    assert_equal(len(low.floors), 2)
    var level = house_interior(model, lot, 0.05, _flat())
    assert_equal(len(level.floors), 1)


def test_doors_in_one_wall_cut_it_in_order() raises:
    var house = _house(2)
    var model = house_model(house)
    var front = front_wall(model)
    var length = model.wall_frame(front).length
    # One door left of the front door, and one right of it.
    _ = model.add_opening(
        DOOR,
        front,
        Length64(0.05, METER),
        Length64(0, METER),
        Length64(0.5, METER),
        Length64(2.0, METER),
        None,
    )
    _ = model.add_opening(
        DOOR,
        front,
        Length64(length - 0.55, METER),
        Length64(0, METER),
        Length64(0.5, METER),
        Length64(2.0, METER),
        None,
    )
    # And a door upstairs, which the ground storey does not walk through.
    var upper = -1
    for e in range(len(model.elements)):
        ref element = model.elements[e]
        if (
            element.kind == WALL
            and element.storey.value == 1
            and model.is_exterior(ElementId(e))
        ):
            upper = e
    var frame = model.wall_frame(ElementId(upper))
    var free = Float64(0.05)
    # Find a place on the wall clear of its windows.
    var spots = model.openings_of(ElementId(upper))
    if len(spots) > 0:
        free = model.openings[spots[0].value].offset.value - 0.6
    _ = model.add_opening(
        DOOR,
        ElementId(upper),
        Length64(max(0.02, free), METER),
        Length64(0, METER),
        Length64(0.5, METER),
        Length64(2.0, METER),
        None,
    )
    _ = frame
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var inside = house_interior(model, lot, 0, _flat())
    # Three doors on the ground storey's front wall, and the inside door.
    assert_equal(len(inside.doorways), 4)
    var front_spans = 0
    for span in inside.walls:
        if abs(span.z0 - 2.75) < 1.0e-4 and span.bottom < 1:
            front_spans += 1
    # The hall's three front doors leave four pieces of its front wall,
    # and the chamber's front wall is one more.
    assert_equal(front_spans, 5)


def test_a_wall_with_no_door_is_one_span() raises:
    var house = _house(1)
    var model = house_model(house)
    model.openings = List[Opening]()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var inside = house_interior(model, lot, 0, _flat())
    var walls = 0
    for e in model.elements:
        if e.kind == WALL:
            walls += 1
    assert_equal(len(inside.walls), walls)
    assert_equal(len(inside.doorways), 0)
    assert_equal(len(inside.floors), 1)


def test_doors_that_touch_leave_no_piece_between_them() raises:
    var house = _house(1)
    var model = house_model(house)
    var front = front_wall(model)
    # Only the doors stay, so a second door can touch the front door.
    var doors = List[Opening]()
    var end = Float64(0)
    for o in model.openings:
        if o.kind == DOOR:
            doors.append(o.copy())
            if o.host == front:
                end = o.offset.value + o.width.value
    model.openings = doors^
    _ = model.add_opening(
        DOOR,
        front,
        Length64(end, METER),
        Length64(0, METER),
        Length64(0.5, METER),
        Length64(2.0, METER),
        None,
    )
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var inside = house_interior(model, lot, 0, _flat())
    var low = 0
    var heads = 0
    for span in inside.walls:
        if abs(span.z0 - 2.75) < 1.0e-4:
            if span.bottom < 1:
                low += 1
            else:
                heads += 1
    # The hall's front wall keeps a piece left of the doors and one right
    # of them, and the chamber's front wall is one more. Each door has
    # the wall over its head.
    assert_equal(low, 3)
    assert_equal(heads, 2)


def test_a_model_with_no_elements_is_only_its_floor() raises:
    var house = _house(1)
    var model = house_model(house)
    model.elements = List[Element]()
    model.openings = List[Opening]()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var inside = house_interior(model, lot, 0, _flat())
    assert_equal(len(inside.walls), 0)
    assert_equal(len(inside.doorways), 0)
    assert_equal(len(inside.floors), 1)
    # No slab covers the floor, so its ceiling is the storey's top.
    assert_almost_equal(inside.floors[0].ceiling, 2.8, atol=1.0e-4)


def test_a_stair_climbs_to_the_floor_above() raises:
    var house = HouseParameters(
        "stair house", Length(9.0, METER), Length(7.0, METER), 2, brick()
    )
    var model = house_model(house)
    var stair = house_stair(model).value()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var inside = house_interior(model, lot, 0, _flat())
    # The ground floor, a floor for each of the fourteen treads, and the
    # upper floor before the well, beside its foot and past its top.
    assert_equal(len(inside.floors), 1 + 14 + 3)
    assert_equal(inside.steps, 0)
    var top = Float32(stair.height())
    var over = top + 2.8 - 0.2
    for k in range(14):
        ref tread = inside.floors[1 + k]
        assert_almost_equal(
            tread.height, Float32(Float64(k + 1) * stair.rise), atol=1e-5
        )
        assert_almost_equal(tread.ceiling, over, atol=1e-4)
        assert_almost_equal(
            tread.area.half_width, Float32(STAIR_GOING / 2), atol=1e-6
        )
        # Tread by tread along the plan's x, at the stair's middle.
        assert_almost_equal(
            tread.area.x,
            Float32(stair.x0 + (Float64(k) + 0.5) * STAIR_GOING),
            atol=1e-5,
        )
        assert_almost_equal(
            tread.area.z, -Float32((stair.y0 + stair.y1) / 2), atol=1e-5
        )
    for k in range(15, 18):
        assert_almost_equal(inside.floors[k].height, top, atol=1e-5)
        assert_almost_equal(inside.floors[k].ceiling, over, atol=1e-4)
    # The upper floor past the top reaches from the stair to the east wall.
    ref past = inside.floors[17]
    assert_almost_equal(
        past.area.x - past.area.half_width, Float32(stair.x1), atol=1e-5
    )
    # Three railings after the walls: along the well's open side from the
    # ground floor up, across its foot upstairs, and under the stair's top.
    var walls = 0
    var doors = 0
    for e in model.elements:
        if e.kind == WALL:
            walls += 1
    for o in model.openings:
        if o.kind == DOOR:
            doors += 1
    assert_equal(len(inside.walls), walls + doors * 2 + 3)
    var n = len(inside.walls)
    ref side = inside.walls[n - 3]
    assert_almost_equal(side.bottom, 0)
    assert_almost_equal(side.top, top + RAIL_HEIGHT, atol=1e-5)
    assert_almost_equal(side.z0, -Float32(stair.y0), atol=1e-5)
    assert_almost_equal(side.z1, -Float32(stair.y0), atol=1e-5)
    ref foot = inside.walls[n - 2]
    assert_almost_equal(foot.bottom, top, atol=1e-5)
    assert_almost_equal(foot.x0, Float32(stair.x0), atol=1e-5)
    ref under = inside.walls[n - 1]
    assert_almost_equal(under.bottom, 0)
    assert_almost_equal(under.top, top / 2, atol=1e-5)
    assert_almost_equal(under.x0, Float32(stair.x1), atol=1e-5)


def test_the_front_door_is_the_first_that_leads_out() raises:
    var inside = HouseInterior(0)
    with assert_raises(contains="outside"):
        _ = inside.front_door()
    inside.doorways.append(Doorway(0, 0, 1, 0, 0, 1, 1, 2, 0, False))
    inside.doorways.append(Doorway(5, 0, 1, 0, 0, -1, 1, 2, 0, True))
    inside.doorways.append(Doorway(9, 0, 1, 0, 0, -1, 1, 2, 0, True))
    assert_almost_equal(inside.front_door().hinge_x, 5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
