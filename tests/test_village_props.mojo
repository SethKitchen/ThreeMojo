# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's props: their kinds, their checks, what they draw and
what of them stops a character."""

from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.ground import Ground
from extensions.village.props import (
    BARREL,
    BENCH,
    CRATE,
    FENCE,
    FENCE_HEIGHT,
    HAY_BALE,
    Prop,
    PropKind,
    WELL,
    WOODPILE,
    WOODPILE_DEPTH,
    stand_props,
)
from extensions.village.surfaces import house_looks
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Angle, Length


def _flat() raises -> Ground:
    """Return level ground with no pond."""
    return Ground(hill_height=Length(0.0, METER))


def test_a_prop_kind_is_one_of_seven() raises:
    for kind in [WELL, BARREL, CRATE, HAY_BALE, FENCE, BENCH, WOODPILE]:
        assert_true(kind.is_valid())
    assert_false(PropKind(7).is_valid())
    assert_false(PropKind(-1).is_valid())


def test_a_prop_that_cannot_be_drawn_is_refused() raises:
    var turn = Angle(0.0, DEGREE)
    Prop(WELL, 0, 0, turn, 0.8).check()
    with assert_raises(contains="kind"):
        Prop(PropKind(9), 0, 0, turn, 1).check()
    with assert_raises(contains="10 kilometers"):
        Prop(CRATE, 2.0e4, 0, turn, 1).check()
    with assert_raises(contains="10 kilometers"):
        Prop(CRATE, 0, -2.0e4, turn, 1).check()
    with assert_raises(contains="long"):
        Prop(CRATE, 0, 0, turn, 0.1).check()
    with assert_raises(contains="long"):
        Prop(FENCE, 0, 0, turn, 60).check()
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    with assert_raises(contains="kind"):
        _ = stand_props(
            scene, assets, looks, [Prop(PropKind(7), 0, 0, turn, 1)], _flat()
        )


def test_every_kind_stands_and_stops_a_character() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    var turn = Angle(30.0, DEGREE)
    var props: List[Prop] = [
        Prop(WELL, 0, 0, turn, 0.8),
        Prop(BARREL, 3, 0, turn, 0.3),
        Prop(CRATE, 5, 0, turn, 0.6),
        Prop(HAY_BALE, 7, 0, turn, 1.2),
        Prop(FENCE, 0, 6, Angle(0.0, DEGREE), 5),
        Prop(BENCH, 10, 0, turn, 1.6),
        Prop(WOODPILE, 13, 0, turn, 1.8),
    ]
    var standing = stand_props(scene, assets, looks, props, _flat())
    # Wood, stone, hay and the well's roof tiles: one mesh each.
    assert_equal(standing.meshes, 4)
    assert_equal(len(scene.meshes), 4)
    assert_true(standing.triangles > 300)
    assert_equal(len(standing.lots), 6)
    assert_equal(len(standing.walls), 1)
    # A well's and a barrel's footprint reach past their radius; a bale is
    # half as deep as it is long, and a bench is narrow.
    assert_almost_equal(standing.lots[0].half_width, 0.95, atol=1e-5)
    assert_almost_equal(standing.lots[1].half_depth, 0.45, atol=1e-5)
    assert_almost_equal(standing.lots[2].half_depth, 0.3, atol=1e-5)
    assert_almost_equal(standing.lots[3].half_depth, 0.3, atol=1e-5)
    assert_almost_equal(standing.lots[4].half_depth, 0.18, atol=1e-5)
    assert_almost_equal(standing.lots[4].half_width, 0.8, atol=1e-5)
    # A woodpile is as deep as `WOODPILE_DEPTH`.
    assert_almost_equal(standing.lots[5].half_width, 0.9, atol=1e-5)
    assert_almost_equal(
        standing.lots[5].half_depth, WOODPILE_DEPTH / 2, atol=1e-5
    )
    # A fence is a wall as long as the fence, as tall as a fence.
    ref fence = standing.walls[0]
    assert_almost_equal(fence.x0, -2.5, atol=1e-5)
    assert_almost_equal(fence.x1, 2.5, atol=1e-5)
    assert_almost_equal(fence.top - fence.bottom, FENCE_HEIGHT + 0.1, atol=1e-5)
    assert_true(fence.blocks(0, 1.5))


def test_a_woodpile_shows_the_ends_of_its_logs() raises:
    """A woodpile is a stack, a lid, and an octagon of eight triangles for
    each log's end, in rows across its front."""
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    var turn = Angle(0.0, DEGREE)
    var short = stand_props(
        scene, assets, looks, [Prop(WOODPILE, 0, 0, turn, 0.6)], _flat()
    )
    var other = Scene()
    var long = stand_props(
        other, assets, looks, [Prop(WOODPILE, 0, 0, turn, 1.2)], _flat()
    )
    # Twice as long: twice as many logs across, each of eight triangles,
    # with the same two boxes.
    var ends_short = short.triangles - 24
    var ends_long = long.triangles - 24
    assert_equal(ends_short % 8, 0)
    assert_equal(ends_long, 2 * ends_short)
    assert_true(ends_short >= 8 * 4 * 8)


def test_a_lone_barrel_draws_one_mesh_and_none_draws_none() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    var barrel = stand_props(
        scene,
        assets,
        looks,
        [Prop(BARREL, 0, 0, Angle(0.0, DEGREE), 0.3)],
        _flat(),
    )
    assert_equal(barrel.meshes, 1)
    var bare = Scene()
    var none = stand_props(bare, assets, looks, List[Prop](), _flat())
    assert_equal(none.meshes, 0)
    assert_equal(none.triangles, 0)
    assert_equal(len(bare.meshes), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
