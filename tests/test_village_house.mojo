# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A house of the village: its parameters, its facades and materials, and
its building model, with its rooms, its doors, its windows and its
furniture."""

from extensions.building.ids import ElementId
from extensions.building.kinds import (
    BEDROOM,
    DOOR,
    KITCHEN,
    LIVING,
    WALL,
    WINDOW,
)
from extensions.building.material import brick
from extensions.building.model import Element
from extensions.vegetation.ground import Ground
from extensions.village.house import (
    BOARDED,
    BRICK_FACADE,
    CHAMBERED,
    FRONT_DOOR,
    Facade,
    HouseParameters,
    NATURAL,
    PAINT,
    STONE_FACADE,
    TIMBER_FRAMED,
    fieldstone,
    footing,
    front_wall,
    house_lot,
    house_model,
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
from units.si import DEGREE, METER, RADIAN, Angle, Length


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
