# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's weather: its looks, its lights and fog, its clouds and
its rain."""

from cameras.perspective_camera import PerspectiveCamera
from core.fog import exp2_fog
from core.object3d import Object3D
from core.scene import Scene
from extensions.village.weather import (
    CLEAR,
    CLOUD_STEP,
    CYCLE_SECONDS,
    DROPS,
    FOG,
    OVERCAST,
    RAIN,
    SNOW,
    SOAK_SECONDS,
    SNOW_SECONDS,
    Weather,
    WeatherKind,
    cloud_cover,
    next_weather,
    weather_label,
    weather_look,
)
from lights.light import ambient_light, directional_light, point_light
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


def test_each_weather_has_its_name() raises:
    assert_equal(weather_label(CLEAR), "CLEAR")
    assert_equal(weather_label(OVERCAST), "OVERCAST")
    assert_equal(weather_label(RAIN), "RAIN")
    assert_equal(weather_label(FOG), "FOG")
    assert_equal(weather_label(SNOW), "SNOW")
    assert_equal(weather_label(WeatherKind(9)), "")


def test_each_weather_has_its_look() raises:
    assert_true(FOG.is_valid())
    assert_true(SNOW.is_valid())
    assert_false(WeatherKind(5).is_valid())
    var snow = weather_look(SNOW)
    assert_equal(snow.snow, 1)
    assert_equal(snow.rain, 0)
    var clear = weather_look(CLEAR)
    var overcast = weather_look(OVERCAST)
    var rain = weather_look(RAIN)
    var fog = weather_look(FOG)
    assert_true(clear.sun > overcast.sun and overcast.sun > rain.sun)
    assert_true(rain.clouds > overcast.clouds)
    assert_equal(clear.rain, 0)
    assert_equal(rain.rain, 1)
    assert_true(fog.fog > rain.fog and rain.fog > clear.fog)
    with assert_raises(contains="one of the five"):
        _ = weather_look(WeatherKind(9))
    # A look moves a share of the way to another.
    var half = clear.mixed(rain, 0.5)
    assert_almost_equal(half.rain, 0.5, atol=1e-6)
    assert_almost_equal(half.sun, (clear.sun + rain.sun) / 2, atol=1e-6)
    assert_almost_equal(clear.mixed(rain, 1).gloom, rain.gloom, atol=1e-6)


def test_the_cycle_turns_through_six_weathers() raises:
    var order: List[WeatherKind] = []
    for step in range(7):
        order.append(next_weather(CLEAR, step))
    assert_true(order[0] == OVERCAST)
    assert_true(order[1] == RAIN)
    assert_true(order[2] == OVERCAST)
    assert_true(order[3] == CLEAR)
    assert_true(order[4] == FOG)
    assert_true(order[5] == CLEAR)
    assert_true(order[6] == OVERCAST)


def test_more_cloud_covers_more_sky() raises:
    var thin = 0
    var thick = 0
    for k in range(400):
        var u = Float32(k % 20) * 0.137
        var v = Float32(k // 20) * 0.211
        var a = cloud_cover(u, v, 0.2)
        var b = cloud_cover(u, v, 0.9)
        assert_true(a >= 0 and a <= 1)
        assert_true(b >= a)
        if a > 0.5:
            thin += 1
        if b > 0.5:
            thick += 1
    assert_true(thick > thin)
    assert_true(thick > 300)


def _scene() raises -> Scene:
    """Return a scene with a sun, an ambient light and a fog."""
    var scene = Scene()
    var high = Object3D()
    high.set_position(0, 10, 0)
    scene.add_light(
        directional_light(Color(255, 255, 255), scene.add(high^), 4)
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 0.5))
    scene.add_light(ambient_light(Color(150, 180, 240), 0.1))
    scene.fog = exp2_fog(Color(180, 200, 230))
    return scene^


def test_the_weather_sets_the_lights_and_the_fog() raises:
    var scene = _scene()
    var weather = Weather(scene, CLEAR)
    assert_equal(len(weather.drops), DROPS)
    weather.update(scene, Duration(0.1, SECOND), Angle(0.0, DEGREE))
    assert_almost_equal(scene.lights[0].intensity, 4, atol=1e-4)
    assert_almost_equal(scene.lights[1].intensity, 0.5, atol=1e-4)
    # Rain dims the sun most, and turns the fog gray and thick.
    weather.set(RAIN)
    for _ in range(100):
        weather.update(scene, Duration(0.2, SECOND), Angle(0.0, DEGREE))
    assert_true(scene.lights[0].intensity < 0.6)
    # The sky's light grays; the sun keeps its color.
    assert_equal(Int(scene.lights[1].color.r), 255)
    assert_equal(Int(scene.lights[0].color.b), 255)
    assert_true(scene.fog.density.value > 0.004)
    assert_true(Int(scene.fog.color.r) < 180)
    ref blue = scene.lights[2].color
    assert_true(Int(blue.b) - Int(blue.r) < 30)
    # In rain the lightning has flashed.
    assert_true(weather.flashes > 0)
    with assert_raises(contains="one of the five"):
        weather.set(WeatherKind(8))
    with assert_raises(contains="negative"):
        weather.update(scene, Duration(-1.0, SECOND), Angle(0.0, DEGREE))
    # A scene with fewer lights than the weather began with is refused.
    var bare = Scene()
    with assert_raises(contains="lost a light"):
        weather.update(bare, Duration(0.1, SECOND), Angle(0.0, DEGREE))
    # A scene with no light at all has nothing to scale.
    var dark = Weather(bare, FOG)
    dark.update(bare, Duration(0.1, SECOND), Angle(0.0, DEGREE))
    assert_equal(len(dark.bases), 0)
    with assert_raises(contains="one of the five"):
        _ = Weather(bare, WeatherKind(5))


def test_a_lamp_burns_as_bright_in_the_rain() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_light(point_light(Color(255, 180, 100), node, 6))
    scene.update()
    var weather = Weather(scene, RAIN)
    for _ in range(10):
        weather.update(scene, Duration(0.2, SECOND), Angle(0.0, DEGREE))
    assert_almost_equal(scene.lights[0].intensity, 6, atol=1e-5)
    assert_equal(Int(scene.lights[0].color.b), 100)


def test_rain_soaks_the_village_and_snow_covers_it() raises:
    var scene = Scene()
    var weather = Weather(scene, RAIN)
    for _ in range(Int(SOAK_SECONDS) + 5):
        weather.update(scene, Duration(1.0, SECOND), Angle(0.0, DEGREE))
    assert_almost_equal(weather.wet, 1, atol=1e-6)
    assert_equal(weather.snowed, 0)
    # It dries once the rain stops; and snow covers it.
    weather.set(SNOW)
    weather.look = weather_look(SNOW)
    for _ in range(Int(SNOW_SECONDS) + 5):
        weather.update(scene, Duration(1.0, SECOND), Angle(0.0, DEGREE))
    assert_true(weather.wet < 1)
    assert_almost_equal(weather.snowed, 1, atol=1e-6)
    # The flakes fall slower than the drops, and show on the window.
    weather.drops[0].y = 0.1
    weather.update(scene, Duration(0.1, SECOND), Angle(0.0, DEGREE))
    var fell = weather.drops[0].y - 0.1
    var window = Framebuffer(64, 48, Color(0, 0, 0, 255))
    weather.rain(window)
    var lit = 0
    for k in range(64 * 48):
        if window.pixels[k * 4] > 0:
            lit += 1
    assert_true(lit > 0)
    var rainy = Weather(scene, RAIN)
    rainy.drops[0].y = 0.1
    rainy.update(scene, Duration(0.1, SECOND), Angle(0.0, DEGREE))
    assert_true(fell > 0 and fell < rainy.drops[0].y - 0.1)
    # Under a roof, no drop or flake is drawn.
    var covered = Framebuffer(64, 48, Color(0, 0, 0, 255))
    weather.rain(covered, List[Bool](length=4, fill=True), 2, 2)
    rainy.rain(covered, List[Bool](length=4, fill=True), 2, 2)
    for k in range(64 * 48):
        assert_equal(covered.pixels[k * 4], 0)
    # A grid that does not fit shelters nothing.
    var bare = Framebuffer(64, 48, Color(0, 0, 0, 255))
    rainy.look.rain = 1
    rainy.rain(bare, List[Bool](length=3, fill=True), 2, 2)
    var wet = 0
    for k in range(64 * 48):
        if bare.pixels[k * 4] > 0:
            wet += 1
    assert_true(wet > 0)


def test_the_weather_cycles_by_itself() raises:
    var scene = _scene()
    var weather = Weather(scene, CLEAR)
    weather.cycle = True
    var step = Duration(1.0, SECOND)
    for _ in range(Int(CYCLE_SECONDS) - 1):
        weather.update(scene, step, Angle(0.0, DEGREE))
    assert_true(weather.kind == CLEAR)
    weather.update(scene, step, Angle(0.0, DEGREE))
    assert_true(weather.kind == OVERCAST)
    assert_equal(weather.changes, 1)
    # A weather that does not cycle stays.
    var still = Weather(scene, FOG)
    for _ in range(Int(CYCLE_SECONDS) + 5):
        still.update(scene, step, Angle(0.0, DEGREE))
    assert_true(still.kind == FOG)


def test_the_drops_fall_and_slide_as_the_camera_turns() raises:
    var scene = _scene()
    var weather = Weather(scene, RAIN)
    var before = weather.drops[0]
    weather.update(scene, Duration(0.05, SECOND), Angle(0.0, DEGREE))
    var fell = weather.drops[0]
    assert_true(fell.y != before.y)
    weather.update(scene, Duration(0.0, SECOND), Angle(30.0, DEGREE))
    var slid = weather.drops[0]
    assert_true(abs(slid.x - fell.x) > 0.05)
    for d in weather.drops:
        assert_true(d.x >= 0 and d.x < 1)
        assert_true(d.y >= 0 and d.y < 1)


def _frame(width: Int, height: Int) raises -> Framebuffer:
    """Return a blue frame whose top half is sky and bottom half ground."""
    var depth = List[Float32](length=width * height, fill=0.5)
    for k in range(width * height // 2):
        depth[k] = inf[DType.float32]()
    var pixels = List[UInt8](length=width * height * 4, fill=0)
    for k in range(width * height):
        pixels[4 * k] = 90
        pixels[4 * k + 1] = 140
        pixels[4 * k + 2] = 220
        pixels[4 * k + 3] = 255
    return Framebuffer(width, height, pixels^, depth^)


def _camera() raises -> PerspectiveCamera:
    """Return a camera that looks out level, 2 meters up."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 2, Length(0.1, METER), Length(1000.0, METER)
    )
    camera.place(Vector3(0, 2, 0), Vector3(0, 2.5, -10))
    return camera^


