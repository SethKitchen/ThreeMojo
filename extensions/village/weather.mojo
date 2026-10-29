# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's weather: drifting clouds, overcast, rain with lightning,
and fog.

A `WeatherKind` names the weather. `weather_look` gives what each kind
looks like, as a `WeatherLook`:

| Kind | Clouds | Gloom | Rain | Fog density | Sun | Sky light |
|---|---|---|---|---|---|---|
| `CLEAR` | 0.25 | 0 | 0 | 0.0008 per meter | 1 | 1 |
| `OVERCAST` | 0.85 | 0.35 | 0 | 0.002 per meter | 0.12 | 2.5 |
| `RAIN` | 1 | 0.7 | 1 | 0.005 per meter | 0.03 | 1.8 |
| `FOG` | 0.6 | 0.2 | 0 | 0.03 per meter | 0.15 | 2.4 |

`Weather` holds the weather now. It eases its look toward the look of
its kind, so a change of weather takes some seconds. Each frame:

1. `update` moves the look on, scales each light of the scene, and sets
   the scene's fog. A directional light is the sun: it takes the look's
   `sun`. Every other light takes its `sky`. Under cloud the sky gives
   more light than on a clear day, as the cloud spreads the sun's light
   over it, so the ground keeps most of its brightness and loses its
   shadows. As the gloom grows, the sky's light turns from blue to gray.
   The fog's color turns from
   the sky's haze toward gray as the gloom grows. In rain, lightning
   flashes now and then, and lights the sky and the ground for a moment.
   The rain's drops fall, and slide sideways as the camera turns.
2. `cover` draws a layer of cloud over the sky's pixels, at 1,500 meters,
   drifting with the wind. The clouds thicken and darken with the look.
   Where the fog is thick, the sky fades into it.
3. `rain` draws the drops over the window as thin streaks, longer and
   brighter near the eye.

The layer of cloud is found on a grid of `CLOUD_STEP` pixels, and mixed
bilinearly between, so it costs a few samples a pixel.

With `cycle` set, the weather turns on by itself: clear, overcast, rain,
overcast, clear and fog, each for `CYCLE_SECONDS`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.fog import exp2_fog
from core.ordinal import ordinal_valid
from core.scene import Scene
from extensions.vegetation.noise import hash01, value_noise
from lights.light import DIRECTIONAL
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import exp, isinf, sqrt
from units.si import PER_METER, RADIAN, SECOND, Angle, Duration, InverseLength

comptime DROPS = 700
"""How many drops fall in the heaviest rain."""
comptime CLOUD_STEP = 4
"""The step, in pixels, between the samples of the layer of cloud."""
comptime CLOUD_HEIGHT = Float32(1500)
"""How high the layer of cloud is, in meters."""
comptime CLOUD_SCALE = Float32(2500)
"""The meters of the layer one unit of the cloud's noise covers."""
comptime WIND = Vector3(0.006, 0, 0.0025)
"""How fast the clouds drift, in units of their noise a second."""
comptime EASE = Float32(0.4)
"""How fast the look closes on its kind's: each second it closes all but
`exp(-EASE)` of the gap."""
comptime CYCLE_SECONDS = Float32(90)
"""How long each weather of the cycle lasts, in seconds."""
comptime FOG_GRAY = Vector3(150, 155, 160)
"""The color, in sRGB bytes, that the fog turns toward in gloom."""


@fieldwise_init
struct WeatherKind(Equatable, ImplicitlyCopyable, Writable):
    """What the weather is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four kinds there are.

        Returns:
            Whether the value names a kind.
        """
        return ordinal_valid(self.value, 3)


comptime CLEAR = WeatherKind(0)
comptime OVERCAST = WeatherKind(1)
comptime RAIN = WeatherKind(2)
comptime FOG = WeatherKind(3)


@fieldwise_init
struct WeatherLook(ImplicitlyCopyable):
    """What a weather looks like."""

    # The share of the sky the drifting layer of cloud covers, from 0 to 1.
    var clouds: Float32
    # How dark the clouds are, from 0, white, to 1, the gray of a storm.
    var gloom: Float32
    # The share of `DROPS` that fall, from 0 to 1.
    var rain: Float32
    # The fog's density, per meter.
    var fog: Float32
    # The share of the sun's light and of the sky's light that reach the
    # ground.
    var sun: Float32
    var sky: Float32

    def mixed(self, other: WeatherLook, t: Float32) -> WeatherLook:
        """Return this look moved a share of the way to another.

        Args:
            other: The look to move toward.
            t: The share of the way, from 0 to 1.

        Returns:
            Each value mixed linearly.
        """
        return WeatherLook(
            self.clouds + (other.clouds - self.clouds) * t,
            self.gloom + (other.gloom - self.gloom) * t,
            self.rain + (other.rain - self.rain) * t,
            self.fog + (other.fog - self.fog) * t,
            self.sun + (other.sun - self.sun) * t,
            self.sky + (other.sky - self.sky) * t,
        )


