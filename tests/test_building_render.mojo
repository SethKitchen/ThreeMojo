# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the render view and the model fingerprint of
`extensions.building`.

The references are counts: the triangles of boxes and of walls with holes,
the meshes per storey and look, and the provenance the view records.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from core.assets import Assets
from core.scene import Scene
from extensions.building.construction import (
    Construction,
    Layer,
    double_glazing,
)
from extensions.building.fingerprint import Fingerprint, fingerprint
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    StoreyId,
)
from extensions.building.kinds import (
    CIRCLE,
    CORRIDOR,
    DOOR,
    OFFICE,
    WALL,
    WINDOW,
)
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
    Section,
    Site,
    Space,
    SpacePlan,
    StoreyPlan,
    assemble,
    i_shape,
)
from extensions.building.views.render import (
    ELEMENT_ID,
    FULL,
    MASSING,
    RenderDetail,
    RenderOptions,
    add_building,
)
from extensions.building.generate.plan import RESIDENTIAL_FLOOR
from extensions.building.generate.tower import TowerOptions, generate_tower
from generators.skyscraper import SkyscraperParameters
from extensions.topology.arrangement import Point2, Region
from extensions.topology.storeys import build_storeys
from extensions.topology.ids import CellId
from units.si import Angle64, DEGREE, DEGREE64, Length, Length64, METER


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
        Construction("partition", [Layer(MaterialId(2), _m(0.1))])
    )
    constructions.append(Construction("slab", [Layer(MaterialId(3), _m(0.2))]))
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("office", OFFICE, _rect(0, 0, 6, 5)))
    ground.append(SpacePlan("corridor", CORRIDOR, _rect(6, 0, 8, 5)))
    plans.append(StoreyPlan("ground", _m(3.5), ground^))
    var first = List[SpacePlan]()
    first.append(SpacePlan("hall", OFFICE, _rect(0, 0, 8, 5)))
    plans.append(StoreyPlan("first", _m(3), first^))
    var b = assemble(
        "render test",
        Site(Angle64(40, DEGREE64), Angle64(-105, DEGREE64), _m(0), Angle64(0)),
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
    # A window and a door in the first ground-floor wall that is long
    # enough.
    var wall = ElementId(0)
    while b.elements[wall.value].kind != WALL or b.wall_frame(wall).length < 4:
        wall = ElementId(wall.value + 1)
    _ = b.add_opening(
        WINDOW, wall, _m(0.5), _m(0.9), _m(1.2), _m(1.2), double_glazing()
    )
    _ = b.add_opening(DOOR, wall, _m(2.5), _m(0), _m(0.9), _m(2.1), None)
    var section = i_shape(_m(0.2), _m(0.3), _m(0.012), _m(0.008))
    _ = b.add_column(StoreyId(0), Point2(3, 2.5), section, MaterialId(4))
    _ = b.add_beam(
        StoreyId(0), Point2(0, 2.5), Point2(8, 2.5), section, MaterialId(4)
    )
    var round = Section(CIRCLE, _m(0.3), _m(0), _m(0), _m(0))
    _ = b.add_column(StoreyId(1), Point2(4, 2.5), round, MaterialId(3))
    return b^


def test_full_detail_draws_every_element() raises:
    var b = _building()
    var scene = Scene()
    var assets = Assets()
    var out = add_building(scene, assets, b, RenderOptions.default())
    assert_true(out.meshes >= 6)
    assert_equal(len(scene.meshes), out.meshes)
    assert_true(out.triangles > 200)
    ref root = scene.node(out.root)
    assert_equal(root.user_data.string("model"), "render test")
    assert_equal(root.user_data.string("detail"), "full")
    assert_equal(root.user_data.string("fingerprint"), hex(Int(fingerprint(b))))
    assert_true(root.user_data.has("dropped"))
    var total = 0
    for i in range(len(scene.meshes)):
        ref geometry = assets.geometries.get(scene.meshes[i].geometry)
        assert_true(geometry.has_attribute(String(ELEMENT_ID)))
        total += geometry.vertex_count() // 3
    assert_equal(total, out.triangles)


def test_massing_draws_the_envelope_only() raises:
    var b = _building()
    var scene = Scene()
    var assets = Assets()
    var full = add_building(scene, assets, b, RenderOptions.default())
    var massing_scene = Scene()
    var massing = add_building(
        massing_scene, assets, b, RenderOptions(MASSING, -1)
    )
    assert_true(massing.triangles < full.triangles)
    assert_equal(
        massing_scene.node(massing.root).user_data.string("detail"), "massing"
    )


def test_a_cutaway_stops_at_a_storey() raises:
    var b = _building()
    var scene = Scene()
    var assets = Assets()
    var full = add_building(scene, assets, b, RenderOptions.default())
    var cut_scene = Scene()
    var cut = add_building(cut_scene, assets, b, RenderOptions(FULL, 0))
    assert_true(cut.triangles < full.triangles)
    assert_equal(cut_scene.node(cut.root).user_data.number("topStorey"), 0)


def test_render_refuses_bad_options() raises:
    var b = _building()
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="detail"):
        _ = add_building(scene, assets, b, RenderOptions(RenderDetail(3), -1))
    with assert_raises(contains="top storey"):
        _ = add_building(scene, assets, b, RenderOptions(FULL, 2))
    with assert_raises(contains="top storey"):
        _ = add_building(scene, assets, b, RenderOptions(FULL, -2))
    assert_true(MASSING.is_valid())
    assert_false(RenderDetail(-1).is_valid())


