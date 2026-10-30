# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A swing's trail, drawn as light over the frame, and a blow's sparks."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.village.combat import (
    BURST,
    DEMON_FANG,
    DODGE,
    FREE,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    MYSTIC_ARTE,
    THROW,
    PLUNGE,
    RISING_EDGE,
    TEMPEST,
    CombatMove,
    Fighter,
    FighterParameters,
)
from extensions.village.slashes import (
    BURST_TRAIL,
    PLAYER_TRAIL,
    SPARKS,
    SPARK_SECONDS,
    Sparks,
    Trail,
    arc_points,
    draw_ring,
    draw_wave,
    glow_ribbon,
    glow_star,
    glow_triangle,
    slash_material,
    spark_sheet,
    trail_points,
)
from materials.material import BASIC
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length


def _light(frame: Framebuffer) -> Int:
    """Return how bright a frame is: its color bytes, added."""
    var sum = 0
    for k in range(len(frame.pixels)):
        if k % 4 != 3:
            sum += Int(frame.pixels[k])
    return sum


def test_a_ribbon_sweeps_its_arc() raises:
    var x = Vector3(1, 0, 0)
    var z = Vector3(0, 0, 1)
    # A half turn takes eighteen steps; a sliver takes two.
    var half = arc_points(Vector3(0, 0, 0), x, z, 0, Float32(pi), 1, 2)
    assert_equal(len(half), 38)
    assert_almost_equal(half[1].x, 2, atol=1e-5)
    assert_almost_equal(half[37].x, -2, atol=1e-5)
    assert_equal(len(arc_points(Vector3(0, 0, 0), x, z, 0, 0.01, 1, 2)), 6)
    # Each attack has a ribbon, and nothing else does.
    assert_equal(len(trail_points(FREE, 1)), 0)
    assert_equal(len(trail_points(DODGE, 1)), 0)
    var moves: List[CombatMove] = [
        LIGHT_ONE,
        LIGHT_TWO,
        LIGHT_THREE,
        HEAVY,
        RISING_EDGE,
        TEMPEST,
        DEMON_FANG,
        BURST,
        MYSTIC_ARTE,
        PLUNGE,
    ]
    for move in moves:
        assert_true(len(trail_points(move, 1)) > 0)
    # The first cut starts on the sword's side, minus x, and higher; the
    # second starts on the other side.
    var one = trail_points(LIGHT_ONE, 1)
    var two = trail_points(LIGHT_TWO, 1)
    assert_true(one[0].x < 0)
    assert_true(two[0].x > 0)
    assert_true(one[0].y > two[0].y)
    assert_equal(spark_sheet().triangles(), 108)


def test_light_adds_over_a_triangle() raises:
    var frame = Framebuffer(20, 20, Color(0, 0, 0))
    # A flat triangle adds nothing.
    glow_triangle(
        frame,
        Vector3(1, 1, 1),
        Vector3(5, 5, 1),
        Vector3(9, 9, 1),
        PLAYER_TRAIL,
    )
    assert_equal(_light(frame), 0)
    # One above the frame, or left of it, adds nothing.
    glow_triangle(
        frame,
        Vector3(1, -9, 1),
        Vector3(9, -9, 1),
        Vector3(5, -2, 1),
        PLAYER_TRAIL,
    )
    glow_triangle(
        frame,
        Vector3(-9, 1, 1),
        Vector3(-9, 9, 1),
        Vector3(-2, 5, 1),
        PLAYER_TRAIL,
    )
    assert_equal(_light(frame), 0)
    # One that runs off the frame adds light where it lies on it.
    glow_triangle(
        frame,
        Vector3(-5, -5, 1),
        Vector3(30, 0, 1),
        Vector3(0, 30, 0),
        PLAYER_TRAIL,
    )
    var once = _light(frame)
    assert_true(once > 0)
    # Light adds up, and stops at white.
    for _ in range(4):
        glow_triangle(
            frame,
            Vector3(-5, -5, 1),
            Vector3(30, 0, 1),
            Vector3(0, 30, 1),
            Vector3(255, 255, 255),
        )
    assert_equal(Int(frame.pixels[0]), 255)