def weather_look(kind: WeatherKind) raises -> WeatherLook:
    """Return what a kind of weather looks like.

    Args:
        kind: The weather.

    Returns:
        Its look: see the module's table.

    Raises:
        Error: If the kind is not one.
    """
    if kind == CLEAR:
        return WeatherLook(0.25, 0, 0, 0.0008, 1, 1)
    if kind == OVERCAST:
        return WeatherLook(0.85, 0.35, 0, 0.002, 0.12, 2.5)
    if kind == RAIN:
        return WeatherLook(1, 0.7, 1, 0.005, 0.03, 1.8)
    if kind == FOG:
        return WeatherLook(0.6, 0.2, 0, 0.03, 0.15, 2.4)
    raise Error("A weather must be one of the four")


def next_weather(kind: WeatherKind, step: Int) -> WeatherKind:
    """Return the weather that follows in the cycle.

    Args:
        kind: The weather now. It is not read: the cycle's place is.
        step: How many changes the cycle has made, from zero.

    Returns:
        The weather at the next place of the cycle: clear, overcast,
        rain, overcast, clear and fog, again and again.
    """
    _ = kind
    var order: List[WeatherKind] = [
        CLEAR,
        OVERCAST,
        RAIN,
        OVERCAST,
        CLEAR,
        FOG,
    ]
    return order[(step + 1) % len(order)]


def cloud_cover(u: Float32, v: Float32, clouds: Float32) -> Float32:
    """Return how thick the layer of cloud is at a place on it.

    Args:
        u: Where along the layer's first axis, in units of its noise.
        v: Where along its second axis.
        clouds: The share of the sky the clouds cover, from 0 to 1.

    Returns:
        From 0, clear, to 1, thick: four octaves of value noise, each
        turned against the last so no edge lines up with the lattice, cut
        at the share that leaves `clouds` of the sky covered, and softened
        over half the noise's range.
    """
    var n = value_noise(u * 3, v * 3, 31) * 0.5
    # Each octave turns by about 37 degrees.
    var a = u * 0.8 - v * 0.6
    var b = u * 0.6 + v * 0.8
    n += value_noise(a * 7, b * 7, 32) * 0.27
    var c = a * 0.8 - b * 0.6
    var d = a * 0.6 + b * 0.8
    n += value_noise(c * 15, d * 15, 33) * 0.15
    n += value_noise(d * 31, -c * 31, 34) * 0.08
    var edge = 0.8 - 0.65 * clouds
    return smoothstep(edge - 0.12, edge + 0.22, n)


