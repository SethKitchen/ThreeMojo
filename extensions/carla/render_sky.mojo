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

**Below the horizon** the cube holds the ground's color, so that a shiny
car reflects a ground below it and not a second sky.

The scales in this module are this port's own choices.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.carla.render_weather import (
    SkySettings,
    daylight,
    sky_settings,
    sun_color,
    sun_intensity,
)
from extensions.carla.weather import WeatherParameters
from math.noise import ImprovedNoise
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from objects.sky import Sky
from render.cube_texture import FACE_COUNT, CubeTexture, face_direction
from render.cube_texture_store import CubeTextureId
from render.framebuffer import FloatColor
from render.pmrem import pmrem_from_cube
from renderers.environment import scene_cube
from renderers.renderer import Renderer
from std.math import exp, max, min, pow, sqrt
from units.si import METER, Length

# What Preetham's sky is scaled by, against `SUN_INTENSITY`'s sunlight.
comptime SKY_SCALE = Float32(0.15)
# The night sky's glow at the horizon and overhead, in linear light.
comptime NIGHT_HORIZON = FloatColor(0.006, 0.007, 0.012)
comptime NIGHT_ZENITH = FloatColor(0.0007, 0.001, 0.0025)
# The ground's color below the horizon, in linear light, by day.
comptime GROUND = FloatColor(0.09, 0.085, 0.08)
# How many octaves the cloud noise sums, and the size of the first.
comptime CLOUD_OCTAVES = 4
comptime CLOUD_SCALE = Float32(1.7)
# The sky's default size: texels on a side of each face.
comptime SKY_SIZE = 128


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


def cloud_density(
    noise: ImprovedNoise, direction: Vector3, cover: Float32
) raises -> Float32:
    """Return how thick the cloud is in a direction, from zero to one.

    The direction is projected onto a layer overhead, where the noise is
    summed over `CLOUD_OCTAVES` octaves. A cover of zero shows no cloud
    and a cover of one shows cloud everywhere.

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
    if direction.y <= 0 or cover <= 0:
        return 0
    var lift = direction.y + Float32(0.12)
    var x = Float64(direction.x / lift * CLOUD_SCALE)
    var z = Float64(direction.z / lift * CLOUD_SCALE)
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
    var thick = smoothstep(edge - Float32(0.08), edge + Float32(0.3), field)
    return thick * smoothstep(0, Float32(0.12), direction.y)


def sky_texel(
    sky: FloatColor,
    direction: Vector3,
    settings: SkySettings,
    light: FloatColor,
    day: Float32,
    cloud: Float32,
) -> FloatColor:
    """Return one direction of the finished sky.

    Args:
        sky: Preetham's sky there, before `SKY_SCALE`.
        direction: The unit direction.
        settings: The sky's settings; its cover and sun are read.
        light: The sunlight's color times its intensity.
        day: The share of the sun that is up.
        cloud: The cloud density there, from `cloud_density`.

    Returns:
        The color, in linear light.
    """
    var up = max(direction.y, 0)
    var night = _mix(NIGHT_HORIZON, NIGHT_ZENITH, sqrt(up))
    var clear = FloatColor(
        sky.r * SKY_SCALE * day + night.r,
        sky.g * SKY_SCALE * day + night.g,
        sky.b * SKY_SCALE * day + night.b,
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
    var ground = FloatColor(
        GROUND.r * (day + Float32(0.05)),
        GROUND.g * (day + Float32(0.05)),
        GROUND.b * (day + Float32(0.05)),
    )
    return _mix(
        ground, colored, smoothstep(Float32(-0.04), Float32(0.01), direction.y)
    )


def build_sky(
    renderer: Renderer,
    mut assets: Assets,
    weather: WeatherParameters,
    size: Int = SKY_SIZE,
) raises -> SkyLighting:
    """Draw a weather's sky into a cube and add the two cubes to the stores.

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
    var tint = sun_color(weather)
    var strength = sun_intensity(weather)
    var light = FloatColor(
        tint.r * strength, tint.g * strength, tint.b * strength
    )
    var day = daylight(weather)
    var noise = ImprovedNoise()
    var horizon = FloatColor(0, 0, 0)
    var counted = 0
    # Six faces.
    for face in range(FACE_COUNT):  # pragma: no branch
        ref data = cube.faces[face].data
        # The cube refuses a face of no texels.
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var direction = face_direction(face, x, y, size)
                direction.normalize()
                var at = (y * size + x) * 4
                var cloud = cloud_density(
                    noise, direction, settings.cloud_cover
                )
                var seen = sky_texel(
                    FloatColor(data[at], data[at + 1], data[at + 2]),
                    direction,
                    settings,
                    light,
                    day,
                    cloud,
                )
                data[at] = seen.r
                data[at + 1] = seen.g
                data[at + 2] = seen.b
                if direction.y > 0 and direction.y < Float32(0.15):
                    horizon = FloatColor(
                        horizon.r + seen.r,
                        horizon.g + seen.g,
                        horizon.b + seen.b,
                    )
                    counted += 1
    var mean = Float32(1) / Float32(max(counted, 1))
    var environment = pmrem_from_cube(cube)
    return SkyLighting(
        assets.cube_textures.add(cube^),
        assets.cube_textures.add(environment^),
        FloatColor(horizon.r * mean, horizon.g * mean, horizon.b * mean),
    )


def _mix(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor:
    """Return `a` moved toward `b` by `t`."""
    return FloatColor(
        a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t
    )
