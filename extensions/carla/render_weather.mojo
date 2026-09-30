# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's weather as render settings: sun, sky, fog, wet road and rain.

A world keeps its weather as CARLA's `WeatherParameters`, which is data.
This module turns that data into the numbers ThreeMojo's renderer reads.
Every mapping is a small pure function, so a test can check it by hand.
The renderer's side is in `render_sky`, `town` and `camera_render`.

**The sun.** The azimuth turns from CARLA's plus x toward plus y, and the
altitude rises from the horizon. A preset's azimuth of -1 means "the
town's sun", which is `TOWN_SUN_AZIMUTH`. The sun's light passes through
the air mass of the Kasten-Young formula, so it dims and reddens toward
the horizon. Its color is a black body from `SUNRISE_KELVIN` at the
horizon to `NOON_KELVIN` high in the sky. Cloud cover takes up to
`CLOUD_SHADE` of the direct light away. Below the horizon the sun fades
out over `TWILIGHT` and a moon lights the town instead.

**Physical daylight.** The sun and the sky are lit in lux, from the
well-known daylight availability formulas of lighting engineering. The
sun gives `SOLAR_ILLUMINANCE` outside the air, less `exp(-c m)` through an
air mass `m` with the clear-sky extinction `c` of `CLEAR_EXTINCTION`. A
clear sky gives `0.8 + 15.5 sqrt(sin h)` kilolux on the ground at a sun
altitude `h`, and an overcast sky `0.3 + 21 sin h` kilolux; the cloud
cover moves the sky from one to the other. `LUX_PER_UNIT` turns lux into
the renderer's light: a white wall under one unit shines `1 / pi` units,
and one unit of shine is `NITS_PER_UNIT` candela per square meter, so one
unit of light is `pi` times that in lux. `render_sky` scales its sky so
that the ground under it gets `sky_illuminance`, which makes the sky, an
HDRI and the sun agree.

**The sky.** The sky is Preetham's model, three.js's `Sky`. Its
turbidity rises with the clouds and the dust, its Rayleigh term follows
the Rayleigh scale over CARLA's default of 0.0331, and its Mie term
follows the Mie scale over CARLA's default of 0.03.

**Height fog.** The fog is an exponential height fog, a well-known model
of a fog that thins with height. Its extinction at the ground is the fog
density over 100 times `FOG_EXTINCTION`, it starts `fog_distance` from the
camera, and it thins by `exp(-fog_falloff * h)` at a height `h` in meters.
A ray's optical depth is the closed-form integral of that density along
the ray. The dust storm adds to the fog. An aerosol haze, as thick as
the Mie scale says, dims the distant town the same at every height: the
well-known aerial perspective.

**The wet road.** The precipitation and the deposits wet the road. A wet
surface is darker and smoother, as the well-known wet-surface models make
it: its roughness moves toward `WET_ROUGHNESS` and its albedo is scaled
toward `WET_DARKENING`. The deposits also make puddles, which cover a
share of the road.

**Rain.** The precipitation draws rain streaks over the image. The wind
leans them.