struct Weather(Movable):
    """The weather now, and the drops of its rain."""

    # The weather it turns toward, and its look now.
    var kind: WeatherKind
    var look: WeatherLook
    # Whether it turns from weather to weather by itself, how long the
    # weather has lasted, in seconds, and how many changes it has made.
    var cycle: Bool
    var lasted: Float32
    var changes: Int
    # The game's clock, in seconds.
    var clock: Float32
    # Each light's intensity and color when the weather began, and the
    # sky's haze.
    var bases: List[Float32]
    var colors: List[Vector3]
    var haze: Vector3
    # How bright a flash of lightning is now, from 0 to 1, and how long
    # until the next one, in seconds.
    var flash: Float32
    var until_flash: Float32
    var flashes: Int
    # Each drop: where it is on the window, from 0 to 1 across and down,
    # and how near the eye, from 0.3 to 1.
    var drops: List[Vector3]
    # The camera's last yaw, in radians, so the drops slide as it turns.
    var yaw: Float32

    def __init__(out self, scene: Scene, kind: WeatherKind) raises:
        """Begin a weather, already in its look.

        Args:
            scene: The scene: its lights' intensities and its fog's color
                now are the weather's clear ones.
            kind: The weather.

        Raises:
            Error: If the kind is not one.
        """
        self.look = weather_look(kind)
        self.kind = kind
        self.cycle = False
        self.lasted = 0
        self.changes = 0
        self.clock = 0
        self.bases = List[Float32]()
        self.colors = List[Vector3]()
        for light in scene.lights:
            self.bases.append(light.intensity)
            self.colors.append(
                Vector3(
                    Float32(light.color.r),
                    Float32(light.color.g),
                    Float32(light.color.b),
                )
            )
        var c = scene.fog.color
        self.haze = Vector3(Float32(c.r), Float32(c.g), Float32(c.b))
        self.flash = 0
        self.until_flash = 4
        self.flashes = 0
        self.drops = List[Vector3]()
        for k in range(DROPS):  # pragma: no branch
            self.drops.append(
                Vector3(
                    hash01(k, 1, 77),
                    hash01(k, 2, 77),
                    0.3 + 0.7 * hash01(k, 3, 77),
                )
            )
        self.yaw = 0

    def set(mut self, kind: WeatherKind) raises:
        """Turn toward a weather. The look eases toward it.

        Args:
            kind: The weather.

        Raises:
            Error: If the kind is not one.
        """
        _ = weather_look(kind)
        self.kind = kind
        self.lasted = 0

    def update(mut self, mut scene: Scene, delta: Duration, yaw: Angle) raises:
        """Run one frame of the weather.

        Args:
            scene: The scene: its lights and its fog are set.
            delta: The frame's time.
            yaw: The camera's yaw now.

        Raises:
            Error: If the time is negative, or the scene has fewer lights
                than when the weather began.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0):
            raise Error("A frame's time must not be negative")
        if len(scene.lights) < len(self.bases):
            raise Error("The weather's scene lost a light")
        self.clock += seconds
        self.lasted += seconds
        if self.cycle and self.lasted >= CYCLE_SECONDS:
            self.set(next_weather(self.kind, self.changes))
            self.changes += 1
        var target = weather_look(self.kind)
        self.look = self.look.mixed(target, 1 - exp(-EASE * seconds))
        # Lightning flashes in heavy rain, every 5 to 15 seconds.
        self.flash *= exp(-10 * seconds)
        if self.look.rain > 0.5:
            self.until_flash -= seconds
            if self.until_flash <= 0:
                self.flash = 1
                self.flashes += 1
                self.until_flash = 5 + 10 * hash01(self.flashes, 0, 78)
        var sky = self.look.sky * (1 + 2.5 * self.flash)
        # Under cloud the sky's light loses its blue.
        var neutral = min(Float32(1), self.look.gloom * 1.4)
        for index in range(len(self.bases)):
            ref light = scene.lights[index]
            var share = sky
            var tint = neutral
            if light.kind == DIRECTIONAL:
                share = self.look.sun
                tint = 0
            light.intensity = self.bases[index] * share
            var base = self.colors[index]
            var gray = (base.x + base.y + base.z) / 3
            var c = base + (Vector3(gray, gray, gray) - base) * tint
            light.color = Color(
                UInt8(Int(c.x + 0.5)),
                UInt8(Int(c.y + 0.5)),
                UInt8(Int(c.z + 0.5)),
            )
        var gray = min(Float32(1), self.look.gloom + self.look.fog * 20)
        var color = self.haze + (FOG_GRAY - self.haze) * gray
        scene.fog = exp2_fog(
            Color(
                UInt8(Int(color.x)), UInt8(Int(color.y)), UInt8(Int(color.z))
            ),
            InverseLength(self.look.fog, PER_METER),
        )
        # The drops fall, nearer ones faster, and slide as the camera
        # turns and as the wind blows.
        var turned = yaw.to(RADIAN) - self.yaw
        self.yaw = yaw.to(RADIAN)
        for ref d in self.drops:  # pragma: no branch
            d.y += seconds * (0.9 + 1.6 * d.z)
            d.x += turned * 0.6 * d.z + seconds * 0.05
            d.x -= Float32(Int(d.x + 8)) - 8
            d.y -= Float32(Int(d.y + 8)) - 8

    def cover(self, mut image: Framebuffer, camera: PerspectiveCamera) raises:
        """Draw the drifting clouds, the fog and the lightning over a
        frame's sky.

        A pixel shows the sky where its depth is infinite.

        Args:
            image: The frame, with its depths.
            camera: The camera that drew it.

        Raises:
            Error: If the frame has no depth for a pixel.
        """
        if len(image.depth) != image.width * image.height:
            raise Error("A frame needs a depth for each pixel")
        var inverse = camera.projection_matrix()
        inverse.multiply(camera.view_matrix())
        inverse.invert()
        var eye = camera.position
        # The directions through three corners of the window: the rest
        # are mixed from them.
        var d00 = inverse.transform_point(Vector3(-1, 1, 1)) - eye
        var d10 = inverse.transform_point(Vector3(1, 1, 1)) - eye
        var d01 = inverse.transform_point(Vector3(-1, -1, 1)) - eye
        var w = image.width
        var h = image.height
        var columns = (w + CLOUD_STEP - 1) // CLOUD_STEP + 1
        var rows = (h + CLOUD_STEP - 1) // CLOUD_STEP + 1
        # Each grid point's cloud, as how much it covers and its shade.
        var cover = List[Float32](length=columns * rows, fill=0)
        var drift_u = WIND.x * self.clock
        var drift_v = WIND.z * self.clock
        for row in range(rows):  # pragma: no branch
            var fy = min(Float32(row * CLOUD_STEP), Float32(h)) / Float32(h)
            for column in range(columns):  # pragma: no branch
                var fx = min(
                    Float32(column * CLOUD_STEP), Float32(w)
                ) / Float32(w)
                var d = d00 + (d10 - d00) * fx + (d01 - d00) * fy
                var up = d.y / d.length()
                if up < 0.02:
                    continue
                var reach = CLOUD_HEIGHT / d.y
                var u = (eye.x + d.x * reach) / CLOUD_SCALE + drift_u
                var v = (eye.z + d.z * reach) / CLOUD_SCALE + drift_v
                cover[row * columns + column] = cloud_cover(
                    u, v, self.look.clouds
                ) * smoothstep(0.02, 0.2, up)
        var shade = 235 - 120 * self.look.gloom
        var veil = (
            max(Float32(0), self.look.clouds - 0.5)
            * 2
            * (0.4 + 0.5 * self.look.gloom)
        )
        var mist = smoothstep(0.001, 0.02, self.look.fog)
        var bright = 1 + 1.5 * self.flash
        var gray = Vector3(shade, shade, shade + 6)
        for y in range(h):  # pragma: no branch
            var gy = Float32(y) / Float32(CLOUD_STEP)
            var r0 = min(Int(gy), rows - 2)
            var ty = gy - Float32(r0)
            for x in range(w):  # pragma: no branch
                var at = y * w + x
                if not isinf(image.depth[at]):
                    continue
                var gx = Float32(x) / Float32(CLOUD_STEP)
                var c0 = min(Int(gx), columns - 2)
                var tx = gx - Float32(c0)
                var a = cover[r0 * columns + c0]
                var b = cover[r0 * columns + c0 + 1]
                var c = cover[(r0 + 1) * columns + c0]
                var e = cover[(r0 + 1) * columns + c0 + 1]
                var top = a + (b - a) * tx
                var bottom = c + (e - c) * tx
                var cloud = top + (bottom - top) * ty
                var alpha = min(Float32(1), veil + cloud * (1 - veil))
                var p = at * 4
                var sky = Vector3(
                    Float32(image.pixels[p]),
                    Float32(image.pixels[p + 1]),
                    Float32(image.pixels[p + 2]),
                )
                # The underside of a thick cloud is darker than its edge.
                var tone = gray * (1 - 0.18 * cloud * self.look.gloom)
                var seen = sky + (tone - sky) * alpha
                var fog = self.haze + (FOG_GRAY - self.haze) * self.look.gloom
                seen = seen + (fog - seen) * mist
                seen = seen * bright
                image.pixels[p] = UInt8(Int(min(Float32(255), seen.x)))
                image.pixels[p + 1] = UInt8(Int(min(Float32(255), seen.y)))
                image.pixels[p + 2] = UInt8(Int(min(Float32(255), seen.z)))

    def rain(self, mut window: Framebuffer):
        """Draw the falling drops over a window as thin streaks.

        Args:
            window: The window's frame.
        """
        var count = Int(Float32(DROPS) * self.look.rain)
        var long = Float32(window.height) * 0.05
        for k in range(count):
            ref d = self.drops[k]
            var length = Int(long * d.z)
            var x0 = Float32(window.width) * d.x
            var y0 = Float32(window.height) * d.y
            var alpha = 0.12 + 0.2 * d.z
            for s in range(length):
                # The streak leans a little with the wind, and stops at the
                # window's right edge. A drop starts on the window, so only
                # its foot can leave it at the bottom.
                var x = min(Int(x0 + Float32(s) * 0.12), window.width - 1)
                var y = Int(y0) + s
                if y >= window.height:
                    continue
                var p = (y * window.width + x) * 4
                for c in range(3):
                    var under = Float32(window.pixels[p + c])
                    window.pixels[p + c] = UInt8(
                        Int(under + (215 - under) * alpha)
                    )
