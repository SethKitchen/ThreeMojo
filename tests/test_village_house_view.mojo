# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's view of a house: each facade's walls and dressings, the
windows, the doors on their hinges, the roof, the plinth and the steps,
and every kind of furniture."""

from core.assets import Assets
from core.scene import Scene
from extensions.building.ids import ElementId, SpaceId
from extensions.building.kinds import (
    CABINET,
    DESK,
    DOOR,
    SINK,
    TOILET,
    WALL,
    WINDOW,
)
from extensions.building.construction import double_glazing
from extensions.building.material import brick, timber
from extensions.building.model import Furnishing, Opening
from extensions.topology.arrangement import Point2
from extensions.vegetation.ground import Canyon, Ground, Lot
from extensions.village.house import (
    BOARDED,
    BRICK_FACADE,
    Facade,
    HouseParameters,
    STONE_FACADE,
    TIMBER_FRAMED,
    fieldstone,
    front_wall,
    house_lot,
    house_model,
    lime_plaster,
)
from extensions.village.house_view import (
    OAK,
    WOOD_MEAN,
    door_leaf,
    facade_look,
    inside_shade,
    outside_shade,
    painted,
    stand_house,
)
from extensions.village.surfaces import HouseLooks, house_looks
from math.vector3 import Vector3
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    RADIAN,
    Angle,
    Angle64,
    Length,
    Length64,
)


def _flat() raises -> Ground:
    """Return level ground with no pond."""
    return Ground(hill_height=Length(0.0, METER))


def _house(
    width: Float32, storeys: Int, facade: Facade = BRICK_FACADE
) -> HouseParameters:
    """Return a house `width` wide and 5 meters deep."""
    return HouseParameters(
        "test house",
        Length(width, METER),
        Length(5.0, METER),
        storeys,
        brick(),
        facade,
    )


def test_paint_and_shade() raises:
    var green = painted(Vector3(0.1, 0.2, 0.05))
    assert_almost_equal(green.x * WOOD_MEAN.x, 0.1, atol=1e-6)
    assert_almost_equal(green.z * WOOD_MEAN.z, 0.05, atol=1e-6)
    # An outside wall is darker at its foot and under its eaves.
    var middle = outside_shade(2, 1.5, 3, 4)
    assert_true(outside_shade(2, 0, 3, 4) < middle)
    assert_true(outside_shade(2, 3, 3, 4) < middle)
    # An inside wall is darker in its corners, at the floor and at the
    # ceiling.
    var open = inside_shade(2, 1.4, 4, 2.8)
    assert_true(inside_shade(0, 1.4, 4, 2.8) < open)
    assert_true(inside_shade(2, 0, 4, 2.8) < open)
    assert_true(inside_shade(2, 2.8, 4, 2.8) < open)


def test_a_door_leaf_hangs_from_its_hinge() raises:
    var leaf = door_leaf(1, 2, OAK)
    assert_true(leaf.triangles() > 0)
    var low = Vector3(1.0e9, 1.0e9, 1.0e9)
    var high = Vector3(-1.0e9, -1.0e9, -1.0e9)
    for k in range(len(leaf.positions) // 3):
        var p = Vector3(
            leaf.positions[k * 3],
            leaf.positions[k * 3 + 1],
            leaf.positions[k * 3 + 2],
        )
        low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
    assert_almost_equal(low.x, 0, atol=0.01)
    assert_almost_equal(high.x, 1, atol=0.01)
    assert_almost_equal(low.y, 0, atol=1e-5)
    assert_almost_equal(high.y, 2, atol=1e-5)
    assert_true(high.z < 0.07 and low.z > -0.07)


def test_each_facade_has_its_own_look() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    assert_equal(facade_look(looks, BRICK_FACADE).value, looks.brick.value)
    assert_equal(facade_look(looks, STONE_FACADE).value, looks.fieldstone.value)
    assert_equal(facade_look(looks, TIMBER_FRAMED).value, looks.plaster.value)
    assert_equal(facade_look(looks, BOARDED).value, looks.boards.value)


def _stand(
    mut scene: Scene,
    mut assets: Assets,
    looks: HouseLooks,
    house: HouseParameters,
) raises -> Int:
    """Stand a house on level ground and return its triangles."""
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var standing = stand_house(
        scene, assets, looks, house, house_model(house), lot, _flat()
    )
    return standing.triangles


def test_every_facade_stands_with_its_doors_on_hinges() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    for facade in [BRICK_FACADE, STONE_FACADE, TIMBER_FRAMED, BOARDED]:
        var scene = Scene()
        var house = _house(7, 2, facade)
        var lot = house_lot(house, 2, -3, Angle(0.5, RADIAN))
        var model = house_model(house)
        var standing = stand_house(
            scene, assets, looks, house, model, lot, _flat()
        )
        # Eight sheets, and a leaf for each of the two doors.
        assert_equal(standing.meshes, 10)
        assert_equal(len(scene.meshes), 10)
        assert_equal(len(standing.hinges), 2)
        assert_equal(len(standing.interior.doorways), 2)
        assert_true(standing.triangles > 2000)
        ref root = scene.node(standing.root)
        assert_almost_equal(root.position.x, 2, atol=1e-6)
        assert_almost_equal(
            root.position.y, standing.interior.floor_height, atol=1e-6
        )
        # Each hinge opens its leaf one way or the other.
        for hinge in standing.hinges:
            assert_almost_equal(abs(hinge.sense), 1, atol=1e-5)


def test_a_flat_roofed_house_draws_no_roof() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    var pitched = _stand(scene, assets, looks, _house(5, 1))
    var flat = _house(5, 1)
    flat.pitch = Angle(0.0, DEGREE)
    var bare = Scene()
    var level = _stand(bare, assets, looks, flat)
    assert_true(level < pitched)
    # One door, and no roof sheet.
    assert_equal(len(bare.meshes), len(scene.meshes) - 1)


def test_steps_and_a_deep_plinth_stand_on_a_slope() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    # The canyon's rim falls away under the house's front.
    var slope = Ground(
        hill_height=Length(0.0, METER),
        canyon=Canyon(
            Length(0.0, METER),
            Length(80.0, METER),
            Length(3.0, METER),
            Length(0.0, METER),
        ),
    )
    var house = _house(5, 1)
    var lot = house_lot(house, 0, -1, Angle(Float32(pi), RADIAN))
    var model = house_model(house)
    var standing = stand_house(scene, assets, looks, house, model, lot, slope)
    assert_true(len(standing.interior.floors) > 2)
    var level = Scene()
    var flat = stand_house(
        level, assets, looks, house, house_model(house), lot, _flat()
    )
    assert_equal(len(flat.interior.floors), 1)
    assert_true(standing.triangles > flat.triangles)


def test_every_kind_of_furniture_is_drawn() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var house = _house(7, 1)
    var model = house_model(house)
    var bare = house_model(house)
    bare.furnishings = List[Furnishing]()
    var scene = Scene()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var empty = stand_house(scene, assets, looks, house, bare, lot, _flat())
    # A desk, a sink, a toilet and a cabinet in the bare hall: no house
    # of the village furnishes itself with them.
    var hall = SpaceId(0)
    var places = [
        Point2(-2.5, -1.5),
        Point2(-2.5, 0),
        Point2(-2.5, 1.5),
        Point2(-0.8, -1.5),
    ]
    var kinds = [DESK, SINK, TOILET, CABINET]
    for k in range(4):
        _ = bare.add_furnishing(
            kinds[k],
            hall,
            places[k],
            Angle64(0),
            Length64(0.6, METER),
            Length64(0.4, METER),
            Length64(0.8, METER),
        )
    var full = Scene()
    var furnished = stand_house(full, assets, looks, house, bare, lot, _flat())
    assert_true(furnished.triangles > empty.triangles)
    # The village's own furniture: tables, chairs, a counter, a bed, a
    # nightstand and a wardrobe.
    var home = Scene()
    var lived = stand_house(home, assets, looks, house, model, lot, _flat())
    assert_true(lived.triangles > empty.triangles)


def test_a_wide_window_on_a_framed_wall_and_doors_upstairs() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var house = _house(7, 2, TIMBER_FRAMED)
    var model = house_model(house)
    # Clear the openings of one ground wall, and cut a window wider and
    # taller than the village's.
    var wall = -1
    for e in range(len(model.elements)):
        ref element = model.elements[e]
        if (
            element.kind == WALL
            and element.storey.value == 0
            and model.is_exterior(ElementId(e))
            and ElementId(e) != front_wall(model)
            and model.wall_frame(ElementId(e)).length > 4.5
        ):
            wall = e
    var kept = List[Opening]()
    for o in model.openings:
        if o.host.value != wall:
            kept.append(o.copy())
    model.openings = kept^
    _ = model.add_opening(
        WINDOW,
        ElementId(wall),
        Length64(0.6, METER),
        Length64(0.3, METER),
        Length64(2.2, METER),
        Length64(2.1, METER),
        double_glazing(),
    )
    # A door upstairs: the ground storey's doors alone turn on hinges.
    var upper = -1
    for e in range(len(model.elements)):
        ref element = model.elements[e]
        if element.kind == WALL and element.storey.value == 1:
            if not model.is_exterior(ElementId(e)):
                continue
            if len(model.openings_of(ElementId(e))) == 0:
                continue
            upper = e
    var first = model.openings_of(ElementId(upper))[0].value
    var offset = model.openings[first].offset.value
    _ = model.add_opening(
        DOOR,
        ElementId(upper),
        Length64(max(0.02, offset - 0.6), METER),
        Length64(0, METER),
        Length64(0.5, METER),
        Length64(2.0, METER),
        None,
    )
    var scene = Scene()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var standing = stand_house(scene, assets, looks, house, model, lot, _flat())
    assert_equal(len(standing.hinges), 2)
    # The upstairs door has a leaf too.
    assert_equal(standing.meshes, 11)


def test_a_boarded_house_with_no_openings() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var house = _house(5, 1, BOARDED)
    var model = house_model(house)
    model.openings = List[Opening]()
    var scene = Scene()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var standing = stand_house(scene, assets, looks, house, model, lot, _flat())
    assert_equal(len(standing.hinges), 0)
    # No window: no pane, and so no glass and no daylight sheet.
    assert_equal(standing.meshes, 6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