These constants are this port's own. They make the town look as CARLA's
weather looks, and they are not taken from any engine.
"""

from extensions.carla.weather import WeatherParameters
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.color_utils import kelvin_color
from render.framebuffer import FloatColor
from std.math import cos, exp, pow, sin, sqrt
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    RADIAN,
    Angle,
    InverseLength,
    Length,
)
from units.photometry import LUX, NIT, Illuminance, Luminance
from units.temperature import KELVIN, Temperature

# The sun's azimuth when a weather keeps the town's, as a preset's -1 does.
comptime TOWN_SUN_AZIMUTH = Angle(150, DEGREE)
# The luminance of one unit of the renderer's shine.
comptime NITS_PER_UNIT = Luminance(4000, NIT)
# The illuminance of one unit of the renderer's light: the light under
# which a white diffuse surface shines `NITS_PER_UNIT`, pi times it.
comptime LUX_PER_UNIT = Illuminance(
    Float32(3.141592653589793) * NITS_PER_UNIT.to(NIT), LUX
)
# The sun's illuminance outside the air, and the clear sky's extinction
# per unit of air mass.
comptime SOLAR_ILLUMINANCE = Illuminance(127500, LUX)
comptime CLEAR_EXTINCTION = Float32(0.21)
# The daylight availability formulas' terms: a clear sky's
# `CLEAR_SKY_BASE + CLEAR_SKY_GAIN sqrt(sin h)` and an overcast sky's
# `OVERCAST_BASE + OVERCAST_GAIN sin h`.
comptime CLEAR_SKY_BASE = Illuminance(800, LUX)
comptime CLEAR_SKY_GAIN = Illuminance(15500, LUX)
comptime OVERCAST_BASE = Illuminance(300, LUX)
comptime OVERCAST_GAIN = Illuminance(21000, LUX)
# The sun's color at the horizon and high in the sky.
comptime SUNRISE_KELVIN = Float32(1900)
comptime NOON_KELVIN = Float32(5800)
# The altitude, in degrees, above which the sun keeps its noon color.
comptime NOON_ALTITUDE = Float32(55)
# How far below the horizon the sun fades out, in degrees.
comptime TWILIGHT = Float32(4)
# How much of the direct light full cloud cover takes away.
comptime CLOUD_SHADE = Float32(0.82)
# The moon's light on a clear night, its altitude and its color.
comptime MOON_INTENSITY = Float32(0.12)
comptime MOON_ALTITUDE = Angle(50, DEGREE)
comptime MOON_KELVIN = Float32(8000)
# The fog's extinction at the ground at a density of 100 percent.
comptime FOG_EXTINCTION = InverseLength(0.03, PER_METER)
# The aerosol haze's extinction at CARLA's default Mie scale.
comptime HAZE_EXTINCTION = InverseLength(0.0012, PER_METER)
# What a full dust storm adds to the fog density, in percent.
comptime DUST_FOG = Float32(60)
# The roughness a fully wet surface moves toward, and a puddle's.
comptime WET_ROUGHNESS = Float32(0.18)
comptime PUDDLE_ROUGHNESS = Float32(0.04)
# What a fully wet surface's albedo is scaled by.
comptime WET_DARKENING = Float32(0.55)
# Rain streaks per million pixels at a precipitation of 100 percent.
comptime RAIN_STREAKS = Float32(6000)
# How far a streak leans at full wind.
comptime RAIN_LEAN = Angle(18, DEGREE)
# CARLA's default Rayleigh and Mie scales, which give the sky's defaults.
comptime CARLA_RAYLEIGH = Float32(0.0331)
comptime CARLA_MIE = Float32(0.03)


def _percent(value: Float32) -> Float32:
    """Return a CARLA percentage as a share from zero to one."""
    return min(max(value, 0), 100) / 100


def sun_azimuth(weather: WeatherParameters) -> Angle:
    """Return the sun's azimuth, or the town's when the weather keeps it.

    Args:
        weather: The weather.

    Returns:
        The azimuth, or `TOWN_SUN_AZIMUTH` for a negative azimuth.
    """
    if weather.sun_azimuth_angle.value < 0:
        return TOWN_SUN_AZIMUTH
    return weather.sun_azimuth_angle


def carla_direction(azimuth: Angle, altitude: Angle) -> Vector3:
    """Return the unit vector toward a point in the sky, in CARLA's frame.

    Args:
        azimuth: The turn from plus x toward plus y.
        altitude: The height above the horizon.

    Returns:
        The direction: plus x forward, plus y right, plus z up.
    """
    var a = azimuth.value
    var e = altitude.value
    return Vector3(cos(e) * cos(a), cos(e) * sin(a), sin(e))


def sun_direction(weather: WeatherParameters) -> Vector3:
    """Return the unit vector toward the sun, in three.js's frame.

    Args:
        weather: The weather.

    Returns:
        The direction: CARLA's x, z and y.
    """
    var d = carla_direction(sun_azimuth(weather), weather.sun_altitude_angle)
    return Vector3(d.x, d.z, d.y)


def moon_direction(weather: WeatherParameters) -> Vector3:
    """Return the unit vector toward the moon, in three.js's frame.

    The moon stands opposite the sun's azimuth, at `MOON_ALTITUDE`.

    Args:
        weather: The weather.

    Returns:
        The direction: CARLA's x, z and y.
    """
    var turn = Angle(sun_azimuth(weather).to(DEGREE) + 180, DEGREE)
    var d = carla_direction(turn, MOON_ALTITUDE)
    return Vector3(d.x, d.z, d.y)


def air_mass(altitude: Angle) -> Float32:
    """Return the relative air mass toward a sun at an altitude.

    The Kasten-Young formula. It is one overhead and about 38 at the
    horizon. A sun below the horizon takes the horizon's value.

    Args:
        altitude: The sun's altitude.

    Returns:
        The air mass.
    """
    var degrees = max(altitude.to(DEGREE), 0)
    var e = degrees * Float32(0.017453292519943295)
    return 1 / (
        sin(e)
        + Float32(0.50572) * pow(degrees + Float32(6.07995), Float32(-1.6364))
    )


def daylight(weather: WeatherParameters) -> Float32:
    """Return how much of the sun is up, from zero to one.

    Args:
        weather: The weather.

    Returns:
        Zero at `TWILIGHT` degrees below the horizon and lower, one at the
        horizon and higher, and a smooth step between.
    """
    return smoothstep(-TWILIGHT, 0, weather.sun_altitude_angle.to(DEGREE))


def is_night(weather: WeatherParameters) -> Bool:
    """Return True when the sun is below the horizon.

    Args:
        weather: The weather.

    Returns:
        Whether the altitude is less than zero.
    """
    return weather.sun_altitude_angle.value < 0


def sun_color(weather: WeatherParameters) raises -> FloatColor:
    """Return the sun's color, in linear light.

    Args:
        weather: The weather.

    Returns:
        A black body from `SUNRISE_KELVIN` at the horizon to `NOON_KELVIN`
        at `NOON_ALTITUDE`, mixed toward gray by the clouds.

    Raises:
        Error: Never; the color fit is passed on.
    """
    var high = smoothstep(
        0, NOON_ALTITUDE, weather.sun_altitude_angle.to(DEGREE)
    )
    var kelvin = SUNRISE_KELVIN + (NOON_KELVIN - SUNRISE_KELVIN) * high
    var warm = kelvin_color(Temperature(kelvin, KELVIN))
    var gray = _percent(weather.cloudiness) * Float32(0.6)
    return _mix(warm, FloatColor(0.9, 0.92, 1.0), gray)


def direct_normal_illuminance(altitude: Angle) -> Illuminance:
    """Return the clear sky's direct sunlight on a surface facing the sun.

    Args:
        altitude: The sun's altitude.

    Returns:
        `SOLAR_ILLUMINANCE exp(-CLEAR_EXTINCTION m)`, with `m` the air
        mass.
    """
    return SOLAR_ILLUMINANCE * exp(-CLEAR_EXTINCTION * air_mass(altitude))


def sun_illuminance(weather: WeatherParameters) -> Illuminance:
    """Return the direct sunlight on a surface facing the sun.

    Args:
        weather: The weather.

    Returns:
        `direct_normal_illuminance`, less the cloud shade, times
        `daylight`.
    """
    var shade = 1 - CLOUD_SHADE * _percent(weather.cloudiness)
    return (
        direct_normal_illuminance(weather.sun_altitude_angle)
        * shade
        * daylight(weather)
    )


def sky_illuminance(weather: WeatherParameters) -> Illuminance:
    """Return the sky's light on level ground, the sun's disk left out.

    Args:
        weather: The weather.

    Returns:
        The clear sky's `0.8 + 15.5 sqrt(sin h)` kilolux mixed toward the
        overcast sky's `0.3 + 21 sin h` kilolux by the cloud cover, at
        the sun's altitude `h` held at zero or more, times `daylight`.
    """
    var h = max(weather.sun_altitude_angle.to(RADIAN), 0)
    var clear = CLEAR_SKY_BASE + CLEAR_SKY_GAIN * sqrt(sin(h))
    var overcast = OVERCAST_BASE + OVERCAST_GAIN * sin(h)
    var cover = _percent(weather.cloudiness)
    return (clear + (overcast - clear) * cover) * daylight(weather)


def light_units(illuminance: Illuminance) -> Float32:
    """Return an illuminance in the renderer's units of light.

    Args:
        illuminance: The illuminance.

    Returns:
        `illuminance / LUX_PER_UNIT`.
    """
    return illuminance / LUX_PER_UNIT


def sun_intensity(weather: WeatherParameters) -> Float32:
    """Return how bright the direct sunlight is, in the renderer's units.

    Args:
        weather: The weather.

    Returns:
        `light_units(sun_illuminance(weather))`.
    """
    return light_units(sun_illuminance(weather))


def moon_intensity(weather: WeatherParameters) -> Float32:
    """Return how bright the moonlight is.

    Args:
        weather: The weather.

    Returns:
        `MOON_INTENSITY` less the cloud shade, times the share of the sun
        that is down.
    """
    var shade = 1 - CLOUD_SHADE * _percent(weather.cloudiness)
    return MOON_INTENSITY * shade * (1 - daylight(weather))


def moon_color() raises -> FloatColor:
    """Return the moon's color, a cool black body at `MOON_KELVIN`.

    Returns:
        The color, in linear light.

    Raises:
        Error: Never; the color fit is passed on.
    """
    return kelvin_color(Temperature(MOON_KELVIN, KELVIN))


def street_lights_on(weather: WeatherParameters) -> Bool:
    """Return True when the street lamps and the car lamps are lit.

    Args:
        weather: The weather.

    Returns:
        Whether the sun is below the horizon.
    """
    return is_night(weather)


@fieldwise_init
struct SkySettings(ImplicitlyCopyable, Writable):
    """The uniforms of three.js's `Sky` for a weather."""

    var turbidity: Float32
    var rayleigh: Float32
    var mie_coefficient: Float32
    var mie_directional_g: Float32
    # Toward the sun, in three.js's frame.
    var sun: Vector3
    # The share of the sky the clouds cover, zero to one.
    var cloud_cover: Float32

    def write_to(self, mut writer: Some[Writer]):
        """Write the settings.

        Args:
            writer: The destination.
        """
        writer.write(
            "SkySettings(turbidity=",
            self.turbidity,
            ", rayleigh=",
            self.rayleigh,
            ", mie=",
            self.mie_coefficient,
            ", cloud_cover=",
            self.cloud_cover,
            ")",
        )


