# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's weather: `WeatherParameters` and its presets.

The weather is data. A world keeps one `WeatherParameters`, and the
renderer reads it to draw the sun, the sky, the fog, the rain and the wet
road. The fourteen fields, their defaults and the twenty-three presets
are CARLA's, from `LibCarla/source/carla/rpc/WeatherParameters.h` and
`WeatherParameters.cpp`. The ranges of `clamped` and the two screen
effects are from CARLA's simulator plugin, `Carla/Weather/WeatherParameters.h`
and `Carla/Weather/Weather.cpp`.

**Units.** The sun's angles are `Angle`s and the fog distance is a
`Length`. Cloudiness, precipitation, deposits, wind, fog density, wetness
and dust are percentages from 0 to 100; the fog falloff and the three
scattering values are plain factors. A preset's -1 means "keep what the
town has", as in CARLA's `Default` preset.
"""

from units.si import DEGREE, METER, Angle, Length


struct WeatherParameters(Equatable, ImplicitlyCopyable, Writable):
    """The weather of a world, CARLA's `rpc::WeatherParameters`."""

    # Percent, 0 to 100.
    var cloudiness: Float32
    var precipitation: Float32
    var precipitation_deposits: Float32
    var wind_intensity: Float32
    var sun_azimuth_angle: Angle
    var sun_altitude_angle: Angle
    # Percent, 0 to 100.
    var fog_density: Float32
    # Where the fog starts.
    var fog_distance: Length
    # How fast the fog thins with height.
    var fog_falloff: Float32
    # Percent, 0 to 100.
    var wetness: Float32
    var scattering_intensity: Float32
    var mie_scattering_scale: Float32
    var rayleigh_scattering_scale: Float32
    # Percent, 0 to 100.
    var dust_storm: Float32

    def __init__(out self):
        """Create CARLA's field defaults: all zero but the Rayleigh scale."""
        self = WeatherParameters(
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Float32(0.0331), 0
        )

    def __init__(
        out self,
        cloudiness: Float32,
        precipitation: Float32,
        precipitation_deposits: Float32,
        wind_intensity: Float32,
        sun_azimuth_degrees: Float32,
        sun_altitude_degrees: Float32,
        fog_density: Float32,
        fog_distance_meters: Float32,
        fog_falloff: Float32,
        wetness: Float32,
        scattering_intensity: Float32,
        mie_scattering_scale: Float32,
        rayleigh_scattering_scale: Float32,
        dust_storm: Float32,
    ):
        """Create a weather in CARLA's argument order.

        Args:
            cloudiness: Percent of the sky covered.
            precipitation: Percent of rain.
            precipitation_deposits: Percent of the road under puddles.
            wind_intensity: Percent of wind.
            sun_azimuth_degrees: The sun's bearing, in degrees.
            sun_altitude_degrees: The sun's height, in degrees.
            fog_density: Percent of fog.
            fog_distance_meters: Where the fog starts, in meters.
            fog_falloff: How fast the fog thins with height.
            wetness: Percent of wetness on the camera's view.
            scattering_intensity: How much light the fog scatters.
            mie_scattering_scale: The scattering by large particles.
            rayleigh_scattering_scale: The scattering by the air.
            dust_storm: Percent of dust.
        """
        self.cloudiness = cloudiness
        self.precipitation = precipitation
        self.precipitation_deposits = precipitation_deposits
        self.wind_intensity = wind_intensity
        self.sun_azimuth_angle = Angle(sun_azimuth_degrees, DEGREE)
        self.sun_altitude_angle = Angle(sun_altitude_degrees, DEGREE)
        self.fog_density = fog_density
        self.fog_distance = Length(fog_distance_meters, METER)
        self.fog_falloff = fog_falloff
        self.wetness = wetness
        self.scattering_intensity = scattering_intensity
        self.mie_scattering_scale = mie_scattering_scale
        self.rayleigh_scattering_scale = rayleigh_scattering_scale
        self.dust_storm = dust_storm

    def __eq__(self, other: Self) -> Bool:
        """Return True if every field is equal, as CARLA compares.

        Args:
            other: The other weather.

        Returns:
            Whether all fourteen fields match exactly.
        """
        return (
            self.cloudiness == other.cloudiness
            and self.precipitation == other.precipitation
            and self.precipitation_deposits == other.precipitation_deposits
            and self.wind_intensity == other.wind_intensity
            and self.sun_azimuth_angle == other.sun_azimuth_angle
            and self.sun_altitude_angle == other.sun_altitude_angle
            and self.fog_density == other.fog_density
            and self.fog_distance == other.fog_distance
            and self.fog_falloff == other.fog_falloff
            and self.wetness == other.wetness
            and self.scattering_intensity == other.scattering_intensity
            and self.mie_scattering_scale == other.mie_scattering_scale
            and self.rayleigh_scattering_scale
            == other.rayleigh_scattering_scale
            and self.dust_storm == other.dust_storm
        )

    def clamped(self) -> WeatherParameters:
        """Return the weather with each field in the range CARLA's town
        weather accepts.

        The percentages go into 0 to 100, the azimuth into 0 to 360
        degrees, the altitude into -90 to 90, the fog distance and falloff
        to zero or more, the Mie scale into 0 to 5 and the Rayleigh scale
        into 0 to 2.

        Returns:
            The clamped weather.
        """
        var out = self
        out.cloudiness = _clamp(self.cloudiness, 0, 100)
        out.precipitation = _clamp(self.precipitation, 0, 100)
        out.precipitation_deposits = _clamp(self.precipitation_deposits, 0, 100)
        out.wind_intensity = _clamp(self.wind_intensity, 0, 100)
        out.sun_azimuth_angle = Angle(
            _clamp(self.sun_azimuth_angle.to(DEGREE), 0, 360), DEGREE
        )
        out.sun_altitude_angle = Angle(
            _clamp(self.sun_altitude_angle.to(DEGREE), -90, 90), DEGREE
        )
        out.fog_density = _clamp(self.fog_density, 0, 100)
        out.fog_distance = Length(max(self.fog_distance.value, 0), METER)
        out.fog_falloff = max(self.fog_falloff, 0)
        out.wetness = _clamp(self.wetness, 0, 100)
        out.scattering_intensity = _clamp(self.scattering_intensity, 0, 100)
        out.mie_scattering_scale = _clamp(self.mie_scattering_scale, 0, 5)
        out.rayleigh_scattering_scale = _clamp(
            self.rayleigh_scattering_scale, 0, 2
        )
        out.dust_storm = _clamp(self.dust_storm, 0, 100)
        return out

    def rain_screen_weight(self) -> Float32:
        """Return how strongly raindrops cover a camera's image.

        Returns:
            The precipitation over 100 when it rains, else zero. CARLA
            blends its raindrop effect by this weight.
        """
        return self.precipitation / 100 if self.precipitation > 0 else 0

    def dust_screen_weight(self) -> Float32:
        """Return how strongly dust covers a camera's image.

        Returns:
            The dust storm over 100 when there is one, else zero.
        """
        return self.dust_storm / 100 if self.dust_storm > 0 else 0

    def write_to(self, mut writer: Some[Writer]):
        """Write the weather as CARLA prints it.

        Args:
            writer: The destination.
        """
        writer.write(
            "WeatherParameters(cloudiness=",
            self.cloudiness,
            ", precipitation=",
            self.precipitation,
            ", precipitation_deposits=",
            self.precipitation_deposits,
            ", wind_intensity=",
            self.wind_intensity,
            ", sun_azimuth_angle=",
            self.sun_azimuth_angle.to(DEGREE),
            ", sun_altitude_angle=",
            self.sun_altitude_angle.to(DEGREE),
        )
        writer.write(
            ", fog_density=",
            self.fog_density,
            ", fog_distance=",
            self.fog_distance.value,
            ", fog_falloff=",
            self.fog_falloff,
            ", wetness=",
            self.wetness,
            ", scattering_intensity=",
            self.scattering_intensity,
            ", mie_scattering_scale=",
            self.mie_scattering_scale,
            ", rayleigh_scattering_scale=",
            self.rayleigh_scattering_scale,
            ", dust_storm=",
            self.dust_storm,
            ")",
        )


