# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a character can walk in a house: walls cut at the doors, the
floor and its ceiling, the steps up to the door, the furniture and the
doorways, all read from the house's building model."""

from extensions.building.kinds import DOOR, WALL
from extensions.building.material import brick
from extensions.building.model import Opening
from extensions.vegetation.ground import Ground, Lot
from extensions.village.house import (
    HouseParameters,
    front_wall,
    house_lot,
    house_model,
)
from extensions.village.interior import (
    Doorway,
    HouseInterior,
    MOST_STEPS,
    PLINTH_OVERHANG,
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
    # Only the ground storey's furniture stands in the way.
    var ground_pieces = 0
    for piece in model.furnishings:
        if model.spaces[piece.space.value].storey.value == 0:
            ground_pieces += 1
    assert_equal(len(inside.furniture), ground_pieces)
    assert_true(ground_pieces > 0)
    assert_true(len(model.furnishings) > ground_pieces)


def test_steps_lead_up_to_a_door_above_the_ground() raises:
    var house = _house(1)
    var model = house_model(house)
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    # A floor a meter over level ground: five steps of a sixth of a meter.
    var high = house_interior(model, lot, 1.0, _flat())
    assert_equal(len(high.floors), 6)
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
