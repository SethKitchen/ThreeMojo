# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sky of a CARLA weather: a cube that is the background and the light.

`build_sky` draws three.js's `Sky`, Preetham's analytic daylight model,
into a cube around the camera with `renderers.environment.scene_cube`. It
then paints the weather's clouds and the night into the cube's faces, and
prefilters a copy with `render.pmrem.pmrem_from_cube` so that a rough
surface reads a blurred sky. The sharp cube is the background, and the
prefiltered cube is the environment every physical material reflects.

**Clouds.** A cloud layer is a well-known sky trick: each direction above
the horizon is projected onto a flat layer of cloud high overhead, and
Perlin's improved noise, summed over `CLOUD_OCTAVES` octaves, gives the
cloud's thickness there. The cloud cover sets how much of the noise shows.
A cloud is lit gray from the sky and silver toward the sun. Heavy cover
also turns the whole sky toward an overcast gray.

**Night.** Preetham's sky is black with the sun down. A night sky is a
faint blue glow that is brighter toward the horizon, as a town's light
makes it. The clouds at night reflect a little of that glow.

**Below the horizon** the cube holds the ground, lit by the sun and the
sky, so that a shiny car reflects a ground below it and not a second sky.

**Physical light.** Preetham's model gives the sky's colors but not its
brightness in lux. `build_sky` measures the light the finished sky casts
on level ground, `hemisphere_illuminance`, and scales the sky until that
light is `render_weather.sky_illuminance`: the sky of the daylight
availability formulas, in the renderer's units. The sun is then the
directional light at `sun_illuminance`, so the two agree as they do
outdoors.

**An HDRI.** `hdri_sky` builds the same two cubes from a photographed
panorama. It finds the panorama's sun, its brightest texel, and turns the
panorama about the vertical so that its sun stands at the weather's
azimuth. It caps each texel at `HDRI_SUN_CAP` times the mean of the upper
half, which takes the sun's disk out: the directional light is the sun.
It then scales the sky to `sky_illuminance`, as `build_sky` does, and puts
the same lit ground below the horizon.

**Cloud shadows.** `cloud_shadow_density` follows the sunlight from a
point up to the cloud layer, `CLOUD_HEIGHT` above the ground, and reads
the same noise the sky's clouds are drawn from there. `render_post` darkens
the sunlit part of the light by it.

The scales in this module are this port's own choices.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.carla.render_weather import (
    SkySettings,
    daylight,
    light_units,
    sky_illuminance,
    sky_settings,
    sun_color,
    sun_direction,
    sun_illuminance,
    sun_intensity,
)
from extensions.carla.weather import WeatherParameters
from math.noise import ImprovedNoise
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from objects.sky import Sky
from render.cube_texture import (
    FACE_COUNT,
    CubeTexture,
    cube_from_equirectangular,
    face_direction,
)
from render.cube_texture_store import CubeTextureId
from render.framebuffer import FloatColor
from render.pmrem import pmrem_from_cube
from render.texture import Texture
from renderers.environment import scene_cube
from renderers.renderer import Renderer
from std.math import asin, atan2, max, min, pi, pow, sin, sqrt
from units.si import DEGREE, METER, RADIAN, Angle, Length

# The night sky's glow at the horizon and overhead, in linear light.
comptime NIGHT_HORIZON = FloatColor(0.006, 0.007, 0.012)
comptime NIGHT_ZENITH = FloatColor(0.0007, 0.001, 0.0025)
# The ground's albedo below the horizon.
comptime GROUND = FloatColor(0.09, 0.085, 0.08)
# The light on the ground at night, from the town's own lamps, in the
# renderer's units.
comptime NIGHT_GROUND_LIGHT = Float32(0.05)
# How many octaves the cloud noise sums, and the size of the first.
comptime CLOUD_OCTAVES = 4
comptime CLOUD_SCALE = Float32(1.7)
# How high the cloud layer that casts shadows is.
comptime CLOUD_HEIGHT = Length(1000, METER)
# The sky's default size: texels on a side of each face.
comptime SKY_SIZE = 128
# An HDRI texel is capped at this many times the mean of the upper half.
comptime HDRI_SUN_CAP = Float32(16)