def _clamp(x: Float32, low: Float32, high: Float32) -> Float32:
    return min(max(x, low), high)


def _preset(
    cloudiness: Float32,
    precipitation: Float32,
    deposits: Float32,
    wind: Float32,
    altitude: Float32,
    fog: Float32,
    fog_distance: Float32,
    fog_falloff: Float32,
    wetness: Float32,
) -> WeatherParameters:
    """A preset: the azimuth is -1 and the scattering is 1, 0.03, 0.0331."""
    return WeatherParameters(
        cloudiness,
        precipitation,
        deposits,
        wind,
        -1,
        altitude,
        fog,
        fog_distance,
        fog_falloff,
        wetness,
        1,
        Float32(0.03),
        Float32(0.0331),
        0,
    )


def weather_preset_names() -> List[String]:
    """Return the names of CARLA's weather presets.

    Returns:
        The twenty-three names, in CARLA's order.
    """
    return [
        "Default",
        "ClearNoon",
        "CloudyNoon",
        "WetNoon",
        "WetCloudyNoon",
        "MidRainyNoon",
        "HardRainNoon",
        "SoftRainNoon",
        "ClearSunset",
        "CloudySunset",
        "WetSunset",
        "WetCloudySunset",
        "MidRainSunset",
        "HardRainSunset",
        "SoftRainSunset",
        "ClearNight",
        "CloudyNight",
        "WetNight",
        "WetCloudyNight",
        "SoftRainNight",
        "MidRainyNight",
        "HardRainNight",
        "DustStorm",
    ]


