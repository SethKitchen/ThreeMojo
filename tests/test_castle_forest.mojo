# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the woods of a landscape: the settings, the tier a tree is
drawn in, the sector that a camera sees, the tints, and the planting of a
meadow, with clearings and a narrow view.

The meadow is level and dry, so every tree that is not planted is left out
by a rule of the woods and not by the ground.
"""

from core.object3d import Object3D
from core.scene import Scene
from core.assets import Assets
from extensions.castle.forest import (
    Clearing,
    ForestSettings,
    _color_of,
    _in_view,
    _mute,
    _tier_at,
    default_forest,
    plant_forest,
)
from extensions.castle.look import castle_look
from render.framebuffer import Color
from std.math import nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.castle.landscape import Landscape
from tests._castle_land import meadow, plateau
from units.si import Length64


def test_the_defaults_plant_all_round() raises:
    var settings = default_forest()
    settings.check()
    assert_almost_equal(settings.hero.value, 110.0)
    assert_almost_equal(settings.far.value, 2600.0)
    assert_almost_equal(settings.half_view, pi)


def test_the_distances_must_grow() raises:
    var none = default_forest()
    none.hero = Length64(0.0)
    with assert_raises(contains="must grow"):
        none.check()
    var close = default_forest()
    close.near = Length64(100.0)
    with assert_raises(contains="must grow"):
        close.check()
    var middle = default_forest()
    middle.mid = Length64(300.0)
    with assert_raises(contains="must grow"):
        middle.check()
    var last = default_forest()
    last.far = Length64(1000.0)
    with assert_raises(contains="must grow"):
        last.check()


def test_the_view_and_the_keep_must_make_sense() raises:
    var blind = default_forest()
    blind.half_view = 0.0
    with assert_raises(contains="half view"):
        blind.check()
    var keep = default_forest()
    keep.keep_radius = -1.0
    with assert_raises(contains="half view"):
        keep.check()
    var lost = default_forest()
    lost.eye_x = nan[DType.float64]()
    with assert_raises(contains="numbers"):
        lost.check()
    lost = default_forest()
    lost.eye_y = nan[DType.float64]()
    with assert_raises(contains="numbers"):
        lost.check()
    lost = default_forest()
    lost.heading = nan[DType.float64]()
    with assert_raises(contains="numbers"):
        lost.check()


def test_a_tree_is_drawn_in_the_tier_its_distance_asks() raises:
    var settings = default_forest()
    assert_equal(_tier_at(settings, 50.0), 0)
    assert_equal(_tier_at(settings, 200.0), 1)
    assert_equal(_tier_at(settings, 800.0), 2)
    assert_equal(_tier_at(settings, 2000.0), 3)
    assert_equal(_tier_at(settings, 5000.0), -1)


def test_only_the_sector_that_the_camera_sees_is_planted() raises:
    var settings = default_forest()
    settings.heading = 0.0
    settings.half_view = 0.5
    # Close to the eye, every way. In the sector. Out of it, on both sides.
    assert_true(_in_view(settings, 0.0, 40.0))
    assert_true(_in_view(settings, 500.0, 100.0))
    assert_true(not _in_view(settings, 500.0, 400.0))
    assert_true(not _in_view(settings, 500.0, -400.0))
    # The angle wraps round: a camera that looks nearly west sees the point
    # that is nearly west on the other side of the cut.
    settings.heading = -3.0
    assert_true(_in_view(settings, -500.0, 50.0))
    settings.heading = 3.0
    assert_true(_in_view(settings, -500.0, -50.0))


def test_each_kind_of_tree_has_its_tint() raises:
    var broad = _color_of(0, 0.05, 0.5, 0.0)
    var spruce = _color_of(1, 0.05, 0.5, 0.0)
    var fir = _color_of(2, 0.05, 0.5, 0.0)
    var larch = _color_of(3, 0.05, 0.5, 0.0)
    # Autumn broadleaf is warm, spruce green, fir bluer, and larch gold.
    assert_true(broad.r > broad.b)
    assert_true(spruce.g > spruce.r and spruce.g > spruce.b)
    assert_true(fir.b > spruce.b)
    assert_true(larch.r > larch.b and larch.g > larch.b)
    # A regional drift moves the autumn tint, and wraps.
    var drifted = _color_of(0, 0.9, 0.5, 0.9)
    assert_true(
        drifted.r != broad.r or drifted.g != broad.g or drifted.b != broad.b
    )


def test_air_mutes_a_color_toward_gray() raises:
    var vivid = Color(240, 90, 30)
    var quiet = _mute(vivid, 0.5)
    assert_true(quiet.r < vivid.r)
    assert_true(quiet.b > vivid.b)
    var same = _mute(vivid, 0.0)
    assert_equal(Int(same.r), 240)
    assert_equal(Int(same.g), 90)


def _planted_on(
    land: Landscape, settings: ForestSettings, clearings: List[Clearing]
) raises -> List[Int]:
    """Plant a ground and return the number of trees, then of instanced
    meshes."""
    var scene = Scene()
    var assets = Assets()
    var look = castle_look(assets, 16)
    var node = scene.add(Object3D())
    var trees = plant_forest(
        scene, assets, look, land, node, settings, clearings
    )
    return [trees, len(scene.instanced_meshes)]


def _planted(
    settings: ForestSettings, clearings: List[Clearing]
) raises -> List[Int]:
    """Plant the meadow and return the number of trees, then of instanced
    meshes."""
    return _planted_on(meadow(), settings, clearings)


def test_a_meadow_is_planted_by_distance_and_a_view_plants_less() raises:
    var settings = default_forest()
    settings.eye_x = -300.0
    settings.eye_y = -300.0
    settings.keep_radius = 20.0
    var everywhere = _planted(settings, List[Clearing]())
    # Many trees, in more than one shape, for every tier.
    assert_true(everywhere[0] > 300)
    assert_true(everywhere[1] >= 8)
    var narrow = default_forest()
    narrow.eye_x = -300.0
    narrow.eye_y = -300.0
    narrow.keep_radius = 20.0
    narrow.heading = 0.78
    narrow.half_view = 0.3
    var seen = _planted(narrow, List[Clearing]())
    assert_true(seen[0] > 0)
    assert_true(seen[0] < everywhere[0])


def test_a_clearing_and_a_keep_leave_no_tree() raises:
    var settings = default_forest()
    settings.eye_x = -300.0
    settings.eye_y = -300.0
    settings.keep_radius = 20.0
    var cleared = List[Clearing]()
    cleared.append(Clearing(-300.0, -300.0, 9000.0))
    var none = _planted(settings, cleared)
    assert_equal(none[0], 0)
    assert_equal(none[1], 0)
    settings.keep_radius = 9000.0
    var kept = _planted(settings, List[Clearing]())
    assert_equal(kept[0], 0)


def test_a_cliff_has_no_trees_and_high_ground_has_larch_and_fir() raises:
    var settings = default_forest()
    settings.eye_x = 0.0
    settings.eye_y = 0.0
    settings.keep_radius = 0.0
    # The ramp of the plateau is steeper than a tree can stand on.
    var cliff = _planted_on(plateau(), settings, List[Clearing]())
    assert_true(cliff[0] > 0)
    # A meadow 150 m over the water is conifer country, and larch grows here.
    var high = _planted_on(meadow(150.0), settings, List[Clearing]())
    assert_true(high[0] > 0)
    assert_true(high[1] > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
