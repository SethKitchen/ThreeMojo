# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the trees of the domain: the shapes that are grown, the autumn
tints, and the planting of trees and shrubs round the moat.

The textures are the smallest the look allows, so a test spends its time on
the trees.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.castle.look import CastleLook, castle_look
from extensions.castle.trees import (
    _autumn,
    _cards,
    _side,
    _unit_or,
    broadleaf,
    bush,
    conifer,
    plant_bushes,
    plant_trees,
)
from extensions.castle.wijnendale import wijnendale_plan
from generators.tree import TreeTube
from generators.utils import Vec3d
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


struct _Garden(Movable):
    """An empty scene, its stores, and a look with the smallest textures."""

    var scene: Scene
    var assets: Assets
    var look: CastleLook
    var node: NodeId

    def __init__(out self) raises:
        self.scene = Scene()
        self.assets = Assets()
        self.look = castle_look(self.assets, 16)
        self.node = self.scene.add(Object3D())


def test_a_vector_with_no_length_takes_the_fallback() raises:
    var up = Vec3d(0, 1, 0)
    var none = _unit_or(Vec3d(0, 0, 0), up)
    assert_almost_equal(none.y, 1.0, atol=1.0e-12)
    var long = _unit_or(Vec3d(3, 0, 0), up)
    assert_almost_equal(long.x, 1.0, atol=1.0e-12)
    # Parallel arguments have no side, and the east axis stands in.
    var east = _side(Vec3d(0, 1, 0), Vec3d(0, 1, 0))
    assert_almost_equal(east.x, 1.0, atol=1.0e-12)
    var across = _side(Vec3d(0, 0, 1), Vec3d(0, 1, 0))
    assert_almost_equal(across.x, -1.0, atol=1.0e-12)


def test_the_autumn_has_six_tints() raises:
    var seen = List[Int]()
    for index in range(6):
        var tint = _autumn((Float64(index) + 0.5) / 6.0, 1.0)
        var key = Int(tint.r) * 65536 + Int(tint.g) * 256 + Int(tint.b)
        assert_true(key not in seen)
        seen.append(key)
    # A darker shade scales the tint.
    assert_true(_autumn(0.05, 0.5).r < _autumn(0.05, 1.0).r)


def test_a_broadleaf_has_bark_and_a_crown_of_cards() raises:
    var near = broadleaf(3, 1.0)
    var far = broadleaf(3, 0.4)
    assert_true(near.bark.triangle_count() > 100)
    assert_true(near.leaves.triangle_count() > 100)
    assert_true(near.height > 10.0)
    # A tree far away is grown with fewer boughs.
    assert_true(far.bark.triangle_count() < near.bark.triangle_count())


def test_a_conifer_is_taller_and_narrower() raises:
    var near = conifer(2, 1.0)
    var far = conifer(2, 0.4)
    assert_true(near.height > 20.0)
    assert_true(near.leaves.triangle_count() > 100)
    assert_true(far.bark.triangle_count() < near.bark.triangle_count())


def test_a_skeleton_with_no_thin_end_has_no_cards() raises:
    var found = _cards(List[TreeTube](), 1, 1.0, 5, 0.1, 1, False)
    assert_equal(found[0].triangle_count(), 0)
    assert_almost_equal(found[1], 1.0, atol=1.0e-12)


def test_a_bush_is_a_ball_of_cards() raises:
    var geometry = bush(1, 1.5, 1.8)
    assert_equal(geometry.triangle_count(), 220)


def test_the_woods_are_planted_round_the_moat() raises:
    var garden = _Garden()
    var all = plant_trees(
        garden.scene,
        garden.assets,
        garden.look,
        wijnendale_plan(),
        garden.node,
        0.0,
        0.0,
        0.0,
    )
    assert_true(all > 100)
    assert_true(len(garden.scene.instanced_meshes) >= 2)


def test_a_place_to_keep_clear_loses_the_trees_round_it() raises:
    var garden = _Garden()
    # Every tree of the woods is within 100 km, so only the garden is left.
    var few = plant_trees(
        garden.scene,
        garden.assets,
        garden.look,
        wijnendale_plan(),
        garden.node,
        0.0,
        0.0,
        1.0e5,
    )
    assert_equal(few, 2)
    assert_equal(len(garden.scene.instanced_meshes), 4)


def test_the_shrubs_are_planted_along_the_bank() raises:
    var garden = _Garden()
    var plan = wijnendale_plan()
    var some = plant_bushes(
        garden.scene, garden.assets, garden.look, plan, garden.node
    )
    assert_true(some > 20)
    var bare = _Garden()
    var none = plant_bushes(
        bare.scene, bare.assets, bare.look, plan, bare.node, gap=1.0
    )
    assert_equal(none, 0)
    assert_equal(len(bare.scene.instanced_meshes), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
