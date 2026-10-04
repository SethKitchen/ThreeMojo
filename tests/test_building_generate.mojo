# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the building generators: floor plans, doors and windows,
furniture, towers, and the model's furnishings.

The references are invariants: plan areas add up to the footprint, every
room shares a wall with a corridor or lobby, every room gets one door,
every piece of furniture stands inside its room without overlap, and the
same seed gives the same building.
"""

from std.math import inf, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.construction import (
    Construction,
    Glazing,
    Layer,
    double_glazing,
)
from extensions.building.fingerprint import fingerprint
from extensions.building.generate.furnish import furnish
from extensions.building.generate.openings import (
    WindowOptions,
    add_doors,
    add_windows,
)
from extensions.building.generate.plan import (
    FloorProgram,
    LOBBY_FLOOR,
    OFFICE_FLOOR,
    PlanOptions,
    RESIDENTIAL_FLOOR,
    clip_half,
    default_plan_options,
    is_convex,
    plan_floor,
)
from extensions.building.generate.tower import (
    TowerOptions,
    generate_tower,
    inset,
)
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    FurnishingId,
    MaterialId,
    SpaceId,
)
from extensions.building.kinds import (
    BED,
    BEDROOM,
    CHAIR,
    COLUMN,
    CORRIDOR,
    DESK,
    DOOR,
    FurnitureKind,
    KITCHEN,
    LOBBY,
    OFFICE,
    SHELF,
    WALL,
    WINDOW,
)
from extensions.building.material import (
    BuildingMaterial,
    concrete,
    gypsum_board,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    quads_apart,
)
from extensions.topology.arrangement import Point2, polygon_area
from generators.skyscraper import SkyscraperParameters
from units.si import (
    Angle64,
    DEGREE,
    DEGREE64,
    Length,
    Length64,
    METER,
    RADIAN,
    SQUARE_METER,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _rect(x0: Float64, y0: Float64, x1: Float64, y1: Float64) -> List[Point2]:
    return [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]


def _assemble(var plans: List[StoreyPlan]) raises -> Building:
    var materials = List[BuildingMaterial]()
    materials.append(concrete())
    materials.append(gypsum_board())
    var constructions = List[Construction]()
    constructions.append(Construction("wall", [Layer(MaterialId(0), _m(0.2))]))
    constructions.append(
        Construction("partition", [Layer(MaterialId(1), _m(0.1))])
    )
    var c = ConstructionId(0)
    return assemble(
        "generated",
        Site(Angle64(0), Angle64(0), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(c, ConstructionId(1), c, c, c),
        Length64(1e-6, METER),
    )


def _one_storey(var spaces: List[SpacePlan]) raises -> Building:
    var plans = List[StoreyPlan]()
    plans.append(StoreyPlan("g", _m(3.5), spaces^))
    return _assemble(plans^)


# --- geometry helpers --------------------------------------------------------


def test_clip_half_and_convexity() raises:
    var square = _rect(0, 0, 4, 4)
    var left = clip_half(square, Point2(1, 0), 1)
    assert_almost_equal(polygon_area(left), 4, atol=1e-12)
    assert_equal(len(clip_half(square, Point2(1, 0), -1)), 0)
    assert_equal(len(clip_half(square, Point2(1, 0), 9)), 4)
    assert_true(is_convex(square))
    var notch: List[Point2] = [
        Point2(0, 0),
        Point2(4, 0),
        Point2(4, 4),
        Point2(2, 1),
        Point2(0, 4),
    ]
    assert_false(is_convex(notch))
    var straight: List[Point2] = [
        Point2(0, 0),
        Point2(2, 0),
        Point2(4, 0),
        Point2(4, 4),
        Point2(0, 4),
    ]
    assert_true(is_convex(straight))
    assert_true(is_convex(List[Point2]()))
    var clockwise = square.copy()
    clockwise.reverse()
    assert_true(is_convex(clockwise))
    var smaller = inset(square, 1)
    assert_almost_equal(polygon_area(smaller), 4, atol=1e-12)
    assert_equal(len(inset(square, 3)), 0)


# --- floor plans ---------------------------------------------------------------


def test_an_office_floor_tiles_its_footprint() raises:
    var footprint = _rect(0, 0, 36, 20)
    var plan = plan_floor(footprint, OFFICE_FLOOR, 5, default_plan_options())
    assert_true(plan[0].use == CORRIDOR)
    var total = Float64(0)
    for i in range(len(plan)):
        assert_true(is_convex(plan[i].outline))
        total += abs(polygon_area(plan[i].outline))
    assert_almost_equal(total, 720, atol=1e-6)
    # Every room shares a wall with the corridor.
    var b = _one_storey(plan^)
    b.validate()
    for s in range(1, len(b.spaces)):
        var shared = b.topology.complex.shared_faces(
            b.spaces[s].cell, b.spaces[0].cell
        )
        assert_true(len(shared) > 0)
    # The same seed gives the same plan.
    var again = plan_floor(footprint, OFFICE_FLOOR, 5, default_plan_options())
    var first = plan_floor(footprint, OFFICE_FLOOR, 5, default_plan_options())
    assert_equal(len(again), len(first))
    assert_equal(again[3].outline[1].x, first[3].outline[1].x)


def test_a_short_floor_has_no_cuts_beside_its_core() raises:
    # 19 m long: the 12 m core leaves 3.5 m on each side, one room each.
    var plan = plan_floor(
        _rect(0, 0, 19, 12), OFFICE_FLOOR, 1, default_plan_options()
    )
    var b = _one_storey(plan^)
    b.validate()


def test_residential_and_lobby_floors() raises:
    var footprint = _rect(0, 0, 30, 18)
    var homes = plan_floor(
        footprint, RESIDENTIAL_FLOOR, 0, default_plan_options()
    )
    var kitchens = 0
    for i in range(len(homes)):
        if homes[i].use == KITCHEN:
            kitchens += 1
    assert_true(kitchens > 0)
    var lobby = plan_floor(footprint, LOBBY_FLOOR, 3, default_plan_options())
    assert_true(lobby[0].use == LOBBY)
    # The lobby is two and a half corridors wide.
    var width = Float64(0)
    for k in range(len(lobby[0].outline)):
        width = max(width, lobby[0].outline[k].y)
    assert_almost_equal(width, 9 + 2.25, atol=1e-9)


def test_plan_floor_refuses() raises:
    var footprint = _rect(0, 0, 36, 20)
    var options = default_plan_options()
    with assert_raises(contains="program"):
        _ = plan_floor(footprint, FloorProgram(3), 1, options)
    with assert_raises(contains="program"):
        _ = plan_floor(footprint, FloorProgram(-1), 1, options)
    var bad = options
    bad.corridor_width = _m(0)
    with assert_raises(contains="positive"):
        _ = plan_floor(footprint, OFFICE_FLOOR, 1, bad)
    var endless = options
    endless.core_length = _m(inf[DType.float64]())
    with assert_raises(contains="positive"):
        _ = plan_floor(footprint, OFFICE_FLOOR, 1, endless)
    var inverted = options
    inverted.max_room = _m(1)
    with assert_raises(contains="narrower"):
        _ = plan_floor(footprint, OFFICE_FLOOR, 1, inverted)
    with assert_raises(contains="three corners"):
        _ = plan_floor([Point2(0, 0), Point2(1, 0)], OFFICE_FLOOR, 1, options)
    with assert_raises(contains="three corners"):
        _ = plan_floor(
            [Point2(0, 0), Point2(1, 0), Point2(2, 0)], OFFICE_FLOOR, 1, options
        )
    var notch: List[Point2] = [
        Point2(0, 0),
        Point2(40, 0),
        Point2(40, 30),
        Point2(20, 5),
        Point2(0, 30),
    ]
    with assert_raises(contains="convex"):
        _ = plan_floor(notch, OFFICE_FLOOR, 1, options)
    with assert_raises(contains="narrow"):
        _ = plan_floor(_rect(0, 0, 36, 7), OFFICE_FLOOR, 1, options)
    with assert_raises(contains="short"):
        _ = plan_floor(_rect(0, 0, 16, 15), OFFICE_FLOOR, 1, options)


# --- doors and windows -----------------------------------------------------------


def test_every_room_gets_one_door() raises:
    var plan = plan_floor(
        _rect(0, 0, 36, 20), LOBBY_FLOOR, 4, default_plan_options()
    )
    var b = _one_storey(plan^)
    var doors = add_doors(b, _m(0.9), _m(2.1))
    # One door per room and an entrance for the lobby.
    assert_equal(doors, len(b.spaces))
    var per_space = List[Int]()
    for _ in range(len(b.spaces)):
        per_space.append(0)
    for o in range(len(b.openings)):
        assert_true(b.openings[o].kind == DOOR)
    with assert_raises(contains="size"):
        _ = add_doors(b, _m(0), _m(2.1))
    with assert_raises(contains="size"):
        _ = add_doors(b, _m(0.9), _m(inf[DType.float64]()))
    with assert_raises(contains="size"):
        _ = add_doors(b, _m(0.9), _m(0))
    with assert_raises(contains="size"):
        _ = add_doors(b, _m(inf[DType.float64]()), _m(2.1))


def test_a_room_with_no_corridor_opens_into_a_neighbor() raises:
    # A corridor; a front room on it; a room behind the front room; and a
    # slot whose corridor wall is too short, so it opens into a neighbor.
    var spaces = List[SpacePlan]()
    # The slot comes first, so the front room later finds the slot's door
    # in the wall they share.
    spaces.append(SpacePlan("corridor", CORRIDOR, _rect(0, 0, 10, 2)))
    spaces.append(SpacePlan("slot", OFFICE, _rect(3, 2, 3.5, 6)))
    spaces.append(SpacePlan("front", OFFICE, _rect(0, 2, 3, 6)))
    spaces.append(SpacePlan("side", OFFICE, _rect(3.5, 2, 10, 6)))
    spaces.append(SpacePlan("back", OFFICE, _rect(0, 6, 10, 10)))
    var b = _one_storey(spaces^)
    var doors = add_doors(b, _m(0.9), _m(2.1))
    assert_equal(doors, 4)
    # A door taller than the storey does not fit anywhere.
    var low = List[SpacePlan]()
    low.append(SpacePlan("corridor", CORRIDOR, _rect(0, 0, 10, 2)))
    low.append(SpacePlan("room", OFFICE, _rect(0, 2, 10, 6)))
    var c = _one_storey(low^)
    assert_equal(add_doors(c, _m(0.9), _m(5)), 0)


def test_doors_skip_what_they_cannot_use() raises:
    # A room alone has no neighbor. An empty storey has no rooms.
    var hut = _one_storey([SpacePlan("hut", OFFICE, _rect(0, 0, 4, 4))])
    assert_equal(add_doors(hut, _m(0.9), _m(2.1)), 0)
    var plans = List[StoreyPlan]()
    plans.append(StoreyPlan("g", _m(3), List[SpacePlan]()))
    var empty = _assemble(plans^)
    assert_equal(add_doors(empty, _m(0.9), _m(2.1)), 0)
    var g = double_glazing()
    assert_equal(
        add_windows(empty, WindowOptions(_m(2), _m(0.4), _m(0.9), _m(1.5), g)),
        0,
    )
    assert_equal(furnish(empty, 1), 0)
    # A lobby walled in by rooms has no outside wall, and a lobby whose
    # outside walls are short has no room for its entrance.
    var ring = List[SpacePlan]()
    ring.append(SpacePlan("lobby", LOBBY, _rect(2, 2, 4, 4)))
    ring.append(SpacePlan("s", OFFICE, _rect(0, 0, 6, 2)))
    ring.append(SpacePlan("n", OFFICE, _rect(0, 4, 6, 6)))
    ring.append(SpacePlan("w", OFFICE, _rect(0, 2, 2, 4)))
    ring.append(SpacePlan("e", OFFICE, _rect(4, 2, 6, 4)))
    var walled = _one_storey(ring^)
    assert_equal(add_doors(walled, _m(0.9), _m(2.1)), 4)
    var corner = List[SpacePlan]()
    corner.append(SpacePlan("lobby", LOBBY, _rect(0, 0, 1.5, 1.5)))
    var small = _one_storey(corner^)
    assert_equal(add_doors(small, _m(0.9), _m(2.1)), 0)
    # A wall with no element is no door wall.
    var spaces = List[SpacePlan]()
    spaces.append(SpacePlan("corridor", CORRIDOR, _rect(0, 0, 10, 2)))
    spaces.append(SpacePlan("front", OFFICE, _rect(0, 2, 10, 6)))
    spaces.append(SpacePlan("back", OFFICE, _rect(0, 6, 10, 10)))
    var b = _one_storey(spaces^)
    for f in range(len(b.face_element)):
        var element = b.face_element[f]
        if b.elements[element].kind == WALL and not b.is_exterior(
            ElementId(element)
        ):
            b.face_element[f] = -1
    assert_equal(add_doors(b, _m(0.9), _m(2.1)), 0)


def test_windows_fill_outside_walls_by_bay() raises:
    var spaces = List[SpacePlan]()
    spaces.append(SpacePlan("corridor", CORRIDOR, _rect(0, 0, 10, 2)))
    spaces.append(SpacePlan("room", OFFICE, _rect(0, 2, 10, 6)))
    spaces.append(SpacePlan("sliver", OFFICE, _rect(10, 0, 10.6, 6)))
    var b = _one_storey(spaces^)
    _ = add_doors(b, _m(0.9), _m(2.1))
    var options = WindowOptions(
        _m(2.5), _m(0.4), _m(0.9), _m(1.5), double_glazing()
    )
    var windows = add_windows(b, options)
    assert_true(windows > 0)
    # No window crosses a door, and none is in an inside wall.
    for o in range(len(b.openings)):
        if b.openings[o].kind == WINDOW:
            assert_true(b.is_exterior(b.openings[o].host))
    # A lobby with an entrance in a long outside wall keeps its windows
    # clear of the door.
    var hall = _one_storey([SpacePlan("lobby", LOBBY, _rect(0, 0, 12, 3))])
    _ = add_doors(hall, _m(0.9), _m(2.1))
    var hall_windows = add_windows(hall, options)
    assert_true(hall_windows > 4)
    with assert_raises(contains="sill"):
        WindowOptions(
            _m(2), _m(0.4), _m(inf[DType.float64]()), _m(1.5), double_glazing()
        ).check()
    # A window row taller than the wall cuts nothing.
    var tall = WindowOptions(_m(2.5), _m(0.4), _m(0.9), _m(3), double_glazing())
    var c = _one_storey([SpacePlan("room", OFFICE, _rect(0, 0, 6, 4))])
    assert_equal(add_windows(c, tall), 0)


def test_window_options_refuse() raises:
    var g = double_glazing()
    with assert_raises(contains="positive"):
        WindowOptions(_m(0), _m(0.4), _m(0.9), _m(1.5), g).check()
    with assert_raises(contains="positive"):
        WindowOptions(_m(2), _m(0), _m(0.9), _m(1.5), g).check()
    with assert_raises(contains="positive"):
        WindowOptions(_m(2), _m(0.4), _m(0.9), _m(0), g).check()
    with assert_raises(contains="positive"):
        WindowOptions(
            _m(inf[DType.float64]()), _m(0.4), _m(0.9), _m(1.5), g
        ).check()
    with assert_raises(contains="sill"):
        WindowOptions(_m(2), _m(0.4), _m(-1), _m(1.5), g).check()
    with assert_raises(contains="sill"):
        WindowOptions(
            _m(2), _m(0.4), _m(nan[DType.float64]()), _m(1.5), g
        ).check()
    with assert_raises(contains="pier"):
        WindowOptions(_m(2), _m(2), _m(0.9), _m(1.5), g).check()
    with assert_raises(contains="solar"):
        WindowOptions(
            _m(2), _m(0.4), _m(0.9), _m(1.5), Glazing(g.u_value, 3, 0.5)
        ).check()


# --- furniture -------------------------------------------------------------------


def test_furniture_stands_inside_rooms_without_overlap() raises:
    var plan = plan_floor(
        _rect(0, 0, 36, 20), RESIDENTIAL_FLOOR, 2, default_plan_options()
    )
    var b = _one_storey(plan^)
    _ = add_doors(b, _m(0.9), _m(2.1))
    _ = add_windows(
        b, WindowOptions(_m(2.6), _m(0.5), _m(0.9), _m(1.6), double_glazing())
    )
    var placed = furnish(b, 9)
    assert_equal(placed, len(b.furnishings))
    assert_true(placed > 10)
    b.validate()
    var beds = 0
    for i in range(len(b.furnishings)):
        if b.furnishings[i].kind == BED:
            beds += 1
    assert_true(beds > 0)
    # The same seed gives the same furniture.
    var plan2 = plan_floor(
        _rect(0, 0, 36, 20), RESIDENTIAL_FLOOR, 2, default_plan_options()
    )
    var c = _one_storey(plan2^)
    _ = add_doors(c, _m(0.9), _m(2.1))
    _ = add_windows(
        c, WindowOptions(_m(2.6), _m(0.5), _m(0.9), _m(1.6), double_glazing())
    )
    _ = furnish(c, 9)
    assert_equal(fingerprint(b), fingerprint(c))


def test_furniture_in_bare_rooms() raises:
    # No doors and no windows; one outline runs clockwise; one office is too
    # shallow for a desk's chair.
    var spaces = List[SpacePlan]()
    spaces.append(SpacePlan("office", OFFICE, _rect(0, 0, 5, 4)))
    var clockwise = _rect(5, 0, 9, 4)
    clockwise.reverse()
    spaces.append(SpacePlan("bedroom", BEDROOM, clockwise^))
    spaces.append(SpacePlan("shallow", OFFICE, _rect(0, 4, 5, 5.2)))
    var b = _one_storey(spaces^)
    var placed = furnish(b, 4)
    assert_true(placed > 3)
    b.validate()
    var shallow_chairs = 0
    for i in range(len(b.furnishings)):
        if (
            b.furnishings[i].space == SpaceId(2)
            and b.furnishings[i].kind == CHAIR
        ):
            shallow_chairs += 1
    assert_equal(shallow_chairs, 0)


def test_a_tiny_room_gets_no_furniture() raises:
    var spaces = List[SpacePlan]()
    spaces.append(SpacePlan("cupboard", OFFICE, _rect(0, 0, 0.8, 0.8)))
    var b = _one_storey(spaces^)
    assert_equal(furnish(b, 1), 0)


def test_add_furnishing_checks_its_place() raises:
    var b = _one_storey([SpacePlan("room", OFFICE, _rect(0, 0, 4, 4))])
    var desk = b.add_furnishing(
        DESK, SpaceId(0), Point2(1, 1), Angle64(0), _m(1.4), _m(0.7), _m(0.75)
    )
    b.check_furnishing(desk)
    var corners = b.furnishings[0].corners()
    assert_almost_equal(corners[0].x, 0.3, atol=1e-12)
    assert_almost_equal(corners[2].y, 1.35, atol=1e-12)
    # A turned shelf against the far wall.
    _ = b.add_furnishing(
        SHELF,
        SpaceId(0),
        Point2(3.8, 2),
        Angle64(90, DEGREE64),
        _m(1),
        _m(0.4),
        _m(1.8),
    )
    with assert_raises(contains="kind"):
        _ = b.add_furnishing(
            FurnitureKind(20),
            SpaceId(0),
            Point2(2, 3),
            Angle64(0),
            _m(1),
            _m(1),
            _m(1),
        )
    with assert_raises(contains="space id"):
        _ = b.add_furnishing(
            DESK, SpaceId(5), Point2(2, 3), Angle64(0), _m(1), _m(1), _m(1)
        )
    with assert_raises(contains="size"):
        _ = b.add_furnishing(
            DESK, SpaceId(0), Point2(2, 3), Angle64(0), _m(0), _m(1), _m(1)
        )
    with assert_raises(contains="size"):
        _ = b.add_furnishing(
            DESK,
            SpaceId(0),
            Point2(2, 3),
            Angle64(0),
            _m(1),
            _m(inf[DType.float64]()),
            _m(1),
        )
    with assert_raises(contains="place"):
        _ = b.add_furnishing(
            DESK,
            SpaceId(0),
            Point2(nan[DType.float64](), 3),
            Angle64(0),
            _m(1),
            _m(1),
            _m(1),
        )
    with assert_raises(contains="place"):
        _ = b.add_furnishing(
            DESK,
            SpaceId(0),
            Point2(2, inf[DType.float64]()),
            Angle64(0),
            _m(1),
            _m(1),
            _m(1),
        )
    with assert_raises(contains="place"):
        _ = b.add_furnishing(
            DESK,
            SpaceId(0),
            Point2(2, 3),
            Angle64(nan[DType.float64]()),
            _m(1),
            _m(1),
            _m(1),
        )
    with assert_raises(contains="inside"):
        _ = b.add_furnishing(
            DESK, SpaceId(0), Point2(3.9, 3.9), Angle64(0), _m(1), _m(1), _m(1)
        )
    with assert_raises(contains="overlap"):
        _ = b.add_furnishing(
            DESK, SpaceId(0), Point2(1.2, 1.2), Angle64(0), _m(1), _m(1), _m(1)
        )
    with assert_raises(contains="furnishing id"):
        b.check_furnishing(FurnishingId(9))
    with assert_raises(contains="furnishing id"):
        b.check_furnishing(FurnishingId(-1))
    assert_false(FurnishingId(-1).is_valid())
    assert_equal(FurnitureKind(99).name(), "unknown")
    assert_equal(BED.name(), "bed")
    b.furnishings[0].kind = FurnitureKind(77)
    with assert_raises(contains="kind"):
        b.validate()
    b.furnishings[0].kind = DESK
    b.furnishings[0].space = SpaceId(8)
    with assert_raises(contains="space id"):
        b.validate()


def test_quads_apart() raises:
    var a = _rect(0, 0, 1, 1)
    var touching = _rect(1, 0, 2, 1)
    var overlapping = _rect(0.5, 0.5, 1.5, 1.5)
    assert_true(quads_apart(a, touching))
    assert_false(quads_apart(a, overlapping))
    # Apart only along the second shape's own axis: the boxes' x and y
    # ranges overlap, but x + y separates them.
    var diamond: List[Point2] = [
        Point2(1.5, 1.0),
        Point2(2.0, 1.5),
        Point2(1.5, 2.0),
        Point2(1.0, 1.5),
    ]
    var corner = _rect(0, 0, 1.2, 1.2)
    assert_true(quads_apart(corner, diamond))


# --- towers --------------------------------------------------------------------


def _small(seed: Int, height: Float32) -> SkyscraperParameters:
    var p = SkyscraperParameters()
    p.seed = seed
    p.total_height = Length(height, METER)
    return p^


def test_a_small_tower_is_a_full_building() raises:
    var b = generate_tower(TowerOptions(_small(35, 16)))
    b.validate()
    assert_equal(len(b.storeys), 4)
    assert_true(b.spaces[0].use == LOBBY)
    var doors = 0
    var windows = 0
    for o in range(len(b.openings)):
        if b.openings[o].kind == DOOR:
            doors += 1
        else:
            windows += 1
    assert_true(windows > 100)
    var halls = 0
    for s in range(len(b.spaces)):
        if b.spaces[s].use == CORRIDOR or b.spaces[s].use == LOBBY:
            halls += 1
    # Every room has a door, and the lobby has an entrance.
    assert_equal(doors, len(b.spaces) - halls + 1)
    var columns = 0
    for e in range(len(b.elements)):
        if b.elements[e].kind == COLUMN:
            columns += 1
    assert_true(columns > 0)
    assert_true(len(b.furnishings) > 100)
    # The same seed gives the same tower.
    var again = generate_tower(TowerOptions(_small(35, 16)))
    assert_equal(fingerprint(again), fingerprint(b))


def test_tower_options_change_the_building() raises:
    var options = TowerOptions(_small(7, 12))
    options.shaft = RESIDENTIAL_FLOOR
    options.furnished = False
    options.frame = False
    var b = generate_tower(options)
    b.validate()
    assert_equal(len(b.furnishings), 0)
    for e in range(len(b.elements)):
        assert_true(b.elements[e].kind != COLUMN)
    # A narrow tower's crown is too small to set back, so it keeps the
    # shaft's footprint.
    var narrow = _small(3, 40)
    narrow.footprint_width = Length(26, METER)
    narrow.footprint_depth = Length(12, METER)
    narrow.setback_depth = 2
    var thin = generate_tower(TowerOptions(narrow^))
    thin.validate()
    var bad = _small(3, 40)
    bad.chamfer_corner_x = 5
    with assert_raises(contains="chamfer"):
        _ = generate_tower(TowerOptions(bad^))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
