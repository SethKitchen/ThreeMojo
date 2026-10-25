# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.building.views.bearing`, the gravity load down a
building's walls.

Every expected number is worked by hand from the masonry kit:

- A brick wall weighs 1800 kg/m3 x 0.365 m + 800 kg/m3 x 0.015 m =
  669 kg/m2. The roof weighs 30 x 0.2 + 500 x 0.1 = 56 kg/m2, a floor slab
  2400 x 0.18 = 432 kg/m2 and the ground slab 2400 x 0.2 = 480 kg/m2.
- A 4 m by 5 m storey 3 m high has 54 m2 of wall, 18 m long, on 0.365 m
  of brick of 10 MPa: 0.6 x 10 MPa x 18 m x 0.365 m = 39.42 MN.
- The roof's live load is 0.96 kPa and a dwelling's floor 1.92 kPa.
"""

from extensions.building.construction import Construction, Layer
from extensions.building.ids import ElementId, MaterialId, StoreyId
from extensions.building.kinds import DOOR, LIVING, SLAB, WALL
from extensions.building.kits import MASONRY_KIT, construction_kit
from extensions.building.model import (
    Building,
    Element,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    rectangle,
)
from extensions.building.views.bearing import (
    BearingCheck,
    BearingOptions,
    StoreyBearing,
    bearing_check,
    default_bearing_options,
    element_mass,
)
from extensions.topology.arrangement import Point2
from extensions.topology.ids import FaceId
from generators.utils import Vec3d
from std.math import isinf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Acceleration64,
    Angle64,
    DEGREE64,
    Force64,
    KILOGRAM,
    Length64,
    Mass64,
    METER,
    METER_PER_SECOND_SQUARED,
    NEWTON,
)

comptime G = 9.80665
comptime WALL_MASS = 669.0 * 54
comptime ROOF_MASS = 56.0 * 20
comptime FLOOR_MASS = 432.0 * 20
comptime GROUND_MASS = 480.0 * 20


def _box(storeys: Int) raises -> Building:
    """Return a 4 m by 5 m masonry box of storeys 3 m high."""
    var kit = construction_kit(MASONRY_KIT)
    var plans = List[StoreyPlan]()
    for s in range(storeys):
        var outline: List[Point2] = [
            Point2(0, 0),
            Point2(4, 0),
            Point2(4, 5),
            Point2(0, 5),
        ]
        var spaces = List[SpacePlan]()
        spaces.append(SpacePlan("room", LIVING, outline^))
        plans.append(
            StoreyPlan(String("storey ", s), Length64(3, METER), spaces^)
        )
    return assemble(
        "box",
        Site(
            Angle64(52.2, DEGREE64),
            Angle64(21.0, DEGREE64),
            Length64(100, METER),
            Angle64(0, DEGREE64),
        ),
        Length64(0, METER),
        plans,
        kit.materials.copy(),
        kit.constructions.copy(),
        kit.defaults,
        Length64(1e-6, METER),
    )


def test_the_default_options_are_the_code_factors() raises:
    """1.2 dead, 1.6 live and 0.6 on the strength."""
    var options = default_bearing_options()
    options.check()
    assert_equal(options.dead_factor, 1.2)
    assert_equal(options.live_factor, 1.6)
    assert_equal(options.resistance_factor, 0.6)


def test_options_that_cannot_weigh_a_building_are_refused() raises:
    """Each factor and the gravity are checked."""
    var good = default_bearing_options()
    var options = good
    options.gravity = Acceleration64(0, METER_PER_SECOND_SQUARED)
    with assert_raises(contains="the gravity must be positive"):
        options.check()
    options = good
    options.dead_factor = -1
    with assert_raises(contains="the dead factor must be positive"):
        options.check()
    options = good
    options.live_factor = 0
    with assert_raises(contains="the live factor must be positive"):
        options.check()
    options = good
    options.resistance_factor = 0
    with assert_raises(contains="the resistance factor must be positive"):
        options.check()
    options.resistance_factor = 1.5
    with assert_raises(contains="the resistance factor is at most one"):
        options.check()
    with assert_raises(contains="the resistance factor is at most one"):
        _ = bearing_check(_box(1), options)


def test_each_element_weighs_its_layers() raises:
    """Walls, the roof and the ground slab of one storey."""
    var box = _box(1)
    var total = Float64(0)
    for e in range(len(box.elements)):
        var mass = element_mass(box, ElementId(e)).to(KILOGRAM)
        total += mass
        if box.elements[e].kind == WALL:
            var area = box.topology.complex.face_area(box.elements[e].faces[0])
            assert_almost_equal(mass, 669 * area, atol=1e-6)
    assert_almost_equal(total, WALL_MASS + ROOF_MASS + GROUND_MASS, atol=1e-6)
    with assert_raises():
        _ = element_mass(box, ElementId(99))


def test_one_storey_carries_its_walls_and_roof() raises:
    """The ground slab loads no wall."""
    var check = bearing_check(_box(1), default_bearing_options())
    assert_equal(len(check.storeys), 1)
    var base = check.storeys[0]
    var dead = (WALL_MASS + ROOF_MASS) * G
    var live = 960.0 * 20
    assert_almost_equal(base.dead.to(NEWTON), dead, atol=1e-6)
    assert_almost_equal(base.live.to(NEWTON), live, atol=1e-6)
    assert_almost_equal(
        base.demand.to(NEWTON), 1.2 * dead + 1.6 * live, atol=1e-6
    )
    assert_almost_equal(
        base.capacity.to(NEWTON), 0.6 * 10e6 * 18 * 0.365, atol=1e-3
    )
    assert_almost_equal(base.wall_length.to(METER), 18, atol=1e-9)
    assert_almost_equal(
        check.utilization(), base.demand.value / base.capacity.value, atol=1e-12
    )
    assert_almost_equal(
        check.mass.to(KILOGRAM), WALL_MASS + ROOF_MASS + GROUND_MASS, atol=1e-6
    )
    assert_equal(len(check.notes), 1)


def test_a_lower_storey_carries_everything_above_it() raises:
    """Storey 0 carries both storeys' walls, the floor between and the
    roof; storey 1 only its walls and the roof."""
    var check = bearing_check(_box(2), default_bearing_options())
    assert_equal(len(check.storeys), 2)
    assert_almost_equal(
        check.storeys[0].dead.to(NEWTON),
        (2 * WALL_MASS + FLOOR_MASS + ROOF_MASS) * G,
        atol=1e-6,
    )
    assert_almost_equal(
        check.storeys[0].live.to(NEWTON), 1920.0 * 20 + 960.0 * 20, atol=1e-6
    )
    assert_almost_equal(
        check.storeys[1].dead.to(NEWTON), (WALL_MASS + ROOF_MASS) * G, atol=1e-6
    )
    assert_true(check.storeys[0].utilization() > check.storeys[1].utilization())
    assert_almost_equal(check.utilization(), check.storeys[0].utilization())


def test_a_door_takes_its_area_and_its_width() raises:
    """A 0.9 m by 2.1 m door removes 1.89 m2 of wall and 0.9 m of length."""
    var box = _box(1)
    var wall = ElementId(0)
    for e in range(len(box.elements)):
        if box.elements[e].kind == WALL:
            wall = ElementId(e)
            break
    var before = element_mass(box, wall).to(KILOGRAM)
    _ = box.add_opening(
        DOOR,
        wall,
        Length64(0.5, METER),
        Length64(0, METER),
        Length64(0.9, METER),
        Length64(2.1, METER),
        None,
    )
    assert_almost_equal(
        element_mass(box, wall).to(KILOGRAM), before - 669 * 1.89, atol=1e-6
    )
    var check = bearing_check(box, default_bearing_options())
    assert_almost_equal(check.storeys[0].wall_length.to(METER), 17.1, atol=1e-9)


def test_a_column_adds_its_weight_and_a_note() raises:
    """A 0.3 m square concrete column 3 m high weighs 648 kg."""
    var box = _box(1)
    var column = box.add_column(
        StoreyId(0),
        Point2(2, 2.5),
        rectangle(Length64(0.3, METER), Length64(0.3, METER)),
        MaterialId(2),
    )
    assert_almost_equal(element_mass(box, column).to(KILOGRAM), 648, atol=1e-6)
    var check = bearing_check(box, default_bearing_options())
    assert_equal(len(check.notes), 2)
    assert_true("columns and beams" in check.notes[1])
    assert_almost_equal(
        check.storeys[0].dead.to(NEWTON),
        (WALL_MASS + ROOF_MASS + 648) * G,
        atol=1e-6,
    )


def test_a_beam_adds_its_weight_too() raises:
    """A 0.2 m by 0.4 m concrete beam 4 m long weighs 768 kg."""
    var box = _box(1)
    var beam = box.add_beam(
        StoreyId(0),
        Point2(0, 2.5),
        Point2(4, 2.5),
        rectangle(Length64(0.2, METER), Length64(0.4, METER)),
        MaterialId(2),
    )
    assert_almost_equal(element_mass(box, beam).to(KILOGRAM), 768, atol=1e-6)
    assert_equal(len(bearing_check(box, default_bearing_options()).notes), 2)


def test_a_setback_roof_loads_only_the_storey_under_it() raises:
    """With storey 1 over half the plan, the other half of storey 0's top
    is a roof that storey 1's walls do not carry."""
    var kit = construction_kit(MASONRY_KIT)
    var plans = List[StoreyPlan]()
    var corners: List[Float64] = [5, 2.5]
    for s in range(2):
        var outline: List[Point2] = [
            Point2(0, 0),
            Point2(4, 0),
            Point2(4, corners[s]),
            Point2(0, corners[s]),
        ]
        var spaces = List[SpacePlan]()
        spaces.append(SpacePlan("room", LIVING, outline^))
        plans.append(
            StoreyPlan(String("storey ", s), Length64(3, METER), spaces^)
        )
    var building = assemble(
        "setback",
        Site(
            Angle64(52.2, DEGREE64),
            Angle64(21.0, DEGREE64),
            Length64(100, METER),
            Angle64(0, DEGREE64),
        ),
        Length64(0, METER),
        plans,
        kit.materials.copy(),
        kit.constructions.copy(),
        kit.defaults,
        Length64(1e-6, METER),
    )
    var check = bearing_check(building, default_bearing_options())
    # Storey 1: walls of 13 m by 3 m, and a roof of 10 m2.
    assert_almost_equal(
        check.storeys[1].dead.to(NEWTON),
        (669.0 * 39 + 56.0 * 10) * G,
        atol=1e-6,
    )
    assert_almost_equal(check.storeys[1].live.to(NEWTON), 960.0 * 10, atol=1e-6)
    # Storey 0 also carries the low roof, the floor slab and its walls.
    assert_almost_equal(
        check.storeys[0].live.to(NEWTON),
        960.0 * 20 + 1920.0 * 10,
        atol=1e-6,
    )


