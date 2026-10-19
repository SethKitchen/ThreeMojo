# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the render view of `extensions.castle`.

The references are the plan's own numbers: the highest vertex stands at the
top of the keep and its merlons, and the water stands at the freeboard below
the ground. The rest are counts: one mesh for each surface that has
triangles, the same seed giving the same colors, and an option leaving a
part out.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from core.assets import Assets
from core.buffer_geometry import COLOR, POSITION
from core.scene import Scene
from extensions.castle.kinds import (
    BRICK,
    CONE,
    FOLIAGE,
    GRAVEL,
    LAWN,
    PARAPET,
    SLATE,
    SQUARE,
    STONE,
    Surface,
    TRUNK,
    WATER,
)
from extensions.castle.plan import Block, PlanPoint, wijnendale
from extensions.castle.render import (
    CastleOptions,
    add_castle,
    foliage_color,
    surface_color,
)
from std.math import pi
from units.si import Length64, METER


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _few_trees() -> CastleOptions:
    var options = CastleOptions.default()
    options.trees = 40
    return options


def test_one_mesh_for_each_surface_with_triangles() raises:
    var assets = Assets()
    var scene = Scene()
    var plan = wijnendale()
    var castle = add_castle(scene, assets, plan, _few_trees())
    assert_equal(castle.meshes, 8)
    assert_equal(len(scene.meshes), 8)
    assert_true(castle.triangles > 8000)
    assert_equal(scene.node(castle.root).name, "Wijnendale Castle")
    assert_true(scene.node(castle.root).user_data.has("dropped"))


def test_the_surfaces_are_named_in_order() raises:
    var assets = Assets()
    var scene = Scene()
    var castle = add_castle(scene, assets, wijnendale(), _few_trees())
    var names: List[String] = [
        "brick",
        "stone",
        "slate",
        "water",
        "lawn",
        "gravel",
        "trunk",
        "foliage",
    ]
    for k in range(8):
        var node = scene.meshes[k].node
        assert_equal(scene.node(node).name, names[k])


