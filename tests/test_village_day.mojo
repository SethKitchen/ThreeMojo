# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's day and night: its light, its sky and its water."""

from cameras.perspective_camera import PerspectiveCamera
from core.fog import exp2_fog
from core.object3d import Object3D
from core.scene import Scene
from extensions.village.day import (
    DayCycle,
    MOON,
    MOONLIGHT,
    SUNRISE,
    SUNSET,
    dim_water,
)
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length


def test_a_day_is_checked_and_moves_on() raises:
    with assert_raises(contains="from 0 to less than 24"):
        _ = DayCycle(24)
    with assert_raises(contains="from 0 to less than 24"):
        _ = DayCycle(-1)
    with assert_raises(contains="0 to 24 hours a second"):
        _ = DayCycle(12, -1)
    with assert_raises(contains="0 to 24 hours a second"):
        _ = DayCycle(12, 25)
    var day = DayCycle(23, 2)
    day.advance(Duration(1.0, SECOND))
    assert_almost_equal(day.hour, 1, atol=1e-5)
    with assert_raises(contains="negative"):
        day.advance(Duration(-1.0, SECOND))
    var still = DayCycle(9)
    still.advance(Duration(100.0, SECOND))
    assert_equal(still.hour, 9)


def test_the_light_rises_and_sets() raises:
    assert_equal(DayCycle(12).daylight(), 1)
    assert_equal(DayCycle(2).daylight(), 0)
    assert_almost_equal(DayCycle(SUNRISE).daylight(), 0.5, atol=1e-5)
    assert_almost_equal(DayCycle(SUNSET).daylight(), 0.5, atol=1e-5)
    assert_equal(DayCycle(SUNSET).dusk(), 1)
    assert_equal(DayCycle(12).dusk(), 0)
    assert_almost_equal(DayCycle(2).sky_light(), MOONLIGHT, atol=1e-6)
    assert_almost_equal(DayCycle(2).water_light(), MOON, atol=1e-6)
    assert_equal(DayCycle(12).water_light(), 1)


def _scene() raises -> Scene:
    """Return a scene with a white sun, a white sky light and a fog."""
    var scene = Scene()
    var high = Object3D()
    high.set_position(0, 10, 0)
    scene.add_light(
        directional_light(Color(255, 255, 255), scene.add(high^), 4)
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 1))
    scene.fog = exp2_fog(Color(200, 200, 200))
    return scene^


def test_night_dims_and_tints_the_light() raises:
    var noon = _scene()
    DayCycle(12).light(noon)
    assert_almost_equal(noon.lights[0].intensity, 4, atol=1e-5)
    assert_equal(Int(noon.lights[0].color.b), 255)
    var night = _scene()
    DayCycle(1).light(night)
    # The moon is a little of the sun, and blue.
    assert_almost_equal(night.lights[0].intensity, 4 * MOON, atol=1e-5)
    assert_true(night.lights[0].color.r < night.lights[0].color.b)
    assert_almost_equal(night.lights[1].intensity, MOONLIGHT, atol=1e-5)
    assert_true(Int(night.fog.color.r) < 60)
    # Indoors, the lamps keep the sky's light whole and warm.
    var room = _scene()
    DayCycle(1).light(room, True)
    assert_almost_equal(room.lights[1].intensity, 1, atol=1e-5)
    assert_true(room.lights[1].color.r > room.lights[1].color.b)
    # At dusk, the sun is orange.
    var dusk = _scene()
    DayCycle(SUNSET - 0.5).light(dusk)
    assert_true(dusk.lights[0].color.b < dusk.lights[0].color.r)
    # A scene with no light changes only its fog.
    var bare = Scene()
    bare.fog = exp2_fog(Color(200, 200, 200))
    DayCycle(1).light(bare)
    assert_equal(len(bare.lights), 0)


def _frame() raises -> Framebuffer:
    """Return a blue frame 128 by 64 whose top half is sky."""
    var w = 128
    var h = 64
    var depth = List[Float32](length=w * h, fill=0.5)
    for k in range(w * h // 2):
        depth[k] = inf[DType.float32]()
    var pixels = List[UInt8](length=w * h * 4, fill=0)
    for k in range(w * h):
        pixels[4 * k] = 120
        pixels[4 * k + 1] = 160
        pixels[4 * k + 2] = 230
        pixels[4 * k + 3] = 255
    return Framebuffer(w, h, pixels^, depth^)


def _camera(rise: Float32 = 4) raises -> PerspectiveCamera:
    """Return a camera that looks up into the sky, rising `rise` meters in
    ten."""
    var camera = PerspectiveCamera(
        Angle(70.0, DEGREE), 2, Length(0.1, METER), Length(1000.0, METER)
    )
    camera.place(Vector3(0, 2, 0), Vector3(0, 2 + rise, -10))
    return camera^


def test_the_night_sky_is_dark_and_starry() raises:
    # By day, the sky is left alone.
    var noon = _frame()
    DayCycle(12).night_sky(noon, _camera(), 1)
    assert_equal(Int(noon.pixels[0]), 120)
    # Just after sunrise, the low sky is warmed.
    var morning = _frame()
    DayCycle(7.2).night_sky(morning, _camera(0), 1)
    var bottom = (31 * 128 + 64) * 4
    assert_true(Int(morning.pixels[bottom + 2]) < 230)
    # At night the sky is dark, with stars; the ground is left alone.
    var night = _frame()
    DayCycle(1).night_sky(night, _camera(), 1)
    var dark = 0
    var stars = 0
    for k in range(128 * 32):
        if Int(night.pixels[4 * k + 2]) < 60:
            dark += 1
        elif Int(night.pixels[4 * k]) > 60:
            stars += 1
    assert_true(dark > 3000)
    assert_true(stars > 0)
    assert_equal(Int(night.pixels[(40 * 128) * 4]), 120)
    # Under full cloud, no star shows.
    var cloudy = _frame()
    DayCycle(1).night_sky(cloudy, _camera(), 0)
    for k in range(128 * 32):
        assert_true(Int(cloudy.pixels[4 * k]) < 60)
    var flat = Framebuffer(4, 4, List[UInt8](length=64, fill=0))
    flat.depth = List[Float32]()
    with assert_raises(contains="depth for each pixel"):
        DayCycle(1).night_sky(flat, _camera(), 1)


def test_the_water_darkens() raises:
    var image = _frame()
    var before = image.depth.copy()
    image.depth[100 * 0 + 5000] = 0.25
    dim_water(image, before, 0.5)
    assert_equal(Int(image.pixels[5000 * 4]), 60)
    assert_equal(Int(image.pixels[5001 * 4]), 120)
    with assert_raises(contains="depth for each pixel"):
        dim_water(image, List[Float32](), 0.5)
    var flat = Framebuffer(4, 4, List[UInt8](length=64, fill=0))
    flat.depth = List[Float32]()
    with assert_raises(contains="depth for each pixel"):
        dim_water(flat, List[Float32](length=16, fill=0), 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