def _camera(eye: Vector3) raises -> PerspectiveCamera:
    """Return a camera at `eye` looking along +z."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, Length(0.1, METER), Length(50.0, METER)
    )
    camera.place(eye, eye + Vector3(0, -0.3, 4))
    return camera^


def test_a_trail_grows_with_the_swing_and_fades() raises:
    var scene = Scene()
    var carrier = scene.add(Object3D())
    var trail = Trail(scene, carrier, 1, PLAYER_TRAIL)
    assert_false(trail.nodes[FREE.value])
    assert_true(trail.nodes[LIGHT_ONE.value])
    var fighter = Fighter(FighterParameters())
    trail.show(scene, fighter)
    assert_equal(trail.shown, -1)
    _ = fighter.press_light()
    fighter.clock = 0.1
    trail.show(scene, fighter)
    assert_equal(trail.shown, -1)
    fighter.clock = 0.19
    trail.show(scene, fighter)
    assert_equal(trail.shown, LIGHT_ONE.value)
    assert_almost_equal(trail.sweep, 0.5, atol=1e-4)
    assert_almost_equal(trail.glow, 1, atol=1e-6)
    # Half swept, it adds light before the camera, and none behind it.
    scene.update()
    var look = Vector3(0, -0.3, 4) / Vector3(0, -0.3, 4).length()
    var before = Framebuffer(64, 64, Color(0, 0, 0))
    trail.draw(before, scene, _camera(Vector3(0, 1.5, -5)), look)
    var half = _light(before)
    assert_true(half > 0)
    var behind = Framebuffer(64, 64, Color(0, 0, 0))
    trail.draw(behind, scene, _camera(Vector3(0, 1.5, 0.5)), look)
    assert_equal(_light(behind), 0)
    # Swept whole, it adds more; then it fades.
    fighter.clock = 0.24
    trail.show(scene, fighter)
    var whole = Framebuffer(64, 64, Color(0, 0, 0))
    trail.draw(whole, scene, _camera(Vector3(0, 1.5, -5)), look)
    assert_true(_light(whole) > half)
    fighter.clock = 0.3
    trail.show(scene, fighter)
    assert_almost_equal(trail.sweep, 1, atol=1e-6)
    assert_true(trail.glow < 1)
    fighter.clock = 0.45
    trail.show(scene, fighter)
    assert_equal(trail.shown, -1)
    var none = Framebuffer(64, 64, Color(0, 0, 0))
    trail.draw(none, scene, _camera(Vector3(0, 1.5, -5)), look)
    assert_equal(_light(none), 0)
    # The tempest's ribbon turns with the body.
    var spinner = Fighter(FighterParameters())
    _ = spinner.request(TEMPEST)
    spinner.clock = 0.4
    trail.show(scene, spinner)
    assert_equal(trail.shown, TEMPEST.value)
    # A throw has no ribbon, and shows none.
    var thrower = Fighter(FighterParameters())
    _ = thrower.request(THROW)
    thrower.clock = 0.5
    trail.show(scene, thrower)
    assert_equal(trail.shown, -1)
    var ring = trail.nodes[TEMPEST.value].value()
    assert_true(abs(scene.node(ring).quaternion.w) < 0.99)
    # A burst attack's thrust is red, whoever makes it.
    var burster = Fighter(FighterParameters())
    _ = burster.request(BURST)
    burster.clock = 0.84
    trail.show(scene, burster)
    assert_equal(trail.shown, BURST.value)
    scene.update()
    var red = Framebuffer(64, 64, Color(0, 0, 0))
    trail.draw(red, scene, _camera(Vector3(0, 1.5, -5)), look)
    var reds = 0
    var blues = 0
    for k in range(0, len(red.pixels), 4):
        reds += Int(red.pixels[k])
        blues += Int(red.pixels[k + 2])
    assert_true(reds > 4 * blues)
    assert_true(blues > 0)
    # A mystic arte's ring turns with the body, and is gold.
    var mystic = Fighter(FighterParameters())
    mystic.over = 1
    _ = mystic.request(MYSTIC_ARTE)
    mystic.clock = 0.8
    trail.show(scene, mystic)
    assert_equal(trail.shown, MYSTIC_ARTE.value)
    assert_almost_equal(trail.sweep, 1, atol=1e-6)
    var wide = trail.nodes[MYSTIC_ARTE.value].value()
    assert_true(abs(scene.node(wide).quaternion.w) < 0.99)
    scene.update()
    var gold = Framebuffer(64, 64, Color(0, 0, 0))
    trail.draw(gold, scene, _camera(Vector3(0, 1.5, -5)), look)
    var golds = 0
    var cools = 0
    for k in range(0, len(gold.pixels), 4):
        golds += Int(gold.pixels[k])
        cools += Int(gold.pixels[k + 2])
    assert_true(golds > 2 * cools)
    assert_true(cools > 0)


def test_a_star_of_light_is_brightest_at_its_middle() raises:
    var frame = Framebuffer(40, 40, Color(0, 0, 0))
    glow_star(frame, Vector3(20.3, 19.6, 1), 12, BURST_TRAIL)
    var middle = (19 * 40 + 20) * 4
    var ray = (19 * 40 + 28) * 4
    assert_true(frame.pixels[ray] > 0)
    assert_true(frame.pixels[middle] > frame.pixels[ray])
    # Between two rays, past their waists, it is dark.
    assert_equal(Int(frame.pixels[(23 * 40 + 29) * 4]), 0)


def test_a_wave_stands_as_an_arch_of_light() raises:
    var look = Vector3(0, -0.3, 4) / Vector3(0, -0.3, 4).length()
    var before = Framebuffer(64, 64, Color(0, 0, 0))
    draw_wave(
        before,
        _camera(Vector3(0, 1.5, -5)),
        look,
        Vector3(0, 0, 0),
        Vector3(0, 0, -1),
        1,
    )
    assert_true(_light(before) > 0)
    # Behind the camera, it is not drawn.
    var behind = Framebuffer(64, 64, Color(0, 0, 0))
    draw_wave(
        behind,
        _camera(Vector3(0, 1.5, 0.5)),
        look,
        Vector3(0, 0, 0),
        Vector3(0, 0, -1),
        1,
    )
    assert_equal(_light(behind), 0)
    # A ring on the ground before the camera adds light; a dark one adds
    # none.
    var ring = Framebuffer(64, 64, Color(0, 0, 0))
    draw_ring(ring, _camera(Vector3(0, 1.5, -5)), look, Vector3(0, 0, 0), 2, 1)
    assert_true(_light(ring) > 0)
    var dark = Framebuffer(64, 64, Color(0, 0, 0))
    draw_ring(dark, _camera(Vector3(0, 1.5, -5)), look, Vector3(0, 0, 0), 2, 0)
    assert_equal(_light(dark), 0)
    # A ribbon of one step has no width to draw.
    var one = Framebuffer(64, 64, Color(0, 0, 0))
    var corners: List[Vector3] = [Vector3(0, 0, 0), Vector3(0, 1, 0)]
    var light: List[Float32] = [1]
    glow_ribbon(
        one,
        _camera(Vector3(0, 1.5, -5)),
        look,
        corners,
        light,
        PLAYER_TRAIL,
    )
    assert_equal(_light(one), 0)


def test_sparks_burst_grow_and_go() raises:
    var assets = Assets()
    var scene = Scene()
    var glow = slash_material(assets)
    assert_true(assets.materials.get(glow).kind == BASIC)
    var sparks = Sparks(scene, assets, glow)
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