def test_the_highest_vertex_is_the_top_of_the_keep() raises:
    var assets = Assets()
    var scene = Scene()
    var plan = wijnendale()
    var options = _few_trees()
    options.trees = 0
    _ = add_castle(scene, assets, plan, options)
    var top = Float32(-1000.0)
    for m in range(len(scene.meshes)):
        ref position = assets.geometries.get(
            scene.meshes[m].geometry
        ).attribute_view(String(POSITION))
        for v in range(len(position.data) // 3):
            top = max(top, position.data[3 * v + 1])
    # The keep is 28 m to its parapet floor and its merlons add 1.2 m.
    assert_almost_equal(top, 29.2, atol=1e-3)
    assert_true(Float64(top) >= plan.tallest().value)


def test_the_water_stands_at_the_freeboard() raises:
    var assets = Assets()
    var scene = Scene()
    var plan = wijnendale()
    _ = add_castle(scene, assets, plan, _few_trees())
    ref position = assets.geometries.get(
        scene.meshes[3].geometry
    ).attribute_view(String(POSITION))
    assert_true(len(position.data) > 0)
    for v in range(len(position.data) // 3):
        assert_almost_equal(
            position.data[3 * v + 1], -Float32(plan.moat.freeboard.value)
        )


def test_the_water_ring_lies_between_the_island_and_the_bank() raises:
    var assets = Assets()
    var scene = Scene()
    var plan = wijnendale()
    _ = add_castle(scene, assets, plan, _few_trees())
    ref position = assets.geometries.get(
        scene.meshes[3].geometry
    ).attribute_view(String(POSITION))
    var low_x = Float32(1000.0)
    var high_x = Float32(-1000.0)
    for v in range(len(position.data) // 3):
        low_x = min(low_x, position.data[3 * v])
        high_x = max(high_x, position.data[3 * v])
    # The outer circle is centered on x = 4 with a radius of 46 m.
    assert_almost_equal(high_x, 50.0, atol=0.05)
    assert_almost_equal(low_x, -42.0, atol=0.05)


def test_the_same_seed_gives_the_same_colors() raises:
    var colors = List[List[Float32]]()
    for seed in [7, 7, 8]:
        var assets = Assets()
        var scene = Scene()
        var options = _few_trees()
        options.seed = seed
        _ = add_castle(scene, assets, wijnendale(), options)
        ref color = assets.geometries.get(
            scene.meshes[0].geometry
        ).attribute_view(String(COLOR))
        colors.append(color.data.copy())
    assert_equal(len(colors[0]), len(colors[1]))
    var same = True
    var different = False
    for i in range(len(colors[0])):
        if colors[0][i] != colors[1][i]:
            same = False
        if colors[0][i] != colors[2][i]:
            different = True
    assert_true(same)
    assert_true(different)


def test_options_leave_parts_out() raises:
    var plan = wijnendale()
    var options = _few_trees()
    options.water = False
    var assets = Assets()
    var scene = Scene()
    var no_water = add_castle(scene, assets, plan, options)
    assert_equal(no_water.meshes, 7)
    options = _few_trees()
    options.shadows = False
    assets = Assets()
    scene = Scene()
    _ = add_castle(scene, assets, plan, options)
    for m in range(len(scene.meshes)):
        assert_false(scene.meshes[m].cast_shadow)
        assert_false(scene.meshes[m].receive_shadow)
    options = _few_trees()
    assets = Assets()
    scene = Scene()
    _ = add_castle(scene, assets, plan, options)
    assert_true(scene.meshes[0].cast_shadow)
    assert_true(scene.meshes[0].receive_shadow)
    # The water receives shadows and casts none.
    assert_false(scene.meshes[3].cast_shadow)
    assert_true(scene.meshes[3].receive_shadow)


def test_a_clearing_keeps_trees_away() raises:
    var plan = wijnendale()
    var options = _few_trees()
    options.clearing = PlanPoint(_m(0.0), _m(0.0))
    options.clearing_radius = _m(1.0e6)
    var assets = Assets()
    var scene = Scene()
    var bare = add_castle(scene, assets, plan, options)
    # No trunk and no foliage: two meshes fewer.
    assert_equal(bare.meshes, 6)
    options.clearing_radius = _m(0.0)
    assets = Assets()
    scene = Scene()
    assert_equal(add_castle(scene, assets, plan, options).meshes, 8)


def test_more_trees_make_more_triangles() raises:
    var plan = wijnendale()
    var counts = List[Int]()
    for trees in [0, 100]:
        var options = _few_trees()
        options.trees = trees
        var assets = Assets()
        var scene = Scene()
        counts.append(add_castle(scene, assets, plan, options).triangles)
    assert_true(counts[1] > counts[0] + 1000)


def test_a_square_tower_is_drawn() raises:
    var plan = wijnendale()
    plan.towers[1].shape = SQUARE
    plan.towers[2].shape = SQUARE
    plan.towers[2].radius = _m(2.2)
    var options = _few_trees()
    options.trees = 0
    var assets = Assets()
    var scene = Scene()
    var square = add_castle(scene, assets, plan, options)
    assert_equal(plan.towers[1].roof, PARAPET)
    assert_equal(plan.towers[2].roof, CONE)
    var round_plan = wijnendale()
    assets = Assets()
    scene = Scene()
    var round = add_castle(scene, assets, round_plan, options)
    assert_true(square.triangles != round.triangles)


def test_a_plan_without_blocks_is_drawn() raises:
    var plan = wijnendale()
    plan.blocks = List[Block]()
    var options = _few_trees()
    options.trees = 0
    var assets = Assets()
    var scene = Scene()
    var castle = add_castle(scene, assets, plan, options)
    assert_true(castle.triangles > 3000)
    assert_true(castle.triangles < 5000)


def test_a_narrow_block_still_gets_a_window() raises:
    var plan = wijnendale()
    plan.blocks[0].width = _m(3.0)
    plan.blocks[0].wall = _m(1.0)
    plan.blocks[0].length = _m(5.0)
    var options = _few_trees()
    options.trees = 0
    var assets = Assets()
    var scene = Scene()
    var castle = add_castle(scene, assets, plan, options)
    assert_true(castle.triangles > 5000)


def test_refuses_what_it_cannot_draw() raises:
    var assets = Assets()
    var scene = Scene()
    var options = _few_trees()
    options.sides = 5
    with assert_raises(contains="at least six facets"):
        _ = add_castle(scene, assets, wijnendale(), options)
    options = _few_trees()
    options.trees = -1
    with assert_raises(contains="fewer than no trees"):
        _ = add_castle(scene, assets, wijnendale(), options)
    var plan = wijnendale()
    plan.towers[0].radius = _m(0.0)
    with assert_raises(contains="A tower radius must be positive"):
        _ = add_castle(scene, assets, plan, _few_trees())


def test_surface_colors_are_linear_and_distinct() raises:
    var seen = List[Float64]()
    for k in range(8):
        var c = surface_color(Surface(k))
        assert_true(c.x >= 0.0 and c.x <= 1.0)
        assert_true(c.y >= 0.0 and c.y <= 1.0)
        assert_true(c.z >= 0.0 and c.z <= 1.0)
        seen.append(c.x * 1000.0 + c.y * 100.0 + c.z)
    for i in range(8):
        for j in range(i + 1, 8):
            assert_true(abs(seen[i] - seen[j]) > 1e-6)
    var gray = surface_color(Surface(99))
    assert_almost_equal(gray.x, gray.y)
    assert_almost_equal(gray.y, gray.z)
    # Brick is red: red above blue, in linear light.
    assert_true(surface_color(BRICK).x > surface_color(BRICK).z * 2.0)
    assert_true(surface_color(SLATE).z > surface_color(SLATE).x)


def test_foliage_has_six_colors() raises:
    for k in range(6):
        var c = foliage_color(k)
        assert_true(c.x >= 0.0 and c.x <= 1.0)
        assert_almost_equal(foliage_color(k + 6).x, c.x)
    # Index 4 is the conifer: green over red.
    assert_true(foliage_color(4).y > foliage_color(4).x)
    # Index 0 is orange: red over green over blue.
    assert_true(foliage_color(0).x > foliage_color(0).y)
    assert_true(foliage_color(0).y > foliage_color(0).z)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
