# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.city`, three.js's `CityGenerator`.

The expected numbers were computed from three.js r186's
`examples/jsm/generators/CityGenerator.js`, step for step in `Float64`
with its Mulberry32 generator: the towers lot by lot, then the furniture
edge by edge. The default city is planned without building its towers;
a one-lot city of seed 35, whose tower is 38 meters tall, is built.
"""

from generators.car import CarPlacement
from generators.city import (
    BlockEdge,
    City,
    CityGenerator,
    CityParameters,
    CityPlan,
    block_edges,
    car_color,
    car_color_thresholds,
    car_colors,
    city_layout,
)
from generators.utils import generator_random
from math.matrix4 import Matrix4
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _matrix(m: Matrix4, expected: List[Float32]) raises:
    """Assert a matrix, its elements in column-major order."""
    for i in range(16):
        assert_almost_equal(m.elements[i], expected[i], atol=2e-5)


def _one_lot(seed: Int) -> CityParameters:
    """Return a city of one block of one lot, with no curb."""
    var p = CityParameters()
    p.seed = seed
    p.blocks_x = 1
    p.blocks_z = 1
    p.lots_x = 1
    p.lots_z = 1
    p.curb_height = Length(0, METER)
    return p^


def test_layout_matches_three() raises:
    """The default city is two by two blocks of three by two lots."""
    var layout = CityGenerator().layout()
    assert_equal(layout.block_w, 90)
    assert_equal(layout.block_d, 60)
    assert_almost_equal(layout.inner_lot_x, 26.666666666666668, atol=1e-5)
    assert_almost_equal(layout.inner_lot_z, 25.0, atol=1e-5)
    assert_equal(layout.city_w, 202)
    assert_equal(layout.city_d, 142)
    assert_equal(layout.block_x(1), -101 + 112)
    assert_equal(layout.block_z(1), -71 + 82)


def test_default_plan_matches_three() raises:
    """Towers and furniture of the default city, as three.js draws them."""
    var plan = CityGenerator().plan()
    assert_equal(len(plan.slabs), 4)
    assert_equal(plan.slabs[0].elements[12], -56)
    assert_equal(plan.slabs[0].elements[14], -41)
    assert_equal(len(plan.towers), 24)
    assert_equal(len(plan.lights), 40)
    assert_equal(len(plan.signals), 8)
    assert_equal(len(plan.cans), 16)
    assert_equal(len(plan.benches), 8)
    assert_equal(len(plan.hydrants), 16)
    assert_equal(len(plan.trees), 57)
    assert_equal(len(plan.people), 91)
    assert_equal(len(plan.cars), 131)
    ref first = plan.towers[0]
    assert_equal(first.parameters.seed, 98105)
    assert_almost_equal(
        first.parameters.total_height.to(METER), 82.82727687398321, atol=1e-4
    )
    assert_almost_equal(
        first.parameters.footprint_width.value().to(METER),
        26.263930945486454,
        atol=1e-4,
    )
    assert_almost_equal(
        first.parameters.floor_height.to(METER), 5.143080216785893, atol=1e-5
    )
    assert_almost_equal(
        first.parameters.chamfer_width.to(METER), 4.703187808394432, atol=1e-5
    )
    assert_equal(first.parameters.chamfer_corner_x, -1)
    assert_equal(first.parameters.chamfer_corner_z, -1)
    assert_equal(first.parameters.setback_depth, 0)
    assert_equal(first.parameters.string_course_every, 5)
    assert_almost_equal(first.position.x, -82.86803452725677, atol=1e-9)
    assert_almost_equal(first.position.y, 0.15, atol=1e-6)
    assert_almost_equal(first.position.z, -53.96372351997998, atol=1e-9)
    assert_almost_equal(first.box_center.y, 41.5636384369916, atol=1e-9)
    assert_almost_equal(first.box_size.x, 26.263930945486454, atol=1e-9)
    # A middle lot is not on a corner: no chamfer, centered along x.
    ref middle = plan.towers[2]
    assert_equal(middle.parameters.seed, 65812)
    assert_equal(middle.parameters.chamfer_width.to(METER), 0)
    assert_equal(middle.parameters.chamfer_corner_x, 0)
    assert_equal(middle.parameters.chamfer_corner_z, -1)
    assert_almost_equal(middle.position.x, -56.0, atol=1e-9)
    ref last = plan.towers[23]
    assert_equal(last.parameters.seed, 15339)
    assert_almost_equal(last.position.x, 83.16232193770509, atol=1e-9)
    assert_equal(last.parameters.chamfer_corner_x, 1)
    _matrix(
        plan.lights[0],
        [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, -86, 0.15, -70.2, 1],
    )
    _matrix(
        plan.lights[39],
        [0, 0, -1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 100.2, 0.15, 56, 1],
    )
    _matrix(
        plan.trees[0],
        [
            -0.5468356,
            0,
            0.6060206,
            0,
            0,
            0.8162660,
            0,
            0,
            -0.6060206,
            0,
            -0.5468356,
            0,
            -88.5,
            0.15,
            -69.5,
            1,
        ],
    )
    _matrix(
        plan.people[0],
        [
            -0.8032440,
            0,
            -0.7107167,
            0,
            0,
            1.0725293,
            0,
            0,
            0.7107167,
            0,
            -0.8032440,
            0,
            -90.5653038,
            0.15,
            -67.4221386,
            1,
        ],
    )
    _matrix(
        plan.hydrants[0],
        [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, -60.8535267, 0.15, -70.3, 1],
    )
    _matrix(
        plan.benches[0],
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -59.9772153, 0.15, -12.7, 1],
    )
    _matrix(
        plan.signals[0],
        [
            -0.7071068,
            0,
            0.7071068,
            0,
            0,
            1,
            0,
            0,
            -0.7071068,
            0,
            -0.7071068,
            0,
            -99.6,
            0.15,
            -69.6,
            1,
        ],
    )
    _matrix(
        plan.cans[0],
        [
            0.7071068,
            0,
            -0.7071068,
            0,
            0,
            1,
            0,
            0,
            0.7071068,
            0,
            0.7071068,
            0,
            -98.8,
            0.15,
            -68.8,
            1,
        ],
    )
    _matrix(
        plan.cars[0].matrix,
        [0, 0, 1, 0, 0, 1, 0, 0, -1, 0, 0, 0, -86.2, 0, -72.5, 1],
    )
    assert_equal(plan.cars[0].color, 0xF5C518)
    _matrix(
        plan.cars[130].matrix,
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 106.5, 0, 38, 1],
    )
    assert_equal(plan.cars[130].color, 0x3E4247)
    var taxis = 0
    for i in range(len(plan.cars)):
        taxis += 1 if plan.cars[i].color == 0xF5C518 else 0
    assert_equal(taxis, 27)


def test_a_one_lot_city_is_built() raises:
    """A one-lot city builds its tower, its furniture and no slab."""
    var generator = CityGenerator(_one_lot(35))
    var city = generator.build()
    ref plan = city.plan
    assert_equal(len(plan.slabs), 0)
    assert_equal(len(plan.towers), 1)
    ref tower = plan.towers[0]
    assert_equal(tower.parameters.seed, 88147)
    assert_almost_equal(tower.position.x, -0.4527250847779207, atol=1e-9)
    assert_almost_equal(tower.position.z, -0.5609898315044113, atol=1e-9)
    assert_almost_equal(
        tower.parameters.setback_depth, 2.0452710345387457, atol=1e-12
    )
    assert_equal(tower.parameters.string_course_every, 0)
    assert_equal(len(city.buildings), 1)
    assert_equal(city.buildings[0].vertex_count(), 23886)
    var at = city.building_matrix(0)
    assert_almost_equal(at.elements[12], -0.4527251, atol=1e-6)
    with assert_raises(contains="no tower"):
        _ = city.building_matrix(1)
    with assert_raises(contains="no tower"):
        _ = city.building_matrix(-1)
    assert_false(Bool(city.sidewalk))
    # Six kinds of furniture, the two poses, and the bodies the paints
    # deal: taxi, burgundy on a sedan or an SUV, bronze and white.
    assert_equal(city.furniture[0].name, "Streetlights")
    assert_equal(city.furniture[0].count(), 4)
    assert_equal(city.furniture[1].count(), 2)
    assert_equal(city.furniture[2].count(), 4)
    assert_equal(city.furniture[3].count(), 1)
    assert_equal(city.furniture[4].count(), 4)
    assert_equal(city.furniture[5].count(), 4)
    assert_equal(city.furniture[6].name, "People")
    assert_equal(city.furniture[6].count() + city.furniture[7].count(), 8)
    var cars = 0
    for i in range(8, len(city.furniture)):
        assert_equal(city.furniture[i].name, "Car")
        cars += city.furniture[i].count()
    assert_equal(cars, 8)
    _matrix(
        plan.trees[0],
        [
            1.0104943,
            0,
            -0.3023698,
            0,
            0,
            1.0547636,
            0,
            0,
            0.3023698,
            0,
            1.0104943,
            0,
            -2.5,
            0,
            -13.5,
            1,
        ],
    )
    var proxy = generator.build_proxy(plan)
    assert_equal(proxy.name, "CityProxy")
    assert_equal(proxy.count(), 1)
    assert_almost_equal(
        proxy.matrices[0].elements[5], 38.00633364903985, atol=1e-4
    )
    assert_almost_equal(
        proxy.matrices[0].elements[13], 19.003166824519926, atol=1e-4
    )
    assert_equal(generator.build_proxy(CityPlan(plan.layout)).count(), 0)


def test_a_curbed_city_is_built_on_slabs() raises:
    """With a curb, the built city stands on one slab a block, and the
    towers stand on the sidewalk."""
    var p = _one_lot(35)
    p.curb_height = Length(0.15, METER)
    var city = CityGenerator(p^).build()
    assert_true(Bool(city.sidewalk))
    assert_equal(city.sidewalk.value().slab.count(), 1)
    assert_equal(city.sidewalk.value().curb.count(), 1)
    assert_almost_equal(city.building_matrix(0).elements[13], 0.15, atol=1e-7)


def test_a_curb_raises_a_sidewalk() raises:
    """A curb puts a slab and a curb under every block."""
    var generator = CityGenerator()
    var sidewalk = generator.sidewalk()
    assert_equal(sidewalk.width.to(METER), 90)
    assert_equal(sidewalk.depth.to(METER), 60)
    assert_almost_equal(sidewalk.height.to(METER), 0.15, atol=1e-7)
    var slabs: List[Matrix4] = [Matrix4(), Matrix4()]
    var built = sidewalk.build(slabs)
    assert_equal(built.slab.count(), 2)
    assert_equal(built.curb.count(), 2)


def test_a_tiny_block_has_no_trees_or_cars() raises:
    """On a two-meter block a tree pit would sit in a corner, and no lane
    is long enough for a car."""
    var p = _one_lot(1)
    p.lot = Length(2, METER)
    p.sidewalk_width = Length(0.5, METER)
    var plan = CityGenerator(p^).plan()
    assert_equal(len(plan.trees), 0)
    assert_equal(len(plan.cars), 0)
    assert_equal(len(plan.lights), 4)
    assert_equal(len(plan.people), 5)
    assert_equal(len(plan.benches), 2)


def test_paints_follow_their_thresholds() raises:
    """A draw takes the first paint whose threshold it is under."""
    assert_equal(len(car_colors()), len(car_color_thresholds()))
    var random = generator_random(1)
    # Mulberry32 seeded with one draws 0.627 first: the silver.
    assert_equal(car_color(random), 0xB2B5B8)
    # Then 0.0027: the yellow cab.
    assert_equal(car_color(random), 0xF5C518)


def test_block_edges_face_the_road() raises:
    """The four edges run along the block with their normals out."""
    var edges = block_edges(-10, -5, 20, 10)
    assert_equal(len(edges), 4)
    assert_equal(edges[0].nz, -1)
    assert_equal(edges[1].z0, 5)
    assert_equal(edges[2].nx, -1)
    assert_equal(edges[3].x0, 10)
    assert_equal(edges[3].length, 10)
    var m = edges[3].on_walk(2, 1, 0.15)
    assert_equal(m.elements[12], 9)
    assert_equal(m.elements[14], -3)


def test_city_parameters_are_checked() raises:
    """A city needs a block and a lot each way, and sizes."""
    var p = CityParameters()
    p.lots_x = 0
    with assert_raises(contains="one block"):
        _ = city_layout(p)
    p = CityParameters()
    p.lots_z = 0
    with assert_raises(contains="one block"):
        _ = city_layout(p)
    p = CityParameters()
    p.blocks_x = 0
    with assert_raises(contains="one block"):
        _ = city_layout(p)
    p = CityParameters()
    p.blocks_z = 0
    with assert_raises(contains="one block"):
        _ = city_layout(p)
    p = CityParameters()
    p.lot = Length(0, METER)
    with assert_raises(contains="lot must be positive"):
        _ = city_layout(p)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