def weather_preset(name: String) raises -> WeatherParameters:
    """Return one of CARLA's weather presets, such as `ClearNoon`.

    Args:
        name: The preset's name, as `weather_preset_names` lists it.

    Returns:
        The preset's parameters.

    Raises:
        Error: If there is no preset of that name.
    """
    var t = (Float32(0.75), Float32(0.1))
    if name == "Default":
        return WeatherParameters(
            -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 1, 0.03, 0.0331, 0
        )
    if name == "ClearNoon":
        return _preset(5, 0, 0, 10, 45, 2, t[0], t[1], 0)
    if name == "CloudyNoon":
        return _preset(60, 0, 0, 10, 45, 3, t[0], t[1], 0)
    if name == "WetNoon":
        return _preset(5, 0, 50, 10, 45, 3, t[0], t[1], 0)
    if name == "WetCloudyNoon":
        return _preset(60, 0, 50, 10, 45, 3, t[0], t[1], 0)
    if name == "MidRainyNoon":
        return _preset(60, 60, 60, 60, 45, 3, t[0], t[1], 0)
    if name == "HardRainNoon":
        return _preset(100, 100, 90, 100, 45, 7, t[0], t[1], 0)
    if name == "SoftRainNoon":
        return _preset(20, 30, 50, 30, 45, 3, t[0], t[1], 0)
    if name == "ClearSunset":
        return _preset(5, 0, 0, 10, 15, 2, t[0], t[1], 0)
    if name == "CloudySunset":
        return _preset(60, 0, 0, 10, 15, 3, t[0], t[1], 0)
    if name == "WetSunset":
        return _preset(5, 0, 50, 10, 15, 2, t[0], t[1], 0)
    if name == "WetCloudySunset":
        return _preset(60, 0, 50, 10, 15, 2, t[0], t[1], 0)
    if name == "MidRainSunset":
        return _preset(60, 60, 60, 60, 15, 3, t[0], t[1], 0)
    if name == "HardRainSunset":
        return _preset(100, 100, 90, 100, 15, 7, t[0], t[1], 0)
    if name == "SoftRainSunset":
        return _preset(20, 30, 50, 30, 15, 2, t[0], t[1], 0)
    if name == "ClearNight":
        return _preset(5, 0, 0, 10, -90, 60, 75, 1, 0)
    if name == "CloudyNight":
        return _preset(60, 0, 0, 10, -90, 60, t[0], t[1], 0)
    if name == "WetNight":
        return _preset(5, 0, 50, 10, -90, 60, 75, 1, 60)
    if name == "WetCloudyNight":
        return _preset(60, 0, 50, 10, -90, 60, t[0], t[1], 60)
    if name == "SoftRainNight":
        return _preset(60, 30, 50, 30, -90, 60, t[0], t[1], 60)
    if name == "MidRainyNight":
        return _preset(80, 60, 60, 60, -90, 60, t[0], t[1], 80)
    if name == "HardRainNight":
        return _preset(100, 100, 90, 100, -90, 100, t[0], t[1], 100)
    if name == "DustStorm":
        var out = _preset(100, 0, 0, 100, 45, 2, t[0], t[1], 0)
        out.dust_storm = 100
        return out
    raise Error("No weather preset is named " + name)
