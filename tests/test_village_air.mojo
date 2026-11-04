# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The air of a frame: bloom round bright light, the ground mist, and
the surfaces that the weather wets and the snow covers."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from extensions.village.air import bloom, ground_mist
from extensions.village.day import DayCycle
from extensions.village.village import SNOW_WHITE, SOAKED, Village
from extensions.water.pebbles import pebble_bed
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._village_tiny import gray_photograph, tiny_village
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length


def test_bright_light_glows_into_what_is_round_it() raises:
    var image = Framebuffer(96, 96, Color(10, 10, 10, 255))
    image.set_pixel(16, 16, Color(255, 240, 200, 255))
    image.set_pixel(17, 16, Color(255, 240, 200, 255))
    assert_equal(bloom(image, 0.8, 1.5), 2)
    # A pixel beside the lamp catches its glow; a far corner does not.
    assert_true(image.get_pixel(14, 16).r > 10)
    assert_equal(image.get_pixel(95, 95).r, 10)
    # A dim frame has nothing to glow, and no strength adds nothing.
    var dim = Framebuffer(8, 8, Color(40, 40, 40, 255))
    assert_equal(bloom(dim, 0.8, 1), 0)
    var bright = Framebuffer(8, 8, Color(255, 255, 255, 255))
    assert_equal(bloom(bright, 0.5, 0), 64)
    assert_equal(bright.get_pixel(3, 3).r, 255)
    with assert_raises(contains="threshold"):
        _ = bloom(dim, 1, 1)
    with assert_raises(contains="strength"):
        _ = bloom(dim, 0.5, 5)
    with assert_raises(contains="threshold"):
        _ = bloom(dim, -0.1, 1)
    with assert_raises(contains="strength"):
        _ = bloom(dim, 0.5, -1)


def _camera() raises -> PerspectiveCamera:
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, Length(0.1, METER), Length(500.0, METER)
    )
    camera.place(Vector3(0, 1.7, 0), Vector3(0, 1.0, -20))
    return camera^


def test_the_mist_lies_low_and_far() raises:
    var camera = _camera()
    var image = Framebuffer(16, 16, Color(0, 0, 0, 255))
    var clip = camera.projection_matrix()
    clip.multiply(camera.view_matrix())
    # The top half is the sky; the bottom half is ground far away.
    var far = clip.transform_point(Vector3(0, 0, -150)).z
    for k in range(16 * 16):
        image.depth[k] = inf[DType.float32]() if k < 128 else far
    var veiled = ground_mist(image, camera, 0, 0.6, Color(200, 200, 200, 255))
    assert_equal(veiled, 128)
    assert_equal(image.get_pixel(3, 3).r, 0)
    assert_true(image.get_pixel(3, 12).r > 100)
    # No mist veils nothing.
    assert_equal(ground_mist(image, camera, 0, 0, Color(0, 0, 0, 255)), 0)
    # Mist far below the ground's points thins away.
    var high = Framebuffer(16, 16, Color(0, 0, 0, 255))
    for k in range(16 * 16):
        high.depth[k] = far
    assert_equal(
        ground_mist(high, camera, -200, 0.6, Color(200, 200, 200, 255)), 0
    )
    with assert_raises(contains="thickness"):
        _ = ground_mist(image, camera, 0, 2, Color(0, 0, 0, 255))
    with assert_raises(contains="thickness"):
        _ = ground_mist(image, camera, 0, -1, Color(0, 0, 0, 255))
    image.depth = List[Float32]()
    with assert_raises(contains="depth"):
        _ = ground_mist(image, camera, 0, 0.5, Color(0, 0, 0, 255))


def test_the_rain_darkens_and_the_snow_whitens_the_village() raises:
    var assets = Assets()
    var scene = Scene()
    var village = Village(
        scene,
        assets,
        Renderer(16, 16),
        tiny_village(),
        pebble_bed(gray_photograph()),
        None,
    )
    village.weather_surfaces(assets, 1, 1, 1)
    var wall = assets.materials.get(village.weathered[0])
    var roof = assets.materials.get(village.weathered[village.roofs])
    var gray = UInt8(Int(255 * (1 - SOAKED) + 0.5))
    assert_equal(wall.color.r, gray)
    assert_equal(wall.emissive.r, 0)
    assert_true(roof.emissive == SNOW_WHITE)
    assert_true(roof.emissive_intensity > 0)
    # Dry and bare, they are as they were.
    village.weather_surfaces(assets, 0, 0, 1)
    assert_equal(assets.materials.get(village.weathered[0]).color.r, 255)
    assert_equal(
        assets.materials.get(
            village.weathered[village.roofs]
        ).emissive_intensity,
        0,
    )
    with assert_raises(contains="from 0 to 1"):
        village.weather_surfaces(assets, 2, 0, 1)
    with assert_raises(contains="from 0 to 1"):
        village.weather_surfaces(assets, -1, 0, 1)


def test_a_village_keeps_an_hour_for_a_still() raises:
    var assets = Assets()
    var scene = Scene()
    var renderer = Renderer(32, 18)
    renderer.set_antialias(True)
    var village = Village(
        scene,
        assets,
        renderer,
        tiny_village(),
        pebble_bed(gray_photograph()),
        None,
    )
    var night = DayCycle(23)
    village.keep_hour(scene, night)
    assert_true(scene.node(village.lamps).visible)
    assert_true(scene.node(village.houses[0].lit).visible)
    assert_false(scene.node(village.props.daylit).visible)
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(300.0, METER),
    )
    camera.place(Vector3(0, 6, 10), Vector3(0, -1, 4))
    _ = village.update(scene, assets, camera, Duration(6.0, SECOND))
    night.light(scene)
    scene.update()
    var dark = village.render(renderer, scene, assets, camera, night)
    assert_equal(dark.width, 32)
    # By day, the lamps are out and the panes show the day.
    village.keep_hour(scene, DayCycle(14))
    assert_false(scene.node(village.lamps).visible)
    assert_true(scene.node(village.houses[0].daylit).visible)
    # Reading a node through `scene.node` marks the scene changed.
    scene.update()
    var day = village.render(renderer, scene, assets, camera, DayCycle(14))
    # The night's sky and water differ from the day's.
    var differ = 0
    for k in range(len(day.pixels) // 4):
        if day.pixels[k * 4 + 2] != dark.pixels[k * 4 + 2]:
            differ += 1
    assert_true(differ > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