def sky_settings(weather: WeatherParameters) -> SkySettings:
    """Return the sky for a weather.

    The turbidity is 2 in a clear sky with a high sun. It rises by up to
    6 as the sun sinks below `NOON_ALTITUDE`, as the long light path
    through the dusty low air makes a sunset's sky redder, by 8 with full
    cloud, and by 10 with a full dust storm. The Rayleigh term is 2 at CARLA's
    Rayleigh scale, and the Mie coefficient 0.005 at CARLA's Mie scale.

    Args:
        weather: The weather.

    Returns:
        The sky's uniforms and its cloud cover.
    """
    var clouds = _percent(weather.cloudiness)
    var dust = _percent(weather.dust_storm)
    var low = 1 - smoothstep(
        0, NOON_ALTITUDE, weather.sun_altitude_angle.to(DEGREE)
    )
    return SkySettings(
        2 + 6 * low + 8 * clouds + 10 * dust,
        3 * max(weather.rayleigh_scattering_scale, 0) / CARLA_RAYLEIGH,
        Float32(0.005) * max(weather.mie_scattering_scale, 0) / CARLA_MIE,
        Float32(0.8),
        sun_direction(weather),
        clouds,
    )


@fieldwise_init
struct HeightFog(ImplicitlyCopyable, Writable):
    """An exponential height fog."""

    # The extinction at height zero.
    var density: InverseLength
    # How far from the camera the fog starts.
    var start: Length
    # How fast the fog thins with height.
    var falloff: InverseLength
    # How much sunlight the fog scatters toward the camera, CARLA's
    # scattering intensity.
    var scattering: Float32
    # The aerosol haze's extinction, the same at every height. It dims
    # the surfaces and not the sky, whose model holds its own air.
    var haze: InverseLength

    def is_on(self) -> Bool:
        """Return True when the fog or the haze has any density.

        Returns:
            Whether either extinction is more than zero.
        """
        return self.density.value > 0 or self.haze.value > 0

    def optical_depth(
        self, eye_height: Length, rise: Float32, distance: Length
    ) -> Float32:
        """Return the fog's optical depth along a ray.

        The integral of `density * exp(-falloff * h)` from the start to the
        ray's end, where the height `h` rises by `rise` per meter.

        Args:
            eye_height: The camera's height above the fog's base.
            rise: The ray direction's vertical part, from -1 to 1.
            distance: How far the ray goes.

        Returns:
            The optical depth, zero or more. The light that reaches the
            camera is `exp` of minus this.
        """
        var run = distance.to(METER) - self.start.to(METER)
        if run <= 0:
            return 0
        var b = self.falloff.to(PER_METER)
        var h0 = eye_height.to(METER) + rise * self.start.to(METER)
        var base = self.density.to(PER_METER) * exp(-b * h0)
        var slope = b * rise
        if abs(slope * run) < Float32(1e-4):
            return base * run
        return base * (1 - exp(-slope * run)) / slope

    def write_to(self, mut writer: Some[Writer]):
        """Write the fog.

        Args:
            writer: The destination.
        """
        writer.write(
            "HeightFog(density=",
            self.density.to(PER_METER),
            ", start=",
            self.start.to(METER),
            ", falloff=",
            self.falloff.to(PER_METER),
            ")",
        )