def test_clouds_cover_only_the_sky() raises:
    var scene = _scene()
    var weather = Weather(scene, OVERCAST)
    var image = _frame(64, 32)
    weather.cover(image, _camera())
    var sky_changed = 0
    for k in range(64 * 16):
        if image.pixels[4 * k + 2] != 220:
            sky_changed += 1
    assert_true(sky_changed > 400)
    for k in range(64 * 16, 64 * 32):
        assert_equal(Int(image.pixels[4 * k + 2]), 220)
    # Overcast grays the sky: its blue falls toward its red.
    var top = 4 * 32
    assert_true(Int(image.pixels[top + 2]) - Int(image.pixels[top]) < 220 - 90)
    # A flash of lightning brightens the sky further.
    var stormy = Weather(scene, RAIN)
    stormy.flash = 1
    var dark = _frame(64, 32)
    var lit = _frame(64, 32)
    weather.cover(dark, _camera())
    stormy.cover(lit, _camera())
    assert_true(Int(lit.pixels[top]) > Int(dark.pixels[top]))
    # A frame with no depths is refused.
    var flat = Framebuffer(4, 4, List[UInt8](length=64, fill=0))
    flat.depth = List[Float32]()
    with assert_raises(contains="depth for each pixel"):
        weather.cover(flat, _camera())


