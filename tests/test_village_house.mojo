# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A house of the village: its parameters, its facades and materials, and
its building model, with its rooms, its doors, its windows and its
furniture."""

from extensions.building.ids import ElementId, SpaceId
from extensions.building.kinds import (
    BEDROOM,
    CABINET,
    COLUMN,
    DOOR,
    KITCHEN,
    LIVING,
    SHELF,
    STORAGE,
    TABLE,
    WALL,
    WINDOW,
)
from extensions.building.material import brick
from extensions.building.model import Element, Furnishing, Opening, Space
from extensions.vegetation.ground import Ground
from extensions.village.house import (
    BARN,
    BARN_DOOR,
    BOARDED,
    BRICK_FACADE,
    CHAMBERED,
    DWELLING,
    FRONT_DOOR,
    Facade,
    HAY,
    HouseParameters,
    HouseUse,
    MANGER,
    NATURAL,
    OUTSIDE_WALL,
    PAINT,
    BREAST_CLEAR,
    BREAST_DEPTH,
    BREAST_WIDTH,
    BREAST_Y,
    STAIR_GOING,
    STAIR_LANDING,
    STAIR_RISE,
    STAIR_WIDTH,
    STONE_FACADE,
    TIMBER_FRAMED,
    clear_breast,
    clear_stair,
    fieldstone,
    footing,
    front_wall,
    house_breast,
    house_lot,
    house_model,
    house_stair,
    lime_plaster,
)
from math.vector3 import Vector3
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.topology.arrangement import Point2
from units.si import (
    DEGREE,
    METER,
    RADIAN,
    Angle,
    Angle64,
    Length,
    Length64,
)


def _house(width: Float32, storeys: Int) -> HouseParameters:
    """Return a brick house `width` wide and 4 meters deep."""
    return HouseParameters(
        "test house",
        Length(width, METER),
        Length(4.0, METER),
        storeys,
        brick(),
    )


def test_a_facade_is_one_of_four() raises:
    for facade in [BRICK_FACADE, STONE_FACADE, TIMBER_FRAMED, BOARDED]:
        assert_true(facade.is_valid())
    assert_false(Facade(4).is_valid())
    assert_false(Facade(-1).is_valid())


def test_fieldstone_and_lime_plaster_are_materials() raises:
    var stone = fieldstone()
    assert_equal(stone.name, "fieldstone")
    assert_almost_equal(Float32(stone.density.value), 2200)
    var plaster = lime_plaster()
    assert_equal(plaster.name, "lime plaster")
    assert_true(plaster.look.red > plaster.look.blue)


def test_house_parameters_are_checked() raises:
    """A house in range passes; each field out of range is refused."""
    var house = _house(5, 2)
    house.check()
    assert_true(house.facade == BRICK_FACADE)
    assert_almost_equal(house.roof.x, NATURAL.x)
    assert_almost_equal(house.trim.y, PAINT.y)
    house.width = Length(2.0, METER)
    with assert_raises(contains="wide"):
        house.check()
    house = _house(5, 2)
    house.depth = Length(70.0, METER)
    with assert_raises(contains="deep"):
        house.check()
    with assert_raises(contains="storeys"):
        _house(5, 0).check()
    house = _house(5, 2)
    house.storey_height = Length(7.0, METER)
    with assert_raises(contains="storey must"):
        house.check()
    house = _house(5, 2)
    house.facade = Facade(9)
    with assert_raises(contains="facade"):
        house.check()
    house = _house(5, 2)
    house.pitch = Angle(70.0, DEGREE)
    with assert_raises(contains="pitch"):
        house.check()
    house = _house(5, 2)
    house.roof = Vector3(2, 0, 0)
    with assert_raises(contains="color"):
        house.check()
    house = _house(5, 2)
    house.trim = Vector3(0, -1, 0)
    with assert_raises(contains="color"):
        house.check()
    house = _house(5, 2)
    house.roof = Vector3(0, 0, 3)
    with assert_raises(contains="color"):
        house.check()


def test_a_wide_house_has_a_hall_and_a_chamber() raises:
    var house = _house(7, 2)
    assert_true(house.chambered())
    var model = house_model(house)
    assert_equal(len(model.storeys), 2)
    var ground = List[Int]()
    var upper = 0
    for s in range(len(model.spaces)):
        if model.spaces[s].storey.value == 0:
            ground.append(s)
        else:
            upper += 1
            assert_true(model.spaces[s].use == LIVING)
    assert_equal(len(ground), 2)
    assert_equal(upper, 1)
    assert_true(model.spaces[ground[0]].use == KITCHEN)
    assert_true(model.spaces[ground[1]].use == BEDROOM)
    # A front door in the middle of the hall's front wall, and a door
    # from the chamber into the hall.
    var front = front_wall(model)
    var outside = 0
    var inside = 0
    var windows = 0
    for o in model.openings:
        if o.kind == WINDOW:
            windows += 1
            continue
        if o.host == front:
            outside += 1
            var length = model.wall_frame(front).length
            assert_almost_equal(
                Float32(o.offset.value + o.width.value / 2),
                Float32(length / 2),
                atol=1e-5,
            )
            assert_almost_equal(Float32(o.width.value), FRONT_DOOR.x)
        else:
            inside += 1
    assert_equal(outside, 1)
    assert_equal(inside, 1)
    assert_true(windows > 4)
    assert_true(len(model.furnishings) > 4)
    with assert_raises(contains="storeys"):
        _ = house_model(_house(7, 0))


def test_a_narrow_house_has_a_hall_alone() raises:
    var house = _house(CHAMBERED - 1, 1)
    assert_false(house.chambered())
    var model = house_model(house)
    assert_equal(len(model.spaces), 1)
    var doors = 0
    for o in model.openings:
        if o.kind == DOOR:
            doors += 1
    assert_equal(doors, 1)


def test_a_house_with_no_front_wall_is_refused() raises:
    var model = house_model(_house(5, 1))
    model.elements = List[Element]()
    with assert_raises(contains="front wall"):
        _ = front_wall(model)


def test_a_house_stands_on_its_lot_at_its_footing() raises:
    var house = _house(5, 1)
    var lot = house_lot(house, 4, -4, Angle(0.3, RADIAN))
    assert_almost_equal(lot.half_width, 2.5)
    assert_almost_equal(lot.half_depth, 2)
    assert_almost_equal(lot.turn, 0.3, atol=1e-6)
    var ground = Ground()
    var feet = footing(lot, ground)
    var low = Float32(1.0e30)
    var high = Float32(-1.0e30)
    for k in range(4):
        var u = Float32(2.5) if k % 2 == 0 else Float32(-2.5)
        var v = Float32(2) if k < 2 else Float32(-2)
        var y = ground.height_at(
            4 + u * cos(Float32(0.3)) + v * sin(Float32(0.3)),
            -4 - u * sin(Float32(0.3)) + v * cos(Float32(0.3)),
        )
        low = min(low, y)
        high = max(high, y)
    assert_almost_equal(feet[0], low, atol=1e-5)
    assert_almost_equal(feet[1], high, atol=1e-5)
    assert_true(feet[1] >= feet[0])


def _two_storeys(width: Float32 = 9, storeys: Int = 2) -> HouseParameters:
    """Return a brick house `width` wide and 7 meters deep."""
    return HouseParameters(
        "stair house",
        Length(width, METER),
        Length(7.0, METER),
        storeys,
        brick(),
    )


def test_a_house_of_two_storeys_has_a_stair() raises:
    var model = house_model(_two_storeys())
    var stair = house_stair(model).value()
    # Fifteen risers of 2.8 / 15 meters, so each is at most 19 cm.
    assert_equal(stair.risers, 15)
    assert_almost_equal(stair.rise, 2.8 / 15, atol=1e-9)
    assert_true(stair.rise <= STAIR_RISE)
    assert_almost_equal(stair.height(), 2.8, atol=1e-9)
    # Its foot keeps a landing clear of the hall's west wall, and its
    # fourteen treads run along the back wall's inside face.
    var half = OUTSIDE_WALL / 2
    assert_almost_equal(stair.x0, -4.5 + half + STAIR_LANDING, atol=1e-9)
    assert_almost_equal(stair.x1 - stair.x0, 14 * STAIR_GOING, atol=1e-9)
    assert_almost_equal(stair.y1, 3.5 - half, atol=1e-9)
    assert_almost_equal(stair.y1 - stair.y0, STAIR_WIDTH, atol=1e-9)
    # The hall's ground storey and the room above keep their furniture
    # off the stair, its landing and its well.
    for piece in model.furnishings:
        var storey = model.spaces[piece.space.value].storey.value
        if storey > 1:
            continue
        var inside_x = (
            piece.center.x > stair.x0 - STAIR_LANDING
            and piece.center.x < stair.x1
        )
        var inside_y = piece.center.y > stair.y0
        assert_false(inside_x and inside_y)


def test_some_houses_have_no_stair() raises:
    # One storey, and a hall too short for six-meter storeys.
    assert_false(Bool(house_stair(house_model(_two_storeys(9, 1)))))
    var tall = _two_storeys()
    tall.storey_height = Length(6.0, METER)
    assert_false(Bool(house_stair(house_model(tall))))
    # A model with no room, and one whose upper storey is one riser up.
    var bare = house_model(_two_storeys())
    bare.spaces = List[Space]()
    assert_false(Bool(house_stair(bare)))
    var low = house_model(_two_storeys())
    low.storeys[1].elevation = Length64(STAIR_RISE, METER)
    assert_false(Bool(house_stair(low)))


def _table(space: Int, at: Point2) -> Furnishing:
    """Return a table turned half a radian, in a room, at a point."""
    return Furnishing(
        "table",
        TABLE,
        SpaceId(space),
        at,
        Angle64(0.5),
        Length64(1.2, METER),
        Length64(0.8, METER),
        Length64(0.75, METER),
    )


def test_a_stair_clears_the_furniture_in_its_way() raises:
    var model = house_model(_two_storeys(9, 3))
    var stair = house_stair(model).value()
    var top = -1
    for k in range(len(model.spaces)):
        if model.spaces[k].storey.value == 2:
            top = k
    var middle = Point2((stair.x0 + stair.x1) / 2, (stair.y0 + stair.y1) / 2)
    model.furnishings = [
        # On the stair: taken away.
        _table(0, middle),
        # Clear of it along x, and along y: kept.
        _table(0, Point2(stair.x1 + 2, middle.y)),
        _table(0, Point2(middle.x, stair.y0 - 2)),
        # Two storeys up, over the well: kept.
        _table(top, middle),
    ]
    clear_stair(model, stair)
    assert_equal(len(model.furnishings), 3)
    assert_equal(model.furnishings[2].space.value, top)
    # A model with no furniture keeps none.
    model.furnishings = List[Furnishing]()
    clear_stair(model, stair)
    assert_equal(len(model.furnishings), 0)


def test_a_brick_or_stone_house_has_a_chimney_breast() raises:
    var model = house_model(_two_storeys())
    var breast = house_breast(model).value()
    # The outside wall is as thick as `OUTSIDE_WALL` says.
    assert_almost_equal(
        model.constructions[0].thickness().value, OUTSIDE_WALL, atol=1e-12
    )
    # Against the west gable wall's inside face, on each storey.
    var half = OUTSIDE_WALL / 2
    assert_almost_equal(breast.x0, -4.5 + half, atol=1e-9)
    assert_almost_equal(breast.x1 - breast.x0, BREAST_DEPTH, atol=1e-9)
    assert_almost_equal((breast.y0 + breast.y1) / 2, BREAST_Y, atol=1e-9)
    assert_almost_equal(breast.y1 - breast.y0, BREAST_WIDTH, atol=1e-9)
    var columns = 0
    for element in model.elements:
        if element.kind == COLUMN:
            columns += 1
    assert_equal(columns, 2)
    # No window stands behind it; the gable keeps the others.
    var gable = 0
    for o in model.openings:
        var frame = model.wall_frame(o.host)
        var middle = frame.origin.x + frame.along.x * frame.length / 2
        if abs(middle - breast.x0) >= BREAST_DEPTH:
            continue
        gable += 1
        var a = frame.origin.y + frame.along.y * o.offset.value
        var b = a + frame.along.y * o.width.value
        assert_true(max(a, b) <= breast.y0 or min(a, b) >= breast.y1)
    assert_true(gable >= 2)
    # And no furniture stands near it.
    for piece in model.furnishings:
        var near_x = piece.center.x < breast.x1 + BREAST_CLEAR
        var near_y = (
            piece.center.y > breast.y0 - BREAST_CLEAR
            and piece.center.y < breast.y1 + BREAST_CLEAR
        )
        assert_false(near_x and near_y)
    # A model with no openings and no furniture keeps none.
    model.openings = List[Opening]()
    model.furnishings = List[Furnishing]()
    clear_breast(model, breast)
    assert_equal(len(model.openings), 0)
    assert_equal(len(model.furnishings), 0)
    # A framed or a boarded house has no hearth.
    var framed = _two_storeys()
    framed.facade = TIMBER_FRAMED
    assert_false(Bool(house_breast(house_model(framed))))
    var boarded = _two_storeys(9, 1)
    boarded.facade = BOARDED
    assert_false(Bool(house_breast(house_model(boarded))))
    var stone = _two_storeys(9, 1)
    stone.facade = STONE_FACADE
    assert_true(Bool(house_breast(house_model(stone))))


def _barn(storeys: Int = 1) -> HouseParameters:
    """Return a boarded barn 13 meters wide and 8 meters deep, with
    storeys 4.2 meters tall."""
    return HouseParameters(
        "barn",
        Length(13.0, METER),
        Length(8.0, METER),
        storeys,
        brick(),
        BOARDED,
        Length(4.2, METER),
        use=BARN,
    )


def test_a_barn_has_an_open_floor_a_wide_door_and_stock() raises:
    var barn = _barn()
    barn.check()
    assert_true(_house(9, 1).use == DWELLING)
    assert_false(barn.chambered())
    var model = house_model(barn)
    # One open floor, for storage.
    assert_equal(len(model.spaces), 1)
    assert_equal(model.spaces[0].name, "threshing floor")
    assert_true(model.spaces[0].use == STORAGE)
    # A wide door in the front wall, and small windows high up.
    var doors = 0
    var windows = 0
    for o in model.openings:
        if o.kind == DOOR:
            doors += 1
            assert_almost_equal(Float32(o.width.value), BARN_DOOR.x)
            assert_almost_equal(Float32(o.height.value), BARN_DOOR.y)
        else:
            windows += 1
            assert_almost_equal(o.sill.value, 2.3, atol=1e-9)
            assert_almost_equal(o.height.value, 0.7, atol=1e-9)
    assert_equal(doors, 1)
    assert_true(windows >= 4)
    # Hay along the west half of the back wall, and mangers along the east
    # half, facing into the barn, and no hearth.
    assert_false(Bool(house_breast(model)))
    var hay = 0
    var mangers = 0
    for piece in model.furnishings:
        assert_true(piece.center.y > 3)
        assert_almost_equal(piece.rotation.value, 3.141592653589793)
        if piece.kind == SHELF:
            hay += 1
            assert_true(piece.center.x + Float64(HAY.x) / 2 < 0)
        else:
            assert_true(piece.kind == CABINET)
            mangers += 1
            assert_true(piece.center.x - Float64(MANGER.x) / 2 > 0)
    assert_equal(hay, 2)
    assert_equal(mangers, 2)
    # A barn of brick has no hearth either, and its storeys above are
    # lofts.
    var lofted = _barn(2)
    lofted.facade = BRICK_FACADE
    var tall = house_model(lofted)
    assert_false(Bool(house_breast(tall)))
    assert_equal(tall.spaces[1].name, "loft 1")
    assert_true(tall.spaces[1].use == STORAGE)


def test_a_barn_is_checked() raises:
    var barn = _barn()
    barn.use = HouseUse(2)
    with assert_raises(contains="dwelling or a barn"):
        barn.check()
    barn = _barn()
    barn.width = Length(4.5, METER)
    with assert_raises(contains="barn must be"):
        barn.check()
    barn = _barn()
    barn.storey_height = Length(3.0, METER)
    with assert_raises(contains="barn's storey"):
        barn.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
