# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A summer sky with clouds, baked once into the cube behind the scene.

`paint_sky` draws three.js's `Sky`, Preetham's analytic model of the light
the atmosphere scatters, into a cube with `scene_cube`. It then paints
clouds into each face and makes the cube the scene's background. The cube
is read once a pixel, which costs less than running Preetham's shader on
every pixel of every frame.

**Clouds.** Each direction above the horizon is projected onto a flat
layer of cloud overhead. Four octaves of value noise give the cloud's
thickness there, and `cloud_cover` sets how much of it shows. A cloud is
lit by how much cloud lies between it and the sun, read a little way
along the layer toward the sun. So a cloud is white on its sunward edge,
gray and a little blue where more cloud shades it, and brighter toward
the sun, as a summer cumulus is.

**The color.** `gain` scales Preetham's light to the light of the scene.
`saturation` deepens the blue: Preetham's clear sky is pale once it is
tone mapped, and a summer sky over a meadow looks deeper. One keeps
Preetham's color.

**Below the horizon** the cube holds the haze, the mean color of the sky
just above the horizon, so the edge of the ground fades into it. The fog
of the scene takes the same color.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.noise import value_noise
from math.smoothstep import smoothstep
from math.utils import rec709_luminance
from math.vector3 import Vector3
from objects.sky import Sky
from render.cube_texture import FACE_COUNT, CubeTexture, face_direction
from render.cube_texture_store import CubeTextureId
from render.framebuffer import Color
from render.srgb import linear_to_srgb
from render.texture import BILINEAR, CLAMP, IGNORED, Texture, float_texture
from renderers.environment import scene_cube
from renderers.renderer import Renderer
from std.math import pow, sqrt
from units.si import METER, Length

# How many octaves the cloud noise sums.
comptime CLOUD_OCTAVES = 4
# How high above the horizon the haze band reaches, as the sine of the
# angle.
comptime HAZE_BAND = Float32(0.12)
# Texels on a side of the small cube Preetham's sky is drawn into.
comptime PREETHAM_SIZE = 48
# How far along the cloud layer toward the sun a cloud looks for the
# cloud that shades it, as a change of direction.
comptime SELF_SHADOW = Float32(0.05)


struct SkyLook(ImplicitlyCopyable):
    """How the sky looks: the air, how bright and how deep it is, and its
    clouds."""

    # How hazy the air is, Preetham's `turbidity`, from 1 to 20.
    var turbidity: Float32
    # How much the air scatters blue, Preetham's `rayleigh`, from 0 to 4.
    var rayleigh: Float32
    # What Preetham's light is multiplied by, from 0 to 100.
    var gain: Float32
    # How far the color is pushed from gray, from 0 to 4. One keeps it.
    var saturation: Float32
    # What each linear channel is multiplied by, from 0 to 4, after the
    # saturation. Preetham's deepened blue leans to cyan; less green
    # turns it to the blue of a summer sky.
    var tint: Vector3
    # The share of the sky the clouds cover, from 0 to 1.
    var cloud_cover: Float32
    # How many clouds fit across one layer height, from 0.1 to 20.
    var cloud_scale: Float32
    # Which clouds to paint.
    var seed: Int

    def __init__(out self):
        """Create a clear summer sky with a few fair-weather clouds."""
        self.turbidity = 2.5
        self.rayleigh = 1.6
        self.gain = 0.55
        self.saturation = 1.7
        self.tint = Vector3(0.85, 0.88, 1.12)
        self.cloud_cover = 0.42
        self.cloud_scale = 1.6
        self.seed = 9

    def check(self) raises:
        """Refuse a value outside the range its field names.

        Raises:
            Error: If a value is out of its range, or NaN.
        """
        require_between(
            self.turbidity, 1, 20, "A sky's turbidity must be from 1 to 20"
        )
        require_between(
            self.rayleigh, 0, 4, "A sky's rayleigh must be from 0 to 4"
        )
        require_between(self.gain, 0, 100, "A sky's gain must be from 0 to 100")
        require_between(
            self.saturation, 0, 4, "A sky's saturation must be from 0 to 4"
        )
        require_between(self.tint.x, 0, 4, "A sky's tint must be from 0 to 4")
        require_between(self.tint.y, 0, 4, "A sky's tint must be from 0 to 4")
        require_between(self.tint.z, 0, 4, "A sky's tint must be from 0 to 4")
        require_between(
            self.cloud_cover, 0, 1, "A sky's cloud cover must be from 0 to 1"
        )
        require_between(
            self.cloud_scale,
            0.1,
            20,
            "A sky's cloud scale must be from 0.1 to 20",
        )


def cloud_density(direction: Vector3, look: SkyLook) -> Float32:
    """Return how thick the cloud is in a direction, from zero to one.

    Args:
        direction: A unit direction, +y up.
        look: The sky; its cover, scale and seed are read.

    Returns:
        The density. It fades to zero at the horizon.
    """
    var lift = max(direction.y, 0) + Float32(0.1)
    var u = direction.x / lift * look.cloud_scale
    var v = direction.z / lift * look.cloud_scale
    var total = Float32(0)
    var weight = Float32(0.5)
    var frequency = Float32(1)
    for octave in range(CLOUD_OCTAVES):  # pragma: no branch
        total += weight * value_noise(
            u * frequency + 17, v * frequency - 3, look.seed + octave
        )
        weight *= 0.5
        frequency *= 2.07
    var field = total / Float32(0.9375)
    var edge = 1 - look.cloud_cover
    return smoothstep(edge - 0.04, edge + 0.22, field) * smoothstep(
        0, 0.15, direction.y
    )


