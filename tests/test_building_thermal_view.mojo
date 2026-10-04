# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.building.views.thermal`.

The reference is the building itself: the zones are its spaces, the
surface areas are the areas of the faces of its cell complex less its
windows, and each face between two spaces is one surface that couples
both zones.
"""

from std.math import abs
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.construction import Construction, Layer, double_glazing
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    StoreyId,
)
from extensions.building.kinds import CORRIDOR, DOOR, OFFICE, WALL, WINDOW
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
    steel,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    rectangle,
)
from extensions.building.views.thermal import (
    default_thermal_options,
    thermal_view,
)
from extensions.energy.ids import GROUND, INTERZONE, ZoneId
from extensions.energy.simulation import default_options, simulate
from extensions.energy.weather import WeatherLocation, design_day
from extensions.topology.arrangement import Point2
from extensions.topology.ids import FaceId
from units.si import (
    Angle64,
    DEGREE,
    DEGREE64,
    Duration64,
    HOUR,
    Length64,
    METER,
    METER_PER_SECOND,
    Velocity64,
)
from units.temperature import CELSIUS, Temperature64


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _rect(x0: Float64, y0: Float64, x1: Float64, y1: Float64) -> List[Point2]:
    return [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]


def _building() raises -> Building:
    var materials = List[BuildingMaterial]()
    materials.append(brick())
    materials.append(mineral_wool())
    materials.append(gypsum_board())
    materials.append(concrete())
    materials.append(steel())
    var constructions = List[Construction]()
    constructions.append(
        Construction(
            "exterior wall",
            [
                Layer(MaterialId(0), _m(0.2)),
                Layer(MaterialId(1), _m(0.1)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    constructions.append(
        Construction(
            "partition",
            [
                Layer(MaterialId(2), _m(0.0125)),
                Layer(MaterialId(1), _m(0.05)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    constructions.append(
        Construction(
            "slab",
            [Layer(MaterialId(1), _m(0.1)), Layer(MaterialId(3), _m(0.2))],
        )
    )
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("office A", OFFICE, _rect(0, 0, 6, 5)))
    ground.append(SpacePlan("corridor", CORRIDOR, _rect(6, 0, 8, 5)))
    plans.append(StoreyPlan("ground", _m(3.5), ground^))
    var first = List[SpacePlan]()
    first.append(SpacePlan("office B", OFFICE, _rect(0, 0, 10, 5)))
    plans.append(StoreyPlan("first", _m(3), first^))
    return assemble(
        "thermal test",
        Site(
            Angle64(40, DEGREE64), Angle64(-105, DEGREE64), _m(1600), Angle64(0)
        ),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(2),
        ),
        Length64(1e-6, METER),
    )


def _wall_at(
    b: Building, x: Float64, y: Float64, z: Float64
) raises -> ElementId:
    for e in range(len(b.elements)):
        ref element = b.elements[e]
        if element.kind != WALL:
            continue
        var c = b.topology.complex.face_centroid(element.faces[0])
        if abs(c.x - x) < 1e-6 and abs(c.y - y) < 1e-6 and abs(c.z - z) < 1e-6:
            return ElementId(e)
    raise Error("no wall there")


def _furnished() raises -> Building:
    var b = _building()
    var south = _wall_at(b, 3, 0, 1.75)
    _ = b.add_opening(
        WINDOW, south, _m(1), _m(1), _m(2), _m(1.5), double_glazing()
    )
    var inner = _wall_at(b, 6, 2.5, 1.75)
    _ = b.add_opening(DOOR, inner, _m(0.5), _m(0), _m(1), _m(2.1), None)
    _ = b.add_opening(
        WINDOW, inner, _m(3), _m(1), _m(1), _m(1), double_glazing()
    )
    var east = _wall_at(b, 8, 2.5, 1.75)
    _ = b.add_opening(
        WINDOW, east, _m(0), _m(0), _m(5), _m(3.5), double_glazing()
    )
    _ = b.add_column(
        StoreyId(0), Point2(3, 2.5), rectangle(_m(0.3), _m(0.3)), MaterialId(4)
    )
    _ = b.add_beam(
        StoreyId(0),
        Point2(0, 2.5),
        Point2(6, 2.5),
        rectangle(_m(0.3), _m(0.5)),
        MaterialId(4),
    )
    return b^


def _contains(lines: List[String], text: String) -> Bool:
    for i in range(len(lines)):
        if text in lines[i]:
            return True
    return False


def test_zones_surfaces_and_windows() raises:
    var b = _furnished()
    var view = thermal_view(b, default_thermal_options(), List[ZoneId]())
    ref model = view.model
    model.check()
    assert_equal(len(model.zones), 3)
    assert_equal(view.space_zone[2], ZoneId(2))
    assert_equal(model.zones[1].name, "corridor")
    assert_almost_equal(model.zones[0].floor_area.value, 30, atol=1e-9)
    assert_almost_equal(model.zones[0].volume.value, 105, atol=1e-9)
    assert_almost_equal(model.zones[0].gains.total().value, 25, atol=1e-12)
    assert_almost_equal(
        model.zones[0].heating_setpoint.to(CELSIUS), 20, atol=1e-12
    )
    # Two windows in exterior walls; the one in the partition is dropped.
    assert_equal(len(model.windows), 2)
    assert_equal(len(view.window_opening), 2)
    assert_almost_equal(model.windows[0].area.value, 3, atol=1e-12)
    assert_almost_equal(model.windows[0].normal.y, -1, atol=1e-12)
    assert_equal(model.windows[1].zone, ZoneId(1))
    assert_almost_equal(model.windows[1].normal.x, 1, atol=1e-12)
    # Every face is a surface but the fully glazed wall.
    ref complex = b.topology.complex
    assert_equal(len(model.surfaces), len(complex.faces) - 1)
    var faces_total = 0.0
    for f in range(len(complex.faces)):
        faces_total += complex.face_area(FaceId(f))
    var surfaces_total = 0.0
    var interzone = 0
    var ground = 0
    var exposed_floor = 0
    for k in range(len(model.surfaces)):
        ref s = model.surfaces[k]
        var face = view.surface_face[k]
        surfaces_total += s.area.value
        var expected = complex.face_area(face)
        if s.boundary == INTERZONE:
            interzone += 1
            assert_true(s.inside != s.outside.value())
            assert_almost_equal(s.area.value, expected, atol=1e-9)
        elif s.boundary == GROUND:
            ground += 1
            assert_almost_equal(s.normal.z, -1, atol=1e-12)
            assert_almost_equal(s.inside_film.value, 1 / 0.17, atol=1e-12)
        elif s.normal.z < -0.5:
            exposed_floor += 1
            assert_equal(s.inside, ZoneId(2))
        if s.normal.z > 0.5:
            assert_almost_equal(s.inside_film.value, 1 / 0.10, atol=1e-12)
    assert_almost_equal(surfaces_total + 3, faces_total - 5 * 3.5, atol=1e-9)
    # One partition and two floor pieces couple zones.
    assert_equal(interzone, 3)
    assert_equal(ground, 2)
    assert_equal(exposed_floor, 1)
    assert_true(_contains(view.dropped, "1 doors"))
    assert_true(_contains(view.dropped, "interior wall"))
    assert_true(_contains(view.dropped, "2 columns and beams"))
    assert_true(_contains(view.dropped, "fully glazed"))
    assert_true(_contains(view.dropped, "Furniture"))


def test_interzone_surfaces_pair_both_zones() raises:
    var b = _building()
    var view = thermal_view(b, default_thermal_options(), List[ZoneId]())
    ref model = view.model
    # Each zone sees every interzone surface it touches, from either face.
    var pairs = 0
    for k in range(len(model.surfaces)):
        ref s = model.surfaces[k]
        if s.boundary != INTERZONE:
            continue
        var a = s.inside
        var c = s.outside.value()
        var seen_a = model.surfaces_of(a)
        var seen_c = model.surfaces_of(c)
        var found = 0
        for i in range(len(seen_a)):
            if seen_a[i].value == k:
                found += 1
        for i in range(len(seen_c)):
            if seen_c[i].value == k:
                found += 1
        assert_equal(found, 2)
        # The face's two cells are the two zones.
        ref face = b.topology.complex.faces[view.surface_face[k].value]
        var cells = [face.positive.value().value, face.negative.value().value]
        assert_true(
            (cells[0] == a.value and cells[1] == c.value)
            or (cells[0] == c.value and cells[1] == a.value)
        )
        pairs += 1
    assert_equal(pairs, 3)
    assert_false(_contains(view.dropped, "doors"))
    assert_false(_contains(view.dropped, "columns"))


def test_grouped_zones() raises:
    var b = _building()
    var view = thermal_view(
        b, default_thermal_options(), [ZoneId(0), ZoneId(0), ZoneId(1)]
    )
    ref model = view.model
    assert_equal(len(model.zones), 2)
    assert_equal(model.zones[0].name, "office A + corridor")
    assert_almost_equal(model.zones[0].volume.value, 140, atol=1e-9)
    assert_almost_equal(model.zones[0].floor_area.value, 40, atol=1e-9)
    # Area-weighted: (25 W/m² x 30 m² + 6 W/m² x 10 m²) / 40 m².
    assert_almost_equal(
        model.zones[0].gains.total().value, 810.0 / 40, atol=1e-12
    )
    var internal = 0
    for k in range(len(model.surfaces)):
        ref s = model.surfaces[k]
        if s.boundary == INTERZONE and s.inside == s.outside.value():
            internal += 1
    assert_equal(internal, 1)
    with assert_raises(contains="one zone per space"):
        _ = thermal_view(b, default_thermal_options(), [ZoneId(0)])
    with assert_raises(contains="zone id"):
        _ = thermal_view(
            b, default_thermal_options(), [ZoneId(0), ZoneId(-1), ZoneId(0)]
        )
    with assert_raises(contains="every zone"):
        _ = thermal_view(
            b, default_thermal_options(), [ZoneId(0), ZoneId(0), ZoneId(2)]
        )
    var bad = default_thermal_options()
    bad.cooling_setpoint = Temperature64(10, CELSIUS)
    with assert_raises(contains="above cooling"):
        _ = thermal_view(b, bad, List[ZoneId]())


def test_empty_building() raises:
    var b = _building()
    var empty = assemble(
        "empty",
        b.site,
        _m(0),
        List[StoreyPlan](),
        b.materials.copy(),
        b.constructions.copy(),
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(0),
            ConstructionId(0),
            ConstructionId(0),
            ConstructionId(0),
        ),
        Length64(1e-6, METER),
    )
    var view = thermal_view(empty, default_thermal_options(), List[ZoneId]())
    assert_equal(len(view.model.zones), 0)
    assert_equal(len(view.model.surfaces), 0)
    assert_equal(len(view.dropped), 2)


def test_view_simulates() raises:
    var b = _furnished()
    var view = thermal_view(b, default_thermal_options(), List[ZoneId]())
    var weather = design_day(
        WeatherLocation(
            "Golden",
            Angle64(39.74, DEGREE64),
            Angle64(-105.18, DEGREE64),
            Duration64(-7, HOUR),
            _m(1829),
        ),
        1,
        21,
        Temperature64(-12, CELSIUS),
        Temperature64(2, CELSIUS),
        Temperature64(-15, CELSIUS),
        Velocity64(3, METER_PER_SECOND),
        1.0,
        1,
    )
    var options = default_options()
    options.warmup_days = 2
    var result = simulate(view.model, weather, options)
    for z in range(3):
        assert_true(result.heating_energy(ZoneId(z)).value > 0)
    # The sun through 17.5 m² of east glass overheats the corridor in the
    # morning. Office B has no window and needs no cooling.
    assert_true(result.cooling_energy(ZoneId(1)).value > 0)
    assert_equal(result.cooling_energy(ZoneId(2)).value, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
