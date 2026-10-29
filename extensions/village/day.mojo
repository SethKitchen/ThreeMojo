# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's day and night.

A `DayCycle` keeps the hour of the day, from 0 to 24, and moves it on at
`hours_a_second`. Zero keeps the hour still. Its `daylight` is the share
of the day's light: one from `SUNRISE` to `SUNSET`, none at night, and a
smooth change over `TWILIGHT` hours round each. Its `dusk` is how much
the low sun reddens the sky and the light, most at sunrise and sunset.

The sun's direction and its shadows stay as the meadow baked them. The
day changes how much light there is, and its color:

1. `light` scales each light of the scene, after the weather has set it.
   A directional light is the sun: it takes `daylight`, and turns
   orange at dusk. At night it is the moon: `MOON` of its light, blue.
   Every other light is the sky: it keeps `MOONLIGHT` of its light at
   night, and turns the blue of moonlight. Indoors at night, the lamps
   keep the sky's light whole and warm. The fog darkens with the sky.
2. `night_sky` darkens a frame's sky toward the deep blue of night, warms
   it near the horizon at dusk, and pricks it with stars where the
   clouds leave it clear.

The pond's water is shaded by its own sun and sky, so `dim_water`
darkens the pixels it was composed into, by `water_light`, toward the
deep blue of the night sky that it mirrors.

The windows of the houses and the lanterns by their doors are drawn
unlit, so they glow at night: see `extensions.village.house_view`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.fog import exp2_fog
from core.scene import Scene
from extensions.vegetation.noise import hash01
from lights.light import DIRECTIONAL
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import floor, isinf
from units.si import PER_METER, SECOND, Duration, InverseLength

comptime SUNRISE = Float32(6)
"""The hour the sun rises."""
comptime SUNSET = Float32(19.5)
"""The hour the sun sets."""
comptime TWILIGHT = Float32(1)
"""How many hours either side of sunrise and sunset the light changes
over."""
comptime MOONLIGHT = Float32(0.5)
"""The share of the sky's light that is left at night."""
comptime MOON = Float32(0.15)
"""The share of the sun's light that the moon gives at night."""
comptime LAMPLIT = Vector3(1.0, 0.8, 0.6)
"""The tint of a room's light at night, from its lamps and its fire."""
comptime MOON_BLUE = Vector3(0.62, 0.72, 1.0)
"""The tint of moonlight."""
comptime DUSK_ORANGE = Vector3(1.0, 0.58, 0.32)
"""The tint of the low sun's light."""
comptime NIGHT_SKY = Vector3(8, 12, 30)
"""The color of the night sky, in sRGB bytes."""
comptime NIGHT_WATER = Vector3(6, 10, 22)
"""The color of the pond at night, as it mirrors the night sky, in sRGB
bytes."""
comptime STAR_GRID = Float32(220)
"""How many cells of the sky's direction a star can stand in, on each
axis of a unit direction."""
comptime STARS = Float32(0.004)
"""The share of the sky's cells that hold a star."""


