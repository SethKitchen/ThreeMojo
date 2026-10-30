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
from extensions.village.slashes import (
    PLAYER_TRAIL,
    SPARKS,
    SPARK_SECONDS,
    Sparks,
    Trail,
    arc_points,
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
    var ring = trail.nodes[TEMPEST.value].value()
    assert_true(abs(scene.node(ring).quaternion.w) < 0.99)


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