struct SkyLighting(ImplicitlyCopyable):
    """The cubes a weather's sky gives a scene."""

    # The sharp sky, for the background.
    var background: CubeTextureId
    # The prefiltered sky, for `Scene.environment`.
    var environment: CubeTextureId
    # The mean color near the horizon, in linear light, for the fog.
    var horizon: FloatColor

    def __init__(
        out self,
        background: CubeTextureId,
        environment: CubeTextureId,
        horizon: FloatColor,
    ):
        """Hold the two cubes and the horizon's color.

        Args:
            background: The sharp cube's id.
            environment: The prefiltered cube's id.
            horizon: The horizon's color.
        """
        self.background = background
        self.environment = environment
        self.horizon = horizon


def cloud_layer_density(
    noise: ImprovedNoise, u: Float32, v: Float32, cover: Float32
) raises -> Float32:
    """Return how thick the cloud layer is at a place on it.

    The noise is summed over `CLOUD_OCTAVES` octaves. A cover of zero
    shows no cloud and a cover of one shows cloud everywhere.

    Args:
        noise: The noise field.
        u: The place across the layer, in layer heights.
        v: The place along the layer, in layer heights.
        cover: The share of the sky the clouds cover, zero to one.

    Returns:
        The density, zero to one.

    Raises:
        Error: If the noise refuses a coordinate, which it does not for a
            finite place.
    """
    if cover <= 0:
        return 0
    var x = Float64(u * CLOUD_SCALE)
    var z = Float64(v * CLOUD_SCALE)
    var total = Float64(0)
    var weight = Float64(0.5)
    var frequency = Float64(1)
    # A constant count, more than zero.
    for _ in range(CLOUD_OCTAVES):  # pragma: no branch
        total += weight * noise.noise(x * frequency, 0.37, z * frequency)
        weight *= 0.5
        frequency *= 2.03
    var field = Float32(total) + Float32(0.5)
    var edge = 1 - cover
    return smoothstep(edge - Float32(0.08), edge + Float32(0.3), field)


def cloud_density(
    noise: ImprovedNoise, direction: Vector3, cover: Float32
) raises -> Float32:
    """Return how thick the cloud is in a direction, from zero to one.

    The direction is projected onto the layer overhead, and the density
    fades out toward the horizon.

    Args:
        noise: The noise field.
        direction: A unit direction, plus y up.
        cover: The share of the sky the clouds cover, zero to one.

    Returns:
        The density; zero at or below the horizon.

    Raises:
        Error: If the noise refuses a coordinate, which it does not for a
            finite direction.
    """
    if direction.y <= 0:
        return 0
    var lift = direction.y + Float32(0.12)
    return cloud_layer_density(
        noise, direction.x / lift, direction.z / lift, cover
    ) * smoothstep(0, Float32(0.12), direction.y)


def cloud_shadow_density(
    noise: ImprovedNoise, point: Vector3, sun: Vector3, cover: Float32
) raises -> Float32:
    """Return how thick the cloud is between a point and the sun.

    Args:
        noise: The noise field, the sky's.
        point: The point, in meters, in three.js's frame.
        sun: The unit direction toward the sun.
        cover: The share of the sky the clouds cover, zero to one.

    Returns:
        The density where the sunlight toward the point crosses the layer
        `CLOUD_HEIGHT` above the ground; zero with the sun down.

    Raises:
        Error: If the noise refuses a coordinate.
    """
    if sun.y <= 0:
        return 0
    var height = CLOUD_HEIGHT.to(METER)
    var run = (height - point.y) / sun.y
    return cloud_layer_density(
        noise,
        (point.x + sun.x * run) / height,
        (point.z + sun.z * run) / height,
        cover,
    )


def ground_light(weather: WeatherParameters) -> Float32:
    """Return the light that falls on level ground, in the renderer's
    units.

    Args:
        weather: The weather.

    Returns:
        The sun's light times the sine of its altitude, plus the sky's,
        plus `NIGHT_GROUND_LIGHT`.
    """
    var altitude = max(weather.sun_altitude_angle.to(RADIAN), 0)
    return (
        sun_intensity(weather) * sin(altitude)
        + light_units(sky_illuminance(weather))
        + NIGHT_GROUND_LIGHT
    )


