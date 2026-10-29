# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's view of a house: each facade's walls and dressings, the
windows, the doors on their hinges, the roof, the plinth and the steps,
and every kind of furniture."""

from core.assets import Assets
from core.buffer_geometry import COLOR
from core.scene import Scene
from extensions.building.ids import ElementId, SpaceId
from extensions.building.kinds import (
    CABINET,
    COLUMN,
    DESK,
    DOOR,
    SINK,
    TOILET,
    WALL,
    WINDOW,
)
from extensions.building.construction import double_glazing
from extensions.building.material import brick, timber
from extensions.building.model import Element, Furnishing, Opening, Space
from extensions.topology.arrangement import Point2
from extensions.vegetation.ground import Canyon, Ground, Lot
from extensions.village.house import (
    BARN,
    BOARDED,
    BRICK_FACADE,
    DWELLING,
    Facade,
    HouseParameters,
    STAIR_RISE,
    STONE_FACADE,
    TIMBER_FRAMED,
    fieldstone,
    front_wall,
    house_breast,
    house_lot,
    house_model,
    house_stair,
    lime_plaster,
)
from extensions.village.house_view import (
    CREAM,
    GLASS,
    OAK,
    SKY_GLASS,
    ZINC,
    WOOD_MEAN,
    door_leaf,
    facade_look,
    inside_shade,
    outside_shade,
    painted,
    stand_house,
)
from extensions.village.dressing import FLAME
from extensions.village.surfaces import HouseLooks, house_looks
from materials.material import MaterialId
from math.vector3 import Vector3
from std.math import pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
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
        # Seven sheets of the shell, six of the inside, and a leaf for
        # each of the two doors.
        assert_equal(standing.meshes, 15)
        assert_equal(len(scene.meshes), 15)
        # The inside hangs from a node of its own, and casts no shadow.
        assert_equal(
            scene.node(standing.inside).parent.value, standing.root.value
        )
        var hidden = 0
        for mesh in scene.meshes:
            if mesh.node.value == standing.inside.value:
                hidden += 1
                assert_false(mesh.cast_shadow)
        assert_equal(hidden, 6)
        assert_almost_equal(
            standing.radius, sqrt(Float32(3.5 * 3.5 + 2.5 * 2.5)), atol=1e-5
        )
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
    assert_equal(standing.meshes, 16)


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
    # No window: no pane, and so no glass. Of the shell, the facade, the
    # plaster of the gutters, the wood, the stone and the roof; of the
    # inside, the plaster, the wood, the stone, the planks, the lantern's
    # glow and the rug's cloth.
    assert_equal(standing.meshes, 11)


def test_a_model_with_no_walls_or_rooms_stands_its_roof() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var house = _house(5, 1)
    var model = house_model(house)
    model.elements = List[Element]()
    model.spaces = List[Space]()
    model.openings = List[Opening]()
    model.furnishings = List[Furnishing]()
    var scene = Scene()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var standing = stand_house(scene, assets, looks, house, model, lot, _flat())
    assert_equal(len(standing.interior.walls), 0)
    assert_equal(len(standing.hinges), 0)
    # The roof, its boards and the plinth stand. No wall, floor, ceiling
    # or window does.
    assert_true(standing.triangles > 0)
    assert_true(standing.meshes < 6)


def test_a_stair_rises_through_its_well() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var house = HouseParameters(
        "stair house", Length(9.0, METER), Length(7.0, METER), 2, brick()
    )
    var model = house_model(house)
    assert_true(Bool(house_stair(model)))
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var scene = Scene()
    var stair = stand_house(scene, assets, looks, house, model, lot, _flat())
    # The same house with its upper storey one riser up has no stair: no
    # treads, no well, no balustrade.
    var low = house_model(house)
    low.storeys[1].elevation = Length64(STAIR_RISE, METER)
    assert_false(Bool(house_stair(low)))
    var bare = Scene()
    var plain = stand_house(bare, assets, looks, house, low, lot, _flat())
    assert_equal(len(stair.interior.floors), len(plain.interior.floors) + 17)
    # Fourteen treads and fifteen risers, a stringer, a handrail, its
    # balusters, a newel, trimmers and a balustrade: about 650 triangles
    # more, less the joists over the well. No stone stands under the
    # treads or the upper floor: a block under each would add 200 more.
    var more = stair.triangles - plain.triangles
    assert_true(more > 550)
    assert_true(more < 750)
    assert_equal(stair.meshes, plain.meshes)


def test_a_brick_house_has_a_fireplace_and_a_chimney_over_it() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var house = _house(6, 2)
    var model = house_model(house)
    assert_true(Bool(house_breast(model)))
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var scene = Scene()
    var hearth = stand_house(scene, assets, looks, house, model, lot, _flat())
    # The same model without its breast's columns, the last elements.
    var cold = house_model(house)
    var kept = List[Element]()
    for e in cold.elements:
        if e.kind != COLUMN:
            kept.append(e.copy())
    cold.elements = kept^
    assert_false(Bool(house_breast(cold)))
    var bare = Scene()
    var plain = stand_house(bare, assets, looks, house, cold, lot, _flat())
    # The fireplace's ten blocks and its glow, the breast upstairs and
    # the stack's three blocks: about 170 triangles.
    var more = hearth.triangles - plain.triangles
    assert_true(more > 150)
    assert_true(more < 200)
    assert_equal(len(hearth.interior.walls), len(plain.interior.walls) + 2)


def _barn(pitch: Float32) -> HouseParameters:
    """Return a boarded barn 13 meters wide and 8 meters deep, with a
    storey 4.2 meters tall, under a roof of a pitch in degrees."""
    return HouseParameters(
        "barn",
        Length(13.0, METER),
        Length(8.0, METER),
        1,
        timber(),
        BOARDED,
        Length(4.2, METER),
        Angle(pitch, DEGREE),
        use=BARN,
    )


def _drawn(
    mut assets: Assets,
    looks: HouseLooks,
    house: HouseParameters,
    empty: Bool = False,
) raises -> Int:
    """Stand a barn's model, drawn as the house says, with its furniture
    or `empty`, and return its triangles."""
    var scene = Scene()
    var barn = _barn(Float32(house.pitch.to(DEGREE)))
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var model = house_model(barn)
    if empty:
        model.furnishings.clear()
    return stand_house(
        scene, assets, looks, house, model, lot, _flat()
    ).triangles


def test_a_barn_hangs_two_leaves_that_swing_out() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    var barn = _barn(35)
    var lot = house_lot(barn, 0, 0, Angle(0.0, RADIAN))
    var standing = stand_house(
        scene, assets, looks, barn, house_model(barn), lot, _flat()
    )
    # One doorway, and a leaf at each of its jambs, turned half a turn
    # from each other.
    assert_equal(len(standing.interior.doorways), 1)
    assert_equal(len(standing.hinges), 2)
    ref first = standing.hinges[0]
    ref second = standing.hinges[1]
    assert_equal(first.door, 0)
    assert_equal(second.door, 0)
    assert_almost_equal(abs(first.shut - second.shut), pi, atol=1e-4)
    # Each leaf's free edge swings out of the barn, toward the front: the
    # model's -y, the scene's +z.
    for hinge in standing.hinges:
        var opened = hinge.shut + hinge.sense * 0.5
        var shut_z = -sin(hinge.shut)
        var open_z = -sin(opened)
        assert_true(open_z - shut_z > 0.1)


def test_a_barn_draws_its_hay_its_mangers_and_its_loft_door() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    # The barn draws bales and mangers for its stock.
    var steep = _barn(35)
    var hay = _drawn(assets, looks, steep) - _drawn(assets, looks, steep, True)
    assert_true(hay > 600)
    # The same model drawn as a barn and as a dwelling: what differs
    # but the loft door is the same at every pitch.
    var dwelling = _barn(35)
    dwelling.use = DWELLING
    var stocked = _drawn(assets, looks, steep) - _drawn(assets, looks, dwelling)
    # A gable too low for a loft door has none.
    var low = _barn(8)
    var low_dwelling = _barn(8)
    low_dwelling.use = DWELLING
    var bare = _drawn(assets, looks, low) - _drawn(assets, looks, low_dwelling)
    assert_true(stocked - bare > 100)
    # A flat-roofed barn has no gable, so no loft door either.
    var flat = _barn(0)
    var flat_dwelling = _barn(0)
    flat_dwelling.use = DWELLING
    assert_equal(
        _drawn(assets, looks, flat) - _drawn(assets, looks, flat_dwelling),
        bare,
    )


def test_a_wide_door_leaf_is_braced() raises:
    var narrow = door_leaf(1.0, 2.0, OAK)
    var wide = door_leaf(1.6, 3.0, OAK)
    # Four boards and the ledges, straps and ring of a narrow leaf; six
    # boards and two braces more on a wide one.
    assert_equal(wide.triangles() - narrow.triangles(), 4 * 12)


def _has_color(
    scene: Scene, assets: Assets, material: MaterialId, color: Vector3
) raises -> Bool:
    """Return whether a mesh of a material has a vertex of a color."""
    for mesh in scene.meshes:
        if mesh.material.value != material.value:
            continue
        ref colors = assets.geometries.get(mesh.geometry).attribute_view(
            String(COLOR)
        )
        for v in range(colors.count()):
            if (colors.vector3(v) - color).length() < 1e-4:
                return True
    return False


def _cloth_meshes(scene: Scene, looks: HouseLooks) -> Int:
    """Return how many meshes wear the cloth."""
    var count = 0
    for mesh in scene.meshes:
        if mesh.material.value == looks.cloth.value:
            count += 1
    return count


def test_a_dwelling_is_dressed_and_lit_by_lanterns() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    # A house of two storeys with a stair and a chamber: a rug and a
    # lantern in each room, clear of the stair.
    var house = Scene()
    _ = _stand(house, assets, looks, _house(7, 2))
    assert_equal(_cloth_meshes(house, looks), 1)
    assert_true(_has_color(house, assets, looks.daylight, FLAME * 0.8))
    # A house 3 meters deep, with a stair: the stair's band leaves too
    # little floor for a rug or a lantern in either storey.
    var shallow = Scene()
    _ = _stand(
        shallow,
        assets,
        looks,
        HouseParameters(
            "shallow", Length(5.0, METER), Length(3.0, METER), 2, brick()
        ),
    )
    assert_false(_has_color(shallow, assets, looks.daylight, FLAME * 0.8))
    # A barn has no rug and no lantern.
    var barn = Scene()
    var lot = house_lot(_barn(35), 0, 0, Angle(0.0, RADIAN))
    _ = stand_house(
        barn, assets, looks, _barn(35), house_model(_barn(35)), lot, _flat()
    )
    assert_equal(_cloth_meshes(barn, looks), 0)
    assert_false(_has_color(barn, assets, looks.daylight, FLAME * 0.8))


def test_a_house_is_dressed_by_its_facade() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    # A brick house of two storeys has a band of stone round it at its
    # upper floor, a block along each face, where a stone house has none.
    var brick = Scene()
    var stone = Scene()
    var bricks = _stand(brick, assets, looks, _house(6, 2))
    var stones = _stand(stone, assets, looks, _house(6, 2, STONE_FACADE))
    assert_equal(bricks - stones, 4 * 12)
    var one = Scene()
    var two = Scene()
    assert_equal(
        _stand(one, assets, looks, _house(6, 1)),
        _stand(two, assets, looks, _house(6, 1, STONE_FACADE)),
    )
    # Its panes show the sky at their tops and the ground at their feet,
    # and its frames are cream; a framed house's frames are not.
    assert_true(_has_color(brick, assets, looks.glass, SKY_GLASS))
    assert_true(_has_color(brick, assets, looks.glass, GLASS))
    assert_true(_has_color(brick, assets, looks.wood, painted(CREAM)))
    var framed = Scene()
    _ = _stand(framed, assets, looks, _house(6, 2, TIMBER_FRAMED))
    assert_false(_has_color(framed, assets, looks.wood, painted(CREAM)))
    # A pitched roof has zinc gutters and downpipes; a flat one has none.
    assert_true(_has_color(brick, assets, looks.plaster, ZINC))
    var flat = _house(6, 2)
    flat.pitch = Angle(0.0, DEGREE)
    var level = Scene()
    _ = _stand(level, assets, looks, flat)
    assert_false(_has_color(level, assets, looks.plaster, ZINC))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