def test_the_cover_look_follows_the_weather_and_the_flash() raises:
    var scene = _scene()
    var clear = Weather(scene, CLEAR).cover_look()
    var rain = Weather(scene, RAIN)
    var stormy = rain.cover_look()
    # Rain clouds are darker than a clear sky's, and hide more of it.
    assert_true(stormy.gloom > clear.gloom)
    assert_true(stormy.gray.x < clear.gray.x)
    assert_true(stormy.veil > clear.veil)
    assert_almost_equal(clear.bright, 1)
    assert_almost_equal(clear.gray.z, clear.gray.x + 6)
    # The mist is the fog's share, and a flash of lightning brightens.
    var misty = Weather(scene, FOG).cover_look()
    assert_true(misty.mist > clear.mist)
    rain.flash = 1
    assert_almost_equal(rain.cover_look().bright, 2.5)


def test_the_cloud_grid_holds_the_cover_of_the_sky() raises:
    var scene = _scene()
    var weather = Weather(scene, OVERCAST)
    var grid = weather.cloud_grid(_camera(), 64, 32)
    assert_equal(grid.columns, (64 + CLOUD_STEP - 1) // CLOUD_STEP + 1)
    assert_equal(grid.rows, (32 + CLOUD_STEP - 1) // CLOUD_STEP + 1)
    assert_equal(len(grid.cover), grid.columns * grid.rows)
    # The row at the top of the frame sees cloud. The bottom row looks
    # at the ground, and sees none.
    var top = 0.0
    for column in range(grid.columns):
        top += Float64(grid.cover[column])
    assert_true(top > 1)
    var last = (grid.rows - 1) * grid.columns
    for column in range(grid.columns):
        assert_equal(grid.cover[last + column], 0)
    for value in grid.cover:
        assert_true(value >= 0 and value <= 1)
    # A clear sky has less cloud than an overcast one.
    var clear = Weather(scene, CLEAR).cloud_grid(_camera(), 64, 32)
    var thin = Float32(0)
    for value in clear.cover:
        thin += value
    var thick = Float32(0)
    for value in grid.cover:
        thick += value
    assert_true(thin < thick)


def test_rain_streaks_the_window_and_clear_skies_do_not() raises:
    var scene = _scene()
    var clear = Weather(scene, CLEAR)
    var dry = _frame(320, 180)
    clear.rain(dry)
    for k in range(320 * 180):
        assert_equal(Int(dry.pixels[4 * k]), 90)
    var rain = Weather(scene, RAIN)
    var wet = _frame(320, 180)
    rain.rain(wet)
    var streaked = 0
    for k in range(320 * 180):
        if Int(wet.pixels[4 * k]) != 90:
            streaked += 1
    assert_true(streaked > 1000)
    # On a window too short for a streak, no drop is drawn.
    var tiny = _frame(8, 8)
    rain.rain(tiny)
    for k in range(64):
        assert_equal(Int(tiny.pixels[4 * k]), 90)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