def sky_texel(
    sky: FloatColor,
    direction: Vector3,
    settings: SkySettings,
    light: FloatColor,
    day: Float32,
    cloud: Float32,
    gain: Float32,
    ground: Float32,
) -> FloatColor:
    """Return one direction of the finished sky.

    Args:
        sky: Preetham's sky there.
        direction: The unit direction.
        settings: The sky's settings; its cover and sun are read.
        light: The sunlight's color times its intensity.
        day: The share of the sun that is up.
        cloud: The cloud density there, from `cloud_density`.
        gain: What Preetham's sky is scaled by.
        ground: The light on the ground, from `ground_light`.

    Returns:
        The color, in linear light.
    """
    var up = max(direction.y, 0)
    var night = _mix(NIGHT_HORIZON, NIGHT_ZENITH, sqrt(up))
    var clear = FloatColor(
        sky.r * gain * day + night.r,
        sky.g * gain * day + night.g,
        sky.b * gain * day + night.b,
    )
    # Overcast: the whole sky goes gray as the cover grows.
    var gray = (clear.r + clear.g + clear.b) / 3
    var overcast = _mix(
        clear,
        FloatColor(gray, gray * 1.02, gray * 1.06),
        pow(settings.cloud_cover, Float32(1.5)),
    )
    var toward = max(
        direction.x * settings.sun.x
        + direction.y * settings.sun.y
        + direction.z * settings.sun.z,
        0,
    )
    var silver = pow(toward, Float32(8)) * Float32(0.25)
    var shade = gray * Float32(0.9) + night.b * 2
    var lit = FloatColor(
        shade + light.r * silver * day + light.r * Float32(0.05) * day,
        shade + light.g * silver * day + light.g * Float32(0.05) * day,
        shade + light.b * silver * day + light.b * Float32(0.05) * day,
    )
    var colored = _mix(overcast, lit, cloud)
    return _mix(
        _ground_color(ground),
        colored,
        smoothstep(Float32(-0.04), Float32(0.01), direction.y),
    )


def _ground_color(ground: Float32) -> FloatColor:
    """Return the ground's shine under a light: its albedo over pi."""
    var shine = ground / Float32(pi)
    return FloatColor(GROUND.r * shine, GROUND.g * shine, GROUND.b * shine)


def texel_solid_angle(x: Int, y: Int, size: Int) -> Float32:
    """Return the solid angle a cube face's texel covers.

    Args:
        x: The texel's column.
        y: The texel's row.
        size: Texels on a side.

    Returns:
        `(2 / size)^2 / (1 + a^2 + b^2)^1.5`, with `a` and `b` the texel
        center's place on the face, from -1 to 1.
    """
    var a = (Float32(x) + 0.5) / Float32(size) * 2 - 1
    var b = (Float32(y) + 0.5) / Float32(size) * 2 - 1
    var side = Float32(2) / Float32(size)
    return side * side / pow(1 + a * a + b * b, Float32(1.5))


def hemisphere_illuminance(cube: CubeTexture) raises -> Float32:
    """Return the light a cube casts on level ground from above.

    The sum over the texels above the horizon of each texel's luminance
    times the sine of its height times its solid angle.

    Args:
        cube: A float cube of linear light.

    Returns:
        The illuminance, in the cube's units of light.

    Raises:
        Error: If a face is not a float texture of the cube's size.
    """
    var size = cube.size
    var total = Float32(0)
    # Six faces.
    for face in range(FACE_COUNT):  # pragma: no branch
        ref data = cube.faces[face].data
        if len(data) != size * size * 4:
            raise Error("A sky cube's faces must be float textures")
        # A cube's face has at least one texel.
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var d = face_direction(face, x, y, size)
                d.normalize()
                if d.y <= 0:
                    continue
                var at = (y * size + x) * 4
                var lum = (
                    0.2126 * data[at]
                    + 0.7152 * data[at + 1]
                    + 0.0722 * data[at + 2]
                )
                total += lum * d.y * texel_solid_angle(x, y, size)
    return total


def sky_key(weather: WeatherParameters) -> String:
    """Return the binding key of a weather's HDRI sky.

    Args:
        weather: The weather.

    Returns:
        `sky.night` with the sun below the horizon, `sky.overcast` at 60
        percent cloud or more, `sky.low_sun` with the sun under 25
        degrees, and `sky.clear` otherwise.
    """
    if weather.sun_altitude_angle.value < 0:
        return "sky.night"
    if weather.cloudiness >= 60:
        return "sky.overcast"
    if weather.sun_altitude_angle.to(DEGREE) < 25:
        return "sky.low_sun"
    return "sky.clear"