def test_odd_elements_weigh_nothing_and_bear_nothing() raises:
    """Elements with no construction, a section without a material, a
    wall with no faces and a construction with no layers add no mass and
    no capacity."""
    var box = _box(1)
    box.elements.append(
        Element(
            "marker",
            SLAB,
            StoreyId(0),
            List[FaceId](),
            None,
            None,
            None,
            Vec3d(0, 0, 0),
            Vec3d(0, 0, 0),
        )
    )
    assert_equal(
        element_mass(box, ElementId(len(box.elements) - 1)).to(KILOGRAM), 0
    )
    box.elements.append(
        Element(
            "loose section",
            SLAB,
            StoreyId(0),
            List[FaceId](),
            None,
            None,
            rectangle(Length64(0.3, METER), Length64(0.3, METER)),
            Vec3d(0, 0, 0),
            Vec3d(0, 0, 3),
        )
    )
    assert_equal(
        element_mass(box, ElementId(len(box.elements) - 1)).to(KILOGRAM), 0
    )
    var first = 0
    while box.elements[first].kind != WALL:
        first += 1
    var bare = box.elements[first].copy()
    bare.construction = None
    box.elements.append(bare^)
    var check = bearing_check(box, default_bearing_options())
    assert_almost_equal(
        check.storeys[0].capacity.to(NEWTON), 0.6 * 10e6 * 18 * 0.365, atol=1e-3
    )
    var flat = box.elements[first].copy()
    flat.faces = List[FaceId]()
    box.elements[first] = flat^
    assert_equal(element_mass(box, ElementId(first)).to(KILOGRAM), 0)
    var thin = bearing_check(box, default_bearing_options())
    assert_true(
        thin.storeys[0].capacity.value < check.storeys[0].capacity.value
    )
    box.constructions[0] = Construction("nothing", List[Layer]())
    var none = bearing_check(box, default_bearing_options())
    assert_equal(none.storeys[0].capacity.to(NEWTON), 0)


