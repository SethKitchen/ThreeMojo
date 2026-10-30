# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A swing's trail and a blow's sparks."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.village.combat import (
    DODGE,
    FREE,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    RISING_EDGE,
    TEMPEST,
    CombatMove,
    Fighter,
    FighterParameters,
)
from extensions.village.sheet import Sheet
from extensions.village.slashes import (
    PLAYER_TRAIL,
    SPARKS,
    SPARK_SECONDS,
    Sparks,
    Trail,
    arc,
    slash_material,
    spark_sheet,
    trail_sheet,
)
from materials.material import BASIC
from math.vector3 import Vector3
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import SECOND, Duration


def test_a_ribbon_sweeps_its_arc() raises:
    var sheet = Sheet(1)
    arc(
        sheet,
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 0, 1),
        0,
        Float32(pi),
        1,
        2,
        Vector3(1, 1, 1),
    )
    # A half turn takes eighteen quads; a sliver takes two.
    assert_equal(sheet.triangles(), 36)
    var sliver = Sheet(1)
    arc(
        sliver,
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 0, 1),
        0,
        0.01,
        1,
        2,
        Vector3(1, 1, 1),
    )
    assert_equal(sliver.triangles(), 4)
    # Each attack has a ribbon, and nothing else does.
    assert_equal(trail_sheet(FREE, 1, PLAYER_TRAIL).triangles(), 0)
    assert_equal(trail_sheet(DODGE, 1, PLAYER_TRAIL).triangles(), 0)
    var moves: List[CombatMove] = [
        LIGHT_ONE,
        LIGHT_TWO,
        LIGHT_THREE,
        HEAVY,
        RISING_EDGE,
        TEMPEST,
    ]
    for move in moves:
        assert_true(trail_sheet(move, 1, PLAYER_TRAIL).triangles() > 0)
    # The first cut is higher than the second.
    var one = trail_sheet(LIGHT_ONE, 1, PLAYER_TRAIL)
    var two = trail_sheet(LIGHT_TWO, 1, PLAYER_TRAIL)
    assert_true(one.positions[1] > two.positions[1])
    assert_equal(spark_sheet().triangles(), 108)


def test_a_trail_shows_while_its_move_strikes() raises:
    var assets = Assets()
    var scene = Scene()
    var glow = slash_material(assets)
    assert_true(assets.materials.get(glow).kind == BASIC)
    assert_true(assets.materials.get(glow).transparent)
    var carrier = scene.add(Object3D())
    var trail = Trail(scene, assets, glow, carrier, 1, PLAYER_TRAIL)
    assert_equal(len(scene.meshes), 6)
    assert_false(trail.ribbons[FREE.value])
    var fighter = Fighter(FighterParameters())
    trail.show(scene, fighter)
    assert_equal(trail.shown, -1)
    _ = fighter.press_light()
    fighter.clock = 0.1
    trail.show(scene, fighter)
    assert_equal(trail.shown, -1)
    fighter.clock = 0.2
    trail.show(scene, fighter)
    assert_equal(trail.shown, LIGHT_ONE.value)
    var node = trail.ribbons[LIGHT_ONE.value].value()
    assert_true(scene.node(node).visible)
    trail.show(scene, fighter)
    fighter.clock = 0.45
    trail.show(scene, fighter)
    assert_equal(trail.shown, -1)
    assert_false(scene.node(node).visible)
    # The tempest's ribbon turns with the body.
    var spinner = Fighter(FighterParameters())
    _ = spinner.request(TEMPEST)
    spinner.clock = 0.4
    trail.show(scene, spinner)
    var ring = trail.ribbons[TEMPEST.value].value()
    assert_true(scene.node(ring).visible)
    assert_true(abs(scene.node(ring).quaternion.w) < 0.99)


def test_sparks_burst_grow_and_go() raises:
    var assets = Assets()
    var scene = Scene()
    var sparks = Sparks(scene, assets, slash_material(assets))
    assert_equal(len(sparks.nodes), SPARKS)
    sparks.burst(scene, Vector3(1, 2, 3))
    ref first = scene.node(sparks.nodes[0])
    assert_true(first.visible)
    assert_almost_equal(first.position.y, 2, atol=1e-6)
    sparks.update(scene, Duration(SPARK_SECONDS / 2, SECOND))
    assert_almost_equal(scene.node(sparks.nodes[0]).scale.x, 1.25, atol=1e-4)
    sparks.update(scene, Duration(SPARK_SECONDS, SECOND))
    assert_false(scene.node(sparks.nodes[0]).visible)
    # The bursts are used in turn.
    for _ in range(SPARKS):
        sparks.burst(scene, Vector3(0, 0, 0))
    assert_equal(sparks.next, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