struct DayCycle(ImplicitlyCopyable):
    """The hour of the day, and how fast it moves on."""

    var hour: Float32
    var hours_a_second: Float32

    def __init__(
        out self, hour: Float32 = 14, hours_a_second: Float32 = 0
    ) raises:
        """Begin a day at an hour.

        Args:
            hour: The hour, from 0 to less than 24. Fourteen, the default,
                is the afternoon that the meadow's sun was baked for.
            hours_a_second: How many hours pass in a second of the game.
                Zero, the default, keeps the hour still.

        Raises:
            Error: If the hour is not from 0 to less than 24, or the rate
                is negative or more than 24.
        """
        if not (hour >= 0 and hour < 24):
            raise Error("An hour must be from 0 to less than 24")
        if not (hours_a_second >= 0 and hours_a_second <= 24):
            raise Error("A day's rate must be from 0 to 24 hours a second")
        self.hour = hour
        self.hours_a_second = hours_a_second

    def daylight(self) -> Float32:
        """Return the share of the day's light at this hour.

        Returns:
            One by day, zero by night, and a smooth step between over
            `TWILIGHT` hours either side of sunrise and of sunset.
        """
        var up = smoothstep(SUNRISE - TWILIGHT, SUNRISE + TWILIGHT, self.hour)
        var down = smoothstep(SUNSET - TWILIGHT, SUNSET + TWILIGHT, self.hour)
        return up * (1 - down)

    def dusk(self) -> Float32:
        """Return how much the low sun reddens the light at this hour.

        Returns:
            One at sunrise and at sunset, falling to zero 1.5 hours either
            side.
        """
        var rise = 1 - abs(self.hour - SUNRISE) / 1.5
        var fall = 1 - abs(self.hour - SUNSET) / 1.5
        return max(Float32(0), max(rise, fall))

    def advance(mut self, delta: Duration) raises:
        """Move the hour on by a frame's time, round past midnight.

        Args:
            delta: The frame's time.

        Raises:
            Error: If the time is negative.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0):
            raise Error("A frame's time must not be negative")
        var hour = self.hour + self.hours_a_second * seconds
        self.hour = hour - 24 * floor(hour / 24)

    def sky_light(self) -> Float32:
        """Return the share of the sky's light at this hour.

        Returns:
            One by day, and `MOONLIGHT` by night.
        """
        return MOONLIGHT + (1 - MOONLIGHT) * self.daylight()

    def water_light(self) -> Float32:
        """Return the share of the water's own light at this hour.

        Returns:
            One by day, and `MOON` by night: the water reflects the night
            sky, and the moon's light under it.
        """
        return MOON + (1 - MOON) * self.daylight()

    def light(self, mut scene: Scene, indoors: Bool = False) raises:
        """Scale and tint each light of the scene, and darken its fog, for
        the hour. Call it after the weather has set the lights.

        At night the sun's light is the moon's: `MOON` of it, and blue.
        Indoors, the lamps light the room, so the sky's light keeps all
        its strength, warm, whatever the hour.

        Args:
            scene: The scene.
            indoors: Whether the camera is under a roof.

        Raises:
            Error: If the fog cannot be set.
        """
        var day = self.daylight()
        var dusk = self.dusk()
        var sky = self.sky_light()
        var night = 1 - day
        var sky_tint = MOON_BLUE
        if indoors:
            sky = 1
            sky_tint = LAMPLIT
        var white = Vector3(1, 1, 1)
        for ref light in scene.lights:
            var c = Vector3(
                Float32(light.color.r),
                Float32(light.color.g),
                Float32(light.color.b),
            )
            if light.kind == DIRECTIONAL:
                light.intensity *= day + (1 - day) * MOON
                c = c * (white + (DUSK_ORANGE - white) * dusk)
                c = c * (white + (MOON_BLUE - white) * night)
            else:
                light.intensity *= sky
                c = c * (white + (sky_tint - white) * night)
            light.color = _color(c)
        var f = scene.fog.color
        var shade = 0.12 + 0.88 * day
        var fog = Vector3(Float32(f.r), Float32(f.g), Float32(f.b)) * shade
        scene.fog = exp2_fog(
            _color(fog),
            InverseLength(scene.fog.density.value, PER_METER),
        )

    def night_sky(
        self,
        mut image: Framebuffer,
        camera: PerspectiveCamera,
        clear: Float32,
    ) raises:
        """Darken a frame's sky for the hour, warm it at dusk, and add its
        stars.

        A pixel shows the sky where its depth is infinite.

        Args:
            image: The frame, with its depths.
            camera: The camera that drew it.
            clear: The share of the sky that clouds leave clear, from 0 to
                1: the stars show through it.

        Raises:
            Error: If the frame has no depth for each pixel.
        """
        if len(image.depth) != image.width * image.height:
            raise Error("A frame needs a depth for each pixel")
        var day = self.daylight()
        var dusk = self.dusk()
        if day >= 1 and dusk <= 0:
            return
        var inverse = camera.projection_matrix()
        inverse.multiply(camera.view_matrix())
        inverse.invert()
        var eye = camera.position
        var d00 = inverse.transform_point(Vector3(-1, 1, 1)) - eye
        var across = inverse.transform_point(Vector3(1, 1, 1)) - eye - d00
        var down = inverse.transform_point(Vector3(-1, -1, 1)) - eye - d00
        var w = image.width
        var h = image.height
        # The stars come out once the twilight has mostly gone.
        var stars = (1 - smoothstep(0, 0.4, day)) * clear
        for y in range(h):  # pragma: no branch
            var fy = Float32(y) / Float32(h)
            for x in range(w):  # pragma: no branch
                var at = y * w + x
                if not isinf(image.depth[at]):
                    continue
                var d = d00 + across * (Float32(x) / Float32(w)) + down * fy
                d = d / d.length()
                var p = at * 4
                var c = Vector3(
                    Float32(image.pixels[p]),
                    Float32(image.pixels[p + 1]),
                    Float32(image.pixels[p + 2]),
                )
                # Low in the sky, the dusk's glow; and night over all.
                var low = 1 - smoothstep(0, 0.35, d.y)
                c = c * (
                    Vector3(1, 1, 1)
                    + (DUSK_ORANGE * 1.15 - Vector3(1, 1, 1)) * (dusk * low)
                )
                c = c + (NIGHT_SKY - c) * (1 - day)
                var cell = hash01(
                    Int(floor(d.x * STAR_GRID)),
                    Int(floor(d.z * STAR_GRID)) * 977
                    + Int(floor(d.y * STAR_GRID)),
                    83,
                )
                if cell < STARS:
                    # A star fades into the haze near the horizon.
                    var bright = 120 + 135 * hash01(Int(cell * 1.0e7), 1, 84)
                    var seen = stars * smoothstep(0.03, 0.12, d.y)
                    c = c + (Vector3(bright, bright, bright * 0.95) - c) * seen
                image.pixels[p] = UInt8(Int(min(Float32(255), c.x)))
                image.pixels[p + 1] = UInt8(Int(min(Float32(255), c.y)))
                image.pixels[p + 2] = UInt8(Int(min(Float32(255), c.z)))


def dim_water(
    mut image: Framebuffer, before: List[Float32], share: Float32
) raises:
    """Darken the pixels that the pond's water was composed into, toward
    `NIGHT_WATER`.

    The water is shaded by its own sun and sky. A pixel whose depth the
    water's composition changed shows the water. Its color is multiplied
    by the square of `share`, and `NIGHT_WATER` makes up the rest: so at
    night the pond mirrors the dark sky, and by day it is left as it is.

    Args:
        image: The frame, after the water was composed into it.
        before: Each pixel's depth before the water was composed.
        share: How much of the water's own light is left, from 0 to 1.

    Raises:
        Error: If the depths are not one a pixel.
    """
    var count = image.width * image.height
    if len(before) != count or len(image.depth) != count:
        raise Error("A frame needs a depth for each pixel")
    # A frame has a pixel or more.
    for k in range(count):  # pragma: no branch
        if image.depth[k] == before[k]:
            continue
        var p = k * 4
        var c = Vector3(
            Float32(image.pixels[p]),
            Float32(image.pixels[p + 1]),
            Float32(image.pixels[p + 2]),
        )
        var dark = c * (share * share) + NIGHT_WATER * (1 - share)
        image.pixels[p] = UInt8(Int(dark.x))
        image.pixels[p + 1] = UInt8(Int(dark.y))
        image.pixels[p + 2] = UInt8(Int(dark.z))


def _color(c: Vector3) -> Color:
    """Return a color of sRGB bytes, clamped and rounded."""
    return Color(
        UInt8(Int(min(Float32(255), max(Float32(0), c.x)) + 0.5)),
        UInt8(Int(min(Float32(255), max(Float32(0), c.y)) + 0.5)),
        UInt8(Int(min(Float32(255), max(Float32(0), c.z)) + 0.5)),
    )