def test_a_model_without_spaces_elements_or_storeys_is_empty() raises:
    """With no space, a floor carries no live load; with no element, a
    storey carries nothing; with no storey, there is nothing to check."""
    var two = _box(2)
    two.spaces.clear()
    var check = bearing_check(two, default_bearing_options())
    assert_almost_equal(check.storeys[0].live.to(NEWTON), 960.0 * 20, atol=1e-6)
    two.elements.clear()
    var bare = bearing_check(two, default_bearing_options())
    assert_equal(bare.storeys[0].dead.to(NEWTON), 0)
    assert_equal(bare.mass.to(KILOGRAM), 0)
    two.storeys.clear()
    assert_equal(len(bearing_check(two, default_bearing_options()).storeys), 0)


def test_a_storey_with_no_capacity_is_infinitely_used() raises:
    """No wall gives an infinite utilization; no storey gives zero."""
    var empty = StoreyBearing(
        StoreyId(0),
        Force64(1, NEWTON),
        Force64(0, NEWTON),
        Force64(1, NEWTON),
        Force64(0, NEWTON),
        Length64(0, METER),
    )
    assert_true(isinf(empty.utilization()))
    var none = BearingCheck(
        List[StoreyBearing](), Mass64(0, KILOGRAM), List[String]()
    )
    assert_equal(none.utilization(), 0)


def test_a_storey_with_no_height_is_refused() raises:
    """A model whose storey height was changed to zero cannot be weighed."""
    var box = _box(1)
    box.storeys[0].height = Length64(0, METER)
    with assert_raises(contains="a storey height must be positive"):
        _ = bearing_check(box, default_bearing_options())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