@fieldwise_init
struct SkyDome(ImplicitlyCopyable):
    """The painted sky: its cube, and the haze color at the horizon."""

    # The cube, in `assets.cube_textures`.
    var cube: CubeTextureId
    # The mean linear color just above the horizon.
    var horizon: Vector3

    def haze(self) -> Color:
        """Return the horizon's color in sRGB, for a fog.

        Returns:
            The color, each channel clamped to one before it is encoded.
        """
        return Color(
            _encode(self.horizon.x),
            _encode(self.horizon.y),
            _encode(self.horizon.z),
        )


def _encode(value: Float32) -> UInt8:
    """Return one linear channel as an sRGB byte, clamped to one."""
    var s = linear_to_srgb(min(Float32(1), max(Float32(0), value)))
    return UInt8(Int(s * 255 + 0.5))


def paint_sky(
    renderer: Renderer,
    mut assets: Assets,
    sun: Vector3,
    look: SkyLook,
    size: Int = 512,
) raises -> SkyDome:
    """Draw Preetham's sky into a cube, and paint its clouds and haze.

    Preetham's sky is smooth, so it is drawn into a small cube of
    `PREETHAM_SIZE` texels a side. Each texel of the large cube reads it
    through the bilinear filter. Only the clouds need the large cube.

    Args:
        renderer: What to take the drawing settings and workers from.
        assets: The stores. The sky's program, box and cube are added.
        sun: The unit direction toward the sun.
        look: How the sky looks.
        size: Texels on a side of each face, from 8 to 2048.

    Returns:
        The cube and its horizon color.

    Raises:
        Error: If `look.check` refuses a value, `size` is out of range,
            the sun is below the horizon, or the cube cannot be drawn.
    """
    look.check()
    require_count_between(
        size, 8, 2048, "A sky's faces must be 8 to 2048 texels"
    )
    require_between(sun.y, 0.0001, 1, "The sun must be above the horizon")
    var scene = Scene()
    var dome = Object3D()
    dome.set_scale(40, 40, 40)
    var sky = Sky(assets, scene.add(dome^))
    scene.add_mesh(sky.mesh)
    ref program = assets.programs.get(sky.program)
    program.set_uniform("turbidity", look.turbidity)
    program.set_uniform("rayleigh", look.rayleigh)
    program.set_uniform("sunPosition", sun)
    scene.update()
    var clear = scene_cube(
        renderer,
        scene,
        assets,
        Length(0.1, METER),
        Length(100, METER),
        PREETHAM_SIZE,
    )
    # Pass one: the clear sky, scaled, deepened and tinted, and the haze.
    var faces = List[List[Float32]]()
    var horizon = Vector3(0, 0, 0)
    var counted = 0
    var zenith = Float32(0)
    for face in range(FACE_COUNT):  # pragma: no branch
        var data = List[Float32](capacity=size * size * 4)
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var d = face_direction(face, x, y, size)
                d = d / d.length()
                var raw = clear.sample(d)
                var c = Vector3(raw.r, raw.g, raw.b) * look.gain
                var gray = rec709_luminance(c.x, c.y, c.z)
                c = (
                    Vector3(gray, gray, gray)
                    + (c - Vector3(gray, gray, gray)) * look.saturation
                )
                c = Vector3(
                    max(c.x, 0) * look.tint.x,
                    max(c.y, 0) * look.tint.y,
                    max(c.z, 0) * look.tint.z,
                )
                data.append(c.x)
                data.append(c.y)
                data.append(c.z)
                data.append(1)
                if d.y > 0 and d.y < HAZE_BAND:
                    horizon = horizon + c
                    counted += 1
                if d.y > 0.5:
                    zenith = max(zenith, rec709_luminance(c.x, c.y, c.z))
        faces.append(data^)
    horizon = horizon / Float32(max(counted, 1))
    # Pass two: the clouds over the clear sky, and the haze below. A
    # cloud is lit by how much cloud lies between it and the sun: the
    # density a little way along the layer toward the sun.
    var white = (
        max(zenith, rec709_luminance(horizon.x, horizon.y, horizon.z)) * 1.8
    )
    var level = sqrt(sun.x * sun.x + sun.z * sun.z)
    var sunward = Vector3(sun.x, 0, sun.z) * (
        SELF_SHADOW / max(level, Float32(1.0e-6))
    )
    var textures = List[Texture]()
    for face in range(FACE_COUNT):  # pragma: no branch
        ref data = faces[face]
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var d = face_direction(face, x, y, size)
                d = d / d.length()
                var at = (y * size + x) * 4
                if d.y <= 0:
                    data[at] = horizon.x
                    data[at + 1] = horizon.y
                    data[at + 2] = horizon.z
                    continue
                var cloud = cloud_density(d, look)
                var ahead = d + sunward
                var thick = cloud_density(ahead / ahead.length(), look)
                var lit = 1 - 0.7 * thick
                var toward = max(d.dot(sun), 0)
                var silver = 1 + 0.6 * pow(toward, Float32(6))
                var body = (
                    white
                    * silver
                    * (0.42 + 0.58 * lit)
                    * (1 - 0.2 * sqrt(cloud))
                )
                var fade = smoothstep(0, HAZE_BAND, d.y)
                var blend = cloud * (0.4 + 0.6 * fade)
                var r = body * (0.93 + 0.05 * lit)
                var g = body * (0.96 + 0.03 * lit)
                var b = body * 1.03
                data[at] += (r - data[at]) * blend
                data[at + 1] += (g - data[at + 1]) * blend
                data[at + 2] += (b - data[at + 2]) * blend
        textures.append(
            float_texture(
                size, size, data.copy(), CLAMP, BILINEAR, False, IGNORED
            )
        )
    return SkyDome(assets.cube_textures.add(CubeTexture(textures^)), horizon)