def test_fingerprint_follows_the_content() raises:
    var a = _building()
    var b = _building()
    assert_equal(fingerprint(a), fingerprint(b))
    b.openings[0].width = _m(1.1)
    assert_true(fingerprint(a) != fingerprint(b))
    var c = _building()
    c.name = "another"
    assert_true(fingerprint(a) != fingerprint(c))
    # Parts with no outline, no faces and no layers still hash.
    c.spaces.append(
        Space("empty", StoreyId(0), OFFICE, CellId(0), List[Point2]())
    )
    c.constructions.append(Construction("none", List[Layer]()))
    var h = Fingerprint()
    h.add_text("")
    assert_true(h.value != Fingerprint().value)
    assert_true(fingerprint(c) != fingerprint(a))


def test_empty_and_setback_buildings() raises:
    var empty = Building(
        "empty",
        Site(Angle64(0), Angle64(0), _m(0), Angle64(0)),
        List[BuildingMaterial](),
        List[Construction](),
        build_storeys([_m(0)], List[List[Region]](), Length64(1e-6, METER)),
    )
    var scene = Scene()
    var assets = Assets()
    var none = add_building(scene, assets, empty, RenderOptions.default())
    assert_equal(none.meshes, 0)
    assert_equal(none.triangles, 0)
    _ = fingerprint(empty)
    # A crown inside a shaft: the shaft's roof is a bridged loop.
    var materials = List[BuildingMaterial]()
    materials.append(concrete())
    var constructions = List[Construction]()
    constructions.append(Construction("c", [Layer(MaterialId(0), _m(0.2))]))
    var plans = List[StoreyPlan]()
    var shaft = List[SpacePlan]()
    shaft.append(SpacePlan("shaft", OFFICE, _rect(0, 0, 10, 10)))
    plans.append(StoreyPlan("shaft", _m(3), shaft^))
    var crown = List[SpacePlan]()
    crown.append(SpacePlan("crown", OFFICE, _rect(4, 4, 6, 6)))
    plans.append(StoreyPlan("crown", _m(3), crown^))
    var c = ConstructionId(0)
    var b = assemble(
        "setback",
        Site(Angle64(0), Angle64(0), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(c, c, c, c, c),
        Length64(1e-6, METER),
    )
    var out = add_building(scene, assets, b, RenderOptions.default())
    assert_true(out.triangles > 0)
    # A cutaway at the shaft drops the crown and the shaft's roof.
    var cut = add_building(scene, assets, b, RenderOptions(FULL, 0))
    assert_true(cut.triangles < out.triangles)


def test_furniture_draws_in_full_detail() raises:
    var scene = Scene()
    var assets = Assets()
    var params = SkyscraperParameters()
    params.total_height = Length(12, METER)
    var options = TowerOptions(params^)
    options.shaft = RESIDENTIAL_FLOOR
    var homes = generate_tower(options)
    var full = add_building(scene, assets, homes, RenderOptions.default())
    homes.furnishings.clear()
    var empty = add_building(scene, assets, homes, RenderOptions.default())
    assert_true(full.triangles > empty.triangles)
    var offices = generate_tower(TowerOptions(SkyscraperParameters()))
    var cut = add_building(scene, assets, offices, RenderOptions(FULL, 1))
    assert_true(cut.triangles > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
