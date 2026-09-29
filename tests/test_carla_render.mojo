# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA rendering: the weather's mappings, the textures and the image
effects.

These are the pure parts of the rendering tier. The expected numbers come
from outside this port:

- The Kasten-Young air mass, the smooth step and the closed-form integral
  of an exponential height fog, worked in a short Python script from
  their textbook forms.
- This port's documented constants, such as `SUN_INTENSITY`, applied by
  hand.
- Hand geometry for the lens, the metering histogram and the textures.
"""

from extensions.carla.render_post import (
    FOG_PHASE_G,
    LensSettings,
    SKY_DISTANCE,
    ViewRays,
    apply_gains,
    apply_gamma,
    apply_height_fog,
    apply_lens,
    draw_rain,
    fog_color,
    henyey_greenstein,
    lens_falloff,
    lens_source,
    luminance,
    metered_luminance,
)
from extensions.carla.render_textures import (
    BRICK,
    FACADE_TILE,
    FacadeStyle,
    PANELS,
    PLASTER,
    SHOPFRONT,
    asphalt_maps,
    concrete_maps,
    facade_maps,
    foliage_maps,
    grass_maps,
    hash2,
    normal_map,
    place,
    puddle_roughness,
    tile_fbm,
    tile_noise,
    wall_color,
)
from extensions.carla.render_weather import (
    CLOUD_SHADE,
    HAZE_EXTINCTION,
    HeightFog,
    MOON_INTENSITY,
    RAIN_STREAKS,
    RainSettings,
    SUN_INTENSITY,
    TOWN_SUN_AZIMUTH,
    WET_DARKENING,
    WET_ROUGHNESS,
    WetSurface,
    air_mass,
    carla_direction,
    daylight,
    height_fog,
    is_night,
    moon_color,
    moon_direction,
    moon_intensity,
    rain_settings,
    sky_settings,
    street_lights_on,
    sun_azimuth,
    sun_color,
    sun_direction,
    sun_intensity,
    wet_surface,
)
from extensions.carla.weather import WeatherParameters, weather_preset
from math.matrix4 import Matrix4
from math.projection import perspective
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.color_utils import kelvin_color
from render.framebuffer import Color, FloatColor
from render.cube_texture import CubeTexture
from render.target import RenderTarget
from render.texture import Texture, float_texture
from std.math import cos, exp, inf, nan, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    RADIAN,
    Angle,
    InverseLength,
    Length,
)
from units.temperature import KELVIN, Temperature


def _weather(altitude: Float32, cloudiness: Float32 = 0) -> WeatherParameters:
    var w = WeatherParameters()
    w.sun_altitude_angle = Angle(altitude, DEGREE)
    w.sun_azimuth_angle = Angle(30, DEGREE)
    w.cloudiness = cloudiness
    return w


# The sun and the moon.


def test_sun_azimuth_keeps_the_towns_for_a_negative_one() raises:
    var w = weather_preset("Default")
    assert_almost_equal(
        sun_azimuth(w).to(DEGREE), TOWN_SUN_AZIMUTH.to(DEGREE), atol=1e-5
    )
    w.sun_azimuth_angle = Angle(75, DEGREE)
    assert_almost_equal(sun_azimuth(w).to(DEGREE), 75, atol=1e-5)


def test_directions_turn_from_x_toward_y() raises:
    # 90 degrees round from plus x is plus y, CARLA's right; 30 degrees up.
    var d = carla_direction(Angle(90, DEGREE), Angle(30, DEGREE))
    assert_almost_equal(d.x, 0, atol=1e-6)
    assert_almost_equal(d.y, Float32(sqrt(3.0) / 2), atol=1e-6)
    assert_almost_equal(d.z, 0.5, atol=1e-6)
    # three.js's frame swaps y and z.
    var w = _weather(30)
    w.sun_azimuth_angle = Angle(90, DEGREE)
    var s = sun_direction(w)
    assert_almost_equal(s.y, 0.5, atol=1e-6)
    assert_almost_equal(s.z, Float32(sqrt(3.0) / 2), atol=1e-6)
    # The moon stands opposite, at 50 degrees.
    var m = moon_direction(w)
    assert_almost_equal(
        m.y, Float32(sin(50 * 3.141592653589793 / 180)), atol=1e-5
    )
    assert_almost_equal(
        m.z, Float32(-cos(50 * 3.141592653589793 / 180)), atol=1e-5
    )


def test_air_mass_is_kasten_young() raises:
    # From the textbook formula in Python.
    assert_almost_equal(air_mass(Angle(90, DEGREE)), 0.99971199, atol=1e-5)
    assert_almost_equal(air_mass(Angle(30, DEGREE)), 1.99429285, atol=1e-4)
    assert_almost_equal(air_mass(Angle(0, DEGREE)), 37.9196084, atol=1e-2)
    # Below the horizon it keeps the horizon's.
    assert_almost_equal(air_mass(Angle(-20, DEGREE)), 37.9196084, atol=1e-2)


def test_daylight_and_night() raises:
    assert_almost_equal(daylight(_weather(-2)), 0.5, atol=1e-6)
    assert_almost_equal(daylight(_weather(10)), 1, atol=1e-6)
    assert_almost_equal(daylight(_weather(-10)), 0, atol=1e-6)
    assert_true(is_night(_weather(-1)))
    assert_false(is_night(_weather(1)))
    assert_true(street_lights_on(weather_preset("ClearNight")))
    assert_false(street_lights_on(weather_preset("ClearNoon")))


def test_sun_intensity() raises:
    # 4.2 exp(-0.22 m) (1 - 0.82 c) daylight, worked in Python.
    assert_almost_equal(sun_intensity(_weather(45, 5)), 2.95190099, atol=1e-4)
    assert_almost_equal(sun_intensity(_weather(30, 50)), 1.59792731, atol=1e-4)
    assert_almost_equal(sun_intensity(_weather(-10)), 0, atol=1e-7)
    # Clouds past 100 percent count as 100.
    assert_almost_equal(
        sun_intensity(_weather(90, 250)),
        SUN_INTENSITY * Float32(exp(-0.22 * 0.99971199)) * (1 - CLOUD_SHADE),
        atol=1e-4,
    )


def test_moon_intensity_and_color() raises:
    assert_almost_equal(moon_intensity(_weather(-90, 60)), 0.06096, atol=1e-6)
    assert_almost_equal(
        moon_intensity(_weather(-2)), MOON_INTENSITY / 2, atol=1e-6
    )
    assert_almost_equal(moon_intensity(_weather(20)), 0, atol=1e-7)
    var c = moon_color()
    var k = kelvin_color(Temperature(8000, KELVIN))
    assert_almost_equal(c.b, k.b, atol=1e-6)
    # A cool light: more blue than red.
    assert_true(c.b > c.r)


def test_sun_color_warms_toward_the_horizon() raises:
    var low = sun_color(_weather(2))
    var high = sun_color(_weather(80))
    assert_true(low.r / low.b > high.r / high.b)
    # Above 55 degrees the sun keeps its noon color, a black body at 5800 K.
    var noon = kelvin_color(Temperature(5800, KELVIN))
    assert_almost_equal(high.g, noon.g, atol=1e-5)
    # Full cloud mixes 60 percent of the way to a pale gray-blue.
    var gray = sun_color(_weather(80, 100))
    assert_almost_equal(gray.r, noon.r + (0.9 - noon.r) * 0.6, atol=1e-5)
    assert_almost_equal(gray.b, noon.b + (1.0 - noon.b) * 0.6, atol=1e-5)


# The sky, the fog, the wet road and the rain.


def test_sky_settings() raises:
    var w = _weather(45, 5)
    var sky = sky_settings(w)
    # 2 + 6 (1 - smoothstep(0, 55, 45)) + 8 (0.05), worked in Python.
    assert_almost_equal(sky.turbidity, 2.92291510, atol=1e-4)
    assert_almost_equal(sky.rayleigh, 3, atol=1e-5)
    assert_almost_equal(sky.mie_coefficient, 0, atol=1e-7)
    assert_almost_equal(sky.cloud_cover, 0.05, atol=1e-6)
    w = _weather(15, 60)
    w.dust_storm = 20
    w.rayleigh_scattering_scale = 0.05
    w.mie_scattering_scale = 0.06
    sky = sky_settings(w)
    assert_almost_equal(sky.turbidity, 13.7045830, atol=1e-4)
    assert_almost_equal(sky.rayleigh, 4.53172205, atol=1e-4)
    assert_almost_equal(sky.mie_coefficient, 0.01, atol=1e-6)
    # Negative scales count as zero.
    w.rayleigh_scattering_scale = -1
    w.mie_scattering_scale = -1
    sky = sky_settings(w)
    assert_equal(sky.rayleigh, 0)
    assert_equal(sky.mie_coefficient, 0)
    assert_true("turbidity" in String(sky))


def test_height_fog_mapping() raises:
    var w = WeatherParameters()
    w.fog_density = 50
    w.fog_distance = Length(20, METER)
    w.fog_falloff = 0.5
    w.scattering_intensity = 2
    w.mie_scattering_scale = 0.03
    var fog = height_fog(w)
    # Half of the 0.03 per meter extinction.
    assert_almost_equal(fog.density.to(PER_METER), 0.015, atol=1e-7)
    assert_almost_equal(fog.start.to(METER), 20, atol=1e-6)
    assert_almost_equal(fog.falloff.to(PER_METER), 0.5, atol=1e-7)
    assert_almost_equal(fog.scattering, 2, atol=1e-7)
    assert_almost_equal(
        fog.haze.to(PER_METER), HAZE_EXTINCTION.to(PER_METER), atol=1e-8
    )
    assert_true(fog.is_on())
    assert_true("HeightFog" in String(fog))
    # The dust storm adds 60 percent of its own, and the sum stops at 100.
    w.dust_storm = 100
    assert_almost_equal(height_fog(w).density.to(PER_METER), 0.03, atol=1e-7)
    # Nothing at all is off.
    var clear = WeatherParameters()
    clear.fog_distance = Length(-5, METER)
    clear.fog_falloff = -1
    clear.scattering_intensity = -1
    clear.mie_scattering_scale = -1
    var none = height_fog(clear)
    assert_false(none.is_on())
    assert_equal(none.start.to(METER), 0)
    assert_equal(none.falloff.to(PER_METER), 0)
    assert_equal(none.scattering, 0)
    # A haze alone is on.
    clear.mie_scattering_scale = 0.03
    assert_true(height_fog(clear).is_on())


def test_optical_depth_is_the_closed_form_integral() raises:
    var fog = HeightFog(
        InverseLength(0.01, PER_METER),
        Length(5, METER),
        InverseLength(0.2, PER_METER),
        1,
        InverseLength(0, PER_METER),
    )
    # Worked in Python from the integral of d exp(-b (h0 + r s)).
    assert_almost_equal(
        fog.optical_depth(Length(2, METER), 0.1, Length(105, METER)),
        0.262222830,
        atol=1e-5,
    )
    # A level ray sees a constant density.
    assert_almost_equal(
        fog.optical_depth(Length(2, METER), 0, Length(105, METER)),
        0.670320046,
        atol=1e-5,
    )
    # Nothing before the fog starts.
    assert_equal(fog.optical_depth(Length(2, METER), 0.1, Length(4, METER)), 0)


def test_wet_surface() raises:
    var dry = wet_surface(WeatherParameters())
    assert_equal(dry.wetness, 0)
    assert_equal(dry.albedo_scale(), 1)
    assert_equal(dry.roughness(0.9), 0.9)
    var w = WeatherParameters()
    w.precipitation = 30
    w.precipitation_deposits = 80
    var wet = wet_surface(w)
    assert_almost_equal(wet.wetness, 0.8, atol=1e-6)
    assert_almost_equal(wet.puddles, 0.4, atol=1e-6)
    # 0.9 moved 80 percent of the way to WET_ROUGHNESS.
    assert_almost_equal(
        wet.roughness(0.9), 0.9 + (WET_ROUGHNESS - 0.9) * 0.8, atol=1e-6
    )
    # Never rougher than when dry.
    assert_almost_equal(wet.roughness(0.1), 0.1, atol=1e-7)
    assert_almost_equal(
        wet.albedo_scale(), 1 + (WET_DARKENING - 1) * 0.8, atol=1e-6
    )
    w.precipitation = 90
    assert_almost_equal(wet_surface(w).wetness, 0.9, atol=1e-6)
    assert_true("WetSurface" in String(wet))


def test_rain_settings() raises:
    var none = rain_settings(WeatherParameters())
    assert_false(none.is_on())
    assert_equal(none.streaks(1000, 1000), 0)
    var w = WeatherParameters()
    w.precipitation = 50
    w.wind_intensity = 100
    var rain = rain_settings(w)
    assert_true(rain.is_on())
    assert_almost_equal(rain.density, RAIN_STREAKS / 2, atol=1e-3)
    assert_almost_equal(rain.lean.to(DEGREE), 18, atol=1e-5)
    assert_almost_equal(rain.opacity, 0.45, atol=1e-6)
    # 3000 per million pixels over 800 by 600 pixels.
    assert_equal(rain.streaks(800, 600), 1440)
    assert_true("RainSettings" in String(rain))


# The textures.


def test_hash_is_a_32_bit_integer_hash() raises:
    # The same mix in Python's integers, taken mod 2^32.
    assert_almost_equal(hash2(1, 2, 3), 0.32981825, atol=1e-7)
    assert_almost_equal(hash2(5, 7, 11), 0.62303811, atol=1e-7)
    assert_equal(hash2(0, 0, 0), 0)


def test_noise_tiles() raises:
    # At a lattice point the noise is the point's hash, wrapped.
    assert_almost_equal(tile_noise(2, 3, 4, 9), hash2(2, 3, 9), atol=1e-7)
    assert_almost_equal(tile_noise(6, 7, 4, 9), hash2(2, 3, 9), atol=1e-7)
    assert_almost_equal(
        tile_noise(0.3, 0.8, 4, 9), tile_noise(4.3, 4.8, 4, 9), atol=1e-6
    )
    # Halfway between two points the smooth step is one half.
    assert_almost_equal(
        tile_noise(0.5, 0, 4, 9),
        (hash2(0, 0, 9) + hash2(1, 0, 9)) / 2,
        atol=1e-6,
    )
    assert_equal(tile_fbm(0.1, 0.2, 3, 0, 4), 0)
    var a = tile_fbm(0.1, 0.2, 3, 3, 4)
    assert_almost_equal(a, tile_fbm(1.1, 1.2, 3, 3, 4), atol=1e-5)
    assert_true(a >= 0 and a <= 1)


def test_normal_map() raises:
    var flat = normal_map([Float32(1), 1, 1, 1], 2, 3)
    # Straight out: x and y at the middle, z at the top.
    assert_equal(flat.pixels[0], 128)
    assert_equal(flat.pixels[1], 128)
    assert_equal(flat.pixels[2], 255)
    # A height that rises to the right tilts the normal to the left.
    var ramp = normal_map([Float32(0), 1, 2, 0, 1, 2, 0, 1, 2], 3, 1)
    # Texel (1, 0): dx = 2 - 0, so n = (-2, 0, 1) / sqrt(5).
    var x = Float32(-2) / Float32(sqrt(5.0)) * 0.5 + 0.5
    assert_equal(Int(ramp.pixels[4]), Int(x * 255 + 0.5))
    with assert_raises(contains="one height per texel"):
        _ = normal_map([Float32(0)], 2, 1)
    with assert_raises(contains="at least one texel"):
        _ = normal_map(List[Float32](), 0, 1)


def test_surface_maps() raises:
    var a = asphalt_maps(8)
    assert_equal(a.color.width, 8)
    assert_equal(a.normal.width, 8)
    assert_equal(a.emissive.width, 1)
    place(a, Length(4, METER))
    assert_almost_equal(a.color.repeat.x, 0.25, atol=1e-7)
    assert_almost_equal(a.emissive.repeat.y, 0.25, atol=1e-7)
    # Asphalt is dark: its tone is 0.3, and a stone moves it by 0.14,
    # the mottle by 0.06 and a patch by 0.035 at most.
    for i in range(0, len(a.color.pixels), 4):
        assert_true(a.color.pixels[i] > 16 and a.color.pixels[i] < 128)
    var c = concrete_maps(8, 2, 3)
    assert_equal(c.roughness.width, 8)
    var g = grass_maps(4)
    # Grass is greener than it is red or blue.
    assert_true(g.color.pixels[1] > g.color.pixels[0])
    assert_true(g.color.pixels[1] > g.color.pixels[2])
    var f = foliage_maps(4)
    assert_true(f.color.pixels[1] > f.color.pixels[2])
    with assert_raises(contains="at least one texel"):
        _ = asphalt_maps(0)
    with assert_raises(contains="at least one slab"):
        _ = concrete_maps(4, 0)


def test_facades() raises:
    assert_true(SHOPFRONT.is_valid())
    assert_false(FacadeStyle(4).is_valid())
    assert_false(FacadeStyle(-1).is_valid())
    assert_equal(String(BRICK), "FacadeStyle(1)")
    with assert_raises(contains="one of the four"):
        _ = wall_color(FacadeStyle(7), 0, 0, 0.5)
    # Plaster is pale and warm, brick red, panels gray, a shop's stone dark.
    var plaster = wall_color(PLASTER, 0, 0, 0.5)
    assert_almost_equal(plaster[0], 0.78, atol=1e-6)
    assert_almost_equal(plaster[2], 0.6, atol=1e-6)
    var brick = wall_color(BRICK, 0.1, 0.03, 0.5)
    assert_true(brick[0] > brick[1] and brick[0] > brick[2])
    var panel = wall_color(PANELS, 0.7, 1.5, 0.5)
    assert_almost_equal(panel[0], 0.6, atol=1e-6)
    var stone = wall_color(SHOPFRONT, 0, 0, 0.5)
    assert_almost_equal(stone[0], 0.3, atol=1e-6)
    # A 12-texel tile has one texel per meter. The texel at 1.5 m across
    # and 1.5 m up, row 10, is in a window: smooth glass. The texel at
    # 0.5 m across is wall.
    var maps = facade_maps(PLASTER, 12)
    assert_true(maps.roughness.pixels[(10 * 12 + 1) * 4] < 40)
    assert_true(maps.roughness.pixels[(10 * 12 + 0) * 4] > 200)
    # A shop window starts 0.25 m up: row 11 (0.5 m up) is glass.
    var shop = facade_maps(SHOPFRONT, 12)
    assert_true(shop.roughness.pixels[(11 * 12 + 1) * 4] < 40)
    # Seven tenths of the shop windows are lit; some texel glows.
    var lit = 0
    for i in range(0, len(shop.emissive.pixels), 4):
        if shop.emissive.pixels[i] > 0:
            lit += 1
    assert_true(lit > 0)
    with assert_raises(contains="one of the four"):
        _ = facade_maps(FacadeStyle(9), 4)
    with assert_raises(contains="at least one texel"):
        _ = facade_maps(BRICK, 0)
    assert_almost_equal(FACADE_TILE.to(METER), 12, atol=1e-6)


def test_puddles() raises:
    var maps = asphalt_maps(8)
    ref dry = maps.roughness
    # No puddle: every texel is the wet cap or less.
    var none = puddle_roughness(dry, -1, 0.3, 0.02)
    for i in range(0, len(none.pixels), 4):
        assert_true(none.pixels[i + 1] <= 77)
    # All puddle: every texel is the puddle's.
    var all = puddle_roughness(dry, 2, 0.3, 0.02)
    for i in range(0, len(all.pixels), 4):
        assert_equal(Int(all.pixels[i + 1]), 5)
    var odd = Texture(2, 1, List[UInt8](length=8, fill=0))
    with assert_raises(contains="square"):
        _ = puddle_roughness(odd, 0.5, 0.3, 0.02)


# The image effects.


def _frame(
    color: FloatColor, depth: Float32, size: Int = 1
) raises -> RenderTarget:
    var frame = RenderTarget(size, size, Color(0, 0, 0))
    for i in range(size * size):
        frame.colors[i] = color
        frame.depth[i] = depth
    return frame^


def _uniform_cube(color: FloatColor) raises -> CubeTexture:
    """Return a 1-texel cube of one linear color, stored as floats."""
    var faces = List[Texture]()
    for _ in range(6):
        faces.append(
            float_texture(1, 1, [color.r, color.g, color.b, Float32(1)])
        )
    return CubeTexture(faces^)


def _rays(size: Int) raises -> ViewRays:
    # A 90 degree camera at the origin, looking down minus z, near 1 and
    # far 100.
    return ViewRays(size, size, perspective(-1, 1, 1, -1, 1, 100), Matrix4())


def test_luminance_and_phase() raises:
    assert_almost_equal(luminance(FloatColor(1, 1, 1)), 1, atol=1e-6)
    assert_almost_equal(luminance(FloatColor(0, 1, 0)), 0.7152, atol=1e-6)
    # g = 0 scatters evenly: 1 / (4 pi).
    assert_almost_equal(henyey_greenstein(0.3, 0), 0.0795774715, atol=1e-6)
    # g = 0.6 straight ahead: 0.64 / (4 pi 0.4^3).
    assert_almost_equal(henyey_greenstein(1, 0.6), 0.795774715, atol=1e-5)


def test_view_rays() raises:
    var rays = _rays(1)
    var d = rays.direction(0, 0)
    assert_almost_equal(d.z, -1, atol=1e-6)
    # A point 10 m in front sits at window depth 0.9090...: with n = 1
    # and f = 100, ndc z = (101 / 99 * 10 - 200 / 99) / 10.
    assert_almost_equal(rays.distance(0, 0, 0.9090909).to(METER), 10, atol=1e-2)
    assert_equal(rays.distance(0, 0, 1).to(METER), SKY_DISTANCE.to(METER))
    assert_equal(
        rays.distance(0, 0, inf[DType.float32]()).to(METER),
        SKY_DISTANCE.to(METER),
    )


def test_fog_color_and_height_fog() raises:
    var fog = HeightFog(
        InverseLength(0.1, PER_METER),
        Length(0, METER),
        InverseLength(0, PER_METER),
        1,
        InverseLength(0, PER_METER),
    )
    var horizon = FloatColor(0.2, 0.3, 0.4)
    var sky_cube = _uniform_cube(horizon)
    var tint = fog_color(
        horizon, Vector3(0, 0, -1), FloatColor(1, 1, 1), fog, Vector3(0, 0, -1)
    )
    var phase = henyey_greenstein(1, FOG_PHASE_G)
    assert_almost_equal(tint.r, 0.2 + phase * 0.08, atol=1e-6)
    # A surface 10 m away keeps exp(-1) of its light.
    var frame = _frame(FloatColor(1, 1, 1), 0.9090909)
    apply_height_fog(
        frame,
        _rays(1),
        fog,
        sky_cube,
        Vector3(0, 0, -1),
        FloatColor(0, 0, 0),
        Length(0, METER),
    )
    var keep = Float32(exp(-1.0))
    assert_almost_equal(frame.colors[0].r, keep + 0.2 * (1 - keep), atol=1e-3)
    # The haze dims a surface but not the sky.
    fog.density = InverseLength(0, PER_METER)
    fog.haze = InverseLength(0.1, PER_METER)
    var sky = _frame(FloatColor(1, 1, 1), 1)
    apply_height_fog(
        sky,
        _rays(1),
        fog,
        sky_cube,
        Vector3(0, 1, 0),
        FloatColor(0, 0, 0),
        Length(0, METER),
    )
    assert_almost_equal(sky.colors[0].r, 1, atol=1e-6)
    var hazed = _frame(FloatColor(1, 1, 1), 0.9090909)
    apply_height_fog(
        hazed,
        _rays(1),
        fog,
        sky_cube,
        Vector3(0, 1, 0),
        FloatColor(0, 0, 0),
        Length(0, METER),
    )
    assert_almost_equal(hazed.colors[0].r, keep + 0.2 * (1 - keep), atol=1e-3)
    # No fog, no change.
    fog.haze = InverseLength(0, PER_METER)
    var clear = _frame(FloatColor(1, 1, 1), 0.5)
    apply_height_fog(
        clear,
        _rays(1),
        fog,
        sky_cube,
        Vector3(0, 1, 0),
        FloatColor(0, 0, 0),
        Length(0, METER),
    )
    assert_equal(clear.colors[0].r, 1)


def test_rain() raises:
    var rain = RainSettings(1e6, Angle(10, DEGREE), 0.5)
    # Over the sky every streak shows.
    var open = _frame(FloatColor(0, 0, 0), 1, 8)
    draw_rain(open, _rays(8), rain, FloatColor(1, 1, 1), 3)
    var bright = Float32(0)
    for c in open.colors:
        bright += c.r
    assert_true(bright > 0)
    # A streak that leans hard to the left leaves by the left edge.
    var left = _frame(FloatColor(0, 0, 0), 1, 8)
    draw_rain(
        left,
        _rays(8),
        RainSettings(1e6, Angle(-80, DEGREE), 0.5),
        FloatColor(1, 1, 1),
        5,
    )
    assert_true(left.colors[0].r >= 0)
    # A wall 0.5 m away hides every streak, which falls 1.5 m or more away.
    var hidden = _frame(FloatColor(0, 0, 0), 0.0, 8)
    draw_rain(hidden, _rays(8), rain, FloatColor(1, 1, 1), 3)
    for c in hidden.colors:
        assert_equal(c.r, 0)
    # No rain, no streak.
    var dry = _frame(FloatColor(0, 0, 0), 1, 8)
    draw_rain(
        dry,
        _rays(8),
        RainSettings(0, Angle(0, DEGREE), 0),
        FloatColor(1, 1, 1),
        3,
    )
    assert_equal(dry.colors[0].r, 0)


def test_metering() raises:
    # A gray of luminance 2^-3 falls in bin 44 of 80 from -14 to 6, whose
    # middle is -2.875.
    var frame = _frame(FloatColor(0.125, 0.125, 0.125), 0.5, 4)
    assert_almost_equal(
        metered_luminance(frame), Float32(0.13631343), atol=1e-6
    )
    # Black and far too bright pixels land in the end bins, whose
    # middles are -13.875 and 5.875.
    var black = _frame(FloatColor(0, 0, 0), 0.5, 2)
    assert_almost_equal(
        metered_luminance(black), Float32(0.0000665593), atol=1e-8
    )
    var white = _frame(FloatColor(1000, 1000, 1000), 0.5, 2)
    assert_almost_equal(metered_luminance(white), Float32(58.688259), atol=1e-3)


def test_gains_and_gamma() raises:
    var frame = _frame(FloatColor(0.5, 0.5, 0.5), 0.5)
    apply_gains(frame, FloatColor(2, 1, 0.5))
    assert_almost_equal(frame.colors[0].r, 1, atol=1e-7)
    assert_almost_equal(frame.colors[0].b, 0.25, atol=1e-7)
    apply_gamma(frame, 2.2)
    assert_almost_equal(frame.colors[0].b, 0.25, atol=1e-7)
    apply_gamma(frame, 1.1)
    assert_almost_equal(frame.colors[0].b, 0.0625, atol=1e-6)
    frame.colors[0] = FloatColor(-1, 0.5, 0.5)
    apply_gamma(frame, 1.1)
    assert_equal(frame.colors[0].r, 0)
    with assert_raises(contains="positive"):
        apply_gamma(frame, 0)


def test_lens() raises:
    var flat = LensSettings(0, 0, 0.08, 0.08, 5, 0)
    assert_false(flat.bends())
    assert_false(LensSettings(-1, 0, 0, 0, 5, 0).bends())
    assert_true(LensSettings(0, 1, 0, 0.08, 5, 0).bends())
    var lens = LensSettings(-1, 0, 0.08, 0.08, 5, 0)
    assert_true(lens.bends())
    assert_true("LensSettings" in String(lens))
    # The corners read the corners and the middle the middle.
    var corner = lens_source(lens, 1, 1)
    assert_almost_equal(corner[0], 1, atol=1e-6)
    assert_almost_equal(corner[1], 1, atol=1e-6)
    var middle = lens_source(lens, 0, 0)
    assert_equal(middle[0], 0)
    # A barrel: halfway out reads nearer the middle. r^2 = 1/4, so the
    # place is scaled by (1 + 0.02 / 4) / (1 + 0.02).
    var half = lens_source(lens, 0.5, 0.5)
    assert_almost_equal(half[0], 0.5 * 1.005 / 1.02, atol=1e-6)
    # The falloff: 1 - m r^f.
    assert_equal(lens_falloff(lens, 1, 1), 1)
    var dark = LensSettings(0, 0, 0, 0, 2, 1)
    assert_almost_equal(lens_falloff(dark, 1, 1), 0, atol=1e-6)
    assert_almost_equal(lens_falloff(dark, 0, 1), 0.5, atol=1e-6)
    # A plain lens leaves a frame alone; a uniform frame stays uniform
    # through a bend; the falloff darkens the corners.
    var frame = _frame(FloatColor(1, 1, 1), 0.5, 4)
    apply_lens(frame, flat)
    assert_equal(frame.colors[0].r, 1)
    apply_lens(frame, lens)
    assert_almost_equal(frame.colors[0].r, 1, atol=1e-6)
    apply_lens(frame, dark)
    assert_true(frame.colors[0].r < frame.colors[5].r)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