def height_fog(weather: WeatherParameters) -> HeightFog:
    """Return the height fog of a weather.

    Args:
        weather: The weather.

    Returns:
        The fog: density from the fog density and the dust storm, start
        from the fog distance, falloff from the fog falloff per meter, the
        scattering intensity, and a haze of `HAZE_EXTINCTION` times the
        Mie scale over CARLA's default.
    """
    var percent = min(
        _percent(weather.fog_density)
        + _percent(weather.dust_storm) * DUST_FOG / 100,
        1,
    )
    return HeightFog(
        InverseLength(FOG_EXTINCTION.to(PER_METER) * percent, PER_METER),
        Length(max(weather.fog_distance.to(METER), 0), METER),
        InverseLength(max(weather.fog_falloff, 0), PER_METER),
        max(weather.scattering_intensity, 0),
        InverseLength(
            HAZE_EXTINCTION.to(PER_METER)
            * max(weather.mie_scattering_scale, 0)
            / CARLA_MIE,
            PER_METER,
        ),
    )


@fieldwise_init
struct WetSurface(ImplicitlyCopyable, Writable):
    """How wet the road is."""

    # Zero dry, one soaked.
    var wetness: Float32
    # The share of the road under puddles.
    var puddles: Float32

    def roughness(self, dry: Float32) -> Float32:
        """Return a surface's roughness when wet.

        Args:
            dry: Its roughness when dry.

        Returns:
            The roughness moved toward `WET_ROUGHNESS` by the wetness, and
            never rougher than when dry.
        """
        return min(dry, dry + (WET_ROUGHNESS - dry) * self.wetness)

    def albedo_scale(self) -> Float32:
        """Return what a wet surface's albedo is scaled by.

        Returns:
            One when dry and `WET_DARKENING` when soaked.
        """
        return 1 + (WET_DARKENING - 1) * self.wetness

    def write_to(self, mut writer: Some[Writer]):
        """Write the surface.

        Args:
            writer: The destination.
        """
        writer.write(
            "WetSurface(wetness=", self.wetness, ", puddles=", self.puddles, ")"
        )


