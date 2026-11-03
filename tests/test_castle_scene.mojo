# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the castle as a scene: its settings, its building from a plan,
the sun that moves, and a picture drawn at the smallest size.

The textures, the sky cube and the shadow map are the smallest the scene
allows, so a test spends its time on the steps and not on the quality.
"""

from cameras.perspective_camera import PerspectiveCamera
from extensions.castle.forest import Clearing, default_forest
from extensions.castle.scene import (
    SceneSettings,
    add_splat_layer,
    advance_water,
    aim_sun,
    build_castle_scene,
    build_landscape_scene,
    castle_renderer,
    default_settings,
    draw_castle,
)
from extensions.scan.composite import SplatLayer, splat_layer
from extensions.scan.frame import (
    SCALE_DECLARED,
    SCAN_POSITIVE_Y,
    SCAN_POSITIVE_Z,
    ScanFrame,
)
from generators.utils import Vec3d
from math.vector3 import Vector3
from tests._castle_land import small_landscape
from tests._castle_small import small_plan
from tests._scan_site import site_scan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, Angle64, DEGREE, Length, Length64, METER, RADIAN

comptime SIZE = 24


def _small(woods: Bool) -> SceneSettings:
    return SceneSettings(
        16, 8, 64, woods, String("assets/pebbles.jpg"), Length64(30.0, METER)
    )


def _camera() raises -> PerspectiveCamera:
    var camera = PerspectiveCamera(
        Angle(58.0, DEGREE), 1.0, Length(1.0, METER), Length(6000.0, METER)
    )
    camera.place(Vector3(-30, 49, 16), Vector3(32, 20, -42))
    return camera^


def test_the_default_settings_are_for_a_picture_to_look_at() raises:
    var settings = default_settings()
    assert_equal(settings.texture_size, 512)
    assert_equal(settings.environment_size, 128)
    assert_equal(settings.shadow_size, 4096)
    assert_true(settings.woods)
    assert_equal(settings.pebbles, "assets/pebbles.jpg")
    assert_almost_equal(settings.terrain_step.value, 1.0)


def test_the_renderer_filters_its_shadows_and_tone_maps() raises:
    var renderer = castle_renderer(SIZE, SIZE)
    assert_equal(renderer.width, SIZE)
    assert_equal(renderer.height, SIZE)
    var bright = castle_renderer(SIZE, SIZE, 1.0)
    assert_equal(bright.width, SIZE)


def test_a_scene_is_built_lit_and_drawn() raises:
    """A cut-down plan is built without woods, the sun is moved, a picture is
    drawn, and the water runs on."""
    var plan = small_plan()
    var castle = build_castle_scene(plan, _small(False), -30.0, -16.0, 45.0)
    assert_equal(castle.trees, 0)
    assert_equal(castle.shrubs, 0)
    # The moat is Clearwater's, so no mesh of the view stands for it.
    assert_true(len(castle.scene.meshes) >= 8)
    assert_equal(len(castle.scene.lights), 1)
    assert_almost_equal(
        castle.level,
        Float32(plan.moat.water_level.value - plan.island_level.value),
    )
    var renderer = castle_renderer(SIZE, SIZE)
    # The sun must be over the horizon.
    with assert_raises(contains="over the horizon"):
        aim_sun(castle, renderer, Vector3(1, 0, 0))
    with assert_raises(contains="over the horizon"):
        aim_sun(castle, renderer, Vector3(0, -1, 0))
    # A low sun is dimmer and redder than a high sun.
    aim_sun(castle, renderer, Vector3(0, 1, 0))
    var high = castle.scene.lights[0].intensity
    var green_high = castle.scene.lights[0].color.g
    aim_sun(castle, renderer, Vector3(0.98, 0.1, 0.17))
    assert_true(castle.scene.lights[0].intensity < high)
    assert_true(castle.scene.lights[0].color.g < green_high)
    assert_almost_equal(castle.sun.y, 0.1)
    aim_sun(castle, renderer, Vector3(0.5, 0.7, 0.5))
    var image = draw_castle(castle, renderer, _camera(), 0.5, 5)
    assert_equal(image.width, SIZE)
    var painted = 0
    for at in range(SIZE * SIZE):
        var color = image.get_pixel(at % SIZE, at // SIZE)
        if color.r != 150 or color.g != 186 or color.b != 226:
            painted += 1
    assert_true(painted > SIZE * SIZE // 2)
    advance_water(castle, 1.0)
    with assert_raises():
        advance_water(castle, -1.0)


def test_a_scene_with_woods_is_planted() raises:
    # Nothing but the garden stands outside the keep: two trees.
    var castle = build_castle_scene(small_plan(), _small(True), 0.0, 0.0, 1.0e5)
    assert_equal(castle.trees, 2)
    assert_true(castle.shrubs > 0)
    assert_true(len(castle.scene.instanced_meshes) >= 4)


def test_a_castle_in_a_landscape_is_built_planted_and_shared_with_a_scan() raises:
    var plan = small_plan()
    var land = small_landscape()
    # Woods near the camera only, to keep the test short.
    var woods = default_forest()
    woods.hero = Length64(15.0)
    woods.near = Length64(40.0)
    woods.mid = Length64(120.0)
    woods.far = Length64(300.0)
    woods.eye_x = -30.0
    woods.eye_y = -16.0
    var clearings = List[Clearing]()
    clearings.append(Clearing(0.0, 20.0, 40.0))
    var castle = build_landscape_scene(
        plan, _small(True), land, woods, clearings
    )
    assert_true(castle.trees > 0)
    assert_true(castle.shrubs > 0)
    assert_equal(len(castle.layers), 0)
    var renderer = castle_renderer(SIZE, SIZE)
    aim_sun(castle, renderer, Vector3(0.5, 0.7, 0.5))
    var without = draw_castle(castle, renderer, _camera(), 0.5, 5)
    # A scanned building stands in the scene, and the picture shows it.
    var frame = ScanFrame(
        SCAN_POSITIVE_Z,
        SCAN_POSITIVE_Y,
        Length64(1.0, METER),
        SCALE_DECLARED,
        Angle64(0.0, RADIAN),
        Vec3d(0, 0, 0),
    )
    add_splat_layer(
        castle,
        splat_layer(
            site_scan(SCAN_POSITIVE_Z, True),
            frame,
            32.0,
            42.0,
            land.height(32.0, 42.0) + 6.0,
            0.0,
        ),
    )
    assert_equal(len(castle.layers), 1)
    var with_scan = draw_castle(castle, renderer, _camera(), 0.5, 5)
    var different = 0
    for at in range(len(with_scan.pixels)):
        if with_scan.pixels[at] != without.pixels[at]:
            different += 1
    assert_true(different > 20)


def test_a_landscape_without_woods_has_no_trees() raises:
    var plan = small_plan()
    var castle = build_landscape_scene(
        plan,
        _small(False),
        small_landscape(),
        default_forest(),
        List[Clearing](),
    )
    assert_equal(castle.trees, 0)
    assert_equal(castle.shrubs, 0)
    assert_true(len(castle.scene.meshes) >= 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