def _lighting(mut assets: Assets, var cube: CubeTexture) raises -> SkyLighting:
    """Add a finished sky cube and its prefiltered copy to the stores,
    and measure the horizon."""
    var size = cube.size
    var horizon = FloatColor(0, 0, 0)
    var counted = 0
    # Six faces.
    for face in range(FACE_COUNT):  # pragma: no branch
        ref data = cube.faces[face].data
        # A cube's face has at least one texel.
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var d = face_direction(face, x, y, size)
                d.normalize()
                if d.y > 0 and d.y < Float32(0.15):
                    var at = (y * size + x) * 4
                    horizon = FloatColor(
                        horizon.r + data[at],
                        horizon.g + data[at + 1],
                        horizon.b + data[at + 2],
                    )
                    counted += 1
    var mean = Float32(1) / Float32(max(counted, 1))
    var environment = pmrem_from_cube(cube)
    return SkyLighting(
        assets.cube_textures.add(cube^),
        assets.cube_textures.add(environment^),
        FloatColor(horizon.r * mean, horizon.g * mean, horizon.b * mean),
    )


def _paint(
    mut cube: CubeTexture,
    raw: List[List[Float32]],
    noise: ImprovedNoise,
    weather: WeatherParameters,
    gain: Float32,
) raises:
    """Paint every texel of the cube from Preetham's raw sky."""
    var settings = sky_settings(weather)
    var tint = sun_color(weather)
    var strength = sun_intensity(weather)
    var light = FloatColor(
        tint.r * strength, tint.g * strength, tint.b * strength
    )
    var day = daylight(weather)
    var ground = ground_light(weather)
    var size = cube.size
    # Six faces.
    for face in range(FACE_COUNT):  # pragma: no branch
        ref data = cube.faces[face].data
        # A cube's face has at least one texel.
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var direction = face_direction(face, x, y, size)
                direction.normalize()
                var at = (y * size + x) * 4
                var seen = sky_texel(
                    FloatColor(
                        raw[face][at], raw[face][at + 1], raw[face][at + 2]
                    ),
                    direction,
                    settings,
                    light,
                    day,
                    cloud_density(noise, direction, settings.cloud_cover),
                    gain,
                    ground,
                )
                data[at] = seen.r
                data[at + 1] = seen.g
                data[at + 2] = seen.b


def build_sky(
    renderer: Renderer,
    mut assets: Assets,
    weather: WeatherParameters,
    size: Int = SKY_SIZE,
) raises -> SkyLighting:
    """Draw a weather's sky into a cube and add the two cubes to the stores.

    The sky is painted at a gain of zero and of one, measured each time,
    and painted again at the gain that makes its light on level ground
    `sky_illuminance`. The light that does not grow with the gain, the
    night's glow and the sunlit edges of the clouds, counts toward it.

    Args:
        renderer: What to take the drawing settings and workers from.
        assets: The stores. The sky's program, the cubes and their faces
            are added.
        weather: The weather.
        size: Texels on a side of each face.

    Returns:
        The two cubes and the horizon's color.

    Raises:
        Error: If the sky cannot be drawn or prefiltered.
    """
    var settings = sky_settings(weather)
    var scene = Scene()
    var dome = Object3D()
    dome.set_scale(40, 40, 40)
    var sky = Sky(assets, scene.add(dome^))
    scene.add_mesh(sky.mesh)
    ref program = assets.programs.get(sky.program)
    program.set_uniform("turbidity", settings.turbidity)
    program.set_uniform("rayleigh", settings.rayleigh)
    program.set_uniform("mieCoefficient", settings.mie_coefficient)
    program.set_uniform("mieDirectionalG", settings.mie_directional_g)
    program.set_uniform("sunPosition", settings.sun)
    scene.update()
    var cube = scene_cube(
        renderer,
        scene,
        assets,
        Length(0.1, METER),
        Length(100, METER),
        size,
    )
    var raw = List[List[Float32]]()
    # Six faces.
    for face in range(FACE_COUNT):  # pragma: no branch
        raw.append(cube.faces[face].data.copy())
    var noise = ImprovedNoise()
    # The sky's light is the light at no gain, which the gain does not
    # touch, plus the gain times what one unit of gain adds.
    _paint(cube, raw, noise, weather, 0)
    var fixed = hemisphere_illuminance(cube)
    _paint(cube, raw, noise, weather, 1)
    var per_gain = hemisphere_illuminance(cube) - fixed
    var target = light_units(sky_illuminance(weather))
    var gain = max(target - fixed, 0) / per_gain if per_gain > 0 else Float32(0)
    _paint(cube, raw, noise, weather, gain)
    return _lighting(assets, cube^)