def wet_surface(weather: WeatherParameters) -> WetSurface:
    """Return how wet the road is.

    Args:
        weather: The weather.

    Returns:
        The wetness, the larger of the precipitation and the deposits, and
        the puddles, half the deposits.
    """
    var deposits = _percent(weather.precipitation_deposits)
    return WetSurface(
        max(_percent(weather.precipitation), deposits), deposits / 2
    )


@fieldwise_init
struct RainSettings(ImplicitlyCopyable, Writable):
    """The rain streaks drawn over an image."""

    # Streaks per million pixels.
    var density: Float32
    # How far a streak leans from the vertical, toward the right.
    var lean: Angle
    # How bright a streak is, against the sky's light.
    var opacity: Float32

    def is_on(self) -> Bool:
        """Return True when any streak is drawn.

        Returns:
            Whether the density is more than zero.
        """
        return self.density > 0

    def streaks(self, width: Int, height: Int) -> Int:
        """Return how many streaks an image of a size gets.

        Args:
            width: The image's width in pixels.
            height: Its height in pixels.

        Returns:
            The density times the pixels, in millions, rounded down.
        """
        return Int(self.density * Float32(width * height) / 1e6)

    def write_to(self, mut writer: Some[Writer]):
        """Write the rain.

        Args:
            writer: The destination.
        """
        writer.write(
            "RainSettings(density=",
            self.density,
            ", lean=",
            self.lean.to(DEGREE),
            ")",
        )


def rain_settings(weather: WeatherParameters) -> RainSettings:
    """Return the rain of a weather.

    Args:
        weather: The weather.

    Returns:
        `RAIN_STREAKS` per million pixels times the precipitation, a lean
        of `RAIN_LEAN` times the wind, and an opacity that rises with the
        precipitation from 0.3 to 0.6.
    """
    var rain = _percent(weather.precipitation)
    return RainSettings(
        RAIN_STREAKS * rain,
        Angle(RAIN_LEAN.to(DEGREE) * _percent(weather.wind_intensity), DEGREE),
        Float32(0.3) + Float32(0.3) * rain,
    )


def _mix(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor:
    """Return `a` moved toward `b` by `t`."""
    return FloatColor(
        a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t
    )
