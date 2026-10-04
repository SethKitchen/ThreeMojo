# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.building`: materials, constructions, sections and
the assembled model.

The references are closed forms: the ISO 6946 sum of resistances, the
section properties of a rectangle, an I and a circle, and the areas and
volumes of boxes.
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
    DOWNWARD_FLOW,
    FlowDirection,
    Glazing,
    HORIZONTAL_FLOW,
    Layer,
    UPWARD_FLOW,
    double_glazing,
    inside_film,
    outside_film,
)
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    OpeningId,
    SpaceId,
    StoreyId,
)
from extensions.building.kinds import (
    BEAM,
    CIRCLE,
    COLUMN,
    CORRIDOR,
    DOOR,
    ElementKind,
    I_SHAPE,
    OFFICE,
    OpeningKind,
    RECTANGLE,
    ROOF,
    SLAB,
    SectionShape,
    SpaceUse,
    WALL,
    WINDOW,
)
from extensions.building.material import (
    BuildingMaterial,
    Look,
    aluminum,
    brick,
    concrete,
    glass,
    gypsum_board,
    mineral_wool,
    steel,
    timber,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Section,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    i_shape,
    rectangle,
)
from extensions.topology.arrangement import Point2, Region
from extensions.topology.storeys import build_storeys
from extensions.topology.ids import FaceId
from units.si import (
    Angle64,
    DEGREE,
    GIGAPASCAL,
    JOULE_PER_KELVIN,
    Length64,
    METER,
    MILLIMETER,
    SQUARE_METER,
    WATT_PER_SQUARE_METER_KELVIN,
    CUBIC_METER,
    METER_TO_THE_FOURTH,
    SQUARE_METER_KELVIN_PER_WATT,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _site() -> Site:
    return Site(
        Angle64(40, DEGREE), Angle64(-105, DEGREE), _m(1600), Angle64(0)
    )


def _library() -> List[BuildingMaterial]:
    var out = List[BuildingMaterial]()
    out.append(brick())
    out.append(mineral_wool())
    out.append(gypsum_board())
    out.append(concrete())
    out.append(steel())
    return out^


def _constructions() -> List[Construction]:
    var out = List[Construction]()
    out.append(
        Construction(
            "exterior wall",
            [
                Layer(MaterialId(0), _m(0.2)),
                Layer(MaterialId(1), _m(0.1)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    out.append(
        Construction(
            "partition",
            [
                Layer(MaterialId(2), _m(0.0125)),
                Layer(MaterialId(1), _m(0.05)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    out.append(Construction("slab", [Layer(MaterialId(3), _m(0.2))]))
    return out^


def _defaults() -> ConstructionSet:
    return ConstructionSet(
        ConstructionId(0),
        ConstructionId(1),
        ConstructionId(2),
        ConstructionId(2),
        ConstructionId(2),
    )


def _rect(x0: Float64, y0: Float64, x1: Float64, y1: Float64) -> List[Point2]:
    return [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]


def _two_storeys() raises -> Building:
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("office A", OFFICE, _rect(0, 0, 6, 5)))
    ground.append(SpacePlan("corridor", CORRIDOR, _rect(6, 0, 8, 5)))
    plans.append(StoreyPlan("ground", _m(3.5), ground^))
    var first = List[SpacePlan]()
    first.append(SpacePlan("office B", OFFICE, _rect(0, 0, 8, 5)))
    plans.append(StoreyPlan("first", _m(3), first^))
    return assemble(
        "test",
        _site(),
        _m(0),
        plans,
        _library(),
        _constructions(),
        _defaults(),
        Length64(1e-6, METER),
    )


# --- kinds and ids -----------------------------------------------------------


def test_kinds_are_valid_and_named() raises:
    assert_true(WALL.is_valid())
    assert_equal(BEAM.name(), "beam")
    assert_false(ElementKind(5).is_valid())
    assert_equal(ElementKind(-1).name(), "unknown")
    assert_equal(WINDOW.name(), "window")
    assert_false(OpeningKind(2).is_valid())
    assert_equal(CORRIDOR.name(), "corridor")
    assert_false(SpaceUse(12).is_valid())
    assert_equal(I_SHAPE.name(), "i_shape")
    assert_equal(OpeningKind(9).name(), "unknown")
    assert_equal(SpaceUse(-3).name(), "unknown")
    assert_equal(SectionShape(4).name(), "unknown")
    assert_false(SectionShape(3).is_valid())
    assert_true(StoreyId(0).is_valid())
    assert_false(StoreyId(-1).is_valid())
    assert_false(SpaceId(-1).is_valid())
    assert_false(ElementId(-1).is_valid())
    assert_false(OpeningId(-1).is_valid())
    assert_false(MaterialId(-1).is_valid())
    assert_false(ConstructionId(-1).is_valid())
    assert_true(HORIZONTAL_FLOW.is_valid())
    assert_false(FlowDirection(3).is_valid())
    assert_false(FlowDirection(-1).is_valid())


# --- materials ---------------------------------------------------------------


def test_library_materials_are_valid() raises:
    var all = _library()
    all.append(timber())
    all.append(glass())
    all.append(aluminum())
    for i in range(len(all)):
        all[i].check()
    var s = steel()
    assert_almost_equal(s.shear_modulus().to(GIGAPASCAL), 200 / 2.6, atol=1e-9)


def test_material_check_refuses() raises:
    var m = steel()
    m.density = m.density.scaled(-1)
    with assert_raises(contains="positive"):
        m.check()
    var n = steel()
    n.conductivity = n.conductivity.scaled(inf[DType.float64]())
    with assert_raises(contains="positive"):
        n.check()
    var p = steel()
    p.poisson_ratio = 0.5
    with assert_raises(contains="Poisson"):
        p.check()
    var q = steel()
    q.poisson_ratio = -0.1
    with assert_raises(contains="Poisson"):
        q.check()
    var r = steel()
    r.strength = r.strength.scaled(-1)
    with assert_raises(contains="strength"):
        r.check()
    var t = steel()
    t.thermal_expansion = t.thermal_expansion.scaled(nan[DType.float64]())
    with assert_raises(contains="strength"):
        t.check()
    var w = steel()
    w.thermal_expansion = w.thermal_expansion.scaled(inf[DType.float64]())
    with assert_raises(contains="strength"):
        w.check()
    var u = steel()
    u.look = Look(1.5, 0, 0, 0, 0, 0)
    with assert_raises(contains="look"):
        u.check()
    var v = steel()
    v.look = Look(0, 0, 0, 0, 0, -0.5)
    with assert_raises(contains="look"):
        v.check()


# --- constructions -----------------------------------------------------------


def test_iso_6946_u_value() raises:
    var materials = _library()
    var wall = _constructions()[0].copy()
    var r = 0.2 / 0.77 + 0.1 / 0.035 + 0.0125 / 0.25
    assert_almost_equal(
        wall.resistance(materials).to(SQUARE_METER_KELVIN_PER_WATT),
        r,
        atol=1e-12,
    )
    var u = wall.u_value(materials, HORIZONTAL_FLOW)
    assert_almost_equal(
        u.to(WATT_PER_SQUARE_METER_KELVIN), 1 / (0.13 + r + 0.04), atol=1e-12
    )
    var up = wall.u_value(materials, UPWARD_FLOW)
    assert_almost_equal(
        up.to(WATT_PER_SQUARE_METER_KELVIN), 1 / (0.10 + r + 0.04), atol=1e-12
    )
    var down = wall.u_value(materials, DOWNWARD_FLOW)
    assert_almost_equal(
        down.to(WATT_PER_SQUARE_METER_KELVIN),
        1 / (0.17 + r + 0.04),
        atol=1e-12,
    )
    assert_almost_equal(wall.thickness().to(METER), 0.3125, atol=1e-15)
    # Heat capacity: rho c t for each layer.
    var c = 1800 * 840 * 0.2 + 30 * 1030 * 0.1 + 800 * 1000 * 0.0125
    assert_almost_equal(
        wall.heat_capacity_per_area(materials).to(JOULE_PER_KELVIN),
        c,
        atol=1e-6,
    )
    assert_almost_equal(
        outside_film().to(SQUARE_METER_KELVIN_PER_WATT), 0.04, atol=1e-15
    )


def test_construction_check_refuses() raises:
    var materials = _library()
    var empty = Construction("empty", List[Layer]())
    with assert_raises(contains="needs a layer"):
        empty.check(materials)
    var missing = Construction("missing", [Layer(MaterialId(9), _m(0.1))])
    with assert_raises(contains="out of range"):
        missing.check(materials)
    var negative_id = Construction("neg", [Layer(MaterialId(-1), _m(0.1))])
    with assert_raises(contains="out of range"):
        negative_id.check(materials)
    var thin = Construction("thin", [Layer(MaterialId(0), _m(0))])
    with assert_raises(contains="positive"):
        thin.check(materials)
    var huge = Construction(
        "huge", [Layer(MaterialId(0), _m(inf[DType.float64]()))]
    )
    with assert_raises(contains="positive"):
        huge.check(materials)
    with assert_raises(contains="flow direction"):
        _ = inside_film(FlowDirection(7))
    with assert_raises(contains="flow direction"):
        _ = _constructions()[0].u_value(materials, FlowDirection(7))
    with assert_raises(contains="needs a layer"):
        _ = empty.heat_capacity_per_area(materials)
    assert_equal(empty.thickness().value, 0)


def test_glazing() raises:
    var g = double_glazing()
    g.check()
    var bad_u = Glazing(g.u_value.scaled(0), 0.4, 0.7)
    with assert_raises(contains="U-value"):
        bad_u.check()
    var inf_u = Glazing(g.u_value.scaled(inf[DType.float64]()), 0.4, 0.7)
    with assert_raises(contains="U-value"):
        inf_u.check()
    with assert_raises(contains="solar"):
        Glazing(g.u_value, 1.2, 0.7).check()
    with assert_raises(contains="solar"):
        Glazing(g.u_value, -0.1, 0.7).check()
    with assert_raises(contains="visible"):
        Glazing(g.u_value, 0.4, 1.5).check()
    with assert_raises(contains="visible"):
        Glazing(g.u_value, 0.4, -1).check()


# --- sections ----------------------------------------------------------------


def test_section_properties() raises:
    var r = rectangle(_m(0.3), _m(0.5))
    r.check()
    assert_almost_equal(r.area().to(SQUARE_METER), 0.15, atol=1e-15)
    assert_almost_equal(
        r.strong_inertia().to(METER_TO_THE_FOURTH), 0.3 * 0.125 / 12, atol=1e-15
    )
    assert_almost_equal(
        r.weak_inertia().to(METER_TO_THE_FOURTH), 0.5 * 0.027 / 12, atol=1e-15
    )
    # A square: J = 0.1406 a^4 exactly; the series is within 0.2%.
    var sq = rectangle(_m(1), _m(1))
    assert_almost_equal(
        sq.torsion_constant().to(METER_TO_THE_FOURTH), 0.1406, atol=3e-4
    )
    var tall = rectangle(_m(1), _m(4))
    var wide = rectangle(_m(4), _m(1))
    assert_almost_equal(
        tall.torsion_constant().value, wide.torsion_constant().value, atol=1e-15
    )
    var c = Section(CIRCLE, _m(0.4), _m(0), _m(0), _m(0))
    c.check()
    assert_almost_equal(c.area().value, pi * 0.04, atol=1e-15)
    assert_almost_equal(c.strong_inertia().value, pi * 0.0256 / 64, atol=1e-15)
    assert_almost_equal(c.weak_inertia().value, pi * 0.0256 / 64, atol=1e-15)
    assert_almost_equal(
        c.torsion_constant().value, pi * 0.0256 / 32, atol=1e-15
    )
    # A W-shape-like I: 0.2 wide, 0.4 deep, 0.015 flanges, 0.01 web.
    var i = i_shape(_m(0.2), _m(0.4), _m(0.015), _m(0.01))
    i.check()
    var area = 2 * 0.2 * 0.015 + 0.37 * 0.01
    assert_almost_equal(i.area().value, area, atol=1e-15)
    var strong = (0.2 * 0.064 - 0.19 * 0.37 * 0.37 * 0.37) / 12
    assert_almost_equal(i.strong_inertia().value, strong, atol=1e-15)
    var weak = (2 * 0.015 * 0.008 + 0.37 * 1e-6) / 12
    assert_almost_equal(i.weak_inertia().value, weak, atol=1e-15)
    var j = (2 * 0.2 * 0.015**3 + 0.37 * 0.01**3) / 3
    assert_almost_equal(i.torsion_constant().value, j, atol=1e-15)


def test_section_check_refuses() raises:
    with assert_raises(contains="shape"):
        Section(SectionShape(9), _m(1), _m(1), _m(0), _m(0)).check()
    with assert_raises(contains="width"):
        rectangle(_m(0), _m(1)).check()
    with assert_raises(contains="width"):
        rectangle(_m(inf[DType.float64]()), _m(1)).check()
    with assert_raises(contains="depth"):
        rectangle(_m(1), _m(-1)).check()
    with assert_raises(contains="depth"):
        rectangle(_m(1), _m(nan[DType.float64]())).check()
    with assert_raises(contains="depth"):
        rectangle(_m(1), _m(inf[DType.float64]())).check()
    with assert_raises(contains="fit"):
        i_shape(_m(0.2), _m(0.4), _m(0), _m(0.01)).check()
    with assert_raises(contains="fit"):
        i_shape(_m(0.2), _m(0.4), _m(0.2), _m(0.01)).check()
    with assert_raises(contains="fit"):
        i_shape(_m(0.2), _m(0.4), _m(0.01), _m(0)).check()
    with assert_raises(contains="fit"):
        i_shape(_m(0.2), _m(0.4), _m(0.01), _m(0.2)).check()


# --- site --------------------------------------------------------------------


def test_site_check_refuses() raises:
    _site().check()
    var s = _site()
    s.latitude = Angle64(91, DEGREE)
    with assert_raises(contains="latitude"):
        s.check()
    s.latitude = Angle64(-91, DEGREE)
    with assert_raises(contains="latitude"):
        s.check()
    var t = _site()
    t.longitude = Angle64(181, DEGREE)
    with assert_raises(contains="longitude"):
        t.check()
    t.longitude = Angle64(-181, DEGREE)
    with assert_raises(contains="longitude"):
        t.check()
    var u = _site()
    u.elevation = _m(inf[DType.float64]())
    with assert_raises(contains="finite"):
        u.check()
    var v = _site()
    v.north = Angle64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        v.check()


# --- the assembled model -----------------------------------------------------


def test_assemble_two_storeys() raises:
    var b = _two_storeys()
    b.validate()
    assert_equal(len(b.storeys), 2)
    assert_equal(len(b.spaces), 3)
    assert_equal(b.storeys[1].elevation.to(METER), 3.5)
    var walls = 0
    var exterior_walls = 0
    var slabs = 0
    var roofs = 0
    for i in range(len(b.elements)):
        var kind = b.elements[i].kind
        if kind == WALL:
            walls += 1
            if b.is_exterior(ElementId(i)):
                exterior_walls += 1
        elif kind == SLAB:
            slabs += 1
        elif kind == ROOF:
            roofs += 1
    # Ground: 6 outside walls (two rooms) and 1 partition. First: 4.
    assert_equal(walls, 11)
    assert_equal(exterior_walls, 10)
    # Two ground slabs and two floors under office B; one roof.
    assert_equal(slabs, 4)
    assert_equal(roofs, 1)
    assert_almost_equal(
        b.floor_area(SpaceId(0)).to(SQUARE_METER), 30, atol=1e-9
    )
    assert_almost_equal(
        b.floor_area(SpaceId(2)).to(SQUARE_METER), 40, atol=1e-9
    )
    assert_almost_equal(b.volume(SpaceId(2)).to(CUBIC_METER), 120, atol=1e-9)
    assert_almost_equal(b.gross_floor_area().to(SQUARE_METER), 80, atol=1e-9)
    var n = b.space_neighbors(SpaceId(0))
    assert_equal(len(n), 2)
    var bounding = b.elements_of_space(SpaceId(0))
    assert_equal(len(bounding), 6)
    assert_equal(b.spaces[1].name, "corridor")
    assert_true(b.spaces[2].storey == StoreyId(1))


def test_wall_frames_and_openings() raises:
    var b = _two_storeys()
    # The first exterior wall of the first storey.
    var wall = ElementId(-1)
    for i in range(len(b.elements)):
        if (
            b.elements[i].kind == WALL
            and b.elements[i].storey == StoreyId(1)
            and wall.value < 0
        ):
            wall = ElementId(i)
    var frame = b.wall_frame(wall)
    assert_almost_equal(frame.height, 3, atol=1e-12)
    assert_true(frame.length == 8 or frame.length == 5)
    var p = frame.point(frame.length, frame.height, 0)
    assert_almost_equal(p.z, 6.5, atol=1e-12)
    var window = b.add_opening(
        WINDOW, wall, _m(1), _m(0.9), _m(1.5), _m(1.5), double_glazing()
    )
    var door = b.add_opening(DOOR, wall, _m(3), _m(0), _m(1), _m(2.1), None)
    assert_equal(b.openings_of(wall)[1].value, door.value)
    assert_equal(b.openings[window.value].name, "window 0")
    b.check_opening(window)
    assert_equal(len(b.openings_of(ElementId(0))), 0)
    b.validate()


def test_add_opening_refuses() raises:
    var b = _two_storeys()
    var wall = ElementId(0)
    while b.elements[wall.value].kind != WALL:
        wall = ElementId(wall.value + 1)
    var g = Optional(double_glazing())
    with assert_raises(contains="kind"):
        _ = b.add_opening(OpeningKind(4), wall, _m(1), _m(1), _m(1), _m(1), g)
    var slab = ElementId(0)
    while b.elements[slab.value].kind == WALL:
        slab = ElementId(slab.value + 1)
    with assert_raises(contains="not a wall"):
        _ = b.add_opening(WINDOW, slab, _m(1), _m(1), _m(1), _m(1), g)
    with assert_raises(contains="out of range"):
        _ = b.add_opening(WINDOW, ElementId(999), _m(1), _m(1), _m(1), _m(1), g)
    with assert_raises(contains="size"):
        _ = b.add_opening(WINDOW, wall, _m(1), _m(1), _m(0), _m(1), g)
    with assert_raises(contains="size"):
        _ = b.add_opening(WINDOW, wall, _m(1), _m(1), _m(1), _m(-1), g)
    with assert_raises(contains="size"):
        _ = b.add_opening(
            WINDOW, wall, _m(1), _m(1), _m(inf[DType.float64]()), _m(1), g
        )
    with assert_raises(contains="size"):
        _ = b.add_opening(
            WINDOW, wall, _m(1), _m(1), _m(1), _m(inf[DType.float64]()), g
        )
    with assert_raises(contains="inside"):
        _ = b.add_opening(WINDOW, wall, _m(-1), _m(1), _m(1), _m(1), g)
    with assert_raises(contains="inside"):
        _ = b.add_opening(WINDOW, wall, _m(1), _m(-1), _m(1), _m(1), g)
    with assert_raises(contains="inside"):
        _ = b.add_opening(WINDOW, wall, _m(1), _m(1), _m(99), _m(1), g)
    with assert_raises(contains="inside"):
        _ = b.add_opening(WINDOW, wall, _m(1), _m(1), _m(1), _m(99), g)
    with assert_raises(contains="floor"):
        _ = b.add_opening(DOOR, wall, _m(1), _m(0.1), _m(1), _m(2), None)
    with assert_raises(contains="glazing"):
        _ = b.add_opening(WINDOW, wall, _m(1), _m(1), _m(1), _m(1), None)
    var bad = Glazing(double_glazing().u_value, 2, 0.5)
    with assert_raises(contains="solar"):
        _ = b.add_opening(WINDOW, wall, _m(1), _m(1), _m(1), _m(1), bad)
    _ = b.add_opening(WINDOW, wall, _m(1), _m(1), _m(1), _m(1), g)
    # Overlaps from each side, and neighbors that only touch.
    with assert_raises(contains="overlap"):
        _ = b.add_opening(WINDOW, wall, _m(1.5), _m(1.5), _m(1), _m(1), g)
    with assert_raises(contains="overlap"):
        _ = b.add_opening(WINDOW, wall, _m(0.5), _m(0.5), _m(1), _m(1), g)
    _ = b.add_opening(WINDOW, wall, _m(2), _m(1), _m(0.5), _m(1), g)
    _ = b.add_opening(WINDOW, wall, _m(0), _m(1), _m(1), _m(0.5), g)
    _ = b.add_opening(WINDOW, wall, _m(1), _m(2), _m(1), _m(0.5), g)
    _ = b.add_opening(WINDOW, wall, _m(1), _m(0.2), _m(1), _m(0.8), g)
    # An opening in another wall does not overlap these.
    var other = ElementId(wall.value + 1)
    while b.elements[other.value].kind != WALL:
        other = ElementId(other.value + 1)
    _ = b.add_opening(WINDOW, other, _m(1), _m(1), _m(1), _m(1), g)


def test_columns_and_beams() raises:
    var b = _two_storeys()
    var section = i_shape(_m(0.2), _m(0.3), _m(0.012), _m(0.008))
    var column = b.add_column(
        StoreyId(1), Point2(4, 2.5), section, MaterialId(4)
    )
    ref c = b.elements[column.value]
    assert_true(c.kind == COLUMN)
    assert_equal(c.start.z, 3.5)
    assert_equal(c.end.z, 6.5)
    assert_false(b.is_exterior(column))
    var beam = b.add_beam(
        StoreyId(0), Point2(0, 2.5), Point2(8, 2.5), section, MaterialId(4)
    )
    assert_equal(b.elements[beam.value].start.z, 3.5)
    assert_true(b.elements[beam.value].kind == BEAM)
    b.validate()
    with assert_raises(contains="storey id"):
        _ = b.add_column(StoreyId(5), Point2(0, 0), section, MaterialId(4))
    with assert_raises(contains="material id"):
        _ = b.add_column(StoreyId(0), Point2(0, 0), section, MaterialId(40))
    with assert_raises(contains="width"):
        _ = b.add_column(
            StoreyId(0), Point2(0, 0), rectangle(_m(0), _m(1)), MaterialId(4)
        )
    with assert_raises(contains="finite"):
        _ = b.add_column(
            StoreyId(0), Point2(inf[DType.float64](), 0), section, MaterialId(4)
        )
    with assert_raises(contains="finite"):
        _ = b.add_column(
            StoreyId(0), Point2(0, nan[DType.float64]()), section, MaterialId(4)
        )
    with assert_raises(contains="storey id"):
        _ = b.add_beam(
            StoreyId(-1), Point2(0, 0), Point2(1, 0), section, MaterialId(4)
        )
    with assert_raises(contains="material id"):
        _ = b.add_beam(
            StoreyId(0), Point2(0, 0), Point2(1, 0), section, MaterialId(-4)
        )
    with assert_raises(contains="width"):
        _ = b.add_beam(
            StoreyId(0),
            Point2(0, 0),
            Point2(1, 0),
            rectangle(_m(0), _m(1)),
            MaterialId(4),
        )
    var bad_ends: List[Point2] = [
        Point2(inf[DType.float64](), 0),
        Point2(0, inf[DType.float64]()),
        Point2(nan[DType.float64](), 0),
        Point2(0, nan[DType.float64]()),
    ]
    for i in range(4):
        var start = bad_ends[i] if i < 2 else Point2(0, 0)
        var end = bad_ends[i] if i >= 2 else Point2(1, 0)
        with assert_raises(contains="finite"):
            _ = b.add_beam(StoreyId(0), start, end, section, MaterialId(4))
    with assert_raises(contains="differ"):
        _ = b.add_beam(
            StoreyId(0), Point2(1, 1), Point2(1, 1), section, MaterialId(4)
        )


def test_model_checks_refuse_ids() raises:
    var b = _two_storeys()
    with assert_raises(contains="storey id"):
        b.check_storey(StoreyId(2))
    with assert_raises(contains="space id"):
        b.check_space(SpaceId(3))
    with assert_raises(contains="space id"):
        b.check_space(SpaceId(-1))
    with assert_raises(contains="element id"):
        b.check_element(ElementId(-1))
    with assert_raises(contains="opening id"):
        b.check_opening(OpeningId(0))
    assert_equal(len(b.openings_of(ElementId(0))), 0)
    with assert_raises(contains="opening id"):
        b.check_opening(OpeningId(-1))
    with assert_raises(contains="material id"):
        b.check_material(MaterialId(99))
    with assert_raises(contains="construction id"):
        b.check_construction(ConstructionId(3))
    with assert_raises(contains="construction id"):
        b.check_construction(ConstructionId(-1))
    with assert_raises(contains="face id"):
        _ = b.element_of_face(FaceId(9999))
    with assert_raises(contains="face id"):
        _ = b.element_of_face(FaceId(-1))
    var slab = ElementId(0)
    while b.elements[slab.value].kind == WALL:
        slab = ElementId(slab.value + 1)
    with assert_raises(contains="not a wall"):
        _ = b.wall_frame(slab)


def test_validate_refuses_bad_parts() raises:
    var b = _two_storeys()
    b.spaces[0].use = SpaceUse(40)
    with assert_raises(contains="use"):
        b.validate()
    var c = _two_storeys()
    c.elements[0].kind = ElementKind(40)
    with assert_raises(contains="kind"):
        c.validate()
    var d = _two_storeys()
    d.elements[0].construction = ConstructionId(40)
    with assert_raises(contains="construction id"):
        d.validate()
    var e = _two_storeys()
    e.elements[0].material = MaterialId(40)
    with assert_raises(contains="material id"):
        e.validate()
    var f = _two_storeys()
    f.materials[0].poisson_ratio = 0.9
    with assert_raises(contains="Poisson"):
        f.validate()
    var g = _two_storeys()
    g.constructions[0].layers.clear()
    with assert_raises(contains="layer"):
        g.validate()
    var h = _two_storeys()
    var wall = ElementId(0)
    while h.elements[wall.value].kind != WALL:
        wall = ElementId(wall.value + 1)
    _ = h.add_opening(DOOR, wall, _m(0.5), _m(0), _m(1), _m(2), None)
    h.openings[0].host = ElementId(999)
    with assert_raises(contains="element id"):
        h.validate()
    var k = _two_storeys()
    k.spaces[0].storey = StoreyId(9)
    with assert_raises(contains="storey id"):
        k.validate()
    var m = _two_storeys()
    m.site.latitude = Angle64(100, DEGREE)
    with assert_raises(contains="latitude"):
        m.validate()


def test_assemble_refuses() raises:
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("a", OFFICE, _rect(0, 0, 1, 1)))
    plans.append(StoreyPlan("g", _m(3), ground^))
    var tol = Length64(1e-6, METER)
    var bad_site = _site()
    bad_site.latitude = Angle64(95, DEGREE)
    with assert_raises(contains="latitude"):
        _ = assemble(
            "x",
            bad_site,
            _m(0),
            plans,
            _library(),
            _constructions(),
            _defaults(),
            tol,
        )
    var bad_materials = _library()
    bad_materials[0].poisson_ratio = 0.7
    with assert_raises(contains="Poisson"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            plans,
            bad_materials^,
            _constructions(),
            _defaults(),
            tol,
        )
    var bad_constructions = _constructions()
    bad_constructions[0].layers.clear()
    with assert_raises(contains="layer"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            plans,
            _library(),
            bad_constructions^,
            _defaults(),
            tol,
        )
    var bad_defaults = _defaults()
    bad_defaults.roof = ConstructionId(30)
    with assert_raises(contains="default construction"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            plans,
            _library(),
            _constructions(),
            bad_defaults,
            tol,
        )
    var negative_defaults = _defaults()
    negative_defaults.floor = ConstructionId(-1)
    with assert_raises(contains="default construction"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            plans,
            _library(),
            _constructions(),
            negative_defaults,
            tol,
        )
    var flat = List[StoreyPlan]()
    flat.append(StoreyPlan("g", _m(0), List[SpacePlan]()))
    with assert_raises(contains="height"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            flat,
            _library(),
            _constructions(),
            _defaults(),
            tol,
        )
    var endless = List[StoreyPlan]()
    endless.append(StoreyPlan("g", _m(inf[DType.float64]()), List[SpacePlan]()))
    with assert_raises(contains="height"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            endless,
            _library(),
            _constructions(),
            _defaults(),
            tol,
        )
    var bad_use = List[StoreyPlan]()
    var spaces = List[SpacePlan]()
    spaces.append(SpacePlan("a", SpaceUse(77), _rect(0, 0, 1, 1)))
    bad_use.append(StoreyPlan("g", _m(3), spaces^))
    with assert_raises(contains="use"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            bad_use,
            _library(),
            _constructions(),
            _defaults(),
            tol,
        )


def test_an_overhang_is_a_slab() raises:
    # The first storey sticks out past the ground storey.
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("lobby", OFFICE, _rect(0, 0, 4, 4)))
    plans.append(StoreyPlan("ground", _m(3), ground^))
    var first = List[SpacePlan]()
    first.append(SpacePlan("office", OFFICE, _rect(0, 0, 6, 4)))
    plans.append(StoreyPlan("first", _m(3), first^))
    var b = assemble(
        "overhang",
        _site(),
        _m(10),
        plans,
        _library(),
        _constructions(),
        _defaults(),
        Length64(1e-6, METER),
    )
    b.validate()
    var exposed_floors = 0
    for i in range(len(b.elements)):
        if b.elements[i].kind == SLAB and b.is_exterior(ElementId(i)):
            if b.elements[i].storey == StoreyId(1):
                exposed_floors += 1
    assert_equal(exposed_floors, 1)
    assert_equal(b.storeys[0].elevation.to(METER), 10)


def test_a_face_without_an_element() raises:
    var b = _two_storeys()
    var cell = b.spaces[0].cell
    var faces = b.topology.complex.faces_of(cell)
    b.face_element[faces[0].value] = -1
    assert_false(b.element_of_face(faces[0]))
    assert_equal(len(b.elements_of_space(SpaceId(0))), 5)


def test_empty_and_lonely_models() raises:
    var tol = Length64(1e-6, METER)
    # No storeys at all.
    var none = assemble(
        "none",
        _site(),
        _m(0),
        List[StoreyPlan](),
        _library(),
        _constructions(),
        _defaults(),
        tol,
    )
    none.validate()
    assert_equal(none.gross_floor_area().value, 0)
    # A storey with no spaces.
    var bare = List[StoreyPlan]()
    bare.append(StoreyPlan("bare", _m(3), List[SpacePlan]()))
    var empty = assemble(
        "bare",
        _site(),
        _m(0),
        bare,
        _library(),
        _constructions(),
        _defaults(),
        tol,
    )
    assert_equal(len(empty.spaces), 0)
    # One room alone has no neighbors.
    var alone = List[StoreyPlan]()
    var spaces = List[SpacePlan]()
    spaces.append(SpacePlan("hut", OFFICE, _rect(0, 0, 3, 3)))
    alone.append(StoreyPlan("g", _m(3), spaces^))
    var hut = assemble(
        "hut",
        _site(),
        _m(0),
        alone,
        _library(),
        _constructions(),
        _defaults(),
        tol,
    )
    assert_equal(len(hut.space_neighbors(SpaceId(0))), 0)
    # A model with no materials or constructions validates.
    var shell = Building(
        "shell",
        _site(),
        List[BuildingMaterial](),
        List[Construction](),
        build_storeys([_m(0)], List[List[Region]](), tol),
    )
    shell.validate()
    with assert_raises(contains="default construction"):
        _ = assemble(
            "x",
            _site(),
            _m(0),
            List[StoreyPlan](),
            List[BuildingMaterial](),
            List[Construction](),
            _defaults(),
            tol,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