def hdri_sun_azimuth(panorama: Texture) raises -> Angle:
    """Return the azimuth of a panorama's brightest texel above the
    horizon.

    Args:
        panorama: A float equirectangular panorama, its top row the sky.

    Returns:
        The azimuth, `atan2(z, x)` of the texel's direction, as
        `render.cube_texture.equirect_uv` measures it.

    Raises:
        Error: If the panorama is not a float texture.
    """
    var w = panorama.width
    var h = panorama.height
    if len(panorama.data) != w * h * 4:
        raise Error("An HDRI must be a float texture")
    var best = Float32(-1)
    var column = 0
    # The top half is above the horizon; a panorama has at least a row.
    for y in range(max(h // 2, 1)):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var at = (y * w + x) * 4
            var lum = (
                0.2126 * panorama.data[at]
                + 0.7152 * panorama.data[at + 1]
                + 0.0722 * panorama.data[at + 2]
            )
            if lum > best:
                best = lum
                column = x
    var u = (Float32(column) + 0.5) / Float32(w)
    return Angle((u - 0.5) * 2 * Float32(pi), RADIAN)


def hdri_sky(
    mut assets: Assets,
    panorama: Texture,
    weather: WeatherParameters,
    size: Int = SKY_SIZE,
) raises -> SkyLighting:
    """Build a weather's sky from a photographed panorama.

    The panorama is turned so its sun stands at the weather's sun's
    azimuth, capped at `HDRI_SUN_CAP` times its upper half's mean, scaled
    so its light on level ground is `sky_illuminance`, and given the lit
    ground below the horizon.

    Args:
        assets: The stores; the two cubes are added.
        panorama: A float equirectangular panorama.
        weather: The weather.
        size: Texels on a side of each face.

    Returns:
        The two cubes and the horizon's color.

    Raises:
        Error: If the panorama is not a float texture, or the cube cannot
            be made or prefiltered.
    """
    var sun = sun_direction(weather)
    var turn = Float32(
        atan2(Float64(sun.z), Float64(sun.x))
    ) - hdri_sun_azimuth(panorama).to(RADIAN)
    var cube = cube_from_equirectangular(panorama, size, False)
    var ground = _ground_color(ground_light(weather))
    var total = FloatColor(0, 0, 0)
    var count = 0
    # Two sweeps: the turned panorama and its mean, then the cap, the
    # scale and the ground.
    for sweep in range(2):  # pragma: no branch
        var cap = (
            HDRI_SUN_CAP
            * (0.2126 * total.r + 0.7152 * total.g + 0.0722 * total.b)
            / Float32(max(count, 1))
        )
        # Six faces.
        for face in range(FACE_COUNT):  # pragma: no branch
            ref data = cube.faces[face].data
            # A cube's face has at least one texel.
            for y in range(size):  # pragma: no branch
                for x in range(size):  # pragma: no branch
                    var d = face_direction(face, x, y, size)
                    d.normalize()
                    var at = (y * size + x) * 4
                    if sweep == 0:
                        var azimuth = (
                            Float32(atan2(Float64(d.z), Float64(d.x))) - turn
                        )
                        var seen = panorama.sample(
                            azimuth / (2 * Float32(pi)) + 0.5,
                            asin(max(Float32(-1), min(Float32(1), d.y)))
                            / Float32(pi)
                            + 0.5,
                        )
                        data[at] = seen.r
                        data[at + 1] = seen.g
                        data[at + 2] = seen.b
                        if d.y > 0:
                            total = FloatColor(
                                total.r + seen.r,
                                total.g + seen.g,
                                total.b + seen.b,
                            )
                            count += 1
                    else:
                        var lum = (
                            0.2126 * data[at]
                            + 0.7152 * data[at + 1]
                            + 0.0722 * data[at + 2]
                        )
                        var keep = min(cap / max(lum, Float32(1e-9)), 1)
                        data[at] *= keep
                        data[at + 1] *= keep
                        data[at + 2] *= keep
    var measured = hemisphere_illuminance(cube)
    var target = light_units(sky_illuminance(weather))
    var gain = target / measured if measured > 0 else Float32(0)
    # Six faces.
    for face in range(FACE_COUNT):  # pragma: no branch
        ref data = cube.faces[face].data
        # A cube's face has at least one texel.
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var d = face_direction(face, x, y, size)
                d.normalize()
                var at = (y * size + x) * 4
                var above = smoothstep(Float32(-0.04), Float32(0.01), d.y)
                var sky = FloatColor(
                    data[at] * gain, data[at + 1] * gain, data[at + 2] * gain
                )
                var seen = _mix(ground, sky, above)
                data[at] = seen.r
                data[at + 1] = seen.g
                data[at + 2] = seen.b
    return _lighting(assets, cube^)


def _mix(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor:
    """Return `a` moved toward `b` by `t`."""
    return FloatColor(
        a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t
    )
